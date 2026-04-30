#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mapfile -t repos < <(find "$ROOT" -type d -name .git -prune | sed 's|/\.git$||' | sort)

for repo in "${repos[@]}"; do
  rel="${repo#$ROOT/}"; [ "$repo" = "$ROOT" ] && rel="."

  # local file changes count (staged + unstaged + untracked)
  changes="$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

  # commits ahead of upstream
  ahead=0
  if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  fi

  if [ "$changes" -gt 0 ] || [ "$ahead" -gt 0 ]; then
    echo "$rel|changes:$changes|ahead:$ahead|commit and/or push needed"
  fi
done
