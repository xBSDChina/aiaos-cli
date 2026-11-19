# AIAOS CLI Emacs 集成项目

## 项目概述

AIAOS CLI Emacs 集成项目是一个将 AIAOS CLI 框架与 Emacs 编辑器深度集成的项目。它利用 Emacs Lisp 的强大扩展能力，为 AIAOS 提供了一个完整的、可编程的编辑器控制层。

## 项目结构

```
~/aiaos/aiaos-cli/elisp/
├── aiaos-cli-core.el              # 核心配置
├── aiaos-cli-emacs-adapter.el     # Emacs适配层
├── aiaos-cli-emacs-controller.el  # Emacs管控层
├── aiaos-cli-emacs-call.el        # 双向调用层
├── aiaos-cli-emacs-callback.el    # 回调层
├── aiaos-cli-emacs-integration.el # 集成层（主入口）
├── aiaos-cli-llm.el               # LLM集成
├── aiaos-cli-llm-config-example.el # LLM配置示例
├── aiaos-cli-prompt-engine.el     # 提示引擎
├── aiaos-cli-ripgrep.el           # Ripgrep集成
├── aiaos-cli-toolbox.el           # 工具箱
├── aiaos-cli-window.el            # 窗口管理
├── aiaos-cli-workflow.el          # 工作流
├── aiaos-emacs-bridge.el          # Emacs桥接
├── aiaos-emacs-client.el          # Emacs客户端
├── aiaos-emacs-commands.el        # Emacs命令
├── aiaos-emacs-integration.el     # Emacs集成
├── aiaos-emacs-log.el             # Emacs日志
├── aiaos-emacs-llm.el             # Emacs LLM
├── aiaos-emacs-mcp.el             # Emacs MCP
├── aiaos-emacs-ripgrep.el         # Emacs Ripgrep
├── aiaos-emacs-window.el          # Emacs窗口
├── aiaos-emacs-workflow.el        # Emacs工作流
├── aiaos-rsi-elisp.el             # RSI Elisp
├── aiaos-rsi-emacs.el             # RSI Emacs
├── aiaos-rsi-emacs-client.el      # RSI Emacs客户端
├── aiaos-rsi-emacs-commands.el    # RSI Emacs命令
├── aiaos-rsi-emacs-integration.el # RSI Emacs集成
├── aiaos-rsi-emacs-log.el         # RSI Emacs日志
├── aiaos-rsi-emacs-llm.el         # RSI Emacs LLM
├── aiaos-rsi-emacs-mcp.el         # RSI Emacs MCP
├── aiaos-rsi-emacs-ripgrep.el     # RSI Emacs Ripgrep
├── aiaos-rsi-emacs-window.el      # RSI Emacs窗口
├── aiaos-rsi-emacs-workflow.el    # RSI Emacs工作流
├── test-aiaos-cli-llm.el          # LLM测试
├── test-aiaos-cli-llm-batch.el    # LLM批量测试
├── test-aiaos-cli-llm-emacsclient.el # LLM Emacs客户端测试
├── test-aiaos-cli-llm-function.el  # LLM功能测试
├── test-aiaos-cli-llm-interactive.el # LLM交互测试
├── test-aiaos-cli-llm-ripgrep.el  # LLM Ripgrep测试
├── test-aiaos-cli-llm-workflow.el  # LLM工作流测试
├── test-aiaos-cli-ripgrep.el      # Ripgrep测试
├── test-aiaos-cli-workflow.el      # 工作流测试
├── test-aiaos-cli-window.el        # 窗口测试
├── test-aiaos-emacs-bridge.el      # Emacs桥接测试
├── test-aiaos-emacs-client.el      # Emacs客户端测试
├── test-aiaos-emacs-commands.el    # Emacs命令测试
├── test-aiaos-emacs-integration.el # Emacs集成测试
├── test-aiaos-emacs-log.el         # Emacs日志测试
├── test-aiaos-emacs-llm.el         # Emacs LLM测试
├── test-aiaos-emacs-mcp.el         # Emacs MCP测试
├── test-aiaos-emacs-ripgrep.el     # Emacs Ripgrep测试
├── test-aiaos-emacs-window.el      # Emacs窗口测试
├── test-aiaos-emacs-workflow.el    # Emacs工作流测试
├── test-aiaos-rsi-emacs-client.el  # RSI Emacs客户端测试
├── test-aiaos-rsi-emacs-commands.el # RSI Emacs命令测试
├── test-aiaos-rsi-emacs-integration.el # RSI Emacs集成测试
├── test-aiaos-rsi-emacs-log.el     # RSI Emacs日志测试
├── test-aiaos-rsi-emacs-llm.el     # RSI Emacs LLM测试
├── test-aiaos-rsi-emacs-mcp.el     # RSI Emacs MCP测试
├── test-aiaos-rsi-emacs-ripgrep.el # RSI Emacs Ripgrep测试
├── test-aiaos-rsi-emacs-window.el  # RSI Emacs窗口测试
├── test-aiaos-rsi-emacs-workflow.el # RSI Emacs工作流测试
├── IMPLEMENTATION-SUMMARY.md       # 实现总结
├── MODULES.md                      # 模块说明
├── README-AIAOS-LLM.md             # AIAOS LLM说明
├── README-EMACS-INTEGRATION.md     # Emacs集成说明
├── TESTING.md                      # 测试文档
├── README.md                       # 项目说明（本文件）
└── LICENSE                         # MIT开源协议
```

## 核心架构

### 1. Emacs适配层 (aiaos-cli-emacs-adapter.el)

封装所有 Emacs API，提供统一的接口：
- 缓冲区管理
- 窗口管理
- 帧管理
- 模式管理
- 文本操作
- 命令执行
- 事件系统
- 缓存系统

### 2. Emacs管控层 (aiaos-cli-emacs-controller.el)

高层管理和调度：
- 状态管理
- 自动同步
- 缓冲区管控
- 窗口管控
- 帧管控
- 模式管控
- 文本编辑管控
- 命令管控

### 3. 双向调用层 (aiaos-cli-emacs-call.el)

AIAOS CLI 与 Emacs 之间的双向通信：
- 同步调用
- 异步调用
- 调用队列管理
- 超时处理
- 结果回调

### 4. 回调层 (aiaos-cli-emacs-callback.el)

Emacs 到 AIAOS CLI 的事件回调：
- 事件类型定义
- 回调注册表
- Hook 设置
- 事件触发
- 状态同步

### 5. 集成层 (aiaos-cli-emacs-integration.el)

整合所有组件，提供统一接口：
- 组件初始化
- Hook 设置
- 状态同步
- 自动同步定时器
- 便捷 API
- 事件处理
- 初始化和清理

## 安装

```bash
# 克隆项目
git clone https://github.com/xBSDChina/aiaos-cli
cd aiaos-cli/elisp

# 在 Emacs 中加载
(load-file "aiaos-cli-emacs-integration.el")
```

## 使用

```elisp
;; 加载集成层
(require 'aiaos-cli-emacs-integration)

;; 获取所有缓冲区
(aiaos-cli-emacs-integration-get-all-buffers)

;; 获取所有帧
(aiaos-cli-emacs-integration-get-frames)

;; 插入文本
(aiaos-cli-emacs-integration-insert-text "Hello, AIAOS!")

;; 执行命令
(aiaos-cli-emacs-integration-execute-command 'switch-to-buffer "*scratch*")
```

## 配置

```elisp
;; 自定义配置
(custom-set-variables
 '(aiaos-cli-emacs-controller-auto-sync t)
 '(aiaos-cli-emacs-controller-sync-interval 1000)
 '(aiaos-cli-emacs-call-timeout 5000))
```

## 贡献

欢迎贡献代码！请遵循以下步骤：

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -am 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

## 项目状态

✅ 已完成所有核心功能的实现和测试。项目可以直接在 Emacs 环境中加载使用。