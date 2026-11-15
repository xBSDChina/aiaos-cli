;;; aiaos-cli-skill-provider/commands/add.el --- 添加 Provider -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/add (args options _ctx)
  "Add a new provider."
  (let* ((name (plist-get args :name))
         (api-key (plist-get args :api-key))
         (base-url (plist-get args :base-url))
         (model (plist-get options :model))
         (tier (plist-get options :tier))
         (result (aiaos-cli-provider--add name
                                          :api-key api-key
                                          :base-url base-url
                                          :model model
                                          :tier tier)))
    (if (plist-get result :error)
        (aiaos-cli--result-error "PROVIDER_ADD_FAILED"
                                 (plist-get result :error))
      (let* ((provider (plist-get result :status))
             (output (format "Added provider '%s' (tier=%s)"
                             (aiaos-cli-provider-name provider)
                             (aiaos-cli-provider-tier provider))))
        (aiaos-cli--result-success :provider provider :output output)))))

(put 'aiaos-cli-skill-provider/add 'aiaos-cli-command-spec
    '(:description "Add a new provider"
      :args ((:name "name" :type string :required t :description "Provider name")
             (:name "api-key" :type string :required t :description "API key")
             (:name "base-url" :type string :required t :description "Base URL"))
      :options ((:name "model" :short "m" :type string :default "" :description "Model name")
                (:name "tier" :short "t" :type string :default "active" :description "Tier (full/active/block)"))))

(provide 'aiaos-cli-skill-provider/commands/add)
;;; aiaos-cli-skill-provider/commands/add.el ends here
