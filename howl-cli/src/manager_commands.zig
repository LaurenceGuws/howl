//! Professional operator surface over the authoritative HWLM manager.

const std = @import("std");
const client = @import("howl_client");
const owner = @import("howl_server");
const failure = @import("failure.zig");

pub const Error = client.server.Error || error{
    InvalidArguments,
    ManagerRejected,
    SessionNotFound,
    StaleIdentity,
};

pub fn serverCommand(
    init: std.process.Init,
    args: []const [*:0]const u8,
    context: *failure.Context,
) !void {
    if (args.len == 0) return error.InvalidArguments;
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "run")) {
        context.reset("server.run");
        switch (try owner.run(init, args)) {
            .shutdown => return,
        }
    }
    if (std.mem.eql(u8, verb, "status")) {
        context.reset("server.status");
        if (args.len < 2 or args.len > 3) return error.InvalidArguments;
        const text = args.len == 3 and std.mem.eql(u8, std.mem.span(args[2]), "--text");
        if (args.len == 3 and !text) return error.InvalidArguments;
        var connection = try connect(init, std.mem.span(args[1]), context);
        defer connection.deinit();
        const status = try connection.status();
        if (text) try emitStatusText(init, status) else try emitStatusJson(init, status);
        return;
    }
    if (std.mem.eql(u8, verb, "shutdown")) {
        context.reset("server.shutdown");
        if (args.len != 2) return error.InvalidArguments;
        var connection = try connect(init, std.mem.span(args[1]), context);
        defer connection.deinit();
        const result = try connection.shutdown();
        try requireOk(context, result);
        try emitAction(init, "server.shutdown", result.session_id, result.roster_revision, null);
        return;
    }
    return error.InvalidArguments;
}

pub fn sessionCommand(
    init: std.process.Init,
    args: []const [*:0]const u8,
    context: *failure.Context,
) !void {
    if (args.len == 0) return error.InvalidArguments;
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "list")) context.reset("session.list") else if (std.mem.eql(u8, verb, "show")) context.reset("session.show") else if (std.mem.eql(u8, verb, "create")) context.reset("session.create") else if (std.mem.eql(u8, verb, "close")) context.reset("session.close");
    if (args.len < 2) return error.InvalidArguments;
    const endpoint = std.mem.span(args[1]);
    if (std.mem.eql(u8, verb, "list")) {
        context.reset("session.list");
        const text = args.len == 3 and std.mem.eql(u8, std.mem.span(args[2]), "--text");
        if (args.len > 3 or (args.len == 3 and !text)) return error.InvalidArguments;
        var connection = try connect(init, endpoint, context);
        defer connection.deinit();
        var roster = try connection.observeRoster(0);
        defer roster.deinit();
        if (text) try emitRosterText(init, &roster) else try emitRosterJson(init, &roster);
        return;
    }
    if (std.mem.eql(u8, verb, "show")) {
        context.reset("session.show");
        if (args.len < 3 or args.len > 4) return error.InvalidArguments;
        const text = args.len == 4 and std.mem.eql(u8, std.mem.span(args[3]), "--text");
        if (args.len == 4 and !text) return error.InvalidArguments;
        var connection = try connect(init, endpoint, context);
        defer connection.deinit();
        var roster = try connection.observeRoster(0);
        defer roster.deinit();
        const record = roster.findName(std.mem.span(args[2])) orelse {
            context.code_override = "not_found";
            return error.SessionNotFound;
        };
        if (text) try emitRecordText(init, record) else try emitRecordJsonEnvelope(init, roster.header, record);
        return;
    }
    if (std.mem.eql(u8, verb, "create")) {
        context.reset("session.create");
        if (args.len < 3) return error.InvalidArguments;
        const request = try parseCreate(args[2..]);
        var connection = try connect(init, endpoint, context);
        defer connection.deinit();
        const result = try connection.create(request);
        try requireOk(context, result);
        try emitAction(init, "session.create", result.session_id, result.roster_revision, request.name);
        return;
    }
    if (std.mem.eql(u8, verb, "close")) {
        context.reset("session.close");
        if (args.len < 3 or args.len > 5) return error.InvalidArguments;
        const name = std.mem.span(args[2]);
        var expected_id: ?u64 = null;
        if (args.len != 3) {
            if (args.len != 5 or !std.mem.eql(u8, std.mem.span(args[3]), "--expect-id"))
                return error.InvalidArguments;
            expected_id = std.fmt.parseInt(u64, std.mem.span(args[4]), 10) catch return error.InvalidArguments;
            if (expected_id.? == 0) return error.InvalidArguments;
        }
        var connection = try connect(init, endpoint, context);
        defer connection.deinit();
        var roster = try connection.observeRoster(0);
        defer roster.deinit();
        const record = roster.findName(name) orelse {
            context.code_override = "not_found";
            return error.SessionNotFound;
        };
        if (expected_id) |wanted| {
            if (wanted != record.session_id) {
                context.code_override = "stale_identity";
                return error.StaleIdentity;
            }
        }
        const result = try connection.close(record.session_id);
        try requireOk(context, result);
        try emitAction(init, "session.close", record.session_id, result.roster_revision, record.name);
        return;
    }
    return error.InvalidArguments;
}

fn connect(
    init: std.process.Init,
    endpoint: []const u8,
    context: *failure.Context,
) !client.server.Connection {
    var diagnostic: client.server.ConnectDiagnostic = .{};
    return client.server.Connection.connectNative(init.gpa, init.io, endpoint, &diagnostic) catch |problem| {
        context.captureConnect(&diagnostic);
        return problem;
    };
}

fn requireOk(context: *failure.Context, result: client.server.Result) !void {
    if (result.code == .ok) return;
    context.managerCode(result.code);
    return error.ManagerRejected;
}

fn parseCreate(args: []const [*:0]const u8) Error!client.server.Create {
    if (args.len == 0) return error.InvalidArguments;
    var result = client.server.Create{ .name = std.mem.span(args[0]) };
    var rows_seen = false;
    var columns_seen = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = std.mem.span(args[index]);
        if (std.mem.eql(u8, arg, "--shell")) {
            index += 1;
            if (index == args.len or result.shell != null) return error.InvalidArguments;
            result.shell = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--command")) {
            index += 1;
            if (index == args.len or result.command != null) return error.InvalidArguments;
            result.command = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--cwd")) {
            index += 1;
            if (index == args.len or result.cwd != null) return error.InvalidArguments;
            result.cwd = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--rows")) {
            index += 1;
            if (index == args.len or rows_seen) return error.InvalidArguments;
            result.rows = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch return error.InvalidArguments;
            if (result.rows == 0) return error.InvalidArguments;
            rows_seen = true;
        } else if (std.mem.eql(u8, arg, "--columns")) {
            index += 1;
            if (index == args.len or columns_seen) return error.InvalidArguments;
            result.columns = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch return error.InvalidArguments;
            if (result.columns == 0) return error.InvalidArguments;
            columns_seen = true;
        } else return error.InvalidArguments;
    }
    if (rows_seen != columns_seen) return error.InvalidArguments;
    return result;
}

fn emitStatusJson(init: std.process.Init, value: client.server.ServerStatus) !void {
    var buffer: [2048]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.writeAll("{\"schema\":\"howl.server.status/v1\",\"server_id\":");
    try writeHexId(writer, value.server_id);
    try writer.writeAll(",\"roster_revision\":");
    try writeDecimalId(writer, value.roster_revision);
    try writer.print(",\"pid\":{d},\"sessions\":{d},\"capacity\":{d},\"stopping\":{s}}}\n", .{
        value.pid,
        value.session_count,
        value.capacity,
        if (value.stopping) "true" else "false",
    });
    try writer.flush();
}

fn emitStatusText(init: std.process.Init, value: client.server.ServerStatus) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.print(
        "server={x} pid={d} sessions={d}/{d} revision={d} state={s}\n",
        .{ value.server_id, value.pid, value.session_count, value.capacity, value.roster_revision, if (value.stopping) "stopping" else "running" },
    );
    try stdout.interface.flush();
}

fn emitRosterJson(init: std.process.Init, roster: *const client.server.Roster) !void {
    var buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.writeAll("{\"schema\":\"howl.server.sessions/v1\",\"server_id\":");
    try writeHexId(writer, roster.header.server_id);
    try writer.writeAll(",\"roster_revision\":");
    try writeDecimalId(writer, roster.header.roster_revision);
    try writer.print(",\"capacity\":{d},\"stopping\":{s},\"sessions\":[", .{
        roster.header.capacity,
        if (roster.header.stopping) "true" else "false",
    });
    for (roster.items(), 0..) |record, index| {
        if (index != 0) try writer.writeByte(',');
        try emitRecordObject(writer, record);
    }
    try writer.writeAll("]}\n");
    try writer.flush();
}

fn emitRosterText(init: std.process.Init, roster: *const client.server.Roster) !void {
    var buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    for (roster.items()) |record| {
        try writer.print("{d}\t{s}\t{s}", .{ record.session_id, @tagName(record.state), record.name });
        if (record.failure.len != 0) try writer.print("\t{s}", .{record.failure});
        try writer.writeByte('\n');
    }
    try writer.flush();
}

fn emitRecordJsonEnvelope(
    init: std.process.Init,
    header: client.server.RosterHeader,
    record: client.server.SessionRecord,
) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.writeAll("{\"schema\":\"howl.server.session/v1\",\"server_id\":");
    try writeHexId(writer, header.server_id);
    try writer.writeAll(",\"roster_revision\":");
    try writeDecimalId(writer, header.roster_revision);
    try writer.writeAll(",\"session\":");
    try emitRecordObject(writer, record);
    try writer.writeAll("}\n");
    try writer.flush();
}

fn emitRecordText(init: std.process.Init, record: client.server.SessionRecord) !void {
    var buffer: [2048]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.print("id={d} name={s} state={s} created={d}", .{
        record.session_id,
        record.name,
        @tagName(record.state),
        record.created_sequence,
    });
    if (record.failure.len != 0) try stdout.interface.print(" failure={s}", .{record.failure});
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

fn emitRecordObject(writer: *std.Io.Writer, record: client.server.SessionRecord) !void {
    try writer.writeAll("{\"session_id\":");
    try writeDecimalId(writer, record.session_id);
    try writer.writeAll(",\"created_sequence\":");
    try writeDecimalId(writer, record.created_sequence);
    try writer.writeAll(",\"state\":");
    try std.json.Stringify.value(@tagName(record.state), .{}, writer);
    try writer.writeAll(",\"name\":");
    try std.json.Stringify.value(record.name, .{}, writer);
    if (record.failure.len != 0) {
        try writer.writeAll(",\"failure\":");
        try std.json.Stringify.value(record.failure, .{}, writer);
    }
    try writer.writeByte('}');
}

fn emitAction(
    init: std.process.Init,
    operation: []const u8,
    session_id: u64,
    roster_revision: u64,
    name: ?[]const u8,
) !void {
    var buffer: [2048]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.writeAll("{\"schema\":\"howl.server.action/v1\",\"operation\":");
    try std.json.Stringify.value(operation, .{}, writer);
    if (session_id != 0) {
        try writer.writeAll(",\"session_id\":");
        try writeDecimalId(writer, session_id);
    }
    if (name) |value| {
        try writer.writeAll(",\"name\":");
        try std.json.Stringify.value(value, .{}, writer);
    }
    try writer.writeAll(",\"roster_revision\":");
    try writeDecimalId(writer, roster_revision);
    try writer.writeAll("}\n");
    try writer.flush();
}

fn writeHexId(writer: *std.Io.Writer, value: u64) !void {
    try writer.print("\"{x}\"", .{value});
}

fn writeDecimalId(writer: *std.Io.Writer, value: u64) !void {
    try writer.print("\"{d}\"", .{value});
}

test "create parser requires coherent geometry and rejects duplicate options" {
    const valid = [_][*:0]const u8{ "work", "--rows", "30", "--columns", "100", "--shell", "/bin/bash" };
    const parsed = try parseCreate(&valid);
    try std.testing.expectEqualStrings("work", parsed.name);
    try std.testing.expectEqual(@as(u16, 30), parsed.rows);
    try std.testing.expectEqual(@as(u16, 100), parsed.columns);
    const partial = [_][*:0]const u8{ "work", "--rows", "30" };
    try std.testing.expectError(error.InvalidArguments, parseCreate(&partial));
    const duplicate = [_][*:0]const u8{ "work", "--shell", "/bin/sh", "--shell", "/bin/bash" };
    try std.testing.expectError(error.InvalidArguments, parseCreate(&duplicate));
}
