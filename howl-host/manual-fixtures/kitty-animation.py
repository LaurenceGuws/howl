#!/usr/bin/env python3
"""Prove bounded raw Kitty frames, composition, timing, and Vulkan replacement."""

import base64
import sys
import time

SIZE = 64
IMAGE_ID = 90


def pixels(red, green, blue):
    result = bytearray(SIZE * SIZE * 4)
    for y in range(SIZE):
        for x in range(SIZE):
            offset = (y * SIZE + x) * 4
            border = x < 4 or y < 4 or x >= SIZE - 4 or y >= SIZE - 4
            result[offset : offset + 4] = bytes(
                (255, 255, 255, 255) if border else (red, green, blue, 255)
            )
    return result


def command(metadata, payload=b""):
    encoded = base64.b64encode(payload)
    chunk = 4096
    if not encoded:
        sys.stdout.buffer.write(b"\x1b_G" + metadata.encode() + b"\x1b\\")
    for offset in range(0, len(encoded), chunk):
        more = offset + chunk < len(encoded)
        prefix = metadata + f",m={int(more)}" if offset == 0 else f"m={int(more)}"
        sys.stdout.buffer.write(b"\x1b_G" + prefix.encode() + b";")
        sys.stdout.buffer.write(encoded[offset : offset + chunk] + b"\x1b\\")
    sys.stdout.buffer.flush()


sys.stdout.write("\x1b[2J\x1b[H")
print("Kitty animation: red -> green -> blue, 300 ms frames")
print("PASS when the complete square below cycles colors without covering either instruction line.")
sys.stdout.write("\x1b[4;1H")
sys.stdout.flush()
command(f"a=T,f=32,s={SIZE},v={SIZE},i={IMAGE_ID},q=2,c=8,r=4,C=1", pixels(180, 30, 30))
command(f"a=f,f=32,s={SIZE},v={SIZE},i={IMAGE_ID},q=2,r=2,z=300,C=1", pixels(30, 180, 30))
command(f"a=f,f=32,s={SIZE},v={SIZE},i={IMAGE_ID},q=2,r=3,z=300,C=1", pixels(30, 60, 200))
command(f"a=a,i={IMAGE_ID},q=2,r=1,z=300,s=3")
sys.stdout.write("\x1b[9;1HAnimation running; this line must remain below the square.")
sys.stdout.flush()
time.sleep(30)
