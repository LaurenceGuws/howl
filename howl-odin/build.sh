#!/usr/bin/env bash
set -euo pipefail

module_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$module_root/.." && pwd)
bridge_root="$module_root/native"
output_root="$module_root/zig-out/bin"
bridge_lib="$bridge_root/zig-out/lib/libhowl_odin_bridge.so"

expected_zig=$(cat "$repo_root/.zigversion")
actual_zig=$(zig version)
[[ $actual_zig == "$expected_zig" ]] || {
  printf 'howl-odin: Zig mismatch: expected %s, got %s\n' "$expected_zig" "$actual_zig" >&2
  exit 1
}

expected_odin=$(cat "$module_root/.odinversion")
actual_odin=$(odin version | awk '{print $3}')
[[ $actual_odin == "$expected_odin" ]] || {
  printf 'howl-odin: Odin mismatch: expected %s, got %s\n' "$expected_odin" "$actual_odin" >&2
  exit 1
}

(
  cd "$bridge_root"
  zig build test -Doptimize=ReleaseSafe
  zig build install -Doptimize=ReleaseSafe
)

mkdir -p "$output_root"
odin check "$module_root" -collection:bridge="$bridge_root/zig-out/lib"
odin build "$module_root" \
  -collection:bridge="$bridge_root/zig-out/lib" \
  -out:"$output_root/howl-odin" \
  -debug
cp "$bridge_lib" "$output_root/"

printf 'howl-odin: built %s\n' "$output_root/howl-odin"
