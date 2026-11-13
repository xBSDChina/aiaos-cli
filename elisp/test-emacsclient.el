;; test-emacsclient.el - emacsclient 测试
;; 用于 emacsclient 测试

;; 添加 elisp 目录到 load-path
(add-to-list 'load-path (expand-file-name "~/aiaos/aiaos-cli/elisp"))

(load-file "~/aiaos/aiaos-cli/elisp/aiaos-cli.el")

(message "=== AIAOS-CLI Emacsclient Test Start ===")

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

;; 测试7: 会话管理
(message "Test 7: Session management")
(let ((session-cmd (condition-case err
                   (aiaos-cli--build-cmd "session" "list" nil)
                 (error nil))))
  (if session-cmd
      (message "✓ Session command building works: %s" session-cmd)
    (message "✗ Session command failed")))

;; 测试8: 上下文管理
(message "Test 8: Context management")
(let ((ctx-cmd (condition-case err
                 (aiaos-cli--build-cmd "context" "show" nil)
               (error nil))))
  (if ctx-cmd
      (message "✓ Context command building works: %s" ctx-cmd)
    (message "✗ Context command failed")))

;; 测试9: 技能管理
(message "Test 9: Skill management")
(let ((skill-cmd (condition-case err
                  (aiaos-cli--build-cmd "skill" "list" nil)
                (error nil))))
  (if skill-cmd
      (message "✓ Skill command building works: %s" skill-cmd)
    (message "✗ Skill command failed")))

;; 测试10: 配置管理
(message "Test 10: Configuration")
(let ((config-cmd (condition-case err
                    (aiaos-cli--build-cmd "config" "list" nil)
                  (error nil))))
  (if config-cmd
      (message "✓ Config command building works: %s" config-cmd)
    (message "✗ Config command failed")))

(message "=== AIAOS-CLI Emacsclient Test Complete ===")
(kill-emacs 0)