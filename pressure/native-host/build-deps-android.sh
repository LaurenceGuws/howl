#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
ndk=${ANDROID_NDK_ROOT:-${1:-}}
if [[ -z "$ndk" || ! -d "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ]]; then
  echo 'ANDROID_NDK_ROOT or first argument must name Android NDK' >&2
  exit 2
fi
work=${HOWL_ANDROID_NATIVE_WORK:-$root/.work}
src="$work/src"
build="$work/build"
prefix="$work/prefix"
mkdir -p "$src" "$build" "$prefix"

toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
api=24
cc="$toolchain/bin/aarch64-linux-android${api}-clang"
cxx="$toolchain/bin/aarch64-linux-android${api}-clang++"
ar="$toolchain/bin/llvm-ar"
strip="$toolchain/bin/llvm-strip"
pkgconfig=$(command -v pkg-config)
meson=$(command -v meson)
ninja=$(command -v ninja)

echo "ndk=$ndk"
echo "cc=$cc"
echo "meson=$($meson --version)"
echo "ninja=$($ninja --version)"
echo "pkg-config=$($pkgconfig --version)"

cross="$work/android-arm64.ini"
cat >"$cross" <<EOF
[binaries]
c = '$cc'
cpp = '$cxx'
ar = '$ar'
strip = '$strip'
pkg-config = '$pkgconfig'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
EOF

fetch_commit() {
  local url=$1 commit=$2 dest=$3
  if [[ ! -d "$dest/.git" ]]; then
    rm -rf "$dest"
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
  fi
  git -C "$dest" fetch -q --depth=1 origin "$commit"
  git -C "$dest" checkout -q --detach FETCH_HEAD
  test "$(git -C "$dest" rev-parse HEAD)" = "$commit"
}

# Exact upstream commits already pressure-proven on iPhoneOS.
freetype_commit=0a0221a1347e2f1e07c395263540026e9a0aa7c7
harfbuzz_commit=ab5ecbb83985034a76214ac0b2b833dcd590d774
fetch_commit https://github.com/freetype/freetype.git "$freetype_commit" "$src/freetype"
fetch_commit https://github.com/harfbuzz/harfbuzz.git "$harfbuzz_commit" "$src/harfbuzz"

echo "freetype=$freetype_commit"
echo "harfbuzz=$harfbuzz_commit"

rm -rf "$build/freetype" "$build/harfbuzz" "$prefix"
mkdir -p "$prefix"

"$meson" setup "$build/freetype" "$src/freetype" \
  --cross-file "$cross" \
  --prefix "$prefix" \
  --libdir lib \
  --buildtype release \
  --default-library static \
  -Dbrotli=disabled \
  -Dbzip2=disabled \
  -Dharfbuzz=disabled \
  -Dpng=disabled \
  -Dtests=disabled \
  -Dzlib=disabled
"$meson" compile -C "$build/freetype"
"$meson" install -C "$build/freetype"

PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" setup "$build/harfbuzz" "$src/harfbuzz" \
  --cross-file "$cross" \
  --prefix "$prefix" \
  --libdir lib \
  --buildtype release \
  --default-library static \
  -Dbenchmark=disabled \
  -Dcairo=disabled \
  -Dchafa=disabled \
  -Ddocs=disabled \
  -Dfontations=disabled \
  -Dfreetype=enabled \
  -Dglib=disabled \
  -Dgobject=disabled \
  -Dgpu=disabled \
  -Dgraphite2=disabled \
  -Dicu=disabled \
  -Dintrospection=disabled \
  -Dpng=disabled \
  -Draster=disabled \
  -Dsubset=disabled \
  -Dtests=disabled \
  -Dutilities=disabled \
  -Dvector=disabled \
  -Dzlib=disabled
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" compile -C "$build/harfbuzz"
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" install -C "$build/harfbuzz"

for lib in "$prefix/lib/libfreetype.a" "$prefix/lib/libharfbuzz.a"; do
  test -f "$lib"
  file "$lib"
  "$ar" t "$lib" >/dev/null
done
"$toolchain/bin/llvm-nm" -g "$prefix/lib/libharfbuzz.a" >"$work/harfbuzz-symbols.txt"
grep -q ' hb_shape$' "$work/harfbuzz-symbols.txt"
grep -q ' hb_ft_font_create$' "$work/harfbuzz-symbols.txt"

echo "HOWL_ANDROID_TEXT_DEPS_OK prefix=$prefix"
