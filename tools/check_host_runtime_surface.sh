#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_runtime="$repo_root/howl-hosts/howl-android-host/src/main/java/howl/term/terminal/Api.java"
android_ffi="$repo_root/howl-hosts/howl-android-host/src/main/java/howl/term/terminal/Ffi.java"
zig_ffi="$repo_root/howl-term/src/ffi.zig"
zig_root="$repo_root/howl-term/src/howl_term.zig"

if [[ ! -f "$zig_root" ]]; then
  echo "missing howl-term owner: $zig_root" >&2
  exit 1
fi

if [[ ! -f "$android_runtime" || ! -f "$android_ffi" ]]; then
  echo "missing android runtime owner or ffi owner" >&2
  exit 1
fi

mapfile -t android_methods < <(
  perl -ne '
    if (/public\s+(?:static\s+)?(?:final\s+)?[\w.<>\[\], ?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/) {
      next if $1 eq "Api";
      print "$1\n";
    }
  ' "$android_runtime" | sort -u
)

mapfile -t android_ffi_methods < <(
  perl -ne '
    if (/public\s+static\s+native\s+[\w.<>\[\], ?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/) {
      print "$1\n";
    }
  ' "$android_ffi" | sort -u
)

mapfile -t zig_ffi_methods < <(
  perl -ne '
    print "$1\n" if /^\s*pub fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/;
  ' "$zig_ffi" | sort -u
)

terminal_methods=(
  available
  deinit
  isAlive
  wakeSnapshotWaiters
  syncFrameGeometry
  needsFrame
  needsPrepare
  hasQueuedRenderWork
  awaitRenderWake
  prepareNextFrame
  renderReadyFrame
  surfaceState
  renderedSnapshotSeq
  setRuntimeBackpressure
  setCellSizePx
  setFontSizePx
  setPrimaryFontPath
  setFallbackFontPaths
  publishInputBytes
  publishInputKey
  publishPaste
  publishMouseEvent
  setInputFocus
  copyCurrentTitle
  drainPendingClipboardSet
  scrollState
  followLiveBottom
  setScrollbackOffset
  setHoveredLinkAtPixel
  copyHyperlinkUriAtPixel
  selectionInProgress
  beginSelection
  updateSelection
  finishSelection
  renderedTextContains
)

terminal_only_methods=(
  start
)

ffi_required_methods=(
  createWithStartPath
  destroy
  isSessionAlive
  wakeSnapshotWaiters
  syncFrameGeometry
  needsFrame
  needsPrepare
  hasQueuedRenderWork
  awaitRenderWake
  prepareNextFrame
  renderReadyFrame
  surfaceState
  renderedSnapshotSeq
  setRuntimeBackpressure
  setFontSizePx
  setPrimaryFontPath
  clearFallbackFontPaths
  addFallbackFontPath
  publishInputBytes
  publishInputKey
  publishPaste
  publishMouseEvent
  setInputFocus
  copyCurrentTitle
  drainPendingClipboardSet
  scrollState
  followLiveBottom
  setScrollbackOffset
  setHoveredLinkAtPixel
  copyHyperlinkUriAtPixel
  selectionInProgress
  beginSelection
  updateSelection
  finishSelection
  renderedTextContains
)

ffi_constant_methods=(
  modShift modAlt modCtrl
  keyEnter keyTab keyBackspace keyEscape keyUp keyDown keyLeft keyRight keyInsert keyDelete keyHome keyEnd keyPageup keyPagedown
  keyF1 keyF2 keyF3 keyF4 keyF5 keyF6 keyF7 keyF8 keyF9 keyF10 keyF11 keyF12
  mouseButtonNone mouseButtonLeft mouseButtonMiddle mouseButtonRight mouseButtonWheelUp mouseButtonWheelDown
  mousePress mouseRelease mouseMove mouseWheel
)

ffi_to_zig_methods=(
  createWithStartPath
  destroy
  isSessionAlive
  wakeSnapshotWaiters
  syncFrameGeometry
  needsFrame
  needsPrepare
  hasQueuedRenderWork
  awaitRenderWake
  prepareNextFrame
  renderReadyFrame
  surfaceState
  renderedSnapshotSeq
  setRuntimeBackpressure
  setFontSizePx
  setPrimaryFontPath
  clearFallbackFontPaths
  addFallbackFontPath
  publishInputBytes
  publishInputKey
  publishPaste
  publishMouseEvent
  setInputFocus
  copyCurrentTitle
  drainPendingClipboardSet
  scrollState
  followLiveBottom
  setScrollbackOffset
  copyHyperlinkUriAtPixel
  selectionInProgress
  beginSelection
  updateSelection
  finishSelection
  renderedTextContains
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

for method in "${terminal_methods[@]}"; do
  contains "$method" "${android_methods[@]}" || { echo "android runtime missing terminal method '$method'" >&2; exit 1; }
done

for method in "${terminal_only_methods[@]}"; do
  contains "$method" "${android_methods[@]}" || { echo "android runtime missing terminal-only method '$method'" >&2; exit 1; }
done

for method in "${android_methods[@]}"; do
  ensure_in_list "android runtime surface drift" "$method" "${terminal_methods[@]}" "${terminal_only_methods[@]}"
done

for method in "${ffi_required_methods[@]}"; do
  contains "$method" "${android_ffi_methods[@]}" || { echo "android ffi missing method '$method'" >&2; exit 1; }
done

for method in "${android_ffi_methods[@]}"; do
  ensure_in_list "android ffi surface drift" "$method" "${ffi_required_methods[@]}" "${ffi_constant_methods[@]}" available
done

for method in "${ffi_to_zig_methods[@]}"; do
  contains "$method" "${zig_ffi_methods[@]}" || { echo "shared ffi missing Zig method '$method'" >&2; exit 1; }
done

echo "host_runtime_surface_ok=1"
