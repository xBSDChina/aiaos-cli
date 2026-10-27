;;; on-load.el --- base64-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-base64-tools/on-load ()
  "Called when base64-tools skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-base64-tools/encode nil t)
  (require 'aiaos-cli-skill-base64-tools/decode nil t)
  (message "aiaos-cli: base64-tools skill loaded"))

(provide 'aiaos-cli-skill-base64-tools/on-load)
;;; on-load.el ends here
