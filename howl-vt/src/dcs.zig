//! Decodes complete DCS payloads into terminal semantic events.

const parsed_events = @import("parser/events.zig");

fn requestStatusPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '$' and data[1] == 'q') return data[2..];
    return null;
}

fn requestTermcapPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'q') return data[2..];
    return null;
}

fn requestResourcePayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'Q') return data[2..];
    return null;
}

const events = @import("semantic_event.zig");
const std = @import("std");
const SemanticEvent = events.SemanticEvent;
const DcsEvent = @FieldType(parsed_events.Event, "dcs");

/// Decodes one completed borrowed DCS payload; unsupported commands return null.
pub fn process(dcs: DcsEvent) ?SemanticEvent {
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 'q') return SemanticEvent{ .dcs_request_status = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'q') return SemanticEvent{ .dcs_request_termcap = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'Q') return SemanticEvent{ .dcs_request_resource = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'p') return SemanticEvent{ .dcs_payload = .{ .kind = .xtsettcap, .payload = dcs.payload } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 't') return SemanticEvent{ .dcs_payload = .{ .kind = .decrsps, .payload = dcs.body } };
    if (dcs.final == '|') return SemanticEvent{ .dcs_payload = .{ .kind = .decudk, .payload = dcs.body } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '!' and dcs.final == 'u') return SemanticEvent{ .dcs_payload = .{ .kind = .decaupss, .payload = dcs.body } };
    return null;
}

const TestIntermediate = enum {
    dollar,
    plus,
    bang,
};

fn dcsEvent(
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediate: ?TestIntermediate,
) DcsEvent {
    const intermediates: []const u8 = if (intermediate) |value|
        switch (value) {
            .dollar => "$",
            .plus => "+",
            .bang => "!",
        }
    else
        "";
    return .{
        .body = body,
        .payload = payload,
        .final = final,
        .params = params,
        .param_count = param_count,
        .intermediates = intermediates,
        .intermediates_len = @intCast(intermediates.len),
    };
}

test "dcs request payloads map to semantic events" {
    const empty = [_]i32{0} ** 24;
    const status = process(dcsEvent("$q q", " q", 'q', empty[0..], 0, .dollar)).?;
    try std.testing.expectEqualStrings(" q", status.dcs_request_status);

    const termcap = process(dcsEvent("+q436F", "436F", 'q', empty[0..], 0, .plus)).?;
    try std.testing.expectEqualStrings("436F", termcap.dcs_request_termcap);

    const resource = process(dcsEvent(
        "+Q6E616D65",
        "6E616D65",
        'Q',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expectEqualStrings("6E616D65", resource.dcs_request_resource);
}

test "dcs legacy payload protocols classify host-neutral payloads" {
    const empty = [_]i32{0} ** 24;

    const termcap = process(dcsEvent(
        "+p436F=7661",
        "436F=7661",
        'p',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expect(termcap.dcs_payload.kind == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", termcap.dcs_payload.payload);

    try std.testing.expect(process(dcsEvent(
        "1$tstate",
        "state",
        't',
        empty[0..],
        0,
        .dollar,
    )).?.dcs_payload.kind == .decrsps);
    try std.testing.expect(process(dcsEvent(
        "0;1|keys",
        "keys",
        '|',
        empty[0..],
        0,
        null,
    )).?.dcs_payload.kind == .decudk);
    try std.testing.expect(process(dcsEvent(
        "0!uA",
        "A",
        'u',
        empty[0..],
        0,
        .bang,
    )).?.dcs_payload.kind == .decaupss);
}
