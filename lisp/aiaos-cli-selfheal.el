;;; aiaos-cli-selfheal.el --- Self-Healing Engine for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, self-healing, resilience

;; Self-healing mechanisms for automatic problem detection and recovery.

;;; Commentary:

;; This module provides self-healing capabilities:
;; - Automatic error detection
;; - Fallback provider switching
;; - Memory cleanup
;; - Configuration validation
;; - Performance degradation detection

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-events)
(require 'aiaos-cli-monitor)

(defgroup aiaos-cli-selfheal nil
  "AIAOS-CLI Self-Healing"
  :group 'aiaos-cli
  :prefix "aiaos-cli-selfheal-")

;;; Configuration

(defcustom aiaos-cli-selfheal-auto-recover t
  "Enable automatic recovery."
  :type 'boolean
  :group 'aiaos-cli-selfheal)

(defcustom aiaos-cli-selfheal-check-interval 30
  "Health check interval in seconds."
  :type 'integer
  :group 'aiaos-cli-selfheal)

;;; Health status

(defconst aiaos-cli-selfheal-status
  '((healthy . "System is healthy")
    (degraded . "System is degraded")
    (unhealthy . "System is unhealthy")
    (critical . "System is critical"))
  "Health status descriptions.")

(defvar aiaos-cli-selfheal-current-status 'healthy
"Current health status.")

(defvar aiaos-cli-selfheal-check-timer nil
"Timer for periodic health checks.")

;;; Health check functions

(defun aiaos-cli-selfheal-check ()
  "Perform a health check."
  (let ((issues (aiaos-cli-selfheal--collect-issues)))
    (if issues
        (aiaos-cli-selfheal--handle-issues issues)
      (aiaos-cli-selfheal--set-status 'healthy))
    (aiaos-cli-events-publish 'health-check-completed 'selfheal
                              (list :issues issues
                                    :status aiaos-cli-selfheal-current-status))))

(defun aiaos-cli-selfheal--collect-issues ()
  "Collect all detected issues."
  (let (issues)
    ;; Check memory usage
    (let ((mem (aiaos-cli-monitor-memory-usage)))
      (when (> (alist-get :bytes-allocated mem) (* 100 1024 1024)) ; 100MB
        (push (list :type 'memory :severity 'warning
                    :message "High memory usage"
                    :data mem) issues)))
    
    ;; Check LLM provider health
    (when (aiaos-cli-core-provider-p)
      (let ((status (aiaos-cli-core-provider-status)))
        (when (eq status 'down)
          (push (list :type 'provider :severity 'critical
                      :message "LLM provider is down"
                      :data status) issues))))
    
    ;; Check for stale timers
    (let ((stale-count 0))
      (maphash (lambda (k v)
                 (when (> (float-time (time-subtract (current-time) v))
                          300) ; 5 minutes
                   (incf stale-count)))
               aiaos-cli-active-timers)
      (when (> stale-count 0)
        (push (list :type 'resources :severity 'warning
                    :message (format "Stale timers: %d" stale-count)
                    :data stale-count) issues)))
    
    issues))

(defun aiaos-cli-selfheal--handle-issues (issues)
  "Handle detected ISSUES."
  (dolist (issue issues)
    (let ((type (alist-get :type issue))
          (severity (alist-get :severity issue)))
      (message "Self-heal: Handling %s issue (severity: %s)" type severity)
      (case type
        (memory (aiaos-cli-selfheal--recover-memory issue))
        (provider (aiaos-cli-selfheal--recover-provider issue))
        (resources (aiaos-cli-selfheal--recover-resources issue))
        (t (message "No recovery for issue type: %s" type))))
  (aiaos-cli-selfheal--update-status issues)))

;;; Recovery functions

(defun aiaos-cli-selfheal--recover-memory (issue)
  "Recover from memory issues."
  (message "Running garbage collection...")
  (garbage-collect)
  (message "Memory recovery complete"))

(defun aiaos-cli-selfheal--recover-provider (issue)
  "Recover from provider issues."
  (message "Attempting provider recovery...")
  (when (fboundp 'aiaos-cli-core-switch-fallback-provider)
    (aiaos-cli-core-switch-fallback-provider))
  (message "Provider recovery complete"))

(defun aiaos-cli-selfheal--recover-resources (issue)
  "Recover from resource issues."
  (message "Cleaning up stale resources...")
  (maphash (lambda (k v)
             (when (> (float-time (time-subtract (current-time) v))
                      300)
               (remhash k aiaos-cli-active-timers)))
  (message "Resource cleanup complete")))

;;; Status management

(defun aiaos-cli-selfheal--set-status (status)
  "Set health STATUS."
  (unless (eq status aiaos-cli-selfheal-current-status)
    (let ((old-status aiaos-cli-selfheal-current-status))
      (setq aiaos-cli-selfheal-current-status status)
      (aiaos-cli-events-publish 'health-status-changed 'selfheal
                                (list :old-status old-status
                                      :new-status status))
      (message "Health status: %s -> %s" old-status status))))

(defun aiaos-cli-selfheal--update-status (issues)
  "Update health status based on ISSUES."
  (let ((max-severity 0))
    (dolist (issue issues)
      (let ((severity (alist-get :severity issue)))
        (incf max-severity
              (case severity
                (info 0)
                (warning 1)
                (error 2)
                (critical 3)
                (t 1)))))
    (aiaos-cli-selfheal--set-status
     (case max-severity
       (0 'healthy)
       (1 'degraded)
       (2 'unhealthy)
       (3 'critical)
       (t 'unknown)))))

;;; Automatic recovery

(defun aiaos-cli-selfheal-auto-recover ()
  "Perform automatic recovery if needed."
  (when aiaos-cli-selfheal-auto-recover
    (let ((status aiaos-cli-selfheal-current-status))
      (case status
        ((unhealthy critical)
         (message "Triggering automatic recovery...")
         (aiaos-cli-selfheal-check))
        (t nil)))))

;;; Health monitoring loop

(defun aiaos-cli-selfheal-start-monitoring ()
  "Start periodic health monitoring."
  (aiaos-cli-selfheal-stop-monitoring)
  (setq aiaos-cli-selfheal-check-timer
        (run-with-timer aiaos-cli-selfheal-check-interval
                        aiaos-cli-selfheal-check-interval
                        'aiaos-cli-selfheal-check))
  (message "Self-heal monitoring started (interval: %ds)"
           aiaos-cli-selfheal-check-interval))

(defun aiaos-cli-selfheal-stop-monitoring ()
  "Stop periodic health monitoring."
  (when aiaos-cli-selfheal-check-timer
    (cancel-timer aiaos-cli-selfheal-check-timer)
    (setq aiaos-cli-selfheal-check-timer nil)
    (message "Self-heal monitoring stopped")))

;;; Manual health check

(defun aiaos-cli-selfheal-manual-check ()
  "Perform a manual health check."
  (interactive)
  (message "Performing health check...")
  (aiaos-cli-selfheal-check)
  (let ((status aiaos-cli-selfheal-current-status))
    (message "Health check complete. Status: %s" status)
    status))

;;; Get health report

(defun aiaos-cli-selfheal-get-report ()
  "Get a detailed health report."
  (let ((status aiaos-cli-selfheal-current-status)
        (metrics (aiaos-cli-monitor-get-summary))
        (issues (aiaos-cli-selfheal--collect-issues)))
    (list :status status
          :status-description (cdr (assq status aiaos-cli-selfheal-status))
          :metrics metrics
          :issues issues
          :timestamp (current-time))))

(provide 'aiaos-cli-selfheal)

;;; aiaos-cli-selfheal.el ends here