;;; post-command.el --- date-tools skill: post-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-date-tools/post-command (command result)
  "Post-command hook for date-tools.

COMMAND is the command name string.
RESULT is the plist returned by the command.
Used for result validation, logging, and cleanup."
  ;; Validate result structure
  (condition-case _
      (when (and (listp result)
                 (consp result)
                 (keywordp (car result)))
        (unless (plist-get result :status)
          (message "date-tools/%s: result missing :status" command)))
    (error nil))
  nil)

(provide 'aiaos-cli-skill-date-tools/post-command)
