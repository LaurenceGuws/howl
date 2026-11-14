//! Canonical terminal cell, color, and retained-row geometry value vocabulary.

const std = @import("std");

/// Stores one exact 24-bit terminal color.
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// Classifies one terminal color independently from its internal storage.
pub const ColorKind = enum(u8) {
    default,
    indexed,
    rgb,
};

/// Stores a default, indexed, or RGB terminal color.
pub const Color = struct {
    kind: ColorKind,
    value: u32,

    /// Returns the semantic terminal-color class.
    pub fn colorKind(self: Color) ColorKind {
        return self.kind;
    }

    /// Returns zero for default, palette index for indexed, or 0xRRGGBB for RGB.
    pub fn colorValue(self: Color) u32 {
        return self.value;
    }

    /// Constructs an indexed terminal color.
    pub fn indexed(idx: u8) Color {
        return .{ .kind = .indexed, .value = idx };
    }

    /// Constructs an exact RGB terminal color.
    pub fn rgb(rgb_value: Rgb) Color {
        return .{
            .kind = .rgb,
            .value = (@as(u32, rgb_value.r) << 16) |
                (@as(u32, rgb_value.g) << 8) |
                @as(u32, rgb_value.b),
        };
    }

    /// Returns an exact RGB terminal color.
    pub fn rgbComponents(r: u8, g: u8, b: u8) Color {
        return rgb(.{ .r = r, .g = g, .b = b });
    }

    /// Resolves this color against one complete terminal palette and caller-selected default.
    pub fn resolve(self: Color, default_value: Rgb, palette: *const [256]Rgb) Rgb {
        return switch (self.kind) {
            .default => default_value,
            .indexed => palette[@as(u8, @intCast(self.value))],
            .rgb => .{
                .r = @truncate(self.value >> 16),
                .g = @truncate(self.value >> 8),
                .b = @truncate(self.value),
            },
        };
    }
};

/// Identifies the supported terminal underline presentation styles.
pub const UnderlineStyle = enum(u3) {
    straight,
    double,
    curly,
    dotted,
    dashed,
};

/// Identifies the baseline displacement retained for one terminal cell.
pub const Baseline = enum(u2) {
    normal,
    raised,
    lowered,
};

/// Distinguishes ISO guarded areas from DEC selective-erase protection.
pub const Protection = enum(u2) {
    none,
    iso,
    dec,
};

/// Stores one cell's font, baseline, style, colors, protection, and hyperlink identity.
pub const CellAttrs = struct {
    fg: Color,
    bg: Color,
    font: u4,
    baseline: Baseline,
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
    underline_style: UnderlineStyle,
    underline_color: Color,
    protected: Protection,
    link_id: u32,
};

/// Stores one bounded Unicode cluster, ordinary or OSC 66 placement, and complete attributes.
pub const Cell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [3]u32 = .{ 0, 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    subscale_n: u4 = 0,
    subscale_d: u4 = 0,
    vertical_align: u2 = 0,
    horizontal_align: u2 = 0,
    semantic_width: bool = false,
    attrs: CellAttrs,
};

/// Describes one row's DEC presentation geometry without prescribing caller presentation.
pub const LineGeometry = enum(u2) {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

/// Provides the immutable default foreground color.
pub const default_foreground = Color{ .kind = .default, .value = 0 };
/// Provides the immutable default background color.
pub const default_background = Color{ .kind = .default, .value = 0 };
/// Provides the immutable default underline color.
pub const default_underline_color = Color{ .kind = .default, .value = 0 };

/// Provides immutable default terminal cell attributes.
pub const default_attrs = CellAttrs{
    .fg = default_foreground,
    .bg = default_background,
    .font = 0,
    .baseline = .normal,
    .bold = false,
    .dim = false,
    .italic = false,
    .blink = false,
    .blink_fast = false,
    .reverse = false,
    .invisible = false,
    .underline = false,
    .strikethrough = false,
    .underline_style = .straight,
    .underline_color = default_underline_color,
    .protected = .none,
    .link_id = 0,
};

/// Provides the canonical blank terminal cell.
pub const blank = Cell{
    .codepoint = 0,
    .attrs = default_attrs,
};

/// Reports whether one cell is a continuation of a lead cell.
pub fn isContinuation(value: Cell) bool {
    return value.x != 0 or value.y != 0;
}

/// Reports whether one cell is the lead of a semantic double-width cluster.
pub fn isSemanticWideLead(value: Cell) bool {
    return value.semantic_width and value.width == 2 and
        value.height == 1 and value.x == 0 and value.y == 0;
}

/// Reports whether one cell belongs to a semantic double-width cluster.
pub fn isSemanticWideCell(value: Cell) bool {
    return value.semantic_width and value.width == 2 and
        value.height == 1 and value.x < 2 and value.y == 0;
}

/// Compares every attribute value without inspecting object padding.
pub fn attrsEqual(left: *const CellAttrs, right: *const CellAttrs) bool {
    inline for (@typeInfo(CellAttrs).@"struct".field_names, @typeInfo(CellAttrs).@"struct".field_types) |field_name, field_type| {
        const a = @field(left.*, field_name);
        const b = @field(right.*, field_name);
        if (field_type == Color) {
            if (a.kind != b.kind or a.value != b.value) return false;
        } else if (a != b) return false;
    }
    return true;
}

/// Compares every cell value, including inactive scalar slots and rare placement fields.
pub fn cellsEqual(left: *const Cell, right: *const Cell) bool {
    inline for (@typeInfo(Cell).@"struct".field_names, @typeInfo(Cell).@"struct".field_types) |field_name, field_type| {
        const a = &@field(left.*, field_name);
        const b = &@field(right.*, field_name);
        if (field_type == CellAttrs) {
            if (!attrsEqual(a, b)) return false;
        } else if (field_type == [3]u32) {
            if (((a[0] ^ b[0]) | (a[1] ^ b[1]) | (a[2] ^ b[2])) != 0) return false;
        } else if (a.* != b.*) return false;
    }
    return true;
}

fn differentScalar(comptime T: type, value: T) T {
    return switch (@typeInfo(T)) {
        .bool => !value,
        .int => value ^ 1,
        .@"enum" => if (@backingInt(value) == @typeInfo(T).@"enum".field_values[0])
            @fromBackingInt(@intCast(@typeInfo(T).@"enum".field_values[1]))
        else
            @fromBackingInt(@intCast(@typeInfo(T).@"enum".field_values[0])),
        else => @compileError("add a value-domain proof for the new cell field"),
    };
}

fn expectDifferent(left: Cell, right: Cell) !void {
    try std.testing.expect(!std.meta.eql(left, right));
    try std.testing.expect(!cellsEqual(&left, &right));
    try std.testing.expect(!cellsEqual(&right, &left));
    try std.testing.expect(cellsEqual(&right, &right));
    try std.testing.expectEqual(std.meta.eql(left.attrs, right.attrs), attrsEqual(&left.attrs, &right.attrs));
}

test "cell equality covers every scalar array placement and attribute field" {
    const original = blank;
    inline for (@typeInfo(Cell).@"struct".field_names, @typeInfo(Cell).@"struct".field_types) |field_name, field_type| {
        if (field_type == CellAttrs) {
            inline for (@typeInfo(CellAttrs).@"struct".field_names, @typeInfo(CellAttrs).@"struct".field_types) |attr_name, attr_type| {
                if (attr_type == Color) {
                    inline for (@typeInfo(Color).@"struct".field_names, @typeInfo(Color).@"struct".field_types) |component_name, component_type| {
                        var changed = original;
                        const value = &@field(@field(changed.attrs, attr_name), component_name);
                        value.* = differentScalar(component_type, value.*);
                        try expectDifferent(original, changed);
                    }
                } else {
                    var changed = original;
                    const value = &@field(changed.attrs, attr_name);
                    value.* = differentScalar(attr_type, value.*);
                    try expectDifferent(original, changed);
                }
            }
        } else if (field_type == [3]u32) {
            for (0..3) |index| {
                var changed = original;
                @field(changed, field_name)[index] = 1;
                try expectDifferent(original, changed);
            }
        } else {
            var changed = original;
            const value = &@field(changed, field_name);
            value.* = differentScalar(field_type, value.*);
            try expectDifferent(original, changed);
        }
    }
}

test "cell equality ignores padding while preserving exact field values" {
    var left: Cell = undefined;
    var right: Cell = undefined;
    @memset(std.mem.asBytes(&left), 0xa5);
    @memset(std.mem.asBytes(&right), 0x5a);
    inline for (@typeInfo(Cell).@"struct".field_names, @typeInfo(Cell).@"struct".field_types) |field_name, field_type| {
        if (field_type == CellAttrs) {
            inline for (@typeInfo(CellAttrs).@"struct".field_names, @typeInfo(CellAttrs).@"struct".field_types) |attr_name, attr_type| {
                if (attr_type == Color) {
                    inline for (@typeInfo(Color).@"struct".field_names) |component_name| {
                        @field(@field(left.attrs, attr_name), component_name) = @field(@field(blank.attrs, attr_name), component_name);
                        @field(@field(right.attrs, attr_name), component_name) = @field(@field(blank.attrs, attr_name), component_name);
                    }
                } else {
                    @field(left.attrs, attr_name) = @field(blank.attrs, attr_name);
                    @field(right.attrs, attr_name) = @field(blank.attrs, attr_name);
                }
            }
        } else {
            @field(left, field_name) = @field(blank, field_name);
            @field(right, field_name) = @field(blank, field_name);
        }
    }
    try std.testing.expect(std.meta.eql(left, right));
    try std.testing.expect(cellsEqual(&left, &right));
    try std.testing.expect(attrsEqual(&left.attrs, &right.attrs));
}
