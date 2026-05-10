#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_runtime="$repo_root/howl-hosts/howl-android-host/src/main/java/howl/term/Terminal.java"
linux_runtime="$repo_root/howl-term/src/howl_term.zig"

if [[ ! -f "$linux_runtime" ]]; then
  echo "missing howl-term owner: $linux_runtime" >&2
  exit 1
fi

if [[ ! -f "$android_runtime" ]]; then
  echo "host_runtime_surface_skip=missing_android_runtime"
  exit 0
fi

mapfile -t android_methods < <(
  perl -ne '
    if (/public\s+(?:static\s+)?(?:final\s+)?[\w<>\[\], ?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/) {
      next if $1 eq "Terminal";
      print "$1\n";
    }
  ' "$android_runtime" | sort -u
)

mapfile -t linux_methods < <(
  perl -ne '
    print "$1\n" if /^\s*pub fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/;
  ' "$linux_runtime" | sort -u
)

shared_methods=(
  currentScrollbackCount
  currentScrollbackOffset
  deinit
  followLiveBottom
  init
  isAlternateScreen
  presentAck
  publishInputBytes
  renderFrameSized
  setFontSizePx
  setScrollbackOffset
  state
  surfaceHandle
  viewportRows
  waitRenderWake
)

android_only_methods=(
  bindNativeMethods
  hasOutputProof
  isAlive
  setCellSizePx
  setFallbackFontPaths
  setPrimaryFontPath
)

linux_only_methods=(
  beginSelection
  clearSelection
  copyHyperlinkUriAtPixel
  copyTabTitle
  drainPendingClipboardSet
  finishSelection
  hasRenderWork
  publishInputKey
  publishMouseEvent
  publishPaste
  selectionInProgress
  setInputFocus
  updateSelection
)

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

ensure_in_list() {
  local label="$1"
  local method="$2"
  shift 2
  if ! contains "$method" "$@"; then
    echo "$label: unexpected method '$method'" >&2
    exit 1
  fi
}

for method in "${shared_methods[@]}"; do
  contains "$method" "${android_methods[@]}" || { echo "android runtime missing shared method '$method'" >&2; exit 1; }
  contains "$method" "${linux_methods[@]}" || { echo "linux runtime missing shared method '$method'" >&2; exit 1; }
done

for method in "${android_methods[@]}"; do
  ensure_in_list "android runtime surface drift" "$method" "${shared_methods[@]}" "${android_only_methods[@]}"
done

for method in "${linux_methods[@]}"; do
  ensure_in_list "linux runtime surface drift" "$method" "${shared_methods[@]}" "${linux_only_methods[@]}"
done

echo "host_runtime_surface_ok=1"
