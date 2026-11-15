;;; on-load.el --- emacs-tools skill: on-load hook -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/on-load ()
  "Called when the emacs-tools skill is loaded.
预加载所有命令模块，确保技能加载后命令立即可用。"
  (require 'aiaos-cli-skill-emacs-tools/encode nil t)
  (require 'aiaos-cli-skill-emacs-tools/format nil t)
  (require 'aiaos-cli-skill-emacs-tools/slugify nil t)
  (require 'aiaos-cli-skill-emacs-tools/stats nil t)
  (require 'aiaos-cli-skill-emacs-tools/wordfreq nil t)
  (message "aiaos-cli: emacs-tools skill loaded"))

(provide 'aiaos-cli-skill-emacs-tools/on-load)
;;; on-load.el ends here
