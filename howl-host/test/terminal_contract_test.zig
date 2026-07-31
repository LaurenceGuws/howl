//! Proves the copied two-terminal producer boundary before runtime threading.

const std = @import("std");
const vt = @import("howl_vt");
const render = @import("howl_render");
const terminal_handoff = @import("terminal_handoff");
const chrome_state = @import("chrome_state");
const facts = @import("terminal_test_facts");

const terminal = render.terminal;
const terminal_images = render.terminal_images;
const canvas = render.canvas;

const rows: u16 = 2;
const cols: u16 = 8;
const cell_count: usize = rows * cols;
const Producer = struct {
    machine: vt.Terminal,
    content: terminal.Content,
    work: *terminal.Content.Work,
    baseline_cells: [cell_count]terminal.Cell = undefined,
    baseline_scalars: vt.ScalarStorage,
    baseline_geometry: [rows]terminal.LineGeometry = undefined,
    baseline_cursor: terminal.Cursor = undefined,
    work_cells: [cell_count]terminal.Cell = undefined,
    work_scalars: vt.ScalarStorage,
    work_rows: [rows]terminal.RowPatch = undefined,
    image_pixels: [64]u8 = undefined,
    image_uploads: [8]terminal_images.ImageUpload = undefined,
    image_removals: [8]u32 = undefined,
    image_placements: [8]terminal_images.ImagePlacement = undefined,
    image_identities: [8]terminal_images.ImageIdentity = undefined,
    image_identity_count: usize = 0,
    image_generation: u64 = 0,
    initialized: bool = false,

    fn init(
        allocator: std.mem.Allocator,
        fonts: *render.terminal.FontMap,
        work: *terminal.Content.Work,
    ) !Producer {
        var machine = try vt.Terminal.init(allocator, rows, cols);
        errdefer machine.deinit();
        var content = try terminal.Content.init(
            allocator,
            contentLimits(),
            fonts,
        );
        errdefer content.deinit();
        var baseline_scalars = try vt.ScalarStorage.init(allocator, cell_count);
        errdefer baseline_scalars.deinit();
        const work_scalars = try vt.ScalarStorage.init(allocator, cell_count);
        return .{
            .machine = machine,
            .content = content,
            .work = work,
            .baseline_scalars = baseline_scalars,
            .work_scalars = work_scalars,
        };
    }

    fn deinit(self: *Producer) void {
        self.work_scalars.deinit();
        self.baseline_scalars.deinit();
        self.content.deinit();
        self.machine.deinit();
        self.* = undefined;
    }

    fn feed(self: *Producer, bytes: []const u8) !void {
        const summary = try self.machine.feed(bytes);
        try std.testing.expect(summary.state_changed);
    }

    fn recover(self: *Producer) !void {
        const projected = try terminal.project(
            self.machine.semanticView(0),
            self.machine.presentation(),
            .full,
            .{
                .cells = &self.work_cells,
                .scalars = &self.work_scalars,
                .rows = &self.work_rows,
            },
            null,
            selectionStyle(),
        );
        try std.testing.expect(projected.full);
        self.commitProjection(projected);
        const image_update = try self.projectImages();
        try self.content.recover(self.baseline(), image_update);
        self.commitImageIdentities(image_update);
        self.initialized = true;
    }

    fn refresh(self: *Producer) !void {
        try std.testing.expect(self.initialized);
        const projected = try terminal.project(
            self.machine.semanticView(0),
            self.machine.presentation(),
            .{ .incremental = self.baseline() },
            .{
                .cells = &self.work_cells,
                .scalars = &self.work_scalars,
                .rows = &self.work_rows,
            },
            null,
            selectionStyle(),
        );
        try std.testing.expect(!projected.full);
        const current_images = self.machine.images(0);
        const image_update = if (current_images.generation != self.image_generation)
            try self.projectImages()
        else
            null;
        try self.content.apply(projected, image_update);
        self.commitProjection(projected);
        if (image_update) |update| {
            self.commitImageIdentities(update);
        }
    }

    fn publish(
        self: *Producer,
        slot: *terminal_handoff.PendingSlot,
        placement: terminal.Content.Geometry,
    ) !void {
        try slot.publish(
            &self.content,
            self.work,
            terminal.ScalarBaseline.retained(&self.baseline_scalars, cell_count),
            placement,
        );
    }

    fn baseline(self: *const Producer) terminal.ProjectionBaseline {
        return .{
            .rows = rows,
            .cols = cols,
            .cursor = self.baseline_cursor,
            .cells = &self.baseline_cells,
            .scalars = &self.baseline_scalars,
            .geometry = &self.baseline_geometry,
        };
    }

    fn commitProjection(self: *Producer, update: terminal.Update) void {
        for (update.row_patches) |patch| {
            if (patch.cell_count != 0) {
                const destination = @as(usize, patch.row) * cols + patch.start_col;
                @memcpy(
                    self.baseline_cells[destination..][0..patch.cell_count],
                    update.cells[patch.cell_offset..][0..patch.cell_count],
                );
            }
            self.baseline_geometry[patch.row] = patch.geometry;
        }
        self.baseline_cursor = update.cursor;
        std.mem.swap(vt.ScalarStorage, &self.baseline_scalars, &self.work_scalars);
    }

    fn projectImages(self: *Producer) !terminal_images.Update {
        return terminal_images.project(self.machine.images(0), .{
            .retained = self.image_identities[0..self.image_identity_count],
            .pixels = &self.image_pixels,
            .uploads = &self.image_uploads,
            .removals = &self.image_removals,
            .placements = &self.image_placements,
        });
    }

    fn commitImageIdentities(
        self: *Producer,
        update: terminal_images.Update,
    ) void {
        for (update.removals) |removed| {
            var index: usize = 0;
            while (index < self.image_identity_count) : (index += 1) {
                if (self.image_identities[index].id != removed) continue;
                std.mem.copyForwards(
                    terminal_images.ImageIdentity,
                    self.image_identities[index .. self.image_identity_count - 1],
                    self.image_identities[index + 1 .. self.image_identity_count],
                );
                self.image_identity_count -= 1;
                break;
            }
        }
        for (update.uploads) |upload| {
            var found = false;
            for (self.image_identities[0..self.image_identity_count]) |*identity| {
                if (identity.id != upload.identity.id) continue;
                identity.* = upload.identity;
                found = true;
                break;
            }
            if (!found) {
                self.image_identities[self.image_identity_count] = upload.identity;
                self.image_identity_count += 1;
            }
        }
        self.image_generation = update.generation;
    }
};

const FrameStorage = struct {
    uploads: [64]canvas.ResourceUploadFact = undefined,
    removals: [64]canvas.FrameResourceRef = undefined,
    commands: [256]canvas.Command = undefined,
    pixels: [64 * 1024]u8 = undefined,

    fn buffers(self: *FrameStorage) canvas.Composer.FrameBuffers {
        return .{
            .uploads = &self.uploads,
            .removals = &self.removals,
            .commands = &self.commands,
            .pixels = &self.pixels,
        };
    }
};

fn contentLimits() terminal.Content.Limits {
    return .{
        .cells = cell_count,
        .rows = rows,
        .images = 8,
        .placements = 8,
        .image_bytes = 4096,
        .glyphs = 32,
        .masks = 16,
        .commands = 64,
        .resources_per_update = 56,
        .upload_bytes = 8192,
        .raster_bytes = 8192,
        .decoration_bytes = 1024,
    };
}

fn geometry(x: i32) terminal.Content.Geometry {
    return .{
        .x = x,
        .y = 0,
        .clip = .{ .x = x, .y = 0, .width = 64, .height = 32 },
        .metrics = .{ .width_px = 8, .height_px = 16, .baseline_px = 12 },
        .generated_box = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    };
}

fn selectionStyle() terminal.SelectionStyle {
    return .{
        .foreground = .{ .r = 255, .g = 255, .b = 255 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
    };
}

fn commandSource(command: canvas.Command) ?canvas.SourceId {
    return switch (command) {
        .solid => null,
        .alpha_mask => |value| value.resource.resource.source,
        .rgba => |value| value.resource.resource.source,
    };
}

fn expectFrameEqual(
    expected: canvas.Composer.Frame,
    actual: canvas.Composer.Frame,
) !void {
    try std.testing.expectEqual(expected.revision, actual.revision);
    try std.testing.expectEqualSlices(
        canvas.ResourceUploadFact,
        expected.uploads,
        actual.uploads,
    );
    try std.testing.expectEqualSlices(
        canvas.FrameResourceRef,
        expected.removals,
        actual.removals,
    );
    try std.testing.expectEqualSlices(canvas.Command, expected.commands, actual.commands);
    try std.testing.expectEqualSlices(u8, expected.pixels, actual.pixels);
}

fn sourceCommandsEqual(
    left: canvas.Composer.Frame,
    right: canvas.Composer.Frame,
    source: canvas.SourceId,
) bool {
    var left_index: usize = 0;
    var right_index: usize = 0;
    while (true) {
        while (left_index < left.commands.len and
            commandSource(left.commands[left_index]) != source)
            left_index += 1;
        while (right_index < right.commands.len and
            commandSource(right.commands[right_index]) != source)
            right_index += 1;
        if (left_index == left.commands.len or right_index == right.commands.len)
            return left_index == left.commands.len and
                right_index == right.commands.len;
        if (!std.meta.eql(
            left.commands[left_index],
            right.commands[right_index],
        )) return false;
        left_index += 1;
        right_index += 1;
    }
}

fn pendingCopiedBytes(slot: *const terminal_handoff.PendingSlot) usize {
    var pixels: usize = 0;
    for (slot.uploads[0..slot.upload_count]) |upload|
        pixels += upload.pixels.bytes.len;
    return pixels +
        slot.upload_count * @sizeOf(canvas.ResourceUpload) +
        slot.removal_count * @sizeOf(canvas.ResourceRemoval) +
        slot.command_count * @sizeOf(canvas.Input);
}

test "real PendingSlot publication copies coherent terminal updates" {
    var fonts = try render.terminal.FontMap.init(
        std.testing.allocator,
        &.{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = facts.font_path, .size = .{ .pixels = 16 } },
        }},
    );
    defer fonts.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, contentLimits());
    defer work.deinit();
    const transcripts = [_][]const u8{
        "",
        "ordinary text",
        "\x1b_Ga=T,f=32,s=2,v=2,i=7;AQIDBAUGBwgJCgsMDQ4PEA==\x1b\\",
    };
    for (transcripts) |transcript| {
        var producer = try Producer.init(std.testing.allocator, &fonts, &work);
        defer producer.deinit();
        if (transcript.len != 0) try producer.feed(transcript);
        try producer.recover();
        var slot = try terminal_handoff.PendingSlot.init(
            std.testing.allocator,
            contentLimits(),
        );
        defer slot.deinit();
        try producer.publish(&slot, geometry(0));
        const copied = pendingCopiedBytes(&slot);
        try std.testing.expect(copied != 0 or transcript.len == 0);
        try std.testing.expect(try slot.retire());
    }
}

test "production terminal capability generates repeated vertical joins" {
    var fonts = try render.terminal.FontMap.init(
        std.testing.allocator,
        &.{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = facts.font_path, .size = .{ .points = .{
                .points = 12.0,
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            } } },
        }},
    );
    defer fonts.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, contentLimits());
    defer work.deinit();
    var producer = try Producer.init(std.testing.allocator, &fonts, &work);
    defer producer.deinit();
    try producer.feed("\x1b[H\u{2502}\x1b[2;1H\u{2502}");
    try producer.recover();
    var slot = try terminal_handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer {
        const discarded = slot.retire() catch
            @panic("test slot retirement failed");
        std.debug.assert(discarded);
        slot.deinit();
    }
    try producer.publish(&slot, geometry(0));

    var joins: [2]canvas.Input = undefined;
    var join_count: usize = 0;
    for (slot.commands[0..slot.command_count]) |command| switch (command) {
        .alpha_mask => |mask| {
            if (mask.destination.height != 16 or mask.destination.width != 8)
                continue;
            try std.testing.expect(join_count < joins.len);
            joins[join_count] = command;
            join_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(joins.len, join_count);
    const upper = joins[0].alpha_mask;
    const lower = joins[1].alpha_mask;
    try std.testing.expectEqual(upper.resource.resource, lower.resource.resource);
    try std.testing.expectEqual(upper.destination.x, lower.destination.x);
    try std.testing.expectEqual(
        upper.destination.y + @as(i32, @intCast(upper.destination.height)),
        lower.destination.y,
    );

    var upload: ?canvas.ResourceUpload = null;
    for (slot.uploads[0..slot.upload_count]) |candidate| {
        if (!std.meta.eql(candidate.resource, upper.resource.resource)) continue;
        upload = candidate;
        break;
    }
    const joined = upload orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(canvas.ResourceFormat.alpha8, joined.format);
    try std.testing.expectEqual(@as(u16, 16), joined.pixels.height);
    const row_bytes: usize = joined.pixels.width;
    try std.testing.expect(std.mem.indexOfNone(
        u8,
        joined.pixels.bytes[0..row_bytes],
        &.{0},
    ) != null);
    const final_row = (joined.pixels.height - 1) * joined.pixels.stride;
    try std.testing.expect(std.mem.indexOfNone(
        u8,
        joined.pixels.bytes[final_row..][0..row_bytes],
        &.{0},
    ) != null);
}

test "two real terminals cross copied slots into distinct Composer sources" {
    var fonts = try render.terminal.FontMap.init(
        std.testing.allocator,
        &.{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = facts.font_path, .size = .{ .pixels = 16 } },
        }},
    );
    defer fonts.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, contentLimits());
    defer work.deinit();
    var first = try Producer.init(std.testing.allocator, &fonts, &work);
    defer first.deinit();
    var second = try Producer.init(std.testing.allocator, &fonts, &work);
    defer second.deinit();
    try first.feed(
        "\x1b[31mleft A" ++
            "\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\",
    );
    try second.feed(
        "\x1b[34mright B" ++
            "\x1b_Ga=T,f=32,s=1,v=1,i=8;BQYHCA==\x1b\\",
    );
    try first.recover();
    try second.recover();

    var mismatched_limits = contentLimits();
    mismatched_limits.commands -= 1;
    var mismatched_slot = try terminal_handoff.PendingSlot.init(
        std.testing.allocator,
        mismatched_limits,
    );
    defer mismatched_slot.deinit();
    try std.testing.expectError(
        error.InvalidContentLimits,
        first.publish(&mismatched_slot, geometry(0)),
    );
    try std.testing.expect(!(try mismatched_slot.retire()));

    var first_slot = try terminal_handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer first_slot.deinit();
    var second_slot = try terminal_handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer second_slot.deinit();
    var invalid_geometry = geometry(0);
    invalid_geometry.metrics.width_px = 0;
    try std.testing.expectError(
        error.InvalidGeometry,
        first.publish(&first_slot, invalid_geometry),
    );
    try first.publish(&first_slot, geometry(0));
    try second.publish(&second_slot, geometry(0));

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 3,
        .retained_resources = 64,
        .retained_commands = 256,
        .retained_pixel_bytes = 64 * 1024,
        .composition_sources = 2,
        .candidate_resources = 32,
        .candidate_commands = 64,
        .candidate_pixel_bytes = 8192,
    });
    defer composer.deinit();
    const first_source = try composer.registerSource();
    const second_source = try composer.registerSource();

    // The second pane remains pending while the first pane continues to
    // progress and publish a newer complete state. Its VT may advance, but its
    // Content is not drained again until the pending slot becomes free.
    try second.feed(
        "\rqueued" ++
            "\x1b_Ga=t,f=32,s=1,v=1,i=8;CQoLDA==\x1b\\",
    );
    try second.refresh();
    try std.testing.expectError(
        error.Pending,
        second.publish(&second_slot, geometry(0)),
    );
    try std.testing.expect(try first_slot.drain(&composer, first_source));
    try first.feed("\rnew");
    try first.refresh();
    try first.publish(&first_slot, geometry(0));
    try std.testing.expectError(
        error.Pending,
        second.publish(&second_slot, geometry(0)),
    );
    try std.testing.expect(try first_slot.drain(&composer, first_source));
    try std.testing.expect(try second_slot.drain(&composer, second_source));
    try second.publish(&second_slot, geometry(0));
    try std.testing.expect(try second_slot.drain(&composer, second_source));

    try composer.setComposition(.{
        .surface = .{ .width = 128, .height = 32 },
        .sources = &.{
            .{
                .source = first_source,
                .origin = .{ .x = 0, .y = 0 },
                .clip = .{ .x = 0, .y = 0, .width = 64, .height = 32 },
            },
            .{
                .source = second_source,
                .origin = .{ .x = 64, .y = 0 },
                .clip = .{ .x = 64, .y = 0, .width = 64, .height = 32 },
            },
        },
    });
    var complete_storage: FrameStorage = .{};
    const complete = try composer.frame(&.{}, complete_storage.buffers());
    var first_text_seen = false;
    var second_text_seen = false;
    for (complete.commands) |command| {
        const source = commandSource(command) orelse continue;
        if (source == first_source) {
            try std.testing.expect(!second_text_seen);
            first_text_seen = true;
        } else if (source == second_source) {
            second_text_seen = true;
        }
    }
    try std.testing.expect(first_text_seen and second_text_seen);

    var collision = false;
    for (complete.uploads) |left| for (complete.uploads) |right| {
        if (left.resource.source == right.resource.source) continue;
        if (left.resource.resource == right.resource.resource) {
            collision = true;
            break;
        }
    };
    try std.testing.expect(collision);

    // Empty backend residency is a complete deterministic recovery.
    var recovery_storage: FrameStorage = .{};
    const recovered = try composer.frame(&.{}, recovery_storage.buffers());
    try expectFrameEqual(complete, recovered);

    // Hide the second source, accept its newest terminal state, and prove the
    // derived visible frame remains byte-exact until reveal.
    try composer.setComposition(.{
        .surface = .{ .width = 128, .height = 32 },
        .sources = &.{.{
            .source = first_source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = 64, .height = 32 },
        }},
    });
    var hidden_before_storage: FrameStorage = .{};
    const hidden_before = try composer.frame(&.{}, hidden_before_storage.buffers());
    try second.feed("\rnewest");
    try second.refresh();
    try second.publish(&second_slot, geometry(0));
    try std.testing.expect(try second_slot.drain(&composer, second_source));
    var hidden_after_storage: FrameStorage = .{};
    const hidden_after = try composer.frame(&.{}, hidden_after_storage.buffers());
    try expectFrameEqual(hidden_before, hidden_after);

    try composer.setComposition(.{
        .surface = .{ .width = 128, .height = 32 },
        .sources = &.{
            .{
                .source = first_source,
                .origin = .{ .x = 0, .y = 0 },
                .clip = .{ .x = 0, .y = 0, .width = 64, .height = 32 },
            },
            .{
                .source = second_source,
                .origin = .{ .x = 64, .y = 0 },
                .clip = .{ .x = 64, .y = 0, .width = 64, .height = 32 },
            },
        },
    });
    var revealed_storage: FrameStorage = .{};
    const revealed = try composer.frame(&.{}, revealed_storage.buffers());
    try std.testing.expectEqual(
        @as(u64, @backingInt(hidden_after.revision)) + 1,
        @backingInt(revealed.revision),
    );
    var newest_second_seen = false;
    for (revealed.commands) |command| {
        if (commandSource(command) == second_source) newest_second_seen = true;
    }
    try std.testing.expect(newest_second_seen);
    try std.testing.expect(
        !sourceCommandsEqual(complete, revealed, second_source),
    );

    // Closing a pane discards its immutable pending update before retiring the
    // Composer source; the slot can neither drain nor publish afterward.
    try second.feed("\rretiring");
    try second.refresh();
    try second.publish(&second_slot, geometry(0));
    try std.testing.expect(try second_slot.retire());
    try composer.removeSource(second_source);
    try std.testing.expect(!(try second_slot.drain(
        &composer,
        second_source,
    )));
    try std.testing.expectError(
        error.Retired,
        second.publish(&second_slot, geometry(0)),
    );
    try std.testing.expectError(
        error.RetiredSource,
        composer.apply(second_source, .{
            .revision = @fromBackingInt(@intCast(999)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{},
        }),
    );
    const later_source = try composer.registerSource();
    try std.testing.expect(
        @backingInt(later_source) > @backingInt(second_source),
    );

    var topology = try chrome_state.Topology.init(
        .{ .width = 128, .height = 64 },
        chrome_state.default_tab_bar_height,
    );
    const root = topology.focusedPaneId();
    const retired_pane = try topology.split(root, .vertical);
    try topology.closePane(retired_pane);
    const later_pane = try topology.split(root, .vertical);
    try std.testing.expect(
        @backingInt(later_pane) > @backingInt(retired_pane),
    );
}
