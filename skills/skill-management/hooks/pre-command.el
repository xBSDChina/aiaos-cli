;;; pre-command.el --- skill-management skill: pre-command hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos/aiaos-cli_skills.md §4, pre-command receives (command args) and
;;; is used for audit, permission checks, and argument preprocessing.

;;; 设计原则（继承 R2200 固化模板）：
;;;   1. 默认无副作用（不写文件、不弹交互），避免 batch 环境出错
;;;   2. 通过 defcustom 允许用户显式开启审计
;;;   3. 任何异常都必须被吞掉，绝不能影响主命令执行

(defcustom aiaos-cli-skill-skill-management/audit-log nil
  "Audit log path for skill-management pre-command hook.
Set to a writable file path to enable audit logging.
Default nil disables audit logging (safe for batch mode)."
  :type '(choice (string) (const :tag "disabled" nil))
  :group 'aiaos-cli)

(defun aiaos-cli-skill-skill-management/pre-command (command args)
  "Called before any skill-management command runs.

COMMAND is the command name (e.g. \\\"validate\\\", \\\"list\\\").
ARGS is the plist of positional arguments.

Records an audit entry when audit-log is enabled.
Always returns nil (does not mutate args).
Never raises; failures are silently ignored."
  (when (and aiaos-cli-skill-skill-management/audit-log
             (stringp aiaos-cli-skill-skill-management/audit-log)
             (file-directory-p (file-name-directory
                                aiaos-cli-skill-skill-management/audit-log)))
    (condition-case _
        (with-current-buffer (find-file-noselect
                              aiaos-cli-skill-skill-management/audit-log)
          (goto-char (point-max))
          (insert (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                  " skill-management " (prin1-to-string command)
                  " args=" (prin1-to-string args) "\n")
          (save-buffer))
      (error nil)))
  nil)

(provide 'aiaos-cli-skill-skill-management/pre-command)
;;; pre-command.el ends here
