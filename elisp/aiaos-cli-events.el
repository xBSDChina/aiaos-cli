;;; aiaos-cli-events.el --- Event System for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, events, pubsub

;; Event system for decoupled component communication.

;;; Commentary:

;; This module provides a publish/subscribe event system for AIAOS-CLI.
;; Components can subscribe to events and react to state changes.

;;; Code:

(require 'cl-lib)

(defgroup aiaos-cli-events nil
  "AIAOS-CLI Event System"
  :group 'aiaos-cli
  :prefix "aiaos-cli-events-")

;;; Event types

(defconst aiaos-cli-events-types
  '(agent-started
    agent-stopped
    agent-error
    agent-idle
    agent-busy
    task-started
    task-completed
    task-failed
    llm-request
    llm-response
    llm-error
    provider-changed
    config-updated
    memory-saved
    memory-loaded
    buffer-changed
    window-changed)
  "List of all event types.")

;;; Event structure

(cl-defstruct aiaos-cli-event
  "Event structure."
  type        ; event type (symbol)
  timestamp   ; when the event was created
  source      ; source component
  data        ; event payload
  id)         ; unique event id

;;; Event bus

(defvar aiaos-cli-events-subscribers nil)
"Alist of (event-type . handler-list)."

(defvar aiaos-cli-events-event-id-counter 0)
"Counter for generating unique event IDs."

;;; Event bus management

(defun aiaos-cli-events-publish (type &optional source data)
  "Publish an event of TYPE from SOURCE with DATA."
  (let* ((event (make-aiaos-cli-event
                 :type type
                 :timestamp (current-time)
                 :source source
                 :data data
                 :id (cl-incf aiaos-cli-events-event-id-counter))))
    (aiaos-cli-events--dispatch event)
    event))

(defun aiaos-cli-events--dispatch (event)
  "Dispatch EVENT to all subscribers."
  (let ((handlers (cdr (assq (aiaos-cli-event-type event)
                            aiaos-cli-events-subscribers))))
    (dolist (handler handlers)
      (condition-case err
          (funcall handler event)
        (error
         (message "Event handler error: %s" (error-message-string err)))))))

(defun aiaos-cli-events-subscribe (type handler)
  "Subscribe HANDLER to events of TYPE."
  (let ((entry (assq type aiaos-cli-events-subscribers)))
    (if entry
        (setcdr entry (cons handler (cdr entry)))
      (setq aiaos-cli-events-subscribers
            (cons (cons type (list handler))
                  aiaos-cli-events-subscribers))))
  (message "Subscribed to %s" type))

(defun aiaos-cli-events-unsubscribe (type handler)
  "Unsubscribe HANDLER from events of TYPE."
  (let ((entry (assq type aiaos-cli-events-subscribers)))
    (when entry
      (setcdr entry (delete handler (cdr entry)))
      (when (null (cdr entry))
        (setq aiaos-cli-events-subscribers
              (delq entry aiaos-cli-events-subscribers))))))

;;; Convenience functions

(defun aiaos-cli-events-emit-agent-started (source)
  "Emit agent-started event."
  (aiaos-cli-events-publish 'agent-started source nil))

(defun aiaos-cli-events-emit-agent-stopped (source)
  "Emit agent-stopped event."
  (aiaos-cli-events-publish 'agent-stopped source nil))

(defun aiaos-cli-events-emit-agent-error (source error)
  "Emit agent-error event."
  (aiaos-cli-events-publish 'agent-error source (list :error error)))

(defun aiaos-cli-events-emit-llm-response (source response)
  "Emit llm-response event."
  (aiaos-cli-events-publish 'llm-response source (list :response response)))

(defun aiaos-cli-events-emit-llm-error (source error)
  "Emit llm-error event."
  (aiaos-cli-events-publish 'llm-error source (list :error error)))

;;; Initialize event system

(aiaos-cli-events-publish 'system-initialized 'events-system
                          (list :version "1.0.0"))

(provide 'aiaos-cli-events)

;;; aiaos-cli-events.el ends here