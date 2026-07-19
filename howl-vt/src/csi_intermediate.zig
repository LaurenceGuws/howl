//! Decodes CSI commands distinguished by intermediate bytes.

const events = @import("semantic_event.zig");
const params_mod = @import("csi_params.zig");

const SemanticEvent = events.SemanticEvent;

/// Decodes one CSI sequence with intermediates; unsupported forms return null.
pub fn process(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len == 2) return processPair(final, params, intermediates);
    if (intermediates.len != 1) return null;
    return switch (intermediates[0]) {
        '"' => processQuote(final, params),
        '$' => processDollar(final, params),
        '*' => processStar(final, params),
        '+' => processPlus(final, params),
        '#' => processHash(final, params),
        '\'' => processTick(final, params),
        ' ' => processSpace(final, params),
        else => null,
    };
}

fn processPair(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates[0] != '\'' or intermediates[1] != '*') return null;
    if (final != '{') return null;
    return SemanticEvent{ .locator_events = params_mod.collectParams(params) };
}

fn processQuote(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'q') {
        return switch (params_mod.paramAtOrDefault0(params, 0)) {
            0, 2 => SemanticEvent{ .character_protection = false },
            1 => SemanticEvent{ .character_protection = true },
            else => null,
        };
    }
    if (final == 'v') return SemanticEvent.screen_extent_report;
    return null;
}

fn processDollar(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'p' => SemanticEvent{ .ansi_mode_query = params_mod.paramAtOrDefault0(params, 0) },
        'r' => rectAttrsChange(params, false),
        't' => rectAttrsChange(params, true),
        'v' => rectCopy(params),
        'x' => rectFill(params),
        'z' => SemanticEvent{ .rect_erase = params_mod.rectArea(params, 0) },
        '{' => SemanticEvent{ .rect_selective_erase = params_mod.rectArea(params, 0) },
        else => null,
    };
}

fn processStar(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'x') {
        return switch (params_mod.paramAtOrDefault0(params, 0)) {
            0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
            2 => SemanticEvent{ .attr_change_extent_rect = true },
            else => null,
        };
    }
    if (final != 'y') return null;
    return SemanticEvent{ .rect_checksum_request = .{
        .request_id = params_mod.paramAtOrDefault0(params, 0),
        .page = params_mod.paramAtOrDefault1(params, 1),
        .area = params_mod.rectArea(params, 2),
    } };
}

fn processPlus(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'T' => SemanticEvent{ .scroll_down_lines = params_mod.paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processHash(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'P' => if (params.len == 0) SemanticEvent{ .kitty_color_stack = .push } else null,
        'Q' => if (params.len == 0) SemanticEvent{ .kitty_color_stack = .pop } else null,
        'S' => SemanticEvent.xttitlepos,
        'y' => SemanticEvent{ .xtchecksum = params_mod.paramAtOrDefault0(params, 0) },
        'R' => SemanticEvent.xtreportcolors,
        '|' => SemanticEvent{ .selected_graphic_rendition_report = params_mod.rectArea(params, 0) },
        else => null,
    };
}

fn processTick(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'w' => SemanticEvent{ .locator_filter = params_mod.optionalRectArea(params) },
        '}' => SemanticEvent{ .insert_columns = params_mod.paramAtOrDefault1(params, 0) },
        'z' => SemanticEvent{ .locator_reporting = .{
            .mode = params_mod.paramAtOrDefault0(params, 0),
            .unit = params_mod.paramAtOrDefault0(params, 1),
        } },
        '|' => SemanticEvent{ .locator_request = params_mod.paramAtOrDefault0(params, 0) },
        '~' => SemanticEvent{ .delete_columns = params_mod.paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processSpace(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'q' => SemanticEvent{ .cursor_style = params_mod.cursorStyle(params_mod.paramAtOrDefault0(params, 0)) },
        '@' => SemanticEvent{ .shift_left_columns = params_mod.paramAtOrDefault1(params, 0) },
        'A' => SemanticEvent{ .shift_right_columns = params_mod.paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn rectAttrsChange(params: []const i32, reverse: bool) SemanticEvent {
    return .{ .rect_attrs_change = .{
        .area = params_mod.rectArea(params, 0),
        .attrs = params_mod.attrParams(params, 4),
        .reverse = reverse,
    } };
}

fn rectCopy(params: []const i32) SemanticEvent {
    return .{ .rect_copy = .{
        .area = params_mod.rectArea(params, 0),
        .source_page = params_mod.paramAtOrDefault1(params, 4),
        .dest_top = params_mod.paramAtOrDefault1(params, 5) - 1,
        .dest_left = params_mod.paramAtOrDefault1(params, 6) - 1,
        .dest_page = params_mod.paramAtOrDefault1(params, 7),
    } };
}

fn rectFill(params: []const i32) ?SemanticEvent {
    const ch = params_mod.paramAtOrDefault0(params, 0);
    if (!params_mod.isValidRectFillChar(ch)) return null;
    return .{ .rect_fill = .{ .area = params_mod.rectArea(params, 1), .ch = ch } };
}
