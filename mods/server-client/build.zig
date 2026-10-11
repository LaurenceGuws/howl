//! Owns Server clients, private transport, optional render adaptation and their proofs.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bundled = b.option(bool, "bundled_render_text", "Build the render adapter with bundled howl-text") orelse false;
    const windows = target.result.os.tag == .windows;
    const codec = b.dependency("howl_vt", .{ .target = target, .optimize = optimize }).module("howl_vt_codec");
    const protocol = b.dependency("server_protocol", .{ .target = target, .optimize = optimize }).module("server_protocol");

    const transport = b.createModule(.{
        .root_source_file = b.path(if (windows) "src/transport/transport_windows.zig" else "src/transport/transport.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (windows) transport.linkSystemLibrary("ws2_32", .{});
    const terminal = b.createModule(.{
        .root_source_file = b.path("src/terminal/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("server_protocol", protocol);
    terminal.addImport("howl_vt_codec", codec);
    terminal.addImport("client_transport", transport);
    const module = b.addModule("server_client", .{
        .root_source_file = b.path("src/server_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("server_protocol", protocol);
    module.addImport("client_transport", transport);
    module.addImport("terminal_client", terminal);

    const render = b.dependency("howl_render", .{ .target = target, .optimize = optimize, .bundled_text = bundled });
    const adapter = b.addModule("server_client_render", .{
        .root_source_file = b.path("src/terminal/render.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter.addImport("terminal_client", terminal);
    adapter.addImport("howl_render", render.module("howl_render"));

    // Server and live terminal owners supply integration fixtures.
    const server = b.dependency("server", .{ .target = target, .optimize = optimize });
    const control_tests = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    control_tests.addImport("server_client", module);
    control_tests.addImport("server_model", server.module("server"));
    control_tests.addImport("server_service", server.module("server_service"));
    control_tests.addImport("client_transport", transport);
    const render_tests = b.createModule(.{
        .root_source_file = b.path("src/terminal/render_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    render_tests.addImport("terminal_client", terminal);
    render_tests.addImport("server_client_render", adapter);
    render_tests.addImport("howl_vt", b.dependency("howl_vt", .{ .target = target, .optimize = optimize }).module("howl_vt"));
    render_tests.addImport("test_fonts", b.dependency("howl_text", .{ .target = target, .optimize = optimize, .bundled = bundled }).module("howl_text_test_fonts"));

    const check = b.step("check", "Compile Server control, terminal, transport and render adapter proofs");
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    const tests = b.step("test", "Run Server client and private transport proofs");
    inline for (.{
        .{ "server-client", control_tests },
        .{ "server-terminal-client", terminal },
        .{ "server-client-render", render_tests },
        .{ "server-client-transport", transport },
    }) |proof| {
        const artifact = b.addTest(.{ .name = proof[0], .root_module = proof[1], .use_llvm = false, .use_lld = false });
        check.dependOn(&artifact.step);
        tests.dependOn(&b.addRunArtifact(artifact).step);
    }
    if (!windows) {
        // Separate process so the proof owns SIGPIPE policy.
        const sigpipe_root = b.createModule(.{
            .root_source_file = b.path("test/transport_sigpipe.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        sigpipe_root.addImport("client_transport", transport);
        const sigpipe = b.addExecutable(.{ .name = "server-transport-sigpipe", .root_module = sigpipe_root });
        check.dependOn(&sigpipe.step);
        tests.dependOn(&b.addRunArtifact(sigpipe).step);
    }
    b.default_step = check;
}
