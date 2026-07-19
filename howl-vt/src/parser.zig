//! Owns incremental VT parsing and emits ordered borrowed parser actions.

const std = @import("std");
const parse_table = @import("parser/parse_table.zig");
const string_control_mod = @import("parser/string_control.zig");
const utf8_mod = @import("parser/utf8.zig");

const ParseState = parse_table.ParseState;
const TransitionAction = parse_table.TransitionAction;
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
const max_chunk_control_bytes = chunk_control_max_bytes;
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
        return switch (self) {
            .raw_title => |v| v.payload,
            .raw_other => |v| v.payload,
            .title => |v| v.payload,
            .icon => |v| v.payload,
            .palette_control => |v| v.payload,
            .palette_reset => |v| v.payload,
            .dynamic_color => |v| v.payload,
            .dynamic_reset => |v| v.payload,
            .report_pwd => |v| v.payload,
            .hyperlink => |v| v.payload,
            .notification => |v| v.payload,
            .pointer_shape => |v| v.payload,
            .clipboard => |v| v.payload,
            .kitty_color => |v| v.payload,
            .kitty_text_size => |v| v.payload,
            .shell_mark => |v| v.payload,
            .rxvt_extension => |v| v.payload,
            .iterm2 => |v| v.payload,
            .context_signal => |v| v.payload,
            .kitty_color_stack_push, .kitty_color_stack_pop => "",
            .kitty_file_transfer => |v| v.payload,
            .kitty_clipboard => |v| v.payload,
        };
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
        return switch (self) {
            .raw_title => |v| v.term,
            .raw_other => |v| v.term,
            .title => |v| v.term,
            .icon => |v| v.term,
            .palette_control => |v| v.term,
            .palette_reset => |v| v.term,
            .dynamic_color => |v| v.term,
            .dynamic_reset => |v| v.term,
            .report_pwd => |v| v.term,
            .hyperlink => |v| v.term,
            .notification => |v| v.term,
            .pointer_shape => |v| v.term,
            .clipboard => |v| v.term,
            .kitty_color => |v| v.term,
            .kitty_text_size => |v| v.term,
            .shell_mark => |v| v.term,
            .rxvt_extension => |v| v.term,
            .iterm2 => |v| v.term,
            .context_signal => |v| v.term,
            .kitty_color_stack_push => |v| v,
            .kitty_color_stack_pop => |v| v,
            .kitty_file_transfer => |v| v.term,
            .kitty_clipboard => |v| v.term,
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
    apc_start,
    apc_put: u8,
    apc_end,
    dcs_hook: DcsHook,
    dcs_put: u8,
    dcs_unhook,
    pm_start,
    pm_put: u8,
    pm_end,
    sos_start,
    sos_put: u8,
    sos_end,
    esc_dispatch: EscAction,
};

/// Preserves exit, transition, and entry action order for one input byte.
pub const PhaseActions = [3]?Action;

/// Stateful parser for terminal input streams.
pub const Parser = struct {
    /// Parser initialization can fail only while allocating its reusable OSC buffer.
    pub const InitError = error{OutOfMemory};

    utf8: utf8_mod.Utf8Decoder,
    state: ParseState,
    csi_params: [csi_max_params]i32,
    csi_separators: CsiSeparatorList,
    csi_count: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
    csi_in_param: bool,
    osc: string_control_mod.OscControl,
    apc: string_control_mod.PassthroughControl,
    dcs: string_control_mod.PassthroughControl,
    pm: string_control_mod.PassthroughControl,
    sos: string_control_mod.PassthroughControl,

    /// Initialize parser state and its allocator-owned reusable OSC buffer.
    pub fn init(allocator: std.mem.Allocator) InitError!Parser {
        const osc = try string_control_mod.OscControl.init(
            allocator,
            control_init_capacity,
            metadata_control_max_bytes,
            clipboard_control_max_bytes,
            chunk_control_max_bytes,
        );

        return .{
            .utf8 = .{},
            .state = .ground,
            .csi_params = [_]i32{0} ** csi_max_params,
            .csi_separators = CsiSeparatorList.initEmpty(),
            .csi_count = 0,
            .intermediates = [_]u8{0} ** csi_max_intermediates,
            .intermediates_len = 0,
            .csi_in_param = false,
            .osc = osc,
            .apc = string_control_mod.PassthroughControl.init(false),
            .dcs = string_control_mod.PassthroughControl.init(false),
            .pm = string_control_mod.PassthroughControl.init(false),
            .sos = string_control_mod.PassthroughControl.init(false),
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

    /// Returns and clears the pending OSC allocation or bound failure.
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

        const transition = parse_table.table[byte][@intFromEnum(self.state)];
        if (self.isActiveState()) {
            return self.nextActive(byte, transition);
        }

        const transition_action = self.doAction(transition.action, byte);
        const next_state = transition.state;
        const current_state = self.state;
        defer self.state = next_state;

        return self.buildPhases(current_state, next_state, transition_action, byte, null);
    }

    fn nextActive(self: *Parser, byte: u8, transition: parse_table.Transition) PhaseActions {
        const current_state = self.state;
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

        if (byte != 0x1B and byte != 0x9C and !finishing_escape and (transition.state != current_state or transition.action != .none)) {
            const transition_action = self.doAction(transition.action, byte);
            defer self.state = transition.state;
            return self.buildPhases(current_state, transition.state, transition_action, byte, null);
        }

        const next_state, const action = self.feedActiveByte(current_state, sos_kind, byte);
        defer self.state = next_state;
        return self.buildPhases(current_state, next_state, action, byte, sos_kind);
    }

    fn feedActiveByte(self: *Parser, current_state: ParseState, sos_kind: ?BufferedControlKind, byte: u8) struct { ParseState, ?Action } {
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

    fn buildPhases(self: *Parser, current_state: ParseState, next_state: ParseState, transition_action: ?Action, byte: u8, sos_kind: ?BufferedControlKind) PhaseActions {
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
                    else => break :exit null,
                };
                break :exit .{ .osc_dispatch = self.osc.snapshot(term) };
            },
            .dcs_passthrough => dcs: {
                self.dcs.reset();
                std.debug.assert(!self.dcs.active());
                break :dcs .dcs_unhook;
            },
            .sos_pm_apc_string => switch (sos_kind orelse self.sosPmApcKind()) {
                .apc => apc: {
                    self.apc.reset();
                    std.debug.assert(!self.apc.active());
                    break :apc .apc_end;
                },
                .pm => pm: {
                    self.pm.reset();
                    std.debug.assert(!self.pm.active());
                    break :pm .pm_end;
                },
                .sos => sos: {
                    self.sos.reset();
                    std.debug.assert(!self.sos.active());
                    break :sos .sos_end;
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
            .osc_string, .dcs_passthrough, .sos_pm_apc_string => true,
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

fn expectPhaseTags(phases: PhaseActions, exit_tag: ?std.meta.Tag(Action), transition_tag: ?std.meta.Tag(Action), entry_tag: ?std.meta.Tag(Action)) !void {
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
    try expectPhaseTags(apc_start, .dcs_unhook, null, .apc_start);
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
