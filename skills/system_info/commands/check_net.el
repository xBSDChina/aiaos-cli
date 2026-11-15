;;; commands/check_net.el --- 网络接口与连接检查命令 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.0

;;; Commentary:
;; 检查网络接口与 TCP 连接信息：读取 /proc/net/dev 汇总每接口收发字节/包/
;; 错误/丢包，读取 /proc/net/tcp 与 /proc/net/tcp6 汇总 TCP 连接数。

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-system-utils)
(require 'json)
(require 'cl-lib)

(defun aiaos-cli-skill-system-info/check-net (args options ctx)
  "检查网络接口与 TCP 连接信息
ARGS - 位置参数
OPTIONS - 选项列表
CTX - 上下文信息"
  (ignore args)
  (ignore ctx)

  (let ((json-output (or (plist-get options :json) nil))
        (detail (or (plist-get options :detail) nil)))
    (let* ((net-info (aiaos-cli-system--get-net-info detail))
           (result (aiaos-cli--result-success net-info)))
      (if json-output
          result
        (let ((output-lines '()))
          (push "=== 网络信息 ===" output-lines)
          (push (format "接口数:       %s"
                        (cdr (assoc 'iface_count net-info))) output-lines)
          (push (format "TCP 连接数:   %s (IPv4: %s, IPv6: %s)"
                        (cdr (assoc 'tcp_connections net-info))
                        (cdr (assoc 'tcp4_connections net-info))
                        (cdr (assoc 'tcp6_connections net-info))) output-lines)
          (push (format "总收: %s / %s pkts / %s err / %s drop"
                        (aiaos-cli-system--format-bytes
                         (cdr (assoc 'total_rx_bytes net-info)))
                        (cdr (assoc 'total_rx_packets net-info))
                        (cdr (assoc 'total_rx_errors net-info))
                        (cdr (assoc 'total_rx_dropped net-info))) output-lines)
          (push (format "总发: %s / %s pkts / %s err / %s drop"
                        (aiaos-cli-system--format-bytes
                         (cdr (assoc 'total_tx_bytes net-info)))
                        (cdr (assoc 'total_tx_packets net-info))
                        (cdr (assoc 'total_tx_errors net-info))
                        (cdr (assoc 'total_tx_dropped net-info))) output-lines)
          (push "" output-lines)
          (push "--- 各接口明细 ---" output-lines)
          (cl-loop for iface in (cdr (assoc 'interfaces net-info))
                   do (push (format "%-12s rx=%s(%s pkts, %s err, %s drop)  tx=%s(%s pkts, %s err, %s drop)"
                                     (cdr (assoc 'name iface))
                                     (aiaos-cli-system--format-bytes (cdr (assoc 'rx_bytes iface)))
                                     (cdr (assoc 'rx_packets iface))
                                     (cdr (assoc 'rx_errors iface))
                                     (cdr (assoc 'rx_dropped iface))
                                     (aiaos-cli-system--format-bytes (cdr (assoc 'tx_bytes iface)))
                                     (cdr (assoc 'tx_packets iface))
                                     (cdr (assoc 'tx_errors iface))
                                     (cdr (assoc 'tx_dropped iface)))
                     output-lines))
          (aiaos-cli--result-success `((output . ,(mapconcat 'identity output-lines "\n"))
                                       (data . ,net-info))))))))

(aiaos-cli-register-command
 "system_info" "check_net"
 #'aiaos-cli-skill-system-info/check-net
 :description "检查网络接口与 TCP 连接信息（收发字节/包/错误/丢包、TCP 连接数）"
 :args '()
 :options '((:name "json" :short "j" :type boolean :default nil :description "以JSON格式输出")
            (:name "detail" :short "d" :type boolean :default nil :description "显示详细字段"))
 :skill "system_info")

(provide 'aiaos-cli-skill-system-info/commands/check-net)
;;; commands/check_net.el ends here
