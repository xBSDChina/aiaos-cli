;;; pre-command.el --- hello-world skill: pre-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-hello-world/pre-command (command _args)
  "Called before any hello-world command runs."
  (message "hello-world: pre-command %s" command))

(provide 'aiaos-cli-skill-hello-world/pre-command)
