;; aiaos-cli init.el - Entry point for aiaos-cli package
;; Add lisp directory to load-path
(add-to-list 'load-path (expand-file-name "lisp" (file-name-directory (or load-file-name (buffer-file-name) "~/.emacs.d/aiaos-cli"))))

;; Require main modules
(require 'aiaos-cli-core)
(require 'aiaos-cli-llm)
(require 'aiaos-cli-app)
(require 'aiaos-cli-emacs)

;; Note: Do NOT provide 'aiaos-cli here, because the actual implementation
;; is in lisp/aiaos-cli.el. Providing it here would cause require 'aiaos-cli
;; to skip loading aiaos-cli.el, leading to missing functions like
;; aiaos-cli--parse-json.