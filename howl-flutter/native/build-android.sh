#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
ndk=${ANDROID_NDK_ROOT:-${1:-}}
zig=${ZIG:-$(command -v zig || true)}
if [[ -z "$ndk" || ! -d "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ]]; then
  echo 'ANDROID_NDK_ROOT or first argument must name Android NDK' >&2
  exit 2
fi
if [[ -z "$zig" ]]; then
  echo 'ZIG must name the tracked Howl compiler' >&2
  exit 2
fi
test "$($zig version)" = "$(cat "$repo/.zigversion")"

export ANDROID_NDK_ROOT="$ndk"
"$root/build-deps-android.sh" "$ndk"
work=${HOWL_ANDROID_NATIVE_WORK:-$root/.work/android-arm64}
prefix="$work/prefix"
toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"

overlay="$root/ndk-overlay"
mkdir -p "$overlay"
python3 - "$toolchain/sysroot/usr/include/stdlib.h" "$overlay/stdlib.h" <<'PY'
import pathlib,re,sys
src=pathlib.Path(sys.argv[1]).read_text()
src=re.sub(r'\[_(?:Nonnull|Nullable)(?:\s+([0-9]+))?\]', lambda m: '['+(m.group(1) or '')+']', src)
pathlib.Path(sys.argv[2]).write_text(src)
PY

rm -rf "$root/.zig-cache" "$root/zig-out"
( cd "$root" && "$zig" build \
  -Dtarget=aarch64-linux-android \
  -Doptimize=ReleaseFast \
  -Drepo="$repo" \
  -Dndk="$ndk" \
  -Ddeps="$prefix"
)

obj="$root/zig-out/howl_flutter_native_host.o"
out_dir="$root/android/arm64-v8a"
out="$out_dir/libhowl_native_host.so"
mkdir -p "$out_dir"
cxx="$toolchain/bin/aarch64-linux-android24-clang++"
"$cxx" -shared -fPIC \
  -Wl,-soname,libhowl_native_host.so \
  -Wl,--no-undefined \
  "$obj" \
  "$prefix/lib/libharfbuzz.a" \
  "$prefix/lib/libfreetype.a" \
  -static-libstdc++ -lm -ldl \
  -o "$out"

"$toolchain/bin/llvm-readelf" -d "$out" >"$work/native-host-dynamic.txt"
if grep -Eq 'NEEDED.*(harfbuzz|freetype)' "$work/native-host-dynamic.txt"; then
  echo 'private text dependency leaked as dynamic Android ABI' >&2
  exit 1
fi
"$toolchain/bin/llvm-nm" -D --defined-only "$out" >"$work/native-host-symbols.txt"
while IFS= read -r symbol; do
  grep -q " $symbol$" "$work/native-host-symbols.txt"
done <"$root/ffi-symbols.txt"
file "$out"
sha256sum "$out"
echo "HOWL_ANDROID_NATIVE_HOST_OK output=$out"
