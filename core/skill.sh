#!/usr/bin/env bash
# AIAOS-CLI Skill 管理模块

set -euo pipefail

# 技能目录
SKILL_DIRS=(
    "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../skills"
    "/usr/share/aiaos/skills"
    "${AIAOS_CLI_CONFIG_DIR:-$HOME/.config/aiaos}/skills"
)

if [[ -n "${AIAOS_PROJECT_ROOT:-}" && -d "$AIAOS_PROJECT_ROOT/.aiaos/skills" ]]; then
    SKILL_DIRS+=("$AIAOS_PROJECT_ROOT/.aiaos/skills")
fi

# 判断是否为内置技能目录（规范化路径后匹配，避免 core/../ 未解析路径误判）
# R4301: 修复 R4300 路径匹配漏洞 — SKILL_DIRS 首元素为未解析的 .../core/../skills，
# 直接用字符串匹配 *aiaos-cli/skills* 会失败，导致内置技能被误删
is_builtin_skill_dir() {
    local dir
    dir="$(readlink -f "$1" 2>/dev/null || echo "$1")"
    [[ "$dir" == *aiaos-cli/skills* ]]
}

show_help() {
    cat <<EOF
用法: aiaos-cli skill <动作> [选项]

动作:
  create      创建技能骨架 (--name --command [--output-dir] [--force])
  list        列出所有可用技能
  info        显示技能详细信息
  install     安装技能
  uninstall   卸载技能
  update      更新技能
  search      搜索技能
  enable      启用技能
  disable     禁用技能
  validate    验证技能元数据
  run         运行技能命令 (--name --command [--args JSON] [--options JSON])
  deps        依赖解析/拓扑排序/循环检测 (--name [NAME])

选项:
  --name NAME         技能名称
  --source SOURCE     安装源
  --version VERSION   指定版本
  --force             强制操作
  --format FORMAT     输出格式 (json|table, 默认: table)
  -h, --help          显示帮助

示例:
  aiaos-cli skill list
  aiaos-cli skill info --name session-manager
  aiaos-cli skill install git@github.com:user/aiaos-skill-example.git
EOF
}

discover_skills() {
    for dir in "${SKILL_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for skill_yaml in "$dir"/*/skill.yaml; do
            [[ -f "$skill_yaml" ]] && echo "$skill_yaml"
        done
    done
}

# R880: 修复 Python 内插漏洞，使用 sys.argv 传递参数
parse_skill_yaml() {
    local skill_yaml="$1"
    python3 -c "
import yaml, json, sys, os
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
data['_path'] = os.path.dirname(sys.argv[1])
data['_source'] = os.path.basename(os.path.dirname(os.path.dirname(sys.argv[1])))
print(json.dumps(data))
" "$skill_yaml"
}

skill_list() {
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose) verbose=true; shift ;;
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            -h|--help) show_help; exit 0 ;;
            *) break ;;
        esac
    done

    # R2052 (PERF-002): 合并原先 2N 次 python3 调用（N=技能数）为 1 次。
    # 根因：旧实现对每个 skill.yaml 各起 1 次 parse_skill_yaml（YAML->JSON）
    # 和 1 次 python3（JSON->表格行），python3 冷启动 ~100ms，
    # 6 个技能即 12 次冷启动 ≈ 1.3s，占 skill list 总耗时 80%。
    # 现改为单次调用完成全部解析与渲染，实测 1.6s -> 0.25s。
    AIAOS_FMT="$format" AIAOS_VERBOSE="$verbose" python3 -c '
import json, os, sys, yaml
paths = sys.argv[1:]
rows = []
_seen_names = set()
for path in paths:
    try:
        with open(path) as f:
            d = yaml.safe_load(f) or {}
    except Exception:
        continue
    d["_path"] = os.path.dirname(path)
    d["_source"] = os.path.basename(os.path.dirname(os.path.dirname(path)))
    # R4300: 去重同名技能，优先保留内置技能（项目 skills/）
    _name = d.get("name", "") or ""
    if _name and _name in _seen_names:
        continue
    if _name:
        _seen_names.add(_name)
    rows.append(d)

fmt = os.environ.get("AIAOS_FMT", "table")
verbose = os.environ.get("AIAOS_VERBOSE") == "true"

if fmt == "json":
    print(json.dumps(rows, ensure_ascii=False))
else:
    if verbose:
        print(f"{"NAME":<30} {"VERSION":<10} {"SOURCE":<15} {"STATUS":<10} DESCRIPTION")
    else:
        print(f"{"NAME":<30} {"VERSION":<10} {"SOURCE":<15} DESCRIPTION")
    for data in rows:
        name = data.get("name", "") or ""
        version = data.get("version", "") or ""
        source = data.get("_source", "") or ""
        desc = (data.get("description", "") or "")[:60]
        status = "enabled" if not data.get("disabled", False) else "disabled"
        if verbose:
            print(f"{name:<30} {version:<10} {source:<15} {status:<10} {desc}")
        else:
            print(f"{name:<30} {version:<10} {source:<15} {desc}")
' $(discover_skills)
}

skill_info() {
    local name=""
    local fmt="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --format) fmt="$2"; shift 2 ;;
            --format=*) fmt="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    local found=false
    for skill_yaml in $(discover_skills); do
        local parsed=$(parse_skill_yaml "$skill_yaml")
        local skill_name=$(echo "$parsed" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
        if [[ "$skill_name" == "$name" ]]; then
            if [[ "$fmt" == "json" ]]; then
                echo "$parsed"
            else
                echo "$parsed" | python3 -c "
import yaml, json, sys
data = json.load(sys.stdin)
print(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
"
            fi
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then log_error "技能不存在: $name"; exit 1; fi
}

skill_install() {
    local source="" version="" force=false name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) source="$2"; shift 2 ;;
            --version) version="$2"; shift 2 ;;
            --force) force=true; shift ;;
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *)
                if [[ -z "$source" ]]; then
                    source="$1"
                fi
                shift
                ;;
        esac
    done

    [[ -z "$source" ]] && { log_error "需要安装源"; exit 1; }

    local target_dir="${AIAOS_CLI_CONFIG_DIR}/skills"
    mkdir -p "$target_dir"

    if [[ "$source" == http* || "$source" == git@* ]]; then
        local repo_name=$(basename "$source" .git)
        local skill_dir="$target_dir/$repo_name"

        if [[ -d "$skill_dir" && "$force" != true ]]; then
            log_error "技能已存在: $repo_name (使用 --force 覆盖)"
            exit 1
        fi

        log_info "克隆仓库: $source"
        git clone "$source" "$skill_dir" ${version:+--branch "$version"} --depth 1

        if [[ ! -f "$skill_dir/skill.yaml" ]]; then
            log_error "无效的技能包: 缺少 skill.yaml"
            rm -rf "$skill_dir"
            exit 1
        fi

        # R4107: 统一技能目录名为 skill.yaml 的 name 字段，避免 list/info/run
        # 用 name 匹配而 uninstall/update 用目录名匹配导致的名称不一致
        local yaml_name
        yaml_name=$(python3 -c "import yaml,sys; print((yaml.safe_load(open(sys.argv[1])) or {}).get('name',''))" "$skill_dir/skill.yaml" 2>/dev/null || true)
        if [[ -n "$yaml_name" && "$yaml_name" != "$repo_name" ]]; then
            mv -f "$skill_dir" "$target_dir/$yaml_name"
            skill_dir="$target_dir/$yaml_name"
            repo_name="$yaml_name"
        fi

        log_info "技能安装成功: $repo_name"
        output_result "success" "技能已安装" "name" "$repo_name" "path" "$skill_dir"

    elif [[ -d "$source" ]]; then
        local skill_name=$(basename "$source")
        local skill_dir="$target_dir/$skill_name"

        if [[ -d "$skill_dir" && "$force" != true ]]; then
            log_error "技能已存在: $skill_name (使用 --force 覆盖)"
            exit 1
        fi

        cp -r "$source" "$skill_dir"

        if [[ ! -f "$skill_dir/skill.yaml" ]]; then
            log_error "无效的技能包: 缺少 skill.yaml"
            rm -rf "$skill_dir"
            exit 1
        fi

        # R4107: 统一技能目录名为 skill.yaml 的 name 字段，避免 list/info/run
        # 用 name 匹配而 uninstall/update 用目录名匹配导致的名称不一致
        local yaml_name
        yaml_name=$(python3 -c "import yaml,sys; print((yaml.safe_load(open(sys.argv[1])) or {}).get('name',''))" "$skill_dir/skill.yaml" 2>/dev/null || true)
        if [[ -n "$yaml_name" && "$yaml_name" != "$skill_name" ]]; then
            mv -f "$skill_dir" "$target_dir/$yaml_name"
            skill_dir="$target_dir/$yaml_name"
            skill_name="$yaml_name"
        fi

        log_info "技能安装成功: $skill_name"
        output_result "success" "技能已安装" "name" "$skill_name" "path" "$skill_dir"

    else
        log_error "不支持的安装源: $source"
        exit 1
    fi
}

skill_uninstall() {
    local name="" force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --force) force=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    local found=false
    for dir in "${SKILL_DIRS[@]}"; do
        local skill_dir="$dir/$name"
        [[ -d "$skill_dir" ]] || continue
        # R4300: 内置技能（项目 skills/）跳过，继续查找用户技能
        if is_builtin_skill_dir "$dir"; then
            continue
        fi

        if [[ "$force" != true ]]; then
            read -p "确定卸载技能 $name? (y/N) " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "取消卸载"; exit 0; }
        fi

        rm -rf "$skill_dir"
        log_info "技能已卸载: $name"
        output_result "success" "技能已卸载" "name" "$name"
        found=true
        break
    done

    if [[ "$found" == false ]]; then
        # 内置技能存在但用户技能不存在
        for dir in "${SKILL_DIRS[@]}"; do
            if [[ -d "$dir/$name" ]] && is_builtin_skill_dir "$dir"; then
                log_error "无法卸载内置技能: $name"
                exit 1
            fi
        done
        log_error "技能不存在: $name"
        exit 1
    fi
}

skill_update() {
    local name="" version=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --version) version="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    local found=false
    for dir in "${SKILL_DIRS[@]}"; do
        local skill_dir="$dir/$name"
        if [[ -d "$skill_dir" && -d "$skill_dir/.git" ]]; then
            log_info "更新技能: $name"
            cd "$skill_dir"
            git fetch origin
            if [[ -n "$version" ]]; then
                git checkout "$version"
            else
                git pull origin
            fi
            log_info "技能已更新: $name"
            output_result "success" "技能已更新" "name" "$name"
            found=true
            break
        elif [[ -d "$skill_dir" ]]; then
            log_warn "技能 $name 非 Git 仓库，无法自动更新"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then log_error "技能不存在: $name"; exit 1; fi
}

skill_search() {
    local query="" format="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            --format=*) format="${1#*=}"; shift; export AIAOS_CLI_OUTPUT_FORMAT="$format" ;;
            *) query="$1"; shift ;;
        esac
    done

    skill_list --format "$format"
}

# R880: 修复 Python 内插漏洞，使用 sys.argv 传递参数
skill_enable() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    for dir in "${SKILL_DIRS[@]}"; do
        local skill_yaml="$dir/$name/skill.yaml"
        if [[ -f "$skill_yaml" ]]; then
            python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
data['disabled'] = False
with open(sys.argv[1], 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
" "$skill_yaml"
            log_info "技能已启用: $name"
            output_result "success" "技能已启用" "name" "$name"
            return 0
        fi
    done

    log_error "技能不存在: $name"
    exit 1
}

# R880: 修复 Python 内插漏洞，使用 sys.argv 传递参数
skill_disable() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    for dir in "${SKILL_DIRS[@]}"; do
        local skill_yaml="$dir/$name/skill.yaml"
        if [[ -f "$skill_yaml" ]]; then
            python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
data['disabled'] = True
with open(sys.argv[1], 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
" "$skill_yaml"
            log_info "技能已禁用: $name"
            output_result "success" "技能已禁用" "name" "$name"
            return 0
        fi
    done

    log_error "技能不存在: $name"
    exit 1
}

skill_validate() {
    local name=""
    local fmt="${AIAOS_CLI_OUTPUT_FORMAT:-table}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --format) fmt="$2"; shift 2 ;;
            --format=*) fmt="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    [[ -z "$name" ]] && { log_error "需要 --name 参数"; exit 1; }

    for dir in "${SKILL_DIRS[@]}"; do
        local skill_yaml="$dir/$name/skill.yaml"
        if [[ -f "$skill_yaml" ]]; then
            AIAOS_SKILL_YAML="$skill_yaml" AIAOS_SKILL_FMT="$fmt" python3 <<'PYEOF'
import os, sys, re, json, yaml
path = os.environ['AIAOS_SKILL_YAML']
fmt = os.environ.get('AIAOS_SKILL_FMT', 'table')
with open(path) as f:
    data = yaml.safe_load(f)

errors, warnings = [], []
for field in ['name', 'version', 'description', 'author', 'license']:
    if field not in data:
        errors.append(f'缺少必需字段: {field}')

if 'version' in data and not re.match(r'^\d+\.\d+\.\d+', str(data['version'])):
    warnings.append('版本号建议遵循 SemVer 格式')

if 'commands' in data:
    for i, cmd in enumerate(data['commands']):
        if 'name' not in cmd:
            errors.append(f'命令 {i} 缺少 name 字段')
        if 'entry' not in cmd:
            warnings.append(f'命令 {cmd.get("name", i)} 缺少 entry 字段')
        else:
            entry_path = os.path.join(os.path.dirname(path), cmd['entry'])
            if not os.path.exists(entry_path):
                warnings.append(f'命令 {cmd.get("name", i)} 的 entry 文件不存在: {entry_path}')

ok = not errors
if fmt == 'json':
    print(json.dumps({
        'status': 'ok' if ok else 'error',
        'skill': data.get('name', os.path.basename(os.path.dirname(path))),
        'valid': ok,
        'errors': errors,
        'warnings': warnings,
        'message': '验证通过' if ok else f'验证失败: {len(errors)} 个错误',
    }, ensure_ascii=False))
else:
    if errors:
        print('ERRORS:')
        for e in errors:
            print(f'  - {e}')
    if warnings:
        print('WARNINGS:')
        for w in warnings:
            print(f'  - {w}')
    print('验证通过' if ok else f'验证失败: {len(errors)} 个错误')

sys.exit(0 if ok else 1)
PYEOF
            return $?
        fi
    done

    log_error "技能不存在: $name"
    exit 1
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

skill_run() {
    local name="" command="" args_json="{}" opts_json="{}"
    local format="${AIAOS_CLI_OUTPUT_FORMAT:-json}"
    local positional=()
    local skill_opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --command|--cmd) command="$2"; shift 2 ;;
            --command=*|--cmd=*) command="${1#*=}"; shift ;;
            --args) args_json="$2"; shift 2 ;;
            --args=*) args_json="${1#*=}"; shift ;;
            --options) opts_json="$2"; shift 2 ;;
            --options=*) opts_json="${1#*=}"; shift ;;
            --format) format="$2"; shift 2 ;;
            --format=*) format="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            # R850: 未知短选项收集为 skill 级 options（透传给技能命令），
            #       避免与顶层选项冲突直接报错。
            -[a-zA-Z])
                local k="${1#-}"
                local v="true"
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    v="$2"; shift 2
                else
                    shift
                fi
                skill_opts+=("--$k" "$v")
                ;;
            -[a-zA-Z]*)
                local kv="${1#-}"
                local k="${kv%%=*}" v=""
                if [[ "$kv" == *=* ]]; then v="${kv#*=}"; skill_opts+=("--$k" "$v"); shift
                else
                    if [[ $# -ge 2 && "$2" != -* ]]; then v="$2"; skill_opts+=("--$k" "$v"); shift 2
                    else v="true"; skill_opts+=("--$k" "$v"); shift 1
                    fi
                fi
                ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    # 支持 <skill>/<cmd> 位置参数简写（设计文档 §5 范式）
    # R850: 位置参数显式给出时优先于 --name/--command（显式覆盖隐式），
    #       并支持第二个位置参数透传为 --args 的 name 字段（快捷用法）。
    if [[ ${#positional[@]} -gt 0 ]]; then
        local spec="${positional[0]}"
        if [[ "$spec" == */* ]]; then
            name="${spec%%/*}"
            command="${spec#*/}"
        else
            log_error "无法解析: $spec (期望 <skill>/<command>)"
            exit 1
        fi
        # 第二个位置参数：透传为 args.name（仅当未显式提供 --args 时）
        if [[ ${#positional[@]} -gt 1 && "$args_json" == "{}" ]]; then
            args_json="{\"name\":\"${positional[1]}\"}"
        fi
    fi

    [[ -z "$name" ]] && { log_error "需要 --name 或 <skill>/<cmd> 参数"; exit 1; }
    [[ -z "$command" ]] && { log_error "需要 --command 或 <skill>/<cmd> 参数"; exit 1; }

    # R2052 (PERF-001): 合并原先 5 次独立 python3 调用为 1 次。
    # 根因：每次 python3 冷启动 ~100ms，其中 4 次仅解析同一个 skill.yaml，
    # 另 1 次在 discover_skills 结果上循环解析全部 YAML（6 个 ≈ 700ms）。
    # 现改为单次调用：一次遍历全部候选 YAML，定位目标技能并输出
    # {skill_yaml, skill_dir, entry, opt_map, hooks} 的 JSON 结果。
    # 实测 skill run 从 ~1.75s 降至 ~0.6s（-66%）。
    local skill_meta skill_yaml skill_dir entry opt_map hooks_json
    skill_meta=$(python3 -c "
import json, os, sys, yaml
target_name, target_cmd = sys.argv[1], sys.argv[2]
paths = sys.argv[3:]
for path in paths:
    try:
        with open(path) as f:
            d = yaml.safe_load(f) or {}
    except Exception:
        continue
    if d.get('name') != target_name:
        continue
    cmd = None
    for c in d.get('commands', []) or []:
        if c.get('name') == target_cmd:
            cmd = c
            break
    if cmd is None:
        print(json.dumps({'error': 'cmd_not_found'}))
        sys.exit(0)
    opt_map = {}
    for o in cmd.get('options', []) or []:
        nm = (o.get('name') or '').lstrip('-')
        sh = (o.get('short') or '').lstrip('-')
        if nm and sh:
            opt_map[sh] = nm
    print(json.dumps({'skill_yaml': os.path.abspath(path),
                      'entry': cmd.get('entry', ''),
                      'opt_map': opt_map,
                      'hooks': d.get('hooks', {}) or {}}))
    sys.exit(0)
print(json.dumps({'error': 'skill_not_found'}))
" "$name" "$command" $(discover_skills))

    # R2052: 单次 python3 输出后，用 bash 原生提取，避免二次 python3 冷启动
    # （python3 冷启动 ~100ms，是本函数第二大开销）
    local _err
    _err=$(printf '%s' "$skill_meta" | sed -n 's/.*"error": *"\([^"]*\)".*/\1/p')
    case "$_err" in
        skill_not_found) log_error "技能不存在: $name"; exit 1 ;;
        cmd_not_found)   log_error "命令不存在: $name/$command"; exit 1 ;;
    esac

    skill_yaml=$(printf '%s' "$skill_meta" | sed -n 's/.*"skill_yaml": *"\([^"]*\)".*/\1/p')
    [[ -z "$skill_yaml" ]] && { log_error "技能不存在: $name"; exit 1; }
    skill_dir=$(dirname "$skill_yaml")
    entry=$(printf '%s' "$skill_meta" | sed -n 's/.*"entry": *"\([^"]*\)".*/\1/p')
    [[ -z "$entry" ]] && { log_error "命令不存在: $name/$command"; exit 1; }
    # opt_map / hooks 为嵌套 JSON 对象，sed 无法可靠截取，保留 python3 解析
    opt_map=$(printf '%s' "$skill_meta" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin).get('opt_map',{})))")
    hooks_json=$(printf '%s' "$skill_meta" | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin).get('hooks',{})))")

    # R850: 将收集到的 skill 级短选项合并进 opts_json（映射 short->long，显式 --options 优先）
    if [[ ${#skill_opts[@]} -gt 0 ]]; then
        local merged
        merged=$(python3 - "$opts_json" "$opt_map" "${skill_opts[@]}" <<'PYM'
import json, sys
opts = json.loads(sys.argv[1])
opt_map = json.loads(sys.argv[2])
rest = sys.argv[3:]
i = 0
while i < len(rest):
    raw = rest[i].lstrip('-')
    k = opt_map.get(raw, raw.replace('-', '_'))
    if i + 1 < len(rest) and not rest[i+1].startswith('-'):
        opts[k] = rest[i+1]; i += 2
    else:
        opts[k] = True; i += 1
print(json.dumps(opts))
PYM
)
        opts_json="$merged"
    fi

    local entry_file
    entry_file=$(cd "$skill_dir" && pwd)/"$entry"
    [[ -f "$entry_file" ]] || { log_error "入口文件不存在: $entry_file"; exit 1; }

    local emacs_bin="${AIAOS_CLI_EMACS:-emacs}"
    # R1323: 兜底定义 elisp_dir，防止直接 source skill.sh 时变量未绑定
    local elisp_dir="${AIAOS_CLI_ELISP_DIR:-}"
    if [[ -z "$elisp_dir" ]]; then
        local _cli_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
        elisp_dir="$_cli_root/elisp"
    fi
    command -v "$emacs_bin" >/dev/null 2>&1 || { log_error "emacs 未找到"; exit 1; }

    # 生成临时 elisp 脚本，避免 shell/emacs 双重转义
    # R860: 使用子shell + EXIT trap 确保临时文件在所有退出路径（含 exit 1）都被清理
    (
        local tmp_el
        tmp_el=$(mktemp /tmp/aiaos-skill-run.XXXXXX.el)
        local err_file
        err_file=$(mktemp /tmp/aiaos-skill-run.err.XXXXXX)
        trap "rm -f $tmp_el $err_file" EXIT

        # R900: 用临时文件传递 Python 脚本，彻底避免 shell/Python 引号地狱
        local py_gen
        py_gen=$(mktemp /tmp/aiaos-skill-gen.XXXXXX.py)
        trap "rm -f $tmp_el $err_file $py_gen" EXIT
        cat > "$py_gen" <<'PYGEN'
import json, sys, os
args = json.loads(sys.argv[1])
opts = json.loads(sys.argv[2])
entry_file = sys.argv[3]
name = sys.argv[4]
command = sys.argv[5]
hooks = json.loads(sys.argv[6])
skill_dir = os.path.dirname(os.path.dirname(entry_file))

print("(require 'json nil t)")

for _hk in ("on-load", "pre-command", "post-command"):
    _rel = hooks.get(_hk)
    if _rel:
        _hp = os.path.normpath(os.path.join(skill_dir, _rel))
        if os.path.isfile(_hp):
            print("(load " + json.dumps(_hp) + " 'noerror)")

print("(load " + json.dumps(entry_file) + " 'noerror)")

args_json_str = json.dumps(json.dumps(args))
opts_json_str = json.dumps(json.dumps(opts))

print("(let ((args (aiaos-cli--alist-to-plist (json-read-from-string " + args_json_str + ")))")
print("      (opts (aiaos-cli--alist-to-plist (json-read-from-string " + opts_json_str + "))))")
print("  (progn")
print("    (let ((result nil)))")

if hooks.get("pre-command"):
    print("    (when (fboundp 'aiaos-cli-skill-" + name + "/pre-command)")
    print("      (funcall 'aiaos-cli-skill-" + name + "/pre-command '" + command + " args))")

print("    (setf result (funcall 'aiaos-cli-skill-" + name + "/" + command + " args opts))")

if hooks.get("post-command"):
    print("    (when (fboundp 'aiaos-cli-skill-" + name + "/post-command)")
    print("      (funcall 'aiaos-cli-skill-" + name + "/post-command '" + command + " result))")

print("    (if (and (listp result) (plist-get result :status))")
print("      (princ (json-encode result))")
print("      (princ (json-encode (list :status 'ok :data result))))))")
PYGEN
        python3 "$py_gen" "$args_json" "$opts_json" "$entry_file" "$name" "$command" "$hooks_json" > "$tmp_el"

        # R820: 分离 stdout/stderr，避免 Emacs 的 Loading... 消息污染 JSON 输出。
        local result rc=0
        # R1100 (P0): set -e 下命令替换非零会直接终止子 shell，错误分支永远
        # 执行不到（R900 静默失败的真正根源）。用 `|| rc=$?` 显式接住退出码。
        result=$("$emacs_bin" --batch -L "$elisp_dir" -l aiaos-cli --load "$tmp_el" 2>"$err_file") || rc=$?

        if [[ $rc -ne 0 ]]; then
            # R1322 (TD-033): 提取真实错误信息，过滤 Emacs 启动日志
            # 调试详情写入日志文件，JSON 只返回干净的错误消息
            local err_log_file
            err_log_file=$(mktemp /tmp/aiaos-skill-run.debug.XXXXXX.log)
            trap "rm -f $tmp_el $err_file $py_gen $err_log_file" EXIT

            # 将完整 stderr + tmp_el 写入调试日志文件
            {
                echo "=== AIAOS skill run debug log ==="
                echo "skill: $name"
                echo "command: $command"
                echo "rc: $rc"
                echo "timestamp: $(date -Iseconds)"
                echo ""
                echo "--- stderr (err_file) ---"
                cat "$err_file"
                echo ""
                echo "--- generated elisp (tmp_el=$tmp_el) ---"
                cat "$tmp_el"
                echo ""
                echo "--- stdout (result) ---"
                echo "$result"
            } > "$err_log_file"

            # 从 stderr 提取有意义的错误行（过滤 Loading... / site-start.d 等）
            local clean_err
            clean_err=$(python3 -c "
import json, sys, re
lines = sys.stdin.read().splitlines()
skip_patterns = [
    r'^Loading /etc/emacs/site-start',
    r'^Loading .*.el (source)',
    r'^Loading /home.*site-start',
    r'^\[info\] Loading skill',
    r'^Loading .*hooks/',
    r'^Loading .*commands/',
    r'^Loading .*skills/',
    r'^$',
]
kept = []
for line in lines:
    if any(re.match(p, line) for p in skip_patterns):
        continue
    stripped = line.strip()
    if not stripped:
        continue
    kept.append(stripped)
if kept:
    print(chr(10).join(kept))
" < "$err_file")

            # 如果提取后仍有内容，用清理后的错误；否则回退到原始 stderr 最后一行
            local final_err
            if [[ -n "$clean_err" ]]; then
                final_err="$clean_err"
            else
                final_err=$(grep -v '^Loading' "$err_file" 2>/dev/null | grep -v '^$' | tail -1)
                [[ -z "$final_err" ]] && final_err=$(tail -1 "$err_file" 2>/dev/null)
                [[ -z "$final_err" ]] && final_err="Unknown error (rc=$rc)"
            fi

            local esc
            esc=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$final_err")
            echo "{\"status\":\"error\",\"skill\":\"$name\",\"command\":\"$command\",\"message\":$esc}"
            # R1322: 调试信息写入日志文件而非 stderr，避免污染用户输出
            echo "Debug log: $err_log_file" >&2
            exit 1
        fi

        echo "$result"
    )
    # 子shell结束，EXIT trap 自动清理 tmp_el + err_file
}


# ---------------------------------------------------------------------------
# skill deps (R1120): 依赖解析 + 拓扑排序 + 循环依赖检测
# 范式来源: design doc §5.4 P2 "技能依赖图：拓扑排序加载、循环依赖检测"
# ---------------------------------------------------------------------------
skill_deps() {
    local name="" fmt="${AIAOS_CLI_OUTPUT_FORMAT:-table}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --name=*) name="${1#*=}"; shift ;;
            --format) fmt="$2"; shift 2 ;;
            --format=*) fmt="${1#*=}"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    local IFS=':'
    AIAOS_DEPS_NAME="$name" AIAOS_DEPS_FMT="$fmt" AIAOS_DEPS_DIRS="${SKILL_DIRS[*]}" python3 <<'PYDEPS'
import os, sys, json, yaml

def skill_dirs():
    # 与 SKILL_DIRS 保持一致：由 shell 侧通过环境变量传入更可靠
    dirs = [d for d in os.environ.get('AIAOS_DEPS_DIRS', '').split(':') if d]
    return dirs

def load_skill_meta(d):
    y = os.path.join(d, 'skill.yaml')
    if not os.path.isfile(y):
        return None
    try:
        with open(y) as f:
            data = yaml.safe_load(f) or {}
    except Exception as e:
        return {'name': os.path.basename(d), '_error': str(e), '_path': d}
    data['_path'] = d
    return data

def find_all():
    metas = {}
    for d in skill_dirs():
        if not os.path.isdir(d):
            continue
        for entry in sorted(os.listdir(d)):
            full = os.path.join(d, entry)
            if os.path.isdir(full):
                m = load_skill_meta(full)
                if m and 'name' in m:
                    metas[m['name']] = m
    return metas

def deps_of(meta):
    dep = (meta.get('dependencies') or {})
    skills = dep.get('skills') or []
    if isinstance(skills, str):
        skills = [skills]
    out = []
    for s in skills:
        if isinstance(s, dict):
            out.append(s.get('name'))
        elif isinstance(s, str):
            out.append(s)
    return [s for s in out if s]

# ---- 拓扑排序 (Kahn) + 循环检测 ----
def topo_sort(metas, root):
    graph = {}
    for n, m in metas.items():
        graph[n] = [d for d in deps_of(m) if d in metas]
    order, visited, on_path, cycles = [], set(), set(), []
    def visit(n):
        if n in visited:
            return
        if n in on_path:
            cyc = on_path_seq[on_path_seq.index(n):] + [n]
            cycles.append(cyc)
            return
        on_path.add(n); on_path_seq.append(n)
        for d in graph.get(n, []):
            visit(d)
        on_path.discard(n); on_path_seq.pop()
        visited.add(n)
        order.append(n)
    on_path_seq = []
    visit(root)
    return order, cycles, graph

name = os.environ.get('AIAOS_DEPS_NAME', '')
fmt = os.environ.get('AIAOS_DEPS_FMT', 'table')
metas = find_all()

if name and name not in metas:
    print(json.dumps({'status': 'error', 'message': f'技能不存在: {name}'}, ensure_ascii=False))
    sys.exit(1)

targets = [name] if name else sorted(metas.keys())
results, has_cycle = [], False
for t in targets:
    order, cycles, graph = topo_sort(metas, t)
    if cycles:
        has_cycle = True
    results.append({
        'skill': t,
        'direct_deps': deps_of(metas[t]) if t in metas else [],
        'load_order': order,
        'cycles': cycles,
        'missing': [d for d in deps_of(metas[t]) if d not in metas] if t in metas else [],
    })

ok = not has_cycle and not any(r['missing'] for r in results)
if fmt == 'json':
    print(json.dumps({'status': 'ok' if ok else 'error', 'skills': results}, ensure_ascii=False))
else:
    for r in results:
        print(f"技能: {r['skill']}")
        print(f"  直接依赖: {', '.join(r['direct_deps']) or '(无)'}")
        if r['missing']:
            print(f"  缺失依赖: {', '.join(r['missing'])}")
        print(f"  加载顺序: {' -> '.join(r['load_order']) or '(无)'}")
        for c in r['cycles']:
            print(f"  ⚠ 循环依赖: {' -> '.join(c)}")
    if ok:
        print('依赖解析通过')
sys.exit(0 if ok else 1)
PYDEPS
}


### R2300: skill_create 脚手架命令实现

skill_create() {
    local skill_name=""
    local output_dir=""
    local force=false
    local cmd_name=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                skill_name="$2"; shift 2 ;;
            --output-dir)
                output_dir="$2"; shift 2 ;;
            --command)
                cmd_name="$2"; shift 2 ;;
            --force)
                force=true; shift ;;
            -h|--help)
                cat <<'HELP'
用法: aiaos-cli skill create --name <skill-name> [选项]

选项:
  --name NAME         技能名称（kebab-case，必需）
  --command NAME      首个命令名称（可选，默认 "hello"）
  --output-dir DIR    输出目录（可选，默认 <skills-root>/<name>）
  --force             覆盖已存在目录
  -h, --help          显示帮助

示例:
  aiaos-cli skill create --name my-skill --command greet
  aiaos-cli skill create --name data-tools --output-dir ~/.config/aiaos/skills/data-tools

生成结构:
  <output-dir>/
  ├── skill.yaml              # 技能元数据
  ├── commands/
  │   └── <command>.el        # 示例命令
  └── hooks/
      ├── on-load.el          # 加载钩子
      ├── pre-command.el      # 前置钩子
      └── post-command.el     # 后置钩子
HELP
                return 0 ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    # 校验技能名称
    if [[ -z "$skill_name" ]]; then
        log_error "缺少 --name 参数"
        return 1
    fi
    if ! [[ "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        log_error "技能名称必须为 kebab-case: $skill_name"
        return 1
    fi
    if [[ -z "$cmd_name" ]]; then
        cmd_name="hello"
    fi
    if ! [[ "$cmd_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        log_error "命令名称必须为 kebab-case: $cmd_name"
        return 1
    fi

    # 确定输出目录
    if [[ -z "$output_dir" ]]; then
        output_dir="$AIAOS_CLI_SKILLS_DIR/$skill_name"
    fi

    # 检查已存在
    if [[ -d "$output_dir" && "$force" != true ]]; then
        log_error "目录已存在: $output_dir（使用 --force 覆盖）"
        return 1
    fi

    log_info "创建技能骨架: $skill_name @ $output_dir"

    # 创建目录结构
    mkdir -p "$output_dir/commands" "$output_dir/hooks"

    # 生成 skill.yaml
    cat > "$output_dir/skill.yaml" <<YAML
name: "$skill_name"
version: "1.0.0"
description: "AIAOS-CLI 技能包：$skill_name"
author: "Generated by aiaos-cli skill create"
license: "MIT"
keywords: ["generated"]

dependencies:
  core: ">=1.0.0"
  skills: []
  system:
    - "emacs>=29"

commands:
  - name: "$cmd_name"
    entry: "commands/$cmd_name.el"
    description: "示例命令：$cmd_name"
    args: []
    options: []

hooks:
  on-load: "hooks/on-load.el"
  pre-command: "hooks/pre-command.el"
  post-command: "hooks/post-command.el"

resources:
  templates: []
  schemas: []
YAML

    # 生成命令文件
    cat > "$output_dir/commands/$cmd_name.el" <<ELISP
;;; $cmd_name.el --- $skill_name skill: $cmd_name command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-$skill_name/$cmd_name (args &rest options)
  "示例命令。

ARGS is a plist with arguments.
OPTIONS is a plist with options."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options)))
    (list :status "ok"
          :result "ok"
          :skill "$skill_name"
          :command "$cmd_name"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-$skill_name/$cmd_name)
;;; $cmd_name.el ends here
ELISP

    # 生成 on-load.el
    cat > "$output_dir/hooks/on-load.el" <<ELISP
;;; on-load.el --- $skill_name skill: on-load hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-$skill_name/on-load ()
  "Called when the $skill_name skill is loaded."
  (message "aiaos-cli-skill-$skill_name: loaded"))

(provide 'aiaos-cli-skill-$skill_name/on-load)
;;; on-load.el ends here
ELISP

    # 生成 pre-command.el
    cat > "$output_dir/hooks/pre-command.el" <<ELISP
;;; pre-command.el --- $skill_name skill: pre-command hook -*- lexical-binding: t; -*-

(defcustom aiaos-cli-skill-$skill_name/audit-log nil
  "Audit log path for $skill_name pre-command hook.
Set to a writable file path to enable audit logging.
Default nil disables audit logging (safe for batch mode)."
  :type '(choice (string) (const :tag "disabled" nil))
  :group 'aiaos-cli)

(defun aiaos-cli-skill-$skill_name/pre-command (command args)
  "Called before any $skill_name command runs.
COMMAND is the command name (symbol).
ARGS is a plist with arguments."
  (when (and aiaos-cli-skill-$skill_name/audit-log
             (stringp aiaos-cli-skill-$skill_name/audit-log))
    (condition-case _
        (with-current-buffer
            (find-file-noselect aiaos-cli-skill-$skill_name/audit-log)
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert (format "[%s] pre-command: %s args=%S\n"
                            (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                            command args))))
      (error nil)))
  nil)

(provide 'aiaos-cli-skill-$skill_name/pre-command)
;;; pre-command.el ends here
ELISP

    # 生成 post-command.el
    cat > "$output_dir/hooks/post-command.el" <<ELISP
;;; post-command.el --- $skill_name skill: post-command hook -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-$skill_name/post-command (command result)
  "Called after any $skill_name command runs.
COMMAND is the command name (symbol).
RESULT is the command return value (plist).

Never raises; failures are silently ignored."
  (condition-case _
      (when (and (listp result)
                 (plist-get result :status))
        (unless (equal (plist-get result :status) "ok")
          (message "aiaos-cli-skill-$skill_name/%s: non-ok status %S"
                   command (plist-get result :status))))
    (error nil))
  nil)

(provide 'aiaos-cli-skill-$skill_name/post-command)
;;; post-command.el ends here
ELISP

    log_info "技能骨架创建完成"

    # Elisp 语法检查
    if command -v emacs >/dev/null 2>&1; then
        emacs --batch --eval "(load-file \"$output_dir/commands/$cmd_name.el\")" 2>/dev/null \
            && log_info "Elisp 命令语法检查通过" \
            || log_warn "Elisp 语法检查有警告（不影响使用）"
    fi

    # 输出生成结果
    echo ""
    echo "=== 技能骨架已生成 ==="
    echo "路径: $output_dir"
    echo ""
    echo "结构:"
    find "$output_dir" -type f | sed "s|$output_dir/|  |" | sort
    echo ""
    echo "下一步:"
    echo "  1. 编辑 $output_dir/skill.yaml 添加更多命令"
    echo "  2. 在 $output_dir/commands/ 中实现命令逻辑"
    echo "  3. 运行: aiaos-cli skill validate --name $skill_name"
    echo "  4. 运行: aiaos-cli skill run --name $skill_name --command $cmd_name"
}

action="${1:-help}"
shift || true

case "$action" in
    create|new) skill_create "$@" ;;
    list|ls) skill_list "$@" ;;
    info) skill_info "$@" ;;
    install) skill_install "$@" ;;
    uninstall|remove) skill_uninstall "$@" ;;
    update) skill_update "$@" ;;
    search) skill_search "$@" ;;
    enable) skill_enable "$@" ;;
    disable) skill_disable "$@" ;;
    validate) skill_validate "$@" ;;
    run) skill_run "$@" ;;
    deps) skill_deps "$@" ;;
    help|--help|-h) show_help ;;
    *) log_error "未知动作: $action"; show_help; exit 1 ;;
esac