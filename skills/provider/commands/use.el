;;; aiaos-cli-skill-provider/commands/use.el --- 设置当前 Provider -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/use (args options _ctx)
  "Set the current provider to use."
  (let* ((name (plist-get args :name))
         (providers (aiaos-cli-provider--load-config))
         (provider (aiaos-cli-provider--find name)))
    (if (not provider)
        (aiaos-cli--result-error "PROVIDER_NOT_FOUND"
                                 (format "Provider '%s' not found" name))
      (let* ((tier (aiaos-cli-provider-tier provider))
             (output (format "Using provider '%s' (tier=%s, model=%s)"
                             name tier (or (aiaos-cli-provider-model provider) ""))))
        (aiaos-cli-provider--audit name "use" (format "tier=%s" tier))
        (aiaos-cli--result-success :provider name :output output)))))

(put 'aiaos-cli-skill-provider/use 'aiaos-cli-command-spec
    '(:description "Set current provider"
      :args ((:name "name" :type string :required t :description "Provider name"))
      :options nil))

(provide 'aiaos-cli-skill-provider/commands/use)
;;; aiaos-cli-skill-provider/commands/use.el ends here
