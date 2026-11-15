;;; aiaos-cli-skill-diag/commands/check-registry.el --- 命令注册完整性检查 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; R636: 诊断技能 diag/check-registry
;;
;; 目标：扫描 lisp/aiaos-cli-*.el 中定义的 aiaos-cli-<domain>-<verb> 函数，
;;       与源码中 aiaos-cli-register-command 调用对比，报告"函数有、命令没挂"
;;       的静默缺陷（R635 遗留建议）。
;; 实现要点：不使用正则（Debian Emacs 中 [[:space:]] 不匹配换行，\s- 同样失效），
;;       改用 split-string 做 token 级扫描，零转义风险。

(require 'cl-lib)
(require 'aiaos-cli-core)
(require 'aiaos-cli-router)

(defun aiaos-cli-skill-diag--lisp-dir ()
  "Return the aiaos-cli lisp directory (parent of skills/)."
  (cond
   ;; 1) load-file-name 可用时（正常 load 路径）
   ((and load-file-name (file-exists-p load-file-name))
    (expand-file-name "../../.." (file-name-directory load-file-name)))
   ;; 2) 从 aiaos-cli-skill-dirs 变量推导
   ((boundp 'aiaos-cli-skill-dirs)
    (let ((d (car aiaos-cli-skill-dirs)))
      (when (and d (file-directory-p d))
        (expand-file-name ".." d))))
   ;; 3) 硬编码 fallback
   (t (expand-file-name "~/aiaos-cli/lisp"))))

(defconst aiaos-cli-skill-diag--helper-prefixes
  '("aiaos-cli-skill--"
    "aiaos-cli-router--"
    "aiaos-cli-core--"
    "aiaos-cli-config--"
    "aiaos-cli-context--"
    "aiaos-cli-session--"
    "aiaos-cli-project--"
    "aiaos-cli-log--"
    "aiaos-cli-agent--"
    "aiaos-cli-memory--"
    "aiaos-cli-plugin--"
    "aiaos-cli-registry--"
    "aiaos-cli-schedule--"
    "aiaos-cli-mcp--"
    "aiaos-cli-system--"
    "aiaos-cli-test--"
    "aiaos-cli--")
  "Helper 函数前缀白名单")

(defconst aiaos-cli-skill-diag--non-command-symbols
  '("aiaos-cli-config-get"
    "aiaos-cli-config-set"
    "aiaos-cli-config-list"
    "aiaos-cli-config-load"
    "aiaos-cli-config-save"
    "aiaos-cli-config-show"
    "aiaos-cli-config-paths"
    "aiaos-cli-config-ensure-file"
    "aiaos-cli-context-new"
    "aiaos-cli-context-get"
    "aiaos-cli-context-list"
    "aiaos-cli-context-switch"
    "aiaos-cli-context-show"
    "aiaos-cli-log-info"
    "aiaos-cli-log-warn"
    "aiaos-cli-log-error"
    "aiaos-cli-log-debug"
    "aiaos-cli-log-view"
    "aiaos-cli-version"
    "aiaos-cli-init"
    "aiaos-cli-run"
    "aiaos-cli-main"
    "aiaos-cli-register-command"
    "aiaos-cli-unregister-command")
  "已知的非命令函数（底层 API，不要求注册到路由表）")

(defun aiaos-cli-skill-diag--is-helper (sym)
  "Return t if SYM matches a known helper prefix."
  (cl-some (lambda (p) (string-prefix-p p sym))
           aiaos-cli-skill-diag--helper-prefixes))

(defun aiaos-cli-skill-diag--split-symbol (sym)
  "Split SYM into (domain . verb). Returns nil if not in expected form."
  (let* ((stripped (substring sym 10))
         (dash-pos (string-match "-" stripped)))
    (if dash-pos
        (cons (substring stripped 0 dash-pos)
              (substring stripped (1+ dash-pos)))
      nil)))

(defun aiaos-cli-skill-diag--strip-quotes (s)
  "Strip surrounding quotes from S if present."
  (if (and (>= (length s) 2)
           (eq (aref s 0) ?\")
           (eq (aref s (1- (length s))) ?\"))
      (substring s 1 (1- (length s)))
    s))

(defun aiaos-cli-skill-diag--scan-file (file)
  "Scan FILE and return (defined-symbols . registered-pairs).

Uses split-string based tokenization instead of regex, because in this
Debian Emacs build [[:space:]] and \s- do not match newlines."
  (let ((defs '()) (regs '()))
    (with-temp-buffer
      (insert-file-contents file)
      (let* ((content (buffer-string))
             (tokens (split-string content)))
        (let ((i 0))
          (while (< i (length tokens))
            (when (or (string= (nth i tokens) "defun")
                         (string= (nth i tokens) "(defun"))
              (let ((sym (nth (1+ i) tokens)))
                (when (and sym (string-prefix-p "aiaos-cli-" sym))
                  (push sym defs))))
            (setq i (1+ i))))
        (let ((i 0))
          (while (< i (length tokens))
            (when (or (string= (nth i tokens) "aiaos-cli-register-command")
                         (string= (nth i tokens) "(aiaos-cli-register-command"))
              (let ((domain (aiaos-cli-skill-diag--strip-quotes
                             (or (nth (1+ i) tokens) "")))
                    (action (aiaos-cli-skill-diag--strip-quotes
                             (or (nth (1+ (1+ i)) tokens) ""))))
                (when (and (stringp domain) (stringp action)
                           (> (length domain) 0) (> (length action) 0))
                  (push (cons domain action) regs))))
            (setq i (1+ i)))))
      (cons defs regs))))

(defun aiaos-cli-skill-diag--check (scan-dir verbose strict)
  "Scan SCAN-DIR for aiaos-cli-*.el files and report unregistered candidates."
  (let ((files (directory-files scan-dir t "^aiaos-cli-.*\\.el$" t))
        (all-defs '()) (all-regs '()) (per-file '()))
    (dolist (f files)
      (let ((result (aiaos-cli-skill-diag--scan-file f)))
        (setq all-defs (append all-defs (car result)))
        (setq all-regs (append all-regs (cdr result)))
        (push (list (file-name-nondirectory f)
                    (length (car result))
                    (length (cdr result)))
              per-file)))
    (let ((registered-set (make-hash-table :test 'equal :size 64)))
      (dolist (r all-regs)
        (puthash (concat (car r) "/" (cdr r)) t registered-set))
      (let ((candidates '()) (registered '()) (excluded '()))
        (dolist (sym (delete-dups all-defs))
          (cond
           ((aiaos-cli-skill-diag--is-helper sym)
            (push sym excluded))
           ((member sym aiaos-cli-skill-diag--non-command-symbols)
            (push sym excluded))
           (t
            (let ((parts (aiaos-cli-skill-diag--split-symbol sym)))
              (if (null parts)
                  (push sym excluded)
                (let ((key (concat (car parts) "/" (cdr parts))))
                  (if (gethash key registered-set)
                      (push (list sym key) registered)
                    (push (list sym key) candidates))))))))
        (let ((unregistered (length candidates))
              (n-registered (length registered)))
          (aiaos-cli--result-success
           :total-files (length files)
           :total-defs (length all-defs)
           :total-registered-calls (length all-regs)
           :registered-matched n-registered
           :unregistered-candidates unregistered
           :excluded (length excluded)
           :unregistered
           (mapcar (lambda (x) (list :symbol (car x) :key (cdr x))) candidates)
           :registered
           (mapcar (lambda (x) (list :symbol (car x) :key (cdr x))) registered)
           :per-file
           (mapcar (lambda (x)
                     (list :file (nth 0 x) :defs (nth 1 x) :regs (nth 2 x)))
                   per-file)
           :verbose-list
           (if verbose
               (append
                (mapcar (lambda (x) (list :symbol x :kind "excluded")) excluded)
                (mapcar (lambda (x)
                          (list :symbol (car x) :key (cdr x) :kind "registered"))
                        registered))
             nil)
           :strict (if (and strict (> unregistered 0)) t nil)
           :status (if (and strict (> unregistered 0)) "warning" "ok")))))))

(defun aiaos-cli-skill-diag/check-registry (_args opts _ctx)
  "Check command registration integrity."
  (let* ((opts (or opts '()))
         (verbose (plist-get opts :verbose))
         (strict (plist-get opts :strict))
         (path (plist-get opts :path))
         (scan-dir
          (if (and path (stringp path) (> (length path) 0))
              (expand-file-name path)
            (aiaos-cli-skill-diag--lisp-dir))))
    (unless (file-directory-p scan-dir)
      (aiaos-cli--result-error
       "SCAN_DIR_NOT_FOUND"
       (format "Scan directory not found: %s" scan-dir)))
    (aiaos-cli-skill-diag--check scan-dir verbose strict)))

(aiaos-cli-register-command
 "diag" "check-registry"
 #'aiaos-cli-skill-diag/check-registry
 :description "扫描源码检查命令注册完整性"
 :args '()
 :options '((:verbose "verbose" "v" boolean nil "详细模式")
            (:strict "strict" "s" boolean nil "严格模式")
            (:path "path" "p" string nil "扫描目录"))
 :skill "diag")

(provide 'aiaos-cli-skill-diag/commands/check-registry)
;;; aiaos-cli-skill-diag/commands/check-registry.el ends here
