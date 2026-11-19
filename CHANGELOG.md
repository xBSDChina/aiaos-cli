# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- elisp/aiaos-cli-history.el: 修复预存语法错误（`let` 块内错误变量定义 → `defvar`；移除加载时副作用 `with-current-buffer` 初始化；`after-load` → `with-eval-after-load`；补全括号；新增缺失 `defcustom`/`defvar`）
- elisp/aiaos-cli-llm.el: 新增 `aiaos-llm-handle-error`/`aiaos-llm-recover-from-error` 错误处理与恢复函数（超时/402/网络错误标记为可重试）
- elisp/aiaos-cli-logging.el: 修复预存语法错误（`-var` → `defvar`；`defcustom` 缺右括号；文件末尾换行）
- elisp/aiaos-cli-monitor.el: 修复预存语法错误（`-var` → `defvar`；注释括号错位；文件末尾换行）
- elisp/aiaos-cli-security.el: 修复预存语法错误（`-var` → `defvar`；`case` → `cl-case`；正则转义修复；文件末尾换行）
- elisp/aiaos-cli-selfheal.el: 修复预存语法错误（`-var` → `defvar`；`case` → `cl-case`；`maphash` 缺返回值参数；文件末尾换行）
- elisp/aiaos-llm-config-example.el: 封装加载时副作用到 `aiaos-llm-config-example-demo` 交互函数，避免加载即执行网络请求；新增 `(require 'aiaos-cli-llm)`
- design.md: 修正钩子签名文档-实现不一致（§2531/§2532/§2660/§2661 行 `(cmd args opts)` → `(command args)`，`(cmd args opts result)` → `(command result)`，与 core/skill.sh 生成模板及全部 8 技能实现一致）
- scripts/compile-gate.sh: 移除过时的 `aiaos-cli-app:aiaos-cli-components` 依赖声明（app.el 于 d4bd610 重构后不再 require aiaos-cli-components，改用 aiaos-cli--component-*）

### Added
- skill deps --graph dot: 支持 DOT 格式输出技能依赖图（P2 实现，设计文档 §64 R2104）
- tests: 新增 skill deps --graph dot 3 项测试（合法 DOT 输出 / --name 过滤 / graphviz 语法校验）

### Changed
- agent chat: 支持通过 `~/.config/aiaos/agent_llm_bridge.py` 桥接真实 LLM，失败时优雅降级到模拟回复

## [1.0.0] - 2026-10-28

### Added
- scripts/compile-gate.sh: Elisp 语法加载 + 函数定义 + 依赖链校验
- scripts/version-gate.sh: 版本一致性校验
- scripts/schema-gate.sh: JSON Schema / 契约字段校验
- scripts/sync-to-runtime.sh: 运行时同步（支持 --dry-run / --apply）
- run-tests.sh: 统一测试入口（委托 tests/run-all.sh）

### Fixed
- elisp/aiaos-cli-state.el: 版本号 1.1.0 → 1.0.0（与其他模块对齐）
