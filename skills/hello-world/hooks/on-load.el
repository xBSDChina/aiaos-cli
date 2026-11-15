;;; on-load.el --- hello-world skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-hello-world/on-load ()
  "Called when the hello-world skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-hello-world/hello nil t)
  (require 'aiaos-cli-skill-hello-world/time nil t)
  (message "aiaos-cli: hello-world skill loaded"))

(provide 'aiaos-cli-skill-hello-world/on-load)
;;; on-load.el ends here
