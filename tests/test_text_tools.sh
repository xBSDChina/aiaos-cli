#!/usr/bin/env bash
# AIAOS-CLI text-tools 技能端到端测试
# 用法: bash tests/test_text_tools.sh
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
    "$CLI_BIN" skill run "text-tools/$cmd" \
        --args "$args_json" --options "$opts_json" --format json 2>/dev/null
}

echo "=== text-tools 技能测试 ==="

# ---- 测试用例 ----
test_case_upper() {
    local out
    out=$(run_skill case text "hello world")
    assert_json_status "case: 默认 upper status=ok" "$out" "ok"
    assert_contains "case: 含 HELLO WORLD" "$out" 'HELLO WORLD'
}

test_case_lower() {
    local out
    out=$(run_skill case text "HELLO WORLD" -- mode lower)
    assert_json_status "case: lower status=ok" "$out" "ok"
    assert_contains "case: lower 含 hello world" "$out" 'hello world'
}

test_case_title() {
    local out
    out=$(run_skill case text "hello world" -- mode title)
    assert_json_status "case: title status=ok" "$out" "ok"
    assert_contains "case: title 含 Hello World" "$out" 'Hello World'
}

test_wordcount_words() {
    local out
    out=$(run_skill wordcount text "one two three four five")
    assert_json_status "wordcount: words status=ok" "$out" "ok"
    assert_contains "wordcount: words 含 5" "$out" '"words":5'
}

test_wordcount_punct() {
    local out
    out=$(run_skill wordcount text "one, two. three!")
    assert_json_status "wordcount: 带标点 status=ok" "$out" "ok"
    assert_contains "wordcount: 含 3" "$out" '"words":3'
}

test_wordcount_multiline() {
    local out
    out=$(run_skill wordcount text "$(printf 'line1\nline2\nline3\nline4')")
    assert_json_status "wordcount: 多行 status=ok" "$out" "ok"
    assert_contains "wordcount: 多行 含 4" "$out" '"lines":4'
}

test_wordcount_empty() {
    local out
    out=$(run_skill wordcount text "")
    assert_json_status "wordcount: 空文本 status=ok" "$out" "ok"
    assert_contains "wordcount: 空文本 含 0" "$out" '"words":0'
}

test_wordcount_chars() {
    local out
    out=$(run_skill wordcount text "hello world" -- count chars)
    assert_json_status "wordcount: chars status=ok" "$out" "ok"
    assert_contains "wordcount: chars 含 11" "$out" '"chars":11'
}

test_wordcount_lines() {
    local out
    out=$(run_skill wordcount text "$(printf 'line1\nline2\nline3')" -- count lines)
    assert_json_status "wordcount: lines status=ok" "$out" "ok"
    assert_contains "wordcount: lines 含 3" "$out" '"lines":3'
}

test_wordcount_single() {
    local out
    out=$(run_skill wordcount text "hello")
    assert_json_status "wordcount: 单字 status=ok" "$out" "ok"
    assert_contains "wordcount: 单字 含 1" "$out" '"words":1'
}

# ---- 运行 ----
test_case_upper
test_case_lower
test_case_title
test_wordcount_words
test_wordcount_punct
test_wordcount_multiline
test_wordcount_empty
test_wordcount_chars
test_wordcount_lines
test_wordcount_single

echo ""
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
if [[ $FAIL -gt 0 ]]; then
    printf "失败用例: %s\n" "${FAIL_NAMES[*]}"
    exit 1
fi
echo "所有测试通过!"
