;;; post-command.el --- base64-tools skill: post-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-base64-tools/post-command (command result)
  "Called after executing a base64-tools command.

COMMAND is the command name string, RESULT is the result plist."
  (message "base64-tools post-command: %s -> %s"
           command
           (plist-get result :status)))

(provide 'aiaos-cli-skill-base64-tools/post-command)
;;; post-command.el ends here
