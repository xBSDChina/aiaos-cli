;;; commands/skill.el --- 技能管理命令 -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-skill)
(require 'cl-lib)

(defun aiaos-cli-skill-builtin/skill-list (_args _options _ctx)
  "List loaded skills."
    (let* ((skills-list aiaos-cli--loaded-skills)
         (skill-names (mapcar (lambda (s)
                                (aiaos-cli-skill-name s))
                              skills-list))
         (output (if skill-names
                     (format "Loaded skills (%d):\n%s"
                             (length skill-names)
                             (mapconcat (lambda (n)
                                          (format "  - %s" n))
                                        skill-names "\n"))
                   "No skills loaded")))
    (aiaos-cli--result-success
     :skills skill-names
     :output output)))

(defun aiaos-cli-skill-builtin/skill-info (args _options _ctx)
  "Show details for a single skill."
    (let ((name (aiaos-cli--arg-value args "name")))
    (if (not name)
        (aiaos-cli--result-error "MISSING_ARG" "skill info requires <name>")
      (let ((skill (cl-find name aiaos-cli--loaded-skills
                            :key 'aiaos-cli-skill-name
                            :test 'string=)))
        (if (not skill)
            (aiaos-cli--result-error "SKILL_NOT_FOUND"
                                     (format "Skill '%s' not loaded" name))
          (let ((output (format "Skill: %s\nVersion: %s\nDescription: %s\nAuthor: %s\nPath: %s\nEnabled: %s"
                                (aiaos-cli-skill-name skill)
                                (aiaos-cli-skill-version skill)
                                (aiaos-cli-skill-description skill)
                                (aiaos-cli-skill-author skill)
                                (aiaos-cli-skill-path skill)
                                (aiaos-cli-skill-enabled skill))))
            (aiaos-cli--result-success
             :skill skill
             :output output)))))))

(defun aiaos-cli-skill-builtin/skill-install (args _options _ctx)
  "Install a skill from a directory path (copy into user skill dir).

The source directory must contain a `skill.yaml'. The skill is
copied into `aiaos-cli-skill-user-dir' and registered in the
loaded-skills table so it can be enabled/disabled immediately.
"
    (let ((src (aiaos-cli--arg-value args "path")))
    (if (not src)
        (aiaos-cli--result-error "MISSING_ARG"
                                 "skill install requires <path>")
      (unless (file-directory-p src)
        (aiaos-cli--result-error "NOT_A_DIRECTORY"
                                 (format "Source path is not a directory: %s" src)))
      (unless (file-exists-p (expand-file-name "skill.yaml" src))
        (aiaos-cli--result-error "MISSING_MANIFEST"
                                 (format "No skill.yaml in %s" src)))
      (let* ((name (file-name-nondirectory (directory-file-name src)))
             (dest-dir (expand-file-name "~/.config/aiaos/skills"))
             (dest (expand-file-name name dest-dir)))
        (make-directory dest-dir t)
        (copy-tree src dest)
        ;; Register the installed skill in-memory.
        (let ((skill (list :name name
                           :path dest
                           :enabled t
                           :version "1.0.0"
                           :description "installed"
                           :author "user"
                           :license "MIT"
                           :metadata '()
                           :commands '()
                           :hooks '())))
          (setq aiaos-cli--loaded-skills
                (cons skill (cl-remove name aiaos-cli--loaded-skills
                                       :test (lambda (s)
                                               (string= (aiaos-cli-skill-name s) name))))))
        (aiaos-cli--result-success
         :name name
         :path dest
         :output (format "Installed skill '%s' -> %s" name dest))))))

(defun aiaos-cli-skill-builtin/skill-enable (args _options _ctx)
  "Enable a loaded skill."
    (let ((name (aiaos-cli--arg-value args "name")))
    (if (not name)
        (aiaos-cli--result-error "MISSING_ARG"
                                 "skill enable requires <name>")
      (let ((skill (cl-find name aiaos-cli--loaded-skills
                            :key 'aiaos-cli-skill-name
                            :test 'string=)))
        (if (not skill)
            (aiaos-cli--result-error "SKILL_NOT_FOUND"
                                     (format "Skill '%s' not loaded" name))
          (setf (plist-get skill :enabled) t)
          (aiaos-cli--result-success
           :name name
           :enabled t
           :output (format "Enabled skill '%s'" name)))))))

(defun aiaos-cli-skill-builtin/skill-disable (args _options _ctx)
  "Disable a loaded skill."
    (let ((name (aiaos-cli--arg-value args "name")))
    (if (not name)
        (aiaos-cli--result-error "MISSING_ARG"
                                 "skill disable requires <name>")
      (let ((skill (cl-find name aiaos-cli--loaded-skills
                            :key 'aiaos-cli-skill-name
                            :test 'string=)))
        (if (not skill)
            (aiaos-cli--result-error "SKILL_NOT_FOUND"
                                     (format "Skill '%s' not loaded" name))
          (setf (plist-get skill :enabled) nil)
          (aiaos-cli--result-success
           :name name
           :enabled nil
           :output (format "Disabled skill '%s'" name)))))))

;; 参数读取辅助由 aiaos-cli-registry.el 提供（aiaos-cli--arg-value）。

;; 注册命令
(aiaos-cli-register-command
 "builtin" "skill-list"
 #'aiaos-cli-skill-builtin/skill-list
 :description "列出已加载技能"
 :args '()
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "builtin" "skill-info"
 #'aiaos-cli-skill-builtin/skill-info
 :description "查看技能详情"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "builtin" "skill-install"
 #'aiaos-cli-skill-builtin/skill-install
 :description "从目录安装技能"
 :args '((:name "path" :type string :required t :description "技能目录路径"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "builtin" "skill-enable"
 #'aiaos-cli-skill-builtin/skill-enable
 :description "启用技能"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "builtin" "skill-disable"
 #'aiaos-cli-skill-builtin/skill-disable
 :description "禁用技能"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")

(provide 'aiaos-cli-skill-builtin/commands/skill)
;;; commands/skill.el ends here

;; R637: 同时在 "skill" 域下注册别名，使 `aiaos-cli skill list' 等
;; 用户友好的调用形式可以直接路由到对应 handler（`aiaos-cli-execute'
;; 使用 "domain/action" 拼接键查找，因此 domain 必须是 "skill"）。
(aiaos-cli-register-command
 "skill" "list"
 #'aiaos-cli-skill-builtin/skill-list
 :description "列出已加载技能"
 :args '()
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "skill" "info"
 #'aiaos-cli-skill-builtin/skill-info
 :description "查看技能详情"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "skill" "install"
 #'aiaos-cli-skill-builtin/skill-install
 :description "从目录安装技能"
 :args '((:name "path" :type string :required t :description "技能目录路径"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "skill" "enable"
 #'aiaos-cli-skill-builtin/skill-enable
 :description "启用技能"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")

(aiaos-cli-register-command
 "skill" "disable"
 #'aiaos-cli-skill-builtin/skill-disable
 :description "禁用技能"
 :args '((:name "name" :type string :required t :description "技能名称"))
 :options '()
 :skill "builtin")
