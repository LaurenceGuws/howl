//! Backend-independent final-frame vocabulary for one terminal presentation.
//!
//! There is exactly one terminal resource identity space. This file owns
//! clipping, exact resource metadata, backend residency comparison, and final
//! command projection only. It owns no retained terminal state.

const std = @import("std");
const validation = @import("frame_validation.zig");

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

/// Identifies one logical resource in this Renderer's collision-free resource space.
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

/// Retains metadata for one Host-owned resource whose recovery bytes stay outside Render.
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

/// Locates one Render-owned upload in caller-provided frame pixel storage.
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

/// Supplies one ordered pre-projection draw fact with its caller-space clip.
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

/// Bounded painted-row lookup shared by projection and host cursor composition.
/// Stores command spans only; invalidate when content storage changes.
pub const CursorRows = struct {
    const Span = struct { start: usize = 0, count: usize = 0 };
    rows: [@import("limits").maximum_rows]Span = @splat(.{}),
    ready: bool = false,
    height: u16 = 1,
    row_count: usize = 0,

    /// Indexes clipped alpha ink and the intrinsic color glyph plane.
    /// Larger surfaces retain the complete-command fallback.
    pub fn build(self: *CursorRows, comptime T: type, commands: []const T, surface: Size, height: u16, color_id: ?ResourceId) Error!void {
        self.ready = false;
        if (height == 0 or surface.height == 0 or surface.width == 0) return error.InvalidSurface;
        const count = (@as(usize, surface.height) + height - 1) / height;
        if (count > self.rows.len) return;
        @memset(&self.rows, .{});
        const whole: Rect = .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height };
        for (commands, 0..) |command, index| {
            const ink = glyph(T, command, color_id) orelse continue;
            const clipped_ink = (try intersectRects(ink.destination, ink.clip)) orelse continue;
            const visible = (try intersectRects(clipped_ink, whole)) orelse continue;
            const first = @as(usize, @intCast(visible.y)) / height;
            const last = (@as(usize, @intCast(visible.y)) + visible.height - 1) / height;
            for (self.rows[first .. last + 1]) |*span| {
                if (span.count == 0) span.start = index;
                span.count = index + 1 - span.start;
            }
        }
        self.height = height;
        self.row_count = count;
        self.ready = true;
    }

    /// Borrows an ordered candidate span for a surface-contained cursor rectangle.
    pub fn candidates(self: *const CursorRows, comptime T: type, commands: []const T, rect: Rect) []const T {
        if (!self.ready) return commands;
        if (rect.y < 0 or rect.height == 0) return commands[0..0];
        const first = @as(usize, @intCast(rect.y)) / self.height;
        const last = (@as(usize, @intCast(rect.y)) + rect.height - 1) / self.height;
        if (last >= self.row_count) return commands;
        var start = commands.len;
        var end: usize = 0;
        for (self.rows[first .. last + 1]) |span| {
            if (span.count == 0) continue;
            start = @min(start, span.start);
            end = @max(end, span.start + span.count);
        }
        std.debug.assert(end <= commands.len);
        return if (end == 0) commands[0..0] else commands[start..end];
    }

    /// Replays stationary content ink through an arbitrary host cursor rectangle.
    /// Intrinsic RGBA glyphs retain their original pixels and source mapping.
    pub fn recolor(command: Command, rect: Rect, color: Color, color_id: ?ResourceId) Error!?Command {
        const ink = glyph(Command, command, color_id) orelse return null;
        const clip = (try intersectRects(ink.clip, rect)) orelse return null;
        if (try intersectRects(ink.destination, clip) == null) return null;
        var result = command;
        switch (result) {
            .alpha_mask => |*value| {
                value.clip = clip;
                value.color = color;
                value.cursor_component = false;
            },
            .rgba => |*value| value.clip = clip,
            else => return null,
        }
        return result;
    }

    /// Exact clipped glyph geometry without resource or font ownership.
    pub const Glyph = struct { destination: Rect, clip: Rect };

    /// Selects the same cursor ink before and after final frame projection.
    pub fn glyph(comptime T: type, command: T, color_id: ?ResourceId) ?Glyph {
        return switch (command) {
            .alpha_mask => |v| if (v.cursor_component) .{ .destination = v.destination, .clip = v.clip } else null,
            .rgba => |v| if (color_id != null and v.resource.resource.resource == color_id.?) .{ .destination = v.destination, .clip = v.clip } else null,
            else => null,
        };
    }
};

fn project(
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

/// Projects one already-capacity-bounded frame input list in a single pass.
///
/// Unlike `project`, this helper may modify `commands` before a later input
/// validation error is returned. Callers must therefore use private scratch and
/// publish only after success. `commands.len >= inputs.len` is required so
/// visibility filtering can never exhaust destination storage.
pub fn projectPrepared(
    surface: Size,
    inputs: []const Input,
    commands: []Command,
) Error![]const Command {
    if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
    if (commands.len < inputs.len) return error.InsufficientCommands;
    const command_bytes = try bytesFor(commands.len, @sizeOf(Command));
    const input_bytes = try bytesFor(inputs.len, @sizeOf(Input));
    if (overlaps(@intFromPtr(commands.ptr), command_bytes, @intFromPtr(inputs.ptr), input_bytes))
        return error.AliasedStorage;

    var used: usize = 0;
    for (inputs) |*input| {
        const visible = (try visibleRect(input.*, surface)) orelse continue;
        commands[used] = switch (input.*) {
            .solid => |*value| .{ .solid = .{ .rect = visible, .color = value.color } },
            .alpha_mask => |*value| .{ .alpha_mask = .{
                .destination = value.destination,
                .clip = visible,
                .resource = value.resource,
                .color = value.color,
                .cursor_component = value.cursor_component,
            } },
            .rgba => |*value| .{ .rgba = .{
                .destination = value.destination,
                .clip = visible,
                .resource = value.resource,
            } },
        };
        used += 1;
    }
    return commands[0..used];
}

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

/// Reports whether current pre-projection drawing references this exact resource occurrence.
pub fn resourceVisible(inputs: []const Input, resource: ResourceRef) bool {
    for (inputs) |input| switch (input) {
        .solid => {},
        .alpha_mask => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
        .rgba => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
    };
    return false;
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

test "prepared projection equals transactional projection for valid inputs" {
    const alpha_resource = ResourceView{
        .resource = .{
            .resource = try ResourceId.init(1),
            .generation = @fromBackingInt(1),
        },
        .format = .alpha8,
        .size = .{ .width = 16, .height = 16 },
        .source = .{ .x = 1, .y = 2, .width = 4, .height = 5 },
    };
    const rgba_resource = ResourceView{
        .resource = .{
            .resource = try ResourceId.init(2),
            .generation = @fromBackingInt(7),
        },
        .format = .rgba8,
        .size = .{ .width = 8, .height = 8 },
    };
    var inputs = [_]Input{
        .{ .solid = .{
            .rect = .{ .x = -2, .y = 1, .width = 6, .height = 3 },
            .clip = .{ .x = 0, .y = 0, .width = 8, .height = 4 },
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } },
        .{ .alpha_mask = .{
            .destination = .{ .x = 2, .y = -1, .width = 4, .height = 4 },
            .clip = .{ .x = 1, .y = 0, .width = 6, .height = 4 },
            .resource = alpha_resource,
            .color = .{ .r = 9, .g = 8, .b = 7, .a = 255 },
            .cursor_component = true,
        } },
        .{ .rgba = .{
            .destination = .{ .x = 6, .y = 2, .width = 4, .height = 3 },
            .clip = .{ .x = 0, .y = 0, .width = 8, .height = 4 },
            .resource = rgba_resource,
        } },
        .{ .solid = .{
            .rect = .{ .x = 20, .y = 20, .width = 2, .height = 2 },
            .clip = .{ .x = 20, .y = 20, .width = 2, .height = 2 },
            .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 },
        } },
    };
    var expected: [inputs.len]Command = undefined;
    var actual: [inputs.len]Command = undefined;
    const surface: Size = .{ .width = 8, .height = 4 };
    const transactional = try project(surface, &inputs, &expected);
    const prepared = try projectPrepared(surface, &inputs, &actual);
    try std.testing.expectEqualDeep(transactional, prepared);
}

test "prepared projection requires capacity for every input" {
    var inputs = [_]Input{
        .{ .solid = .{
            .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 1, .g = 1, .b = 1, .a = 255 },
        } },
        .{ .solid = .{
            .rect = .{ .x = 4, .y = 4, .width = 1, .height = 1 },
            .clip = .{ .x = 4, .y = 4, .width = 1, .height = 1 },
            .color = .{ .r = 2, .g = 2, .b = 2, .a = 255 },
        } },
    };
    var output: [1]Command = undefined;
    try std.testing.expectError(
        error.InsufficientCommands,
        projectPrepared(.{ .width = 2, .height = 2 }, &inputs, &output),
    );
}

test "prepared projection rejects exact and partial aliases without changing inputs" {
    var inputs: [3]Input = @splat(.{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } });
    const before = inputs;
    // The shared byte arena deliberately exercises the public rejection path;
    // neither exact nor offset overlap may become a noalias precondition.
    try std.testing.expectEqual(@sizeOf(Input), @sizeOf(Command));
    const commands = std.mem.bytesAsSlice(Command, std.mem.asBytes(&inputs));
    try std.testing.expectError(
        error.AliasedStorage,
        projectPrepared(.{ .width = 2, .height = 2 }, inputs[0..2], commands[0..2]),
    );
    try std.testing.expectEqualDeep(before, inputs);
    try std.testing.expectError(
        error.AliasedStorage,
        projectPrepared(.{ .width = 2, .height = 2 }, inputs[0..2], commands[1..3]),
    );
    try std.testing.expectEqualDeep(before, inputs);
}

test "moving cursor preserves intrinsic color ink and excludes unrelated graphics and decorations" {
    const color_id = try ResourceId.init(4);
    const other_id = try ResourceId.init(5);
    const resource: ResourceView = .{
        .resource = .{ .resource = color_id, .generation = @fromBackingInt(3) },
        .format = .rgba8,
        .size = .{ .width = 32, .height = 32 },
        .source = .{ .x = 3, .y = 5, .width = 8, .height = 10 },
    };
    const ink: Command = .{ .rgba = .{ .destination = .{ .x = 2, .y = -3, .width = 16, .height = 20 }, .clip = .{ .x = 4, .y = 0, .width = 12, .height = 17 }, .resource = resource } };
    const rect: Rect = .{ .x = 8, .y = 8, .width = 10, .height = 10 };
    const tint: Color = .{ .r = 1, .g = 2, .b = 3, .a = 255 };
    const replay = (try CursorRows.recolor(ink, rect, tint, color_id)).?;
    try std.testing.expectEqualDeep(ink.rgba.resource, replay.rgba.resource);
    try std.testing.expectEqualDeep(ink.rgba.destination, replay.rgba.destination);
    try std.testing.expectEqualDeep(Rect{ .x = 8, .y = 8, .width = 8, .height = 9 }, replay.rgba.clip);
    try std.testing.expectEqual(null, try CursorRows.recolor(ink, rect, tint, other_id));
    var mask: Command = .{ .alpha_mask = .{ .destination = ink.rgba.destination, .clip = ink.rgba.clip, .resource = resource, .color = tint, .cursor_component = false } };
    try std.testing.expectEqual(null, try CursorRows.recolor(mask, rect, tint, color_id));
    mask.alpha_mask.cursor_component = true;
    const alpha = (try CursorRows.recolor(mask, rect, tint, color_id)).?;
    try std.testing.expectEqualDeep(mask.alpha_mask.destination, alpha.alpha_mask.destination);
    try std.testing.expectEqualDeep(mask.alpha_mask.resource, alpha.alpha_mask.resource);
    try std.testing.expect(!alpha.alpha_mask.cursor_component);
    var index: CursorRows = .{};
    try index.build(Command, &.{ink}, .{ .width = 30, .height = 30 }, 10, color_id);
    try std.testing.expectEqual(@as(usize, 1), index.candidates(Command, &.{ink}, rect).len);
    try std.testing.expectEqual(@as(usize, 0), index.candidates(Command, &.{ink}, .{ .x = 0, .y = 20, .width = 10, .height = 10 }).len);
}
