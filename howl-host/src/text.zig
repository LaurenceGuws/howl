//! Owns the render thread's font set and fixed GLES alpha atlas.

const std = @import("std");
const howl_text = @import("howl_text");
const terminal = @import("terminal.zig");
const c = @import("native.zig").c;

/// Reserves a fixed 16x16 texture grid: one solid mask and 255 glyph masks.
pub const atlas_capacity: usize = 255;
const atlas_columns: u16 = 16;
const atlas_slots: u16 = atlas_capacity + 1;
/// Bounds shaped output to howl-vt's base scalar plus three trailing scalars.
pub const max_cell_glyphs: usize = 1 + terminal.max_combining;

/// Reports exact font, shaping, raster, atlas, or GLES ownership failure.
pub const Error = std.mem.Allocator.Error || howl_text.ShapeError ||
    howl_text.RasterError || howl_text.GeneratedError || error{
    InvalidMetrics,
    GlyphTooLarge,
    GlyphRunTooLarge,
    AtlasFull,
    InvalidGeneration,
    TextureTooLarge,
    TextureCreateFailed,
    TextureUploadFailed,
    TextureCleanupFailed,
};

/// Reports font construction together with atlas initialization failures.
pub const InitError = howl_text.InitError || Error;

/// Identifies one raster by every input that can change its alpha or geometry
/// during this FontSet lifetime.
pub const Key = union(enum) {
    native: struct {
        face: u8,
        glyph: u32,
        cell_span: u8,
    },
    generated: struct {
        codepoint: u21,
        width: u16,
        height: u16,
    },
};

const Entry = struct {
    key: Key,
    slot: u16,
    last_used_generation: u64,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

const Entries = struct {
    values: [atlas_capacity]Entry = undefined,
    count: u16 = 0,
    generation: u64 = 0,

    const Admission = struct {
        index: u16,
        slot: u16,
    };

    fn beginFrame(self: *Entries, generation: u64) error{InvalidGeneration}!void {
        if (generation == 0 or generation <= self.generation)
            return error.InvalidGeneration;
        self.generation = generation;
    }

    fn find(self: *Entries, key: Key) ?Entry {
        for (self.values[0..self.count]) |*entry| {
            if (!std.meta.eql(entry.key, key)) continue;
            entry.last_used_generation = self.generation;
            return entry.*;
        }
        return null;
    }

    fn admit(
        self: *const Entries,
    ) error{AtlasFull}!Admission {
        if (self.count < self.values.len) return .{
            .index = self.count,
            .slot = self.count + 1,
        };
        var oldest_index: ?u16 = null;
        var oldest_generation: u64 = std.math.maxInt(u64);
        for (self.values[0..self.count], 0..) |entry, index| {
            if (entry.last_used_generation == self.generation) continue;
            if (entry.last_used_generation < oldest_generation) {
                oldest_index = @intCast(index);
                oldest_generation = entry.last_used_generation;
            }
        }
        const index = oldest_index orelse return error.AtlasFull;
        return .{ .index = index, .slot = index + 1 };
    }

    fn commit(self: *Entries, admission: Admission, entry: Entry) void {
        std.debug.assert(entry.slot == admission.slot);
        std.debug.assert(admission.index <= self.count);
        self.values[admission.index] = entry;
        if (admission.index == self.count) self.count += 1;
    }

    fn finishUpload(
        self: *Entries,
        admission: Admission,
        result: error{TextureUploadFailed}!Entry,
    ) error{TextureUploadFailed}!Entry {
        const entry = try result;
        self.commit(admission, entry);
        return entry;
    }
};

/// Carries one atlas-backed glyph and exact 26.6 placement offsets.
pub const Glyph = struct {
    slot: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    x_offset: i32,
    y_offset: i32,
};

/// Holds every glyph emitted for one terminal cell.
pub const CellGlyphs = struct {
    values: [max_cell_glyphs]Glyph = undefined,
    count: u8 = 0,

    /// Returns only initialized glyph facts.
    pub fn slice(self: *const CellGlyphs) []const Glyph {
        return self.values[0..self.count];
    }
};

/// Exclusively owns one FontSet, one texture, and fixed atlas entries.
pub const Text = struct {
    allocator: std.mem.Allocator,
    fonts: howl_text.FontSet,
    texture: c.GLuint,
    metrics: howl_text.Metrics,
    slot_width: u16,
    slot_height: u16,
    texture_width: u16,
    texture_height: u16,
    entries: Entries = .{},

    /// Opens one explicit primary font and creates an empty bounded alpha atlas.
    pub fn init(
        allocator: std.mem.Allocator,
        font_path: []const u8,
    ) InitError!Text {
        var fonts = try howl_text.FontSet.init(allocator, .{
            .primary = font_path,
            .pixel_height = 18,
        });
        errdefer fonts.deinit();
        const metrics = fonts.metrics;
        const slot_width = std.math.mul(u16, metrics.cell_width, 2) catch
            return error.InvalidMetrics;
        const slot_height = std.math.mul(u16, metrics.cell_height, 2) catch
            return error.InvalidMetrics;
        if (slot_width == 0 or slot_height == 0 or
            slot_width > howl_text.max_generated_extent_px or
            slot_height > howl_text.max_generated_extent_px)
            return error.InvalidMetrics;
        const rows = (atlas_slots + atlas_columns - 1) / atlas_columns;
        const texture_width = std.math.mul(u16, slot_width, atlas_columns) catch
            return error.TextureTooLarge;
        const texture_height = std.math.mul(u16, slot_height, rows) catch
            return error.TextureTooLarge;
        var maximum_texture: c.GLint = 0;
        c.glGetIntegerv(c.GL_MAX_TEXTURE_SIZE, &maximum_texture);
        if (maximum_texture <= 0 or texture_width > maximum_texture or
            texture_height > maximum_texture)
            return error.TextureTooLarge;

        var texture: c.GLuint = 0;
        c.glGenTextures(1, &texture);
        if (texture == 0 or c.glGetError() != c.GL_NO_ERROR)
            return error.TextureCreateFailed;
        errdefer deleteTextureRollback(texture);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_ALPHA,
            texture_width,
            texture_height,
            0,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            null,
        );
        const solid: u8 = 255;
        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            0,
            0,
            1,
            1,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            &solid,
        );
        if (c.glGetError() != c.GL_NO_ERROR)
            return error.TextureUploadFailed;
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .texture = texture,
            .metrics = metrics,
            .slot_width = slot_width,
            .slot_height = slot_height,
            .texture_width = texture_width,
            .texture_height = texture_height,
        };
    }

    /// Begins one strictly newer prepared frame. Cache hits and admissions
    /// during that frame are pinned until the next prepared generation.
    pub fn beginFrame(self: *Text, generation: u64) Error!void {
        try self.entries.beginFrame(generation);
    }

    /// Resolves one nonblank terminal cell through generated or native text.
    pub fn resolve(
        self: *Text,
        codepoints: []const u32,
        cell_span: u8,
    ) Error!CellGlyphs {
        if (cell_span == 0 or codepoints.len == 0 or
            codepoints.len > max_cell_glyphs)
            return error.InvalidText;
        const first = std.math.cast(u21, codepoints[0]) orelse
            return error.InvalidText;
        if (codepoints.len == 1 and
            howl_text.classifyGenerated(first) != null)
        {
            const entry = try self.generated(first, cell_span);
            return .{
                .values = initialized: {
                    var values: [max_cell_glyphs]Glyph = undefined;
                    values[0] = glyphFromEntry(entry, 0, 0);
                    break :initialized values;
                },
                .count = 1,
            };
        }
        const clusters = [_]u32{0} ** max_cell_glyphs;
        var run = try self.fonts.shape(self.allocator, .{
            .codepoints = codepoints,
            .clusters = clusters[0..codepoints.len],
            .cell_span = cell_span,
        });
        defer run.deinit();
        if (run.glyphs.len > max_cell_glyphs) return error.GlyphRunTooLarge;
        var result = CellGlyphs{};
        var pen_x: i32 = 0;
        var pen_y: i32 = 0;
        for (run.glyphs) |glyph| {
            const entry = try self.native(
                run.face_index,
                glyph.id,
                cell_span,
            );
            result.values[result.count] = glyphFromEntry(
                entry,
                std.math.add(i32, pen_x, glyph.x_offset) catch
                    return error.InvalidShapeResult,
                std.math.add(i32, pen_y, glyph.y_offset) catch
                    return error.InvalidShapeResult,
            );
            result.count += 1;
            pen_x = std.math.add(i32, pen_x, glyph.x_advance) catch
                return error.InvalidShapeResult;
            pen_y = std.math.add(i32, pen_y, glyph.y_advance) catch
                return error.InvalidShapeResult;
        }
        return result;
    }

    /// Returns normalized texture bounds for one committed slot and mask size.
    pub fn textureRect(
        self: *const Text,
        slot: u16,
        width: u16,
        height: u16,
    ) [4]f32 {
        const x = slot % atlas_columns * self.slot_width;
        const y = slot / atlas_columns * self.slot_height;
        const left = @as(f32, @floatFromInt(x)) + 0.5;
        const top = @as(f32, @floatFromInt(y)) + 0.5;
        const right = @as(f32, @floatFromInt(x + width)) - 0.5;
        const bottom = @as(f32, @floatFromInt(y + height)) - 0.5;
        return .{
            left / @as(f32, @floatFromInt(self.texture_width)),
            top / @as(f32, @floatFromInt(self.texture_height)),
            right / @as(f32, @floatFromInt(self.texture_width)),
            bottom / @as(f32, @floatFromInt(self.texture_height)),
        };
    }

    /// Releases the atlas texture and FontSet after all render-thread use ends.
    pub fn deinit(self: *Text) Error!void {
        c.glDeleteTextures(1, &self.texture);
        const failed = c.glGetError() != c.GL_NO_ERROR;
        self.fonts.deinit();
        self.* = undefined;
        if (failed) return error.TextureCleanupFailed;
    }

    fn generated(self: *Text, codepoint: u21, cell_span: u8) Error!Entry {
        const width = std.math.mul(
            u16,
            self.metrics.cell_width,
            cell_span,
        ) catch return error.InvalidText;
        if (width > self.slot_width) return error.GlyphTooLarge;
        const key = Key{ .generated = .{
            .codepoint = codepoint,
            .width = width,
            .height = self.metrics.cell_height,
        } };
        if (self.entries.find(key)) |entry| return entry;
        const admission = try self.entries.admit();
        const count = @as(usize, width) * self.metrics.cell_height;
        const pixels = try self.allocator.alloc(u8, count);
        defer self.allocator.free(pixels);
        try howl_text.rasterizeGenerated(
            pixels,
            width,
            self.metrics.cell_height,
            codepoint,
        );
        const entry = Entry{
            .key = key,
            .slot = admission.slot,
            .last_used_generation = self.entries.generation,
            .width = width,
            .height = self.metrics.cell_height,
            .left = 0,
            .top = @intCast(self.metrics.baseline),
        };
        return self.entries.finishUpload(
            admission,
            self.uploadedEntry(entry, pixels),
        );
    }

    fn native(
        self: *Text,
        face: u8,
        glyph_id: u32,
        cell_span: u8,
    ) Error!Entry {
        const key = Key{ .native = .{
            .face = face,
            .glyph = glyph_id,
            .cell_span = cell_span,
        } };
        if (self.entries.find(key)) |entry| return entry;
        const admission = try self.entries.admit();
        var raster = try self.fonts.rasterize(
            self.allocator,
            face,
            glyph_id,
            cell_span,
        );
        defer raster.deinit();
        if (raster.width > self.slot_width or raster.height > self.slot_height)
            return error.GlyphTooLarge;
        const entry = Entry{
            .key = key,
            .slot = admission.slot,
            .last_used_generation = self.entries.generation,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
        };
        return self.entries.finishUpload(
            admission,
            if (raster.width != 0 and raster.height != 0)
                self.uploadedEntry(entry, raster.pixels)
            else
                entry,
        );
    }

    fn uploadedEntry(
        self: *Text,
        entry: Entry,
        pixels: []const u8,
    ) error{TextureUploadFailed}!Entry {
        const x = entry.slot % atlas_columns * self.slot_width;
        const y = entry.slot / atlas_columns * self.slot_height;
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            x,
            y,
            entry.width,
            entry.height,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );
        // A rejected upload may have changed the victim texture region.
        // Metadata stays unchanged and the render owner treats this failure as
        // terminal, so no later lookup can observe an uncertain slot.
        if (c.glGetError() != c.GL_NO_ERROR)
            return error.TextureUploadFailed;
        return entry;
    }
};

fn glyphFromEntry(entry: Entry, x_offset: i32, y_offset: i32) Glyph {
    return .{
        .slot = entry.slot,
        .width = entry.width,
        .height = entry.height,
        .left = entry.left,
        .top = entry.top,
        .x_offset = x_offset,
        .y_offset = y_offset,
    };
}

fn deleteTextureRollback(texture: c.GLuint) void {
    c.glDeleteTextures(1, &texture);
    if (c.glGetError() != c.GL_NO_ERROR)
        @panic("GLES rejected an owned text texture during rollback");
}

test "atlas admits empty slots and keeps repeated keys in one slot" {
    var entries = Entries{};
    try entries.beginFrame(1);
    const first = Key{ .native = .{
        .face = 0,
        .glyph = 1,
        .cell_span = 1,
    } };
    const first_admission = try entries.admit();
    const first_entry = Entry{
        .key = first,
        .slot = first_admission.slot,
        .last_used_generation = 1,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 0,
    };
    entries.commit(first_admission, first_entry);
    try std.testing.expectEqualDeep(first_entry, entries.find(first).?);
    try std.testing.expect(entries.find(.{ .native = .{
        .face = 0,
        .glyph = 1,
        .cell_span = 2,
    } }) == null);
    const second_key = Key{ .native = .{
        .face = 0,
        .glyph = 1,
        .cell_span = 2,
    } };
    const second_admission = try entries.admit();
    const second_entry = Entry{
        .key = second_key,
        .slot = second_admission.slot,
        .last_used_generation = 1,
        .width = 2,
        .height = 1,
        .left = 0,
        .top = 0,
    };
    entries.commit(second_admission, second_entry);
    try std.testing.expect(first_entry.slot != second_entry.slot);
    try std.testing.expectEqualDeep(second_entry, entries.find(second_key).?);
    try std.testing.expectEqualDeep(second_entry, entries.find(second_key).?);
    try std.testing.expectEqual(@as(u16, 2), entries.count);
    try std.testing.expect(entries.find(.{ .generated = .{
        .codepoint = 0x2500,
        .width = 8,
        .height = 16,
    } }) == null);
}

test "atlas evicts oldest generation with lowest-slot tie break" {
    var entries = Entries{};
    try entries.beginFrame(2);
    while (entries.count < atlas_capacity) {
        const admission = try entries.admit();
        entries.commit(admission, .{
            .key = .{ .native = .{
                .face = 0,
                .glyph = admission.slot,
                .cell_span = 1,
            } },
            .slot = admission.slot,
            .last_used_generation = if (admission.slot <= 2) 1 else 2,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 0,
        });
    }
    try entries.beginFrame(3);
    const evicted_key = entries.values[0].key;
    const oldest = try entries.admit();
    try std.testing.expectEqual(@as(u16, 0), oldest.index);
    try std.testing.expectEqual(@as(u16, 1), oldest.slot);
    const replacement = Entry{
        .key = .{ .native = .{
            .face = 0,
            .glyph = 999,
            .cell_span = 1,
        } },
        .slot = oldest.slot,
        .last_used_generation = 3,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 0,
    };
    entries.commit(oldest, replacement);
    try std.testing.expectEqualDeep(
        replacement,
        entries.find(replacement.key).?,
    );
    try std.testing.expect(entries.find(evicted_key) == null);
    try std.testing.expectEqual(@as(u16, atlas_capacity), entries.count);
}

test "current-frame pins reject partial admission without metadata mutation" {
    var entries = Entries{};
    try entries.beginFrame(7);
    while (entries.count < atlas_capacity) {
        const admission = try entries.admit();
        entries.commit(admission, .{
            .key = .{ .native = .{
                .face = 0,
                .glyph = admission.slot,
                .cell_span = 1,
            } },
            .slot = admission.slot,
            .last_used_generation = 7,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 0,
        });
    }
    const before = entries;
    try std.testing.expectError(error.AtlasFull, entries.admit());
    try std.testing.expectEqualDeep(before, entries);
}

test "admission and failed upload leave metadata unchanged until one commit" {
    var entries = Entries{};
    try entries.beginFrame(1);
    while (entries.count < atlas_capacity) {
        const admission = try entries.admit();
        entries.commit(admission, .{
            .key = .{ .native = .{
                .face = 0,
                .glyph = admission.slot,
                .cell_span = 1,
            } },
            .slot = admission.slot,
            .last_used_generation = 1,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 0,
        });
    }
    try entries.beginFrame(2);
    const admission = try entries.admit();
    const before = entries;
    try std.testing.expectError(
        error.TextureUploadFailed,
        entries.finishUpload(admission, error.TextureUploadFailed),
    );
    try std.testing.expectEqualDeep(before, entries);
    const committed = try entries.finishUpload(admission, Entry{
        .key = .{ .native = .{
            .face = 0,
            .glyph = 999,
            .cell_span = 1,
        } },
        .slot = admission.slot,
        .last_used_generation = 2,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 0,
    });
    try std.testing.expectEqual(@as(u16, 1), committed.slot);
    try std.testing.expectEqual(@as(u16, atlas_capacity), entries.count);
    try std.testing.expectEqual(@as(u32, 1), before.values[0].key.native.glyph);
    try std.testing.expectEqual(@as(u32, 999), entries.values[0].key.native.glyph);
    try std.testing.expectEqual(@as(u32, 2), entries.values[1].key.native.glyph);
}

test "only prepared generations advance atlas usage" {
    var entries = Entries{};
    try entries.beginFrame(1);
    const admission = try entries.admit();
    const key = Key{ .native = .{
        .face = 0,
        .glyph = 7,
        .cell_span = 1,
    } };
    entries.commit(admission, .{
        .key = key,
        .slot = admission.slot,
        .last_used_generation = 1,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 0,
    });

    // Generation 2 is coalesced before preparation, so the next observed
    // generation moves directly from 1 to 3.
    try entries.beginFrame(3);
    _ = entries.find(key).?;
    try std.testing.expectEqual(
        @as(u64, 3),
        entries.values[0].last_used_generation,
    );
    try std.testing.expectError(error.InvalidGeneration, entries.beginFrame(2));
    try std.testing.expectError(error.InvalidGeneration, entries.beginFrame(3));
}

test "frozen text dependency shapes rasters and reports exact failures" {
    const paths = @import("host_test_paths");
    var fonts = try howl_text.FontSet.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer fonts.deinit();
    const codepoints = [_]u32{'A'};
    const clusters = [_]u32{0};
    var run = try fonts.shape(std.testing.allocator, .{
        .codepoints = &codepoints,
        .clusters = &clusters,
        .cell_span = 1,
    });
    defer run.deinit();
    try std.testing.expect(run.glyphs.len > 0);
    var raster = try fonts.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        1,
    );
    defer raster.deinit();
    try std.testing.expect(raster.pixels.len > 0);
    try std.testing.expectError(
        error.InvalidRaster,
        fonts.rasterize(std.testing.allocator, run.face_index, 0, 1),
    );
    const missing = [_]u32{0x10ffff};
    try std.testing.expectError(error.MissingGlyph, fonts.shape(
        std.testing.allocator,
        .{ .codepoints = &missing, .clusters = &clusters, .cell_span = 1 },
    ));

    const generated_count = @as(usize, fonts.metrics.cell_width) *
        fonts.metrics.cell_height;
    const generated = try std.testing.allocator.alloc(u8, generated_count);
    defer std.testing.allocator.free(generated);
    try howl_text.rasterizeGenerated(
        generated,
        fonts.metrics.cell_width,
        fonts.metrics.cell_height,
        0x2500,
    );
    try std.testing.expect(std.mem.indexOfScalar(u8, generated, 255) != null);
}

test "frozen cell sequences shape within four glyphs and whitespace stays empty" {
    const paths = @import("host_test_paths");
    var fonts = try howl_text.FontSet.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer fonts.deinit();
    const clusters = [_]u32{0} ** max_cell_glyphs;
    for ([_][]const u32{
        &.{ 'o', 0x0300 },
        &.{ 'o', 0x0300, 0x0301, 0x0302 },
    }) |codepoints| {
        var run = try fonts.shape(std.testing.allocator, .{
            .codepoints = codepoints,
            .clusters = clusters[0..codepoints.len],
            .cell_span = 1,
        });
        defer run.deinit();
        try std.testing.expect(run.glyphs.len > 0);
        try std.testing.expect(run.glyphs.len <= max_cell_glyphs);
        for (run.glyphs) |glyph| {
            var raster = try fonts.rasterize(
                std.testing.allocator,
                run.face_index,
                glyph.id,
                1,
            );
            raster.deinit();
        }
    }

    var space = try fonts.shape(std.testing.allocator, .{
        .codepoints = &.{' '},
        .clusters = &.{0},
        .cell_span = 1,
    });
    defer space.deinit();
    try std.testing.expectEqual(@as(usize, 1), space.glyphs.len);
    var raster = try fonts.rasterize(
        std.testing.allocator,
        space.face_index,
        space.glyphs[0].id,
        1,
    );
    defer raster.deinit();
    try std.testing.expectEqual(@as(u16, 0), raster.width);
    try std.testing.expectEqual(@as(u16, 0), raster.height);
    try std.testing.expectEqual(@as(usize, 0), raster.pixels.len);
}
