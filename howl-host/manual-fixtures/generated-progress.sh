#!/bin/sh
#
# Focused U+EE00-U+EE0B generated progress/spinner fixture. Kitty and Howl
# generate these pixels independently of Fira Code font outline availability.

set -eu

python3 - <<'PY'
import sys

reset = "\x1b[0m"
white = "\x1b[38;2;242;242;242m"
blue = "\x1b[38;2;90;170;240m"
gold = "\x1b[38;2;220;185;90m"
purple = "\x1b[38;2;175;120;220m"

glyphs = [chr(cp) for cp in range(0xEE00, 0xEE0C)]
print(f"{white}Generated progress/spinner U+EE00-U+EE0B{reset}\n")
print(f"unfilled adjoining {blue}{''.join(glyphs[0:3])}{reset}")
print(f"filled adjoining   {gold}{''.join(glyphs[3:6])}{reset}")
print(f"all isolated       {white}{' '.join(glyphs)}{reset}")
print(f"spinner phases     {purple}{' '.join(glyphs[6:12])}{reset}")
print(f"repeated identity  {blue}{glyphs[6] * 8}{reset}")
print(f"recreated sequence {gold}{''.join(glyphs[6:12]) * 2}{reset}")
print("\nGate: progress frames and fills join exactly; spinner arcs remain centered, "
      "unclipped, and stable under repeated shared-resource reuse.")
sys.stdout.flush()
PY
