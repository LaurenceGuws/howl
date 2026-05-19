#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repos=("$ROOT")

if [ -f "$ROOT/.gitmodules" ]; then
  while read -r _ path; do
    repos+=("$ROOT/$path")
  done < <(git -C "$ROOT" config --file "$ROOT/.gitmodules" --get-regexp path 2>/dev/null || true)
fi

while IFS= read -r git_entry; do
  repo="${git_entry%/.git}"
  skip=0
  for known in "${repos[@]}"; do
    if [ "$known" = "$repo" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" -eq 0 ]; then
    repos+=("$repo")
  fi
done < <(find "$ROOT" -path "$ROOT/utils" -prune -o \( -type d -o -type f \) -name .git -print | sort)

for repo in "${repos[@]}"; do
  rel="${repo#$ROOT/}"; [ "$repo" = "$ROOT" ] && rel="."

  # local file changes count (staged + unstaged + untracked)
  status_args=(status --porcelain)
  if [ "$repo" = "$ROOT" ]; then
    status_args+=(--ignore-submodules=all)
  fi
  changes="$(git -C "$repo" "${status_args[@]}" 2>/dev/null | wc -l | tr -d ' ')"

  # commits ahead of upstream
  ahead=0
  if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  fi

  if [ "$changes" -gt 0 ] || [ "$ahead" -gt 0 ]; then
    echo "$rel|changes:$changes|ahead:$ahead|commit and/or push needed"
  fi
done
