;;; head-tail.el --- file-tools skill: head-tail command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-file-tools/head-tail (args &rest options)
  "Extract the first or last N lines of a file.

ARGS is a plist with :path.
OPTIONS is a plist with :lines (default 10) and :mode (head|tail)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (path (plist-get args :path))
         (n (let ((raw (or (plist-get opts :lines) 10)))
           (if (stringp raw)
               (condition-case _
                   (string-to-number raw)
                 (error 10))
             raw)))
         (mode (or (plist-get opts :mode) "head")))
    (cond
     ((or (null path) (not (stringp path)) (string= path ""))
      (list :status "error" :code "INVALID_ARGS"
            :message "path 不能为空"
            :skill "file-tools" :command "head-tail"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     ((and (not (string= mode "head")) (not (string= mode "tail")))
      (list :status "error" :code "INVALID_ARGS"
            :message (format "mode 必须为 head 或 tail，实际: %s" mode)
            :skill "file-tools" :command "head-tail"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     ((not (file-exists-p path))
      (list :status "error" :code "NOT_FOUND"
            :message (format "文件不存在: %s" path)
            :skill "file-tools" :command "head-tail"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     (t
      (let* ((lines (with-current-buffer
                        (find-file-noselect path)
                      (split-string (buffer-string) "\n" t)))
             (total (length lines))
             (k (max 0 n))
             (picked
              (if (string= mode "head")
                  (seq-take lines k)
                (nthcdr (max 0 (- total k)) lines))))
        (list :status "ok"
              :path path
              :mode mode
              :requested n
              :total-lines total
              :returned (length picked)
              :lines picked
              :skill "file-tools" :command "head-tail"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))))

(provide 'aiaos-cli-skill-file-tools/head-tail)
