#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scanner=${WAYLAND_SCANNER:-wayland-scanner}
out="${TMPDIR:-/tmp}/howl-wayland-repro-$$"
mkdir "$out"
trap 'rm -rf -- "$out"' EXIT INT TERM

version=$($scanner --version 2>&1)
case "$version" in
    *"1.25.0"*) ;;
    *) echo "expected wayland-scanner 1.25.0, got: $version" >&2; exit 1 ;;
esac

check() {
    stem=$1
    xml=$2
    "$scanner" client-header "$root/protocol/$stem/$xml.xml" "$out/$xml.h"
    "$scanner" private-code "$root/protocol/$stem/$xml.xml" "$out/$xml.c"
    cmp "$out/$xml.h" "$root/protocol/$stem/$xml-client-protocol.h"
    cmp "$out/$xml.c" "$root/protocol/$stem/$xml-protocol.c"
}

check xdg-shell xdg-shell
check linux-dmabuf linux-dmabuf-v1
check linux-drm-syncobj linux-drm-syncobj-v1
echo "Wayland generated artifacts match $scanner"
