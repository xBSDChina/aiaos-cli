;;; run.el --- skill-management skill: run command -*- lexical-binding: t; -*-
;;
;; Run a target skill command in-process (load .el then call function).
;;
;; Contract:
;;   Input  plist: (:name TARGET-SKILL :command CMD :args PLIST)
;;   Output plist: (:status "ok"|"error" :output ... :skill "skill-management"
;;                  :command "run" :timestamp "...")

;;;###autoload
(defun aiaos-cli-skill-skill-management/run (args &rest _options)
  "Run a target skill command in-process.

ARGS is a plist with :name (target skill), :command (cmd name),
and optional :args (plist of arguments).
Returns a plist describing execution result."
  (let* ((name (plist-get args :name))
         (cmd (plist-get args :command))
         (cmd-args (or (plist-get args :args) '()))
         (skills-dir (or (getenv "AIAOS_CLI_SKILLS_DIR")
                         (expand-file-name "~/aiaos/aiaos-cli/skills")))
         (skill-dir (expand-file-name name skills-dir))
         (cmd-file (expand-file-name (concat "commands/" cmd ".el") skill-dir))
         (func-name (intern (format "aiaos-cli-skill-%s/%s" name cmd)))
         (result nil)
         (err nil))
    (unless (stringp name) (error "skill-management/run: missing :name"))
    (unless (stringp cmd) (error "skill-management/run: missing :command"))
    (if (not (file-exists-p cmd-file))
        (list :status "error"
              :error (format "command file not found: %s" cmd-file)
              :target-skill name :target-command cmd
              :skill "skill-management" :command "run"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
      (progn
        (condition-case e
            (progn
              (load cmd-file)
              (unless (fboundp func-name)
                (error (format "function not defined after load: %s" func-name)))
              (setq result (funcall func-name cmd-args)))
          (error (setq err (error-message-string e))))
        (list :status (if err "error" "ok")
              :output result
              :error err
              :target-skill name
              :target-command cmd
              :skill "skill-management"
              :command "run"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))))

(provide 'aiaos-cli-skill-skill-management/run)
;;; run.el ends here
