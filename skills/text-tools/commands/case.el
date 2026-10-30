;;; case.el --- text-tools skill: case command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-text-tools/case (args &rest options)
  "Transform text case.

ARGS is a plist with :text.
OPTIONS is a plist with :mode (upper|lower|title).
R9001: 参数类型转换契约修复，接受 string/number，自动转换。
注意：默认 mode 为 \"upper\"（与测试契约一致）。"
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (raw (plist-get args :text))
         (text (cond ((stringp raw) raw)
                     ((numberp raw) (format "%s" raw))
                     (t nil)))
         (mode (or (plist-get opts :mode) "upper"))
         result)
    (unless text
      (error "aiaos-cli-skill-text-tools/case: missing :text"))
    (cond
     ((string= mode "upper")
      (setf result (upcase text)))
     ((string= mode "lower")
      (setf result (downcase text)))
     ((string= mode "title")
      (setf result
            (mapconcat (lambda (w)
                         (if (> (length w) 0)
                             (concat (upcase (substring w 0 1))
                                     (downcase (substring w 1)))
                           w))
                       (split-string text "[ \t]+" t) " ")))
     (t (error (format "aiaos-cli-skill-text-tools/case: unknown mode %s" mode))))
    (list :status "ok"
          :text result
          :mode mode
          :skill "text-tools"
          :command "case"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-text-tools/case)
