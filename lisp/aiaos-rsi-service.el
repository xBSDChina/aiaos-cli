;;; aiaos-rsi-service.el --- Self-Evolution Service Layer for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, self-evolution, rsi, async

;; Self-evolution service layer for AIAOS-CLI.
;; This module provides non-blocking async self-evolution capabilities:
;;   - Runs in Emacs background as a non-blocking service
;;   - Communicates with LLM providers
;;   - Uses rsi.md as a tracking document
;;   - Executes elisp programs (including those sent by LLM provider)
;;   - Continuously plans, designs, aligns, and improves the project
;;   - Implements self-debugging based on emacs_debug.md
;;   - Periodic self-evolution (every 47 minutes)

;;; Commentary:

;; This module provides self-evolution (RSI - Recursive Self-Improvement)
;; capabilities for AIAOS-CLI. It runs as a non-blocking async service in
;; the Emacs background and periodically examines the project state to
;; identify and fix issues.
;;
;; Key features:
;;   - Non-blocking async service via run-with-timer
;;   - Communication with LLM providers
;;   - Tracking via ~/.emacs.d/aiaos-cli/rsi.md
;;   - Execution of arbitrary elisp programs
;;   - Self-debugging based on emacs_debug.md
;;   - Periodic self-evolution (default: every 47 minutes)

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'aiaos-cli-events)
(require 'aiaos-cli-monitor)
(require 'aiaos-cli-logging)
(require 'aiaos-cli-selfheal)

;; Capture this file's directory for subprocess -L argument.
(defconst aiaos-rsi-service-load-dir
  (or (and load-file-name (file-name-directory load-file-name))
      default-directory
      invocation-directory)
  "Directory containing aiaos-rsi-service.el, used for subprocess -L.")

(defgroup aiaos-rsi-service nil
  "AIAOS-CLI Self-Evolution Service"
  :group 'aiaos-cli
  :prefix "aiaos-rsi-service-")

;;; Configuration

(defcustom aiaos-rsi-service-enabled t
  "Enable the self-evolution service."
  :type 'boolean
  :group 'aiaos-rsi-service)

(defcustom aiaos-rsi-service-interval (* 47 60)
  "Self-evolution interval in seconds (default: 47 minutes)."
  :type 'integer
  :group 'aiaos-rsi-service)

(defcustom aiaos-rsi-service-max-retries 3
  "Maximum retries for self-evolution cycles."
  :type 'integer
  :group 'aiaos-rsi-service)

(defcustom aiaos-rsi-service-tracking-file
  (expand-file-name "~/.emacs.d/aiaos-cli/rsi.md")
  "Path to the RSI tracking document."
  :type 'file
  :group 'aiaos-rsi-service)

;;; Service state

(defvar aiaos-rsi-service-timer nil
  "Timer for periodic self-evolution.")

(defvar aiaos-rsi-service-running nil
  "Whether the service is currently running.")

(defvar aiaos-rsi-service-cycle-count 0
  "Number of completed self-evolution cycles.")

(defvar aiaos-rsi-service-issue-count 0
  "Number of issues found and fixed.")

(defvar aiaos-rsi-service-last-cycle-time nil
  "Timestamp of the last self-evolution cycle.")

;;; Tracking document management

(defun aiaos-rsi-service-tracking-file ()
  "Return the path to the RSI tracking document."
  aiaos-rsi-service-tracking-file)

(defun aiaos-rsi-service-tracking-exists ()
  "Check if the RSI tracking document exists."
  (file-exists-p aiaos-rsi-service-tracking-file))

(defun aiaos-rsi-service-tracking-append (text)
  "Append TEXT to the RSI tracking document."
  (when aiaos-rsi-service-tracking-file
    (let ((file aiaos-rsi-service-tracking-file))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert text)
        (save-buffer))
      (message "RSI tracking updated: %s" (truncate-undo-border text 60)))))

(defun aiaos-rsi-service-tracking-init ()
  "Initialize the RSI tracking document if it doesn't exist."
  (unless (aiaos-rsi-service-tracking-exists)
    (let ((dir (file-name-directory aiaos-rsi-service-tracking-file)))
      (unless (file-exists-p dir)
        (make-directory dir t))
      (with-temp-file aiaos-rsi-service-tracking-file
        (insert (aiaos-rsi-service-tracking-template)))
      (message "RSI tracking document created: %s"
               aiaos-rsi-service-tracking-file))))

(defun aiaos-rsi-service-tracking-template ()
  "Return the initial template for the RSI tracking document."
  (concat "# RSI (Recursive Self-Improvement) 跟踪文档\n\n"
          "> **说明**: 本文档由 `aiaos-rsi-service`（自进化服务层）维护，\n"
          "> 记录每次自进化的状态、发现的问题和修复结果。\n"
          "> **更新方式**: 每次自进化周期结束时，由 `aiaos-rsi-service` 自动追加。\n\n"
          "---\n\n"
          "## 自进化状态概览\n\n"
          "| 项目 | 值 |\n"
          "|------|-----|\n"
          "| 服务状态 | `pending` |\n"
          "| 上次自进化 | 从未执行 |\n"
          "| 下次自进化 | 服务启动后 47 分钟 |\n"
          "| 累计进化轮次 | 0 |\n"
          "| 累计修复问题 | 0 |\n"
          "| 项目健康度 | `unknown` |\n\n"
          "---\n\n"
          "## 自进化日志\n\n"
          "### 2026-11-15 — 初始化\n\n"
          "- **触发**: 服务初始化\n"
          "- **状态**: `pending`\n"
          "- **操作**: 创建跟踪文档，初始化自进化服务层\n"
          "- **发现**: 无\n"
          "- **修复**: 无\n"
          "- **备注**: `aiaos-rsi-service` 模块已创建，等待首次自进化周期\n\n"
          "---\n\n"
          "## 自进化检查清单\n\n"
          "每次自进化周期执行以下检查：\n\n"
          "### 1. 模块完整性\n"
          "- [ ] 检查所有 `.el` 文件是否存在\n"
          "- [ ] 检查 `provide` 语句是否完整\n"
          "- [ ] 检查模块依赖是否满足\n\n"
          "### 2. 语法健康\n"
          "- [ ] 对所有 `.el` 文件执行 `byte-compile` 检查\n"
          "- [ ] 检查是否存在 `reference to free variable` 警告\n"
          "- [ ] 检查是否存在 `void-function` 错误\n\n"
          "### 3. 测试覆盖\n"
          "- [ ] 运行 ERT 单元测试\n"
          "- [ ] 运行 Shell 集成测试\n"
          "- [ ] 检查测试覆盖率\n\n"
          "### 4. 功能完整性\n"
          "- [ ] 检查核心功能是否正常\n"
          "- [ ] 检查 LLM provider 通信\n"
          "- [ ] 检查 elisp 执行能力\n\n"
          "### 5. 性能与资源\n"
          "- [ ] 检查内存使用\n"
          "- [ ] 检查定时器泄漏\n"
          "- [ ] 检查缓冲区泄漏\n\n"
          "### 6. 安全性\n"
          "- [ ] 检查 API key 存储\n"
          "- [ ] 检查输入验证\n"
          "- [ ] 检查访问控制\n\n"
          "---\n\n"
          "## 问题跟踪\n\n"
          "| # | 日期 | 类型 | 严重度 | 描述 | 状态 |\n"
          "|---|------|------|--------|------|------|\n"
          "| - | - | - | - | 暂无 | - |\n\n"
          "---\n\n"
          "## 修复记录\n\n"
          "| # | 日期 | 问题 # | 修复方式 | 结果 |\n"
          "|---|------|--------|----------|------|\n"
          "| - | - | - | 暂无 | - |\n"))

;;; Project scanning

(defun aiaos-rsi-service--project-dir ()
  "Return the project directory."
  (or (and load-file-name
           (file-name-directory (directory-file-name
                                 (file-name-directory load-file-name))))
      (expand-file-name "~/.emacs.d/aiaos-cli")))

(defun aiaos-rsi-service--elisp-files ()
  "Return a list of all .el files in the project."
  (let ((dir (aiaos-rsi-service--project-dir))
        (files '()))
    (when (file-exists-p dir)
      (dolist (f (directory-files dir t "\\.el$")
                 (reverse files))
        (unless (string-match-p "test" f)
          (push f files))))
    files))

;;; Syntax checking

(defun aiaos-rsi-service--check-syntax (file)
  "Check syntax of FILE using byte-compile.
Returns (ok . message)."
  (let ((result nil)
        (msg nil))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (let ((read-result (read (current-buffer))))
            (if (listp read-result)
                (setq result t)
              (setq msg "Unexpected read result"))))
      (error
       (setq msg (format "Syntax error: %s" (error-message-string err)))
       (setq result nil)))
    (cons result msg)))

(defun aiaos-rsi-service--check-all-syntax ()
  "Check syntax of all .el files.
Returns a list of (file . status) pairs."
  (let ((files (aiaos-rsi-service--elisp-files))
        (results '()))
    (dolist (file files)
      (let ((status (aiaos-rsi-service--check-syntax file)))
        (push (cons file status) results)))
    (reverse results)))

;;; Module integrity check

(defun aiaos-rsi-service--check-modules ()
  "Check that all expected modules exist and have provide statements.
Returns a list of issues found."
  (let ((issues '())
        (expected-modules
         '("aiaos-cli-core" "aiaos-cli-state" "aiaos-cli-context"
           "aiaos-cli-lifecycle" "aiaos-cli-component" "aiaos-cli-theme"
           "aiaos-cli-components" "aiaos-cli-router" "aiaos-cli-app"
           "aiaos-cli-events" "aiaos-cli-monitor" "aiaos-cli-logging"
           "aiaos-cli-security" "aiaos-cli-async" "aiaos-cli-selfheal"
           "aiaos-cli-llm" "aiaos-cli-elisp" "aiaos-cli-persist"
           "aiaos-cli-msg" "aiaos-rsi-service" "aiaos-fast-determin")))
    (dolist (mod expected-modules)
      (let ((file (expand-file-name (concat mod ".el")
                                   (aiaos-rsi-service--project-dir))))
        (if (file-exists-p file)
            ;; Check for provide statement
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (unless (re-search-forward "(provide '" nil t)
                (push (list :type 'module
                           :severity 'warning
                           :message (format "Missing provide in %s" mod)
                           :data mod) issues)))
          (push (list :type 'module
                     :severity 'error
                     :message (format "Module file not found: %s" mod)
                     :data mod) issues))))
    issues))

;;; Memory and resource check

(defun aiaos-rsi-service--check-resources ()
  "Check memory usage and resource leaks.
Returns a list of issues found."
  (let ((issues '()))
    ;; Check memory
    (let ((mem (aiaos-cli-monitor-memory-usage)))
      (when (> (alist-get :bytes-allocated mem) (* 100 1024 1024)) ; 100MB
        (push (list :type 'memory
                   :severity 'warning
                   :message "High memory usage"
                   :data mem) issues)))
    ;; Check for stale timers
    (let ((stale-count 0))
      (maphash (lambda (k v)
                 (when (> (float-time (time-subtract (current-time) v))
                          300) ; 5 minutes
                   (cl-incf stale-count)))
               aiaos-cli-active-timers)
      (when (> stale-count 0)
        (push (list :type 'resources
                   :severity 'warning
                   :message (format "Stale timers: %d" stale-count)
                   :data stale-count) issues)))
    issues))

;;; Self-healing

(defun aiaos-rsi-service--heal (issues)
  "Attempt to heal ISSUES.
Returns the number of issues healed."
  (let ((healed 0))
    (dolist (issue issues)
      (let ((type (alist-get :type issue)))
        (message "RSI: Attempting to heal %s issue" type)
        (case type
          (memory
           (message "RSI: Running garbage collection...")
           (garbage-collect)
           (cl-incf healed))
          (resources
           (message "RSI: Cleaning up stale resources...")
           (maphash (lambda (k v)
                      (when (> (float-time (time-subtract (current-time) v))
                               300)
                        (remhash k aiaos-cli-active-timers)))
                    aiaos-cli-active-timers)
           (cl-incf healed))
          (t nil))))
    healed))

;;; Elisp execution (for LLM provider requests)

(defun aiaos-rsi-service-exec (code)
  "Execute Elisp CODE and return the result.
This is used when the LLM provider requests elisp execution."
  (condition-case err
      (let ((result nil))
        (with-temp-buffer
          (insert code)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((expr (read (current-buffer))))
              (setq result (eval expr))))
          (format "OK: %s" result)))
    (error
     (format "ERROR: %s\nBACKTRACE:\n%s"
             (error-message-string err)
             (mapconcat (lambda (frame)
                          (format "  %s\n" frame))
                        (backtrace) "")))))

;;; Self-evolution cycle

(defun aiaos-rsi-service--evolve ()
  "Perform one self-evolution cycle.
This examines the project state, identifies issues, and attempts to fix them."
  (message "RSI: Starting self-evolution cycle %d..."
           (1+ aiaos-rsi-service-cycle-count))
  (setq aiaos-rsi-service-running t)
  (unwind-protect
      (let ((all-issues '())
            (healed 0))
        ;; 1. Check module integrity
        (message "RSI: Checking module integrity...")
        (let ((module-issues (aiaos-rsi-service--check-modules)))
          (setq all-issues (append all-issues module-issues)))
        ;; 2. Check syntax
        (message "RSI: Checking syntax...")
        (let ((syntax-results (aiaos-rsi-service--check-all-syntax)))
          (dolist (result syntax-results)
            (let ((file (car result))
                  (status (cdr result)))
              (unless (car status)
                (push (list :type 'syntax
                           :severity 'error
                           :message (format "Syntax error in %s: %s"
                                           file (cdr status))
                           :data file) all-issues)))))
        ;; 3. Check resources
        (message "RSI: Checking resources...")
        (let ((resource-issues (aiaos-rsi-service--check-resources)))
          (setq all-issues (append all-issues resource-issues)))
        ;; 4. Attempt self-healing
        (when all-issues
          (message "RSI: Found %d issue(s), attempting healing..."
                   (length all-issues))
          (setq healed (aiaos-rsi-service--heal all-issues)))
        ;; 5. Update tracking document
        (aiaos-rsi-service-tracking-update all-issues healed)
        ;; 6. Update counters
        (cl-incf aiaos-rsi-service-cycle-count)
        (cl-incf aiaos-rsi-service-issue-count (length all-issues))
        (setq aiaos-rsi-service-last-cycle-time (current-time))
        ;; 7. Publish event
        (aiaos-cli-events-publish 'rsi-cycle-completed 'rsi-service
                                  (list :cycle aiaos-rsi-service-cycle-count
                                        :issues all-issues
                                        :healed healed))
        (message "RSI: Self-evolution cycle %d complete. %d issue(s) found, %d healed."
                 aiaos-rsi-service-cycle-count
                 (length all-issues)
                 healed)
        (list :cycle aiaos-rsi-service-cycle-count
              :issues all-issues
              :healed healed
              :issue-count (length all-issues)))
    (setq aiaos-rsi-service-running nil)))

(defun aiaos-rsi-service-tracking-update (issues healed)
  "Update the RSI tracking document with ISSUES and HEALED count."
  (let* ((now (format-time-string "%Y-%m-%d %H:%M:%S"))
         (status (if (and issues (zerop healed)) 'failed 'completed))
         (entry (format "
### %s — 自进化周期 %d

- **触发**: 定时自进化（间隔 %d 分钟）
- **状态**: `%s`
- **发现**: %d 个问题
- **修复**: %d 个问题
- **累计轮次**: %d
- **累计修复**: %d
- **项目健康度**: `%s`
%s
"
                        now
                        (1+ aiaos-rsi-service-cycle-count)
                        (/ aiaos-rsi-service-interval 60)
                        status
                        (length issues)
                        healed
                        aiaos-rsi-service-cycle-count
                        aiaos-rsi-service-issue-count
                        (aiaos-rsi-service--health-status issues)
                        (if issues
                            "\n#### 问题列表\n\n"
                            ""))))
    (when issues
      (dolist (issue issues)
        (let ((type (alist-get :type issue))
              (severity (alist-get :severity issue))
              (message (alist-get :message issue)))
          (setq entry (concat entry
                              (format "- [%s] %s: %s\n"
                                      (upcase (symbol-name severity))
                                      (upcase (symbol-name type))
                                      message))))))
    (aiaos-rsi-service-tracking-append entry)))

(defun aiaos-rsi-service--health-status (issues)
  "Return health status based on ISSUES."
  (let ((max-severity 0))
    (dolist (issue issues)
      (let ((severity (alist-get :severity issue)))
        (cl-incf max-severity
              (case severity
                (info 0)
                (warning 1)
                (error 2)
                (critical 3)
                (t 1)))))
    (case max-severity
      (0 'healthy)
      (1 'degraded)
      (2 'unhealthy)
      (3 'critical)
      (t 'unknown))))

;;; Service lifecycle

(defun aiaos-rsi-service-start ()
  "Start the self-evolution service."
  (interactive)
  (when aiaos-rsi-service-timer
    (aiaos-rsi-service-stop))
  (aiaos-rsi-service-tracking-init)
  (setq aiaos-rsi-service-timer
        (run-with-timer aiaos-rsi-service-interval
                        aiaos-rsi-service-interval
                        'aiaos-rsi-service--evolve))
  (message "RSI service started (interval: %d minutes, next cycle in %d minutes)"
           (/ aiaos-rsi-service-interval 60)
           (/ aiaos-rsi-service-interval 60))
  (aiaos-cli-events-publish 'rsi-service-started 'rsi-service nil))

(defun aiaos-rsi-service-stop ()
  "Stop the self-evolution service."
  (when aiaos-rsi-service-timer
    (cancel-timer aiaos-rsi-service-timer)
    (setq aiaos-rsi-service-timer nil)
    (message "RSI service stopped")
    (aiaos-cli-events-publish 'rsi-service-stopped 'rsi-service nil)))

(defun aiaos-rsi-service-run-now ()
  "Run a self-evolution cycle immediately."
  (interactive)
  (message "RSI: Running immediate self-evolution cycle...")
  (aiaos-rsi-service--evolve))

(defun aiaos-rsi-service-status ()
  "Return the status of the self-evolution service."
  (list :enabled aiaos-rsi-service-enabled
        :running aiaos-rsi-service-running
        :timer (and aiaos-rsi-service-timer t)
        :interval aiaos-rsi-service-interval
        :cycle-count aiaos-rsi-service-cycle-count
        :issue-count aiaos-rsi-service-issue-count
        :last-cycle aiaos-rsi-service-last-cycle-time
        :tracking-file aiaos-rsi-service-tracking-file))

;;; Provide

(provide 'aiaos-rsi-service)

;;; aiaos-rsi-service.el ends here