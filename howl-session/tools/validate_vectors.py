#!/usr/bin/env python3
"""Independent Howl session v1 wire-vector decoder and validator.

This tool intentionally does not import, execute, or inspect the Zig
implementation.  The duplicated constants below are the client-facing wire
contract.  Keeping this decoder boring and separate gives the tracked golden
vectors a witness with a different implementation and language.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


MAGIC = b"HWLS"
FRAMING_VERSION = 1
HEADER_BYTES = 12
MAXIMUM_PAYLOAD_BYTES = 1024 * 1024

KINDS = {
    1: "hello",
    2: "welcome",
    3: "observe",
    4: "snapshot_begin",
    5: "snapshot_data",
    6: "snapshot_end",
    7: "input",
    8: "assign_leader",
    9: "resize",
    10: "signal",
    11: "result",
}

INPUT_KINDS = {1: "bytes", 2: "paste", 3: "key", 4: "mouse", 5: "focus"}
KEY_KINDS = {1: "named", 2: "unicode"}
KEY_ACTIONS = {1: "press", 2: "repeat", 3: "release"}
MOUSE_KINDS = {1: "press", 2: "release", 3: "move", 4: "wheel"}
MOUSE_BUTTONS = {
    0: "none",
    1: "left",
    2: "middle",
    3: "right",
    4: "wheel_up",
    5: "wheel_down",
}
FOCUS = {1: "in", 2: "out"}
SIGNALS = {1: "hangup", 2: "interrupt", 3: "resize_notify", 9: "kill", 15: "terminate"}
RESULT_CODES = {
    0: "ok",
    1: "malformed",
    2: "unsupported",
    3: "no_such_client",
    4: "not_leader",
    5: "rejected",
}

SNAPSHOT_FORMATS = {1: "grid_v1", 2: "text_v1"}
TEXT_RECORD_KINDS = {1: "presentation", 2: "row", 3: "hyperlink"}
TEXT_COLOR_KINDS = {0: "default", 1: "indexed", 2: "rgb"}

TEXT_PRESENTATION_BYTES = 1060
TEXT_RECORD_HEADER_BYTES = 8
TEXT_ROW_HEADER_BYTES = 4
TEXT_CELL_HEADER_BYTES = 35
TEXT_HYPERLINK_HEADER_BYTES = 6
TEXT_MAXIMUM_CELL_SCALARS = 24
TEXT_MAXIMUM_HYPERLINKS = 4096
TEXT_MAXIMUM_HYPERLINK_URI_BYTES = 2048
TEXT_PRESENTATION_PRESENCE_KNOWN = 0x0F
TEXT_PRESENTATION_FLAGS_KNOWN = 0x01
TEXT_STYLE_KNOWN = 0x01FF

TYPED_KEY_HEADER_BYTES = 20
TYPED_MAXIMUM_LEGACY_KEY_BYTES = 511
TYPED_MAXIMUM_KEY_TEXT_BYTES = 64
TYPED_MOUSE_BYTES = 19
TYPED_FOCUS_BYTES = 1

NAMED_KEY_MAXIMUM = 58


class WireError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def reject(code: str) -> None:
    raise WireError(code)


def require(condition: bool, code: str) -> None:
    if not condition:
        reject(code)


def u16(data: bytes) -> int:
    require(len(data) == 2, "internal_u16")
    return int.from_bytes(data, "big")


def u32(data: bytes) -> int:
    require(len(data) == 4, "internal_u32")
    return int.from_bytes(data, "big")


def i32(data: bytes) -> int:
    require(len(data) == 4, "internal_i32")
    return struct.unpack(">i", data)[0]


def u64(data: bytes) -> int:
    require(len(data) == 8, "internal_u64")
    return int.from_bytes(data, "big")


def valid_scalar(value: int) -> bool:
    return value <= 0x10FFFF and not 0xD800 <= value <= 0xDFFF


def decode_hello(payload: bytes) -> dict:
    require(len(payload) == 12, "hello_size")
    return {
        "min_version": u16(payload[0:2]),
        "max_version": u16(payload[2:4]),
        "features": u64(payload[4:12]),
    }


def decode_welcome(payload: bytes) -> dict:
    require(len(payload) == 18, "welcome_size")
    return {
        "version": u16(payload[0:2]),
        "features": u64(payload[2:10]),
        "client_id": u64(payload[10:18]),
    }


def decode_observe(payload: bytes) -> dict:
    require(len(payload) == 12, "observe_size")
    return {
        "after_revision": u64(payload[0:8]),
        "history_offset": u32(payload[8:12]),
    }


def decode_snapshot_begin(payload: bytes) -> dict:
    require(len(payload) == 40, "snapshot_begin_size")
    format_value = u16(payload[16:18])
    require(format_value in SNAPSHOT_FORMATS, "snapshot_format")
    flags = payload[39]
    require(flags & 0x80 == 0, "snapshot_flags")
    return {
        "revision": u64(payload[0:8]),
        "terminal_revision": u64(payload[8:16]),
        "format": SNAPSHOT_FORMATS[format_value],
        "history_offset": u32(payload[18:22]),
        "history_count": u32(payload[22:26]),
        "history_row_base": u32(payload[26:30]),
        "rows": u16(payload[30:32]),
        "columns": u16(payload[32:34]),
        "cursor_row": u16(payload[34:36]),
        "cursor_column": u16(payload[36:38]),
        "cursor_shape": payload[38],
        "cursor_visible": bool(flags & (1 << 0)),
        "cursor_blink": bool(flags & (1 << 1)),
        "alternate_screen": bool(flags & (1 << 2)),
        "stream_closed": bool(flags & (1 << 3)),
        "child_exited": bool(flags & (1 << 4)),
        "leader_present": bool(flags & (1 << 5)),
        "you_are_leader": bool(flags & (1 << 6)),
    }


def decode_snapshot_end(payload: bytes) -> dict:
    require(len(payload) == 8, "snapshot_end_size")
    return {"revision": u64(payload)}


def decode_assign_leader(payload: bytes) -> dict:
    require(len(payload) == 8, "assign_leader_size")
    return {"client_id": u64(payload)}


def decode_resize(payload: bytes) -> dict:
    require(len(payload) == 4, "resize_size")
    return {"rows": u16(payload[0:2]), "columns": u16(payload[2:4])}


def decode_signal(payload: bytes) -> dict:
    require(len(payload) == 1, "signal_size")
    require(payload[0] in SIGNALS, "signal_value")
    return {"signal": SIGNALS[payload[0]]}


def decode_result(payload: bytes) -> dict:
    require(len(payload) == 2, "result_size")
    require(payload[0] in KINDS, "result_request_kind")
    require(payload[1] in RESULT_CODES, "result_code")
    return {
        "request_kind": KINDS[payload[0]],
        "code": RESULT_CODES[payload[1]],
    }


def decode_typed_key(body: bytes) -> dict:
    require(len(body) >= TYPED_KEY_HEADER_BYTES, "key_size")
    key_kind = body[0]
    action = body[1]
    modifiers = body[2]
    presence = body[3]
    require(key_kind in KEY_KINDS, "key_kind")
    require(action in KEY_ACTIONS, "key_action")
    require(presence & ~0x03 == 0, "key_presence")

    key_value = u32(body[4:8])
    shifted_raw = u32(body[8:12])
    alternate_raw = u32(body[12:16])
    legacy_len = u16(body[16:18])
    text_len = u16(body[18:20])
    require(legacy_len <= TYPED_MAXIMUM_LEGACY_KEY_BYTES, "key_legacy_limit")
    require(text_len <= TYPED_MAXIMUM_KEY_TEXT_BYTES, "key_text_limit")
    require(len(body) == TYPED_KEY_HEADER_BYTES + legacy_len + text_len, "key_size")

    if key_kind == 1:
        require(1 <= key_value <= NAMED_KEY_MAXIMUM, "key_name")
    else:
        require(valid_scalar(key_value), "key_unicode")

    shifted_present = bool(presence & 0x01)
    alternate_present = bool(presence & 0x02)
    if shifted_present:
        require(valid_scalar(shifted_raw), "key_shifted_unicode")
        shifted = shifted_raw
    else:
        require(shifted_raw == 0, "key_shifted_canonical")
        shifted = None
    if alternate_present:
        require(valid_scalar(alternate_raw), "key_alternate_unicode")
        alternate = alternate_raw
    else:
        require(alternate_raw == 0, "key_alternate_canonical")
        alternate = None

    legacy = body[20 : 20 + legacy_len]
    text_bytes = body[20 + legacy_len :]
    try:
        text = text_bytes.decode("utf-8")
    except UnicodeDecodeError:
        reject("key_text_utf8")

    return {
        "kind": KEY_KINDS[key_kind],
        "key_value": key_value,
        "action": KEY_ACTIONS[action],
        "modifiers": modifiers,
        "shifted": shifted,
        "alternate": alternate,
        "legacy_len": legacy_len,
        "legacy_hex": legacy.hex(),
        "text_len": text_len,
        "text": text,
    }


def decode_typed_mouse(body: bytes) -> dict:
    require(len(body) == TYPED_MOUSE_BYTES, "mouse_size")
    require(body[0] in MOUSE_KINDS, "mouse_kind")
    require(body[1] in MOUSE_BUTTONS, "mouse_button")
    require(body[3] & ~0x07 == 0, "mouse_buttons_down")
    presence = body[10]
    require(presence & ~0x01 == 0, "mouse_presence")
    pixel_x_raw = u32(body[11:15])
    pixel_y_raw = u32(body[15:19])
    pixels_present = bool(presence & 0x01)
    if not pixels_present:
        require(pixel_x_raw == 0 and pixel_y_raw == 0, "mouse_pixels_canonical")
    return {
        "kind": MOUSE_KINDS[body[0]],
        "button": MOUSE_BUTTONS[body[1]],
        "modifiers": body[2],
        "buttons_down": body[3],
        "row": i32(body[4:8]),
        "column": u16(body[8:10]),
        "pixel_x": pixel_x_raw if pixels_present else None,
        "pixel_y": pixel_y_raw if pixels_present else None,
    }


def decode_typed_focus(body: bytes) -> dict:
    require(len(body) == TYPED_FOCUS_BYTES, "focus_size")
    require(body[0] in FOCUS, "focus_value")
    return {"focus": FOCUS[body[0]]}


def decode_input(payload: bytes) -> dict:
    require(len(payload) >= 1, "input_size")
    input_kind = payload[0]
    require(input_kind in INPUT_KINDS, "input_kind")
    body = payload[1:]
    name = INPUT_KINDS[input_kind]
    if name in ("bytes", "paste"):
        return {"kind": name, "bytes_hex": body.hex()}
    if name == "key":
        return {"kind": name, "key": decode_typed_key(body)}
    if name == "mouse":
        return {"kind": name, "mouse": decode_typed_mouse(body)}
    return {"kind": name, **decode_typed_focus(body)}


def decode_color(data: bytes) -> dict:
    require(len(data) == 5, "text_color_size")
    kind = data[0]
    value = u32(data[1:5])
    require(kind in TEXT_COLOR_KINDS, "text_color_kind")
    if kind == 0:
        require(value == 0, "text_color_default")
    elif kind == 1:
        require(value <= 255, "text_color_indexed")
    else:
        require(value <= 0x00FFFFFF, "text_color_rgb")
    return {"kind": TEXT_COLOR_KINDS[kind], "value": value}


def rgba(data: bytes) -> str:
    require(len(data) == 4, "internal_rgba")
    return data.hex()


def decode_presentation(payload: bytes) -> dict:
    require(len(payload) == TEXT_PRESENTATION_BYTES, "text_presentation_size")
    presence = payload[8]
    flags = payload[9]
    require(presence & ~TEXT_PRESENTATION_PRESENCE_KNOWN == 0, "text_presentation_presence")
    require(flags & ~TEXT_PRESENTATION_FLAGS_KNOWN == 0, "text_presentation_flags")
    require(payload[10] == 0 and payload[11] == 0, "text_presentation_reserved")

    palette = payload[12:1036]
    foreground = payload[1036:1040]
    background = payload[1040:1044]
    cursor = payload[1044:1048]
    cursor_text = payload[1048:1052]
    selection_background = payload[1052:1056]
    selection_foreground = payload[1056:1060]
    return {
        "cursor_age_ns": u64(payload[0:8]),
        "presence": presence,
        "reverse_screen": bool(flags & 0x01),
        "palette_samples": {
            "0": rgba(palette[0:4]),
            "1": rgba(palette[4:8]),
            "255": rgba(palette[1020:1024]),
        },
        "foreground": rgba(foreground),
        "background": rgba(background),
        "cursor": rgba(cursor) if presence & 0x01 else None,
        "cursor_text": rgba(cursor_text) if presence & 0x02 else None,
        "selection_background": rgba(selection_background) if presence & 0x04 else None,
        "selection_foreground": rgba(selection_foreground) if presence & 0x08 else None,
    }


def decode_text_row(payload: bytes, columns: int, referenced_links: set[int]) -> dict:
    require(len(payload) >= TEXT_ROW_HEADER_BYTES, "text_row_size")
    require(payload[0] <= 1, "text_row_wrapped")
    require(payload[1] <= 3, "text_row_geometry")
    require(u16(payload[2:4]) == columns, "text_row_columns")

    offset = TEXT_ROW_HEADER_BYTES
    cells = []
    for _ in range(columns):
        require(len(payload) - offset >= TEXT_CELL_HEADER_BYTES, "text_cell_size")
        cell = payload[offset : offset + TEXT_CELL_HEADER_BYTES]
        scalar_count = cell[0]
        width = cell[1]
        height = cell[2]
        x = cell[3]
        y = cell[4]
        require(scalar_count <= TEXT_MAXIMUM_CELL_SCALARS, "text_scalar_count")
        require(width > 0 and height > 0 and x < width and y < height, "text_cell_geometry")
        require(cell[5] <= 15 and cell[6] <= 15, "text_cell_subscale")
        require(cell[7] <= 3 and cell[8] <= 3, "text_cell_alignment")
        require(cell[9] <= 1, "text_cell_semantic_width")
        require(cell[10] <= 15, "text_cell_font")
        require(cell[11] <= 2, "text_cell_baseline")
        require(cell[12] <= 4, "text_cell_underline")
        require(cell[13] <= 2, "text_cell_protection")
        style = u16(cell[14:16])
        require(style & ~TEXT_STYLE_KNOWN == 0, "text_style_bits")
        fg = decode_color(cell[16:21])
        bg = decode_color(cell[21:26])
        underline = decode_color(cell[26:31])
        link_id = u32(cell[31:35])
        require(link_id <= TEXT_MAXIMUM_HYPERLINKS, "text_link_id")
        if link_id:
            referenced_links.add(link_id)

        offset += TEXT_CELL_HEADER_BYTES
        scalar_bytes = scalar_count * 4
        require(len(payload) - offset >= scalar_bytes, "text_scalar_bytes")
        scalars = []
        for scalar_offset in range(offset, offset + scalar_bytes, 4):
            scalar = u32(payload[scalar_offset : scalar_offset + 4])
            require(valid_scalar(scalar), "text_scalar_unicode")
            scalars.append(scalar)
        require((x == 0 and y == 0) or not scalars, "text_continuation_scalars")
        offset += scalar_bytes

        cells.append(
            {
                "scalars": scalars,
                "width": width,
                "height": height,
                "x": x,
                "y": y,
                "subscale_n": cell[5],
                "subscale_d": cell[6],
                "vertical_align": cell[7],
                "horizontal_align": cell[8],
                "semantic_width": bool(cell[9]),
                "font": cell[10],
                "baseline": cell[11],
                "underline_style": cell[12],
                "protection": cell[13],
                "style": style,
                "fg": fg,
                "bg": bg,
                "underline_color": underline,
                "link_id": link_id,
            }
        )
    require(offset == len(payload), "text_row_trailing")
    return {
        "wrapped": bool(payload[0]),
        "line_geometry": payload[1],
        "columns": columns,
        "cells": cells,
    }


def decode_hyperlink(payload: bytes, resolved_links: dict[int, str]) -> dict:
    require(len(payload) >= TEXT_HYPERLINK_HEADER_BYTES, "text_hyperlink_size")
    link_id = u32(payload[0:4])
    uri_len = u16(payload[4:6])
    require(1 <= link_id <= TEXT_MAXIMUM_HYPERLINKS, "text_hyperlink_id")
    require(1 <= uri_len <= TEXT_MAXIMUM_HYPERLINK_URI_BYTES, "text_hyperlink_uri_limit")
    require(len(payload) == TEXT_HYPERLINK_HEADER_BYTES + uri_len, "text_hyperlink_size")
    require(link_id not in resolved_links, "text_hyperlink_duplicate")
    uri_hex = payload[6:].hex()
    resolved_links[link_id] = uri_hex
    return {"link_id": link_id, "uri_hex": uri_hex}


def decode_grid_rows(payload: bytes, begin: dict) -> list[dict]:
    columns = begin["columns"]
    row_bytes = 4 + columns * 8
    require(row_bytes > 0 and len(payload) % row_bytes == 0, "grid_data_size")
    rows = []
    offset = 0
    while offset < len(payload):
        header = payload[offset : offset + 4]
        require(header[0] <= 1, "grid_row_wrapped")
        require(header[1] <= 3, "grid_row_geometry")
        require(u16(header[2:4]) == columns, "grid_row_columns")
        offset += 4
        cells = []
        for _ in range(columns):
            cell = payload[offset : offset + 8]
            codepoint = u32(cell[0:4])
            width, height, x, y = cell[4], cell[5], cell[6], cell[7]
            require(width > 0 and height > 0 and x < width and y < height, "grid_cell_geometry")
            require(codepoint == 0 or valid_scalar(codepoint), "grid_codepoint")
            cells.append(
                {
                    "codepoint": codepoint,
                    "width": width,
                    "height": height,
                    "x": x,
                    "y": y,
                }
            )
            offset += 8
        rows.append(
            {
                "wrapped": bool(header[0]),
                "line_geometry": header[1],
                "columns": columns,
                "cells": cells,
            }
        )
    return rows


def new_snapshot(begin: dict) -> dict:
    return {
        "begin": begin,
        "grid_rows": [],
        "presentation": None,
        "text_rows": [],
        "hyperlinks": [],
        "referenced_links": set(),
        "resolved_links": {},
        "phase": "presentation",
    }


def decode_text_records(payload: bytes, snapshot: dict) -> list[dict]:
    records = []
    offset = 0
    while offset < len(payload):
        require(len(payload) - offset >= TEXT_RECORD_HEADER_BYTES, "text_record_size")
        header = payload[offset : offset + TEXT_RECORD_HEADER_BYTES]
        kind = header[0]
        require(header[1:4] == b"\x00\x00\x00", "text_record_reserved")
        require(kind in TEXT_RECORD_KINDS, "text_record_kind")
        payload_len = u32(header[4:8])
        offset += TEXT_RECORD_HEADER_BYTES
        require(len(payload) - offset >= payload_len, "text_record_size")
        record_payload = payload[offset : offset + payload_len]
        offset += payload_len
        name = TEXT_RECORD_KINDS[kind]

        if name == "presentation":
            require(snapshot["phase"] == "presentation" and snapshot["presentation"] is None, "text_record_order")
            decoded = decode_presentation(record_payload)
            snapshot["presentation"] = decoded
            snapshot["phase"] = "links" if snapshot["begin"]["rows"] == 0 else "rows"
        elif name == "row":
            require(snapshot["phase"] == "rows", "text_record_order")
            require(len(snapshot["text_rows"]) < snapshot["begin"]["rows"], "text_row_count")
            decoded = decode_text_row(
                record_payload,
                snapshot["begin"]["columns"],
                snapshot["referenced_links"],
            )
            snapshot["text_rows"].append(decoded)
            if len(snapshot["text_rows"]) == snapshot["begin"]["rows"]:
                snapshot["phase"] = "links"
        else:
            require(snapshot["phase"] == "links", "text_record_order")
            decoded = decode_hyperlink(record_payload, snapshot["resolved_links"])
            snapshot["hyperlinks"].append(decoded)
        records.append({"kind": name, "payload": decoded})
    require(len(records) == 1, "text_record_count")
    return records


def finish_snapshot(snapshot: dict, end: dict) -> dict:
    begin = snapshot["begin"]
    require(end["revision"] == begin["revision"], "snapshot_revision")
    if begin["format"] == "grid_v1":
        require(len(snapshot["grid_rows"]) == begin["rows"], "grid_row_count")
        return {"begin": begin, "rows": snapshot["grid_rows"], "end": end}

    require(snapshot["presentation"] is not None, "text_presentation_missing")
    require(len(snapshot["text_rows"]) == begin["rows"], "text_row_count")
    require(snapshot["referenced_links"] == set(snapshot["resolved_links"]), "text_unresolved_hyperlink")
    return {
        "begin": begin,
        "presentation": snapshot["presentation"],
        "rows": snapshot["text_rows"],
        "hyperlinks": snapshot["hyperlinks"],
        "end": end,
    }


def decode_fixed_payload(kind: int, payload: bytes) -> dict:
    if kind == 1:
        return decode_hello(payload)
    if kind == 2:
        return decode_welcome(payload)
    if kind == 3:
        return decode_observe(payload)
    if kind == 4:
        return decode_snapshot_begin(payload)
    if kind == 6:
        return decode_snapshot_end(payload)
    if kind == 7:
        return decode_input(payload)
    if kind == 8:
        return decode_assign_leader(payload)
    if kind == 9:
        return decode_resize(payload)
    if kind == 10:
        return decode_signal(payload)
    if kind == 11:
        return decode_result(payload)
    reject("snapshot_data_without_begin")


def decode_stream(data: bytes) -> dict:
    frames = []
    snapshots = []
    snapshot = None
    offset = 0
    while offset < len(data):
        require(len(data) - offset >= HEADER_BYTES, "truncated_header")
        header = data[offset : offset + HEADER_BYTES]
        require(header[0:4] == MAGIC, "header_magic")
        require(header[4] == FRAMING_VERSION, "header_version")
        require(header[6] == 0 and header[7] == 0, "header_reserved")
        kind = header[5]
        require(kind in KINDS, "header_kind")
        payload_len = u32(header[8:12])
        require(payload_len <= MAXIMUM_PAYLOAD_BYTES, "payload_limit")
        offset += HEADER_BYTES
        require(len(data) - offset >= payload_len, "truncated_frame")
        payload = data[offset : offset + payload_len]
        offset += payload_len

        name = KINDS[kind]
        if kind == 4:
            require(snapshot is None, "snapshot_nested")
            decoded = decode_snapshot_begin(payload)
            snapshot = new_snapshot(decoded)
        elif kind == 5:
            require(snapshot is not None, "snapshot_data_without_begin")
            if snapshot["begin"]["format"] == "grid_v1":
                decoded_rows = decode_grid_rows(payload, snapshot["begin"])
                snapshot["grid_rows"].extend(decoded_rows)
                require(len(snapshot["grid_rows"]) <= snapshot["begin"]["rows"], "grid_row_count")
                decoded = {"format": "grid_v1", "rows": decoded_rows}
            else:
                decoded_records = decode_text_records(payload, snapshot)
                decoded = {"format": "text_v1", "records": decoded_records}
        elif kind == 6:
            require(snapshot is not None, "snapshot_end_without_begin")
            decoded = decode_snapshot_end(payload)
            snapshots.append(finish_snapshot(snapshot, decoded))
            snapshot = None
        else:
            require(snapshot is None, "snapshot_interleaved")
            decoded = decode_fixed_payload(kind, payload)
        frames.append({"kind": name, "payload": decoded})

    require(snapshot is None, "snapshot_unterminated")
    return {"frames": frames, "snapshots": snapshots}


def assert_subset(expected, actual, path: str = "value") -> None:
    if isinstance(expected, dict):
        require(isinstance(actual, dict), f"expect_type:{path}")
        for key, value in expected.items():
            require(key in actual, f"expect_missing:{path}.{key}")
            assert_subset(value, actual[key], f"{path}.{key}")
        return
    if isinstance(expected, list):
        require(isinstance(actual, list), f"expect_type:{path}")
        require(len(expected) == len(actual), f"expect_length:{path}")
        for index, (left, right) in enumerate(zip(expected, actual)):
            assert_subset(left, right, f"{path}[{index}]")
        return
    require(expected == actual, f"expect_value:{path}")


def validate_case(case: dict) -> None:
    require(isinstance(case.get("id"), str) and case["id"], "case_id")
    try:
        data = bytes.fromhex(case["hex"])
    except (KeyError, TypeError, ValueError):
        reject("case_hex")

    expected_error = case.get("error")
    if expected_error is not None:
        try:
            decode_stream(data)
        except WireError as error:
            require(error.code == expected_error, f"wrong_error:{case['id']}:{error.code}")
            return
        reject(f"expected_error:{case['id']}")

    decoded = decode_stream(data)
    require("expect" in case, f"case_expect:{case['id']}")
    assert_subset(case["expect"], decoded, case["id"])


def validate_document(document: dict) -> int:
    require(document.get("schema") == "howl.session.wire.v1/vectors", "document_schema")
    cases = document.get("cases")
    require(isinstance(cases, list) and cases, "document_cases")
    seen = set()
    for case in cases:
        require(case.get("id") not in seen, "case_duplicate")
        seen.add(case.get("id"))
        validate_case(case)
    return len(cases)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_vectors.py protocol/v1-vectors.json", file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        count = validate_document(document)
    except (OSError, json.JSONDecodeError, WireError) as error:
        code = error.code if isinstance(error, WireError) else str(error)
        print(f"wire vectors: FAIL: {code}", file=sys.stderr)
        return 1
    print(f"wire vectors: PASS ({count} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
