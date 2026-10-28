;;; aiaos-cli-state.el --- 响应式状态管理 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos, tui

;; 响应式状态管理系统，借鉴 ratatui-kit 的 use_state hook 设计理念。
;; 提供类似 React useState 的响应式状态管理能力。

;;; Commentary:

;; 本模块为 aiaos-cli 提供响应式状态管理能力。
;; 主要功能：
;;   * aiaos-cli--use-state     - 创建响应式状态
;;   * aiaos-cli--state-get     - 获取状态值
;;   * aiaos-cli--state-set     - 设置状态值（触发更新）
;;   * aiaos-cli--state-update  - 更新状态值（函数式）
;;   * aiaos-cli--state-batch   - 批量更新
;;   * aiaos-cli--state-subscribe - 订阅状态变化

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-core)

(defgroup aiaos-cli-state nil
  "aiaos-cli 响应式状态管理"
  :group 'aiaos-cli
  :prefix "aiaos-cli-state-")

(defcustom aiaos-cli-state-auto-render t
  "是否在状态变化时自动重绘"
  :type 'boolean
  :group 'aiaos-cli-state)

(defcustom aiaos-cli-state-render-debounce 0.1
  "重绘防抖时间（秒）"
  :type 'number
  :group 'aiaos-cli-state)

;; 状态存储结构
(cl-defstruct aiaos-cli--state
  "响应式状态容器

VALUE: 当前值
SUBSCRIBERS: 订阅者列表（函数列表）
LOCKED: 防止并发修改标志
ID: 唯一标识符"
  (value nil)
  (subscribers nil)
  (locked nil)
  (id nil))

(defvar aiaos-cli--state-counter 0
  "状态 ID 计数器")

(defvar aiaos-cli--state-registry nil
  "所有活跃状态的注册表（用于调试）")

(defvar aiaos-cli--state-render-queue nil
  "待重绘的组件列表")

;; 创建响应式状态
(defun aiaos-cli--state-create (initial-value)
  "创建响应式状态

INITIAL-VALUE 是初始值。

返回一个状态句柄，可以用 aiaos-cli--state-get/set 操作。"
  (cl-incf aiaos-cli--state-counter)
  (let ((state (make-aiaos-cli--state
                 :value initial-value
                 :id aiaos-cli--state-counter)))
    (push (cons state nil) aiaos-cli--state-registry)
    state))

;; 获取状态值
(defun aiaos-cli--state-get (state)
  "获取状态当前值"
  (aiaos-cli--state-value state))

;; 设置状态值
(defun aiaos-cli--state-set (state value)
  "设置状态值并通知订阅者

STATE 是状态句柄
VALUE 是新值

会触发所有订阅者的回调函数。"
  (unless (aiaos-cli--state-locked state)
    (setf (aiaos-cli--state-value state) value)
    (aiaos-cli--state--notify state)))

;; 更新状态值（函数式）
(defun aiaos-cli--state-update (state updater)
  "使用函数更新状态值

STATE 是状态句柄
UPDATER 是函数，接收当前值，返回新值

示例: (aiaos-cli--state-update counter (lambda (v) (1+ v)))"
  (aiaos-cli--state-set state (funcall updater (aiaos-cli--state-value state))))

;; 批量更新
(defmacro aiaos-cli--state-batch (state &rest body)
  "批量更新状态，只触发一次通知

STATE 是状态句柄
BODY 是要执行的更新操作

示例:
  (aiaos-cli--state-batch state
    (aiaos-cli--state-set state 1)
    (aiaos-cli--state-set state 2)
    ;; 只会触发一次通知)"
  (declare (indent 1))
  `(progn
     (setf (aiaos-cli--state-locked ,state) t)
     ,@body
     (setf (aiaos-cli--state-locked ,state) nil)
     (aiaos-cli--state--notify ,state)))

;; 订阅状态变化
(defun aiaos-cli--state-subscribe (state callback)
  "订阅状态变化

STATE 是状态句柄
CALLBACK 是回调函数，接收状态句柄作为参数

返回一个取消订阅的函数"
  (add-to-list (aiaos-cli--state-subscribers state) callback t)
  (let ((subscriber-list (aiaos-cli--state-subscribers state)))
    (lambda ()
      (setf (aiaos-cli--state-subscribers state)
            (delq callback subscriber-list)))
))

;; 通知订阅者
(defun aiaos-cli--state--notify (state)
  "通知所有订阅者状态已变化"
  (let ((subscribers (aiaos-cli--state-subscribers state)))
    (dolist (cb subscribers)
      (funcall cb state))
    (when (and aiaos-cli-state-auto-render (buffer-live-p (current-buffer)))
      (push state aiaos-cli--state-render-queue))))

;; use-state 宏
(defmacro aiaos-cli--use-state (init-form)
  "创建响应式状态（组件内使用）

INIT-FORM 是初始值的求值形式

示例:
  (let ((counter (aiaos-cli--use-state 0)))
    (aiaos-cli--state-set counter 5)))"
  (declare (indent 1))
  `(aiaos-cli--state-create ,init-form))

;; 派生状态
(defun aiaos-cli--state-derive (state deriver)
  "派生状态

STATE 是源状态
DERIVER 是派生函数，接收源状态值，返回派生值

返回派生状态的 getter 函数"
  (let ((derived-state (aiaos-cli--state-create nil)))
    (aiaos-cli--state-subscribe state
      (lambda (_)
        (aiaos-cli--state-set derived-state (funcall deriver (aiaos-cli--state-value state)))))
    (lambda ()
      (aiaos-cli--state-value derived-state))))

;; 状态持久化
(defun aiaos-cli--state-save (state file)
  "保存状态到文件

STATE 是状态句柄
FILE 是文件路径"
  (with-temp-file file
    (princ (format "%S" (aiaos-cli--state-value state)) file)))

(defun aiaos-cli--state-load (file)
  "从文件加载状态

FILE 是文件路径
返回新的状态句柄"
  (let* ((value (with-temp-buffer
                  (insert-file-contents file)
                  (read (buffer-string))))
       (state (aiaos-cli--state-create value)))
    state))

;; 状态调试
(defun aiaos-cli--state-debug-info (state)
  "获取状态调试信息"
  (list :id (aiaos-cli--state-id state)
        :value (aiaos-cli--state-value state)
        :subscribers (length (aiaos-cli--state-subscribers state))
        :locked (aiaos-cli--state-locked state)))

;; 清理无用状态
(defun aiaos-cli--state-gc ()
  "垃圾回收，清理无用状态"
  (setf aiaos-cli--state-registry nil))

;; 清空渲染队列
(defun aiaos-cli--state-flush-render-queue ()
  "清空渲染队列"
  (setf aiaos-cli--state-render-queue nil))

;;;###autoload
(defun aiaos-cli--state-init ()
  "初始化状态管理系统"
  (setf aiaos-cli--state-counter 0)
  (setf aiaos-cli--state-registry nil)
  (setf aiaos-cli--state-render-queue nil))

;; Public API aliases
(defalias 'aiaos-cli-state-init 'aiaos-cli--state-init)
(defalias 'aiaos-cli-state-get 'aiaos-cli--state-get)
(defalias 'aiaos-cli-state-set 'aiaos-cli--state-set)
(defalias 'aiaos-cli-state-subscribe 'aiaos-cli--state-subscribe)
(defalias 'aiaos-cli-state-update 'aiaos-cli--state-update)

(provide 'aiaos-cli-state)

;;; Footer:

;; Local Variables:
;; folded-file: t
;; End:

;;; aiaos-cli-state.el ends here
