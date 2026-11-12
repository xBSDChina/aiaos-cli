# AIAOS-LLM 增强版文档

## 概述

AIAOS-LLM 是一个基于 Emacs 的智能代理系统，支持多 LLM provider 管理、错误自愈、连续任务执行等功能。

## 核心特性

### 1. 多 LLM Provider 管理

系统支持注册多个 LLM provider，并自动进行状态探测和分类。

#### Provider 状态分类

- **A类（Healthy）**: 完全可访问，响应时间 < 2秒
- **B类（Unstable）**: 可连接但交互不稳定，响应时间 > 2秒
- **C类（Down）**: 连接中断、超时或拒绝连接

#### 状态探测

```elisp
;; 探测所有 provider 状态
(aiaos-llm-probe-all-providers)

;; 分类 provider
(aiaos-llm-classify-providers)
;; 返回: (:healthy ... :unstable ... :down ...)
```

### 2. Fallback 机制

当主 provider 出错时，系统会自动切换到 fallback 链中的下一个 provider。

#### Fallback 链构建

系统自动从健康（A类）provider 构建 fallback 链：

```elisp
(aiaos-llm-build-fallback-chain)
;; 设置 aiaos-llm-fallback-chain 变量
```

#### 切换机制

- **顺序切换**: 按 fallback 链顺序切换
- **全队列再循环**: 到达链尾后从头开始
- **同步切换**: 切换时同时更新 name, endpoint, model

### 3. 错误自愈能力

系统支持以下错误类型的自动恢复：

| 错误类型 | HTTP 代码 | 恢复策略 |
|---------|----------|---------|
| 超时 | Timeout | 切换 provider |
| 服务不可用 | 502, 503 | 切换 provider + 延迟重试 |
| 请求过于频繁 | 429 | 延迟 2秒 + 切换 provider |
| 其他 HTTP 错误 | 4xx, 5xx | 切换 provider |

### 4. 连续任务执行

支持任务链的连续执行，provider 切换时不影响任务链的持续执行。

```elisp
;; 定义任务链
(let ((tasks '("任务1" "任务2" "任务3")))
  (aiaos-llm-start-task-chain tasks))
```

### 5. 消息格式支持

系统支持 LLM provider 的所有消息格式（约13种），包括：
- 普通文本消息
- 广播消息
- 工具执行消息
- 思考过程（thinking）
- 等等

## 配置指南

### 注册 Provider

```elisp
;; 基本用法
(aiaos-llm-register-provider
 "openai"
 "https://api.openai.com/v1"
 "gpt-4"
 (system-getenv "OPENAI_API_KEY"))

;; 带选项的用法
(aiaos-llm-register-provider
 "anthropic"
 "https://api.anthropic.com"
 "claude-3-opus"
 (system-getenv "ANTHROPIC_API_KEY")
 '((timeout . 60)    ; 自定义超时
   (retries . 3)))  ; 自定义重试次数
```

### 设置 Fallback 链

系统会自动从健康 provider 构建 fallback 链，也可以手动设置：

```elisp
;; 手动设置 fallback 链（按优先级排序）
(setq aiaos-llm-fallback-chain '("openai" "anthropic" "google"))
```

### 初始化

```elisp
;; 初始化系统
(aiaos-llm-init)

;; 可选：启用调试模式
;; (aiaos-llm-debug-toggle)
```

## API 参考

### 主要函数

#### `aiaos-llm-message` (message &optional context)
发送消息到 LLM 并获取响应。

#### `aiaos-llm-start-task-chain` (tasks)
启动连续任务链。

#### `aiaos-llm-probe-all-providers`
探测所有 provider 状态。

#### `aiaos-llm-build-fallback-chain`
构建 fallback 链。

#### `aiaos-llm-set-current-provider` (name)
设置当前活跃的 provider。

#### `aiaos-llm-get-current-provider`
获取当前活跃的 provider 配置。

### 配置变量

#### `aiaos-llm-providers`
已注册的 provider 列表。

#### `aiaos-llm-fallback-chain`
fallback 链（provider 名称列表）。

#### `aiaos-llm-provider-timeout`
超时时间（秒），默认 120。

#### `aiaos-llm-max-retries`
最大重试次数，默认 3。

## 高级用法

### 自定义消息格式

可以通过 `aiaos-llm-format-messages` 函数自定义消息格式：

```elisp
(let ((context '((:system . "你是一个有帮助的助手")
                 (:role "user" :content "之前的问题")
                 (:role "assistant" :content "之前的回答"))))
  (aiaos-llm-format-messages "新问题" context))
```

### 工具扩展

注册自定义工具：

```elisp
(aiaos-llm-register-tool
 "custom-tool"
 (lambda (args)
   (format "Custom tool executed with: %s" args))
 "My custom tool")
```

### 错误处理定制

可以通过重写以下函数定制错误处理：

- `aiaos-llm-handle-error`: 主错误处理
- `aiaos-llm-recover-from-error`: 错误恢复
- `aiaos-llm-handle-timeout-error`: 超时处理
- `aiaos-llm-handle-server-error`: 服务器错误处理
- `aiaos-llm-handle-rate-limit-error`: 限流处理

## 故障排除

### 常见问题

1. **Provider 连接失败**
   - 检查 API key 是否正确
   - 检查 endpoint URL 是否可访问
   - 运行 `aiaos-llm-probe-all-providers` 查看状态

2. **Fallback 不工作**
   - 确保有至少一个健康 provider
   - 运行 `aiaos-llm-build-fallback-chain` 重建链

3. **任务链中断**
   - 检查错误日志
   - 确保 fallback 链中有可用 provider
   - 增加 `aiaos-llm-max-retries`

### 调试模式

```elisp
;; 启用调试
;; (aiaos-llm-debug-toggle)

;; 查看日志
;; 日志会显示在 *Messages* 缓冲区
```

## 架构说明

### 组件关系

```
AIAOS-LLM
├── Provider 管理
│   ├── 注册/注销 provider
│   ├── 状态探测
│   └── 分类（A/B/C）
├── Fallback 机制
│   ├── 构建 fallback 链
│   ├── 顺序切换
│   └── 循环切换
├── 错误自愈
│   ├── 超时处理
│   ├── HTTP 错误处理
│   └── 自动恢复
├── 任务执行
│   ├── 连续任务链
│   └── 异步执行
└── 消息格式
    ├── 13种消息格式支持
    └── JSON 序列化
```

### 数据流

1. 用户输入消息
2. 系统选择当前 provider
3. 发送请求到 LLM API
4. 如果出错，触发 fallback 机制
5. 切换到下一个健康 provider
6. 重试请求
7. 返回响应给用户

### 性能优化

- 状态探测结果缓存
- Fallback 链预构建
- 异步任务执行
- 延迟重试机制