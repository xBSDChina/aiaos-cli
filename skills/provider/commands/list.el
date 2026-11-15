;;; aiaos-cli-skill-provider/commands/list.el --- 列出 Provider -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/list (args options _ctx)
  "List all configured providers."
  (let* ((json-mode (or (plist-get options :json) aiaos-cli--json-mode))
         (tier-filter (plist-get options :tier))
         (providers (if tier-filter
                        (aiaos-cli-provider--list-by-tier tier-filter)
                      (aiaos-cli-provider--list)))
         (output
          (if (null providers)
              "No providers configured."
            (format "Providers (%d):\n%s"
                    (length providers)
                    (mapconcat (lambda (p)
                                 (format "  - %s | tier=%s | model=%s | base-url=%s"
                                         (aiaos-cli-provider-name p)
                                         (aiaos-cli-provider-tier p)
                                         (or (aiaos-cli-provider-model p) "")
                                         (or (aiaos-cli-provider-base-url p) "")))
                               providers "\n")))))
    (if json-mode
        (aiaos-cli--result-success
         :providers (mapcar (lambda (p)
                              (list :name (aiaos-cli-provider-name p)
                                    :tier (aiaos-cli-provider-tier p)
                                    :model (aiaos-cli-provider-model p)
                                    :base-url (aiaos-cli-provider-base-url p)
                                    :status (aiaos-cli-provider-status p)))
                            providers)
         :output output)
      (aiaos-cli--result-success :output output))))

(put 'aiaos-cli-skill-provider/list 'aiaos-cli-command-spec
    '(:description "List all configured providers"
      :args nil
      :options ((:name "json" :short "j" :type boolean :default false :description "JSON output")
                (:name "tier" :short "t" :type string :default "" :description "Filter by tier"))))

(provide 'aiaos-cli-skill-provider/commands/list)
;;; aiaos-cli-skill-provider/commands/list.el ends here
