//! Owns three fixed Linux PTY/VT threads and bounded semantic publication.

const std = @import("std");
const howl_vt = @import("howl_vt");
const layout = @import("layout.zig");
const c = @import("native.zig").c;

/// Bounds one terminal surface to a 1920-pixel-wide first-freeze window.
pub const max_cols: u16 = 240;
/// Bounds one terminal surface to a 1088-pixel-high first-freeze window.
pub const max_rows: u16 = 68;
const command_capacity: usize = 32;
const mouse_motion_capacity: usize = 1;
// Ordinary work cannot consume one cancellation slot per physical button.
const mouse_release_capacity: usize = 3;
/// Bounds accepted physical key lifecycles and their reserved releases.
pub const max_pressed_keys: usize = 16;
/// Bounds one compositor wheel event without losing accepted detent count.
pub const max_wheel_steps: u8 = 32;
/// Bounds one committed keyboard text command.
pub const max_input_bytes: usize = 64;
/// Mirrors howl-vt's bounded trailing-scalar storage in one lead cell.
pub const max_combining: usize = 3;
/// Mirrors howl-vt's bound for each copied title or icon value.
pub const metadata_max_bytes: usize = howl_vt.Terminal.metadata_max_bytes;

/// Bounds one complete semantic terminal snapshot.
pub const max_cells: usize = @as(usize, max_cols) * max_rows;
const read_bytes: usize = 4096;
const blank_cell = Cell{
    .codepoint = 0,
    .width = 1,
    .foreground = howl_vt.Terminal.default_presentation.foreground,
    .background = howl_vt.Terminal.default_presentation.background,
    .underline_color = howl_vt.Terminal.default_presentation.foreground,
};
const shell_path: [:0]const u8 = "/bin/bash";
const test_cell_size = CellSize{ .width = 8, .height = 16 };

/// Reports exact terminal owner, queue, PTY, VT, or cleanup failure.
pub const Error = std.mem.Allocator.Error || std.Thread.SpawnError ||
    howl_vt.Terminal.InitError || howl_vt.Terminal.ResizeError ||
    howl_vt.Terminal.InputError || error{
    invalid_geometry,
    input_too_large,
    command_queue_full,
    owner_stopping,
    pty_open_failed,
    pty_config_failed,
    child_launch_failed,
    child_exited,
    pty_read_failed,
    pty_write_failed,
    pty_resize_failed,
    wake_failed,
    wait_failed,
    signal_failed,
    child_wait_failed,
    descriptor_close_failed,
    publication_exhausted,
    ParsedEventLimit,
    StringControlLimit,
    transcript_mismatch,
    transcript_incomplete,
    invalid_cell,
    invalid_key,
    invalid_metadata,
    invalid_mouse,
};

/// Copies one bounded terminal metadata value with a trailing C sentinel.
pub const Metadata = struct {
    len: u16 = 0,
    bytes: [metadata_max_bytes:0]u8 = .{0} ** metadata_max_bytes,

    /// Borrows initialized bytes without the trailing sentinel.
    pub fn view(self: *const Metadata) []const u8 {
        return self.bytes[0..self.len];
    }

    /// Borrows initialized bytes with the stored trailing C sentinel.
    pub fn sentinelView(self: *const Metadata) [:0]const u8 {
        return self.bytes[0..self.len :0];
    }
};

/// Copies one bounded shell-integration mark into an immutable generation.
pub const ShellMark = struct {
    kind: u8 = 0,
    status: ?i32 = null,
    metadata: Metadata = .{},
};

/// Copies one shell name at howl-vt's exact protocol bound.
pub const ShellName = struct {
    len: u8 = 0,
    bytes: [howl_vt.Terminal.shell_name_max_bytes:0]u8 =
        .{0} ** howl_vt.Terminal.shell_name_max_bytes,

    /// Borrows initialized shell-name bytes without the trailing sentinel.
    pub fn view(self: *const ShellName) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Copies validated shell identity into an immutable terminal generation.
pub const ShellIntegration = struct {
    version: u32,
    shell: ?ShellName,
};

/// Copies one complete bounded howl-vt cell for immutable publication.
pub const Cell = struct {
    codepoint: u21,
    combining_len: u8 = 0,
    combining: [max_combining]u21 = .{0} ** max_combining,
    width: u8,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    foreground: howl_vt.Terminal.Rgb =
        howl_vt.Terminal.default_presentation.foreground,
    background: howl_vt.Terminal.Rgb =
        howl_vt.Terminal.default_presentation.background,
    underline_color: howl_vt.Terminal.Rgb =
        howl_vt.Terminal.default_presentation.foreground,
    dim: bool = false,
    invisible: bool = false,
    underline: bool = false,
    underline_style: howl_vt.Terminal.UnderlineStyle = .straight,
    strikethrough: bool = false,

    /// Copies the base and initialized trailing scalars into shaping storage.
    pub fn copyCodepoints(
        self: *const Cell,
        values: *[max_combining + 1]u32,
    ) []const u32 {
        values[0] = self.codepoint;
        for (0..self.combining_len) |index|
            values[index + 1] = self.combining[index];
        return values[0 .. self.combining_len + 1];
    }
};

/// Carries nonzero font-derived terminal cell geometry.
pub const CellSize = struct {
    width: u16,
    height: u16,
};

/// Owns one complete immutable bounded semantic terminal generation.
pub const Snapshot = struct {
    terminal: layout.TerminalId,
    generation: u64,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    cursor_shape: howl_vt.Terminal.CursorShape = .block,
    cursor_color: howl_vt.Terminal.Rgb =
        howl_vt.Terminal.default_presentation.foreground,
    cursor_text_color: howl_vt.Terminal.Rgb =
        howl_vt.Terminal.default_presentation.background,
    title: Metadata = .{},
    icon: Metadata = .{},
    shell_integration: ?ShellIntegration = null,
    shell_mark: ShellMark = .{},
    /// Copies the VT BEL count without choosing an audible or visual policy.
    bell_generation: u64 = 0,
    is_alternate_screen: bool = false,
    count: u32,
    cells: [max_cells]Cell,

    /// Returns only cells belonging to this complete surface.
    pub fn visible(self: *const Snapshot) []const Cell {
        return self.cells[0..self.count];
    }
};

const Geometry = struct {
    rows: u16,
    cols: u16,
    cell_width: u16 = test_cell_size.width,
    cell_height: u16 = test_cell_size.height,
};

const Input = struct {
    len: u8 = 0,
    bytes: [max_input_bytes]u8 = .{0} ** max_input_bytes,
};

/// Names ordinary non-text keys routed through VT mode-aware encoding.
pub const NamedKey = enum {
    enter,
    backspace,
    up,
    down,
    left,
    right,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    left_hyper,
    right_hyper,
    left_meta,
    right_meta,
    caps_lock,
    num_lock,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_add,
    keypad_subtract,
    keypad_multiply,
    keypad_divide,
    keypad_separator,
    keypad_equal,
    keypad_enter,
};

/// Identifies one physical key transition retained through VT encoding.
pub const KeyAction = enum { press, repeat, release };

/// Carries one named key and its complete terminal modifier state.
pub const KeyCommand = struct {
    named: NamedKey,
    action: KeyAction = .press,
    shift: bool,
    alt: bool,
    control: bool,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
};

/// Copies one Unicode physical key, legacy bytes, and committed text.
pub const UnicodeKeyCommand = struct {
    codepoint: u21,
    shifted: ?u21 = null,
    alternate: ?u21 = null,
    legacy: Input = .{},
    text: Input,
    action: KeyAction = .press,
    shift: bool,
    alt: bool,
    control: bool,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
};

/// Names the bounded mouse buttons understood by howl-vt.
pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
};

/// Names one physical pointer transition routed through howl-vt.
pub const MouseKind = enum {
    press,
    release,
    move,
    wheel,
};

/// Carries one bounded cell-local mouse fact into its terminal owner.
///
/// Row, column, and pixels are local to the selected visible terminal.
/// `buttons_down` uses bits 0, 1, and 2 for left, middle, and right.
pub const MouseCommand = struct {
    kind: MouseKind,
    button: MouseButton,
    row: u16,
    col: u16,
    pixel_x: u16,
    pixel_y: u16,
    shift: bool,
    alt: bool,
    control: bool,
    buttons_down: u8,
    wheel_steps: u8 = 1,
};

const Command = union(enum) {
    input: Input,
    key: KeyCommand,
    unicode_key: UnicodeKeyCommand,
    mouse: MouseCommand,
    focus: bool,
    resize: Geometry,
};

const Operation = union(enum) {
    write: Input,
    resize: Geometry,
};

const Step = struct {
    operation: Operation,
    failure: ?Error = null,
};

const Transcript = struct {
    steps: []const Step,
    index: usize = 0,

    fn consume(self: *Transcript, operation: Operation) Error!void {
        if (self.index == self.steps.len) return error.transcript_mismatch;
        const step = self.steps[self.index];
        if (!std.meta.eql(step.operation, operation)) return error.transcript_mismatch;
        self.index += 1;
        if (step.failure) |failure| return failure;
    }

    fn finish(self: *const Transcript) error{transcript_incomplete}!void {
        if (self.index != self.steps.len) return error.transcript_incomplete;
    }
};

const Queue = struct {
    values: [command_capacity + mouse_motion_capacity + mouse_release_capacity + max_pressed_keys]Command = undefined,
    head: usize = 0,
    count: usize = 0,
    mouse_releases: usize = 0,
    key_releases: usize = 0,

    fn push(self: *Queue, command: Command) error{command_queue_full}!void {
        if (isKeyRelease(command))
            @panic("physical key release bypassed its reserved admission path");
        if (self.count >= command_capacity) return error.command_queue_full;
        self.append(command);
    }

    fn pushMouseRelease(self: *Queue, command: MouseCommand) error{command_queue_full}!void {
        if (self.mouse_releases == mouse_release_capacity or
            self.count == self.values.len)
            return error.command_queue_full;
        self.append(.{ .mouse = command });
        self.mouse_releases += 1;
    }

    fn pushKeyRelease(self: *Queue, command: Command) error{command_queue_full}!void {
        if (!isKeyRelease(command))
            @panic("key-release reserve received a non-release command");
        if (self.key_releases == max_pressed_keys or self.count == self.values.len)
            return error.command_queue_full;
        self.append(command);
        self.key_releases += 1;
    }

    const MotionAdmission = enum { appended, replaced, dropped };

    fn pushMouseMotion(self: *Queue, command: MouseCommand) MotionAdmission {
        if (self.count != 0) {
            const tail = (self.head + self.count - 1) % self.values.len;
            switch (self.values[tail]) {
                .mouse => |mouse| if (mouse.kind == .move) {
                    self.values[tail] = .{ .mouse = command };
                    return .replaced;
                },
                else => {},
            }
        }
        if (self.count >= command_capacity + mouse_motion_capacity) return .dropped;
        self.append(.{ .mouse = command });
        return .appended;
    }

    fn append(self: *Queue, command: Command) void {
        self.values[(self.head + self.count) % self.values.len] = command;
        self.count += 1;
    }

    fn pop(self: *Queue) ?Command {
        if (self.count == 0) return null;
        const command = self.values[self.head];
        self.head = (self.head + 1) % self.values.len;
        self.count -= 1;
        switch (command) {
            .mouse => |mouse| {
                if (mouse.kind == .release) self.mouse_releases -= 1;
            },
            .key => |key| {
                if (key.action == .release) self.key_releases -= 1;
            },
            .unicode_key => |key| {
                if (key.action == .release) self.key_releases -= 1;
            },
            else => {},
        }
        return command;
    }

    fn discardNewest(self: *Queue) void {
        std.debug.assert(self.count > 0);
        const tail = (self.head + self.count - 1) % self.values.len;
        switch (self.values[tail]) {
            .mouse => |mouse| {
                if (mouse.kind == .release) self.mouse_releases -= 1;
            },
            .key => |key| {
                if (key.action == .release) self.key_releases -= 1;
            },
            .unicode_key => |key| {
                if (key.action == .release) self.key_releases -= 1;
            },
            else => {},
        }
        self.count -= 1;
    }
};

fn isKeyRelease(command: Command) bool {
    return switch (command) {
        .key => |key| key.action == .release,
        .unicode_key => |key| key.action == .release,
        else => false,
    };
}

const StopRequest = struct {
    prior_failure: ?Error,
    request_failure: ?Error,
};

const Pty = struct {
    master_fd: c_int,
    child: c.pid_t,

    fn open(geometry: Geometry, executable: [:0]const u8) Error!Pty {
        // CLOEXEC turns parent EOF into proof that execve replaced the child;
        // any return from execve writes one failure marker first.
        var launch_pipe: [2]c_int = undefined;
        if (std.c.pipe2(&launch_pipe, .{ .CLOEXEC = true }) != 0)
            return error.child_launch_failed;
        var master: c_int = -1;
        var winsize = c.struct_winsize{
            .ws_row = geometry.rows,
            .ws_col = geometry.cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        const child = c.forkpty(&master, null, null, &winsize);
        if (child < 0) {
            closeOwned(launch_pipe[0]);
            closeOwned(launch_pipe[1]);
            return error.pty_open_failed;
        }
        if (child == 0) {
            const no_profile: [*:0]const u8 = "--noprofile";
            const no_rc: [*:0]const u8 = "--norc";
            const interactive: [*:0]const u8 = "-i";
            const argv = [_:null][*c]u8{
                @ptrCast(@constCast(executable.ptr)),
                @ptrCast(@constCast(no_profile)),
                @ptrCast(@constCast(no_rc)),
                @ptrCast(@constCast(interactive)),
            };
            const envp: [*c]const [*c]u8 = @ptrCast(@constCast(std.c.environ));
            const exec_result = c.execve(executable.ptr, argv[0..].ptr, envp);
            writeLaunchFailure(launch_pipe[1]);
            c._exit(if (exec_result == -1) 127 else 126);
        }
        closeOwned(launch_pipe[1]);
        const launched = readLaunchStatus(launch_pipe[0]) catch |failure| {
            closeOwned(launch_pipe[0]);
            rollbackChild(master, child);
            return failure;
        };
        closeOwned(launch_pipe[0]);
        if (!launched) {
            rollbackChild(master, child);
            return error.child_launch_failed;
        }
        errdefer rollbackChild(master, child);
        const flags = c.fcntl(master, c.F_GETFL, @as(c_int, 0));
        if (flags < 0 or c.fcntl(master, c.F_SETFL, flags | c.O_NONBLOCK) != 0)
            return error.pty_config_failed;
        const fd_flags = c.fcntl(master, c.F_GETFD, @as(c_int, 0));
        if (fd_flags < 0 or c.fcntl(master, c.F_SETFD, fd_flags | c.FD_CLOEXEC) != 0)
            return error.pty_config_failed;
        return .{ .master_fd = master, .child = child };
    }

    fn resize(self: Pty, geometry: Geometry) Error!void {
        var winsize = c.struct_winsize{
            .ws_row = geometry.rows,
            .ws_col = geometry.cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        if (c.ioctl(self.master_fd, c.TIOCSWINSZ, &winsize) != 0)
            return error.pty_resize_failed;
    }

    fn writeAll(self: Pty, bytes: []const u8) Error!void {
        var written: usize = 0;
        while (written < bytes.len) {
            const count = c.write(self.master_fd, bytes[written..].ptr, bytes.len - written);
            if (count > 0) {
                written += @intCast(count);
                continue;
            }
            if (count < 0 and std.posix.errno(count) == .INTR) continue;
            if (count < 0 and std.posix.errno(count) == .AGAIN) {
                var fd = [_]std.posix.pollfd{.{
                    .fd = self.master_fd,
                    .events = std.posix.POLL.OUT,
                    .revents = 0,
                }};
                if ((std.posix.poll(&fd, -1) catch return error.wait_failed) == 0)
                    return error.wait_failed;
                continue;
            }
            return error.pty_write_failed;
        }
    }

    fn stop(self: Pty) Error!void {
        var failure: ?Error = null;
        signalChild(self.child, c.SIGHUP) catch {
            failure = error.signal_failed;
        };
        signalChild(self.child, c.SIGKILL) catch {
            failure = error.signal_failed;
        };
        waitForChild(self.child) catch {
            failure = error.child_wait_failed;
        };
        if (c.close(self.master_fd) != 0 and failure == null)
            failure = error.descriptor_close_failed;
        if (failure) |cause| return cause;
    }
};

const Transport = union(enum) {
    native: Pty,
    transcript: *Transcript,

    fn writeAll(self: *Transport, input: Input) Error!void {
        switch (self.*) {
            .native => |pty| try pty.writeAll(input.bytes[0..input.len]),
            .transcript => |transcript| try transcript.consume(.{ .write = input }),
        }
    }

    fn resize(self: *Transport, value: Geometry) Error!void {
        switch (self.*) {
            .native => |pty| try pty.resize(value),
            .transcript => |transcript| try transcript.consume(.{ .resize = value }),
        }
    }
};

/// Owns one stable terminal thread, command queue, PTY, VT, and publication.
const Owner = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    id: layout.TerminalId,
    mutex: std.Io.Mutex = .init,
    condition: std.Io.Condition = .init,
    queue: Queue = .{},
    thread: std.Thread = undefined,
    wake_fd: c_int,
    completion_fd: c_int,
    started: bool = false,
    stopping: bool = false,
    failure: ?Error = null,
    child: ?c.pid_t = null,
    snapshot: Snapshot,

    // Startup waits until both VT and PTY ownership are complete or rolled back.
    fn start(
        allocator: std.mem.Allocator,
        io: std.Io,
        id: layout.TerminalId,
        geometry: Geometry,
    ) Error!*Owner {
        return startExecutable(allocator, io, id, geometry, shell_path);
    }

    fn startExecutable(
        allocator: std.mem.Allocator,
        io: std.Io,
        id: layout.TerminalId,
        geometry: Geometry,
        executable: [:0]const u8,
    ) Error!*Owner {
        try validateGeometry(geometry);
        const self = try allocator.create(Owner);
        errdefer allocator.destroy(self);
        const wake_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (wake_fd < 0) return error.wake_failed;
        errdefer closeOwned(wake_fd);
        const completion_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (completion_fd < 0) return error.wake_failed;
        errdefer closeOwned(completion_fd);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .id = id,
            .wake_fd = wake_fd,
            .completion_fd = completion_fd,
            .snapshot = emptySnapshot(id, geometry),
        };
        self.thread = try std.Thread.spawn(.{}, threadMain, .{ self, geometry, executable });
        self.mutex.lockUncancelable(io);
        while (!self.started) self.condition.waitUncancelable(io, &self.mutex);
        const failure = self.failure;
        self.mutex.unlock(io);
        if (failure) |cause| {
            self.thread.join();
            return cause;
        }
        return self;
    }

    // The main thread polls this descriptor alongside Wayland and rendering.
    fn completionFd(self: *const Owner) c_int {
        return self.completion_fd;
    }

    // Input bytes are copied before the caller can release or mutate them.
    fn input(self: *Owner, bytes: []const u8) Error!void {
        try self.checkAdmission();
        if (bytes.len == 0) return;
        if (bytes.len > max_input_bytes) return error.input_too_large;
        var command = Input{
            .len = @intCast(bytes.len),
            .bytes = .{0} ** max_input_bytes,
        };
        @memcpy(command.bytes[0..bytes.len], bytes);
        try self.submit(.{ .input = command });
    }

    // Named keys retain modifiers until the VT owner encodes its current mode.
    fn key(self: *Owner, command: KeyCommand) Error!void {
        try self.checkAdmission();
        if (command.action == .release)
            try self.submitKeyRelease(.{ .key = command })
        else
            try self.submit(.{ .key = command });
    }

    // Unicode key identity and committed text remain one atomic VT command.
    fn unicodeKey(self: *Owner, command: UnicodeKeyCommand) Error!void {
        try self.checkAdmission();
        if (!std.unicode.utf8ValidCodepoint(command.codepoint))
            return error.invalid_key;
        if (command.action == .release)
            try self.submitKeyRelease(.{ .unicode_key = command })
        else
            try self.submit(.{ .unicode_key = command });
    }

    // Mouse facts retain target identity and modifiers until VT mode encoding.
    fn mouse(self: *Owner, command: MouseCommand) Error!void {
        try self.checkAdmission();
        try validateMouse(command);
        if (command.kind == .move)
            try self.submitMouseMotion(command)
        else if (command.kind == .release)
            try self.submitMouseRelease(command)
        else
            try self.submit(.{ .mouse = command });
    }

    // Focus is encoded by the VT owner against its current DEC 1004 mode.
    fn focus(self: *Owner, focused: bool) Error!void {
        try self.checkAdmission();
        try self.submit(.{ .focus = focused });
    }

    // Geometry enters the queue only after the complete bound is accepted.
    fn resize(self: *Owner, geometry: Geometry) Error!void {
        try self.checkAdmission();
        try validateGeometry(geometry);
        try self.submit(.{ .resize = geometry });
    }

    // One drain observes every coalesced publication preceding it.
    fn copySnapshot(self: *Owner) Error!Snapshot {
        var value: u64 = 0;
        const count = c.read(self.completion_fd, &value, @sizeOf(u64));
        if (count < 0 and std.posix.errno(count) != .AGAIN) return error.wake_failed;
        if (count >= 0 and count != @sizeOf(u64)) return error.wake_failed;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        return self.snapshot;
    }

    fn peekSnapshot(self: *Owner) Error!Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        return self.snapshot;
    }

    // Joining precedes descriptor and allocation release.
    fn deinit(self: *Owner) Error!void {
        const stop = self.requestStop();
        self.thread.join();
        const failure = self.failure;
        var close_failure = false;
        if (c.close(self.wake_fd) != 0) close_failure = true;
        if (c.close(self.completion_fd) != 0) close_failure = true;
        const allocator = self.allocator;
        allocator.destroy(self);
        if (stop.prior_failure) |cause| return cause;
        if (stop.request_failure) |cause| return cause;
        if (failure) |cause| return cause;
        if (close_failure) return error.descriptor_close_failed;
    }

    fn submit(self: *Owner, command: Command) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.owner_stopping;
        try self.queue.push(command);
        signalFd(self.wake_fd) catch |failure| {
            self.queue.discardNewest();
            self.failure = failure;
            return failure;
        };
    }

    fn submitMouseRelease(self: *Owner, command: MouseCommand) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.owner_stopping;
        try self.queue.pushMouseRelease(command);
        signalFd(self.wake_fd) catch |failure| {
            self.queue.discardNewest();
            self.failure = failure;
            return failure;
        };
    }

    fn submitKeyRelease(self: *Owner, command: Command) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.owner_stopping;
        try self.queue.pushKeyRelease(command);
        signalFd(self.wake_fd) catch |failure| {
            self.queue.discardNewest();
            self.failure = failure;
            return failure;
        };
    }

    fn submitMouseMotion(self: *Owner, command: MouseCommand) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.owner_stopping;
        switch (self.queue.pushMouseMotion(command)) {
            .replaced, .dropped => return,
            .appended => {},
        }
        signalFd(self.wake_fd) catch |failure| {
            self.queue.discardNewest();
            self.failure = failure;
            return failure;
        };
    }

    fn checkAdmission(self: *Owner) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.owner_stopping;
    }

    fn requestStop(self: *Owner) StopRequest {
        self.mutex.lockUncancelable(self.io);
        const prior_failure = self.failure;
        if (self.stopping) {
            self.mutex.unlock(self.io);
            return .{ .prior_failure = prior_failure, .request_failure = null };
        }
        self.stopping = true;
        const child = self.child;
        self.mutex.unlock(self.io);
        signalFd(self.wake_fd) catch |failure| {
            if (child) |pid| signalChild(pid, c.SIGHUP) catch
                return .{ .prior_failure = prior_failure, .request_failure = failure };
            return .{ .prior_failure = prior_failure, .request_failure = failure };
        };
        return .{ .prior_failure = prior_failure, .request_failure = null };
    }

    fn threadMain(self: *Owner, geometry: Geometry, executable: [:0]const u8) void {
        var terminal = howl_vt.Terminal.init(self.allocator, geometry.rows, geometry.cols) catch |failure| {
            self.finishStart(failure);
            return;
        };
        defer terminal.deinit();
        terminal.setCellPixelSize(geometry.cell_width, geometry.cell_height) catch |failure| {
            self.finishStart(failure);
            return;
        };
        var transport = Transport{ .native = Pty.open(geometry, executable) catch |failure| {
            self.finishStart(failure);
            return;
        } };
        self.mutex.lockUncancelable(self.io);
        self.child = transport.native.child;
        self.mutex.unlock(self.io);
        self.publish(&terminal) catch |failure| {
            transport.native.stop() catch |cleanup| {
                self.finishStart(cleanup);
                return;
            };
            self.finishStart(failure);
            return;
        };
        self.finishStart(null);
        var active = true;
        while (active) {
            var fds = [_]std.posix.pollfd{
                .{
                    .fd = transport.native.master_fd,
                    .events = std.posix.POLL.IN | std.posix.POLL.HUP,
                    .revents = 0,
                },
                .{ .fd = self.wake_fd, .events = std.posix.POLL.IN, .revents = 0 },
            };
            const ready = std.posix.poll(&fds, -1) catch {
                self.setFailure(error.wait_failed);
                break;
            };
            if (ready == 0) {
                self.setFailure(error.wait_failed);
                break;
            }
            if (fds[1].revents & std.posix.POLL.IN != 0) {
                drainFd(self.wake_fd) catch |failure| {
                    self.setFailure(failure);
                    break;
                };
                active = self.consumeCommands(&terminal, &transport);
            }
            if (active and fds[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0)
                self.readPty(&terminal, transport.native);
            if (active and self.failure == null and fds[0].revents & std.posix.POLL.HUP != 0) {
                self.setFailure(error.child_exited);
                active = false;
            }
            if (self.failure != null) active = false;
        }
        transport.native.stop() catch |failure| self.setFailure(failure);
    }

    fn consumeCommands(
        self: *Owner,
        terminal: *howl_vt.Terminal,
        transport: *Transport,
    ) bool {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            if (self.stopping) {
                // Shutdown revokes queued work before touching its PTY effects.
                self.queue = .{};
                self.mutex.unlock(self.io);
                return false;
            }
            const command = self.queue.pop();
            self.mutex.unlock(self.io);
            const next = command orelse return true;
            const active = applyCommand(
                terminal,
                self.allocator,
                transport,
                next,
            ) catch |failure| {
                self.setFailure(failure);
                return false;
            };
            if (!active) return false;
            if (next == .resize) {
                self.publish(terminal) catch |failure| {
                    self.setFailure(failure);
                    return false;
                };
            }
        }
    }

    fn readPty(self: *Owner, terminal: *howl_vt.Terminal, pty: Pty) void {
        var bytes: [read_bytes]u8 = undefined;
        var changed = false;
        while (true) {
            const count = c.read(pty.master_fd, &bytes, bytes.len);
            if (count < 0) {
                const errno = std.posix.errno(count);
                if (errno == .INTR) continue;
                if (errno == .AGAIN) break;
                if (errno == .IO) {
                    self.finishRead(terminal, changed, error.child_exited);
                    return;
                }
                self.finishRead(terminal, changed, error.pty_read_failed);
                return;
            }
            if (count == 0) {
                self.finishRead(terminal, changed, error.child_exited);
                return;
            }
            const summary = terminal.feed(bytes[0..@intCast(count)]) catch |failure| {
                self.setFailure(failure);
                return;
            };
            const reply = terminal.drainPendingOutput(self.allocator) catch |failure| {
                self.setFailure(failure);
                return;
            };
            defer self.allocator.free(reply);
            pty.writeAll(reply) catch |failure| {
                self.setFailure(failure);
                return;
            };
            changed = changed or summary.state_changed or
                summary.title_changed or summary.icon_changed;
        }
        if (changed) self.publish(terminal) catch |failure| self.setFailure(failure);
    }

    fn finishRead(
        self: *Owner,
        terminal: *howl_vt.Terminal,
        changed: bool,
        failure: Error,
    ) void {
        if (changed) self.publish(terminal) catch |cause| {
            self.setFailure(cause);
            return;
        };
        self.setFailure(failure);
    }

    fn publish(self: *Owner, terminal: *howl_vt.Terminal) Error!void {
        const surface = terminal.surfaceSnapshot();
        self.mutex.lockUncancelable(self.io);
        const previous = self.snapshot;
        self.mutex.unlock(self.io);
        if (previous.generation == std.math.maxInt(u64))
            return error.publication_exhausted;
        const next = try prepareSnapshot(previous, surface);
        if (!terminal.ackSurface(surface.snapshot_seq))
            return error.publication_exhausted;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.snapshot = next;
        signalFd(self.completion_fd) catch |failure| {
            self.failure = failure;
        };
    }

    fn finishStart(self: *Owner, failure: ?Error) void {
        self.mutex.lockUncancelable(self.io);
        self.failure = failure;
        self.started = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
    }

    fn setFailure(self: *Owner, failure: Error) void {
        self.mutex.lockUncancelable(self.io);
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
        // Completion delivery is secondary after an operating failure; deinit
        // preserves and returns the first cause even if notification also fails.
        signalFd(self.completion_fd) catch return;
    }
};

fn prepareSnapshot(
    previous: Snapshot,
    surface: howl_vt.Terminal.SurfacePublication,
) error{ invalid_cell, invalid_geometry, invalid_metadata }!Snapshot {
    const view = surface.snapshot.view;
    const count = @as(usize, view.rows) * view.cols;
    if (count > max_cells) return error.invalid_geometry;
    var next = previous;
    next.generation += 1;
    next.rows = view.rows;
    next.cols = view.cols;
    next.cursor_row = view.cursor_row;
    next.cursor_col = view.cursor_col;
    next.cursor_visible = view.cursor_visible;
    next.cursor_shape = view.cursor_shape;
    next.cursor_color = surface.presentation.cursor orelse
        surface.presentation.foreground;
    next.cursor_text_color = surface.presentation.cursor_text orelse
        surface.presentation.background;
    next.title = try copyMetadata(surface.title);
    next.icon = try copyMetadata(surface.icon);
    next.shell_integration = if (surface.shell_integration) |integration| .{
        .version = integration.version,
        .shell = if (integration.shell) |shell| try copyShellName(shell) else null,
    } else null;
    next.shell_mark = .{
        .kind = surface.shell_mark.kind,
        .status = surface.shell_mark.status,
        .metadata = try copyMetadata(surface.shell_mark.metadata),
    };
    next.bell_generation = surface.bell_generation;
    next.is_alternate_screen = surface.is_alternate_screen;
    next.count = @intCast(count);
    for (0..view.rows) |row| for (0..view.cols) |col| {
        const cell = view.cellInfoAt(@intCast(row), @intCast(col));
        next.cells[row * view.cols + col] = try copyCell(
            cell.codepoint,
            cell.combining_len,
            cell.combining,
            cell.width,
            cell.height,
            cell.x,
            cell.y,
            cell.attrs,
            &surface.presentation,
        );
    };
    return next;
}

/// Owns all three stable terminal identities and their reverse-order lifecycle.
pub const Set = struct {
    owners: [layout.terminal_count]*Owner,
    cell_size: CellSize,

    /// Starts all owners transactionally at their fixed initial geometry.
    pub fn start(
        allocator: std.mem.Allocator,
        io: std.Io,
        snapshot: layout.Snapshot,
        cell_size: CellSize,
    ) Error!Set {
        return startExecutables(
            allocator,
            io,
            snapshot,
            cell_size,
            .{ shell_path, shell_path, shell_path },
        );
    }

    fn startExecutables(
        allocator: std.mem.Allocator,
        io: std.Io,
        snapshot: layout.Snapshot,
        cell_size: CellSize,
        executables: [layout.terminal_count][:0]const u8,
    ) Error!Set {
        if (cell_size.width == 0 or cell_size.height == 0)
            return error.invalid_geometry;
        var owners: [layout.terminal_count]*Owner = undefined;
        var count: usize = 0;
        errdefer while (count > 0) {
            count -= 1;
            owners[count].deinit() catch
                @panic("terminal startup rollback failed");
        };
        for (std.enums.values(layout.TerminalId)) |id| {
            const initial_geometry = geometryFor(snapshot, id, cell_size) orelse
                Geometry{ .cols = 80, .rows = 24 };
            owners[id.index()] = try Owner.startExecutable(
                allocator,
                io,
                id,
                initial_geometry,
                executables[id.index()],
            );
            count += 1;
        }
        return .{ .owners = owners, .cell_size = cell_size };
    }

    /// Routes copied text to the focused terminal identity.
    pub fn input(self: *Set, id: layout.TerminalId, bytes: []const u8) Error!void {
        try self.owners[id.index()].input(bytes);
    }

    /// Routes one named key to the focused terminal identity.
    pub fn key(self: *Set, id: layout.TerminalId, command: KeyCommand) Error!void {
        try self.owners[id.index()].key(command);
    }

    /// Routes one copied Unicode key and committed text to its terminal owner.
    pub fn unicodeKey(
        self: *Set,
        id: layout.TerminalId,
        command: UnicodeKeyCommand,
    ) Error!void {
        try self.owners[id.index()].unicodeKey(command);
    }

    /// Routes one pointer fact to the terminal under the pointer.
    pub fn mouse(self: *Set, id: layout.TerminalId, command: MouseCommand) Error!void {
        try self.owners[id.index()].mouse(command);
    }

    /// Routes compositor focus to the terminal's mode-aware encoder.
    pub fn focus(self: *Set, id: layout.TerminalId, focused: bool) Error!void {
        try self.owners[id.index()].focus(focused);
    }

    /// Applies complete geometry only to visible terminals.
    pub fn resizeVisible(self: *Set, snapshot: layout.Snapshot) Error!void {
        for (snapshot.visible()) |placement|
            try self.owners[placement.terminal.index()].resize(
                cellGeometry(placement.rect, self.cell_size),
            );
    }

    /// Returns the completion descriptor for one stable identity.
    pub fn completionFd(self: *const Set, id: layout.TerminalId) c_int {
        return self.owners[id.index()].completionFd();
    }

    /// Copies the latest terminal generation after one completion.
    pub fn copySnapshot(self: *Set, id: layout.TerminalId) Error!Snapshot {
        return self.owners[id.index()].copySnapshot();
    }

    /// Copies all three current immutable terminal generations.
    pub fn snapshots(self: *Set) Error![layout.terminal_count]Snapshot {
        var values: [layout.terminal_count]Snapshot = undefined;
        for (std.enums.values(layout.TerminalId)) |id|
            values[id.index()] = try self.owners[id.index()].peekSnapshot();
        return values;
    }

    /// Stops, joins, and releases all owners in reverse identity order.
    pub fn deinit(self: *Set) Error!void {
        var failure: ?Error = null;
        var index = self.owners.len;
        while (index > 0) {
            index -= 1;
            self.owners[index].deinit() catch |cause| {
                if (failure == null) failure = cause;
            };
        }
        if (failure) |cause| return cause;
    }
};

fn geometryFor(
    snapshot: layout.Snapshot,
    id: layout.TerminalId,
    cell_size: CellSize,
) ?Geometry {
    for (snapshot.visible()) |placement|
        if (placement.terminal == id) return cellGeometry(placement.rect, cell_size);
    return null;
}

fn cellGeometry(rect: layout.Rect, cell_size: CellSize) Geometry {
    return .{
        .cols = @max(@as(u16, 1), rect.width / cell_size.width),
        .rows = @max(@as(u16, 1), rect.height / cell_size.height),
        .cell_width = cell_size.width,
        .cell_height = cell_size.height,
    };
}

/// Reports whether one publication exactly fills its metric-derived placement.
pub fn matchesPlacement(
    snapshot: *const Snapshot,
    placement: layout.Placement,
    cell_size: CellSize,
) bool {
    if (cell_size.width == 0 or cell_size.height == 0 or
        snapshot.terminal != placement.terminal)
        return false;
    const geometry = cellGeometry(placement.rect, cell_size);
    return snapshot.cols == geometry.cols and snapshot.rows == geometry.rows and
        snapshot.count == @as(u32, geometry.cols) * geometry.rows;
}

fn copyCell(
    codepoint: u32,
    combining_len: u8,
    combining: [max_combining]u32,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
    attrs: howl_vt.Terminal.CellAttrs,
    presentation: *const howl_vt.Terminal.Presentation,
) error{invalid_cell}!Cell {
    if (combining_len > max_combining) return error.invalid_cell;
    var foreground = attrs.fg.resolve(
        presentation.foreground,
        &presentation.palette,
    );
    var background = attrs.bg.resolve(
        presentation.background,
        &presentation.palette,
    );
    if (attrs.reverse != presentation.reverse_screen)
        std.mem.swap(howl_vt.Terminal.Rgb, &foreground, &background);
    var copied = Cell{
        .codepoint = std.math.cast(u21, codepoint) orelse
            return error.invalid_cell,
        .combining_len = combining_len,
        .width = width,
        .height = height,
        .x = x,
        .y = y,
        .foreground = foreground,
        .background = background,
        .underline_color = attrs.underline_color.resolve(
            foreground,
            &presentation.palette,
        ),
        .dim = attrs.dim,
        .invisible = attrs.invisible,
        .underline = attrs.underline,
        .underline_style = attrs.underline_style,
        .strikethrough = attrs.strikethrough,
    };
    for (0..combining_len) |index|
        copied.combining[index] = std.math.cast(
            u21,
            combining[index],
        ) orelse return error.invalid_cell;
    return copied;
}

fn copyMetadata(value: ?[]const u8) error{invalid_metadata}!Metadata {
    const bytes = value orelse return .{};
    if (bytes.len > metadata_max_bytes) return error.invalid_metadata;
    var copied = Metadata{};
    if (bytes.len != 0) @memcpy(copied.bytes[0..bytes.len], bytes);
    copied.len = std.math.cast(u16, bytes.len) orelse
        return error.invalid_metadata;
    return copied;
}

fn copyShellName(value: []const u8) error{invalid_metadata}!ShellName {
    if (value.len > howl_vt.Terminal.shell_name_max_bytes)
        return error.invalid_metadata;
    var copied = ShellName{};
    if (value.len != 0) @memcpy(copied.bytes[0..value.len], value);
    copied.len = std.math.cast(u8, value.len) orelse
        return error.invalid_metadata;
    return copied;
}

fn validateGeometry(value: Geometry) Error!void {
    if (value.rows == 0 or value.cols == 0 or
        value.rows > max_rows or value.cols > max_cols or
        value.cell_width == 0 or value.cell_height == 0)
        return error.invalid_geometry;
}

fn emptySnapshot(id: layout.TerminalId, value: Geometry) Snapshot {
    return .{
        .terminal = id,
        .generation = 0,
        .rows = value.rows,
        .cols = value.cols,
        .cursor_row = 0,
        .cursor_col = 0,
        .cursor_visible = true,
        .cursor_shape = .block,
        .cursor_color = howl_vt.Terminal.default_presentation.foreground,
        .cursor_text_color = howl_vt.Terminal.default_presentation.background,
        .count = 0,
        .cells = .{blank_cell} ** max_cells,
    };
}

fn writeLaunchFailure(fd: c_int) void {
    const marker: u8 = 1;
    while (true) {
        const count = c.write(fd, &marker, @sizeOf(u8));
        if (count == @sizeOf(u8)) return;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        c._exit(124);
    }
}

fn readLaunchStatus(fd: c_int) error{child_launch_failed}!bool {
    var marker: u8 = 0;
    while (true) {
        const count = c.read(fd, &marker, @sizeOf(u8));
        if (count == 0) return true;
        if (count == @sizeOf(u8)) return false;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        return error.child_launch_failed;
    }
}

fn signalFd(fd: c_int) Error!void {
    const value: u64 = 1;
    const count = c.write(fd, &value, @sizeOf(u64));
    if (count != @sizeOf(u64) and
        !(count < 0 and std.posix.errno(count) == .AGAIN))
        return error.wake_failed;
}

fn drainFd(fd: c_int) Error!void {
    var value: u64 = 0;
    const count = c.read(fd, &value, @sizeOf(u64));
    if (count != @sizeOf(u64) and
        !(count < 0 and std.posix.errno(count) == .AGAIN))
        return error.wake_failed;
}

fn closeOwned(fd: c_int) void {
    if (c.close(fd) != 0)
        @panic("Linux rejected an owned terminal descriptor during rollback");
}

fn rollbackChild(master_fd: c_int, child: c.pid_t) void {
    signalChild(child, c.SIGKILL) catch
        @panic("Linux rejected terminal child rollback signal");
    waitForChild(child) catch
        @panic("Linux rejected terminal child rollback wait");
    closeOwned(master_fd);
}

fn signalChild(child: c.pid_t, signal: c_int) error{signal_failed}!void {
    const group_result = c.kill(-child, signal);
    if (group_result == 0) return;
    if (std.posix.errno(group_result) != .SRCH) return error.signal_failed;
    // forkpty establishes the child's process group in the child. Rollback can
    // race that transition, so an absent group is signaled by PID instead.
    const child_result = c.kill(child, signal);
    if (child_result != 0 and std.posix.errno(child_result) != .SRCH)
        return error.signal_failed;
}

fn waitForChild(child: c.pid_t) error{child_wait_failed}!void {
    var status: c_int = 0;
    while (true) {
        const waited = c.waitpid(child, &status, 0);
        if (waited == child) return;
        if (waited < 0 and std.posix.errno(waited) == .INTR) continue;
        if (waited < 0 and std.posix.errno(waited) == .CHILD) return;
        return error.child_wait_failed;
    }
}

fn encodeNamed(
    terminal: *howl_vt.Terminal,
    allocator: std.mem.Allocator,
    scratch: *howl_vt.Terminal.InputScratch,
    command: KeyCommand,
) howl_vt.Terminal.InputError!howl_vt.Terminal.EncodedInput {
    const named: howl_vt.Terminal.NamedKey = switch (command.named) {
        inline else => |value| @field(
            howl_vt.Terminal.NamedKey,
            @tagName(value),
        ),
    };
    return terminal.encodeInput(allocator, scratch, .{ .key = .{
        .key = .{ .named = named },
        .mods = .{
            .shift = command.shift,
            .alt = command.alt,
            .control = command.control,
            .super = command.super,
            .hyper = command.hyper,
            .meta = command.meta,
            .caps_lock = command.caps_lock,
            .num_lock = command.num_lock,
        },
        .action = switch (command.action) {
            .press => .press,
            .repeat => .repeat,
            .release => .release,
        },
    } });
}

fn encodeUnicode(
    terminal: *howl_vt.Terminal,
    allocator: std.mem.Allocator,
    scratch: *howl_vt.Terminal.InputScratch,
    command: UnicodeKeyCommand,
) howl_vt.Terminal.InputError!howl_vt.Terminal.EncodedInput {
    @memcpy(
        scratch.buf[0..command.legacy.len],
        command.legacy.bytes[0..command.legacy.len],
    );
    return terminal.encodeInput(allocator, scratch, .{
        .key = .{
            // Admission validates this copied scalar before it enters the queue.
            .key = howl_vt.Terminal.Key.initUnicode(command.codepoint) catch unreachable,
            .mods = .{
                .shift = command.shift,
                .alt = command.alt,
                .control = command.control,
                .super = command.super,
                .hyper = command.hyper,
                .meta = command.meta,
                .caps_lock = command.caps_lock,
                .num_lock = command.num_lock,
            },
            .action = switch (command.action) {
                .press => .press,
                .repeat => .repeat,
                .release => .release,
            },
            .shifted = command.shifted,
            .alternate = command.alternate,
            // Legacy bytes must outlive this by-value command copy when the
            // returned encoding borrows caller scratch.
            .legacy_text = scratch.buf[0..command.legacy.len],
            .text = command.text.bytes[0..command.text.len],
        },
    });
}

fn applyCommand(
    terminal: *howl_vt.Terminal,
    allocator: std.mem.Allocator,
    transport: *Transport,
    command: Command,
) Error!bool {
    switch (command) {
        .input => |input| try transport.writeAll(input),
        .key => |named| {
            var scratch: howl_vt.Terminal.InputScratch = .{};
            var encoded = try encodeNamed(terminal, allocator, &scratch, named);
            defer encoded.deinit();
            try transport.writeAll(try inputValue(encoded.bytes));
        },
        .unicode_key => |unicode| {
            var scratch: howl_vt.Terminal.InputScratch = .{};
            var encoded = try encodeUnicode(terminal, allocator, &scratch, unicode);
            defer encoded.deinit();
            try transport.writeAll(try inputValue(encoded.bytes));
        },
        .mouse => |mouse| {
            for (0..mouse.wheel_steps) |_| {
                var scratch: howl_vt.Terminal.InputScratch = .{};
                var encoded = try terminal.encodeInput(allocator, &scratch, .{ .mouse = .{
                    .kind = switch (mouse.kind) {
                        .press => .press,
                        .release => .release,
                        .move => .move,
                        .wheel => .wheel,
                    },
                    .button = switch (mouse.button) {
                        .none => .none,
                        .left => .left,
                        .middle => .middle,
                        .right => .right,
                        .wheel_up => .wheel_up,
                        .wheel_down => .wheel_down,
                    },
                    .row = mouse.row,
                    .col = mouse.col,
                    .pixel_x = mouse.pixel_x,
                    .pixel_y = mouse.pixel_y,
                    .mod = .{
                        .shift = mouse.shift,
                        .alt = mouse.alt,
                        .control = mouse.control,
                    },
                    .buttons_down = mouse.buttons_down,
                } });
                defer encoded.deinit();
                if (encoded.bytes.len != 0)
                    try transport.writeAll(try inputValue(encoded.bytes));
            }
        },
        .focus => |focused| {
            var scratch: howl_vt.Terminal.InputScratch = .{};
            var encoded = try terminal.encodeInput(allocator, &scratch, .{
                .focus = if (focused) .in else .out,
            });
            defer encoded.deinit();
            if (encoded.bytes.len != 0)
                try transport.writeAll(try inputValue(encoded.bytes));
        },
        .resize => |value| {
            try transport.resize(value);
            try terminal.resize(value.rows, value.cols);
            try terminal.setCellPixelSize(value.cell_width, value.cell_height);
        },
    }
    return true;
}

fn inputValue(bytes: []const u8) Error!Input {
    if (bytes.len > max_input_bytes) return error.input_too_large;
    var value = Input{
        .len = @intCast(bytes.len),
        .bytes = .{0} ** max_input_bytes,
    };
    @memcpy(value.bytes[0..bytes.len], bytes);
    return value;
}

fn validateMouse(command: MouseCommand) error{invalid_mouse}!void {
    if (command.row >= max_rows or command.col >= max_cols or
        command.buttons_down & ~@as(u8, 0x07) != 0)
        return error.invalid_mouse;
    if (command.wheel_steps == 0 or command.wheel_steps > max_wheel_steps)
        return error.invalid_mouse;
    switch (command.kind) {
        .move => if (command.button != .none or command.wheel_steps != 1)
            return error.invalid_mouse,
        .wheel => if (command.button != .wheel_up and command.button != .wheel_down)
            return error.invalid_mouse,
        .press, .release => if (command.button != .left and
            command.button != .middle and command.button != .right)
            return error.invalid_mouse,
    }
    if (command.kind != .wheel and command.wheel_steps != 1)
        return error.invalid_mouse;
}

test "command queue preserves identity bounds and overflow" {
    var queue = Queue{};
    for (0..command_capacity) |index|
        try queue.push(.{ .resize = .{ .rows = 1, .cols = @intCast(index + 1) } });
    try std.testing.expectError(
        error.command_queue_full,
        queue.push(.{ .resize = .{ .rows = 1, .cols = 1 } }),
    );
    queue.discardNewest();
    try queue.push(.{ .resize = .{ .rows = 1, .cols = command_capacity } });
    for (1..command_capacity + 1) |expected| {
        const command = queue.pop().?;
        try std.testing.expectEqual(@as(u16, @intCast(expected)), command.resize.cols);
    }
    try std.testing.expect(queue.pop() == null);
}

test "command queue reserves exactly three physical mouse releases" {
    var queue = Queue{};
    for (0..command_capacity) |index|
        try queue.push(.{ .resize = .{
            .rows = 1,
            .cols = @intCast(index + 1),
        } });
    const release = MouseCommand{
        .kind = .release,
        .button = .left,
        .row = 0,
        .col = 0,
        .pixel_x = 0,
        .pixel_y = 0,
        .shift = false,
        .alt = false,
        .control = false,
        .buttons_down = 0,
    };
    try queue.pushMouseRelease(release);
    var middle = release;
    middle.button = .middle;
    try queue.pushMouseRelease(middle);
    var right = release;
    right.button = .right;
    try queue.pushMouseRelease(right);
    try std.testing.expectError(
        error.command_queue_full,
        queue.pushMouseRelease(release),
    );
    for (0..command_capacity) |_| try std.testing.expect(queue.pop().? == .resize);
    try std.testing.expectEqual(MouseButton.left, queue.pop().?.mouse.button);
    try std.testing.expectEqual(MouseButton.middle, queue.pop().?.mouse.button);
    try std.testing.expectEqual(MouseButton.right, queue.pop().?.mouse.button);
    try std.testing.expect(queue.pop() == null);
}

test "command queue reserves every accepted physical key release" {
    var queue: Queue = .{};
    for (0..command_capacity) |index|
        try queue.push(.{ .resize = .{
            .rows = 1,
            .cols = @intCast(index + 1),
        } });
    const release = KeyCommand{
        .named = .left_shift,
        .action = .release,
        .shift = false,
        .alt = false,
        .control = false,
    };
    for (0..max_pressed_keys) |_| try queue.pushKeyRelease(.{ .key = release });
    try std.testing.expectEqual(max_pressed_keys, queue.key_releases);
    try std.testing.expectError(
        error.command_queue_full,
        queue.pushKeyRelease(.{ .key = release }),
    );
    for (0..command_capacity) |_| try std.testing.expect(queue.pop().? == .resize);
    for (0..max_pressed_keys) |_|
        try std.testing.expect(queue.pop().?.key.action == .release);
    try std.testing.expectEqual(@as(usize, 0), queue.key_releases);
    try std.testing.expect(queue.pop() == null);

    try queue.pushKeyRelease(.{ .key = release });
    queue.discardNewest();
    try std.testing.expectEqual(@as(usize, 0), queue.key_releases);
    try std.testing.expect(queue.pop() == null);

    try queue.pushKeyRelease(.{ .unicode_key = .{
        .codepoint = 'a',
        .text = .{},
        .action = .release,
        .shift = false,
        .alt = false,
        .control = false,
    } });
    try std.testing.expect(queue.pop().?.unicode_key.action == .release);
    try std.testing.expectEqual(@as(usize, 0), queue.key_releases);
}

test "motion bursts coalesce without crossing ordered pointer transitions" {
    const motion = MouseCommand{
        .kind = .move,
        .button = .none,
        .row = 1,
        .col = 1,
        .pixel_x = 8,
        .pixel_y = 16,
        .shift = false,
        .alt = false,
        .control = false,
        .buttons_down = 0,
    };
    var queue = Queue{};
    try std.testing.expectEqual(Queue.MotionAdmission.appended, queue.pushMouseMotion(motion));
    var latest = motion;
    latest.col = 2;
    try std.testing.expectEqual(Queue.MotionAdmission.replaced, queue.pushMouseMotion(latest));
    var press = latest;
    press.kind = .press;
    press.button = .left;
    press.buttons_down = 1;
    try queue.push(.{ .mouse = press });
    var drag = latest;
    drag.col = 3;
    drag.buttons_down = 1;
    try std.testing.expectEqual(Queue.MotionAdmission.appended, queue.pushMouseMotion(drag));
    var release = drag;
    release.kind = .release;
    release.button = .left;
    release.buttons_down = 0;
    try queue.pushMouseRelease(release);
    var hover = motion;
    for (0..1000) |index| {
        hover.col = @intCast(index % max_cols);
        const admission = queue.pushMouseMotion(hover);
        try std.testing.expect(admission == .appended or admission == .replaced);
    }

    try std.testing.expectEqual(@as(u16, 2), queue.pop().?.mouse.col);
    try std.testing.expectEqual(MouseKind.press, queue.pop().?.mouse.kind);
    try std.testing.expectEqual(@as(u16, 3), queue.pop().?.mouse.col);
    try std.testing.expectEqual(MouseKind.release, queue.pop().?.mouse.kind);
    try std.testing.expectEqual(hover.col, queue.pop().?.mouse.col);
    try std.testing.expect(queue.pop() == null);

    for (0..command_capacity) |index|
        try queue.push(.{ .resize = .{
            .rows = 1,
            .cols = @intCast(index + 1),
        } });
    try std.testing.expectEqual(Queue.MotionAdmission.appended, queue.pushMouseMotion(motion));
    try queue.pushMouseRelease(release);
    var middle = release;
    middle.button = .middle;
    try queue.pushMouseRelease(middle);
    var right = release;
    right.button = .right;
    try queue.pushMouseRelease(right);
    try std.testing.expectEqual(Queue.MotionAdmission.dropped, queue.pushMouseMotion(latest));
}

test "mouse command vocabulary rejects impossible bounded combinations" {
    const valid = MouseCommand{
        .kind = .move,
        .button = .none,
        .row = max_rows - 1,
        .col = max_cols - 1,
        .pixel_x = std.math.maxInt(u16),
        .pixel_y = std.math.maxInt(u16),
        .shift = false,
        .alt = false,
        .control = false,
        .buttons_down = 0x07,
    };
    try validateMouse(valid);
    var invalid = valid;
    invalid.row = max_rows;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid = valid;
    invalid.col = max_cols;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid = valid;
    invalid.buttons_down = 0x08;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid = valid;
    invalid.button = .left;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid = valid;
    invalid.kind = .wheel;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid.button = .wheel_up;
    invalid.wheel_steps = 0;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid.wheel_steps = max_wheel_steps + 1;
    try std.testing.expectError(error.invalid_mouse, validateMouse(invalid));
    invalid.wheel_steps = max_wheel_steps;
    try validateMouse(invalid);
}

test "strict PTY transcript consumes input resize and key exactly" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer terminal.deinit();
    const steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("hello") } },
        .{ .operation = .{ .resize = .{ .rows = 10, .cols = 30 } } },
        .{ .operation = .{ .write = try inputValue("\x1b[A") } },
    };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .input = try inputValue("hello") },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .resize = .{ .rows = 10, .cols = 30 } },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = .{
            .named = .up,
            .shift = false,
            .alt = false,
            .control = false,
        } },
    ));
    try transcript.finish();
    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u16, 10), view.rows);
    try std.testing.expectEqual(@as(u16, 30), view.cols);
}

test "Unicode command crosses VT Kitty negotiation without bypassing encoding" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer terminal.deinit();
    const enabled = try terminal.feed("\x1b[=8u");
    try std.testing.expect(enabled.state_changed);
    const command = UnicodeKeyCommand{
        .codepoint = 'a',
        .shifted = 'A',
        .text = try inputValue("A"),
        .shift = true,
        .alt = false,
        .control = false,
    };
    const steps = [_]Step{.{ .operation = .{
        .write = try inputValue("\x1b[97;2u"),
    } }};
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .unicode_key = command },
    ));
    try transcript.finish();
}

test "Unicode command preserves Kitty press repeat and release identity" {
    var vt = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer vt.deinit();
    const enabled = try vt.feed("\x1b[=31u");
    try std.testing.expect(enabled.state_changed);
    const steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1b[97:65;2;65u") } },
        .{ .operation = .{ .write = try inputValue("\x1b[97:65;2:2;65u") } },
        .{ .operation = .{ .write = try inputValue("\x1b[97:65;2:3u") } },
    };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    for ([_]KeyAction{ .press, .repeat, .release }) |action| {
        const command = UnicodeKeyCommand{
            .codepoint = 'a',
            .shifted = 'A',
            .text = if (action == .release) try inputValue("") else try inputValue("A"),
            .action = action,
            .shift = true,
            .alt = false,
            .control = false,
        };
        try std.testing.expect(try applyCommand(
            &vt,
            std.testing.allocator,
            &transport,
            .{ .unicode_key = command },
        ));
    }
    try transcript.finish();
}

test "Unicode command separates legacy transformations from Kitty text" {
    var vt = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer vt.deinit();
    var scratch: howl_vt.Terminal.InputScratch = .{};
    var legacy_probe = try encodeUnicode(&vt, std.testing.allocator, &scratch, .{
        .codepoint = 'a',
        .legacy = try inputValue("\x1ba"),
        .text = try inputValue("a"),
        .shift = false,
        .alt = true,
        .control = false,
    });
    defer legacy_probe.deinit();
    try std.testing.expectEqualStrings("\x1ba", legacy_probe.bytes);
    const steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1ba") } },
        .{ .operation = .{ .write = try inputValue("\x01") } },
        .{ .operation = .{ .write = try inputValue("\x1b[97;3;97:233u") } },
    };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &vt,
        std.testing.allocator,
        &transport,
        .{ .unicode_key = .{
            .codepoint = 'a',
            .legacy = try inputValue("\x1ba"),
            .text = try inputValue("a"),
            .shift = false,
            .alt = true,
            .control = false,
        } },
    ));
    try std.testing.expect(try applyCommand(
        &vt,
        std.testing.allocator,
        &transport,
        .{ .unicode_key = .{
            .codepoint = 'a',
            .legacy = try inputValue("\x01"),
            .text = try inputValue("a"),
            .shift = false,
            .alt = false,
            .control = true,
        } },
    ));
    const enabled = try vt.feed("\x1b[=31u");
    try std.testing.expect(enabled.state_changed);
    try std.testing.expect(try applyCommand(
        &vt,
        std.testing.allocator,
        &transport,
        .{ .unicode_key = .{
            .codepoint = 'a',
            .legacy = try inputValue("\x1b\x01"),
            .text = try inputValue("aé"),
            .shift = false,
            .alt = true,
            .control = false,
        } },
    ));
    try transcript.finish();
}

test "named modifier commands preserve Super action and lock state" {
    var vt = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer vt.deinit();
    const enabled = try vt.feed("\x1b[=10u");
    try std.testing.expect(enabled.state_changed);
    const steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1b[57444;9u") } },
        .{ .operation = .{ .write = try inputValue("\x1b[57444;1:3u") } },
        .{ .operation = .{ .write = try inputValue("\x1b[57358;65u") } },
    };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    for ([_]KeyCommand{
        .{
            .named = .left_super,
            .shift = false,
            .alt = false,
            .control = false,
            .super = true,
        },
        .{
            .named = .left_super,
            .action = .release,
            .shift = false,
            .alt = false,
            .control = false,
        },
        .{
            .named = .caps_lock,
            .shift = false,
            .alt = false,
            .control = false,
            .caps_lock = true,
        },
    }) |command|
        try std.testing.expect(try applyCommand(
            &vt,
            std.testing.allocator,
            &transport,
            .{ .key = command },
        ));
    try transcript.finish();
}

test "keypad input preserves VT normal and application mode identity" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer terminal.deinit();
    const steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("0") } },
        .{ .operation = .{ .write = try inputValue("\x1bOp") } },
        .{ .operation = .{ .write = try inputValue("\x1bOl") } },
        .{ .operation = .{ .write = try inputValue("\x1bOX") } },
        .{ .operation = .{ .write = try inputValue("\x1bOM") } },
    };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    const keypad_zero = KeyCommand{
        .named = .keypad_0,
        .shift = false,
        .alt = false,
        .control = false,
    };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = keypad_zero },
    ));
    const application_mode = try terminal.feed("\x1b=");
    try std.testing.expect(application_mode.state_changed);
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = keypad_zero },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = .{
            .named = .keypad_separator,
            .shift = false,
            .alt = false,
            .control = false,
        } },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = .{
            .named = .keypad_equal,
            .shift = false,
            .alt = false,
            .control = false,
        } },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .key = .{
            .named = .keypad_enter,
            .shift = false,
            .alt = false,
            .control = false,
        } },
    ));
    try transcript.finish();
}

test "focus commands write only while DEC 1004 is enabled" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer terminal.deinit();
    const disabled_steps = [_]Step{};
    var disabled = Transcript{ .steps = &disabled_steps };
    var transport = Transport{ .transcript = &disabled };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .focus = true },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .focus = false },
    ));
    try disabled.finish();

    const enabled = try terminal.feed("\x1b[?1004h");
    try std.testing.expect(enabled.state_changed);
    try std.testing.expect(!enabled.title_changed);
    try std.testing.expect(!enabled.icon_changed);
    const enabled_steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1b[I") } },
        .{ .operation = .{ .write = try inputValue("\x1b[O") } },
    };
    var enabled_transcript = Transcript{ .steps = &enabled_steps };
    transport = .{ .transcript = &enabled_transcript };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .focus = true },
    ));
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .focus = false },
    ));
    try enabled_transcript.finish();

    const disabled_again = try terminal.feed("\x1b[?1004l");
    try std.testing.expect(disabled_again.state_changed);
    const reused_steps = [_]Step{};
    var reused = Transcript{ .steps = &reused_steps };
    transport = .{ .transcript = &reused };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .focus = true },
    ));
    try reused.finish();
}

test "mouse commands preserve howl-vt tracking and protocol semantics" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 8, 241);
    defer value.deinit();
    const press = MouseCommand{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = 24,
        .pixel_y = 32,
        .shift = false,
        .alt = false,
        .control = false,
        .buttons_down = 1,
    };

    const no_steps = [_]Step{};
    var transcript = Transcript{ .steps = &no_steps };
    var transport = Transport{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = press },
    ));
    try transcript.finish();

    const x10_summary = try value.feed("\x1b[?9h");
    try std.testing.expect(x10_summary.state_changed);
    const x10_steps = [_]Step{.{ .operation = .{
        .write = try inputValue("\x1b[M $#"),
    } }};
    transcript = .{ .steps = &x10_steps };
    transport = .{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = press },
    ));
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = .{
            .kind = .release,
            .button = .left,
            .row = 2,
            .col = 3,
            .pixel_x = 24,
            .pixel_y = 32,
            .shift = false,
            .alt = false,
            .control = false,
            .buttons_down = 0,
        } },
    ));
    try transcript.finish();

    const normal_summary = try value.feed("\x1b[?1000h");
    try std.testing.expect(normal_summary.state_changed);
    const normal_steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1b[M4$#") } },
        .{ .operation = .{ .write = try inputValue("\x1b[M#$#") } },
        .{ .operation = .{ .write = try inputValue("\x1b[Ma$#") } },
    };
    transcript = .{ .steps = &normal_steps };
    transport = .{ .transcript = &transcript };
    var modified = press;
    modified.shift = true;
    modified.control = true;
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = modified },
    ));
    var release = press;
    release.kind = .release;
    release.buttons_down = 0;
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = release },
    ));
    var wheel = release;
    wheel.kind = .wheel;
    wheel.button = .wheel_down;
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = wheel },
    ));
    try transcript.finish();

    const sgr_summary = try value.feed("\x1b[?1002h\x1b[?1006h");
    try std.testing.expect(sgr_summary.state_changed);
    const sgr_steps = [_]Step{
        .{ .operation = .{ .write = try inputValue("\x1b[<32;4;3M") } },
        .{ .operation = .{ .write = try inputValue("\x1b[<35;4;3M") } },
    };
    transcript = .{ .steps = &sgr_steps };
    transport = .{ .transcript = &transcript };
    var move = press;
    move.kind = .move;
    move.button = .none;
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = move },
    ));
    const motion_summary = try value.feed("\x1b[?1003h");
    try std.testing.expect(motion_summary.state_changed);
    move.buttons_down = 0;
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = move },
    ));
    try transcript.finish();

    const utf8_summary = try value.feed("\x1b[?1005h");
    try std.testing.expect(utf8_summary.state_changed);
    var far = press;
    far.col = 200;
    const utf8_steps = [_]Step{.{ .operation = .{
        .write = try inputValue("\x1b[M \xc3\xa9#"),
    } }};
    transcript = .{ .steps = &utf8_steps };
    transport = .{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = far },
    ));
    try transcript.finish();

    const urxvt_summary = try value.feed("\x1b[?1015h");
    try std.testing.expect(urxvt_summary.state_changed);
    const urxvt_steps = [_]Step{.{ .operation = .{
        .write = try inputValue("\x1b[32;201;3M"),
    } }};
    transcript = .{ .steps = &urxvt_steps };
    transport = .{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = far },
    ));
    try transcript.finish();
}

test "one bounded wheel command preserves every accepted detent" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer value.deinit();
    const summary = try value.feed("\x1b[?1000h\x1b[?1006h");
    try std.testing.expect(summary.state_changed);
    var steps: [max_wheel_steps]Step = undefined;
    for (&steps) |*step| step.* = .{ .operation = .{
        .write = try inputValue("\x1b[<65;4;3M"),
    } };
    var transcript = Transcript{ .steps = &steps };
    var transport = Transport{ .transcript = &transcript };
    try std.testing.expect(try applyCommand(
        &value,
        std.testing.allocator,
        &transport,
        .{ .mouse = .{
            .kind = .wheel,
            .button = .wheel_down,
            .row = 2,
            .col = 3,
            .pixel_x = 24,
            .pixel_y = 32,
            .shift = false,
            .alt = false,
            .control = false,
            .buttons_down = 0,
            .wheel_steps = max_wheel_steps,
        } },
    ));
    try transcript.finish();
}

test "PTY transcript failure preserves VT geometry and permits reuse" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 8, 20);
    defer terminal.deinit();
    const failed_steps = [_]Step{.{
        .operation = .{ .resize = .{ .rows = 10, .cols = 30 } },
        .failure = error.pty_resize_failed,
    }};
    var failed = Transcript{ .steps = &failed_steps };
    var transport = Transport{ .transcript = &failed };
    try std.testing.expectError(
        error.pty_resize_failed,
        applyCommand(
            &terminal,
            std.testing.allocator,
            &transport,
            .{ .resize = .{ .rows = 10, .cols = 30 } },
        ),
    );
    try failed.finish();
    try std.testing.expectEqual(@as(u16, 8), terminal.surfaceSnapshot().snapshot.view.rows);

    const reuse_steps = [_]Step{.{ .operation = .{
        .resize = .{ .rows = 9, .cols = 21 },
    } }};
    var reuse = Transcript{ .steps = &reuse_steps };
    transport = .{ .transcript = &reuse };
    try std.testing.expect(try applyCommand(
        &terminal,
        std.testing.allocator,
        &transport,
        .{ .resize = .{ .rows = 9, .cols = 21 } },
    ));
    try reuse.finish();
    try std.testing.expectEqual(@as(u16, 9), terminal.surfaceSnapshot().snapshot.view.rows);
}

test "pixel rectangles map to exact bounded cell geometry" {
    try std.testing.expectEqualDeep(
        Geometry{ .cols = 100, .rows = 30, .cell_width = 8, .cell_height = 16 },
        cellGeometry(
            .{ .x = 0, .y = 0, .width = 800, .height = 480 },
            test_cell_size,
        ),
    );
    try std.testing.expectEqualDeep(
        Geometry{ .cols = 80, .rows = 24, .cell_width = 10, .cell_height = 20 },
        cellGeometry(
            .{ .x = 0, .y = 0, .width = 800, .height = 480 },
            .{ .width = 10, .height = 20 },
        ),
    );
    try std.testing.expectError(
        error.invalid_geometry,
        validateGeometry(.{ .cols = max_cols + 1, .rows = 1 }),
    );
    try validateGeometry(.{ .cols = max_cols, .rows = max_rows });
}

test "host metric geometry drives exact iTerm cell-size report" {
    const geometry = cellGeometry(
        .{ .x = 0, .y = 0, .width = 900, .height = 360 },
        .{ .width = 9, .height = 18 },
    );
    var terminal = try howl_vt.Terminal.init(
        std.testing.allocator,
        geometry.rows,
        geometry.cols,
    );
    defer terminal.deinit();
    try terminal.setCellPixelSize(geometry.cell_width, geometry.cell_height);
    const summary = try terminal.feed("\x1b]1337;ReportCellSize\x07");
    try std.testing.expect(summary.state_changed);
    const reply = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(reply);
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        reply,
    );
}

test "frozen VT cell publication preserves three trailing scalars" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer value.deinit();
    const summary = try value.feed("o\xcc\x80\xcc\x81\xcc\x82");
    try std.testing.expect(summary.state_changed);
    const publication = value.surfaceSnapshot();
    const source = publication.snapshot.view.cellInfoAt(0, 0);
    const copied = try copyCell(
        source.codepoint,
        source.combining_len,
        source.combining,
        source.width,
        source.height,
        source.x,
        source.y,
        source.attrs,
        &publication.presentation,
    );
    var storage: [max_combining + 1]u32 = undefined;
    try std.testing.expectEqualSlices(
        u32,
        &.{ 'o', 0x0300, 0x0301, 0x0302 },
        copied.copyCodepoints(&storage),
    );
}

test "VT metadata copies are distinct bounded values across mutation" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer value.deinit();

    const initial = try value.feed("\x1b]2;title-one\x07\x1b]1;icon-one\x07");
    try std.testing.expect(initial.title_changed);
    try std.testing.expect(initial.icon_changed);
    const first = value.surfaceSnapshot();
    const first_snapshot = try prepareSnapshot(
        emptySnapshot(.first, .{ .rows = 2, .cols = 4 }),
        first,
    );
    try std.testing.expectEqual(@as(u64, 0), first_snapshot.bell_generation);

    const changed = try value.feed("\x1b]2;title-two\x07\x07\x1b[?1049h");
    try std.testing.expect(changed.title_changed);
    const second = value.surfaceSnapshot();
    const second_snapshot = try prepareSnapshot(first_snapshot, second);
    try std.testing.expectEqualStrings("title-one", first_snapshot.title.view());
    try std.testing.expectEqualStrings("icon-one", first_snapshot.icon.view());
    try std.testing.expect(!first_snapshot.is_alternate_screen);
    try std.testing.expectEqualStrings("title-two", second_snapshot.title.view());
    try std.testing.expectEqualStrings("icon-one", second_snapshot.icon.view());
    try std.testing.expectEqual(@as(u64, 1), second_snapshot.bell_generation);
    try std.testing.expect(second_snapshot.is_alternate_screen);
    try std.testing.expectEqual(
        @as(u8, 0),
        second_snapshot.title.bytes[second_snapshot.title.len],
    );

    const oversized = [_]u8{'x'} ** (metadata_max_bytes + 1);
    try std.testing.expectError(error.invalid_metadata, copyMetadata(&oversized));
    const shell_boundary = [_]u8{'s'} ** howl_vt.Terminal.shell_name_max_bytes;
    const copied_shell = try copyShellName(&shell_boundary);
    try std.testing.expectEqualSlices(u8, &shell_boundary, copied_shell.view());
    const shell_oversized = [_]u8{'s'} ** (howl_vt.Terminal.shell_name_max_bytes + 1);
    try std.testing.expectError(error.invalid_metadata, copyShellName(&shell_oversized));
    try std.testing.expectEqualStrings("title-two", second_snapshot.title.view());
}

test "iTerm shell metadata copies into an immutable host generation" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer value.deinit();
    const summary = try value.feed(
        "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07" ++
            "\x1b]133;D;17\x07",
    );
    try std.testing.expect(summary.state_changed);
    const first = try prepareSnapshot(
        emptySnapshot(.first, .{ .rows = 2, .cols = 4 }),
        value.surfaceSnapshot(),
    );
    try std.testing.expectEqual(@as(u32, 20), first.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", first.shell_integration.?.shell.?.view());
    try std.testing.expectEqual(@as(u8, 'D'), first.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 17), first.shell_mark.status);
    try std.testing.expectEqualStrings("17", first.shell_mark.metadata.view());

    const changed = try value.feed("\x1b]1337;ShellIntegrationVersion=21;shell=zsh\x07\x1b]133;A\x07");
    try std.testing.expect(changed.state_changed);
    const second = try prepareSnapshot(first, value.surfaceSnapshot());
    try std.testing.expectEqual(@as(u32, 20), first.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", first.shell_integration.?.shell.?.view());
    try std.testing.expectEqualStrings("17", first.shell_mark.metadata.view());
    try std.testing.expectEqual(@as(u32, 21), second.shell_integration.?.version);
    try std.testing.expectEqualStrings("zsh", second.shell_integration.?.shell.?.view());
    try std.testing.expectEqual(@as(u8, 'A'), second.shell_mark.kind);
    try std.testing.expectEqualStrings("", second.shell_mark.metadata.view());
}

test "VT publication resolves cell and cursor presentation per generation" {
    var value = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer value.deinit();
    const first_feed = try value.feed(
        "\x1b]4;2;#010203\x1b\\" ++
            "\x1b]10;#111213\x1b\\" ++
            "\x1b]11;#212223\x1b\\" ++
            "\x1b]12;#313233\x1b\\" ++
            "\x1b[38;5;2;48;2;4;5;6;58;2;7;8;9;2;4:4;8;9mX",
    );
    try std.testing.expect(first_feed.state_changed);
    const first = value.surfaceSnapshot();
    const source = first.snapshot.view.cellInfoAt(0, 0);
    const copied = try copyCell(
        source.codepoint,
        source.combining_len,
        source.combining,
        source.width,
        source.height,
        source.x,
        source.y,
        source.attrs,
        &first.presentation,
    );
    try std.testing.expectEqual(
        howl_vt.Terminal.Rgb{ .r = 1, .g = 2, .b = 3 },
        copied.foreground,
    );
    try std.testing.expectEqual(
        howl_vt.Terminal.Rgb{ .r = 4, .g = 5, .b = 6 },
        copied.background,
    );
    try std.testing.expectEqual(
        howl_vt.Terminal.Rgb{ .r = 7, .g = 8, .b = 9 },
        copied.underline_color,
    );
    try std.testing.expect(copied.dim);
    try std.testing.expect(copied.invisible);
    try std.testing.expect(copied.underline);
    try std.testing.expectEqual(.dotted, copied.underline_style);
    try std.testing.expect(copied.strikethrough);
    try std.testing.expectEqual(
        @as(?howl_vt.Terminal.Rgb, .{ .r = 0x31, .g = 0x32, .b = 0x33 }),
        first.presentation.cursor,
    );

    const second_feed = try value.feed("\x1b]4;2;#a1a2a3\x1b\\");
    try std.testing.expect(second_feed.state_changed);
    const second = value.surfaceSnapshot();
    try std.testing.expect(second.snapshot_seq != first.snapshot_seq);
    const second_source = second.snapshot.view.cellInfoAt(0, 0);
    const recolored = try copyCell(
        second_source.codepoint,
        second_source.combining_len,
        second_source.combining,
        second_source.width,
        second_source.height,
        second_source.x,
        second_source.y,
        second_source.attrs,
        &second.presentation,
    );
    try std.testing.expectEqual(
        howl_vt.Terminal.Rgb{ .r = 0xa1, .g = 0xa2, .b = 0xa3 },
        recolored.foreground,
    );

    const reverse_feed = try value.feed("\x1b[?5h");
    try std.testing.expect(reverse_feed.state_changed);
    const reversed = value.surfaceSnapshot();
    const reversed_source = reversed.snapshot.view.cellInfoAt(0, 0);
    const reversed_cell = try copyCell(
        reversed_source.codepoint,
        reversed_source.combining_len,
        reversed_source.combining,
        reversed_source.width,
        reversed_source.height,
        reversed_source.x,
        reversed_source.y,
        reversed_source.attrs,
        &reversed.presentation,
    );
    try std.testing.expectEqual(copied.background, reversed_cell.foreground);
    try std.testing.expectEqual(recolored.foreground, reversed_cell.background);
}

test "native owner launches bash, publishes input, resizes, and reuses descriptors" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    const owner = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .first,
        .{ .cols = 40, .rows = 12 },
    );
    const initial = try owner.copySnapshot();
    try std.testing.expect(initial.generation > 0);
    try owner.input("printf 'HOWL_NATIVE_OK\\n'\n");
    const output = try waitForText(owner, "HOWL_NATIVE_OK");
    try std.testing.expectEqual(layout.TerminalId.first, output.terminal);
    try std.testing.expect(output.generation > initial.generation);
    try owner.resize(.{ .cols = 50, .rows = 14 });
    const resized = try waitForGeometry(owner, .{ .cols = 50, .rows = 14 });
    try std.testing.expectEqual(@as(u16, 50), resized.cols);
    try std.testing.expectEqual(@as(u16, 14), resized.rows);
    try owner.deinit();
    try std.testing.expectEqual(descriptors_before, try descriptorCount());

    const reused = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .first,
        .{ .cols = 20, .rows = 8 },
    );
    try std.testing.expect((try reused.copySnapshot()).generation > 0);
    try reused.deinit();
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
}

test "exec failure is reported after exact child and descriptor rollback" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    try std.testing.expectError(
        error.child_launch_failed,
        Owner.startExecutable(
            std.testing.allocator,
            std.testing.io,
            .first,
            .{ .cols = 20, .rows = 8 },
            "/howl-host-test/missing-shell",
        ),
    );
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
    try expectNoChildren();

    const layout_value = try layout.Layout.init(.horizontal, .{ .width = 800, .height = 480 });
    try std.testing.expectError(
        error.child_launch_failed,
        Set.startExecutables(
            std.testing.allocator,
            std.testing.io,
            try layout_value.snapshot(),
            test_cell_size,
            .{ shell_path, shell_path, "/howl-host-test/missing-shell" },
        ),
    );
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
    try expectNoChildren();

    const reused = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .first,
        .{ .cols = 20, .rows = 8 },
    );
    try reused.deinit();
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
}

test "queue-full stop discards pending work and releases every owner resource" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    const owner = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .first,
        .{ .cols = 20, .rows = 8 },
    );
    owner.mutex.lockUncancelable(owner.io);
    for (0..command_capacity) |index|
        try owner.queue.push(.{ .resize = .{
            .rows = 8,
            .cols = @intCast(index + 1),
        } });
    owner.mutex.unlock(owner.io);
    try owner.deinit();
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
    try expectNoChildren();
}

test "stored failure closes admission and remains cleanup authority" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    const owner = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .second,
        .{ .cols = 20, .rows = 8 },
    );
    owner.mutex.lockUncancelable(owner.io);
    owner.failure = error.pty_write_failed;
    owner.mutex.unlock(owner.io);
    try std.testing.expectError(error.pty_write_failed, owner.input(""));
    try std.testing.expectError(error.pty_write_failed, owner.input("ignored"));
    try std.testing.expectError(
        error.pty_write_failed,
        owner.key(.{
            .named = .enter,
            .shift = false,
            .alt = false,
            .control = false,
        }),
    );
    try std.testing.expectError(
        error.pty_write_failed,
        owner.resize(.{ .cols = max_cols + 1, .rows = 1 }),
    );
    try std.testing.expectError(error.pty_write_failed, owner.deinit());
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
    try expectNoChildren();
}

test "wake failure falls back to child signal and preserves first cleanup failure" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    const owner = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .third,
        .{ .cols = 20, .rows = 8 },
    );
    if (c.close(owner.wake_fd) != 0)
        return error.TestUnexpectedResult;
    try std.testing.expectError(error.wake_failed, owner.input("not queued"));
    try std.testing.expectEqual(@as(usize, 0), owner.queue.count);
    try std.testing.expectError(
        error.wake_failed,
        owner.key(.{
            .named = .enter,
            .shift = false,
            .alt = false,
            .control = false,
        }),
    );
    try std.testing.expectError(error.wake_failed, owner.deinit());
    try std.testing.expectEqual(descriptors_before, try descriptorCount());
    try expectNoChildren();
}

test "allocation and third-owner startup rollback preserve descriptors" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const descriptors_before = try descriptorCount();
    try std.testing.expectError(
        error.OutOfMemory,
        Owner.start(
            std.testing.failing_allocator,
            std.testing.io,
            .first,
            .{ .cols = 20, .rows = 8 },
        ),
    );
    try std.testing.expectEqual(descriptors_before, try descriptorCount());

    var value = try layout.Layout.init(.horizontal, .{ .width = 800, .height = 480 });
    var snapshot = try value.snapshot();
    snapshot.placements[1] = .{
        .terminal = .third,
        .rect = .{
            .x = 0,
            .y = 0,
            .width = std.math.maxInt(u16),
            .height = 16,
        },
        .focused = false,
    };
    try std.testing.expectError(
        error.invalid_geometry,
        Set.start(std.testing.allocator, std.testing.io, snapshot, test_cell_size),
    );
    try std.testing.expectEqual(descriptors_before, try descriptorCount());

    const reused = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .third,
        .{ .cols = 20, .rows = 8 },
    );
    try std.testing.expect((try reused.copySnapshot()).generation >= 1);
    try reused.deinit();
}

test "three owners preserve input identity and hidden resize state" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const visible = try layout.Layout.init(.horizontal, .{ .width = 800, .height = 480 });
    const snapshot = try visible.snapshot();
    var set = try Set.start(
        std.testing.allocator,
        std.testing.io,
        snapshot,
        test_cell_size,
    );
    defer set.deinit() catch @panic("terminal set test cleanup failed");
    for (std.enums.values(layout.TerminalId)) |id|
        try std.testing.expect((try set.copySnapshot(id)).generation >= 1);

    try set.input(.first, "printf 'FIRST_OWNER\\n'\n");
    try set.input(.second, "printf 'SECOND_OWNER\\n'\n");
    try set.input(.third, "printf 'THIRD_OWNER\\n'\n");
    try std.testing.expect(snapshotContains(
        &(try waitForText(set.owners[0], "FIRST_OWNER")),
        "FIRST_OWNER",
    ));
    try std.testing.expect(snapshotContains(
        &(try waitForText(set.owners[1], "SECOND_OWNER")),
        "SECOND_OWNER",
    ));
    const third_with_text = try waitForText(set.owners[2], "THIRD_OWNER");
    try std.testing.expect(snapshotContains(&third_with_text, "THIRD_OWNER"));
    const third_geometry = Geometry{
        .cols = third_with_text.cols,
        .rows = third_with_text.rows,
    };

    try set.resizeVisible(snapshot);
    const first_resized = try waitForGeometry(set.owners[0], .{ .cols = 50, .rows = 30 });
    const second_resized = try waitForGeometry(set.owners[1], .{ .cols = 50, .rows = 30 });
    try std.testing.expect(first_resized.generation > 1);
    try std.testing.expect(second_resized.generation > 1);
    const third_after_resize = (try set.snapshots())[2];
    try std.testing.expectEqual(third_geometry.rows, third_after_resize.rows);
    try std.testing.expectEqual(third_geometry.cols, third_after_resize.cols);
    try std.testing.expect(snapshotContains(&third_after_resize, "THIRD_OWNER"));
}

test "child exit is exact and owner cleanup remains reusable" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const owner = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .second,
        .{ .cols = 20, .rows = 8 },
    );
    try std.testing.expect((try owner.copySnapshot()).generation > 0);
    try owner.input("exit\n");
    try std.testing.expectError(error.child_exited, waitForChildExit(owner));
    try std.testing.expectError(error.child_exited, owner.deinit());

    const reused = try Owner.start(
        std.testing.allocator,
        std.testing.io,
        .second,
        .{ .cols = 20, .rows = 8 },
    );
    try std.testing.expect((try reused.copySnapshot()).generation > 0);
    try reused.deinit();
}

fn waitForText(owner: *Owner, expected: []const u8) !Snapshot {
    var attempts: u8 = 0;
    while (attempts < 32) : (attempts += 1) {
        const snapshot = try waitForCompletion(owner);
        if (snapshotContains(&snapshot, expected)) return snapshot;
    }
    return error.TestExpectedTextMissing;
}

fn waitForGeometry(owner: *Owner, expected: Geometry) !Snapshot {
    var attempts: u8 = 0;
    while (attempts < 32) : (attempts += 1) {
        const snapshot = try waitForCompletion(owner);
        if (snapshot.rows == expected.rows and snapshot.cols == expected.cols)
            return snapshot;
    }
    return error.TestExpectedGeometryMissing;
}

fn waitForCompletion(owner: *Owner) !Snapshot {
    var fds = [_]std.posix.pollfd{.{
        .fd = owner.completionFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = std.posix.poll(&fds, 5_000) catch return error.TestWaitFailed;
    if (ready != 1 or fds[0].revents & std.posix.POLL.IN == 0)
        return error.TestWaitFailed;
    return owner.copySnapshot();
}

fn drainAvailable(owner: *Owner) !Snapshot {
    var snapshot = try owner.peekSnapshot();
    while (true) {
        var fds = [_]std.posix.pollfd{.{
            .fd = owner.completionFd(),
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&fds, 0) catch return error.TestWaitFailed;
        if (ready == 0) return snapshot;
        snapshot = try owner.copySnapshot();
    }
}

fn waitForChildExit(owner: *Owner) !void {
    var attempts: u8 = 0;
    while (attempts < 32) : (attempts += 1) {
        const snapshot = waitForCompletion(owner) catch |failure| return failure;
        if (snapshot.generation == 0) return error.TestExpectedChildExit;
    }
    return error.TestExpectedChildExit;
}

fn snapshotContains(snapshot: *const Snapshot, expected: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(expected)) return false;
    var matched: usize = 0;
    for (snapshot.visible()) |cell| {
        if (cell.codepoint == expected[matched]) {
            matched += 1;
            if (matched == expected.len) return true;
        } else {
            matched = if (cell.codepoint == expected[0]) 1 else 0;
        }
    }
    return false;
}

fn descriptorCount() !usize {
    var directory = try std.Io.Dir.openDirAbsolute(
        std.testing.io,
        "/proc/self/fd",
        .{ .iterate = true },
    );
    defer directory.close(std.testing.io);
    var entries = directory.iterate();
    var count: usize = 0;
    while (try entries.next(std.testing.io)) |_| count += 1;
    return count;
}

fn expectNoChildren() !void {
    var status: c_int = 0;
    const child = c.waitpid(-1, &status, c.WNOHANG);
    if (child >= 0 or std.posix.errno(child) != .CHILD)
        return error.TestUnexpectedResult;
}
