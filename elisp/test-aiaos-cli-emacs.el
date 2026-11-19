;;; test-aiaos-cli-emacs.el --- AIAOS CLI Emacs集成测试  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 描述: 测试Emacs适配层、管控层、回调层、调用层、集成层

(require 'aiaos-cli-emacs)
(require 'cl-lib)

;;; 测试辅助函数

(defconst aiaos-cli-emacs-test-results nil)

(defun aiaos-cli-emacs-test-record (name result)
  "记录测试结果"
  (push (cons name result) aiaos-cli-emacs-test-results)
  (aiaos-log (if result "info" "error") 
             (format "Test %s: %s" name (if result "PASS" "FAIL"))))

;;; 测试1: 适配层测试

(defun aiaos-cli-emacs-test-adapter ()
  "测试适配层"
  (aiaos-log "info" "Running adapter tests")
  
  ;; 测试获取缓冲区信息
  (let ((buf-info (aiaos-cli-emacs-adapter-get-buffer (buffer-name))))
    (aiaos-cli-emacs-test-record "adapter-get-buffer" 
                                 (and buf-info (assoc 'name buf-info))))
  
  ;; 测试获取所有缓冲区
  (let ((all-bufs (aiaos-cli-emacs-adapter-get-all-buffers)))
    (aiaos-cli-emacs-test-record "adapter-get-all-buffers" 
                                 (and all-bufs (> (length all-bufs) 0))))
  
  ;; 测试获取帧信息
  (let ((frame-info (aiaos-cli-emacs-adapter-get-frames)))
    (aiaos-cli-emacs-test-record "adapter-get-frames" 
                                 (and frame-info (> (length frame-info) 0)))))

;;; 测试2: 管控层测试

(defun aiaos-cli-emacs-test-controller ()
  "测试管控层"
  (aiaos-log "info" "Running controller tests")
  
  ;; 测试创建缓冲区
  (let ((buf (aiaos-cli-emacs-controller-create-buffer "*test-aiaos*" 'text-mode)))
    (aiaos-cli-emacs-test-record "controller-create-buffer" 
                                 (and buf (assoc 'name buf))))
  
  ;; 测试获取缓冲区
  (let ((buf (aiaos-cli-emacs-controller-get-buffer "*test-aiaos*")))
    (aiaos-cli-emacs-test-record "controller-get-buffer" buf))
  
  ;; 测试执行命令
  (let ((result (aiaos-cli-emacs-controller-execute-command 'message "test")))
    (aiaos-cli-emacs-test-record "controller-execute-command" t)))

;;; 测试3: 回调层测试

(defun aiaos-cli-emacs-test-callback ()
  "测试回调层"
  (aiaos-log "info" "Running callback tests")
  
  ;; 测试注册事件
  (let ((registered (aiaos-cli-emacs-callback-register 
                     'test-event 'ignore)))
    (aiaos-cli-emacs-test-record "callback-register" registered))
  
  ;; 测试触发事件
  (let ((triggered nil))
    (aiaos-cli-emacs-callback-register 
     'test-event-2 
     (lambda (&rest args) (setq triggered t)))
    (aiaos-cli-emacs-callback-trigger 'test-event-2)
    (aiaos-cli-emacs-test-record "callback-trigger" triggered)))

;;; 测试4: 调用层测试

(defun aiaos-cli-emacs-test-call ()
  "测试调用层"
  (aiaos-log "info" "Running call tests")
  
  ;; 测试同步调用
  (let ((result (aiaos-cli-emacs-call-sync 'message "sync test")))
    (aiaos-cli-emacs-test-record "call-sync" t))
  
  ;; 测试异步调用
  (let ((result (aiaos-cli-emacs-call-async 'message "async test")))
    (aiaos-cli-emacs-test-record "call-async" t)))

;;; 测试5: 集成层测试

(defun aiaos-cli-emacs-test-integration ()
  "测试集成层"
  (aiaos-log "info" "Running integration tests")
  
  ;; 测试获取所有缓冲区
  (let ((bufs (aiaos-cli-emacs-integration-get-all-buffers)))
    (aiaos-cli-emacs-test-record "integration-get-all-buffers" 
                                 (and bufs (> (length bufs) 0))))
  
  ;; 测试获取模式
  (let ((mode (aiaos-cli-emacs-integration-get-mode)))
    (aiaos-cli-emacs-test-record "integration-get-mode" mode))
  
  ;; 测试执行命令
  (let ((result (aiaos-cli-emacs-integration-execute-command 'message "test")))
    (aiaos-cli-emacs-test-record "integration-execute-command" t)))

;;; 测试6: 性能优化层测试

(defun aiaos-cli-emacs-test-performance ()
  "测试性能优化层"
  (aiaos-log "info" "Running performance tests")
  
  ;; 测试缓存功能
  (let ((cached (aiaos-cli-emacs-perf-get-all-buffers)))
    (aiaos-cli-emacs-test-record "perf-cache" 
                                 (and cached (> (length cached) 0))))
  
  ;; 测试性能统计
  (let ((stats (aiaos-cli-emacs-perf-get-stats)))
    (aiaos-cli-emacs-test-record "perf-stats" 
                                 (and stats (assoc 'call-count stats)))))

;;; 测试7: 安全机制层测试

(defun aiaos-cli-emacs-test-security ()
  "测试安全机制层"
  (aiaos-log "info" "Running security tests")
  
  ;; 测试授予权限
  (let ((granted (aiaos-cli-emacs-security-grant-permission 
                  'test-resource 'read)))
    (aiaos-cli-emacs-test-record "security-grant" granted))
  
  ;; 测试检查权限
  (let ((has-perm (aiaos-cli-emacs-security-check-permission 
                   'test-resource 'read)))
    (aiaos-cli-emacs-test-record "security-check" has-perm))
  
  ;; 测试输入验证
  (let ((valid (aiaos-cli-emacs-security-validate-buffer-name "test")))
    (aiaos-cli-emacs-test-record "security-validate" valid)))

;;; 测试8: 主加载文件测试

(defun aiaos-cli-emacs-test-main ()
  "测试主加载文件"
  (aiaos-log "info" "Running main tests")
  
  ;; 测试初始化
  (let ((initialized (aiaos-cli-emacs-init)))
    (aiaos-cli-emacs-test-record "main-init" initialized))
  
  ;; 测试获取状态
  (let ((state (aiaos-cli-emacs-get-current-state)))
    (aiaos-cli-emacs-test-record "main-get-state" 
                                 (and state (assoc 'buffers state)))))
  
  ;; 测试获取性能统计
  (let ((stats (aiaos-cli-emacs-get-perf-stats)))
    (aiaos-cli-emacs-test-record "main-perf-stats" stats))

;;; 测试9: 交互命令测试

(defun aiaos-cli-emacs-test-interactive ()
  "测试交互式命令"
  (aiaos-log "info" "Running interactive command tests")
  
  ;; 测试 show-status 生成缓冲区
  (let ((buf (get-buffer-create "*AIAOS-Emacs-Status*")))
    (aiaos-cli-emacs-test-record "interactive-show-status-buffer" 
                                 (and buf (buffer-name buf))))
  
  ;; 测试 sync-now 不报错
  (let ((ok (condition-case err
                (progn (aiaos-cli-emacs-sync-now) t)
              (error nil))))
    (aiaos-cli-emacs-test-record "interactive-sync-now" ok))
  
  ;; 测试 toggle-auto-sync
  (let ((ok (condition-case err
                (progn (aiaos-cli-emacs-toggle-auto-sync) t)
              (error nil))))
    (aiaos-cli-emacs-test-record "interactive-toggle-auto-sync" ok))
  
  ;; 测试 show-perf 生成缓冲区
  (let ((buf (get-buffer-create "*AIAOS-Emacs-Perf*")))
    (aiaos-cli-emacs-test-record "interactive-show-perf-buffer" 
                                 (and buf (buffer-name buf))))
  
  ;; 测试 check-permission-interactive
  (let ((ok (condition-case err
                (progn 
                  (aiaos-cli-emacs-security-grant-permission 'test-resource '(read))
                  (aiaos-cli-emacs-check-permission 'test-resource 'read))
              (error nil))))
    (aiaos-cli-emacs-test-record "interactive-check-permission" ok)))

;;; 运行所有测试

(defun aiaos-cli-emacs-run-all-tests ()
  "运行所有测试"
  (interactive)
  (setq aiaos-cli-emacs-test-results nil)
  
  (aiaos-log "info" "Running all AIAOS CLI Emacs tests")
  
  (condition-case err
      (progn
        (aiaos-cli-emacs-test-adapter)
        (aiaos-cli-emacs-test-controller)
        (aiaos-cli-emacs-test-callback)
        (aiaos-cli-emacs-test-call)
        (aiaos-cli-emacs-test-integration)
        (aiaos-cli-emacs-test-performance)
        (aiaos-cli-emacs-test-security)
        (aiaos-cli-emacs-test-main)
        (aiaos-cli-emacs-test-interactive))
    (error (aiaos-log "error" "Test suite failed" err)))
  
  ;; 输出结果
  (aiaos-cli-emacs-print-test-results))

(defun aiaos-cli-emacs-print-test-results ()
  "打印测试结果"
  (let ((passed 0)
        (failed 0))
    (dolist (result aiaos-cli-emacs-test-results)
      (if (cdr result)
          (cl-incf passed)
        (cl-incf failed))
      (message "Test %s: %s" (car result) (if (cdr result) "PASS" "FAIL")))
    
    (message "\n=== Test Results ===")
    (message "Total: %d, Passed: %d, Failed: %d" 
             (+ passed failed) passed failed)
    
    (when (> failed 0)
      (error "Some tests failed"))))

(aiaos-cli-emacs-test-main)

(provide 'test-aiaos-cli-emacs)

;;; test-aiaos-cli-emacs.el 结束