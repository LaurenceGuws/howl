//! Maintained WebAssembly canary; never part of the native core dependency graph.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = .ReleaseSafe });
    const client_module = client.module("howl_client");
    const session_module = client_module.import_table.get("howl_session") orelse
        @panic("howl-client lost its owned session protocol dependency");
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = .ReleaseSafe,
        .native_text = false,
        .generated_glyphs = false,
    });
    const root = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    root.addImport("howl_client", client_module);
    root.addImport("howl_session", session_module);
    root.addImport("howl_render", render.module("howl_render"));
    const wasm = b.addExecutable(.{ .name = "howl-web", .root_module = root });
    wasm.entry = .disabled;
    root.export_symbol_names = &.{
        "hw_input_ptr",    "hw_input_capacity", "hw_output_ptr",   "hw_output_len",
        "hw_text_ptr",     "hw_text_len",       "hw_snapshot_ptr", "hw_snapshot_len",
        "hw_error_ptr",    "hw_error_len",      "hw_phase",        "hw_identity",
        "hw_revision",     "hw_rows",           "hw_columns",      "hw_reset",
        "hw_observe",      "hw_send_text",      "hw_feed",         "hw_finish",
        "hw_canvas_check",
    };
    wasm.export_memory = true;
    wasm.initial_memory = 32 * 1024 * 1024;
    wasm.max_memory = 32 * 1024 * 1024;
    b.installArtifact(wasm);

    const check = b.step("check", "Run the zero-import Wasm wire and Canvas contract");
    const test_command = b.addSystemCommand(&.{ "node", "tests/check.mjs" });
    test_command.setCwd(b.path("."));
    test_command.addFileArg(wasm.getEmittedBin());
    check.dependOn(&test_command.step);
    const live = b.step("live", "Test this Wasm client against a caller-supplied disposable Howl endpoint");
    const live_command = b.addSystemCommand(&.{ "node", "tests/live.mjs" });
    live_command.setCwd(b.path("."));
    live_command.addFileArg(wasm.getEmittedBin());
    live_command.addPassthruArgs();
    live.dependOn(&live_command.step);
    const text_check = b.step("text-check", "Run the native/Wasm text engine and runtime parity gate");
    const text_run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "check", "-j2" });
    text_run.setCwd(b.path("text"));
    text_check.dependOn(&text_run.step);
    const text_web = b.step("text-web", "Build the local-only browser font/raster canary");
    const text_site = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "web", "-j2" });
    text_site.setCwd(b.path("text"));
    text_web.dependOn(&text_site.step);
    const render_check = b.step("render-check", "Run the shared terminal renderer in Wasm");
    const render_run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "check", "-j2" });
    render_run.setCwd(b.path("render"));
    render_check.dependOn(&render_run.step);
    const render_web = b.step("render-web", "Build the local-only live browser renderer canary");
    const render_site = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "web", "-j2" });
    render_site.setCwd(b.path("render"));
    render_web.dependOn(&render_site.step);
    const gateway_check = b.step("gateway-check", "Run the maintained loopback WebSocket gateway proofs");
    const gateway_tests = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "check", "test" });
    gateway_tests.setCwd(b.path("gateway"));
    gateway_check.dependOn(&gateway_tests.step);
    const gateway_install = b.step("gateway-install", "Build the maintained loopback WebSocket gateway");
    const gateway_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "install", "-Doptimize=ReleaseSafe" });
    gateway_build.setCwd(b.path("gateway"));
    gateway_install.dependOn(&gateway_build.step);
    b.default_step = check;
}
