#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
version=3.47.4
expected_head=9584c6713b324636289d067944a46fd6b49df14b
mode=${1:-profile}
case "$mode" in
  profile|release) ;;
  *) echo 'usage: build-engine.sh [profile|release]' >&2; exit 64 ;;
esac

lab="$root/temp/flutter-engine-$version"
src="$lab/engine/src"
patch="$root/tools/flutter-linux/flutter-$version-linux-vsync.patch"
depot="$root/temp/depot_tools"
[[ -d $lab/.git && -x $src/flutter/tools/gn ]] || {
  echo 'flutter-linux: run tools/flutter-linux/prepare-engine.sh first' >&2
  exit 1
}
[[ -x $depot/vpython3 ]] || {
  echo 'flutter-linux: depot_tools missing; run tools/flutter-linux/prepare-engine.sh first' >&2
  exit 1
}
actual=$(git -C "$lab" rev-parse HEAD)
[[ $actual == "$expected_head" ]] || {
  echo "flutter-linux: expected checkout $expected_head, got $actual" >&2
  exit 1
}

if git -C "$lab" apply --reverse --check "$patch" >/dev/null 2>&1; then
  : # already applied exactly
else
  if ! git -C "$lab" diff --quiet || ! git -C "$lab" diff --cached --quiet; then
    echo 'flutter-linux: checkout has unrelated source changes; refusing to patch' >&2
    exit 1
  fi
  git -C "$lab" apply --check "$patch"
  git -C "$lab" apply "$patch"
fi

cd "$src"
export PATH="$depot:$PATH"
flutter/tools/gn --runtime-mode="$mode" --no-lto
out="out/host_$mode"
ninja_bin="$lab/third_party/ninja/ninja"
[[ -x $ninja_bin ]] || ninja_bin=ninja

"$ninja_bin" -C "$out" -j2 \
  libflutter_linux_gtk.so gen_snapshot flutter_patched_sdk publish_headers_linux

# Keep the patch contract executable. The first test build is larger; later
# runs are incremental.
"$ninja_bin" -C "$out" -j2 flutter_linux_unittests
"$out/flutter_linux_unittests" \
  --gtest_filter='FlEngineTest.Vsync*:FlDisplayMonitorTest.*'

printf 'flutter-linux: patched %s engine ready at %s/%s\n' "$mode" "$src" "$out"
