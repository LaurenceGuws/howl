//! Defines terminal color values and their RGB projection.

/// Stores one exact 24-bit terminal color.
pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

const Kind = enum(u8) {
    default,
    indexed,
    rgb,
};

/// Stores a default, indexed, or RGB terminal color.
pub const Color = struct {
    kind: Kind,
    value: u32,

    /// Constructs an indexed terminal color.
    pub fn indexed(idx: u8) Color {
        return .{ .kind = .indexed, .value = idx };
    }

    /// Constructs an exact RGB terminal color.
    pub fn rgb(rgb_value: Rgb) Color {
        return .{
            .kind = .rgb,
            .value = (@as(u32, rgb_value.r) << 16) | (@as(u32, rgb_value.g) << 8) | @as(u32, rgb_value.b),
        };
    }

    /// Returns RGB components only when this color is RGB.
    pub fn rgbComponents(r: u8, g: u8, b: u8) Color {
        return rgb(.{ .r = r, .g = g, .b = b });
    }

    /// Resolves this cell color against one complete terminal palette and
    /// caller-selected default without retaining either borrowed value.
    pub fn resolve(self: Color, default_value: Rgb, palette: *const [256]Rgb) Rgb {
        return switch (self.kind) {
            .default => default_value,
            .indexed => palette[@as(u8, @intCast(self.value))],
            .rgb => .{
                .r = @truncate(self.value >> 16),
                .g = @truncate(self.value >> 8),
                .b = @truncate(self.value),
            },
        };
    }
};

/// Provides the immutable default foreground color.
pub const default_fg = Color{ .kind = .default, .value = 0 };
/// Provides the immutable default background color.
pub const default_bg = Color{ .kind = .default, .value = 0 };
/// Provides the immutable default underline color.
pub const default_underline_color = Color{ .kind = .default, .value = 0 };
