// Workspace root is orchestration and audit only.
// Keep package ownership and ABI seams intact by aggregating package-local build steps,
// not by introducing root-level Zig imports across package boundaries.

const std = @import("std");

const Build = std.Build;

const RootAggregate = struct {
    name: []const u8,
    description: []const u8,
    mappings: []const Mapping,
};

const Mapping = struct {
    package_dir: []const u8,
    step_name: []const u8,
};

const check_mappings = [_]Mapping{
    .{ .package_dir = "howl-pty", .step_name = "check" },
    .{ .package_dir = "howl-vt", .step_name = "check" },
    .{ .package_dir = "howl-render", .step_name = "check" },
    .{ .package_dir = "howl-linux-host", .step_name = "check" },
};

const test_mappings = [_]Mapping{
    .{ .package_dir = "howl-pty", .step_name = "test" },
    .{ .package_dir = "howl-vt", .step_name = "test" },
    .{ .package_dir = "howl-render", .step_name = "test" },
    .{ .package_dir = "howl-linux-host", .step_name = "test" },
};

const test_unit_mappings = [_]Mapping{
    .{ .package_dir = "howl-pty", .step_name = "test:unit" },
    .{ .package_dir = "howl-vt", .step_name = "test:unit" },
    .{ .package_dir = "howl-render", .step_name = "test:unit" },
    .{ .package_dir = "howl-linux-host", .step_name = "test:unit" },
};

const test_abi_mappings = [_]Mapping{
    .{ .package_dir = "howl-pty", .step_name = "test:abi" },
    .{ .package_dir = "howl-vt", .step_name = "test:abi" },
    .{ .package_dir = "howl-render", .step_name = "test:abi" },
};

const test_integration_mappings = [_]Mapping{
    .{ .package_dir = "howl-pty", .step_name = "test:integration" },
    .{ .package_dir = "howl-linux-host", .step_name = "test:integration" },
};

const simulate_mappings = [_]Mapping{
    .{ .package_dir = "howl-vt", .step_name = "simulate" },
};

const benchmark_mappings = [_]Mapping{
    .{ .package_dir = "howl-vt", .step_name = "benchmark:m7_baseline" },
    .{ .package_dir = "howl-render", .step_name = "benchmark:render" },
};

const root_aggregates = [_]RootAggregate{
    .{ .name = "check", .description = "Build normalized package check steps across the workspace", .mappings = &check_mappings },
    .{ .name = "test", .description = "Run canonical package test aggregates across the workspace", .mappings = &test_mappings },
    .{ .name = "test:unit", .description = "Run package unit proofs across the workspace", .mappings = &test_unit_mappings },
    .{ .name = "test:abi", .description = "Run product-package ABI proofs across the workspace", .mappings = &test_abi_mappings },
    .{ .name = "test:integration", .description = "Run explicit package integration proofs across the workspace", .mappings = &test_integration_mappings },
    .{ .name = "simulate", .description = "Run deterministic package simulation workloads across the workspace", .mappings = &simulate_mappings },
    .{ .name = "benchmark", .description = "Run currently exposed named package benchmarks across the workspace", .mappings = &benchmark_mappings },
};

pub fn build(b: *Build) void {
    inline for (root_aggregates) |aggregate| {
        const step = b.step(aggregate.name, aggregate.description);
        for (aggregate.mappings) |mapping| {
            step.dependOn(&addPackageStep(b, mapping.package_dir, mapping.step_name).step);
        }

        if (std.mem.eql(u8, aggregate.name, "check")) {
            b.default_step = step;
        }
    }
}

fn addPackageStep(b: *Build, package_dir: []const u8, step_name: []const u8) *Build.Step.Run {
    const cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build", step_name });
    cmd.setCwd(b.path(package_dir));
    return cmd;
}
