//! Composes every maintained Zig package's proofs and public consumer graph.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const check = b.step("check", "Compile every maintained Zig package and audit the workspace");
    const tests = b.step("test", "Run the complete maintained Zig test graph");
    const audit = b.step("audit", "Audit every maintained Zig package and Howl project invariants");
    // The manifest is the one child inventory. Missing child gates fail during
    // configuration; public modules/artifacts are forwarded from their owners.
    for (b.available_deps) |entry| {
        const name = entry[0];
        // Match Instance's explicit text selection so standalone Render and
        // local composition expose one exact schema/renderer module identity.
        const child = if (std.mem.eql(u8, name, "howl_render"))
            b.dependency(name, .{ .target = target, .optimize = optimize, .bundled_text = false })
        else
            b.dependency(name, .{ .target = target, .optimize = optimize });
        const composition_leaf =
            std.mem.eql(u8, name, "howl_vt") or
            std.mem.eql(u8, name, "howl_pty") or
            std.mem.eql(u8, name, "howl_text") or
            std.mem.eql(u8, name, "howl_render");
        forward(b, name, child, check, tests, !composition_leaf);
        if (std.mem.eql(u8, name, "howl_render")) {
            std.debug.assert(child.module("howl_render_native") == b.modules.get("howl_render_native").?);
            // zig-audit: acknowledge panic
            // reason: Forward the child-owned optional module; graph allocation failure is unrecoverable.
            b.modules.put(b.allocator, "howl_render_owner_native", child.module("howl_render_owner_native")) catch @panic("OOM");
        }
        audit.dependOn(childStep(child, "audit"));
    }

    // Native bundled text must honor the same path/memory font contract.
    // Its proof-only module never replaces a published native module identity.
    const bundled_text = b.dependency("howl_text", .{
        .target = b.graph.host,
        .optimize = optimize,
        .bundled = true,
    });
    check.dependOn(childStep(bundled_text, "check"));
    tests.dependOn(childStep(bundled_text, "test"));

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

    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    const consumer_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    consumer_audit.setCwd(b.path("test/consumer"));
    audit.dependOn(&consumer_audit.step);
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
    // OSC 52 grammar is the only VT-owned observation-adjacent language shared
    // upward. Session encoding must not become a dependency of a local terminal.
    // zig-audit: acknowledge panic
    // reason: Build configuration cannot recover from allocation failure.
    b.modules.put(b.allocator, "vt_clipboard_grammar", vt.module("vt_clipboard_grammar")) catch @panic("OOM");
    // The optional standalone native contract is the exact VT-owned module.
    // zig-audit: acknowledge panic
    // reason: Build graph allocation failure is unrecoverable while forwarding the child-owned module.
    b.modules.put(b.allocator, "howl_vt_native", vt.module("howl_vt_native")) catch @panic("OOM");
    b.step("simulate", "Run VT simulations").dependOn(childStep(vt, "simulate"));
    b.step("fuzz:terminal", "Run VT fuzz proofs").dependOn(childStep(vt, "fuzz"));
    b.step("benchmark:vt", "Run the VT benchmark").dependOn(childStep(vt, "benchmark"));
    b.default_step = check;
}

fn sameInstallDirectory(left: ?std.Build.InstallDir, right: ?std.Build.InstallDir) bool {
    const a = left orelse return right == null;
    const b = right orelse return false;
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .prefix, .lib, .bin, .header => true,
        .custom => |path| std.mem.eql(u8, path, b.custom),
    };
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
    publish_modules: bool,
) void {
    check.dependOn(childStep(child, "check"));
    tests.dependOn(childStep(child, "test"));
    // Retain child entrypoints for targeted work without a second build process.
    for (child.builder.top_level_steps.keys(), child.builder.top_level_steps.values()) |step_name, step| {
        if (std.mem.eql(u8, step_name, "uninstall")) continue;
        b.step(b.fmt("{s}:{s}", .{ name, step_name }), step.description).dependOn(&step.step);
    }
    if (publish_modules) {
        for (child.builder.modules.keys(), child.builder.modules.values()) |module_name, module| {
            std.debug.assert(!b.modules.contains(module_name));
            // zig-audit: acknowledge panic
            // reason: Build configuration cannot recover from allocation failure.
            b.modules.put(b.allocator, module_name, module) catch @panic("OOM");
        }
    }
    for (child.builder.named_lazy_paths.keys(), child.builder.named_lazy_paths.values()) |path_name, path| {
        b.addNamedLazyPath(path_name, path);
    }
    for (child.builder.getInstallStep().dependencies.items) |step| {
        const install = step.cast(std.Build.Step.InstallArtifact) orelse continue;
        var duplicate = false;
        for (b.getInstallStep().dependencies.items) |published_step| {
            const published = published_step.cast(std.Build.Step.InstallArtifact) orelse continue;
            if (!std.mem.eql(u8, published.artifact.name, install.artifact.name)) continue;
            const same_sub_path = if (published.dest_sub_path) |path|
                if (install.dest_sub_path) |candidate| std.mem.eql(u8, path, candidate) else false
            else
                install.dest_sub_path == null;
            // Shared child companions may arrive through several packages, but
            // one public name must still denote one exact artifact and install.
            if (published.artifact != install.artifact or
                !sameInstallDirectory(published.dest_dir, install.dest_dir) or
                !same_sub_path or
                !sameInstallDirectory(published.pdb_dir, install.pdb_dir) or
                !sameInstallDirectory(published.h_dir, install.h_dir) or
                !sameInstallDirectory(published.implib_dir, install.implib_dir) or
                published.dylib_symlinks != install.dylib_symlinks)
            {
                // zig-audit: acknowledge panic
                // reason: A public artifact name cannot select conflicting child objects or installation contracts.
                @panic("conflicting public artifact");
            }
            duplicate = true;
            break;
        }
        if (duplicate) continue;
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
