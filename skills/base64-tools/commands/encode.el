;;; encode.el --- base64-tools skill: encode command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-base64-tools/encode (args &rest _options)
  "Base64 encode TEXT from ARGS.

ARGS is a plist with :text."
  (let ((text (plist-get args :text))
        result)
    (unless (stringp text)
      (error "aiaos-cli-skill-base64-tools/encode: missing :text"))
    (setf result (base64-encode-string text))
    (list :status "ok"
          :encoded result
          :skill "base64-tools"
          :command "encode"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-base64-tools/encode)
;;; encode.el ends here
