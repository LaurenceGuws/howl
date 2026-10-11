#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS native dependencies require macOS/Xcode' >&2
  exit 2
fi

work=${HOWL_IOS_NATIVE_WORK:-$root/.work/ios-arm64}
src="$work/src"
build="$work/build"
prefix="$work/prefix"
stamp="$work/deps.stamp"
mkdir -p "$src" "$build"

freetype_commit=0a0221a1347e2f1e07c395263540026e9a0aa7c7
harfbuzz_commit=ab5ecbb83985034a76214ac0b2b833dcd590d774
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
clang=$(xcrun --sdk iphoneos --find clang)
clangxx=$(xcrun --sdk iphoneos --find clang++)
ar=$(xcrun --sdk iphoneos --find ar)
strip=$(xcrun --sdk iphoneos --find strip)
pkgconfig=$(command -v pkg-config)
meson=$(command -v meson)
ninja=$(command -v ninja)
wanted="sdk=$(basename "$sdk") freetype=$freetype_commit harfbuzz=$harfbuzz_commit"

if [[ -f "$stamp" && "$(cat "$stamp")" == "$wanted" && \
      -f "$prefix/lib/libfreetype.a" && -f "$prefix/lib/libharfbuzz.a" ]]; then
  echo "HOWL_IOS_TEXT_DEPS_CACHED prefix=$prefix"
  exit 0
fi

cross="$work/ios-arm64.ini"
cat >"$cross" <<CROSS
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
CROSS

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

fetch_commit https://github.com/freetype/freetype.git "$freetype_commit" "$src/freetype"
fetch_commit https://github.com/harfbuzz/harfbuzz.git "$harfbuzz_commit" "$src/harfbuzz"
rm -rf "$build/freetype" "$build/harfbuzz" "$prefix"
mkdir -p "$prefix"

"$meson" setup "$build/freetype" "$src/freetype" \
  --cross-file "$cross" --prefix "$prefix" --libdir lib \
  --buildtype release --default-library static \
  -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled \
  -Dtests=disabled -Dzlib=disabled
"$meson" compile -C "$build/freetype"
"$meson" install -C "$build/freetype"

PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" setup "$build/harfbuzz" "$src/harfbuzz" \
  --cross-file "$cross" --prefix "$prefix" --libdir lib \
  --buildtype release --default-library static \
  -Dbenchmark=disabled -Dcairo=disabled -Dchafa=disabled -Ddocs=disabled \
  -Dfontations=disabled -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled \
  -Dgpu=disabled -Dgraphite2=disabled -Dicu=disabled -Dintrospection=disabled \
  -Dpng=disabled -Draster=disabled -Dsubset=disabled -Dtests=disabled \
  -Dutilities=disabled -Dvector=disabled -Dzlib=disabled
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" compile -C "$build/harfbuzz"
PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
"$meson" install -C "$build/harfbuzz"

for lib in "$prefix/lib/libfreetype.a" "$prefix/lib/libharfbuzz.a"; do
  test -f "$lib"
  file "$lib"
  xcrun lipo -info "$lib"
done
nm -gU "$prefix/lib/libharfbuzz.a" >"$work/harfbuzz-symbols.txt"
grep -q ' _hb_shape$' "$work/harfbuzz-symbols.txt"
grep -q ' _hb_ft_font_create$' "$work/harfbuzz-symbols.txt"
printf '%s\n' "$wanted" >"$stamp"
echo "HOWL_IOS_TEXT_DEPS_OK prefix=$prefix"
