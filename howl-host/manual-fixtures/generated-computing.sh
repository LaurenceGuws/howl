#!/bin/sh
#
# Exhaustive generated block, Braille, sextant, and octant fixture for the
# currently implemented Render classifier ranges.

set -eu

python3 - <<'PY'
import sys

reset = "\x1b[0m"
families = (
    ("blocks", 0x2580, 0x259F),
    ("braille", 0x2800, 0x28FF),
    ("sextants", 0x1FB00, 0x1FB3B),
    ("octants", 0x1CD00, 0x1CDE5),
    ("octant aliases", 0x1FBE6, 0x1FBE7),
)

for family_index, (name, first, last) in enumerate(families):
    color = f"\x1b[38;2;{90 + family_index * 25};{180 - family_index * 18};210m"
    print(f"\n{color}{name}: U+{first:04X}-U+{last:04X}{reset}")
    for start in range(first, last + 1, 16):
        end = min(start + 15, last)
        chars = "".join(chr(cp) for cp in range(start, end + 1))
        print(f"{start:05X} {color}{chars}{reset}")

print("\nGate: every supported scalar is present with stable cell occupancy, "
      "edge coverage, clipping, and no cross-row resource corruption.")
sys.stdout.flush()
PY
