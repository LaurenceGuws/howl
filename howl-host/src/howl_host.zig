//! Curates the native Linux window host and deterministic layout values.

/// Owns the main-thread Wayland window and one render thread.
pub const Window = @import("window.zig").Window;
/// Reports exact native window startup, dispatch, and rendering failures.
pub const WindowError = @import("window.zig").Error;

/// Selects the fixed first-tab split direction.
pub const Axis = @import("layout.zig").Axis;
/// Owns the fixed topology and transactional geometry.
pub const Layout = @import("layout.zig").Layout;
/// Reports exact geometry and generation failures.
pub const LayoutError = @import("layout.zig").Error;
/// Locates one visible terminal.
pub const Rect = @import("layout.zig").Rect;
/// Bounds layout width and height.
pub const Size = @import("layout.zig").Size;
/// Carries one complete immutable visible-layout generation.
pub const Snapshot = @import("layout.zig").Snapshot;
/// Divides the first tab between two terminals.
pub const Split = @import("layout.zig").Split;
/// Holds either one terminal or the first-freeze split.
pub const Tab = @import("layout.zig").Tab;
/// Identifies one terminal for the Host lifetime.
pub const TerminalId = @import("layout.zig").TerminalId;

/// Owns all three fixed Linux PTY/VT terminal threads.
pub const Terminals = @import("terminal.zig").Set;
/// Reports exact terminal, PTY, queue, VT, or cleanup failure.
pub const TerminalError = @import("terminal.zig").Error;
/// Copies one bounded immutable terminal surface generation.
pub const TerminalSnapshot = @import("terminal.zig").Snapshot;
