# AIAOS CLI for Emacs

## 项目状态

**版本**: v1.0.0 (2026-10-13)
**状态**: ✅ 可正常运行，所有核心功能可用

## 快速开始

### 安装

```bash
# 方式 1: 在 .emacs.d/init.el 中添加
(add-to-list 'load-path "~/.emacs.d/aiaos-cli")
(require 'init "~/.emacs.d/aiaos-cli/init.el" t)

# 方式 2: 直接加载
emacs --eval "(require 'init \"/home/shjiaye8/.emacs.d/aiaos-cli/init.el\" t)"
```

### 使用

```
M-x aiaos        ; 启动交互会话
C-c a            ; 快捷键启动
M-x aiaos-cli-chat       ; 聊天
M-x aiaos-cli-send-message ; 发送消息
M-x aiaos-cli-clear      ; 清除会话
M-x aiaos-cli-history    ; 查看历史
M-x aiaos-cli-status     ; 查看状态
```

## 模块架构

```
aiaos-cli.el              # 核心框架
├── aiaos-cli-config.el   # 配置管理
├── aiaos-cli-llm.el      # LLM provider catalog
├── aiaos-cli-task.el     # 任务管理
├── aiaos-cli-exec.el     # 命令执行
├── aiaos-cli-msg.el      # 消息流
├── aiaos-cli-protocol.el # 协议支持
├── aiaos-cli-throttle.el # 限流
├── aiaos-cli-tracing.el  # 追踪
├── aiaos-cli-skill.el    # 技能管理
├── aiaos-llm-adapter.el  # LLM adapter
└── init.el               # 统一加载入口
```

## 支持的 Provider

- OpenAI
- Anthropic
- Google
- SenseNova

## 支持的协议

- HTTP
- MQTT
- WebSocket
- gRPC
- TCP
- UDP

## 调试接口

所有模块都提供 elisp 调试接口，可通过 emacsclient -e 进行调试：

```bash
# 启动 emacs daemon
emacs --daemon -q

# 调试示例
emacsclient -e "(aiaos-cli--list-protocols)"
emacsclient -e "(aiaos-cli-llm--status)"
emacsclient -e "(aiaos-cli-throttle-status)"
emacsclient -e "(aiaos-cli-tracing-status)"
```

## 开发

### 括号检查

```bash
# 方式 1: emacs batch 加载
emacs --batch -q -l init.el

# 方式 2: byte-compile
emacs --batch -q -f batch-byte-compile <file>.el

# 方式 3: python 计数
python3 -c "s=open('file.el').read(); print(s.count('(')-s.count(')'))"
```

### 文件结构

```
~/.emacs.d/aiaos-cli/
├── *.el              # 源代码
├── *.elc             # 编译后的字节码
├── *.bak.*           # 备份文件
├── TODO              # 开发 TODO
├── README.md         # 本文件
└── legacy/           # 旧版本代码
```

## 问题追踪

详见 `~/aiaos-cli_issues.txt`

## 许可证

MIT License
