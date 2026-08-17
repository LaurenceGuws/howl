//! Public renderer-neutral boundary for native font shaping and rasterization.

const std = @import("std");
const engine = @import("engine.zig");

pub const max_fallbacks = engine.max_fallbacks;
pub const max_font_path_bytes = engine.max_font_path_bytes;
pub const max_codepoints = engine.max_codepoints;
pub const max_glyphs = engine.max_glyphs;
pub const max_raster_bytes = engine.max_raster_bytes;

pub const InitError = engine.InitError;
pub const ShapeError = engine.ShapeError;
pub const ShapeBufferInitError = engine.ShapeBufferInitError || error{OutOfMemory};
pub const RasterError = engine.RasterError;
pub const GlyphWidthError = engine.GlyphWidthError;
pub const GroupError = engine.GroupError;

pub const Dpi = engine.Dpi;
pub const PointSize = engine.PointSize;
pub const Size = engine.Size;
pub const Config = engine.Config;
pub const Metrics = engine.Metrics;
pub const Text = engine.Text;
pub const Glyph = engine.Glyph;
pub const Run = engine.Run;
pub const Raster = engine.Raster;
pub const SpacerStrategy = engine.SpacerStrategy;
pub const LigatureType = engine.LigatureType;

const FontOwner = struct {
    value: engine.FontSet,
};

/// Opaque owner of one ordered native font/fallback set.
pub const FontSet = opaque {
    /// Copies the config and transactionally opens all native font state.
    pub fn init(allocator: std.mem.Allocator, config: Config) InitError!*FontSet {
        try engine.validateConfig(config);
        const owner = allocator.create(FontOwner) catch return error.OutOfMemory;
        errdefer allocator.destroy(owner);
        owner.* = .{ .value = try engine.FontSet.init(allocator, config) };
        return @ptrCast(owner);
    }

    /// Releases every native face/library and the opaque owner exactly once.
    pub fn deinit(self: *FontSet) void {
        const owner = fontOwner(self);
        const allocator = owner.value.allocator;
        owner.value.deinit();
        allocator.destroy(owner);
    }

    /// Copies the validated native metrics for this configured font set.
    pub fn metrics(self: *const FontSet) Metrics {
        return fontOwnerConst(self).value.metrics;
    }

    /// Shapes one validated sequence into caller-owned glyph storage.
    pub fn shape(
        self: *FontSet,
        buffer: *ShapeBuffer,
        text: Text,
        glyph_storage: []Glyph,
    ) ShapeError!Run {
        return fontOwner(self).value.shape(
            &shapeOwner(buffer).value,
            text,
            glyph_storage,
        );
    }

    /// Shapes one sequence on one already selected fallback face.
    pub fn shapeFace(
        self: *FontSet,
        buffer: *ShapeBuffer,
        text: Text,
        glyph_storage: []Glyph,
        face_index: u8,
        disable_contextual: bool,
    ) ShapeError!Run {
        return fontOwner(self).value.shapeFace(
            &shapeOwner(buffer).value,
            text,
            glyph_storage,
            face_index,
            disable_contextual,
        );
    }

    /// Returns the first configured face covering one complete valid sequence.
    pub fn faceFor(
        self: *FontSet,
        codepoints: []const u32,
    ) error{ InvalidText, TextTooLong }!?u8 {
        return fontOwner(self).value.faceFor(codepoints);
    }

    /// Returns the selected native glyph's bounded pixel width.
    pub fn glyphWidth(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
    ) GlyphWidthError!u16 {
        return fontOwner(self).value.glyphWidth(face_index, glyph_id);
    }

    /// Returns the selected face's exact glyph identity for one scalar.
    pub fn glyphForCodepoint(
        self: *FontSet,
        face_index: u8,
        codepoint: u21,
    ) GlyphWidthError!u32 {
        return fontOwner(self).value.glyphForCodepoint(face_index, codepoint);
    }

    /// Reports whether a shaped glyph differs from the direct scalar glyph.
    pub fn glyphIsSpecial(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
        codepoint: u32,
    ) error{InvalidRaster}!bool {
        return fontOwner(self).value.glyphIsSpecial(face_index, glyph_id, codepoint);
    }

    /// Reports Kitty's exact zero-horizontal-metric empty-glyph result.
    pub fn glyphIsEmpty(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
    ) error{ GlyphLoad, InvalidRaster }!bool {
        return fontOwner(self).value.glyphIsEmpty(face_index, glyph_id);
    }

    /// Classifies one variable-length ligature glyph-name component.
    pub fn glyphLigatureType(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
        strategy: SpacerStrategy,
    ) error{InvalidRaster}!LigatureType {
        return fontOwner(self).value.glyphLigatureType(face_index, glyph_id, strategy);
    }

    /// Detects and retains one face's bounded ligature spacer convention.
    pub fn spacerStrategy(
        self: *FontSet,
        buffer: *ShapeBuffer,
        glyph_storage: []Glyph,
        face_index: u8,
    ) GroupError!SpacerStrategy {
        return fontOwner(self).value.spacerStrategy(
            &shapeOwner(buffer).value,
            glyph_storage,
            face_index,
        );
    }

    /// Rasterizes one glyph into one bounded cell-normalized alpha mask.
    pub fn rasterize(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        maximum_width_px: u16,
    ) RasterError!Raster {
        return fontOwner(self).value.rasterize(
            allocator,
            face_index,
            glyph_id,
            maximum_width_px,
        );
    }

    /// Rasterizes one glyph with bearings retained for multi-cell clipping.
    pub fn rasterizeGroup(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        maximum_width_px: u16,
    ) RasterError!Raster {
        return fontOwner(self).value.rasterizeGroup(
            allocator,
            face_index,
            glyph_id,
            maximum_width_px,
        );
    }
};

const ShapeOwner = struct {
    allocator: std.mem.Allocator,
    value: engine.ShapeBuffer,
};

/// Opaque owner of one bounded reusable native shaping buffer.
pub const ShapeBuffer = opaque {
    /// Allocates one opaque owner and preallocates native shaping capacity.
    pub fn init(
        allocator: std.mem.Allocator,
        capacity: u32,
    ) ShapeBufferInitError!*ShapeBuffer {
        if (capacity == 0 or capacity > max_glyphs) return error.InvalidCapacity;
        const owner = allocator.create(ShapeOwner) catch return error.OutOfMemory;
        errdefer allocator.destroy(owner);
        owner.* = .{
            .allocator = allocator,
            .value = try engine.ShapeBuffer.init(capacity),
        };
        return @ptrCast(owner);
    }

    /// Releases native shaping storage and the opaque owner exactly once.
    pub fn deinit(self: *ShapeBuffer) void {
        const owner = shapeOwner(self);
        const allocator = owner.allocator;
        owner.value.deinit();
        allocator.destroy(owner);
    }
};

fn fontOwner(value: *FontSet) *FontOwner {
    return @ptrCast(@alignCast(value));
}

fn fontOwnerConst(value: *const FontSet) *const FontOwner {
    return @ptrCast(@alignCast(value));
}

fn shapeOwner(value: *ShapeBuffer) *ShapeOwner {
    return @ptrCast(@alignCast(value));
}
