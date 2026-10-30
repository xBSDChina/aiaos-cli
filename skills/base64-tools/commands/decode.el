;;; decode.el --- base64-tools skill: decode command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-base64-tools/decode (args &rest _options)
  "Base64 decode TEXT from ARGS.

ARGS is a plist with :text.
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let ((raw (plist-get args :text))
        (text (cond ((stringp (plist-get args :text)) (plist-get args :text))
                    ((numberp (plist-get args :text)) (format "%s" (plist-get args :text)))
                    (t nil)))
        result)
    (unless text
      (error "aiaos-cli-skill-base64-tools/decode: missing :text"))
    (setf result (base64-decode-string text))
    (list :status "ok"
          :decoded result
          :skill "base64-tools"
          :command "decode"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-base64-tools/decode)
;;; decode.el ends here
