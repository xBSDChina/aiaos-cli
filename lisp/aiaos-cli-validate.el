;;; aiaos-cli-validate.el --- Validation for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, validation, aiaos

;; Input validation for AIAOS-CLI.

;;; Commentary:

;; This module provides validation functions:
;;   * aiaos-cli-validate-command - Validate command
;;   * aiaos-cli-validate-provider - Validate provider config
;;   * aiaos-cli-validate-input - Validate user input

;;; Code:

(require 'cl-lib)

(defgroup aiaos-cli-validate nil
  "AIAOS-CLI Validation"
  :group 'aiaos-cli
  :prefix "aiaos-cli-validate-")

;;; Validation functions

(defun aiaos-cli-validate-command (command)
  "Validate COMMAND string."
  (and (stringp command)
       (> (length command) 0)
       (<= (length command) 1024)))

(defun aiaos-cli-validate-provider (provider)
  "Validate PROVIDER configuration."
  (and (listp provider)
       (assoc 'name provider)
       (assoc 'endpoint provider)
       (assoc 'model provider)))

(defun aiaos-cli-validate-input (input &optional pattern)
  "Validate INPUT against PATTERN."
  (if pattern
      (string-match-p pattern input)
    (and (stringp input)
         (> (length input) 0))))

(provide 'aiaos-cli-validate)

;;; aiaos-cli-validate.el ends here