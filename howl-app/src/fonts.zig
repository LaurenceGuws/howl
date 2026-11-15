//! Owns the desktop font recipe and shared native text owners per physical size.

const std = @import("std");
const c = @import("desktop");
const app_presentation = @import("presentation.zig");
const output = @import("howl_vt_output");
const canonical_vt = @import("howl_vt");
const fallback = @import("font_fallback.zig");

/// Owns the exact desktop regular/style/fallback recipe and supplies bounded presentation policy.
pub const Fonts = struct {
    allocator: std.mem.Allocator,
    // 0..3 styles; 4 Arabic; 5 CJK; 6 emoji; 7 Devanagari; 8 Bengali.
    paths: [9][]const u8 = @splat(""),
    atlas_height_limit: u16 = 4096,
    // At most 8 tabs × 8 panes, plus one staged replacement size.
    stores: [65]?struct { pixels: u16, owner: *output.PresentationStore } = @splat(null),

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
        const optional = [_][:0]const u8{
            "Noto Color Emoji",
            "Noto Sans Devanagari",
            "Noto Sans Bengali",
        };
        for (optional, 6..) |pattern, index| {
            self.paths[index] = match(allocator, pattern) catch |failure| switch (failure) {
                error.FontMissing => "",
                else => return failure,
            };
        }
        return self;
    }

    /// Frees the owned path strings after all borrowers have retired.
    pub fn deinit(self: *Fonts) void {
        for (self.stores) |slot| if (slot) |store| output.releasePresentationStore(store.owner);
        for (self.paths) |path| if (path.len != 0) self.allocator.free(path);
        self.* = undefined;
    }

    /// Releases idle native owners. Live direct projections retain references.
    pub fn collect(self: *Fonts) void {
        for (&self.stores) |*slot| if (slot.*) |store| {
            if (output.presentationStoreReferences(store.owner) != 1) continue;
            output.releasePresentationStore(store.owner);
            slot.* = null;
        };
    }

    /// Clamps the retained atlas policy to this SDL renderer's physical texture bound.
    /// SDL reports zero when it has no maximum; the host still caps growth.
    pub fn configureTextureLimit(self: *Fonts, maximum: i64) error{RendererTextureLimit}!void {
        if (maximum < 0 or (maximum != 0 and maximum < 512)) return error.RendererTextureLimit;
        self.atlas_height_limit = @intCast(if (maximum == 0) 4096 else @min(maximum, 4096));
    }

    /// Borrows a matching text owner for the immediate construction/reconfigure
    /// call. Io must outlive all direct projections; do not retain this config across collect.
    pub fn config(self: *Fonts, io: std.Io, pixels: u16) (output.PresentationStoreInitError || error{PresentationStoreLimit})!app_presentation.Config {
        const shape_cache: @FieldType(output.StoreConfig, "shape_cache") = .{
            .entry_capacity = 256,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = canonical_vt.scalar.maximum_scalars,
            .growth = .{ .entry_limit = 8192, .scalar_limit = 32768, .glyph_limit = 16384 },
        };
        for (self.stores) |slot| if (slot) |store| {
            if (store.pixels == pixels) return presentation(store.owner, shape_cache, self.atlas_height_limit);
        };
        self.collect();
        var ordered_fallbacks: [5][]const u8 = undefined;
        var fallback_count: usize = 0;
        for (self.paths[4..]) |path| {
            if (path.len == 0) continue;
            ordered_fallbacks[fallback_count] = path;
            fallback_count += 1;
        }
        const fallbacks = ordered_fallbacks[0..fallback_count];
        for (&self.stores) |*slot| if (slot.* == null) {
            const owner = try output.initPresentationStore(self.allocator, io, .{
                .regular = .{ .path = .{ .primary = self.paths[0], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .italic = if (self.paths[1].len == 0) null else .{ .path = .{ .primary = self.paths[1], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .bold = if (self.paths[2].len == 0) null else .{ .path = .{ .primary = self.paths[2], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .bold_italic = if (self.paths[3].len == 0) null else .{ .path = .{ .primary = self.paths[3], .fallbacks = fallbacks, .size = .{ .pixels = pixels } } },
                .fallback_factory = fallback.factory,
            }, .{ .shape_cache = shape_cache, .shaped_capacity = 32, .raster_bytes = 512 * 512 });
            slot.* = .{ .pixels = pixels, .owner = owner };
            return presentation(owner, shape_cache, self.atlas_height_limit);
        };
        return error.PresentationStoreLimit;
    }

    fn presentation(owner: *output.PresentationStore, shape_cache: @FieldType(output.StoreConfig, "shape_cache"), height_limit: u16) app_presentation.Config {
        return .{
            .text = .{ .shared = owner },
            .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
            .shape_cache = shape_cache,
            .atlas = .{
                .width = 512,
                .height = 512,
                .color_height = 128,
                .entry_capacity = 256,
                .growth = .{ .entry_limit = 8192, .alpha_height_limit = height_limit, .color_height_limit = @min(1024, height_limit) },
            },
            .shaped_capacity = 32,
            .raster_bytes = 512 * 512,
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
    for (fonts.paths[0..6]) |path| {
        try std.testing.expectEqualStrings(original, path);
        try std.testing.expect(path.ptr != original.ptr);
    }
}

test "desktop presentation renders the full canonical cell scalar bound" {
    const a = std.testing.allocator;
    const vt = @import("howl_vt");
    const output_owner = @import("howl_vt_output");
    var fonts: Fonts = .{ .allocator = a };
    defer fonts.deinit();
    // The absent optional emoji face between existing and new optional faces
    // must not be passed as an empty path to the text engine.
    for ([_]usize{ 0, 4, 5, 7, 8 }) |index| fonts.paths[index] = try a.dupe(u8, @import("test_fonts").primary_font);
    const config = try fonts.config(std.testing.io, 15);
    var bytes: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    for ([_]usize{ 16, 17, vt.scalar.maximum_scalars }, 1..) |count, row| {
        try writer.print("\x1b[{d};1Ha", .{row});
        for (1..count) |_| try writer.writeAll("\xcc\x81");
    }
    const store = switch (config.text) {
        .shared => |value| value,
        .private => return error.ExpectedSharedStore,
    };
    const owner = try output_owner.Terminal.initShared(a, store, .{
        .cursor_stroke_pixels = config.cursor_stroke_pixels,
        .box_drawing = config.box_drawing,
        .atlas = config.atlas,
    });
    // zig-audit: acknowledge catch_unreachable
    // reason: This test releases its only output lease before owner cleanup.
    defer owner.deinit() catch unreachable;
    try owner.feed(writer.buffered());
    try owner.flush();
    const held = try owner.hold();
    // zig-audit: acknowledge catch_unreachable
    // reason: The test releases the exact live lease returned by this owner.
    defer owner.release(held) catch unreachable;
    for ([_]usize{ 16, 17, vt.scalar.maximum_scalars }, 0..) |count, row| {
        var scalars: [vt.scalar.maximum_scalars]u21 = undefined;
        const actual = owner.observation().semanticView(0).cellScalarsAt(@intCast(row), 0, &scalars);
        try std.testing.expectEqual(count, actual.len);
        try std.testing.expectEqual(@as(u21, 'a'), actual[0]);
        for (actual[1..]) |value| try std.testing.expectEqual(@as(u21, 0x0301), value);
        try std.testing.expect(held.snapshot.glyphs[row].len != 0);
    }
}

test "desktop atlas ceilings respect the actual renderer and retain a finite unknown-limit policy" {
    var fonts: Fonts = .{ .allocator = std.testing.allocator };
    try fonts.configureTextureLimit(0);
    try std.testing.expectEqual(@as(u16, 4096), fonts.atlas_height_limit);
    try fonts.configureTextureLimit(16384);
    try std.testing.expectEqual(@as(u16, 4096), fonts.atlas_height_limit);
    try fonts.configureTextureLimit(1024);
    try std.testing.expectEqual(@as(u16, 1024), fonts.atlas_height_limit);
    try fonts.configureTextureLimit(512);
    try std.testing.expectEqual(@as(u16, 512), fonts.atlas_height_limit);
    try std.testing.expectError(error.RendererTextureLimit, fonts.configureTextureLimit(511));
    try std.testing.expectError(error.RendererTextureLimit, fonts.configureTextureLimit(-1));
    try std.testing.expectEqual(@as(u16, 512), fonts.atlas_height_limit);
}
