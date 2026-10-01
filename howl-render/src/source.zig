//! Small semantic vocabulary crossing source adapters into terminal projection.
//!
//! These values are private renderer input facts. They are not terminal state,
//! transport structs, backend commands, or a public compatibility surface.

pub const TextColorKind = enum {
    default,
    indexed,
    rgb,
};

pub const TextColor = struct {
    kind: TextColorKind,
    value: u32,
};

pub const CellStyle = struct {
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
};

pub const CursorShape = enum {
    block,
    underline,
    bar,
    none,
};

pub const LineGeometry = enum {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

pub const ColorRole = enum {
    foreground,
    background,
    underline_color,
};

pub const Image = struct {
    image_id: u32,
    generation: u64,
    width: u32,
    height: u32,
};

pub const ImagePlacement = struct {
    image_id: u32,
    generation: u64,
    row: u16,
    column: u16,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    cell_x: u32,
    cell_y: u32,
    pixel_width: u32,
    pixel_height: u32,
    z: i32,
};
