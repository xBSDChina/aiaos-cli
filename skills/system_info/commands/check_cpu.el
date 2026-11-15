;;; commands/check_cpu.el --- CPU信息检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查CPU使用率、核心数、负载等信息

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-cpu (args options ctx)
  "检查CPU信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore ctx)
  
  ;; 检查是否需要JSON输出
  (let ((json-output (or (plist-get options :json) nil))
        (interval (or (plist-get options :interval) 1)))
    
    ;; 获取CPU信息（使用系统命令）
    (let* ((cpu-info (aiaos-cli-system--get-cpu-info interval))
           (result (aiaos-cli--result-success cpu-info)))
      
      (if json-output
          result
        ;; 文本格式输出
        (let ((output-lines '()))
          (push "=== CPU 信息 ===" output-lines)
          (push (format "CPU型号: %s" (cdr (assoc 'model cpu-info))) output-lines)
          (push (format "核心数: %s" (cdr (assoc 'cores cpu-info))) output-lines)
          (push (format "线程数: %s" (cdr (assoc 'threads cpu-info))) output-lines)
          (push (format "使用率: %.1f%%" (cdr (assoc 'usage cpu-info))) output-lines)
          (push (format "用户空间: %.1f%%" (cdr (assoc 'user_pct cpu-info))) output-lines)
          (push (format "系统空间: %.1f%%" (cdr (assoc 'sys_pct cpu-info))) output-lines)
          (push (format "空闲: %.1f%%" (cdr (assoc 'idle_pct cpu-info))) output-lines)
          (push (format "负载(1min): %.2f" (cdr (assoc 'load1 cpu-info))) output-lines)
          (push (format "负载(5min): %.2f" (cdr (assoc 'load5 cpu-info))) output-lines)
          (push (format "负载(15min): %.2f" (cdr (assoc 'load15 cpu-info))) output-lines)
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,cpu-info))))))))

(aiaos-cli-register-command
 "system_info" "check_cpu"
 #'aiaos-cli-skill-system-info/check-cpu
 :description "检查CPU使用率、核心数、负载等信息"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "interval" :short "i" :type integer :default 1 :description "采样间隔秒数"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-cpu)
;;; commands/check_cpu.el ends here
