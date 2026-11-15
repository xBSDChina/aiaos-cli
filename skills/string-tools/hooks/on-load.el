;;; on-load.el --- string-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-string-tools/on-load ()
  "Called when the string-tools skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-string-tools/trim nil t)
  (require 'aiaos-cli-skill-string-tools/reverse nil t)
  (require 'aiaos-cli-skill-string-tools/repeat nil t)
  (require 'aiaos-cli-skill-string-tools/pad nil t)
  (message "aiaos-cli: string-tools skill loaded"))

(provide 'aiaos-cli-skill-string-tools/on-load)
;;; on-load.el ends here
