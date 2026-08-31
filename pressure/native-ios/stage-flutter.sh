#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
native="$root/pressure/native-ios"
work=${HOWL_IOS_NATIVE_WORK:-${RUNNER_TEMP:-$native/.work}/howl-ios-native}
prefix="$work/prefix"
dest="$root/howl-flutter/ios/NativePressure"
host="$native/zig-out/howl_native_host_ios.o"
canary="$native/zig-out/howl_native_canary_ios.o"
for path in "$host" "$canary" "$prefix/lib/libharfbuzz.a" "$prefix/lib/libfreetype.a"; do test -f "$path"; done
rm -rf "$dest"; mkdir -p "$dest"
xcrun libtool -static -o "$dest/libhowl_ios_native.a" \
  "$host" "$canary" "$prefix/lib/libharfbuzz.a" "$prefix/lib/libfreetype.a"
file "$dest/libhowl_ios_native.a"
xcrun lipo -info "$dest/libhowl_ios_native.a"
nm -gU "$dest/libhowl_ios_native.a" >"$dest/symbols.txt"
for symbol in howl_native_host_version howl_native_host_create howl_native_host_observe \
  howl_native_control_create howl_native_control_committed_text howl_native_control_mouse \
  howl_ios_native_canary_version howl_ios_native_render_hcr1; do
  grep -q " _$symbol$" "$dest/symbols.txt"
done
echo "HOWL_IOS_NATIVE_HOST_STAGED library=$dest/libhowl_ios_native.a"
