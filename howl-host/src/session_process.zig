//! Owns one host-created canonical Session process and its private Unix socket.
//!
//! The native Host packages the exact matching `howl-sessiond` beside itself.
//! This owner never consults PATH and never changes externally attached Session
//! lifetimes. It exists only for panes the Host itself creates.

const std = @import("std");
const client = @import("howl_client");

const start_attempts: usize = 250;
const start_retry_ms: i64 = 2;

pub const SessionProcess = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    child: std.process.Child,
    socket_path: []u8,
    endpoint: []u8,

    pub fn launchSibling(
        allocator: std.mem.Allocator,
        io: std.Io,
        runtime_dir: []const u8,
        shell: []const u8,
        environ_map: *const std.process.Environ.Map,
        rows: u16,
        cols: u16,
        identity: u32,
    ) !SessionProcess {
        if (runtime_dir.len == 0 or shell.len == 0 or rows == 0 or cols == 0 or identity == 0)
            return error.InvalidSessionLaunch;
        const executable_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(executable_dir);
        const sessiond_path = try std.fs.path.join(allocator, &.{ executable_dir, "howl-sessiond" });
        defer allocator.free(sessiond_path);
        return launch(
            allocator,
            io,
            sessiond_path,
            runtime_dir,
            shell,
            environ_map,
            rows,
            cols,
            identity,
        );
    }

    fn launch(
        allocator: std.mem.Allocator,
        io: std.Io,
        sessiond_path: []const u8,
        runtime_dir: []const u8,
        shell: []const u8,
        environ_map: *const std.process.Environ.Map,
        rows: u16,
        cols: u16,
        identity: u32,
    ) !SessionProcess {
        const socket_path = try std.fmt.allocPrint(
            allocator,
            "{s}/howl-host-{d}-{d}.sock",
            .{ runtime_dir, std.os.linux.getpid(), identity },
        );
        errdefer allocator.free(socket_path);
        if (socket_path.len >= 100) return error.SocketPathTooLong;
        std.Io.Dir.deleteFileAbsolute(io, socket_path) catch |failure| switch (failure) {
            error.FileNotFound => {},
            else => return failure,
        };
        errdefer std.Io.Dir.deleteFileAbsolute(io, socket_path) catch |failure|
            std.debug.print("Howl Session socket rollback cleanup failed: {s}\n", .{@errorName(failure)});

        const endpoint = try std.fmt.allocPrint(allocator, "unix:{s}", .{socket_path});
        errdefer allocator.free(endpoint);
        const rows_text = try std.fmt.allocPrint(allocator, "{d}", .{rows});
        defer allocator.free(rows_text);
        const cols_text = try std.fmt.allocPrint(allocator, "{d}", .{cols});
        defer allocator.free(cols_text);
        const argv = [_][]const u8{
            sessiond_path,
            socket_path,
            shell,
            rows_text,
            cols_text,
        };
        var child = try std.process.spawn(io, .{
            .argv = &argv,
            .environ_map = environ_map,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .inherit,
        });
        errdefer child.kill(io);

        var attempt: usize = 0;
        while (attempt < start_attempts) : (attempt += 1) {
            var probe = client.Connection.connect(allocator, endpoint) catch |failure| switch (failure) {
                error.SocketConnectFailed => {
                    try std.Io.sleep(io, .fromMilliseconds(start_retry_ms), .awake);
                    continue;
                },
                else => return failure,
            };
            probe.deinit();
            return .{
                .allocator = allocator,
                .io = io,
                .child = child,
                .socket_path = socket_path,
                .endpoint = endpoint,
            };
        }
        return error.SessionStartTimeout;
    }

    pub fn deinit(self: *SessionProcess) void {
        self.child.kill(self.io);
        std.Io.Dir.deleteFileAbsolute(self.io, self.socket_path) catch |failure|
            std.debug.print("Howl Session socket cleanup failed: {s}\n", .{@errorName(failure)});
        self.allocator.free(self.endpoint);
        self.allocator.free(self.socket_path);
        self.* = undefined;
    }
};
