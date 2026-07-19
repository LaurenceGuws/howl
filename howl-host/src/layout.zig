//! Owns the fixed first-freeze topology and transactional visible geometry.

const std = @import("std");

/// The first host freeze owns exactly two tabs.
pub const tab_count: usize = 2;

/// The first host freeze owns the two split terminals and one second-tab terminal.
pub const terminal_count: usize = 3;

/// Identifies one terminal for the complete lifetime of a Host.
pub const TerminalId = enum(u2) {
    first,
    second,
    third,

    /// Returns the fixed-array index owned by this identifier.
    pub fn index(self: TerminalId) usize {
        return @intFromEnum(self);
    }
};

/// Selects the direction in which the first tab divides its terminals.
pub const Axis = enum {
    horizontal,
    vertical,
};

/// Holds a bounded pixel or cell extent accepted by layout geometry.
pub const Size = struct {
    width: u16,
    height: u16,
};

/// Locates one terminal within the active tab's complete rectangular layout.
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

/// Associates one visible terminal with its complete rectangle and focus state.
pub const Placement = struct {
    terminal: TerminalId,
    rect: Rect,
    focused: bool,
};

/// Publishes one immutable, complete active-tab layout generation.
pub const Snapshot = struct {
    generation: u64,
    tab: u1,
    size: Size,
    count: u2,
    placements: [2]Placement,

    /// Returns only initialized placements; hidden tabs and terminals are absent.
    pub fn visible(self: *const Snapshot) []const Placement {
        return self.placements[0..self.count];
    }
};

/// Reports why a requested layout mutation left the previous state unchanged.
pub const Error = error{
    invalid_size,
    terminal_hidden,
    generation_exhausted,
};

/// Divides one tab between two stable terminal identities.
pub const Split = struct {
    axis: Axis,
    first: TerminalId,
    second: TerminalId,
};

/// Describes either the first-freeze split or one full-tab terminal.
pub const Tab = union(enum) {
    split: Split,
    terminal: TerminalId,

    fn initialFocus(self: Tab) TerminalId {
        return switch (self) {
            .split => |split| split.first,
            .terminal => |terminal| terminal,
        };
    }

    fn contains(self: Tab, terminal: TerminalId) bool {
        return switch (self) {
            .split => |split| terminal == split.first or terminal == split.second,
            .terminal => |one| terminal == one,
        };
    }
};

/// Owns the fixed topology, active tab, focus, size, and publication generation.
pub const Layout = struct {
    tabs: [tab_count]Tab,
    selected_tab: u1,
    focused: TerminalId,
    size: Size,
    generation: u64,

    /// Constructs two tabs and validates the initial complete geometry.
    pub fn init(axis: Axis, size: Size) Error!Layout {
        const tabs = [tab_count]Tab{
            .{ .split = .{
                .axis = axis,
                .first = .first,
                .second = .second,
            } },
            .{ .terminal = .third },
        };
        const layout = Layout{
            .tabs = tabs,
            .selected_tab = 0,
            .focused = .first,
            .size = size,
            .generation = 1,
        };
        try validateTab(layout.tabs[0], size);
        return layout;
    }

    /// Returns current geometry or an exact failure if caller-mutated public state is invalid.
    pub fn snapshot(self: *const Layout) Error!Snapshot {
        return self.currentSnapshot();
    }

    /// Selects one of the two tabs and publishes its initial focus.
    pub fn selectTab(self: *Layout, tab: u1) Error!Snapshot {
        if (tab == self.selected_tab) return try self.snapshot();
        const generation = try nextGeneration(self.generation);
        const focused = self.tabs[tab].initialFocus();
        const candidate = try makeSnapshot(
            self.tabs[tab],
            tab,
            focused,
            self.size,
            generation,
        );
        self.selected_tab = tab;
        self.focused = focused;
        self.generation = generation;
        return candidate;
    }

    /// Focuses a terminal in the active tab or preserves state when it is hidden.
    pub fn focus(self: *Layout, terminal: TerminalId) Error!Snapshot {
        const tab = self.tabs[self.selected_tab];
        if (!tab.contains(terminal)) return error.terminal_hidden;
        if (terminal == self.focused) return try self.snapshot();
        const generation = try nextGeneration(self.generation);
        const candidate = try makeSnapshot(
            tab,
            self.selected_tab,
            terminal,
            self.size,
            generation,
        );
        self.focused = terminal;
        self.generation = generation;
        return candidate;
    }

    /// Applies a complete valid size or leaves size and generation unchanged.
    pub fn resize(self: *Layout, size: Size) Error!Snapshot {
        if (std.meta.eql(size, self.size)) return try self.snapshot();
        const generation = try nextGeneration(self.generation);
        const candidate = try makeSnapshot(
            self.tabs[self.selected_tab],
            self.selected_tab,
            self.focused,
            size,
            generation,
        );
        self.size = size;
        self.generation = generation;
        return candidate;
    }

    fn currentSnapshot(self: *const Layout) Error!Snapshot {
        return makeSnapshot(
            self.tabs[self.selected_tab],
            self.selected_tab,
            self.focused,
            self.size,
            self.generation,
        );
    }
};

fn nextGeneration(generation: u64) Error!u64 {
    if (generation == std.math.maxInt(u64)) return error.generation_exhausted;
    return generation + 1;
}

fn validateTab(tab: Tab, size: Size) Error!void {
    if (size.width == 0 or size.height == 0) return error.invalid_size;
    switch (tab) {
        .terminal => {},
        .split => |split| switch (split.axis) {
            .horizontal => if (size.width < 2) return error.invalid_size,
            .vertical => if (size.height < 2) return error.invalid_size,
        },
    }
}

fn makeSnapshot(
    tab: Tab,
    tab_index: u1,
    focused: TerminalId,
    size: Size,
    generation: u64,
) Error!Snapshot {
    try validateTab(tab, size);
    if (!tab.contains(focused)) return error.terminal_hidden;
    var placements: [2]Placement = undefined;
    const count: u2 = switch (tab) {
        .terminal => |terminal| single: {
            placements[0] = .{
                .terminal = terminal,
                .rect = .{ .x = 0, .y = 0, .width = size.width, .height = size.height },
                .focused = terminal == focused,
            };
            placements[1] = placements[0];
            break :single 1;
        },
        .split => |split| divided: {
            switch (split.axis) {
                .horizontal => {
                    const first_width = size.width / 2;
                    placements[0] = .{
                        .terminal = split.first,
                        .rect = .{ .x = 0, .y = 0, .width = first_width, .height = size.height },
                        .focused = split.first == focused,
                    };
                    placements[1] = .{
                        .terminal = split.second,
                        .rect = .{
                            .x = first_width,
                            .y = 0,
                            .width = size.width - first_width,
                            .height = size.height,
                        },
                        .focused = split.second == focused,
                    };
                },
                .vertical => {
                    const first_height = size.height / 2;
                    placements[0] = .{
                        .terminal = split.first,
                        .rect = .{ .x = 0, .y = 0, .width = size.width, .height = first_height },
                        .focused = split.first == focused,
                    };
                    placements[1] = .{
                        .terminal = split.second,
                        .rect = .{
                            .x = 0,
                            .y = first_height,
                            .width = size.width,
                            .height = size.height - first_height,
                        },
                        .focused = split.second == focused,
                    };
                },
            }
            break :divided 2;
        },
    };
    return .{
        .generation = generation,
        .tab = tab_index,
        .size = size,
        .count = count,
        .placements = placements,
    };
}
