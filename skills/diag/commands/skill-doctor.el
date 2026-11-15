;;; aiaos-cli-skill-diag/commands/skill-doctor.el --- 技能健康检查 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; R644: 诊断技能 diag/skill-doctor
;;
;; 目标：对每个已加载技能做结构性健康检查，报告：
;;   1) 元数据完整性（name/version/description 是否存在）
;;   2) 命令 entry 文件是否存在（skill.yaml 声明 vs 磁盘）
;;   3) 命令注册一致性（skill.yaml 声明 vs 路由表实际注册）
;;   4) 未加载技能的发现（skill-dirs 下存在但未加载）
;; 实现要点：
;;   - 不依赖正则（Debian Emacs [[:space:]] 换行失效，见 check-registry.el 注释）
;;   - 使用 cl-lib + hash-table 做 O(1) 查询
;;   - 与 check-registry 互补：check-registry 看"函数↔注册"，doctor 看"技能↔路由"

(require 'cl-lib)
(require 'aiaos-cli-core)
(require 'aiaos-cli-skill)
(require 'aiaos-cli-router)

(declare-function aiaos-cli--loaded-skills "aiaos-cli-skill")

(defconst aiaos-cli-skill-doctor--required-meta-fields
  '("name" "version" "description")
  "skill.yaml 必需字段")

(defun aiaos-cli-skill-doctor--skill-dirs ()
  "Return list of skill search directories."
  (let ((dirs (symbol-value 'aiaos-cli-skill-dirs)))
    (if (and dirs (listp dirs)) dirs '())))

(defun aiaos-cli-skill-doctor--registered-keys ()
  "Return set of registered command keys as hash-table of key->t."
  (let ((ht (make-hash-table :test 'equal)))
    (maphash (lambda (k _) (puthash k t ht)) aiaos-cli--commands)
    ht))

(defun aiaos-cli-skill-doctor--find-skill-yaml (name)
  "Return path to skill.yaml for skill NAME, or nil."
  (let ((dirs (aiaos-cli-skill-doctor--skill-dirs))
        (found nil))
    (dolist (d dirs)
      (let ((p (expand-file-name (concat name "/skill.yaml") d)))
        (when (and (file-exists-p p) (not found))
          (setq found p))))
    found))

(defun aiaos-cli-skill-doctor--commands-to-list (commands)
  "Normalize COMMANDS to a list regardless of hash-table/list/vector type."
  (cond
   ((hash-table-p commands)
    (let ((lst '()))
      (maphash (lambda (k v) (push (cons k v) lst)) commands)
      lst))
   ((vectorp commands)
    (let ((lst '()))
      (cl-loop for x across commands do (push x lst))
      lst))
   ((listp commands) (append commands nil))
   (t '())))

(defun aiaos-cli-skill-doctor--check-skill (skill)
  "Run health check on a single loaded SKILL. Return plist of findings."
  (let* ((name (aiaos-cli-skill-name skill))
         (version (aiaos-cli-skill-version skill))
         (description (aiaos-cli-skill-description skill))
         (path (aiaos-cli-skill-path skill))
         (commands (aiaos-cli-skill-commands skill))
         (yaml (aiaos-cli-skill-doctor--find-skill-yaml name))
         (missing-entries '())
         (unregistered '())
         (missing-fields '())
         (registered-keys (aiaos-cli-skill-doctor--registered-keys))
         (skill-dir (or path (file-name-directory yaml)))
         (cmd-list (aiaos-cli-skill-doctor--commands-to-list commands))
         (n-registered 0))
    ;; 1) 元数据完整性 (top-level plist fields, NOT metadata hash-table)
    (when (null name) (push "name" missing-fields))
    (when (null version) (push "version" missing-fields))
    (when (null description) (push "description" missing-fields))
    ;; 2) 命令 entry 文件存在性 + 3) 注册一致性
    (mapc
     (lambda (cmd)
       (let* ((cmd-name (gethash 'name cmd))
              (entry (gethash 'entry cmd))
              (entry-path (and entry (expand-file-name entry skill-dir)))
              (key (concat name "/" cmd-name)))
         (when (and entry-path (not (file-exists-p entry-path)))
           (push (list :command cmd-name :entry entry) missing-entries))
         (if (gethash key registered-keys)
             (setq n-registered (1+ n-registered))
           (push (list :command cmd-name :key key) unregistered))))
     cmd-list)
    (list :name name
          :path skill-dir
          :yaml-path yaml
          :n-commands (length cmd-list)
          :n-registered n-registered
          :missing-fields missing-fields
          :missing-entries missing-entries
          :unregistered unregistered
          :status (if (or missing-fields missing-entries unregistered)
                      "warning" "ok"))))

(defun aiaos-cli-skill-doctor--find-unloaded ()
  "Return list of skill.yaml files found on disk but not loaded."
  (let ((loaded (mapcar 'aiaos-cli-skill-name aiaos-cli--loaded-skills))
        (dirs (aiaos-cli-skill-doctor--skill-dirs))
        (unloaded '()))
    (dolist (d dirs)
      (when (file-directory-p d)
        (dolist (f (directory-files d t "\\.yaml$"))
          (let* ((dir (file-name-directory f))
                 (name (file-name-nondirectory dir)))
            (when (not (member name loaded))
              (push (list :name name :path f) unloaded))))))
    unloaded))

(defun aiaos-cli-skill-doctor--check (strict json?)
  "Run doctor on all loaded skills. STRICT makes any warning a failure."
  (let* ((loaded (symbol-value (quote aiaos-cli--loaded-skills)))
         (reports (mapcar #'aiaos-cli-skill-doctor--check-skill loaded))
         (unloaded (aiaos-cli-skill-doctor--find-unloaded))
         (total-issues 0)
         (any-warning nil))
    (dolist (r reports)
      (let ((n (+ (length (plist-get r :missing-fields))
                  (length (plist-get r :missing-entries))
                  (length (plist-get r :unregistered)))))
        (setq total-issues (+ total-issues n))
        (when (> n 0) (setq any-warning t))))
    (when (> (length unloaded) 0)
      (setq total-issues (+ total-issues (length unloaded))))
    (aiaos-cli--result-success
     :status (if (and strict any-warning) "failed" "ok")
     :strict strict
     :json json?
     :n-skills (length loaded)
     :n-unloaded (length unloaded)
     :total-issues total-issues
     :reports reports
     :unloaded unloaded)))

(defun aiaos-cli-skill-diag/skill-doctor (_args opts _ctx)
  "Check health of all loaded skills."
  (let* ((opts (or opts '()))
         (strict (plist-get opts :strict))
         (json? (plist-get opts :json)))
    (aiaos-cli-skill-doctor--check strict json?)))

(put 'aiaos-cli-skill-diag/skill-doctor
     'aiaos-cli-command-spec
     '(:domain "diag"
       :verb "skill-doctor"
       :description "技能健康检查：元数据完整性 + entry 文件存在 + 注册一致性"
       :args '()
       :options '((:strict "strict" "s" boolean nil "严格模式：任何 warning 视为失败")
                  (:json "json" "j" boolean nil "JSON 格式输出")
                  (:name "name" "n" string nil "仅检查指定技能（预留）"))
       :skill "diag"))

(provide 'aiaos-cli-skill-diag/commands/skill-doctor)
;;; aiaos-cli-skill-diag/commands/skill-doctor.el ends here
