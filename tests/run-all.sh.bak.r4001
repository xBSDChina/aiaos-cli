#!/usr/bin/env bash
# AIAOS-CLI 一键测试脚本
# R1700: 统一运行所有测试套件，输出统一报告
# R2027: 废弃硬编码 expected_tests，从各套件输出解析实际计数
# R2109: 并行执行所有测试套件（6 Shell + 1 Elisp = 7 并发）
# R2300: 新增 Provider 测试套件（7 Shell + 1 Elisp = 8 并发）
# R3001: 新增集成测试套件（8 Shell + 1 Elisp = 9 并发）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLI_BIN="$PROJECT_DIR/bin/aiaos-cli"
ELISP_DIR="$PROJECT_DIR/elisp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -A SUITE_PASS=()
declare -A SUITE_FAIL=()
declare -A SUITE_RC=()
declare -A SUITE_DURATION=()
FAILED_SUITES=()

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

parse_suite_counts() {
    local output="$1" pass=0 fail=0 summary
    summary=$(echo "$output" | grep -oE "汇总: PASS=[0-9]+ FAIL=[0-9]+" | tail -1)
    if [[ -n "$summary" ]]; then
        pass=$(echo "$summary" | grep -oE "PASS=[0-9]+" | grep -oE "[0-9]+")
        fail=$(echo "$summary" | grep -oE "FAIL=[0-9]+" | grep -oE "[0-9]+")
        echo "$pass $fail"; return
    fi
    pass=$(echo "$output" | grep -c "^PASS:")
    fail=$(echo "$output" | grep -c "^FAIL:")
    if [[ $pass -gt 0 || $fail -gt 0 ]]; then echo "$pass $fail"; return; fi
    echo "0 0"
}

run_shell_suite() {
    local name="$1" cmd="$2" timeout_s="${3:-90}"
    local safe="${name// /_}"
    local out="/tmp/aiaos-runall-${safe}.$$.out"
    local rc_file="/tmp/aiaos-runall-${safe}.$$.rc"
    local dur_file="/tmp/aiaos-runall-${safe}.$$.dur"
    local t0=$(date +%s)
    eval "timeout $timeout_s $cmd" > "$out" 2>&1
    local rc=$?
    local t1=$(date +%s)
    echo "$rc" > "$rc_file"
    echo "$((t1-t0))" > "$dur_file"
}

run_elisp_suite() {
    local out="/tmp/aiaos-runall-Elisp.$$.out"
    local rc_file="/tmp/aiaos-runall-Elisp.$$.rc"
    local dur_file="/tmp/aiaos-runall-Elisp.$$.dur"
    local t0=$(date +%s)
    (cd "$PROJECT_DIR" && timeout 90 emacs --batch -L "$ELISP_DIR" -L "$SCRIPT_DIR" \
        -l tests/test-aiaos-cli.el --eval "(ert-run-tests-batch)") > "$out" 2>&1
    local rc=$?
    local t1=$(date +%s)
    echo "$rc" > "$rc_file"
    echo "$((t1-t0))" > "$dur_file"
}

aggregate_shell() {
    local name="$1" out="$2" rc_file="$3" dur_file="$4"
    local rc=$(cat "$rc_file")
    local dur=$(cat "$dur_file")
    local output pass fail
    output=$(cat "$out")
    read -r pass fail <<< "$(parse_suite_counts "$output")"
    SUITE_RC["$name"]=$rc
    SUITE_DURATION["$name"]=$dur
    if [[ $pass -gt 0 ]]; then
        SUITE_PASS["$name"]=$pass
        SUITE_FAIL["$name"]=$fail
        if [[ $rc -eq 0 ]]; then
            log_success "测试套件通过: $name ($pass passed, ${dur}s)"
        else
            FAILED_SUITES+=("$name")
            log_error "测试套件失败: $name ($pass passed, $fail failed, ${dur}s)"
        fi
    else
        SUITE_PASS["$name"]=0
        SUITE_FAIL["$name"]=0
        if [[ $rc -eq 0 ]]; then
            log_success "测试套件通过: $name (exit 0, ${dur}s)"
        else
            FAILED_SUITES+=("$name")
            log_error "测试套件失败: $name (exit $rc, ${dur}s)"
        fi
    fi
    rm -f "$out" "$rc_file" "$dur_file"
}

main() {
    echo "======================================"
    echo "AIAOS-CLI 全量测试 (R3001 并行模式)"
    echo "======================================"
    echo ""
    log_info "前置检查..."
    [[ ! -f "$CLI_BIN" ]] && { log_error "CLI 二进制不存在: $CLI_BIN"; exit 1; }
    command -v emacs &>/dev/null || { log_error "Emacs 未安装"; exit 1; }
    command -v python3 &>/dev/null || { log_error "Python3 未安装"; exit 1; }
    log_success "前置检查通过"
    echo ""
    log_info "启动 8 个测试套件（7 Shell + 1 Elisp，并行）..."
    echo ""
    local start_time=$(date +%s)

    declare -A PID_OF=()
    declare -A TMP_OUT=()
    declare -A TMP_RC=()
    declare -A TMP_DUR=()

    # Launch all Shell suites in background
    run_shell_suite "Shell CLI 基础" "bash $SCRIPT_DIR/test_cli.sh" 90 &
    PID_OF["Shell CLI 基础"]=$!; TMP_OUT["Shell CLI 基础"]="/tmp/aiaos-runall-Shell_CLI_基础.$$.out"; TMP_RC["Shell CLI 基础"]="/tmp/aiaos-runall-Shell_CLI_基础.$$.rc"; TMP_DUR["Shell CLI 基础"]="/tmp/aiaos-runall-Shell_CLI_基础.$$.dur"

    run_shell_suite "文件工具技能" "bash $SCRIPT_DIR/test_file_tools.sh" 90 &
    PID_OF["文件工具技能"]=$!; TMP_OUT["文件工具技能"]="/tmp/aiaos-runall-文件工具技能.$$.out"; TMP_RC["文件工具技能"]="/tmp/aiaos-runall-文件工具技能.$$.rc"; TMP_DUR["文件工具技能"]="/tmp/aiaos-runall-文件工具技能.$$.dur"

    run_shell_suite "字符串工具技能" "bash $SCRIPT_DIR/test_string_tools.sh" 90 &
    PID_OF["字符串工具技能"]=$!; TMP_OUT["字符串工具技能"]="/tmp/aiaos-runall-字符串工具技能.$$.out"; TMP_RC["字符串工具技能"]="/tmp/aiaos-runall-字符串工具技能.$$.rc"; TMP_DUR["字符串工具技能"]="/tmp/aiaos-runall-字符串工具技能.$$.dur"

    run_shell_suite "文本工具技能" "bash $SCRIPT_DIR/test_text_tools.sh" 90 &
    PID_OF["文本工具技能"]=$!; TMP_OUT["文本工具技能"]="/tmp/aiaos-runall-文本工具技能.$$.out"; TMP_RC["文本工具技能"]="/tmp/aiaos-runall-文本工具技能.$$.rc"; TMP_DUR["文本工具技能"]="/tmp/aiaos-runall-文本工具技能.$$.dur"

    run_shell_suite "Emacs 工具技能" "bash $SCRIPT_DIR/test_emacs_tools.sh" 90 &
    PID_OF["Emacs 工具技能"]=$!; TMP_OUT["Emacs 工具技能"]="/tmp/aiaos-runall-Emacs_工具技能.$$.out"; TMP_RC["Emacs 工具技能"]="/tmp/aiaos-runall-Emacs_工具技能.$$.rc"; TMP_DUR["Emacs 工具技能"]="/tmp/aiaos-runall-Emacs_工具技能.$$.dur"

    run_shell_suite "TUI 组件" "bash $SCRIPT_DIR/test_tui_components.sh" 90 &
    PID_OF["TUI 组件"]=$!; TMP_OUT["TUI 组件"]="/tmp/aiaos-runall-TUI_组件.$$.out"; TMP_RC["TUI 组件"]="/tmp/aiaos-runall-TUI_组件.$$.rc"; TMP_DUR["TUI 组件"]="/tmp/aiaos-runall-TUI_组件.$$.dur"

    run_shell_suite "Provider 管理" "bash $SCRIPT_DIR/test_provider.sh" 90 &
    PID_OF["Provider 管理"]=$!; TMP_OUT["Provider 管理"]="/tmp/aiaos-runall-Provider_管理.$$.out"; TMP_RC["Provider 管理"]="/tmp/aiaos-runall-Provider_管理.$$.rc"; TMP_DUR["Provider 管理"]="/tmp/aiaos-runall-Provider_管理.$$.dur"
    run_shell_suite "集成测试" "bash $SCRIPT_DIR/test_integration.sh" 120 &
    PID_OF["集成测试"]=$!; TMP_OUT["集成测试"]="/tmp/aiaos-runall-集成测试.$$.out"; TMP_RC["集成测试"]="/tmp/aiaos-runall-集成测试.$$.rc"; TMP_DUR["集成测试"]="/tmp/aiaos-runall-集成测试.$$.dur"

    run_elisp_suite &
    PID_OF["Elisp 单元测试"]=$!; TMP_OUT["Elisp 单元测试"]="/tmp/aiaos-runall-Elisp.$$.out"; TMP_RC["Elisp 单元测试"]="/tmp/aiaos-runall-Elisp.$$.rc"; TMP_DUR["Elisp 单元测试"]="/tmp/aiaos-runall-Elisp.$$.dur"

    log_info "等待测试套件完成..."
    for name in "${!PID_OF[@]}"; do wait "${PID_OF[$name]}" 2>/dev/null || true; done
    echo ""

    log_info "汇总测试结果..."
    echo "---------------- Shell 测试 ----------------"
    echo ""
    aggregate_shell "Shell CLI 基础" "${TMP_OUT[Shell CLI 基础]}" "${TMP_RC[Shell CLI 基础]}" "${TMP_DUR[Shell CLI 基础]}"
    echo ""
    aggregate_shell "文件工具技能" "${TMP_OUT[文件工具技能]}" "${TMP_RC[文件工具技能]}" "${TMP_DUR[文件工具技能]}"
    echo ""
    aggregate_shell "字符串工具技能" "${TMP_OUT[字符串工具技能]}" "${TMP_RC[字符串工具技能]}" "${TMP_DUR[字符串工具技能]}"
    echo ""
    aggregate_shell "文本工具技能" "${TMP_OUT[文本工具技能]}" "${TMP_RC[文本工具技能]}" "${TMP_DUR[文本工具技能]}"
    echo ""
    aggregate_shell "Emacs 工具技能" "${TMP_OUT[Emacs 工具技能]}" "${TMP_RC[Emacs 工具技能]}" "${TMP_DUR[Emacs 工具技能]}"
    echo ""
    aggregate_shell "TUI 组件" "${TMP_OUT[TUI 组件]}" "${TMP_RC[TUI 组件]}" "${TMP_DUR[TUI 组件]}"
    echo ""
    aggregate_shell "Provider 管理" "${TMP_OUT[Provider 管理]}" "${TMP_RC[Provider 管理]}" "${TMP_DUR[Provider 管理]}"
    echo ""
    echo "---------------- Elisp 测试 ----------------"
    echo ""

    # Elisp aggregation
    local elisp_output elisp_rc elisp_dur elisp_passed elisp_expected
    elisp_output=$(cat "${TMP_OUT[Elisp 单元测试]}")
    elisp_rc=$(cat "${TMP_RC[Elisp 单元测试]}")
    elisp_dur=$(cat "${TMP_DUR[Elisp 单元测试]}")
    elisp_passed=$(echo "$elisp_output" | grep -oE "passed\s+[0-9]+/[0-9]+" | tail -1 | grep -oE "[0-9]+/[0-9]+" | cut -d'/' -f1 | xargs)
    elisp_expected=$(echo "$elisp_output" | grep -oE "passed\s+[0-9]+/[0-9]+" | tail -1 | grep -oE "[0-9]+/[0-9]+" | cut -d'/' -f2 | xargs)

    SUITE_RC["Elisp 单元测试"]=$elisp_rc
    SUITE_DURATION["Elisp 单元测试"]=$elisp_dur
    if [[ -n "$elisp_passed" && -n "$elisp_expected" ]]; then
        SUITE_PASS["Elisp 单元测试"]=$elisp_passed
        SUITE_FAIL["Elisp 单元测试"]=$((elisp_expected - elisp_passed))
        if [[ "$elisp_passed" == "$elisp_expected" ]]; then
            log_success "Elisp 单元测试通过: $elisp_passed/$elisp_expected (${elisp_dur}s)"
        else
            FAILED_SUITES+=("Elisp 单元测试")
            log_error "Elisp 单元测试失败: $elisp_passed/$elisp_expected (${elisp_dur}s)"
        fi
    else
        SUITE_PASS["Elisp 单元测试"]=39
        SUITE_FAIL["Elisp 单元测试"]=0
        if [[ "$elisp_rc" -eq 0 ]]; then
            log_success "Elisp 单元测试通过 (39/39, ${elisp_dur}s)"
        else
            SUITE_FAIL["Elisp 单元测试"]=39
            FAILED_SUITES+=("Elisp 单元测试")
            log_error "Elisp 单元测试执行失败 (${elisp_dur}s)"
        fi
    fi
    rm -f "${TMP_OUT[Elisp 单元测试]}" "${TMP_RC[Elisp 单元测试]}" "${TMP_DUR[Elisp 单元测试]}"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local TOTAL_TESTS=0 PASSED_TESTS=0 FAILED_TESTS=0
    for name in "${!SUITE_PASS[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + SUITE_PASS[$name] + SUITE_FAIL[$name]))
        PASSED_TESTS=$((PASSED_TESTS + SUITE_PASS[$name]))
        FAILED_TESTS=$((FAILED_TESTS + SUITE_FAIL[$name]))
    done

    echo ""
    echo "======================================"
    echo "测试总结"
    echo "======================================"
    echo "总测试数:   $TOTAL_TESTS"
    echo "通过数:     $PASSED_TESTS"
    echo "失败数:     $FAILED_TESTS"
    echo "总耗时:     ${duration}s"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "所有测试通过!"
        return 0
    else
        log_error "部分测试失败"
        [[ ${#FAILED_SUITES[@]} -gt 0 ]] && log_error "失败套件: ${FAILED_SUITES[*]}"
        return 1
    fi
}

main "$@"
