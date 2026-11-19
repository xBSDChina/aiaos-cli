;;; aiaos-cli-emacs-controller.el --- AIAOS CLI Emacs管控层  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 提供Emacs操作的高层封装，包含错误处理和重试机制

(require 'aiaos-cli-core)
(require 'cl-lib)
(require 'aiaos-cli-emacs-adapter)

(defgroup aiaos-cli-emacs-controller nil
  "AIAOS CLI Emacs管控层"
  :prefix "aiaos-cli-emacs-controller-"
  :group 'aiaos-cli-emacs)

;;; 变量定义

(defcustom aiaos-cli-emacs-controller-retry-count 3
  "重试次数"
  :type 'integer
  :group 'aiaos-cli-emacs-controller)

(defcustom aiaos-cli-emacs-controller-retry-delay 100
  "重试延迟（毫秒）"
  :type 'integer
  :group 'aiaos-cli-emacs-controller)

;;; 重试机制

(defun aiaos-cli-emacs-controller-with-retry (func &optional max-retry)
  "执行函数，失败时重试"
  (let ((retry-count 0)
        (max-retry (or max-retry aiaos-cli-emacs-controller-retry-count))
        (result nil)
        (error nil))
    (while (and (not result) (<= retry-count max-retry))
      (condition-case err
          (progn
            (setq result (funcall func))
            ;; 函数成功执行但返回 nil 时，视为一次尝试完成，避免无限循环
            (when (and (null result) (< retry-count max-retry))
              (cl-incf retry-count)))
        (error 
         (setq error err)
         (aiaos-log "warning" 
                    (format "Retry %d/%d" retry-count max-retry) err)
         (when (< retry-count max-retry)
           (sit-for (/ aiaos-cli-emacs-controller-retry-delay 1000.0))
           (cl-incf retry-count)))))
    (if result
        result
      (error "Operation failed after %d retries: %s" max-retry error))))

;;; 缓冲区操作

(defun aiaos-cli-emacs-controller-get-buffer (name)
  "获取缓冲区信息"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (let ((buf (get-buffer name)))
       (if buf
           (aiaos-cli-emacs-adapter-buffer-info buf)
         nil)))))

(defun aiaos-cli-emacs-controller-create-buffer (name mode)
  "创建缓冲区"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (let ((buf (get-buffer-create name)))
       (with-current-buffer buf
         (funcall mode))
       (aiaos-cli-emacs-adapter-buffer-info buf)))))

(defun aiaos-cli-emacs-controller-switch-buffer (name)
  "切换缓冲区"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (let ((buf (get-buffer name)))
       (if buf
           (switch-to-buffer buf)
         (switch-to-buffer (get-buffer-create name)))
       (aiaos-cli-emacs-adapter-buffer-info (get-buffer name))))))

;;; 窗口操作

(defun aiaos-cli-emacs-controller-split-window (&optional side)
  "分割窗口"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (let ((window (split-window (selected-window) nil side)))
       (if window
           (aiaos-cli-emacs-adapter-window-info window)
         nil)))))

;;; 帧操作

(defun aiaos-cli-emacs-controller-create-frame (params)
  "创建帧"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (let ((frame (make-frame params)))
       (if frame
           (aiaos-cli-emacs-adapter-frame-info frame)
         nil)))))

;;; 文本操作

(defun aiaos-cli-emacs-controller-insert-text (text &optional point)
  "插入文本"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (save-excursion
       (if point
           (goto-char point)
         (goto-char (point-max)))
       (insert text)
       t))))

(defun aiaos-cli-emacs-controller-get-text (start end)
  "获取文本"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (buffer-substring start end))))

(defun aiaos-cli-emacs-controller-replace-text (start end new-text)
  "替换文本"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (save-excursion
       (goto-char start)
       (delete-region start end)
       (insert new-text)
       t))))

;;; 模式操作

(defun aiaos-cli-emacs-controller-get-mode ()
  "获取当前模式"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     major-mode)))

;;; 命令执行

(defun aiaos-cli-emacs-controller-execute-command (command &rest args)
  "执行命令"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (apply command args)
     t)))

;;; 配置管理

(defun aiaos-cli-emacs-controller-get-config (key default)
  "获取配置"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (aiaos-cli-emacs-adapter-get-config key default))))

(defun aiaos-cli-emacs-controller-set-config (key value)
  "设置配置"
  (aiaos-cli-emacs-controller-with-retry
   (lambda ()
     (aiaos-cli-emacs-adapter-set-config key value)
     t)))

;;; 事件系统

;; 使用全局变量存储事件处理器
(defconst aiaos-cli-emacs-controller-event-handlers nil)

(defun aiaos-cli-emacs-controller-register-event (event-type callback)
  "注册事件"
  (push (cons event-type callback) aiaos-cli-emacs-controller-event-handlers)
  t)

(defun aiaos-cli-emacs-controller-trigger-event (event-type &rest args)
  "触发事件"
  (dolist (handler aiaos-cli-emacs-controller-event-handlers)
    (when (eq (car handler) event-type)
      (condition-case err
          (apply (cdr handler) args)
        (error (aiaos-log "error" "Event handler failed" err))))))

(provide 'aiaos-cli-emacs-controller)

;;; aiaos-cli-emacs-controller.el 结束