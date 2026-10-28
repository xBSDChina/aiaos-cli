#!/usr/bin/env bash
# AIAOS-CLI Schema 门禁脚本
# R5002: 校验 JSON Schema 输出格式一致性
#
# 用法: bash scripts/schema-gate.sh
# 退出码: 0=通过, 1=失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BIN_FILE="$PROJECT_DIR/bin/aiaos-cli"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

echo "============================================"
echo "AIAOS-CLI Schema 门禁 (schema-gate)"
echo "============================================"

# 1. JSON 输出格式校验（所有域命令）
echo ""
echo "--- 1. JSON 输出格式校验 ---"

DOMAINS=(
    "skill list"
    "provider list"
    "session list"
    "context list"
    "config list"
    "log list"
)

for domain_cmd in "${DOMAINS[@]}"; do
    json_output=$("$BIN_FILE" $domain_cmd --format json 2>/dev/null || true)
    if echo "$json_output" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
        log_pass "JSON 格式: $domain_cmd"
    else
        log_fail "JSON 格式: $domain_cmd"
    fi
done

# 2. 响应契约字段校验
# 实际契约：list 命令返回裸数组/对象，单个操作返回 {"status":..., ...}
echo ""
echo "--- 2. 响应契约字段校验 ---"

# 检查 session new 的契约（有 status 字段）
SESSION_OUT=$("$BIN_FILE" session new --name test-schema-gate --format json 2>/dev/null || true)
if echo "$SESSION_OUT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert 'status' in data, 'missing status field'
assert data['status'] in ('success', 'ok', 'error'), f'invalid status: {data[\"status\"]}'
print('ok')
" 2>/dev/null; then
    log_pass "契约字段: session new status"
else
    log_fail "契约字段: session new status"
fi

# 清理测试会话
"$BIN_FILE" session delete --name test-schema-gate 2>/dev/null || true

# 3. JSON Lines 日志格式校验
echo ""
echo "--- 3. JSON Lines 日志格式校验 ---"

LOG_DIR="$HOME/.config/aiaos/logs"
if [ -f "$LOG_DIR/aiaos-cli.log" ]; then
    if python3 -c "
import json, sys
with open('$LOG_DIR/aiaos-cli.log') as f:
    for i, line in enumerate(f):
        line = line.strip()
        if line:
            json.loads(line)
        if i > 100: break
" 2>/dev/null; then
        log_pass "JSON Lines 日志格式"
    else
        log_fail "JSON Lines 日志格式"
    fi
else
    echo "  日志文件不存在，跳过检查"
fi

# 4. Elisp 调用契约校验
echo ""
echo "--- 4. Elisp 调用契约校验 ---"

CONTRACT_FILE="/tmp/aiaos-cli-schema-contract.el"
cat > "$CONTRACT_FILE" << CHECK_EOF
(require 'aiaos-cli)
;; 验证核心调用函数存在
(princ (format "run=%s\n" (if (fboundp 'aiaos-cli-run) "YES" "NO")))
(princ (format "init=%s\n" (if (fboundp 'aiaos-cli-init) "YES" "NO")))
(princ (format "execute=%s\n" (if (fboundp 'aiaos-cli-execute) "YES" "NO")))
CHECK_EOF

ELISP_OUT=$(emacs --batch -Q -L "$PROJECT_DIR/elisp" -l "$CONTRACT_FILE" 2>/dev/null || true)
rm -f "$CONTRACT_FILE"

if echo "$ELISP_OUT" | grep -q "run=YES"; then
    log_pass "Elisp 契约: aiaos-cli-run"
else
    log_fail "Elisp 契约: aiaos-cli-run"
fi

echo ""
echo "============================================"
echo "Schema 门禁结果: ${PASS} 通过, ${FAIL} 失败"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
