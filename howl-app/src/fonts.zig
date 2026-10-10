//! Owns the desktop font recipe and shared native text owners per physical size.

const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");

/// Owns the exact desktop regular/style/fallback recipe and supplies bounded presentation policy.
pub const Fonts = struct {
    allocator: std.mem.Allocator,
    paths: [6][]const u8 = @splat(""),
    // At most 8 tabs × 8 panes, plus one staged replacement size.
    stores: [65]?struct { pixels: u16, owner: *instance.PresentationStore } = @splat(null),

    /// Resolves saved paths, then environment paths, then exact installed family/style matches; required faces fail explicitly.
    pub fn discover(allocator: std.mem.Allocator, env: *const std.process.Environ.Map, saved: [6][]const u8) !Fonts {
        var self: Fonts = .{ .allocator = allocator };
        errdefer self.deinit();
        const variables = [_][]const u8{ "HOWL_FONT", "HOWL_ITALIC_FONT", "HOWL_BOLD_FONT", "HOWL_BOLD_ITALIC_FONT", "HOWL_FALLBACK_FONT", "HOWL_SECONDARY_FALLBACK_FONT" };
        const patterns = [_][:0]const u8{
            "JetBrainsMono Nerd Font:style=Regular",
            "JetBrainsMono Nerd Font:style=Italic",
            "JetBrainsMono Nerd Font:style=Bold",
            "JetBrainsMono Nerd Font:style=Bold Italic",
            "Noto Sans Arabic",
            "Noto Sans CJK JP",
        };
        if (c.FcInit() == 0) return error.Fontconfig;
        for (variables, patterns, 0..) |variable, pattern, index| {
            const explicit = if (saved[index].len != 0) saved[index] else env.get(variable);
            if (explicit) |path| {
                if (path.len == 0 or path.len >= 4096 or path[0] != '/') return error.InvalidFontPath;
                self.paths[index] = try allocator.dupe(u8, path);
                continue;
            }
            if (index >= 1 and index <= 3 and (saved[0].len != 0 or env.get("HOWL_FONT") != null)) continue;
            self.paths[index] = match(allocator, pattern) catch |failure| {
                if (index >= 1 and index <= 3) continue;
                return failure;
            };
        }
        return self;
    }

    /// Frees the six owned path strings after all borrowers have retired.
    pub fn deinit(self: *Fonts) void {
        for (self.stores) |slot| if (slot) |store| instance.releasePresentationStore(store.owner);
        for (self.paths) |path| if (path.len != 0) self.allocator.free(path);
        self.* = undefined;
    }

    /// Releases idle native owners. Live Instances retain their own references.
    pub fn collect(self: *Fonts) void {
        for (&self.stores) |*slot| if (slot.*) |store| {
            if (instance.presentationStoreReferences(store.owner) != 1) continue;
            instance.releasePresentationStore(store.owner);
            slot.* = null;
        };
    }

    /// Borrows a matching text owner for the immediate construction/reconfigure
    /// call. Io must outlive the Instances; do not retain this config across collect.
    pub fn config(self: *Fonts, io: std.Io, pixels: u16) (instance.PresentationStoreInitError || error{PresentationStoreLimit})!instance.PresentationConfig {
        const shape_cache: instance.render.terminal.ShapeCacheConfig = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 };
        for (self.stores) |slot| if (slot) |store| {
            if (store.pixels == pixels) return presentation(store.owner, shape_cache);
        };
        self.collect();
        const fallbacks = self.paths[4..6];
        for (&self.stores) |*slot| if (slot.* == null) {
            const owner = try instance.initPresentationStore(self.allocator, io, .{
                .regular = .{ .path = .{ .primary = self.paths[0], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .italic = if (self.paths[1].len == 0) null else .{ .path = .{ .primary = self.paths[1], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .bold = if (self.paths[2].len == 0) null else .{ .path = .{ .primary = self.paths[2], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .bold_italic = if (self.paths[3].len == 0) null else .{ .path = .{ .primary = self.paths[3], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
            }, .{ .shape_cache = shape_cache, .shaped_capacity = 32, .raster_bytes = 512 * 512 });
            slot.* = .{ .pixels = pixels, .owner = owner };
            return presentation(owner, shape_cache);
        };
        return error.PresentationStoreLimit;
    }

    fn presentation(owner: *instance.PresentationStore, shape_cache: instance.render.terminal.ShapeCacheConfig) instance.PresentationConfig {
        return .{
            .text = .{ .shared = owner },
            .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
            .shape_cache = shape_cache,
            .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
            .shaped_capacity = 32,
            .raster_bytes = 512 * 512,
            .command_capacity = 4 * 1024,
            .command_limit = instance.render.limits.maximum_frame_commands,
        };
    }
};

fn match(allocator: std.mem.Allocator, pattern: [:0]const u8) ![]const u8 {
    const query = c.FcNameParse(pattern.ptr) orelse return error.FontPattern;
    defer c.FcPatternDestroy(query);
    if (c.FcConfigSubstitute(null, query, c.FcMatchPattern) == 0) return error.FontPattern;
    c.FcDefaultSubstitute(query);
    var result: c.FcResult = undefined;
    const found = c.FcFontMatch(null, query, &result) orelse return error.FontMissing;
    defer c.FcPatternDestroy(found);
    const colon = std.mem.indexOfScalar(u8, pattern, ':') orelse pattern.len;
    var family: [*c]u8 = null;
    if (c.FcPatternGetString(found, c.FC_FAMILY, 0, &family) != c.FcResultMatch or family == null or
        std.mem.indexOf(u8, std.mem.span(family), pattern[0..colon]) == null) return error.FontMissing;
    if (colon < pattern.len and std.mem.startsWith(u8, pattern[colon..], ":style=")) {
        var style: [*c]u8 = null;
        if (c.FcPatternGetString(found, c.FC_STYLE, 0, &style) != c.FcResultMatch or style == null or
            !std.mem.eql(u8, std.mem.span(style), pattern[colon + ":style=".len ..])) return error.FontStyleMissing;
    }
    var path: [*c]u8 = null;
    if (c.FcPatternGetString(found, c.FC_FILE, 0, &path) != c.FcResultMatch or path == null) return error.FontMissing;
    const text = std.mem.span(path);
    if (text.len == 0 or text.len >= 4096 or text[0] != '/') return error.InvalidFontPath;
    return allocator.dupe(u8, text);
}

/// Owns SDL's UI/preedit faces; the canonical terminal font stack remains howl-text.
pub const TextFonts = struct {
    faces: [3]*c.TTF_Font,

    /// Opens the regular and two Unicode fallback faces with reverse-order failure cleanup.
    pub fn open(allocator: std.mem.Allocator, fonts: *const Fonts, pixels: f32) !TextFonts {
        var self: TextFonts = undefined;
        var count: usize = 0;
        errdefer {
            if (count != 0) c.TTF_ClearFallbackFonts(self.faces[0]);
            while (count != 0) {
                count -= 1;
                c.TTF_CloseFont(self.faces[count]);
            }
        }
        for ([_]usize{ 0, 4, 5 }, 0..) |index, slot| {
            const path = try allocator.dupeSentinel(u8, fonts.paths[index], 0);
            defer allocator.free(path);
            self.faces[slot] = c.TTF_OpenFont(path, pixels) orelse return error.TTF;
            count += 1;
            if (slot != 0 and !c.TTF_AddFallbackFont(self.faces[0], self.faces[slot])) return error.TTF;
        }
        return self;
    }
    /// Keeps all three SDL faces at the same physical size.
    pub fn setSize(self: *TextFonts, pixels: f32) error{TTF}!void {
        for (self.faces) |face| if (!c.TTF_SetFontSize(face, pixels)) return error.TTF;
    }
    /// Detaches fallbacks before retiring every owned SDL font.
    pub fn deinit(self: *TextFonts) void {
        c.TTF_ClearFallbackFonts(self.faces[0]);
        var count: usize = self.faces.len;
        while (count != 0) {
            count -= 1;
            c.TTF_CloseFont(self.faces[count]);
        }
        self.* = undefined;
    }
};

test "saved font paths take precedence and remain owned after their input retires" {
    const a = std.testing.allocator;
    var env = std.process.Environ.Map.init(a);
    defer env.deinit();
    try env.put("HOWL_FONT", "/environment/regular");
    const original = "/saved/selection-proof.ttf";
    const paths: [6][]const u8 = @splat(original);
    var fonts = try Fonts.discover(a, &env, paths);
    defer fonts.deinit();
    for (fonts.paths) |path| {
        try std.testing.expectEqualStrings(original, path);
        try std.testing.expect(path.ptr != original.ptr);
    }
}
