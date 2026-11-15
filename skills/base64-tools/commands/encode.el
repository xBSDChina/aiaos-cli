;;; encode.el --- base64-tools skill: encode command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-base64-tools/encode (args &rest _options)
  "Base64 encode TEXT from ARGS.

ARGS is a plist with :text.
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let ((raw (plist-get args :text))
        (text (cond ((stringp (plist-get args :text)) (plist-get args :text))
                    ((numberp (plist-get args :text)) (format "%s" (plist-get args :text)))
                    (t nil)))
        result)
    (unless text
      (error "aiaos-cli-skill-base64-tools/encode: missing :text"))
    (setf result (base64-encode-string text))
    (list :status "ok"
          :encoded result
          :skill "base64-tools"
          :command "encode"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-base64-tools/encode)
;;; encode.el ends here
