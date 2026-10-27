#!/usr/bin/env bash
# AIAOS-CLI Provider 管理模块
#
# 提供 LLM Provider 切换、可用性分级、健康检查、fallback 策略管理
#
# 用法:
#   aiaos-cli provider list [--format table|json]
#   aiaos-cli provider use <name>
#   aiaos-cli provider test <name> [--probe mock|live]
#   aiaos-cli provider tier <name> <full|active|block>
#   aiaos-cli provider fallback --strategy sequential|round_robin|priority
#   aiaos-cli provider fallback-order <p1,p2,p3>
#   aiaos-cli provider chat --message "..." [--strategy ...]
#   aiaos-cli provider audit <name>
#   aiaos-cli provider report

set -euo pipefail

# 使用主 CLI 导出的日志函数（如果可用）
if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[INFO]  $*" >&2; }
    log_warn()  { echo "[WARN]  $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { :; }
fi

# AIAOS 项目根目录（lib/ 所在目录）
AIAOS_ROOT="${AIAOS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AIAOS_LIB_DIR="${AIAOS_LIB_DIR:-$AIAOS_ROOT/lib}"
AIAOS_AUDIT_LOG="${AIAOS_AUDIT_LOG:-${AIAOS_CLI_CONFIG_DIR:-$HOME/.config/aiaos}/provider_audit.log}"

# 设置 PYTHONPATH 以便 import aiaos.lib
export PYTHONPATH="${AIAOS_LIB_DIR}/..:${PYTHONPATH:-}"

show_help() {
    cat <<'EOF'
用法: aiaos-cli provider <动作> [选项]

动作:
  list                列出所有 provider 及当前分级
  use <name>          切换当前 provider
  test <name>         健康检查并更新分级
  tier <name> <lvl>   手动设置分级 (full|active|block)
  fallback --strategy <s>  设置 fallback 策略 (sequential|round_robin|priority)
  fallback-order <list>    设置顺序 fallback 顺序 (逗号分隔)
  chat --message "..."     带 fallback 的 chat 调用（演示）
  audit <name>      查看 provider 审计日志
  report            完整快照（含策略、当前 provider、fallback 顺序）

选项:
  --format FORMAT   输出格式 (table|json, 默认 table)
  --probe MODE      探测模式 (mock|live, 默认 mock)
  -h, --help        显示帮助

示例:
  aiaos-cli provider list
  aiaos-cli provider use sensenova
  aiaos-cli provider test agnes --probe mock
  aiaos-cli provider tier nvidia block
  aiaos-cli provider fallback --strategy round_robin
  aiaos-cli provider fallback-order agnes,sensenova,xunfei,cn,red,nvidia,nvidia2
  aiaos-cli provider chat --message "你好" --strategy sequential
EOF
}

# 通用：调用 Python 子命令
_py() {
    python3 - "$@" <<'__PY__'
import sys, os, json
sys.path.insert(0, os.environ.get("PYTHONPATH", "").split(":")[0] if os.environ.get("PYTHONPATH") else ".")
from lib.llm_provider_registry import ProviderRegistry, ProviderTier, BUILTIN_PROVIDERS, get_default_registry
from lib.llm_fallback import FallbackRouter, FallbackStrategy
import argparse

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False, default=str))

def main():
    cmd = sys.argv[1]
    args = sys.argv[2:]

    if cmd == "list":
        fmt = "table"
        if "--format" in args:
            fmt = args[args.index("--format") + 1]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        snap = reg.snapshot()
        if fmt == "json":
            emit(snap)
        else:
            print(f"{'NAME':<12} {'DISPLAY':<20} {'TIER':<8} {'USABLE':<7} {'ERR':<4} {'OK':<4} {'LAT_MS':<7} {'MODEL'}")
            print("-" * 90)
            for name, info in snap["providers"].items():
                m, s = info["meta"], info["state"]
                print(f"{name:<12} {m['display_name']:<20} {s['tier']:<8} "
                      f"{str(s['tier'] != 'block'):<7} {s['consecutive_errors']:<4} "
                      f"{s['consecutive_successes']:<4} {s['last_check_latency_ms']:<7} {m['default_model']}")
        return

    if cmd == "use":
        if not args:
            emit({"error": "provider use needs 1 arg: <name>", "usage": "aiaos-cli provider use <name>"})
            sys.exit(1)
        name = args[0]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        try:
            reg.set_current(name)
        except KeyError as e:
            emit({"error": str(e).strip(chr(39)), "usage": "aiaos-cli provider use <name>"})
            sys.exit(1)
        cfg = os.environ.get("AIAOS_CLI_CONFIG_DIR", os.path.expanduser("~/.config/aiaos"))
        os.makedirs(cfg, exist_ok=True)
        with open(os.path.join(cfg, "provider.yaml"), "w") as f:
            f.write(f"current_provider: {name}\n")
        print(f"当前 provider: {name}")
        return

    if cmd == "test":
        if not args:
            emit({"error": "provider test needs 1 arg: <name>", "usage": "aiaos-cli provider test <name> [--probe mock|live]"})
            sys.exit(1)
        name = args[0]
        probe_mode = "mock"
        if "--probe" in args:
            probe_mode = args[args.index("--probe") + 1]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        meta = reg.get_meta(name)

        if probe_mode == "mock":
            # mock 探测：模拟全部成功
            from lib.llm_provider_registry import HealthCheckResult
            result = reg.health_check(name, probe=lambda m: HealthCheckResult(ok=True, latency_ms=42))
        else:
            # live 探测：使用默认（仅检查 API key）
            result = reg.health_check(name)

        emit({
            "provider": name,
            "ok": result.ok,
            "latency_ms": result.latency_ms,
            "error": result.error,
            "tier_after": reg.get_tier(name).value,
        })
        return

    if cmd == "tier":
        if len(args) < 2:
            emit({"error": "provider tier needs 2 args: <name> <full|active|block>", "usage": "aiaos-cli provider tier <name> <full|active|block>"})
            sys.exit(1)
        name, lvl = args[0], args[1]
        valid_tiers = {"full", "active", "block"}
        if lvl not in valid_tiers:
            emit({"error": f"invalid tier '{lvl}', must be one of: {', '.join(sorted(valid_tiers))}", "usage": "aiaos-cli provider tier <name> <full|active|block>"})
            sys.exit(1)
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        reg.set_tier(name, ProviderTier(lvl), reason="cli_manual")
        print(f"{name} tier -> {lvl}")
        return

    if cmd == "fallback":
        strategy = "sequential"
        if "--strategy" in args:
            strategy = args[args.index("--strategy") + 1]
        valid_strategies = {"sequential", "round_robin", "priority"}
        if strategy not in valid_strategies:
            emit({"error": f"invalid strategy '{strategy}', must be one of: {', '.join(sorted(valid_strategies))}", "usage": "aiaos-cli provider fallback --strategy <s>"})
            sys.exit(1)
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        router = FallbackRouter(reg, strategy=FallbackStrategy(strategy))
        # 持久化策略（覆盖模式：先读旧配置，只替换 fallback_strategy 行）
        cfg = os.environ.get("AIAOS_CLI_CONFIG_DIR", os.path.expanduser("~/.config/aiaos"))
        os.makedirs(cfg, exist_ok=True)
        cfg_path = os.path.join(cfg, "provider.yaml")
        old_lines = []
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                old_lines = [l for l in f if not l.startswith("fallback_strategy:")]
        with open(cfg_path, "w") as f:
            f.writelines(old_lines)
            f.write(f"fallback_strategy: {strategy}\n")
        print(f"fallback strategy -> {strategy}")
        return

    if cmd == "fallback-order":
        order_str = args[0]
        order = [p.strip() for p in order_str.split(",") if p.strip()]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        reg.set_fallback_order(order)
        cfg = os.environ.get("AIAOS_CLI_CONFIG_DIR", os.path.expanduser("~/.config/aiaos"))
        os.makedirs(cfg, exist_ok=True)
        with open(os.path.join(cfg, "provider.yaml"), "a") as f:
            f.write(f"fallback_order: {order_str}\n")
        print(f"fallback order -> {order}")
        return

    if cmd == "chat":
        msg = ""
        strategy = "sequential"
        if "--message" in args:
            msg = args[args.index("--message") + 1]
        if "--strategy" in args:
            strategy = args[args.index("--strategy") + 1]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        router = FallbackRouter(reg, strategy=FallbackStrategy(strategy))

        # 演示用 mock invoke：模拟第一个 provider 失败、第二个成功
        calls = {"n": 0}
        def mock_invoke(meta, messages, **kw):
            calls["n"] += 1
            # 第一个调用失败，第二个成功
            if calls["n"] == 1:
                return False, None, "mock_first_failure"
            return True, {"content": f"[{meta.name}] echo: {messages[-1].get('content','')[:50]}",
                          "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}}, None

        result = router.chat(messages=[{"role": "user", "content": msg}], invoke_fn=mock_invoke)
        emit(result.to_dict())
        return

    if cmd == "audit":
        if not args:
            emit({"error": "provider audit needs 1 arg: <name>", "usage": "aiaos-cli provider audit <name>"})
            sys.exit(1)
        name = args[0]
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        log = reg.get_audit_log(name)
        # R2500: 附加 circuit breaker 状态
        try:
            state = reg.get_state(name)
            circuit = {
                "tier": state.tier.value,
                "consecutive_errors": state.consecutive_errors,
                "consecutive_successes": state.consecutive_successes,
                "circuit_open": state.circuit_open,
                "circuit_open_until": state.circuit_open_until,
            }
        except Exception:
            circuit = None
        emit({"provider": name, "audit_log": log, "circuit_state": circuit})
        return

    if cmd == "report":
        reg = get_default_registry(audit_log_path=os.environ.get("AIAOS_AUDIT_LOG"))
        # R2500: 读取持久化策略，而非硬编码
        cfg = os.environ.get("AIAOS_CLI_CONFIG_DIR", os.path.expanduser("~/.config/aiaos"))
        cfg_path = os.path.join(cfg, "provider.yaml")
        persisted_strategy = "sequential"
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                for line in f:
                    if line.startswith("fallback_strategy:"):
                        persisted_strategy = line.split(":", 1)[1].strip()
                        break
        router = FallbackRouter(reg, strategy=FallbackStrategy(persisted_strategy))
        emit(router.report())
        return

    print(f"unknown provider subcommand: {cmd}", file=sys.stderr)
    sys.exit(1)

main()
__PY__
}

# 主入口
provider_main() {
    local action="${1:-}"
    shift || true

    # 统一拦截 --help / -h（R2300 修复：所有子命令均支持 --help）
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    case "$action" in
        list|use|test|tier|fallback|fallback-order|chat|audit|report)
            # 参数校验（R2300 修复：Shell 层统一参数检查）
            case "$action" in
                use|test|audit)
                    if [[ -z "${1:-}" ]]; then
                        log_error "$action 需要 <name> 参数"
                        show_help
                        exit 1
                    fi
                    ;;
                tier)
                    if [[ -z "${1:-}" || -z "${2:-}" ]]; then
                        log_error "tier 需要 <name> <full|active|block> 参数"
                        show_help
                        exit 1
                    fi
                    ;;
                fallback-order)
                    if [[ -z "${1:-}" ]]; then
                        log_error "需要 <provider1,provider2,...> 参数"
                        show_help
                        exit 1
                    fi
                    ;;
            esac
            _py "$action" "$@"
            ;;
        -h|--help|help|"")
            show_help
            ;;
        *)
            log_error "未知 provider 子命令: $action"
            show_help
            exit 1
            ;;
    esac
}

provider_main "$@"
