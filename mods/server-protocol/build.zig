//! Exposes the pure Server control wire without runtime or terminal ownership.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const protocol = b.addModule("server_protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    const proofs = b.addTest(.{
        .name = "server-protocol",
        .root_module = protocol,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the bounded Server wire");
    check.dependOn(&proofs.step);
    b.step("test", "Run the Server wire proofs").dependOn(&b.addRunArtifact(proofs).step);
    b.default_step = check;
}
