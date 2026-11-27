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

test "public owner holds exact bytes across placeholder input and font replacement" {
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
    // The reserved placeholder is not rasterized as a text glyph.
    try owner.flush();
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

test "accepted output cut freezes transparent color opacity across canonical mutations" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b]21;transparent_background_color2=#112233@0.5\x1b\\");
    try owner.flush();

    const old = try owner.hold();
    var old_held = true;
    defer if (old_held) release(owner, old);
    const held = old.snapshot.transparent_background[1].?;
    try std.testing.expectEqualDeep(
        @import("howl_vt").Terminal.Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 },
        held.rgb,
    );
    try std.testing.expectEqual(@as(?f32, 0.5), held.opacity);
    const revision = old.snapshot.content_revision;

    // The host can retain this frame while VT continues receiving controls.
    // The old cut must not read the live canonical color owner.
    try owner.feed("\x1b]21;transparent_background_color2=#aabbcc@0.2\x1b\\");
    try std.testing.expectEqualDeep(held, old.snapshot.transparent_background[1].?);
    try owner.flush();
    try std.testing.expectEqualDeep(held, old.snapshot.transparent_background[1].?);

    // The newer accepted frame cannot be leased while the old one is pinned.
    try std.testing.expectError(error.LeaseBusy, owner.hold());
    try std.testing.expect(owner.observation().presentation().transparent_background[1] != null);
    try std.testing.expectEqual(revision, old.snapshot.content_revision);

    release(owner, old);
    old_held = false;
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expect(next.snapshot.content_revision > revision);
    try std.testing.expectEqualDeep(
        @import("howl_vt").Terminal.Rgb{ .r = 0xaa, .g = 0xbb, .b = 0xcc },
        next.snapshot.transparent_background[1].?.rgb,
    );
    try std.testing.expectEqual(@as(?f32, 0.2), next.snapshot.transparent_background[1].?.opacity);
}

test "native output retains SGR blink glyph tags and phase without reprojecting text" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l\x1b[5mA\x1b[25mB");
    try owner.flush();
    const old = try owner.hold();
    var held = true;
    defer if (held) release(owner, old);
    try std.testing.expect(old.snapshot.text_blink_rows[0]);
    try std.testing.expect(old.snapshot.text_blink_visible);
    var blinking: usize = 0;
    var steady: usize = 0;
    for (old.snapshot.glyphs[0]) |command| {
        if (output.commands.blinks(command)) blinking += 1 else steady += 1;
    }
    try std.testing.expect(blinking > 0 and steady > 0);
    const sequence = owner.observation().semanticSequence();
    const revision = old.snapshot.content_revision;
    const generation = old.snapshot.resource;
    const glyphs = try a.dupe(output.commands.Command, old.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try std.testing.expect(!owner.serviceAnimations(100 * std.time.ns_per_ms).changed);
    const advanced = owner.serviceAnimations(600 * std.time.ns_per_ms);
    try std.testing.expect(advanced.changed);
    try std.testing.expectEqual(@as(?u32, 500), advanced.next_ms);
    try std.testing.expectEqual(sequence, owner.observation().semanticSequence());
    try owner.flush();
    // The reader's prior lease is not mutated by another phase service.
    try std.testing.expect(old.snapshot.text_blink_visible);
    try std.testing.expectEqualDeep(glyphs, old.snapshot.glyphs[0]);
    release(owner, old);
    held = false;
    const current = try owner.hold();
    defer release(owner, current);
    try std.testing.expect(!current.snapshot.text_blink_visible);
    try std.testing.expect(current.snapshot.text_blink_rows[0]);
    try std.testing.expectEqual(revision, current.snapshot.content_revision);
    try std.testing.expectEqualDeep(generation, current.snapshot.resource);
    try std.testing.expectEqualDeep(glyphs, current.snapshot.glyphs[0]);
}

test "native image output resolves physical P Q ancestry without mutating held cuts" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l\x1b[3;4H" ++
        "\x1b_Ga=T,f=32,s=1,v=1,i=91,p=3,C=1,q=2;/wAA/w==\x1b\\" ++
        "\x1b_Ga=t,f=32,s=1,v=1,i=92,q=2;AP8A/w==\x1b\\");
    const before_cursor = owner.observation().semanticView(0);
    const row = before_cursor.cursor_row;
    const col = before_cursor.cursor_col;
    try owner.feed("\x1b_Ga=p,i=92,p=4,P=91,Q=3,H=2,V=1,z=1,q=2\x1b\\");
    const after_cursor = owner.observation().semanticView(0);
    try std.testing.expectEqual(row, after_cursor.cursor_row);
    try std.testing.expectEqual(col, after_cursor.cursor_col);
    try owner.flush();
    const first = try owner.hold();
    var held = true;
    defer if (held) release(owner, first);
    try std.testing.expectEqual(@as(usize, 2), first.snapshot.graphics.positive.len);
    const cell_width: i32 = first.snapshot.cell_width;
    const cell_height: i32 = first.snapshot.cell_height;
    const child = first.snapshot.graphics.positive[1].rgba.destination;
    try std.testing.expectEqual(@as(i32, 5) * cell_width, child.x);
    try std.testing.expectEqual(@as(i32, 3) * cell_height, child.y);
    const previous = child;
    const image_bytes = try a.dupe(u8, first.snapshot.graphics.images[1].pixels);
    defer a.free(image_bytes);

    // Re-put a physical root with the same placement ID. Its stable ref
    // identity moves the child, without retransmitting the child's image.
    try owner.feed("\x1b[6;2H\x1b_Ga=p,i=91,p=3,C=1,q=2\x1b\\");
    try owner.flush();
    try std.testing.expectEqualDeep(previous, first.snapshot.graphics.positive[1].rgba.destination);
    try std.testing.expectEqualSlices(u8, image_bytes, first.snapshot.graphics.images[1].pixels);
    release(owner, first);
    held = false;
    const moved = try owner.hold();
    try std.testing.expectEqual(@as(usize, 2), moved.snapshot.graphics.positive.len);
    const moved_child = moved.snapshot.graphics.positive[1].rgba.destination;
    try std.testing.expectEqual(@as(i32, 3) * cell_width, moved_child.x);
    try std.testing.expectEqual(@as(i32, 6) * cell_height, moved_child.y);
    release(owner, moved);

    // Exact signed left clipping is not expressible by a u16 cell-column.
    try owner.feed("\x1b_Ga=p,i=92,p=4,P=91,Q=3,H=-2,V=0,c=3,z=1,q=2\x1b\\");
    try owner.flush();
    const clipped = try owner.hold();
    try std.testing.expectEqual(@as(usize, 2), clipped.snapshot.graphics.positive.len);
    const negative = clipped.snapshot.graphics.positive[1].rgba.destination;
    try std.testing.expectEqual(-cell_width, negative.x);
    try std.testing.expectEqual(@as(i32, 5) * cell_height, negative.y);
    // Parent deletion retires the child resource, not a pinned cut.
    try owner.feed("\x1b_Ga=d,d=i,i=91,p=3\x1b\\");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 1), owner.observation().images(0).imageCount());
    try std.testing.expectEqualDeep(negative, clipped.snapshot.graphics.positive[1].rgba.destination);
    try std.testing.expectEqualSlices(u8, image_bytes, clipped.snapshot.graphics.images[1].pixels);
    release(owner, clipped);
    const deleted = try owner.hold();
    defer release(owner, deleted);
    try std.testing.expectEqual(@as(usize, 0), deleted.snapshot.graphics.positive.len);
    try std.testing.expectEqual(@as(usize, 0), deleted.snapshot.graphics.images.len);
}

test "native image output follows Unicode virtual parent cells with immutable held graphics" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    const placeholder = "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85";
    const styled = "\x1b[38;5;42;58;5;3m" ++ placeholder ++ "\x1b[0m";
    try owner.feed("\x1b[?25l" ++
        "\x1b_Ga=T,f=32,s=1,v=1,i=42,p=3,U=1,C=1,q=2;AQIDBA==\x1b\\" ++
        "\x1b_Ga=t,f=32,s=1,v=1,i=43,q=2;AQIDBA==\x1b\\" ++
        "\x1b_Ga=p,i=43,p=4,P=42,Q=3,H=2,V=1,z=1,q=2\x1b\\");
    try owner.flush();
    const unanchored = try owner.hold();
    try std.testing.expectEqual(@as(usize, 0), unanchored.snapshot.graphics.positive.len);
    try owner.release(unanchored);

    try owner.feed("\x1b[2;3H" ++ styled);
    try owner.flush();
    const initial = try owner.hold();
    var holding = true;
    defer if (holding) release(owner, initial);
    try std.testing.expectEqual(@as(usize, 1), initial.snapshot.graphics.positive.len);
    try std.testing.expectEqual(@as(usize, 1), initial.snapshot.graphics.negative.len);
    const width: i32 = initial.snapshot.cell_width;
    const height: i32 = initial.snapshot.cell_height;
    const child = initial.snapshot.graphics.positive[0].rgba.destination;
    try std.testing.expectEqual(@as(i32, 4) * width, child.x);
    try std.testing.expectEqual(@as(i32, 2) * height, child.y);
    const old_bytes = try a.dupe(u8, initial.snapshot.graphics.images[1].pixels);
    defer a.free(old_bytes);
    const data_revision = owner.observation().images(0).content_generation;

    // Text edit, not graphics mutation, relocates the same child.
    try owner.feed("\x1b[2;3H\x1b[X\x1b[4;5H" ++ styled);
    try owner.flush();
    try std.testing.expectEqualDeep(child, initial.snapshot.graphics.positive[0].rgba.destination);
    try std.testing.expectEqualSlices(u8, old_bytes, initial.snapshot.graphics.images[1].pixels);
    release(owner, initial);
    holding = false;
    const moved = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), moved.snapshot.graphics.positive.len);
    const relocated = moved.snapshot.graphics.positive[0].rgba.destination;
    try std.testing.expectEqual(@as(i32, 6) * width, relocated.x);
    try std.testing.expectEqual(@as(i32, 4) * height, relocated.y);
    try std.testing.expectEqual(data_revision, owner.observation().images(0).content_generation);
    release(owner, moved);

    try owner.feed("\x1b[4;5H\x1b[X");
    try owner.flush();
    const absent = try owner.hold();
    defer release(owner, absent);
    try std.testing.expectEqual(@as(usize, 0), absent.snapshot.graphics.positive.len);
    try std.testing.expectEqual(data_revision, owner.observation().images(0).content_generation);
}

test "native indexed Kitty images refresh palette-derived pixels without changing held graphics" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?25l\x1b[2;2H" ++
        "\x1b_Ga=T,f=8,s=2,v=1,i=91,z=1,C=1,q=2;Afg=\x1b\\" ++
        "\x1b[3;2H\x1b_Ga=T,f=16,s=2,v=1,i=92,z=1,C=1,q=2;AoD5/w==\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    var holding = true;
    defer if (holding) release(owner, held);
    try std.testing.expectEqual(@as(usize, 2), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 2), held.snapshot.graphics.positive.len);
    const initial_rgba = try a.dupe(u8, held.snapshot.graphics.images[0].pixels);
    defer a.free(initial_rgba);
    const initial_alpha = try a.dupe(u8, held.snapshot.graphics.images[1].pixels);
    defer a.free(initial_alpha);
    const first_generation = held.snapshot.graphics.images[0].resource.generation;
    const first_command = held.snapshot.graphics.positive[0];
    const decoded_before = owner.observation().images(0).content_generation;

    // Recolor terminal-owned image pixels, while the old accepted frame
    // remains a frozen, caller-pinned copy of the previous palette.
    try owner.feed("\x1b]4;1;#112233;2;#aabbcc\x1b\\\x1b]10;#445566\x1b\\\x1b]11;#778899\x1b\\");
    try owner.flush();
    try std.testing.expect(owner.observation().images(0).content_generation > decoded_before);
    try std.testing.expectEqualSlices(u8, initial_rgba, held.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqualSlices(u8, initial_alpha, held.snapshot.graphics.images[1].pixels);
    try std.testing.expectEqualDeep(first_command, held.snapshot.graphics.positive[0]);
    try std.testing.expectError(error.LeaseBusy, owner.hold());
    release(owner, held);
    holding = false;

    const updated = try owner.hold();
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 255, 0x77, 0x88, 0x99, 255 }, updated.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc, 128, 0x44, 0x55, 0x66, 255 }, updated.snapshot.graphics.images[1].pixels);
    try std.testing.expect(@backingInt(updated.snapshot.graphics.images[0].resource.generation) > @backingInt(first_generation));
    const refreshed_resource = updated.snapshot.graphics.images[0].resource;
    release(owner, updated);

    // A palette color absent from both images never invalidates the native
    // image resource even though the terminal's global colors do change.
    const unchanged = owner.observation().images(0).content_generation;
    try owner.feed("\x1b]4;17;#123456\x1b\\");
    try owner.flush();
    try std.testing.expectEqual(unchanged, owner.observation().images(0).content_generation);
    const unrelated = try owner.hold();
    defer release(owner, unrelated);
    try std.testing.expectEqualDeep(refreshed_resource, unrelated.snapshot.graphics.images[0].resource);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 255, 0x77, 0x88, 0x99, 255 }, unrelated.snapshot.graphics.images[0].pixels);
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

test "warmed alpha and color rows keep accepted resource identities" {
    const f = try text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.feed("\x1b[?25lA😀B");
    try owner.flush();
    const first = try owner.hold();
    const alpha = first.snapshot.resource;
    const color = first.snapshot.color_resource orelse return error.MissingColorResource;
    try owner.release(first);

    // Reuse already admitted alpha and color glyphs without growing either
    // atlas; the emitter must name accepted resources without a rebind pass.
    try owner.feed("\x1b[1;6HA😀");
    try owner.flush();
    const warmed = try owner.hold();
    defer release(owner, warmed);
    try std.testing.expectEqualDeep(alpha, warmed.snapshot.resource);
    try std.testing.expectEqualDeep(color, warmed.snapshot.color_resource orelse return error.MissingColorResource);
    var alpha_seen = false;
    var color_seen = false;
    for (warmed.snapshot.glyphs[0]) |command| switch (command) {
        .alpha_mask => |mask| {
            try std.testing.expectEqualDeep(alpha, mask.resource.resource);
            alpha_seen = true;
        },
        .rgba => |image| {
            try std.testing.expectEqualDeep(color, image.resource.resource);
            color_seen = true;
        },
        else => {},
    };
    try std.testing.expect(alpha_seen and color_seen);
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

test "public output reports narrow command damage only for exact incremental rows" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(4, 20);
    try owner.feed("\x1b[?25lABCDEFXY");
    try owner.flush();
    const initial = try owner.hold();
    const revision = initial.snapshot.content_revision;
    try std.testing.expect(initial.snapshot.row_damage[0] == null);
    try owner.release(initial);

    // X is already resident at the end of this row; changing C at column 3
    // must leave the other glyphs and their resource generation identical.
    try owner.feed("\x1b[1;3HX");
    try owner.flush();
    const changed = try owner.hold();
    try std.testing.expectEqual(revision + 1, changed.snapshot.content_revision);
    const band = changed.snapshot.row_damage[0] orelse return error.MissingDamage;
    try std.testing.expect(band.first > 0 and band.after < changed.snapshot.surface.width);
    try std.testing.expect(band.first < band.after);
    try std.testing.expectEqual(@as(u21, 'X'), owner.observation().semanticView(0).cellAt(0, 2));
    try owner.release(changed);

    // Global reverse changes the entire presentation context, even if only
    // one row's source cells are relevant to a particular consumer.
    try owner.feed("\x1b[?5h");
    try owner.flush();
    const reversed = try owner.hold();
    defer release(owner, reversed);
    try std.testing.expect(reversed.snapshot.row_damage[0] == null);
    try std.testing.expect(reversed.snapshot.visual_context > changed.snapshot.visual_context);
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
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b_Ga=p,i=56,p=1,c=1,r=1,C=1,q=2\x1b\\");
    try owner.flush();
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    release(owner, held);
    const placed = try owner.hold();
    defer release(owner, placed);
    try std.testing.expectEqual(@as(usize, 1), placed.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), placed.snapshot.graphics.positive.len);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, placed.snapshot.graphics.images[0].pixels);
}

test "held RGBA graphics survives deletion and replacement without canonical replay" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\");
    try owner.flush();
    const original = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), original.snapshot.graphics.images.len);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, original.snapshot.graphics.images[0].pixels);
    const first_resource = original.snapshot.graphics.images[0].resource;
    const first_command = original.snapshot.graphics.positive[0];

    try owner.feed("\x1b_Ga=d,d=A,q=2\x1b\\");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, original.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqualDeep(first_command, original.snapshot.graphics.positive[0]);
    release(owner, original);

    const empty = try owner.hold();
    try std.testing.expectEqual(@as(usize, 0), empty.snapshot.graphics.images.len);
    release(owner, empty);

    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=57,C=1,q=2;AAD//w==\x1b\\");
    try owner.flush();
    const blue = try owner.hold();
    defer release(owner, blue);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, blue.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqual(first_resource.resource, blue.snapshot.graphics.images[0].resource.resource);
    try std.testing.expect(@backingInt(blue.snapshot.graphics.images[0].resource.generation) > @backingInt(first_resource.generation));
}

test "Unicode-placeholder Kitty image projects without rasterizing its reserved scalar" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const placeholder = "\x1b[1;1H\x1b[38;5;56m\xf4\x8e\xbb\xae\xcc\x85\xcc\x85\x1b[0m";
    try owner.feed("\x1b_Ga=t,f=32,s=1,v=1,i=56,q=2;/wAA/w==\x1b\\" ++ placeholder);
    try owner.flush();
    const missing = try owner.hold();
    try std.testing.expectEqual(@as(usize, 0), missing.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), missing.snapshot.glyphs[0].len);
    release(owner, missing);

    try owner.feed("\x1b_Ga=p,i=56,p=7,c=1,r=1,U=1,q=2\x1b\\");
    const canonical_images = owner.observation().images(0);
    try std.testing.expectEqual(@as(usize, 2), canonical_images.placementCount());
    try std.testing.expect(canonical_images.placement(1) != null);
    try owner.flush();
    const shown = try owner.hold();
    var shown_pinned = true;
    defer if (shown_pinned) release(owner, shown);
    try std.testing.expectEqual(@as(usize, 1), shown.snapshot.graphics.images.len);
    // Virtual placeholders sit under terminal text by canonical Kitty policy.
    try std.testing.expectEqual(@as(usize, 1), shown.snapshot.graphics.negative.len);
    try std.testing.expectEqual(@as(usize, 0), shown.snapshot.glyphs[0].len);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, shown.snapshot.graphics.images[0].pixels);
    const image_generation = shown.snapshot.graphics.images[0].resource.generation;
    const content_revision = shown.snapshot.content_revision;
    release(owner, shown);
    shown_pinned = false;

    try owner.feed("\x1b[1;2H");
    try owner.flush();
    const cursor_only = try owner.hold();
    try std.testing.expectEqual(image_generation, cursor_only.snapshot.graphics.images[0].resource.generation);
    try std.testing.expectEqual(content_revision, cursor_only.snapshot.content_revision);
    release(owner, cursor_only);

    try owner.feed("\x1b[1;1HX");
    try owner.flush();
    const erased = try owner.hold();
    try std.testing.expectEqual(@as(usize, 0), erased.snapshot.graphics.images.len);
    release(owner, erased);

    // Rewriting the same placeholder changes no Kitty image-plane generation.
    // It must nevertheless reproject the virtual image from canonical cells.
    try owner.feed(placeholder);
    try owner.flush();
    const returned = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), returned.snapshot.graphics.negative.len);
    release(owner, returned);

    try owner.feed("\x1b_Ga=d,d=i,i=56,p=7,q=2\x1b\\");
    try owner.flush();
    const removed = try owner.hold();
    defer release(owner, removed);
    try std.testing.expectEqual(@as(usize, 0), removed.snapshot.graphics.images.len);
}

test "all canonical Kitty image identities publish with exact bindings and immutable held cuts" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const count = @import("howl_vt").Terminal.maximum_images;
    const held = try owner.hold();
    var holding = true;
    defer if (holding) release(owner, held);
    const original = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(original);
    for (0..count) |index| {
        const pixels = [4]u8{ @intCast(index), 11, 23, 255 };
        var encoded: [8]u8 = undefined;
        const payload = std.base64.standard.Encoder.encode(&encoded, &pixels);
        var bytes: [128]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b_Ga=T,i={d},C=1,q=2,s=1,v=1;{s}\x1b\\", .{ 100 + index, payload });
        try owner.feed(command);
    }
    try std.testing.expectEqual(count, owner.observation().images(0).imageCount());
    try owner.flush();
    try std.testing.expectEqualDeep(original, held.snapshot.glyphs[0]);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    release(owner, held);
    holding = false;
    const full = try owner.hold();
    var full_held = true;
    defer if (full_held) release(owner, full);
    try std.testing.expectEqual(count, full.snapshot.graphics.images.len);
    try std.testing.expectEqual(count, full.snapshot.graphics.positive.len);
    for (full.snapshot.graphics.images, full.snapshot.graphics.positive, 0..) |image, command, index| {
        try std.testing.expectEqual(try output.commands.ResourceId.init(3 + index), image.resource.resource);
        try std.testing.expectEqualDeep(image.resource, command.rgba.resource.resource);
        try std.testing.expectEqualSlices(u8, &.{ @intCast(index), 11, 23, 255 }, image.pixels);
    }
    // Re-put one retained image: another placement is not another resource.
    try owner.feed("\x1b_Ga=p,i=100,C=1,q=2\x1b\\");
    try owner.flush();
    // Replace one logical identity and then clear, without disturbing the pin.
    try owner.feed("\x1b_Ga=T,i=355,C=1,q=2,s=1,v=1;AQIDBA==\x1b\\");
    try owner.flush();
    try std.testing.expectEqual(count, full.snapshot.graphics.images.len);
    for (full.snapshot.graphics.images, full.snapshot.graphics.positive, 0..) |image, command, index| {
        try std.testing.expectEqualDeep(image.resource, command.rgba.resource.resource);
        try std.testing.expectEqualSlices(u8, &.{ @intCast(index), 11, 23, 255 }, image.pixels);
    }
    release(owner, full);
    full_held = false;
    {
        const changed = try owner.hold();
        defer release(owner, changed);
        try std.testing.expectEqual(count, changed.snapshot.graphics.images.len);
        try std.testing.expectEqual(count + 1, changed.snapshot.graphics.positive.len);
        try std.testing.expectEqualDeep(changed.snapshot.graphics.positive[0].rgba.resource.resource, changed.snapshot.graphics.positive[1].rgba.resource.resource);
        try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, changed.snapshot.graphics.images[count - 1].pixels);
        try std.testing.expectEqualDeep(changed.snapshot.graphics.images[count - 1].resource, changed.snapshot.graphics.positive[count].rgba.resource.resource);
    }
    try owner.feed("\x1b_Ga=d,d=A,q=2\x1b\\");
    try owner.flush();
    const recovered = try owner.hold();
    defer release(owner, recovered);
    try std.testing.expectEqual(@as(usize, 0), recovered.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), recovered.snapshot.graphics.positive.len);
}

test "eight completely clipped Kitty images do not consume output resource quota" {
    const large = try font(18);
    defer large.deinit();
    const small = try font(12);
    defer small.deinit();
    const reference = try ready(a, small);
    const small_width = reference.acceptedMetrics().?.cell_width;
    destroy(reference);
    const owner = try ready(a, large);
    defer destroy(owner);
    try std.testing.expect(small_width < owner.acceptedMetrics().?.cell_width);
    try owner.resize(2, 1);
    for (0..8) |index| {
        var bytes: [128]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i={d},X={d},c=1,r=1,C=1,q=2;/wAA/w==\x1b\\", .{ 100 + index, small_width });
        try owner.feed(command);
    }
    try owner.replaceWorkingBorrowed(small, .{});
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.positive.len);
}

test "malformed Kitty placeholder run does not hide later valid runs on its row" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const invalid = "\u{10eeee}\u{0305}\u{0305}\u{1d244}";
    const valid = "\u{10eeee}\u{0305}\u{0305}";
    try owner.feed(
        "\x1b_Ga=t,f=32,s=1,v=1,i=56,q=2;/wAA/w==\x1b\\" ++
            "\x1b_Ga=p,i=56,p=7,c=1,r=1,U=1,q=2\x1b\\" ++
            "\x1b[H\x1b[38;5;56m" ++ invalid ++ " " ++ valid ++
            "\x1b[2;1H" ++ valid ++ "\x1b[0m",
    );
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 2), held.snapshot.graphics.negative.len);
    try std.testing.expectEqual(@as(i32, 2 * held.snapshot.cell_width), held.snapshot.graphics.negative[0].rgba.destination.x);
    try std.testing.expectEqual(held.snapshot.graphics.negative[0].rgba.destination.y + @as(i32, held.snapshot.cell_height), held.snapshot.graphics.negative[1].rgba.destination.y);
}

test "direct Kitty images have deterministic deep negative and positive paint order" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed(
        "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=1,z=-1073741825,C=1,q=2;/wAA/w==\x1b\\" ++
            "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=2,z=-1,C=1,q=2;AP8A/w==\x1b\\" ++
            "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=3,z=1,C=1,q=2;AAD//w==\x1b\\",
    );
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 3), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.deep.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.negative.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.positive.len);
    const scene = held.snapshot.graphics;
    try std.testing.expectEqualDeep(scene.images[0].resource, scene.deep[0].rgba.resource.resource);
    try std.testing.expectEqualDeep(scene.images[1].resource, scene.negative[0].rgba.resource.resource);
    try std.testing.expectEqualDeep(scene.images[2].resource, scene.positive[0].rgba.resource.resource);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, scene.images[0].pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, scene.images[1].pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, scene.images[2].pixels);
}

test "direct output preserves Kitty source crop and destination pixel offsets" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed(
        "\x1b_Ga=t,f=32,s=2,v=2,i=11,q=2;AQIDBAUGBwgJCgsMDQ4PEA==\x1b\\" ++
            "\x1b[1;1H\x1b_Ga=p,i=11,p=3,x=1,y=0,w=1,h=2,c=2,r=3,X=2,Y=4,z=-7,C=1,q=2\x1b\\",
    );
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.negative.len);
    const command = held.snapshot.graphics.negative[0].rgba;
    const metrics = owner.acceptedMetrics().?;
    // Source crop is 1:2. Center its fit in the box remaining after X/Y.
    const box_width = metrics.cell_width * 2 - 2;
    const box_height = metrics.cell_height * 3 - 4;
    const fitted_width = @min(box_width, @max(1, box_height / 2));
    const fitted_height = @min(box_height, box_width * 2);
    try std.testing.expectEqual(@as(i32, 2 + (box_width - fitted_width) / 2), command.destination.x);
    try std.testing.expectEqual(@as(i32, 4 + (box_height - fitted_height) / 2), command.destination.y);
    try std.testing.expectEqual(fitted_width, command.destination.width);
    try std.testing.expectEqual(fitted_height, command.destination.height);
    try std.testing.expectEqualDeep(output.commands.SourceRect{
        .x = 1,
        .y = 0,
        .width = 1,
        .height = 2,
    }, command.resource.source.?);
}

test "tall physical image survives scrolling when its anchor is above the viewport" {
    const f = try font(12);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(4, 4);
    try owner.feed("\x1b[H\x1b_Ga=T,f=32,s=1,v=4,i=56,r=3,C=1,q=2;/wAA//8AAP//AAD//wAA/w==\x1b\\");
    try owner.flush();
    const first = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), first.snapshot.graphics.positive.len);
    try std.testing.expectEqual(@as(i32, 0), first.snapshot.graphics.positive[0].rgba.destination.y);
    const cell_height = first.snapshot.cell_height;
    try owner.feed("\x1b[4;1H\n");
    try owner.flush();
    try std.testing.expectEqual(@as(i32, 0), first.snapshot.graphics.positive[0].rgba.destination.y);
    release(owner, first);

    const scrolled = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), scrolled.snapshot.graphics.positive.len);
    try std.testing.expectEqual(-@as(i32, cell_height), scrolled.snapshot.graphics.positive[0].rgba.destination.y);
    release(owner, scrolled);

    owner.selectHistoryOffset(1);
    try owner.flush();
    const history = try owner.hold();
    defer release(owner, history);
    try std.testing.expectEqual(@as(u32, 1), history.snapshot.history_offset);
    try std.testing.expectEqual(@as(i32, 0), history.snapshot.graphics.positive[0].rgba.destination.y);
}

test "Sixel decoded pixels reach direct graphics commands without Render" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[H\x1bPq\"1;1;3;6#1;2;100;0;0!3~\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.positive.len);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, held.snapshot.graphics.images[0].pixels[0..4]);
    const command = held.snapshot.graphics.positive[0].rgba;
    try std.testing.expectEqual(@as(i32, 0), command.destination.x);
    try std.testing.expectEqual(@as(i32, 0), command.destination.y);
    try std.testing.expectEqual(@as(u16, 3), command.destination.width);
    try std.testing.expectEqual(@as(u16, 6), command.destination.height);
}

test "every graphics staging allocation failure retains the previous cut and retries" {
    const f = try font(12);
    defer f.deinit();
    var failing = std.testing.FailingAllocator.init(a, .{});
    const owner = try ready(failing.allocator(), f);
    defer destroy(owner);
    const original = try owner.hold();
    try std.testing.expectEqual(@as(usize, 0), original.snapshot.graphics.images.len);
    const glyphs = try a.dupe(output.commands.Command, original.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\");
    // Ordering storage, copied RGBA slab, final commands, exact descriptors.
    // Each failure starts a clean graphics stage and must preserve the pin.
    for (0..4) |skip| {
        failing.fail_index = failing.alloc_index + skip;
        try std.testing.expectError(error.OutOfMemory, owner.flush());
        try std.testing.expectEqualDeep(glyphs, original.snapshot.glyphs[0]);
        try std.testing.expectEqual(@as(usize, 0), original.snapshot.graphics.images.len);
    }
    failing.fail_index = std.math.maxInt(usize);
    try owner.flush();
    try std.testing.expectEqualDeep(glyphs, original.snapshot.glyphs[0]);
    release(owner, original);
    const recovered = try owner.hold();
    defer release(owner, recovered);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, recovered.snapshot.graphics.images[0].pixels);
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
    try std.testing.expect(held.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b[?1049l");
    try owner.flush();
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
    release(owner, held);
    const primary = try owner.hold();
    defer release(owner, primary);
    try std.testing.expect(!primary.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 1), primary.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), primary.snapshot.graphics.positive.len);
}

test "alternate image does not block a clean primary screen" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b[?47h\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\\x1b[?47lPRIMARY");
    try owner.flush();
    const held = try owner.hold();
    try std.testing.expect(!held.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const glyphs = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(glyphs);
    try owner.feed("\x1b[?47h");
    try owner.flush();
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
    release(owner, held);
    const alternate = try owner.hold();
    defer release(owner, alternate);
    try std.testing.expect(alternate.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 1), alternate.snapshot.graphics.images.len);
}

test "an inactive placement does not hide an active placement" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\\x1b[?47hALT\x1b_Ga=T,f=32,s=1,v=1,i=57,C=1,q=2;/wAA/w==\x1b\\");
    try owner.flush();
    const with_image = try owner.hold();
    try std.testing.expectEqual(@as(usize, 1), with_image.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), with_image.snapshot.graphics.positive.len);
    release(owner, with_image);
    try owner.feed("\x1b_Ga=d,d=i,i=57,q=2\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    try std.testing.expect(held.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    try owner.feed("\x1b[?47l");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    release(owner, held);
    const primary = try owner.hold();
    defer release(owner, primary);
    try std.testing.expectEqual(@as(usize, 1), primary.snapshot.graphics.images.len);
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

test "OSC 66 fractional glyph and colour alignment use the scaled render area on every strip" {
    const f = try text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(3, 8);
    const Rect = output.commands.Rect;
    for ([_][]const u8{ "─", "X", "😀" }) |glyph| {
        for ([_]u16{ 2, 3 }) |denominator| {
            var reference: ?Rect = null;
            for (0..3) |vertical| for (0..3) |horizontal| {
                var wire: [128]u8 = undefined;
                try owner.feed(try std.fmt.bufPrint(&wire, "\x1b[2J\x1b[H\x1b[?25l\x1b]66;s=2:w=2:n=1:d={d}:v={d}:h={d};{s}\x07", .{ denominator, vertical, horizontal, glyph }));
                try owner.flush();
                const held = try owner.hold();
                defer release(owner, held);
                const snap = held.snapshot;
                const width = snap.cell_width * 4;
                const height = snap.cell_height * 2;
                const rw = (width + denominator - 1) / denominator;
                const rh = (height + denominator - 1) / denominator;
                const dx: i32 = switch (horizontal) {
                    1 => width - rw,
                    2 => (width - rw) / 2,
                    else => 0,
                };
                const dy: i32 = switch (vertical) {
                    1 => height - rh,
                    2 => (height - rh) / 2,
                    else => 0,
                };
                var destination: ?Rect = null;
                var covered: u32 = 0;
                for (snap.glyphs, 0..) |commands, row| {
                    for (commands) |command| {
                        const value: struct { destination: Rect, clip: Rect } = switch (command) {
                            .alpha_mask => |mask| .{ .destination = mask.destination, .clip = mask.clip },
                            .rgba => |rgba| .{ .destination = rgba.destination, .clip = rgba.clip },
                            else => return error.UnexpectedCommand,
                        };
                        var global = value.destination;
                        global.y += @as(i32, @intCast(row * snap.cell_height));
                        const clip_y = value.clip.y + @as(i32, @intCast(row * snap.cell_height));
                        try std.testing.expect(value.clip.x >= dx and value.clip.x + @as(i32, value.clip.width) <= dx + @as(i32, rw));
                        try std.testing.expect(clip_y >= dy and clip_y + @as(i32, value.clip.height) <= dy + @as(i32, rh));
                        if (destination) |prior| try std.testing.expectEqualDeep(prior, global) else destination = global;
                        covered += @as(u32, value.clip.width) * value.clip.height;
                    }
                }
                const actual = destination orelse return error.MissingGlyph;
                if (reference) |base| {
                    var expected = base;
                    expected.x += dx;
                    expected.y += dy;
                    try std.testing.expectEqualDeep(expected, actual);
                } else reference = actual;
                try std.testing.expect(covered != 0);
                if (std.mem.eql(u8, glyph, "─")) {
                    try std.testing.expectEqualDeep(Rect{ .x = dx, .y = dy, .width = rw, .height = rh }, actual);
                    try std.testing.expectEqual(@as(u32, rw) * rh, covered);
                }
                try std.testing.expectEqual(@as(u8, 4), owner.observation().semanticView(0).cellInfoAt(0, 0).width);
                try std.testing.expectEqual(@as(u8, 2), owner.observation().semanticView(0).cellInfoAt(1, 3).height);
            };
        }
    }
}

test "Unicode Core renders unsupported emoji ZWJ clusters as one bounded replacement" {
    const fonts = @import("test_fonts");
    const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &.{fonts.colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const shape = try text.ShapeBuffer.init(a, 24);
    defer shape.deinit();
    var glyphs: [24]text.Glyph = undefined;
    const joined = try f.shape(shape, .{ .codepoints = &.{ 0x1f469, 0x200d, 0x1f4bb }, .clusters = &.{ 0, 1, 2 } }, &glyphs);
    try std.testing.expectEqual(@as(usize, 1), joined.glyphs.len);
    const separated = try f.shape(shape, .{ .codepoints = &.{ 0x1f469, 0x200d, 0x1f527 }, .clusters = &.{ 0, 1, 2 } }, &glyphs);
    // All component scalars have font coverage; no ligature exists.
    try std.testing.expect(separated.glyphs.len > 1);
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8, .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(3, 12);
    try owner.feed("\x1b[?25l\x1b[?2027h👩‍💻X\r\n👩‍🔧Y\r\n👩‍🚀Z");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const view = owner.observation().semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    var scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f4bb }, view.cellScalarsAt(0, 0, &scalars));
    try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f527 }, view.cellScalarsAt(1, 0, &scalars));
    try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f680 }, view.cellScalarsAt(2, 0, &scalars));
    const snap = held.?.snapshot;
    const right = @as(i32, snap.cell_width) * 2;
    for (0..3) |row| {
        try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(@intCast(row), 0).width);
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(@intCast(row), 1).x);
        try std.testing.expectEqual(@as(u21, @intCast('X' + row)), view.cellAt(@intCast(row), 2));
        try std.testing.expectEqual(@as(usize, 2), snap.glyphs[row].len);
        const first = snap.glyphs[row][0];
        if (row == 0) {
            try std.testing.expect(first == .rgba);
            try std.testing.expect(first.rgba.clip.x >= 0);
            try std.testing.expect(first.rgba.clip.x + @as(i32, first.rgba.clip.width) <= right);
        } else {
            try std.testing.expect(first == .alpha_mask);
            try std.testing.expect(first.alpha_mask.clip.x >= 0);
            try std.testing.expect(first.alpha_mask.clip.x + @as(i32, first.alpha_mask.clip.width) <= right);
        }
    }
    // Decomposition fallback and missing scalar coverage use the same
    // replacement ink. Neither substitutes the canonical scalar sequence.
    try std.testing.expectEqualDeep(snap.glyphs[1][0].alpha_mask.resource.source, snap.glyphs[2][0].alpha_mask.resource.source);
    const before = try a.dupe(output.commands.Command, snap.glyphs[1]);
    defer a.free(before);
    try owner.feed("\x1b[?2027l\x1b[3;1H\r\n");
    owner.selectHistoryOffset(1);
    try owner.flush();
    try std.testing.expectEqualSlices(output.commands.Command, before, held.?.snapshot.glyphs[1]);
    try owner.release(held.?);
    held = null;
    const retained = try owner.hold();
    defer release(owner, retained);
    try std.testing.expectEqualSlices(output.commands.Command, before, retained.snapshot.glyphs[1]);
    try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f527 }, owner.observation().semanticView(1).cellScalarsAt(1, 0, &scalars));
}

test "Unicode selectors prefer text and colour faces without changing negotiated occupancy" {
    const fonts = @import("test_fonts");
    for ([_]bool{ false, true }) |colour_first| {
        const fallbacks = if (colour_first)
            [_][]const u8{ fonts.colour_font, fonts.symbol_font }
        else
            [_][]const u8{ fonts.symbol_font, fonts.colour_font };
        const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &fallbacks, .size = .{ .pixels = 20 } });
        defer f.deinit();
        const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
        defer destroy(owner);
        try owner.resize(3, 12);
        try owner.feed("\x1b[?25l\x1b[?2027h☺\u{fe0e}X\r\n☺\u{fe0f}Y\r\n☺Z");
        try owner.flush();
        const held = try owner.hold();
        defer release(owner, held);
        const snap = held.snapshot;
        try std.testing.expectEqual(@as(usize, 2), snap.glyphs[0].len);
        try std.testing.expectEqual(@as(usize, 2), snap.glyphs[1].len);
        try std.testing.expectEqual(@as(usize, 2), snap.glyphs[2].len);
        try std.testing.expect(snap.glyphs[0][0] == .alpha_mask);
        try std.testing.expect(snap.glyphs[1][0] == .rgba);
        try std.testing.expectEqual(colour_first, snap.glyphs[2][0] == .rgba);
        const view = owner.observation().semanticView(0);
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(0, 0).width);
        try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(1, 0).width);
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(2, 0).width);
        try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 1));
        try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(1, 2));
        try std.testing.expectEqual(@as(u21, 'Z'), view.cellAt(2, 1));
    }
}

test "Unicode Core searches later joined faces without collapsing explicit width strings" {
    const fonts = @import("test_fonts");
    const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &.{ fonts.decomposed_colour_font, fonts.colour_font }, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(4, 12);
    // First warm the exact same scalar sequence under ordinary unconstrained
    // shaping. Natural single-image shaping must not reuse that cached run.
    try owner.feed("\x1b[?25l\x1b[?2027h\x1b]66;w=4;👩‍💻\x07X\r\n👩‍💻Y\r\n\x1b]66;w=4;👩‍💻\x07Z\r\n👩‍💻W");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    const view = owner.observation().semanticView(0);
    for (0..4) |row| {
        const explicit = row % 2 == 0;
        try std.testing.expectEqual(@as(u8, if (explicit) 4 else 2), view.cellInfoAt(@intCast(row), 0).width);
        try std.testing.expectEqual(explicit, view.cellInfoAt(@intCast(row), 0).explicit_width);
        try std.testing.expectEqual(@as(usize, if (explicit) 3 else 2), snap.glyphs[row].len);
        try std.testing.expect(snap.glyphs[row][0] == .rgba);
        if (explicit) try std.testing.expect(snap.glyphs[row][1] == .rgba);
        var scalars: [24]u21 = undefined;
        try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f4bb }, view.cellScalarsAt(@intCast(row), 0, &scalars));
    }
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'W'), view.cellAt(3, 2));
}

test "Unicode Core natural scaled images and explicit width strings retain distinct shaped runs" {
    const fonts = @import("test_fonts");
    const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &.{ fonts.decomposed_colour_font, fonts.colour_font }, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(5, 12);
    try owner.feed("\x1b[?25l\x1b[?2027h\x1b]66;s=2:w=2;👩‍💻\x07\x1b[3;1H\x1b]66;s=2;👩‍💻\x07");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    const view = owner.observation().semanticView(0);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_col);
    for (0..4) |row| {
        const cell = view.cellInfoAt(@intCast(row), 0);
        try std.testing.expectEqual(@as(u8, 4), cell.width);
        try std.testing.expectEqual(@as(u8, 2), cell.height);
        try std.testing.expectEqual(@as(u8, @intCast(row % 2)), cell.y);
        try std.testing.expectEqual(row < 2, cell.explicit_width);
        var count: usize = 0;
        for (snap.glyphs[row]) |cmd| {
            try std.testing.expect(cmd == .rgba);
            try std.testing.expect(cmd.rgba.clip.x >= 0);
            try std.testing.expect(cmd.rgba.clip.x + @as(i32, cmd.rgba.clip.width) <= @as(i32, snap.cell_width) * 4);
            count += 1;
        }
        // Both strips of the joined image retain one image command. Both
        // strips of the application string retain its two component images.
        try std.testing.expectEqual(@as(usize, if (row < 2) 2 else 1), count);
    }
    var scalars: [24]u21 = undefined;
    for ([_]u16{ 0, 2 }) |row|
        try std.testing.expectEqualSlices(u21, &.{ 0x1f469, 0x200d, 0x1f4bb }, view.cellScalarsAt(row, 0, &scalars));
}

test "Kitty underline colour follows effective foreground unless explicitly assigned" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(4, 12);
    const Color = output.commands.Color;
    const fg: Color = .{ .r = 10, .g = 20, .b = 30, .a = 255 };
    const bg: Color = .{ .r = 40, .g = 50, .b = 60, .a = 255 };
    const ul: Color = .{ .r = 70, .g = 80, .b = 90, .a = 255 };
    try owner.feed("\x1b[?25l\x1b[38;2;10;20;30;48;2;40;50;60;4mA\x1b[7mB\x1b[58;2;70;80;90mC\x1b[27mD\x1b[59mE\x1b[9;58;2;70;80;90mF");
    try owner.feed("\x1b[2;1H\x1b[0;38;2;10;20;30;48;2;40;50;60;4;9;7m\x1b]66;s=2;X\x07\x1b[2;4H\x1b[58;2;70;80;90m\x1b]66;s=2;Y\x07");
    for ([_]bool{ false, true }) |reverse_screen| {
        if (reverse_screen) try owner.feed("\x1b[?5h");
        try owner.flush();
        const held = try owner.hold();
        defer release(owner, held);
        const snap = held.snapshot;
        const plain = if (reverse_screen) bg else fg;
        const reversed = if (reverse_screen) fg else bg;
        const expected = [_]Color{ plain, reversed, ul, ul, plain, ul, plain };
        try std.testing.expectEqual(expected.len, snap.decorations[0].len);
        for (expected, snap.decorations[0]) |color, command| {
            try std.testing.expect(command == .solid);
            try std.testing.expectEqual(color, command.solid.color);
        }
        // Scaled X uses the reversed effective foreground for both lines;
        // scaled Y uses explicit underline colour but foreground for strike.
        var x_count: usize = 0;
        var y_underline: usize = 0;
        var y_strike: usize = 0;
        for (snap.decorations[1..3]) |strip| for (strip) |command| {
            try std.testing.expect(command == .solid);
            if (command.solid.rect.x == 0) {
                try std.testing.expectEqual(reversed, command.solid.color);
                x_count += 1;
            } else {
                try std.testing.expectEqual(@as(i32, snap.cell_width) * 3, command.solid.rect.x);
                if (command.solid.color == ul) {
                    y_underline += 1;
                } else {
                    try std.testing.expectEqual(reversed, command.solid.color);
                    y_strike += 1;
                }
            }
        };
        try std.testing.expect(x_count >= 2 and y_underline != 0 and y_strike != 0);
    }
}

test "Kitty indexed underline colours refresh in history without mutating a held frame" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(2, 8);
    try owner.feed("\x1b[?25l\x1b]4;1;#123456;2;#345678\x07\x1b[31;4mA\x1b[58:5:2mB\x1b[59mC\x1b[0m\r\nD\r\nE");
    owner.selectHistoryOffset(1);
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const Color = output.commands.Color;
    const old = [_]Color{ .{ .r = 0x12, .g = 0x34, .b = 0x56, .a = 255 }, .{ .r = 0x34, .g = 0x56, .b = 0x78, .a = 255 }, .{ .r = 0x12, .g = 0x34, .b = 0x56, .a = 255 } };
    try std.testing.expectEqual(old.len, held.?.snapshot.decorations[0].len);
    for (old, held.?.snapshot.decorations[0]) |color, command| try std.testing.expectEqual(color, command.solid.color);
    const previous = try a.dupe(output.commands.Command, held.?.snapshot.decorations[0]);
    defer a.free(previous);
    try owner.feed("\x1b]4;1;#abcdef;2;#fedcba\x07");
    try owner.flush();
    try std.testing.expectEqualSlices(output.commands.Command, previous, held.?.snapshot.decorations[0]);
    try owner.release(held.?);
    held = null;
    const next = try owner.hold();
    defer release(owner, next);
    const updated = [_]Color{ .{ .r = 0xab, .g = 0xcd, .b = 0xef, .a = 255 }, .{ .r = 0xfe, .g = 0xdc, .b = 0xba, .a = 255 }, .{ .r = 0xab, .g = 0xcd, .b = 0xef, .a = 255 } };
    try std.testing.expectEqual(updated.len, next.snapshot.decorations[0].len);
    for (updated, next.snapshot.decorations[0]) |color, command| try std.testing.expectEqual(color, command.solid.color);
    const view = owner.observation().semanticView(1);
    try std.testing.expectEqual(@as(u32, 1), view.history_count);
    try std.testing.expectEqual(@as(u32, 1), view.cellInfoAt(0, 0).attrs.fg.value);
    try std.testing.expectEqual(@as(u32, 2), view.cellInfoAt(0, 1).attrs.underline_color.value);
    try std.testing.expect(view.cellInfoAt(0, 2).attrs.underline_color.kind == .default);
}

test "Kitty underline style projections have distinct bounded ink and preserve explicit colour" {
    const f = try font(24);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(7, 8);
    try owner.feed("\x1b[?25l\x1b[58:2::70:80:90;4:0mA\r\n\x1b[4:1mA\r\n\x1b[4:2mA\r\n\x1b[4:3mA\r\n\x1b[4:4mA\r\n\x1b[4:5mA\r\n\x1b[24mA");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    try std.testing.expectEqual(@as(usize, 0), snap.decorations[0].len);
    try std.testing.expectEqual(@as(usize, 0), snap.decorations[6].len);
    try std.testing.expectEqual(@as(usize, 1), snap.decorations[1].len);
    try std.testing.expectEqual(@as(usize, 2), snap.decorations[2].len);
    const first = snap.decorations[2][0].solid;
    const second = snap.decorations[2][1].solid;
    try std.testing.expect(first.rect.y + @as(i32, first.rect.height) < second.rect.y);
    const expected: output.commands.Color = .{ .r = 70, .g = 80, .b = 90, .a = 255 };
    for (snap.decorations[1..6]) |commands| {
        for (commands) |command| switch (command) {
            .solid => |value| {
                try std.testing.expectEqual(expected, value.color);
                try std.testing.expect(value.rect.x >= 0 and value.rect.x + @as(i32, value.rect.width) <= snap.cell_width);
                try std.testing.expect(value.rect.y >= 0 and value.rect.y + @as(i32, value.rect.height) <= snap.cell_height);
            },
            .alpha_mask => |value| {
                try std.testing.expectEqual(expected, value.color);
                try std.testing.expect(value.clip.x >= 0 and value.clip.x + @as(i32, value.clip.width) <= snap.cell_width);
                try std.testing.expect(value.clip.y >= 0 and value.clip.y + @as(i32, value.clip.height) <= snap.cell_height);
            },
            else => return error.UnexpectedDecoration,
        };
    }
    for (3..6) |row| {
        try std.testing.expectEqual(@as(usize, 1), snap.decorations[row].len);
        try std.testing.expect(snap.decorations[row][0] == .alpha_mask);
    }
    const curly = snap.decorations[3][0].alpha_mask.resource.source.?;
    const dotted = snap.decorations[4][0].alpha_mask.resource.source.?;
    const dashed = snap.decorations[5][0].alpha_mask.resource.source.?;
    try std.testing.expect(curly.height > dotted.height);
    try std.testing.expect(!std.meta.eql(dotted, dashed));
    const masks = [_]output.commands.SourceRect{ dotted, dashed };
    for (masks, [_]usize{ 2, 5 }, [_]usize{ 1, 3 }) |mask, step, ink| {
        for (0..mask.height) |y| for (0..mask.width) |x| {
            const pos = (@as(usize, @intCast(mask.y)) + y) * snap.atlas_width + @as(usize, @intCast(mask.x)) + x;
            try std.testing.expectEqual(@as(u8, if (x % step < ink) 255 else 0), snap.atlas_pixels[pos]);
        };
    }
}

test "Kitty double underline remains visible at small font and fractional heights" {
    for ([_]u16{ 4, 6, 8, 12, 24 }) |pixels| {
        const f = try font(pixels);
        defer f.deinit();
        const owner = try output.Terminal.init(a, f);
        defer destroy(owner);
        try owner.resize(3, 8);
        try owner.feed("\x1b[?25l\x1b[4:2mX\x1b[2;1H\x1b]66;s=1:n=1:d=7:v=1;X\x07");
        try owner.flush();
        const held = try owner.hold();
        defer release(owner, held);
        const snap = held.snapshot;
        for ([_]u16{ snap.cell_height, (snap.cell_height + 6) / 7 }, 0..) |height, row| {
            const lines = snap.decorations[row];
            try std.testing.expectEqual(@as(usize, if (height >= 2) 2 else 1), lines.len);
            const top = if (row == 0) @as(i32, 0) else @as(i32, snap.cell_height - height);
            for (lines) |line| {
                try std.testing.expect(line == .solid);
                try std.testing.expect(line.solid.rect.height != 0);
                try std.testing.expect(line.solid.rect.y >= top);
                try std.testing.expect(line.solid.rect.y + @as(i32, line.solid.rect.height) <= snap.cell_height);
            }
            if (height >= 2) {
                const first_end = lines[0].solid.rect.y + @as(i32, lines[0].solid.rect.height);
                try std.testing.expect(first_end <= lines[1].solid.rect.y);
                if (height >= 3) try std.testing.expect(first_end < lines[1].solid.rect.y);
            }
        }
    }
}

test "Kitty dim underline and strike share text opacity without losing explicit RGB" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(5, 12);
    try owner.feed("\x1b[?25l\x1b[38;2;10;20;30;48;2;40;50;60;2;9;4;58;2;70;80;90mA\x1b[7mB\x1b[59mC\x1b[22mD\x1b[2m\x1b[2;1H\x1b[58;2;70;80;90;4:4mX\x1b[3;1H\x1b]66;s=2;Y\x07");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const Color = output.commands.Color;
    const fg: Color = .{ .r = 10, .g = 20, .b = 30, .a = 140 };
    const bg: Color = .{ .r = 40, .g = 50, .b = 60, .a = 140 };
    const ul: Color = .{ .r = 70, .g = 80, .b = 90, .a = 140 };
    const plain: Color = .{ .r = 40, .g = 50, .b = 60, .a = 255 };
    const expected = [_]Color{ ul, fg, ul, bg, bg, bg, plain, plain };
    try std.testing.expectEqual(expected.len, held.snapshot.decorations[0].len);
    for (expected, held.snapshot.decorations[0]) |color, line| try std.testing.expectEqual(color, line.solid.color);
    var masks: usize = 0;
    for (held.snapshot.decorations[1..4]) |strip| for (strip) |line| {
        switch (line) {
            .alpha_mask => |mask| {
                try std.testing.expectEqual(ul, mask.color);
                masks += 1;
            },
            .solid => |solid_line| try std.testing.expectEqual(bg, solid_line.color),
            else => return error.UnexpectedDecoration,
        }
    };
    try std.testing.expect(masks >= 2);
}

test "wide scaled underline chunks retain native pattern phase inside a narrow atlas" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 32, .height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(3, 16);
    try owner.feed("\x1b[?25l\x1b[4:5m\x1b]66;s=2:w=7;X\x07");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    try std.testing.expect(snap.cell_width * 7 > snap.atlas_width);
    try std.testing.expectEqual(@as(usize, 7), snap.decorations[1].len);
    var end: i32 = 0;
    for (snap.decorations[1], 0..) |cmd, index| {
        try std.testing.expect(cmd == .alpha_mask);
        const mask = cmd.alpha_mask;
        try std.testing.expectEqual(end, mask.destination.x);
        try std.testing.expectEqual(snap.cell_width * 2, mask.destination.width);
        end += mask.destination.width;
        const source = mask.resource.source.?;
        try std.testing.expectEqual(snap.cell_width, source.width);
        try std.testing.expectEqual(@as(u16, 1), source.height);
        for (0..source.width) |x| {
            const at = @as(usize, source.y) * snap.atlas_width + source.x + x;
            try std.testing.expectEqual(@as(u8, if ((index * snap.cell_width + x) % 5 < 3) 255 else 0), snap.atlas_pixels[at]);
        }
    }
    try std.testing.expectEqual(@as(i32, snap.cell_width) * 14, end);
}

test "transparent colour metadata retains explicit alpha and host fallback without dimming opaque output" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(2, 8);
    try owner.feed("\x1b[?25l\x1b]11;#112233\x07\x1b[48;2;68;85;102mX\x1b[0mY");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const before = held.?.snapshot.background;
    const row = try a.dupe(output.commands.Command, held.?.snapshot.backgrounds[0]);
    defer a.free(row);
    try owner.feed("\x1b]21;transparent_background_color1=#112233@-0.5;transparent_background_color2=#445566@0.25;transparent_background_color1=?;transparent_background_color2=?\x07");
    try owner.flush();
    try std.testing.expect(held.?.snapshot.transparent_background[0] == null);
    try std.testing.expectEqualDeep(before, held.?.snapshot.background);
    try std.testing.expectEqualSlices(output.commands.Command, row, held.?.snapshot.backgrounds[0]);
    try owner.release(held.?);
    held = null;
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectEqual(@as(?f32, null), next.snapshot.transparent_background[0].?.opacity);
    try std.testing.expectEqual(@as(?f32, 0.25), next.snapshot.transparent_background[1].?.opacity);
    try std.testing.expectEqualDeep(before, next.snapshot.background);
    try std.testing.expectEqualSlices(output.commands.Command, row, next.snapshot.backgrounds[0]);
    try std.testing.expectEqual(@as(u8, 255), next.snapshot.background.solid.color.a);
    for (next.snapshot.backgrounds[0]) |command| try std.testing.expectEqual(@as(u8, 255), command.solid.color.a);
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color1=rgb:11/22/33@1.0000;transparent_background_color2=rgb:44/55/66@0.2471\x1b\\", owner.replyBytes());
}

test "WezTerm RGBA cell output retains independent background ink and underline alpha" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(3, 8);
    try owner.feed("\x1b[?25l\x1b[38:6::255:0:0:128;48:6::0:255:0:64;58:6::0:0:255:192;4m█\x1b[2m█\x1b[7m█\x1b[0m");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const s = held.snapshot;
    const Color = output.commands.Color;
    const red: Color = .{ .r = 255, .g = 0, .b = 0, .a = 128 };
    const green: Color = .{ .r = 0, .g = 255, .b = 0, .a = 64 };
    const blue: Color = .{ .r = 0, .g = 0, .b = 255, .a = 192 };
    try std.testing.expectEqual(@as(usize, 2), s.backgrounds[0].len);
    try std.testing.expectEqual(green, s.backgrounds[0][0].solid.color);
    try std.testing.expectEqual(red, s.backgrounds[0][1].solid.color);
    try std.testing.expectEqual(@as(usize, 3), s.glyphs[0].len);
    try std.testing.expectEqual(red, s.glyphs[0][0].alpha_mask.color);
    var dim_red = red;
    dim_red.a = 70;
    try std.testing.expectEqual(dim_red, s.glyphs[0][1].alpha_mask.color);
    var dim_green = green;
    dim_green.a = 35;
    try std.testing.expectEqual(dim_green, s.glyphs[0][2].alpha_mask.color);
    try std.testing.expectEqual(@as(usize, 3), s.decorations[0].len);
    try std.testing.expectEqual(blue, s.decorations[0][0].solid.color);
    var dim_blue = blue;
    dim_blue.a = 106;
    for (s.decorations[0][1..]) |cmd| try std.testing.expectEqual(dim_blue, cmd.solid.color);
}

test "WezTerm RGBA scaled strips preserve independent text alpha and intrinsic image ink" {
    const fonts = @import("test_fonts");
    const f = try text.FontSet.init(a, .{
        .primary = fonts.primary_font,
        .fallbacks = &.{fonts.colour_font},
        .size = .{ .pixels = 20 },
    });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(6, 12);
    try owner.feed("\x1b[?25l\x1b[38:6:255:0:0:128;48:6:0:255:0:64;58:6:0:0:255:192;4;9m\x1b]66;s=2;█\x07\x1b[1;5H\x1b]66;s=2;😀\x07");
    try owner.feed("\x1b[2m\x1b[3;1H\x1b]66;s=2;█\x07\x1b[3;5H\x1b]66;s=2;😀\x07");
    try owner.feed("\x1b[22m\x1b[38:6:255:0:0:0m\x1b[5;1H\x1b]66;s=2:n=1:d=2;█\x07\x1b[5;5H\x1b]66;s=2:n=1:d=2;😀\x07");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    const view = owner.observation().semanticView(0);
    const Color = output.commands.Color;
    const bg: Color = .{ .r = 0, .g = 255, .b = 0, .a = 64 };
    var colour_count: usize = 0;
    var fractional_ink: usize = 0;
    for (0..6) |row| {
        const fg_alpha: u8 = if (row < 2) 128 else if (row < 4) 70 else 0;
        const underline_alpha: u8 = if (row >= 2 and row < 4) 106 else 192;
        const raw_alpha: u8 = if (row < 4) 128 else 0;
        const glyph_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = fg_alpha };
        const underline_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = underline_alpha };
        for ([_]u16{ 0, 4 }, [_]u8{ 2, 4 }) |col, width| {
            const cell = view.cellInfoAt(@intCast(row), col);
            try std.testing.expectEqual(width, cell.width);
            try std.testing.expectEqual(@as(u8, 2), cell.height);
            try std.testing.expectEqual(@as(u8, @intCast(row % 2)), cell.y);
            try std.testing.expectEqual(raw_alpha, @as(u8, @truncate(cell.attrs.fg.value >> 24)));
        }
        try std.testing.expectEqual(@as(usize, 2), snap.backgrounds[row].len);
        for (snap.backgrounds[row]) |cmd| try std.testing.expectEqual(bg, cmd.solid.color);
        for (snap.decorations[row]) |cmd| {
            try std.testing.expect(cmd == .solid);
            try std.testing.expect(cmd.solid.color.a == underline_color.a or cmd.solid.color.a == glyph_color.a);
            if (cmd.solid.color.b == 255) {
                try std.testing.expectEqual(underline_color, cmd.solid.color);
            } else {
                try std.testing.expectEqual(glyph_color, cmd.solid.color);
            }
        }
        for (snap.glyphs[row]) |cmd| switch (cmd) {
            .alpha_mask => |mask| {
                try std.testing.expectEqual(glyph_color, mask.color);
                if (row >= 4) fractional_ink += 1;
            },
            .rgba => |image| {
                colour_count += 1;
                if (row >= 2 and row < 4) {
                    const original = snap.glyphs[row - 2][snap.glyphs[row - 2].len - 1];
                    try std.testing.expectEqualDeep(original.rgba, image);
                }
                if (row >= 4) fractional_ink += 1;
            },
            else => return error.UnexpectedCommand,
        };
    }
    try std.testing.expect(colour_count >= 5 and fractional_ink >= 2);
}

test "DECCARA lead-only rendition repairs every scaled ink strip without mutating continuations" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(4, 8);
    try owner.feed("\x1b[?25l\x1b[32m\x1b]66;s=2;█\x07\x1b[2*x");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const first = held.?.snapshot;
    const initial_view = owner.observation().semanticView(0);
    const lower = initial_view.cellInfoAt(1, 0);
    const untouched = initial_view.rowGeneration(2);
    const lower_bg = initial_view.rowBackgroundGeneration(1);
    try std.testing.expectEqual(@as(usize, 1), first.glyphs[0].len);
    try std.testing.expectEqual(@as(usize, 1), first.glyphs[1].len);
    const old = try a.dupe(output.commands.Command, first.glyphs[1]);
    defer a.free(old);
    try owner.feed("\x1b[1;1;1;1;38:6:255:0:0:128;4;5$r");
    try owner.flush();
    try std.testing.expectEqualSlices(output.commands.Command, old, first.glyphs[1]);
    const old_lower_generation = first.row_generations[1];
    try owner.release(held.?);
    held = null;
    {
        const next = try owner.hold();
        defer release(owner, next);
        const s = next.snapshot;
        const view = owner.observation().semanticView(0);
        try std.testing.expectEqualDeep(lower, view.cellInfoAt(1, 0));
        try std.testing.expectEqual(untouched, view.rowGeneration(2));
        try std.testing.expectEqual(lower_bg, view.rowBackgroundGeneration(1));
        try std.testing.expect(s.row_generations[1] != old_lower_generation);
        for (0..2) |row| {
            try std.testing.expectEqual(@as(usize, 1), s.glyphs[row].len);
            try std.testing.expectEqual(output.commands.Color{ .r = 255, .g = 0, .b = 0, .a = 128 }, s.glyphs[row][0].alpha_mask.color);
            try std.testing.expect(s.glyphs[row][0].alpha_mask.blink);
        }
        try std.testing.expectEqual(@as(usize, 1), s.decorations[1].len);
        try std.testing.expectEqual(s.glyphs[1][0].alpha_mask.color, s.decorations[1][0].solid.color);
        try std.testing.expect(s.decorations[1][0].solid.blink);
    }
    try owner.feed("\x1b[1;1;1;1;8$r");
    try owner.flush();
    const hidden = try owner.hold();
    defer release(owner, hidden);
    for (0..2) |row| {
        try std.testing.expectEqual(@as(usize, 0), hidden.snapshot.glyphs[row].len);
        try std.testing.expectEqual(@as(usize, 0), hidden.snapshot.decorations[row].len);
    }
    try std.testing.expectEqualDeep(lower, owner.observation().semanticView(0).cellInfoAt(1, 0));
}

test "DECCARA continuation background remains independent across history lead eviction" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 1 });
    defer destroy(owner);
    try owner.resize(4, 8);
    try owner.feed("\x1b[?25l\x1b[38:6:10:20:30:128;4m\x1b]66;s=2;█\x07\x1b[S\x1b[2*x");
    owner.selectHistoryOffset(1);
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const before = held.?.snapshot;
    const old_view = owner.observation().semanticView(1);
    const lead = old_view.cellInfoAt(0, 0);
    const lower = old_view.cellInfoAt(1, 0);
    try std.testing.expectEqual(@as(u8, 0), lead.y);
    try std.testing.expectEqual(@as(u8, 1), lower.y);
    const lower_ink = before.glyphs[1][0];
    const lower_deco = before.decorations[1][0];
    const old_lead_generation = before.row_generations[0];
    const old_lower_generation = before.row_generations[1];
    try owner.feed("\x1b[1;2;1;2;38:6:255:0:0:0;48:6:0:255:0:64;8;24$r");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 0), before.backgrounds[1].len);
    try std.testing.expectEqualDeep(lower_ink, before.glyphs[1][0]);
    try owner.release(held.?);
    held = null;
    var styled = lower;
    {
        const next = try owner.hold();
        defer release(owner, next);
        const s = next.snapshot;
        const view = owner.observation().semanticView(1);
        try std.testing.expectEqualDeep(lead, view.cellInfoAt(0, 0));
        try std.testing.expectEqualDeep(lower, view.cellInfoAt(1, 0));
        styled = view.cellInfoAt(1, 1);
        try std.testing.expectEqual(@as(u8, 1), styled.x);
        try std.testing.expectEqual(@as(u8, 1), styled.y);
        try std.testing.expectEqual(@as(u32, 0x4000ff00), styled.attrs.bg.value);
        try std.testing.expectEqual(@as(u32, 0x00ff0000), styled.attrs.fg.value);
        try std.testing.expect(styled.attrs.invisible and !styled.attrs.underline);
        try std.testing.expectEqual(old_lead_generation, s.row_generations[0]);
        try std.testing.expect(old_lower_generation != s.row_generations[1]);
        try std.testing.expectEqualDeep(lower_ink, s.glyphs[1][0]);
        try std.testing.expectEqualDeep(lower_deco, s.decorations[1][0]);
        try std.testing.expectEqual(@as(usize, 1), s.backgrounds[1].len);
        const bg = s.backgrounds[1][0].solid;
        try std.testing.expectEqual(output.commands.Color{ .r = 0, .g = 255, .b = 0, .a = 64 }, bg.color);
        try std.testing.expectEqual(@as(i32, s.cell_width), bg.rect.x);
        try std.testing.expectEqual(s.cell_width, bg.rect.width);
    }
    // The one-row history capacity retires the lead, but must retain
    // the individually edited lower background without orphaned glyph ink.
    try owner.feed("\x1b[S");
    owner.selectHistoryOffset(1);
    try owner.flush();
    const evicted = try owner.hold();
    defer release(owner, evicted);
    try std.testing.expectEqualDeep(styled, owner.observation().semanticView(1).cellInfoAt(0, 1));
    try std.testing.expectEqual(@as(usize, 0), evicted.snapshot.glyphs[0].len);
    try std.testing.expectEqual(@as(usize, 0), evicted.snapshot.decorations[0].len);
    try std.testing.expectEqual(@as(usize, 1), evicted.snapshot.backgrounds[0].len);
    try std.testing.expectEqual(output.commands.Color{ .r = 0, .g = 255, .b = 0, .a = 64 }, evicted.snapshot.backgrounds[0][0].solid.color);
}

test "Mintty baseline presentation shrinks generated and font ink without changing occupancy" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(5, 8);
    try owner.feed("\x1b[?25l█A\r\n\x1b[73m█A\r\n\x1b[75;73;74m█A\r\n\x1b[75;74m█A\r\n\x1b[75;74;73m█A");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const s = held.snapshot;
    const metrics = f.metrics();
    const width: u16 = @intCast((@as(u32, s.cell_width) * 3 + 4) / 5);
    const height: u16 = @intCast((@as(u32, s.cell_height) * 3 + 4) / 5);
    const small_baseline: u16 = @intCast(@as(u32, metrics.baseline) * 3 / 5);
    const offsets = [_]u16{ @min(s.cell_height / 8, s.cell_height - height), @min(metrics.baseline - small_baseline, s.cell_height - height), @min(@as(u16, @intCast(@as(u32, s.cell_height) * 13 / 32)), s.cell_height - height) };
    try std.testing.expect(offsets[0] < offsets[1] and offsets[1] < offsets[2]);
    const original = s.glyphs[0][1].alpha_mask;
    const view = owner.observation().semanticView(0);
    for (0..5) |row| {
        try std.testing.expectEqual(@as(usize, 2), s.glyphs[row].len);
        const block = s.glyphs[row][0].alpha_mask;
        const ink = s.glyphs[row][1].alpha_mask;
        try std.testing.expectEqualDeep(original.resource.source, ink.resource.source);
        try std.testing.expectEqual(@as(u16, if (row == 0) s.cell_width else width), block.destination.width);
        try std.testing.expectEqual(@as(u16, if (row == 0) s.cell_height else height), block.destination.height);
        if (row != 0) {
            try std.testing.expectEqual(@as(i32, offsets[if (row == 4) 1 else row - 1]), block.destination.y);
            try std.testing.expectEqual(@as(u16, @intCast((@as(u32, original.destination.width) * 3 + 4) / 5)), ink.destination.width);
            try std.testing.expectEqual(@as(u16, @intCast((@as(u32, original.destination.height) * 3 + 4) / 5)), ink.destination.height);
            try std.testing.expect(ink.clip.x >= s.cell_width and ink.clip.x + @as(i32, ink.clip.width) <= @as(i32, s.cell_width) * 2);
            try std.testing.expect(ink.clip.y >= 0 and ink.clip.y + @as(i32, ink.clip.height) <= s.cell_height);
        }
        for (0..2) |col| {
            const cell = view.cellInfoAt(@intCast(row), @intCast(col));
            try std.testing.expectEqual(@as(u8, 1), cell.width);
            try std.testing.expectEqual(@as(u8, 1), cell.height);
            try std.testing.expectEqual(@as(u4, 0), cell.subscale_d);
        }
    }
    try std.testing.expectEqualSlices(output.commands.Command, s.glyphs[2], s.glyphs[4]);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_col);
}

test "Mintty script ink composes with sized text and survives the retained history boundary" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(4, 8);
    try owner.feed("\x1b[?25l\x1b[73;74;4;38:6:10:20:30:128m\x1b]66;s=2;█\x07\x1b[3;1H\x1b]66;s=2:n=1:d=2;█\x07");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const s = held.?.snapshot;
    const view = owner.observation().semanticView(0);
    const expected_counts = [_]usize{ 1, 1, 1, 0 };
    for (expected_counts, 0..) |count, row| {
        try std.testing.expectEqual(count, s.glyphs[row].len);
        for (0..2) |col| {
            const cell = view.cellInfoAt(@intCast(row), @intCast(col));
            try std.testing.expectEqual(@as(u8, 2), cell.width);
            try std.testing.expectEqual(@as(u8, 2), cell.height);
            try std.testing.expectEqual(@as(u8, @intCast(row % 2)), cell.y);
            try std.testing.expectEqual(@as(u8, @intCast(col)), cell.x);
            try std.testing.expect(cell.attrs.baseline == .small);
        }
    }
    const upper = s.glyphs[0][0].alpha_mask;
    const lower = s.glyphs[1][0].alpha_mask;
    const fractional = s.glyphs[2][0].alpha_mask;
    try std.testing.expectEqualDeep(upper.resource, lower.resource);
    try std.testing.expectEqual(upper.destination.y, lower.destination.y + s.cell_height);
    try std.testing.expectEqual(@as(u16, @intCast((@as(u32, s.cell_width) * 6 + 4) / 5)), upper.destination.width);
    try std.testing.expectEqual(@as(u16, @intCast((@as(u32, s.cell_height) * 6 + 4) / 5)), upper.destination.height);
    try std.testing.expectEqual(@as(u16, @intCast((@as(u32, s.cell_width) * 3 + 4) / 5)), fractional.destination.width);
    try std.testing.expectEqual(@as(u16, @intCast((@as(u32, s.cell_height) * 3 + 4) / 5)), fractional.destination.height);
    for ([_]output.commands.Color{ upper.color, lower.color, fractional.color }) |color|
        try std.testing.expectEqual(output.commands.Color{ .r = 10, .g = 20, .b = 30, .a = 128 }, color);
    var copied: [3]output.commands.Command = undefined;
    for (&copied, 0..) |*command, row| command.* = s.glyphs[row][0];
    try owner.feed("\x1b[2S");
    owner.selectHistoryOffset(2);
    try owner.flush();
    for (copied, 0..) |command, row| try std.testing.expectEqualDeep(command, s.glyphs[row][0]);
    try owner.release(held.?);
    held = null;
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectEqual(@as(u32, 2), next.snapshot.history_offset);
    for (expected_counts, 0..) |count, row| {
        try std.testing.expectEqual(count, next.snapshot.glyphs[row].len);
        if (count != 0) try std.testing.expectEqualDeep(copied[row], next.snapshot.glyphs[row][0]);
        try std.testing.expect(owner.observation().semanticView(2).cellInfoAt(@intCast(row), 0).attrs.baseline == .small);
    }
}

test "Mintty shadow uses retained ink resources and clipped ordered layers" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(3, 8);
    try owner.feed("\x1b[?25l\x1b]11;#143c64\x07\x1b[38:6:200:40:20:128;58:2:80:100:120;4mA\r\n\x1b[1:2mA\r\n\x1b[22mA");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const snap = held.snapshot;
    try std.testing.expectEqual(@as(usize, 1), snap.glyphs[0].len);
    try std.testing.expectEqual(@as(usize, 2), snap.glyphs[1].len);
    try std.testing.expectEqual(@as(usize, 1), snap.glyphs[2].len);
    const original = snap.glyphs[0][0].alpha_mask;
    const shadow = snap.glyphs[1][0].alpha_mask;
    const primary = snap.glyphs[1][1].alpha_mask;
    const shift: i32 = @max(1, @divTrunc(@as(i32, snap.cell_height) * 3, 40));
    try std.testing.expectEqualDeep(original.resource, primary.resource);
    try std.testing.expectEqualDeep(primary.resource, shadow.resource);
    try std.testing.expectEqualDeep(original.destination, primary.destination);
    try std.testing.expectEqual(primary.destination.x + shift, shadow.destination.x);
    try std.testing.expectEqual(primary.destination.y - shift, shadow.destination.y);
    try std.testing.expectEqual(output.commands.Color{ .r = 110, .g = 50, .b = 60, .a = 128 }, shadow.color);
    try std.testing.expectEqual(original.color, primary.color);
    try std.testing.expect(!shadow.cursor_component and primary.cursor_component);
    try std.testing.expect(shadow.clip.x >= 0 and shadow.clip.x + @as(i32, shadow.clip.width) <= snap.cell_width);
    try std.testing.expect(shadow.clip.y >= 0 and shadow.clip.y + @as(i32, shadow.clip.height) <= snap.cell_height);
    try std.testing.expectEqual(@as(usize, 2), snap.decorations[1].len);
    try std.testing.expectEqual(output.commands.Color{ .r = 50, .g = 80, .b = 110, .a = 255 }, snap.decorations[1][0].solid.color);
    try std.testing.expectEqual(snap.decorations[0][0].solid.color, snap.decorations[1][1].solid.color);
    try std.testing.expectEqual(snap.glyphs[0][0], snap.glyphs[2][0]);
}

test "Mintty shadow composes with script sizing and blink but leaves intrinsic images single" {
    const fonts = @import("test_fonts");
    const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &.{fonts.colour_font}, .size = .{ .pixels = 20 } });
    defer f.deinit();
    const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 }, .history_capacity = 8 });
    defer destroy(owner);
    try owner.resize(4, 8);
    try owner.feed("\x1b[?25l\x1b]11;#000000\x07\x1b[1:2;2;5;73;74;38:6:200:40:20:128m\x1b]66;s=2;█\x07\x1b[1;4H😀\x1b[3;4H\x1b[22m😀");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const s = held.snapshot;
    for (0..2) |row| {
        const glyphs = s.glyphs[row];
        try std.testing.expectEqual(@as(usize, if (row == 0) 3 else 2), glyphs.len);
        const shadow = glyphs[0].alpha_mask;
        const primary = glyphs[1].alpha_mask;
        try std.testing.expectEqualDeep(primary.resource, shadow.resource);
        try std.testing.expectEqual(output.commands.Color{ .r = 100, .g = 20, .b = 10, .a = 70 }, shadow.color);
        try std.testing.expectEqual(output.commands.Color{ .r = 200, .g = 40, .b = 20, .a = 70 }, primary.color);
        try std.testing.expect(shadow.blink and primary.blink);
        try std.testing.expect(!shadow.cursor_component and primary.cursor_component);
        try std.testing.expect(shadow.clip.x >= 0 and shadow.clip.x + @as(i32, shadow.clip.width) <= @as(i32, s.cell_width) * 2);
        try std.testing.expect(shadow.clip.y >= 0 and shadow.clip.y + @as(i32, shadow.clip.height) <= s.cell_height);
    }
    try std.testing.expectEqual(@as(usize, 1), s.glyphs[2].len);
    try std.testing.expectEqualDeep(s.glyphs[0][2], s.glyphs[2][0]);
}

test "ECMA rectangle and ellipse enclosures retain distinct ink without forcing emoji" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(4, 8);
    try owner.feed("\x1b[?25l\x1b[38:6:100:120:140:128m1\r\n\x1b[51m1\r\n\x1b[52m1\r\n\x1b[54m1");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const s = held.snapshot;
    for (0..4) |row| {
        try std.testing.expectEqual(@as(usize, 1), s.glyphs[row].len);
        try std.testing.expectEqualDeep(s.glyphs[0][0], s.glyphs[row][0]);
    }
    try std.testing.expectEqual(@as(usize, 0), s.decorations[0].len);
    try std.testing.expectEqual(@as(usize, 4), s.decorations[1].len);
    try std.testing.expectEqual(@as(usize, 1), s.decorations[2].len);
    try std.testing.expectEqual(@as(usize, 0), s.decorations[3].len);
    const color: output.commands.Color = .{ .r = 100, .g = 120, .b = 140, .a = 128 };
    var area: usize = 0;
    for (s.decorations[1], 0..) |cmd, i| {
        try std.testing.expect(cmd == .solid);
        try std.testing.expectEqual(color, cmd.solid.color);
        const rect = cmd.solid.rect;
        area += @as(usize, rect.width) * rect.height;
        for (s.decorations[1][0..i]) |previous|
            try std.testing.expect((try output.commands.intersectRects(rect, previous.solid.rect)) == null);
    }
    const ring = s.decorations[2][0].alpha_mask;
    try std.testing.expectEqual(color, ring.color);
    try std.testing.expect(!ring.cursor_component);
    const source = ring.resource.source.?;
    const center = (@as(usize, source.y) + source.height / 2) * s.atlas_width + source.x + source.width / 2;
    try std.testing.expectEqual(@as(u8, 0), s.atlas_pixels[center]);
    const north = @as(usize, source.y) * s.atlas_width + source.x + source.width / 2;
    try std.testing.expect(s.atlas_pixels[north] != 0);
    const corner = @as(usize, source.y) * s.atlas_width + source.x;
    try std.testing.expectEqual(@as(u8, 0), s.atlas_pixels[corner]);
    try std.testing.expect(area > 0 and area < @as(usize, s.cell_width) * s.cell_height);
}

test "ECMA enclosures preserve text and emoji variation choice in both fallback orders" {
    const fonts = @import("test_fonts");
    for ([_]bool{ false, true }) |colour_first| {
        const fallbacks = if (colour_first)
            [_][]const u8{ fonts.colour_font, fonts.symbol_font }
        else
            [_][]const u8{ fonts.symbol_font, fonts.colour_font };
        const f = try text.FontSet.init(a, .{ .primary = fonts.primary_font, .fallbacks = &fallbacks, .size = .{ .pixels = 20 } });
        defer f.deinit();
        const owner = try output.Terminal.initConfig(a, f, .{ .atlas = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 } });
        defer destroy(owner);
        try owner.resize(3, 12);
        try owner.feed("\x1b[?25l\x1b[?2027h☺\u{fe0e}☺\u{fe0f}☺\r\n\x1b[51m☺\u{fe0e}☺\u{fe0f}☺\r\n\x1b[52m☺\u{fe0e}☺\u{fe0f}☺");
        try owner.flush();
        const held = try owner.hold();
        defer release(owner, held);
        const s = held.snapshot;
        for (0..3) |row| {
            try std.testing.expectEqual(@as(usize, 3), s.glyphs[row].len);
            try std.testing.expect(s.glyphs[row][0] == .alpha_mask);
            try std.testing.expect(s.glyphs[row][1] == .rgba);
            try std.testing.expectEqual(colour_first, s.glyphs[row][2] == .rgba);
            try std.testing.expectEqualSlices(output.commands.Command, s.glyphs[0], s.glyphs[row]);
        }
        try std.testing.expectEqual(@as(usize, 12), s.decorations[1].len);
        try std.testing.expectEqual(@as(usize, 3), s.decorations[2].len);
    }
}

test "ECMA tiny and sized enclosure geometry stays bounded through history" {
    for ([_]u16{ 4, 6, 20 }) |pixels| {
        const f = try font(pixels);
        defer f.deinit();
        const owner = try output.Terminal.initConfig(a, f, .{ .history_capacity = 8 });
        defer destroy(owner);
        try owner.resize(4, 8);
        try owner.feed("\x1b[?25l\x1b[51;73;74;5m\x1b]66;s=2;█\x07\x1b[3;1H\x1b[52m\x1b]66;s=2:n=1:d=2;█\x07");
        try owner.flush();
        var held: ?output.Lease = try owner.hold();
        defer if (held) |lease| release(owner, lease);
        const s = held.?.snapshot;
        var saved: [4][]output.commands.Command = undefined;
        var initialized: usize = 0;
        defer for (saved[0..initialized]) |row| a.free(row);
        for (0..4) |row| {
            const commands = s.decorations[row];
            saved[row] = try a.dupe(output.commands.Command, commands);
            initialized += 1;
            try std.testing.expectEqual(commands.len != 0, s.text_blink_rows[row]);
            for (commands, 0..) |cmd, index| {
                const rect = switch (cmd) {
                    .solid => |v| v.rect,
                    .alpha_mask => |v| v.clip,
                    else => return error.UnexpectedDecoration,
                };
                try std.testing.expect(rect.width > 0 and rect.height > 0);
                try std.testing.expect(rect.x >= 0 and rect.x + @as(i32, rect.width) <= @as(i32, s.cell_width) * 2);
                try std.testing.expect(rect.y >= 0 and rect.y + @as(i32, rect.height) <= s.cell_height);
                try std.testing.expect(output.commands.blinks(cmd));
                if (cmd == .solid) for (commands[0..index]) |earlier|
                    try std.testing.expect((try output.commands.intersectRects(rect, earlier.solid.rect)) == null);
            }
        }
        try std.testing.expect(saved[0].len + saved[1].len > 0);
        try std.testing.expect(saved[2].len + saved[3].len > 0);
        try owner.feed("\x1b[2S");
        owner.selectHistoryOffset(2);
        try owner.flush();
        for (saved, 0..) |row, i| try std.testing.expectEqualSlices(output.commands.Command, row, s.decorations[i]);
        try owner.release(held.?);
        held = null;
        const next = try owner.hold();
        defer release(owner, next);
        for (saved, 0..) |row, i| try std.testing.expectEqualSlices(output.commands.Command, row, next.snapshot.decorations[i]);
    }
}

test "ECMA blank enclosure is blink ink without manufacturing a glyph" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(2, 8);
    try owner.feed("\x1b[?25l\x1b[51;5m \x1b[2*x\x1b[1;3;1;3;52;5$r");
    const start = owner.serviceAnimations(0);
    try std.testing.expectEqual(@as(?u32, 500), start.next_ms);
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const s = held.?.snapshot;
    try std.testing.expect(s.text_blink_rows[0] and s.text_blink_visible);
    try std.testing.expectEqual(@as(usize, 0), s.glyphs[0].len);
    try std.testing.expectEqual(@as(usize, 5), s.decorations[0].len);
    for (s.decorations[0]) |cmd| try std.testing.expect(output.commands.blinks(cmd));
    const step = owner.serviceAnimations(500 * std.time.ns_per_ms);
    try std.testing.expect(step.changed);
    try owner.flush();
    try std.testing.expect(s.text_blink_visible);
    try owner.release(held.?);
    held = null;
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expect(!next.snapshot.text_blink_visible);
}

test "contextual operator joining cannot consume independently shadowed ink" {
    const f = try font(20);
    defer f.deinit();
    const owner = try output.Terminal.init(a, f);
    defer destroy(owner);
    try owner.resize(2, 8);
    try owner.feed("\x1b[?25l=\x1b[1:2m=");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    try std.testing.expectEqual(@as(usize, 3), held.snapshot.glyphs[0].len);
    try std.testing.expect(!held.snapshot.glyphs[0][1].alpha_mask.cursor_component);
}

test "Kitty chunked image replacement preserves a held resource through rejection and commit" {
    const f = try font(20);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,i=56,p=7,C=1,q=2,s=1,v=1;/wAA/w==\x1b\\");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const before = held.?.snapshot;
    const resource = before.graphics.images[0].resource;
    const command = before.graphics.positive[0];
    try owner.feed("\x1b_Ga=t,i=56,q=2,s=1,v=1,m=1;AAD/\x1b\\");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, owner.observation().images(0).image(0).?.pixels);
    try owner.feed("\x1b_Gm=0;A\x1b\\");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, owner.observation().images(0).image(0).?.pixels);
    try owner.feed("\x1b_Ga=t,i=56,q=2,s=1,v=1,m=1;AAD/\x1b\\\x1b_Gm=0;/w==\x1b\\");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, before.graphics.images[0].pixels);
    try std.testing.expectEqualDeep(resource, before.graphics.images[0].resource);
    try std.testing.expectEqualDeep(command, before.graphics.positive[0]);
    try owner.release(held.?);
    held = null;
    {
        const unplaced = try owner.hold();
        defer release(owner, unplaced);
        try std.testing.expectEqual(@as(usize, 0), unplaced.snapshot.graphics.images.len);
        try std.testing.expectEqual(@as(usize, 0), unplaced.snapshot.graphics.positive.len);
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, owner.observation().images(0).image(0).?.pixels);
    }
    try owner.feed("\x1b_Ga=p,i=56,p=7,C=1,q=2\x1b\\");
    try owner.flush();
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectEqual(@as(usize, 1), next.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), next.snapshot.graphics.positive.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, next.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqual(resource.resource, next.snapshot.graphics.images[0].resource.resource);
    try std.testing.expect(@backingInt(next.snapshot.graphics.images[0].resource.generation) > @backingInt(resource.generation));
}

test "Kitty equal z order follows stable image identity after re-put and replacement" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    // Pinned Kitty compares internal image IDs, not client IDs or put time.
    try owner.feed(
        "\x1b_Ga=t,i=90,s=1,v=1,q=2;/wAA/w==\x1b\\" ++
            "\x1b_Ga=T,i=12,p=1,s=1,v=1,C=1,q=2;AP8A/w==\x1b\\" ++
            "\x1b_Ga=p,i=90,p=1,C=1,q=2\x1b\\",
    );
    try owner.flush();
    {
        const held = try owner.hold();
        defer release(owner, held);
        const scene = held.snapshot.graphics;
        try std.testing.expectEqual(@as(usize, 2), scene.positive.len);
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, scene.images[0].pixels);
        try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, scene.images[1].pixels);
        try std.testing.expectEqualDeep(scene.images[0].resource, scene.positive[0].rgba.resource.resource);
        try std.testing.expectEqualDeep(scene.images[1].resource, scene.positive[1].rgba.resource.resource);
    }
    try owner.feed("\x1b_Ga=T,i=90,p=1,s=1,v=1,C=1,q=2;AAD//w==\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    defer release(owner, held);
    const scene = held.snapshot.graphics;
    try std.testing.expectEqual(@as(usize, 2), scene.positive.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, scene.images[0].pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, scene.images[1].pixels);
    try std.testing.expectEqualDeep(scene.images[0].resource, scene.positive[0].rgba.resource.resource);
    try std.testing.expectEqualDeep(scene.images[1].resource, scene.positive[1].rgba.resource.resource);
}

test "Kitty same client ID in another bank preserves held output and clears only alternate resources" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.feed("\x1b_Ga=T,i=56,p=7,C=1,q=2,s=1,v=1;/wAA/w==\x1b\\");
    try owner.flush();
    var held: ?output.Lease = try owner.hold();
    defer if (held) |lease| release(owner, lease);
    const before = held.?.snapshot;
    const resource = before.graphics.images[0].resource;
    const command = before.graphics.positive[0];
    const primary_id = owner.observation().images(0).image(0).?.id;
    const primary_generation = owner.observation().images(0).image(0).?.generation;
    try owner.feed("\x1b[?47h\x1b_Ga=T,i=56,p=7,C=1,q=2,s=1,v=1;AAD//w==\x1b\\");
    try owner.flush();
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, before.graphics.images[0].pixels);
    try std.testing.expectEqualDeep(resource, before.graphics.images[0].resource);
    try std.testing.expectEqualDeep(command, before.graphics.positive[0]);
    try owner.release(held.?);
    held = null;
    {
        const alternate = try owner.hold();
        defer release(owner, alternate);
        try std.testing.expect(alternate.snapshot.alternate);
        try std.testing.expectEqual(@as(usize, 1), alternate.snapshot.graphics.images.len);
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, alternate.snapshot.graphics.images[0].pixels);
        const observed = owner.observation().images(0);
        try std.testing.expectEqual(@as(usize, 2), observed.imageCount());
        try std.testing.expect(observed.image(1).?.id != primary_id);
        try std.testing.expectEqual(observed.image(1).?.id, observed.placement(1).?.image_id);
        // Resource slots belong to a cut, not to canonical image IDs.
        try std.testing.expect(@backingInt(alternate.snapshot.graphics.images[0].resource.generation) > @backingInt(resource.generation));
        try std.testing.expectEqualDeep(alternate.snapshot.graphics.images[0].resource, alternate.snapshot.graphics.positive[0].rgba.resource.resource);
    }
    try owner.feed("\x1b[?47l\x1b[?1049h");
    try owner.flush();
    {
        const cleared = try owner.hold();
        defer release(owner, cleared);
        try std.testing.expectEqual(@as(usize, 0), cleared.snapshot.graphics.images.len);
        try std.testing.expectEqual(@as(usize, 1), owner.observation().images(0).imageCount());
    }
    try owner.feed("\x1b[?1049l");
    try owner.flush();
    const returned = try owner.hold();
    defer release(owner, returned);
    try std.testing.expect(!returned.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 1), returned.snapshot.graphics.images.len);
    const observed = owner.observation().images(0);
    try std.testing.expectEqual(primary_id, observed.image(0).?.id);
    try std.testing.expectEqual(primary_generation, observed.image(0).?.generation);
    try std.testing.expectEqual(primary_id, observed.placement(0).?.image_id);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, returned.snapshot.graphics.images[0].pixels);
    var expected = command;
    expected.rgba.resource.resource = returned.snapshot.graphics.images[0].resource;
    try std.testing.expectEqualDeep(expected, returned.snapshot.graphics.positive[0]);
}

test "Kitty centered fit reaches direct output and preserves a held cut across re-put" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.resize(8, 8);
    try owner.feed("\x1b[H\x1b_Ga=T,i=7,p=1,s=1,v=1,c=4,r=1,C=1,q=2;/wAA/w==\x1b\\");
    try owner.flush();
    const held = try owner.hold();
    var holding = true;
    defer if (holding) release(owner, held);
    const metrics = owner.acceptedMetrics().?;
    const first = held.snapshot.graphics.positive[0].rgba;
    const wide_side = @min(metrics.cell_width * 4, metrics.cell_height);
    try std.testing.expectEqualDeep(output.commands.Rect{
        .x = @intCast((metrics.cell_width * 4 - wide_side) / 2),
        .y = @intCast((metrics.cell_height - wide_side) / 2),
        .width = wide_side,
        .height = wide_side,
    }, first.destination);
    const image_generation = owner.observation().images(0).image(0).?.generation;
    try owner.feed("\x1b[H\x1b_Ga=p,i=7,p=1,c=1,r=4,C=1,q=2\x1b\\");
    try owner.flush();
    try std.testing.expectEqualDeep(first, held.snapshot.graphics.positive[0].rgba);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, held.snapshot.graphics.images[0].pixels);
    release(owner, held);
    holding = false;
    const fitted = try owner.hold();
    defer release(owner, fitted);
    const tall_side = @min(metrics.cell_width, metrics.cell_height * 4);
    try std.testing.expectEqual(@as(usize, 1), fitted.snapshot.graphics.positive.len);
    try std.testing.expectEqualDeep(output.commands.Rect{
        .x = @intCast((metrics.cell_width - tall_side) / 2),
        .y = @intCast((metrics.cell_height * 4 - tall_side) / 2),
        .width = tall_side,
        .height = tall_side,
    }, fitted.snapshot.graphics.positive[0].rgba.destination);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, fitted.snapshot.graphics.images[0].pixels);
    try std.testing.expectEqual(image_generation, owner.observation().images(0).image(0).?.generation);
}

test "iTerm2 inline PNG uses native graphics output and survives held-cut retirement" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    try owner.feed("\x1b[H\x1b]1337;File=inline=1:" ++ png ++ "\x07");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.positive.len);
    const original = held.snapshot.graphics.positive[0].rgba;
    try std.testing.expectEqualDeep(output.commands.Rect{ .x = 0, .y = 0, .width = 2, .height = 1 }, original.destination);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, held.snapshot.graphics.images[0].pixels);
    // Kitty selectors cannot acquire an unrelated decoded image.
    try owner.feed("\x1b_Ga=d,d=A,q=2\x1b\\");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 1), owner.observation().images(0).placementCount());
    try owner.feed("\x1b[2J");
    try owner.flush();
    try std.testing.expectEqualDeep(original, held.snapshot.graphics.positive[0].rgba);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, held.snapshot.graphics.images[0].pixels);
    release(owner, held);
    pinned = false;
    const cleared = try owner.hold();
    defer release(owner, cleared);
    try std.testing.expectEqual(@as(usize, 0), cleared.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), cleared.snapshot.graphics.positive.len);
}

test "iTerm2 sized inline output preserves source pixels and top-left fit across held publication" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    try owner.resize(8, 8);
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    try owner.feed("\x1b[H\x1b]1337;File=inline=1;width=6px;height=15px:" ++ png ++ "\x07");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.positive.len);
    const original = held.snapshot.graphics.positive[0].rgba;
    try std.testing.expectEqualDeep(output.commands.Rect{ .x = 0, .y = 0, .width = 6, .height = 3 }, original.destination);
    try std.testing.expectEqualDeep(output.commands.SourceRect{ .x = 0, .y = 0, .width = 2, .height = 1 }, original.resource.source.?);
    const metrics = owner.acceptedMetrics().?;
    try owner.feed("\x1b[3;3H\x1b]1337;File=inline=1;width=6px;height=15px;preserveAspectRatio=0:" ++ png ++ "\x1b\\");
    try owner.flush();
    try std.testing.expectEqualDeep(original, held.snapshot.graphics.positive[0].rgba);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, held.snapshot.graphics.images[0].pixels);
    release(owner, held);
    pinned = false;
    const next = try owner.hold();
    defer release(owner, next);
    try std.testing.expectEqual(@as(usize, 2), next.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 2), next.snapshot.graphics.positive.len);
    const stretched = next.snapshot.graphics.positive[1].rgba;
    try std.testing.expectEqualDeep(output.commands.Rect{
        .x = 2 * @as(i32, metrics.cell_width),
        .y = 2 * @as(i32, metrics.cell_height),
        .width = 6,
        .height = 15,
    }, stretched.destination);
    try std.testing.expectEqualDeep(original.resource.source, stretched.resource.source);
    try std.testing.expectEqualSlices(u8, next.snapshot.graphics.images[0].pixels, next.snapshot.graphics.images[1].pixels);
    try std.testing.expect(next.snapshot.graphics.images[0].resource.resource != next.snapshot.graphics.images[1].resource.resource);
}

test "iTerm2 multipart publishes one immutable image cut only after FileEnd" {
    const f = try font(12);
    defer f.deinit();
    const owner = try ready(a, f);
    defer destroy(owner);
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const start = "\x1b]1337;MultipartFile=inline=1;width=6px;height=15px\x07";
    try owner.feed("\x1b[H" ++ start ++ "\x1b]1337;FilePart=" ++ sample[0..47] ++ "\x07");
    try owner.flush();
    const held = try owner.hold();
    var pinned = true;
    defer if (pinned) release(owner, held);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try owner.feed("\x1b]1337;FilePart=" ++ sample[47..] ++ "\x1b\\");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 0), owner.observation().images(0).imageCount());
    try owner.feed("\x1b]1337;FileEnd\x07");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), owner.observation().images(0).imageCount());
    release(owner, held);
    pinned = false;
    const complete = try owner.hold();
    defer release(owner, complete);
    try std.testing.expectEqual(@as(usize, 1), complete.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), complete.snapshot.graphics.positive.len);
    try std.testing.expectEqualDeep(output.commands.Rect{ .x = 0, .y = 0, .width = 6, .height = 3 }, complete.snapshot.graphics.positive[0].rgba.destination);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, complete.snapshot.graphics.images[0].pixels);
    try owner.feed("\x1b]1337;FileEnd\x07\x1b[2J");
    try owner.flush();
    try std.testing.expectEqual(@as(usize, 1), complete.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), owner.observation().images(0).placementCount());
}
