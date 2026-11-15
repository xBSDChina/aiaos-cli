;;; aiaos-cli-skill-provider/commands/remove.el --- 删除 Provider -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/remove (args options _ctx)
  "Remove a provider."
  (let* ((name (plist-get args :name))
         (success (aiaos-cli-provider--remove name)))
    (if (not success)
        (aiaos-cli--result-error "PROVIDER_NOT_FOUND"
                                 (format "Provider '%s' not found" name))
      (let ((output (format "Removed provider '%s'" name)))
        (aiaos-cli--result-success :output output)))))

(put 'aiaos-cli-skill-provider/remove 'aiaos-cli-command-spec
    '(:description "Remove a provider"
      :args ((:name "name" :type string :required t :description "Provider name"))
      :options nil))

(provide 'aiaos-cli-skill-provider/commands/remove)
;;; aiaos-cli-skill-provider/commands/remove.el ends here
