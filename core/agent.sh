#!/usr/bin/env bash
# AIAOS-CLI Agent 交互模块

set -euo pipefail

show_help() {
    cat <<EOF
用法: aiaos-cli agent <动作> [选项]

动作:
  chat        与 Agent 对话
  delegate    委托任务给 Agent
  tool        调用 Agent 工具
  history     查看对话历史
  status      查看 Agent 状态

选项:
  --message MSG       对话消息 (chat)
  --session ID        会话 ID
  --agent NAME        Agent 名称
  --task DESC         任务描述 (delegate)
  --tool NAME         工具名称 (tool)
  --args JSON         工具参数 JSON (tool)
  --limit N           历史条数限制 (history, 默认: 20)
  --format FORMAT     输出格式 (json|table|stream, 默认: stream)
  --allow-dangerous   显式授权执行危险命令/写入受限路径 (tool)
  -h, --help          显示帮助

示例:
  aiaos-cli agent chat --message "帮我分析这段代码"
  aiaos-cli agent delegate --task "重构用户认证模块" --agent coder
  aiaos-cli agent tool --tool read_file --args '{"path": "main.py"}'
EOF
}

# 安全检查：从配置文件加载危险命令模式（R4001）
# 内置默认模式始终生效，用户可通过 cli.yaml 的 safety.dangerous_patterns 追加自定义模式
_load_safety_config() {
    if [[ -n "${SAFETY_PATTERNS:-}" ]]; then
        return 0
    fi
    # 内置默认危险命令模式（始终生效，不可移除）
    local builtin_dangerous='rm\s+-rf?\s+/|dd\s+if=|mkfs|:\(\)\s*\{|>\s*/dev/sd|chmod\s+-R\s+777\s+/|curl.*\|.*bash|wget.*\|.*sh'
    # 内置默认禁止写入路径（始终生效，不可移除）
    local builtin_forbidden='/etc/|/bin/|/sbin/|/usr/|/boot/|/sys/|/proc/'
    
    local config_file="${AIAOS_CLI_CONFIG_DIR:-$HOME/.config/aiaos}/cli.yaml"
    
    if [[ -f "$config_file" ]]; then
        local result
        result=$(python3 -c "
import yaml, sys
builtin_d = r'rm\s+-rf?\s+/|dd\s+if=|mkfs|:\(\)\s*\{|>\s*/dev/sd|chmod\s+-R\s+777\s+/|curl.*\|.*bash|wget.*\|.*sh'
builtin_f = r'/etc/|/bin/|/sbin/|/usr/|/boot/|/sys/|/proc/'
try:
    with open(sys.argv[1]) as f:
        cfg = yaml.safe_load(f) or {}
    safety = cfg.get('safety', {})
    user_d = safety.get('dangerous_patterns', [])
    user_f = safety.get('forbidden_paths', [])
    combined_d = builtin_d
    if user_d:
        combined_d += '|' + '|'.join(user_d)
    combined_f = builtin_f
    if user_f:
        combined_f += '|' + '|'.join(user_f)
    print(combined_d + '||' + combined_f)
except Exception:
    print(builtin_d + '||' + builtin_f)
" "$config_file" 2>/dev/null) || result=""
        
        if [[ -n "$result" ]]; then
            SAFETY_PATTERNS="${result%%||*}"
            SAFETY_FORBIDDEN="${result#*||}"
        else
            SAFETY_PATTERNS="$builtin_dangerous"
            SAFETY_FORBIDDEN="$builtin_forbidden"
        fi
    # R4003: 加载白名单模式（allowed_paths 为空时不启用）
    ALLOWED_PATHS=""
    if [[ -f "$config_file" ]]; then
        local allowed
        allowed=$(python3 -c "
import yaml, sys
try:
    with open(sys.argv[1]) as f:
        cfg = yaml.safe_load(f) or {}
    safety = cfg.get('safety', {})
    ap = safety.get('allowed_paths', [])
    if isinstance(ap, list) and ap:
        print('|'.join(ap))
    else:
        print('')
except Exception:
    print('')
" "$config_file" 2>/dev/null) || allowed=""
        if [[ -n "$allowed" ]]; then
            ALLOWED_PATHS="$allowed"
        fi
    fi
    else
        SAFETY_PATTERNS="$builtin_dangerous"
        SAFETY_FORBIDDEN="$builtin_forbidden"
    fi
}

# R4004: 审计日志 — 记录工具调用的关键操作
_audit_log() {
    local tool="$1" detail="$2" session="$3" status="$4" allow_dangerous="$5"
    local audit_file="${AIAOS_CLI_DATA_DIR}/logs/audit.log"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local msg_escaped=$(python3 -c "import json; print(json.dumps(json.loads('"'+'"'.join('"$detail"'.replace('\\','\\\\')))))" 2>/dev/null || echo '"'"$detail"'"')
    # 简化：直接构造 JSON Lines
    local entry
    entry=$(python3 -c "
import json, sys
entry = {
    'tool': sys.argv[1],
    'detail': sys.argv[2],
    'session': sys.argv[3],
    'status': sys.argv[4],
    'allow_dangerous': sys.argv[5] == 'true',
    'timestamp': sys.argv[6]
}
print(json.dumps(entry))
" "$tool" "$detail" "$session" "$status" "$allow_dangerous" "$timestamp")
    echo "$entry" >> "$audit_file"
}

# 安全检查：检测危险命令（支持用户自定义模式）
check_dangerous_command() {
    local cmd="$1"
    _load_safety_config
    if echo "$cmd" | grep -qE "$SAFETY_PATTERNS"; then
        log_error "检测到危险命令，已拒绝执行"
        log_warn "禁止的命令模式: $SAFETY_PATTERNS"
        return 1
    fi
    return 0
}

# 安全检查：验证写入路径（支持用户自定义禁止路径）
validate_write_path() {
    local path="$1"
    _load_safety_config
    # R4003: 白名单模式 — 配置了 allowed_paths 时，路径必须在白名单内
    if [[ -n "$ALLOWED_PATHS" ]]; then
        local in_whitelist=false
        IFS='|' read -ra WHITELIST <<< "$ALLOWED_PATHS"
        for wl in "${WHITELIST[@]}"; do
            # 规范化：去除尾部斜杠
            wl_clean="${wl%/}"
            # 匹配逻辑：
            # 1. 精确匹配：path == wl_clean
            # 2. 目录匹配：path 以 wl_clean/ 开头
            # 3. 通配符匹配：wl 包含 * 时用 glob
            if [[ "$wl" == *"*"* ]]; then
                if [[ "$path" == $wl ]]; then
                    in_whitelist=true
                    break
                fi
            elif [[ "$path" == "$wl_clean" ]] || [[ "$path" == "$wl_clean"/* ]]; then
                in_whitelist=true
                break
            fi
        done
        if [[ "$in_whitelist" == false ]]; then
            log_error "路径不在白名单内"
            log_warn "白名单: $ALLOWED_PATHS"
            log_warn "尝试写入: $path"
            return 1
        fi
    fi
    # 黑名单模式 — 即使在白名单内，系统关键目录仍禁止
    if echo "$path" | grep -qE "$SAFETY_FORBIDDEN"; then
        log_error "禁止写入系统关键目录"
        log_warn "受限路径: $path"
        return 1
    fi
    return 0
}

output_result() {
    local status="$1" message="$2"
    shift 2

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        local json='{"status":"'$status'","message":"'$message'"'
        while [[ $# -gt 0 ]]; do
            json+=',"'$1'":"'$2'"'
            shift 2
        done
        json+='}'
        echo "$json"
    else
        echo "$message"
        while [[ $# -gt 0 ]]; do
            echo "  $1: $2"
            shift 2
        done
    fi
}

agent_chat() {
    local message="" session_id="" agent_name="default" format="${AIAOS_CLI_OUTPUT_FORMAT:-stream}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message) message="$2"; shift 2 ;;
            --message=*) message="${1#*=}"; shift ;;
            --session) session_id="$2"; shift 2 ;;
            --agent) agent_name="$2"; shift 2 ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            *) shift ;;
        esac
    done

    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"

    # 优先尝试真实 LLM（通过桥接脚本），失败则优雅降级到模拟回复
    local bridge_reply=""
    local bridge_err=""
    if [[ -f "${HOME}/.config/aiaos/agent_llm_bridge.py" ]]; then
        bridge_reply=$(python3 "${HOME}/.config/aiaos/agent_llm_bridge.py" --message "$message" --agent "$agent_name" --session "$session_id" 2>/dev/null || true)
    fi

    local real_reply=""
    if [[ -n "$bridge_reply" ]]; then
        # 解析 JSON 中的 reply 字段
        real_reply=$(echo "$bridge_reply" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if data.get('reply'):
        print(data['reply'])
except Exception:
    pass
" 2>/dev/null)
    fi

    if [[ -n "$real_reply" ]]; then
        if [[ "$format" == "json" ]]; then
            python3 -c "
import json, time, sys
response = {
    'type': 'result',
    'session_id': sys.argv[1],
    'agent': sys.argv[2],
    'message': sys.argv[3],
    'reply': sys.argv[4],
    'timestamp': time.time()
}
print(json.dumps(response))
" "$session_id" "$agent_name" "$message" "$real_reply"
        else
            echo -n "🤖 [$agent_name] "
            for ((i=0; i<${#real_reply}; i++)); do
                echo -n "${real_reply:i:1}"
                sleep 0.01
            done
            echo
        fi
    else
        # 降级：模拟回复（无真实凭据时不崩溃）
        if [[ "$format" == "json" ]]; then
            python3 -c "
import json, time, sys
response = {
    'type': 'result',
    'session_id': sys.argv[1],
    'agent': sys.argv[2],
    'message': sys.argv[3],
    'reply': '（模拟回复）当前未配置可用的 LLM API 凭据，无法连接真实后端。',
    'timestamp': time.time()
}
print(json.dumps(response))
" "$session_id" "$agent_name" "$message"
        else
            echo -n "🤖 [$agent_name] "
            local reply="（模拟回复）当前未配置可用的 LLM API 凭据，无法连接真实后端。"
            for ((i=0; i<${#reply}; i++)); do
                echo -n "${reply:i:1}"
                sleep 0.02
            done
            echo
        fi
    fi
}


agent_delegate() {
    local task="" session_id="" agent_name="default"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task) task="$2"; shift 2 ;;
            --session) session_id="$2"; shift 2 ;;
            --agent) agent_name="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$task" ]] && { log_error "需要 --task 参数"; exit 1; }

    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"

    log_info "委托任务给 Agent [$agent_name]: $task"

    local task_id="task-$(date +%s)-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d " \n")"

    output_result "success" "任务已委托" "task_id" "$task_id" "agent" "$agent_name" "session" "$session_id"
}

# 统一工具调用逻辑 — 消除 JSON/table 格式重复
agent_tool_read_file() {
    local path="$1" format="$2"
    if [[ ! -f "$path" ]]; then
        if [[ "$format" == "json" ]]; then
            output_result "error" "文件不存在" "path" "$path"
        else
            echo "错误: 文件不存在: $path" >&2
            return 1
        fi
        return 1
    fi
    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read()
print(json.dumps({'status': 'success', 'content': content, 'path': sys.argv[1]}, ensure_ascii=False))
" "$path"
    else
        cat "$path"
    fi
}

agent_tool_write_file() {
    local path="$1" content="$2" format="$3" allow_dangerous="${4:-}"
    if [[ "$allow_dangerous" != "true" ]] && ! validate_write_path "$path"; then
        if [[ "$format" == "json" ]]; then
            output_result "error" "路径受限" "path" "$path"
        fi
        # R4004: 审计日志 — 记录文件写入拦截
        _audit_log "write_file" "$path" "$session_id" "denied" "$allow_dangerous"
        return 1
    fi
    mkdir -p "$(dirname "$path")" 2>/dev/null || true
    echo "$content" > "$path"
    # R4004: 审计日志 — 记录文件写入
    _audit_log "write_file" "$path" "$session_id" "success" "$allow_dangerous"
    if [[ "$format" == "json" ]]; then
        output_result "success" "文件已写入" "path" "$path"
    else
        echo "✓ 文件已写入: $path"
    fi
}

agent_tool_list_files() {
    local path="$1" format="$2"
    path="${path:-.}"
    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, os, sys
files = []
for f in os.listdir(sys.argv[1]):
    fp = os.path.join(sys.argv[1], f)
    stat = os.stat(fp)
    files.append({'name': f, 'size': stat.st_size, 'is_dir': os.path.isdir(fp)})
print(json.dumps({'status': 'success', 'path': sys.argv[1], 'files': files}, ensure_ascii=False))
" "$path"
    else
        ls -la "$path"
    fi
}

agent_tool_execute_command() {
    local cmd="$1" format="$2" allow_dangerous="${3:-}"
    if [[ "$allow_dangerous" != "true" ]] && ! check_dangerous_command "$cmd"; then
        if [[ "$format" == "json" ]]; then
            output_result "error" "危险命令已拒绝" "command" "$cmd"
        fi
        return 1
    fi
    if [[ "$format" == "json" ]]; then
        bash -c "$cmd" 2>&1 | python3 -c "
import json, sys
print(json.dumps({'status': 'success', 'output': sys.stdin.read()}, ensure_ascii=False))
"
    else
        bash -c "$cmd"
    fi
}

agent_tool() {
    local tool_name="" args="{}" session_id="" allow_dangerous=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool_name="$2"; shift 2 ;;
            --args) args="$2"; shift 2 ;;
            --session) session_id="$2"; shift 2 ;;
            --allow-dangerous) allow_dangerous="true"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$tool_name" ]] && { log_error "需要 --tool 参数"; exit 1; }

    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"

    log_info "调用工具: $tool_name"

    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    local status="success"
    local result=""

    case "$tool_name" in
        read_file)
            local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
            agent_tool_read_file "$path" "$format" || status="error"
            ;;
        write_file)
            local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
            local content=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('content',''))")
            agent_tool_write_file "$path" "$content" "$format" "$allow_dangerous" || status="error"
            ;;
        list_files)
            local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path','.'))")
            agent_tool_list_files "$path" "$format" || status="error"
            ;;
        execute_command)
            local cmd=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))")
            agent_tool_execute_command "$cmd" "$format" "$allow_dangerous" || status="error"
            ;;
        *)
            if [[ "$format" == "json" ]]; then
                output_result "error" "未知工具" "tool" "$tool_name"
            else
                echo "错误: 未知工具: $tool_name" >&2
            fi
            status="error"
            ;;
    esac
}

agent_history() {
    local session_id="" limit=20 format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) session_id="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"
    local history_file="${AIAOS_CLI_DATA_DIR}/sessions/${session_id}.history"

    if [[ ! -f "$history_file" ]]; then
        if [[ "$format" == "json" ]]; then
            echo '{"status":"ok","data":{"history":[],"count":0}}'
        else
            echo "（无对话历史）"
        fi
        return 0
    fi

    # 使用 timeout 限制读取行数，防止大文件
    local entries
    entries=$(timeout 5 tail -n "$limit" "$history_file" 2>/dev/null || true)

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, sys
entries = sys.stdin.read().strip().split('\n') if sys.stdin else []
entries = [e for e in entries if e]
print(json.dumps({'status':'ok','data':{'history':entries,'count':len(entries)}}, ensure_ascii=False))
" <<< "$entries"
    else
        echo "$entries"
    fi
}

agent_status() {
    local session_id="${AIAOS_CLI_DATA_DIR}/sessions/.current"
    session_id=$(cat "$session_id" 2>/dev/null || echo "default")

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        local history_count=0
        local history_file="${AIAOS_CLI_DATA_DIR}/sessions/${session_id}.history"
        if [[ -f "$history_file" ]]; then
            history_count=$(wc -l < "$history_file")
        fi
        output_result "success" "Agent 状态" \
            "session_id" "$session_id" \
            "status" "active" \
            "history_count" "$history_count"
    else
        echo "AIAOS-CLI Agent 状态"
        echo "===================="
        echo "会话: $session_id"
        echo "状态: active"
    fi
}

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        chat) agent_chat "$@" ;;
        delegate) agent_delegate "$@" ;;
        tool) agent_tool "$@" ;;
        history) agent_history "$@" ;;
        status) agent_status "$@" ;;
        ""|-h|--help) show_help ;;
        *) log_error "未知动作: $action"; show_help; exit 1 ;;
    esac
}

main "$@"
