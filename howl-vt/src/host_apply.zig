//! Applies semantic events whose consequences belong to the embedding host.

const std = @import("std");
const locator = @import("locator.zig");
const osc_color = @import("osc_color.zig");
const screen = @import("screen.zig");
const kitty_color = @import("kitty/color.zig");
const input_encode = @import("input/encode.zig");
const semantic_event = @import("semantic_event.zig");
const terminal_mod = @import("terminal.zig");

const LocatorNs = locator;
const OscColorNs = osc_color;
const HostState = @import("host_state.zig");
const Terminal = terminal_mod.Terminal;
const SemanticEvent = semantic_event.SemanticEvent;

/// Apply one host-directed semantic event and retain its bounded consequence.
pub fn apply(vt: *Terminal, event: SemanticEvent) HostState.ApplyError!void {
    var scratch: input_encode.Scratch = .{};
    const allocator = vt.allocator;
    switch (event) {
        .bell => try vt.host.ringBell(),
        .title_and_icon_set => |value| try vt.host.replaceTitleAndIcon(value),
        .title_set => |title| try vt.host.replaceTitle(title),
        .icon_set => |icon| try vt.host.replaceIcon(icon),
        .shell_integration_set => |integration| try vt.host.replaceShellIntegration(integration),
        .shell_mark => |mark| try vt.host.replaceShellMark(mark),
        .color_control => |cmd| {
            switch (cmd.command) {
                21 => try kitty_color.handleKittyControl(allocator, &vt.host.colors, &vt.host.pending_output, cmd.payload),
                4 => try OscColorNs.handleXtermPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                5 => try OscColorNs.handleXtermSpecialPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try OscColorNs.handleXtermDynamicColor(
                    allocator,
                    &vt.host.colors,
                    &vt.host.pending_output,
                    scratch.buf[0..],
                    cmd.command,
                    cmd.payload,
                ),
                104 => OscColorNs.resetXtermPalette(&vt.host.colors, cmd.payload),
                110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => OscColorNs.resetXtermDynamicColor(&vt.host.colors, cmd.command, cmd.payload),
                else => {},
            }
        },
        .hyperlink_set => |uri| vt.screen_state.active().setCurrentLinkId(try vt.host.internHyperlink(uri)),
        .hyperlink_clear => vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| try vt.host.replaceClipboard(payload),
        .locator_reporting => |cfg| LocatorNs.setReporting(&vt.host.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| LocatorNs.setFilter(&vt.host.locator, area),
        .locator_events => |modes| LocatorNs.setEvents(&vt.host.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| try LocatorNs.appendReportForRequest(&vt.host.locator, allocator, &vt.host.pending_output, scratch.buf[0..], param),
        .media_copy_request => |param| vt.host.media_copy_request = param,
        .dcs_payload => |payload| try vt.host.replaceDcsPayload(payload),
        .legacy_control => |kind| vt.host.legacy_control = kind,
        else => unreachable,
    }
}
