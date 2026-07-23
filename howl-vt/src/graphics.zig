//! Owns bounded static terminal image data and ordinary cell-relative placements.

const std = @import("std");

/// Bounds decoded image bytes retained by one terminal.
pub const max_storage_bytes: usize = 64 * 1024 * 1024;
/// Bounds one decoded RGBA image.
pub const max_image_bytes: usize = 16 * 1024 * 1024;
/// Bounds retained image identities.
pub const max_images: usize = 256;
/// Bounds retained image placements.
pub const max_placements: usize = 1024;
/// Bounds either image dimension before byte-count validation.
pub const max_dimension: u32 = 4096;
/// Bounds one encoded Kitty APC command chunk.
pub const max_command_bytes: usize = 8192;

/// Identifies the screen bank owning one placement.
pub const Bank = enum { primary, alternate };

/// Borrows immutable decoded RGBA pixels until plane mutation.
pub const ImageView = struct {
    /// Application-selected nonzero Kitty image identity.
    id: u32,
    /// Pixel width.
    width: u32,
    /// Pixel height.
    height: u32,
    /// Monotonic content identity used by retained render storage.
    generation: u64,
    /// Exact row-major RGBA8 pixels.
    pixels: []const u8,
};

/// Copies one ordinary cell-relative placement.
pub const Placement = struct {
    /// Image identity resolved by the plane.
    image_id: u32,
    /// Monotonic placement identity.
    generation: u64,
    /// Screen bank owning this placement.
    bank: Bank,
    /// Primary absolute projected row or alternate screen row.
    row: u64,
    /// Physical terminal column.
    col: u16,
    /// Counts occupied terminal rows at placement time.
    rows: u16,
    /// Counts occupied physical terminal columns at placement time.
    cols: u16,
};

const Image = struct {
    id: u32,
    width: u32,
    height: u32,
    generation: u64,
    pixels: []u8,

    fn view(self: *const Image) ImageView {
        return .{
            .id = self.id,
            .width = self.width,
            .height = self.height,
            .generation = self.generation,
            .pixels = self.pixels,
        };
    }
};

const Loading = struct {
    action: u8,
    format: u8,
    id: u32,
    width: u32,
    height: u32,
    quiet: u2,
    bytes: []u8,
    used: usize = 0,
};

/// Reports exact static Kitty command admission.
pub const Result = struct {
    /// True when retained images or placements changed.
    changed: bool = false,
    /// Image identity echoed by a protocol response.
    response_id: ?u32 = null,
    /// Null identifies success; otherwise supplies Kitty's stable short error.
    failure: ?Failure = null,
    /// Suppresses success or all responses according to `q`.
    quiet: u2 = 0,
};

/// Names one bounded static graphics rejection.
pub const Failure = enum {
    invalid,
    unsupported,
    quota,
    missing,

    /// Returns the Kitty response token.
    pub fn bytes(self: Failure) []const u8 {
        return switch (self) {
            .invalid => "EINVAL",
            .unsupported => "ENOTSUP",
            .quota => "ENOSPC",
            .missing => "ENOENT",
        };
    }
};

const Command = struct {
    action: u8 = 't',
    medium: u8 = 'd',
    format: u8 = 32,
    id: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    more: bool = false,
    quiet: u2 = 0,
    delete: u8 = 0,
    payload: []const u8 = "",
};

/// Owns decoded image bytes, static placements, and one chunked transfer.
pub const Plane = struct {
    allocator: std.mem.Allocator,
    images: [max_images]Image = undefined,
    image_count: u16 = 0,
    placements: [max_placements]Placement = undefined,
    placement_count: u16 = 0,
    storage_bytes: usize = 0,
    next_generation: u64 = 0,
    content_generation: u64 = 0,
    loading: ?Loading = null,

    /// Initializes an empty plane borrowing `allocator` through `deinit`.
    pub fn init(allocator: std.mem.Allocator) Plane {
        return .{ .allocator = allocator };
    }

    /// Releases transfer and retained image allocations.
    pub fn deinit(self: *Plane) void {
        self.cancel();
        for (self.images[0..self.image_count]) |retained| self.allocator.free(retained.pixels);
        self.* = undefined;
    }

    /// Cancels one incomplete transfer without changing retained images.
    pub fn cancel(self: *Plane) void {
        if (self.loading) |loading| self.allocator.free(loading.bytes);
        self.loading = null;
    }

    /// Applies one complete `_G` APC body after the leading `G`.
    ///
    /// Allocation and quota failures preserve all retained images and placements.
    pub fn command(
        self: *Plane,
        bytes: []const u8,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) std.mem.Allocator.Error!Result {
        if (bytes.len > max_command_bytes) return .{ .failure = .quota };
        const command_value = parseCommand(bytes) orelse {
            self.cancel();
            return .{ .failure = .invalid };
        };
        if (command_value.medium != 'd') {
            self.cancel();
            return .{
                .response_id = nonzero(command_value.id),
                .failure = .unsupported,
                .quiet = command_value.quiet,
            };
        }
        return switch (command_value.action) {
            't', 'T', 'q' => try self.transmit(command_value, bank, row, col, cell_width, cell_height),
            'p' => self.put(command_value, bank, row, col, cell_width, cell_height),
            'd' => self.delete(command_value),
            else => .{
                .response_id = nonzero(command_value.id),
                .failure = .unsupported,
                .quiet = command_value.quiet,
            },
        };
    }

    fn transmit(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) std.mem.Allocator.Error!Result {
        if (self.loading == null) {
            if (command_value.id == 0 or command_value.width == 0 or command_value.height == 0 or
                command_value.width > max_dimension or command_value.height > max_dimension or
                (command_value.format != 24 and command_value.format != 32))
                return .{
                    .response_id = nonzero(command_value.id),
                    .failure = .invalid,
                    .quiet = command_value.quiet,
                };
            const channels: usize = if (command_value.format == 24) 3 else 4;
            const pixels = std.math.mul(usize, command_value.width, command_value.height) catch
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
            const rgba_bytes = std.math.mul(usize, pixels, 4) catch
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
            const input_bytes = std.math.mul(usize, pixels, channels) catch
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
            if (rgba_bytes > max_image_bytes)
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
            self.loading = .{
                .action = command_value.action,
                .format = command_value.format,
                .id = command_value.id,
                .width = command_value.width,
                .height = command_value.height,
                .quiet = command_value.quiet,
                .bytes = try self.allocator.alloc(u8, input_bytes),
            };
        } else {
            if (command_value.width != 0 or command_value.height != 0 or command_value.id != 0) {
                self.cancel();
                return self.transmit(command_value, bank, row, col, cell_width, cell_height);
            }
            if (command_value.format != 32 or command_value.action != 't') {
                self.cancel();
                return .{ .failure = .invalid, .quiet = command_value.quiet };
            }
        }

        const loading = &self.loading.?;
        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(command_value.payload) catch {
            self.cancel();
            return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet };
        };
        if (decoded_len > loading.bytes.len - loading.used) {
            const id = loading.id;
            const quiet = loading.quiet;
            self.cancel();
            return .{ .response_id = id, .failure = .quota, .quiet = quiet };
        }
        std.base64.standard.Decoder.decode(
            loading.bytes[loading.used..][0..decoded_len],
            command_value.payload,
        ) catch {
            const id = loading.id;
            const quiet = loading.quiet;
            self.cancel();
            return .{ .response_id = id, .failure = .invalid, .quiet = quiet };
        };
        loading.used += decoded_len;
        if (command_value.more) return .{ .quiet = loading.quiet };
        if (loading.used != loading.bytes.len) {
            const id = loading.id;
            const quiet = loading.quiet;
            self.cancel();
            return .{ .response_id = id, .failure = .invalid, .quiet = quiet };
        }
        return try self.finish(bank, row, col, cell_width, cell_height);
    }

    fn finish(
        self: *Plane,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) std.mem.Allocator.Error!Result {
        const loading = self.loading.?;
        self.loading = null;
        defer self.allocator.free(loading.bytes);
        const rgba_len = @as(usize, loading.width) * loading.height * 4;
        if (loading.action == 'q')
            return .{ .response_id = loading.id, .quiet = loading.quiet };
        const prior_index = self.imageIndex(loading.id);
        const prior_bytes = if (prior_index) |index| self.images[index].pixels.len else 0;
        if (rgba_len > max_storage_bytes - (self.storage_bytes - prior_bytes))
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        if (prior_index == null and self.image_count == max_images)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const display = loading.action == 'T';
        if (display and self.placement_count == max_placements)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const rgba = try self.allocator.alloc(u8, rgba_len);
        errdefer self.allocator.free(rgba);
        if (loading.format == 32) {
            @memcpy(rgba, loading.bytes);
        } else {
            var source: usize = 0;
            var destination: usize = 0;
            while (source < loading.bytes.len) : ({
                source += 3;
                destination += 4;
            }) {
                @memcpy(rgba[destination..][0..3], loading.bytes[source..][0..3]);
                rgba[destination + 3] = 255;
            }
        }
        self.advance();
        const content_generation = self.next_generation;
        self.content_generation = content_generation;
        if (prior_index) |index| {
            self.storage_bytes -= self.images[index].pixels.len;
            self.allocator.free(self.images[index].pixels);
            self.images[index] = .{
                .id = loading.id,
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
            };
        } else {
            self.images[self.image_count] = .{
                .id = loading.id,
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
            };
            self.image_count += 1;
        }
        self.storage_bytes += rgba.len;
        if (display) self.addPlacement(
            loading.id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            loading.width,
            loading.height,
            content_generation,
        );
        return .{
            .changed = true,
            .response_id = loading.id,
            .quiet = loading.quiet,
        };
    }

    fn put(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) Result {
        const image_index = self.imageIndex(command_value.id) orelse
            return .{ .response_id = nonzero(command_value.id), .failure = .missing, .quiet = command_value.quiet };
        if (self.placement_count == max_placements)
            return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
        self.advance();
        const placement_generation = self.next_generation;
        const retained = self.images[image_index];
        self.addPlacement(
            command_value.id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            retained.width,
            retained.height,
            placement_generation,
        );
        return .{ .changed = true, .response_id = command_value.id, .quiet = command_value.quiet };
    }

    fn delete(self: *Plane, command_value: Command) Result {
        if (command_value.delete != 'i' or command_value.id == 0)
            return .{ .response_id = nonzero(command_value.id), .failure = .unsupported, .quiet = command_value.quiet };
        const image_index = self.imageIndex(command_value.id) orelse
            return .{ .response_id = command_value.id, .failure = .missing, .quiet = command_value.quiet };
        self.advance();
        self.content_generation = self.next_generation;
        self.removePlacements(command_value.id);
        const removed = self.images[image_index];
        self.storage_bytes -= removed.pixels.len;
        self.allocator.free(removed.pixels);
        self.image_count -= 1;
        if (image_index != self.image_count) self.images[image_index] = self.images[self.image_count];
        return .{ .changed = true, .response_id = command_value.id, .quiet = command_value.quiet };
    }

    /// Removes every image and placement, preserving no protocol transfer.
    pub fn reset(self: *Plane) bool {
        self.cancel();
        const changed = self.image_count != 0 or self.placement_count != 0;
        for (self.images[0..self.image_count]) |retained| self.allocator.free(retained.pixels);
        self.image_count = 0;
        self.placement_count = 0;
        self.storage_bytes = 0;
        if (changed) {
            self.advance();
            self.content_generation = self.next_generation;
        }
        return changed;
    }

    /// Removes all placements owned by one bank while retaining image data.
    pub fn clearBank(self: *Plane, bank: Bank) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            if (self.placements[index].bank != bank) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Drops primary placements whose complete anchor row was evicted.
    pub fn evictBefore(self: *Plane, absolute_row: u64) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = self.placements[index];
            if (retained.bank != .primary or retained.row >= absolute_row) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Removes placements intersecting one cell rectangle.
    pub fn erase(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        left: u16,
        right: u16,
    ) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = self.placements[index];
            const retained_bottom = retained.row + retained.rows - 1;
            const retained_right = @as(u32, retained.col) + retained.cols - 1;
            if (retained.bank != bank or retained.row > bottom or retained_bottom < top or
                retained.col > right or retained_right < left)
            {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Moves or clips placement anchors with one terminal row scroll.
    pub fn scroll(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        count: u16,
        upward: bool,
    ) bool {
        if (count == 0) return false;
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = &self.placements[index];
            if (retained.bank != bank or retained.row < top or retained.row > bottom) {
                index += 1;
                continue;
            }
            if (upward) {
                if (retained.row < top + count) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.row -= count;
            } else {
                if (retained.row + count > bottom) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.row += count;
            }
            changed = true;
            index += 1;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Moves or clips placement anchors with one terminal column shift.
    pub fn shiftColumns(
        self: *Plane,
        bank: Bank,
        row: u64,
        left: u16,
        right: u16,
        count: u16,
        toward_left: bool,
    ) bool {
        if (count == 0) return false;
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = &self.placements[index];
            if (retained.bank != bank or retained.row != row or
                retained.col < left or retained.col > right)
            {
                index += 1;
                continue;
            }
            if (toward_left) {
                if (retained.col < left + count) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.col -= count;
            } else {
                if (@as(u32, retained.col) + count > right) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.col += count;
            }
            changed = true;
            index += 1;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Borrows one retained image by dense index.
    pub fn image(self: *const Plane, index: usize) ?ImageView {
        if (index >= self.image_count) return null;
        return self.images[index].view();
    }

    /// Copies one retained placement by dense index.
    pub fn placement(self: *const Plane, index: usize) ?Placement {
        if (index >= self.placement_count) return null;
        return self.placements[index];
    }

    /// Returns the monotonic image-plane mutation identity.
    pub fn generation(self: *const Plane) u64 {
        return self.next_generation;
    }

    /// Returns the monotonic identity of retained decoded image content.
    pub fn imageGeneration(self: *const Plane) u64 {
        return self.content_generation;
    }

    fn addPlacement(
        self: *Plane,
        image_id: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        pixel_width: u32,
        pixel_height: u32,
        placement_generation: u64,
    ) void {
        std.debug.assert(cell_width != 0 and cell_height != 0);
        const occupied_cols = (pixel_width + cell_width - 1) / cell_width;
        const occupied_rows = (pixel_height + cell_height - 1) / cell_height;
        self.placements[self.placement_count] = .{
            .image_id = image_id,
            .generation = placement_generation,
            .bank = bank,
            .row = row,
            .col = col,
            .rows = @intCast(@min(occupied_rows, std.math.maxInt(u16))),
            .cols = @intCast(@min(occupied_cols, std.math.maxInt(u16))),
        };
        self.placement_count += 1;
    }

    fn removePlacements(self: *Plane, image_id: u32) void {
        var index: usize = 0;
        while (index < self.placement_count) {
            if (self.placements[index].image_id != image_id) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
        }
    }

    fn removePlacement(self: *Plane, index: usize) void {
        self.placement_count -= 1;
        if (index != self.placement_count) self.placements[index] = self.placements[self.placement_count];
    }

    fn imageIndex(self: *const Plane, id: u32) ?usize {
        for (self.images[0..self.image_count], 0..) |retained, index|
            if (retained.id == id) return index;
        return null;
    }

    fn advance(self: *Plane) void {
        if (self.next_generation == std.math.maxInt(u64))
            @panic("terminal image generation exhausted");
        self.next_generation += 1;
    }
};

fn parseCommand(bytes: []const u8) ?Command {
    const separator = std.mem.indexOfScalar(u8, bytes, ';');
    const metadata = if (separator) |index| bytes[0..index] else bytes;
    var result = Command{ .payload = if (separator) |index| bytes[index + 1 ..] else "" };
    var seen: u32 = 0;
    var fields = std.mem.splitScalar(u8, metadata, ',');
    while (fields.next()) |field| {
        if (field.len < 3 or field[1] != '=') return null;
        const key = field[0];
        const bit: u32 = switch (key) {
            'a' => 1 << 0,
            't' => 1 << 1,
            'f' => 1 << 2,
            'i' => 1 << 3,
            's' => 1 << 4,
            'v' => 1 << 5,
            'm' => 1 << 6,
            'q' => 1 << 7,
            'd' => 1 << 8,
            else => return null,
        };
        if (seen & bit != 0) return null;
        seen |= bit;
        const value = field[2..];
        switch (key) {
            'a' => if (value.len == 1) {
                result.action = value[0];
            } else return null,
            't' => if (value.len == 1) {
                result.medium = value[0];
            } else return null,
            'f' => result.format = std.fmt.parseInt(u8, value, 10) catch return null,
            'i' => result.id = std.fmt.parseInt(u32, value, 10) catch return null,
            's' => result.width = std.fmt.parseInt(u32, value, 10) catch return null,
            'v' => result.height = std.fmt.parseInt(u32, value, 10) catch return null,
            'm' => {
                const more = std.fmt.parseInt(u8, value, 10) catch return null;
                if (more > 1) return null;
                result.more = more == 1;
            },
            'q' => {
                const quiet = std.fmt.parseInt(u8, value, 10) catch return null;
                if (quiet > 2) return null;
                result.quiet = @intCast(quiet);
            },
            'd' => if (value.len == 1) {
                result.delete = value[0];
            } else return null,
            else => return null,
        }
    }
    return result;
}

fn nonzero(value: u32) ?u32 {
    return if (value == 0) null else value;
}

test "static plane admission is transactional across chunks replacement put and delete" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const first = try plane.command("a=T,f=32,s=1,v=1,i=7,m=1;/wA=", .primary, 4, 2, 1, 1);
    try std.testing.expect(!first.changed);
    const completed = try plane.command("m=0;AP8=", .primary, 4, 2, 1, 1);
    try std.testing.expect(completed.changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    const generation = plane.generation();
    const malformed = try plane.command("a=t,f=32,s=1,v=1,i=8;%%", .primary, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, malformed.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expect((try plane.command("a=p,i=7", .alternate, 1, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=i,i=7", .primary, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "RGB conversion quota cancellation and bank cleanup preserve exact ownership" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=24,s=1,v=1,i=1;AQID",
        .alternate,
        2,
        4,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, plane.image(0).?.pixels);
    try std.testing.expect(plane.clearBank(.alternate));
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    const before = plane.generation();
    const rejected = try plane.command("a=t,f=32,s=4096,v=4096,i=2;", .primary, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.quota, rejected.failure.?);
    try std.testing.expectEqual(before, plane.generation());
}

test "new transmission cancels an incomplete stream without retained mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const incomplete = try plane.command(
        "a=t,f=32,s=1,v=1,i=2,m=1;AQ==",
        .primary,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(!incomplete.changed);
    try std.testing.expectEqual(@as(u64, 0), plane.generation());
    const replacement = try plane.command(
        "a=t,f=32,s=1,v=1,i=3;AQIDBA==",
        .primary,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(replacement.changed);
    try std.testing.expectEqual(@as(u32, 3), plane.image(0).?.id);
}

test "static image allocation failure leaves the plane reusable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var plane = Plane.init(allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
}
