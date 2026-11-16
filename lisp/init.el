;;; init.el --- AIAOS-CLI unified loading entry -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0

;; This file is the unified loading entry for aiaos-cli.
;; It defines the aiaos-cli-main function expected by the aiaos-cli executable.

(require 'aiaos-cli)
(require 'aiaos-cli-registry)
(require 'aiaos-cli-skill)

;; JSON output mode flag (set by aiaos-cli executable via AIAOS_CLI_JSON env var)
(make-variable-buffer-local 'aiaos-cli--json-mode)

;; Forward declarations
(declare-function aiaos-cli-find-command "aiaos-cli-registry.el")
(declare-function aiaos-cli-execute "aiaos-cli-registry.el")
(declare-function aiaos-cli--build-cmd "aiaos-cli.el")
(declare-function aiaos-cli--call-sync "aiaos-cli.el")
(declare-function aiaos-cli-agent-run "aiaos-cli.el")

;; Help text
(defconst aiaos-cli--help-text
  "AIAOS-CLI - command line interface for AIAOS\n\n\
Usage: aiaos-cli [--json] <command> [args...]\n\n\
Commands:\n\
  system_info check_cpu      - CPU information\n\
  system_info check_memory    - Memory information\n\
  system_info check_disk      - Disk information\n\
  system_info check_os        - OS information\n\
  system_info check_load      - Load information\n\
  system_info check_net       - Network information\n\
  session new [name]          - Create new session\n\
  session list                - List sessions\n\
  session current             - Show current session\n\
  session show [name]         - Show session details\n\
  session switch <name>       - Switch session\n\
  context show                - Show current context\n\
  skill list                  - List skills\n\
  skill search <query>        - Search skills\n\
  skill enable <name>         - Enable skill\n\
  skill disable <name>        - Disable skill\n\
   skill deps <name>           - Show skill dependencies\n\
   agent <message>             - Run agent script: interact with LLM, execute tools, complete task\n\
   version                     - Show version\n\
  help                        - Show this help\n\n\
Options:\n\
  --json                      - Output in JSON format\n\
  --no-json                   - Output in plain text (default)\n")

(defun aiaos-cli--version-string ()
  "Return version string."
  (require 'aiaos-cli-version)
  (format "AIAOS-CLI %s\n" aiaos-cli-version))

(defun aiaos-cli--format-result (result &optional status)
  "Format RESULT to stdout.
If aiaos-cli--json-mode is t, output JSON.
Otherwise output plain text."
  (cond
   (aiaos-cli--json-mode
    (condition-case _
        (princ (json-encode result))
      (error (princ (format "%S" result)))))
   (t
    (cond
     ((stringp result) result)
     ((and (listp result) (keywordp (car result)))
      ;; plist result
      (let ((status (plist-get result :status))
            (data (plist-get result :data))
            (error-code (plist-get result :error-code))
            (error-msg (plist-get result :error-message)))
        (cond
         ((string= status "success")
          (if data (format "%S" data) ""))
         (t
          (format "Error: %s - %s\n" (or error-code "UNKNOWN") (or error-msg "Unknown error"))))))
     ((integerp status)
      ;; External command result: (status . output)
      (if (= status 0)
          (or result "")
          (format "Command failed with exit code %s\n" status)))
     (t
      (format "%S" result))))))

(defun aiaos-cli-main (args)
  "Main entry point for aiaos-cli executable.
ARGS is the list of command line arguments."
  (let ((remaining args)
        (json-mode nil))
    ;; Parse flags
    (while (and remaining (string-prefix-p "--" (car remaining)))
      (let ((flag (car remaining)))
        (cond
         ((string= flag "--json")
          (setq json-mode t))
         ((string= flag "--no-json")
          (setq json-mode nil))
         (t
          (princ (format "Unknown option: %s\n" flag))
          (princ aiaos-cli--help-text)
          (return-from aiaos-cli-main 1)))
        (setq remaining (cdr remaining))))
    (setq aiaos-cli--json-mode json-mode)
    
    (if (null remaining)
        (progn
          (princ aiaos-cli--help-text)
          0)
      (let ((domain (car remaining))
            (rest (cdr remaining)))
        (cond
         ((string= domain "version")
          (princ (aiaos-cli--version-string))
          0)
         ((string= domain "help")
          (princ aiaos-cli--help-text)
          0)
         ((string= domain "system_info")
          (if (null rest)
              (progn
                (princ "Usage: system_info <action>\n")
                1)
            (let ((action (car rest))
                  (args (cdr rest)))
              (condition-case err
                  (let ((result (aiaos-cli-execute domain action args)))
                    (princ (aiaos-cli--format-result result))
                    0)
                (error
                 (princ (format "Error: %s\n" (error-message-string err)))
                 1)))))
         ((string= domain "session")
          (if (null rest)
              (progn
                (princ "Usage: session <action> [args]\n")
                1)
            (let ((action (car rest))
                  (args (cdr rest)))
              (condition-case err
                  (let ((result (aiaos-cli-execute domain action args)))
                    (princ (aiaos-cli--format-result result))
                    0)
                (error
                 (princ (format "Error: %s\n" (error-message-string err)))
                 1)))))
         ((string= domain "context")
          (if (null rest)
              (progn
                (princ "Usage: context <action>\n")
                1)
            (let ((action (car rest))
                  (args (cdr rest)))
              (condition-case err
                  (let ((result (aiaos-cli-execute domain action args)))
                    (princ (aiaos-cli--format-result result))
                    0)
                (error
                 (princ (format "Error: %s\n" (error-message-string err)))
                 1)))))
          ((string= domain "skill")
           (if (null rest)
               (progn
                 (princ "Usage: skill <action> [args]\n")
                 1)
             (let ((action (car rest))
                   (args (cdr rest)))
               (condition-case err
                   (let ((result (aiaos-cli-execute domain action args)))
                     (princ (aiaos-cli--format-result result))
                     0)
                 (error
                  (princ (format "Error: %s\n" (error-message-string err)))
                  1)))))
          ((string= domain "agent")
           (if (null rest)
               (progn
                 (princ "Usage: agent <message>\n")
                 1)
             (let ((message (mapconcat #'identity rest " ")))
               (condition-case err
                   (let ((result (aiaos-cli-agent-run message)))
                     (princ (aiaos-cli--format-result result))
                     0)
                 (error
                  (princ (format "Error: %s\n" (error-message-string err)))
                  1)))))
          (t
          (princ (format "Unknown command: %s\n" domain))
          (princ aiaos-cli--help-text)
          1))))))

(provide 'init)
;;; init.el ends here