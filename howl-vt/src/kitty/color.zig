//! Owns Kitty color-stack mutation and color-control replies.

const std = @import("std");
const osc_color = @import("../osc_color.zig");
const host_state = @import("../host_state.zig");

const OscColor = osc_color;

const State = OscColor.TerminalColorState;

/// Selects one terminal-owned Kitty color-stack operation.
pub const Command = enum { push, pop };

/// Stores at most sixteen complete terminal color states for Kitty push and pop.
pub const Stack = struct {
    stack: [16]State = undefined,
    len: u8 = 0,
};

/// Pushes a color state, dropping the oldest entry when the stack is full.
pub fn pushState(stack: *Stack, colors: *const State) void {
    if (stack.len == stack.stack.len) {
        std.mem.copyForwards(State, stack.stack[0 .. stack.stack.len - 1], stack.stack[1..stack.stack.len]);
        stack.len -= 1;
    }
    stack.stack[stack.len] = colors.*;
    stack.len += 1;
}

/// Restores the newest color state when present and decrements the exposed depth.
pub fn popState(stack: *Stack, colors: *State) void {
    if (stack.len == 0) return;
    stack.len -= 1;
    colors.* = stack.stack[stack.len];
}

/// Applies one Kitty color control or appends its bounded query reply.
pub fn handleKittyControl(allocator: std.mem.Allocator, colors: *State, output: *std.ArrayList(u8), payload: []const u8) host_state.ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=');
        if (eq) |pos| {
            const key = std.mem.trim(u8, part[0..pos], " \t");
            const value = std.mem.trim(u8, part[pos + 1 ..], " \t");
            if (std.mem.eql(u8, value, "?")) {
                try appendKittyQueryReply(allocator, output, key, colors.*);
            } else {
                OscColor.setColorKey(colors, key, value);
            }
        } else {
            OscColor.resetColorKey(colors, std.mem.trim(u8, part, " \t"));
        }
    }
}
fn appendKittyQueryReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), key: []const u8, colors: State) host_state.ApplyError!void {
    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, "\x1b]21;");
    try host_state.appendOutput(output, allocator, key);
    try host_state.appendOutput(output, allocator, "=");
    if (OscColor.colorForKey(colors, key)) |color| {
        try OscColor.appendColorOsc(allocator, output, color);
    } else if (OscColor.isKnownColorKey(key)) {
        // Empty value means dynamic/undefined for Kitty color control.
    } else {
        try host_state.appendOutput(output, allocator, "?");
    }
    try host_state.appendOutput(output, allocator, "\x1b\\");
}
