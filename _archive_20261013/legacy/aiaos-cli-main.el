;;; aiaos-cli-main.el --- Main Entry Point and Command Processing -*- lexical-binding: t; -*-

;; This is the main entry point that integrates all AIAOS CLI modules.

(require 'aiaos-cli)
(require 'aiaos-cli-llm)
(require 'aiaos-cli-task)
(require 'aiaos-cli-exec)
(require 'aiaos-cli-msg)
(require 'aiaos-cli-protocol)

(provide 'aiaos-cli-main)


;;; Enhanced Command Processing

(defun aiaos-cli--process-command (command)
  "Process a command string with full AIAOS CLI support."
  (aiaos-cli--append-input command)
  
  (cond
    ;; Help commands
    ((string= command "/help")
     (aiaos-cli--help))
    
    ;; LLM provider management
    ((string-prefix-p "/llm " command)
     (aiaos-cli--handle-llm-command (substring command 4)))
    ((string= command "/llm")
     (aiaos-cli--list-providers))
    
    ;; Task management
    ((string-prefix-p "/task " command)
     (aiaos-cli--handle-task-command (substring command 5)))
    ((string= command "/task")
     (aiaos-cli--task-list))
    
    ;; Command execution
    ((string-prefix-p "/exec " command)
     (aiaos-cli--handle-exec-command (substring command 5)))
    ((string= command "/exec")
     (aiaos-cli--exec-list))
    
    ;; Message flow
    ((string-prefix-p "/msg " command)
     (aiaos-cli--handle-msg-command (substring command 4)))
    ((string= command "/msg")
     (aiaos-cli--get-messages 10))
    
    ;; Protocol management
    ((string-prefix-p "/protocol " command)
     (aiaos-cli--handle-protocol-command (substring command 9)))
    ((string= command "/protocol")
     (aiaos-cli--list-protocols))
    
    ;; Clear buffer
    ((string= command "/clear")
     (aiaos-cli--clear-buffer))
    
    ;; Quit
    ((string= command "/quit")
     (aiaos-cli--quit))
    
    ;; Default: treat as LLM query
    (t
     (aiaos-cli--process-default-command command))))

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
       (setq aiaos-cli--temperature temp)
       (aiaos-cli--append-output (format "✓ Temperature set to %.1f" temp))))
    ((string-prefix-p "tokens " arg)
     (let ((tokens (string-to-number (substring arg 7))))
       (setq aiaos-cli--max-tokens tokens)
       (aiaos-cli--append-output (format "✓ Max tokens set to %d" tokens)))))

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
     (aiaos-cli--add-task-step (substring arg 5) (car (split-string arg " " t)))))

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
         ("complete" (aiaos-cli--execution-flow-complete (cadr flow-args)))))))

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

(defun aiaos-cli--process-default-command (command)
  "Process a default command as an LLM query."
  (aiaos-cli--append-output "Processing your query...\n")
  (aiaos-cli--llm-query command))


;;; Main Entry Point

(defun aiaos-cli--init ()
  "Initialize AIAOS CLI environment."
  (interactive)
  (aiaos-cli--init-provider aiaos-cli-default-provider)
  (aiaos-cli--load-provider-config)
  (aiaos-cli--register-protocol "http" "HTTP/HTTPS Protocol")
  (aiaos-cli--register-protocol "mqtt" "MQTT Protocol")
  (aiaos-cli--register-protocol "websocket" "WebSocket Protocol")
  (aiaos-cli--register-protocol "grpc" "gRPC Protocol")
  (aiaos-cli--register-protocol "tcp" "TCP Protocol")
  (aiaos-cli--register-protocol "udp" "UDP Protocol"))

(defun aiaos-cli--quit ()
  "Exit AIAOS CLI."
  (interactive)
  (aiaos-cli--append-output "Goodbye! AIAOS CLI exited.")
  (delete-buffer)
  (message "AIAOS CLI exited."))


;;; Enhanced Welcome Message

(defun aiaos-cli--welcome-message ()
  "Display enhanced welcome message."
  (insert "================================================================================\n")
  (insert "                    AIAOS CLI for Emacs v1.0.0\n")
  (insert "================================================================================\n")
  (insert "\n")
  (insert "Welcome to AIAOS CLI - The Ultimate Agent Interface for Emacs\n")
  (insert "\n")
  (insert "This client provides full support for all AIAOS protocols, operations,\n")
  (insert "message flows, command execution flows, and task iteration flows.\n")
  (insert "\n")
  (insert "Quick Start:\n")
  (insert "  1. Send a message to the LLM (just type and press Enter)\n")
  (insert "  2. Use /help to see all available commands\n")
  (insert "  3. Manage tasks, execute commands, and handle protocols\n")
  (insert "\n")
  (insert "Available Modules:\n")
  (insert "  • LLM Providers: OpenAI, Anthropic, Google, Ollama\n")
  (insert "  • Task Management: Create, start, complete, cancel tasks\n")
  (insert "  • Command Execution: Async/sync command execution\n")
  (insert "  • Message Flows: Conversations and messaging\n")
  (insert "  • Protocol Support: HTTP, MQTT, WebSocket, gRPC, TCP, UDP\n")
  (insert "\n")
  (insert "Commands:\n")
  (insert "  /help        - Show this help message\n")
  (insert "  /llm         - Manage LLM providers\n")
  (insert "  /task        - Manage tasks\n")
  (insert "  /exec        - Execute commands\n")
  (insert "  /msg         - Send messages\n")
  (insert "  /protocol    - Manage protocols\n")
  (insert "  /clear       - Clear buffer\n")
  (insert "  /quit        - Exit AIAOS CLI\n")
  (insert "\n")
  (insert "Use C-c C-c to execute, C-c C-k to cancel.\n")
  (insert "================================================================================\n\n")
  (insert "Ready. Type your command or question below:\n")
  (insert "-----------------------------------------------------------------------------\n"))


;;; Exported Functions

(provide 'aiaos-cli-main)

;;; aiaos-cli-main.el ends here
