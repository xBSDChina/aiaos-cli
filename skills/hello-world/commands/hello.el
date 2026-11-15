;;; hello.el --- hello-world skill: hello command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-hello-world/hello (args &rest options)
  "Greet a name.

ARGS is a plist with :name.
OPTIONS is a plist with :greeting.

R9001: 参数类型转换契约修复。
此前 `(stringp name)` 严格校验拒绝 number 类型参数（JSON 数字），
违反 skills.md §2 类型转换契约。现改为宽松校验：
- number → (format \"%s\" name) 自动转换为字符串
- string → 直接使用
- 其他类型 → 报错"
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (raw-name (plist-get args :name))
         (name (cond
                ((stringp raw-name) raw-name)
                ((numberp raw-name) (format "%s" raw-name))
                (t nil)))
         (greeting (or (plist-get opts :greeting) "Hello")))
    (unless name
      (error "aiaos-cli-skill-hello-world/hello: missing :name"))
    (list :status "ok"
          :message (format "%s, %s!" greeting name)
          :skill "hello-world"
          :command "hello"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-hello-world/hello)
