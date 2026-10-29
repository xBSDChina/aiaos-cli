;;; aiaos-cli-component.el --- 组件系统核心 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 组件系统核心，借鉴 ratatui-kit 的 component/element 设计理念。
;; 提供组件抽象、属性管理、子组件组合和渲染能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供组件化开发能力。
;; 主要功能：
;;   * aiaos-cli--component       - 定义组件
;;   * aiaos-cli--props           - 属性管理
;;   * aiaos-cli--children        - 子组件管理
;;   * aiaos-cli--render          - 渲染组件
;;   * aiaos-cli--compose         - 组合组件
;;   * aiaos-cli--fragment        - 片段容器

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-lifecycle)

(defgroup aiaos-cli-component nil
  "aiaos-cli 组件系统"
  :group 'aiaos-cli
  :prefix "aiaos-cli-component-")

(defcustom aiaos-cli-component-cache t
  "是否缓存渲染结果"
  :type 'boolean
  :group 'aiaos-cli-component)

;; 组件结构
(cl-defstruct aiaos-cli--component
  "UI 组件

NAME: 组件名称
PROPS: 属性哈希表
STATE: 本地状态
CHILDREN: 子组件列表
RENDER: 渲染函数
EFFECTS: 副作用列表
CONTEXT: 组件上下文"
  (name nil)
  (props (make-hash-table :test 'equal))
  (state nil)
  (children nil)
  (render nil)
  (effects nil)
  (context nil))

;; 当前组件栈
(defvar aiaos-cli--component-stack nil
  "组件栈，用于管理嵌套组件")

;; 组件注册表
(defvar aiaos-cli--component-registry nil
  "组件注册表")

;; 创建组件
(defun aiaos-cli--component-create (name &rest props)
  "创建组件

NAME 是组件名称
PROPS 是属性列表（键值对）

返回组件对象。"
  (let ((component (make-aiaos-cli--component
                    :name name
                    :props (make-hash-table :test 'equal))))
    ;; 设置属性
    (dolist (pair props)
      (setf (gethash (car pair) (aiaos-cli--component-props component))
            (cdr pair)))
    ;; 注册组件
    (setf (gethash name aiaos-cli--component-registry) component)
    component))

;; 获取组件
(defun aiaos-cli--component-get (name)
  "获取已注册的组件"
  (gethash name aiaos-cli--component-registry nil))

;; 设置属性
(defun aiaos-cli--component-set-prop (component key value)
  "设置组件属性

COMPONENT 是组件对象
KEY 是属性键
VALUE 是属性值"
  (setf (gethash key (aiaos-cli--component-props component)) value)
  value)

;; 获取属性
(defun aiaos-cli--component-get-prop (component key &optional default)
  "获取组件属性

COMPONENT 是组件对象
KEY 是属性键
DEFAULT 是默认值（可选）"
  (or (gethash key (aiaos-cli--component-props component) default)
      default))

;; 属性宏
(defmacro aiaos-cli--props (&rest body)
  "属性管理（宏）

示例:
  (aiaos-cli--props
    :title \"My Component\"
    :items `(1 2 3))"
  `(aiaos-cli--component-create 'props
    ,@(mapcar (lambda (pair)
                `(,(car pair) . ,(cdr pair)))
              body)))

;; 子组件管理
(defun aiaos-cli--component-add-child (component child)
  "添加子组件

COMPONENT 是父组件
CHILD 是子组件对象或组件名称"
  (if (stringp child)
      (let ((registered (aiaos-cli--component-get child)))
        (if registered
            (push registered (aiaos-cli--component-children component))
          (error "Component '%S' not registered" child)))
    (push child (aiaos-cli--component-children component)))
)
;; 获取子组件
(defun aiaos-cli--component-get-children (component)
  "获取组件的所有子组件"
  (aiaos-cli--component-children component))

;; 渲染函数
(defun aiaos-cli--render-component (component &optional buffer)
  "渲染组件

COMPONENT 是组件对象
BUFFER 是目标 buffer（可选，默认当前 buffer）

返回渲染的字符串。"
  (let ((result nil))
    (let* ((target-buffer (or buffer (current-buffer)))
           (old-buffer (current-buffer)))
      (with-current-buffer target-buffer
        (let ((inhibit-modification-hooks t))
          ;; 执行渲染函数
          (when (aiaos-cli--component-render component)
            (funcall (aiaos-cli--component-render component) target-buffer))
          ;; 保存渲染结果
          (setf result (buffer-string))))
      (when (not (eq target-buffer old-buffer))
        (kill-buffer target-buffer))
      result)))

;; 渲染函数宏
(defmacro aiaos-cli--component-render-fn (component &rest body)
  "定义渲染函数（宏）

COMPONENT 是组件对象
BODY 是渲染代码

示例:
  (aiaos-cli--component-render-fn comp
    (insert \"Hello World\\n\"))"
  (declare (indent 1))
  `(setf (aiaos-cli--component-render ,component)
         (lambda (buffer)
           ,@body)))

;; 组件定义宏
(defmacro aiaos-cli--define-component (name &rest body)
  "定义组件（宏）

NAME 是组件名称
BODY 是组件体

示例:
  (aiaos-cli--define-component my-component
    (:title \"My Component\")
    (aiaos-cli--use-state 0)
    ;; 渲染函数
    (aiaos-cli--component-render-fn comp
      (insert title \"\\n\"))"
  (declare (indent 1))
  `(cl-defun ,name (props)
     "组件函数"
     (let ((component (make-aiaos-cli--component
                       :name ',name
                       :props (aiaos-cli--props ,@(nthcdr 1 body)))))
       ,@body
       component)))

;; 组合组件
(defmacro aiaos-cli--compose (&rest components)
  "组合多个组件（宏）

COMPONENTS 是组件列表

示例:
  (aiaos-cli--compose comp1 comp2 comp3)"
  `(aiaos-cli--component-create 'composed
    ,@(mapcar (lambda (comp)
                `(:component . ,comp))
              components)))

;; Fragment 片段容器
(defmacro aiaos-cli--fragment (&rest children)
  "创建片段容器（宏）

CHILDREN 是子组件列表

示例:
  (aiaos-cli--fragment
    comp1
    comp2
    comp3)"
  `(let ((fragment (make-aiaos-cli--component
                    :name 'fragment
                    :props (make-hash-table :test 'equal))))
     ;; 添加子组件
     (dolist (child ,children)
       (aiaos-cli--component-add-child fragment child))
     fragment))

;; Context Provider 组件
(defmacro aiaos-cli--context-provider-component (name context-value &rest body)
  "创建上下文提供者组件（宏）

NAME 是组件名称
CONTEXT-VALUE 是上下文值
BODY 是组件体

示例:
  (aiaos-cli--context-provider-component theme-provider dark-theme
    ;; 组件体)"
  (declare (indent 2))
  `(aiaos-cli--define-component ,name
    (:context-value ,context-value)
    (aiaos-cli--context-provider
      (:context-value ,context-value)
      ,@body)))

;; 组件树遍历
(defun aiaos-cli--component-traverse (component visit-fn)
  "遍历组件树

COMPONENT 是根组件
VISIT-FN 是访问函数（接收组件作为参数）

深度优先遍历所有子组件。"
  (funcall visit-fn component)
  (dolist (child (aiaos-cli--component-get-children component))
    (aiaos-cli--component-traverse child visit-fn)))

;; 组件状态
(defun aiaos-cli--component-get-state (component)
  "获取组件状态

COMPONENT 是组件对象

返回组件的状态句柄（如果没有，创建一个新的）"
  (if (aiaos-cli--component-state component)
      (aiaos-cli--component-state component)
    (let ((state (aiaos-cli--state-create nil)))
      (setf (aiaos-cli--component-state component) state)
      state)))

;; 组件上下文
(defun aiaos-cli--component-get-context (component)
  "获取组件上下文

COMPONENT 是组件对象

返回组件的上下文（如果没有，创建一个新的子上下文）"
  (if (aiaos-cli--component-context component)
      (aiaos-cli--component-context component)
    (let ((context (aiaos-cli--context-create
                   :name (aiaos-cli--component-name component))))
      (setf (aiaos-cli--component-context component) context)
      context)))

;; 组件 HOC 高阶组件
(defmacro aiaos-cli--with-props (props &rest body)
  "为组件注入属性（HOC）

PROPS 是属性列表
BODY 是组件体

示例:
  (aiaos-cli--with-props
  (:title \"My Component\")
     :items `(1 2 3))
    ;; 组件体)"
  `(let ((component (make-aiaos-cli--component
                    :name 'hoc-component
                    :props (aiaos-cli--props ,props))))
     ,@body
     component))

;; 组件 memo 化
(defun aiaos-cli--component-memo (component)
  "为组件添加 memo 缓存

COMPONENT 是组件对象

返回一个新的 memo 化组件。"
  (let ((memo-hash (make-hash-table :test 'equal))
        (memo-component (make-aiaos-cli--component
                       :name (format "memo-%s" (aiaos-cli--component-name component))
                       :props (copy-hash-table (aiaos-cli--component-props component)))))
    ;; 设置渲染缓存
    (setf (gethash :render-cache memo-hash) nil)
    ;; 复制渲染函数
    (setf (aiaos-cli--component-render memo-component)
          (aiaos-cli--component-render component))
    memo-component))

;; 组件调试
(defun aiaos-cli--component-debug-info (component)
  "获取组件调试信息"
  (list :name (aiaos-cli--component-name component)
        :props-count (hash-table-count (aiaos-cli--component-props component))
        :children-count (length (aiaos-cli--component-get-children component))
        :has-render (not (null (aiaos-cli--component-render component)))
        :has-state (not (null (aiaos-cli--component-state component)))))

;; 初始化组件系统
(defun aiaos-cli--component-init ()
  "初始化组件系统"
  (setf aiaos-cli--component-registry (make-hash-table :test 'equal))
  (setf aiaos-cli--component-stack nil))

;; 清理组件
(defun aiaos-cli--component-cleanup (component)
  "清理组件

COMPONENT 是组件对象

会清理所有子组件和副作用。"
  (aiaos-cli--lifecycle-unmount (aiaos-cli--component-name component))
  (dolist (child (aiaos-cli--component-get-children component))
    (aiaos-cli--component-cleanup child))
  t)

(provide 'aiaos-cli-component)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-component.el ends here
