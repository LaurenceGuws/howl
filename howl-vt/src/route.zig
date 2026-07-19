//! Converts parser events into canonical semantic events and applies them by owner.

const events = @import("semantic_event.zig");
const host_apply = @import("host_apply.zig");
const kitty_apply = @import("kitty/apply.zig");
const report_apply = @import("report.zig");
const parsed_events = @import("parser/events.zig");
const parser_mod = @import("parser.zig");
const terminal_mod = @import("terminal.zig");
const c0 = @import("c0.zig");
const csi = @import("csi.zig");
const dcs = @import("dcs.zig");
const esc = @import("esc.zig");
const osc = @import("osc.zig");
const osc_color = @import("osc_color.zig");
const host_state = @import("host_state.zig");

/// Parser event classified before semantic dispatch.
const Event = parsed_events.Event;
/// Canonical parser-to-domain vocabulary exposed to routing tests.
const SemanticEvent = events.SemanticEvent;

const Terminal = terminal_mod.Terminal;

/// Observable terminal mutations produced while applying one parser event.
pub const EventEffect = struct {
    changed: bool,
    title_changed: bool,
    icon_changed: bool,
};

/// Classify one parsed event into the canonical parser-to-domain vocabulary.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| {
            const params = sc.params[0..sc.param_count];
            const intermediates = sc.intermediates[0..sc.intermediates_len];
            return csi.process(sc.final, params, sc.separators, sc.leader, sc.private, intermediates);
        },
        .invoke_charset, .configure_charset => return null,
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return c0.process(c0.fromByte(c)),
        .osc => |osc_event| return processOscEvent(osc_event),
        .esc_dispatch => |esc_dispatch| return esc.process(esc_dispatch.final),
        .apc => return null,
        .dcs => |dcs_data| return dcs.process(dcs_data),
        .pm, .invalid_sequence => return null,
    }
}

fn processOscEvent(osc_event: parser_mod.OscAction) ?SemanticEvent {
    return osc.process(osc_event);
}

/// Apply one parser event and report whether terminal or title state changed.
pub fn apply(vt: *Terminal, event: Event) host_state.ApplyError!EventEffect {
    switch (event) {
        .invoke_charset => |slot| {
            vt.gl_index = slot;
            return .{ .changed = true, .title_changed = false, .icon_changed = false };
        },
        .configure_charset => |cfg| {
            switch (cfg.slot) {
                0 => vt.g0_designation = cfg.designation,
                1 => vt.g1_designation = cfg.designation,
                else => unreachable,
            }
            return .{ .changed = true, .title_changed = false, .icon_changed = false };
        },
        else => {},
    }

    const semantic = process(event) orelse return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
    try applySemantic(vt, semantic);
    return switch (semantic) {
        .title_and_icon_set => .{
            .changed = true,
            .title_changed = true,
            .icon_changed = true,
        },
        .title_set => .{
            .changed = true,
            .title_changed = true,
            .icon_changed = false,
        },
        .icon_set => .{
            .changed = true,
            .title_changed = false,
            .icon_changed = true,
        },
        else => .{
            .changed = true,
            .title_changed = false,
            .icon_changed = false,
        },
    };
}

fn applySemantic(vt: *Terminal, event: SemanticEvent) host_state.ApplyError!void {
    switch (event) {
        .reset_screen => vt.resetScreen(),
        .save_cursor => vt.saveCursor(),
        .restore_cursor => vt.restoreCursor(),
        .enter_alt_screen => |opts| {
            vt.switchScreenMode(true, opts.clear, opts.save_cursor);
        },
        .exit_alt_screen => |opts| {
            vt.switchScreenMode(false, false, opts.restore_cursor);
        },
        .ansi_mode_query,
        .modify_other_keys_query,
        .key_format_query,
        .dec_mode_query,
        .dcs_request_status,
        .dcs_request_termcap,
        .dcs_request_resource,
        .device_status_report,
        .dec_device_status_report,
        .cursor_position_report,
        .dec_cursor_position_report,
        .primary_device_attributes,
        .secondary_device_attributes,
        .tertiary_device_attributes,
        .xtversion,
        .xttitlepos,
        .xtchecksum,
        .rect_checksum_request,
        .selected_graphic_rendition_report,
        .screen_extent_report,
        .parameters_report,
        .xtreportcolors,
        .iterm_report_cell_size,
        => try report_apply.apply(vt, event),

        .kitty_keyboard_set,
        .kitty_keyboard_query,
        .kitty_keyboard_push,
        .kitty_keyboard_pop,
        .kitty_color_stack,
        => try kitty_apply.apply(vt, event),

        .application_cursor_keys,
        .application_keypad,
        .reverse_screen_mode,
        .ansi_mode_set,
        .ansi_mode_reset,
        .modify_other_keys_set,
        .modify_other_keys_disable,
        .key_format_change,
        .pointer_mode,
        .reverse_wraparound_mode,
        .extended_reverse_wraparound_mode,
        .focus_reporting,
        .bracketed_paste,
        .synchronized_output,
        .mouse_tracking_off,
        .mouse_tracking_x10,
        .mouse_tracking_normal,
        .mouse_tracking_button_event,
        .mouse_tracking_any_event,
        .mouse_protocol_utf8,
        .mouse_protocol_sgr,
        .mouse_protocol_urxvt,
        .dec_mode_save,
        .dec_mode_restore,
        => vt.applyModeEvent(event),

        .color_control => |control| {
            if (osc_color.cursorColorEvent(control)) |cursor_event| {
                vt.screen_state.active().applyScreen(cursor_event);
            }
            try host_apply.apply(vt, event);
        },
        .iterm_set_colors => |payload| {
            osc_color.handleItermSetColors(&vt.host.colors, payload);
        },
        .bell,
        .title_and_icon_set,
        .title_set,
        .icon_set,
        .shell_integration_set,
        .shell_mark,
        .hyperlink_set,
        .hyperlink_clear,
        .clipboard_set,
        .locator_reporting,
        .locator_filter,
        .locator_events,
        .locator_request,
        .media_copy_request,
        .dcs_payload,
        .legacy_control,
        => try host_apply.apply(vt, event),

        .cursor_up,
        .cursor_down,
        .cursor_forward,
        .cursor_back,
        .cursor_next_line,
        .cursor_prev_line,
        .cursor_horizontal_absolute,
        .cursor_vertical_absolute,
        .cursor_position,
        .write_text,
        .write_codepoint,
        .repeat_preceding,
        .line_feed,
        .next_line,
        .reverse_index,
        .carriage_return,
        .backspace,
        .horizontal_tab,
        .horizontal_tab_forward,
        .horizontal_tab_back,
        .horizontal_tab_set,
        .tab_clear_current,
        .tab_clear_all,
        .cursor_visible,
        .cursor_style,
        .cursor_shape,
        .cursor_color,
        .cursor_text_color,
        .auto_wrap,
        .origin_mode,
        .insert_mode,
        .sgr,
        .insert_lines,
        .delete_lines,
        .insert_chars,
        .delete_chars,
        .scroll_up_lines,
        .scroll_down_lines,
        .set_scroll_region,
        .erase_display_below,
        .erase_display_above,
        .erase_display_complete,
        .erase_display_scrollback,
        .erase_display_scroll_complete,
        .erase_line,
        .selective_erase_line,
        .erase_chars,
        .shift_left_columns,
        .shift_right_columns,
        .character_protection,
        .rect_erase,
        .rect_selective_erase,
        .rect_fill,
        .rect_copy,
        .rect_attrs_change,
        .insert_columns,
        .delete_columns,
        .attr_change_extent_rect,
        .left_right_margin_mode,
        .set_left_right_margins,
        .reset_default_tab_stops,
        => vt.screen_state.active().applyScreen(event),
    }
}
