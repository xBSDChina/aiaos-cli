# aiaos-cli 模块架构 (R1324)

## 概述

R1324 任务将 `aiaos-cli.el` 按设计文档拆分为 9 个独立模块，覆盖状态管理、上下文、组件化、主题、路由、生命周期和 TUI 应用层。

## 模块列表

| 模块 | 文件 | 行数 | 状态 |
|------|------|------|------|
| 核心 | `aiaos-cli-core.el` | 79 | ✅ |
| 状态 | `aiaos-cli-state.el` | 225 | ✅ |
| 上下文 | `aiaos-cli-context.el` | 284 | ✅ |
| 生命周期 | `aiaos-cli-lifecycle.el` | 346 | ✅ |
| 组件基础 | `aiaos-cli-component.el` | 360 | ✅ |
| 主题 | `aiaos-cli-theme.el` | 351 | ✅ |
| 组件 | `aiaos-cli-components.el` | 448 | ✅ |
| 路由 | `aiaos-cli-router.el` | 382 | ✅ |
| 应用 | `aiaos-cli-app.el` | 471 | ✅ |

## 依赖关系

```
aiaos-cli-core (基础)
  ↓
aiaos-cli-state (状态管理)
  ↓
aiaos-cli-context (上下文) → aiaos-cli-lifecycle (生命周期)
  ↓
aiaos-cli-component (组件基础) → aiaos-cli-theme (主题)
  ↓
aiaos-cli-components (组件) → aiaos-cli-router (路由)
  ↓
aiaos-cli-app (应用入口)
```

## 当前状态

- ✅ 模块拆分完成
- ✅ 基线测试通过（26 PASS / 0 FAIL）
- ✅ 所有模块括号平衡
- ⚠️ TUI 模块语法问题已修复（theme/components/router）
- ⚠️ 模块尚未集成到 `aiaos-cli.el`

## 下一步工作

1. 修复剩余语法问题（`aiaos-cli-theme.el` 中的 cl-defstruct 访问器调用）
2. 集成模块到 `aiaos-cli.el`
3. 更新 `aiaos-cli.el` 的 `require` 列表
4. 编写模块使用文档

## 设计决策

- **模块拆分**：参考 ratatui-kit 架构，按功能分层
- **状态管理**：React 风格 useState + 自动更新
- **组件系统**：Vue/React 风格组件树 + 生命周期
- **主题系统**：可定制的主题和样式
- **路由系统**：React Router 风格页面导航

## 注意事项

- TUI 模块是从设计文档生成的，语法可能不完整
- 模块尚未被 `aiaos-cli.el` 加载，不影响当前功能
- 集成前需要修复语法问题
