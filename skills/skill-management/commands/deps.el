;;; deps.el --- skill-management skill: deps command -*- lexical-binding: t; -*-
;;
;; Resolve dependencies of a skill (topological order + cycle detection).
;;
;; Contract:
;;   Input  plist: (:name SKILL-NAME)
;;   Output plist: (:status "ok" :skill NAME :dependencies [...]
;;                  :topological-order [...] :cycle NIL
;;                  :skill "skill-management" :command "deps" :timestamp "...")

;;;###autoload
(defun aiaos-cli-skill-skill-management/deps (args &rest _options)
  "Resolve dependencies for SKILL-NAME.

ARGS is a plist with optional :name (target skill name).
Returns a plist describing dependency graph and topological order."
  (let* ((target (plist-get args :name))
         (skills-dir (or (getenv "AIAOS_CLI_SKILLS_DIR")
                         (expand-file-name "~/aiaos/aiaos-cli/skills")))
         (skill-dir (expand-file-name target skills-dir))
         (yaml-path (expand-file-name "skill.yaml" skill-dir))
         (yaml-content "")
         (deps '())
         (topo '())
         (cycle nil))
    (unless (stringp target) (error "skill-management/deps: missing :name"))
    (if (not (file-exists-p yaml-path))
        (list :status "error"
              :error (format "skill.yaml not found: %s" yaml-path)
              :skill "skill-management" :command "deps"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
      (with-temp-buffer
        (insert-file-contents yaml-path)
        (setq yaml-content (buffer-string)))
      (setq deps (aiaos-cli--yaml-parse-deps yaml-content))
      (setq topo (aiaos-cli--toposort target deps '() '()))
      (when (eq topo :cycle) (setq cycle t))
      (list :status "ok"
            :skill target
            :dependencies deps
            :topological-order (if cycle nil topo)
            :cycle cycle
            :skill "skill-management"
            :command "deps"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(defun aiaos-cli--yaml-parse-deps (content)
  "Parse dependencies from YAML CONTENT.

Supports simple forms:
  dependencies:
    - name
    - name
Returns a list of dependency names."
  (let ((deps '())
        (in-deps nil)
        (lines (split-string content "\n")))
    (dolist (line lines)
      (cond
       ((string-match "^\\s *dependencies:\\s *$" line)
        (setq in-deps t))
       (in-deps
        (cond
         ((string-match "^\\s *-[\\s ]*\\([^\s:#][^:]*\\)" line)
          (let ((name (match-string 1 line)))
            (setq name (replace-regexp-in-string "[\"']" "" name))
            (push (string-trim name) deps)))
         ((string-match "^[a-zA-Z]" line)
          (setq in-deps nil))))))
    (nreverse deps)))

(defun aiaos-cli--toposort (node deps visited stack)
  "Topological sort starting from NODE using DEPS graph.

Returns sorted list or :cycle if cycle detected."
  (cond
   ((member node visited) node)
   ((member node stack) :cycle)
   (t
    (push node stack)
    (let ((result '()))
      (dolist (dep deps)
        (let ((r (aiaos-cli--toposort dep '() visited stack)))
          (if (eq r :cycle)
              (return-from aiaos-cli--toposort :cycle)
            (when (not (member r result))
              (push r result)))))
      (pop stack)
      (push node visited)
      (push node result)
      (nreverse result)))))

(provide 'aiaos-cli-skill-skill-management/deps)
;;; deps.el ends here
