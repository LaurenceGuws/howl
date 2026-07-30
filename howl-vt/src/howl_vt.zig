//! Public embedding root for the terminal emulator.

const terminal = @import("terminal.zig");
const scalar_storage = @import("scalar_storage.zig");
const unicode_17 = @import("unicode_17.zig");
const std = @import("std");

/// Owns one terminal emulator, its retained state, replies, and consequences.
pub const Terminal = terminal.Terminal;
/// Owns bounded overflow scalars for one caller-owned cell cohort.
pub const ScalarStorage = scalar_storage.Storage;
/// Borrows pinned Unicode 17 classification without transferring VT occupancy.
pub const UnicodeProperties = unicode_17.Properties;
/// Returns pinned Unicode 17 facts for one valid scalar.
pub const unicodeProperties = unicode_17.properties;
/// Reports the fixed scalar-storage contract.
pub const scalar = struct {
    /// Number of cells qualified by one fixed scalar bank.
    pub const page_cells = scalar_storage.page_cells;
    /// Fixed scalar bytes retained for each owner-local page.
    pub const bank_bytes = scalar_storage.scalar_bank_bytes;
    /// Scalars retained directly in each lead cell.
    pub const inline_scalars = scalar_storage.inline_scalars;
    /// Maximum accepted scalars in one grapheme.
    pub const maximum_scalars = scalar_storage.maximum_scalars;
};

test {
    std.testing.refAllDecls(Terminal);
    std.testing.refAllDecls(ScalarStorage);
}
