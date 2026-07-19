//! Defines parser event values consumed by semantic routing.

const parser_mod = @import("../parser.zig");

/// Parser output event.
const StyleChange = struct {
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    param_count: u8,
    leader: u8,
    private: bool,
    intermediates: []const u8,
    intermediates_len: u8,
};

const DcsEvent = struct {
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediates: []const u8,
    intermediates_len: u8,
};

/// Carries one parser event with slices borrowed until the next parser advance.
pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    invoke_charset: u8,
    configure_charset: struct { slot: u8, designation: u8 },
    style_change: StyleChange,
    osc: parser_mod.OscAction,
    apc: []const u8,
    dcs: DcsEvent,
    pm: []const u8,
    esc_dispatch: parser_mod.EscAction,
    invalid_sequence,
};
