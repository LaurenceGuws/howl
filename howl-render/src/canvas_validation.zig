//! Shares stateless Canvas identity, extent, and pixel-syntax validation.

const std = @import("std");

/// Reports malformed resource syntax without retaining caller facts.
pub const Error = error{
    InvalidIdentity,
    InvalidGeneration,
    InvalidPixels,
    ExtentMismatch,
    ArithmeticOverflow,
};

/// Rejects the reserved zero Composer source identity.
pub fn sourceIdentity(value: u64) error{InvalidIdentity}!void {
    if (value == 0) return error.InvalidIdentity;
}

/// Rejects reserved zero local identity or generation values.
pub fn localIdentity(resource: u64, generation: u64) error{
    InvalidIdentity,
    InvalidGeneration,
}!void {
    if (resource == 0) return error.InvalidIdentity;
    if (generation == 0) return error.InvalidGeneration;
}

/// Validates one complete extent and optional contained nonzero source region.
pub fn extent(
    width: u16,
    height: u16,
    source_x: ?u16,
    source_y: ?u16,
    source_width: ?u16,
    source_height: ?u16,
) error{ ExtentMismatch, ArithmeticOverflow }!void {
    if (width == 0 or height == 0) return error.ExtentMismatch;
    if (source_x == null and source_y == null and
        source_width == null and source_height == null) return;
    const x = source_x orelse return error.ExtentMismatch;
    const y = source_y orelse return error.ExtentMismatch;
    const selected_width = source_width orelse return error.ExtentMismatch;
    const selected_height = source_height orelse return error.ExtentMismatch;
    if (selected_width == 0 or selected_height == 0)
        return error.ExtentMismatch;
    const right = std.math.add(u32, x, selected_width) catch
        return error.ArithmeticOverflow;
    const bottom = std.math.add(u32, y, selected_height) catch
        return error.ArithmeticOverflow;
    if (right > width or bottom > height) return error.ExtentMismatch;
}

/// Validates one complete tightly or explicitly strided alpha-mask plane.
pub fn alpha8(
    bytes_len: usize,
    width: u16,
    height: u16,
    stride: usize,
) Error!void {
    try pixelPlane(bytes_len, width, height, stride, 1);
}

/// Validates one complete tightly or explicitly strided RGBA8 plane.
pub fn rgba8(
    bytes_len: usize,
    width: u16,
    height: u16,
    stride: usize,
) Error!void {
    try pixelPlane(bytes_len, width, height, stride, 4);
}

fn pixelPlane(
    bytes_len: usize,
    width: u16,
    height: u16,
    stride: usize,
    comptime bytes_per_pixel: usize,
) Error!void {
    try extent(width, height, null, null, null, null);
    const row_bytes = std.math.mul(usize, width, bytes_per_pixel) catch
        return error.ArithmeticOverflow;
    if (stride < row_bytes) return error.InvalidPixels;
    const preceding = std.math.mul(usize, height - 1, stride) catch
        return error.ArithmeticOverflow;
    const required = std.math.add(usize, preceding, row_bytes) catch
        return error.ArithmeticOverflow;
    if (bytes_len != required) return error.InvalidPixels;
}
