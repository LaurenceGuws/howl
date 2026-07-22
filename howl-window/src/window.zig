//! Owns one direct Wayland/xkb loop around bounded tabs, panes, and terminals.

const std = @import("std");
const howl_control = @import("howl_control");
const howl_vt = @import("howl_vt");
const renderer = @import("renderer.zig");
const workspace_model = @import("workspace.zig");
const c = @import("native.zig").c;
const MouseInput = @FieldType(howl_control.Input, "mouse");
const MouseButton = @FieldType(MouseInput, "button");
const MouseKind = @FieldType(MouseInput, "kind");

const initial_size = renderer.Size{ .width = 960, .height = 600 };
const max_wheel_steps: usize = 32;
const PaneId = workspace_model.PaneId;
const TabId = workspace_model.TabId;
const TerminalIndex = u6;
const KeyModifiers = @FieldType(@FieldType(howl_control.Input, "key"), "mods");

comptime {
    if (workspace_model.max_panes != @bitSizeOf(u64) or
        workspace_model.max_panes - 1 > std.math.maxInt(TerminalIndex))
        @compileError("workspace pane capacity must fit the terminal wake-bit domain");
}

const Repeat = struct {
    interval_ns: ?u64 = null,
    delay_ns: u64 = 1,
    key: ?u32 = null,

    fn configure(self: *Repeat, rate: i32, delay_ms: i32) error{InvalidRepeat}!void {
        if (rate < 0 or delay_ms < 0) return error.InvalidRepeat;
        self.key = null;
        if (rate == 0) {
            self.interval_ns = null;
            return;
        }
        self.interval_ns = @max(@as(u64, 1), std.time.ns_per_s / @as(u64, @intCast(rate)));
        self.delay_ns = @max(@as(u64, 1), @as(u64, @intCast(delay_ms)) * std.time.ns_per_ms);
    }

    fn press(self: *Repeat, key: u32, repeatable: bool) ?u64 {
        self.key = null;
        if (!repeatable or self.interval_ns == null) return null;
        self.key = key;
        return self.delay_ns;
    }

    fn release(self: *Repeat, key: u32) bool {
        if (self.key != key) return false;
        self.key = null;
        return true;
    }

    fn fire(self: *const Repeat) ?struct { key: u32, next_ns: u64 } {
        return .{ .key = self.key orelse return null, .next_ns = self.interval_ns orelse return null };
    }

    fn cancel(self: *Repeat) void {
        self.key = null;
    }
};

const HostKeys = struct {
    values: [16]u32 = undefined,
    count: u8 = 0,

    fn capture(self: *HostKeys, code: u32) bool {
        for (self.values[0..self.count]) |value| if (value == code) return true;
        if (self.count == self.values.len) return false;
        self.values[self.count] = code;
        self.count += 1;
        return true;
    }

    fn release(self: *HostKeys, code: u32) bool {
        for (self.values[0..self.count], 0..) |value, index| if (value == code) {
            self.count -= 1;
            if (index != self.count) self.values[index] = self.values[self.count];
            return true;
        };
        return false;
    }

    fn clear(self: *HostKeys) void {
        self.count = 0;
    }
};

const HostAction = enum {
    new_tab,
    split_horizontal,
    split_vertical,
    close_pane,
    close_tab,
    next_tab,
    previous_tab,
    focus_left,
    focus_right,
    focus_up,
    focus_down,
    resize_left,
    resize_right,
    resize_up,
    resize_down,
};

fn hostAction(symbol: u32, mods: KeyModifiers) ?HostAction {
    if (mods.hyper or mods.meta) return null;
    if (mods.control and mods.shift and !mods.alt and !mods.super) return switch (symbol) {
        c.XKB_KEY_t, c.XKB_KEY_T => .new_tab,
        c.XKB_KEY_Return => .split_horizontal,
        c.XKB_KEY_backslash, c.XKB_KEY_bar => .split_vertical,
        c.XKB_KEY_w, c.XKB_KEY_W => .close_pane,
        c.XKB_KEY_q, c.XKB_KEY_Q => .close_tab,
        c.XKB_KEY_Left => .resize_left,
        c.XKB_KEY_Right => .resize_right,
        c.XKB_KEY_Up => .resize_up,
        c.XKB_KEY_Down => .resize_down,
        c.XKB_KEY_Tab, c.XKB_KEY_ISO_Left_Tab => .previous_tab,
        else => null,
    };
    if (mods.control and !mods.shift and !mods.alt and !mods.super) return switch (symbol) {
        c.XKB_KEY_Tab => .next_tab,
        else => null,
    };
    if (mods.alt and !mods.control and !mods.shift and !mods.super) return switch (symbol) {
        c.XKB_KEY_Left => .focus_left,
        c.XKB_KEY_Right => .focus_right,
        c.XKB_KEY_Up => .focus_up,
        c.XKB_KEY_Down => .focus_down,
        else => null,
    };
    return null;
}

const PointerTarget = struct {
    pane: PaneId,
    row: i32,
    col: u16,
    pixel_x: u32,
    pixel_y: u32,
};

const ButtonTransition = struct {
    index: usize,
    target: PointerTarget,
    buttons_down: u8,
};

const PointerState = struct {
    position: ?struct { x: u32, y: u32 } = null,
    pressed: [3]?PointerTarget = @splat(null),
    buttons_down: u8 = 0,

    fn preparePress(self: *const PointerState, index: usize, target: PointerTarget) ?ButtonTransition {
        if (index >= self.pressed.len or self.pressed[index] != null) return null;
        return .{
            .index = index,
            .target = target,
            .buttons_down = self.buttons_down | (@as(u8, 1) << @intCast(index)),
        };
    }

    fn commitPress(self: *PointerState, transition: ButtonTransition) void {
        std.debug.assert(self.pressed[transition.index] == null);
        std.debug.assert(transition.buttons_down ==
            self.buttons_down | (@as(u8, 1) << @intCast(transition.index)));
        self.pressed[transition.index] = transition.target;
        self.buttons_down = transition.buttons_down;
    }

    fn prepareRelease(self: *const PointerState, index: usize) ?ButtonTransition {
        if (index >= self.pressed.len) return null;
        const target = self.pressed[index] orelse return null;
        return .{
            .index = index,
            .target = target,
            .buttons_down = self.buttons_down & ~(@as(u8, 1) << @intCast(index)),
        };
    }

    fn commitRelease(self: *PointerState, transition: ButtonTransition) void {
        std.debug.assert(std.meta.eql(self.pressed[transition.index].?, transition.target));
        std.debug.assert(transition.buttons_down ==
            self.buttons_down & ~(@as(u8, 1) << @intCast(transition.index)));
        self.pressed[transition.index] = null;
        self.buttons_down = transition.buttons_down;
    }

    fn move(self: *PointerState, target: PointerTarget) bool {
        for (self.pressed) |pressed| if (pressed) |value|
            if (value.pane != target.pane) return false;
        for (&self.pressed) |*pressed| {
            if (pressed.* != null) pressed.* = target;
        }
        return true;
    }
};

const Ready = packed struct(u8) {
    display_read: bool,
    display_write: bool,
    terminal: bool,
    render: bool,
    repeat: bool,
    padding: u3 = 0,

    fn from(fds: [4]std.posix.pollfd) Ready {
        return .{
            .display_read = fds[0].revents & std.posix.POLL.IN != 0,
            .display_write = fds[0].revents & std.posix.POLL.OUT != 0,
            .terminal = fds[1].revents & std.posix.POLL.IN != 0,
            .render = fds[2].revents & std.posix.POLL.IN != 0,
            .repeat = fds[3].revents & std.posix.POLL.IN != 0,
        };
    }
};

const WakeContext = struct { owner: ?*anyopaque = null, index: TerminalIndex = 0 };

const PaneOwner = struct {
    pane: ?PaneId = null,
    terminal: ?*howl_control.Terminal = null,
    geometry: Geometry = .{ .cols = 1, .rows = 1 },
    unavailable: bool = false,
    wake: WakeContext = .{},
};

pub const Error = renderer.StartError || renderer.Error || howl_control.InitError ||
    howl_control.InputError || howl_control.ResizeError || error{
    WaylandConnect,
    WaylandRegistry,
    WaylandProtocol,
    WaylandDispatch,
    WaylandFlush,
    KeyboardContext,
    KeyboardMap,
    KeyboardState,
    KeyboardRepeat,
    HostKeyLimit,
    Pointer,
    TerminalSignal,
    Poll,
    InputIncomplete,
    ResizeResultMismatch,
    ResizeTransactionFailed,
    InvalidSession,
    InvalidName,
    TabLimit,
    PaneLimit,
    DepthLimit,
    GeometryLimit,
    IdExhausted,
    StaleTab,
    StalePane,
    LastTab,
    LastPane,
};

const Loop = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    display: *c.struct_wl_display,
    registry: *c.struct_wl_registry,
    compositor: ?*c.struct_wl_compositor = null,
    wm_base: ?*c.struct_xdg_wm_base = null,
    surface: ?*c.struct_wl_surface = null,
    xdg_surface: ?*c.struct_xdg_surface = null,
    toplevel: ?*c.struct_xdg_toplevel = null,
    seat: ?*c.struct_wl_seat = null,
    keyboard: ?*c.struct_wl_keyboard = null,
    pointer: ?*c.struct_wl_pointer = null,
    xkb_context: ?*c.struct_xkb_context = null,
    xkb_keymap: ?*c.struct_xkb_keymap = null,
    xkb_state: ?*c.struct_xkb_state = null,
    terminal_signal: c_int,
    repeat_fd: c_int,
    repeat: Repeat = .{},
    host_keys: HostKeys = .{},
    pointer_state: PointerState = .{},
    wake_bits: std.atomic.Value(u64) = .init(0),
    panes: [workspace_model.max_panes]PaneOwner = @splat(.{}),
    render: ?*renderer.Render = null,
    size: renderer.Size = initial_size,
    pending_size: renderer.Size = initial_size,
    configured: bool = false,
    closed: bool = false,
    failure: ?Error = null,
    render_generation: u64 = 0,
    completed_generation: u64 = 0,
    workspace: ?workspace_model.Workspace = null,
    title: [128]u8 = undefined,

    fn init(allocator: std.mem.Allocator, io: std.Io, font_paths: []const []const u8) Error!*Loop {
        if (font_paths.len == 0) return error.FontOpen;
        const display = c.wl_display_connect(null) orelse return error.WaylandConnect;
        errdefer c.wl_display_disconnect(display);
        const registry = c.wl_display_get_registry(display) orelse return error.WaylandRegistry;
        errdefer c.wl_registry_destroy(registry);
        const terminal_signal = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (terminal_signal < 0) return error.TerminalSignal;
        errdefer closeOwned(terminal_signal);
        const repeat_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC | c.TFD_NONBLOCK);
        if (repeat_fd < 0) return error.KeyboardRepeat;
        errdefer closeOwned(repeat_fd);
        const self = try allocator.create(Loop);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .display = display,
            .registry = registry,
            .terminal_signal = terminal_signal,
            .repeat_fd = repeat_fd,
        };
        errdefer self.destroyWayland();
        if (c.wl_registry_add_listener(registry, &registry_listener, self) != 0)
            return error.WaylandRegistry;
        if (c.wl_display_roundtrip(display) < 0) return error.WaylandDispatch;
        const compositor = self.compositor orelse return error.WaylandProtocol;
        const wm_base = self.wm_base orelse return error.WaylandProtocol;
        const surface = c.wl_compositor_create_surface(compositor) orelse
            return error.WaylandProtocol;
        self.surface = surface;
        const xdg_surface = c.xdg_wm_base_get_xdg_surface(wm_base, surface) orelse
            return error.WaylandProtocol;
        self.xdg_surface = xdg_surface;
        if (c.xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, self) != 0)
            return error.WaylandProtocol;
        const toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse
            return error.WaylandProtocol;
        self.toplevel = toplevel;
        if (c.xdg_toplevel_add_listener(toplevel, &toplevel_listener, self) != 0)
            return error.WaylandProtocol;
        c.xdg_toplevel_set_title(toplevel, "Howl");
        c.wl_surface_commit(surface);
        while (!self.configured and self.failure == null)
            if (c.wl_display_dispatch(display) < 0) return error.WaylandDispatch;
        if (self.failure) |failure| return failure;
        self.size = self.pending_size;
        if (self.size.width < 2) return error.InvalidSize;
        const render = try renderer.Render.start(allocator, io, .{
            .display = display,
            .surface = surface,
            .size = self.size,
            .font_paths = font_paths,
        });
        self.render = render;
        errdefer render.deinit() catch |failure|
            @panic(@errorName(failure));
        errdefer {
            self.deinitTerminals();
        }
        const grid = gridSize(self.size, render.metrics());
        self.workspace = try workspace_model.Workspace.init(allocator, @enumFromInt(1), "tab", grid);
        try self.initPane(self.workspace.?.focusedPane(), .{ .cols = grid.cols, .rows = grid.rows });
        self.updateTitle();
        return self;
    }

    fn run(self: *Loop) Error!void {
        try self.submitVisible(self.visibleBits());
        while (!self.closed and self.failure == null) {
            if (c.wl_display_dispatch_pending(self.display) < 0) return error.WaylandDispatch;
            if (self.closed or self.failure != null) continue;
            if (!std.meta.eql(self.pending_size, self.size) and
                self.completed_generation == self.render_generation) try self.resizeAll();
            const flush = c.wl_display_flush(self.display);
            const flush_blocked = flush < 0 and std.posix.errno(flush) == .AGAIN;
            if (flush < 0 and !flush_blocked) return error.WaylandFlush;
            var fds = [_]std.posix.pollfd{
                .{
                    .fd = c.wl_display_get_fd(self.display),
                    .events = @as(i16, std.posix.POLL.IN) |
                        if (flush_blocked) @as(i16, std.posix.POLL.OUT) else 0,
                    .revents = 0,
                },
                .{ .fd = self.terminal_signal, .events = std.posix.POLL.IN, .revents = 0 },
                .{ .fd = self.render.?.signalFd(), .events = std.posix.POLL.IN, .revents = 0 },
                .{ .fd = self.repeat_fd, .events = std.posix.POLL.IN, .revents = 0 },
            };
            const ready = std.posix.poll(&fds, -1) catch return error.Poll;
            std.debug.assert(ready != 0);
            const faults = std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL;
            if (fds[2].revents & faults != 0) return error.Signal;
            if (fds[1].revents & faults != 0) return error.TerminalSignal;
            if (fds[3].revents & faults != 0) return error.KeyboardRepeat;
            if (fds[0].revents & faults != 0) return error.WaylandDispatch;
            const sources = Ready.from(fds);
            if (sources.render) {
                self.completed_generation = try self.render.?.completed();
                std.debug.assert(self.completed_generation != 0);
                if (!std.meta.eql(self.pending_size, self.size)) try self.resizeAll();
            }
            if (sources.terminal) {
                try drainEvent(self.terminal_signal);
                const changed = self.wake_bits.swap(0, .acq_rel);
                for (&self.panes, 0..) |*pane, index| if (changed & (@as(u64, 1) << @intCast(index)) != 0) {
                    const value = pane.terminal orelse continue;
                    value.consumeWake();
                    pane.unavailable = value.state() != .running;
                };
                self.updateTitle();
                const visible_changed = changed & self.visibleBits();
                if (visible_changed != 0) try self.submitVisible(visible_changed);
            }
            if (sources.repeat) try self.repeatKey();
            if (sources.display_read and
                c.wl_display_dispatch(self.display) < 0) return error.WaylandDispatch;
            if (sources.display_write) {
                const resumed = c.wl_display_flush(self.display);
                if (resumed < 0 and std.posix.errno(resumed) != .AGAIN)
                    return error.WaylandFlush;
            }
        }
        if (self.failure) |failure| return failure;
    }

    fn submitVisible(self: *Loop, dirty_mask: u64) Error!void {
        var panes: [renderer.max_visible_panes]renderer.Pane = undefined;
        const pane_count = self.visiblePanes(&panes);
        var live: [workspace_model.max_panes]renderer.PaneId = undefined;
        var live_count: usize = 0;
        for (self.panes) |pane| if (pane.pane) |id| {
            live[live_count] = id;
            live_count += 1;
        };
        var dirty: [workspace_model.max_panes]*howl_control.Terminal = undefined;
        var dirty_count: usize = 0;
        for (panes[0..pane_count]) |pane| for (&self.panes, 0..) |*owned, index| {
            if (owned.terminal == pane.terminal and !owned.unavailable and
                dirty_mask & (@as(u64, 1) << @intCast(index)) != 0)
            {
                dirty[dirty_count] = pane.terminal;
                dirty_count += 1;
                break;
            }
        };
        if (self.render_generation == std.math.maxInt(u64)) return error.StaleGeneration;
        self.render_generation += 1;
        try self.render.?.submit(
            self.render_generation,
            self.size,
            live[0..live_count],
            panes[0..pane_count],
            dirty[0..dirty_count],
        );
    }

    fn resizeAll(self: *Loop) Error!void {
        const render = self.render orelse return;
        if (self.completed_generation != self.render_generation) return;
        if (self.pending_size.width < 2 or self.pending_size.height == 0 or
            self.pending_size.width > renderer.max_window_dimension or
            self.pending_size.height > renderer.max_window_dimension) return error.InvalidSize;
        var candidate = self.workspace.?;
        const grid = gridSize(self.pending_size, render.metrics());
        if (try candidate.resize(grid)) try self.applyWorkspaceGeometry(&candidate);
        self.workspace.? = candidate;
        self.size = self.pending_size;
        try self.submitVisible(self.visibleBits());
    }

    fn rollbackResize(self: *Loop, applied: [workspace_model.max_panes]bool, end: usize) bool {
        var index = end;
        while (index != 0) {
            index -= 1;
            if (!applied[index]) continue;
            const prior = self.panes[index].geometry;
            const restored = self.panes[index].terminal.?.resize(prior.cols, prior.rows) catch return false;
            if (restored.cols != prior.cols or restored.rows != prior.rows) return false;
        }
        return true;
    }

    fn applyWorkspaceGeometry(self: *Loop, candidate: *const workspace_model.Workspace) Error!void {
        var target: [workspace_model.max_panes]Geometry = undefined;
        var change: [workspace_model.max_panes]bool = @splat(false);
        for (self.panes, 0..) |pane, index| target[index] = pane.geometry;
        var tab_ids: [workspace_model.max_tabs]TabId = undefined;
        var layouts: [workspace_model.max_panes_per_tab]workspace_model.PaneLayout = undefined;
        for (candidate.tabOrder(&tab_ids)) |tab| for (try candidate.layout(tab, &layouts)) |layout| {
            const index = self.slotIndex(layout.pane) orelse return error.StalePane;
            if (self.panes[index].unavailable) continue;
            target[index] = .{ .cols = layout.rect.cols, .rows = layout.rect.rows };
            change[index] = !std.meta.eql(target[index], self.panes[index].geometry);
        };
        var applied: [workspace_model.max_panes]bool = @splat(false);
        for (&self.panes, 0..) |*pane, index| {
            if (!change[index]) continue;
            const result = pane.terminal.?.resize(target[index].cols, target[index].rows) catch |failure| {
                if (!self.rollbackResize(applied, index)) return error.ResizeTransactionFailed;
                return failure;
            };
            if (result.cols != target[index].cols or result.rows != target[index].rows) {
                const restored = pane.terminal.?.resize(pane.geometry.cols, pane.geometry.rows) catch
                    return error.ResizeTransactionFailed;
                if (restored.cols != pane.geometry.cols or restored.rows != pane.geometry.rows or
                    !self.rollbackResize(applied, index)) return error.ResizeTransactionFailed;
                return error.ResizeResultMismatch;
            }
            applied[index] = true;
        }
        for (&self.panes, target, change) |*pane, geometry, changed| {
            if (changed) pane.geometry = geometry;
        }
    }

    fn visiblePanes(self: *Loop, output: *[renderer.max_visible_panes]renderer.Pane) usize {
        const workspace = &self.workspace.?;
        var layouts: [workspace_model.max_panes_per_tab]workspace_model.PaneLayout = undefined;
        const visible = workspace.layout(workspace.activeTab(), &layouts) catch unreachable;
        const metrics = self.render.?.metrics();
        for (visible, output[0..visible.len]) |layout, *pane| {
            const owned = &self.panes[self.slotIndex(layout.pane) orelse unreachable];
            const x = @as(u32, layout.rect.col) * metrics.cell_width;
            const y = @as(u32, layout.rect.row) * metrics.cell_height;
            const right = if (layout.rect.col + layout.rect.cols == workspace.size.cols)
                self.size.width
            else
                @as(u32, layout.rect.col + layout.rect.cols) * metrics.cell_width;
            const bottom = if (layout.rect.row + layout.rect.rows == workspace.size.rows)
                self.size.height
            else
                @as(u32, layout.rect.row + layout.rect.rows) * metrics.cell_height;
            pane.* = .{
                .id = layout.pane,
                .terminal = owned.terminal.?,
                .x = x,
                .y = y,
                .width = right - x,
                .height = bottom - y,
                .focused = layout.focused,
                .terminal_available = !owned.unavailable,
            };
        }
        return visible.len;
    }

    fn updateTitle(self: *Loop) void {
        var order: [workspace_model.max_tabs]TabId = undefined;
        const tabs = self.workspace.?.tabOrder(&order);
        const active = self.workspace.?.activeTab();
        const ordinal = for (tabs, 1..) |tab, index| {
            if (tab == active) break index;
        } else unreachable;
        const title = std.fmt.bufPrintZ(&self.title, "Howl · tab {d}/{d}", .{ ordinal, tabs.len }) catch unreachable;
        c.xdg_toplevel_set_title(self.toplevel.?, title);
    }

    fn slotIndex(self: *const Loop, pane_id: PaneId) ?usize {
        for (self.panes, 0..) |pane, index| if (pane.pane == pane_id) return index;
        return null;
    }

    fn initPane(self: *Loop, pane_id: PaneId, geometry: Geometry) Error!void {
        const index = for (&self.panes, 0..) |*pane, candidate| {
            if (pane.pane == null) break candidate;
        } else return error.PaneLimit;
        const owned = &self.panes[index];
        owned.* = .{
            .pane = pane_id,
            .geometry = geometry,
            .wake = .{ .owner = self, .index = @intCast(index) },
        };
        errdefer {
            clearWakeBit(&self.wake_bits, @intCast(index));
            owned.* = .{};
        }
        owned.terminal = try howl_control.Terminal.init(self.allocator, self.io, .{
            .shell = "/bin/bash",
            .cols = geometry.cols,
            .rows = geometry.rows,
            .cell_pixels = .{
                .width = self.render.?.metrics().cell_width,
                .height = self.render.?.metrics().cell_height,
            },
        }, .{ .context = &owned.wake, .notify = terminalWake });
    }

    fn retirePane(self: *Loop, pane_id: PaneId) void {
        const index = self.slotIndex(pane_id) orelse return;
        const owned = &self.panes[index];
        owned.terminal.?.deinit();
        clearWakeBit(&self.wake_bits, @intCast(index));
        owned.* = .{};
    }

    fn paneGeometry(model: *const workspace_model.Workspace, pane_id: PaneId) ?Geometry {
        var tabs: [workspace_model.max_tabs]TabId = undefined;
        var layouts: [workspace_model.max_panes_per_tab]workspace_model.PaneLayout = undefined;
        for (model.tabOrder(&tabs)) |tab| for (model.layout(tab, &layouts) catch return null) |layout| {
            if (layout.pane == pane_id) return .{ .cols = layout.rect.cols, .rows = layout.rect.rows };
        };
        return null;
    }

    fn visibleBits(self: *const Loop) u64 {
        return visibleBitsFor(&self.workspace.?, &self.panes);
    }

    fn submitAndQuiesce(self: *Loop) Error!void {
        try self.submitVisible(self.visibleBits());
        try self.render.?.quiesce(self.render_generation);
        self.completed_generation = self.render_generation;
    }

    fn performHostAction(self: *Loop, action: HostAction) Error!void {
        switch (action) {
            .new_tab => {
                const created = try self.workspace.?.createTab("tab");
                self.initPane(created.pane, paneGeometry(&self.workspace.?, created.pane).?) catch |failure| {
                    var removed: [workspace_model.max_panes_per_tab]PaneId = undefined;
                    const rolled_back = self.workspace.?.closeTab(created.tab, &removed) catch unreachable;
                    std.debug.assert(rolled_back.len == 1 and rolled_back[0] == created.pane);
                    return failure;
                };
                if (!try self.workspace.?.switchTab(created.tab)) unreachable;
                self.updateTitle();
                try self.submitVisible(self.visibleBits());
            },
            .split_horizontal, .split_vertical => {
                var candidate = self.workspace.?;
                const tab = candidate.activeTab();
                const pane = try candidate.splitPane(
                    tab,
                    candidate.focusedPane(),
                    if (action == .split_horizontal) .horizontal else .vertical,
                );
                try self.initPane(pane, paneGeometry(&candidate, pane).?);
                self.applyWorkspaceGeometry(&candidate) catch |failure| {
                    self.retirePane(pane);
                    return failure;
                };
                self.workspace.? = candidate;
                try self.submitVisible(self.visibleBits());
            },
            .close_pane => {
                const pane = self.workspace.?.focusedPane();
                var candidate = self.workspace.?;
                const removed = candidate.closePane(candidate.activeTab(), pane) catch |failure| switch (failure) {
                    error.LastPane => return,
                    else => return failure,
                };
                std.debug.assert(removed == pane);
                try self.applyWorkspaceGeometry(&candidate);
                self.cancelPointer();
                self.workspace.? = candidate;
                try self.submitAndQuiesce();
                self.retirePane(pane);
            },
            .close_tab => {
                var retired: [workspace_model.max_panes_per_tab]PaneId = undefined;
                const removed = self.workspace.?.closeTab(
                    self.workspace.?.activeTab(),
                    &retired,
                ) catch |failure| switch (failure) {
                    error.LastTab => return,
                    else => return failure,
                };
                const count = removed.len;
                self.cancelPointer();
                try self.submitAndQuiesce();
                for (retired[0..count]) |pane| self.retirePane(pane);
                self.updateTitle();
            },
            .next_tab, .previous_tab => {
                var tabs: [workspace_model.max_tabs]TabId = undefined;
                const order = self.workspace.?.tabOrder(&tabs);
                if (order.len < 2) return;
                const active = self.workspace.?.activeTab();
                const index = for (order, 0..) |tab, candidate| {
                    if (tab == active) break candidate;
                } else unreachable;
                const target = if (action == .next_tab)
                    order[(index + 1) % order.len]
                else
                    order[if (index == 0) order.len - 1 else index - 1];
                if (!try self.workspace.?.switchTab(target)) unreachable;
                self.updateTitle();
                try self.submitVisible(self.visibleBits());
            },
            .focus_left, .focus_right, .focus_up, .focus_down => {
                const direction: workspace_model.Direction = switch (action) {
                    .focus_left => .left,
                    .focus_right => .right,
                    .focus_up => .up,
                    .focus_down => .down,
                    else => unreachable,
                };
                if (!self.workspace.?.focus(direction)) return;
                try self.submitVisible(self.visibleBits());
            },
            .resize_left, .resize_right, .resize_up, .resize_down => {
                const direction: workspace_model.Direction = switch (action) {
                    .resize_left => .left,
                    .resize_right => .right,
                    .resize_up => .up,
                    .resize_down => .down,
                    else => unreachable,
                };
                var candidate = self.workspace.?;
                if (!try candidate.resizePane(candidate.activeTab(), candidate.focusedPane(), direction, 1)) return;
                try self.applyWorkspaceGeometry(&candidate);
                self.workspace.? = candidate;
                try self.submitVisible(self.visibleBits());
            },
        }
    }

    fn key(self: *Loop, code: u32, state_value: u32) void {
        const action: @FieldType(@FieldType(howl_control.Input, "key"), "action") = switch (state_value) {
            c.WL_KEYBOARD_KEY_STATE_PRESSED => .press,
            c.WL_KEYBOARD_KEY_STATE_RELEASED => .release,
            else => return,
        };
        if (action == .release) {
            if (self.host_keys.release(code)) return;
            if (self.repeat.release(code)) self.armRepeat(null) catch |failure| {
                self.failure = failure;
            };
        } else {
            self.repeat.cancel();
            self.armRepeat(null) catch |failure| {
                self.failure = failure;
                return;
            };
        }
        const routed = self.routeKey(code, action);
        if (action != .press or !routed or self.failure != null) return;
        const keymap = self.xkb_keymap orelse return;
        const delay = self.repeat.press(code, c.xkb_keymap_key_repeats(keymap, code + 8) == 1);
        self.armRepeat(delay) catch |failure| {
            self.failure = failure;
        };
    }

    fn routeKey(
        self: *Loop,
        code: u32,
        action: @FieldType(@FieldType(howl_control.Input, "key"), "action"),
    ) bool {
        const state = self.xkb_state orelse return false;
        const symbol = c.xkb_state_key_get_one_sym(state, code + 8);
        var bytes: [64]u8 = undefined;
        const count = c.xkb_state_key_get_utf8(state, code + 8, &bytes, bytes.len);
        if (count < 0 or count >= bytes.len) return false;
        const text = if (action == .release) bytes[0..0] else bytes[0..@intCast(count)];
        const mods: KeyModifiers = .{
            .shift = modifierActive(state, c.XKB_MOD_NAME_SHIFT),
            .alt = modifierActive(state, c.XKB_MOD_NAME_ALT),
            .control = modifierActive(state, c.XKB_MOD_NAME_CTRL),
            .super = modifierActive(state, c.XKB_MOD_NAME_LOGO),
            .caps_lock = modifierActive(state, c.XKB_MOD_NAME_CAPS),
            .num_lock = modifierActive(state, c.XKB_MOD_NAME_NUM),
        };
        if (action == .press) {
            if (hostAction(symbol, mods)) |host| {
                if (!self.host_keys.capture(code)) {
                    self.failure = error.HostKeyLimit;
                    return false;
                }
                self.performHostAction(host) catch |failure| {
                    self.failure = failure;
                };
                return false;
            }
        }
        const named: ?howl_vt.Terminal.NamedKey = switch (symbol) {
            c.XKB_KEY_Return => .enter,
            c.XKB_KEY_Tab => .tab,
            c.XKB_KEY_BackSpace => .backspace,
            c.XKB_KEY_Escape => .escape,
            c.XKB_KEY_Up => .up,
            c.XKB_KEY_Down => .down,
            c.XKB_KEY_Left => .left,
            c.XKB_KEY_Right => .right,
            c.XKB_KEY_Insert => .insert,
            c.XKB_KEY_Delete => .delete,
            c.XKB_KEY_Home => .home,
            c.XKB_KEY_End => .end,
            c.XKB_KEY_Page_Up => .page_up,
            c.XKB_KEY_Page_Down => .page_down,
            c.XKB_KEY_F1 => .f1,
            c.XKB_KEY_F2 => .f2,
            c.XKB_KEY_F3 => .f3,
            c.XKB_KEY_F4 => .f4,
            c.XKB_KEY_F5 => .f5,
            c.XKB_KEY_F6 => .f6,
            c.XKB_KEY_F7 => .f7,
            c.XKB_KEY_F8 => .f8,
            c.XKB_KEY_F9 => .f9,
            c.XKB_KEY_F10 => .f10,
            c.XKB_KEY_F11 => .f11,
            c.XKB_KEY_F12 => .f12,
            else => null,
        };
        const input: howl_control.Input = if (named) |value|
            .{ .key = .{ .key = .{ .named = value }, .mods = mods, .action = action, .text = text } }
        else unicode: {
            const scalar = c.xkb_keysym_to_utf32(symbol);
            if (scalar == 0 or scalar > std.math.maxInt(u21)) return false;
            const codepoint: u21 = @intCast(scalar);
            if (!std.unicode.utf8ValidCodepoint(codepoint)) return false;
            break :unicode .{ .key = .{
                .key = howl_vt.Terminal.Key.initUnicode(codepoint) catch return false,
                .mods = mods,
                .action = action,
                .text = text,
            } };
        };
        const focused = self.slotIndex(self.workspace.?.focusedPane()) orelse return false;
        if (self.panes[focused].unavailable) return false;
        const result = self.panes[focused].terminal.?.send(&.{.{ .input = input }}) catch |failure| {
            self.failure = failure;
            return false;
        };
        switch (result.outcome) {
            .complete => {},
            .incomplete, .rejected => self.failure = error.InputIncomplete,
        }
        return self.failure == null;
    }

    fn repeatKey(self: *Loop) Error!void {
        var expirations: u64 = 0;
        while (true) {
            const count = c.read(self.repeat_fd, &expirations, @sizeOf(u64));
            if (count == @sizeOf(u64)) break;
            if (count < 0 and std.posix.errno(count) == .INTR) continue;
            return error.KeyboardRepeat;
        }
        if (expirations == 0) return error.KeyboardRepeat;
        const firing = self.repeat.fire() orelse return;
        // Delayed dispatch coalesces timer expirations into one repeat so a
        // stalled window loop cannot flood the bounded terminal admission.
        if (self.routeKey(firing.key, .repeat)) try self.armRepeat(firing.next_ns);
    }

    fn armRepeat(self: *Loop, duration_ns: ?u64) error{KeyboardRepeat}!void {
        try setRepeatTimer(self.repeat_fd, duration_ns);
    }

    fn pointerMotion(self: *Loop, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) void {
        if (surface_x < 0 or surface_y < 0) {
            self.pointer_state.position = null;
            return;
        }
        self.pointer_state.position = .{
            .x = @intCast(c.wl_fixed_to_int(surface_x)),
            .y = @intCast(c.wl_fixed_to_int(surface_y)),
        };
        if (self.pointerMoveTarget()) |target| if (self.sendMouse(
            target,
            .move,
            .none,
            self.pointer_state.buttons_down,
        )) std.debug.assert(self.pointer_state.move(target));
    }

    fn pointerButton(self: *Loop, button_code: u32, state_value: u32) void {
        const button: MouseButton = switch (button_code) {
            c.BTN_LEFT => .left,
            c.BTN_MIDDLE => .middle,
            c.BTN_RIGHT => .right,
            else => return,
        };
        const index = mouseButtonIndex(button).?;
        switch (state_value) {
            c.WL_POINTER_BUTTON_STATE_PRESSED => {
                const position = self.pointer_state.position orelse return;
                const target = self.resolvePointer(position.x, position.y, false) orelse return;
                const focused = self.workspace.?.focusPane(target.pane) catch return;
                if (focused) self.submitVisible(self.visibleBits()) catch |failure| {
                    retainFirstFailure(&self.failure, failure);
                    return;
                };
                const transition = self.pointer_state.preparePress(index, target) orelse return;
                if (!self.sendMouse(target, .press, button, transition.buttons_down)) return;
                self.pointer_state.commitPress(transition);
            },
            c.WL_POINTER_BUTTON_STATE_RELEASED => {
                const transition = self.pointer_state.prepareRelease(index) orelse return;
                if (!self.sendMouse(
                    transition.target,
                    .release,
                    button,
                    transition.buttons_down,
                )) return;
                self.pointer_state.commitRelease(transition);
            },
            else => {},
        }
    }

    fn pointerWheel(self: *Loop, discrete: i32) void {
        if (discrete == 0) return;
        const magnitude: u32 = if (discrete < 0)
            @intCast(-@as(i64, discrete))
        else
            @intCast(discrete);
        if (magnitude > max_wheel_steps) {
            self.failure = error.Pointer;
            return;
        }
        const target = self.pointerTarget() orelse return;
        var events: [max_wheel_steps]howl_control.BatchEvent = undefined;
        for (events[0..magnitude]) |*event| event.* = .{ .input = .{ .mouse = .{
            .kind = .wheel,
            .button = if (discrete < 0) .wheel_up else .wheel_down,
            .row = target.row,
            .col = target.col,
            .pixel_x = target.pixel_x,
            .pixel_y = target.pixel_y,
            .mod = self.mouseModifiers(),
            .buttons_down = self.pointer_state.buttons_down,
        } } };
        if (!self.sendBatch(target.pane, events[0..magnitude])) return;
    }

    fn pointerTarget(self: *Loop) ?PointerTarget {
        const position = self.pointer_state.position orelse return null;
        return self.resolvePointer(position.x, position.y, true);
    }

    fn resolvePointer(self: *Loop, x: u32, y: u32, focused_only: bool) ?PointerTarget {
        var panes: [renderer.max_visible_panes]renderer.Pane = undefined;
        const visible = self.visiblePanes(&panes);
        const focused = self.workspace.?.focusedPane();
        for (panes[0..visible]) |pane| {
            if ((focused_only and pane.id != focused) or !pane.terminal_available or
                x < pane.x or x >= pane.x + pane.width or y < pane.y or y >= pane.y + pane.height) continue;
            const index = self.slotIndex(pane.id) orelse return null;
            const local_x = x - pane.x;
            const local_y = y - pane.y;
            const metrics = self.render.?.metrics();
            const geometry = self.panes[index].geometry;
            if (local_x >= @as(u32, geometry.cols) * metrics.cell_width or
                local_y >= @as(u32, geometry.rows) * metrics.cell_height) return null;
            return .{
                .pane = pane.id,
                .row = @intCast(local_y / metrics.cell_height),
                .col = @intCast(local_x / metrics.cell_width),
                .pixel_x = local_x,
                .pixel_y = local_y,
            };
        }
        return null;
    }

    fn pointerMoveTarget(self: *Loop) ?PointerTarget {
        const target = self.pointerTarget() orelse return null;
        for (self.pointer_state.pressed) |pressed| if (pressed) |value|
            if (value.pane != target.pane) return null;
        return target;
    }

    fn cancelPointer(self: *Loop) void {
        // Teardown commits each release only after admission and stops at the
        // first failure, preserving retained state and the prior loop failure.
        for (0..self.pointer_state.pressed.len) |index| {
            const transition = self.pointer_state.prepareRelease(index) orelse continue;
            const button: MouseButton = switch (index) {
                0 => .left,
                1 => .middle,
                2 => .right,
                else => unreachable,
            };
            if (!self.sendMouse(
                transition.target,
                .release,
                button,
                transition.buttons_down,
            )) break;
            self.pointer_state.commitRelease(transition);
        }
        self.pointer_state.position = null;
    }

    fn sendMouse(
        self: *Loop,
        target: PointerTarget,
        kind: MouseKind,
        button: MouseButton,
        buttons_down: u8,
    ) bool {
        return self.sendBatch(target.pane, &.{.{ .input = .{ .mouse = .{
            .kind = kind,
            .button = button,
            .row = target.row,
            .col = target.col,
            .pixel_x = target.pixel_x,
            .pixel_y = target.pixel_y,
            .mod = self.mouseModifiers(),
            .buttons_down = buttons_down,
        } } }});
    }

    fn mouseModifiers(self: *Loop) @FieldType(MouseInput, "mod") {
        const state = self.xkb_state orelse return .{};
        return .{
            .shift = modifierActive(state, c.XKB_MOD_NAME_SHIFT),
            .alt = modifierActive(state, c.XKB_MOD_NAME_ALT),
            .control = modifierActive(state, c.XKB_MOD_NAME_CTRL),
            .super = modifierActive(state, c.XKB_MOD_NAME_LOGO),
            .caps_lock = modifierActive(state, c.XKB_MOD_NAME_CAPS),
            .num_lock = modifierActive(state, c.XKB_MOD_NAME_NUM),
        };
    }

    fn sendBatch(self: *Loop, pane_id: PaneId, events: []const howl_control.BatchEvent) bool {
        const index = self.slotIndex(pane_id) orelse return false;
        if (self.panes[index].unavailable) return false;
        const result = self.panes[index].terminal.?.send(events) catch |failure| {
            retainFirstFailure(&self.failure, failure);
            return false;
        };
        switch (result.outcome) {
            .complete => return true,
            .incomplete, .rejected => {
                retainFirstFailure(&self.failure, error.InputIncomplete);
                return false;
            },
        }
    }

    fn deinit(self: *Loop) Error!void {
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| if (self.failure == null) {
            self.failure = failure;
        };
        self.cancelPointer();
        const interaction_failure = self.failure;
        if (self.render) |render| render.deinit() catch |failure| {
            self.deinitTerminals();
            self.destroyWayland();
            const allocator = self.allocator;
            allocator.destroy(self);
            if (interaction_failure) |prior| if (prior != failure)
                @panic("window interaction and render cleanup failed distinctly");
            return failure;
        };
        self.deinitTerminals();
        self.destroyWayland();
        const allocator = self.allocator;
        allocator.destroy(self);
        if (interaction_failure) |failure| return failure;
    }

    fn deinitTerminals(self: *Loop) void {
        for (&self.panes) |*pane| if (pane.terminal) |terminal| {
            terminal.deinit();
            pane.* = .{};
        };
        if (self.workspace) |*workspace| workspace.deinit();
        self.workspace = null;
    }

    fn destroyWayland(self: *Loop) void {
        self.destroyKeyboard();
        if (self.pointer) |value| c.wl_pointer_destroy(value);
        self.pointer = null;
        if (self.seat) |value| c.wl_seat_destroy(value);
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.wm_base) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
        closeOwned(self.repeat_fd);
        closeOwned(self.terminal_signal);
    }

    fn destroyKeyboard(self: *Loop) void {
        self.host_keys.clear();
        if (self.keyboard) |value| c.wl_keyboard_destroy(value);
        self.keyboard = null;
        self.clearKeymap();
    }

    fn clearKeymap(self: *Loop) void {
        if (self.xkb_state) |value| c.xkb_state_unref(value);
        if (self.xkb_keymap) |value| c.xkb_keymap_unref(value);
        if (self.xkb_context) |value| c.xkb_context_unref(value);
        self.xkb_state = null;
        self.xkb_keymap = null;
        self.xkb_context = null;
    }
};

fn visibleBitsFor(
    model: *const workspace_model.Workspace,
    panes: *const [workspace_model.max_panes]PaneOwner,
) u64 {
    var layouts: [workspace_model.max_panes_per_tab]workspace_model.PaneLayout = undefined;
    const visible = model.layout(model.activeTab(), &layouts) catch unreachable;
    var bits: u64 = 0;
    for (visible) |layout| for (panes, 0..) |pane, index| {
        if (pane.pane == layout.pane) {
            bits |= @as(u64, 1) << @intCast(index);
            break;
        }
    };
    return bits;
}

/// Runs the native Wayland window until compositor close or exact failure.
pub fn run(allocator: std.mem.Allocator, io: std.Io, font_paths: []const []const u8) Error!void {
    const owner = try Loop.init(allocator, io, font_paths);
    var primary_failure: ?Error = null;
    owner.run() catch |failure| {
        primary_failure = failure;
    };
    owner.deinit() catch |cleanup_failure| {
        if (primary_failure) |failure| if (failure != cleanup_failure)
            @panic("window cleanup failed after a distinct runtime failure");
        return cleanup_failure;
    };
    if (primary_failure) |failure| return failure;
}

fn terminalWake(context: ?*anyopaque) void {
    const wake: *WakeContext = @ptrCast(@alignCast(context.?));
    const self: *Loop = @ptrCast(@alignCast(wake.owner.?));
    const bit = @as(u64, 1) << wake.index;
    if (!markTerminalWake(&self.wake_bits, bit)) return;
    const value: u64 = 1;
    const count = c.write(self.terminal_signal, &value, @sizeOf(u64));
    if (count != @sizeOf(u64) and !(count < 0 and std.posix.errno(count) == .AGAIN))
        @panic("terminal wake eventfd write failed");
}

fn markTerminalWake(bits: *std.atomic.Value(u64), bit: u64) bool {
    std.debug.assert(bit != 0 and bit & (bit - 1) == 0);
    return bits.fetchOr(bit, .release) & bit == 0;
}

fn clearWakeBit(bits: *std.atomic.Value(u64), index: TerminalIndex) void {
    const bit = @as(u64, 1) << index;
    var current = bits.load(.acquire);
    while (current & bit != 0) {
        current = bits.cmpxchgWeak(current, current & ~bit, .acq_rel, .acquire) orelse return;
    }
}

const Geometry = struct { cols: u16, rows: u16 };

fn gridSize(size: renderer.Size, metrics: @import("howl_text").Metrics) workspace_model.Size {
    return .{
        .cols = @intCast(@min(workspace_model.max_cols, @max(1, size.width / metrics.cell_width))),
        .rows = @intCast(@min(workspace_model.max_rows, @max(1, size.height / metrics.cell_height))),
    };
}

fn mouseButtonIndex(button: MouseButton) ?usize {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        else => null,
    };
}

fn setRepeatTimer(fd: c_int, duration_ns: ?u64) error{KeyboardRepeat}!void {
    var timer: c.struct_itimerspec = std.mem.zeroes(c.struct_itimerspec);
    if (c.timerfd_settime(fd, 0, &timer, null) != 0) return error.KeyboardRepeat;
    while (true) {
        var expirations: u64 = 0;
        const count = c.read(fd, &expirations, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) break;
        return error.KeyboardRepeat;
    }
    if (duration_ns) |duration| {
        timer.it_value.tv_sec = @intCast(duration / std.time.ns_per_s);
        timer.it_value.tv_nsec = @intCast(duration % std.time.ns_per_s);
        if (c.timerfd_settime(fd, 0, &timer, null) != 0) return error.KeyboardRepeat;
    }
}

fn drainEvent(fd: c_int) Error!void {
    while (true) {
        var value: u64 = 0;
        const count = c.read(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) return;
        return error.TerminalSignal;
    }
}

fn loop(data: ?*anyopaque) *Loop {
    return @ptrCast(@alignCast(data.?));
}

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self = loop(data);
    const value = std.mem.span(interface);
    if (std.mem.eql(u8, value, "wl_compositor") and self.compositor == null)
        self.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, @min(version, 4)))
    else if (std.mem.eql(u8, value, "xdg_wm_base") and self.wm_base == null) {
        self.wm_base = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, 1));
        if (c.xdg_wm_base_add_listener(self.wm_base, &wm_base_listener, self) != 0)
            self.failure = error.WaylandProtocol;
    } else if (std.mem.eql(u8, value, "wl_seat") and self.seat == null) {
        self.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 7)));
        if (c.wl_seat_add_listener(self.seat, &seat_listener, self) != 0)
            self.failure = error.WaylandProtocol;
    }
}

fn registryRemove(_: ?*anyopaque, _: ?*c.struct_wl_registry, _: u32) callconv(.c) void {}
const registry_listener = c.struct_wl_registry_listener{ .global = registryGlobal, .global_remove = registryRemove };

fn shellPing(_: ?*anyopaque, base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.c) void {
    c.xdg_wm_base_pong(base, serial);
}
const wm_base_listener = c.struct_xdg_wm_base_listener{ .ping = shellPing };

fn surfaceConfigure(data: ?*anyopaque, surface: ?*c.struct_xdg_surface, serial: u32) callconv(.c) void {
    const self = loop(data);
    c.xdg_surface_ack_configure(surface, serial);
    self.configured = true;
}
const xdg_surface_listener = c.struct_xdg_surface_listener{ .configure = surfaceConfigure };

fn toplevelConfigure(
    data: ?*anyopaque,
    _: ?*c.struct_xdg_toplevel,
    width: i32,
    height: i32,
    _: ?*c.struct_wl_array,
) callconv(.c) void {
    if (width <= 0 or height <= 0) return;
    const self = loop(data);
    self.pending_size = .{ .width = @intCast(width), .height = @intCast(height) };
}
fn toplevelClose(data: ?*anyopaque, _: ?*c.struct_xdg_toplevel) callconv(.c) void {
    requestClose(&loop(data).closed);
}
fn requestClose(closed: *bool) void {
    closed.* = true;
}
fn configureBounds(_: ?*anyopaque, _: ?*c.struct_xdg_toplevel, _: i32, _: i32) callconv(.c) void {}
fn wmCapabilities(_: ?*anyopaque, _: ?*c.struct_xdg_toplevel, _: ?*c.struct_wl_array) callconv(.c) void {}
const toplevel_listener = c.struct_xdg_toplevel_listener{
    .configure = toplevelConfigure,
    .close = toplevelClose,
    .configure_bounds = configureBounds,
    .wm_capabilities = wmCapabilities,
};

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.struct_wl_seat, capabilities: u32) callconv(.c) void {
    const self = loop(data);
    if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0 and self.keyboard == null) {
        self.keyboard = c.wl_seat_get_keyboard(seat);
        if (c.wl_keyboard_add_listener(self.keyboard, &keyboard_listener, self) != 0)
            self.failure = error.KeyboardContext;
    } else if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD == 0) {
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| {
            self.failure = failure;
        };
        self.destroyKeyboard();
    }
    if (capabilities & c.WL_SEAT_CAPABILITY_POINTER != 0 and self.pointer == null) {
        self.pointer = c.wl_seat_get_pointer(seat);
        if (self.pointer == null or
            c.wl_pointer_add_listener(self.pointer, &pointer_listener, self) != 0)
            self.failure = error.Pointer;
    } else if (capabilities & c.WL_SEAT_CAPABILITY_POINTER == 0) {
        self.cancelPointer();
        if (self.pointer) |pointer| c.wl_pointer_destroy(pointer);
        self.pointer = null;
    }
}
fn seatName(_: ?*anyopaque, _: ?*c.struct_wl_seat, _: [*c]const u8) callconv(.c) void {}
const seat_listener = c.struct_wl_seat_listener{ .capabilities = seatCapabilities, .name = seatName };

fn keyboardKeymap(data: ?*anyopaque, _: ?*c.struct_wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    const self = loop(data);
    defer if (!closeCallback(fd)) {
        self.failure = error.KeyboardMap;
    };
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 or size == 0) {
        self.failure = error.KeyboardMap;
        return;
    }
    const bytes = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (bytes == c.MAP_FAILED) {
        self.failure = error.KeyboardMap;
        return;
    }
    defer if (c.munmap(bytes, size) != 0) {
        self.failure = error.KeyboardMap;
    };
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse {
        self.failure = error.KeyboardContext;
        return;
    };
    const keymap = c.xkb_keymap_new_from_string(
        context,
        @ptrCast(bytes),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse {
        c.xkb_context_unref(context);
        self.failure = error.KeyboardMap;
        return;
    };
    const state = c.xkb_state_new(keymap) orelse {
        c.xkb_keymap_unref(keymap);
        c.xkb_context_unref(context);
        self.failure = error.KeyboardState;
        return;
    };
    self.repeat.cancel();
    self.host_keys.clear();
    self.armRepeat(null) catch |failure| {
        c.xkb_state_unref(state);
        c.xkb_keymap_unref(keymap);
        c.xkb_context_unref(context);
        self.failure = failure;
        return;
    };
    self.clearKeymap();
    self.xkb_context = context;
    self.xkb_keymap = keymap;
    self.xkb_state = state;
}
fn keyboardEnter(
    _: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: ?*c.struct_wl_surface,
    _: ?*c.struct_wl_array,
) callconv(.c) void {}
fn keyboardLeave(data: ?*anyopaque, _: ?*c.struct_wl_keyboard, _: u32, _: ?*c.struct_wl_surface) callconv(.c) void {
    const self = loop(data);
    self.repeat.cancel();
    self.host_keys.clear();
    self.armRepeat(null) catch |failure| {
        self.failure = failure;
    };
}
fn keyboardKey(data: ?*anyopaque, _: ?*c.struct_wl_keyboard, _: u32, _: u32, code: u32, state: u32) callconv(.c) void {
    loop(data).key(code, state);
}
fn keyboardModifiers(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    depressed: u32,
    latched: u32,
    locked: u32,
    group: u32,
) callconv(.c) void {
    if (loop(data).xkb_state) |state| {
        const changed = c.xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group);
        const known: @TypeOf(changed) = c.XKB_STATE_MODS_DEPRESSED | c.XKB_STATE_MODS_LATCHED |
            c.XKB_STATE_MODS_LOCKED | c.XKB_STATE_MODS_EFFECTIVE |
            c.XKB_STATE_LAYOUT_DEPRESSED | c.XKB_STATE_LAYOUT_LATCHED |
            c.XKB_STATE_LAYOUT_LOCKED | c.XKB_STATE_LAYOUT_EFFECTIVE | c.XKB_STATE_LEDS;
        if (changed & ~known != 0) loop(data).failure = error.KeyboardState;
    }
}
fn keyboardRepeat(data: ?*anyopaque, _: ?*c.struct_wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    const self = loop(data);
    self.repeat.configure(rate, delay) catch {
        self.repeat.cancel();
        self.failure = error.KeyboardRepeat;
        return;
    };
    self.armRepeat(null) catch |failure| {
        self.failure = failure;
    };
}
const keyboard_listener = c.struct_wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeat,
};

fn pointerEnter(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    surface: ?*c.struct_wl_surface,
    x: c.wl_fixed_t,
    y: c.wl_fixed_t,
) callconv(.c) void {
    const self = loop(data);
    if (surface != self.surface) {
        self.pointer_state.position = null;
        return;
    }
    self.pointerMotion(x, y);
}

fn pointerLeave(data: ?*anyopaque, _: ?*c.struct_wl_pointer, _: u32, _: ?*c.struct_wl_surface) callconv(.c) void {
    loop(data).cancelPointer();
}

fn pointerMotion(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    x: c.wl_fixed_t,
    y: c.wl_fixed_t,
) callconv(.c) void {
    loop(data).pointerMotion(x, y);
}

fn pointerButton(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: u32,
    button: u32,
    state: u32,
) callconv(.c) void {
    loop(data).pointerButton(button, state);
}

fn pointerAxis(_: ?*anyopaque, _: ?*c.struct_wl_pointer, _: u32, _: u32, _: c.wl_fixed_t) callconv(.c) void {}
fn pointerFrame(_: ?*anyopaque, _: ?*c.struct_wl_pointer) callconv(.c) void {}
fn pointerAxisSource(_: ?*anyopaque, _: ?*c.struct_wl_pointer, _: u32) callconv(.c) void {}
fn pointerAxisStop(_: ?*anyopaque, _: ?*c.struct_wl_pointer, _: u32, _: u32) callconv(.c) void {}
fn pointerAxisDiscrete(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    axis: u32,
    discrete: i32,
) callconv(.c) void {
    if (axis == c.WL_POINTER_AXIS_VERTICAL_SCROLL) loop(data).pointerWheel(discrete);
}

const pointer_listener = c.struct_wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
    .frame = pointerFrame,
    .axis_source = pointerAxisSource,
    .axis_stop = pointerAxisStop,
    .axis_discrete = pointerAxisDiscrete,
    .axis_value120 = null,
    .axis_relative_direction = null,
};

fn closeOwned(fd: c_int) void {
    const result = c.close(fd);
    if (result != 0 and std.posix.errno(result) != .INTR)
        @panic("owned host descriptor close failed");
}

fn closeCallback(fd: c_int) bool {
    const result = c.close(fd);
    return result == 0 or std.posix.errno(result) == .INTR;
}

fn modifierActive(state: *c.struct_xkb_state, name: [*c]const u8) bool {
    return c.xkb_state_mod_name_is_active(state, name, c.XKB_STATE_MODS_EFFECTIVE) == 1;
}

fn retainFirstFailure(current: *?Error, failure: Error) void {
    if (current.* == null) current.* = failure;
}

test "pixel geometry admits at least one bounded cell" {
    const size = renderer.Size{ .width = 1, .height = 1 };
    try std.testing.expectEqual(@as(u32, 1), @max(1, size.width / 8));
    try std.testing.expectEqual(@as(u32, 1), @max(1, size.height / 16));
}

test "keyboard repeat replaces and cancels one bounded physical key" {
    var repeat = Repeat{};
    try repeat.configure(25, 400);
    try std.testing.expectEqual(@as(?u64, 400 * std.time.ns_per_ms), repeat.press(30, true));
    try std.testing.expectEqual(@as(u32, 30), repeat.fire().?.key);
    try std.testing.expectEqual(@as(u64, 40 * std.time.ns_per_ms), repeat.fire().?.next_ns);
    try std.testing.expectEqual(@as(?u64, 400 * std.time.ns_per_ms), repeat.press(31, true));
    try std.testing.expect(!repeat.release(30));
    try std.testing.expectEqual(@as(u32, 31), repeat.fire().?.key);
    try std.testing.expect(repeat.release(31));
    try std.testing.expectEqual(null, repeat.fire());

    try repeat.configure(0, 0);
    try std.testing.expectEqual(null, repeat.press(32, true));
    try std.testing.expectError(error.InvalidRepeat, repeat.configure(-1, 0));
}

test "host chords capture sixteen concurrent physical releases exactly" {
    var captures = HostKeys{};
    for (10..26) |code| try std.testing.expect(captures.capture(@intCast(code)));
    try std.testing.expect(captures.capture(10));
    try std.testing.expectEqual(@as(u8, 16), captures.count);
    try std.testing.expect(!captures.capture(26));
    try std.testing.expect(captures.release(11));
    try std.testing.expect(!captures.release(11));
    for (10..26) |code| if (code != 11) try std.testing.expect(captures.release(@intCast(code)));
    try std.testing.expectEqual(@as(u8, 0), captures.count);

    try std.testing.expect(captures.capture(20));
    captures.clear();
    try std.testing.expect(!captures.release(20));
}

test "host actions require exact non-lock modifiers" {
    const Case = struct { symbol: u32, mods: KeyModifiers, action: HostAction };
    const control_shift: KeyModifiers = .{ .control = true, .shift = true };
    const control: KeyModifiers = .{ .control = true };
    const alt: KeyModifiers = .{ .alt = true };
    const cases = [_]Case{
        .{ .symbol = c.XKB_KEY_t, .mods = control_shift, .action = .new_tab },
        .{ .symbol = c.XKB_KEY_T, .mods = control_shift, .action = .new_tab },
        .{ .symbol = c.XKB_KEY_Return, .mods = control_shift, .action = .split_horizontal },
        .{ .symbol = c.XKB_KEY_backslash, .mods = control_shift, .action = .split_vertical },
        .{ .symbol = c.XKB_KEY_bar, .mods = control_shift, .action = .split_vertical },
        .{ .symbol = c.XKB_KEY_w, .mods = control_shift, .action = .close_pane },
        .{ .symbol = c.XKB_KEY_W, .mods = control_shift, .action = .close_pane },
        .{ .symbol = c.XKB_KEY_q, .mods = control_shift, .action = .close_tab },
        .{ .symbol = c.XKB_KEY_Q, .mods = control_shift, .action = .close_tab },
        .{ .symbol = c.XKB_KEY_Left, .mods = control_shift, .action = .resize_left },
        .{ .symbol = c.XKB_KEY_Right, .mods = control_shift, .action = .resize_right },
        .{ .symbol = c.XKB_KEY_Up, .mods = control_shift, .action = .resize_up },
        .{ .symbol = c.XKB_KEY_Down, .mods = control_shift, .action = .resize_down },
        .{ .symbol = c.XKB_KEY_Tab, .mods = control_shift, .action = .previous_tab },
        .{ .symbol = c.XKB_KEY_ISO_Left_Tab, .mods = control_shift, .action = .previous_tab },
        .{ .symbol = c.XKB_KEY_Tab, .mods = control, .action = .next_tab },
        .{ .symbol = c.XKB_KEY_Left, .mods = alt, .action = .focus_left },
        .{ .symbol = c.XKB_KEY_Right, .mods = alt, .action = .focus_right },
        .{ .symbol = c.XKB_KEY_Up, .mods = alt, .action = .focus_up },
        .{ .symbol = c.XKB_KEY_Down, .mods = alt, .action = .focus_down },
    };

    for (cases) |case| {
        try std.testing.expectEqual(@as(?HostAction, case.action), hostAction(case.symbol, case.mods));

        var lock_state = case.mods;
        lock_state.caps_lock = true;
        lock_state.num_lock = true;
        try std.testing.expectEqual(@as(?HostAction, case.action), hostAction(case.symbol, lock_state));

        if (!case.mods.shift and !(case.symbol == c.XKB_KEY_Tab and case.mods.control)) {
            var augmented = case.mods;
            augmented.shift = true;
            try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
        }
        if (!case.mods.alt) {
            var augmented = case.mods;
            augmented.alt = true;
            try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
        }
        if (!case.mods.control) {
            var augmented = case.mods;
            augmented.control = true;
            try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
        }
        var augmented = case.mods;
        augmented.super = true;
        try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
        augmented = case.mods;
        augmented.hyper = true;
        try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
        augmented = case.mods;
        augmented.meta = true;
        try std.testing.expectEqual(@as(?HostAction, null), hostAction(case.symbol, augmented));
    }
    try std.testing.expectEqual(@as(?HostAction, null), hostAction(c.XKB_KEY_Escape, control_shift));
}

test "one poll result preserves every simultaneous ready source" {
    const input = [_]std.posix.pollfd{
        .{ .fd = 1, .events = 0, .revents = std.posix.POLL.IN | std.posix.POLL.OUT },
        .{ .fd = 2, .events = 0, .revents = std.posix.POLL.IN },
        .{ .fd = 3, .events = 0, .revents = std.posix.POLL.IN },
        .{ .fd = 4, .events = 0, .revents = std.posix.POLL.IN },
    };
    const ready = Ready.from(input);
    try std.testing.expect(ready.display_read);
    try std.testing.expect(ready.display_write);
    try std.testing.expect(ready.terminal);
    try std.testing.expect(ready.render);
    try std.testing.expect(ready.repeat);
}

test "terminal output wake coalesces until the window drains its exact bit" {
    var bits: std.atomic.Value(u64) = .init(0);
    try std.testing.expect(markTerminalWake(&bits, 0b001));
    try std.testing.expect(!markTerminalWake(&bits, 0b001));
    try std.testing.expect(markTerminalWake(&bits, 0b100));
    try std.testing.expectEqual(@as(u64, 0b101), bits.swap(0, .acq_rel));
    try std.testing.expect(markTerminalWake(&bits, 0b001));
}

test "visible wake routing follows stable pane identity through tab churn" {
    var model = try workspace_model.Workspace.init(
        std.testing.allocator,
        @enumFromInt(1),
        "one",
        .{ .cols = 80, .rows = 24 },
    );
    defer model.deinit();
    const first_tab = model.activeTab();
    const first = model.focusedPane();
    const second = try model.splitPane(first_tab, first, .horizontal);
    const other = try model.createTab("two");
    var panes: [workspace_model.max_panes]PaneOwner = @splat(.{});
    panes[5].pane = first;
    panes[17].pane = second;
    panes[63].pane = other.pane;
    try std.testing.expectEqual((@as(u64, 1) << 5) | (@as(u64, 1) << 17), visibleBitsFor(&model, &panes));
    try std.testing.expect(try model.reorderTab(first_tab, 1));
    try std.testing.expectEqual((@as(u64, 1) << 5) | (@as(u64, 1) << 17), visibleBitsFor(&model, &panes));
    try std.testing.expect(try model.switchTab(other.tab));
    try std.testing.expectEqual(@as(u64, 1) << 63, visibleBitsFor(&model, &panes));

    var retired: [workspace_model.max_panes_per_tab]PaneId = undefined;
    const removed = try model.closeTab(other.tab, &retired);
    try std.testing.expectEqualSlices(PaneId, &.{other.pane}, removed);
    panes[63] = .{};
    try std.testing.expectEqual((@as(u64, 1) << 5) | (@as(u64, 1) << 17), visibleBitsFor(&model, &panes));
}

test "pane retirement clears stale wake ownership before slot reuse" {
    const terminal = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 2, .rows = 1 },
        .{},
    );
    var owner: Loop = undefined;
    owner.panes = @splat(.{});
    owner.wake_bits = .init(0);
    const pane: PaneId = @enumFromInt(9);
    owner.panes[63] = .{ .pane = pane, .terminal = terminal, .geometry = .{ .cols = 2, .rows = 1 } };
    try std.testing.expect(markTerminalWake(&owner.wake_bits, @as(u64, 1) << 63));
    owner.retirePane(pane);
    try std.testing.expectEqual(@as(u64, 0), owner.wake_bits.load(.acquire));
    try std.testing.expectEqual(null, owner.panes[63].pane);
    owner.panes[63].pane = @enumFromInt(10);
    try std.testing.expectEqual(@as(u64, 0), owner.wake_bits.load(.acquire));
}

test "terminal construction allocation failure leaves its pane slot reusable" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var render: renderer.Render = undefined;
    render.metrics_value = .{
        .cell_width = 10,
        .cell_height = 20,
        .baseline = 15,
        .underline_y = 17,
        .underline_height = 1,
        .strike_y = 10,
        .strike_height = 1,
    };
    var owner: Loop = undefined;
    owner.allocator = failing.allocator();
    owner.io = std.testing.io;
    owner.panes = @splat(.{});
    owner.wake_bits = .init(0);
    owner.render = &render;
    const pane: PaneId = @enumFromInt(7);
    try std.testing.expectError(error.OutOfMemory, owner.initPane(pane, .{ .cols = 2, .rows = 1 }));
    try std.testing.expectEqual(null, owner.panes[0].pane);
    try std.testing.expectEqual(@as(u64, 0), owner.wake_bits.load(.acquire));
}

test "failed live PTY resize rolls back earlier pane before workspace commit" {
    var model = try workspace_model.Workspace.init(
        std.testing.allocator,
        @enumFromInt(1),
        "one",
        .{ .cols = 8, .rows = 2 },
    );
    defer model.deinit();
    const first = model.focusedPane();
    const second = try model.splitPane(model.activeTab(), first, .horizontal);
    try std.testing.expect(try model.focusPane(first));
    const first_terminal = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 4, .rows = 2 },
        .{},
    );
    defer first_terminal.deinit();
    const second_terminal = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 4, .rows = 2 },
        .{},
    );
    defer second_terminal.deinit();
    second_terminal.cancel();
    var owner: Loop = undefined;
    owner.panes = @splat(.{});
    owner.panes[0] = .{ .pane = first, .terminal = first_terminal, .geometry = .{ .cols = 4, .rows = 2 } };
    owner.panes[1] = .{ .pane = second, .terminal = second_terminal, .geometry = .{ .cols = 4, .rows = 2 } };
    var candidate = model;
    try std.testing.expect(try candidate.resizePane(candidate.activeTab(), second, .left, 1));
    try std.testing.expectError(error.NotStarted, owner.applyWorkspaceGeometry(&candidate));
    try std.testing.expectEqual(Geometry{ .cols = 4, .rows = 2 }, owner.panes[0].geometry);
    try std.testing.expectEqual(Geometry{ .cols = 4, .rows = 2 }, owner.panes[1].geometry);
    const status = first_terminal.status();
    try std.testing.expectEqual(@as(u16, 4), status.cols);
    try std.testing.expectEqual(@as(u16, 2), status.rows);
}

test "compositor close is an idempotent loop termination fact" {
    var closed = false;
    requestClose(&closed);
    try std.testing.expect(closed);
    requestClose(&closed);
    try std.testing.expect(closed);
}

test "pointer button transitions commit only after successful admission" {
    const target = PointerTarget{
        .pane = @enumFromInt(1),
        .row = 2,
        .col = 3,
        .pixel_x = 30,
        .pixel_y = 40,
    };
    var state = PointerState{};
    const pending_press = state.preparePress(0, target).?;
    // A failed send performs no commit, so the prospective press changes no local button fact.
    try std.testing.expectEqual(@as(u8, 0b001), pending_press.buttons_down);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);
    try std.testing.expectEqual(null, state.pressed[0]);
    state.commitPress(pending_press);
    try std.testing.expectEqual(@as(u8, 0b001), state.buttons_down);
    try std.testing.expectEqual(null, state.preparePress(0, target));

    const middle = state.preparePress(1, target).?;
    try std.testing.expectEqual(@as(u8, 0b011), middle.buttons_down);
    state.commitPress(middle);
    const moved = PointerTarget{
        .pane = @enumFromInt(1),
        .row = 4,
        .col = 5,
        .pixel_x = 50,
        .pixel_y = 60,
    };
    try std.testing.expect(state.move(moved));
    const pending_release = state.prepareRelease(0).?;
    try std.testing.expectEqual(moved, pending_release.target);
    try std.testing.expectEqual(@as(u8, 0b010), pending_release.buttons_down);
    try std.testing.expectEqual(@as(u8, 0b011), state.buttons_down);
    try std.testing.expectEqual(moved, state.pressed[0].?);
    // The same uncommitted state is the retryable release fact after failure.
    state.commitRelease(pending_release);
    try std.testing.expectEqual(@as(u8, 0b010), state.buttons_down);
    try std.testing.expectEqual(null, state.pressed[0]);
    state.commitRelease(state.prepareRelease(1).?);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);
    try std.testing.expectEqual(null, state.prepareRelease(0));

    state.commitPress(state.preparePress(0, target).?);
    var other = moved;
    other.pane = @enumFromInt(2);
    try std.testing.expect(!state.move(other));
    try std.testing.expectEqual(target, state.prepareRelease(0).?.target);
}

test "pointer hit identifies a visible pane before active focus admission" {
    var model = try workspace_model.Workspace.init(
        std.testing.allocator,
        @enumFromInt(1),
        "one",
        .{ .cols = 10, .rows = 1 },
    );
    defer model.deinit();
    const first = model.focusedPane();
    const second = try model.splitPane(model.activeTab(), first, .horizontal);
    try std.testing.expect(try model.focusPane(first));
    var render: renderer.Render = undefined;
    render.metrics_value = .{
        .cell_width = 10,
        .cell_height = 20,
        .baseline = 15,
        .underline_y = 17,
        .underline_height = 1,
        .strike_y = 10,
        .strike_height = 1,
    };
    var owner: Loop = undefined;
    owner.workspace = model;
    owner.panes = @splat(.{});
    owner.panes[0] = .{
        .pane = first,
        .terminal = @ptrFromInt(16),
        .geometry = .{ .cols = 5, .rows = 1 },
    };
    owner.panes[1] = .{
        .pane = second,
        .terminal = @ptrFromInt(32),
        .geometry = .{ .cols = 5, .rows = 1 },
    };
    owner.render = &render;
    owner.size = .{ .width = 100, .height = 20 };
    try std.testing.expectEqual(second, owner.resolvePointer(75, 5, false).?.pane);
    try std.testing.expectEqual(null, owner.resolvePointer(75, 5, true));
    try std.testing.expect(try owner.workspace.?.focusPane(second));
    try std.testing.expectEqual(second, owner.resolvePointer(75, 5, true).?.pane);
    owner.workspace = null;
}

test "pointer cleanup retains the first exact loop failure" {
    var failure: ?Error = error.WaylandDispatch;
    retainFirstFailure(&failure, error.InputIncomplete);
    try std.testing.expectEqual(@as(?Error, error.WaylandDispatch), failure);
    failure = null;
    retainFirstFailure(&failure, error.InputIncomplete);
    try std.testing.expectEqual(@as(?Error, error.InputIncomplete), failure);
}
