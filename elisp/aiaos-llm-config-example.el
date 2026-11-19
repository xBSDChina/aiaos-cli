;;; aiaos-llm-config-example.el --- AIAOS-LLM 配置示例  -*- lexical-binding: t; -*-

;; 展示如何配置多个 LLM provider 和 fallback 链

(require 'aiaos-cli-llm)

;; 注册多个 LLM provider
(aiaos-llm-register-provider
 "openai"
 "https://api.openai.com/v1"
 "gpt-4"
 (or (getenv "OPENAI_API_KEY") "demo-key"))

(aiaos-llm-register-provider
 "anthropic"
 "https://api.anthropic.com"
 "claude-3-opus"
 (or (getenv "ANTHROPIC_API_KEY") "demo-key")
 '((timeout . 60)
   (retries . 3)))

(aiaos-llm-register-provider
 "google"
 "https://generativelanguage.googleapis.com"
 "gemini-pro"
 (or (getenv "GOOGLE_API_KEY") "demo-key"))

;; 设置默认 provider
(aiaos-llm-set-current-provider "openai")

;; 启用调试模式（可选）
;; (aiaos-llm-debug-toggle)

;; 初始化
(aiaos-llm-init)

;; 使用示例：
;; 以下示例操作在用户显式调用时才执行，避免加载时副作用

(defun aiaos-llm-config-example-demo ()
  "运行 LLM 配置示例演示。"
  (interactive)
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
  (message "AIAOS LLM configuration example demo complete"))

;; 注册演示命令
(provide 'aiaos-llm-config-example)
