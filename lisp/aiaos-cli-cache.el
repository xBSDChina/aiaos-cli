;;; aiaos-cli-cache.el --- Caching for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, cache, aiaos

;; Caching system for AIAOS-CLI.

;;; Commentary:

;; This module provides caching capabilities:
;;   * aiaos-cli-cache-get - Get cached value
;;   * aiaos-cli-cache-set - Set cached value
;;   * aiaos-cli-cache-invalidate - Invalidate cache entry
;;   * aiaos-cli-cache-clear - Clear all cache

;;; Code:

(require 'cl-lib)
(require 'timer)

(defgroup aiaos-cli-cache nil
  "AIAOS-CLI Cache"
  :group 'aiaos-cli
  :prefix "aiaos-cli-cache-")

(defcustom aiaos-cli-cache-default-ttl 300
  "Default cache TTL in seconds."
  :type 'integer
  :group 'aiaos-cli-cache)

(cl-defstruct (aiaos-cli-cache-entry
  (:constructor make-aiaos-cli-cache-entry)
  (:copier copy-aiaos-cli-cache-entry))
  key value expiry)

(defconst aiaos-cli-cache (make-hash-table :test 'equal)
  "Cache hash table.")

(defun aiaos-cli-cache-get (key)
  "Get cached value for KEY."
  (let ((entry (gethash key aiaos-cli-cache)))
    (when entry
      (if (> (float-time) (aiaos-cli-cache-entry-expiry entry))
          (progn
            (remhash key aiaos-cli-cache)
            nil)
        (aiaos-cli-cache-entry-value entry)))))

(defun aiaos-cli-cache-set (key value &optional ttl)
  "Set cached KEY to VALUE with TTL."
  (let ((expiry (if ttl (+ (float-time) ttl) (+ (float-time) aiaos-cli-cache-default-ttl))))
    (puthash key (make-aiaos-cli-cache-entry :key key :value value :expiry expiry) aiaos-cli-cache)))

(defun aiaos-cli-cache-invalidate (key)
  "Invalidate cache entry for KEY."
  (remhash key aiaos-cli-cache))

(defun aiaos-cli-cache-clear ()
  "Clear all cache."
  (when aiaos-cli-cache
    (clrhash aiaos-cli-cache)))

(provide 'aiaos-cli-cache)

;;; aiaos-cli-cache.el ends here