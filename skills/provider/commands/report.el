;;; aiaos-cli-skill-provider/commands/report.el --- Provider 报告 -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/report (args options _ctx)
  "Generate provider configuration report."
  (let* ((json-mode (or (plist-get options :json) aiaos-cli--json-mode))
         (report (aiaos-cli-provider--report))
         (total (or (plist-get report :total) 0))
         (by-tier (plist-get report :by-tier))
         (fallback-enabled (plist-get report :fallback-enabled))
         (fallback-order (plist-get report :fallback-order))
         (providers (aiaos-cli-provider--list))
         (provider-list (if (null providers)
                            "  (none)"
                          (mapconcat (lambda (p)
                                       (format "  - %s [%s] %s"
                                               (aiaos-cli-provider-name p)
                                               (aiaos-cli-provider-tier p)
                                               (or (aiaos-cli-provider-model p) "")))
                                     providers "\n")))
         (tier-list (if (null by-tier)
                        "  (none)"
                      (mapconcat (lambda (pair)
                                   (format "  %s: %d"
                                           (car pair)
                                           (length (cdr pair))))
                                 by-tier "\n")))
         (output
          (format "=== Provider Report ===\n\nTotal: %d\n\nProviders:\n%s\n\nBy Tier:\n%s\n\nFallback: %s"
                  total
                  provider-list
                  tier-list
                  (if fallback-enabled
                      (mapconcat #'identity fallback-order " -> ")
                    "disabled"))))
    (if json-mode
        (aiaos-cli--result-success :report report :output output)
      (aiaos-cli--result-success :output output))))

(put 'aiaos-cli-skill-provider/report 'aiaos-cli-command-spec
    '(:description "Generate provider report"
      :args nil
      :options ((:name "json" :short "j" :type boolean :default false :description "JSON output"))))

(provide 'aiaos-cli-skill-provider/commands/report)
;;; aiaos-cli-skill-provider/commands/report.el ends here
