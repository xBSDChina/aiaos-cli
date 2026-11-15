;;; aiaos-cli-skill-provider/commands/fallback-order.el --- 查询/设置 fallback 顺序 -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/fallback-order (args options _ctx)
  "Query or set fallback order."
  (let* ((json-mode (or (plist-get options :json) aiaos-cli--json-mode)))
    (if (and (listp args) (not (null args)))
        ;; Set mode - args is the full provider list
        (let* ((result (aiaos-cli-provider--fallback-set args)))
          (if json-mode
              (aiaos-cli--result-success
               :order (aiaos-cli-provider--fallback-order)
               :enabled (aiaos-cli-provider--fallback-enabled))
            (aiaos-cli--result-success
             :output (format "Set: %s (%s)"
                            (mapconcat #'identity (aiaos-cli-provider--fallback-order) ", ")
                            (if (aiaos-cli-provider--fallback-enabled) "on" "off")))))
      ;; Query mode
      (let* ((order (aiaos-cli-provider--fallback-order))
             (enabled (aiaos-cli-provider--fallback-enabled)))
        (if json-mode
            (aiaos-cli--result-success :order order :enabled enabled)
          (aiaos-cli--result-success
           :output (format "Order: %s (%s)"
                          (mapconcat #'identity order ", ")
                          (if enabled "on" "off"))))))))

(put 'aiaos-cli-skill-provider/fallback-order 'aiaos-cli-command-spec
    '(:description "Query or set fallback order"
      :args ((:name "order" :type string :required nil :description "Order of providers"))
      :options ((:name "json" :short "j" :type boolean :default false :description "JSON output"))))

(provide 'aiaos-cli-skill-provider/commands/fallback-order)
;;; aiaos-cli-skill-provider/commands/fallback-order.el ends here
