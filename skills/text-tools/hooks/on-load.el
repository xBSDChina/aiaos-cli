;;; on-load.el --- text-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-text-tools/on-load ()
  "Called when text-tools skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-text-tools/case nil t)
  (require 'aiaos-cli-skill-text-tools/wordcount nil t)
  (message "aiaos-cli: text-tools skill loaded"))

(provide 'aiaos-cli-skill-text-tools/on-load)
;;; on-load.el ends here
