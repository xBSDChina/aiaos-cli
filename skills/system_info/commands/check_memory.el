;;; commands/check_memory.el --- 内存信息检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查内存使用情况，包括总内存、已用、可用、缓存等

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-memory (args options ctx)
  "检查内存信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore ctx)
  
  (let ((json-output (or (plist-get options :json) nil))
        (human-readable (or (plist-get options :human) t)))
    
    ;; 获取内存信息
    (let ((mem-info (aiaos-cli-system--get-memory-info)))
      (if json-output
          (aiaos-cli--result-success mem-info)
        ;; 文本格式输出
        (let ((output-lines '()))
          (push "=== 内存信息 ===" output-lines)
          (push (format "总内存: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'total mem-info)))
                        (format "%d bytes" (cdr (assoc 'total mem-info))))) output-lines)
          (push (format "已用内存: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'used mem-info)))
                        (format "%d bytes" (cdr (assoc 'used mem-info))))) output-lines)
          (push (format "可用内存: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'available mem-info)))
                        (format "%d bytes" (cdr (assoc 'available mem-info))))) output-lines)
          (push (format "缓存: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'buffers mem-info)))
                        (format "%d bytes" (cdr (assoc 'buffers mem-info))))) output-lines)
          (push (format "缓存(高速): %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'cached mem-info)))
                        (format "%d bytes" (cdr (assoc 'cached mem-info))))) output-lines)
          (push (format "Swap总: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'swap_total mem-info)))
                        (format "%d bytes" (cdr (assoc 'swap_total mem-info))))) output-lines)
          (push (format "Swap已用: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'swap_used mem-info)))
                        (format "%d bytes" (cdr (assoc 'swap_used mem-info))))) output-lines)
          (push (format "Swap可用: %s" (if human-readable
                          (aiaos-cli-system--format-bytes (cdr (assoc 'swap_available mem-info)))
                        (format "%d bytes" (cdr (assoc 'swap_available mem-info))))) output-lines)
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,mem-info))))))))

(aiaos-cli-register-command
 "system_info" "check_memory"
 #'aiaos-cli-skill-system-info/check-memory
 :description "检查内存使用情况"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "human" :short "h" :type boolean :default t :description "以人类可读格式显示"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-memory)
;;; commands/check_memory.el ends here
