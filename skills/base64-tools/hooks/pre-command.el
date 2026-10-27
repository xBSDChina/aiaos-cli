;;; pre-command.el --- base64-tools skill: pre-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-base64-tools/pre-command (command args)
  "Called before executing a base64-tools command.

COMMAND is the command name string, ARGS is the args plist."
  (message "base64-tools pre-command: %s" command))

(provide 'aiaos-cli-skill-base64-tools/pre-command)
;;; pre-command.el ends here
