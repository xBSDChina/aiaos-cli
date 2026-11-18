#!/usr/bin/env bash
# aiaos-cli-batch.sh - command line wrapper for the aiaos-cli Emacs package.
# Usage: aiaos-cli-batch.sh [--json] <command> [args...]
#
# This script runs the aiaos-cli Elisp environment in a headless Emacs
# (emacs-nox preferred, falls back to emacs) in --batch mode, so that the
# full aiaos-cli capability (system_info / session / context / skill / agent)
# can be driven from an automated shell script.
#
# Design notes:
#   - argv is serialised as JSON via AIAOS_CLI_ARGS_JSON so Emacs can parse
#     it with json-read-from-string (Emacs 27+), avoiding shell escaping.
#   - `--json' / `--no-json' are consumed here and surfaced to Emacs through
#     AIAOS_CLI_JSON so Emacs never sees them as unknown command-line options.
#   - `--help' / `-h' / `--version' are handled here and never reach Emacs.
#   - The `agent <message>' command is forwarded verbatim to
#     aiaos-cli-agent-run inside the Elisp environment, giving the batch
#     wrapper access to the full agent (LLM + tools + task completion) stack.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

JSON_MODE="f"
FILTERED_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --json)       JSON_MODE="t" ;;
    --no-json)    JSON_MODE="f" ;;
    --help|-h)
      cat <<'HELP'
aiaos-cli - AIAOS Framework Command Line Interface

Usage: aiaos-cli [--json] <command> [args...]

Global options:
  --json        Output JSON
  --no-json     Output human-readable text (default)
  --help, -h    Show this help
  --version     Show version

Commands:
  system_info check_cpu      CPU information
  system_info check_memory   Memory information
  system_info check_disk     Disk information
  system_info check_os       OS information
  system_info check_load     Load information
  system_info check_net      Network information
  session new [name]         Create new session
  session list               List sessions
  session current            Show current session
  session show [name]        Show session details
  session switch <name>      Switch session
  context show               Show current context
  skill list                 List skills
  skill search <query>       Search skills
  skill enable <name>        Enable skill
  skill disable <name>       Disable skill
  skill deps <name>          Show skill dependencies
  agent <message>            Run agent script: LLM + tools + task completion
  version                    Show version
  help                       Show help

Examples:
  aiaos-cli system_info check_cpu
  aiaos-cli --json system_info check_memory
  aiaos-cli skill list
  aiaos-cli agent "Summarise the project TODO list"
HELP
      exit 0
      ;;
    --version)
      cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown"
      exit 0
      ;;
    *) FILTERED_ARGS+=("$arg") ;;
  esac
done

export AIAOS_CLI_SCRIPT_DIR="$SCRIPT_DIR"
export AIAOS_CLI_JSON="$JSON_MODE"

# Serialise argv as JSON so Emacs can read it back without shell escaping.
ARGS_JSON="$({ python3 -c 'import sys,json; print(json.dumps(sys.argv[1:]))' "${FILTERED_ARGS[@]}"; })"
export AIAOS_CLI_ARGS_JSON="$ARGS_JSON"

# Prefer emacs-nox (headless) for automated batch use; fall back to emacs.
if [ -n "${EMACS_BIN:-}" ]; then
  EMACS_BIN="$EMACS_BIN"
elif command -v emacs-nox >/dev/null 2>&1; then
  EMACS_BIN="emacs-nox"
else
  EMACS_BIN="emacs"
fi

# Locate the yaml package directory (used by some aiaos modules) if present.
YAML_DIR=""
for d in "$HOME"/.emacs.d/elpa/yaml-*; do
  if [ -d "$d" ]; then YAML_DIR="$d"; break; fi
done

# Build a temporary Lisp source that loads the aiaos-cli environment and
# dispatches the command. Using a heredoc avoids shell escaping of quotes.
LISP_SRC="$(mktemp)"
trap 'rm -f "$LISP_SRC"' EXIT
cat > "$LISP_SRC" << LISP_EOF
(load-file (expand-file-name "lisp/init.el" "$SCRIPT_DIR"))
(setq command-line-args-left
      (append (json-read-from-string (getenv "AIAOS_CLI_ARGS_JSON")) nil))
(when (string= (or (getenv "AIAOS_CLI_JSON") "") "t")
  (setq aiaos-cli--json-mode t))
;; kill-emacs propagates the exit code AND prevents command-line-1 from
;; re-interpreting leftover args as file paths (long messages would trigger
;; "filename too long" file-error).
(kill-emacs (aiaos-cli-main command-line-args-left))
LISP_EOF

# --no-site-file is the reliable switch (Emacs 30 still loads site-start.d
# under -q alone). -Q would also disable user packages, which we do not want.
DEFAULT_FLAGS="--no-site-file --batch"
EMACS_FLAGS="${AIAOS_CLI_EMACS_FLAGS:-$DEFAULT_FLAGS}"

EMACS_CMD=()
# shellcheck disable=SC2086
EMACS_CMD+=("$EMACS_BIN" $EMACS_FLAGS)
EMACS_CMD+=(-L "$SCRIPT_DIR" -L "$SCRIPT_DIR/lisp")
if [ -n "$YAML_DIR" ]; then
  EMACS_CMD+=(-L "$YAML_DIR")
fi
EMACS_CMD+=(-l "$LISP_SRC")

"${EMACS_CMD[@]}"
