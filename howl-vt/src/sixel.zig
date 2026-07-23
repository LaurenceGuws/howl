//! Decodes one bounded Sixel payload into caller-owned RGBA pixels.

const std = @import("std");
const graphics = @import("graphics.zig");

/// Bounds one retained encoded Sixel command independently of generic DCS.
pub const max_encoded_bytes: usize = 16 * 1024 * 1024;

/// Owns one decoded image until transferred to the terminal image plane.
pub const Image = struct {
    pixels: []u8,
    width: u32,
    height: u32,

    /// Releases decoded pixels through their originating allocator.
    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

/// Reports exact bounded decoder failure.
pub const Error = std.mem.Allocator.Error || error{ Invalid, Unsupported, Quota };

const Extent = struct {
    width: u32 = 0,
    height: u32 = 0,
};

/// Decodes a complete unescaped Sixel payload transactionally.
///
/// Howl accepts RGB percentage color definitions and rejects HLS rather than
/// approximating it. `transparent` selects alpha-zero or opaque-black
/// unpainted pixels from the DCS background parameter.
pub fn decode(allocator: std.mem.Allocator, payload: []const u8, transparent: bool) Error!Image {
    if (payload.len > max_encoded_bytes) return error.Quota;
    const extent = try walk(payload, null);
    if (extent.width == 0 or extent.height == 0 or
        extent.width > graphics.max_dimension or extent.height > graphics.max_dimension)
        return error.Quota;
    const pixel_count = std.math.mul(usize, extent.width, extent.height) catch return error.Quota;
    const byte_count = std.math.mul(usize, pixel_count, 4) catch return error.Quota;
    if (byte_count > graphics.max_image_bytes) return error.Quota;
    const pixels = try allocator.alloc(u8, byte_count);
    errdefer allocator.free(pixels);
    if (transparent) {
        @memset(pixels, 0);
    } else {
        const background = [4]u8{ 0, 0, 0, 255 };
        var offset: usize = 0;
        while (offset < pixels.len) : (offset += 4)
            @memcpy(pixels[offset..][0..4], &background);
    }
    const painted = try walk(payload, .{ .pixels = pixels, .width = extent.width, .height = extent.height });
    std.debug.assert(std.meta.eql(extent, painted));
    return .{ .pixels = pixels, .width = extent.width, .height = extent.height };
}

const Canvas = struct {
    pixels: []u8,
    width: u32,
    height: u32,
};

fn walk(payload: []const u8, canvas: ?Canvas) Error!Extent {
    var palette = [_][4]u8{.{ 0, 0, 0, 255 }} ** 256;
    var color: u8 = 0;
    var x: u32 = 0;
    var y: u32 = 0;
    var extent: Extent = .{};
    var aspect_1_1 = false;
    var index: usize = 0;
    while (index < payload.len) {
        const byte = payload[index];
        switch (byte) {
            '?'...'~' => {
                if (!aspect_1_1) return error.Unsupported;
                try paintColumn(canvas, x, y, byte - '?', palette[color], &extent);
                x = std.math.add(u32, x, 1) catch return error.Quota;
                index += 1;
            },
            '!' => {
                if (!aspect_1_1) return error.Unsupported;
                index += 1;
                const repeat = parseNumber(payload, &index) orelse return error.Invalid;
                if (repeat == 0 or index >= payload.len or payload[index] < '?' or payload[index] > '~')
                    return error.Invalid;
                const bits = payload[index] - '?';
                var count: u32 = 0;
                while (count < repeat) : (count += 1) {
                    try paintColumn(canvas, x, y, bits, palette[color], &extent);
                    x = std.math.add(u32, x, 1) catch return error.Quota;
                }
                index += 1;
            },
            '$' => {
                x = 0;
                index += 1;
            },
            '-' => {
                x = 0;
                y = std.math.add(u32, y, 6) catch return error.Quota;
                index += 1;
            },
            '#' => {
                index += 1;
                const selected = parseNumber(payload, &index) orelse return error.Invalid;
                if (selected > 255) return error.Unsupported;
                color = @intCast(selected);
                if (index < payload.len and payload[index] == ';') {
                    index += 1;
                    const system = parseNumber(payload, &index) orelse return error.Invalid;
                    if (system != 2) return error.Unsupported;
                    var component: usize = 0;
                    while (component < 3) : (component += 1) {
                        if (index >= payload.len or payload[index] != ';') return error.Invalid;
                        index += 1;
                        const percentage = parseNumber(payload, &index) orelse return error.Invalid;
                        if (percentage > 100) return error.Invalid;
                        palette[color][component] = @intCast((percentage * 255 + 50) / 100);
                    }
                    palette[color][3] = 255;
                }
            },
            '"' => {
                index += 1;
                const pan = parseNumber(payload, &index) orelse return error.Invalid;
                if (index >= payload.len or payload[index] != ';') return error.Invalid;
                index += 1;
                const pad = parseNumber(payload, &index) orelse return error.Invalid;
                if (pan == 0 or pad == 0) return error.Invalid;
                if (pan != 1 or pad != 1) return error.Unsupported;
                aspect_1_1 = true;
                if (index < payload.len and payload[index] == ';') {
                    index += 1;
                    const width = parseNumber(payload, &index) orelse return error.Invalid;
                    if (index >= payload.len or payload[index] != ';') return error.Invalid;
                    index += 1;
                    const height = parseNumber(payload, &index) orelse return error.Invalid;
                    extent.width = @max(extent.width, width);
                    extent.height = @max(extent.height, height);
                }
            },
            else => return error.Invalid,
        }
        if (extent.width > graphics.max_dimension or extent.height > graphics.max_dimension)
            return error.Quota;
    }
    return extent;
}

fn paintColumn(
    canvas: ?Canvas,
    x: u32,
    y: u32,
    bits: u8,
    color: [4]u8,
    extent: *Extent,
) Error!void {
    const bottom = std.math.add(u32, y, 6) catch return error.Quota;
    extent.width = @max(extent.width, std.math.add(u32, x, 1) catch return error.Quota);
    extent.height = @max(extent.height, bottom);
    if (canvas) |target| {
        var bit: u3 = 0;
        while (bit < 6) : (bit += 1) {
            if (bits & (@as(u8, 1) << bit) == 0) continue;
            const py = y + bit;
            if (x >= target.width or py >= target.height) continue;
            const offset = (@as(usize, py) * target.width + x) * 4;
            @memcpy(target.pixels[offset..][0..4], &color);
        }
    }
}

fn parseNumber(bytes: []const u8, index: *usize) ?u32 {
    const start = index.*;
    var value: u32 = 0;
    while (index.* < bytes.len and std.ascii.isDigit(bytes[index.*])) : (index.* += 1) {
        value = std.math.mul(u32, value, 10) catch return null;
        value = std.math.add(u32, value, bytes[index.*] - '0') catch return null;
    }
    return if (index.* == start) null else value;
}

test "Sixel decoder measures paints repeats colors and rolls back bounds" {
    const allocator = std.testing.allocator;
    var image = try decode(allocator, "\"1;1;3;6#1;2;100;0;0!3~-#2;2;0;100;0!2~", true);
    defer image.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), image.width);
    try std.testing.expectEqual(@as(u32, 12), image.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, image.pixels[0..4]);
    const green = (@as(usize, 6) * image.width) * 4;
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, image.pixels[green..][0..4]);
    try std.testing.expectError(error.Unsupported, decode(allocator, "\"1;1#1;1;0;0;0;0~", false));
    try std.testing.expectError(error.Invalid, decode(allocator, "\"1;1!0~", false));
    try std.testing.expectError(error.Quota, decode(allocator, "\"1;1;4097;1~", false));
    try std.testing.expectError(error.Unsupported, decode(allocator, "~", false));

    const opaque_image = try decode(allocator, "\"1;1;2;6~", false);
    defer opaque_image.deinit(allocator);
    const transparent = try decode(allocator, "\"1;1;2;6~", true);
    defer transparent.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 255), opaque_image.pixels[7]);
    try std.testing.expectEqual(@as(u8, 0), transparent.pixels[7]);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    const image = try decode(allocator, "\"1;1;3;6#1;2;100;0;0!3~", false);
    image.deinit(allocator);
}

test "Sixel decoder releases every allocation failure boundary" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}
