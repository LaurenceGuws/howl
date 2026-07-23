//! Owns one Wayland window, one Control terminal, retained visuals, and render admission.

const std = @import("std");
const clipboard = @import("clipboard.zig");
const control = @import("howl_control");
const howl_render = @import("howl_render");
const renderer = @import("renderer.zig");
const viewport = @import("viewport.zig");
const terminal_render = howl_render.terminal;
const text = howl_render.terminal_text;

const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("errno.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("poll.h");
    @cInclude("stdlib.h");
    @cInclude("sys/eventfd.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/timerfd.h");
    @cInclude("unistd.h");
    @cInclude("wayland-client.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-keysyms.h");
    @cInclude("xdg-system-bell-v1-client-protocol.h");
    @cInclude("xdg-shell-client-protocol.h");
});

const initial_size = Size{ .width = 960, .height = 600 };
const initial_rows: u16 = 24;
const initial_cols: u16 = 80;
const font_pixel_height: u16 = 18;
const selection_style = terminal_render.SelectionStyle{
    .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee },
    .background = .{ .r = 0xd6, .g = 0x5d, .b = 0x0e },
};

// Bounds dimensions before Wayland and EGL C integer narrowing.
const max_dimension: u32 = 8_192;

const Size = struct { width: u32, height: u32 };
const KeyInput = @FieldType(control.Input, "key");
const KeyAction = @FieldType(KeyInput, "action");
const KeyModifiers = @FieldType(KeyInput, "mods");
const MouseInput = @FieldType(control.Input, "mouse");
const MouseButton = @FieldType(MouseInput, "button");
const MouseKind = @FieldType(MouseInput, "kind");
const ClipboardAction = enum { copy, paste };
const physical_key_count: usize = @as(usize, c.KEY_MAX) + 1;
const max_wheel_steps: usize = 32;
const max_bells_per_turn: u8 = 32;
const default_title = "Howl";
const clipboard_poll_count = 1 + clipboard.max_sends;

const PresentationChange = struct {
    title: bool,
    bells: u8,
    bells_pending: bool,
};

const PresentationState = struct {
    title: [control.title_max_bytes + 1]u8 = @splat(0),
    title_len: u16 = 0,
    title_set: bool = false,
    bell_generation: u64 = 0,

    fn apply(self: *PresentationState, facts: control.HostPresentation, bell_available: bool) PresentationChange {
        const reported_title = facts.titleBytes();
        // Wayland title strings are UTF-8 C strings; an invalid child report
        // leaves the last admitted compositor title intact.
        const next_title = if (reported_title) |bytes|
            if (std.unicode.utf8ValidateSlice(bytes) and std.mem.indexOfScalar(u8, bytes, 0) == null)
                bytes
            else
                null
        else
            null;
        const title_accepted = reported_title == null or next_title != null;
        const title_changed = title_accepted and (self.title_set != (next_title != null) or
            if (next_title) |bytes|
                !std.mem.eql(u8, self.title[0..self.title_len], bytes)
            else
                false);
        if (title_changed) {
            self.title_set = next_title != null;
            self.title_len = if (next_title) |bytes| @intCast(bytes.len) else 0;
            if (next_title) |bytes| @memcpy(self.title[0..bytes.len], bytes);
            self.title[self.title_len] = 0;
        }
        std.debug.assert(facts.bell_generation >= self.bell_generation);
        if (!bell_available) {
            self.bell_generation = facts.bell_generation;
            return .{ .title = title_changed, .bells = 0, .bells_pending = false };
        }
        const pending = facts.bell_generation - self.bell_generation;
        const bells: u8 = @intCast(@min(pending, max_bells_per_turn));
        self.bell_generation += bells;
        return .{
            .title = title_changed,
            .bells = bells,
            .bells_pending = self.bell_generation != facts.bell_generation,
        };
    }

    fn titlePointer(self: *const PresentationState) [*:0]const u8 {
        return if (self.title_set) @ptrCast(&self.title) else default_title;
    }
};

// Wayland key events use Linux input-event codes, whose inclusive bound is
// KEY_MAX from linux/input-event-codes.h.
const PhysicalKeys = struct {
    admitted: std.StaticBitSet(physical_key_count) = .initEmpty(),

    fn canPress(self: *const PhysicalKeys, code: u32) bool {
        return code <= c.KEY_MAX and !self.admitted.isSet(@intCast(code));
    }

    fn admitPress(self: *PhysicalKeys, code: u32) void {
        std.debug.assert(self.canPress(code));
        self.admitted.set(@intCast(code));
    }

    fn canRelease(self: *const PhysicalKeys, code: u32) bool {
        return code <= c.KEY_MAX and self.admitted.isSet(@intCast(code));
    }

    fn admitRelease(self: *PhysicalKeys, code: u32) void {
        std.debug.assert(self.canRelease(code));
        self.admitted.unset(@intCast(code));
    }

    fn clear(self: *PhysicalKeys) void {
        self.admitted = .initEmpty();
    }
};

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

    fn firing(self: *const Repeat) ?struct { key: u32, next_ns: u64 } {
        return .{ .key = self.key orelse return null, .next_ns = self.interval_ns orelse return null };
    }

    fn cancel(self: *Repeat) void {
        self.key = null;
    }
};

const KeyboardMap = struct {
    context: *c.struct_xkb_context,
    keymap: *c.struct_xkb_keymap,
    state: *c.struct_xkb_state,

    fn init(text_bytes: [*:0]const u8) error{ KeyboardContext, KeyboardMap, KeyboardState }!KeyboardMap {
        const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse
            return error.KeyboardContext;
        const keymap = c.xkb_keymap_new_from_string(
            context,
            text_bytes,
            c.XKB_KEYMAP_FORMAT_TEXT_V1,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        ) orelse {
            c.xkb_context_unref(context);
            return error.KeyboardMap;
        };
        const state = c.xkb_state_new(keymap) orelse {
            c.xkb_keymap_unref(keymap);
            c.xkb_context_unref(context);
            return error.KeyboardState;
        };
        return .{ .context = context, .keymap = keymap, .state = state };
    }

    fn deinit(self: *KeyboardMap) void {
        c.xkb_state_unref(self.state);
        c.xkb_keymap_unref(self.keymap);
        c.xkb_context_unref(self.context);
        self.* = undefined;
    }
};

const PointerTarget = struct {
    row: i32,
    col: u16,
    pixel_x: u32,
    pixel_y: u32,
};

const PointerPosition = struct { x: u32, y: u32 };

const ButtonTransition = struct {
    index: usize,
    target: PointerTarget,
    buttons_down: u8,
};

const PointerState = struct {
    position: ?PointerPosition = null,
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
        self.pressed[transition.index] = null;
        self.buttons_down = transition.buttons_down;
    }

    fn commitMove(self: *PointerState, target: PointerTarget) void {
        for (&self.pressed) |*pressed| {
            if (pressed.* != null) pressed.* = target;
        }
    }

    fn clear(self: *PointerState) void {
        self.* = .{};
    }
};

const AxisFrame = struct {
    vertical_discrete: i32 = 0,
    saw_continuous: bool = false,
    source: ?u32 = null,

    fn discrete(self: *AxisFrame, value: i32) error{Pointer}!void {
        const sum = std.math.add(i32, self.vertical_discrete, value) catch return error.Pointer;
        if (@abs(@as(i64, sum)) > max_wheel_steps) return error.Pointer;
        self.vertical_discrete = sum;
    }

    fn clear(self: *AxisFrame) void {
        self.* = .{};
    }
};

/// Reports exact executable construction, dispatch, projection, or rendering failure.
pub const Error = std.mem.Allocator.Error || clipboard.Error || control.InitError || control.InputError ||
    control.SelectionError ||
    control.ResizeError || control.ReaderError || terminal_render.Error || renderer.Error || error{
    InvalidSize,
    GeometryUnstable,
    WaylandConnect,
    WaylandRegistry,
    WaylandProtocol,
    WaylandDispatch,
    WaylandFlush,
    Poll,
    InputIncomplete,
    KeyboardContext,
    KeyboardMap,
    KeyboardRepeat,
    KeyboardState,
    Pointer,
    TerminalSignal,
    VisualInspectionDeclined,
    StaleVisualInspection,
    GenerationExhausted,
};

const GridSize = struct { rows: u16, cols: u16 };

const TerminalWake = struct {
    pending: std.atomic.Value(bool) = .init(true),
    fd: c_int,
};

const DrawProgress = struct {
    submitted: u64 = 0,
    completed: u64 = 0,
    final: ?u64 = null,

    fn next(self: DrawProgress) error{GenerationExhausted}!u64 {
        if (self.submitted == std.math.maxInt(u64)) return error.GenerationExhausted;
        return self.submitted + 1;
    }

    fn admit(self: *DrawProgress, generation: u64) void {
        std.debug.assert(generation == self.submitted + 1);
        self.submitted = generation;
        if (self.final != null) self.final = generation;
    }

    fn finish(self: *DrawProgress) void {
        self.final = self.submitted;
    }

    fn complete(self: *DrawProgress, generation: u64) void {
        std.debug.assert(generation >= self.completed);
        std.debug.assert(generation <= self.submitted);
        self.completed = generation;
    }

    fn done(self: DrawProgress) bool {
        return if (self.final) |generation| self.completed >= generation else false;
    }
};

const VisualStorage = struct {
    allocator: std.mem.Allocator,
    cells: []terminal_render.Cell,
    scratch: []terminal_render.Cell,
    row_geometry: []terminal_render.LineGeometry,
    patches: []terminal_render.RowPatch,
    rows: u16,
    cols: u16,
    baseline: ?terminal_render.ProjectionBaseline = null,

    fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!VisualStorage {
        const cell_count = @as(usize, rows) * cols;
        const all_cells = try allocator.alloc(terminal_render.Cell, cell_count * 2);
        errdefer allocator.free(all_cells);
        const geometry = try allocator.alloc(terminal_render.LineGeometry, rows);
        errdefer allocator.free(geometry);
        const patches = try allocator.alloc(terminal_render.RowPatch, rows);
        return .{
            .allocator = allocator,
            .cells = all_cells[0..cell_count],
            .scratch = all_cells[cell_count..],
            .row_geometry = geometry,
            .patches = patches,
            .rows = rows,
            .cols = cols,
        };
    }

    fn deinit(self: *VisualStorage) void {
        self.allocator.free(self.cells.ptr[0 .. self.cells.len + self.scratch.len]);
        self.allocator.free(self.row_geometry);
        self.allocator.free(self.patches);
        self.* = undefined;
    }

    fn capture(self: *VisualStorage, terminal: *control.Terminal) Error!bool {
        var attempts: u8 = 0;
        while (attempts < 4) : (attempts += 1) {
            var context = ProjectionContext{ .storage = self };
            const inspection = terminal.inspectVisual(&context, projectVisual);
            if (context.failure) |failure| return failure;
            if (context.projected) {
                switch (inspection) {
                    .acknowledged, .already_acknowledged => {},
                    .stale => return error.StaleVisualInspection,
                    .declined => return error.VisualInspectionDeclined,
                }
                return context.changed;
            }
            if (inspection == .stale) return error.StaleVisualInspection;
            std.debug.assert(inspection == .declined);
            const required_rows = context.required_rows orelse return error.GeometryUnstable;
            const required_cols = context.required_cols orelse return error.GeometryUnstable;
            var replacement = try VisualStorage.init(self.allocator, required_rows, required_cols);
            var replacement_context = ProjectionContext{ .storage = &replacement };
            const replacement_inspection = terminal.inspectVisual(&replacement_context, projectVisual);
            if (replacement_context.failure) |failure| {
                replacement.deinit();
                return failure;
            }
            if (!replacement_context.projected) {
                if (replacement_inspection == .stale) {
                    replacement.deinit();
                    return error.StaleVisualInspection;
                }
                std.debug.assert(replacement_inspection == .declined);
                replacement.deinit();
                continue;
            }
            switch (replacement_inspection) {
                .acknowledged, .already_acknowledged => {},
                .stale => {
                    replacement.deinit();
                    return error.StaleVisualInspection;
                },
                .declined => {
                    replacement.deinit();
                    return error.VisualInspectionDeclined;
                },
            }
            const previous = self.*;
            self.* = replacement;
            replacement = previous;
            replacement.deinit();
            return true;
        }
        return error.GeometryUnstable;
    }

    fn apply(self: *VisualStorage, update: terminal_render.Update) void {
        std.debug.assert(update.rows == self.rows and update.cols == self.cols);
        for (update.row_patches) |patch| {
            std.debug.assert(patch.row < self.rows);
            std.debug.assert(patch.start_col <= self.cols);
            std.debug.assert(patch.cell_count <= self.cols - patch.start_col);
            const destination = @as(usize, patch.row) * self.cols + patch.start_col;
            const source_end = patch.cell_offset + patch.cell_count;
            std.debug.assert(source_end <= update.cells.len);
            @memcpy(
                self.cells[destination..][0..patch.cell_count],
                update.cells[patch.cell_offset..source_end],
            );
            self.row_geometry[patch.row] = patch.geometry;
        }
        self.baseline = update.next_baseline;
    }
};

const ProjectionContext = struct {
    storage: *VisualStorage,
    failure: ?terminal_render.Error = null,
    projected: bool = false,
    changed: bool = false,
    required_rows: ?u16 = null,
    required_cols: ?u16 = null,
};

const Window = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    display: *c.struct_wl_display,
    registry: *c.struct_wl_registry,
    compositor: ?*c.struct_wl_compositor = null,
    wm_base: ?*c.struct_xdg_wm_base = null,
    system_bell: ?*c.struct_xdg_system_bell_v1 = null,
    seat: ?*c.struct_wl_seat = null,
    data_device_manager: ?*c.struct_wl_data_device_manager = null,
    data_device: ?*c.struct_wl_data_device = null,
    pending_offer: ?*c.struct_wl_data_offer = null,
    pending_offer_mimes: clipboard.Offer = .{},
    selection_offer: ?*c.struct_wl_data_offer = null,
    selection_offer_mimes: clipboard.Offer = .{},
    data_source: ?*c.struct_wl_data_source = null,
    keyboard: ?*c.struct_wl_keyboard = null,
    pointer: ?*c.struct_wl_pointer = null,
    keymap: ?KeyboardMap = null,
    keyboard_focused: bool = false,
    surface: ?*c.struct_wl_surface = null,
    xdg_surface: ?*c.struct_xdg_surface = null,
    toplevel: ?*c.struct_xdg_toplevel = null,
    terminal_signal: c_int,
    repeat_signal: c_int,
    repeat: Repeat = .{},
    physical_keys: PhysicalKeys = .{},
    pointer_state: PointerState = .{},
    axis_frame: AxisFrame = .{},
    viewport_state: viewport.State = .{},
    viewport_drag: ?viewport.Drag = null,
    selection_drag: bool = false,
    clipboard_transfers: clipboard.Transfers,
    selection_serial: u32 = 0,
    wake: TerminalWake,
    render: ?*renderer.Renderer = null,
    terminal: ?*control.Terminal = null,
    visual: ?VisualStorage = null,
    size: Size = initial_size,
    pending_size: Size = initial_size,
    configured: bool = false,
    closed: bool = false,
    failure: ?Error = null,
    draw: DrawProgress = .{},
    terminal_failure: ?control.ReaderError = null,
    presentation: PresentationState = .{},

    fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        runtime_dir: []const u8,
        font_path: []const u8,
        shell: []const u8,
        command: ?[]const u8,
    ) Error!*Window {
        if (font_path.len == 0) return error.FontOpen;
        const display = c.wl_display_connect(null) orelse return error.WaylandConnect;
        var display_owned = true;
        errdefer if (display_owned) c.wl_display_disconnect(display);
        const registry = c.wl_display_get_registry(display) orelse return error.WaylandRegistry;
        var registry_owned = true;
        errdefer if (registry_owned) c.wl_registry_destroy(registry);
        const terminal_signal = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (terminal_signal < 0) return error.TerminalSignal;
        var signal_owned = true;
        errdefer if (signal_owned) closeOwned(terminal_signal);
        const repeat_signal = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC | c.TFD_NONBLOCK);
        if (repeat_signal < 0) return error.KeyboardRepeat;
        var repeat_owned = true;
        errdefer if (repeat_owned) closeOwned(repeat_signal);
        const self = try allocator.create(Window);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .display = display,
            .registry = registry,
            .terminal_signal = terminal_signal,
            .repeat_signal = repeat_signal,
            .wake = .{ .fd = terminal_signal },
            .clipboard_transfers = clipboard.Transfers.init(allocator),
        };
        display_owned = false;
        registry_owned = false;
        signal_owned = false;
        repeat_owned = false;
        errdefer self.rollback();

        if (c.wl_registry_add_listener(registry, &registry_listener, self) != 0)
            return error.WaylandRegistry;
        if (c.wl_display_roundtrip(display) < 0) return error.WaylandDispatch;
        if (self.failure) |failure| return failure;
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
        c.xdg_toplevel_set_title(toplevel, default_title);
        c.wl_surface_commit(surface);
        while (!self.configured and self.failure == null) {
            if (c.wl_display_dispatch(display) < 0) return error.WaylandDispatch;
        }
        if (self.failure) |failure| return failure;

        const configs = fontConfigs(font_path);
        self.render = try renderer.Renderer.start(allocator, io, .{
            .display = @ptrCast(display),
            .surface = @ptrCast(surface),
            .size = pixelSize(self.size),
            .rows = initial_rows,
            .cols = initial_cols,
            .fonts = &configs,
        });
        const metrics = self.render.?.metrics();
        const grid = gridSize(self.size, metrics);
        self.terminal = try control.Terminal.init(allocator, io, .{
            .runtime_dir = runtime_dir,
            .shell = shell,
            .command = command,
            .rows = grid.rows,
            .cols = grid.cols,
            .cell_pixels = .{ .width = metrics.width_px, .height = metrics.height_px },
        }, .{ .context = &self.wake, .notify = terminalWake });
        if (self.keyboard_focused) sendFocus(self, .in);
        if (self.failure) |failure| return failure;
        self.visual = try VisualStorage.init(allocator, grid.rows, grid.cols);
        self.viewport_state.reconcile(viewportFacts(self.terminal.?.viewportFacts()));
        var captured = false;
        while (true) {
            self.terminal.?.consumeWake();
            if (try self.visual.?.capture(self.terminal.?)) captured = true;
            if (!self.wake.pending.swap(false, .acq_rel)) break;
        }
        self.applyTerminalPresentation();
        if (!captured) return error.GeometryUnstable;
        try self.submitVisual(self.size);
        if (self.terminal.?.state() != .running) self.finishTerminal();
        return self;
    }

    fn runLoop(self: *Window) Error!void {
        while (!self.closed) {
            if (c.wl_display_dispatch_pending(self.display) < 0) return error.WaylandDispatch;
            if (self.failure) |failure| return failure;
            if (!std.meta.eql(self.pending_size, self.size)) try self.applyResize();
            if (self.draw.done()) break;

            while (c.wl_display_prepare_read(self.display) != 0) {
                if (c.wl_display_dispatch_pending(self.display) < 0)
                    return error.WaylandDispatch;
                if (self.failure) |failure| return failure;
            }
            var read_prepared = true;
            defer if (read_prepared) c.wl_display_cancel_read(self.display);
            const flush = c.wl_display_flush(self.display);
            const flush_blocked = flush < 0 and std.posix.errno(flush) == .AGAIN;
            if (flush < 0 and !flush_blocked) return error.WaylandFlush;
            var fds: [4 + clipboard_poll_count]std.posix.pollfd = undefined;
            fds[0] = .{
                .fd = c.wl_display_get_fd(self.display),
                .events = std.posix.POLL.IN |
                    if (flush_blocked) @as(i16, std.posix.POLL.OUT) else 0,
                .revents = 0,
            };
            fds[1] = .{ .fd = self.terminal_signal, .events = std.posix.POLL.IN, .revents = 0 };
            fds[2] = .{ .fd = self.render.?.signalFd(), .events = std.posix.POLL.IN, .revents = 0 };
            fds[3] = .{ .fd = self.repeat_signal, .events = std.posix.POLL.IN, .revents = 0 };
            const clipboard_count = self.clipboard_transfers.pollDescriptors(fds[4..]);
            const active_fds = fds[0 .. 4 + clipboard_count];
            const ready_count = std.posix.poll(active_fds, -1) catch return error.Poll;
            std.debug.assert(ready_count != 0);
            const faults = std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL;
            if (fds[0].revents & faults != 0) return error.WaylandDispatch;
            if (fds[1].revents & faults != 0) return error.TerminalSignal;
            if (fds[2].revents & faults != 0) return error.Signal;
            if (fds[3].revents & faults != 0) return error.KeyboardRepeat;

            if (fds[0].revents & std.posix.POLL.IN != 0) {
                if (c.wl_display_read_events(self.display) < 0) return error.WaylandDispatch;
                read_prepared = false;
            } else {
                c.wl_display_cancel_read(self.display);
                read_prepared = false;
            }
            if (c.wl_display_dispatch_pending(self.display) < 0) return error.WaylandDispatch;
            if (fds[0].revents & std.posix.POLL.OUT != 0) {
                const resumed = c.wl_display_flush(self.display);
                if (resumed < 0 and std.posix.errno(resumed) != .AGAIN)
                    return error.WaylandFlush;
            }
            if (fds[2].revents & std.posix.POLL.IN != 0)
                self.draw.complete(try self.render.?.completedGeneration());
            if (fds[1].revents & std.posix.POLL.IN != 0) try self.handleTerminalWake();
            if (!self.closed and fds[3].revents & std.posix.POLL.IN != 0) try self.repeatKey();
            for (fds[4 .. 4 + clipboard_count]) |descriptor|
                if (descriptor.revents != 0)
                    try self.clipboard_transfers.service(descriptor.fd, descriptor.revents);
            if (self.clipboard_transfers.received()) |text_bytes| {
                defer self.clipboard_transfers.finishReceive();
                if (!try self.admitBatch(&.{.{ .input = .{ .paste = text_bytes } }}))
                    return error.InputIncomplete;
            }
            if (self.failure) |failure| return failure;
        }
        if (self.terminal_failure) |failure| return failure;
    }

    fn handleTerminalWake(self: *Window) Error!void {
        try drainEvent(self.terminal_signal);
        while (self.wake.pending.swap(false, .acq_rel)) {
            const terminal = self.terminal.?;
            terminal.consumeWake();
            self.viewport_state.reconcile(viewportFacts(terminal.viewportFacts()));
            try self.captureAndSubmit();
            if (terminal.state() != .running) self.finishTerminal();
        }
        self.applyTerminalPresentation();
    }

    fn applyTerminalPresentation(self: *Window) void {
        const bell = self.system_bell;
        const change = self.presentation.apply(self.terminal.?.hostPresentation(), bell != null);
        if (change.title) c.xdg_toplevel_set_title(self.toplevel.?, self.presentation.titlePointer());
        for (0..change.bells) |_| c.xdg_system_bell_v1_ring(bell.?, self.surface.?);
        if (change.bells_pending) terminalWake(&self.wake);
    }

    fn captureAndSubmit(self: *Window) Error!void {
        const terminal = self.terminal.?;
        if (try self.visual.?.capture(terminal)) try self.submitVisual(self.size);
    }

    fn submitVisual(self: *Window, size: Size) Error!void {
        const visual = &self.visual.?;
        const next = try self.draw.next();
        try self.render.?.submit(.{
            .generation = next,
            .rows = visual.rows,
            .cols = visual.cols,
            .cells = visual.cells,
            .row_geometry = visual.row_geometry,
            .cursor = visual.baseline.?.cursor,
            .size = pixelSize(size),
            .scrollbar = viewport.scrollbar(
                self.viewport_state.facts,
                size.width,
                size.height,
                self.render.?.metrics().width_px,
                self.render.?.metrics().height_px,
            ),
        });
        self.draw.admit(next);
    }

    fn applyResize(self: *Window) Error!void {
        const target = self.pending_size;
        const terminal = self.terminal.?;
        const grid = gridSize(target, self.render.?.metrics());
        const status = terminal.status();
        var geometry_changed = false;
        if (terminal.state() == .running and
            (status.rows != grid.rows or status.cols != grid.cols))
        {
            const resized = terminal.resize(grid.cols, grid.rows) catch |failure| switch (failure) {
                error.NotStarted => null,
                else => return failure,
            };
            if (resized) |result| {
                std.debug.assert(result.changed);
                geometry_changed = true;
            }
        }
        const visual_changed = try self.visual.?.capture(terminal);
        if (geometry_changed and !visual_changed) return error.GeometryUnstable;
        self.viewport_state.reconcile(viewportFacts(terminal.viewportFacts()));
        try self.submitVisual(target);
        self.size = target;
        if (terminal.state() != .running) self.finishTerminal();
    }

    fn finishTerminal(self: *Window) void {
        self.draw.finish();
        if (self.terminal_failure == null)
            self.terminal_failure = self.terminal.?.readerError();
    }

    fn key(self: *Window, code: u32, state_value: u32) void {
        if (!inputAdmissionOpen(self.closed, self.failure)) return;
        const action: KeyAction = switch (state_value) {
            c.WL_KEYBOARD_KEY_STATE_PRESSED => .press,
            c.WL_KEYBOARD_KEY_STATE_RELEASED => .release,
            else => return,
        };
        if (action == .release) {
            if (!self.physical_keys.canRelease(code)) return;
            if (self.repeat.release(code)) self.armRepeat(null) catch |failure| {
                retainFailure(self, failure);
            };
        } else {
            if (!self.physical_keys.canPress(code)) return;
            self.repeat.cancel();
            self.armRepeat(null) catch |failure| {
                retainFailure(self, failure);
                return;
            };
        }
        if (!self.routeKey(code, action)) return;
        if (action == .release) {
            self.physical_keys.admitRelease(code);
            return;
        }
        self.physical_keys.admitPress(code);
        if (self.failure != null) return;
        const keymap = self.keymap orelse return;
        const delay = self.repeat.press(code, c.xkb_keymap_key_repeats(keymap.keymap, code + 8) == 1);
        self.armRepeat(delay) catch |failure| retainFailure(self, failure);
    }

    fn routeKey(self: *Window, code: u32, action: KeyAction) bool {
        const state = if (self.keymap) |keymap| keymap.state else return false;
        const symbol = c.xkb_state_key_get_one_sym(state, code + 8);
        const modifiers = keyModifiers(state);
        if (clipboardAction(symbol, modifiers)) |clipboard_action| {
            if (action == .press) switch (clipboard_action) {
                .copy => self.copySelectionToClipboard() catch |failure| retainFailure(self, failure),
                .paste => self.requestClipboardPaste() catch |failure| retainFailure(self, failure),
            };
            return true;
        }
        if (viewportMove(symbol, modifiers)) |move| {
            if (action != .release) self.applyViewport(move);
            return true;
        }
        var bytes: [64]u8 = undefined;
        const count = c.xkb_state_key_get_utf8(state, code + 8, &bytes, bytes.len);
        if (count < 0 or count >= bytes.len) return false;
        const text_bytes = if (action == .release) bytes[0..0] else bytes[0..@intCast(count)];
        const input = keyInput(symbol, text_bytes, modifiers, action) orelse return false;
        const result = self.terminal.?.send(&.{.{ .input = input }}) catch |failure| {
            retainFailure(self, failure);
            return false;
        };
        switch (result.outcome) {
            .complete => return true,
            .incomplete, .rejected => {
                retainFailure(self, error.InputIncomplete);
                return false;
            },
        }
    }

    fn repeatKey(self: *Window) Error!void {
        var expirations: u64 = 0;
        while (true) {
            const count = c.read(self.repeat_signal, &expirations, @sizeOf(u64));
            if (count == @sizeOf(u64)) break;
            if (count < 0 and std.posix.errno(count) == .INTR) continue;
            return error.KeyboardRepeat;
        }
        if (expirations == 0) return error.KeyboardRepeat;
        const firing = self.repeat.firing() orelse return;
        if (!self.physical_keys.canRelease(firing.key)) {
            self.repeat.cancel();
            try self.armRepeat(null);
            return;
        }
        if (self.routeKey(firing.key, .repeat)) try self.armRepeat(firing.next_ns);
    }

    fn armRepeat(self: *Window, duration_ns: ?u64) error{KeyboardRepeat}!void {
        try setRepeatTimer(self.repeat_signal, duration_ns);
    }

    fn pointerMotion(self: *Window, x: i64, y: i64) void {
        if (!inputAdmissionOpen(self.closed, self.failure)) return;
        if (self.selection_drag) {
            const point = self.selectionPoint(x, y) orelse return;
            self.terminal.?.select(.{ .update = point });
            return;
        }
        const position = self.surfacePosition(x, y) orelse {
            self.pointer_state.position = null;
            return;
        };
        self.pointer_state.position = position;
        if (self.viewport_drag) |drag| {
            self.applyViewportAbsolute(drag.offset(y, self.viewport_state.facts.history_count));
            return;
        }
        const target = self.pointerTarget(x, y) orelse {
            return;
        };
        if (!self.sendMouse(target, .move, .none, self.pointer_state.buttons_down)) return;
        self.pointer_state.commitMove(target);
    }

    fn pointerButton(self: *Window, button_code: u32, state_value: u32) void {
        if (!inputAdmissionOpen(self.closed, self.failure)) return;
        const button: MouseButton = switch (button_code) {
            c.BTN_LEFT => .left,
            c.BTN_MIDDLE => .middle,
            c.BTN_RIGHT => .right,
            else => return,
        };
        const index: usize = switch (button) {
            .left => 0,
            .middle => 1,
            .right => 2,
            else => unreachable,
        };
        switch (state_value) {
            c.WL_POINTER_BUTTON_STATE_PRESSED => {
                const position = self.pointer_state.position orelse return;
                if (button == .left) {
                    if (self.currentScrollbar()) |value| if (value.begin(position.x, position.y)) |drag| {
                        self.viewport_drag = drag;
                        self.applyViewportAbsolute(drag.offset(position.y, value.history_count));
                        return;
                    };
                }
                if (button == .left and self.selectionOwnsPointer()) {
                    const point = self.selectionPoint(position.x, position.y) orelse return;
                    self.terminal.?.select(.{ .start = point });
                    self.selection_drag = true;
                    return;
                }
                const target = self.pointerTarget(position.x, position.y) orelse return;
                const transition = self.pointer_state.preparePress(index, target) orelse return;
                if (!self.sendMouse(target, .press, button, transition.buttons_down)) return;
                self.pointer_state.commitPress(transition);
            },
            c.WL_POINTER_BUTTON_STATE_RELEASED => {
                if (button == .left and self.selection_drag) {
                    self.terminal.?.select(.finish);
                    self.selection_drag = false;
                    return;
                }
                if (button == .left and self.viewport_drag != null) {
                    if (self.pointer_state.position) |position|
                        self.applyViewportAbsolute(self.viewport_drag.?.offset(
                            position.y,
                            self.viewport_state.facts.history_count,
                        ));
                    self.viewport_drag = null;
                    return;
                }
                const transition = self.pointer_state.prepareRelease(index) orelse return;
                if (!self.sendMouse(transition.target, .release, button, transition.buttons_down)) return;
                self.pointer_state.commitRelease(transition);
            },
            else => {},
        }
    }

    fn pointerWheel(self: *Window, discrete: i32) void {
        if (discrete == 0 or !inputAdmissionOpen(self.closed, self.failure)) return;
        if (!self.viewport_state.facts.mouse_reporting) {
            self.applyViewport(.{ .lines = -discrete });
            return;
        }
        const position = self.pointer_state.position orelse return;
        const target = self.pointerTarget(position.x, position.y) orelse return;
        const magnitude: usize = @intCast(@abs(@as(i64, discrete)));
        std.debug.assert(magnitude <= max_wheel_steps);
        var events: [max_wheel_steps]control.BatchEvent = undefined;
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
        if (!self.sendBatch(events[0..magnitude])) return;
    }

    fn pointerTarget(self: *Window, x: i64, y: i64) ?PointerTarget {
        const visual = if (self.visual) |*value| value else return null;
        const render = self.render orelse return null;
        return resolvePointerTarget(x, y, visual.rows, visual.cols, render.metrics());
    }

    fn surfacePosition(self: *Window, x: i64, y: i64) ?PointerPosition {
        if (x < 0 or y < 0 or x >= self.size.width or y >= self.size.height) return null;
        return .{ .x = @intCast(x), .y = @intCast(y) };
    }

    fn currentScrollbar(self: *Window) ?viewport.Scrollbar {
        const render = self.render orelse return null;
        const metrics = render.metrics();
        return viewport.scrollbar(
            self.viewport_state.facts,
            self.size.width,
            self.size.height,
            metrics.width_px,
            metrics.height_px,
        );
    }

    fn applyViewport(self: *Window, move: viewport.Move) void {
        self.applyViewportAbsolute(self.viewport_state.requested(move));
    }

    fn applyViewportAbsolute(self: *Window, offset: u32) void {
        if (!inputAdmissionOpen(self.closed, self.failure)) return;
        const terminal = self.terminal orelse return;
        if (terminal.state() != .running) return;
        self.viewport_state.reconcile(viewportFacts(terminal.setViewport(offset)));
    }

    fn selectionOwnsPointer(self: *Window) bool {
        return selectionOverridesMouse(
            self.viewport_state.facts.mouse_reporting,
            self.mouseModifiers(),
        );
    }

    fn selectionPoint(self: *Window, x: i64, y: i64) ?control.SelectionPoint {
        const visual = if (self.visual) |*value| value else return null;
        const metrics = if (self.render) |render| render.metrics() else return null;
        return resolveSelectionPoint(x, y, visual.rows, visual.cols, metrics);
    }

    fn copySelectionToClipboard(self: *Window) Error!void {
        const manager = self.data_device_manager orelse return error.WaylandProtocol;
        const device = self.data_device orelse return error.WaylandProtocol;
        if (self.selection_serial == 0) return error.WaylandProtocol;
        const terminal = self.terminal orelse return error.InputIncomplete;
        const bytes = terminal.copySelection(self.allocator, clipboard.max_bytes) catch |failure| switch (failure) {
            error.SelectionUnavailable => return,
            else => return failure,
        };
        errdefer self.allocator.free(bytes);
        const source = c.wl_data_device_manager_create_data_source(manager) orelse
            return error.WaylandProtocol;
        errdefer c.wl_data_source_destroy(source);
        if (c.wl_data_source_add_listener(source, &data_source_listener, self) != 0)
            return error.WaylandProtocol;
        c.wl_data_source_offer(source, clipboard.Mime.utf8.bytes());
        c.wl_data_source_offer(source, clipboard.Mime.plain.bytes());
        try self.clipboard_transfers.replaceSource(bytes);
        if (self.data_source) |prior| c.wl_data_source_destroy(prior);
        self.data_source = source;
        c.wl_data_device_set_selection(device, source, self.selection_serial);
    }

    fn requestClipboardPaste(self: *Window) Error!void {
        const offer = self.selection_offer orelse return;
        const mime = self.selection_offer_mimes.preferred() orelse return;
        if (self.clipboard_transfers.receiving()) return error.ClipboardBusy;
        const fds = try clipboard.pipe();
        var read_owned = true;
        errdefer if (read_owned) closeOwned(fds[0]);
        defer closeOwned(fds[1]);
        try self.clipboard_transfers.beginReceive(fds[0]);
        read_owned = false;
        c.wl_data_offer_receive(offer, mime.bytes(), fds[1]);
    }

    fn sendMouse(
        self: *Window,
        target: PointerTarget,
        kind: MouseKind,
        button: MouseButton,
        buttons_down: u8,
    ) bool {
        return self.admitMouse(target, kind, button, buttons_down) catch |failure| {
            retainFailure(self, failure);
            return false;
        };
    }

    fn admitMouse(
        self: *Window,
        target: PointerTarget,
        kind: MouseKind,
        button: MouseButton,
        buttons_down: u8,
    ) Error!bool {
        return self.admitBatch(&.{.{ .input = .{ .mouse = .{
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

    fn sendBatch(self: *Window, events: []const control.BatchEvent) bool {
        return self.admitBatch(events) catch |failure| {
            retainFailure(self, failure);
            return false;
        };
    }

    fn admitBatch(self: *Window, events: []const control.BatchEvent) Error!bool {
        const terminal = self.terminal orelse return false;
        if (terminal.state() != .running) return false;
        const result = try terminal.send(events);
        switch (result.outcome) {
            .complete => return true,
            .incomplete, .rejected => return error.InputIncomplete,
        }
    }

    fn mouseModifiers(self: *Window) @FieldType(MouseInput, "mod") {
        const state = if (self.keymap) |keymap| keymap.state else return .{};
        return keyModifiers(state);
    }

    fn cancelPointer(self: *Window) Error!void {
        self.viewport_drag = null;
        if (self.selection_drag) {
            self.terminal.?.select(.finish);
            self.selection_drag = false;
        }
        for (0..self.pointer_state.pressed.len) |index| {
            const transition = self.pointer_state.prepareRelease(index) orelse continue;
            const button: MouseButton = switch (index) {
                0 => .left,
                1 => .middle,
                2 => .right,
                else => unreachable,
            };
            if (!try self.admitMouse(transition.target, .release, button, transition.buttons_down)) break;
            self.pointer_state.commitRelease(transition);
        }
        self.pointer_state.position = null;
        self.axis_frame.clear();
    }

    fn rollback(self: *Window) void {
        self.deinit() catch |failure| @panic(@errorName(failure));
    }

    fn deinit(self: *Window) Error!void {
        var cleanup_failure = self.failure;
        self.repeat.cancel();
        self.armRepeat(null) catch |failure| {
            retainCleanupFailure(&cleanup_failure, failure);
        };
        self.cancelPointer() catch |failure| retainCleanupFailure(&cleanup_failure, failure);
        self.clipboard_transfers.deinit();
        if (self.visual) |*visual| visual.deinit();
        self.visual = null;
        if (self.terminal) |terminal| terminal.deinit();
        self.terminal = null;
        if (self.render) |render_owner| render_owner.deinit() catch |failure|
            retainCleanupFailure(&cleanup_failure, failure);
        self.render = null;
        closeOwned(self.repeat_signal);
        closeOwned(self.terminal_signal);
        self.destroyProtocol();
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
        if (cleanup_failure) |failure| return failure;
    }

    fn destroyProtocol(self: *Window) void {
        self.destroyKeyboard();
        if (self.pointer) |value| c.wl_pointer_destroy(value);
        self.pointer = null;
        self.pointer_state.clear();
        self.axis_frame.clear();
        if (self.data_source) |value| c.wl_data_source_destroy(value);
        self.data_source = null;
        if (self.pending_offer) |value| c.wl_data_offer_destroy(value);
        self.pending_offer = null;
        if (self.selection_offer) |value| c.wl_data_offer_destroy(value);
        self.selection_offer = null;
        if (self.data_device) |value| c.wl_data_device_release(value);
        self.data_device = null;
        if (self.seat) |value| c.wl_seat_destroy(value);
        self.seat = null;
        if (self.data_device_manager) |value| c.wl_data_device_manager_destroy(value);
        self.data_device_manager = null;
        if (self.system_bell) |value| c.xdg_system_bell_v1_destroy(value);
        self.system_bell = null;
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        self.toplevel = null;
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        self.xdg_surface = null;
        if (self.surface) |value| c.wl_surface_destroy(value);
        self.surface = null;
        if (self.wm_base) |value| c.xdg_wm_base_destroy(value);
        self.wm_base = null;
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        self.compositor = null;
    }

    fn destroyKeyboard(self: *Window) void {
        self.repeat.cancel();
        self.physical_keys.clear();
        if (self.keyboard) |value| c.wl_keyboard_destroy(value);
        self.keyboard = null;
        self.clearKeymap();
    }

    fn clearKeymap(self: *Window) void {
        if (self.keymap) |*keymap| keymap.deinit();
        self.keymap = null;
    }

    fn ensureDataDevice(self: *Window) void {
        if (self.data_device != null) return;
        const manager = self.data_device_manager orelse return;
        const seat = self.seat orelse return;
        const device = c.wl_data_device_manager_get_data_device(manager, seat) orelse {
            retainFailure(self, error.WaylandProtocol);
            return;
        };
        if (c.wl_data_device_add_listener(device, &data_device_listener, self) != 0) {
            c.wl_data_device_release(device);
            retainFailure(self, error.WaylandProtocol);
            return;
        }
        self.data_device = device;
    }
};

/// Runs one terminal window until compositor close, terminal completion, or exact failure.
pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime_dir: []const u8,
    font_path: []const u8,
    shell: []const u8,
    command: ?[]const u8,
) Error!void {
    const window_owner = try Window.init(allocator, io, runtime_dir, font_path, shell, command);
    var primary_failure: ?Error = null;
    window_owner.runLoop() catch |failure| {
        primary_failure = failure;
    };
    window_owner.deinit() catch |cleanup_failure| {
        if (primary_failure) |failure| if (failure != cleanup_failure)
            @panic("window cleanup failed after a distinct runtime failure");
        return cleanup_failure;
    };
    if (primary_failure) |failure| return failure;
}

fn projectVisual(context_pointer: ?*anyopaque, source: control.VisualView) ?control.DirtyToken {
    const context: *ProjectionContext = @ptrCast(@alignCast(context_pointer.?));
    if (source.view.rows != context.storage.rows or source.view.cols != context.storage.cols) {
        context.required_rows = source.view.rows;
        context.required_cols = source.view.cols;
        return null;
    }
    const mode: terminal_render.ProjectMode = if (context.storage.baseline) |baseline|
        .{ .incremental = baseline }
    else
        .full;
    const buffers = terminal_render.Buffers{
        .cells = context.storage.scratch,
        .rows = context.storage.patches,
    };
    const update = terminal_render.project(source, mode, buffers, selection_style) catch |failure| retry: {
        if (failure != error.FullRequired) {
            context.failure = failure;
            return null;
        }
        break :retry terminal_render.project(source, .full, buffers, selection_style) catch |full_failure| {
            context.failure = full_failure;
            return null;
        };
    };
    context.changed = update.full or update.row_patches.len != 0 or
        context.storage.baseline == null or
        !std.meta.eql(context.storage.baseline.?, update.next_baseline);
    context.storage.apply(update);
    context.projected = true;
    return source.dirty_token;
}

fn fontConfigs(path: []const u8) [4]text.FontConfig {
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = path, .pixel_height = font_pixel_height } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = path, .pixel_height = font_pixel_height } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = path, .pixel_height = font_pixel_height } },
        .{
            .key = .{ .slot = 0, .style = .bold_italic },
            .native = .{ .primary = path, .pixel_height = font_pixel_height },
        },
    };
}

fn gridSize(size: Size, metrics: text.CellMetrics) GridSize {
    std.debug.assert(metrics.width_px != 0 and metrics.height_px != 0);
    return .{
        .rows = @intCast(@min(
            @as(u32, control.max_rows),
            @max(@as(u32, 1), size.height / metrics.height_px),
        )),
        .cols = @intCast(@min(
            @as(u32, control.max_cols),
            @max(@as(u32, 1), size.width / metrics.width_px),
        )),
    };
}

fn pixelSize(size: Size) renderer.PixelSize {
    return .{ .width = size.width, .height = size.height };
}

fn validateSize(size: Size) error{InvalidSize}!void {
    if (size.width == 0 or size.height == 0 or
        size.width > max_dimension or size.height > max_dimension)
        return error.InvalidSize;
}

fn configuredSize(current: Size, width: i32, height: i32) error{InvalidSize}!Size {
    if (width < 0 or height < 0) return error.InvalidSize;
    const result = Size{
        .width = if (width == 0) current.width else @intCast(width),
        .height = if (height == 0) current.height else @intCast(height),
    };
    try validateSize(result);
    return result;
}

fn terminalWake(context: ?*anyopaque) void {
    const wake: *TerminalWake = @ptrCast(@alignCast(context.?));
    if (wake.pending.swap(true, .acq_rel)) return;
    signalEvent(wake.fd);
}

fn signalEvent(fd: c_int) void {
    const value: u64 = 1;
    while (true) {
        const count = c.write(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64) or (count < 0 and std.posix.errno(count) == .AGAIN)) return;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        @panic("terminal wake signal failed");
    }
}

fn drainEvent(fd: c_int) error{TerminalSignal}!void {
    while (true) {
        var value: u64 = 0;
        const count = c.read(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) return;
        return error.TerminalSignal;
    }
}

fn closeOwned(fd: c_int) void {
    const result = c.close(fd);
    if (result != 0 and std.posix.errno(result) != .INTR)
        @panic("owned host descriptor close failed");
}

fn closeCallback(self: *Window, fd: c_int) void {
    const result = c.close(fd);
    if (result != 0 and std.posix.errno(result) != .INTR) retainFailure(self, error.KeyboardMap);
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

fn keyModifiers(state: *c.struct_xkb_state) KeyModifiers {
    return .{
        .shift = modifierActive(state, c.XKB_MOD_NAME_SHIFT),
        .alt = modifierActive(state, c.XKB_MOD_NAME_ALT),
        .control = modifierActive(state, c.XKB_MOD_NAME_CTRL),
        .super = modifierActive(state, c.XKB_MOD_NAME_LOGO),
        .caps_lock = modifierActive(state, c.XKB_MOD_NAME_CAPS),
        .num_lock = modifierActive(state, c.XKB_MOD_NAME_NUM),
    };
}

fn viewportMove(symbol: u32, modifiers: KeyModifiers) ?viewport.Move {
    if (!modifiers.control or !modifiers.shift or modifiers.alt or modifiers.super or
        modifiers.hyper or modifiers.meta)
        return null;
    return switch (symbol) {
        c.XKB_KEY_Page_Up => .page_up,
        c.XKB_KEY_Page_Down => .page_down,
        c.XKB_KEY_Home => .top,
        c.XKB_KEY_End => .bottom,
        else => null,
    };
}

fn clipboardAction(symbol: u32, modifiers: KeyModifiers) ?ClipboardAction {
    if (!modifiers.control or !modifiers.shift or modifiers.alt or modifiers.super or
        modifiers.hyper or modifiers.meta)
        return null;
    return switch (symbol) {
        'c', 'C' => .copy,
        'v', 'V' => .paste,
        else => null,
    };
}

fn selectionOverridesMouse(mouse_reporting: bool, modifiers: KeyModifiers) bool {
    if (!mouse_reporting) return true;
    return modifiers.shift and !modifiers.alt and !modifiers.control and !modifiers.super and
        !modifiers.hyper and !modifiers.meta;
}

fn resolveSelectionPoint(
    x: i64,
    y: i64,
    rows: u16,
    cols: u16,
    metrics: text.CellMetrics,
) ?control.SelectionPoint {
    if (rows == 0 or cols == 0 or metrics.width_px == 0 or metrics.height_px == 0)
        return null;
    const col: u16 = if (x <= 0)
        0
    else
        @intCast(@min(@as(u64, @intCast(x)) / metrics.width_px, cols - 1));
    const row: u16 = if (y <= 0)
        0
    else
        @intCast(@min(@as(u64, @intCast(y)) / metrics.height_px, rows - 1));
    return .{ .row = row, .col = col };
}

fn viewportFacts(facts: control.ViewportFacts) viewport.Facts {
    return .{
        .history_count = facts.history_count,
        .offset = facts.offset,
        .rows = facts.rows,
        .alternate_screen = facts.alternate_screen,
        .mouse_reporting = facts.mouse_reporting,
    };
}

fn modifierActive(state: *c.struct_xkb_state, name: [*c]const u8) bool {
    return c.xkb_state_mod_name_is_active(state, name, c.XKB_STATE_MODS_EFFECTIVE) == 1;
}

fn fixedCoordinate(value: c.wl_fixed_t) ?i64 {
    if (value < 0) return null;
    return c.wl_fixed_to_int(value);
}

fn resolvePointerTarget(
    x: i64,
    y: i64,
    rows: u16,
    cols: u16,
    metrics: text.CellMetrics,
) ?PointerTarget {
    if (x < 0 or y < 0 or metrics.width_px == 0 or metrics.height_px == 0) return null;
    const pixel_x: u64 = @intCast(x);
    const pixel_y: u64 = @intCast(y);
    const width = @as(u64, cols) * metrics.width_px;
    const height = @as(u64, rows) * metrics.height_px;
    if (pixel_x >= width or pixel_y >= height) return null;
    return .{
        .row = @intCast(pixel_y / metrics.height_px),
        .col = @intCast(pixel_x / metrics.width_px),
        .pixel_x = @intCast(pixel_x),
        .pixel_y = @intCast(pixel_y),
    };
}

fn keyInput(symbol: u32, text_bytes: []const u8, mods: KeyModifiers, action: KeyAction) ?control.Input {
    const named: ?@FieldType(@FieldType(KeyInput, "key"), "named") = switch (symbol) {
        c.XKB_KEY_Return => .enter,
        c.XKB_KEY_Tab, c.XKB_KEY_ISO_Left_Tab => .tab,
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
        c.XKB_KEY_KP_0 => .keypad_0,
        c.XKB_KEY_KP_1 => .keypad_1,
        c.XKB_KEY_KP_2 => .keypad_2,
        c.XKB_KEY_KP_3 => .keypad_3,
        c.XKB_KEY_KP_4 => .keypad_4,
        c.XKB_KEY_KP_5 => .keypad_5,
        c.XKB_KEY_KP_6 => .keypad_6,
        c.XKB_KEY_KP_7 => .keypad_7,
        c.XKB_KEY_KP_8 => .keypad_8,
        c.XKB_KEY_KP_9 => .keypad_9,
        c.XKB_KEY_KP_Decimal => .keypad_decimal,
        c.XKB_KEY_KP_Add => .keypad_add,
        c.XKB_KEY_KP_Subtract => .keypad_subtract,
        c.XKB_KEY_KP_Multiply => .keypad_multiply,
        c.XKB_KEY_KP_Divide => .keypad_divide,
        c.XKB_KEY_KP_Separator => .keypad_separator,
        c.XKB_KEY_KP_Equal => .keypad_equal,
        c.XKB_KEY_KP_Enter => .keypad_enter,
        else => null,
    };
    const key = if (named) |value|
        @FieldType(KeyInput, "key"){ .named = value }
    else unicode: {
        const scalar = c.xkb_keysym_to_utf32(symbol);
        if (scalar == 0 or scalar > std.math.maxInt(u21)) return null;
        break :unicode @FieldType(KeyInput, "key").initUnicode(@intCast(scalar)) catch return null;
    };
    return .{ .key = .{
        .key = key,
        .mods = mods,
        .action = action,
        .legacy_text = text_bytes,
        .text = text_bytes,
    } };
}

fn sendFocus(self: *Window, focus: @FieldType(control.Input, "focus")) void {
    if (!inputAdmissionOpen(self.closed, self.failure)) return;
    const terminal = self.terminal orelse return;
    if (terminal.state() != .running) return;
    const result = terminal.send(&.{.{ .input = .{ .focus = focus } }}) catch |failure| {
        retainFailure(self, failure);
        return;
    };
    switch (result.outcome) {
        .complete => {},
        .incomplete, .rejected => retainFailure(self, error.InputIncomplete),
    }
}

fn owner(data: ?*anyopaque) *Window {
    return @ptrCast(@alignCast(data.?));
}

fn retainFailure(self: *Window, failure: Error) void {
    if (self.failure == null) self.failure = failure;
}

fn retainCleanupFailure(retained: *?Error, failure: Error) void {
    if (retained.*) |prior| {
        if (prior != failure) @panic("host cleanup failed distinctly after an earlier failure");
    } else {
        retained.* = failure;
    }
}

fn inputAdmissionOpen(closed: bool, failure: ?Error) bool {
    return !closed and failure == null;
}

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    const value = std.mem.span(interface);
    if (std.mem.eql(u8, value, "wl_compositor") and self.compositor == null) {
        self.compositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_compositor_interface,
            @min(version, 4),
        ));
    } else if (std.mem.eql(u8, value, "wl_data_device_manager") and self.data_device_manager == null) {
        self.data_device_manager = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_data_device_manager_interface,
            @min(version, 3),
        ));
        if (self.data_device_manager == null) {
            retainFailure(self, error.WaylandProtocol);
            return;
        }
        self.ensureDataDevice();
    } else if (std.mem.eql(u8, value, "xdg_wm_base") and self.wm_base == null) {
        self.wm_base = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.xdg_wm_base_interface,
            1,
        ));
        const base = self.wm_base orelse {
            retainFailure(self, error.WaylandProtocol);
            return;
        };
        if (c.xdg_wm_base_add_listener(base, &wm_base_listener, self) != 0)
            retainFailure(self, error.WaylandProtocol);
    } else if (std.mem.eql(u8, value, "xdg_system_bell_v1") and self.system_bell == null) {
        self.system_bell = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.xdg_system_bell_v1_interface,
            @min(version, 1),
        ));
        if (self.system_bell == null) retainFailure(self, error.WaylandProtocol);
    } else if (std.mem.eql(u8, value, "wl_seat") and self.seat == null) {
        self.seat = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_seat_interface,
            @min(version, 7),
        ));
        const seat = self.seat orelse {
            retainFailure(self, error.WaylandProtocol);
            return;
        };
        if (c.wl_seat_add_listener(seat, &seat_listener, self) != 0)
            retainFailure(self, error.WaylandProtocol);
        self.ensureDataDevice();
    }
}

fn registryRemove(_: ?*anyopaque, _: ?*c.struct_wl_registry, _: u32) callconv(.c) void {}

const registry_listener = c.struct_wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryRemove,
};

fn shellPing(_: ?*anyopaque, base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.c) void {
    c.xdg_wm_base_pong(base, serial);
}

const wm_base_listener = c.struct_xdg_wm_base_listener{ .ping = shellPing };

fn dataOfferMime(
    data: ?*anyopaque,
    offer: ?*c.struct_wl_data_offer,
    mime: [*c]const u8,
) callconv(.c) void {
    const self = owner(data);
    if (offer != self.pending_offer or mime == null) {
        retainFailure(self, error.WaylandProtocol);
        return;
    }
    self.pending_offer_mimes.admit(std.mem.span(mime));
}

fn dataOfferSourceActions(
    _: ?*anyopaque,
    _: ?*c.struct_wl_data_offer,
    _: u32,
) callconv(.c) void {}

fn dataOfferAction(_: ?*anyopaque, _: ?*c.struct_wl_data_offer, _: u32) callconv(.c) void {}

const data_offer_listener = c.struct_wl_data_offer_listener{
    .offer = dataOfferMime,
    .source_actions = dataOfferSourceActions,
    .action = dataOfferAction,
};

fn dataDeviceOffer(
    data: ?*anyopaque,
    _: ?*c.struct_wl_data_device,
    offer: ?*c.struct_wl_data_offer,
) callconv(.c) void {
    const self = owner(data);
    const value = offer orelse {
        retainFailure(self, error.WaylandProtocol);
        return;
    };
    if (self.pending_offer) |prior| c.wl_data_offer_destroy(prior);
    self.pending_offer = value;
    self.pending_offer_mimes = .{};
    if (c.wl_data_offer_add_listener(value, &data_offer_listener, self) != 0)
        retainFailure(self, error.WaylandProtocol);
}

fn dataDeviceEnter(
    data: ?*anyopaque,
    _: ?*c.struct_wl_data_device,
    serial: u32,
    _: ?*c.struct_wl_surface,
    _: c.wl_fixed_t,
    _: c.wl_fixed_t,
    offer: ?*c.struct_wl_data_offer,
) callconv(.c) void {
    const self = owner(data);
    if (offer) |value| c.wl_data_offer_accept(value, serial, null);
    if (offer != self.pending_offer) retainFailure(self, error.WaylandProtocol);
}

fn dataDeviceLeave(data: ?*anyopaque, _: ?*c.struct_wl_data_device) callconv(.c) void {
    const self = owner(data);
    if (self.pending_offer) |offer| c.wl_data_offer_destroy(offer);
    self.pending_offer = null;
    self.pending_offer_mimes = .{};
}

fn dataDeviceMotion(
    _: ?*anyopaque,
    _: ?*c.struct_wl_data_device,
    _: u32,
    _: c.wl_fixed_t,
    _: c.wl_fixed_t,
) callconv(.c) void {}

fn dataDeviceDrop(data: ?*anyopaque, device: ?*c.struct_wl_data_device) callconv(.c) void {
    dataDeviceLeave(data, device);
}

fn dataDeviceSelection(
    data: ?*anyopaque,
    _: ?*c.struct_wl_data_device,
    offer: ?*c.struct_wl_data_offer,
) callconv(.c) void {
    const self = owner(data);
    if (self.selection_offer) |prior| c.wl_data_offer_destroy(prior);
    self.selection_offer = null;
    self.selection_offer_mimes = .{};
    const value = offer orelse return;
    if (value != self.pending_offer) {
        retainFailure(self, error.WaylandProtocol);
        return;
    }
    self.selection_offer = value;
    self.selection_offer_mimes = self.pending_offer_mimes;
    self.pending_offer = null;
    self.pending_offer_mimes = .{};
}

const data_device_listener = c.struct_wl_data_device_listener{
    .data_offer = dataDeviceOffer,
    .enter = dataDeviceEnter,
    .leave = dataDeviceLeave,
    .motion = dataDeviceMotion,
    .drop = dataDeviceDrop,
    .selection = dataDeviceSelection,
};

fn dataSourceTarget(
    _: ?*anyopaque,
    _: ?*c.struct_wl_data_source,
    _: [*c]const u8,
) callconv(.c) void {}

fn dataSourceSend(
    data: ?*anyopaque,
    source: ?*c.struct_wl_data_source,
    mime: [*c]const u8,
    fd: i32,
) callconv(.c) void {
    const self = owner(data);
    if (source != self.data_source or mime == null) {
        closeOwned(fd);
        retainFailure(self, error.WaylandProtocol);
        return;
    }
    const bytes = std.mem.span(mime);
    if (!std.mem.eql(u8, bytes, clipboard.Mime.utf8.bytes()) and
        !std.mem.eql(u8, bytes, clipboard.Mime.plain.bytes()))
    {
        closeOwned(fd);
        return;
    }
    self.clipboard_transfers.beginSend(fd) catch |failure| retainFailure(self, failure);
}

fn dataSourceCancelled(
    data: ?*anyopaque,
    source: ?*c.struct_wl_data_source,
) callconv(.c) void {
    const self = owner(data);
    if (source != self.data_source) {
        retainFailure(self, error.WaylandProtocol);
        return;
    }
    c.wl_data_source_destroy(source);
    self.data_source = null;
    self.clipboard_transfers.clearSource();
}

fn dataSourceDrop(_: ?*anyopaque, _: ?*c.struct_wl_data_source) callconv(.c) void {}
fn dataSourceFinished(_: ?*anyopaque, _: ?*c.struct_wl_data_source) callconv(.c) void {}
fn dataSourceAction(_: ?*anyopaque, _: ?*c.struct_wl_data_source, _: u32) callconv(.c) void {}

const data_source_listener = c.struct_wl_data_source_listener{
    .target = dataSourceTarget,
    .send = dataSourceSend,
    .cancelled = dataSourceCancelled,
    .dnd_drop_performed = dataSourceDrop,
    .dnd_finished = dataSourceFinished,
    .action = dataSourceAction,
};

fn seatCapabilities(
    data: ?*anyopaque,
    seat: ?*c.struct_wl_seat,
    capabilities: u32,
) callconv(.c) void {
    const self = owner(data);
    if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0 and self.keyboard == null) {
        const keyboard = c.wl_seat_get_keyboard(seat) orelse {
            retainFailure(self, error.WaylandProtocol);
            return;
        };
        if (c.wl_keyboard_add_listener(keyboard, &keyboard_listener, self) != 0) {
            c.wl_keyboard_destroy(keyboard);
            retainFailure(self, error.WaylandProtocol);
            return;
        }
        self.keyboard = keyboard;
    } else if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD == 0) {
        if (self.keyboard_focused) sendFocus(self, .out);
        self.keyboard_focused = false;
        self.armRepeat(null) catch |failure| retainFailure(self, failure);
        self.destroyKeyboard();
    }
    if (capabilities & c.WL_SEAT_CAPABILITY_POINTER != 0 and self.pointer == null) {
        const pointer = c.wl_seat_get_pointer(seat) orelse {
            retainFailure(self, error.WaylandProtocol);
            return;
        };
        if (c.wl_pointer_add_listener(pointer, &pointer_listener, self) != 0) {
            c.wl_pointer_destroy(pointer);
            retainFailure(self, error.WaylandProtocol);
            return;
        }
        self.pointer = pointer;
    } else if (capabilities & c.WL_SEAT_CAPABILITY_POINTER == 0 and self.pointer != null) {
        if (!self.closed) self.cancelPointer() catch |failure| retainFailure(self, failure);
        if (self.pointer) |pointer| c.wl_pointer_destroy(pointer);
        self.pointer = null;
        self.pointer_state.clear();
        self.axis_frame.clear();
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
    const self = owner(data);
    defer closeCallback(self, fd);
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 or size == 0) {
        retainFailure(self, error.KeyboardMap);
        return;
    }
    const bytes = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (bytes == c.MAP_FAILED) {
        retainFailure(self, error.KeyboardMap);
        return;
    }
    defer if (c.munmap(bytes, size) != 0) retainFailure(self, error.KeyboardMap);
    const mapped: [*]const u8 = @ptrCast(bytes);
    if (mapped[size - 1] != 0) {
        retainFailure(self, error.KeyboardMap);
        return;
    }
    var replacement = KeyboardMap.init(@ptrCast(mapped)) catch |failure| {
        retainFailure(self, failure);
        return;
    };
    self.armRepeat(null) catch |failure| {
        replacement.deinit();
        retainFailure(self, failure);
        return;
    };
    self.repeat.cancel();
    self.physical_keys.clear();
    self.clearKeymap();
    self.keymap = replacement;
}

fn keyboardEnter(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: ?*c.struct_wl_surface,
    _: ?*c.struct_wl_array,
) callconv(.c) void {
    const self = owner(data);
    self.repeat.cancel();
    self.physical_keys.clear();
    self.armRepeat(null) catch |failure| retainFailure(self, failure);
    self.keyboard_focused = true;
    sendFocus(self, .in);
}

fn keyboardLeave(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    _: u32,
    _: ?*c.struct_wl_surface,
) callconv(.c) void {
    const self = owner(data);
    self.keyboard_focused = false;
    self.repeat.cancel();
    self.physical_keys.clear();
    self.armRepeat(null) catch |failure| retainFailure(self, failure);
    if (self.selection_offer) |offer| c.wl_data_offer_destroy(offer);
    self.selection_offer = null;
    self.selection_offer_mimes = .{};
    sendFocus(self, .out);
}

fn keyboardKey(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    serial: u32,
    _: u32,
    code: u32,
    state: u32,
) callconv(.c) void {
    const self = owner(data);
    self.selection_serial = serial;
    self.key(code, state);
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
    const self = owner(data);
    const state = if (self.keymap) |keymap| keymap.state else return;
    const changed = c.xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group);
    const known: @TypeOf(changed) = c.XKB_STATE_MODS_DEPRESSED | c.XKB_STATE_MODS_LATCHED |
        c.XKB_STATE_MODS_LOCKED | c.XKB_STATE_MODS_EFFECTIVE |
        c.XKB_STATE_LAYOUT_DEPRESSED | c.XKB_STATE_LAYOUT_LATCHED |
        c.XKB_STATE_LAYOUT_LOCKED | c.XKB_STATE_LAYOUT_EFFECTIVE | c.XKB_STATE_LEDS;
    if (changed & ~known != 0) retainFailure(self, error.KeyboardState);
}

fn keyboardRepeat(
    data: ?*anyopaque,
    _: ?*c.struct_wl_keyboard,
    rate: i32,
    delay: i32,
) callconv(.c) void {
    const self = owner(data);
    self.repeat.configure(rate, delay) catch {
        self.repeat.cancel();
        retainFailure(self, error.KeyboardRepeat);
        return;
    };
    self.armRepeat(null) catch |failure| retainFailure(self, failure);
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
    const self = owner(data);
    if (self.failure != null) return;
    if (surface != self.surface) {
        retainFailure(self, error.WaylandProtocol);
        return;
    }
    self.pointer_state.clear();
    self.axis_frame.clear();
    self.pointerMotion(fixedCoordinate(x) orelse -1, fixedCoordinate(y) orelse -1);
}

fn pointerLeave(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    _: ?*c.struct_wl_surface,
) callconv(.c) void {
    const self = owner(data);
    if (!self.closed and self.failure == null)
        self.cancelPointer() catch |failure| retainFailure(self, failure);
}

fn pointerMotion(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    x: c.wl_fixed_t,
    y: c.wl_fixed_t,
) callconv(.c) void {
    owner(data).pointerMotion(fixedCoordinate(x) orelse -1, fixedCoordinate(y) orelse -1);
}

fn pointerButton(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    serial: u32,
    _: u32,
    button: u32,
    state: u32,
) callconv(.c) void {
    const self = owner(data);
    self.selection_serial = serial;
    self.pointerButton(button, state);
}

fn pointerAxis(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    axis: u32,
    value: c.wl_fixed_t,
) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    switch (axis) {
        c.WL_POINTER_AXIS_VERTICAL_SCROLL => if (value != 0) {
            self.axis_frame.saw_continuous = true;
        },
        c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => {},
        else => retainFailure(self, error.Pointer),
    }
}

fn pointerFrame(data: ?*anyopaque, _: ?*c.struct_wl_pointer) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    const discrete = self.axis_frame.vertical_discrete;
    self.axis_frame.clear();
    // Continuous-only touchpad distance has no protocol-defined wheel-step
    // conversion. It intentionally produces neither VT bytes nor host scroll.
    if (discrete != 0) self.pointerWheel(discrete);
}

fn pointerAxisSource(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    source: u32,
) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    switch (source) {
        c.WL_POINTER_AXIS_SOURCE_WHEEL,
        c.WL_POINTER_AXIS_SOURCE_FINGER,
        c.WL_POINTER_AXIS_SOURCE_CONTINUOUS,
        c.WL_POINTER_AXIS_SOURCE_WHEEL_TILT,
        => self.axis_frame.source = source,
        else => retainFailure(self, error.Pointer),
    }
}

fn pointerAxisStop(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    _: u32,
    axis: u32,
) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    if (axis != c.WL_POINTER_AXIS_VERTICAL_SCROLL and axis != c.WL_POINTER_AXIS_HORIZONTAL_SCROLL)
        retainFailure(self, error.Pointer);
}

fn pointerAxisDiscrete(
    data: ?*anyopaque,
    _: ?*c.struct_wl_pointer,
    axis: u32,
    discrete: i32,
) callconv(.c) void {
    const self = owner(data);
    if (self.failure != null) return;
    switch (axis) {
        c.WL_POINTER_AXIS_VERTICAL_SCROLL => self.axis_frame.discrete(discrete) catch
            retainFailure(self, error.Pointer),
        c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => {},
        else => retainFailure(self, error.Pointer),
    }
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

fn surfaceConfigure(data: ?*anyopaque, surface: ?*c.struct_xdg_surface, serial: u32) callconv(.c) void {
    const self = owner(data);
    c.xdg_surface_ack_configure(surface, serial);
    validateSize(self.pending_size) catch {
        retainFailure(self, error.InvalidSize);
        return;
    };
    if (!self.configured) self.size = self.pending_size;
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
    const self = owner(data);
    self.pending_size = configuredSize(self.pending_size, width, height) catch {
        retainFailure(self, error.InvalidSize);
        return;
    };
}

fn toplevelClose(data: ?*anyopaque, _: ?*c.struct_xdg_toplevel) callconv(.c) void {
    owner(data).closed = true;
}

fn configureBounds(_: ?*anyopaque, _: ?*c.struct_xdg_toplevel, _: i32, _: i32) callconv(.c) void {}
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

test "terminal presentation retains exact title and bounded bell progress" {
    var state = PresentationState{};
    var facts = control.HostPresentation{
        .title_set = false,
        .title = @splat(0),
        .title_len = 0,
        .bell_generation = 0,
    };
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = 0, .bells_pending = false },
        state.apply(facts, true),
    );
    try std.testing.expectEqualStrings(default_title, std.mem.span(state.titlePointer()));

    @memcpy(facts.title[0..5], "build");
    facts.title_set = true;
    facts.title_len = 5;
    facts.bell_generation = 3;
    try std.testing.expectEqual(
        PresentationChange{ .title = true, .bells = 3, .bells_pending = false },
        state.apply(facts, true),
    );
    try std.testing.expectEqualStrings("build", std.mem.span(state.titlePointer()));
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = 0, .bells_pending = false },
        state.apply(facts, true),
    );

    facts.title_len = 0;
    try std.testing.expectEqual(
        PresentationChange{ .title = true, .bells = 0, .bells_pending = false },
        state.apply(facts, true),
    );
    try std.testing.expectEqualStrings("", std.mem.span(state.titlePointer()));
    facts.title_set = false;
    facts.bell_generation = 4;
    try std.testing.expectEqual(
        PresentationChange{ .title = true, .bells = 1, .bells_pending = false },
        state.apply(facts, true),
    );
    try std.testing.expectEqualStrings(default_title, std.mem.span(state.titlePointer()));

    facts.title_set = true;
    facts.title_len = 1;
    facts.title[0] = 0xff;
    facts.bell_generation = 5;
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = 1, .bells_pending = false },
        state.apply(facts, true),
    );
    try std.testing.expectEqualStrings(default_title, std.mem.span(state.titlePointer()));

    facts.title_set = false;
    facts.bell_generation += max_bells_per_turn + 2;
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = max_bells_per_turn, .bells_pending = true },
        state.apply(facts, true),
    );
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = 2, .bells_pending = false },
        state.apply(facts, true),
    );
    facts.bell_generation += 9;
    try std.testing.expectEqual(
        PresentationChange{ .title = false, .bells = 0, .bells_pending = false },
        state.apply(facts, false),
    );
}

test "window dimensions and grid conversion preserve exact bounds" {
    try std.testing.expectError(error.InvalidSize, validateSize(.{ .width = 0, .height = 1 }));
    try std.testing.expectError(error.InvalidSize, validateSize(.{ .width = 1, .height = 0 }));
    try std.testing.expectError(
        error.InvalidSize,
        validateSize(.{ .width = max_dimension + 1, .height = 1 }),
    );
    try std.testing.expectEqual(
        Size{ .width = 90, .height = 24 },
        try configuredSize(.{ .width = 80, .height = 24 }, 90, 0),
    );
    try std.testing.expectEqual(
        GridSize{ .rows = 2, .cols = 4 },
        gridSize(.{ .width = 43, .height = 41 }, .{
            .width_px = 10,
            .height_px = 20,
            .baseline_px = 15,
        }),
    );
    try std.testing.expectEqual(
        GridSize{ .rows = 1, .cols = 1 },
        gridSize(.{ .width = 1, .height = 1 }, .{
            .width_px = 10,
            .height_px = 20,
            .baseline_px = 15,
        }),
    );
}

test "terminal completion waits for the newest admitted draw only" {
    var progress = DrawProgress{};
    const first = try progress.next();
    try std.testing.expectEqual(@as(u64, 1), first);
    // A failed renderer admission does not advance executable ownership.
    try std.testing.expectEqual(@as(u64, 0), progress.submitted);
    progress.admit(first);
    progress.finish();
    try std.testing.expect(!progress.done());

    // Coalesced final state admitted after terminal completion replaces the
    // draw that normal shutdown must observe.
    const final = try progress.next();
    progress.admit(final);
    progress.complete(first);
    try std.testing.expect(!progress.done());
    progress.complete(final);
    try std.testing.expect(progress.done());

    progress.submitted = std.math.maxInt(u64);
    try std.testing.expectError(error.GenerationExhausted, progress.next());
}

test "terminal wake coalescing rearms after an exact drain" {
    const fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (fd < 0) return error.SkipZigTest;
    defer closeOwned(fd);
    var wake = TerminalWake{ .pending = .init(false), .fd = fd };

    terminalWake(&wake);
    terminalWake(&wake);
    try std.testing.expect(wake.pending.load(.acquire));
    try drainEvent(fd);
    try std.testing.expect(wake.pending.swap(false, .acq_rel));

    terminalWake(&wake);
    try std.testing.expect(wake.pending.load(.acquire));
    try drainEvent(fd);
    try std.testing.expect(wake.pending.swap(false, .acq_rel));
    try drainEvent(fd);
}

test "compositor close and first runtime failure revoke input admission" {
    try std.testing.expect(inputAdmissionOpen(false, null));
    try std.testing.expect(!inputAdmissionOpen(true, null));
    try std.testing.expect(!inputAdmissionOpen(false, error.WaylandDispatch));
    try std.testing.expect(!inputAdmissionOpen(true, error.WaylandDispatch));

    var retained: ?Error = error.WaylandDispatch;
    retainCleanupFailure(&retained, error.WaylandDispatch);
    try std.testing.expectEqual(error.WaylandDispatch, retained.?);
}

test "visual storage admits complete and resized control observations" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .rows = 2, .cols = 4 },
        .{},
    );
    defer terminal.deinit();
    var visual = try VisualStorage.init(std.testing.allocator, 2, 4);
    defer visual.deinit();

    try std.testing.expect(try visual.capture(terminal));
    try std.testing.expectEqual(@as(u16, 2), visual.baseline.?.rows);
    try std.testing.expectEqual(@as(u16, 4), visual.baseline.?.cols);
    for (visual.cells) |cell| try std.testing.expectEqual(@as(u21, 0), cell.codepoint);
    for (visual.row_geometry) |geometry|
        try std.testing.expectEqual(terminal_render.LineGeometry.single_width, geometry);
    try std.testing.expect(!try visual.capture(terminal));

    try std.testing.expect((try terminal.resize(5, 3)).changed);
    try std.testing.expect(try visual.capture(terminal));
    try std.testing.expectEqual(@as(u16, 3), visual.rows);
    try std.testing.expectEqual(@as(u16, 5), visual.cols);
}

test "terminal exit retains final visual until its admitted draw completes" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "printf final-state", .rows = 2, .cols = 16 },
        .{},
    );
    defer terminal.deinit();
    var visual = try VisualStorage.init(std.testing.allocator, 2, 16);
    defer visual.deinit();
    var progress = DrawProgress{};

    var attempts: u8 = 0;
    while (attempts < 100) : (attempts += 1) {
        terminal.consumeWake();
        if (try visual.capture(terminal)) {
            const generation = try progress.next();
            progress.admit(generation);
        }
        if (terminal.state() != .running) {
            progress.finish();
            break;
        }
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expectEqual(control.State.stopped, terminal.state());
    try std.testing.expect(visualContains(&visual, "final-state"));
    try std.testing.expect(progress.final != null);
    try std.testing.expect(!progress.done());
    progress.complete(progress.submitted);
    try std.testing.expect(progress.done());
}

test "visual storage allocation failure preserves admitted state" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var visual = try VisualStorage.init(failing.allocator(), 2, 4);
    defer visual.deinit();
    visual.cells[0].codepoint = 'A';
    failing.fail_index = failing.alloc_index;
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .rows = 3, .cols = 5 },
        .{},
    );
    defer terminal.deinit();

    try std.testing.expectError(error.OutOfMemory, visual.capture(terminal));
    try std.testing.expectEqual(@as(u16, 2), visual.rows);
    try std.testing.expectEqual(@as(u16, 4), visual.cols);
    try std.testing.expectEqual(@as(u21, 'A'), visual.cells[0].codepoint);
}

test "font configuration retains every terminal style identity" {
    const configs = fontConfigs("font.ttf");
    try std.testing.expectEqual(text.FontStyle.normal, configs[0].key.style);
    try std.testing.expectEqual(text.FontStyle.bold, configs[1].key.style);
    try std.testing.expectEqual(text.FontStyle.italic, configs[2].key.style);
    try std.testing.expectEqual(text.FontStyle.bold_italic, configs[3].key.style);
    for (configs) |config| {
        try std.testing.expectEqual(@as(u4, 0), config.key.slot);
        try std.testing.expectEqualStrings("font.ttf", config.native.primary);
        try std.testing.expectEqual(font_pixel_height, config.native.pixel_height);
    }
}

test "key translation retains named unicode modifier and transition facts" {
    const mods = KeyModifiers{ .shift = true, .alt = true, .caps_lock = true };
    const up = keyInput(c.XKB_KEY_Up, "", mods, .release).?;
    switch (up) {
        .key => |event| {
            try std.testing.expectEqual(.release, event.action);
            try std.testing.expectEqual(.up, event.key.named);
            try std.testing.expect(event.mods.shift);
            try std.testing.expect(event.mods.alt);
            try std.testing.expect(event.mods.caps_lock);
            try std.testing.expectEqualStrings("", event.text);
        },
        else => unreachable,
    }

    const unicode = keyInput(c.XKB_KEY_eacute, "é", .{}, .press).?;
    switch (unicode) {
        .key => |event| {
            try std.testing.expectEqual(.press, event.action);
            try std.testing.expectEqual(@as(u21, 'é'), event.key.unicode.value);
            try std.testing.expectEqualStrings("é", event.legacy_text);
            try std.testing.expectEqualStrings("é", event.text);
        },
        else => unreachable,
    }
    const modifier = keyInput(c.XKB_KEY_Control_R, "", .{ .control = true }, .release).?;
    try std.testing.expectEqual(.right_control, modifier.key.key.named);
    try std.testing.expectEqual(.release, modifier.key.action);
    const keypad = keyInput(c.XKB_KEY_KP_Enter, "", .{ .num_lock = true }, .press).?;
    try std.testing.expectEqual(.keypad_enter, keypad.key.key.named);
    try std.testing.expect(keyInput(c.XKB_KEY_VoidSymbol, "", .{}, .press) == null);
}

test "viewport key chords require exact host modifiers" {
    const required = KeyModifiers{ .control = true, .shift = true };
    try std.testing.expectEqual(viewport.Move.page_up, viewportMove(c.XKB_KEY_Page_Up, required).?);
    try std.testing.expectEqual(viewport.Move.page_down, viewportMove(c.XKB_KEY_Page_Down, required).?);
    try std.testing.expectEqual(viewport.Move.top, viewportMove(c.XKB_KEY_Home, required).?);
    try std.testing.expectEqual(viewport.Move.bottom, viewportMove(c.XKB_KEY_End, required).?);

    const rejected = [_]KeyModifiers{
        .{ .shift = true },
        .{ .control = true },
        .{ .control = true, .shift = true, .alt = true },
        .{ .control = true, .shift = true, .super = true },
        .{ .control = true, .shift = true, .hyper = true },
        .{ .control = true, .shift = true, .meta = true },
    };
    for (rejected) |modifiers|
        try std.testing.expect(viewportMove(c.XKB_KEY_Page_Up, modifiers) == null);
    try std.testing.expect(viewportMove(c.XKB_KEY_Up, required) == null);
}

test "clipboard chords require exact host modifiers and preserve public keys" {
    const required = KeyModifiers{ .control = true, .shift = true };
    try std.testing.expectEqual(ClipboardAction.copy, clipboardAction('c', required).?);
    try std.testing.expectEqual(ClipboardAction.copy, clipboardAction('C', required).?);
    try std.testing.expectEqual(ClipboardAction.paste, clipboardAction('v', required).?);
    try std.testing.expectEqual(ClipboardAction.paste, clipboardAction('V', required).?);
    try std.testing.expect(clipboardAction('x', required) == null);
    try std.testing.expect(clipboardAction('c', .{ .control = true }) == null);
    try std.testing.expect(clipboardAction('c', .{
        .control = true,
        .shift = true,
        .alt = true,
    }) == null);
}

test "keyboard repeat has one bounded replacement and release owner" {
    var repeat = Repeat{};
    try repeat.configure(25, 400);
    try std.testing.expectEqual(@as(?u64, 400 * std.time.ns_per_ms), repeat.press(30, true));
    try std.testing.expectEqual(@as(u32, 30), repeat.firing().?.key);
    try std.testing.expectEqual(@as(u64, 40 * std.time.ns_per_ms), repeat.firing().?.next_ns);
    try std.testing.expectEqual(@as(?u64, 400 * std.time.ns_per_ms), repeat.press(31, true));
    try std.testing.expect(!repeat.release(30));
    try std.testing.expect(repeat.release(31));
    try std.testing.expect(repeat.firing() == null);
    try repeat.configure(0, 0);
    try std.testing.expect(repeat.press(32, true) == null);
    try std.testing.expectError(error.InvalidRepeat, repeat.configure(-1, 0));
}

test "physical key admission is transactional bounded and teardown-safe" {
    var keys = PhysicalKeys{};
    try std.testing.expect(!keys.canRelease(c.KEY_A));

    // A failed press performs no commit, so its release remains unseen.
    try std.testing.expect(keys.canPress(c.KEY_A));
    try std.testing.expect(!keys.canRelease(c.KEY_A));

    keys.admitPress(c.KEY_A);
    try std.testing.expect(!keys.canPress(c.KEY_A));
    try std.testing.expect(keys.canRelease(c.KEY_A));
    // A failed release performs no commit and remains available for cleanup.
    try std.testing.expect(keys.canRelease(c.KEY_A));
    keys.admitRelease(c.KEY_A);
    try std.testing.expect(!keys.canRelease(c.KEY_A));

    try std.testing.expect(keys.canPress(0));
    keys.admitPress(0);
    try std.testing.expect(keys.canPress(c.KEY_MAX));
    keys.admitPress(c.KEY_MAX);
    try std.testing.expect(!keys.canPress(@as(u32, c.KEY_MAX) + 1));
    try std.testing.expect(!keys.canRelease(@as(u32, c.KEY_MAX) + 1));
    keys.clear();
    try std.testing.expect(!keys.canRelease(0));
    try std.testing.expect(!keys.canRelease(c.KEY_MAX));
}

test "focus-enter held keys and teardown suppress later orphan releases" {
    var keys = PhysicalKeys{};
    var repeat = Repeat{};
    try repeat.configure(30, 200);
    keys.admitPress(c.KEY_B);
    try std.testing.expect(repeat.press(c.KEY_B, true) != null);

    // Focus enter intentionally ignores wl_keyboard.enter's held-key array.
    // Resetting admission means the corresponding later release is suppressed.
    keys.clear();
    repeat.cancel();
    try std.testing.expect(!keys.canRelease(c.KEY_B));
    try std.testing.expect(repeat.firing() == null);

    keys.admitPress(c.KEY_C);
    try std.testing.expect(repeat.press(c.KEY_C, true) != null);
    keys.clear();
    repeat.cancel();
    try std.testing.expect(!keys.canRelease(c.KEY_C));
    try std.testing.expect(repeat.firing() == null);
}

test "pointer pixels resolve exact label-free terminal bounds" {
    const metrics = text.CellMetrics{ .width_px = 10, .height_px = 20, .baseline_px = 15 };
    try std.testing.expectEqual(
        PointerTarget{ .row = 0, .col = 0, .pixel_x = 0, .pixel_y = 0 },
        resolvePointerTarget(0, 0, 2, 4, metrics).?,
    );
    try std.testing.expectEqual(
        PointerTarget{ .row = 1, .col = 3, .pixel_x = 39, .pixel_y = 39 },
        resolvePointerTarget(39, 39, 2, 4, metrics).?,
    );
    try std.testing.expect(resolvePointerTarget(-1, 0, 2, 4, metrics) == null);
    try std.testing.expect(resolvePointerTarget(0, -1, 2, 4, metrics) == null);
    try std.testing.expect(resolvePointerTarget(40, 0, 2, 4, metrics) == null);
    try std.testing.expect(resolvePointerTarget(0, 40, 2, 4, metrics) == null);
    try std.testing.expect(resolvePointerTarget(std.math.maxInt(i64), 0, 2, 4, metrics) == null);
    try std.testing.expect(resolvePointerTarget(0, 0, 2, 4, .{
        .width_px = 0,
        .height_px = 20,
        .baseline_px = 15,
    }) == null);
}

test "selection pointer clamps hostile pixels and Shift exactly overrides mouse reporting" {
    const metrics = text.CellMetrics{ .width_px = 10, .height_px = 20, .baseline_px = 15 };
    try std.testing.expectEqual(
        control.SelectionPoint{ .row = 0, .col = 0 },
        resolveSelectionPoint(std.math.minInt(i64), std.math.minInt(i64), 3, 4, metrics).?,
    );
    try std.testing.expectEqual(
        control.SelectionPoint{ .row = 2, .col = 3 },
        resolveSelectionPoint(std.math.maxInt(i64), std.math.maxInt(i64), 3, 4, metrics).?,
    );
    try std.testing.expectEqual(
        control.SelectionPoint{ .row = 1, .col = 2 },
        resolveSelectionPoint(29, 39, 3, 4, metrics).?,
    );
    try std.testing.expect(resolveSelectionPoint(0, 0, 0, 4, metrics) == null);

    try std.testing.expect(selectionOverridesMouse(false, .{}));
    try std.testing.expect(!selectionOverridesMouse(true, .{}));
    try std.testing.expect(selectionOverridesMouse(true, .{ .shift = true }));
    try std.testing.expect(!selectionOverridesMouse(true, .{ .shift = true, .control = true }));
    try std.testing.expect(!selectionOverridesMouse(true, .{ .shift = true, .alt = true }));
}

test "pointer buttons and drag coordinates commit only after admission" {
    const initial = PointerTarget{ .row = 1, .col = 2, .pixel_x = 20, .pixel_y = 25 };
    const moved = PointerTarget{ .row = 2, .col = 4, .pixel_x = 40, .pixel_y = 45 };
    var state = PointerState{};

    const failed_press = state.preparePress(0, initial).?;
    try std.testing.expectEqual(@as(u8, 0b001), failed_press.buttons_down);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);
    try std.testing.expectEqual(null, state.pressed[0]);
    state.commitPress(failed_press);
    try std.testing.expectEqual(@as(u8, 0b001), state.buttons_down);
    try std.testing.expectEqual(initial, state.pressed[0].?);
    try std.testing.expect(state.preparePress(0, initial) == null);

    // Failed motion preserves the last admitted drag target.
    try std.testing.expectEqual(initial, state.pressed[0].?);
    state.commitMove(moved);
    try std.testing.expectEqual(moved, state.pressed[0].?);
    const failed_release = state.prepareRelease(0).?;
    try std.testing.expectEqual(@as(u8, 0), failed_release.buttons_down);
    try std.testing.expectEqual(moved, failed_release.target);
    try std.testing.expectEqual(moved, state.pressed[0].?);
    state.commitRelease(failed_release);
    try std.testing.expectEqual(null, state.pressed[0]);
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);

    const middle = state.preparePress(1, initial).?;
    state.commitPress(middle);
    const right = state.preparePress(2, initial).?;
    try std.testing.expectEqual(@as(u8, 0b110), right.buttons_down);
    state.commitPress(right);
    state.clear();
    try std.testing.expectEqual(@as(u8, 0), state.buttons_down);
    for (state.pressed) |pressed| try std.testing.expectEqual(null, pressed);
}

test "pointer axis accumulates one bounded frame in callback order" {
    var frame = AxisFrame{};
    frame.source = c.WL_POINTER_AXIS_SOURCE_WHEEL;
    frame.saw_continuous = true;
    try frame.discrete(-2);
    try frame.discrete(1);
    try std.testing.expectEqual(@as(i32, -1), frame.vertical_discrete);
    try std.testing.expectError(error.Pointer, frame.discrete(max_wheel_steps + 2));
    try std.testing.expectEqual(@as(i32, -1), frame.vertical_discrete);
    frame.clear();
    try std.testing.expectEqual(@as(i32, 0), frame.vertical_discrete);
    try std.testing.expectEqual(@as(?u32, null), frame.source);
    try std.testing.expect(!frame.saw_continuous);
}

test "keymap replacement is constructed before prior ownership is released" {
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse return error.SkipZigTest;
    defer c.xkb_context_unref(context);
    const source = c.xkb_keymap_new_from_names(
        context,
        null,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse return error.SkipZigTest;
    defer c.xkb_keymap_unref(source);
    const serialized = c.xkb_keymap_get_as_string(source, c.XKB_KEYMAP_FORMAT_TEXT_V1) orelse
        return error.SkipZigTest;
    defer c.free(serialized);

    var current = try KeyboardMap.init(serialized);
    defer current.deinit();
    try std.testing.expectError(error.KeyboardMap, KeyboardMap.init("not an xkb keymap"));
    try std.testing.expect(c.xkb_state_key_get_one_sym(current.state, 38) != c.XKB_KEY_NoSymbol);

    var replacement = try KeyboardMap.init(serialized);
    current.deinit();
    current = replacement;
    replacement = undefined;
    try std.testing.expect(c.xkb_state_key_get_one_sym(current.state, 38) != c.XKB_KEY_NoSymbol);
    const shift_index = c.xkb_keymap_mod_get_index(current.keymap, c.XKB_MOD_NAME_SHIFT);
    try std.testing.expect(shift_index != c.XKB_MOD_INVALID);
    const shift_mask: c.xkb_mod_mask_t = @as(c.xkb_mod_mask_t, 1) << @intCast(shift_index);
    try std.testing.expect(c.xkb_state_update_mask(current.state, shift_mask, 0, 0, 0, 0, 0) != 0);
    const modifiers = keyModifiers(current.state);
    try std.testing.expect(modifiers.shift);
    try std.testing.expect(!modifiers.alt);
}

test "typed host key uses VT mode encoding before exact PTY transfer" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "stty raw -echo; od -An -tx1 -N3", .rows = 4, .cols = 20 },
        .{},
    );
    defer terminal.deinit();
    const input = keyInput(c.XKB_KEY_Up, "", .{}, .press).?;
    const sent = try terminal.send(&.{.{ .input = input }});
    switch (sent.outcome) {
        .complete => |count| try std.testing.expectEqual(@as(usize, 3), count),
        else => return error.TestUnexpectedResult,
    }

    var visual = try VisualStorage.init(std.testing.allocator, 4, 20);
    defer visual.deinit();
    var found = false;
    var attempts: u8 = 0;
    while (attempts < 100 and !found) : (attempts += 1) {
        terminal.consumeWake();
        const changed = try visual.capture(terminal);
        found = visualContains(&visual, "1b 5b 41");
        if (!changed and terminal.state() != .running and !found) break;
        if (!found) try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expect(found);
}

test "typed mouse uses VT tracking and SGR encoding before PTY transfer" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .command = "printf '\\033[?1000h\\033[?1006h'; stty raw -echo; od -An -tx1 -N9",
            .rows = 4,
            .cols = 20,
            .cell_pixels = .{ .width = 10, .height = 20 },
        },
        .{},
    );
    defer terminal.deinit();
    var attempts: u8 = 0;
    while (attempts < 100 and !terminal.viewportFacts().mouse_reporting) : (attempts += 1) {
        terminal.consumeWake();
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expect(terminal.viewportFacts().mouse_reporting);
    const sent = try terminal.send(&.{.{ .input = .{ .mouse = .{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .pixel_x = 20,
        .pixel_y = 25,
        .mod = .{},
        .buttons_down = 1,
    } } }});
    switch (sent.outcome) {
        .complete => |count| try std.testing.expectEqual(@as(usize, 9), count),
        else => return error.TestUnexpectedResult,
    }

    var visual = try VisualStorage.init(std.testing.allocator, 4, 20);
    defer visual.deinit();
    var found = false;
    attempts = 0;
    while (attempts < 100 and !found) : (attempts += 1) {
        terminal.consumeWake();
        const changed = try visual.capture(terminal);
        found = visualContains(&visual, "1b 5b 3c 30 3b 33 3b 32 4d");
        if (!changed and terminal.state() != .running and !found) break;
        if (!found) try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expect(found);
}

test "clipboard paste remains framed by VT bracketed-paste mode" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .command = "printf '\\033[?2004h'; stty raw -echo; od -An -tx1 -N16",
            .rows = 4,
            .cols = 40,
        },
        .{},
    );
    defer terminal.deinit();
    var attempts: u8 = 0;
    while (attempts < 100 and terminal.status().semantic_sequence == 1) : (attempts += 1) {
        terminal.consumeWake();
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    const sent = try terminal.send(&.{.{ .input = .{ .paste = "clip" } }});
    switch (sent.outcome) {
        .complete => |count| try std.testing.expectEqual(@as(usize, 16), count),
        else => return error.TestUnexpectedResult,
    }

    var visual = try VisualStorage.init(std.testing.allocator, 4, 40);
    defer visual.deinit();
    var found = false;
    attempts = 0;
    while (attempts < 100 and !found) : (attempts += 1) {
        terminal.consumeWake();
        const changed = try visual.capture(terminal);
        found = visualContains(&visual, "1b 5b 32 30 30 7e 63 6c 69 70 1b 5b 32 30 31 7e");
        if (!changed and terminal.state() != .running and !found) break;
        if (!found) try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(5),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expect(found);
}

test "mouse tracking disabled admits no bytes and owns no host scroll" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .rows = 2, .cols = 4 },
        .{},
    );
    defer terminal.deinit();
    const before = terminal.viewportFacts();
    const sent = try terminal.send(&.{.{ .input = .{ .mouse = .{
        .kind = .wheel,
        .button = .wheel_down,
        .row = 0,
        .col = 0,
        .mod = .{ .shift = true },
        .buttons_down = 0,
    } } }});
    switch (sent.outcome) {
        .complete => |count| try std.testing.expectEqual(@as(usize, 0), count),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.meta.eql(before, terminal.viewportFacts()));
}

test "host viewport reconciles only terminal-applied history facts" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .rows = 3, .cols = 5, .history_rows = 8 },
        .{},
    );
    defer terminal.deinit();
    try terminal.consume("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");

    var state = viewport.State{};
    state.reconcile(viewportFacts(terminal.viewportFacts()));
    const requested = state.requested(.page_up);
    try std.testing.expectEqual(@as(u32, 0), state.facts.offset);
    const applied = terminal.setViewport(requested);
    state.reconcile(viewportFacts(applied));
    try std.testing.expectEqual(applied.offset, state.facts.offset);
    try std.testing.expect(!state.follow);

    const reviewed_offset = state.facts.offset;
    try terminal.consume("\r\n5EEEE");
    try std.testing.expectEqual(reviewed_offset, state.facts.offset);
    const advanced = terminal.viewportFacts();
    try std.testing.expect(advanced.offset > reviewed_offset);
    state.reconcile(viewportFacts(advanced));
    try std.testing.expect(!state.follow);

    try terminal.consume("\x1b[?1049h");
    const alternate = terminal.viewportFacts();
    try std.testing.expect(alternate.alternate_screen);
    try std.testing.expectEqual(@as(u32, 0), alternate.offset);
    try std.testing.expectEqual(@as(u32, 0), alternate.history_count);
    state.reconcile(viewportFacts(alternate));
    try std.testing.expectEqual(@as(u32, 0), state.requested(.top));

    try terminal.consume("\x1b[?1049l");
    state.reconcile(viewportFacts(terminal.setViewport(0)));
    try std.testing.expect(state.follow);
    try terminal.consume("\r\n6FFFF");
    state.reconcile(viewportFacts(terminal.viewportFacts()));
    try std.testing.expectEqual(@as(u32, 0), state.facts.offset);
    try std.testing.expect(state.follow);

    const resize_result = try terminal.resize(5, 4);
    try std.testing.expect(resize_result.changed);
    const resized = terminal.viewportFacts();
    try std.testing.expectEqual(@as(u16, 4), resized.rows);
    try std.testing.expect(resized.offset <= resized.history_count);
}

fn visualContains(visual: *const VisualStorage, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var matched: usize = 0;
    for (visual.cells) |cell| {
        if (cell.codepoint == needle[matched]) {
            matched += 1;
            if (matched == needle.len) return true;
        } else {
            matched = if (cell.codepoint == needle[0]) 1 else 0;
        }
    }
    return false;
}
