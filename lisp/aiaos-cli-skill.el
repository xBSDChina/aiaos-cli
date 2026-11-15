;;; aiaos-cli-skill.el --- AIAOS-CLI Skill Management -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; Author: AIAOS Team
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1") (aiaos-cli-core "1.0.0") (aiaos-cli-router "1.0.0"))
;; Keywords: tools, ai, cli

;;; Commentary:
;; 技能管理：安装、列表、启用、禁用、卸载、开发模板

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'json)
(require 'cl-lib)
(require 'yaml nil t)

(defgroup aiaos-cli-skill nil
  "AIAOS-CLI Skill Management"
  :group 'aiaos-cli)

(defcustom aiaos-cli-skill-dirs
  '("~/.config/aiaos/skills" "/usr/share/aiaos/skills")
  "Skill search directories"
  :type '(repeat string)
  :group 'aiaos-cli-skill)

(defcustom aiaos-cli-skill-auto-load t
  "启动时自动Loading skill"
  :type 'boolean
  :group 'aiaos-cli-skill)

(defvar aiaos-cli--loaded-skills nil
  "Loaded skills list")

(defun aiaos-cli--make-skill (name version description author license path metadata commands hooks enabled)
  "Create skill object"
  (list :name name
        :version version
        :description description
        :author author
        :license license
        :path path
        :metadata metadata
        :commands commands
        :hooks hooks
        :enabled enabled))

(defun aiaos-cli-skill-name (skill) (plist-get skill :name))
(defun aiaos-cli-skill-version (skill) (plist-get skill :version))
(defun aiaos-cli-skill-description (skill) (plist-get skill :description))
(defun aiaos-cli-skill-author (skill) (plist-get skill :author))
(defun aiaos-cli-skill-license (skill) (plist-get skill :license))
(defun aiaos-cli-skill-path (skill) (plist-get skill :path))
(defun aiaos-cli-skill-metadata (skill) (plist-get skill :metadata))
(defun aiaos-cli-skill-commands (skill) (plist-get skill :commands))
(defun aiaos-cli-skill-hooks (skill) (plist-get skill :hooks))
(defun aiaos-cli-skill-enabled (skill) (plist-get skill :enabled))

(defun aiaos-cli-skill-set-name (skill name) (plist-put skill :name name))
(defun aiaos-cli-skill-set-version (skill version) (plist-put skill :version version))
(defun aiaos-cli-skill-set-description (skill desc) (plist-put skill :description desc))
(defun aiaos-cli-skill-set-author (skill author) (plist-put skill :author author))
(defun aiaos-cli-skill-set-license (skill license) (plist-put skill :license license))
(defun aiaos-cli-skill-set-path (skill path) (plist-put skill :path path))
(defun aiaos-cli-skill-set-metadata (skill meta) (plist-put skill :metadata meta))
(defun aiaos-cli-skill-set-commands (skill cmds) (plist-put skill :commands cmds))
(defun aiaos-cli-skill-set-hooks (skill hooks) (plist-put skill :hooks hooks))
(defun aiaos-cli-skill-set-enabled (skill enabled) (plist-put skill :enabled enabled))

(defun aiaos-cli-skill--find-skills ()
  "Find all available skills"
  (let ((skills nil))
    (dolist (dir aiaos-cli-skill-dirs)
      (let ((expanded (expand-file-name dir)))
        (when (file-directory-p expanded)
          (dolist (entry (directory-files expanded t "^.*$"))
            (when (and (file-directory-p entry)
                       (file-exists-p (expand-file-name "skill.yaml" entry)))
              (push (cons (file-name-nondirectory entry) entry) skills))))))
    (nreverse skills)))

(defun aiaos-cli-skill--parse-metadata (skill-path)
  "Parse skill metadata and convert keys to symbols"
  (let ((yaml-file (expand-file-name "skill.yaml" skill-path))
        (data))
    (when (file-exists-p yaml-file)
      (with-temp-buffer
        (insert-file-contents yaml-file)
        (setq data (yaml-parse-string (buffer-string))))
      (aiaos-cli-skill--ht-keys-to-symbols data))))

(defun aiaos-cli-skill--ht-keys-to-symbols (ht)
  "Recursively convert hash-table string keys to symbols"
  (if (hash-table-p ht)
      (let ((new-ht (make-hash-table :test 'equal :size (hash-table-count ht))))
        (maphash (lambda (k v)
                   (puthash (if (stringp k) (intern k) k)
                            (aiaos-cli-skill--ht-keys-to-symbols v)
                            new-ht))
                 ht)
        new-ht)
    ht))


(defun aiaos-cli-skill--read-yaml-file (file)
  "Read YAML file"
  (with-temp-buffer
    (insert-file-contents file)
    (yaml-parse-string (buffer-string))))

(defun aiaos-cli--write-yaml-file (file data)
  "Write YAML file"
  (require 'yaml nil t)
  (with-temp-buffer
    (insert (yaml-encode data))
    (write-file file)))

;; NOTE: aiaos-cli-skill-load and aiaos-cli-skill-list are provided by the
;; authoritative frontend aiaos-cli.el (consolidated build).  The old
;; skill.yaml-metadata-based implementations are superseded.

(defun aiaos-cli-skill--check-dependency (dep)
  "Check dependency"
  t)

(defun aiaos-cli-skill--ht-to-plist (ht)
  "Convert hash-table to plist with keyword keys"
  (let ((plist '()))
    (maphash (lambda (k v)
               (setq plist (cons (intern (format ":%s" (symbol-name k))) (cons v plist))))
             ht)
    plist))

(defun aiaos-cli-skill--convert-args-spec (args-ht-list)
  "Convert list of hash-table args to args-spec format: (name required? type doc)"
  (mapcar (lambda (ht)
            (let ((plist (aiaos-cli-skill--ht-to-plist ht)))
              (list (plist-get plist :name)
                    (plist-get plist :required)
                    (plist-get plist :type)
                    (plist-get plist :description))))
          args-ht-list))

(defun aiaos-cli-skill--convert-options-spec (options-ht-list)
  "Convert hash-table options to options-spec format."
  (mapcar (lambda (ht)
            (let ((plist (aiaos-cli-skill--ht-to-plist ht)))
              (list (plist-get plist :name)
                    (plist-get plist :short)
                    (plist-get plist :type)
                    (plist-get plist :default)
                    (plist-get plist :description))))
          options-ht-list))


(defun aiaos-cli-skill--load-command (skill-name cmd entry-path)
  "Load single command"
  (let ((ext (file-name-extension entry-path)))
    (cond
     ((string= ext "el")
      (let ((domain (or (gethash 'domain cmd) skill-name))
            (verb   (gethash 'name cmd)))
        (load-file entry-path)
        ;; 声明式注册：若命令 .el 通过 put 'aiaos-cli-command-spec 声明，
        ;; 且尚未注册到路由表，则自动注册
        (let* ((spec-var (intern (concat "aiaos-cli-skill-" skill-name "/" verb)))
               (spec    (get spec-var 'aiaos-cli-command-spec)))
          (when spec
            (message "[debug] spec found for %s/%s" domain verb)
            (unless (aiaos-cli-find-command domain verb)
              (message "[debug] registering %s/%s" domain verb)
              (aiaos-cli-register-command
               domain verb
               (lambda (args options ctx)
                 (let* ((fn (intern (concat "aiaos-cli-skill-" skill-name "/" verb))))
                   (funcall fn args options ctx)))
               :description (plist-get spec :description)
               :args (plist-get spec :args)
               :options (plist-get spec :options)
               :skill skill-name))))))
     ((string= ext "py")
      (aiaos-cli-register-command
       (gethash 'domain cmd) (gethash 'name cmd)
       (aiaos-cli-skill--make-python-wrapper skill-name (gethash 'name cmd) entry-path)
       :description (gethash 'description cmd)
       :args (aiaos-cli-skill--convert-args-spec (gethash 'args cmd))
       :options (gethash 'options cmd)
       :skill skill-name))
     ((string= ext "sh")
      (aiaos-cli-register-command
       (gethash 'domain cmd) (gethash 'name cmd)
       (aiaos-cli-skill--make-shell-wrapper skill-name (gethash 'name cmd) entry-path)
       :description (gethash 'description cmd)
       :args (aiaos-cli-skill--convert-args-spec (gethash 'args cmd))
       :options (gethash 'options cmd)
       :skill skill-name))
     (t
      (aiaos-cli-log-warn "Unsupported command type: %s" entry-path)))))

(defun aiaos-cli-skill--make-python-wrapper (skill-name cmd-name script-path)
  "Create Python command wrapper (no-op; Python is not used in pure-elisp build)."
  (declare (ignore script-path))
  (lambda (args options ctx)
    (declare (ignore args options ctx))
    (aiaos-cli--result-error "PYTHON_UNSUPPORTED"
                             (format "Skill %s/%s requires Python, which is disabled in pure-elisp mode"
                                     skill-name cmd-name))))

(defun aiaos-cli-skill--make-shell-wrapper (skill-name cmd-name script-path)
  "Create Shell command wrapper"
  (lambda (args options ctx)
    (declare (ignore options ctx))
    (let ((proc (aiaos-cli-process-start
                 (format "%s-%s" skill-name cmd-name)
                 "bash" (list script-path)
                 (lambda (p output)
                   (let ((result (json-read-from-string output)))
                     (aiaos-cli--display-result result))))))
      (proc-input proc (json-encode
                        `((args . ,args)
                          (options . ,options)
                          (context . ,(aiaos-cli-context-to-plist ctx))))))))

(defun aiaos-cli-context-to-plist (ctx)
  "Convert context to plist"
  (when ctx
    (list :history (aiaos-cli--context-history ctx)
          :metadata (aiaos-cli--context-metadata ctx))))

(defun aiaos-cli-skill-unload (name)
  "Unloading skill"
  (let ((skill (cl-find name aiaos-cli--loaded-skills
                        :key 'aiaos-cli-skill-name :test 'string=)))
    (if (not skill)
        (aiaos-cli--result-error "NOT_LOADED" (format "Skill not loaded: %s" name))
      (progn
       (setq aiaos-cli--loaded-skills
             (cl-remove name aiaos-cli--loaded-skills
                        :key 'aiaos-cli-skill-name :test 'string=))
       (aiaos-cli-log-info "Unloading skill: %s" name)
       (aiaos-cli--result-success (list :name name))))))

;; NOTE: aiaos-cli-skill-list is provided by aiaos-cli.el (see above).

(defun aiaos-cli-skill-create-template (name path &optional type)
  "Create skill template"
  (let ((skill-dir (expand-file-name name path)))
    (make-directory skill-dir t)
    (make-directory (expand-file-name "commands" skill-dir) t)
    (make-directory (expand-file-name "hooks" skill-dir) t)
    (let ((metadata `((name . ,name)
                      (version . "0.1.0")
                      (description . "New skill description")
                      (author . ,(user-full-name))
                      (license . "MIT")
                      (type . ,(or type "user"))
                      (dependencies
                       (core . ">=1.0.0")
                       (skills . nil)
                       (system . nil))
                      (commands
                       (example . "Example command")))))
      (write-region (aiaos-cli--yaml-encode metadata) nil
                    (expand-file-name "skill.yaml" skill-dir)))
      (let ((commands-dir (expand-file-name "commands" skill-dir)))
        (write-region "" nil (expand-file-name ".gitkeep" commands-dir))
        (let ((hooks-dir (expand-file-name "hooks" skill-dir)))
          (write-region "" nil (expand-file-name ".gitkeep" hooks-dir))
          (let ((command-file (expand-file-name (format "commands/%s.el" name) skill-dir)))
            (write-region "" nil command-file)
            (let ((example-file (expand-file-name (format "commands/example.el" skill-dir))))
              (write-region "" nil example-file)
              (insert-file-contents command-file)
              (goto-char (point-min))
              (insert (format ";;; %s.el — %s skill command\n" name name))
              (insert "\n")
              (insert "(require 'aiaos-cli)\n")
              (insert "\n")
              (insert "(defun aiaos-cli-skill-%s/example (args options ctx)\n" name)
              (insert (format "  \"Execute the %s example command\"\n" name))
              
              (insert (format "  (aiaos-cli--result-success `((message . \"Hello from %s!\")))\n\n" name))
              (insert (format "(aiaos-cli-register-command\n \"%s\" \"example\"\n" name))
              (insert (format " #'aiaos-cli-skill-%s/example\n" name))
              (insert " :description \"Example command\"\n")
              (insert " :args '((:name \"arg\" :type string :description \"argument\"))\n")
              (insert " :options nil)\n\n")
              (insert (format "(provide 'aiaos-cli-skill-%s/commands/example)\n" name))
              (write-region nil nil command-file)))
          (aiaos-cli-log-info "Creating skill template: %s" skill-dir)
          (aiaos-cli--result-success :path skill-dir)))))

(aiaos-cli-register-command
 "skill" "list"
 (lambda (args options ctx)
   (ignore args)
  (declare (ignore options ctx))
   (aiaos-cli-skill-list))
 :description "List all skills"
 :args nil
 :options nil)

(aiaos-cli-register-command
 "skill" "load"
 (lambda (args options ctx)
   (declare (ignore options ctx))
   (aiaos-cli-skill-load (plist-get args :name)))
 :description "Loading skill"
 :args '((:name "name" :type string :required t :description "Skill name"))
 :options nil)

(aiaos-cli-register-command
 "skill" "unload"
 (lambda (args options ctx)
   (declare (ignore options ctx))
   (aiaos-cli-skill-unload (plist-get args :name)))
 :description "Unloading skill"
 :args '((:name "name" :type string :required t :description "Skill name"))
 :options nil)

(aiaos-cli-register-command
 "skill" "create"
 (lambda (args options ctx)
   (ignore ctx)
   (aiaos-cli-skill-create-template (plist-get args :name)
                                    (plist-get options :path)
                                    (plist-get options :type)))
 :description "Creating skill template"
 :args '((:name "name" :type string :required t :description "Skill name"))
 :options '((:name "path" :short "p" :type string :description "Create path" :default "~/.config/aiaos/skills")
            (:name "type" :short "t" :type string :description "Skill type" :default "user")))

(provide 'aiaos-cli-skill)
;;; aiaos-cli-skill.el ends here

;; --- R636 补齐：YAML/Context/Process 辅助函数（修复未定义函数）---

(defun aiaos-cli--read-yaml-file (file)
  "Read YAML file (alias for aiaos-cli-skill--read-yaml-file)."
  (aiaos-cli-skill--read-yaml-file file))

(defun aiaos-cli--yaml-encode (data)
  "Encode DATA to YAML string."
  (require 'yaml nil t)
  (yaml-encode data))

(defun aiaos-cli--context-history (ctx)
  "Return history entries of CONTEXT (empty list if none)."
  (when ctx
    (or (cdr (assq :history ctx)) '())))

(defun aiaos-cli--context-metadata (ctx)
  "Return metadata of CONTEXT (empty list if none)."
  (when ctx
    (or (cdr (assq :metadata ctx)) '())))

(defun aiaos-cli-process-start (name program args &optional callback)
  "Start PROGRAM with ARGS under NAME; CALLBACK receives (proc output)."
  (let ((proc (start-process name nil program
                             (if (stringp args) args (mapconcat 'identity args " ")))))
    (when callback
      (set-process-filter proc
        (lambda (p output) (funcall callback p output))))
    proc))

(defun proc-input (proc text)
  "Send TEXT to PROC stdin (wrapper around process-send-string)."
  (process-send-string proc text))
