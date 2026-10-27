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
  -h, --help          显示帮助

示例:
  aiaos-cli agent chat --message "帮我分析这段代码"
  aiaos-cli agent delegate --task "重构用户认证模块" --agent coder
  aiaos-cli agent tool --name read_file --args '{"path": "main.py"}'
EOF
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
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$message" ]] && { log_error "需要 --message 参数"; exit 1; }
    
    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"
    
    if [[ "$format" == "json" ]]; then
        python3 -c "
import json, time
response = {
    'type': 'result',
    'session_id': '$session_id',
    'agent': '$agent_name',
    'message': '$message',
    'reply': '这是模拟回复。实际应连接到 AIAOS Agent 后端。',
    'timestamp': time.time()
}
print(json.dumps(response))
"
    else
        echo -n "🤖 [$agent_name] "
        local reply="这是模拟回复。实际应连接到 AIAOS Agent 后端。"
        for ((i=0; i<${#reply}; i++)); do
            echo -n "${reply:i:1}"
            sleep 0.02
        done
        echo
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

agent_tool() {
    local tool_name="" args="{}" session_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool_name="$2"; shift 2 ;;
            --args) args="$2"; shift 2 ;;
            --session) session_id="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$tool_name" ]] && { log_error "需要 --tool 参数"; exit 1; }
    
    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"
    
    log_info "调用工具: $tool_name"
    
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        case "$tool_name" in
            read_file)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
                if [[ -f "$path" ]]; then
                    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read()
print(json.dumps({'status': 'success', 'content': content, 'path': sys.argv[1]}, ensure_ascii=False))
" "$path"
                else
                    output_result "error" "文件不存在" "path" "$path"
                fi
                ;;
            write_file)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
                local content=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('content',''))")
                echo "$content" > "$path"
                output_result "success" "文件已写入" "path" "$path"
                ;;
            list_files)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path','.'))")
                python3 -c "
import json, os, sys
files = []
for f in os.listdir(sys.argv[1]):
    fp = os.path.join(sys.argv[1], f)
    stat = os.stat(fp)
    files.append({'name': f, 'size': stat.st_size, 'is_dir': os.path.isdir(fp)})
print(json.dumps({'status': 'success', 'path': sys.argv[1], 'files': files}, ensure_ascii=False))
" "$path"
                ;;
            execute_command)
                local cmd=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))")
                eval "$cmd" 2>&1 | python3 -c "
import json, sys
print(json.dumps({'status': 'success', 'output': sys.stdin.read()}, ensure_ascii=False))
"
                ;;
            *)
                output_result "error" "未知工具" "tool" "$tool_name"
                ;;
        esac
    else
        case "$tool_name" in
            read_file)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
                if [[ -f "$path" ]]; then
                    cat "$path"
                else
                    output_result "error" "文件不存在" "path" "$path"
                fi
                ;;
            write_file)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
                local content=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('content',''))")
                echo "$content" > "$path"
                output_result "success" "文件已写入" "path" "$path"
                ;;
            list_files)
                local path=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path','.'))")
                ls -la "$path"
                ;;
            execute_command)
                local cmd=$(echo "$args" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))")
                eval "$cmd"
                ;;
            *)
                output_result "error" "未知工具" "tool" "$tool_name"
                ;;
        esac
    fi
}

agent_history() {
    local session_id="" limit=20 format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) session_id="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --limit=*) limit="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    session_id="${session_id:-$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "default")}"
    
    local history_file="${AIAOS_CLI_DATA_DIR}/sessions/$session_id.history.jsonl"
    
    if [[ ! -f "$history_file" ]]; then
        output_result "info" "无历史记录" "session" "$session_id"
        return 0
    fi
    
    if [[ "$format" == "json" ]]; then
        echo "["
        tail -n "$limit" "$history_file" | paste -sd, -
        echo "]"
    else
        printf "%-20s %-10s %s\n" "TIMESTAMP" "ROLE" "CONTENT"
        printf "%-20s %-10s %s\n" "--------------------" "----------" "----------------------------------------"
        tail -n "$limit" "$history_file" | while IFS= read -r line; do
            printf '%s\n' "$line" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
ts = (data.get("timestamp", "") or "")[:19]
role = data.get("role", "") or ""
content = (data.get("content", "") or "")[:80]
print(f"{ts:<20} {role:<10} {content}")
'
        done
    fi
}

agent_status() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    local status="running"
    local agents=("default" "coder" "reviewer" "architect")
    local current_agent="default"
    
    if [[ "$format" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'status': '$status',
    'current_agent': '$current_agent',
    'available_agents': ['default', 'coder', 'reviewer', 'architect'],
    'session': '$(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "none")'
}))
"
    else
        echo "Agent 状态: $status"
        echo "当前 Agent: $current_agent"
        echo "可用 Agents: ${agents[*]}"
        echo "当前会话: $(cat "${AIAOS_CLI_DATA_DIR}/sessions/.current" 2>/dev/null || echo "none")"
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
    chat) agent_chat "$@" ;;
    delegate) agent_delegate "$@" ;;
    tool) agent_tool "$@" ;;
    history) agent_history "$@" ;;
    status) agent_status "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac