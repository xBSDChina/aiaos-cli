;;; reverse.el --- string-tools skill: reverse command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/reverse (args &rest _options)
  "Reverse a string.

ARGS is a plist with :text.
OPTIONS is accepted but unused (kept for forward-compat).
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let* ((raw (plist-get args :text))
         (text (cond ((stringp raw) raw)
                     ((numberp raw) (format "%s" raw))
                     (t nil)))
         result)
    (unless text
      (error "aiaos-cli-skill-string-tools/reverse: missing :text"))
    ;; Emacs 30 removed string-reverse; rebuild manually
    (setf result
          (apply 'concat
                 (mapcar (lambda (c) (string c))
                         (reverse (string-to-list text)))))
    (list :status "ok"
          :text result
          :skill "string-tools"
          :command "reverse"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-string-tools/reverse)
