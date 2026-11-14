//! Small semantic vocabulary crossing source adapters into terminal projection.
//!
//! These values are private renderer input facts. They are not terminal state,
//! transport structs, backend commands, or a public compatibility surface.
//! Timed blink intent remains source semantics until presentation has an explicit
//! caller-clocked phase contract; this untimed renderer input does not carry it.

/// Selects one source-neutral terminal text-color representation.
pub const TextColorKind = enum {
    default,
    indexed,
    rgb,
};

/// Carries either default, palette-indexed, or packed RGB terminal color data.
pub const TextColor = struct {
    kind: TextColorKind,
    value: u32,
};

/// Carries only cell rendition facts that directly affect current frame projection.
pub const CellStyle = struct {
    bold: bool,
    dim: bool,
    italic: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
};

/// Selects the visible terminal cursor geometry independently of source encoding.
pub const CursorShape = enum {
    block,
    underline,
    bar,
    none,
};

/// Selects DEC line scaling independently of VT or transported representation.
pub const LineGeometry = enum {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

/// Selects which terminal cell color channel the renderer is resolving.
pub const ColorRole = enum {
    foreground,
    background,
    underline_color,
};

/// Names one exact source image generation and its decoded pixel extent.
pub const Image = struct {
    image_id: u32,
    generation: u64,
    width: u32,
    height: u32,
};

/// Places one source-image region into the canonical terminal pixel lattice.
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
