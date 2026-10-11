const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bundled_render_text = b.option(
        bool,
        "bundled_render_text",
        "Build Instance-owned Render with bundled howl-text",
    ) orelse false;
    const linux = target.result.os.tag == .linux;
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .bundled_text = bundled_render_text,
    });
    const text = b.dependency("howl_text", .{
        .target = target,
        .optimize = optimize,
        .bundled = bundled_render_text,
    });
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });

    // HWLS is transport-neutral client/server vocabulary. Export it separately
    // so remote clients do not inherit the local PTY/VT ownership module merely
    // to encode and decode the frozen wire.
    const protocol = b.addModule("howl_instance_protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("howl_instance", .{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_pty", pty.module("howl_pty"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addImport("howl_vt", vt.module("howl_vt"));
    module.addImport("howl_instance_protocol", protocol);

    // Expose the exact composition modules rather than asking embedders to
    // instantiate sibling copies with independent type identity.
    exposeModule(b, "howl_pty", pty.module("howl_pty"));
    exposeModule(b, "howl_vt", vt.module("howl_vt"));
    exposeModule(b, "howl_render", render.module("howl_render"));
    exposeModule(b, "howl_render_limits", render.module("howl_render_limits"));
    exposeModule(b, "howl_text", text.module("howl_text"));
    exposeModule(b, "howl_text_test_fonts", text.module("howl_text_test_fonts"));

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("howl_pty", pty.module("howl_pty"));
    test_module.addImport("howl_render", render.module("howl_render"));
    test_module.addImport("howl_vt", vt.module("howl_vt"));
    test_module.addImport("howl_instance_protocol", protocol);
    test_module.addImport("test_fonts", text.module("howl_text_test_fonts"));

    const tests = b.addTest(.{
        .name = "howl-instance",
        .root_module = test_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const wire_command = b.addSystemCommand(&.{
        "python3",
        "tools/validate_vectors.py",
        "protocol/v10-vectors.json",
    });
    wire_command.setName("howl-instance wire vectors");
    wire_command.setCwd(b.path("."));
    const wire = b.step("wire", "Validate the language-neutral instance wire corpus");
    wire.dependOn(&wire_command.step);

    const check = b.step("check", "Compile one canonical PTY and VT instance");
    check.dependOn(wire);
    check.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(wire);
    test_step.dependOn(&run_tests.step);
    const service_module = b.addModule("howl_instance_service", .{
        .root_source_file = b.path("src/service.zig"),
        .target = target,
        .optimize = optimize,
    });
    service_module.addImport("howl_instance", module);
    if (linux) {
        const service_tests = b.addTest(.{
            .name = "howl-instance-service",
            .root_module = service_module,
            .use_llvm = false,
            .use_lld = false,
        });
        check.dependOn(&service_tests.step);
        test_step.dependOn(&b.addRunArtifact(service_tests).step);
    }
    b.default_step = check;
}

fn exposeModule(b: *std.Build, name: []const u8, module: *std.Build.Module) void {
    std.debug.assert(!b.modules.contains(name));
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    b.modules.put(b.allocator, name, module) catch @panic("OOM");
}
