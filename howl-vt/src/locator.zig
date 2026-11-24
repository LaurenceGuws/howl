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

const Position = struct { row: u32, col: u32 };

const FilterRect = struct {
    top: u32,
    left: u32,
    bottom: u32,
    right: u32,

    fn contains(self: FilterRect, point: Position) bool {
        return point.row >= self.top and point.row <= self.bottom and
            point.col >= self.left and point.col <= self.right;
    }
};

const Filter = union(enum) {
    rectangle: FilterRect,
    defined_entry,
};

/// Zero-based filter coordinates whose omitted edges use the latest pointer position.
pub const FilterArea = struct {
    top: ?u32,
    left: ?u32,
    bottom: ?u32,
    right: ?u32,
};

/// Owns DEC locator reporting mode, filtering, and latest pointer state.
pub const State = struct {
    mode: ReportingMode = .disabled,
    active: bool = true,
    coordinate_unit: u16 = 0,
    report_button_down: bool = false,
    report_button_up: bool = false,
    filter: ?Filter = null,
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
        self.filter = null;
    }

    /// Arms a one-shot filter, or reports immediately when already outside it.
    /// Invalid bounds and failed immediate replies preserve the previous latch.
    pub fn setFilter(
        self: *State,
        output: *replies.Buffer,
        encode_buf: []u8,
        area: FilterArea,
    ) replies.AppendError!bool {
        if (self.mode == .disabled) return false;
        if (area.top) |top| {
            if (area.bottom) |bottom| if (top > bottom) return false;
        }
        if (area.left) |left| {
            if (area.right) |right| if (left > right) return false;
        }

        const point = self.coordinates();
        const omitted = area.top == null or area.left == null or area.bottom == null or area.right == null;
        if (point == null and omitted) {
            const changed = self.filter == null or self.filter.? != .defined_entry;
            self.filter = .defined_entry;
            return changed;
        }

        const row = if (point) |value| value.row else 0;
        const col = if (point) |value| value.col else 0;
        const rect: FilterRect = .{
            .top = area.top orelse row,
            .left = area.left orelse col,
            .bottom = area.bottom orelse row,
            .right = area.right orelse col,
        };
        if (rect.top > rect.bottom or rect.left > rect.right) return false;
        if (point == null or !rect.contains(point.?)) {
            try self.appendReport(output, encode_buf, 10, self.last_buttons_down);
            self.filter = null;
            return true;
        }
        const next: Filter = .{ .rectangle = rect };
        const changed = !std.meta.eql(self.filter, @as(?Filter, next));
        self.filter = next;
        return changed;
    }

    /// Replaces selected button and filter event flags from borrowed DEC modes.
    pub fn setEvents(self: *State, modes: []const u16) void {
        const selected: []const u16 = if (modes.len == 0) &.{0} else modes;
        for (selected) |mode| switch (mode) {
            0 => {
                self.report_button_down = false;
                self.report_button_up = false;
                self.filter = null;
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
        const valid_row = std.math.cast(u16, event.row);
        if (valid_row) |row| {
            self.last_row = row;
            self.last_col = event.col;
            self.last_pixel_x = event.pixel_x;
            self.last_pixel_y = event.pixel_y;
        } else {
            self.clearCoordinates();
        }

        if (self.mode == .disabled) return;
        const point = self.coordinates();
        const outside = if (self.filter) |filter| switch (filter) {
            .rectangle => |rect| if (point) |value| !rect.contains(value) else true,
            .defined_entry => point != null,
        } else false;

        const event_code: ?u16 = if (valid_row == null) null else switch (event.kind) {
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

        // One caller sample is one transaction. Retain its facts, but neither
        // consume a latch nor publish a partial ordered report batch on failure.
        const start = output.len();
        const prior_mode = self.mode;
        errdefer {
            output.truncate(start);
            self.mode = prior_mode;
        }
        if (event_code) |code| try self.appendReport(output, encode_buf, code, event.buttons_down);
        if (outside and self.mode != .disabled) {
            try self.appendReport(output, encode_buf, 10, event.buttons_down);
            self.filter = null;
        }
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

    fn coordinates(self: *const State) ?Position {
        if (!self.active) return null;
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
    var state: State = .{ .mode = .continuous, .last_row = 5, .last_col = 7 };
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;

    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = 2, .left = null, .bottom = 6, .right = null }));
    const valid: Filter = .{ .rectangle = .{ .top = 2, .left = 7, .bottom = 6, .right = 7 } };
    try std.testing.expectEqualDeep(valid, state.filter.?);
    try std.testing.expect(!(try state.setFilter(&output, &scratch, .{ .top = 8, .left = 0, .bottom = 3, .right = 9 })));
    try std.testing.expectEqualDeep(valid, state.filter.?);
    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = null, .left = null, .bottom = null, .right = null }));
    try std.testing.expectEqualDeep(Filter{ .rectangle = .{ .top = 5, .left = 7, .bottom = 5, .right = 7 } }, state.filter.?);
    try std.testing.expectEqualStrings("", output.bytes());
}

test "locator one-shot and filter latches commit only after reply append" {
    var state: State = .{ .last_row = 1, .last_col = 1 };
    state.setReporting(2, 0);
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = 1, .left = 1, .bottom = 2, .right = 2 }));

    const full = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(full);
    @memset(full, 'x');
    try output.append(full);
    try std.testing.expectError(error.ReplyLimit, state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 4, 5, 1, null, null)));
    try std.testing.expectEqual(ReportingMode.one_shot, state.mode);
    try std.testing.expect(state.filter != null);
    try std.testing.expectEqualSlices(u8, full, output.bytes());
    output.truncate(0);
    try state.handleMouseEvent(&output, &scratch, mouse(.press, .left, 4, 5, 1, null, null));
    try std.testing.expectEqualStrings("\x1b[10;4;5;6;1&w", output.bytes());
    try std.testing.expectEqual(ReportingMode.disabled, state.mode);
    try std.testing.expectEqual(@as(?Filter, null), state.filter);
}

test "locator undefined query preserves one-shot and filter under reply pressure" {
    var state: State = .{};
    state.setReporting(2, 0);
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = null, .left = 1, .bottom = 2, .right = 2 }));
    const before = state;
    const full = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(full);
    @memset(full, 'x');
    try output.append(full);

    try std.testing.expectError(error.ReplyLimit, state.appendReportForRequest(&output, &scratch, 0));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expectEqualSlices(u8, full, output.bytes());
    output.truncate(0);
    try state.appendReportForRequest(&output, &scratch, 1);
    try std.testing.expectEqualStrings("\x1b[1;0&w", output.bytes());
    try std.testing.expectEqual(ReportingMode.disabled, state.mode);
    try std.testing.expectEqualDeep(before.filter, state.filter);

    state.setReporting(1, 0);
    try std.testing.expect(state.filter == null);
    state.setEvents(&.{ 1, 3 });
    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = null, .left = 1, .bottom = 2, .right = 2 }));
    state.setEvents(&.{});
    try std.testing.expect(!state.report_button_down and !state.report_button_up);
    try std.testing.expect(state.filter == null);
    state.setActive(false);
    state.reset();
    try std.testing.expect(!state.active);
    state.setReporting(1, 0);
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, 2, 3, 1, null, null));
    output.truncate(0);
    try state.appendReportForRequest(&output, &scratch, 1);
    try std.testing.expectEqualStrings("\x1b[0&w", output.bytes());
}

test "locator filter undefined entry and immediate report rollback" {
    var state: State = .{};
    state.setReporting(1, 0);
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    const omitted: FilterArea = .{ .top = null, .left = null, .bottom = null, .right = null };
    const explicit: FilterArea = .{ .top = 0, .left = 0, .bottom = 0, .right = 0 };
    try std.testing.expect(try state.setFilter(&output, &scratch, omitted));
    try std.testing.expect(state.filter.? == .defined_entry);
    const full = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(full);
    @memset(full, 'x');
    try output.append(full);
    const before = state;
    try std.testing.expectError(error.ReplyLimit, state.setFilter(&output, &scratch, explicit));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expectEqualSlices(u8, full, output.bytes());
    output.truncate(0);
    try std.testing.expect(try state.setFilter(&output, &scratch, explicit));
    try std.testing.expectEqualStrings("\x1b[10;0&w", output.bytes());
    try std.testing.expect(state.filter == null);
    output.truncate(0);
    state.setActive(false);
    try std.testing.expect(try state.setFilter(&output, &scratch, explicit));
    try std.testing.expectEqualStrings("\x1b[10;0&w", output.bytes());
    output.truncate(0);
    try std.testing.expect(try state.setFilter(&output, &scratch, omitted));
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, 0, 0, 0, null, null));
    try std.testing.expectEqualStrings("", output.bytes());
    state.setActive(true);
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, 2, 3, 0, null, null));
    try std.testing.expectEqualStrings("\x1b[10;0;3;4;1&w", output.bytes());
    try std.testing.expect(state.filter == null);
    output.truncate(0);
    try std.testing.expect(try state.setFilter(&output, &scratch, omitted));
    try state.handleMouseEvent(&output, &scratch, mouse(.move, .none, -1, 0, 0, null, null));
    try std.testing.expectEqualStrings("\x1b[10;0&w", output.bytes());
}

test "locator simultaneous report rollback retains exact prior prefix" {
    var state: State = .{ .last_row = 1, .last_col = 1 };
    state.setReporting(1, 0);
    state.setEvents(&.{1});
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [report_max_bytes]u8 = undefined;
    try std.testing.expect(try state.setFilter(&output, &scratch, .{ .top = null, .left = null, .bottom = null, .right = null }));
    const first = "\x1b[2;4;3;3;1&w";
    const second = "\x1b[10;4;3;3;1&w";
    const prefix = try std.testing.allocator.alloc(u8, replies.max_bytes - first.len);
    defer std.testing.allocator.free(prefix);
    @memset(prefix, 'k');
    try output.append(prefix);
    const filter = state.filter;
    const event = mouse(.press, .left, 2, 2, 1, null, null);
    try std.testing.expectError(error.ReplyLimit, state.handleMouseEvent(&output, &scratch, event));
    try std.testing.expectEqualSlices(u8, prefix, output.bytes());
    try std.testing.expectEqualDeep(filter, state.filter);
    try std.testing.expectEqual(ReportingMode.continuous, state.mode);
    output.truncate(0);
    try state.handleMouseEvent(&output, &scratch, event);
    try std.testing.expectEqualStrings(first ++ second, output.bytes());
    try std.testing.expect(state.filter == null);
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
