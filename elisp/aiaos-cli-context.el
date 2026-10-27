;;; aiaos-cli-context.el --- 依赖注入系统 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 依赖注入系统，借鉴 ratatui-kit 的 Context 设计理念。
;; 提供跨组件的数据共享和依赖管理能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供依赖注入能力。
;; 主要功能：
;;   * aiaos-cli--context-create    - 创建上下文
;;   * aiaos-cli--context-provider  - 上下文提供者（宏）
;;   * aiaos-cli--context-consumer  - 上下文消费者（宏）
;;   * aiaos-cli--context-get      - 获取上下文值
;;   * aiaos-cli--context-set      - 设置上下文值
;;   * aiaos-cli--context-with     - 临时提供上下文值

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-state)

(defgroup aiaos-cli-context nil
  "aiaos-cli 依赖注入系统"
  :group 'aiaos-cli
  :prefix "aiaos-cli-context-")

(defcustom aiaos-cli-context-strict t
  "是否严格模式（找不到上下文时报错）"
  :type 'boolean
  :group 'aiaos-cli-context)

;; 上下文结构
(cl-defstruct aiaos-cli--context
  "依赖注入上下文

PARENT: 父上下文（用于嵌套）
VALUES: 值哈希表
NAME: 上下文名称（用于调试）"
  (parent nil)
  (values (make-hash-table :test 'equal))
  (name nil))

;; 当前上下文栈
(defvar aiaos-cli--context-stack nil
  "上下文栈，用于管理嵌套的上下文")

;; 创建上下文
(defun aiaos-cli--context-create (&optional name parent)
  "创建新的上下文

NAME 是上下文名称（可选）
PARENT 是父上下文（可选）

返回新的上下文对象。"
  (make-aiaos-cli--context
   :parent parent
   :values (make-hash-table :test 'equal)
   :name name))

;; 获取当前上下文
(defun aiaos-cli--context-current ()
  "获取当前上下文"
  (if aiaos-cli--context-stack
      (car aiaos-cli--context-stack)
    nil))

;; 获取上下文值
(defun aiaos-cli--context-get (key &optional context)
  "获取上下文值

KEY 是键
CONTEXT 是上下文（可选，默认当前上下文）

如果找不到值，返回 nil（非严格模式）或报错（严格模式）"
  (let* ((ctx (or context (aiaos-cli--context-current)))
         (value (if ctx
                   (gethash key (aiaos-cli--context-values ctx) nil)
                 nil)))
    (if (and aiaos-cli-context-strict (null value))
        (error "Context key '%S' not found" key)
      value)))

;; 设置上下文值
(defun aiaos-cli--context-set (key value &optional context)
  "设置上下文值

KEY 是键
VALUE 是值
CONTEXT 是上下文（可选，默认当前上下文）"
  (let* ((ctx (or context (aiaos-cli--context-current))))
    (if (null ctx)
        (error "No context available")
      (setf (gethash key (aiaos-cli--context-values ctx)) value)
    value)))

;; 上下文提供者（宏）
(defmacro aiaos-cli--context-provider (&rest body)
  "上下文提供者（宏）

在 body 中提供额外的上下文值。

示例:
  (aiaos-cli--context-provider
    (:theme dark-theme)
    (:user \"alice\")
    ;; body 代码)"
  (declare (indent 1))
  (let ((old-context 'aiaos-cli--context-stack))
    `(let ((,old-context ,old-context))
       (let ((new-context (make-aiaos-cli--context
                           :parent (car ,old-context)
                           :values (make-hash-table :test 'equal)
                           :name 'context-provider)))
         ;; 设置提供的值
         ,@(mapcar (lambda (pair)
                     `(setf (gethash (car ,pair) (aiaos-cli--context-values new-context))
                            (cdr ,pair)))
                   (nbutlast body))
         ;; 执行 body
         (let ((aiaos-cli--context-stack (cons new-context ,old-context)))
           ,@(list (car (last body))))))))

;; 上下文消费者（宏）
(defmacro aiaos-cli--context-consumer (key)
  "上下文消费者（宏）

获取指定键的上下文值。

示例:
  (let ((theme (aiaos-cli--context-consumer :theme)))
    ;; 使用 theme)"
  `(aiaos-cli--context-get ,key))

;; 临时提供上下文值
(defmacro aiaos-cli--context-with (&rest body)
  "临时提供上下文值（宏）

示例:
  (aiaos-cli--context-with
    (:temp-value 123)
    ;; 在这个上下文中，(aiaos-cli--context-get :temp-value) 返回 123)"
  (declare (indent 1))
  `(aiaos-cli--context-provider
    ,@(mapcar (lambda (pair)
                `(,(car pair) . ,(cdr pair)))
              (nbutlast body))
    ,@(list (car (last body)))))

;; 初始化根上下文
(defun aiaos-cli--context-init (&optional parent)
  "初始化根上下文

PARENT 是父上下文（可选）"
  (let ((root-context (make-aiaos-cli--context
                       :parent parent
                       :values (make-hash-table :test 'equal)
                       :name 'root)))
    (setf aiaos-cli--context-stack (list root-context))
    root-context))

;; 销毁上下文
(defun aiaos-cli--context-destroy (context)
  "销毁上下文及其所有值"
  (setf (aiaos-cli--context-values context) (make-hash-table :test 'equal)
        (aiaos-cli--context-parent context) nil))

;; 查找上下文值（递归）
(defun aiaos-cli--context-lookup (key &optional context)
  "递归查找上下文值

KEY 是键
CONTEXT 是上下文（可选，默认当前上下文）

会从当前上下文向上查找，直到找到值或到达根上下文。"
  (let* ((ctx (or context (aiaos-cli--context-current)))
         (value (if ctx
                   (gethash key (aiaos-cli--context-values ctx) nil)
                 nil)))
    (if value
        value
      (if (and ctx (aiaos-cli--context-parent ctx))
          (aiaos-cli--context-lookup key (aiaos-cli--context-parent ctx))
        nil))))

;; 上下文调试
(defun aiaos-cli--context-debug-info (&optional context)
  "获取上下文调试信息"
  (let* ((ctx (or context (aiaos-cli--context-current)))
         (values (when ctx (aiaos-cli--context-values ctx))))
    (list :context ctx
          :name (and ctx (aiaos-cli--context-name ctx))
          :parent (and ctx (aiaos-cli--context-parent ctx))
          :value-count (if values (hash-table-count values) 0))))

;; 上下文深度
(defun aiaos-cli--context-depth (&optional context)
  "获取上下文深度"
  (let ((ctx (or context (aiaos-cli--context-current)))
        (depth 0))
    (while ctx
      (cl-incf depth)
      (setf ctx (aiaos-cli--context-parent ctx)))
    depth))

;; 检查上下文是否包含键
(defun aiaos-cli--context-has-key (key &optional context)
  "检查上下文是否包含指定键"
  (let* ((ctx (or context (aiaos-cli--context-current))))
    (while ctx
      (if (gethash key (aiaos-cli--context-values ctx) nil)
          (return t))
      (setf ctx (aiaos-cli--context-parent ctx)))
    nil))

;; 批量设置上下文值
(defun aiaos-cli--context-set-many (context &rest pairs)
  "批量设置上下文值

CONTEXT 是上下文
PAIRS 是键值对列表"
  (dolist (pair pairs)
    (setf (gethash (car pair) (aiaos-cli--context-values context))
          (cdr pair)))
  context)

;; 创建子上下文
(defun aiaos-cli--context-child (&optional name &rest pairs)
  "创建子上下文

NAME 是子上下文名称（可选）
PAIRS 是键值对列表（可选）

返回新的子上下文对象。"
  (let* ((parent (aiaos-cli--context-current))
         (child (make-aiaos-cli--context
                 :parent parent
                 :values (make-hash-table :test 'equal)
                 :name name)))
    ;; 设置提供的值
    (when pairs
      (aiaos-cli--context-set-many child pairs))
    child))

;; 上下文栈操作
(defun aiaos-cli--context-push (context)
  "将上下文压入栈顶"
  (push context aiaos-cli--context-stack)
  context)

(defun aiaos-cli--context-pop ()
  "弹出栈顶上下文"
  (pop aiaos-cli--context-stack))

;; 上下文快照
(defun aiaos-cli--context-snapshot (&optional context)
  "创建上下文快照"
  (let* ((ctx (or context (aiaos-cli--context-current)))
         (snapshot (make-aiaos-cli--context
                    :parent nil
                    :values (copy-hash-table (aiaos-cli--context-values ctx))
                    :name (and ctx (aiaos-cli--context-name ctx)))))
    snapshot))

;; 恢复上下文快照
(defun aiaos-cli--context-restore (snapshot)
  "恢复上下文快照"
  (when (and snapshot (aiaos-cli--context-current))
    (setf (aiaos-cli--context-values (aiaos-cli--context-current))
          (aiaos-cli--context-values snapshot))))

(provide 'aiaos-cli-context)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-context.el ends here

;;; Aliases for public API
(defalias 'aiaos-cli-context-init 'aiaos-cli--context-init)
(provide 'aiaos-cli-context)
