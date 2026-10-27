;;; on-load.el --- skill-management skill: on-load hook -*- lexical-binding: t; -*-

;;; Per ~/aiaos-cli_skills.md §4, on-load is called once when the skill
;;; is loaded. It is used for initialization and validation.

;;; 设计原则（继承 R2200 固化模板）：
;;;   1. 默认无副作用（不写文件、不弹交互），避免 batch 环境出错
;;;   2. 通过 message 输出轻量加载确认
;;;   3. 任何异常必须被吞掉，绝不能阻塞技能加载

(defun aiaos-cli-skill-skill-management/on-load ()
  "Called when the skill-management skill is loaded."
  (message "aiaos-cli: skill-management skill loaded"))

(provide 'aiaos-cli-skill-skill-management/on-load)
;;; on-load.el ends here
