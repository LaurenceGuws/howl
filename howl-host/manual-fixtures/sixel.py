#!/usr/bin/env python3
"""Emit one bounded RGB Sixel receipt through the common terminal image plane."""

import sys
import time

WIDTH = 60
HEIGHT = 30


def sixel():
    out = bytearray(b'"2;2;60;30')
    # HLS orange plus explicit RGB colors exercise both DEC color forms.
    out.extend(b"#1;1;150;50;100#2;2;93;86;70#3;2;12;12;15")
    for band in range(HEIGHT // 6):
        if band:
            out.extend(b"-")
        # Orange frame, pale center, and a dark diagonal notch.
        for color, start, end in (
            (1, 0, WIDTH),
            (2, 3, WIDTH - 3),
            (3, 22 + band, 36 + band),
        ):
            out.extend(f"#{color}${'?' * start}!{end - start}~".encode())
    return bytes(out)


print("Sixel common image plane: 120x60 HLS/RGB with 2:2 raster aspect")
sys.stdout.buffer.write(b"\x1bPq" + sixel() + b"\x1b\\")
sys.stdout.buffer.flush()
print("\nPASS when a complete orange-framed pale rectangle with a dark diagonal is visible.")
time.sleep(30)
