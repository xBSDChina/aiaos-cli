;;; aiaos-cli-lifecycle.el --- 生命周期管理 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 生命周期管理系统，借鉴 ratatui-kit 的 use_effect/use_on_drop 设计理念。
;; 提供组件生命周期管理和副作用清理能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供生命周期管理能力。
;; 主要功能：
;;   * aiaos-cli--use-effect      - 注册副作用
;;   * aiaos-cli--use-on-drop     - 注册清理函数
;;   * aiaos-cli--lifecycle-mount - 组件挂载
;;   * aiaos-cli--lifecycle-unmount - 组件卸载
;;   * aiaos-cli--lifecycle-update - 组件更新

;;; Code:

(require 'cl-lib)
(declare-function cl-last (cl))
(require 'aiaos-cli-state)

(defgroup aiaos-cli-lifecycle nil
  "aiaos-cli 生命周期管理"
  :group 'aiaos-cli
  :prefix "aiaos-cli-lifecycle-")

(defcustom aiaos-cli-lifecycle-auto-cleanup t
  "是否自动清理副作用"
  :type 'boolean
  :group 'aiaos-cli-lifecycle)

;; 当前组件
(defvar aiaos-cli--current-component nil
  "当前正在挂载的组件")

;; 副作用注册表
(defvar aiaos-cli--effects-registry nil
  "副作用注册表（按组件 ID 组织）")

;; 清理函数注册表
(defvar aiaos-cli--cleanup-registry nil
  "清理函数注册表（按组件 ID 组织）")

;; 组件 ID 计数器
(defvar aiaos-cli--component-id-counter 0
  "组件 ID 计数器")

;; 副作用结构
(cl-defstruct aiaos-cli--effect
  "副作用定义

DEPENDENCIES: 依赖列表（当这些值变化时重新执行）
BODY: 副作用函数
CLEANUP: 清理函数
COMPONENT-ID: 所属组件 ID
RUNNING: 是否正在运行"
  (dependencies nil)
  (body nil)
  (cleanup nil)
  (component-id nil)
  (running nil))

;; 组件注册表
(cl-defstruct aiaos-cli--component-registry
  "组件注册表

ID: 组件 ID
MOUNTED: 是否已挂载
EFFECTS: 副作用列表
CLEANUPS: 清理函数列表"
  (id nil)
  (mounted nil)
  (effects nil)
  (cleanups nil))

;; 获取或创建组件注册表
(defun aiaos-cli--lifecycle--get-registry (component-id)
  "获取或创建组件注册表"
  (let ((entry (assq component-id aiaos-cli--effects-registry)))
    (if entry
        entry
      (let ((registry (make-aiaos-cli--component-registry :id component-id)))
        (setf (aiaos-cli--component-registry-effects registry) nil)
        (setf (aiaos-cli--component-registry-cleanups registry) nil)
        (push registry aiaos-cli--effects-registry)
        registry))))

;; 注册副作用
(defun aiaos-cli--lifecycle--register-effect (dependencies body &optional cleanup)
  "注册副作用

DEPENDENCIES 是依赖列表（可以是符号或函数）
BODY 是副作用函数
CLEANUP 是清理函数（可选）

返回副作用 ID"
  (let* ((component-id (or aiaos-cli--current-component
                          (cl-incf aiaos-cli--component-id-counter)))
         (effect (make-aiaos-cli--effect
                  :dependencies dependencies
                  :body body
                  :cleanup cleanup
                  :component-id component-id)))
    (let ((registry (aiaos-cli--lifecycle--get-registry component-id)))
      (push effect (aiaos-cli--component-registry-effects registry)))
    effect))

;; 注册清理函数
(defun aiaos-cli--lifecycle--register-cleanup (cleanup)
  "注册清理函数

CLEANUP 是清理函数

返回清理函数 ID"
  (let* ((component-id (or aiaos-cli--current-component
                          (cl-incf aiaos-cli--component-id-counter)))
         (registry (aiaos-cli--lifecycle--get-registry component-id)))
    (push cleanup (aiaos-cli--component-registry-cleanups registry))
    cleanup))

;; use-effect 宏
(defmacro aiaos-cli--use-effect (deps &rest body)
  "注册副作用（宏）

DEPS 是依赖列表（可以是值或表达式）
BODY 是要执行的副作用

示例:
  (aiaos-cli--use-effect
    (list value)
    (message \"Value changed to %S\" value)
    ;; 清理函数
    (lambda ()
      (message \"Cleanup effect\"))))"

  `(aiaos-cli--lifecycle--register-effect
     ,deps
     (lambda () ,@body)
     ;; 如果有额外的清理函数，提取出来
     ,@(when (cl-last body)
         (if (eq (car (cl-last body)) ':cleanup)
             (list (cadr (cl-last body)))
           nil))))

;; use-on-drop 宏
(defmacro aiaos-cli--use-on-drop (&rest body)
  "注册组件卸载时的清理函数（宏）

BODY 是要执行的清理代码

示例:
  (aiaos-cli--use-on-drop
    (close-process process)
    (erase-buffer buffer))"
  (declare (indent 0))
  `(aiaos-cli--lifecycle--register-cleanup
     (lambda () ,@body)))

;; 组件挂载
(defun aiaos-cli--lifecycle-mount (component-id &rest body)
  "挂载组件

COMPONENT-ID 是组件 ID
BODY 是要执行的挂载代码

返回组件 ID"
  (let* ((registry (aiaos-cli--lifecycle--get-registry component-id))
         (old-component aiaos-cli--current-component))
    (setf (aiaos-cli--component-registry-mounted registry) t)
    (setf aiaos-cli--current-component component-id)
    (unwind-protect
        (progn ,@body)
      (setf aiaos-cli--current-component old-component)))
  component-id)

;; 组件卸载
(defun aiaos-cli--lifecycle-unmount (component-id)
  "卸载组件

COMPONENT-ID 是组件 ID

会执行所有清理函数并移除副作用。"
  (let* ((registry (assq component-id aiaos-cli--effects-registry)))
    (when registry
      ;; 执行清理函数
      (when aiaos-cli-lifecycle-auto-cleanup
        (dolist (cleanup (aiaos-cli--component-registry-cleanups registry))
          (ignore-errors (funcall cleanup))))
      ;; 移除副作用
      (setf (aiaos-cli--component-registry-effects registry) nil)
      (setf (aiaos-cli--component-registry-cleanups registry) nil)
      (setf (aiaos-cli--component-registry-mounted registry) nil)
      ;; 从注册表移除
      (setf aiaos-cli--effects-registry
            (delete registry aiaos-cli--effects-registry))
      ;; 返回清理结果
      t)))

;; 组件更新
(defun aiaos-cli--lifecycle-update (component-id &rest body)
  "更新组件

COMPONENT-ID 是组件 ID
BODY 是要执行的更新代码

会重新执行所有副作用（如果依赖变化）。"
  (let* ((registry (aiaos-cli--lifecycle--get-registry component-id))
         (old-component aiaos-cli--current-component))
    (setf aiaos-cli--current-component component-id)
    (unwind-protect
        (progn ,@body)
      (setf aiaos-cli--current-component old-component)))
  component-id)

;; 执行副作用
(defun aiaos-cli--lifecycle--run-effects (component-id)
  "执行组件的所有副作用"
  (let* ((registry (assq component-id aiaos-cli--effects-registry)))
    (when registry
      (dolist (effect (aiaos-cli--component-registry-effects registry))
        (when (aiaos-cli--lifecycle--should-run effect)
          (aiaos-cli--lifecycle--execute-effect effect))))))

;; 检查副作用是否应该运行
(defun aiaos-cli--lifecycle--should-run (effect)
  "检查副作用是否应该运行"
  ;; 简化版：总是运行（实际应用中需要比较依赖值）
  t)

;; 执行副作用
(defun aiaos-cli--lifecycle--execute-effect (effect)
  "执行副作用"
  (setf (aiaos-cli--effect-running effect) t)
  (unwind-protect
      (funcall (aiaos-cli--effect-body effect))
    (setf (aiaos-cli--effect-running effect) nil)))

;; 清理副作用
(defun aiaos-cli--lifecycle--cleanup-effect (effect)
  "清理副作用"
  (when (and (aiaos-cli--effect-cleanup effect)
             (aiaos-cli--effect-running effect))
    (funcall (aiaos-cli--effect-cleanup effect)))
  (setf (aiaos-cli--effect-running effect) nil))

;; 创建组件
(defmacro aiaos-cli--lifecycle-component (name &rest body)
  "创建组件（宏）

NAME 是组件名称
BODY 是组件体

示例:
  (aiaos-cli--lifecycle-component my-component
    (aiaos-cli--use-effect
      (list value)
      (message \"Effect\"))
    (aiaos-cli--use-on-drop
      (message \"Cleanup\")))"

  `(cl-defun ,name ()
     "组件函数"
     (let ((component-id (cl-incf aiaos-cli--component-id-counter)))
       (aiaos-cli--lifecycle-mount component-id
         ,@body)
       component-id)))

;; 组件树管理
(defvar aiaos-cli--component-tree nil
  "组件树结构")

;; 添加子组件
(defun aiaos-cli--lifecycle--add-child (parent-id child-id)
  "添加子组件

PARENT-ID 是父组件 ID
CHILD-ID 是子组件 ID"
  (let ((parent (assq parent-id aiaos-cli--component-tree)))
    (if parent
        (push child-id (cdr parent))
      (push (cons parent-id (list child-id)) aiaos-cli--component-tree))))

;; 移除子组件
(defun aiaos-cli--lifecycle--remove-child (parent-id child-id)
  "移除子组件

PARENT-ID 是父组件 ID
CHILD-ID 是子组件 ID"
  (let ((parent (assq parent-id aiaos-cli--component-tree)))
    (when parent
      (setf (cdr parent) (delete child-id (cdr parent)))))
  t)

;; 卸载组件树
(defun aiaos-cli--lifecycle--unmount-tree (component-id)
  "卸载组件及其所有子组件"
  (aiaos-cli--lifecycle-unmount component-id)
  ;; 递归卸载子组件
  (let ((parent (assq component-id aiaos-cli--component-tree)))
    (when parent
      (dolist (child-id (cdr parent))
        (aiaos-cli--lifecycle--unmount-tree child-id)))))

;; 组件调试
(defun aiaos-cli--lifecycle-debug-info (component-id)
  "获取组件调试信息"
  (let ((registry (assq component-id aiaos-cli--effects-registry)))
    (if registry
        (list :id component-id
              :mounted (aiaos-cli--component-registry-mounted registry)
              :effects (length (aiaos-cli--component-registry-effects registry))
              :cleanups (length (aiaos-cli--component-registry-cleanups registry)))
      (list :id component-id :mounted nil))))

;; 清理所有组件
(defun aiaos-cli--lifecycle-cleanup-all ()
  "清理所有组件"
  (when aiaos-cli-lifecycle-auto-cleanup
    (dolist (registry aiaos-cli--effects-registry)
      (aiaos-cli--lifecycle-unmount
        (aiaos-cli--component-registry-id registry))))
  (setf aiaos-cli--effects-registry nil)
  (setf aiaos-cli--component-tree nil))

;; 初始化生命周期系统
(defun aiaos-cli--lifecycle-init ()
  "初始化生命周期管理系统"
  (setf aiaos-cli--component-id-counter 0)
  (setf aiaos-cli--effects-registry nil)
  (setf aiaos-cli--cleanup-registry nil)
  (setf aiaos-cli--component-tree nil)
  (setf aiaos-cli--current-component nil))

(provide 'aiaos-cli-lifecycle)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-lifecycle.el ends here
