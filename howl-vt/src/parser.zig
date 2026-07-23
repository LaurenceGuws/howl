//! Parses bounded terminal bytes and string controls into typed events.

const std = @import("std");

const ParamKind = enum {
    csi,
    dcs,
};
const BufferedControlKind = enum {
    apc,
    pm,
    sos,
};

const DeccirCharsetState = struct {
    g0_designation: u8,
    g1_designation: u8,
    gl_index: u8,
};

// Ghostty raised this from 16 to 24 after hitting real 17-parameter SGR input
// from Kakoune. Howl now matches 24 because queued CSI and DCS events no longer
// carry this bound inline in the parsed-event union. Keep this aligned with the
// Ghostty reference unless later proof falsifies the current cut.
const csi_max_params = 24;
const csi_max_intermediates = 4;
// Start metadata controls small so ordinary title, report, and color traffic
// avoids immediate growth without preallocating the full metadata ceiling for
// every parser-owned control buffer.
const control_init_capacity = 256;
// Ghostty's fixed OSC parser demonstrates that ordinary terminal metadata fits
// in 2 KiB. Howl uses that scale for controls whose complete value is metadata.
const metadata_control_max_bytes = 2 * 1024;
// OSC 52 is an unchunked clipboard protocol, so parser acceptance remains
// larger than metadata while host retention applies the same explicit bound.
const clipboard_control_max_bytes = 1024 * 1024;
// Kitty clipboard and file-transfer protocols send binary data in chunks no
// larger than 4096 decoded bytes. 8 KiB covers base64 expansion and command
// metadata without turning one protocol packet into a bulk-transfer buffer.
const chunk_control_max_bytes = 8 * 1024;

/// Maximum CSI or DCS parameters retained by one parser action.
pub const max_params = csi_max_params;
/// Maximum intermediate bytes retained by one parser action.
pub const max_intermediates = csi_max_intermediates;
/// Tracks colon separators across the bounded CSI parameter array.
pub const CsiSeparatorList = std.StaticBitSet(csi_max_params);
/// Maximum complete payload accepted for one ordinary metadata control.
pub const max_metadata_control_bytes = metadata_control_max_bytes;
/// Maximum complete payload accepted for one unchunked OSC 52 control.
const max_clipboard_control_bytes = clipboard_control_max_bytes;
/// Maximum complete payload accepted for one chunked Kitty control.
pub const max_chunk_control_bytes = chunk_control_max_bytes;

// Borrowed parser event vocabulary.

/// Identifies BEL or ST termination for a completed OSC action.
pub const OscTerminator = enum {
    bel,
    st,
};

/// Borrows one completed ESC final byte and bounded intermediates.
pub const EscAction = struct {
    final: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
};

const OscText = struct {
    payload: []const u8,
    term: OscTerminator,
};

const OscCommandText = struct {
    command: u16,
    payload: []const u8,
    term: OscTerminator,
};

/// Borrows one typed completed OSC payload until the parser advances.
pub const OscAction = union(enum) {
    raw_title: OscText,
    raw_other: OscText,
    title: OscCommandText,
    icon: OscText,
    palette_control: OscCommandText,
    palette_reset: OscCommandText,
    dynamic_color: OscCommandText,
    dynamic_reset: OscCommandText,
    report_pwd: OscText,
    hyperlink: OscText,
    notification: OscCommandText,
    pointer_shape: OscText,
    clipboard: OscCommandText,
    kitty_color: OscCommandText,
    kitty_text_size: OscText,
    kitty_drag_drop: OscText,
    shell_mark: OscText,
    rxvt_extension: OscText,
    iterm2: OscCommandText,
    context_signal: OscText,
    kitty_color_stack_push: OscTerminator,
    kitty_color_stack_pop: OscTerminator,
    kitty_file_transfer: OscText,
    kitty_clipboard: OscText,

    /// Returns the borrowed payload slice carried by any OSC action variant.
    pub fn payload(self: OscAction) []const u8 {
        return self.text().payload;
    }

    /// Returns the numeric OSC command when the variant has one.
    pub fn command(self: OscAction) ?u16 {
        return switch (self) {
            .raw_title, .raw_other => null,
            .title => |v| v.command,
            .icon => 1,
            .palette_control => |v| v.command,
            .palette_reset => |v| v.command,
            .dynamic_color => |v| v.command,
            .dynamic_reset => |v| v.command,
            .kitty_color => |v| v.command,
            .report_pwd => 7,
            .hyperlink => 8,
            .notification => |v| v.command,
            .pointer_shape => 22,
            .clipboard => |v| v.command,
            .kitty_text_size => 66,
            .kitty_drag_drop => 72,
            .shell_mark => 133,
            .rxvt_extension => 777,
            .iterm2 => |v| v.command,
            .context_signal => 3008,
            .kitty_color_stack_push => 30001,
            .kitty_color_stack_pop => 30101,
            .kitty_file_transfer => 5113,
            .kitty_clipboard => 5522,
        };
    }

    /// Returns the delimiter that completed this OSC action.
    pub fn term(self: OscAction) OscTerminator {
        return self.text().term;
    }

    fn text(self: OscAction) OscText {
        return switch (self) {
            .raw_title,
            .raw_other,
            .icon,
            .report_pwd,
            .hyperlink,
            .pointer_shape,
            .kitty_text_size,
            .kitty_drag_drop,
            .shell_mark,
            .rxvt_extension,
            .context_signal,
            .kitty_file_transfer,
            .kitty_clipboard,
            => |v| v,
            .title,
            .palette_control,
            .palette_reset,
            .dynamic_color,
            .dynamic_reset,
            .notification,
            .clipboard,
            .kitty_color,
            .iterm2,
            => |v| .{ .payload = v.payload, .term = v.term },
            .kitty_color_stack_push, .kitty_color_stack_pop => |delimiter| .{ .payload = "", .term = delimiter },
        };
    }
};

/// Borrows one DCS final byte, parameters, and bounded intermediates.
pub const DcsHook = struct {
    // Borrowed parser-owned slices. Callers that retain them past the next
    // `Parser.next` call must copy.
    final: u8,
    params: []const i32,
    count: u8,
    intermediates: []const u8,
    intermediates_len: u8,
};

/// Borrows one CSI final byte, bounded parameters, separators, and intermediates.
pub const CsiAction = struct {
    // Borrowed parser-owned slices. Callers that retain them past the next
    // `Parser.next` call must copy.
    final: u8,
    params: []const i32,
    separators: CsiSeparatorList,
    count: u8,
    leader: u8,
    private: bool,
    intermediates: []const u8,
    intermediates_len: u8,
};

/// Carries one ordered parser phase action with parser-borrowed slices.
pub const Action = union(enum) {
    print: u21,
    execute: u8,
    invalid,
    csi_dispatch: CsiAction,
    osc_dispatch: OscAction,
    screen_title: []const u8,
    apc_start,
    apc_put: u8,
    apc_end,
    apc_cancel,
    dcs_hook: DcsHook,
    dcs_put: u8,
    dcs_unhook,
    dcs_cancel,
    pm_start,
    pm_put: u8,
    pm_end,
    pm_cancel,
    sos_start,
    sos_put: u8,
    sos_end,
    sos_cancel,
    esc_dispatch: EscAction,
};

/// Preserves exit, transition, and entry action order for one input byte.
pub const PhaseActions = [3]?Action;

/// Stateful parser for terminal input streams.
pub const Parser = struct {
    /// Parser initialization can fail only while allocating its reusable string-control buffer.
    pub const InitError = error{OutOfMemory};

    utf8: Utf8Decoder,
    latin1: bool,
    state: ParseState,
    csi_params: [csi_max_params]i32,
    csi_separators: CsiSeparatorList,
    csi_count: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
    csi_in_param: bool,
    osc: OscControl,
    apc: PassthroughControl,
    dcs: PassthroughControl,
    pm: PassthroughControl,
    sos: PassthroughControl,

    /// Initialize parser state and its allocator-owned reusable string-control buffer.
    pub fn init(allocator: std.mem.Allocator) InitError!Parser {
        const osc = try OscControl.init(
            allocator,
            control_init_capacity,
            metadata_control_max_bytes,
            clipboard_control_max_bytes,
            chunk_control_max_bytes,
        );

        return .{
            .utf8 = .{},
            .latin1 = false,
            .state = .ground,
            .csi_params = [_]i32{0} ** csi_max_params,
            .csi_separators = CsiSeparatorList.initEmpty(),
            .csi_count = 0,
            .intermediates = [_]u8{0} ** csi_max_intermediates,
            .intermediates_len = 0,
            .csi_in_param = false,
            .osc = osc,
            .apc = PassthroughControl.init(false),
            .dcs = PassthroughControl.init(false),
            .pm = PassthroughControl.init(false),
            .sos = PassthroughControl.init(false),
        };
    }

    /// Release parser-owned buffers.
    pub fn deinit(self: *Parser) void {
        self.osc.deinit();
    }

    /// Reset parser state and transient buffers.
    pub fn reset(self: *Parser) void {
        self.utf8.reset();
        self.clear();
        self.state = .ground;
        self.osc.reset();
        self.apc.reset();
        self.dcs.reset();
        self.pm.reset();
        self.sos.reset();
    }

    /// Selects ISO-8859-1 graphic decoding or UTF-8 and clears partial text.
    ///
    /// C1 bytes remain terminal controls in both modes. The result reports an
    /// encoding or partial-decoder mutation.
    pub fn selectLatin1(self: *Parser, enabled: bool) bool {
        const changed = self.latin1 != enabled or self.utf8.needed != 0;
        self.utf8.reset();
        self.latin1 = enabled;
        return changed;
    }

    /// Restores UTF-8 decoding for terminal hard reset.
    pub fn resetTextEncoding(self: *Parser) void {
        self.utf8.reset();
        self.latin1 = false;
    }

    /// Returns and clears the pending buffered string-control allocation or bound failure.
    pub fn takeStringControlFailed(self: *Parser) ?error{ OutOfMemory, StringControlLimit } {
        if (self.osc.takeFailure()) |failure| return failure;
        return null;
    }

    /// Advance the parser by one byte and return ordered phase actions.
    pub fn next(self: *Parser, byte: u8) PhaseActions {
        std.debug.assert(self.activeControlCount() <= 1);
        if (self.state == .ground and self.utf8.needed > 0) {
            const action = self.consumeGroundByte(byte);
            return .{ null, action, null };
        }

        if (self.state == .escape and self.intermediates_len == 0 and byte == 'k') {
            self.osc.startScreenTitle();
            self.state = .screen_title_string;
            return .{ null, null, null };
        }

        const transition = table[byte][@intFromEnum(self.state)];
        if (self.isActiveState()) {
            return self.nextActive(byte, transition);
        }

        const transition_action = self.doAction(transition.action, byte);
        const next_state = transition.state;
        const current_state = self.state;
        defer self.state = next_state;

        return self.buildPhases(current_state, next_state, transition_action, byte, null);
    }

    fn nextActive(self: *Parser, byte: u8, transition: Transition) PhaseActions {
        const current_state = self.state;
        if (current_state == .screen_title_string) return self.nextScreenTitle(byte);
        const sos_kind = if (current_state == .sos_pm_apc_string) self.sosPmApcKind() else null;
        const finishing_escape = byte == '\\' and switch (current_state) {
            .osc_string => self.osc.escaping(),
            .dcs_passthrough => self.dcs.escaping(),
            .sos_pm_apc_string => switch (sos_kind.?) {
                .apc => self.apc.escaping(),
                .pm => self.pm.escaping(),
                .sos => self.sos.escaping(),
            },
            else => false,
        };

        if (byte != 0x1B and
            byte != 0x9C and
            !finishing_escape and
            (transition.state != current_state or transition.action != .none))
        {
            const transition_action = self.doAction(transition.action, byte);
            defer self.state = transition.state;
            return self.buildPhases(current_state, transition.state, transition_action, byte, null);
        }

        const next_state, const action = self.feedActiveByte(current_state, sos_kind, byte);
        defer self.state = next_state;
        return self.buildPhases(current_state, next_state, action, byte, sos_kind);
    }

    fn nextScreenTitle(self: *Parser, byte: u8) PhaseActions {
        const result = self.osc.feedScreenTitle(byte) orelse return .{ null, null, null };
        return switch (result) {
            .put => .{ null, null, null },
            .finish => finish: {
                self.state = .ground;
                break :finish .{ .{ .screen_title = self.osc.payload() }, null, null };
            },
        };
    }

    fn feedActiveByte(
        self: *Parser,
        current_state: ParseState,
        sos_kind: ?BufferedControlKind,
        byte: u8,
    ) struct { ParseState, ?Action } {
        return switch (current_state) {
            .osc_string => osc: {
                const result = self.osc.feed(byte) orelse break :osc .{ .osc_string, null };
                break :osc switch (result) {
                    .put => .{ .osc_string, null },
                    .finish => .{ .ground, null },
                };
            },
            .dcs_passthrough => dcs: {
                const result = self.dcs.feed(byte) orelse break :dcs .{ .dcs_passthrough, null };
                break :dcs switch (result) {
                    .put => |payload_byte| .{ .dcs_passthrough, .{ .dcs_put = payload_byte } },
                    .finish => .{ .ground, null },
                };
            },
            .sos_pm_apc_string => switch (sos_kind.?) {
                .apc => apc: {
                    const result = self.apc.feed(byte) orelse break :apc .{ .sos_pm_apc_string, null };
                    break :apc switch (result) {
                        .put => |payload_byte| .{ .sos_pm_apc_string, .{ .apc_put = payload_byte } },
                        .finish => .{ .ground, null },
                    };
                },
                .pm => pm: {
                    const result = self.pm.feed(byte) orelse break :pm .{ .sos_pm_apc_string, null };
                    break :pm switch (result) {
                        .put => |payload_byte| .{ .sos_pm_apc_string, .{ .pm_put = payload_byte } },
                        .finish => .{ .ground, null },
                    };
                },
                .sos => sos: {
                    const result = self.sos.feed(byte) orelse break :sos .{ .sos_pm_apc_string, null };
                    break :sos switch (result) {
                        .put => |payload_byte| .{ .sos_pm_apc_string, .{ .sos_put = payload_byte } },
                        .finish => .{ .ground, null },
                    };
                },
            },
            else => unreachable,
        };
    }

    fn collect(self: *Parser, byte: u8) void {
        if (self.intermediates_len >= self.intermediates.len) return;
        self.intermediates[self.intermediates_len] = byte;
        self.intermediates_len += 1;
    }

    fn buildPhases(
        self: *Parser,
        current_state: ParseState,
        next_state: ParseState,
        transition_action: ?Action,
        byte: u8,
        sos_kind: ?BufferedControlKind,
    ) PhaseActions {
        if (current_state == next_state) {
            return .{ null, transition_action, null };
        }

        return .{
            self.exitPhase(current_state, byte, sos_kind),
            transition_action,
            self.entryPhase(next_state, byte),
        };
    }

    fn exitPhase(self: *Parser, state: ParseState, byte: u8, sos_kind: ?BufferedControlKind) ?Action {
        return switch (state) {
            .osc_string => exit: {
                const term = switch (byte) {
                    0x07 => OscTerminator.bel,
                    '\\', 0x9C => OscTerminator.st,
                    else => {
                        self.osc.reset();
                        break :exit null;
                    },
                };
                break :exit .{ .osc_dispatch = self.osc.snapshot(term) };
            },
            .dcs_passthrough => dcs: {
                self.dcs.reset();
                std.debug.assert(!self.dcs.active());
                break :dcs if (stringControlCompleted(byte)) .dcs_unhook else .dcs_cancel;
            },
            .sos_pm_apc_string => switch (sos_kind orelse self.sosPmApcKind()) {
                .apc => apc: {
                    self.apc.reset();
                    std.debug.assert(!self.apc.active());
                    break :apc if (stringControlCompleted(byte)) .apc_end else .apc_cancel;
                },
                .pm => pm: {
                    self.pm.reset();
                    std.debug.assert(!self.pm.active());
                    break :pm if (stringControlCompleted(byte)) .pm_end else .pm_cancel;
                },
                .sos => sos: {
                    self.sos.reset();
                    std.debug.assert(!self.sos.active());
                    break :sos if (stringControlCompleted(byte)) .sos_end else .sos_cancel;
                },
            },
            else => null,
        };
    }

    fn entryPhase(self: *Parser, state: ParseState, byte: u8) ?Action {
        return switch (state) {
            .escape, .csi_entry, .dcs_entry => entry: {
                if (state == .escape) {
                    std.debug.assert(self.activeControlCount() <= 1);
                    self.utf8.reset();
                    self.osc.reset();
                    self.apc.reset();
                    self.dcs.reset();
                    self.pm.reset();
                    self.sos.reset();
                    self.clear();
                    std.debug.assert(self.activeControlCount() == 0);
                } else {
                    self.clear();
                }
                break :entry null;
            },
            .osc_string => entry: {
                std.debug.assert(self.activeControlCount() == 0);
                self.osc.start();
                std.debug.assert(self.osc.active());
                std.debug.assert(self.activeControlCount() == 1);
                break :entry null;
            },
            .dcs_passthrough => entry: {
                std.debug.assert(self.activeControlCount() == 0);
                self.dcs.start();
                std.debug.assert(self.dcs.active());
                std.debug.assert(self.activeControlCount() == 1);
                break :entry self.dcsHook(byte);
            },
            .sos_pm_apc_string => switch (byte) {
                '_', 0x9F => apc: {
                    std.debug.assert(self.activeControlCount() == 0);
                    self.apc.start();
                    std.debug.assert(self.apc.active());
                    std.debug.assert(self.activeControlCount() == 1);
                    break :apc .apc_start;
                },
                '^', 0x9E => pm: {
                    std.debug.assert(self.activeControlCount() == 0);
                    self.pm.start();
                    std.debug.assert(self.pm.active());
                    std.debug.assert(self.activeControlCount() == 1);
                    break :pm .pm_start;
                },
                'X', 0x98 => sos: {
                    std.debug.assert(self.activeControlCount() == 0);
                    self.sos.start();
                    std.debug.assert(self.sos.active());
                    std.debug.assert(self.activeControlCount() == 1);
                    break :sos .sos_start;
                },
                else => unreachable,
            },
            else => null,
        };
    }

    fn dcsHook(self: *Parser, byte: u8) Action {
        var final_count = self.csi_count;
        if (self.csi_in_param) final_count += 1;
        const hook = DcsHook{
            .final = byte,
            .params = self.csi_params[0..final_count],
            .count = final_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        };
        return .{ .dcs_hook = hook };
    }

    fn doAction(self: *Parser, action: TransitionAction, byte: u8) ?Action {
        return switch (action) {
            .none => null,
            .print => .{ .print = byte },
            .ground => ground: {
                if (self.consumeGroundByte(byte)) |action_result| break :ground action_result;
                break :ground null;
            },
            .execute => .{ .execute = byte },
            .collect => collect: {
                self.collect(byte);
                break :collect null;
            },
            .ignore => null,
            .esc_dispatch => esc_dispatch: {
                const esc: Action = .{ .esc_dispatch = .{
                    .final = byte,
                    .intermediates = self.intermediates,
                    .intermediates_len = self.intermediates_len,
                } };
                self.clear();
                break :esc_dispatch esc;
            },
            .csi_dispatch => self.consumeCsiDispatch(byte),
            .osc_put => osc_put: {
                const result = self.osc.feed(byte) orelse unreachable;
                switch (result) {
                    .put => {},
                    .finish => unreachable,
                }
                break :osc_put null;
            },
            .put => put: {
                const result = self.dcs.feed(byte) orelse break :put null;
                break :put switch (result) {
                    .put => |payload_byte| .{ .dcs_put = payload_byte },
                    .finish => unreachable,
                };
            },
            .apc_put => apc_put: {
                break :apc_put switch (self.sosPmApcKind()) {
                    .apc => apc: {
                        const result = self.apc.feed(byte) orelse break :apc null;
                        break :apc switch (result) {
                            .put => |payload_byte| .{ .apc_put = payload_byte },
                            .finish => unreachable,
                        };
                    },
                    .pm => pm: {
                        const result = self.pm.feed(byte) orelse break :pm null;
                        break :pm switch (result) {
                            .put => |payload_byte| .{ .pm_put = payload_byte },
                            .finish => unreachable,
                        };
                    },
                    .sos => sos: {
                        const result = self.sos.feed(byte) orelse break :sos null;
                        break :sos switch (result) {
                            .put => |payload_byte| .{ .sos_put = payload_byte },
                            .finish => unreachable,
                        };
                    },
                };
            },
            .param => switch (self.state) {
                .csi_entry, .csi_param => csi: {
                    self.feedParamByte(.csi, byte);
                    break :csi null;
                },
                .dcs_entry, .dcs_param => dcs: {
                    self.feedParamByte(.dcs, byte);
                    break :dcs null;
                },
                else => unreachable,
            },
        };
    }

    fn isActiveState(self: *const Parser) bool {
        return switch (self.state) {
            .osc_string, .screen_title_string, .dcs_passthrough, .sos_pm_apc_string => true,
            else => false,
        };
    }

    fn sosPmApcKind(self: *const Parser) BufferedControlKind {
        if (self.apc.active()) {
            std.debug.assert(!self.pm.active());
            std.debug.assert(!self.sos.active());
            return .apc;
        }

        if (self.pm.active()) {
            std.debug.assert(!self.sos.active());
            return .pm;
        }

        std.debug.assert(self.sos.active());
        return .sos;
    }

    fn activeControlCount(self: *const Parser) u3 {
        var count: u3 = 0;
        if (self.osc.active()) count += 1;
        if (self.apc.active()) count += 1;
        if (self.dcs.active()) count += 1;
        if (self.pm.active()) count += 1;
        if (self.sos.active()) count += 1;
        return count;
    }

    fn clear(self: *Parser) void {
        self.csi_params[0] = 0;
        self.csi_count = 0;
        self.csi_separators = CsiSeparatorList.initEmpty();
        self.intermediates_len = 0;
        self.csi_in_param = false;
    }

    fn consumeGroundByte(self: *Parser, byte: u8) ?Action {
        if (self.latin1) {
            std.debug.assert(byte >= 0xA0);
            return .{ .print = @intCast(byte) };
        }
        return switch (self.utf8.feed(byte)) {
            .codepoint => |cp| .{ .print = cp },
            .invalid => .invalid,
            .incomplete => null,
        };
    }

    fn feedParamByte(self: *Parser, comptime kind: ParamKind, byte: u8) void {
        if (byte == ';' or byte == ':') {
            if (self.csi_count < self.csi_params.len) {
                if (kind == .csi and byte == ':') self.csi_separators.set(self.csi_count);
                self.csi_count += 1;
                if (self.csi_count < self.csi_params.len) {
                    self.csi_params[self.csi_count] = 0;
                }
            }
            self.csi_in_param = false;
            return;
        }

        if (byte >= '0' and byte <= '9') {
            const digit: i32 = @intCast(byte - '0');
            if (self.csi_count >= self.csi_params.len) return;
            if (!self.csi_in_param) {
                self.csi_params[self.csi_count] = digit;
                self.csi_in_param = true;
            } else {
                self.csi_params[self.csi_count] = self.csi_params[self.csi_count] * 10 + digit;
            }
            return;
        }
    }

    fn consumeCsiDispatch(self: *Parser, byte: u8) ?Action {
        std.debug.assert(byte >= 0x40);
        std.debug.assert(byte <= 0x7E);

        var leader: u8 = 0;
        var private = false;
        var intermediate_start: u8 = 0;
        if (self.intermediates_len > 0) {
            switch (self.intermediates[0]) {
                '<', '>', '=', '?' => {
                    leader = self.intermediates[0];
                    private = leader == '?';
                    intermediate_start = 1;
                },
                else => {},
            }
        }

        var final_count = self.csi_count;
        if (self.csi_in_param) final_count += 1;
        const intermediates_len = self.intermediates_len - intermediate_start;
        const action = CsiAction{
            .final = byte,
            .params = self.csi_params[0..final_count],
            .separators = self.csi_separators,
            .count = final_count,
            .leader = leader,
            .private = private,
            .intermediates = self.intermediates[intermediate_start .. intermediate_start + intermediates_len],
            .intermediates_len = intermediates_len,
        };
        return .{ .csi_dispatch = action };
    }
};

fn stringControlCompleted(byte: u8) bool {
    return byte == '\\' or byte == 0x9C;
}

fn expectPhaseTags(
    phases: PhaseActions,
    exit_tag: ?std.meta.Tag(Action),
    transition_tag: ?std.meta.Tag(Action),
    entry_tag: ?std.meta.Tag(Action),
) !void {
    const expected = [_]?std.meta.Tag(Action){ exit_tag, transition_tag, entry_tag };
    for (phases, expected) |phase, maybe_tag| {
        if (maybe_tag) |tag| {
            try std.testing.expect(phase != null);
            try std.testing.expectEqual(tag, std.meta.activeTag(phase.?));
        } else {
            try std.testing.expectEqual(@as(?Action, null), phase);
        }
    }
}

test "parser control spine orders populated phase slots in one next call" {
    var parser = try Parser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.next(0x1B);
    _ = parser.next('P');
    _ = parser.next('1');
    _ = parser.next(';');
    _ = parser.next('2');

    const hook = parser.next('q');
    try expectPhaseTags(hook, null, null, .dcs_hook);
    try std.testing.expectEqual(ParseState.dcs_passthrough, parser.state);

    const apc_start = parser.next(0x9F);
    try expectPhaseTags(apc_start, .dcs_cancel, null, .apc_start);
    try std.testing.expectEqual(ParseState.sos_pm_apc_string, parser.state);
    try std.testing.expectEqual(@as(u3, 1), parser.activeControlCount());
    try std.testing.expect(parser.apc.active());
    try std.testing.expect(!parser.dcs.active());
}

test "parser initialization reports only allocation failure" {
    const init: *const fn (std.mem.Allocator) Parser.InitError!Parser = Parser.init;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator()));
    try std.testing.expect(failing.has_induced_failure);
}

test "parser keeps active string controls exclusive" {
    var parser = try Parser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.next(0x1B);
    _ = parser.next(']');
    try std.testing.expectEqual(@as(u3, 1), parser.activeControlCount());
    try std.testing.expect(parser.osc.active());
    try std.testing.expect(!parser.apc.active());
    try std.testing.expect(!parser.dcs.active());
    try std.testing.expect(!parser.pm.active());

    parser.state = .escape;
    _ = parser.entryPhase(.escape, 0x1B);
    try std.testing.expectEqual(@as(u3, 0), parser.activeControlCount());
    try std.testing.expect(!parser.osc.active());
    try std.testing.expect(!parser.apc.active());
    try std.testing.expect(!parser.dcs.active());
    try std.testing.expect(!parser.pm.active());

    parser.reset();
    _ = parser.next(0x1B);
    _ = parser.next('_');
    try std.testing.expectEqual(@as(u3, 1), parser.activeControlCount());
    try std.testing.expect(!parser.osc.active());
    try std.testing.expect(parser.apc.active());
    try std.testing.expect(!parser.dcs.active());
    try std.testing.expect(!parser.pm.active());
}

test "parser assembles CSI params and separators" {
    var parser = try Parser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.next(0x1B);
    _ = parser.next('[');
    _ = parser.next('1');
    _ = parser.next(':');
    _ = parser.next('2');
    _ = parser.next(';');
    _ = parser.next('3');

    const phases = parser.next('m');
    try expectPhaseTags(phases, null, .csi_dispatch, null);

    const csi = phases[1].?.csi_dispatch;
    try std.testing.expectEqual(@as(u8, 'm'), csi.final);
    try std.testing.expectEqual(@as(u8, 3), csi.count);
    try std.testing.expectEqual(@as(usize, 3), csi.params.len);
    try std.testing.expectEqual(@as(i32, 1), csi.params[0]);
    try std.testing.expectEqual(@as(i32, 2), csi.params[1]);
    try std.testing.expectEqual(@as(i32, 3), csi.params[2]);
    try std.testing.expect(csi.separators.isSet(0));
    try std.testing.expect(!csi.separators.isSet(1));
    try std.testing.expect(!csi.separators.isSet(2));
}

test "parser DCS hook stays on the hook boundary" {
    var parser = try Parser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.next(0x1B);
    _ = parser.next('P');
    _ = parser.next('1');
    _ = parser.next('$');

    const hook_phases = parser.next('q');
    try expectPhaseTags(hook_phases, null, null, .dcs_hook);

    const hook = hook_phases[2].?.dcs_hook;
    try std.testing.expectEqual(@as(u8, 'q'), hook.final);
    try std.testing.expectEqual(@as(u8, 1), hook.count);
    try std.testing.expectEqual(@as(usize, 1), hook.params.len);
    try std.testing.expectEqual(@as(i32, 1), hook.params[0]);
    try std.testing.expectEqual(@as(u8, 1), hook.intermediates_len);
    try std.testing.expectEqual(@as(usize, 1), hook.intermediates.len);
    try std.testing.expectEqual(@as(u8, '$'), hook.intermediates[0]);

    const put = parser.next('x');
    try expectPhaseTags(put, null, .dcs_put, null);
    try std.testing.expectEqual(@as(u8, 'x'), put[1].?.dcs_put);

    _ = parser.next(0x1B);
    const unhook = parser.next('\\');
    try expectPhaseTags(unhook, .dcs_unhook, null, null);
}

// Borrows one completed CSI rendition action.
const StyleChange = struct {
    final: u8,
    params: []const i32,
    separators: CsiSeparatorList,
    param_count: u8,
    leader: u8,
    private: bool,
    intermediates: []const u8,
    intermediates_len: u8,
};

const DcsEvent = struct {
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediates: []const u8,
    intermediates_len: u8,
};

/// Carries one parser event with slices borrowed until the next parser advance.
pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    invoke_charset: u8,
    configure_charset: struct { slot: u8, designation: u8 },
    style_change: StyleChange,
    osc: OscAction,
    screen_title: []const u8,
    apc: []const u8,
    dcs: DcsEvent,
    pm: []const u8,
    esc_dispatch: EscAction,
    invalid_sequence,
};

// Generated ECMA-48 byte-state transition table.

// Names every state in the generated VT parser automaton.
const ParseState = enum {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_param,
    csi_intermediate,
    csi_ignore,
    osc_string,
    screen_title_string,
    dcs_entry,
    dcs_param,
    dcs_intermediate,
    dcs_ignore,
    dcs_passthrough,
    sos_pm_apc_string,
};

// Names the byte action performed while crossing a parser parseTransition.
const TransitionAction = enum {
    none,
    print,
    ground,
    execute,
    collect,
    ignore,
    esc_dispatch,
    csi_dispatch,
    osc_put,
    put,
    apc_put,
    param,
};

// Pairs the next parser state with its parseTransition action.
const Transition = struct {
    state: ParseState,
    action: TransitionAction,
};

// Provides the compile-time-complete byte-by-state parseTransition table.
const table = genTable();

const Table = genTableType(false);
const OptionalTable = genTableType(true);

fn genTableType(comptime optional: bool) type {
    const max_u8 = std.math.maxInt(u8);
    const state_info = @typeInfo(ParseState);
    const max_state = state_info.@"enum".fields.len;
    const Elem = if (optional) ?Transition else Transition;
    return [max_u8 + 1][max_state]Elem;
}

fn genTable() Table {
    @setEvalBranchQuota(20000);

    var result: OptionalTable = undefined;
    initEmpty(&result);
    fillAnywhere(&result);
    fillGround(&result);
    fillEscapeIntermediate(&result);
    fillSosPmApcString(&result);
    fillEscape(&result);
    fillDcsEntry(&result);
    fillDcsIntermediate(&result);
    fillDcsIgnore(&result);
    fillDcsParam(&result);
    fillDcsPassthrough(&result);
    fillCsiParam(&result);
    fillCsiIgnore(&result);
    fillCsiIntermediate(&result);
    fillCsiEntry(&result);
    fillOscString(&result);
    return finalizeTable(result);
}

fn initEmpty(result: *OptionalTable) void {
    for (0..result.len) |i| {
        for (0..result[0].len) |j| {
            result[i][j] = null;
        }
    }
}

fn fillAnywhere(result: *OptionalTable) void {
    const state_info = @typeInfo(ParseState);
    inline for (state_info.@"enum".fields) |field| {
        const source: ParseState = @enumFromInt(field.value);
        single(result, 0x18, source, .ground, .execute);
        single(result, 0x1A, source, .ground, .execute);
        range(result, 0x80, 0x8F, source, .ground, .execute);
        range(result, 0x91, 0x97, source, .ground, .execute);
        single(result, 0x99, source, .ground, .execute);
        single(result, 0x9A, source, .ground, .execute);
        single(result, 0x9C, source, .ground, .none);

        single(result, 0x1B, source, .escape, .none);

        single(result, 0x98, source, .sos_pm_apc_string, .none);
        single(result, 0x9E, source, .sos_pm_apc_string, .none);
        single(result, 0x9F, source, .sos_pm_apc_string, .none);

        single(result, 0x9B, source, .csi_entry, .none);
        single(result, 0x90, source, .dcs_entry, .none);
        single(result, 0x9D, source, .osc_string, .none);
    }
}

fn fillGround(result: *OptionalTable) void {
    range(result, 0x00, 0x17, .ground, .ground, .execute);
    single(result, 0x19, .ground, .ground, .execute);
    range(result, 0x1C, 0x1F, .ground, .ground, .execute);
    range(result, 0x20, 0x7F, .ground, .ground, .print);
    // An incomplete UTF-8 sequence consumes continuation bytes before table
    // lookup. Standalone C1 bytes therefore retain their anywhere transitions,
    // while non-C1 high bytes still enter the UTF-8 decoder.
    range(result, 0xA0, 0xFF, .ground, .ground, .ground);
}

fn fillEscapeIntermediate(result: *OptionalTable) void {
    const source = ParseState.escape_intermediate;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    range(result, 0x20, 0x2F, source, source, .collect);
    single(result, 0x7F, source, source, .ignore);
    range(result, 0x30, 0x7E, source, .ground, .esc_dispatch);
}

fn fillSosPmApcString(result: *OptionalTable) void {
    const source = ParseState.sos_pm_apc_string;
    range(result, 0x00, 0x17, source, source, .apc_put);
    single(result, 0x19, source, source, .apc_put);
    range(result, 0x1C, 0x1F, source, source, .apc_put);
    range(result, 0x20, 0x7F, source, source, .apc_put);
}

fn fillEscape(result: *OptionalTable) void {
    const source = ParseState.escape;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x30, 0x4F, source, .ground, .esc_dispatch);
    range(result, 0x51, 0x57, source, .ground, .esc_dispatch);
    single(result, 0x59, source, .ground, .esc_dispatch);
    single(result, 0x5A, source, .ground, .esc_dispatch);
    single(result, 0x5C, source, .ground, .esc_dispatch);
    range(result, 0x60, 0x7E, source, .ground, .esc_dispatch);

    range(result, 0x20, 0x2F, source, .escape_intermediate, .collect);

    single(result, 0x50, source, .dcs_entry, .none);
    single(result, 0x58, source, .sos_pm_apc_string, .none);
    single(result, 0x5B, source, .csi_entry, .none);
    single(result, 0x5D, source, .osc_string, .none);
    single(result, 0x5E, source, .sos_pm_apc_string, .none);
    single(result, 0x5F, source, .sos_pm_apc_string, .none);
}

fn fillDcsEntry(result: *OptionalTable) void {
    const source = ParseState.dcs_entry;
    range(result, 0x00, 0x17, source, source, .ignore);
    single(result, 0x19, source, source, .ignore);
    range(result, 0x1C, 0x1F, source, source, .ignore);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x20, 0x2F, source, .dcs_intermediate, .collect);
    single(result, 0x3A, source, .dcs_ignore, .none);
    range(result, 0x30, 0x39, source, .dcs_param, .param);
    single(result, 0x3B, source, .dcs_param, .param);
    range(result, 0x3C, 0x3F, source, .dcs_param, .collect);
    range(result, 0x40, 0x7E, source, .dcs_passthrough, .none);
}

fn fillDcsIntermediate(result: *OptionalTable) void {
    const source = ParseState.dcs_intermediate;
    range(result, 0x00, 0x17, source, source, .ignore);
    single(result, 0x19, source, source, .ignore);
    range(result, 0x1C, 0x1F, source, source, .ignore);
    range(result, 0x20, 0x2F, source, source, .collect);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x30, 0x3F, source, .dcs_ignore, .none);
    range(result, 0x40, 0x7E, source, .dcs_passthrough, .none);
}

fn fillDcsIgnore(result: *OptionalTable) void {
    const source = ParseState.dcs_ignore;
    range(result, 0x00, 0x17, source, source, .ignore);
    single(result, 0x19, source, source, .ignore);
    range(result, 0x1C, 0x1F, source, source, .ignore);
    range(result, 0x20, 0x3F, source, source, .ignore);
    range(result, 0x40, 0x7E, source, .ground, .none);
}

fn fillDcsParam(result: *OptionalTable) void {
    const source = ParseState.dcs_param;
    range(result, 0x00, 0x17, source, source, .ignore);
    single(result, 0x19, source, source, .ignore);
    range(result, 0x1C, 0x1F, source, source, .ignore);
    range(result, 0x30, 0x39, source, source, .param);
    single(result, 0x3B, source, source, .param);
    single(result, 0x7F, source, source, .ignore);

    single(result, 0x3A, source, .dcs_ignore, .none);
    range(result, 0x3C, 0x3F, source, .dcs_ignore, .none);
    range(result, 0x20, 0x2F, source, .dcs_intermediate, .collect);
    range(result, 0x40, 0x7E, source, .dcs_passthrough, .none);
}

fn fillDcsPassthrough(result: *OptionalTable) void {
    const source = ParseState.dcs_passthrough;
    range(result, 0x00, 0x17, source, source, .put);
    single(result, 0x19, source, source, .put);
    range(result, 0x1C, 0x1F, source, source, .put);
    range(result, 0x20, 0x7E, source, source, .put);
    single(result, 0x7F, source, source, .ignore);
}

fn fillCsiParam(result: *OptionalTable) void {
    const source = ParseState.csi_param;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    range(result, 0x30, 0x39, source, source, .param);
    single(result, 0x3A, source, source, .param);
    single(result, 0x3B, source, source, .param);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x40, 0x7E, source, .ground, .csi_dispatch);
    range(result, 0x3C, 0x3F, source, .csi_ignore, .none);
    range(result, 0x20, 0x2F, source, .csi_intermediate, .collect);
}

fn fillCsiIgnore(result: *OptionalTable) void {
    const source = ParseState.csi_ignore;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    range(result, 0x20, 0x3F, source, source, .ignore);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x40, 0x7E, source, .ground, .none);
}

fn fillCsiIntermediate(result: *OptionalTable) void {
    const source = ParseState.csi_intermediate;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    range(result, 0x20, 0x2F, source, source, .collect);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x40, 0x7E, source, .ground, .csi_dispatch);
    range(result, 0x30, 0x3F, source, .csi_ignore, .none);
}

fn fillCsiEntry(result: *OptionalTable) void {
    const source = ParseState.csi_entry;
    range(result, 0x00, 0x17, source, source, .execute);
    single(result, 0x19, source, source, .execute);
    range(result, 0x1C, 0x1F, source, source, .execute);
    single(result, 0x7F, source, source, .ignore);

    range(result, 0x40, 0x7E, source, .ground, .csi_dispatch);
    single(result, 0x3A, source, .csi_ignore, .none);
    range(result, 0x20, 0x2F, source, .csi_intermediate, .collect);
    range(result, 0x30, 0x39, source, .csi_param, .param);
    single(result, 0x3B, source, .csi_param, .param);
    range(result, 0x3C, 0x3F, source, .csi_param, .collect);
}

fn fillOscString(result: *OptionalTable) void {
    const source = ParseState.osc_string;
    range(result, 0x00, 0x06, source, source, .ignore);
    range(result, 0x08, 0x17, source, source, .ignore);
    single(result, 0x19, source, source, .ignore);
    range(result, 0x1C, 0x1F, source, source, .ignore);
    single(result, 0x07, source, source, .none);
    range(result, 0x20, 0xFF, source, source, .osc_put);
}

fn finalizeTable(result: OptionalTable) Table {
    var final: Table = undefined;
    for (0..final.len) |i| {
        for (0..final[0].len) |j| {
            final[i][j] = result[i][j] orelse parseTransition(@enumFromInt(j), .none);
        }
    }
    return final;
}

fn single(t: *OptionalTable, c: u8, s0: ParseState, s1: ParseState, a: TransitionAction) void {
    t[c][@intFromEnum(s0)] = parseTransition(s1, a);
}

fn range(t: *OptionalTable, from: u8, to: u8, s0: ParseState, s1: ParseState, a: TransitionAction) void {
    var i = from;
    while (i <= to) : (i += 1) {
        single(t, i, s0, s1, a);
        if (i == to) break;
    }
}

fn parseTransition(state: ParseState, action: TransitionAction) Transition {
    return .{ .state = state, .action = action };
}

// Bounded OSC and generic string-control owners.

const ByteLimit = u32;

/// String-control terminator.
pub const Finish = enum {
    bel,
    st,
    cr,
    lf,
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

/// Owns bounded OSC parsing and lends its mutually exclusive payload allocation to ESC k titles.
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
        kitty_drag_drop,
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
        screen_title,
        screen_title_esc,
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
        c72,
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

    // Begins GNU Screen's ESC k title control using the ordinary metadata bound.
    fn startScreenTitle(self: *OscControl) void {
        self.reset();
        self.policy = .{ .command = null, .class = .raw_title, .max_len = self.metadata_max_len };
        self.state = .screen_title;
    }

    /// Reports whether an OSC delimiter has started and not finished.
    pub fn active(self: *const OscControl) bool {
        return self.state != .idle;
    }

    /// Reports whether a buffered control consumed ESC while awaiting ST or payload continuation.
    pub fn escaping(self: *const OscControl) bool {
        return switch (self.state) {
            .prefix_esc, .payload_esc, .raw_esc, .screen_title_esc => true,
            else => false,
        };
    }

    fn payload(self: *const OscControl) []const u8 {
        return self.buffer.items;
    }

    /// Borrows the completed OSC action until reset, start, feed, or deinit.
    pub fn snapshot(self: *const OscControl, term: OscTerminator) OscAction {
        return switch (self.policy.class) {
            .raw_title => .{ .raw_title = .{ .payload = self.buffer.items, .term = term } },
            .raw_other => .{ .raw_other = .{ .payload = self.buffer.items, .term = term } },
            .title => .{ .title = .{ .command = self.policy.command.?, .payload = self.buffer.items, .term = term } },
            .icon => .{ .icon = .{ .payload = self.buffer.items, .term = term } },
            .palette_control => .{ .palette_control = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .palette_reset => .{ .palette_reset = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .dynamic_color => .{ .dynamic_color = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .dynamic_reset => .{ .dynamic_reset = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .report_pwd => .{ .report_pwd = .{ .payload = self.buffer.items, .term = term } },
            .hyperlink => .{ .hyperlink = .{ .payload = self.buffer.items, .term = term } },
            .notification => .{ .notification = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .pointer_shape => .{ .pointer_shape = .{ .payload = self.buffer.items, .term = term } },
            .clipboard => .{ .clipboard = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .kitty_color => .{ .kitty_color = .{
                .command = self.policy.command.?,
                .payload = self.buffer.items,
                .term = term,
            } },
            .kitty_text_size => .{ .kitty_text_size = .{ .payload = self.buffer.items, .term = term } },
            .kitty_drag_drop => .{ .kitty_drag_drop = .{ .payload = self.buffer.items, .term = term } },
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
            .screen_title, .screen_title_esc => unreachable,
        };
    }

    // Screen titles end at CR, LF, C1 ST, or ESC ST; any other ESC remains payload.
    fn feedScreenTitle(self: *OscControl, byte: u8) ?FeedResult {
        return switch (self.state) {
            .screen_title => switch (byte) {
                '\r' => self.finishScreenTitle(.cr),
                '\n' => self.finishScreenTitle(.lf),
                0x9C => self.finishScreenTitle(.st),
                0x1B => title_escape: {
                    self.state = .screen_title_esc;
                    break :title_escape null;
                },
                else => title_put: {
                    self.append(byte);
                    break :title_put .{ .put = byte };
                },
            },
            .screen_title_esc => if (byte == '\\')
                self.finishScreenTitle(.st)
            else title_continue: {
                self.state = .screen_title;
                self.append(0x1B);
                if (byte == '\r') break :title_continue self.finishScreenTitle(.cr);
                if (byte == '\n') break :title_continue self.finishScreenTitle(.lf);
                if (byte == 0x9C) break :title_continue self.finishScreenTitle(.st);
                if (byte == 0x1B) {
                    self.state = .screen_title_esc;
                    break :title_continue null;
                }
                self.append(byte);
                break :title_continue .{ .put = byte };
            },
            else => unreachable,
        };
    }

    fn finishScreenTitle(self: *OscControl, terminator: Finish) FeedResult {
        self.state = .idle;
        return .{ .finish = terminator };
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
            '2' => .c72,
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
            .c4, .c5 => |state| .{
                .command = if (state == .c4) 4 else 5,
                .class = .palette_control,
                .max_len = self.metadata_max_len,
            },
            .c7 => .{ .command = 7, .class = .report_pwd, .max_len = self.metadata_max_len },
            .c8 => .{ .command = 8, .class = .hyperlink, .max_len = self.metadata_max_len },
            .c9, .c99 => |state| .{
                .command = if (state == .c9) 9 else 99,
                .class = .notification,
                .max_len = self.metadata_max_len,
            },
            .c10, .c11, .c12, .c13, .c14, .c15, .c16, .c17, .c18, .c19 => .{
                .command = prefixDynamicCommand(self.prefix),
                .class = .dynamic_color,
                .max_len = self.metadata_max_len,
            },
            .c21 => .{ .command = 21, .class = .kitty_color, .max_len = self.metadata_max_len },
            .c22 => .{ .command = 22, .class = .pointer_shape, .max_len = self.metadata_max_len },
            .c50 => .{ .command = 50, .class = .iterm2, .max_len = self.metadata_max_len },
            .c52 => .{ .command = 52, .class = .clipboard, .max_len = self.clipboard_max_len },
            .c66 => .{ .command = 66, .class = .kitty_text_size, .max_len = self.chunk_max_len },
            .c72 => .{ .command = 72, .class = .kitty_drag_drop, .max_len = self.chunk_max_len },
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

// Incremental string-control parser state without payload ownership.
const PassthroughControl = struct {
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

// Incremental text decoding.

/// UTF-8 decode result union.
const Utf8Result = union(enum) {
    codepoint: u21,
    incomplete,
    invalid,
};

// Incremental UTF-8 decoder state.
const Utf8Decoder = struct {
    buf: [4]u8 = undefined,
    len: u8 = 0,
    needed: u8 = 0,

    /// Reset decoder state.
    pub fn reset(self: *Utf8Decoder) void {
        self.len = 0;
        self.needed = 0;
    }

    /// Feed one byte and return decode state.
    pub fn feed(self: *Utf8Decoder, byte: u8) Utf8Result {
        if (self.needed == 0) {
            if (byte < 0x80) {
                return .{ .codepoint = @intCast(byte) };
            }
            const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch return .invalid;
            std.debug.assert(seq_len > 1);
            self.buf[0] = byte;
            self.len = 1;
            self.needed = @intCast(seq_len);
            return .incomplete;
        }

        // Continuation byte required while sequence is incomplete.
        if ((byte & 0xC0) != 0x80) {
            self.reset();
            return .invalid;
        }
        self.buf[self.len] = byte;
        self.len += 1;

        if (self.len < self.needed) return .incomplete;

        const cp = std.unicode.utf8Decode(self.buf[0..self.needed]) catch {
            self.reset();
            return .invalid;
        };
        self.reset();
        return .{ .codepoint = cp };
    }
};

test "UTF8 decoder: ASCII passthrough" {
    var decoder = Utf8Decoder{};
    const result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: multi-byte sequence (€ = U+20AC)" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0xE2);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0x82);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0xAC);
    try std.testing.expectEqual(@as(u21, 0x20AC), result.codepoint);
}

test "UTF8 decoder: invalid start leaves decoder clear" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0x80);
    try std.testing.expect(result == .invalid);
    result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: invalid continuation resets partial sequence" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0xE2);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed('A');
    try std.testing.expect(result == .invalid);
    result = decoder.feed('B');
    try std.testing.expectEqual(@as(u21, 'B'), result.codepoint);
}

// Transactional event copying for simulation and fuzz ownership.

/// Copies borrowed parser phase actions into arena-backed storage transactionally.
pub fn appendOwnedPhases(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(Action),
    phases: PhaseActions,
) error{OutOfMemory}!void {
    for (phases) |phase| {
        if (phase) |action| try appendOwnedAction(allocator, arena, actions, action);
    }
}

fn appendOwnedAction(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(Action),
    action: Action,
) error{OutOfMemory}!void {
    switch (action) {
        .csi_dispatch => |csi| {
            const params = try dupeArenaSlice(arena, i32, csi.params[0..csi.count]);
            const intermediates = try dupeArenaSlice(arena, u8, csi.intermediates[0..csi.intermediates_len]);
            try actions.append(allocator, .{ .csi_dispatch = .{
                .final = csi.final,
                .params = params,
                .separators = csi.separators,
                .count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = intermediates,
                .intermediates_len = csi.intermediates_len,
            } });
        },
        .dcs_hook => |hook| {
            const params = try dupeArenaSlice(arena, i32, hook.params[0..hook.count]);
            const intermediates = try dupeArenaSlice(arena, u8, hook.intermediates[0..hook.intermediates_len]);
            try actions.append(allocator, .{ .dcs_hook = .{
                .final = hook.final,
                .params = params,
                .count = hook.count,
                .intermediates = intermediates,
                .intermediates_len = hook.intermediates_len,
            } });
        },
        .osc_dispatch => |osc| {
            const owned = try arena.dupe(u8, osc.payload());
            try actions.append(allocator, .{ .osc_dispatch = switch (osc) {
                .raw_title => .{ .raw_title = .{ .payload = owned, .term = osc.term() } },
                .raw_other => .{ .raw_other = .{ .payload = owned, .term = osc.term() } },
                .title => |v| .{ .title = .{ .command = v.command, .payload = owned, .term = v.term } },
                .icon => .{ .icon = .{ .payload = owned, .term = osc.term() } },
                .palette_control => |v| .{ .palette_control = .{
                    .command = v.command,
                    .payload = owned,
                    .term = v.term,
                } },
                .palette_reset => |v| .{ .palette_reset = .{ .command = v.command, .payload = owned, .term = v.term } },
                .dynamic_color => |v| .{ .dynamic_color = .{ .command = v.command, .payload = owned, .term = v.term } },
                .dynamic_reset => |v| .{ .dynamic_reset = .{ .command = v.command, .payload = owned, .term = v.term } },
                .report_pwd => .{ .report_pwd = .{ .payload = owned, .term = osc.term() } },
                .hyperlink => .{ .hyperlink = .{ .payload = owned, .term = osc.term() } },
                .notification => |v| .{ .notification = .{ .command = v.command, .payload = owned, .term = v.term } },
                .pointer_shape => .{ .pointer_shape = .{ .payload = owned, .term = osc.term() } },
                .clipboard => |v| .{ .clipboard = .{ .command = v.command, .payload = owned, .term = v.term } },
                .kitty_color => |v| .{ .kitty_color = .{ .command = v.command, .payload = owned, .term = v.term } },
                .kitty_text_size => .{ .kitty_text_size = .{ .payload = owned, .term = osc.term() } },
                .kitty_drag_drop => .{ .kitty_drag_drop = .{ .payload = owned, .term = osc.term() } },
                .shell_mark => .{ .shell_mark = .{ .payload = owned, .term = osc.term() } },
                .rxvt_extension => .{ .rxvt_extension = .{ .payload = owned, .term = osc.term() } },
                .iterm2 => |v| .{ .iterm2 = .{
                    .command = v.command,
                    .payload = owned,
                    .term = v.term,
                } },
                .context_signal => .{ .context_signal = .{ .payload = owned, .term = osc.term() } },
                .kitty_color_stack_push => .{ .kitty_color_stack_push = osc.term() },
                .kitty_color_stack_pop => .{ .kitty_color_stack_pop = osc.term() },
                .kitty_file_transfer => .{ .kitty_file_transfer = .{ .payload = owned, .term = osc.term() } },
                .kitty_clipboard => .{ .kitty_clipboard = .{ .payload = owned, .term = osc.term() } },
            } });
        },
        .screen_title => |title| {
            const owned = try arena.dupe(u8, title);
            try actions.append(allocator, .{ .screen_title = owned });
        },
        else => try actions.append(allocator, action),
    }
}

fn dupeArenaSlice(arena: std.mem.Allocator, comptime T: type, data: []const T) error{OutOfMemory}![]const T {
    if (data.len == 0) return &.{};
    return try arena.dupe(T, data);
}
