;;; commands/check_load.el --- 系统负载详细检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查系统负载详细信息：/proc/loadavg、运行/可运行进程数、上下文切换、
;; 中断计数、僵尸进程等，用于诊断系统繁忙程度与调度状态。

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-load (args options ctx)
  "检查系统负载详细信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore args)
  (ignore ctx)

  (let ((json-output (or (plist-get options :json) nil))
        (detail (or (plist-get options :detail) nil)))
    (let* ((load-info (aiaos-cli-system--get-load-info detail))
           (result (aiaos-cli--result-success load-info)))
      (if json-output
          result
        (let ((output-lines '()))
          (push "=== 系统负载信息 ===" output-lines)
          (push (format "负载(1min):   %.2f" (cdr (assoc 'load1 load-info))) output-lines)
          (push (format "负载(5min):   %.2f" (cdr (assoc 'load5 load-info))) output-lines)
          (push (format "负载(15min):  %.2f" (cdr (assoc 'load15 load-info))) output-lines)
          (push (format "运行中/可运行: %s / %s"
                        (cdr (assoc 'running load-info))
                        (cdr (assoc 'total_procs load-info))) output-lines)
          (push (format "上下文切换: %s" (cdr (assoc 'ctxt load-info))) output-lines)
          (push (format "中断计数:   %s" (cdr (assoc 'intr load-info))) output-lines)
          (push (format "僵尸进程:   %s" (cdr (assoc 'zombies load-info))) output-lines)
          (push (format "核心数:     %s" (cdr (assoc 'cores load-info))) output-lines)
          (let* ((cores (cdr (assoc 'cores load-info)))
                 (load1 (cdr (assoc 'load1 load-info)))
                 (per-core (if (and (numberp cores) (> cores 0))
                               (/ load1 (float cores))
                             0.0))
                 (status "正常"))
            (when (> per-core 2.0) (setq status "过载"))
            (when (and (> per-core 1.0) (<= per-core 2.0)) (setq status "偏忙"))
            (push (format "单核负载:   %.2f (%s)" per-core status) output-lines))
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,load-info))))))))

(aiaos-cli-register-command
 "system_info" "check_load"
 #'aiaos-cli-skill-system-info/check-load
 :description "检查系统负载详细信息（loadavg、进程、上下文切换、中断、僵尸）"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "detail" :short "d" :type boolean :default nil :description "显示详细字段"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-load)
;;; commands/check_load.el ends here
