;;; aiaos-core.el --- Core functionality for AIAOS CLI  -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS

(require 'cl-lib)

(defgroup aiaos-core nil "AIAOS core utilities." :group 'aiaos-cli)

(defconst aiaos-core-version "1.0.0" "AIAOS CLI version.")

(defun aiaos-core-init ()
  "Initialize AIAOS core."
  (let ((home-dir (aiaos-core-home-dir)))
    (when (not (file-exists-p home-dir))
      (make-directory home-dir t)))
  (setq aiaos-core-log-level 'info))

(defcustom aiaos-cli-home-dir "~/.aiaos" "Home directory for AIAOS files."
  :type 'string :group 'aiaos-cli)
(defcustom aiaos-core-log-level 'info "Logging level."
  :type '(choice (const debug) (const info) (const warn) (const error))
  :group 'aiaos-cli)
(defcustom aiaos-cli-log-prefix "AIAOS" "Log message prefix."
  :type 'string :group 'aiaos-cli)

(defvar aiaos-core-log-suppress-stdout nil
  "Non-nil when log messages must NOT be echoed to standard-output.

aiaos-core-log writes every info/warn/error message to the *Messages*
buffer, and additionally echoes it to standard-output so that batch-mode
callers can capture it. Downstream callers that need a clean stdout
channel (e.g. JSON output mode) flip this switch via
aiaos-core-log-suppress-stdout-set so that only the structured payload
reaches stdout while logs still go to *Messages*.

This switch lives in core on purpose: core must never reference a
business module (see design doc section 2, strict one-way dependencies).
Business modules own the policy of when to suppress and ask core to
apply it. aiaos-cli--json-mode is such a policy and is mirrored here by
aiaos-cli.")

(defun aiaos-core-log-suppress-stdout-set (val)
  "Set whether stdout echo of log messages is suppressed to VAL.
Returns the new value. Idempotent, so it is safe to call
unconditionally at the start of every dispatch."
  (setq aiaos-core-log-suppress-stdout val)
  val)

(defun aiaos-core-log-suppress-stdout-p ()
  "Return non-nil if stdout echo of log messages is suppressed."
  aiaos-core-log-suppress-stdout)

(defun aiaos-core-home-dir ()
  "Return the user home directory, safe in batch mode.
Uses the HOME environment variable, falling back to user-home-dir
or the current directory."
  (file-name-as-directory
   (or (getenv "HOME")
       (and (boundp 'user-home-dir) user-home-dir)
       default-directory)))

(defun aiaos-core-emit-line (text)
  "Print TEXT to stdout, guaranteeing a trailing newline (R597).

This is the single canonical stdout emitter for the whole project.
It wraps `princ' so batch-mode output stays on stdout, and appends
\\n when TEXT does not already end with one.  All modules must use
this (directly or via `aiaos-cli--print') instead of raw `princ'
so the R596 no-concatenation contract holds project-wide."
  (princ text)
  (unless (string-suffix-p "\n" text)
    (princ "\n")))

(defun aiaos-core-log (level message &rest args)
  "Log MESSAGE with LEVEL and ARGS.

Writes to the *Messages* buffer via `message' and, for info/warn/error
levels, also echoes the formatted line to `standard-output' so that
batch-mode callers and tests that redirect `standard-output' can capture
the output."
  (let ((formatted (apply #'format message args))
        (level-name (if (stringp level) level (symbol-name level))))
    (message "[%s] [%s] %s: %s"
             (format-time-string "%Y-%m-%d %H:%M:%S")
             level-name
             aiaos-cli-log-prefix
             formatted)
    (when (and (member level '(info warn error)) (not aiaos-core-log-suppress-stdout))
      (aiaos-core-emit-line formatted))))

(defun aiaos-core-debug (&rest args)
  "Log a debug message."
  (apply #'aiaos-core-log 'debug args))

(defun aiaos-core-info (&rest args)
  "Log an info message."
  (apply #'aiaos-core-log 'info args))

(defun aiaos-core-warn (&rest args)
  "Log a warning message."
  (apply #'aiaos-core-log 'warn args))

(defun aiaos-core-error (&rest args)
  "Log an error message."
  (apply #'aiaos-core-log 'error args))

;; Alias for backward compatibility and cross-module usage
(defalias 'aiaos-cli-info 'aiaos-core-info)
(defalias 'aiaos-cli-warn 'aiaos-core-warn)
(defalias 'aiaos-cli-error 'aiaos-core-error)
(defalias 'aiaos-cli-debug 'aiaos-core-debug)

(provide 'aiaos-core)
;;; aiaos-core.el ends here