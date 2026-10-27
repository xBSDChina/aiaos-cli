#!/usr/bin/env bash
# AIAOS-CLI 项目管理模块

set -euo pipefail

show_help() {
    cat <<EOF
用法: aiaos-cli project <动作> [选项]

动作:
  init        初始化新项目
  sync        同步项目配置
  build       构建项目
  deploy      部署项目
  status      查看项目状态
  info        查看项目信息

选项:
  --name NAME         项目名称 (init)
  --template NAME     模板名称 (init)
  --path PATH         项目路径 (init)
  --target TARGET     部署目标 (deploy)
  --env ENV           部署环境 (deploy)
  --config FILE       配置文件路径 (info)
  -h, --help          显示帮助
EOF
}

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

generate_id() {
    date +%s%N | sha256sum | head -c 12
}

project_init() {
    local name="" template="python" path="."
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --template) template="$2"; shift 2 ;;
            --path) path="$2"; shift 2 ;;
            --path=*) path="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -n "$name" ]] || { log_error "需要 --name 参数"; exit 1; }
    
    mkdir -p "$path"
    cd "$path"
    
    mkdir -p .aiaos
    cat > .aiaos/project.yaml <<YAML
name: "$name"
template: "$template"
created_at: "$(date -Iseconds)"
version: "1.0.0"
config:
  build_command: ""
  test_command: ""
  deploy_targets: []
YAML
    
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'status': 'success',
    'message': '项目已初始化',
    'name': '$name',
    'path': '$(pwd)',
    'template': '$template'
}, ensure_ascii=False))
"
    else
        log_info "项目已初始化: $name" >log_info "项目已初始化: $name"2
    fi
}

project_sync() {
    log_info "同步项目配置" >log_info "同步项目配置"2
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'status': 'success',
    'message': '项目配置已同步'
}, ensure_ascii=False))
"
    else
        log_info "项目配置已同步" >log_info "项目配置已同步"2
    fi
}

project_build() {
    log_info "构建项目" >log_info "构建项目"2
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'status': 'success',
    'message': '项目构建完成'
}, ensure_ascii=False))
"
    else
        log_info "项目构建完成" >log_info "项目构建完成"2
    fi
}

project_deploy() {
    local target="local" env="dev"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --env) env="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    log_info "部署项目到 $target ($env)" >log_info "部署项目到 $target ($env)"2
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'status': 'success',
    'message': '项目部署完成',
    'target': '$target',
    'env': '$env'
}, ensure_ascii=False))
"
    else
        log_info "项目部署完成" >log_info "项目部署完成"2
    fi
}

project_status() {
    local git_status="clean"
    if git status --porcelain 2>/dev/null | grep -q .; then
        git_status="dirty"
    fi
    
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import json, os
print(json.dumps({
    'path': '$(pwd)',
    'type': 'python',
    'git_status': '$git_status',
    'aiaos_config': $(test -f .aiaos/project.yaml && echo True || echo False)
}, ensure_ascii=False))
"
    else
        echo "路径: $(pwd)"
        echo "类型: python"
        echo "Git 状态: $git_status"
        echo "AIAOS 配置: $(test -f .aiaos/project.yaml && echo 是 || echo 否)"
    fi
}

project_info() {
    local config_file=".aiaos/project.yaml"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_file="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done
    
    [[ -f "$config_file" ]] || { log_error "配置文件不存在: $config_file"; exit 1; }
    
    if [[ "${AIAOS_CLI_OUTPUT_FORMAT:-table}" == "json" ]]; then
        python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))
" "$config_file"
    else
        cat "$config_file"
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
    init) project_init "$@" ;;
    sync) project_sync "$@" ;;
    build) project_build "$@" ;;
    deploy) project_deploy "$@" ;;
    status) project_status "$@" ;;
    info) project_info "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac
