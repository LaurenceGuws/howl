//! Transitional compile-time source-adapter seam.
//!
//! Canonical Howl Render consumes VT directly. This namespace exists only so
//! edge packages being retired can project an alternate semantic source through
//! the same Renderer instance without rebuilding or wrapping the renderer.

const renderer = @import("renderer");
const semantic = @import("source");

/// Source-neutral text-color kind required by a compile-time source adapter.
pub const TextColorKind = semantic.TextColorKind;
/// Source-neutral text color required by a compile-time source adapter.
pub const TextColor = semantic.TextColor;
/// Source-neutral untimed cell style required by a compile-time source adapter.
pub const CellStyle = semantic.CellStyle;
/// Source-neutral cursor geometry required by a compile-time source adapter.
pub const CursorShape = semantic.CursorShape;
/// Source-neutral DEC line geometry required by a compile-time source adapter.
pub const LineGeometry = semantic.LineGeometry;
/// Source-neutral cell color role required by a compile-time source adapter.
pub const ColorRole = semantic.ColorRole;
/// Source-neutral image identity required by image-binding planning.
pub const Image = semantic.Image;
/// Source-neutral terminal image placement required by a compile-time source adapter.
pub const ImagePlacement = semantic.ImagePlacement;

/// Plans exact backend resource bindings for normalized source images.
pub fn planImageBindings(
    current: []const renderer.ExternalImageBinding,
    current_usage: renderer.Usage,
    images: []const Image,
    output: *[renderer.maximum_external_images]renderer.ExternalImageBinding,
) error{ ImageLimit, InvalidImageBinding, ResourceIdentityOverflow }![]const renderer.ExternalImageBinding {
    return renderer.planImageBindings(current, current_usage, images, output);
}

/// Projects one synchronous compile-time source snapshot through the canonical Renderer.
pub fn updateSource(
    comptime Source: type,
    owner: *renderer.Renderer,
    snapshot: *const Source.Snapshot,
    image_bindings: []const renderer.ExternalImageBinding,
) renderer.Error!void {
    return renderer.updateSource(Source, owner, snapshot, image_bindings);
}
