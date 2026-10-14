//! C export root for optional standalone ownership; direct/schema roots stay separate.
const std = @import("std");
const owner = @import("howl_render_owner_native");
const c = owner.c;
const heap = std.heap.c_allocator;
fn status(err: owner.Error) u32 {
    return switch (err) {
        error.OutOfMemory => c.HRC_OUT_OF_MEMORY,
        error.Busy => c.HRC_BUSY,
        error.NoFrame => c.HRC_NO_FRAME,
        error.SourceClosed => c.HRC_SOURCE_CLOSED,
        error.InvalidArgument, error.InvalidConfig, error.InvalidCapacity, error.InvalidAtlasConfig, error.InvalidShapeCacheConfig, error.InvalidFontFaces, error.InvalidSurface, error.InvalidRectangle, error.InvalidIdentity, error.InvalidGeneration, error.InvalidPixels, error.FormatMismatch, error.ExtentMismatch, error.AliasedStorage, error.InvalidResidency => c.HRC_INVALID_ARGUMENT,
        error.ResourceLimit, error.CacheFull, error.AtlasFull, error.GlyphTooLarge, error.BufferTooSmall, error.InsufficientCommands, error.ImageLimit, error.CommandLimit, error.PixelLimit, error.RasterTooLarge, error.TextTooLong, error.GlyphLimit, error.InsufficientShapeBuffer, error.InsufficientGlyphs, error.ShapeSequenceLimit, error.ShapeEntryFull, error.ShapeScalarFull, error.ShapeGlyphFull, error.GenerationOverflow, error.RevisionOverflow, error.ResourceIdentityOverflow, error.ResourceGenerationOverflow, error.ArithmeticOverflow => c.HRC_RESOURCE_LIMIT,
        // Caller stroke/DPI validation already becomes InvalidArgument. Remaining
        // generated-size/stroke/metric errors arise during canonical production.
        error.FreeTypeInit, error.FontOpen, error.UnicodeCharmap, error.FontSize, error.HarfBuzzFont, error.InvalidMetrics, error.HarfBuzzBuffer, error.InvalidRaster, error.GlyphLoad, error.GlyphRender, error.UnsupportedPixelMode, error.InvalidBitmap, error.InvalidPlacement, error.RasterExtentMismatch, error.InvalidShapeResult, error.InvalidGlyphIdentity, error.MissingGlyph, error.InvalidText, error.InvalidView, error.InvalidColor, error.InvalidImageBinding, error.InvalidPresentationGeometry, error.FontSetMismatch, error.MissingExternalResource, error.InvalidPixelSpan, error.UnsupportedGlyph, error.InvalidSize, error.InvalidStroke => c.HRC_OPERATION_FAILED,
    };
}
fn mutable(raw: *c.hrc_renderer) *owner.Owner {
    // zig-audit: acknowledge ptr_cast
    // reason: Only this exact constructor-owned Owner is represented by hrc_renderer.
    return @ptrCast(raw);
}
fn constant(raw: *const c.hrc_renderer) *const owner.Owner {
    // zig-audit: acknowledge ptr_cast
    // reason: This const matching opaque handle lends only immutable owner access.
    return @ptrCast(raw);
}
fn buffer(raw: *c.hrc_frame_buffer) *owner.Buffer {
    // zig-audit: acknowledge ptr_cast
    // reason: Only this constructor-owned Buffer is represented by hrc_frame_buffer.
    return @ptrCast(raw);
}
fn bufferConst(raw: *const c.hrc_frame_buffer) *const owner.Buffer {
    // zig-audit: acknowledge ptr_cast
    // reason: The matching const frame handle grants only its immutable lease.
    return @ptrCast(raw);
}
/// Returns the exact owned native version.
pub export fn hrc_abi_version() u32 {
    return c.HRC_NATIVE_VERSION;
}
/// Creates only a completely admitted source-bound private renderer.
pub export fn hrc_create(version: u32, config: ?*const c.hrc_config, source: ?*c.struct_hvt_observation, out: ?*?*c.hrc_renderer) u32 {
    if (version != c.HRC_NATIVE_VERSION) return c.HRC_VERSION_MISMATCH;
    const slot = out orelse return c.HRC_INVALID_ARGUMENT;
    if (slot.* != null) return c.HRC_INVALID_ARGUMENT;
    const input = config orelse return c.HRC_INVALID_ARGUMENT;
    const reader = source orelse return c.HRC_INVALID_ARGUMENT;
    const value = owner.create(heap, input, owner.readerFromC(reader)) catch |err| return status(err);
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only the complete matching Owner through its exact opaque C family.
    slot.* = @ptrCast(value);
    return c.HRC_OK;
}
/// Preserves a busy owner and otherwise clears it only after complete teardown.
pub export fn hrc_try_destroy(out: ?*?*c.hrc_renderer) u32 {
    const slot = out orelse return c.HRC_OK;
    const raw = slot.* orelse return c.HRC_OK;
    owner.destroy(mutable(raw)) catch |err| return status(err);
    slot.* = null;
    return c.HRC_OK;
}
/// Copies canonical immutable font-derived geometry.
pub export fn hrc_get_cell_size(raw: ?*const c.hrc_renderer, out: ?*c.hrc_cell_size) u32 {
    const result = out orelse return c.HRC_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hrc_cell_size);
    const value = raw orelse return c.HRC_INVALID_ARGUMENT;
    result.* = owner.cellSize(constant(value));
    return c.HRC_OK;
}
/// Opens one explicitly selected reusable buffer; count admission never evicts.
pub export fn hrc_frame_open(version: u32, raw: ?*c.hrc_renderer, out: ?*?*c.hrc_frame_buffer) u32 {
    if (version != c.HRC_NATIVE_VERSION) return c.HRC_VERSION_MISMATCH;
    const slot = out orelse return c.HRC_INVALID_ARGUMENT;
    if (slot.* != null) return c.HRC_INVALID_ARGUMENT;
    const value = raw orelse return c.HRC_INVALID_ARGUMENT;
    const frame = owner.open(mutable(value)) catch |err| return status(err);
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only this complete parent-bound Buffer as its exact C handle family.
    slot.* = @ptrCast(frame);
    return c.HRC_OK;
}
/// Closes available output storage; a live read lease preserves the handle.
pub export fn hrc_frame_try_close(out: ?*?*c.hrc_frame_buffer) u32 {
    const slot = out orelse return c.HRC_OK;
    const raw = slot.* orelse return c.HRC_OK;
    owner.close(buffer(raw)) catch |err| return status(err);
    slot.* = null;
    return c.HRC_OK;
}
/// Publishes a complete copied frame only after all scalar/range admission.
pub export fn hrc_frame_capture(raw: ?*c.hrc_frame_buffer, history: u32, ptr: ?[*]const c.hrc_residency, count: usize, out: ?*c.hrc_frame_info) u32 {
    const result = out orelse return c.HRC_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hrc_frame_info);
    const value = raw orelse return c.HRC_INVALID_ARGUMENT;
    if (count > c.HRC_MAX_RESIDENCIES) return c.HRC_RESOURCE_LIMIT;
    const values = if (ptr) |data| range: {
        const bytes = std.math.mul(usize, count, @sizeOf(c.hrc_residency)) catch return c.HRC_INVALID_ARGUMENT;
        // zig-audit: acknowledge discard
        // reason: Validate exactly the admitted input array extent before forming any slice.
        _ = std.math.add(usize, @intFromPtr(data), bytes) catch return c.HRC_INVALID_ARGUMENT;
        break :range data[0..count];
    } else if (count == 0) &.{} else return c.HRC_INVALID_ARGUMENT;
    result.* = owner.capture(buffer(value), history, values) catch |err| return status(err);
    return c.HRC_OK;
}
/// Returns only immutable native arrays borrowing the active lease.
pub export fn hrc_frame_read(raw: ?*const c.hrc_frame_buffer, out: ?*c.hrc_frame_view) u32 {
    const result = out orelse return c.HRC_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hrc_frame_view);
    const value = raw orelse return c.HRC_INVALID_ARGUMENT;
    result.* = owner.read(bufferConst(value)) catch |err| return status(err);
    return c.HRC_OK;
}
/// Publishes buffer availability as its final buffer access; acknowledges no GPU state.
pub export fn hrc_frame_release(raw: ?*c.hrc_frame_buffer) u32 {
    const value = raw orelse return c.HRC_INVALID_ARGUMENT;
    owner.release(buffer(value)) catch |err| return status(err);
    return c.HRC_OK;
}
