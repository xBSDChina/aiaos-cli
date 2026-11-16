# AIAOS-CLI Elisp 适配层架构设计文档

## 目录

1. [项目概述](#项目概述)
2. [架构全景图](#架构全景图)
3. [核心层](#核心层)
4. [状态管理层](#状态管理层)
5. [上下文层](#上下文层)
6. [生命周期层](#生命周期层)
7. [组件层](#组件层)
8. [主题层](#主题层)
9. [组件库层](#组件库层)
10. [路由层](#路由层)
11. [应用层](#应用层)
12. [LLM Provider 层](#llm-provider-层)
13. [Elisp 执行沙箱层](#elisp-执行沙箱层)
14. [技能系统](#技能系统)
15. [依赖关系图](#依赖关系图)
16. [数据流图](#数据流图)
17. [模块状态与改进计划](#模块状态与改进计划)

---

## 项目概述

AIAOS-CLI 是一个基于 Emacs Lisp 的智能 CLI 工具，采用 **Elisp 为主、外部进程为辅** 的架构范式。项目通过模块化设计实现了：

- 响应式状态管理（React 风格 useState）
- 依赖注入系统（Context API 风格）
- 组件化 UI（Vue/React 风格组件树）
- 主题系统（可定制深色/浅色主题）
- 路由系统（React Router 风格页面导航）
- LLM Provider 管理（多 provider fallback 机制）
- Elisp 执行沙箱（execute_elisp 标准工具）
- 技能系统（可扩展的技能包）

---

## 架构全景图

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                   AIAOS-CLI 架构全景                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │  aiaos-cli   │    │ aiaos-cli-  │    │ aiaos-cli-  │    │ aiaos-cli-  │      │
│  │  .el         │    │  llm.el     │    │  elisp.el   │    │  core.el    │      │
│  │  (主入口)    │    │ (LLM 引擎)  │    │ (沙箱执行)  │    │ (核心定义)  │      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                   │                   │              │
│         │    ┌──────────────┴───────────────────┴───────────────┐    │              │
│         │    │             核心基础层 (Core)                      │    │              │
│         │    │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐│    │              │
│         │    │  │aiaos-cli │ │aiaos-cli │ │aiaos-cli │ │aiaos-cli ││    │              │
│         │    │  │ core.el  │ │ state.el │ │ context.el│ │ lifecycle││    │              │
│         │    │  └──────────┘ └──────────┘ └──────────┘ └──────────┘│    │              │
│         │    └──────────────────────────────────────────────────────┘    │              │
│         │                                                                   │              │
│         │    ┌──────────────────────────────────────────────────────┐       │              │
│         │    │              TUI 组件层 (TUI)                          │       │              │
│         │    │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐│       │              │
│         │    │  │aiaos-cli │ │aiaos-cli │ │aiaos-cli │ │aiaos-cli ││       │              │
│         │    │  │component │ │theme.el  │ │components│ │ router.el││       │              │
│         │    │  │ .el      │ │          │ │  .el    │ │   .el    ││       │              │
│         │    │  └──────────┘ └──────────┘ └──────────┘ └──────────┘│       │              │
│         │    └──────────────────────────────────────────────────────┘       │              │
│         │                                                                   │              │
│         │    ┌──────────────────────────────────────────────────────┐       │              │
│         │    │              应用层 (App)                             │       │              │
│         │    │  ┌────────────────────────────────────────────────┐  │       │              │
│         │    │  │            aiaos-cli-app.el                    │  │       │              │
│         │    │  │    (TUI 应用入口 + 路由注册 + 页面组件)         │  │       │              │
│         │    │  └────────────────────────────────────────────────┘  │       │              │
│         │    └──────────────────────────────────────────────────────┘       │              │
│         │                                                                   │              │
│         └───────────────────────────────────────────────────────────────────┘              │
│                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────┐     │
│  │                        技能系统 (Skills)                                    │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │     │
│  │  │base64-   │ │ date-    │ │ emacs-   │ │ file-    │ │ hello-   │     │     │
│  │  │  tools   │ │  tools   │ │  tools   │ │  tools   │ │  world   │     │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘     │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                            │     │
│  │  │skill-    │ │ string-  │ │ text-    │                            │     │
│  │  │management│ │  tools   │ │  tools   │                            │     │
│  │  └──────────┘ └──────────┘ └──────────┘                            │     │
│  └─────────────────────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 核心层

### aiaos-cli-core.el

**文件路径**: `lisp/aiaos-cli-core.el`  
**行数**: ~79 行  
**状态**: ✅ 已完成

**功能**:
- AIAOS 系统配置管理（defgroup aiaos）
- LLM Provider 管理（注册、查询、切换）
- Fallback 链机制（健康检查 + 自动切换）
- HTTP 客户端（纯 elisp 实现，替代 Python bridge）
- SSE 流式请求支持
- 记忆系统（持久化存储）
- 日志系统
- 任务链路连续执行
- 工具系统注册

**关键数据结构**:
```elisp
;; Provider 配置格式
((:name . "provider-name")
 (:endpoint . "https://api.example.com")
 (:model . "gpt-4")
 (:api-key . "sk-...")
 (:options . ((:timeout . 5400)))
 (:status . healthy|unstable|down)
 (:last-check . nil)
 (:failure-count . 0))
```

**关键函数**:
- `aiaos-llm-build-request-url` - 构建请求 URL
- `aiaos-llm-build-request-headers` - 构建请求头
- `aiaos-llm-build-request-data-full` - 构建完整请求数据
- `aiaos-http-request` - 纯 elisp HTTP 请求
- `aiaos-http-stream-request` - SSE 流式请求
- `aiaos-probe-provider` - 探测 provider 状态
- `aiaos-build-fallback-chain` - 构建 fallback 链

---

## 状态管理层

### aiaos-cli-state.el

**文件路径**: `lisp/aiaos-cli-state.el`  
**行数**: ~225 行  
**状态**: ✅ 已完成

**功能**:
- 响应式状态管理（React 风格 useState）
- 状态订阅/通知机制
- 批量更新（batch update）
- 派生状态（derived state）
- 状态持久化

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--state
  (value nil)        ; 当前值
  (subscribers nil)  ; 订阅者列表
  (locked nil)       ; 防止并发修改
  (id nil))          ; 唯一标识符
```

**关键函数**:
- `aiaos-cli--state-create` - 创建响应式状态
- `aiaos-cli--state-get` - 获取状态值
- `aiaos-cli--state-set` - 设置状态值（触发更新）
- `aiaos-cli--state-update` - 函数式更新
- `aiaos-cli--state-subscribe` - 订阅状态变化
- `aiaos-cli--state-derive` - 派生状态

---

## 上下文层

### aiaos-cli-context.el

**文件路径**: `lisp/aiaos-cli-context.el`  
**行数**: ~284 行  
**状态**: ✅ 已完成

**功能**:
- 依赖注入系统（Context API 风格）
- 上下文提供者/消费者
- 嵌套上下文支持
- 上下文查找（递归向上）
- 上下文快照/恢复

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--context
  (parent nil)       ; 父上下文
  (values (make-hash-table :test 'equal)) ; 值哈希表
  (name nil))        ; 上下文名称
```

**关键函数**:
- `aiaos-cli--context-create` - 创建上下文
- `aiaos-cli--context-get` - 获取上下文值
- `aiaos-cli--context-set` - 设置上下文值
- `aiaos-cli--context-provider` - 上下文提供者（宏）
- `aiaos-cli--context-consumer` - 上下文消费者（宏）

---

## 生命周期层

### aiaos-cli-lifecycle.el

**文件路径**: `lisp/aiaos-cli-lifecycle.el`  
**行数**: ~346 行  
**状态**: ✅ 已完成

**功能**:
- 组件生命周期管理（mount/unmount）
- 副作用管理（use-effect 风格）
- 清理函数注册（use-on-drop 风格）
- 组件树管理

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--effect
  (dependencies nil)  ; 依赖列表
  (body nil)          ; 副作用函数
  (cleanup nil)       ; 清理函数
  (component-id nil)  ; 所属组件 ID
  (running nil))      ; 是否正在运行
```

**关键函数**:
- `aiaos-cli--use-effect` - 注册副作用（宏）
- `aiaos-cli--use-on-drop` - 注册清理函数（宏）
- `aiaos-cli--lifecycle-mount` - 挂载组件（宏）
- `aiaos-cli--lifecycle-unmount` - 卸载组件
- `aiaos-cli--lifecycle-update` - 更新组件（宏）

---

## 组件层

### aiaos-cli-component.el

**文件路径**: `lisp/aiaos-cli-component.el`  
**行数**: ~360 行  
**状态**: ✅ 已完成

**功能**:
- 组件定义和注册
- 属性管理（Props）
- 子组件管理
- 组件渲染
- 组件组合
- HOC（高阶组件）
- 组件 memo 化

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--component
  (name nil)          ; 组件名称
  (props (make-hash-table :test 'equal)) ; 属性哈希表
  (state nil)         ; 本地状态
  (children nil)      ; 子组件列表
  (render nil)        ; 渲染函数
  (effects nil)       ; 副作用列表
  (context nil))      ; 组件上下文
```

**关键函数**:
- `aiaos-cli--component-create` - 创建组件
- `aiaos-cli--component-set-prop` - 设置属性
- `aiaos-cli--component-get-prop` - 获取属性
- `aiaos-cli--component-add-child` - 添加子组件
- `aiaos-cli--render-component` - 渲染组件
- `aiaos-cli--define-component` - 定义组件（宏）
- `aiaos-cli--compose` - 组合组件（宏）
- `aiaos-cli--fragment` - 片段容器（宏）

---

## 主题层

### aiaos-cli-theme.el

**文件路径**: `lisp/aiaos-cli-theme.el`  
**行数**: ~351 行  
**状态**: ✅ 已完成

**功能**:
- 主题定义（深色/浅色）
- 颜色管理
- 样式管理
- 图标管理
- 主题切换
- Face 创建

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--theme
  (name "custom")     ; 主题名称
  (colors (make-hash-table :test 'equal))  ; 颜色定义
  (styles (make-hash-table :test 'equal))  ; 样式定义
  (icons (make-hash-table :test 'equal)))  ; 图标定义
```

**内置主题**:
- `aiaos-cli--theme-dark` - 深色主题
- `aiaos-cli--theme-light` - 浅色主题

**关键函数**:
- `aiaos-cli--theme-register` - 注册主题
- `aiaos-cli--theme-get` - 获取主题
- `aiaos-cli--theme-current` - 获取当前主题
- `aiaos-cli--theme-apply` - 应用主题到 buffer
- `aiaos-cli--theme-toggle` - 切换主题

---

## 组件库层

### aiaos-cli-components.el

**文件路径**: `lisp/aiaos-cli-components.el`  
**行数**: ~448 行  
**状态**: ✅ 已完成

**功能**:
- 文本组件
- 边框组件
- 列表组件
- 输入框组件
- 模态框组件
- 表格组件
- 进度条组件
- 状态栏组件
- 组合组件（垂直/水平）
- 分割面板组件
- 标签页组件
- 快捷键提示组件
- 虚拟列表组件

**关键函数**:
- `aiaos-cli-component-text` - 文本组件
- `aiaos-cli-component-border` - 边框组件
- `aiaos-cli-component-list` - 列表组件
- `aiaos-cli-component-input` - 输入框组件
- `aiaos-cli-component-modal` - 模态框组件
- `aiaos-cli-component-table` - 表格组件
- `aiaos-cli-component-progress` - 进度条组件
- `aiaos-cli-component-statusbar` - 状态栏组件
- `aiaos-cli-component-vertical` - 垂直组合
- `aiaos-cli-component-horizontal` - 水平组合
- `aiaos-cli-component-split` - 分割面板
- `aiaos-cli-component-tabs` - 标签页
- `aiaos-cli-component-shortcuts` - 快捷键提示
- `aiaos-cli-component-vlist` - 虚拟列表

---

## 路由层

### aiaos-cli-router.el

**文件路径**: `lisp/aiaos-cli-router.el`  
**行数**: ~382 行  
**状态**: ✅ 已完成

**功能**:
- 路由定义和注册
- 路由匹配
- 页面导航
- 路由历史记录
- 路由守卫
- 路由中间件
- 嵌套路由

**关键数据结构**:
```elisp
(cl-defstruct aiaos-cli--route
  (path "/")          ; 路径
  (component nil)     ; 组件对象或名称
  (params nil)        ; 参数
  (meta nil))         ; 元数据
```

**关键函数**:
- `aiaos-cli--router-create-route` - 创建路由
- `aiaos-cli--router-match` - 匹配路由
- `aiaos-cli--router-navigate` - 导航到指定路径
- `aiaos-cli--router-current` - 获取当前路由
- `aiaos-cli--router-render` - 渲染路由
- `aiaos-cli--router-back` - 返回上一页
- `aiaos-cli--router-add` - 添加路由

---

## 应用层

### aiaos-cli-app.el

**文件路径**: `lisp/aiaos-cli-app.el`  
**行数**: ~471 行  
**状态**: ✅ 已完成

**功能**:
- TUI 应用初始化
- 应用渲染（头部、导航栏、状态栏）
- 页面组件（首页、总览、技能、代理、设置）
- 路由注册
- 应用主模式
- 应用退出

**关键函数**:
- `aiaos-cli--app-init` - 初始化应用
- `aiaos-cli--app-render` - 渲染应用界面
- `aiaos-cli--app-run` - 运行应用
- `aiaos-cli--app-quit` - 退出应用
- `aiaos-cli-app-mode` - 应用主模式

---

## LLM Provider 层

### aiaos-cli-llm.el

**文件路径**: `lisp/aiaos-cli-llm.el`  
**行数**: ~600+ 行  
**状态**: ✅ 已完成

**功能**:
- LLM Provider 注册和管理
- Fallback 链机制
- 错误自愈
- SSE 流式支持
- 工具调用支持
- 会话管理
- 记忆系统

**关键函数**:
- `aiaos-llm-register-provider` - 注册 provider
- `aiaos-llm-probe-provider` - 探测 provider 状态
- `aiaos-llm-build-fallback-chain` - 构建 fallback 链
- `aiaos-llm-call` - 调用 LLM（带 fallback）
- `aiaos-llm-tool-call` - 工具调用
- `aiaos-llm-build-tools-schema` - 构建工具 schema

---

## Elisp 执行沙箱层

### aiaos-cli-elisp.el

**文件路径**: `lisp/aiaos-cli-elisp.el`  
**行数**: ~400+ 行  
**状态**: ✅ 已完成

**功能**:
- execute_elisp 标准工具
- 三层安全沙箱：
  1. 静态策略检查（purpose + 高危符号扫描）
  2. 子进程隔离执行（emacs --batch 独立实例）
  3. 运行时资源限制（超时、输出截断）
- 兼容 ;;elisp-exec 文本协议

**关键函数**:
- `aiaos-cli-elisp-execute` - execute_elisp 标准入口
- `aiaos-cli-elisp-policy-check` - 静态策略检查
- `aiaos-cli-elisp--run-subprocess` - 子进程隔离执行
- `aiaos-cli-elisp--tool-handler` - 工具处理函数

---

## 技能系统

### 技能目录结构

```
skills/
├── base64-tools/
│   ├── skill.yaml
│   ├── commands/
│   │   ├── encode.el
│   │   └── decode.el
│   └── hooks/
│       └── on-load.el
├── date-tools/
│   ├── skill.yaml
│   ├── commands/
│   │   └── add.el
│   └── hooks/
│       └── on-load.el
├── emacs-tools/
│   ├── skill.yaml
│   ├── commands/
│   │   └── format.el
│   └── hooks/
│       └── on-load.el
├── file-tools/
│   ├── skill.yaml
│   ├── commands/
│   │   ├── read.el
│   │   └── write.el
│   └── hooks/
│       └── on-load.el
├── hello-world/
│   ├── skill.yaml
│   ├── commands/
│   │   └── hello.el
│   └── hooks/
│       └── on-load.el
├── skill-management/
│   ├── skill.yaml
│   ├── commands/
│   │   ├── validate.el
│   │   ├── list.el
│   │   ├── deps.el
│   │   ├── run.el
│   │   └── filter_select.el
│   └── hooks/
│       ├── on-load.el
│       ├── pre-command.el
│       └── post-command.el
├── string-tools/
│   ├── skill.yaml
│   ├── commands/
│   │   ├── reverse.el
│   │   ├── trim.el
│   │   ├── pad.el
│   │   └── repeat.el
│   └── hooks/
│       └── on-load.el
└── text-tools/
    ├── skill.yaml
    ├── commands/
    │   ├── case.el
    │   └── wordcount.el
    └── hooks/
        └── on-load.el
```

### 技能加载流程

```
1. aiaos-cli-init (可选 load-skills)
   ↓
2. aiaos-cli-skill-load-all
   ↓
3. 扫描 skills/ 目录
   ↓
4. 解析 skill.yaml 元数据
   ↓
5. 加载 commands/*.el
   ↓
6. 加载 hooks/*.el
   ↓
7. 执行 on-load hook
   ↓
8. 注册技能命令到 aiaos-llm-tools
```

---

## 依赖关系图

```
aiaos-cli-core (基础)
  ↓
aiaos-cli-state (状态管理)
  ↓
aiaos-cli-context (上下文) → aiaos-cli-lifecycle (生命周期)
  ↓
aiaos-cli-component (组件基础) → aiaos-cli-theme (主题)
  ↓
aiaos-cli-components (组件库) → aiaos-cli-router (路由)
  ↓
aiaos-cli-app (应用入口)
  ↓
aiaos-cli-llm (LLM Provider 管理)
  ↓
aiaos-cli-elisp (Elisp 执行沙箱)
  ↓
aiaos-cli (主入口)
```

**依赖规则**:
- 单向依赖，避免循环
- 高层模块可以依赖低层模块
- 低层模块不应依赖高层模块

---

## 数据流图

### LLM 请求数据流

```
用户输入
  ↓
aiaos-cli-agent-send
  ↓
aiaos-cli--agent-dialog-pure
  ↓
aiaos-llm-full-chat
  ↓
aiaos-llm--http-once (遍历 provider fallback 链)
  ↓
aiaos-http-stream-request (SSE 流式)
  ↓
LLM Provider API
  ↓
SSE 事件流 (data: {...})
  ↓
aiaos-llm--merge-tool-calls (合并工具调用)
  ↓
aiaos-llm-execute-tool-arg (执行工具)
  ↓
工具结果回传 LLM
  ↓
最终回复 → 用户
```

### 技能执行数据流

```
用户调用 M-x aiaos-cli-skill-run
  ↓
aiaos-cli-skill-load (加载技能)
  ↓
读取 skill.yaml
  ↓
加载 commands/*.el
  ↓
执行 aiaos-cli-skill-<name>/<command>
  ↓
返回 JSON 结果
  ↓
aiaos-cli--show-result (展示结果)
```

---

## 模块状态与改进计划

### 当前状态

| 模块 | 文件 | 行数 | 状态 | 测试覆盖 |
|------|------|------|------|----------|
| 核心 | aiaos-cli-core.el | ~79 | ✅ | ✅ |
| 状态 | aiaos-cli-state.el | ~225 | ✅ | ✅ |
| 上下文 | aiaos-cli-context.el | ~284 | ✅ | ✅ |
| 生命周期 | aiaos-cli-lifecycle.el | ~346 | ✅ | ✅ |
| 组件基础 | aiaos-cli-component.el | ~360 | ✅ | ✅ |
| 主题 | aiaos-cli-theme.el | ~351 | ✅ | ✅ |
| 组件库 | aiaos-cli-components.el | ~448 | ✅ | ✅ |
| 路由 | aiaos-cli-router.el | ~382 | ✅ | ✅ |
| 应用 | aiaos-cli-app.el | ~471 | ✅ | ✅ |
| LLM | aiaos-cli-llm.el | ~600+ | ✅ | ✅ |
| Elisp 沙箱 | aiaos-cli-elisp.el | ~400+ | ✅ | ✅ |
| 主入口 | aiaos-cli.el | ~1000+ | ✅ | ✅ |

### 改进计划

1. **技能自动加载**: 实现技能自动发现和加载机制，减少手动调用
2. **代码健康度扩展**: 增加 defcustom 的 defgroup、版本号格式、Package-Requires 等检查
3. **Doctor fix 自动化**: 实现自动修复能力（如自动补 lexical-binding 声明）
4. **TUI 完善**: 增加更多交互组件，提升用户体验
5. **文档完善**: 补充更多使用示例和最佳实践
6. **性能优化**: 关注异步调用超时控制、进程池管理
7. **Provider 扩展**: 考虑更多 Provider 接入和智能路由

---

**文档版本**: 1.0  
**更新时间**: 2026-10-30  
**维护者**: AIAOS Project