//! Owns semantic cursor position, style, and client-movement identity.

const color = @import("color.zig");

/// Identifies block, underline, bar, or hidden cursor presentation.
pub const CursorShape = enum {
    block,
    underline,
    bar,
    none,
};

/// Stores cursor shape and blink state.
pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

/// Selects a program override or restoration to configured default style.
pub const CursorStyleCommand = union(enum) {
    restore_default,
    program_override: CursorStyle,
};

const Rgb = color.Rgb;

/// Provides the default blinking block cursor.
pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

/// Owns cursor position, style layers, and client-movement identity.
pub const SemanticCursor = struct {
    row: u16,
    col: u16,
    visible: bool,
    effective_shape: CursorShape,
    blink_intent: bool,
    default_style: CursorStyle,
    program_override_style: ?CursorStyle,
    cursor_color: ?Rgb,
    cursor_text_color: ?Rgb,
    position_changed_by_client_at: u64,

    /// Initializes a cursor at the origin with the supplied default style.
    pub fn init(default_style: CursorStyle) SemanticCursor {
        return .{
            .row = 0,
            .col = 0,
            .visible = true,
            .effective_shape = default_style.shape,
            .blink_intent = default_style.blink,
            .default_style = default_style,
            .program_override_style = null,
            .cursor_color = null,
            .cursor_text_color = null,
            .position_changed_by_client_at = 0,
        };
    }

    /// Returns position and style to terminal-reset defaults and advances client identity.
    pub fn reset(self: *SemanticCursor) void {
        const default_style = self.default_style;
        self.* = init(default_style);
    }

    /// Returns position and pending wrap to the alternate-screen origin.
    pub fn resetForAltEntry(self: *SemanticCursor) void {
        self.row = 0;
        self.col = 0;
        self.effective_shape = .none;
        self.blink_intent = true;
        self.program_override_style = null;
        self.position_changed_by_client_at = 0;
    }

    /// Returns the program override when present, otherwise the configured default.
    pub fn effectiveStyle(self: *const SemanticCursor) CursorStyle {
        return .{ .shape = self.effective_shape, .blink = self.blink_intent };
    }

    /// Replaces the configured default without disturbing a program override.
    pub fn setDefaultStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.default_style = style;
        if (self.program_override_style == null) self.applyStyle(style);
    }

    /// Installs a program cursor-style override.
    pub fn setProgramStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.program_override_style = style;
        self.applyStyle(style);
    }

    /// Replaces only the program-selected shape while preserving blink intent.
    pub fn setProgramShape(self: *SemanticCursor, shape: CursorShape) void {
        self.setProgramStyle(.{ .shape = shape, .blink = self.blink_intent });
    }

    /// Restores a previously saved effective style as the program override.
    pub fn restoreSavedStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.program_override_style = if (style.shape == self.default_style.shape and style.blink == self.default_style.blink) null else style;
        self.applyStyle(style);
    }

    /// Clears the program override and exposes the configured default.
    pub fn restoreDefaultStyle(self: *SemanticCursor) void {
        self.program_override_style = null;
        self.applyStyle(self.default_style);
    }

    /// Moves to exact bounded coordinates and advances client-movement identity.
    pub fn setPositionByClient(self: *SemanticCursor, row: u16, col: u16) void {
        if (self.row != row or self.col != col) self.position_changed_by_client_at +|= 1;
        self.row = row;
        self.col = col;
    }

    /// Moves to exact bounded coordinates without changing client identity.
    pub fn setPositionStructural(self: *SemanticCursor, row: u16, col: u16) void {
        self.row = row;
        self.col = col;
    }

    /// Moves the row and advances client-movement identity.
    pub fn setRowByClient(self: *SemanticCursor, row: u16) void {
        self.setPositionByClient(row, self.col);
    }

    fn setRowStructural(self: *SemanticCursor, row: u16) void {
        self.setPositionStructural(row, self.col);
    }

    /// Moves the column and advances client-movement identity.
    pub fn setColByClient(self: *SemanticCursor, col: u16) void {
        self.setPositionByClient(self.row, col);
    }

    fn setColStructural(self: *SemanticCursor, col: u16) void {
        self.setPositionStructural(self.row, col);
    }

    fn applyStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.effective_shape = style.shape;
        self.blink_intent = style.blink;
    }
};
