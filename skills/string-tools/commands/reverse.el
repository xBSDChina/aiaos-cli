;;; reverse.el --- string-tools skill: reverse command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/reverse (args &rest _options)
  "Reverse a string.

ARGS is a plist with :text.
OPTIONS is accepted but unused (kept for forward-compat)."
  (let ((text (plist-get args :text))
        result)
    (unless (stringp text)
      (error "aiaos-cli-skill-string-tools/reverse: missing :text"))
    ;; Emacs 30 removed string-reverse; rebuild from reversed char list.
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
