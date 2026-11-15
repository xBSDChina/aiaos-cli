;; aiaos-cli-llm.el - Wrapper to load from lisp subdirectory
(add-to-list 'load-path (expand-file-name "lisp" (file-name-directory (or load-file-name (buffer-file-name) "~/.emacs.d/aiaos-cli"))))

;; Load the actual implementation without requiring the wrapper feature
(load (expand-file-name "lisp/aiaos-cli-llm.el" (file-name-directory (or load-file-name (buffer-file-name) "~/.emacs.d/aiaos-cli"))))

;; Ensure the feature is provided
(provide 'aiaos-cli-llm)