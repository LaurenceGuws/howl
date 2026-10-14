//! Private native presentation admission and one caller Store reference.
//! C-created Stores have only try-claim/immutable/release users; no waiter exists.
const std = @import("std");
const instance = @import("howl_instance");
const c = @import("instance_native").c;
const text = instance.text;
const terminal = instance.render.terminal;

/// Rejects malformed descriptors or native resource ceilings before construction.
pub const AdmissionError = error{ InvalidArgument, ResourceLimit };
/// Includes canonical font/store failures after admission.
pub const CreateError = AdmissionError || instance.PresentationStoreInitError;

/// The foreign caller owns this wrapper; Instances retain only value directly.
pub const Owner = struct {
    allocator: std.mem.Allocator,
    value: *instance.PresentationStore,
    config: terminal.StoreConfig,
};

comptime {
    if (c.HI_MAX_FONT_FALLBACKS != text.max_fallbacks or
        c.HI_MAX_FONT_PATH_BYTES != text.max_font_path_bytes or
        c.HI_MAX_FONT_BYTES != text.max_font_bytes or
        c.HI_MAX_FONT_SET_BYTES != text.max_font_set_bytes or
        c.HI_MAX_PRESENTATION_RASTER_BYTES != text.max_raster_bytes or
        c.HI_MAX_PRESENTATION_SHAPED != text.max_codepoints or
        c.HI_MAX_PRESENTATION_SHAPED != text.max_glyphs or
        c.HI_MAX_PRESENTATION_ROWS != instance.render.limits.maximum_rows)
        @compileError("Native presentation bounds must match their exact child owners");
}

fn item(value: usize) AdmissionError!void {
    if (value > c.HI_MAX_PRESENTATION_ITEMS) return error.ResourceLimit;
    if (value == 0) return error.InvalidArgument;
}

fn storeConfig(config: *const c.hi_presentation_config) AdmissionError!terminal.StoreConfig {
    if (config.reserved != 0 or config.pixel_size == 0) return error.InvalidArgument;
    try item(config.shape_entries);
    try item(config.shape_scalars);
    try item(config.shape_glyphs);
    if (config.max_sequence_scalars > c.HI_MAX_PRESENTATION_SHAPED or
        config.shaped_capacity > c.HI_MAX_PRESENTATION_SHAPED or
        config.raster_bytes > c.HI_MAX_PRESENTATION_RASTER_BYTES)
        return error.ResourceLimit;
    if (config.max_sequence_scalars == 0 or config.shaped_capacity == 0 or
        config.raster_bytes == 0 or config.max_sequence_scalars > config.shape_scalars)
        return error.InvalidArgument;
    return .{
        .shape_cache = .{
            .entry_capacity = config.shape_entries,
            .scalar_capacity = config.shape_scalars,
            .glyph_capacity = config.shape_glyphs,
            .max_sequence_scalars = config.max_sequence_scalars,
        },
        .shaped_capacity = config.shaped_capacity,
        .raster_bytes = config.raster_bytes,
    };
}

const Kind = enum { none, path, memory };
const Source = struct {
    kind: Kind = .none,
    primary: []const u8 = "",
    fallbacks: [text.max_fallbacks][]const u8 = undefined,
    count: usize = 0,
};

fn sourceBytes(value: c.hi_bytes, kind: Kind) AdmissionError![]const u8 {
    const maximum: usize = switch (kind) {
        .path => text.max_font_path_bytes,
        .memory => text.max_font_bytes,
        .none => return error.InvalidArgument,
    };
    if (value.len > maximum) return error.ResourceLimit;
    if (value.len == 0 or value.data == null) return error.InvalidArgument;
    const data = value.data[0..value.len];
    if (kind == .path and std.mem.indexOfScalar(u8, data, 0) != null)
        return error.InvalidArgument;
    return data;
}

/// Uses stable caller storage: returned family slices borrow these fallback arrays.
const Fonts = struct {
    sources: [4]Source = .{ .{}, .{}, .{}, .{} },
    pixels: u16 = 0,

    fn init(self: *Fonts, config: *const c.hi_presentation_config) AdmissionError!void {
        self.* = .{ .pixels = config.pixel_size };
        for (config.fonts, 0..) |source, index| {
            if (!std.mem.allEqual(u8, &source.reserved, 0)) return error.InvalidArgument;
            const kind: Kind = switch (source.kind) {
                c.HI_FONT_NONE => .none,
                c.HI_FONT_PATH => .path,
                c.HI_FONT_MEMORY => .memory,
                else => return error.InvalidArgument,
            };
            if (kind == .none) {
                if (index == 0 or source.primary.data != null or source.primary.len != 0 or
                    source.fallbacks != null or source.fallback_count != 0)
                    return error.InvalidArgument;
                continue;
            }
            if (source.fallback_count > text.max_fallbacks) return error.ResourceLimit;
            if (source.fallback_count != 0 and source.fallbacks == null) return error.InvalidArgument;
            const primary = try sourceBytes(source.primary, kind);
            var total = primary.len;
            self.sources[index].kind = kind;
            self.sources[index].primary = primary;
            self.sources[index].count = source.fallback_count;
            for (0..source.fallback_count) |fallback| {
                const data = try sourceBytes(source.fallbacks[fallback], kind);
                if (kind == .memory) {
                    total = std.math.add(usize, total, data.len) catch return error.ResourceLimit;
                    if (total > text.max_font_set_bytes) return error.ResourceLimit;
                }
                self.sources[index].fallbacks[fallback] = data;
            }
        }
    }

    fn font(self: *const Fonts, index: usize) ?instance.FontConfig {
        const source = &self.sources[index];
        const size: text.Size = .{ .pixels = self.pixels };
        return switch (source.kind) {
            .none => null,
            .path => .{ .path = .{ .primary = source.primary, .fallbacks = source.fallbacks[0..source.count], .size = size } },
            .memory => .{ .memory = .{ .primary = source.primary, .fallbacks = source.fallbacks[0..source.count], .size = size } },
        };
    }

    fn family(self: *const Fonts) instance.FontFamilyConfig {
        return .{ .regular = self.font(0).?, .italic = self.font(1), .bold = self.font(2), .bold_italic = self.font(3) };
    }
};

/// Copies admitted font inputs into one canonical Store and caller reference.
pub fn create(allocator: std.mem.Allocator, config: *const c.hi_presentation_config) CreateError!*Owner {
    const limits = try storeConfig(config);
    var fonts: Fonts = .{};
    try fonts.init(config);
    // Only try-lock claimants may use this Io.failing Store. A blocking C
    // operation would require a different, explicitly owned Io lifetime first.
    const value = try instance.initPresentationStore(allocator, .failing, fonts.family(), limits);
    errdefer instance.releasePresentationStore(value);
    const owner = try allocator.create(Owner);
    owner.* = .{ .allocator = allocator, .value = value, .config = limits };
    return owner;
}

/// Drops the caller reference; retained Instances keep the Store alive.
pub fn release(owner: *Owner) void {
    const allocator = owner.allocator;
    instance.releasePresentationStore(owner.value);
    allocator.destroy(owner);
}

/// Admits per-Instance budgets and selects the matching shared Store.
pub fn instanceConfig(owner: *const Owner, config: *const c.hi_presented_config) AdmissionError!instance.PresentationConfig {
    if (!std.mem.allEqual(u8, &config.reserved, 0)) return error.InvalidArgument;
    try item(config.atlas_entries);
    try item(config.command_capacity);
    try item(config.command_limit);
    if (config.incremental_commands > c.HI_MAX_PRESENTATION_ITEMS or
        config.incremental_rows > c.HI_MAX_PRESENTATION_ROWS)
        return error.ResourceLimit;
    if (config.atlas_width == 0 or config.atlas_height == 0 or
        config.command_limit < config.command_capacity or
        ((config.incremental_rows == 0) != (config.incremental_commands == 0)))
        return error.InvalidArgument;
    const pixels = std.math.mul(usize, config.atlas_width, config.atlas_height) catch return error.ResourceLimit;
    if (pixels > c.HI_MAX_PRESENTATION_RASTER_BYTES) return error.ResourceLimit;
    const box: instance.BoxDrawingConfig = .{
        .stroke_points = config.stroke_points,
        .dpi_x = .{ .numerator = config.dpi_x_numerator, .denominator = config.dpi_x_denominator },
        .dpi_y = .{ .numerator = config.dpi_y_numerator, .denominator = config.dpi_y_denominator },
    };
    box.validate() catch return error.InvalidArgument;
    return .{
        .text = .{ .shared = owner.value },
        .box_drawing = box,
        .shape_cache = owner.config.shape_cache,
        .shaped_capacity = owner.config.shaped_capacity,
        .raster_bytes = owner.config.raster_bytes,
        .atlas = .{ .width = config.atlas_width, .height = config.atlas_height, .gap = config.atlas_gap, .entry_capacity = config.atlas_entries },
        .command_capacity = config.command_capacity,
        .command_limit = config.command_limit,
        .incremental_row_capacity = config.incremental_rows,
        .incremental_command_capacity = config.incremental_commands,
    };
}

fn testConfig() c.hi_presentation_config {
    const path = @import("test_fonts").primary_font;
    var config = std.mem.zeroes(c.hi_presentation_config);
    config.fonts[0] = .{ .kind = c.HI_FONT_PATH, .reserved = @splat(0), .primary = .{ .data = path.ptr, .len = path.len }, .fallbacks = null, .fallback_count = 0 };
    config.pixel_size = 18;
    config.max_sequence_scalars = 16;
    config.shape_entries = 256;
    config.shape_scalars = 512;
    config.shape_glyphs = 512;
    config.shaped_capacity = 1024;
    config.raster_bytes = 64 * 1024;
    return config;
}

fn testInstanceConfig() c.hi_presented_config {
    var config = std.mem.zeroes(c.hi_presented_config);
    config.stroke_points = .{ 0.001, 1, 1.5, 2 };
    config.dpi_x_numerator = 96;
    config.dpi_x_denominator = 1;
    config.dpi_y_numerator = 96;
    config.dpi_y_denominator = 1;
    config.atlas_width = 128;
    config.atlas_height = 128;
    config.atlas_gap = 1;
    config.atlas_entries = 256;
    config.command_capacity = 256;
    config.command_limit = 256;
    return config;
}

test "font admission checks tags and inactive fields before native font access" {
    var prepared: Fonts = .{};
    const original = testConfig();
    for (0..256) |tag| {
        var config = original;
        config.fonts[0].kind = @intCast(tag);
        if (tag == c.HI_FONT_PATH or tag == c.HI_FONT_MEMORY) {
            try prepared.init(&config);
        } else try std.testing.expectError(error.InvalidArgument, prepared.init(&config));
    }
    var bad = original;
    bad.fonts[1].primary.data = "ignored".ptr;
    try std.testing.expectError(error.InvalidArgument, prepared.init(&bad));
    bad = original;
    bad.fonts[0].reserved[6] = 1;
    try std.testing.expectError(error.InvalidArgument, prepared.init(&bad));
    bad = original;
    bad.fonts[0].fallback_count = text.max_fallbacks + 1;
    try std.testing.expectError(error.ResourceLimit, prepared.init(&bad));
    bad = original;
    bad.fonts[0].fallback_count = 1;
    try std.testing.expectError(error.InvalidArgument, prepared.init(&bad));
    bad = original;
    bad.fonts[0].primary.len = text.max_font_path_bytes + 1;
    try std.testing.expectError(error.ResourceLimit, prepared.init(&bad));
    bad = original;
    bad.fonts[0].primary = .{ .data = null, .len = 1 };
    try std.testing.expectError(error.InvalidArgument, prepared.init(&bad));
    bad = original;
    const nul = [_]u8{ 'a', 0, 'b' };
    bad.fonts[0].primary = .{ .data = &nul, .len = nul.len };
    try std.testing.expectError(error.InvalidArgument, prepared.init(&bad));
}

test "memory source aggregate bound and stable fallback slices match Text" {
    const data = try std.testing.allocator.alloc(u8, text.max_font_bytes);
    defer std.testing.allocator.free(data);
    var config = testConfig();
    var fallbacks = [_]c.hi_bytes{
        .{ .data = data.ptr, .len = data.len },
        .{ .data = data.ptr, .len = data.len },
    };
    config.fonts[0] = .{ .kind = c.HI_FONT_MEMORY, .reserved = @splat(0), .primary = .{ .data = data.ptr, .len = data.len }, .fallbacks = &fallbacks, .fallback_count = 1 };
    var prepared: Fonts = .{};
    try prepared.init(&config);
    const family = prepared.family();
    try std.testing.expect(family.regular == .memory);
    try std.testing.expectEqual(data.ptr, family.regular.memory.primary.ptr);
    try std.testing.expectEqual(data.ptr, family.regular.memory.fallbacks[0].ptr);
    config.fonts[0].fallback_count = 2;
    try std.testing.expectError(error.ResourceLimit, prepared.init(&config));
    config.fonts[0].fallback_count = 0;
    config.fonts[0].primary.len = text.max_font_bytes + 1;
    try std.testing.expectError(error.ResourceLimit, prepared.init(&config));
}

test "store and terminal capacity relationships fail before allocating" {
    const original = testConfig();
    inline for (.{ "shape_entries", "shape_scalars", "shape_glyphs", "shaped_capacity", "raster_bytes" }) |name| {
        var bad = original;
        @field(bad, name) = 0;
        try std.testing.expectError(error.InvalidArgument, storeConfig(&bad));
        @field(bad, name) = if (comptime std.mem.eql(u8, name, "raster_bytes"))
            c.HI_MAX_PRESENTATION_RASTER_BYTES + 1
        else if (comptime std.mem.eql(u8, name, "shaped_capacity"))
            c.HI_MAX_PRESENTATION_SHAPED + 1
        else
            c.HI_MAX_PRESENTATION_ITEMS + 1;
        try std.testing.expectError(error.ResourceLimit, storeConfig(&bad));
    }
    var bad = original;
    bad.max_sequence_scalars = @intCast(bad.shape_scalars + 1);
    try std.testing.expectError(error.InvalidArgument, storeConfig(&bad));
    bad = original;
    bad.max_sequence_scalars = c.HI_MAX_PRESENTATION_SHAPED + 1;
    try std.testing.expectError(error.ResourceLimit, storeConfig(&bad));
    bad = original;
    bad.reserved = 1;
    try std.testing.expectError(error.InvalidArgument, storeConfig(&bad));

    // A real Store is needed only after admission checks are independently proved.
    const owner = try create(std.testing.allocator, &original);
    defer release(owner);
    var options = testInstanceConfig();
    options.command_limit = options.command_capacity - 1;
    try std.testing.expectError(error.InvalidArgument, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.incremental_rows = 1;
    try std.testing.expectError(error.InvalidArgument, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.incremental_rows = c.HI_MAX_PRESENTATION_ROWS + 1;
    try std.testing.expectError(error.ResourceLimit, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.atlas_width = 8192;
    options.atlas_height = 8192;
    try std.testing.expectError(error.ResourceLimit, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.stroke_points[1] = std.math.nan(f32);
    try std.testing.expectError(error.InvalidArgument, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.dpi_x_numerator = 192;
    options.dpi_x_denominator = 2;
    try std.testing.expectError(error.InvalidArgument, instanceConfig(owner, &options));
    options = testInstanceConfig();
    options.reserved[7] = 1;
    try std.testing.expectError(error.InvalidArgument, instanceConfig(owner, &options));
    const valid = testInstanceConfig();
    const selected = try instanceConfig(owner, &valid);
    try std.testing.expect(selected.text == .shared);
    try std.testing.expect(selected.text.shared == owner.value);
    try std.testing.expectEqualDeep(owner.config.shape_cache, selected.shape_cache);
}

fn allocationProof(allocator: std.mem.Allocator) !void {
    const config = testConfig();
    const owner = try create(allocator, &config);
    defer release(owner);
    try std.testing.expectEqual(@as(u32, 1), instance.presentationStoreReferences(owner.value));
    const size = instance.presentationStoreCellSize(owner.value);
    try std.testing.expect(size.width != 0 and size.height != 0);
}

test "font Store and wrapper allocation prefixes release every owned resource" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProof, .{});
}

test "failed later style destroys already opened regular fonts" {
    var config = testConfig();
    const invalid = "not-a-font";
    config.fonts[1] = .{ .kind = c.HI_FONT_MEMORY, .reserved = @splat(0), .primary = .{ .data = invalid.ptr, .len = invalid.len }, .fallbacks = null, .fallback_count = 0 };
    try std.testing.expectError(error.FontOpen, create(std.testing.allocator, &config));
    config.fonts[1] = std.mem.zeroes(c.hi_font_source);
    const owner = try create(std.testing.allocator, &config);
    release(owner);
}
