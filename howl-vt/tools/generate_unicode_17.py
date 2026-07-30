#!/usr/bin/env python3
"""Translate Kitty's Unicode 17 char-props-data.h into Howl's exact table blob."""

from pathlib import Path
import re
import struct
import sys


GBP = {
    name: value
    for value, name in enumerate(
        (
            "AtStart",
            "None",
            "Prepend",
            "CR",
            "LF",
            "Control",
            "Extend",
            "Regional_Indicator",
            "SpacingMark",
            "L",
            "V",
            "T",
            "LV",
            "LVT",
            "ZWJ",
            "Private_Expecting_RI",
        )
    )
}
ICB = {"None": 0, "Linker": 1, "Consonant": 2, "Extend": 3}
UC = {
    name: value
    for value, name in enumerate(
        (
            "Cn",
            "Cc",
            "Zs",
            "Po",
            "Sc",
            "Ps",
            "Pe",
            "Sm",
            "Pd",
            "Nd",
            "Lu",
            "Sk",
            "Pc",
            "Ll",
            "So",
            "Lo",
            "Pi",
            "Cf",
            "No",
            "Pf",
            "Lt",
            "Lm",
            "Mn",
            "Me",
            "Mc",
            "Nl",
            "Zl",
            "Zp",
            "Cs",
            "Co",
        )
    )
}


def array_body(source: str, declaration: str) -> str:
    start = source.index(declaration)
    opening = source.index("{", start)
    closing = source.index("};", opening)
    return source[opening + 1 : closing]


def integers(source: str, declaration: str) -> list[int]:
    body = array_body(source, declaration)
    return [int(value) for value in re.findall(r"\b\d+\b", body)]


def fields(line: str) -> dict[str, str]:
    return dict(re.findall(r"\.([a-z_]+)=([A-Za-z0-9_]+)", line))


def char_props(source: str) -> list[int]:
    body = array_body(source, "static const CharProps CharProps_t3[106]")
    result = []
    for line in body.splitlines():
        if "{." not in line:
            continue
        item = fields(line)
        value = int(item["shifted_width"]) << 9
        value |= int(item["is_emoji"]) << 12
        value |= UC[item["category"].removeprefix("UC_")] << 13
        value |= int(item["is_emoji_presentation_base"]) << 18
        value |= int(item["is_invalid"]) << 19
        value |= int(item["is_non_rendered"]) << 20
        value |= int(item["is_symbol"]) << 21
        value |= int(item["is_combining_char"]) << 22
        value |= int(item["is_word_char"]) << 23
        value |= int(item["is_punctuation"]) << 24
        value |= GBP[item["grapheme_break"].removeprefix("GBP_")] << 25
        value |= ICB[item["indic_conjunct_break"].removeprefix("ICB_")] << 29
        value |= int(item["is_extended_pictographic"]) << 31
        result.append(value)
    return result


def transitions(source: str) -> list[int]:
    body = array_body(
        source,
        "static const GraphemeSegmentationResult "
        "GraphemeSegmentationResult_t2[2880]",
    )
    result = []
    for line in body.splitlines():
        if "{." not in line:
            continue
        item = fields(line)
        value = int(item["add_to_current_cell"]) << 6
        value |= GBP[item["grapheme_break"].removeprefix("GBP_")] << 7
        value |= int(item["incb_consonant_extended"]) << 11
        value |= int(item["incb_consonant_extended_linker"]) << 12
        value |= int(item["incb_consonant_extended_linker_extended"]) << 13
        value |= int(item["emoji_modifier_sequence"]) << 14
        value |= int(item["emoji_modifier_sequence_before_last_char"]) << 15
        result.append(value)
    return result


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit(
            "usage: generate_unicode_17.py KITTY_CHAR_PROPS_DATA_H OUTPUT [--check]"
        )
    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    output = bytearray()
    tables = (
        (integers(source, "static const uint8_t CharProps_t1[4352]"), "B", 4352),
        (integers(source, "static const uint8_t CharProps_t2[46592]"), "B", 46592),
        (char_props(source), "I", 106),
        (
            integers(
                source,
                "static const uint8_t GraphemeSegmentationResult_t1[4096]",
            ),
            "B",
            4096,
        ),
        (transitions(source), "H", 2880),
    )
    for values, kind, expected in tables:
        if len(values) != expected:
            raise SystemExit(f"expected {expected} {kind} values, got {len(values)}")
        output.extend(struct.pack(f"<{len(values)}{kind}", *values))
    if len(output) != 61224:
        raise SystemExit(f"expected 61224 output bytes, got {len(output)}")
    destination = Path(sys.argv[2])
    if len(sys.argv) == 4:
        if sys.argv[3] != "--check":
            raise SystemExit(f"unknown option: {sys.argv[3]}")
        if destination.read_bytes() != output:
            raise SystemExit(f"{destination} is not the generated Unicode 17 table")
    else:
        destination.write_bytes(output)


if __name__ == "__main__":
    main()
