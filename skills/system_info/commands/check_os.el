;;; commands/check_os.el --- 操作系统信息检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查操作系统信息，包括名称、版本、内核、主机名、架构等

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-os (args options ctx)
  "检查操作系统信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore ctx)
  
  (let ((json-output (or (plist-get options :json) nil))
        (detail (or (plist-get options :detail) nil)))
    
    ;; 获取操作系统信息
    (let ((os-info (aiaos-cli-system--get-os-info detail)))
      (if json-output
          (aiaos-cli--result-success os-info)
        ;; 文本格式输出
        (let ((output-lines '()))
          (push "=== 操作系统信息 ===" output-lines)
          (push (format "系统: %s" (cdr (assoc 'system os-info))) output-lines)
          (push (format "名称: %s" (cdr (assoc 'name os-info))) output-lines)
          (push (format "版本: %s" (cdr (assoc 'version os-info))) output-lines)
          (push (format "发行版: %s" (cdr (assoc 'distro os-info))) output-lines)
          (push (format "内核: %s" (cdr (assoc 'kernel os-info))) output-lines)
          (push (format "内核版本: %s" (cdr (assoc 'kernel-version os-info))) output-lines)
          (push (format "主机名: %s" (cdr (assoc 'hostname os-info))) output-lines)
          (push (format "架构: %s" (cdr (assoc 'architecture os-info))) output-lines)
          (push (format "处理器: %s" (cdr (assoc 'processor os-info))) output-lines)
          
          ;; 详细信息
          (when detail
            (push "" output-lines)
            (push "--- 详细系统信息 ---" output-lines)
            (when (assoc 'uptime os-info)
              (push (format "运行时间: %s" (cdr (assoc 'uptime os-info))) output-lines))
            (when (assoc 'users os-info)
              (push (format "当前用户数: %s" (cdr (assoc 'users os-info))) output-lines))
            (when (assoc 'boot-time os-info)
              (push (format "启动时间: %s" (cdr (assoc 'boot-time os-info))) output-lines)))
          
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,os-info))))))))

(aiaos-cli-register-command
 "system_info" "check_os"
 #'aiaos-cli-skill-system-info/check-os
 :description "检查操作系统信息"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "detail" :short "d" :type boolean :default nil :description "显示详细系统信息"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-os)
;;; commands/check_os.el ends here
