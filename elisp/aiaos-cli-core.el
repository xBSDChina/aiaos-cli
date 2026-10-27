;;; aiaos-cli-core.el --- aiaos-cli 核心接口定义
;;
;; 为 TUI 模块提供共享的工具函数和类型定义
;; 避免 circular dependency

;; Author: AIAOS Project
;; Keywords: tools, ai, automation, tui
;; Package-Version: 1.0.0
;; Created: 2026-10-25

;;;; Commentary:

;; aiaos-cli-core 提供 TUI 模块间共享的核心接口。
;; 设计原则：
;; 1. 无副作用：模块加载时不执行任何操作
;; 2. 纯函数：所有工具函数为纯函数，无全局状态
;; 3. 依赖注入：TUI 模块通过 aiaos-cli-context 注入依赖
;; 4. 向后兼容：不修改 aiaos-cli.el 现有 API

;;;; Requires:

(require 'cl-lib)

;;;; Code:

(defgroup aiaos-cli-core nil
  "aiaos-cli TUI 核心接口"
  :group 'aiaos-cli
  :prefix "aiaos-cli-core-")

(defconst aiaos-cli-core-version "1.0.0"
  "aiaos-cli-core 模块版本")

(defconst aiaos-cli-core-min-emacs-version "29.0"
  "aiaos-cli-core 最低支持的 Emacs 版本")

;; 版本信息
(defun aiaos-cli-core-version-info ()
  "返回 aiaos-cli-core 版本信息（列表）"
  (list :version aiaos-cli-core-version
        :min-emacs aiaos-cli-core-min-emacs-version
        :emacs-version (format "%s" emacs-version)))

(defun aiaos-cli-core-require-version (version)
  "验证 TUI 模块依赖的 core 版本

VERSION - 所需版本号字符串

返回非 nil 表示满足要求"
  (version<= version aiaos-cli-core-version))

;; 字符串工具

(defun aiaos-cli-core-truncate-string (str max-len)
  "截断字符串到 MAX-LEN 字符，超出部分以 ... 结尾

返回截断后的字符串。如果 str 长度 <= max-len，原样返回。"
  (if (> (length str) max-len)
      (format "%s..." (substring str 0 max-len))
    str))

(defun aiaos-cli-core-format-keybinding (keys)
  "格式化按键序列为人类可读形式

KEYS - 按键序列列表，如 (\"C-x\" \"C-c\")
返回格式化字符串，如 \"C-x C-c\""
  (mapconcat 'identity keys " "))

;; 调试辅助

(defun aiaos-cli-core-debug-log (msg)
  "记录调试日志到 *aiaos-cli-debug* buffer"
  (with-current-buffer (get-buffer-create "*aiaos-cli-debug*")
    (goto-char (point-max))
    (insert (format "[%s] %s\n" (format-time-string "%H:%M:%S") msg))))

(provide 'aiaos-cli-core)

;;; aiaos-cli-core.el ends here
