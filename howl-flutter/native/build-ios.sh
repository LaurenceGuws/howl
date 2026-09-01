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
mkdir -p "$dest"

rm -rf "$root/zig-out" "$root/.zig-cache"
(
  cd "$root"
  zig build \
    -Dtarget=aarch64-ios.15.0 \
    -Doptimize=ReleaseFast \
    -Drepo="$repo" \
    -Dfreetype-include="$prefix/include/freetype2" \
    -Dharfbuzz-include="$prefix/include" \
    -Dapple-sdk="$sdk"
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
for symbol in \
  howl_native_host_version howl_native_host_create howl_native_host_destroy howl_native_host_observe \
  howl_native_control_create howl_native_control_destroy howl_native_control_committed_text \
  howl_native_control_paste howl_native_control_named_key howl_native_control_unicode_key \
  howl_native_control_focus howl_native_control_resize howl_native_control_signal howl_native_control_mouse
do
  grep -q " _$symbol$" "$dest/symbols.txt"
done
echo "HOWL_IOS_NATIVE_HOST_OK library=$dest/libhowl_ios_native.a"
