//! Drives parser actions into semantic routing and bounded DCS capture.

const std = @import("std");
const parsed_events = @import("parser/events.zig");
const route = @import("route.zig");
const parser_mod = @import("parser.zig");
const terminal_mod = @import("terminal.zig");

const Event = parsed_events.Event;

/// Reports parser allocation, parser bound, captured DCS bound, or retained-consequence failure.
pub const FeedError = error{
    ConsequenceLimit,
    OutOfMemory,
    ParsedEventLimit,
    StringControlLimit,
};

/// Reports terminal mutation and distinct title or icon metadata changes.
pub const FeedSummary = struct {
    state_changed: bool,
    title_changed: bool,
    icon_changed: bool,
};

const DcsCapture = struct {
    const StartError = error{OutOfMemory};
    const PutError = error{ OutOfMemory, StringControlLimit };

    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    params: [parser_mod.max_params]i32 = [_]i32{0} ** parser_mod.max_params,
    intermediates: [parser_mod.max_intermediates]u8 = [_]u8{0} ** parser_mod.max_intermediates,
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,

    fn init(allocator: std.mem.Allocator) DcsCapture {
        return .{ .allocator = allocator, .bytes = .empty };
    }

    fn deinit(self: *DcsCapture) void {
        self.bytes.deinit(self.allocator);
    }

    fn reset(self: *DcsCapture) void {
        self.active = false;
        self.payload_start = 0;
        self.final = 0;
        self.param_count = 0;
        self.intermediates_len = 0;
        self.bytes.clearRetainingCapacity();
    }

    fn start(self: *DcsCapture, hook: parser_mod.DcsHook) StartError!void {
        std.debug.assert(hook.count <= parser_mod.max_params);
        std.debug.assert(hook.intermediates_len <= parser_mod.max_intermediates);
        self.reset();
        self.active = true;
        self.final = hook.final;
        self.param_count = hook.count;
        self.intermediates_len = hook.intermediates_len;
        std.mem.copyForwards(i32, self.params[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(u8, self.intermediates[0..hook.intermediates_len], hook.intermediates[0..hook.intermediates_len]);

        errdefer self.reset();
        var idx: u8 = 0;
        while (idx < hook.count) : (idx += 1) {
            if (idx > 0) try self.bytes.append(self.allocator, ';');
            var text_buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{d}", .{hook.params[idx]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(self.allocator, self.intermediates[0..hook.intermediates_len]);
        try self.bytes.append(self.allocator, hook.final);
        self.payload_start = self.bytes.items.len;
    }

    fn put(self: *DcsCapture, byte: u8) PutError!void {
        std.debug.assert(self.active);
        if (self.bytes.items.len - self.payload_start >= @as(usize, parser_mod.max_metadata_control_bytes)) {
            return error.StringControlLimit;
        }
        try self.bytes.append(self.allocator, byte);
    }

    fn event(self: *const DcsCapture) Event {
        std.debug.assert(self.active);
        return .{ .dcs = .{
            .body = self.bytes.items,
            .payload = self.bytes.items[self.payload_start..],
            .final = self.final,
            .params = self.params[0..self.param_count],
            .param_count = self.param_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        } };
    }
};

/// Owns parser allocation and bounded DCS capture for one terminal lifetime.
pub const TerminalStreamState = struct {
    /// Stream-state initialization can fail only while allocating parser storage.
    pub const InitError = error{OutOfMemory};

    parser: parser_mod.Parser,
    dcs: DcsCapture,

    /// Initializes parser storage and an empty DCS capture with one borrowed allocator.
    pub fn initAlloc(allocator: std.mem.Allocator) InitError!TerminalStreamState {
        return .{
            .parser = try parser_mod.Parser.init(allocator),
            .dcs = DcsCapture.init(allocator),
        };
    }

    /// Releases parser and DCS capture allocations.
    pub fn deinit(self: *TerminalStreamState) void {
        self.dcs.deinit();
        self.parser.deinit();
    }
};

/// Borrows one terminal while translating input bytes into terminal mutation.
pub const Stream = struct {
    terminal: *terminal_mod.Terminal,

    /// Creates a stream borrowing the terminal until the stream is discarded.
    pub fn init(terminal: *terminal_mod.Terminal) Stream {
        return .{ .terminal = terminal };
    }

    /// Feeds one byte and omits the optional mutation summary while preserving failures.
    pub fn next(self: *Stream, byte: u8) FeedError!void {
        const summary = try self.nextSummary(byte);
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    /// Feeds a borrowed byte slice and omits the optional mutation summary.
    pub fn nextSlice(self: *Stream, bytes: []const u8) FeedError!void {
        const summary = try self.nextSliceSummary(bytes);
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    fn nextSummary(self: *Stream, byte: u8) FeedError!FeedSummary {
        var state_changed = false;
        var title_changed = false;
        var icon_changed = false;
        const state = &self.terminal.stream_state;

        errdefer {
            state.parser.reset();
            state.dcs.reset();
        }

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;

        for (phases) |phase| {
            if (phase) |action| {
                const effect = try self.applyAction(action);
                state_changed = state_changed or effect.changed;
                title_changed = title_changed or effect.title_changed;
                icon_changed = icon_changed or effect.icon_changed;
            }
        }

        return .{
            .state_changed = state_changed,
            .title_changed = title_changed,
            .icon_changed = icon_changed,
        };
    }

    /// Feeds a complete borrowed slice and merges per-byte mutation summaries.
    pub fn nextSliceSummary(self: *Stream, bytes: []const u8) FeedError!FeedSummary {
        var summary: FeedSummary = .{
            .state_changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
        for (bytes) |byte| {
            const byte_summary = try self.nextSummary(byte);
            summary.state_changed = summary.state_changed or byte_summary.state_changed;
            summary.title_changed = summary.title_changed or byte_summary.title_changed;
            summary.icon_changed = summary.icon_changed or byte_summary.icon_changed;
        }
        return summary;
    }

    fn applyAction(self: *Stream, action: parser_mod.Action) FeedError!route.EventEffect {
        return switch (action) {
            .print => |cp| self.applyPrint(cp),
            .execute => |ctrl| self.applyExecute(ctrl),
            .invalid => try self.applyEvent(.invalid_sequence),
            .csi_dispatch => |csi| try self.applyEvent(.{ .style_change = .{
                .final = csi.final,
                .params = csi.params[0..csi.count],
                .separators = csi.separators,
                .param_count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = csi.intermediates[0..csi.intermediates_len],
                .intermediates_len = csi.intermediates_len,
            } }),
            .osc_dispatch => |osc| try self.applyEvent(.{ .osc = osc }),
            .apc_start, .apc_put, .apc_end => discardedStringControl(),
            .dcs_hook => |hook| self.startDcs(hook),
            .dcs_put => |byte| self.putDcs(byte),
            .dcs_unhook => self.endDcs(),
            .pm_start, .pm_put, .pm_end => discardedStringControl(),
            .sos_start, .sos_put, .sos_end => discardedStringControl(),
            .esc_dispatch => |esc| self.applyEsc(esc),
        };
    }

    fn applyPrint(self: *Stream, cp: u21) FeedError!route.EventEffect {
        const mapped = self.mapCodepoint(cp);
        if (mapped <= 0x7f) {
            const ascii: [1]u8 = .{@intCast(mapped)};
            return try self.applyEvent(.{ .text = ascii[0..] });
        }
        return try self.applyEvent(.{ .codepoint = mapped });
    }

    fn applyExecute(self: *Stream, ctrl: u8) FeedError!route.EventEffect {
        switch (ctrl) {
            0x0E => {
                self.terminal.gl_index = 1;
                return .{
                    .changed = true,
                    .title_changed = false,
                    .icon_changed = false,
                };
            },
            0x0F => {
                self.terminal.gl_index = 0;
                return .{
                    .changed = true,
                    .title_changed = false,
                    .icon_changed = false,
                };
            },
            else => return try self.applyEvent(.{ .control = ctrl }),
        }
    }

    fn applyEsc(self: *Stream, esc: parser_mod.EscAction) FeedError!route.EventEffect {
        if (esc.intermediates_len == 1) {
            switch (esc.intermediates[0]) {
                '(' => {
                    self.terminal.g0_designation = esc.final;
                    return .{
                        .changed = true,
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                ')' => {
                    self.terminal.g1_designation = esc.final;
                    return .{
                        .changed = true,
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                else => {},
            }
        }
        return try self.applyEvent(.{ .esc_dispatch = esc });
    }

    fn applyEvent(self: *Stream, event: Event) FeedError!route.EventEffect {
        return try route.apply(self.terminal, event);
    }

    fn startDcs(self: *Stream, hook: parser_mod.DcsHook) FeedError!route.EventEffect {
        try self.terminal.stream_state.dcs.start(hook);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn putDcs(self: *Stream, byte: u8) FeedError!route.EventEffect {
        try self.terminal.stream_state.dcs.put(byte);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn endDcs(self: *Stream) FeedError!route.EventEffect {
        const state = &self.terminal.stream_state;
        const event = state.dcs.event();
        defer state.dcs.reset();
        return try route.apply(self.terminal, event);
    }

    fn mapCodepoint(self: *const Stream, cp: u21) u21 {
        if (!isDecSpecial(self.terminal)) return cp;
        if (cp < 0x20 or cp > 0x7e) return cp;
        return mapDecSpecial(@intCast(cp));
    }
};

fn discardedStringControl() route.EventEffect {
    return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
}

fn isDecSpecial(terminal: *const terminal_mod.Terminal) bool {
    return switch (terminal.gl_index) {
        0 => terminal.g0_designation == '0',
        1 => terminal.g1_designation == '0',
        else => false,
    };
}

fn mapDecSpecial(byte: u8) u21 {
    return switch (byte) {
        '`' => 0x25C6,
        'a' => 0x2592,
        'f' => 0x00B0,
        'g' => 0x00B1,
        'h' => 0x2424,
        'i' => 0x240B,
        'j' => 0x2518,
        'k' => 0x2510,
        'l' => 0x250C,
        'm' => 0x2514,
        'n' => 0x253C,
        'o' => 0x23BA,
        'p' => 0x23BB,
        'q' => 0x2500,
        'r' => 0x23BC,
        's' => 0x23BD,
        't' => 0x251C,
        'u' => 0x2524,
        'v' => 0x2534,
        'w' => 0x252C,
        'x' => 0x2502,
        'y' => 0x2264,
        'z' => 0x2265,
        '{' => 0x03C0,
        '|' => 0x2260,
        '}' => 0x00A3,
        '~' => 0x00B7,
        else => byte,
    };
}

test "stream state initialization reports parser allocation failure" {
    const init: *const fn (std.mem.Allocator) TerminalStreamState.InitError!TerminalStreamState = TerminalStreamState.initAlloc;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator()));
    try std.testing.expect(failing.has_induced_failure);
}

test "DCS capture start and put report exact failures and remain reusable" {
    const start: *const fn (*DcsCapture, parser_mod.DcsHook) DcsCapture.StartError!void = DcsCapture.start;
    const put: *const fn (*DcsCapture, u8) DcsCapture.PutError!void = DcsCapture.put;
    const hook: parser_mod.DcsHook = .{
        .final = 'q',
        .params = &.{1},
        .count = 1,
        .intermediates = "$",
        .intermediates_len = 1,
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var capture = DcsCapture.init(failing.allocator());
    defer capture.deinit();

    try std.testing.expectError(error.OutOfMemory, start(&capture, hook));
    try std.testing.expect(!capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try start(&capture, hook);
    const payload_start = capture.payload_start;
    failing.fail_index = failing.alloc_index;

    var put_count: u32 = 0;
    while (!failing.has_induced_failure) : (put_count += 1) {
        try std.testing.expect(put_count < parser_mod.max_metadata_control_bytes);
        put(&capture, 'x') catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            break;
        };
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(capture.active);
    try std.testing.expectEqual(payload_start + put_count, capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try put(&capture, 'y');
    while (capture.bytes.items.len - capture.payload_start < parser_mod.max_metadata_control_bytes) {
        try put(&capture, 'z');
    }
    try std.testing.expectError(error.StringControlLimit, put(&capture, 'z'));
    capture.reset();
    try std.testing.expect(!capture.active);
    try start(&capture, hook);
}

test "discarded string controls stream without retaining payload bytes" {
    var terminal = try terminal_mod.Terminal.init(std.testing.allocator, 2, 2);
    defer terminal.deinit();
    var stream = Stream.init(&terminal);

    try stream.nextSlice("\x1b_G");
    try stream.nextSlice("x" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1b^");
    try stream.nextSlice("y" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1bX");
    try stream.nextSlice("z" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("ok");

    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u21, 'o'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), view.cellAt(0, 1));
}
