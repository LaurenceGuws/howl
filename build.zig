//! Publishes Howl's native Zig modules and composes root-only development work.

const std = @import("std");
const dev = @import("build/dev.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vt = b.addModule("howl_vt", .{
        .root_source_file = b.path("howl-vt/src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const text = b.addModule("howl_text", .{
        .root_source_file = b.path("howl-text/src/howl_text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    text.linkSystemLibrary("freetype", .{});
    text.linkSystemLibrary("harfbuzz", .{});
    const frame = b.addModule("howl_frame", .{
        .root_source_file = b.path("howl-frame/src/howl_frame.zig"),
        .target = target,
        .optimize = optimize,
    });
    frame.addImport("howl_vt", vt);
    const pty = b.addModule("howl_pty", .{
        .root_source_file = b.path("howl-pty/src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pty.addCMacro("_FORTIFY_SOURCE", "0");
    const control = b.addModule("howl_control", .{
        .root_source_file = b.path("howl-control/src/howl_control.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    control.addImport("howl_vt", vt);
    control.addImport("howl_frame", frame);
    control.addImport("howl_pty", pty);

    if (b.dep_prefix.len == 0) dev.add(b, target, optimize, vt, text, frame, pty, control);
}
