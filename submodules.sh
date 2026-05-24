#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./submodules.sh <command>

Commands:
  status   Show submodule commit/status summary.
  sync     Sync urls and initialize/update submodules.
  update   Fast-forward submodules to their configured branch tips.
  foreach  Show branch + porcelain status for each submodule.
EOF
}

cd "$ROOT"

command="${1:-status}"

case "$command" in
  status)
    git submodule status
    ;;
  sync)
    git submodule sync --recursive
    git submodule update --init --recursive
    ;;
  update)
    git submodule sync --recursive
    git submodule update --init --remote --recursive
    ;;
  foreach)
    git submodule foreach 'printf "%s|branch:%s\n" "$sm_path" "$(git branch --show-current 2>/dev/null || true)"; git status --short'
    ;;
  *)
    usage
    exit 1
    ;;
esac
