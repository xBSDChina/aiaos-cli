;;; on-load.el --- skill-management skill: on-load hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos-cli_skills.md §4, on-load is called once when the skill
;;; is loaded. It is used for initialization and validation.

;;; 设计原则（继承 R2200 固化模板）：
;;;   1. 默认无副作用（不写文件、不弹交互），避免 batch 环境出错
;;;   2. 预加载所有命令模块，确保技能加载后命令立即可用
;;;   3. 任何异常必须被吞掉，绝不能阻塞技能加载

;;;###autoload
(defun aiaos-cli-skill-skill-management/on-load ()
  "Called when the skill-management skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-skill-management/validate nil t)
  (require 'aiaos-cli-skill-skill-management/list nil t)
  (require 'aiaos-cli-skill-skill-management/run nil t)
  (require 'aiaos-cli-skill-skill-management/deps nil t)
  (message "aiaos-cli: skill-management skill loaded"))

(provide 'aiaos-cli-skill-skill-management/on-load)
;;; on-load.el ends here
