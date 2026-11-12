;;; test-aiaos-llm.el --- LLM Provider 管理与 Fallback 机制测试

(require 'aiaos-cli-llm)
(require 'ert)

;;; 测试 Provider 管理

(ert-deftest aiaos-llm-register-provider-test ()
  "Test provider registration."
  (aiaos-llm-register-provider "test-provider" "http://example.com" "test-model" "test-key")
  (let ((provider (aiaos-llm-get-provider "test-provider")))
    (should provider)
    (should (equal (cdr (assq :name provider)) "test-provider"))
    (should (equal (cdr (assq :endpoint provider)) "http://example.com"))
    (should (equal (cdr (assq :model provider)) "test-model"))
    (should (equal (cdr (assq :api-key provider)) "test-key"))))

(ert-deftest aiaos-llm-set-current-provider-test ()
  "Test setting current provider."
  (aiaos-llm-register-provider "test-provider-2" "http://example2.com" "test-model-2" "test-key-2")
  (should (aiaos-llm-set-current-provider "test-provider-2"))
  (should (equal aiaos-llm-current-provider "test-provider-2"))
  (should-not (aiaos-llm-set-current-provider "non-existent")))

;;; 测试 Fallback 机制

(ert-deftest aiaos-llm-get-next-fallback-test ()
  "Test getting next fallback provider."
  (setq aiaos-llm-fallback-chain '("p1" "p2" "p3"))
  (should (equal (aiaos-llm-get-next-fallback-provider "p1") "p2"))
  (should (equal (aiaos-llm-get-next-fallback-provider "p2") "p3"))
  (should (equal (aiaos-llm-get-next-fallback-provider "p3") "p1")) ; Loop back
  (should (equal (aiaos-llm-get-next-fallback-provider "unknown") "p1")))

;;; 测试消息格式化

(ert-deftest aiaos-llm-format-messages-test ()
  "Test message formatting."
  (let ((messages (aiaos-llm-format-messages "Hello" nil)))
    (should (= (length messages) 1))
    (should (equal (cdr (assq :role (car messages))) "user"))
    (should (equal (cdr (assq :content (car messages))) "Hello")))
  
  (let ((messages (aiaos-llm-format-messages "Hello" '((:system . "You are helpful")))))
    (should (= (length messages) 2))
    (should (equal (cdr (assq :role (car messages))) "system"))
    (should (equal (cdr (assq :content (car messages))) "You are helpful"))
    (should (equal (cdr (assq :role (cadr messages))) "user"))
    (should (equal (cdr (assq :content (cadr messages))) "Hello"))))

;;; 测试错误处理

(ert-deftest aiaos-llm-handle-error-test ()
  "Test error handling."
  (let ((result (aiaos-llm-handle-error (error "Test error") nil)))
    (should (stringp result))
    (should (string-match "Error occurred" result))))

(ert-deftest aiaos-llm-recover-from-error-test ()
  "Test error recovery."
  ;; Should not throw error even if recovery fails
  (should (aiaos-llm-recover-from-error (error "Timeout: process killed after 120 seconds") nil)))

;;; 测试任务链

(ert-deftest aiaos-llm-execute-task-test ()
  "Test task execution."
  (let ((result (aiaos-llm-execute-task "Hello world")))
    (should (stringp result))))

(ert-deftest aiaos-llm-start-task-chain-test ()
  "Test task chain start."
  (let ((tasks '("Task 1" "Task 2")))
    (should (aiaos-llm-start-task-chain tasks))))

;;; 测试工具系统

(ert-deftest aiaos-llm-tool-call-test ()
  "Test tool calling."
  (aiaos-llm-register-tool "test-tool"
                           (lambda (args) (format "Test result: %s" args))
                           "Test tool")
  (let ((result (aiaos-llm-tool-call "test-tool" '((:param . "value")))))
    (should (stringp result))
    (should (string-match "Test result" result))))

(ert-deftest aiaos-llm-tool-not-found-test ()
  "Test tool not found error."
  (let ((result (aiaos-llm-tool-call "non-existent-tool" nil)))
    (should (stringp result))
    (should (string-match "Tool not found" result))))

;;; 测试配置管理

(ert-deftest aiaos-llm-config-test ()
  "Test configuration management."
  (aiaos-set-config 'test-key "test-value")
  (should (equal (aiaos-get-config 'test-key) "test-value"))
  (aiaos-set-config 'test-key "new-value")
  (should (equal (aiaos-get-config 'test-key) "new-value")))

;;; 运行所有测试

(provide 'test-aiaos-llm)

;;; 手动测试函数

(defun aiaos-llm-run-manual-tests ()
  "Run manual tests for AIAOS LLM features."
  (interactive)
  
  (message "=== AIAOS LLM Manual Tests ===")
  
  ;; Test 1: Provider registration
  (message "Test 1: Registering providers...")
  (aiaos-llm-register-provider "manual-test" "http://example.com" "test-model" "test-key")
  (message "✓ Provider registered")
  
  ;; Test 2: Fallback chain
  (message "Test 2: Building fallback chain...")
  (aiaos-llm-build-fallback-chain)
  (message "✓ Fallback chain: %s" aiaos-llm-fallback-chain)
  
  ;; Test 3: Message formatting
  (message "Test 3: Formatting messages...")
  (let ((msgs (aiaos-llm-format-messages "Test" nil)))
    (message "✓ Formatted %d messages" (length msgs)))
  
  ;; Test 4: Error handling
  (message "Test 4: Error handling...")
  (let ((err-result (aiaos-llm-handle-error (error "Test error") nil)))
    (message "✓ Error handled: %s" (substring err-result 0 30)))
  
  (message "=== All manual tests completed ==="))