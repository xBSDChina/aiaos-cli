;;; aiaos-cli-theme.el --- 主题系统 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 主题系统，借鉴 ratatui-kit 的 Theme/ThemeProvider 设计理念。
;; 提供可定制的主题和样式管理能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供主题管理功能。
;; 主要功能：
;;   * aiaos-cli--theme-dark       - 深色主题
;;   * aiaos-cli--theme-light      - 浅色主题
;;   * aiaos-cli--theme-provider   - 主题提供者（宏）
;;   * aiaos-cli--theme-current    - 获取当前主题
;;   * aiaos-cli--theme-apply      - 应用主题到 buffer
;;   * aiaos-cli--theme-customize   - 自定义主题

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-context)

(defgroup aiaos-cli-theme nil
  "aiaos-cli 主题系统"
  :group 'aiaos-cli
  :prefix "aiaos-cli-theme-")

(defcustom aiaos-cli-theme-default 'dark
  "默认主题（'dark 或 'light）"
  :type '(choice (const dark) (const light))
  :group 'aiaos-cli-theme)

;; 主题结构
(cl-defstruct aiaos-cli--theme
  "UI 主题

NAME: 主题名称
COLORS: 颜色定义
STYLES: 样式定义
ICONS: 图标定义"
  (name "custom")
  (colors (make-hash-table :test 'equal))
  (styles (make-hash-table :test 'equal))
  (icons (make-hash-table :test 'equal)))

;; 深色主题（基于 ratatui-kit DESIGN.md）
(defconst aiaos-cli--theme-dark
  (let ((theme (make-aiaos-cli--theme :name "dark")))
    ;; 颜色定义
    (setf (gethash :background (aiaos-cli--theme-colors theme)) "#081518")
    (setf (gethash :foreground (aiaos-cli--theme-colors theme)) "#E8E3D5")
    (setf (gethash :primary (aiaos-cli--theme-colors theme)) "#46C2C7")
    (setf (gethash :secondary (aiaos-cli--theme-colors theme)) "#2E8A90")
    (setf (gethash :accent (aiaos-cli--theme-colors theme)) "#FCA91C")
    (setf (gethash :error (aiaos-cli--theme-colors theme)) "#FF6B6B")
    (setf (gethash :success (aiaos-cli--theme-colors theme)) "#4ECB71")
    (setf (gethash :warning (aiaos-cli--theme-colors theme)) "#FCA91C")
    (setf (gethash :muted (aiaos-cli--theme-colors theme)) "rgba(232, 227, 213, 0.74)")
    ;; 样式定义
    (setf (gethash :default (aiaos-cli--theme-styles theme))
          '((:foreground :foreground)))
    (setf (gethash :border (aiaos-cli--theme-styles theme))
          '((:foreground :secondary)))
    (setf (gethash :highlight (aiaos-cli--theme-styles theme))
          '((:background :primary) (:foreground :background)))
    (setf (gethash :selected (aiaos-cli--theme-styles theme))
          '((:background :accent) (:foreground :background)))
    (setf (gethash :disabled (aiaos-cli--theme-styles theme))
          '((:strike-through t) (:foreground :muted)))
    (setf (gethash :title (aiaos-cli--theme-styles theme))
          '((:bold t) (:foreground :primary)))
    (setf (gethash :heading (aiaos-cli--theme-styles theme))
          '((:bold t) (:foreground :secondary)))
    (setf (gethash :button (aiaos-cli--theme-styles theme))
          '((:background :primary) (:foreground :background)))
    (setf (gethash :input (aiaos-cli--theme-styles theme))
          '((:background :background) (:foreground :foreground) (:box t)))
    ;; 图标定义
    (setf (gethash :pointer (aiaos-cli--theme-icons theme)) "▶")
    (setf (gethash :check (aiaos-cli--theme-icons theme)) "✓")
    (setf (gethash :cross (aiaos-cli--theme-icons theme)) "✗")
    (setf (gethash :warning (aiaos-cli--theme-icons theme)) "⚠")
    (setf (gethash :info (aiaos-cli--theme-icons theme)) "ℹ")
    theme))

;; 浅色主题
(defconst aiaos-cli--theme-light
  (let ((theme (make-aiaos-cli--theme :name "light")))
    ;; 颜色定义
    (setf (gethash :background (aiaos-cli--theme-colors theme)) "#F4F0E6")
    (setf (gethash :foreground (aiaos-cli--theme-colors theme)) "#1A1206")
    (setf (gethash :primary (aiaos-cli--theme-colors theme)) "#2E8A90")
    (setf (gethash :secondary (aiaos-cli--theme-colors theme)) "#46C2C7")
    (setf (gethash :accent (aiaos-cli--theme-colors theme)) "#B06A05")
    (setf (gethash :error (aiaos-cli--theme-colors theme)) "#C0392B")
    (setf (gethash :success (aiaos-cli--theme-colors theme)) "#27AE60")
    (setf (gethash :warning (aiaos-cli--theme-colors theme)) "#B06A05")
    (setf (gethash :muted (aiaos-cli--theme-colors theme)) "rgba(26, 18, 6, 0.6)")
    ;; 样式定义
    (setf (gethash :default (aiaos-cli--theme-styles theme))
          '((:foreground :foreground)))
    (setf (gethash :border (aiaos-cli--theme-styles theme))
          '((:foreground :secondary)))
    (setf (gethash :highlight (aiaos-cli--theme-styles theme))
          '((:background :primary) (:foreground :background)))
    (setf (gethash :selected (aiaos-cli--theme-styles theme))
          '((:background :accent) (:foreground :background)))
    (setf (gethash :disabled (aiaos-cli--theme-styles theme))
          '((:strike-through t) (:foreground :muted)))
    (setf (gethash :title (aiaos-cli--theme-styles theme))
          '((:bold t) (:foreground :primary)))
    (setf (gethash :heading (aiaos-cli--theme-styles theme))
          '((:bold t) (:foreground :secondary)))
    (setf (gethash :button (aiaos-cli--theme-styles theme))
          '((:background :primary) (:foreground :background)))
    (setf (gethash :input (aiaos-cli--theme-styles theme))
          '((:background :background) (:foreground :foreground) (:box t)))
    ;; 图标定义
    (setf (gethash :pointer (aiaos-cli--theme-icons theme)) "▶")
    (setf (gethash :check (aiaos-cli--theme-icons theme)) "✓")
    (setf (gethash :cross (aiaos-cli--theme-icons theme)) "✗")
    (setf (gethash :warning (aiaos-cli--theme-icons theme)) "⚠")
    (setf (gethash :info (aiaos-cli--theme-icons theme)) "ℹ")
    theme))

;; 主题注册
(defvar aiaos-cli--theme-registry nil
  "主题注册表")

;; 注册主题
(defun aiaos-cli--theme-register (theme)
  "注册主题

THEME 是主题对象"
  (let ((name (aiaos-cli--theme-name theme)))
    (setf (gethash name aiaos-cli--theme-registry) theme)
    (message "Registered theme: %S" name)
    theme))

;; 获取主题
(defun aiaos-cli--theme-get (name)
  "获取主题

NAME 是主题名称（符号或字符串）。如果注册表未初始化，自动初始化。"
  (when (null aiaos-cli--theme-registry)
    (aiaos-cli--theme-init))
  (let ((key (if (symbolp name) (symbol-name name) name)))
    (or (gethash key aiaos-cli--theme-registry nil)
        (gethash name aiaos-cli--theme-registry nil))))

;; 主题提供者（宏）
(defmacro aiaos-cli--theme-provider (theme &rest body)
  "主题提供者（宏）

THEME 是主题对象或主题名称
BODY 是在主题上下文中执行的代码

示例:
  (aiaos-cli--theme-provider aiaos-cli--theme-dark
    ;; 这里的代码使用深色主题)"
  (declare (indent 1))
  `(let ((theme-value (if (stringp ,theme)
                         (aiaos-cli--theme-get ,theme)
                       ,theme)))
     (aiaos-cli--context-provider
       (:theme theme-value)
       ,@body)))

;; 获取当前主题
(defun aiaos-cli--theme-current ()
  "获取当前主题

如果没有设置主题，返回默认主题。"
  (let ((ctx (aiaos-cli--context-current)))
    (if ctx
        (or (gethash :theme (aiaos-cli--context-values ctx) nil)
            (aiaos-cli--theme-get aiaos-cli-theme-default))
      (aiaos-cli--theme-get aiaos-cli-theme-default))))

;; 应用主题到 buffer
(defun aiaos-cli--theme-apply (theme buffer)
  "应用主题到 buffer

THEME 是主题对象
BUFFER 是目标 buffer

设置 buffer 的前景色和背景色。"
  (with-current-buffer buffer
    ;; 设置背景色
    (let ((bg-color (gethash :background (aiaos-cli--theme-colors theme))))
      (when bg-color
        (set-background-color bg-color)))
    ;; 设置前景色
    (let ((fg-color (gethash :foreground (aiaos-cli--theme-colors theme))))
      (when fg-color
        (set-foreground-color fg-color)))))

;; 获取主题颜色
(defun aiaos-cli--theme-color (theme color-key)
  "获取主题颜色

THEME 是主题对象
COLOR-KEY 是颜色键

返回颜色值。"
  (gethash color-key (aiaos-cli--theme-colors theme) nil))

;; 获取主题样式
(defun aiaos-cli--theme-style (theme style-key)
  "获取主题样式

THEME 是主题对象
STYLE-KEY 是样式键

返回样式列表。"
  (gethash style-key (aiaos-cli--theme-styles theme) nil))

;; 获取主题图标
(defun aiaos-cli--theme-icon (theme icon-key)
  "获取主题图标

THEME 是主题对象
ICON-KEY 是图标键

返回图标字符。"
  (gethash icon-key (aiaos-cli--theme-icons theme) nil))

;; 创建 face
(defun aiaos-cli--theme-face (theme style-key &optional inherit)
  "创建 face

THEME 是主题对象
STYLE-KEY 是样式键
INHERIT 是继承的 face（可选）

返回 face 规范。"
  (let* ((style (aiaos-cli--theme-style theme style-key))
         (face (list 'default)))
    (dolist (attr style)
      (let ((key (car attr))
            (value (cadr attr)))
        (cond
          ((eq key :foreground)
           (let ((color (aiaos-cli--theme-color theme value)))
             (when color
               (setf (nth 1 face) `(:foreground ,color)))))
          ((eq key :background)
           (let ((color (aiaos-cli--theme-color theme value)))
             (when color
               (setf (nth 2 face) `(:background ,color)))))
          ((eq key :bold)
           (push 'bold (cdr face)))
          ((eq key :italic)
           (push 'italic (cdr face)))
          ((eq key :underline)
           (push 'underline (cdr face)))
          ((eq key :strike-through)
           (push 'strike-through (cdr face)))
          ((eq key :box)
           (push 'box (cdr face))))))
    (if inherit
        (list face inherit)
      face)))

;; 自定义主题
(defmacro aiaos-cli--theme-customize (name &rest body)
  "自定义主题（宏）

NAME 是主题名称
BODY 是主题定义

示例:
  (aiaos-cli--theme-customize my-theme
    (:background \"#000000\")
    (:foreground \"#FFFFFF\")
    (:primary \"#00FF00\"))"
  (declare (indent 1))
  `(let ((theme (make-aiaos-cli--theme :name (format "%S" ,name))))
     ;; 设置颜色
     ,@(mapcar (lambda (pair)
                 `(setf (gethash ,(car pair) (aiaos-cli--theme-colors theme))
                        ,(cadr pair)))
               (nthcdr 1 body))
     ;; 注册主题
     (aiaos-cli--theme-register theme)
     theme))

;; 主题切换
(defun aiaos-cli--theme-toggle ()
  "切换主题（深色/浅色）

返回新的主题对象。"
  (let ((current (aiaos-cli--theme-current)))
    (let ((new-theme (if (string= (aiaos-cli--theme-name current) "dark")
                        aiaos-cli--theme-light
                      aiaos-cli--theme-dark)))
      ;; 设置到上下文
      (aiaos-cli--context-set :theme new-theme)
      new-theme)))

;; 主题调试
(defun aiaos-cli--theme-debug-info (theme)
  "获取主题调试信息"
  (list :name (aiaos-cli--theme-name theme)
        :colors-count (hash-table-count (aiaos-cli--theme-colors theme))
        :styles-count (hash-table-count (aiaos-cli--theme-styles theme))
        :icons-count (hash-table-count (aiaos-cli--theme-icons theme))))

;; 主题导入
(defun aiaos-cli--theme-import (file)
  "从文件导入主题

FILE 是文件路径，内容是主题定义（Elisp 代码）"
  (with-temp-buffer
    (insert-file-contents file)
    (let ((theme (read (buffer-string))))
      (aiaos-cli--theme-register theme)
      theme)))

;; 主题导出
(defun aiaos-cli--theme-export (theme file)
  "导出主题到文件

THEME 是主题对象
FILE 是文件路径"
  (with-temp-file file
    (princ (format "(aiaos-cli--theme-customize %S" (aiaos-cli--theme-name theme)) file)
    (dolist (pair (aiaos-cli--theme-colors theme))
      (princ (format "\n  (:%S . \"%S\")" (car pair) (cdr pair)) file))
    (princ ")" file)))

;; 初始化主题系统
(defun aiaos-cli--theme-init ()
  "初始化主题系统

注册内置主题。"
  (setf aiaos-cli--theme-registry (make-hash-table :test 'equal))
  ;; 注册内置主题
  (aiaos-cli--theme-register aiaos-cli--theme-dark)
  (aiaos-cli--theme-register aiaos-cli--theme-light)
  ;; 设置默认主题到上下文（如果上下文已初始化）
  (when (aiaos-cli--context-current)
    (aiaos-cli--context-set :theme aiaos-cli--theme-dark))
  t)

(provide 'aiaos-cli-theme)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-theme.el ends here
