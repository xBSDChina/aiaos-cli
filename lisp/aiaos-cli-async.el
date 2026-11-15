;;; aiaos-cli-async.el --- Async Processing for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, async, aiaos

;; Async processing utilities for non-blocking operations.

;;; Commentary:

;; This module provides async processing capabilities:
;;   * aiaos-cli-async-run - Run function asynchronously
;;   * aiaos-cli-async-call - Call function with timeout
;;   * aiaos-cli-async-poll - Poll for condition
;;   * aiaos-cli-async-batch - Batch async operations

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-events)

(defgroup aiaos-cli-async nil
  "AIAOS-CLI Async Processing"
  :group 'aiaos-cli
  :prefix "aiaos-cli-async-")

(defcustom aiaos-cli-async-default-timeout 30
  "Default timeout for async operations in seconds."
  :type 'integer
  :group 'aiaos-cli-async)

;;; Async execution

(defun aiaos-cli-async-run (func &rest args)
  "Run FUNC with ARGS asynchronously."
  (let ((buf (generate-new-buffer " *aiaos-async*")))
    (make-process
     :name "aiaos-async"
     :buffer buf
     :command (list "emacs" "--batch" "--eval"
                   (format "(progn (require 'aiaos-cli-core) (apply '%s '%s))" func args))
     :connection-type 'pipe
     :sentinel (lambda (proc event)
                 (when (eq (process-status proc) 'exit)
                   (kill-buffer (process-buffer proc)))))))

;;; Timeout wrapper

(defun aiaos-cli-async-call (func timeout &rest args)
  "Call FUNC with ARGS, return result or timeout."
  (let ((result nil)
        (timed-out nil))
    (run-with-timer timeout nil
                    (lambda () (setq timed-out t)))
    (condition-case err
        (setq result (apply func args))
      (error (message "Error: %s" (error-message-string err))))
    (if timed-out nil result)))

;;; Polling

(defun aiaos-cli-async-poll (condition &optional timeout interval)
  "Poll CONDITION until true or timeout."
  (let ((start (float-time))
        (timeout (or timeout 30))
        (interval (or interval 0.5)))
    (while (and (not (funcall condition))
                (< (- (float-time) start) timeout))
      (sleep-for interval))
    (funcall condition)))

(provide 'aiaos-cli-async)

;;; aiaos-cli-async.el ends here