;;; aiaos-fast-determin.el --- Fast Determination Module for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, fast-determin, simulation, intent

;; Fast determination module for AIAOS-CLI.
;; This module provides fast judgment and simulation capabilities:
;;   - Quick judgment of user intent based on interaction history
;;   - Simulation of LLM provider behavior
;;   - Forward-looking simulation judgment
;;   - Based on interaction history and task progress
;;   - Provides fast judgment and simulation guidance for LLM provider

;;; Commentary:

;; This module provides fast determination (快速判断) capabilities for
;; AIAOS-CLI. It uses Elisp to build judgment and simulation mechanisms
;; that perform forward-looking simulation judgment on user intent and
;; LLM provider behavior, enabling better decision-making.
;;
;; Key features:
;;   - Fast intent classification from user input
;;   - Pattern-based task type detection
;;   - Provider performance simulation
;;   - Task progress prediction
;;   - Route suggestions based on historical patterns

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'aiaos-cli-events)
(require 'aiaos-cli-monitor)
(require 'aiaos-cli-logging)

(defgroup aiaos-fast-determin nil
  "AIAOS-CLI Fast Determination"
  :group 'aiaos-cli
  :prefix "aiaos-fast-determin-")

;;; Configuration

(defcustom aiaos-fast-determin-enabled t
  "Enable the fast determination module."
  :type 'boolean
  :group 'aiaos-fast-determin)

(defcustom aiaos-fast-determin-max-history 100
  "Maximum number of interaction history entries to retain."
  :type 'integer
  :group 'aiaos-fast-determin)

(defcustom aiaos-fast-determin-similarity-threshold 0.6
  "Similarity threshold (0.0-1.0) for pattern matching."
  :type 'float
  :group 'aiaos-fast-determin)

;;; Intent classification

(defconst aiaos-fast-determin-intent-keywords
  '((code-programming . ("代码" "函数" "类" "方法" "实现" "编写" "编程" "script" "program"))
    (config-system . ("配置" "设置" "参数" "选项" "环境变量" "config" "setup"))
    (debug-troubleshoot . ("调试" "错误" "问题" "修复" "bug" "error" "fix" "debug"))
    (documentation . ("文档" "说明" "注释" "readme" "docs" "documentation"))
    (file-operation . ("文件" "目录" "读取" "写入" "删除" "移动" "复制" "file" "dir"))
    (search-query . ("搜索" "查找" "搜索" "grep" "find" "search"))
    (skill-management . ("技能" "加载" "卸载" "列表" "skill" "load" "list"))
    (session-management . ("会话" "保存" "加载" "删除" "列表" "session" "save" "load"))
    (provider-management . ("provider" "模型" "端点" "密钥" "切换" "fallback"))
    (system-status . ("状态" "健康" "监控" "指标" "内存" "性能" "status" "health"))
    (help-info . ("帮助" "如何" "怎么" "什么是" "help" "how" "what")))
  "Intent keyword mapping: (intent-type . keyword-list).")

(defconst aiaos-fast-determin-intent-weights
  '((code-programming . 1.0)
    (config-system . 0.8)
    (debug-troubleshoot . 0.9)
    (documentation . 0.6)
    (file-operation . 0.7)
    (search-query . 0.5)
    (skill-management . 0.8)
    (session-management . 0.8)
    (provider-management . 0.9)
    (system-status . 0.7)
    (help-info . 0.4))
  "Intent type weights for confidence scoring.")

;;; Task type detection

(defconst aiaos-fast-determin-task-types
  '((elisp-code . ("elisp" "emacs-lisp" "lisp" ".el"))
    (shell-script . ("bash" "shell" "sh" "脚本"))
    (python-code . ("python" "py"))
    (web-search . ("搜索" "搜索" "search"))
    (file-analysis . ("分析" "分析" "analyze" "review"))
    (refactoring . ("重构" "重构" "refactor"))
    (testing . ("测试" "test" "测试")))
  "Task type patterns: (task-type . keyword-list).")

;;; Interaction history

(defvar aiaos-fast-determin-history nil
  "List of recent interaction entries.
Each entry is (timestamp input intent task-type provider success?).")

(defvar aiaos-fast-determin-history-size 0
  "Current size of interaction history.")

;;; Intent classification

(defun aiaos-fast-determin-classify-intent (input)
  "Classify the intent of INPUT.
Returns (intent-type . confidence) where intent-type is a symbol
and confidence is a float between 0.0 and 1.0."
  (let ((lower-input (downcase input))
        (scores '()))
    (dolist (mapping aiaos-fast-determin-intent-keywords)
      (let ((intent (car mapping))
            (keywords (cdr mapping))
            (match-count 0))
        (dolist (kw keywords)
          (when (string-match-p (regexp-quote (downcase kw)) lower-input)
            (cl-incf match-count)))
        (when (> match-count 0)
          (let ((weight (cdr (assq intent aiaos-fast-determin-intent-weights))))
            (push (cons intent
                        (/ (* match-count (or weight 1.0))
                           (max 1 (length keywords))))
                  scores)))))
    (if scores
        (let ((best (sort scores (lambda (a b) (> (cdr a) (cdr b))))))
          (cons (car (car best)) (cdr (car best))))
      (cons 'unknown 0.0))))

;;; Task type detection

(defun aiaos-fast-determin-detect-task-type (input)
  "Detect the task type of INPUT.
Returns (task-type . confidence)."
  (let ((lower-input (downcase input))
        (scores '()))
    (dolist (mapping aiaos-fast-determin-task-types)
      (let ((task-type (car mapping))
            (keywords (cdr mapping))
            (match-count 0))
        (dolist (kw keywords)
          (when (string-match-p (regexp-quote (downcase kw)) lower-input)
            (cl-incf match-count)))
        (when (> match-count 0)
          (push (cons task-type
                      (/ match-count (length keywords)))
                scores))))
    (if scores
        (let ((best (sort scores (lambda (a b) (> (cdr a) (cdr b))))))
          (cons (car (car best)) (cdr (car best))))
      (cons 'general 0.0))))

;;; Provider simulation

(defun aiaos-fast-determin-simulate-provider (provider task-type)
  "Simulate provider performance for TASK-TYPE.
Returns a plist with simulated performance metrics."
  (let* ((base-latency (case task-type
                       (elisp-code 2.0)
                       (shell-script 1.5)
                       (python-code 3.0)
                       (web-search 1.0)
                       (file-analysis 2.5)
                       (refactoring 4.0)
                       (testing 3.0)
                       (t 2.0)))
         (success-rate (case task-type
                        (elisp-code 0.95)
                        (shell-script 0.90)
                        (python-code 0.85)
                        (web-search 0.98)
                        (file-analysis 0.92)
                        (refactoring 0.80)
                        (testing 0.88)
                        (t 0.90)))
         (simulated-latency (* base-latency (1+ (random 0.5))))
         (simulated-success (<= (random 1.0) success-rate)))
    (list :provider provider
          :task-type task-type
          :simulated-latency simulated-latency
          :simulated-success simulated-success
          :confidence success-rate)))

;;; Task progress prediction

(defun aiaos-fast-determin-predict-progress (task-type provider history)
  "Predict task progress based on TASK-TYPE, PROVIDER, and HISTORY.
Returns a plist with predicted metrics."
  (let* ((similar-tasks (aiaos-fast-determin--find-similar
                         task-type provider history))
         (count (length similar-tasks))
         (avg-duration (aiaos-fast-determin--avg-duration similar-tasks))
         (success-rate (aiaos-fast-determin--success-rate similar-tasks)))
    (list :task-type task-type
          :provider provider
          :similar-tasks count
          :predicted-duration (or avg-duration 5.0)
          :predicted-success-rate (or success-rate 0.9)
          :confidence (min 1.0 (/ count 10.0)))))

(defun aiaos-fast-determin--find-similar (task-type provider history)
  "Find similar tasks in HISTORY."
  (let ((similar '()))
    (dolist (entry history)
      (let ((entry-task-type (cdr (assq :task-type entry)))
            (entry-provider (cdr (assq :provider entry))))
        (when (and (eq entry-task-type task-type)
                   (equal entry-provider provider))
          (push entry similar))))
    similar))

(defun aiaos-fast-determin--avg-duration (tasks)
  "Calculate average duration for TASKS."
  (when tasks
    (let ((total 0)
          (count 0))
      (dolist (task tasks)
        (let ((duration (cdr (assq :duration task))))
          (when duration
            (cl-incf total duration)
            (cl-incf count))))
      (when (> count 0)
        (/ total count)))))

(defun aiaos-fast-determin--success-rate (tasks)
  "Calculate success rate for TASKS."
  (when tasks
    (let ((total 0)
          (success 0))
      (dolist (task tasks)
        (cl-incf total)
        (when (cdr (assq :success task))
          (cl-incf success)))
    (when (> total 0)
      (/ (float success) total)))))

;;; Route suggestion

(defun aiaos-fast-determin-suggest-route (input provider)
  "Suggest the best route for INPUT with PROVIDER.
Returns a plist with route suggestion."
  (let* ((intent (aiaos-fast-determin-classify-intent input))
         (task-type (aiaos-fast-determin-detect-task-type input))
         (intent-type (car intent))
         (intent-confidence (cdr intent))
         (task-confidence (cdr task-type))
         (simulation (aiaos-fast-determin-simulate-provider
                      provider task-type))
         (progress (aiaos-fast-determin-predict-progress
                    task-type provider aiaos-fast-determin-history)))
    (list :input input
          :provider provider
          :intent (cons intent-type intent-confidence)
          :task-type (cons task-type task-confidence)
          :simulated-latency (cdr (assq :simulated-latency simulation))
          :predicted-success (cdr (assq :predicted-success simulation))
          :predicted-duration (cdr (assq :predicted-duration progress))
          :overall-confidence (* intent-confidence task-confidence))))

;;; History management

(defun aiaos-fast-determin-record-interaction (input intent task-type provider success &optional duration)
  "Record an interaction to history.
INPUT, INTENT, TASK-TYPE, PROVIDER are the interaction parameters.
SUCCESS is whether the interaction succeeded.
DURATION is the optional duration in seconds."
  (let ((entry (list :timestamp (current-time)
                     :input input
                     :intent intent
                     :task-type task-type
                     :provider provider
                     :success success
                     :duration duration)))
    (push entry aiaos-fast-determin-history)
    (when (> (length aiaos-fast-determin-history)
             aiaos-fast-determin-max-history)
      (setq aiaos-fast-determin-history
            (nreverse (last aiaos-fast-determin-history
                            aiaos-fast-determin-max-history))))
  (aiaos-cli-events-publish 'interaction-recorded 'fast-determin entry)))

;;; Quick judgment

(defun aiaos-fast-determin-judge (input &optional provider)
  "Perform quick judgment on INPUT.
Returns a plist with judgment results."
  (let* ((provider (or provider (aiaos-fast-determin--current-provider)))
         (intent (aiaos-fast-determin-classify-intent input))
         (task-type (aiaos-fast-determin-detect-task-type input))
         (route (aiaos-fast-determin-suggest-route input provider))
         (judgment (aiaos-fast-determin--make-judgment intent task-type route)))
    (list :input input
          :provider provider
          :intent intent
          :task-type task-type
          :route route
          :judgment judgment
          :timestamp (current-time))))

(defun aiaos-fast-determin--current-provider ()
  "Return the current LLM provider name."
  (condition-case nil
      (aiaos-cli-core-current-provider)
    (error nil)))

(defun aiaos-fast-determin--make-judgment (intent task-type route)
  "Make a judgment based on INTENT, TASK-TYPE, and ROUTE."
  (let* ((intent-type (car intent))
         (intent-confidence (cdr intent))
         (task-confidence (cdr (assq :task-type route)))
         (overall-confidence (cdr (assq :overall-confidence route)))
         (predicted-success (cdr (assq :predicted-success route))))
    (cond
     ((>= overall-confidence 0.8)
      (list :verdict 'high-confidence
            :message (format "High confidence judgment: %s task for %s intent"
                            (cdr (assq :task-type route))
                            intent-type)
            :confidence overall-confidence
            :recommended-action 'proceed))
     ((>= overall-confidence 0.5)
      (list :verdict 'medium-confidence
            :message (format "Medium confidence judgment: %s task for %s intent"
                            (cdr (assq :task-type route))
                            intent-type)
            :confidence overall-confidence
            :recommended-action 'verify))
     ((>= overall-confidence 0.2)
      (list :verdict 'low-confidence
            :message (format "Low confidence judgment: unclear intent for %s"
                            input)
            :confidence overall-confidence
            :recommended-action 'ask-clarification))
     (t
      (list :verdict 'unknown
            :message "Unable to determine intent"
            :confidence 0.0
            :recommended-action 'ask-clarification)))))

;;; Forward-looking simulation

(defun aiaos-fast-determin-simulate-forward (input provider steps)
  "Perform forward-looking simulation for INPUT with PROVIDER over STEPS.
Returns a list of simulation steps."
  (let ((results '()))
    (dotimes (i steps (reverse results))
      (let* ((step-input (format "%s [step %d]" input (1+ i)))
             (judgment (aiaos-fast-determin-judge step-input provider))
             (success-prob (cdr (assq :predicted-success
                                      (cdr (assq :route judgment))))))
        (push (list :step (1+ i)
                   :input step-input
                   :judgment judgment
                   :success-prob success-prob)
              results)))))

;;; Status and reporting

(defun aiaos-fast-determin-status ()
  "Return the status of the fast determination module."
  (list :enabled aiaos-fast-determin-enabled
        :history-size (length aiaos-fast-determin-history)
        :max-history aiaos-fast-determin-max-history
        :similarity-threshold aiaos-fast-determin-similarity-threshold))

(defun aiaos-fast-determin-summary ()
  "Return a summary of recent interactions."
  (let ((recent (last aiaos-fast-determin-history 10)))
    (list :total-interactions (length aiaos-fast-determin-history)
          :recent-interactions (mapcar
                                (lambda (entry)
                                  (list :timestamp (cdr (assq :timestamp entry))
                                        :intent (cdr (assq :intent entry))
                                        :task-type (cdr (assq :task-type entry))
                                        :success (cdr (assq :success entry))))
                                recent))))

;;; Provide

(provide 'aiaos-fast-determin)

;;; aiaos-fast-determin.el ends here