;;; aiaos-cli-config.el --- Configuration Management for AIAOS-CLI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, config, aiaos

;; Configuration management with validation, persistence, and hot-reload.

;;; Commentary:

;; This module provides:
;;   * aiaos-cli-config-load - Load configuration from file
;;   * aiaos-cli-config-save - Save configuration to file
;;   * aiaos-cli-config-get - Get configuration value
;;   * aiaos-cli-config-set - Set configuration value
;;   * aiaos-cli-config-validate - Validate configuration
;;   * aiaos-cli-config-reload - Hot-reload configuration

;;; Code:

(require 'json)
(require 'cl-lib)

(defgroup aiaos-cli-config nil
  "AIAOS-CLI Configuration"
  :group 'aiaos-cli
  :prefix "aiaos-cli-config-")

(defcustom aiaos-cli-config-file
  (expand-file-name "~/.aiaos-cli.json")
  "Path to the configuration file."
  :type 'file
  :group 'aiaos-cli-config)

(defcustom aiaos-cli-config-auto-save t
  "Automatically save configuration on changes."
  :type 'boolean
  :group 'aiaos-cli-config)

;; Additional configuration variables (BUG-023 fix)
(defcustom aiaos-cli-temperature 0.7
  "Temperature for LLM generation."
  :type 'number
  :group 'aiaos-cli-config)

(defcustom aiaos-cli-max-tokens 2048
  "Maximum tokens for LLM generation."
  :type 'integer
  :group 'aiaos-cli-config)

(defcustom aiaos-cli-config-dir
  (expand-file-name "~/.aiaos-cli")
  "Directory for AIAOS CLI configuration."
  :type 'directory
  :group 'aiaos-cli-config)

;; Configuration structure
(cl-defstruct aiaos-cli-config
  "Configuration container."
  (providers nil :type list)
  (skills nil :type list)
  (ui nil :type list)
  (security nil :type list)
  (monitoring nil :type list)
  (last-loaded nil))

;; Current configuration
(defun aiaos-cli-config-current ()
  "Get current configuration object."
  aiaos-cli-config-current-var)

(provide 'aiaos-cli-config)

;;; Configuration loading

(defun aiaos-cli-config-load (&optional file)
  "Load configuration from FILE or default location."
  (let ((config-file (or file aiaos-cli-config-file)))
    (if (file-exists-p config-file)
        (condition-case err
            (with-temp-buffer
              (insert-file-contents config-file)
              (let ((json-object-type 'alist))
                (json-read-from-string (buffer-string))))
          (error
           (message "Failed to load config: %s" (error-message-string err))
           nil)
        (make-aiaos-cli-config))))

(defun aiaos-cli-config-save (&optional config file)
  "Save CONFIG to FILE."
  (let ((config-data (or config aiaos-cli-config-current-var))
        (config-file (or file aiaos-cli-config-file)))
    (when config-data
      (with-temp-file config-file
        (json-encode (aiaos-cli-config-to-alist config-data)))
      t)))

;;; Configuration access

(defun aiaos-cli-config-get (key &optional default)
  "Get configuration value for KEY."
  (cond
   ((eq key 'providers) (aiaos-cli-config-providers aiaos-cli-config-current-var))
   ((eq key 'skills) (aiaos-cli-config-skills aiaos-cli-config-current-var))
   ((eq key 'ui) (aiaos-cli-config-ui aiaos-cli-config-current-var))
   ((eq key 'security) (aiaos-cli-config-security aiaos-cli-config-current-var))
   ((eq key 'monitoring) (aiaos-cli-config-monitoring aiaos-cli-config-current-var))
   (t default)))

(defun aiaos-cli-config-set (key value)
  "Set configuration KEY to VALUE."
  (when aiaos-cli-config-current-var
    (cond
     ((eq key 'providers) (setf (aiaos-cli-config-providers aiaos-cli-config-current-var) value))
     ((eq key 'skills) (setf (aiaos-cli-config-skills aiaos-cli-config-current-var) value))
     ((eq key 'ui) (setf (aiaos-cli-config-ui aiaos-cli-config-current-var) value))
     ((eq key 'security) (setf (aiaos-cli-config-security aiaos-cli-config-current-var) value))
     ((eq key 'monitoring) (setf (aiaos-cli-config-monitoring aiaos-cli-config-current-var) value)))
    (when aiaos-cli-config-auto-save
      (aiaos-cli-config-save))))

;;; Configuration validation

(defun aiaos-cli-config-validate (config)
  "Validate CONFIG structure."
  (and (aiaos-cli-config-p config)
       (listp (aiaos-cli-config-providers config))
       (listp (aiaos-cli-config-skills config))))

;;; Hot reload

(defun aiaos-cli-config-reload ()
  "Reload configuration from disk."
  (setq aiaos-cli-config-current-var (aiaos-cli-config-load))
  (message "Configuration reloaded")
  aiaos-cli-config-current-var)

;;; Helper: Convert config struct to alist for JSON encoding

(defun aiaos-cli-config-to-alist (config)
  "Convert CONFIG struct to alist for JSON encoding."
  (when (aiaos-cli-config-p config)
    (list
     (cons 'providers (aiaos-cli-config-providers config))
     (cons 'skills (aiaos-cli-config-skills config))
     (cons 'ui (aiaos-cli-config-ui config))
     (cons 'security (aiaos-cli-config-security config))
     (cons 'monitoring (aiaos-cli-config-monitoring config))
     (cons 'last-loaded (aiaos-cli-config-last-loaded config)))))

;;; Initialize

(defun aiaos-cli-config-init ()
  "Initialize configuration system."
  (unless aiaos-cli-config-current-var
    (setq aiaos-cli-config-current-var (aiaos-cli-config-load))
    (unless aiaos-cli-config-current-var
      (setq aiaos-cli-config-current-var (make-aiaos-cli-config))
      (aiaos-cli-config-save))))

(provide 'aiaos-cli-config)

;;; aiaos-config.el ends here