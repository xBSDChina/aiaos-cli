;;; stat.el --- file-tools skill: stat command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-file-tools/stat (args &rest _options)
  "Stat a file: bytes, lines, chars, words and modification time.

ARGS is a plist with :path.
OPTIONS is an unused plist for this command."
  (let ((path (plist-get args :path)))
    (cond
      ((or (null path) (not (stringp path)) (string= path ""))
       (list :status "error" :code "INVALID_ARGS"
             :message "path 不能为空"
             :skill "file-tools" :command "stat"
             :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
      ((not (file-exists-p path))
       (list :status "error" :code "NOT_FOUND"
             :message (format "文件不存在: %s" path)
             :skill "file-tools" :command "stat"
             :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
      (t
       (let* ((attr (file-attributes path))
              (bytes (nth 7 attr))
              (mtime (nth 5 attr))
              (content (with-current-buffer
                         (find-file-noselect path)
                       (buffer-substring (point-min) (point-max))))
              (n-lines (if (string= content "")
                           0
                         (length (split-string content "\n"))))
              (n-chars (length content))
              (n-words (length (split-string content
                                              "[ \t\n\r]+"
                                              t))))
         (list :status "ok"
               :path path
               :bytes bytes
               :lines n-lines
               :chars n-chars
               :words n-words
               :mtime (format-time-string "%Y-%m-%dT%H:%M:%S%z" mtime)
               :skill "file-tools" :command "stat"
               :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))))

(provide 'aiaos-cli-skill-file-tools/stat)
;;; stat.el ends here
