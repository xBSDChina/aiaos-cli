;;; aiaos-cli-history.el - AIAOS-CLI 历史记录与上下文记忆增强
;;; 提供历史记录浏览、编辑、重新发送，以及跨 provider 的上下文记忆

(require 'aiaos-cli-core)

;;; 配置
(defgroup aiaos-history nil
  "AIAOS-CLI history configuration."
  :group 'aiaos)

(defcustom aiaos-history-max-entries 100
  "Maximum number of history entries to keep."
  :type 'integer
  :group 'aiaos-history)

(defcustom aiaos-history-file "~/.aiaos-history.el"
  "File for persistent history storage."
  :type 'string
  :group 'aiaos-history)

(defcustom aiaos-context-memory-enabled t
  "Enable context memory across provider switches."
  :type 'boolean
  :group 'aiaos-history)

;;; 历史记录数据结构
(let ((history-list nil)
      (history-index -1)
      (context-memory (make-hash-table :test 'equal)))
  (setq history-list nil)
  (setq history-index -1))

;;; 上下文记忆管理
(defun aiaos-context-memory-store (key value)
  "Store KEY with VALUE in context memory."
  (puthash key value aiaos-context-memory)
  (aiaos-context-memory-save))

(defun aiaos-context-memory-retrieve (key)
  "Retrieve value for KEY from context memory."
  (gethash key aiaos-context-memory))

(defun aiaos-context-memory-save ()
  "Save context memory to file."
  (let ((buf (get-buffer-create "*aiaos-context*")))
    (with-current-buffer buf
      (erase-buffer)
      (princ "(" (current-buffer))
      (maphash (lambda (k v)
                  (princ (format "(%s . %s) " k v) (current-buffer)))
                aiaos-context-memory)
      (princ ")" (current-buffer))
      (write-file aiaos-context-memory-file)))

(defun aiaos-context-memory-load ()
  "Load context memory from file."
  (if (file-exists-p aiaos-context-memory-file)
      (with-temp-buffer
        (insert-file-contents aiaos-context-memory-file)
        (goto-char (point-min))
        (condition-case nil
            (read (current-buffer))
          (error nil)))
    (make-hash-table :test 'equal)))

;; 初始化上下文记忆
(with-current-buffer (get-buffer-create "*aiaos-context*")
  (erase-buffer)
  (princ "(" (current-buffer))
  (maphash (lambda (k v)
              (princ (format "(%s . %s) " k v) (current-buffer)))
            aiaos-context-memory)
  (princ ")" (current-buffer)))

;;; 历史记录管理
(defun aiaos-history-add (message)
  "Add MESSAGE to history."
  (when message
    (let ((entry (list :message message
                       :timestamp (current-time)
                       :provider (aiaos-get-config 'current-provider))))
      (push entry history-list)
      ;; Trim history if too long
      (when (> (length history-list) aiaos-history-max-entries)
        (nthcdr (1- aiaos-history-max-entries) history-list))
      (aiaos-history-save)
      (aiaos-log "debug" (format "Added to history: %s" (substring message 0 (min 50 (length message))))))))

(defun aiaos-history-save ()
  "Save history to file."
  (let ((buf (get-buffer-create "*aiaos-history*")))
    (with-current-buffer buf
      (erase-buffer)
      (princ "(" (current-buffer))
      (dolist (entry history-list)
        (princ (format "(%s . %s) "
                       (format-time-string "%Y-%m-%dT%H:%M:%S" (cdr (assq :timestamp entry)))
                       (prin1-to-string (cdr (assq :message entry))))
               (current-buffer)))
      (princ ")" (current-buffer))
      (write-file aiaos-history-file))))

(defun aiaos-history-load ()
  "Load history from file."
  (if (file-exists-p aiaos-history-file)
      (with-temp-buffer
        (insert-file-contents aiaos-history-file)
        (goto-char (point-min))
        (condition-case nil
            (let ((data (read (current-buffer))))
              (dolist (pair data)
                (push (list :message (cdr pair)
                           :timestamp (date-to-time (car pair))
                           :provider (aiaos-get-config 'current-provider)))
                     history-list)))
          (error nil)))
    (setq history-list nil)))

;; 初始化历史记录
(aiaos-history-load)

;;; 历史导航
(defun aiaos-history-previous ()
  "Navigate to previous history entry."
  (interactive)
  (when history-list
    (if (= history-index -1)
        (setq history-index 0)
      (when (< history-index (1- (length history-list)))
        (setq history-index (1+ history-index))))
    (when (>= history-index 0)
      (let ((entry (nth history-index history-list)))
        (when entry
          (aiaos-buffer-insert-at-point (cdr (assq :message entry))))))))

(defun aiaos-history-next ()
  "Navigate to next history entry."
  (interactive)
  (when (> history-index 0)
    (setq history-index (1- history-index))
    (let ((entry (nth history-index history-list)))
      (when entry
        (aiaos-buffer-insert-at-point (cdr (assq :message entry)))))))

(defun aiaos-buffer-insert-at-point (text)
  "Insert TEXT at point in current buffer."
  (insert text)
  (goto-char (point-max)))

;;; 增强的 Buffer 模式
(define-derived-mode aiaos-history-buffer-mode fundamental-mode "AIAOS-History"
  "Major mode for AIAOS history browsing."
  (define-key aiaos-history-buffer-mode-map (kbd "<up>") 'aiaos-history-previous-line)
  (define-key aiaos-history-buffer-mode-map (kbd "<down>") 'aiaos-history-next-line)
  (define-key aiaos-history-buffer-mode-map (kbd "<prior>") 'aiaos-history-page-up)
  (define-key aiaos-history-buffer-mode-map (kbd "<next>") 'aiaos-history-page-down)
  (define-key aiaos-history-buffer-mode-map (kbd "e") 'aiaos-history-edit-entry)
  (define-key aiaos-history-buffer-mode-map (kbd "RET") 'aiaos-history-view-entry)
  (define-key aiaos-history-buffer-mode-map (kbd "C-c C-c") 'aiaos-history-send-edited)
  (font-lock-mode 1))

(defun aiaos-history-previous-line ()
  "Move to previous line in history buffer."
  (interactive)
  (forward-line -1)
  (aiaos-history-highlight-current-line))

(defun aiaos-history-next-line ()
  "Move to next line in history buffer."
  (interactive)
  (forward-line 1)
  (aiaos-history-highlight-current-line))

(defun aiaos-history-page-up ()
  "Page up in history buffer."
  (interactive)
  (scroll-down)
  (aiaos-history-highlight-current-line))

(defun aiaos-history-page-down ()
  "Page down in history buffer."
  (interactive)
  (scroll-up)
  (aiaos-history-highlight-current-line))

(defun aiaos-history-highlight-current-line ()
  "Highlight the current line in history buffer."
  (when (and (boundp 'aiaos-history-overlay) aiaos-history-overlay)
    (delete-overlay aiaos-history-overlay))
  (let ((overlay (make-overlay (line-beginning-position) (line-end-position))))
    (overlay-put overlay 'face '( :background "blue" :foreground "white"))
    (setq aiaos-history-overlay overlay)))

(defconst aiaos-history-overlay nil
  "Overlay for highlighting current history line.")

(defun aiaos-history-edit-entry ()
  "Edit the current history entry."
  (interactive)
  (let ((line (thing-at-point 'line t)))
    (when line
      (let ((edited (read-string "Edit: " (string-trim line))))
        (when (> (length edited) 0)
          (delete-region (line-beginning-position) (line-end-position))
          (insert edited)
          (aiaos-log "debug" (format "Edited history entry: %s" edited)))))))

(defun aiaos-history-view-entry ()
  "View the full current history entry."
  (interactive)
  (let ((line (thing-at-point 'line t)))
    (when line
      (message "History: %s" (string-trim line)))))

(defun aiaos-history-send-edited ()
  "Send the edited history entry to LLM."
  (interactive)
  (let ((line (thing-at-point 'line t)))
    (when line
      (let ((message (string-trim line)))
        (when (> (length message) 0)
          (aiaos-history-add message)
          (aiaos-send-message message))))))

;;; 增强的发送函数
(defun aiaos-send-message (message)
  "Send MESSAGE to LLM and handle response."
  (condition-case err
      (let ((response (aiaos-message message)))
        (aiaos-buffer-append-response response)
        (aiaos-context-memory-store (format "msg-%s" (format-time-string "%H:%M:%S"))
                                    (list :user message :agent response))
        response)
    (error
     (aiaos-handle-error err (aiaos-context-memory-retrieve 'current-context))
     nil)))

;;; 增强的上下文记忆
(defun aiaos-context-memory-switch-provider (new-provider)
  "Switch to NEW-PROVIDER and preserve context memory."
  (when aiaos-context-memory-enabled
    (aiaos-context-memory-store 'last-provider (aiaos-get-config 'current-provider))
    (aiaos-set-current-provider new-provider)
    (aiaos-context-memory-store 'current-provider new-provider)
    (aiaos-log "info" (format "Switched to provider %s with context preserved" new-provider))))

;;; 历史浏览界面
(defun aiaos-show-history ()
  "Show history in a dedicated buffer."
  (interactive)
  (let ((buf (get-buffer-create "*AIAOS-History*")))
    (with-current-buffer buf
      (aiaos-history-buffer-mode)
      (erase-buffer)
      (insert "AIAOS-CLI History\n")
      (insert "===============\n")
      (insert "Use up/down arrows to navigate, Enter to view, e to edit, C-c C-c to send.\n\n")
      (dolist (entry (reverse history-list))
        (let ((msg (cdr (assq :message entry)))
              (time (format-time-string "%H:%M:%S" (cdr (assq :timestamp entry)))))
          (insert (format "[%s] %s\n" time (substring msg 0 (min 80 (length msg)))))))
      (goto-char (point-min))
      (forward-line 2))
    (switch-to-buffer buf)
    buf))

;;; 自动保存上下文记忆
(add-hook 'kill-buffer-hook
          (lambda ()
            (when (string-match-p "\\*AIAOS" (buffer-name))
              (aiaos-context-memory-save))))

(add-hook 'kill-emacs-hook
          (lambda ()
            (aiaos-context-memory-save)
            (aiaos-history-save)))

;;; 集成到现有系统
(after-load 'aiaos-cli-core
  (define-key aiaos-buffer-mode-map (kbd "<up>") 'aiaos-history-previous)
  (define-key aiaos-buffer-mode-map (kbd "<down>") 'aiaos-history-next)
  (define-key aiaos-buffer-mode-map (kbd "<prior>") 'aiaos-history-page-up)
  (define-key aiaos-buffer-mode-map (kbd "<next>") 'aiaos-history-page-down)
  (define-key aiaos-buffer-mode-map (kbd "C-c C-h") 'aiaos-show-history))

(provide 'aiaos-cli-history)