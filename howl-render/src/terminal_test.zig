//! Proves frozen-VT terminal projection through direct semantic observations.

const std = @import("std");
const vt = @import("howl_vt");
const terminal = @import("howl_render").terminal;

comptime {
    std.testing.refAllDecls(@import("image_projection_test.zig"));
}

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

fn full(source: *const vt.Terminal, storage: *Storage, range: ?terminal.SelectionRange) !terminal.Update {
    return terminal.project(
        source.semanticView(0),
        source.presentation(),
        .full,
        storage.buffers(),
        range,
        selection,
    );
}

fn baseline(frame: []const terminal.Cell, geometry: []const terminal.LineGeometry, update: terminal.Update) terminal.ProjectionBaseline {
    return .{
        .rows = update.rows,
        .cols = update.cols,
        .cursor = update.cursor,
        .cells = frame,
        .geometry = geometry,
    };
}

fn applyUpdate(frame: []terminal.Cell, geometry: []terminal.LineGeometry, update: terminal.Update) void {
    for (update.row_patches) |patch| {
        geometry[patch.row] = patch.geometry;
        if (patch.cell_count == 0) continue;
        const destination = frame[@as(usize, patch.row) * update.cols + patch.start_col ..][0..patch.cell_count];
        @memcpy(destination, update.cells[patch.cell_offset..][0..patch.cell_count]);
    }
}

test "full projection resolves presentation, caller selection, geometry, and cursor" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed(
        "\x1b[38;2;1;2;3;48;2;4;5;6;58;2;7;8;9;3;4mA\r\nB\x1b#6",
    )).state_changed);

    var storage: Storage = .{};
    const update = try full(&source, &storage, .{
        .start = .{ .row = 0, .col = 0 },
        .end = .{ .row = 0, .col = 0 },
    });
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
    for (update.row_patches) |patch| {
        try std.testing.expect(patch.damage_start <= patch.damage_end);
        try std.testing.expect(patch.damage_end < update.cols);
    }
}

test "projection resolves indexed, RGB, dynamic-default, and reverse colors" {
    var source = try vt.Terminal.init(std.testing.allocator, 1, 6);
    defer source.deinit();
    try std.testing.expect((try source.feed(
        "\x1b]4;1;#010203\x1b\\" ++
            "\x1b]10;#aabbcc\x1b\\" ++
            "\x1b]11;#0d0e0f\x1b\\" ++
            "\x1b[38;5;1;48;2;4;5;6mA\x1b[39mB\x1b[7mC",
    )).state_changed);
    var storage: Storage = .{};
    const update = try full(&source, &storage, null);
    try std.testing.expectEqual(terminal.Rgb{ .r = 1, .g = 2, .b = 3 }, update.cells[0].foreground);
    try std.testing.expectEqual(terminal.Rgb{ .r = 4, .g = 5, .b = 6 }, update.cells[0].background);
    try std.testing.expectEqual(terminal.Rgb{ .r = 170, .g = 187, .b = 204 }, update.cells[1].foreground);
    try std.testing.expectEqual(terminal.Rgb{ .r = 4, .g = 5, .b = 6 }, update.cells[1].background);
    try std.testing.expectEqual(terminal.Rgb{ .r = 4, .g = 5, .b = 6 }, update.cells[2].foreground);
    try std.testing.expectEqual(terminal.Rgb{ .r = 170, .g = 187, .b = 204 }, update.cells[2].background);
}

test "projection derives sparse cell and cursor differences from retained facts" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 8);
    defer source.deinit();
    try std.testing.expect((try source.feed("abcdef")).state_changed);

    var storage: Storage = .{};
    var frame: [24]terminal.Cell = undefined;
    var frame_geometry: [3]terminal.LineGeometry = undefined;
    const initial = try full(&source, &storage, null);
    @memcpy(frame[0..initial.cells.len], initial.cells);
    for (initial.row_patches) |patch| frame_geometry[patch.row] = patch.geometry;

    const unchanged = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &frame_geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 0), unchanged.row_patches.len);

    try std.testing.expect((try source.feed("\x1b[1;2HX")).state_changed);
    const sparse = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &frame_geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expect(!sparse.full);
    try std.testing.expectEqual(@as(usize, 1), sparse.row_patches.len);
    try std.testing.expectEqual(@as(usize, 1), sparse.cells.len);
    try std.testing.expectEqual(@as(u16, 0), sparse.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 1), sparse.row_patches[0].start_col);
    try std.testing.expectEqual(@as(u21, 'X'), sparse.cells[0].codepoint);
    applyUpdate(&frame, &frame_geometry, sparse);

    try std.testing.expect((try source.feed("\x1b[3;2H")).state_changed);
    const cursor = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &frame_geometry, sparse) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 2), cursor.row_patches.len);
    try std.testing.expectEqual(@as(u16, 0), cursor.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 2), cursor.row_patches[1].row);
    try std.testing.expectEqual(@as(u16, 0), cursor.row_patches[0].cell_count);
    try std.testing.expectEqual(@as(u16, 0), cursor.row_patches[1].cell_count);
    try std.testing.expectEqual(@as(u16, 2), cursor.row_patches[0].damage_start);
    try std.testing.expectEqual(@as(u16, 2), cursor.row_patches[0].damage_end);
    try std.testing.expectEqual(@as(u16, 1), cursor.row_patches[1].damage_start);
    try std.testing.expectEqual(@as(u16, 1), cursor.row_patches[1].damage_end);
}

test "cursor damage is exact for same-row movement and visibility changes" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 8);
    defer source.deinit();
    try std.testing.expect((try source.feed("abc")).state_changed);
    var storage: Storage = .{};
    var frame: [24]terminal.Cell = undefined;
    var geometry: [3]terminal.LineGeometry = undefined;
    const initial = try full(&source, &storage, null);
    @memcpy(frame[0..initial.cells.len], initial.cells);
    for (initial.row_patches) |patch| geometry[patch.row] = patch.geometry;

    try std.testing.expect((try source.feed("\x1b[1;6H")).state_changed);
    const moved = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), moved.row_patches.len);
    try std.testing.expectEqual(@as(u16, 3), moved.row_patches[0].damage_start);
    try std.testing.expectEqual(@as(u16, 5), moved.row_patches[0].damage_end);
    applyUpdate(&frame, &geometry, moved);

    try std.testing.expect((try source.feed("\x1b[?25l")).state_changed);
    const hidden = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, moved) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), hidden.row_patches.len);
    try std.testing.expectEqual(@as(u16, 5), hidden.row_patches[0].damage_start);
    try std.testing.expectEqual(@as(u16, 5), hidden.row_patches[0].damage_end);
}

test "selection is caller-owned and changes are sparse" {
    var source = try vt.Terminal.init(std.testing.allocator, 1, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("abcd")).state_changed);
    var storage: Storage = .{};
    const unselected = try full(&source, &storage, null);
    var frame: [4]terminal.Cell = undefined;
    @memcpy(&frame, unselected.cells);
    var geometry: [1]terminal.LineGeometry = undefined;
    for (unselected.row_patches) |patch| geometry[patch.row] = patch.geometry;
    const selected = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, unselected) },
        storage.buffers(),
        .{ .start = .{ .row = 0, .col = 1 }, .end = .{ .row = 0, .col = 2 } },
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), selected.row_patches.len);
    try std.testing.expectEqual(@as(usize, 2), selected.cells.len);
    try std.testing.expect(selected.cells[0].selected and selected.cells[1].selected);
}

test "selection normalizes, clips, clears, and expands top-clipped OSC 66 continuations" {
    var source = try vt.Terminal.init(std.testing.allocator, 3, 6);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b]66;s=2:w=2:n=1:d=2:v=2:h=1;Hi\x1b\\")).state_changed);
    var storage: Storage = .{};
    const clipped = try full(&source, &storage, .{
        .start = .{ .row = 9, .col = 99 },
        .end = .{ .row = -2, .col = 0 },
    });
    var selected_count: usize = 0;
    for (clipped.cells) |cell| selected_count += @intFromBool(cell.selected);
    try std.testing.expectEqual(@as(usize, 18), selected_count);
    const cluster = try full(&source, &storage, .{
        .start = .{ .row = -1, .col = 0 },
        .end = .{ .row = 0, .col = 0 },
    });
    selected_count = 0;
    for (cluster.cells) |cell| selected_count += @intFromBool(cell.selected);
    try std.testing.expectEqual(@as(usize, 8), selected_count);
    try std.testing.expectEqual(@as(u8, 4), cluster.cells[0].sizing.width);
    try std.testing.expectEqual(@as(u8, 2), cluster.cells[0].sizing.height);
    const continuation = try full(&source, &storage, .{
        .start = .{ .row = 1, .col = 0 },
        .end = .{ .row = 1, .col = 0 },
    });
    try std.testing.expectEqual(@as(u8, 1), source.semanticView(0).rowCells(1)[0].y);
    selected_count = 0;
    for (continuation.cells) |cell| selected_count += @intFromBool(cell.selected);
    try std.testing.expectEqual(@as(usize, 8), selected_count);

    var frame: [18]terminal.Cell = undefined;
    var geometry: [3]terminal.LineGeometry = undefined;
    @memcpy(frame[0..cluster.cells.len], cluster.cells);
    for (cluster.row_patches) |patch| geometry[patch.row] = patch.geometry;
    const cleared = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, cluster) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expect(cleared.row_patches.len > 0);
    for (cleared.cells) |cell| try std.testing.expect(!cell.selected);

    const changed_style = terminal.SelectionStyle{
        .foreground = .{ .r = 1, .g = 2, .b = 3 },
        .background = .{ .r = 4, .g = 5, .b = 6 },
    };
    const restyled = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, cluster) },
        storage.buffers(),
        .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 0, .col = 0 } },
        changed_style,
    );
    try std.testing.expect(restyled.cells.len > 0);
    try std.testing.expectEqual(changed_style.foreground, restyled.cells[0].foreground);
}

test "projection capacity failures preserve caller destinations" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    var storage: Storage = .{};
    @memset(std.mem.asBytes(&storage), 0xa5);
    var before: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before, std.mem.asBytes(&storage));

    try std.testing.expectError(
        error.InsufficientPatches,
        terminal.project(source.semanticView(0), source.presentation(), .full, .{
            .cells = &storage.cells,
            .rows = storage.rows[0..1],
        }, null, selection),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    try std.testing.expectError(
        error.InsufficientCells,
        terminal.project(source.semanticView(0), source.presentation(), .full, .{
            .cells = storage.cells[0..7],
            .rows = &storage.rows,
        }, null, selection),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    const valid = try full(&source, &storage, null);
    var valid_geometry = [_]terminal.LineGeometry{ .single_width, .single_width };
    for (valid.row_patches) |patch| valid_geometry[patch.row] = patch.geometry;
    var wrong_shape = baseline(&storage.cells, &valid_geometry, valid);
    wrong_shape.rows = 1;
    var before_wrong_shape: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before_wrong_shape, std.mem.asBytes(&storage));
    try std.testing.expectError(
        error.FullRequired,
        terminal.project(source.semanticView(0), source.presentation(), .{ .incremental = wrong_shape }, storage.buffers(), null, selection),
    );
    try std.testing.expectEqualSlices(u8, &before_wrong_shape, std.mem.asBytes(&storage));

    var malformed_frame: [8]terminal.Cell = undefined;
    @memcpy(malformed_frame[0..valid.cells.len], valid.cells);
    var malformed = baseline(&malformed_frame, &valid_geometry, valid);
    malformed.cursor = .{
        .row = valid.rows,
        .col = 0,
        .visible = true,
        .shape = .block,
        .blink = false,
        .color = .{ .r = 1, .g = 2, .b = 3 },
        .text_color = .{ .r = 4, .g = 5, .b = 6 },
    };
    var before_malformed: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before_malformed, std.mem.asBytes(&storage));
    try std.testing.expectError(
        error.InvalidBaseline,
        terminal.project(source.semanticView(0), source.presentation(), .{ .incremental = malformed }, storage.buffers(), null, selection),
    );
    try std.testing.expectEqualSlices(u8, &before_malformed, std.mem.asBytes(&storage));

    malformed.cursor = .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = true,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
    @memcpy(&before_malformed, std.mem.asBytes(&storage));
    try std.testing.expectError(
        error.InvalidBaseline,
        terminal.project(source.semanticView(0), source.presentation(), .{ .incremental = malformed }, storage.buffers(), null, selection),
    );
    try std.testing.expectEqualSlices(u8, &before_malformed, std.mem.asBytes(&storage));
}

test "geometry-only changes damage a full row without recopying cells" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b[?25labcd")).state_changed);
    var storage: Storage = .{};
    var frame: [8]terminal.Cell = undefined;
    var geometry: [2]terminal.LineGeometry = undefined;
    const initial = try full(&source, &storage, null);
    @memcpy(frame[0..initial.cells.len], initial.cells);
    for (initial.row_patches) |patch| geometry[patch.row] = patch.geometry;
    try std.testing.expect((try source.feed("\x1b[2;1H\x1b#6")).state_changed);
    const update = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), update.row_patches.len);
    try std.testing.expectEqual(@as(u16, 1), update.row_patches[0].row);
    try std.testing.expectEqual(@as(u16, 0), update.row_patches[0].cell_count);
    try std.testing.expectEqual(terminal.LineGeometry.double_width, update.row_patches[0].geometry);
    try std.testing.expectEqual(@as(u16, 0), update.row_patches[0].damage_start);
    try std.testing.expectEqual(@as(u16, 3), update.row_patches[0].damage_end);
}

test "multiple skipped semantic mutations compare cumulatively against one baseline" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    var storage: Storage = .{};
    var frame: [8]terminal.Cell = undefined;
    var geometry: [2]terminal.LineGeometry = undefined;
    const initial = try full(&source, &storage, null);
    @memcpy(frame[0..initial.cells.len], initial.cells);
    for (initial.row_patches) |patch| geometry[patch.row] = patch.geometry;
    try std.testing.expect((try source.feed("\x1b[1;1HA\x1b[2;2HB")).state_changed);
    const update = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 2), update.row_patches.len);
    try std.testing.expectEqual(@as(usize, 2), update.cells.len);
}

test "changed cell beneath an unchanged cursor remains a cell patch" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    var storage: Storage = .{};
    var frame: [8]terminal.Cell = undefined;
    var geometry: [2]terminal.LineGeometry = undefined;
    const initial = try full(&source, &storage, null);
    @memcpy(frame[0..initial.cells.len], initial.cells);
    for (initial.row_patches) |patch| geometry[patch.row] = patch.geometry;
    try std.testing.expect((try source.feed("\x1b7X\x1b8")).state_changed);
    const update = try terminal.project(
        source.semanticView(0),
        source.presentation(),
        .{ .incremental = baseline(&frame, &geometry, initial) },
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(usize, 1), update.row_patches.len);
    try std.testing.expectEqual(@as(usize, 1), update.cells.len);
    try std.testing.expectEqual(@as(u21, 'X'), update.cells[0].codepoint);
    try std.testing.expectEqual(initial.cursor, update.cursor);
}

test "history offset projects the caller-selected semantic rows" {
    var source = try vt.Terminal.initWithHistory(std.testing.allocator, 2, 4, 8);
    defer source.deinit();
    try std.testing.expect((try source.feed("1111\r\n2222\r\n3333")).state_changed);
    var storage: Storage = .{};
    const update = try terminal.project(
        source.semanticView(1),
        source.presentation(),
        .full,
        storage.buffers(),
        null,
        selection,
    );
    try std.testing.expectEqual(@as(u16, 2), update.rows);
    try std.testing.expectEqual(@as(u21, '1'), update.cells[0].codepoint);
}

test "projection rejects output and baseline aliasing before comparison" {
    var source = try vt.Terminal.init(std.testing.allocator, 1, 2);
    defer source.deinit();

    var overlapping: [@sizeOf(terminal.Cell) * 2 + @sizeOf(terminal.RowPatch)]u8 align(@alignOf(terminal.RowPatch)) = undefined;
    @memset(&overlapping, 0xa7);
    const overlapping_before = overlapping;
    const overlapping_cells = @as([*]terminal.Cell, @ptrCast(&overlapping))[0..2];
    const overlapping_rows = @as([*]terminal.RowPatch, @ptrCast(&overlapping))[0..1];
    try std.testing.expectError(
        error.AliasedStorage,
        terminal.project(source.semanticView(0), source.presentation(), .full, .{
            .cells = overlapping_cells,
            .rows = overlapping_rows,
        }, null, selection),
    );
    try std.testing.expectEqualSlices(u8, &overlapping_before, &overlapping);

    var storage: Storage = .{};
    var geometry = [_]terminal.LineGeometry{.single_width};
    const full_update = try full(&source, &storage, null);
    const before = storage;
    try std.testing.expectError(
        error.AliasedStorage,
        terminal.project(
            source.semanticView(0),
            source.presentation(),
            .{ .incremental = baseline(&storage.cells, &geometry, full_update) },
            storage.buffers(),
            null,
            selection,
        ),
    );
    try std.testing.expectEqualDeep(before, storage);
}
