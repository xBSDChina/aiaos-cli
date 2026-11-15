;;; repeat.el --- string-tools skill: repeat command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/repeat (args &rest _options)
  "Repeat a string N times.

ARGS is a plist with :text and :times.
OPTIONS is accepted but unused (kept for forward-compat).
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let* ((raw (plist-get args :text))
         (text (cond ((stringp raw) raw)
                     ((numberp raw) (format "%s" raw))
                     (t nil)))
         (times (let ((raw-t (plist-get args :times)))
                  (cond ((stringp raw-t) (string-to-number raw-t))
                        ((numberp raw-t) raw-t)
                        (t nil))))
         result)
    (unless text
      (error "aiaos-cli-skill-string-tools/repeat: missing :text"))
    (unless times
      (error "aiaos-cli-skill-string-tools/repeat: missing :times"))
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
