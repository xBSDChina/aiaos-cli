;;; on-load.el --- hello-world skill: on-load hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-hello-world/on-load ()
  "Called when the hello-world skill is loaded."
  (message "hello-world skill loaded"))

(provide 'aiaos-cli-skill-hello-world/on-load)
