;;; post-command.el --- hello-world skill: post-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-hello-world/post-command (command result)
  "Called after any hello-world command runs."
  (message "hello-world: post-command %s -> %s" command (plist-get result :status)))

(provide 'aiaos-cli-skill-hello-world/post-command)
