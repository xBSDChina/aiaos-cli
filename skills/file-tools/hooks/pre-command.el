;;; pre-command.el --- file-tools skill: pre-command hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos-cli_skills.md §4, pre-command receives (command args) and is
;;; used for audit, permission checks, and argument preprocessing.

;;; 设计原则（R2200 固化，继承 emacs-tools 模板）：
;;;   1. 默认无副作用（不写文件、不弹交互），避免 batch 环境出错
;;;   2. 通过 defcustom 允许用户显式开启审计
;;;   3. 任何异常都必须被吞掉，绝不能影响主命令执行

(defcustom aiaos-cli-skill-file-tools/audit-log nil
  "Audit log path for file-tools pre-command hook.
Set to a writable file path to enable audit logging.
Default nil disables audit logging (safe for batch mode)."
  :type '(choice (string) (const :tag "disabled" nil))
  :group 'aiaos-cli)

(defun aiaos-cli-skill-file-tools/pre-command (command args)
  "Called before any file-tools command runs.

COMMAND is the command name (e.g. \"checksum\").
ARGS is the plist of positional arguments.

Records an audit entry when audit-log is enabled.
Always returns nil (does not mutate args).
Never raises; failures are silently ignored."
  (when (and aiaos-cli-skill-file-tools/audit-log
             (stringp aiaos-cli-skill-file-tools/audit-log)
             (file-directory-p (file-name-directory
                                aiaos-cli-skill-file-tools/audit-log)))
    (condition-case _
        (with-current-buffer (find-file-noselect
                              aiaos-cli-skill-file-tools/audit-log)
          (goto-char (point-max))
          (insert (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                  " file-tools " (prin1-to-string command)
                  " args=" (prin1-to-string args) "\n")
          (save-buffer))
      (error nil)))
  nil)

(provide 'aiaos-cli-skill-file-tools/pre-command)
