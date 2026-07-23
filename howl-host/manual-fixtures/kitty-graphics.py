#!/usr/bin/env python3
"""Decode the tracked RGB PNG and transmit one bounded Kitty raw-RGBA image."""

import base64
import pathlib
import struct
import sys
import time
import zlib

TARGET = 256
IMAGE_ID = 72


def decode_rgb_png(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    offset = 8
    compressed = bytearray()
    width = height = None
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        body = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", body
            )
            assert depth == 8 and color == 2
            assert compression == filtering == interlace == 0
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
    assert width and height and width <= 4096 and height <= 4096
    encoded = zlib.decompress(compressed)
    stride = width * 3
    assert len(encoded) == height * (stride + 1)
    rows = []
    prior = bytearray(stride)
    source = 0
    for _ in range(height):
        filter_kind = encoded[source]
        source += 1
        row = bytearray(encoded[source : source + stride])
        source += stride
        for index in range(stride):
            left = row[index - 3] if index >= 3 else 0
            up = prior[index]
            upper_left = prior[index - 3] if index >= 3 else 0
            if filter_kind == 1:
                row[index] = (row[index] + left) & 255
            elif filter_kind == 2:
                row[index] = (row[index] + up) & 255
            elif filter_kind == 3:
                row[index] = (row[index] + ((left + up) >> 1)) & 255
            elif filter_kind == 4:
                estimate = left + up - upper_left
                distances = (
                    abs(estimate - left),
                    abs(estimate - up),
                    abs(estimate - upper_left),
                )
                predictor = (left, up, upper_left)[distances.index(min(distances))]
                row[index] = (row[index] + predictor) & 255
            else:
                assert filter_kind == 0
        rows.append(row)
        prior = row
    return width, height, rows


def scaled_rgba(width, height, rows):
    result = bytearray(TARGET * TARGET * 4)
    destination = 0
    for y in range(TARGET):
        source_row = rows[y * height // TARGET]
        for x in range(TARGET):
            source = (x * width // TARGET) * 3
            result[destination : destination + 3] = source_row[source : source + 3]
            result[destination + 3] = 255
            destination += 4
    return result


def transmit(pixels):
    encoded = base64.b64encode(pixels)
    chunk = 4096
    first = True
    for offset in range(0, len(encoded), chunk):
        more = offset + chunk < len(encoded)
        if first:
            control = (
                f"a=T,t=d,f=32,s={TARGET},v={TARGET},i={IMAGE_ID},q=2,m={int(more)}"
            )
            first = False
        else:
            control = f"m={int(more)}"
        sys.stdout.buffer.write(b"\x1b_G" + control.encode() + b";")
        sys.stdout.buffer.write(encoded[offset : offset + chunk])
        sys.stdout.buffer.write(b"\x1b\\")
    sys.stdout.buffer.flush()


asset = pathlib.Path(__file__).resolve().parent.parent / "assets/howl_window_icon.png"
source_width, source_height, source_rows = decode_rgb_png(asset)
print("Kitty static graphics: tracked Howl logo, 256x256 raw RGBA")
transmit(scaled_rgba(source_width, source_height, source_rows))
print("\nPASS when the complete colored logo is visible below the heading.")
time.sleep(30)
