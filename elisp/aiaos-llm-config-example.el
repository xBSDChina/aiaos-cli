;;; aiaos-llm-config-example.el --- AIAOS-LLM 配置示例  -*- lexical-binding: t; -*-

;; 展示如何配置多个 LLM provider 和 fallback 链

;; 注册多个 LLM provider
(aiaos-llm-register-provider
 "openai"
 "https://api.openai.com/v1"
 "gpt-4"
 (getenv "OPENAI_API_KEY"))

(aiaos-llm-register-provider
 "anthropic"
 "https://api.anthropic.com"
 "claude-3-opus"
 (getenv "ANTHROPIC_API_KEY")
 '((timeout . 60)
   (retries . 3)))

(aiaos-llm-register-provider
 "google"
 "https://generativelanguage.googleapis.com"
 "gemini-pro"
 (getenv "GOOGLE_API_KEY"))

;; 设置默认 provider
(aiaos-llm-set-current-provider "openai")

;; 启用调试模式（可选）
;; (aiaos-llm-debug-toggle)

;; 初始化
(aiaos-llm-init)

;; 使用示例：

;; 1. 简单消息
(aiaos-llm-message "你好，请介绍一下自己")

;; 2. 连续任务链
(let ((tasks '("什么是AI?" "如何学习AI?" "AI的未来是什么?")))
  (aiaos-llm-start-task-chain tasks))

;; 3. 探测所有 provider 状态
(aiaos-llm-probe-all-providers)

;; 4. 构建 fallback 链
(aiaos-llm-build-fallback-chain)

;; 5. 查看当前 fallback 链
(message "Fallback chain: %s" aiaos-llm-fallback-chain)

(message "AIAOS LLM configuration example loaded successfully")
(provide 'aiaos-llm-config-example)
