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

;;; Code:

(require 'json)
(require 'url)
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

(defcustom aiaos-llm-provider-timeout 120
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
  (let ((provider (list :name name
                        :endpoint endpoint
                        :model model
                        :api-key api-key
                        :options (or options '())
                        :status 'unknown
                        :last-check nil
                        :failure-count 0)))
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
            (error "Timeout: process killed after %s seconds" timeout))
            (with-temp-buffer
              (url-insert-file-contents url)
              (goto-char (point-min))
              (let ((status (aiaos-llm-parse-http-status)))
                (cond
                 ((= status 200)
                  (setq response (aiaos-llm-parse-json-response))
                  (if response
                      (let ((response-time (- (float-time) start-time)))
                        (if (< response-time 2.0)
                            :healthy
                          :unstable))
                    :unstable))
                 ((member status '(502 503 429))
                  (setq error-type (format "HTTP %d" status))
                  :down)
                 (t
                  (setq error-type (format "HTTP %d" status))
                  :down)))))
          (let ((response-time (- (float-time) start-time)))
            (if (> response-time 5.0)
                :unstable
              :healthy)))
      (error
       (let ((err-msg (format "%s" err)))
         (cond
          ((string-match "Timeout" err-msg)
           (setq error-type "Timeout")
           :down)
          ((string-match "connection" err-msg)
           (setq error-type "Connection refused")
           :down)
          (t
            (setq error-type err-msg)
            :down))))))
  
  (let ((status (or response :down)))
    (aiaos-llm-update-provider-status provider status error-type)
    status))

(defun aiaos-llm-update-provider-status (provider status &optional error)
  "Update the status of PROVIDER to STATUS with optional ERROR."
  (let ((updated (cons :status status
                      (cons :last-check (float-time)
                            (if error
                                (cons :last-error error
                                      (cons :failure-count
                                             (1+ (or (cdr (assq :failure-count provider)) 0))
                                             provider))
                              provider)))))
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
        (case status
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
      (let ((pos (position current-name chain :test 'equal)))
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
  "Format MESSAGE and CONTEXT into API messages array."
  (let ((messages nil))
    ;; Add system message if context exists
    (when context
      (let ((system-msg (aiaos-llm-extract-system-message context)))
        (when system-msg
          (push (list :role "system" :content system-msg) messages))))
    
    ;; Add conversation history
    (when (and context (listp context))
      (dolist (msg (reverse context))
        (when (listp msg)
          (push (list :role (cdr (assq :role msg))
                      :content (cdr (assq :content msg)))
                messages))))
    
    ;; Add current message
    (push (list :role "user" :content message) messages)
    
    messages))

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
        (when (looking-at-p "\\([^\n]*\n\\)*")
          (goto-char (match-end 0))
          (json-read))
        (json-read))
    (error nil)))

;;; 核心 LLM 调用函数（增强版）

(defun aiaos-llm-call (message context &optional provider-name)
  "Call LLM with MESSAGE and CONTEXT, optionally specifying PROVIDER-NAME.
Returns the response content."
  (let* ((provider (if provider-name
                      (aiaos-llm-get-provider provider-name)
                    (aiaos-llm-get-current-provider)))
         (max-retries aiaos-llm-max-retries)
         (attempt 0)
         (response nil)
         (error-occurred nil))
    
    (while (and (not response) (< attempt max-retries))
      (condition-case err
          (progn
            (aiaos-llm-log "debug"
                           (format "LLM call attempt %d/%d with provider %s"
                                   (1+ attempt) max-retries
                                   (cdr (assq :name provider))))
            (setq response (aiaos-llm-do-llm-request provider message context))
            (when response
              (aiaos-llm-update-provider-status provider :healthy)))
        (error
         (aiaos-llm-log "error"
                        (format "LLM call failed (attempt %d): %s"
                                (1+ attempt) err))
         (setq error-occurred err)
         (let ((next-provider (aiaos-llm-get-next-fallback-provider
                              (cdr (assq :name provider)))))
           (when next-provider
             (aiaos-llm-log "info"
                            (format "Falling back to provider: %s" next-provider))
             (setq provider (aiaos-llm-get-provider next-provider))
             (aiaos-llm-set-current-provider next-provider)))
         (sleep-for 0.5)
         (setq attempt (1+ attempt)))))
    
    (if response
        response
      (error "All LLM providers failed. Last error: %s" error-occurred))))

(defun aiaos-llm-do-llm-request (provider message context)
  "Perform actual LLM request to PROVIDER with MESSAGE and CONTEXT."
  (let* ((url (aiaos-llm-build-request-url provider))
         (headers (aiaos-llm-build-request-headers provider))
         (data (aiaos-llm-build-request-data provider message context))
         (url-request-method "POST")
         (url-request-data data)
         (url-request-extra-headers headers)
         (buffer (url-retrieve url))
         (response nil))
    
    (with-current-buffer buffer
      (condition-case err
          (progn
            (goto-char (point-min))
            (let ((status (aiaos-llm-parse-http-status)))
              (cond
               ((= status 200)
                (goto-char (point-min))
                (re-search-forward "^$" nil t)
                (let ((json (json-read)))
                  (let ((choices (cdr (assq :choices json))))
                    (when choices
                      (let ((first-choice (car choices)))
                        (let ((msg (cdr (assq :message first-choice))))
                          (cdr (assq :content msg))))))))
               ((member status '(502 503 429))
                (error "HTTP %d - Service temporarily unavailable" status))
               (t
                (error "HTTP %d - Request failed" status)))))
        (error
         (progn
           (kill-buffer buffer)
           (signal err))))))
  
  (with-current-buffer buffer
    (kill-buffer buffer))
  
  response))

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

;;; 任务链路连续执行

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
              (puthash index result aiaos-llm-task-context)
              ;; Continue to next step after a delay
              (run-at-time 0.1 nil 'aiaos-llm-execute-task-chain-step (1+ index))))
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
  (puthash name (list :function function :description description) aiaos-llm-tools)
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