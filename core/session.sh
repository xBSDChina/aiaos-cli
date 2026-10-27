#!/usr/bin/env bash
# AIAOS-CLI Session 管理模块

set -euo pipefail

# 会话数据目录
SESSION_DIR="${AIAOS_CLI_DATA_DIR}/sessions"
mkdir -p "$SESSION_DIR"

show_help() {
    cat <<EOF
用法: aiaos-cli session <动作> [选项]

动作:
  new         创建新会话
  list        列出所有会话
  show        显示会话详情
  switch      切换当前会话
  archive     归档会话
  delete      删除会话
  current     显示当前会话

选项:
  --name NAME         会话名称 (new)
  --id ID             会话 ID (show, switch, archive, delete)
  --project PATH      关联项目路径 (new)
  --description TEXT  会话描述 (new)
  --format FORMAT     输出格式 (json|table, 默认: table)
  -h, --help          显示帮助

示例:
  aiaos-cli session new --name "feature-x" --project ~/my-project
  aiaos-cli session list
  aiaos-cli session show --id sess-abc123
  aiaos-cli session switch --id sess-abc123
EOF
}

generate_session_id() {
    echo "sess-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d " \n")"
}

session_new() {
    local name="" project="" description="" session_id="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --project) project="$2"; shift 2 ;;
            --project=*) project="${1#*=}"; shift ;;
            --description) description="$2"; shift 2 ;;
            --description=*) description="${1#*=}"; shift ;;
            --id) session_id="$2"; shift 2 ;;
            --id=*) session_id="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    session_id="${session_id:-$(generate_session_id)}"
    name="${name:-session-$(date +%H%M%S)}"
    project="${project:-$PWD}"
    description="${description:-}"
    
    local session_file="$SESSION_DIR/$session_id.yaml"
    local created_at=$(date -Iseconds)
    
    cat > "$session_file" <<EOF
id: "$session_id"
name: "$name"
project: "$project"
description: "$description"
created_at: "$created_at"
updated_at: "$created_at"
status: "active"
context: {}
history: []
EOF
    
    # 设置为当前会话
    echo "$session_id" > "$SESSION_DIR/.current"
    
    if [[ "$format" == "json" ]]; then
        printf '{"status":"success","message":"会话创建成功","id":"%s","name":"%s","project":"%s"}\n' \
            "$session_id" "$name" "$project"
    else
        output_result "success" "会话创建成功" "id" "$session_id" "name" "$name" "project" "$project"
    fi
}

session_list() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    local sessions=()
    
    for file in "$SESSION_DIR"/*.yaml; do
        [[ -f "$file" ]] || continue
        local id name project status created_at
        id=$(grep '^id:' "$file" | cut -d'"' -f2)
        name=$(grep '^name:' "$file" | cut -d'"' -f2)
        project=$(grep '^project:' "$file" | cut -d'"' -f2)
        status=$(grep '^status:' "$file" | cut -d'"' -f2)
        created_at=$(grep '^created_at:' "$file" | cut -d'"' -f2)
        sessions+=("$id|$name|$project|$status|$created_at")
    done
    
    if [[ "$format" == "json" ]]; then
        local json="["
        local first=true
        for s in "${sessions[@]}"; do
            IFS='|' read -r id name project status created_at <<< "$s"
            [[ "$first" == true ]] && first=false || json+=","
            json+="{\"id\":\"$id\",\"name\":\"$name\",\"project\":\"$project\",\"status\":\"$status\",\"created_at\":\"$created_at\"}"
        done
        json+="]"
        echo "$json"
    else
        printf "%-20s %-30s %-40s %-10s %s\n" "ID" "NAME" "PROJECT" "STATUS" "CREATED"
        printf "%-20s %-30s %-40s %-10s %s\n" "--------------------" "------------------------------" "----------------------------------------" "----------" "-------------------"
        for s in "${sessions[@]}"; do
            IFS='|' read -r id name project status created_at <<< "$s"
            local current_marker=" "
            [[ -f "$SESSION_DIR/.current" ]] && [[ "$(cat "$SESSION_DIR/.current")" == "$id" ]] && current_marker="*"
            printf "%-20s %-30s %-40s %-10s %s\n" "$current_marker$id" "$name" "$project" "$status" "$created_at"
        done
    fi
}

session_show() {
    local session_id="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) session_id="$2"; shift 2 ;;
            --id=*) session_id="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$session_id" ]] && { log_error "需要 --id 参数"; exit 1; }
    
    local session_file="$SESSION_DIR/$session_id.yaml"
    [[ -f "$session_file" ]] || { log_error "会话不存在: $session_id"; exit 1; }
    
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        # Convert YAML to JSON
        python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))" "$session_file"
    else
        cat "$session_file"
    fi
}

session_switch() {
    local session_id="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) session_id="$2"; shift 2 ;;
            --id=*) session_id="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$session_id" ]] && { log_error "需要 --id 参数"; exit 1; }
    
    local session_file="$SESSION_DIR/$session_id.yaml"
    [[ -f "$session_file" ]] || { log_error "会话不存在: $session_id"; exit 1; }
    
    echo "$session_id" > "$SESSION_DIR/.current"
    
    sed -i 's/^status:.*/status: "active"/' "$session_file"
    sed -i "s/^updated_at:.*/updated_at: \"$(date -Iseconds)\"/" "$session_file"
    
    output_result "success" "已切换到会话" "id" "$session_id"
}

session_archive() {
    local session_id="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) session_id="$2"; shift 2 ;;
            --id=*) session_id="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$session_id" ]] && { log_error "需要 --id 参数"; exit 1; }
    
    local session_file="$SESSION_DIR/$session_id.yaml"
    [[ -f "$session_file" ]] || { log_error "会话不存在: $session_id"; exit 1; }
    
    sed -i 's/^status:.*/status: "archived"/' "$session_file"
    sed -i "s/^updated_at:.*/updated_at: \"$(date -Iseconds)\"/" "$session_file"
    
    [[ -f "$SESSION_DIR/.current" ]] && [[ "$(cat "$SESSION_DIR/.current")" == "$session_id" ]] && rm "$SESSION_DIR/.current"
    
    output_result "success" "会话已归档" "id" "$session_id"
}

session_delete() {
    local session_id="" force=false format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) session_id="$2"; shift 2 ;;
            --id=*) session_id="${1#*=}"; shift ;;
            --force) force=true; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -z "$session_id" ]] && { log_error "需要 --id 参数"; exit 1; }
    
    local session_file="$SESSION_DIR/$session_id.yaml"
    [[ -f "$session_file" ]] || { log_error "会话不存在: $session_id"; exit 1; }
    
    if [[ "$force" != true ]]; then
        read -p "确定删除会话 $session_id? (y/N) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "取消删除"; exit 0; }
    fi
    
    rm "$session_file"
    
    [[ -f "$SESSION_DIR/.current" ]] && [[ "$(cat "$SESSION_DIR/.current")" == "$session_id" ]] && rm "$SESSION_DIR/.current"
    
    output_result "success" "会话已删除" "id" "$session_id"
}

session_current() {
    if [[ -f "$SESSION_DIR/.current" ]]; then
        local current_id=$(cat "$SESSION_DIR/.current")
        local session_file="$SESSION_DIR/$current_id.yaml"
        if [[ -f "$session_file" ]]; then
            if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
                # Convert YAML to JSON
                python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))" "$session_file"
            else
                cat "$session_file"
            fi
        else
            output_result "error" "当前会话文件丢失: $current_id" "code" "SESSION_FILE_MISSING"
        fi
    else
        output_result "error" "无当前会话" "code" "NO_CURRENT_SESSION"
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

# 主入口
action="${1:-help}"
shift || true

case "$action" in
    new) session_new "$@" ;;
    list|ls) session_list "$@" ;;
    show) session_show "$@" ;;
    switch) session_switch "$@" ;;
    archive) session_archive "$@" ;;
    delete|rm) session_delete "$@" ;;
    current) session_current "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac