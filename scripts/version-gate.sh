#!/usr/bin/env bash
# AIAOS-CLI 版本门禁脚本
# R5002: 校验所有模块版本号一致性
#
# 用法: bash scripts/version-gate.sh
# 退出码: 0=通过, 1=失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ELISP_DIR="$PROJECT_DIR/elisp"
BIN_FILE="$PROJECT_DIR/bin/aiaos-cli"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

echo "============================================"
echo "AIAOS-CLI 版本门禁 (version-gate)"
echo "============================================"

# 1. 版本号提取
echo ""
echo "--- 1. 版本号提取 ---"

VERSIONS=()

for elfile in "$ELISP_DIR"/aiaos-cli*.el; do
    [ -f "$elfile" ] || continue
    modname=$(basename "$elfile" .el)
    ver=$(grep -oP 'Version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' "$elfile" 2>/dev/null | head -1 || true)
    if [ -n "$ver" ]; then
        VERSIONS+=("$modname:$ver")
    fi
done

bin_ver=$(grep -oP 'AIAOS_CLI_VERSION="\K[0-9]+\.[0-9]+\.[0-9]+' "$BIN_FILE" 2>/dev/null | head -1 || true)
if [ -n "$bin_ver" ]; then
    VERSIONS+=("aiaos-cli-bin:$bin_ver")
fi

for entry in "${VERSIONS[@]}"; do
    echo "  $entry"
done

# 2. 一致性校验
echo ""
echo "--- 2. 版本一致性校验 ---"

if [ ${#VERSIONS[@]} -eq 0 ]; then
    log_fail "未提取到任何版本号"
else
    FIRST_VER=$(echo "${VERSIONS[0]}" | grep -oP '\d+\.\d+\.\d+$' || true)
    MISMATCH=0

    for entry in "${VERSIONS[@]}"; do
        ver=$(echo "$entry" | grep -oP '\d+\.\d+\.\d+$' || true)
        if [ "$ver" != "$FIRST_VER" ]; then
            log_fail "版本不一致: $entry (基准: $FIRST_VER)"
            MISMATCH=1
        fi
    done

    if [ "$MISMATCH" -eq 0 ]; then
        log_pass "所有版本号一致: $FIRST_VER"
    fi
fi

# 3. CHANGELOG 检查
echo ""
echo "--- 3. CHANGELOG 检查 ---"

CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
    latest_ver=$(grep -oP '^##\s*\[\K[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG" 2>/dev/null | head -1 || true)
    if [ -n "$latest_ver" ]; then
        log_pass "CHANGELOG 最新版本: $latest_ver"
    else
        log_fail "CHANGELOG 存在但无法提取版本号"
    fi
else
    log_fail "CHANGELOG.md 不存在"
fi

echo ""
echo "============================================"
echo "版本门禁结果: ${PASS} 通过, ${FAIL} 失败"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
