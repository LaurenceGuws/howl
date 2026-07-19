//! Owns bounded protocol consequences retained for host inspection or drain.

const std = @import("std");
const dcs_payload = @import("dcs_payload.zig");
const legacy_control = @import("legacy_control.zig");
const locator = @import("locator.zig");
const osc_color = @import("osc_color.zig");
const osc = @import("osc.zig");
const iterm = @import("iterm.zig");

const LocatorNs = locator;
const OscColorNs = osc_color;

const ClipboardRequest = struct {
    raw: []u8,
};

const CopyIntoResult = union(enum) {
    copied: u64,
    short: u64,
};

const ClipboardDrainResult = union(enum) {
    none,
    copied: u64,
    short: u64,
    failed,
};

/// Reports allocation failure or rejection by a concrete retained-consequence bound.
pub const ApplyError = error{
    OutOfMemory,
    ConsequenceLimit,
};

/// Accumulated replies await a host drain and stop at a bounded 64 KiB queue.
pub const pending_output_max_bytes: u32 = 64 * 1024;
/// OSC 52 is unchunked; retain at most the parser's 1 MiB clipboard packet.
const clipboard_max_bytes: u32 = 1024 * 1024;
/// Retained DCS families are metadata protocols bounded by parser acceptance.
const dcs_payload_max_bytes: u32 = 2 * 1024;
/// One hyperlink URI shares the ordinary OSC metadata scale.
const hyperlink_target_max_bytes: u32 = 2 * 1024;
/// Each retained title or icon name follows the 1 KiB parser metadata scale.
pub const metadata_max_bytes: u32 = 1024;
/// A terminal instance interns at most 4096 distinct hyperlink targets.
const hyperlink_target_max_count: u32 = 4096;
/// Owns the latest bounded OSC 133 shell mark.
pub const ShellMark = struct {
    kind: u8 = 0,
    status: ?i32 = null,
    metadata: []u8 = &[_]u8{},
};

/// Owns validated shell-integration identity until replacement or deinit.
pub const ShellIntegration = struct {
    version: u32,
    shell: ?[]u8,
};

comptime {
    std.debug.assert(metadata_max_bytes <= hyperlink_target_max_bytes);
    std.debug.assert(dcs_payload_max_bytes <= pending_output_max_bytes);
    std.debug.assert(hyperlink_target_max_count > 0);
}

/// Converts a slice length after asserting it fits the protocol-owned u32 domain.
pub fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

fn hyperlinkCount(items: []const []u8) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

/// Retains bounded terminal consequences for later host inspection or drain.
///
/// `allocator` is borrowed for the State lifetime and owns every retained
/// allocation; caller-selected drain allocators own only returned buffers.
pub const State = struct {
    // Host consequence retention is heap-backed today, but every retained path
    // is bounded by this file's product capacity constants before allocation.
    const DcsPayloadOwned = struct {
        kind: dcs_payload.DcsPayloadKind,
        payload: []u8,
    };

    allocator: std.mem.Allocator,
    colors: OscColorNs.TerminalColorState = .{},
    pending_output: std.ArrayList(u8),
    hyperlink_targets: std.ArrayList([]u8),
    pending_clipboard: ?ClipboardRequest = null,
    current_title: ?[]u8 = null,
    current_icon: ?[]u8 = null,
    shell_integration: ?ShellIntegration = null,
    shell_mark: ShellMark = .{},
    bell_generation: u64 = 0,
    locator: LocatorNs.Locator = .{},
    media_copy_request: ?u16 = null,
    dcs_payload: ?DcsPayloadOwned = null,
    legacy_control: ?legacy_control.LegacyControlKind = null,

    /// Initialize empty consequence state borrowing `allocator` until deinit.
    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .allocator = allocator,
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    /// Release every retained allocation through the initializer allocator.
    pub fn deinit(self: *State) void {
        for (self.hyperlink_targets.items) |uri| self.allocator.free(uri);
        self.hyperlink_targets.deinit(self.allocator);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        if (self.current_title) |title| self.allocator.free(title);
        if (self.current_icon) |icon| self.allocator.free(icon);
        if (self.shell_integration) |integration|
            if (integration.shell) |shell| self.allocator.free(shell);
        self.allocator.free(self.shell_mark.metadata);
        if (self.dcs_payload) |payload| self.allocator.free(payload.payload);
        self.pending_output.deinit(self.allocator);
    }

    /// Reset host-observed state governed by terminal reset.
    pub fn resetTerminalState(self: *State) void {
        self.locator = .{};
    }

    /// Borrow pending terminal reply bytes until the next State mutation.
    pub fn pendingOutput(self: *const State) []const u8 {
        return self.pending_output.items;
    }

    /// Append bounded reply bytes transactionally through the State allocator.
    pub fn appendPendingOutput(self: *State, bytes: []const u8) ApplyError!void {
        try appendOutput(&self.pending_output, self.allocator, bytes);
    }

    /// Replace the bounded title after allocation succeeds, preserving the old title on failure.
    pub fn replaceTitle(self: *State, title: []const u8) ApplyError!void {
        try replaceMetadata(self, &self.current_title, title);
    }

    /// Replace the bounded icon name transactionally.
    pub fn replaceIcon(self: *State, icon: []const u8) ApplyError!void {
        try replaceMetadata(self, &self.current_icon, icon);
    }

    /// Replaces typed shell integration after optional shell allocation succeeds.
    pub fn replaceShellIntegration(
        self: *State,
        integration: iterm.ShellIntegration,
    ) ApplyError!void {
        const shell = if (integration.shell) |value| blk: {
            if (value.len > iterm.shell_name_max_bytes) return error.ConsequenceLimit;
            break :blk try self.allocator.dupe(u8, value);
        } else null;
        if (self.shell_integration) |old|
            if (old.shell) |value| self.allocator.free(value);
        self.shell_integration = .{
            .version = integration.version,
            .shell = shell,
        };
    }

    /// Replaces one bounded shell mark without disturbing the prior mark on failure.
    pub fn replaceShellMark(self: *State, mark: iterm.ShellMark) ApplyError!void {
        try ensureRetainedBound(byteCount(mark.metadata), metadata_max_bytes);
        const metadata = try self.allocator.dupe(u8, mark.metadata);
        self.allocator.free(self.shell_mark.metadata);
        self.shell_mark = .{
            .kind = mark.kind,
            .status = mark.status,
            .metadata = metadata,
        };
    }

    /// Replace title and icon together after both bounded allocations succeed.
    pub fn replaceTitleAndIcon(self: *State, value: []const u8) ApplyError!void {
        try ensureRetainedBound(byteCount(value), metadata_max_bytes);
        const title = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(title);
        const icon = try self.allocator.dupe(u8, value);
        if (self.current_title) |old| self.allocator.free(old);
        if (self.current_icon) |old| self.allocator.free(old);
        self.current_title = title;
        self.current_icon = icon;
    }

    /// Retain one BEL occurrence without choosing an audible or visual policy.
    pub fn ringBell(self: *State) ApplyError!void {
        if (self.bell_generation == std.math.maxInt(u64))
            return error.ConsequenceLimit;
        self.bell_generation += 1;
    }

    /// Replace the retained clipboard request after bounds and allocation succeed.
    pub fn replaceClipboard(self: *State, payload: []const u8) ApplyError!void {
        try ensureRetainedBound(byteCount(payload), clipboard_max_bytes);
        const owned = try self.allocator.dupe(u8, payload);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = .{ .raw = owned };
    }

    /// Replace the retained DCS payload after bounds and allocation succeed.
    pub fn replaceDcsPayload(self: *State, payload: dcs_payload.DcsPayload) ApplyError!void {
        try ensureRetainedBound(byteCount(payload.payload), dcs_payload_max_bytes);
        const owned = try self.allocator.dupe(u8, payload.payload);
        if (self.dcs_payload) |old| self.allocator.free(old.payload);
        self.dcs_payload = .{ .kind = payload.kind, .payload = owned };
    }

    /// Return a stable nonzero URI identity, preserving existing identities on failure.
    pub fn internHyperlink(self: *State, uri: []const u8) ApplyError!u32 {
        for (self.hyperlink_targets.items, 0..) |existing, idx| {
            if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
        }
        try ensureRetainedBound(byteCount(uri), hyperlink_target_max_bytes);
        if (hyperlinkCount(self.hyperlink_targets.items) >= hyperlink_target_max_count) return error.ConsequenceLimit;
        const owned = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned);
        try self.hyperlink_targets.append(self.allocator, owned);
        return hyperlinkCount(self.hyperlink_targets.items);
    }

    /// Copy pending replies into caller memory without consuming them.
    fn copyPendingOutputInto(self: *const State, out: []u8) CopyIntoResult {
        const pending = self.pendingOutput();
        if (out.len < pending.len) return .{ .short = @intCast(pending.len) };
        if (pending.len != 0) @memcpy(out[0..pending.len], pending);
        return .{ .copied = @intCast(pending.len) };
    }

    /// Consume pending replies while retaining their allocation capacity.
    pub fn clearPendingOutput(self: *State) void {
        self.pending_output.clearRetainingCapacity();
    }

    /// Borrow the URI for a retained nonzero identity, or return null.
    pub fn hyperlinkUriForId(self: *const State, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.hyperlink_targets.items.len) return null;
        return self.hyperlink_targets.items[idx];
    }

    /// Borrow the pending raw clipboard request until the next State mutation.
    pub fn pendingClipboardSet(self: *const State) ?[]const u8 {
        if (self.pending_clipboard) |req| return req.raw;
        return null;
    }

    /// Consume and release the pending raw clipboard request.
    pub fn clearPendingClipboardSet(self: *State) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = null;
    }

    /// Decode into caller-owned memory; allocation failure preserves the request.
    pub fn drainPendingClipboardSet(self: *State, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        const pending = self.pendingClipboardSet() orelse return null;
        const decoded = osc.decodeClipboardSet(allocator, pending) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.clearPendingClipboardSet();
                return null;
            },
        };
        self.clearPendingClipboardSet();
        return decoded;
    }

    /// Decode into caller memory and consume only after a complete copy.
    fn drainPendingClipboardSetInto(self: *State, out: []u8) ClipboardDrainResult {
        const pending = self.pendingClipboardSet() orelse return .none;
        const decoded_len = osc.decodedClipboardSetSize(pending) catch return .failed;
        if (out.len < decoded_len) return .{ .short = decoded_len };
        const written = osc.decodeClipboardSetInto(pending, out) catch return .failed;
        self.clearPendingClipboardSet();
        return .{ .copied = written };
    }

    /// Return the most recently retained media-copy request.
    pub fn mediaCopyRequest(self: *const State) ?u16 {
        return self.media_copy_request;
    }

    /// Return the retained DCS payload kind, if any.
    pub fn dcsPayloadKind(self: *const State) ?dcs_payload.DcsPayloadKind {
        if (self.dcs_payload) |payload| return payload.kind;
        return null;
    }

    /// Borrow the retained DCS payload bytes, if any.
    pub fn dcsPayload(self: *const State) ?[]const u8 {
        if (self.dcs_payload) |payload| return payload.payload;
        return null;
    }

    /// Return the most recently observed legacy control kind.
    pub fn legacyControl(self: *const State) ?legacy_control.LegacyControlKind {
        return self.legacy_control;
    }

    /// Return a value snapshot of host-observable terminal colors.
    pub fn terminalColorState(self: *const State) OscColorNs.TerminalColorState {
        return self.colors;
    }
};

fn replaceMetadata(
    self: *State,
    destination: *?[]u8,
    bytes: []const u8,
) ApplyError!void {
    try ensureRetainedBound(byteCount(bytes), metadata_max_bytes);
    const owned = try self.allocator.dupe(u8, bytes);
    if (destination.*) |old| self.allocator.free(old);
    destination.* = owned;
}

test "shell mark replacement is bounded transactional and reusable" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        replaceShellMarkAllocation,
        .{},
    );

    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const oversized = [_]u8{'x'} ** (metadata_max_bytes + 1);
    try std.testing.expectError(error.ConsequenceLimit, state.replaceShellMark(.{
        .kind = 'C',
        .status = null,
        .metadata = &oversized,
    }));
}

fn replaceShellMarkAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    state.replaceShellMark(.{ .kind = 'C', .status = null, .metadata = "old" }) catch |failure| {
        try std.testing.expectEqual(@as(u8, 0), state.shell_mark.kind);
        return failure;
    };
    state.replaceShellMark(.{ .kind = 'D', .status = 7, .metadata = "7" }) catch |failure| {
        try std.testing.expectEqual(@as(u8, 'C'), state.shell_mark.kind);
        try std.testing.expectEqualStrings("old", state.shell_mark.metadata);
        return failure;
    };
    try std.testing.expectEqual(@as(u8, 'D'), state.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), state.shell_mark.status);
    try std.testing.expectEqualStrings("7", state.shell_mark.metadata);
}

/// Appends a reply transactionally within the accumulated-output bound.
pub fn appendOutput(output: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) ApplyError!void {
    try ensureAppendBound(byteCount(output.items), byteCount(bytes), pending_output_max_bytes);
    try output.appendSlice(allocator, bytes);
}

/// Restores drained reply bytes ahead of current output without partial mutation.
pub fn restorePendingOutput(output: *std.ArrayList(u8), len: u32) void {
    std.debug.assert(len <= byteCount(output.items));
    output.items.len = len;
}

fn ensureAppendBound(current_len: u32, append_len: u32, max_len: u32) ApplyError!void {
    const next_len = std.math.add(u32, current_len, append_len) catch return error.ConsequenceLimit;
    try ensureRetainedBound(next_len, max_len);
}

fn ensureRetainedBound(len: u32, max_len: u32) ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

test "clipboard replacement preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceClipboardAllocation, .{});
}

test "title replacement preserves the retained title on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceTitleAllocation, .{});
}

test "icon replacement preserves title and prior icon on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceIconAllocation, .{});
}

test "paired title and icon replacement is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        replaceTitleAndIconAllocation,
        .{},
    );
}

fn replaceTitleAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.replaceTitle("old");
    state.replaceTitle("new") catch |err| {
        try std.testing.expectEqualStrings("old", state.current_title.?);
        return err;
    };
    try std.testing.expectEqualStrings("new", state.current_title.?);
}

fn replaceIconAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.replaceTitle("title");
    try state.replaceIcon("old");
    state.replaceIcon("new") catch |err| {
        try std.testing.expectEqualStrings("title", state.current_title.?);
        try std.testing.expectEqualStrings("old", state.current_icon.?);
        return err;
    };
    try std.testing.expectEqualStrings("title", state.current_title.?);
    try std.testing.expectEqualStrings("new", state.current_icon.?);
}

fn replaceTitleAndIconAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.replaceTitle("old-title");
    try state.replaceIcon("old-icon");
    state.replaceTitleAndIcon("both") catch |err| {
        try std.testing.expectEqualStrings("old-title", state.current_title.?);
        try std.testing.expectEqualStrings("old-icon", state.current_icon.?);
        return err;
    };
    try std.testing.expectEqualStrings("both", state.current_title.?);
    try std.testing.expectEqualStrings("both", state.current_icon.?);
}

fn replaceClipboardAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.replaceClipboard("c;b2xk");
    state.replaceClipboard("c;bmV3") catch |err| {
        try std.testing.expectEqualStrings("c;b2xk", state.pendingClipboardSet().?);
        return err;
    };
    try std.testing.expectEqualStrings("c;bmV3", state.pendingClipboardSet().?);
}

test "hyperlink interning preserves prior identities on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, internHyperlinkAllocation, .{});
}

fn internHyperlinkAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try std.testing.expectEqual(@as(u32, 1), try state.internHyperlink("https://one.example"));
    const second_id = state.internHyperlink("https://two.example") catch |err| {
        try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
        try std.testing.expectEqual(@as(?[]const u8, null), state.hyperlinkUriForId(2));
        return err;
    };
    try std.testing.expectEqual(@as(u32, 2), second_id);
    try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
    try std.testing.expectEqualStrings("https://two.example", state.hyperlinkUriForId(2).?);
}

test "clipboard drain preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, drainClipboardAllocation, .{});
}

test "retained host consequences enforce owner-specific boundaries" {
    const allocator = std.testing.allocator;
    var state = State.init(allocator);
    defer state.deinit();

    const title = try allocator.alloc(u8, metadata_max_bytes + 1);
    defer allocator.free(title);
    @memset(title, 't');
    try state.replaceTitle(title[0 .. metadata_max_bytes - 1]);
    try state.replaceTitle(title[0..metadata_max_bytes]);
    try std.testing.expectError(error.ConsequenceLimit, state.replaceTitle(title));
    try std.testing.expectEqual(metadata_max_bytes, byteCount(state.current_title.?));

    const hyperlink = try allocator.alloc(u8, hyperlink_target_max_bytes + 1);
    defer allocator.free(hyperlink);
    @memset(hyperlink, 'h');
    try std.testing.expectEqual(@as(u32, 1), try state.internHyperlink(hyperlink[0 .. hyperlink_target_max_bytes - 1]));
    try std.testing.expectEqual(@as(u32, 2), try state.internHyperlink(hyperlink[0..hyperlink_target_max_bytes]));
    try std.testing.expectError(error.ConsequenceLimit, state.internHyperlink(hyperlink));
    try std.testing.expectEqual(@as(u32, 2), hyperlinkCount(state.hyperlink_targets.items));

    const dcs = try allocator.alloc(u8, dcs_payload_max_bytes + 1);
    defer allocator.free(dcs);
    @memset(dcs, 'd');
    try state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs[0 .. dcs_payload_max_bytes - 1] });
    try state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs[0..dcs_payload_max_bytes] });
    try std.testing.expectError(
        error.ConsequenceLimit,
        state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs }),
    );
    try std.testing.expectEqual(dcs_payload_max_bytes, byteCount(state.dcsPayload().?));

    const clipboard = try allocator.alloc(u8, clipboard_max_bytes + 1);
    defer allocator.free(clipboard);
    @memset(clipboard, 'c');
    try state.replaceClipboard(clipboard[0 .. clipboard_max_bytes - 1]);
    try state.replaceClipboard(clipboard[0..clipboard_max_bytes]);
    try std.testing.expectError(error.ConsequenceLimit, state.replaceClipboard(clipboard));
    try std.testing.expectEqual(clipboard_max_bytes, byteCount(state.pendingClipboardSet().?));
}

test "pending output enforces exact accumulated boundary" {
    const allocator = std.testing.allocator;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    const bytes = try allocator.alloc(u8, pending_output_max_bytes + 1);
    defer allocator.free(bytes);
    @memset(bytes, 'o');

    try appendOutput(&output, allocator, bytes[0 .. pending_output_max_bytes - 1]);
    try appendOutput(&output, allocator, bytes[pending_output_max_bytes - 1 .. pending_output_max_bytes]);
    try std.testing.expectEqual(pending_output_max_bytes, byteCount(output.items));
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendOutput(&output, allocator, bytes[pending_output_max_bytes..]),
    );
    try std.testing.expectEqual(pending_output_max_bytes, byteCount(output.items));
}

fn drainClipboardAllocation(result_allocator: std.mem.Allocator) !void {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try state.replaceClipboard("c;SG93bA==");
    const decoded = state.drainPendingClipboardSet(result_allocator) catch |err| {
        try std.testing.expectEqualStrings("c;SG93bA==", state.pendingClipboardSet().?);
        return err;
    };
    defer result_allocator.free(decoded.?);
    try std.testing.expectEqualStrings("Howl", decoded.?);
    try std.testing.expectEqual(@as(?[]const u8, null), state.pendingClipboardSet());
}
