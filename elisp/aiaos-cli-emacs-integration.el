;;; aiaos-cli-emacs-integration.el --- AIAOS CLI Emacs集成层  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 整合所有Emacs层，提供统一的API接口

(require 'aiaos-cli-core)
(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-emacs-controller)
(require 'aiaos-cli-emacs-callback)

(defgroup aiaos-cli-emacs-integration nil
  "AIAOS CLI Emacs集成层"
  :prefix "aiaos-cli-emacs-integration-"
  :group 'aiaos-cli-emacs)

;;; 缓冲区操作

(defun aiaos-cli-emacs-integration-get-all-buffers ()
  "获取所有缓冲区信息"
  (aiaos-cli-emacs-adapter-get-all-buffers))

(defun aiaos-cli-emacs-integration-get-buffer (name)
  "获取指定缓冲区信息"
  (aiaos-cli-emacs-adapter-get-buffer name))

(defun aiaos-cli-emacs-integration-create-buffer (name mode)
  "创建缓冲区"
  (aiaos-cli-emacs-controller-create-buffer name mode))

(defun aiaos-cli-emacs-integration-switch-buffer (name)
  "切换缓冲区"
  (aiaos-cli-emacs-controller-switch-buffer name))

;;; 文本操作

(defun aiaos-cli-emacs-integration-insert-text (text &optional point)
  "插入文本"
  (aiaos-cli-emacs-adapter-insert-text text point))

(defun aiaos-cli-emacs-integration-get-text (start end)
  "获取文本"
  (aiaos-cli-emacs-adapter-get-text start end))

(defun aiaos-cli-emacs-integration-replace-text (start end new-text)
  "替换文本"
  (aiaos-cli-emacs-adapter-replace-text start end new-text))

;;; 窗口操作

(defun aiaos-cli-emacs-integration-split-window (&optional side)
  "分割窗口"
  (aiaos-cli-emacs-controller-split-window side))

;;; 帧操作

(defun aiaos-cli-emacs-integration-create-frame (params)
  "创建帧"
  (aiaos-cli-emacs-controller-create-frame params))

(defun aiaos-cli-emacs-integration-get-frames ()
  "获取所有帧"
  (aiaos-cli-emacs-adapter-get-frames))

;;; 模式操作

(defun aiaos-cli-emacs-integration-get-mode ()
  "获取当前模式"
  (aiaos-cli-emacs-adapter-get-major-mode))

;;; 命令执行

(defun aiaos-cli-emacs-integration-execute-command (command &rest args)
  "执行命令"
  (apply #'aiaos-cli-emacs-controller-execute-command command args))

;;; 配置管理

(defun aiaos-cli-emacs-integration-get-config (key default)
  "获取配置"
  (aiaos-cli-emacs-adapter-get-config key default))

(defun aiaos-cli-emacs-integration-set-config (key value)
  "设置配置"
  (aiaos-cli-emacs-adapter-set-config key value))

;;; 事件系统

(defun aiaos-cli-emacs-integration-register-event (event-type callback)
  "注册事件"
  (aiaos-cli-emacs-controller-register-event event-type callback))

(provide 'aiaos-cli-emacs-integration)

;;; aiaos-cli-emacs-integration.el 结束