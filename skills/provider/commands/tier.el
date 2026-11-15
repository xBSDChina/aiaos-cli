;;; aiaos-cli-skill-provider/commands/tier.el --- Provider Tier 管理 -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/tier (args options _ctx)
  "Get or set provider tier."
  (let* ((name (plist-get args :name))
         (tier-arg (plist-get args :tier))
         (result (if tier-arg
                     (aiaos-cli-provider--tier-set name tier-arg)
                   (list :status (aiaos-cli-provider--tier-get name)))))
    (if (plist-get result :error)
        (aiaos-cli--result-error "PROVIDER_TIER_FAILED"
                                 (plist-get result :error))
      (let* ((provider-or-tier (plist-get result :status))
             (output
              (if (consp provider-or-tier)
                  (format "Provider '%s' tier set to '%s'"
                          name (aiaos-cli-provider-tier provider-or-tier))
                (format "Provider '%s' tier: %s" name provider-or-tier))))
        (aiaos-cli--result-success :output output)))))

(put 'aiaos-cli-skill-provider/tier 'aiaos-cli-command-spec
    '(:description "Get or set provider tier"
      :args ((:name "name" :type string :required t :description "Provider name")
             (:name "tier" :type string :required nil :description "Tier to set (full/active/block)"))
      :options nil))

(provide 'aiaos-cli-skill-provider/commands/tier)
;;; aiaos-cli-skill-provider/commands/tier.el ends here
