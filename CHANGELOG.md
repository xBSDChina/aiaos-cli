# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-28

### Added
- scripts/compile-gate.sh: Elisp 语法加载 + 函数定义 + 依赖链校验
- scripts/version-gate.sh: 版本一致性校验
- scripts/schema-gate.sh: JSON Schema / 契约字段校验
- scripts/sync-to-runtime.sh: 运行时同步（支持 --dry-run / --apply）
- run-tests.sh: 统一测试入口（委托 tests/run-all.sh）

### Fixed
- elisp/aiaos-cli-state.el: 版本号 1.1.0 → 1.0.0（与其他模块对齐）
