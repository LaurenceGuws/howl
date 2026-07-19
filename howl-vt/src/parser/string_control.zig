//! Owns incremental delimited-control state and bounded OSC payload buffering.

const std = @import("std");
const parser_mod = @import("../parser.zig");

const ByteLimit = u32;

/// String-control terminator.
pub const Finish = enum {
    bel,
    st,
};

const FeedResult = union(enum) {
    put: u8,
    finish: Finish,
};

const DelimitedState = enum {
    idle,
    payload,
    esc,
};

/// Owns bounded incremental OSC parsing and its reusable payload allocation.
pub const OscControl = struct {
    const Failure = error{ OutOfMemory, StringControlLimit };
    const prefix_max_bytes = 8;

    const CommandPolicy = struct {
        command: ?u16,
        class: OscClass,
        max_len: ByteLimit,
    };

    const OscClass = enum {
        raw_title,
        raw_other,
        title,
        icon,
        palette_control,
        palette_reset,
        dynamic_color,
        dynamic_reset,
        report_pwd,
        hyperlink,
        notification,
        pointer_shape,
        clipboard,
        kitty_color,
        kitty_text_size,
        shell_mark,
        rxvt_extension,
        iterm2,
        context_signal,
        kitty_color_stack_push,
        kitty_color_stack_pop,
        kitty_file_transfer,
        kitty_clipboard,
    };

    allocator: std.mem.Allocator,
    state: OscState = .idle,
    prefix: PrefixState = .start,
    buffer: std.ArrayList(u8),
    metadata_max_len: ByteLimit,
    clipboard_max_len: ByteLimit,
    chunk_max_len: ByteLimit,
    policy: CommandPolicy,
    alloc_failed: bool = false,
    overflowed: bool = false,

    const OscState = enum {
        idle,
        prefix,
        prefix_esc,
        payload,
        payload_esc,
        raw,
        raw_esc,
    };

    const BodyKind = enum {
        payload,
        raw,
    };

    const PrefixState = enum {
        start,
        c0,
        c1,
        c2,
        c3,
        c4,
        c5,
        c6,
        c7,
        c8,
        c9,
        c10,
        c11,
        c12,
        c13,
        c14,
        c15,
        c16,
        c17,
        c18,
        c19,
        c21,
        c22,
        c30,
        c50,
        c51,
        c52,
        c55,
        c66,
        c77,
        c99,
        c104,
        c110,
        c111,
        c112,
        c113,
        c114,
        c115,
        c116,
        c117,
        c118,
        c119,
        c133,
        c300,
        c301,
        c511,
        c552,
        c777,
        c1337,
        c3008,
        c3000,
        c30001,
        c3010,
        c30101,
        c5113,
        c5522,
    };

    /// Allocates the initial OSC buffer and records metadata, clipboard, and chunk bounds.
    pub fn init(
        allocator: std.mem.Allocator,
        capacity: ByteLimit,
        metadata_max_len: ByteLimit,
        clipboard_max_len: ByteLimit,
        chunk_max_len: ByteLimit,
    ) error{OutOfMemory}!OscControl {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, @intCast(capacity)),
            .metadata_max_len = metadata_max_len,
            .clipboard_max_len = clipboard_max_len,
            .chunk_max_len = chunk_max_len,
            .policy = .{ .command = null, .class = .raw_title, .max_len = metadata_max_len },
        };
    }

    /// Releases the OSC payload buffer through its initializer allocator.
    pub fn deinit(self: *OscControl) void {
        self.buffer.deinit(self.allocator);
    }

    /// Returns OSC state to idle while retaining reusable capacity.
    pub fn reset(self: *OscControl) void {
        self.state = .idle;
        self.prefix = .start;
        self.alloc_failed = false;
        self.overflowed = false;
        self.policy = .{ .command = null, .class = .raw_title, .max_len = self.metadata_max_len };
        self.buffer.clearRetainingCapacity();
    }

    /// Begins a new OSC and clears prior payload and failure state.
    pub fn start(self: *OscControl) void {
        self.reset();
        self.state = .prefix;
    }

    /// Reports whether an OSC delimiter has started and not finished.
    pub fn active(self: *const OscControl) bool {
        return self.state != .idle;
    }

    /// Reports whether OSC has consumed ESC while awaiting ST or payload continuation.
    pub fn escaping(self: *const OscControl) bool {
        return switch (self.state) {
            .prefix_esc, .payload_esc, .raw_esc => true,
            else => false,
        };
    }

    /// Borrows the completed OSC action until reset, start, feed, or deinit.
    pub fn snapshot(self: *const OscControl, term: parser_mod.OscTerminator) parser_mod.OscAction {
        return switch (self.policy.class) {
            .raw_title => .{ .raw_title = .{ .payload = self.buffer.items, .term = term } },
            .raw_other => .{ .raw_other = .{ .payload = self.buffer.items, .term = term } },
            .title => .{ .title = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .icon => .{ .icon = .{ .payload = self.buffer.items, .term = term } },
            .palette_control => .{ .palette_control = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .palette_reset => .{ .palette_reset = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .dynamic_color => .{ .dynamic_color = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .dynamic_reset => .{ .dynamic_reset = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .report_pwd => .{ .report_pwd = .{ .payload = self.buffer.items, .term = term } },
            .hyperlink => .{ .hyperlink = .{ .payload = self.buffer.items, .term = term } },
            .notification => .{ .notification = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .pointer_shape => .{ .pointer_shape = .{ .payload = self.buffer.items, .term = term } },
            .clipboard => .{ .clipboard = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .kitty_color => .{ .kitty_color = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .kitty_text_size => .{ .kitty_text_size = .{ .payload = self.buffer.items, .term = term } },
            .shell_mark => .{ .shell_mark = .{ .payload = self.buffer.items, .term = term } },
            .rxvt_extension => .{ .rxvt_extension = .{ .payload = self.buffer.items, .term = term } },
            .iterm2 => .{ .iterm2 = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .context_signal => .{ .context_signal = .{ .payload = self.buffer.items, .term = term } },
            .kitty_color_stack_push => .{ .kitty_color_stack_push = term },
            .kitty_color_stack_pop => .{ .kitty_color_stack_pop = term },
            .kitty_file_transfer => .{ .kitty_file_transfer = .{ .payload = self.buffer.items, .term = term } },
            .kitty_clipboard => .{ .kitty_clipboard = .{ .payload = self.buffer.items, .term = term } },
        };
    }

    /// Returns and clears the first OSC allocation or bound failure.
    pub fn takeFailure(self: *OscControl) ?Failure {
        var failure: ?Failure = null;
        if (self.overflowed) {
            failure = error.StringControlLimit;
        } else if (self.alloc_failed) {
            failure = error.OutOfMemory;
        }
        self.alloc_failed = false;
        self.overflowed = false;
        return failure;
    }

    /// Consumes one OSC byte and returns its payload or terminator effect.
    pub fn feed(self: *OscControl, byte: u8) ?FeedResult {
        return switch (self.state) {
            .idle => null,
            .prefix => self.feedPrefix(byte),
            .prefix_esc => self.feedPrefixEsc(byte),
            .payload, .payload_esc => self.feedPayload(byte),
            .raw, .raw_esc => self.feedRaw(byte),
        };
    }

    fn feedPrefix(self: *OscControl, byte: u8) ?FeedResult {
        if (byte == 0x07) {
            self.finishPrefix();
            return .{ .finish = .bel };
        }
        if (byte == 0x9C) {
            self.finishPrefix();
            return .{ .finish = .st };
        }
        if (byte == 0x1B) {
            self.state = .prefix_esc;
            return null;
        }
        if (byte == ';') {
            if (!self.enterPayloadFromPrefix()) return .{ .put = byte };
            return .{ .put = byte };
        }
        if (self.advancePrefix(byte)) |next| {
            self.append(byte);
            self.prefix = next;
            return .{ .put = byte };
        }
        self.enterRawFromPrefix(byte, false);
        return .{ .put = byte };
    }

    fn feedPrefixEsc(self: *OscControl, byte: u8) ?FeedResult {
        if (byte == '\\') {
            self.finishPrefix();
            return .{ .finish = .st };
        }
        self.state = .prefix;
        return self.feedPrefix(byte);
    }

    fn feedPayload(self: *OscControl, byte: u8) ?FeedResult {
        return self.feedBody(.payload, byte);
    }

    fn feedRaw(self: *OscControl, byte: u8) ?FeedResult {
        return self.feedBody(.raw, byte);
    }

    fn feedBody(self: *OscControl, comptime kind: BodyKind, byte: u8) ?FeedResult {
        switch (self.state) {
            bodyState(kind) => {
                if (byte == 0x07) {
                    self.finishBody(kind);
                    return .{ .finish = .bel };
                }
                if (byte == 0x9C) {
                    self.finishBody(kind);
                    return .{ .finish = .st };
                }
                if (byte == 0x1B) {
                    self.state = bodyEscState(kind);
                    return null;
                }
                if (kind == .raw and byte == ';') self.policy.class = .raw_other;
                self.append(byte);
                return .{ .put = byte };
            },
            bodyEscState(kind) => {
                if (byte == '\\') {
                    self.finishBody(kind);
                    return .{ .finish = .st };
                }
                self.state = bodyState(kind);
                if (kind == .raw and byte == ';') self.policy.class = .raw_other;
                self.append(byte);
                return .{ .put = byte };
            },
            else => unreachable,
        }
    }

    fn finishPrefix(self: *OscControl) void {
        if (!self.promoteRecognizedPrefix(.idle)) {
            self.policy = .{ .command = null, .class = .raw_title, .max_len = self.metadata_max_len };
        }
        self.prefix = .start;
        self.state = .idle;
    }

    fn finishRaw(self: *OscControl) void {
        self.policy.command = null;
        self.prefix = .start;
        self.state = .idle;
    }

    fn finishBody(self: *OscControl, comptime kind: BodyKind) void {
        switch (kind) {
            .payload => self.state = .idle,
            .raw => self.finishRaw(),
        }
    }

    fn enterPayloadFromPrefix(self: *OscControl) bool {
        if (self.promoteRecognizedPrefix(.payload)) return true;
        self.enterRawFromPrefix(';', true);
        return false;
    }

    fn enterRawFromPrefix(self: *OscControl, byte: u8, has_separator: bool) void {
        self.policy = .{
            .command = null,
            .class = if (has_separator) .raw_other else .raw_title,
            .max_len = self.metadata_max_len,
        };
        self.prefix = .start;
        self.state = .raw;
        if (byte == ';') self.policy.class = .raw_other;
        self.append(byte);
    }

    fn promoteRecognizedPrefix(self: *OscControl, next_state: OscState) bool {
        self.policy = self.prefixPolicy() orelse return false;
        self.buffer.clearRetainingCapacity();
        self.prefix = .start;
        self.state = next_state;
        return true;
    }

    fn append(self: *OscControl, byte: u8) void {
        std.debug.assert(self.buffer.items.len <= std.math.maxInt(u32));
        const buffer_len: u32 = @intCast(self.buffer.items.len);
        if (buffer_len >= self.policy.max_len) {
            self.overflowed = true;
            return;
        }
        self.buffer.append(self.allocator, byte) catch {
            self.alloc_failed = true;
        };
    }

    fn advancePrefix(self: *const OscControl, byte: u8) ?PrefixState {
        return switch (self.prefix) {
            .start => advanceStart(byte),
            .c1 => advanceC1(byte),
            .c2 => advanceC2(byte),
            .c3 => advanceC3(byte),
            .c5 => advanceC5(byte),
            .c6 => advanceC6(byte),
            .c7 => advanceC7(byte),
            .c9 => advanceC9(byte),
            .c10 => advanceC10(byte),
            .c11 => advanceC11(byte),
            .c13 => advanceC13(byte),
            .c30 => advanceC30(byte),
            .c51 => advanceC51(byte),
            .c55 => advanceC55(byte),
            .c77 => advanceC77(byte),
            .c133 => advanceC133(byte),
            .c300 => advanceC300(byte),
            .c301 => advanceC301(byte),
            .c511 => advanceC511(byte),
            .c552 => advanceC552(byte),
            .c3000 => advanceC3000(byte),
            .c3010 => advanceC3010(byte),
            else => null,
        };
    }

    fn advanceStart(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c0,
            '1' => .c1,
            '2' => .c2,
            '3' => .c3,
            '4' => .c4,
            '5' => .c5,
            '6' => .c6,
            '7' => .c7,
            '8' => .c8,
            '9' => .c9,
            else => null,
        };
    }

    fn advanceC1(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c10,
            '1' => .c11,
            '2' => .c12,
            '3' => .c13,
            '4' => .c14,
            '5' => .c15,
            '6' => .c16,
            '7' => .c17,
            '8' => .c18,
            '9' => .c19,
            else => null,
        };
    }

    fn advanceC2(byte: u8) ?PrefixState {
        return switch (byte) {
            '1' => .c21,
            '2' => .c22,
            else => null,
        };
    }

    fn advanceC3(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c30,
            else => null,
        };
    }

    fn advanceC5(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c50,
            '1' => .c51,
            '2' => .c52,
            '5' => .c55,
            else => null,
        };
    }

    fn advanceC6(byte: u8) ?PrefixState {
        return switch (byte) {
            '6' => .c66,
            else => null,
        };
    }

    fn advanceC7(byte: u8) ?PrefixState {
        return switch (byte) {
            '7' => .c77,
            else => null,
        };
    }

    fn advanceC9(byte: u8) ?PrefixState {
        return switch (byte) {
            '9' => .c99,
            else => null,
        };
    }

    fn advanceC10(byte: u8) ?PrefixState {
        return switch (byte) {
            '4' => .c104,
            else => null,
        };
    }

    fn advanceC11(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c110,
            '1' => .c111,
            '2' => .c112,
            '3' => .c113,
            '4' => .c114,
            '5' => .c115,
            '6' => .c116,
            '7' => .c117,
            '8' => .c118,
            '9' => .c119,
            else => null,
        };
    }

    fn advanceC13(byte: u8) ?PrefixState {
        return switch (byte) {
            '3' => .c133,
            else => null,
        };
    }

    fn advanceC30(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c300,
            '1' => .c301,
            else => null,
        };
    }

    fn advanceC51(byte: u8) ?PrefixState {
        return switch (byte) {
            '1' => .c511,
            else => null,
        };
    }

    fn advanceC55(byte: u8) ?PrefixState {
        return switch (byte) {
            '2' => .c552,
            else => null,
        };
    }

    fn advanceC77(byte: u8) ?PrefixState {
        return switch (byte) {
            '7' => .c777,
            else => null,
        };
    }

    fn advanceC133(byte: u8) ?PrefixState {
        return switch (byte) {
            '7' => .c1337,
            else => null,
        };
    }

    fn advanceC300(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c3000,
            '8' => .c3008,
            else => null,
        };
    }

    fn advanceC301(byte: u8) ?PrefixState {
        return switch (byte) {
            '0' => .c3010,
            else => null,
        };
    }

    fn advanceC511(byte: u8) ?PrefixState {
        return switch (byte) {
            '3' => .c5113,
            else => null,
        };
    }

    fn advanceC552(byte: u8) ?PrefixState {
        return switch (byte) {
            '2' => .c5522,
            else => null,
        };
    }

    fn advanceC3000(byte: u8) ?PrefixState {
        return switch (byte) {
            '1' => .c30001,
            else => null,
        };
    }

    fn advanceC3010(byte: u8) ?PrefixState {
        return switch (byte) {
            '1' => .c30101,
            else => null,
        };
    }

    fn prefixPolicy(self: *const OscControl) ?CommandPolicy {
        return switch (self.prefix) {
            .c0 => .{ .command = 0, .class = .title, .max_len = self.metadata_max_len },
            .c1 => .{ .command = 1, .class = .icon, .max_len = self.metadata_max_len },
            .c2 => .{ .command = 2, .class = .title, .max_len = self.metadata_max_len },
            .c4, .c5 => |state| .{ .command = if (state == .c4) 4 else 5, .class = .palette_control, .max_len = self.metadata_max_len },
            .c7 => .{ .command = 7, .class = .report_pwd, .max_len = self.metadata_max_len },
            .c8 => .{ .command = 8, .class = .hyperlink, .max_len = self.metadata_max_len },
            .c9, .c99 => |state| .{ .command = if (state == .c9) 9 else 99, .class = .notification, .max_len = self.metadata_max_len },
            .c10, .c11, .c12, .c13, .c14, .c15, .c16, .c17, .c18, .c19 => .{ .command = prefixDynamicCommand(self.prefix), .class = .dynamic_color, .max_len = self.metadata_max_len },
            .c21 => .{ .command = 21, .class = .kitty_color, .max_len = self.metadata_max_len },
            .c22 => .{ .command = 22, .class = .pointer_shape, .max_len = self.metadata_max_len },
            .c50 => .{ .command = 50, .class = .iterm2, .max_len = self.metadata_max_len },
            .c52 => .{ .command = 52, .class = .clipboard, .max_len = self.clipboard_max_len },
            .c66 => .{ .command = 66, .class = .kitty_text_size, .max_len = self.metadata_max_len },
            .c104 => .{ .command = 104, .class = .palette_reset, .max_len = self.metadata_max_len },
            .c110, .c111, .c112, .c113, .c114, .c115, .c116, .c117, .c118, .c119 => .{
                .command = prefixDynamicCommand(self.prefix),
                .class = .dynamic_reset,
                .max_len = self.metadata_max_len,
            },
            .c133 => .{ .command = 133, .class = .shell_mark, .max_len = self.metadata_max_len },
            .c777 => .{ .command = 777, .class = .rxvt_extension, .max_len = self.metadata_max_len },
            .c1337 => .{ .command = 1337, .class = .iterm2, .max_len = self.metadata_max_len },
            .c3008 => .{ .command = 3008, .class = .context_signal, .max_len = self.metadata_max_len },
            .c30001 => .{ .command = 30001, .class = .kitty_color_stack_push, .max_len = self.metadata_max_len },
            .c30101 => .{ .command = 30101, .class = .kitty_color_stack_pop, .max_len = self.metadata_max_len },
            .c5113 => .{ .command = 5113, .class = .kitty_file_transfer, .max_len = self.chunk_max_len },
            .c5522 => .{ .command = 5522, .class = .kitty_clipboard, .max_len = self.chunk_max_len },
            else => null,
        };
    }
};

fn prefixDynamicCommand(prefix: OscControl.PrefixState) u16 {
    return switch (prefix) {
        .c10 => 10,
        .c11 => 11,
        .c12 => 12,
        .c13 => 13,
        .c14 => 14,
        .c15 => 15,
        .c16 => 16,
        .c17 => 17,
        .c18 => 18,
        .c19 => 19,
        .c110 => 110,
        .c111 => 111,
        .c112 => 112,
        .c113 => 113,
        .c114 => 114,
        .c115 => 115,
        .c116 => 116,
        .c117 => 117,
        .c118 => 118,
        .c119 => 119,
        else => unreachable,
    };
}

fn bodyState(comptime kind: OscControl.BodyKind) OscControl.OscState {
    return switch (kind) {
        .payload => .payload,
        .raw => .raw,
    };
}

fn bodyEscState(comptime kind: OscControl.BodyKind) OscControl.OscState {
    return switch (kind) {
        .payload => .payload_esc,
        .raw => .raw_esc,
    };
}

/// Incremental string-control parser state without payload ownership.
pub const PassthroughControl = struct {
    state: DelimitedState = .idle,
    bel_terminates: bool,

    /// Initializes allocation-free delimited-control state.
    pub fn init(bel_terminates: bool) PassthroughControl {
        return .{ .bel_terminates = bel_terminates };
    }

    /// Returns delimited-control state to idle.
    pub fn reset(self: *PassthroughControl) void {
        self.state = .idle;
    }

    /// Begins one allocation-free delimited control.
    pub fn start(self: *PassthroughControl) void {
        self.state = .payload;
    }

    /// Reports whether a delimited control is active.
    pub fn active(self: *const PassthroughControl) bool {
        return stateActive(self.state);
    }

    /// Reports whether a delimited control is awaiting ST completion.
    pub fn escaping(self: *const PassthroughControl) bool {
        return stateEscaping(self.state);
    }

    /// Consumes one delimited-control byte without retaining payload data.
    pub fn feed(self: *PassthroughControl, byte: u8) ?FeedResult {
        return feedDelimitedState(&self.state, byte, self.bel_terminates);
    }
};

fn stateActive(state: DelimitedState) bool {
    return state != .idle;
}

fn stateEscaping(state: DelimitedState) bool {
    return state == .esc;
}

fn feedDelimitedState(state: *DelimitedState, byte: u8, bel_terminates: bool) ?FeedResult {
    return switch (state.*) {
        .idle => null,
        .payload => feedPayloadState(state, byte, bel_terminates),
        .esc => feedEscState(state, byte),
    };
}

fn feedPayloadState(state: *DelimitedState, byte: u8, bel_terminates: bool) ?FeedResult {
    if (bel_terminates and byte == 0x07) {
        state.* = .idle;
        return .{ .finish = .bel };
    }
    if (byte == 0x9C) {
        state.* = .idle;
        return .{ .finish = .st };
    }
    if (byte == 0x1B) {
        state.* = .esc;
        return null;
    }
    return .{ .put = byte };
}

fn feedEscState(state: *DelimitedState, byte: u8) ?FeedResult {
    if (byte == '\\') {
        state.* = .idle;
        return .{ .finish = .st };
    }

    // Stray ESC marker is dropped; following byte stays payload.
    state.* = .payload;
    return .{ .put = byte };
}
