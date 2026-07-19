//! Exercises hostile bytes and lifecycle operations through the native embedding root.

const std = @import("std");
const howl_vt = @import("howl_vt");

const rows_max: u16 = 32;
const cols_max: u16 = 96;
const history_max: u16 = 128;
const operations_max: u8 = 32;
const feed_max: usize = 256;
const input_max: usize = 256;

const Operation = enum {
    feed,
    resize,
    reject_zero_resize,
    reset_and_reuse,
    input_bytes,
    keyboard,
    keyboard_unicode,
    mouse,
    focus,
    paste,
    selection,
    drain_output,
    drain_clipboard,
    acknowledge,
    scroll_viewport,
    inspect,
};

test "native Terminal hostile input and lifecycle" {
    try std.testing.fuzz({}, fuzzTerminal, .{});
}

fn fuzzTerminal(_: void, smith: *std.testing.Smith) !void {
    const initial_rows = smith.valueRangeAtMost(u16, 1, rows_max);
    const initial_cols = smith.valueRangeAtMost(u16, 1, cols_max);
    const history_capacity = smith.valueRangeAtMost(u16, 0, history_max);
    var terminal = try howl_vt.Terminal.initWithHistory(
        std.testing.allocator,
        initial_rows,
        initial_cols,
        history_capacity,
    );
    defer terminal.deinit();

    try assertPublicInvariants(&terminal, history_capacity);

    var operation_count: u8 = 0;
    while (operation_count < operations_max and !smith.eosWeightedSimple(7, 1)) : (operation_count += 1) {
        switch (smith.value(Operation)) {
            .feed => {
                var bytes: [feed_max]u8 = undefined;
                const len = smith.slice(&bytes);
                try feedHostile(&terminal, bytes[0..len]);
            },
            .resize => {
                const rows = smith.valueRangeAtMost(u16, 1, rows_max);
                const cols = smith.valueRangeAtMost(u16, 1, cols_max);
                try terminal.resize(rows, cols);
            },
            .reject_zero_resize => {
                const before = terminal.visibleMeta();
                if (smith.value(bool)) {
                    try std.testing.expectError(error.InvalidDimensions, terminal.resize(0, before.cols));
                } else {
                    try std.testing.expectError(error.InvalidDimensions, terminal.resize(before.rows, 0));
                }
                const after = terminal.visibleMeta();
                try std.testing.expectEqual(before.rows, after.rows);
                try std.testing.expectEqual(before.cols, after.cols);
                try std.testing.expectEqual(before.history_count, after.history_count);
                try std.testing.expectEqual(before.is_alternate_screen, after.is_alternate_screen);
                _ = try terminal.feed("R");
            },
            .reset_and_reuse => {
                terminal.resetScreen();
                _ = try terminal.feed("R");
            },
            .input_bytes => try encodeBytes(&terminal, smith),
            .keyboard => try encodeKeyboard(&terminal, smith),
            .keyboard_unicode => try encodeUnicodeKeyboard(&terminal, smith),
            .mouse => try encodeMouse(&terminal, smith),
            .focus => try encodeFocus(&terminal, smith),
            .paste => try encodePaste(&terminal, smith),
            .selection => try mutateSelection(&terminal, smith),
            .drain_output => try drainOutput(&terminal),
            .drain_clipboard => try drainClipboard(&terminal),
            .acknowledge => try acknowledgeAndReuse(&terminal),
            .scroll_viewport => scrollViewport(&terminal, smith),
            .inspect => {},
        }
        try assertPublicInvariants(&terminal, history_capacity);
    }
}

fn feedHostile(terminal: *howl_vt.Terminal, bytes: []const u8) !void {
    _ = terminal.feed(bytes) catch |err| switch (err) {
        error.ConsequenceLimit,
        error.ParsedEventLimit,
        error.StringControlLimit,
        => {
            _ = try terminal.feed("R");
            return;
        },
        error.OutOfMemory => return err,
    };
}

fn encodeBytes(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    var bytes: [input_max]u8 = undefined;
    const len = smith.slice(&bytes);
    var scratch: howl_vt.Terminal.InputScratch = .{};
    var encoded = try terminal.encodeInput(std.testing.allocator, &scratch, .{ .bytes = bytes[0..len] });
    defer encoded.deinit();
    try std.testing.expectEqualSlices(u8, bytes[0..len], encoded.bytes);
}

fn encodeKeyboard(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    var scratch: howl_vt.Terminal.InputScratch = .{};
    const event: howl_vt.Terminal.InputEvent = .{
        .key = .{
            .key = switch (smith.valueRangeAtMost(u8, 0, 3)) {
                0 => .{ .named = .enter },
                1 => .{ .named = .tab },
                2 => .{ .named = .up },
                else => .{ .named = .f12 },
            },
            .mods = .{
                .shift = smith.value(bool),
                .alt = smith.value(bool),
                .control = smith.value(bool),
            },
        },
    };
    var encoded = try terminal.encodeInput(std.testing.allocator, &scratch, event);
    defer encoded.deinit();
    try std.testing.expect(encoded.bytes.len <= scratch.buf.len);
}

fn encodeUnicodeKeyboard(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    const Key = @FieldType(@FieldType(howl_vt.Terminal.InputEvent, "key"), "key");
    const generated = Key.initUnicode(smith.value(u21)) catch |err| switch (err) {
        error.InvalidUnicodeScalar => try Key.initUnicode('A'),
    };
    var scratch: howl_vt.Terminal.InputScratch = .{};
    var encoded = try terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .key = .{ .key = generated } },
    );
    defer encoded.deinit();
    try std.testing.expect(encoded.bytes.len <= scratch.buf.len);
}

fn encodeMouse(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    try feedHostile(terminal, switch (smith.valueRangeAtMost(u8, 0, 3)) {
        0 => "\x1b[?1000h",
        1 => "\x1b[?1002h\x1b[?1006h",
        2 => "\x1b[?1003h\x1b[?1015h",
        else => "\x1b[?1000l",
    });
    var scratch: howl_vt.Terminal.InputScratch = .{};
    const event: howl_vt.Terminal.InputEvent = .{
        .mouse = .{
            .kind = switch (smith.valueRangeAtMost(u8, 0, 3)) {
                0 => .press,
                1 => .release,
                2 => .move,
                else => .wheel,
            },
            .button = switch (smith.valueRangeAtMost(u8, 0, 5)) {
                0 => .none,
                1 => .left,
                2 => .middle,
                3 => .right,
                4 => .wheel_up,
                else => .wheel_down,
            },
            .row = smith.value(i32),
            .col = smith.value(u16),
            .pixel_x = if (smith.value(bool)) smith.value(u32) else null,
            .pixel_y = if (smith.value(bool)) smith.value(u32) else null,
            .mod = .{
                .shift = smith.value(bool),
                .alt = smith.value(bool),
                .control = smith.value(bool),
            },
            .buttons_down = smith.value(u8),
        },
    };
    var encoded = terminal.encodeInput(std.testing.allocator, &scratch, event) catch |err| switch (err) {
        error.ConsequenceLimit => {
            const pending = try terminal.drainPendingOutput(std.testing.allocator);
            std.testing.allocator.free(pending);
            var retry = try terminal.encodeInput(std.testing.allocator, &scratch, event);
            retry.deinit();
            return;
        },
        error.OutOfMemory => return err,
        error.LengthOverflow => return err,
        // Generated key events carry no committed text.
        error.InvalidUtf8, error.InvalidText, error.KeyTextLimit => unreachable,
    };
    defer encoded.deinit();
    try std.testing.expect(encoded.bytes.len <= scratch.buf.len);
}

fn encodeFocus(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    try feedHostile(terminal, if (smith.value(bool)) "\x1b[?1004h" else "\x1b[?1004l");
    var scratch: howl_vt.Terminal.InputScratch = .{};
    var encoded = try terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .focus = if (smith.value(bool)) .in else .out },
    );
    defer encoded.deinit();
    try std.testing.expect(encoded.bytes.len <= scratch.buf.len);
}

fn encodePaste(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    try feedHostile(terminal, if (smith.value(bool)) "\x1b[?2004h" else "\x1b[?2004l");
    var text: [input_max]u8 = undefined;
    const len = smith.slice(&text);
    var scratch: howl_vt.Terminal.InputScratch = .{};
    var encoded = try terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .paste = text[0..len] },
    );
    defer encoded.deinit();
    try std.testing.expect(encoded.bytes.len <= input_max + 12);
}

fn mutateSelection(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) !void {
    terminal.startSelection(smith.value(i32), smith.value(u16));
    terminal.updateSelection(smith.value(i32), smith.value(u16));
    terminal.finishSelection();
    const generated = try terminal.copySelection(std.testing.allocator);
    std.testing.allocator.free(generated);
    if (smith.value(bool)) terminal.clearSelection();

    // Arbitrary histories may select no text, so allocation retention uses one
    // known cell without weakening the generated live-terminal mutation.
    var proof = try howl_vt.Terminal.init(std.testing.allocator, 1, 1);
    defer proof.deinit();
    _ = try proof.feed("S");
    proof.startSelection(0, 0);
    proof.updateSelection(0, 0);
    proof.finishSelection();
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, proof.copySelection(failing.allocator()));
    const copied = try proof.copySelection(std.testing.allocator);
    try std.testing.expectEqualStrings("S", copied);
    std.testing.allocator.free(copied);
}

fn drainOutput(terminal: *howl_vt.Terminal) !void {
    const previous = try terminal.drainPendingOutput(std.testing.allocator);
    std.testing.allocator.free(previous);
    // CAN returns an arbitrary preceding byte history to parser ground.
    try feedHostile(terminal, "\x18\x1b[5n");
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, terminal.drainPendingOutput(failing.allocator()));
    const output = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(output);
    const empty = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

fn drainClipboard(terminal: *howl_vt.Terminal) !void {
    if (try terminal.drainPendingClipboard(std.testing.allocator)) |previous| {
        std.testing.allocator.free(previous);
    }
    // CAN makes the retained OSC consequence independent of preceding bytes.
    try feedHostile(terminal, "\x18\x1b]52;c;SG93bA==\x07");
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, terminal.drainPendingClipboard(failing.allocator()));
    const clipboard = (try terminal.drainPendingClipboard(std.testing.allocator)).?;
    defer std.testing.allocator.free(clipboard);
    try std.testing.expectEqualStrings("Howl", clipboard);
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.drainPendingClipboard(std.testing.allocator));
}

fn acknowledgeAndReuse(terminal: *howl_vt.Terminal) !void {
    const publication = terminal.surfaceSnapshot();
    try std.testing.expect(!terminal.ackSurface(0));
    try std.testing.expect(terminal.ackSurface(publication.snapshot_seq));
    _ = try terminal.feed("\x18A");
    const next = terminal.surfaceSnapshot();
    try std.testing.expect(next.dirty_generation != publication.dirty_generation);
    try std.testing.expect(terminal.ackSurface(next.snapshot_seq));
}

fn scrollViewport(terminal: *howl_vt.Terminal, smith: *std.testing.Smith) void {
    _ = terminal.scrollViewport(switch (smith.valueRangeAtMost(u8, 0, 3)) {
        0 => .top,
        1 => .bottom,
        2 => .{ .delta = smith.value(i64) },
        else => .{ .absolute = smith.value(u64) },
    });
}

fn assertPublicInvariants(terminal: *howl_vt.Terminal, history_capacity: u16) !void {
    const publication = terminal.surfaceSnapshot();
    const view = publication.snapshot.view;
    try std.testing.expect(view.rows > 0);
    try std.testing.expect(view.cols > 0);
    try std.testing.expect(view.cursor_row < view.rows);
    try std.testing.expect(view.cursor_col < view.cols);
    try std.testing.expect(view.history_count <= history_capacity);
    if (view.is_alternate_screen) try std.testing.expectEqual(@as(u32, 0), view.history_count);
    try std.testing.expect(publication.snapshot_seq != 0);

    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            _ = view.cellInfoAt(row, col);
        }
    }
    try std.testing.expect(terminal.ackSurface(publication.snapshot_seq));
}
