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
    const terminal = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    const terminal_proofs = b.addTest(.{
        .name = "server-terminal-wire",
        .root_module = terminal,
        .use_llvm = false,
        .use_lld = false,
    });
    const vectors = b.addSystemCommand(&.{
        "python3", "tools/validate_vectors.py", "protocol/v10-vectors.json",
    });
    vectors.setCwd(b.path("."));
    const wire = b.step("wire", "Validate the Server terminal wire corpus");
    wire.dependOn(&vectors.step);
    const check = b.step("check", "Compile the bounded Server wire");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&proofs.step);
    check.dependOn(&terminal_proofs.step);
    check.dependOn(wire);
    const test_step = b.step("test", "Run Server control and terminal wire proofs");
    test_step.dependOn(&b.addRunArtifact(proofs).step);
    test_step.dependOn(&b.addRunArtifact(terminal_proofs).step);
    test_step.dependOn(wire);
    b.default_step = check;
}
