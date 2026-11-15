# AIAOS CLI Changelog

## R557 — 2026-10-15

### Fixed

1. **`aiaos-cli-sanitize.el` 同名变量/函数冲突（严重）**
   - 问题：`aiaos-cli-sanitize-alist-p` 同时被定义为 `defvar`（变量）和 `defun`（函数），字节码编译时变量遮蔽函数，导致 `aiaos-cli.el` 中 `(aiaos-cli-sanitize-alist-p obj)` 调用报 `void-variable`。
   - 修复：将变量重命名为 `aiaos-cli-sanitize-alist-mode`，函数保持原名。

2. **`aiaos-cli-config.el` 温度校验逻辑错误**
   - 问题：`(when (and aiaos-cli-temperature (< aiaos-cli-temperature 0) (> aiaos-cli-temperature 1)) ...)` — `and` 永远为假（温度不可能同时 <0 且 >1），校验完全失效。
   - 修复：改为 `(or (< 0) (> 1))`，正确拒绝越界温度。

3. **`aiaos-cli-config.el` 缺失 defcustom 声明**
   - 问题：`aiaos-cli-temperature`、`aiaos-cli-max-tokens`、`aiaos-cli-config-dir` 在 `aiaos-cli-config.el` 中被引用但未声明（R556 遗留），加载时报 `void-variable`。
   - 修复：补齐三个 defcustom 声明。

4. **`aiaos-cli.el` 死代码：`temperature`/`max_tokens` 从未传给 LLM**
   - 问题：`aiaos-cli--encode-chat-request` 只发送 `model`/`messages`/`stream`，`aiaos-cli-temperature` 和 `aiaos-cli-max-tokens` 是死代码。
   - 修复：当这两个 defcustom 已绑定时，将其加入请求体。

5. **`aiaos-cli.el` docstring 尾随多余引号**
   - 问题：`aiaos-cli--diag-health` 的 docstring 以 `."""` 结尾（多了一个 `"`）。
   - 修复：改为 `."`。

### Added

- **`aiaos-cli-test.el`**：新增 2 个回归测试
  - `aiaos-cli-test-validate-config-rejects-bad-temperature`：锁定温度校验行为
  - `aiaos-cli-test-encode-chat-request-includes-temperature`：锁定请求体包含 temperature/max_tokens

### 验证

- byte-compile：19 个文件全部无 Error
- ERT：43/43 通过

### 备注

- 曾尝试为 sanitize 变量/函数共存写测试，但字节码下 `find-function`/`functionp`/`fboundp` 对同名符号的处理不可靠，最终删除该测试。主修复本身已通过 `aiaos-cli.el` 中函数调用的正常执行间接验证。
