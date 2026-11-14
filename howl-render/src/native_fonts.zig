//! Private standalone Render font admission/composition over canonical Text.
const std = @import("std");
const text = @import("howl_render").text;
const terminal = @import("howl_render").terminal;
const c = @import("howl_render_native").c;
/// Closed caller font-source admission failures.
pub const AdmissionError = error{ InvalidArgument, ResourceLimit };
const Kind = enum { none, path, memory };
const Source = struct {
    kind: Kind = .none,
    primary: []const u8 = "",
    fallbacks: [text.max_fallbacks][]const u8 = undefined,
    count: usize = 0,
};
fn bytes(value: c.hrc_bytes, kind: Kind) AdmissionError![]const u8 {
    const maximum: usize = if (kind == .path) text.max_font_path_bytes else text.max_font_bytes;
    if (value.len > maximum) return error.ResourceLimit;
    if (value.data == null or value.len == 0) return error.InvalidArgument;
    // zig-audit: acknowledge discard
    // reason: Validate the entire admitted nested byte range before forming its slice.
    _ = std.math.add(usize, @intFromPtr(value.data), value.len) catch return error.InvalidArgument;
    const result = value.data[0..value.len];
    if (kind == .path and std.mem.indexOfScalar(u8, result, 0) != null) return error.InvalidArgument;
    return result;
}
/// Temporary caller-source admission. Derived family slices never outlive this value.
pub const Prepared = struct {
    sources: [4]Source = @splat(.{}),
    pixel_size: u16 = 0,
    /// Validates all nested borrowed sources before native font construction.
    pub fn init(self: *Prepared, config: *const c.hrc_config) AdmissionError!void {
        self.* = .{ .pixel_size = config.pixel_size };
        if (config.pixel_size == 0) return error.InvalidArgument;
        for (config.fonts, 0..) |input, index| {
            if (!std.mem.allEqual(u8, &input.reserved, 0)) return error.InvalidArgument;
            const kind: Kind = switch (input.kind) {
                c.HRC_FONT_NONE => .none,
                c.HRC_FONT_PATH => .path,
                c.HRC_FONT_MEMORY => .memory,
                else => return error.InvalidArgument,
            };
            if (kind == .none) {
                if (index == 0 or input.primary.data != null or input.primary.len != 0 or
                    input.fallbacks != null or input.fallback_count != 0) return error.InvalidArgument;
                continue;
            }
            if (input.fallback_count > text.max_fallbacks) return error.ResourceLimit;
            if (input.fallback_count != 0 and input.fallbacks == null) return error.InvalidArgument;
            const array_bytes = std.math.mul(usize, input.fallback_count, @sizeOf(c.hrc_bytes)) catch return error.InvalidArgument;
            if (input.fallbacks != null) {
                // zig-audit: acknowledge discard
                // reason: Validate the admitted descriptor array extent before any indexed descriptor read.
                _ = std.math.add(usize, @intFromPtr(input.fallbacks), array_bytes) catch return error.InvalidArgument;
            }
            const primary = try bytes(input.primary, kind);
            var total = primary.len;
            self.sources[index].kind = kind;
            self.sources[index].primary = primary;
            self.sources[index].count = input.fallback_count;
            for (0..input.fallback_count) |fallback| {
                const data = try bytes(input.fallbacks[fallback], kind);
                if (kind == .memory) {
                    total = std.math.add(usize, total, data.len) catch return error.ResourceLimit;
                    if (total > text.max_font_set_bytes) return error.ResourceLimit;
                }
                self.sources[index].fallbacks[fallback] = data;
            }
        }
    }
};
/// Four style owners; Render retains their exact canonical Text identities.
pub const Owned = struct {
    values: [4]?*text.FontSet = @splat(null),
    /// Copies each admitted source into canonical Text ownership.
    pub fn init(allocator: std.mem.Allocator, prepared: *const Prepared) text.InitError!Owned {
        var result: Owned = .{};
        errdefer result.deinit();
        for (prepared.sources, 0..) |input, index| {
            const size: text.Size = .{ .pixels = prepared.pixel_size };
            result.values[index] = switch (input.kind) {
                .none => null,
                .path => try text.FontSet.init(allocator, .{
                    .primary = input.primary,
                    .fallbacks = input.fallbacks[0..input.count],
                    .size = size,
                }),
                .memory => try text.FontSet.initMemory(allocator, .{
                    .primary = input.primary,
                    .fallbacks = input.fallbacks[0..input.count],
                    .size = size,
                }),
            };
        }
        return result;
    }
    /// Borrows the exact live style identities for canonical Render construction.
    pub fn faces(self: *const Owned) terminal.FontFaces {
        return .{ .regular = self.values[0].?, .italic = self.values[1], .bold = self.values[2], .bold_italic = self.values[3] };
    }
    /// Releases completed styles in reverse construction order.
    pub fn deinit(self: *Owned) void {
        var remaining = self.values.len;
        while (remaining != 0) {
            remaining -= 1;
            if (self.values[remaining]) |font| font.deinit();
            self.values[remaining] = null;
        }
    }
};
