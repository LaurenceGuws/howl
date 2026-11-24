//! DEC locator reporting state and bounded child-directed replies.
//!
//! Terminal decoding selects locator operations; this owner retains reporting
//! mode, coordinate policy, filter latches, and the latest caller mouse facts.

const std = @import("std");
const input = @import("input.zig");
const replies = @import("replies.zig");

const report_max_bytes: usize = 40;

const ReportingMode = enum(u2) {
    disabled,
    continuous,
    one_shot,
};

const FilterRect = struct {
    top: u16,
    left: u16,
    bottom: u16,
    right: u16,
};

/// Zero-based filter coordinates whose omitted edges use the latest pointer position.
pub const FilterArea = struct {
    top: ?u16,
    left: ?u16,
    bottom: ?u16,
    right: ?u16,
};

/// Owns DEC locator reporting mode, filtering, and latest pointer state.
pub const State = struct {
    mode: ReportingMode = .disabled,
    active: bool = true,
    coordinate_unit: u16 = 0,
    report_button_down: bool = false,
    report_button_up: bool = false,
    filter_rect: ?FilterRect = null,
    last_row: ?u16 = null,
    last_col: ?u16 = null,
    last_pixel_x: ?u32 = null,
    last_pixel_y: ?u32 = null,
    last_buttons_down: u8 = 0,

    /// Restores the disabled default without allocation.
    pub fn reset(self: *State) void {
        self.* = .{ .active = self.active };
    }

    /// Accepts the caller's session focus, independently of focus-report mode.
    pub fn setActive(self: *State, active: bool) void {
        if (self.active == active) return;
        self.active = active;
        self.clearCoordinates();
        self.last_buttons_down = 0;
    }

    fn clearCoordinates(self: *State) void {
        self.last_row = null;
        self.last_col = null;
        self.last_pixel_x = null;
        self.last_pixel_y = null;
    }

    /// Selects reporting mode and cell-or-pixel coordinates.
    pub fn setReporting(self: *State, mode: u16, unit: u16) void {
        self.mode = switch (mode) {
            1 => .continuous,
            2 => .one_shot,
            else => .disabled,
        };
        self.coordinate_unit = unit;
        self.filter_rect = null;
    }

    /// Installs an optional filter rectangle using the latest position for omitted edges.
    pub fn setFilter(self: *State, area: FilterArea) void {
        const row = self.last_row orelse 0;
        const col = self.last_col orelse 0;
        const top = area.top orelse row;
        const left = area.left orelse col;
        const bottom = area.bottom orelse row;
        const right = area.right orelse col;
        if (area.top == null and area.left == null and area.bottom == null and area.right == null) {
            self.filter_rect = null;
            return;
        }
        if (top > bottom or left > right) return;
        self.filter_rect = .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    /// Replaces selected button and filter event flags from borrowed DEC modes.
    pub fn setEvents(self: *State, modes: []const u16) void {
        const selected: []const u16 = if (modes.len == 0) &.{0} else modes;
        for (selected) |mode| switch (mode) {
            0 => {
                self.report_button_down = false;
                self.report_button_up = false;
                self.filter_rect = null;
            },
            1 => self.report_button_down = true,
            2 => self.report_button_down = false,
            3 => self.report_button_up = true,
            4 => self.report_button_up = false,
            else => {},
        };
    }

    /// Appends a bounded status or current-position report for a valid request.
    pub fn appendReportForRequest(
        self: *State,
        output: *replies.Buffer,
        encode_buf: []u8,
        param: u16,
    ) replies.AppendError!void {
        if (param > 1) return;
        if (self.mode == .disabled or !self.active) {
            try output.appendCsi(.terminal, "0&w");
            return;
        }
        try self.appendReport(output, encode_buf, 1, self.last_buttons_down);
    }

    /// Updates representable coordinates and emits enabled reports transactionally.
    ///
    /// Rows outside the retained coordinate domain invalidate the latest position.
    /// Inactive sessions do not accept locator facts. Reply failure preserves
    /// one-shot and filter latches while retaining the latest pointer facts.
    pub fn handleMouseEvent(
        self: *State,
        output: *replies.Buffer,
        encode_buf: []u8,
        event: input.MouseEvent,
    ) replies.AppendError!void {
        if (!self.active) return;
        self.last_buttons_down = event.buttons_down;
        if (event.row < 0 or event.row > std.math.maxInt(u16)) {
            self.clearCoordinates();
            return;
        }
        const row: u16 = @intCast(event.row);
        const col = event.col;
        self.last_row = row;
        self.last_col = col;
        self.last_pixel_x = event.pixel_x;
        self.last_pixel_y = event.pixel_y;

        if (self.mode == .disabled) return;

        if (self.filter_rect) |filter| {
            if (row < filter.top or row > filter.bottom or col < filter.left or col > filter.right) {
                try self.appendReport(output, encode_buf, 10, event.buttons_down);
                self.filter_rect = null;
                return;
            }
        }

        const event_code: ?u16 = switch (event.kind) {
            .press => if (self.report_button_down) switch (event.button) {
                .left => 2,
                .middle => 4,
                .right => 6,
                else => null,
            } else null,
            .release => if (self.report_button_up) switch (event.button) {
                .left => 3,
                .middle => 5,
                .right => 7,
                else => null,
            } else null,
            else => null,
        };
        if (event_code) |code| try self.appendReport(output, encode_buf, code, event.buttons_down);
    }

    fn appendReport(
        self: *State,
        output: *replies.Buffer,
        encode_buf: []u8,
        event_code: u16,
        buttons_down: u8,
    ) replies.AppendError!void {
        const button_mask = buttonsMask(buttons_down);
        std.debug.assert(encode_buf.len >= report_max_bytes);
        const text = if (self.coordinates()) |coords|
            std.fmt.bufPrint(
                encode_buf,
                "{d};{d};{d};{d};1&w",
                .{ event_code, button_mask, @as(u64, coords.row) + 1, @as(u64, coords.col) + 1 },
            )
        else
            std.fmt.bufPrint(encode_buf, "{d};{d}&w", .{ event_code, button_mask });
        // zig-audit: acknowledge catch_unreachable
        // reason: The bounded report buffer fits all event codes, button masks, and one-based u32 coordinates.
        try output.appendCsi(.terminal, text catch unreachable);
        if (self.mode == .one_shot) self.mode = .disabled;
    }

    fn coordinates(self: *const State) ?struct { row: u32, col: u32 } {
        const row = self.last_row orelse return null;
        const col = self.last_col orelse return null;
        if (self.coordinate_unit == 1) {
            return .{
                .row = self.last_pixel_y orelse return null,
                .col = self.last_pixel_x orelse return null,
            };
        }
        return .{ .row = row, .col = col };
    }
};

/// Appends the two supported DEC locator device-status replies.
pub fn appendDeviceStatusReport(
    output: *replies.Buffer,
    encode_buf: []u8,
    param: u16,
) replies.AppendError!void {
    const text = switch (param) {
        // zig-audit: acknowledge catch_unreachable
        // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
        55 => std.fmt.bufPrint(encode_buf, "?50n", .{}) catch unreachable,
        // zig-audit: acknowledge catch_unreachable
        // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
        56 => std.fmt.bufPrint(encode_buf, "?57;1n", .{}) catch unreachable,
        else => return,
    };
    try output.appendCsi(.terminal, text);
}

fn buttonsMask(buttons_down: u8) u16 {
    var mask: u16 = 0;
    if ((buttons_down & 0b001) != 0) mask |= 4;
    if ((buttons_down & 0b010) != 0) mask |= 2;
    if ((buttons_down & 0b100) != 0) mask |= 1;
    return mask;
}

test "locator emits exact cell and pixel reports" {
    var state: State = .{};
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;

    try state.appendReportForRequest(&output, &scratch, 0);
    try std.testing.expectEqualStrings("\x1b[0&w", output.bytes());
    output.truncate(0);

    state.setReporting(1, 0);
    state.setEvents(&.{ 1, 3 });
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 2, 3, 1, null, null));
    try std.testing.expectEqualStrings("\x1b[2;4;3;4;1&w", output.bytes());
    output.truncate(0);

    state.setReporting(1, 1);
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 4, 5, 1, 9, 11));
    try std.testing.expectEqualStrings("\x1b[2;4;12;10;1&w", output.bytes());
}

test "locator one-based pixel reports preserve the full u32 coordinate domain" {
    var state: State = .{};
    state.setReporting(1, 1);
    state.setEvents(&.{1});
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 2, 3, 1, std.math.maxInt(u32), std.math.maxInt(u32)));
    try std.testing.expectEqualStrings("\x1b[2;4;4294967296;4294967296;1&w", output.bytes());
    output.truncate(0);
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 2, 3, 1, std.math.maxInt(u32) - 1, std.math.maxInt(u32) - 1));
    try std.testing.expectEqualStrings("\x1b[2;4;4294967295;4294967295;1&w", output.bytes());
}

test "locator filter resolves omitted edges and preserves its valid latch" {
    var state: State = .{ .last_row = 5, .last_col = 7 };

    state.setFilter(.{ .top = 2, .left = null, .bottom = 6, .right = null });
    const valid = FilterRect{ .top = 2, .left = 7, .bottom = 6, .right = 7 };
    try std.testing.expectEqualDeep(valid, state.filter_rect.?);

    state.setFilter(.{ .top = 8, .left = 0, .bottom = 3, .right = 9 });
    try std.testing.expectEqualDeep(valid, state.filter_rect.?);

    state.setFilter(.{ .top = null, .left = null, .bottom = null, .right = null });
    try std.testing.expectEqual(@as(?FilterRect, null), state.filter_rect);
}

test "locator one-shot and filter latches commit only after reply append" {
    var state: State = .{};
    state.setReporting(2, 0);
    state.setEvents(&.{1});
    state.setFilter(.{ .top = 1, .left = 1, .bottom = 2, .right = 2 });

    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    const full = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(full);
    @memset(full, 'x');
    try output.append(full);
    var scratch: [report_max_bytes]u8 = undefined;

    try std.testing.expectError(
        error.ReplyLimit,
        state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 4, 5, 1, null, null)),
    );
    try std.testing.expectEqual(ReportingMode.one_shot, state.mode);
    try std.testing.expect(state.filter_rect != null);
    try std.testing.expectEqual(@as(usize, replies.max_bytes), output.bytes().len);

    output.truncate(0);
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 4, 5, 1, null, null));
    try std.testing.expectEqualStrings("\x1b[10;4;5;6;1&w", output.bytes());
    try std.testing.expectEqual(ReportingMode.disabled, state.mode);
    try std.testing.expectEqual(@as(?FilterRect, null), state.filter_rect);
}

test "locator undefined query preserves one-shot and filter under reply pressure" {
    var state: State = .{};
    state.setReporting(2, 0);
    state.setFilter(.{ .top = 1, .left = 1, .bottom = 2, .right = 2 });
    const before = state;
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    const full = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(full);
    @memset(full, 'x');
    try output.append(full);
    var scratch: [report_max_bytes]u8 = undefined;

    try std.testing.expectError(error.ReplyLimit, state.appendReportForRequest(&output, &scratch, 0));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expectEqualSlices(u8, full, output.bytes());
    output.truncate(0);
    try state.appendReportForRequest(&output, &scratch, 1);
    try std.testing.expectEqualStrings("\x1b[1;0&w", output.bytes());
    try std.testing.expectEqual(ReportingMode.disabled, state.mode);
    try std.testing.expectEqualDeep(before.filter_rect, state.filter_rect);

    state.setReporting(1, 0);
    try std.testing.expect(state.filter_rect == null);
    state.setEvents(&.{ 1, 3 });
    state.setFilter(.{ .top = 1, .left = 1, .bottom = 2, .right = 2 });
    state.setEvents(&.{});
    try std.testing.expect(!state.report_button_down and !state.report_button_up);
    try std.testing.expect(state.filter_rect == null);
    state.setActive(false);
    state.reset();
    try std.testing.expect(!state.active);
    state.setReporting(1, 0);
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, 2, 3, 1, null, null));
    output.truncate(0);
    try state.appendReportForRequest(&output, &scratch, 1);
    try std.testing.expectEqualStrings("\x1b[0&w", output.bytes());
}

test "locator reset clears every retained pointer fact and event selection" {
    var state: State = .{};
    state.setReporting(1, 1);
    state.setEvents(&.{ 1, 3 });
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, 8, 9, 0, 30, 40));

    state.reset();

    try std.testing.expectEqualDeep(State{}, state);
}

fn mouse(
    kind: input.MouseEventKind,
    button: input.MouseButton,
    row: i32,
    col: u16,
    buttons_down: u8,
    pixel_x: ?u32,
    pixel_y: ?u32,
) input.MouseEvent {
    return .{
        .kind = kind,
        .button = button,
        .row = row,
        .col = col,
        .pixel_x = pixel_x,
        .pixel_y = pixel_y,
        .mod = .{},
        .buttons_down = buttons_down,
    };
}
