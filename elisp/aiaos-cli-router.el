;;; aiaos-cli-router.el --- 路由系统 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 路由系统，借鉴 ratatui-kit 的 use_router/Router 设计理念。
;; 提供页面路由和导航管理能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供路由功能。
;; 主要功能：
;;   * aiaos-cli--define-routes      - 定义路由表
;;   * aiaos-cli--router-navigate    - 导航到指定路径
;;   * aiaos-cli--router-current     - 获取当前路由
;;   * aiaos-cli--router-render     - 渲染当前路由
;;   * aiaos-cli--router-match      - 匹配路由

;;; Code:

;; 兼容 Emacs 28+ 的 syntax-quote 机制
(unless (boundp (quote with-syntax-quote-reworked-p))
  (defmacro with-syntax-quote-reworked-p (&rest body)
    "兼容层：在 Emacs < 29 中，直接展开 body，不改变语法引用行为"
    body))

(require 'cl-lib)
(declare-function cl-copy-list (cl))
(require 'aiaos-cli-component)
(require 'aiaos-cli-context)

(declare-function mouse-event-button-press-event-p (mouse))
(defgroup aiaos-cli-router nil
  "aiaos-cli 路由系统"
  :group 'aiaos-cli
  :prefix "aiaos-cli-router-")

(defcustom aiaos-cli-router-default-path "/"
  "默认路由路径"
  :type 'string
  :group 'aiaos-cli-router)

;; 路由结构
(cl-defstruct aiaos-cli--route
  "路由定义

PATH: 路径
COMPONENT: 组件对象或组件名称
PARAMS: 参数
META: 元数据"
  (path "/")
  (component nil)
  (params nil)
  (meta nil))

;; 路由表
(defvar aiaos-cli--routes nil
  "路由表")

;; 当前路由
(defvar aiaos-cli--current-route nil
  "当前路由")

;; 路由栈（用于历史记录）
(defvar aiaos-cli--route-stack nil
  "路由栈")

;; 定义路由
(defmacro aiaos-cli--define-routes (&rest routes)
  "定义路由表（宏）

ROUTES 是路由定义列表

示例:
  (aiaos-cli--define-routes
    (:path \"/\" :component home-page)
    (:path \"/skills\" :component skills-page)
    (:path \"/agent\" :component agent-page))"
  `(setf aiaos-cli--routes
         '(,@routes)))

;; 创建路由
(defun aiaos-cli--router-create-route (path component &optional params meta)
  "创建路由

PATH 是路径
COMPONENT 是组件对象或组件名称
PARAMS 是参数（可选）
META 是元数据（可选）

返回路由对象。"
  (make-aiaos-cli--route
   :path path
   :component component
   :params params
   :meta meta))

;; 匹配路由
(defun aiaos-cli--router-match (path &optional routes)
  "匹配路由

PATH 是路径
ROUTES 是路由表（可选，默认全局路由表）

返回匹配的路由对象或 nil。"
  (cl-block aiaos-cli--router-match
  (let ((route-table (or routes aiaos-cli--routes))
        (matched nil))
    (dolist (route route-table)
      (when (string= (aiaos-cli--route-path route) path)
        (setq matched route)
        (cl-return-from aiaos-cli--router-match matched))
      ;; 支持参数路由
      (when (string-match "\\(.*\\)" (aiaos-cli--route-path route))
        (when (string-match (aiaos-cli--route-path route) path)
          (setq matched route)
          (cl-return-from aiaos-cli--router-match matched))))
    matched)))

;; 导航到指定路径
(defun aiaos-cli--router-navigate (path &optional params)
  "导航到指定路径

PATH 是目标路径
PARAMS 是参数（可选）

返回新的路由对象或 nil（如果路径不存在）。"
  (let* ((route (aiaos-cli--router-match path))
         (old-route aiaos-cli--current-route))
    (when route
      ;; 设置参数
      (when params
        (setf (aiaos-cli--route-params route) params))
      ;; 更新当前路由
      (setf aiaos-cli--current-route route)
      ;; 压入路由栈
      (when old-route
        (push old-route aiaos-cli--route-stack))
      ;; 渲染路由
      (aiaos-cli--router-render route)
      route)))

;; 获取当前路由
(defun aiaos-cli--router-current ()
  "获取当前路由

返回当前路由对象。"
  aiaos-cli--current-route)

;; 渲染路由
(defun aiaos-cli--router-render (route &optional buffer)
  "渲染路由

ROUTE 是路由对象
BUFFER 是目标 buffer（可选，默认当前 buffer）

返回渲染的字符串。"
  (let* ((component (aiaos-cli--route-component route))
         (target-buffer (or buffer (current-buffer))))
    ;; 处理组件
    (if (stringp component)
        ;; 组件名称
        (let ((registered (aiaos-cli--component-get component)))
          (if registered
              (aiaos-cli--render-component registered target-buffer)
            (error "Component '%S' not registered" component)))
      ;; 组件对象
      (aiaos-cli--render-component component target-buffer))
    nil))

;; 返回上一页
(defun aiaos-cli--router-back ()
  "返回上一页

如果有历史记录，返回上一页路由。"
  (when aiaos-cli--route-stack
    (let ((previous (pop aiaos-cli--route-stack)))
      (setf aiaos-cli--current-route previous)
      (aiaos-cli--router-render previous)
      previous)))

;; 前进
(defun aiaos-cli--router-forward ()
  "前进（需要实现前进栈）

当前版本暂不支持。"
  nil)

;; 刷新当前路由
(defun aiaos-cli--router-refresh ()
  "刷新当前路由

重新渲染当前路由的组件。"
  (when aiaos-cli--current-route
    (aiaos-cli--router-render aiaos-cli--current-route)
    t))

;; 添加路由
(defun aiaos-cli--router-add (route)
  "添加路由到路由表

ROUTE 是路由对象"
  (push route aiaos-cli--routes)
  route)

;; 移除路由
(defun aiaos-cli--router-remove (path)
  "从路由表移除路由

PATH 是路径

返回被移除的路由对象或 nil。"
  (let ((route (aiaos-cli--router-match path)))
    (when route
      (setf aiaos-cli--routes (delete route aiaos-cli--routes))
      route)))

;; 获取路由参数
(defun aiaos-cli--router-params (&optional route)
  "获取路由参数

ROUTE 是路由对象（可选，默认当前路由）

返回参数哈希表。"
  (let ((current-route (or route aiaos-cli--current-route)))
    (if current-route
        (aiaos-cli--route-params current-route)
      nil)))

;; 获取路由元数据
(defun aiaos-cli--router-meta (&optional route)
  "获取路由元数据

ROUTE 是路由对象（可选，默认当前路由）

返回元数据。"
  (let ((current-route (or route aiaos-cli--current-route)))
    (if current-route
        (aiaos-cli--route-meta current-route)
      nil)))

;; 路由守卫
(defun aiaos-cli--router-guard (guard-fn path)
  "执行路由守卫

GUARD-FN 是守卫函数，接收路径作为参数，返回 t 或 nil
PATH 是路径

如果守卫返回 nil，阻止导航。"
  (if (funcall guard-fn path)
      t
    (message "Navigation blocked by guard")
    nil))

;; 路由中间件
(defvar aiaos-cli--router-middleware nil
  "路由中间件列表")

;; 添加中间件
(defun aiaos-cli--router-add-middleware (middleware)
  "添加路由中间件

MIDDLEWARE 是中间件函数，接收路由和继续函数作为参数"
  (push middleware aiaos-cli--router-middleware))

;; 执行中间件
(defun aiaos-cli--router--run-middleware (route)
  "执行路由中间件

ROUTE 是路由对象

返回经过中间件处理后的路由。"
  (if (null aiaos-cli--router-middleware)
      route
    (let ((middleware (car aiaos-cli--router-middleware))
          (_rest (cdr aiaos-cli--router-middleware)))
      ;; 简化版：直接调用中间件
      (funcall middleware route))))

;; 路由钩子
(defvar aiaos-cli--router-hooks nil
  "路由钩子列表")

;; 添加路由钩子
(defun aiaos-cli--router-add-hook (hook)
  "添加路由钩子

HOOK 是钩子函数，接收路由作为参数"
  (add-hook 'aiaos-cli--router-hooks hook))

;; 执行路由钩子
(defun aiaos-cli--router--run-hooks (route)
  "执行路由钩子

ROUTE 是路由对象"
  (run-hook-with-args 'aiaos-cli--router-hooks route))

;; 路由链接组件
;; 路由链接组件

(defmacro aiaos-cli--router-link (path &rest body)
  "创建路由链接组件（宏）。

PATH 是目标路径，BODY 是链接内容。
示例: (aiaos-cli--router-link \"/skills\" \"技能管理\")"
  `(propertize ,@body
     'face 'link
     'mouse-face 'highlight
     'mouse-action
     (lambda (event)
       (when (mouse-event-button-press-event-p event)
         (aiaos-cli--router-navigate ,path)))))


;; 路由参数提取
(defun aiaos-cli--router--extract-params (_path _route)
  "从路径提取参数

PATH 是实际路径
ROUTE 是路由对象

返回参数哈希表。"
  (let ((params (make-hash-table :test 'equal)))
    ;; 简化版：不实现复杂的参数提取
    params))

;; 路由嵌套
(cl-defstruct aiaos-cli--nested-route
  "嵌套路由

PARENT: 父路由
CHILDREN: 子路由列表"
  (parent nil)
  (children nil))

;; 创建嵌套路由
(defun aiaos-cli--router-create-nested (parent &rest children)
  "创建嵌套路由

PARENT 是父路由
CHILDREN 是子路由列表

返回嵌套路由对象。"
  (let ((nested (make-aiaos-cli--nested-route :parent parent)))
    (dolist (child children)
      (push child (aiaos-cli--nested-route-children nested)))
    nested))

;; 路由调试
(defun aiaos-cli--router-debug-info (&optional route)
  "获取路由调试信息

ROUTE 是路由对象（可选，默认当前路由）"
  (let ((current-route (or route aiaos-cli--current-route)))
    (list :path (and current-route (aiaos-cli--route-path current-route))
          :component (and current-route (aiaos-cli--route-component current-route))
          :has-params (and current-route (not (null (aiaos-cli--route-params current-route))))
          :has-meta (and current-route (not (null (aiaos-cli--route-meta current-route)))))))

;; 路由历史
(defun aiaos-cli--router-history ()
  "获取路由历史

返回路由栈的副本。"
  (cl-copy-list aiaos-cli--route-stack))

;; 清空路由历史
(defun aiaos-cli--router-clear-history ()
  "清空路由历史"
  (setf aiaos-cli--route-stack nil))

;; 初始化路由系统
(defun aiaos-cli--router-init ()
  "初始化路由系统

设置默认路由。"
  (setf aiaos-cli--routes nil)
  (setf aiaos-cli--current-route nil)
  (setf aiaos-cli--route-stack nil)
  (setf aiaos-cli--router-middleware nil)
  (setf aiaos-cli--router-hooks nil)
  t)

;;; Aliases for public API
(defalias 'aiaos-cli-router-init 'aiaos-cli--router-init)

(provide 'aiaos-cli-router)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-router.el ends here
