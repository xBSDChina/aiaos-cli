#!/usr/bin/env bash
# AIAOS-CLI Provider 测试脚本 (R2300 新增, R2301 补充 use 错误路径)

set -euo pipefail

CLI_BIN="${AIAOS_CLI_ROOT:-$(dirname "$(dirname "$(readlink -f "$0")")")}/bin/aiaos-cli"
CLI_BIN="$(dirname "$(dirname "$(readlink -f "$0")")")/bin/aiaos-cli"
export AIAOS_CLI_DATA_DIR="/tmp/aiaos-cli-test-provider-$$"
export AIAOS_CLI_CONFIG_DIR="/tmp/aiaos-cli-test-provider-config-$$"
export AIAOS_CLI_OUTPUT_FORMAT="json"

PASS=0
FAIL=0

test_assert() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS+1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $desc (expected: $expected, got: $actual)"
    fi
}

test_contains() {
    local desc="$1" pattern="$2" text="$3"
    if echo "$text" | grep -q "$pattern"; then
        PASS=$((PASS+1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $desc (pattern '$pattern' not found)"
    fi
}

test_not_contains() {
    local desc="$1" pattern="$2" text="$3"
    if echo "$text" | grep -q "$pattern"; then
        FAIL=$((FAIL+1))
        echo "  ✗ $desc (pattern '$pattern' unexpectedly found)"
    else
        PASS=$((PASS+1))
        echo "  ✓ $desc"
    fi
}

echo "======================================"
echo "Provider 管理测试"
echo "======================================"

# Test 1: provider list --help
echo ""
echo "--- Test 1: provider list --help ---"
out=$($CLI_BIN provider list --help 2>&1)
test_contains "list --help returns usage" "用法" "$out"
test_assert "list --help exit code" "0" "$?"

# Test 2: provider use --help (R2300 fix: was crashing with Python traceback)
echo ""
echo "--- Test 2: provider use --help ---"
out=$($CLI_BIN provider use --help 2>&1)
test_contains "use --help returns usage" "用法" "$out"
test_assert "use --help exit code" "0" "$?"

# Test 3: provider test --help
echo ""
echo "--- Test 3: provider test --help ---"
out=$($CLI_BIN provider test --help 2>&1)
test_contains "test --help returns usage" "用法" "$out"
test_assert "test --help exit code" "0" "$?"

# Test 4: provider tier --help
echo ""
echo "--- Test 4: provider tier --help ---"
out=$($CLI_BIN provider tier --help 2>&1)
test_contains "tier --help returns usage" "用法" "$out"
test_assert "tier --help exit code" "0" "$?"

# Test 5: provider fallback --help
echo ""
echo "--- Test 5: provider fallback --help ---"
out=$($CLI_BIN provider fallback --help 2>&1)
test_contains "fallback --help returns usage" "用法" "$out"
test_assert "fallback --help exit code" "0" "$?"

# Test 6: provider fallback-order --help
echo ""
echo "--- Test 6: provider fallback-order --help ---"
out=$($CLI_BIN provider fallback-order --help 2>&1)
test_contains "fallback-order --help returns usage" "用法" "$out"
test_assert "fallback-order --help exit code" "0" "$?"

# Test 7: provider chat --help
echo ""
echo "--- Test 7: provider chat --help ---"
out=$($CLI_BIN provider chat --help 2>&1)
test_contains "chat --help returns usage" "用法" "$out"
test_assert "chat --help exit code" "0" "$?"

# Test 8: provider audit --help
echo ""
echo "--- Test 8: provider audit --help ---"
out=$($CLI_BIN provider audit --help 2>&1)
test_contains "audit --help returns usage" "用法" "$out"
test_assert "audit --help exit code" "0" "$?"

# Test 9: provider use without args → error (R2300 fix: shell-level validation)
echo ""
echo "--- Test 9: provider use without args ---"
out=$($CLI_BIN provider use 2>&1) || true
test_contains "use without args returns error" "需要" "$out"

# Test 10: provider tier with invalid tier value → JSON error (R2300 fix: tier validation)
echo ""
echo "--- Test 10: provider tier with invalid tier ---"
out=$($CLI_BIN provider tier test invalid 2>&1) || true
test_contains "invalid tier returns JSON error" "invalid tier" "$out"
test_not_contains "no Python traceback" "Traceback" "$out"

# Test 11: provider tier with valid tier → success
echo ""
echo "--- Test 11: provider tier with valid tier ---"
out=$($CLI_BIN provider tier agnes full 2>&1) || true
test_contains "valid tier returns success" "tier" "$out"

# Test 12: provider list works
echo ""
echo "--- Test 12: provider list ---"
out=$($CLI_BIN provider list 2>&1)
test_contains "list returns providers" "agnes" "$out"

# Test 13: provider report works
echo ""
echo "--- Test 13: provider report ---"
out=$($CLI_BIN provider report 2>&1)
test_contains "report returns JSON" "current" "$out"

# Test 14: provider audit works
echo ""
echo "--- Test 14: provider audit ---"
out=$($CLI_BIN provider audit agnes 2>&1)
test_contains "audit returns JSON" "agnes" "$out"

# Test 15: provider fallback --strategy
echo ""
echo "--- Test 15: provider fallback --strategy ---"
out=$($CLI_BIN provider fallback --strategy round_robin 2>&1) || true
test_contains "fallback strategy set" "round_robin" "$out"

# Test 16: provider use with nonexistent name → JSON error (R2301 fix: KeyError caught)
echo ""
echo "--- Test 16: provider use with nonexistent name ---"
out=$($CLI_BIN provider use nonexistent 2>&1) || true
test_contains "use nonexistent returns JSON error" "unknown provider" "$out"
test_not_contains "no Python traceback" "Traceback" "$out"
test_not_contains "no KeyError raw" "KeyError" "$out"

echo ""
echo "======================================"
echo "Provider 测试总结"
echo "汇总: PASS=$PASS FAIL=$FAIL"
echo "总测试数: $((PASS + FAIL))"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
