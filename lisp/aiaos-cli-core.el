;;; aiaos-cli-core.el - AIAOS-CLI 核心模块（增强版）
;; 提供AIAOS系统的核心功能和交互界面，包含LLM provider管理、错误自愈、连续任务等
;; -*- lexical-binding: t; -*-

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
  "Get LLM provider configuration by NAME.
Supports both alist format ((:name . \"x\") ...) and legacy list format
(name endpoint model api-key)."
  (cl-find-if
   (lambda (p)
     (if (and (listp p) (assq :name p))
         (string-equal (cdr (assq :name p)) name)
       (and (listp p) (string-equal (car p) name))))
   aiaos-llm-providers))

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
(defun aiaos-http--connection-test (url &optional timeout)
  "Return non-nil if a TCP/TLS connection to URL can be established.
Uses `open-network-stream' with a hard TIMEOUT (default 6s); returns nil on
connection failure/timeout.  Reliable and non-blocking, unlike
`url-retrieve-synchronously' which has no interruptible timeout."
  (let* ((parsed (condition-case nil (url-generic-parse-url url) (error nil)))
         (host (and parsed (url-host parsed)))
         (port (and parsed (url-port parsed)))
         (scheme (and parsed (downcase (or (url-type parsed) ""))))
         (secure (string= scheme "https"))
         (timeout (or timeout 6))
         (buf (generate-new-buffer " *aiaos-conn-test*"))
         (proc nil)
         (ok nil))
    (when (and host port)
      (condition-case nil
          (let ((deadline (+ (float-time) timeout)))
            (setq proc (let ((gnutls-verify-error nil))
                         (open-network-stream "aiaos-conn-test" buf host port
                                              :type (if secure 'tls 'plain)
                                              :coding 'binary :buffer buf
                                              :timeout timeout)))
            (while (and (not ok) (not (memq (process-status proc) '(exit signal closed failed)))
                        (< (float-time) deadline))
              (accept-process-output proc 0.2)
              (when (eq (process-status proc) 'open) (setq ok t))))
        (error nil)))
    (when (and proc (processp proc)) (ignore-errors (delete-process proc)))
    (when (buffer-live-p buf) (kill-buffer buf))
    ok))

(defun aiaos-probe-provider (provider)
  "Probe the status of PROVIDER by POSTing a minimal chat/completions request.
Returns:
- 2xx      -> :healthy  (endpoint answers; genuinely usable)
- 4xx/5xx  -> :unstable (endpoint reachable but rejects the probe; still usable)
- nil      -> :down     (connection refused / timeout / network error)"
  (let* ((name (cdr (assq :name provider)))
         (url (aiaos-llm-build-request-url provider))
         (headers (aiaos-llm-build-request-headers provider))
         (probe-timeout 12)
         (min-body (aiaos-llm-build-request-data-full
                    provider (list (aiaos-llm-message-user "ping")) nil nil)))
    (aiaos-log "debug" (format "Probing provider: %s" name))
    (condition-case err
        (let ((resp (aiaos-http-post-json url headers min-body probe-timeout)))
          (cond
           ((null resp)
            ;; http-request 失败：可能是 connection-close 响应（可达）或网络不通。
            ;; 用连接测试区分：连接成功但 API 请求无完整响应 → 保守标 :unstable。
            (if (aiaos-http--connection-test url 6)
                (progn
                  (aiaos-log "warning" (format "Provider %s reachable but no full HTTP response" name))
                  :unstable)
              (progn
                (aiaos-log "warning" (format "Provider %s unreachable (connection refused)" name))
                :down)))
           ((and (car resp) (>= (car resp) 200) (< (car resp) 300))
            (aiaos-log "debug" (format "Provider %s is healthy (HTTP %s)" name (car resp)))
            :healthy)
           (t
            (aiaos-log "warning" (format "Provider %s unstable (HTTP %s)" name (car resp)))
            :unstable)))
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

(defun aiaos-get-next-fallback-provider (current-name)
  "Get the next provider in the fallback chain after CURRENT-NAME."
  (let ((chain aiaos-fallback-chain))
    (if (null chain)
        (progn
          (aiaos-build-fallback-chain)
          (setq chain aiaos-fallback-chain)))
    (if (null chain)
        nil
      (let ((pos (position current-name chain :test 'equal)))
        (if pos
            (if (< (1+ pos) (length chain))
                (nth (1+ pos) chain)
              (car chain))
          (car chain))))))

(defun aiaos-handle-402-error ()
  "Handle HTTP 402 quota/billing errors by switching to the next fallback provider.
If no fallback is available, probes all providers to find a working one."
  (let ((next-provider (aiaos-get-next-fallback-provider
                        (aiaos-get-config 'current-provider))))
    (if next-provider
        (progn
          (aiaos-set-current-provider next-provider)
          (aiaos-log "info" (format "Switched to fallback provider due to 402: %s" next-provider)))
      (progn
        (aiaos-log "warning" "No fallback provider available for 402, probing all providers")
        (aiaos-probe-all-providers)
        (aiaos-build-fallback-chain)
        (let ((fresh-next (aiaos-get-next-fallback-provider
                           (aiaos-get-config 'current-provider))))
          (when fresh-next
            (aiaos-set-current-provider fresh-next)
            (aiaos-log "info" (format "Recovered via provider probe: %s" fresh-next))))))))

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

;;; ============================================================
;;; 纯 elisp HTTP 客户端（替代 Python bridge）
;;; 使用 url-retrieve-synchronously 实现同步 HTTP 请求
;;; ============================================================

(defvar aiaos-http-curl-timeout 120
  "Timeout in seconds for synchronous HTTP requests.")

(defcustom aiaos-llm-request-timeout 12
  "Per-provider HTTP timeout (seconds) for LLM requests.
Short enough that dead/unreachable providers in the fallback chain fail
quickly instead of stalling the whole chain (each timeout adds up)."
  :type 'integer
  :group 'aiaos-llm)

(defun aiaos-http--parse-status (buffer)
  "Parse HTTP status code from response BUFFER."
  (with-current-buffer buffer
    (goto-char (point-min))
    (if (re-search-forward "HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
        (string-to-number (match-string 1))
      nil)))

(defun aiaos-http--extract-body (buffer)
  "Extract response body from HTTP response BUFFER."
  (with-current-buffer buffer
    (goto-char (point-min))
    ;; Find the blank line separating headers from body
    (if (re-search-forward "^\r?\n" nil t)
        (buffer-substring-no-properties (point) (point-max))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun aiaos-http-request (url method headers data &optional timeout)
  "Perform synchronous HTTP(S) request to URL with METHOD, HEADERS, and DATA.

Pure elisp via `open-network-stream' (no url.el, no curl).  401/402/5xx are
returned as ordinary (status . body) results so provider-fallback chains are
never interrupted by url.el's auth/402 branches.

Returns (status-code . body-string), or nil on connection failure/timeout."
  (let* ((timeout-sec (or timeout aiaos-http-curl-timeout 30))
         (parsed (condition-case nil (url-generic-parse-url url) (error nil)))
         (scheme (and parsed (downcase (or (url-type parsed) ""))))
         (host (and parsed (url-host parsed)))
         (port (and parsed (url-port parsed)
                    (if (string= scheme "https") 443 80)))
         (secure (string= scheme "https"))
         (full-path (and parsed (or (url-filename parsed) "/")))
         (proc nil)
         (response-buf (generate-new-buffer " *aiaos-http-response*"))
         (done nil)
         (deadline (+ (float-time) timeout-sec)))
    (unwind-protect
        (condition-case err
            (progn
              (setq proc
                    (let ((gnutls-verify-error nil))
                      (open-network-stream "aiaos-http" response-buf host port
                                           :type (if secure 'tls 'plain)
                                           :coding 'binary
                                           :buffer response-buf
                                           :timeout timeout-sec)))
              (set-process-filter
               proc (lambda (_p chunk)
                      (with-current-buffer response-buf
                        (goto-char (point-max))
                        (insert chunk))))
              (let ((req (concat
                          (format "%s %s HTTP/1.1\r\n" method full-path)
                          (format "Host: %s%s\r\n" host
                                  (if (or (and secure (= port 443))
                                          (and (not secure) (= port 80)))
                                      "" (format ":%d" port)))
                          (mapconcat (lambda (h)
                                       (format "%s: %s\r\n" (car h) (cdr h)))
                                     headers "")
                          (when data (format "Content-Length: %d\r\n" (string-bytes data)))
                          "Connection: close\r\n"
                          "\r\n"
                          (or data ""))))
                (process-send-string proc req))
              ;; 等待响应完成。主检测：Content-Length 匹配或 chunked 结束。
              ;; 进程死亡（connection-close 响应）时 buffer 已有数据即视为完整。
              (while (and (not done) (< (float-time) deadline)
                          (not (memq (process-status proc) '(exit signal closed failed))))
                (when (process-live-p proc)
                  (accept-process-output proc 0.1))
                (with-current-buffer response-buf
                  (goto-char (point-min))
                  (when (re-search-forward "^\r?\n" nil t)
                    (let* ((headers-end (point))
                           (content-length
                            (save-excursion
                              (goto-char (point-min))
                              (if (re-search-forward "^Content-Length:[ \t]*\\([0-9]+\\)" nil t)
                                  (string-to-number (match-string 1)))))
                           (transfer-encoding
                            (save-excursion
                              (goto-char (point-min))
                              (re-search-forward "^Transfer-Encoding:[ \t]*\\([^ \r\n]+\\)" nil t))))
                      (when (or (string= (downcase (or transfer-encoding "")) "chunked")
                                (and content-length
                                     (>= (- (point-max) headers-end) content-length)))
                        (setq done t)))))
                ;; 连接已关闭且已有响应数据 → 响应完整
                (when (and (not done)
                           (>= (buffer-size response-buf) 1)
                           (memq (process-status proc) '(exit signal closed failed)))
                  (setq done t)))
              (if (not done)
                  (progn
                    (aiaos-llm-log "debug" (format "HTTP timeout/no-response: %s" url))
                    nil)
                (let ((raw (with-current-buffer response-buf
                             (buffer-substring-no-properties (point-min) (point-max)))))
                  ;; 响应体是二进制/单字节，解码为 UTF-8 多字节字符串，
                  ;; 否则中文会显示为乱码。
                  (setq raw (decode-coding-string raw 'utf-8))
                  (aiaos-http--parse-response raw))))
          (error
           nil))
       (when (and proc (process-live-p proc)) (delete-process proc))
      (when (buffer-live-p response-buf) (kill-buffer response-buf)))))


(defun aiaos-http--parse-response (raw)
  "Parse raw HTTP response RAW (string) into (status-code . body-string).
Skips leading process-status messages (e.g. \"\\nProcess ... broken by remote
peer\\n\") that Emacs may prepend to the buffer."
  (let ((raw (if (string-match "HTTP/[0-9.]+" raw)
                 (substring raw (match-beginning 0))
               raw)))
    (when (string-match "\\`HTTP/[0-9.]+ \\([0-9]+\\)" raw)
      (let ((status (string-to-number (match-string 1 raw)))
            (headers-end (and (string-match "\r?\n\r?\n" raw)
                              (match-end 0)))
            (body-start (and (string-match "\r?\n\r?\n" raw)
                             (match-end 0))))
        (if (null body-start)
            (cons status "")
          (let ((body (substring raw body-start))
                (is-chunked (string-match-p "^[Tt]ransfer-[Ee]ncoding:[ \t]*chunked" raw)))
            (cons status (if is-chunked (aiaos-http--decode-chunked body) body))))))))

(defun aiaos-http--decode-chunked (str)
  "Decode chunked-transfer-encoded STR to plain body."
  (let ((result "") (pos 0) (len (length str)))
    (while (< pos len)
      (let* ((line-end (or (string-match "\r?\n" str pos) len))
             (size-str (substring str pos line-end))
             (size (string-to-number (car (split-string size-str ";")) 16)))
        (setq pos (min len (1+ line-end)))
        (when (and (> size 0) (<= (+ pos size) len))
          (setq result (concat result (substring str pos (+ pos size))))
          (setq pos (+ pos size))
          (when (string-match "\r?\n" str pos) (setq pos (match-end 0))))
        (when (and (>= size 0) (string= (string-trim size-str) "0"))
          (setq pos len))))
    result))

(defun aiaos-json-parse (str)
  "Parse JSON STR with string keys (alist)."
  (condition-case nil
      (let ((json-object-type 'alist)
            (json-key-type 'string)
            (json-array-type 'list)
            (json-null nil)
            (json-false nil))
        (json-read-from-string str))
    (error str)))

(defun aiaos-http-post-json (url headers json-object &optional timeout)
  "POST JSON-OBJECT (encoded) to URL with HEADERS.
Returns (status-code . parsed-json) or nil on error.
Parsed JSON uses string keys (alist with \"key\" . value pairs)."
  (let* ((json-str (if (stringp json-object) json-object (json-encode json-object)))
         (result (aiaos-http-request url "POST" headers json-str timeout)))
    (when result
      (let ((status (car result))
            (body (cdr result)))
        (cons status (aiaos-json-parse body))))))

(defun aiaos-http-get-json (url &optional headers timeout)
  "GET URL with HEADERS, return (status-code . parsed-json) or nil."
  (let ((result (aiaos-http-request url "GET" headers nil timeout)))
    (when result
      (cons (car result) (aiaos-json-parse (cdr result))))))

;;; === SSE 流式请求（真实流式，非同步模拟）===

(defvar aiaos-sse-done nil
  "Global flag used to signal SSE stream completion from the process filter.
The process filter runs asynchronously; a global is the only reliable way to
share state with the waiting loop under all binding regimes.")

(defun aiaos-http-stream-request (url method headers data event-cb &optional timeout)
  "Perform streaming HTTP(S) POST/GET to URL, parsing SSE events.

Reuses the synchronous `open-network-stream' transport, but reads the response
incrementally and calls EVENT-CB with each parsed SSE `data:' JSON object (an
alist with string keys).  Returns (status-code . full-body-string) on complete
response, or nil on connection failure/timeout.

EVENT-CB is called as (lambda (obj) ...) for every SSE `data:' JSON line.
This gives true incremental streaming while keeping the pure-elisp transport."
  (let* ((timeout-sec (or timeout aiaos-llm-request-timeout 12))
         (parsed (condition-case nil (url-generic-parse-url url) (error nil)))
         (scheme (and parsed (downcase (or (url-type parsed) ""))))
         (host (and parsed (url-host parsed)))
         (port (and parsed (url-port parsed) (if (string= scheme "https") 443 80)))
         (secure (string= scheme "https"))
         (full-path (and parsed (or (url-filename parsed) "/")))
         (proc nil)
         (response-buf (generate-new-buffer " *aiaos-http-stream*"))
         (done nil)
          (deadline (+ (float-time) timeout-sec))
          (acc ""))
    (setq aiaos-sse-done nil)
    (unwind-protect
        (condition-case err
            (progn
              (setq proc
                    (let ((gnutls-verify-error nil))
                      (open-network-stream "aiaos-http-stream" response-buf host port
                                           :type (if secure 'tls 'plain)
                                           :coding 'binary
                                           :buffer response-buf
                                           :timeout timeout-sec)))
               ;; 流式 filter：增量解析 SSE data: 行
               (set-process-filter
                 proc (lambda (_p chunk)
                       (condition-case ferr
                           (progn
                             (with-current-buffer response-buf
                               (goto-char (point-max))
                               (insert chunk))
                             (setq acc (concat acc (decode-coding-string chunk 'utf-8)))
                             ;; 每次只处理 acc 中最后一段（不含末尾换行后的部分行）
                             (let* ((last-nl (string-match "\n[^\n]*\\'" acc))
                                    (proc-len (if last-nl last-nl (length acc)))
                                    (complete (substring acc 0 proc-len)))
                               ;; 逐行处理完整的 data: 行
                               (dolist (line (split-string complete "\n" t))
                                 (let ((trimmed (string-trim line)))
                                   (when (string-match-p "^data:" trimmed)
                                     (let ((payload (string-trim (substring trimmed 5))))
                                       (if (string= payload "[DONE]")
                                           (progn
                                             (setq aiaos-sse-done t)
                                             (when (process-live-p _p) (delete-process _p)))
                                         (condition-case nil
                                              (let ((obj (aiaos-json-parse payload)))
                                                (funcall event-cb obj)
                                               (let* ((choices (and (listp obj) (cdr (assoc "choices" obj))))
                                                      (c0 (and (listp choices) (car choices)))
                                                      (fin (and (listp c0) (cdr (assoc "finish_reason" c0)))))
                                                 (when fin
                                                   (setq aiaos-sse-done t)
                                                   (when (process-live-p _p) (delete-process _p)))))
                                           (error nil)))))))
                               ;; 保留未完整行到 acc 以便下个 chunk 拼接
                                (setq acc (substring acc proc-len))))
                         (error (message "SSE-FILTER-ERR: %S" ferr)))))
              (let ((req (concat
                          (format "%s %s HTTP/1.1\r\n" method full-path)
                          (format "Host: %s%s\r\n" host
                                  (if (or (and secure (= port 443))
                                          (and (not secure) (= port 80)))
                                      "" (format ":%d" port)))
                          (mapconcat (lambda (h) (format "%s: %s\r\n" (car h) (cdr h))) headers "")
                          (when data (format "Content-Length: %d\r\n" (string-bytes data)))
                          "Accept: text/event-stream\r\n"
                          "Connection: close\r\n"
                          "\r\n"
                           (or data ""))))
                (process-send-string proc req))
               ;; 等待响应结束或超时（用非阻塞方式，避免 filter 持续喂数据导致卡死）
               (let ((iters 0)
                     (last-size 0)
                     (stall 0))
                   (while (and (not aiaos-sse-done) (process-live-p proc)
                               (< (float-time) deadline) (< stall 10))
                     (accept-process-output proc 0.2)
                     (setq iters (1+ iters))
                     (let ((sz (buffer-size response-buf)))
                       (if (= sz last-size)
                           (setq stall (1+ stall))
                         (setq stall 0 last-size sz)))
                     (when (or (string-match-p "\\[DONE\\]" acc)
                               (not (process-live-p proc)))
                       (setq aiaos-sse-done t))))
               ;; 若超时但已有响应体，也认为完成（取已接收内容）
               (when (and (not aiaos-sse-done)
                          (>= (buffer-size response-buf) 2))
                 (setq aiaos-sse-done t))
               (let ((raw (with-current-buffer response-buf
                            (buffer-substring-no-properties (point-min) (point-max)))))
                 (aiaos-http--parse-response (decode-coding-string raw 'utf-8))))
          (error
           nil))
      (when (and proc (process-live-p proc)) (delete-process proc))
      (when (buffer-live-p response-buf) (kill-buffer response-buf)))))

;;; Provider 配置加载（从 JSON 配置读取，替代 Python 读取逻辑）

(defvar aiaos-llm-config-file "~/.config/aiaos/llm_providers.json"
  "Path to LLM providers JSON config.")

(defun aiaos-llm--flat-list-to-alist (flat)
  "Convert a flat plist-like FLAT list to an alist.
Example: (\"moonshot\" \"api-key\" \"sk-...\" \"base-url\" \"https://...\" ...)
becomes ((\"name\" . \"moonshot\") (\"api-key\" . \"sk-...\") (\"base-url\" . \"https://...\") ...)."
  (let ((pairs nil)
        (name (car flat))
        (rest (cdr flat)))
    (push (cons "name" name) pairs)
    (while (and rest (cdr rest))
      (push (cons (car rest) (cadr rest)) pairs)
      (setq rest (cddr rest)))
    (nreverse pairs)))

(defun aiaos-llm--provider-from-data (p)
  "Build a provider alist from config entry P.
P may be an alist ({\"name\": ...}) or a flat list ([name \"api-key\" ...])."
  (let* ((p-alist (if (and (listp p) (stringp (car p))
                           (not (assoc "name" p)))
                      (aiaos-llm--flat-list-to-alist p)
                    p))
         (name (or (cdr (assoc "name" p-alist)) "unknown"))
         (base-url (or (cdr (assoc "base-url" p-alist))
                       (cdr (assoc "base_url" p-alist)) ""))
         (model (or (cdr (assoc "model" p-alist)) "gpt-4"))
         (api-key (or (cdr (assoc "api-key" p-alist))
                      (cdr (assoc "api_key" p-alist)) ""))
         (timeout (or (cdr (assoc "timeout" p-alist)) aiaos-provider-timeout)))
    (list (cons :name (format "%s" name))
          (cons :endpoint (format "%s" base-url))
          (cons :model (format "%s" model))
          (cons :api-key (format "%s" api-key))
          (cons :options (list (cons :timeout timeout)))
          (cons :status 'unknown)
          (cons :last-check nil)
          (cons :failure-count 0))))

(defun aiaos-load-llm-providers-from-config ()
  "Load LLM providers from aiaos-llm-config-file.
Handles both formats:
  {\"providers\": [{...}, ...]}
  {\"name\": [...], \"provider\": [flat...], ...} (repeated provider keys)"
  (let ((file (expand-file-name aiaos-llm-config-file)))
    (if (file-exists-p file)
        (condition-case nil
            (let* ((data (aiaos-json-parse (with-temp-buffer
                                              (insert-file-contents file)
                                              (buffer-string))))
                   (providers-list (cdr (assoc "providers" data)))
                   (providers (if providers-list
                                  providers-list
                                (mapcar #'cdr
                                        (cl-remove-if (lambda (e)
                                                        (not (and (listp e) (equal (car e) "provider"))))
                                                      data)))))
              (mapcar #'aiaos-llm--provider-from-data providers))
          (error nil))
      nil)))

(defun aiaos-ensure-llm-providers ()
  "Ensure aiaos-llm-providers is populated from config if empty."
  (when (and (null aiaos-llm-providers)
             (file-exists-p (expand-file-name aiaos-llm-config-file)))
    (setq aiaos-llm-providers (aiaos-load-llm-providers-from-config)))
  aiaos-llm-providers)

;;; 响应解析（OpenAI 兼容格式）

(defun aiaos-extract-response-content (result)
  "Extract text content from LLM RESULT (parsed JSON alist, string keys)."
  (let ((choices (cdr (assoc "choices" result))))
    (when (and choices (listp choices))
      (let* ((choice (car choices))
             (message (and (listp choice) (cdr (assoc "message" choice))))
             (content (if (and message (listp message)) (cdr (assoc "content" message)) nil)))
        (when (and content (stringp content))
          content)))))

(defun aiaos-extract-response-tool-calls (result)
  "Extract tool calls from LLM RESULT (parsed JSON alist, string keys)."
  (let ((choices (cdr (assoc "choices" result))))
    (when (and choices (listp choices))
      (let* ((choice (car choices))
             (message (and (listp choice) (cdr (assoc "message" choice)))))
        (when (and message (listp message))
          (cdr (assoc "tool_calls" message)))))))

(defun aiaos-extract-response-error (result)
  "Extract error message from LLM RESULT (parsed JSON alist, string keys)."
  (let ((error-obj (cdr (assoc "error" result))))
    (when error-obj
      (if (stringp error-obj)
          error-obj
        (or (cdr (assoc "message" error-obj))
            (format "%s" error-obj))))))

;;; 核心 elisp LLM 调用（替代 Python bridge 的单一请求）
;;; 遍历 provider fallback 链，直到成功或全部失败

;;; 请求构建函数（core 自包含；aiaos-cli-llm.el 加载时以相同实现覆盖）
(defun aiaos-llm-build-request-url (provider)
  "Build request URL for PROVIDER.
R1324: 确保 endpoint 与 /chat/completions 之间无重复斜杠。"
  (let ((endpoint (cdr (assq :endpoint provider)))
        (model (cdr (assq :model provider))))
    (if (string-match-p "/chat/completions$" endpoint)
        endpoint
      (concat (string-trim-right endpoint "/") "/chat/completions"))))

(defun aiaos-llm-build-request-headers (provider)
  "Build request headers for PROVIDER.
Only includes options that are string-keyed (valid HTTP header names)."
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
           :max_tokens 2000))))

(defun aiaos-llm-format-messages (message context)
  "Format MESSAGE and CONTEXT into API messages array."
  (let ((messages nil))
    (when (and context (listp context))
      (let ((system-msg (cdr (assq :system context))))
        (when system-msg
          (push (list (cons :role "system") (cons :content system-msg)) messages))))
    (push (list (cons :role "user") (cons :content message)) messages)
    (nreverse messages)))

;;; === 全能力 LLM 请求构建（消息数组 + 工具 + 流式）===

(defun aiaos-llm-build-request-data-full (provider messages &optional tools stream)
  "Build full request data for PROVIDER with MESSAGES array, TOOLS, and STREAM.
MESSAGES is a list of OpenAI-format message alists (role/content/tool_calls/
tool_call_id).  TOOLS is the OpenAI `tools' array.  STREAM non-nil adds
:stream t.  Returns a JSON string."
  (let ((model (cdr (assq :model provider))))
    (json-encode
     (delq nil
           (append (list :model model
                         :messages messages
                         :temperature 0.7
                         :max_tokens 2000)
                   (when tools (list :tools tools))
                   (when stream (list :stream t)))))))

(defun aiaos-llm-message-user (content)
  "Build a user MESSAGE alist with CONTENT."
  (list (cons :role "user") (cons :content content)))

(defun aiaos-llm-message-system (content)
  "Build a system MESSAGE alist with CONTENT."
  (list (cons :role "system") (cons :content content)))

(defun aiaos-llm-message-assistant (content &optional tool-calls)
  "Build an assistant MESSAGE alist with CONTENT and optional TOOL-CALLS."
  (let ((m (list (cons :role "assistant")
                 (cons :content (or content "")))))
    (when tool-calls
      (setq m (append m (list (cons :tool_calls tool-calls)))))
    m))

(defun aiaos-llm-message-tool (tool-call-id content)
  "Build a tool-result MESSAGE alist with TOOL-CALL-ID and CONTENT."
  (list (cons :role "tool")
        (cons :tool_call_id tool-call-id)
        (cons :content (format "%s" content))))

(defun aiaos-llm-tool-call-to-message (call)
  "Convert a raw tool CALL alist to the assistant-message tool_calls entry.
The OpenAI response gives {\"id\":..., \"type\":\"function\", \"function\":
{\"name\":..., \"arguments\":...}}.  Returns the same shape (keyword keys)."
  (let ((func-obj (if (listp call) (cdr (assq 'function call)) nil)))
    (list (cons :id (or (cdr (assq 'id call)) ""))
          (cons :type "function")
          (cons :function
                (list (cons :name (and func-obj (cdr (assq 'name func-obj))))
                      (cons :arguments (and func-obj (cdr (assq 'arguments func-obj)))))))))

(defun aiaos-llm-tool-call-parse-args (call)
  "Parse the arguments JSON string of tool CALL into an alist (keyword keys).
Returns nil on parse failure or if no arguments."
  (let ((func-obj (if (listp call)
                      (or (cdr (assq 'function call))
                          (cdr (assoc "function" call)))
                      nil)))
    (when func-obj
      (let ((args-str (or (cdr (assq 'arguments func-obj))
                          (cdr (assoc "arguments" func-obj)))))
        (when args-str
          (condition-case nil
              (json-read-from-string args-str)
            (error nil)))))))

(defun aiaos-llm-tool-call-name (call)
  "Extract tool name from CALL alist."
  (let ((func-obj (if (listp call)
                      (or (cdr (assq 'function call))
                          (cdr (assoc "function" call)))
                      nil)))
    (and func-obj (or (cdr (assq 'name func-obj))
                      (cdr (assoc "name" func-obj))))))

(defun aiaos-llm-log (level message)
  "Log a message at given LEVEL."
  (message "[AIAOS-LLM-%s] %s" level message))

(defun aiaos-llm-extract-system-message (context)
  "Extract system message from CONTEXT."
  (when (and context (listp context))
    (cdr (assq :system context))))

(defun aiaos--call-llm-http (message &optional agent session-id)
  "Pure elisp LLM call with MESSAGE.
Loads providers from config, tries each in order until success.
Returns alist (reply . content) (tool_calls . calls) (provider . name) (error . msg) or nil."
  (aiaos-ensure-llm-providers)
  (let ((providers aiaos-llm-providers)
        (attempts nil)
        (last-error nil)
        (success nil)
        (round 0)
        (max-rounds 2))           ; R-FALLBACK-LOOP: 切换完一轮后从头再循环一轮
    (if (null providers)
        (list (cons 'error "no_providers")
              (cons 'message "没有配置任何 LLM provider"))
      (progn
        (while (and (not success) (< round max-rounds))
          (setq round (1+ round))
          (dolist (provider providers)
            (let* ((name (cdr (assq :name provider)))
                   (endpoint (cdr (assq :endpoint provider)))
                   (api-key (cdr (assq :api-key provider)))
                   (model (cdr (assq :model provider)))
                   (url (aiaos-llm-build-request-url provider))
                   (headers (aiaos-llm-build-request-headers provider))
                   (request-data (aiaos-llm-build-request-data provider message session-id))
                   (resp (aiaos-http-post-json url headers request-data
                                               aiaos-llm-request-timeout))
                   (status (and resp (car resp)))
                   (result (and resp (cdr resp))))
              (if (and resp status (>= status 200) (< status 300))
                  (let ((content (if (stringp result) result (aiaos-extract-response-content result)))
                        (tool-calls (if (stringp result) nil (aiaos-extract-response-tool-calls result))))
                    (setq success (list (cons 'reply (or content ""))
                                        (cons 'tool_calls tool-calls)
                                        (cons 'provider name)
                                        (cons 'session_id (or session-id "")))))
                ;; 失败，记录错误，继续下一个 provider
                (let ((err-msg (if (and result (listp result))
                                   (or (aiaos-extract-response-error result)
                                       (format "HTTP %s" status))
                                 (format "HTTP %s" status))))
                  (push (format "%s:%s" name err-msg) attempts)
                  (setq last-error err-msg))))))
        ;; 成功返回成功结果；全部失败返回 fallback_exhausted
        (or success
            (list (cons 'error "fallback_exhausted")
                   (cons 'message (or last-error "所有 LLM provider 均不可用"))
                   (cons 'permanent t)
                   (cons 'attempts (nreverse attempts))))))))

;;; === 全能力 LLM 引擎：消息数组 + 工具 + 流式（纯 elisp）===

(defun aiaos-llm--tool-call-get (call field &optional default)
  "Get FIELD from tool CALL alist, trying both string and keyword keys."
  (or (cdr (assoc field call))
      (cdr (assq (intern field) call))
      default))

(defun aiaos-llm--merge-tool-calls (acc new-calls)
  "Merge NEW-CALLS (streamed tool_call delta fragments) into ACC.
Streaming splits a tool call across multiple deltas with the same `index';
merge them by index, concatenating `arguments' and keeping the first non-empty
`id' and `name'.  Returns the merged list of tool call alists."
  (let ((result (copy-sequence acc)))
    (dolist (nc new-calls result)
      (let* ((idx (aiaos-llm--tool-call-get nc "index" nil))
             (nfun (aiaos-llm--tool-call-get nc "function" nil))
             (nname (and nfun (aiaos-llm--tool-call-get nfun "name" nil)))
             (nargs (and nfun (aiaos-llm--tool-call-get nfun "arguments" "")))
             (nid (aiaos-llm--tool-call-get nc "id" ""))
             (existing (and idx (cl-find idx result
                                         :key (lambda (c) (aiaos-llm--tool-call-get c "index" nil))
                                         :test 'equal))))
        (if existing
            ;; 合并到已有条目：拼接 arguments，补全 id/name
            (let* ((efun (aiaos-llm--tool-call-get existing "function" nil))
                   (eargs (and efun (aiaos-llm--tool-call-get efun "arguments" "")))
                   (merged-fun (list (cons "name" (or (and nname (not (string= nname "")) nname)
                                                      (and efun (aiaos-llm--tool-call-get efun "name" nil))))
                                     (cons "arguments" (concat (or eargs "") (or nargs ""))))))
              (setcar existing (cons "id" (or (and nid (not (string= nid "")) nid)
                                              (aiaos-llm--tool-call-get existing "id" ""))))
              (setcdr existing (cons (cons "index" idx)
                                     (cons (cons "type" (or (aiaos-llm--tool-call-get nc "type" "function")
                                                            (aiaos-llm--tool-call-get existing "type" "function")))
                                           (list (cons "function" merged-fun))))))
          ;; 新条目
          (push (list (cons "id" nid)
                      (cons "index" idx)
                      (cons "type" (aiaos-llm--tool-call-get nc "type" "function"))
                      (cons "function" (list (cons "name" nname)
                                             (cons "arguments" (or nargs "")))))
                result))))))

(defun aiaos-llm--http-once (messages &optional tools stream on-event)
  "Send MESSAGES (with TOOLS, optionally STREAM) to the LLM once.
Tries each provider in order until one succeeds.  Returns an alist:
  (reply . content) (tool_calls . calls) (provider . name) (error . msg)
  (permanent . bool) (streamed . bool)
If STREAM is non-nil and ON-EVENT is a function, uses real SSE streaming and
calls ON-EVENT with each parsed delta object.  Returns the final accumulated
reply in `reply'."
  (aiaos-ensure-llm-providers)
  (let ((providers aiaos-llm-providers)
        (attempts nil)
        (last-error nil)
        (success nil)
        (round 0)
        (max-rounds 2))           ; R-FALLBACK-LOOP: 切换完一轮后从头再循环一轮
    (if (null providers)
        (list (cons 'error "no_providers")
              (cons 'message "没有配置任何 LLM provider"))
      (while (and (not success) (< round max-rounds))
        (setq round (1+ round))
        (dolist (provider providers)
          (when (not success)
          (let* ((name (cdr (assq :name provider)))
                 (url (aiaos-llm-build-request-url provider))
                 (headers (aiaos-llm-build-request-headers provider))
                 (request-data (aiaos-llm-build-request-data-full provider messages tools (and stream on-event)))
                 (stream-acc "")
                 (stream-tool-calls nil)
                 (stream-cb (if (and stream on-event)
                                (lambda (obj)
                                  ;; 累积流式内容到 stream-acc
                                  (let* ((choices (and (listp obj) (cdr (assoc "choices" obj))))
                                         (c0 (and (listp choices) (car choices)))
                                         (delta (and (listp c0) (cdr (assoc "delta" c0))))
                                         (content (and (listp delta) (cdr (assoc "content" delta))))
                                         (reasoning (and (listp delta) (cdr (assoc "reasoning" delta))))
                                         (reasoning-c (and (listp delta) (cdr (assoc "reasoning_content" delta))))
                                         (delta-tc (and (listp delta) (cdr (assoc "tool_calls" delta)))))
                                    (when (and content (stringp content) (not (string= content "")))
                                      (setq stream-acc (concat stream-acc content)))
                                    (when (and reasoning (stringp reasoning))
                                      (setq stream-acc (concat stream-acc reasoning)))
                                    (when (and reasoning-c (stringp reasoning-c))
                                      (setq stream-acc (concat stream-acc reasoning-c)))
                                     (when delta-tc
                                       (setq stream-tool-calls
                                             (aiaos-llm--merge-tool-calls stream-tool-calls delta-tc)))
                                     (funcall on-event obj)))
                              nil))
                 (resp (if (and stream on-event)
                           (aiaos-http-stream-request url "POST" headers request-data stream-cb aiaos-llm-request-timeout)
                         (aiaos-http-post-json url headers request-data aiaos-llm-request-timeout)))
                  (status (and resp (car resp)))
                  (result (and resp (cdr resp))))
              (if (and resp status (>= status 200) (< status 300)
                      (or (not (and stream on-event))
                          (not (string= stream-acc ""))
                          ;; R-SSE-FALLBACK: SSE 未解析出 content 但 HTTP 200 且有
                          ;; 完整响应体（connection-close 场景），用 body 兜底提取，
                          ;; 避免流式 provider 被误判为失败。
                          (and (stringp result) (not (string= result "")))))
                  (let ((content (if (and stream (not (string= stream-acc "")))
                                    stream-acc
                                  (if (stringp result)
                                      ;; R-SSE-FALLBACK: result 是原始 body 字符串，
                                      ;; 先 parse 再提取 content（stream-acc 为空时）
                                      (condition-case nil
                                          (aiaos-extract-response-content (aiaos-json-parse result))
                                        (error result))
                                    (aiaos-extract-response-content result))))
                        (tool-calls (or (and stream stream-tool-calls)
                                        (if (stringp result) nil (aiaos-extract-response-tool-calls result)))))
                    (setq success (list (cons 'reply (or content ""))
                                        (cons 'tool_calls tool-calls)
                                        (cons 'provider name)
                                        (cons 'session_id (or "" ""))
                                        (cons 'streamed (and stream on-event)))))
              (let ((err-msg (if (and result (listp result))
                                  (or (aiaos-extract-response-error result) (format "HTTP %s" status))
                                (format "HTTP %s" status))))
                 (push (format "%s:%s" name err-msg) attempts)
                 (setq last-error err-msg)))))))
      (or success
          (list (cons 'error "fallback_exhausted")
                (cons 'message (or last-error "所有 LLM provider 均不可用"))
                (cons 'permanent t)
                (cons 'attempts (nreverse attempts)))))))

(defun aiaos-llm-execute-tool-arg (call)
  "Execute a single tool CALL (OpenAI format), return (id name result-string)."
  (let* ((id (or (cdr (assq 'id call)) ""))
         (name (aiaos-llm-tool-call-name call))
         (args (aiaos-llm-tool-call-parse-args call))
         (result (if name
                     (aiaos-llm-tool-call name (or args nil))
                   "Tool name missing")))
    (list id name (format "%s" result))))

(defun aiaos-llm-full-chat (messages &optional tools max-iters on-event)
  "Run a full LLM chat loop with MESSAGES and TOOLS.

Loops: send MESSAGES -> if the model returns tool_calls, execute each tool,
append assistant + tool-result messages, and repeat (up to MAX-ITERS).  Stops
when the model returns a plain text reply.  Returns the final reply string.

ON-EVENT, if non-nil, is called with each SSE delta object during streaming."
  (let ((msgs messages)
        (tools (or tools (and (fboundp 'aiaos-llm-build-tools-schema)
                              (aiaos-llm-build-tools-schema))))
        (iters (or max-iters 10))
        (i 0)
        (final-reply nil))
    (while (and (not final-reply) (< i iters))
      (setq i (1+ i))
      (let ((result (aiaos-llm--http-once msgs tools t on-event)))
        (let ((reply (cdr (assq 'reply result)))
              (tool-calls (cdr (assq 'tool_calls result)))
              (error-msg (cdr (assq 'error result)))
              (permanent (cdr (assq 'permanent result))))
          (cond
           ((or permanent (and error-msg (string= error-msg "fallback_exhausted")))
            (error "fallback_exhausted: 所有 LLM provider 均不可用"))
           (tool-calls
            ;; 追加 assistant 消息（含 tool_calls）+ 各工具结果，再继续
            (setq msgs (append msgs
                               (list (aiaos-llm-message-assistant "" tool-calls))))
            (dolist (call tool-calls)
              (let* ((info (aiaos-llm-execute-tool-arg call))
                     (tid (nth 0 info))
                     (tname (nth 1 info))
                     (tresult (nth 2 info)))
                (when on-event
                  (funcall on-event (list (cons 'type "tool_call")
                                          (cons 'name tname)
                                          (cons 'args (and call (cdr (assq 'function call)))))))
                (when on-event
                  (funcall on-event (list (cons 'type "tool_result")
                                          (cons 'name tname)
                                          (cons 'result tresult))))
                (setq msgs (append msgs
                                   (list (aiaos-llm-message-tool tid tresult)))))))
           ((and reply (> (length (format "%s" reply)) 0))
            (setq final-reply (format "%s" reply)))
           (error-msg
            (error "LLM error: %s" error-msg))
           (t
            (error "LLM returned empty reply"))))))
    (or final-reply "")))

(defun aiaos-llm-chat-stream (message &optional system-prompt callback)
  "Convenience: run a full LLM chat for MESSAGE with streaming.
SYSTEM-PROMPT is prepended as a system message if non-nil.  CALLBACK is called
with each event object (hash/alist: type/content/name/args/result).  Returns
the final reply string."
  (let ((messages (append (when system-prompt
                            (list (aiaos-llm-message-system system-prompt)))
                          (list (aiaos-llm-message-user message)))))
    (aiaos-llm-full-chat messages nil 10 callback)))

;;; 核心 LLM 调用函数（增强版）
(defun aiaos-call-llm (message context &optional provider-name)
  "Call LLM with MESSAGE and CONTEXT, optionally specifying PROVIDER-NAME.
Returns the response content."
  (let* ((provider (if provider-name
                      (aiaos-get-llm-provider provider-name)
                    (aiaos-get-current-provider)))
         (max-retries aiaos-max-retries)
         (attempt 0)
         (response nil))
    (while (and (not response) (< attempt max-retries))
      (condition-case caught-err
          (progn
            (aiaos-log "debug"
                       (format "LLM call attempt %d/%d with provider %s"
                               (1+ attempt) max-retries
                               (or (and provider (cdr (assq :name provider))) "unknown")))
            (setq response (aiaos-do-llm-request provider message context))
            (when response
              (if (fboundp 'aiaos-llm-update-provider-status)
                  (aiaos-llm-update-provider-status provider :healthy)
                (aiaos-llm-log "debug"
                               (format "Provider %s healthy"
                                       (or (and provider (cdr (assq :name provider))) "unknown"))))))
        (error
         (aiaos-log "error"
                    (format "LLM call failed (attempt %d): %s"
                            (1+ attempt) caught-err))
         (when provider
           (let ((next-provider (aiaos-get-next-fallback-provider
                                 (cdr (assq :name provider)))))
             (when next-provider
               (aiaos-log "info"
                          (format "Falling back to provider: %s" next-provider))
               (setq provider (aiaos-get-llm-provider next-provider))
               (aiaos-set-current-provider next-provider))))
         (sleep-for 0.5)
         (setq attempt (1+ attempt)))))
    (if response
        response
      (aiaos-log "warning" "Bridge unavailable, returning mock response (task chain continues)")
      (format "（模拟回复）LLM bridge 暂不可用，任务继续: %s" message))))

(defun aiaos--call-bridge (message &optional agent)
  "Call the LLM with MESSAGE and return parsed reply.
Pure elisp implementation via `aiaos--call-llm-http'. 返回 alist 或 nil."
  (aiaos--call-llm-http message agent nil))

(defun aiaos-do-llm-request (provider message context)
  "Perform actual LLM request to PROVIDER with MESSAGE and CONTEXT.
Pure elisp implementation using synchronous HTTP.  Returns text content."
  (let ((result (aiaos--call-llm-http message nil nil)))
    (if result
        (let ((reply (cdr (assq 'reply result)))
              (error-msg (cdr (assq 'error result)))
              (fallback-exhausted (cdr (assq 'permanent result))))
          (cond
           ((or fallback-exhausted
                (and error-msg (string= error-msg "fallback_exhausted")))
            (error "fallback_exhausted: 所有 LLM provider 均不可用"))
           ((and reply (> (length (format "%s" reply)) 0))
            (format "%s" reply))
           (error-msg
            (error "LLM error: %s" error-msg))
           (t
            (error "LLM returned empty reply"))))
      (error "Bridge unavailable"))))

;;; 错误处理函数
(defun aiaos-handle-error (error context)
  "Handle general errors with context."
  (aiaos-log "error" (format "Error: %s" error))
  (condition-case nil
      (aiaos-recover-from-error error context)
    (error nil))
  nil)

(defun aiaos-recover-from-error (error context)
  "Attempt to recover from ERROR with CONTEXT.
R2903: 任何 API 错误（无论错误码）一律先尝试切换 provider，
与 Python bridge 的 FallbackRouter 策略保持一致。"
  (aiaos-log "info" "Attempting error recovery")
  (let ((err-msg (error-message error)))
    ;; R2903: 任何 HTTP/timeout/connection 错误 → 立即切换 provider
    (if (or (string-match-p "HTTP\|timeout\|402\|429\|50[0-9]\|connection\|refused\|network\|failed" err-msg)
            (string-match-p "error\|Error\|fail\|Fail" err-msg))
        (aiaos-handle-provider-switch err-msg)
      (aiaos-handle-generic-error))))

(defun aiaos-handle-provider-switch (err-msg)
  "Switch to next fallback provider for ERR-MSG.
If no fallback available, probe all providers to find a working one."
  (let ((next-provider (aiaos-get-next-fallback-provider
                        (aiaos-get-config 'current-provider))))
    (if next-provider
        (progn
          (aiaos-set-current-provider next-provider)
          (aiaos-log "info" (format "Switched to fallback provider: %s (error: %s)"
                                   next-provider
                                   (substring err-msg 0 (min 60 (length err-msg))))))
      (progn
        (aiaos-log "warning" "No fallback in chain, probing all providers")
        (aiaos-probe-all-providers)
        (aiaos-build-fallback-chain)
        (let ((fresh-next (aiaos-get-next-fallback-provider
                           (aiaos-get-config 'current-provider))))
          (when fresh-next
            (aiaos-set-current-provider fresh-next)
            (aiaos-log "info" (format "Recovered via probe: %s" fresh-next))))))))

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
      (let ((ctx (or context (and (boundp 'aiaos-context) aiaos-context))))
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