const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const policy = @import("publication.zig");
const selection = @import("selection.zig");
const find = @import("find.zig");
const desktop = @import("desktop.zig");
const posix = std.posix;

const queue_limit = 64;
const input_byte_limit = 1024 * 1024;

/// Bounded asynchronous semantic input and presentation-geometry intent.
pub const Task = union(enum) {
    input: instance.Input,
    resize: struct { rows: u16, columns: u16 },
    scroll: i32,
    seek: u32,
    retry_render,
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
    point: instance.Terminal.TextPoint = .{ .row = 0, .col = 0 },
};
/// Noncanonical selection failures never stop process/VT service.
pub const SelectionError = error{ InvalidSelection, SelectionContextChanged, SelectionEvicted };
/// Bounded canonical extraction and FIFO admission failures.
pub const CopyError = instance.Terminal.TextError || SelectionError || error{ NoSelection, NoHyperlink, HyperlinkLimit, CopyLimit, TerminalStopped, InputQueueFull };
const Link = struct { context: selection.Context, point: instance.Terminal.TextPoint };
const Copy = struct {
    link: ?Link = null,
    allocator: std.mem.Allocator,
    max_bytes: usize,
    result: ?[]const u8 = null,
    failure: ?CopyError = null,
    complete: bool = false,
};

/// Exact failures produced by this terminal worker's owned operations.
pub const Failure = instance.InputError || instance.ResizeError ||
    instance.ServiceError || std.posix.PollError || desktop.Error;

/// Projection failure stays separate from canonical I/O and never stops PTY/VT service.
pub const PresentationFailure = instance.PublishError || error{SDLNotification};

/// Immutable lease transfer failures; no-frame leaves the previously accepted lease untouched.
pub const FrameError = instance.RenderLease.ReleaseError || error{ WrongExchange, NoPublishedFrame };

/// Exact transactional configuration/admission failures; old presentation survives failure.
pub const ConfigureError = instance.ReconfigurePresentationError || error{ TerminalStopped, InputQueueFull };

const Configuration = struct {
    config: instance.PresentationConfig,
    surface: ?instance.render.terminal.Size,
    result: ?instance.PresentationGeometry = null,
    failure: ?ConfigureError = null,
    complete: bool = false,
};
const Work = union(enum) { intent: Task, configure: *Configuration, copy: *Copy };

/// Copied interaction/lifecycle facts; contains no borrowed canonical storage.
pub const Status = struct {
    title: [1024]u8 = undefined,
    title_len: usize = 0,
    failure: ?Failure = null,
    presentation_failure: ?PresentationFailure = null,
    revision: u64 = 0,
    closed: bool = false,
    child_exit: ?instance.ChildExit = null,
    selected: ?selection.Range = null,
    selection_serial: u64 = 0,
    selection_failure: ?SelectionError = null,
    search: find.Status = .{},
    interaction: ?instance.Terminal.InteractionState = null,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
};

/// Typed ownership boundary. SDL cannot obtain the live canonical Instance.
/// This is ordinary Zig composition; no C ABI, exported symbols or catalogue.
// zig-audit: acknowledge opaque_type
// reason: The terminal worker's canonical Instance and queue ownership must be inaccessible to the graphical consumer.
pub const Terminal = opaque {
    /// Constructs and starts one sole terminal owner; rolls back completed resources on failure.
    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: instance.Launch,
        presentation: instance.PresentationConfig,
        event_type: u32,
        initially_visible: bool,
    ) !*Terminal {
        // zig-audit: acknowledge ptr_cast
        // reason: State owns this allocation; the opaque pointer keeps SDL outside canonical mutation authority without changing address or lifetime.
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
    /// Borrows a font recipe only until the sole worker completes its transaction.
    /// Waiting is uncancelable, so queued configuration cannot outlive these borrowed paths.
    pub fn reconfigure(self: *Terminal, config: instance.PresentationConfig, surface: ?instance.render.terminal.Size) ConfigureError!instance.PresentationGeometry {
        return self.state().reconfigure(config, surface);
    }
    /// Copies the FIFO-selected canonical range into bounded caller-owned UTF-8 storage.
    pub fn copySelection(self: *Terminal, allocator: std.mem.Allocator, max_bytes: usize) CopyError![]const u8 {
        return self.state().copySelection(allocator, max_bytes);
    }
    /// Copies one clicked canonical OSC 8 URI through the same bounded FIFO completion.
    pub fn copyHyperlink(self: *Terminal, allocator: std.mem.Allocator, context: selection.Context, point: instance.Terminal.TextPoint) CopyError![]const u8 {
        return self.state().copy(allocator, desktop.uri_limit, .{ .context = context, .point = point });
    }
    /// Takes one coalesced copied attention fact without blocking canonical service.
    pub fn takeAttention(self: *Terminal) bool {
        return self.state().attention.swap(false, .acq_rel);
    }
    /// Changes projection visibility without changing canonical service policy.
    pub fn setVisible(self: *Terminal, visible: bool) void {
        self.state().setVisible(visible);
    }
    /// Grants one projection credit after presentation or an explicit reveal.
    pub fn requestFrame(self: *Terminal) void {
        self.state().requestFrame();
    }
    /// Replaces the backend's old lease only when another publication is ready.
    /// A null result preserves the old lease; the short transfer contains no SDL work.
    pub fn replaceFrame(self: *Terminal, previous: ?*instance.RenderLease, residency: []const instance.render.terminal.Residency, paint: ?*selection.Paint) FrameError!?instance.RenderLease {
        return self.state().replaceFrame(previous, residency, paint);
    }

    fn state(self: *Terminal) *State {
        // zig-audit: acknowledge ptr_cast
        // reason: This module owns the concrete allocation behind its terminal-worker authority boundary.
        // zig-audit: acknowledge align_cast
        // reason: Only State.create produces Terminal pointers, preserving State alignment for their entire lifetime.
        return @ptrCast(@alignCast(self));
    }
};

/// Main owns lifetime; its terminal worker owns every live Instance mutation.
/// Main sees only immutable frame leases and bounded copied interaction facts.
const State = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *instance.Instance,
    exchange: *instance.RenderExchange,
    wake_fd: posix.fd_t,
    event_type: u32,
    thread: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    configured: std.Io.Condition = .init,
    frame_mutex: std.Io.Mutex = .init,
    tasks: [queue_limit]Work = undefined,
    head: usize = 0,
    count: usize = 0,
    input_bytes: usize = 0,
    stopping: bool = false,
    status: Status = .{},
    visible: std.atomic.Value(bool) = .init(true),
    credit: std.atomic.Value(bool) = .init(true),
    new_frame: std.atomic.Value(bool) = .init(false),
    gate: policy.Gate = .{},
    // Block only the content/viewport which failed; canonical service remains independent.
    store_busy: bool = false,
    blocked_presentation: ?struct { content_sequence: u64, history_offset: u32 } = null,
    history: policy.History = .{},
    selected: ?selection.Range = null,
    selection_serial: u64 = 0,
    selection_failure: ?SelectionError = null,
    paint: selection.Paint = .{},
    search: find.Find = .{},
    attention: std.atomic.Value(bool) = .init(false),
    consequence_worked: bool = false,

    fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: instance.Launch,
        presentation: instance.PresentationConfig,
        event_type: u32,
        initially_visible: bool,
    ) !*State {
        const self = try allocator.create(State);
        errdefer allocator.destroy(self);
        const value = try instance.initPresented(allocator, environ, launch, presentation);
        errdefer instance.deinit(value);
        const exchange = try instance.renderExchange(value);
        const fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (fd < 0) return error.WakeFailed;
        errdefer closeWake(fd);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .value = value,
            .exchange = exchange,
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
        closeWake(self.wake_fd);
        instance.deinit(self.value);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn takeFrame(self: *State) bool {
        return self.new_frame.swap(false, .acq_rel);
    }

    fn replaceFrame(self: *State, previous: ?*instance.RenderLease, residency: []const instance.render.terminal.Residency, paint: ?*selection.Paint) FrameError!?instance.RenderLease {
        if (!self.new_frame.load(.acquire)) {
            // Reconfiguration or a stalled transfer may still owe a credit-backed publication.
            if (self.credit.load(.acquire)) self.wake();
            return null;
        }
        self.frame_mutex.lockUncancelable(self.io);
        defer {
            self.frame_mutex.unlock(self.io);
            // A producer that skipped this short transfer never waits for the GUI.
            if (self.credit.load(.acquire)) self.wake();
        }
        if (!self.new_frame.load(.acquire)) return null;
        if (previous) |lease| {
            if (lease.exchange != self.exchange) return error.WrongExchange;
            try lease.release(residency);
        }
        const lease = instance.acquirePublishedFrame(self.exchange) orelse return error.NoPublishedFrame;
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
        if (bytes.len > input_byte_limit) return error.InputLimit;
        // Key events contain no asynchronous borrowed text in this app.
        if (task == .input and task.input == .key and
            (task.input.key.text.len != 0 or task.input.key.legacy_text.len != 0))
            return error.BorrowedKeyText;
        if (bytes.len != 0) {
            const owned = try self.allocator.dupe(u8, bytes);
            switch (task.input) {
                .bytes => task.input.bytes = owned,
                .paste => task.input.paste = owned,
                // zig-audit: acknowledge unreachable
                // reason: taskBytes can return nonempty bytes only for these two input tags, and no mutation changes the active tag before this switch.
                else => unreachable,
            }
        }
        errdefer self.releaseTask(task);
        try self.admit(.{ .intent = task });
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

    fn reconfigure(self: *State, config: instance.PresentationConfig, surface: ?instance.render.terminal.Size) ConfigureError!instance.PresentationGeometry {
        var request: Configuration = .{ .config = config, .surface = surface };
        try self.admit(.{ .configure = &request });
        self.mutex.lockUncancelable(self.io);
        while (!request.complete) self.configured.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
        return request.result.?;
    }

    fn completeConfiguration(self: *State, request: *Configuration, result: ConfigureError!instance.PresentationGeometry) void {
        self.mutex.lockUncancelable(self.io);
        if (result) |geometry| request.result = geometry else |failure| request.failure = failure;
        request.complete = true;
        self.configured.broadcast(self.io);
        // No request access follows unlock: the waiting caller can now retire its stack storage.
        self.mutex.unlock(self.io);
    }

    fn applyConfiguration(self: *State, request: *Configuration) void {
        const live = instance.terminal(self.value).semanticView(0);
        const result = if (request.surface) |surface|
            instance.reconfigurePresentationSurface(self.value, request.config, surface)
        else keep_grid: {
            const cell = instance.reconfigurePresentation(self.value, request.config) catch |failure| {
                self.completeConfiguration(request, failure);
                return;
            };
            break :keep_grid instance.PresentationGeometry{ .cell_size = cell, .rows = live.rows, .columns = live.cols };
        };
        if (result) |geometry| {
            // The sole producer invalidates only notification authority, never an accepted lease.
            // Reconfiguration completes before the GUI can start its next transfer; only a later
            // publication can make pre-reset unread slots observable again, retiring them first.
            self.new_frame.store(false, .release);
            if (geometry.columns != live.cols) self.history.reset();
            self.blocked_presentation = null;
            self.mutex.lockUncancelable(self.io);
            self.status.presentation_failure = null;
            self.mutex.unlock(self.io);
            self.gate.pending = true;
            self.credit.store(true, .release);
            self.completeConfiguration(request, geometry);
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
        while (!request.complete) self.configured.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
        return request.result.?;
    }
    fn completeCopy(self: *State, request: *Copy, result: CopyError![]const u8) void {
        self.mutex.lockUncancelable(self.io);
        if (result) |bytes| request.result = bytes else |failure| request.failure = failure;
        request.complete = true;
        self.configured.broadcast(self.io);
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
        self.completeCopy(request, range.copy(instance.terminal(self.value), request.allocator, request.max_bytes));
    }
    fn resolve(self: *State, context: selection.Context, point: instance.Terminal.TextPoint) SelectionError!struct { view: instance.Terminal.SemanticView, row: u16 } {
        const observation = instance.terminal(self.value);
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
        const uri = instance.terminal(self.value).hyperlinkUri(cell.attrs.link_id) orelse return error.NoHyperlink;
        if (uri.len > max_bytes) return error.HyperlinkLimit;
        return allocator.dupe(u8, uri);
    }
    fn applySelection(self: *State, intent: Select) SelectionError!void {
        self.selection_serial = intent.serial;
        self.selection_failure = null;
        self.gate.pending = true;
        if (intent.kind == .clear) {
            self.selected = null;
            return;
        }
        const resolved = try self.resolve(intent.context, intent.point);
        const view = resolved.view;
        const row_index = resolved.row;
        const current = selection.Context.fromView(view);
        const point = try selection.point(view, row_index, intent.point.col);
        switch (intent.kind) {
            .start => self.selected = try selection.start(view, @intCast(row_index), intent.point.col),
            .extend => {
                const range = self.selected orelse return error.InvalidSelection;
                switch (range.validity(current)) {
                    .valid => {},
                    .context_changed => return error.SelectionContextChanged,
                    .evicted => return error.SelectionEvicted,
                }
                self.selected.?.focus = point;
            },
            .word => self.selected = try selection.word(view, @intCast(row_index), intent.point.col),
            .row => self.selected = try selection.visualRow(view, @intCast(row_index)),
            .clear => {},
        }
    }
    fn selectMatch(self: *State, range: selection.Range) void {
        self.selected = range;
        self.selection_failure = null;
        const live = instance.terminal(self.value).semanticView(0);
        const top: i64 = if (live.is_alternate_screen) 0 else @as(i64, live.history_row_base) + live.history_count;
        self.history.seek(@intCast(@min(@as(i64, live.history_count), @max(0, top - range.anchor.row))), live.history_count, live.history_row_base, live.is_alternate_screen);
        self.gate.pending = true;
    }
    fn applyFind(self: *State, request: find.Request) void {
        self.selection_serial = request.serial;
        self.selection_failure = null;
        const observation = instance.terminal(self.value);
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
        self.gate.pending = true;
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
        const live = instance.terminal(self.value).semanticView(0);
        switch (task) {
            .find => |request| self.applyFind(request),
            .select => |intent| self.applySelection(intent) catch |failure| {
                self.selected = null;
                self.selection_failure = failure;
            },
            .input => |input| {
                // Committed input returns this pane to live; focus/mouse do not.
                if (input == .bytes or input == .paste or input == .key) {
                    if (self.history.offset != 0) self.gate.pending = true;
                    self.history.reset();
                    if (self.selected != null) {
                        self.selected = null;
                        self.gate.pending = true;
                    }
                }
                try instance.input(self.value, input);
            },
            .resize => |size| {
                if (size.rows != live.rows or size.columns != live.cols) {
                    if (size.columns != live.cols) self.history.reset();
                    try instance.resize(self.value, size.rows, size.columns);
                    self.gate.pending = true;
                }
            },
            .scroll => |delta| {
                self.history.scroll(delta, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.gate.pending = true;
            },
            .seek => |offset| {
                self.history.seek(offset, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.gate.pending = true;
            },
            .retry_render => {
                self.blocked_presentation = null;
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = null;
                self.mutex.unlock(self.io);
                self.gate.pending = true;
                self.credit.store(true, .release);
            },
        }
    }

    fn service(self: *State, readable: bool, writable: bool, now: u64) !instance.Service {
        const result = try instance.serviceWithConsequencePolicy(self.value, readable, writable, now, .retain);
        const host = try desktop.drain(self.value);
        self.consequence_worked = host.worked;
        if (host.attention and !self.attention.swap(true, .acq_rel)) self.notify();
        const observation = instance.terminal(self.value);
        const live = observation.semanticView(0);
        self.history.follow(live.history_count, live.history_row_base, live.is_alternate_screen);
        self.gate.note(observation.semanticSequence(), observation.synchronizedOutput(), result.synchronized_output.ended, now);
        if (self.selected) |range| switch (range.validity(selection.Context.fromView(live))) {
            .valid => {},
            .context_changed => {
                self.selected = null;
                self.selection_failure = error.SelectionContextChanged;
            },
            .evicted => {
                self.selected = null;
                self.selection_failure = error.SelectionEvicted;
            },
        };
        const search_changed = self.search.step(observation) catch |failure| failed: {
            self.search.fail(failure);
            break :failed true;
        };
        if (self.selection_serial == self.search.status.serial) {
            if (self.search.status.phase == .stale and self.selected != null) {
                self.selected = null;
                self.gate.pending = true;
            } else if (self.search.status.current == null and self.search.status.count != 0) {
                if (self.search.navigate(self.selection_serial, false)) |range| self.selectMatch(range);
            }
        }
        self.mutex.lockUncancelable(self.io);
        self.status.search = self.search.status;
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
        if (lifecycle_changed or title_changed or search_changed) self.notify();
        // Only this turn's failed text claim earns a retry deadline.
        self.store_busy = false;
        var published = false;
        const blocked = if (self.blocked_presentation) |failed|
            failed.content_sequence == observation.contentSequence() and failed.history_offset == self.history.offset
        else
            false;
        if (!blocked and self.gate.pending and self.visible.load(.acquire) and
            self.gate.released(observation.synchronizedOutput()) and self.credit.load(.acquire))
        {
            // Projection may skip a stalled GUI transfer; canonical service never waits for it.
            if (!self.frame_mutex.tryLock()) return result;
            defer self.frame_mutex.unlock(self.io);
            std.debug.assert(self.credit.swap(false, .acq_rel));
            instance.publishRenderAt(self.value, self.history.offset) catch |failure| {
                if (failure == error.PublicationBusy or failure == error.PresentationBusy) {
                    self.store_busy = failure == error.PresentationBusy;
                    self.credit.store(true, .release);
                    return result;
                }
                self.blocked_presentation = .{
                    .content_sequence = observation.contentSequence(),
                    .history_offset = self.history.offset,
                };
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
            const view = observation.semanticView(self.history.offset);
            self.paint = if (self.selected) |range| range.paint(view, self.selection_serial) catch .{ .serial = self.selection_serial } else .{ .serial = self.selection_serial };
            self.gate.pending = false;
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

    fn loop(self: *State) !void {
        var readable = true;
        var writable = true;
        while (!self.stopRequested()) {
            while (self.pop()) |work| switch (work) {
                .intent => |task| {
                    defer self.releaseTask(task);
                    try self.apply(task);
                },
                .configure => |request| self.applyConfiguration(request),
                .copy => |request| self.applyCopy(request),
            };
            const now: u64 = @intCast(std.Io.Clock.awake.now(self.io).toNanoseconds());
            const result = try self.service(readable, writable, now);
            var timeout: i32 = if (result.stream_closed and result.child_exit == null) 50 else -1;
            for ([_]?i32{
                self.gate.waitMs(now),
                if (self.store_busy and self.visible.load(.acquire) and self.credit.load(.acquire)) @as(i32, 1) else null,
                if (result.animation_wait_ms) |ms| @intCast(@min(ms, std.math.maxInt(i32))) else null,
            }) |deadline| {
                if (deadline) |ms| timeout = if (timeout < 0) ms else @min(timeout, ms);
            }
            if (instance.bufferedOutputPending(self.value) or self.search.status.phase == .scanning or self.consequence_worked) timeout = 0;
            var fds = [_]posix.pollfd{
                .{
                    .fd = if (result.stream_closed and !result.write_pending) -1 else try instance.descriptor(self.value),
                    .events = posix.POLL.IN | posix.POLL.HUP | if (result.write_pending or instance.writePending(self.value)) @as(i16, posix.POLL.OUT) else 0,
                    .revents = 0,
                },
                .{ .fd = self.wake_fd, .events = posix.POLL.IN, .revents = 0 },
            };
            // zig-audit: acknowledge discard
            // reason: Readiness is consumed from each exact revents mask below; the aggregate ready count adds no authority.
            _ = try posix.poll(&fds, timeout);
            if (fds[1].revents & posix.POLL.IN != 0) self.drainWake();
            readable = fds[0].revents & (posix.POLL.IN | posix.POLL.HUP) != 0 or instance.bufferedOutputPending(self.value);
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
        else => "",
    };
}

fn testPresentation() instance.PresentationConfig {
    return .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
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
    try std.testing.expect(!owner.state().takeFrame());
    try std.testing.expect(instance.acquirePublishedFrame(owner.state().exchange) == null);
    // Oversized input and borrowed key text are rejected without mutation.
    const oversized = try std.testing.allocator.alloc(u8, input_byte_limit + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.InputLimit, owner.submit(.{ .input = .{ .paste = oversized } }));
    try std.testing.expectError(error.BorrowedKeyText, owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter }, .text = "borrowed" } } }));
}

test "a held immutable publication cannot pace canonical progress or prevent cleanup" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var lease = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer lease.abandon();
    const before = lease.value.terminal_revision;
    const first = lease.value.commands[0];
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(before, lease.value.terminal_revision);
    try std.testing.expectEqualDeep(first, lease.value.commands[0]);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

fn waitFrame(owner: *Terminal) !void {
    var attempt: u16 = 0;
    while (attempt < 5000) : (attempt += 1) {
        if (owner.state().takeFrame()) return;
        if (owner.snapshot().failure) |failure| return failure;
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
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    const ready_revision = owner.snapshot().revision;
    if (initial.value.terminal_revision < ready_revision) {
        try initial.release(&.{});
        owner.requestFrame();
        try waitFrame(owner);
        initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    }
    try std.testing.expectEqual(ready_revision, initial.value.terminal_revision);
    const revision = initial.value.terminal_revision;
    try initial.release(&.{});
    const start = std.Io.Clock.awake.now(owner.state().io);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    owner.requestFrame();
    try waitFrame(owner);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(owner.state().io)).toMilliseconds();
    if (elapsed < 800) {
        std.debug.print("hold published too early: {d}ms after input, initial revision {d}, canonical revision {d}\n", .{ elapsed, revision, owner.snapshot().revision });
        return error.EarlyPublication;
    }
    var released = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer released.abandon();
    try std.testing.expect(released.value.terminal_revision > revision);
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

test "projection failure blocks only the failed content while canonical service stays alive" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var presentation = testPresentation();
    presentation.command_capacity = 16;
    presentation.command_limit = 16;
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; i=0; while [ $i -lt 32 ]; do printf '\\033[41mX\\033[42mY'; i=$((i + 1)); done; printf '\\033[0m'; printf '\\033]0;FIRST\\007'; read line; printf '\\033[1;2H'; read line; printf '\\033[0m\\033[2J\\033[Hok\\033]0;RECOVERED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, presentation, c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var stage: []const u8 = "initial";
    errdefer {
        const status = owner.snapshot();
        std.debug.print("recovery proof {s}: title={s}, cursor={d}, failure={any}, credit={any}, ready={any}\n", .{
            stage,                               status.title[0..status.title_len],      status.cursor_col, status.presentation_failure,
            owner.state().credit.load(.acquire), owner.state().new_frame.load(.acquire),
        });
    }
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    const initial_revision = initial.value.terminal_revision;
    try initial.release(&.{});
    stage = "exhaustion";
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "FIRST");
    owner.requestFrame();
    var attempts: u16 = 0;
    while (owner.snapshot().presentation_failure == null and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    try std.testing.expect(owner.snapshot().presentation_failure != null);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
    stage = "cursor";
    try owner.submit(.{ .input = .{ .bytes = "CONTINUE\n" } });
    attempts = 0;
    while (owner.snapshot().cursor_col != 1 and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    try std.testing.expectEqual(@as(u16, 1), owner.snapshot().cursor_col);
    const failure = owner.snapshot().presentation_failure;
    try std.testing.expect(failure != null);
    owner.requestFrame();
    try std.Io.sleep(owner.state().io, .fromMilliseconds(20), .awake);
    try std.testing.expectEqual(failure, owner.snapshot().presentation_failure);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
    try std.testing.expect(!owner.state().new_frame.load(.acquire));
    // A consumed credit would prove another failed projection, even with no new frame.
    try std.testing.expect(owner.state().credit.load(.acquire));
    stage = "recovery";
    try owner.submit(.{ .input = .{ .bytes = "RECOVER\n" } });
    try waitTitle(owner, "RECOVERED");
    try waitFrame(owner);
    try std.testing.expectEqual(@as(?PresentationFailure, null), owner.snapshot().presentation_failure);
    var recovered = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer recovered.abandon();
    try std.testing.expect(recovered.value.terminal_revision > initial_revision);
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
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    try initial.release(&.{});
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "FIRST");
    for (0..16) |_| owner.setVisible(true);
    try owner.submit(.{ .input = .{ .bytes = "END\n" } });
    try waitTitle(owner, "SECOND");
    try std.testing.expect(!owner.state().takeFrame());
    try std.testing.expect(instance.acquirePublishedFrame(owner.state().exchange) == null);
    owner.setVisible(false);
    owner.setVisible(true);
    try waitFrame(owner);
    var revealed = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer revealed.abandon();
    try std.testing.expectEqual(owner.snapshot().revision, revealed.value.terminal_revision);
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
    try waitFrame(owner);
    var held = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    const old_generation = held.value.presentation_generation;
    const old_size = held.value.cell_size;
    var invalid = testPresentation();
    invalid.text.private.regular = .{ .path = .{ .primary = "/missing-howl-live-font.ttf", .size = .{ .pixels = 18 } } };
    try std.testing.expectError(error.FontOpen, owner.reconfigure(invalid, null));
    try std.testing.expectEqual(old_generation, held.value.presentation_generation);
    try std.testing.expectEqualDeep(old_size, held.value.cell_size);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CONTINUED");
    var larger = testPresentation();
    larger.text.private.regular.path.size = .{ .pixels = 18 };
    const surface: instance.render.terminal.Size = .{ .width = 200, .height = 150 };
    const geometry = try owner.reconfigure(larger, surface);
    try std.testing.expectEqual(surface.width / geometry.cell_size.width, geometry.columns);
    try std.testing.expectEqual(surface.height / geometry.cell_size.height, geometry.rows);
    try std.testing.expectEqual(old_generation, held.value.presentation_generation);
    try std.testing.expectEqualDeep(old_size, held.value.cell_size);
    try held.release(&.{});
    try waitFrame(owner);
    var changed = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer changed.abandon();
    try std.testing.expect(changed.value.presentation_generation > old_generation);
    try std.testing.expectEqualDeep(geometry.cell_size, changed.value.cell_size);
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
    var initial: ?instance.RenderLease = null;
    var attempts: u16 = 0;
    while (initial == null and attempts < 5000) : (attempts += 1) {
        initial = try owner.replaceFrame(null, &.{}, null);
        if (initial == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var held = initial orelse return error.MissingFrame;
    defer held.abandon();
    try std.testing.expect(try owner.replaceFrame(&held, &.{}, null) == null);
    try std.testing.expect(!held.released);
    const sequence = held.value.sequence;
    owner.state().frame_mutex.lockUncancelable(owner.state().io);
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(owner.state().io);
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(sequence, held.value.sequence);
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
    var other_frame: ?instance.RenderLease = null;
    attempts = 0;
    while (other_frame == null and attempts < 5000) : (attempts += 1) {
        other_frame = try other.replaceFrame(null, &.{}, null);
        if (other_frame == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var foreign = other_frame orelse return error.MissingFrame;
    defer foreign.abandon();
    attempts = 0;
    while (!owner.state().new_frame.load(.acquire) and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    if (attempts == 5000) return error.Timeout;
    try std.testing.expectError(error.WrongExchange, owner.replaceFrame(&foreign, &.{}, null));
    try std.testing.expect(!foreign.released and !held.released);
    var replacement: ?instance.RenderLease = null;
    attempts = 0;
    while (replacement == null and attempts < 5000) : (attempts += 1) {
        replacement = try owner.replaceFrame(&held, &.{}, null);
        if (replacement == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var changed = replacement orelse return error.MissingFrame;
    defer changed.abandon();
    try std.testing.expect(held.released);
    try std.testing.expect(changed.value.sequence > sequence);
    try std.testing.expect(try owner.replaceFrame(&changed, &.{}, null) == null);
    try std.testing.expect(!changed.released);
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
    try std.testing.expectEqual(instance.Terminal.MouseTrackingMode.button_event, before.interaction.?.mouse_tracking);
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 1 } } });
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 0 } } });
    try waitTitle(owner, "1b5b3c303b343b334d1b5b3c303b343b336d");
    const after = owner.snapshot();
    try std.testing.expectEqual(@as(u16, 1), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), after.cursor_col);
    try std.testing.expect(!owner.state().takeFrame());
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
    var hidden = try owner.replaceFrame(null, &.{}, null);
    defer if (hidden) |*lease| lease.abandon();
    if (hidden) |lease| std.debug.print("pre-reset unread generation entered the backend: {d}\n", .{lease.value.presentation_generation});
    try std.testing.expect(hidden == null);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CONTINUED");
    owner.setVisible(true);
    var fresh: ?instance.RenderLease = null;
    defer if (fresh) |*lease| lease.abandon();
    attempts = 0;
    while (fresh == null and attempts < 5000) : (attempts += 1) {
        fresh = try owner.replaceFrame(null, &.{}, null);
        if (fresh == null) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    const accepted = fresh orelse return error.Timeout;
    try std.testing.expect(accepted.value.presentation_generation > 1);
}

fn waitCopy(owner: *Terminal, request: *Copy) void {
    const state = owner.state();
    state.mutex.lockUncancelable(state.io);
    while (!request.complete) state.configured.waitUncancelable(state.io, &state.mutex);
    state.mutex.unlock(state.io);
}
fn waitPaint(owner: *Terminal, previous: ?*instance.RenderLease, paint: *selection.Paint) !instance.RenderLease {
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        if (try owner.replaceFrame(previous, &.{}, paint)) |lease| return lease;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
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
    var held = try waitPaint(owner, null, &paint);
    defer held.abandon();
    try std.testing.expectEqual(@as(u64, 11), paint.serial);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 9 }), paint.spans[0]);
    const sequence = held.value.sequence;
    owner.state().frame_mutex.lockUncancelable(threaded.io());
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(threaded.io());
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(sequence, held.value.sequence);
    try std.testing.expect(try owner.replaceFrame(&held, &.{}, &paint) == null);
    try std.testing.expect(!held.released);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 9 }), paint.spans[0]);
    try std.testing.expectError(error.NoSelection, owner.copySelection(std.testing.allocator, 128));
    owner.state().frame_mutex.unlock(threaded.io());
    locked = false;
    owner.requestFrame();
    owner.state().wake();
    var cleared = try waitPaint(owner, &held, &paint);
    defer cleared.abandon();
    try std.testing.expect(held.released);
    try std.testing.expect(cleared.value.sequence > sequence);
    try std.testing.expectEqual(@as(u64, 11), paint.serial);
    for (paint.spans) |span| try std.testing.expect(span == null);
    const fresh_context = try selection.Context.fromFrame(cleared.value);
    try owner.submit(.{ .select = .{ .serial = 12, .kind = .word, .context = fresh_context, .point = .{ .row = try fresh_context.row(0), .col = 7 } } });
    const next = try owner.copySelection(std.testing.allocator, 128);
    defer std.testing.allocator.free(next);
    try std.testing.expectEqualStrings("psi", next);
    owner.requestFrame();
    var selected = try waitPaint(owner, &cleared, &paint);
    defer selected.abandon();
    try std.testing.expectEqual(@as(u64, 12), paint.serial);
    try std.testing.expectEqual(@as(?selection.Span, .{ .first = 6, .last = 8 }), paint.spans[0]);
    try std.testing.expect(try owner.replaceFrame(&selected, &.{}, &paint) == null);
    try std.testing.expect(!selected.released);
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
    const shared = try instance.initPresentationStore(a, threaded.io(), config.text.private, .{
        .shape_cache = config.shape_cache,
        .shaped_capacity = config.shaped_capacity,
        .raster_bytes = config.raster_bytes,
    });
    var caller_live = true;
    defer if (caller_live) instance.releasePresentationStore(shared);
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
    try waitFrame(owners[0]);
    var held = instance.acquirePublishedFrame(owners[0].state().exchange) orelse return error.MissingFrame;
    defer held.abandon();
    const before = held.value.terminal_revision;
    const command = held.value.commands[0];
    instance.releasePresentationStore(shared);
    caller_live = false;
    for (owners) |owner| try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    var attempts: u16 = 0;
    var accepted_revision: ?u64 = null;
    while (attempts < 5000) : (attempts += 1) {
        const live = owners[1];
        if (instance.acquirePublishedFrame(live.state().exchange)) |ready| {
            var lease = ready;
            accepted_revision = lease.value.terminal_revision;
            try lease.release(&.{});
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
    try std.testing.expectEqual(before, held.value.terminal_revision);
    try std.testing.expectEqualDeep(command, held.value.commands[0]);
}
