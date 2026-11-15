;;; aiaos-cli-version.el --- AIAOS CLI version information -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project

;; This file reads the VERSION file from the project root and provides
;; the version string as the variable `aiaos-cli-version'.

(require 'find-func)

;; R637: Fallback literal for when VERSION is unreadable at load time
;; (the runtime copy is byte-compiled, and the VERSION file may not be
;; alongside it). This must be kept in sync with VERSION manually or
;; via the version gate in run-tests.sh.
(defconst aiaos-cli-version-fallback "1.0.36"
  "Fallback version string if VERSION file cannot be read.")

(defconst aiaos-cli-version
  (let ((version-file (expand-file-name "VERSION" (file-name-directory (directory-file-name (file-name-directory load-file-name))))))
    (if (file-exists-p version-file)
        (with-temp-buffer
          (insert-file-contents version-file)
          (string-trim (buffer-string)))
      aiaos-cli-version-fallback))
  "AIAOS CLI version string, read from VERSION file.")

(provide 'aiaos-cli-version)

;;; aiaos-cli-version.el ends here