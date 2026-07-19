//! Defines erase modes and erase event application.

/// Erase extent selected by CSI display and line erase controls.
pub const EraseMode = enum(u2) {
    cursor_to_end = 0,
    start_to_cursor = 1,
    all = 2,
    scrollback = 3,
};
