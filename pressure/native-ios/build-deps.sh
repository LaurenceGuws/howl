#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
work=${HOWL_IOS_NATIVE_WORK:-${RUNNER_TEMP:-$root/.work}/howl-ios-native}
src="$work/src"
build="$work/build"
prefix="$work/prefix"
mkdir -p "$src" "$build" "$prefix"

sdk=$(xcrun --sdk iphoneos --show-sdk-path)
clang=$(xcrun --sdk iphoneos --find clang)
clangxx=$(xcrun --sdk iphoneos --find clang++)
ar=$(xcrun --sdk iphoneos --find ar)
strip=$(xcrun --sdk iphoneos --find strip)
pkgconfig=$(command -v pkg-config)
meson=$(command -v meson)
ninja=$(command -v ninja)

echo "sdk=$sdk"
echo "clang=$clang"
echo "meson=$($meson --version)"
echo "ninja=$($ninja --version)"
echo "pkg-config=$($pkgconfig --version)"

cross="$work/ios-arm64.ini"
cat >"$cross" <<EOF
[binaries]
c = '$clang'
cpp = '$clangxx'
ar = '$ar'
strip = '$strip'
pkg-config = '$pkgconfig'

[built-in options]
c_args = ['-target', 'arm64-apple-ios15.0', '-isysroot', '$sdk']
c_link_args = ['-target', 'arm64-apple-ios15.0', '-isysroot', '$sdk']
cpp_args = ['-target', 'arm64-apple-ios15.0', '-isysroot', '$sdk']
cpp_link_args = ['-target', 'arm64-apple-ios15.0', '-isysroot', '$sdk']

[host_machine]
system = 'darwin'
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
  xcrun lipo -info "$lib"
done
nm -gU "$prefix/lib/libharfbuzz.a" >"$work/harfbuzz-symbols.txt"
grep -q ' _hb_shape$' "$work/harfbuzz-symbols.txt"
grep -q ' _hb_ft_font_create$' "$work/harfbuzz-symbols.txt"

cat >"$work/smoke.cc" <<'EOF'
#include <ft2build.h>
#include FT_FREETYPE_H
#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ft.h>
int main(void) {
  FT_Library ft = nullptr;
  if (FT_Init_FreeType(&ft) != 0) return 2;
  hb_buffer_t* b = hb_buffer_create();
  hb_buffer_destroy(b);
  FT_Done_FreeType(ft);
  return 0;
}
EOF

"$clangxx" \
  -target arm64-apple-ios15.0 \
  -isysroot "$sdk" \
  -I"$prefix/include/freetype2" \
  -I"$prefix/include" \
  "$work/smoke.cc" \
  "$prefix/lib/libharfbuzz.a" \
  "$prefix/lib/libfreetype.a" \
  -lc++ \
  -o "$work/howl-text-ios-smoke"

file "$work/howl-text-ios-smoke"
xcrun lipo -info "$work/howl-text-ios-smoke"

echo "HOWL_IOS_TEXT_DEPS_OK prefix=$prefix"
