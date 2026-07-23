#!/usr/bin/env python3
"""Emit one bounded RGB Sixel receipt through the common terminal image plane."""

import sys
import time

WIDTH = 120
HEIGHT = 60


def sixel():
    out = bytearray(b'"1;1;120;60')
    # Explicit RGB colors keep the receipt independent of a terminal palette.
    out.extend(b"#1;2;85;36;5#2;2;93;86;70#3;2;12;12;15")
    for band in range(HEIGHT // 6):
        if band:
            out.extend(b"-")
        # Orange frame, pale center, and a dark diagonal notch.
        for color, start, end in (
            (1, 0, WIDTH),
            (2, 5, WIDTH - 5),
            (3, 46 + band * 2, 74 + band * 2),
        ):
            out.extend(f"#{color}${'?' * start}!{end - start}~".encode())
    return bytes(out)


print("Sixel common image plane: 120x60 explicit RGB")
sys.stdout.buffer.write(b"\x1bPq" + sixel() + b"\x1b\\")
sys.stdout.buffer.flush()
print("\nPASS when a complete orange-framed pale rectangle with a dark diagonal is visible.")
time.sleep(30)
