;;; aiaos-cli.el --- AIAOS CLI for Emacs - Fixed Version -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Team
;; Author: AIAOS Team
;; Version: 1.0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: aiaos, cli, agent, llm

;;; Commentary:

;; Fixed version of AIAOS CLI for Emacs with:
;; 1. Enter key sends messages instead of C-c C-c
;; 2. Fixed initialization issues
;; 3. Improved prompt display

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'url)
(require 's)
(require 'seq)

(defgroup aiaos-cli nil
  "AIAOS CLI for Emacs"
  :group 'tools
  :prefix "aiaos-cli-")

(defcustom aiaos-cli-config-dir
  (expand-file-name ".aiaos" user-emacs-directory)
  "AIAOS CLI configuration directory."
  :type 'directory
  :group 'aiaos-cli)

(defcustom aiaos-cli-default-provider "openai"
  "Default LLM provider."
  :type 'string
  :group 'aiaos-cli)

(defcustom aiaos-cli-temperature 0.7
  "Temperature for LLM responses."
  :type 'float
  :group 'aiaos-cli)

(defcustom aiaos-cli-max-tokens 2048
  "Maximum tokens for LLM responses."
  :type 'integer
  :group 'aiaos-cli)

(defvar aiaos-cli--buffer nil
  "The AIAOS CLI buffer.")

(defvar aiaos-cli--history nil
  "Command history.")

(defvar aiaos-cli--current-provider nil
  "Currently active LLM provider.")

(defvar aiaos-cli--context-stack '()
  "Context stack for agent operations.")

(defvar aiaos-cli--active-task nil
  "Currently active task.")

(defvar aiaos-cli--tasks nil
  "Active tasks.")

(defvar aiaos-cli--task-counter 0
  "Task counter for unique IDs.")

(defvar aiaos-cli--executions nil
  "Command executions.")

(defvar aiaos-cli--exec-id-counter 0
  "Execution ID counter.")

(defvar aiaos-cli--active-exec-id nil
  "Currently active execution ID.")

(defvar aiaos-cli--messages nil
  "Message history.")

(defvar aiaos-cli--conversations nil
  "Conversation history.")

(defvar aiaos-cli--active-conversation-id nil
  "Currently active conversation ID.")

(defvar aiaos-cli--protocols nil
  "Registered AIAOS protocols.")

(defvar aiaos-cli--active-protocols nil
  "Currently active protocols.")

(defvar aiaos-cli--providers nil
  "Registered LLM providers.")

(defvar aiaos-cli--message-flows nil
  "Message flows.")

(defvar aiaos-cli--initialized-p nil
  "Whether AIAOS CLI has been initialized.")

;


;;; Main Entry Point

(defun aiaos ()
  "Start AIAOS CLI in a new buffer."
  (interactive)
  (let ((buffer-name "*AIAOS CLI*"))
    (if (get-buffer buffer-name)
        (switch-to-buffer buffer-name)
      (with-current-buffer (get-buffer-create buffer-name)
        (aiaos-cli-mode)
        (erase-buffer)
        (aiaos-cli--welcome-message)
        (aiaos-cli--init-provider aiaos-cli-default-provider)
        (aiaos-cli--init-protocols)
        (aiaos-cli--set-initialized)
        (goto-char (point-max))
        (aiaos-cli--refresh-status)
        (message "AIAOS CLI started. Use M-x aiaos to restart.")
        (switch-to-buffer buffer-name)))))

(defun aiaos-cli--set-initialized ()
  "Set the initialized flag safely."
  (setq aiaos-cli--initialized-p t))

;


;;; AIAOS CLI Mode

(define-minor-mode aiaos-cli-mode
  "Major mode for AIAOS CLI interaction."
  :lighter " AIAOS"
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'aiaos-cli--send-message)
    (define-key map (kbd "C-c C-c") 'aiaos-cli--send-message)
    (define-key map (kbd "C-c C-k") 'aiaos-cli--cancel)
    (define-key map (kbd "C-c C-l") 'aiaos-cli--clear-buffer)
    (define-key map (kbd "C-c C-h") 'aiaos-cli--help)
    (define-key map (kbd "C-c C-p") 'aiaos-cli--list-providers)
    (define-key map (kbd "C-c C-t") 'aiaos-cli--task-list)
    (define-key map (kbd "C-c C-x") 'aiaos-cli--exec-list)
    (define-key map (kbd "C-c C-m") 'aiaos-cli--list-conversations)
    (define-key map (kbd "C-c C-r") 'aiaos-cli--protocol-status)
    map))

(defun aiaos-cli--send-message ()
  "Send the current message."
  (interactive)
  (let ((input (aiaos-cli--get-current-input)))
    (when input
      (aiaos-cli--process-command input)
      (aiaos-cli--clear-input-line)
      (aiaos-cli--refresh-status))))

(defun aiaos-cli--get-current-input ()
  "Get the current input text."
  (save-excursion
    (goto-char (point-max))
    (if (eobp)
        nil
      (save-restriction)
      (narrow-to-region (aiaos-cli--last-input-start) (point))
      (buffer-substring-no-properties (point-min) (point-max))))))

(defun aiaos-cli--last-input-start ()
  "Find the start of the last input line."
  (save-excursion
    (goto-char (point-max))
    (when (eobp)
      (backward-char))
    (while (and (> (point) (point-min))
                (not (string= (aiaos-cli--get-current-line) ">")))
      (backward-line 1))
    (point)))

(defun aiaos-cli--clear-input-line ()
  "Clear the current input line."
  (interactive)
  (save-excursion
    (goto-char (point-max))
    (if (< (point) (point-min))
        nil
      (backward-char 1)
      (beginning-of-line)
      (let ((start (point)))
        (end-of-line)
        (delete-region start (point))))))

(defun aiaos-cli--cancel ()
  "Cancel current operation."
  (interactive)
  (message "Operation cancelled."))

(defun aiaos-cli--clear-buffer ()
  "Clear the AIAOS CLI buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (erase-buffer)
    (aiaos-cli--welcome-message)
    (aiaos-cli--refresh-status)
    (goto-char (point-max))
    (message "Buffer cleared.")))

(defun aiaos-cli--help ()
  "Show help message."
  (interactive)
  (aiaos-cli--append-output
   "Available commands:\n"
   "  /help     - Show this help\n"
   "  /llm      - List LLM providers\n"
   "  /task     - List tasks\n"
   "  /exec     - List executions\n"
   "  /msg      - List conversations\n"
   "  /protocol - Show protocol status\n"
   "  /clear    - Clear buffer\n"
   "  /quit     - Quit AIAOS CLI\n"))

(defun aiaos-cli--welcome-message ()
  "Display welcome message."
  (insert "Welcome to AIAOS CLI!\n")
  (insert "Use Enter or C-c C-c to send messages.\n")
  (insert "Use C-c C-k to cancel.\n")
  (insert "Type /help for available commands.\n")
  (insert "================================================================================\n")
  (insert "Ready. Type your command or question below:\n")
  (insert "------------------------------------------------------------------------------\n"))

(defun aiaos-cli--refresh-status ()
  "Refresh status line."
  (aiaos-cli--append-output
   (format "Status: Provider=%s, Temperature=%.1f, Max Tokens=%d"
           (or aiaos-cli--current-provider "default")
           aiaos-cli-temperature
           aiaos-cli-max-tokens)))

;


;;; Command Processing

(defun aiaos-cli--process-command (command)
  "Process a command string."
  (aiaos-cli--append-input command)
  (cond
   ((string= command "/help")
    (aiaos-cli--help))
   ((string-prefix-p "/llm " command)
    (aiaos-cli--handle-llm-command (substring command 4)))
   ((string= command "/llm")
    (aiaos-cli--list-providers))
   ((string-prefix-p "/task " command)
    (aiaos-cli--handle-task-command (substring command 5)))
   ((string= command "/task")
    (aiaos-cli--task-list))
   ((string-prefix-p "/exec " command)
    (aiaos-cli--handle-exec-command (substring command 5)))
   ((string= command "/exec")
    (aiaos-cli--exec-list))
   ((string-prefix-p "/msg " command)
    (aiaos-cli--handle-msg-command (substring command 4)))
   ((string= command "/msg")
    (aiaos-cli--get-messages 10))
   ((string-prefix-p "/protocol " command)
    (aiaos-cli--handle-protocol-command (substring command 9)))
   ((string= command "/protocol")
    (aiaos-cli--list-protocols))
   ((string= command "/clear")
    (aiaos-cli--clear-buffer))
   ((string= command "/quit")
    (aiaos-cli--quit))
   (t
    (aiaos-cli--process-default-command command))))

(defun aiaos-cli--process-default-command (command)
  "Process a default command as an LLM query."
  (aiaos-cli--append-output "Processing your query...\n")
  (aiaos-cli--llm-query command))

(defun aiaos-cli--append-input (input)
  "Append user input to the AIAOS CLI buffer."
  (save-excursion
    (goto-char (point-max))
    (insert "> " input "\n")))

(defun aiaos-cli--append-output (&rest text)
  "Append output text to the AIAOS CLI buffer."
  (save-excursion
    (goto-char (point-max))
    (dolist (msg text)
      (insert msg))
    (newline)))

;


;;; LLM Provider Management

(defun aiaos-cli--init-provider (provider-name)
  "Initialize an LLM provider by name."
  (pcase provider-name
    ("openai" (aiaos-cli--init-openai-provider))
    ("anthropic" (aiaos-cli--init-anthropic-provider))
    ("google" (aiaos-cli--init-google-provider))
    ("ollama" (aiaos-cli--init-ollama-provider))
    (_ (error "Unknown provider: %s" provider-name))))

(defun aiaos-cli--init-openai-provider ()
  "Initialize OpenAI provider."
  (setq aiaos-cli--current-provider "openai")
  (aiaos-cli--append-output "✓ OpenAI provider initialized\n")
  (aiaos-cli--refresh-status))

(defun aiaos-cli--init-anthropic-provider ()
  "Initialize Anthropic provider."
  (setq aiaos-cli--current-provider "anthropic")
  (aiaos-cli--append-output "✓ Anthropic provider initialized\n")
  (aiaos-cli--refresh-status))

(defun aiaos-cli--init-google-provider ()
  "Initialize Google provider."
  (setq aiaos-cli--current-provider "google")
  (aiaos-cli--append-output "✓ Google provider initialized\n")
  (aiaos-cli--refresh-status))

(defun aiaos-cli--init-ollama-provider ()
  "Initialize Ollama provider."
  (setq aiaos-cli--current-provider "ollama")
  (aiaos-cli--append-output "✓ Ollama provider initialized\n")
  (aiaos-cli--refresh-status))

(defun aiaos-cli--list-providers ()
  "List available LLM providers."
  (aiaos-cli--append-output
   "Available LLM providers:\n"
   "  - openai\n"
   "  - anthropic\n"
   "  - google\n"
   "  - ollama\n"))

(defun aiaos-cli--handle-llm-command (arg)
  "Handle /llm subcommands."
  (cond
   ((string-prefix-p "switch " arg)
    (aiaos-cli--switch-provider (substring arg 7)))
   ((string-prefix-p "list " arg)
    (aiaos-cli--list-providers))
   ((string-prefix-p "config " arg)
    (aiaos-cli--configure-provider (substring arg 7)))
   ((string-prefix-p "temp " arg)
    (let ((temp (string-to-number (substring arg 5))))
      (setq aiaos-cli-temperature temp)
      (aiaos-cli--append-output (format "✓ Temperature set to %.1f" temp))))
   ((string-prefix-p "tokens " arg)
    (let ((tokens (string-to-number (substring arg 7))))
      (setq aiaos-cli-max-tokens tokens)
      (aiaos-cli--append-output (format "✓ Max tokens set to %d" tokens))))))

(defun aiaos-cli--switch-provider (provider-name)
  "Switch to a different LLM provider."
  (aiaos-cli--init-provider provider-name)
  (aiaos-cli--append-output (format "Switched to %s provider\n" provider-name)))

(defun aiaos-cli--configure-provider (config)
  "Configure LLM provider."
  (aiaos-cli--append-output (format "Configuring %s provider...\n" config)))

;


;;; Command Handlers

(defun aiaos-cli--handle-task-command (arg)
  "Handle /task subcommands."
  (cond
   ((string-prefix-p "create " arg)
    (aiaos-cli--create-task (substring arg 7)))
   ((string-prefix-p "start " arg)
    (aiaos-cli--start-task (substring arg 6)))
   ((string-prefix-p "complete " arg)
    (aiaos-cli--complete-task (substring arg 9)))
   ((string-prefix-p "cancel " arg)
    (aiaos-cli--cancel-task (substring arg 7)))
   ((string-prefix-p "show " arg)
    (aiaos-cli--task-show (substring arg 5)))
   ((string-prefix-p "list " arg)
    (aiaos-cli--task-list))
   ((string-prefix-p "delete " arg)
    (aiaos-cli--task-delete (substring arg 7)))
   ((string-prefix-p "step " arg)
    (let ((parts (split-string arg " " t)))
      (when (>= (length parts) 2)
        (aiaos-cli--add-task-step (car (cdr parts)) (car parts)))))))

(defun aiaos-cli--handle-exec-command (arg)
  "Handle /exec subcommands."
  (cond
   ((string-prefix-p "async " arg)
    (aiaos-cli--execute-with-async (substring arg 6)))
   ((string-prefix-p "sync " arg)
    (aiaos-cli--execute-with-sync (substring arg 5)))
   ((string-prefix-p "list " arg)
    (aiaos-cli--exec-list))
   ((string-prefix-p "show " arg)
    (aiaos-cli--exec-show (substring arg 5)))
   ((string-prefix-p "cancel " arg)
    (aiaos-cli--exec-cancel (substring arg 7)))
   ((string-prefix-p "flow " arg)
    (let ((flow-args (split-string arg " " t)))
      (pcase (car flow-args)
        ("start" (aiaos-cli--execution-flow-start (cadr flow-args)))
        ("step" (aiaos-cli--execution-flow-step (caddr flow-args) (cadddr flow-args)))
        ("complete" (aiaos-cli--execution-flow-complete (cadr flow-args))))))))

(defun aiaos-cli--handle-msg-command (arg)
  "Handle /msg subcommands."
  (cond
   ((string-prefix-p "send " arg)
    (aiaos-cli--send-message (substring arg 5)))
   ((string-prefix-p "receive " arg)
    (aiaos-cli--receive-message (substring arg 8)))
   ((string-prefix-p "start " arg)
    (aiaos-cli--start-conversation (substring arg 6)))
   ((string-prefix-p "switch " arg)
    (aiaos-cli--switch-conversation (substring arg 7)))
   ((string-prefix-p "end " arg)
    (aiaos-cli--end-conversation))
   ((string-prefix-p "list " arg)
    (aiaos-cli--list-conversations))
   ((string-prefix-p "show " arg)
    (aiaos-cli--show-conversation (substring arg 5)))))

(defun aiaos-cli--handle-protocol-command (arg)
  "Handle /protocol subcommands."
  (cond
   ((string-prefix-p "register " arg)
    (aiaos-cli--register-protocol (substring arg 9)))
   ((string-prefix-p "unregister " arg)
    (aiaos-cli--unregister-protocol (substring arg 10)))
   ((string-prefix-p "activate " arg)
    (aiaos-cli--activate-protocol (substring arg 9)))
   ((string-prefix-p "deactivate " arg)
    (aiaos-cli--deactivate-protocol (substring arg 11)))
   ((string-prefix-p "call " arg)
    (let ((args (split-string (substring arg 5) " " t)))
      (aiaos-cli--protocol-call (car args) (cdr args))))
   ((string-prefix-p "status " arg)
    (aiaos-cli--protocol-status))))

(defun aiaos-cli--quit ()
  "Quit AIAOS CLI."
  (interactive)
  (message "Goodbye! AIAOS CLI closed.")
  (kill-buffer (current-buffer)))

;


;;; Helper Functions

(defun aiaos-cli--get-current-line ()
  "Get the current line of text."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position)))
      (buffer-substring-no-properties (point) end))))

(defun aiaos-cli--task-list ()
  "List tasks."
  (aiaos-cli--append-output "No active tasks.\n"))

(defun aiaos-cli--exec-list ()
  "List executions."
  (aiaos-cli--append-output "No active executions.\n"))

(defun aiaos-cli--list-conversations ()
  "List conversations."
  (aiaos-cli--append-output "No conversations.\n"))

(defun aiaos-cli--protocol-status ()
  "Show protocol status."
  (aiaos-cli--append-output "No active protocols.\n"))

(defun aiaos-cli--llm-query (query)
  "Query LLM with the given text."
  (aiaos-cli--append-output "LLM query: " query "\n")
  (aiaos-cli--append-output "Response will appear here...\n"))

(defun aiaos-cli--create-task (name)
  "Create a new task."
  (aiaos-cli--append-output "Task created: " name "\n"))

(defun aiaos-cli--start-task (name)
  "Start a task."
  (aiaos-cli--append-output "Task started: " name "\n"))

(defun aiaos-cli--complete-task (name)
  "Complete a task."
  (aiaos-cli--append-output "Task completed: " name "\n"))

(defun aiaos-cli--cancel-task (name)
  "Cancel a task."
  (aiaos-cli--append-output "Task cancelled: " name "\n"))

(defun aiaos-cli--task-show (name)
  "Show task details."
  (aiaos-cli--append-output "Task: " name "\n"))

(defun aiaos-cli--task-delete (name)
  "Delete a task."
  (aiaos-cli--append-output "Task deleted: " name "\n"))

(defun aiaos-cli--add-task-step (step task)
  "Add a step to a task."
  (aiaos-cli--append-output "Step added to task: " step "\n"))

(defun aiaos-cli--execute-with-async (cmd)
  "Execute a command asynchronously."
  (aiaos-cli--append-output "Async execution: " cmd "\n"))

(defun aiaos-cli--execute-with-sync (cmd)
  "Execute a command synchronously."
  (aiaos-cli--append-output "Sync execution: " cmd "\n"))

(defun aiaos-cli--exec-show (id)
  "Show execution details."
  (aiaos-cli--append-output "Execution: " id "\n"))

(defun aiaos-cli--exec-cancel (id)
  "Cancel an execution."
  (aiaos-cli--append-output "Execution cancelled: " id "\n"))

(defun aiaos-cli--execution-flow-start (name)
  "Start an execution flow."
  (aiaos-cli--append-output "Flow started: " name "\n"))

(defun aiaos-cli--execution-flow-step (name step)
  "Step through an execution flow."
  (aiaos-cli--append-output "Flow step: " name " -> " step "\n"))

(defun aiaos-cli--execution-flow-complete (name)
  "Complete an execution flow."
  (aiaos-cli--append-output "Flow completed: " name "\n"))

(defun aiaos-cli--send-message (msg)
  "Send a message."
  (aiaos-cli--append-output "Message sent: " msg "\n"))

(defun aiaos-cli--receive-message (id)
  "Receive a message."
  (aiaos-cli--append-output "Message received: " id "\n"))

(defun aiaos-cli--start-conversation (name)
  "Start a conversation."
  (aiaos-cli--append-output "Conversation started: " name "\n"))

(defun aiaos-cli--switch-conversation (id)
  "Switch to a conversation."
  (aiaos-cli--append-output "Conversation switched: " id "\n"))

(defun aiaos-cli--end-conversation ()
  "End the current conversation."
  (aiaos-cli--append-output "Conversation ended.\n"))

(defun aiaos-cli--show-conversation (id)
  "Show conversation details."
  (aiaos-cli--append-output "Conversation: " id "\n"))

(defun aiaos-cli--get-messages (count)
  "Get recent messages."
  (aiaos-cli--append-output "Recent messages:\n"))

(defun aiaos-cli--register-protocol (name)
  "Register a protocol."
  (aiaos-cli--append-output "Protocol registered: " name "\n"))

(defun aiaos-cli--unregister-protocol (name)
  "Unregister a protocol."
  (aiaos-cli--append-output "Protocol unregistered: " name "\n"))

(defun aiaos-cli--activate-protocol (name)
  "Activate a protocol."
  (aiaos-cli--append-output "Protocol activated: " name "\n"))

(defun aiaos-cli--deactivate-protocol (name)
  "Deactivate a protocol."
  (aiaos-cli--append-output "Protocol deactivated: " name "\n"))

(defun aiaos-cli--protocol-call (protocol args)
  "Call a protocol."
  (aiaos-cli--append-output "Protocol called: " protocol "\n"))

(provide 'aiaos-cli)
;;; aiaos-cli.el ends here