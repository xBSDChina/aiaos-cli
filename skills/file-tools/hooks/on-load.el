;;; on-load.el --- file-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-file-tools/on-load ()
  "Called when the file-tools skill is loaded."
  (require 'aiaos-cli-skill-file-tools/stat nil t)
  (require 'aiaos-cli-skill-file-tools/head-tail nil t)
  (require 'aiaos-cli-skill-file-tools/checksum nil t)
  (require 'aiaos-cli-skill-file-tools/normalize nil t)
  (message "aiaos-cli: file-tools skill loaded"))

(provide 'aiaos-cli-skill-file-tools/on-load)
