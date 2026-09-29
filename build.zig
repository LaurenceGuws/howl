//! Curates the tracked Howl core modules and their owner-local proofs.

const std = @import("std");
const howl_text_build = @import("howl-text/build.zig");

const children = [_][]const u8{
    "howl-vt",
    "howl-instance",
    "howl-pty",
    "howl-text",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const text_module = howl_text_build.addModule(
        b,
        b.path("howl-text"),
        target,
        optimize,
        false,
    );
    std.debug.assert(b.modules.get("howl_text") == text_module);

    const check = b.step("check", "Compile the Howl core and run source audit");
    const test_step = b.step("test", "Run every Howl core proof");

    inline for (children) |child| {
        addChildBuild(b, check, child, "check", optimize, target, false);
        addChildBuild(b, test_step, child, "test", optimize, target, true);
    }

    const logger_module = b.createModule(.{
        .root_source_file = b.path("tools/json_logger.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });
    const logger_tests = b.addTest(.{
        .name = "howl-json-logger",
        .root_module = logger_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&logger_tests.step);
    test_step.dependOn(&b.addRunArtifact(logger_tests).step);

    const audit = b.step("audit", "Audit maintained Zig source");
    const audit_command = b.addSystemCommand(&.{ "bash", "tools/audit_source.sh" });
    audit_command.setName("workspace source audit");
    audit.dependOn(&audit_command.step);
    check.dependOn(audit);

    const protocol = b.step("protocol", "Validate the protocol catalogue");
    const protocol_command = b.addSystemCommand(&.{
        "nu",
        "--no-config-file",
        "-c",
        "source protocol_coverage.nu; protocol validate --fail | ignore",
    });
    protocol_command.setName("protocol catalogue validation");
    protocol.dependOn(&protocol_command.step);

    const simulate = b.step("simulate", "Run VT simulations");
    addChildBuild(b, simulate, "howl-vt", "simulate", optimize, target, true);
    const fuzz = b.step("fuzz:terminal", "Run VT fuzz proofs");
    addChildBuild(b, fuzz, "howl-vt", "fuzz", optimize, target, true);
    const benchmark = b.step("benchmark:m7", "Run the VT m7 benchmark");
    addChildBuild(b, benchmark, "howl-vt", "benchmark", optimize, target, true);
    b.default_step = check;
}

fn addChildBuild(
    b: *std.Build,
    parent: *std.Build.Step,
    child: []const u8,
    step: []const u8,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    passthru: bool,
) void {
    const command = b.addSystemCommand(&.{ b.graph.zig_exe, "build", step });
    command.setName(b.fmt("{s} {s}", .{ child, step }));
    command.setCwd(b.path(child));
    command.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));

    const target_text = target.query.zigTriple(b.allocator) catch @panic("OOM");
    command.addArg(b.fmt("-Dtarget={s}", .{target_text}));

    const cpu_text = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    if (cpu_text.len != 0) {
        command.addArg(b.fmt("-Dcpu={s}", .{cpu_text}));
    }

    if (passthru) {
        command.addArg("--");
        command.addPassthruArgs();
    }
    parent.dependOn(&command.step);
}
