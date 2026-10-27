;;; validate.el --- skill-management skill: validate command -*- lexical-binding: t; -*-
;;
;; Validate a skill's metadata file (skill.yaml).
;;
;; Contract:
;;   Input  plist: (:name SKILL-NAME)
;;   Output plist: (:status "ok"|"error" :skill NAME :valid T|NIL
;;                  :errors [...] :warnings [...] :commands-count N
;;                  :hooks-count N :timestamp "...")

;;;###autoload
(defun aiaos-cli-skill-skill-management/validate (args &rest _options)
  "Validate skill metadata for SKILL-NAME."
  (let ((name (plist-get args :name)))
    (unless (stringp name)
      (error "skill-management/validate: missing :name"))
    (when (string-empty-p name)
      (error "skill-management/validate: :name is empty"))
    (let* ((skills-dir (or (getenv "AIAOS_CLI_SKILLS_DIR")
                           (expand-file-name "~/aiaos/aiaos-cli/skills")))
           (skill-dir (expand-file-name name skills-dir))
           (yaml-path (expand-file-name "skill.yaml" skill-dir))
           (errs '())
           (warns '())
           (cmds 0)
           (hooks 0))
      (unless (file-directory-p skill-dir)
        (push (format "skill directory not found: %s" skill-dir) errs))
      (unless (file-exists-p yaml-path)
        (push (format "skill.yaml not found at: %s" yaml-path) errs))
      (when (file-exists-p yaml-path)
        (setq errs (aiaos-cli--validate-yaml yaml-path errs)))
      (when (file-directory-p skill-dir)
        (setq cmds (aiaos-cli--count-commands skill-dir))
        (setq hooks (aiaos-cli--count-hooks skill-dir)))
      (list :status (if errs "error" "ok")
            :skill name
            :valid (not errs)
            :path skill-dir
            :commands-count cmds
            :hooks-count hooks
            :errors errs
            :warnings warns
            :command "validate"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(defun aiaos-cli--validate-yaml (yaml-path errs)
  "Validate YAML file at YAML-PATH and return updated error list."
  (let ((content ""))
    (with-temp-buffer
      (insert-file-contents yaml-path)
      (setq content (buffer-string)))
    (dolist (key '("name:" "version:" "description:" "commands:"))
      (unless (string-match-p key content)
        (push (format "missing required field: %s" key) errs)))
    errs))

(defun aiaos-cli--count-commands (skill-dir)
  "Count .el files in commands/ subdirectory of SKILL-DIR."
  (let ((cmds-dir (expand-file-name "commands" skill-dir)))
    (if (file-directory-p cmds-dir)
        (length (directory-files cmds-dir t "\\.el$"))
      0)))

(defun aiaos-cli--count-hooks (skill-dir)
  "Count .el files in hooks/ subdirectory of SKILL-DIR."
  (let ((hooks-dir (expand-file-name "hooks" skill-dir)))
    (if (file-directory-p hooks-dir)
        (length (directory-files hooks-dir t "\\.el$"))
      0)))

(provide 'aiaos-cli-skill-skill-management/validate)
;;; validate.el ends here