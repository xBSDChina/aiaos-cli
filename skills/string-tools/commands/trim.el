;;; trim.el --- string-tools skill: trim command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/trim (args &rest options)
  "Trim whitespace from a string.

ARGS is a plist with :text.
OPTIONS is a plist with :side (left|right|both, default both).
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (raw (plist-get args :text))
         (text (cond ((stringp raw) raw)
                     ((numberp raw) (format "%s" raw))
                     (t nil)))
         (side (or (plist-get opts :side) "both"))
         result)
    (unless text
      (error "aiaos-cli-skill-string-tools/trim: missing :text"))
    (cond
     ((string= side "left") (setf result (string-trim-left text)))
     ((string= side "right") (setf result (string-trim-right text)))
     ((string= side "both") (setf result (string-trim text)))
     (t (error (format "aiaos-cli-skill-string-tools/trim: unknown side %s" side))))
    (list :status "ok"
          :text result
          :side side
          :skill "string-tools"
          :command "trim"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-string-tools/trim)
