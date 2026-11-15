;;; aiaos-agent-adapter.el --- Enterprise-grade Agent Adapter for Emacs/AIAOS -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS
;; Author: AIAOS Agent Framework
;; Version: 1.0.0
;; Keywords: aiaos, agent, emacs, llm, adapter

(require 'cl-lib)
(require 'json)
(require 'aiaos-core)
(require 'aiaos-config)

;;; Commentary:
;; Enterprise-grade agent adapter for Emacs/AIAOS.
;; Features:
;; 1. Environment detection & adaptation
;; 2. Agent capability enhancement
;; 3. LLM integration optimization
;; 4. Self-repair mechanism
;; 5. Performance monitoring
;; 6. Complete testing framework

;;; Code:

;; ============================================================
;; Section 1: Environment Detection & Adaptation
;; ============================================================

(defgroup aiaos-agent-adapter nil
  "AIAOS Agent Adapter configuration."
  :group 'aiaos-cli)

(defcustom aiaos-agent-adapter-log-level 'info
  "Logging level for agent adapter."
  :type '(choice (const debug) (const info) (const warn) (const error))
  :group 'aiaos-agent-adapter)

(defcustom aiaos-agent-adapter-max-retries 3
  "Maximum retries for failed operations."
  :type 'integer
  :group 'aiaos-agent-adapter)

(defcustom aiaos-agent-adapter-timeout 30
  "Timeout for LLM requests in seconds."
  :type 'integer
  :group 'aiaos-agent-adapter)

;;; Environment Detection

(defun aiaos-agent-adapter-detect-emacs-version ()
  "Detect Emacs version and return structured version info."
  (let ((version-string (emacs-version))
        (version-list (version-to-list (emacs-version))))
    `((version-string . ,version-string)
      (major . ,(car version-list))
      (minor . ,(cadr version-list))
      (patch . ,(caddr version-list))
      (features . ,(list :gui ,window-system
                         :daemon ,daemon-mode
                         :batch ,noninteractive)))))

(defun aiaos-agent-adapter-detect-load-path ()
  "Detect current load-path and return relevant entries."
  (let ((relevant '()))
    (dolist (path load-path relevant)
      (when (string-match-p "aiaos" path)
        (push path relevant)))))

(defun aiaos-agent-adapter-detect-modules ()
  "Detect loaded AIAOS modules and their status."
  (let ((modules '()))
    (dolist (mod '(aiaos-core aiaos-config aiaos-cli aiaos-browser aiaos-sync aiaos-report))
      (let ((feature (intern (symbol-name mod))))
        (push (cons (symbol-name mod)
                    (if (featurep feature)
                        (format "loaded (version: %s)" (aiaos-agent-adapter-get-module-version mod))
                        "not loaded"))
              modules)))
    (reverse modules)))

(defun aiaos-agent-adapter-get-module-version (mod-name)
  "Get version of module MOD-NAME if available."
  (condition-case nil
      (let ((version-var (intern (format "%s-version" mod-name))))
        (when (boundp version-var)
          (symbol-value version-var)))
    (error "unknown")))

;; ============================================================
;; Section 2: Agent Capability Enhancement
;; ============================================================

;; --- Message Format Standardization ---

(defclass aiaos-agent-message ()
  ((role :initarg :role :type string :protection :read-write)
   (content :initarg :content :type string :protection :read-write)
   (timestamp :initarg :timestamp :type string :protection :read-write)
   (metadata :initarg :metadata :type list :protection :read-write))
  "Standardized agent message format.")

(cl-defmethod aiaos-agent-message-to-json ((msg aiaos-agent-message))
  "Convert message MSG to JSON string."
  (json-encode
   `((role . ,(oref msg role))
     (content . ,(oref msg content))
     (timestamp . ,(oref msg timestamp))
     (metadata . ,(oref msg metadata)))))

(cl-defmethod aiaos-agent-message-from-json ((json-string string))
  "Create message from JSON string."
  (let ((data (json-read-from-string json-string)))
    (aiaos-agent-message
     :role (alist-get 'role data)
     :content (alist-get 'content data)
     :timestamp (alist-get 'timestamp data)
     :metadata (alist-get 'metadata data))))

;; --- Error Code Standardization ---

(defconst aiaos-agent-error-codes
  '((:network-error . "Network connection failed")
    (:auth-error . "Authentication failed")
    (:rate-limit . "Rate limit exceeded")
    (:invalid-request . "Invalid request format")
    (:timeout . "Request timed out")
    (:empty-response . "Empty response from LLM")
    (:model-not-found . "Model not found")
    (:server-error . "Internal server error")
    (:unknown-error . "Unknown error"))
  "Standard error code mapping.")

(defun aiaos-agent-error-code-message (code)
  "Get error message for error CODE."
  (cdr (assq code aiaos-agent-error-codes)))

(defclass aiaos-agent-error ()
  ((code :initarg :code :type symbol :protection :read-write)
   (message :initarg :message :type string :protection :read-write)
   (details :initarg :details :type list :protection :read-write)
   (timestamp :initarg :timestamp :type string :protection :read-write))
  "Standardized agent error format.")

(cl-defmethod aiaos-agent-error-to-string ((err aiaos-agent-error))
  "Convert error ERR to string representation."
  (format "[%s] %s (details: %S)"
          (oref err code)
          (oref err message)
          (oref err details)))

;; --- Empty Message Detection ---

(defun aiaos-agent-adapter-is-empty-response (response)
  "Check if RESPONSE is an empty or invalid LLM response."
  (or (null response)
      (string-empty-p response)
      (and (listp response)
           (null (cdr response)))
      (and (stringp response)
           (string-match-p "^[[:space:]]*$" response))
      (and (listp response)
           (let ((choices (alist-get 'choices response)))
             (or (null choices)
                 (and (listp choices)
                      (= (length choices) 0))
                 (and (listp choices)
                  (let ((first-choice (car choices)))
                    (or (null first-choice)
                        (null (alist-get 'text first-choice))
                        (string-empty-p (alist-get 'text first-choice))))))))))

;; ============================================================
;; Section 3: LLM Integration Optimization
;; ============================================================

(provide 'aiaos-agent-adapter)