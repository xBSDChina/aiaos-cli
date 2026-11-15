;;; commands/echo.el --- 内置回显命令 -*- lexical-binding: t; -*-

;;; Code:

(defun aiaos-cli-skill-builtin/echo (args options _ctx)
  "回显测试命令"
  (let ((message (aiaos-cli--arg-value args "message"))
        (repeat (or (plist-get options :repeat) 1)))
    (aiaos-cli--result-success
     :output (mapconcat 'identity (make-list repeat message) "\n")
     :count repeat)))

(aiaos-cli-register-command
 "builtin" "echo"
 #'aiaos-cli-skill-builtin/echo
 :description "回显测试命令"
 :args '((:name "message" :type string :required t :description "要回显的消息"))
 :options '(("repeat" "r" integer 1 "重复次数"))
 :skill "builtin")

(provide 'aiaos-cli-skill-builtin/commands/echo)
;;; commands/echo.el ends here
