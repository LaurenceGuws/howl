//! OSC 7501 revision-0.4 status grammar shared by Ghostty and modern Kitty.
//! Validates one borrowed completed body after "7501;" without allocating.
//! The host owns any status records, feature replies and visible UI.
const std = @import("std");

/// The ordinary OSC transport retains 2048 bytes including "7501;".
/// The complete 4096-byte status protocol is a future transport cut.
pub const max_body_bytes: usize = 2048 - "7501;".len;
/// Maximum decoded message bytes the caller can observe in fixed scratch.
/// Maximum decoded message bytes the caller can observe in fixed scratch.
/// Maximum decoded message bytes retained in caller scratch.
pub const max_msg_bytes: usize = 2048;
const max_title_bytes: usize = 192;
const max_id_bytes: usize = 128;
const max_id_segments: usize = 8;
const max_id_segment_bytes: usize = 32;
const max_key_bytes: usize = 16;
const max_app_bytes: usize = 32;
const max_title_encoded_bytes: usize = 256;
const max_msg_encoded_bytes: usize = 2732;
const whitespace = " \t\n\r\x0b\x0c";

/// Recognized status states. Clear is a separate action, never a status.
pub const State = enum { idle, working, done, blocked, @"error" };
/// User interaction classes accepted only when a report is blocked.
/// User interaction classes accepted only when a report is blocked.
/// Interaction kinds accepted only for blocked program reports.
pub const Kind = enum { permission, question, auth };

/// Borrowed validated report fields; decoded text uses caller-owned scratch.
pub const Report = struct {
    state: State,
    id: []const u8 = "",
    kind: ?Kind = null,
    progress: ?u8 = null,
    app: []const u8 = "",
    title: []const u8 = "",
    msg: []const u8 = "",

    /// Decodes validated title bytes into caller-owned bounded scratch.
    /// Decodes validated title bytes into caller-owned bounded scratch.
    /// Decode validated title into fixed caller-owned scratch.
    pub fn titleText(self: Report, scratch: *[max_msg_bytes]u8) ?[]const u8 {
        if (self.title.len == 0) return "";
        return decodeText(self.title, scratch, max_title_bytes);
    }

    /// Decodes validated message bytes into caller-owned bounded scratch.
    /// Decodes validated message bytes into caller-owned bounded scratch.
    /// Decode validated message into fixed caller-owned scratch.
    pub fn messageText(self: Report, scratch: *[max_msg_bytes]u8) ?[]const u8 {
        if (self.msg.len == 0) return "";
        return decodeText(self.msg, scratch, max_msg_bytes);
    }
};

/// Query recognition does not authorize a reply without a real host consumer.
pub const Action = union(enum) {
    query,
    process_exited,
    clear: []const u8,
    report: Report,
};

/// Only grammar is owned here: no user interface, timers or retained status.
pub fn parse(body: []const u8) ?Action {
    if (body.len == 0 or body.len > max_body_bytes) return null;
    if (std.mem.eql(u8, body, "?")) return .query;
    if (std.mem.eql(u8, body, "process-exited")) return .process_exited;

    var id: []const u8 = "";
    var state_field: []const u8 = "";
    var kind_field: []const u8 = "";
    var progress_field: []const u8 = "";
    var app: []const u8 = "";
    var title: []const u8 = "";
    var msg: []const u8 = "";

    var pairs = std.mem.splitScalar(u8, body, ':');
    while (pairs.next()) |pair| {
        const separator = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = std.mem.trim(u8, pair[0..separator], whitespace);
        const value = std.mem.trim(u8, pair[separator + 1 ..], whitespace);
        if (key.len > max_key_bytes) return null;
        if (!lowercaseKey(key)) continue;
        if (!validValue(value)) {
            // Invalid id must not silently target the root record.
            if (std.mem.eql(u8, key, "id")) return null;
            continue;
        }
        if (std.mem.eql(u8, key, "id")) {
            if (!validId(value)) return null;
            id = value;
        } else if (std.mem.eql(u8, key, "state")) {
            state_field = value;
        } else if (std.mem.eql(u8, key, "kind")) {
            kind_field = value;
        } else if (std.mem.eql(u8, key, "progress")) {
            progress_field = value;
        } else if (std.mem.eql(u8, key, "app")) {
            if (value.len > max_app_bytes) return null;
            app = value;
        } else if (std.mem.eql(u8, key, "title")) {
            if (value.len > max_title_encoded_bytes) return null;
            title = value;
        } else if (std.mem.eql(u8, key, "msg")) {
            if (value.len > max_msg_encoded_bytes) return null;
            msg = value;
        }
    }
    // Both references decode/validate every recognized text field before
    // distinguishing clear from update. An invalid title on a clear cannot
    // bypass admission by taking the early clear branch.
    var scratch: [max_msg_bytes]u8 = undefined;
    if (title.len != 0 and decodeText(title, &scratch, max_title_bytes) == null) return null;
    if (msg.len != 0 and decodeText(msg, &scratch, max_msg_bytes) == null) return null;
    if (std.mem.eql(u8, state_field, "clear")) return .{ .clear = id };
    const state = std.meta.stringToEnum(State, state_field) orelse return null;

    const kind: ?Kind = if (state == .blocked)
        std.meta.stringToEnum(Kind, kind_field)
    else
        null;
    const progress: ?u8 = if (state == .working or state == .blocked)
        validProgress(progress_field)
    else
        null;
    return .{ .report = .{
        .state = state,
        .id = id,
        .kind = kind,
        .progress = progress,
        .app = if (validName(app)) app else "",
        .title = title,
        .msg = msg,
    } };
}

fn lowercaseKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |byte| if (byte < 'a' or byte > 'z') return false;
    return true;
}

fn validName(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        switch (byte) {
            '_', '.', '+', '-' => {},
            else => return false,
        }
    }
    return true;
}

fn validValue(value: []const u8) bool {
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        switch (byte) {
            '_', '.', '+', '-', ',', '/', '=' => {},
            else => return false,
        }
    }
    return true;
}

fn validId(value: []const u8) bool {
    if (value.len == 0 or value.len > max_id_bytes) return false;
    var depth: usize = 0;
    var segments = std.mem.splitScalar(u8, value, '/');
    while (segments.next()) |segment| {
        depth += 1;
        if (depth > max_id_segments or segment.len > max_id_segment_bytes or !validName(segment)) return false;
    }
    return true;
}

fn validProgress(value: []const u8) ?u8 {
    if (value.len == 0) return null;
    var number: u16 = 0;
    for (value) |byte| {
        if (byte < '0' or byte > '9') return null;
        number = number * 10 + (byte - '0');
        if (number > 100) return null;
    }
    return @intCast(number);
}

// Both source references allow padded and unpadded standard base64.
// Decoded UTF-8 may not contain C0, DEL, or C1 control codepoints.
fn decodeText(encoded: []const u8, scratch: *[max_msg_bytes]u8, max_decoded: usize) ?[]const u8 {
    const decoder = if (std.mem.endsWith(u8, encoded, "="))
        std.base64.standard.Decoder
    else
        std.base64.standard_no_pad.Decoder;
    const len = decoder.calcSizeForSlice(encoded) catch return null;
    if (len > max_decoded) return null;
    const result = scratch[0..len];
    decoder.decode(result, encoded) catch return null;
    if (!std.unicode.utf8ValidateSlice(result)) return null;
    for (result, 0..) |byte, i| {
        if (byte < 0x20 or byte == 0x7f) return null;
        if (i > 0 and byte >= 0x80 and byte <= 0x9f and result[i - 1] == 0xc2) return null;
    }
    return result;
}
