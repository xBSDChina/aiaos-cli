;;; aiaos-cli-skill-provider/commands/test.el --- 测试 Provider -*- lexical-binding: t; -*-

(require 'aiaos-cli-core)
(require 'aiaos-cli-router)
(require 'aiaos-cli-provider)
(require 'cl-lib)

(defun aiaos-cli-skill-provider/test (args options _ctx)
  "Test provider availability."
  (let* ((name (plist-get args :name))
         (json-mode (or (plist-get options :json) aiaos-cli--json-mode))
         (result (aiaos-cli-provider--test name)))
    (if (plist-get result :error)
        (if json-mode
            (aiaos-cli--result-error "PROVIDER_TEST_FAILED"
                                     (format "\"status\":\"error\",\"message\":\"%s\""
                                             (plist-get result :error)))
          (aiaos-cli--result-error "PROVIDER_TEST_FAILED"
                                   (plist-get result :error)))
      (let ((message (plist-get result :status)))
        (if json-mode
            (aiaos-cli--result-success
             :result (format "\"status\":\"ok\",\"message\":\"%s\"" message)
             :output message)
          (aiaos-cli--result-success :output message))))))

(put 'aiaos-cli-skill-provider/test 'aiaos-cli-command-spec
    '(:description "Test provider availability"
      :args ((:name "name" :type string :required t :description "Provider name"))
      :options ((:name "json" :short "j" :type boolean :default false :description "JSON output"))))

(provide 'aiaos-cli-skill-provider/commands/test)
;;; aiaos-cli-skill-provider/commands/test.el ends here
