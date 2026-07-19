//! Defines terminal cell content, attributes, defaults, and continuation markers.

const color = @import("color.zig");

const Color = color.Color;

/// Identifies the supported terminal underline rendering styles.
pub const UnderlineStyle = enum(u3) {
    straight,
    double,
    curly,
    dotted,
    dashed,
};

/// Stores one cell’s style, colors, protection, and hyperlink identity.
pub const CellAttrs = struct {
    fg: Color,
    bg: Color,
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
    protected: bool,
    link_id: u32,
};

/// Stores one Unicode codepoint, display width, and complete cell attributes.
pub const Cell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [3]u32 = .{ 0, 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    attrs: CellAttrs,
};

fn isCellContinuation(cell: Cell) bool {
    return cell.x != 0 or cell.y != 0;
}

const default_fg = color.default_fg;
const default_bg = color.default_bg;
const default_underline_color = color.default_underline_color;

/// Provides immutable default terminal cell attributes.
pub const default_cell_attrs = CellAttrs{
    .fg = default_fg,
    .bg = default_bg,
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
    .protected = false,
    .link_id = 0,
};

/// Provides the blank default cell used for clearing and allocation.
pub const default_cell = Cell{
    .codepoint = 0,
    .attrs = default_cell_attrs,
};
