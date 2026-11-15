;; aiaos-cli init.el - Entry point for aiaos-cli package
;; Add lisp directory to load-path
(add-to-list 'load-path (expand-file-name "lisp" (file-name-directory (or load-file-name (buffer-file-name) "~/.emacs.d/aiaos-cli"))))

;; Require main modules
(require 'aiaos-cli-core)
(require 'aiaos-cli-llm)
(require 'aiaos-cli-app)
(require 'aiaos-cli-emacs)

;; Provide the package
(provide 'aiaos-cli)