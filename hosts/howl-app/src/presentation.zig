//! The SDL app's direct Text and VT-output presentation recipe.
//! No Instance or legacy Render owner participates in this configuration.
const output = @import("howl_vt_output");
const commands = @import("howl_vt_output_commands");

/// Shared or app-private native Text input, plus bounded direct-output policy.
pub const Config = struct {
    cursor_stroke_pixels: u8 = 2,
    text: union(enum) { private: output.FontFamilyConfig, shared: *output.PresentationStore },
    box_drawing: @FieldType(output.SharedConfig, "box_drawing"),
    shape_cache: @FieldType(output.StoreConfig, "shape_cache"),
    atlas: output.AtlasConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
};

/// Exact selected cell lattice and PTY/VT grid after configuration.
pub const Geometry = struct {
    cell_size: commands.Size,
    rows: u16,
    columns: u16,
};
