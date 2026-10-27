;;; pre-command.el --- emacs-tools skill: pre-command hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos-cli_skills.md §4, pre-command receives (command args) and is
;;; used for audit, permission checks, and argument preprocessing.

;;; 设计原则：
;;;   1. 默认无副作用（不写文件、不弹交互），避免 batch 环境出错
;;;   2. 通过 defcustom 允许用户显式开启审计
;;;   3. 任何异常都必须被吞掉，绝不能影响主命令执行

(defcustom aiaos-cli-skill-emacs-tools/audit-log nil
  "Audit log path for emacs-tools pre-command hook.
Set to a writable file path to enable audit logging.
Default nil disables audit logging (safe for batch mode)."
  :type '(choice (string) (const :tag "disabled" nil))
  :group 'aiaos-cli)

(defun aiaos-cli-skill-emacs-tools/pre-command (command args)
  "Called before any emacs-tools command runs.

COMMAND is the command name (e.g. \"encode\").
ARGS is the plist of positional arguments.

Records an audit entry when audit-log is enabled.
Always returns nil (does not mutate args).
Never raises; failures are silently ignored."
  (when (and aiaos-cli-skill-emacs-tools/audit-log
             (stringp aiaos-cli-skill-emacs-tools/audit-log)
             (file-directory-p (file-name-directory
                                aiaos-cli-skill-emacs-tools/audit-log)))
    (condition-case _
        (with-current-buffer (find-file-noselect
                              aiaos-cli-skill-emacs-tools/audit-log)
          (goto-char (point-max))
          (insert (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                  " emacs-tools " (prin1-to-string command)
                  " args=" (prin1-to-string args) "\n")
          (save-buffer))
      (error nil)))
  nil)

(provide 'aiaos-cli-skill-emacs-tools/pre-command)
