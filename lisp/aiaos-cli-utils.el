;;; aiaos-cli-utils.el --- Utility Functions for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, utils, aiaos

;; Utility functions for AIAOS-CLI.

;;; Commentary:

;; This module provides various utility functions:
;;   * String manipulation
;;   * Path handling
;;   * Process management
;;   * Data conversion

;;; Code:

(require 'cl-lib)
(require 'json)

;;; String utilities

(defun aiaos-cli-utils-truncate (str max-length &optional suffix)
  "Truncate STR to MAX-LENGTH with SUFFIX."
  (if (<= (length str) max-length)
      str
    (concat (substring str 0 (- max-length (length suffix))) suffix)))

(defun aiaos-cli-utils-pad-left (str width &optional fill-char)
  "Pad STR to WIDTH with FILL-CHAR on left."
  (let ((fill-char (or fill-char ? )))
    (if (>= (length str) width)
        str
      (concat (make-string (- width (length str)) fill-char) str))))

(defun aiaos-cli-utils-pad-right (str width &optional fill-char)
  "Pad STR to WIDTH with FILL-CHAR on right."
  (let ((fill-char (or fill-char ? )))
    (if (>= (length str) width)
        str
      (concat str (make-string (- width (length str)) fill-char)))))

;;; Path utilities

(defun aiaos-cli-utils-path-join (&rest components)
  "Join path COMPONENTS."
  (mapconcat 'expand-file-name components "/"))

(defun aiaos-cli-utils-path-relative (path base)
  "Make PATH relative to BASE."
  (let ((abs-path (expand-file-name path))
        (abs-base (expand-file-name base)))
    (if (string-prefix-p abs-base abs-path)
        (substring abs-path (length abs-base))
      abs-path)))

;;; Process utilities

(defun aiaos-cli-utils-command-exists (command)
  "Check if COMMAND exists."
  (when (executable-find command) t))

;;; JSON utilities

(defun aiaos-cli-utils-json-pretty-print (json-object)
  "Pretty print JSON-OBJECT."
  (json-encode json-object))

;;; Time utilities

(defun aiaos-cli-utils-time-format (seconds)
  "Format SECONDS as HH:MM:SS."
  (let* ((hours (floor seconds 3600))
         (minutes (floor (mod seconds 600) 60))
         (secs (mod seconds 60)))
    (format "%02d:%02d:%02d" hours minutes secs)))

;;; Validation utilities

(defun aiaos-cli-utils-validate-string (str &optional min-length max-length)
  "Validate STR length."
  (and (stringp str)
       (or (null min-length) (>= (length str) min-length))
       (or (null max-length) (<= (length str) max-length))))

(provide 'aiaos-cli-utils)

;;; aiaos-cli-utils.el ends here