#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
zig=${ZIG:-$(command -v zig || true)}
if [[ -z "$zig" ]]; then
  echo 'ZIG must name the tracked Howl compiler' >&2
  exit 2
fi
test "$($zig version)" = "$(cat "$repo/.zigversion")"

freetype_include=$(
  pkg-config --cflags-only-I freetype2 |
    tr ' ' '\n' |
    sed -n 's/^-I//p' |
    grep '/freetype2$' |
    sed -n '1p'
)
if [[ -z "$freetype_include" ]]; then
  echo 'freetype2 include directory not found through pkg-config' >&2
  exit 2
fi

rm -rf "$root/.zig-cache" "$root/zig-out"
( cd "$root" && "$zig" build \
  -Dtarget=native \
  -Doptimize=ReleaseFast \
  -Drepo="$repo" \
  -Dfreetype-include="$freetype_include"
)

obj="$root/zig-out/howl_flutter_native_host.o"
out="$root/libhowl_native_host.so"
${CXX:-c++} -shared -fPIC "$obj" $(pkg-config --libs freetype2 harfbuzz) -lm -ldl -o "$out"

nm -D --defined-only "$out" >"$root/.native-host-symbols.txt"
for symbol in howl_native_host_version howl_native_host_create howl_native_host_destroy howl_native_host_observe; do
  grep -q " $symbol$" "$root/.native-host-symbols.txt"
done
file "$out"
sha256sum "$out"
echo "HOWL_LINUX_NATIVE_HOST_OK output=$out"
