#!/usr/bin/env bash
# AIAOS-CLI 运行时同步脚本
# R5002: 将开发环境的代码同步到运行时目录
#
# 用法:
#   bash scripts/sync-to-runtime.sh --dry-run    # 仅预览
#   bash scripts/sync-to-runtime.sh --apply      # 执行同步
# 退出码: 0=成功, 1=失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Dry-run 模式，不会实际修改文件"
elif [[ "${1:-}" == "--apply" ]]; then
    DRY_RUN=false
else
    echo "用法: bash scripts/sync-to-runtime.sh [--dry-run|--apply]"
    exit 1
fi

echo "============================================"
echo "AIAOS-CLI 运行时同步 (sync-to-runtime)"
echo "============================================"

RUNTIME_DIR="$HOME/.aiaos"
RUNTIME_ELISP="$RUNTIME_DIR/elisp"
RUNTIME_BIN="$RUNTIME_DIR/bin"

# 1. 同步 elisp 模块
echo ""
echo "--- 1. 同步 elisp 模块 ---"

for elfile in "$PROJECT_DIR"/elisp/aiaos-cli*.el; do
    [ -f "$elfile" ] || continue
    relpath="$(basename "$elfile")"
    target="$RUNTIME_ELISP/$relpath"

    if [ ! -d "$RUNTIME_ELISP" ]; then
        if [ "$DRY_RUN" = false ]; then
            mkdir -p "$RUNTIME_ELISP"
        fi
        log_info "创建目录: $RUNTIME_ELISP"
    fi

    if [ ! -f "$target" ] || [ "$(stat -c %Y "$elfile")" -gt "$(stat -c %Y "$target" 2>/dev/null || echo 0)" ]; then
        if [ "$DRY_RUN" = false ]; then
            cp "$elfile" "$target"
        fi
        log_success "同步: $relpath"
    else
        log_info "跳过 (已是最新): $relpath"
    fi
done

# 2. 同步 bin/aiaos-cli
echo ""
echo "--- 2. 同步 bin/aiaos-cli ---"

BIN_SRC="$PROJECT_DIR/bin/aiaos-cli"
BIN_TARGET="$RUNTIME_BIN/aiaos-cli"

if [ ! -d "$RUNTIME_BIN" ]; then
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$RUNTIME_BIN"
    fi
    log_info "创建目录: $RUNTIME_BIN"
fi

if [ ! -f "$BIN_TARGET" ] || [ "$(stat -c %Y "$BIN_SRC")" -gt "$(stat -c %Y "$BIN_TARGET" 2>/dev/null || echo 0)" ]; then
    if [ "$DRY_RUN" = false ]; then
        cp "$BIN_SRC" "$BIN_TARGET"
        chmod +x "$BIN_TARGET"
    fi
    log_success "同步: aiaos-cli"
else
    log_info "跳过 (已是最新): aiaos-cli"
fi

# 3. 同步 skills
echo ""
echo "--- 3. 同步 skills ---"

SKILLS_SRC="$PROJECT_DIR/skills"
SKILLS_TARGET="$RUNTIME_DIR/skills"

if [ -d "$SKILLS_SRC" ]; then
    for skill_dir in "$SKILLS_SRC"/*/; do
        skill_name=$(basename "$skill_dir")
        target="$SKILLS_TARGET/$skill_name"

        if [ ! -f "$target/skill.yaml" ] || [ "$(stat -c %Y "$skill_dir/skill.yaml")" -gt "$(stat -c %Y "$target/skill.yaml" 2>/dev/null || echo 0)" ]; then
            if [ "$DRY_RUN" = false ]; then
                mkdir -p "$target"
                cp -r "$skill_dir"/* "$target/"
            fi
            log_success "同步技能: $skill_name"
        else
            log_info "跳过 (已是最新): $skill_name"
        fi
    done
fi

# 4. 验证
echo ""
echo "--- 4. 同步验证 ---"

if [ "$DRY_RUN" = false ]; then
    SYNCED_ELISP=$(find "$RUNTIME_ELISP" -name "aiaos-cli*.el" 2>/dev/null | wc -l)
    log_success "运行时 elisp 模块: $SYNCED_ELISP 个"

    if [ -f "$RUNTIME_BIN/aiaos-cli" ]; then
        log_success "运行时 bin: 存在"
    fi

    if [ -d "$RUNTIME_DIR/skills" ]; then
        SYNCED_SKILLS=$(find "$RUNTIME_DIR/skills" -name "skill.yaml" 2>/dev/null | wc -l)
        log_success "运行时技能: $SYNCED_SKILLS 个"
    fi
else
    log_info "Dry-run 完成，未实际修改"
fi

echo ""
echo "============================================"
log_success "运行时同步完成"
echo "============================================"
