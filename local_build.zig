//! Exposes local terminal ownership and rendering without transport dependencies.
const std = @import("std");

/// Adds local modules sharing one VT and Text type identity.
pub fn addModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    text: *std.Build.Module,
) void {
    const vt = b.addModule("howl_vt", .{
        .root_source_file = b.path("howl-vt/src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pty = b.addModule("howl_pty", .{
        .root_source_file = b.path(if (target.result.os.tag == .windows)
            "howl-pty/src/howl_pty_windows.zig"
        else
            "howl-pty/src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) pty.linkSystemLibrary("kernel32", .{});
    const instance = b.addModule("howl_instance", .{
        .root_source_file = b.path("howl-instance/src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    instance.addImport("howl_vt", vt);
    instance.addImport("howl_pty", pty);
    const limits = b.createModule(.{
        .root_source_file = b.path("howl-render/src/limits.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source = b.createModule(.{
        .root_source_file = b.path("howl-render/src/source.zig"),
        .target = target,
        .optimize = optimize,
    });
    const renderer = b.createModule(.{
        .root_source_file = b.path("howl-render/src/renderer.zig"),
        .target = target,
        .optimize = optimize,
    });
    renderer.addImport("limits", limits);
    renderer.addImport("source", source);
    renderer.addImport("howl_text", text);
    const local = b.createModule(.{
        .root_source_file = b.path("howl-render/src/local.zig"),
        .target = target,
        .optimize = optimize,
    });
    local.addImport("howl_vt", vt);
    local.addImport("renderer", renderer);
    local.addImport("source", source);
    const render = b.addModule("howl_render", .{
        .root_source_file = b.path("howl-render/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    render.addImport("terminal", local);
    render.addImport("limits", limits);
    render.addImport("howl_text", text);
}
