;;; encode.el --- emacs-tools skill: encode command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/encode (args &rest options)
  "Encode/decode TEXT using base64 or URL encoding.

ARGS is a plist with :text.
OPTIONS is a plist with :mode (b64|url|b64d|urld).

Per ~/aiaos-cli_skills.md §3.3, every command MUST return a plist
containing at least :status, :skill, :command, :timestamp."
  (let ((text (plist-get args :text))
        (mode (or (plist-get options :mode) "b64"))
        (result))
    (condition-case e
        (progn
          (when (null text)
            (error "aiaos-cli-skill-emacs-tools/encode: missing :text"))
          (setq result
                (pcase mode
                  ("b64"  (base64-encode-string text))
                  ("b64d" (base64-decode-string text))
                  ("url"  (url-hexify-string text))
                  ("urld" (url-unhex-string text))
                  (_     (error "unknown mode: %s" mode))))
          (list :status "ok"
                :mode mode
                :result result
                :skill "emacs-tools"
                :command "encode"
                :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
      (error
       (list :status "error"
             :mode mode
             :error (error-message-string e)
             :skill "emacs-tools"
             :command "encode"
             :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))))

(provide 'aiaos-cli-skill-emacs-tools/encode)
;;; encode.el ends here
