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

    // Both entry points share this exact private owner. It imports only PTY/VT.
    const runtime = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.addImport("howl_pty", pty.module("howl_pty"));
    runtime.addImport("howl_vt", vt.module("howl_vt"));

    const publication = b.createModule(.{
        .root_source_file = b.path("src/publication.zig"),
        .target = target,
        .optimize = optimize,
    });
    publication.addImport("howl_render", render.module("howl_render"));

    const module = b.addModule("howl_instance", .{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("instance_runtime", runtime);
    module.addImport("howl_render", render.module("howl_render"));
    module.addImport("instance_publication", publication);

    const headless = b.addModule("howl_instance_headless", .{
        .root_source_file = b.path("src/headless.zig"),
        .target = target,
        .optimize = optimize,
    });
    headless.addImport("instance_runtime", runtime);

    // Expose the exact composition modules rather than asking embedders to
    // instantiate sibling copies with independent type identity.
    exposeModule(b, "howl_pty", pty.module("howl_pty"));
    exposeModule(b, "howl_vt", vt.module("howl_vt"));
    exposeModule(b, "howl_render", render.module("howl_render"));
    exposeModule(b, "howl_render_limits", render.module("howl_render_limits"));
    exposeModule(b, "howl_text", text.module("howl_text"));
    exposeModule(b, "howl_text_test_fonts", text.module("howl_text_test_fonts"));

    const tests = compositionProofs(b, target, optimize, pty.module("howl_pty"), vt.module("howl_vt"), render.module("howl_render"), publication, text.module("howl_text_test_fonts"));
    const headless_proofs = compositionProofs(b, target, optimize, pty.module("howl_pty"), vt.module("howl_vt"), null, null, null);

    const boundary_root = b.createModule(.{
        .root_source_file = b.path("test/headless.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary_root.addImport("howl_instance_headless", headless);
    const boundary = b.addTest(.{
        .name = "howl-instance-headless-api",
        .root_module = boundary_root,
        .use_llvm = false,
        .use_lld = false,
    });

    const publication_proofs = b.addTest(.{
        .name = "howl-instance-publication",
        .root_module = publication,
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
    check.dependOn(&headless_proofs.step);
    check.dependOn(&boundary.step);
    check.dependOn(&publication_proofs.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&b.addRunArtifact(headless_proofs).step);
    test_step.dependOn(&b.addRunArtifact(boundary).step);
    test_step.dependOn(&b.addRunArtifact(publication_proofs).step);
    b.default_step = check;
}

fn exposeModule(b: *std.Build, name: []const u8, module: *std.Build.Module) void {
    std.debug.assert(!b.modules.contains(name));
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    b.modules.put(b.allocator, name, module) catch @panic("OOM");
}

fn compositionProofs(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pty: *std.Build.Module,
    vt: *std.Build.Module,
    render: ?*std.Build.Module,
    publication: ?*std.Build.Module,
    fonts: ?*std.Build.Module,
) *std.Build.Step.Compile {
    const root = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("howl_pty", pty);
    root.addImport("howl_vt", vt);
    const options = b.addOptions();
    options.addOption(bool, "presentation", render != null);
    root.addOptions("composition_options", options);
    if (render) |module| {
        root.addImport("howl_render", module);
        root.addImport("instance_publication", publication.?);
        root.addImport("test_fonts", fonts.?);
    }
    return b.addTest(.{
        .name = if (render != null) "howl-instance" else "howl-instance-headless",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
}
