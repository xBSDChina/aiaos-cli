#!/usr/bin/env bash
# AIAOS-CLI Log 查看模块

set -euo pipefail

LOG_DIR="${AIAOS_CLI_DATA_DIR}/logs"
mkdir -p "$LOG_DIR"

show_help() {
    cat <<EOF
用法: aiaos-cli log <动作> [选项]

动作:
  tail        实时跟踪日志
  search      搜索日志
  export      导出日志
  analyze     分析日志统计
  list        列出日志文件

选项:
  --file FILE         日志文件 (tail, search, export)
  --pattern PATTERN   搜索模式 (search)
  --level LEVEL       日志级别过滤 (search: debug,info,warn,error)
  --since TIME        起始时间 (search: 1h, 30m, 2024-01-01)
  --until TIME        结束时间 (search)
  --limit N           限制行数 (tail, search, 默认: 100)
  --follow            持续跟踪 (tail)
  --output FILE       输出文件 (export)
  --format FORMAT     输出格式 (json|jsonl|table|raw, 默认: raw)
  -h, --help          显示帮助

示例:
  aiaos-cli log tail --follow
  aiaos-cli log search --pattern "error" --level error
  aiaos-cli log export --output ~/logs-backup.json
  aiaos-cli log analyze
EOF
}

get_main_log() {
    # Use the same log file as the main CLI logging system
    if [[ -n "${AIAOS_CLI_LOG_FILE:-}" ]]; then
        echo "${AIAOS_CLI_LOG_FILE}"
    else
        echo "${AIAOS_CLI_DATA_DIR}/logs/cli.log"
    fi
}

log_tail() {
    local log_file=$(get_main_log)
    local follow=false limit=100 format="${AIAOS_CLI_OUTPUT_FORMAT:-raw}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) log_file="$2"; shift 2 ;;
            --follow) follow=true; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --limit=*) limit="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -f "$log_file" ]] || { log_error "日志文件不存在: $log_file"; exit 1; }

    # --follow 时强制 raw 输出（流式）
    if [[ "$follow" == true ]]; then
        tail -f -n "$limit" "$log_file"
        return 0
    fi

    local content
    content=$(tail -n "$limit" "$log_file")

    case "$format" in
        json)
            echo "$content" | python3 -c "
import json, sys
lines = sys.stdin.read().strip().split('\n')
output = []
for line in lines:
    if not line:
        continue
    try:
        obj = json.loads(line)
        output.append({'level': obj.get('level', 'raw'), 'timestamp': obj.get('timestamp'), 'message': obj.get('message', '')})
    except json.JSONDecodeError:
        output.append({'level': 'raw', 'timestamp': None, 'message': line})
print(json.dumps({'status': 'success', 'count': len(output), 'lines': output}, ensure_ascii=False))
"
            ;;
        table)
            echo "$content" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.rstrip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        level = obj.get('level', 'raw').ljust(10)
        ts = obj.get('timestamp', '') or ''
        msg = obj.get('message', '')
        print(f'{level} {ts[:20]:<20} {msg}')
    except json.JSONDecodeError:
        print(line)
"
            ;;
        raw|*)
            echo "$content"
            ;;
    esac
}

log_search() {
    local log_file=$(get_main_log)
    local pattern="" level="" since="" until="" limit=100 format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) log_file="$2"; shift 2 ;;
            --pattern) pattern="$2"; shift 2 ;;
            --level) level="$2"; shift 2 ;;
            --level=*) level="${1#*=}"; shift ;;
            --since) since="$2"; shift 2 ;;
            --until) until="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --limit=*) limit="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -f "$log_file" ]] || { log_error "日志文件不存在: $log_file"; exit 1; }

    local grep_cmd="grep"
    [[ -n "$pattern" ]] && grep_cmd+=" -E \"$pattern\""
    # R2105: JSON Lines 格式下，level 过滤改为 grep 字段值
    [[ -n "$level" ]] && grep_cmd+=" | grep -i \"\\\"level\\\":\\\"$level\\\"\""

    local results=$(eval "$grep_cmd \"$log_file\" | tail -n \"$limit\"")

    if [[ "$format" == "json" ]]; then
        echo "$results" | python3 -c "
import json, sys
lines = sys.stdin.read().strip().split('\n')
output = []
for line in lines:
    if not line:
        continue
    try:
        obj = json.loads(line)
        output.append({'level': obj.get('level', 'raw'), 'timestamp': obj.get('timestamp'), 'message': obj.get('message', '')})
    except json.JSONDecodeError:
        output.append({'raw': line})
print(json.dumps(output, ensure_ascii=False))
"
    else
        echo "$results"
    fi
}

log_export() {
    local log_file=$(get_main_log)
    local output_file="" format="json"
    # R2400: 若 main() 通过 --format 设置了 AIAOS_CLI_OUTPUT_FORMAT，
    # 且非默认 table 值，则使用它作为默认格式
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" != "table" ]]; then
        format="$AIAOS_CLI_OUTPUT_FORMAT"
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) log_file="$2"; shift 2 ;;
            --output) output_file="$2"; shift 2 ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$output_file" ]] && output_file="$LOG_DIR/export-$(date +%Y%m%d-%H%M%S).$format"
    [[ -f "$log_file" ]] || { log_error "日志文件不存在: $log_file"; exit 1; }

    # R2400 修复: 支持 jsonl 格式（每行一个 JSON 对象，与源日志一致）
    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    lines = f.readlines()

output = []
for line in lines:
    line = line.rstrip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        output.append({'level': obj.get('level', 'raw'), 'timestamp': obj.get('timestamp'), 'message': obj.get('message', '')})
    except json.JSONDecodeError:
        output.append({'raw': line})

with open(sys.argv[2], 'w') as f:
    json.dump(output, f, indent=2)
" "$log_file" "$output_file"
    elif [[ "$format" == "jsonl" ]]; then
        # JSONL: 逐行输出，保留原始 JSON 结构
        python3 -c "
import json, sys
with open(sys.argv[1]) as f, open(sys.argv[2], 'w') as out:
    for line in f:
        line = line.rstrip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            out.write(json.dumps(obj, ensure_ascii=False) + '\\n')
        except json.JSONDecodeError:
            out.write(json.dumps({'raw': line}, ensure_ascii=False) + '\\n')
"
    else
        cp "$log_file" "$output_file"
    fi

    output_result "success" "日志已导出" "file" "$output_file" "format" "$format"
}

log_analyze() {
    local log_file=$(get_main_log)
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    [[ -f "$log_file" ]] || { log_error "日志文件不存在: $log_file"; exit 1; }

    python3 -c "
import json, sys
from collections import Counter

with open(sys.argv[1]) as f:
    lines = f.readlines()

total = len(lines)
levels = Counter()
hours = Counter()
errors = []

for line in lines:
    line = line.rstrip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        level = obj.get('level', 'raw')
        msg = obj.get('message', '')
        ts = obj.get('timestamp', '')
    except json.JSONDecodeError:
        level = 'raw'
        msg = line
        ts = ''
    levels[level] += 1
    if level.upper() in ('ERROR', 'WARN'):
        errors.append({'level': level, 'message': msg})
    if ts:
        hour_key = ts[:13]
        hours[hour_key] += 1

if sys.argv[2] == 'json':
    print(json.dumps({
        'total_lines': total,
        'levels': dict(levels),
        'hourly_distribution': dict(hours),
        'recent_errors': errors[-10:]
    }, indent=2))
else:
    print(f'日志分析报告')
    print(f'===============')
    print(f'总行数: {total}')
    print(f'')
    print(f'级别分布:')
    for level, count in levels.most_common():
        print(f'  {level}: {count}')
    print(f'')
    print(f'最近错误 (最多10条):')
    for e in errors[-10:]:
        print(f'  [{e[\"level\"]}] {e[\"message\"][:80]}')
    print(f'')
    print(f'按小时分布 (最近24小时):')
    for hour, count in sorted(hours.items())[-24:]:
        print(f'  {hour}: {count}')
" "$log_file" "$format"
}

log_list() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, os
files = []
for f in os.listdir('$LOG_DIR'):
    path = os.path.join('$LOG_DIR', f)
    if os.path.isfile(path):
        stat = os.stat(path)
        files.append({
            'name': f,
            'size': stat.st_size,
            'modified': stat.st_mtime
        })
print(json.dumps(files, indent=2))
"
    else
        printf "%-40s %10s %s\n" "NAME" "SIZE" "MODIFIED"
        printf "%-40s %10s %s\n" "----------------------------------------" "----------" "-------------------"
        for f in "$LOG_DIR"/*; do
            [[ -f "$f" ]] || continue
            local name=$(basename "$f")
            local size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
            local modified=$(stat -c%y "$f" 2>/dev/null | cut -d. -f1 || stat -f%Sm "$f")
            printf "%-40s %10s %s\n" "$name" "$size" "$modified"
        done
    fi
}

output_result() {
    local status="$1" message="$2"
    shift 2

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        local json="{\"status\":\"$status\",\"message\":\"$message\""
        while [[ $# -gt 0 ]]; do
            json+=",\"$1\":\"$2\""
            shift 2
        done
        json+="}"
        echo "$json"
    else
        echo "$message"
        while [[ $# -gt 0 ]]; do
            echo "  $1: $2"
            shift 2
        done
    fi
}

action="${1:-help}"
shift || true

case "$action" in
    tail) log_tail "$@" ;;
    search) log_search "$@" ;;
    export) log_export "$@" ;;
    analyze) log_analyze "$@" ;;
    list|ls) log_list "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac