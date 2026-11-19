;;; aiaos-cli-security.el --- Security Module for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, security, api-key

;; Security features for API key management and access control.

;;; Commentary:

;; This module provides security features for AIAOS-CLI:
;; - API key encryption and secure storage
;; - Access control lists (ACL)
;; - Input validation and sanitization
;; - Rate limiting

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'base64)

(defgroup aiaos-cli-security nil
  "AIAOS-CLI Security"
  :group 'aiaos-cli
  :prefix "aiaos-cli-security-")

;;; Configuration

(defcustom aiaos-cli-security-keychain-file
  (expand-file-name "~/.aiaos-cli-keychain")
  "File for storing encrypted API keys."
  :type 'file
  :group 'aiaos-cli-security)

(defcustom aiaos-cli-security-encrypt-method 'xor
  "Method for encrypting API keys.
Possible values: xor, base64"
  :type '(choice (const xor) (const base64))
  :group 'aiaos-cli-security)

;;; API Key Storage

(defvar aiaos-cli-security-keychain nil
  "Hash table of stored API keys (name . encrypted-key).")

;;; Initialize security system

(defun aiaos-cli-security-init ()
  "Initialize the security system."
  (load-keychain)
  (message "AIAOS-CLI Security initialized"))

;;; Key encryption

(defun aiaos-cli-security--encrypt (key)
  "Encrypt KEY using the configured method."
  (cl-case aiaos-cli-security-encrypt-method
    (xor (base64-encode-string (xor-string key "aiaos-cli-key")))
    (base64 (base64-encode-string key))
    (t (base64-encode-string key))))

(defun aiaos-cli-security--decrypt (encrypted-key)
  "Decrypt ENCRYPTED-KEY using the configured method."
  (cl-case aiaos-cli-security-encrypt-method
    (xor (xor-string (base64-decode-string encrypted-key) "aiaos-cli-key"))
    (base64 (base64-decode-string encrypted-key))
    (t (base64-decode-string encrypted-key))))

(defun xor-string (str key)
  "XOR STRING with KEY (repeating)."
  (let ((result "")
        (key-len (length key)))
    (dotimes (i (length str) result)
      (let ((c1 (aref str i))
            (c2 (aref key (mod i key-len))))
        (concat result (string (logxor c1 c2)))))))

;;; Key management

(defun aiaos-cli-security-store-key (name key)
  "Store an API KEY under NAME."
  (let ((encrypted (aiaos-cli-security--encrypt key)))
    (puthash name encrypted aiaos-cli-security-keychain)
    (save-keychain)
    (message "Stored key: %s" name)))

(defun aiaos-cli-security-retrieve-key (name)
  "Retrieve API key by NAME."
  (let ((encrypted (gethash name aiaos-cli-security-keychain)))
    (when encrypted
      (aiaos-cli-security--decrypt encrypted))))

(defun aiaos-cli-security-delete-key (name)
  "Delete API key by NAME."
  (remhash name aiaos-cli-security-keychain)
  (save-keychain)
  (message "Deleted key: %s" name))

;;; Key persistence

(defun load-keychain ()
  "Load the keychain from disk."
  (if (file-exists-p aiaos-cli-security-keychain-file)
      (with-temp-buffer
        (insert-file-contents aiaos-cli-security-keychain-file)
        (goto-char (point-min))
        (let ((data (json-read)))
          (setq aiaos-cli-security-keychain (make-hash-table :test 'equal))
          (dolist (pair data)
            (puthash (car pair) (cdr pair) aiaos-cli-security-keychain)))
        (message "Loaded %d keys" (hash-table-count aiaos-cli-security-keychain))
        t)
    (setq aiaos-cli-security-keychain (make-hash-table :test 'equal))
    nil))

(defun save-keychain ()
  "Save the keychain to disk."
  (let ((data '()))
    (maphash (lambda (k v) (push (cons k v) data))
             aiaos-cli-security-keychain)
    (with-temp-file aiaos-cli-security-keychain-file
      (insert (json-encode data)))
    (set-file-modes aiaos-cli-security-keychain-file #o600)
    (message "Saved %d keys" (length data))))

;;; Input validation

(defun aiaos-cli-security-validate-input (input type)
  "Validate INPUT against TYPE.
Returns t if valid, nil otherwise."
  (cl-case type
    (api-key
     (and (stringp input)
          (> (length input) 10)
          (string-match-p "^[a-zA-Z0-9_-]+$" input)))
    (url
     (and (stringp input)
          (string-match-p "^https?://" input)))
    (filename
     (and (stringp input)
          (not (string-match-p "[;&|`$(){}\\\\[\\\\]!]" input))))
    (t (and (stringp input) (> (length input) 0)))))

;;; Access control

(defconst aiaos-cli-security-default-acl
  '((llm . (read write))
    (memory . (read write))
    (filesystem . (read))
    (network . (read write)))
  "Default ACL.")

(defvar aiaos-cli-security-acl nil
  "Access control list.")

(defun aiaos-cli-security-init-acl ()
  "Initialize ACL."
  (setq aiaos-cli-security-acl aiaos-cli-security-default-acl))

(defun aiaos-cli-security-check-permission (resource operation)
  "Check if OPERATION is allowed on RESOURCE."
  (let ((entry (assq resource aiaos-cli-security-acl)))
    (if entry
        (memq operation (cdr entry))
      nil)))

;;; Rate limiting

(defvar aiaos-cli-security-rate-limits nil
  "Rate limit tracking (resource . (count . last-time)).")

(defcustom aiaos-cli-security-rate-limit-interval 60
  "Rate limit interval in seconds."
  :type 'integer
  :group 'aiaos-cli-security)

(defcustom aiaos-cli-security-rate-limit-max 100
  "Maximum requests per interval."
  :type 'integer
  :group 'aiaos-cli-security)

(defun aiaos-cli-security-check-rate-limit (resource)
  "Check if RESOURCE is within rate limits.
Returns t if allowed, nil if rate limited."
  (let* ((now (current-time))
         (entry (gethash resource aiaos-cli-security-rate-limits)))
    (if entry
        (let ((count (car entry))
              (last-time (cdr entry)))
          (if (> (float-time (time-subtract now last-time))
                 aiaos-cli-security-rate-limit-interval)
              ;; Reset counter
              (progn
                (puthash resource (cons 1 now) aiaos-cli-security-rate-limits)
                t)
            (if (< count aiaos-cli-security-rate-limit-max)
                (progn
                  (puthash resource (cons (1+ count) last-time)
                           aiaos-cli-security-rate-limits)
                  t)
              nil)))
      (puthash resource (cons 1 now) aiaos-cli-security-rate-limits)
      t)))

(provide 'aiaos-cli-security)

;;; aiaos-cli-security.el ends here
