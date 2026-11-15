;;; commands/check_disk.el --- 磁盘信息检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查磁盘使用情况，包括各分区容量、使用率、inode等

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-disk (args options ctx)
  "检查磁盘信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore ctx)
  
  (let ((json-output (or (plist-get options :json) nil))
        (mount-filter (or (plist-get options :mount) "")))
    
    ;; 获取磁盘信息
    (let ((disk-info (aiaos-cli-system--get-disk-info mount-filter)))
      (if json-output
          (aiaos-cli--result-success disk-info)
        ;; 文本格式输出
        (let ((output-lines '())
              (partitions (cdr (assoc 'partitions disk-info))))
          (push "=== 磁盘信息 ===" output-lines)
          
          ;; 遍历分区
          (dolist (part partitions)
            (let ((device (cdr (assoc 'device part)))
                  (mount-point (cdr (assoc 'mountpoint part)))
                  (fstype (cdr (assoc 'fstype part)))
                  (size (cdr (assoc 'size part)))
                  (used (cdr (assoc 'used part)))
                  (available (cdr (assoc 'available part)))
                  (use-pct (cdr (assoc 'use_pct part))))
              
              (push (format "\n--- 分区: %s ---" mount-point) output-lines)
              (push (format "设备: %s" device) output-lines)
              (push (format "文件系统: %s" fstype) output-lines)
              (push (format "总容量: %s" (aiaos-cli-system--format-bytes size)) output-lines)
              (push (format "已用: %s (%s%%)" 
                          (aiaos-cli-system--format-bytes used) use-pct) output-lines)
              (push (format "可用: %s" (aiaos-cli-system--format-bytes available)) output-lines)
              
              (push "" output-lines)))
          
          (push (format "\n总计: %d 个分区" (length partitions)) output-lines)
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,disk-info))))))))

(aiaos-cli-register-command
 "system_info" "check_disk"
 #'aiaos-cli-skill-system-info/check-disk
 :description "检查磁盘使用情况"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "mount" :short "m" :type string :default "" :description "指定挂载点过滤"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-disk)
;;; commands/check_disk.el ends here
