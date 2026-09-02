#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS native host requires macOS/Xcode' >&2
  exit 2
fi

test "$(zig version)" = "$(cat "$repo/.zigversion")"
"$root/build-deps-ios.sh"
work=${HOWL_IOS_NATIVE_WORK:-$root/.work/ios-arm64}
prefix="$work/prefix"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
dest="$repo/howl-flutter/ios/NativeHost"
howl_text="$work/src/howl-text"
# Exact pre-split source snapshot. Its Zig package hash is identical to the
# standalone pin; this mirror remains reproducible even if the old remote URL moves.
howl_text_source_commit=88fb476bc60024c1f03c8c06e51019a5f8ac52bd
howl_text_hash=howl_text-0.1.6-dev-fp7jPoZZ2QBExKz8gj5T7MtGp3vVEUU_bDtdh_FhaHaW
mkdir -p "$dest" "$work/src"

if ! git -C "$repo" cat-file -e "$howl_text_source_commit^{commit}" 2>/dev/null; then
  git -C "$repo" fetch -q --depth=1 origin "$howl_text_source_commit"
fi
rm -rf "$howl_text"
mkdir -p "$howl_text"
git -C "$repo" archive "$howl_text_source_commit" howl-text | \
  tar -x -C "$howl_text" --strip-components=1
actual_hash=$(zig fetch "$howl_text")
test "$actual_hash" = "$howl_text_hash"
echo "HOWL_IOS_TEXT_SOURCE_OK source_commit=$howl_text_source_commit hash=$actual_hash"

rm -rf "$root/zig-out" "$root/.zig-cache"
(
  cd "$root"
  zig build \
    -Dtarget=aarch64-ios.15.0 \
    -Doptimize=ReleaseFast \
    -Drepo="$repo" \
    -Dfreetype-include="$prefix/include/freetype2" \
    -Dharfbuzz-include="$prefix/include" \
    -Dapple-sdk="$sdk" \
    -Dhowl-text-root="$howl_text"
)
object="$root/zig-out/howl_flutter_native_host.o"
test -f "$object"
file "$object"
xcrun lipo -info "$object"

xcrun libtool -static -o "$dest/libhowl_ios_native.a" \
  "$object" "$prefix/lib/libharfbuzz.a" "$prefix/lib/libfreetype.a"
file "$dest/libhowl_ios_native.a"
xcrun lipo -info "$dest/libhowl_ios_native.a"
nm -gU "$dest/libhowl_ios_native.a" >"$dest/symbols.txt"
while IFS= read -r symbol; do
  grep -q " _$symbol$" "$dest/symbols.txt"
done <"$root/ffi-symbols.txt"
echo "HOWL_IOS_NATIVE_HOST_OK library=$dest/libhowl_ios_native.a"
