;;; pad.el --- string-tools skill: pad command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/pad (args &rest options)
  "Pad a string to a target length.

ARGS is a plist with :text and :length.
OPTIONS is a plist with :char (default \" \") and :align (left|center|right)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (len (let ((raw (plist-get args :length)))
                (if (stringp raw)
                    (condition-case nil
                        (string-to-number raw)
                      (error "aiaos-cli-skill-string-tools/pad: :length must be integer"))
                  raw)))
         (ch (or (plist-get opts :char) " "))
         (align (or (plist-get opts :align) "right"))
         result)
    (unless (stringp text)
      (error "aiaos-cli-skill-string-tools/pad: missing :text"))
    (unless (integerp len)
      (error "aiaos-cli-skill-string-tools/pad: :length must be integer"))
    (unless (and (stringp ch) (>= (length ch) 1))
      (error "aiaos-cli-skill-string-tools/pad: :char must be non-empty string"))
    (let ((cur (length text))
          (fillchar (aref ch 0)))
      (cond
       ((<= len cur) (setf result text))
       ((string= align "left")
        (setf result (concat text (make-string (- len cur) fillchar))))
       ((string= align "right")
        (setf result (concat (make-string (- len cur) fillchar) text)))
       ((string= align "center")
        (let* ((pad (- len cur))
               (left (floor pad 2))
               (right (- pad left)))
          (setf result (concat (make-string left fillchar) text
                               (make-string right fillchar)))))
       (t (error (format "aiaos-cli-skill-string-tools/pad: unknown align %s" align)))))
    (list :status "ok"
          :text result
          :length len
          :align align
          :skill "string-tools"
          :command "pad"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-string-tools/pad)
;;; pad.el ends here
