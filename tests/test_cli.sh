#!/usr/bin/env bash
# AIAOS-CLI 测试脚本

set -euo pipefail

CLI_BIN="/home/shjiaye8/aiaos/aiaos-cli/bin/aiaos-cli"
export AIAOS_CLI_DATA_DIR="/tmp/aiaos-cli-test-$$"
export AIAOS_CLI_CONFIG_DIR="/tmp/aiaos-cli-test-config-$$"
export AIAOS_CLI_OUTPUT_FORMAT="json"

echo "=== AIAOS-CLI 测试开始 ==="
echo "数据目录: $AIAOS_CLI_DATA_DIR"
echo "配置目录: $AIAOS_CLI_CONFIG_DIR"

# 测试 1: 版本和帮助
echo ""
echo "--- 测试 1: 版本和帮助 ---"
$CLI_BIN --version
$CLI_BIN --help | head -20

# 测试 2: 环境检查
echo ""
echo "--- 测试 2: 环境检查 ---"
$CLI_BIN doctor check --format json | python3 -m json.tool

# 测试 3: 会话管理
echo ""
echo "--- 测试 3: 会话管理 ---"
$CLI_BIN session new --name "test-session" --project "/tmp/test-project" --description "测试会话" --format json | python3 -m json.tool

SESSION_ID=$($CLI_BIN session current --format json | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
echo "当前会话 ID: $SESSION_ID"

$CLI_BIN session list --format json | python3 -m json.tool

$CLI_BIN session show --id "$SESSION_ID" --format json | python3 -m json.tool

$CLI_BIN session archive --id "$SESSION_ID" --format json | python3 -m json.tool

$CLI_BIN session new --name "test-session-2" --format json | python3 -m json.tool
SESSION_ID2=$($CLI_BIN session current --format json | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")

$CLI_BIN session switch --id "$SESSION_ID2" --format json | python3 -m json.tool

$CLI_BIN session delete --id "$SESSION_ID" --force --format json | python3 -m json.tool

# 测试 4: 上下文管理
echo ""
echo "--- 测试 4: 上下文管理 ---"
$CLI_BIN context show --format json | python3 -m json.tool

$CLI_BIN context save --name "test-context" --session "$SESSION_ID2" --format json | python3 -m json.tool

CONTEXT_ID=$($CLI_BIN context list --format json | python3 -c "import json,sys; data=json.load(sys.stdin); print(data[0]['id'] if data else '')")
echo "上下文 ID: $CONTEXT_ID"

$CLI_BIN context show --format json | python3 -m json.tool

$CLI_BIN context load --id "$CONTEXT_ID" --format json | python3 -m json.tool

$CLI_BIN context list --format json | python3 -m json.tool

$CLI_BIN context export --id "$CONTEXT_ID" --file "/tmp/context-export.yaml" --format json | python3 -m json.tool

$CLI_BIN context clear --format json | python3 -m json.tool

# 测试 5: 技能管理
echo ""
echo "--- 测试 5: 技能管理 ---"
$CLI_BIN skill list --format json | python3 -m json.tool

# validate: 真实存在的技能应返回 success
$CLI_BIN skill validate --name hello-world --format json | python3 -m json.tool

# validate: 不存在的技能应报错（不再用 || true 静默吞掉）
if $CLI_BIN skill validate --name __nonexistent__ >/dev/null 2>&1; then
  echo "FAIL: validate 对不存在的技能应报错"; exit 1
else
  echo "PASS: validate 对不存在的技能正确报错"
fi

# run: 端到端调用真实技能命令
$CLI_BIN skill run --name hello-world --command hello --args '{"name":"AIAOS"}' --format json | python3 -m json.tool

# 测试 6: Agent 交互
echo ""
echo "--- 测试 6: Agent 交互 ---"
$CLI_BIN agent status --format json | python3 -m json.tool

$CLI_BIN agent chat --message "测试消息" --format json | python3 -m json.tool

$CLI_BIN agent delegate --task "测试任务" --agent default --format json | python3 -m json.tool

$CLI_BIN agent tool --tool read_file --args '{"path": "/etc/hostname"}' --format json | python3 -m json.tool

$CLI_BIN agent history --limit 10 --format json | python3 -m json.tool

# 测试 7: 项目管理
echo ""
echo "--- 测试 7: 项目管理 ---"
cd /tmp
$CLI_BIN project init --name "test-project" --template python --path "/tmp/test-aiaos-project" --format json | python3 -m json.tool

cd /tmp/test-aiaos-project
$CLI_BIN project status --format json | python3 -m json.tool

$CLI_BIN project info --format json | python3 -m json.tool

$CLI_BIN project sync --format json | python3 -m json.tool

$CLI_BIN project build --format json | python3 -m json.tool

$CLI_BIN project deploy --target local --env dev --format json | python3 -m json.tool

# 测试 8: 配置管理
echo ""
echo "--- 测试 8: 配置管理 ---"
$CLI_BIN config list --format json | python3 -m json.tool

$CLI_BIN config get --key core.log_level --format json | python3 -m json.tool

$CLI_BIN config set --key core.log_level --value debug --format json | python3 -m json.tool

$CLI_BIN config get --key core.log_level --format json | python3 -m json.tool

$CLI_BIN config validate --format json | python3 -m json.tool

$CLI_BIN config migrate --format json | python3 -m json.tool

# 测试 9: 日志管理
echo ""
echo "--- 测试 9: 日志管理 ---"
$CLI_BIN log list --format json | python3 -m json.tool

$CLI_BIN log tail --limit 5 --format json | python3 -m json.tool

$CLI_BIN log search --pattern "test" --limit 5 --format json | python3 -m json.tool

$CLI_BIN log analyze --format json | python3 -m json.tool

$CLI_BIN log export --output "/tmp/log-export.json" --format json | python3 -m json.tool

# 测试 10: 顶层 help 与 skill 子命令一致性（防回归）
echo ""
echo "--- 测试 10: help 一致性防回归 ---"
TOP_HELP=$($CLI_BIN --help 2>&1)
echo "$TOP_HELP" | grep -q "validate" || { echo "FAIL: 顶层 help 缺少 validate"; exit 1; }
echo "$TOP_HELP" | grep -q "run"       || { echo "FAIL: 顶层 help 缺少 run"; exit 1; }
echo "PASS: 顶层 help 包含 validate/run"

# 测试 11: skill info --format json 契约（防回归：不能输出 YAML）
echo ""
echo "--- 测试 11: skill info --format json ---"
INFO_JSON=$($CLI_BIN skill info --name hello-world --format json 2>/dev/null)
echo "$INFO_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['name']=='hello-world'; assert 'commands' in d" \
  || { echo "FAIL: skill info --format json 未返回合法 JSON"; exit 1; }
echo "PASS: skill info --format json 返回合法 JSON"

# 测试 12: skill run <skill>/<cmd> 位置参数简写（设计文档 §5 范式）
echo ""
echo "--- 测试 12: skill run shorthand ---"
set +e
RUN_OUT=$($CLI_BIN skill run hello-world/hello --args '{"name":"World"}' 2>/dev/null | grep -v '^\[')
RC=$?
set -e
echo "$RUN_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('message')=='Hello, World!'" \
  || { echo "FAIL: skill run <skill>/<cmd> 简写未生效"; exit 1; }
echo "PASS: skill run hello-world/hello 简写成功"

# 清理
echo ""
echo "--- 测试 13: skill run 短选项映射 (R850) ---"
R13=$($CLI_BIN skill run hello-world/hello 世界 -g=你好 2>/dev/null)
if echo "$R13" | grep -q "你好, 世界"; then
    echo "PASS: skill run 短选项 -g 映射为 greeting"
else
    echo "FAIL: skill run 短选项映射失败: $R13"
fi
R13b=$($CLI_BIN skill run hello-world/hello 世界 2>/dev/null)
if echo "$R13b" | grep -q "Hello, 世界"; then
    echo "PASS: skill run 位置参数透传 args.name"
else
    echo "FAIL: skill run 位置参数透传失败: $R13b"
fi

# R2112: 复合短选项 set -u 修复测试
echo ""
echo "--- 测试 14: 复合短选项 set -u 安全 (R2112) ---"
# 测试14a: 复合短选项无值在末尾（修复前崩溃）
R14a=$($CLI_BIN skill run string-tools/reverse --args '{"text":"hello"}' -ab 2>/dev/null)
if echo "$R14a" | grep -q '"status":"ok"'; then
    echo "PASS: 复合短选项 -ab 末尾不崩溃 (R2112 修复)"
else
    echo "FAIL: 复合短选项 -ab 末尾崩溃: $R14a"
fi
# 测试14b: 复合短选项带等号值
R14b=$($CLI_BIN skill run string-tools/reverse --args '{"text":"hello"}' -ab=xyz 2>/dev/null)
if echo "$R14b" | grep -q '"status":"ok"'; then
    echo "PASS: 复合短选项 -ab=xyz 带值解析 (R2112)"
else
    echo "FAIL: 复合短选项 -ab=xyz 解析失败: $R14b"
fi
# 测试14c: 复合短选项后跟值
R14c=$($CLI_BIN skill run string-tools/reverse --args '{"text":"hello"}' -ab value 2>/dev/null)
if echo "$R14c" | grep -q '"status":"ok"'; then
    echo "PASS: 复合短选项 -ab value 后跟值 (R2112)"
else
    echo "FAIL: 复合短选项 -ab value 后跟值失败: $R14c"
fi


# --- 测试 14: skill deps 依赖解析/拓扑排序/循环检测 (R1120) ---
echo "--- 测试 14: skill deps (R1120) ---"
# 注意: 前序测试(测试11)可能 export AIAOS_CLI_OUTPUT_FORMAT=json 造成格式泄漏，
# 此处显式指定 --format table 保证测试隔离 (R1130)
R14=$($CLI_BIN skill deps --name hello-world --format table 2>/dev/null)
if echo "$R14" | grep -q "加载顺序: hello-world" && echo "$R14" | grep -q "依赖解析通过"; then
    echo "PASS: skill deps 正常路径（无依赖技能）"
else
    echo "FAIL: skill deps 正常路径失败: $R14"
fi
R14b=$($CLI_BIN skill deps --name hello-world --format json 2>/dev/null)
if echo "$R14b" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['status']=='ok' and d['skills'][0]['skill']=='hello-world' and d['skills'][0]['cycles']==[]" 2>/dev/null; then
    echo "PASS: skill deps --format json 返回合法 JSON 且无循环"
else
    echo "FAIL: skill deps json 校验失败: $R14b"
fi
R14c=$($CLI_BIN skill deps --name __nonexistent__ 2>/dev/null; echo "rc=$?")
if echo "$R14c" | grep -q "技能不存在" && echo "$R14c" | grep -q "rc=1"; then
    echo "PASS: skill deps 对不存在技能正确报错(rc=1)"
else
    echo "FAIL: skill deps 不存在技能处理失败: $R14c"
fi
# R1140: set -e 安全写法——grep -c 零匹配返回1会终止脚本，必须 || true 兜底
R14d=$($CLI_BIN skill --help 2>/dev/null | grep -c "deps" || true)
if [ "${R14d:-0}" -ge 1 ]; then
    echo "PASS: skill help 包含 deps（文档-实现一致）"
else
    echo "FAIL: skill help 缺少 deps"
fi



echo "--- 测试 15: skill action --help 路由 R1230 ---"
# 子命令 --help 必须透传给 core/skill.sh，不能在主入口被顶层 show_help 拦截
R15a=$($CLI_BIN skill list --help 2>/dev/null)
if echo "$R15a" | grep -q "aiaos-cli skill"; then
    echo "PASS: skill list --help 路由到子命令 help"
else
    echo "FAIL: skill list --help 未路由到子命令 help: $R15a"
fi
R15b=$($CLI_BIN skill validate --help 2>/dev/null)
if echo "$R15b" | grep -q "validate"; then
    echo "PASS: skill validate --help 路由到子命令 help"
else
    echo "FAIL: skill validate --help 未路由到子命令 help: $R15b"
fi
# 顶层 --help 仍应显示顶层帮助
R15c=$($CLI_BIN --help 2>/dev/null)
if echo "$R15c" | grep -q "aiaos-cli <域> <动作>"; then
    echo "PASS: 顶层 --help 保持顶层帮助"
else
    echo "FAIL: 顶层 --help 被破坏: $R15c"
fi


echo "--- 测试 16: skill list table 不崩溃 (R1313) ---"
# 回归：含中文/单引号/特殊字符的 description 不能破坏 table 输出
R16a=$($CLI_BIN skill list --format table 2>&1)
if echo "$R16a" | grep -q "Traceback" || echo "$R16a" | grep -q "json.loads"; then
    echo "FAIL: skill list 输出含 Python 异常: $R16a"
else
    echo "PASS: skill list table 无 Python 异常"
fi
# 每个技能名必须出现在输出中
for skill in hello-world emacs-tools file-tools string-tools text-tools; do
    if echo "$R16a" | grep -q "$skill"; then
        echo "PASS: skill list 包含 $skill"
    else
        echo "FAIL: skill list 缺少 $skill"
    fi
done

echo "--- 测试 17: skill list --verbose 状态列 (R1313) ---"
R17=$($CLI_BIN skill list --format table --verbose 2>&1)
if echo "$R17" | grep -q "STATUS" && echo "$R17" | grep -q "enabled"; then
    echo "PASS: --verbose 输出 STATUS 列且含 enabled"
else
    echo "FAIL: --verbose 输出异常: $R17"
fi

echo "--- 测试 18: agent history 空历史不崩溃 (R1313) ---"
R18=$($CLI_BIN agent history 2>&1)
if echo "$R18" | grep -q "Traceback" || echo "$R18" | grep -q "json.loads"; then
    echo "FAIL: agent history 输出含 Python 异常: $R18"
else
    echo "PASS: agent history 无 Python 异常"
fi

echo ""
echo "=== 清理测试环境 ==="
rm -rf "$AIAOS_CLI_DATA_DIR" "$AIAOS_CLI_CONFIG_DIR" "/tmp/test-aiaos-project" "/tmp/context-export.yaml" "/tmp/log-export.json"

echo ""
echo "=== 所有测试完成 ==="
