;;;; commands/lowercase.el --- text-tools: lowercase command -*- lexical-binding: t -*-

;; Copyright (C) 2026 AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 将文本转换为小写。

;;; Code:

(require 'aiaos-cli-core)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-text-tools/lowercase (args _options _ctx)
  "将文本转换为小写。
ARGS 为 CLI 构建的扁平 plist，如 (:message \"Hello\")。"
  (let* ((text (or (plist-get args :message) (plist-get args :text) ""))
         (result (downcase text)))
    (aiaos-cli--result-success
     :data result
     :skill "text-tools"
     :command "lowercase")))

(aiaos-cli-register-command
 "text-tools" "lowercase"
 #'aiaos-cli-skill-text-tools/lowercase
 :description "将文本转换为小写"
 :args '((:name "text" :type string :required t :description "要转换的文本"))
 :options '()
 :skill "text-tools")

(provide 'aiaos-cli-skill-text-tools/commands/lowercase)
;;; commands/lowercase.el ends here
