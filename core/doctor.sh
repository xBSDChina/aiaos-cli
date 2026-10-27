#!/usr/bin/env bash
# AIAOS-CLI Doctor 环境诊断模块

set -euo pipefail

# Default values for environment variables (can be overridden)
AIAOS_CLI_DATA_DIR="${AIAOS_CLI_DATA_DIR:-$HOME/.local/share/aiaos}"
AIAOS_CLI_CONFIG_DIR="${AIAOS_CLI_CONFIG_DIR:-$HOME/.config/aiaos}"
AIAOS_CLI_CACHE_DIR="${AIAOS_CLI_CACHE_DIR:-$HOME/.cache/aiaos}"
AIAOS_CLI_OUTPUT_FORMAT="${AIAOS_CLI_OUTPUT_FORMAT:-table}"


# 全局数组存储检查结果
DOCTOR_CHECKS=()
log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }


show_help() {
    cat <<EOF
用法: aiaos-cli doctor <动作> [选项]

动作:
  check       检查环境依赖
  fix         尝试修复常见问题
  report      生成诊断报告

选项:
  --verbose         详细输出
  --format FORMAT   输出格式 (json|table, 默认: table)
  -h, --help        显示帮助

示例:
  aiaos-cli doctor check
  aiaos-cli doctor fix
  aiaos-cli doctor report --verbose
EOF
}

check_command() {
    local cmd="$1" min_version="${2:-}" desc="${3:-}" optional="${4:-false}"
    local status="✓" version="" details=""

    if command -v "$cmd" &>/dev/null; then
        case "$cmd" in
            emacs) version=$(emacs --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || version="error" ;;
            python3) version=$(python3 --version | cut -d' ' -f2) ;;
            git) version=$(git --version | cut -d' ' -f3) ;;
            jq) version=$(jq --version | sed 's/^jq-//') ;;
            node) version=$(node --version | sed 's/^v//') ;;
            cargo) version=$(cargo --version | cut -d' ' -f2) ;;
            go) version=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | sed 's/go//') ;;
            docker) version=$(docker --version | cut -d' ' -f3 | sed 's/,//') ;;
            # R1317: curl/wget 是 agent 场景常用依赖（下载/HTTP 探测）
            curl) version=$(curl --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || version="found" ;;
            wget) version=$(wget --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || version="found" ;;
            *) version="found" ;;
        esac

        # Handle emacs error case (command exists but fails to run)
        if [[ "$version" == "error" ]] || [[ -z "$version" ]]; then
            if [[ "$optional" == "true" ]]; then
                status="⚠"
            else
                status="⚠"
            fi
            version="unavailable"
            details="无法获取版本 (运行时错误)"
            DOCTOR_CHECKS+=("$status|$cmd|$version|$desc|$details")
            return
        fi

        if [[ -n "$min_version" ]]; then
            local cur_major=$(echo "$version" | cut -d. -f1)
            local cur_minor=$(echo "$version" | cut -d. -f2)
            local min_major=$(echo "$min_version" | cut -d. -f1)
            local min_minor=$(echo "$min_version" | cut -d. -f2)

            if [[ $cur_major -lt $min_major ]] || [[ $cur_major -eq $min_major && $cur_minor -lt $min_minor ]]; then
                status="⚠"
                details="版本 $version < 最低要求 $min_version"
            fi
        fi
    else
        if [[ "$optional" == "true" ]]; then
            status="⚠"
        else
            status="✗"
        fi
        version="missing"
        details="未安装"
    fi

    DOCTOR_CHECKS+=("$status|$cmd|$version|$desc|$details")
}

check_directory() {
    local dir="$1" desc="$2"
    local status="✓" version="" details=""

    if [[ -d "$dir" ]]; then
        if [[ -w "$dir" ]]; then
            details="可写"
        else
            status="⚠"
            details="不可写"
        fi
    else
        status="✗"
        version="missing"
        details="目录不存在"
    fi

    DOCTOR_CHECKS+=("$status|dir:$dir|$version|$desc|$details")
}

doctor_check() {
    local verbose=false format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose) verbose=true; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; return 0 ;;
            *) log_error "未知选项: $1"; show_help; return 1 ;;
        esac
    done

    DOCTOR_CHECKS=()

    check_command emacs "28.1" "Emacs 编辑器 (核心运行环境)"
    check_command python3 "3.10" "Python 3.10+ (脚本运行时)"
    check_command git "2.30" "Git 版本控制"
    check_command jq "1.6" "JSON 处理工具"
    # R1315: sha256sum/md5sum 是 file-tools/checksum 技能的运行时依赖（TD-024）
    check_command sha256sum "" "SHA-256 校验工具 (file-tools/checksum 依赖)"
    check_command md5sum "" "MD5 校验工具 (file-tools/checksum 依赖)"
    check_command node "" "Node.js (可选，Node 技能需要)" "true"
    check_command cargo "" "Rust 工具链 (可选，Rust 技能需要)" "true"
    check_command go "" "Go 工具链 (可选，Go 技能需要)" "true"
    check_command docker "" "Docker (可选，容器部署需要)" "true"
    # R1317: curl/wget 是 agent 场景常用依赖（下载/HTTP 探测），
    # 至少装一个即可。此处按 optional=true 处理：缺失仅告警不阻断。
    check_command curl "" "HTTP 客户端 (agent 下载/探测依赖)" "true"
    check_command wget "" "HTTP 客户端 (curl 备选)" "true"

    check_directory "$AIAOS_CLI_DATA_DIR" "数据目录"
    check_directory "$AIAOS_CLI_CONFIG_DIR" "配置目录"
    check_directory "$AIAOS_CLI_CACHE_DIR" "缓存目录"

    if [[ ! -f "$AIAOS_CLI_CONFIG_DIR/cli.yaml" ]]; then
        DOCTOR_CHECKS+=("⚠|config|missing|配置文件|将使用默认配置")
    else
        DOCTOR_CHECKS+=("✓|config|exists|配置文件|已存在")
        # R4001: 检查 safety 配置节
        local safety_check
        safety_check=$(python3 -c "
import yaml, sys
try:
    with open(sys.argv[1]) as f:
        cfg = yaml.safe_load(f) or {}
    safety = cfg.get('safety', {})
    if isinstance(safety, dict):
        d = safety.get('dangerous_patterns', [])
        f = safety.get('forbidden_paths', [])
        print(f'{len(d)}:{len(f)}')
    else:
        print('0:0')
except Exception:
    print('0:0')
" "$AIAOS_CLI_CONFIG_DIR/cli.yaml" 2>/dev/null) || safety_check="0:0"
        local dp="${safety_check%%:*}"
        local fp="${safety_check#*:}"
        if [[ "$dp" -gt 0 || "$fp" -gt 0 ]]; then
            DOCTOR_CHECKS+=("✓|safety|configured|安全配置|自定义模式 ${dp} 条，禁止路径 ${fp} 条")
        else
            DOCTOR_CHECKS+=("✓|safety|default|安全配置|使用内置默认模式")
        fi
    fi

    local passed=0 warnings=0 failed=0

    if [[ "$format" == "json" ]]; then
        local json="{\"checks\":["
        local first=true
        for check in "${DOCTOR_CHECKS[@]}"; do
            IFS='|' read -r status name version desc details <<< "$check"
            [[ "$first" == true ]] && first=false || json+=","
            json+="{\"status\":\"$status\",\"name\":\"$name\",\"version\":\"$version\",\"description\":\"$desc\",\"details\":\"$details\"}"
            case "$status" in
                "✓") ((passed++)) || true ;;
                "⚠") ((warnings++)) || true ;;
                "✗") ((failed++)) || true ;;
            esac
        done
        json+="],\"summary\":{\"passed\":$passed,\"warnings\":$warnings,\"failed\":$failed}}"
        echo "$json"
    else
        printf "%-4s %-20s %-15s %-30s %s\n" "ST" "NAME" "VERSION" "DESCRIPTION" "DETAILS"
        printf "%-4s %-20s %-15s %-30s %s\n" "---" "--------------------" "---------------" "------------------------------" "-----"

        for check in "${DOCTOR_CHECKS[@]}"; do
            IFS='|' read -r status name version desc details <<< "$check"
            printf "%-4s %-20s %-15s %-30s %s\n" "$status" "$name" "$version" "$desc" "$details"

            case "$status" in
                "✓") ((passed++)) || true ;;
                "⚠") ((warnings++)) || true ;;
                "✗") ((failed++)) || true ;;
            esac
        done

        echo
        echo "汇总: 通过 $passed, 警告 $warnings, 失败 $failed"

        if [[ $failed -gt 0 ]]; then
            echo
            log_error "发现 $failed 个关键问题，请解决后重试"
            return 1
        elif [[ $warnings -gt 0 ]]; then
            echo
            log_warn "发现 $warnings 个警告，功能可能受限"
        else
            echo
            log_info "所有检查通过！"
        fi
    fi
}

doctor_fix() {
    log_info "尝试修复常见问题..."

    if [[ ! -d "$AIAOS_CLI_DATA_DIR" ]]; then
        mkdir -p "$AIAOS_CLI_DATA_DIR"
        log_info "创建数据目录: $AIAOS_CLI_DATA_DIR"
    fi

    if [[ ! -d "$AIAOS_CLI_CONFIG_DIR" ]]; then
        mkdir -p "$AIAOS_CLI_CONFIG_DIR"
        log_info "创建配置目录: $AIAOS_CLI_CONFIG_DIR"
    fi

    if [[ ! -d "$AIAOS_CLI_CACHE_DIR" ]]; then
        mkdir -p "$AIAOS_CLI_CACHE_DIR"
        log_info "创建缓存目录: $AIAOS_CLI_CACHE_DIR"
    fi

    if [[ ! -f "$AIAOS_CLI_CONFIG_DIR/cli.yaml" ]]; then
        cat > "$AIAOS_CLI_CONFIG_DIR/cli.yaml" <<EOF
# AIAOS-CLI 配置文件
data_dir: "$AIAOS_CLI_DATA_DIR"
config_dir: "$AIAOS_CLI_CONFIG_DIR"
cache_dir: "$AIAOS_CLI_CACHE_DIR"
log_level: "info"
output_format: "table"
EOF
        log_info "创建默认配置文件: $AIAOS_CLI_CONFIG_DIR/cli.yaml"
    fi

    log_info "修复完成"
}

doctor_report() {
    doctor_check --verbose --format json
}

case "${1:-}" in
    check)
        doctor_check "${@:2}"
        ;;
    fix)
        doctor_fix "${@:2}"
        ;;
    report)
        doctor_report "${@:2}"
        ;;
    *)
        show_help
        exit 1
        ;;
esac