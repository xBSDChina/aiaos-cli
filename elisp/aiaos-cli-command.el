;;; aiaos-cli-command.el --- Aiaos CLI command system  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Aiaos Project
;; Author: Aiaos Team
;; Keywords: aiaos, cli, command

;; This file is part of Aiaos.
;; Aiaos is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License.

;;; Commentary:
;; This module provides the command system for Aiaos CLI.
;; Commands are organized hierarchically with subcommands.

;;; Code:

(require 'cl-lib)
(require 'aiaos-cli-component)


;;; ###autoload
(defun aiaos-cli--command-make (name description handler)
  "Create command object.

NAME is the command name
DESCRIPTION is the description
HANDLER is the handler function"
  (list :name name
        :description description
        :handler handler
        :subcommands nil))

;;; ###autoload
(defun aiaos-cli--command-add-subcommand (cmd subcmd)
  "Add subcommand to CMD."
  (setf (plist-get cmd :subcommands)
        (cons subcmd (plist-get cmd :subcommands))))

(defun aiaos-cli--command-subcommands (cmd)
  "Get subcommands of CMD."
  (plist-get cmd :subcommands))

;;; ###autoload
(defun aiaos-cli--command-get-handler (cmd)
  "Get handler function of CMD."
  (plist-get cmd :handler))

;;; ###autoload
(defun aiaos-cli--command-get-name (cmd)
  "Get name of CMD."
  (plist-get cmd :name))

;;; ###autoload
(defun aiaos-cli--command-get-description (cmd)
  "Get description of CMD."
  (plist-get cmd :description))


(defvar aiaos-cli--command-registry nil
  "Command registry.")

;;; ###autoload
(defun aiaos-cli--command-init ()
  "Initialize command system."
  (setq aiaos-cli--command-registry (make-hash-table :test 'equal)))

;;; ###autoload
(defun aiaos-cli--command-register (cmd-name cmd)
  "Register command.

CMD-NAME is the command name (e.g. \"skill\" or \"skill list\")
CMD is the command object"
  (let* ((parts (split-string cmd-name "/"))
         (parent-path (butlast parts))
         (parent-name (when (= (length parent-path) 1)
                        (car parent-path))))
    (if (and (> (length parts) 1)
             parent-name)
        ;; Subcommand
        (let ((parent-cmd (gethash parent-name aiaos-cli--command-registry)))
          (if parent-cmd
              (aiaos-cli--command-add-subcommand parent-cmd cmd)
            (error "Parent command \"%s\" not found" parent-name)))
      ;; Top-level command
      (setf (gethash cmd-name aiaos-cli--command-registry) cmd))))

;;; ###autoload
(defun aiaos-cli--command-lookup (cmd-path)
  "Lookup command by path.

CMD-PATH is the command path (e.g. \"skill\" or \"skill list\")"
  (let* ((parts (split-string cmd-path " "))
         (cmd-name (pop parts))
         (cmd (gethash cmd-name aiaos-cli--command-registry)))
    (if (null cmd)
        nil
      (dolist (part parts)
        (let ((subcmds (aiaos-cli--command-subcommands cmd)))
          (setq cmd (cl-find part subcmds
                             :key #'aiaos-cli--command-get-name
                             :test #'equal))))
      cmd)))

;;; ###autoload
(defun aiaos-cli--command-run (cmd-path args)
  "Run command.

CMD-PATH is the command path
ARGS is the argument list"
  (let ((cmd (aiaos-cli--command-lookup cmd-path)))
    (if (null cmd)
        (error "Command \"%s\" not found" cmd-path)
      (let ((handler (aiaos-cli--command-get-handler cmd)))
        (if (null handler)
            (error "Command \"%s\" has no handler" cmd-path)
          (funcall handler args))))))

(provide 'aiaos-cli-command)
;;; aiaos-cli-command.el ends here
