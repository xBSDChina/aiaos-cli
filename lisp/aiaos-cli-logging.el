;;; aiaos-cli-logging.el --- Logging for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, logging, aiaos

;; Logging system for AIAOS-CLI.

;;; Commentary:

;; This module provides logging capabilities:
;;   * aiaos-cli-log - Log a message
;;   * aiaos-cli-log-level-set - Set log level
;;   * aiaos-cli-log-file-set - Set log file
;;   * aiaos-cli-log-view - View log buffer

;;; Code:

(require 'cl-lib)

(defgroup aiaos-cli-logging nil
  "AIAOS-CLI Logging"
  :group 'aiaos-cli
  :prefix "aiaos-cli-log-")

(defcustom aiaos-cli-log-level 'info
  "Log level: debug, info, warn, error."
  :type '(choice (const debug) (const info) (const warn) (const error))
  :group 'aiaos-cli-logging)

(defcustom aiaos-cli-log-file nil
  "Log file path."
  :type 'file
  :group 'aiaos-cli-logging)

;; Log levels
(defconst aiaos-cli-log-levels
  '((debug . 0) (info . 1) (warn . 2) (error . 3))
  "Log level priorities.")

;; Log buffer
(defvar aiaos-cli-log-buffer nil
"Log buffer.")

;;; Logging functions

(defun aiaos-cli-log-level-priority (level)
  "Get priority for LEVEL."
  (cdr (assoc level aiaos-cli-log-levels)))

(defun aiaos-cli-log (level message &rest args)
  "Log MESSAGE at LEVEL with ARGS."
  (when (>= (aiaos-cli-log-level-priority level)
            (aiaos-cli-log-level-priority aiaos-cli-log-level))
    (let ((formatted (apply 'format message args)))
      (when aiaos-cli-log-buffer
        (with-current-buffer aiaos-cli-log-buffer
          (goto-char (point-max))
          (insert (format "[%s] %s: %s\n"
                         (format-time-string "%Y-%m-%d %H:%M:%S")
                         (upcase (symbol-name level))
                         formatted))))
      (when aiaos-cli-log-file
        (append-to-file (format "[%s] %s: %s\n"
                               (format-time-string "%Y-%m-%d %H:%M:%S")
                               (upcase (symbol-name level))
                               formatted)
                       nil aiaos-cli-log-file)))))

;;; Convenience functions

(defun aiaos-cli-log-debug (msg &rest args)
  "Log debug message."
  (apply 'aiaos-cli-log 'debug msg args))

(defun aiaos-cli-log-info (msg &rest args)
  "Log info message."
  (apply 'aiaos-cli-log 'info msg args))

(defun aiaos-cli-log-warn (msg &rest args)
  "Log warning message."
  (apply 'aiaos-cli-log 'warn msg args))

(defun aiaos-cli-log-error (msg &rest args)
  "Log error message."
  (apply 'aiaos-cli-log 'error msg args))

;;; Initialize

(defun aiaos-cli-log-init ()
  "Initialize logging system."
  (unless aiaos-cli-log-buffer
    (setq aiaos-cli-log-buffer (get-buffer-create "*aiaos-cli-log*"))))

(provide 'aiaos-cli-logging)

;;; aiaos-cli-logging.el ends here