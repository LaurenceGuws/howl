//! Host policy for constructing Instance-owned terminal presentation.
//!
//! This file chooses fonts, DPI and bounded cache sizes. It owns no live Text
//! or Render state; those lifetimes belong to howl_instance.

const std = @import("std");
const instance = @import("howl_instance");

pub const base_font_pixels: u16 = 16;
const scale_denominator: u32 = 120;
const atlas_extent: u16 = 512;
const atlas_pixel_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
const command_capacity: usize = instance.render.limits.maximum_frame_commands;

/// One explicit primary font plus ordered missing-cluster fallbacks.
pub const FontPaths = struct {
    primary: []const u8,
    fallbacks: []const []const u8 = &.{},
};

/// Converts compositor fractional scale to the Host's physical font-pixel size.
pub fn fontPixels(scale_120: u32) error{InvalidDisplayScale}!u16 {
    if (scale_120 == 0) return error.InvalidDisplayScale;
    const numerator = std.math.mul(u32, base_font_pixels, scale_120) catch
        return error.InvalidDisplayScale;
    const rounded = std.math.add(u32, numerator, scale_denominator / 2) catch
        return error.InvalidDisplayScale;
    const pixels = rounded / scale_denominator;
    if (pixels == 0 or pixels > std.math.maxInt(u16))
        return error.InvalidDisplayScale;
    return @intCast(pixels);
}

/// Builds the complete bounded configuration for one Instance-owned Renderer.
pub fn config(font: FontPaths, pixels: u16) instance.PresentationConfig {
    return .{
        .text = .{ .private = .{ .regular = .{ .path = .{
            .primary = font.primary,
            .fallbacks = font.fallbacks,
            .size = .{ .pixels = pixels },
        } } } },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 1024,
            .scalar_capacity = 4096,
            .glyph_capacity = 4096,
            .max_sequence_scalars = 32,
        },
        .atlas = .{
            .width = atlas_extent,
            .height = atlas_extent,
            .entry_capacity = 1024,
        },
        .shaped_capacity = 128,
        .raster_bytes = atlas_pixel_bytes,
        .command_capacity = command_capacity,
    };
}

/// Measures one font size for Host logical-window geometry only.
pub fn measureCellSize(
    allocator: std.mem.Allocator,
    font: FontPaths,
    pixels: u16,
) !instance.render.terminal.Size {
    if (pixels == 0) return error.InvalidFontPixels;
    const fonts = try instance.text.FontSet.init(allocator, .{
        .primary = font.primary,
        .fallbacks = font.fallbacks,
        .size = .{ .pixels = pixels },
    });
    defer fonts.deinit();
    const metrics = fonts.metrics();
    return .{ .width = metrics.advance_width, .height = metrics.line_height };
}
