//! Lossless NDJSON presentation of the reusable native Howl rich snapshot.
//!
//! `howl-client` owns text_v1 parsing and validation. This experimental leaf
//! only formats that already-decoded native model for protocol/AX inspection.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("howl_client");
const wire = @import("wire.zig");

const Rgba = client.rich.Rgba;
const SemanticColor = struct { kind: []const u8, value: u32 };
const Style = struct {
    bits: u16,
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
};
const BeginRecord = struct {
    record: []const u8 = "snapshot_begin",
    revision: u64,
    terminal_revision: u64,
    format: []const u8 = "text_v1",
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_shape: u8,
    cursor_visible: bool,
    cursor_blink: bool,
    alternate_screen: bool,
    stream_closed: bool,
    child_exited: bool,
    leader_present: bool,
    you_are_leader: bool,
};
const PresentationRecord = struct {
    record: []const u8 = "presentation",
    cursor_age_ns: ?u64,
    presence_bits: u8,
    flags: u8,
    reverse_screen: bool,
    palette: [256]Rgba,
    foreground: Rgba,
    background: Rgba,
    cursor: ?Rgba,
    cursor_text: ?Rgba,
    selection_background: ?Rgba,
    selection_foreground: ?Rgba,
};
const CellRecord = struct {
    scalars: []const u32,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
    subscale_n: u8,
    subscale_d: u8,
    vertical_align: u8,
    horizontal_align: u8,
    semantic_width: bool,
    font: u8,
    baseline: u8,
    underline_style: u8,
    protection: u8,
    style: Style,
    foreground: SemanticColor,
    background: SemanticColor,
    underline_color: SemanticColor,
    link_id: u32,
};
const RowRecord = struct {
    record: []const u8 = "row",
    row: u16,
    wrapped: bool,
    line_geometry: u8,
    columns: u16,
    cells: []const CellRecord,
};
const HyperlinkRecord = struct {
    record: []const u8 = "hyperlink",
    link_id: u32,
    uri_bytes_hex: []const u8,
};
const EndRecord = struct {
    record: []const u8 = "snapshot_end",
    revision: u64,
};

pub fn emitSnapshot(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    history_offset: u32,
) !void {
    var snapshot = try client.rich.request(connection, allocator, 0, history_offset);
    defer snapshot.deinit();
    try emitNative(allocator, writer, &snapshot);
}

pub fn receiveAndEmitSnapshot(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void {
    var snapshot = try client.rich.receive(connection, allocator);
    defer snapshot.deinit();
    try emitNative(allocator, writer, &snapshot);
}

fn emitNative(allocator: std.mem.Allocator, writer: *std.Io.Writer, snapshot: *const client.rich.Snapshot) !void {
    const begin = snapshot.begin;
    try emitJson(writer, BeginRecord{
        .revision = begin.revision,
        .terminal_revision = begin.terminal_revision,
        .history_offset = begin.history_offset,
        .history_count = begin.history_count,
        .history_row_base = begin.history_row_base,
        .rows = begin.rows,
        .columns = begin.columns,
        .cursor_row = begin.cursor_row,
        .cursor_column = begin.cursor_column,
        .cursor_shape = begin.cursor_shape,
        .cursor_visible = begin.cursor_visible,
        .cursor_blink = begin.cursor_blink,
        .alternate_screen = begin.alternate_screen,
        .stream_closed = begin.stream_closed,
        .child_exited = begin.child_exited,
        .leader_present = begin.leader_present,
        .you_are_leader = begin.you_are_leader,
    });
    const presentation = snapshot.presentation;
    try emitJson(writer, PresentationRecord{
        .cursor_age_ns = presentation.cursor_age_ns,
        .presence_bits = presentation.presence_bits,
        .flags = presentation.flags,
        .reverse_screen = presentation.reverse_screen,
        .palette = presentation.palette,
        .foreground = presentation.foreground,
        .background = presentation.background,
        .cursor = presentation.cursor,
        .cursor_text = presentation.cursor_text,
        .selection_background = presentation.selection_background,
        .selection_foreground = presentation.selection_foreground,
    });
    for (snapshot.rows, 0..) |row, row_index| {
        const cells = try allocator.alloc(CellRecord, row.cells.len);
        defer allocator.free(cells);
        for (row.cells, cells) |cell, *out| out.* = .{
            .scalars = cell.scalars,
            .width = cell.width,
            .height = cell.height,
            .x = cell.x,
            .y = cell.y,
            .subscale_n = cell.subscale_n,
            .subscale_d = cell.subscale_d,
            .vertical_align = cell.vertical_align,
            .horizontal_align = cell.horizontal_align,
            .semantic_width = cell.semantic_width,
            .font = cell.font,
            .baseline = cell.baseline,
            .underline_style = cell.underline_style,
            .protection = cell.protection,
            .style = style(cell.style_bits),
            .foreground = semanticColor(cell.foreground),
            .background = semanticColor(cell.background),
            .underline_color = semanticColor(cell.underline_color),
            .link_id = cell.link_id,
        };
        try emitJson(writer, RowRecord{
            .row = @intCast(row_index),
            .wrapped = row.wrapped,
            .line_geometry = row.line_geometry,
            .columns = begin.columns,
            .cells = cells,
        });
    }
    for (snapshot.hyperlinks) |link| {
        const hex = try hexBytes(allocator, link.uri_bytes);
        defer allocator.free(hex);
        try emitJson(writer, HyperlinkRecord{ .link_id = link.link_id, .uri_bytes_hex = hex });
    }
    try emitJson(writer, EndRecord{ .revision = begin.revision });
}

fn style(bits: u16) Style {
    return .{
        .bits = bits,
        .bold = bits & protocol.text_v1.style.bold != 0,
        .dim = bits & protocol.text_v1.style.dim != 0,
        .italic = bits & protocol.text_v1.style.italic != 0,
        .blink = bits & protocol.text_v1.style.blink != 0,
        .blink_fast = bits & protocol.text_v1.style.blink_fast != 0,
        .reverse = bits & protocol.text_v1.style.reverse != 0,
        .invisible = bits & protocol.text_v1.style.invisible != 0,
        .underline = bits & protocol.text_v1.style.underline != 0,
        .strikethrough = bits & protocol.text_v1.style.strikethrough != 0,
    };
}

fn semanticColor(value: protocol.TextColor) SemanticColor {
    return .{ .kind = @tagName(value.kind), .value = value.value };
}

fn hexBytes(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    const output = try allocator.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn emitJson(writer: *std.Io.Writer, value: anytype) !void {
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
}
