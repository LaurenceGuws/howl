//! Desktop-only, presentation-owned Fontconfig discovery for uncached missing glyphs.
//! The canonical VT and portable text engine never depend on Fontconfig.
const std = @import("std");
const c = @import("desktop");
const output = @import("howl_vt_output");
const text = @import("howl_text");

const buckets_per_style = 2;
const bucket_count = 4 * buckets_per_style;

const Resolver = struct {
    allocator: std.mem.Allocator,
    attempted: [bucket_count]bool = @splat(false),
    candidates: [bucket_count]?*c.FcFontSet = @splat(null),

    fn deinit(self: *Resolver) void {
        for (self.candidates) |set| if (set) |value| c.FcFontSetDestroy(value);
        self.allocator.destroy(self);
    }

    fn sorted(self: *Resolver, variant: output.FontVariant, color: bool) ?*c.FcFontSet {
        const slot = @as(usize, @backingInt(variant)) * buckets_per_style + @intFromBool(color);
        if (self.attempted[slot]) return self.candidates[slot];
        self.attempted[slot] = true;

        const pattern = c.FcPatternCreate() orelse return null;
        defer c.FcPatternDestroy(pattern);
        // The configured fonts always win first. Only genuine misses use the
        // desktop's monospace fallback preference, including locale-specific fonts.
        if (c.FcPatternAddString(pattern, c.FC_FAMILY, "monospace") == 0) return null;
        switch (variant) {
            .regular => {},
            .italic => if (c.FcPatternAddInteger(pattern, c.FC_SLANT, c.FC_SLANT_ITALIC) == 0) return null,
            .bold => if (c.FcPatternAddInteger(pattern, c.FC_WEIGHT, c.FC_WEIGHT_BOLD) == 0) return null,
            .bold_italic => {
                if (c.FcPatternAddInteger(pattern, c.FC_WEIGHT, c.FC_WEIGHT_BOLD) == 0 or
                    c.FcPatternAddInteger(pattern, c.FC_SLANT, c.FC_SLANT_ITALIC) == 0) return null;
            },
        }
        if (color and c.FcPatternAddBool(pattern, c.FC_COLOR, c.FcTrue) == 0) return null;
        if (c.FcConfigSubstitute(null, pattern, c.FcMatchPattern) == 0) return null;
        c.FcDefaultSubstitute(pattern);

        var result: c.FcResult = undefined;
        const found = c.FcFontSort(null, pattern, c.FcFalse, null, &result) orelse return null;
        if (found.*.nfont <= 0) {
            c.FcFontSetDestroy(found);
            return null;
        }
        self.candidates[slot] = found;
        return found;
    }

    fn find(self: *Resolver, variant: output.FontVariant, codepoints: []const u32) ?text.FallbackFile {
        var required: usize = 0;
        for (codepoints) |cp| if (!isShapingControl(cp) and !isVariationSelector(cp)) {
            required += 1;
        };
        if (required == 0) return null;
        const set = self.sorted(variant, prefersColor(codepoints)) orelse return null;
        for (0..@intCast(set.*.nfont)) |i| {
            const pattern = set.*.fonts[i];
            var charset: ?*c.FcCharSet = null;
            if (c.FcPatternGetCharSet(pattern, c.FC_CHARSET, 0, &charset) != c.FcResultMatch or charset == null) continue;
            var supported: usize = 0;
            for (codepoints) |cp| {
                if (isShapingControl(cp) or isVariationSelector(cp)) continue;
                if (c.FcCharSetHasChar(charset, cp) != 0) supported += 1;
            }
            if (supported != required) continue;

            var file: [*c]u8 = null;
            if (c.FcPatternGetString(pattern, c.FC_FILE, 0, &file) != c.FcResultMatch or file == null) continue;
            const path = std.mem.span(file);
            if (path.len == 0 or path.len > text.max_font_path_bytes or path[0] != '/') continue;
            var index: c_int = 0;
            if (c.FcPatternGetInteger(pattern, c.FC_INDEX, 0, &index) != c.FcResultMatch) index = 0;
            if (index < 0) continue;
            return .{ .path = path, .collection_index = @intCast(index) };
        }
        return null;
    }
};

fn isVariationSelector(cp: u32) bool {
    return (cp >= 0xfe00 and cp <= 0xfe0f) or (cp >= 0xe0100 and cp <= 0xe01ef);
}

fn isShapingControl(cp: u32) bool {
    return cp == 0x200c or cp == 0x200d or (cp >= 0xe0020 and cp <= 0xe007f);
}

fn prefersColor(codepoints: []const u32) bool {
    for (codepoints) |cp| if (cp == 0xfe0f or
        (cp >= 0x1f000 and cp <= 0x1faff) or
        (cp >= 0x2600 and cp <= 0x27bf)) return true;
    return false;
}

fn create(allocator: std.mem.Allocator) ?output.FallbackContext {
    const resolver = allocator.create(Resolver) catch return null;
    resolver.* = .{ .allocator = allocator };
    // zig-audit: acknowledge ptr_cast
    // reason: The host factory returns the address of its exact owned Resolver allocation.
    return @ptrCast(resolver);
}

fn find(context: output.FallbackContext, variant: output.FontVariant, codepoints: []const u32) ?text.FallbackFile {
    // zig-audit: acknowledge ptr_cast
    // reason: Every context originates from this factory's Resolver allocation.
    // zig-audit: acknowledge align_cast
    // reason: The original allocation guarantees Resolver alignment for the borrowed callback.
    const resolver: *Resolver = @ptrCast(@alignCast(context));
    return resolver.find(variant, codepoints);
}

fn destroy(context: output.FallbackContext) void {
    // zig-audit: acknowledge ptr_cast
    // reason: The presentation owner releases this factory's exact Resolver allocation.
    // zig-audit: acknowledge align_cast
    // reason: The original allocation guarantees Resolver alignment on final release.
    const resolver: *Resolver = @ptrCast(@alignCast(context));
    resolver.deinit();
}

/// Lets the presentation owner construct and release this optional lookup.
pub const factory: output.FallbackFactory = .{
    .create = create,
    .find = find,
    .destroy = destroy,
};

test "desktop candidate resolver treats unsupported scalars and standalone controls as misses" {
    const context = create(std.testing.allocator) orelse return error.OutOfMemory;
    defer destroy(context);
    try std.testing.expect(find(context, .regular, &.{0x10ffff}) == null);
    try std.testing.expect(find(context, .regular, &.{0x200d}) == null);
}
