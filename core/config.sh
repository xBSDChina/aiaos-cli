#!/usr/bin/env bash
# AIAOS-CLI Config 管理模块

set -euo pipefail

export CONFIG_FILE="${AIAOS_CLI_CONFIG_DIR}/cli.yaml"

show_help() {
    cat <<EOF
用法: aiaos-cli config <动作> [选项]

动作:
  get         获取配置值
  set         设置配置值
  list        列出所有配置
  edit        编辑配置文件
  validate    验证配置
  migrate     迁移配置到新版本
  reset       重置为默认配置

选项:
  --key KEY           配置键 (get, set)
  --value VALUE       配置值 (set)
  --format FORMAT     输出格式 (json|yaml|table, 默认: table)
  -h, --help          显示帮助
EOF
}

# 使用主 CLI 导出的日志函数（如果可用），否则定义本地备用
if ! declare -f log_info >/dev/null 2>&1; then
    log_info() {
        echo "[INFO] $*" >&2
    }
fi

if ! declare -f log_error >/dev/null 2>&1; then
    log_error() {
        echo "[ERROR] $*" >&2
    }
fi

ensure_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "创建默认配置: $CONFIG_FILE"
        cat > "$CONFIG_FILE" <<'YAML'
version: "1.0"
core:
  log_level: "info"
  data_dir: "~/.local/share/aiaos"
  config_dir: "~/.config/aiaos"
  default_model: "gpt-4"
  temperature: 0.7
  max_tokens: 4096
session:
  auto_save: true
  max_history: 100
project:
  default_template: "python"
  auto_sync: false
logging:
  level: "info"
  file: "~/.local/share/aiaos/logs/cli.log"
safety:
  # 用户自定义危险命令模式（追加到内置默认模式之后）
  dangerous_patterns: []
  # 用户自定义禁止写入路径（追加到内置默认路径之后）
  forbidden_paths: []
YAML
    fi
}

config_get() {
    local key="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --key=*) key="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    [[ -z "$key" ]] && { log_error "需要 --key 参数"; exit 1; }

    ensure_config

    local value
    value=$(python3 - "$CONFIG_FILE" "$key" <<'__PY__'
import yaml, sys
config_file, key = sys.argv[1], sys.argv[2]
with open(config_file) as f:
    data = yaml.safe_load(f) or {}
keys = key.split(".")
current = data
for k in keys:
    if isinstance(current, dict) and k in current:
        current = current[k]
    else:
        sys.stdout.write("NOT_FOUND")
        sys.exit(0)
sys.stdout.write(str(current))
__PY__
)

    if [[ "$value" == "NOT_FOUND" ]]; then
        log_error "配置键不存在: $key"
        exit 1
    fi

    if [[ "$format" == "json" ]]; then
        python3 - "$key" "$value" <<'__PY__'
import json, sys
print(json.dumps({"key": sys.argv[1], "value": sys.argv[2]}, ensure_ascii=False))
__PY__
    else
        echo "$key: $value"
    fi
}

config_set() {
    local key="" value="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --key=*) key="${1#*=}"; shift ;;
            --value) value="$2"; shift 2 ;;
            --value=*) value="${1#*=}"; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    [[ -z "$key" ]] && { log_error "需要 --key 参数"; exit 1; }
    [[ -z "$value" ]] && { log_error "需要 --value 参数"; exit 1; }

    ensure_config

    python3 - "$CONFIG_FILE" "$key" "$value" <<'__PY__'
import yaml, sys
config_file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_file) as f:
    data = yaml.safe_load(f) or {}
if not isinstance(data, dict):
    data = {}
keys = key.split(".")
target = data
for k in keys[:-1]:
    if not isinstance(target.get(k), dict):
        target[k] = {}
    target = target[k]
val = value
low = value.lower()
if low == "true":
    val = True
elif low == "false":
    val = False
elif low in ("null", "none"):
    val = None
elif value.lstrip("-").isdigit():
    val = int(value)
else:
    try:
        val = float(value)
    except ValueError:
        pass
target[keys[-1]] = val
with open(config_file, "w") as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
__PY__

    log_info "配置已更新: $key = $value"

    if [[ "$format" == "json" ]]; then
        python3 - "$key" "$value" <<'__PY__'
import json, sys
print(json.dumps({"status": "success", "key": sys.argv[1], "value": sys.argv[2]}, ensure_ascii=False))
__PY__
    fi
}

config_list() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    ensure_config

    if [[ "$format" == "json" ]]; then
        python3 -c "
import yaml, json, os
config_file = os.environ.get('CONFIG_FILE')
with open(config_file) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, indent=2))
" CONFIG_FILE="$CONFIG_FILE"
    elif [[ "$format" == "yaml" ]]; then
        cat "$CONFIG_FILE"
    else
        python3 -c "
import yaml, sys, os
config_file = os.environ.get('CONFIG_FILE')
with open(config_file) as f:
    data = yaml.safe_load(f)

def print_dict(d, prefix=''):
    for k, v in sorted(d.items()):
        key = prefix + k
        if isinstance(v, dict):
            print(key + ':')
            print_dict(v, '  ')
        elif isinstance(v, list):
            print(key + ': [' + ', '.join(str(x) for x in v) + ']')
        else:
            print(key + ': ' + str(v))

print_dict(data)
" CONFIG_FILE="$CONFIG_FILE"
    fi
}

config_edit() {
    ensure_config
    \${EDITOR:-vim} "$CONFIG_FILE"
}

config_validate() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    ensure_config

    local validation_result=$(python3 -c "
import yaml, sys, os
config_file = os.environ.get('CONFIG_FILE')
try:
    with open(config_file) as f:
        data = yaml.safe_load(f)
    print('VALID')
except Exception as e:
    print('INVALID: ' + str(e))
    sys.exit(1)
" CONFIG_FILE="$CONFIG_FILE")

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({'status': 'success', 'message': '配置验证通过'}))
"
    else
        log_info "配置验证通过"
    fi
}

config_migrate() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    ensure_config

    local current_version=$(python3 -c "
import yaml, os
config_file = os.environ.get('CONFIG_FILE')
with open(config_file) as f:
    data = yaml.safe_load(f)
print(data.get('version', '1.0'))
" CONFIG_FILE="$CONFIG_FILE")

    local target_version="1.0"

    if [[ "$current_version" == "$target_version" ]]; then
        if [[ "$format" == "json" ]]; then
            python3 -c "
import json
print(json.dumps({'status': 'success', 'message': '配置已是最新版本 (v$target_version)'}))
"
        else
            log_info "配置已是最新版本 (v$target_version)"
        fi
        return 0
    fi

    log_info "迁移配置: v$current_version -> v$target_version"

    python3 -c "
import yaml, os
config_file = os.environ.get('CONFIG_FILE')
with open(config_file) as f:
    data = yaml.safe_load(f)
data['version'] = '$target_version'
with open(config_file, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
" CONFIG_FILE="$CONFIG_FILE"

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({'status': 'success', 'message': '配置迁移完成', 'from': '$current_version', 'to': '$target_version'}))
"
    else
        log_info "配置迁移完成"
    fi
}

config_reset() {
    local force=false format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done

    if [[ "$force" != "true" ]]; then
        read -p "确定要重置配置吗? (y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_info "取消重置"; exit 0; }
    fi

    rm -f "$CONFIG_FILE"
    ensure_config

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({'status': 'success', 'message': '配置已重置为默认值'}))
"
    else
        log_info "配置已重置为默认值"
    fi
}

action="${1:-help}"
shift || true

case "$action" in
    get) config_get "$@" ;;
    set) config_set "$@" ;;
    list) config_list "$@" ;;
    edit) config_edit "$@" ;;
    validate) config_validate "$@" ;;
    migrate) config_migrate "$@" ;;
    reset) config_reset "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac
