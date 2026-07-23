//! Owns bounded terminal images, animation frames, and cell-relative placements.

const std = @import("std");

/// Bounds decoded image bytes retained by one terminal.
pub const max_storage_bytes: usize = 64 * 1024 * 1024;
/// Bounds one decoded RGBA image.
pub const max_image_bytes: usize = 16 * 1024 * 1024;
/// Bounds retained image identities.
pub const max_images: usize = 256;
/// Bounds retained image placements.
pub const max_placements: usize = 1024;
/// Bounds retained animation frames across one terminal.
pub const max_frames: usize = 256;
/// Bounds either image dimension before byte-count validation.
pub const max_dimension: u32 = 4096;
/// Bounds one encoded Kitty APC command chunk.
pub const max_command_bytes: usize = 8192;

/// Identifies the screen bank owning one placement.
pub const Bank = enum { primary, alternate };

/// Borrows immutable decoded RGBA pixels until plane mutation.
pub const ImageView = struct {
    /// Plane-owned nonzero image identity.
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
    /// Optional application-selected Kitty placement identity.
    kitty_id: u32,
    /// Monotonic placement identity.
    generation: u64,
    /// Screen bank owning this placement.
    bank: Bank,
    /// Primary absolute projected row or alternate screen row.
    row: u64,
    /// Physical terminal column.
    col: u16,
    /// Selects the first decoded source column.
    source_x: u32,
    /// Selects the first decoded source row.
    source_y: u32,
    /// Counts selected decoded source columns.
    source_width: u32,
    /// Counts selected decoded source rows.
    source_height: u32,
    /// Offsets the destination within its anchor cell horizontally.
    cell_x: u32,
    /// Offsets the destination within its anchor cell vertically.
    cell_y: u32,
    /// Counts destination pixels horizontally.
    pixel_width: u32,
    /// Counts destination pixels vertically.
    pixel_height: u32,
    /// Signed Kitty layer relative to terminal text.
    z: i32,
    /// Counts occupied terminal rows at placement time.
    rows: u16,
    /// Counts occupied physical terminal columns at placement time.
    cols: u16,
};

const Image = struct {
    id: u32,
    kitty_id: ?u32,
    kitty_number: ?u32,
    width: u32,
    height: u32,
    generation: u64,
    pixels: []u8,
    current_frame: u16 = 0,
    root_gap_ms: u32 = 40,
    animation: AnimationState = .stopped,
    max_loops: u32 = 0,
    loops_remaining: u32 = 0,
    frame_started_ms: ?u64 = null,
};

const AnimationState = enum { stopped, loading, running };

const Frame = struct {
    image_id: u32,
    number: u16,
    gap_ms: u32,
    pixels: []u8,
};

const Loading = struct {
    action: u8,
    format: u8,
    id: u32,
    image_number: u32,
    placement_id: u32,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    columns: u32,
    rows: u32,
    cell_x: u32,
    cell_y: u32,
    z: i32,
    compose_mode: u2,
    width: u32,
    height: u32,
    quiet: u2,
    bytes: []u8,
    used: usize = 0,
};

/// Reports exact bounded Kitty graphics admission.
pub const Result = struct {
    /// True when retained images or placements changed.
    changed: bool = false,
    /// True when a semantic change alters the currently visible image plane.
    visual_changed: bool = true,
    /// Image identity echoed by a protocol response.
    response_id: ?u32 = null,
    /// Image number echoed alongside generated or selected identity.
    response_number: ?u32 = null,
    /// Animation frame number echoed for frame admission.
    response_frame: ?u16 = null,
    /// Null identifies success; otherwise supplies Kitty's stable short error.
    failure: ?Failure = null,
    /// Suppresses success or all responses according to `q`.
    quiet: u2 = 0,
};

/// Names one bounded terminal-graphics rejection.
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

/// Reports one monotonic animation service result.
pub const AnimationTick = struct {
    /// True when a currently displayed frame changed.
    changed: bool,
    /// True when frame or run-state mutation was accepted.
    semantic_changed: bool,
    /// Milliseconds until the next frame boundary, or null when idle.
    next_ms: ?u32,
};

const Command = struct {
    action: u8 = 't',
    medium: u8 = 'd',
    format: u8 = 32,
    id: u32 = 0,
    image_number: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    more: bool = false,
    quiet: u2 = 0,
    delete: u8 = 0,
    placement_id: u32 = 0,
    source_width: u32 = 0,
    source_height: u32 = 0,
    columns: u32 = 0,
    rows: u32 = 0,
    cell_x: u32 = 0,
    cell_y: u32 = 0,
    z: i32 = 0,
    compose_mode: u2 = 0,
    x: u32 = 0,
    y: u32 = 0,
    payload: []const u8 = "",
};

/// Returns whether one command can emit a Kitty protocol response.
pub fn mayRespond(bytes: []const u8) bool {
    const command_value = parseCommand(bytes) orelse return true;
    return command_value.action != 'd';
}

/// Owns decoded image/frame bytes, placements, animation state, and one transfer.
pub const Plane = struct {
    allocator: std.mem.Allocator,
    images: [max_images]Image = undefined,
    image_count: u16 = 0,
    placements: [max_placements]Placement = undefined,
    placement_count: u16 = 0,
    frames: [max_frames]Frame = undefined,
    frame_count: u16 = 0,
    storage_bytes: usize = 0,
    next_generation: u64 = 0,
    next_image_id: u32 = 0,
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
        for (self.frames[0..self.frame_count]) |retained| self.allocator.free(retained.pixels);
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
        screen_origin: u64,
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
                .response_number = nonzero(command_value.image_number),
                .failure = .unsupported,
                .quiet = command_value.quiet,
            };
        }
        return switch (command_value.action) {
            't', 'T', 'q' => try self.transmit(command_value, bank, row, col, cell_width, cell_height),
            'f' => try self.frame(command_value),
            'a' => self.animate(command_value),
            'c' => try self.composeFrames(command_value),
            'p' => self.put(command_value, bank, row, col, cell_width, cell_height),
            'd' => self.delete(command_value, bank, screen_origin, row, col),
            else => .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
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
            if ((command_value.id == 0 and command_value.image_number == 0) or
                (command_value.id != 0 and command_value.image_number != 0) or
                command_value.width == 0 or command_value.height == 0 or
                command_value.width > max_dimension or command_value.height > max_dimension or
                (command_value.format != 24 and command_value.format != 32))
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .invalid,
                    .quiet = command_value.quiet,
                };
            const channels: usize = if (command_value.format == 24) 3 else 4;
            const pixels = std.math.mul(usize, command_value.width, command_value.height) catch
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .quota,
                    .quiet = command_value.quiet,
                };
            const rgba_bytes = std.math.mul(usize, pixels, 4) catch
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .quota,
                    .quiet = command_value.quiet,
                };
            const input_bytes = std.math.mul(usize, pixels, channels) catch
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .quota,
                    .quiet = command_value.quiet,
                };
            if (rgba_bytes > max_image_bytes)
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .quota,
                    .quiet = command_value.quiet,
                };
            const kitty_id = if (command_value.id != 0)
                command_value.id
            else
                self.allocateKittyId() orelse
                    return .{ .response_number = command_value.image_number, .failure = .quota, .quiet = command_value.quiet };
            const input = try self.allocator.alloc(u8, input_bytes);
            self.loading = .{
                .action = command_value.action,
                .format = command_value.format,
                .id = kitty_id,
                .image_number = command_value.image_number,
                .placement_id = command_value.placement_id,
                .source_x = command_value.x,
                .source_y = command_value.y,
                .source_width = command_value.source_width,
                .source_height = command_value.source_height,
                .columns = command_value.columns,
                .rows = command_value.rows,
                .cell_x = command_value.cell_x,
                .cell_y = command_value.cell_y,
                .z = command_value.z,
                .compose_mode = command_value.compose_mode,
                .width = command_value.width,
                .height = command_value.height,
                .quiet = command_value.quiet,
                .bytes = input,
            };
        } else {
            if (command_value.width != 0 or command_value.height != 0 or
                command_value.id != 0 or command_value.image_number != 0 or command_value.placement_id != 0)
            {
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

    fn frame(self: *Plane, command_value: Command) std.mem.Allocator.Error!Result {
        if (self.loading != null) {
            self.cancel();
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        }
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = self.images[image_index];
        const width = if (command_value.width == 0) image_value.width else command_value.width;
        const height = if (command_value.height == 0) image_value.height else command_value.height;
        if (width > image_value.width or height > image_value.height or
            command_value.x > image_value.width - width or command_value.y > image_value.height - height or
            (command_value.format != 24 and command_value.format != 32))
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const channels: usize = if (command_value.format == 24) 3 else 4;
        const input_bytes = std.math.mul(usize, width, height) catch
            return .{ .response_id = image_value.kitty_id, .failure = .quota, .quiet = command_value.quiet };
        const byte_count = std.math.mul(usize, input_bytes, channels) catch
            return .{ .response_id = image_value.kitty_id, .failure = .quota, .quiet = command_value.quiet };
        const input = try self.allocator.alloc(u8, byte_count);
        self.loading = .{
            .action = 'f',
            .format = command_value.format,
            .id = image_value.kitty_id.?,
            .image_number = image_value.kitty_number orelse 0,
            .placement_id = 0,
            .source_x = command_value.x,
            .source_y = command_value.y,
            .source_width = 0,
            .source_height = 0,
            .columns = command_value.columns,
            .rows = command_value.rows,
            .cell_x = 0,
            .cell_y = 0,
            .z = command_value.z,
            .compose_mode = command_value.compose_mode,
            .width = width,
            .height = height,
            .quiet = command_value.quiet,
            .bytes = input,
        };
        var continuation = command_value;
        continuation.action = 't';
        continuation.format = 32;
        continuation.id = 0;
        continuation.image_number = 0;
        continuation.width = 0;
        continuation.height = 0;
        return self.transmit(continuation, .primary, 0, 0, 1, 1);
    }

    fn finishFrame(self: *Plane, loading: Loading) std.mem.Allocator.Error!Result {
        const image_index = self.kittyImageIndex(loading.id) orelse
            return .{ .response_id = loading.id, .failure = .missing, .quiet = loading.quiet };
        const image_value = self.images[image_index];
        const next_number = self.nextFrameNumber(image_value.id) orelse
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const requested = if (loading.rows == 0)
            next_number
        else
            std.math.cast(u16, loading.rows) orelse
                return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet };
        if (requested == 0)
            return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet };
        const frame_number = @min(requested, next_number);
        const root = frame_number == 1;
        const existing = self.frameIndex(image_value.id, frame_number);
        if (!root and existing == null and self.frame_count == max_frames)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const canvas_bytes = image_value.pixels.len;
        const prior_bytes = if (root)
            image_value.pixels.len
        else if (existing) |index|
            self.frames[index].pixels.len
        else
            0;
        if (canvas_bytes > max_image_bytes or self.storage_bytes - prior_bytes > max_storage_bytes - canvas_bytes)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const canvas = try self.allocator.alloc(u8, canvas_bytes);
        errdefer self.allocator.free(canvas);
        const base = if (loading.columns == 0)
            null
        else if (loading.columns == 1)
            image_value.pixels
        else
            (self.frameByNumber(image_value.id, std.math.cast(u16, loading.columns) orelse
                return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet }) orelse
                return .{ .response_id = loading.id, .failure = .missing, .quiet = loading.quiet }).pixels;
        if (base) |pixels| @memcpy(canvas, pixels) else @memset(canvas, 0);
        composeRgba(
            canvas,
            image_value.width,
            loading.bytes,
            loading.width,
            0,
            0,
            loading.format,
            loading.width,
            loading.height,
            loading.source_x,
            loading.source_y,
            loading.compose_mode != 1,
        );
        const gap: u32 = if (loading.z > 0) @intCast(loading.z) else if (loading.z < 0) 0 else 40;
        if (root) {
            self.storage_bytes -= self.images[image_index].pixels.len;
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = canvas;
            self.images[image_index].root_gap_ms = gap;
        } else if (existing) |index| {
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
            self.frames[index] = .{ .image_id = image_value.id, .number = frame_number, .gap_ms = gap, .pixels = canvas };
        } else {
            self.frames[self.frame_count] = .{
                .image_id = image_value.id,
                .number = frame_number,
                .gap_ms = gap,
                .pixels = canvas,
            };
            self.frame_count += 1;
        }
        self.storage_bytes += canvas.len;
        const visible = self.images[image_index].current_frame + 1 == frame_number;
        if (visible) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{
            .changed = true,
            .visual_changed = visible,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .response_frame = frame_number,
            .quiet = loading.quiet,
        };
    }

    fn composeFrames(self: *Plane, command_value: Command) std.mem.Allocator.Error!Result {
        if ((command_value.id == 0) == (command_value.image_number == 0) or
            command_value.rows == 0 or command_value.columns == 0)
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = self.images[image_index];
        const source = self.framePixels(image_value, command_value.rows) orelse
            return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        const destination_number = std.math.cast(u16, command_value.columns) orelse
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const destination_index = if (destination_number == 1)
            null
        else
            self.frameIndex(image_value.id, destination_number) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        const copy_width = if (command_value.width == 0) image_value.width else command_value.width;
        const copy_height = if (command_value.height == 0) image_value.height else command_value.height;
        if (copy_width == 0 or copy_height == 0 or
            copy_width > image_value.width or copy_height > image_value.height or
            command_value.x > image_value.width -| copy_width or
            command_value.y > image_value.height -| copy_height or
            command_value.cell_x > image_value.width -| copy_width or
            command_value.cell_y > image_value.height -| copy_height)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (command_value.rows == command_value.columns and
            rectanglesOverlap(
                command_value.cell_x,
                command_value.cell_y,
                command_value.x,
                command_value.y,
                copy_width,
                copy_height,
            ))
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const destination = if (destination_index) |index|
            self.frames[index].pixels
        else
            image_value.pixels;
        const replacement = try self.allocator.dupe(u8, destination);
        errdefer self.allocator.free(replacement);
        composeRgba(
            replacement,
            image_value.width,
            source,
            image_value.width,
            command_value.cell_x,
            command_value.cell_y,
            32,
            copy_width,
            copy_height,
            command_value.x,
            command_value.y,
            command_value.compose_mode != 1,
        );
        if (destination_index) |index| {
            self.allocator.free(self.frames[index].pixels);
            self.frames[index].pixels = replacement;
        } else {
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = replacement;
        }
        const visible = image_value.current_frame + 1 == destination_number;
        if (visible) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{
            .changed = true,
            .visual_changed = visible,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
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
        if (loading.action == 'f') return try self.finishFrame(loading);
        const rgba_len = @as(usize, loading.width) * loading.height * 4;
        if (loading.action == 'q')
            return .{ .response_id = loading.id, .quiet = loading.quiet };
        const prior_index = if (loading.image_number != 0)
            null
        else
            self.kittyImageIndex(loading.id);
        const prior_bytes = if (prior_index) |index|
            self.images[index].pixels.len + self.frameBytes(self.images[index].id)
        else
            0;
        if (rgba_len > max_storage_bytes - (self.storage_bytes - prior_bytes))
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        if (prior_index == null and self.image_count == max_images)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const display = loading.action == 'T';
        const replaced_placement = if (display and prior_index != null)
            self.placementIndex(self.images[prior_index.?].id, loading.placement_id)
        else
            null;
        if (display and self.placement_count == max_placements and replaced_placement == null)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        var planned_placement = if (display)
            makePlacement(
                1,
                loading.placement_id,
                bank,
                row,
                col,
                cell_width,
                cell_height,
                loading.width,
                loading.height,
                loading.source_x,
                loading.source_y,
                loading.source_width,
                loading.source_height,
                loading.columns,
                loading.rows,
                loading.cell_x,
                loading.cell_y,
                loading.z,
                1,
            ) orelse return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet }
        else
            null;
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
            const image_id = self.images[index].id;
            self.removeFrames(image_id);
            self.storage_bytes -= self.images[index].pixels.len;
            self.allocator.free(self.images[index].pixels);
            self.images[index] = .{
                .id = image_id,
                .kitty_id = loading.id,
                .kitty_number = nonzero(loading.image_number),
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
            };
        } else {
            const image_id = self.allocateImageId();
            self.images[self.image_count] = .{
                .id = image_id,
                .kitty_id = loading.id,
                .kitty_number = nonzero(loading.image_number),
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
            };
            self.image_count += 1;
        }
        self.storage_bytes += rgba.len;
        if (display) {
            const image_id = self.images[prior_index orelse self.image_count - 1].id;
            planned_placement.?.image_id = image_id;
            planned_placement.?.generation = content_generation;
            if (replaced_placement) |index| {
                self.placements[index] = planned_placement.?;
            } else {
                self.placements[self.placement_count] = planned_placement.?;
                self.placement_count += 1;
            }
        }
        return .{
            .changed = true,
            .response_id = loading.id,
            .response_number = nonzero(loading.image_number),
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
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .invalid,
                .quiet = command_value.quiet,
            };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .missing,
                .quiet = command_value.quiet,
            };
        const retained = self.images[image_index];
        var planned = makePlacement(
            retained.id,
            command_value.placement_id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            retained.width,
            retained.height,
            command_value.x,
            command_value.y,
            command_value.source_width,
            command_value.source_height,
            command_value.columns,
            command_value.rows,
            command_value.cell_x,
            command_value.cell_y,
            command_value.z,
            1,
        ) orelse return .{ .response_id = command_value.id, .failure = .invalid, .quiet = command_value.quiet };
        if (self.placement_count == max_placements)
            if (self.placementIndex(retained.id, command_value.placement_id) == null)
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
        self.advance();
        const placement_generation = self.next_generation;
        planned.generation = placement_generation;
        if (self.placementIndex(retained.id, command_value.placement_id)) |index| {
            self.placements[index] = planned;
        } else {
            self.placements[self.placement_count] = planned;
            self.placement_count += 1;
        }
        return .{
            .changed = true,
            .response_id = retained.kitty_id,
            .response_number = retained.kitty_number,
            .quiet = command_value.quiet,
        };
    }

    fn delete(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        screen_origin: u64,
        cursor_row: u64,
        cursor_col: u16,
    ) Result {
        self.cancel();
        const selector = if (command_value.delete == 0) 'a' else command_value.delete;
        const remove_data = std.ascii.isUpper(selector);
        const normalized = std.ascii.toLower(selector);
        if (std.mem.indexOfScalar(u8, "afinrpqxyzc", normalized) == null)
            return .{ .quiet = 2 };
        if (normalized == 'f') return self.deleteFrame(command_value, remove_data);
        if (normalized == 'i' and command_value.id == 0) return .{ .quiet = 2 };
        if (normalized == 'n' and command_value.image_number == 0) return .{ .quiet = 2 };
        if (normalized == 'r' and command_value.x > command_value.y) return .{ .quiet = 2 };
        const numbered_image_id = if (normalized == 'n')
            if (self.kittyImageNumberIndex(command_value.image_number)) |index| self.images[index].id else null
        else
            null;

        var changed = false;
        var placement_index: usize = 0;
        while (placement_index < self.placement_count) {
            const placement_value = self.placements[placement_index];
            if (normalized == 'n' and placement_value.image_id != numbered_image_id) {
                placement_index += 1;
                continue;
            }
            const kitty_id = self.kittyIdForImage(placement_value.image_id);
            const kitty_number = self.kittyNumberForImage(placement_value.image_id);
            if (kitty_id == null or placement_value.bank != bank or !deleteMatches(
                placement_value,
                kitty_id,
                kitty_number,
                normalized,
                command_value,
                screen_origin,
                cursor_row,
                cursor_col,
            )) {
                placement_index += 1;
                continue;
            }
            self.removePlacement(placement_index);
            changed = true;
        }

        var content_changed = false;
        if (remove_data) {
            var image_index: usize = 0;
            while (image_index < self.image_count) {
                const image_id = self.images[image_index].id;
                const kitty_id = self.images[image_index].kitty_id;
                const selected = switch (normalized) {
                    'a' => kitty_id != null and !self.hasPlacement(image_id),
                    'i' => kitty_id == command_value.id,
                    'n' => image_id == numbered_image_id,
                    'r' => if (kitty_id) |id| command_value.x <= id and id <= command_value.y else false,
                    else => !self.hasPlacement(image_id),
                };
                if (!selected) {
                    image_index += 1;
                    continue;
                }
                if (normalized == 'i' or normalized == 'r') self.removePlacements(image_id);
                self.removeImage(image_index);
                content_changed = true;
                changed = true;
            }
        }
        if (changed) {
            self.advance();
            if (content_changed) self.content_generation = self.next_generation;
        }
        // Kitty deletion commands deliberately produce no protocol response.
        return .{ .changed = changed, .quiet = 2 };
    }

    fn deleteFrame(self: *Plane, command_value: Command, remove_image: bool) Result {
        if ((command_value.id == 0) == (command_value.image_number == 0)) return .{ .quiet = 2 };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse return .{ .quiet = 2 };
        const image_id = self.images[image_index].id;
        const frame_count = self.frameCount(image_id);
        if (frame_count == 0) {
            if (!remove_image) return .{ .quiet = 2 };
            self.removePlacements(image_id);
            self.removeImage(image_index);
            self.advance();
            self.content_generation = self.next_generation;
            return .{ .changed = true, .quiet = 2 };
        }
        const requested = if (command_value.rows == 0)
            1
        else
            @min(std.math.cast(u16, command_value.rows) orelse return .{ .quiet = 2 }, frame_count + 1);
        const prior_current = self.images[image_index].current_frame;
        const visible_changed = prior_current + 1 == requested;
        if (requested == 1) {
            const promoted_index = self.frameIndex(image_id, 2).?;
            const promoted_gap = self.frames[promoted_index].gap_ms;
            self.storage_bytes -= self.images[image_index].pixels.len;
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = self.frames[promoted_index].pixels;
            self.images[image_index].root_gap_ms = promoted_gap;
            self.removeFrameSlot(promoted_index, false);
        } else {
            const removed_index = self.frameIndex(image_id, requested).?;
            self.removeFrameSlot(removed_index, true);
        }
        for (self.frames[0..self.frame_count]) |*retained_frame| {
            if (retained_frame.image_id == image_id and retained_frame.number > requested) {
                retained_frame.number -= 1;
            }
        }
        const remaining = self.frameCount(image_id);
        if (prior_current + 1 == requested or prior_current > remaining) {
            self.images[image_index].current_frame = @min(prior_current, remaining);
        } else if (prior_current + 1 > requested) {
            self.images[image_index].current_frame -= 1;
        }
        if (visible_changed) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{ .changed = true, .visual_changed = visible_changed, .quiet = 2 };
    }

    /// Removes every image and placement, preserving no protocol transfer.
    pub fn reset(self: *Plane) bool {
        self.cancel();
        const changed = self.image_count != 0 or self.placement_count != 0 or self.frame_count != 0;
        for (self.images[0..self.image_count]) |retained| self.allocator.free(retained.pixels);
        for (self.frames[0..self.frame_count]) |retained| self.allocator.free(retained.pixels);
        self.image_count = 0;
        self.placement_count = 0;
        self.frame_count = 0;
        self.storage_bytes = 0;
        if (changed) {
            self.advance();
            self.content_generation = self.next_generation;
        }
        return changed;
    }

    /// Transactionally retains one decoded RGBA image and ordinary placement.
    ///
    /// Ownership of `pixels` transfers only on success. Sixel and other
    /// terminal-owned decoders use a plane identity that cannot collide with a
    /// Kitty application-selected identity.
    pub fn admitDecoded(
        self: *Plane,
        pixels: []u8,
        width: u32,
        height: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) error{Quota}!void {
        if (width == 0 or height == 0 or width > max_dimension or height > max_dimension or
            pixels.len > max_image_bytes or pixels.len > max_storage_bytes - self.storage_bytes or
            self.image_count == max_images or self.placement_count == max_placements)
            return error.Quota;
        const expected = std.math.mul(usize, width, height) catch return error.Quota;
        const expected_bytes = std.math.mul(usize, expected, 4) catch return error.Quota;
        if (expected_bytes != pixels.len)
            return error.Quota;
        const image_id = self.allocateImageId();
        self.advance();
        self.content_generation = self.next_generation;
        self.images[self.image_count] = .{
            .id = image_id,
            .kitty_id = null,
            .kitty_number = null,
            .width = width,
            .height = height,
            .generation = self.next_generation,
            .pixels = pixels,
        };
        self.image_count += 1;
        self.storage_bytes += pixels.len;
        const added = self.addPlacement(
            image_id,
            0,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            width,
            height,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            self.next_generation,
        );
        std.debug.assert(added != null);
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
        const retained = self.images[index];
        const pixels = if (retained.current_frame == 0)
            retained.pixels
        else
            self.frameByNumber(retained.id, retained.current_frame + 1).?.pixels;
        return .{
            .id = retained.id,
            .width = retained.width,
            .height = retained.height,
            .generation = retained.generation,
            .pixels = pixels,
        };
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

    /// Advances running Kitty animations against caller monotonic milliseconds.
    pub fn advanceAnimations(self: *Plane, now_ms: u64) AnimationTick {
        var changed = false;
        var semantic_changed = false;
        var next_ms: ?u32 = null;
        for (self.images[0..self.image_count]) |*image_value| {
            if (image_value.animation == .stopped or self.frameCount(image_value.id) == 0 or
                !self.hasPlacement(image_value.id) or self.animationDuration(image_value.*) == 0)
                continue;
            if (image_value.frame_started_ms == null) image_value.frame_started_ms = now_ms;
            const gap = self.currentGap(image_value.*);
            const elapsed = now_ms -| image_value.frame_started_ms.?;
            if (elapsed >= gap) {
                const initial_last = self.lastFrameNumber(image_value.id);
                const initial_number = image_value.current_frame + 1;
                if (initial_number == initial_last and image_value.animation == .loading) continue;
                if (initial_number == initial_last and image_value.loops_remaining == 1) {
                    image_value.animation = .stopped;
                    image_value.loops_remaining = 0;
                    semantic_changed = true;
                    continue;
                }
                var advanced = false;
                var steps: u16 = 0;
                while (steps <= self.frameCount(image_value.id)) : (steps += 1) {
                    const last = self.lastFrameNumber(image_value.id);
                    const current_number = image_value.current_frame + 1;
                    if (current_number < last) {
                        image_value.current_frame += 1;
                    } else if (image_value.animation == .loading) {
                        break;
                    } else if (image_value.loops_remaining == 1) {
                        image_value.animation = .stopped;
                        image_value.loops_remaining = 0;
                        break;
                    } else {
                        image_value.current_frame = 0;
                        if (image_value.loops_remaining > 1) image_value.loops_remaining -= 1;
                    }
                    advanced = true;
                    if (self.currentGap(image_value.*) != 0) break;
                }
                if (advanced) {
                    image_value.frame_started_ms = now_ms;
                    self.advance();
                    self.content_generation = self.next_generation;
                    image_value.generation = self.next_generation;
                    changed = true;
                    semantic_changed = true;
                }
            }
            if (image_value.animation != .stopped) {
                const remaining: u32 = @intCast(@min(
                    @as(u64, self.currentGap(image_value.*)) -|
                        (now_ms -| image_value.frame_started_ms.?),
                    std.math.maxInt(u32),
                ));
                next_ms = if (next_ms) |prior| @min(prior, @max(1, remaining)) else @max(1, remaining);
            }
        }
        return .{ .changed = changed, .semantic_changed = semantic_changed, .next_ms = next_ms };
    }

    fn animate(self: *Plane, command_value: Command) Result {
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = &self.images[index];
        const selected_frame: ?u16 = if (command_value.columns == 0)
            null
        else
            std.math.cast(u16, command_value.columns) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (selected_frame) |number| {
            if (number == 0)
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
            if (number != 1 and self.frameByNumber(image_value.id, number) == null)
                return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        }
        const gap_frame: ?u16 = if (command_value.rows == 0 or command_value.z == 0)
            null
        else
            std.math.cast(u16, command_value.rows) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const gap_index: ?usize = if (gap_frame) |number|
            if (number == 0)
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet }
            else if (number == 1)
                null
            else
                self.frameIndex(image_value.id, number) orelse
                    return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet }
        else
            null;
        const requested_animation: ?AnimationState = if (command_value.width == 0)
            null
        else switch (command_value.width) {
            1 => .stopped,
            2 => .loading,
            3 => .running,
            else => return .{
                .response_id = image_value.kitty_id,
                .failure = .invalid,
                .quiet = command_value.quiet,
            },
        };
        var semantic_changed = false;
        var visible_changed = false;
        if (selected_frame) |number| {
            if (image_value.current_frame + 1 != number) {
                image_value.current_frame = number - 1;
                semantic_changed = true;
                visible_changed = true;
            }
        }
        if (gap_frame) |number| {
            const gap: u32 = if (command_value.z > 0) @intCast(command_value.z) else 0;
            if (number == 1) {
                if (image_value.root_gap_ms != gap) {
                    image_value.root_gap_ms = gap;
                    semantic_changed = true;
                }
            } else {
                if (self.frames[gap_index.?].gap_ms != gap) {
                    self.frames[gap_index.?].gap_ms = gap;
                    semantic_changed = true;
                }
            }
        }
        if (requested_animation) |animation| {
            if (image_value.animation != animation) {
                const was_stopped = image_value.animation == .stopped;
                image_value.animation = animation;
                if (animation == .stopped or was_stopped) image_value.loops_remaining = image_value.max_loops;
                semantic_changed = true;
            }
        }
        if (command_value.height != 0) {
            const loops = command_value.height - 1;
            if (image_value.max_loops != loops) {
                image_value.max_loops = loops;
                image_value.loops_remaining = loops;
                semantic_changed = true;
            }
        }
        if (semantic_changed) image_value.frame_started_ms = null;
        if (!semantic_changed) return .{
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
        if (visible_changed) {
            self.advance();
            self.content_generation = self.next_generation;
            image_value.generation = self.next_generation;
        }
        return .{
            .changed = semantic_changed,
            .visual_changed = visible_changed,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
    }

    fn addPlacement(
        self: *Plane,
        image_id: u32,
        kitty_id: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        pixel_width: u32,
        pixel_height: u32,
        source_x: u32,
        source_y: u32,
        source_width: u32,
        source_height: u32,
        columns: u32,
        rows: u32,
        cell_x: u32,
        cell_y: u32,
        z: i32,
        placement_generation: u64,
    ) ?void {
        self.placements[self.placement_count] = makePlacement(
            image_id,
            kitty_id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            pixel_width,
            pixel_height,
            source_x,
            source_y,
            source_width,
            source_height,
            columns,
            rows,
            cell_x,
            cell_y,
            z,
            placement_generation,
        ) orelse return null;
        self.placement_count += 1;
    }

    fn placementIndex(self: *const Plane, image_id: u32, kitty_id: u32) ?usize {
        if (kitty_id == 0) return null;
        for (self.placements[0..self.placement_count], 0..) |retained, index|
            if (retained.image_id == image_id and retained.kitty_id == kitty_id) return index;
        return null;
    }

    fn makePlacement(
        image_id: u32,
        kitty_id: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        pixel_width: u32,
        pixel_height: u32,
        source_x: u32,
        source_y: u32,
        requested_width: u32,
        requested_height: u32,
        requested_cols: u32,
        requested_rows: u32,
        cell_x: u32,
        cell_y: u32,
        z: i32,
        placement_generation: u64,
    ) ?Placement {
        std.debug.assert(cell_width != 0 and cell_height != 0);
        if (source_x >= pixel_width or source_y >= pixel_height or
            cell_x >= cell_width or cell_y >= cell_height) return null;
        const source_width = if (requested_width == 0) pixel_width - source_x else requested_width;
        const source_height = if (requested_height == 0) pixel_height - source_y else requested_height;
        if (source_width == 0 or source_height == 0 or
            source_width > pixel_width - source_x or source_height > pixel_height - source_y) return null;
        var destination_width = source_width;
        var destination_height = source_height;
        if (requested_cols != 0) {
            destination_width = std.math.mul(u32, requested_cols, cell_width) catch return null;
            if (destination_width <= cell_x) return null;
            destination_width -= cell_x;
        }
        if (requested_rows != 0) {
            destination_height = std.math.mul(u32, requested_rows, cell_height) catch return null;
            if (destination_height <= cell_y) return null;
            destination_height -= cell_y;
        }
        if (requested_cols == 0 and requested_rows != 0)
            destination_width = ceilRatio(destination_height, source_width, source_height) orelse return null;
        if (requested_rows == 0 and requested_cols != 0)
            destination_height = ceilRatio(destination_width, source_height, source_width) orelse return null;
        const occupied_cols = ceilRatio(
            1,
            std.math.add(u32, destination_width, cell_x) catch return null,
            cell_width,
        ) orelse return null;
        const occupied_rows = ceilRatio(
            1,
            std.math.add(u32, destination_height, cell_y) catch return null,
            cell_height,
        ) orelse return null;
        return .{
            .image_id = image_id,
            .kitty_id = kitty_id,
            .generation = placement_generation,
            .bank = bank,
            .row = row,
            .col = col,
            .source_x = source_x,
            .source_y = source_y,
            .source_width = source_width,
            .source_height = source_height,
            .cell_x = cell_x,
            .cell_y = cell_y,
            .pixel_width = destination_width,
            .pixel_height = destination_height,
            .z = z,
            .rows = @intCast(@min(occupied_rows, std.math.maxInt(u16))),
            .cols = @intCast(@min(occupied_cols, std.math.maxInt(u16))),
        };
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
        const image_id = self.placements[index].image_id;
        self.placement_count -= 1;
        if (index != self.placement_count) self.placements[index] = self.placements[self.placement_count];
        if (!self.hasPlacement(image_id)) {
            for (self.images[0..self.image_count]) |*image_value| {
                if (image_value.id == image_id) {
                    image_value.frame_started_ms = null;
                    break;
                }
            }
        }
    }

    fn removeImage(self: *Plane, index: usize) void {
        const removed = self.images[index];
        self.removeFrames(removed.id);
        self.storage_bytes -= removed.pixels.len;
        self.allocator.free(removed.pixels);
        self.image_count -= 1;
        if (index != self.image_count) self.images[index] = self.images[self.image_count];
    }

    fn removeFrames(self: *Plane, image_id: u32) void {
        var index: usize = 0;
        while (index < self.frame_count) {
            if (self.frames[index].image_id != image_id) {
                index += 1;
                continue;
            }
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
            self.frame_count -= 1;
            if (index != self.frame_count) self.frames[index] = self.frames[self.frame_count];
        }
    }

    fn removeFrameSlot(self: *Plane, index: usize, free_pixels: bool) void {
        if (free_pixels) {
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
        }
        self.frame_count -= 1;
        if (index != self.frame_count) self.frames[index] = self.frames[self.frame_count];
    }

    fn frameByNumber(self: *const Plane, image_id: u32, number: u16) ?*const Frame {
        for (self.frames[0..self.frame_count]) |*retained_frame|
            if (retained_frame.image_id == image_id and retained_frame.number == number) return retained_frame;
        return null;
    }

    fn framePixels(self: *const Plane, image_value: Image, number_value: u32) ?[]const u8 {
        const number = std.math.cast(u16, number_value) orelse return null;
        if (number == 1) return image_value.pixels;
        const retained = self.frameByNumber(image_value.id, number) orelse return null;
        return retained.pixels;
    }

    fn frameIndex(self: *const Plane, image_id: u32, number: u16) ?usize {
        for (self.frames[0..self.frame_count], 0..) |retained_frame, index|
            if (retained_frame.image_id == image_id and retained_frame.number == number) return index;
        return null;
    }

    fn frameCount(self: *const Plane, image_id: u32) u16 {
        var count: u16 = 0;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_id) count += 1;
        }
        return count;
    }

    fn frameBytes(self: *const Plane, image_id: u32) usize {
        var bytes: usize = 0;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_id) bytes += retained_frame.pixels.len;
        }
        return bytes;
    }

    fn animationDuration(self: *const Plane, image_value: Image) u64 {
        var duration: u64 = image_value.root_gap_ms;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_value.id) duration += retained_frame.gap_ms;
        }
        return duration;
    }

    fn nextFrameNumber(self: *const Plane, image_id: u32) ?u16 {
        const count = self.frameCount(image_id);
        if (count == std.math.maxInt(u16) - 1) return null;
        return count + 2;
    }

    fn lastFrameNumber(self: *const Plane, image_id: u32) u16 {
        return self.frameCount(image_id) + 1;
    }

    fn currentGap(self: *const Plane, image_value: Image) u32 {
        if (image_value.current_frame == 0) return image_value.root_gap_ms;
        return self.frameByNumber(image_value.id, image_value.current_frame + 1).?.gap_ms;
    }

    fn hasPlacement(self: *const Plane, image_id: u32) bool {
        for (self.placements[0..self.placement_count]) |value|
            if (value.image_id == image_id) return true;
        return false;
    }

    fn kittyImageIndex(self: *const Plane, id: u32) ?usize {
        for (self.images[0..self.image_count], 0..) |retained, index|
            if (retained.kitty_id == id) return index;
        return null;
    }

    fn kittyImageNumberIndex(self: *const Plane, number: u32) ?usize {
        var index: usize = self.image_count;
        while (index != 0) {
            index -= 1;
            if (self.images[index].kitty_number == number) return index;
        }
        return null;
    }

    fn kittyIdForImage(self: *const Plane, id: u32) ?u32 {
        for (self.images[0..self.image_count]) |retained|
            if (retained.id == id) return retained.kitty_id;
        return null;
    }

    fn kittyNumberForImage(self: *const Plane, id: u32) ?u32 {
        for (self.images[0..self.image_count]) |retained|
            if (retained.id == id) return retained.kitty_number;
        return null;
    }

    fn allocateKittyId(self: *const Plane) ?u32 {
        var candidate: u32 = 1;
        while (candidate != std.math.maxInt(u32)) : (candidate += 1)
            if (self.kittyImageIndex(candidate) == null) return candidate;
        return null;
    }

    fn allocateImageId(self: *Plane) u32 {
        if (self.next_image_id == std.math.maxInt(u32))
            @panic("terminal image identity exhausted");
        self.next_image_id += 1;
        return self.next_image_id;
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
            'x' => 1 << 9,
            'y' => 1 << 10,
            'p' => 1 << 11,
            'w' => 1 << 12,
            'h' => 1 << 13,
            'c' => 1 << 14,
            'r' => 1 << 15,
            'X' => 1 << 16,
            'Y' => 1 << 17,
            'z' => 1 << 18,
            'I' => 1 << 19,
            'C' => 1 << 20,
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
            'x' => result.x = std.fmt.parseInt(u32, value, 10) catch return null,
            'y' => result.y = std.fmt.parseInt(u32, value, 10) catch return null,
            'p' => result.placement_id = std.fmt.parseInt(u32, value, 10) catch return null,
            'w' => result.source_width = std.fmt.parseInt(u32, value, 10) catch return null,
            'h' => result.source_height = std.fmt.parseInt(u32, value, 10) catch return null,
            'c' => result.columns = std.fmt.parseInt(u32, value, 10) catch return null,
            'r' => result.rows = std.fmt.parseInt(u32, value, 10) catch return null,
            'X' => result.cell_x = std.fmt.parseInt(u32, value, 10) catch return null,
            'Y' => result.cell_y = std.fmt.parseInt(u32, value, 10) catch return null,
            'z' => result.z = std.fmt.parseInt(i32, value, 10) catch return null,
            'I' => result.image_number = std.fmt.parseInt(u32, value, 10) catch return null,
            'C' => {
                result.compose_mode = std.fmt.parseInt(u2, value, 10) catch return null;
                if (result.compose_mode > 1) return null;
            },
            else => return null,
        }
    }
    return result;
}

fn ceilRatio(a: u32, b: u32, divisor: u32) ?u32 {
    if (divisor == 0) return null;
    const product = std.math.mul(u64, a, b) catch return null;
    return @intCast((product + divisor - 1) / divisor);
}

fn rectanglesOverlap(
    source_x: u32,
    source_y: u32,
    destination_x: u32,
    destination_y: u32,
    width: u32,
    height: u32,
) bool {
    return @max(source_x, destination_x) < @min(source_x, destination_x) + width and
        @max(source_y, destination_y) < @min(source_y, destination_y) + height;
}

fn composeRgba(
    canvas: []u8,
    canvas_width: u32,
    source: []const u8,
    source_stride: u32,
    source_x: u32,
    source_y: u32,
    format: u8,
    width: u32,
    height: u32,
    offset_x: u32,
    offset_y: u32,
    blend: bool,
) void {
    const channels: usize = if (format == 24) 3 else 4;
    for (0..height) |y| {
        for (0..width) |x| {
            const source_offset = ((@as(usize, source_y) + y) * source_stride + source_x + x) * channels;
            const destination_offset = ((@as(usize, offset_y) + y) * canvas_width +
                offset_x + x) * 4;
            const alpha: u16 = if (format == 24) 255 else source[source_offset + 3];
            if (!blend or alpha == 255) {
                @memcpy(canvas[destination_offset..][0..3], source[source_offset..][0..3]);
                canvas[destination_offset + 3] = @intCast(alpha);
                continue;
            }
            if (alpha == 0) continue;
            const inverse: u32 = 255 - alpha;
            const destination_alpha: u32 = canvas[destination_offset + 3];
            const alpha_numerator: u32 = @as(u32, alpha) * 255 + destination_alpha * inverse;
            for (0..3) |channel| {
                const mixed = @as(u32, source[source_offset + channel]) * alpha * 255 +
                    @as(u32, canvas[destination_offset + channel]) * destination_alpha * inverse;
                canvas[destination_offset + channel] = @intCast(
                    (mixed + alpha_numerator / 2) / alpha_numerator,
                );
            }
            canvas[destination_offset + 3] = @intCast((alpha_numerator + 127) / 255);
        }
    }
}

fn deleteMatches(
    placement_value: Placement,
    kitty_id: ?u32,
    kitty_number: ?u32,
    selector: u8,
    command_value: Command,
    screen_origin: u64,
    cursor_row: u64,
    cursor_col: u16,
) bool {
    const bottom = placement_value.row + placement_value.rows - 1;
    const right = @as(u32, placement_value.col) + placement_value.cols - 1;
    const explicit_row = if (command_value.y == 0)
        null
    else
        std.math.add(u64, screen_origin, command_value.y - 1) catch null;
    return switch (selector) {
        'a' => true,
        'i' => kitty_id == command_value.id and
            (command_value.placement_id == 0 or placement_value.kitty_id == command_value.placement_id),
        'n' => kitty_number == command_value.image_number and
            (command_value.placement_id == 0 or placement_value.kitty_id == command_value.placement_id),
        'r' => if (kitty_id) |id| command_value.x <= id and id <= command_value.y else false,
        'p' => command_value.x != 0 and explicit_row != null and
            placement_value.col <= command_value.x - 1 and command_value.x - 1 <= right and
            placement_value.row <= explicit_row.? and explicit_row.? <= bottom,
        'q' => placement_value.z == command_value.z and command_value.x != 0 and explicit_row != null and
            placement_value.col <= command_value.x - 1 and command_value.x - 1 <= right and
            placement_value.row <= explicit_row.? and explicit_row.? <= bottom,
        'x' => command_value.x != 0 and
            placement_value.col <= command_value.x - 1 and command_value.x - 1 <= right,
        'y' => explicit_row != null and
            placement_value.row <= explicit_row.? and explicit_row.? <= bottom,
        'z' => placement_value.z == command_value.z,
        'c' => placement_value.col <= cursor_col and cursor_col <= right and
            placement_value.row <= cursor_row and cursor_row <= bottom,
        else => false,
    };
}

fn nonzero(value: u32) ?u32 {
    return if (value == 0) null else value;
}

test "static plane admission is transactional across chunks replacement put and delete" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const first = try plane.command("a=T,f=32,s=1,v=1,i=7,m=1;/wA=", .primary, 0, 4, 2, 1, 1);
    try std.testing.expect(!first.changed);
    const completed = try plane.command("m=0;AP8=", .primary, 0, 4, 2, 1, 1);
    try std.testing.expect(completed.changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    const generation = plane.generation();
    const malformed = try plane.command("a=t,f=32,s=1,v=1,i=8;%%", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, malformed.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expect((try plane.command("a=p,i=7", .alternate, 0, 1, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=I,i=7", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "RGB conversion quota cancellation and bank cleanup preserve exact ownership" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=24,s=1,v=1,i=1;AQID",
        .alternate,
        0,
        2,
        4,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, plane.image(0).?.pixels);
    try std.testing.expect(plane.clearBank(.alternate));
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    const before = plane.generation();
    const rejected = try plane.command("a=t,f=32,s=4096,v=4096,i=2;", .primary, 0, 0, 0, 1, 1);
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
        0,
        1,
        1,
    );
    try std.testing.expect(replacement.changed);
    try std.testing.expectEqual(@as(u32, 1), plane.image(0).?.id);
}

test "static delete selectors preserve placement and image ownership distinctions" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        10,
        11,
        2,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=1", .primary, 10, 13, 4, 1, 1)).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=2;BQYHCA==",
        .primary,
        10,
        12,
        5,
        1,
        1,
    )).changed);

    try std.testing.expect((try plane.command("a=d,d=p,x=3,y=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=C", .primary, 10, 13, 4, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u32, 2), plane.image(0).?.id);

    try std.testing.expect((try plane.command("a=d,d=i,i=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expect((try plane.command("a=p,i=2", .primary, 10, 12, 5, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=I,i=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=3;AQIDBA==",
        .primary,
        10,
        12,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=4;AQIDBA==",
        .primary,
        10,
        13,
        1,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=d,d=x,x=1", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=y,y=4", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=R,x=3,y=4", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=5;AQIDBA==",
        .primary,
        10,
        10,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=6;AQIDBA==",
        .primary,
        10,
        11,
        1,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=d", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=A", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
}

test "plane identities survive Kitty replacement and isolate decoded images from Kitty deletion" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=99;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const kitty_identity = plane.image(0).?.id;
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=99;BAIDAg==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(kitty_identity, plane.image(0).?.id);

    const decoded = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 });
    try plane.admitDecoded(decoded, 1, 1, .primary, 1, 1, 1, 1);
    const decoded_identity = plane.image(1).?.id;
    try std.testing.expect(decoded_identity != kitty_identity);
    try std.testing.expect((try plane.command("a=d,d=A", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
    try std.testing.expectEqual(decoded_identity, plane.image(0).?.id);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);

    const rejected = try std.testing.allocator.dupe(u8, &.{ 5, 6, 7, 8 });
    defer std.testing.allocator.free(rejected);
    const before = .{
        plane.image_count,
        plane.placement_count,
        plane.storage_bytes,
        plane.generation(),
        plane.imageGeneration(),
    };
    try std.testing.expectError(
        error.Quota,
        plane.admitDecoded(rejected, max_dimension + 1, 1, .primary, 0, 0, 1, 1),
    );
    try std.testing.expectEqualDeep(before, .{
        plane.image_count,
        plane.placement_count,
        plane.storage_bytes,
        plane.generation(),
        plane.imageGeneration(),
    });
}

test "Kitty placement identity replaces and deletes only the exact retained placement" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=9;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=9,p=4", .primary, 0, 2, 3, 1, 1)).changed);
    const first_generation = plane.placement(0).?.generation;
    try std.testing.expect((try plane.command("a=p,i=9,p=4", .primary, 0, 5, 6, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);
    try std.testing.expectEqual(@as(u64, 5), plane.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 6), plane.placement(0).?.col);
    try std.testing.expect(plane.placement(0).?.generation > first_generation);

    try std.testing.expect(!(try plane.command("a=d,d=i,i=9,p=3", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=i,i=9,p=4", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 0), plane.placement_count);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
}

test "Kitty crop destination offsets and layer preflight before placement mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=2,i=11;AQIDBAUGBwgJCgsMDQ4PEA==",
        .primary,
        0,
        0,
        0,
        8,
        16,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=p,i=11,p=3,x=1,y=0,w=1,h=2,c=2,r=3,X=2,Y=4,z=-7",
        .primary,
        0,
        4,
        5,
        8,
        16,
    )).changed);
    const placed = plane.placement(0).?;
    try std.testing.expectEqual(@as(u32, 1), placed.source_x);
    try std.testing.expectEqual(@as(u32, 1), placed.source_width);
    try std.testing.expectEqual(@as(u32, 14), placed.pixel_width);
    try std.testing.expectEqual(@as(u32, 44), placed.pixel_height);
    try std.testing.expectEqual(@as(i32, -7), placed.z);
    const generation = plane.next_generation;
    const unchanged = plane.placement(0).?;
    const invalid = try plane.command("a=p,i=11,p=3,x=2", .primary, 0, 7, 7, 8, 16);
    try std.testing.expectEqual(Failure.invalid, invalid.failure.?);
    try std.testing.expectEqual(generation, plane.next_generation);
    try std.testing.expectEqualDeep(unchanged, plane.placement(0).?);
}

test "Kitty z and point3d deletion preserve unmatched layers and image data" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=12;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=12,p=1,z=-2", .primary, 10, 10, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=p,i=12,p=2,z=4", .primary, 10, 10, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=q,x=4,y=1,z=-2", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);
    try std.testing.expectEqual(@as(i32, 4), plane.placement(0).?.z);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
    try std.testing.expect(!(try plane.command("a=d,d=z,z=-2", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=Z,z=4", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 0), plane.placement_count);
    try std.testing.expectEqual(@as(usize, 0), plane.image_count);
}

test "Kitty frames compose transactionally and advance on monotonic gaps" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=20;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const frame = try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=99,c=1,z=50;AAD/gA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(frame.changed);
    try std.testing.expect(!frame.visual_changed);
    try std.testing.expectEqual(@as(?u16, 2), frame.response_frame);
    try std.testing.expectEqual(@as(usize, 1), plane.frame_count);
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 128, 255 }, plane.frames[0].pixels);
    const generation_before_bad_composition = plane.generation();
    const bad_composition = try plane.command(
        "a=c,i=20,r=1,c=2,C=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, bad_composition.failure.?);
    try std.testing.expectEqual(generation_before_bad_composition, plane.generation());
    const generation_before_invalid_control = plane.generation();
    const invalid_control = try plane.command(
        "a=a,i=20,c=2,r=99,z=10",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.missing, invalid_control.failure.?);
    try std.testing.expectEqual(@as(u16, 0), plane.images[0].current_frame);
    try std.testing.expectEqual(generation_before_invalid_control, plane.generation());

    const started = plane.advanceAnimations(100);
    try std.testing.expect(!started.changed);
    try std.testing.expectEqual(@as(?u32, null), started.next_ms);
    try std.testing.expect((try plane.command(
        "a=a,i=20,s=3",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(100).next_ms);
    const second = plane.advanceAnimations(140);
    try std.testing.expect(second.changed);
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 128, 255 }, plane.image(0).?.pixels);
    const root = plane.advanceAnimations(190);
    try std.testing.expect(root.changed);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);

    try std.testing.expect((try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=3,C=1;AP8A/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=c,i=20,r=2,c=3",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const internal_id = plane.image(0).?.id;
    try std.testing.expectEqualSlices(u8, plane.frames[0].pixels, plane.frameByNumber(internal_id, 3).?.pixels);
    try std.testing.expect((try plane.command("a=d,d=f,i=20,r=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
    try std.testing.expect(plane.frameByNumber(internal_id, 2) != null);
    const bytes_before_root_edit = plane.storage_bytes;
    const root_prefix = try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=1,C=1,z=70,m=1;AAH+",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(!root_prefix.changed);
    const root_edit = try plane.command(
        "m=0;/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(root_edit.changed);
    try std.testing.expect(root_edit.visual_changed);
    try std.testing.expectEqual(@as(?u16, 1), root_edit.response_frame);
    try std.testing.expectEqual(bytes_before_root_edit, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 254, 255 }, plane.images[0].pixels);
    try std.testing.expectEqual(@as(u32, 70), plane.images[0].root_gap_ms);
    try std.testing.expect(plane.reset());
    try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
}

test "Kitty composition owns root and nonoverlapping same-frame edits" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=1,i=30,q=2;AQAA/wIAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=2,v=1,i=30,r=2,C=1,q=2;CgAA/xQAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const image_id = plane.image(0).?.id;
    const storage = plane.storage_bytes;
    const same = try plane.command(
        "a=c,i=30,r=2,c=2,s=1,v=1,x=1,X=0,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(same.changed);
    try std.testing.expect(!same.visual_changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 10, 0, 0, 255, 10, 0, 0, 255 },
        plane.frameByNumber(image_id, 2).?.pixels,
    );
    const generation = plane.generation();
    const overlap = try plane.command(
        "a=c,i=30,r=2,c=2,s=1,v=1,x=0,X=0,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, overlap.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(storage, plane.storage_bytes);
    const root = try plane.command(
        "a=c,i=30,r=2,c=1,s=1,v=1,x=0,X=1,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(root.changed);
    try std.testing.expect(root.visual_changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 10, 0, 0, 255, 2, 0, 0, 255 },
        plane.images[0].pixels,
    );
    try std.testing.expectEqual(storage, plane.storage_bytes);
}

test "Kitty frame deletion defaults to root and uppercase retires frame-less image" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=40,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=40,r=2,C=1,q=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const after_root = try plane.command("a=d,d=f,i=40", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(after_root.changed);
    try std.testing.expect(after_root.visual_changed);
    try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.image(0).?.pixels);
    try std.testing.expect(!(try plane.command("a=d,d=f,i=40", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=F,i=40", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
}

test "Kitty animation requires a placement and nonzero total duration" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=41,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=41,r=2,z=-1,C=1,q=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=a,i=41,s=3,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(100).next_ms);
    try std.testing.expect((try plane.command("a=p,i=41,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(100).next_ms);
    try std.testing.expect((try plane.command("a=d,d=a", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(1000).next_ms);
    try std.testing.expect((try plane.command("a=p,i=41,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(1000).next_ms);
    try std.testing.expect((try plane.command(
        "a=a,i=41,r=1,z=-1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(200).next_ms);
}

test "static image allocation failure leaves the plane reusable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, frameAllocationFailure, .{});
}

test "Kitty frame capacity rejects the next frame without retained mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=70,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    var number: usize = 2;
    while (number < max_frames + 2) : (number += 1) {
        var command_bytes: [80]u8 = undefined;
        const command_value = try std.fmt.bufPrint(
            &command_bytes,
            "a=f,f=32,s=1,v=1,i=70,r={d},q=2;BQYHCA==",
            .{number},
        );
        try std.testing.expect((try plane.command(
            command_value,
            .primary,
            0,
            0,
            0,
            1,
            1,
        )).changed);
    }
    const generation = plane.generation();
    const bytes = plane.storage_bytes;
    const rejected = try plane.command(
        "a=f,f=32,s=1,v=1,i=70,r=258,q=2;CQoLDA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.quota, rejected.failure.?);
    try std.testing.expectEqual(@as(u16, max_frames), plane.frame_count);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(bytes, plane.storage_bytes);
}

fn frameAllocationFailure(allocator: std.mem.Allocator) !void {
    var plane = Plane.init(allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const before = plane.storage_bytes;
    try std.testing.expect((try plane.command(
        "a=f,f=32,i=1,s=1,v=1;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(before + 4, plane.storage_bytes);
    const with_frame = plane.storage_bytes;
    try std.testing.expect((try plane.command(
        "a=f,f=32,i=1,s=1,v=1,r=1,C=1;CQoLDA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(with_frame, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 9, 10, 11, 12 }, plane.images[0].pixels);
    try std.testing.expect((try plane.command(
        "a=c,i=1,r=2,c=1,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(with_frame, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.images[0].pixels);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var plane = Plane.init(allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
}
