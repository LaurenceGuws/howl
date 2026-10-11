const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bundled_render_text = b.option(
        bool,
        "bundled_render_text",
        "Build Instance-owned Render with bundled howl-text",
    ) orelse false;
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

    const module = b.addModule("howl_instance", .{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_pty", pty.module("howl_pty"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addImport("howl_vt", vt.module("howl_vt"));

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
    test_module.addImport("test_fonts", text.module("howl_text_test_fonts"));

    const tests = b.addTest(.{
        .name = "howl-instance",
        .root_module = test_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile one canonical PTY and VT instance");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(&run_tests.step);
    b.default_step = check;
}

fn exposeModule(b: *std.Build, name: []const u8, module: *std.Build.Module) void {
    std.debug.assert(!b.modules.contains(name));
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    b.modules.put(b.allocator, name, module) catch @panic("OOM");
}
