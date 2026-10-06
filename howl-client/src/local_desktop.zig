//! Desktop catalogue for listener-free Local Instances.
//!
//! The catalogue owns platform-neutral Local identity/lifetime. Linux and
//! Windows differ only in the unnamed stream owner used beneath ordinary HWLS.

const std = @import("std");
const builtin = @import("builtin");
const client = @import("howl_client");
const instance = @import("howl_instance");
const local_instance = switch (builtin.os.tag) {
    .linux => @import("local_owner_linux.zig"),
    .windows => @import("local_owner_windows.zig"),
    else => @compileError("desktop Local catalogue requires Linux or Windows"),
};

const maximum_local_instances: usize = 64;

const Slot = struct {
    id: u64,
    owner: *local_instance.Owner,
};

/// Reports local Instance construction, capacity, identity, and service failures.
pub const Error = local_instance.Error || error{
    LocalInstanceCapacity,
    LocalIdentityExhausted,
};

/// Owns the fixed-capacity catalogue of listener-free Local Instances.
pub const State = struct {
    mutex: std.Io.Mutex = .init,
    instances: [maximum_local_instances]?Slot = @splat(null),
    next_id: u64 = 1,
};

/// Creates one Local Instance and returns its process-local catalogue identity.
pub fn create(
    state: *State,
    io: std.Io,
    environ: std.process.Environ,
    shell: []const u8,
    command: []const u8,
    cwd: []const u8,
    rows: u16,
    columns: u16,
    history_rows: u16,
) Error!u64 {
    const owner = try local_instance.Owner.init(
        std.heap.c_allocator,
        io,
        environ,
        instance.Launch{
            .shell = shell,
            .command = if (command.len == 0) null else command,
            .cwd = if (cwd.len == 0) null else cwd,
            .rows = rows,
            .columns = columns,
            .history_rows = history_rows,
        },
    );
    errdefer owner.deinit();

    state.mutex.lockUncancelable(io);
    defer state.mutex.unlock(io);
    var free: ?usize = null;
    for (state.instances, 0..) |slot, index| {
        if (slot == null) {
            free = index;
            break;
        }
    }
    const index = free orelse return error.LocalInstanceCapacity;
    const id = state.next_id;
    if (id == 0) return error.LocalIdentityExhausted;
    state.next_id +%= 1;
    state.instances[index] = .{ .id = id, .owner = owner };
    return id;
}

/// Removes one exact Local identity and destroys its Instance owner.
pub fn destroy(state: *State, io: std.Io, id: u64) bool {
    if (id == 0) return false;
    var owner: ?*local_instance.Owner = null;
    state.mutex.lockUncancelable(io);
    for (&state.instances) |*slot| {
        if (slot.*) |active| {
            if (active.id == id) {
                owner = active.owner;
                slot.* = null;
                break;
            }
        }
    }
    state.mutex.unlock(io);
    if (owner) |active| active.deinit();
    return owner != null;
}

/// Opens one ordinary HWLS connection to an existing Local Instance identity.
pub fn connect(
    state: *State,
    io: std.Io,
    id: u64,
    diagnostic: *client.ConnectDiagnostic,
    interrupt: ?*client.Interrupt,
) Error!client.Connection {
    state.mutex.lockUncancelable(io);
    defer state.mutex.unlock(io);
    for (state.instances) |slot| {
        if (slot) |active| {
            if (active.id == id) return active.owner.connect(diagnostic, interrupt);
        }
    }
    return error.ServiceFailed;
}

/// Reports whether the Local catalogue contains no live Instances.
pub fn empty(state: *const State) bool {
    for (state.instances) |slot| if (slot != null) return false;
    return true;
}
