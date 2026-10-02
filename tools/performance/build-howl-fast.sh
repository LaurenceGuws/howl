#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
module_root="$repo_root/howl-odin"
bridge_root="$module_root/native"
out=${HORSES_HOWL_FAST_ROOT:-"$HOME/.local/state/howl-performance-index/howl-fast"}

expected_zig=$(cat "$repo_root/.zigversion")
actual_zig=$(zig version)
[[ $actual_zig == "$expected_zig" ]] || { echo "Zig mismatch: expected $expected_zig, got $actual_zig" >&2; exit 1; }
expected_odin=$(cat "$module_root/.odinversion")
actual_odin=$(odin version | awk '{print $3}')
[[ $actual_odin == "$expected_odin" ]] || { echo "Odin mismatch: expected $expected_odin, got $actual_odin" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out/bin" "$out/bridge"
(
  cd "$bridge_root"
  zig build test -Doptimize=ReleaseFast
  zig build install -Doptimize=ReleaseFast --prefix "$out/bridge"
)
odin check "$module_root" -collection:bridge="$out/bridge/lib"
odin build "$module_root" \
  -collection:bridge="$out/bridge/lib" \
  -out:"$out/bin/howl-odin" \
  -o:speed
cp "$out/bridge/lib/libhowl_odin_bridge.so" "$out/bin/libhowl_odin_bridge.so"
cp "$module_root/packaging/howl-window-icon.bmp" "$out/bin/howl-window-icon.bmp"

"$out/bin/howl-odin" --version
sha256sum "$out/bin/howl-odin" "$out/bin/libhowl_odin_bridge.so"
