#!/usr/bin/env bash
# AIAOS-CLI file-tools 技能端到端测试
# 沉淀自 §26.7 TD-023：把 file-tools 的 8 条用例脚本化，纳入回归
#
# 用法: bash tests/test_file_tools.sh
# 退出码: 0 全绿；1 有失败
#
# 契约说明：
#   - --args    : 命令必填入参（如 path）
#   - --options : 命令可选参数（如 mode/lines/algo）
#   与 skill.yaml 的 args / options 声明一致；混用会导致命令取不到值。

set -uo pipefail

CLI_BIN="${CLI_BIN:-/home/shjiaye8/aiaos/aiaos-cli/bin/aiaos-cli}"
FIXTURE_DIR="${FIXTURE_DIR:-/tmp/aiaos-file-tools-fix-$$}"
PASS=0
FAIL=0
declare -a FAIL_NAMES=()

# ---- 断言工具 ---------------------------------------------------------------
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

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf "PASS: %s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "FAIL: %s (unexpected '%s')\n  actual: %s\n" "$label" "$needle" "$haystack"
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

# 把 key value key value ... 序列化为 JSON
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

# 调用 file-tools/<cmd>，args 是必填入参，opts 是可选参数
# 用 -- 分隔：run_skill <cmd> <arg-k> <arg-v> ... -- <opt-k> <opt-v> ...
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
    "$CLI_BIN" skill run "file-tools/$cmd" \
        --args "$args_json" --options "$opts_json" --format json 2>/dev/null
}

# ---- 夹具 -------------------------------------------------------------------
setup_fixture() {
    mkdir -p "$FIXTURE_DIR"
    cat > "$FIXTURE_DIR/sample.txt" <<'EOF'
The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump!
The five boxing wizards jump quickly.
Sphinx of black quartz, judge my vow.
EOF
    printf 'line1\nline2\nline3\nline4\nline5\n' > "$FIXTURE_DIR/lines.txt"
}

cleanup() {
    rm -rf "$FIXTURE_DIR"
}

# ---- 测试用例 ---------------------------------------------------------------
test_stat_basic() {
    local out
    out=$(run_skill stat path "$FIXTURE_DIR/sample.txt")
    assert_json_status "stat: status=ok" "$out" "ok"
    assert_contains "stat: 含 bytes 字段" "$out" '"bytes":'
    assert_contains "stat: 含 lines 字段" "$out" '"lines":'
    assert_contains "stat: 含 mtime 字段" "$out" '"mtime":'
}

test_head_tail_head() {
    local out
    out=$(run_skill head-tail path "$FIXTURE_DIR/lines.txt" -- mode head lines 2)
    assert_json_status "head-tail head: status=ok" "$out" "ok"
    assert_contains "head-tail head: 含 line1" "$out" 'line1'
    assert_contains "head-tail head: 含 line2" "$out" 'line2'
    assert_not_contains "head-tail head: 不含 line3" "$out" 'line3'
    assert_contains "head-tail head: returned=2" "$out" '"returned":2'
}

test_head_tail_tail() {
    local out
    out=$(run_skill head-tail path "$FIXTURE_DIR/lines.txt" -- mode tail lines 2)
    assert_json_status "head-tail tail: status=ok" "$out" "ok"
    assert_contains "head-tail tail: 含 line4" "$out" 'line4'
    assert_contains "head-tail tail: 含 line5" "$out" 'line5'
    assert_not_contains "head-tail tail: 不含 line1" "$out" 'line1'
}

test_checksum_sha256() {
    local out expected
    out=$(run_skill checksum path "$FIXTURE_DIR/sample.txt" -- algo sha256)
    assert_json_status "checksum sha256: status=ok" "$out" "ok"
    expected=$(sha256sum "$FIXTURE_DIR/sample.txt" | awk '{print $1}')
    assert_contains "checksum sha256: 与系统 sha256sum 一致" "$out" "$expected"
}

test_checksum_md5() {
    local out expected
    out=$(run_skill checksum path "$FIXTURE_DIR/sample.txt" -- algo md5)
    assert_json_status "checksum md5: status=ok" "$out" "ok"
    expected=$(md5sum "$FIXTURE_DIR/sample.txt" | awk '{print $1}')
    assert_contains "checksum md5: 与系统 md5sum 一致" "$out" "$expected"
}

test_normalize() {
    local out
    out=$(run_skill normalize path "$FIXTURE_DIR/sample.txt")
    assert_json_status "normalize: status=ok" "$out" "ok"
    assert_contains "normalize: name=sample.txt" "$out" '"name":"sample.txt"'
    assert_contains "normalize: extension=txt" "$out" '"extension":"txt"'
    assert_contains "normalize: stem=sample" "$out" '"stem":"sample"'
    assert_contains "normalize: exists=true" "$out" '"exists":true'
}

test_invalid_path() {
    local out
    out=$(run_skill stat path "/tmp/definitely-not-exist-$$")
    assert_json_status "stat 缺失文件: status=error" "$out" "error"
    assert_contains "stat 缺失文件: code=NOT_FOUND" "$out" '"code":"NOT_FOUND"'
}

test_invalid_args() {
    local out
    out=$(run_skill head-tail path "$FIXTURE_DIR/lines.txt" -- mode middle lines 2)
    assert_json_status "head-tail 非法 mode: status=error" "$out" "error"
    assert_contains "head-tail 非法 mode: code=INVALID_ARGS" "$out" '"code":"INVALID_ARGS"'
}

# ---- 主流程 -----------------------------------------------------------------
echo "=== AIAOS-CLI file-tools 端到端测试开始 ==="
echo "CLI: $CLI_BIN"
echo "夹具目录: $FIXTURE_DIR"
echo ""

setup_fixture
trap cleanup EXIT

test_stat_basic
test_head_tail_head
test_head_tail_tail
test_checksum_sha256
test_checksum_md5
test_normalize
test_invalid_path
test_invalid_args

echo ""
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
if [[ $FAIL -gt 0 ]]; then
    echo "失败用例:"
    for name in "${FAIL_NAMES[@]}"; do
        echo "  - $name"
    done
    exit 1
fi
exit 0
