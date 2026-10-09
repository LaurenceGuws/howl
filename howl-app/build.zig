const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const headers = b.addWriteFiles();
    const header = headers.add("desktop.h",
        \\#include <SDL3/SDL.h>
        \\#include <SDL3_ttf/SDL_ttf.h>
        \\#include <fontconfig/fontconfig.h>
        \\#include <sys/eventfd.h>
        \\#include <poll.h>
        \\#include <unistd.h>
        \\#include <errno.h>
        \\#include <sys/socket.h>
        \\#include <netinet/in.h>
    );
    const translation = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize });
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const server = b.dependency("server_client", .{ .target = target, .optimize = optimize });
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("desktop", translation.createModule());
    root.addImport("howl_instance", instance.module("howl_instance"));
    root.addImport("howl_client", client.module("howl_client"));
    root.addImport("howl_client_render", client.module("howl_client_render"));
    root.addImport("server_client", server.module("server_client"));
    root.addImport("test_instance_service", instance.module("howl_instance_service"));
    root.addImport("test_fonts", instance.module("howl_text_test_fonts"));
    root.linkSystemLibrary("SDL3", .{});
    root.linkSystemLibrary("SDL3_ttf", .{});
    root.linkSystemLibrary("fontconfig", .{});
    const app = b.addExecutable(.{ .name = "howl-app", .root_module = root, .use_llvm = false, .use_lld = false });
    b.installArtifact(app);
    const tests = b.addTest(.{ .name = "howl-app", .root_module = root, .use_llvm = false, .use_lld = false });
    const check = b.step("check", "Compile the direct Zig SDL app and its proofs");
    check.dependOn(&app.step);
    check.dependOn(&tests.step);
    const audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    audit.setCwd(b.path("."));
    check.dependOn(&audit.step);
    b.step("test", "Run application ownership and behavior proofs").dependOn(&b.addRunArtifact(tests).step);
    const run = b.addRunArtifact(app);
    run.addPassthruArgs();
    b.step("run", "Run howl-app").dependOn(&run.step);
    b.default_step = check;
}
