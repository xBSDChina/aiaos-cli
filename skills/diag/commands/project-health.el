;; lisp/skills/diag/commands/project-health.el --- 项目健康检查 -*- lexical-binding: t -*-

;;; Commentary:
;; R664: diag/project-health — 项目级健康检查命令。
;;
;; 检查维度：
;;   1. 备份文件统计（.bak.r* 未归档文件计数）
;;   2. 文档完整性（README.md、CHANGELOG.md、SKILL.md、VERSION）
;;   3. 版本一致性（VERSION 文件与 SKILL.md 中的 Version: 字段）
;;   4. 代码规模统计（lisp/ 下 .el 文件的行数与 defun 数量）
;;   5. TODO/FIXME 标记计数（lisp/ 下源码中的待办标记）
;;   6. 模块统计（lisp/skills/ 下的技能目录数量）
;;
;; 返回值结构：
;;   (:status "healthy"|"warning"|"error"
;;    :version "1.0.36"
;;    :backup-files 42
;;    :total-lines 1234
;;    :total-defuns 56
;;    :missing-docs ()
;;    :todo-count 3
;;    :module-count 12
;;    :issues ((...)))
;;
;;; Code:
(require 'cl-lib)
(require 'aiaos-cli-core)

;; Helper: Count regexp matches in a string
(defun aiaos-diag-project-health--count-matches (regexp str)
  "Count matches of REGEXP in STR."
  (let ((count 0)
        (start 0))
    (while (string-match regexp str start)
      (setq count (1+ count))
      (setq start (match-end 0)))
    count))


(defconst aiaos-diag-project-health--docs
  '("design.md" "CHANGELOG.md" "README.md" "SKILL.md")
  "项目级文档文件清单。")

(defconst aiaos-diag-project-health--todos
  '("TODO" "FIXME" "XXX")
  "源码中需要关注的标记关键词。")

(defconst aiaos-diag-project-health--config-keys
  '(version skills)
  "配置文件中必需的键名。")

;; ------------------------------------------------------------------
;; 备份文件统计
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--count-backups (dir)
  "统计 dir 下未归档的 .bak.r* 备份文件数量。

仅扫描顶层目录，不递归子目录。
返回整数计数。"
  (let ((count 0))
    (dolist (f (directory-files dir))
      (when (and (file-regular-p (expand-file-name f dir))
                 (string-match-p "\\.bak\\.r" f))
        (setq count (1+ count))))
    count))

;; ------------------------------------------------------------------
;; lisp/ 代码规模统计
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--count-elisp (dir)
  "统计 lisp/ 目录下 .el 文件的代码规模。

返回 (list total-lines total-defuns)。
若 lisp/ 目录不存在，返回 (list 0 0)。"
  (let ((lisp-dir (expand-file-name "lisp" dir))
        (total-lines 0)
        (total-defuns 0))
    (if (file-directory-p lisp-dir)
        (progn
          (dolist (f (directory-files lisp-dir))
            (when (string-suffix-p ".el" f)
              (let ((full (expand-file-name f lisp-dir)))
                (with-temp-buffer
                  (insert-file-contents full)
                  (setq total-lines
                        (+ total-lines
                           (count-lines (point-min) (point-max))))
                  (goto-char (point-min))
                  (setq total-defuns
                        (+ total-defuns
                           (count-matches
                            "^(defun \\|defmacro \\|defstruct ")))))))
          (list total-lines total-defuns))
      (list 0 0))))

;; ------------------------------------------------------------------
;; 文档完整性检查
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--check-docs (dir)
  "检查关键文档文件是否存在。

返回缺失文件列表，若全部存在则返回 nil。"
  (let ((missing nil))
    (dolist (d aiaos-diag-project-health--docs)
      (unless (file-exists-p (expand-file-name d dir))
        (push d missing)))
    missing))

;; ------------------------------------------------------------------
;; 版本一致性检查
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--check-version (dir)
  "检查 VERSION 文件与 SKILL.md 中的版本号一致性。

返回 (VERSION . ISSUES) 列表，ISSUES 包含不一致描述。
若 VERSION 文件不存在，返回 (nil . (\"VERSION 文件不存在\"))。"
  (let ((v-file (expand-file-name "VERSION" dir))
        (issues nil))
    (if (not (file-exists-p v-file))
        (cons nil (list "VERSION 文件不存在"))
      (with-temp-buffer
        (insert-file-contents v-file)
        (let ((v (string-trim (buffer-string))))
          ;; 检查 CHANGELOG.md 中的最新版本标签
          (when (file-exists-p (expand-file-name "CHANGELOG.md" dir))
            (with-temp-buffer
              (insert-file-contents
               (expand-file-name "CHANGELOG.md" dir))
              (goto-char (point-min))
              (when (re-search-forward "^## \\[\\([0-9.]+\\)\\]" nil t)
                (unless (string= v (match-string 1))
                  (push
                   (format "VERSION(%s) != CHANGELOG(%s)"
                           v (match-string 1))
                   issues))))
          ;; 检查 SKILL.md 中的 Version: 字段
          (when (file-exists-p (expand-file-name "SKILL.md" dir))
            (with-temp-buffer
              (insert-file-contents
               (expand-file-name "SKILL.md" dir))
              (goto-char (point-min))
              (when (re-search-forward "Version:\\s*\\([0-9.]+\\)" nil t)
                (unless (string= v (match-string 1))
                  (push
                   (format "VERSION(%s) != SKILL.md(%s)"
                           v (match-string 1))
                   issues))))
          (cons v issues))))))))

;; ------------------------------------------------------------------
;; TODO/FIXME 计数
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--count-todos (dir)
  "扫描 lisp/ 目录下 .el 文件中的 TODO/FIXME/XXX 标记。

返回 plist，每个关键词作为键，对应出现次数。"
  (let ((lisp-dir (expand-file-name "lisp" dir))
        (counts (list :TODO 0 :FIXME 0 :XXX 0)))
    (if (file-directory-p lisp-dir)
        (progn
          (dolist (f (directory-files lisp-dir))
            (when (string-suffix-p ".el" f)
              (with-temp-buffer
                (insert-file-contents (expand-file-name f lisp-dir))
                (let ((c (buffer-string)))
                  (dolist (p aiaos-diag-project-health--todos)
                    (let ((kw (intern (concat ":" (upcase p)))))
                      (setq counts
                            (plist-put counts kw
                                       (+ (plist-get counts kw)
                                          (aiaos-diag-project-health--count-matches
                                           (concat "\\<" p "\\>") c))))))))))
          counts)
      counts)))

;; ------------------------------------------------------------------
;; 模块统计
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--count-modules (dir)
  "统计 lisp/skills/ 下的技能模块数量。

返回子目录计数整数（排除 . 和 ..）。"
  (let ((skills-dir (expand-file-name "lisp/skills" dir))
        (count 0))
    (if (file-directory-p skills-dir)
        (dolist (d (directory-files skills-dir))
          (when (and (not (string= d "."))
                     (not (string= d ".."))
                     (file-directory-p (expand-file-name d skills-dir)))
            (setq count (1+ count))))
      count)
    count))

;; ------------------------------------------------------------------
;; 配置文件检查
;; ------------------------------------------------------------------
(defun aiaos-diag-project-health--check-config (dir)
  "检查 .aiaos-cli.json 配置文件完整性。

返回 (CFG-PATH . ISSUES) 列表。
若配置文件不存在，ISSUES 包含\"配置文件不存在\"。"
  (let ((cfg (expand-file-name ".aiaos-cli.json" dir)))
    (if (not (file-exists-p cfg))
        (cons cfg (list "配置文件不存在"))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents cfg)
            (let ((p (json-read))
                  (issues nil))
              ;; json-read 默认返回 alist，转换为 hash-table 以便 gethash
              (let ((ht (make-hash-table :test 'equal)))
                (dolist (pair p)
                  (puthash (car pair) (cdr pair) ht))
                (dolist (k aiaos-diag-project-health--config-keys)
                  (unless (gethash k ht)
                    (push (format "缺少必需键: %s" k) issues))))
              (cons cfg issues)))
        (error (cons cfg (list "JSON解析失败")))))))

;; ------------------------------------------------------------------
;; 主入口函数
;; ------------------------------------------------------------------
(defun aiaos-cli-skill-diag/project-health (_args opts _ctx)
  "主入口：执行项目健康检查。

ARGS   — 命令行参数列表（忽略）
OPTS   — 选项表（支持 --json 输出）
CTX    — 上下文（忽略）

返回 aiaos-cli-core 标准结果结构。"
  (let* ((dir (expand-file-name
               (or (getenv "AIAOS_PROJECT_ROOT")
                   default-directory)))
         (backups (aiaos-diag-project-health--count-backups dir))
         (stats (aiaos-diag-project-health--count-elisp dir))
         (missing-docs (aiaos-diag-project-health--check-docs dir))
         (v-result (aiaos-diag-project-health--check-version dir))
         (version (car v-result))
         (v-issues (cdr v-result))
         (todos (let ((c (aiaos-diag-project-health--count-todos dir))) (+ (plist-get c :TODO) (plist-get c :FIXME) (plist-get c :XXX))))
         (cfg-result (aiaos-diag-project-health--check-config dir))
         (cfg-path (car cfg-result))
         (cfg-issues (cdr cfg-result))
         (modules (aiaos-diag-project-health--count-modules dir))
         (issues nil)
         (status "healthy"))
    ;; 备份文件过多 → warning
    (when (> backups 50)
      (push (format "备份文件过多: %d 个未归档" backups) issues)
      (setq status "warning"))
    ;; 文档缺失 → warning
    (when missing-docs
      (push
       (format "文档缺失: %s"
               (mapconcat 'identity missing-docs ", "))
       issues)
      (setq status "warning"))
    ;; 版本不一致 → error
    (when v-issues
      (setq issues (append issues v-issues))
      (setq status "error"))
    ;; 配置文件问题 → warning
    (when cfg-issues
      (setq issues (append issues cfg-issues))
      (setq status "warning"))
    ;; 构建报告
    (let ((report
           (list :status status
                 :version version
                 :backup-files backups
                 :total-lines (car stats)
                 :total-defuns (cadr stats)
                 :missing-docs missing-docs
                 :todo-count todos
                 :config-path cfg-path
                 :version-issues v-issues
                 :config-issues cfg-issues
                 :module-count modules
                 :issues issues)))
      (aiaos-cli--result-success report))))

;; ------------------------------------------------------------------
;; 命令注册
;; ------------------------------------------------------------------
(put 'aiaos-cli-skill-diag/project-health
     'aiaos-cli-command-spec
     '(:domain "diag"
       :verb "project-health"
       :description
       "项目健康检查：备份统计、文档完整性、版本一致性、代码规模、TODO标记、模块统计"
       :args '()
       :options '((:json "json" "j" string nil "JSON格式输出")
                  (:strict "strict" "s" string nil "严格模式"))
       :skill "diag"))

(provide 'aiaos-cli-skill-diag/commands/project-health)
;;; project-health.el ends here
