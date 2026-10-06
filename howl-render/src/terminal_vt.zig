//! Direct canonical VT terminal-rendering facade.
//!
//! This module contains no transported-client vocabulary. It projects one
//! borrowed howl-vt observation synchronously into the source-neutral renderer.

const VT = @import("howl_vt").Terminal;
const renderer = @import("renderer");
const semantic = @import("source");
const source_vt = @import("source_vt.zig");

/// Uses the source-neutral renderer atlas configuration.
pub const AtlasConfig = renderer.AtlasConfig;
/// Uses the source-neutral renderer shape-cache configuration.
pub const ShapeCacheConfig = renderer.ShapeCacheConfig;
/// Uses the source-neutral renderer shape-cache usage counters.
pub const ShapeCacheUsage = renderer.ShapeCacheUsage;
/// Uses the source-neutral renderer runtime atlas errors.
pub const AtlasError = renderer.AtlasError;
/// Uses the source-neutral renderer shape-cache initialization errors.
pub const ShapeCacheInitError = renderer.ShapeCacheInitError;
/// Uses the source-neutral renderer runtime shape-cache errors.
pub const ShapeCacheError = renderer.ShapeCacheError;
/// Uses the source-neutral renderer font style variants.
pub const FontVariant = renderer.FontVariant;
/// Uses the source-neutral renderer font-family value.
pub const FontFaces = renderer.FontFaces;
/// Uses the source-neutral process render Store owner.
pub const Store = renderer.Store;
/// Uses the source-neutral Store configuration.
pub const StoreConfig = renderer.StoreConfig;
/// Uses the source-neutral Store usage counters.
pub const StoreUsage = renderer.StoreUsage;
/// Uses the source-neutral Store initialization errors.
pub const StoreInitError = renderer.StoreInitError;

/// Uses the shared frame color type.
pub const Color = renderer.Color;
/// Uses the shared frame pixel extent.
pub const Size = renderer.Size;
/// Uses the shared destination/clip rectangle.
pub const Rect = renderer.Rect;
/// Uses the shared resource source rectangle.
pub const SourceRect = renderer.SourceRect;
/// Uses the shared logical resource identity.
pub const ResourceId = renderer.ResourceId;
/// Uses the shared resource generation type.
pub const ResourceGeneration = renderer.ResourceGeneration;
/// Uses the shared resource pixel format.
pub const ResourceFormat = renderer.ResourceFormat;
/// Uses the shared exact resource occurrence.
pub const ResourceRef = renderer.ResourceRef;
/// Uses the shared resource sampling view.
pub const ResourceView = renderer.ResourceView;
/// Uses the shared backend residency fact.
pub const Residency = renderer.Residency;
/// Uses the shared frame upload descriptor.
pub const FrameResourceUpload = renderer.FrameResourceUpload;
/// Uses the shared missing Host-owned resource descriptor.
pub const FrameExternalResource = renderer.FrameExternalResource;
/// Uses the shared final backend command type.
pub const Command = renderer.Command;
/// Uses the shared pre-projection draw-input type.
pub const Input = renderer.Input;

/// Uses the source-neutral terminal Renderer configuration.
pub const Config = renderer.Config;
/// Uses the source-neutral external-image binding value.
pub const ExternalImageBinding = renderer.ExternalImageBinding;
/// Bounds simultaneously visible external terminal images.
pub const maximum_external_images = renderer.maximum_external_images;
/// Uses the source-neutral terminal Renderer owner.
pub const Renderer = renderer.Renderer;
/// Uses the source-neutral Renderer usage counters.
pub const Usage = renderer.Usage;
/// Uses the source-neutral frame scratch buffers.
pub const FrameBuffers = renderer.FrameBuffers;
/// Uses the source-neutral completed frame view.
pub const Frame = renderer.Frame;
/// Uses the retained-row scene update kind.
pub const RowSceneKind = renderer.RowSceneKind;
/// Uses one retained-row command span.
pub const RowSceneRow = renderer.RowSceneRow;
/// Uses the source-neutral retained-row acceleration view.
pub const RowScene = renderer.RowScene;
/// Uses the source-neutral Renderer initialization errors.
pub const InitError = renderer.InitError;
/// Uses the source-neutral Renderer operation errors.
pub const Error = renderer.Error;
/// Validates exact backend residency without mutating terminal Render state.
pub const validateResidencies = renderer.validateResidencies;

/// Allocates one bounded terminal Renderer and private Store.
pub const init = renderer.init;
/// Allocates one reusable process render Store.
pub const initStore = renderer.initStore;
/// Releases one process render Store.
pub const deinitStore = renderer.deinitStore;
/// Returns the fixed Store font metrics.
pub const storeMetrics = renderer.storeMetrics;
/// Reports retained Store cache usage.
pub const storeUsage = renderer.storeUsage;
/// Forgets retained Store shaping knowledge.
pub const resetStore = renderer.resetStore;
/// Allocates one Renderer borrowing an existing Store.
pub const initWithStore = renderer.initWithStore;
/// Releases one terminal Renderer.
pub const deinit = renderer.deinit;
/// Explicitly forgets terminal-local shaping/raster caches.
pub const resetCaches = renderer.resetCaches;
/// Reports current Renderer usage and resource counters.
pub const usage = renderer.usage;
/// Reports visible Host-owned resources missing from backend residency.
pub const missingExternalResources = renderer.missingExternalResources;
/// Produces one backend-facing frame against exact residency.
pub const frame = renderer.frame;
/// Borrows the current retained-row acceleration view when eligible.
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
