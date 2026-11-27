//! Decodes bounded PNG pixels into the terminal's canonical RGBA8 image.
//! No image data, decompression state, or allocations survive a failed decode.

const std = @import("std");

/// Rejects malformed, unsupported, or oversized PNG without retaining pixels.
pub const DecodeError = error{ Invalid, Unsupported, Quota } || std.mem.Allocator.Error;

/// Owns the decoded RGBA buffer; the caller must release `pixels`.
pub const Image = struct {
    width: u32,
    height: u32,
    pixels: []u8,
};

const signature = "\x89PNG\r\n\x1a\n";
const max_dimension: u32 = 4096;
const max_pixels_bytes: usize = 16 * 1024 * 1024;
/// Maximum encoded PNG bytes accepted by the shared decoder.
pub const max_encoded_bytes: usize = max_pixels_bytes + 128 * 1024;

const Header = struct {
    width: u32,
    height: u32,
    depth: u8,
    color: u8,
    interlace: u8,
    channels: u8,
    palette: [256][4]u8 = undefined,
    palette_count: usize = 0,
    transparent_gray: ?u16 = null,
    transparent_rgb: ?[3]u16 = null,
};

const Pass = struct {
    x: u8,
    y: u8,
    dx: u8,
    dy: u8,
};

const adam7 = [_]Pass{
    .{ .x = 0, .y = 0, .dx = 8, .dy = 8 },
    .{ .x = 4, .y = 0, .dx = 8, .dy = 8 },
    .{ .x = 0, .y = 4, .dx = 4, .dy = 8 },
    .{ .x = 2, .y = 0, .dx = 4, .dy = 4 },
    .{ .x = 0, .y = 2, .dx = 2, .dy = 4 },
    .{ .x = 1, .y = 0, .dx = 2, .dy = 2 },
    .{ .x = 0, .y = 1, .dx = 1, .dy = 2 },
};

/// Validates PNG framing and bounded zlib scanlines before returning RGBA8.
pub fn decode(allocator: std.mem.Allocator, encoded: []const u8) DecodeError!Image {
    if (encoded.len > max_encoded_bytes) return error.Quota;
    if (!std.mem.startsWith(u8, encoded, signature)) return error.Invalid;
    var cursor: usize = signature.len;
    var header: ?Header = null;
    var saw_palette = false;
    var saw_transparency = false;
    var saw_idat = false;
    var after_idat = false;
    var finished = false;
    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(allocator);

    while (cursor < encoded.len) {
        if (encoded.len - cursor < 12) return error.Invalid;
        const size = std.mem.readInt(u32, encoded[cursor..][0..4], .big);
        const count: usize = size;
        if (count > encoded.len - cursor - 12) return error.Invalid;
        const kind = encoded[cursor + 4 ..][0..4];
        const data = encoded[cursor + 8 ..][0..count];
        const checksum = std.mem.readInt(u32, encoded[cursor + 8 + count ..][0..4], .big);
        var crc = std.hash.Crc32.init();
        crc.update(kind);
        crc.update(data);
        if (crc.final() != checksum) return error.Invalid;
        cursor += count + 12;

        if (header == null and !std.mem.eql(u8, kind, "IHDR")) return error.Invalid;
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (header != null or count != 13) return error.Invalid;
            const width = std.mem.readInt(u32, data[0..4], .big);
            const height = std.mem.readInt(u32, data[4..8], .big);
            const depth = data[8];
            const color = data[9];
            const channels: u8 = switch (color) {
                0 => 1,
                2 => 3,
                3 => 1,
                4 => 2,
                6 => 4,
                else => return error.Unsupported,
            };
            const supported_depth = switch (color) {
                0, 3 => depth == 1 or depth == 2 or depth == 4 or depth == 8 or (color == 0 and depth == 16),
                2, 4, 6 => depth == 8 or depth == 16,
                else => false,
            };
            if (!supported_depth) return error.Unsupported;
            if (width == 0 or height == 0 or width > max_dimension or height > max_dimension)
                return error.Quota;
            if (@as(u64, width) * height * 4 > max_pixels_bytes) return error.Quota;
            if (data[10] != 0 or data[11] != 0 or data[12] > 1) return error.Unsupported;
            header = .{
                .width = width,
                .height = height,
                .depth = depth,
                .color = color,
                .interlace = data[12],
                .channels = channels,
            };
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            if (saw_palette or saw_idat or count == 0 or count > 768 or count % 3 != 0)
                return error.Invalid;
            if (header.?.color == 0 or header.?.color == 4) return error.Invalid;
            const entries = count / 3;
            if (header.?.color == 3 and entries > (@as(usize, 1) << @intCast(header.?.depth)))
                return error.Invalid;
            for (0..entries) |index| {
                header.?.palette[index] = .{ data[index * 3], data[index * 3 + 1], data[index * 3 + 2], 255 };
            }
            header.?.palette_count = entries;
            saw_palette = true;
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            if (saw_transparency or saw_idat) return error.Invalid;
            switch (header.?.color) {
                0 => {
                    if (count != 2) return error.Invalid;
                    header.?.transparent_gray = std.mem.readInt(u16, data[0..2], .big);
                },
                2 => {
                    if (count != 6) return error.Invalid;
                    header.?.transparent_rgb = .{
                        std.mem.readInt(u16, data[0..2], .big),
                        std.mem.readInt(u16, data[2..4], .big),
                        std.mem.readInt(u16, data[4..6], .big),
                    };
                },
                3 => {
                    if (!saw_palette or count > header.?.palette_count) return error.Invalid;
                    for (data, 0..) |alpha, index| header.?.palette[index][3] = alpha;
                },
                else => return error.Invalid,
            }
            saw_transparency = true;
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            if (after_idat or header.?.color == 3 and !saw_palette) return error.Invalid;
            saw_idat = true;
            if (count > max_encoded_bytes - compressed.items.len) return error.Quota;
            try compressed.appendSlice(allocator, data);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            if (!saw_idat or count != 0 or cursor != encoded.len) return error.Invalid;
            finished = true;
            break;
        } else if (kind[0] & 0x20 == 0) {
            // Unknown critical chunks change pixel semantics; never guess.
            return error.Unsupported;
        }
        if (saw_idat and !std.mem.eql(u8, kind, "IDAT")) after_idat = true;
    }
    if (!finished) return error.Invalid;
    return try decodePixels(allocator, header.?, compressed.items);
}

fn passCount(limit: u32, start: u8, stride: u8) usize {
    if (limit <= start) return 0;
    return (@as(usize, limit - start) + stride - 1) / stride;
}

fn lineBytes(width: usize, header: Header) usize {
    return (width * header.channels * header.depth + 7) / 8;
}

fn decodePixels(allocator: std.mem.Allocator, header: Header, compressed: []const u8) DecodeError!Image {
    const passes = if (header.interlace == 1) adam7[0..] else &[_]Pass{.{ .x = 0, .y = 0, .dx = 1, .dy = 1 }};
    var inflated_bytes: usize = 0;
    for (passes) |pass| {
        const width = passCount(header.width, pass.x, pass.dx);
        const height = passCount(header.height, pass.y, pass.dy);
        if (width == 0 or height == 0) continue;
        inflated_bytes += height * (1 + lineBytes(width, header));
    }
    if (inflated_bytes > max_encoded_bytes) return error.Quota;
    const filtered = try allocator.alloc(u8, inflated_bytes);
    defer allocator.free(filtered);
    const work = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(work);
    var output: std.Io.Writer = .fixed(filtered);
    var input: std.Io.Reader = .fixed(compressed);
    var decompressor: std.compress.flate.Decompress = .init(&input, .zlib, work);
    const read = decompressor.reader.streamRemaining(&output) catch return error.Invalid;
    if (read != inflated_bytes or output.buffered().len != inflated_bytes or input.seek != input.end)
        return error.Invalid;
    if (std.hash.Adler32.hash(filtered) != decompressor.container_metadata.zlib.adler)
        return error.Invalid;

    const rgba = try allocator.alloc(u8, @as(usize, header.width) * header.height * 4);
    errdefer allocator.free(rgba);
    var offset: usize = 0;
    const filter_bpp = @max(1, (@as(usize, header.channels) * header.depth + 7) / 8);
    for (passes) |pass| {
        const width = passCount(header.width, pass.x, pass.dx);
        const height = passCount(header.height, pass.y, pass.dy);
        if (width == 0 or height == 0) continue;
        const bytes_per_line = lineBytes(width, header);
        var previous: ?[]const u8 = null;
        for (0..height) |y| {
            const filter = filtered[offset];
            const line = filtered[offset + 1 ..][0..bytes_per_line];
            for (line, 0..) |*value, index| {
                const left: u8 = if (index < filter_bpp) 0 else line[index - filter_bpp];
                const above: u8 = if (previous) |row| row[index] else 0;
                const upper_left: u8 = if (previous) |row|
                    (if (index < filter_bpp) @as(u8, 0) else row[index - filter_bpp])
                else
                    0;
                const prediction: u8 = switch (filter) {
                    0 => 0,
                    1 => left,
                    2 => above,
                    3 => @intCast((@as(u16, left) + above) / 2),
                    4 => paeth(left, above, upper_left),
                    else => return error.Invalid,
                };
                value.* +%= prediction;
            }
            for (0..width) |x| {
                const pixel = try pixelRgba(header, line, x);
                const destination_x = @as(usize, pass.x) + x * pass.dx;
                const destination_y = @as(usize, pass.y) + y * pass.dy;
                const destination = (destination_y * header.width + destination_x) * 4;
                @memcpy(rgba[destination..][0..4], &pixel);
            }
            previous = line;
            offset += 1 + bytes_per_line;
        }
    }
    return .{ .width = header.width, .height = header.height, .pixels = rgba };
}

fn paeth(left: u8, above: u8, upper_left: u8) u8 {
    const a: i32 = left;
    const b: i32 = above;
    const c: i32 = upper_left;
    const p = a + b - c;
    const da = @abs(p - a);
    const db = @abs(p - b);
    const dc = @abs(p - c);
    return if (da <= db and da <= dc) left else if (db <= dc) above else upper_left;
}

fn sample(header: Header, line: []const u8, x: usize, channel: usize) u16 {
    const index = x * header.channels + channel;
    if (header.depth == 16) return std.mem.readInt(u16, line[index * 2 ..][0..2], .big);
    if (header.depth == 8) return line[index];
    const per_byte: usize = 8 / header.depth;
    const shift: u3 = @intCast((per_byte - 1 - (index % per_byte)) * header.depth);
    return (line[index / per_byte] >> shift) & ((@as(u16, 1) << @intCast(header.depth)) - 1);
}

fn toByte(depth: u8, value: u16) u8 {
    if (depth == 16) return @truncate(value >> 8);
    if (depth == 8) return @intCast(value);
    const maximum = (@as(u16, 1) << @intCast(depth)) - 1;
    return @intCast(value * 255 / maximum);
}

fn pixelRgba(header: Header, line: []const u8, x: usize) DecodeError![4]u8 {
    const first = sample(header, line, x, 0);
    return switch (header.color) {
        0 => .{ toByte(header.depth, first), toByte(header.depth, first), toByte(header.depth, first), if (header.transparent_gray == first) 0 else 255 },
        2 => blk: {
            const second = sample(header, line, x, 1);
            const third = sample(header, line, x, 2);
            break :blk .{ toByte(header.depth, first), toByte(header.depth, second), toByte(header.depth, third), if (header.transparent_rgb) |transparent|
                (if (std.mem.eql(u16, &transparent, &.{ first, second, third })) @as(u8, 0) else 255)
            else
                255 };
        },
        3 => if (first < header.palette_count) header.palette[first] else error.Invalid,
        4 => .{ toByte(header.depth, first), toByte(header.depth, first), toByte(header.depth, first), toByte(header.depth, sample(header, line, x, 1)) },
        6 => .{ toByte(header.depth, first), toByte(header.depth, sample(header, line, x, 1)), toByte(header.depth, sample(header, line, x, 2)), toByte(header.depth, sample(header, line, x, 3)) },
        else => error.Unsupported,
    };
}

fn fixture(allocator: std.mem.Allocator, base64: []const u8) ![]u8 {
    const size = try std.base64.standard.Decoder.calcSizeForSlice(base64);
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);
    try std.base64.standard.Decoder.decode(bytes, base64);
    return bytes;
}

test "PNG RGBA RGB indexed grayscale and Adam7 restore exact pixels" {
    const allocator = std.testing.allocator;
    const samples = .{
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=", &[_]u8{ 255, 0, 0, 255, 0, 0, 255, 255 } },
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVQI12P4z8DAwPAfAAcAAf921adgAAAAAElFTkSuQmCC", &[_]u8{ 255, 0, 0, 255, 0, 0, 255, 255 } },
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAMAAADD/I+4AAAABlBMVEX/AAAAAP9sof2OAAAAC0lEQVQI12NgYAQAAAQAAicCke4AAAAASUVORK5CYII=", &[_]u8{ 255, 0, 0, 255, 0, 0, 255, 255 } },
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAAAAABX3VL4AAAADklEQVQI12NsYGBiYAAAApIAhEdXPhUAAAAASUVORK5CYII=", &[_]u8{128} },
    };
    inline for (samples, 0..) |item, index| {
        const bytes = try fixture(allocator, item[0]);
        defer allocator.free(bytes);
        const decoded = try decode(allocator, bytes);
        defer allocator.free(decoded.pixels);
        if (index < 3) {
            try std.testing.expectEqual(@as(u32, 2), decoded.width);
            try std.testing.expectEqual(@as(u32, 1), decoded.height);
            try std.testing.expectEqualSlices(u8, item[1], decoded.pixels);
        } else {
            try std.testing.expectEqual(@as(u32, 2), decoded.width);
            try std.testing.expectEqual(@as(u32, 2), decoded.height);
            for (0..4) |pixel| {
                const offset = pixel * 4;
                try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, decoded.pixels[offset..][0..4]);
            }
        }
    }
    const interlaced = try fixture(allocator, "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAAHe9q7oAAAAI0lEQVQI103IsREAIAyAwNf9d8ZGc1IBItGKYGS7zHnsP5YcIFMK/tzgEl4AAAAASUVORK5CYII=");
    defer allocator.free(interlaced);
    const decoded = try decode(allocator, interlaced);
    defer allocator.free(decoded.pixels);
    try std.testing.expectEqual(@as(u32, 4), decoded.width);
    try std.testing.expectEqual(@as(u32, 4), decoded.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, decoded.pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, decoded.pixels[15 * 4 ..][0..4]);
}

test "PNG truncated malformed CRC and impossible dimensions preserve decoding boundary" {
    const allocator = std.testing.allocator;
    const bytes = try fixture(allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=");
    defer allocator.free(bytes);
    for (0..bytes.len) |length| {
        try std.testing.expectError(error.Invalid, decode(allocator, bytes[0..length]));
    }
    bytes[bytes.len - 8] ^= 0x80;
    try std.testing.expectError(error.Invalid, decode(allocator, bytes));
    bytes[bytes.len - 8] ^= 0x80;
    // A dimension above the quota fails before inflation, even with valid CRC.
    std.mem.writeInt(u32, bytes[16..20], 4097, .big);
    var crc = std.hash.Crc32.init();
    crc.update("IHDR");
    crc.update(bytes[16..29]);
    std.mem.writeInt(u32, bytes[29..33], crc.final(), .big);
    try std.testing.expectError(error.Quota, decode(allocator, bytes));
}

test "PNG 16-bit samples preserve high bytes without overflowing RGBA" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABEAIAAADA54+dAAAAD0lEQVQI12MQMgmrmLUHAAYnAmsGA8PKAAAAAElFTkSuQmCC", &[_]u8{ 0x12, 0x56, 0x9a, 255 } },
        .{ "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABEAYAAABPhRjKAAAAEUlEQVQI12MQMgmrmLXn3gcADakEOUMR2o4AAAAASUVORK5CYII=", &[_]u8{ 0x12, 0x56, 0x9a, 0xde } },
    }) |item| {
        const bytes = try fixture(allocator, item[0]);
        defer allocator.free(bytes);
        const decoded = try decode(allocator, bytes);
        defer allocator.free(decoded.pixels);
        try std.testing.expectEqualSlices(u8, item[1], decoded.pixels);
    }
}

test "PNG malformed DEFLATE and unknown critical chunks fail with valid outer CRCs" {
    const allocator = std.testing.allocator;
    const bytes = try fixture(allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=");
    defer allocator.free(bytes);
    // The sample IDAT begins at offset 33: 4-byte length, 4-byte type,
    // followed by a zlib stream. Corrupt its Adler32 and fix the chunk CRC.
    const idat_size = std.mem.readInt(u32, bytes[33..37], .big);
    const idat_end: usize = 41 + idat_size;
    bytes[idat_end - 1] ^= 1;
    var crc = std.hash.Crc32.init();
    crc.update(bytes[37..idat_end]);
    std.mem.writeInt(u32, bytes[idat_end..][0..4], crc.final(), .big);
    try std.testing.expectError(error.Invalid, decode(allocator, bytes));

    // Unknown critical chunks cannot be silently interpreted as pixels.
    @memcpy(bytes[37..41], "ABCD");
    crc = std.hash.Crc32.init();
    crc.update(bytes[37..idat_end]);
    std.mem.writeInt(u32, bytes[idat_end..][0..4], crc.final(), .big);
    try std.testing.expectError(error.Unsupported, decode(allocator, bytes));
}
