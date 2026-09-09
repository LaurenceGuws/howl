//! Full shared terminal-renderer WebAssembly canary.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .cpu_features_add = std.Target.wasm.featureSet(&.{ .exception_handling, .reference_types }),
    });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const client_module = client.module("howl_client");
    const session_module = client_module.import_table.get("howl_session") orelse
        @panic("howl-client lost its session protocol import");
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .native_text = true,
        .generated_glyphs = false,
        .bundled_text = true,
    });
    const text = b.dependency("howl_text", .{
        .target = target,
        .optimize = optimize,
        .bundled = true,
    });
    const root = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .strip = true,
    });
    root.addImport("howl_client", client_module);
    root.addImport("howl_render", render.module("howl_render"));
    root.export_symbol_names = &.{
        "font_ptr",   "font_capacity", "run",       "report_ptr", "report_len",
        "pixels_ptr", "pixels_len",    "error_ptr", "error_len",
    };
    const wasm = b.addExecutable(.{ .name = "howl-render-proof", .root_module = root });
    wasm.entry = .disabled;
    wasm.export_memory = true;
    wasm.initial_memory = 96 * 1024 * 1024;
    wasm.max_memory = 128 * 1024 * 1024;
    wasm.wasi_exec_model = .reactor;

    const check = b.step("check", "Run shared terminal renderer in Wasm on one bounded semantic view");
    const run = b.addSystemCommand(&.{ "node", "tests/check.mjs" });
    run.setCwd(b.path("."));
    run.addFileArg(wasm.getEmittedBin());
    run.addFileArg(text.path("testdata/primary.ttf"));
    check.dependOn(&run.step);

    const live_root = b.createModule(.{
        .root_source_file = b.path("live.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .strip = true,
    });
    live_root.addImport("howl_session", session_module);
    live_root.addImport("howl_client", client_module);
    live_root.addImport("howl_render", render.module("howl_render"));
    live_root.export_symbol_names = &.{
        "rv_font_ptr",               "rv_font_capacity", "rv_fallback_font_ptr",
        "rv_fallback_font_capacity", "rv_snapshot_ptr",  "rv_snapshot_capacity",
        "rv_frame_ptr",              "rv_frame_len",     "rv_pixels_ptr",
        "rv_pixels_len",             "rv_error_ptr",     "rv_error_len",
        "rv_render_count",           "rv_ready",         "rv_init",
        "rv_reset",                  "rv_render",        "rv_ack",
    };
    const live = b.addExecutable(.{ .name = "howl-live-render", .root_module = live_root });
    live.entry = .disabled;
    live.export_memory = true;
    live.initial_memory = 128 * 1024 * 1024;
    live.max_memory = 192 * 1024 * 1024;
    live.wasi_exec_model = .reactor;

    // The accepted check compiles both the synthetic proof and the live renderer.
    check.dependOn(&live.step);
    const asset_contract_test = b.addSystemCommand(&.{ "node", "tests/asset_contract.mjs" });
    asset_contract_test.setCwd(b.path("."));
    asset_contract_test.setName("browser module asset contract");
    check.dependOn(&asset_contract_test.step);
    const host_syntax = b.addSystemCommand(&.{ "node", "--check", "web/host.mjs" });
    host_syntax.setCwd(b.path("."));
    host_syntax.setName("live browser host syntax");
    check.dependOn(&host_syntax.step);
    const input_test = b.addSystemCommand(&.{ "node", "tests/input.mjs" });
    input_test.setCwd(b.path("."));
    input_test.setName("browser semantic input staging");
    check.dependOn(&input_test.step);
    const queue_test = b.addSystemCommand(&.{ "node", "tests/control_queue.mjs" });
    queue_test.setCwd(b.path("."));
    queue_test.setName("browser control queue");
    check.dependOn(&queue_test.step);
    const display_test = b.addSystemCommand(&.{ "node", "tests/display_schedule.mjs" });
    display_test.setCwd(b.path("."));
    display_test.setName("browser display scheduler");
    check.dependOn(&display_test.step);
    const resize_policy_test = b.addSystemCommand(&.{ "node", "tests/resize_policy.mjs" });
    resize_policy_test.setCwd(b.path("."));
    resize_policy_test.setName("browser resize authority policy");
    check.dependOn(&resize_policy_test.step);
    const lifecycle_policy_test = b.addSystemCommand(&.{ "node", "tests/lifecycle_policy.mjs" });
    lifecycle_policy_test.setCwd(b.path("."));
    lifecycle_policy_test.setName("browser lifecycle recovery policy");
    check.dependOn(&lifecycle_policy_test.step);
    const frame_scheduler_test = b.addSystemCommand(&.{ "node", "tests/frame_scheduler.mjs" });
    frame_scheduler_test.setCwd(b.path("."));
    frame_scheduler_test.setName("browser latest-frame scheduler");
    check.dependOn(&frame_scheduler_test.step);
    const telemetry_test = b.addSystemCommand(&.{ "node", "tests/telemetry.mjs" });
    telemetry_test.setCwd(b.path("."));
    telemetry_test.setName("browser telemetry ring");
    check.dependOn(&telemetry_test.step);
    const history_test = b.addSystemCommand(&.{ "node", "tests/history.mjs" });
    history_test.setCwd(b.path("."));
    history_test.setName("browser history viewport model");
    check.dependOn(&history_test.step);

    const web = b.step("web", "Build the local-only live terminal renderer site");
    web.dependOn(&b.addInstallFile(live.getEmittedBin(), "live-web/render.wasm").step);
    web.dependOn(&b.addInstallFile(text.path("testdata/fira-code-medium.otf"), "live-web/font.bin").step);
    web.dependOn(&b.addInstallFile(text.path("testdata/primary.ttf"), "live-web/fallback-font.bin").step);
    web.dependOn(&b.addInstallFile(text.path("LICENSES/test-fonts.txt"), "live-web/font-licences.txt").step);
    web.dependOn(&b.addInstallFile(text.path("LICENSES/bundled-dependencies.txt"), "live-web/dependencies.txt").step);
    inline for (.{ "index.html", "host.mjs", "lifecycle_policy.mjs", "input.mjs", "history.mjs", "control_queue.mjs", "telemetry.mjs", "frame_scheduler.mjs", "display_schedule.mjs", "resize_policy.mjs", "style.css", "manifest.webmanifest", "sw.js", "icon.png" }) |file| {
        web.dependOn(&b.addInstallFile(b.path("web/" ++ file), "live-web/" ++ file).step);
    }
    // The restricted WASI host is shared with the preceding text canary. Keep
    // one implementation while Web is still a monorepo-local experimental client.
    web.dependOn(&b.addInstallFile(.{ .cwd_relative = "../text/web/runtime.mjs" }, "live-web/runtime.mjs").step);

    b.default_step = check;
}
