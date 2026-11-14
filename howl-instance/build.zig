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
    module.addImport("howl_pty", pty.module("howl_pty"));
    module.addImport("howl_vt", vt.module("howl_vt"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addImport("instance_publication", publication);
    const support = render.module("howl_vt_output").import_table.get("text_support").?;
    module.addImport("text_support", support);
    module.addImport("output_state", render.module("howl_vt_output").import_table.get("output_state").?);

    // Expose the exact composition modules rather than asking embedders to
    // instantiate sibling copies with independent type identity.
    exposeModule(b, "howl_pty", pty.module("howl_pty"));
    exposeModule(b, "howl_vt", vt.module("howl_vt"));
    exposeModule(b, "howl_vt_native", vt.module("howl_vt_native"));
    exposeModule(b, "howl_render", render.module("howl_render"));
    exposeModule(b, "howl_render_native", render.module("howl_render_native"));
    exposeModule(b, "howl_render_limits", render.module("howl_render_limits"));
    exposeModule(b, "howl_vt_output", render.module("howl_vt_output"));
    exposeModule(b, "howl_vt_output_commands", render.module("howl_vt_output_commands"));
    exposeModule(b, "howl_vt_output_limits", render.module("howl_vt_output_limits"));
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
    const abi_owner = b.createModule(.{ .root_source_file = b.path("src/abi_owner.zig"), .target = target, .optimize = optimize, .link_libc = true });
    abi_owner.addImport("howl_instance", module);
    abi_owner.addImport("howl_vt_native", vt.module("howl_vt_native"));
    abi_owner.addImport("test_fonts", text.module("howl_text_test_fonts"));
    const abi_root = b.createModule(.{ .root_source_file = b.path("src/abi.zig"), .target = target, .optimize = optimize, .link_libc = true });
    abi_root.addImport("instance_native", native);
    abi_root.addImport("instance_abi_owner", abi_owner);
    abi_root.addImport("howl_instance", module);
    abi_root.addImport("instance_native_frames", native_frames);
    const native_library = b.addLibrary(.{ .name = "howl_instance_native", .linkage = .static, .root_module = abi_root, .use_llvm = false, .use_lld = false });
    native_library.installHeader(b.path("include/howl_instance_native.h"), "howl_instance_native.h");
    native_library.installHeader(vt.namedLazyPath("howl_vt_native_header"), "howl_vt_native.h");
    native_library.installHeader(render.namedLazyPath("howl_render_native_header"), "howl_render_native.h");
    b.installArtifact(native_library);
    // Forward the exact VT companion used to release module-owned Readers.
    b.installArtifact(vt.artifact("howl_vt_native"));

    const test_root = b.createModule(.{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_root.addImport("howl_pty", pty.module("howl_pty"));
    test_root.addImport("howl_vt", vt.module("howl_vt"));
    test_root.addImport("howl_render", render.module("howl_render"));
    test_root.addImport("instance_publication", publication);
    test_root.addImport("text_support", support);
    test_root.addImport("howl_vt_output", render.module("howl_vt_output"));
    test_root.addImport("output_state", render.module("howl_vt_output").import_table.get("output_state").?);
    test_root.addImport("test_fonts", text.module("howl_text_test_fonts"));
    const tests = b.addTest(.{
        .name = "howl-instance",
        .root_module = test_root,
        .use_llvm = false,
        .use_lld = false,
    });
    const publication_proofs = b.addTest(.{
        .name = "howl-instance-publication",
        .root_module = publication,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile one canonical PTY, VT and Render instance");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&tests.step);
    check.dependOn(&publication_proofs.step);
    check.dependOn(&native_library.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&b.addRunArtifact(publication_proofs).step);
    if (target.result.os.tag == .linux) {
        const abi_owner_tests = b.addTest(.{ .name = "howl-instance-c-owner", .root_module = abi_owner, .use_llvm = false, .use_lld = false });
        check.dependOn(&abi_owner_tests.step);
        const abi_owner_run = b.addRunArtifact(abi_owner_tests);
        test_step.dependOn(&abi_owner_run.step);
        b.step("test:c-owner", "Qualify private C owner and retired-safe VT observation").dependOn(&abi_owner_run.step);
        const admission_root = b.createModule(.{ .root_source_file = b.path("src/abi_presentation.zig"), .target = target, .optimize = optimize, .link_libc = true });
        admission_root.addImport("howl_instance", module);
        admission_root.addImport("instance_native", native);
        admission_root.addImport("test_fonts", text.module("howl_text_test_fonts"));
        const admission = b.addTest(.{ .name = "howl-instance-native-presentation-admission", .root_module = admission_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&admission.step);
        const admission_run = b.addRunArtifact(admission);
        test_step.dependOn(&admission_run.step);
        const presentation_step = b.step("test:native-presentation", "Qualify standalone C construction and ownership");
        presentation_step.dependOn(&admission_run.step);
        const presentation_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        presentation_root.linkLibrary(native_library);
        presentation_root.linkLibrary(vt.artifact("howl_vt_native"));
        presentation_root.addCSourceFile(.{ .file = b.path("test/native_presentation.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const presentation_proof = b.addExecutable(.{ .name = "howl-instance-native-presentation", .root_module = presentation_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&presentation_proof.step);
        const presentation_run = b.addRunArtifact(presentation_proof);
        presentation_run.addFileArg(text.namedLazyPath("howl_text_test_font"));
        test_step.dependOn(&presentation_run.step);
        presentation_step.dependOn(&presentation_run.step);
        const foreign_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        foreign_root.linkLibrary(native_library);
        foreign_root.linkLibrary(vt.artifact("howl_vt_native"));
        foreign_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
        foreign_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const foreign = b.addExecutable(.{ .name = "howl-instance-native-consumer", .root_module = foreign_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&foreign.step);
        const run_foreign = b.addRunArtifact(foreign);
        run_foreign.addFileArg(text.namedLazyPath("howl_text_test_font"));
        test_step.dependOn(&run_foreign.step);
        b.step("test:native", "Qualify the standalone Instance C lifecycle").dependOn(&run_foreign.step);
        // Exercise the same foreign proof inside a host-owned shared library.
        const shared_root = b.createModule(.{ .root_source_file = b.path("test/static_embedding.zig"), .target = target, .optimize = optimize, .link_libc = true });
        shared_root.linkLibrary(native_library);
        shared_root.linkLibrary(vt.artifact("howl_vt_native"));
        shared_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
        shared_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Dmain=howl_instance_static_c" } });
        const shared = b.addLibrary(.{ .name = "howl_instance_static_embedding", .linkage = .dynamic, .root_module = shared_root, .use_llvm = false, .use_lld = false });
        const shared_driver_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
        shared_driver_root.linkLibrary(shared);
        shared_driver_root.addCSourceFile(.{ .file = b.path("test/static_embedding.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        const shared_driver = b.addExecutable(.{ .name = "howl-instance-static-embedding", .root_module = shared_driver_root, .use_llvm = false, .use_lld = false });
        check.dependOn(&shared_driver.step);
        const shared_run = b.addRunArtifact(shared_driver);
        shared_run.addFileArg(text.namedLazyPath("howl_text_test_font"));
        test_step.dependOn(&shared_run.step);
        b.step("test:static-embedding", "Qualify static Instance ABI inside a foreign shared library").dependOn(&shared_run.step);

        const frame_root = b.createModule(.{ .root_source_file = b.path("test/native_frames.zig"), .target = target, .optimize = optimize, .link_libc = true });
        frame_root.addImport("howl_instance", module);
        frame_root.addImport("howl_instance_native", native);
        frame_root.addImport("howl_instance_frames_native", native_frames);
        frame_root.addImport("test_fonts", text.module("howl_text_test_fonts"));
        frame_root.linkLibrary(native_library);
        frame_root.linkLibrary(vt.artifact("howl_vt_native"));
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
