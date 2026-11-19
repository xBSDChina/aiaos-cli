#!/bin/bash
# 运行 AIAOS-CLI 测试的脚本

echo "=== AIAOS-CLI 测试套件 ==="
echo ""

cd ~/aiaos/aiaos-cli/elisp

echo "1. 运行批处理测试..."
emacs --batch --eval "(load-file \"~/aiaos/aiaos-cli/elisp/test-emacs-batch.el\")" 2>&1 | grep -E "^(===|Test|✓|✗)"
echo ""

echo "2. 运行 Emacsclient 测试..."
emacs --batch --eval "(load-file \"~/aiaos/aiaos-cli/elisp/test-emacsclient.el\")" 2>&1 | grep -E "^(===|Test|✓|✗)"
echo ""

echo "3. 运行 Emacs 集成测试..."
emacs --batch -L ~/aiaos/aiaos-cli/elisp -l aiaos-cli-emacs.el -l test-aiaos-cli-emacs.el --eval "(aiaos-cli-emacs-run-all-tests)" 2>&1 | grep -E "^(Test|===)"
echo ""

echo "=== 测试完成 ==="
