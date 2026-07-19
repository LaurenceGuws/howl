//! Decodes ordinary CSI commands without private leaders or intermediates.

const csi_params = @import("csi_params.zig");
const events = @import("semantic_event.zig");
const erase = @import("screen/erase.zig");
const params_mod = @import("csi_params.zig");

const SemanticEvent = events.SemanticEvent;
const CsiSeparatorList = csi_params.CsiSeparatorList;

/// Decodes one ordinary CSI sequence; unsupported forms return null.
pub fn process(final: u8, params: []const i32, separators: CsiSeparatorList, intermediates: []const u8) ?SemanticEvent {
    switch (final) {
        '@' => return SemanticEvent{ .insert_chars = params_mod.paramAtOrDefault1(params, 0) },
        'A' => return SemanticEvent{ .cursor_up = params_mod.paramAtOrDefault1(params, 0) },
        'B', 'e' => return SemanticEvent{ .cursor_down = params_mod.paramAtOrDefault1(params, 0) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = params_mod.paramAtOrDefault1(params, 0) },
        'b' => return SemanticEvent{ .repeat_preceding = params_mod.paramAtOrDefault1(params, 0) },
        'D' => return SemanticEvent{ .cursor_back = params_mod.paramAtOrDefault1(params, 0) },
        'E' => return SemanticEvent{ .cursor_next_line = params_mod.paramAtOrDefault1(params, 0) },
        'F' => return SemanticEvent{ .cursor_prev_line = params_mod.paramAtOrDefault1(params, 0) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = params_mod.paramAtOrDefault1(params, 0) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = params_mod.paramAtOrDefault1(params, 0) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = params_mod.paramAtOrDefault1(params, 0) },
        'g' => switch (params_mod.paramAtOrDefault0(params, 0)) {
            0 => return SemanticEvent.tab_clear_current,
            3 => return SemanticEvent.tab_clear_all,
            else => return null,
        },
        'Z' => return SemanticEvent{ .horizontal_tab_back = params_mod.paramAtOrDefault1(params, 0) },
        'L' => return SemanticEvent{ .insert_lines = params_mod.paramAtOrDefault1(params, 0) },
        'M' => return SemanticEvent{ .delete_lines = params_mod.paramAtOrDefault1(params, 0) },
        'P' => return SemanticEvent{ .delete_chars = params_mod.paramAtOrDefault1(params, 0) },
        'S' => return SemanticEvent{ .scroll_up_lines = params_mod.paramAtOrDefault1(params, 0) },
        'T' => return SemanticEvent{ .scroll_down_lines = params_mod.paramAtOrDefault1(params, 0) },
        'h' => return SemanticEvent{ .ansi_mode_set = params_mod.collectParams(params) },
        'l' => return SemanticEvent{ .ansi_mode_reset = params_mod.collectParams(params) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .separators = separators } },
        's' => if (params.len == 0) return SemanticEvent.save_cursor else return SemanticEvent{ .set_left_right_margins = .{
            .left = params_mod.paramAtOrDefault1(params, 0) - 1,
            .right = if (params.len >= 2 and params[1] > 0) params_mod.paramAtOrDefault1(params, 1) - 1 else null,
        } },
        'u' => return SemanticEvent.restore_cursor,
        'H', 'f' => {
            const row = params_mod.paramAtOrDefault1(params, 0);
            const col = params_mod.paramAtOrDefault1(params, 1);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = params_mod.paramAtOrDefault1(params, 0) - 1,
            .bottom = if (params.len >= 2 and params[1] > 0) params_mod.paramAtOrDefault1(params, 1) - 1 else null,
        } },
        'J' => return eraseDisplayEvent(params_mod.eraseMode(params_mod.paramAtOrDefault0(params, 0)), false),
        'K' => return SemanticEvent{ .erase_line = params_mod.eraseMode(params_mod.paramAtOrDefault0(params, 0)) },
        'X' => return SemanticEvent{ .erase_chars = params_mod.paramAtOrDefault1(params, 0) },
        'x' => return SemanticEvent{ .parameters_report = params_mod.paramAtOrDefault0(params, 0) },
        'n' => switch (params_mod.paramAtOrDefault0(params, 0)) {
            5 => return SemanticEvent.device_status_report,
            6 => return SemanticEvent.cursor_position_report,
            else => return null,
        },
        'c' => return SemanticEvent.primary_device_attributes,
        'p' => {
            if (params.len == 0 and intermediates.len == 1 and intermediates[0] == '!') {
                return SemanticEvent.reset_screen;
            }
            return null;
        },
        else => return null,
    }
}

fn eraseDisplayEvent(mode: erase.EraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}
