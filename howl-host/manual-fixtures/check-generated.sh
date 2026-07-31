#!/bin/sh
#
# Verifies that the generated-glyph manual fixtures retain complete coverage
# of every currently implemented classifier range.

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 GENERATED_CLASSIFIER" >&2
    exit 2
fi

fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
classifier=$1

python3 - "$fixture_dir" "$classifier" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
classifier = sys.argv[2]

def output(name):
    return subprocess.run(
        [str(root / name)],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout

powerline = output("powerline.sh")
box = output("generated-box.sh")
computing = output("generated-computing.sh")
progress = output("generated-progress.sh")
branch = output("generated-branch.sh")
fixtures = {
    "box": ("generated-box.sh", box),
    "block": ("generated-computing.sh", computing),
    "braille": ("generated-computing.sh", computing),
    "sextant": ("generated-computing.sh", computing),
    "octant": ("generated-computing.sh", computing),
    "powerline": ("powerline.sh", powerline),
    "progress": ("generated-progress.sh", progress),
    "branch": ("generated-branch.sh", branch),
}

classified = subprocess.run(
    [classifier],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
manifest = classified.stdout + classified.stderr
seen = set()
for line in manifest.splitlines():
    scalar, family = line.split("\t")
    codepoint = int(scalar, 16)
    if codepoint in seen:
        raise SystemExit(f"classifier duplicate U+{codepoint:04X}")
    seen.add(codepoint)
    try:
        name, text = fixtures[family]
    except KeyError:
        raise SystemExit(f"classifier emitted unknown family {family!r}")
    if chr(codepoint) not in text:
        raise SystemExit(f"{name}: missing classified U+{codepoint:04X} ({family})")

if not seen:
    raise SystemExit("classifier emitted no generated glyphs")

print("generated manual fixture coverage passed")
PY
