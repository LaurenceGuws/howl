//! Public terminal-rendering facade.
//!
//! Local VT observation and transported client views are source adapters around
//! one source-independent renderer. Backend frame vocabulary and text behavior
//! remain identical regardless of where terminal semantics came from.

const client = @import("howl_client");
const renderer = @import("renderer");
const semantic = @import("source");
const source_client = @import("source_client.zig");
const direct = @import("terminal_vt");

pub const AtlasConfig = direct.AtlasConfig;
pub const ShapeCacheConfig = direct.ShapeCacheConfig;
pub const ShapeCacheUsage = direct.ShapeCacheUsage;
pub const AtlasError = direct.AtlasError;
pub const ShapeCacheInitError = direct.ShapeCacheInitError;
pub const ShapeCacheError = direct.ShapeCacheError;
pub const FontVariant = direct.FontVariant;
pub const FontFaces = direct.FontFaces;
pub const Store = direct.Store;
pub const StoreConfig = direct.StoreConfig;
pub const StoreUsage = direct.StoreUsage;
pub const StoreInitError = direct.StoreInitError;

pub const View = client.view;

pub const Color = direct.Color;
pub const Size = direct.Size;
pub const Rect = direct.Rect;
pub const SourceRect = direct.SourceRect;
pub const ResourceId = direct.ResourceId;
pub const ResourceGeneration = direct.ResourceGeneration;
pub const ResourceFormat = direct.ResourceFormat;
pub const ResourceRef = direct.ResourceRef;
pub const ResourceView = direct.ResourceView;
pub const Residency = direct.Residency;
pub const FrameResourceUpload = direct.FrameResourceUpload;
pub const FrameExternalResource = direct.FrameExternalResource;
pub const Command = direct.Command;
pub const Input = direct.Input;

pub const Config = direct.Config;
pub const ExternalImageBinding = direct.ExternalImageBinding;
pub const maximum_external_images = direct.maximum_external_images;
pub const Renderer = direct.Renderer;
pub const Usage = direct.Usage;
pub const FrameBuffers = direct.FrameBuffers;
pub const Frame = direct.Frame;
pub const RowSceneKind = direct.RowSceneKind;
pub const RowSceneRow = direct.RowSceneRow;
pub const RowScene = direct.RowScene;
pub const InitError = direct.InitError;
pub const Error = direct.Error;

pub const init = direct.init;
pub const initStore = direct.initStore;
pub const deinitStore = direct.deinitStore;
pub const storeMetrics = direct.storeMetrics;
pub const storeUsage = direct.storeUsage;
pub const resetStore = direct.resetStore;
pub const initWithStore = direct.initWithStore;
pub const deinit = direct.deinit;
pub const resetCaches = direct.resetCaches;
pub const usage = direct.usage;
pub const missingExternalResources = direct.missingExternalResources;
pub const frame = direct.frame;
pub const rowScene = direct.rowScene;
pub const planObservationImageBindings = direct.planObservationImageBindings;
pub const updateObservation = direct.updateObservation;

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
