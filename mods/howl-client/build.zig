const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linux_desktop = target.result.os.tag == .linux and target.result.abi != .android;
    const windows = target.result.os.tag == .windows;
    const bundled_render_text = b.option(
        bool,
        "bundled_render_text",
        "Build the transitional client Render adapter with bundled howl-text",
    ) orelse false;
    const instance = if (bundled_render_text)
        b.dependency("howl_instance", .{
            .target = target,
            .optimize = optimize,
            .bundled_render_text = true,
        })
    else
        b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const text = b.dependency("howl_text", .{ .target = target, .optimize = optimize, .bundled = false });
    const transport = b.dependency("client_transport", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_client", .{
        .root_source_file = b.path("src/howl_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_instance_protocol", instance.module("howl_instance_protocol"));
    module.addImport("client_transport", transport.module("client_transport"));

    // Transitional transported presentation adapter. It depends outward on the
    // canonical direct-VT renderer rather than pulling Client into Render.
    const render_adapter = b.addModule("howl_client_render", .{
        .root_source_file = b.path("src/render.zig"),
        .target = target,
        .optimize = optimize,
    });
    render_adapter.addImport("howl_client", module);
    render_adapter.addImport("howl_instance", instance.module("howl_instance"));

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
    const render_test_module = b.createModule(.{
        .root_source_file = b.path("src/render_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    render_test_module.addImport("howl_client_render", render_adapter);
    render_test_module.addImport("howl_client", module);
    render_test_module.addImport("howl_instance", instance.module("howl_instance"));
    render_test_module.addImport("test_fonts", text.module("howl_text_test_fonts"));
    const render_tests = b.addTest(.{
        .name = "howl-client-render",
        .root_module = render_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the reusable native Howl client");
    check.dependOn(&tests.step);
    check.dependOn(&local_tests.step);
    check.dependOn(&render_tests.step);
    const audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    audit.setCwd(b.path("."));
    check.dependOn(&audit.step);
    const test_step = b.step("test", "Run native Howl client framing proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(local_tests).step);
    test_step.dependOn(&b.addRunArtifact(render_tests).step);
    b.default_step = check;
}
