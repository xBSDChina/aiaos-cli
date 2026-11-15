;;; aiaos-accessors.el --- Convenience accessors -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS
;;
;; Thin wrappers over aiaos-config so browser/sync/report modules can
;; call stable accessor functions without depending on aiaos-cli.el
;; (which would create a circular dependency).

(require 'aiaos-config)

(defun aiaos-cli-ws-url ()
  "Return the configured WebSocket URL."
  (aiaos-config-get :ws-url))

(defun aiaos-cli-ssh-port ()
  "Return the configured SSH port."
  (aiaos-config-get :ssh-port))

(defun aiaos-cli-ssh-user ()
  "Return the configured SSH user."
  (aiaos-config-get :ssh-user))

(defun aiaos-cli-target-host ()
  "Return the configured target host."
  (aiaos-config-get :host))

(provide 'aiaos-accessors)
;;; aiaos-accessors.el ends here
