;;; aiaos-cli-registry.el --- AIAOS-CLI 命令注册表与技能基础设施 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; Version: 1.0.0

;;; Code:

(require 'cl-lib)
(require 'json)

(defgroup aiaos-cli-registry nil
  "AIAOS-CLI 命令注册表与技能基础设施"
  :group 'aiaos-cli)

;; 命令表：存储所有已注册的命令
;; 键格式："domain/action"，值为命令规范 plist
(defconst aiaos-cli--commands (make-hash-table :test 'equal)
  "命令注册表，键为 \"domain/action\"，值为命令规范 plist。")

;; 命令别名表：存储命令别名
;; 键为别名，值为目标命令
(defconst aiaos-cli--command-aliases (make-hash-table :test 'equal)
  "命令别名表，键为别名，值为目标命令。")

;; 已加载的技能列表
(defvar aiaos-cli--loaded-skills nil
  "已加载的技能列表。")

;; 上下文数据库
(defconst aiaos-cli--context-db (make-hash-table :test 'equal)
  "上下文数据库。")

;;; 结果辅助

(defvar aiaos-cli--json-mode nil
  "当非 nil 时，`aiaos-cli--display-result' 输出 JSON 到 stdout。")

(defvar aiaos-cli--exit-code 0 "退出码")

;; aiaos-cli--alist-to-plist is provided by the authoritative frontend
;; aiaos-cli.el (which is loaded before this registry module).

(defun aiaos-cli--result-success (&rest data)
  "Return a success result plist. DATA is an alist flattened to a flat plist."
  (append (list :status "success")
          (aiaos-cli--alist-to-plist data)))

(defun aiaos-cli--result-error (code message &rest data)
  "Return an error result plist."
  (append (list :status "error" :error-code code :error-message message)
          (aiaos-cli--alist-to-plist data)))

;;; 参数提取

(defun aiaos-cli--arg-value (args key)
  "Extract value for KEY from ARGS (hash-table, plist, or alist).

Handles keyword plists (:key val ...), symbol-keyed alists ((key . val) ...),
string-keyed alists ((\"key\" . val) ...), and hash-tables."
  (let ((kw (intern (concat ":" key))))
    (cond
     ((hash-table-p args)
      (gethash key args))
     ((and (listp args) (keywordp (car args)))
      (plist-get args kw))
     ((listp args)
      (catch 'aiaos-cli--arg-value-found
        (dolist (a args)
          (let ((k (if (consp a) (car a) a)))
            (when (or (eq k kw)
                      (eq k (intern key))
                      (and (stringp k) (string= k key))
                      (and (stringp k) (string= k (concat ":" key))))
              (throw 'aiaos-cli--arg-value-found
                     (if (consp a) (cdr a) t)))))))
     (t nil))))

;;; 命令注册

(defun aiaos-cli-register-command (domain action handler &rest kwargs)
  "Register a command.
DOMAIN is the command domain.
ACTION is the action name.
HANDLER is the handler function.
KWARGS are optional keyword arguments:
  :description - Command description
  :args - Argument specifications
  :options - Option specifications
  :tags - Command tags
  :skill - Owning skill name"
  (let ((key (format "%s/%s" domain action))
        (spec (list :domain domain
                    :action action
                    :handler handler
                    :description (or (plist-get kwargs :description) "")
                    :args (plist-get kwargs :args)
                    :options (plist-get kwargs :options)
                    :tags (plist-get kwargs :tags)
                    :skill (plist-get kwargs :skill)
                    :registered-at (current-time-string))))
    (puthash key spec aiaos-cli--commands)
    (when (fboundp 'aiaos-cli-log-debug)
      (aiaos-cli-log-debug "Command registered: %s" key))
    key))

(defun aiaos-cli-unregister-command (domain action)
  "Unregister a command."
  (let ((key (format "%s/%s" domain action)))
    (remhash key aiaos-cli--commands)
    (remhash key aiaos-cli--command-aliases)))

(defun aiaos-cli-execute (domain action args &optional opts ctx)
  "Execute a command.
DOMAIN is the command domain.
ACTION is the action name.
ARGS is the argument list.
OPTS is optional options plist.
CTX is optional context."
  (let* ((key (format "%s/%s" domain action))
         (spec (gethash key aiaos-cli--commands)))
    (if (null spec)
        (aiaos-cli--result-error "COMMAND_NOT_FOUND"
                                 (format "Command %s not found" key))
      (let ((handler (plist-get spec :handler)))
        (if (functionp handler)
            (funcall handler
                     (aiaos-cli--build-args-plist args (plist-get spec :args))
                     (aiaos-cli--alist-to-plist opts)
                     ctx)
          (aiaos-cli--result-error "INVALID_HANDLER"
                                   (format "Invalid handler for %s" key)))))))

(defun aiaos-cli--build-args-plist (args argspec)
  "Build flat plist from positional ARGS using ARGSPEC."
  (let ((plist '()))
    (when (listp args)
      (if (and (consp (car args))
               (listp (caar args)))
          ;; wrapped alist form
          (setq plist (aiaos-cli--alist-to-plist (car args)))
        ;; flat alist form
        (setq plist (aiaos-cli--alist-to-plist args))))
    plist))

(defun aiaos-cli-command-list ()
  "List all registered commands."
  (let ((cmds '()))
    (maphash (lambda (key spec)
               (push (list key (plist-get spec :description)) cmds))
             aiaos-cli--commands)
    (nreverse cmds)))

(defun aiaos-cli-find-command (domain action)
  "Find a command by domain and action."
  (let ((key (format "%s/%s" domain action)))
    (gethash key aiaos-cli--commands)))

;;; 技能访问器

(defun aiaos-cli--make-skill (name version description author license path metadata commands hooks enabled)
  "Create skill object."
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

;;; 实用辅助（供技能命令文件使用）

(defun aiaos-cli--hash-table-to-list (ht)
  "Convert hash-table HT to an alist."
  (let (result)
    (maphash (lambda (k v) (push (cons k v) result)) ht)
    (nreverse result)))

(defun aiaos-cli--count-commands (skill)
  "Count commands in SKILL (plist)."
  (length (plist-get skill :commands)))

(defun aiaos-cli--count-hooks (skill)
  "Count hooks in SKILL (plist)."
  (length (plist-get skill :hooks)))

(defun aiaos-cli--collect-errors (items)
  "Collect :error-message from a list of result ITEMS."
  (cl-loop for item in items
           when (and (listp item) (plist-get item :error-message))
           collect (plist-get item :error-message)))

(defun aiaos-cli--make-freq-entry (word count)
  "Make a frequency entry (word, count)."
  (cons word count))

(defun aiaos-cli--toposort (nodes edges)
  "Topologically sort NODES with dependency EDGES.
NODES is a list of node identifiers. EDGES is an alist mapping node -> deps.
Returns a list of node ids in topological order."
  (let ((result '())
        (visited (make-hash-table :test 'equal))
        (visiting (make-hash-table :test 'equal)))
    (cl-labels ((visit (n)
                 (unless (gethash n visited)
                   (when (gethash n visiting)
                     (error "Cycle detected at %s" n))
                   (puthash n t visiting)
                   (let ((deps (cdr (assoc n edges))))
                     (when deps
                       (mapc #'visit deps)))
                   (remhash n visiting)
                   (puthash n t visited)
                   (push n result))))
      (mapc #'visit nodes))
    (nreverse result)))

(defun aiaos-cli--validate-yaml (obj)
  "Validate that OBJ is a parsed YAML/plist structure.  Return t if valid."
  (or (listp obj) (stringp obj) (numberp obj)))

(defun aiaos-cli--yaml-get (obj key)
  "Get KEY from YAML-derived plist/alist OBJ."
  (cond
   ((and (listp obj) (keywordp (car obj))) (plist-get obj key))
   ((and (listp obj) (consp (car obj))) (cdr (assoc (substring (symbol-name key) 1) obj)))
   (t nil)))

(defun aiaos-cli--yaml-parse-deps (obj)
  "Parse dependencies from YAML OBJ."
  (let ((deps (aiaos-cli--yaml-get obj :depends)))
    (if (listp deps) deps (list deps))))

;;; slugify 辅助

(defun aiaos-cli--slugify-has-unicode-p (s)
  "Return non-nil if string S contains non-ASCII characters."
  (string-match-p "[^\x00-\x7F]" s))

(defun aiaos-cli--slugify-char-keep-p (c)
  "Return non-nil if char C should be kept in a slug."
  (or (and (>= c ?a) (<= c ?z))
      (and (>= c ?A) (<= c ?Z))
      (and (>= c ?0) (<= c ?9))))

(defun aiaos-cli--slugify-replace-underscore (c)
  "Replace underscore/space char C with a dash."
  (if (or (= c ?_) (= c ?\s)) ?- c))

(defun aiaos-cli--slugify-collapse-sep (s)
  "Collapse multiple separators in S."
  (replace-regexp-in-string "-+" "-" s))

(defun aiaos-cli--slugify-trim-separator (s)
  "Trim leading/trailing separators from S."
  (replace-regexp-in-string "^-\+\\|-\+$" "" s))

(defun aiaos-cli--slugify-translate (s)
  "Translate unicode S to ASCII approximation (minimal)."
  (replace-regexp-in-string "[^\x00-\x7F]" "" s))

(defun aiaos-cli--scan-skills-dir (dir)
  "Scan DIR for skill subdirectories, return alist of skill-name -> skill plist."
  (let (skills)
    (when (file-directory-p dir)
      (dolist (sub (directory-files dir t))
        (when (and (file-directory-p sub)
                   (not (string-match-p "\\.$" sub)))
          (let ((yaml (expand-file-name "skill.yaml" sub)))
            (when (file-exists-p yaml)
              (push (cons (file-name-nondirectory sub)
                          (list :name (file-name-nondirectory sub)
                                :path sub
                                :version "1.0.0"
                                :enabled t))
                    skills))))))
    (nreverse skills)))

(defun aiaos-cli--read-skill-meta (skill-dir)
  "Read skill metadata from SKILL-DIR's skill.yaml.  Returns a plist."
  (let ((yaml (expand-file-name "skill.yaml" skill-dir)))
    (if (file-exists-p yaml)
        (with-temp-buffer
          (insert-file-contents yaml)
          (let ((content (buffer-string)))
            (list :name (file-name-nondirectory skill-dir)
                  :path skill-dir
                  :version (or (and (string-match "version[: \t]+\\S-" content)
                                    (match-string 0 content))
                               "1.0.0")
                  :enabled t)))
      (list :name (file-name-nondirectory skill-dir)
            :path skill-dir
            :version "1.0.0"
            :enabled t))))

(defun aiaos-cli--scan-version-drift (skills)
  "Scan SKILLS for version drift.  Returns list of (name . version)."
  (let (drift)
    (dolist (s skills)
      (let ((name (if (consp s) (car s) (plist-get s :name)))
            (ver (if (consp s) (cdr s) (plist-get s :version))))
        (push (cons name ver) drift)))
    (nreverse drift)))

(defun aiaos-cli--skill-filter-by-query (skills query)
  "Filter SKILLS by QUERY string."
  (if (or (null query) (string-empty-p query))
      skills
    (cl-remove-if-not
     (lambda (s)
       (let ((name (if (consp s) (car s) (plist-get s :name))))
         (string-match-p (regexp-quote query) (or name ""))))
     skills)))

(defun aiaos-cli-skill-user-dir ()
  "Return the user skill directory (defaults to aiaos-cli-skills-dir)."
  (if (boundp 'aiaos-cli-skills-dir)
      aiaos-cli-skills-dir
    (expand-file-name "~/.emacs.d/aiaos-cli/skills")))

(defun aiaos-cli-skill-builtin ()
  "Return t for builtin skills (compatibility accessor)."
  t)

(provide 'aiaos-cli-registry)
;;; aiaos-cli-registry.el ends here
