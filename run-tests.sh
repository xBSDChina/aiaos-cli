#!/usr/bin/env bash
# AIAOS-CLI 统一测试入口
# R5002: 替代 run-tests.sh，委托给 tests/run-all.sh
#
# 用法: bash run-tests.sh [--json] [--verbose]
# 退出码: 0=全部通过, 1=有失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} 委托到 tests/run-all.sh ..."
echo ""

bash "$SCRIPT_DIR/tests/run-all.sh" "$@"
