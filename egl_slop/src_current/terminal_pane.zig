//! Owns one real Control terminal and its retained render-thread visual.
//!
//! PaneId is the complete routing identity: Screen never reuses it. Visual
//! dirtiness is acknowledged only after fixed pane storage admits a complete
//! projection; synchronized output remains cumulative and unacknowledged.

const std = @import("std");
const control = @import("howl_control");
const render = @import("howl_render").terminal;
const screen_module = @import("screen.zig");
const tiled = @import("tiled_panes.zig");
const c = @import("renderer_c");

pub const PaneId = tiled.PaneId;
pub const Rect = tiled.Rect;
pub const TabId = screen_module.TabId;
pub const GridSize = tiled.GridSize;
pub const SplitAxis = tiled.SplitAxis;

const selection_style = render.SelectionStyle{
    .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee },
    .background = .{ .r = 0xd6, .g = 0x5d, .b = 0x0e },
};

/// Reports retained projection or terminal construction failure.
pub const Error = control.InitError || render.Error || error{
    GeometryUnstable,
    VisualWithheld,
};

/// Owns actual projected cells, row geometry, revisions, and cursor baseline.
pub const RetainedVisual = struct {
    allocator: std.mem.Allocator,
    cells: []render.Cell,
    scratch: []render.Cell,
    geometry: []render.LineGeometry,
    versions: []u64,
    patches: []render.RowPatch,
    rows: u16,
    cols: u16,
    baseline: ?render.ProjectionBaseline = null,
    token: ?control.DirtyToken = null,

    /// Allocate exact retained and staging storage for one pane grid.
    pub fn init(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
    ) std.mem.Allocator.Error!RetainedVisual {
        const count = @as(usize, rows) * cols;
        const all_cells = try allocator.alloc(render.Cell, count * 2);
        errdefer allocator.free(all_cells);
        const geometry = try allocator.alloc(render.LineGeometry, rows);
        errdefer allocator.free(geometry);
        const versions = try allocator.alloc(u64, rows);
        errdefer allocator.free(versions);
        @memset(versions, 0);
        const patches = try allocator.alloc(render.RowPatch, rows);
        return .{
            .allocator = allocator,
            .cells = all_cells[0..count],
            .scratch = all_cells[count..],
            .geometry = geometry,
            .versions = versions,
            .patches = patches,
            .rows = rows,
            .cols = cols,
        };
    }

    /// Release all retained and staging allocations.
    pub fn deinit(self: *RetainedVisual) void {
        self.allocator.free(self.cells.ptr[0 .. self.cells.len + self.scratch.len]);
        self.allocator.free(self.geometry);
        self.allocator.free(self.versions);
        self.allocator.free(self.patches);
        self.* = undefined;
    }

    /// Admit one complete cumulative view or leave dirtiness unacknowledged.
    pub fn capture(
        self: *RetainedVisual,
        terminal: *control.Terminal,
    ) (render.Error || error{ GeometryUnstable, VisualWithheld })!bool {
        var borrow = terminal.borrowVisual();
        const source = borrow.view();
        if (source.view.rows != self.rows or source.view.cols != self.cols) {
            borrow.decline();
            return error.GeometryUnstable;
        }
        if (source.synchronized_output and terminal.state() == .running) {
            borrow.decline();
            return error.VisualWithheld;
        }
        const mode: render.ProjectMode = if (self.baseline) |baseline|
            .{ .incremental = baseline }
        else
            .full;
        const update = render.project(source, mode, .{
            .cells = self.scratch,
            .rows = self.patches,
        }, selection_style) catch |failure| retry: {
            if (failure != error.FullRequired) {
                borrow.decline();
                return failure;
            }
            break :retry render.project(source, .full, .{
                .cells = self.scratch,
                .rows = self.patches,
            }, selection_style) catch |full_failure| {
                borrow.decline();
                return full_failure;
            };
        };
        const changed = self.token == null or self.token.? != source.dirty_token;
        for (update.row_patches) |patch| {
            const destination = @as(usize, patch.row) * self.cols + patch.start_col;
            const end = patch.cell_offset + patch.cell_count;
            @memcpy(
                self.cells[destination..][0..patch.cell_count],
                update.cells[patch.cell_offset..end],
            );
            self.geometry[patch.row] = patch.geometry;
            self.versions[patch.row] = nextVersion(self.versions[patch.row]);
        }
        self.baseline = update.next_baseline;
        self.token = source.dirty_token;
        const inspection = borrow.admit();
        std.debug.assert(inspection == .acknowledged or inspection == .already_acknowledged);
        return changed;
    }
};

/// Owns one real Control terminal for one globally never-reused PaneId.
pub const TerminalPane = struct {
    allocator: std.mem.Allocator,
    id: PaneId,
    terminal: *control.Terminal,
    visual: RetainedVisual,
    rect: Rect,
    available: bool = true,

    /// Construct endpoint, PTY, VT, wake route, and retained visual completely.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        id: PaneId,
        rect: Rect,
        base_config: control.Config,
        render_signal_fd: std.posix.fd_t,
    ) Error!*TerminalPane {
        var config = base_config;
        config.cols = rect.cols;
        config.rows = rect.rows;
        const terminal = try control.Terminal.init(
            allocator,
            io,
            config,
            .{ .signal_fd = render_signal_fd },
        );
        errdefer terminal.deinit();
        var visual = try RetainedVisual.init(allocator, rect.rows, rect.cols);
        errdefer visual.deinit();
        const captured = visual.capture(terminal) catch |failure| switch (failure) {
            error.VisualWithheld => return error.GeometryUnstable,
            else => |cause| return cause,
        };
        std.debug.assert(captured);
        const self = try allocator.create(TerminalPane);
        self.* = .{
            .allocator = allocator,
            .id = id,
            .terminal = terminal,
            .visual = visual,
            .rect = rect,
        };
        return self;
    }

    /// Terminate the process group and endpoint before releasing retained state.
    pub fn deinit(self: *TerminalPane) void {
        self.terminal.deinit();
        self.visual.deinit();
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
    }

    /// Consume cumulative progress and retain the newest admissible visual.
    pub fn consumeWake(self: *TerminalPane) (render.Error || error{GeometryUnstable})!bool {
        if (!self.terminal.wakePending()) return false;
        self.terminal.consumeWake();
        const captured = self.visual.capture(self.terminal) catch |failure| switch (failure) {
            error.VisualWithheld => return false,
            else => |cause| return cause,
        };
        if (self.terminal.state() != .running) self.available = false;
        return captured;
    }
};

const ResizeAdmission = struct {
    pane: *TerminalPane,
    rect: Rect,
    replacement: ?RetainedVisual,
};

/// Owns Screen and the bounded render-thread-only PaneId terminal registry.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    screen: screen_module.Screen,
    panes: [screen_module.live_pane_limit]?*TerminalPane = @splat(null),
    count: u8 = 0,
    config: control.Config,
    signal_fd: std.posix.fd_t,

    /// Construct the first terminal before publishing the initial Screen.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        name: []const u8,
        size: GridSize,
        config: control.Config,
        signal_fd: std.posix.fd_t,
    ) (Error || error{ InvalidName, InvalidSize })!Registry {
        const id: PaneId = @fromBackingInt(1);
        const pane = try TerminalPane.init(
            allocator,
            io,
            id,
            fullRect(size),
            config,
            signal_fd,
        );
        errdefer pane.deinit();
        var result = Registry{
            .allocator = allocator,
            .io = io,
            .screen = try .init(allocator, name, size),
            .config = config,
            .signal_fd = signal_fd,
        };
        result.panes[0] = pane;
        result.count = 1;
        return result;
    }

    /// Retire panes in reverse registry order before releasing Screen names.
    pub fn deinit(self: *Registry) void {
        var index = self.count;
        while (index > 0) {
            index -= 1;
            self.panes[index].?.deinit();
            self.panes[index] = null;
        }
        self.count = 0;
        self.screen.deinit();
    }

    /// Construct a terminal before publishing one named tab.
    pub fn createTab(
        self: *Registry,
        name: []const u8,
    ) (Error || error{ InvalidName, TabLimit, PaneLimit, IdExhausted })!screen_module.CreatedTab {
        const id = try self.screen.candidatePaneId();
        const pane = try TerminalPane.init(
            self.allocator,
            self.io,
            id,
            fullRect(self.screen.size),
            self.config,
            self.signal_fd,
        );
        errdefer pane.deinit();
        const created = try self.screen.createTab(name);
        std.debug.assert(created.pane == id);
        self.append(pane);
        return created;
    }

    /// Construct and resize terminals before publishing one split.
    pub fn splitPane(
        self: *Registry,
        tab: TabId,
        target: PaneId,
        axis: SplitAxis,
    ) (Error || control.ResizeError || error{
        StaleTab,
        StalePane,
        PaneLimit,
        GeometryLimit,
        IdExhausted,
    })!PaneId {
        var candidate = self.screen;
        const id = try candidate.splitPane(tab, target, axis);
        const pane = try TerminalPane.init(
            self.allocator,
            self.io,
            id,
            try paneRect(&candidate, id),
            self.config,
            self.signal_fd,
        );
        errdefer pane.deinit();
        try self.resizeTo(&candidate);
        self.screen = candidate;
        self.append(pane);
        return id;
    }

    /// Resize survivors before topology commit, then retire the removed pane.
    pub fn closePane(
        self: *Registry,
        tab: TabId,
        id: PaneId,
    ) (control.ResizeError || render.Error || error{
        StaleTab,
        StalePane,
        LastPane,
        GeometryLimit,
        GeometryUnstable,
    })!void {
        var candidate = self.screen;
        try candidate.closePane(tab, id);
        try self.resizeTo(&candidate);
        self.screen = candidate;
        self.retire(id);
    }

    /// Publish tab removal before reverse retirement of all removed terminals.
    pub fn closeTab(self: *Registry, id: TabId) error{ StaleTab, LastTab }!void {
        var removed: [tiled.pane_limit]PaneId = undefined;
        const ids = try self.screen.closeTab(id, &removed);
        var index = ids.len;
        while (index > 0) {
            index -= 1;
            self.retire(ids[index]);
        }
    }

    /// Resize every live terminal before publishing complete Screen geometry.
    pub fn resize(
        self: *Registry,
        size: GridSize,
    ) (control.ResizeError || render.Error || error{
        InvalidSize,
        GeometryLimit,
        GeometryUnstable,
    })!bool {
        var candidate = self.screen;
        const changed = try candidate.resize(size);
        if (!changed) return false;
        try self.resizeTo(&candidate);
        self.screen = candidate;
        return true;
    }

    /// Consume all cumulative terminal progress after one shared render wake.
    pub fn consumeWakes(
        self: *Registry,
        changed: *[screen_module.live_pane_limit]PaneId,
    ) (render.Error || error{GeometryUnstable})![]const PaneId {
        var changed_count: u8 = 0;
        for (self.panes[0..self.count]) |entry| {
            const pane = entry.?;
            if (!pane.terminal.wakePending()) continue;
            if (try pane.consumeWake()) {
                changed[changed_count] = pane.id;
                changed_count += 1;
            }
        }
        return changed[0..changed_count];
    }

    /// Return one registry-owned terminal pane by globally stable identity.
    pub fn terminalPane(self: *Registry, id: PaneId) error{StalePane}!*TerminalPane {
        return self.panes[self.indexOf(id) orelse return error.StalePane].?;
    }

    /// Return the active tab's focused terminal pane.
    pub fn focused(self: *Registry) *TerminalPane {
        return self.terminalPane(self.screen.focusedPane()) catch
            @panic("Screen focus absent from terminal registry");
    }

    /// Validate exact topology-to-terminal identity and geometry ownership.
    pub fn validate(self: *const Registry) error{InvalidRegistry}!void {
        self.screen.validate() catch return error.InvalidRegistry;
        if (self.count != self.screen.livePaneCount()) return error.InvalidRegistry;
        for (self.panes[0..self.count], 0..) |entry, index| {
            const pane_value = entry orelse return error.InvalidRegistry;
            for (self.panes[0..index]) |prior|
                if (prior.?.id == pane_value.id) return error.InvalidRegistry;
            const rect = paneRect(&self.screen, pane_value.id) catch return error.InvalidRegistry;
            if (!std.meta.eql(rect, pane_value.rect)) return error.InvalidRegistry;
        }
    }

    fn resizeTo(
        self: *Registry,
        candidate: *const screen_module.Screen,
    ) (control.ResizeError || render.Error || error{GeometryUnstable})!void {
        var admissions: [screen_module.live_pane_limit]ResizeAdmission = undefined;
        var admitted: u8 = 0;
        for (self.panes[0..self.count]) |entry| {
            const pane = entry.?;
            const target = paneRect(candidate, pane.id) catch continue;
            if (std.meta.eql(pane.rect, target)) continue;
            var replacement: ?RetainedVisual = null;
            if (pane.available) {
                replacement = RetainedVisual.init(
                    pane.allocator,
                    target.rows,
                    target.cols,
                ) catch |failure| {
                    try rollbackAdmissions(admissions[0..admitted]);
                    return failure;
                };
                const resized = pane.terminal.resize(target.cols, target.rows) catch |failure| {
                    replacement.?.deinit();
                    try rollbackAdmissions(admissions[0..admitted]);
                    return failure;
                };
                std.debug.assert(resized.changed);
                const captured = replacement.?.capture(pane.terminal) catch |failure| {
                    const restored = pane.terminal.resize(
                        pane.rect.cols,
                        pane.rect.rows,
                    ) catch {
                        replacement.?.deinit();
                        rollbackAdmissions(admissions[0..admitted]) catch
                            return error.ResizeRollbackFailed;
                        return error.ResizeRollbackFailed;
                    };
                    std.debug.assert(restored.changed);
                    replacement.?.deinit();
                    try rollbackAdmissions(admissions[0..admitted]);
                    return switch (failure) {
                        error.VisualWithheld => error.GeometryUnstable,
                        else => |cause| cause,
                    };
                };
                std.debug.assert(captured);
            }
            admissions[admitted] = .{
                .pane = pane,
                .rect = target,
                .replacement = replacement,
            };
            admitted += 1;
        }
        for (admissions[0..admitted]) |*admission| {
            if (admission.replacement) |replacement| {
                admission.pane.visual.deinit();
                admission.pane.visual = replacement;
                admission.replacement = null;
            }
            admission.pane.rect = admission.rect;
        }
    }

    fn append(self: *Registry, pane_value: *TerminalPane) void {
        std.debug.assert(self.count < screen_module.live_pane_limit);
        self.panes[self.count] = pane_value;
        self.count += 1;
    }

    fn retire(self: *Registry, id: PaneId) void {
        const index = self.indexOf(id) orelse @panic("Screen retired an absent terminal");
        self.panes[index].?.deinit();
        var cursor = index;
        while (cursor + 1 < self.count) : (cursor += 1)
            self.panes[cursor] = self.panes[cursor + 1];
        self.count -= 1;
        self.panes[self.count] = null;
    }

    fn indexOf(self: *const Registry, id: PaneId) ?u8 {
        for (self.panes[0..self.count], 0..) |entry, index|
            if (entry.?.id == id) return @intCast(index);
        return null;
    }
};

// Restores every already-resized Control in reverse order while always
// releasing its uncommitted retained replacement. A failed native rollback is
// reported only after every remaining admission receives the same cleanup.
fn rollbackAdmissions(
    admissions: []ResizeAdmission,
) error{ResizeRollbackFailed}!void {
    var failed = false;
    var index = admissions.len;
    while (index > 0) {
        index -= 1;
        const admission = &admissions[index];
        if (admission.replacement) |*replacement| {
            const restored = admission.pane.terminal.resize(
                admission.pane.rect.cols,
                admission.pane.rect.rows,
            ) catch {
                failed = true;
                replacement.deinit();
                admission.replacement = null;
                continue;
            };
            std.debug.assert(restored.changed);
            replacement.deinit();
            admission.replacement = null;
        }
    }
    if (failed) return error.ResizeRollbackFailed;
}

fn paneRect(screen: *const screen_module.Screen, id: PaneId) error{StalePane}!Rect {
    var tabs: [screen_module.tab_limit]TabId = undefined;
    for (screen.tabOrder(&tabs)) |tab| {
        var placements: [tiled.pane_limit]screen_module.Placement = undefined;
        const values = screen.placements(tab, &placements) catch
            @panic("Screen returned a stale ordered TabId");
        for (values) |placement| if (placement.pane == id) return placement.rect;
    }
    return error.StalePane;
}

fn fullRect(size: GridSize) Rect {
    return .{ .col = 0, .row = 0, .cols = size.cols, .rows = size.rows };
}

fn nextVersion(value: u64) u64 {
    return if (value == std.math.maxInt(u64)) 1 else value + 1;
}

fn testRuntimeDirectory() ![]u8 {
    var random: [8]u8 = undefined;
    std.testing.io.random(&random);
    return std.fmt.allocPrint(std.testing.allocator, "/tmp/howl-pane-{x}", .{random});
}

fn waitForWake(terminal: *control.Terminal) !void {
    var attempts: u8 = 0;
    while (!terminal.wakePending() and attempts < 100) : (attempts += 1) {
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(10),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expect(terminal.wakePending());
}

test "real Control endpoint and final visual live exactly with PaneId" {
    const runtime_dir = try testRuntimeDirectory();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    const pane = try TerminalPane.init(
        std.testing.allocator,
        std.testing.io,
        @fromBackingInt(1),
        .{ .col = 0, .row = 0, .cols = 8, .rows = 2 },
        .{
            .runtime_dir = runtime_dir,
            .shell = "/bin/sh",
            .command = "printf final; exit 0",
            .history_rows = 0,
        },
        signal_fd,
    );
    errdefer pane.deinit();
    const endpoint = try std.testing.allocator.dupe(u8, pane.terminal.endpoint().?);
    defer std.testing.allocator.free(endpoint);
    try waitForWake(pane.terminal);
    while (pane.available) {
        const changed = try pane.consumeWake();
        if (!pane.available) try std.testing.expect(changed);
        if (pane.available) try waitForWake(pane.terminal);
    }
    try std.testing.expect(pane.visual.token != null);
    try std.Io.Dir.accessAbsolute(std.testing.io, endpoint, .{});
    pane.deinit();
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.accessAbsolute(std.testing.io, endpoint, .{}),
    );
}

test "synchronized output stays dirty until retained admission" {
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    const pane = try TerminalPane.init(
        std.testing.allocator,
        std.testing.io,
        @fromBackingInt(2),
        .{ .col = 0, .row = 0, .cols = 8, .rows = 2 },
        .{
            .shell = "/bin/sh",
            .command = "printf '\\033[?2026hheld'; sleep 0.2; printf 'done\\033[?2026l'; sleep 1",
            .history_rows = 0,
        },
        signal_fd,
    );
    defer pane.deinit();
    const admitted_before_sync = pane.visual.token.?;
    try waitForWake(pane.terminal);
    try std.testing.expect(!(try pane.consumeWake()));
    try std.testing.expectEqual(admitted_before_sync, pane.visual.token.?);
    try waitForWake(pane.terminal);
    try std.testing.expect(try pane.consumeWake());
    try std.testing.expect(pane.visual.token != null);
}

test "topology rejection retires real candidate without consuming identity" {
    const runtime_dir = try testRuntimeDirectory();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        "one",
        .{ .cols = 8, .rows = 2 },
        .{
            .runtime_dir = runtime_dir,
            .shell = "/bin/cat",
            .history_rows = 0,
        },
        signal_fd,
    );
    defer registry.deinit();
    const candidate = try registry.screen.candidatePaneId();
    try std.testing.expectError(error.InvalidName, registry.createTab(""));
    try std.testing.expectEqual(candidate, try registry.screen.candidatePaneId());
    try std.testing.expectEqual(@as(u8, 1), registry.count);
    try registry.validate();
}

test "retired PaneId cannot receive a stale shared wake" {
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        "one",
        .{ .cols = 8, .rows = 2 },
        .{
            .shell = "/bin/cat",
            .history_rows = 0,
        },
        signal_fd,
    );
    defer registry.deinit();
    const retired = registry.screen.focusedPane();
    const second = try registry.createTab("two");
    try registry.closeTab(@fromBackingInt(1));
    try std.testing.expectError(error.StalePane, registry.terminalPane(retired));
    try std.testing.expect(registry.screen.focusedPane() == second.pane);
    var changed: [screen_module.live_pane_limit]PaneId = undefined;
    const wakes = try registry.consumeWakes(&changed);
    for (wakes) |id| try std.testing.expect(id != retired);
    try registry.validate();
}

test "hidden tab progress is retained without changing active identity" {
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        "visible",
        .{ .cols = 12, .rows = 2 },
        .{
            .shell = "/bin/sh",
            .command = "printf hidden; sleep 1",
            .history_rows = 0,
        },
        signal_fd,
    );
    defer registry.deinit();
    const visible_tab = registry.screen.activeTab();
    const hidden = try registry.createTab("hidden");
    try std.testing.expect(try registry.screen.switchTab(visible_tab));
    try waitForWake((try registry.terminalPane(hidden.pane)).terminal);
    var changed: [screen_module.live_pane_limit]PaneId = undefined;
    var admitted = false;
    var attempts: u8 = 0;
    while (!admitted and attempts < 100) : (attempts += 1) {
        for (try registry.consumeWakes(&changed)) |id| {
            if (id == hidden.pane) admitted = true;
        }
        if (!admitted) {
            try (std.Io.Clock.Duration{
                .raw = .fromMilliseconds(10),
                .clock = .awake,
            }).sleep(std.testing.io);
        }
    }
    try std.testing.expect(admitted);
    try std.testing.expectEqual(visible_tab, registry.screen.activeTab());
    try std.testing.expect((try registry.terminalPane(hidden.pane)).visual.token != null);
    try registry.validate();
}

test "retained allocation failure leaves topology and pane bytes exact" {
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    try std.testing.expect(signal_fd >= 0);
    defer std.debug.assert(c.close(signal_fd) == 0);
    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        "one",
        .{ .cols = 8, .rows = 2 },
        .{
            .shell = "/bin/cat",
            .history_rows = 0,
        },
        signal_fd,
    );
    defer registry.deinit();
    const id = registry.screen.focusedPane();
    const pane = try registry.terminalPane(id);
    const screen_before = registry.screen;
    const rect_before = pane.rect;
    const visual_before = pane.visual;
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    pane.allocator = failing.allocator();
    defer pane.allocator = std.testing.allocator;
    try std.testing.expectError(
        error.OutOfMemory,
        registry.resize(.{ .cols = 10, .rows = 2 }),
    );
    try std.testing.expect(std.meta.eql(screen_before, registry.screen));
    try std.testing.expect(std.meta.eql(rect_before, pane.rect));
    try std.testing.expectEqual(visual_before.cells.ptr, pane.visual.cells.ptr);
    try std.testing.expectEqual(visual_before.geometry.ptr, pane.visual.geometry.ptr);
    try std.testing.expectEqual(visual_before.versions.ptr, pane.visual.versions.ptr);
    try std.testing.expectEqual(visual_before.patches.ptr, pane.visual.patches.ptr);
    try registry.validate();
}

test "registry storage matches exact aggregate and visible bounds" {
    try std.testing.expectEqual(
        @as(usize, screen_module.live_pane_limit),
        @typeInfo(@FieldType(Registry, "panes")).array.len,
    );
    try std.testing.expectEqual(@as(u8, 16), tiled.pane_limit);
}
