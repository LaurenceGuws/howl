//! Private C-family ownership around the exact canonical local Instance.
//! Direct Zig owners/helpers never import this wrapper.
const std = @import("std");
const engine = @import("howl_instance");
const source = @import("howl_vt_native").observation;
/// One constructor-owned C handle; never interchangeable with a direct Instance.
// zig-audit: acknowledge opaque_type
// reason: Only the optional C factory owns this wrapper; canonical Instance layout and source Controller stay private.
pub const Owner = opaque {};
const State = struct {
    allocator: std.mem.Allocator,
    instance: *engine.Instance,
    controller: ?*source.Controller,
};
fn state(value: *Owner) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only this constructor-owned wrapper is represented by Owner.
    // zig-audit: acknowledge align_cast
    // reason: The matching allocator-owned State retains its original alignment.
    return @ptrCast(@alignCast(value));
}
fn stateConst(value: *const Owner) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: A matching const Owner lends only this private wrapper, never mutable canonical terminal storage.
    // zig-audit: acknowledge align_cast
    // reason: The const view preserves the matching State allocation alignment.
    return @ptrCast(@alignCast(value));
}
/// Stages C storage before canonical construction or any child launch.
pub fn create(allocator: std.mem.Allocator, environ: std.process.Environ, launch: engine.Launch) engine.InitError!*Owner {
    const value = try allocator.create(State);
    errdefer allocator.destroy(value);
    const instance = try engine.init(allocator, environ, launch);
    value.* = .{ .allocator = allocator, .instance = instance, .controller = null };
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only the fully constructed matching C wrapper.
    return @ptrCast(value);
}
/// Keeps the canonical nonwaiting shared-font factory and specialization unchanged.
pub fn createPresented(allocator: std.mem.Allocator, environ: std.process.Environ, launch: engine.Launch, presentation: engine.PresentationConfig) engine.TryPresentedInitError!*Owner {
    const value = try allocator.create(State);
    errdefer allocator.destroy(value);
    const instance = try engine.tryInitPresented(allocator, environ, launch, presentation);
    value.* = .{ .allocator = allocator, .instance = instance, .controller = null };
    // zig-audit: acknowledge ptr_cast
    // reason: Presented and unpresented C construction publish the same complete wrapper family.
    return @ptrCast(value);
}
/// Private ABI entrypoints borrow the exact canonical opaque Instance.
pub fn get(value: *Owner) *engine.Instance {
    return state(value).instance;
}
/// Query entrypoints borrow only the exact canonical const Instance.
pub fn getConst(value: *const Owner) *const engine.Instance {
    return stateConst(value).instance;
}
/// Allocation or bounded source-reference admission failure.
pub const ObservationOpenError = std.mem.Allocator.Error || source.RetainError;
/// Lazily opens one VT-owned Reader; canonical revisions remain unchanged.
pub fn openObservation(value: *Owner) ObservationOpenError!*source.Reader {
    const storage = state(value);
    if (storage.controller) |controller| return source.open(controller);
    const controller = try source.create(storage.allocator, engine.terminal(storage.instance));
    errdefer source.retire(controller);
    const reader = try source.open(controller);
    storage.controller = controller;
    return reader;
}
/// Busy leaves the entire C owner/source live. Source reads and destruction
/// serialize, and canonical teardown cannot reenter the optional capability.
/// After successful canonical teardown, retire before clearing/freeing C storage.
pub fn destroy(value: *Owner) error{PublicationBorrowed}!void {
    const storage = state(value);
    const allocator = storage.allocator;
    try engine.tryDeinit(storage.instance);
    if (storage.controller) |controller| source.retire(controller);
    allocator.destroy(storage);
}

fn testLaunch() engine.Launch {
    return .{ .shell = "/bin/sh", .command = "exec sleep 30", .rows = 2, .columns = 8, .history_rows = 0 };
}
fn testPresentation() engine.PresentationConfig {
    return .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 128, .height = 128, .entry_capacity = 256 },
        .shaped_capacity = 1024,
        .raster_bytes = 64 * 1024,
        .command_capacity = 256,
        .command_limit = 256,
    };
}
test "C wrapper allocation precedes canonical construction" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, create(failing.allocator(), std.testing.environ, testLaunch()));
    try std.testing.expect(failing.has_induced_failure and failing.allocations == 0);
    try std.testing.expectError(error.OutOfMemory, createPresented(failing.allocator(), std.testing.environ, testLaunch(), testPresentation()));
    try std.testing.expect(failing.allocations == 0);
}
test "C owner and lazy observation unwind every headless and presented allocation prefix" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, campaign, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, campaign, .{true});
}
fn campaign(allocator: std.mem.Allocator, presented: bool) !void {
    const value = if (presented) try createPresented(allocator, std.testing.environ, testLaunch(), testPresentation()) else try create(allocator, std.testing.environ, testLaunch());
    var live = true;
    defer if (live) destroy(value) catch {
        // zig-audit: acknowledge panic
        // reason: This proof opens no publication borrower; cleanup must destroy its matching canonical owner.
        @panic("C owner cleanup unexpectedly busy");
    };
    const before = engine.terminal(getConst(value)).semanticSequence();
    const reader = try openObservation(value);
    defer source.release(reader);
    const peer = try openObservation(value);
    defer source.release(peer);
    try std.testing.expect(reader == peer);
    try std.testing.expect(try source.read(reader) == engine.terminal(get(value)));
    try std.testing.expectEqual(before, engine.terminal(getConst(value)).semanticSequence());
    try destroy(value);
    live = false;
    try std.testing.expectError(error.SourceClosed, source.read(reader));
}
test "busy C owner destruction preserves its live observation through endpoint gaps" {
    const value = try createPresented(std.testing.allocator, std.testing.environ, testLaunch(), testPresentation());
    var live = true;
    defer if (live) destroy(value) catch {
        // zig-audit: acknowledge panic
        // reason: The proof closes every publication borrow before cleanup.
        @panic("C owner cleanup unexpectedly busy");
    };
    const reader = try openObservation(value);
    defer source.release(reader);
    const before = engine.terminal(get(value)).semanticSequence();
    const exchange = try engine.borrowRenderExchange(get(value));
    var borrowed = true;
    defer if (borrowed) engine.releaseRenderExchange(exchange);
    try std.testing.expectError(error.PublicationBorrowed, destroy(value));
    try std.testing.expect(try source.read(reader) == engine.terminal(get(value)));
    try std.testing.expectEqual(before, engine.terminal(get(value)).semanticSequence());
    engine.releaseRenderExchange(exchange);
    borrowed = false;
    try destroy(value);
    live = false;
    try std.testing.expectError(error.SourceClosed, source.read(reader));
}
