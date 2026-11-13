;; aiaos-cli-core.el - AIAOS-CLI 核心模块（增强版）
;; 提供AIAOS系统的核心功能和交互界面，包含LLM provider管理、错误自愈、连续任务等

(require 'json)
(require 'url)
(require 'org)
(require 'url-http)

;;; 配置管理
(defgroup aiaos nil
  "AIAOS-CLI configuration group."
  :group 'external)

(defcustom aiaos-config nil
  "AIAOS configuration alist."
  :type '(alist :key-type symbol :value-type string)
  :group 'aiaos)

(defcustom aiaos-debug-mode nil
  "Enable debug mode for AIAOS."
  :type 'boolean
  :group 'aiaos)

(defcustom aiaos-api-key nil
  "LLM API key."
  :type 'string
  :group 'aiaos)

(defcustom aiaos-model "gpt-4"
  "Default LLM model."
  :type 'string
  :group 'aiaos)

;;; LLM Provider 管理
(defcustom aiaos-llm-providers nil
  "List of LLM provider configurations.
Each element is a list: (name endpoint model api-key &optional options).
Options can include: timeout, retries, headers, etc."
  :type '(repeat
          (list :key-type string
                string  ; name
                string  ; endpoint
                string  ; model
                string  ; api-key
                (repeat :key-type symbol
                        (symbol :value-type any))))
  :group 'aiaos)

(defcustom aiaos-fallback-chain nil
  "Fallback chain for LLM providers. List of provider names in order."
  :type '(repeat string)
  :group 'aiaos)

(defcustom aiaos-provider-timeout 5400
  "Timeout for LLM provider requests in seconds."
  :type 'integer
  :group 'aiaos)

(defcustom aiaos-max-retries 3
  "Maximum retries for failed requests."
  :type 'integer
  :group 'aiaos)

;;; Agent 状态和超时增强配置
(defcustom aiaos-max-busy-time 900
  "Maximum time (in seconds) agent can be continuously busy before triggering hedge mechanism."
  :type 'integer
  :group 'aiaos)

(defcustom aiaos-hedge-interval 60
  "Base interval (in seconds) for hedge reminders when agent is busy."
  :type 'integer
  :group 'aiaos)

;;; 全局状态变量
(let ((aiaos-agent-busy-start-time nil)
      (aiaos-agent-busy-timer nil)
      (aiaos-hedge-counter 0)
      (aiaos-task-chain-iteration-limit nil))  ; nil means no limit
  (setq aiaos-agent-busy-start-time nil)
  (setq aiaos-agent-busy-timer nil)
  (setq aiaos-hedge-counter 0))

;;; Provider 状态分类
(defconst aiaos-provider-status
  '((:healthy . "完全可访问")
    (:unstable . "可连接但交互不稳定")
    (:down . "连接中断与拒绝连接"))
  "Provider status categories.")

;;; 记忆系统
(defconst aiaos-memory-file "~/.aiaos-memory.el"
  "File for persistent memory storage.")

(defun aiaos-memory-load ()
  "Load memory from file."
  (if (file-exists-p aiaos-memory-file)
      (with-temp-buffer
        (insert-file-contents aiaos-memory-file)
        (goto-char (point-min))
        (condition-case nil
            (read (current-buffer))
          (error nil)))
    (make-hash-table :test 'equal)))

(defconst aiaos-memory (aiaos-memory-load)
  "Memory storage hash table.")

(defun aiaos-memory-save ()
  "Save memory to file."
  (let ((buf (get-buffer-create "*aiaos-memory*")))
    (with-current-buffer buf
      (erase-buffer)
      (princ "(" (current-buffer))
      (maphash (lambda (k v)
                  (princ (format "(%s . %s) " k v) (current-buffer)))
                aiaos-memory)
      (princ ")" (current-buffer))
      (write-file aiaos-memory-file))))

(defun aiaos-memory-store (key value)
  "Store KEY with VALUE in memory."
  (puthash key value aiaos-memory)
  (aiaos-memory-save)
  t)

(defun aiaos-memory-retrieve (key)
  "Retrieve value for KEY from memory."
  (gethash key aiaos-memory))

;;; 日志系统
;;; Buffer configuration
(defconst aiaos-buffer-name "*AIAOS-CLI*"
  "Name of the AIAOS interaction buffer.")

(defun aiaos-log (level message)
  "Log MESSAGE at LEVEL to AIAOS buffer."
  (let ((buf (get-buffer-create aiaos-buffer-name)))
    (when buf
      (with-current-buffer buf
        (goto-char (point-max))
        (insert (format "[%s] %s: %s\n"
                        (format-time-string "%H:%M:%S")
                        (upcase (if (symbolp level) (symbol-name level) level))
                        message))))))

;;; 配置管理函数
(defun aiaos-set-config (key value)
  "Set configuration KEY to VALUE."
  (setq aiaos-config (assq-delete-all key aiaos-config))
  (push (cons key value) aiaos-config))

(defun aiaos-get-config (key)
  "Get configuration value for KEY."
  (cdr (assq key aiaos-config)))

;;; LLM Provider 管理函数
(defun aiaos-get-llm-provider (name)
  "Get LLM provider configuration by NAME."
  (let ((providers aiaos-llm-providers))
    (while providers
      (when (string-equal (car (car providers)) name)
        (return (car providers)))
      (setq providers (cdr providers)))
    nil))

(defun aiaos-get-current-provider ()
  "Get the current active LLM provider."
  (let ((current-name (aiaos-get-config 'current-provider)))
    (if current-name
        (aiaos-get-llm-provider current-name)
      (car aiaos-llm-providers))))

(defun aiaos-set-current-provider (name)
  "Set the current active LLM provider to NAME."
  (let ((provider (aiaos-get-llm-provider name)))
    (if provider
        (progn
          (aiaos-set-config 'current-provider name)
          (aiaos-log "info" (format "Switched to provider: %s" name))
          t)
      (aiaos-log "error" (format "Provider not found: %s" name))
      nil)))

;;; Agent 状态探测函数
(defun aiaos-check-agent-status ()
  "Check if agent is busy or idle.
Returns :busy or :idle."
  (condition-case nil
      (let ((buf (get-buffer aiaos-buffer-name)))
        (if buf
            (with-current-buffer buf
              (let ((last-line (buffer-substring (point-max) (point-max))))
                (if (string-match-p "Agent:" last-line)
                    :busy
                  :idle)))
          :idle))
    (error :idle)))

(defun aiaos-reset-timeout-if-busy ()
  "Reset the timeout counter if agent is busy.
This allows continuous tasks to proceed without timeout interruption."
  (let ((status (aiaos-check-agent-status)))
    (when (eq status :busy)
      (aiaos-log "debug" "Agent is busy, resetting timeout")
      (run-at-time aiaos-provider-timeout nil 'aiaos-reset-timeout-if-busy)
      (aiaos-check-hedge-mechanism))))

(defun aiaos-check-hedge-mechanism ()
  "Check if hedge mechanism should be triggered based on busy duration."
  (when aiaos-agent-busy-start-time
    (let ((busy-duration (float-time (time-subtract (current-time) aiaos-agent-busy-start-time))))
      (when (> busy-duration aiaos-max-busy-time)
        (aiaos-log "warning" (format "Agent busy for %.0f seconds, triggering hedge" busy-duration))
        (aiaos-hedge-reminder)
        (aiaos-enter-reflect-mode)))))

(defun aiaos-hedge-reminder ()
  "Send a hedge reminder to the agent using exponential backoff distribution."
  (let ((hedge-message (format "Hedge reminder %d: Agent has been busy for an extended period. Please check status and provide progress update." (1+ aiaos-hedge-counter))))
    (aiaos-log "info" hedge-message)
    (setq aiaos-hedge-counter (1+ aiaos-hedge-counter))
    ;; Schedule next hedge with exponential backoff
    (let ((next-interval (* aiaos-hedge-interval (expt 2 (1- aiaos-hedge-counter)))))
      (run-at-time next-interval nil 'aiaos-hedge-reminder))))

(defun aiaos-enter-reflect-mode ()
  "Enter reflection mode to analyze and optimize task execution."
  (aiaos-log "info" "Entering reflection mode for task optimization")
  ;; Save current state to memory for reflection
  (aiaos-memory-store 'last-reflect-time (current-time))
  (aiaos-memory-store 'hedge-counter aiaos-hedge-counter)
  ;; Reset hedge counter after entering reflection
  (setq aiaos-hedge-counter 0))

;;; Provider 状态探测
(defun aiaos-probe-provider (provider)
  "Probe the status of PROVIDER.
Returns one of: :healthy, :unstable, :down"
  (let* ((name (cdr (assq :name provider)))
         (endpoint (cdr (assq :endpoint provider)))
         (api-key (cdr (assq :api-key provider)))
         (timeout (or (cdr (assq :timeout (cdr (assq :options provider))))
                     aiaos-provider-timeout)))
    (condition-case err
        (progn
          (aiaos-log "debug" (format "Probing provider: %s" name))
          (let ((buf (url-retrieve endpoint)))
            (with-current-buffer buf
              (goto-char (point-min))
              (let ((status (aiaos-parse-http-status)))
                (cond
                 ((= status 200)
                  (aiaos-log "debug" (format "Provider %s is healthy" name))
                  :healthy)
                 ((member status '(502 503))
                  (aiaos-log "warning" (format "Provider %s unstable (HTTP %d)" name status))
                  :unstable)
                 (t
                  (aiaos-log "warning" (format "Provider %s down (HTTP %d)" name status))
                  :down))))))
      (error
       (aiaos-log "warning" (format "Provider %s unreachable: %s" name err))
       :down))))

(defun aiaos-probe-all-providers ()
  "Probe all configured providers and update their status."
  (let ((providers aiaos-llm-providers))
    (while providers
      (let* ((provider (car providers))
             (name (cdr (assq :name provider)))
             (status (aiaos-probe-provider provider)))
        (aiaos-set-config (intern (format "provider-%s-status" name)) status)
        (aiaos-log "info" (format "Provider %s status: %s" name status)))
      (setq providers (cdr providers)))))

(defun aiaos-build-fallback-chain ()
  "Build fallback chain based on provider status."
  (let ((healthy-providers nil)
        (unstable-providers nil))
    (dolist (provider aiaos-llm-providers)
      (let* ((name (cdr (assq :name provider)))
             (status (aiaos-get-config (intern (format "provider-%s-status" name)))))
        (cond
         ((eq status :healthy)
          (push name healthy-providers))
         ((eq status :unstable)
          (push name unstable-providers)))))
    (setq aiaos-fallback-chain (append healthy-providers unstable-providers))
    (aiaos-log "info" (format "Fallback chain: %s" aiaos-fallback-chain))))

;;; 请求构建函数
(defun aiaos-build-request-url (provider)
  "Build request URL for PROVIDER."
  (cdr (assq :endpoint provider)))

(defun aiaos-build-request-headers (provider)
  "Build request headers for PROVIDER."
  (let ((api-key (cdr (assq :api-key provider))))
    (list (cons "Authorization" (format "Bearer %s" api-key))
          (cons "Content-Type" "application/json"))))

(defun aiaos-build-request-data (provider message context)
  "Build request data for PROVIDER with MESSAGE and CONTEXT."
  (let ((model (cdr (assq :model provider))))
    (json-encode
     (list
      (cons "model" model)
      (cons "messages" (list (cons "role" "user") (cons "content" message)))
      (cons "stream" t)))))  ; Enable streaming

;;; 响应解析
(defun aiaos-parse-http-status ()
  "Parse HTTP status from current buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
      (string-to-number (match-string 1)))))

(defun aiaos-parse-json-response ()
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
(defun aiaos-call-llm (message context &optional provider-name)
  "Call LLM with MESSAGE and CONTEXT, optionally specifying PROVIDER-NAME.
Returns the response content."
  (let* ((provider (if provider-name
                      (aiaos-get-llm-provider provider-name)
                    (aiaos-get-current-provider)))
         (max-retries aiaos-max-retries)
         (attempt 0)
         (response nil)
         (error-occurred nil))
    
    (while (and (not response) (< attempt max-retries))
      (condition-case err
          (progn
            (aiaos-log "debug"
                       (format "LLM call attempt %d/%d with provider %s"
                               (1+ attempt) max-retries
                               (cdr (assq :name provider)))))
            (setq response (aiaos-do-llm-request provider message context))
            (when response
              (aiaos-update-provider-status provider :healthy)))
        (error
         (aiaos-log "error"
                    (format "LLM call failed (attempt %d): %s"
                            (1+ attempt) err))
         (setq error-occurred err)
         (let ((next-provider (aiaos-get-next-fallback-provider
                              (cdr (assq :name provider)))))
           (when next-provider
             (aiaos-log "info"
                        (format "Falling back to provider: %s" next-provider))
             (setq provider (aiaos-get-llm-provider next-provider))
             (aiaos-set-current-provider next-provider)))
         (sleep-for 0.5)
         (setq attempt (1+ attempt)))))
    
    (if response
        response
      (error "All LLM providers failed. Last error: %s" error-occurred)))

(defun aiaos-do-llm-request (provider message context)
  "Perform actual LLM request to PROVIDER with MESSAGE and CONTEXT."
  (let* ((url (aiaos-build-request-url provider))
         (headers (aiaos-build-request-headers provider))
         (data (aiaos-build-request-data provider message context))
         (url-request-method "POST")
         (url-request-data data)
         (url-request-extra-headers headers)
         (buffer (url-retrieve url))
         (response nil))
    
    (with-current-buffer buffer
      (condition-case err
          (progn
            (goto-char (point-min))
            (let ((status (aiaos-parse-http-status)))
              (cond
               ((= status 200)
                (goto-char (point-min))
                (re-search-forward "^$" nil t)
                (let ((json-data (json-read)))
                  (setq response (cdr (assq 'content json-data)))))
               ((= status 429)
                (error "Rate limit exceeded"))
               ((member status '(502 503))
                (error "Server error"))
               (t
                (error "HTTP error: %d" status)))))
        (error
         (aiaos-log "error" (format "Request failed: %s" err))
         (kill-buffer buffer)
         (error "Request failed: %s" err))))
    
    (kill-buffer buffer)
    response))

;;; 错误处理函数
(defun aiaos-handle-error (error context)
  "Handle general errors with context."
  (aiaos-log "error" (format "Error: %s" error))
  (condition-case nil
      (aiaos-recover-from-error error context)
    (error nil))
  nil)

(defun aiaos-recover-from-error (error context)
  "Attempt to recover from ERROR with CONTEXT."
  (aiaos-log "info" "Attempting error recovery")
  (cond
   ((string-match-p "timeout" (error-message error))
    (aiaos-handle-timeout-error))
   ((string-match-p "rate limit" (error-message error))
    (aiaos-handle-rate-limit-error))
   ((string-match-p "502|503" (error-message error))
    (aiaos-handle-server-error))
   (t
    (aiaos-handle-generic-error))))

(defun aiaos-handle-timeout-error ()
  "Handle timeout errors."
  (let ((next-provider (aiaos-get-next-fallback-provider
                        (aiaos-get-config 'current-provider))))
    (when next-provider
      (aiaos-set-current-provider next-provider)
      (aiaos-log "info" (format "Switched to provider: %s" next-provider)))))

(defun aiaos-handle-server-error ()
  "Handle HTTP 502/503 errors."
  (aiaos-handle-timeout-error))

(defun aiaos-handle-rate-limit-error ()
  "Handle HTTP 429 rate limit errors."
  (sleep-for 2) ; Wait before retry
  (aiaos-handle-timeout-error))

(defun aiaos-handle-generic-error ()
  "Handle generic errors."
  (aiaos-probe-all-providers)
  (aiaos-build-fallback-chain))

;;; 任务链路连续执行
(defconst aiaos-task-chain nil
  "Current task chain being executed.")

(defconst aiaos-task-context (make-hash-table :test 'equal)
  "Context for current task chain.")

(defun aiaos-start-task-chain (tasks)
  "Start a continuous task chain with TASKS.
This function initiates an unbounded task execution loop that continues
until all tasks are completed or an unrecoverable error occurs."
  (setq aiaos-task-chain tasks)
  (aiaos-log "info" (format "Starting task chain with %d tasks" (length tasks)))
  ;; Start the continuous execution loop
  (aiaos-execute-task-chain-step 0))

(defun aiaos-execute-task-chain-step (index)
  "Execute task at INDEX in the chain.
This function is designed to run continuously without iteration limits."
  (if (>= index (length aiaos-task-chain))
      (progn
        (aiaos-log "info" "Task chain completed")
        nil)
    (let ((task (nth index aiaos-task-chain)))
      (condition-case err
          (progn
            (aiaos-log "info" (format "Executing task %d: %s" (1+ index) task))
            (let ((result (aiaos-execute-task task)))
              (puthash index result aiaos-task-context)
              ;; Continue to next step immediately without delay
              (aiaos-execute-task-chain-step (1+ index))))
        (error
         (aiaos-log "error" (format "Task %d failed: %s" (1+ index) err))
         ;; Attempt recovery and continue
         (condition-case nil
             (aiaos-recover-from-error err aiaos-task-context)
           (error nil))
         ;; Continue to next step after brief recovery delay
         (run-at-time 0.1 nil 'aiaos-execute-task-chain-step (1+ index)))))))

(defun aiaos-execute-task (task)
  "Execute a single TASK."
  (if (stringp task)
      (aiaos-message task)
    (if (listp task)
        (let ((type (cdr (assq :type task)))
              (content (cdr (assq :content task))))
          (cond
           ((equal type 'llm)
            (aiaos-message content))
           ((equal type 'tool)
            (aiaos-tool-call (cdr (assq :name task)) (cdr (assq :args task))))
           (t
            (format "Unknown task type: %s" type))))
      (format "Invalid task: %s" task))))

;;; 工具系统
(defconst aiaos-tools (make-hash-table :test 'equal)
  "Registry of available tools.")

(defun aiaos-register-tool (name function description)
  "Register a tool with NAME, FUNCTION, and DESCRIPTION."
  (puthash name (list :function function :description description) aiaos-tools)
  (aiaos-log "debug" (format "Registered tool: %s" name)))

(defun aiaos-tool-list ()
  "Get list of available tools."
  (let ((tools nil))
    (maphash (lambda (k v)
               (push (cons k (cdr v)) tools))
             aiaos-tools)
    tools))

(defun aiaos-tool-call (tool-name args)
  "Call tool TOOL-NAME with ARGS."
  (let ((tool (gethash tool-name aiaos-tools)))
    (if tool
        (condition-case err
            (funcall (cdr (assq :function tool)) args)
          (error
           (aiaos-log "error" (format "Tool call failed: %s" err))
           (format "Error: %s" err)))
      (format "Tool not found: %s" tool-name))))

;; 注册内置工具
(aiaos-register-tool
 "shell"
 (lambda (args)
   (let ((command (cdr (assq :command args))))
     (if command
         (with-temp-buffer
           (shell-command command t nil)
           (buffer-string))
       "No command provided")))
 "Execute shell command")

(aiaos-register-tool
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

(aiaos-register-tool
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
(defun aiaos-message (message &optional context)
  "Send MESSAGE to LLM and get response."
  (condition-case err
      (let ((ctx (or context aiaos-context)))
        (aiaos-call-llm message ctx))
    (error
     (aiaos-handle-error err context))))

;;; 交互界面

(defun aiaos-open-buffer ()
  "Open the AIAOS interaction buffer."
  (interactive)
  (let ((buf (get-buffer-create aiaos-buffer-name)))
    (with-current-buffer buf
      (aiaos-buffer-mode)
      (goto-char (point-max))
      (unless (> (point-max) 1)
        (insert "AIAOS-CLI Interactive Agent\n")
        (insert "==========================\n")
        (insert "Type your message and press Enter to interact with the agent.\n")
        (insert "Use M-x aiaos-close-buffer to close this buffer.\n\n")))
    (switch-to-buffer buf)
    buf))

(defun aiaos-close-buffer ()
  "Close the AIAOS interaction buffer."
  (interactive)
  (let ((buf (get-buffer aiaos-buffer-name)))
    (when buf
      (kill-buffer buf))))

(define-derived-mode aiaos-buffer-mode fundamental-mode "AIAOS-CLI"
  "Major mode for AIAOS interaction."
  (define-key aiaos-buffer-mode-map (kbd "C-c C-c") 'aiaos-send-current-line)
  (define-key aiaos-buffer-mode-map (kbd "C-c C-k") 'aiaos-close-buffer)
  (font-lock-mode 1))

(defun aiaos-send-current-line ()
  "Send current line to AIAOS agent."
  (interactive)
  (let ((line (string-trim (thing-at-point 'line t))))
    (when (> (length line) 0)
      (aiaos-buffer-append-response (aiaos-message line)))))

(defun aiaos-buffer-append-response (response)
  "Append RESPONSE to the AIAOS buffer."
  (let ((buf (get-buffer aiaos-buffer-name)))
    (when buf
      (with-current-buffer buf
        (goto-char (point-max))
        (insert (format "\nAgent: %s\n" response))
        (goto-char (point-max))))))

;;; 用户交互函数
(defun aiaos-prompt (question &optional default)
  "Prompt user with QUESTION and optional DEFAULT value."
  (interactive)
  (let ((response (read-string question default)))
    (aiaos-log "debug" (format "User prompt response: %s" response))
    response))

(defun aiaos-confirm (message)
  "Confirm with user via MESSAGE.
Returns t if user confirms, nil otherwise."
  (interactive)
  (let ((result (yes-or-no-p message)))
    (aiaos-log "debug" (format "User confirm: %s" result))
    result))

;; 主入口命令
;;;###autoboot
(defun aiaos ()
  "Open AIAOS-CLI interface."
  (interactive)
  (aiaos-init)
  (aiaos-open-buffer))

;;; 初始化函数
(defun aiaos-init (&optional config)
  "Initialize AIAOS system with optional CONFIG."
  (interactive)
  (when config
    (dolist (pair config)
      (aiaos-set-config (car pair) (cdr pair))))
  ;; Set default config if not set
  (unless (aiaos-get-config 'model)
    (aiaos-set-config 'model aiaos-model))
  ;; Initialize providers if configured
  (when aiaos-llm-providers
    (aiaos-build-fallback-chain))
  ;; Start timeout reset monitoring
  (run-at-time aiaos-provider-timeout nil 'aiaos-reset-timeout-if-busy)
  (aiaos-log "info" "AIAOS initialized")
  t)

(provide 'aiaos-cli-core)

;;; TODO: Add more sophisticated LLM integration
;;; TODO: Implement actual context management
;;; TODO: Add tool permission system