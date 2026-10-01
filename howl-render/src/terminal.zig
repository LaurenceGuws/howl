//! Public terminal-rendering facade.
//!
//! Local VT observation and transported client views are source adapters around
//! one source-independent projector. Backend frame vocabulary and text behavior
//! remain identical regardless of where terminal semantics came from.

const VT = @import("howl_vt").Terminal;
const client = @import("howl_client");
const projector = @import("projector");
const semantic = @import("source");
const source_client = @import("source_client.zig");
const source_vt = @import("source_vt.zig");

pub const AtlasConfig = projector.AtlasConfig;
pub const ShapeCacheConfig = projector.ShapeCacheConfig;
pub const ShapeCacheUsage = projector.ShapeCacheUsage;
pub const AtlasError = projector.AtlasError;
pub const ShapeCacheInitError = projector.ShapeCacheInitError;
pub const ShapeCacheError = projector.ShapeCacheError;
pub const FontVariant = projector.FontVariant;
pub const FontFaces = projector.FontFaces;

pub const View = client.view;

pub const Color = projector.Color;
pub const Size = projector.Size;
pub const Rect = projector.Rect;
pub const SourceRect = projector.SourceRect;
pub const ResourceId = projector.ResourceId;
pub const ResourceGeneration = projector.ResourceGeneration;
pub const ResourceFormat = projector.ResourceFormat;
pub const ResourceRef = projector.ResourceRef;
pub const ResourceView = projector.ResourceView;
pub const Residency = projector.Residency;
pub const FrameResourceUpload = projector.FrameResourceUpload;
pub const FrameExternalResource = projector.FrameExternalResource;
pub const Command = projector.Command;

pub const CanvasConfig = projector.CanvasConfig;
pub const ExternalImageBinding = projector.ExternalImageBinding;
pub const maximum_external_images = projector.maximum_external_images;
pub const Canvas = projector.Canvas;
pub const CanvasUsage = projector.CanvasUsage;
pub const FrameBuffers = projector.FrameBuffers;
pub const Frame = projector.Frame;
pub const CanvasInitError = projector.CanvasInitError;
pub const CanvasError = projector.CanvasError;

pub const initCanvas = projector.initCanvas;
pub const deinitCanvas = projector.deinitCanvas;
pub const resetCanvasCaches = projector.resetCanvasCaches;
pub const canvasUsage = projector.canvasUsage;
pub const missingExternalResources = projector.missingExternalResources;
pub const frame = projector.frame;

/// Plans exact resource bindings for one transported semantic image manifest.
pub fn planExternalImageBindings(
    current: []const ExternalImageBinding,
    usage: CanvasUsage,
    images: []const View.Image,
    output: *[maximum_external_images]ExternalImageBinding,
) error{ ImageLimit, InvalidImageBinding, ResourceIdentityOverflow }![]const ExternalImageBinding {
    if (images.len > output.len) return error.ImageLimit;
    var normalized: [maximum_external_images]semantic.Image = undefined;
    for (images, 0..) |image, index| normalized[index] = .{
        .image_id = image.image_id,
        .generation = image.generation,
        .width = image.width,
        .height = image.height,
    };
    return projector.planImageBindings(current, usage, normalized[0..images.len], output);
}

/// Plans exact resource bindings for images visible in one canonical VT view.
pub fn planObservationImageBindings(
    current: []const ExternalImageBinding,
    usage: CanvasUsage,
    observation: *const VT.Observation,
    history_offset: u32,
    output: *[maximum_external_images]ExternalImageBinding,
) error{ ImageLimit, InvalidImageBinding, ResourceIdentityOverflow }![]const ExternalImageBinding {
    const graphics = observation.images(history_offset);
    var normalized: [maximum_external_images]semantic.Image = undefined;
    var count: usize = 0;
    for (0..source_vt.Source.graphicsImageCount(graphics)) |index| {
        const image = source_vt.Source.graphicsImage(graphics, index);
        if (!source_vt.Source.graphicsImageVisible(graphics, image.image_id)) continue;
        if (count == normalized.len) return error.ImageLimit;
        normalized[count] = image;
        count += 1;
    }
    return projector.planImageBindings(current, usage, normalized[0..count], output);
}

/// Replaces this Canvas with one immutable owned client view.
pub fn update(owner: *Canvas, snapshot: *const View.Snapshot) CanvasError!void {
    return projector.updateSource(source_client.Owned, owner, snapshot, &.{});
}

/// Replaces this Canvas with one already-validated borrowed rich client view.
pub fn updateRich(owner: *Canvas, snapshot: *const client.rich.View) CanvasError!void {
    return projector.updateSource(source_client.RichView, owner, snapshot, &.{});
}

pub fn updateWithImageBinding(
    owner: *Canvas,
    snapshot: *const View.Snapshot,
    image_binding: ExternalImageBinding,
) CanvasError!void {
    return updateWithImageBindings(owner, snapshot, &.{image_binding});
}

/// Replaces this Canvas with one immutable owned client view and exact image bindings.
pub fn updateWithImageBindings(
    owner: *Canvas,
    snapshot: *const View.Snapshot,
    image_bindings: []const ExternalImageBinding,
) CanvasError!void {
    return projector.updateSource(source_client.Owned, owner, snapshot, image_bindings);
}

/// Borrowed-rich equivalent of updateWithImageBindings.
pub fn updateRichWithImageBindings(
    owner: *Canvas,
    snapshot: *const client.rich.View,
    image_bindings: []const ExternalImageBinding,
) CanvasError!void {
    return projector.updateSource(source_client.RichView, owner, snapshot, image_bindings);
}

/// Presents one canonical VT observation synchronously without retaining a VT borrow.
pub fn updateObservation(
    owner: *Canvas,
    observation: *const VT.Observation,
    history_offset: u32,
    image_bindings: []const ExternalImageBinding,
) CanvasError!void {
    const snapshot: source_vt.Source.Snapshot = .{
        .view = observation.semanticView(history_offset),
        .colors = observation.presentation(),
        .images = observation.images(history_offset),
    };
    return projector.updateSource(source_vt.Source, owner, &snapshot, image_bindings);
}
