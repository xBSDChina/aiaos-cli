;;; list.el --- skill-management skill: list command -*- lexical-binding: t; -*-
;;
;; List all installed skills (read from skills/*/skill.yaml).
;;
;; Contract:
;;   Input  plist: (:skills-dir DIR optional)
;;   Output plist: (:status "ok" :skills [...] :count N :timestamp "...")

;;;###autoload
(defun aiaos-cli-skill-skill-management/list (args &rest _options)
  "List all installed skills.
ARGS is a plist with optional :skills-dir.
Returns a plist describing available skills."
  (let* ((skills-dir (or (plist-get args :skills-dir)
                         (getenv "AIAOS_CLI_SKILLS_DIR")
                         (expand-file-name "~/aiaos/aiaos-cli/skills")))
         (all-skills (aiaos-cli--scan-skills-dir skills-dir))
         (validation-errors (aiaos-cli--collect-errors skills-dir)))
    (list :status (if validation-errors "error" "ok")
          :skills all-skills
          :count (length all-skills)
          :skills-dir skills-dir
          :errors validation-errors
          :skill "skill-management"
          :command "list"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(defun aiaos-cli--scan-skills-dir (skills-dir)
  "Scan SKILLS-DIR and return a sorted list of skill metadata plists."
  (let ((result '()))
    (when (file-directory-p skills-dir)
      (dolist (dir (directory-files skills-dir t))
        (when (and (file-directory-p dir)
                   (not (string= (file-name-nondirectory dir) "."))
                   (not (string= (file-name-nondirectory dir) ".."))
                   (file-exists-p (expand-file-name "skill.yaml" dir)))
          (push (aiaos-cli--read-skill-meta dir) result))))
    (cl-sort result
             (lambda (a b)
               (string< (plist-get a :name) (plist-get b :name))))))

(defun aiaos-cli--read-skill-meta (dir)
  "Read skill.yaml from DIR and return a metadata plist."
  (let ((yaml-path (expand-file-name "skill.yaml" dir))
        (content ""))
    (with-temp-buffer
      (insert-file-contents yaml-path)
      (setq content (buffer-string)))
    (let ((cmds-dir (expand-file-name "commands" dir))
          (cmds-count 0))
      (when (file-directory-p cmds-dir)
        (setq cmds-count (length (directory-files cmds-dir t "\\.el$"))))
      (list :name (or (aiaos-cli--yaml-get content "name")
                      (file-name-nondirectory dir))
            :version (or (aiaos-cli--yaml-get content "version") "0.0.0")
            :description (or (aiaos-cli--yaml-get content "description") "")
            :path dir
            :commands-count cmds-count))))

(defun aiaos-cli--collect-errors (skills-dir)
  "Return list of error strings for SKILLS-DIR (empty if OK)."
  (if (file-directory-p skills-dir)
      '()
    (list (format "skills dir not found: %s" skills-dir))))

(defun aiaos-cli--yaml-get (content key)
  "Get simple scalar value for KEY from YAML CONTENT.
Returns nil if absent. Strips surrounding double quotes."
  (let ((re (concat "^\\s*\\(" key "\\):\\s*\\(.*\\)$")))
    (when (string-match re content)
      (let ((val (match-string 2)))
        (replace-regexp-in-string "^\"\\|\"$" "" val)))))

(provide 'aiaos-cli-skill-skill-management/list)
;;; list.el ends here
