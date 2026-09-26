//! Owns one Windows ConPTY, its child process, bounded I/O, and cleanup.
//!
//! This is the Windows implementation of the same platform PTY contract used by
//! howl-instance. It owns process/pipe/ConPTY mechanics only; VT semantics,
//! Instance publication, HWLS, and desktop policy remain outside this module.

const std = @import("std");
const windows = std.os.windows;
const kernel32 = windows.kernel32;

const pipe_buffer_bytes: u32 = 64 * 1024;
const pipe_nowait: u32 = 0x0000_0001;
const pseudo_console_attribute: usize = 0x0002_0016;
const still_active: u32 = 259;
const wait_object_0: u32 = 0;
const stop_wait_ms: u32 = 2_000;

const HRESULT = i32;
const HPCON = windows.LPVOID;

const StartupInfoEx = extern struct {
    startup: windows.STARTUPINFOW,
    attributes: windows.LPVOID,
};

extern "kernel32" fn CreatePipe(
    read_pipe: *windows.HANDLE,
    write_pipe: *windows.HANDLE,
    attributes: ?*windows.SECURITY_ATTRIBUTES,
    size: u32,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn SetNamedPipeHandleState(
    pipe: windows.HANDLE,
    mode: ?*u32,
    maximum_collection_count: ?*u32,
    collect_data_timeout: ?*u32,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn PeekNamedPipe(
    pipe: windows.HANDLE,
    buffer: ?windows.LPVOID,
    buffer_size: u32,
    bytes_read: ?*u32,
    total_bytes_available: ?*u32,
    bytes_left_this_message: ?*u32,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn ReadFile(
    file: windows.HANDLE,
    buffer: windows.LPVOID,
    bytes_to_read: u32,
    bytes_read: *u32,
    overlapped: ?windows.LPVOID,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn WriteFile(
    file: windows.HANDLE,
    buffer: windows.LPCVOID,
    bytes_to_write: u32,
    bytes_written: *u32,
    overlapped: ?windows.LPVOID,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn CreatePseudoConsole(
    size: windows.COORD,
    input: windows.HANDLE,
    output: windows.HANDLE,
    flags: u32,
    pseudo_console: *HPCON,
) callconv(.winapi) HRESULT;
extern "kernel32" fn ResizePseudoConsole(
    pseudo_console: HPCON,
    size: windows.COORD,
) callconv(.winapi) HRESULT;
extern "kernel32" fn ClosePseudoConsole(pseudo_console: HPCON) callconv(.winapi) void;
extern "kernel32" fn InitializeProcThreadAttributeList(
    attributes: ?windows.LPVOID,
    count: u32,
    flags: u32,
    bytes: *usize,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn UpdateProcThreadAttribute(
    attributes: windows.LPVOID,
    flags: u32,
    attribute: usize,
    value: windows.LPVOID,
    value_bytes: usize,
    previous_value: ?windows.LPVOID,
    return_bytes: ?*usize,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn DeleteProcThreadAttributeList(attributes: windows.LPVOID) callconv(.winapi) void;
extern "kernel32" fn GetExitCodeProcess(
    process: windows.HANDLE,
    exit_code: *u32,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn WaitForSingleObject(
    handle: windows.HANDLE,
    milliseconds: u32,
) callconv(.winapi) u32;
extern "kernel32" fn TerminateProcess(
    process: windows.HANDLE,
    exit_code: u32,
) callconv(.winapi) windows.BOOL;

/// Platform-native descriptor used by Windows readiness owners.
pub const Descriptor = windows.HANDLE;

/// Reports copied launch allocation or invalid inherited environment.
pub const InitError = std.mem.Allocator.Error || error{
    EnvironmentByteLimit,
    EnvironmentCountLimit,
    InvalidEnvironment,
    UnsupportedPlatform,
};

/// Selects terminal-owned child identity values copied with the inherited environment.
pub const ChildEnvironment = struct {
    /// Selects one nonempty installed TERM identity without equals or NUL bytes.
    term: []const u8,
    /// Optionally selects COLORTERM under the same value constraints.
    colorterm: ?[]const u8,
};

/// Reports an invalid lifecycle transition or failed Windows child construction.
pub const StartError = error{
    AlreadyStarted,
    ChildCwdFailed,
    ChildExecFailed,
    ChildSessionFailed,
    ChildStdioFailed,
    ForkFailed,
    LaunchStatusFailed,
    LaunchStatusPipeFailed,
    MasterConfigureFailed,
    OpenPtyFailed,
    ShellUnavailable,
    InvalidDimensions,
};

/// Names cross-platform child-control requests accepted by the PTY owner.
pub const Signal = enum(u8) {
    hangup = 1,
    interrupt = 2,
    resize_notify = 3,
    kill = 9,
    terminate = 15,
};

/// Reports a nonblocking ConPTY output read failure.
pub const ReadError = error{ EndOfStream, Interrupted, NotStarted, ReadFailed, WouldBlock };

/// Reports invalid dimensions or a failed ConPTY resize.
pub const ResizeError = error{ InvalidDimensions, NotStarted, ResizeFailed };

/// Reports unavailable terminal-control state.
pub const TermiosSignalError = error{
    ForegroundGroupFailed,
    NotStarted,
    SignalFailed,
    TermiosQueryFailed,
};

/// Reports one nonblocking ConPTY input write failure.
pub const WriteError = error{ ChildClosed, Interrupted, NotStarted, WouldBlock, WriteFailed };

/// Reports the conventional child exit status retained by Instance wire.
pub const ChildExit = union(enum) {
    code: u8,
    signal: u8,
};

/// Reports whether the child remains live or has exited.
pub const ChildObservation = union(enum) {
    running,
    exited: ChildExit,
};

/// Reports child observation before start or when Win32 cannot report state.
pub const ObserveError = error{ NotStarted, ObserveFailed };

/// Reports exact child-control delivery outcomes.
pub const SignalResult = enum {
    delivered,
    target_missing,
    permission_denied,
    native_signal_failed,
};

/// Owns copied launch values, one ConPTY, its host pipe ends, and one child process.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    shell_path: [:0]u16,
    command_line: [:0]u16,
    command: ?[]u8,
    start_path: ?[:0]u16,
    environment: std.process.Environ.WindowsBlock,

    started: bool = false,
    input_write: ?windows.HANDLE = null,
    output_read: ?windows.HANDLE = null,
    pseudo_console: ?HPCON = null,
    process: ?windows.HANDLE = null,
    process_id: u32 = 0,
    child_exit: ?ChildExit = null,
    last_cols: u16 = 0,
    last_rows: u16 = 0,

    const Self = @This();

    /// Copies launch strings/environment and initializes an idle ConPTY owner.
    pub fn init(
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        shell_path: []const u8,
        command: ?[]const u8,
        start_path: ?[]const u8,
        child_environment: ChildEnvironment,
    ) InitError!Self {
        if (comptime @import("builtin").os.tag != .windows) return error.UnsupportedPlatform;
        try validateEnvironmentValue(child_environment.term);
        if (child_environment.colorterm) |value| try validateEnvironmentValue(value);

        const shell_path_w = std.unicode.wtf8ToWtf16LeAllocZ(allocator, shell_path) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => return error.InvalidEnvironment,
        };
        errdefer allocator.free(shell_path_w);
        const command_line_w = try allocator.dupeSentinel(u16, shell_path_w, 0);
        errdefer allocator.free(command_line_w);

        const command_copy = if (command) |value| try allocator.dupe(u8, value) else null;
        errdefer if (command_copy) |value| allocator.free(value);

        const start_path_w = if (start_path) |value|
            std.unicode.wtf8ToWtf16LeAllocZ(allocator, value) catch |failure| switch (failure) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidWtf8 => return error.InvalidEnvironment,
            }
        else
            null;
        errdefer if (start_path_w) |value| allocator.free(value);

        var environment_map = std.process.Environ.createMap(inherited_environment, allocator) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidEnvironment,
        };
        defer environment_map.deinit();
        try environment_map.put("TERM", child_environment.term);
        if (child_environment.colorterm) |value| {
            try environment_map.put("COLORTERM", value);
        } else {
            if (environment_map.orderedRemove("COLORTERM")) {}
        }
        const environment = environment_map.createWindowsBlock(allocator, .{}) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => return error.InvalidEnvironment,
        };

        return .{
            .allocator = allocator,
            .shell_path = shell_path_w,
            .command_line = command_line_w,
            .command = command_copy,
            .start_path = start_path_w,
            .environment = environment,
        };
    }

    /// Stops the child, closes ConPTY/pipe handles, and releases copied launch data.
    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.shell_path);
        self.allocator.free(self.command_line);
        if (self.command) |value| self.allocator.free(value);
        if (self.start_path) |value| self.allocator.free(value);
        self.environment.deinit(self.allocator);
        self.* = undefined;
    }

    /// Starts one child at the supplied nonzero terminal dimensions.
    pub fn start(self: *Self, cols: u16, rows: u16) StartError!void {
        return self.startWithPixels(cols, rows, 0, 0);
    }

    /// Starts one ConPTY. Pixel extents remain canonical VT facts, not ConPTY inputs.
    pub fn startWithPixels(
        self: *Self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
    ) StartError!void {
        if ((pixel_width == 0) != (pixel_height == 0)) return error.InvalidDimensions;
        if (self.started) return error.AlreadyStarted;
        if (cols == 0 or rows == 0 or cols > std.math.maxInt(i16) or rows > std.math.maxInt(i16))
            return error.InvalidDimensions;
        // First prove the canonical interactive-shell path. Command-tail
        // grammar belongs to the Windows profile recipe, not guessed PTY policy.
        if (self.command != null) return error.ChildExecFailed;

        var pseudo_input_read: windows.HANDLE = undefined;
        var host_input_write: windows.HANDLE = undefined;
        if (!CreatePipe(&pseudo_input_read, &host_input_write, null, pipe_buffer_bytes).toBool())
            return error.OpenPtyFailed;
        var pseudo_input_read_owned = true;
        defer if (pseudo_input_read_owned) closeHandle(pseudo_input_read);
        var host_input_write_owned = true;
        defer if (host_input_write_owned) closeHandle(host_input_write);

        var host_output_read: windows.HANDLE = undefined;
        var pseudo_output_write: windows.HANDLE = undefined;
        if (!CreatePipe(&host_output_read, &pseudo_output_write, null, pipe_buffer_bytes).toBool())
            return error.OpenPtyFailed;
        var host_output_read_owned = true;
        defer if (host_output_read_owned) closeHandle(host_output_read);
        var pseudo_output_write_owned = true;
        defer if (pseudo_output_write_owned) closeHandle(pseudo_output_write);

        var pseudo: HPCON = undefined;
        if (!hresultSucceeded(CreatePseudoConsole(
            .{ .X = @intCast(cols), .Y = @intCast(rows) },
            pseudo_input_read,
            pseudo_output_write,
            0,
            &pseudo,
        ))) return error.OpenPtyFailed;
        var pseudo_owned = true;
        defer if (pseudo_owned) ClosePseudoConsole(pseudo);

        var attribute_bytes: usize = 0;
        const size_probe = InitializeProcThreadAttributeList(null, 1, 0, &attribute_bytes);
        if (size_probe.toBool() or windows.GetLastError() != .INSUFFICIENT_BUFFER or attribute_bytes == 0)
            return error.ChildExecFailed;
        const attribute_storage = self.allocator.alignedAlloc(u8, .of(usize), attribute_bytes) catch
            return error.ChildExecFailed;
        defer self.allocator.free(attribute_storage);
        const attributes: windows.LPVOID = @ptrCast(attribute_storage.ptr);
        if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_bytes).toBool())
            return error.ChildExecFailed;
        defer DeleteProcThreadAttributeList(attributes);

        if (!UpdateProcThreadAttribute(
            attributes,
            0,
            pseudo_console_attribute,
            pseudo,
            @sizeOf(HPCON),
            null,
            null,
        ).toBool()) return error.ChildExecFailed;

        var startup = StartupInfoEx{
            .startup = emptyStartupInfo(),
            .attributes = attributes,
        };
        startup.startup.cb = @sizeOf(StartupInfoEx);

        var process_info: windows.PROCESS.INFORMATION = undefined;
        @memcpy(self.command_line[0..self.shell_path.len], self.shell_path);
        self.command_line[self.shell_path.len] = 0;
        const flags: windows.CreateProcessFlags = .{
            .create_unicode_environment = true,
            .extended_startupinfo_present = true,
        };
        if (!kernel32.CreateProcessW(
            null,
            self.command_line.ptr,
            null,
            null,
            .FALSE,
            flags,
            self.environment.slice.ptr,
            if (self.start_path) |value| value.ptr else null,
            &startup.startup,
            &process_info,
        ).toBool()) {
            return switch (windows.GetLastError()) {
                .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.ShellUnavailable,
                .DIRECTORY => error.ChildCwdFailed,
                else => error.ChildExecFailed,
            };
        }

        // ConPTY requires the handles supplied to CreatePseudoConsole to remain
        // valid through hosted-process creation. Once CreateProcess succeeds,
        // the pseudoconsole owns its references and the host must release these
        // local copies so broken-channel detection remains truthful.
        closeHandle(pseudo_input_read);
        pseudo_input_read_owned = false;
        closeHandle(pseudo_output_write);
        pseudo_output_write_owned = false;

        // Only host-owned ends are made nonblocking, after ConPTY and the child
        // have completed their synchronous channel setup.
        try configureNonblockingPipe(host_input_write);
        try configureNonblockingPipe(host_output_read);

        closeHandle(process_info.hThread);
        self.input_write = host_input_write;
        self.output_read = host_output_read;
        self.pseudo_console = pseudo;
        self.process = process_info.hProcess;
        self.process_id = process_info.dwProcessId;
        self.child_exit = null;
        self.last_cols = cols;
        self.last_rows = rows;
        self.started = true;
        host_input_write_owned = false;
        host_output_read_owned = false;
        pseudo_owned = false;
    }

    /// Stops the ConPTY and guarantees the owned child leader is no longer live.
    pub fn stop(self: *Self) void {
        if (!self.started) return;

        if (self.input_write) |handle| {
            closeHandle(handle);
            self.input_write = null;
        }
        if (self.output_read) |handle| {
            closeHandle(handle);
            self.output_read = null;
        }
        if (self.pseudo_console) |pseudo| {
            ClosePseudoConsole(pseudo);
            self.pseudo_console = null;
        }
        if (self.process) |process| {
            var exit_code: u32 = 0;
            if (!GetExitCodeProcess(process, &exit_code).toBool())
                @panic("ConPTY child exit query failed during teardown");
            if (exit_code == still_active) {
                if (!TerminateProcess(process, 1).toBool())
                    @panic("ConPTY child termination failed during teardown");
            }
            if (WaitForSingleObject(process, stop_wait_ms) != wait_object_0)
                @panic("ConPTY child did not stop within cleanup bound");
            closeHandle(process);
            self.process = null;
        }

        self.started = false;
        self.process_id = 0;
        self.child_exit = null;
        self.last_cols = 0;
        self.last_rows = 0;
    }

    /// Returns the ConPTY output handle for platform readiness integration.
    pub fn masterFd(self: *const Self) error{NotStarted}!Descriptor {
        return self.output_read orelse error.NotStarted;
    }

    /// Observes the child process without consuming its retained process handle.
    pub fn observeChild(self: *Self) ObserveError!ChildObservation {
        if (!self.started) return error.NotStarted;
        if (self.child_exit) |value| return .{ .exited = value };
        const process = self.process orelse return error.ObserveFailed;
        var exit_code: u32 = 0;
        if (!GetExitCodeProcess(process, &exit_code).toBool()) return error.ObserveFailed;
        if (exit_code == still_active) return .running;
        const value = ChildExit{ .code = @truncate(exit_code) };
        self.child_exit = value;
        return .{ .exited = value };
    }

    /// Writes one bounded chunk to ConPTY input without waiting for pipe space.
    pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
        const handle = self.input_write orelse return error.NotStarted;
        if (bytes.len == 0) return 0;
        const count: u32 = @intCast(@min(bytes.len, @as(usize, std.math.maxInt(u32))));
        var written: u32 = 0;
        if (!WriteFile(handle, @ptrCast(bytes.ptr), count, &written, null).toBool()) {
            return switch (windows.GetLastError()) {
                .BROKEN_PIPE, .NO_DATA, .PIPE_NOT_CONNECTED => error.ChildClosed,
                .OPERATION_ABORTED => error.Interrupted,
                else => error.WriteFailed,
            };
        }
        if (written == 0) return error.WouldBlock;
        return written;
    }

    /// Reads one available ConPTY output chunk without waiting for future bytes.
    pub fn read(self: *Self, buffer: []u8) ReadError!usize {
        const handle = self.output_read orelse return error.NotStarted;
        if (buffer.len == 0) return 0;
        var available: u32 = 0;
        if (!PeekNamedPipe(handle, null, 0, null, &available, null).toBool()) {
            return switch (windows.GetLastError()) {
                .BROKEN_PIPE, .PIPE_NOT_CONNECTED => error.EndOfStream,
                .OPERATION_ABORTED => error.Interrupted,
                else => error.ReadFailed,
            };
        }
        if (available == 0) return error.WouldBlock;
        const count: u32 = @intCast(@min(
            @min(buffer.len, @as(usize, available)),
            @as(usize, std.math.maxInt(u32)),
        ));
        var read_count: u32 = 0;
        if (!ReadFile(handle, @ptrCast(buffer.ptr), count, &read_count, null).toBool()) {
            return switch (windows.GetLastError()) {
                .BROKEN_PIPE, .PIPE_NOT_CONNECTED => error.EndOfStream,
                .NO_DATA => error.WouldBlock,
                .OPERATION_ABORTED => error.Interrupted,
                else => error.ReadFailed,
            };
        }
        if (read_count == 0) return error.EndOfStream;
        return read_count;
    }

    /// Resizes the ConPTY cell geometry.
    pub fn resize(self: *Self, cols: u16, rows: u16) ResizeError!void {
        return self.resizeWithPixels(cols, rows, 0, 0);
    }

    /// Resizes cell geometry while retaining pixel facts in canonical VT only.
    pub fn resizeWithPixels(
        self: *Self,
        cols: u16,
        rows: u16,
        pixel_width: u16,
        pixel_height: u16,
    ) ResizeError!void {
        if ((pixel_width == 0) != (pixel_height == 0) or
            cols == 0 or rows == 0 or
            cols > std.math.maxInt(i16) or rows > std.math.maxInt(i16))
            return error.InvalidDimensions;
        const pseudo = self.pseudo_console orelse return error.NotStarted;
        if (!hresultSucceeded(ResizePseudoConsole(
            pseudo,
            .{ .X = @intCast(cols), .Y = @intCast(rows) },
        ))) return error.ResizeFailed;
        self.last_cols = cols;
        self.last_rows = rows;
    }

    /// Windows ConPTY owns console control processing; no POSIX termios interception applies.
    pub fn handleTermiosSignal(self: *Self, byte: u8) TermiosSignalError!bool {
        if (!self.started) return error.NotStarted;
        std.mem.doNotOptimizeAway(byte);
        return false;
    }

    /// Delivers the closest ConPTY-native equivalent of the requested child control.
    pub fn signal(self: *Self, requested: Signal) SignalResult {
        if (!self.started) return .target_missing;
        const process = self.process orelse return .target_missing;
        return switch (requested) {
            .interrupt => interrupt: {
                const accepted = self.write(&.{0x03}) catch break :interrupt .native_signal_failed;
                break :interrupt if (accepted == 1) .delivered else .native_signal_failed;
            },
            .resize_notify => .delivered,
            .hangup, .terminate, .kill => if (TerminateProcess(process, @backingInt(requested)).toBool())
                .delivered
            else
                .native_signal_failed,
        };
    }
};

fn validateEnvironmentValue(value: []const u8) error{InvalidEnvironment}!void {
    if (value.len == 0 or std.mem.indexOfAny(u8, value, "=\x00") != null)
        return error.InvalidEnvironment;
}

fn hresultSucceeded(result: HRESULT) bool {
    return result >= 0;
}

fn configureNonblockingPipe(handle: windows.HANDLE) error{MasterConfigureFailed}!void {
    var mode: u32 = pipe_nowait;
    if (!SetNamedPipeHandleState(handle, &mode, null, null).toBool())
        return error.MasterConfigureFailed;
}

fn closeHandle(handle: windows.HANDLE) void {
    windows.CloseHandle(handle);
}

fn emptyStartupInfo() windows.STARTUPINFOW {
    return .{
        .cb = @sizeOf(windows.STARTUPINFOW),
        .lpReserved = null,
        .lpDesktop = null,
        .lpTitle = null,
        .dwX = 0,
        .dwY = 0,
        .dwXSize = 0,
        .dwYSize = 0,
        .dwXCountChars = 0,
        .dwYCountChars = 0,
        .dwFillAttribute = 0,
        // Prevent CreateProcess from duplicating redirected parent std handles
        // into the hosted console child. Null handles plus USESTDHANDLES leave
        // standard-stream establishment to the attached pseudoconsole.
        .dwFlags = windows.STARTF_USESTDHANDLES,
        .wShowWindow = 0,
        .cbReserved2 = 0,
        .lpReserved2 = null,
        .hStdInput = null,
        .hStdOutput = null,
        .hStdError = null,
    };
}

test "Windows PTY rejects malformed child environment values before native access" {
    try std.testing.expectError(
        error.InvalidEnvironment,
        Owned.init(
            std.testing.allocator,
            std.testing.environ,
            "C:\\Windows\\System32\\cmd.exe",
            null,
            null,
            .{ .term = "xterm=bad", .colorterm = null },
        ),
    );
}
