# aiaos-cli 设计文档

## 概述

aiaos-cli 是 AI Agent 操作系统 (AIAOS) 的 CLI 前端，由 Go 后端 + Emacs Lisp 前端组成。

## 架构

- **Go 后端**: `bin/aiaos-cli` — 处理命令、会话、技能、上下文、日志
- **Elisp 前端**: `elisp/aiaos-cli.el` — Emacs 集成、按键绑定、交互式界面
- **技能系统**: `skills/<name>/` — YAML 元数据 + Elisp 命令 + Hooks

## 版本控制

- Go 后端版本: `v1.0.0`
- Elisp 前端版本: `v1.0.0`
- 版本一致性检查: `aiaos-cli--version-consistent-p`

## 命令列表

- `C-c a h` — 帮助
- `C-c a v` — 版本信息
- `C-c a d` — 诊断
- `C-c a s` — 会话列表
- `C-c a S` — 新建会话
- `C-c a c` — 上下文查看
- `C-c a C` — 上下文保存
- `C-c a k` — 技能列表
- `C-c a K` — 技能安装
- `C-c a r` — 运行技能（`skill run <skill>/<cmd>` 简写）
- `C-c a a` — Agent 对话
- `C-c a p` — 项目状态
- `C-c a P` — 项目初始化
- `C-c a g` — 配置查看
- `C-c a G` — 配置编辑
- `C-c a l` — 日志查看
- `C-c a L` — 日志清理

## 技能系统

### 目录结构

```
skills/
  hello-world/
    skill.yaml          # 元数据：name, version, description, commands[]
    commands/
      hello.el          # 实现 aiaos-cli-skill-hello-world/hello
```

### skill.yaml Schema

```yaml
name: hello-world
version: "1.0.0"
description: "示例技能"
commands:
  - name: hello
    description: "打招呼"
    args:
      - name: name
        type: string
        required: true
        description: "名字"
    options:
      - name: uppercase
        type: boolean
        default: false
        description: "大写输出"
```

### 简写语法

`aiaos-cli skill run <skill>/<cmd>` 等价于 `aiaos-cli skill run --name <skill> --command <cmd>`（R800+）

## 已修复问题

### 2026-10-21: skill run 简写在项目目录下失败

**现象**: 在包含 `.aiaos/project.yaml` 的项目目录下运行 `aiaos-cli skill run hello-world/hello` 失败，报错 `Cannot open load file "aiaos-cli"`。

**根因**: `core/skill.sh` 中调用 Emacs 时使用了相对路径 `-L elisp`，导致在非 aiaos-cli 根目录下找不到 elisp 模块。

**修复**: 将 `-L elisp` 改为 `-L "$AIAOS_CLI_ELISP_DIR"`（绝对路径），在 `bin/aiaos-cli` 中已导出 `AIAOS_CLI_ELISP_DIR`。

**变更文件**: `core/skill.sh` 第 604 行。

## 测试规范

### 双绿标准

每次提交必须同时通过：
1. Shell 测试: `bash tests/test_cli.sh`（12 项全部 PASS）
2. Elisp ERT 测试: `emacs --batch -L elisp -l tests/test-aiaos-cli.el --eval "(ert-run-tests-batch)"`（16 项全部 PASS）

### 测试覆盖

| 测试 | 说明 |
|------|------|
| 1 | 版本和帮助 |
| 2 | 环境检查 |
| 3 | 会话管理 |
| 4 | 上下文管理 |
| 5 | 技能管理（validate, run --name/--command） |
| 6 | Agent 交互 |
| 7 | 项目管理 |
| 8 | 配置管理 |
| 9 | 日志管理 |
| 10 | help 一致性防回归 |
| 11 | skill info --format json 契约 |
| 12 | **skill run <skill>/<cmd> 简写（R800+）** |

## 关键设计决策

### R800: skill run 简写语法

- 新增 `skill run <skill>/<cmd>` 简写，兼容 `--name/--command` 完整形式
- 解析逻辑在 `core/skill.sh:skill_run()` 中，通过位置参数识别 `/` 分隔符

### R810: skill info --format json 契约

- 强制 JSON 输出，防止 YAML 回归
- 测试 11 专门验证

### R820: Emacs 输出分离

- `skill_run` 使用临时文件分离 stdout/stderr
- 避免 Emacs 启动消息污染 JSON 输出

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `AIAOS_CLI_DATA_DIR` | 数据目录 | `~/.local/share/aiaos` |
| `AIAOS_CLI_CONFIG_DIR` | 配置目录 | `~/.config/aiaos` |
| `AIAOS_CLI_OUTPUT_FORMAT` | 输出格式 | `json` |
| `AIAOS_CLI_ROOT` | CLI 根目录 | 自动推导 |
| `AIAOS_CLI_ELISP_DIR` | Elisp 模块目录 | `$AIAOS_CLI_ROOT/elisp` |
| `AIAOS_PROJECT_ROOT` | 项目根目录 | 未设置（由 project 模块检测） |

## 演进原则

1. **CLI 是契约，前端是消费者**：任何业务变更先改 CLI，再改 Elisp。
2. **JSON 是唯一跨层格式**：`--format=json` 默认，raw 仅用于日志 tail。
3. **版本号显式声明**：Elisp 与二进制各自声明，`aiaos-cli--version-consistent-p` 强制校验。
4. **异步默认，同步例外**：只有 init 与测试允许同步。
5. **测试先行**：新增子命令必须先补 shell 测试，再补 ERT。
6. **路径必须绝对化**：所有 `-L`、模块加载、技能目录均使用绝对路径，避免 CWD 依赖。
---

## 28. emacs-tools 技能开发日志 (R1316)

### 28.1 需求分析

基于 `~/aiaos-cli_skills.md` 中 emacs-tools 技能需求，实现以下命令：

| 命令 | 功能 | 输入 | 输出 |
|------|------|------|------|
| encode | Base64/URL 编码解码 | :text, :mode | :encoded-data |
| format | 文本折行 | :text, :width, :indent | :output |
| wordfreq | 词频统计 | :text, :top | :frequencies |
| stats | 文本统计 | :text | :chars, :words, :lines, :bytes |
| slugify | URL slug 生成 | :text, :separator, :truncate | :output |

### 28.2 技术难点与解决

**难点 1：wordfreq.el 读取语法错误**
- 问题：UTF-8 编码的 § 符号导致 elisp 解析失败
- 解决：移除注释中的特殊字符，使用纯 ASCII

**难点 2：wordfreq.el 缺少 cl-lib 依赖**
- 问题：使用 `loop` 宏但未导入
- 解决：改用 `maphash` + `seq-take` 组合

**难点 3：slugify.el 参数验证**
- 问题：初始版本未验证 :truncate 和 :separator
- 解决：添加 nil 默认值处理，空字符串拒绝

### 28.3 关键代码片段

```elisp
;; slugify.el - 核心 slug 生成逻辑
(let ((step1 (replace-regexp-in-string "_" sep text))
      (step2 (downcase step1))
      (step3 (replace-regexp-in-string "[^a-z0-9]+" sep step2)))
  ;; 折叠连续分隔符
  (aiaos-cli--slugify-collapse-sep step3 sep))
```

### 28.4 测试覆盖

- 测试脚本：`tests/test_emacs_tools.sh`（22 个断言）
- 测试结果：PASS=22 FAIL=0
- 覆盖场景：encode（Base64/URL）、wordfreq、stats、slugify（基础/分隔符/截断/trim/折叠）

### 28.5 技术债

- [TD-027] format.el 有读取语法错误（需修复）
- [TD-028] slugify 可添加 `:lower` 选项支持多语言

---

*更新时间：2026-10-22T07:10:00-01:00*
*更新人：AIAOS-CLI 自动化流程（R1316）*
*本轮增量：新增 emacs-tools 技能（5 个命令）+ tests/test_emacs_tools.sh（22 断言）*

---

## 31. R1318 — 修复 Python 内插漏洞 (TD-029)

### 31.1 背景

TD-029 要求全项目审计 Python 内插漏洞：shell 变量直接内插到 `python3 -c "..."` 字符串中，存在代码注入风险。

### 31.2 修复范围

**core/skill.sh (R880)** - 7 处修复：

| 位置 | 函数 | 修复前 | 修复后 |
|------|------|--------|--------|
| L60-66 | `parse_skill_yaml` | `open('$skill_yaml')` | `open(sys.argv[1])` + `"$skill_yaml"` |
| L349-355 | `skill_enable` | `open('$skill_yaml')` | `open(sys.argv[1])` + `"$skill_yaml"` |
| L384-390 | `skill_disable` | `open('$skill_yaml')` | `open(sys.argv[1])` + `"$skill_yaml"` |
| L562 | `skill_run` sname 查找 | `open('$y')` | `open(sys.argv[1])` + `"$y"` |
| L571-578 | `skill_run` entry 查找 | `open('$skill_yaml')` + `== '$command'` | `open(sys.argv[1])` + `== sys.argv[2]` + `"$skill_yaml" "$command"` |
| L581-593 | `skill_run` opt_map 查找 | `open('$skill_yaml')` + `== '$command'` | `open(sys.argv[1])` + `== sys.argv[2]` + `"$skill_yaml" "$command"` |
| L597-603 | `skill_run` hooks_json 查找 | `open('$skill_yaml')` | `open(sys.argv[1])` + `"$skill_yaml"` |

### 31.3 验证结果

| 测试套件 | 结果 |
|---------|------|
| Shell (tests/test_cli.sh) | 18/18 通过 |
| Elisp ERT (tests/test-aiaos-cli.el) | 28/28 通过 |

### 31.4 新增范式

#### 范式 AH：Python 内插必须用 sys.argv 传参

**规则**：Shell 变量**绝不能**直接内插到 `python3 -c "..."` 字符串中。必须通过 `sys.argv` 传递。

```bash
# ❌ 错误：内插风险
python3 -c "
import yaml
with open('$skill_yaml') as f:
    data = yaml.safe_load(f)
"

# ✅ 正确：sys.argv 传参
python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
" "$skill_yaml"
```

**原因**：
- 防止代码注入（变量含单引号/双引号/反引号时）
- 避免特殊字符破坏 Python 语法
- 符合最小权限原则

### 31.5 关闭项

| ID | 状态 |
|----|------|
| TD-029 | **关闭** — 全项目 Python 内插漏洞已修复 |

---

*更新时间：2026-10-22T08:18:00-01:00*
*更新人：AIAOS-CLI 自动化流程（R1318）*
*本轮增量：修复 core/skill.sh 7 处 Python 内插漏洞 (R880) + 新增范式 AH + TD-029 关闭*
*关键成果：Shell 18/18 + Elisp 28/28 全绿；skill enable/disable/run/parse 均验证通过*
*核心教训：Shell 变量绝不能内插到 python -c 字符串，必须用 sys.argv（范式 AH）*
