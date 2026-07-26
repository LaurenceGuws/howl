//! Curates independent Howl child projects for workspace development.

const std = @import("std");

const children = [_][]const u8{
    "howl-vt",
    "howl-pty",
    "howl-render",
    "howl-host",
    "howl-vk",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.option([]const u8, "target", "Forward the target triple to every child");
    const cpu = b.option([]const u8, "cpu", "Forward target CPU features to every child");

    const check = b.step("check", "Compile every surviving child and validate root evidence");
    const test_step = b.step("test", "Run every surviving child's proofs");
    inline for (children) |child| {
        addChildBuild(b, check, child, "check", optimize, target, cpu, false);
        addChildBuild(b, test_step, child, "test", optimize, target, cpu, true);
    }

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
    check.dependOn(protocol);

    const simulate = b.step("simulate", "Run VT simulations");
    addChildBuild(b, simulate, "howl-vt", "simulate", optimize, target, cpu, true);
    const fuzz = b.step("fuzz:terminal", "Run VT fuzz proofs");
    addChildBuild(b, fuzz, "howl-vt", "fuzz", optimize, target, cpu, true);
    const benchmark = b.step("benchmark:m7", "Run the VT m7 benchmark");
    addChildBuild(b, benchmark, "howl-vt", "benchmark", optimize, target, cpu, true);
    const host = b.step("run:host", "Run the first-party Wayland host");
    addChildBuild(b, host, "howl-host", "run", optimize, target, cpu, true);
    b.default_step = check;
}

fn addChildBuild(
    b: *std.Build,
    parent: *std.Build.Step,
    child: []const u8,
    step: []const u8,
    optimize: std.builtin.OptimizeMode,
    target: ?[]const u8,
    cpu: ?[]const u8,
    passthru: bool,
) void {
    const command = b.addSystemCommand(&.{ b.graph.zig_exe, "build", step });
    command.setName(b.fmt("{s} {s}", .{ child, step }));
    command.setCwd(b.path(child));
    command.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    if (target) |value| command.addArg(b.fmt("-Dtarget={s}", .{value}));
    if (cpu) |value| command.addArg(b.fmt("-Dcpu={s}", .{value}));
    if (passthru) {
        command.addArg("--");
        command.addPassthruArgs();
    }
    parent.dependOn(&command.step);
}
