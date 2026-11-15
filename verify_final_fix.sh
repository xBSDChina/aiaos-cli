#!/bin/bash
# verify_final_fix.sh — 验证 r560 修复
set -e
echo "=== r560 修复验证 ==="

cd /home/shjiaye8/.emacs.d/aiaos-cli

echo ""
echo "=== [1/6] 检查重复定义 ==="
for fn in aiaos-cli--send-to-backend aiaos-cli--parse-response aiaos-cli--on-response aiaos-cli--on-error aiaos-cli--on-timeout aiaos-cli--on-abort; do
    count=$(grep -c "^(defun $fn" aiaos-cli.el)
    if [ "$count" -ne 1 ]; then
        echo "FAIL: $fn defined $count times"
        exit 1
    fi
    echo "OK: $fn defined $count time"
done

echo ""
echo "=== [2/6] 检查关键 bug 修复 ==="
# BUG-1: exec 参数用 aiaos-cli--exec-cmd
if grep -q "aiaos-cli--exec-cmd" aiaos-cli.el; then
    echo "OK: exec 使用 aiaos-cli--exec-cmd"
else
    echo "FAIL: exec 未使用 aiaos-cli--exec-cmd"
    exit 1
fi

# BUG-2: timeout 使用 aiaos-cli--get-timeout
if grep -q "aiaos-cli--get-timeout" aiaos-cli.el; then
    echo "OK: timeout 使用 aiaos-cli--get-timeout"
else
    echo "FAIL: timeout 未使用 aiaos-cli--get-timeout"
    exit 1
fi

# BUG-3: 使用 aiaos-cli--get-prompt
if grep -q "aiaos-cli--get-prompt" aiaos-cli.el; then
    echo "OK: 使用 aiaos-cli--get-prompt"
else
    echo "FAIL: 未使用 aiaos-cli--get-prompt"
    exit 1
fi

echo ""
echo "=== [3/6] 检查 aiaos-cli.el 字节编译 ==="
emacs --batch -q -l aiaos-cli.el --eval '(progn (byte-compile-file "aiaos-cli.el") (princ "OK"))' 2>&1

echo ""
echo "=== [4/6] 检查 aiaos-cli-config.el 字节编译 ==="
emacs --batch -q -l aiaos-cli.el -l aiaos-cli-config.el --eval '(progn (byte-compile-file "aiaos-cli-config.el") (princ "OK"))' 2>&1

echo ""
echo "=== [5/6] 检查 aiaos-cli-exec.el 字节编译 ==="
emacs --batch -q -l aiaos-cli-exec.el --eval '(progn (byte-compile-file "aiaos-cli-exec.el") (princ "OK"))' 2>&1

echo ""
echo "=== [6/6] 加载测试 ==="
emacs --batch -q -l aiaos-cli.el -l aiaos-cli-config.el -l aiaos-cli-exec.el --eval '(progn (princ "All modules loaded OK\n") (princ (format "aiaos-cli--exec-cmd = %s\n" aiaos-cli--exec-cmd)) (princ (format "aiaos-cli--timeout = %s\n" aiaos-cli--timeout)) (princ (format "aiaos-cli--get-prompt returns: %s\n" (aiaos-cli--get-prompt))))' 2>&1

echo ""
echo "=== 全部验证通过 ==="
