//! Owns main-thread Wayland dispatch, input, layout, and native render lifecycle.

const std = @import("std");
const layout = @import("layout.zig");
const render = @import("render.zig");
const terminal = @import("terminal.zig");
const c = @import("native.zig").c;
const fallback_title: [:0]const u8 = "howl-host";

/// Reports exact allocation, thread, Wayland, keyboard, layout, or rendering failure.
pub const Error = std.mem.Allocator.Error || layout.Error || render.StartError ||
    terminal.Error || error{
    wayland_connect_failed,
    wayland_registry_failed,
    wayland_compositor_missing,
    wayland_shell_missing,
    wayland_surface_failed,
    wayland_dispatch_failed,
    wayland_flush_failed,
    wayland_poll_failed,
    invalid_configure,
    keyboard_context_failed,
    keyboard_map_failed,
    keyboard_state_failed,
    keyboard_repeat_failed,
    pressed_key_limit,
};

const Configure = struct {
    pending_size: ?layout.Size = null,
    configured: bool = false,

    fn toplevel(self: *Configure, width: i32, height: i32) error{invalid_configure}!void {
        if (width == 0 and height == 0) return;
        if (width <= 0 or height <= 0) return error.invalid_configure;
        self.pending_size = .{
            .width = std.math.cast(u16, width) orelse return error.invalid_configure,
            .height = std.math.cast(u16, height) orelse return error.invalid_configure,
        };
    }

    const Completed = struct {
        serial: u32,
        size: ?layout.Size,
    };

    fn complete(self: *Configure, serial: u32) Completed {
        const completed = Completed{ .serial = serial, .size = self.pending_size };
        self.pending_size = null;
        self.configured = true;
        return completed;
    }
};

const FrameGate = struct {
    pending: bool = false,
    dirty: bool = true,

    fn changed(self: *FrameGate) bool {
        self.dirty = true;
        if (self.pending) return false;
        self.pending = true;
        self.dirty = false;
        return true;
    }

    fn completed(self: *FrameGate) bool {
        self.pending = false;
        if (!self.dirty) return false;
        self.pending = true;
        self.dirty = false;
        return true;
    }

    fn failed(self: *FrameGate) void {
        self.pending = false;
        self.dirty = true;
    }
};

const Presentation = struct {
    current: layout.Snapshot,
    desired: layout.Snapshot,
    terminals: [layout.terminal_count]terminal.Snapshot,

    fn init(
        snapshot: layout.Snapshot,
        terminals: [layout.terminal_count]terminal.Snapshot,
    ) Presentation {
        return .{
            .current = snapshot,
            .desired = snapshot,
            .terminals = terminals,
        };
    }

    fn change(self: *Presentation, snapshot: layout.Snapshot) void {
        self.desired = snapshot;
    }

    fn promote(
        self: *Presentation,
        snapshots: *const [layout.terminal_count]terminal.Snapshot,
        cell_size: terminal.CellSize,
    ) bool {
        for (self.desired.visible()) |placement|
            if (!terminal.matchesPlacement(
                &snapshots[placement.terminal.index()],
                placement,
                cell_size,
            )) return false;
        if (std.meta.eql(self.current, self.desired)) return false;
        self.current = self.desired;
        self.terminals = snapshots.*;
        return true;
    }

    fn refresh(
        self: *Presentation,
        id: layout.TerminalId,
        snapshot: *const terminal.Snapshot,
        cell_size: terminal.CellSize,
    ) bool {
        for (self.current.visible()) |placement|
            if (placement.terminal == id) {
                if (!terminal.matchesPlacement(snapshot, placement, cell_size))
                    return false;
                self.terminals[id.index()] = snapshot.*;
                return true;
            };
        return false;
    }
};

const KeyAction = enum {
    none,
    first_tab,
    second_tab,
    next_terminal,
    close,
};

const Repeat = struct {
    interval_ns: ?u64 = null,
    delay_ns: u64 = 1,
    key: ?u32 = null,

    fn configure(self: *Repeat, rate: i32, delay_ms: i32) error{invalid}!void {
        if (rate < 0 or delay_ms < 0) return error.invalid;
        self.key = null;
        if (rate == 0) {
            self.interval_ns = null;
            return;
        }
        self.interval_ns = @max(@as(u64, 1), std.time.ns_per_s / @as(u64, @intCast(rate)));
        self.delay_ns = @max(
            @as(u64, 1),
            @as(u64, @intCast(delay_ms)) * std.time.ns_per_ms,
        );
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
        return .{
            .key = self.key orelse return null,
            .next_ns = self.interval_ns orelse return null,
        };
    }

    fn cancel(self: *Repeat) void {
        self.key = null;
    }
};

const pressed_key_capacity: usize = terminal.max_pressed_keys;

const ModifierFacts = struct {
    shift: bool,
    alt: bool,
    control: bool,
    super: bool,
    hyper: bool,
    meta: bool,
    caps_lock: bool,
    num_lock: bool,
};

const PressedKey = struct {
    code: u32,
    target: layout.TerminalId,
    command: union(enum) {
        named: terminal.KeyCommand,
        unicode: terminal.UnicodeKeyCommand,
    },

    fn action(self: PressedKey, value: terminal.KeyAction) PressedKey {
        var result = self;
        switch (result.command) {
            .named => |*command| command.action = value,
            .unicode => |*command| {
                command.action = value;
                if (value == .release) {
                    command.legacy.len = 0;
                    command.text.len = 0;
                }
            },
        }
        return result;
    }

    fn modifiers(self: PressedKey, facts: ModifierFacts) PressedKey {
        var result = self;
        switch (result.command) {
            inline else => |*command| {
                command.shift = facts.shift;
                command.alt = facts.alt;
                command.control = facts.control;
                command.super = facts.super;
                command.hyper = facts.hyper;
                command.meta = facts.meta;
                command.caps_lock = facts.caps_lock;
                command.num_lock = facts.num_lock;
            },
        }
        if (result.command == .named)
            applyModifierKey(
                &result.command.named,
                result.command.named.named,
                result.command.named.action != .release,
            );
        return result;
    }
};

fn applyModifierKey(command: *terminal.KeyCommand, key: terminal.NamedKey, active: bool) void {
    switch (key) {
        .left_shift, .right_shift => command.shift = active,
        .left_control, .right_control => command.control = active,
        .left_alt, .right_alt => command.alt = active,
        .left_super, .right_super => command.super = active,
        .left_hyper, .right_hyper => command.hyper = active,
        .left_meta, .right_meta => command.meta = active,
        // Lock state is supplied by XKB and may toggle on press or release;
        // physical key action must not overwrite that retained lock fact.
        .caps_lock, .num_lock => {},
        else => {},
    }
}

const PressedKeys = struct {
    values: [pressed_key_capacity]PressedKey = undefined,
    len: u8 = 0,

    fn find(self: *const PressedKeys, code: u32) ?usize {
        for (self.values[0..self.len], 0..) |value, index|
            if (value.code == code) return index;
        return null;
    }

    fn admit(self: *const PressedKeys, code: u32) error{pressed_key_limit}!bool {
        if (self.find(code) != null) return false;
        if (self.len == self.values.len) return error.pressed_key_limit;
        return true;
    }

    fn append(self: *PressedKeys, value: PressedKey) void {
        if (self.find(value.code) != null or self.len == self.values.len)
            @panic("pressed-key admission was not preserved through routing");
        self.values[self.len] = value;
        self.len += 1;
    }

    fn remove(self: *PressedKeys, index: usize) void {
        if (index >= self.len) @panic("pressed-key removal index is invalid");
        self.len -= 1;
        if (index != self.len) self.values[index] = self.values[self.len];
    }
};

const PointerTarget = struct {
    terminal: layout.TerminalId,
    row: u16,
    col: u16,
    pixel_x: u16,
    pixel_y: u16,
};

const PointerState = struct {
    target: ?PointerTarget = null,
    position: ?struct { x: c.wl_fixed_t, y: c.wl_fixed_t } = null,
    // A press retains its original terminal target until one exact release.
    pressed: [3]?PointerTarget = .{null} ** 3,
    buttons_down: u8 = 0,

    const Transition = struct {
        target: PointerTarget,
        button: terminal.MouseButton,
        kind: terminal.MouseKind,
        buttons_down: u8,
    };

    fn press(
        self: *PointerState,
        value: terminal.MouseButton,
    ) ?Transition {
        const target = self.target orelse return null;
        const index = buttonIndex(value) orelse return null;
        if (self.pressed[index] != null) return null;
        const mask = buttonMask(index);
        self.pressed[index] = target;
        self.buttons_down |= mask;
        return .{
            .target = target,
            .button = value,
            .kind = .press,
            .buttons_down = self.buttons_down,
        };
    }

    fn release(self: *PointerState, value: terminal.MouseButton) ?Transition {
        const index = buttonIndex(value) orelse return null;
        const target = self.pressed[index] orelse return null;
        const mask = buttonMask(index);
        self.pressed[index] = null;
        self.buttons_down &= ~mask;
        return .{
            .target = target,
            .button = value,
            .kind = .release,
            .buttons_down = self.buttons_down,
        };
    }

    fn undoPress(self: *PointerState, value: terminal.MouseButton) void {
        const index = buttonIndex(value) orelse
            @panic("pointer press rollback received a non-physical button");
        if (self.pressed[index] == null)
            @panic("pointer press rollback has no accepted press");
        self.pressed[index] = null;
        self.buttons_down &= ~buttonMask(index);
    }

    fn cancelNext(self: *PointerState) ?Transition {
        for ([_]terminal.MouseButton{ .left, .middle, .right }) |button|
            if (self.release(button)) |transition| return transition;
        return null;
    }

    fn leave(self: *PointerState) void {
        if (self.buttons_down != 0 or
            self.pressed[0] != null or
            self.pressed[1] != null or
            self.pressed[2] != null)
            @panic("pointer lifecycle cleared an accepted press without release");
        self.* = .{};
    }
};

fn buttonIndex(button: terminal.MouseButton) ?usize {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        else => null,
    };
}

fn buttonMask(index: usize) u8 {
    std.debug.assert(index < 3);
    return @as(u8, 1) << @intCast(index);
}

const Wheel = struct {
    button: terminal.MouseButton,
    steps: u8,
};

fn wheelEvent(discrete: i32) error{invalid_mouse}!?Wheel {
    if (discrete == 0) return null;
    const magnitude: u32 = if (discrete < 0)
        @intCast(-@as(i64, discrete))
    else
        @intCast(discrete);
    if (magnitude > terminal.max_wheel_steps) return error.invalid_mouse;
    return .{
        .button = if (discrete < 0) .wheel_up else .wheel_down,
        .steps = @intCast(magnitude),
    };
}

/// Owns one top-level window, deterministic layout, input, and render thread.
pub const Window = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    display: *c.struct_wl_display,
    registry: *c.struct_wl_registry,
    compositor: ?*c.struct_wl_compositor,
    wm_base: ?*c.struct_xdg_wm_base,
    compositor_name: ?u32 = null,
    wm_base_name: ?u32 = null,
    seat_name: ?u32 = null,
    surface: *c.struct_wl_surface,
    xdg_surface: *c.struct_xdg_surface,
    toplevel: *c.struct_xdg_toplevel,
    seat: ?*c.struct_wl_seat = null,
    keyboard: ?*c.struct_wl_keyboard = null,
    pointer: ?*c.struct_wl_pointer = null,
    pointer_state: PointerState = .{},
    xkb_context: ?*c.struct_xkb_context = null,
    xkb_keymap: ?*c.struct_xkb_keymap = null,
    xkb_state: ?*c.struct_xkb_state = null,
    repeat_fd: c_int,
    repeat: Repeat = .{},
    pressed_keys: PressedKeys = .{},
    renderer: ?*render.Render,
    terminals: ?terminal.Set,
    terminal_snapshots: [layout.terminal_count]terminal.Snapshot,
    layout: layout.Layout,
    presentation: Presentation,
    cell_size: terminal.CellSize,
    render_generation: u64 = 0,
    frame_callback: ?*c.struct_wl_callback = null,
    configure: Configure = .{},
    frame: FrameGate = .{},
    focused: bool = false,
    closed: bool = false,
    failure: ?Error = null,

    /// Starts one window, explicit-font render owner, and three terminal owners.
    pub fn open(
        allocator: std.mem.Allocator,
        io: std.Io,
        axis: layout.Axis,
        size: layout.Size,
        font_path: []const u8,
    ) Error!*Window {
        const self = try allocator.create(Window);
        errdefer allocator.destroy(self);
        const repeat_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC | c.TFD_NONBLOCK);
        if (repeat_fd < 0) return error.keyboard_repeat_failed;
        errdefer if (c.close(repeat_fd) != 0)
            @panic("Linux rejected keyboard timer rollback");
        const display = c.wl_display_connect(null) orelse return error.wayland_connect_failed;
        errdefer c.wl_display_disconnect(display);
        const registry = c.wl_display_get_registry(display) orelse
            return error.wayland_registry_failed;
        errdefer c.wl_registry_destroy(registry);

        self.* = undefined;
        self.allocator = allocator;
        self.io = io;
        self.display = display;
        self.registry = registry;
        self.compositor = null;
        self.wm_base = null;
        self.compositor_name = null;
        self.wm_base_name = null;
        self.seat_name = null;
        self.seat = null;
        self.keyboard = null;
        self.pointer = null;
        self.pointer_state = .{};
        self.xkb_context = null;
        self.xkb_keymap = null;
        self.xkb_state = null;
        self.repeat_fd = repeat_fd;
        self.repeat = .{};
        self.pressed_keys = .{};
        self.renderer = null;
        self.terminals = null;
        self.frame_callback = null;
        self.configure = .{};
        self.frame = .{};
        self.focused = false;
        self.closed = false;
        self.failure = null;
        self.render_generation = 0;
        self.layout = try .init(axis, size);
        errdefer self.destroyRegistryObjects();
        if (c.wl_registry_add_listener(registry, &registry_listener, self) != 0)
            return error.wayland_registry_failed;
        if (c.wl_display_roundtrip(display) < 0) return error.wayland_dispatch_failed;
        if (self.failure) |failure| return failure;
        const compositor = self.compositorOrError() catch return error.wayland_compositor_missing;
        const wm_base = self.shellOrError() catch return error.wayland_shell_missing;
        self.compositor = compositor;
        self.wm_base = wm_base;
        if (c.xdg_wm_base_add_listener(wm_base, &wm_base_listener, self) != 0)
            return error.wayland_shell_missing;

        const surface = c.wl_compositor_create_surface(compositor) orelse
            return error.wayland_surface_failed;
        errdefer c.wl_surface_destroy(surface);
        const xdg_surface = c.xdg_wm_base_get_xdg_surface(wm_base, surface) orelse
            return error.wayland_surface_failed;
        errdefer c.xdg_surface_destroy(xdg_surface);
        if (c.xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, self) != 0)
            return error.wayland_surface_failed;
        const toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse
            return error.wayland_surface_failed;
        errdefer c.xdg_toplevel_destroy(toplevel);
        if (c.xdg_toplevel_add_listener(toplevel, &toplevel_listener, self) != 0)
            return error.wayland_surface_failed;
        c.xdg_toplevel_set_title(toplevel, fallback_title.ptr);
        c.wl_surface_commit(surface);

        self.surface = surface;
        self.xdg_surface = xdg_surface;
        self.toplevel = toplevel;
        while (!self.configure.configured) {
            if (c.wl_display_dispatch(display) < 0) return error.wayland_dispatch_failed;
            if (self.failure) |failure| return failure;
        }
        const snapshot = try self.layout.snapshot();
        self.renderer = try render.Render.startNative(allocator, io, .{
            .display = display,
            .surface = surface,
            .size = self.layout.size,
            .font_path = font_path,
        });
        errdefer if (self.renderer) |renderer| renderer.deinit() catch
            @panic("render startup rollback failed");
        const metrics = self.renderer.?.metrics();
        self.cell_size = .{
            .width = metrics.cell_width,
            .height = metrics.cell_height,
        };
        self.terminals = try .start(allocator, io, snapshot, self.cell_size);
        errdefer if (self.terminals) |*terminals| terminals.deinit() catch
            @panic("terminal startup rollback failed");
        if (self.focused)
            try self.terminals.?.focus(self.layout.focused, true);
        self.terminal_snapshots = try self.terminals.?.snapshots();
        self.presentation = .init(snapshot, self.terminal_snapshots);
        if (self.pointer_state.position) |position|
            self.pointerMotion(position.x, position.y);
        self.schedule() catch |failure| {
            if (self.frame_callback) |callback| {
                c.wl_callback_destroy(callback);
                self.frame_callback = null;
            }
            return failure;
        };
        return self;
    }

    /// Dispatches until compositor close, owner failure, or explicit close shortcut.
    pub fn run(self: *Window) Error!void {
        while (!self.closed) {
            while (c.wl_display_prepare_read(self.display) != 0) {
                if (c.wl_display_dispatch_pending(self.display) < 0)
                    return error.wayland_dispatch_failed;
            }
            const flush_result = c.wl_display_flush(self.display);
            const flush_blocked = flush_result < 0 and std.posix.errno(flush_result) == .AGAIN;
            if (flush_result < 0 and !flush_blocked) {
                c.wl_display_cancel_read(self.display);
                return error.wayland_flush_failed;
            }
            const display_events: i16 = @as(i16, std.posix.POLL.IN) |
                if (flush_blocked) @as(i16, std.posix.POLL.OUT) else 0;
            var fds = [_]std.posix.pollfd{
                .{
                    .fd = c.wl_display_get_fd(self.display),
                    .events = display_events,
                    .revents = 0,
                },
                .{
                    .fd = self.terminals.?.completionFd(.first),
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = self.terminals.?.completionFd(.second),
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = self.terminals.?.completionFd(.third),
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = self.renderer.?.signalFd(),
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = self.repeat_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };
            const ready = std.posix.poll(&fds, -1) catch {
                c.wl_display_cancel_read(self.display);
                return error.wayland_poll_failed;
            };
            if (ready == 0) {
                c.wl_display_cancel_read(self.display);
                return error.wayland_poll_failed;
            }
            if (fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0) {
                c.wl_display_cancel_read(self.display);
                return error.wayland_dispatch_failed;
            }
            if (fds[0].revents & std.posix.POLL.IN != 0) {
                if (c.wl_display_read_events(self.display) < 0)
                    return error.wayland_dispatch_failed;
            } else {
                c.wl_display_cancel_read(self.display);
            }
            if (c.wl_display_dispatch_pending(self.display) < 0)
                return error.wayland_dispatch_failed;
            if (fds[0].revents & std.posix.POLL.OUT != 0 and c.wl_display_flush(self.display) < 0)
                return error.wayland_flush_failed;
            for (std.enums.values(layout.TerminalId), 1..) |id, fd_index| {
                if (fds[fd_index].revents & std.posix.POLL.IN == 0) continue;
                self.terminal_snapshots[id.index()] = try self.terminals.?.copySnapshot(id);
                const changed = self.presentation.promote(
                    &self.terminal_snapshots,
                    self.cell_size,
                ) or self.presentation.refresh(
                    id,
                    &self.terminal_snapshots[id.index()],
                    self.cell_size,
                );
                if (changed) {
                    self.updateTitle();
                    try self.schedule();
                }
            }
            const render_fd_index = 1 + layout.terminal_count;
            if (fds[render_fd_index].revents & std.posix.POLL.IN != 0)
                try self.renderer.?.completed();
            const repeat_fd_index = render_fd_index + 1;
            if (fds[repeat_fd_index].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0)
                return error.keyboard_repeat_failed;
            if (fds[repeat_fd_index].revents & std.posix.POLL.IN != 0)
                try self.repeatKey();
            if (self.failure) |failure| return failure;
        }
    }

    /// Ends main-thread dispatch; deinit performs the joined native teardown.
    pub fn close(self: *Window) void {
        self.closed = true;
    }

    /// Stops and joins rendering, then destroys native objects in reverse order.
    pub fn deinit(self: *Window) Error!void {
        var repeat_failure: ?Error = null;
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| {
            repeat_failure = failure;
        };
        const pointer_failure = self.endPointer();
        // Final teardown terminates every PTY child; queued releases race the
        // stop command and have no observable lifecycle guarantee. Clear only
        // host tracking here. Focus loss remains the delivery boundary.
        self.pressed_keys = .{};
        self.focused = false;
        var render_failure: ?render.Error = null;
        if (self.renderer) |renderer| renderer.deinit() catch |failure| {
            render_failure = failure;
        };
        var terminal_failure: ?terminal.Error = null;
        if (self.terminals) |*terminals| terminals.deinit() catch |failure| {
            terminal_failure = failure;
        };
        if (self.frame_callback) |callback| c.wl_callback_destroy(callback);
        c.xdg_toplevel_destroy(self.toplevel);
        c.xdg_surface_destroy(self.xdg_surface);
        c.wl_surface_destroy(self.surface);
        self.destroyRegistryObjects();
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
        if (c.close(self.repeat_fd) != 0 and repeat_failure == null)
            repeat_failure = error.keyboard_repeat_failed;
        const allocator = self.allocator;
        allocator.destroy(self);
        if (pointer_failure) |failure| return failure;
        if (render_failure) |failure| return failure;
        if (terminal_failure) |failure| return failure;
        if (repeat_failure) |failure| return failure;
    }

    fn schedule(self: *Window) Error!void {
        if (!self.frame.changed()) return;
        self.requestFrame() catch |failure| {
            self.frame.failed();
            return failure;
        };
    }

    fn requestFrame(self: *Window) Error!void {
        const callback = c.wl_surface_frame(self.surface) orelse
            return error.wayland_surface_failed;
        if (c.wl_callback_add_listener(callback, &frame_listener, self) != 0) {
            c.wl_callback_destroy(callback);
            return error.wayland_surface_failed;
        }
        self.frame_callback = callback;
        if (self.render_generation == std.math.maxInt(u64))
            return error.stale_generation;
        self.render_generation += 1;
        try self.renderer.?.submit(
            self.render_generation,
            self.presentation.current,
            self.presentation.terminals,
        );
    }

    fn applyConfigure(self: *Window, serial: u32) void {
        const completed = self.configure.complete(serial);
        c.xdg_surface_ack_configure(self.xdg_surface, completed.serial);
        var changed = false;
        if (completed.size) |size| {
            const generation = self.layout.generation;
            const snapshot = self.layout.resize(size) catch |failure| {
                self.failure = failure;
                return;
            };
            std.debug.assert(std.meta.eql(snapshot.size, size));
            changed = snapshot.generation != generation;
            if (changed and self.terminals != null) {
                self.presentation.change(snapshot);
                self.terminals.?.resizeVisible(snapshot) catch |failure| {
                    self.failure = failure;
                    return;
                };
            }
        }
        if (self.renderer != null and changed and self.presentation.promote(
            &self.terminal_snapshots,
            self.cell_size,
        )) {
            self.updateTitle();
            self.schedule() catch |failure| {
                self.failure = failure;
            };
        }
    }

    fn key(self: *Window, code: u32, state: u32) void {
        if (state == c.WL_KEYBOARD_KEY_STATE_RELEASED) {
            if (self.pressed_keys.find(code)) |index| {
                const xkb_state = self.xkb_state orelse return;
                const facts = readModifiers(xkb_state) catch |failure| {
                    self.failure = failure;
                    return;
                };
                const released = self.pressed_keys.values[index]
                    .action(.release).modifiers(facts);
                self.submitPressed(released) catch |failure| {
                    self.failure = failure;
                    return;
                };
                self.pressed_keys.remove(index);
            }
            if (self.repeat.release(code))
                self.armRepeat(null) catch |failure| {
                    self.failure = failure;
                };
            return;
        }
        if (state != c.WL_KEYBOARD_KEY_STATE_PRESSED) return;
        const xkb_state = self.xkb_state orelse return;
        const symbol = c.xkb_state_key_get_one_sym(xkb_state, code + 8);
        const action = keyAction(symbol);
        var routed = false;
        if (action == .none) {
            const admitted = self.pressed_keys.admit(code) catch |failure| {
                self.failure = failure;
                return;
            };
            if (!admitted) return;
            if (self.routeKey(xkb_state, code + 8, symbol, .press)) |pressed| {
                self.pressed_keys.append(pressed);
                routed = true;
            }
        }
        const keymap = self.xkb_keymap orelse return;
        const repeatable = routed and c.xkb_keymap_key_repeats(keymap, code + 8) != 0;
        self.armRepeat(self.repeat.press(code, repeatable)) catch |failure| {
            self.failure = failure;
            return;
        };
        switch (action) {
            .none => {},
            .first_tab => self.selectTab(0),
            .second_tab => self.selectTab(1),
            .next_terminal => self.toggleFocus(),
            .close => self.closed = true,
        }
    }

    fn routeKey(
        self: *Window,
        state: *c.struct_xkb_state,
        code: u32,
        symbol: c.xkb_keysym_t,
        action: terminal.KeyAction,
    ) ?PressedKey {
        const facts = readModifiers(state) catch |failure| {
            self.failure = failure;
            return null;
        };
        const shift = facts.shift;
        const alt = facts.alt;
        const control = facts.control;
        if (namedKey(symbol)) |named| {
            var command = terminal.KeyCommand{
                .named = named,
                .action = action,
                .shift = shift,
                .alt = alt,
                .control = control,
                .super = facts.super,
                .hyper = facts.hyper,
                .meta = facts.meta,
                .caps_lock = facts.caps_lock,
                .num_lock = facts.num_lock,
            };
            applyModifierKey(&command, named, action != .release);
            self.terminals.?.key(self.layout.focused, command) catch |failure| {
                self.failure = failure;
                return null;
            };
            return .{
                .code = code - 8,
                .target = self.layout.focused,
                .command = .{ .named = command },
            };
        }
        var committed: [terminal.max_input_bytes + 1]u8 = undefined;
        const count = c.xkb_state_key_get_utf8(
            state,
            code,
            &committed,
            committed.len,
        );
        if (count <= 0) return null;
        const len = std.math.cast(usize, count) orelse {
            self.failure = error.input_too_large;
            return null;
        };
        if (len >= committed.len) {
            self.failure = error.input_too_large;
            return null;
        }
        const text = if (action == .release) committed[0..0] else committed[0..len];
        var legacy: [terminal.max_input_bytes]u8 = undefined;
        const legacy_start: usize = if (alt) 1 else 0;
        if (legacy_start + len > legacy.len) {
            self.failure = error.input_too_large;
            return null;
        }
        if (alt) legacy[0] = 0x1b;
        @memcpy(legacy[legacy_start .. legacy_start + len], committed[0..len]);
        if (control and len == 1)
            legacy[legacy_start] = controlByte(legacy[legacy_start]) orelse
                legacy[legacy_start];
        const legacy_text = if (action == .release)
            legacy[0..0]
        else
            legacy[0 .. legacy_start + len];
        const keymap = self.xkb_keymap orelse return null;
        const layout_index = c.xkb_state_key_get_layout(state, code);
        const base_symbol = keySymbolAtLevel(keymap, code, layout_index, 0) orelse symbol;
        const scalar = c.xkb_keysym_to_utf32(base_symbol);
        const shifted_scalar = if (shift) c.xkb_keysym_to_utf32(symbol) else 0;
        if (scalar != 0 and scalar <= std.math.maxInt(u21) and
            std.unicode.utf8ValidCodepoint(@intCast(scalar)))
        {
            var command = terminal.UnicodeKeyCommand{
                .codepoint = @intCast(scalar),
                .shifted = if (shifted_scalar != 0 and
                    shifted_scalar <= std.math.maxInt(u21) and
                    std.unicode.utf8ValidCodepoint(@intCast(shifted_scalar)))
                    @intCast(shifted_scalar)
                else
                    null,
                .text = .{
                    .len = @intCast(text.len),
                    .bytes = .{0} ** terminal.max_input_bytes,
                },
                .legacy = .{
                    .len = @intCast(legacy_text.len),
                    .bytes = .{0} ** terminal.max_input_bytes,
                },
                .action = action,
                .shift = shift,
                .alt = alt,
                .control = control,
                .super = facts.super,
                .hyper = facts.hyper,
                .meta = facts.meta,
                .caps_lock = facts.caps_lock,
                .num_lock = facts.num_lock,
            };
            @memcpy(command.text.bytes[0..text.len], text);
            @memcpy(command.legacy.bytes[0..legacy_text.len], legacy_text);
            self.terminals.?.unicodeKey(self.layout.focused, command) catch |failure| {
                self.failure = failure;
                return null;
            };
            return .{
                .code = code - 8,
                .target = self.layout.focused,
                .command = .{ .unicode = command },
            };
        }
        if (action == .release) return null;
        self.terminals.?.input(self.layout.focused, text) catch |failure| {
            self.failure = failure;
            return null;
        };
        return null;
    }

    fn repeatKey(self: *Window) Error!void {
        var expirations: u64 = 0;
        const count = c.read(self.repeat_fd, &expirations, @sizeOf(u64));
        if (count != @sizeOf(u64) or expirations != 1)
            return error.keyboard_repeat_failed;
        const firing = self.repeat.fire() orelse
            return;
        const index = self.pressed_keys.find(firing.key) orelse
            return error.keyboard_repeat_failed;
        const state = self.xkb_state orelse return error.keyboard_state_failed;
        const repeated = self.pressed_keys.values[index]
            .action(.repeat).modifiers(try readModifiers(state));
        try self.submitPressed(repeated);
        // One-shot cadence coalesces delayed dispatch into one routed key
        // instead of flooding the bounded terminal command queue.
        try self.armRepeat(firing.next_ns);
    }

    fn submitPressed(self: *Window, pressed: PressedKey) Error!void {
        switch (pressed.command) {
            .named => |command| try self.terminals.?.key(pressed.target, command),
            .unicode => |command| try self.terminals.?.unicodeKey(pressed.target, command),
        }
    }

    fn releasePressed(self: *Window) Error!void {
        const facts = if (self.xkb_state) |state|
            try readModifiers(state)
        else
            null;
        while (self.pressed_keys.len != 0) {
            const index = self.pressed_keys.len - 1;
            var released = self.pressed_keys.values[index].action(.release);
            if (facts) |value| released = released.modifiers(value);
            try self.submitPressed(released);
            self.pressed_keys.remove(index);
        }
    }

    fn armRepeat(self: *Window, duration_ns: ?u64) Error!void {
        try setRepeatTimer(self.repeat_fd, duration_ns);
    }

    fn keyboardFocus(self: *Window, focused: bool) void {
        if (self.focused == focused) return;
        self.focused = focused;
        if (!focused) {
            self.repeat.cancel();
            self.armRepeat(null) catch |failure| {
                self.failure = failure;
                return;
            };
            self.releasePressed() catch |failure| {
                self.failure = failure;
                return;
            };
        }
        if (self.terminals) |*terminals|
            terminals.focus(self.layout.focused, focused) catch |failure| {
                self.failure = failure;
            };
    }

    fn pointerMotion(self: *Window, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) void {
        self.pointer_state.position = .{ .x = surface_x, .y = surface_y };
        self.updatePointerTarget();
        self.routePointer(.move, .none, 1);
    }

    fn updatePointerTarget(self: *Window) void {
        if (self.terminals == null) {
            self.pointer_state.target = null;
            return;
        }
        const position = self.pointer_state.position orelse {
            self.pointer_state.target = null;
            return;
        };
        self.pointer_state.target = pointerTarget(
            self.presentation.current,
            &self.presentation.terminals,
            self.cell_size,
            position.x,
            position.y,
        );
    }

    fn pointerButton(self: *Window, button_code: u32, state: u32) void {
        if (self.terminals == null) return;
        self.updatePointerTarget();
        const button: terminal.MouseButton = switch (button_code) {
            c.BTN_LEFT => .left,
            c.BTN_MIDDLE => .middle,
            c.BTN_RIGHT => .right,
            else => return,
        };
        const transition = switch (state) {
            c.WL_POINTER_BUTTON_STATE_PRESSED => self.pointer_state.press(button) orelse return,
            c.WL_POINTER_BUTTON_STATE_RELEASED => self.pointer_state.release(button) orelse return,
            else => return,
        };
        if (self.routePointerTransition(transition)) |failure| {
            if (transition.kind == .press)
                self.pointer_state.undoPress(transition.button);
            self.failure = failure;
        }
    }

    fn pointerWheel(self: *Window, steps: i32) void {
        self.updatePointerTarget();
        const wheel = wheelEvent(steps) catch {
            self.failure = error.invalid_mouse;
            return;
        } orelse return;
        self.routePointer(
            .wheel,
            wheel.button,
            wheel.steps,
        );
    }

    fn routePointer(
        self: *Window,
        kind: terminal.MouseKind,
        button: terminal.MouseButton,
        wheel_steps: u8,
    ) void {
        const target = self.pointer_state.target orelse return;
        if (self.routePointerTo(
            target,
            kind,
            button,
            self.pointer_state.buttons_down,
            wheel_steps,
        )) |failure| self.failure = failure;
    }

    fn routePointerTransition(self: *Window, transition: PointerState.Transition) ?Error {
        return self.routePointerTo(
            transition.target,
            transition.kind,
            transition.button,
            transition.buttons_down,
            1,
        );
    }

    fn routePointerTo(
        self: *Window,
        target: PointerTarget,
        kind: terminal.MouseKind,
        button: terminal.MouseButton,
        buttons_down: u8,
        wheel_steps: u8,
    ) ?Error {
        var shift = false;
        var alt = false;
        var control = false;
        if (self.xkb_state) |state| {
            shift = modifierActive(state, c.XKB_MOD_NAME_SHIFT) catch {
                return error.keyboard_state_failed;
            };
            alt = modifierActive(state, c.XKB_MOD_NAME_ALT) catch {
                return error.keyboard_state_failed;
            };
            control = modifierActive(state, c.XKB_MOD_NAME_CTRL) catch {
                return error.keyboard_state_failed;
            };
        }
        // A pointer-only seat has no keyboard modifier state; its exact
        // modifier snapshot is therefore empty rather than unroutable.
        self.terminals.?.mouse(target.terminal, .{
            .kind = kind,
            .button = button,
            .row = target.row,
            .col = target.col,
            .pixel_x = target.pixel_x,
            .pixel_y = target.pixel_y,
            .shift = shift,
            .alt = alt,
            .control = control,
            .buttons_down = buttons_down,
            .wheel_steps = wheel_steps,
        }) catch |failure| return failure;
        return null;
    }

    fn cancelPointer(self: *Window) ?Error {
        var failure: ?Error = null;
        while (self.pointer_state.cancelNext()) |transition| {
            const cause = self.routePointerTo(
                transition.target,
                transition.kind,
                transition.button,
                transition.buttons_down,
                1,
            );
            if (failure == null) failure = cause;
        }
        return failure;
    }

    fn transitionTerminalFocus(
        self: *Window,
        previous: layout.TerminalId,
        current: layout.TerminalId,
    ) void {
        if (!self.focused or previous == current) return;
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| {
            self.failure = failure;
            return;
        };
        self.terminals.?.focus(previous, false) catch |failure| {
            self.failure = failure;
            return;
        };
        self.terminals.?.focus(current, true) catch |failure| {
            self.failure = failure;
        };
    }

    fn selectTab(self: *Window, tab: u1) void {
        const previous_focus = self.layout.focused;
        const generation = self.layout.generation;
        const snapshot = self.layout.selectTab(tab) catch |failure| {
            self.failure = failure;
            return;
        };
        if (snapshot.generation == generation) return;
        self.transitionTerminalFocus(previous_focus, self.layout.focused);
        if (self.failure != null) return;
        self.presentation.change(snapshot);
        self.terminals.?.resizeVisible(snapshot) catch |failure| {
            self.failure = failure;
            return;
        };
        if (self.presentation.promote(
            &self.terminal_snapshots,
            self.cell_size,
        )) {
            self.updateTitle();
            self.schedule() catch |failure| {
                self.failure = failure;
            };
        }
    }

    fn toggleFocus(self: *Window) void {
        if (self.layout.selected_tab != 0) return;
        const previous_focus = self.layout.focused;
        const terminal_id: layout.TerminalId = if (self.layout.focused == .first) .second else .first;
        const generation = self.layout.generation;
        const snapshot = self.layout.focus(terminal_id) catch |failure| {
            self.failure = failure;
            return;
        };
        if (snapshot.generation == generation) return;
        self.transitionTerminalFocus(previous_focus, self.layout.focused);
        if (self.failure != null) return;
        self.presentation.change(snapshot);
        if (!self.presentation.promote(
            &self.terminal_snapshots,
            self.cell_size,
        )) return;
        self.updateTitle();
        self.schedule() catch |failure| {
            self.failure = failure;
        };
    }

    fn updateTitle(self: *Window) void {
        c.xdg_toplevel_set_title(
            self.toplevel,
            selectedTitle(
                self.presentation.current,
                &self.presentation.terminals,
            ).ptr,
        );
    }

    fn compositorOrError(self: *Window) error{missing}!*c.struct_wl_compositor {
        return self.compositor orelse error.missing;
    }

    fn shellOrError(self: *Window) error{missing}!*c.struct_xdg_wm_base {
        return self.wm_base orelse error.missing;
    }

    fn destroySeat(self: *Window) void {
        if (self.focused) self.keyboardFocus(false);
        if (self.endPointer()) |failure| {
            if (self.failure == null) self.failure = failure;
        }
        if (self.pointer) |pointer| c.wl_pointer_destroy(pointer);
        if (self.xkb_state) |state| c.xkb_state_unref(state);
        if (self.xkb_keymap) |keymap| c.xkb_keymap_unref(keymap);
        if (self.xkb_context) |context| c.xkb_context_unref(context);
        if (self.keyboard) |keyboard| c.wl_keyboard_destroy(keyboard);
        if (self.seat) |seat| c.wl_seat_destroy(seat);
        self.xkb_state = null;
        self.xkb_keymap = null;
        self.xkb_context = null;
        self.keyboard = null;
        self.pointer = null;
        self.seat = null;
        self.seat_name = null;
    }

    fn endPointer(self: *Window) ?Error {
        const failure = if (self.terminals == null) null else self.cancelPointer();
        self.pointer_state.leave();
        return failure;
    }

    fn destroyRegistryObjects(self: *Window) void {
        self.destroySeat();
        if (self.wm_base) |wm_base| c.xdg_wm_base_destroy(wm_base);
        if (self.compositor) |compositor| c.wl_compositor_destroy(compositor);
        self.wm_base = null;
        self.compositor = null;
        self.wm_base_name = null;
        self.compositor_name = null;
    }
};

fn setRepeatTimer(fd: c_int, duration_ns: ?u64) error{keyboard_repeat_failed}!void {
    var timer: c.struct_itimerspec = std.mem.zeroes(c.struct_itimerspec);
    if (c.timerfd_settime(fd, 0, &timer, null) != 0)
        return error.keyboard_repeat_failed;
    // Disarm before draining so replacement and release cannot inherit an
    // already-readable expiration from the previous physical key.
    while (true) {
        var expirations: u64 = 0;
        const count = c.read(fd, &expirations, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) break;
        return error.keyboard_repeat_failed;
    }
    if (duration_ns) |duration| {
        timer.it_value.tv_sec = @intCast(duration / std.time.ns_per_s);
        timer.it_value.tv_nsec = @intCast(duration % std.time.ns_per_s);
        if (c.timerfd_settime(fd, 0, &timer, null) != 0)
            return error.keyboard_repeat_failed;
    }
}

fn keySymbolAtLevel(
    keymap: *c.struct_xkb_keymap,
    code: u32,
    layout_index: u32,
    level: u32,
) ?c.xkb_keysym_t {
    var symbols: [*c]const c.xkb_keysym_t = null;
    const count = c.xkb_keymap_key_get_syms_by_level(
        keymap,
        code,
        layout_index,
        level,
        &symbols,
    );
    if (count != 1 or symbols == null) return null;
    return symbols[0];
}

fn window(data: ?*anyopaque) *Window {
    // Wayland's C listener ABI erases callback data; every registration in
    // this file passes the stable allocation returned by Window.open.
    return @ptrCast(@alignCast(data.?));
}

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self = window(data);
    const name_slice = std.mem.span(interface);
    if (std.mem.eql(u8, name_slice, "wl_compositor") and self.compositor == null) {
        const bound = c.wl_registry_bind(
            registry,
            name,
            &c.wl_compositor_interface,
            @min(version, 4),
        );
        self.compositor = @ptrCast(bound);
        self.compositor_name = name;
    } else if (std.mem.eql(u8, name_slice, "xdg_wm_base") and self.wm_base == null) {
        const bound = c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, 1);
        self.wm_base = @ptrCast(bound);
        self.wm_base_name = name;
    } else if (std.mem.eql(u8, name_slice, "wl_seat") and self.seat == null) {
        const bound = c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 7));
        self.seat = @ptrCast(bound);
        self.seat_name = name;
        if (self.seat == null or
            c.wl_seat_add_listener(self.seat, &seat_listener, self) != 0)
            self.failure = error.keyboard_context_failed;
    }
}

fn registryRemove(
    data: ?*anyopaque,
    _: ?*c.struct_wl_registry,
    name: u32,
) callconv(.c) void {
    const self = window(data);
    if (self.seat_name == name) {
        self.destroySeat();
    } else if (self.compositor_name == name or self.wm_base_name == name) {
        self.failure = error.wayland_dispatch_failed;
    }
}

const registry_listener = c.struct_wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryRemove,
};

fn shellPing(_: ?*anyopaque, base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.c) void {
    c.xdg_wm_base_pong(base, serial);
}

const wm_base_listener = c.struct_xdg_wm_base_listener{ .ping = shellPing };

fn surfaceConfigure(
    data: ?*anyopaque,
    _: ?*c.struct_xdg_surface,
    serial: u32,
) callconv(.c) void {
    window(data).applyConfigure(serial);
}

const xdg_surface_listener = c.struct_xdg_surface_listener{ .configure = surfaceConfigure };

fn toplevelConfigure(
    data: ?*anyopaque,
    _: ?*c.struct_xdg_toplevel,
    width: i32,
    height: i32,
    _: ?*c.struct_wl_array,
) callconv(.c) void {
    const self = window(data);
    self.configure.toplevel(width, height) catch {
        self.failure = error.invalid_configure;
    };
}

fn toplevelClose(data: ?*anyopaque, _: ?*c.struct_xdg_toplevel) callconv(.c) void {
    window(data).closed = true;
}

fn configureBounds(
    _: ?*anyopaque,
    _: ?*c.struct_xdg_toplevel,
    _: i32,
    _: i32,
) callconv(.c) void {}

fn wmCapabilities(
    _: ?*anyopaque,
    _: ?*c.struct_xdg_toplevel,
    _: ?*c.struct_wl_array,
) callconv(.c) void {}

const toplevel_listener = c.struct_xdg_toplevel_listener{
    .configure = toplevelConfigure,
    .close = toplevelClose,
    .configure_bounds = configureBounds,
    .wm_capabilities = wmCapabilities,
};

fn seatCapabilities(
    data: ?*anyopaque,
    seat: ?*c.struct_wl_seat,
    capabilities: u32,
) callconv(.c) void {
    const self = window(data);
    if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0 and self.keyboard == null) {
        self.keyboard = c.wl_seat_get_keyboard(seat);
        if (self.keyboard == null or
            c.wl_keyboard_add_listener(self.keyboard, &keyboard_listener, self) != 0)
        {
            self.failure = error.keyboard_context_failed;
        }
    } else if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD == 0) {
        if (self.keyboard) |keyboard| c.wl_keyboard_destroy(keyboard);
        self.keyboard = null;
    }
    if (capabilities & c.WL_SEAT_CAPABILITY_POINTER != 0 and self.pointer == null) {
        self.pointer = c.wl_seat_get_pointer(seat);
        if (self.pointer == null or
            c.wl_pointer_add_listener(self.pointer, &pointer_listener, self) != 0)
        {
            self.failure = error.wayland_dispatch_failed;
        }
    } else if (capabilities & c.WL_SEAT_CAPABILITY_POINTER == 0) {
        if (self.endPointer()) |failure| {
            if (self.failure == null) self.failure = failure;
        }
        if (self.pointer) |pointer| c.wl_pointer_destroy(pointer);
        self.pointer = null;
    }
}

fn seatName(_: ?*anyopaque, _: ?*c.struct_wl_seat, _: [*c]const u8) callconv(.c) void {}

const seat_listener = c.struct_wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn keyboardKeymap(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    format: u32,
    fd: i32,
    size: u32,
) callconv(.c) void {
    const self = window(data);
    defer {
        if (c.close(fd) != 0) self.failure = error.keyboard_map_failed;
    }
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 or size == 0) {
        self.failure = error.keyboard_map_failed;
        return;
    }
    const bytes = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (bytes == c.MAP_FAILED) {
        self.failure = error.keyboard_map_failed;
        return;
    }
    defer {
        if (c.munmap(bytes, size) != 0) self.failure = error.keyboard_map_failed;
    }
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse {
        self.failure = error.keyboard_context_failed;
        return;
    };
    const keymap = c.xkb_keymap_new_from_string(
        context,
        @ptrCast(bytes),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse {
        c.xkb_context_unref(context);
        self.failure = error.keyboard_map_failed;
        return;
    };
    const state = c.xkb_state_new(keymap) orelse {
        c.xkb_keymap_unref(keymap);
        c.xkb_context_unref(context);
        self.failure = error.keyboard_state_failed;
        return;
    };
    if (self.xkb_state) |old| c.xkb_state_unref(old);
    if (self.xkb_keymap) |old| c.xkb_keymap_unref(old);
    if (self.xkb_context) |old| c.xkb_context_unref(old);
    self.xkb_context = context;
    self.xkb_keymap = keymap;
    self.xkb_state = state;
}

fn keyboardEnter(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: ?*c.struct_wl_surface,
    _: ?*c.struct_wl_array,
) callconv(.c) void {
    window(data).keyboardFocus(true);
}

fn keyboardLeave(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: ?*c.struct_wl_surface,
) callconv(.c) void {
    window(data).keyboardFocus(false);
}

fn keyboardKey(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: u32,
    key_code: u32,
    state: u32,
) callconv(.c) void {
    window(data).key(key_code, state);
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
    const self = window(data);
    if (self.xkb_state) |state| {
        const changed_components = c.xkb_state_update_mask(
            state,
            depressed,
            latched,
            locked,
            0,
            0,
            group,
        );
        const known_components: @TypeOf(changed_components) = c.XKB_STATE_MODS_DEPRESSED |
            c.XKB_STATE_MODS_LATCHED |
            c.XKB_STATE_MODS_LOCKED |
            c.XKB_STATE_MODS_EFFECTIVE |
            c.XKB_STATE_LAYOUT_DEPRESSED |
            c.XKB_STATE_LAYOUT_LATCHED |
            c.XKB_STATE_LAYOUT_LOCKED |
            c.XKB_STATE_LAYOUT_EFFECTIVE |
            c.XKB_STATE_LEDS;
        // xkb applies the update before reporting the changed components.
        // Key routing reads that live state; only an unknown ABI bit is a
        // keyboard-state failure because this owner retains no derived cache.
        if (changed_components & ~known_components != 0)
            self.failure = error.keyboard_state_failed;
    }
}

fn keyboardRepeat(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    rate: i32,
    delay: i32,
) callconv(.c) void {
    const self = window(data);
    self.repeat.configure(rate, delay) catch {
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| {
            self.failure = failure;
            return;
        };
        self.failure = error.keyboard_repeat_failed;
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
    surface_x: c.wl_fixed_t,
    surface_y: c.wl_fixed_t,
) callconv(.c) void {
    const self = window(data);
    if (surface != self.surface) {
        if (self.endPointer()) |failure| {
            if (self.failure == null) self.failure = failure;
        }
        return;
    }
    self.pointerMotion(surface_x, surface_y);
}

fn pointerLeave(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: ?*c.struct_wl_surface,
) callconv(.c) void {
    const self = window(data);
    if (self.endPointer()) |failure| {
        if (self.failure == null) self.failure = failure;
    }
}

fn pointerMotion(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    surface_x: c.wl_fixed_t,
    surface_y: c.wl_fixed_t,
) callconv(.c) void {
    window(data).pointerMotion(surface_x, surface_y);
}

fn pointerButton(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: u32,
    button: u32,
    state: u32,
) callconv(.c) void {
    window(data).pointerButton(button, state);
}

fn pointerAxis(
    _: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: u32,
    _: c.wl_fixed_t,
) callconv(.c) void {
    // Continuous distance has no exact terminal wheel-step equivalent.
}

fn pointerFrame(_: ?*anyopaque, _: ?*c.struct_wl_pointer) callconv(.c) void {}

fn pointerAxisSource(
    _: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
) callconv(.c) void {}

fn pointerAxisStop(
    _: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: u32,
) callconv(.c) void {}

fn pointerAxisDiscrete(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    axis: u32,
    discrete: i32,
) callconv(.c) void {
    if (axis == c.WL_POINTER_AXIS_VERTICAL_SCROLL)
        window(data).pointerWheel(discrete);
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

fn frameDone(data: ?*anyopaque, callback: ?*c.struct_wl_callback, _: u32) callconv(.c) void {
    const self = window(data);
    c.wl_callback_destroy(callback);
    self.frame_callback = null;
    if (self.frame.completed()) self.requestFrame() catch |failure| {
        self.frame.failed();
        self.failure = failure;
    };
}

const frame_listener = c.struct_wl_callback_listener{ .done = frameDone };

fn keyAction(symbol: c.xkb_keysym_t) KeyAction {
    return switch (symbol) {
        c.XKB_KEY_F1 => .first_tab,
        c.XKB_KEY_F2 => .second_tab,
        c.XKB_KEY_Tab => .next_terminal,
        c.XKB_KEY_Escape => .close,
        else => .none,
    };
}

fn selectedTitle(
    snapshot: layout.Snapshot,
    terminals: *const [layout.terminal_count]terminal.Snapshot,
) [:0]const u8 {
    for (snapshot.visible()) |placement| {
        if (!placement.focused) continue;
        const title = &terminals[placement.terminal.index()].title;
        if (title.len != 0) return title.sentinelView();
        return fallback_title;
    }
    return fallback_title;
}

fn namedKey(symbol: c.xkb_keysym_t) ?terminal.NamedKey {
    return switch (symbol) {
        c.XKB_KEY_Return => .enter,
        c.XKB_KEY_BackSpace => .backspace,
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
        c.XKB_KEY_Shift_L => .left_shift,
        c.XKB_KEY_Shift_R => .right_shift,
        c.XKB_KEY_Control_L => .left_control,
        c.XKB_KEY_Control_R => .right_control,
        c.XKB_KEY_Alt_L => .left_alt,
        c.XKB_KEY_Alt_R => .right_alt,
        c.XKB_KEY_Super_L => .left_super,
        c.XKB_KEY_Super_R => .right_super,
        c.XKB_KEY_Hyper_L => .left_hyper,
        c.XKB_KEY_Hyper_R => .right_hyper,
        c.XKB_KEY_Meta_L => .left_meta,
        c.XKB_KEY_Meta_R => .right_meta,
        c.XKB_KEY_Caps_Lock => .caps_lock,
        c.XKB_KEY_Num_Lock => .num_lock,
        c.XKB_KEY_KP_0, c.XKB_KEY_KP_Insert => .keypad_0,
        c.XKB_KEY_KP_1, c.XKB_KEY_KP_End => .keypad_1,
        c.XKB_KEY_KP_2, c.XKB_KEY_KP_Down => .keypad_2,
        c.XKB_KEY_KP_3, c.XKB_KEY_KP_Page_Down => .keypad_3,
        c.XKB_KEY_KP_4, c.XKB_KEY_KP_Left => .keypad_4,
        c.XKB_KEY_KP_5, c.XKB_KEY_KP_Begin => .keypad_5,
        c.XKB_KEY_KP_6, c.XKB_KEY_KP_Right => .keypad_6,
        c.XKB_KEY_KP_7, c.XKB_KEY_KP_Home => .keypad_7,
        c.XKB_KEY_KP_8, c.XKB_KEY_KP_Up => .keypad_8,
        c.XKB_KEY_KP_9, c.XKB_KEY_KP_Page_Up => .keypad_9,
        c.XKB_KEY_KP_Decimal, c.XKB_KEY_KP_Delete => .keypad_decimal,
        c.XKB_KEY_KP_Add => .keypad_add,
        c.XKB_KEY_KP_Subtract => .keypad_subtract,
        c.XKB_KEY_KP_Multiply => .keypad_multiply,
        c.XKB_KEY_KP_Divide => .keypad_divide,
        c.XKB_KEY_KP_Separator => .keypad_separator,
        c.XKB_KEY_KP_Equal => .keypad_equal,
        c.XKB_KEY_KP_Enter => .keypad_enter,
        else => null,
    };
}

fn modifierActive(
    state: *c.struct_xkb_state,
    name: [*c]const u8,
) error{keyboard_state_failed}!bool {
    const active = c.xkb_state_mod_name_is_active(
        state,
        name,
        c.XKB_STATE_MODS_EFFECTIVE,
    );
    if (active < 0) return error.keyboard_state_failed;
    return active == 1;
}

fn optionalModifierActive(state: *c.struct_xkb_state, name: [*:0]const u8) bool {
    const active = c.xkb_state_mod_name_is_active(
        state,
        name,
        c.XKB_STATE_MODS_EFFECTIVE,
    );
    return active > 0;
}

fn readModifiers(state: *c.struct_xkb_state) error{keyboard_state_failed}!ModifierFacts {
    return .{
        .shift = try modifierActive(state, c.XKB_MOD_NAME_SHIFT),
        .alt = try modifierActive(state, c.XKB_MOD_NAME_ALT),
        .control = try modifierActive(state, c.XKB_MOD_NAME_CTRL),
        .super = try modifierActive(state, c.XKB_MOD_NAME_LOGO),
        // Meta and Hyper are optional XKB names. Absence is represented as
        // unavailable/false; a present mapping contributes its exact state.
        .hyper = optionalModifierActive(state, "Hyper"),
        .meta = optionalModifierActive(state, "Meta"),
        .caps_lock = try modifierActive(state, c.XKB_MOD_NAME_CAPS),
        .num_lock = try modifierActive(state, c.XKB_MOD_NAME_NUM),
    };
}

fn controlByte(byte: u8) ?u8 {
    return switch (byte) {
        'a'...'z' => byte - 'a' + 1,
        'A'...'Z' => byte - 'A' + 1,
        ' ', '@' => 0,
        '[' => 27,
        '\\' => 28,
        ']' => 29,
        '^' => 30,
        '_' => 31,
        '?' => 127,
        else => null,
    };
}

fn pointerTarget(
    snapshot: layout.Snapshot,
    terminals: *const [layout.terminal_count]terminal.Snapshot,
    cell_size: terminal.CellSize,
    surface_x: c.wl_fixed_t,
    surface_y: c.wl_fixed_t,
) ?PointerTarget {
    if (surface_x < 0 or surface_y < 0) return null;
    const x: u32 = @intCast(c.wl_fixed_to_int(surface_x));
    const y: u32 = @intCast(c.wl_fixed_to_int(surface_y));
    for (snapshot.visible()) |placement| {
        const rect = placement.rect;
        const right = @as(u32, rect.x) + rect.width;
        const bottom = @as(u32, rect.y) + rect.height;
        if (x < rect.x or x >= right or y < rect.y or y >= bottom) continue;
        const local_x = x - rect.x;
        const local_y = y - rect.y;
        const value = terminals[placement.terminal.index()];
        const used_width = @as(u32, value.cols) * cell_size.width;
        const used_height = @as(u32, value.rows) * cell_size.height;
        if (local_x >= used_width or local_y >= used_height) return null;
        return .{
            .terminal = placement.terminal,
            .row = @intCast(local_y / cell_size.height),
            .col = @intCast(local_x / cell_size.width),
            .pixel_x = @intCast(local_x),
            .pixel_y = @intCast(local_y),
        };
    }
    return null;
}

test "configure coalesces size before one surface acknowledgement" {
    var configure = Configure{};
    try configure.toplevel(800, 480);
    try configure.toplevel(1000, 600);
    const completed = configure.complete(91);
    try std.testing.expectEqual(@as(u32, 91), completed.serial);
    try std.testing.expectEqual(
        layout.Size{ .width = 1000, .height = 600 },
        completed.size.?,
    );
    try std.testing.expect(configure.configured);
    try std.testing.expect(configure.complete(92).size == null);
    try std.testing.expectError(error.invalid_configure, configure.toplevel(-1, 20));
    try configure.toplevel(0, 0);
    try std.testing.expect(configure.complete(93).size == null);
}

test "frame gate coalesces changes and requests only after completion" {
    var frame = FrameGate{};
    try std.testing.expect(frame.changed());
    try std.testing.expect(!frame.changed());
    try std.testing.expect(frame.completed());
    try std.testing.expect(!frame.completed());
    frame.failed();
    try std.testing.expect(frame.changed());
}

test "presentation waits for hidden tab geometry before one promotion" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const initial = try value.snapshot();
    var snapshots = presentationSnapshots(initial, cell_size);
    var presentation = Presentation.init(initial, snapshots);
    const second = try value.selectTab(1);
    presentation.change(second);
    try std.testing.expect(!presentation.promote(&snapshots, cell_size));
    try std.testing.expectEqual(@as(u1, 0), presentation.current.tab);
    setSnapshotGeometry(
        &snapshots[layout.TerminalId.third.index()],
        second.placements[0],
        cell_size,
    );
    try std.testing.expect(presentation.promote(&snapshots, cell_size));
    try std.testing.expectEqual(@as(u1, 1), presentation.current.tab);
}

test "presentation coalesces rapid resize publications to latest geometry" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const initial = try value.snapshot();
    const initial_snapshots = presentationSnapshots(initial, cell_size);
    var presentation = Presentation.init(initial, initial_snapshots);
    const intermediate = try value.resize(.{ .width = 96, .height = 32 });
    presentation.change(intermediate);
    const latest = try value.resize(.{ .width = 112, .height = 48 });
    presentation.change(latest);
    var snapshots = presentationSnapshots(intermediate, cell_size);
    try std.testing.expect(!presentation.refresh(
        .first,
        &snapshots[layout.TerminalId.first.index()],
        cell_size,
    ));
    try std.testing.expect(!presentation.promote(&snapshots, cell_size));
    try std.testing.expectEqual(initial.generation, presentation.current.generation);
    try std.testing.expectEqual(
        @as(u16, 5),
        presentation.terminals[layout.TerminalId.first.index()].cols,
    );
    for (latest.visible()) |placement|
        setSnapshotGeometry(
            &snapshots[placement.terminal.index()],
            placement,
            cell_size,
        );
    try std.testing.expect(presentation.promote(&snapshots, cell_size));
    try std.testing.expectEqual(latest.generation, presentation.current.generation);
    try std.testing.expectEqual(latest.size, presentation.current.size);
    try std.testing.expectEqual(
        @as(u16, 7),
        presentation.terminals[layout.TerminalId.first.index()].cols,
    );
}

test "focused terminal title follows split and tab selection with fallback" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const first_tab = try value.snapshot();
    var snapshots = presentationSnapshots(first_tab, cell_size);
    snapshots[layout.TerminalId.first.index()].title =
        try testMetadata("first");
    snapshots[layout.TerminalId.second.index()].title =
        try testMetadata("second");
    try std.testing.expectEqualStrings(
        "first",
        selectedTitle(first_tab, &snapshots),
    );

    const second_focus = try value.focus(.second);
    try std.testing.expectEqualStrings(
        "second",
        selectedTitle(second_focus, &snapshots),
    );

    const second_tab = try value.selectTab(1);
    try std.testing.expectEqualStrings(
        fallback_title,
        selectedTitle(second_tab, &snapshots),
    );
    snapshots[layout.TerminalId.third.index()].title =
        try testMetadata("third");
    try std.testing.expectEqualStrings(
        "third",
        selectedTitle(second_tab, &snapshots),
    );
}

test "keyboard vocabulary is exact and bounded" {
    try std.testing.expectEqual(KeyAction.first_tab, keyAction(c.XKB_KEY_F1));
    try std.testing.expectEqual(KeyAction.second_tab, keyAction(c.XKB_KEY_F2));
    try std.testing.expectEqual(KeyAction.next_terminal, keyAction(c.XKB_KEY_Tab));
    try std.testing.expectEqual(KeyAction.close, keyAction(c.XKB_KEY_Escape));
    try std.testing.expectEqual(KeyAction.none, keyAction(c.XKB_KEY_a));
    try std.testing.expectEqual(terminal.NamedKey.enter, namedKey(c.XKB_KEY_Return).?);
    try std.testing.expectEqual(terminal.NamedKey.page_down, namedKey(c.XKB_KEY_Page_Down).?);
    const keypad_cases = [_]struct {
        symbol: c.xkb_keysym_t,
        expected: terminal.NamedKey,
    }{
        .{ .symbol = c.XKB_KEY_KP_0, .expected = .keypad_0 },
        .{ .symbol = c.XKB_KEY_KP_1, .expected = .keypad_1 },
        .{ .symbol = c.XKB_KEY_KP_2, .expected = .keypad_2 },
        .{ .symbol = c.XKB_KEY_KP_3, .expected = .keypad_3 },
        .{ .symbol = c.XKB_KEY_KP_4, .expected = .keypad_4 },
        .{ .symbol = c.XKB_KEY_KP_5, .expected = .keypad_5 },
        .{ .symbol = c.XKB_KEY_KP_6, .expected = .keypad_6 },
        .{ .symbol = c.XKB_KEY_KP_7, .expected = .keypad_7 },
        .{ .symbol = c.XKB_KEY_KP_8, .expected = .keypad_8 },
        .{ .symbol = c.XKB_KEY_KP_9, .expected = .keypad_9 },
        .{ .symbol = c.XKB_KEY_KP_Insert, .expected = .keypad_0 },
        .{ .symbol = c.XKB_KEY_KP_End, .expected = .keypad_1 },
        .{ .symbol = c.XKB_KEY_KP_Down, .expected = .keypad_2 },
        .{ .symbol = c.XKB_KEY_KP_Page_Down, .expected = .keypad_3 },
        .{ .symbol = c.XKB_KEY_KP_Left, .expected = .keypad_4 },
        .{ .symbol = c.XKB_KEY_KP_Begin, .expected = .keypad_5 },
        .{ .symbol = c.XKB_KEY_KP_Right, .expected = .keypad_6 },
        .{ .symbol = c.XKB_KEY_KP_Home, .expected = .keypad_7 },
        .{ .symbol = c.XKB_KEY_KP_Up, .expected = .keypad_8 },
        .{ .symbol = c.XKB_KEY_KP_Page_Up, .expected = .keypad_9 },
        .{
            .symbol = c.XKB_KEY_KP_Decimal,
            .expected = .keypad_decimal,
        },
        .{
            .symbol = c.XKB_KEY_KP_Delete,
            .expected = .keypad_decimal,
        },
        .{ .symbol = c.XKB_KEY_KP_Add, .expected = .keypad_add },
        .{
            .symbol = c.XKB_KEY_KP_Subtract,
            .expected = .keypad_subtract,
        },
        .{
            .symbol = c.XKB_KEY_KP_Multiply,
            .expected = .keypad_multiply,
        },
        .{
            .symbol = c.XKB_KEY_KP_Divide,
            .expected = .keypad_divide,
        },
        .{
            .symbol = c.XKB_KEY_KP_Separator,
            .expected = .keypad_separator,
        },
        .{
            .symbol = c.XKB_KEY_KP_Equal,
            .expected = .keypad_equal,
        },
        .{
            .symbol = c.XKB_KEY_KP_Enter,
            .expected = .keypad_enter,
        },
    };
    for (keypad_cases) |case|
        try std.testing.expectEqual(case.expected, namedKey(case.symbol).?);
    try std.testing.expect(namedKey(c.XKB_KEY_a) == null);
    try std.testing.expectEqual(@as(?u8, 1), controlByte('a'));
    try std.testing.expectEqual(@as(?u8, 27), controlByte('['));
    try std.testing.expectEqual(@as(?u8, 127), controlByte('?'));
    try std.testing.expect(controlByte('1') == null);
}

test "pressed keys retain target identity with bounded exact transitions" {
    var keys: PressedKeys = .{};
    const first = PressedKey{
        .code = 30,
        .target = .first,
        .command = .{ .named = .{
            .named = .left_shift,
            .shift = true,
            .alt = false,
            .control = false,
        } },
    };
    try std.testing.expect(try keys.admit(first.code));
    keys.append(first);
    try std.testing.expect(!(try keys.admit(first.code)));
    const repeated = keys.values[keys.find(first.code).?].action(.repeat);
    try std.testing.expectEqual(layout.TerminalId.first, repeated.target);
    try std.testing.expectEqual(terminal.KeyAction.repeat, repeated.command.named.action);
    const released = repeated.action(.release).modifiers(.{
        .shift = false,
        .alt = false,
        .control = false,
        .super = false,
        .hyper = false,
        .meta = false,
        .caps_lock = true,
        .num_lock = false,
    });
    try std.testing.expectEqual(terminal.KeyAction.release, released.command.named.action);
    try std.testing.expect(!released.command.named.shift);
    try std.testing.expect(released.command.named.caps_lock);
    // A failed terminal submission does not call remove; the accepted press
    // remains available for focus-loss retry or deterministic host cleanup.
    try std.testing.expect(keys.find(first.code) != null);
    keys.remove(keys.find(first.code).?);
    try std.testing.expect(keys.find(first.code) == null);
    // Unknown compositor releases are ignored because they have no accepted
    // press and therefore no terminal lifecycle to complete.

    for (0..pressed_key_capacity) |index| {
        const code: u32 = @intCast(index);
        try std.testing.expect(try keys.admit(code));
        var value = first;
        value.code = code;
        keys.append(value);
    }
    try std.testing.expectError(error.pressed_key_limit, keys.admit(99));
}

test "pointer hit testing targets visible cells without changing keyboard focus" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const first_tab = try value.snapshot();
    const snapshots = presentationSnapshots(first_tab, cell_size);

    const first = pointerTarget(first_tab, &snapshots, cell_size, 8 * 256, 16 * 256).?;
    try std.testing.expectEqual(layout.TerminalId.first, first.terminal);
    try std.testing.expectEqual(@as(u16, 1), first.row);
    try std.testing.expectEqual(@as(u16, 1), first.col);
    try std.testing.expectEqual(@as(u16, 8), first.pixel_x);
    try std.testing.expectEqual(@as(u16, 16), first.pixel_y);

    const second = pointerTarget(first_tab, &snapshots, cell_size, 48 * 256, 0).?;
    try std.testing.expectEqual(layout.TerminalId.second, second.terminal);
    try std.testing.expectEqual(layout.TerminalId.first, value.focused);
    try std.testing.expectEqual(@as(u16, 1), second.col);

    const second_tab = try value.selectTab(1);
    var tab_snapshots = snapshots;
    setSnapshotGeometry(
        &tab_snapshots[layout.TerminalId.third.index()],
        second_tab.placements[0],
        cell_size,
    );
    const third = pointerTarget(second_tab, &tab_snapshots, cell_size, 0, 0).?;
    try std.testing.expectEqual(layout.TerminalId.third, third.terminal);
}

test "pointer hit testing rejects negative clipped and unused pane pixels" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.horizontal, .{ .width = 83, .height = 33 });
    const snapshot = try value.snapshot();
    const snapshots = presentationSnapshots(snapshot, cell_size);

    try std.testing.expect(pointerTarget(snapshot, &snapshots, cell_size, -1, 0) == null);
    try std.testing.expect(pointerTarget(snapshot, &snapshots, cell_size, 0, -1) == null);
    try std.testing.expect(pointerTarget(
        snapshot,
        &snapshots,
        cell_size,
        40 * 256,
        0,
    ) == null);
    try std.testing.expect(pointerTarget(
        snapshot,
        &snapshots,
        cell_size,
        82 * 256,
        32 * 256,
    ) == null);
    try std.testing.expect(pointerTarget(
        snapshot,
        &snapshots,
        cell_size,
        83 * 256,
        0,
    ) == null);
}

test "pointer hit testing follows vertical split geometry" {
    const cell_size = terminal.CellSize{ .width = 8, .height = 16 };
    var value = try layout.Layout.init(.vertical, .{ .width = 80, .height = 64 });
    const snapshot = try value.snapshot();
    const snapshots = presentationSnapshots(snapshot, cell_size);
    const lower = pointerTarget(snapshot, &snapshots, cell_size, 8 * 256, 48 * 256).?;
    try std.testing.expectEqual(layout.TerminalId.second, lower.terminal);
    try std.testing.expectEqual(@as(u16, 1), lower.row);
    try std.testing.expectEqual(@as(u16, 1), lower.col);
}

test "pointer transitions reject duplicates and cancel against press targets" {
    var state = PointerState{
        .target = .{
            .terminal = .second,
            .row = 2,
            .col = 3,
            .pixel_x = 24,
            .pixel_y = 32,
        },
    };
    const left_press = state.press(.left).?;
    try std.testing.expectEqual(terminal.MouseKind.press, left_press.kind);
    try std.testing.expectEqual(layout.TerminalId.second, left_press.target.terminal);
    try std.testing.expect(state.press(.left) == null);
    state.target = .{
        .terminal = .first,
        .row = 1,
        .col = 1,
        .pixel_x = 8,
        .pixel_y = 16,
    };
    const right_press = state.press(.right).?;
    try std.testing.expectEqual(layout.TerminalId.first, right_press.target.terminal);
    try std.testing.expectEqual(@as(u8, 0x05), state.buttons_down);
    const left_release = state.release(.left).?;
    try std.testing.expectEqual(terminal.MouseKind.release, left_release.kind);
    try std.testing.expectEqual(layout.TerminalId.second, left_release.target.terminal);
    try std.testing.expect(state.release(.left) == null);
    try std.testing.expectEqual(@as(u8, 0x04), state.buttons_down);
    const cancellation = state.cancelNext().?;
    try std.testing.expectEqual(terminal.MouseKind.release, cancellation.kind);
    try std.testing.expectEqual(layout.TerminalId.first, cancellation.target.terminal);
    try std.testing.expectEqual(@as(u8, 0), cancellation.buttons_down);
    try std.testing.expect(state.cancelNext() == null);
    state.leave();
    try std.testing.expect(state.target == null);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);

    state.target = left_press.target;
    try std.testing.expect(state.press(.middle) != null);
    state.undoPress(.middle);
    try std.testing.expect(state.release(.middle) == null);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);
    try std.testing.expect(state.press(.middle) != null);
    try std.testing.expect(state.release(.middle) != null);
    state.leave();
}

test "wheel event bounds preserve exact direction and reject extreme work" {
    try std.testing.expect(try wheelEvent(0) == null);
    const up = (try wheelEvent(-@as(i32, terminal.max_wheel_steps))).?;
    try std.testing.expectEqual(terminal.MouseButton.wheel_up, up.button);
    try std.testing.expectEqual(terminal.max_wheel_steps, up.steps);
    const down = (try wheelEvent(terminal.max_wheel_steps)).?;
    try std.testing.expectEqual(terminal.MouseButton.wheel_down, down.button);
    try std.testing.expectEqual(terminal.max_wheel_steps, down.steps);
    try std.testing.expectError(
        error.invalid_mouse,
        wheelEvent(@as(i32, terminal.max_wheel_steps) + 1),
    );
    try std.testing.expectError(error.invalid_mouse, wheelEvent(std.math.minInt(i32)));
}

test "repeat state owns delay cadence replacement and cancellation" {
    var repeat = Repeat{};
    try repeat.configure(25, 400);
    try std.testing.expectEqual(
        @as(?u64, 400 * std.time.ns_per_ms),
        repeat.press(10, true),
    );
    try std.testing.expectEqual(@as(u32, 10), repeat.fire().?.key);
    try std.testing.expectEqual(
        @as(u64, 40 * std.time.ns_per_ms),
        repeat.fire().?.next_ns,
    );

    try std.testing.expectEqual(
        @as(?u64, 400 * std.time.ns_per_ms),
        repeat.press(11, true),
    );
    try std.testing.expect(!repeat.release(10));
    try std.testing.expectEqual(@as(u32, 11), repeat.fire().?.key);
    try std.testing.expect(repeat.release(11));
    try std.testing.expect(repeat.fire() == null);

    try std.testing.expect(repeat.press(12, false) == null);
    try std.testing.expect(repeat.fire() == null);
    try repeat.configure(0, 0);
    try std.testing.expect(repeat.press(13, true) == null);
    repeat.cancel();
    try std.testing.expect(repeat.fire() == null);
    try repeat.configure(std.math.maxInt(i32), std.math.maxInt(i32));
    try std.testing.expectEqual(@as(u64, 1), repeat.interval_ns.?);
    try std.testing.expectEqual(
        @as(u64, std.math.maxInt(i32)) * std.time.ns_per_ms,
        repeat.delay_ns,
    );
    try std.testing.expectError(error.invalid, repeat.configure(-1, 0));
    try std.testing.expectError(error.invalid, repeat.configure(1, -1));
}

test "repeat timer has one monotonic wake and remains idle when disarmed" {
    const fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC | c.TFD_NONBLOCK);
    try std.testing.expect(fd >= 0);
    defer if (c.close(fd) != 0)
        @panic("Linux rejected owned repeat test descriptor cleanup");
    var poll_fd = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    try setRepeatTimer(fd, null);
    try std.testing.expectEqual(@as(usize, 0), try std.posix.poll(&poll_fd, 0));
    try setRepeatTimer(fd, 1);
    try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&poll_fd, 1_000));
    try setRepeatTimer(fd, null);
    poll_fd[0].revents = 0;
    try std.testing.expectEqual(@as(usize, 0), try std.posix.poll(&poll_fd, 0));
    try setRepeatTimer(fd, 1);
    try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&poll_fd, 1_000));
    var expirations: u64 = 0;
    try std.testing.expectEqual(
        @as(isize, @sizeOf(u64)),
        c.read(fd, &expirations, @sizeOf(u64)),
    );
    try std.testing.expectEqual(@as(u64, 1), expirations);
    try setRepeatTimer(fd, null);
    poll_fd[0].revents = 0;
    try std.testing.expectEqual(@as(usize, 0), try std.posix.poll(&poll_fd, 0));
}

fn presentationSnapshots(
    snapshot: layout.Snapshot,
    cell_size: terminal.CellSize,
) [layout.terminal_count]terminal.Snapshot {
    var values: [layout.terminal_count]terminal.Snapshot = undefined;
    for (std.enums.values(layout.TerminalId)) |id| values[id.index()] = .{
        .terminal = id,
        .generation = 1,
        .rows = 24,
        .cols = 80,
        .cursor_row = 0,
        .cursor_col = 0,
        .cursor_visible = true,
        .count = 24 * 80,
        .cells = .{terminal.Cell{ .codepoint = 0, .width = 1 }} **
            terminal.max_cells,
    };
    for (snapshot.visible()) |placement|
        setSnapshotGeometry(
            &values[placement.terminal.index()],
            placement,
            cell_size,
        );
    return values;
}

fn setSnapshotGeometry(
    snapshot: *terminal.Snapshot,
    placement: layout.Placement,
    cell_size: terminal.CellSize,
) void {
    snapshot.cols = @max(@as(u16, 1), placement.rect.width / cell_size.width);
    snapshot.rows = @max(@as(u16, 1), placement.rect.height / cell_size.height);
    snapshot.count = @as(u32, snapshot.cols) * snapshot.rows;
}

fn testMetadata(bytes: []const u8) !terminal.Metadata {
    if (bytes.len > terminal.metadata_max_bytes)
        return error.TestMetadataTooLong;
    var value = terminal.Metadata{};
    @memcpy(value.bytes[0..bytes.len], bytes);
    value.len = @intCast(bytes.len);
    return value;
}
