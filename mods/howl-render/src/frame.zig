//! Legacy frame Input projection and flat cursor indexing over canonical output types.
//!
//! There is exactly one terminal resource identity space. This file owns
//! clipping, exact resource metadata, backend residency comparison, and final
//! command projection only. It owns no retained terminal state.

const std = @import("std");
const vocabulary = @import("output_commands");
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Error = vocabulary.Error;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Color = vocabulary.Color;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Size = vocabulary.Size;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Rect = vocabulary.Rect;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const SourceRect = vocabulary.SourceRect;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ResourceId = vocabulary.ResourceId;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ResourceGeneration = vocabulary.ResourceGeneration;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ResourceFormat = vocabulary.ResourceFormat;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ResourceRef = vocabulary.ResourceRef;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ResourceView = vocabulary.ResourceView;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const ExternalResource = vocabulary.ExternalResource;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Residency = vocabulary.Residency;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const FrameResourceUpload = vocabulary.FrameResourceUpload;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const FrameExternalResource = vocabulary.FrameExternalResource;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const Command = vocabulary.Command;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const residencyMatches = vocabulary.residencyMatches;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const validateResidencies = vocabulary.validateResidencies;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const validateExternal = vocabulary.validateExternal;
/// Exact canonical final-output declaration retained for existing Render callers.
pub const intersectRects = vocabulary.intersectRects;
const validateResourceView = vocabulary.validateResourceView;
const validateExtent = vocabulary.validateExtent;
const edges = vocabulary.edges;

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

/// Reports whether current pre-projection drawing references this exact resource occurrence.
pub fn resourceVisible(inputs: []const Input, resource: ResourceRef) bool {
    for (inputs) |input| switch (input) {
        .solid => {},
        .alpha_mask => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
        .rgba => |value| if (std.meta.eql(value.resource.resource, resource)) return true,
    };
    return false;
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
