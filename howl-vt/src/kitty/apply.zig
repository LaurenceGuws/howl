//! Applies Kitty semantic events to bounded terminal-owned Kitty state.

const std = @import("std");
const kitty_color = @import("color.zig");
const input_encode = @import("../input/encode.zig");
const host_state = @import("../host_state.zig");
const semantic_event = @import("../semantic_event.zig");
const terminal_mod = @import("../terminal.zig");

const Terminal = terminal_mod.Terminal;
const SemanticEvent = semantic_event.SemanticEvent;

/// Apply one Kitty-directed semantic event to terminal-owned Kitty state.
pub fn apply(vt: *Terminal, event: SemanticEvent) host_state.ApplyError!void {
    var scratch: input_encode.Scratch = .{};
    const allocator = vt.allocator;
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (event) {
        .kitty_keyboard_set => |req| {
            active_screen.keyboard.set(req.flags, req.mode);
        },
        .kitty_keyboard_query => {
            try active_screen_const.keyboard.appendReport(allocator, &vt.host.pending_output, scratch.buf[0..]);
        },
        .kitty_keyboard_push => |flags| {
            active_screen.keyboard.push(flags);
        },
        .kitty_keyboard_pop => |count| {
            active_screen.keyboard.pop(count);
        },
        .kitty_color_stack => |cmd| {
            switch (cmd) {
                .push => kitty_color.pushState(&vt.kitty.color_stack, &vt.host.colors),
                .pop => kitty_color.popState(&vt.kitty.color_stack, &vt.host.colors),
            }
        },
        else => unreachable,
    }
}
