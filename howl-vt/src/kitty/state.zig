//! Owns terminal-consumed Kitty keyboard and color-stack state.

const color = @import("color.zig");
const key = @import("key.zig");

const ScreenState = struct {
    keyboard: key.Stack = .{},
};

/// Combines per-screen keyboard stacks with the terminal color stack.
pub const KittyState = struct {
    main: ScreenState = .{},
    alt: ScreenState = .{},
    color_stack: color.Stack = .{},

    /// Returns mutable Kitty state for the currently selected screen.
    pub fn activeScreen(self: *KittyState, alt_active: bool) *ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Returns borrowed read-only Kitty state for the selected screen.
    pub fn activeScreenConst(self: *const KittyState, alt_active: bool) *const ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Resets Kitty state governed by terminal reset.
    pub fn resetTerminalState(self: *KittyState) void {
        self.main.keyboard = .{};
        self.alt.keyboard = .{};
        self.color_stack.len = 0;
    }
};
