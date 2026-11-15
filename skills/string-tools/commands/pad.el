;;; pad.el --- string-tools skill: pad command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/pad (args &rest options)
  "Pad a string to a target length.

ARGS is a plist with :text and :length.
OPTIONS is a plist with :char (default \" \") and :align (left|center|right).
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
         (raw-len (plist-get args :length))
         (len (cond ((stringp raw-len) (string-to-number raw-len))
                    ((numberp raw-len) raw-len)
                    (t nil)))
         (char (or (plist-get opts :char) " "))
         (align (or (plist-get opts :align) "left"))
         fillchar result)
    (unless text
      (error "aiaos-cli-skill-string-tools/pad: missing :text"))
    (unless (and len (numberp len))
      (error "aiaos-cli-skill-string-tools/pad: missing :length"))
    (setq fillchar (if (string= char "") ?\s (aref char 0)))
    (cond
     ((string= align "left")
      (setf result (concat text (make-string (- len (length text)) fillchar))))
     ((string= align "right")
      (setf result (concat (make-string (- len (length text)) fillchar) text)))
     ((string= align "center")
      (let* ((pad (- len (length text)))
             (left (/ pad 2))
             (right (- pad left)))
        (setf result (concat (make-string left fillchar)
                             text
                             (make-string right fillchar)))))
     (t (error (format "aiaos-cli-skill-string-tools/pad: unknown align %s" align))))
    (list :status "ok"
          :text result
          :length len
          :align align
          :skill "string-tools"
          :command "pad"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-string-tools/pad)
;;; pad.el ends here
