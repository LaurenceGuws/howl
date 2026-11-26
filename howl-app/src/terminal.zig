const std = @import("std");
const c = @import("desktop");
const app_presentation = @import("presentation.zig");
const pty_vt = @import("pty_vt.zig");
const projection = @import("projection.zig");
const consequences = @import("consequences.zig");
const host_status = @import("program_status.zig");
const vt_output = @import("howl_vt_output");
const vt = @import("howl_vt");
const pty = @import("howl_pty");
const commands = @import("howl_vt_output_commands");
const selection = @import("selection.zig");
const find = @import("find.zig");
const desktop = @import("desktop.zig");
const posix = std.posix;

const queue_limit = 64;
const queue_turn_limit = 16;
const input_byte_limit = 1024 * 1024;

/// Bounded asynchronous semantic input and presentation-geometry intent.
pub const Task = union(enum) {
    input: vt.Terminal.InputEvent,
    resize: struct { rows: u16, columns: u16 },
    scroll: i32,
    seek: u32,
    retry_projection,
    select: Select,
    find: find.Request,
};

/// Selection operations resolve only within the terminal worker.
pub const SelectKind = enum { start, extend, word, row, clear };
/// One copied stable selection intent; only the worker resolves its canonical text.
pub const Select = struct {
    serial: u64,
    kind: SelectKind,
    context: selection.Context,
    point: vt.Terminal.TextPoint = .{ .row = 0, .col = 0 },
};
/// Noncanonical selection failures never stop process/VT service.
pub const SelectionError = error{ InvalidSelection, SelectionContextChanged, SelectionEvicted };
/// Bounded canonical extraction and FIFO admission failures.
pub const CopyError = vt.Terminal.TextError || SelectionError || error{ NoSelection, NoHyperlink, HyperlinkLimit, CopyLimit, TerminalStopped, InputQueueFull, InputBackpressured };
const Link = struct { context: selection.Context, point: vt.Terminal.TextPoint };
const Copy = struct {
    link: ?Link = null,
    allocator: std.mem.Allocator,
    max_bytes: usize,
    result: ?[]const u8 = null,
    failure: ?CopyError = null,
    complete: bool = false,
};

/// Exact failures produced by this terminal worker's owned operations.
pub const Failure = pty_vt.InputError || pty_vt.ResizeError ||
    pty_vt.ServiceError || std.posix.PollError || consequences.Error;

/// Projection failure stays separate from canonical I/O and never stops PTY/VT service.
pub const PresentationFailure = @import("output_state").State(false).FlushError || error{SDLNotification};

/// Immutable cut transfer or lease validation failure.
pub const Frame = projection.Frame;
/// Exact frame replacement and checked retirement failures.
pub const FrameError = projection.ReplaceError;

/// Exact transactional configuration/admission failures; old presentation survives failure.
pub const ConfigureError = projection.ConfigureError || vt_output.PresentationStoreInitError || error{ TerminalStopped, InputQueueFull, InputBackpressured };

const Configuration = struct {
    config: app_presentation.Config,
    surface: ?commands.Size,
    result: ?app_presentation.Geometry = null,
    failure: ?ConfigureError = null,
    complete: bool = false,
};
const Work = union(enum) { intent: Task, configure: *Configuration, copy: *Copy };

fn sharedConfig(config: app_presentation.Config, history_rows: u16) @import("output_state").SharedConfig {
    return .{
        .history_capacity = history_rows,
        .cursor_stroke_pixels = config.cursor_stroke_pixels,
        .box_drawing = config.box_drawing,
        .atlas = config.atlas,
    };
}

/// Copied interaction/lifecycle facts; contains no borrowed canonical storage.
pub const Status = struct {
    title: [1024]u8 = undefined,
    title_len: usize = 0,
    /// Copied, bounded program-status summary, never a borrowed VT event.
    program_status: host_status.Summary = .{},
    /// The separate OSC 9;4 task progress, copied from canonical VT state.
    task_progress: vt.Terminal.Progress = .{},
    failure: ?Failure = null,
    presentation_failure: ?PresentationFailure = null,
    revision: u64 = 0,
    closed: bool = false,
    child_exit: ?pty.ChildExit = null,
    selected: ?selection.Range = null,
    selection_serial: u64 = 0,
    selection_failure: ?SelectionError = null,
    search: find.Status = .{},
    interaction: ?vt.Terminal.InteractionState = null,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
};

/// Typed ownership boundary. SDL cannot obtain the app-owned canonical Core.
/// This is ordinary Zig composition; no C ABI, exported symbols or catalogue.
// zig-audit: acknowledge opaque_type
// reason: The terminal worker's canonical PTY/VT and queue ownership must be inaccessible to the graphical consumer.
pub const Terminal = opaque {
    /// Constructs one PTY/VT owner with final draw commands; rolls back on failure.
    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: pty_vt.Launch,
        presentation: app_presentation.Config,
        event_type: u32,
        initially_visible: bool,
    ) !*Terminal {
        // zig-audit: acknowledge ptr_cast
        // reason: State owns this allocation behind the same opaque worker boundary.
        return @ptrCast(try State.create(allocator, io, environ, launch, presentation, event_type, initially_visible));
    }

    /// Stops/joins the worker and retires its child; all graphical leases must already be retired.
    pub fn destroy(self: *Terminal) void {
        self.state().destroy();
    }
    /// Copies coherent UI routing/lifecycle facts under the bounded metadata lock.
    pub fn snapshot(self: *Terminal) Status {
        return self.state().snapshot();
    }
    /// Admits bounded typed work, copying text before returning and rejecting borrowed key text.
    pub fn submit(self: *Terminal, task: Task) !void {
        return self.state().submit(task);
    }
    /// Consumes coalesced accepted typing/paste activity for host cursor presentation.
    pub fn takeInputActivity(self: *Terminal) bool {
        return self.state().input_activity.swap(false, .acq_rel);
    }
    /// Copies the latest app color preference into one bounded mailbox, without allocation.
    /// The sole worker applies it canonically; stopped panes use the saved preference on restart.
    pub fn setColorDefaults(self: *Terminal, defaults: vt.Terminal.ColorDefaults) void {
        const owned = self.state();
        owned.mutex.lockUncancelable(owned.io);
        owned.pending_colors = defaults;
        owned.wake();
        owned.mutex.unlock(owned.io);
    }
    /// Coalesces cursor defaults without bypassing the sole canonical worker.
    pub fn setDefaultCursorStyle(self: *Terminal, style: vt.Terminal.CursorStyle) void {
        const owned = self.state();
        owned.mutex.lockUncancelable(owned.io);
        owned.pending_cursor = style;
        owned.wake();
        owned.mutex.unlock(owned.io);
    }
    /// Borrows a font recipe only until the sole worker completes its transaction.
    /// Waiting is uncancelable, so queued configuration cannot outlive these borrowed paths.
    pub fn reconfigure(self: *Terminal, config: app_presentation.Config, surface: ?commands.Size) ConfigureError!app_presentation.Geometry {
        return self.state().reconfigure(config, surface);
    }
    /// Copies the FIFO-selected canonical range into bounded caller-owned UTF-8 storage.
    pub fn copySelection(self: *Terminal, allocator: std.mem.Allocator, max_bytes: usize) CopyError![]const u8 {
        return self.state().copySelection(allocator, max_bytes);
    }
    /// Copies one clicked canonical OSC 8 URI through the same bounded FIFO completion.
    pub fn copyHyperlink(self: *Terminal, allocator: std.mem.Allocator, context: selection.Context, point: vt.Terminal.TextPoint) CopyError![]const u8 {
        return self.state().copy(allocator, desktop.uri_limit, .{ .context = context, .point = point });
    }
    /// Takes one coalesced copied attention fact without blocking canonical service.
    pub fn takeAttention(self: *Terminal) bool {
        return self.state().attention.swap(false, .acq_rel);
    }
    /// Copies and retires the latest terminal-originated clipboard set, if any.
    pub fn takeClipboardSet(self: *Terminal, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]u8 {
        return self.state().takeClipboardSet(allocator);
    }
    /// Changes projection visibility without changing canonical service policy.
    pub fn setVisible(self: *Terminal, visible: bool) void {
        self.state().setVisible(visible);
    }
    /// Grants one projection credit after presentation or an explicit reveal.
    pub fn requestFrame(self: *Terminal) void {
        self.state().requestFrame();
    }
    /// Transfers a completed draw-command cut; no new cut preserves the held lease.
    pub fn replaceFrame(self: *Terminal, previous: ?*Frame, paint: ?*selection.Paint) FrameError!?Frame {
        return self.state().replaceFrame(previous, paint);
    }
    /// Retires the host's held cut before destroying the terminal worker.
    pub fn releaseFrame(self: *Terminal, lease: Frame) projection.ReleaseError!void {
        const owned = self.state();
        owned.frame_mutex.lockUncancelable(owned.io);
        defer {
            owned.frame_mutex.unlock(owned.io);
            // A producer may have skipped this short transfer mutex while credit was ready.
            // Retiring the pin must not strand a pending projection in the idle poll.
            if (owned.credit.load(.acquire)) owned.wake();
        }
        try owned.projection.release(lease);
    }

    fn state(self: *Terminal) *State {
        // zig-audit: acknowledge ptr_cast
        // reason: This module owns the concrete allocation behind its terminal-worker authority boundary.
        // zig-audit: acknowledge align_cast
        // reason: Only State.create produces Terminal pointers, preserving State alignment for their entire lifetime.
        return @ptrCast(@alignCast(self));
    }
};

/// Worker-owned synchronization/output publication state, never canonical VT progress.
const OutputGate = struct {
    revision: u64 = 0,
    hold_started: ?u64 = null,
    timed_out: bool = false,
    pending: bool = true,

    /// Tracks pending canonical change and exact release/hold deadlines without changing VT.
    fn note(self: *OutputGate, revision: u64, held: bool, ended: bool, now: u64) void {
        if (ended or !held) {
            self.hold_started = null;
            self.timed_out = false;
        }
        self.pending = self.pending or revision != self.revision;
        self.revision = revision;
        if (held and !self.timed_out) {
            const started = self.hold_started orelse now;
            self.hold_started = started;
            if (now -| started >= std.time.ns_per_s) {
                self.timed_out = true;
                self.hold_started = null;
            }
        }
    }

    /// Allows projection only outside a hold or after its bounded timeout.
    fn released(self: OutputGate, held: bool) bool {
        return !held or self.timed_out;
    }

    /// Supplies the next hold deadline, including a quiescent child.
    fn waitMs(self: OutputGate, now: u64) ?i32 {
        const start = self.hold_started orelse return null;
        const ns = std.time.ns_per_s -| (now -| start);
        return @intCast((ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms);
    }
};

/// Worker-owned scrollback viewport; the canonical VT remains the history authority.
const HistoryViewport = struct {
    offset: u32 = 0,
    anchor: ?u64 = null,

    /// Returns this viewport to live and retires its absolute anchor.
    fn reset(self: *HistoryViewport) void {
        self.* = .{};
    }

    /// Clamps an explicit history window and records its absolute retained-row anchor.
    fn seek(self: *HistoryViewport, offset: u32, count: u32, base: u32, alternate: bool) void {
        self.offset = if (alternate) 0 else @min(offset, count);
        self.anchor = if (self.offset == 0) null else @as(u64, base) + count - self.offset;
    }

    /// Applies bounded signed row intent against exact retained extent.
    fn scroll(self: *HistoryViewport, delta: i32, count: u32, base: u32, alternate: bool) void {
        const next = std.math.clamp(@as(i64, self.offset) + delta, 0, @as(i64, count));
        self.seek(@intCast(next), count, base, alternate);
    }

    /// Keeps the same absolute top row during output and clamps it after eviction.
    fn follow(self: *HistoryViewport, count: u32, base: u32, alternate: bool) void {
        const anchor = self.anchor orelse return;
        if (alternate) return self.reset();
        const end = @as(u64, base) + count;
        self.seek(@intCast(@min(end -| anchor, count)), count, base, false);
    }
};

/// Main owns lifetime; its terminal worker owns every canonical PTY/VT mutation.
/// Main sees only immutable frame leases and bounded copied interaction facts.
const State = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    core: *pty_vt.Core,
    projection: *projection.Projection,
    history_capacity: u16,
    wake_fd: posix.fd_t,
    event_type: u32,
    thread: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    request_completed: std.Io.Condition = .init,
    frame_mutex: std.Io.Mutex = .init,
    tasks: [queue_limit]Work = undefined,
    head: usize = 0,
    count: usize = 0,
    input_bytes: usize = 0,
    // Accepted GUI intents that could no longer enter the canonical PTY outbox.
    // Core.undelivered_bytes accounts only for bytes already encoded there.
    write_closed_intents: usize = 0,
    write_closed_payload_bytes: usize = 0,
    stopping: bool = false,
    status: Status = .{},
    /// One host-owned per-pane OSC 7501 index, not a second VT database.
    program_status_index: host_status.Index,
    /// A user-input acknowledgment may change the header without changing VT.
    program_status_changed_pending: bool = false,
    pending_colors: ?vt.Terminal.ColorDefaults = null,
    pending_cursor: ?vt.Terminal.CursorStyle = null,
    color_preference: vt.Terminal.ColorSchemePreference = .dark,
    preference_pending: bool = false,
    visible: std.atomic.Value(bool) = .init(true),
    credit: std.atomic.Value(bool) = .init(true),
    new_frame: std.atomic.Value(bool) = .init(false),
    output_gate: OutputGate = .{},
    // Block only the content/viewport which failed; canonical service remains independent.
    store_busy: bool = false,
    blocked_presentation: ?struct { content_sequence: u64, history_offset: u32 } = null,
    viewport: HistoryViewport = .{},
    selected: ?selection.Range = null,
    selection_serial: u64 = 0,
    selection_structural_edit_generation: u64 = 0,
    selection_row_generation_floor: u64 = 0,
    selection_last_checked_row_generation: u64 = 0,
    selection_failure: ?SelectionError = null,
    paint: selection.Paint = .{},
    search: find.Find = .{},
    attention: std.atomic.Value(bool) = .init(false),
    input_activity: std.atomic.Value(bool) = .init(false),
    clipboard: ?[]u8 = null,
    consequence_worked: bool = false,

    fn observe(self: *const State) *const vt.Terminal.Observation {
        return self.core.terminal.observation();
    }

    fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: pty_vt.Launch,
        presentation: app_presentation.Config,
        event_type: u32,
        initially_visible: bool,
    ) !*State {
        const self = try allocator.create(State);
        errdefer allocator.destroy(self);
        const store = switch (presentation.text) {
            .shared => |shared| shared,
            .private => |fonts| try vt_output.initPresentationStore(allocator, io, fonts, .{
                .shape_cache = presentation.shape_cache,
                .shaped_capacity = presentation.shaped_capacity,
                .raster_bytes = presentation.raster_bytes,
            }),
        };
        defer if (presentation.text == .private) vt_output.releasePresentationStore(store);
        const cell = vt_output.presentationStoreCellSize(store);
        const core = try allocator.create(pty_vt.Core);
        errdefer allocator.destroy(core);
        try core.initInto(allocator, environ, launch, .{ .width = cell.width, .height = cell.height });
        errdefer core.deinit();
        // Register the real per-pane consumer before PTY read admission,
        // otherwise an early OSC 7501 query would be falsely ignored.
        core.terminal.setProgramStatusConsumer(true);
        const output_owner = try projection.Projection.create(allocator, &core.terminal, store, sharedConfig(presentation, launch.history_rows));
        errdefer output_owner.destroy();
        const fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (fd < 0) return error.WakeFailed;
        errdefer closeWake(fd);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .core = core,
            .projection = output_owner,
            .history_capacity = launch.history_rows,
            .program_status_index = host_status.Index.init(allocator),
            .color_preference = desktop.colorPreference(launch.color_defaults.background),
            .wake_fd = fd,
            .event_type = event_type,
            .visible = .init(initially_visible),
        };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    /// All backend leases must be retired before destroying this lifetime owner.
    fn destroy(self: *State) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.mutex.unlock(self.io);
        self.wake();
        if (self.thread) |thread| thread.join();
        self.cancelPending();
        self.program_status_index.deinit();
        closeWake(self.wake_fd);
        if (self.clipboard) |bytes| self.allocator.free(bytes);
        self.projection.destroy();
        self.core.deinit();
        self.allocator.destroy(self.core);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn takeClipboardSet(self: *State, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const source = self.clipboard orelse return null;
        const copied = try allocator.dupe(u8, source);
        self.allocator.free(source);
        self.clipboard = null;
        return copied;
    }

    fn replaceFrame(self: *State, previous: ?*Frame, paint: ?*selection.Paint) FrameError!?Frame {
        if (!self.new_frame.load(.acquire)) return null;
        self.frame_mutex.lockUncancelable(self.io);
        defer {
            self.frame_mutex.unlock(self.io);
            if (self.credit.load(.acquire)) self.wake();
        }
        if (!self.new_frame.load(.acquire)) return null;
        const lease = try self.projection.replace(if (previous) |lease| lease.* else null);
        if (paint) |output| output.* = self.paint;
        self.new_frame.store(false, .release);
        return lease;
    }

    fn snapshot(self: *State) Status {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.status;
    }

    fn submit(self: *State, supplied: Task) !void {
        var task = supplied;
        const bytes = taskBytes(task);
        if (bytes.len > pty_vt.input_event_limit) return error.InputLimit;
        // Associated text shares the bounded owned byte lane; legacy fallback text is not submitted by this host.
        if (task == .input and task.input == .key and
            task.input.key.legacy_text.len != 0)
            return error.BorrowedKeyText;
        if (bytes.len != 0) {
            const owned = try self.allocator.dupe(u8, bytes);
            switch (task.input) {
                .bytes => task.input.bytes = owned,
                .paste => task.input.paste = owned,
                .key => task.input.key.text = owned,
                // zig-audit: acknowledge unreachable
                // reason: taskBytes can return nonempty bytes only for these three input tags, and no mutation changes the active tag before this switch.
                else => unreachable,
            }
        }
        errdefer self.releaseTask(task);
        try self.admit(.{ .intent = task });
        if (inputActivity(task)) self.input_activity.store(true, .release);
    }

    fn admit(self: *State, work: Work) error{ TerminalStopped, InputQueueFull }!void {
        const bytes = if (work == .intent) taskBytes(work.intent).len else 0;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping or self.status.failure != null) return error.TerminalStopped;
        if (self.count == queue_limit or bytes > input_byte_limit - self.input_bytes) return error.InputQueueFull;
        self.tasks[(self.head + self.count) % queue_limit] = work;
        self.count += 1;
        self.input_bytes += bytes;
        self.wake();
    }

    fn reconfigure(self: *State, config: app_presentation.Config, surface: ?commands.Size) ConfigureError!app_presentation.Geometry {
        var request: Configuration = .{ .config = config, .surface = surface };
        try self.admit(.{ .configure = &request });
        self.mutex.lockUncancelable(self.io);
        while (!request.complete) self.request_completed.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
        return request.result.?;
    }

    fn completeConfiguration(self: *State, request: *Configuration, result: ConfigureError!app_presentation.Geometry) void {
        self.mutex.lockUncancelable(self.io);
        if (result) |geometry| request.result = geometry else |failure| request.failure = failure;
        request.complete = true;
        self.request_completed.broadcast(self.io);
        // No request access follows unlock: the waiting caller can now retire its stack storage.
        self.mutex.unlock(self.io);
    }

    fn applyConfiguration(self: *State, request: *Configuration) void {
        const live = self.observe().semanticView(0);
        const store = switch (request.config.text) {
            .shared => |shared| shared,
            .private => |fonts| vt_output.initPresentationStore(self.allocator, self.io, fonts, .{
                .shape_cache = request.config.shape_cache,
                .shaped_capacity = request.config.shaped_capacity,
                .raster_bytes = request.config.raster_bytes,
            }) catch |failure| {
                self.completeConfiguration(request, failure);
                return;
            },
        };
        // Completion releases the caller's stack request. Snapshot cleanup
        // ownership before signaling; the defer must never inspect request.
        const store_is_private = request.config.text == .private;
        defer if (store_is_private) vt_output.releasePresentationStore(store);
        const target: projection.Target = if (request.surface) |surface|
            .{ .surface = .{ .width = surface.width, .height = surface.height } }
        else
            .current;
        self.frame_mutex.lockUncancelable(self.io);
        defer self.frame_mutex.unlock(self.io);
        const result = self.projection.reconfigure(self.core, store, sharedConfig(request.config, self.history_capacity), target);
        if (result) |geometry| {
            // The sole producer invalidates only notification authority, never an accepted lease.
            // Reconfiguration completes before the GUI can start its next transfer; only a later
            // publication can make pre-reset unread slots observable again, retiring them first.
            self.new_frame.store(false, .release);
            if (geometry.columns != live.cols) self.viewport.reset();
            self.blocked_presentation = null;
            self.mutex.lockUncancelable(self.io);
            self.status.presentation_failure = null;
            self.mutex.unlock(self.io);
            self.output_gate.pending = true;
            self.credit.store(true, .release);
            self.completeConfiguration(request, app_presentation.Geometry{
                .cell_size = .{ .width = @intCast(geometry.cell_size.width), .height = @intCast(geometry.cell_size.height) },
                .rows = geometry.rows,
                .columns = geometry.columns,
            });
        } else |failure| self.completeConfiguration(request, failure);
    }

    fn copySelection(self: *State, allocator: std.mem.Allocator, max_bytes: usize) CopyError![]const u8 {
        return self.copy(allocator, max_bytes, null);
    }
    fn copy(self: *State, allocator: std.mem.Allocator, max_bytes: usize, link: ?Link) CopyError![]const u8 {
        if (max_bytes == 0 or max_bytes > input_byte_limit) return error.CopyLimit;
        var request: Copy = .{ .allocator = allocator, .max_bytes = max_bytes, .link = link };
        try self.admit(.{ .copy = &request });
        self.mutex.lockUncancelable(self.io);
        while (!request.complete) self.request_completed.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
        return request.result.?;
    }
    fn completeCopy(self: *State, request: *Copy, result: CopyError![]const u8) void {
        self.mutex.lockUncancelable(self.io);
        if (result) |bytes| request.result = bytes else |failure| request.failure = failure;
        request.complete = true;
        self.request_completed.broadcast(self.io);
        // The caller can retire request storage after this unlock.
        self.mutex.unlock(self.io);
    }
    fn applyCopy(self: *State, request: *Copy) void {
        if (request.link) |link| {
            self.completeCopy(request, self.linkText(link, request.allocator, request.max_bytes));
            return;
        }
        const range = self.selected orelse {
            self.completeCopy(request, self.selection_failure orelse error.NoSelection);
            return;
        };
        self.completeCopy(request, range.copy(self.observe(), request.allocator, request.max_bytes));
    }
    fn resolve(self: *State, context: selection.Context, point: vt.Terminal.TextPoint) SelectionError!struct { view: vt.Terminal.SemanticView, row: u16 } {
        const observation = self.observe();
        const live = observation.semanticView(0);
        if (live.cols != context.columns or live.is_alternate_screen != context.alternate) return error.SelectionContextChanged;
        const first = try context.row(0);
        const top: i64 = if (live.is_alternate_screen) 0 else @as(i64, live.history_row_base) + live.history_count;
        const offset = top - first;
        if (offset < 0 or offset > live.history_count) return error.SelectionEvicted;
        const view = observation.semanticView(@intCast(offset));
        const row_index = @as(i64, point.row) - first;
        if (row_index < 0 or row_index >= @min(view.rows, context.rows) or point.col >= view.cols) return error.InvalidSelection;
        return .{ .view = view, .row = @intCast(row_index) };
    }
    fn linkText(self: *State, link: Link, allocator: std.mem.Allocator, max_bytes: usize) CopyError![]const u8 {
        const resolved = try self.resolve(link.context, link.point);
        const cell = resolved.view.cellInfoAt(resolved.row, link.point.col);
        if (cell.attrs.link_id == 0) return error.NoHyperlink;
        const uri = self.observe().hyperlinkUri(cell.attrs.link_id) orelse return error.NoHyperlink;
        if (uri.len > max_bytes) return error.HyperlinkLimit;
        return allocator.dupe(u8, uri);
    }
    fn applySelection(self: *State, intent: Select) SelectionError!void {
        self.selection_serial = intent.serial;
        self.selection_failure = null;
        self.output_gate.pending = true;
        if (intent.kind == .clear) {
            self.selected = null;
            return;
        }
        const resolved = try self.resolve(intent.context, intent.point);
        const view = resolved.view;
        const row_index = resolved.row;
        const current = selection.Context.fromView(view);
        switch (intent.kind) {
            .start => self.selected = try selection.start(view, row_index, intent.point.col),
            .extend => {
                const range = self.selected orelse return;
                const observed = self.observe();
                if (self.selection_structural_edit_generation != observed.structuralEditGeneration() or
                    (observed.rowMutationFloor() != self.selection_last_checked_row_generation and
                        range.rowsModifiedSince(observed, self.selection_row_generation_floor)))
                    return error.SelectionContextChanged;
                switch (range.validity(current)) {
                    .valid => {},
                    .context_changed => return error.SelectionContextChanged,
                    .evicted => return error.SelectionEvicted,
                }
                try self.selected.?.extend(view, row_index, intent.point.col);
            },
            .word => self.selected = try selection.word(view, @intCast(row_index), intent.point.col),
            .row => self.selected = try selection.visualRow(view, @intCast(row_index)),
            .clear => {},
        }
        if (self.selected != null) self.bindSelectionGeneration();
    }
    fn selectMatch(self: *State, range: selection.Range) void {
        self.selected = range;
        self.bindSelectionGeneration();
        self.selection_failure = null;
        const live = self.observe().semanticView(0);
        const top: i64 = if (live.is_alternate_screen) 0 else @as(i64, live.history_row_base) + live.history_count;
        self.viewport.seek(@intCast(@min(@as(i64, live.history_count), @max(0, top - range.anchor.row))), live.history_count, live.history_row_base, live.is_alternate_screen);
        self.output_gate.pending = true;
    }

    fn bindSelectionGeneration(self: *State) void {
        const observed = self.observe();
        self.selection_structural_edit_generation = observed.structuralEditGeneration();
        self.selection_row_generation_floor = observed.rowMutationFloor();
        self.selection_last_checked_row_generation = self.selection_row_generation_floor;
    }

    // Row identity is canonical in VT, so selection observes that existing
    // proof rather than maintaining a second line-erase or cell-damage ledger.
    // An unaffected selected row survives ordinary output and history scrolls.
    fn reconcileSelection(self: *State, observation: *const vt.Terminal.Observation, live: vt.Terminal.SemanticView) void {
        const range = self.selected orelse return;
        const row_floor = observation.rowMutationFloor();
        if (observation.structuralEditGeneration() != self.selection_structural_edit_generation or
            (row_floor != self.selection_last_checked_row_generation and
                range.rowsModifiedSince(observation, self.selection_row_generation_floor)))
        {
            self.selected = null;
            // Invalidation caused by normal output is not a user action error.
            self.selection_failure = null;
            self.output_gate.pending = true;
            return;
        }
        self.selection_last_checked_row_generation = row_floor;
        switch (range.validity(selection.Context.fromView(live))) {
            .valid => {},
            .context_changed => {
                self.selected = null;
                self.selection_failure = error.SelectionContextChanged;
            },
            .evicted => {
                self.selected = null;
                self.selection_failure = error.SelectionEvicted;
            },
        }
    }
    fn applyFind(self: *State, request: find.Request) void {
        self.selection_serial = request.serial;
        self.selection_failure = null;
        const observation = self.observe();
        switch (request.kind) {
            .close => {
                self.search = .{};
                self.search.status.serial = request.serial;
                self.selected = null;
            },
            .query => {
                self.selected = null;
                self.search.begin(observation, request) catch |failure| self.search.fail(failure);
            },
            .next, .previous => {
                if (self.search.status.phase == .stale or self.search.status.phase == .failed) {
                    var refreshed = self.search.request;
                    refreshed.serial = request.serial;
                    self.selected = null;
                    self.search.begin(observation, refreshed) catch |failure| self.search.fail(failure);
                } else if (self.search.navigate(request.serial, request.kind == .previous)) |range| self.selectMatch(range);
            },
        }
        self.output_gate.pending = true;
        self.notify();
    }

    fn cancelPending(self: *State) void {
        while (self.pop()) |work| switch (work) {
            .intent => |task| self.releaseTask(task),
            .configure => |request| self.completeConfiguration(request, error.TerminalStopped),
            .copy => |request| self.completeCopy(request, error.TerminalStopped),
        };
    }

    fn setVisible(self: *State, visible: bool) void {
        if (self.visible.swap(visible, .acq_rel) != visible) {
            if (visible) self.requestFrame();
            self.wake();
        }
    }

    /// Called only after successful SDL presentation, or an explicit reveal.
    fn requestFrame(self: *State) void {
        if (!self.credit.swap(true, .acq_rel)) self.wake();
    }

    fn pop(self: *State) ?Work {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.count == 0) return null;
        const task = self.tasks[self.head];
        self.head = (self.head + 1) % queue_limit;
        self.count -= 1;
        if (task == .intent) self.input_bytes -= taskBytes(task.intent).len;
        return task;
    }

    fn peek(self: *State) ?Work {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return if (self.count == 0) null else self.tasks[self.head];
    }

    /// An unwritable PTY must not hold GUI callers on borrowed stack requests.
    /// Rejection has no canonical effect; retained intent keeps its exact FIFO order.
    fn rejectBlockedControls(self: *State) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const count = self.count;
        var retained: usize = 0;
        var rejected = false;
        for (0..count) |index| {
            const work = self.tasks[(self.head + index) % queue_limit];
            switch (work) {
                .intent => {
                    self.tasks[(self.head + retained) % queue_limit] = work;
                    retained += 1;
                },
                .configure => |request| {
                    request.failure = error.InputBackpressured;
                    request.complete = true;
                    rejected = true;
                },
                .copy => |request| {
                    request.failure = error.InputBackpressured;
                    request.complete = true;
                    rejected = true;
                },
            }
        }
        self.count = retained;
        if (rejected) self.request_completed.broadcast(self.io);
    }

    const QueueTurn = enum { empty, backpressured, more };

    /// Service canonical reads after a bounded amount of work, even if callers
    /// replenish the queue faster than the worker can retire late input.
    fn applyQueued(self: *State) !QueueTurn {
        for (0..queue_turn_limit) |_| {
            const work = self.peek() orelse return .empty;
            switch (work) {
                .intent => |task| self.apply(task) catch |failure| switch (failure) {
                    error.WriteQueueFull => {
                        self.rejectBlockedControls();
                        return .backpressured;
                    },
                    error.ChildClosed => {
                        // This is an ordinary half-closed PTY lifecycle event,
                        // not a failed read-side worker. Retire only this intent.
                        self.write_closed_intents +|= 1;
                        self.write_closed_payload_bytes +|= taskBytes(task).len;
                    },
                    else => return failure,
                },
                .configure => |request| self.applyConfiguration(request),
                .copy => |request| self.applyCopy(request),
            }
            const completed = self.pop().?;
            if (completed == .intent) self.releaseTask(completed.intent);
        }
        // The next worker turn must run without another external eventfd wake.
        return .more;
    }

    fn releaseTask(self: *State, task: Task) void {
        const bytes = taskBytes(task);
        if (bytes.len != 0) self.allocator.free(bytes);
    }

    fn stopRequested(self: *State) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stopping;
    }

    fn apply(self: *State, task: Task) !void {
        const live = self.observe().semanticView(0);
        switch (task) {
            .find => |request| self.applyFind(request),
            .select => |intent| self.applySelection(intent) catch |failure| {
                self.selected = null;
                self.selection_failure = failure;
            },
            .input => |input| {
                try self.core.input(input);
                // Explicit user input acknowledges unseen completed/failed
                // statuses, but must not remove a still-blocked request.
                if (input == .bytes or input == .paste or input == .key) {
                    if (self.program_status_index.seenByUser())
                        self.program_status_changed_pending = true;
                    if (self.viewport.offset != 0) self.output_gate.pending = true;
                    self.viewport.reset();
                    if (self.selected != null) {
                        self.selected = null;
                        self.output_gate.pending = true;
                    }
                }
            },
            .resize => |size| {
                if (size.rows != live.rows or size.columns != live.cols) {
                    if (size.columns != live.cols) self.viewport.reset();
                    try self.core.resize(size.rows, size.columns);
                    self.output_gate.pending = true;
                }
            },
            .scroll => |delta| {
                self.viewport.scroll(delta, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.output_gate.pending = true;
            },
            .seek => |offset| {
                self.viewport.seek(offset, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.output_gate.pending = true;
            },
            .retry_projection => {
                self.blocked_presentation = null;
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = null;
                self.mutex.unlock(self.io);
                self.output_gate.pending = true;
                self.credit.store(true, .release);
            },
        }
    }

    fn service(self: *State, readable: bool, writable: bool, now: u64) !pty_vt.Service {
        const result = try self.core.service(readable, writable, now);
        var host = try consequences.drain(&self.core.terminal, self.allocator, self.color_preference, &self.program_status_index);
        defer host.deinit(self.allocator);
        self.consequence_worked = host.worked;
        var program_status_dirty = host.status_changed or self.program_status_changed_pending;
        self.program_status_changed_pending = false;
        // The child exit and new shell prompt clear transient work only.
        // Finished and failed status remains until acknowledged by user input.
        if (result.child_exit != null and self.program_status_index.processExited())
            program_status_dirty = true;
        var host_notify = false;
        if (host.clipboard) |bytes| {
            self.mutex.lockUncancelable(self.io);
            const previous = self.clipboard;
            self.clipboard = bytes;
            host.clipboard = null;
            self.mutex.unlock(self.io);
            if (previous) |old| self.allocator.free(old);
            host_notify = true;
        }
        if (host.attention and !self.attention.swap(true, .acq_rel)) host_notify = true;
        if (host_notify) self.notify();
        const observation = self.observe();
        const live = observation.semanticView(0);
        self.viewport.follow(live.history_count, live.history_row_base, live.is_alternate_screen);
        self.output_gate.note(observation.semanticSequence(), observation.synchronizedOutput(), result.synchronized_output.ended, now);
        if (result.animation_changed) self.output_gate.pending = true;
        self.reconcileSelection(observation, live);
        const search_changed = self.search.step(observation) catch |failure| failed: {
            self.search.fail(failure);
            break :failed true;
        };
        if (self.selection_serial == self.search.status.serial) {
            if (self.search.status.phase == .stale and self.selected != null) {
                self.selected = null;
                self.output_gate.pending = true;
            } else if (self.search.status.current == null and self.search.status.count != 0) {
                if (self.search.navigate(self.selection_serial, false)) |range| self.selectMatch(range);
            }
        }
        self.mutex.lockUncancelable(self.io);
        self.status.search = self.search.status;
        const next_program_status = self.program_status_index.summary();
        const program_status_changed = program_status_dirty or
            !std.meta.eql(self.status.program_status, next_program_status);
        self.status.program_status = next_program_status;
        const next_task_progress = observation.taskProgress();
        const task_progress_changed = !std.meta.eql(self.status.task_progress, next_task_progress);
        self.status.task_progress = next_task_progress;
        self.status.selected = self.selected;
        self.status.selection_serial = self.selection_serial;
        self.status.selection_failure = self.selection_failure;
        const lifecycle_changed = self.status.closed != result.stream_closed or
            (self.status.child_exit == null and result.child_exit != null);
        self.status.closed = result.stream_closed;
        self.status.child_exit = result.child_exit;
        self.status.interaction = observation.interactionState();
        self.status.cursor_row = live.cursor_row;
        self.status.cursor_col = live.cursor_col;
        self.status.revision = observation.semanticSequence();
        const title = observation.title() orelse "";
        const title_len = @min(title.len, self.status.title.len);
        const title_changed = title_len != self.status.title_len or
            !std.mem.eql(u8, self.status.title[0..self.status.title_len], title[0..title_len]);
        self.status.title_len = title_len;
        @memcpy(self.status.title[0..self.status.title_len], title[0..self.status.title_len]);
        self.mutex.unlock(self.io);
        if (lifecycle_changed or title_changed or program_status_changed or task_progress_changed or search_changed) self.notify();
        // Only this turn's failed text claim earns a retry deadline.
        self.store_busy = false;
        var published = false;
        const blocked = if (self.blocked_presentation) |failed|
            failed.content_sequence == observation.contentSequence() and failed.history_offset == self.viewport.offset
        else
            false;
        if (!blocked and self.output_gate.pending and self.visible.load(.acquire) and
            self.output_gate.released(observation.synchronizedOutput()) and self.credit.load(.acquire))
        {
            // Projection may skip a stalled GUI transfer; canonical service never waits for it.
            if (!self.frame_mutex.tryLock()) return result;
            defer self.frame_mutex.unlock(self.io);
            std.debug.assert(self.credit.swap(false, .acq_rel));
            self.projection.prepare(self.viewport.offset) catch |failure| {
                if (failure == error.PresentationBusy) {
                    self.store_busy = true;
                    self.credit.store(true, .release);
                    return result;
                }
                self.blocked_presentation = .{ .content_sequence = observation.contentSequence(), .history_offset = self.viewport.offset };
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = failure;
                self.mutex.unlock(self.io);
                self.notify();
                return result;
            };
            if (self.blocked_presentation != null) {
                self.blocked_presentation = null;
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = null;
                self.mutex.unlock(self.io);
            }
            const view = observation.semanticView(self.viewport.offset);
            self.paint = if (self.selected) |range| range.paint(view, self.selection_serial) catch .{ .serial = self.selection_serial } else .{ .serial = self.selection_serial };
            self.output_gate.pending = false;
            self.new_frame.store(true, .release);
            published = true;
        }
        if (published) self.notify();
        return result;
    }

    fn run(self: *State) void {
        self.loop() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            self.status.failure = failure;
            self.mutex.unlock(self.io);
            self.cancelPending();
            self.notify();
        };
    }

    fn takeColors(self: *State) ?vt.Terminal.ColorDefaults {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const result = self.pending_colors;
        self.pending_colors = null;
        return result;
    }

    fn takeCursor(self: *State) ?vt.Terminal.CursorStyle {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const result = self.pending_cursor;
        self.pending_cursor = null;
        return result;
    }

    fn loop(self: *State) !void {
        var readable = true;
        var writable = true;
        while (!self.stopRequested()) {
            // Blocked scalar work still targets the current screen and cursor.
            // Defer queued mutations until it has been applied.
            const scalar_was_blocked = self.core.inputBlocked();
            var queue_turn: QueueTurn = .empty;
            if (!scalar_was_blocked) {
                queue_turn = try self.applyQueued();
                if (self.takeCursor()) |style| {
                    self.core.terminal.setDefaultCursorStyle(style);
                    self.output_gate.pending = true;
                }
                if (self.takeColors()) |defaults| {
                    self.core.terminal.setColorDefaults(defaults);
                    const preference = desktop.colorPreference(defaults.background);
                    self.preference_pending = self.preference_pending or preference != self.color_preference;
                    self.color_preference = preference;
                    self.output_gate.pending = true;
                }
                if (self.preference_pending) {
                    const sent: ?bool = self.core.terminal.reportColorSchemePreference(self.color_preference) catch |failure| switch (failure) {
                        error.ReplyLimit => null,
                        else => return failure,
                    };
                    if (sent != null) self.preference_pending = false;
                }
            } else {
                self.rejectBlockedControls();
            }
            const room_before = self.core.writeRoom();
            const now: u64 = @intCast(std.Io.Clock.awake.now(self.io).toNanoseconds());
            const result = try self.service(readable, writable, now);
            const retry_after_write_progress = queue_turn == .backpressured and self.core.writeRoom() > room_before;
            // Queued work received while blocked must not wait for another wake.
            const retry_after_scalar_recovery = scalar_was_blocked and !self.core.inputBlocked();
            var timeout: i32 = if (result.stream_closed and result.child_exit == null) 50 else -1;
            for ([_]?i32{
                self.output_gate.waitMs(now),
                if (self.store_busy and self.visible.load(.acquire) and self.credit.load(.acquire)) @as(i32, 1) else null,
                // Hidden panes have no pixels to animate. A reveal wakes the
                // worker and services current phase before publication.
                if (self.visible.load(.acquire)) if (result.animation_wait_ms) |ms| @as(i32, @intCast(@min(ms, std.math.maxInt(i32)))) else null else null,
                if (result.input_retry_wait_ms) |ms| @intCast(@min(ms, std.math.maxInt(i32))) else null,
            }) |deadline| {
                if (deadline) |ms| timeout = if (timeout < 0) ms else @min(timeout, ms);
            }
            // Runnable queue work and newly available outbox room both need a
            // fresh PTY readiness snapshot. A zero-timeout poll retries now
            // without pinning readable=false through sustained input traffic.
            if (queue_turn == .more or retry_after_write_progress or retry_after_scalar_recovery or self.core.bufferedOutputRunnable() or self.search.status.phase == .scanning or self.consequence_worked) timeout = 0;
            const can_read = self.core.readAdmissible();
            const can_write = result.write_pending or self.core.writePending();
            var fds = [_]posix.pollfd{
                .{
                    .fd = if (!can_read and !can_write) -1 else try self.core.descriptor(),
                    .events = (if (can_read) @as(i16, posix.POLL.IN | posix.POLL.HUP) else 0) | (if (can_write) @as(i16, posix.POLL.OUT) else 0),
                    .revents = 0,
                },
                .{ .fd = self.wake_fd, .events = posix.POLL.IN, .revents = 0 },
            };
            // zig-audit: acknowledge discard
            // reason: Readiness is consumed from each exact revents mask below; the aggregate ready count adds no authority.
            _ = try posix.poll(&fds, timeout);
            if (fds[1].revents & posix.POLL.IN != 0) self.drainWake();
            readable = fds[0].revents & (posix.POLL.IN | posix.POLL.HUP) != 0 or self.core.bufferedOutputRunnable();
            writable = fds[0].revents & posix.POLL.OUT != 0;
        }
    }

    fn notify(self: *State) void {
        var event: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        event.type = self.event_type;
        if (!c.SDL_PushEvent(&event)) {
            self.mutex.lockUncancelable(self.io);
            if (self.status.presentation_failure == null) self.status.presentation_failure = error.SDLNotification;
            self.mutex.unlock(self.io);
        }
    }

    fn wake(self: *State) void {
        const one: u64 = 1;
        while (true) {
            const result = posix.system.write(self.wake_fd, std.mem.asBytes(&one).ptr, 8);
            switch (posix.errno(result)) {
                .INTR => continue,
                .SUCCESS, .AGAIN => return,
                // zig-audit: acknowledge panic
                // reason: The eventfd belongs to this live State until its worker joins; EBADF or any non-EINTR/non-saturation failure is an impossible ownership violation.
                else => @panic("terminal wake descriptor failed"),
            }
        }
    }

    fn drainWake(self: *State) void {
        var value: u64 = undefined;
        while (true) {
            const result = posix.system.read(self.wake_fd, std.mem.asBytes(&value).ptr, 8);
            switch (posix.errno(result)) {
                .INTR => continue,
                .SUCCESS, .AGAIN => return,
                // zig-audit: acknowledge panic
                // reason: The worker exclusively reads its live eventfd, whose lifetime ends only after join; unexpected descriptor errors violate construction/cleanup ownership.
                else => @panic("terminal wake drain failed"),
            }
        }
    }
};

fn taskBytes(task: Task) []const u8 {
    if (task != .input) return "";
    return switch (task.input) {
        .bytes => |bytes| bytes,
        .paste => |bytes| bytes,
        .key => |key| key.text,
        else => "",
    };
}

fn inputActivity(task: Task) bool {
    if (task != .input) return false;
    return switch (task.input) {
        .bytes, .paste => |bytes| bytes.len != 0,
        .key => |key| key.action != .release and switch (key.key) {
            .unicode => true,
            .named => |named| switch (named) {
                .left_shift, .right_shift, .left_control, .right_control, .left_alt, .right_alt, .left_super, .right_super, .left_hyper, .right_hyper, .left_meta, .right_meta, .caps_lock, .num_lock => false,
                else => true,
            },
        },
        else => false,
    };
}

fn testPresentation() app_presentation.Config {
    return .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
    };
}

fn waitTitle(owner: *Terminal, title: []const u8) !void {
    var attempt: u16 = 0;
    while (attempt < 5000) : (attempt += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], title)) return;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}

test "OSC 52 sets become coalesced copied desktop facts without pacing canonical service" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]52;c;T25l\\007\\033]52;c;VHdv\\007\\033]0;READY\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");

    var copied: ?[]u8 = null;
    var attempts: u16 = 0;
    while (copied == null and attempts < 5000) : (attempts += 1) {
        copied = try owner.takeClipboardSet(std.testing.allocator);
        if (copied == null) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    const text = copied orelse return error.Timeout;
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Two", text);
    try std.testing.expect((try owner.takeClipboardSet(std.testing.allocator)) == null);
    try std.testing.expectEqual(@as(u16, 0), owner.state().core.terminal.consequenceCount());
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "hidden presentation still drains one MiB and semantic input to the sole canonical owner" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const submitted = try std.testing.allocator.dupe(u8, "DONE\n");
    try owner.submit(.{ .input = .{ .bytes = submitted } });
    @memset(submitted, '?');
    std.testing.allocator.free(submitted);
    try waitTitle(owner, "DONE");
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    // Every owned payload is bounded; unused legacy key fallback remains rejected.
    const oversized = try std.testing.allocator.alloc(u8, input_byte_limit + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.InputLimit, owner.submit(.{ .input = .{ .paste = oversized } }));
    try std.testing.expectError(error.InputLimit, owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter }, .text = oversized } } }));
    try std.testing.expectError(error.BorrowedKeyText, owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter }, .legacy_text = "borrowed" } } }));
}

test "projection retry clears only worker output blockage and restores a credit" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const core = try std.testing.allocator.create(pty_vt.Core);
    defer std.testing.allocator.destroy(core);
    core.* = .{ .allocator = std.testing.allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 20, 8);
    defer core.terminal.deinit();
    const fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (fd < 0) return error.WakeFailed;
    defer closeWake(fd);
    const before = core.terminal.observation().semanticSequence();
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = core,
        .projection = undefined,
        .history_capacity = 8,
        .wake_fd = fd,
        .event_type = 0,
        .status = .{ .presentation_failure = error.SDLNotification },
        .blocked_presentation = .{ .content_sequence = 9, .history_offset = 2 },
        .output_gate = .{ .pending = false },
        .credit = .init(false),
    };
    defer state.program_status_index.deinit();
    try state.apply(.retry_projection);
    try std.testing.expect(state.blocked_presentation == null);
    try std.testing.expect(state.status.presentation_failure == null);
    try std.testing.expect(state.output_gate.pending);
    try std.testing.expect(state.credit.load(.acquire));
    try std.testing.expect(!state.new_frame.load(.acquire));
    try std.testing.expectEqual(before, core.terminal.observation().semanticSequence());
}

test "selected terminal text survives ordinary output but not admitted CSI line edits" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var core: pty_vt.Core = .{
        .allocator = std.testing.allocator,
        .transport = undefined,
        .terminal = undefined,
    };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 8, 0);
    defer core.terminal.deinit();
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = &core,
        .projection = undefined,
        .history_capacity = 0,
        .wake_fd = -1,
        .event_type = 0,
    };
    defer state.program_status_index.deinit();
    try std.testing.expect((try core.terminal.feed("alpha")).stateChanged());
    const context = selection.Context.fromView(core.terminal.semanticView(0));
    try state.applySelection(.{
        .serial = 1,
        .kind = .word,
        .context = context,
        .point = .{ .row = 0, .col = 2 },
    });
    try std.testing.expect(state.selected != null);
    const generation = core.terminal.observation().structuralEditGeneration();
    try std.testing.expectEqual(generation, state.selection_structural_edit_generation);

    // The row above the active DEC margins is unaffected. Ordinary output and
    // a rejected CSI L cannot invalidate a selected word on that row.
    try std.testing.expect((try core.terminal.feed("\x1b[2;4r\x1b[1;1H\x1b[L\x1b[2;1Hz")).stateChanged());
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected != null);
    try std.testing.expectEqual(generation, core.terminal.observation().structuralEditGeneration());

    // The command is admitted on row two, even though the selected text on
    // row one is unchanged. Kitty clears all selection on structural IL/DL.
    try std.testing.expect((try core.terminal.feed("\x1b[2;1H\x1b[L")).stateChanged());
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected == null);
    try std.testing.expect(state.selection_failure == null);
    try std.testing.expect(state.output_gate.pending);

    // Re-selecting after the edit binds the new generation, so an idle turn
    // does not repeatedly discard the new selection.
    state.output_gate.pending = false;
    try state.applySelection(.{
        .serial = 2,
        .kind = .word,
        .context = selection.Context.fromView(core.terminal.semanticView(0)),
        .point = .{ .row = 0, .col = 2 },
    });
    state.output_gate.pending = false;
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected != null);
    try std.testing.expect(!state.output_gate.pending);
    try std.testing.expect((try core.terminal.feed("\x1b[2;1H\x1b[M")).stateChanged());
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected == null);
    try std.testing.expect(state.selection_failure == null);
}

test "selected terminal text invalidates only when selected rows are rewritten" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var core: pty_vt.Core = .{
        .allocator = std.testing.allocator,
        .transport = undefined,
        .terminal = undefined,
    };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 12, 4);
    defer core.terminal.deinit();
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = &core,
        .projection = undefined,
        .history_capacity = 4,
        .wake_fd = -1,
        .event_type = 0,
    };
    defer state.program_status_index.deinit();
    try std.testing.expect((try core.terminal.feed("alpha\x1b[2;1Hbeta")).stateChanged());
    try state.applySelection(.{
        .serial = 1,
        .kind = .word,
        .context = selection.Context.fromView(core.terminal.semanticView(0)),
        .point = .{ .row = 0, .col = 2 },
    });
    try std.testing.expect(state.selected != null);

    // An ordinary write and erase on another row must not discard the
    // selected word, even though the terminal content generation changes.
    try std.testing.expect((try core.terminal.feed("\x1b[2;1Hzeta\x1b[2K")).stateChanged());
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected != null);
    try std.testing.expect(state.selection_failure == null);

    // Kitty clears a selection on a row intersected by CSI EL, including
    // DEC private EL. VT row identities already tell us exactly which row
    // changed, without a second erase-event journal or a GUI owner in VT.
    try std.testing.expect((try core.terminal.feed("\x1b[1;1H\x1b[?2K")).stateChanged());
    state.reconcileSelection(core.terminal.observation(), core.terminal.semanticView(0));
    try std.testing.expect(state.selected == null);
    try std.testing.expect(state.selection_failure == null);
    try std.testing.expect(state.output_gate.pending);
}

test "oversized paste fails at admission and leaves the terminal worker alive" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");

    const oversized = try std.testing.allocator.alloc(u8, 64 * 1024);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(error.InputLimit, owner.submit(.{ .input = .{ .paste = oversized } }));
    try owner.submit(.{ .input = .{ .bytes = "AFTER\n" } });
    try waitTitle(owner, "AFTER");
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "full PTY outbox retains accepted input in FIFO order until capacity returns" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const core = try std.testing.allocator.create(pty_vt.Core);
    defer std.testing.allocator.destroy(core);
    core.* = .{ .allocator = std.testing.allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 20, 8);
    defer core.terminal.deinit();
    const filler: [pty_vt.input_event_limit]u8 = @splat('x');
    try core.input(.{ .bytes = &filler });
    const room_before = core.writeRoom();
    try std.testing.expectEqual(@as(usize, 12), room_before);

    const wake_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (wake_fd < 0) return error.WakeFailed;
    defer closeWake(wake_fd);
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = core,
        .projection = undefined,
        .history_capacity = 8,
        .wake_fd = wake_fd,
        .event_type = 0,
    };
    defer state.program_status_index.deinit();
    defer state.cancelPending();
    try state.submit(.{ .input = .{ .bytes = "FIRST_123456789" } });
    var configuration: Configuration = .{ .config = testPresentation(), .surface = null };
    try state.admit(.{ .configure = &configuration });
    try state.submit(.{ .input = .{ .bytes = "SECOND\n" } });
    var copy_request: Copy = .{ .allocator = std.testing.allocator, .max_bytes = 128 };
    try state.admit(.{ .copy = &copy_request });
    try std.testing.expectEqual(State.QueueTurn.backpressured, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, 2), state.count);
    try std.testing.expectEqual(room_before, core.writeRoom());
    try std.testing.expect(configuration.complete);
    try std.testing.expectEqual(@as(?ConfigureError, error.InputBackpressured), configuration.failure);
    try std.testing.expect(copy_request.complete);
    try std.testing.expectEqual(@as(?CopyError, error.InputBackpressured), copy_request.failure);
    try std.testing.expectEqual(@as(usize, "FIRST_123456789SECOND\n".len), state.input_bytes);

    // The PTY accepted the previous bytes, so the same bounded queue can advance.
    core.writes = .{};
    try std.testing.expectEqual(State.QueueTurn.empty, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, 0), state.count);
    try std.testing.expectEqualStrings("FIRST_123456789SECOND\n", core.writes.bytes[0..core.writes.count]);
}

test "borrowed-control rejection compacts a wrapped queue without retiring later input" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const core = try std.testing.allocator.create(pty_vt.Core);
    defer std.testing.allocator.destroy(core);
    core.* = .{ .allocator = std.testing.allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 20, 8);
    defer core.terminal.deinit();
    const wake_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (wake_fd < 0) return error.WakeFailed;
    defer closeWake(wake_fd);
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = core,
        .projection = undefined,
        .history_capacity = 8,
        .wake_fd = wake_fd,
        .event_type = 0,
        .head = queue_limit - 2,
    };
    defer state.program_status_index.deinit();
    defer state.cancelPending();
    try state.submit(.{ .input = .{ .bytes = "A" } });
    var configuration: Configuration = .{ .config = testPresentation(), .surface = null };
    try state.admit(.{ .configure = &configuration });
    try state.submit(.{ .input = .{ .bytes = "B" } });
    var copy_request: Copy = .{ .allocator = std.testing.allocator, .max_bytes = 32 };
    try state.admit(.{ .copy = &copy_request });
    state.rejectBlockedControls();
    try std.testing.expect(configuration.complete);
    try std.testing.expectEqual(@as(?ConfigureError, error.InputBackpressured), configuration.failure);
    try std.testing.expect(copy_request.complete);
    try std.testing.expectEqual(@as(?CopyError, error.InputBackpressured), copy_request.failure);
    try std.testing.expectEqual(@as(usize, 2), state.count);
    try std.testing.expectEqual(@as(usize, 2), state.input_bytes);
    try std.testing.expectEqual(State.QueueTurn.empty, try state.applyQueued());
    try std.testing.expectEqualStrings("AB", core.writes.bytes[0..core.writes.count]);
    try std.testing.expectEqual(@as(usize, 0), state.input_bytes);
}

test "late accepted input after PTY write closure retires without killing read-side service" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const core = try std.testing.allocator.create(pty_vt.Core);
    defer std.testing.allocator.destroy(core);
    core.* = .{ .allocator = std.testing.allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, std.testing.allocator, 4, 20, 8);
    defer core.terminal.deinit();
    core.write_closed = true;

    const wake_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (wake_fd < 0) return error.WakeFailed;
    defer closeWake(wake_fd);
    var state: State = .{
        .allocator = std.testing.allocator,
        .program_status_index = host_status.Index.init(std.testing.allocator),
        .io = threaded.io(),
        .core = core,
        .projection = undefined,
        .history_capacity = 8,
        .wake_fd = wake_fd,
        .event_type = 0,
    };
    defer state.program_status_index.deinit();
    defer state.cancelPending();
    try state.submit(.{ .input = .{ .bytes = "LATE\n" } });
    try state.submit(.{ .input = .{ .paste = "SECOND" } });
    try std.testing.expectEqual(State.QueueTurn.empty, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, 0), state.count);
    try std.testing.expectEqual(@as(usize, 0), state.input_bytes);
    try std.testing.expectEqual(@as(usize, 2), state.write_closed_intents);
    try std.testing.expectEqual(@as(usize, "LATE\nSECOND".len), state.write_closed_payload_bytes);
    try std.testing.expectEqual(@as(usize, 0), core.undelivered_bytes);
    try std.testing.expect(core.readAdmissible());
    try std.testing.expectEqual(@as(?Failure, null), state.status.failure);

    // Continuous late-input admission cannot monopolize a worker turn.
    // Its caller immediately schedules another turn without a fresh wake.
    for (0..queue_turn_limit * 2) |_| try state.submit(.{ .input = .{ .bytes = "x" } });
    try std.testing.expectEqual(State.QueueTurn.more, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, queue_turn_limit), state.count);
    try std.testing.expect(core.readAdmissible());
    try std.testing.expectEqual(State.QueueTurn.more, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, 0), state.count);
    try std.testing.expectEqual(State.QueueTurn.empty, try state.applyQueued());
    try std.testing.expectEqual(@as(usize, 2 + queue_turn_limit * 2), state.write_closed_intents);
}

test "paused PTY reader eventually consumes every accepted input chunk" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033]0;READY\\007'; sleep 1; dd iflag=fullblock bs=1024 count=96 of=/dev/null 2>/dev/null; printf '\\033]0;DRAINED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");

    const chunk: [32 * 1024]u8 = @splat('x');
    for (0..3) |_| try owner.submit(.{ .input = .{ .bytes = &chunk } });
    try waitTitle(owner, "DRAINED");
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "actual PTY child program status advances through live pane UI and user acknowledgment" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;JOB\\007\\033]7501;state=working:id=job:progress=40\\033\\\\'; read step; printf '\\033]7501;state=blocked:id=job:kind=auth\\033\\\\'; read step; printf '\\033]7501;state=done:id=job\\033\\\\'; read step; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();

    const Check = struct {
        fn wait(owner_value: *Terminal, wanted: ?vt.Terminal.ProgramStatus.State) !Status {
            for (0..5000) |_| {
                const current = owner_value.snapshot();
                if (current.failure) |failure| return failure;
                if (current.program_status.state == wanted) return current;
                try std.Io.sleep(owner_value.state().io, .fromMilliseconds(1), .awake);
            }
            return error.Timeout;
        }
    };

    const working = try Check.wait(owner, .working);
    try std.testing.expectEqual(@as(?u8, 40), working.program_status.progress);
    try std.testing.expectEqual(@as(u8, 1), working.program_status.count);
    try std.testing.expectEqualStrings("JOB", working.title[0..working.title_len]);

    try owner.submit(.{ .input = .{ .bytes = "next\n" } });
    const blocked = try Check.wait(owner, .blocked);
    try std.testing.expect(blocked.program_status.kind.? == .auth);
    try std.testing.expectEqual(@as(u8, 1), blocked.program_status.count);

    try owner.submit(.{ .input = .{ .bytes = "next\n" } });
    const finished = try Check.wait(owner, .done);
    try std.testing.expect(finished.program_status.state.? == .done);

    // A third explicit input acknowledges the completed status before the
    // child exits. A GUI never borrows this worker's internal id records.
    try owner.submit(.{ .input = .{ .bytes = "ack\n" } });
    const acknowledged = try Check.wait(owner, null);
    try std.testing.expectEqual(@as(?vt.Terminal.ProgramStatus.State, null), acknowledged.program_status.state);
    try std.testing.expectEqual(@as(?Failure, null), acknowledged.failure);
}

test "sustained PTY write pressure cannot hide a fresh child output marker" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033]0;READY\\007'; sleep 1; dd iflag=fullblock bs=1024 count=128 of=/dev/null 2>/dev/null; printf '\\033]0;MARKER\\007'; cat > /dev/null",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");

    const chunk: [32 * 1024]u8 = @splat('x');
    var admitted: usize = 0;
    var saw_marker = false;
    for (0..5000) |_| {
        if (owner.submit(.{ .input = .{ .bytes = &chunk } })) |_| {
            admitted += 1;
        } else |failure| switch (failure) {
            error.InputQueueFull => {},
            else => return failure,
        }
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "MARKER")) {
            saw_marker = true;
            break;
        }
        if (status.failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(admitted >= 4);
    try std.testing.expect(saw_marker);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "permanently unread PTY rejects borrowed GUI controls promptly without worker failure" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033]0;READY\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");

    const chunk: [32 * 1024]u8 = @splat('x');
    for (0..4) |_| try owner.submit(.{ .input = .{ .bytes = &chunk } });
    var blocked = false;
    for (0..1000) |_| {
        const state = owner.state();
        state.mutex.lockUncancelable(threaded.io());
        const queued = state.count;
        state.mutex.unlock(threaded.io());
        if (queued != 0) {
            blocked = true;
            break;
        }
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(blocked);

    var invalid = testPresentation();
    invalid.text.private.regular = .{ .path = .{ .primary = "/missing-font-unread-pty.ttf", .size = .{ .pixels = 18 } } };
    const start = std.Io.Clock.awake.now(threaded.io());
    try std.testing.expectError(error.InputBackpressured, owner.reconfigure(invalid, null));
    try std.testing.expectError(error.InputBackpressured, owner.copySelection(std.testing.allocator, 128));
    const elapsed_ns = std.Io.Clock.awake.now(threaded.io()).toNanoseconds() - start.toNanoseconds();
    try std.testing.expect(elapsed_ns < 2_000_000_000);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

fn waitFrame(owner: *Terminal, previous: ?*Frame, paint: ?*selection.Paint) !Frame {
    for (0..5000) |_| {
        if (try owner.replaceFrame(previous, paint)) |lease| return lease;
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (status.presentation_failure) |failure| return failure;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}

test "synchronized hold releases a new frame after one second without further child output" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033[?2026hX'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var initial = try waitFrame(owner, null, null);
    const ready_revision = owner.snapshot().revision;
    if (initial.snapshot.terminal_revision < ready_revision) {
        try owner.releaseFrame(initial);
        owner.requestFrame();
        initial = try waitFrame(owner, null, null);
    }
    try std.testing.expectEqual(ready_revision, initial.snapshot.terminal_revision);
    const revision = initial.snapshot.terminal_revision;
    try owner.releaseFrame(initial);
    const start = std.Io.Clock.awake.now(owner.state().io);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    owner.requestFrame();
    const released = try waitFrame(owner, null, null);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(owner.state().io)).toMilliseconds();
    if (elapsed < 800) {
        std.debug.print("hold published too early: {d}ms after input, initial revision {d}, canonical revision {d}\n", .{ elapsed, revision, owner.snapshot().revision });
        return error.EarlyPublication;
    }
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(released) catch unreachable;
    try std.testing.expect(released.snapshot.terminal_revision > revision);
}

test "failed font construction frees the unobservable terminal owner" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var presentation = testPresentation();
    presentation.text.private.regular = .{ .path = .{ .primary = "/definitely-missing-howl-font.ttf", .size = .{ .pixels = 15 } } };
    const owner = Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .rows = 4,
        .columns = 20,
    }, presentation, 0, false);
    try std.testing.expectError(error.FontOpen, owner);
}

fn closeWake(fd: posix.fd_t) void {
    const result = posix.system.close(fd);
    const status = posix.errno(result);
    // Linux consumes the descriptor even when close reports EINTR.
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

test "visibility affirmation cannot manufacture presentation credits; reveal can" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf 'X\\033]0;FIRST\\007'; read line; printf '\\033]0;SECOND\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const initial = try waitFrame(owner, null, null);
    try owner.releaseFrame(initial);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "FIRST");
    for (0..16) |_| owner.setVisible(true);
    try owner.submit(.{ .input = .{ .bytes = "END\n" } });
    try waitTitle(owner, "SECOND");
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    owner.setVisible(false);
    owner.setVisible(true);
    const revealed = try waitFrame(owner, null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(revealed) catch unreachable;
    try std.testing.expectEqual(owner.snapshot().revision, revealed.snapshot.terminal_revision);
}

test "font configuration rolls back failure and replaces geometry while an older immutable lease stays held" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033]0;CONTINUED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var held = try waitFrame(owner, null, null);
    const old_generation = held.presentation_generation;
    const old_size: commands.Size = .{ .width = held.snapshot.cell_width, .height = held.snapshot.cell_height };
    var invalid = testPresentation();
    invalid.text.private.regular = .{ .path = .{ .primary = "/missing-howl-live-font.ttf", .size = .{ .pixels = 18 } } };
    try std.testing.expectError(error.FontOpen, owner.reconfigure(invalid, null));
    try std.testing.expectEqual(old_generation, held.presentation_generation);
    try std.testing.expectEqualDeep(old_size, commands.Size{ .width = held.snapshot.cell_width, .height = held.snapshot.cell_height });
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CONTINUED");
    var larger = testPresentation();
    larger.text.private.regular.path.size = .{ .pixels = 18 };
    const surface: commands.Size = .{ .width = 200, .height = 150 };
    const geometry = try owner.reconfigure(larger, surface);
    try std.testing.expectEqual(surface.width / geometry.cell_size.width, geometry.columns);
    try std.testing.expectEqual(surface.height / geometry.cell_size.height, geometry.rows);
    try std.testing.expectEqual(old_generation, held.presentation_generation);
    try std.testing.expectEqualDeep(old_size, commands.Size{ .width = held.snapshot.cell_width, .height = held.snapshot.cell_height });
    const changed = try waitFrame(owner, &held, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(changed) catch unreachable;
    try std.testing.expect(changed.presentation_generation > old_generation);
    try std.testing.expectEqualDeep(geometry.cell_size, commands.Size{ .width = changed.snapshot.cell_width, .height = changed.snapshot.cell_height });
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "canonical failure rejects or releases borrowed configuration before its caller retires" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try owner.submit(.{ .resize = .{ .rows = 0, .columns = 0 } });
    try std.testing.expectError(error.TerminalStopped, owner.reconfigure(testPresentation(), null));
    try std.testing.expect(owner.snapshot().failure != null);
}

test "releasing a held cut wakes an idle producer that skipped the transfer mutex" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'A\\033]0;READY\\007'; read line; printf 'B\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const held = try waitFrame(owner, null, null);
    const before = held.snapshot.terminal_revision;
    owner.state().frame_mutex.lockUncancelable(threaded.io());
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(threaded.io());
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expect(owner.snapshot().revision > before);
    // Let the worker attempt projection while the transfer lock is still held.
    try std.Io.sleep(threaded.io(), .fromMilliseconds(20), .awake);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    owner.state().frame_mutex.unlock(threaded.io());
    locked = false;
    // The release itself supplies the only post-content wake. No test-only wake
    // and no new canonical input may rescue a missed producer turn.
    try owner.releaseFrame(held);
    const next = try waitFrame(owner, null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test owns the sole new pin and releases it before teardown.
    defer owner.releaseFrame(next) catch unreachable;
    try std.testing.expect(next.snapshot.terminal_revision > before);
}

test "a stalled backend lease transfer cannot pace canonical output; no-frame preserves the accepted lease" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var held = try waitFrame(owner, null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(held) catch unreachable;
    try std.testing.expect(try owner.replaceFrame(&held, null) == null);
    const sequence = held.serial;
    owner.state().frame_mutex.lockUncancelable(owner.state().io);
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(owner.state().io);
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(sequence, held.serial);
    owner.state().frame_mutex.unlock(owner.state().io);
    locked = false;
    owner.requestFrame();
    owner.state().wake();

    const other = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer other.destroy();
    const foreign = try waitFrame(other, null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer other.releaseFrame(foreign) catch unreachable;

    var attempts: u16 = 0;
    while (!owner.state().new_frame.load(.acquire) and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    if (attempts == 5000) return error.Timeout;
    var foreign_copy = foreign;
    try std.testing.expectError(error.InvalidLease, owner.replaceFrame(&foreign_copy, null));
    try std.testing.expectEqual(sequence, held.serial);
    held = try waitFrame(owner, &held, null);
    try std.testing.expect(held.serial > sequence);
    try std.testing.expect(try owner.replaceFrame(&held, null) == null);
}

test "semantic mouse reports and copied caret facts survive without a graphical observer" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033[?1002h\\033[?1006h\\033]0;READY\\007'; bytes=$(dd bs=1 count=18 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf '\\033[2;5H\\033]0;%s\\007' \"$bytes\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const before = owner.snapshot();
    try std.testing.expectEqual(vt.Terminal.MouseTrackingMode.button_event, before.interaction.?.mouse_tracking);
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 1 } } });
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 0 } } });
    try waitTitle(owner, "1b5b3c303b343b334d1b5b3c303b343b336d");
    const after = owner.snapshot();
    try std.testing.expectEqual(@as(u16, 1), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), after.cursor_col);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
}

test "completed reconfiguration fences unread frames from the previous presentation" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf 'HELLO\\033]0;READY\\007'; read line; printf '\\033]0;CONTINUED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var attempts: u16 = 0;
    while (!owner.state().new_frame.load(.acquire) and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    try std.testing.expect(attempts < 5000);
    owner.setVisible(false);
    const configured = try owner.reconfigure(testPresentation(), null);
    try std.testing.expect(configured.cell_size.width > 0);
    // An old unread slot remains native-owned, but cannot enter a fresh backend.
    const hidden = try owner.replaceFrame(null, null);
    if (hidden) |lease| {
        // zig-audit: acknowledge catch_unreachable
        // reason: This test defers the exact live pin's release before destroying its terminal owner.
        defer owner.releaseFrame(lease) catch unreachable;
        std.debug.print("pre-reset unread generation entered the backend: {d}\n", .{lease.presentation_generation});
    }
    try std.testing.expect(hidden == null);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CONTINUED");
    owner.setVisible(true);
    const accepted = try waitFrame(owner, null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(accepted) catch unreachable;
    try std.testing.expect(accepted.presentation_generation > 1);
}

fn waitCopy(owner: *Terminal, request: *Copy) void {
    const state = owner.state();
    state.mutex.lockUncancelable(state.io);
    while (!request.complete) state.request_completed.waitUncancelable(state.io, &state.mutex);
    state.mutex.unlock(state.io);
}

test "hidden canonical selection copies Unicode in FIFO order without presentation authority" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'alpha beta gamma\\r\\nwide: \\347\\225\\214 e\\314\\201\\033]0;READY\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const context: selection.Context = .{ .rows = 4, .columns = 20, .history_count = 0, .history_row_base = 0, .history_offset = 0, .alternate = false };
    try std.testing.expectError(error.NoSelection, owner.copySelection(std.testing.allocator, 128));
    try std.testing.expectError(error.CopyLimit, owner.copySelection(std.testing.allocator, 0));
    try std.testing.expectError(error.CopyLimit, owner.copySelection(std.testing.allocator, input_byte_limit + 1));
    try owner.submit(.{ .select = .{ .serial = 1, .kind = .word, .context = context, .point = .{ .row = 0, .col = 7 } } });
    var first: Copy = .{ .allocator = std.testing.allocator, .max_bytes = 128 };
    try owner.state().admit(.{ .copy = &first });
    defer {
        waitCopy(owner, &first);
        if (first.result) |bytes| std.testing.allocator.free(bytes);
    }
    try owner.submit(.{ .select = .{ .serial = 2, .kind = .row, .context = context, .point = .{ .row = 1, .col = 0 } } });
    const line = try owner.copySelection(std.testing.allocator, 128);
    defer std.testing.allocator.free(line);
    waitCopy(owner, &first);
    try std.testing.expect(first.failure == null);
    try std.testing.expectEqualStrings("beta", first.result.?);
    try std.testing.expectEqualStrings("wide: \xe7\x95\x8c e\xcc\x81", line);
    try std.testing.expectError(error.TextLimit, owner.copySelection(std.testing.allocator, 3));
    try owner.submit(.{ .resize = .{ .rows = 4, .columns = 19 } });
    try std.testing.expectError(error.SelectionContextChanged, owner.copySelection(std.testing.allocator, 128));
    try owner.submit(.{ .select = .{ .serial = 3, .kind = .word, .context = context, .point = .{ .row = 0, .col = 7 } } });
    try std.testing.expectError(error.SelectionContextChanged, owner.copySelection(std.testing.allocator, 128));
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    try std.testing.expect(owner.snapshot().failure == null);
}

test "selection paint travels with its immutable lease and a stalled transfer cannot pace canonical progress" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'alpha beta gamma\\033]0;READY\\007'; read line; printf '\\033[2J\\033[Homega psi chi\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const context: selection.Context = .{ .rows = 4, .columns = 20, .history_count = 0, .history_row_base = 0, .history_offset = 0, .alternate = false };
    try owner.submit(.{ .select = .{ .serial = 11, .kind = .word, .context = context, .point = .{ .row = 0, .col = 7 } } });
    const word = try owner.copySelection(std.testing.allocator, 128);
    defer std.testing.allocator.free(word);
    try std.testing.expectEqualStrings("beta", word);
    var paint: selection.Paint = .{};
    owner.setVisible(true);
    var held = try waitFrame(owner, null, &paint);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owner.releaseFrame(held) catch unreachable;
    try std.testing.expectEqual(@as(u64, 11), paint.serial);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 9 }), paint.spanAt(0));
    const sequence = held.serial;
    owner.state().frame_mutex.lockUncancelable(threaded.io());
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(threaded.io());
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(sequence, held.serial);
    try std.testing.expect(try owner.replaceFrame(&held, &paint) == null);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 9 }), paint.spanAt(0));
    try std.testing.expectError(error.NoSelection, owner.copySelection(std.testing.allocator, 128));
    owner.state().frame_mutex.unlock(threaded.io());
    locked = false;
    owner.requestFrame();
    owner.state().wake();
    held = try waitFrame(owner, &held, &paint);
    try std.testing.expect(held.serial > sequence);
    try std.testing.expectEqual(@as(u64, 11), paint.serial);
    for (0..paint.rows) |row| try std.testing.expect(paint.spanAt(row) == null);
    const fresh_context = try selection.Context.fromFrame(@import("frame_info.zig").Info.fromSnapshot(&held.snapshot, held.presentation_generation, held.serial));
    try owner.submit(.{ .select = .{ .serial = 12, .kind = .word, .context = fresh_context, .point = .{ .row = try fresh_context.row(0), .col = 7 } } });
    const next = try owner.copySelection(std.testing.allocator, 128);
    defer std.testing.allocator.free(next);
    try std.testing.expectEqualStrings("psi", next);
    owner.requestFrame();
    held = try waitFrame(owner, &held, &paint);
    try std.testing.expectEqual(@as(u64, 12), paint.serial);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 8 }), paint.spanAt(0));
    try std.testing.expect(try owner.replaceFrame(&held, &paint) == null);
    try std.testing.expectEqual(@as(u64, 12), paint.serial);
}

test "canonical failure cancels or rejects borrowed copy requests before caller retirement" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try owner.submit(.{ .resize = .{ .rows = 0, .columns = 0 } });
    try std.testing.expectError(error.TerminalStopped, owner.copySelection(std.testing.allocator, 128));
    const context: selection.Context = .{ .rows = 4, .columns = 20, .history_count = 0, .history_row_base = 0, .history_offset = 0, .alternate = false };
    try std.testing.expectError(error.TerminalStopped, owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 0 }));
    try std.testing.expect(owner.snapshot().failure != null);
}

fn waitSearch(owner: *Terminal, serial: u64, phase: find.Phase) !Status {
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (status.search.serial == serial and status.search.phase == phase) return status;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}
test "hidden retained-history find refreshes stale cuts and never steals a later pointer selection" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; i=0; while [ \"$i\" -lt 100 ]; do printf 'needle %03d\\r\\n' \"$i\"; i=$((i+1)); done; printf '\\033]0;READY\\007'; read line; printf 'needle NEW\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 128,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try owner.submit(.{ .find = try find.Request.query(1, "needle") });
    const initial = try waitSearch(owner, 1, .complete);
    try std.testing.expectEqual(@as(u16, 100), initial.search.count);
    try std.testing.expectEqual(@as(?u16, 0), initial.search.current);
    try std.testing.expect(initial.selected.?.anchor.row < 10);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    const text = try owner.copySelection(std.testing.allocator, 128);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("needle", text);
    try owner.submit(.{ .find = .{ .serial = 2, .kind = .next } });
    const next = try waitSearch(owner, 2, .complete);
    try std.testing.expectEqual(@as(?u16, 1), next.search.current);
    try std.testing.expect(next.selected.?.anchor.row > initial.selected.?.anchor.row);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    const stale = try waitSearch(owner, 2, .stale);
    try std.testing.expect(stale.selected == null);
    try owner.submit(.{ .find = .{ .serial = 3, .kind = .previous } });
    const refreshed = try waitSearch(owner, 3, .complete);
    try std.testing.expectEqual(@as(u16, 101), refreshed.search.count);
    // Query and later pointer intent share one FIFO; incremental first-match navigation
    // must honor the later selection serial even when no graphical observer exists.
    try owner.submit(.{ .find = try find.Request.query(4, "needle") });
    const context: selection.Context = .{ .rows = 4, .columns = 20, .history_count = 97, .history_row_base = 0, .history_offset = 0, .alternate = false };
    try owner.submit(.{ .select = .{ .serial = 5, .kind = .start, .context = context, .point = .{ .row = 99, .col = 7 } } });
    const manual = try waitSearch(owner, 4, .complete);
    try std.testing.expectEqual(@as(u64, 5), manual.selection_serial);
    try std.testing.expectEqual(@as(i32, 99), manual.selected.?.anchor.row);
    try std.testing.expectEqual(@as(u16, 7), manual.selected.?.anchor.col);
    try owner.submit(.{ .find = .{ .serial = 6, .kind = .close } });
    const closed = try waitSearch(owner, 6, .idle);
    try std.testing.expect(closed.selected == null);
    try std.testing.expectError(error.NoSelection, owner.copySelection(std.testing.allocator, 128));
    try owner.submit(.{ .find = .{ .serial = 7, .kind = .query, .len = 65535 } });
    const invalid = try waitSearch(owner, 7, .failed);
    try std.testing.expectEqual(error.InvalidQuery, invalid.search.failure.?);
    try std.testing.expect(invalid.failure == null);
}

test "incremental hidden find cannot fence canonical input and one MiB output behind observer progress" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; i=0; while [ \"$i\" -lt 1000 ]; do printf 'needle %04d\\r\\n' \"$i\"; i=$((i+1)); done; printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 2048,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try owner.submit(.{ .find = try find.Request.query(1, "never") });
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    const status = try waitSearch(owner, 1, .stale);
    try std.testing.expect(status.failure == null);
    try std.testing.expect(status.selected == null);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
}

test "retained desktop replies flush in exact FIFO while hidden and attention never paces canonical service" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033]52;c;?\\007\\033]22;?\\007\\033[?996n\\033[19t\\033[11t\\033[13t\\033[20t\\033[5t\\033]9;message\\007'; actual=$(dd bs=1 count=41 2>/dev/null | od -An -v -tx1 | tr -d ' \\n'); if [ \"$actual\" = '1b5d35323b633b1b5c1b5d32323b64656661756c741b5c1b5b3f3939373b316e1b5b393b343b323074' ]; then printf '\\033]0;REPLIED\\007'; else printf '\\033]0;BAD_REPLY\\007'; fi; read line; printf '\\007\\007\\033]1337;RequestAttention=yes\\007\\033]1337;StealFocus\\007\\033]0;ATTENTION\\007'; read line; printf '\\033]9;ordinary message\\007\\033]52;c;SGVsbG8=\\007\\033]0;MESSAGE\\007'; read line; i=0; while [ \"$i\" -lt 200 ]; do printf '\\007\\033]1337;RequestAttention=burst\\007'; i=$((i+1)); done; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    // The child emits only the queries before blocking on all exact replies.
    // No observer credit or later child output can flush them on our behalf.
    try waitTitle(owner, "REPLIED");
    try std.testing.expect(!owner.takeAttention());
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "ATTENTION");
    try std.testing.expect(owner.takeAttention());
    try std.testing.expect(!owner.takeAttention());
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "MESSAGE");
    try std.testing.expect(!owner.takeAttention());
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expect(owner.takeAttention());
    try std.testing.expect(!owner.takeAttention());
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    try std.testing.expect(owner.snapshot().failure == null);
}

test "canonical hyperlink copy owns UTF8 and resolves retained rows while refusing bank columns and eviction" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]8;id=one;https://howl.example/owned?q=1\\033\\\\界X\\033]8;;\\033\\\\\\r\\nplain\\r\\n\\033]0;READY\\007'; read line; i=0; while [ \"$i\" -lt 5 ]; do printf 'later\\r\\n'; i=$((i+1)); done; printf '\\033]0;SCROLLED\\007'; read line; printf '\\033[?1049hALT\\033]0;ALT\\007'; read line; printf '\\033[?1049l\\033]0;NORMAL\\007'; read line; i=0; while [ \"$i\" -lt 20 ]; do printf 'evicted\\r\\n'; i=$((i+1)); done; printf '\\033]0;EVICTED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const context: selection.Context = .{ .rows = 4, .columns = 20, .history_count = 0, .history_row_base = 0, .history_offset = 0, .alternate = false };
    const uri = try owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 0 });
    defer std.testing.allocator.free(uri);
    try std.testing.expectEqualStrings("https://howl.example/owned?q=1", uri);
    const continuation = try owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 1 });
    defer std.testing.allocator.free(continuation);
    try std.testing.expectEqualStrings(uri, continuation);
    try std.testing.expectError(error.NoHyperlink, owner.copyHyperlink(std.testing.allocator, context, .{ .row = 1, .col = 0 }));
    try std.testing.expectError(error.InvalidSelection, owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 20 }));
    try std.testing.expectError(error.InvalidSelection, owner.copyHyperlink(std.testing.allocator, context, .{ .row = -1, .col = 0 }));
    try std.testing.expectError(error.HyperlinkLimit, owner.state().copy(std.testing.allocator, 3, .{ .context = context, .point = .{ .row = 0, .col = 0 } }));
    var changed = context;
    changed.columns = 19;
    try std.testing.expectError(error.SelectionContextChanged, owner.copyHyperlink(std.testing.allocator, changed, .{ .row = 0, .col = 0 }));
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "SCROLLED");
    const retained = try owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 0 });
    defer std.testing.allocator.free(retained);
    try std.testing.expectEqualStrings(uri, retained);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "ALT");
    try std.testing.expectError(error.SelectionContextChanged, owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 0 }));
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "NORMAL");
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "EVICTED");
    try std.testing.expectError(error.SelectionEvicted, owner.copyHyperlink(std.testing.allocator, context, .{ .row = 0, .col = 0 }));
    try std.testing.expectEqualStrings("https://howl.example/owned?q=1", uri);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    try std.testing.expect(owner.snapshot().failure == null);
}

test "owned file and text drops preserve exact canonical bracketed paste after caller buffers retire" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033[?2004h\\033]0;READY\\007'; actual=$(dd bs=1 count=100 2>/dev/null | od -An -v -tx1 | tr -d ' \\n'); if [ \"$actual\" = '1b5b3230307e272f6e6f7465732f4361707461696e275c272773202428746f756368206e6f7065292e74787427201b5b3230317e1b5b3230307ee7958c206c696e65206f6e650a2428746f756368206e6f7065293b206c696e652074776f1b5b3230317e' ]; then printf '\\033]0;EXACT\\007'; else printf '\\033]0;BAD_DROP\\007'; fi; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var output: [desktop.quoted_limit]u8 = undefined;
    const quoted = try desktop.quoteFile("/notes/Captain's $(touch nope).txt", &output);
    try owner.submit(.{ .input = .{ .paste = quoted } });
    @memset(&output, '?');
    const original = try std.testing.allocator.dupe(u8, "界 line one\n$(touch nope); line two");
    try owner.submit(.{ .input = .{ .paste = try desktop.dropText(original) } });
    @memset(original, '?');
    std.testing.allocator.free(original);
    try waitTitle(owner, "EXACT");
    try std.testing.expect(owner.snapshot().failure == null);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
}

test "shared text serves concurrent workers while one observer stalls and native ownership retires" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var config = testPresentation();
    // Bound each render below atlas capacity, but pressure the shared shape store.
    config.shape_cache.entry_capacity = 4;
    config.shape_cache.scalar_capacity = 16;
    config.shape_cache.glyph_capacity = 16;
    const shared = try vt_output.initPresentationStore(a, threaded.io(), config.text.private, .{
        .shape_cache = config.shape_cache,
        .shaped_capacity = config.shaped_capacity,
        .raster_bytes = config.raster_bytes,
    });
    var caller_live = true;
    defer if (caller_live) vt_output.releasePresentationStore(shared);
    config.text = .{ .shared = shared };
    var owners: [2]*Terminal = undefined;
    var count: usize = 0;
    defer for (owners[0..count]) |owner| owner.destroy();
    for (&owners) |*slot| {
        const command_text = try std.fmt.allocPrint(a, "printf '\\033]0;READY\\007'; read line; i=0; while [ $i -lt 200 ]; do printf '\\033[2J\\033[H\\033[1m{c}\\033[0m{c}\\033[3m{c}\\033[0m{c}'; i=$((i+1)); done; printf '\\033[2J\\033[HOK\\033]0;DONE\\007'; sleep 30", .{ @as(u8, 'A') + @as(u8, @intCast(count * 4)), @as(u8, 'B') + @as(u8, @intCast(count * 4)), @as(u8, 'C') + @as(u8, @intCast(count * 4)), @as(u8, 'D') + @as(u8, @intCast(count * 4)) });
        defer a.free(command_text);
        slot.* = try Terminal.create(a, threaded.io(), std.testing.environ, .{
            .shell = "/bin/sh",
            .command = command_text,
            .rows = 4,
            .columns = 20,
            .history_rows = 8,
        }, config, c.SDL_RegisterEvents(1), true);
        count += 1;
    }
    for (owners) |owner| try waitTitle(owner, "READY");
    const held = try waitFrame(owners[0], null, null);
    // zig-audit: acknowledge catch_unreachable
    // reason: This test defers the exact live pin's release before destroying its terminal owner.
    defer owners[0].releaseFrame(held) catch unreachable;
    const before = held.snapshot.terminal_revision;
    const glyph_count = held.snapshot.glyphs[0].len;
    vt_output.releasePresentationStore(shared);
    caller_live = false;
    for (owners) |owner| try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    var attempts: u16 = 0;
    var accepted_revision: ?u64 = null;
    while (attempts < 5000) : (attempts += 1) {
        const live = owners[1];
        if (try live.replaceFrame(null, null)) |ready| {
            accepted_revision = ready.snapshot.terminal_revision;
            try live.releaseFrame(ready);
            live.requestFrame();
        }
        const status = live.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "DONE") and accepted_revision == status.revision) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    try waitTitle(owners[0], "DONE");
    for (owners) |owner| {
        try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
        try std.testing.expectEqual(@as(?PresentationFailure, null), owner.snapshot().presentation_failure);
    }
    try std.testing.expectEqual(before, held.snapshot.terminal_revision);
    try std.testing.expectEqual(glyph_count, held.snapshot.glyphs[0].len);
}

test "cursor activity coalesces accepted typing and paste without echo; releases modifiers and rejected work stay quiet" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; sleep 30",
        .rows = 2,
        .columns = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const revision = owner.snapshot().revision;
    try std.testing.expect(!owner.takeInputActivity());
    for ([_]Task{
        .{ .input = .{ .bytes = "" } },
        .{ .input = .{ .paste = "" } },
        .{ .input = .{ .focus = .in } },
        .{ .input = .{ .key = .{ .key = .{ .named = .enter }, .action = .release } } },
        .{ .input = .{ .key = .{ .key = .{ .named = .left_shift }, .action = .press } } },
    }) |task| {
        try owner.submit(task);
        try std.testing.expect(!owner.takeInputActivity());
    }
    try owner.submit(.{ .input = .{ .bytes = "a" } });
    try owner.submit(.{ .input = .{ .paste = "b" } });
    try std.testing.expect(owner.takeInputActivity());
    try std.testing.expect(!owner.takeInputActivity());
    try owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .left }, .action = .repeat } } });
    try std.testing.expect(owner.takeInputActivity());
    try std.testing.expectError(error.BorrowedKeyText, owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter }, .legacy_text = "borrow" } } }));
    try std.testing.expect(!owner.takeInputActivity());
    try std.Io.sleep(threaded.io(), .fromMilliseconds(20), .awake);
    try std.testing.expectEqual(revision, owner.snapshot().revision);
    // Only these fields are reachable before the full-queue rejection; no
    // process, descriptor, wake or uninitialized queue slot is accessed.
    var full: State = undefined;
    full.allocator = std.testing.allocator;
    full.io = threaded.io();
    full.mutex = .init;
    full.stopping = false;
    full.status = .{};
    full.count = queue_limit;
    full.input_bytes = 0;
    full.input_activity = .init(false);
    try std.testing.expectError(error.InputQueueFull, full.submit(.{ .input = .{ .bytes = "rejected" } }));
    try std.testing.expect(!full.input_activity.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), full.input_bytes);
}

test "direct worker publishes the sole VT while a previous cut is held" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033[?25lFIRST\\033]0;READY\\007'; read line; printf '\\r\\nSECOND\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var first: ?Frame = null;
    for (0..5000) |_| {
        first = try owner.replaceFrame(null, null);
        if (first != null) break;
        if (owner.snapshot().presentation_failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    var held = first orelse return error.Timeout;
    var pinned = true;
    // zig-audit: acknowledge catch_unreachable
    // reason: The test releases the sole held direct lease before worker destruction.
    defer if (pinned) owner.releaseFrame(held) catch unreachable;
    if (held.snapshot.glyphs[0].len == 0) {
        owner.requestFrame();
        held = try waitFrame(owner, &held, null);
    }
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const initial = held.snapshot.terminal_revision;
    const old_first = held.snapshot.glyphs[0][0];
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(initial, held.snapshot.terminal_revision);
    try std.testing.expectEqualDeep(old_first, held.snapshot.glyphs[0][0]);
    owner.requestFrame();
    var next: ?Frame = null;
    for (0..5000) |_| {
        next = try owner.replaceFrame(&held, null);
        if (next != null) break;
        if (owner.snapshot().presentation_failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    held = next orelse return error.Timeout;
    try std.testing.expect(held.snapshot.terminal_revision > initial);
    var glyph_count: usize = 0;
    for (held.snapshot.glyphs[0..held.snapshot.rows]) |glyphs| glyph_count += glyphs.len;
    try std.testing.expect(glyph_count != 0);
    try owner.releaseFrame(held);
    pinned = false;
}

// Test-only allocator that fails exactly the first scalar-pool expansion size.
const ScalarPressureAllocator = struct {
    child: std.mem.Allocator,
    armed: std.atomic.Value(bool) = .init(false),
    failures: std.atomic.Value(u32) = .init(0),

    fn allocator(self: *ScalarPressureAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = allocate, .resize = resize, .remap = remap, .free = free } };
    }
    // zig-audit: acknowledge anyopaque
    // reason: The standard allocator vtable passes the concrete test owner as opaque context.
    fn cast(ctx: *anyopaque) *ScalarPressureAllocator {
        // zig-audit: acknowledge ptr_cast
        // reason: This context was created from a live ScalarPressureAllocator.
        // zig-audit: acknowledge align_cast
        // reason: Allocator vtable calls preserve the alignment supplied at construction.
        return @ptrCast(@alignCast(ctx));
    }
    // zig-audit: acknowledge anyopaque
    // reason: The standard allocator vtable supplies the test owner as opaque context.
    fn allocate(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self = cast(ctx);
        const ScreenState = @FieldType(vt.Terminal, "screen_state");
        const Screen = @FieldType(ScreenState, "primary");
        const Storage = @typeInfo(@FieldType(Screen, "scalars")).optional.child;
        const Page = @typeInfo(@FieldType(Storage, "pages")).pointer.child;
        if (len == 2 * @sizeOf(Page) and self.armed.load(.acquire)) {
            // zig-audit: acknowledge discard
            // reason: The test only needs the cumulative count, not the previous value.
            _ = self.failures.fetchAdd(1, .monotonic);
            return null;
        }
        return self.child.rawAlloc(len, alignment, ra);
    }
    // zig-audit: acknowledge anyopaque
    // reason: The standard allocator vtable supplies the test owner as opaque context.
    fn resize(ctx: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) bool {
        return cast(ctx).child.rawResize(bytes, alignment, len, ra);
    }
    // zig-audit: acknowledge anyopaque
    // reason: The standard allocator vtable supplies the test owner as opaque context.
    fn remap(ctx: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
        return cast(ctx).child.rawRemap(bytes, alignment, len, ra);
    }
    // zig-audit: acknowledge anyopaque
    // reason: The standard allocator vtable supplies the test owner as opaque context.
    fn free(ctx: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        cast(ctx).child.rawFree(bytes, alignment, ra);
    }
};

test "direct worker backs off scalar pressure and applies queued resize after recovery" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var pressure = ScalarPressureAllocator{ .child = std.testing.allocator };
    const owner = try Terminal.create(pressure.allocator(), threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; i=0; while [ $i -lt 511 ]; do printf 'e\\314\\201\\314\\202\\314\\203\\314\\204\\314\\205\\314\\206\\314\\207\\314\\210'; i=$((i+1)); done; printf 'X\\033]0;DONE\\007'; sleep 30",
        .rows = 1,
        .columns = 512,
        .history_rows = 0,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    pressure.armed.store(true, .release);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    var saw_failure = false;
    for (0..5000) |_| {
        if (pressure.failures.load(.acquire) != 0) {
            saw_failure = true;
            break;
        }
        if (owner.snapshot().failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(saw_failure);
    try owner.submit(.{ .resize = .{ .rows = 1, .columns = 512 } });
    try std.Io.sleep(threaded.io(), .fromMilliseconds(250), .awake);
    const failures = pressure.failures.load(.acquire);
    try std.testing.expect(failures >= 2 and failures <= 6);
    try std.testing.expect(owner.snapshot().failure == null);
    pressure.armed.store(false, .release);
    try waitTitle(owner, "DONE");
    try std.testing.expect(owner.snapshot().failure == null);
    const state = owner.state();
    state.mutex.lockUncancelable(state.io);
    const queued = state.count;
    state.mutex.unlock(state.io);
    try std.testing.expectEqual(@as(usize, 0), queued);
}

test "direct worker recovers on a clean alternate screen with primary image retained" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'READY\\033]0;READY\\007'; read line; printf '\\033_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\\033\\\\\\033]0;IMAGE\\007'; read line; printf '\\033[?1049hALT\\033]0;ALT\\007'; read line; printf '\\033[?1049l\\033]0;PRIMARY\\007'; read line; printf '\\033_Ga=d,d=A,q=2\\033\\\\\\033]0;CLEARED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var first: ?Frame = null;
    for (0..5000) |_| {
        first = try owner.replaceFrame(null, null);
        if (first != null) break;
        if (owner.snapshot().presentation_failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    var held = first orelse return error.Timeout;
    var pinned = true;
    // zig-audit: acknowledge catch_unreachable
    // reason: This test releases the one pinned direct lease before worker teardown.
    defer if (pinned) owner.releaseFrame(held) catch unreachable;
    if (held.snapshot.glyphs[0].len == 0) {
        owner.requestFrame();
        held = try waitFrame(owner, &held, null);
    }
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    const initial = held.snapshot.terminal_revision;
    const original = held.snapshot.glyphs[0][0];
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "IMAGE");
    owner.requestFrame();
    try std.testing.expectEqualDeep(original, held.snapshot.glyphs[0][0]);
    held = try waitFrame(owner, &held, null);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.positive.len);
    try std.testing.expectEqual(@as(?PresentationFailure, null), owner.snapshot().presentation_failure);

    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "ALT");
    owner.requestFrame();
    held = try waitFrame(owner, &held, null);
    try std.testing.expect(held.snapshot.alternate);
    try std.testing.expect(held.snapshot.terminal_revision > initial);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);

    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "PRIMARY");
    owner.requestFrame();
    held = try waitFrame(owner, &held, null);
    try std.testing.expect(!held.snapshot.alternate);
    try std.testing.expectEqual(@as(usize, 1), held.snapshot.graphics.images.len);

    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CLEARED");
    owner.requestFrame();
    held = try waitFrame(owner, &held, null);
    try std.testing.expectEqual(@as(usize, 0), held.snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(?PresentationFailure, null), owner.snapshot().presentation_failure);
    try owner.releaseFrame(held);
    pinned = false;
}

test "direct worker draws a multi-row continuation after history scroll" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033[?25l\\033]66;s=2;X\\007\\033[S\\033]0;SCROLLED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var first: ?Frame = null;
    for (0..5000) |_| {
        first = try owner.replaceFrame(null, null);
        if (first != null) break;
        if (owner.snapshot().presentation_failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    var held = first orelse return error.Timeout;
    var pinned = true;
    // zig-audit: acknowledge catch_unreachable
    // reason: The single direct lease is released before worker teardown.
    defer if (pinned) owner.releaseFrame(held) catch unreachable;
    const initial = held.snapshot.terminal_revision;
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "SCROLLED");
    owner.requestFrame();
    var next: ?Frame = null;
    for (0..5000) |_| {
        next = try owner.replaceFrame(&held, null);
        if (next != null) break;
        if (owner.snapshot().presentation_failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    held = next orelse return error.Timeout;
    try std.testing.expect(held.snapshot.terminal_revision > initial);
    try std.testing.expect(held.snapshot.glyphs[0].len != 0);
    try owner.releaseFrame(held);
    pinned = false;
}

test "held output releases on timeout without new child output, then resets on exact release" {
    var gate: OutputGate = .{ .pending = false };
    gate.note(7, true, false, 100);
    try std.testing.expect(gate.pending);
    try std.testing.expect(!gate.released(true));
    try std.testing.expectEqual(@as(?i32, 1000), gate.waitMs(100));
    gate.note(7, true, false, 100 + std.time.ns_per_s);
    try std.testing.expect(gate.released(true));
    try std.testing.expectEqual(@as(?i32, null), gate.waitMs(100 + std.time.ns_per_s));
    gate.pending = false;
    gate.note(8, true, true, 200 + std.time.ns_per_s);
    try std.testing.expect(!gate.released(true));
    gate.note(8, false, false, 201 + std.time.ns_per_s);
    try std.testing.expect(gate.released(false));
}

test "history anchor follows output, clamps eviction and resets alternate screen" {
    var history: HistoryViewport = .{};
    history.seek(20, 100, 10, false);
    history.follow(110, 10, false);
    try std.testing.expectEqual(@as(u32, 30), history.offset);
    try std.testing.expectEqual(@as(?u64, 90), history.anchor);
    history.follow(15, 100, false);
    try std.testing.expectEqual(@as(u32, 15), history.offset);
    try std.testing.expectEqual(@as(?u64, 100), history.anchor);
    history.follow(15, 100, true);
    try std.testing.expectEqual(@as(u32, 0), history.offset);
}
