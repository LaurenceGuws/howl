//! Black-box proofs of the actual optional opaque owner, without Render access.
const std = @import("std");
const output = @import("howl_vt_output");
const text = @import("howl_text");
const a = std.testing.allocator;

fn font(size: u16) !*text.FontSet {
    return text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = size } });
}
fn ready(allocator: std.mem.Allocator, f: *text.FontSet) !*output.Terminal {
    const owner = try output.Terminal.init(allocator, f);
    errdefer destroy(owner);
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    return owner;
}
fn destroy(owner: *output.Terminal) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Every test releases its leases before this deferred teardown.
    owner.deinit() catch unreachable;
}
fn release(owner: *output.Terminal, lease: output.Lease) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: This cleanup receives exactly one live lease from the same owner.
    owner.release(lease) catch unreachable;
}

test "public owner holds exact bytes across unsupported input retry and font replacement" {
    const f = try font(12);
    defer f.deinit();
    const larger = try font(18);
    defer larger.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const held = try owner.hold();
    defer release(owner, held);
    const pixels = try a.dupe(u8, held.snapshot.atlas_pixels);
    defer a.free(pixels);
    const commands = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(commands);
    try std.testing.expect(commands.len > 0 and pixels.len > 0);
    try owner.feed("\x1b[H\x1b]66;s=2;\u{10eeee}\x1b\\");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
    try std.testing.expectEqual(@as(u21, 0x10eeee), owner.observation().semanticView(0).cellAt(0, 0));
    try owner.feed("\x1b[0m\x1b[2J\x1b[HY");
    try owner.flush();
    const accepted = owner.acceptedMetrics().?;
    try owner.replaceWorkingBorrowed(larger, .{});
    try std.testing.expectEqualDeep(accepted, owner.acceptedMetrics().?);
    try owner.flush();
    try std.testing.expect(owner.acceptedMetrics().?.cell_height > accepted.cell_height);
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.atlas_pixels);
    try std.testing.expectEqualDeep(commands, held.snapshot.glyphs[0]);
}

test "public output OOM preserves held output and retries newer canonical input" {
    const f = try font(12);
    defer f.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{});
    const owner = try ready(failing.allocator(), f);
    defer destroy(owner);
    const held = try owner.hold();
    defer release(owner, held);
    const pixels = try a.dupe(u8, held.snapshot.atlas_pixels);
    defer a.free(pixels);
    const commands = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(commands);
    try owner.feed("\x1b[HAA");
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.flush());
    failing.fail_index = std.math.maxInt(usize);
    try owner.feed("\x1b[HR");
    try owner.flush();
    try std.testing.expectEqual(@as(u21, 'R'), owner.observation().semanticView(0).cellAt(0, 0));
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.atlas_pixels);
    try std.testing.expectEqualDeep(commands, held.snapshot.glyphs[0]);
}

test "public leases reject wrong owner duplicate stale and destruction while held" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try std.testing.expectError(error.NotReady, owner.hold());
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    const other = try ready(a, f);
    defer destroy(other);
    const held = try owner.hold();
    try std.testing.expectError(error.LeaseBusy, owner.hold());
    try std.testing.expectError(error.LeaseBusy, owner.deinit());
    try std.testing.expectError(error.InvalidLease, other.release(held));
    try owner.release(held);
    try std.testing.expectError(error.InvalidLease, owner.release(held));
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectError(error.InvalidLease, owner.release(held));
}

test "canonical occurrence rejects old lease when fixed buffer reuses owner address" {
    const f = try font(12);
    defer f.deinit();
    const storage = try a.alloc(u8, 16 * 1024 * 1024);
    defer a.free(storage);
    var fixed = std.heap.FixedBufferAllocator.init(storage);
    const first = try ready(fixed.allocator(), f);
    const old = try first.hold();
    try first.release(old);
    try first.deinit();
    fixed.reset();
    const second = try ready(fixed.allocator(), f);
    defer destroy(second);
    const current = try second.hold();
    defer release(second, current);
    try std.testing.expect(first == second);
    try std.testing.expectEqual(old.serial, current.serial);
    try std.testing.expect(old.occurrence != current.occurrence);
    try std.testing.expectError(error.InvalidLease, second.release(old));
}

const FeedWorker = struct {
    owner: *output.Terminal,
    transfer: *std.Io.Mutex,
    io: std.Io,
    skipped: bool = false,
    // zig-audit: acknowledge anyerror
    // reason: The test transfers the producer's exact feed/flush failure across thread join without erasing it.
    failure: ?anyerror = null,

    fn run(self: *FeedWorker) void {
        self.owner.feed("\x1b[HLATEST") catch |err| {
            self.failure = err;
            return;
        };
        if (!self.transfer.tryLock()) {
            self.skipped = true;
            return;
        }
        defer self.transfer.unlock(self.io);
        self.owner.flush() catch |err| {
            self.failure = err;
        };
    }
};

test "default owner feeds before busy transfer tryLock and later flushes latest input" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var transfer: std.Io.Mutex = .init;
    transfer.lockUncancelable(io);
    var locked = true;
    defer if (locked) transfer.unlock(io);
    const held = try owner.hold();
    var held_live = true;
    defer if (held_live) release(owner, held);
    const pixels = try a.dupe(u8, held.snapshot.atlas_pixels);
    defer a.free(pixels);
    var worker = FeedWorker{ .owner = owner, .transfer = &transfer, .io = io };
    const thread = try std.Thread.spawn(.{}, FeedWorker.run, .{&worker});
    thread.join();
    if (worker.failure) |err| return err;
    try std.testing.expect(worker.skipped);
    // The producer has joined: canonical observation is now serialized again.
    try std.testing.expectEqual(@as(u21, 'L'), owner.observation().semanticView(0).cellAt(0, 0));
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.atlas_pixels);
    try owner.release(held);
    held_live = false;
    transfer.unlock(io);
    locked = false;
    try std.testing.expect(transfer.tryLock());
    defer transfer.unlock(io);
    try owner.flush();
    const latest = try owner.hold();
    defer release(owner, latest);
    try std.testing.expect(latest.snapshot.glyphs[0].len >= 6);
}

fn expectPixelReplies(owner: *output.Terminal, width: u16, height: u16, rows: u16, columns: u16) !void {
    try owner.consumeReplyBytes(owner.replyBytes().len);
    try owner.feed("\x1b[16t\x1b[14t");
    var buffer: [96]u8 = undefined;
    const expected = try std.fmt.bufPrint(&buffer, "\x1b[6;{d};{d}t\x1b[4;{d};{d}t", .{ height, width, @as(u32, rows) * height, @as(u32, columns) * width });
    try std.testing.expectEqualStrings(expected, owner.replyBytes());
    try owner.consumeReplyBytes(owner.replyBytes().len);
}

test "public owner canonical cell pixels follow resolved fonts before output acceptance" {
    const f = try font(12);
    defer f.deinit();
    const regular = try font(18);
    defer regular.deinit();
    const replacement = try font(24);
    defer replacement.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{});
    // Explicit regular face overrides the positional font for canonical metrics.
    const owner = try output.Terminal.initConfig(failing.allocator(), f, .{ .faces = .{ .regular = regular } });
    defer destroy(owner);
    const first = regular.metrics();
    try std.testing.expectEqual(@as(u32, first.advance_width), owner.observation().cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, first.line_height), owner.observation().cellPixelSize().?.height);
    try expectPixelReplies(owner, first.advance_width, first.line_height, 24, 80);
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    const old = owner.acceptedMetrics().?;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.replaceWorkingBorrowed(replacement, .{}));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(u32, first.advance_width), owner.observation().cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, first.line_height), owner.observation().cellPixelSize().?.height);
    try std.testing.expectEqualDeep(old, owner.acceptedMetrics().?);
    try expectPixelReplies(owner, first.advance_width, first.line_height, 24, 80);
    try owner.replaceWorkingBorrowed(replacement, .{});
    const next = replacement.metrics();
    try std.testing.expectEqual(@as(u32, next.advance_width), owner.observation().cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, next.line_height), owner.observation().cellPixelSize().?.height);
    try expectPixelReplies(owner, next.advance_width, next.line_height, 24, 80);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.flush());
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqualDeep(old, owner.acceptedMetrics().?);
    try std.testing.expectEqual(@as(u32, next.line_height), owner.observation().cellPixelSize().?.height);
    try owner.feed("\x1b[HZ");
    try owner.flush();
    try std.testing.expectEqual(next.advance_width, owner.acceptedMetrics().?.cell_width);
    try std.testing.expectEqual(next.line_height, owner.acceptedMetrics().?.cell_height);
    try std.testing.expectEqual(@as(u21, 'Z'), owner.observation().semanticView(0).cellAt(0, 0));
    try owner.resize(12, 40);
    try expectPixelReplies(owner, next.advance_width, next.line_height, 12, 40);
    try owner.feed("\x1b[?1049h");
    try std.testing.expectEqual(@as(u32, next.line_height), owner.observation().cellPixelSize().?.height);
    try expectPixelReplies(owner, next.advance_width, next.line_height, 12, 40);
    try owner.feed("\x1b[?1049l");
    try owner.flush();
    try std.testing.expectEqual(@as(u16, 12), owner.acceptedMetrics().?.rows);
    try std.testing.expectEqual(@as(u16, 40), owner.acceptedMetrics().?.columns);
}

test "public owner presents history beyond the proof bound" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 64 });
    defer destroy(owner);
    try owner.feed("\x1b[?25l");
    for (0..64) |_| try owner.feed("line\r\n");
    owner.selectHistoryOffset(32);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 32), held.snapshot.history_offset);
    try std.testing.expect(held.snapshot.history_count >= 32);
    try std.testing.expect(held.snapshot.cell_width != 0);
}

test "public owner renders beyond the proof geometry and at the product bounds" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l");
    try owner.resize(42, 128);
    try owner.feed("\x1b[42;128HX");
    try owner.flush();
    {
        const held = try owner.hold();
        defer release(owner, held);
        try std.testing.expectEqual(@as(u16, 42), held.snapshot.rows);
        try std.testing.expectEqual(@as(u16, 128), held.snapshot.cols);
        try std.testing.expect(held.snapshot.glyphs[41].len > 0);
    }
    try owner.resize(192, 512);
    try owner.feed("\x1b[192;512HY");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u16, 192), held.snapshot.rows);
    try std.testing.expectEqual(@as(u16, 512), held.snapshot.cols);
    try std.testing.expect(held.snapshot.glyphs[191].len > 0);
    try std.testing.expectError(error.UnsupportedDimensions, owner.resize(193, 512));
    try std.testing.expectError(error.UnsupportedDimensions, owner.resize(192, 513));
}

test "wide contextual row and held output survive resize" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l");
    try owner.resize(42, 128);
    try owner.feed("\x1b[Hheld");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const old = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(old);
    try owner.resize(50, 512);
    try owner.feed("\x1b[H\x1b[?7l");
    try owner.feed(&@as([512]u8, @splat('>')));
    try owner.flush();
    try std.testing.expectEqualDeep(old, held.snapshot.glyphs[0]);
    try std.testing.expectEqual(@as(u16, 512), owner.acceptedMetrics().?.columns);
}

test "pixel geometry overflow rejects resize and font replacement transactionally" {
    const small = try font(12);
    defer small.deinit();
    const large = try font(512);
    defer large.deinit();
    const owner = try output.Terminal.init(a, small);
    defer destroy(owner);
    try owner.feed("\x1b[?25lA");
    try owner.resize(192, 512);
    try owner.flush();
    const accepted = owner.acceptedMetrics().?;
    try std.testing.expectError(error.Overflow, owner.replaceWorkingBorrowed(large, .{}));
    try std.testing.expectEqualDeep(accepted, owner.acceptedMetrics().?);
    try owner.feed("B");
    try owner.flush();
    try owner.resize(24, 80);
    try owner.feed("\x1b[2J");
    try owner.replaceWorkingBorrowed(large, .{});
    try owner.flush();
    const large_accepted = owner.acceptedMetrics().?;
    try std.testing.expectError(error.UnsupportedDimensions, owner.resize(192, 512));
    try std.testing.expectEqualDeep(large_accepted, owner.acceptedMetrics().?);
}

test "block cursor emits recolored ink and held cursor survives movement" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("A\x1b[H");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const cursor = held.snapshot.cursor.?.solid;
    try std.testing.expectEqual(@as(?@import("howl_vt").Terminal.CursorShape, .block), held.snapshot.cursor_shape);
    try std.testing.expect(held.snapshot.cursor_text_color != null);
    const revision = held.snapshot.terminal_revision;
    try std.testing.expect(held.snapshot.cursor_ink.len > 0);
    const saved = try a.dupe(output.commands.Command, held.snapshot.cursor_ink);
    defer a.free(saved);
    const pixels = try a.dupe(u8, held.snapshot.atlas_pixels);
    defer a.free(pixels);
    for (held.snapshot.cursor_ink) |command| {
        const ink = command.alpha_mask;
        try std.testing.expect(!ink.cursor_component);
        try std.testing.expect(ink.clip.x >= cursor.rect.x);
        try std.testing.expect(ink.clip.y >= cursor.rect.y);
        try std.testing.expect(ink.clip.x + ink.clip.width <= cursor.rect.x + cursor.rect.width);
        try std.testing.expect(ink.clip.y + ink.clip.height <= cursor.rect.y + cursor.rect.height);
        try std.testing.expect(ink.color.r != cursor.color.r or ink.color.g != cursor.color.g or ink.color.b != cursor.color.b);
    }
    try owner.feed("\x1b[2;2HΩ");
    try owner.flush();
    try std.testing.expectEqualDeep(saved, held.snapshot.cursor_ink);
    try std.testing.expectEqual(revision, held.snapshot.terminal_revision);
    try std.testing.expect(owner.observation().semanticSequence() > revision);
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.atlas_pixels);
}

test "block cursor allocation failure preserves accepted output and retries" {
    const f = try font(12);
    defer f.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{});
    const owner = try output.Terminal.init(failing.allocator(), f);
    defer destroy(owner);
    try owner.feed("\x1b[?25lA\x1b[H");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.cursor == null);
    try owner.feed("\x1b[?25h");
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.flush());
    try std.testing.expect(held.snapshot.cursor == null);
    failing.fail_index = std.math.maxInt(usize);
    try owner.flush();
    try std.testing.expect(held.snapshot.cursor == null);
}

test "public owner emits generated box and block glyphs" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l┌─┐\r\n│█│\r\n└─┘");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.glyphs[0].len >= 3);
    try std.testing.expect(held.snapshot.glyphs[1].len >= 3);
    try std.testing.expect(held.snapshot.glyphs[2].len >= 3);
}

test "public owner emits all underline styles and dim text" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l\x1b[2;4:2mA\x1b[4:3mB\x1b[4:4mC\x1b[4:5mD");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.decorations[0].len >= 4);
    try std.testing.expect(held.snapshot.glyphs[0].len == 4);
    for (held.snapshot.glyphs[0]) |command| try std.testing.expectEqual(@as(u8, 140), command.alpha_mask.color.a);
}

test "row command limit preserves held output and accepts a simpler later scene" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .command_limit = 8 });
    defer destroy(owner);
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const saved = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(saved);
    try owner.feed("\x1b[H\x1b[4:4mABCDEFGHIJKLMNOP");
    try std.testing.expectError(error.CommandLimit, owner.flush());
    try std.testing.expectEqualDeep(saved, held.snapshot.glyphs[0]);
    try owner.feed("\x1b[0m\x1b[2J\x1b[HZ");
    try owner.flush();
    try std.testing.expectEqualDeep(saved, held.snapshot.glyphs[0]);
}

test "full-width dotted underline stays within the ordinary row command bound" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25l\x1b[?7l\x1b[4:4m");
    try owner.feed(&@as([512]u8, @splat('A')));
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 512), held.snapshot.decorations[0].len);
    try std.testing.expectEqual(@as(usize, 512), held.snapshot.glyphs[0].len);
}

test "accepted content revision follows output not cursor-only changes" {
    const f = try font(12);
    defer f.deinit();
    const larger = try font(18);
    defer larger.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("A\x1b[H");
    try owner.flush();
    const first = try owner.hold();
    const content = first.snapshot.content_revision;
    const semantic = first.snapshot.terminal_revision;
    try owner.release(first);
    try owner.feed("\x1b[2;2H");
    try owner.flush();
    const moved = try owner.hold();
    try std.testing.expectEqual(content, moved.snapshot.content_revision);
    try std.testing.expect(moved.snapshot.terminal_revision > semantic);
    try owner.release(moved);
    try owner.replaceWorkingBorrowed(larger, .{});
    try owner.flush();
    const replaced = try owner.hold();
    defer release(owner, replaced);
    try std.testing.expect(replaced.snapshot.content_revision > content);
}

test "held cursor metadata stays tied to its accepted frame" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?12lA\x1b[H");
    try owner.flush();
    const old = try owner.hold();
    try std.testing.expect(!old.snapshot.cursor_blink);
    const revision = old.snapshot.terminal_revision;
    try owner.feed("\x1b[?12h");
    try owner.flush();
    try std.testing.expect(!old.snapshot.cursor_blink);
    try std.testing.expectEqual(revision, old.snapshot.terminal_revision);
    try owner.release(old);
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expect(next.snapshot.cursor_blink);
    try std.testing.expect(next.snapshot.terminal_revision > revision);
}

test "color glyph uses its own immutable resource including block cursor ink" {
    const f = try text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.feed("M😀\x1b[2G");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const color = held.snapshot.color_resource orelse return error.MissingColorResource;
    try std.testing.expect(!std.meta.eql(color, held.snapshot.resource));
    try std.testing.expectEqual(@as(usize, held.snapshot.color_atlas_width) * held.snapshot.color_atlas_height * 4, held.snapshot.color_atlas_pixels.len);
    var glyph_found = false;
    for (held.snapshot.glyphs[0]) |command| switch (command) {
        .rgba => |image| {
            try std.testing.expectEqualDeep(color, image.resource.resource);
            glyph_found = true;
        },
        else => {},
    };
    try std.testing.expect(glyph_found);
    var cursor_found = false;
    for (held.snapshot.cursor_ink) |command| if (command == .rgba) {
        cursor_found = true;
    };
    try std.testing.expect(cursor_found);
    const pixels = try a.dupe(u8, held.snapshot.color_atlas_pixels);
    defer a.free(pixels);
    try owner.resetAtlas();
    try owner.feed("\x1b[HNew");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.color_atlas_pixels);
}

fn colorAllocationProof(allocator: std.mem.Allocator, f: *text.FontSet) !void {
    const owner = try output.Terminal.initConfig(allocator, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.feed("M😀\x1b[2G");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.color_resource != null);
}

test "color glyph output unwinds all allocator failures" {
    const f = try text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    try std.testing.checkAllAllocationFailures(a, colorAllocationProof, .{f});
}

test "cursor cell geometry is retained independently of its painted shape" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .cursor_stroke_pixels = 5 });
    defer destroy(owner);
    try owner.feed("\x1b[6 q界\x1b[H");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const cell = held.snapshot.cursor_cell.?;
    const painted = held.snapshot.cursor.?.solid.rect;
    try std.testing.expectEqual(held.snapshot.cell_width * 2, cell.width);
    try std.testing.expectEqual(held.snapshot.cell_height, cell.height);
    try std.testing.expectEqual(@min(cell.width, 5), painted.width);
    try owner.feed("\x1b[4 q\x1b[2;2H");
    try owner.flush();
    try std.testing.expectEqualDeep(cell, held.snapshot.cursor_cell.?);
}

test "DEC sized rows and cursor are accepted without changing held output" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.resize(4, 79);
    try owner.feed("\x1b[2J\x1b[H\x1b#6Wide\x1b[2;1H\x1b#3Tall\x1b[3;1H\x1b#4Tall\x1b[1;2H\x1b[?25h");
    try owner.flush();
    const held = try owner.hold();
    const generation = held.snapshot.row_generations[0];
    const cell = held.snapshot.cursor_cell.?;
    try std.testing.expectEqual(held.snapshot.cell_width * 2, cell.width);
    try std.testing.expectEqual(@as(i32, held.snapshot.cell_width) * 2, cell.x);
    try std.testing.expect(held.snapshot.glyphs[0].len > 0);
    const first = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(first);
    try owner.feed("\x1b[H\x1b#5Narrow");
    try owner.flush();
    try std.testing.expectEqualDeep(first, held.snapshot.glyphs[0]);
    try owner.release(held);
    const narrow = try owner.hold();
    defer release(owner, narrow);
    try std.testing.expect(narrow.snapshot.glyphs[0].len > 0);
    try std.testing.expect(narrow.snapshot.row_generations[0] != generation);
}

test "dense decorated row fits ordinary command capacity" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25l\x1b[?7l\x1b[4:2;9m");
    for (0..512) |i| {
        if (i % 2 == 0) try owner.feed("\x1b[41mA") else try owner.feed("\x1b[44mA");
    }
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 512), held.snapshot.glyphs[0].len);
}

test "dense decorated multi-glyph row fits the automatic command bound" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25l\x1b[?7l\x1b[4:2;9m");
    for (0..512) |col| {
        try owner.feed(if (col % 2 == 0) "\x1b[41m" else "\x1b[44m");
        try owner.feed("x\u{0301}\u{0301}\u{0301}\u{0301}");
    }
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const count = held.snapshot.backgrounds[0].len + held.snapshot.decorations[0].len + held.snapshot.glyphs[0].len;
    try std.testing.expect(count > 512 * 5);
}

test "dense output allocation failure preserves the held frame and retries" {
    const f = try font(12);
    defer f.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{});
    const owner = try output.Terminal.init(failing.allocator(), f);
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const before = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(before);
    try owner.feed("\x1b[H\x1b[?7l\x1b[4:2;9m");
    for (0..512) |col| {
        try owner.feed(if (col % 2 == 0) "\x1b[41m" else "\x1b[44m");
        try owner.feed("x\u{0301}\u{0301}\u{0301}\u{0301}");
    }
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.flush());
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqualDeep(before, held.snapshot.glyphs[0]);
    try owner.flush();
    try std.testing.expectEqualDeep(before, held.snapshot.glyphs[0]);
}

test "single-row explicit-width OSC 66 remains drawable with cursor on any cell" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.resize(2, 12);
    try owner.feed("\x1b[?25h\x1b[H\x1b]66;s=1:w=7;X\x07");
    for (0..7) |col| {
        var sequence: [32]u8 = undefined;
        const move = try std.fmt.bufPrint(&sequence, "\x1b[1;{d}H", .{col + 1});
        try owner.feed(move);
        try owner.flush();
        const held = try owner.hold();
        try std.testing.expect(held.snapshot.glyphs[0].len != 0);
        try std.testing.expectEqual(@as(i32, @intCast(col * held.snapshot.cell_width)), held.snapshot.cursor_cell.?.x);
        try owner.release(held);
    }
    try owner.feed("\x1b[1;4HZ");
    try owner.flush();
    try std.testing.expectEqual(@as(u21, ' '), owner.observation().semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), owner.observation().semanticView(0).cellAt(0, 3));
}

test "single-row explicit-width OSC 66 remains drawable in history" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(2, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=1:w=7;X\x07\r\nnext\r\n");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 1), held.snapshot.history_offset);
    try std.testing.expectEqual(@as(u21, 'X'), owner.observation().semanticView(1).cellAt(0, 0));
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
}

test "scaled row strips repair together while a prior frame is held" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[H\x1b]66;s=2;X\x07");
    try owner.flush();
    const old = try owner.hold();
    defer release(owner, old);
    try std.testing.expect(old.snapshot.glyphs[0].len != 0);
    try std.testing.expect(old.snapshot.glyphs[1].len != 0);
    const top = try a.dupe(output.commands.Command, old.snapshot.glyphs[0]);
    defer a.free(top);
    const bottom = try a.dupe(output.commands.Command, old.snapshot.glyphs[1]);
    defer a.free(bottom);
    try owner.feed("\x1b[2;1H\x1b[2KZ");
    try owner.flush();
    try std.testing.expectEqualSlices(output.commands.Command, top, old.snapshot.glyphs[0]);
    try std.testing.expectEqualSlices(output.commands.Command, bottom, old.snapshot.glyphs[1]);
    try std.testing.expectEqual(@as(u21, 0), owner.observation().semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), owner.observation().semanticView(0).cellAt(1, 0));
}

test "fractional single-row text remains drawable in history" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(2, 12);
    try owner.feed("\x1b[?25l\x1b[4:3m\x1b]66;s=1:n=1:d=2:h=2:v=2;e\u{0301}\x07\x1b[0m");
    try owner.flush();
    const live = try owner.hold();
    try std.testing.expect(live.snapshot.glyphs[0].len != 0);
    const live_glyph = live.snapshot.glyphs[0][0].alpha_mask;
    release(owner, live);
    try owner.feed("\r\nnext\r\n");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 1), held.snapshot.history_offset);
    try std.testing.expectEqual(@as(u21, 'e'), owner.observation().semanticView(1).cellAt(0, 0));
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    try std.testing.expect(held.snapshot.decorations[0].len != 0);
    const history_glyph = held.snapshot.glyphs[0][0].alpha_mask;
    try std.testing.expectEqualDeep(live_glyph.destination, history_glyph.destination);
    try std.testing.expectEqualDeep(live_glyph.clip, history_glyph.clip);
    try std.testing.expectEqualDeep(live_glyph.resource.source, history_glyph.resource.source);
    try std.testing.expectEqualDeep(live_glyph.color, history_glyph.color);
}

test "unplaced image does not prevent text output" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=t,f=32,s=1,v=1,i=56,q=2;/wAA/w==\x1b\\after");
    try std.testing.expectEqual(@as(usize, 1), owner.observation().images(0).imageCount());
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b_Ga=p,i=56,p=1,c=1,r=1,C=1,q=2\x1b\\");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
}

test "fractional generated and colour glyphs survive history" {
    const f = try text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8, .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(2, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=1:n=1:d=2;─\x07\x1b[1;5H\x1b]66;s=1:n=1:d=2;😀\x07");
    try owner.flush();
    const live = try owner.hold();
    try std.testing.expectEqual(@as(usize, 2), live.snapshot.glyphs[0].len);
    const alpha = live.snapshot.glyphs[0][0].alpha_mask;
    const rgba = live.snapshot.glyphs[0][1].rgba;
    release(owner, live);
    try owner.feed("\r\nnext\r\n");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 2), held.snapshot.glyphs[0].len);
    const history_alpha = held.snapshot.glyphs[0][0].alpha_mask;
    const history_rgba = held.snapshot.glyphs[0][1].rgba;
    try std.testing.expectEqualDeep(alpha.destination, history_alpha.destination);
    try std.testing.expectEqualDeep(alpha.clip, history_alpha.clip);
    try std.testing.expectEqualDeep(alpha.resource.source, history_alpha.resource.source);
    try std.testing.expectEqualDeep(rgba.destination, history_rgba.destination);
    try std.testing.expectEqualDeep(rgba.clip, history_rgba.clip);
    try std.testing.expectEqualDeep(rgba.resource.source, history_rgba.resource.source);
}

test "primary image does not block a clean alternate screen" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\\x1b[?1049hALT");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.alternate);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b[?1049l");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
}

test "alternate image does not block a clean primary screen" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?47h\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\\x1b[?47lPRIMARY");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(!held.snapshot.alternate);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b[?47h");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
}

test "an inactive placement does not hide an active placement" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\\x1b[?47hALT\x1b_Ga=T,f=32,s=1,v=1,i=57,C=1,q=2;/wAA/w==\x1b\\");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
    try owner.feed("\x1b_Ga=d,d=i,i=57,q=2\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expect(held.snapshot.alternate);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    try owner.feed("\x1b[?47l");
    try std.testing.expectError(error.UnsupportedScene, owner.flush());
}

test "direct output resolves a multi-row lead across the history boundary" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=2;X\x07");
    try owner.flush();
    var held = try owner.hold();
    try std.testing.expect(held.snapshot.glyphs[1].len != 0);
    const lower = held.snapshot.glyphs[1][0].alpha_mask;
    release(owner, held);
    try owner.feed("\x1b[S");
    try owner.flush();
    held = try owner.hold();
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const after = held.snapshot.glyphs[0][0].alpha_mask;
    try std.testing.expectEqualDeep(lower.destination, after.destination);
    try std.testing.expectEqualDeep(lower.clip, after.clip);
    try std.testing.expectEqualDeep(lower.resource.source, after.resource.source);
    try std.testing.expectEqualDeep(lower.color, after.color);
    release(owner, held);
    owner.selectHistoryOffset(1);
    try owner.flush();
    held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 1), held.snapshot.history_offset);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    try std.testing.expect(held.snapshot.glyphs[1].len != 0);
}

test "evicting a multi-row lead retires live fragments without stale output" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 1 });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=3;X\x07\x1b[S");
    try owner.flush();
    const held = try owner.hold();
    try std.testing.expect(held.snapshot.glyphs[1].len != 0);
    const old = held.snapshot.glyphs[1][0];
    try owner.feed("\x1b[S");
    try owner.flush();
    try std.testing.expectEqualDeep(old, held.snapshot.glyphs[1][0]);
    release(owner, held);
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectEqual(@as(usize, 0), next.snapshot.glyphs[0].len);
    try std.testing.expectEqual(@as(u8, 1), owner.observation().semanticView(0).cellInfoAt(0, 0).width);
}

test "maximum-height cluster retires every live fragment when its lead is evicted" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 1 });
    defer destroy(owner);
    try owner.resize(8, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=7;X\x07\x1b[S");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    var glyph_row: ?usize = null;
    for (held.snapshot.glyphs[0..held.snapshot.rows], 0..) |glyphs, row| {
        if (glyphs.len != 0) {
            glyph_row = row;
            break;
        }
    }
    const selected_row = glyph_row orelse return error.MissingGlyph;
    const old = held.snapshot.glyphs[selected_row][0];
    try owner.feed("\x1b[S");
    try owner.flush();
    try std.testing.expectEqualDeep(old, held.snapshot.glyphs[selected_row][0]);
    release(owner, held);
    pinned = false;
    const next = try owner.hold();
    defer release(owner, next);
    for (0..5) |row| {
        try std.testing.expectEqual(@as(usize, 0), next.snapshot.glyphs[row].len);
        try std.testing.expectEqual(@as(u8, 1), owner.observation().semanticView(0).cellInfoAt(@intCast(row), 0).width);
    }
}

test "resizing across a retained multi-row boundary preserves text and held output" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=2;X\x07\x1b[S");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    const old = held.snapshot.glyphs[0][0];
    try owner.resize(4, 14);
    owner.selectHistoryOffset(std.math.maxInt(u32));
    try owner.flush();
    try std.testing.expectEqualDeep(old, held.snapshot.glyphs[0][0]);
    release(owner, held);
    pinned = false;
    const next = try owner.hold();
    defer release(owner, next);
    var glyph_count: usize = 0;
    for (next.snapshot.glyphs[0..next.snapshot.rows]) |row| glyph_count += row.len;
    const view = owner.observation().semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        if (view.cellAt(@intCast(row), @intCast(col)) == 'X') found = true;
    };
    try std.testing.expect(found);
    try std.testing.expect(glyph_count != 0);
}

test "height-only resize preserves text across a retained multi-row boundary" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=2;X\x07\x1b[S");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    const old = held.snapshot.glyphs[0][0];
    try owner.resize(4, 12);
    owner.selectHistoryOffset(std.math.maxInt(u32));
    try owner.flush();
    try std.testing.expectEqualDeep(old, held.snapshot.glyphs[0][0]);
    release(owner, held);
    pinned = false;
    const next = try owner.hold();
    defer release(owner, next);
    var glyph_count: usize = 0;
    for (next.snapshot.glyphs[0..next.snapshot.rows]) |row| glyph_count += row.len;
    const view = owner.observation().semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        if (view.cellAt(@intCast(row), @intCast(col)) == 'X') found = true;
    };
    try std.testing.expect(found);
    try std.testing.expect(glyph_count != 0);
}

test "a history viewport can begin on a retained cluster continuation" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(4, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=3;X\x07\x1b[2S");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 1), held.snapshot.history_offset);
    try std.testing.expectEqual(@as(u8, 1), owner.observation().semanticView(1).cellInfoAt(0, 0).y);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
}

test "history output tolerates a continuation whose lead was evicted" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 1 });
    defer destroy(owner);
    try owner.resize(4, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=3;X\x07\x1b[2S");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(u32, 1), held.snapshot.history_offset);
    for (held.snapshot.glyphs[0..held.snapshot.rows]) |row| try std.testing.expectEqual(@as(usize, 0), row.len);
}

test "multi-row history frontier survives every admitted scale and small capacity" {
    const f = try font(12);
    defer f.deinit();
    for (2..8) |scale| for (1..8) |capacity| {
        const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = @intCast(capacity) });
        defer destroy(owner);
        try owner.resize(8, 16);
        var command: [64]u8 = undefined;
        try owner.feed(try std.fmt.bufPrint(&command, "\x1b[?25l\x1b]66;s={d};X\x07", .{scale}));
        for (0..scale + 1) |step| {
            try owner.feed("\x1b[S");
            try owner.flush();
            const view = owner.observation().semanticView(@intCast(@min(step + 1, capacity)));
            if (step + 1 <= capacity) {
                try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
            } else {
                const live = owner.observation().semanticView(0);
                for (0..live.rows) |row| {
                    const cell = live.cellInfoAt(@intCast(row), 0);
                    try std.testing.expect(@as(u32, cell.y) <= live.history_count + row);
                }
            }
        }
    };
}

test "multi-row history output reads the complete cold scalar tail" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b]66;s=2;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07\x1b[S");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    var scalars: [24]u21 = undefined;
    const view = owner.observation().semanticView(1);
    try std.testing.expectEqualSlices(u21, &.{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 }, view.cellScalarsAt(0, 0, &scalars));
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
}
