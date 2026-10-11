const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const codec = b.dependency("howl_vt", .{ .target = target, .optimize = optimize }).module("howl_vt_codec");

    const protocol_module = b.dependency("server_protocol", .{
        .target = target,
        .optimize = optimize,
    }).module("server_protocol");

    const terminal_service = b.addModule("server_terminal_service", .{
        .root_source_file = b.path("src/terminal_service.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_service.addImport("howl_instance", instance.module("howl_instance_headless"));
    terminal_service.addImport("server_protocol", protocol_module);
    terminal_service.addImport("howl_vt_codec", codec);

    const module = b.addModule("server", .{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("server_protocol", protocol_module);
    module.addImport("howl_instance", instance.module("howl_instance_headless"));
    module.addImport("server_terminal_service", terminal_service);

    const tests = b.addTest(.{
        .name = "server",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });

    const service_module = b.addModule("server_service", .{
        .root_source_file = b.path("src/service.zig"),
        .target = target,
        .optimize = optimize,
    });
    service_module.addImport("server_model", module);
    service_module.addImport("server_protocol", protocol_module);
    service_module.addImport("howl_instance", instance.module("howl_instance_headless"));
    const service_tests = b.addTest(.{
        .name = "server-service",
        .root_module = service_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile Server -> Sessions -> Instances ownership");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&tests.step);
    check.dependOn(&service_tests.step);
    const test_step = b.step("test", "Run Server -> Sessions -> Instances ownership proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(service_tests).step);
    if (target.result.os.tag == .linux) {
        const terminal_proofs = b.addTest(.{
            .name = "server-terminal-service",
            .root_module = terminal_service,
            .use_llvm = false,
            .use_lld = false,
        });
        check.dependOn(&terminal_proofs.step);
        test_step.dependOn(&b.addRunArtifact(terminal_proofs).step);
    }
    const boundary_root = b.createModule(.{
        .root_source_file = b.path("test/owner.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary_root.addImport("server", module);
    const boundary = b.addTest(.{
        .name = "server-owner-api",
        .root_module = boundary_root,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&boundary.step);
    test_step.dependOn(&b.addRunArtifact(boundary).step);
    b.default_step = check;
}
