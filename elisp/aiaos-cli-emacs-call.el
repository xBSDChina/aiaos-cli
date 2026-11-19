;;; aiaos-cli-emacs-call.el --- Emacs双向调用层  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: AIAOS CLI与Emacs之间的双向通信机制

(require 'cl-lib)
(require 'aiaos-cli-emacs-controller)
(require 'aiaos-cli-core)

(defgroup aiaos-cli-emacs-call nil
  "AIAOS CLI Emacs调用层"
  :prefix "aiaos-cli-emacs-call-")

;;; 变量定义

(defcustom aiaos-cli-emacs-call-timeout 5000
  "调用超时时间（毫秒）"
  :type 'integer
  :group 'aiaos-cli-emacs-call)

;;; 调用队列

(cl-defstruct aiaos-cli-emacs-call-item
  "调用项"
  (id nil)
  (command nil)
  (args nil)
  (callback nil)
  (timestamp nil)
  (status nil)) ; pending, success, error

(defconst aiaos-cli-emacs-call-queue (make-hash-table :test 'equal))
(defvar aiaos-cli-emacs-call-counter 0
  "调用计数器"
  )

;;; 调用管理

(defun aiaos-cli-emacs-call-id ()
  "生成调用ID"
  (cl-incf aiaos-cli-emacs-call-counter))

(defun aiaos-cli-emacs-call-register (command args callback)
  "注册调用请求"
  (let* ((id (aiaos-cli-emacs-call-id))
        (item (make-aiaos-cli-emacs-call-item
               :id id
               :command command
               :args args
               :callback callback
               :timestamp (current-time)
               :status 'pending)))
    (puthash id item aiaos-cli-emacs-call-queue)
    ;; 直接执行，不通过AIAOS核心转发
    (aiaos-cli-emacs-call-execute id command args callback)
    id))

(defun aiaos-cli-emacs-call-execute (id command args callback)
  "执行调用"
  (condition-case err
      (let ((result (apply command args)))
        (aiaos-cli-emacs-call-handle-result id result nil))
    (error
     (aiaos-cli-emacs-call-handle-result id nil err))))

;;; 结果处理

(defun aiaos-cli-emacs-call-handle-result (id result error)
  "处理调用结果"
  (let ((item (gethash id aiaos-cli-emacs-call-queue)))
    (when item
      (setf (aiaos-cli-emacs-call-item-status item) (if error 'error 'success))
      (when (aiaos-cli-emacs-call-item-callback item)
        (condition-case err
            (funcall (aiaos-cli-emacs-call-item-callback item) result error)
          (error (aiaos-log "error" "Callback failed" err))))
      (remhash id aiaos-cli-emacs-call-queue))))

;;; 同步调用

(defun aiaos-cli-emacs-call-sync (command &rest args)
  "同步调用Emacs命令"
  (let ((result nil)
        (error nil)
        (done nil))
    (aiaos-cli-emacs-call-register
     command args
     (lambda (r e)
       (setq result r)
       (setq error e)
       (setq done t)))
    ;; 等待结果，最多 aiaos-cli-emacs-call-timeout 毫秒
    (let ((deadline (+ (float-time) (/ aiaos-cli-emacs-call-timeout 1000.0))))
      (while (and (not done) (< (float-time) deadline))
        (sit-for 0.01)))
    (unless done
      (aiaos-log "error" "Sync call timed out after %s ms" aiaos-cli-emacs-call-timeout))
    (if error
        (progn
          (aiaos-log "error" "Sync call failed" error)
          nil)
      result)))

;;; 异步调用

(defun aiaos-cli-emacs-call-async (command &rest args)
  "异步调用Emacs命令"
  (aiaos-cli-emacs-call-register command args nil))

;;; 快捷函数

(defun aiaos-cli-emacs-call-get-buffer (name)
  "获取缓冲区"
  (aiaos-cli-emacs-call-sync 'aiaos-cli-emacs-controller-get-buffer name))

(defun aiaos-cli-emacs-call-get-all-buffers ()
  "获取所有缓冲区"
  (aiaos-cli-emacs-call-sync 'aiaos-cli-emacs-controller-get-all-buffers))

(defun aiaos-cli-emacs-call-get-frames ()
  "获取所有帧"
  (aiaos-cli-emacs-call-sync 'aiaos-cli-emacs-controller-get-frames))

(defun aiaos-cli-emacs-call-insert-text (text &optional point)
  "插入文本"
  (aiaos-cli-emacs-call-sync 'aiaos-cli-emacs-controller-insert-text text point))

;;; 清理

(defun aiaos-cli-emacs-call-cleanup ()
  "清理调用层资源"
  (clrhash aiaos-cli-emacs-call-queue)
  (aiaos-log "debug" "Call layer cleaned up"))

(provide 'aiaos-cli-emacs-call)

;;; aiaos-cli-emacs-call.el 结束
