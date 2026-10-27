;;; aiaos-cli-components.el --- UI 组件库 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; UI 组件库，提供各种可复用的界面组件。
;; 基于 aiaos-cli-component 和 aiaos-cli-theme 构建。

;;; Commentary:

;; 本模块提供 aiaos-cli 的 UI 组件库。
;; 主要组件：
;;   * aiaos-cli-component-text       - 文本组件
;;   * aiaos-cli-component-border     - 边框组件
;;   * aiaos-cli-component-list       - 列表组件
;;   * aiaos-cli-component-input      - 输入框组件
;;   * aiaos-cli-component-modal      - 模态框组件
;;   * aiaos-cli-component-table      - 表格组件
;;   * aiaos-cli-component-progress   - 进度条组件
;;   * aiaos-cli-component-statusbar - 状态栏组件

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-component)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-lifecycle)

(defgroup aiaos-cli-components nil
  "aiaos-cli UI 组件库"
  :group 'aiaos-cli
  :prefix "aiaos-cli-components-")

;; ============================================================
;; 文本组件
;; ============================================================

(defun aiaos-cli-component-text (&rest body)
  "创建文本组件

BODY 是文本内容

示例:
  (aiaos-cli-component-text \"Hello World\")"
  (let ((component (make-aiaos-cli--component :name 'text)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (insert (mapconcat #'identity body ""))))
    component))

;; ============================================================
;; 边框组件
;; ============================================================

(defun aiaos-cli-component-border (title &optional content)
  "创建边框组件

TITLE 是边框标题
CONTENT 是边框内容（可选）

示例:
  (aiaos-cli-component-border \"My Border\" \"Content\")"
  (let ((component (make-aiaos-cli--component :name 'border))
        (theme (aiaos-cli--theme-current)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 渲染边框
            (insert-char ?│ (max 1 (1+ (length title))))
            (insert " " title " ")
            (insert-char ?│)
            (insert ?\n)
            ;; 渲染内容
            (when content
              (insert content "\n"))
            ;; 渲染底边框
            (insert-char ?│ (max 1 (1+ (length title))))
            (insert " " title " ")
            (insert-char ?│)))
    component))

;; ============================================================
;; 列表组件
;; ============================================================

(defun aiaos-cli-component-list (items &optional selected-idx)
  "创建列表组件

ITEMS 是列表项列表
SELECTED-IDX 是选中项的索引（可选）

示例:
  (aiaos-cli-component-list '(\"Item 1\" \"Item 2\" \"Item 3\") 0)"
  (let ((component (make-aiaos-cli--component :name 'list))
        (theme (aiaos-cli--theme-current))
        (selected-state (aiaos-cli--state-create (or selected-idx 0))))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (dolist (item items)
              ;; 获取当前索引
              (let* ((current-idx (cl-position item items))
                     (is-selected (= current-idx (aiaos-cli--state-get selected-state))))
                ;; 渲染选中标记
                (if is-selected
                    (insert (aiaos-cli--theme-icon theme :pointer) " ")
                  (insert "  "))
                ;; 渲染列表项
                (insert item "\n")))
            ;; 显示当前选中索引
            (insert (format "\nSelected: %S" (aiaos-cli--state-get selected-state)))))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) selected-state)
    component))

;; ============================================================
;; 输入框组件
;; ============================================================

(defun aiaos-cli-component-input (placeholder)
  "创建输入框组件

PLACEHOLDER 是占位符文本

示例:
  (aiaos-cli-component-input \"Enter your name\")"
  (let ((component (make-aiaos-cli--component :name 'input))
        (theme (aiaos-cli--theme-current))
        (value-state (aiaos-cli--state-create "")))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 渲染输入框边框
            (insert "┃ ")
            ;; 渲染输入值或占位符
            (if (string= (aiaos-cli--state-get value-state) "")
                (insert (propertize placeholder 'face 'aiaos-cli-input-placeholder))
              (insert (aiaos-cli--state-get value-state)))
            (insert " ┃")
            ;; 渲染光标
            (insert (propertize " ┃" 'face 'aiaos-cli-input-cursor))
            ))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) value-state)
    ;; 返回组件和状态
    (list component value-state)))

;; ============================================================
;; 模态框组件
;; ============================================================

(defun aiaos-cli-component-modal (title content)
  "创建模态框组件

TITLE 是模态框标题
CONTENT 是模态框内容

示例:
  (aiaos-cli-component-modal \"Confirm\" \"Are you sure?\")"
  (let ((component (make-aiaos-cli--component :name 'modal))
        (theme (aiaos-cli--theme-current))
        (visible-state (aiaos-cli--state-create t)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 如果可见，渲染模态框
            (when (aiaos-cli--state-get visible-state)
              ;; 渲染遮罩
              (insert (make-string 80 ?\u2588))
              (insert ?\n)
              ;; 渲染标题
              (insert (propertize title 'face 'aiaos-cli-modal-title))
              (insert "\n")
              ;; 渲染内容
              (insert content "\n")
              ;; 渲染按钮
              (insert "\n[Enter] 确认  [Esc] 取消"))))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) visible-state)
    component))

;; ============================================================
;; 表格组件
;; ============================================================

(defun aiaos-cli-component-table (headers rows)
  "创建表格组件

HEADERS 是表头列表
ROWS 是行列表，每行是单元格列表

示例:
  (aiaos-cli-component-table '(\"Name\" \"Value\")
    '((\"Key1\" \"Value1\")
      (\"Key2\" \"Value2\")))"
  (let ((component (make-aiaos-cli--component :name 'table))
        (theme (aiaos-cli--theme-current)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 渲染表头
            (dolist (header headers)
              (insert header "\t"))
            (insert ?\n)
            ;; 渲染分隔线
            (dotimes (i (length headers))
              (insert "-----\t"))
            (insert ?\n)
            ;; 渲染行
            (dolist (row rows)
              (dolist (cell row)
                (insert cell "\t"))
              (insert ?\n))))
    component))

;; ============================================================
;; 进度条组件
;; ============================================================

(defun aiaos-cli-component-progress (current total &optional label)
  "创建进度条组件

CURRENT 是当前进度
TOTAL 是总进度
LABEL 是标签（可选）

示例:
  (aiaos-cli-component-progress 75 100 \"Downloading\")"
  (let ((component (make-aiaos-cli--component :name 'progress))
        (theme (aiaos-cli--theme-current))
        (current-state (aiaos-cli--state-create current)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 计算进度百分比
            (let* ((cur (aiaos-cli--state-get current-state))
                   (pct (if (zerop total)
                            0
                          (floor (* cur 100) total)))
                   (filled (floor (* cur 20) total))
                   (empty (- 20 filled)))
              ;; 渲染标签
              (when label (insert label ": "))
              ;; 渲染进度条
              (insert "[")
              (dotimes (i filled)
                (insert-char ?█))
              (dotimes (i empty)
                (insert-char ?░))
              (insert "]")
              ;; 渲染百分比
              (insert (format " %d%%\n" pct)))))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) current-state)
    component))

;; ============================================================
;; 状态栏组件
;; ============================================================

(defun aiaos-cli-component-statusbar (left right)
  "创建状态栏组件

LEFT 是左侧文本
RIGHT 是右侧文本

示例:
  (aiaos-cli-component-statusbar \"Ready\" \"Line 1, Col 1\")"
  (let ((component (make-aiaos-cli--component :name 'statusbar)))
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (with-current-buffer buffer
              (insert left)
              (dotimes (i (max 0 (- 80 (+ (length left) (length right)))))
                (insert " "))
              (insert right))))
    component))
;; ============================================================
;; 组合组件
;; ============================================================

(defun aiaos-cli-component-vertical (&rest components)
  "创建垂直组合组件

COMPONENTS 是子组件列表

示例:
  (aiaos-cli-component-vertical
    (aiaos-cli-component-text \"Title\")
    (aiaos-cli-component-list items))"
  (let ((component (make-aiaos-cli--component :name 'vertical)))
    ;; 添加子组件
    (dolist (comp components)
      (aiaos-cli--component-add-child component comp))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 依次渲染子组件
            (dolist (child (aiaos-cli--component-get-children component))
              (aiaos-cli--render-component child buffer)
              (insert ?\n))))
    component))

(defun aiaos-cli-component-horizontal (&rest components)
  "创建水平组合组件

COMPONENTS 是子组件列表

示例:
  (aiaos-cli-component-horizontal
    (aiaos-cli-component-text \"Left\")
    (aiaos-cli-component-text \"Right\"))"
  (let ((component (make-aiaos-cli--component :name 'horizontal)))
    ;; 添加子组件
    (dolist (comp components)
      (aiaos-cli--component-add-child component comp))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 依次渲染子组件（不换行）
            (dolist (child (aiaos-cli--component-get-children component))
              (aiaos-cli--render-component child buffer))))
    component))

;; ============================================================
;; 分割面板组件
;; ============================================================

(defun aiaos-cli-component-split (left right &optional direction)
  "创建分割面板组件

LEFT 是左侧组件
RIGHT 是右侧组件
DIRECTION 是分割方向（'horizontal 或 'vertical，默认 'horizontal）

示例:
  (aiaos-cli-component-split
    (aiaos-cli-component-text \"Left\")
    (aiaos-cli-component-text \"Right\"))"
  (let ((component (make-aiaos-cli--component :name 'split))
        (dir (or direction 'horizontal)))
    ;; 添加子组件
    (aiaos-cli--component-add-child component left)
    (aiaos-cli--component-add-child component right)
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (if (eq dir 'horizontal)
                ;; 水平分割
                (progn
                  (aiaos-cli--render-component left buffer)
                  (insert "│ ")
                  (aiaos-cli--render-component right buffer))
              ;; 垂直分割
              (progn
                (aiaos-cli--render-component left buffer)
                (insert ?\n)
                (aiaos-cli--render-component right buffer)))))
    component))

;; ============================================================
;; 标签页组件
;; ============================================================

(defun aiaos-cli-component-tabs (tabs)
  "创建标签页组件

TABS 是标签列表，每个标签是 (名称 . 组件) 对

示例:
  (aiaos-cli-component-tabs
    (\"Tab 1\" . comp1)
    (\"Tab 2\" . comp2))"
  (let ((component (make-aiaos-cli--component :name 'tabs))
        (theme (aiaos-cli--theme-current))
        (active-tab (aiaos-cli--state-create 0)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 渲染标签栏
            (dotimes (i (length tabs))
              (let ((item (nth i tabs)))
                (insert (if (consp item) (car item) item)))
              (insert " │ "))
            (insert ?\n)
            ;; 渲染分隔线
            (insert (make-string 80 ?\u2500))
            (insert ?\n)
            ;; 渲染当前标签的内容
            (let* ((current-idx (aiaos-cli--state-get active-tab))
                   (current-tab (nth current-idx tabs)))
              (when current-tab
                (when (consp current-tab)
                  (aiaos-cli--render-component (cdr current-tab) buffer))))))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) active-tab)
    component))

;; ============================================================
;; 快捷键提示组件
;; ============================================================

(defun aiaos-cli-component-shortcuts (shortcuts)
  "创建快捷键提示组件

SHORTCUTS 是快捷键列表，每个快捷键是 (描述 . 按键) 对

示例:
  (aiaos-cli-component-shortcuts
    (\"Help\" . \"C-c a h\")
    (\"Version\" . \"C-c a v\"))"
  (let ((component (make-aiaos-cli--component :name 'shortcuts))
        (theme (aiaos-cli--theme-current)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            ;; 渲染快捷键
            (dolist (shortcut shortcuts)
              (insert (propertize (cdr shortcut) 'face 'aiaos-cli-shortcut-key))
              (insert " - ")
              (insert (propertize (car shortcut) 'face 'default))
              (insert ?\n))
            ;; 填充剩余空间
            (dotimes (i (max 0 (- 80 (* 2 (length shortcuts)))))
              (insert ?\s))
            (insert ?\n)))
    component))

;; ============================================================
;; 虚拟列表组件 (阶段4 高级组件)
;; ============================================================

(defun aiaos-cli-component-vlist (items &optional selected-idx window-size)
  "创建虚拟列表组件（支持大数据集滚动）

ITEMS 是列表项列表
SELECTED-IDX 是选中项的索引（可选，默认0）
WINDOW-SIZE 是可视窗口大小（可选，默认20）

示例:
  (aiaos-cli-component-vlist (number-sequence 1 1000) 0 20)"
  (let ((component (make-aiaos-cli--component :name 'vlist))
        (theme (aiaos-cli--theme-current))
        (selected-state (aiaos-cli--state-create (or selected-idx 0)))
        (scroll-state (aiaos-cli--state-create 0)))
    ;; 设置渲染函数
    (setf (aiaos-cli--component-render component)
          (lambda (buffer)
            (let* ((total (length items))
                   (ws (or window-size 20))
                   (start (max 0 (aiaos-cli--state-get scroll-state)))
                   (end (min total (+ start ws))))
              ;; 渲染标题
              (insert (format "Virtual List [%d items, showing %d-%d]\n"
                               total start end))
              (insert (make-string 40 ?\u2500) "\n")
              ;; 渲染可视范围内的项
              (dotimes (i (- end start))
                (let* ((idx (+ start i))
                       (item (nth idx items))
                       (is-selected (= idx (aiaos-cli--state-get selected-state))))
                  (if is-selected
                      (insert (aiaos-cli--theme-icon theme :pointer) " ")
                    (insert "  "))
                  (insert (format "%d: %S" idx item) "\n")))
              ;; 渲染滚动提示
              (when (> total ws)
                (insert "\n" (make-string 40 ?\u2500) "\n")
                (insert (format "[↑↓ scroll | ↑↓ selected | q quit]" start end))
              ))))
    ;; 添加状态到组件
    (setf (aiaos-cli--component-state component) (list selected-state scroll-state))
    component))

;; 初始化组件库
(defun aiaos-cli-components-init ()
  "初始化 UI 组件库"
  ;; 这里可以添加全局初始化逻辑
  t)

(provide 'aiaos-cli-components)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-components.el ends here
