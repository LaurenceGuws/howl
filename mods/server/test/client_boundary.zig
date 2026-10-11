//! Compiles the client public graph without Server, Instance, PTY, VT or Render imports.
const std = @import("std");
const client = @import("server_client");
const protocol = @import("server_protocol");

test "client-only public graph owns no canonical process or runtime" {
    std.testing.refAllDecls(client);
    std.testing.refAllDecls(client.terminal);
    try std.testing.expect(client.protocol == protocol);
    try std.testing.expect(client.terminal.protocol == protocol.terminal);
    inline for (.{ "Runtime", "Server", "Session", "instance", "pty", "render" }) |name| {
        try std.testing.expect(!@hasDecl(client, name));
        try std.testing.expect(!@hasDecl(client.terminal, name));
    }
}
