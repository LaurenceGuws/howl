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

    if (b.dep_prefix.len == 0) dev.add(b, target, optimize, vt, text);
}
