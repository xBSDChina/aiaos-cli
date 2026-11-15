;;; aiaos-cli-monitor.el --- Performance Monitoring for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, monitoring, metrics

;; Performance monitoring and metrics collection.

;;; Commentary:

;; This module provides performance monitoring capabilities for AIAOS-CLI.
;; It tracks response times, error rates, memory usage, and other metrics.

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-events)

(defgroup aiaos-cli-monitor nil
  "AIAOS-CLI Performance Monitoring"
  :group 'aiaos-cli
  :prefix "aiaos-cli-monitor-")

;;; Metrics structure

(cl-defstruct aiaos-cli-metric
  "Performance metric."
  name        ; metric name
  value       ; current value
  count       ; number of samples
  min         ; minimum value
  max         ; maximum value
  avg         ; average value
  timestamp)  ; last update time

;;; Metrics registry

(defvar aiaos-cli-metrics-registry nil
"Hash table of metrics (name . metric).")

;;; Timer tracking

(defvar aiaos-cli-active-timers nil
"Hash table of active timers (name . start-time).")

;;; Initialize monitoring

(defun aiaos-cli-monitor-init ()
  "Initialize the monitoring system."
  (setq aiaos-cli-metrics-registry (make-hash-table :test 'equal))
  (setq aiaos-cli-active-timers (make-hash-table :test 'equal))
  (aiaos-cli-events-subscribe 'llm-request 'aiaos-cli-monitor--on-llm-request)
  (aiaos-cli-events-subscribe 'llm-response 'aiaos-cli-monitor--on-llm-response)
  (aiaos-cli-events-subscribe 'llm-error 'aiaos-cli-monitor--on-llm-error)
  (aiaos-cli-events-subscribe 'task-completed 'aiaos-cli-monitor--on-task-completed)
  (aiaos-cli-events-subscribe 'task-failed 'aiaos-cli-monitor--on-task-failed)
  (message "AIAOS-CLI Monitor initialized"))

;;; Start a timer

(defun aiaos-cli-monitor-start-timer (name)
  "Start a timer with NAME."
  (puthash name (current-time) aiaos-cli-active-timers))

;;; Stop a timer and record metric

(defun aiaos-cli-monitor-stop-timer (name &optional category)
  "Stop timer with NAME and record the elapsed time.
CATEGORY is the metric category (default 'default)."
  (let ((start (gethash name aiaos-cli-active-timers)))
    (when start
      (remhash name aiaos-cli-active-timers)
      (let ((elapsed (float-time (time-subtract (current-time) start))))
        (aiaos-cli-monitor-record name elapsed category)
        elapsed))))

;;; Record a metric

(defun aiaos-cli-monitor-record (name value &optional category)
  "Record a metric VALUE for NAME.
CATEGORY is optional (default 'default)."
  (let* ((key (if category (format "%s/%s" category name) name))
         (metric (gethash key aiaos-cli-metrics-registry)))
    (unless metric
      (setq metric (make-aiaos-cli-metric
                    :name key
                    :value value
                    :count 1
                    :min value
                    :max value
                    :avg value
                    :timestamp (current-time)))
      (puthash key metric aiaos-cli-metrics-registry))
    (setf (aiaos-cli-metric-value metric) value)
    (setf (aiaos-cli-metric-count metric) (1+ (aiaos-cli-metric-count metric)))
    (setf (aiaos-cli-metric-min metric) (min (aiaos-cli-metric-min metric) value))
    (setf (aiaos-cli-metric-max metric) (max (aiaos-cli-metric-max metric) value))
    (setf (aiaos-cli-metric-avg metric)
          (/ (+ (* (aiaos-cli-metric-avg metric) (1- (aiaos-cli-metric-count metric)))
                 value)
              (aiaos-cli-metric-count metric)))
    (setf (aiaos-cli-metric-timestamp metric) (current-time))))

;;; Get metric

(defun aiaos-cli-monitor-get-metric (name)
  "Get metric with NAME."
  (gethash name aiaos-cli-metrics-registry))

;;; Get all metrics

(defun aiaos-cli-monitor-get-all-metrics ()
  "Get all metrics as a list."
  (let (metrics)
    (maphash (lambda (k v) (push (cons k v) metrics))
             aiaos-cli-metrics-registry)
    metrics))

;;; Get metrics summary

(defun aiaos-cli-monitor-get-summary ()
  "Get a summary of all metrics."
  (let ((metrics (aiaos-cli-monitor-get-all-metrics))
        (total-count 0)
        (total-avg 0)
        (total-min most-positive-fixnum)
        (total-max 0))
    (dolist (metric metrics)
      (let ((m (cdr metric)))
        (incf total-count (aiaos-cli-metric-count m))
        (incf total-avg (aiaos-cli-metric-avg m))
        (setf total-min (min total-min (aiaos-cli-metric-min m)))
        (setf total-max (max total-max (aiaos-cli-metric-max m)))))
    (list :total-metrics (length metrics)
          :total-count total-count
          :total-avg (/ total-avg (max 1 (length metrics)))
          :total-min total-min
          :total-max total-max)))

;;; Event handlers

(defun aiaos-cli-monitor--on-llm-request (event)
  "Handle llm-request event."
  (let ((source (aiaos-cli-event-source event)))
    (aiaos-cli-monitor-start-timer (format "llm-request-%s" source))))

(defun aiaos-cli-monitor--on-llm-response (event)
  "Handle llm-response event."
  (let ((source (aiaos-cli-event-source event)))
    (aiaos-cli-monitor-stop-timer (format "llm-request-%s" source) 'llm)))

(defun aiaos-cli-monitor--on-llm-error (event)
  "Handle llm-error event."
  (aiaos-cli-monitor-record "llm-error" 1 'llm))

(defun aiaos-cli-monitor--on-task-completed (event)
  "Handle task-completed event."
  (let ((data (aiaos-cli-event-data event)))
    (when (alist-get :duration data)
      (aiaos-cli-monitor-record "task-duration" (alist-get :duration data) 'task))))

(defun aiaos-cli-monitor--on-task-failed (event)
  "Handle task-failed event."
  (aiaos-cli-monitor-record "task-failure" 1 'task))

;;; Reset metrics

(defun aiaos-cli-monitor-reset ()
  "Reset all metrics."
  (setq aiaos-cli-metrics-registry (make-hash-table :test 'equal))
  (message "Metrics reset"))

;;; Display metrics

(defun aiaos-cli-monitor-show ()
  "Display metrics summary in a buffer."
  (let ((summary (aiaos-cli-monitor-get-summary))
        (metrics (aiaos-cli-monitor-get-all-metrics)))
    (with-current-buffer (get-buffer-create "*AIAOS-CLI Metrics*")
      (erase-buffer)
      (insert (propertize "AIAOS-CLI Performance Metrics\n\n" 'face 'bold))
      (insert (format "Total Metrics: %d\n" (alist-get :total-metrics summary)))
      (insert (format "Total Samples: %d\n" (alist-get :total-count summary)))
      (insert (format "Average: %.2f\n" (alist-get :total-avg summary)))
      (insert (format "Min: %.2f\n" (alist-get :total-min summary)))
      (insert (format "Max: %.2f\n\n" (alist-get :total-max summary)))
      (insert (propertize "Detailed Metrics:\n" 'face 'bold))
      (dolist (metric (sort metrics (lambda (a b)
                                      (string> (car a) (car b)))))
        (let ((m (cdr metric)))
          (insert (format "  %s: count=%d avg=%.4f min=%.4f max=%.4f\n"
                          (car metric)
                          (aiaos-cli-metric-count m)
                          (aiaos-cli-metric-avg m)
                          (aiaos-cli-metric-min m)
                          (aiaos-cli-metric-max m)))))
      (switch-to-buffer (current-buffer)))))

;;; Memory monitoring

(defun aiaos-cli-monitor-memory-usage ()
  "Get current memory usage."
  (let ((gc-cons-threshold most-positive-fixnum))
    (garbage-collect)
    (let ((stats (gc-stats)))
      (list :bytes-allocated (cdr (assq 'bytes-allocated stats))
            :bytes-free (cdr (assq 'bytes-free stats))
            :heap-size (cdr (assq 'heap-size stats))))))

(provide 'aiaos-cli-monitor)

;;; aiaos-cli-monitor.el ends here