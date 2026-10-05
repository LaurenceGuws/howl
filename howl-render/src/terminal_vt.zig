//! Direct canonical VT terminal-rendering facade.
//!
//! This module contains no transported-client vocabulary. It projects one
//! borrowed howl-vt observation synchronously into the source-neutral renderer.

const VT = @import("howl_vt").Terminal;
const renderer = @import("renderer");
const semantic = @import("source");
const source_vt = @import("source_vt.zig");

pub const AtlasConfig = renderer.AtlasConfig;
pub const ShapeCacheConfig = renderer.ShapeCacheConfig;
pub const ShapeCacheUsage = renderer.ShapeCacheUsage;
pub const AtlasError = renderer.AtlasError;
pub const ShapeCacheInitError = renderer.ShapeCacheInitError;
pub const ShapeCacheError = renderer.ShapeCacheError;
pub const FontVariant = renderer.FontVariant;
pub const FontFaces = renderer.FontFaces;
pub const Store = renderer.Store;
pub const StoreConfig = renderer.StoreConfig;
pub const StoreUsage = renderer.StoreUsage;
pub const StoreInitError = renderer.StoreInitError;

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
pub const Input = renderer.Input;

pub const Config = renderer.Config;
pub const ExternalImageBinding = renderer.ExternalImageBinding;
pub const maximum_external_images = renderer.maximum_external_images;
pub const Renderer = renderer.Renderer;
pub const Usage = renderer.Usage;
pub const FrameBuffers = renderer.FrameBuffers;
pub const Frame = renderer.Frame;
pub const RowSceneKind = renderer.RowSceneKind;
pub const RowSceneRow = renderer.RowSceneRow;
pub const RowScene = renderer.RowScene;
pub const InitError = renderer.InitError;
pub const Error = renderer.Error;

pub const init = renderer.init;
pub const initStore = renderer.initStore;
pub const deinitStore = renderer.deinitStore;
pub const storeMetrics = renderer.storeMetrics;
pub const storeUsage = renderer.storeUsage;
pub const resetStore = renderer.resetStore;
pub const initWithStore = renderer.initWithStore;
pub const deinit = renderer.deinit;
pub const resetCaches = renderer.resetCaches;
pub const usage = renderer.usage;
pub const missingExternalResources = renderer.missingExternalResources;
pub const frame = renderer.frame;
pub const rowScene = renderer.rowScene;

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
