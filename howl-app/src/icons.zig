//! Tiny stroke renderer for selected Lucide 0.456.0 shell icons (ISC).
//! Original 24x24 paths and attribution: assets/lucide/.
//! No SVG parser, font glyph fallback, texture residency, or runtime package.
const std = @import("std");
const c = @import("desktop");
const Rect = @import("layout.zig").Rect;

/// Bounded icons used by the native host shell; source paths are 24x24.
pub const Name = enum { search, x, plus, chevron_right, ellipsis, minus };
const Point = struct { x: f32, y: f32 };

const Geometry = struct {
    const disc_sides = 12;
    const ring_sides = 40;
    vertices: [256]c.SDL_Vertex = undefined,
    indices: [512]c_int = undefined,
    vertex_count: usize = 0,
    index_count: usize = 0,
    origin: Point,
    unit: f32,
    color: c.SDL_FColor,

    fn init(rect: Rect, color: c.SDL_Color) Geometry {
        const size = @min(rect.width, rect.height);
        return .{
            .origin = .{ .x = rect.x + (rect.width - size) / 2, .y = rect.y + (rect.height - size) / 2 },
            .unit = size / 24,
            .color = .{
                .r = @as(f32, @floatFromInt(color.r)) / 255,
                .g = @as(f32, @floatFromInt(color.g)) / 255,
                .b = @as(f32, @floatFromInt(color.b)) / 255,
                .a = @as(f32, @floatFromInt(color.a)) / 255,
            },
        };
    }
    fn add(self: *Geometry, p: Point) c_int {
        std.debug.assert(self.vertex_count < self.vertices.len);
        const result: c_int = @intCast(self.vertex_count);
        self.vertices[self.vertex_count] = .{
            .position = .{ .x = self.origin.x + p.x * self.unit, .y = self.origin.y + p.y * self.unit },
            .color = self.color,
            .tex_coord = .{ .x = 0, .y = 0 },
        };
        self.vertex_count += 1;
        return result;
    }
    fn triangle(self: *Geometry, a: c_int, b: c_int, d: c_int) void {
        std.debug.assert(self.index_count + 3 <= self.indices.len);
        self.indices[self.index_count..][0..3].* = .{ a, b, d };
        self.index_count += 3;
    }
    fn disc(self: *Geometry, center: Point, radius: f32) void {
        const middle = self.add(center);
        var outline: [disc_sides]c_int = undefined;
        for (0..disc_sides) |step| {
            const angle: f32 = 2 * std.math.pi * @as(f32, @floatFromInt(step)) / disc_sides;
            outline[step] = self.add(.{ .x = center.x + radius * @cos(angle), .y = center.y + radius * @sin(angle) });
        }
        for (0..disc_sides) |step| self.triangle(middle, outline[step], outline[(step + 1) % disc_sides]);
    }
    fn edge(self: *Geometry, a: Point, b: Point) void {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const length = @sqrt(dx * dx + dy * dy);
        if (length <= 0) return;
        // The source SVG has a two-unit stroke, centred on each path.
        const nx = -dy / length;
        const ny = dx / length;
        const first = self.add(.{ .x = a.x + nx, .y = a.y + ny });
        const second = self.add(.{ .x = a.x - nx, .y = a.y - ny });
        const third = self.add(.{ .x = b.x - nx, .y = b.y - ny });
        const fourth = self.add(.{ .x = b.x + nx, .y = b.y + ny });
        self.triangle(first, second, third);
        self.triangle(first, third, fourth);
    }
    fn stroke(self: *Geometry, a: Point, b: Point) void {
        self.edge(a, b);
        self.disc(a, 1);
        self.disc(b, 1);
    }
    fn ring(self: *Geometry, center: Point, radius: f32) void {
        var previous: Point = .{ .x = center.x + radius, .y = center.y };
        for (1..ring_sides + 1) |step| {
            const angle: f32 = 2 * std.math.pi * @as(f32, @floatFromInt(step)) / ring_sides;
            const next: Point = .{ .x = center.x + radius * @cos(angle), .y = center.y + radius * @sin(angle) };
            self.edge(previous, next);
            previous = next;
        }
    }
    fn compose(self: *Geometry, name: Name) void {
        switch (name) {
            .search => {
                self.ring(.{ .x = 11, .y = 11 }, 8);
                self.stroke(.{ .x = 16.7, .y = 16.7 }, .{ .x = 21, .y = 21 });
            },
            .x => {
                self.stroke(.{ .x = 18, .y = 6 }, .{ .x = 6, .y = 18 });
                self.stroke(.{ .x = 6, .y = 6 }, .{ .x = 18, .y = 18 });
            },
            .plus => {
                self.stroke(.{ .x = 5, .y = 12 }, .{ .x = 19, .y = 12 });
                self.stroke(.{ .x = 12, .y = 5 }, .{ .x = 12, .y = 19 });
            },
            .chevron_right => {
                self.stroke(.{ .x = 9, .y = 18 }, .{ .x = 15, .y = 12 });
                self.stroke(.{ .x = 15, .y = 12 }, .{ .x = 9, .y = 6 });
            },
            .ellipsis => {
                for ([_]f32{ 5, 12, 19 }) |x| self.disc(.{ .x = x, .y = 12 }, 2);
            },
            .minus => self.stroke(.{ .x = 5, .y = 12 }, .{ .x = 19, .y = 12 }),
        }
    }
};

/// Paints a selected Lucide stroke set in a caller-owned logical rectangle.
pub fn draw(renderer: *c.SDL_Renderer, name: Name, rect: Rect, color: c.SDL_Color) error{SDL}!void {
    if (rect.width <= 0 or rect.height <= 0) return;
    var geometry = Geometry.init(rect, color);
    geometry.compose(name);
    if (!c.SDL_RenderGeometry(renderer, null, &geometry.vertices, @intCast(geometry.vertex_count), &geometry.indices, @intCast(geometry.index_count))) return error.SDL;
}

test "Lucide paths stay inside their 24-unit viewbox at arbitrary shell positions" {
    for ([_]Name{ .search, .x, .plus, .chevron_right, .ellipsis, .minus }) |name| {
        var geometry = Geometry.init(.{ .x = 5.25, .y = 9.5, .width = 20, .height = 20 }, .{ .r = 255, .g = 100, .b = 40, .a = 255 });
        geometry.compose(name);
        try std.testing.expect(geometry.vertex_count > 0 and geometry.index_count > 0);
        for (geometry.vertices[0..geometry.vertex_count]) |vertex| {
            try std.testing.expect(vertex.position.x >= 5.25 and vertex.position.x <= 25.25);
            try std.testing.expect(vertex.position.y >= 9.5 and vertex.position.y <= 29.5);
        }
        for (geometry.indices[0..geometry.index_count]) |index| try std.testing.expect(index >= 0 and index < geometry.vertex_count);
    }
}

test "Lucide search ring stays hollow and close strokes paint on SDL software" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(96, 48, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try draw(renderer, .search, .{ .x = 4, .y = 4, .width = 32, .height = 32 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    try draw(renderer, .x, .{ .x = 52, .y = 4, .width = 32, .height = 32 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const ProbeError = error{ SearchCenterFilled, SearchRingMissing, SearchHandleMissing, CloseCentreMissing, CloseBackgroundFilled };
    for ([_]struct { x: i32, y: i32, ink: bool, failure: ProbeError }{
        .{ .x = 19, .y = 19, .ink = false, .failure = error.SearchCenterFilled },
        .{ .x = 19, .y = 8, .ink = true, .failure = error.SearchRingMissing },
        .{ .x = 29, .y = 29, .ink = true, .failure = error.SearchHandleMissing },
        .{ .x = 68, .y = 20, .ink = true, .failure = error.CloseCentreMissing },
        .{ .x = 54, .y = 6, .ink = false, .failure = error.CloseBackgroundFilled },
    }) |probe| {
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, probe.x, probe.y, &red, null, null, null));
        if ((red > 0) != probe.ink) return probe.failure;
    }
}
