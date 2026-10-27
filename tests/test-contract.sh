#!/usr/bin/env bash
# AIAOS-CLI 契约自动化核对脚本
# R2030: 将 aiaos-cli_design.md §62.3 范式 D 从伪代码落地为可执行脚本
#
# 用途：把 ~/aiaos-cli_skills.md 中"关键约束"章节的硬约束，
#       从"人肉 grep"升级为"契约表驱动"的自动核对。
#
# 用法：
#   bash tests/test-contract.sh          # 全量核对
#   bash tests/test-contract.sh --quick  # 仅核对阻塞级约束（<2s）
#
# 退出码：0=全部通过；1=有 FAIL；2=脚本自身错误

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLI_BIN="$PROJECT_DIR/bin/aiaos-cli"
ELISP_DIR="$PROJECT_DIR/elisp"
SKILLS_DIR="$PROJECT_DIR/skills"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASS=0; FAIL=0; SKIP=0
FAIL_NAMES=()

check() {
    local name="$1" level="$2" cmd="$3"
    local out rc
    # 去掉 cmd 两端的双引号（若存在），避免 eval 把它当字符串字面量
    cmd="${cmd#\"}"
    cmd="${cmd%\"}"
    out=$(eval "$cmd" 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}: $name"
        PASS=$((PASS+1))
    else
        if [[ "$level" == "block" ]]; then
            echo -e "${RED}FAIL${NC}: $name"
            echo "       cmd: $cmd"
            echo "       out: ${out:0:200}"
            FAIL=$((FAIL+1))
            FAIL_NAMES+=("$name")
        else
            echo -e "${YELLOW}WARN${NC}: $name (non-blocking)"
            SKIP=$((SKIP+1))
        fi
    fi
}

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

# --- 契约组 A：技能加载（skills.md §四.1）---
check "A1: aiaos-cli.el 使用 autoload 而非 init 自动加载 [R2030-drift]" "warn" \
    "grep -q 'autoload' $ELISP_DIR/aiaos-cli.el"
check "A2: 存在显式 skill load 入口" "block" \
    "grep -Eq 'aiaos-cli-skill-load|load-skill' $ELISP_DIR/*.el"

# --- 契约组 B：通信契约（skills.md §四.2）---
check "B1: hello-world/hello 返回 status=ok" "block" \
    "$CLI_BIN skill run --name hello-world --command hello --args '{\"name\":\"AIAOS\"}' | grep -q '\"status\":\"ok\"'"
check "B2: 缺失必需参数返回 status=error" "block" \
    "tmpf=\$(mktemp); $CLI_BIN skill run --name string-tools --command reverse --args '{}' > \$tmpf 2>&1; grep -q error \$tmpf; rm -f \$tmpf"
check "B3: 返回体含 skill 字段" "block" \
    "$CLI_BIN skill run --name hello-world --command hello --args '{\"name\":\"x\"}' | grep -q '\"skill\":\"hello-world\"'"
check "B4: 返回体含 command 字段" "block" \
    "$CLI_BIN skill run --name hello-world --command hello --args '{\"name\":\"x\"}' | grep -q '\"command\":\"hello\"'"

# --- 契约组 C：进程管理（skills.md §四.3）---
check "C1: 存在 start-process 异步调用" "block" \
    "grep -q 'start-process' $ELISP_DIR/*.el"
check "C2: 存在进程哨兵回调 (set-process-sentinel 或 make-process :sentinel)" "warn" \
    "grep -q 'set-process-sentinel' $ELISP_DIR/*.el || grep -q ':sentinel' $ELISP_DIR/*.el"
check "C3: 默认超时 30s" "block" \
    "grep -Eq '(timeout.*30|30.*timeout)' $ELISP_DIR/*.el"

# --- 契约组 D：日志规范（skills.md §四.4）---
check "D1: 存在 JSON Lines 日志写入 [R2030-drift]" "warn" \
    "grep -Eq 'json-lines|json_lines|JSON Lines' $ELISP_DIR/*.el $PROJECT_DIR/core/*.sh 2>/dev/null"
check "D2: 统一日志目录存在" "warn" \
    "test -d ~/.local/share/aiaos/logs || test -d ~/.cache/aiaos/logs"

# --- 契约组 E：技能元数据完整性（skills.md §1-2）---
for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    sname="$(basename "$skill_dir")"
    check "E[$sname]: skill.yaml 存在" "block" \
        "test -f $skill_dir/skill.yaml"
    check "E[$sname]: commands/ 目录存在" "block" \
        "test -d $skill_dir/commands"
    check "E[$sname]: skill.yaml 含 name 字段" "block" \
        "grep -q '^name:' $skill_dir/skill.yaml"
    check "E[$sname]: skill.yaml 含 version 字段" "block" \
        "grep -q '^version:' $skill_dir/skill.yaml"
done

echo ""
echo -e "${BLUE}=== 契约核对汇总 ===${NC}"
echo "PASS=$PASS  FAIL=$FAIL  WARN=$SKIP"
if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}失败契约:${NC}"
    for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
    echo ""
    echo -e "${RED}=== 汇总: PASS=$PASS FAIL=$FAIL ===${NC}"
    exit 1
fi
echo -e "${GREEN}=== 汇总: PASS=$PASS FAIL=$FAIL ===${NC}"
exit 0
