;;; post-command.el --- emacs-tools skill: post-command hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos-cli_skills.md §4, post-command receives (command result) and
;;; is used for cleanup, metrics, and result post-processing.

;;; 设计原则：
;;;   1. 无副作用（默认只记 message，不写文件）
;;;   2. 结果校验：确保 result 是 plist 且含 :status
;;;   3. 任何异常必须被吞掉，绝不能影响主命令返回

(defun aiaos-cli-skill-emacs-tools/post-command (command result)
  "Called after any emacs-tools command runs.

COMMAND is the command name.
RESULT is the plist returned by the command.

Validates the result shape (must be a plist with :status) and records
a lightweight message. Never raises; failures are silently ignored."
  (condition-case _
      (when (and (listp result)
                 (consp result)
                 (keywordp (car result)))
        (unless (plist-get result :status)
          (message "emacs-tools/%s: result missing :status" command)))
    (error nil))
  nil)

(provide 'aiaos-cli-skill-emacs-tools/post-command)
