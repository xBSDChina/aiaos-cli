;;; commands/version.el --- 内置版本命令 -*- lexical-binding: t; -*-

;;; Code:

(defun aiaos-cli-skill-builtin/version (&rest _args)
  "显示 AIAOS CLI 版本信息。

R642 FIX: 之前把 alist `((version . ...) (output . ...))' 传给
`aiaos-cli--result-success'，而根 `aiaos-cli.el' 的本地版本只做
`(append '(:status \"success\") data)'，不做 alist→plist 展平，
导致返回的 plist 里 `:version' 取不到、并且混入一个嵌套 list。
现在直接返回扁平 plist，与测试断言（`plist-get r :version'）一致。
版本号从 `aiaos-cli-version' 读取，避免硬编码与 VERSION 文件漂移。"
  (ignore _args)
  (let ((v (if (boundp 'aiaos-cli-version) aiaos-cli-version "unknown")))
    (list :status "success"
          :version v
          :output (format "aiaos-cli %s" v))))

(aiaos-cli-register-command
 "builtin" "version"
 #'aiaos-cli-skill-builtin/version
 :description "显示版本信息"
 :args '()
 :options '()
 :skill "builtin")

(provide 'aiaos-cli-skill-builtin/commands/version)
;;; commands/version.el ends here
