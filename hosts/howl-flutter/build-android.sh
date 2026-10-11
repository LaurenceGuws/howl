#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
mode=${1:-profile}
if [[ $# -gt 0 ]]; then shift; fi
case "$mode" in
  debug|profile|release) ;;
  *) echo 'usage: build-android.sh [debug|profile|release] [flutter build apk args...]' >&2; exit 64 ;;
esac

flutter=${FLUTTER:-$(command -v flutter || true)}
if [[ -z "$flutter" ]]; then
  echo 'FLUTTER must name the Flutter executable' >&2
  exit 2
fi

"$root/native/build-android.sh"
(
  cd "$root"
  "$flutter" clean
  "$flutter" pub get
  "$flutter" build apk \
    "--$mode" \
    --target-platform android-arm64 \
    "$@"
)

apk="$root/build/app/outputs/flutter-apk/app-$mode.apk"
test -f "$apk"
file_list=$(unzip -Z1 "$apk")
abis=$(
  printf '%s\n' "$file_list" |
    awk '/^lib\// {print $0}' |
    sed 's#^lib/##;s#/.*##' |
    sort -u
)
if [[ "$abis" != arm64-v8a ]]; then
  printf 'unexpected Android ABIs:\n%s\n' "$abis" >&2
  exit 1
fi
grep -Fxq 'lib/arm64-v8a/libhowl_native_host.so' <<<"$file_list"
sha256sum "$apk"
echo "HOWL_ANDROID_APP_OK apk=$apk"
