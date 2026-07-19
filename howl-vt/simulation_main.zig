const std = @import("std");
const protocol = @import("simulation/protocol.zig");
const scrollback = @import("simulation/scrollback.zig");

// Proof statement: this root runs deterministic VT-owned protocol and scrollback
// simulation workloads with replayable seeds; it is not a unit test.

const Simulation = enum {
    smoke,
    protocol,
    scrollback,
};

const EventMax = u32;

const CLIArgs = struct {
    simulation: Simulation,
    seed: ?u64 = null,
    events_max: ?EventMax = null,
};

fn argCount(argv: []const [:0]const u8) u16 {
    std.debug.assert(argv.len <= std.math.maxInt(u16));
    return @intCast(argv.len);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const argv = try init.minimal.args.toSlice(arena);

    const cli_args = try parseArgs(argv);

    switch (cli_args.simulation) {
        .smoke => try mainSmoke(gpa),
        .protocol => try mainProtocol(gpa, cli_args),
        .scrollback => try mainScrollback(gpa, cli_args),
    }
}

fn mainSmoke(gpa: std.mem.Allocator) !void {
    const seeds = [_]u64{
        0x1111111111111111,
        0x2222222222222222,
        0x3333333333333333,
    };

    for (seeds) |seed| {
        try scrollback.runCanonicalPreservation(gpa, seed, scrollback.defaultPreservationOptions(64));
    }
    try protocol.runSmoke(gpa);
}

fn mainProtocol(gpa: std.mem.Allocator, cli_args: CLIArgs) !void {
    const seed = cli_args.seed orelse 0x70726f746f636f6c;

    try protocol.runDeterminism(gpa, seed, protocol.defaultOptions(cli_args.events_max));
}

fn mainScrollback(gpa: std.mem.Allocator, cli_args: CLIArgs) !void {
    const seed = cli_args.seed orelse 0x7363726f6c6c6261;

    try scrollback.runCanonicalPreservation(gpa, seed, scrollback.defaultPreservationOptions(cli_args.events_max));
}

fn parseArgs(argv: []const [:0]const u8) !CLIArgs {
    var result = CLIArgs{ .simulation = .smoke };
    var positional: [2][]const u8 = undefined;
    var positional_len: u8 = 0;
    const argc = argCount(argv);

    var i: u16 = 1;
    while (i < argc) : (i += 1) {
        const arg = argv[@intCast(i)];
        if (std.mem.startsWith(u8, arg, "--events-max=")) {
            result.events_max = std.fmt.parseUnsigned(EventMax, arg["--events-max=".len..], 10) catch return error.InvalidEventsMax;
            continue;
        }
        if (std.mem.eql(u8, arg, "--events-max")) {
            i += 1;
            if (i >= argc) return error.MissingEventsMax;
            result.events_max = std.fmt.parseUnsigned(EventMax, argv[@intCast(i)], 10) catch return error.InvalidEventsMax;
            continue;
        }
        if (positional_len >= positional.len) return error.InvalidArguments;
        positional[@intCast(positional_len)] = arg;
        positional_len += 1;
    }

    if (positional_len == 0) return result;

    result.simulation = std.meta.stringToEnum(Simulation, positional[0]) orelse return error.UnknownSimulation;
    if (positional_len >= 2) {
        result.seed = try scrollback.parseSeed(positional[1]);
    }
    return result;
}
