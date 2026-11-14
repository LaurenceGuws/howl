#!/usr/bin/env python3
"""Encode Kitty's Unicode 17 GraphemeBreakTest resource for Zig proofs."""

import json
from pathlib import Path
import struct
import sys


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit(
            "usage: generate_unicode_17_graphemes.py KITTY_JSON OUTPUT [--check]"
        )
    tests = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    output = bytearray(struct.pack("<H", len(tests)))
    for test in tests:
        graphemes = test["data"]
        output.append(len(graphemes))
        for grapheme in graphemes:
            scalars = [ord(value) for value in grapheme]
            output.append(len(scalars))
            output.extend(struct.pack(f"<{len(scalars)}I", *scalars))
    destination = Path(sys.argv[2])
    if len(sys.argv) == 4:
        if sys.argv[3] != "--check":
            raise SystemExit(f"unknown option: {sys.argv[3]}")
        if destination.read_bytes() != output:
            raise SystemExit(f"{destination} is not the generated grapheme proof")
    else:
        destination.write_bytes(output)


if __name__ == "__main__":
    main()
