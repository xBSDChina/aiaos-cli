;;; checksum.el --- file-tools skill: checksum command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-file-tools/checksum (args &rest options)
  "Compute MD5 or SHA256 digest of a file.

ARGS is a plist with :path.
OPTIONS is a plist with :algo (md5|sha256, default sha256).

Digests are produced by the system tools `md5sum' / `sha256sum' so that
this skill stays portable across Emacs builds (Emacs has no built-in
`sha256' function)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (path (plist-get args :path))
         (algo (or (plist-get opts :algo) "sha256")))
    (cond
     ((or (null path) (not (stringp path)) (string= path ""))
      (list :status "error" :code "INVALID_ARGS"
            :message "path 不能为空"
            :skill "file-tools" :command "checksum"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     ((and (not (string= algo "md5")) (not (string= algo "sha256")))
      (list :status "error" :code "INVALID_ARGS"
            :message (format "algo 必须为 md5 或 sha256，实际: %s" algo)
            :skill "file-tools" :command "checksum"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     ((not (file-exists-p path))
      (list :status "error" :code "NOT_FOUND"
            :message (format "文件不存在: %s" path)
            :skill "file-tools" :command "checksum"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
     (t
      (aiaos-cli-skill-file-tools--digest
       path algo (if (string= algo "md5") "md5sum" "sha256sum"))))))

;; Internal helper: run TOOL on PATH and return the bare digest string.
(defun aiaos-cli-skill-file-tools--digest (path algo tool)
  "Run TOOL on PATH and return the digest, or nil on failure."
  (let* ((first-line (nth 0 (split-string
                               (shell-command-to-string
                                (format "%s %s" tool (shell-quote-argument path)))
                               "\n" t)))
         (digest (when first-line
                   (substring first-line 0
                              (or (string-search " " first-line)
                                  (length first-line))))))
    (if digest
        (list :status "ok"
              :path path
              :algo algo
              :digest digest
              :skill "file-tools" :command "checksum"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
      (list :status "error" :code "TOOL_FAILED"
            :message (format "%s 未返回摘要" tool)
            :skill "file-tools" :command "checksum"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(provide 'aiaos-cli-skill-file-tools/checksum)
