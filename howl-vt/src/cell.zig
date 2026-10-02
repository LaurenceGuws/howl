//! Canonical terminal cell, color, and retained-row geometry value vocabulary.

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
