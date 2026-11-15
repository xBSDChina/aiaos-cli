;;; aiaos-sync.el --- File synchronization module  -*- lexical-binding: t -*-

;; Copyright (C) 2026 AIAOS

;;; Commentary:

;; File synchronization module with SSH/SFTP support for uploading
;; and downloading files from remote AIAOS servers.

;;; Code:

(require 'cl-lib)
(require 'aiaos-core)
(require 'aiaos-config)
(require 'aiaos-accessors)
(require 'shell)

(defgroup aiaos-sync nil
  "File synchronization functionality."
  :group 'aiaos-cli)

;; Sync state
(defvar aiaos-sync--last-upload-time nil
  "Timestamp of last successful upload.")
(defvar aiaos-sync--pending-files '()
  "Files pending synchronization.")


;; SSH timeout configuration
(defcustom aiaos-sync-ssh-timeout 10
  "SSH connection timeout in seconds."
  :type 'integer
  :group 'aiaos-sync)

(defun aiaos-sync--ssh-timeout ()
  "Return effective SSH timeout: config :ssh-timeout overrides defcustom."
  (let ((cfg (aiaos-config-get :ssh-timeout)))
    (if (and (integerp cfg) (>= cfg 0))
        cfg
      aiaos-sync-ssh-timeout)))

;; R617 FIX: separate timeout for *probe* SSH calls (status / check-status /
;; detect-conflict).  These are read-only existence checks that run on every
;; `aiaos-cli status' invocation.  When the remote is unreachable they used to
;; block for the full 10s `aiaos-sync-ssh-timeout', which made the regression
;; suite (which calls status 4+ times) blow past the 120s wall-clock budget.
;; Probe calls only need a short budget; upload/download keep the full 10s.
(defcustom aiaos-sync-probe-timeout 2
  "SSH timeout in seconds for probe calls (status / check-status / conflict)."
  :type 'integer
  :group 'aiaos-sync)

(defun aiaos-sync--probe-timeout ()
  "Return effective probe SSH timeout: config :probe-timeout overrides defcustom."
  (let ((cfg (aiaos-config-get :probe-timeout)))
    (if (and (integerp cfg) (>= cfg 0))
        cfg
      aiaos-sync-probe-timeout)))

;; SSH connection helper
(defun aiaos-sync--ssh-command (command)
  "Build SSH command for COMMAND."
  (format "ssh -p %s -o ConnectTimeout=%s -o StrictHostKeyChecking=no %s@%s \"%s\""
          (aiaos-cli-ssh-port)
          (aiaos-sync--ssh-timeout)
          (aiaos-cli-ssh-user)
          (aiaos-cli-target-host)
          command))

;;; R602 FIX: total-timeout helper for synchronous shell calls.
;;
;; Background: `ssh -o ConnectTimeout=N` only bounds the TCP handshake.
;; Once the connection is established, an unresponsive remote (or an SSH
;; session that accepts the connection but never answers) makes the
;; synchronous `process-lines`/`call-process` block indefinitely.
;;
;; `with-timeout` does NOT help here: Emacs does not run its timer queue
;; while `call-process` is blocked, so the timeout never fires (verified in
;; R602: an 8s command completed in full under a 2s with-timeout).
;;
;; The fix uses an asynchronous process polled with a bounded
;; `accept-process-output`, which does run the timer queue and lets us
;; enforce a wall-clock deadline.
;;
;; NOTE (R602): Emacs 30.1 removed the obsolete MILLISEC parameter from
;; `accept-process-output'; the signature is now
;;   (fn &optional PROCESS SECONDS MILLISEC JUST-THIS-ONE)
;; so the wait is passed as the SECONDS (float) argument.  Also pass an
;; explicit buffer to `start-process': with a nil buffer, `process-buffer'
;; returns nil.

(defun aiaos-sync--run-with-timeout-string (command timeout)
  "Run COMMAND via /bin/sh, return raw output string, error on TIMEOUT.

COMMAND is a full shell command line.  TIMEOUT is a wall-clock limit in
seconds.  Signals a `timeout' error if the command does not finish in
time.  Unlike a bare `process-lines' call this cannot hang: the deadline
is enforced by polling an asynchronous process."
  (unless (and (numberp timeout) (>= timeout 0))
    (user-error "Invalid timeout: %s" timeout))
  (let ((buf (get-buffer-create (format "*aiaos-sync %s*" (buffer-name)))))
    (unwind-protect
        (let ((proc (start-process "aiaos-sync" buf "/bin/sh" "-c" command))
              (deadline (float-time (time-add (current-time) timeout))))
          ;; R602: no-op sentinel keeps the captured buffer free of the
          ;; automatic "Process ... finished" line, so callers parsing the
          ;; output (e.g. md5sum fields) see exactly what the command printed.
          (set-process-sentinel proc (lambda (&rest _) nil))
          (set-process-query-on-exit-flag proc nil)
          (while (process-live-p proc)
            (let ((remaining (max 0.0 (- deadline (float-time)))))
              (when (<= remaining 0)
                (kill-process proc)
                (error "timeout after %d sec: %s" timeout command))
              (accept-process-output proc remaining nil t)))
          (when (= (process-exit-status proc) 0)
            (with-current-buffer buf (buffer-string))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(defun aiaos-sync--run-with-timeout (command timeout)
  "Like `aiaos-sync--run-with-timeout-string' but return a list of lines."
  (let ((result (aiaos-sync--run-with-timeout-string command timeout)))
    (when result
      (split-string result "\n" t))))

;; Check SSH connectivity
(defun aiaos-sync-check-connection ()
  "Check if SSH connection to remote server is available."
  (let* ((test-cmd (aiaos-sync--ssh-command "echo connected"))
         (result (ignore-errors
                   (aiaos-sync--run-with-timeout test-cmd
                                                 (aiaos-sync--probe-timeout)))))
    (if result
        (progn
          (aiaos-cli-info "SSH connection successful")
          t)
      (progn
        (aiaos-cli-error "SSH connection failed (port %s)" (aiaos-cli-ssh-port)
          (aiaos-sync--ssh-timeout))
        nil))))

;; Upload file
(defun aiaos-sync-upload-file (local-path &optional remote-path)
  "Upload LOCAL-PATH to REMOTE-PATH on remote server.
If REMOTE-PATH is nil, defaults to ~/$(basename LOCAL-PATH)."
  (unless (file-exists-p local-path)
    (user-error "Local file not found: %s" local-path)
    )

  (let* ((base-name (file-name-nondirectory local-path))
         (target-remote (or remote-path (format "~/%s" base-name)))
         (scp-cmd (format "scp -P %s -o ConnectTimeout=%s %s %s@%s:%s"
                          (aiaos-cli-ssh-port)
          (aiaos-sync--ssh-timeout)
                          local-path
                          (aiaos-cli-ssh-user)
                          (aiaos-cli-target-host)
                          target-remote)))
    (aiaos-cli-info "Uploading %s to %s:%s"
                    local-path (aiaos-cli-target-host) target-remote)
    (condition-case err
        (let ((exit-code (call-process "/bin/sh" nil nil nil "-c" scp-cmd)))
          (if (= exit-code 0)
              (progn
                (setq aiaos-sync--last-upload-time (current-time))
                (aiaos-cli-info "Upload successful: %s" local-path)
                t)
            (progn
              (aiaos-cli-error "Upload failed with code: %d" exit-code)
              nil)))
      (error
       (aiaos-cli-error "Upload error: %s" err)
       nil))))

;; Download file
(defun aiaos-sync-download-file (remote-path &optional local-path)
  "Download REMOTE-PATH from server to LOCAL-PATH."
  (let* ((base-name (file-name-nondirectory remote-path))
         (target-local (or local-path (expand-file-name base-name)))
         (scp-cmd (format "scp -P %s -o ConnectTimeout=%s %s@%s:%s %s"
                          (aiaos-cli-ssh-port)
          (aiaos-sync--ssh-timeout)
                          (aiaos-cli-ssh-user)
                          (aiaos-cli-target-host)
                          remote-path
                          target-local)))
    (aiaos-cli-info "Downloading %s:%s to %s"
                    (aiaos-cli-target-host) remote-path target-local)
    (condition-case err
        (let ((exit-code (call-process "/bin/sh" nil nil nil "-c" scp-cmd)))
          (if (= exit-code 0)
              (progn
                (aiaos-cli-info "Download successful: %s" target-local)
                t)
            (progn
              (aiaos-cli-error "Download failed with code: %d" exit-code)
              nil)))
      (error
       (aiaos-cli-error "Download error: %s" err)
       nil))))

;; Check sync status
(defun aiaos-sync-check-status (&optional remote-file local-file)
  "Check synchronization status between REMOTE-FILE and LOCAL-FILE."
  (let ((remote (or remote-file "~/aiaos_skills.txt"))
        (local (or local-file "~/aiaos_skills.txt"))
        (remote-exists nil))
    (condition-case _
        (let ((result (aiaos-sync--run-with-timeout
                                  (aiaos-sync--ssh-command
                                   (format "test -f %s && echo OK" remote))
                                  (aiaos-sync--probe-timeout))))
          (setq remote-exists (and result (member "OK" result))))
      (error nil))
    (let ((local-exists (file-exists-p (expand-file-name local))))
      (message "Remote: %s@%s:%s" (aiaos-cli-ssh-user) (aiaos-cli-target-host) remote)
      (message "Remote exists: %s" remote-exists)
      (message "Local: %s" local)
      (message "Local exists: %s" local-exists)
      (list :remote remote :local local
            :remote-exists remote-exists :local-exists local-exists))))

(defun aiaos-sync-pending-files ()
  "Return list of pending files.  Never nil: the JSON contract for
`--json sync pending' promises an array, and `json-encode' renders
elisp `nil' as the literal `null', which would silently break any
consumer calling `.length' on the result (R606).

The fallback must be `(vconcat nil)', not `\'()' or `(list)': in Emacs
an empty list is identical to `nil', so both would still encode as
`null'.  `(vconcat nil)' returns a zero-length vector, which encodes
as the JSON empty array `[]'."
  (or aiaos-sync--pending-files (vconcat nil)))

(defun aiaos-sync-add-pending (file)
  "Add FILE to pending list."
  (unless (member file aiaos-sync--pending-files)
    (push file aiaos-sync--pending-files)))

(defun aiaos-sync--md5 (file)
  "Return the MD5 digest of FILE, or nil if it cannot be computed."
  (when (file-exists-p file)
    (let ((out (with-temp-buffer
                 (if (eq (call-process "md5sum" nil (current-buffer) nil
                                       (shell-quote-argument file)) 0)
                     (buffer-string)
                   ""))))
      (when (string-match "^[0-9a-f]{32}" out)
        (match-string 0 out)))))

(defun aiaos-sync-detect-conflict (local-file remote-file)
  "Detect whether LOCAL-FILE and REMOTE-FILE are in conflict.
Returns a plist with :conflict, :local-exists, :remote-exists,
:local-md5, :remote-md5, :pending and :reason."
  (let* ((local (expand-file-name local-file))
         (remote (expand-file-name remote-file))
         (local-exists (file-exists-p local))
         (local-md5 (aiaos-sync--md5 local))
         (remote-exists nil)
         (remote-md5 nil)
         (reason "not checked"))
    ;; Probe remote via SSH.
    (condition-case _
        (let ((r (aiaos-sync--run-with-timeout
                                 (aiaos-sync--ssh-command
                                  (format "test -f %s && echo YES || echo NO" remote))
                                 (aiaos-sync--probe-timeout))))
          (setq remote-exists (and r (string= (car r) "YES")))
          (when remote-exists
            (let ((m (aiaos-sync--run-with-timeout
                                     (aiaos-sync--ssh-command
                                      (format "md5sum %s 2>/dev/null || echo UNKNOWN" remote))
                                     (aiaos-sync--probe-timeout))))
              (when (and m (string-match "^[0-9a-f]{32}" (car m)))
                (setq remote-md5 (match-string 0 (car m)))))))
      (error (setq remote-exists nil)))
    (let ((pending (member local aiaos-sync--pending-files))
          (conflict nil))
      (cond
       ((and local-exists remote-exists local-md5 remote-md5
             (not (string= local-md5 remote-md5)))
        (setq conflict t)
        (setq reason "content differs on both sides"))
       ((and local-exists remote-exists)
        (setq reason "content identical")
        (setq conflict nil))
       (t (setq reason (if local-exists "remote missing"
                           (if remote-exists "local missing" "both missing")))
          (setq conflict nil)))
      (when conflict
        (aiaos-cli-warn "Conflict detected: %s <-> %s (%s)" local remote reason))
      (list :conflict conflict :local-exists local-exists
            :remote-exists remote-exists :local-md5 local-md5
            :remote-md5 remote-md5 :pending pending :reason reason))))

(defun aiaos-sync-resolve-conflict (local-file remote-file strategy)
  "Resolve a conflict between LOCAL-FILE and REMOTE-FILE using STRATEGY.
STRATEGY is one of: `local', `remote', `backup', `abort'.
Returns a plist with :resolved, :strategy and :detail."
  (let ((local (expand-file-name local-file))
        (remote remote-file))
    (cond
     ((eq strategy 'abort)
      (aiaos-cli-warn "Conflict resolution aborted for %s" local)
      (list :resolved nil :strategy 'abort :detail "no action taken"))
     ((eq strategy 'backup)
      (let ((backup (concat local ".conflict")))
        (copy-file local backup t)
        (aiaos-cli-info "Conflict backup written: %s" backup)
        (list :resolved t :strategy 'backup :detail backup)))
     ((eq strategy 'local)
      (let ((ok (aiaos-sync-upload-file local remote)))
        (if ok
            (list :resolved t :strategy 'local :detail "local pushed to remote")
          (list :resolved nil :strategy 'local :detail "upload failed"))))
     ((eq strategy 'remote)
      (let ((ok (aiaos-sync-download-file remote local)))
        (if ok
            (list :resolved t :strategy 'remote :detail "remote pulled to local")
          (list :resolved nil :strategy 'remote :detail "download failed"))))
     (t (list :resolved nil :strategy strategy
              :detail (format "unknown strategy: %S" strategy))))))

(provide 'aiaos-sync)
;;; aiaos-sync.el ends here
