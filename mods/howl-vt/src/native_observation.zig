//! Optional native source lifetime. Only Controller can retire canonical access.
//! Reader references retain this small allocation, never terminal state.
//! Actual observation reads serialize with source mutation/destruction.
const std = @import("std");
const Terminal = @import("howl_vt").Terminal;
const c = @import("vt_native_types");
/// Includes Controller, opened Readers and downstream retained Readers.
pub const maximum_references: u32 = c.HVT_MAX_OBSERVATION_REFERENCES;
/// Source-owner-only retirement authority; never exposed through C.
// zig-audit: acknowledge opaque_type
// reason: Only a matching native terminal owner receives retirement authority; readers cannot recover it through this API.
pub const Controller = opaque {};
/// Retain/read/release authority without source retirement or mutable VT access.
// zig-audit: acknowledge opaque_type
// reason: C and downstream consumers retain only this opaque read capability, not Controller or canonical terminal storage.
pub const Reader = opaque {};
/// Bounded reference admission; existing references remain valid on exhaustion.
pub const RetainError = error{ResourceLimit};
/// Retirement closes live access without extending canonical terminal lifetime.
pub const ReadError = error{SourceClosed};
const State = struct {
    allocator: std.mem.Allocator,
    references: std.atomic.Value(u32),
    observation: std.atomic.Value(?*const Terminal.Observation),
};
comptime {
    if (maximum_references < 2) @compileError("Source requires owner and reader references");
}
fn controllerState(value: *Controller) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only this constructor-owned allocation is represented by Controller.
    // zig-audit: acknowledge align_cast
    // reason: The private State allocation preserves its original alignment.
    return @ptrCast(@alignCast(value));
}
fn readerState(value: *Reader) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Reader is only the read-reference view of this same private State allocation.
    // zig-audit: acknowledge align_cast
    // reason: A live Reader preserves its matching State allocation alignment.
    return @ptrCast(@alignCast(value));
}
fn readerStateConst(value: *const Reader) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: Const observation access recovers only this matching private State, not Controller authority.
    // zig-audit: acknowledge align_cast
    // reason: A live const Reader preserves its matching State allocation alignment.
    return @ptrCast(@alignCast(value));
}
/// Allocates one owner reference. Retire exactly once after serialized source use.
pub fn create(allocator: std.mem.Allocator, observation: *const Terminal.Observation) std.mem.Allocator.Error!*Controller {
    const value = try allocator.create(State);
    value.* = .{ .allocator = allocator, .references = .init(1), .observation = .init(observation) };
    // zig-audit: acknowledge ptr_cast
    // reason: Only the completed private source allocation is published as Controller.
    return @ptrCast(value);
}
fn retainState(value: *State) RetainError!void {
    var count = value.references.load(.monotonic);
    while (true) {
        std.debug.assert(count != 0);
        if (count >= maximum_references) return error.ResourceLimit;
        if (value.references.cmpxchgWeak(count, count + 1, .monotonic, .monotonic)) |changed| {
            count = changed;
        } else return;
    }
}
/// Opens a Reader without exposing Controller through the resulting capability.
pub fn open(controller: *Controller) RetainError!*Reader {
    const value = controllerState(controller);
    try retainState(value);
    // zig-audit: acknowledge ptr_cast
    // reason: The newly retained reference exposes only Reader authority on the same allocation.
    return @ptrCast(value);
}
/// Creates one independently releasable reference; caller retains a live reference.
pub fn retain(reader: *Reader) RetainError!*Reader {
    try retainState(readerState(reader));
    return reader;
}
/// Borrows canonical const observation only for this serialized synchronous use.
pub fn read(reader: *const Reader) ReadError!*const Terminal.Observation {
    return readerStateConst(reader).observation.load(.acquire) orelse error.SourceClosed;
}
fn releaseState(value: *State) void {
    const before = value.references.fetchSub(1, .acq_rel);
    std.debug.assert(before != 0);
    if (before != 1) return;
    std.debug.assert(value.observation.load(.acquire) == null);
    const allocator = value.allocator;
    allocator.destroy(value);
}
/// Closes source access and consumes Controller; never keeps VT alive or waits.
pub fn retire(controller: *Controller) void {
    const value = controllerState(controller);
    value.observation.store(null, .release);
    releaseState(value);
}
/// Drops exactly one Reader reference, including after source retirement.
pub fn release(reader: *Reader) void {
    releaseState(readerState(reader));
}
/// Adapts only this matching Reader family to its VT-owned C opaque declaration.
pub fn toC(reader: *Reader) *c.hvt_observation {
    // zig-audit: acknowledge ptr_cast
    // reason: The C handle represents only the exact matching Reader allocation/reference.
    return @ptrCast(reader);
}
/// Recovers only Reader authority from a matching live C reference.
pub fn fromC(reader: *c.hvt_observation) *Reader {
    // zig-audit: acknowledge ptr_cast
    // reason: A matching hvt_observation is this exact Reader family, never a Controller or terminal handle.
    return @ptrCast(reader);
}
