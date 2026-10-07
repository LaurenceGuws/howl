//! C-shaped seam from the Odin desktop shell to canonical Howl owners.
//!
//! Transported Direct/Server routes retain `howl-client` as decoder/action owner.
//! Local instead claims one in-process Instance on one terminal thread and publishes
//! immutable Render frames. Odin gets bounded presentation facts and semantic
//! operations without importing Zig backing layouts.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const client = @import("howl_client");
const server_client = @import("server_client");
const protocol = client.protocol;

const terminal_render = @import("howl_client_render");
const render = terminal_render;
const native_instance = terminal_render.instance;

const RuntimeHandle = opaque {};
const query_declined: i32 = 6;
const size_rejected: i32 = 8;
const native_local_limit: usize = 64;

const NativeLocalSlot = struct {
    id: u64,
    value: *native_instance.Instance,
    claimed: bool = false,
};

/// Owns only process-local Instance identity and exclusive terminal-thread claim.
///
/// The mutex protects catalogue pointer handoff. Once claimed, the Instance is
/// mutated only by that terminal owner; no service/client worker shares it.
const NativeLocalState = struct {
    mutex: std.Io.Mutex = .init,
    instances: [native_local_limit]?NativeLocalSlot = @splat(null),
    next_id: u64 = 1,

    fn insert(
        self: *NativeLocalState,
        io: std.Io,
        value: *native_instance.Instance,
    ) error{ LocalInstanceCapacity, LocalIdentityExhausted }!u64 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        var free: ?usize = null;
        for (self.instances, 0..) |slot, index| {
            if (slot == null) {
                free = index;
                break;
            }
        }
        const index = free orelse return error.LocalInstanceCapacity;
        const id = self.next_id;
        if (id == 0) return error.LocalIdentityExhausted;
        self.next_id +%= 1;
        self.instances[index] = .{ .id = id, .value = value };
        return id;
    }

    fn createPresented(
        self: *NativeLocalState,
        io: std.Io,
        environ: std.process.Environ,
        launch: native_instance.Launch,
        presentation: native_instance.PresentationConfig,
    ) (native_instance.PresentedInitError || error{
        LocalInstanceCapacity,
        LocalIdentityExhausted,
    })!u64 {
        const value = try native_instance.initPresented(
            std.heap.c_allocator,
            environ,
            launch,
            presentation,
        );
        errdefer native_instance.deinit(value);
        return self.insert(io, value);
    }

    fn claim(
        self: *NativeLocalState,
        io: std.Io,
        id: u64,
    ) error{ LocalInstanceUnavailable, LocalInstanceClaimed }!*native_instance.Instance {
        if (id == 0) return error.LocalInstanceUnavailable;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        for (&self.instances) |*slot| {
            if (slot.*) |*active| {
                if (active.id != id) continue;
                if (active.claimed) return error.LocalInstanceClaimed;
                active.claimed = true;
                return active.value;
            }
        }
        return error.LocalInstanceUnavailable;
    }

    fn release(
        self: *NativeLocalState,
        io: std.Io,
        id: u64,
        value: *native_instance.Instance,
    ) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        for (&self.instances) |*slot| {
            if (slot.*) |*active| {
                if (active.id != id) continue;
                std.debug.assert(active.value == value);
                std.debug.assert(active.claimed);
                active.claimed = false;
                return;
            }
        }
        std.debug.assert(false);
    }

    fn destroy(self: *NativeLocalState, io: std.Io, id: u64) bool {
        if (id == 0) return false;
        var value: ?*native_instance.Instance = null;
        self.mutex.lockUncancelable(io);
        for (&self.instances) |*slot| {
            if (slot.*) |active| {
                if (active.id != id) continue;
                if (active.claimed) {
                    self.mutex.unlock(io);
                    return false;
                }
                value = active.value;
                slot.* = null;
                break;
            }
        }
        self.mutex.unlock(io);
        if (value) |owned| native_instance.deinit(owned);
        return value != null;
    }

    fn empty(self: *const NativeLocalState) bool {
        for (self.instances) |slot| if (slot != null) return false;
        return true;
    }
};

const native_synchronized_output_timeout_ns: u64 = std.time.ns_per_s;

const NativePublication = struct {
    revision: u64,
    synchronized_started_ns: ?u64 = null,
    synchronized_pending: bool = false,
    synchronized_timed_out: bool = false,

    fn note(
        self: *NativePublication,
        current_revision: u64,
        synchronized: bool,
        release_ended: bool,
        now_ns: u64,
    ) bool {
        if (release_ended) {
            self.synchronized_started_ns = null;
            self.synchronized_timed_out = false;
        }
        if (!synchronized) {
            const release_pending = self.synchronized_pending;
            self.synchronized_started_ns = null;
            self.synchronized_pending = false;
            self.synchronized_timed_out = false;
            if (current_revision == self.revision and !release_pending)
                return false;
            self.revision = current_revision;
            return true;
        }
        if (self.synchronized_timed_out) {
            if (current_revision == self.revision) return false;
            self.revision = current_revision;
            return true;
        }
        if (self.synchronized_started_ns == null)
            self.synchronized_started_ns = now_ns;
        const elapsed_ns = now_ns -| self.synchronized_started_ns.?;
        if (elapsed_ns < native_synchronized_output_timeout_ns) {
            self.synchronized_pending =
                self.synchronized_pending or current_revision != self.revision;
            return false;
        }
        self.synchronized_started_ns = null;
        self.synchronized_timed_out = true;
        const publish =
            self.synchronized_pending or current_revision != self.revision;
        self.synchronized_pending = false;
        if (publish) self.revision = current_revision;
        return publish;
    }
};

const NativeTerminalHandle = opaque {};
const NativeCanvasHandle = opaque {};

/// One claimed local Instance. Exactly one Odin terminal worker owns this value.
const NativeTerminal = struct {
    runtime: *Runtime,
    id: u64,
    value: *native_instance.Instance,
    publication: NativePublication,
    stream_closed: bool = false,
    child_exit: ?native_instance.ChildExit = null,
    history_offset: u32 = 0,
    write_pending: bool = false,
    animation_wait_ms: ?u32 = null,
    wake_read: posix.fd_t = -1,
    wake_write: posix.fd_t = -1,
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *NativeTerminal) void {
        self.last_error_len = 0;
    }

    fn setError(
        self: *NativeTerminal,
        stage: []const u8,
        failure_name: []const u8,
    ) void {
        const rendered = std.fmt.bufPrint(
            &self.last_error,
            "{s}:{s}",
            .{ stage, failure_name },
        ) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = rendered.len;
    }

    fn publishCurrent(self: *NativeTerminal) !void {
        if (!native_instance.presented(self.value)) return;
        const view = native_instance.terminal(self.value).semanticView(
            self.history_offset,
        );
        self.history_offset = view.history_offset;
        try native_instance.publishRenderAt(
            self.value,
            self.history_offset,
        );
    }

    fn service(self: *NativeTerminal, timestamp_ns: u64) !native_instance.Service {
        self.clearError();
        const serviced = native_instance.serviceWithConsequencePolicy(
            self.value,
            true,
            true,
            timestamp_ns,
            .retain,
        ) catch |failure| {
            self.setError("service", @errorName(failure));
            return failure;
        };
        const observation = native_instance.terminal(self.value);
        const revision = observation.semanticSequence();
        const publish = self.publication.note(
            revision,
            observation.synchronizedOutput(),
            serviced.synchronized_output.ended,
            timestamp_ns,
        );
        const lifecycle_changed =
            serviced.stream_closed != self.stream_closed or
            (serviced.child_exit != null and self.child_exit == null);
        self.stream_closed = serviced.stream_closed;
        if (serviced.child_exit) |value| self.child_exit = value;
        self.write_pending = serviced.write_pending;
        self.animation_wait_ms = serviced.animation_wait_ms;
        if (publish or lifecycle_changed)
            self.publishCurrent() catch |failure| {
                self.setError("publish", @errorName(failure));
                return failure;
            };
        return serviced;
    }

    fn wake(self: *NativeTerminal) void {
        if (comptime builtin.os.tag == .windows) return;
        if (self.wake_write < 0) return;
        const byte = [_]u8{1};
        while (true) {
            const result = posix.system.write(
                self.wake_write,
                &byte,
                byte.len,
            );
            switch (posix.errno(result)) {
                .SUCCESS => return,
                .INTR => continue,
                .AGAIN => return,
                else => return,
            }
        }
    }

    fn drainWake(self: *NativeTerminal) void {
        if (comptime builtin.os.tag == .windows) return;
        if (self.wake_read < 0) return;
        var bytes: [64]u8 = undefined;
        while (true) {
            const result = posix.system.read(
                self.wake_read,
                &bytes,
                bytes.len,
            );
            switch (posix.errno(result)) {
                .SUCCESS => {
                    if (result == 0 or result < bytes.len) return;
                },
                .INTR => continue,
                .AGAIN => return,
                else => return,
            }
        }
    }

    fn waitAndService(
        self: *NativeTerminal,
        timeout_ms: i32,
    ) !native_instance.Service {
        if (comptime builtin.os.tag == .windows) {
            if (timeout_ms > 0)
                try std.Io.sleep(
                    self.runtime.threaded.io(),
                    .fromMilliseconds(@intCast(timeout_ms)),
                    .awake,
                );
            return self.service(nativeNowNs(self.runtime.threaded.io()));
        }

        const descriptor = try native_instance.descriptor(self.value);
        const write_pending =
            self.write_pending or native_instance.writePending(self.value);
        const animation_timeout: i32 = if (self.animation_wait_ms) |value|
            @intCast(@min(value, @as(u32, @intCast(std.math.maxInt(i32)))))
        else
            timeout_ms;
        const effective_timeout = if (native_instance.bufferedOutputPending(self.value))
            @as(i32, 0)
        else if (timeout_ms < 0)
            animation_timeout
        else
            @min(timeout_ms, animation_timeout);
        var pty_events: i16 = posix.POLL.IN | posix.POLL.HUP;
        if (write_pending) pty_events |= posix.POLL.OUT;
        var descriptors = [_]posix.pollfd{
            .{
                .fd = descriptor,
                .events = pty_events,
                .revents = 0,
            },
            .{
                .fd = self.wake_read,
                .events = posix.POLL.IN,
                .revents = 0,
            },
        };
        _ = try posix.poll(&descriptors, effective_timeout);
        if (descriptors[1].revents & posix.POLL.IN != 0)
            self.drainWake();
        const readable =
            descriptors[0].revents & (posix.POLL.IN | posix.POLL.HUP) != 0 or
            native_instance.bufferedOutputPending(self.value);
        const writable =
            write_pending and descriptors[0].revents & posix.POLL.OUT != 0;
        const timestamp_ns = nativeNowNs(self.runtime.threaded.io());

        self.clearError();
        const serviced = native_instance.serviceWithConsequencePolicy(
            self.value,
            readable,
            writable,
            timestamp_ns,
            .retain,
        ) catch |failure| {
            self.setError("service", @errorName(failure));
            return failure;
        };
        const observation = native_instance.terminal(self.value);
        const revision = observation.semanticSequence();
        const publish = self.publication.note(
            revision,
            observation.synchronizedOutput(),
            serviced.synchronized_output.ended,
            timestamp_ns,
        );
        const lifecycle_changed =
            serviced.stream_closed != self.stream_closed or
            (serviced.child_exit != null and self.child_exit == null);
        self.stream_closed = serviced.stream_closed;
        if (serviced.child_exit) |value| self.child_exit = value;
        self.write_pending = serviced.write_pending;
        self.animation_wait_ms = serviced.animation_wait_ms;
        if (publish or lifecycle_changed)
            self.publishCurrent() catch |failure| {
                self.setError("publish", @errorName(failure));
                return failure;
            };
        return serviced;
    }
};

fn nativeNowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.awake.now(io).toNanoseconds());
}

fn createNativeWakePair() error{WakeFailed}![2]posix.fd_t {
    if (comptime builtin.os.tag == .windows) return .{ -1, -1 };
    var pair: [2]posix.fd_t = undefined;
    const result = posix.system.socketpair(
        posix.AF.UNIX,
        posix.SOCK.STREAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC,
        0,
        &pair,
    );
    if (posix.errno(result) != .SUCCESS) return error.WakeFailed;
    return pair;
}

fn closeNativeWake(fd: posix.fd_t) void {
    if (comptime builtin.os.tag == .windows) return;
    if (fd < 0) return;
    const result = posix.system.close(fd);
    const status = posix.errno(result);
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

fn nativeTerminalValue(raw: ?*NativeTerminalHandle) ?*NativeTerminal {
    return if (raw) |value| @ptrCast(@alignCast(value)) else null;
}

const NativeCanvasFront = struct {
    presentation_generation: u64 = 0,
    frame_revision: u64 = 0,
    terminal_revision: u64 = 0,
    history_offset: u32 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    alternate_screen: bool = false,
    background_rgba: u32 = 0xff211918,
    // No backend-visible geometry exists until one publication is accepted.
    // Zero keeps UI sizing from manufacturing a fake pre-frame cell lattice.
    surface: terminal_render.Size = .{ .width = 0, .height = 0 },
    cell_size: terminal_render.Size = .{ .width = 0, .height = 0 },
};

/// Backend-thread owner around one immutable Instance Render publication lease.
///
/// It owns no Instance, VT, Text, or Renderer state. Exact Render residency is
/// the only feedback returned to the terminal producer.
const NativeCanvas = struct {
    allocator: std.mem.Allocator,
    exchange: *native_instance.RenderExchange,
    lease: ?native_instance.RenderLease = null,
    accepted: [render_resource_limit]terminal_render.Residency = undefined,
    accepted_count: usize = 0,
    accepted_generation: u64 = 0,
    candidate: [render_resource_limit]terminal_render.Residency = undefined,
    candidate_count: usize = 0,
    front: NativeCanvasFront = .{},
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *NativeCanvas) void {
        self.last_error_len = 0;
    }

    fn setError(
        self: *NativeCanvas,
        stage_name: []const u8,
        failure_name: []const u8,
    ) void {
        const rendered = std.fmt.bufPrint(
            &self.last_error,
            "{s}:{s}",
            .{ stage_name, failure_name },
        ) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = rendered.len;
    }

    fn deinit(self: *NativeCanvas) void {
        if (self.lease) |*lease| lease.abandon();
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
    }

    fn removeCandidate(
        self: *NativeCanvas,
        resource: terminal_render.ResourceRef,
    ) void {
        var index: usize = 0;
        while (index < self.candidate_count) : (index += 1) {
            const current = self.candidate[index];
            if (current.resource.resource != resource.resource or
                current.resource.generation != resource.generation)
                continue;
            const trailing = self.candidate_count - index - 1;
            if (trailing != 0)
                std.mem.copyForwards(
                    terminal_render.Residency,
                    self.candidate[index .. index + trailing],
                    self.candidate[index + 1 .. index + 1 + trailing],
                );
            self.candidate_count -= 1;
            return;
        }
    }

    fn stage(self: *NativeCanvas) !void {
        if (self.lease != null) return error.PendingFrame;
        var lease = native_instance.acquirePublishedFrame(self.exchange) orelse
            return error.NoFrame;
        var owned = true;
        errdefer if (owned) lease.abandon();

        const frame = lease.value;
        if (self.accepted_generation != frame.presentation_generation) {
            self.accepted_generation = frame.presentation_generation;
            self.accepted_count = 0;
        }
        @memcpy(
            self.candidate[0..self.accepted_count],
            self.accepted[0..self.accepted_count],
        );
        self.candidate_count = self.accepted_count;
        for (frame.removals) |resource| self.removeCandidate(resource);
        for (frame.uploads) |upload|
            try upsertResidency(
                &self.candidate,
                &self.candidate_count,
                .{
                    .resource = upload.resource,
                    .format = upload.format,
                    .size = upload.size,
                },
            );
        self.lease = lease;
        owned = false;
    }

    fn accept(self: *NativeCanvas) !void {
        var lease = self.lease orelse return error.NoPendingFrame;
        self.lease = null;
        const frame = lease.value;
        @memcpy(
            self.accepted[0..self.candidate_count],
            self.candidate[0..self.candidate_count],
        );
        self.accepted_count = self.candidate_count;
        self.front = .{
            .presentation_generation = frame.presentation_generation,
            .frame_revision = frame.revision,
            .terminal_revision = frame.terminal_revision,
            .history_offset = frame.history_offset,
            .history_count = frame.history_count,
            .history_row_base = frame.history_row_base,
            .alternate_screen = frame.alternate_screen,
            .background_rgba = publicationBackground(frame),
            .surface = frame.surface,
            .cell_size = frame.cell_size,
        };
        try lease.release(self.accepted[0..self.accepted_count]);
    }

    fn discard(self: *NativeCanvas) !void {
        var lease = self.lease orelse return;
        self.lease = null;
        self.candidate_count = 0;
        try lease.release(self.accepted[0..self.accepted_count]);
    }

    fn pending(self: *NativeCanvas) ?*const native_instance.PublishedFrame {
        if (self.lease) |*lease| return &lease.value;
        return null;
    }
};

fn nativeCanvasValue(raw: ?*NativeCanvasHandle) ?*NativeCanvas {
    return if (raw) |value| @ptrCast(@alignCast(value)) else null;
}

fn publicationBackground(frame: native_instance.PublishedFrame) u32 {
    for (frame.commands) |command| switch (command) {
        .solid => |solid| {
            if (solid.rect.x == 0 and solid.rect.y == 0 and
                solid.rect.width == frame.surface.width and
                solid.rect.height == frame.surface.height)
                return colorBits(solid.color);
        },
        else => {},
    };
    return 0xff211918;
}

// One explicit desktop lifetime, constructed/destroyed by the application.
// Process and route owners borrow its I/O; no per-connection signal handlers.
const Runtime = struct {
    threaded: std.Io.Threaded,
    borrowers: std.atomic.Value(u32) = .init(0),
    native_local: NativeLocalState = .{},
    render_lanes: [render_lane_limit]?*RenderLane = @splat(null),
    render_scratch: ?*RenderScratch = null,
};

fn runtimeValue(raw: ?*RuntimeHandle) ?*Runtime {
    return if (raw) |value| @ptrCast(@alignCast(value)) else null;
}

fn retainRuntime(value: ?*Runtime) void {
    if (value) |runtime| {
        const before = runtime.borrowers.fetchAdd(1, .monotonic);
        std.debug.assert(before < 1024);
    }
}

fn releaseRuntime(value: ?*Runtime) void {
    if (value) |runtime| {
        const before = runtime.borrowers.fetchSub(1, .release);
        std.debug.assert(before > 0);
    }
}

pub export fn howl_odin_bridge_runtime_create() ?*RuntimeHandle {
    const value = std.heap.c_allocator.create(Runtime) catch return null;
    value.* = .{ .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .environ = currentProcessEnviron() }) };
    return @ptrCast(value);
}

pub export fn howl_odin_bridge_runtime_destroy(raw: ?*RuntimeHandle) void {
    const value = runtimeValue(raw) orelse return;
    std.debug.assert(value.borrowers.load(.acquire) == 0);
    std.debug.assert(value.native_local.empty());
    deinitRenderScratch(value);
    deinitRenderLanes(value);
    value.threaded.deinit();
    std.heap.c_allocator.destroy(value);
}

/// Creates one fully presented local Instance with no HWLS or service worker.
pub export fn howl_odin_bridge_native_local_instance_create(
    runtime_raw: ?*RuntimeHandle,
    shell_ptr: [*]const u8,
    shell_len: usize,
    command_ptr: [*]const u8,
    command_len: usize,
    cwd_ptr: [*]const u8,
    cwd_len: usize,
    rows: u16,
    columns: u16,
    history_rows: u16,
    font_ptr: [*]const u8,
    font_len: usize,
    italic_ptr: [*]const u8,
    italic_len: usize,
    bold_ptr: [*]const u8,
    bold_len: usize,
    bold_italic_ptr: [*]const u8,
    bold_italic_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: [*]const u8,
    secondary_fallback_len: usize,
    font_pixels: u16,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) u64 {
    diagnostic_len.* = 0;
    const runtime = runtimeValue(runtime_raw) orelse {
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "runtime_unavailable",
        );
        return 0;
    };
    if (shell_len == 0 or rows == 0 or columns == 0 or history_rows == 0 or
        font_len == 0 or font_pixels == 0)
    {
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "invalid_native_local_launch",
        );
        return 0;
    }
    const launch = native_instance.Launch{
        .shell = shell_ptr[0..shell_len],
        .command = if (command_len == 0) null else command_ptr[0..command_len],
        .cwd = if (cwd_len == 0) null else cwd_ptr[0..cwd_len],
        .rows = rows,
        .columns = columns,
        .history_rows = history_rows,
    };
    var fallback_storage: [2][]const u8 = undefined;
    const config = nativePresentationConfig(
        &fallback_storage,
        font_ptr[0..font_len],
        italic_ptr[0..italic_len],
        bold_ptr[0..bold_len],
        bold_italic_ptr[0..bold_italic_len],
        fallback_ptr[0..fallback_len],
        secondary_fallback_ptr[0..secondary_fallback_len],
        font_pixels,
    );
    return runtime.native_local.createPresented(
        runtime.threaded.io(),
        currentProcessEnviron(),
        launch,
        config,
    ) catch |failure| {
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
        );
        return 0;
    };
}

pub export fn howl_odin_bridge_native_local_instance_destroy(
    runtime_raw: ?*RuntimeHandle,
    id: u64,
) i32 {
    const runtime = runtimeValue(runtime_raw) orelse return 1;
    return if (runtime.native_local.destroy(runtime.threaded.io(), id)) 0 else 2;
}

pub export fn howl_odin_bridge_native_terminal_claim(
    runtime_raw: ?*RuntimeHandle,
    id: u64,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*NativeTerminalHandle {
    diagnostic_len.* = 0;
    const runtime = runtimeValue(runtime_raw) orelse {
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "runtime_unavailable",
        );
        return null;
    };
    const value = runtime.native_local.claim(
        runtime.threaded.io(),
        id,
    ) catch |failure| {
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
        );
        return null;
    };
    const owner = std.heap.c_allocator.create(NativeTerminal) catch {
        runtime.native_local.release(runtime.threaded.io(), id, value);
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "out_of_memory",
        );
        return null;
    };
    const wake = createNativeWakePair() catch {
        runtime.native_local.release(runtime.threaded.io(), id, value);
        std.heap.c_allocator.destroy(owner);
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "wake_failed",
        );
        return null;
    };
    owner.* = .{
        .runtime = runtime,
        .id = id,
        .value = value,
        .publication = .{
            .revision = native_instance.terminal(value).semanticSequence(),
        },
        .wake_read = wake[0],
        .wake_write = wake[1],
    };
    owner.publishCurrent() catch |failure| {
        runtime.native_local.release(runtime.threaded.io(), id, value);
        closeNativeWake(wake[1]);
        closeNativeWake(wake[0]);
        std.heap.c_allocator.destroy(owner);
        writeDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
        );
        return null;
    };
    retainRuntime(runtime);
    return @ptrCast(owner);
}

pub export fn howl_odin_bridge_native_terminal_release(
    raw: ?*NativeTerminalHandle,
) void {
    const owner = nativeTerminalValue(raw) orelse return;
    const runtime = owner.runtime;
    runtime.native_local.release(
        runtime.threaded.io(),
        owner.id,
        owner.value,
    );
    closeNativeWake(owner.wake_write);
    closeNativeWake(owner.wake_read);
    releaseRuntime(runtime);
    std.heap.c_allocator.destroy(owner);
}

/// Services one nonblocking PTY/VT turn and publishes an eligible Render cut.
pub export fn howl_odin_bridge_native_terminal_service(
    raw: ?*NativeTerminalHandle,
    timestamp_ns: u64,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    _ = owner.service(timestamp_ns) catch return 2;
    return 0;
}

/// Blocks until PTY/control/animation work or timeout, then services one turn.
pub export fn howl_odin_bridge_native_terminal_wait(
    raw: ?*NativeTerminalHandle,
    timeout_ms: i32,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    _ = owner.waitAndService(timeout_ms) catch return 2;
    return 0;
}

/// Wakes a terminal worker after another thread enqueues copied control work.
pub export fn howl_odin_bridge_native_terminal_wake(
    raw: ?*NativeTerminalHandle,
) void {
    const owner = nativeTerminalValue(raw) orelse return;
    owner.wake();
}

/// Wakes child-directed writes by admitting one exact byte sequence.
pub export fn howl_odin_bridge_native_terminal_send_text(
    raw: ?*NativeTerminalHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    native_instance.input(
        owner.value,
        .{ .bytes = bytes_ptr[0..bytes_len] },
    ) catch |failure| {
        owner.setError("input", @errorName(failure));
        return 2;
    };
    return 0;
}

fn nativeModifiers(value: u8) native_instance.InputModifier {
    return @bitCast(value);
}

fn nativeNamedKey(value: u8) ?native_instance.KeyName {
    const wire = std.enums.fromInt(protocol.InputKeyName, value) orelse
        return null;
    return std.meta.stringToEnum(native_instance.KeyName, @tagName(wire));
}

fn nativeKeyAction(value: u8) ?native_instance.KeyAction {
    return std.enums.fromInt(native_instance.KeyAction, value);
}

fn nativeMouseKind(value: u8) ?native_instance.MouseEventKind {
    const wire = std.enums.fromInt(protocol.InputMouseKind, value) orelse
        return null;
    return std.meta.stringToEnum(native_instance.MouseEventKind, @tagName(wire));
}

fn nativeMouseButton(value: u8) ?native_instance.MouseButton {
    return std.enums.fromInt(native_instance.MouseButton, value);
}

const NativeViewportPosition = struct {
    row: u16,
    column: u16,
};

fn nativeStableRow(
    view: *const native_instance.Terminal.SemanticView,
    viewport_row: u16,
) ?i32 {
    if (viewport_row >= view.rows) return null;
    if (view.is_alternate_screen) return @intCast(viewport_row);
    if (view.history_offset > view.history_count) return null;
    const row = @as(u64, view.history_row_base) +
        view.history_count - view.history_offset + viewport_row;
    if (row > std.math.maxInt(i32)) return null;
    return @intCast(row);
}

fn nativeViewportRow(
    view: *const native_instance.Terminal.SemanticView,
    stable_row: i32,
) ?u16 {
    if (view.rows == 0) return null;
    if (view.is_alternate_screen) {
        if (stable_row < 0 or stable_row >= view.rows) return null;
        return @intCast(stable_row);
    }
    const top = @as(i64, view.history_row_base) +
        view.history_count - view.history_offset;
    const relative = @as(i64, stable_row) - top;
    if (relative < 0 or relative >= view.rows) return null;
    return @intCast(relative);
}

fn nativeLeadPosition(
    view: *const native_instance.Terminal.SemanticView,
    row: u16,
    column: u16,
) ?NativeViewportPosition {
    if (row >= view.rows or column >= view.cols) return null;
    const cell = view.cellInfoAt(row, column);
    if (cell.x > column or cell.y > row) return null;
    return .{
        .row = row - cell.y,
        .column = column - cell.x,
    };
}

fn nativeSelectableLead(
    view: *const native_instance.Terminal.SemanticView,
    position: NativeViewportPosition,
) bool {
    const cell = view.cellInfoAt(position.row, position.column);
    if (cell.x != 0 or cell.y != 0 or cell.attrs.invisible) return false;
    var scalars: [native_instance.maximum_cell_scalars]u21 = undefined;
    const values = view.cellScalarsAt(
        position.row,
        position.column,
        &scalars,
    );
    return values.len != 0 and values[0] != ' ';
}

fn nativePreviousLead(
    view: *const native_instance.Terminal.SemanticView,
    position: NativeViewportPosition,
) ?NativeViewportPosition {
    if (position.column > 0)
        return nativeLeadPosition(view, position.row, position.column - 1);
    if (position.row == 0 or !view.rowWrapped(position.row - 1)) return null;
    return nativeLeadPosition(view, position.row - 1, view.cols - 1);
}

fn nativeNextLead(
    view: *const native_instance.Terminal.SemanticView,
    position: NativeViewportPosition,
) ?NativeViewportPosition {
    const cell = view.cellInfoAt(position.row, position.column);
    const next_column = @as(u32, position.column) + @max(@as(u32, cell.width), 1);
    if (next_column < view.cols)
        return nativeLeadPosition(view, position.row, @intCast(next_column));
    if (!view.rowWrapped(position.row) or position.row + 1 >= view.rows)
        return null;
    return nativeLeadPosition(view, position.row + 1, 0);
}

fn nativeLastContentColumn(
    view: *const native_instance.Terminal.SemanticView,
    row: u16,
) ?u16 {
    if (row >= view.rows) return null;
    var column: usize = view.cols;
    while (column != 0) {
        column -= 1;
        const cell = view.cellInfoAt(row, @intCast(column));
        if (cell.x != 0 or cell.y != 0) continue;
        var scalars: [native_instance.maximum_cell_scalars]u21 = undefined;
        const values = view.cellScalarsAt(row, @intCast(column), &scalars);
        if (values.len == 0 or values[0] == ' ') continue;
        const end = @min(
            @as(u32, view.cols - 1),
            @as(u32, @intCast(column)) + @max(@as(u32, cell.width), 1) - 1,
        );
        return @intCast(end);
    }
    return null;
}

fn nativeLastSearchColumn(
    view: *const native_instance.Terminal.SemanticView,
    row: u16,
) ?u16 {
    if (row >= view.rows) return null;
    var column: usize = view.cols;
    while (column != 0) {
        column -= 1;
        const cell = view.cellInfoAt(row, @intCast(column));
        if (cell.x != 0 or cell.y != 0 or cell.attrs.invisible) continue;
        var scalars: [native_instance.maximum_cell_scalars]u21 = undefined;
        if (view.cellScalarsAt(row, @intCast(column), &scalars).len != 0)
            return @intCast(column);
    }
    return null;
}

fn nativeExpandSelection(
    owner: *NativeTerminal,
    kind: u8,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate: bool,
    output: *SelectionRangeInfo,
) i32 {
    output.* = .{};
    const observation = native_instance.terminal(owner.value);
    const view = observation.semanticView(history_offset);
    if (view.cols != expected_columns or
        view.is_alternate_screen != expected_alternate)
    {
        owner.setError("selection_expand", "context_changed");
        return query_declined;
    }
    const viewport_row = nativeViewportRow(&view, target_row) orelse {
        owner.setError("selection_expand", "target_moved");
        return query_declined;
    };
    if (target_column >= view.cols) {
        owner.setError("selection_expand", "target_column");
        return query_declined;
    }

    if (kind == 2) {
        const last = nativeLastContentColumn(&view, viewport_row) orelse return 0;
        var first: ?u16 = null;
        var column: u16 = 0;
        while (column < view.cols) : (column += 1) {
            const cell = view.cellInfoAt(viewport_row, column);
            if (cell.x == 0 and cell.y == 0) {
                first = column;
                break;
            }
        }
        const start_column = first orelse return 0;
        const stable = nativeStableRow(&view, viewport_row) orelse
            return query_declined;
        output.* = .{
            .start_row = stable,
            .end_row = stable,
            .start_column = start_column,
            .end_column = last,
            .columns = view.cols,
            .found = 1,
            .alternate_screen = @intFromBool(view.is_alternate_screen),
        };
        return 0;
    }
    if (kind != 1) return 2;

    const start = nativeLeadPosition(
        &view,
        viewport_row,
        target_column,
    ) orelse return query_declined;
    if (!nativeSelectableLead(&view, start)) return 0;

    var first = start;
    while (nativePreviousLead(&view, first)) |candidate| {
        if (!nativeSelectableLead(&view, candidate)) break;
        first = candidate;
    }
    var last = start;
    while (nativeNextLead(&view, last)) |candidate| {
        if (!nativeSelectableLead(&view, candidate)) break;
        last = candidate;
    }
    const first_row = nativeStableRow(&view, first.row) orelse
        return query_declined;
    const last_row = nativeStableRow(&view, last.row) orelse
        return query_declined;
    const last_cell = view.cellInfoAt(last.row, last.column);
    const end_column = @min(
        @as(u32, view.cols - 1),
        @as(u32, last.column) + @max(@as(u32, last_cell.width), 1) - 1,
    );
    output.* = .{
        .start_row = first_row,
        .end_row = last_row,
        .start_column = first.column,
        .end_column = @intCast(end_column),
        .columns = view.cols,
        .found = 1,
        .alternate_screen = @intFromBool(view.is_alternate_screen),
    };
    return 0;
}

fn nativeViewForStableRow(
    observation: *const native_instance.Terminal.Observation,
    stable_row: i32,
) ?struct {
    view: native_instance.Terminal.SemanticView,
    viewport_row: u16,
} {
    const live = observation.semanticView(0);
    if (live.is_alternate_screen) {
        if (stable_row < 0 or stable_row >= live.rows) return null;
        return .{ .view = live, .viewport_row = @intCast(stable_row) };
    }
    const live_top = @as(i64, live.history_row_base) + live.history_count;
    const last = live_top + live.rows - 1;
    if (stable_row < live.history_row_base or stable_row > last) return null;
    if (stable_row >= live_top)
        return .{
            .view = live,
            .viewport_row = @intCast(@as(i64, stable_row) - live_top),
        };
    const offset: u32 = @intCast(live_top - stable_row);
    return .{
        .view = observation.semanticView(offset),
        .viewport_row = 0,
    };
}

fn nativeSearchRow(
    owner: *NativeTerminal,
    query: []const u8,
    stable_row: i32,
    column_bound: u16,
    reverse: bool,
) !?struct { start: u16, end: u16 } {
    const observation = native_instance.terminal(owner.value);
    const located = nativeViewForStableRow(observation, stable_row) orelse
        return null;
    const view = located.view;
    const row = located.viewport_row;
    const last = nativeLastSearchColumn(&view, row) orelse return null;
    const maximum_bytes = try std.math.mul(
        usize,
        @as(usize, last) + 1,
        native_instance.maximum_cell_scalars * 4,
    );
    const text = try std.heap.c_allocator.alloc(u8, maximum_bytes);
    defer std.heap.c_allocator.free(text);
    const columns = try std.heap.c_allocator.alloc(u16, maximum_bytes);
    defer std.heap.c_allocator.free(columns);

    var used: usize = 0;
    var column: u16 = 0;
    while (column <= last) : (column += 1) {
        const cell = view.cellInfoAt(row, column);
        if (cell.x != 0 or cell.y != 0) continue;
        var scalars: [native_instance.maximum_cell_scalars]u21 = undefined;
        const values = view.cellScalarsAt(row, column, &scalars);
        if (cell.attrs.invisible or values.len == 0) {
            text[used] = ' ';
            columns[used] = column;
            used += 1;
            continue;
        }
        for (values) |scalar| {
            var encoded: [4]u8 = undefined;
            const count = try std.unicode.utf8Encode(scalar, &encoded);
            @memcpy(text[used .. used + count], encoded[0..count]);
            @memset(columns[used .. used + count], column);
            used += count;
        }
    }
    if (query.len > used) return null;
    const haystack = text[0..used];
    if (reverse) {
        var end_at = haystack.len;
        while (end_at >= query.len) {
            const found = std.mem.lastIndexOf(
                u8,
                haystack[0..end_at],
                query,
            ) orelse return null;
            const start_column = columns[found];
            const end_lead = columns[found + query.len - 1];
            if (end_lead <= column_bound) {
                const cell = view.cellInfoAt(row, end_lead);
                const end_column = @min(
                    @as(u32, view.cols - 1),
                    @as(u32, end_lead) + @max(@as(u32, cell.width), 1) - 1,
                );
                return .{
                    .start = start_column,
                    .end = @intCast(end_column),
                };
            }
            if (found == 0) return null;
            end_at = found;
        }
        return null;
    }

    var start_at: usize = 0;
    while (start_at + query.len <= haystack.len) {
        const relative = std.mem.indexOf(
            u8,
            haystack[start_at..],
            query,
        ) orelse return null;
        const found = start_at + relative;
        const start_column = columns[found];
        if (start_column >= column_bound) {
            const end_lead = columns[found + query.len - 1];
            const cell = view.cellInfoAt(row, end_lead);
            const end_column = @min(
                @as(u32, view.cols - 1),
                @as(u32, end_lead) + @max(@as(u32, cell.width), 1) - 1,
            );
            return .{
                .start = start_column,
                .end = @intCast(end_column),
            };
        }
        start_at = found + 1;
    }
    return null;
}

fn nativeSearch(
    owner: *NativeTerminal,
    query: []const u8,
    reverse: bool,
    origin_present: bool,
    origin_row: i32,
    origin_column: u16,
    output: *SearchMatchInfo,
) i32 {
    output.* = .{};
    if (query.len == 0 or query.len > maximum_search_query_bytes or
        !std.unicode.utf8ValidateSlice(query))
        return 2;

    const observation = native_instance.terminal(owner.value);
    const live = observation.semanticView(0);
    output.cut_revision = observation.semanticSequence();
    output.columns = live.cols;
    output.alternate_screen = @intFromBool(live.is_alternate_screen);
    output.complete = 1;
    if (live.rows == 0 or live.cols == 0) return 0;
    if (origin_present and origin_column >= live.cols) return 4;

    const first: i64 = if (live.is_alternate_screen)
        0
    else
        live.history_row_base;
    const last: i64 = if (live.is_alternate_screen)
        live.rows - 1
    else
        @as(i64, live.history_row_base) + live.history_count + live.rows - 1;

    var row: i64 = if (origin_present)
        origin_row
    else if (reverse)
        last
    else
        first;
    var column: u16 = if (origin_present)
        origin_column
    else if (reverse)
        live.cols - 1
    else
        0;

    if (origin_present) {
        if (reverse) {
            if (column == 0) {
                row -= 1;
                column = live.cols - 1;
            } else column -= 1;
        } else if (column + 1 >= live.cols) {
            row += 1;
            column = 0;
        } else column += 1;
    }

    while (row >= first and row <= last) {
        output.scanned_snapshots += 1;
        const found = nativeSearchRow(
            owner,
            query,
            @intCast(row),
            column,
            reverse,
        ) catch |failure| {
            owner.setError("search", @errorName(failure));
            return 4;
        };
        if (found) |match| {
            output.found = 1;
            output.row = @intCast(row);
            output.start_column = match.start;
            output.end_column = match.end;
            return 0;
        }
        if (reverse) {
            row -= 1;
            column = live.cols - 1;
        } else {
            row += 1;
            column = 0;
        }
    }
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_paste(
    raw: ?*NativeTerminalHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    native_instance.input(
        owner.value,
        .{ .paste = bytes_ptr[0..bytes_len] },
    ) catch |failure| {
        owner.setError("paste", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_named_key(
    raw: ?*NativeTerminalHandle,
    key_value: u8,
    action_value: u8,
    modifiers: u8,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    const key = nativeNamedKey(key_value) orelse return 3;
    const action = nativeKeyAction(action_value) orelse return 3;
    native_instance.input(owner.value, .{ .key = .{
        .key = .{ .named = key },
        .mods = nativeModifiers(modifiers),
        .action = action,
    } }) catch |failure| {
        owner.setError("key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_unicode_key(
    raw: ?*NativeTerminalHandle,
    scalar: u32,
    action_value: u8,
    modifiers: u8,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (scalar > std.math.maxInt(u21)) return 3;
    const key = native_instance.Key.initUnicode(@intCast(scalar)) catch
        return 3;
    const action = nativeKeyAction(action_value) orelse return 3;
    native_instance.input(owner.value, .{ .key = .{
        .key = key,
        .mods = nativeModifiers(modifiers),
        .action = action,
    } }) catch |failure| {
        owner.setError("unicode_key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_mouse(
    raw: ?*NativeTerminalHandle,
    kind_value: u8,
    button_value: u8,
    modifiers: u8,
    buttons_down: u8,
    row: i32,
    column: u16,
    pixels_present: u8,
    pixel_x: u32,
    pixel_y: u32,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (pixels_present > 1) return 3;
    const kind = nativeMouseKind(kind_value) orelse return 3;
    const button = nativeMouseButton(button_value) orelse return 3;
    native_instance.input(owner.value, .{ .mouse = .{
        .kind = kind,
        .button = button,
        .row = row,
        .col = column,
        .pixel_x = if (pixels_present != 0) pixel_x else null,
        .pixel_y = if (pixels_present != 0) pixel_y else null,
        .mod = nativeModifiers(modifiers),
        .buttons_down = buttons_down,
    } }) catch |failure| {
        owner.setError("mouse", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_focus(
    raw: ?*NativeTerminalHandle,
    focus_value: u8,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    const wire = std.enums.fromInt(protocol.InputFocus, focus_value) orelse
        return 3;
    const focus: native_instance.Terminal.InputEvent = .{
        .focus = if (wire == .in) .in else .out,
    };
    native_instance.input(owner.value, focus) catch |failure| {
        owner.setError("focus", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_send_resize(
    raw: ?*NativeTerminalHandle,
    rows: u16,
    columns: u16,
    cell_width: u16,
    cell_height: u16,
    claim: u8,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (claim > 1) return 3;
    native_instance.resizeGeometry(
        owner.value,
        rows,
        columns,
        cell_width,
        cell_height,
    ) catch |failure| {
        owner.setError("resize", @errorName(failure));
        return if (failure == error.InvalidDimensions) size_rejected else 2;
    };
    owner.publication.revision =
        native_instance.terminal(owner.value).semanticSequence();
    owner.publishCurrent() catch |failure| {
        owner.setError("publish", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_selection_expand(
    raw: ?*NativeTerminalHandle,
    kind: u8,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output: *SelectionRangeInfo,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (expected_alternate_screen > 1) return 2;
    return nativeExpandSelection(
        owner,
        kind,
        history_offset,
        target_row,
        target_column,
        expected_columns,
        expected_alternate_screen != 0,
        output,
    );
}

pub export fn howl_odin_bridge_native_terminal_selection_extract(
    raw: ?*NativeTerminalHandle,
    start_row: i32,
    start_column: u16,
    end_row: i32,
    end_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (expected_columns == 0 or expected_alternate_screen > 1) return 2;
    const observation = native_instance.terminal(owner.value);
    const current = observation.semanticView(0);
    if (current.cols != expected_columns or
        current.is_alternate_screen != (expected_alternate_screen != 0))
        return query_declined;
    const text = observation.copyText(
        std.heap.c_allocator,
        .{
            .start = .{ .row = start_row, .col = start_column },
            .end = .{ .row = end_row, .col = end_column },
        },
        output_capacity,
    ) catch |failure| {
        owner.setError("selection_extract", @errorName(failure));
        return query_declined;
    };
    defer std.heap.c_allocator.free(text);
    if (text.len > output_capacity) return query_declined;
    @memcpy(output_ptr[0..text.len], text);
    output_len.* = text.len;
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_hyperlink_copy(
    raw: ?*NativeTerminalHandle,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (expected_columns == 0 or expected_alternate_screen > 1) return 2;
    const observation = native_instance.terminal(owner.value);
    const view = observation.semanticView(history_offset);
    if (view.cols != expected_columns or
        view.is_alternate_screen != (expected_alternate_screen != 0))
        return query_declined;
    const viewport_row = nativeViewportRow(&view, target_row) orelse
        return query_declined;
    if (target_column >= view.cols) return query_declined;
    const cell = view.cellInfoAt(viewport_row, target_column);
    if (cell.attrs.link_id == 0) return 0;
    const uri = observation.hyperlinkUri(cell.attrs.link_id) orelse return 0;
    if (uri.len > output_capacity) return query_declined;
    @memcpy(output_ptr[0..uri.len], uri);
    output_len.* = uri.len;
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_search_find(
    raw: ?*NativeTerminalHandle,
    query_ptr: [*]const u8,
    query_len: usize,
    reverse_value: u8,
    origin_present: u8,
    origin_row: i32,
    origin_column: u16,
    output: *SearchMatchInfo,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (reverse_value > 1 or origin_present > 1) return 2;
    return nativeSearch(
        owner,
        query_ptr[0..query_len],
        reverse_value != 0,
        origin_present != 0,
        origin_row,
        origin_column,
        output,
    );
}

const NativeConsequenceView = struct {
    kind: protocol.ConsequenceKind = .none,
    reply_required: bool = false,
    metadata: [protocol.consequence_metadata_bytes]u8 = @splat(0),
    payload: []const u8 = &.{},
};

fn nativeWriteU16(output: []u8, value: u16) void {
    std.debug.assert(output.len == 2);
    output[0] = @truncate(value >> 8);
    output[1] = @truncate(value);
}

fn nativeWriteU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

fn nativeWriteU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    for (0..8) |index|
        output[index] = @truncate(value >> @intCast((7 - index) * 8));
}

fn nativeReadU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        input[3];
}

fn nativeConsequenceRequiresReply(value: native_instance.Consequence) bool {
    return switch (value) {
        .clipboard => |request| request.kind == .query,
        .pointer_shape => |request| request.payload.len != 0 and
            request.payload[0] == '?',
        .container => |occurrence| switch (occurrence.request) {
            .report_state,
            .report_position,
            .report_screen_cells,
            .report_icon_title,
            => true,
            else => false,
        },
        .color_preference_query => true,
        else => false,
    };
}

fn nativeConsequenceView(
    value: ?native_instance.Consequence,
) error{InvalidConsequence}!NativeConsequenceView {
    const consequence = value orelse return .{};
    var result = NativeConsequenceView{
        .reply_required = nativeConsequenceRequiresReply(consequence),
    };
    switch (consequence) {
        .clipboard => |request| {
            if (request.selection.len >
                protocol.consequence_clipboard_selection_bytes)
                return error.InvalidConsequence;
            result.kind = .clipboard;
            result.metadata[0] = @backingInt(switch (request.protocol) {
                .osc52 => protocol.ConsequenceClipboardProtocol.osc52,
                .kitty_5522 => .kitty_5522,
            });
            result.metadata[1] = @backingInt(switch (request.kind) {
                .set => protocol.ConsequenceClipboardKind.set,
                .query => .query,
                .packet => .packet,
            });
            result.metadata[2] = @intCast(request.selection.len);
            @memcpy(
                result.metadata[4..][0..request.selection.len],
                request.selection,
            );
            result.payload = request.payload;
        },
        .notification => |notification| {
            result.kind = .notification;
            result.metadata[0] = @backingInt(switch (notification.kind) {
                .message => protocol.ConsequenceNotificationKind.message,
                .steal_focus => .steal_focus,
                .request_attention => .request_attention,
            });
            nativeWriteU16(result.metadata[2..4], notification.command);
            result.payload = notification.payload;
        },
        .pointer_shape => |request| {
            result.kind = .pointer_shape;
            nativeWriteU64(result.metadata[0..8], request.reset_generation);
            result.metadata[8] = @intFromBool(request.alternate_screen);
            result.payload = request.payload;
        },
        .file_transfer => |packet| {
            result.kind = .file_transfer;
            result.metadata[0] = @backingInt(switch (packet.protocol) {
                .iterm2_1337 => protocol.ConsequenceFileTransferProtocol.iterm2_1337,
                .kitty_5113 => .kitty_5113,
            });
            result.payload = packet.payload;
        },
        .drag_drop => |command| {
            result.kind = .drag_drop;
            result.metadata[0] = @backingInt(switch (command.kind) {
                .enable => protocol.ConsequenceDragDropKind.enable,
                .disable => .disable,
                .accept => .accept,
                .request => .request,
                .complete => .complete,
                .query => .query,
                .continuation => .continuation,
                .unsupported => .unsupported,
            });
            result.metadata[1] = command.command;
            var flags: u8 = 0;
            if (command.more) flags |= 0x01;
            if (command.remote) flags |= 0x02;
            if (command.client_id) |id| {
                flags |= 0x04;
                nativeWriteU32(result.metadata[4..8], id);
            }
            if (command.operation) |operation| {
                flags |= 0x08;
                nativeWriteU32(result.metadata[8..12], operation);
            }
            if (command.index) |index| {
                flags |= 0x10;
                nativeWriteU32(result.metadata[12..16], index);
            }
            result.metadata[2] = flags;
            result.payload = command.payload;
        },
        .container => |occurrence| {
            result.kind = .container;
            result.metadata[0] = @backingInt(switch (occurrence.request) {
                .deiconify => protocol.ConsequenceContainerKind.deiconify,
                .iconify => .iconify,
                .move => .move,
                .resize_pixels => .resize_pixels,
                .raise => .raise,
                .lower => .lower,
                .resize_rows => .resize_rows,
                .resize_columns => .resize_columns,
                .resize_cells => .resize_cells,
                .report_state => .report_state,
                .report_position => .report_position,
                .report_screen_cells => .report_screen_cells,
                .report_icon_title => .report_icon_title,
            });
            switch (occurrence.request) {
                .move => |request| {
                    nativeWriteU32(result.metadata[4..8], request.x);
                    nativeWriteU32(result.metadata[8..12], request.y);
                },
                .resize_pixels => |request| {
                    nativeWriteU32(result.metadata[4..8], request.height);
                    nativeWriteU32(result.metadata[8..12], request.width);
                },
                .resize_rows => |rows| nativeWriteU32(result.metadata[4..8], rows),
                .resize_columns => |columns| nativeWriteU32(
                    result.metadata[4..8],
                    @backingInt(columns),
                ),
                .resize_cells => |request| {
                    nativeWriteU32(result.metadata[4..8], request.rows);
                    nativeWriteU32(result.metadata[8..12], request.cols);
                },
                else => {},
            }
        },
        .color_preference_query => {
            result.kind = .color_preference;
        },
        .media_copy => |occurrence| {
            result.kind = .media_copy;
            result.metadata[0] = @intFromBool(occurrence.request.private);
            nativeWriteU16(
                result.metadata[2..4],
                occurrence.request.parameter,
            );
        },
        .bell => result.kind = .bell,
        .legacy_control => |occurrence| {
            result.kind = .legacy_control;
            result.metadata[0] = @backingInt(switch (occurrence.kind) {
                .tek_point_plot => protocol.ConsequenceLegacyControlKind.tek_point_plot,
                .tek_graph => .tek_graph,
                .tek_incremental_plot => .tek_incremental_plot,
                .tek_alpha => .tek_alpha,
                .tek_copy => .tek_copy,
                .tek_special_point_plot => .tek_special_point_plot,
                .tek_write_thru_short_dashed => .tek_write_thru_short_dashed,
                .hp_memory_lock => .hp_memory_lock,
            });
        },
        .dcs => |occurrence| {
            result.kind = .dcs;
            result.metadata[0] = @backingInt(switch (occurrence.kind) {
                .xtsettcap => protocol.ConsequenceDcsKind.xtsettcap,
                .decudk => .decudk,
                .decaupss => .decaupss,
                .iterm_tmux_hook => .iterm_tmux_hook,
                .iterm_ssh_hook => .iterm_ssh_hook,
                .iterm_tmux_wrap => .iterm_tmux_wrap,
                .kitty_remote_command => .kitty_remote_command,
                .kitty_overlay_ready => .kitty_overlay_ready,
                .kitty_result => .kitty_result,
                .kitty_print => .kitty_print,
                .kitty_echo => .kitty_echo,
                .kitty_ssh => .kitty_ssh,
                .kitty_askpass => .kitty_askpass,
                .kitty_clone => .kitty_clone,
                .kitty_edit => .kitty_edit,
            });
            result.payload = occurrence.payload;
        },
        .string_control => |occurrence| {
            result.kind = .string_control;
            result.metadata[0] = @backingInt(switch (occurrence.kind) {
                .apc => protocol.ConsequenceStringKind.apc,
                .pm => .pm,
                .sos => .sos,
            });
            result.payload = occurrence.payload;
        },
    }
    if (result.payload.len > protocol.maximum_consequence_payload_bytes)
        return error.InvalidConsequence;
    return result;
}

pub export fn howl_odin_bridge_native_terminal_consequence_observe(
    raw: ?*NativeTerminalHandle,
    info: *ConsequenceInfo,
    payload_ptr: [*]u8,
    payload_capacity: usize,
    copied_len: *usize,
) i32 {
    info.* = .{};
    copied_len.* = 0;
    const owner = nativeTerminalValue(raw) orelse return 1;
    const observation = native_instance.terminal(owner.value);
    const current = observation.consequenceHead();
    const projected = nativeConsequenceView(current) catch |failure| {
        owner.setError("consequence_observe", @errorName(failure));
        return 2;
    };
    info.* = .{
        .terminal_revision = observation.semanticSequence(),
        .authority_client_id = 0,
        .generation = if (current) |value| value.id() else 0,
        .payload_len = @intCast(projected.payload.len),
        .kind = @backingInt(projected.kind),
        .reply_required = @intFromBool(projected.reply_required),
        .metadata = projected.metadata,
    };
    const count = @min(payload_capacity, projected.payload.len);
    @memcpy(payload_ptr[0..count], projected.payload[0..count]);
    copied_len.* = count;
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_consequence_consume(
    raw: ?*NativeTerminalHandle,
    generation: u64,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    native_instance.consumeConsequence(
        owner.value,
        generation,
    ) catch |failure| {
        owner.setError("consequence_consume", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_consequence_reply(
    raw: ?*NativeTerminalHandle,
    generation: u64,
    kind_raw: u8,
    body_ptr: [*]const u8,
    body_len: usize,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    const body = body_ptr[0..body_len];
    const kind = std.enums.fromInt(
        protocol.ConsequenceReplyKind,
        kind_raw,
    ) orelse return 2;
    switch (kind) {
        .clipboard => {
            const replied = native_instance.replyClipboard(
                owner.value,
                generation,
                body,
            ) catch |failure| {
                owner.setError("consequence_reply", @errorName(failure));
                return 2;
            };
            if (!replied) return 2;
        },
        .pointer_shape => native_instance.replyPointerShape(
            owner.value,
            generation,
            body,
        ) catch |failure| {
            owner.setError("consequence_reply", @errorName(failure));
            return 2;
        },
        .color_preference => {
            if (body.len != 1) return 2;
            native_instance.replyColorPreference(
                owner.value,
                generation,
                if (body[0] == 1) .dark else .light,
            ) catch |failure| {
                owner.setError("consequence_reply", @errorName(failure));
                return 2;
            };
        },
        .container_state => {
            if (body.len != 1) return 2;
            native_instance.replyContainer(
                owner.value,
                generation,
                .{ .state = if (body[0] == 1) .normal else .iconified },
            ) catch |failure| {
                owner.setError("consequence_reply", @errorName(failure));
                return 2;
            };
        },
        .container_position => {
            if (body.len != 8) return 2;
            native_instance.replyContainer(
                owner.value,
                generation,
                .{ .position = .{
                    .x = nativeReadU32(body[0..4]),
                    .y = nativeReadU32(body[4..8]),
                } },
            ) catch |failure| {
                owner.setError("consequence_reply", @errorName(failure));
                return 2;
            };
        },
        .container_screen_cells => {
            if (body.len != 8) return 2;
            native_instance.replyContainer(
                owner.value,
                generation,
                .{ .screen_cells = .{
                    .rows = nativeReadU32(body[0..4]),
                    .cols = nativeReadU32(body[4..8]),
                } },
            ) catch |failure| {
                owner.setError("consequence_reply", @errorName(failure));
                return 2;
            };
        },
        .container_icon_title => native_instance.replyContainer(
            owner.value,
            generation,
            .{ .icon_title = body },
        ) catch |failure| {
            owner.setError("consequence_reply", @errorName(failure));
            return 2;
        },
        .container_decline => native_instance.declineContainerQuery(
            owner.value,
            generation,
        ) catch |failure| {
            owner.setError("consequence_reply", @errorName(failure));
            return 2;
        },
    }
    return 0;
}

pub export fn howl_odin_bridge_native_terminal_copy_error(
    raw: ?*NativeTerminalHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const owner = nativeTerminalValue(raw) orelse return;
    const count = @min(output_capacity, owner.last_error_len);
    @memcpy(output_ptr[0..count], owner.last_error[0..count]);
    output_len.* = count;
}

/// Borrows only the backend publication exchange; it grants no Instance access.
pub export fn howl_odin_bridge_native_terminal_render_exchange(
    raw: ?*NativeTerminalHandle,
) ?*native_instance.RenderExchange {
    const owner = nativeTerminalValue(raw) orelse return null;
    return native_instance.renderExchange(owner.value) catch null;
}

/// Publishes one canonical live/history presentation cut from the terminal owner.
pub export fn howl_odin_bridge_native_terminal_publish_history(
    raw: ?*NativeTerminalHandle,
    history_offset: u32,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    const view = native_instance.terminal(owner.value).semanticView(
        history_offset,
    );
    owner.history_offset = view.history_offset;
    native_instance.publishRenderAt(
        owner.value,
        owner.history_offset,
    ) catch |failure| {
        owner.setError("publish_history", @errorName(failure));
        return 2;
    };
    return 0;
}

/// Replaces the local Instance presentation on its sole terminal-owner thread.
pub export fn howl_odin_bridge_native_terminal_reconfigure_presentation(
    raw: ?*NativeTerminalHandle,
    font_ptr: [*]const u8,
    font_len: usize,
    italic_ptr: [*]const u8,
    italic_len: usize,
    bold_ptr: [*]const u8,
    bold_len: usize,
    bold_italic_ptr: [*]const u8,
    bold_italic_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: [*]const u8,
    secondary_fallback_len: usize,
    font_pixels: u16,
) i32 {
    const owner = nativeTerminalValue(raw) orelse return 1;
    if (font_len == 0 or font_pixels == 0) return 2;
    var fallback_storage: [2][]const u8 = undefined;
    const config = nativePresentationConfig(
        &fallback_storage,
        font_ptr[0..font_len],
        italic_ptr[0..italic_len],
        bold_ptr[0..bold_len],
        bold_italic_ptr[0..bold_italic_len],
        fallback_ptr[0..fallback_len],
        secondary_fallback_ptr[0..secondary_fallback_len],
        font_pixels,
    );
    _ = native_instance.reconfigurePresentation(
        owner.value,
        config,
    ) catch |failure| {
        owner.setError("reconfigure_presentation", @errorName(failure));
        return 3;
    };
    owner.publication.revision =
        native_instance.terminal(owner.value).semanticSequence();
    owner.publishCurrent() catch |failure| {
        owner.setError("publish", @errorName(failure));
        return 3;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_create(
    exchange: ?*native_instance.RenderExchange,
) ?*NativeCanvasHandle {
    const value = exchange orelse return null;
    const canvas = std.heap.c_allocator.create(NativeCanvas) catch return null;
    canvas.* = .{
        .allocator = std.heap.c_allocator,
        .exchange = value,
    };
    return @ptrCast(canvas);
}

pub export fn howl_odin_bridge_native_canvas_destroy(
    raw: ?*NativeCanvasHandle,
) void {
    const canvas = nativeCanvasValue(raw) orelse return;
    canvas.deinit();
}

/// Claims the newest unread publication; returns 9 when no frame is ready.
pub export fn howl_odin_bridge_native_canvas_prepare(
    raw: ?*NativeCanvasHandle,
) i32 {
    const canvas = nativeCanvasValue(raw) orelse return 1;
    canvas.clearError();
    canvas.stage() catch |failure| {
        if (failure == error.NoFrame) return 9;
        canvas.setError("prepare", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_accept(
    raw: ?*NativeCanvasHandle,
) i32 {
    const canvas = nativeCanvasValue(raw) orelse return 1;
    canvas.accept() catch |failure| {
        canvas.setError("accept", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_discard(
    raw: ?*NativeCanvasHandle,
) i32 {
    const canvas = nativeCanvasValue(raw) orelse return 1;
    canvas.discard() catch |failure| {
        canvas.setError("discard", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_presentation_generation(
    raw: ?*NativeCanvasHandle,
) u64 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.presentation_generation;
    return canvas.front.presentation_generation;
}

pub export fn howl_odin_bridge_native_canvas_background_rgba(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0xff211918;
    return canvas.front.background_rgba;
}

pub export fn howl_odin_bridge_native_canvas_surface_width(
    raw: ?*NativeCanvasHandle,
) u16 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.surface.width;
    return canvas.front.surface.width;
}

pub export fn howl_odin_bridge_native_canvas_surface_height(
    raw: ?*NativeCanvasHandle,
) u16 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.surface.height;
    return canvas.front.surface.height;
}

pub export fn howl_odin_bridge_native_canvas_cell_width(
    raw: ?*NativeCanvasHandle,
) u16 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.cell_size.width;
    return canvas.front.cell_size.width;
}

pub export fn howl_odin_bridge_native_canvas_cell_height(
    raw: ?*NativeCanvasHandle,
) u16 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.cell_size.height;
    return canvas.front.cell_size.height;
}

pub export fn howl_odin_bridge_native_canvas_frame_revision(
    raw: ?*NativeCanvasHandle,
) u64 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.revision;
    return canvas.front.frame_revision;
}

pub export fn howl_odin_bridge_native_canvas_terminal_revision(
    raw: ?*NativeCanvasHandle,
) u64 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.terminal_revision;
    return canvas.front.terminal_revision;
}

pub export fn howl_odin_bridge_native_canvas_history_offset(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.history_offset;
    return canvas.front.history_offset;
}

pub export fn howl_odin_bridge_native_canvas_history_count(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.history_count;
    return canvas.front.history_count;
}

pub export fn howl_odin_bridge_native_canvas_history_row_base(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return frame.history_row_base;
    return canvas.front.history_row_base;
}

pub export fn howl_odin_bridge_native_canvas_alternate_screen(
    raw: ?*NativeCanvasHandle,
) u8 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    if (canvas.pending()) |frame| return @intFromBool(frame.alternate_screen);
    return @intFromBool(canvas.front.alternate_screen);
}

pub export fn howl_odin_bridge_native_canvas_upload_count(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    const frame = canvas.pending() orelse return 0;
    return @intCast(frame.uploads.len);
}

pub export fn howl_odin_bridge_native_canvas_removal_count(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    const frame = canvas.pending() orelse return 0;
    return @intCast(frame.removals.len);
}

pub export fn howl_odin_bridge_native_canvas_command_count(
    raw: ?*NativeCanvasHandle,
) u32 {
    const canvas = nativeCanvasValue(raw) orelse return 0;
    const frame = canvas.pending() orelse return 0;
    return @intCast(frame.commands.len);
}

pub export fn howl_odin_bridge_native_canvas_upload_info(
    raw: ?*NativeCanvasHandle,
    index: u32,
    output: *RenderResourceInfo,
) i32 {
    output.* = .{};
    const canvas = nativeCanvasValue(raw) orelse return 1;
    const frame = canvas.pending() orelse return 3;
    if (index >= frame.uploads.len) return 2;
    const upload = frame.uploads[index];
    fillRenderResourceRef(upload.resource, output);
    output.pixel_count = upload.pixel_count;
    output.stride = upload.stride;
    output.width = upload.size.width;
    output.height = upload.size.height;
    output.format = @backingInt(upload.format);
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_upload_copy(
    raw: ?*NativeCanvasHandle,
    index: u32,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const canvas = nativeCanvasValue(raw) orelse return 1;
    const frame = canvas.pending() orelse return 3;
    if (index >= frame.uploads.len) return 2;
    const upload = frame.uploads[index];
    const end = std.math.add(
        usize,
        upload.pixel_offset,
        upload.pixel_count,
    ) catch return 3;
    if (end > frame.pixels.len) return 3;
    if (output_capacity < upload.pixel_count) return 4;
    @memcpy(
        output_ptr[0..upload.pixel_count],
        frame.pixels[upload.pixel_offset..end],
    );
    output_len.* = upload.pixel_count;
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_removal_info(
    raw: ?*NativeCanvasHandle,
    index: u32,
    output: *RenderRemovalInfo,
) i32 {
    output.* = .{};
    const canvas = nativeCanvasValue(raw) orelse return 1;
    const frame = canvas.pending() orelse return 3;
    if (index >= frame.removals.len) return 2;
    fillRenderRemovalRef(frame.removals[index], output);
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_command_info(
    raw: ?*NativeCanvasHandle,
    index: u32,
    output: *RenderCommandInfo,
) i32 {
    output.* = .{};
    const canvas = nativeCanvasValue(raw) orelse return 1;
    const frame = canvas.pending() orelse return 3;
    if (index >= frame.commands.len) return 2;
    fillRenderCommandInfo(frame.commands[index], output);
    return 0;
}

pub export fn howl_odin_bridge_native_canvas_copy_error(
    raw: ?*NativeCanvasHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const canvas = nativeCanvasValue(raw) orelse return;
    const count = @min(output_capacity, canvas.last_error_len);
    @memcpy(output_ptr[0..count], canvas.last_error[0..count]);
    output_len.* = count;
}

pub export fn howl_odin_bridge_native_terminal_info_size() u32 {
    return @sizeOf(NativeTerminalInfo);
}

/// Copies one terminal-thread-owned UI cut without creating client/snapshot state.
pub export fn howl_odin_bridge_native_terminal_snapshot(
    raw: ?*NativeTerminalHandle,
    history_offset: u32,
    info: *NativeTerminalInfo,
    title_ptr: [*]u8,
    title_capacity: usize,
    title_len: *usize,
    row_shapes_ptr: [*]NativeRowShape,
    row_shape_capacity: usize,
    row_shape_count: *usize,
) i32 {
    info.* = .{};
    title_len.* = 0;
    row_shape_count.* = 0;
    const owner = nativeTerminalValue(raw) orelse return 1;
    const observation = native_instance.terminal(owner.value);
    const view = observation.semanticView(history_offset);
    if (view.rows > row_shape_capacity) return 2;
    fillNativeTerminalInfo(owner, history_offset, info);
    const title = observation.title() orelse "";
    title_len.* = writeDisplayTitle(title, title_ptr[0..title_capacity]);
    for (0..view.rows) |row_index| {
        const row: u16 = @intCast(row_index);
        const last = nativeLastContentColumn(&view, row);
        row_shapes_ptr[row_index] = .{
            .content_end_exclusive = if (last) |column|
                @intCast(@min(
                    @as(u32, view.cols),
                    @as(u32, column) + 1,
                ))
            else
                0,
            .wrapped = @intFromBool(view.rowWrapped(row)),
        };
    }
    row_shape_count.* = view.rows;
    return 0;
}

pub export fn howl_odin_bridge_interrupt_create() ?*client.Interrupt {
    return client.Interrupt.init(std.heap.c_allocator) catch null;
}

pub export fn howl_odin_bridge_interrupt_cancel(value: ?*client.Interrupt) i32 {
    const token = value orelse return 1;
    token.cancel() catch return 2;
    return 0;
}

pub export fn howl_odin_bridge_interrupt_destroy(value: ?*client.Interrupt) void {
    if (value) |token| token.deinit();
}

const RouteKind = enum(u8) {
    direct = 0,
    server = 1,
};

const ConnectTarget = struct {
    kind: RouteKind,
    endpoint: []const u8,
    server_id: u64 = 0,
    session_id: u64 = 0,
    instance_id: u64 = 0,
};

fn targetFromAbi(kind_raw: u8, endpoint: []const u8, server_id: u64, session_id: u64, instance_id: u64) !ConnectTarget {
    const kind: RouteKind = switch (kind_raw) {
        0 => .direct,
        1 => .server,
        else => return error.InvalidEndpoint,
    };
    return switch (kind) {
        .direct => blk: {
            if (endpoint.len == 0) return error.InvalidEndpoint;
            if (server_id != 0 or session_id != 0 or instance_id != 0) return error.InvalidEndpoint;
            break :blk .{ .kind = .direct, .endpoint = endpoint };
        },
        .server => blk: {
            if (endpoint.len == 0) return error.InvalidEndpoint;
            if (server_id == 0 or session_id == 0 or instance_id == 0) return error.InvalidEndpoint;
            break :blk .{
                .kind = .server,
                .endpoint = endpoint,
                .server_id = server_id,
                .session_id = session_id,
                .instance_id = instance_id,
            };
        },
    };
}

fn connectForHost(
    runtime: ?*Runtime,
    interrupt: ?*client.Interrupt,
    target: ConnectTarget,
    diagnostic: *client.ConnectDiagnostic,
) (client.Error || server_client.Error)!client.Connection {
    if (runtime == null and interrupt != null) return error.InvalidEndpoint;
    return switch (target.kind) {
        .direct => client.Connection.connectCancelable(
            std.heap.c_allocator,
            target.endpoint,
            diagnostic,
            interrupt,
        ),
        .server => blk: {
            const attached = try server_client.attach(std.heap.c_allocator, .{
                .endpoint = target.endpoint,
                .server_id = target.server_id,
                .session_id = target.session_id,
                .instance_id = target.instance_id,
            }, diagnostic, interrupt);
            break :blk try client.connectTransport(std.heap.c_allocator, attached.stream, diagnostic);
        },
    };
}

const RenderHandle = opaque {};

// Existing full-observation encoding preference, after endpoint validation.
// TCP retains compression; Unix retains its measured raw-snapshot default.
// View reuse below is independent of this heuristic and sends no extra bytes.
fn rawObservationTarget(target: ConnectTarget) bool {
    return target.kind == .direct and std.mem.startsWith(u8, target.endpoint, "unix:");
}

fn requestObservation(
    connection: *client.Connection,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
    raw: bool,
) client.rich.Error!client.rich.Snapshot {
    if (raw) return client.rich.requestRaw(connection, allocator, after_revision, history_offset);
    return client.rich.request(connection, allocator, after_revision, history_offset);
}

fn nativePresentationConfig(
    fallback_storage: *[2][]const u8,
    regular_path: []const u8,
    italic_path: []const u8,
    bold_path: []const u8,
    bold_italic_path: []const u8,
    fallback_path: []const u8,
    secondary_fallback_path: []const u8,
    font_pixels: u16,
) native_instance.PresentationConfig {
    var fallback_count: usize = 0;
    if (fallback_path.len != 0) {
        fallback_storage.*[fallback_count] = fallback_path;
        fallback_count += 1;
    }
    if (secondary_fallback_path.len != 0) {
        fallback_storage.*[fallback_count] = secondary_fallback_path;
        fallback_count += 1;
    }
    const fallbacks = fallback_storage.*[0..fallback_count];
    return .{
        .fonts = .{
            .regular = .{ .path = .{
                .primary = regular_path,
                .fallbacks = fallbacks,
                .size = .{ .pixels = font_pixels },
            } },
            .italic = if (italic_path.len != 0) .{ .path = .{
                .primary = italic_path,
                .fallbacks = fallbacks,
                .size = .{ .pixels = font_pixels },
            } } else null,
            .bold = if (bold_path.len != 0) .{ .path = .{
                .primary = bold_path,
                .fallbacks = fallbacks,
                .size = .{ .pixels = font_pixels },
            } } else null,
            .bold_italic = if (bold_italic_path.len != 0) .{ .path = .{
                .primary = bold_italic_path,
                .fallbacks = fallbacks,
                .size = .{ .pixels = font_pixels },
            } } else null,
        },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 256,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = 16,
        },
        .atlas = .{
            .width = render_atlas_extent,
            .height = render_atlas_extent,
            .entry_capacity = 256,
        },
        .shaped_capacity = 32,
        .raster_bytes = render_pixel_capacity,
        .command_capacity = render_command_initial_capacity,
        .command_limit = render_command_limit,
        .incremental_row_capacity = render.limits.maximum_rows,
        .incremental_command_capacity = render_incremental_command_capacity,
    };
}

test "only validated transported Unix endpoints avoid same-machine text compression" {
    try std.testing.expect(rawObservationTarget(try targetFromAbi(0, "unix:/run/user/1000/howl.sock", 0, 0, 0)));
    try std.testing.expect(!rawObservationTarget(try targetFromAbi(0, "tcp://127.0.0.1:43127", 0, 0, 0)));
    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(2, "", 0, 0, 7));
}
const render_resource_limit: usize = terminal_render.maximum_external_images + 1;
const render_atlas_extent: u16 = 512;
const render_pixel_capacity: usize = @as(usize, render_atlas_extent) * render_atlas_extent;
const render_command_initial_capacity: usize = 4 * 1024;
const render_command_limit: usize = render.limits.maximum_frame_commands;
// Retain one common dense interactive row-command window. Richer frames remain
// correct by falling back to complete projection when this bounded cache fills.
const render_incremental_command_capacity: usize = 32 * 1024;
// One global recipe plus up to eight profile-specific font recipes can be live
// concurrently in the Odin product.
const render_lane_limit: usize = 9;
const RenderImageBinding = terminal_render.ExternalImageBinding;

const ExternalUpload = struct {
    external: terminal_render.FrameExternalResource,
    fetched: client.images.Resource,
};

pub const RenderResourceInfo = extern struct {
    resource: u64 = 0,
    generation: u64 = 0,
    pixel_count: u64 = 0,
    stride: u64 = 0,
    width: u16 = 0,
    height: u16 = 0,
    format: u8 = 0,
    _reserved: [3]u8 = @splat(0),
};

pub const RenderRemovalInfo = extern struct {
    resource: u64 = 0,
    generation: u64 = 0,
};

pub const RenderCommandInfo = extern struct {
    resource: u64 = 0,
    generation: u64 = 0,
    color_rgba: u32 = 0,
    destination_x: i32 = 0,
    destination_y: i32 = 0,
    clip_x: i32 = 0,
    clip_y: i32 = 0,
    destination_width: u16 = 0,
    destination_height: u16 = 0,
    clip_width: u16 = 0,
    clip_height: u16 = 0,
    source_x: u16 = 0,
    source_y: u16 = 0,
    source_width: u16 = 0,
    source_height: u16 = 0,
    resource_width: u16 = 0,
    resource_height: u16 = 0,
    tag: u8 = 0,
    format: u8 = 0,
    cursor_component: u8 = 0,
    _reserved: u8 = 0,
};

pub const SearchMatchInfo = extern struct {
    cut_revision: u64 = 0,
    row: i32 = 0,
    start_column: u16 = 0,
    end_column: u16 = 0,
    columns: u16 = 0,
    found: u8 = 0,
    complete: u8 = 1,
    alternate_screen: u8 = 0,
    _reserved: u8 = 0,
    scanned_snapshots: u32 = 0,
};

pub const SelectionRangeInfo = extern struct {
    start_row: i32 = 0,
    end_row: i32 = 0,
    start_column: u16 = 0,
    end_column: u16 = 0,
    columns: u16 = 0,
    found: u8 = 0,
    alternate_screen: u8 = 0,
    _reserved: [2]u8 = @splat(0),
};

pub const InteractionStateInfo = extern struct {
    terminal_revision: u64 = 0,
    flags: u32 = 0,
    mouse_tracking: u8 = 0,
    mouse_protocol: u8 = 0,
    pointer_mode: u8 = 0,
    _reserved: u8 = 0,
};

pub const NativeTerminalInfo = extern struct {
    revision: u64 = 0,
    terminal_revision: u64 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    interaction_flags: u32 = 0,
    rows: u16 = 0,
    columns: u16 = 0,
    cursor_row: u16 = 0,
    cursor_column: u16 = 0,
    task_progress: u16 = 0,
    cursor_shape: u8 = 0,
    cursor_visible: u8 = 0,
    alternate_screen: u8 = 0,
    stream_closed: u8 = 0,
    child_exited: u8 = 0,
    mouse_tracking: u8 = 0,
    mouse_protocol: u8 = 0,
    pointer_mode: u8 = 0,
    _reserved: [4]u8 = @splat(0),
};

pub const NativeRowShape = extern struct {
    content_end_exclusive: u16 = 0,
    wrapped: u8 = 0,
    _reserved: u8 = 0,
};

const interaction_info_flags = struct {
    const alternate_scroll: u32 = 1 << 0;
    const focus_reporting: u32 = 1 << 1;
};

comptime {
    if (@sizeOf(NativeTerminalInfo) != 56)
        @compileError("Odin native terminal info ABI drifted");
    if (@sizeOf(NativeRowShape) != 4)
        @compileError("Odin native row-shape ABI drifted");
}

const maximum_search_query_bytes: usize = 4096;
const maximum_search_retries: usize = 8;

const RenderFront = struct {
    frame_revision: u64 = 0,
    begin: ?protocol.SnapshotBegin = null,
    selection_rows: [render.limits.maximum_rows]client.selection.RowShape = undefined,
    surface: terminal_render.Size = .{ .width = 1, .height = 1 },
    background_rgba: u32 = 0xff211918,
};

const RenderFonts = struct {
    regular: *render.text.FontSet,
    italic: ?*render.text.FontSet = null,
    bold: ?*render.text.FontSet = null,
    bold_italic: ?*render.text.FontSet = null,

    fn deinit(self: *RenderFonts) void {
        if (self.bold_italic) |value| value.deinit();
        if (self.bold) |value| value.deinit();
        if (self.italic) |value| value.deinit();
        self.regular.deinit();
        self.* = undefined;
    }

    fn faces(self: *RenderFonts) terminal_render.FontFaces {
        return .{
            .regular = self.regular,
            .italic = self.italic,
            .bold = self.bold,
            .bold_italic = self.bold_italic,
        };
    }

    fn metrics(self: *const RenderFonts) render.text.Metrics {
        return self.regular.metrics();
    }
};

const RenderLane = struct {
    allocator: std.mem.Allocator,
    regular_path: []u8,
    italic_path: []u8,
    bold_path: []u8,
    bold_italic_path: []u8,
    fallback_path: []u8,
    secondary_fallback_path: []u8,
    font_pixels: u16,
    fonts: RenderFonts,
    store: *terminal_render.Store,
    borrowers: std.atomic.Value(u32) = .init(1),

    fn matches(
        self: *const RenderLane,
        regular: []const u8,
        italic: []const u8,
        bold: []const u8,
        bold_italic: []const u8,
        fallback: []const u8,
        secondary_fallback: []const u8,
        font_pixels: u16,
    ) bool {
        return self.font_pixels == font_pixels and
            std.mem.eql(u8, self.regular_path, regular) and
            std.mem.eql(u8, self.italic_path, italic) and
            std.mem.eql(u8, self.bold_path, bold) and
            std.mem.eql(u8, self.bold_italic_path, bold_italic) and
            std.mem.eql(u8, self.fallback_path, fallback) and
            std.mem.eql(u8, self.secondary_fallback_path, secondary_fallback);
    }

    fn deinit(self: *RenderLane) void {
        std.debug.assert(self.borrowers.load(.acquire) == 0);
        terminal_render.deinitStore(self.store);
        self.fonts.deinit();
        self.allocator.free(self.secondary_fallback_path);
        self.allocator.free(self.fallback_path);
        self.allocator.free(self.bold_italic_path);
        self.allocator.free(self.bold_path);
        self.allocator.free(self.italic_path);
        self.allocator.free(self.regular_path);
        self.* = undefined;
    }
};

const RenderScratch = struct {
    allocator: std.mem.Allocator,
    frame_uploads: [render_resource_limit]terminal_render.FrameResourceUpload = undefined,
    frame_removals: [render_resource_limit]terminal_render.ResourceRef = undefined,
    frame_commands: []terminal_render.Command,
    frame_pixels: []u8,
    prepared_owner: ?*Render = null,

    fn deinit(self: *RenderScratch) void {
        std.debug.assert(self.prepared_owner == null);
        self.allocator.free(self.frame_pixels);
        self.allocator.free(self.frame_commands);
        self.* = undefined;
    }
};

const Render = struct {
    front: RenderFront = .{},
    allocator: std.mem.Allocator,
    runtime: ?*Runtime = null,
    connection: client.Connection,
    raw_observation: bool,
    lane: *RenderLane,
    terminal_renderer: *terminal_render.Renderer,
    cell_size: terminal_render.Size,
    scratch: *RenderScratch,
    residencies: [render_resource_limit]terminal_render.Residency = undefined,
    residency_count: usize = 0,
    image_bindings: [terminal_render.maximum_external_images]RenderImageBinding = undefined,
    image_binding_count: usize = 0,
    missing_external: [terminal_render.maximum_external_images]terminal_render.FrameExternalResource = undefined,
    external_uploads: [terminal_render.maximum_external_images]ExternalUpload = undefined,
    external_upload_count: usize = 0,
    frame_upload_count: usize = 0,
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    pixel_count: usize = 0,
    frame_revision: u64 = 0,
    // Pending snapshot facts are published only after the host accepts resources.
    begin: ?protocol.SnapshotBegin = null,
    selection_rows: [render.limits.maximum_rows]client.selection.RowShape = undefined,
    surface: terminal_render.Size = .{ .width = 1, .height = 1 },
    background_rgba: u32 = 0xff211918,
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *Render) void {
        self.last_error_len = 0;
    }

    fn setError(self: *Render, stage: []const u8, failure_name: []const u8) void {
        const value = std.fmt.bufPrint(&self.last_error, "{s}:{s}", .{ stage, failure_name }) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = value.len;
    }
};

fn renderContentConfig(cell_size: terminal_render.Size) terminal_render.Config {
    const store = renderStoreConfig();
    return .{
        .cell_size = cell_size,
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = store.shape_cache,
        .atlas = .{
            .width = render_atlas_extent,
            .height = render_atlas_extent,
            .entry_capacity = 256,
        },
        .shaped_capacity = store.shaped_capacity,
        .raster_bytes = store.raster_bytes,
        .command_capacity = render_command_initial_capacity,
        .command_limit = render_command_limit,
        .incremental_row_capacity = render.limits.maximum_rows,
        .incremental_command_capacity = render_incremental_command_capacity,
    };
}

fn renderStoreConfig() terminal_render.StoreConfig {
    return .{
        .shape_cache = .{
            .entry_capacity = 256,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = 16,
        },
        .shaped_capacity = 32,
        .raster_bytes = render_pixel_capacity,
    };
}

fn renderSurface(rows: u16, columns: u16, cell: terminal_render.Size) !terminal_render.Size {
    const width = try std.math.mul(u32, columns, cell.width);
    const height = try std.math.mul(u32, rows, cell.height);
    if (width == 0 or height == 0 or width > std.math.maxInt(u16) or height > std.math.maxInt(u16))
        return error.InvalidSurface;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

pub export fn howl_odin_bridge_render_create(
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
    route_kind: u8,
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    font_ptr: [*]const u8,
    font_len: usize,
    italic_ptr: [*]const u8,
    italic_len: usize,
    bold_ptr: [*]const u8,
    bold_len: usize,
    bold_italic_ptr: [*]const u8,
    bold_italic_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: [*]const u8,
    secondary_fallback_len: usize,
    font_pixels: u16,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*RenderHandle {
    diagnostic_len.* = 0;
    if (font_len == 0 or font_pixels == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_render_arguments");
        return null;
    }
    const target = targetFromAbi(route_kind, endpoint_ptr[0..endpoint_len], server_id, session_id, instance_id) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_render_target");
        return null;
    };
    const allocator = std.heap.c_allocator;
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = connectForHost(
        runtime,
        interrupt,
        target,
        &connect_diagnostic,
    ) catch |failure| {
        writeConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
            connect_diagnostic,
        );
        return null;
    };
    defer if (!accepted) connection.deinit();
    const lane = acquireRenderLane(
        runtime,
        allocator,
        font_ptr[0..font_len],
        italic_ptr[0..italic_len],
        bold_ptr[0..bold_len],
        bold_italic_ptr[0..bold_italic_len],
        fallback_ptr[0..fallback_len],
        secondary_fallback_ptr[0..secondary_fallback_len],
        font_pixels,
    ) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    defer if (!accepted) releaseRenderLane(lane);
    const metrics = lane.fonts.metrics();
    const cell_size = terminal_render.Size{
        .width = metrics.advance_width,
        .height = metrics.line_height,
    };
    const terminal_renderer = terminal_render.initWithStore(
        allocator,
        lane.store,
        renderContentConfig(cell_size),
    ) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    defer if (!accepted) terminal_render.deinit(terminal_renderer);
    const scratch = processRenderScratch(runtime, allocator) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    const value = allocator.create(Render) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    value.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connection,
        .raw_observation = rawObservationTarget(target),
        .lane = lane,
        .terminal_renderer = terminal_renderer,
        .cell_size = cell_size,
        .scratch = scratch,
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(value);
}

fn initRenderFonts(
    runtime: ?*Runtime,
    allocator: std.mem.Allocator,
    regular_path: []const u8,
    italic_path: []const u8,
    bold_path: []const u8,
    bold_italic_path: []const u8,
    fallbacks: []const []const u8,
    font_pixels: u16,
) !RenderFonts {
    var result = RenderFonts{
        .regular = try initRenderFont(runtime, allocator, regular_path, fallbacks, font_pixels),
    };
    errdefer result.deinit();
    if (italic_path.len != 0)
        result.italic = try initRenderFont(runtime, allocator, italic_path, fallbacks, font_pixels);
    if (bold_path.len != 0)
        result.bold = try initRenderFont(runtime, allocator, bold_path, fallbacks, font_pixels);
    if (bold_italic_path.len != 0)
        result.bold_italic = try initRenderFont(runtime, allocator, bold_italic_path, fallbacks, font_pixels);
    return result;
}

fn initRenderLane(
    runtime: *Runtime,
    allocator: std.mem.Allocator,
    regular_path: []const u8,
    italic_path: []const u8,
    bold_path: []const u8,
    bold_italic_path: []const u8,
    fallback_path: []const u8,
    secondary_fallback_path: []const u8,
    font_pixels: u16,
) !*RenderLane {
    const regular = try allocator.dupe(u8, regular_path);
    errdefer allocator.free(regular);
    const italic = try allocator.dupe(u8, italic_path);
    errdefer allocator.free(italic);
    const bold = try allocator.dupe(u8, bold_path);
    errdefer allocator.free(bold);
    const bold_italic = try allocator.dupe(u8, bold_italic_path);
    errdefer allocator.free(bold_italic);
    const fallback = try allocator.dupe(u8, fallback_path);
    errdefer allocator.free(fallback);
    const secondary = try allocator.dupe(u8, secondary_fallback_path);
    errdefer allocator.free(secondary);

    var fallback_storage: [2][]const u8 = undefined;
    var fallback_count: usize = 0;
    if (fallback_path.len != 0) {
        fallback_storage[fallback_count] = fallback_path;
        fallback_count += 1;
    }
    if (secondary_fallback_path.len != 0) {
        fallback_storage[fallback_count] = secondary_fallback_path;
        fallback_count += 1;
    }
    var fonts = try initRenderFonts(
        runtime,
        allocator,
        regular_path,
        italic_path,
        bold_path,
        bold_italic_path,
        fallback_storage[0..fallback_count],
        font_pixels,
    );
    errdefer fonts.deinit();
    const store = try terminal_render.initStore(
        allocator,
        fonts.faces(),
        renderStoreConfig(),
    );
    errdefer terminal_render.deinitStore(store);
    const lane = try allocator.create(RenderLane);
    lane.* = .{
        .allocator = allocator,
        .regular_path = regular,
        .italic_path = italic,
        .bold_path = bold,
        .bold_italic_path = bold_italic,
        .fallback_path = fallback,
        .secondary_fallback_path = secondary,
        .font_pixels = font_pixels,
        .fonts = fonts,
        .store = store,
    };
    return lane;
}

fn acquireRenderLane(
    runtime: ?*Runtime,
    allocator: std.mem.Allocator,
    regular_path: []const u8,
    italic_path: []const u8,
    bold_path: []const u8,
    bold_italic_path: []const u8,
    fallback_path: []const u8,
    secondary_fallback_path: []const u8,
    font_pixels: u16,
) !*RenderLane {
    const owner = runtime orelse return error.RuntimeUnavailable;
    for (owner.render_lanes) |maybe_lane| {
        const lane = maybe_lane orelse continue;
        if (!lane.matches(
            regular_path,
            italic_path,
            bold_path,
            bold_italic_path,
            fallback_path,
            secondary_fallback_path,
            font_pixels,
        )) continue;
        const before = lane.borrowers.fetchAdd(1, .monotonic);
        std.debug.assert(before < 1024);
        return lane;
    }

    var slot: ?usize = null;
    for (owner.render_lanes, 0..) |maybe_lane, index| {
        if (maybe_lane) |lane| {
            if (lane.borrowers.load(.acquire) == 0) {
                slot = index;
                break;
            }
        } else if (slot == null) {
            slot = index;
        }
    }
    const index = slot orelse return error.RenderLaneLimit;
    if (owner.render_lanes[index]) |retired| {
        std.debug.assert(retired.borrowers.load(.acquire) == 0);
        retired.deinit();
        allocator.destroy(retired);
        owner.render_lanes[index] = null;
    }
    const lane = try initRenderLane(
        owner,
        allocator,
        regular_path,
        italic_path,
        bold_path,
        bold_italic_path,
        fallback_path,
        secondary_fallback_path,
        font_pixels,
    );
    owner.render_lanes[index] = lane;
    return lane;
}

fn releaseRenderLane(lane: *RenderLane) void {
    const before = lane.borrowers.fetchSub(1, .release);
    std.debug.assert(before > 0);
}

fn deinitRenderLanes(runtime: *Runtime) void {
    for (&runtime.render_lanes) |*slot| {
        const lane = slot.* orelse continue;
        std.debug.assert(lane.borrowers.load(.acquire) == 0);
        lane.deinit();
        std.heap.c_allocator.destroy(lane);
        slot.* = null;
    }
}

fn processRenderScratch(
    runtime: ?*Runtime,
    allocator: std.mem.Allocator,
) !*RenderScratch {
    const owner = runtime orelse return error.RuntimeUnavailable;
    if (owner.render_scratch) |scratch| return scratch;

    const commands = try allocator.alloc(terminal_render.Command, render_command_limit);
    errdefer allocator.free(commands);
    const pixels = try allocator.alloc(u8, render_pixel_capacity);
    errdefer allocator.free(pixels);
    const scratch = try allocator.create(RenderScratch);
    scratch.* = .{
        .allocator = allocator,
        .frame_commands = commands,
        .frame_pixels = pixels,
    };
    owner.render_scratch = scratch;
    return scratch;
}

fn deinitRenderScratch(runtime: *Runtime) void {
    const scratch = runtime.render_scratch orelse return;
    scratch.deinit();
    std.heap.c_allocator.destroy(scratch);
    runtime.render_scratch = null;
}

fn initRenderFont(
    runtime: ?*Runtime,
    allocator: std.mem.Allocator,
    primary: []const u8,
    fallbacks: []const []const u8,
    font_pixels: u16,
) !*render.text.FontSet {
    if (comptime builtin.os.tag != .windows) {
        return render.text.FontSet.init(allocator, .{
            .primary = primary,
            .fallbacks = fallbacks,
            .size = .{ .pixels = font_pixels },
        });
    }

    const owner = runtime orelse return error.RuntimeUnavailable;
    const io = owner.threaded.io();
    const primary_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        primary,
        allocator,
        .limited(render.text.max_font_bytes),
    );
    defer allocator.free(primary_bytes);

    var fallback_bytes: [2][]u8 = undefined;
    var loaded: usize = 0;
    defer for (fallback_bytes[0..loaded]) |bytes| allocator.free(bytes);
    while (loaded < fallbacks.len) : (loaded += 1) {
        fallback_bytes[loaded] = try std.Io.Dir.cwd().readFileAlloc(
            io,
            fallbacks[loaded],
            allocator,
            .limited(render.text.max_font_bytes),
        );
    }
    return render.text.FontSet.initMemory(allocator, .{
        .primary = primary_bytes,
        .fallbacks = fallback_bytes[0..loaded],
        .size = .{ .pixels = font_pixels },
    });
}

pub export fn howl_odin_bridge_render_destroy(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const allocator = renderer.allocator;
    clearExternalUploads(renderer);
    if (renderer.scratch.prepared_owner == renderer)
        renderer.scratch.prepared_owner = null;
    terminal_render.deinit(renderer.terminal_renderer);
    releaseRenderLane(renderer.lane);
    renderer.connection.deinit();
    releaseRuntime(renderer.runtime);
    allocator.destroy(renderer);
}

fn clearExternalUploads(renderer: *Render) void {
    var index: usize = 0;
    while (index < renderer.external_upload_count) : (index += 1) {
        renderer.external_uploads[index].fetched.deinit();
    }
    renderer.external_upload_count = 0;
}

fn findRenderImageBindingByResource(
    bindings: []const RenderImageBinding,
    resource: terminal_render.ResourceRef,
) ?RenderImageBinding {
    for (bindings) |binding| {
        if (binding.resource.resource == resource.resource and
            binding.resource.generation == resource.generation)
            return binding;
    }
    return null;
}

fn upsertResidency(
    storage: *[render_resource_limit]terminal_render.Residency,
    count: *usize,
    value: terminal_render.Residency,
) error{ResidencyLimit}!void {
    var index: usize = 0;
    while (index < count.*) : (index += 1) {
        const existing = storage[index];
        if (@backingInt(existing.resource.resource) == @backingInt(value.resource.resource)) {
            storage[index] = value;
            return;
        }
    }
    if (count.* == storage.len) return error.ResidencyLimit;
    storage[count.*] = value;
    count.* += 1;
}

fn prepareExternalUploads(
    renderer: *Render,
    bindings: []const RenderImageBinding,
    residency: *[render_resource_limit]terminal_render.Residency,
    residency_count: *usize,
) !void {
    const missing = try terminal_render.missingExternalResources(
        renderer.terminal_renderer,
        renderer.residencies[0..renderer.residency_count],
        &renderer.missing_external,
    );
    if (missing.len > renderer.external_uploads.len) return error.ImageLimit;
    errdefer clearExternalUploads(renderer);

    for (missing) |external| {
        if (external.format != .rgba8)
            return error.InvalidExternalResource;
        const binding = findRenderImageBindingByResource(bindings, external.resource) orelse
            return error.InvalidImageBinding;
        var fetched = try client.images.request(
            &renderer.connection,
            renderer.allocator,
            binding.image_id,
            binding.generation,
        );
        var fetched_owned = true;
        errdefer if (fetched_owned) fetched.deinit();
        const stride = std.math.mul(usize, @as(usize, external.size.width), 4) catch
            return error.InvalidExternalResource;
        const pixel_count = std.math.mul(usize, stride, external.size.height) catch
            return error.InvalidExternalResource;
        if (fetched.width != external.size.width or fetched.height != external.size.height or
            fetched.pixels.len != pixel_count or external.stride != stride)
            return error.InvalidExternalResource;

        renderer.external_uploads[renderer.external_upload_count] = .{
            .external = external,
            .fetched = fetched,
        };
        renderer.external_upload_count += 1;
        fetched_owned = false;
        try upsertResidency(residency, residency_count, .{
            .resource = external.resource,
            .format = external.format,
            .size = external.size,
        });
    }
}

// Synchronous diagnostic entry; the desktop instead prepares on its worker and
// accepts only after the GUI has successfully installed every SDL resource.
pub export fn howl_odin_bridge_render_observe(raw: ?*RenderHandle, history_offset: u32) i32 {
    const result = howl_odin_bridge_render_prepare(raw, history_offset);
    if (result == 0) howl_odin_bridge_render_accept(raw);
    return result;
}

pub export fn howl_odin_bridge_render_discard(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    clearExternalUploads(renderer);
    renderer.frame_upload_count = 0;
    renderer.upload_count = 0;
    renderer.removal_count = 0;
    renderer.command_count = 0;
    renderer.pixel_count = 0;
    if (renderer.scratch.prepared_owner == renderer)
        renderer.scratch.prepared_owner = null;
}

pub export fn howl_odin_bridge_render_accept(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.front.frame_revision = renderer.frame_revision;
    renderer.front.begin = renderer.begin;
    renderer.front.surface = renderer.surface;
    renderer.front.background_rgba = renderer.background_rgba;
    if (renderer.begin) |begin|
        @memcpy(renderer.front.selection_rows[0..begin.rows], renderer.selection_rows[0..begin.rows]);
    if (renderer.scratch.prepared_owner == renderer)
        renderer.scratch.prepared_owner = null;
}

pub export fn howl_odin_bridge_render_prepare(raw: ?*RenderHandle, history_offset: u32) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.clearError();
    clearExternalUploads(renderer);
    var rich = requestObservation(
        &renderer.connection,
        renderer.allocator,
        0,
        history_offset,
        renderer.raw_observation,
    ) catch |failure| {
        renderer.setError("observe", @errorName(failure));
        return 2;
    };
    defer rich.deinit();
    const view = client.view.project(renderer.allocator, &rich) catch |failure| {
        renderer.setError("project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(view);
    return prepareProjectedView(renderer, view);
}

// The offered immutable view is borrowed only during this call. A stale offer
// cannot roll back a renderer that observed farther ahead on its image channel.
// Code 9 means this offer is ineligible, not a transport or terminal failure.
pub export fn howl_odin_bridge_render_prepare_view(raw: ?*RenderHandle, view: ?*const client.view.Snapshot) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const snapshot = view orelse return 9;
    const pending_revision = if (renderer.begin) |begin| begin.revision else 0;
    if (!standaloneLiveView(snapshot) or client.view.begin(snapshot).revision < pending_revision) return 9;
    renderer.clearError();
    clearExternalUploads(renderer);
    return prepareProjectedView(renderer, snapshot);
}

pub export fn howl_odin_bridge_render_prepare_rich_loan(raw: ?*RenderHandle, loan_raw: ?*Handle) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const loan_value = loan_raw orelse return 9;
    const bridge: *Bridge = @ptrCast(@alignCast(loan_value));
    if (!bridge.rich_loan_active or !bridge.rich_loan_taken) return 9;
    const snapshot = &(bridge.live_view orelse return 9);
    const pending_revision = if (renderer.begin) |begin| begin.revision else 0;
    if (snapshot.begin.history_offset != 0 or snapshot.graphics.images.len != 0 or snapshot.begin.revision < pending_revision)
        return 9;
    renderer.clearError();
    clearExternalUploads(renderer);
    return prepareRichView(renderer, snapshot);
}

fn prepareRichView(renderer: *Render, view: *const client.rich.View) i32 {
    const begin = view.begin;
    if (begin.rows > renderer.selection_rows.len) {
        renderer.setError("selection_rows", "row_limit");
        return 3;
    }
    const surface = renderSurface(begin.rows, begin.columns, renderer.cell_size) catch |failure| {
        renderer.setError("surface", @errorName(failure));
        return 3;
    };
    var candidate_bindings: [terminal_render.maximum_external_images]RenderImageBinding = undefined;
    const bindings = terminal_render.planExternalImageBindings(
        renderer.image_bindings[0..renderer.image_binding_count],
        terminal_render.usage(renderer.terminal_renderer),
        view.graphics.images,
        &candidate_bindings,
    ) catch |failure| {
        renderer.setError("image_bindings", @errorName(failure));
        return 3;
    };
    terminal_render.updateRichWithImageBindings(renderer.terminal_renderer, view, bindings) catch |failure| {
        renderer.setError("terminal_canvas", @errorName(failure));
        return 3;
    };
    @memcpy(renderer.image_bindings[0..bindings.len], bindings);
    renderer.image_binding_count = bindings.len;
    var prospective_residencies: [render_resource_limit]terminal_render.Residency = undefined;
    @memcpy(
        prospective_residencies[0..renderer.residency_count],
        renderer.residencies[0..renderer.residency_count],
    );
    var prospective_residency_count = renderer.residency_count;
    prepareExternalUploads(
        renderer,
        bindings,
        &prospective_residencies,
        &prospective_residency_count,
    ) catch |failure| {
        renderer.setError("image_refill", @errorName(failure));
        return 3;
    };
    const scratch = renderer.scratch;
    if (scratch.prepared_owner != null and scratch.prepared_owner != renderer) {
        renderer.setError("frame", "process_lane_busy");
        clearExternalUploads(renderer);
        return 3;
    }
    scratch.prepared_owner = renderer;
    const frame = terminal_render.frame(
        renderer.terminal_renderer,
        prospective_residencies[0..prospective_residency_count],
        .{
            .uploads = &scratch.frame_uploads,
            .removals = &scratch.frame_removals,
            .commands = scratch.frame_commands,
            .pixels = scratch.frame_pixels,
        },
    ) catch |failure| {
        scratch.prepared_owner = null;
        renderer.setError("frame", @errorName(failure));
        clearExternalUploads(renderer);
        return 3;
    };
    renderer.frame_upload_count = frame.uploads.len;
    renderer.upload_count = frame.uploads.len + renderer.external_upload_count;
    renderer.removal_count = frame.removals.len;
    renderer.command_count = frame.commands.len;
    renderer.pixel_count = frame.pixels.len;
    renderer.frame_revision = frame.revision;
    renderer.background_rgba = paddingBackground(&view.presentation);
    for (0..begin.rows) |row| {
        renderer.selection_rows[row] = client.selection.rowShapeRich(view, @intCast(row)).?;
    }
    renderer.begin = begin;
    renderer.surface = surface;
    updateRenderResidency(renderer, frame.uploads, frame.removals);
    for (renderer.external_uploads[0..renderer.external_upload_count]) |external| {
        upsertResidency(&renderer.residencies, &renderer.residency_count, .{
            .resource = external.external.resource,
            .format = external.external.format,
            .size = external.external.size,
        }) catch unreachable;
    }
    return 0;
}

fn prepareProjectedView(renderer: *Render, view: *const client.view.Snapshot) i32 {
    const begin = client.view.begin(view).*;
    if (begin.rows > renderer.selection_rows.len) {
        renderer.setError("selection_rows", "row_limit");
        return 3;
    }
    const surface = renderSurface(begin.rows, begin.columns, renderer.cell_size) catch |failure| {
        renderer.setError("surface", @errorName(failure));
        return 3;
    };
    const graphics = client.view.graphics(view);
    var candidate_bindings: [terminal_render.maximum_external_images]RenderImageBinding = undefined;
    const bindings = terminal_render.planExternalImageBindings(
        renderer.image_bindings[0..renderer.image_binding_count],
        terminal_render.usage(renderer.terminal_renderer),
        graphics.images,
        &candidate_bindings,
    ) catch |failure| {
        renderer.setError("image_bindings", @errorName(failure));
        return 3;
    };
    terminal_render.updateWithImageBindings(renderer.terminal_renderer, view, bindings) catch |failure| {
        renderer.setError("terminal_canvas", @errorName(failure));
        return 3;
    };
    @memcpy(renderer.image_bindings[0..bindings.len], bindings);
    renderer.image_binding_count = bindings.len;
    var prospective_residencies: [render_resource_limit]terminal_render.Residency = undefined;
    @memcpy(
        prospective_residencies[0..renderer.residency_count],
        renderer.residencies[0..renderer.residency_count],
    );
    var prospective_residency_count = renderer.residency_count;
    prepareExternalUploads(
        renderer,
        bindings,
        &prospective_residencies,
        &prospective_residency_count,
    ) catch |failure| {
        renderer.setError("image_refill", @errorName(failure));
        return 3;
    };
    const scratch = renderer.scratch;
    if (scratch.prepared_owner != null and scratch.prepared_owner != renderer) {
        renderer.setError("frame", "process_lane_busy");
        clearExternalUploads(renderer);
        return 3;
    }
    scratch.prepared_owner = renderer;
    const frame = terminal_render.frame(
        renderer.terminal_renderer,
        prospective_residencies[0..prospective_residency_count],
        .{
            .uploads = &scratch.frame_uploads,
            .removals = &scratch.frame_removals,
            .commands = scratch.frame_commands,
            .pixels = scratch.frame_pixels,
        },
    ) catch |failure| {
        scratch.prepared_owner = null;
        renderer.setError("frame", @errorName(failure));
        clearExternalUploads(renderer);
        return 3;
    };
    renderer.frame_upload_count = frame.uploads.len;
    renderer.upload_count = frame.uploads.len + renderer.external_upload_count;
    renderer.removal_count = frame.removals.len;
    renderer.command_count = frame.commands.len;
    renderer.pixel_count = frame.pixels.len;
    renderer.frame_revision = frame.revision;
    renderer.background_rgba = paddingBackground(client.view.presentation(view));
    for (0..begin.rows) |row| {
        renderer.selection_rows[row] = client.selection.rowShape(view, @intCast(row)).?;
    }
    renderer.begin = begin;
    renderer.surface = surface;
    updateRenderResidency(renderer, frame.uploads, frame.removals);
    for (renderer.external_uploads[0..renderer.external_upload_count]) |external| {
        upsertResidency(&renderer.residencies, &renderer.residency_count, .{
            .resource = external.external.resource,
            .format = external.external.format,
            .size = external.external.size,
        }) catch unreachable;
    }
    return 0;
}

fn updateRenderResidency(
    renderer: *Render,
    uploads: []const terminal_render.FrameResourceUpload,
    removals: []const terminal_render.ResourceRef,
) void {
    for (removals) |removal| {
        var index: usize = 0;
        while (index < renderer.residency_count) {
            if (std.meta.eql(renderer.residencies[index].resource, removal)) {
                renderer.residency_count -= 1;
                renderer.residencies[index] = renderer.residencies[renderer.residency_count];
                break;
            }
            index += 1;
        }
    }
    for (uploads) |upload| {
        var index: usize = 0;
        while (index < renderer.residency_count) : (index += 1) {
            const existing = renderer.residencies[index];
            if (@backingInt(existing.resource.resource) == @backingInt(upload.resource.resource)) {
                renderer.residencies[index] = .{
                    .resource = upload.resource,
                    .format = upload.format,
                    .size = upload.size,
                };
                break;
            }
        }
        if (index == renderer.residency_count and renderer.residency_count < renderer.residencies.len) {
            renderer.residencies[renderer.residency_count] = .{
                .resource = upload.resource,
                .format = upload.format,
                .size = upload.size,
            };
            renderer.residency_count += 1;
        }
    }
}

// Padding follows the same accepted presentation cut, never an inferred cell
// color or a host theme. Reverse-screen applies to the default outside-cell fill.
fn paddingBackground(presentation: *const client.rich.Presentation) u32 {
    const color = if (presentation.reverse_screen) presentation.foreground else presentation.background;
    return @as(u32, color.r) | (@as(u32, color.g) << 8) | (@as(u32, color.b) << 16) | (@as(u32, color.a) << 24);
}

pub export fn howl_odin_bridge_render_background_rgba(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0xff211918;
    const renderer: *const Render = @ptrCast(@alignCast(value));
    return renderer.front.background_rgba;
}

pub export fn howl_odin_bridge_render_surface_width(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.front.surface.width;
}

pub export fn howl_odin_bridge_render_surface_height(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.front.surface.height;
}

pub export fn howl_odin_bridge_render_cell_width(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.cell_size.width;
}

pub export fn howl_odin_bridge_render_cell_height(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.cell_size.height;
}

pub export fn howl_odin_bridge_render_maximum_rows() u16 {
    return render.limits.maximum_rows;
}

pub export fn howl_odin_bridge_render_maximum_columns() u16 {
    return render.limits.maximum_columns;
}

pub export fn howl_odin_bridge_render_frame_revision(raw: ?*RenderHandle) u64 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.front.frame_revision;
}

pub export fn howl_odin_bridge_render_instance_revision(raw: ?*RenderHandle) u64 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.revision;
}

pub export fn howl_odin_bridge_render_history_offset(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_offset;
}

pub export fn howl_odin_bridge_render_history_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_count;
}

pub export fn howl_odin_bridge_render_history_row_base(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_row_base;
}

pub export fn howl_odin_bridge_render_alternate_screen(raw: ?*RenderHandle) u8 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return @intFromBool(begin.alternate_screen);
}

/// Projects selection against this renderer's accepted frame only. No Instance
/// request, allocation, text parsing, or endpoint mutation occurs while dragging.
pub export fn howl_odin_bridge_render_selection_span(
    raw: ?*RenderHandle,
    anchor_row: i32,
    anchor_column: u16,
    focus_row: i32,
    focus_column: u16,
    columns: u16,
    alternate_screen: u8,
    viewport_row: u16,
    first: *u16,
    last: *u16,
) u8 {
    first.* = 0;
    last.* = 0;
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    if (alternate_screen > 1 or viewport_row >= begin.rows or viewport_row >= renderer.front.selection_rows.len)
        return 0;
    const range = client.selection.Range{
        .anchor = .{ .row = anchor_row, .column = anchor_column },
        .focus = .{ .row = focus_row, .column = focus_column },
        .columns = columns,
        .alternate_screen = alternate_screen != 0,
    };
    const span = range.textSpan(&begin, viewport_row, renderer.front.selection_rows[viewport_row]) orelse return 0;
    first.* = span.start_column;
    last.* = span.end_column;
    return 1;
}

pub export fn howl_odin_bridge_render_upload_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.upload_count);
}

pub export fn howl_odin_bridge_render_removal_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.removal_count);
}

pub export fn howl_odin_bridge_render_command_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.command_count);
}

fn fillRenderResourceRef(resource: terminal_render.ResourceRef, output: *RenderResourceInfo) void {
    output.resource = @backingInt(resource.resource);
    output.generation = @backingInt(resource.generation);
}

fn fillRenderRemovalRef(resource: terminal_render.ResourceRef, output: *RenderRemovalInfo) void {
    output.resource = @backingInt(resource.resource);
    output.generation = @backingInt(resource.generation);
}

pub export fn howl_odin_bridge_render_upload_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderResourceInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.upload_count) return 2;
    if (index < renderer.frame_upload_count) {
        if (renderer.scratch.prepared_owner != renderer) return 3;
        const upload = renderer.scratch.frame_uploads[index];
        fillRenderResourceRef(upload.resource, output);
        output.pixel_count = upload.pixel_count;
        output.stride = upload.stride;
        output.width = upload.size.width;
        output.height = upload.size.height;
        output.format = @backingInt(upload.format);
        return 0;
    }
    const external_index = index - renderer.frame_upload_count;
    if (external_index >= renderer.external_upload_count) return 2;
    const upload = renderer.external_uploads[external_index];
    fillRenderResourceRef(upload.external.resource, output);
    output.pixel_count = upload.fetched.pixels.len;
    output.stride = upload.external.stride;
    output.width = upload.external.size.width;
    output.height = upload.external.size.height;
    output.format = @backingInt(upload.external.format);
    return 0;
}

pub export fn howl_odin_bridge_render_upload_copy(
    raw: ?*RenderHandle,
    index: u32,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.upload_count) return 2;
    if (index < renderer.frame_upload_count) {
        if (renderer.scratch.prepared_owner != renderer) return 3;
        const upload = renderer.scratch.frame_uploads[index];
        if (upload.pixel_offset + upload.pixel_count > renderer.pixel_count) return 3;
        if (output_capacity < upload.pixel_count) return 4;
        @memcpy(
            output_ptr[0..upload.pixel_count],
            renderer.scratch.frame_pixels[upload.pixel_offset .. upload.pixel_offset + upload.pixel_count],
        );
        output_len.* = upload.pixel_count;
        return 0;
    }
    const external_index = index - renderer.frame_upload_count;
    if (external_index >= renderer.external_upload_count) return 2;
    const pixels = renderer.external_uploads[external_index].fetched.pixels;
    if (output_capacity < pixels.len) return 4;
    @memcpy(output_ptr[0..pixels.len], pixels);
    output_len.* = pixels.len;
    return 0;
}

pub export fn howl_odin_bridge_render_removal_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderRemovalInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.removal_count) return 2;
    if (renderer.scratch.prepared_owner != renderer) return 3;
    fillRenderRemovalRef(renderer.scratch.frame_removals[index], output);
    return 0;
}

fn colorBits(color: terminal_render.Color) u32 {
    return @as(u32, color.r) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.a) << 24);
}

fn fillCommandResource(output: *RenderCommandInfo, resource: terminal_render.ResourceView) void {
    output.resource = @backingInt(resource.resource.resource);
    output.generation = @backingInt(resource.resource.generation);
    output.format = @backingInt(resource.format);
    output.resource_width = resource.size.width;
    output.resource_height = resource.size.height;
    const source = resource.source orelse terminal_render.SourceRect{
        .x = 0,
        .y = 0,
        .width = resource.size.width,
        .height = resource.size.height,
    };
    output.source_x = source.x;
    output.source_y = source.y;
    output.source_width = source.width;
    output.source_height = source.height;
}

fn fillRectFields(
    destination: terminal_render.Rect,
    clip: terminal_render.Rect,
    output: *RenderCommandInfo,
) void {
    output.destination_x = destination.x;
    output.destination_y = destination.y;
    output.destination_width = destination.width;
    output.destination_height = destination.height;
    output.clip_x = clip.x;
    output.clip_y = clip.y;
    output.clip_width = clip.width;
    output.clip_height = clip.height;
}

fn fillRenderCommandInfo(
    command: terminal_render.Command,
    output: *RenderCommandInfo,
) void {
    output.* = .{};
    switch (command) {
        .solid => |solid| {
            output.tag = 0;
            output.color_rgba = colorBits(solid.color);
            fillRectFields(solid.rect, solid.rect, output);
        },
        .alpha_mask => |mask| {
            output.tag = 1;
            output.color_rgba = colorBits(mask.color);
            output.cursor_component = @intFromBool(mask.cursor_component);
            fillRectFields(mask.destination, mask.clip, output);
            fillCommandResource(output, mask.resource);
        },
        .rgba => |rgba| {
            output.tag = 2;
            fillRectFields(rgba.destination, rgba.clip, output);
            fillCommandResource(output, rgba.resource);
        },
    }
}

pub export fn howl_odin_bridge_render_command_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderCommandInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.command_count) return 2;
    if (renderer.scratch.prepared_owner != renderer) return 3;
    fillRenderCommandInfo(renderer.scratch.frame_commands[index], output);
    return 0;
}

pub export fn howl_odin_bridge_render_copy_error(
    raw: ?*RenderHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, renderer.last_error_len);
    @memcpy(output_ptr[0..count], renderer.last_error[0..count]);
    output_len.* = count;
}

pub export fn howl_odin_bridge_render_resource_info_size() u32 {
    return @sizeOf(RenderResourceInfo);
}

pub export fn howl_odin_bridge_render_removal_info_size() u32 {
    return @sizeOf(RenderRemovalInfo);
}

pub export fn howl_odin_bridge_render_command_info_size() u32 {
    return @sizeOf(RenderCommandInfo);
}

pub export fn howl_odin_bridge_search_match_info_size() u32 {
    return @sizeOf(SearchMatchInfo);
}

pub export fn howl_odin_bridge_selection_range_info_size() u32 {
    return @sizeOf(SelectionRangeInfo);
}

pub export fn howl_odin_bridge_interaction_state_info_size() u32 {
    return @sizeOf(InteractionStateInfo);
}

const Handle = opaque {};
const ConsequenceHandle = opaque {};

pub const ConsequenceInfo = extern struct {
    terminal_revision: u64 = 0,
    authority_client_id: u64 = 0,
    generation: u64 = 0,
    payload_len: u32 = 0,
    kind: u8 = 0,
    reply_required: u8 = 0,
    _reserved: [2]u8 = @splat(0),
    metadata: [protocol.consequence_metadata_bytes]u8 = @splat(0),
};
comptime {
    if (@sizeOf(ConsequenceInfo) != protocol.payload_bytes.consequence_begin)
        @compileError("Odin consequence info must stay one fixed begin-sized record");
}

fn packedNibbleSignature(comptime values: []const u8) u64 {
    if (values.len > 14) @compileError("packed ABI signature exceeds u64");
    var result = @as(u64, values.len) << 56;
    inline for (values, 0..) |value, index| {
        if (value > 0x0f) @compileError("packed ABI signature value exceeds nibble");
        result |= @as(u64, value) << @intCast(index * 4);
    }
    return result;
}

const consequence_kind_values = [_]u8{
    @backingInt(protocol.ConsequenceKind.none),
    @backingInt(protocol.ConsequenceKind.clipboard),
    @backingInt(protocol.ConsequenceKind.notification),
    @backingInt(protocol.ConsequenceKind.pointer_shape),
    @backingInt(protocol.ConsequenceKind.file_transfer),
    @backingInt(protocol.ConsequenceKind.drag_drop),
    @backingInt(protocol.ConsequenceKind.container),
    @backingInt(protocol.ConsequenceKind.color_preference),
    @backingInt(protocol.ConsequenceKind.media_copy),
    @backingInt(protocol.ConsequenceKind.bell),
    @backingInt(protocol.ConsequenceKind.legacy_control),
    @backingInt(protocol.ConsequenceKind.dcs),
    @backingInt(protocol.ConsequenceKind.string_control),
};
const consequence_reply_values = [_]u8{
    @backingInt(protocol.ConsequenceReplyKind.clipboard),
    @backingInt(protocol.ConsequenceReplyKind.pointer_shape),
    @backingInt(protocol.ConsequenceReplyKind.color_preference),
    @backingInt(protocol.ConsequenceReplyKind.container_state),
    @backingInt(protocol.ConsequenceReplyKind.container_position),
    @backingInt(protocol.ConsequenceReplyKind.container_screen_cells),
    @backingInt(protocol.ConsequenceReplyKind.container_icon_title),
    @backingInt(protocol.ConsequenceReplyKind.container_decline),
};
const consequence_kind_abi_signature = packedNibbleSignature(&consequence_kind_values);
const consequence_reply_abi_signature = packedNibbleSignature(&consequence_reply_values);

comptime {
    if (@typeInfo(protocol.ConsequenceKind).@"enum".field_names.len != consequence_kind_values.len)
        @compileError("update Odin consequence kind ABI signature");
    if (@typeInfo(protocol.ConsequenceReplyKind).@"enum".field_names.len != consequence_reply_values.len)
        @compileError("update Odin consequence reply ABI signature");
}

const ConsequenceBridge = struct {
    allocator: std.mem.Allocator,
    runtime: ?*Runtime = null,
    connection: client.Connection,
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *ConsequenceBridge) void {
        self.last_error_len = 0;
    }

    fn setError(self: *ConsequenceBridge, stage: []const u8, failure_name: []const u8) void {
        const rendered = std.fmt.bufPrint(
            &self.last_error,
            "{s}:{s}",
            .{ stage, failure_name },
        ) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = rendered.len;
    }
};

fn currentProcessEnviron() std.process.Environ {
    if (comptime builtin.os.tag == .windows) return .{ .block = .global };
    return posixProcessEnviron();
}

fn posixProcessEnviron() std.process.Environ {
    const c_environ = std.c.environ;
    var count: usize = 0;
    while (c_environ[count] != null) : (count += 1) {}
    const block: std.process.Environ.Block = .{
        .slice = c_environ[0..count :null],
    };
    return .{ .block = block };
}

const Bridge = struct {
    allocator: std.mem.Allocator,
    runtime: ?*Runtime = null,
    connection: client.Connection,
    raw_observation: bool,
    live_raw_cache: client.rich.RawCache,
    live_view: ?client.rich.View = null,
    rich_loan_active: bool = false,
    rich_loan_taken: bool = false,
    last_begin: ?protocol.SnapshotBegin = null,
    reusable_view: ?*client.view.Snapshot = null,
    display_title: [protocol.properties.maximum_field_bytes]u8 = undefined,
    display_title_len: usize = 0,
    task_progress: protocol.properties.Progress = .{},
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *Bridge) void {
        self.last_error_len = 0;
    }

    fn setError(self: *Bridge, stage: []const u8, failure_name: []const u8) void {
        const rendered = std.fmt.bufPrint(
            &self.last_error,
            "{s}:{s}",
            .{ stage, failure_name },
        ) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = rendered.len;
    }
};

const NativeTextWriter = struct {
    bytes: []u8,
    used: usize = 0,
    truncated: bool = false,

    fn byte(self: *NativeTextWriter, value: u8) bool {
        if (self.used == self.bytes.len) {
            self.truncated = true;
            return false;
        }
        self.bytes[self.used] = value;
        self.used += 1;
        return true;
    }

    fn scalar(self: *NativeTextWriter, value: u32) bool {
        var encoded: [4]u8 = undefined;
        const count = std.unicode.utf8Encode(
            @intCast(value),
            &encoded,
        ) catch {
            self.truncated = true;
            return false;
        };
        if (count > self.bytes.len - self.used) {
            self.truncated = true;
            return false;
        }
        @memcpy(
            self.bytes[self.used .. self.used + count],
            encoded[0..count],
        );
        self.used += count;
        return true;
    }
};

fn fillNativeTerminalInfo(
    owner: *const NativeTerminal,
    history_offset: u32,
    output: *NativeTerminalInfo,
) void {
    const observation = native_instance.terminal(owner.value);
    const view = observation.semanticView(history_offset);
    const interaction = observation.interactionState();
    const progress = observation.taskProgress();
    output.* = .{
        .revision = observation.semanticSequence(),
        .terminal_revision = observation.semanticSequence(),
        .history_count = view.history_count,
        .history_row_base = view.history_row_base,
        .interaction_flags = (if (interaction.alternate_scroll)
            interaction_info_flags.alternate_scroll
        else
            0) |
            (if (interaction.focus_reporting)
                interaction_info_flags.focus_reporting
            else
                0),
        .rows = view.rows,
        .columns = view.cols,
        .cursor_row = view.cursor_row,
        .cursor_column = view.cursor_col,
        .task_progress = (@as(u16, @backingInt(progress.kind)) << 8) | progress.value,
        .cursor_shape = @backingInt(view.cursor_shape),
        .cursor_visible = @intFromBool(view.cursor_visible),
        .alternate_screen = @intFromBool(view.is_alternate_screen),
        .stream_closed = @intFromBool(owner.stream_closed),
        .child_exited = @intFromBool(owner.child_exit != null),
        .mouse_tracking = @backingInt(interaction.mouse_tracking),
        .mouse_protocol = @backingInt(interaction.mouse_protocol),
        .pointer_mode = @intCast(interaction.pointer_mode),
    };
}

pub export fn howl_odin_bridge_version() u32 {
    return 15;
}

test "Odin bridge version tracks native local ownership ABI" {
    try std.testing.expectEqual(@as(u32, 15), howl_odin_bridge_version());
}

pub export fn howl_odin_bridge_create(
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
    route_kind: u8,
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*Handle {
    diagnostic_len.* = 0;
    const target = targetFromAbi(route_kind, endpoint_ptr[0..endpoint_len], server_id, session_id, instance_id) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_target");
        return null;
    };

    const allocator = std.heap.c_allocator;
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = connectForHost(
        runtime,
        interrupt,
        target,
        &connect_diagnostic,
    ) catch |failure| {
        writeConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
            connect_diagnostic,
        );
        return null;
    };
    defer if (!accepted) connection.deinit();

    const bridge = allocator.create(Bridge) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    bridge.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connection,
        .raw_observation = rawObservationTarget(target),
        .live_raw_cache = client.rich.RawCache.init(allocator),
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(bridge);
}

pub export fn howl_odin_bridge_destroy(raw: ?*Handle) void {
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const allocator = bridge.allocator;
    if (bridge.reusable_view) |view| client.view.deinit(view);
    bridge.live_raw_cache.deinit();
    bridge.connection.deinit();
    releaseRuntime(bridge.runtime);
    allocator.destroy(bridge);
}

/// Requests a complete view and publishes compact metadata. The existing shared
/// immutable projection may be taken once for rendering when it has no external
/// image dependencies. Otherwise its observing connection's pin stays private.
pub export fn howl_odin_bridge_snapshot(
    raw: ?*Handle,
    after_revision: u64,
    history_offset: u32,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (bridge.rich_loan_active) {
        bridge.setError("observe_loan", "active");
        return 4;
    }
    bridge.live_view = null;
    bridge.rich_loan_taken = false;
    if (bridge.reusable_view) |view| client.view.deinit(view);
    bridge.reusable_view = null;

    var owned_rich: ?client.rich.Snapshot = null;
    defer if (owned_rich) |*snapshot_value| snapshot_value.deinit();
    const use_live_delta = history_offset == 0;
    if (use_live_delta) {
        bridge.live_raw_cache.sendDeltaRequest(
            &bridge.connection,
            after_revision,
            0,
        ) catch |failure| switch (failure) {
            // A caller may legitimately return from history or another
            // complete-observation path with a revision newer than this live
            // cache. Preserve the caller's after-revision wait with one full raw
            // response; RawCache receives that same response and adopts it as
            // the next live delta baseline.
            error.DeltaBaselineMismatch => client.rich.sendRawRequest(
                &bridge.connection,
                after_revision,
                0,
            ) catch |resync_failure| {
                bridge.setError("observe_resync", @errorName(resync_failure));
                return 2;
            },
            else => {
                bridge.setError("observe_arm", @errorName(failure));
                return 2;
            },
        };
    }
    const rich_view: client.rich.View = if (use_live_delta)
        bridge.live_raw_cache.receive(&bridge.connection) catch |failure| {
            bridge.setError("observe", @errorName(failure));
            return 2;
        }
    else blk: {
        owned_rich = requestObservation(
            &bridge.connection,
            bridge.allocator,
            after_revision,
            history_offset,
            bridge.raw_observation,
        ) catch |failure| {
            bridge.setError("observe", @errorName(failure));
            return 2;
        };
        break :blk owned_rich.?.view();
    };

    if (use_live_delta and rich_view.begin.history_offset == 0 and rich_view.graphics.images.len == 0) {
        bridge.live_view = rich_view;
        bridge.rich_loan_active = true;
        bridge.last_begin = rich_view.begin;
        bridge.display_title_len = writeDisplayTitle(rich_view.properties.title orelse "", &bridge.display_title);
        bridge.task_progress = rich_view.properties.progress;
        return 0;
    }

    const projected = client.view.projectView(bridge.allocator, &rich_view) catch |failure| {
        bridge.setError("project", @errorName(failure));
        return 3;
    };
    if (standaloneLiveView(projected)) {
        bridge.reusable_view = projected;
    }
    defer if (bridge.reusable_view == null) client.view.deinit(projected);

    bridge.last_begin = client.view.begin(projected).*;
    const properties = client.view.properties(projected);
    bridge.display_title_len = writeDisplayTitle(properties.title orelse "", &bridge.display_title);
    bridge.task_progress = properties.progress;
    return 0;
}

// No image bytes are fetched or eagerly cached to make a cut transferable.
// Image-bearing and historical projections retain the original render channel.
fn standaloneLiveView(view: *const client.view.Snapshot) bool {
    return client.view.begin(view).history_offset == 0 and client.view.graphics(view).images.len == 0;
}

/// Moves the existing allocation out. It owns no connection or runtime borrow,
/// survives further observation/bridge teardown, and must be destroyed once.
pub export fn howl_odin_bridge_snapshot_take_rich_loan(raw: ?*Handle) ?*Handle {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    if (!bridge.rich_loan_active or bridge.rich_loan_taken or bridge.live_view == null) return null;
    bridge.rich_loan_taken = true;
    return raw;
}

pub export fn howl_odin_bridge_snapshot_release_rich_loan(raw: ?*Handle) void {
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.live_view = null;
    bridge.rich_loan_active = false;
    bridge.rich_loan_taken = false;
}

pub export fn howl_odin_bridge_snapshot_take_view(raw: ?*Handle) ?*client.view.Snapshot {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const view = bridge.reusable_view;
    bridge.reusable_view = null;
    return view;
}

pub export fn howl_odin_bridge_view_destroy(view: ?*client.view.Snapshot) void {
    if (view) |value| client.view.deinit(value);
}

// Property bytes are untrusted labels, not terminal input or process identity.
// Reject invalid UTF-8 and replace control/bidi formatting with ordinary spaces.
fn writeDisplayTitle(source: []const u8, output: []u8) usize {
    if (!std.unicode.utf8ValidateSlice(source)) return 0;
    var input: usize = 0;
    var used: usize = 0;
    while (input < source.len) {
        const width = std.unicode.utf8ByteSequenceLength(source[input]) catch unreachable;
        const codepoint = std.unicode.utf8Decode(source[input..][0..width]) catch unreachable;
        const control = codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f) or
            (codepoint >= 0x2028 and codepoint <= 0x202e) or
            (codepoint >= 0x2066 and codepoint <= 0x2069);
        const needed: usize = if (control) 1 else width;
        if (needed > output.len - used) break;
        if (control) output[used] = ' ' else @memcpy(output[used..][0..needed], source[input..][0..width]);
        used += needed;
        input += width;
    }
    return used;
}

pub export fn howl_odin_bridge_snapshot_title(raw: ?*Handle, output: [*]u8, capacity: usize) usize {
    const value = raw orelse return 0;
    const bridge: *const Bridge = @ptrCast(@alignCast(value));
    return writeDisplayTitle(bridge.display_title[0..bridge.display_title_len], output[0..capacity]);
}

pub export fn howl_odin_bridge_snapshot_progress(raw: ?*Handle) u16 {
    const value = raw orelse return 0;
    const bridge: *const Bridge = @ptrCast(@alignCast(value));
    return (@as(u16, @backingInt(bridge.task_progress.kind)) << 8) | bridge.task_progress.value;
}

test "desktop property labels never leak controls or partial UTF-8 to chrome" {
    var output: [64]u8 = undefined;
    const length = writeDisplayTitle("hi\x00\x1b\nλ\u{202e}", &output);
    try std.testing.expectEqualStrings("hi   λ ", output[0..length]);
    try std.testing.expectEqual(@as(usize, 0), writeDisplayTitle(&.{0xff}, &output));
    try std.testing.expectEqual(@as(usize, 0), writeDisplayTitle("λ", output[0..1]));
    try std.testing.expectEqual(@as(usize, 2), writeDisplayTitle("λx", output[0..2]));
    try std.testing.expectEqualStrings("λ", output[0..2]);
}

pub export fn howl_odin_bridge_search_find(
    raw: ?*Handle,
    query_ptr: [*]const u8,
    query_len: usize,
    reverse_value: u8,
    origin_present: u8,
    origin_row: i32,
    origin_column: u16,
    output: *SearchMatchInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (query_len == 0 or query_len > maximum_search_query_bytes or
        reverse_value > 1 or origin_present > 1)
    {
        bridge.setError("search", "invalid_arguments");
        return 2;
    }
    const query = query_ptr[0..query_len];
    if (!std.unicode.utf8ValidateSlice(query)) {
        bridge.setError("search", "invalid_utf8");
        return 2;
    }
    const reverse = reverse_value != 0;

    var initial_rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        0,
    ) catch |failure| {
        bridge.setError("search_observe", @errorName(failure));
        return 3;
    };
    defer initial_rich.deinit();
    const initial = client.view.project(bridge.allocator, &initial_rich) catch |failure| {
        bridge.setError("search_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(initial);
    const initial_begin = client.view.begin(initial).*;
    output.cut_revision = initial_begin.revision;
    output.columns = initial_begin.columns;
    output.alternate_screen = @intFromBool(initial_begin.alternate_screen);
    output.complete = 1;
    output.scanned_snapshots = 1;
    if (initial_begin.rows == 0 or initial_begin.columns == 0) return 0;
    if (origin_present != 0 and origin_column >= initial_begin.columns) {
        bridge.setError("search", "origin_context_changed");
        return 4;
    }

    const cut_first: i64 = if (initial_begin.alternate_screen)
        0
    else
        initial_begin.history_row_base;
    const cut_last_u64: u64 = if (initial_begin.alternate_screen)
        initial_begin.rows - 1
    else
        @as(u64, initial_begin.history_row_base) + initial_begin.history_count + initial_begin.rows - 1;
    if (cut_last_u64 > std.math.maxInt(i32)) {
        bridge.setError("search", "row_identity_overflow");
        return 4;
    }
    const cut_last: i64 = @intCast(cut_last_u64);

    var start_row: i64 = if (origin_present != 0) origin_row else if (reverse) cut_last else cut_first;
    var start_column: u16 = if (origin_present != 0) origin_column else if (reverse) initial_begin.columns - 1 else 0;
    if (origin_present != 0) {
        if (reverse) {
            if (start_column == 0) {
                start_row -= 1;
                start_column = initial_begin.columns - 1;
            } else {
                start_column -= 1;
            }
        } else if (start_column + 1 >= initial_begin.columns) {
            start_row += 1;
            start_column = 0;
        } else {
            start_column += 1;
        }
    }
    if (start_row < cut_first) {
        if (reverse) return 0;
        start_row = cut_first;
        start_column = 0;
    }
    if (start_row > cut_last) {
        if (!reverse) return 0;
        start_row = cut_last;
        start_column = initial_begin.columns - 1;
    }

    if (initial_begin.alternate_screen) {
        return searchProjectedCut(
            bridge,
            initial,
            query,
            reverse,
            start_row,
            start_column,
            cut_first,
            cut_last,
            output,
        );
    }

    var current_row = start_row;
    var current_column = start_column;
    var metadata = initial_begin;
    var pages: usize = 0;
    const maximum_pages = @as(usize, initial_begin.history_count) / initial_begin.rows + 4;
    while (pages < maximum_pages and current_row >= cut_first and current_row <= cut_last) : (pages += 1) {
        if (metadata.columns != initial_begin.columns or metadata.alternate_screen) {
            bridge.setError("search", "context_changed");
            return 4;
        }
        const current_first: i64 = metadata.history_row_base;
        if (reverse and current_row < current_first) return 0;
        if (!reverse and current_row < current_first) {
            output.complete = 0;
            current_row = @min(cut_last, current_first + searchGuardRows(metadata.rows));
            current_column = 0;
            if (current_row > cut_last) return 0;
        }

        var retry: usize = 0;
        while (retry < maximum_search_retries) : (retry += 1) {
            const retry_first: i64 = metadata.history_row_base;
            const retry_live_top: i64 = retry_first + metadata.history_count;
            if (reverse and current_row < retry_first) return 0;
            if (!reverse and current_row < retry_first) {
                output.complete = 0;
                current_row = @min(cut_last, retry_first + searchGuardRows(metadata.rows));
                current_column = 0;
                if (current_row > cut_last) return 0;
            }
            const guard = searchGuardRows(metadata.rows);
            const desired_top = if (reverse)
                @max(retry_first, current_row - (@as(i64, metadata.rows) - 1 - guard))
            else
                @max(retry_first, current_row - guard);
            const requested_offset: u32 = if (desired_top >= retry_live_top)
                0
            else
                @intCast(@min(@as(i64, metadata.history_count), retry_live_top - desired_top));
            var page_rich = client.rich.request(
                &bridge.connection,
                bridge.allocator,
                0,
                requested_offset,
            ) catch |failure| {
                bridge.setError("search_observe", @errorName(failure));
                return 3;
            };
            defer page_rich.deinit();
            const page = client.view.project(bridge.allocator, &page_rich) catch |failure| {
                bridge.setError("search_project", @errorName(failure));
                return 3;
            };
            defer client.view.deinit(page);
            output.scanned_snapshots += 1;
            const begin = client.view.begin(page).*;
            metadata = begin;
            if (begin.columns != initial_begin.columns or begin.alternate_screen) {
                bridge.setError("search", "context_changed");
                return 4;
            }
            const actual_top: i64 = @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
            const actual_last = actual_top + begin.rows - 1;
            if (current_row < begin.history_row_base) {
                if (reverse) return 0;
                output.complete = 0;
                current_row = @min(cut_last, @as(i64, begin.history_row_base) + searchGuardRows(begin.rows));
                current_column = 0;
                metadata = begin;
                continue;
            }
            if (current_row < actual_top or current_row > actual_last) {
                if (retry + 1 == maximum_search_retries) {
                    output.complete = 0;
                    return 0;
                }
                continue;
            }

            const search_code = searchProjectedCut(
                bridge,
                page,
                query,
                reverse,
                current_row,
                current_column,
                @max(cut_first, actual_top),
                @min(cut_last, actual_last),
                output,
            );
            if (search_code != 0) return search_code;
            if (output.found != 0) return 0;

            if (reverse) {
                current_row = @max(cut_first, actual_top) - 1;
                current_column = initial_begin.columns - 1;
            } else {
                current_row = @min(cut_last, actual_last) + 1;
                current_column = 0;
            }
            break;
        }
    }
    return 0;
}

fn searchGuardRows(rows: u16) i64 {
    if (rows <= 4) return 1;
    return @max(@as(i64, 2), @divTrunc(@as(i64, rows), 4));
}

fn searchProjectedCut(
    bridge: *Bridge,
    snapshot: *const client.view.Snapshot,
    query: []const u8,
    reverse: bool,
    start_row: i64,
    start_column: u16,
    first_row: i64,
    last_row: i64,
    output: *SearchMatchInfo,
) i32 {
    const begin = client.view.begin(snapshot);
    const top: i64 = if (begin.alternate_screen)
        0
    else
        @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
    if (first_row > last_row or start_row < first_row or start_row > last_row) return 0;

    if (reverse) {
        var canonical_row = start_row;
        while (canonical_row >= first_row) : (canonical_row -= 1) {
            const viewport_row: u16 = @intCast(canonical_row - top);
            const bound = if (canonical_row == start_row) start_column else begin.columns - 1;
            const found = client.search.rowFrom(
                snapshot,
                bridge.allocator,
                query,
                viewport_row,
                bound,
                true,
            ) catch |failure| {
                bridge.setError("search_match", @errorName(failure));
                return 4;
            };
            if (found) |match| {
                return fillSearchMatch(match, output);
            }
        }
        return 0;
    }

    var canonical_row = start_row;
    while (canonical_row <= last_row) : (canonical_row += 1) {
        const viewport_row: u16 = @intCast(canonical_row - top);
        const bound = if (canonical_row == start_row) start_column else 0;
        const found = client.search.rowFrom(
            snapshot,
            bridge.allocator,
            query,
            viewport_row,
            bound,
            false,
        ) catch |failure| {
            bridge.setError("search_match", @errorName(failure));
            return 4;
        };
        if (found) |match| {
            return fillSearchMatch(match, output);
        }
    }
    return 0;
}

fn fillSearchMatch(match: client.search.Match, output: *SearchMatchInfo) i32 {
    const ordered = match.range.ordered();
    output.found = 1;
    output.row = ordered.start.row;
    output.start_column = match.start_column;
    output.end_column = match.end_column;
    output.columns = match.range.columns;
    output.alternate_screen = @intFromBool(match.range.alternate_screen);
    return 0;
}

pub export fn howl_odin_bridge_send_text(
    raw: ?*Handle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.actions.committedText(&bridge.connection, bytes_ptr[0..bytes_len]) catch |failure| {
        bridge.setError("text", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_paste(
    raw: ?*Handle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.actions.paste(&bridge.connection, bytes_ptr[0..bytes_len]) catch |failure| {
        bridge.setError("paste", @errorName(failure));
        return 2;
    };
    return 0;
}

fn selectionViewportRow(begin: *const protocol.SnapshotBegin, stable_row: i32) ?u16 {
    if (begin.rows == 0) return null;
    if (begin.alternate_screen) {
        if (stable_row < 0 or stable_row >= begin.rows) return null;
        return @intCast(stable_row);
    }
    if (begin.history_offset > begin.history_count) return null;
    const top: i64 = @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
    const relative = @as(i64, stable_row) - top;
    if (relative < 0 or relative >= begin.rows) return null;
    return @intCast(relative);
}

fn hyperlinkUriAt(
    snapshot: *const client.view.Snapshot,
    viewport_row: u16,
    column: u16,
) ?[]const u8 {
    const rows = client.view.rows(snapshot);
    if (viewport_row >= rows.len) return null;
    const row = rows[viewport_row];
    if (column >= row.cell_count) return null;
    const cells = client.view.cells(snapshot);
    const cell_index = std.math.add(usize, row.cell_offset, column) catch return null;
    if (cell_index >= cells.len) return null;
    const link_id = cells[cell_index].link_id;
    if (link_id == 0) return null;
    const links = client.view.hyperlinks(snapshot);
    const uris = client.view.uris(snapshot);
    for (links) |link| {
        if (link.link_id != link_id) continue;
        const end = std.math.add(usize, link.uri_offset, link.uri_len) catch return null;
        if (end > uris.len) return null;
        return uris[link.uri_offset..end];
    }
    return null;
}

/// Copies the exact OSC 8 URI attached to one currently displayed canonical
/// cell. The stable target row must still name the requested history window;
/// output length zero means the cell has no canonical hyperlink.
pub export fn howl_odin_bridge_hyperlink_copy(
    raw: ?*Handle,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (expected_columns == 0 or expected_alternate_screen > 1) {
        bridge.setError("hyperlink", "invalid_arguments");
        return 2;
    }
    var rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        history_offset,
    ) catch |failure| {
        bridge.setError("hyperlink_observe", @errorName(failure));
        return 3;
    };
    defer rich.deinit();
    const snapshot = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("hyperlink_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(snapshot);

    const begin = client.view.begin(snapshot);
    const expected_alternate = expected_alternate_screen != 0;
    if (begin.columns != expected_columns or begin.alternate_screen != expected_alternate) {
        bridge.setError("hyperlink", "context_changed");
        return query_declined;
    }
    const viewport_row = selectionViewportRow(begin, target_row) orelse {
        bridge.setError("hyperlink", "target_moved");
        return query_declined;
    };
    if (target_column >= begin.columns) {
        bridge.setError("hyperlink", "target_column");
        return query_declined;
    }
    const uri = hyperlinkUriAt(snapshot, viewport_row, target_column) orelse return 0;
    if (uri.len > output_capacity) {
        bridge.setError("hyperlink", "short_buffer");
        return query_declined;
    }
    @memcpy(output_ptr[0..uri.len], uri);
    output_len.* = uri.len;
    return 0;
}

/// Expands one currently displayed canonical cell into either its contiguous
/// non-space word (kind=1) or its current projected visual row (kind=2).
/// The stable target row must still be visible in the requested history window;
/// a moving-output race is rejected rather than retargeted.
pub export fn howl_odin_bridge_selection_expand(
    raw: ?*Handle,
    kind: u8,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output: *SelectionRangeInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if ((kind != 1 and kind != 2) or expected_columns == 0 or expected_alternate_screen > 1) {
        bridge.setError("selection_expand", "invalid_arguments");
        return 2;
    }

    var rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        history_offset,
    ) catch |failure| {
        bridge.setError("selection_expand_observe", @errorName(failure));
        return 3;
    };
    defer rich.deinit();
    const snapshot = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("selection_expand_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(snapshot);

    const begin = client.view.begin(snapshot);
    const expected_alternate = expected_alternate_screen != 0;
    if (begin.columns != expected_columns or begin.alternate_screen != expected_alternate) {
        bridge.setError("selection_expand", "context_changed");
        return query_declined;
    }
    const viewport_row = selectionViewportRow(begin, target_row) orelse {
        bridge.setError("selection_expand", "target_moved");
        return query_declined;
    };
    if (target_column >= begin.columns) {
        bridge.setError("selection_expand", "target_column");
        return query_declined;
    }

    const maybe_range = if (kind == 1)
        client.selection.word(snapshot, viewport_row, target_column)
    else
        client.selection.visualRow(snapshot, viewport_row);
    const range = maybe_range catch |failure| {
        bridge.setError("selection_expand", @errorName(failure));
        return query_declined;
    } orelse return 0;
    const ordered = range.ordered();

    var end_column = ordered.end.column;
    const end_viewport_row = selectionViewportRow(begin, ordered.end.row) orelse {
        bridge.setError("selection_expand", "expanded_end_not_visible");
        return query_declined;
    };
    if (client.selection.visualSpan(snapshot, range, end_viewport_row)) |span| {
        end_column = span.end_column;
    }

    output.* = .{
        .start_row = ordered.start.row,
        .end_row = ordered.end.row,
        .start_column = ordered.start.column,
        .end_column = end_column,
        .columns = range.columns,
        .found = 1,
        .alternate_screen = @intFromBool(range.alternate_screen),
    };
    return 0;
}

pub export fn howl_odin_bridge_selection_extract(
    raw: ?*Handle,
    start_row: i32,
    start_column: u16,
    end_row: i32,
    end_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (expected_columns == 0 or expected_alternate_screen > 1) {
        bridge.setError("selection_context", "invalid_expected_context");
        return 3;
    }
    const range = client.selection.Range{
        .anchor = .{ .row = start_row, .column = start_column },
        .focus = .{ .row = end_row, .column = end_column },
        .columns = expected_columns,
        .alternate_screen = expected_alternate_screen != 0,
    };
    const text = client.selection.extract(
        &bridge.connection,
        bridge.allocator,
        range,
    ) catch |failure| {
        bridge.setError("selection_extract", @errorName(failure));
        return if (failure == error.SelectionRejected) query_declined else 4;
    };
    defer bridge.allocator.free(text);
    if (text.len > output_capacity) {
        bridge.setError("selection_extract", "output_too_small");
        return query_declined;
    }
    @memcpy(output_ptr[0..text.len], text);
    output_len.* = text.len;
    return 0;
}

pub export fn howl_odin_bridge_send_named_key(
    raw: ?*Handle,
    key_value: u8,
    action_value: u8,
    modifiers: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0) return 3;
    const key = std.enums.fromInt(protocol.InputKeyName, key_value) orelse return 3;
    const action = std.enums.fromInt(protocol.InputKeyAction, action_value) orelse return 3;
    client.actions.namedKey(&bridge.connection, key, action, modifiers) catch |failure| {
        bridge.setError("key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_unicode_key(
    raw: ?*Handle,
    scalar: u32,
    action_value: u8,
    modifiers: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0) return 3;
    const action = std.enums.fromInt(protocol.InputKeyAction, action_value) orelse return 3;
    client.actions.unicodeKey(&bridge.connection, scalar, action, modifiers) catch |failure| {
        bridge.setError("unicode_key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_interaction_state(
    raw: ?*Handle,
    output: *InteractionStateInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const state = client.state.get(&bridge.connection) catch |failure| {
        bridge.setError("interaction_state", @errorName(failure));
        return 2;
    };
    var flags: u32 = 0;
    if (state.alternate_scroll) flags |= interaction_info_flags.alternate_scroll;
    if (state.focus_reporting) flags |= interaction_info_flags.focus_reporting;
    output.* = .{
        .terminal_revision = state.terminal_revision,
        .flags = flags,
        .mouse_tracking = @backingInt(state.mouse_tracking),
        .mouse_protocol = @backingInt(state.mouse_protocol),
        .pointer_mode = state.pointer_mode,
    };
    return 0;
}

pub export fn howl_odin_bridge_send_mouse(
    raw: ?*Handle,
    kind_value: u8,
    button_value: u8,
    modifiers: u8,
    buttons_down: u8,
    row: i32,
    column: u16,
    pixels_present: u8,
    pixel_x: u32,
    pixel_y: u32,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0 or
        pixels_present > 1)
        return 3;
    const kind = std.enums.fromInt(protocol.InputMouseKind, kind_value) orelse return 3;
    const button = std.enums.fromInt(protocol.InputMouseButton, button_value) orelse return 3;
    client.actions.mouse(&bridge.connection, .{
        .kind = kind,
        .button = button,
        .modifiers = modifiers,
        .buttons_down = buttons_down,
        .row = row,
        .column = column,
        .pixel_x = if (pixels_present != 0) pixel_x else null,
        .pixel_y = if (pixels_present != 0) pixel_y else null,
    }) catch |failure| {
        bridge.setError("mouse", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_focus(
    raw: ?*Handle,
    focus_value: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const focus = std.enums.fromInt(protocol.InputFocus, focus_value) orelse return 3;
    client.actions.focus(&bridge.connection, focus) catch |failure| {
        bridge.setError("focus", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_resize(
    raw: ?*Handle,
    rows: u16,
    columns: u16,
    cell_width: u16,
    cell_height: u16,
    claim: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (claim > 1) return 3;
    const geometry: protocol.Resize = .{
        .rows = rows,
        .columns = columns,
        .cell_pixel_width = cell_width,
        .cell_pixel_height = cell_height,
    };
    const outcome = if (claim == 1)
        client.actions.resizeGeometry(&bridge.connection, geometry)
    else
        client.actions.resizeGeometryOwned(&bridge.connection, geometry);
    outcome catch |failure| {
        bridge.setError("resize", @errorName(failure));
        return switch (failure) {
            error.NotGeometryLeader => 7,
            error.ServerRejected => 8,
            else => 2,
        };
    };
    return 0;
}

pub export fn howl_odin_bridge_copy_error(
    raw: ?*Handle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, bridge.last_error_len);
    @memcpy(output_ptr[0..count], bridge.last_error[0..count]);
    output_len.* = count;
}

pub export fn howl_odin_bridge_revision(raw: ?*Handle) u64 {
    return if (lastBegin(raw)) |begin| begin.revision else 0;
}

pub export fn howl_odin_bridge_terminal_revision(raw: ?*Handle) u64 {
    return if (lastBegin(raw)) |begin| begin.terminal_revision else 0;
}

pub export fn howl_odin_bridge_rows(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.rows else 0;
}

pub export fn howl_odin_bridge_columns(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.columns else 0;
}

pub export fn howl_odin_bridge_cursor_row(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.cursor_row else 0;
}

pub export fn howl_odin_bridge_cursor_column(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.cursor_column else 0;
}

pub export fn howl_odin_bridge_cursor_visible(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.cursor_visible) else 0;
}

pub export fn howl_odin_bridge_cursor_shape(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| begin.cursor_shape else 0;
}

pub export fn howl_odin_bridge_alternate_screen(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.alternate_screen) else 0;
}

pub export fn howl_odin_bridge_stream_closed(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.stream_closed) else 0;
}

pub export fn howl_odin_bridge_child_exited(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.child_exited) else 0;
}

pub export fn howl_odin_bridge_history_count(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_count else 0;
}

pub export fn howl_odin_bridge_history_offset(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_offset else 0;
}

pub export fn howl_odin_bridge_history_row_base(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_row_base else 0;
}

fn lastBegin(raw: ?*Handle) ?protocol.SnapshotBegin {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    return bridge.last_begin;
}

fn writeDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    message: []const u8,
) void {
    const count = @min(output_capacity, message.len);
    @memcpy(output_ptr[0..count], message[0..count]);
    output_len.* = count;
}

fn writeConnectDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    failure_name: []const u8,
    diagnostic: client.ConnectDiagnostic,
) void {
    if (output_capacity == 0) return;
    const rendered = std.fmt.bufPrint(
        output_ptr[0..output_capacity],
        "{s} stage={s} os_error={d}",
        .{ failure_name, @tagName(diagnostic.stage), diagnostic.os_error },
    ) catch return;
    output_len.* = rendered.len;
    if (diagnostic.route_message_len != 0 and rendered.len + 1 < output_capacity) {
        output_ptr[rendered.len] = ' ';
        const count = @min(output_capacity - rendered.len - 1, diagnostic.route_message_len);
        @memcpy(output_ptr[rendered.len + 1 ..][0..count], diagnostic.route_message[0..count]);
        output_len.* += 1 + count;
    }
}

fn writeJsonIdentity(writer: *std.Io.Writer, value: u64) !void {
    var buffer: [32]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{d}", .{value});
    try std.json.Stringify.value(rendered, .{}, writer);
}

pub export fn howl_odin_bridge_server_tree(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    interrupt: ?*client.Interrupt,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) i32 {
    output_len.* = 0;
    diagnostic_len.* = 0;
    if (endpoint_len == 0 or output_capacity == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_arguments");
        return 1;
    }

    const allocator = std.heap.c_allocator;
    var connect_diagnostic: server_client.ConnectDiagnostic = .{};
    var connection = server_client.Connection.connectCancelable(
        allocator,
        endpoint_ptr[0..endpoint_len],
        &connect_diagnostic,
        interrupt,
    ) catch |failure| {
        writeConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
            connect_diagnostic,
        );
        return 2;
    };
    defer connection.deinit();

    var tree = connection.observeTree(0) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return 3;
    };
    defer tree.deinit();

    var writer: std.Io.Writer = .fixed(output_ptr[0..output_capacity]);
    writer.writeAll("{\"schema\":\"howl.server.tree/v1\",\"server_id\":") catch return 4;
    writeJsonIdentity(&writer, tree.status.server_id) catch return 4;
    writer.writeAll(",\"tree_revision\":") catch return 4;
    writeJsonIdentity(&writer, tree.status.tree_revision) catch return 4;
    writer.writeAll(",\"sessions\":[") catch return 4;
    for (tree.sessions, 0..) |session, session_index| {
        if (session_index != 0) writer.writeByte(',') catch return 4;
        writer.writeAll("{\"session_id\":") catch return 4;
        writeJsonIdentity(&writer, session.id) catch return 4;
        writer.writeAll(",\"name\":") catch return 4;
        std.json.Stringify.value(session.name, .{}, &writer) catch return 4;
        writer.writeAll(",\"instances\":[") catch return 4;
        for (session.instances, 0..) |instance, instance_index| {
            if (instance_index != 0) writer.writeByte(',') catch return 4;
            writer.writeAll("{\"instance_id\":") catch return 4;
            writeJsonIdentity(&writer, instance.instance_id) catch return 4;
            writer.writeAll(",\"state\":") catch return 4;
            std.json.Stringify.value(@tagName(instance.state), .{}, &writer) catch return 4;
            writer.writeByte('}') catch return 4;
        }
        writer.writeAll("]}") catch return 4;
    }
    writer.writeAll("]}") catch return 4;
    output_len.* = writer.buffered().len;
    return 0;
}

test "bridge named key action values stay protocol-aligned" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyName.enter));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyName.backspace));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyAction.press));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyAction.release));
    try std.testing.expectEqual(@as(u8, 1), protocol.typed_input.modifiers.shift);
    try std.testing.expectEqual(@as(u8, 4), protocol.typed_input.modifiers.control);
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputMouseKind.press));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(protocol.InputMouseKind.wheel));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputMouseButton.left));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(protocol.InputMouseButton.wheel_down));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputFocus.in));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(protocol.InputFocus.out));
}

test "Odin renderer C records stay fixed and format tags follow renderer" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(RenderResourceInfo));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(RenderRemovalInfo));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(RenderCommandInfo));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(terminal_render.ResourceFormat.alpha8));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(terminal_render.ResourceFormat.rgba8));
}

test "Odin residency upsert replaces generations without growing the table" {
    const local = terminal_render.ResourceRef{
        .resource = try terminal_render.ResourceId.init(9),
        .generation = @fromBackingInt(1),
    };
    var storage: [render_resource_limit]terminal_render.Residency = undefined;
    var count: usize = 0;
    try upsertResidency(&storage, &count, .{
        .resource = local,
        .format = .rgba8,
        .size = .{ .width = 2, .height = 2 },
    });
    try std.testing.expectEqual(@as(usize, 1), count);
    var replacement = local;
    replacement.generation = @fromBackingInt(2);
    try upsertResidency(&storage, &count, .{
        .resource = replacement,
        .format = .rgba8,
        .size = .{ .width = 4, .height = 3 },
    });
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(storage[0].resource.generation));
    try std.testing.expectEqual(terminal_render.Size{ .width = 4, .height = 3 }, storage[0].size);
}

test "Odin search selection and interaction C records stay fixed" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SearchMatchInfo));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(SelectionRangeInfo));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(InteractionStateInfo));
}

/// Opens one consequence-policy connection without claiming Instance authority.
/// Callers can observe the current authority first and acquire only when policy
/// permits; this keeps independent desktop windows from stealing host policy
/// merely by attaching later.
pub export fn howl_odin_bridge_consequence_create(
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
    route_kind: u8,
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*ConsequenceHandle {
    diagnostic_len.* = 0;
    const target = targetFromAbi(route_kind, endpoint_ptr[0..endpoint_len], server_id, session_id, instance_id) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_target");
        return null;
    };
    const allocator = std.heap.c_allocator;
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    const bridge = allocator.create(ConsequenceBridge) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    defer if (!accepted) allocator.destroy(bridge);
    bridge.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connectForHost(runtime, interrupt, target, &connect_diagnostic) catch |failure| {
            writeConnectDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure), connect_diagnostic);
            return null;
        },
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(bridge);
}

pub export fn howl_odin_bridge_consequence_client_id(raw: ?*ConsequenceHandle) u64 {
    const value = raw orelse return 0;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    return bridge.connection.client_id;
}

pub export fn howl_odin_bridge_consequence_acquire(raw: ?*ConsequenceHandle) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.consequences.acquire(&bridge.connection) catch |failure| {
        bridge.setError("acquire", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_destroy(raw: ?*ConsequenceHandle) void {
    const value = raw orelse return;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    const allocator = bridge.allocator;
    // Deliberately close rather than sending assign(no_client): endpoint disconnect
    // clears authority only if this exact connection still owns it.
    bridge.connection.deinit();
    releaseRuntime(bridge.runtime);
    allocator.destroy(bridge);
}

pub export fn howl_odin_bridge_consequence_info_size() u32 {
    return @sizeOf(ConsequenceInfo);
}

/// Returns the packed canonical consequence-kind ABI values for the Odin startup check.
pub export fn howl_odin_bridge_consequence_kind_signature() u64 {
    return consequence_kind_abi_signature;
}

/// Returns the packed canonical consequence-reply ABI values for the Odin startup check.
pub export fn howl_odin_bridge_consequence_reply_signature() u64 {
    return consequence_reply_abi_signature;
}

/// Observes one current consequence. Payload bytes are copied only up to the
/// caller's bounded scratch; `info.payload_len` always reports the complete size.
pub export fn howl_odin_bridge_consequence_observe(
    raw: ?*ConsequenceHandle,
    info: *ConsequenceInfo,
    payload_ptr: [*]u8,
    payload_capacity: usize,
    copied_len: *usize,
) i32 {
    info.* = .{};
    copied_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    var snapshot = client.consequences.observe(&bridge.connection, bridge.allocator) catch |failure| {
        bridge.setError("observe", @errorName(failure));
        return 2;
    };
    defer snapshot.deinit();
    info.* = .{
        .terminal_revision = snapshot.begin.terminal_revision,
        .authority_client_id = snapshot.begin.authority_client_id,
        .generation = snapshot.begin.generation,
        .payload_len = snapshot.begin.payload_len,
        .kind = @backingInt(snapshot.begin.kind),
        .reply_required = @intFromBool(snapshot.begin.reply_required),
        .metadata = snapshot.begin.metadata,
    };
    const count = @min(payload_capacity, snapshot.payload.len);
    @memcpy(payload_ptr[0..count], snapshot.payload[0..count]);
    copied_len.* = count;
    return 0;
}

pub export fn howl_odin_bridge_consequence_consume(
    raw: ?*ConsequenceHandle,
    generation: u64,
) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.consequences.consume(&bridge.connection, generation) catch |failure| {
        bridge.setError("consume", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_reply(
    raw: ?*ConsequenceHandle,
    generation: u64,
    kind_raw: u8,
    body_ptr: [*]const u8,
    body_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const kind: client.consequences.ReplyKind = switch (kind_raw) {
        @backingInt(client.consequences.ReplyKind.clipboard) => .clipboard,
        @backingInt(client.consequences.ReplyKind.pointer_shape) => .pointer_shape,
        @backingInt(client.consequences.ReplyKind.color_preference) => .color_preference,
        @backingInt(client.consequences.ReplyKind.container_state) => .container_state,
        @backingInt(client.consequences.ReplyKind.container_position) => .container_position,
        @backingInt(client.consequences.ReplyKind.container_screen_cells) => .container_screen_cells,
        @backingInt(client.consequences.ReplyKind.container_icon_title) => .container_icon_title,
        @backingInt(client.consequences.ReplyKind.container_decline) => .container_decline,
        else => {
            bridge.setError("reply", "invalid_kind");
            return 2;
        },
    };
    client.consequences.reply(&bridge.connection, generation, kind, body_ptr[0..body_len]) catch |failure| {
        bridge.setError("reply", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_copy_error(
    raw: ?*ConsequenceHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, bridge.last_error_len);
    @memcpy(output_ptr[0..count], bridge.last_error[0..count]);
    output_len.* = count;
}

test "pane gutter background follows accepted default color and screen reverse" {
    var presentation: client.rich.Presentation = undefined;
    presentation.reverse_screen = false;
    presentation.background = .{ .r = 17, .g = 34, .b = 51, .a = 255 };
    presentation.foreground = .{ .r = 221, .g = 204, .b = 187, .a = 255 };
    try std.testing.expectEqual(@as(u32, 0xff332211), paddingBackground(&presentation));
    presentation.reverse_screen = true;
    try std.testing.expectEqual(@as(u32, 0xffbbccdd), paddingBackground(&presentation));
}

test "discarding a prepared render releases shared scratch without publishing front state" {
    var renderer: Render = undefined;
    var scratch: RenderScratch = undefined;
    scratch.prepared_owner = &renderer;
    renderer.front = .{};
    renderer.scratch = &scratch;
    renderer.external_upload_count = 0;
    renderer.frame_upload_count = 2;
    renderer.upload_count = 3;
    renderer.removal_count = 4;
    renderer.command_count = 5;
    renderer.pixel_count = 6;
    const handle: *RenderHandle = @ptrCast(&renderer);

    howl_odin_bridge_render_discard(handle);

    try std.testing.expectEqual(@as(?*Render, null), scratch.prepared_owner);
    try std.testing.expectEqual(@as(usize, 0), renderer.frame_upload_count);
    try std.testing.expectEqual(@as(usize, 0), renderer.upload_count);
    try std.testing.expectEqual(@as(usize, 0), renderer.removal_count);
    try std.testing.expectEqual(@as(usize, 0), renderer.command_count);
    try std.testing.expectEqual(@as(usize, 0), renderer.pixel_count);
    try std.testing.expect(renderer.front.begin == null);
}

test "render headers publish metadata and selection only on acceptance" {
    var renderer: Render = undefined;
    var scratch: RenderScratch = undefined;
    scratch.prepared_owner = &renderer;
    renderer.front = .{};
    renderer.begin = null;
    renderer.frame_revision = 17;
    renderer.surface = .{ .width = 400, .height = 200 };
    renderer.background_rgba = 0xff123456;
    renderer.external_upload_count = 0;
    renderer.scratch = &scratch;
    // Eligible offers fail before accessing the deliberately undefined composer.
    renderer.cell_size = .{ .width = 0, .height = 0 };
    const handle: *RenderHandle = @ptrCast(&renderer);
    var first_begin = std.mem.zeroes(protocol.SnapshotBegin);
    first_begin.revision = 6;
    first_begin.history_offset = 4;
    first_begin.history_count = 100;
    first_begin.history_row_base = 2;
    first_begin.rows = 1;
    first_begin.columns = 8;
    var next_begin = first_begin;
    next_begin.revision = 8;
    next_begin.history_offset = 0;
    next_begin.history_count = 0;
    next_begin.history_row_base = 0;
    next_begin.alternate_screen = true;
    const live = try testReusableProjection(0, false);
    defer client.view.deinit(live);
    const historical = try testReusableProjection(1, false);
    defer client.view.deinit(historical);
    const image = try testReusableProjection(0, true);
    defer client.view.deinit(image);

    // null, unprepared, prepared, accepted, next prepared/rejected, next accepted
    for (0..6) |stage| {
        switch (stage) {
            2 => {
                renderer.begin = first_begin;
                renderer.selection_rows[0] = .{ .content_end_exclusive = 3, .wrapped = false };
            },
            3, 5 => howl_odin_bridge_render_accept(handle),
            4 => {
                // Missing, older, and equal pending headers all permit revision 7.
                // A surface failure must leave the accepted cut and selection intact.
                for ([_]?u64{ null, 6, 7 }) |revision| {
                    renderer.begin = if (revision) |value| blk: {
                        var begin = next_begin;
                        begin.revision = value;
                        break :blk begin;
                    } else null;
                    try std.testing.expectEqual(@as(i32, 3), howl_odin_bridge_render_prepare_view(handle, live));
                    try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                    try std.testing.expectEqualDeep(client.selection.RowShape{ .content_end_exclusive = 3, .wrapped = false }, renderer.front.selection_rows[0]);
                    try std.testing.expectEqualStrings("surface:InvalidSurface", renderer.last_error[0..renderer.last_error_len]);
                }
                // Invalid cuts remain rejected even at an eligible revision.
                for ([_]?*const client.view.Snapshot{ historical, image, null }) |offer| {
                    try std.testing.expectEqual(@as(i32, 9), howl_odin_bridge_render_prepare_view(handle, offer));
                    try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                }
                renderer.begin = next_begin;
                renderer.selection_rows[0] = .{ .content_end_exclusive = 1, .wrapped = true };
                // Revision 7 is newer than front 6 but older than pending 8.
                try std.testing.expectEqual(@as(i32, 9), howl_odin_bridge_render_prepare_view(handle, live));
                try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                try std.testing.expectEqualDeep(next_begin, renderer.begin.?);
            },
            else => {},
        }
        const raw = if (stage == 0) null else handle;
        const expected = if (stage < 3) std.mem.zeroes(protocol.SnapshotBegin) else if (stage == 5) next_begin else first_begin;
        try std.testing.expectEqual(expected.revision, howl_odin_bridge_render_instance_revision(raw));
        try std.testing.expectEqual(expected.history_offset, howl_odin_bridge_render_history_offset(raw));
        try std.testing.expectEqual(expected.history_count, howl_odin_bridge_render_history_count(raw));
        try std.testing.expectEqual(expected.history_row_base, howl_odin_bridge_render_history_row_base(raw));
        try std.testing.expectEqual(@as(u8, @intFromBool(expected.alternate_screen)), howl_odin_bridge_render_alternate_screen(raw));
        var first: u16 = 99;
        var last: u16 = 99;
        const selected = howl_odin_bridge_render_selection_span(raw, 98, 0, 98, 7, 8, 0, 0, &first, &last);
        try std.testing.expectEqual(@as(u8, if (stage == 3 or stage == 4) 1 else 0), selected);
        try std.testing.expectEqual(@as(u16, 0), first);
        try std.testing.expectEqual(@as(u16, if (selected == 1) 2 else 0), last);
        if (stage == 5) {
            try std.testing.expectEqual(@as(u8, 1), howl_odin_bridge_render_selection_span(raw, 0, 0, 0, 7, 8, 1, 0, &first, &last));
            try std.testing.expectEqual(@as(u16, 0), first);
            try std.testing.expectEqual(@as(u16, 0), last);
        }
        if (stage >= 3) try std.testing.expectEqual(@as(u16, 400), howl_odin_bridge_render_surface_width(raw));
    }
}

test "completed selection rejection is distinct from interrupted transport" {
    try std.testing.expectEqual(@as(i32, 6), query_declined);
    try std.testing.expect(query_declined != 4);
}

// Small coherent fixture; projections own their bytes rather than borrowing the
// temporary rich model, just as in the real observer-to-render handoff.
fn testReusableProjection(history: u32, with_image: bool) !*client.view.Snapshot {
    var scalar = [_]u32{'x'};
    var cells = [_]client.rich.Cell{std.mem.zeroes(client.rich.Cell)};
    cells[0].scalars = &scalar;
    cells[0].width = 1;
    cells[0].height = 1;
    cells[0].subscale_n = 1;
    cells[0].subscale_d = 1;
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var rich = std.mem.zeroes(client.rich.View);
    rich.begin.revision = 7;
    rich.begin.terminal_revision = 5;
    rich.begin.rows = 1;
    rich.begin.columns = 1;
    rich.begin.history_count = history;
    rich.begin.history_offset = history;
    rich.rows = &rows;
    rich.properties.title = "shared title";
    var image = [_]protocol.SnapshotImage{.{ .image_id = 1, .generation = 1, .width = 1, .height = 1 }};
    var placement = [_]protocol.SnapshotImagePlacement{std.mem.zeroes(protocol.SnapshotImagePlacement)};
    if (with_image) {
        placement[0].image_id = 1;
        placement[0].generation = 1;
        placement[0].source_width = 1;
        placement[0].source_height = 1;
        placement[0].pixel_width = 1;
        placement[0].pixel_height = 1;
        rich.graphics.cell_pixel_width = 1;
        rich.graphics.cell_pixel_height = 1;
        rich.graphics.images = &image;
        rich.graphics.placements = &placement;
    }
    return client.view.projectView(std.testing.allocator, &rich);
}

test "rich loan is single-take and release bounded without a connection" {
    var scalar = [_]u32{'x'};
    var cells = [_]client.rich.Cell{std.mem.zeroes(client.rich.Cell)};
    cells[0].scalars = &scalar;
    cells[0].width = 1;
    cells[0].height = 1;
    cells[0].subscale_n = 1;
    cells[0].subscale_d = 1;
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var rich = std.mem.zeroes(client.rich.View);
    rich.begin.revision = 11;
    rich.begin.rows = 1;
    rich.begin.columns = 1;
    rich.rows = &rows;

    var bridge: Bridge = undefined;
    bridge.live_view = rich;
    bridge.rich_loan_active = true;
    bridge.rich_loan_taken = false;
    const handle: *Handle = @ptrCast(&bridge);

    const loan = howl_odin_bridge_snapshot_take_rich_loan(handle).?;
    try std.testing.expectEqual(handle, loan);
    try std.testing.expect(bridge.rich_loan_taken);
    try std.testing.expectEqual(@as(?*Handle, null), howl_odin_bridge_snapshot_take_rich_loan(handle));

    howl_odin_bridge_snapshot_release_rich_loan(loan);
    try std.testing.expect(!bridge.rich_loan_active);
    try std.testing.expect(!bridge.rich_loan_taken);
    try std.testing.expect(bridge.live_view == null);
}

test "live view transfer keeps exact immutable text and metadata without a connection" {
    const projected = try testReusableProjection(0, false);
    var bridge: Bridge = undefined;
    bridge.reusable_view = projected;
    const handle: *Handle = @ptrCast(&bridge);
    const taken = howl_odin_bridge_snapshot_take_view(handle).?;
    defer howl_odin_bridge_view_destroy(taken);
    try std.testing.expectEqual(projected, taken);
    try std.testing.expectEqual(@as(?*client.view.Snapshot, null), howl_odin_bridge_snapshot_take_view(handle));
    try std.testing.expect(standaloneLiveView(taken));
    try std.testing.expectEqual(@as(u64, 7), client.view.begin(taken).revision);
    try std.testing.expectEqualStrings("shared title", client.view.properties(taken).title.?);
    var text: [16]u8 = undefined;
    const written = client.view.writeVisibleText(taken, &text);
    try std.testing.expectEqualStrings("x", text[0..written.bytes_written]);
}

test "only self-contained live views may cross the observation connection boundary" {
    const live = try testReusableProjection(0, false);
    defer client.view.deinit(live);
    const historical = try testReusableProjection(1, false);
    defer client.view.deinit(historical);
    const image = try testReusableProjection(0, true);
    defer client.view.deinit(image);
    try std.testing.expect(standaloneLiveView(live));
    try std.testing.expect(!standaloneLiveView(historical));
    try std.testing.expect(!standaloneLiveView(image));
}

test "Odin bridge transported route ABI admits only direct and Server targets" {
    const direct = try targetFromAbi(0, "unix:/tmp/howl.sock", 0, 0, 0);
    try std.testing.expectEqual(RouteKind.direct, direct.kind);
    try std.testing.expectEqualStrings("unix:/tmp/howl.sock", direct.endpoint);
    try std.testing.expectEqual(@as(u64, 0), direct.session_id);
    try std.testing.expectEqual(@as(u64, 0), direct.instance_id);

    const managed = try targetFromAbi(1, "tcp://127.0.0.1:43130", 91, 7, 3);
    try std.testing.expectEqual(RouteKind.server, managed.kind);
    try std.testing.expectEqual(@as(u64, 91), managed.server_id);
    try std.testing.expectEqual(@as(u64, 7), managed.session_id);
    try std.testing.expectEqual(@as(u64, 3), managed.instance_id);

    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(0, "tcp://127.0.0.1:1", 91, 7, 3));
    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(1, "tcp://127.0.0.1:1", 91, 0, 3));
    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(1, "tcp://127.0.0.1:1", 0, 7, 3));
    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(2, "", 0, 0, 3));
    try std.testing.expectError(error.InvalidEndpoint, targetFromAbi(3, "", 0, 0, 3));
}

test "native local catalogue grants one terminal owner per stable identity" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{
        .environ = std.testing.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();
    var state = NativeLocalState{};
    const value = try native_instance.init(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "sleep 30",
            .rows = 2,
            .columns = 8,
            .history_rows = 8,
        },
    );
    var inserted = false;
    defer if (!inserted) native_instance.deinit(value);
    const id = try state.insert(io, value);
    inserted = true;
    try std.testing.expect(id != 0);
    try std.testing.expect(!state.empty());

    const claimed = try state.claim(io, id);
    try std.testing.expect(claimed == value);
    try std.testing.expectError(
        error.LocalInstanceClaimed,
        state.claim(io, id),
    );
    try std.testing.expect(!state.destroy(io, id));

    state.release(io, id, claimed);
    try std.testing.expect(state.destroy(io, id));
    try std.testing.expect(state.empty());
}

test "native terminal claim services PTY directly and publishes Render" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{
        .environ = std.testing.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();
    var state = NativeLocalState{};

    const value = try native_instance.init(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "stty -echo; printf NATIVE_READY; read line; printf DIRECT_ACK; sleep 30",
            .rows = 2,
            .columns = 16,
            .history_rows = 8,
        },
    );
    var inserted = false;
    defer if (!inserted) native_instance.deinit(value);
    const id = try state.insert(io, value);
    inserted = true;

    var runtime = Runtime{
        .threaded = std.Io.Threaded.init(std.testing.allocator, .{
            .environ = std.testing.environ,
        }),
    };
    defer runtime.threaded.deinit();
    runtime.native_local = state;

    var diagnostic: [160]u8 = undefined;
    var diagnostic_len: usize = 0;
    var raw: ?*NativeTerminalHandle = howl_odin_bridge_native_terminal_claim(
        @ptrCast(&runtime),
        id,
        &diagnostic,
        diagnostic.len,
        &diagnostic_len,
    ) orelse return error.ClaimFailed;
    defer {
        if (raw) |active| howl_odin_bridge_native_terminal_release(active);
        if (!runtime.native_local.empty())
            _ = runtime.native_local.destroy(runtime.threaded.io(), id);
    }
    const owner = nativeTerminalValue(raw).?;

    try std.testing.expectEqual(
        size_rejected,
        howl_odin_bridge_native_terminal_send_resize(
            raw,
            0,
            16,
            10,
            20,
            1,
        ),
    );

    var attempts: usize = 0;
    while (attempts < 2000) : (attempts += 1) {
        _ = try owner.service(attempts + 1);
        const view = native_instance.terminal(owner.value).semanticView(0);
        if (view.cellAt(0, 0) == 'N') break;
        try std.Io.sleep(std.testing.io, .fromMilliseconds(1), .awake);
    } else return error.Timeout;

    var info = NativeTerminalInfo{};
    var title: [64]u8 = undefined;
    var title_len: usize = 0;
    var row_shapes: [16]NativeRowShape = undefined;
    var row_shape_count: usize = 0;
    try std.testing.expectEqual(
        @as(i32, 0),
        howl_odin_bridge_native_terminal_snapshot(
            raw,
            0,
            &info,
            &title,
            title.len,
            &title_len,
            &row_shapes,
            row_shapes.len,
            &row_shape_count,
        ),
    );
    try std.testing.expect(info.revision != 0);
    try std.testing.expectEqual(info.revision, info.terminal_revision);
    try std.testing.expectEqual(@as(u16, 2), info.rows);
    try std.testing.expectEqual(@as(u16, 16), info.columns);
    try std.testing.expectEqual(@as(usize, 2), row_shape_count);
    try std.testing.expectEqual(
        @as(u21, 'N'),
        native_instance.terminal(owner.value).semanticView(0).cellAt(0, 0),
    );
    try std.testing.expectEqual(@as(u16, 12), row_shapes[0].content_end_exclusive);

    try std.testing.expectEqual(
        @as(i32, 0),
        howl_odin_bridge_native_terminal_send_text(
            raw,
            "DIRECT\n".ptr,
            "DIRECT\n".len,
        ),
    );
    attempts = 0;
    while (attempts < 2000) : (attempts += 1) {
        _ = try owner.waitAndService(1);
        const view = native_instance.terminal(owner.value).semanticView(0);
        var found = false;
        for (0..view.rows) |row| {
            for (0..view.cols) |column| {
                if (view.cellAt(@intCast(row), @intCast(column)) == 'D') {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (found) break;
        try std.Io.sleep(std.testing.io, .fromMilliseconds(1), .awake);
    } else return error.Timeout;

    // This fixture is headless, so the backend exchange is intentionally absent.
    try std.testing.expect(
        howl_odin_bridge_native_terminal_render_exchange(raw) == null,
    );

    // Release before catalogue destruction.
    howl_odin_bridge_native_terminal_release(raw);
    raw = null;
    try std.testing.expect(runtime.native_local.destroy(runtime.threaded.io(), id));
}

test "native Canvas exposes no geometry before an accepted publication" {
    const front = NativeCanvasFront{};
    try std.testing.expectEqual(@as(u16, 0), front.surface.width);
    try std.testing.expectEqual(@as(u16, 0), front.surface.height);
    try std.testing.expectEqual(@as(u16, 0), front.cell_size.width);
    try std.testing.expectEqual(@as(u16, 0), front.cell_size.height);
}

test "native presentation config retains two caller-owned fallback paths" {
    var fallbacks: [2][]const u8 = undefined;
    const config = nativePresentationConfig(
        &fallbacks,
        "regular.ttf",
        "",
        "",
        "",
        "arabic.ttf",
        "cjk.ttc",
        17,
    );
    const regular = switch (config.fonts.regular) {
        .path => |value| value,
        .memory => return error.UnexpectedMemoryFont,
    };
    try std.testing.expectEqual(@as(usize, 2), regular.fallbacks.len);
    try std.testing.expectEqualStrings("arabic.ttf", regular.fallbacks[0]);
    try std.testing.expectEqualStrings("cjk.ttc", regular.fallbacks[1]);
}
