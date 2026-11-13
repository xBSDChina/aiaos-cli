# AIAOS-CLI 测试指南

## 测试文件

### test-emacs-batch.el
批处理模式测试，使用 `emacs --batch` 运行。

**运行方法：**
```bash
cd ~/aiaos/aiaos-cli/elisp
emacs --batch --eval "(load-file \"~/aiaos/aiaos-cli/elisp/test-emacs-batch.el\")"
```

### test-emacsclient.el
Emacsclient 测试，模拟交互式环境。

**运行方法：**
```bash
cd ~/aiaos/aiaos-cli/elisp
emacs --batch --eval "(load-file \"~/aiaos/aiaos-cli/elisp/test-emacsclient.el\")"
```

## 测试内容

两个测试文件都包含以下测试：

1. **模块加载** - 验证 aiaos-cli 模块是否正确加载
2. **二进制文件检查** - 验证 aiaos 二进制文件是否可用
3. **JSON 解析** - 测试 JSON 解析功能
4. **命令构建** - 测试命令构建功能
5. **版本检查** - 验证版本信息
6. **帮助命令** - 测试帮助系统
7. **会话管理** - 测试会话命令构建
8. **上下文管理** - 测试上下文命令构建
9. **技能管理** - 测试技能命令构建
10. **配置管理** - 测试配置命令构建

## 故障排除

### 问题：Cannot open load file: aiaos-cli-core
**解决方案：** 确保 load-path 包含 elisp 目录。测试文件已包含：
```elisp
(add-to-list 'load-path (expand-file-name "~/aiaos/aiaos-cli/elisp"))
```

### 问题：函数未定义
确保使用正确的函数名。主要 API 函数：
- `aiaos-cli--assert-binary` - 检查二进制文件
- `aiaos-cli--parse-json` - 解析 JSON
- `aiaos-cli--build-cmd` - 构建命令
- `aiaos-cli-version` - 获取版本
- `aiaos-cli-help` - 显示帮助
- `aiaos-cli-config-get/set` - 配置管理

## 注意事项

- 测试中的某些功能（如配置管理）会调用外部 aiaos 命令，可能需要实际的 aiaos 二进制文件
- 如果二进制文件未安装，某些测试会显示预期的错误消息，但仍会通过