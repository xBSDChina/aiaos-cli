;;; aiaos-cli-emacs-performance.el --- Emacs性能优化层  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 提供Emacs操作的性能优化，包括缓存、批量操作、异步执行

(require 'aiaos-cli-core)
(require 'cl-lib)
(require 'aiaos-cli-emacs-adapter)

(defgroup aiaos-cli-emacs-performance nil
  "AIAOS CLI Emacs性能优化"
  :prefix "aiaos-cli-emacs-performance-"
  :group 'aiaos-cli-emacs)

;;; 配置

(defcustom aiaos-cli-emacs-performance-cache-ttl 300
  "缓存生存时间（秒）"
  :type 'integer
  :group 'aiaos-cli-emacs-performance)

(defcustom aiaos-cli-emacs-performance-batch-size 50
  "批量操作大小"
  :type 'integer
  :group 'aiaos-cli-emacs-performance)

(defcustom aiaos-cli-emacs-performance-async-enabled t
  "是否启用异步执行"
  :type 'boolean
  :group 'aiaos-cli-emacs-performance)

;;; 缓存实现

(cl-defstruct aiaos-cli-emacs-perf-cache
  "性能缓存结构"
  (data nil)
  (timestamp nil)
  (ttl nil))

(defun aiaos-cli-emacs-perf-cache-create (ttl)
  "创建缓存"
  (make-aiaos-cli-emacs-perf-cache
   :data (make-hash-table :test 'equal)
   :timestamp (current-time)
   :ttl (or ttl aiaos-cli-emacs-performance-cache-ttl)))

(defun aiaos-cli-emacs-perf-cache-get (cache key)
  "从缓存获取值"
  (let ((entry (gethash key (aiaos-cli-emacs-perf-cache-data cache))))
    (when entry
      (if (aiaos-cli-emacs-perf-cache-valid-p cache)
          (cdr entry)
        (remhash key (aiaos-cli-emacs-perf-cache-data cache))
        nil))))

(defun aiaos-cli-emacs-perf-cache-set (cache key value)
  "设置缓存值"
  (puthash key (cons (current-time) value)
           (aiaos-cli-emacs-perf-cache-data cache)))

(defun aiaos-cli-emacs-perf-cache-valid-p (cache)
  "检查缓存是否有效"
  (let ((elapsed (time-convert (time-subtract (current-time)
                                            (aiaos-cli-emacs-perf-cache-timestamp cache))
                               'integer)))
    (< elapsed (aiaos-cli-emacs-perf-cache-ttl cache))))

;;; 全局缓存实例

(defconst aiaos-cli-emacs-perf-buffer-cache 
  (aiaos-cli-emacs-perf-cache-create aiaos-cli-emacs-performance-cache-ttl))

(defconst aiaos-cli-emacs-perf-window-cache
  (aiaos-cli-emacs-perf-cache-create aiaos-cli-emacs-performance-cache-ttl))

(defconst aiaos-cli-emacs-perf-frame-cache
  (aiaos-cli-emacs-perf-cache-create aiaos-cli-emacs-performance-cache-ttl))

;;; 缓存的适配层函数

(defun aiaos-cli-emacs-perf-get-all-buffers ()
  "获取所有缓冲区（带缓存）"
  (let ((cached (aiaos-cli-emacs-perf-cache-get 
                 aiaos-cli-emacs-perf-buffer-cache "all")))
    (if cached
        cached
      (let ((result (aiaos-cli-emacs-adapter-get-all-buffers)))
        (aiaos-cli-emacs-perf-cache-set 
         aiaos-cli-emacs-perf-buffer-cache "all" result)
        result))))

(defun aiaos-cli-emacs-perf-get-all-frames ()
  "获取所有帧（带缓存）"
  (let ((cached (aiaos-cli-emacs-perf-cache-get 
                 aiaos-cli-emacs-perf-frame-cache "all")))
    (if cached
        cached
      (let ((result (aiaos-cli-emacs-adapter-get-frames)))
        (aiaos-cli-emacs-perf-cache-set 
         aiaos-cli-emacs-perf-frame-cache "all" result)
        result))))

;;; 缓存失效

(defun aiaos-cli-emacs-perf-invalidate-buffer-cache ()
  "失效缓冲区缓存"
  (remhash "all" (aiaos-cli-emacs-perf-cache-data aiaos-cli-emacs-perf-buffer-cache)))

(defun aiaos-cli-emacs-perf-invalidate-frame-cache ()
  "失效帧缓存"
  (remhash "all" (aiaos-cli-emacs-perf-cache-data aiaos-cli-emacs-perf-frame-cache)))

(defun aiaos-cli-emacs-perf-invalidate-all ()
  "失效所有缓存"
  (aiaos-cli-emacs-perf-invalidate-buffer-cache)
  (aiaos-cli-emacs-perf-invalidate-frame-cache)
  (clrhash (aiaos-cli-emacs-perf-cache-data aiaos-cli-emacs-perf-window-cache)))

;;; 批量操作

(defun aiaos-cli-emacs-perf-batch-execute (commands)
  "批量执行命令"
  (let ((results nil))
    (dolist (cmd commands)
      (condition-case err
          (let ((result (apply (car cmd) (cdr cmd))))
            (push result results))
        (error (aiaos-log "error" "Batch command failed" err)
               (push nil results))))
    (nreverse results)))

;;; 异步执行

(defun aiaos-cli-emacs-perf-async-execute (command &rest args)
  "异步执行命令"
  (if aiaos-cli-emacs-performance-async-enabled
      (apply 'async-shell-command 
             (format "%s %s" command (mapconcat 'identity args " "))
             nil nil)
    (apply command args)))

;;; 性能统计

(cl-defstruct aiaos-cli-emacs-perf-stats
  "性能统计"
  (call-count 0)
  (total-time 0)
  (avg-time 0)
  (max-time 0)
  (min-time most-positive-fixnum))

(defconst aiaos-cli-emacs-perf-stats (make-aiaos-cli-emacs-perf-stats))

(defun aiaos-cli-emacs-perf-record (duration)
  "记录性能数据"
  (let ((stats aiaos-cli-emacs-perf-stats))
    (setf (aiaos-cli-emacs-perf-stats-call-count stats)
          (1+ (aiaos-cli-emacs-perf-stats-call-count stats)))
    (setf (aiaos-cli-emacs-perf-stats-total-time stats)
          (+ (aiaos-cli-emacs-perf-stats-total-time stats) duration))
    (setf (aiaos-cli-emacs-perf-stats-avg-time stats)
          (/ (aiaos-cli-emacs-perf-stats-total-time stats)
             (aiaos-cli-emacs-perf-stats-call-count stats)))
    (when (> duration (aiaos-cli-emacs-perf-stats-max-time stats))
      (setf (aiaos-cli-emacs-perf-stats-max-time stats) duration))
    (when (< duration (aiaos-cli-emacs-perf-stats-min-time stats))
      (setf (aiaos-cli-emacs-perf-stats-min-time stats) duration))))

(defun aiaos-cli-emacs-perf-get-stats ()
  "获取性能统计"
  (let ((stats aiaos-cli-emacs-perf-stats))
    `((call-count . ,(aiaos-cli-emacs-perf-stats-call-count stats))
      (total-time . ,(aiaos-cli-emacs-perf-stats-total-time stats))
      (avg-time . ,(aiaos-cli-emacs-perf-stats-avg-time stats))
      (max-time . ,(aiaos-cli-emacs-perf-stats-max-time stats))
      (min-time . ,(aiaos-cli-emacs-perf-stats-min-time stats)))))

;;; 包装函数（带性能监控）

(defmacro aiaos-cli-emacs-perf-monitor (body)
  "性能监控宏"
  (let ((start-time (gensym))
        (duration (gensym)))
    `(let ((,start-time (current-time)))
       (prog1 ,body
         (let ((,duration (time-convert (time-subtract (current-time) ,start-time) 'integer)))
           (aiaos-cli-emacs-perf-record ,duration))))))

(provide 'aiaos-cli-emacs-performance)

;;; aiaos-cli-emacs-performance.el 结束