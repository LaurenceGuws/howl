#!/bin/sh
#
# Exhaustive generated Unicode box-drawing fixture. Every supported
# U+2500-U+257F scalar is emitted in codepoint order and in adjoining runs.

set -eu

python3 - <<'PY'
import sys

reset = "\x1b[0m"
colors = ("\x1b[38;2;242;242;242m", "\x1b[38;2;190;170;90m")

print(f"{colors[0]}Generated box drawing U+2500-U+257F{reset}")
for start in range(0x2500, 0x2580, 16):
    chars = "".join(chr(cp) for cp in range(start, start + 16))
    spaced = " ".join(chars)
    color = colors[(start - 0x2500) // 16 % 2]
    print(f"{start:04X} adjoining {color}{chars}{reset}")
    print(f"{start:04X} isolated  {color}{spaced}{reset}")

print("\nGate: every scalar is present; adjoining strokes meet without gaps, "
      "overdraw, clipping, or stale pixels.")
sys.stdout.flush()
PY
