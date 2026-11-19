;;; aiaos-cli-emacs.el --- AIAOS CLI Emacs主加载文件  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 加载所有Emacs集成层，提供统一的Emacs管理接口

(require 'aiaos-cli-core)
(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-emacs-controller)
(require 'aiaos-cli-emacs-callback)
(require 'aiaos-cli-emacs-call)
(require 'aiaos-cli-emacs-integration)
(require 'aiaos-cli-emacs-performance)
(require 'aiaos-cli-emacs-security)

(defgroup aiaos-cli-emacs nil
  "AIAOS CLI Emacs集成"
  :prefix "aiaos-cli-emacs-"
  :group 'aiaos)

;;; 配置变量

(defcustom aiaos-cli-emacs-auto-sync t
  "是否自动同步Emacs状态到AIAOS CLI"
  :type 'boolean
  :group 'aiaos-cli-emacs)

(defcustom aiaos-cli-emacs-sync-interval 500
  "状态同步间隔（毫秒）"
  :type 'integer
  :group 'aiaos-cli-emacs)

(defcustom aiaos-cli-emacs-cache-enabled t
  "是否启用缓存"
  :type 'boolean
  :group 'aiaos-cli-emacs)

;;; 同步定时器

(defconst aiaos-cli-emacs-sync-timer nil)

;;; 初始化

(defun aiaos-cli-emacs-init ()
  "初始化Emacs集成"
  (interactive)
  (aiaos-log "info" "Initializing AIAOS CLI Emacs integration")
  
  ;; 初始化各层
  (aiaos-cli-emacs-adapter-init)
  (aiaos-cli-emacs-controller-init)
  (aiaos-cli-emacs-callback-init)
  (aiaos-cli-emacs-call-init)
  (aiaos-cli-emacs-integration-init)
  (aiaos-cli-emacs-performance-init)
  (aiaos-cli-emacs-security-init)
  
  ;; 注册默认事件处理器
  (aiaos-cli-emacs-register-default-handlers)
  
  ;; 启动自动同步
  (when aiaos-cli-emacs-auto-sync
    (aiaos-cli-emacs-start-auto-sync))
  
  (aiaos-log "info" "AIAOS CLI Emacs integration initialized")
  t)

(defun aiaos-cli-emacs-adapter-init ()
  "初始化适配层"
  (aiaos-log "debug" "Adapter layer initialized"))

(defun aiaos-cli-emacs-controller-init ()
  "初始化管控层"
  (aiaos-log "debug" "Controller layer initialized"))

(defun aiaos-cli-emacs-callback-init ()
  "初始化回调层"
  (aiaos-log "debug" "Callback layer initialized"))

(defun aiaos-cli-emacs-call-init ()
  "初始化调用层"
  (aiaos-log "debug" "Call layer initialized"))

(defun aiaos-cli-emacs-integration-init ()
  "初始化集成层"
  (aiaos-log "debug" "Integration layer initialized"))

(defun aiaos-cli-emacs-performance-init ()
  "初始化性能优化层"
  (aiaos-log "debug" "Performance layer initialized"))

;;; 默认事件处理器

(defun aiaos-cli-emacs-register-default-handlers ()
  "注册默认事件处理器"
  ;; 缓冲区事件
  (aiaos-cli-emacs-register-event 
   'buffer-created 'aiaos-cli-emacs-on-buffer-created)
  (aiaos-cli-emacs-register-event 
   'buffer-switched 'aiaos-cli-emacs-on-buffer-switched)
  (aiaos-cli-emacs-register-event 
   'buffer-modified 'aiaos-cli-emacs-on-buffer-modified)
  
  ;; 帧事件
  (aiaos-cli-emacs-register-event 
   'frame-created 'aiaos-cli-emacs-on-frame-created)
  (aiaos-cli-emacs-register-event 
   'frame-selected 'aiaos-cli-emacs-on-frame-selected)
  
  ;; 模式事件
  (aiaos-cli-emacs-register-event 
   'mode-changed 'aiaos-cli-emacs-on-mode-changed)
  
  ;; 命令事件
  (aiaos-cli-emacs-register-event 
   'post-command 'aiaos-cli-emacs-on-post-command))

;;; 事件处理器实现

(defun aiaos-cli-emacs-on-buffer-created (buffer)
  "缓冲区创建事件处理器"
  (aiaos-log "debug" "Buffer created" (buffer-name buffer))
  (aiaos-cli-emacs-sync-state)
  (aiaos-cli-emacs-perf-invalidate-buffer-cache))

(defun aiaos-cli-emacs-on-buffer-switched (buffer)
  "缓冲区切换事件处理器"
  (aiaos-log "debug" "Buffer switched" (buffer-name buffer))
  (aiaos-cli-emacs-sync-state))

(defun aiaos-cli-emacs-on-buffer-modified (buffer)
  "缓冲区修改事件处理器"
  (aiaos-log "debug" "Buffer modified" (buffer-name buffer))
  (aiaos-cli-emacs-sync-state)
  (aiaos-cli-emacs-perf-invalidate-buffer-cache))

(defun aiaos-cli-emacs-on-frame-created (frame)
  "帧创建事件处理器"
  (aiaos-log "debug" "Frame created" (frame-parameter frame 'name))
  (aiaos-cli-emacs-sync-state)
  (aiaos-cli-emacs-perf-invalidate-frame-cache))

(defun aiaos-cli-emacs-on-frame-selected (frame)
  "帧选择事件处理器"
  (aiaos-log "debug" "Frame selected" (frame-parameter frame 'name))
  (aiaos-cli-emacs-sync-state))

(defun aiaos-cli-emacs-on-mode-changed (mode)
  "模式改变事件处理器"
  (aiaos-log "debug" "Mode changed" mode)
  (aiaos-cli-emacs-sync-state))

(defun aiaos-cli-emacs-on-post-command (command)
  "命令执行后事件处理器"
  (aiaos-log "debug" "Command executed" command)
  (aiaos-cli-emacs-sync-state))

;;; 事件注册

(defun aiaos-cli-emacs-register-event (event-type callback)
  "注册事件"
  (aiaos-cli-emacs-callback-register event-type callback))

;;; 自动同步

(defun aiaos-cli-emacs-start-auto-sync ()
  "启动自动同步"
  (aiaos-cli-emacs-stop-auto-sync)
  (setq aiaos-cli-emacs-sync-timer
        (run-with-timer aiaos-cli-emacs-sync-interval
                        aiaos-cli-emacs-sync-interval
                        'aiaos-cli-emacs-sync-state))
  (aiaos-log "info" "Auto-sync started"))

(defun aiaos-cli-emacs-stop-auto-sync ()
  "停止自动同步"
  (when aiaos-cli-emacs-sync-timer
    (cancel-timer aiaos-cli-emacs-sync-timer)
    (setq aiaos-cli-emacs-sync-timer nil))
  (aiaos-log "info" "Auto-sync stopped"))

;;; 状态同步

(defun aiaos-cli-emacs-sync-state ()
  "同步Emacs状态到AIAOS CLI"
  (condition-case err
      (let ((state (aiaos-cli-emacs-get-current-state)))
        (aiaos-log "debug" "Syncing state" state)
        ;; 这里可以将状态发送到AIAOS CLI核心
        (when (fboundp 'aiaos-cli-core-sync-emacs-state)
          (aiaos-cli-core-sync-emacs-state state)))
    (error (aiaos-log "error" "State sync failed" err))))

(defun aiaos-cli-emacs-get-current-state ()
  "获取当前Emacs状态"
  `((buffers . ,(aiaos-cli-emacs-integration-get-all-buffers))
    (frames . ,(aiaos-cli-emacs-integration-get-frames))
    (current-buffer . ,(aiaos-cli-emacs-integration-get-buffer 
                         (buffer-name (current-buffer))))
    (current-frame . ,(aiaos-cli-emacs-integration-get-frames))
    (major-mode . ,(aiaos-cli-emacs-integration-get-mode))
    (timestamp . ,(current-time))))

;;; 统一API接口

;; 缓冲区操作
(defun aiaos-cli-emacs-get-all-buffers ()
  "获取所有缓冲区"
  (aiaos-cli-emacs-integration-get-all-buffers))

(defun aiaos-cli-emacs-get-buffer (name)
  "获取缓冲区"
  (aiaos-cli-emacs-integration-get-buffer name))

(defun aiaos-cli-emacs-create-buffer (name mode)
  "创建缓冲区"
  (aiaos-cli-emacs-integration-create-buffer name mode))

(defun aiaos-cli-emacs-switch-buffer (name)
  "切换缓冲区"
  (aiaos-cli-emacs-integration-switch-buffer name))

;; 文本操作
(defun aiaos-cli-emacs-insert-text (text &optional point)
  "插入文本"
  (aiaos-cli-emacs-integration-insert-text text point))

(defun aiaos-cli-emacs-get-text (start end)
  "获取文本"
  (aiaos-cli-emacs-integration-get-text start end))

(defun aiaos-cli-emacs-replace-text (start end new-text)
  "替换文本"
  (aiaos-cli-emacs-integration-replace-text start end new-text))

;; 窗口操作
(defun aiaos-cli-emacs-split-window (&optional side)
  "分割窗口"
  (aiaos-cli-emacs-integration-split-window side))

;; 帧操作
(defun aiaos-cli-emacs-create-frame (params)
  "创建帧"
  (aiaos-cli-emacs-integration-create-frame params))

(defun aiaos-cli-emacs-get-frames ()
  "获取所有帧"
  (aiaos-cli-emacs-integration-get-frames))

;; 模式操作
(defun aiaos-cli-emacs-get-mode ()
  "获取当前模式"
  (aiaos-cli-emacs-integration-get-mode))

;; 命令执行
(defun aiaos-cli-emacs-execute-command (command &rest args)
  "执行命令"
  (aiaos-cli-emacs-integration-execute-command command args))

;; 配置管理
(defun aiaos-cli-emacs-get-config (key default)
  "获取配置"
  (aiaos-cli-emacs-integration-get-config key default))

(defun aiaos-cli-emacs-set-config (key value)
  "设置配置"
  (aiaos-cli-emacs-integration-set-config key value))


;; 性能优化接口
(defun aiaos-cli-emacs-get-perf-stats ()
  "获取性能统计"
  (aiaos-cli-emacs-perf-get-stats))

(defun aiaos-cli-emacs-invalidate-cache ()
  "失效所有缓存"
  (aiaos-cli-emacs-perf-invalidate-all))

;; 安全接口
(defun aiaos-cli-emacs-grant-permission (resource operation &optional expires)
  "授予权限"
  (aiaos-cli-emacs-security-grant-permission resource operation expires))

(defun aiaos-cli-emacs-check-permission (resource operation)
  "检查权限"
  (aiaos-cli-emacs-security-check-permission resource operation))

;;; 停止和清理

(defun aiaos-cli-emacs-shutdown ()
  "关闭Emacs集成"
  (interactive)
  (aiaos-log "info" "Shutting down AIAOS CLI Emacs integration")
  
  ;; 停止自动同步
  (aiaos-cli-emacs-stop-auto-sync)
  
  ;; 清理资源
  (aiaos-cli-emacs-call-cleanup)
  
  (aiaos-log "info" "AIAOS CLI Emacs integration shut down")
  t)

;;; 自动加载

(add-hook 'after-init-hook 'aiaos-cli-emacs-init)


;;; 交互式用户界面命令

(defun aiaos-cli-emacs-show-status ()
  "显示Emacs集成状态"
  (interactive)
  (let ((state (aiaos-cli-emacs-get-current-state)))
    (with-current-buffer (get-buffer-create "*AIAOS-Emacs-Status*")
      (erase-buffer)
      (insert (format "AIAOS CLI Emacs Integration Status\n"))
      (insert (format "====================================\n"))
      (insert (format "Buffers: %d\n" (length (cdr (assoc 'buffers state)))))
      (insert (format "Frames: %d\n" (length (cdr (assoc 'frames state)))))
      (insert (format "Current Buffer: %s\n" (cdr (assoc 'current-buffer state))))
      (insert (format "Auto-sync: %s\n" (if aiaos-cli-emacs-sync-timer "enabled" "disabled")))
      (insert (format "Perf Stats: %s\n" (prin1-to-string (aiaos-cli-emacs-get-perf-stats))))
      (goto-char (point-min)))
    (switch-to-buffer "*AIAOS-Emacs-Status*")))

(defun aiaos-cli-emacs-sync-now ()
  "立即同步Emacs状态"
  (interactive)
  (aiaos-cli-emacs-sync-state)
  (message "AIAOS CLI Emacs state synced"))

(defun aiaos-cli-emacs-toggle-auto-sync ()
  "切换自动同步"
  (interactive)
  (if aiaos-cli-emacs-sync-timer
      (progn
        (aiaos-cli-emacs-stop-auto-sync)
        (message "Auto-sync disabled"))
    (progn
      (aiaos-cli-emacs-start-auto-sync)
      (message "Auto-sync enabled"))))

(defun aiaos-cli-emacs-show-perf ()
  "显示性能统计"
  (interactive)
  (let ((stats (aiaos-cli-emacs-get-perf-stats)))
    (with-current-buffer (get-buffer-create "*AIAOS-Emacs-Perf*")
      (erase-buffer)
      (insert (format "AIAOS CLI Emacs Performance Stats\n"))
      (insert (format "==================================\n"))
      (insert (format "%s\n" (prin1-to-string stats)))
      (goto-char (point-min)))
    (switch-to-buffer "*AIAOS-Emacs-Perf*")))

(defun aiaos-cli-emacs-check-permission-interactive (resource operation)
  "交互式检查权限"
  (interactive "sResource: \nsOperation: ")
  (if (aiaos-cli-emacs-check-permission resource operation)
      (message "Permission GRANTED: %s %s" resource operation)
    (message "Permission DENIED: %s %s" resource operation)))

(provide 'aiaos-cli-emacs)

;;; aiaos-cli-emacs.el 结束