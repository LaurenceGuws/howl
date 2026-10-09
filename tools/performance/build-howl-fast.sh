#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
out=${HORSES_HOWL_FAST_ROOT:-"$HOME/.local/state/howl-performance-index/howl-fast"}
expected_zig=$(cat "$repo_root/.zigversion")
actual_zig=$(zig version)
[[ $actual_zig == "$expected_zig" ]] || { echo "Zig mismatch: expected $expected_zig, got $actual_zig" >&2; exit 1; }

cd "$repo_root/howl-app"
zig build install check test -Doptimize=ReleaseFast --prefix "$out"
"$out/bin/howl-app" --version
sha256sum "$out/bin/howl-app"
