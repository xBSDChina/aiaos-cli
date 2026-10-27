#!/usr/bin/env bash
# AIAOS-CLI string-tools 技能端到端测试
# 用法: bash tests/test_string_tools.sh
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
    "$CLI_BIN" skill run "string-tools/$cmd" \
        --args "$args_json" --options "$opts_json" --format json 2>/dev/null
}

echo "=== string-tools 技能测试 ==="

# ---- 测试用例 ----
test_reverse_basic() {
    local out
    out=$(run_skill reverse text "hello")
    assert_json_status "reverse: status=ok" "$out" "ok"
    assert_contains "reverse: 含 olleh" "$out" '"olleh"'
}

test_reverse_chinese() {
    local out
    out=$(run_skill reverse text "好，世界")
    assert_json_status "reverse: 中文 status=ok" "$out" "ok"
    assert_contains "reverse: 含 界世，好" "$out" '界世，好'
}

test_reverse_empty() {
    local out
    out=$(run_skill reverse text "")
    assert_json_status "reverse: 空串 status=ok" "$out" "ok"
}

test_trim_both() {
    local out
    out=$(run_skill trim text "  hello  ")
    assert_json_status "trim: both status=ok" "$out" "ok"
    assert_contains "trim: 含 hello" "$out" '"hello"'
}

test_trim_left() {
    local out
    out=$(run_skill trim text "    hello  world" -- side left)
    assert_json_status "trim: left status=ok" "$out" "ok"
    assert_contains "trim: left 含 hello  world" "$out" 'hello  world'
}

test_trim_right() {
    local out
    out=$(run_skill trim text "hello  world    " -- side right)
    assert_json_status "trim: right status=ok" "$out" "ok"
    assert_contains "trim: right 含 hello  world" "$out" 'hello  world'
}

test_pad_right() {
    local out
    out=$(run_skill pad text abc length 5)
    assert_json_status "pad: right status=ok" "$out" "ok"
    assert_contains "pad: right 含 abc" "$out" 'abc'
}

test_pad_left() {
    local out
    out=$(run_skill pad text abc length 5 -- align left)
    assert_json_status "pad: left status=ok" "$out" "ok"
}

test_pad_center() {
    local out
    out=$(run_skill pad text ab length 5 -- align center)
    assert_json_status "pad: center status=ok" "$out" "ok"
}

test_pad_custom_char() {
    local out
    out=$(run_skill pad text abc length 7 -- char x)
    assert_json_status "pad: custom char status=ok" "$out" "ok"
    assert_contains "pad: custom char 含 abc" "$out" 'abc'
}

test_repeat_basic() {
    local out
    out=$(run_skill repeat text abc times 3)
    assert_json_status "repeat: status=ok" "$out" "ok"
    assert_contains "repeat: 含 abcabcabc" "$out" 'abcabcabc'
}

test_repeat_single() {
    local out
    out=$(run_skill repeat text hello times 1)
    assert_json_status "repeat: single status=ok" "$out" "ok"
    assert_contains "repeat: single 含 hello" "$out" 'hello'
}

test_repeat_zero() {
    local out
    out=$(run_skill repeat text hello times 0)
    assert_json_status "repeat: zero status=ok" "$out" "ok"
}

# ---- 运行 ----
test_reverse_basic
test_reverse_chinese
test_reverse_empty
test_trim_both
test_trim_left
test_trim_right
test_pad_right
test_pad_left
test_pad_center
test_pad_custom_char
test_repeat_basic
test_repeat_single
test_repeat_zero

echo ""
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
if [[ $FAIL -gt 0 ]]; then
    printf "失败用例: %s\n" "${FAIL_NAMES[*]}"
    exit 1
fi
echo "所有测试通过!"
