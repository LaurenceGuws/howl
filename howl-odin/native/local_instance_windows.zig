//! In-process Windows Howl Instance owner for the Odin desktop.
//!
//! Local presentation still traverses ordinary HWLS client semantics. Each
//! connection uses two anonymous one-way pipes as one duplex stream plus an
//! auto-reset wake event. There is no listener, endpoint, Session, or Server.

const std = @import("std");
const windows = std.os.windows;
const client = @import("howl_client");
const transport = @import("client_transport");
const instance = @import("howl_instance");
const instance_service = @import("howl_instance_service");

const service_wait_ms: i32 = 20;
const maximum_pending_admissions: usize = 8;
const pipe_buffer_bytes: u32 = 64 * 1024;
const duplicate_same_access: u32 = 0x0000_0002;

extern "kernel32" fn CreatePipe(
    read_pipe: *windows.HANDLE,
    write_pipe: *windows.HANDLE,
    attributes: ?*windows.SECURITY_ATTRIBUTES,
    size: u32,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn CreateEventW(
    attributes: ?*windows.SECURITY_ATTRIBUTES,
    manual_reset: windows.BOOL,
    initial_state: windows.BOOL,
    name: ?windows.LPCWSTR,
) callconv(.winapi) ?windows.HANDLE;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) windows.HANDLE;
extern "kernel32" fn DuplicateHandle(
    source_process: windows.HANDLE,
    source_handle: windows.HANDLE,
    target_process: windows.HANDLE,
    target_handle: *windows.HANDLE,
    desired_access: u32,
    inherit_handle: windows.BOOL,
    options: u32,
) callconv(.winapi) windows.BOOL;

pub const Error = client.Error || instance.InitError || instance_service.Service.InitError || error{
    StreamPairFailed,
    ServiceThreadFailed,
    ServiceFailed,
    AdmissionFailed,
};

const StreamPair = struct {
    client_read: windows.HANDLE,
    client_write: windows.HANDLE,
    client_read_event: windows.HANDLE,
    service: instance_service.WindowsAdoptedStream,

    fn init() error{StreamPairFailed}!StreamPair {
        var service_read: windows.HANDLE = undefined;
        var client_write: windows.HANDLE = undefined;
        if (!CreatePipe(&service_read, &client_write, null, pipe_buffer_bytes).toBool())
            return error.StreamPairFailed;
        var service_read_owned = true;
        defer if (service_read_owned) closeHandle(service_read);
        var client_write_owned = true;
        defer if (client_write_owned) closeHandle(client_write);

        var client_read: windows.HANDLE = undefined;
        var service_write: windows.HANDLE = undefined;
        if (!CreatePipe(&client_read, &service_write, null, pipe_buffer_bytes).toBool())
            return error.StreamPairFailed;
        var client_read_owned = true;
        defer if (client_read_owned) closeHandle(client_read);
        var service_write_owned = true;
        defer if (service_write_owned) closeHandle(service_write);

        const client_event = CreateEventW(null, .FALSE, .FALSE, null) orelse
            return error.StreamPairFailed;
        var client_event_owned = true;
        defer if (client_event_owned) closeHandle(client_event);

        var service_event: windows.HANDLE = undefined;
        const process = GetCurrentProcess();
        if (!DuplicateHandle(
            process,
            client_event,
            process,
            &service_event,
            0,
            .FALSE,
            duplicate_same_access,
        ).toBool()) return error.StreamPairFailed;

        service_read_owned = false;
        client_write_owned = false;
        client_read_owned = false;
        service_write_owned = false;
        client_event_owned = false;
        return .{
            .client_read = client_read,
            .client_write = client_write,
            .client_read_event = client_event,
            .service = .{
                .read = service_read,
                .write = service_write,
                .peer_read_event = service_event,
            },
        };
    }

    fn closeClient(self: *const StreamPair) void {
        closeHandle(self.client_read);
        closeHandle(self.client_write);
        closeHandle(self.client_read_event);
    }

    fn closeService(self: *const StreamPair) void {
        closeHandle(self.service.read);
        closeHandle(self.service.write);
        closeHandle(self.service.peer_read_event);
    }
};

const Admission = struct {
    stream: instance_service.AdoptedStream,
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

        var pair = try StreamPair.init();
        var client_owned = true;
        var service_owned = true;
        defer if (client_owned) pair.closeClient();
        defer if (service_owned) pair.closeService();

        var admission = Admission{ .stream = pair.service };
        self.admissions.putOneUncancelable(self.io, &admission) catch
            return error.ServiceFailed;
        admission.done.waitUncancelable(self.io);
        if (!admission.accepted) return error.AdmissionFailed;
        service_owned = false;

        const stream = transport.Stream.adoptPipe(
            pair.client_read,
            pair.client_write,
            pair.client_read_event,
            diagnostic,
            interrupt,
        ) catch |failure| {
            client_owned = false;
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
                self.service.adoptClient(admission.stream, &.{}, &.{}) catch {
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

fn closeHandle(handle: windows.HANDLE) void {
    windows.CloseHandle(handle);
}
