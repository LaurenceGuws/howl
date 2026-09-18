//! Private final-frame vocabulary for one terminal presentation.
//!
//! There is exactly one terminal resource identity space. This file owns
//! clipping, exact resource metadata, backend residency comparison, and final
//! command projection only. It owns no retained terminal state.

const std = @import("std");
const validation = @import("terminal_frame_validation.zig");

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
    MissingExternalResource,
    ResourceLimit,
    PixelLimit,
};

pub const Color = packed struct(u32) { r: u8, g: u8, b: u8, a: u8 };
pub const Size = struct { width: u16, height: u16 };
pub const Rect = struct { x: i32, y: i32, width: u16, height: u16 };
pub const SourceRect = struct { x: u16, y: u16, width: u16, height: u16 };

pub const ResourceId = enum(u64) {
    _,
    pub const max_identity: u64 = std.math.maxInt(u64);
    pub const InitError = error{InvalidIdentity};

    pub fn init(value: u64) InitError!ResourceId {
        if (value == 0) return error.InvalidIdentity;
        return @fromBackingInt(value);
    }

    pub fn fromEncoded(value: u64) InitError!ResourceId {
        return init(value);
    }

    pub fn validate(self: ResourceId) InitError!void {
        if (@backingInt(self) == 0) return error.InvalidIdentity;
    }

    pub fn identity(self: ResourceId) InitError!u64 {
        try self.validate();
        return @backingInt(self);
    }
};

pub const ResourceGeneration = enum(u64) { _ };
pub const ResourceFormat = enum(u8) { alpha8, rgba8 };

pub const ResourceRef = struct {
    resource: ResourceId,
    generation: ResourceGeneration,

    pub fn validate(self: ResourceRef) error{ InvalidIdentity, InvalidGeneration }!void {
        try self.resource.validate();
        try validation.localIdentity(try self.resource.identity(), @backingInt(self.generation));
    }
};

pub const ResourceView = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    /// Optional pixel sub-rectangle inside the retained resource.
    source: ?SourceRect = null,
};

pub const ExternalResource = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    stride: usize,
};

pub const Residency = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
};

pub const FrameResourceUpload = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    pixel_offset: usize,
    pixel_count: usize,
    stride: usize,
};

pub const FrameExternalResource = struct {
    resource: ResourceRef,
    format: ResourceFormat,
    size: Size,
    stride: usize,
};

pub const Input = union(enum) {
    solid: struct { rect: Rect, clip: Rect, color: Color },
    alpha_mask: struct {
        destination: Rect,
        clip: Rect,
        resource: ResourceView,
        color: Color,
        cursor_component: bool = false,
    },
    rgba: struct { destination: Rect, clip: Rect, resource: ResourceView },
};

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

pub fn project(
    surface: Size,
    inputs: []const Input,
    commands: []Command,
) Error![]const Command {
    if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
    const command_bytes = try bytesFor(commands.len, @sizeOf(Command));
    const input_bytes = try bytesFor(inputs.len, @sizeOf(Input));
    if (overlaps(@intFromPtr(commands.ptr), command_bytes, @intFromPtr(inputs.ptr), input_bytes))
        return error.AliasedStorage;

    var needed: usize = 0;
    for (inputs) |input| {
        if (try visibleRect(input, surface) != null)
            needed = std.math.add(usize, needed, 1) catch return error.ArithmeticOverflow;
    }
    if (commands.len < needed) return error.InsufficientCommands;

    var used: usize = 0;
    for (inputs) |input| {
        const visible = (try visibleRect(input, surface)) orelse continue;
        commands[used] = switch (input) {
            .solid => |value| .{ .solid = .{ .rect = visible, .color = value.color } },
            .alpha_mask => |value| .{ .alpha_mask = .{
                .destination = value.destination,
                .clip = visible,
                .resource = try validatedView(value.resource),
                .color = value.color,
                .cursor_component = value.cursor_component,
            } },
            .rgba => |value| .{ .rgba = .{
                .destination = value.destination,
                .clip = visible,
                .resource = try validatedView(value.resource),
            } },
        };
        used += 1;
    }
    return commands[0..used];
}

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

pub fn resourceVisible(inputs: []const Input, resource: ResourceRef) bool {
    for (inputs) |input| switch (input) {
        .solid => {},
        .alpha_mask => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
        .rgba => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
    };
    return false;
}

pub fn resourceReferencedByCommand(command: Command) ?ResourceView {
    return switch (command) {
        .solid => null,
        .alpha_mask => |value| value.resource,
        .rgba => |value| value.resource,
    };
}

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

fn validatedView(value: ResourceView) Error!ResourceView {
    try validateResourceView(value);
    return value;
}

fn visibleRect(input: Input, surface: Size) Error!?Rect {
    return switch (input) {
        .solid => |value| try clipped(value.rect, value.clip, surface),
        .alpha_mask => |value| blk: {
            try validateResourceView(value.resource);
            if (value.resource.format != .alpha8) return error.FormatMismatch;
            break :blk try clipped(value.destination, value.clip, surface);
        },
        .rgba => |value| blk: {
            try validateResourceView(value.resource);
            if (value.resource.format != .rgba8) return error.FormatMismatch;
            break :blk try clipped(value.destination, value.clip, surface);
        },
    };
}

fn validateResourceView(value: ResourceView) Error!void {
    value.resource.validate() catch |err| return err;
    try validateExtent(value.size, value.source);
}

fn validateExtent(size: Size, source: ?SourceRect) Error!void {
    if (source) |value| {
        validation.extent(size.width, size.height, value.x, value.y, value.width, value.height) catch |err| return err;
    } else {
        validation.extent(size.width, size.height, null, null, null, null) catch |err| return err;
    }
}

fn clipped(rect: Rect, clip: Rect, surface: Size) Error!?Rect {
    const a = try edges(rect);
    const b = try edges(clip);
    const left = @max(@as(i64, 0), @max(a.left, b.left));
    const top = @max(@as(i64, 0), @max(a.top, b.top));
    const right = @min(@as(i64, surface.width), @min(a.right, b.right));
    const bottom = @min(@as(i64, surface.height), @min(a.bottom, b.bottom));
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

const Edges = struct { left: i64, top: i64, right: i64, bottom: i64 };

fn edges(rect: Rect) Error!Edges {
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

fn bytesFor(count: usize, size: usize) Error!usize {
    return std.math.mul(usize, count, size) catch error.ArithmeticOverflow;
}

fn overlaps(a: usize, a_len: usize, b: usize, b_len: usize) bool {
    if (a_len == 0 or b_len == 0) return false;
    if (a > std.math.maxInt(usize) - a_len or b > std.math.maxInt(usize) - b_len) return true;
    return a < b + b_len and b < a + a_len;
}
