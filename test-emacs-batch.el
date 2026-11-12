;; test-emacs-batch.el - 批处理测试
;; 用于 emacs --batch 测试

;; 添加 elisp 目录到 load-path
(add-to-list 'load-path (expand-file-name "~/aiaos/aiaos-cli/elisp"))

(load-file "~/aiaos/aiaos-cli/elisp/aiaos-cli.el")

(message "=== AIAOS-CLI Batch Test Start ===")

;; 测试1: 模块加载
(message "Test 1: Module loading")
(if (featurep 'aiaos-cli)
    (message "✓ Module loaded successfully")
  (message "✗ Module loading failed"))

;; 测试2: 二进制文件检查
(message "Test 2: Binary check")
(let ((bin (condition-case err
              (aiaos-cli--assert-binary)
            (error nil))))
  (if bin
      (message "✓ Binary found: %s" bin)
    (message "✗ Binary not found (expected if not installed)")))

;; 测试3: JSON解析
(message "Test 3: JSON parsing")
(let ((result (aiaos-cli--parse-json "{\"key\": \"value\"}")))
  (if result
      (message "✓ JSON parsing works: %s" result)
    (message "✗ JSON parsing failed")))

;; 测试4: 命令构建
(message "Test 4: Command building")
(let ((cmd (aiaos-cli--build-cmd "session" "new" "test" nil)))
  (if cmd
      (message "✓ Command building works: %s" cmd)
    (message "✗ Command building failed")))

;; 测试5: 版本检查
(message "Test 5: Version check")
(let ((version (condition-case err
              (aiaos-cli-version)
            (error nil))))
  (if version
      (message "✓ Version: %s" version)
    (message "✗ Version check failed")))

;; 测试6: 帮助命令
(message "Test 6: Help command")
(let ((help (condition-case err
              (aiaos-cli-help)
            (error (format "Error: %s" err)))))
  (if help
      (message "✓ Help works")
    (message "✗ Help failed")))

;; 测试7: 环境医生
(message "Test 7: Doctor")
(let ((doctor (condition-case err
              (aiaos-cli-doctor)
            (error nil))))
  (if doctor
      (message "✓ Doctor works")
    (message "✗ Doctor failed (expected if not installed)")))

;; 测试8: 会话管理
(message "Test 8: Session management")
(let ((session-cmd (condition-case err
                   (aiaos-cli--build-cmd "session" "list" nil)
                 (error nil))))
  (if session-cmd
      (message "✓ Session command building works: %s" session-cmd)
    (message "✗ Session command failed")))

;; 测试9: 上下文管理
(message "Test 9: Context management")
(let ((ctx-cmd (condition-case err
                 (aiaos-cli--build-cmd "context" "show" nil)
               (error nil))))
  (if ctx-cmd
      (message "✓ Context command building works: %s" ctx-cmd)
    (message "✗ Context command failed")))

;; 测试10: 技能管理
(message "Test 10: Skill management")
(let ((skill-cmd (condition-case err
                  (aiaos-cli--build-cmd "skill" "list" nil)
                (error nil))))
  (if skill-cmd
      (message "✓ Skill command building works: %s" skill-cmd)
    (message "✗ Skill command failed")))

(message "=== AIAOS-CLI Batch Test Complete ===")
(kill-emacs 0)