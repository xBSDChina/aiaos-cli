;;;; commands/summarize.el --- text-tools: summarize command -*- lexical-binding: t -*-

;; Copyright (C) 2026 AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 提取文本前N个字符作为摘要。

;;; Code:

(require 'aiaos-cli-core)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-text-tools/summarize (args options _ctx)
  "提取文本前N个字符作为摘要。
ARGS 为 CLI 构建的扁平 plist，如 (:message \"Hello\")。
OPTIONS 为选项 plist。"
  (let* ((text (or (plist-get args :message) (plist-get args :text) ""))
         (max-len-str (or (plist-get options :length) "100"))
         (max-len (if (stringp max-len-str)
                      (string-to-number max-len-str)
                    max-len-str))
         (summary (substring text 0 (min max-len (length text))))
         (truncated (> (length text) max-len)))
    (aiaos-cli--result-success
     :data summary
     :skill "text-tools"
     :command "summarize"
     :truncated truncated)))

(aiaos-cli-register-command
 "text-tools" "summarize"
 #'aiaos-cli-skill-text-tools/summarize
 :description "提取文本前N个字符作为摘要"
 :args '((:name "text" :type string :required t :description "要摘要的文本"))
 :options '((:name "length" :short "l" :type integer :default 100 :description "摘要长度（字符数）"))
 :skill "text-tools")

(provide 'aiaos-cli-skill-text-tools/commands/summarize)
;;; commands/summarize.el ends here
