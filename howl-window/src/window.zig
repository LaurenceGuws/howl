//! Owns one direct Wayland/xkb loop around bounded tabs, panes, and terminals.

const std = @import("std");
const howl_control = @import("howl_control");
const howl_vt = @import("howl_vt");
const renderer = @import("renderer.zig");
const c = @import("native.zig").c;

const initial_size = renderer.Size{ .width = 960, .height = 600 };
const terminal_count: usize = 3;

const TabId = enum(u8) { split = 1, full = 2 };
const PaneId = enum(u8) { left = 1, right = 2, full = 3 };

const PaneSpec = struct { id: PaneId, terminal: u8 };
const Tab = struct { id: TabId, panes: []const PaneSpec };

const split_panes = [_]PaneSpec{
    .{ .id = .left, .terminal = 0 },
    .{ .id = .right, .terminal = 1 },
};
const full_panes = [_]PaneSpec{.{ .id = .full, .terminal = 2 }};
const tabs = [_]Tab{
    .{ .id = .split, .panes = &split_panes },
    .{ .id = .full, .panes = &full_panes },
};

const Workspace = struct {
    tab: u8 = 0,
    focus: [tabs.len]u8 = @splat(0),

    fn switchTab(self: *Workspace, index: u8) bool {
        if (index >= tabs.len or self.tab == index) return false;
        self.tab = index;
        return true;
    }

    fn focusNext(self: *Workspace) bool {
        const count: u8 = @intCast(tabs[self.tab].panes.len);
        if (count < 2) return false;
        self.focus[self.tab] = (self.focus[self.tab] + 1) % count;
        return true;
    }

    fn focusedTerminal(self: *const Workspace) u8 {
        return tabs[self.tab].panes[self.focus[self.tab]].terminal;
    }
};

const WakeContext = struct { owner: ?*anyopaque = null, index: u3 = 0 };

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
    TerminalSignal,
    Poll,
    InputIncomplete,
    ResizeResultMismatch,
    ResizeTransactionFailed,
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
    xkb_context: ?*c.struct_xkb_context = null,
    xkb_keymap: ?*c.struct_xkb_keymap = null,
    xkb_state: ?*c.struct_xkb_state = null,
    terminal_signal: c_int,
    wake_bits: std.atomic.Value(u8) = .init(0),
    wake_contexts: [terminal_count]WakeContext = @splat(.{}),
    terminals: [terminal_count]?*howl_control.Terminal = @splat(null),
    terminal_geometry: [terminal_count]Geometry = undefined,
    // A stopped or failed pane keeps its last backing and rejects only focused
    // input; sibling terminals, rendering, and tab ownership remain live.
    unavailable: [terminal_count]bool = @splat(false),
    render: ?*renderer.Render = null,
    size: renderer.Size = initial_size,
    pending_size: renderer.Size = initial_size,
    configured: bool = false,
    closed: bool = false,
    failure: ?Error = null,
    render_generation: u64 = 0,
    completed_generation: u64 = 0,
    workspace: Workspace = .{},

    fn init(allocator: std.mem.Allocator, io: std.Io, font_paths: []const []const u8) Error!*Loop {
        if (font_paths.len == 0) return error.FontOpen;
        const display = c.wl_display_connect(null) orelse return error.WaylandConnect;
        errdefer c.wl_display_disconnect(display);
        const registry = c.wl_display_get_registry(display) orelse return error.WaylandRegistry;
        errdefer c.wl_registry_destroy(registry);
        const terminal_signal = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (terminal_signal < 0) return error.TerminalSignal;
        errdefer closeOwned(terminal_signal);
        const self = try allocator.create(Loop);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .display = display,
            .registry = registry,
            .terminal_signal = terminal_signal,
        };
        for (&self.wake_contexts, 0..) |*context, index| context.* = .{
            .owner = self,
            .index = @intCast(index),
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
            for (&self.terminals) |*terminal| if (terminal.*) |value| {
                value.deinit();
                terminal.* = null;
            };
        }
        for (&self.terminals, 0..) |*terminal, index| {
            const geometry = terminalGeometry(@intCast(index), self.size, render.metrics());
            terminal.* = try howl_control.Terminal.init(allocator, io, .{
                .shell = "/bin/bash",
                .cols = geometry.cols,
                .rows = geometry.rows,
            }, .{ .context = &self.wake_contexts[index], .notify = terminalWake });
            self.terminal_geometry[index] = geometry;
        }
        self.updateTitle();
        return self;
    }

    fn run(self: *Loop) Error!void {
        try self.submitVisible(visibleMask(self.workspace.tab));
        while (!self.closed and self.failure == null) {
            if (c.wl_display_dispatch_pending(self.display) < 0) return error.WaylandDispatch;
            if (!std.meta.eql(self.pending_size, self.size) and
                self.completed_generation == self.render_generation) try self.resizeAll();
            if (c.wl_display_flush(self.display) < 0 and std.posix.errno(-1) != .AGAIN)
                return error.WaylandFlush;
            var fds = [_]std.posix.pollfd{
                .{ .fd = c.wl_display_get_fd(self.display), .events = std.posix.POLL.IN, .revents = 0 },
                .{ .fd = self.terminal_signal, .events = std.posix.POLL.IN, .revents = 0 },
                .{ .fd = self.render.?.signalFd(), .events = std.posix.POLL.IN, .revents = 0 },
            };
            const ready = std.posix.poll(&fds, -1) catch return error.Poll;
            std.debug.assert(ready != 0);
            const faults = std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL;
            if (fds[2].revents & faults != 0) return error.Signal;
            if (fds[2].revents & std.posix.POLL.IN != 0) {
                self.completed_generation = try self.render.?.completed();
                std.debug.assert(self.completed_generation != 0);
                if (!std.meta.eql(self.pending_size, self.size)) try self.resizeAll();
            }
            if (fds[1].revents & faults != 0) return error.TerminalSignal;
            if (fds[1].revents & std.posix.POLL.IN != 0) {
                try drainEvent(self.terminal_signal);
                const changed = self.wake_bits.swap(0, .acq_rel);
                for (&self.terminals, 0..) |*terminal, index| if (changed & (@as(u8, 1) << @intCast(index)) != 0) {
                    const value = terminal.*.?;
                    value.consumeWake();
                    self.unavailable[index] = value.state() != .running;
                };
                self.updateTitle();
                const visible_changed = changed & visibleMask(self.workspace.tab);
                if (visible_changed != 0) try self.submitVisible(visible_changed);
            }
            if (fds[0].revents & faults != 0) return error.WaylandDispatch;
            if (fds[0].revents & std.posix.POLL.IN != 0 and
                c.wl_display_dispatch(self.display) < 0) return error.WaylandDispatch;
        }
        if (self.failure) |failure| return failure;
    }

    fn submitVisible(self: *Loop, dirty_mask: u8) Error!void {
        var panes: [renderer.max_visible_panes]renderer.Pane = undefined;
        const pane_count = self.visiblePanes(&panes);
        var dirty: [renderer.max_terminals]*howl_control.Terminal = undefined;
        var dirty_count: usize = 0;
        const admitted_dirty = availableMask(dirty_mask, self.unavailable);
        for (panes[0..pane_count]) |pane| {
            for (self.terminals, 0..) |terminal, index| if (terminal == pane.terminal and
                admitted_dirty & (@as(u8, 1) << @intCast(index)) != 0)
            {
                dirty[dirty_count] = pane.terminal;
                dirty_count += 1;
                break;
            };
        }
        if (self.render_generation == std.math.maxInt(u64)) return error.StaleGeneration;
        self.render_generation += 1;
        try self.render.?.submit(
            self.render_generation,
            self.size,
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
        const plan = ResizePlan.init(
            self.pending_size,
            render.metrics(),
            self.terminal_geometry,
            self.unavailable,
        );
        var applied: [terminal_count]bool = @splat(false);
        for (self.terminals, 0..) |terminal, index| {
            if (!plan.change[index]) continue;
            const target = plan.target[index];
            const result = terminal.?.resize(target.cols, target.rows) catch |failure| {
                if (!self.rollbackResize(applied, index)) return error.ResizeTransactionFailed;
                return failure;
            };
            if (result.cols != target.cols or result.rows != target.rows) {
                const prior = self.terminal_geometry[index];
                const restored = terminal.?.resize(prior.cols, prior.rows) catch
                    return error.ResizeTransactionFailed;
                if (restored.cols != prior.cols or restored.rows != prior.rows or
                    !self.rollbackResize(applied, index)) return error.ResizeTransactionFailed;
                return error.ResizeResultMismatch;
            }
            applied[index] = true;
        }
        if (!plan.commit(&self.terminal_geometry, applied)) return error.ResizeTransactionFailed;
        self.size = self.pending_size;
        try self.submitVisible(visibleMask(self.workspace.tab));
    }

    fn rollbackResize(self: *Loop, applied: [terminal_count]bool, end: usize) bool {
        var index = end;
        while (index != 0) {
            index -= 1;
            if (!applied[index]) continue;
            const prior = self.terminal_geometry[index];
            const restored = self.terminals[index].?.resize(prior.cols, prior.rows) catch return false;
            if (restored.cols != prior.cols or restored.rows != prior.rows) return false;
        }
        return true;
    }

    fn visiblePanes(self: *Loop, output: *[renderer.max_visible_panes]renderer.Pane) usize {
        const selected = tabs[self.workspace.tab];
        const split = self.size.width / 2;
        for (selected.panes, 0..) |spec, index| {
            const rect: renderer.Pane = switch (selected.id) {
                .split => if (index == 0) .{
                    .id = @enumFromInt(@intFromEnum(spec.id)),
                    .terminal = self.terminals[spec.terminal].?,
                    .x = 0,
                    .y = 0,
                    .width = split,
                    .height = self.size.height,
                    .focused = self.workspace.focus[self.workspace.tab] == index,
                    .terminal_available = !self.unavailable[spec.terminal],
                } else .{
                    .id = @enumFromInt(@intFromEnum(spec.id)),
                    .terminal = self.terminals[spec.terminal].?,
                    .x = split,
                    .y = 0,
                    .width = self.size.width - split,
                    .height = self.size.height,
                    .focused = self.workspace.focus[self.workspace.tab] == index,
                    .terminal_available = !self.unavailable[spec.terminal],
                },
                .full => .{
                    .id = @enumFromInt(@intFromEnum(spec.id)),
                    .terminal = self.terminals[spec.terminal].?,
                    .x = 0,
                    .y = 0,
                    .width = self.size.width,
                    .height = self.size.height,
                    .focused = true,
                    .terminal_available = !self.unavailable[spec.terminal],
                },
            };
            output[index] = rect;
        }
        return selected.panes.len;
    }

    fn updateTitle(self: *Loop) void {
        const focused = self.workspace.focusedTerminal();
        const title: [*:0]const u8 = switch (self.workspace.tab) {
            0 => if (self.unavailable[focused])
                "Howl · tab 1/2 · pane unavailable"
            else if (self.workspace.focus[0] == 0)
                "Howl · tab 1/2 · pane 1/2"
            else
                "Howl · tab 1/2 · pane 2/2",
            1 => if (self.unavailable[focused])
                "Howl · tab 2/2 · pane unavailable"
            else
                "Howl · tab 2/2 · pane 1/1",
            else => unreachable,
        };
        c.xdg_toplevel_set_title(self.toplevel.?, title);
    }

    fn key(self: *Loop, code: u32, state_value: u32) void {
        if (state_value != c.WL_KEYBOARD_KEY_STATE_PRESSED) return;
        const state = self.xkb_state orelse return;
        const symbol = c.xkb_state_key_get_one_sym(state, code + 8);
        var bytes: [64]u8 = undefined;
        const count = c.xkb_state_key_get_utf8(state, code + 8, &bytes, bytes.len);
        if (count < 0 or count >= bytes.len) return;
        const text = bytes[0..@intCast(count)];
        const mods: @FieldType(@FieldType(howl_control.Input, "key"), "mods") = .{
            .shift = modifierActive(state, c.XKB_MOD_NAME_SHIFT),
            .alt = modifierActive(state, c.XKB_MOD_NAME_ALT),
            .control = modifierActive(state, c.XKB_MOD_NAME_CTRL),
            .super = modifierActive(state, c.XKB_MOD_NAME_LOGO),
            .caps_lock = modifierActive(state, c.XKB_MOD_NAME_CAPS),
            .num_lock = modifierActive(state, c.XKB_MOD_NAME_NUM),
        };
        if (mods.control and mods.shift) {
            const changed = switch (symbol) {
                c.XKB_KEY_F1 => self.workspace.switchTab(0),
                c.XKB_KEY_F2 => self.workspace.switchTab(1),
                c.XKB_KEY_Tab, c.XKB_KEY_ISO_Left_Tab => self.workspace.focusNext(),
                else => false,
            };
            if (changed) {
                self.updateTitle();
                self.submitVisible(visibleMask(self.workspace.tab)) catch |failure| {
                    self.failure = failure;
                };
                return;
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
            .{ .key = .{ .key = .{ .named = value }, .mods = mods, .text = text } }
        else unicode: {
            const scalar = c.xkb_keysym_to_utf32(symbol);
            if (scalar == 0 or scalar > std.math.maxInt(u21)) return;
            const codepoint: u21 = @intCast(scalar);
            if (!std.unicode.utf8ValidCodepoint(codepoint)) return;
            break :unicode .{ .key = .{
                .key = howl_vt.Terminal.Key.initUnicode(codepoint) catch return,
                .mods = mods,
                .text = text,
            } };
        };
        const focused = focusedAvailable(self.workspace, self.unavailable) orelse return;
        const result = self.terminals[focused].?.send(&.{.{ .input = input }}) catch |failure| {
            self.failure = failure;
            return;
        };
        switch (result.outcome) {
            .complete => {},
            .incomplete, .rejected => self.failure = error.InputIncomplete,
        }
    }

    fn deinit(self: *Loop) Error!void {
        if (self.render) |render| render.deinit() catch |failure| {
            self.deinitTerminals();
            self.destroyWayland();
            const allocator = self.allocator;
            allocator.destroy(self);
            return failure;
        };
        self.deinitTerminals();
        self.destroyWayland();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn deinitTerminals(self: *Loop) void {
        for (&self.terminals) |*terminal| if (terminal.*) |value| {
            value.deinit();
            terminal.* = null;
        };
    }

    fn destroyWayland(self: *Loop) void {
        self.destroyKeyboard();
        if (self.seat) |value| c.wl_seat_destroy(value);
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.wm_base) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
        closeOwned(self.terminal_signal);
    }

    fn destroyKeyboard(self: *Loop) void {
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

/// Runs one replacement Wayland window until compositor close or exact failure.
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
    const bit = @as(u8, 1) << wake.index;
    if (self.wake_bits.fetchOr(bit, .release) & bit != 0) return;
    const value: u64 = 1;
    const count = c.write(self.terminal_signal, &value, @sizeOf(u64));
    if (count != @sizeOf(u64) and !(count < 0 and std.posix.errno(count) == .AGAIN))
        @panic("terminal wake eventfd write failed");
}

const Geometry = struct { cols: u16, rows: u16 };

const ResizePlan = struct {
    target: [terminal_count]Geometry,
    change: [terminal_count]bool,

    fn init(
        size: renderer.Size,
        metrics: @import("howl_text").Metrics,
        current: [terminal_count]Geometry,
        unavailable: [terminal_count]bool,
    ) ResizePlan {
        var plan = ResizePlan{ .target = current, .change = @splat(false) };
        for (&plan.target, 0..) |*target, index| {
            if (unavailable[index]) continue;
            target.* = terminalGeometry(@intCast(index), size, metrics);
            plan.change[index] = !std.meta.eql(target.*, current[index]);
        }
        return plan;
    }

    fn commit(
        self: ResizePlan,
        current: *[terminal_count]Geometry,
        applied: [terminal_count]bool,
    ) bool {
        if (!std.meta.eql(self.change, applied)) return false;
        current.* = self.target;
        return true;
    }
};

fn terminalGeometry(index: u8, size: renderer.Size, metrics: @import("howl_text").Metrics) Geometry {
    const width = if (index < 2)
        if (index == 0) size.width / 2 else size.width - size.width / 2
    else
        size.width;
    return .{
        .cols = @intCast(@max(1, width / metrics.cell_width)),
        .rows = @intCast(@max(1, size.height / metrics.cell_height)),
    };
}

fn visibleMask(tab: u8) u8 {
    var mask: u8 = 0;
    for (tabs[tab].panes) |pane| mask |= @as(u8, 1) << @intCast(pane.terminal);
    return mask;
}

fn availableMask(requested: u8, unavailable: [terminal_count]bool) u8 {
    var admitted = requested;
    for (unavailable, 0..) |blocked, index| {
        if (blocked) admitted &= ~(@as(u8, 1) << @intCast(index));
    }
    return admitted;
}

fn focusedAvailable(workspace: Workspace, unavailable: [terminal_count]bool) ?u8 {
    const terminal = workspace.focusedTerminal();
    return if (unavailable[terminal]) null else terminal;
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
    loop(data).closed = true;
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
        self.destroyKeyboard();
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
fn keyboardLeave(_: ?*anyopaque, _: ?*c.struct_wl_keyboard, _: u32, _: ?*c.struct_wl_surface) callconv(.c) void {}
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
fn keyboardRepeat(_: ?*anyopaque, _: ?*c.struct_wl_keyboard, _: i32, _: i32) callconv(.c) void {}
const keyboard_listener = c.struct_wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeat,
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

test "pixel geometry admits at least one bounded cell" {
    const size = renderer.Size{ .width = 1, .height = 1 };
    try std.testing.expectEqual(@as(u32, 1), @max(1, size.width / 8));
    try std.testing.expectEqual(@as(u32, 1), @max(1, size.height / 16));
}

test "two stable tabs retain split focus independently" {
    var workspace = Workspace{};
    try std.testing.expectEqual(TabId.split, tabs[workspace.tab].id);
    try std.testing.expectEqual(@as(u8, 0), workspace.focusedTerminal());
    try std.testing.expect(workspace.focusNext());
    try std.testing.expectEqual(@as(u8, 1), workspace.focusedTerminal());
    try std.testing.expect(workspace.switchTab(1));
    try std.testing.expectEqual(TabId.full, tabs[workspace.tab].id);
    try std.testing.expectEqual(@as(u8, 2), workspace.focusedTerminal());
    try std.testing.expect(!workspace.focusNext());
    try std.testing.expect(workspace.switchTab(0));
    try std.testing.expectEqual(@as(u8, 1), workspace.focusedTerminal());
    try std.testing.expectEqual(@intFromEnum(PaneId.left), 1);
    try std.testing.expectEqual(@intFromEnum(PaneId.right), 2);
    try std.testing.expectEqual(@intFromEnum(PaneId.full), 3);
}

test "hidden terminal wakes stay outside visible work until tab switch" {
    try std.testing.expectEqual(@as(u8, 0b011), visibleMask(0));
    try std.testing.expectEqual(@as(u8, 0b100), visibleMask(1));
    const hidden_wake: u8 = 0b100;
    try std.testing.expectEqual(@as(u8, 0), hidden_wake & visibleMask(0));
    try std.testing.expectEqual(hidden_wake, hidden_wake & visibleMask(1));
}

test "one failed pane rejects only its focused input" {
    var workspace = Workspace{};
    var unavailable: [terminal_count]bool = @splat(false);
    unavailable[0] = true;
    try std.testing.expectEqual(null, focusedAvailable(workspace, unavailable));
    try std.testing.expect(workspace.focusNext());
    try std.testing.expectEqual(@as(u8, 1), focusedAvailable(workspace, unavailable).?);
    try std.testing.expect(workspace.switchTab(1));
    try std.testing.expectEqual(@as(u8, 2), focusedAvailable(workspace, unavailable).?);
    try std.testing.expectEqual(@as(u8, 0b010), availableMask(visibleMask(0), unavailable));
    try std.testing.expectEqual(@as(u8, 0b100), availableMask(visibleMask(1), unavailable));
}

test "split and full terminal geometry cover admitted pixels deterministically" {
    const metrics = testMetrics();
    const size = renderer.Size{ .width = 101, .height = 61 };
    try std.testing.expectEqual(Geometry{ .cols = 5, .rows = 3 }, terminalGeometry(0, size, metrics));
    try std.testing.expectEqual(Geometry{ .cols = 5, .rows = 3 }, terminalGeometry(1, size, metrics));
    try std.testing.expectEqual(Geometry{ .cols = 10, .rows = 3 }, terminalGeometry(2, size, metrics));
}

test "resize plan excludes unavailable geometry and commits every live result together" {
    const metrics = testMetrics();
    const current = [_]Geometry{
        .{ .cols = 40, .rows = 20 },
        .{ .cols = 40, .rows = 20 },
        .{ .cols = 80, .rows = 20 },
    };
    const unavailable = [_]bool{ false, true, false };
    const plan = ResizePlan.init(
        .{ .width = 1_000, .height = 500 },
        metrics,
        current,
        unavailable,
    );
    try std.testing.expectEqual([_]bool{ true, false, true }, plan.change);
    try std.testing.expectEqual(current[1], plan.target[1]);

    var uncommitted = current;
    try std.testing.expect(!plan.commit(&uncommitted, .{ true, false, false }));
    try std.testing.expectEqual(current, uncommitted);

    var committed = current;
    try std.testing.expect(plan.commit(&committed, plan.change));
    try std.testing.expectEqual(plan.target, committed);
    try std.testing.expectEqual(current[1], committed[1]);
}

fn testMetrics() @import("howl_text").Metrics {
    return .{
        .cell_width = 10,
        .cell_height = 20,
        .baseline = 15,
        .underline_y = 17,
        .underline_height = 1,
        .strike_y = 10,
        .strike_height = 1,
    };
}
