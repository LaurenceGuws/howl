#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
work=${HOWL_IOS_NATIVE_WORK:-${RUNNER_TEMP:-$root/.work}/howl-ios-native}
prefix="$work/prefix"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)

test "$(zig version)" = "$(cat "$repo/.zigversion")"
for path in "$prefix/lib/libfreetype.a" "$prefix/lib/libharfbuzz.a"; do test -f "$path"; done

mkdir -p "$root/generated"
zig translate-c \
  -target aarch64-ios.15.0 \
  -lc \
  --sysroot "$sdk" \
  -isystem "$sdk/usr/include" \
  -I"$prefix/include/freetype2" \
  -I"$prefix/include" \
  "$root/native.h" >"$root/generated/native_c.zig"
grep -q 'pub extern fn FT_Init_FreeType' "$root/generated/native_c.zig"
grep -q 'pub extern fn hb_shape' "$root/generated/native_c.zig"
grep -q 'pub extern fn hb_ft_font_create' "$root/generated/native_c.zig"

(cd "$root" && zig build -Dtarget=aarch64-ios.15.0 -Doptimize=ReleaseFast)
host="$root/zig-out/howl_native_host_ios.o"
canary="$root/zig-out/howl_native_canary_ios.o"
for object in "$host" "$canary"; do
  test -f "$object"
  file "$object"
  xcrun lipo -info "$object"
done

nm -gU "$host" >"$work/host-symbols.txt"
for symbol in \
  howl_native_host_version \
  howl_native_host_create \
  howl_native_host_observe \
  howl_native_control_create \
  howl_native_control_committed_text \
  howl_native_control_named_key \
  howl_native_control_unicode_key \
  howl_native_control_focus \
  howl_native_control_resize \
  howl_native_control_mouse
do
  grep -q " _$symbol$" "$work/host-symbols.txt"
done
nm -gU "$canary" >"$work/canary-symbols.txt"
grep -q ' _howl_ios_native_canary_version$' "$work/canary-symbols.txt"
grep -q ' _howl_ios_native_render_hcr1$' "$work/canary-symbols.txt"

cat >"$work/howl-host-smoke.cc" <<'EOF2'
#include <cstddef>
#include <cstdint>
extern "C" uint32_t howl_native_host_version(void);
extern "C" void* howl_native_host_create(const uint8_t*, size_t, const uint8_t*, size_t, const uint8_t*, const size_t*, size_t);
extern "C" void* howl_native_control_create(const uint8_t*, size_t);
extern "C" uint32_t howl_ios_native_canary_version(void);
int main(void) {
  if (howl_native_host_version() != 1) return 10;
  if (howl_ios_native_canary_version() != 2) return 11;
  if (&howl_native_host_create == nullptr || &howl_native_control_create == nullptr) return 12;
  return 0;
}
EOF2
clangxx=$(xcrun --sdk iphoneos --find clang++)
"$clangxx" \
  -target arm64-apple-ios15.0 \
  -isysroot "$sdk" \
  "$work/howl-host-smoke.cc" \
  "$host" "$canary" \
  "$prefix/lib/libharfbuzz.a" "$prefix/lib/libfreetype.a" \
  -lc++ \
  -o "$work/howl-host-ios-smoke"
file "$work/howl-host-ios-smoke"
xcrun lipo -info "$work/howl-host-ios-smoke"
echo "HOWL_IOS_NATIVE_HOST_OBJECT_OK host=$host canary=$canary"
