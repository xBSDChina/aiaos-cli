#!/usr/bin/env bash
# AIAOS-CLI 编译门禁脚本
# R5002: 统一加载所有 Elisp 模块，验证语法正确性 + 无未定义函数引用
#
# 用法: bash scripts/compile-gate.sh
# 退出码: 0=通过, 1=失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ELISP_DIR="$PROJECT_DIR/elisp"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

echo "============================================"
echo "AIAOS-CLI 编译门禁 (compile-gate)"
echo "============================================"

MODULES=(
    aiaos-cli-core
    aiaos-cli-state
    aiaos-cli-context
    aiaos-cli-lifecycle
    aiaos-cli-component
    aiaos-cli-theme
    aiaos-cli-components
    aiaos-cli-router
    aiaos-cli-app
    aiaos-cli
)

# 1. 语法加载检查
echo ""
echo "--- 1. Elisp 语法加载检查 ---"

for mod in "${MODULES[@]}"; do
    if emacs --batch -Q -L "$ELISP_DIR" --eval "(require '$mod)" 2>/dev/null; then
        log_pass "加载模块: $mod"
    else
        log_fail "加载模块: $mod"
    fi
done

# 2. 公共导出函数检查（使用临时 elisp 文件避免引号地狱）
echo ""
echo "--- 2. 公共导出函数检查 ---"

CORE_FUNCS=(
    "aiaos-cli-init"
    "aiaos-cli-run"
    "aiaos-cli-help"
    "aiaos-cli-version"
    "aiaos-cli-doctor"
    "aiaos-cli-skill-list"
    "aiaos-cli-skill-load"
    "aiaos-cli-skill-run"
    "aiaos-cli-session-new"
    "aiaos-cli-agent-chat"
    "aiaos-cli-log-tail"
    "aiaos-cli-app-start"
)

CHECK_FILE="/tmp/aiaos-cli-compile-gate-check.el"
cat > "$CHECK_FILE" << CHECK_EOF
$(for mod in "${MODULES[@]}"; do echo "(require '$mod)"; done)
$(for func in "${CORE_FUNCS[@]}"; do echo "(princ (format \"$func=%s\\n\" (if (fboundp '$func) \"YES\" \"NO\")))"; done)
CHECK_EOF

FUNC_OUTPUT=$(emacs --batch -Q -L "$ELISP_DIR" -l "$CHECK_FILE" 2>/dev/null)
for func in "${CORE_FUNCS[@]}"; do
    if echo "$FUNC_OUTPUT" | grep -q "$func=YES"; then
        log_pass "函数定义: $func"
    else
        log_fail "函数定义: $func"
    fi
done
rm -f "$CHECK_FILE"

# 3. 模块依赖顺序验证
echo ""
echo "--- 3. 模块依赖顺序验证 ---"

DEPENDENCIES=(
    "aiaos-cli-state:aiaos-cli-core"
    "aiaos-cli-context:aiaos-cli-state"
    "aiaos-cli-lifecycle:aiaos-cli-state"
    "aiaos-cli-component:aiaos-cli-state"
    "aiaos-cli-component:aiaos-cli-context"
    "aiaos-cli-component:aiaos-cli-lifecycle"
    "aiaos-cli-theme:aiaos-cli-context"
    "aiaos-cli-components:aiaos-cli-component"
    "aiaos-cli-components:aiaos-cli-state"
    "aiaos-cli-components:aiaos-cli-context"
    "aiaos-cli-components:aiaos-cli-theme"
    "aiaos-cli-components:aiaos-cli-lifecycle"
    "aiaos-cli-router:aiaos-cli-component"
    "aiaos-cli-router:aiaos-cli-context"
    "aiaos-cli-app:aiaos-cli-state"
    "aiaos-cli-app:aiaos-cli-context"
    "aiaos-cli-app:aiaos-cli-component"
    "aiaos-cli-app:aiaos-cli-lifecycle"
    "aiaos-cli-app:aiaos-cli-theme"
    "aiaos-cli-app:aiaos-cli-router"
)

for dep in "${DEPENDENCIES[@]}"; do
    module=$(echo "$dep" | cut -d: -f1)
    required=$(echo "$dep" | cut -d: -f2)
    if grep -q "(require '$required)" "$ELISP_DIR/$module.el" 2>/dev/null; then
        log_pass "依赖: $module → $required"
    else
        log_fail "依赖: $module → $required (缺少 require)"
    fi
done

echo ""
echo "============================================"
echo "编译门禁结果: ${PASS} 通过, ${FAIL} 失败"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
