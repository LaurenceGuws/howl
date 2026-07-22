//! Curates independent Howl child projects for workspace development.

const std = @import("std");

const children = [_][]const u8{
    "howl-vt",
    "howl-text",
    "howl-frame",
    "howl-render",
    "howl-pty",
    "howl-control",
    "howl-window",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.option([]const u8, "target", "Forward the target triple to every child");
    const cpu = b.option([]const u8, "cpu", "Forward target CPU features to every child");

    const check = b.step("check", "Compile every independent child and workspace validation");
    const test_step = b.step("test", "Run every independent child's proofs");
    inline for (children) |child| {
        addChildBuild(b, check, child, "check", optimize, target, cpu, b.args);
        addChildBuild(b, test_step, child, "test", optimize, target, cpu, b.args);
    }
    const consumer = b.step("consumer:vt", "Run the isolated howl-vt package consumer");
    addChildBuild(b, consumer, "consumer-vt", "test", optimize, target, cpu, b.args);
    check.dependOn(consumer);
    test_step.dependOn(consumer);

    const audit = b.addSystemCommand(&.{ "bash", "tools/audit_source.sh" });
    audit.setName("workspace source audit");
    check.dependOn(&audit.step);
    const protocol = b.addSystemCommand(&.{
        "nu",
        "--no-config-file",
        "-c",
        "source protocol_coverage.nu; protocol validate --fail | ignore",
    });
    protocol.setName("protocol catalogue validation");
    check.dependOn(&protocol.step);

    const simulate = b.step("simulate", "Run VT simulations");
    addChildBuild(b, simulate, "howl-vt", "simulate", optimize, target, cpu, b.args);
    const fuzz = b.step("fuzz:terminal", "Run the VT fuzz proofs");
    addChildBuild(b, fuzz, "howl-vt", "fuzz", optimize, target, cpu, b.args);
    const benchmark = b.step("benchmark:m7", "Run the VT m7 benchmark");
    addChildBuild(b, benchmark, "howl-vt", "benchmark", optimize, target, cpu, b.args);
    const window = b.step("run:window", "Run the native Wayland window");
    addChildBuild(b, window, "howl-window", "run", optimize, target, cpu, b.args);
    const measure = b.step("measure:probe", "Measure the deterministic PTY-to-render pipeline");
    addChildBuild(b, measure, "howl-window", "measure", optimize, target, cpu, b.args);
    const disabled = b.step("measure:probe-disabled", "Measure the disabled probe boundary");
    addChildBuild(b, disabled, "howl-window", "measure-disabled", optimize, target, cpu, b.args);
    addWindowProbe(b, optimize, target, cpu);
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
    arguments: ?[]const []const u8,
) void {
    const command = b.addSystemCommand(&.{ b.graph.zig_exe, "build", step });
    command.setName(b.fmt("{s} {s}", .{ child, step }));
    command.setCwd(b.path(child));
    command.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    if (target) |value| command.addArg(b.fmt("-Dtarget={s}", .{value}));
    if (cpu) |value| command.addArg(b.fmt("-Dcpu={s}", .{value}));
    if (arguments) |values| {
        command.addArg("--");
        command.addArgs(values);
    }
    parent.dependOn(&command.step);
}

fn addWindowProbe(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: ?[]const u8,
    cpu: ?[]const u8,
) void {
    const step = b.step("run:window-probe", "Run the native window with temporary measurements");
    const command = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "run" });
    command.setName("howl-window run with probe");
    command.setCwd(b.path("howl-window"));
    command.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    command.addArg("-Dprobe=true");
    if (target) |value| command.addArg(b.fmt("-Dtarget={s}", .{value}));
    if (cpu) |value| command.addArg(b.fmt("-Dcpu={s}", .{value}));
    if (b.args) |values| {
        command.addArg("--");
        command.addArgs(values);
    }
    step.dependOn(&command.step);
}
