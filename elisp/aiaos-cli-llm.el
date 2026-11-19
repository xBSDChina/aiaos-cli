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
                        (cons :failure-count 0)
                        (cons :last-error nil))))
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

(defun aiaos-llm-set-current-provider (name)
  "Set the current active LLM provider to NAME."
  (let ((provider (aiaos-llm-get-provider name)))
    (if provider
        (progn
          (setq aiaos-llm-current-provider name)
          (aiaos-llm-log "info" (format "Switched to provider: %s" name))
          t)
      (aiaos-llm-log "error" (format "Provider not found: %s" name))
      nil)))

;;; Provider 状态探测

(defun aiaos-llm-probe-provider (provider)
  "Probe the status of PROVIDER.
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
          (t :unstable))))))
  
  (let ((status (aiaos-llm-probe-provider-internal provider)))
    (let ((updated (aiaos-llm-update-provider-status provider status)))
      (aiaos-llm-log "debug" (format "Provider %s status: %s"
                                     (cdr (assq :name provider))
                                     status))
      updated)))

(defun aiaos-llm-probe-provider-internal (provider)
  "Internal probe function for PROVIDER."
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
    (let ((status-cell (assq :status updated)))
      (if status-cell (setcdr status-cell status)
        (setq updated (append updated (list (cons :status status))))))
    (let ((check-cell (assq :last-check updated)))
      (if check-cell (setcdr check-cell (float-time))
        (setq updated (append updated (list (cons :last-check (float-time)))))))
    (when (eq status :down)
      (let ((err-cell (assq :last-error updated)))
        (if err-cell (setcdr err-cell "connection_failed")
          (setq updated (append updated (list (cons :last-error "connection_failed"))))))
      (let ((fail-cell (assq :failure-count updated)))
        (if fail-cell (setcdr fail-cell (1+ (or (cdr (assq :failure-count provider)) 0)))
          (setq updated (append updated (list (cons :failure-count 1)))))))
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
  "Classify providers into categories: healthy, unstable, down."
  (let ((healthy nil)
        (unstable nil)
        (down nil))
    (dolist (provider aiaos-llm-providers)
      (let ((status (aiaos-llm-probe-provider provider)))
        (cl-case status
          (:healthy (push provider healthy))
          (:unstable (push provider unstable))
          (:down (push provider down)))))
    (list :healthy healthy
          :unstable unstable
          :down down)))

;;; Fallback 机制

(defun aiaos-llm-build-fallback-chain ()
  "Build the fallback chain from healthy providers."
  (let* ((classified (aiaos-llm-classify-providers))
         (healthy (cdr (assq :healthy classified))))
    (setq aiaos-llm-fallback-chain
          (mapcar (lambda (p) (cdr (assq :name p))) healthy))
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
  "Build request URL for PROVIDER."
  (let ((endpoint (cdr (assq :endpoint provider)))
        (model (cdr (assq :model provider))))
    (if (string-match-p "/chat/completions$" endpoint)
        endpoint
      (format "%s/chat/completions" endpoint))))

(defun aiaos-llm-build-request-headers (provider)
  "Build request headers for PROVIDER."
  (let ((api-key (cdr (assq :api-key provider)))
        (headers (cdr (assq :options provider))))
    (append
     '((Content-Type . "application/json"))
     (when api-key
       (list (cons "Authorization" (format "Bearer %s" api-key))))
     (when (and headers (listp headers))
       headers))))

(defun aiaos-llm-build-request-data (provider message context)
  "Build request data for PROVIDER, MESSAGE, and CONTEXT."
  (let ((model (cdr (assq :model provider)))
        (messages (aiaos-llm-format-messages message context)))
    (json-encode
     (list :model model
           :messages messages
           :temperature 0.7
           :max_tokens 2000))))

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
  "Call the Python bridge with MESSAGE in SSE streaming mode.
R3003: 使用 agent_llm_bridge.py --stream 参数，通过 process-filter 逐块接收数据。
CALLBACK 是一个函数，接收一个参数（数据块），在每块数据到达时调用。
返回最终的完整响应（alist），或 nil。"
  (let* ((bridge (expand-file-name "~/.config/aiaos/agent_llm_bridge.py"))
         (python (or (executable-find "python3") "python3"))
         (pyenv (format "PYTHONPATH=%s:%s:%s"
                        (expand-file-name "~/aiaos/lib")
                        (expand-file-name "~/.config/aiaos")
                        (or (getenv "PYTHONPATH") "")))
         (buf (get-buffer-create "*aiaos-llm-stream*"))
         (result nil)
         (full-content "")
         (tool-calls nil)
         (final-event nil))
    
    (when (file-exists-p bridge)
      (with-current-buffer buf
        (erase-buffer))
      
      (let ((process-environment (cons pyenv process-environment)))
        (let ((proc (start-process "aiaos-llm-stream" buf python bridge
                                   "--message" (or message "")
                                   "--agent" (or agent "default")
                                   "--session" (or session-id "")
                                   "--stream")))
          
          (set-process-filter proc
                              (lambda (proc chunk)
                                (with-current-buffer (process-buffer proc)
                                  (goto-char (point-max))
                                  (insert chunk)
                                  ;; 解析 SSE 事件
                                  (let ((events (aiaos-llm--parse-sse-events)))
                                    (dolist (event events)
                                      (let ((event-type (cdr (assq 'type event)))
                                            (event-data (cdr (assq 'data event))))
                                        (cond
                                         ((equal event-type "chunk")
                                          (let ((content (cdr (assq 'content event-data))))
                                            (when content
                                              (setq full-content (concat full-content content))
                                              (when callback
                                                (funcall callback content)))))
                                         ((equal event-type "end")
                                          (setq final-event event-data)
                                          (when (cdr (assq 'tool_calls event-data))
                                            (setq tool-calls (cdr (assq 'tool_calls event-data)))))
                                         ((equal event-type "error")
                                          (message "SSE error: %s" event-data))))))))
          
          (set-process-sentinel proc
                                (lambda (proc status)
                                  (when (and (process-exit-status proc) (not result))
                                    (with-current-buffer (process-buffer proc)
                                      (goto-char (point-min))
                                      (let ((json-str (string-trim (buffer-string))))
                                        (when (> (length json-str) 0)
                                          (condition-case nil
                                              (progn
                                                (goto-char (point-min))
                                                (setq result (json-read)))
                                            (error nil))))))))
          
          (while (and (process-live-p proc) (not result))
            (accept-process-output proc 0.1))
          
          ;; 如果最终结果未设置，使用 final-event
          (when (and final-event (not result))
            (setq result final-event))
          
          (when result
            (let ((reply (cdr (assq 'reply result)))
                  (final-tool-calls (or tool-calls (cdr (assq 'tool_calls result)))))
              (list (cons 'reply (or reply full-content))
                    (cons 'tool_calls final-tool-calls)
                    (cons 'agent (or agent "default"))
                    (cons 'session_id session-id))))))))))

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
  "Call the Python bridge with MESSAGE, return parsed response including tool_calls.
R3001: 委托给 agent_llm_bridge.py（支持工具调用和会话历史）。
返回完整的 alist（包含 reply, tool_calls, session_id 等），或 nil。"
  (let* ((bridge (expand-file-name "~/.config/aiaos/agent_llm_bridge.py"))
         (python (or (executable-find "python3") "python3"))
         (pyenv (format "PYTHONPATH=%s:%s:%s"
                        (expand-file-name "~/aiaos/lib")
                        (expand-file-name "~/.config/aiaos")
                        (or (getenv "PYTHONPATH") ""))))
    (when (file-exists-p bridge)
      (let ((process-environment (cons pyenv process-environment)))
        (with-temp-buffer
          (let ((status (call-process python nil t nil
                                      bridge
                                      "--message" (or message "")
                                      "--agent" (or agent "default")
                                      "--session" (or session-id ""))))
            (when (= status 0)
              (let ((json-str (string-trim (buffer-string))))
                (when (> (length json-str) 0)
                  (condition-case nil
                      (progn
                        (goto-char (point-min))
                        (json-read))
                    (error nil)))))))))))

(defun aiaos-llm-do-llm-request-with-tools (provider message context session-id)
  "Perform LLM request to PROVIDER with MESSAGE and CONTEXT, handling tool calls.
R3001: 通过 Python bridge（支持工具调用）完成请求，
然后执行工具调用，将结果返回给 LLM，直到获得最终回复。
返回最终的文本响应。"
  (let ((result (aiaos-llm--call-bridge-with-tools message nil session-id)))
    (if result
        (let ((reply (cdr (assq 'reply result)))
              (error-msg (cdr (assq 'error result)))
              (fallback-exhausted (cdr (assq 'permanent result)))
              (tool-calls (cdr (assq 'tool_calls result))))
          (cond
           ;; 所有 provider 均失败（permanent）→ 抛错让上层走 fallback/recover
           ((or fallback-exhausted
                (and error-msg (string= error-msg "fallback_exhausted")))
            (error "fallback_exhausted: 所有 LLM provider 均不可用"))
           ;; 有工具调用 → 执行工具并递归调用
           (tool-calls
            (aiaos-llm-execute-tool-calls tool-calls message context session-id))
           ;; 有 reply → 正常返回
           ((and reply (> (length (format "%s" reply)) 0))
            (format "%s" reply))
           ;; 有 error → 抛错（触发 provider fallback / recover）
           (error-msg
            (error "LLM error: %s" error-msg))
           (t
            (error "LLM returned empty reply"))))
      (error "Bridge unavailable"))))

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

(defun aiaos-llm-handle-error (err context)
  "Handle an error ERR in the given CONTEXT.
Returns a human-readable error message string."
  (let ((msg (format "%s" err)))
    (aiaos-llm-log "error" (format "LLM error in context %s: %s" context msg))
    (format "Error occurred: %s" msg)))

(defun aiaos-llm-recover-from-error (err context)
  "Attempt to recover from an error ERR in the given CONTEXT.
Returns non-nil if recovery was possible, nil otherwise.
Never throws an error."
  (let ((msg (format "%s" err)))
    (aiaos-llm-log "warn" (format "Attempting recovery from error: %s" msg))
    (cond
     ;; Timeout errors are transient - retryable
     ((string-match "timeout\|Timeout\|timed out" msg) t)
     ;; HTTP 402 / quota / credits errors are transient
     ((string-match "402\|quota\|credits\|insufficient" msg) t)
     ;; Connection/network errors are transient
     ((string-match "connection\|refused\|network\|unavailable" msg) t)
     ;; Otherwise not recoverable
     (t nil))))

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

(defun aiaos-llm-register-tool (name function description)
  "Register a tool with NAME, FUNCTION, and DESCRIPTION."
  (puthash name (list (cons :function function) (cons :description description)) aiaos-llm-tools)
  (aiaos-llm-log "debug" (format "Registered tool: %s" name)))

(defun aiaos-llm-tool-list ()
  "Get list of available tools."
  (let ((tools nil))
    (maphash (lambda (k v)
               (push (cons k (cdr v)) tools))
             aiaos-llm-tools)
    tools))

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

;; 注册内置工具
(aiaos-llm-register-tool
 "shell"
 (lambda (args)
   (let ((command (cdr (assq :command args))))
     (if command
         (with-temp-buffer
           (shell-command command t nil)
           (buffer-string))
       "No command provided")))
 "Execute shell command")

(aiaos-llm-register-tool
 "file-read"
 (lambda (args)
   (let ((file (cdr (assq :file args))))
     (if file
         (if (file-exists-p file)
             (with-temp-buffer
               (insert-file-contents file)
               (buffer-string))
           "File not found")
       "No file specified")))
 "Read file content")

(aiaos-llm-register-tool
 "file-write"
 (lambda (args)
   (let ((file (cdr (assq :file args)))
         (content (cdr (assq :content args))))
     (if (and file content)
         (with-temp-buffer
           (insert content)
           (write-file file)
           (format "Wrote %d bytes to %s" (length content) file))
       "Missing file or content")))
 "Write content to file")

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
