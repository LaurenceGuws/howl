//! Host stroke policy and physical-pixel alignment for hand-drawn UI.
const std = @import("std");
const c = @import("desktop");
const layout = @import("layout.zig");

/// Settings name stroke width at a 15-pixel font. Direct output accepts 1–16
/// physical pixels; apply font/display scaling here, outside terminal semantics.
pub fn cursorStroke(font_pixels: u16, reference: u8) u8 {
    std.debug.assert(reference >= 1 and reference <= 16);
    return @intCast(std.math.clamp((@as(u32, font_pixels) * reference + 7) / 15, 1, 16));
}

fn scale(renderer: *c.SDL_Renderer) error{SDL}![2]f32 {
    var x: f32 = 0;
    var y: f32 = 0;
    if (!c.SDL_GetRenderScale(renderer, &x, &y)) return error.SDL;
    std.debug.assert(std.math.isFinite(x) and x > 0 and std.math.isFinite(y) and y > 0);
    return .{ x, y };
}

fn bounds(rect: layout.Rect, factor: [2]f32) c.SDL_FRect {
    const x = @round(rect.x * factor[0]);
    const y = @round(rect.y * factor[1]);
    return .{
        .x = x,
        .y = y,
        .w = @max(1, @round((rect.x + rect.width) * factor[0]) - x),
        .h = @max(1, @round((rect.y + rect.height) * factor[1]) - y),
    };
}

fn physicalRect(rect: c.SDL_Rect, factor: [2]f32) c.SDL_Rect {
    const x: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(rect.x)) * factor[0]));
    const y: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(rect.y)) * factor[1]));
    return .{
        .x = x,
        .y = y,
        .w = @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(rect.x + rect.w)) * factor[0]))) - x,
        .h = @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(rect.y + rect.h)) * factor[1]))) - y,
    };
}

fn restore(renderer: *c.SDL_Renderer, factor: [2]f32, viewport: ?*const c.SDL_Rect, clip: ?*const c.SDL_Rect) bool {
    // Attempt all restoration even if an earlier SDL operation fails.
    const scaled = c.SDL_SetRenderScale(renderer, factor[0], factor[1]);
    const viewed = c.SDL_SetRenderViewport(renderer, viewport);
    const clipped = c.SDL_SetRenderClipRect(renderer, clip);
    return scaled and viewed and clipped;
}

fn paint(renderer: *c.SDL_Renderer, rects: []const c.SDL_FRect, factor: [2]f32, value: c.SDL_Color) error{SDL}!void {
    const viewport_set = c.SDL_RenderViewportSet(renderer);
    const clip_set = c.SDL_RenderClipEnabled(renderer);
    var viewport: c.SDL_Rect = undefined;
    var clip: c.SDL_Rect = undefined;
    if (!c.SDL_GetRenderViewport(renderer, &viewport) or !c.SDL_GetRenderClipRect(renderer, &clip)) return error.SDL;
    const saved_viewport = if (viewport_set) &viewport else null;
    const saved_clip = if (clip_set) &clip else null;
    if (!c.SDL_SetRenderScale(renderer, 1, 1)) return error.SDL;
    // zig-audit: acknowledge discard
    // reason: Restore all caller state on drawing failure without hiding the original SDL error.
    errdefer _ = restore(renderer, factor, saved_viewport, saved_clip);
    const physical_viewport = physicalRect(viewport, factor);
    const physical_clip = physicalRect(clip, factor);
    if ((viewport_set and !c.SDL_SetRenderViewport(renderer, &physical_viewport)) or
        (clip_set and !c.SDL_SetRenderClipRect(renderer, &physical_clip)) or
        !c.SDL_SetRenderDrawColor(renderer, value.r, value.g, value.b, value.a)) return error.SDL;
    for (rects) |rect| {
        if (rect.w <= 0 or rect.h <= 0) continue;
        if (!c.SDL_RenderFillRect(renderer, &rect)) return error.SDL;
    }
    if (!restore(renderer, factor, saved_viewport, saved_clip)) return error.SDL;
}

/// Fills nonempty logical UI geometry at whole physical-pixel edges. Does not
/// retain changes to renderer scale, target, viewport or clipping.
pub fn fill(renderer: *c.SDL_Renderer, rect: layout.Rect, value: c.SDL_Color) error{SDL}!void {
    if (rect.width <= 0 or rect.height <= 0) return;
    const factor = try scale(renderer);
    try paint(renderer, &.{bounds(rect, factor)}, factor, value);
}

fn vertex(x: f32, y: f32, factor: [2]f32, color: c.SDL_FColor) c.SDL_Vertex {
    return .{
        .position = .{ .x = x / factor[0], .y = y / factor[1] },
        .color = color,
        .tex_coord = .{ .x = 0, .y = 0 },
    };
}

/// A single convex mesh keeps translucent interior and edge coverage disjoint.
/// A bounded inward fringe antialiases only the curved corners, leaving straight
/// edges exact and pixels outside the caller's rectangle untouched.
pub fn fillRounded(renderer: *c.SDL_Renderer, rect: layout.Rect, value: c.SDL_Color, radius: f32) error{SDL}!void {
    if (rect.width <= 0 or rect.height <= 0) return;
    std.debug.assert(std.math.isFinite(radius) and radius >= 0);
    const factor = try scale(renderer);
    const r = bounds(rect, factor);
    // The chrome uses a four-pixel radius; the cap bounds stack work if a
    // future caller supplies an excessively large radius or display scale.
    const rx = @min(@floor(r.w / 2), @min(@round(radius * factor[0]), 32));
    const ry = @min(@floor(r.h / 2), @min(@round(radius * factor[1]), 32));
    if (rx < 1 or ry < 1) return paint(renderer, &.{r}, factor, value);

    const steps = 8;
    const perimeter = 4 * (steps + 1);
    var vertices: [1 + 2 * perimeter]c.SDL_Vertex = undefined;
    var indices: [9 * perimeter]c_int = undefined;
    const color: c.SDL_FColor = .{
        .r = @as(f32, @floatFromInt(value.r)) / 255,
        .g = @as(f32, @floatFromInt(value.g)) / 255,
        .b = @as(f32, @floatFromInt(value.b)) / 255,
        .a = @as(f32, @floatFromInt(value.a)) / 255,
    };
    const transparent: c.SDL_FColor = .{ .r = color.r, .g = color.g, .b = color.b, .a = 0 };
    vertices[0] = vertex(r.x + r.w / 2, r.y + r.h / 2, factor, color);
    const centers = [_][2]f32{
        .{ r.x + r.w - rx, r.y + ry },
        .{ r.x + r.w - rx, r.y + r.h - ry },
        .{ r.x + rx, r.y + r.h - ry },
        .{ r.x + rx, r.y + ry },
    };
    for (centers, 0..) |center, corner| {
        for (0..steps + 1) |step| {
            const angle = (-0.5 + @as(f32, @floatFromInt(corner)) / 2 + @as(f32, @floatFromInt(step)) / (2 * steps)) * std.math.pi;
            const dx = @cos(angle);
            const dy = @sin(angle);
            const nx = dx / rx;
            const ny = dy / ry;
            const feather = if (step == 0 or step == steps) @as(f32, 0) else 0.85 * @sin(@as(f32, @floatFromInt(step)) * std.math.pi / steps);
            const normal = feather / @sqrt(nx * nx + ny * ny);
            const x = center[0] + dx * rx;
            const y = center[1] + dy * ry;
            const ox = nx * normal;
            const oy = ny * normal;
            const i = corner * (steps + 1) + step;
            vertices[1 + i] = vertex(x - ox, y - oy, factor, color);
            vertices[1 + perimeter + i] = vertex(x, y, factor, transparent);
        }
    }
    for (0..perimeter) |i| {
        const next = (i + 1) % perimeter;
        indices[9 * i ..][0..9].* = .{
            0,               @intCast(1 + i),                @intCast(1 + next),
            @intCast(1 + i), @intCast(1 + perimeter + i),    @intCast(1 + perimeter + next),
            @intCast(1 + i), @intCast(1 + perimeter + next), @intCast(1 + next),
        };
    }
    if (!c.SDL_RenderGeometry(renderer, null, &vertices, vertices.len, &indices, indices.len)) return error.SDL;
}

/// One logical-pixel outline, rounded to at least one physical pixel. Disjoint
/// filled bands keep translucent corners from blending twice.
pub fn outline(renderer: *c.SDL_Renderer, rect: layout.Rect, value: c.SDL_Color) error{SDL}!void {
    if (rect.width <= 0 or rect.height <= 0) return;
    const factor = try scale(renderer);
    const r = bounds(rect, factor);
    const width = @min(r.w, @max(1, @round(factor[0])));
    const top = @min(r.h, @max(1, @round(factor[1])));
    const bottom = @min(r.h - top, top);
    const right = @min(r.w - width, width);
    const middle = r.h - top - bottom;
    try paint(renderer, &.{
        .{ .x = r.x, .y = r.y, .w = r.w, .h = top },
        .{ .x = r.x, .y = r.y + r.h - bottom, .w = r.w, .h = bottom },
        .{ .x = r.x, .y = r.y + top, .w = width, .h = middle },
        .{ .x = r.x + r.w - right, .y = r.y + top, .w = right, .h = middle },
    }, factor, value);
}

/// Centers a constant physical-width stroke in a logical split hit lane.
pub fn divider(renderer: *c.SDL_Renderer, lane: layout.Rect, axis: layout.Axis, thickness: f32, value: c.SDL_Color) error{SDL}!void {
    const factor = try scale(renderer);
    var r = bounds(lane, factor);
    if (axis == .horizontal) {
        r.w = @max(1, @round(thickness * factor[0]));
        r.x = @round((lane.x + lane.width / 2) * factor[0] - r.w / 2);
    } else {
        r.h = @max(1, @round(thickness * factor[1]));
        r.y = @round((lane.y + lane.height / 2) * factor[1] - r.h / 2);
    }
    try paint(renderer, &.{r}, factor, value);
}

test "cursor strokes follow font pixels including display scale and bounded extremes" {
    try std.testing.expectEqual(@as(u8, 1), cursorStroke(6, 2));
    try std.testing.expectEqual(@as(u8, 1), cursorStroke(9, 2));
    try std.testing.expectEqual(@as(u8, 2), cursorStroke(15, 2));
    try std.testing.expectEqual(@as(u8, 3), cursorStroke(23, 2));
    try std.testing.expectEqual(@as(u8, 4), cursorStroke(30, 2));
    try std.testing.expectEqual(@as(u8, 1), cursorStroke(6, 1));
    try std.testing.expectEqual(@as(u8, 2), cursorStroke(30, 1));
    try std.testing.expectEqual(@as(u8, 1), cursorStroke(0, 16));
    try std.testing.expectEqual(@as(u8, 16), cursorStroke(std.math.maxInt(u16), 16));
}

test "rounded chrome raster preserves corners, opacity and render scale" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(128, 128, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    const rect: layout.Rect = .{ .x = 6, .y = 8, .width = 32, .height = 30 };
    for ([_]f32{ 1, 1.25, 1.5, 2 }) |factor| {
        try std.testing.expect(c.SDL_SetRenderScale(renderer, factor, factor));
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try fillRounded(renderer, rect, .{ .r = 200, .g = 0, .b = 0, .a = 128 }, 4);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        const x: i32 = @intFromFloat(@round(rect.x * factor));
        const y: i32 = @intFromFloat(@round(rect.y * factor));
        const width: i32 = @as(i32, @intFromFloat(@round((rect.x + rect.width) * factor))) - x;
        const height: i32 = @as(i32, @intFromFloat(@round((rect.y + rect.height) * factor))) - y;
        for ([_]struct { x: i32, y: i32, ink: u8 }{
            .{ .x = x, .y = y, .ink = 0 },
            .{ .x = x + width - 1, .y = y, .ink = 0 },
            .{ .x = x, .y = y + height - 1, .ink = 0 },
            .{ .x = x + width - 1, .y = y + height - 1, .ink = 0 },
            .{ .x = x + @divTrunc(width, 2), .y = y, .ink = 100 },
            .{ .x = x, .y = y + @divTrunc(height, 2), .ink = 100 },
            .{ .x = x + @divTrunc(width, 2), .y = y + @divTrunc(height, 2), .ink = 100 },
        }) |probe| {
            var red: u8 = 0;
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, probe.x, probe.y, &red, null, null, null));
            if (red != probe.ink) {
                std.debug.print("rounded scale={d} point={d},{d} expected={d} observed={d}\n", .{ factor, probe.x, probe.y, probe.ink, red });
                return error.RoundedPixelMismatch;
            }
        }
        var observed_x: f32 = 0;
        var observed_y: f32 = 0;
        try std.testing.expect(c.SDL_GetRenderScale(renderer, &observed_x, &observed_y));
        try std.testing.expectEqual(factor, observed_x);
        try std.testing.expectEqual(factor, observed_y);
        try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
    }
}

test "rounded switch chrome feathers the pill edge without overblending or escaping its bounds" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(96, 64, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try fillRounded(renderer, .{ .x = 10, .y = 10, .width = 44, .height = 26 }, .{ .r = 200, .g = 0, .b = 0, .a = 128 }, 13);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    var feather: usize = 0;
    var interior: usize = 0;
    for (0..64) |y| for (0..96) |x| {
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &red, null, null, null));
        const inside = x >= 10 and x < 54 and y >= 10 and y < 36;
        if (!inside and red != 0) {
            std.debug.print("rounded pill escaped at {d},{d} red={d}\n", .{ x, y, red });
            return error.RoundedPixelEscaped;
        }
        try std.testing.expect(red <= 100);
        if (red > 0 and red < 100) feather += 1;
        if (red == 100) interior += 1;
    };
    try std.testing.expect(feather >= 20);
    try std.testing.expect(interior >= 300);
}

test "fractional UI strokes cover exact pixels without double blending or state changes" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(128, 128, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    const ink: c.SDL_Color = .{ .r = 200, .g = 0, .b = 0, .a = 128 };
    for ([_]f32{ 0.75, 1, 1.25, 1.5, 1.7, 2 }) |factor| {
        try std.testing.expect(c.SDL_SetRenderScale(renderer, factor, factor));
        for ([_]f32{ 0, 0.2, 0.5, 0.8 }) |offset| {
            const rect: layout.Rect = .{ .x = 5 + offset, .y = 7 + offset, .width = 30.3, .height = 25.7 };
            // Independent integer-pixel oracle, including corner alpha.
            const left: i32 = @intFromFloat(@round(rect.x * factor));
            const top: i32 = @intFromFloat(@round(rect.y * factor));
            const right: i32 = @intFromFloat(@round((rect.x + rect.width) * factor));
            const bottom: i32 = @intFromFloat(@round((rect.y + rect.height) * factor));
            const stroke: i32 = @intFromFloat(@max(1, @round(factor)));
            for (0..3) |kind| {
                try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
                try std.testing.expect(c.SDL_RenderClear(renderer));
                if (kind == 0) try outline(renderer, rect, ink) else try divider(renderer, rect, if (kind == 1) .horizontal else .vertical, 2, ink);
                try std.testing.expect(c.SDL_RenderPresent(renderer));
                const line_width: i32 = @intFromFloat(@max(1, @round(2 * factor)));
                const line_x: i32 = @intFromFloat(@round((rect.x + rect.width / 2) * factor - @as(f32, @floatFromInt(line_width)) / 2));
                const line_y: i32 = @intFromFloat(@round((rect.y + rect.height / 2) * factor - @as(f32, @floatFromInt(line_width)) / 2));
                for (0..100) |y| for (0..100) |x| {
                    const px: i32 = @intCast(x);
                    const py: i32 = @intCast(y);
                    const painted = if (kind == 0)
                        px >= left and px < right and py >= top and py < bottom and
                            (px < left + stroke or px >= right - stroke or py < top + stroke or py >= bottom - stroke)
                    else if (kind == 1)
                        px >= line_x and px < line_x + line_width and py >= top and py < bottom
                    else
                        py >= line_y and py < line_y + line_width and px >= left and px < right;
                    var red: u8 = 0;
                    try std.testing.expect(c.SDL_ReadSurfacePixel(surface, px, py, &red, null, null, null));
                    if (red != @as(u8, if (painted) 100 else 0)) {
                        std.debug.print("scale={d} offset={d} kind={d} point={d},{d} bounds={d},{d}..{d},{d} red={d} expected={any}\n", .{ factor, offset, kind, x, y, left, top, right, bottom, red, painted });
                        return error.PixelMismatch;
                    }
                };
                var sx: f32 = 0;
                var sy: f32 = 0;
                try std.testing.expect(c.SDL_GetRenderScale(renderer, &sx, &sy));
                try std.testing.expectEqual(factor, sx);
                try std.testing.expectEqual(factor, sy);
                try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
                try std.testing.expect(c.SDL_GetRenderTarget(renderer) == null);
            }
        }
    }
}

test "physical UI drawing preserves explicit viewport clip target and anisotropic scale" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(128, 128, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const target = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, 128, 128) orelse return error.SDL;
    defer c.SDL_DestroyTexture(target);
    try std.testing.expect(c.SDL_SetRenderTarget(renderer, target));
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    const viewport: c.SDL_Rect = .{ .x = 3, .y = 4, .w = 40, .h = 40 };
    const clip: c.SDL_Rect = .{ .x = 5, .y = 6, .w = 12, .h = 13 };
    try std.testing.expect(c.SDL_SetRenderScale(renderer, 1.7, 1.25));
    try std.testing.expect(c.SDL_SetRenderViewport(renderer, &viewport));
    try std.testing.expect(c.SDL_SetRenderClipRect(renderer, &clip));
    try fill(renderer, .{ .x = -100, .y = -100, .width = 500, .height = 500 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    var observed: c.SDL_Rect = undefined;
    try std.testing.expect(c.SDL_GetRenderViewport(renderer, &observed));
    try std.testing.expectEqualDeep(viewport, observed);
    try std.testing.expect(c.SDL_RenderViewportSet(renderer));
    try std.testing.expect(c.SDL_GetRenderClipRect(renderer, &observed));
    try std.testing.expectEqualDeep(clip, observed);
    try std.testing.expect(c.SDL_RenderClipEnabled(renderer));
    try std.testing.expectEqual(target, c.SDL_GetRenderTarget(renderer).?);
    var sx: f32 = 0;
    var sy: f32 = 0;
    try std.testing.expect(c.SDL_GetRenderScale(renderer, &sx, &sy));
    try std.testing.expectEqual(@as(f32, 1.7), sx);
    try std.testing.expectEqual(@as(f32, 1.25), sy);
    try std.testing.expect(c.SDL_SetRenderTarget(renderer, null));
    try std.testing.expect(c.SDL_RenderTexture(renderer, target, null, null));
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    // Rounded viewport origin (5,5) plus rounded clip (9,8)..(29,24).
    for (0..100) |y| for (0..100) |x| {
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &red, null, null, null));
        try std.testing.expectEqual(@as(u8, if (x >= 14 and x < 34 and y >= 13 and y < 29) 255 else 0), red);
    };
}
