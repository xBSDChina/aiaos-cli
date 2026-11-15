#!/bin/bash

echo "=== AIAOS CLI 修复验证脚本 ==="
echo "验证时间: $(date)"
echo ""

# 1. 检查修复版本是否存在
echo "1. 检查修复版本..."
if [ -f ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el ]; then
    echo "✅ 修复版本存在"
    echo "   文件: ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el"
    echo "   大小: $(ls -lh ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el | awk '{print $5}')"
    echo "   修改时间: $(ls -l ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el | awk '{print $6, $7, $8}')"
else
    echo "❌ 修复版本缺失"
    exit 1
fi

echo ""

# 2. 检查初始化标志
echo "2. 检查初始化标志..."
if grep -q "aiaos-cli--initialized-p" ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el; then
    echo "✅ 初始化标志存在"
    grep -n "aiaos-cli--initialized-p" ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el
else
    echo "❌ 初始化标志缺失"
    exit 1
fi

echo ""

# 3. 检查 set-initialized 函数
echo "3. 检查 set-initialized 函数..."
if grep -q "defun aiaos-cli--set-initialized" ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el; then
    echo "✅ set-initialized 函数存在"
    grep -n "defun aiaos-cli--set-initialized" ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el
else
    echo "❌ set-initialized 函数缺失"
    exit 1
fi

echo ""

# 4. 检查版本对比
echo "4. 版本对比..."
echo "   原版本 vs 修复版本差异:"
DIFF_OUTPUT=$(diff -u ~/.emacs.d/aiaos-cli/aiaos-cli.el ~/.emacs.d/aiaos-cli/aiaos-cli-complete-fix.el | head -50)
if [ -n "$DIFF_OUTPUT" ]; then
    echo "✅ 检测到代码变更"
    echo "$DIFF_OUTPUT"
else
    echo "⚠️  未发现明显差异（可能不是通过diff方式修复）"
fi

echo ""

# 5. 检查备份文件
echo "5. 检查备份文件..."
BACKUP_COUNT=$(ls -1 ~/.emacs.d/aiaos-cli/aiaos-cli.el.backup.* 2>/dev/null | wc -l)
echo "   备份文件数量: $BACKUP_COUNT"
if [ $BACKUP_COUNT -gt 0 ]; then
    echo "   备份文件列表:"
    ls -1 ~/.emacs.d/aiaos-cli/aiaos-cli.el.backup.* | xargs -I {} basename {}
else
    echo "   未发现备份文件"
fi

echo ""

# 6. 检查错误信息
echo "6. 检查FIX_SUMMARY.md..."
if [ -f ~/.emacs.d/aiaos-cli/FIX_SUMMARY.md ]; then
    echo "✅ FIX_SUMMARY.md 存在"
    echo "   内容摘要:"
    grep -A 5 "## 问题诊断" ~/.emacs.d/aiaos-cli/FIX_SUMMARY.md | head -10
else
    echo "❌ FIX_SUMMARY.md 缺失"
fi

echo ""

# 7. 手动验证步骤
echo "7. 手动验证步骤:"
echo "   请按照以下步骤手动验证修复是否生效："
echo "   1. 重启Emacs"
echo "   2. 执行 M-x aiaos"
echo "   3. 在输入框中输入测试消息（如 'test'）"
echo "   4. 按 Enter 键发送"
echo "   5. 检查是否出现 'Attempt to set a constant symbol: t' 错误"
echo "   6. 如果未出现错误，则修复成功"

echo ""
echo "=== 验证完成 ==="
echo "如果所有检查都通过，请手动执行上述步骤确认功能正常。"
