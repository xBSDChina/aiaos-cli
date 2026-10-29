#!/usr/bin/env bash
# AIAOS-CLI Context 管理模块

set -euo pipefail

# 上下文目录
CONTEXT_DIR="${AIAOS_CLI_DATA_DIR}/contexts"
mkdir -p "$CONTEXT_DIR"

generate_context_id() {
    echo "ctx-$(date +%s)-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d " \n")"
}

get_current_session() {
    local session_file="${AIAOS_CLI_DATA_DIR}/sessions/.current"
    [[ -f "$session_file" ]] && cat "$session_file" || echo ""
}

capture_context() {
    python3 << 'PYEOF'
import json, os, subprocess, sys

ctx = {}

# 基础环境信息
ctx['cwd'] = os.getcwd()
ctx['user'] = os.environ.get('USER', '')
ctx['hostname'] = os.uname().nodename
from datetime import datetime
ctx['timestamp'] = datetime.now().isoformat()
ctx['shell'] = os.environ.get('SHELL', '')
ctx['term'] = os.environ.get('TERM', 'unknown')

# Git 信息
try:
    git_dir = subprocess.run(['git', 'rev-parse', '--git-dir'], capture_output=True, text=True, timeout=2)
    if git_dir.returncode == 0:
        ctx['git_root'] = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True, timeout=2).stdout.strip()
        ctx['git_branch'] = subprocess.run(['git', 'branch', '--show-current'], capture_output=True, text=True, timeout=2).stdout.strip()
        ctx['git_status'] = subprocess.run(['git', 'status', '--short'], capture_output=True, text=True, timeout=2).stdout.strip()
except:
    pass

# 项目类型检测
project_types = []
for f in ['package.json', 'Cargo.toml', 'go.mod', 'Makefile', 'pyproject.toml', 'pom.xml', 'build.gradle']:
    if os.path.exists(f):
        project_types.append(f.replace('.', '_'))
if project_types:
    ctx['project_type'] = ','.join(project_types)

# 环境变量（过滤敏感信息）
safe_env = {}
for var in ['PATH', 'HOME', 'USER', 'LANG', 'LC_ALL', 'TERM', 'EDITOR', 'VISUAL', 'PAGER']:
    if var in os.environ:
        safe_env[var] = os.environ[var]
ctx['env'] = safe_env

# 当前会话
current_session = ''
session_file = os.path.join(os.environ.get('AIAOS_CLI_DATA_DIR', os.path.expanduser('~/.local/share/aiaos')), 'sessions', '.current')
if os.path.exists(session_file):
    with open(session_file) as f:
        current_session = f.read().strip()
if current_session:
    ctx['session'] = current_session

print(json.dumps(ctx))
PYEOF
}

show_help() {
    cat <<EOF
用法: aiaos-cli context <动作> [选项]

动作:
  show        显示当前上下文
  save        保存上下文
  load        加载上下文
  clear       清除上下文
  list        列出所有上下文
  export      导出上下文
  import      导入上下文

选项:
  --id ID           上下文 ID
  --name NAME       上下文名称
  --session ID      关联会话 ID
  --format FORMAT   输出格式 (json, yaml, table)
  -h, --help        显示帮助
EOF
}

context_show() {
    local context_id="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                context_id="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -n "$context_id" ]]; then
        local context_file="$CONTEXT_DIR/$context_id.yaml"
        [[ -f "$context_file" ]] || { log_error "上下文不存在: $context_id"; exit 1; }

        if [[ "$format" == "json" ]]; then
            python3 -c '
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ctx = data.get("context", data)
print(json.dumps(ctx, indent=2, ensure_ascii=False))
' "$context_file"
        elif [[ "$format" == "yaml" ]]; then
            cat "$context_file"
        else
            python3 -c '
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ctx = data.get("context", data)
for k, v in sorted(ctx.items()):
    if isinstance(v, dict):
        print(k + ":")
        for k2, v2 in sorted(v.items()):
            print("  " + k2 + ": " + str(v2))
    else:
        print(k + ": " + str(v))
' "$context_file"
        fi
    else
        local ctx_json=$(capture_context)

        if [[ "$format" == "json" ]]; then
            echo "$ctx_json" | python3 -m json.tool
        elif [[ "$format" == "yaml" ]]; then
            python3 -c '
import json, yaml, sys
print(yaml.dump(json.load(sys.stdin), default_flow_style=False, allow_unicode=True))
' <<< "$ctx_json"
        else
            python3 -c '
import json, sys
ctx = json.load(sys.stdin)
for k, v in sorted(ctx.items()):
    if isinstance(v, dict):
        print(k + ":")
        for k2, v2 in sorted(v.items()):
            print("  " + k2 + ": " + str(v2))
    else:
        print(k + ": " + str(v))
' <<< "$ctx_json"
        fi
    fi
}

context_save() {
    local name="" session_id="" context_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --session) session_id="$2"; shift 2 ;;
            --id) context_id="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    context_id="${context_id:-$(generate_context_id)}"
    name="${name:-context-$(date +%s)}"
    session_id="${session_id:-$(get_current_session)}"

    [[ -n "$session_id" ]] || { log_error "无当前会话，请指定 --session"; exit 1; }

    local context_file="$CONTEXT_DIR/$context_id.yaml"

    local ctx_json=$(capture_context)
    python3 -c "
import yaml, json, sys
data = json.load(sys.stdin)
data['id'] = sys.argv[1]
data['name'] = sys.argv[2]
data['session'] = sys.argv[3]
from datetime import datetime
data['created_at'] = datetime.now().isoformat()
data['updated_at'] = datetime.now().isoformat()
with open(sys.argv[4], 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
" "$context_id" "$name" "$session_id" "$context_file" <<< "$ctx_json"

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))" "$context_file"
    else
        log_info "上下文保存成功"
        log_info "  id: $context_id"
        log_info "  name: $name"
        log_info "  session: $session_id"
    fi
}

context_load() {
    local context_id="" context_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                context_id="$2"
                shift 2
                ;;
            --name)
                context_name="$2"
                shift 2
                ;;
            --name=*)
                context_name="${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -n "$context_name" ]]; then
        # Search for context by name
        local found_id=""
        for f in "$CONTEXT_DIR"/*.yaml; do
            [[ -f "$f" ]] || continue
            local fname=$(python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d.get('name',''))" "$f" 2>/dev/null)
            if [[ "$fname" == "$context_name" ]]; then
                found_id=$(basename "$f" .yaml)
                break
            fi
        done
        if [[ -z "$found_id" ]]; then
            log_error "未找到名称为 '$context_name' 的上下文"
            exit 1
        fi
        context_id="$found_id"
    fi

    [[ -n "$context_id" ]] || { log_error "需要 --id 或 --name 参数"; exit 1; }

    local context_file="$CONTEXT_DIR/$context_id.yaml"
    [[ -f "$context_file" ]] || { log_error "上下文不存在: $context_id"; exit 1; }

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c '
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))' "$context_file"
    else
        CONTEXT_FILE="$context_file" python3 -c '
import yaml, os, sys
with open(os.environ["CONTEXT_FILE"]) as f:
    data = yaml.safe_load(f)
ctx = data.get("context", data)
for k, v in ctx.items():
    if isinstance(v, dict):
        for k2, v2 in v.items():
            val = str(v2).replace(chr(34), chr(92)+chr(34))
            print("export AIAOS_CTX_" + k.upper() + "_" + k2.upper() + "=" + chr(34) + val + chr(34))
    else:
        val = str(v).replace(chr(34), chr(92)+chr(34))
        print("export AIAOS_CTX_" + k.upper() + "=" + chr(34) + val + chr(34))
'
        log_info "上下文已加载，请执行上述 export 命令"
    fi
}

context_clear() {
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c '
import os, json
unset_vars = [k for k in os.environ.keys() if k.startswith("AIAOS_CTX_")]
for k in unset_vars:
    print("unset " + k)
print(json.dumps({"status": "success", "message": "上下文环境变量已清除", "unset_count": len(unset_vars)}, ensure_ascii=False))'
    else
        log_info "清除当前上下文环境变量"
        python3 -c '
import os
for k in list(os.environ.keys()):
    if k.startswith("AIAOS_CTX_"):
        print("unset " + k)'
    fi
}

context_list() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    local context_files=()

    for file in "$CONTEXT_DIR"/*.yaml; do
        [[ -f "$file" ]] || continue
        context_files+=("$file")
    done

    if [[ "$format" == "json" ]]; then
        python3 -c '
import yaml, json, sys
files = sys.argv[1:]
results = []
for f in files:
    with open(f) as fp:
        data = yaml.safe_load(fp)
    results.append({
        "id": data.get("id", ""),
        "name": data.get("name", ""),
        "session": data.get("session", ""),
        "created_at": data.get("created_at", "")
    })
print(json.dumps(results, ensure_ascii=False))' "${context_files[@]}"
    else
        printf "%-30s %-30s %-30s %s\n" "ID" "名称" "会话" "创建时间"
        for file in "${context_files[@]}"; do
            python3 -c '
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(data.get("id", "") + "|" + data.get("name", "") + "|" + data.get("session", "") + "|" + data.get("created_at", ""))' "$file" | while IFS="|" read -r id name session created_at; do
                printf "%-30s %-30s %-30s %s\n" "$id" "$name" "$session" "$created_at"
            done
        done
    fi
}

context_export() {
    local context_id="" output_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) context_id="$2"; shift 2 ;;
            --output) output_file="$2"; shift 2 ;;
            --file) output_file="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -n "$context_id" ]] || { log_error "需要 --id 参数"; exit 1; }
    [[ -n "$output_file" ]] || { log_error "需要 --output 参数"; exit 1; }

    local context_file="$CONTEXT_DIR/$context_id.yaml"
    [[ -f "$context_file" ]] || { log_error "上下文不存在: $context_id"; exit 1; }

    cp "$context_file" "$output_file"

    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c '
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps({"status": "success", "message": "上下文已导出到: " + sys.argv[2], "file": sys.argv[2]}, ensure_ascii=False))' "$context_file" "$output_file"
    else
        log_info "上下文已导出到: $output_file"
    fi
}

context_import() {
    local input_file="" context_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) input_file="$2"; shift 2 ;;
            --id) context_id="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -n "$input_file" ]] || { log_error "需要 --file 参数"; exit 1; }
    [[ -f "$input_file" ]] || { log_error "文件不存在: $input_file"; exit 1; }

    context_id="${context_id:-$(generate_context_id)}"
    local context_file="$CONTEXT_DIR/$context_id.yaml"

    # 复制文件并更新内部 id 字段
    python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
data['id'] = sys.argv[2]
data['name'] = data.get('name', 'imported-context')
with open(sys.argv[3], 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
" "$input_file" "$context_id" "$context_file"

    log_info "上下文已导入: $context_id"
}

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        show)
            context_show "$@"
            ;;
        save)
            context_save "$@"
            ;;
        load)
            context_load "$@"
            ;;
        clear)
            context_clear "$@"
            ;;
        list|ls)
            context_list "$@"
            ;;
        export)
            context_export "$@"
            ;;
        import)
            context_import "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知动作: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
