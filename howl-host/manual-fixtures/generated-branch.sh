#!/bin/sh
#
# Exhaustive Kitty branch-drawing fixture for U+F5D0-U+F60D. Every classified
# scalar is emitted in codepoint order; spaces keep the wide branch rasters
# independently inspectable while repeated rows expose stale-resource reuse.

set -eu

python3 - <<'PY'
import sys

reset = "\x1b[0m"
white = "\x1b[38;2;242;242;242m"
blue = "\x1b[38;2;90;170;240m"
gold = "\x1b[38;2;220;185;90m"
purple = "\x1b[38;2;175;120;220m"

first = 0xF5D0
last = 0xF60D
glyphs = [chr(cp) for cp in range(first, last + 1)]

print(f"{white}Generated branch drawing U+F5D0-U+F60D (62 scalars){reset}")
for offset in range(0, len(glyphs), 8):
    end = min(offset + 8, len(glyphs))
    label = f"U+{first + offset:04X}-U+{first + end - 1:04X}"
    print(f"{label} {blue}{' '.join(glyphs[offset:end])}{reset}")

# The complete unspaced run catches missing endpoints and accidental
# codepoint reordering; the spaced rows above keep individual rasters visible.
print(f"complete  {gold}{''.join(glyphs)}{reset}")
print(f"repeated   {purple}{glyphs[0] * 4} {glyphs[1] * 4} {glyphs[0] * 4}{reset}")
print(f"metric-free F5EE {white}{glyphs[0xF5EE - first]}{reset}")
print("\nGate: every branch scalar is present; adjoining edges, corners, fades, "
      "curves, clipping, and repeated shared-resource reuse remain exact.")
sys.stdout.flush()
PY
