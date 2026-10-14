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
    exposeModule(b, "howl_vt_native", vt.module("howl_vt_native"));
    exposeModule(b, "howl_render", render.module("howl_render"));
    exposeModule(b, "howl_render_native", render.module("howl_render_native"));
    exposeModule(b, "howl_render_limits", render.module("howl_render_limits"));
    exposeModule(b, "howl_text", text.module("howl_text"));
    exposeModule(b, "howl_text_test_fonts", text.module("howl_text_test_fonts"));

    const native_frames = b.addModule("howl_instance_frames_native", .{ .root_source_file = b.path("src/native_frames.zig"), .target = target, .optimize = optimize });
    native_frames.addImport("howl_instance", module);
    native_frames.addImport("howl_render_native", render.module("howl_render_native"));

    const native_types = b.addTranslateC(.{ .root_source_file = b.path("include/howl_instance_native.h"), .target = target, .optimize = optimize });
    native_types.addIncludePath(vt.namedLazyPath("howl_vt_native_header").dirname());
    native_types.addIncludePath(render.namedLazyPath("howl_render_native_header").dirname());
    const native = b.addModule("howl_instance_native", .{ .root_source_file = b.path("src/native.zig"), .target = target, .optimize = optimize, .link_libc = true });
    native.addImport("howl_instance", module);
    native.addImport("howl_vt_native", vt.module("howl_vt_native"));
    native.addImport("instance_native_types", native_types.createModule());
    native_frames.addImport("instance_native", native);
    const abi_root = b.createModule(.{ .root_source_file = b.path("src/abi.zig"), .target = target, .optimize = optimize, .link_libc = true });
    abi_root.addImport("instance_native", native);
    abi_root.addImport("howl_instance", module);
    abi_root.addImport("instance_native_frames", native_frames);
    const native_library = b.addLibrary(.{ .name = "howl_instance_native", .linkage = .dynamic, .root_module = abi_root, .use_llvm = false, .use_lld = false });
    native_library.installHeader(b.path("include/howl_instance_native.h"), "howl_instance_native.h");
    native_library.installHeader(vt.namedLazyPath("howl_vt_native_header"), "howl_vt_native.h");
    native_library.installHeader(render.namedLazyPath("howl_render_native_header"), "howl_render_native.h");
    b.installArtifact(native_library);

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
    check.dependOn(&native_library.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&b.addRunArtifact(headless_proofs).step);
    test_step.dependOn(&b.addRunArtifact(boundary).step);
    test_step.dependOn(&b.addRunArtifact(publication_proofs).step);
    if (target.result.os.tag == .linux) {
        const admission_root = b.createModule(.{ .root_source_file = b.path("src/abi_presentation.zig"), .target = target, .optimize = optimize, .link_libc = true });
        admission_root.addImport("howl_instance", module);
        admission_root.addImport("instance_native", native);
        admission_root.addImport("test_fonts", text.module("howl_text_test_fonts"));
        const admission = b.addTest(.{ .name = "howl-instance-native-presentation-admission", .root_module = admission_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&admission.step);
        const admission_run = b.addRunArtifact(admission);
        test_step.dependOn(&admission_run.step);
        const presented_step = b.step("test:native-presentation", "Qualify standalone C presented construction and ownership");
        presented_step.dependOn(&admission_run.step);
        const presented_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        presented_root.linkLibrary(native_library);
        presented_root.addCSourceFile(.{ .file = b.path("test/native_presented.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const presented = b.addExecutable(.{ .name = "howl-instance-native-presented", .root_module = presented_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&presented.step);
        const presented_run = b.addRunArtifact(presented);
        presented_run.addFileArg(text.namedLazyPath("howl_text_test_font"));
        test_step.dependOn(&presented_run.step);
        presented_step.dependOn(&presented_run.step);
        const foreign_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        foreign_root.linkLibrary(native_library);
        foreign_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
        foreign_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const foreign = b.addExecutable(.{ .name = "howl-instance-native-consumer", .root_module = foreign_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&foreign.step);
        const run_foreign = b.addRunArtifact(foreign);
        test_step.dependOn(&run_foreign.step);
        b.step("test:native", "Qualify the standalone Instance C lifecycle").dependOn(&run_foreign.step);
        const frame_root = b.createModule(.{ .root_source_file = b.path("test/native_frames.zig"), .target = target, .optimize = optimize, .link_libc = true });
        frame_root.addImport("howl_instance", module);
        frame_root.addImport("howl_instance_native", native);
        frame_root.addImport("howl_instance_frames_native", native_frames);
        frame_root.addImport("test_fonts", text.module("howl_text_test_fonts"));
        frame_root.linkLibrary(native_library);
        frame_root.addCSourceFile(.{ .file = b.path("test/native_frame_peer.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const frame_proof = b.addTest(.{ .name = "howl-instance-native-frames", .root_module = frame_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&frame_proof.step);
        const frame_run = b.addRunArtifact(frame_proof);
        test_step.dependOn(&frame_run.step);
        const frame_units = b.addTest(.{ .name = "howl-instance-native-frame-envelope", .root_module = native_frames, .use_llvm = false, .use_lld = false });
        check.dependOn(&frame_units.step);
        const frame_unit_run = b.addRunArtifact(frame_units);
        test_step.dependOn(&frame_unit_run.step);
        const frame_step = b.step("test:native-frames", "Qualify foreign frame projection and checked lifetimes");
        frame_step.dependOn(&frame_run.step);
        frame_step.dependOn(&frame_unit_run.step);
    }
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
