#!/usr/bin/env bash
# AIAOS-CLI date-tools 技能端到端测试
# 用法: bash tests/test_date_tools.sh
# 退出码: 0 全绿；1 有失败

set -uo pipefail

CLI_BIN="${CLI_BIN:-/home/shjiaye8/aiaos/aiaos-cli/bin/aiaos-cli}"
PASS=0
FAIL=0
declare -a FAIL_NAMES=()

# ---- 断言工具 ----
assert_eq() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf "PASS: %s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "FAIL: %s\n  expected: %s\n  actual  : %s\n" "$label" "$expected" "$actual"
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=("$label")
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "PASS: %s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "FAIL: %s (missing '%s')\n  actual: %s\n" "$label" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=("$label")
    fi
}

assert_json_status() {
    local label="$1" payload="$2" expected="$3"
    local got
    got=$(printf '%s' "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "__parse_error__")
    assert_eq "$label" "$got" "$expected"
}

json_kv() {
    python3 -c '
import json, sys
args = sys.argv[1:]
d = {}
i = 0
while i < len(args) - 1:
    d[args[i]] = args[i+1]
    i += 2
print(json.dumps(d))
' "$@"
}

run_skill() {
    local cmd="$1"; shift
    local -a args_kv=() opts_kv=()
    local mode="args"
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            shift; mode="opts"; continue
        fi
        if [[ "$mode" == "args" ]]; then
            args_kv+=("$1" "$2")
        else
            opts_kv+=("$1" "$2")
        fi
        shift 2
    done
    local args_json="{}" opts_json="{}"
    if [[ ${#args_kv[@]} -gt 0 ]]; then
        args_json=$(json_kv "${args_kv[@]}")
    fi
    if [[ ${#opts_kv[@]} -gt 0 ]]; then
        opts_json=$(json_kv "${opts_kv[@]}")
    fi
    "$CLI_BIN" skill run "date-tools/$cmd" \
        --args "$args_json" --options "$opts_json" --format json 2>/dev/null
}

echo "=== date-tools 技能测试 ==="

# ---- 测试用例 ----
test_now_basic() {
    local out
    out=$(run_skill now)
    assert_json_status "now: status=ok" "$out" "ok"
    assert_contains "now: 含 date-tools" "$out" '"date-tools"'
}

test_now_custom_format() {
    local out
    out=$(run_skill now format "%Y")
    assert_json_status "now: custom format status=ok" "$out" "ok"
    assert_contains "now: 含 %Y" "$out" '"%Y"'
}

test_timestamp_to_date() {
    local out
    out=$(run_skill timestamp value "1729700000" direction "to-date")
    assert_json_status "timestamp: to-date status=ok" "$out" "ok"
}

test_timestamp_to_unix() {
    local out
    out=$(run_skill timestamp value "2024-10-25" direction "to-unix")
    assert_json_status "timestamp: to-unix status=ok" "$out" "ok"
}

test_timestamp_auto() {
    local out
    out=$(run_skill timestamp value "1729700000")
    assert_json_status "timestamp: auto status=ok" "$out" "ok"
}

test_add_days() {
    local out
    out=$(run_skill add date "2024-10-25" days 7)
    assert_json_status "add: days status=ok" "$out" "ok"
}

test_add_months() {
    local out
    out=$(run_skill add date "2024-01-31" months 1)
    assert_json_status "add: months status=ok" "$out" "ok"
}

test_add_negative_days() {
    local out
    out=$(run_skill add date "2024-03-15" days "-30")
    assert_json_status "add: negative days status=ok" "$out" "ok"
}

test_add_both() {
    local out
    out=$(run_skill add date "2024-03-15" days 10 months 2)
    assert_json_status "add: both status=ok" "$out" "ok"
}

# ---- 运行测试 ----
test_now_basic
test_now_custom_format
test_timestamp_to_date
test_timestamp_to_unix
test_timestamp_auto
test_add_days
test_add_months
test_add_negative_days
test_add_both

echo ""
echo "=== date-tools 测试汇总 ==="
echo "PASS=$PASS FAIL=$FAIL"

if [[ $FAIL -gt 0 ]]; then
    echo "失败用例:"
    for name in "${FAIL_NAMES[@]}"; do
        echo "  - $name"
    done
    exit 1
fi

echo "所有测试通过!"
exit 0
