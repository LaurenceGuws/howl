//! Public, allocation-free OSC 7501 grammar acceptance tests, no host UI.
const std = @import("std");
const status = @import("../../src/program_status.zig");

test "OSC 7501 query and process-exited do not invent host status" {
    try std.testing.expect(status.parse("?").? == .query);
    try std.testing.expect(status.parse("process-exited").? == .process_exited);
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
