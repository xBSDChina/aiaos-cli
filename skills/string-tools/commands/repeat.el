;;; repeat.el --- string-tools skill: repeat command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/repeat (args &rest _options)
  "Repeat a string N times.

ARGS is a plist with :text and :times.
OPTIONS is accepted but unused (kept for forward-compat)."
  (let* ((text (plist-get args :text))
         (times (let ((raw (plist-get args :times)))
                   (if (stringp raw)
                       (condition-case nil
                           (string-to-number raw)
                         (error "aiaos-cli-skill-string-tools/repeat: :times must be integer"))
                     raw)))
         result)
    (unless (stringp text)
      (error "aiaos-cli-skill-string-tools/repeat: missing :text"))
    (unless (integerp times)
      (error "aiaos-cli-skill-string-tools/repeat: :times must be integer"))
    (when (< times 0)
      (error "aiaos-cli-skill-string-tools/repeat: :times must be >= 0"))
    (setq result "")
    (dotimes (_i times)
      (setq result (concat result text)))
    (list :status "ok"
          :text result
          :times times
          :skill "string-tools"
          :command "repeat"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-string-tools/repeat)
;;; repeat.el ends here
