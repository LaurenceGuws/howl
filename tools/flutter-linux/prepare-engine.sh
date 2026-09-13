#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
version=3.47.4
expected_head=9584c6713b324636289d067944a46fd6b49df14b
sdk="$root/.fvm/flutter_sdk"
lab="$root/temp/flutter-engine-$version"
depot="$root/temp/depot_tools"

[[ -L $sdk || -d $sdk ]] || {
  echo 'flutter-linux: run `fvm use 3.47.4` first' >&2
  exit 1
}
actual=$(git -C "$sdk" rev-parse HEAD)
[[ $actual == "$expected_head" ]] || {
  echo "flutter-linux: expected Flutter $version at $expected_head, got $actual" >&2
  exit 1
}

if [[ ! -d $lab/.git ]]; then
  mkdir -p "$(dirname "$lab")"
  git clone --no-checkout "$sdk" "$lab"
  git -C "$lab" checkout --detach "$expected_head"
fi
actual=$(git -C "$lab" rev-parse HEAD)
[[ $actual == "$expected_head" ]] || {
  echo "flutter-linux: disposable checkout is at unexpected commit $actual" >&2
  exit 1
}

if [[ ! -d $depot/.git ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$depot"
fi

# A hydrated checkout remains useful after build-engine.sh has applied the
# tracked source patch. Do not send gclient through a locally patched tree just
# to rediscover dependencies we already have.
if [[ -x $lab/third_party/ninja/ninja && \
      -d $lab/engine/src/build/linux/debian_bullseye_amd64-sysroot ]]; then
  printf 'flutter-linux: engine checkout already hydrated at %s\n' "$lab"
  exit 0
fi

cat > "$lab/.gclient" <<'GCLIENT'
solutions = [
  {
    "custom_deps": {},
    "deps_file": "DEPS",
    "managed": False,
    "name": ".",
    "safesync_url": "",
    "url": "https://github.com/flutter/flutter.git",
    "custom_vars": {
      "download_android_deps": False,
      "download_fuchsia_deps": False,
      "download_jdk": False,
      "download_emsdk": False,
      "download_esbuild": False,
      "checkout_llvm": False,
      "setup_githooks": False,
    },
  },
]
GCLIENT

PATH="$depot:$PATH" "$depot/gclient" sync --no-history -j 8
printf 'flutter-linux: engine checkout ready at %s\n' "$lab"
