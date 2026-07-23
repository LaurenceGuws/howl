//! Proves stateless terminal projection through exact VT byte transcripts.

const std = @import("std");
const vt = @import("howl_vt");
const terminal = @import("howl_render").terminal;

const selection = terminal.SelectionStyle{
    .foreground = .{ .r = 0xee, .g = 0xdd, .b = 0xcc },
    .background = .{ .r = 0x33, .g = 0x22, .b = 0x11 },
};

const Storage = struct {
    cells: [64]terminal.Cell = undefined,
    rows: [8]terminal.RowPatch = undefined,

    fn buffers(self: *Storage) terminal.Buffers {
        return .{ .cells = &self.cells, .rows = &self.rows };
    }
};

fn full(source: vt.Terminal.VisualView, storage: *Storage) !terminal.Update {
    return terminal.project(source, .full, storage.buffers(), selection);
}

test "full projection resolves terminal colors selection geometry and cursor" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed(
        "\x1b[38;2;1;2;3;48;2;4;5;6;58;2;7;8;9;3;4mA\r\nB\x1b#6",
    )).state_changed);
    source.startSelection(0, 0);
    source.updateSelection(0, 0);

    var storage: Storage = .{};
    const update = try full(source.visualView(), &storage);
    try std.testing.expect(update.full);
    try std.testing.expectEqual(@as(usize, 2), update.row_patches.len);
    try std.testing.expectEqual(@as(usize, 8), update.cells.len);
    try std.testing.expectEqual(terminal.LineGeometry.double_width, update.row_patches[1].geometry);
    try std.testing.expect(update.cells[0].selected);
    try std.testing.expectEqual(selection.foreground, update.cells[0].foreground);
    try std.testing.expectEqual(selection.background, update.cells[0].background);
    try std.testing.expect(update.cells[0].italic);
    try std.testing.expectEqual(terminal.UnderlineStyle.single, update.cells[0].underline_style);
    try std.testing.expectEqual(terminal.Rgb{ .r = 7, .g = 8, .b = 9 }, update.cells[0].underline_color);
    try std.testing.expect(update.cursor.visible);
}

test "OSC 66 projection copies complete sizing and expands selection appearance" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 6);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b]66;s=2:w=2:n=1:d=2:v=2:h=1;Hi\x1b\\")).state_changed);
    source.startSelection(0, 2);
    source.updateSelection(0, 3);
    try std.testing.expect(source.visualView().selectedSpan(0) != null);

    var storage: Storage = .{};
    const update = try full(source.visualView(), &storage);
    const expected = terminal.TextSizing{
        .width = 4,
        .height = 2,
        .subscale_n = 1,
        .subscale_d = 2,
        .vertical_align = 2,
        .horizontal_align = 1,
    };
    try std.testing.expectEqual(expected, update.cells[0].sizing);
    try std.testing.expect(update.cells[0].selected);
    try std.testing.expect(update.cells[3].selected);
    try std.testing.expect(update.cells[6].selected);
    try std.testing.expect(update.cells[9].selected);
    try std.testing.expectEqual(@as(u8, 3), update.cells[9].sizing.x);
    try std.testing.expectEqual(@as(u8, 1), update.cells[9].sizing.y);
}

test "dynamic colors resolve complete cell cursor and selection presentation" {
    var source = try vt.Terminal.init(std.testing.allocator, 1, 2);
    defer source.deinit();
    try std.testing.expect((try source.feed("AB")).state_changed);

    var storage: Storage = .{};
    const initial_view = source.visualView();
    const initial = try full(initial_view, &storage);
    try std.testing.expect(source.ackVisual(initial_view.dirty_token));

    try std.testing.expect((try source.feed(
        "\x1b]10;#010203\x1b\\\x1b]11;#040506\x1b\\\x1b]12;#070809\x1b\\" ++
            "\x1b]17;#0a0b0c\x1b\\\x1b]19;#0d0e0f\x1b\\",
    )).state_changed);
    source.startSelection(0, 0);
    source.updateSelection(0, 0);
    const changed_view = source.visualView();
    try std.testing.expectEqual(vt.Terminal.VisualDirty.full, changed_view.dirty);
    try std.testing.expectError(error.FullRequired, terminal.project(
        changed_view,
        .{ .incremental = initial.next_baseline },
        storage.buffers(),
        selection,
    ));
    const changed = try full(changed_view, &storage);
    try std.testing.expectEqual(terminal.Rgb{ .r = 13, .g = 14, .b = 15 }, changed.cells[0].foreground);
    try std.testing.expectEqual(terminal.Rgb{ .r = 10, .g = 11, .b = 12 }, changed.cells[0].background);
    try std.testing.expectEqual(terminal.Rgb{ .r = 1, .g = 2, .b = 3 }, changed.cells[1].foreground);
    try std.testing.expectEqual(terminal.Rgb{ .r = 4, .g = 5, .b = 6 }, changed.cells[1].background);
    try std.testing.expectEqual(terminal.Rgb{ .r = 7, .g = 8, .b = 9 }, changed.cursor.color);

    try std.testing.expect((try source.feed(
        "\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\\x1b]17;?\x1b\\\x1b]19;?\x1b\\",
    )).state_changed);
    const replies = try source.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(replies);
    try std.testing.expectEqualStrings(
        "\x1b]10;rgb:0101/0202/0303\x1b\\\x1b]11;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]12;rgb:0707/0808/0909\x1b\\\x1b]17;rgb:0a0a/0b0b/0c0c\x1b\\" ++
            "\x1b]19;rgb:0d0d/0e0e/0f0f\x1b\\",
        replies,
    );

    try std.testing.expect(source.ackVisual(changed_view.dirty_token));
    try std.testing.expect((try source.feed(
        "\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\\x1b]117\x1b\\\x1b]119\x1b\\",
    )).state_changed);
    const reset = try full(source.visualView(), &storage);
    try std.testing.expectEqual(selection.foreground, reset.cells[0].foreground);
    try std.testing.expectEqual(selection.background, reset.cells[0].background);
    try std.testing.expectEqual(
        terminal.Rgb{ .r = 220, .g = 220, .b = 220 },
        reset.cells[1].foreground,
    );
    try std.testing.expectEqual(
        terminal.Rgb{ .r = 24, .g = 25, .b = 33 },
        reset.cells[1].background,
    );
}

test "one cell and mixed scrollback remain sparse" {
    var source = try vt.Terminal.initWithHistory(std.testing.allocator, 4, 6, 8);
    defer source.deinit();
    try std.testing.expect((try source.feed(
        "\x1b[?25l111111\r\n222222\r\n333333\r\n444444\r\n555555\r\n666666",
    )).state_changed);
    try std.testing.expect(source.scrollViewport(.{ .absolute = 2 }));

    var storage: Storage = .{};
    const initial_view = source.visualView();
    const initial = try full(initial_view, &storage);
    try std.testing.expect(source.ackVisual(initial_view.dirty_token));
    try std.testing.expect(!initial.cursor.visible);
    try std.testing.expectEqual(terminal.CursorShape.none, initial.cursor.shape);
    try std.testing.expectEqual(terminal.Rgb{ .r = 0, .g = 0, .b = 0 }, initial.cursor.color);

    try std.testing.expect((try source.feed("\x1b[1;2HX\x1b[4;5HY")).state_changed);
    const sparse_view = source.visualView();
    const sparse = try terminal.project(
        sparse_view,
        .{ .incremental = initial.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expect(!sparse.full);
    try std.testing.expectEqual(@as(usize, 1), sparse.row_patches.len);
    try std.testing.expectEqual(@as(usize, 1), sparse.cells.len);
    try std.testing.expectEqual(@as(u16, 2), sparse.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 1), sparse.row_patches[0].start_col);
    try std.testing.expectEqual(@as(u21, 'X'), sparse.cells[0].codepoint);
}

test "declined sparse work remains cumulative without projection storage" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b[?25l")).state_changed);
    var storage: Storage = .{};
    const initial_view = source.visualView();
    const initial = try full(initial_view, &storage);
    try std.testing.expect(source.ackVisual(initial_view.dirty_token));

    try std.testing.expect((try source.feed("\x1b[1;2HA")).state_changed);
    const declined = source.visualView();
    try std.testing.expect((try source.feed("\x1b[2;4HB")).state_changed);
    const cumulative = try terminal.project(
        source.visualView(),
        .{ .incremental = initial.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(@as(usize, 2), cumulative.row_patches.len);
    try std.testing.expectEqual(@as(usize, 2), cumulative.cells.len);
    try std.testing.expect(declined.dirty_token != source.visualView().dirty_token);
}

test "row geometry and selection produce exact copied spans" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 8);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b[?25labcdef")).state_changed);
    var storage: Storage = .{};
    const clean_view = source.visualView();
    const clean = try full(clean_view, &storage);
    try std.testing.expect(source.ackVisual(clean_view.dirty_token));

    source.startSelection(0, 1);
    source.updateSelection(0, 3);
    const selected = try terminal.project(
        source.visualView(),
        .{ .incremental = clean.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(@as(usize, 3), selected.cells.len);
    for (selected.cells) |cell| try std.testing.expect(cell.selected);

    const selected_view = source.visualView();
    try std.testing.expect(source.ackVisual(selected_view.dirty_token));
    try std.testing.expect((try source.feed("\x1b[2;1H\x1b#6")).state_changed);
    const geometry = try terminal.project(
        source.visualView(),
        .{ .incremental = selected.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), geometry.row_patches.len);
    try std.testing.expectEqual(@as(u16, 1), geometry.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 8), geometry.row_patches[0].cell_count);
    try std.testing.expectEqual(terminal.LineGeometry.double_width, geometry.row_patches[0].geometry);
}

test "cursor-only projection merges same row and orders different rows" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 8);
    defer source.deinit();
    var storage: Storage = .{};
    const initial_view = source.visualView();
    const initial = try full(initial_view, &storage);
    try std.testing.expect(source.ackVisual(initial_view.dirty_token));

    try std.testing.expect((try source.feed("\x1b[1;5H")).state_changed);
    const same = try terminal.project(
        source.visualView(),
        .{ .incremental = initial.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), same.row_patches.len);
    try std.testing.expectEqual(@as(u16, 0), same.row_patches[0].cell_count);
    try std.testing.expectEqual(@as(u16, 0), same.row_patches[0].damage_start);
    try std.testing.expectEqual(@as(u16, 4), same.row_patches[0].damage_end);

    try std.testing.expect((try source.feed("\x1b[3;2H")).state_changed);
    const different = try terminal.project(
        source.visualView(),
        .{ .incremental = same.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(@as(usize, 2), different.row_patches.len);
    try std.testing.expectEqual(@as(u16, 0), different.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 2), different.row_patches[1].row);
    try std.testing.expectEqual(@as(u16, 0), different.row_patches[0].cell_count);
    try std.testing.expectEqual(@as(u16, 0), different.row_patches[1].cell_count);
}

test "dirty cell beneath an unchanged cursor remains a cell patch" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    var storage: Storage = .{};
    const initial_view = source.visualView();
    const initial = try full(initial_view, &storage);
    try std.testing.expect(source.ackVisual(initial_view.dirty_token));

    try std.testing.expect((try source.feed("\x1b7X\x1b8")).state_changed);
    const update = try terminal.project(
        source.visualView(),
        .{ .incremental = initial.next_baseline },
        storage.buffers(),
        selection,
    );
    try std.testing.expectEqual(initial.cursor, update.cursor);
    try std.testing.expectEqual(@as(usize, 1), update.row_patches.len);
    try std.testing.expectEqual(@as(u16, 1), update.row_patches[0].cell_count);
    try std.testing.expectEqual(@as(u21, 'X'), update.cells[0].codepoint);
}

test "capacity and full-required failures preserve every destination byte" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    var storage: Storage = .{};
    @memset(std.mem.asBytes(&storage), 0xa5);
    var before: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before, std.mem.asBytes(&storage));

    try std.testing.expectError(
        error.InsufficientPatches,
        terminal.project(
            source.visualView(),
            .full,
            .{ .cells = &storage.cells, .rows = storage.rows[0..1] },
            selection,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    try std.testing.expectError(
        error.InsufficientCells,
        terminal.project(
            source.visualView(),
            .full,
            .{ .cells = storage.cells[0..7], .rows = &storage.rows },
            selection,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    const incompatible = terminal.ProjectionBaseline{
        .rows = 1,
        .cols = 4,
        .cursor = undefined,
        .selection_style = selection,
    };
    try std.testing.expectError(
        error.FullRequired,
        terminal.project(source.visualView(), .{ .incremental = incompatible }, storage.buffers(), selection),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));
}

test "incremental projection rejects selection-style discontinuity" {
    var source = try vt.Terminal.init(std.testing.allocator, 1, 2);
    defer source.deinit();
    var storage: Storage = .{};
    const visual = source.visualView();
    const initial = try full(visual, &storage);
    try std.testing.expect(source.ackVisual(visual.dirty_token));
    var before: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before, std.mem.asBytes(&storage));

    const changed = terminal.SelectionStyle{
        .foreground = selection.background,
        .background = selection.foreground,
    };
    try std.testing.expectError(
        error.FullRequired,
        terminal.project(
            source.visualView(),
            .{ .incremental = initial.next_baseline },
            storage.buffers(),
            changed,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));
}
