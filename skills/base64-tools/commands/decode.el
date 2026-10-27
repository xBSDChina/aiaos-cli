;;; decode.el --- base64-tools skill: decode command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-base64-tools/decode (args &rest _options)
  "Base64 decode TEXT from ARGS.

ARGS is a plist with :text."
  (let ((text (plist-get args :text))
        result)
    (unless (stringp text)
      (error "aiaos-cli-skill-base64-tools/decode: missing :text"))
    (setf result (base64-decode-string text))
    (list :status "ok"
          :decoded result
          :skill "base64-tools"
          :command "decode"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-base64-tools/decode)
;;; decode.el ends here
