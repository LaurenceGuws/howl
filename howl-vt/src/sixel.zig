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

/// Selects DCS-level Sixel aspect and background behavior.
pub const Options = struct {
    pan: u3,
    pad: u3,
    transparent: bool,
};

const Extent = struct {
    width: u32 = 0,
    height: u32 = 0,
};

/// Decodes a complete unescaped Sixel payload transactionally.
///
/// Howl accepts RGB percentage color definitions and rejects HLS rather than
/// approximating it. `transparent` selects alpha-zero or opaque-black
/// unpainted pixels from the DCS background parameter.
pub fn decode(allocator: std.mem.Allocator, payload: []const u8, options: Options) Error!Image {
    if (payload.len > max_encoded_bytes) return error.Quota;
    if (options.pan == 0 or options.pan > 5 or options.pad == 0 or options.pad > 5)
        return error.Invalid;
    const extent = try walk(payload, options, null);
    if (extent.width == 0 or extent.height == 0 or
        extent.width > graphics.max_dimension or extent.height > graphics.max_dimension)
        return error.Quota;
    const pixel_count = std.math.mul(usize, extent.width, extent.height) catch return error.Quota;
    const byte_count = std.math.mul(usize, pixel_count, 4) catch return error.Quota;
    if (byte_count > graphics.max_image_bytes) return error.Quota;
    const pixels = try allocator.alloc(u8, byte_count);
    errdefer allocator.free(pixels);
    if (options.transparent) {
        @memset(pixels, 0);
    } else {
        const background = [4]u8{ 0, 0, 0, 255 };
        var offset: usize = 0;
        while (offset < pixels.len) : (offset += 4)
            @memcpy(pixels[offset..][0..4], &background);
    }
    const painted = try walk(
        payload,
        options,
        .{ .pixels = pixels, .width = extent.width, .height = extent.height },
    );
    std.debug.assert(std.meta.eql(extent, painted));
    return .{ .pixels = pixels, .width = extent.width, .height = extent.height };
}

const Canvas = struct {
    pixels: []u8,
    width: u32,
    height: u32,
};

fn walk(payload: []const u8, options: Options, canvas: ?Canvas) Error!Extent {
    var palette = defaultPalette();
    var color: u8 = 0;
    var x: u32 = 0;
    var y: u32 = 0;
    var extent: Extent = .{};
    var pan: u3 = options.pan;
    var pad: u3 = options.pad;
    var painted = false;
    var index: usize = 0;
    while (index < payload.len) {
        const byte = payload[index];
        switch (byte) {
            '?'...'~' => {
                try paintColumn(canvas, x, y, byte - '?', palette[color], pan, pad, &extent);
                x = std.math.add(u32, x, pad) catch return error.Quota;
                painted = true;
                index += 1;
            },
            '!' => {
                index += 1;
                const repeat = parseNumber(payload, &index) orelse return error.Invalid;
                if (repeat == 0 or index >= payload.len or payload[index] < '?' or payload[index] > '~')
                    return error.Invalid;
                const bits = payload[index] - '?';
                var count: u32 = 0;
                while (count < repeat) : (count += 1) {
                    try paintColumn(canvas, x, y, bits, palette[color], pan, pad, &extent);
                    x = std.math.add(u32, x, pad) catch return error.Quota;
                }
                painted = true;
                index += 1;
            },
            '$' => {
                x = 0;
                index += 1;
            },
            '-' => {
                x = 0;
                y = std.math.add(u32, y, @as(u32, pan) * 6) catch return error.Quota;
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
                    if (system != 1 and system != 2) return error.Unsupported;
                    var values: [3]u32 = undefined;
                    var component: usize = 0;
                    while (component < 3) : (component += 1) {
                        if (index >= payload.len or payload[index] != ';') return error.Invalid;
                        index += 1;
                        const percentage = parseNumber(payload, &index) orelse return error.Invalid;
                        if ((system == 1 and component == 0 and percentage > 360) or
                            (system == 1 and component != 0 and percentage > 100) or
                            (system == 2 and percentage > 100))
                            return error.Invalid;
                        values[component] = percentage;
                    }
                    palette[color] = if (system == 1)
                        hls(values[0], values[1], values[2])
                    else
                        .{
                            percent(values[0]),
                            percent(values[1]),
                            percent(values[2]),
                            255,
                        };
                }
            },
            '"' => {
                index += 1;
                const raw_pan = parseNumber(payload, &index) orelse return error.Invalid;
                if (index >= payload.len or payload[index] != ';') return error.Invalid;
                index += 1;
                const raw_pad = parseNumber(payload, &index) orelse return error.Invalid;
                const next_pan: u3 = @intCast(@min(if (raw_pan == 0) 1 else raw_pan, 5));
                const next_pad: u3 = @intCast(@min(if (raw_pad == 0) 1 else raw_pad, 5));
                if (painted and (next_pan != pan or next_pad != pad)) return error.Unsupported;
                pan = next_pan;
                pad = next_pad;
                if (index < payload.len and payload[index] == ';') {
                    index += 1;
                    const width = parseNumber(payload, &index) orelse return error.Invalid;
                    if (index >= payload.len or payload[index] != ';') return error.Invalid;
                    index += 1;
                    const height = parseNumber(payload, &index) orelse return error.Invalid;
                    extent.width = @max(
                        extent.width,
                        std.math.mul(u32, width, pad) catch return error.Quota,
                    );
                    extent.height = @max(
                        extent.height,
                        std.math.mul(u32, height, pan) catch return error.Quota,
                    );
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
    pan: u3,
    pad: u3,
    extent: *Extent,
) Error!void {
    const bottom = std.math.add(u32, y, @as(u32, pan) * 6) catch return error.Quota;
    extent.width = @max(extent.width, std.math.add(u32, x, pad) catch return error.Quota);
    extent.height = @max(extent.height, bottom);
    if (canvas) |target| {
        var bit: u3 = 0;
        while (bit < 6) : (bit += 1) {
            if (bits & (@as(u8, 1) << bit) == 0) continue;
            var dy: u3 = 0;
            while (dy < pan) : (dy += 1) {
                const py = y + @as(u32, bit) * pan + dy;
                var dx: u3 = 0;
                while (dx < pad) : (dx += 1) {
                    const px = x + dx;
                    if (px >= target.width or py >= target.height) continue;
                    const offset = (@as(usize, py) * target.width + px) * 4;
                    @memcpy(target.pixels[offset..][0..4], &color);
                }
            }
        }
    }
}

fn percent(value: u32) u8 {
    return @intCast((value * 255) / 100);
}

fn hls(hue_value: u32, lightness: u32, saturation: u32) [4]u8 {
    const hue = (hue_value + 240) % 360;
    if (saturation == 0) {
        const gray = percent(lightness);
        return .{ gray, gray, gray, 255 };
    }
    const l: i32 = @intCast(lightness);
    const s: i32 = @intCast(saturation);
    const max_value = if (l <= 50)
        @divTrunc(l * (100 + s), 100)
    else
        l + s - @divTrunc(l * s, 100);
    const min_value = 2 * l - max_value;
    return .{
        hueChannel(min_value, max_value, @as(i32, @intCast(hue)) + 120),
        hueChannel(min_value, max_value, @intCast(hue)),
        hueChannel(min_value, max_value, @as(i32, @intCast(hue)) - 120),
        255,
    };
}

fn hueChannel(min_value: i32, max_value: i32, hue_value: i32) u8 {
    const hue = @mod(hue_value, 360);
    const value = if (hue < 60)
        min_value + @divTrunc((max_value - min_value) * hue, 60)
    else if (hue < 180)
        max_value
    else if (hue < 240)
        min_value + @divTrunc((max_value - min_value) * (240 - hue), 60)
    else
        min_value;
    return @intCast(@divTrunc(value * 255, 100));
}

fn defaultPalette() [256][4]u8 {
    var palette = [_][4]u8{.{ 0, 0, 0, 255 }} ** 256;
    palette[0..16].* = .{
        .{ 0x00, 0x00, 0x00, 0xff }, .{ 0x33, 0x33, 0xcc, 0xff },
        .{ 0xcc, 0x21, 0x21, 0xff }, .{ 0x33, 0xcc, 0x33, 0xff },
        .{ 0xcc, 0x33, 0xcc, 0xff }, .{ 0x33, 0xcc, 0xcc, 0xff },
        .{ 0xcc, 0xcc, 0x33, 0xff }, .{ 0x87, 0x87, 0x87, 0xff },
        .{ 0x42, 0x42, 0x42, 0xff }, .{ 0x54, 0x54, 0x99, 0xff },
        .{ 0x99, 0x42, 0x42, 0xff }, .{ 0x54, 0x99, 0x54, 0xff },
        .{ 0x99, 0x54, 0x99, 0xff }, .{ 0x54, 0x99, 0x99, 0xff },
        .{ 0x99, 0x99, 0x54, 0xff }, .{ 0xcc, 0xcc, 0xcc, 0xff },
    };
    return palette;
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
    const options: Options = .{ .pan = 1, .pad = 1, .transparent = true };
    var image = try decode(allocator, "\"1;1;3;6#1;2;100;0;0!3~-#2;2;0;100;0!2~", options);
    defer image.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), image.width);
    try std.testing.expectEqual(@as(u32, 12), image.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, image.pixels[0..4]);
    const green = (@as(usize, 6) * image.width) * 4;
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, image.pixels[green..][0..4]);
    try std.testing.expectError(error.Invalid, decode(allocator, "\"1;1!0~", options));
    try std.testing.expectError(error.Quota, decode(allocator, "\"1;1;4097;1~", options));
    try std.testing.expectError(error.Unsupported, decode(allocator, "~\"2;1~", options));

    const opaque_image = try decode(
        allocator,
        "\"1;1;2;6~",
        .{ .pan = 1, .pad = 1, .transparent = false },
    );
    defer opaque_image.deinit(allocator);
    const transparent = try decode(allocator, "\"1;1;2;6~", options);
    defer transparent.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 255), opaque_image.pixels[7]);
    try std.testing.expectEqual(@as(u8, 0), transparent.pixels[7]);

    const scaled = try decode(
        allocator,
        "#1;1;120;50;100~",
        .{ .pan = 2, .pad = 3, .transparent = true },
    );
    defer scaled.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), scaled.width);
    try std.testing.expectEqual(@as(u32, 12), scaled.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, scaled.pixels[0..4]);

    const default_color = try decode(allocator, "#2~", options);
    defer default_color.deinit(allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0xcc, 0x21, 0x21, 0xff }, default_color.pixels[0..4]);
    try std.testing.expectError(
        error.Invalid,
        decode(allocator, "~", .{ .pan = 0, .pad = 1, .transparent = false }),
    );
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    const image = try decode(
        allocator,
        "\"1;1;3;6#1;2;100;0;0!3~",
        .{ .pan = 1, .pad = 1, .transparent = false },
    );
    image.deinit(allocator);
}

test "Sixel decoder releases every allocation failure boundary" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}
