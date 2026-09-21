//! Connection construction for one externally owned Howl Instance.
//!
//! A target may already expose HWLS directly, or may require one exact
//! Server -> Session -> Instance attach. After construction callers see only the
//! ordinary `howl_client.Connection`; rendering/input never own Server semantics.

const std = @import("std");
const client = @import("howl_client");
const server_client = @import("server_client");

pub const ServerTarget = server_client.Target;

pub const Target = union(enum) {
    direct: []const u8,
    server: ServerTarget,

    pub fn isDirect(self: Target) bool {
        return self == .direct;
    }
};

pub fn connect(allocator: std.mem.Allocator, target: Target) !client.Connection {
    return switch (target) {
        .direct => |endpoint| client.Connection.connect(allocator, endpoint),
        .server => |managed| connectServer(allocator, managed),
    };
}

fn connectServer(
    allocator: std.mem.Allocator,
    managed: ServerTarget,
) !client.Connection {
    var diagnostic: client.ConnectDiagnostic = .{};
    const attached = try server_client.attach(allocator, managed, &diagnostic, null);
    return client.connectTransport(allocator, attached.stream, &diagnostic);
}

test "target preserves direct and exact Server identity without presentation state" {
    const direct = Target{ .direct = "unix:/tmp/howl-instance.sock" };
    try std.testing.expect(direct.isDirect());
    try std.testing.expectEqualStrings("unix:/tmp/howl-instance.sock", direct.direct);

    const managed = Target{ .server = .{
        .endpoint = "tcp://127.0.0.1:43130",
        .server_id = 91,
        .session_id = 7,
        .instance_id = 3,
    } };
    try std.testing.expect(!managed.isDirect());
    try std.testing.expectEqualStrings("tcp://127.0.0.1:43130", managed.server.endpoint);
    try std.testing.expectEqual(@as(u64, 91), managed.server.server_id);
    try std.testing.expectEqual(@as(u64, 7), managed.server.session_id);
    try std.testing.expectEqual(@as(u64, 3), managed.server.instance_id);
}
