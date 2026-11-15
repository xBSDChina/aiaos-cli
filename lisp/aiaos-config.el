;;; aiaos-config.el --- Configuration management for AIAOS CLI -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS
;;
;; R573: rewritten from scratch.  Fixes:
;;   1. Load used `load' on JSON -> "invalid read syntax".
;;   2. Save/Load path mismatch (function shadowed defcustom variable).
;;   3. Save produced invalid JSON (symbol keys had leading colon).
;;   4. aiaos-config-show printed "nil" for all values.
;;   5. file-exists-p compared unexpanded "~/..." path.
;;   6. Recursive save->load->set->save loop.
;;   7. copy-sequence on non-sequence values (numbers).

(require 'json)
(require 'cl-lib)
(require 'aiaos-core)

(defcustom aiaos-config-file
  (expand-file-name "config.json"
                    (expand-file-name ".aiaos-cli"
                                      (getenv "HOME")))
  "Path to the AIAOS CLI configuration file (JSON format)."
  :type 'string
  :group 'aiaos)

(defvar aiaos-config--data nil
  "In-memory configuration alist.")

(defvar aiaos-config--loaded nil
  "Non-nil when configuration has been loaded from disk.")

(defconst aiaos-config--defaults
  '((:host . "localhost")
    (:port . 22)
    (:ssh-port . 22)
    (:ssh-user . "root")
    (:remote-dir . "/tmp/aiaos")
    (:local-dir . "~/.aiaos")
    (:sync-mode . "auto")
    (:log-level . "info")
    (:api-key . "")
    (:api-base-url . "https://api.aiaos.example.com")
    (:workspace . "~/.aiaos/workspace")
    (:max-concurrent . 4)
    (:timeout . 300)
    (:output-dir . "~/aiaos-reports")
    (:ws-url . "ws://localhost:9222/devtools/page")
    (:ssh-timeout . 10)))

(defun aiaos-config--set-defaults ()
  "Initialize `aiaos-config--data' with defaults."
  (setq aiaos-config--data
        (mapcar (lambda (kv) (cons (car kv) (cdr kv)))
                aiaos-config--defaults)))

(defun aiaos-config--ensure-dir ()
  "Make sure the parent directory of `aiaos-config-file' exists."
  (let ((dir (file-name-directory aiaos-config-file)))
    (unless (file-exists-p dir)
      (make-directory dir t))
    dir))

(defun aiaos-config-set-no-save (key value)
  "Set KEY to VALUE in memory without saving to disk."
  (setq aiaos-config--data
        (append (assq-delete-all key aiaos-config--data)
                (list (cons key value)))))

(defun aiaos-config--locate-file ()
  "Return the effective configuration file path.

Precedence:
  1. `$AIAOS_CLI_HOME/config.json' if the environment variable is set
     and the file exists.
  2. `aiaos-config-file' (default `~/.aiaos-cli/config.json').

Returns a string path; caller is responsible for ensuring the
containing directory exists before writing."
  (let ((env (getenv "AIAOS_CLI_HOME")))
    (if (and env (not (string-empty-p env)))
        (let ((p (expand-file-name "config.json" env)))
          (if (file-exists-p p)
              p
            (expand-file-name "config.json" env)))
      aiaos-config-file)))

(defun aiaos-config-load ()
  "Load configuration from `aiaos-config-file' if it exists.

Falls back to defaults.  Returns t on success, nil on failure."
  (aiaos-config--set-defaults)
  (let (ok)
    (when (file-exists-p aiaos-config-file)
      (condition-case err
          (let ((data (with-temp-buffer
                        (insert-file-contents aiaos-config-file)
                        (goto-char (point-min))
                        (let ((json-array-type 'list))
                          (json-read)))))
             (when (listp data)
               (dolist (item data)
                 (cond
                  ;; Dotted pair: (key . value) — cdr is not a cons
                  ((and (consp item) (not (consp (cdr item)))
                        (stringp (car item)))
                   (aiaos-config-set-no-save
                    (intern (concat ":" (car item)))
                    (cdr item)))
                  ;; Proper list of 2 elements: ("key" value)
                  ((and (consp item) (consp (cdr item))
                        (null (cddr item)))
                   (let ((k (car item)) (v (cadr item)))
                     (when (stringp k)
                       (aiaos-config-set-no-save
                        (intern (concat ":" k)) v))))
                  ;; R606: `json-read' renders JSON `null' as a one-element
                  ;; list (KEY) whose cdr is nil, so it matches neither form
                  ;; above and was silently dropped on load.  That is worse
                  ;; than a null leak -- the key vanishes with no trace.
                  ;; Catch it explicitly and skip nil values so the key
                  ;; falls back to its default instead of being stored as
                  ;; `nil' (which `json-encode' would render as `null').
                  ((and (consp item) (null (cdr item))
                        (stringp (car item)))
                   (aiaos-core-debug
                    "config: dropping null value for key %s" (car item))))))
            (aiaos-core-info "Configuration loaded from %s" aiaos-config-file)
            (setq ok t))
        (error
         (aiaos-core-warn "Failed to load config from %s: %s"
                          aiaos-config-file (error-message-string err))
         nil)))
    (setq aiaos-config--loaded t)
    ok))

(defun aiaos-config-get (key &optional default)
  "Return the value for KEY, or DEFAULT if not set."
  (unless aiaos-config--loaded (aiaos-config-load))
  (let ((entry (assoc key aiaos-config--data)))
    (if entry (cdr entry) default)))

(defun aiaos-config-set (key value)
  "Set KEY to VALUE and save to disk."
  (unless aiaos-config--loaded (aiaos-config-load))
  (aiaos-config-set-no-save key value)
  (aiaos-config-save)
  (aiaos-core-info "Set %s = %S" key value)
  value)

(defun aiaos-config--to-alist ()
  "Return current configuration as a JSON-friendly alist.

Keys are plain strings (leading colon/quote stripped) suitable for
json-encode and for downstream consumers such as aiaos-report.
Values are preserved as-is."
  (unless aiaos-config--loaded (aiaos-config-load))
  (mapcar (lambda (kv)
            (cons (replace-regexp-in-string
                   "^[:']+" ""
                   (symbol-name (car kv)))
                  (cdr kv)))
          aiaos-config--data))

(defun aiaos-config-save ()
  "Save current configuration to `aiaos-config-file' as JSON.

Returns t on success, nil on failure."
  (unless aiaos-config--loaded
    (aiaos-config--set-defaults)
    (setq aiaos-config--loaded t))
  (aiaos-config--ensure-dir)
  (let* ((json-path aiaos-config-file)
         (alist (mapcar
                 (lambda (kv)
                   (cons (replace-regexp-in-string "^[:']+" ""
                                                   (symbol-name (car kv)))
                         (cdr kv)))
                 aiaos-config--data)))
    (condition-case err
        (progn
          (with-temp-buffer
            (erase-buffer)
            ;; R606: never emit `null' -- drop nil values so a stale
            ;; in-memory nil cannot re-pollute the file on disk.
            (insert (json-encode (cl-remove-if #'null alist :key #'cdr)))
            (write-region (point-min) (point-max) json-path))
          (aiaos-core-info "Configuration saved to %s" json-path)
          t)
      (error
       (aiaos-core-warn "Failed to save config to %s: %s"
                        json-path (error-message-string err))
       nil))))

(defun aiaos-config-show ()
  "Display and return a human-readable summary of the configuration.

R584: emit to stdout when running under batch (terminal CLI) so that
`./aiaos-cli config show' produces visible output.  In interactive
Emacs, fall back to `display-buffer' for the traditional behaviour.
The returned string is always the same rendered text."
  (unless aiaos-config--loaded (aiaos-config-load))
  (let ((text (with-current-buffer (get-buffer-create "*AIAOS Config*")
                (erase-buffer)
                (insert "=== AIAOS CLI Configuration ===\n\n")
                (dolist (entry aiaos-config--data)
                  (insert (format "%-20s %s\n"
                                  (replace-regexp-in-string "^[:']+" ""
                                                            (symbol-name (car entry)))
                                  (format "%s" (cdr entry)))))
                (buffer-string))))
    (if noninteractive
        (aiaos-core-emit-line text)
      (with-current-buffer (get-buffer-create "*AIAOS Config*")
        (erase-buffer)
        (insert text)
        (goto-char (point-min))
        (display-buffer (current-buffer))))
    text))

(defun aiaos-config-reset ()
  "Reset configuration to defaults."
  (aiaos-config--set-defaults)
  (aiaos-core-info "Configuration reset to defaults")
  t)

(defun aiaos-config-list ()
  "Return all current configuration as an alist."
  (unless aiaos-config--loaded (aiaos-config-load))
  aiaos-config--data)

(provide 'aiaos-config)
;;; aiaos-config.el ends here
