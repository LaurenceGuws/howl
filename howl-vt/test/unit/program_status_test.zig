//! Public, allocation-free OSC 7501 grammar acceptance tests, no host UI.
const std = @import("std");
const status = @import("../../src/program_status.zig");

test "OSC 7501 query and process-exited do not invent host status" {
    try std.testing.expect(status.parse("?").? == .query);
    try std.testing.expect(status.parse("process-exited") == null);
    try std.testing.expect(status.parse("") == null);
    try std.testing.expect(status.parse("??") == null);
    try std.testing.expect(status.parse("state=unknown") == null);
}

test "OSC 7501 parses status, blocked kind, progress and verified encoded text" {
    const input = "state=blocked:id=tf/plan:kind=permission:progress=42:" ++
        "app=terraform:title=UGxhbg==:msg=QXBwbHk=";
    const parsed = status.parse(input).?.report;
    try std.testing.expect(parsed.state == .blocked);
    try std.testing.expectEqualStrings("tf/plan", parsed.id);
    try std.testing.expect(parsed.kind.? == .permission);
    try std.testing.expectEqual(@as(?u8, 42), parsed.progress);
    try std.testing.expectEqualStrings("terraform", parsed.app);
    var out: [status.max_msg_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("Plan", parsed.titleText(&out).?);
    try std.testing.expectEqualStrings("Apply", parsed.messageText(&out).?);

    const last = status.parse("state=idle:state=working:progress=80:progress=000:kind=auth").?.report;
    try std.testing.expect(last.state == .working);
    try std.testing.expectEqual(@as(?u8, 0), last.progress);
    try std.testing.expectEqual(@as(?status.Kind, null), last.kind);
    try std.testing.expectEqualStrings("", last.id);
    const done = status.parse("state=done:progress=70:kind=question").?.report;
    try std.testing.expect(done.progress == null and done.kind == null);
    const unsupported_progress = status.parse("state=working:progress=101:app=-bad").?.report;
    try std.testing.expect(unsupported_progress.progress == null);
    try std.testing.expectEqualStrings("-bad", unsupported_progress.app);
}

test "OSC 7501 clear scopes and malformed identities cannot become root clear" {
    try std.testing.expectEqualStrings("", status.parse("state=clear").?.clear);
    try std.testing.expectEqualStrings("tf/plan", status.parse("state=clear:id=tf/plan").?.clear);
    for ([_][]const u8{
        "state=clear:id=/root",               "state=working:id=foo//bar",                                     "state=clear:id=foo/",
        "state=clear:id=some%bad",            "state=clear:id=has space",                                      "state=clear:id=valid:id=bad//other",
        "state=clear:id=bad//first:id=valid", "state=clear:id=good/id/with/too/many/segments/for/a/single/id",
    }) |invalid| try std.testing.expect(status.parse(invalid) == null);
    try std.testing.expectEqualStrings("root/01", status.parse("state=clear:id=root/01").?.clear);
    try std.testing.expect(status.parse("state=clear:id=root/01:title=AA==") == null);
    try std.testing.expect(status.parse("state=clear:id=root/01:msg=////") == null);
}

test "OSC 7501 source field and UTF-8 bounds reject hostile reports atomically" {
    for ([_][]const u8{
        "state=working:msg=AA==",                              "state=working:msg=////",
        "state=working:title=SGVsbG8A",                        "state=working:msg=woA",
        "state=working:keynameover16bytes=ok",                 "state=working:id=bad:id=bad//2:id=good",
        "state=working:app=abcdefghijklmnopqrstuvwxyz1234567",
    }) |invalid| {
        try std.testing.expect(status.parse(invalid) == null);
    }
    const max_input: [status.max_body_bytes]u8 = @splat('x');
    try std.testing.expect(status.parse(&max_input) == null);
    const too_long: [status.max_body_bytes + 1]u8 = @splat('x');
    try std.testing.expect(status.parse(&too_long) == null);
    // Unknown or syntactically malformed *optional* values do not discard
    // the whole status. Only invalid IDs, state and text decoding do.
    try std.testing.expectEqualStrings("", status.parse("state=working:title=%").?.report.title);
    const good = status.parse("state=done:title=UGxhbg:msg=QXBwbHk").?.report;
    var out: [status.max_msg_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("Plan", good.titleText(&out).?);
    try std.testing.expectEqualStrings("Apply", good.messageText(&out).?);
}

test "OSC 7501 only recognized states and numeric range are returned" {
    const states = [_][]const u8{ "idle", "working", "done", "blocked", "error" };
    for (states) |state_text| {
        var buf: [64]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf, "state={s}", .{state_text});
        try std.testing.expect(status.parse(body) != null);
    }
    try std.testing.expect(status.parse("state=clear").? == .clear);
    for ([_][]const u8{ "state=Clear", "state=finished", "state=", "progress=40" }) |invalid|
        try std.testing.expect(status.parse(invalid) == null);
    try std.testing.expect(status.parse("state=blocked:kind=question").?.report.kind.? == .question);
    try std.testing.expect(status.parse("state=blocked:kind=auth").?.report.kind.? == .auth);
    try std.testing.expect(status.parse("state=blocked:kind=other").?.report.kind == null);
}

test "Rex validates earlier duplicate text before last value wins" {
    for ([_][]const u8{
        "state=working:title=AA==:title=QQ==",
        "state=working:msg=////:msg=QQ==",
        "state=clear:msg=A:msg=QQ==",
        "state=working:title=woA:title=QQ==",
        "state=working:msg=AA==:msg=",
    }) |body| try std.testing.expect(status.parse(body) == null);

    const report = status.parse("state=working:title=QQ==:title=Qg:msg=QQ:msg=Qw==").?.report;
    var scratch: [status.max_msg_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("B", report.titleText(&scratch).?);
    try std.testing.expectEqualStrings("C", report.messageText(&scratch).?);
}

test "Rex ID limits count separators and reject entire invalid report" {
    const segment = "abcdefghijklmnopqrstuvwxyz123456";
    comptime std.debug.assert(segment.len == 32);
    const valid = segment ++ "/" ++ segment ++ "/" ++ segment ++ "/abcdefghijklmnopqrstuvwxyz123";
    comptime std.debug.assert(valid.len == 128);
    try std.testing.expectEqualStrings(valid, status.parse("state=working:id=" ++ valid).?.report.id);
    try std.testing.expect(status.parse("state=working:id=" ++ valid ++ "4") == null);
    try std.testing.expect(status.parse("state=clear:id=" ++ segment ++ "x") == null);
    try std.testing.expect(status.parse("state=clear:id=a/b/c/d/e/f/g/h/i") == null);
    try std.testing.expectEqualStrings("a/b/c/d/e/f/g/h", status.parse("state=working:id=a/b/c/d/e/f/g/h").?.report.id);
}

test "Rex field limits reject even malformed oversized values before duplicate resolution" {
    const too_long_app = "abcdefghijklmnopqrstuvwxyz1234567";
    try std.testing.expect(status.parse("state=working:app=" ++ too_long_app ++ "%:app=ok") == null);
    const title: [257]u8 = @splat('A');
    var buf: [512]u8 = undefined;
    const body = try std.fmt.bufPrint(&buf, "state=working:title={s}%:title=QQ==", .{&title});
    try std.testing.expect(status.parse(body) == null);
}

test "Rex source key application and decoded text bounds are independent" {
    try std.testing.expect(status.parse("state=working:abcdefghijklmnop=value") != null);
    try std.testing.expect(status.parse("state=working:abcdefghijklmnopq=value") == null);
    const name = "abcdefghijklmnopqrstuvwxyz123456";
    try std.testing.expectEqualStrings(name, status.parse("state=working:app=" ++ name).?.report.app);
    try std.testing.expect(status.parse("state=working:app=" ++ name ++ "7") == null);
    var encoded: [2736]u8 = undefined;
    var body: [4096]u8 = undefined;
    var scratch: [status.max_msg_bytes]u8 = undefined;
    const message: [2049]u8 = @splat('m');
    for ([_]usize{ 2048, 2049 }) |len| {
        const msg = std.base64.standard.Encoder.encode(&encoded, message[0..len]);
        const wire_body = try std.fmt.bufPrint(&body, "state=working:msg={s}", .{msg});
        if (len == 2048) {
            const parsed = status.parse(wire_body).?.report;
            try std.testing.expectEqualStrings(message[0..len], parsed.messageText(&scratch).?);
        } else {
            // 2049 decoded bytes also fit in 2732 encoded bytes.
            try std.testing.expectEqual(@as(usize, 2732), msg.len);
            try std.testing.expect(status.parse(wire_body) == null);
        }
    }
    const heading: [193]u8 = @splat('t');
    for ([_]usize{ 192, 193 }) |len| {
        const title = std.base64.standard.Encoder.encode(&encoded, heading[0..len]);
        const wire_body = try std.fmt.bufPrint(&body, "state=working:title={s}", .{title});
        if (len == 192) {
            const parsed = status.parse(wire_body).?.report;
            try std.testing.expectEqualStrings(heading[0..len], parsed.titleText(&scratch).?);
        } else try std.testing.expect(status.parse(wire_body) == null);
    }
}

test "Rex skips malformed pairs and uses last recognized values without fabricating state" {
    const parsed = status.parse("state=idle:broken:=empty:state=working:unknown=future:app=first:app=bad%value:kind=auth:progress=100").?.report;
    try std.testing.expect(parsed.state == .working);
    try std.testing.expectEqualStrings("first", parsed.app);
    try std.testing.expectEqual(@as(?u8, 100), parsed.progress);
    try std.testing.expect(parsed.kind == null);
    try std.testing.expect(status.parse("state=working:state=unrecognized") == null);
    try std.testing.expect(status.parse("state=clear:id=") == null);
    try std.testing.expectEqualStrings("", status.parse("state=working:app=first:app=bad/name").?.report.app);
    for ([_][]const u8{ "-1", "+1", "101", "1.5", "1_0", "99999999999999999999" }) |value| {
        var buf: [128]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf, "state=blocked:progress={s}", .{value});
        try std.testing.expect(status.parse(body).?.report.progress == null);
    }
}
