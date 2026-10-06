const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Compatibility spellings retained while platform scripts stop provisioning
    // a second text stack. Instance-owned Render now owns text on every target.
    _ = b.option([]const u8, "repo", "Deprecated: sources resolve through package dependencies");
    _ = b.option([]const u8, "ndk", "Deprecated: Instance-owned Render owns bundled Android text");
    _ = b.option([]const u8, "deps", "Deprecated: Instance-owned Render owns bundled platform text");
    _ = b.option([]const u8, "freetype-include", "Deprecated: text include override");
    _ = b.option([]const u8, "harfbuzz-include", "Deprecated: text include override");
    _ = b.option([]const u8, "apple-sdk", "Deprecated: Instance-owned Render owns bundled Apple text");

    const bundled_render_text =
        target.result.os.tag != .linux or target.result.abi == .android;
    const client_dependency = b.dependency("howl_client", .{
        .target = target,
        .optimize = optimize,
        .bundled_render_text = bundled_render_text,
    });
    const client = client_dependency.module("howl_client");
    const local = client_dependency.module("howl_local");
    const terminal = client_dependency.module("howl_client_render");

    const server_client = b.dependency("server_client", .{
        .target = target,
        .optimize = optimize,
    }).module("server_client");

    const root = b.createModule(.{
        .root_source_file = b.path("host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("howl_client", client);
    root.addImport("howl_local", local);
    root.addImport("server_client", server_client);
    root.addImport("terminal", terminal);

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
    const check = b.step("check", "Compile the Flutter native host and all its proofs");
    check.dependOn(&object.step);
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run native host presentation-lattice proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
