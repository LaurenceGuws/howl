//! In-process Howl Instance owner for the Odin desktop.
//!
//! Local presentation still traverses ordinary HWLS client semantics, but the
//! service side is adopted through an unnamed socketpair. There is no listener,
//! filesystem socket, Session, or Server in this route.

const std = @import("std");
const client = @import("howl_client");
const transport = @import("client_transport");
const instance = @import("howl_instance");
const instance_service = @import("howl_instance_service");

const posix = std.posix;
const service_wait_ms: i32 = 20;
const maximum_pending_admissions: usize = 8;

pub const Error = client.Error || instance.InitError || instance_service.Service.InitError || error{
    SocketPairFailed,
    ServiceThreadFailed,
    ServiceFailed,
    AdmissionFailed,
};

const Admission = struct {
    fd: posix.fd_t,
    done: std.Io.Event = .unset,
    accepted: bool = false,
};

pub const Owner = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *instance.Instance,
    service: instance_service.Service,
    admission_storage: [maximum_pending_admissions]*Admission = undefined,
    admissions: std.Io.Queue(*Admission) = undefined,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: instance.Launch,
    ) Error!*Owner {
        const owner = try allocator.create(Owner);
        errdefer allocator.destroy(owner);
        const value = try instance.init(allocator, environ, launch);
        errdefer instance.deinit(value);
        var service = try instance_service.Service.init(allocator, io, value);
        errdefer service.deinit();
        owner.* = .{
            .allocator = allocator,
            .io = io,
            .value = value,
            .service = service,
        };
        owner.admissions = .init(&owner.admission_storage);
        owner.thread = std.Thread.spawn(.{}, run, .{owner}) catch
            return error.ServiceThreadFailed;
        return owner;
    }

    pub fn deinit(self: *Owner) void {
        self.admissions.close(self.io);
        self.stop.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.service.deinit();
        instance.deinit(self.value);
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
    }

    pub fn connect(
        self: *Owner,
        diagnostic: *client.ConnectDiagnostic,
        interrupt: ?*client.Interrupt,
    ) Error!client.Connection {
        if (self.failed.load(.acquire)) return error.ServiceFailed;

        var pair: [2]posix.fd_t = undefined;
        const result = posix.system.socketpair(
            posix.AF.UNIX,
            posix.SOCK.STREAM | posix.SOCK.CLOEXEC,
            0,
            &pair,
        );
        if (posix.errno(result) != .SUCCESS) return error.SocketPairFailed;
        var client_owned = true;
        var service_owned = false;
        defer if (client_owned) closeFd(pair[0]);
        defer if (!service_owned) closeFd(pair[1]);

        var admission = Admission{ .fd = pair[1] };
        self.admissions.putOneUncancelable(self.io, &admission) catch
            return error.ServiceFailed;
        admission.done.waitUncancelable(self.io);
        if (!admission.accepted) return error.AdmissionFailed;
        service_owned = true;

        const stream = transport.Stream.adopt(pair[0], diagnostic, interrupt) catch |failure| {
            client_owned = false; // Stream.adopt owns the fd even on failure.
            return failure;
        };
        client_owned = false;
        return client.connectTransport(self.allocator, stream, diagnostic);
    }

    fn run(self: *Owner) void {
        var pending: [maximum_pending_admissions]*Admission = undefined;
        while (!self.stop.load(.acquire)) {
            const count = self.admissions.getUncancelable(self.io, &pending, 0) catch 0;
            for (pending[0..count]) |admission| {
                self.service.adoptClient(admission.fd, &.{}, &.{}) catch {
                    admission.done.set(self.io);
                    continue;
                };
                admission.accepted = true;
                admission.done.set(self.io);
            }
            self.service.turn(service_wait_ms) catch {
                self.failed.store(true, .release);
                self.admissions.close(self.io);
                while (true) {
                    const remaining = self.admissions.getUncancelable(self.io, &pending, 0) catch break;
                    if (remaining == 0) break;
                    for (pending[0..remaining]) |admission| admission.done.set(self.io);
                }
                return;
            };
        }
    }
};

fn closeFd(fd: posix.fd_t) void {
    const result = posix.system.close(fd);
    const status = posix.errno(result);
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

test "local owner admits ordinary HWLS clients without a listener" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const owner = try Owner.init(
        std.testing.allocator,
        threaded.io(),
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "printf 'LOCAL_A\nLOCAL_B\n'; read line",
            .rows = 4,
            .columns = 80,
            .history_rows = 16,
        },
    );
    defer owner.deinit();

    var diagnostic: client.ConnectDiagnostic = .{};
    var first = try owner.connect(&diagnostic, null);
    defer first.deinit();
    var second = try owner.connect(&diagnostic, null);
    defer second.deinit();
    try std.testing.expect(first.client_id != 0);
    try std.testing.expect(second.client_id != 0);
    try std.testing.expect(first.client_id != second.client_id);

    var snapshot = try client.rich.requestRaw(&second, std.testing.allocator, 0, 0);
    defer snapshot.deinit();
    const projected = try client.view.project(std.testing.allocator, &snapshot);
    defer client.view.deinit(projected);
    var text: [1024]u8 = undefined;
    const written = client.view.writeVisibleText(projected, &text);
    try std.testing.expect(std.mem.indexOf(u8, text[0..written.bytes_written], "LOCAL_A\nLOCAL_B") != null);
}
