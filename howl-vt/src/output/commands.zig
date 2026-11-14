//! Canonical final output vocabulary and stateless validation. No VT/Text/Renderer dependency.
const std = @import("std");
const validation = @import("validation.zig");
/// Reports malformed frame geometry, resource syntax, residency, or caller storage.
pub const Error = error{
    InvalidSurface,
    InvalidRectangle,
    InvalidIdentity,
    InvalidGeneration,
    InvalidPixels,
    FormatMismatch,
    ExtentMismatch,
    ArithmeticOverflow,
    AliasedStorage,
    InsufficientCommands,
    InvalidResidency,
};

/// Carries exact 8-bit RGBA channels without choosing backend sampling representation.
pub const Color = packed struct(u32) { r: u8, g: u8, b: u8, a: u8 };
/// Names a pixel extent; accepting frame boundaries require both dimensions nonzero.
pub const Size = struct { width: u16, height: u16 };
/// Names a signed destination/clip rectangle with an unsigned pixel extent.
pub const Rect = struct { x: i32, y: i32, width: u16, height: u16 };
/// Selects one unsigned pixel sub-rectangle inside a complete retained resource.
pub const SourceRect = struct { x: u16, y: u16, width: u16, height: u16 };

/// Identifies one logical resource in this owner's collision-free resource space.
/// Zero is reserved so malformed/uninitialized identities never name residency.
pub const ResourceId = enum(u64) {
    _,
    /// Largest logical identity representable in the resource space.
    pub const max_identity: u64 = std.math.maxInt(u64);
    const InitError = error{InvalidIdentity};

    /// Constructs one nonzero logical resource identity.
    pub fn init(value: u64) InitError!ResourceId {
        if (value == 0) return error.InvalidIdentity;
        return @fromBackingInt(value);
    }

    /// Validates an identity recovered from an encoded/backend representation.
    pub fn fromEncoded(value: u64) InitError!ResourceId {
        return init(value);
    }

    /// Rejects the reserved zero identity.
    pub fn validate(self: ResourceId) InitError!void {
        if (@backingInt(self) == 0) return error.InvalidIdentity;
    }

    /// Returns the validated nonzero logical identity value.
    pub fn identity(self: ResourceId) InitError!u64 {
        try self.validate();
        return @backingInt(self);
    }
};

/// Orders replacement content for one logical resource identity; zero is reserved.
pub const ResourceGeneration = enum(u64) { _ };
/// Selects the exact pixel representation required by one retained resource.
pub const ResourceFormat = enum(u8) { alpha8, rgba8 };

/// Names one exact occurrence of a logical resource.
pub const ResourceRef = struct {
    resource: ResourceId,
    generation: ResourceGeneration,

    /// Rejects reserved identity or generation values.
    pub fn validate(self: ResourceRef) error{ InvalidIdentity, InvalidGeneration }!void {
        try self.resource.validate();
        try validation.localIdentity(try self.resource.identity(), @backingInt(self.generation));
    }
};

/// Selects one complete resource or contained source region for sampling.
pub const ResourceView = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    /// Optional pixel sub-rectangle inside the retained resource.
    source: ?SourceRect = null,
};

/// Retains metadata for one Host-owned resource whose recovery bytes stay outside the output owner.
pub const ExternalResource = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    stride: usize,
};

/// Reports one exact backend resource occurrence available for drawing.
/// Upload stride and backing bytes are intentionally backend-private here.
pub const Residency = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
};

/// Locates one output-owner upload in caller-provided frame pixel storage.
pub const FrameResourceUpload = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    pixel_offset: usize,
    pixel_count: usize,
    stride: usize,
};

/// Names one visible Host-owned resource that exact backend residency does not satisfy.
pub const FrameExternalResource = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    stride: usize,
};

/// Supplies one final surface-clipped backend draw command.
/// Sampled commands retain destination plus visible clip so source mapping is unchanged.
pub const Command = union(enum) {
    solid: struct { rect: Rect, color: Color },
    alpha_mask: struct {
        destination: Rect,
        clip: Rect,
        resource: ResourceView,
        color: Color,
        cursor_component: bool = false,
    },
    rgba: struct { destination: Rect, clip: Rect, resource: ResourceView },
};

/// Reports whether backend residency contains this exact occurrence, format, and extent.
pub fn residencyMatches(
    residency: []const Residency,
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
) bool {
    resource.validate() catch return false;
    for (residency) |value| {
        if (!std.meta.eql(value.resource, resource)) continue;
        return value.format == format and std.meta.eql(value.size, size);
    }
    return false;
}

/// Validates nonzero exact residency and rejects duplicate logical resource identities.
pub fn validateResidencies(residency: []const Residency) Error!void {
    for (residency, 0..) |value, index| {
        value.resource.validate() catch return error.InvalidResidency;
        validateExtent(value.size, null) catch return error.InvalidResidency;
        for (residency[0..index]) |prior| {
            if (prior.resource.resource == value.resource.resource)
                return error.InvalidResidency;
        }
    }
}

/// Validates metadata for one Host-owned resource without requiring its recovery bytes.
pub fn validateExternal(value: ExternalResource) Error!void {
    value.resource.validate() catch |err| return err;
    try validateExtent(value.size, null);
    const bpp: usize = switch (value.format) {
        .alpha8 => 1,
        .rgba8 => 4,
    };
    const row_bytes = std.math.mul(usize, value.size.width, bpp) catch return error.ArithmeticOverflow;
    if (value.stride < row_bytes) return error.InvalidPixels;
}

/// Intersects two checked nonzero rectangles without clipping to a surface.
pub fn intersectRects(left: Rect, right: Rect) Error!?Rect {
    const a = try edges(left);
    const b = try edges(right);
    const x0 = @max(a.left, b.left);
    const y0 = @max(a.top, b.top);
    const x1 = @min(a.right, b.right);
    const y1 = @min(a.bottom, b.bottom);
    if (x0 >= x1 or y0 >= y1) return null;
    return .{
        .x = std.math.cast(i32, x0) orelse return error.ArithmeticOverflow,
        .y = std.math.cast(i32, y0) orelse return error.ArithmeticOverflow,
        .width = std.math.cast(u16, x1 - x0) orelse return error.ArithmeticOverflow,
        .height = std.math.cast(u16, y1 - y0) orelse return error.ArithmeticOverflow,
    };
}

/// Validate a sampled resource identity, format and source bounds.
pub fn validateResourceView(value: ResourceView) Error!void {
    value.resource.validate() catch |err| return err;
    try validateExtent(value.size, value.source);
}

/// Validate an external extent and optional source rectangle.
pub fn validateExtent(size: Size, source: ?SourceRect) Error!void {
    if (source) |value| {
        validation.extent(size.width, size.height, value.x, value.y, value.width, value.height) catch |err| return err;
    } else {
        validation.extent(size.width, size.height, null, null, null, null) catch |err| return err;
    }
}

/// Wide integer rectangle edges used for checked intersections.
pub const Edges = struct { left: i64, top: i64, right: i64, bottom: i64 };

/// Return checked rectangle edges without narrowing arithmetic.
pub fn edges(rect: Rect) Error!Edges {
    if (rect.width == 0 or rect.height == 0) return error.InvalidRectangle;
    const left: i64 = rect.x;
    const top: i64 = rect.y;
    return .{
        .left = left,
        .top = top,
        .right = std.math.add(i64, left, rect.width) catch return error.ArithmeticOverflow,
        .bottom = std.math.add(i64, top, rect.height) catch return error.ArithmeticOverflow,
    };
}

test "pure output resource validation rejects stale and malformed residency" {
    const ref: ResourceRef = .{ .resource = try ResourceId.init(1), .generation = @fromBackingInt(1) };
    const item: Residency = .{ .resource = ref, .format = .alpha8, .size = .{ .width = 8, .height = 8 } };
    try validateResidencies(&.{item});
    try std.testing.expectError(error.InvalidResidency, validateResidencies(&.{ item, item }));
    try std.testing.expect(residencyMatches(&.{item}, ref, .alpha8, item.size));
    var newer = ref;
    newer.generation = @fromBackingInt(2);
    try std.testing.expect(!residencyMatches(&.{item}, newer, .alpha8, item.size));
    try std.testing.expect(!residencyMatches(&.{item}, ref, .rgba8, item.size));
    try std.testing.expectError(error.InvalidIdentity, ResourceId.init(0));
    try std.testing.expectError(error.InvalidPixels, validateExternal(.{ .resource = ref, .format = .rgba8, .size = item.size, .stride = 8 }));
}

test "pure output source bounds and negative rectangle intersections" {
    try validateExtent(.{ .width = 8, .height = 8 }, .{ .x = 1, .y = 2, .width = 7, .height = 6 });
    try std.testing.expectError(error.ExtentMismatch, validateExtent(.{ .width = 8, .height = 8 }, .{ .x = 7, .y = 0, .width = 2, .height = 1 }));
    const overlap = (try intersectRects(.{ .x = -2, .y = -3, .width = 8, .height = 8 }, .{ .x = 0, .y = 0, .width = 10, .height = 10 })).?;
    try std.testing.expectEqualDeep(Rect{ .x = 0, .y = 0, .width = 6, .height = 5 }, overlap);
    try std.testing.expectEqual(@as(?Rect, null), try intersectRects(.{ .x = -3, .y = 0, .width = 2, .height = 2 }, .{ .x = 0, .y = 0, .width = 2, .height = 2 }));
}
