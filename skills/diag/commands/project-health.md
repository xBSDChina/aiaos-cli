# diag/project-health — 项目健康检查

## 功能说明

对整个 AIAOS 项目进行健康检查，产出 JSON 格式报告，供 CI 和本地开发使用。

## 检查维度

### 1. 代码规模统计
- 代码行数（`lisp/` 下所有 `.el` 文件）
- defun 数量
- 备份文件数（`.bak.r*` 模式）

### 2. 文档覆盖率
- `design.md`、`CHANGELOG.md`、`README.md`、`SKILL.md` 是否存在

### 3. TODO/FIXME 数量
- 统计 `lisp/` 源码中的 `TODO`、`FIXME`、`XXX` 标记数量

### 4. 版本一致性
- `VERSION` 文件与 `CHANGELOG.md` 最新标签对比
- `VERSION` 文件与 `SKILL.md` 中 `Version:` 字段对比

### 5. 配置文件检查
- `.aiaos-cli.json` 是否存在
- 必需键（`version`、`skills`）是否存在

### 6. 模块统计
- `lisp/skills/` 下技能模块数量

## 输出格式

```json
{
  "status": "healthy|warning|error",
  "version": "1.0.37",
  "backup-files": 12,
  "total-lines": 2500,
  "total-defuns": 80,
  "missing-docs": [],
  "todo-count": 5,
  "config-path": ".aiaos-cli.json",
  "version-issues": [],
  "config-issues": [],
  "module-count": 8,
  "issues": []
}
```

## 退出码

- `0` — 健康
- `1` — 有 warning
- `2` — 有 error

## 用法

```bash
aiaos-cli diag project-health
```

## 实现文件

- `lisp/skills/diag/commands/project-health.el` — 主实现
- `lisp/skills/diag/tests/test-project-health.el` — ERT 测试（12 项）
