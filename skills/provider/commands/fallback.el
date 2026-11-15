;;; aiaos-cli-skill-provider/commands/fallback.el --- Fallback 策略 -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/fallback (args options _ctx)
  "Set or query fallback strategy."
  (let* ((order-str (plist-get args :order))
         (disable (plist-get options :disable))
         (json-mode (or (plist-get options :json) aiaos-cli--json-mode))
         (fallback (aiaos-cli-provider--load-fallback)))
    (if order-str
        (let* ((names (split-string order-str))
               (result (if disable
                           (progn
                             (aiaos-cli-provider--save-fallback names nil)
                             (aiaos-cli-provider--audit "fallback" "disable" "disabled")
                             (list :status nil))
                         (aiaos-cli-provider--fallback-set names))))
          (aiaos-cli--result-success
           :order names :enabled (unless disable t)
           :output (format "Fallback order set to: %s%s"
                           (mapconcat #'identity names " -> ")
                           (if disable " (disabled)" ""))))
      (let* ((order (aiaos-cli-provider--fallback-order))
             (enabled (aiaos-cli-provider--fallback-enabled))
             (output
              (format "Fallback strategy: %s%s"
                      (if order
                          (format "%s -> %s"
                                  (nth 0 order)
                                  (mapconcat #'identity (cdr order) " -> "))
                        "(empty)")
                      (if enabled "" " (disabled)"))))
        (aiaos-cli--result-success :output output :order order :enabled enabled)))))

(put 'aiaos-cli-skill-provider/fallback 'aiaos-cli-command-spec
    '(:description "Set or query fallback strategy"
      :args ((:name "order" :type string :required nil :description "Order of providers (space-separated)"))
      :options ((:name "disable" :short "d" :type boolean :default false :description "Disable fallback")
                (:name "json" :short "j" :type boolean :default false :description "JSON output"))))

(provide 'aiaos-cli-skill-provider/commands/fallback)
;;; aiaos-cli-skill-provider/commands/fallback.el ends here
