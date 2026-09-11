//! Demand-driven exact terminal image resource client.
//!
//! Rich snapshots carry only visible image identities and placements. This
//! module fetches one exact RGBA8 image generation on a caller-owned connection;
//! it owns no terminal state, renderer resource cache, or residency policy.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

pub const Error = client.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    UnexpectedFrame,
    ServerRejected,
    InvalidResource,
};

pub const Resource = struct {
    allocator: std.mem.Allocator,
    image_id: u32,
    generation: u64,
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn deinit(self: *Resource) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

/// Fetches one exact image generation named by a rich snapshot manifest.
pub fn request(
    connection: *client.Connection,
    allocator: std.mem.Allocator,
    image_id: u32,
    generation: u64,
) Error!Resource {
    if (image_id == 0 or generation == 0) return error.InvalidResource;
    var payload: [protocol.payload_bytes.image_request]u8 = undefined;
    protocol.encodeImageRequest(&payload, .{ .image_id = image_id, .generation = generation });
    try connection.send(.image_request, &payload);
    return receiveFrom(connection, allocator, image_id, generation);
}

fn receiveFrom(
    connection: anytype,
    allocator: std.mem.Allocator,
    image_id: u32,
    generation: u64,
) Error!Resource {
    var begin_frame = try connection.receive();
    defer begin_frame.deinit();
    if (begin_frame.kind == .result) {
        const result = try protocol.decodeResult(begin_frame.payload);
        if (result.request_kind != .image_request or result.code == .ok)
            return error.UnexpectedFrame;
        if (result.code == .rejected) return error.ServerRejected;
        return error.UnexpectedFrame;
    }
    if (begin_frame.kind != .image_begin) return error.UnexpectedFrame;
    const begin = try protocol.decodeImageBegin(begin_frame.payload);
    if (begin.image_id != image_id or begin.generation != generation)
        return error.InvalidResource;

    const pixels = try allocator.alloc(u8, begin.byte_count);
    errdefer allocator.free(pixels);
    var offset: usize = 0;
    while (offset < pixels.len) {
        var frame = try connection.receive();
        defer frame.deinit();
        if (frame.kind != .image_data or frame.payload.len == 0 or
            frame.payload.len > protocol.graphics_v2.data_chunk_bytes or
            frame.payload.len > pixels.len - offset)
            return error.InvalidResource;
        @memcpy(pixels[offset..][0..frame.payload.len], frame.payload);
        offset += frame.payload.len;
    }

    var end_frame = try connection.receive();
    defer end_frame.deinit();
    if (end_frame.kind != .image_end) return error.UnexpectedFrame;
    const end = try protocol.decodeImageEnd(end_frame.payload);
    if (end.image_id != image_id or end.generation != generation)
        return error.InvalidResource;
    return .{
        .allocator = allocator,
        .image_id = image_id,
        .generation = generation,
        .width = begin.width,
        .height = begin.height,
        .pixels = pixels,
    };
}

const TestFrame = struct {
    kind: protocol.Kind,
    payload: []const u8,

    fn deinit(self: *TestFrame) void {
        self.* = undefined;
    }
};

const TestFrames = struct {
    frames: []const TestFrame,
    index: usize = 0,

    fn receive(self: *TestFrames) Error!TestFrame {
        if (self.index >= self.frames.len) return error.UnexpectedFrame;
        defer self.index += 1;
        return self.frames[self.index];
    }
};

test "exact image resource receiver owns complete bounded RGBA bytes" {
    var begin: [protocol.payload_bytes.image_begin]u8 = undefined;
    protocol.encodeImageBegin(&begin, .{
        .image_id = 7,
        .generation = 9,
        .width = 2,
        .height = 2,
        .byte_count = 16,
    });
    var end: [protocol.payload_bytes.image_end]u8 = undefined;
    protocol.encodeImageEnd(&end, .{ .image_id = 7, .generation = 9 });
    const first = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const second = [_]u8{ 9, 10, 11, 12, 13, 14, 15, 16 };
    const frames = [_]TestFrame{
        .{ .kind = .image_begin, .payload = &begin },
        .{ .kind = .image_data, .payload = &first },
        .{ .kind = .image_data, .payload = &second },
        .{ .kind = .image_end, .payload = &end },
    };
    var reader = TestFrames{ .frames = &frames };
    var resource = try receiveFrom(&reader, std.testing.allocator, 7, 9);
    defer resource.deinit();
    try std.testing.expectEqual(@as(u32, 2), resource.width);
    try std.testing.expectEqual(@as(u32, 2), resource.height);
    try std.testing.expectEqualSlices(u8, &.{
        1, 2,  3,  4,  5,  6,  7,  8,
        9, 10, 11, 12, 13, 14, 15, 16,
    }, resource.pixels);
}

test "image resource receiver rejects stale and incomplete identities" {
    var begin: [protocol.payload_bytes.image_begin]u8 = undefined;
    protocol.encodeImageBegin(&begin, .{
        .image_id = 7,
        .generation = 10,
        .width = 1,
        .height = 1,
        .byte_count = 4,
    });
    const bad = [_]TestFrame{.{ .kind = .image_begin, .payload = &begin }};
    var stale = TestFrames{ .frames = &bad };
    try std.testing.expectError(
        error.InvalidResource,
        receiveFrom(&stale, std.testing.allocator, 7, 9),
    );

    var result: [protocol.payload_bytes.result]u8 = undefined;
    protocol.encodeResult(&result, .{ .request_kind = .image_request, .code = .rejected });
    const rejected = [_]TestFrame{.{ .kind = .result, .payload = &result }};
    var server = TestFrames{ .frames = &rejected };
    try std.testing.expectError(
        error.ServerRejected,
        receiveFrom(&server, std.testing.allocator, 7, 9),
    );

    protocol.encodeResult(&result, .{ .request_kind = .image_request, .code = .unsupported });
    const unsupported = [_]TestFrame{.{ .kind = .result, .payload = &result }};
    var incompatible = TestFrames{ .frames = &unsupported };
    try std.testing.expectError(
        error.UnexpectedFrame,
        receiveFrom(&incompatible, std.testing.allocator, 7, 9),
    );
}
