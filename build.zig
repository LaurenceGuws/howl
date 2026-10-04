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
    @import("local_build.zig").addModules(b, target, optimize, text_module);

    const check = b.step("check", "Compile the Howl core and run required audits");
    const test_step = b.step("test", "Run every Howl core proof");
    const embedding_module = b.createModule(.{
        .root_source_file = b.path("howl-render/test/local_embedding.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    embedding_module.addImport("howl_instance", b.modules.get("howl_instance").?);
    embedding_module.addImport("howl_vt", b.modules.get("howl_vt").?);
    embedding_module.addImport("howl_render", b.modules.get("howl_render").?);
    const fonts = b.addOptions();
    // zig-audit: acknowledge panic
    // reason: Build graph construction has no recoverable allocator failure.
    fonts.addOption([]const u8, "primary_font", b.root.joinString(b.allocator, "howl-text/testdata/primary.ttf") catch @panic("OOM"));
    embedding_module.addOptions("test_fonts", fonts);
    const embedding = b.addTest(.{
        .name = "howl-local-embedding",
        .root_module = embedding_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&embedding.step);
    test_step.dependOn(&b.addRunArtifact(embedding).step);

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

    const audit = b.step("audit", "Audit accepted Zig source and Howl project invariants");
    const zig_audit_command = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit_command.setName("zig-audit accepted core");
    zig_audit_command.setCwd(b.path("."));
    audit.dependOn(&zig_audit_command.step);

    const project_audit_command = b.addSystemCommand(&.{ "bash", "tools/audit_project.sh" });
    project_audit_command.setName("Howl project audit");
    audit.dependOn(&project_audit_command.step);
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

    // zig-audit: acknowledge panic
    // reason: Build graph construction has no recoverable allocator/configuration path here; aborting preserves the build-owner contract.
    const target_text = target.query.zigTriple(b.allocator) catch @panic("OOM");
    command.addArg(b.fmt("-Dtarget={s}", .{target_text}));

    // zig-audit: acknowledge panic
    // reason: Build graph construction has no recoverable allocator/configuration path here; aborting preserves the build-owner contract.
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
