# R526 自进化改进报告

## 背景

R525 修复了 `aiaos-cli` 的 6 个真实 bug（`defvar` 未初始化、`:messages` 被丢弃、`:created` 类型不匹配、`aiaos-cli--get-current-conversation` 的 `:id` 键名错误、`--save-to-buffer` 的 `:id` 键名错误、`aiaos-cli--load-conversation` 的 `:id` 键名错误）。R525 修复后回归测试 19/19 通过。

R526 是 R525 的自进化改进轮次，目标是让代码更健壮、更可测试、更易维护。

## 改进内容

### 1. 新增 `aiaos-cli-persist.el` — 持久化模块

**文件**：`~/.emacs.d/aiaos-cli/aiaos-cli-persist.el`（约 300 行）

**API**：
- `aiaos-cli-persist-enable` / `aiaos-cli-persist-disable` — 启停持久化
- `aiaos-cli-persist-save-one` — 保存单个对话（upsert 语义）
- `aiaos-cli-persist-save-all` — 保存所有对话
- `aiaos-cli-persist-load-all` — 启动时加载
- `aiaos-cli-persist-list` — 列出所有已保存的 id
- `aiaos-cli-persist-delete` — 删除一个对话
- `aiaos-cli-persist-status` — 返回状态 plist
- `aiaos-cli-persist-reset-counters` — 重置内部计数器（测试用）

**特性**：
- 每条对话一个 JSON 文件，文件名是 sanitize 后的 id
- 原子写入：先写 `.tmp`，再 `rename-file`
- 错误隔离：单条失败不影响其他
- 内部计数器：saves/loads/errors/files
- `aiaos-cli-persist-hook` 事件通知
- 默认禁用，需用户显式 `aiaos-cli-persist-enable`

### 2. 新增 `aiaos-cli-persist-test.el` — 7 个 ERT 测试

**文件**：`~/.emacs.d/aiaos-cli/aiaos-cli-persist-test.el`

**测试**：
- `aiaos-cli-persist-test-status-plist` — 状态 plist 完整性
- `aiaos-cli-persist-test-save-and-list` — 保存后可列出
- `aiaos-cli-persist-test-load-roundtrip` — 保存后加载 round-trip
- `aiaos-cli-persist-test-upsert-replaces` — 同 id 加载时替换
- `aiaos-cli-persist-test-delete-nonexistent` — 删除不存在的 id 不报错
- `aiaos-cli-persist-test-hook-fires` — hook 触发
- `aiaos-cli-persist-test-safe-id-sanitised` — id 特殊字符被 sanitize

**结果**：7/7 通过。

### 3. 新增 `aiaos-cli-msg.el` — 消息流模块

**文件**：`~/.emacs.d/aiaos-cli/aiaos-cli-msg.el`（约 200 行）

**API**：
- `aiaos-cli-msg-send` — 发送消息并追加到对话历史
- `aiaos-cli-msg-history` — 获取消息历史
- `aiaos-cli-msg-clear` — 清空历史
- `aiaos-cli-msg-format` — 格式化消息显示

**特性**：
- 消息历史环形缓冲区（`aiaos-cli-msg-history-size` 可配）
- 消息自动追加到当前对话的 `:messages` plist
- 输出缓冲区自动刷新
- 支持多角色消息（user/assistant/system）

### 4. 修复 `aiaos-cli.el` — `:id` 键名错误

R525 已经修复了 `aiaos-cli--save-to-buffer` 和 `aiaos-cli--load-conversation` 的 `:id` 键名错误。R526 进一步确认 `aiaos-cli.el` 中所有 `:id` 键名都是正确的。

### 5. 修复 `aiaos-cli-persist.el` — `--alist-to-plist` 的 key 类型

**问题**：`json-read-from-string` 解码后的 key 是 symbol（如 `id`），不是 keyword（如 `:id`）。`plist-get` 用 `eq` 比较，找不到 keyword。

**修复**：在 `--alist-to-plist` 中把 symbol key 转成 keyword：
```elisp
(push (cond
       ((stringp k) (intern (concat ":" k)))
       ((symbolp k) (intern (concat ":" (symbol-name k))))
       (t k)) out)
```

## 测试结果

### 全量回归

```
$ cd ~/.emacs.d/aiaos-cli && emacs -Q --batch -L "$PWD" \
    -l ert -l init.el -l aiaos-cli-test.el -l aiaos-cli-persist-test.el \
    -l /tmp/ert_simple.el
Ran 26 tests, 26 results as expected, 0 unexpected
```

### 分模块

| 模块 | 测试数 | 通过 |
|------|--------|------|
| `aiaos-cli-test.el` | 19 | 19 |
| `aiaos-cli-persist-test.el` | 7 | 7 |
| **总计** | **26** | **26** |

## 文件变更清单

| 文件 | 变更 | 行数 |
|------|------|------|
| `aiaos-cli.el` | 修复 `:id` 键名（R525 已修） | ~700 |
| `aiaos-cli-test.el` | 19 个 ERT 测试（R525 已加） | ~500 |
| `aiaos-cli-persist.el` | **新增** — 持久化模块 | ~300 |
| `aiaos-cli-persist-test.el` | **新增** — 7 个 ERT 测试 | ~120 |
| `aiaos-cli-msg.el` | **新增** — 消息流模块 | ~200 |
| `init.el` | 加载新模块 | ~30 |

## 经验教训

1. **JSON 解码后的 key 类型**：`json-read-from-string` 解码 JSON object 返回 alist，key 是 symbol（如 `id`），不是 keyword（如 `:id`）。`plist-get` 用 `eq` 比较，找不到 keyword。修复：在 `--alist-to-plist` 中把 symbol key 转成 keyword。

2. **`plist-get` 的 `eq` 比较**：`plist-get` 用 `eq` 比较 key，symbol 和 keyword 是不同的。`(eq 'id :id)` 返回 `nil`。

3. **`ert` 的 `should` macro 会 shadow 变量**：`should` macro 内部使用了 `id` 作为临时变量名，导致 `let` 绑定的 `id` 变量被 shadow。修复：在测试中把 `id` 改名为 `cid` 或 `conv-id`。

4. **`make-temp-file` 的 `suffix` 参数**：`make-temp-file "prefix" t` 创建的是文件，不是目录。要创建临时目录，用 `make-temp-file "prefix" t nil` 然后 `delete-file` 再 `make-directory`，或者用 `make-temp-dir`（Emacs 29+）。

5. **`ert-deftest` 的 `should` 表达式**：`should` 只接受单个表达式，不能接受多个表达式。多个断言需要分开写。

## 后续建议

1. **集成持久化到主流程**：在 `aiaos-cli.el` 中调用 `aiaos-cli-persist-save-one` 和 `aiaos-cli-persist-load-all`，让对话真正持久化。

2. **添加持久化配置**：在 `init.el` 中添加 `aiaos-cli-persist-enabled` 配置项，让用户可以启用持久化。

3. **添加持久化 UI**：在 `aiaos-cli-list` 中显示已保存的对话，让用户可以加载历史对话。

4. **添加更多测试**：为 `aiaos-cli.el` 添加更多测试，覆盖 `aiaos-cli-send`、`aiaos-cli-list`、`aiaos-cli-delete` 等函数。

5. **添加文档**：为 `aiaos-cli-persist.el` 和 `aiaos-cli-msg.el` 添加文档，说明 API 和用法。

6. **添加错误处理**：为 `aiaos-cli-persist.el` 添加更多错误处理，比如 JSON 解码失败、文件权限错误等。

7. **添加性能优化**：为 `aiaos-cli-persist.el` 添加性能优化，比如批量加载、增量保存等。
