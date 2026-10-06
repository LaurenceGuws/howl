const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linux_desktop = target.result.os.tag == .linux and target.result.abi != .android;
    const windows = target.result.os.tag == .windows;
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const transport = b.dependency("client_transport", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_client", .{
        .root_source_file = b.path("src/howl_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_instance_protocol", instance.module("howl_instance_protocol"));
    module.addImport("client_transport", transport.module("client_transport"));

    // Optional desktop-only Local ownership. Keeping this as a sibling module
    // means ordinary remote clients still import only the transport-neutral
    // howl_client module and do not inherit PTY/VT/process ownership.
    const local = b.addModule("howl_local", .{
        .root_source_file = b.path(if (linux_desktop or windows)
            "src/local_desktop.zig"
        else
            "src/local_unsupported.zig"),
        .target = target,
        .optimize = optimize,
    });
    local.addImport("howl_client", module);
    local.addImport("client_transport", transport.module("client_transport"));
    local.addImport("howl_instance", instance.module("howl_instance"));
    local.addImport("howl_instance_service", instance.module("howl_instance_service"));
    if (windows) local.linkSystemLibrary("kernel32", .{});

    const tests = b.addTest(.{
        .name = "howl-client",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const local_tests = b.addTest(.{
        .name = "howl-local",
        .root_module = local,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the reusable native Howl client");
    check.dependOn(&tests.step);
    check.dependOn(&local_tests.step);
    const audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    audit.setCwd(b.path("."));
    check.dependOn(&audit.step);
    const test_step = b.step("test", "Run native Howl client framing proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(local_tests).step);
    b.default_step = check;
}
