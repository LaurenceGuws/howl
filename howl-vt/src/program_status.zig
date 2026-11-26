//! OSC 7501 revision-0.4 status grammar shared by Ghostty and modern Kitty.
//! Validates one borrowed completed body after "7501;" without allocating.
//! The host owns any status records, feature replies and visible UI.
const std = @import("std");

/// Rex revision 0.4 counts the entire 7-bit OSC sequence including ST.
pub const max_sequence_bytes: usize = 4096;
/// Largest possible body, with the one-byte BEL terminator.
pub const max_body_bytes: usize = max_sequence_bytes - "\x1b]7501;".len - 1;
/// Maximum body when terminated by ESC backslash (also used for C1 ST).
pub const max_st_body_bytes: usize = max_body_bytes - 1;
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

    /// Decode validated title into fixed caller-owned scratch.
    pub fn titleText(self: Report, scratch: *[max_msg_bytes]u8) ?[]const u8 {
        if (self.title.len == 0) return "";
        return decodeText(self.title, scratch, max_title_bytes);
    }

    /// Decode validated message into fixed caller-owned scratch.
    pub fn messageText(self: Report, scratch: *[max_msg_bytes]u8) ?[]const u8 {
        if (self.msg.len == 0) return "";
        return decodeText(self.msg, scratch, max_msg_bytes);
    }
};

/// Query recognition does not authorize a reply without a real host consumer.
pub const Action = union(enum) {
    query,
    /// An accepted OSC 133 A, ordered with reports; never parsed as OSC 7501.
    prompt_started,
    clear: []const u8,
    report: Report,
};

/// Only grammar is owned here: no user interface, timers or retained status.
pub fn parse(body: []const u8) ?Action {
    if (body.len == 0 or body.len > max_body_bytes) return null;
    if (std.mem.eql(u8, body, "?")) return .query;

    var id: []const u8 = "";
    var state_field: []const u8 = "";
    var kind_field: []const u8 = "";
    var progress_field: []const u8 = "";
    var app: []const u8 = "";
    var title: []const u8 = "";
    var msg: []const u8 = "";

    var scratch: [max_msg_bytes]u8 = undefined;
    var pairs = std.mem.splitScalar(u8, body, ':');
    while (pairs.next()) |pair| {
        const separator = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = std.mem.trim(u8, pair[0..separator], whitespace);
        const value = std.mem.trim(u8, pair[separator + 1 ..], whitespace);
        if (key.len > max_key_bytes) return null;
        if (!lowercaseKey(key)) continue;
        // A hard field cap applies even if the pair will later be skipped.
        if (std.mem.eql(u8, key, "app") and value.len > max_app_bytes) return null;
        if (std.mem.eql(u8, key, "title") and value.len > max_title_encoded_bytes) return null;
        if (std.mem.eql(u8, key, "msg") and value.len > max_msg_encoded_bytes) return null;
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
            app = value;
        } else if (std.mem.eql(u8, key, "title")) {
            if (decodeText(value, &scratch, max_title_bytes) == null) return null;
            title = value;
        } else if (std.mem.eql(u8, key, "msg")) {
            if (decodeText(value, &scratch, max_msg_bytes) == null) return null;
            msg = value;
        }
    }
    // Every admitted text pair was validated before duplicate resolution.
    // Neither replacement nor clear can hide a rejected field.
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

// Rex permits padded and unpadded standard base64.
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
