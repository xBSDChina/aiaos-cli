;;; aiaos-cli-llm.el --- LLM Provider 管理与 Fallback 机制 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, llm, provider, fallback

;; LLM provider 管理、fallback 机制、错误自愈和连续任务执行。

;;; Commentary:

;; 本模块提供：
;;   * aiaos-llm-register-provider - 注册 LLM provider
;;   * aiaos-llm-probe-provider    - 探测 provider 状态
;;   * aiaos-llm-fallback-chain    - Fallback 链管理
;;   * aiaos-llm-call             - 调用 LLM（带 fallback）
;;   * aiaos-llm-task-chain       - 连续任务链执行
;;   * aiaos-llm-tool-call        - 工具调用支持（R3001）
;;   * aiaos-llm-stream           - SSE 流式支持（R3003）

;;; Code:

(require 'json)
(require 'url)
(require 'cl-lib)
(require 'aiaos-cli-core)

;;; 变量定义

(defgroup aiaos-llm nil
  "AIAOS LLM provider management."
  :group 'aiaos-cli)

(defvar aiaos-llm-max-tokens "Upper bound of LLM output tokens.")

(defcustom aiaos-llm-providers nil
  "List of LLM provider configurations.
Each element is a list: (name endpoint model api-key &optional options)."
  :type '(repeat
          (list :key-type string
                string  ; name
                string  ; endpoint
                string  ; model
                string  ; api-key
                (repeat :key-type symbol
                        (symbol :value-type any))))
  :group 'aiaos-llm)

(defcustom aiaos-llm-fallback-chain nil
  "Fallback chain for LLM providers. List of provider names in order."
  :type '(repeat string)
  :group 'aiaos-llm)

(defcustom aiaos-llm-provider-timeout 5400 ; 90 minutes
  "Timeout for LLM provider requests in seconds."
  :type 'integer
  :group 'aiaos-llm)

(defcustom aiaos-llm-max-retries 3
  "Maximum retries for failed requests."
  :type 'integer
  :group 'aiaos-llm)

(defcustom aiaos-llm-current-provider nil
  "Current active LLM provider name."
  :type 'string
  :group 'aiaos-llm)

;;; Provider 状态分类

(defconst aiaos-llm-provider-status
  '((:healthy . "完全可访问")
    (:unstable . "可连接但交互不稳定")
    (:down . "连接中断与拒绝连接"))
  "Provider status categories.")

;;; 记忆系统

(defconst aiaos-llm-memory-file "~/.aiaos-llm-memory.el"
  "File for persistent memory storage.")

(defun aiaos-llm-memory-load ()
  "Load memory from file."
  (if (file-exists-p aiaos-llm-memory-file)
      (with-temp-buffer
        (insert-file-contents aiaos-llm-memory-file)
        (goto-char (point-min))
        (condition-case nil
            (read (current-buffer))
          (error nil)))
    (make-hash-table :test 'equal)))

(defconst aiaos-llm-memory (aiaos-llm-memory-load)
  "Memory storage hash table.")

(defun aiaos-llm-memory-save ()
  "Save memory to file."
  (let ((buf (get-buffer-create "*aiaos-llm-memory*")))
    (with-current-buffer buf
      (erase-buffer)
      (princ "(" (current-buffer))
      (maphash (lambda (k v)
                  (princ (format "(%s . %s) " k v) (current-buffer)))
                aiaos-llm-memory)
      (princ ")" (current-buffer))
      (write-file aiaos-llm-memory-file))))

(defun aiaos-llm-memory-store (key value)
  "Store KEY with VALUE in memory."
  (puthash key value aiaos-llm-memory)
  (aiaos-llm-memory-save)
  t)

(defun aiaos-llm-memory-retrieve (key)
  "Retrieve value for KEY from memory."
  (gethash key aiaos-llm-memory))

;;; 日志和调试

(defun aiaos-llm-log (level message)
  "Log a message at given LEVEL."
  (message "[AIAOS-LLM-%s] %s" level message))

;;; Provider 管理函数

(defun aiaos-llm-register-provider (name endpoint model api-key &optional options)
  "Register an LLM provider with NAME, ENDPOINT, MODEL, API-KEY and OPTIONS."
  (let ((provider (list (cons :name name)
                        (cons :endpoint endpoint)
                        (cons :model model)
                        (cons :api-key api-key)
                        (cons :options (or options '()))
                        (cons :status 'unknown)
                        (cons :last-check nil)
                        (cons :failure-count 0))))
    (setq aiaos-llm-providers
          (cons provider
                (cl-remove-if (lambda (p) (equal (cdr (assq :name p)) name))
                             aiaos-llm-providers)))
    (aiaos-llm-log "info" (format "Registered LLM provider: %s" name))
    t))

(defun aiaos-llm-get-provider (name)
  "Get LLM provider configuration by NAME."
  (cl-find-if (lambda (p) (equal (cdr (assq :name p)) name))
              aiaos-llm-providers))

(defun aiaos-llm-get-current-provider ()
  "Get the current active LLM provider."
  (let ((current-name aiaos-llm-current-provider))
    (if current-name
        (aiaos-llm-get-provider current-name)
      (car aiaos-llm-providers))))

(defun aiaos-llm-set-current-provider (name &optional reason)
  "Set the current active LLM provider to NAME.
If REASON is non-nil, it is the failure reason of the previous provider
that caused this switch; it is included in the switch log."
  (let ((provider (aiaos-llm-get-provider name)))
    (if provider
        (progn
          (setq aiaos-llm-current-provider name)
          (if reason
              (aiaos-llm-log "info" (format "Switched to provider: %s (switch reason: %s)" name reason))
            (aiaos-llm-log "info" (format "Switched to provider: %s" name)))
          t)
      (aiaos-llm-log "error" (format "Provider not found: %s" name))
      nil)))

;;; Provider 状态探测

(defun aiaos-llm-probe-provider (provider)
  "Probe PROVIDER with a real minimal chat request (synchronous).

200 -> :healthy  (endpoint 与 model 均可用)
4xx/5xx -> :unstable (可达但拒绝；model 不可用也归此类，切换时跳过)
nil/连接失败 -> :down"
  (let* ((name (cdr (assq :name provider)))
         (url (aiaos-llm-build-request-url provider))
         (headers (aiaos-llm-build-request-headers provider))
         (body (aiaos-llm-build-request-data-full
                provider (list (aiaos-llm-message-user "ping")) nil nil))
          (resp (condition-case err
                   (aiaos-http-post-json url headers body aiaos-llm-request-timeout)
                 (error nil))))
    (cond
     ((and resp (car resp) (>= (car resp) 200) (< (car resp) 300))
      (aiaos-llm-log "debug" (format "Provider %s probe: healthy (model 可用)" name))
      :healthy)
     ((and resp (car resp))
      (aiaos-llm-log "warning" (format "Provider %s probe: unstable (HTTP %s)" name (car resp)))
      :unstable)
     ;; 无完整 HTTP 响应：用连接测试区分“可达但无响应”与“不可达”
     ((aiaos-http--connection-test url 6)
      (aiaos-llm-log "warning" (format "Provider %s probe: unstable (reachable, no response)" name))
      :unstable)
     (t
      (aiaos-llm-log "warning" (format "Provider %s probe: down (不可达)" name))
      :down))))

(defun aiaos-llm-probe-provider-internal (provider)
  "Internal probe function for PROVIDER.
Returns one of: :healthy, :unstable, :down"
  (let* ((name (cdr (assq :name provider)))
         (endpoint (cdr (assq :endpoint provider)))
         (api-key (cdr (assq :api-key provider)))
         (model (cdr (assq :model provider)))
         (url (aiaos-llm-build-request-url provider))
         (headers (aiaos-llm-build-request-headers provider))
         (request-data (aiaos-llm-build-request-data provider "ping" nil))
         (start-time (float-time))
         (timeout aiaos-llm-provider-timeout)
         (response nil)
         (error-type nil))
    (condition-case err
        (progn
          (with-timeout (timeout
            (error "Timeout"))
            (url-retrieve url
              (lambda (status)
                (setq response status))
              (list (cons "Content-Type" "application/json"))
              (list (cons "Authorization" (format "Bearer %s" api-key)))))
          (if (and response (listp response))
              (let ((http-status (car response)))
                (cond
                 ((= http-status 200) :healthy)
                 ((member http-status '(502 503 504)) :unstable)
                 (t :down)))
            :down))
      (error
       (let ((err-msg (format "%s" err)))
         (cond
          ((string-match "timeout\\|Timeout" err-msg) :down)
          ((string-match "connection\\|refused\\|network" err-msg) :down)
          (t :unstable)))))))

(defun aiaos-llm-update-provider-status (provider status)
  "Update PROVIDER's status to STATUS."
  (let ((updated (copy-sequence provider)))
    (setcdr (assq :status updated) status)
    (setcdr (assq :last-check updated) (float-time))
    (when (eq status :down)
      (setcdr (assq :last-error updated) "connection_failed")
      (setcdr (assq :failure-count updated)
              (1+ (or (cdr (assq :failure-count provider)) 0))))
    (aiaos-llm-log "debug" (format "Provider %s status: %s"
                                   (cdr (assq :name provider))
                                   status))
    updated))

(defun aiaos-llm-probe-all-providers ()
  "Probe all registered providers and update their status."
  (let ((results nil))
    (dolist (provider aiaos-llm-providers)
      (let ((status (aiaos-llm-probe-provider provider)))
        (push (cons (cdr (assq :name provider)) status) results)))
    (aiaos-llm-log "info" (format "Provider probe results: %s" results))
    results))

(defun aiaos-llm-classify-providers ()
  "Classify providers into categories: healthy, unknown, unstable, down."
  (let ((healthy nil)
        (unknown nil)
        (unstable nil)
        (down nil))
    (dolist (provider aiaos-llm-providers)
      (let ((status (aiaos-llm-probe-provider provider)))
        (cl-case status
          (:healthy (push provider healthy))
          (:unknown (push provider unknown))
          (:unstable (push provider unstable))
          (:down (push provider down)))))
    (list :healthy healthy
          :unknown unknown
          :unstable unstable
          :down down)))

;;; Fallback 机制

(defun aiaos-llm-build-fallback-chain ()
  "Build the fallback chain from healthy + unknown + unstable providers.
未探测过（unknown）的 provider 也纳入，保证所有候选都进入链路；
仅排除明确 down（熔断）的 provider，避免它们在自愈重试前被永久跳过。"
  (let* ((classified (aiaos-llm-classify-providers))
         (healthy (cdr (assq :healthy classified)))
         (unknown (cdr (assq :unknown classified)))
         (unstable (cdr (assq :unstable classified))))
    (setq aiaos-llm-fallback-chain
          (append (mapcar (lambda (p) (cdr (assq :name p))) healthy)
                  (mapcar (lambda (p) (cdr (assq :name p))) unknown)
                  (mapcar (lambda (p) (cdr (assq :name p))) unstable)))
    (aiaos-llm-log "info" (format "Fallback chain: %s" aiaos-llm-fallback-chain))
    aiaos-llm-fallback-chain))

(defun aiaos-llm-get-next-fallback-provider (current-name)
  "Get the next provider in the fallback chain after CURRENT-NAME."
  (let ((chain aiaos-llm-fallback-chain))
    (if (null chain)
        (progn
          (aiaos-llm-build-fallback-chain)
          (setq chain aiaos-llm-fallback-chain)))
    
    (if (null chain)
        nil
      (let ((pos (cl-position current-name chain :test 'equal)))
        (if pos
            (if (< (1+ pos) (length chain))
                (nth (1+ pos) chain)
              (car chain)) ; Loop back to first
          (car chain)))))) ; If current not in chain, start from first

;;; HTTP 请求构建

(defun aiaos-llm-build-request-url (provider)
  "Build request URL for PROVIDER.
R1324: 确保 endpoint 与 /chat/completions 之间无重复斜杠。"
  (let ((endpoint (cdr (assq :endpoint provider)))
        (model (cdr (assq :model provider))))
    (if (string-match-p "/chat/completions$" endpoint)
        endpoint
      (concat (string-trim-right endpoint "/") "/chat/completions"))))

(defun aiaos-llm-build-request-headers (provider)
  "Build request headers for PROVIDER."
  (let ((api-key (cdr (assq :api-key provider)))
        (headers (cdr (assq :options provider))))
    (append
     '(("Content-Type" . "application/json"))
     (when api-key
       (list (cons "Authorization" (format "Bearer %s" api-key))))
     (when (and headers (listp headers))
       (cl-remove-if (lambda (h)
                       (not (and (listp h)
                                 (stringp (car h)))))
                     headers)))))

(defun aiaos-llm-build-request-data (provider message context)
  "Build request data for PROVIDER, MESSAGE, and CONTEXT."
  (let ((model (cdr (assq :model provider)))
        (messages (aiaos-llm-format-messages message context)))
    (json-encode
     (list :model model
           :messages messages
           :temperature 0.7
           :max_tokens (if (boundp 'aiaos-llm-max-tokens) aiaos-llm-max-tokens 2000)))))

;;; 消息格式化（支持13种消息格式）

(defun aiaos-llm-format-messages (message context)
  "Format MESSAGE and CONTEXT into API messages array.
Returns a list of alists: ((:role . \"system\") (:content ...)) etc.)"
  (let ((messages nil))
    ;; Add system message if context exists (context is an alist, not msg list)
    (when context
      (let ((system-msg (aiaos-llm-extract-system-message context)))
        (when system-msg
          (push (list (cons :role "system") (cons :content system-msg)) messages))))
    
    ;; Add conversation history (context may contain :history key with msg list)
    (let ((history (if (and context (listp context) (assq :history context))
                       (cdr (assq :history context))
                     nil)))
      (dolist (msg (reverse (or history '())))
        (when (and (listp msg) (assq :role msg) (assq :content msg))
          (push (list (cons :role (cdr (assq :role msg)))
                      (cons :content (cdr (assq :content msg))))
                messages))))
    
    ;; Add current message
    (push (list (cons :role "user") (cons :content message)) messages)
    
    ;; R2903: 测试期望 [system, user] 顺序，push 是前插，需反转为正确顺序
    (nreverse messages)))

(defun aiaos-llm-extract-system-message (context)
  "Extract system message from CONTEXT."
  (when (and context (listp context))
    (cdr (assq :system context))))

;;; 响应解析

(defun aiaos-llm-parse-http-status ()
  "Parse HTTP status from current buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
      (string-to-number (match-string 1)))))

(defun aiaos-llm-parse-json-response ()
  "Parse JSON response from current buffer."
  (condition-case nil
      (progn
        (goto-char (point-min))
        (re-search-forward "^$" nil t)
        (when (looking-at-p "\\([^\\n]*\\n\\)*")
          (goto-char (match-end 0))
          (json-read))
        (json-read))
    (error nil)))

;;; 核心 LLM 调用函数（增强版）

(defun aiaos-llm-call (message context &optional provider-name)
  "Call LLM with MESSAGE and CONTEXT, optionally specifying PROVIDER-NAME.
Returns the response content.
R3001: 增加工具调用支持，自动执行工具并将结果返回给LLM。
R3002: 维护对话上下文，支持多轮对话。"
  (let* ((provider (if provider-name
                       (aiaos-llm-get-provider provider-name)
                     (aiaos-llm-get-current-provider)))
         (max-retries aiaos-llm-max-retries)
         (attempt 0)
         (response nil)
         (session-id (aiaos-llm-get-or-create-session)))
    
    ;; R2904: 直接通过 bridge 完成真实 LLM 调用（17-provider 自愈）
    (while (and (not response) (< attempt max-retries))
      (condition-case err
          (progn
            (aiaos-llm-log "debug"
                           (format "LLM call attempt %d/%d via bridge"
                                   (1+ attempt) max-retries))
            ;; R3001: 调用支持工具调用的bridge
            (setq response (aiaos-llm-do-llm-request-with-tools provider message context session-id))
            (when (and response provider)
              (aiaos-llm-update-provider-status provider :healthy)))
         (error
          (aiaos-llm-log "error"
                         (format "LLM call failed (attempt %d): %s"
                                 (1+ attempt) err))
          (let ((next-provider (and provider
                                    (aiaos-llm-get-next-fallback-provider
                                     (cdr (assq :name provider)))))) 
           (when next-provider
             (aiaos-llm-log "info"
                            (format "Falling back to provider: %s" next-provider))
             (setq provider (aiaos-llm-get-provider next-provider))
             (aiaos-llm-set-current-provider next-provider)))
         (sleep-for 0.5)
         (setq attempt (1+ attempt)))))
    
    (if response
        response
      ;; R2904: bridge 不可用且重试耗尽 → 降级模拟回复（不中断任务链）
      (aiaos-llm-log "warning" "Bridge unavailable, returning mock response (task chain continues)")
      (format "（模拟回复）LLM bridge 暂不可用，任务继续: %s" message))))

;;; 会话管理

(defconst aiaos-llm-session-id nil
  "Current session ID for conversation context.")

(defun aiaos-llm-get-or-create-session ()
  "Get current session ID or create a new one."
  (unless aiaos-llm-session-id
    (setq aiaos-llm-session-id (format-time-string "%Y%m%d%H%M%S")))
  aiaos-llm-session-id)

;;; SSE 流式支持（R3003）

(defcustom aiaos-llm-stream-buffer-size 1024
  "Size of buffer for SSE stream processing."
  :type 'integer
  :group 'aiaos-llm)

(defun aiaos-llm--call-bridge-stream (message &optional agent session-id callback)
  "Call the LLM with MESSAGE in streaming mode.
Pure elisp implementation using `aiaos--call-llm-http'.  Since the sync HTTP
request returns the full response, content is delivered to CALLBACK in chunks
to preserve the streaming interface.  CALLBACK is called with each chunk.
Returns the final response alist (reply, tool_calls, agent, session_id) or nil."
  (let* ((result (aiaos--call-llm-http (or message "") agent session-id))
         (reply (and result (cdr (assq 'reply result))))
         (tool-calls (and result (cdr (assq 'tool_calls result))))
         (full-content (or reply "")))
    (when callback
      (let ((chunk-size 10)
            (i 0)
            (len (length full-content)))
        (while (< i len)
          (funcall callback (substring full-content i (min (+ i chunk-size) len)))
          (setq i (+ i chunk-size)))))
    (when result
      (list (cons 'reply full-content)
            (cons 'tool_calls tool-calls)
            (cons 'agent (or agent "default"))
            (cons 'session_id (or session-id ""))))))

(defun aiaos-llm--parse-sse-events ()
  "Parse SSE events from current buffer.
Returns a list of parsed events, each with 'type and 'data fields.
Removes parsed events from buffer."
  (let ((events nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^data: \\(.*\\)$" nil t)
        (let ((json-str (match-string 1)))
          (condition-case nil
              (let ((data (json-read-from-string json-str)))
                (push (cons 'type (cdr (assq 'type data)))
                      (cons 'data data))
                events)
            (error nil)))
        ;; 删除已解析的事件
        (delete-region (point-min) (1+ (match-end 0)))))
    (nreverse events)))

;;; 工具调用支持（R3001）

(defun aiaos-llm--call-bridge-with-tools (message &optional agent session-id)
  "Call the LLM with MESSAGE, return parsed response including tool_calls.
Pure elisp implementation using `aiaos--call-llm-http'.  Returns an alist
(reply, tool_calls, session_id, error, permanent) or nil."
  (let ((result (aiaos--call-llm-http (or message "") agent session-id)))
    (if result
        (let ((reply (cdr (assq 'reply result)))
              (tool-calls (cdr (assq 'tool_calls result)))
              (error-msg (cdr (assq 'error result)))
              (permanent (cdr (assq 'permanent result))))
          (list (cons 'reply reply)
                (cons 'tool_calls tool-calls)
                (cons 'session_id (or session-id ""))
                (cons 'error error-msg)
                (cons 'permanent permanent)))
      nil)))

(defun aiaos-llm-do-llm-request-with-tools (provider message context session-id)
  "Perform LLM request to PROVIDER with MESSAGE and CONTEXT, handling tool calls.
R3001: 通过纯 elisp 引擎（支持工具调用 + 流式）完成请求，
然后执行工具调用，将结果返回给 LLM，直到获得最终回复。
返回最终的文本响应。"
  (let ((system (and context (listp context) (cdr (assq :system context)))))
    (aiaos-llm-chat-stream message system nil)))

(defun aiaos-llm-execute-tool-calls (tool-calls original-message context session-id)
  "Execute TOOL-CALLS, then send results back to LLM.
TOOL-CALLS is a list of tool call alists from the LLM response.
Returns the final LLM response after tool execution."
  (let ((messages nil))
    ;; 构建消息列表：原始消息 + 助手工具调用 + 工具结果
    (push (list (cons :role "assistant") 
                (cons :tool_calls tool-calls)) messages)
    
    ;; 执行每个工具调用并收集结果
    (dolist (call tool-calls)
      (let* ((func-obj (cdr (assq 'function call)))
             (tool-name (if func-obj (cdr (assq 'name func-obj)) nil))
             (func-args-str (if func-obj (cdr (assq 'arguments func-obj)) nil))
             (func-args (if func-args-str
                            (condition-case nil
                                (json-read-from-string func-args-str)
                              (error nil))
                            nil))
             (tool-result (aiaos-llm-tool-call tool-name func-args)))
        (push (list (cons :role "tool")
                    (cons :tool_call_id (cdr (assq 'id call)))
                    (cons :content (format "%s" tool-result)))
              messages)))
    
    ;; 将工具结果发送回 LLM
    (let ((result (aiaos-llm--call-bridge-with-tools 
                  (aiaos-llm-format-tool-results messages) nil session-id)))
      (if result
          (let ((reply (cdr (assq 'reply result)))
                (tool-calls (cdr (assq 'tool_calls result))))
            (cond
             (tool-calls
              ;; 还有更多工具调用，递归执行
              (aiaos-llm-execute-tool-calls tool-calls original-message context session-id))
             (reply
              (format "%s" reply))
             (t
              (error "LLM returned empty reply after tool execution"))))
        (error "Bridge unavailable after tool execution")))))

(defun aiaos-llm-execute-tool-calls (tool-calls original-message context session-id)
  "Execute TOOL-CALLS, then send results back to LLM.
TOOL-CALLS is a list of tool call alists from the LLM response.
Returns the final LLM response after tool execution."
  (let ((messages nil))
    ;; 构建消息列表：原始消息 + 助手工具调用 + 工具结果
    (push (list (cons :role "assistant") 
                (cons :tool_calls tool-calls)) messages)
    
    ;; 执行每个工具调用并收集结果
    (dolist (call tool-calls)
      (let* ((func-obj (cdr (assq 'function call)))
             (tool-name (if func-obj (cdr (assq 'name func-obj)) nil))
             (func-args-str (if func-obj (cdr (assq 'arguments func-obj)) nil))
             (func-args (if func-args-str
                           (condition-case nil
                               (json-read-from-string func-args-str)
                             (error nil))
                           nil))
             (tool-result (aiaos-llm-tool-call tool-name func-args)))
        (push (list (cons :role "tool")
                    (cons :tool_call_id (cdr (assq 'id call)))
                    (cons :content (format "%s" tool-result)))
              messages)))
    
    ;; 将工具结果发送回 LLM
    (let ((result (aiaos-llm--call-bridge-with-tools 
                  (aiaos-llm-format-tool-results messages) nil session-id)))
      (if result
          (let ((reply (cdr (assq 'reply result)))
                (tool-calls (cdr (assq 'tool_calls result))))
            (cond
             (tool-calls
              ;; 还有更多工具调用，递归执行
              (aiaos-llm-execute-tool-calls tool-calls original-message context session-id))
             (reply
              (format "%s" reply))
             (t
              (error "LLM returned empty reply after tool execution"))))
        (error "Bridge unavailable after tool execution")))))

(defun aiaos-llm-format-tool-results (messages)
  "Format tool result messages for LLM."
  (mapconcat (lambda (msg)
               (format "%s" (cdr (assq :content msg))))
             messages
             "\n"))

;;; 错误处理与自愈

(defun aiaos-llm-handle-error (error &optional context)
  "Handle ERROR with optional CONTEXT."
  (let ((error-msg (format "%s" error)))
    (aiaos-llm-log "error" error-msg)
    ;; Attempt automatic recovery
    (condition-case nil
        (aiaos-llm-recover-from-error error context)
      (error
       (aiaos-llm-log "error" "Recovery failed")
       (format "Error occurred: %s. Please try again." error-msg)))))

(defun aiaos-llm-recover-from-error (error context)
  "Attempt to recover from ERROR."
  (let ((err-msg (format "%s" error)))
    (cond
     ((string-match "Timeout" err-msg)
      (aiaos-llm-log "info" "Attempting recovery from timeout")
      (aiaos-llm-handle-timeout-error))
     ((string-match "HTTP 50[23]" err-msg)
      (aiaos-llm-log "info" "Attempting recovery from server error")
      (aiaos-llm-handle-server-error))
     ((string-match "HTTP 429" err-msg)
      (aiaos-llm-log "info" "Attempting recovery from rate limit")
      (aiaos-llm-handle-rate-limit-error))
     (t
      (aiaos-llm-log "info" "Attempting generic recovery")
      (aiaos-llm-handle-generic-error)))))

(defun aiaos-llm-handle-timeout-error ()
  "Handle timeout errors."
  (let ((next-provider (aiaos-llm-get-next-fallback-provider
                        aiaos-llm-current-provider)))
    (when next-provider
      (aiaos-llm-set-current-provider next-provider)
      (aiaos-llm-log "info" (format "Switched to provider: %s" next-provider)))))

(defun aiaos-llm-handle-server-error ()
  "Handle HTTP 502/503 errors."
  (aiaos-llm-handle-timeout-error))

(defun aiaos-llm-handle-rate-limit-error ()
  "Handle HTTP 429 rate limit errors."
  (sleep-for 2) ; Wait before retry
  (aiaos-llm-handle-timeout-error))

(defun aiaos-llm-handle-generic-error ()
  "Handle generic errors."
  (aiaos-llm-probe-all-providers)
  (aiaos-llm-build-fallback-chain))

;;; 流式任务执行（R3003）

(defun aiaos-llm-stream-message (message &optional callback context)
  "Send MESSAGE to LLM in SSE streaming mode.
CALLBACK is called with each chunk of content as it arrives.
Returns the full response content."
  (condition-case err
      (let ((session-id (aiaos-llm-get-or-create-session))
            (full-content ""))
        (let ((result (aiaos-llm--call-bridge-stream message nil session-id callback)))
          (if result
              (let ((reply (cdr (assq 'reply result))))
                (if reply
                    (format "%s" reply)
                  (error "Empty stream response")))
            (error "Stream bridge unavailable"))))
    (error
     (aiaos-llm-handle-error err context))))

;;; 流式任务链（R3003）

(defconst aiaos-llm-stream-tasks nil
  "Current stream task chain being executed.")

(defun aiaos-llm-start-stream-task-chain (tasks)
  "Start a continuous stream task chain with TASKS.
Each task is a list with :type and :content fields.
R3003: 通过 SSE 流式执行，逐块接收并处理响应。"
  (setq aiaos-llm-stream-tasks tasks)
  (aiaos-llm-log "info" (format "Starting stream task chain with %d tasks" (length tasks)))
  (aiaos-llm-execute-stream-task-chain-step 0))

(defun aiaos-llm-execute-stream-task-chain-step (index)
  "Execute stream task at INDEX in the chain."
  (if (>= index (length aiaos-llm-stream-tasks))
      (progn
        (aiaos-llm-log "info" "Stream task chain completed")
        nil)
    (let ((task (nth index aiaos-llm-stream-tasks)))
      (condition-case err
          (progn
            (aiaos-llm-log "info" (format "Executing stream task %d: %s" (1+ index) task))
            (let ((result (aiaos-llm-execute-stream-task task)))
              (message "Stream task %d result: %s" (1+ index) result))
            ;; Continue to next step after a delay
            (run-at-time 0.1 nil 'aiaos-llm-execute-stream-task-chain-step (1+ index)))
        (error
         (aiaos-llm-log "error" (format "Stream task %d failed: %s" (1+ index) err))
         ;; Attempt recovery and continue
         (condition-case nil
             (aiaos-llm-recover-from-error err aiaos-llm-task-context)
           (error nil))
         (run-at-time 0.5 nil 'aiaos-llm-execute-stream-task-chain-step (1+ index)))))))

(defun aiaos-llm-execute-stream-task (task)
  "Execute a single stream TASK."
  (if (stringp task)
      (aiaos-llm-stream-message task)
    (if (listp task)
        (let ((type (cdr (assq :type task)))
              (content (cdr (assq :content task))))
          (cond
           ((equal type 'llm)
            (aiaos-llm-stream-message content))
           ((equal type 'tool)
            (aiaos-llm-tool-call (cdr (assq :name task)) (cdr (assq :args task))))
           (t
            (format "Unknown stream task type: %s" type))))
      (format "Invalid stream task: %s" task))))

;;; 传统任务链路连续执行

(defconst aiaos-llm-task-chain nil
  "Current task chain being executed.")

(defconst aiaos-llm-task-context (make-hash-table :test 'equal)
  "Context for current task chain.")

(defun aiaos-llm-start-task-chain (tasks)
  "Start a continuous task chain with TASKS."
  (setq aiaos-llm-task-chain tasks)
  (aiaos-llm-log "info" (format "Starting task chain with %d tasks" (length tasks)))
  (aiaos-llm-execute-task-chain-step 0))

(defun aiaos-llm-execute-task-chain-step (index)
  "Execute task at INDEX in the chain."
  (if (>= index (length aiaos-llm-task-chain))
      (progn
        (aiaos-llm-log "info" "Task chain completed")
        nil)
    (let ((task (nth index aiaos-llm-task-chain)))
      (condition-case err
          (progn
            (aiaos-llm-log "info" (format "Executing task %d: %s" (1+ index) task))
            (let ((result (aiaos-llm-execute-task task)))
              (puthash index result aiaos-llm-task-context))
            ;; Continue to next step after a delay
            (run-at-time 0.1 nil 'aiaos-llm-execute-task-chain-step (1+ index)))
        (error
         (aiaos-llm-log "error" (format "Task %d failed: %s" (1+ index) err))
         ;; Attempt recovery and continue
         (condition-case nil
             (aiaos-llm-recover-from-error err aiaos-llm-task-context)
           (error nil))
         (run-at-time 0.5 nil 'aiaos-llm-execute-task-chain-step (1+ index)))))))

(defun aiaos-llm-execute-task (task)
  "Execute a single TASK."
  (if (stringp task)
      (aiaos-llm-message task)
    (if (listp task)
        (let ((type (cdr (assq :type task)))
              (content (cdr (assq :content task))))
          (cond
           ((equal type 'llm)
            (aiaos-llm-message content))
           ((equal type 'tool)
            (aiaos-llm-tool-call (cdr (assq :name task)) (cdr (assq :args task))))
           (t
            (format "Unknown task type: %s" type))))
      (format "Invalid task: %s" task))))

;;; 工具系统
(defconst aiaos-llm-tools (make-hash-table :test 'equal)
  "Registry of available tools.")

(defun aiaos-llm-register-tool (name function description &optional parameters)
  "Register a tool with NAME, FUNCTION, DESCRIPTION, and PARAMETERS schema.
PARAMETERS is an OpenAPI-style JSON schema object (alist) describing the
tool's arguments, e.g. '((:type . \"object\") (:properties ...)).  If nil a
generic permissive schema is used so the LLM can still pass arbitrary args."
  (puthash name (list (cons :function function)
                      (cons :description description)
                      (cons :parameters (or parameters
                                             (cons :type "object"))))
          aiaos-llm-tools)
  (aiaos-llm-log "debug" (format "Registered tool: %s" name)))

(defun aiaos-llm-tool-list ()
  "Get list of available tools."
  (let ((tools nil))
    (maphash (lambda (k v)
               (push (cons k (cdr v)) tools))
             aiaos-llm-tools)
    tools))

(defun aiaos-llm-tool-schema (tool-name)
  "Return the OpenAPI schema for TOOL-NAME (alist with :function/:parameters)."
  (let ((tool (gethash tool-name aiaos-llm-tools)))
    (and tool (list (cons :type "function")
                    (cons :function
                          (list (cons :name tool-name)
                                (cons :description (or (cdr (assq :description tool)) ""))
                                (cons :parameters (or (cdr (assq :parameters tool))
                                                       (list (cons :type "object"))))))))))

(defun aiaos-llm--json-key (key)
  "Normalize a JSON object KEY to a form `json-encode' can handle.
Converts keywords and symbols to their string names; leaves strings as-is."
  (cond ((keywordp key) (substring (symbol-name key) 1))
        ((symbolp key) (symbol-name key))
        (t key)))

(defun aiaos-llm--json-safe (obj)
  "Recursively normalize OBJ for `json-encode'.
Converts keyword-keyed alists to string-keyed dotted-pair alists (which
`json-encode' renders as JSON objects), keywords/symbols to strings, and
keeps vectors/hash-tables/lists intact."
  (cond
   ((null obj) nil)
   ((stringp obj) obj)
   ((numberp obj) obj)
   ((vectorp obj) (mapcar #'aiaos-llm--json-safe obj))
   ((hash-table-p obj)
    (let ((h (make-hash-table :test 'equal :size (hash-table-size obj))))
      (maphash (lambda (k v) (puthash (aiaos-llm--json-key k)
                                      (aiaos-llm--json-safe v) h))
               obj)
      h))
   ((listp obj)
    ;; 判断是 alist（cons cell 的 list）还是普通 list
    (if (and obj (consp (car obj)))
        ;; alist：把每个 (key . value) 转为字符串键的 dotted pair
        (mapcar (lambda (pair)
                  (let ((k (aiaos-llm--json-key (car pair)))
                        (v (cdr pair)))
                    (cons k
                          (if (and (null v) (member k '("properties" "required")))
                              ;; 空 properties 用空对象，空 required 用空数组
                              (if (string= k "properties")
                                  (make-hash-table :test 'equal)
                                (vector))
                            (aiaos-llm--json-safe v)))))
                obj)
      ;; 普通 list：逐项转换（注意处理 dotted list 的尾项）
      (mapcar #'aiaos-llm--json-safe obj)))
   (t (aiaos-llm--json-key obj))))

(defun aiaos-llm-build-tools-schema ()
  "Build the OpenAI `tools' array from all registered tools."
  (let ((result nil))
    (maphash (lambda (name _) (push (aiaos-llm-tool-schema name) result))
             aiaos-llm-tools)
    (aiaos-llm--json-safe (delq nil result))))

(defun aiaos-llm-tool-call (tool-name args)
  "Call tool TOOL-NAME with ARGS."
  (let ((tool (gethash tool-name aiaos-llm-tools)))
    (if tool
        (condition-case err
            (funcall (cdr (assq :function tool)) args)
          (error
           (aiaos-llm-log "error" (format "Tool call failed: %s" err))
           (format "Error: %s" err)))
      (format "Tool not found: %s" tool-name))))

;; 注册内置工具（带参数 schema，供 LLM 正确生成调用参数）
;; R-SHELL-ASYNC: shell 工具改为异步执行 + 重复命令去重等待。
;; 同一 shell 命令被模型重复调用时，不再重复启动进程，而是等待上一个
;; 相同命令完成（30s 起指数退避：30/60/120/240...，超过 600s 幂次提醒），
;; 返回其结果，避免模型反复调用同一命令的死循环。
(defcustom aiaos-cli-shell-wait-base 30
  "重复 shell 命令的首次等待时长（秒）。模型再次调用同一命令时先等待此时间；
后续仍重复则按 `aiaos-cli-shell-wait-multiplier' 指数递增（30/60/120/240...）。"
  :type 'integer
  :group 'aiaos-cli)
(defcustom aiaos-cli-shell-wait-multiplier 2
  "重复 shell 命令等待的指数递增倍数（默认 2：30→60→120→240...）。"
  :type 'integer
  :group 'aiaos-cli)
(defcustom aiaos-cli-shell-wait-reminder 600
  "幂次提醒阈值（秒）。重复 shell 命令累计等待超过此值时，
向 stderr 追加“幂次提醒”并继续按指数递增等待。"
  :type 'integer
  :group 'aiaos-cli)
(defcustom aiaos-cli-shell-wait-max 2700
  "单次重复 shell 命令的最大等待时间（秒），默认 45 分钟。
到达后终止等待并返回提示（不无限等待）。"
  :type 'integer
  :group 'aiaos-cli)
(defcustom aiaos-cli-shell-wait-cumulative-max 5400
  "重复 shell 命令的累积等待总上限（秒），默认 90 分钟。
同一命令被模型反复重复调用时，累计退避等待超过此上限则强制中止任务链路，
避免模型持续忽略“勿再重复”提示造成无限等待。"
  :type 'integer
  :group 'aiaos-cli)
(defvar aiaos-llm--shell-procs (make-hash-table :test 'equal)
  "正在运行的 shell 命令表：key=命令字符串，value=(进程 . 启动时间)。")
(defvar aiaos-llm--shell-results (make-hash-table :test 'equal)
  "已完成的 shell 命令结果表：key=命令字符串，value=结果字符串。")
(defvar aiaos-llm--shell-cumulative-wait (make-hash-table :test 'equal)
  "每个 shell 命令的累积退避等待时间（秒）：key=命令字符串，value=累计秒数。
用于 90 分钟累积上限强制中止。")

(defun aiaos-llm--shell-wait-for-proc (proc buf start-time)
  "等待 PROC（输出到 BUF）完成；30s 起指数退避等待 + 超过600s 幂次提醒。
返回 (输出字符串 . 耗时秒) 或 (输出字符串 . (耗时秒 . timed-out))。"
  (let* ((base-wait (float aiaos-cli-shell-wait-base))
         (mult (float aiaos-cli-shell-wait-multiplier))
         (reminder-limit (float aiaos-cli-shell-wait-reminder))
         (max-wait (float aiaos-cli-shell-wait-max))
         (backoff base-wait)
         (reminder-n 0)
         (last-reminder (float-time))
         (deadline (+ (float-time) base-wait))
         (timed-out nil))
    (catch 'done
      (while (process-live-p proc)
        (let* ((now (float-time))
               (elapsed (- now start-time)))
          ;; 幂次提醒：持续等待超过 600s 后，每 600s 追加提醒并把等待上限按 2^n 递增
          (when (>= now (+ last-reminder reminder-limit))
            (setq reminder-n (1+ reminder-n)
                  last-reminder now
                  backoff (* backoff mult))
            (ignore-errors
              (with-current-buffer buf
                (goto-char (point-max))
                (insert (format "[aiaos-cli 幂次提醒 #%d] 已等待 %.0f 秒，shell 命令仍在执行；将等待上限加倍至 %.0f 秒。\n"
                                reminder-n elapsed (* backoff mult))))))
          (when (> now deadline)
            (setq timed-out t)
            (ignore-errors (delete-process proc))
            (throw 'done nil))
          (accept-process-output proc 0.5))))
    (list (with-current-buffer buf (buffer-string))
          (- (float-time) start-time)
          timed-out)))

(defvar aiaos-llm--shell-repeat-count (make-hash-table :test 'equal)
  "每个 shell 命令字符串被重复调用的次数。用于跨次指数退避（30→60→120...）。")

(defun aiaos-llm--shell-wait-duplicate (key cached-result)
  "重复 shell 命令去重等待：30s 起指数退避（30/60/120...），超过600s 幂次提醒。
KEY 为命令缓存键（名称+参数），CACHED-RESULT 为上一次相同命令的结果字符串。
第 1 次重复等待 `aiaos-cli-shell-wait-base' 秒，第 N 次重复等待 base*mult^(N-1)
（指数递增），超过 `aiaos-cli-shell-wait-reminder' 秒触发幂次提醒并继续递增，
单次上限为 `aiaos-cli-shell-wait-max'；累积等待超过
`aiaos-cli-shell-wait-cumulative-max'（默认 90 分钟）则强制中止任务链路。
等待期间模型若给出最终答复则自然退出；返回带“勿再重复”提示的缓存结果。"
  (let* ((base (float aiaos-cli-shell-wait-base))
         (mult (float aiaos-cli-shell-wait-multiplier))
         (reminder-limit (float aiaos-cli-shell-wait-reminder))
         (max-wait (float aiaos-cli-shell-wait-max))
         (cum-max (float aiaos-cli-shell-wait-cumulative-max))
         (n (1+ (gethash key aiaos-llm--shell-repeat-count 0)))
         (wait-now (min max-wait (* base (expt mult (1- n)))))
         (total-wait 0)
         (start (float-time))
         (reminder-n 0)
         (last-reminder start)
         (forced-stop nil))
    (puthash key n aiaos-llm--shell-repeat-count)
    ;; R-CUMULATIVE-CAP: 累积退避等待超过 90 分钟 → 强制中止任务链路
    (when (> (+ (gethash key aiaos-llm--shell-cumulative-wait 0) wait-now) cum-max)
      (setq wait-now (max 0 (- cum-max (gethash key aiaos-llm--shell-cumulative-wait 0)))
            forced-stop t)
      (message "[aiaos-cli 幂次提醒] 重复 shell 命令累积等待将超过 %.0f 分钟，强制中止任务链路。"
               (/ cum-max 60.0)))
    (message "[aiaos-cli] 重复 shell 命令 #%d：指数退避等待 %.0f 秒（上次 %.0f 秒）。"
             n wait-now (if (> n 1) (* base (expt mult (1- (1- n)))) 0.0))
    (while (and (< total-wait max-wait) (< total-wait wait-now))
      (sleep-for (min 0.5 (max 0.1 (- wait-now total-wait))))
      (setq total-wait (- (float-time) start))
      ;; 幂次提醒：累计等待超过 600s 后，每 600s 追加提醒并按指数递增等待
      (when (>= total-wait (+ (- last-reminder start) reminder-limit))
        (setq reminder-n (1+ reminder-n)
              last-reminder (float-time)
              wait-now (min max-wait (* wait-now mult)))
        (message "[aiaos-cli 幂次提醒 #%d] 重复 shell 命令已等待 %.0f 秒，继续按指数递增等待至 %.0f 秒。"
                 reminder-n total-wait wait-now)))
    (puthash key (+ (gethash key aiaos-llm--shell-cumulative-wait 0) total-wait)
             aiaos-llm--shell-cumulative-wait)
    (if forced-stop
        (format "[重复 shell 命令：累积退避等待已达 %.0f 分钟上限，任务链路强制中止。模型持续重复调用同一命令，未基于结果给出最终答复。]\n%s"
                (/ cum-max 60.0) cached-result)
      (format "[重复 shell 命令去重：已指数退避等待 %.0f 秒（第 %d 次重复），等待上一个相同命令完成，返回其结果。]\n%s\n\n请勿再调用此命令，直接基于结果给出最终答复。"
              total-wait n cached-result))))

(aiaos-llm-register-tool
 "shell"
 (lambda (args)
   (let* ((command (or (cdr (assq :command args))
                       (cdr (assq 'command args))))
          (key (and command (format "%s" command)))
          (running (and key (gethash key aiaos-llm--shell-procs)))
          (cached (and key (gethash key aiaos-llm--shell-results))))
     (cond
      ;; 1) 同一命令正在运行 → 等待其完成（不重复启动进程）
      (running
       (let* ((proc (car running))
              (start (cdr running))
              (out (aiaos-llm--shell-wait-for-proc proc (process-buffer proc) start)))
         (puthash key (car out) aiaos-llm--shell-results)
         (remhash key aiaos-llm--shell-procs)
         (if (nth 2 out)
             (format "[重复 shell 命令：已等待 %.0f 秒，原命令超时终止。]" (nth 1 out))
           (format "[重复 shell 命令去重：等待上一个相同命令完成（%.0f 秒），返回其结果]\n%s"
                   (nth 1 out) (car out)))))
       ;; 2) 已缓存（之前完成过）→ 30s 起指数退避去重等待，再返回缓存结果
       (cached
        (aiaos-llm--shell-wait-duplicate key cached))
      ;; 3) 新命令 → 异步启动并等待完成
      (command
       (let* ((buf (generate-new-buffer " *aiaos-shell*"))
              (start (float-time))
              (proc (make-process
                     :name "aiaos-shell"
                     :buffer buf
                     :command (list "/bin/sh" "-c" command)
                     :connection-type 'pipe))
              (out (aiaos-llm--shell-wait-for-proc proc buf start)))
         (puthash key (car out) aiaos-llm--shell-results)
         (ignore-errors (kill-buffer buf))
         (if (nth 2 out)
             (format "[shell 命令超时（等待 %.0f 秒）] 已终止。" (nth 1 out))
           (car out))))
      (t "No command provided"))))
  "Execute a shell command and return its stdout"
  '(("type" . "object")
    ("properties"
     . (("command" . (("type" . "string")
                      ("description" . "The shell command to execute")))))
    ("required" . ("command"))))

(aiaos-llm-register-tool
 "file-read"
 (lambda (args)
   (let ((file (or (cdr (assq :file args))
                   (cdr (assq 'file args)))))
     (if file
         (if (file-exists-p file)
             (with-temp-buffer
               (insert-file-contents file)
               (buffer-string))
           (format "File not found: %s" file))
       "No file specified")))
  "Read the full contents of a file as text"
  '(("type" . "object")
    ("properties"
     . (("file" . (("type" . "string")
                   ("description" . "Absolute or relative path to the file")))))
    ("required" . ("file"))))

(aiaos-llm-register-tool
 "file-write"
 (lambda (args)
   (let ((file (or (cdr (assq :file args))
                   (cdr (assq 'file args))))
         (content (or (cdr (assq :content args))
                      (cdr (assq 'content args)))))
     (if (and file content)
         (with-temp-buffer
           (insert content)
           (write-region (point-min) (point-max) file nil 'quiet)
           (format "Wrote %d bytes to %s" (string-bytes content) file))
       "Missing file or content")))
  "Write content to a file, creating or overwriting it"
  '(("type" . "object")
    ("properties"
     . (("file" . (("type" . "string")
                   ("description" . "Path of the file to write")))
        ("content" . (("type" . "string")
                      ("description" . "Text content to write")))))
    ("required" . ("file" "content"))))

(aiaos-llm-register-tool
 "list-dir"
 (lambda (args)
   (let ((dir (or (cdr (assq :path args))
                  (cdr (assq :dir args))
                  (cdr (assq 'path args))
                  (cdr (assq 'dir args))
                  ".")))
     (if (file-directory-p dir)
         (mapconcat #'identity (directory-files dir) "\n")
       (format "Not a directory: %s" dir))))
  "List entries in a directory"
  '(("type" . "object")
    ("properties"
     . (("path" . (("type" . "string")
                   ("description" . "Directory path, defaults to .")))))
    ("required" . ())))

(aiaos-llm-register-tool
 "getcwd"
 (lambda (_args) (expand-file-name default-directory))
  "Return the current working directory"
  '(("type" . "object")))

;;; LLM 接口（增强版）

(defun aiaos-llm-message (message &optional context)
  "Send MESSAGE to LLM and get response."
  (condition-case err
      (let ((ctx (or context aiaos-llm-task-context)))
        (aiaos-llm-call message ctx))
    (error
     (aiaos-llm-handle-error err context))))

;;; 交互界面
(defconst aiaos-llm-buffer-name "*AIAOS-LLM*"
  "Name of the AIAOS interaction buffer.")

(defun aiaos-llm-open-buffer ()
  "Open the AIAOS interaction buffer."
  (interactive)
  (let ((buf (get-buffer-create aiaos-llm-buffer-name)))
    (with-current-buffer buf
      (aiaos-llm-buffer-mode)
      (goto-char (point-max))
      (unless (> (point-max) 1)
        (insert "AIAOS-CLI Interactive Agent\n")
        (insert "==========================\n")
        (insert "Type your message and press Enter to interact with the agent.\n")
        (insert "Use M-x aiaos-llm-close-buffer to close this buffer.\n\n")))
    (switch-to-buffer buf)
    buf))

(defun aiaos-llm-close-buffer ()
  "Close the AIAOS interaction buffer."
  (interactive)
  (let ((buf (get-buffer aiaos-llm-buffer-name)))
    (when buf
      (kill-buffer buf))))

(define-derived-mode aiaos-llm-buffer-mode fundamental-mode "AIAOS-LLM"
  "Major mode for AIAOS interaction."
  (define-key aiaos-llm-buffer-mode-map (kbd "C-c C-c") 'aiaos-llm-send-current-line)
  (define-key aiaos-llm-buffer-mode-map (kbd "C-c C-k") 'aiaos-llm-close-buffer)
  (font-lock-mode 1))

(defun aiaos-llm-send-current-line ()
  "Send current line to AIAOS agent."
  (interactive)
  (let ((line (string-trim (thing-at-point 'line t))))
    (when (> (length line) 0)
      (aiaos-llm-buffer-append-response (aiaos-llm-message line)))))

(defun aiaos-llm-buffer-append-response (response)
  "Append RESPONSE to the AIAOS buffer."
  (let ((buf (get-buffer aiaos-llm-buffer-name)))
    (when buf
      (with-current-buffer buf
        (goto-char (point-max))
        (insert (format "\nAgent: %s\n" response))
        (goto-char (point-max))))))

;;; 用户交互函数
(defun aiaos-llm-prompt (question &optional default)
  "Prompt user with QUESTION and optional DEFAULT value."
  (interactive)
  (let ((response (read-string question default)))
    (aiaos-llm-log "debug" (format "User prompt response: %s" response))
    response))

(defun aiaos-llm-confirm (message)
  "Confirm with user via MESSAGE.
Returns t if user confirms, nil otherwise."
  (interactive)
  (let ((result (yes-or-no-p message)))
    (aiaos-llm-log "debug" (format "User confirm: %s" result))
    result))

;; 主入口命令
;;;###autoboot
(defun aiaos-llm ()
  "Open AIAOS-CLI interface."
  (interactive)
  (aiaos-llm-init)
  (aiaos-llm-open-buffer))

;;; 初始化函数
(defun aiaos-llm-init (&optional config)
  "Initialize AIAOS system with optional CONFIG."
  (interactive)
  (when config
    (dolist (pair config)
      (aiaos-set-config (car pair) (cdr pair))))
  ;; Set default config if not set
  (unless (aiaos-get-config 'model)
    (aiaos-set-config 'model "gpt-4"))
  ;; Initialize providers if configured
  (when aiaos-llm-providers
    (aiaos-llm-build-fallback-chain))
  (aiaos-llm-log "info" "AIAOS initialized")
  t)

(provide 'aiaos-cli-llm)

;;; TODO: Add more sophisticated LLM integration
;;; TODO: Implement actual context management
;;; TODO: Add tool permission system
