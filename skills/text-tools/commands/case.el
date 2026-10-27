;;; case.el --- text-tools skill: case command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-text-tools/case (args &rest options)
  "Transform text case.

ARGS is a plist with :text.
OPTIONS is a plist with :mode (upper|lower|title)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (mode (or (plist-get opts :mode) "upper"))
         result)
    (unless (stringp text)
      (error "aiaos-cli-skill-text-tools/case: missing :text"))
    (cond
     ((string= mode "upper")
      (setf result (upcase text)))
     ((string= mode "lower")
      (setf result (downcase text)))
     ((string= mode "title")
      (let ((words (split-string text "[[:space:]]+" t)))
        (setf result
              (mapconcat
               (lambda (w)
                 (if (string-empty-p w)
                     w
                   (concat (upcase (substring w 0 1))
                           (downcase (substring w 1)))))
               words " "))))
     (t (error (format "aiaos-cli-skill-text-tools/case: unknown mode %s" mode))))
    (list :status "ok"
          :text result
          :mode mode
          :skill "text-tools"
          :command "case"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-text-tools/case)
