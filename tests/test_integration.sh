#!/usr/bin/env bash
# AIAOS-CLI 集成测试套件 (R3001 · TD-004 集成测试落地)
# 覆盖 CLI 分发 → Emacs 前端 → 技能命令 → 结果回显 全链路

set -uo pipefail

AIAOS_CLI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIAOS_CLI_BIN="$AIAOS_CLI_ROOT/bin/aiaos-cli"
AIAOS_CLI_ELIP="$AIAOS_CLI_ROOT/elisp"
AIAOS_CLI_SKILLS="$AIAOS_CLI_ROOT/skills"

# 测试数据目录（独立隔离）
export AIAOS_CLI_DATA_DIR="/tmp/aiaos-integration-$$"
export AIAOS_CLI_CONFIG_DIR="/tmp/aiaos-integration-cfg-$$"
mkdir -p "$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_CONFIG_DIR"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 清理
cleanup() {
    rm -rf /tmp/aiaos-integration-$$ /tmp/aiaos-integration-cfg-$$ 2>/dev/null
}
trap cleanup EXIT

echo "=================================="
echo "AIAOS-CLI 集成测试 (R3001 · TD-004)"
echo "=================================="

# ============================================================
# 测试 1: skill run --name --command --args 全链路
# ============================================================
echo ""
echo "--- 测试 1: skill run 全链路 (CLI→Emacs→技能→回显) ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" skill run \
    --name hello-world --command hello --args '{"name":"AIAOS"}' --format json 2>/dev/null)
[[ "$OUT" == *"AIAOS"* ]] && pass "skill run --name 全链路含参数回显" || fail "skill run --name 全链路 ($OUT)"

# ============================================================
# 测试 2: skill run 位置参数透传 (skill/command 格式)
# ============================================================
echo ""
echo "--- 测试 2: skill run 位置参数透传 ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" skill run \
    hello-world/hello --args '{"name":"Integration"}' --format json 2>/dev/null)
[[ "$OUT" == *"Integration"* ]] && pass "skill run 位置参数透传全链路" || fail "skill run 位置参数 ($OUT)"

# ============================================================
# 测试 3: emacs --batch 技能加载与调用
# ============================================================
echo ""
echo "--- 测试 3: emacs --batch 技能加载与调用 ---"

BATCH_SCRIPT=$(cat << 'EL'
(require 'aiaos-cli)
(aiaos-cli-init)
;; 显式加载技能（见 §6 实测记录）
(load (expand-file-name "skills/hello-world/commands/hello.el" "/home/shjiaye8/aiaos/aiaos-cli/"))
(aiaos-cli-skill-hello-world-hello "AIAOS-Integrated")
EL
)

BATCH_FILE="/tmp/aiaos-int-test-$$.el"
echo "$BATCH_SCRIPT" > "$BATCH_FILE"

OUT=$(emacs --batch -L "$AIAOS_CLI_ELIP" -l aiaos-cli --eval "(load \"$BATCH_FILE\")" 2>/dev/null || true)
[[ "$OUT" == *"AIAOS-Integrated"* ]] && pass "emacs --batch 技能加载与调用" || fail "emacs --batch ($OUT)"
rm -f "$BATCH_FILE"

# ============================================================
# 测试 4: skill validate → skill list → skill run 全链路闭环
# ============================================================
echo ""
echo "--- 测试 4: validate→list→run 全链路闭环 ---"

V=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" skill validate --name hello-world --format json 2>/dev/null)
[[ "$V" == *"valid"* ]] || [[ "$V" == *"success"* ]] && pass "validate 全链路" || fail "validate ($V)"

L=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" skill list --format json 2>/dev/null)
[[ "$L" == *"hello-world"* ]] && pass "list 全链路含 hello-world" || fail "list ($L)"

# ============================================================
# 测试 5: 跨技能调用 (string-tools reverse)
# ============================================================
echo ""
echo "--- 测试 5: 跨技能调用 (string-tools reverse) ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" skill run \
    --name string-tools --command reverse --args '{"text":"aiaos"}' --format json 2>/dev/null)
[[ "$OUT" == *"soaia"* ]] && pass "string-tools reverse 全链路" || fail "string-tools ($OUT)"

# ============================================================
# 测试 6: agent chat 端到端
# ============================================================
echo ""
echo "--- 测试 6: agent chat 端到端 ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" agent chat \
    --message "test message" --format json 2>/dev/null)
[[ "$OUT" == *"message"* ]] && pass "agent chat 端到端" || fail "agent chat ($OUT)"

# ============================================================
# 测试 7: session 生命周期全链路
# ============================================================
echo ""
echo "--- 测试 7: session 生命周期全链路 ---"

SID=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" session new --name "integration-test" --format json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
[[ -n "$SID" ]] && pass "session new 全链路 (id=$SID)" || fail "session new"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" session current --format json 2>/dev/null)
[[ "$OUT" == *"$SID"* ]] && pass "session current 全链路" || fail "session current ($OUT)"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" session archive --id "$SID" --format json 2>/dev/null)
[[ "$OUT" == *"归档"* ]] || [[ "$OUT" == *"archiv"* ]] && pass "session archive 全链路" || fail "session archive ($OUT)"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" session delete --id "$SID" --force --format json 2>/dev/null)
[[ "$OUT" == *"删除"* ]] || [[ "$OUT" == *"delete"* ]] && pass "session delete 全链路" || fail "session delete ($OUT)"

# ============================================================
# 测试 8: doctor 诊断全链路
# ============================================================
echo ""
echo "--- 测试 8: doctor 诊断全链路 ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" doctor check --format json 2>/dev/null)
[[ "$OUT" == *"check"* ]] || [[ "$OUT" == *"status"* ]] && pass "doctor check 全链路" || fail "doctor check ($OUT)"

# ============================================================
# 测试 9: provider 管理全链路
# ============================================================
echo ""
echo "--- 测试 9: provider 管理全链路 ---"

OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" provider list --format json 2>/dev/null)
[[ "$OUT" == *"provider"* ]] || [[ "$OUT" == *"agnes"* ]] || [[ "$OUT" == *"[]"* ]] && pass "provider list 全链路" || fail "provider list ($OUT)"

# ============================================================
# 测试 10: JSON 格式一致性验证
# ============================================================
echo ""
echo "--- 测试 10: JSON 格式一致性验证 ---"

for action in "skill list" "session list" "provider list"; do
    OUT=$(AIAOS_CLI_DATA_DIR="$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_BIN" $action --format json 2>/dev/null)
    if echo "$OUT" | python3 -m json.tool >/dev/null 2>&1; then
        pass "$action --format json 合法"
    else
        fail "$action JSON 格式"
    fi
done

echo ""
echo "=================================="
echo "集成测试总结: $PASS passed, $FAIL failed"
echo "=================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
