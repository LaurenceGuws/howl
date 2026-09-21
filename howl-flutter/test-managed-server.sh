#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$root/.." && pwd)
flutter=${FLUTTER:-$HOME/fvm/versions/3.47.2/bin/flutter}
if [[ ! -x "$flutter" ]]; then
  echo 'FLUTTER must name the pinned Flutter 3.47.2 toolchain' >&2
  exit 2
fi
if [[ $($flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])') != 3.47.2 ]]; then
  echo 'Flutter 3.47.2 required' >&2
  exit 2
fi

( cd "$repo/howl-cli" && zig build install )
"$root/native/build-linux.sh"

( cd "$root" && \
  HOWL_NATIVE_MANAGER_TEST=1 \
  HOWL_TEST_HOWL="$repo/howl-cli/zig-out/bin/howl" \
  LD_LIBRARY_PATH="$root/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$flutter" test test/managed_server_native_test.dart \
)
