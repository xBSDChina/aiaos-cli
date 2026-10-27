;;; trim.el --- string-tools skill: trim command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/trim (args &rest options)
  "Trim whitespace from a string.

ARGS is a plist with :text.
OPTIONS is a plist with :side (both|left|right)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (side (or (plist-get opts :side) "both"))
         result)
    (unless (stringp text)
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
