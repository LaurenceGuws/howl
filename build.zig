//! Composes every maintained Zig package's proofs and public consumer graph.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const check = b.step("check", "Compile every maintained Zig package and audit the workspace");
    const tests = b.step("test", "Run the complete maintained Zig test graph");
    // The manifest is the one child inventory. Missing child gates fail during
    // configuration; public modules/artifacts are forwarded from their owners.
    for (b.available_deps) |entry| {
        const name = entry[0];
        const child = if (std.mem.eql(u8, name, "howl_text"))
            b.dependency(name, .{ .target = target, .optimize = optimize, .bundled = false })
        else if (std.mem.eql(u8, name, "howl_render"))
            b.dependency(name, .{ .target = target, .optimize = optimize, .bundled_text = false })
        else
            b.dependency(name, .{ .target = target, .optimize = optimize });
        forward(b, name, child, check, tests);
    }

    const logger_tests = b.addTest(.{
        .name = "howl-json-logger",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/json_logger.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&logger_tests.step);
    tests.dependOn(&b.addRunArtifact(logger_tests).step);

    // A separate package must resolve this root exactly as an external embedder
    // does. This one nested invocation intentionally crosses that build boundary.
    const consumer = b.step("consumer", "Prove the root's external module and artifact contract");
    const consumer_test = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "test", "-j2" });
    consumer_test.setCwd(b.path("test/consumer"));
    consumer_test.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // Match the selected native target across the external package boundary.
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    const target_text = target.query.zigTriple(b.allocator) catch @panic("OOM");
    consumer_test.addArg(b.fmt("-Dtarget={s}", .{target_text}));
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    const cpu_text = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    if (cpu_text.len != 0) consumer_test.addArg(b.fmt("-Dcpu={s}", .{cpu_text}));
    consumer.dependOn(&consumer_test.step);
    check.dependOn(consumer);
    tests.dependOn(consumer);

    const audit = b.step("audit", "Audit accepted Zig source and Howl project invariants");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    const project_audit = b.addSystemCommand(&.{ "bash", "tools/audit_project.sh" });
    project_audit.setCwd(b.path("."));
    audit.dependOn(&project_audit.step);
    check.dependOn(audit);

    const protocol = b.step("protocol", "Validate the protocol catalogue");
    const protocol_command = b.addSystemCommand(&.{
        "nu",                                                             "--no-config-file", "-c",
        "source protocol_coverage.nu; protocol validate --fail | ignore",
    });
    protocol_command.setCwd(b.path("."));
    protocol.dependOn(&protocol_command.step);
    tests.dependOn(protocol);

    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    b.step("simulate", "Run VT simulations").dependOn(childStep(vt, "simulate"));
    b.step("fuzz:terminal", "Run VT fuzz proofs").dependOn(childStep(vt, "fuzz"));
    b.step("benchmark:vt", "Run the VT benchmark").dependOn(childStep(vt, "benchmark"));
    b.default_step = check;
}

fn childStep(child: *std.Build.Dependency, name: []const u8) *std.Build.Step {
    return &child.builder.top_level_steps.get(name).?.step;
}

fn forward(
    b: *std.Build,
    name: []const u8,
    child: *std.Build.Dependency,
    check: *std.Build.Step,
    tests: *std.Build.Step,
) void {
    check.dependOn(childStep(child, "check"));
    tests.dependOn(childStep(child, "test"));
    // Retain child entrypoints for targeted work without a second build process.
    for (child.builder.top_level_steps.keys(), child.builder.top_level_steps.values()) |step_name, step| {
        if (std.mem.eql(u8, step_name, "uninstall")) continue;
        b.step(b.fmt("{s}:{s}", .{ name, step_name }), step.description).dependOn(&step.step);
    }
    for (child.builder.modules.keys(), child.builder.modules.values()) |module_name, module| {
        std.debug.assert(!b.modules.contains(module_name));
        // zig-audit: acknowledge panic
        // reason: Build configuration cannot recover from allocation failure.
        b.modules.put(b.allocator, module_name, module) catch @panic("OOM");
    }
    for (child.builder.named_lazy_paths.keys(), child.builder.named_lazy_paths.values()) |path_name, path| {
        b.addNamedLazyPath(path_name, path);
    }
    for (child.builder.getInstallStep().dependencies.items) |step| {
        const install = step.cast(std.Build.Step.InstallArtifact) orelse continue;
        // Re-install under the parent prefix while preserving the exact artifact.
        const forwarded = b.addInstallArtifact(install.artifact, .{
            .dest_dir = if (install.dest_dir) |dir| .{ .override = dir } else .disabled,
            .dest_sub_path = install.dest_sub_path,
            .pdb_dir = if (install.pdb_dir) |dir| .{ .override = dir } else .disabled,
            .h_dir = if (install.h_dir) |dir| .{ .override = dir } else .disabled,
            .implib_dir = if (install.implib_dir) |dir| .{ .override = dir } else .disabled,
            .dylib_symlinks = install.dylib_symlinks,
        });
        b.getInstallStep().dependOn(&forwarded.step);
    }
}
