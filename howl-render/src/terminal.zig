//! Public terminal-rendering facade.
//!
//! Local VT observation and transported client views are source adapters around
//! one source-independent renderer. Backend frame vocabulary and text behavior
//! remain identical regardless of where terminal semantics came from.

const VT = @import("howl_vt").Terminal;
const client = @import("howl_client");
const renderer = @import("renderer");
const semantic = @import("source");
const source_client = @import("source_client.zig");
const source_vt = @import("source_vt.zig");

pub const AtlasConfig = renderer.AtlasConfig;
pub const ShapeCacheConfig = renderer.ShapeCacheConfig;
pub const ShapeCacheUsage = renderer.ShapeCacheUsage;
pub const AtlasError = renderer.AtlasError;
pub const ShapeCacheInitError = renderer.ShapeCacheInitError;
pub const ShapeCacheError = renderer.ShapeCacheError;
pub const FontVariant = renderer.FontVariant;
pub const FontFaces = renderer.FontFaces;

pub const View = client.view;

pub const Color = renderer.Color;
pub const Size = renderer.Size;
pub const Rect = renderer.Rect;
pub const SourceRect = renderer.SourceRect;
pub const ResourceId = renderer.ResourceId;
pub const ResourceGeneration = renderer.ResourceGeneration;
pub const ResourceFormat = renderer.ResourceFormat;
pub const ResourceRef = renderer.ResourceRef;
pub const ResourceView = renderer.ResourceView;
pub const Residency = renderer.Residency;
pub const FrameResourceUpload = renderer.FrameResourceUpload;
pub const FrameExternalResource = renderer.FrameExternalResource;
pub const Command = renderer.Command;

pub const Config = renderer.Config;
pub const ExternalImageBinding = renderer.ExternalImageBinding;
pub const maximum_external_images = renderer.maximum_external_images;
pub const Renderer = renderer.Renderer;
pub const Usage = renderer.Usage;
pub const FrameBuffers = renderer.FrameBuffers;
pub const Frame = renderer.Frame;
pub const InitError = renderer.InitError;
pub const Error = renderer.Error;

pub const init = renderer.init;
pub const deinit = renderer.deinit;
pub const resetCaches = renderer.resetCaches;
pub const usage = renderer.usage;
pub const missingExternalResources = renderer.missingExternalResources;
pub const frame = renderer.frame;

/// Plans exact resource bindings for one transported semantic image manifest.
pub fn planExternalImageBindings(
    current: []const ExternalImageBinding,
    current_usage: Usage,
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
    return renderer.planImageBindings(current, current_usage, normalized[0..images.len], output);
}

/// Plans exact resource bindings for images visible in one canonical VT view.
pub fn planObservationImageBindings(
    current: []const ExternalImageBinding,
    current_usage: Usage,
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
    return renderer.planImageBindings(current, current_usage, normalized[0..count], output);
}

/// Replaces this renderer with one immutable owned client view.
pub fn update(owner: *Renderer, snapshot: *const View.Snapshot) Error!void {
    return renderer.updateSource(source_client.Owned, owner, snapshot, &.{});
}

/// Replaces this renderer with one already-validated borrowed rich client view.
pub fn updateRich(owner: *Renderer, snapshot: *const client.rich.View) Error!void {
    return renderer.updateSource(source_client.RichView, owner, snapshot, &.{});
}

pub fn updateWithImageBinding(
    owner: *Renderer,
    snapshot: *const View.Snapshot,
    image_binding: ExternalImageBinding,
) Error!void {
    return updateWithImageBindings(owner, snapshot, &.{image_binding});
}

/// Replaces this renderer with one immutable owned client view and exact image bindings.
pub fn updateWithImageBindings(
    owner: *Renderer,
    snapshot: *const View.Snapshot,
    image_bindings: []const ExternalImageBinding,
) Error!void {
    return renderer.updateSource(source_client.Owned, owner, snapshot, image_bindings);
}

/// Borrowed-rich equivalent of updateWithImageBindings.
pub fn updateRichWithImageBindings(
    owner: *Renderer,
    snapshot: *const client.rich.View,
    image_bindings: []const ExternalImageBinding,
) Error!void {
    return renderer.updateSource(source_client.RichView, owner, snapshot, image_bindings);
}

/// Presents one canonical VT observation synchronously without retaining a VT borrow.
pub fn updateObservation(
    owner: *Renderer,
    observation: *const VT.Observation,
    history_offset: u32,
    image_bindings: []const ExternalImageBinding,
) Error!void {
    const snapshot: source_vt.Source.Snapshot = .{
        .view = observation.semanticView(history_offset),
        .colors = observation.presentation(),
        .images = observation.images(history_offset),
    };
    return renderer.updateSource(source_vt.Source, owner, &snapshot, image_bindings);
}
