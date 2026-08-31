#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/../.." && pwd)
endpoint=${1:-tcp://127.0.0.1:43134}
case "$endpoint" in
  tcp://127.0.0.1:*) port=${endpoint##*:} ;;
  *) echo "canary requires exact loopback TCP endpoint" >&2; exit 64 ;;
esac
[[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || {
  echo "invalid endpoint port" >&2; exit 64;
}

adb=${ADB:-$HOME/.local/share/android-sdk/platform-tools/adb}
ndk=${ANDROID_NDK_ROOT:-$HOME/.local/share/android-sdk/ndk/28.2.13676358}
pkg=${HOWL_ANDROID_PACKAGE:-uk.laurencegouws.howl_flutter}
howl=${HOWL_CLI:-$HOME/.local/bin/howl}
lib=${HOWL_NATIVE_HOST_LIB:-$root/libhowl_native_host.so}
cc="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
out=${TMPDIR:-/tmp}/howl-native-control-canary

[[ -x "$adb" && -x "$cc" && -x "$howl" && -f "$lib" ]] || {
  echo "missing adb, NDK clang, howl CLI, or native host library" >&2; exit 2;
}

"$cc" "$root/control-canary.c" -ldl -o "$out"
"$adb" reverse "tcp:$port" "tcp:$port" >/dev/null
"$adb" push "$out" /data/local/tmp/howl-native-control-canary >/dev/null
"$adb" push "$lib" /data/local/tmp/libhowl_native_host.so >/dev/null
"$adb" shell run-as "$pkg" cp /data/local/tmp/howl-native-control-canary files/howl-native-control-canary
"$adb" shell run-as "$pkg" cp /data/local/tmp/libhowl_native_host.so files/libhowl_native_host.so
"$adb" shell run-as "$pkg" chmod 700 files/howl-native-control-canary
"$adb" shell run-as "$pkg" chmod 600 files/libhowl_native_host.so

"$adb" shell run-as "$pkg" files/howl-native-control-canary files/libhowl_native_host.so "$endpoint"

snapshot=$($howl snapshot "$endpoint" --text)
for expected in \
  HOWL_CANARY_TEXT_λ \
  HOWL_CANARY_BACKOK \
  HOWL_CANARY_DEL_XZ \
  HOWL_CANARY_UNICODE_Z \
  HOWL_CANARY_PASTE \
  HOWL_CANARY_MOUSE_OK
do
  grep -Fxq "$expected" <<<"$snapshot" || {
    printf 'missing canonical output: %s\n' "$expected" >&2
    exit 1
  }
done

rich_file=$(mktemp "${TMPDIR:-/tmp}/howl-native-canary-rich.XXXXXX")
trap 'rm -f "$rich_file" "$out"' EXIT
"$howl" snapshot "$endpoint" --rich >"$rich_file"
python3 - "$rich_file" <<'PY'
import json, pathlib, sys
first=pathlib.Path(sys.argv[1]).read_text().splitlines()[0]
value=json.loads(first)
rows=value["rows"]; cols=value["columns"]
if (rows, cols) != (41, 53):
    raise SystemExit(f"unexpected canary geometry {(rows, cols)}")
print(f"canonical_geometry={rows}x{cols}")
PY

printf '%s\n' 'HOWL_NATIVE_CONTROL_CANARY_OK'
