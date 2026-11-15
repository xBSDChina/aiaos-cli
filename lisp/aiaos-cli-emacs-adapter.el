;;; aiaos-cli-emacs-adapter.el --- Emacs适配层：封装所有Emacs API

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 提供统一的Emacs API封装，支持缓冲区、窗口、帧、模式等管理

(require 'aiaos-cli-core)

(defgroup aiaos-cli-emacs-adapter nil
  "AIAOS CLI Emacs适配层"
  :prefix "aiaos-cli-emacs-adapter-")

;;; 变量定义

(defcustom aiaos-cli-emacs-adapter-cache-enabled t
  "是否启用缓存"
  :type 'boolean
  :group 'aiaos-cli-emacs-adapter)

(defcustom aiaos-cli-emacs-adapter-batch-size 50
  "批量操作大小"
  :type 'integer
  :group 'aiaos-cli-emacs-adapter)

;;; 缓存系统

(cl-defstruct aiaos-cli-emacs-adapter-cache
  "缓存结构"
  (buffers nil)
  (windows nil)
  (frames nil)
  (modes nil)
  (last-update nil))

(defconst aiaos-cli-emacs-adapter-cache (make-aiaos-cli-emacs-adapter-cache))

;;; 缓冲区管理适配

(defun aiaos-cli-emacs-adapter-get-buffer (name)
  "获取缓冲区信息"
  (let ((buf (get-buffer name)))
    (if buf
        (aiaos-cli-emacs-adapter-buffer-info buf)
      nil)))

(defun aiaos-cli-emacs-adapter-buffer-info (buffer)
  "获取缓冲区详细信息"
  (with-current-buffer buffer
    `((name . ,(buffer-name))
      (file-name . ,(buffer-file-name))
      (size . ,(buffer-size))
      (point . ,(point))
      (point-min . ,(point-min))
      (point-max . ,(point-max))
      (major-mode . ,major-mode)
      (minor-modes . ,(aiaos-cli-emacs-adapter-get-minor-modes))
      (modified . ,(buffer-modified-p))
      (read-only . ,(if (boundp 'buffer-read-only) buffer-read-only nil)))))

(defun aiaos-cli-emacs-adapter-get-minor-modes ()
  "获取所有激活的minor modes"
  (let (modes)
    (dolist (mode minor-mode-list)
      (when (and mode (symbolp mode) (boundp mode) (symbol-value mode))
        (push (symbol-name mode) modes)))
    modes))

(defun aiaos-cli-emacs-adapter-get-all-buffers ()
  "获取所有缓冲区信息"
  (mapcar #'aiaos-cli-emacs-adapter-buffer-info (buffer-list)))

;;; 窗口管理适配

(defun aiaos-cli-emacs-adapter-get-window (frame)
  "获取指定帧的窗口信息"
  (with-selected-window (frame-first-window frame)
    `((frame . ,(aiaos-cli-emacs-adapter-frame-info frame))
      (selected . ,(window-buffer))
      (all-windows . ,(aiaos-cli-emacs-adapter-get-frame-windows frame)))))

(defun aiaos-cli-emacs-adapter-get-frame-windows (frame)
  "获取帧的所有窗口"
  (let (windows)
    (walk-window-tree (lambda (w)
                        (when (eq (window-frame w) frame)
                          (push (aiaos-cli-emacs-adapter-window-info w) windows)))
                      frame)
    windows))

(defun aiaos-cli-emacs-adapter-window-info (window)
  "获取窗口详细信息"
  `((buffer . ,(window-buffer window))
    (start . ,(window-start window))
    (end . ,(window-end window))
    (point . ,(window-point window))
    (left . ,(if (fboundp 'window-left-edge) (window-left-edge window) 0))
    (top . ,(if (fboundp 'window-top-edge) (window-top-edge window) 0))
    (width . ,(if (fboundp 'window-width) (window-width window) 0))
    (height . ,(if (fboundp 'window-height) (window-height window) 0))))

;;; 帧管理适配

(defun aiaos-cli-emacs-adapter-get-frames ()
  "获取所有帧信息"
  (mapcar #'aiaos-cli-emacs-adapter-frame-info (frame-list)))

(defun aiaos-cli-emacs-adapter-frame-info (frame)
  "获取帧详细信息"
  `((name . ,(frame-parameter frame 'name))
    (width . ,(frame-width frame))
    (height . ,(frame-height frame))
    (left . ,(frame-parameter frame 'left))
    (top . ,(frame-parameter frame 'top))
    (buffer-list . ,(mapcar #'buffer-name (buffer-list frame)))
    (selected-window . ,(aiaos-cli-emacs-adapter-window-info
                                  (frame-selected-window frame)))))

;;; 模式管理适配

(defun aiaos-cli-emacs-adapter-get-major-mode ()
  "获取当前主模式"
  (symbol-name major-mode))

(defun aiaos-cli-emacs-adapter-get-all-modes ()
  "获取所有模式信息"
  `((major . ,(aiaos-cli-emacs-adapter-get-major-mode))
    (minor . ,(aiaos-cli-emacs-adapter-get-minor-modes))
    (major-mode-list . ,(aiaos-cli-emacs-adapter-get-major-mode-list))))

(defun aiaos-cli-emacs-adapter-get-major-mode-list ()
  "获取所有可用的主模式列表"
  (let (modes)
    (dolist (mode minor-mode-list)
      (when (functionp mode)
        (push (symbol-name mode) modes)))
    modes))

;;; 文本操作适配

(defun aiaos-cli-emacs-adapter-insert-text (text &optional point)
  "在指定位置插入文本"
  (save-excursion
    (if point (goto-char point))
    (insert text)
    (point)))

(defun aiaos-cli-emacs-adapter-get-text (start end)
  "获取指定范围的文本"
  (buffer-substring start end))

(defun aiaos-cli-emacs-adapter-replace-text (start end new-text)
  "替换指定范围的文本"
  (delete-region start end)
  (goto-char start)
  (insert new-text))

;;; 命令执行适配

(defun aiaos-cli-emacs-adapter-execute-command (command &rest args)
  "执行Emacs命令"
  (condition-case err
      (apply command args)
    (error (aiaos-log "error" "Command execution failed" err) nil)))

;;; 配置管理适配

(defun aiaos-cli-emacs-adapter-get-config (key default)
  "获取配置值"
  (aiaos-cli-core-get-config key default))

(defun aiaos-cli-emacs-adapter-set-config (key value)
  "设置配置值"
  (aiaos-cli-core-set-config key value))

;;; 事件系统适配

(defcustom aiaos-cli-emacs-adapter-events-enabled t
  "是否启用事件系统"
  :type 'boolean
  :group 'aiaos-cli-emacs-adapter)

(let ((events nil))
  (defun aiaos-cli-emacs-adapter-register-event (event-type callback)
    "注册事件回调"
    (push (cons event-type callback) events))
  
  (defun aiaos-cli-emacs-adapter-trigger-event (event-type &rest args)
    "触发事件"
    (dolist (event events)
      (when (eq (car event) event-type)
        (condition-case err
            (apply (cdr event) args)
          (error (aiaos-log "error" "Event callback failed" err)))))))

(provide 'aiaos-cli-emacs-adapter)

;;; aiaos-cli-emacs-adapter.el 结束