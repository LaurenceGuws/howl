const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Compatibility spellings retained while platform scripts stop provisioning
    // a second text stack. Instance-owned Render now owns text on every target.
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "repo", "Deprecated: sources resolve through package dependencies");
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "ndk", "Deprecated: Instance-owned Render owns bundled Android text");
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "deps", "Deprecated: Instance-owned Render owns bundled platform text");
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "freetype-include", "Deprecated: text include override");
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "harfbuzz-include", "Deprecated: text include override");
    // zig-audit: acknowledge discard
    // reason: The maintained platform scripts still supply this deprecated spelling; registering it consumes the option while package dependencies own the actual text sources.
    _ = b.option([]const u8, "apple-sdk", "Deprecated: Instance-owned Render owns bundled Apple text");

    const bundled_render_text =
        target.result.os.tag != .linux or target.result.abi == .android;
    const client_dependency = b.dependency("server", .{
        .target = target,
        .optimize = optimize,
        .bundled_render_text = bundled_render_text,
    });
    const client = client_dependency.module("server_client");
    const terminal = client_dependency.module("server_client_render");

    const instance = if (bundled_render_text)
        b.dependency("howl_instance", .{ .target = target, .optimize = optimize, .bundled_render_text = true })
    else
        b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const local = b.createModule(.{
        .root_source_file = b.path("local.zig"),
        .target = target,
        .optimize = optimize,
    });
    local.addImport("howl_instance", instance.module("howl_instance"));

    const root = b.createModule(.{
        .root_source_file = b.path("host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("local_owner", local);
    root.addImport("howl_instance", instance.module("howl_instance"));
    root.addImport("howl_vt_native", instance.module("howl_vt_native"));
    root.addImport("test_fonts", instance.module("howl_text_test_fonts"));
    root.addImport("server_client", client);
    root.addImport("server_client_native", client_dependency.module("server_client_native"));
    root.addImport("server_client_render", terminal);

    const object = b.addObject(.{
        .name = "howl_flutter_native_host",
        .root_module = root,
        .use_llvm = true,
        .use_lld = false,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(object, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "howl_flutter_native_host.o",
    }).step);

    const tests = b.addTest(.{
        .name = "howl_flutter_native_host_tests",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
    const local_tests = b.addTest(.{
        .name = "howl_flutter_direct_local_tests",
        .root_module = local,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the Flutter native host and all its proofs");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&object.step);
    check.dependOn(&tests.step);
    check.dependOn(&local_tests.step);
    const test_step = b.step("test", "Run native host presentation-lattice proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(local_tests).step);
}
