#!/usr/bin/env bash
# AIAOS-CLI emacs-tools 技能端到端测试
# 用法: bash tests/test_emacs_tools.sh
# 退出码: 0 全绿；1 有失败

set -uo pipefail

CLI_BIN="${CLI_BIN:-/home/shjiaye8/aiaos/aiaos-cli/bin/aiaos-cli}"
export AIAOS_CLI_OUTPUT_FORMAT="json"
PASS=0
FAIL=0
declare -a FAILS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_json_status() {
    local label="$1"
    local json="$2"
    local expected="$3"
    local actual
    actual=$(echo "$json" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"$//')
    if [[ -z "$actual" ]]; then
        actual=$(echo "$json" | grep -o '{status:[^,}]*' | head -1 | sed 's/{status://')
    fi
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}PASS${NC}: $label"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: $label (expected=$expected, got=$actual)"
        ((FAIL++))
        FAILS+=("$label")
    fi
}

assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}PASS${NC}: $label"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: $label (missing: $needle)"
        ((FAIL++))
        FAILS+=("$label")
    fi
}

assert_not_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}PASS${NC}: $label"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: $label (unexpected: $needle)"
        ((FAIL++))
        FAILS+=("$label")
    fi
}

run_skill() {
    local cmd="$1"; shift
    local args_json="{}"
    local opts_json="{}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --args)
                shift
                args_json="$1"
                ;;
            --options)
                shift
                opts_json="$1"
                ;;
            *)
                ;;
        esac
        shift
    done
    "$CLI_BIN" skill run --name "$(echo "$cmd" | cut -d/ -f1)" \
        --command "$(echo "$cmd" | cut -d/ -f2)" \
        --args "$args_json" --options "$opts_json" 2>&1
}

echo "=== emacs-tools 端到端测试 ==="

# 1. encode Base64
out=$(run_skill "emacs-tools/encode" --args '{"text": "Hello World"}')
assert_json_status "encode Base64" "$out" "ok"

# 2. encode URL
out=$(run_skill "emacs-tools/encode" --args '{"text": "hello world"}' --options '{"mode": "url"}')
assert_json_status "encode URL" "$out" "ok"

# 3. format 折行
out=$(run_skill "emacs-tools/format" --args '{"text": "Hello World Foo Bar Baz", "width": 10}')
assert_json_status "format 折行" "$out" "ok"
assert_contains "format 输出 Hello Worl" "$out" "Hello Worl"

# 4. wordfreq
out=$(run_skill "emacs-tools/wordfreq" --args '{"text": "foo bar foo baz"}' --options '{"top": 2}')
assert_json_status "wordfreq" "$out" "ok"
assert_contains "wordfreq 含 foo" "$out" "foo"

# 5. stats
out=$(run_skill "emacs-tools/stats" --args '{"text": "Hello World Foo"}')
assert_json_status "stats 统计" "$out" "ok"
assert_contains "stats 含 chars" "$out" "chars"
assert_contains "stats 含 words" "$out" "words"
assert_contains "stats 含 lines" "$out" "lines"
assert_contains "stats 含 bytes" "$out" "bytes"

# 6. slugify 基础
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello World!"}')
assert_json_status "slugify 基础" "$out" "ok"
assert_contains "slugify 输出 hello-world" "$out" "hello-world"

# 7. slugify 自定义分隔符
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello World"}' --options '{"separator": "_"}')
assert_json_status "slugify 下划线" "$out" "ok"
assert_contains "slugify 下划线输出" "$out" "hello_world"

# 8. slugify 截断
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello World Foo Bar Baz"}' --options '{"truncate": 15}')
assert_json_status "slugify 截断" "$out" "ok"
assert_contains "slugify 截断输出" "$out" "hello-world-foo"

# 9. slugify trim
out=$(run_skill "emacs-tools/slugify" --args '{"text": "  --Trim Me--  "}')
assert_json_status "slugify trim" "$out" "ok"
assert_contains "slugify trim 输出" "$out" "trim-me"

# 10. slugify 折叠
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello!!!World"}')
assert_json_status "slugify 折叠" "$out" "ok"
assert_contains "slugify 折叠输出" "$out" "hello-world"

# 11. 错误: encode 缺参
out=$(run_skill "emacs-tools/encode" --args '{}')
assert_json_status "encode 缺参报错" "$out" "error"

# 12. 错误: format 非法 width
out=$(run_skill "emacs-tools/format" --args '{"text": "abc", "width": "not-a-number"}')
assert_json_status "format 非法 width" "$out" "error"

# 13. 错误: slugify 非法 truncate
out=$(run_skill "emacs-tools/slugify" --args '{"text": "abc"}' --options '{"truncate": "-5"}')
assert_json_status "slugify 非法 truncate" "$out" "error"

# 14. 错误: slugify 空 separator
out=$(run_skill "emacs-tools/slugify" --args '{"text": "abc"}' --options '{"separator": ""}')
assert_json_status "slugify 空 separator" "$out" "error"

# 15. slugify Unicode 保留中文
out=$(run_skill "emacs-tools/slugify" --args '{"text": "人工智能 AIAOS 大模型"}' --options '{"unicode": true}')
assert_json_status "slugify unicode 中文" "$out" "ok"
assert_contains "slugify unicode 中文输出" "$out" "人工智能-aiaos-大模型"

# 16. slugify 默认丢弃中文
out=$(run_skill "emacs-tools/slugify" --args '{"text": "人工智能 AIAOS 大模型"}')
assert_json_status "slugify 默认丢弃中文" "$out" "ok"
out_json=$(echo "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['output'])")
assert_contains "slugify 默认输出仅ASCII" "$out_json" "aiaos"
assert_not_contains "slugify 默认输出无中文" "$out_json" "人工"

# 17. slugify Unicode 混合特殊字符
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello 世界! @#￥% 测试"}' --options '{"unicode": true}')
assert_json_status "slugify unicode 混合" "$out" "ok"
assert_contains "slugify unicode 混合输出" "$out" "hello-世界-测试"

# 18. slugify preserve 保留下划线
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello_World"}' --options '{"separator": "-", "preserve": "_"}')
assert_json_status "slugify preserve" "$out" "ok"
assert_contains "slugify preserve 输出" "$out" "hello_world"

# 19. slugify has-unicode 字段
out=$(run_skill "emacs-tools/slugify" --args '{"text": "中文测试"}' --options '{"unicode": true}')
assert_json_status "slugify has-unicode" "$out" "ok"
assert_contains "slugify has-unicode 字段" "$out" '"has-unicode":true'

# 20. slugify removed-char-count 字段
out=$(run_skill "emacs-tools/slugify" --args '{"text": "Hello 世界"}')
assert_json_status "slugify removed-count" "$out" "ok"
assert_contains "slugify removed-count 字段" "$out" '"removed-char-count":3'
assert_contains "slugify 默认丢弃中文输出" "$out" '"output":"hello"'

echo
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
if [[ $FAIL -gt 0 ]]; then
    echo "失败用例:"
    for f in "${FAILS[@]}"; do echo "  - $f"; done
    exit 1
fi

exit 0
