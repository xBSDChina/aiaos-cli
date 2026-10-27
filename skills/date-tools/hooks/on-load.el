;;; on-load.el --- date-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-date-tools/on-load ()
  "Called when the date-tools skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-date-tools/now nil t)
  (require 'aiaos-cli-skill-date-tools/add nil t)
  (require 'aiaos-cli-skill-date-tools/timestamp nil t)
  (message "aiaos-cli: date-tools skill loaded"))

(provide 'aiaos-cli-skill-date-tools/on-load)
;;; on-load.el ends here
