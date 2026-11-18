;;; aiaos-cli-buffer.el --- AIAOS-CLI Buffer Management -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, buffer, aiaos

;; This file provides buffer management functions for AIAOS-CLI.
;; It follows the AIAOS-CLI paradigm:
;;   - Buffer as interface (not popup)
;;   - Interactive buffer operations
;;   - Consistent buffer naming

;;; Code:

(require 'aiaos-cli-core)
(require 'aiaos-cli)

;;;###autoload
(defun aiaos-cli-buffer ()
  "Open the AIAOS-CLI interaction buffer.

This is the primary entry point for interacting with AIAOS-CLI.
It creates or switches to the AIAOS-CLI result buffer,
displaying the current state and available commands.

If the buffer does not exist, it is created with a welcome message.
If the buffer already exists, it is switched to and the point is
moved to the end for immediate interaction."
  (interactive)
  (aiaos-cli-init t)
  (let ((buf (get-buffer-create aiaos-cli-result-buffer-name)))
    (with-current-buffer buf
      (aiaos-cli-mode)
      (unless (buffer-modified-p)
        (erase-buffer)
        (let ((buffer-read-only nil))
          (insert "=== AIAOS-CLI Buffer ===\n\n"
                  "Welcome to AIAOS-CLI!\n\n"
                  "This is the main interaction buffer.\n"
                  "Available commands:\n"
                  "  M-x aiaos-cli-run       - Run aiaos-cli subcommand\n"
                  "  M-x aiaos-cli-agent-chat - Open agent chat\n"
                  "  M-x aiaos-cli-menu       - Open full menu\n"
                  "  M-x aiaos-cli-buffer     - Switch to this buffer\n\n"
                  "Type C-c a for quick access to AIAOS-CLI commands.\n\n")))
      (goto-char (point-max)))
    (switch-to-buffer buf)
    buf))

;;;###autoload
(defun aiaos-cli-buffer-other-window ()
  "Open the AIAOS-CLI interaction buffer in another window."
  (interactive)
  (aiaos-cli-buffer)
  (other-window 1))

;;;###autoload
(defun aiaos-cli-buffer-other-frame ()
  "Open the AIAOS-CLI interaction buffer in another frame."
  (interactive)
  (aiaos-cli-buffer)
  (other-frame 1))

;;;###autoload
(defun aiaos-cli-close-buffer ()
  "Close the AIAOS-CLI interaction buffer."
  (interactive)
  (let ((buf (get-buffer aiaos-cli-result-buffer-name)))
    (when buf
      (kill-buffer buf)
      (message "AIAOS-CLI buffer closed"))))

;;;###autoload
(defun aiaos-cli-buffer-rename ()
  "Rename the AIAOS-CLI interaction buffer."
  (interactive)
  (let ((buf (get-buffer aiaos-cli-result-buffer-name)))
    (when buf
      (with-current-buffer buf
        (rename-buffer
         (read-string "New buffer name: " aiaos-cli-result-buffer-name))))))

;;;###autoload
(defun aiaos-cli-buffer-list ()
  "List all AIAOS-CLI related buffers."
  (interactive)
  (let ((buffers (buffer-list))
        (aiaos-buffers '()))
    (dolist (buf buffers)
      (when (string-match-p "aiaos" (buffer-name buf))
        (push buf aiaos-buffers)))
    (if aiaos-buffers
        (message "AIAOS-CLI buffers:\n%s"
                 (mapconcat #'buffer-name aiaos-buffers "\n"))
      (message "No AIAOS-CLI buffers found"))))

(provide 'aiaos-cli-buffer)

;;; aiaos-cli-buffer.el ends here