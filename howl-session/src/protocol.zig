//! Small transport-neutral contract for attaching to one shared Howl session.
//!
//! The wire is request-driven. A client has at most one outstanding `observe`
//! request. The endpoint answers with one coherent snapshot at a single
//! revision, then the client asks again from that revision. This deliberately
//! avoids a server-side stream queue per observer: slow clients may see a newer
//! snapshot later, but they never pace PTY or VT progress.
//!
//! An endpoint must copy/materialize the requested snapshot before it emits
//! `snapshot_begin`. PTY/VT work may continue while those copied bytes drain to
//! the client. `snapshot_end.revision` closes that exact cut; the client's next
//! `observe.after_revision` starts after it. Revision zero always requests an
//! immediate snapshot, which also gives history scrolling a non-waiting path.

const std = @import("std");

/// Version of the fixed frame header, independent of session protocol versions.
pub const framing_version: u8 = 1;
/// Oldest session protocol this implementation can negotiate.
pub const protocol_min_version: u16 = 1;
/// Newest session protocol this implementation can negotiate.
pub const protocol_max_version: u16 = 1;
/// Exact byte width of every frame header.
pub const header_bytes: usize = 12;
/// Hard upper bound admitted for one frame payload.
pub const maximum_payload_bytes: u32 = 1024 * 1024;
/// Hard upper bound the node-local endpoint admits for one client request payload.
pub const maximum_request_payload_bytes: u32 = 64 * 1024;
/// Hard upper bound materialized for one observer snapshot response.
pub const maximum_snapshot_bytes: usize = 4 * 1024 * 1024;
/// Sentinel used only where an optional client identity is serialized.
pub const no_client: ClientId = 0;

const magic = [4]u8{ 'H', 'W', 'L', 'S' };

/// Stable connection-local identity. Zero means no client/leader.
pub const ClientId = u64;

/// Frames carried unchanged over any ordered byte stream, including Unix or TCP sockets.
pub const Kind = enum(u8) {
    hello = 1,
    welcome = 2,
    observe = 3,
    snapshot_begin = 4,
    snapshot_data = 5,
    snapshot_end = 6,
    input = 7,
    assign_leader = 8,
    resize = 9,
    signal = 10,
    result = 11,
    interaction_state = 12,
    interaction_state_snapshot = 13,
};

/// Features are negotiated independently of protocol version.
pub const Feature = enum(u6) {
    grid_snapshot = 0,
    typed_input = 1,
    resize_leader = 2,
    history_window = 3,
    text_snapshot = 4,
    interaction_state = 5,
};

/// Returns the negotiated bit mask for one feature.
pub fn feature(feature_value: Feature) u64 {
    return @as(u64, 1) << @backingInt(feature_value);
}

/// Features implemented by the current endpoint contract.
pub const supported_features = feature(.grid_snapshot) |
    feature(.typed_input) |
    feature(.resize_leader) |
    feature(.history_window) |
    feature(.text_snapshot) |
    feature(.interaction_state);

/// One fixed framing header. Multi-byte integers are big-endian on the wire.
pub const Header = struct {
    kind: Kind,
    payload_len: u32,
};

/// Rejects malformed or unsupported framing before payload allocation/read.
pub const HeaderError = error{
    InvalidMagic,
    UnsupportedFramingVersion,
    InvalidReservedBits,
    UnknownKind,
    PayloadTooLarge,
};

/// Rejects a fixed message payload whose size or enum values are invalid.
pub const PayloadError = error{InvalidPayload};

/// Handshake sent before any session request.
pub const Hello = struct {
    min_version: u16 = protocol_min_version,
    max_version: u16 = protocol_max_version,
    features: u64 = supported_features,
};

/// Handshake response. Clients only learn their own identity by default.
pub const Welcome = struct {
    version: u16,
    features: u64,
    client_id: ClientId,
};

/// Long-poll style observation request. Revision zero means initial attach.
pub const Observe = struct {
    after_revision: u64 = 0,
    history_offset: u32 = 0,
};

/// Input payload family. Structured key/mouse input is capability-gated.
pub const InputKind = enum(u8) {
    bytes = 1,
    paste = 2,
    key = 3,
    mouse = 4,
    focus = 5,
};

/// Distinguishes named physical keys from Unicode physical-key identities.
pub const InputKeyKind = enum(u8) {
    named = 1,
    unicode = 2,
};

/// Stable language-neutral names for physical keys with non-Unicode identity.
pub const InputKeyName = enum(u8) {
    enter = 1,
    tab = 2,
    backspace = 3,
    escape = 4,
    up = 5,
    down = 6,
    left = 7,
    right = 8,
    insert = 9,
    delete = 10,
    home = 11,
    end = 12,
    page_up = 13,
    page_down = 14,
    left_shift = 15,
    right_shift = 16,
    left_control = 17,
    right_control = 18,
    left_alt = 19,
    right_alt = 20,
    left_super = 21,
    right_super = 22,
    left_hyper = 23,
    right_hyper = 24,
    left_meta = 25,
    right_meta = 26,
    caps_lock = 27,
    num_lock = 28,
    f1 = 29,
    f2 = 30,
    f3 = 31,
    f4 = 32,
    f5 = 33,
    f6 = 34,
    f7 = 35,
    f8 = 36,
    f9 = 37,
    f10 = 38,
    f11 = 39,
    f12 = 40,
    keypad_0 = 41,
    keypad_1 = 42,
    keypad_2 = 43,
    keypad_3 = 44,
    keypad_4 = 45,
    keypad_5 = 46,
    keypad_6 = 47,
    keypad_7 = 48,
    keypad_8 = 49,
    keypad_9 = 50,
    keypad_decimal = 51,
    keypad_add = 52,
    keypad_subtract = 53,
    keypad_multiply = 54,
    keypad_divide = 55,
    keypad_separator = 56,
    keypad_equal = 57,
    keypad_enter = 58,
};

/// Stable physical-key transition actions.
pub const InputKeyAction = enum(u8) {
    press = 1,
    repeat = 2,
    release = 3,
};

/// Stable semantic mouse button identities.
pub const InputMouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Stable semantic mouse event classes.
pub const InputMouseKind = enum(u8) {
    press = 1,
    release = 2,
    move = 3,
    wheel = 4,
};

/// Stable semantic focus transitions.
pub const InputFocus = enum(u8) {
    in = 1,
    out = 2,
};

/// One borrowed physical-key payload decoded from the typed-input wire grammar.
pub const KeyInput = struct {
    kind: InputKeyKind,
    key_value: u32,
    action: InputKeyAction,
    modifiers: u8 = 0,
    shifted: ?u32 = null,
    alternate: ?u32 = null,
    legacy_text: []const u8 = "",
    text: []const u8 = "",
};

/// One semantic mouse payload decoded from the typed-input wire grammar.
pub const MouseInput = struct {
    kind: InputMouseKind,
    button: InputMouseButton,
    modifiers: u8 = 0,
    buttons_down: u8 = 0,
    row: i32,
    column: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
};

/// Frozen byte grammar and bounds for capability-gated typed input.
pub const typed_input = struct {
    /// Fixed physical-key header before bounded legacy and committed-text bytes.
    pub const key_header_bytes: usize = 20;
    /// Maximum exact legacy key bytes while retaining canonical Meta prefix room.
    pub const maximum_legacy_key_bytes: u16 = 511;
    /// Maximum committed UTF-8 text carried by one physical key event.
    pub const maximum_key_text_bytes: u8 = 64;
    /// Fixed semantic mouse payload bytes.
    pub const mouse_bytes: usize = 19;
    /// Fixed focus payload bytes.
    pub const focus_bytes: usize = 1;

    /// Modifier bits, independent of any language's packed-struct layout.
    pub const modifiers = struct {
        /// Shift is held.
        pub const shift: u8 = 1 << 0;
        /// Alt/Option is held.
        pub const alt: u8 = 1 << 1;
        /// Control is held.
        pub const control: u8 = 1 << 2;
        /// Super/Command/Windows is held.
        pub const super: u8 = 1 << 3;
        /// Hyper is held.
        pub const hyper: u8 = 1 << 4;
        /// Meta is held.
        pub const meta: u8 = 1 << 5;
        /// Caps Lock is active.
        pub const caps_lock: u8 = 1 << 6;
        /// Num Lock is active.
        pub const num_lock: u8 = 1 << 7;
        /// Mask of every accepted modifier bit.
        pub const known: u8 = shift | alt | control | super | hyper | meta |
            caps_lock | num_lock;
    };

    /// Optional physical-key scalar fields.
    pub const key_presence = struct {
        /// Shift-produced Unicode identity is present.
        pub const shifted: u8 = 1 << 0;
        /// Alternate-layout Unicode identity is present.
        pub const alternate: u8 = 1 << 1;
        /// Mask of every accepted key-presence bit.
        pub const known: u8 = shifted | alternate;
    };

    /// Optional mouse coordinate fields.
    pub const mouse_presence = struct {
        /// Both pixel coordinates are present.
        pub const pixels: u8 = 1 << 0;
        /// Mask of every accepted mouse-presence bit.
        pub const known: u8 = pixels;
    };
};

/// Signals accepted by the session process-group boundary.
pub const Signal = enum(u8) {
    hangup = 1,
    interrupt = 2,
    resize_notify = 3,
    kill = 9,
    terminate = 15,
};

/// Frozen mouse-event selection retained by one interaction-state snapshot.
pub const InteractionMouseTracking = enum(u8) {
    off = 0,
    x10 = 1,
    normal = 2,
    button_event = 3,
    any_event = 4,
};

/// Frozen mouse-report encoding retained by one interaction-state snapshot.
pub const InteractionMouseProtocol = enum(u8) {
    none = 0,
    utf8 = 1,
    sgr = 2,
    sgr_pixel = 3,
    urxvt = 4,
};

/// Coherent mode-directed caller interaction state at one terminal revision.
pub const InteractionStateSnapshot = struct {
    terminal_revision: u64,
    keyboard_action_mode: bool,
    auto_repeat: bool,
    newline_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    meta_sends_escape: bool,
    report_key_up: bool,
    bracketed_paste: bool,
    focus_reporting: bool,
    termios_signals: bool,
    alternate_scroll: bool,
    paste_events: bool,
    inband_resize_notifications: bool,
    mouse_tracking: InteractionMouseTracking,
    mouse_protocol: InteractionMouseProtocol,
    modify_other_keys: i8,
    kitty_keyboard_flags: u8,
    key_format_resource_4: u16,
    pointer_mode: u2,
};

/// Bit positions in the fixed interaction-state flags word.
pub const interaction_state_flags = struct {
    /// Keyboard action mode suppresses ordinary key encoding.
    pub const keyboard_action_mode: u32 = 1 << 0;
    /// Physical key repeat transitions are currently admitted.
    pub const auto_repeat: u32 = 1 << 1;
    /// Enter uses CRLF rather than CR when legacy encoding applies.
    pub const newline_mode: u32 = 1 << 2;
    /// Cursor keys use application-cursor encoding.
    pub const application_cursor_keys: u32 = 1 << 3;
    /// Keypad keys use application-keypad encoding.
    pub const application_keypad: u32 = 1 << 4;
    /// Alt-modified legacy bytes receive an Escape prefix.
    pub const meta_sends_escape: u32 = 1 << 5;
    /// Legacy key-release reporting is enabled.
    pub const report_key_up: u32 = 1 << 6;
    /// Semantic paste is wrapped in bracketed-paste delimiters.
    pub const bracketed_paste: u32 = 1 << 7;
    /// Focus in/out input is reported to the child.
    pub const focus_reporting: u32 = 1 << 8;
    /// Matching control bytes may be delivered as foreground termios signals.
    pub const termios_signals: u32 = 1 << 9;
    /// Alternate-screen wheel input uses alternate-scroll behavior.
    pub const alternate_scroll: u32 = 1 << 10;
    /// Kitty paste-event exchange is enabled.
    pub const paste_events: u32 = 1 << 11;
    /// Resize commits generate in-band terminal resize notification bytes.
    pub const inband_resize_notifications: u32 = 1 << 12;
    /// Mask of every defined interaction-state flag bit.
    pub const known: u32 = (1 << 13) - 1;
};

/// Bounded request outcome without transporting host-specific errno values.
pub const ResultCode = enum(u8) {
    ok = 0,
    malformed = 1,
    unsupported = 2,
    no_such_client = 3,
    not_leader = 4,
    rejected = 5,
};

/// Correlates one command response by its request kind.
pub const Result = struct {
    request_kind: Kind,
    code: ResultCode,
};

/// Stable first terminal snapshot representation carried by snapshot_data frames.
///
/// `grid_v1` intentionally freezes only the canonical spatial grid needed by
/// the first shared-session client: row wrap/DEC geometry and each cell's
/// codepoint plus multicell occupancy. `text_v1` adds complete renderer-neutral
/// text semantics; terminal images remain a separate future capability.
pub const SnapshotFormat = enum(u16) {
    grid_v1 = 1,
    text_v1 = 2,
};

/// Record classes carried inside `snapshot_data` for `SnapshotFormat.text_v1`.
///
/// Each `snapshot_data` frame carries exactly one record. Every record starts
/// with one fixed eight-byte header so clients can validate it without
/// depending on Zig struct layout.
pub const TextRecordKind = enum(u8) {
    presentation = 1,
    row = 2,
    hyperlink = 3,
};

/// One self-delimiting `text_v1` record header. Reserved bytes are always zero.
pub const TextRecordHeader = struct {
    kind: TextRecordKind,
    payload_len: u32,
};

/// Stable language-neutral terminal color classes used by `text_v1` cells.
pub const TextColorKind = enum(u8) {
    default = 0,
    indexed = 1,
    rgb = 2,
};

/// One semantic terminal color. RGB values use the low 24 bits as 0xRRGGBB.
pub const TextColor = struct {
    kind: TextColorKind,
    value: u32,
};

/// Frozen byte grammar and bounds for the renderer-neutral rich text snapshot.
pub const text_v1 = struct {
    /// Fixed record header: kind:u8, reserved:u24=0, payload_len:u32 big-endian.
    pub const record_header_bytes: usize = 8;
    /// Semantic color: kind:u8 followed by value:u32 big-endian.
    pub const color_bytes: usize = 5;
    /// Exact fixed presentation payload; this record has no variable suffix.
    pub const presentation_bytes: usize = 8 + 1 + 1 + 2 +
        256 * 4 + 2 * 4 + 4 * 4;
    /// Cursor-age sentinel when no tracked absolute movement has occurred.
    pub const no_cursor_movement_age_ns: u64 = std.math.maxInt(u64);
    /// Row prefix: wrapped:u8, DEC line geometry:u8, columns:u16 big-endian.
    pub const row_header_bytes: usize = 4;
    /// Fixed cell prefix followed by `scalar_count` big-endian u32 scalars.
    pub const cell_header_bytes: usize = 35;
    /// Hyperlink prefix: stable link_id:u32 + uri_len:u16, both big-endian.
    pub const hyperlink_header_bytes: usize = 6;
    /// Frozen maximum Unicode scalars transported for one terminal grapheme.
    pub const maximum_cell_scalars: u8 = 24;
    /// Frozen maximum referenced OSC 8 identities in one snapshot.
    pub const maximum_hyperlinks: u16 = 4096;
    /// Frozen maximum URI bytes for one transported OSC 8 target.
    pub const maximum_hyperlink_uri_bytes: u16 = 2048;

    /// Optional presentation colors whose four RGBA slots are always present.
    pub const presentation_presence = struct {
        /// Cursor-color RGBA slot is semantically present.
        pub const cursor: u8 = 1 << 0;
        /// Cursor-text RGBA slot is semantically present.
        pub const cursor_text: u8 = 1 << 1;
        /// Selection-background RGBA slot is semantically present.
        pub const selection_background: u8 = 1 << 2;
        /// Selection-foreground RGBA slot is semantically present.
        pub const selection_foreground: u8 = 1 << 3;
        /// Mask of every accepted `text_v1` presentation-presence bit.
        pub const known: u8 = cursor | cursor_text |
            selection_background | selection_foreground;
    };

    /// Terminal-wide presentation flags.
    pub const presentation_flags = struct {
        /// DEC reverse-video mode applies to the complete presentation.
        pub const reverse_screen: u8 = 1 << 0;
        /// Mask of every accepted `text_v1` presentation flag.
        pub const known: u8 = reverse_screen;
    };

    /// Cell style flags. Spare bits must remain zero for `text_v1`.
    pub const style = struct {
        /// SGR bold rendition is active.
        pub const bold: u16 = 1 << 0;
        /// SGR dim rendition is active.
        pub const dim: u16 = 1 << 1;
        /// SGR italic rendition is active.
        pub const italic: u16 = 1 << 2;
        /// Slow blink rendition is active.
        pub const blink: u16 = 1 << 3;
        /// Fast blink rendition is active.
        pub const blink_fast: u16 = 1 << 4;
        /// Cell foreground/background semantic reversal is active.
        pub const reverse: u16 = 1 << 5;
        /// Invisible/conceal rendition is active.
        pub const invisible: u16 = 1 << 6;
        /// Underline rendition is active; style is carried separately.
        pub const underline: u16 = 1 << 7;
        /// Strikethrough rendition is active.
        pub const strikethrough: u16 = 1 << 8;
        /// Mask of every accepted `text_v1` cell-style bit.
        pub const known: u16 = bold | dim | italic | blink | blink_fast |
            reverse | invisible | underline | strikethrough;
    };
};

/// Starts one coherent snapshot. All following data/end frames share revision.
pub const SnapshotBegin = struct {
    /// Endpoint observation revision covering VT, lifecycle, and authority state.
    revision: u64,
    /// Canonical VT semantic revision captured inside this observation.
    terminal_revision: u64,
    format: SnapshotFormat = .grid_v1,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_shape: u8,
    cursor_visible: bool,
    cursor_blink: bool,
    alternate_screen: bool,
    stream_closed: bool,
    child_exited: bool,
    leader_present: bool,
    you_are_leader: bool,
};

/// Completes one snapshot and makes its revision valid for the next observe.
pub const SnapshotEnd = struct {
    revision: u64,
};

/// Explicit geometry request. The endpoint accepts it only from the leader.
pub const Resize = struct {
    rows: u16,
    columns: u16,
};

/// Explicit leader assignment. `no_client` clears leadership.
pub const AssignLeader = struct {
    client_id: ClientId,
};

/// Exact fixed payload widths for v1 messages.
pub const payload_bytes = struct {
    /// `Hello` payload bytes.
    pub const hello: usize = 12;
    /// `Welcome` payload bytes.
    pub const welcome: usize = 18;
    /// `Observe` payload bytes.
    pub const observe: usize = 12;
    /// `SnapshotBegin` payload bytes.
    pub const snapshot_begin: usize = 40;
    /// `SnapshotEnd` payload bytes.
    pub const snapshot_end: usize = 8;
    /// `AssignLeader` payload bytes.
    pub const assign_leader: usize = 8;
    /// `Resize` payload bytes.
    pub const resize: usize = 4;
    /// `Signal` payload bytes.
    pub const signal: usize = 1;
    /// `Result` payload bytes.
    pub const result: usize = 2;
    /// `interaction_state` request payload bytes.
    pub const interaction_state: usize = 0;
    /// `interaction_state_snapshot` payload bytes.
    pub const interaction_state_snapshot: usize = 20;
};

/// Owns only geometry authority. Client discovery/rosters remain endpoint policy.
pub const ResizeAuthority = struct {
    leader_client_id: ClientId = no_client,
    revision: u64 = 1,

    /// Returns the current leader, if explicit geometry authority exists.
    pub fn leader(self: ResizeAuthority) ?ClientId {
        return if (self.leader_client_id == no_client) null else self.leader_client_id;
    }

    /// Replaces or clears the leader and reports whether authority changed.
    pub fn assign(self: *ResizeAuthority, client_id: ClientId) bool {
        if (self.leader_client_id == client_id) return false;
        self.leader_client_id = client_id;
        advance(&self.revision);
        return true;
    }

    /// Clears leadership only when the disconnected client currently owns it.
    pub fn disconnected(self: *ResizeAuthority, client_id: ClientId) bool {
        if (client_id == no_client or self.leader_client_id != client_id) return false;
        self.leader_client_id = no_client;
        advance(&self.revision);
        return true;
    }

    /// Reports whether one attached client may mutate canonical geometry.
    pub fn mayResize(self: ResizeAuthority, client_id: ClientId) bool {
        return client_id != no_client and self.leader_client_id == client_id;
    }
};

/// Selects the highest mutually supported protocol version.
pub fn negotiateVersion(hello: Hello) ?u16 {
    if (hello.min_version > hello.max_version) return null;
    const lower = @max(hello.min_version, protocol_min_version);
    const upper = @min(hello.max_version, protocol_max_version);
    return if (lower <= upper) upper else null;
}

/// Returns the features both peers can use for the negotiated connection.
pub fn negotiateFeatures(hello: Hello) u64 {
    return hello.features & supported_features;
}

/// Encodes one hello payload with explicit endian order.
pub fn encodeHello(output: *[payload_bytes.hello]u8, value: Hello) void {
    writeU16(output[0..2], value.min_version);
    writeU16(output[2..4], value.max_version);
    writeU64(output[4..12], value.features);
}

/// Decodes one exact hello payload.
pub fn decodeHello(input: []const u8) PayloadError!Hello {
    if (input.len != payload_bytes.hello) return error.InvalidPayload;
    return .{
        .min_version = readU16(input[0..2]),
        .max_version = readU16(input[2..4]),
        .features = readU64(input[4..12]),
    };
}

/// Encodes one welcome payload with explicit endian order.
pub fn encodeWelcome(output: *[payload_bytes.welcome]u8, value: Welcome) void {
    writeU16(output[0..2], value.version);
    writeU64(output[2..10], value.features);
    writeU64(output[10..18], value.client_id);
}

/// Decodes one exact welcome payload.
pub fn decodeWelcome(input: []const u8) PayloadError!Welcome {
    if (input.len != payload_bytes.welcome) return error.InvalidPayload;
    return .{
        .version = readU16(input[0..2]),
        .features = readU64(input[2..10]),
        .client_id = readU64(input[10..18]),
    };
}

/// Encodes one observation request.
pub fn encodeObserve(output: *[payload_bytes.observe]u8, value: Observe) void {
    writeU64(output[0..8], value.after_revision);
    writeU32(output[8..12], value.history_offset);
}

/// Decodes one exact observation request.
pub fn decodeObserve(input: []const u8) PayloadError!Observe {
    if (input.len != payload_bytes.observe) return error.InvalidPayload;
    return .{
        .after_revision = readU64(input[0..8]),
        .history_offset = readU32(input[8..12]),
    };
}

/// Encodes one snapshot metadata boundary.
pub fn encodeSnapshotBegin(output: *[payload_bytes.snapshot_begin]u8, value: SnapshotBegin) void {
    output.* = @splat(0);
    writeU64(output[0..8], value.revision);
    writeU64(output[8..16], value.terminal_revision);
    writeU16(output[16..18], @backingInt(value.format));
    writeU32(output[18..22], value.history_offset);
    writeU32(output[22..26], value.history_count);
    writeU32(output[26..30], value.history_row_base);
    writeU16(output[30..32], value.rows);
    writeU16(output[32..34], value.columns);
    writeU16(output[34..36], value.cursor_row);
    writeU16(output[36..38], value.cursor_column);
    output[38] = value.cursor_shape;
    output[39] = (@as(u8, @intFromBool(value.cursor_visible)) << 0) |
        (@as(u8, @intFromBool(value.cursor_blink)) << 1) |
        (@as(u8, @intFromBool(value.alternate_screen)) << 2) |
        (@as(u8, @intFromBool(value.stream_closed)) << 3) |
        (@as(u8, @intFromBool(value.child_exited)) << 4) |
        (@as(u8, @intFromBool(value.leader_present)) << 5) |
        (@as(u8, @intFromBool(value.you_are_leader)) << 6);
}

/// Decodes one exact snapshot metadata boundary.
pub fn decodeSnapshotBegin(input: []const u8) PayloadError!SnapshotBegin {
    if (input.len != payload_bytes.snapshot_begin) return error.InvalidPayload;
    const format = enumFromInt(SnapshotFormat, readU16(input[16..18])) orelse
        return error.InvalidPayload;
    if (input[39] & 0x80 != 0) return error.InvalidPayload;
    return .{
        .revision = readU64(input[0..8]),
        .terminal_revision = readU64(input[8..16]),
        .format = format,
        .history_offset = readU32(input[18..22]),
        .history_count = readU32(input[22..26]),
        .history_row_base = readU32(input[26..30]),
        .rows = readU16(input[30..32]),
        .columns = readU16(input[32..34]),
        .cursor_row = readU16(input[34..36]),
        .cursor_column = readU16(input[36..38]),
        .cursor_shape = input[38],
        .cursor_visible = input[39] & (1 << 0) != 0,
        .cursor_blink = input[39] & (1 << 1) != 0,
        .alternate_screen = input[39] & (1 << 2) != 0,
        .stream_closed = input[39] & (1 << 3) != 0,
        .child_exited = input[39] & (1 << 4) != 0,
        .leader_present = input[39] & (1 << 5) != 0,
        .you_are_leader = input[39] & (1 << 6) != 0,
    };
}

/// Encodes one self-delimiting `text_v1` record header.
pub fn encodeTextRecordHeader(
    output: *[text_v1.record_header_bytes]u8,
    value: TextRecordHeader,
) void {
    output.* = @splat(0);
    output[0] = @backingInt(value.kind);
    writeU32(output[4..8], value.payload_len);
}

/// Decodes one `text_v1` record header and rejects every reserved bit.
pub fn decodeTextRecordHeader(
    input: *const [text_v1.record_header_bytes]u8,
) PayloadError!TextRecordHeader {
    if (input[1] != 0 or input[2] != 0 or input[3] != 0)
        return error.InvalidPayload;
    return .{
        .kind = enumFromInt(TextRecordKind, input[0]) orelse
            return error.InvalidPayload,
        .payload_len = readU32(input[4..8]),
    };
}

/// Encodes one semantic `text_v1` terminal color.
pub fn encodeTextColor(
    output: *[text_v1.color_bytes]u8,
    value: TextColor,
) PayloadError!void {
    switch (value.kind) {
        .default => if (value.value != 0) return error.InvalidPayload,
        .indexed => if (value.value > 255) return error.InvalidPayload,
        .rgb => if (value.value > 0x00ff_ffff) return error.InvalidPayload,
    }
    output[0] = @backingInt(value.kind);
    writeU32(output[1..5], value.value);
}

/// Decodes and validates one semantic `text_v1` terminal color.
pub fn decodeTextColor(input: *const [text_v1.color_bytes]u8) PayloadError!TextColor {
    const value = TextColor{
        .kind = enumFromInt(TextColorKind, input[0]) orelse
            return error.InvalidPayload,
        .value = readU32(input[1..5]),
    };
    var canonical: [text_v1.color_bytes]u8 = undefined;
    try encodeTextColor(&canonical, value);
    return value;
}

/// Reports malformed typed input or insufficient caller-provided encode storage.
pub const InputEncodeError = PayloadError || error{OutputTooSmall};

/// Returns the exact typed-key body bytes after validating its canonical form.
pub fn keyInputBytes(value: KeyInput) PayloadError!usize {
    try validateKeyInput(value);
    return typed_input.key_header_bytes + value.legacy_text.len + value.text.len;
}

/// Encodes one physical-key body after the outer `InputKind.key` byte.
pub fn encodeKeyInput(output: []u8, value: KeyInput) InputEncodeError![]const u8 {
    const needed = try keyInputBytes(value);
    if (output.len < needed) return error.OutputTooSmall;
    const encoded = output[0..needed];
    @memset(encoded[0..typed_input.key_header_bytes], 0);
    encoded[0] = @backingInt(value.kind);
    encoded[1] = @backingInt(value.action);
    encoded[2] = value.modifiers;
    encoded[3] = (@as(u8, @intFromBool(value.shifted != null)) * typed_input.key_presence.shifted) |
        (@as(u8, @intFromBool(value.alternate != null)) * typed_input.key_presence.alternate);
    writeU32(encoded[4..8], value.key_value);
    writeU32(encoded[8..12], value.shifted orelse 0);
    writeU32(encoded[12..16], value.alternate orelse 0);
    writeU16(encoded[16..18], @intCast(value.legacy_text.len));
    writeU16(encoded[18..20], @intCast(value.text.len));
    @memcpy(encoded[20 .. 20 + value.legacy_text.len], value.legacy_text);
    @memcpy(encoded[20 + value.legacy_text.len ..], value.text);
    return encoded;
}

/// Decodes one exact physical-key body and borrows its trailing text slices.
pub fn decodeKeyInput(input: []const u8) PayloadError!KeyInput {
    if (input.len < typed_input.key_header_bytes) return error.InvalidPayload;
    const presence = input[3];
    if (presence & ~typed_input.key_presence.known != 0) return error.InvalidPayload;
    const legacy_len = readU16(input[16..18]);
    const text_len = readU16(input[18..20]);
    if (legacy_len > typed_input.maximum_legacy_key_bytes or
        text_len > typed_input.maximum_key_text_bytes)
        return error.InvalidPayload;
    const expected = std.math.add(
        usize,
        typed_input.key_header_bytes,
        @as(usize, legacy_len) + text_len,
    ) catch return error.InvalidPayload;
    if (input.len != expected) return error.InvalidPayload;
    const shifted_raw = readU32(input[8..12]);
    const alternate_raw = readU32(input[12..16]);
    const value = KeyInput{
        .kind = enumFromInt(InputKeyKind, input[0]) orelse return error.InvalidPayload,
        .action = enumFromInt(InputKeyAction, input[1]) orelse return error.InvalidPayload,
        .modifiers = input[2],
        .key_value = readU32(input[4..8]),
        .shifted = if (presence & typed_input.key_presence.shifted != 0)
            shifted_raw
        else if (shifted_raw == 0)
            null
        else
            return error.InvalidPayload,
        .alternate = if (presence & typed_input.key_presence.alternate != 0)
            alternate_raw
        else if (alternate_raw == 0)
            null
        else
            return error.InvalidPayload,
        .legacy_text = input[20 .. 20 + legacy_len],
        .text = input[20 + legacy_len ..],
    };
    try validateKeyInput(value);
    return value;
}

/// Encodes one semantic mouse body after the outer `InputKind.mouse` byte.
pub fn encodeMouseInput(
    output: *[typed_input.mouse_bytes]u8,
    value: MouseInput,
) PayloadError!void {
    try validateMouseInput(value);
    output.* = @splat(0);
    output[0] = @backingInt(value.kind);
    output[1] = @backingInt(value.button);
    output[2] = value.modifiers;
    output[3] = value.buttons_down;
    writeI32(output[4..8], value.row);
    writeU16(output[8..10], value.column);
    if (value.pixel_x != null) output[10] = typed_input.mouse_presence.pixels;
    writeU32(output[11..15], value.pixel_x orelse 0);
    writeU32(output[15..19], value.pixel_y orelse 0);
}

/// Decodes one exact semantic mouse body.
pub fn decodeMouseInput(input: []const u8) PayloadError!MouseInput {
    if (input.len != typed_input.mouse_bytes or
        input[10] & ~typed_input.mouse_presence.known != 0)
        return error.InvalidPayload;
    const pixels_present = input[10] & typed_input.mouse_presence.pixels != 0;
    const pixel_x = readU32(input[11..15]);
    const pixel_y = readU32(input[15..19]);
    if (!pixels_present and (pixel_x != 0 or pixel_y != 0))
        return error.InvalidPayload;
    const value = MouseInput{
        .kind = enumFromInt(InputMouseKind, input[0]) orelse return error.InvalidPayload,
        .button = enumFromInt(InputMouseButton, input[1]) orelse return error.InvalidPayload,
        .modifiers = input[2],
        .buttons_down = input[3],
        .row = readI32(input[4..8]),
        .column = readU16(input[8..10]),
        .pixel_x = if (pixels_present) pixel_x else null,
        .pixel_y = if (pixels_present) pixel_y else null,
    };
    try validateMouseInput(value);
    return value;
}

/// Encodes one semantic focus body after the outer `InputKind.focus` byte.
pub fn encodeFocusInput(output: *[typed_input.focus_bytes]u8, value: InputFocus) void {
    output[0] = @backingInt(value);
}

/// Decodes one exact semantic focus body.
pub fn decodeFocusInput(input: []const u8) PayloadError!InputFocus {
    if (input.len != typed_input.focus_bytes) return error.InvalidPayload;
    return enumFromInt(InputFocus, input[0]) orelse error.InvalidPayload;
}

fn validateKeyInput(value: KeyInput) PayloadError!void {
    switch (value.kind) {
        .named => {
            const wire_name = std.math.cast(u8, value.key_value) orelse
                return error.InvalidPayload;
            if (enumFromInt(InputKeyName, wire_name) == null) return error.InvalidPayload;
        },
        .unicode => try validateScalar(value.key_value),
    }
    if (value.shifted) |scalar| try validateScalar(scalar);
    if (value.alternate) |scalar| try validateScalar(scalar);
    if (value.legacy_text.len > typed_input.maximum_legacy_key_bytes or
        value.text.len > typed_input.maximum_key_text_bytes or
        !std.unicode.utf8ValidateSlice(value.text))
        return error.InvalidPayload;
}

fn validateMouseInput(value: MouseInput) PayloadError!void {
    if (value.buttons_down & ~@as(u8, 0b111) != 0) return error.InvalidPayload;
    if ((value.pixel_x == null) != (value.pixel_y == null)) return error.InvalidPayload;
}

fn validateScalar(value: u32) PayloadError!void {
    if (value > 0x10ffff or value >= 0xd800 and value <= 0xdfff)
        return error.InvalidPayload;
}

/// Encodes one completed snapshot revision.
pub fn encodeSnapshotEnd(output: *[payload_bytes.snapshot_end]u8, value: SnapshotEnd) void {
    writeU64(output, value.revision);
}

/// Decodes one completed snapshot revision.
pub fn decodeSnapshotEnd(input: []const u8) PayloadError!SnapshotEnd {
    if (input.len != payload_bytes.snapshot_end) return error.InvalidPayload;
    return .{ .revision = readU64(input) };
}

/// Encodes one explicit geometry-leader assignment.
pub fn encodeAssignLeader(output: *[payload_bytes.assign_leader]u8, value: AssignLeader) void {
    writeU64(output, value.client_id);
}

/// Decodes one explicit geometry-leader assignment.
pub fn decodeAssignLeader(input: []const u8) PayloadError!AssignLeader {
    if (input.len != payload_bytes.assign_leader) return error.InvalidPayload;
    return .{ .client_id = readU64(input) };
}

/// Encodes one explicit canonical geometry.
pub fn encodeResize(output: *[payload_bytes.resize]u8, value: Resize) void {
    writeU16(output[0..2], value.rows);
    writeU16(output[2..4], value.columns);
}

/// Decodes one explicit canonical geometry.
pub fn decodeResize(input: []const u8) PayloadError!Resize {
    if (input.len != payload_bytes.resize) return error.InvalidPayload;
    return .{ .rows = readU16(input[0..2]), .columns = readU16(input[2..4]) };
}

/// Encodes one fixed process-group signal.
pub fn encodeSignal(output: *[payload_bytes.signal]u8, value: Signal) void {
    output[0] = @backingInt(value);
}

/// Decodes one fixed process-group signal.
pub fn decodeSignal(input: []const u8) PayloadError!Signal {
    if (input.len != payload_bytes.signal) return error.InvalidPayload;
    return enumFromInt(Signal, input[0]) orelse error.InvalidPayload;
}

/// Encodes one coherent interaction-state snapshot.
pub fn encodeInteractionStateSnapshot(
    output: *[payload_bytes.interaction_state_snapshot]u8,
    value: InteractionStateSnapshot,
) void {
    output.* = @splat(0);
    writeU64(output[0..8], value.terminal_revision);
    var flags: u32 = 0;
    if (value.keyboard_action_mode) flags |= interaction_state_flags.keyboard_action_mode;
    if (value.auto_repeat) flags |= interaction_state_flags.auto_repeat;
    if (value.newline_mode) flags |= interaction_state_flags.newline_mode;
    if (value.application_cursor_keys) flags |= interaction_state_flags.application_cursor_keys;
    if (value.application_keypad) flags |= interaction_state_flags.application_keypad;
    if (value.meta_sends_escape) flags |= interaction_state_flags.meta_sends_escape;
    if (value.report_key_up) flags |= interaction_state_flags.report_key_up;
    if (value.bracketed_paste) flags |= interaction_state_flags.bracketed_paste;
    if (value.focus_reporting) flags |= interaction_state_flags.focus_reporting;
    if (value.termios_signals) flags |= interaction_state_flags.termios_signals;
    if (value.alternate_scroll) flags |= interaction_state_flags.alternate_scroll;
    if (value.paste_events) flags |= interaction_state_flags.paste_events;
    if (value.inband_resize_notifications) flags |= interaction_state_flags.inband_resize_notifications;
    writeU32(output[8..12], flags);
    output[12] = @backingInt(value.mouse_tracking);
    output[13] = @backingInt(value.mouse_protocol);
    output[14] = @bitCast(value.modify_other_keys);
    output[15] = value.kitty_keyboard_flags;
    writeU16(output[16..18], value.key_format_resource_4);
    output[18] = value.pointer_mode;
}

/// Decodes and validates one coherent interaction-state snapshot.
pub fn decodeInteractionStateSnapshot(input: []const u8) PayloadError!InteractionStateSnapshot {
    if (input.len != payload_bytes.interaction_state_snapshot) return error.InvalidPayload;
    const flags = readU32(input[8..12]);
    if (flags & ~interaction_state_flags.known != 0 or input[19] != 0 or
        input[15] & 0x80 != 0 or input[18] > 3)
        return error.InvalidPayload;
    return .{
        .terminal_revision = readU64(input[0..8]),
        .keyboard_action_mode = flags & interaction_state_flags.keyboard_action_mode != 0,
        .auto_repeat = flags & interaction_state_flags.auto_repeat != 0,
        .newline_mode = flags & interaction_state_flags.newline_mode != 0,
        .application_cursor_keys = flags & interaction_state_flags.application_cursor_keys != 0,
        .application_keypad = flags & interaction_state_flags.application_keypad != 0,
        .meta_sends_escape = flags & interaction_state_flags.meta_sends_escape != 0,
        .report_key_up = flags & interaction_state_flags.report_key_up != 0,
        .bracketed_paste = flags & interaction_state_flags.bracketed_paste != 0,
        .focus_reporting = flags & interaction_state_flags.focus_reporting != 0,
        .termios_signals = flags & interaction_state_flags.termios_signals != 0,
        .alternate_scroll = flags & interaction_state_flags.alternate_scroll != 0,
        .paste_events = flags & interaction_state_flags.paste_events != 0,
        .inband_resize_notifications = flags & interaction_state_flags.inband_resize_notifications != 0,
        .mouse_tracking = enumFromInt(InteractionMouseTracking, input[12]) orelse return error.InvalidPayload,
        .mouse_protocol = enumFromInt(InteractionMouseProtocol, input[13]) orelse return error.InvalidPayload,
        .modify_other_keys = @bitCast(input[14]),
        .kitty_keyboard_flags = input[15],
        .key_format_resource_4 = readU16(input[16..18]),
        .pointer_mode = @intCast(input[18]),
    };
}

/// Encodes one bounded command result.
pub fn encodeResult(output: *[payload_bytes.result]u8, value: Result) void {
    output[0] = @backingInt(value.request_kind);
    output[1] = @backingInt(value.code);
}

/// Decodes one bounded command result.
pub fn decodeResult(input: []const u8) PayloadError!Result {
    if (input.len != payload_bytes.result) return error.InvalidPayload;
    return .{
        .request_kind = enumFromInt(Kind, input[0]) orelse return error.InvalidPayload,
        .code = enumFromInt(ResultCode, input[1]) orelse return error.InvalidPayload,
    };
}

/// Encodes one fixed header without allocation.
pub fn encodeHeader(output: *[header_bytes]u8, header: Header) error{PayloadTooLarge}!void {
    if (header.payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    output.* = @splat(0);
    @memcpy(output[0..4], &magic);
    output[4] = framing_version;
    output[5] = @backingInt(header.kind);
    writeU32(output[8..12], header.payload_len);
}

/// Decodes and validates one fixed header before any payload is admitted.
pub fn decodeHeader(input: *const [header_bytes]u8) HeaderError!Header {
    if (!std.mem.eql(u8, input[0..4], &magic)) return error.InvalidMagic;
    if (input[4] != framing_version) return error.UnsupportedFramingVersion;
    if (input[6] != 0 or input[7] != 0) return error.InvalidReservedBits;
    const kind = enumFromInt(Kind, input[5]) orelse return error.UnknownKind;
    const payload_len = readU32(input[8..12]);
    if (payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    return .{ .kind = kind, .payload_len = payload_len };
}

fn writeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

fn writeI32(output: []u8, value: i32) void {
    writeU32(output, @bitCast(value));
}

fn writeU16(output: []u8, value: u16) void {
    std.debug.assert(output.len == 2);
    output[0] = @truncate(value >> 8);
    output[1] = @truncate(value);
}

fn writeU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    var shift: u6 = 56;
    for (output) |*byte| {
        byte.* = @truncate(value >> shift);
        shift -|= 8;
    }
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        @as(u32, input[3]);
}

fn readI32(input: []const u8) i32 {
    return @bitCast(readU32(input));
}

fn readU16(input: []const u8) u16 {
    std.debug.assert(input.len == 2);
    return (@as(u16, input[0]) << 8) | @as(u16, input[1]);
}

fn readU64(input: []const u8) u64 {
    std.debug.assert(input.len == 8);
    var value: u64 = 0;
    for (input) |byte| value = (value << 8) | @as(u64, byte);
    return value;
}

fn enumFromInt(comptime Enum: type, value: @typeInfo(Enum).@"enum".tag_type) ?Enum {
    const info = @typeInfo(Enum).@"enum";
    inline for (info.field_values) |field_value| {
        if (value == field_value) return @fromBackingInt(@intCast(value));
    }
    return null;
}

fn advance(value: *u64) void {
    value.* = std.math.add(u64, value.*, 1) catch @panic("protocol revision exhausted");
}

test "header round trips and rejects framing ambiguity" {
    var bytes: [header_bytes]u8 = undefined;
    try encodeHeader(&bytes, .{ .kind = .observe, .payload_len = 1234 });
    const decoded = try decodeHeader(&bytes);
    try std.testing.expectEqual(Kind.observe, decoded.kind);
    try std.testing.expectEqual(@as(u32, 1234), decoded.payload_len);

    var invalid = bytes;
    invalid[6] = 1;
    try std.testing.expectError(error.InvalidReservedBits, decodeHeader(&invalid));
    invalid = bytes;
    invalid[5] = 0xff;
    try std.testing.expectError(error.UnknownKind, decodeHeader(&invalid));
}

test "wire integers round trip beyond one byte" {
    var header_bytes_out: [header_bytes]u8 = undefined;
    try encodeHeader(&header_bytes_out, .{ .kind = .snapshot_data, .payload_len = 0x00f1_a2b3 });
    const header = try decodeHeader(&header_bytes_out);
    try std.testing.expectEqual(@as(u32, 0x00f1_a2b3), header.payload_len);

    var hello_bytes: [payload_bytes.hello]u8 = undefined;
    const hello = Hello{
        .min_version = 0x0123,
        .max_version = 0x4567,
        .features = 0xf123_4567_89ab_cdef,
    };
    encodeHello(&hello_bytes, hello);
    const decoded_hello = try decodeHello(&hello_bytes);
    try std.testing.expectEqual(hello.min_version, decoded_hello.min_version);
    try std.testing.expectEqual(hello.max_version, decoded_hello.max_version);
    try std.testing.expectEqual(hello.features, decoded_hello.features);

    var resize_bytes: [payload_bytes.resize]u8 = undefined;
    encodeResize(&resize_bytes, .{ .rows = 512, .columns = 1025 });
    const resize = try decodeResize(&resize_bytes);
    try std.testing.expectEqual(@as(u16, 512), resize.rows);
    try std.testing.expectEqual(@as(u16, 1025), resize.columns);
}

test "grid_v1 snapshot begin bytes stay frozen" {
    var encoded: [payload_bytes.snapshot_begin]u8 = undefined;
    encodeSnapshotBegin(&encoded, .{
        .revision = 0x0102_0304_0506_0708,
        .terminal_revision = 0x1112_1314_1516_1718,
        .history_offset = 0x2122_2324,
        .history_count = 0x3132_3334,
        .history_row_base = 0x4142_4344,
        .rows = 0x5152,
        .columns = 0x6162,
        .cursor_row = 0x7172,
        .cursor_column = 0x8182,
        .cursor_shape = 0x91,
        .cursor_visible = true,
        .cursor_blink = true,
        .alternate_screen = true,
        .stream_closed = true,
        .child_exited = true,
        .leader_present = true,
        .you_are_leader = true,
    });
    try std.testing.expectEqualSlices(u8, &.{
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x00, 0x01, 0x21, 0x22, 0x23, 0x24, 0x31, 0x32,
        0x33, 0x34, 0x41, 0x42, 0x43, 0x44, 0x51, 0x52,
        0x61, 0x62, 0x71, 0x72, 0x81, 0x82, 0x91, 0x7f,
    }, &encoded);
}

test "text_v1 record and color grammar is exact and hostile-safe" {
    var record: [text_v1.record_header_bytes]u8 = undefined;
    encodeTextRecordHeader(&record, .{ .kind = .row, .payload_len = 0x0102_0304 });
    try std.testing.expectEqualSlices(u8, &.{
        0x02, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
    }, &record);
    const decoded_record = try decodeTextRecordHeader(&record);
    try std.testing.expectEqual(TextRecordKind.row, decoded_record.kind);
    try std.testing.expectEqual(@as(u32, 0x0102_0304), decoded_record.payload_len);
    var bad_record = record;
    bad_record[2] = 1;
    try std.testing.expectError(error.InvalidPayload, decodeTextRecordHeader(&bad_record));
    bad_record = record;
    bad_record[0] = 0xff;
    try std.testing.expectError(error.InvalidPayload, decodeTextRecordHeader(&bad_record));

    var color: [text_v1.color_bytes]u8 = undefined;
    try encodeTextColor(&color, .{ .kind = .rgb, .value = 0x00ab_cdef });
    try std.testing.expectEqualSlices(u8, &.{ 2, 0, 0xab, 0xcd, 0xef }, &color);
    try std.testing.expectEqualDeep(
        TextColor{ .kind = .rgb, .value = 0x00ab_cdef },
        try decodeTextColor(&color),
    );
    try std.testing.expectError(
        error.InvalidPayload,
        encodeTextColor(&color, .{ .kind = .default, .value = 1 }),
    );
    try std.testing.expectError(
        error.InvalidPayload,
        encodeTextColor(&color, .{ .kind = .indexed, .value = 256 }),
    );
    color = .{ 2, 1, 0, 0, 0 };
    try std.testing.expectError(error.InvalidPayload, decodeTextColor(&color));
}

test "typed key grammar is exact and rejects noncanonical payloads" {
    const value = KeyInput{
        .kind = .unicode,
        .key_value = 'a',
        .action = .repeat,
        .modifiers = typed_input.modifiers.shift | typed_input.modifiers.control,
        .shifted = 'A',
        .alternate = 0x00e4,
        .legacy_text = "\x1ba",
        .text = "A",
    };
    var storage: [64]u8 = undefined;
    const encoded = try encodeKeyInput(&storage, value);
    try std.testing.expectEqualSlices(u8, &.{
        0x02, 0x02, 0x05, 0x03,
        0x00, 0x00, 0x00, 0x61,
        0x00, 0x00, 0x00, 0x41,
        0x00, 0x00, 0x00, 0xe4,
        0x00, 0x02, 0x00, 0x01,
        0x1b, 0x61, 0x41,
    }, encoded);
    const decoded = try decodeKeyInput(encoded);
    try std.testing.expectEqual(value.kind, decoded.kind);
    try std.testing.expectEqual(value.key_value, decoded.key_value);
    try std.testing.expectEqual(value.action, decoded.action);
    try std.testing.expectEqual(value.modifiers, decoded.modifiers);
    try std.testing.expectEqual(value.shifted, decoded.shifted);
    try std.testing.expectEqual(value.alternate, decoded.alternate);
    try std.testing.expectEqualStrings(value.legacy_text, decoded.legacy_text);
    try std.testing.expectEqualStrings(value.text, decoded.text);

    var invalid = storage;
    invalid[0] = 0xff;
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(invalid[0..encoded.len]));
    invalid = storage;
    invalid[1] = 0;
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(invalid[0..encoded.len]));
    invalid = storage;
    invalid[3] = 0;
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(invalid[0..encoded.len]));
    invalid = storage;
    invalid[4] = 0;
    invalid[5] = 0;
    invalid[6] = 0xd8;
    invalid[7] = 0x00;
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(invalid[0..encoded.len]));
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(encoded[0 .. encoded.len - 1]));

    var named_storage: [typed_input.key_header_bytes]u8 = undefined;
    const named = try encodeKeyInput(&named_storage, .{
        .kind = .named,
        .key_value = @backingInt(InputKeyName.up),
        .action = .press,
    });
    named_storage[7] = 59;
    try std.testing.expectError(error.InvalidPayload, decodeKeyInput(named));

    const bad_text = [_]u8{0xff};
    try std.testing.expectError(error.InvalidPayload, keyInputBytes(.{
        .kind = .unicode,
        .key_value = 'x',
        .action = .press,
        .text = &bad_text,
    }));
    var maximum_legacy: [typed_input.maximum_legacy_key_bytes]u8 = @splat('x');
    try std.testing.expectEqual(
        typed_input.key_header_bytes + maximum_legacy.len,
        try keyInputBytes(.{
            .kind = .unicode,
            .key_value = 'x',
            .action = .press,
            .legacy_text = &maximum_legacy,
        }),
    );
    var oversized_legacy: [typed_input.maximum_legacy_key_bytes + 1]u8 = @splat('x');
    try std.testing.expectError(error.InvalidPayload, keyInputBytes(.{
        .kind = .unicode,
        .key_value = 'x',
        .action = .press,
        .legacy_text = &oversized_legacy,
    }));
    var tiny: [typed_input.key_header_bytes - 1]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, encodeKeyInput(&tiny, .{
        .kind = .unicode,
        .key_value = 0,
        .action = .press,
    }));
}

test "typed mouse and focus grammars are exact and hostile-safe" {
    const value = MouseInput{
        .kind = .move,
        .button = .none,
        .modifiers = typed_input.modifiers.alt,
        .buttons_down = 0b101,
        .row = -2,
        .column = 0x1234,
        .pixel_x = 0x0102_0304,
        .pixel_y = 0xa1a2_a3a4,
    };
    var encoded: [typed_input.mouse_bytes]u8 = undefined;
    try encodeMouseInput(&encoded, value);
    try std.testing.expectEqualSlices(u8, &.{
        0x03, 0x00, 0x02, 0x05,
        0xff, 0xff, 0xff, 0xfe,
        0x12, 0x34, 0x01, 0x01,
        0x02, 0x03, 0x04, 0xa1,
        0xa2, 0xa3, 0xa4,
    }, &encoded);
    try std.testing.expectEqualDeep(value, try decodeMouseInput(&encoded));

    var invalid = encoded;
    invalid[0] = 0;
    try std.testing.expectError(error.InvalidPayload, decodeMouseInput(&invalid));
    invalid = encoded;
    invalid[1] = 0xff;
    try std.testing.expectError(error.InvalidPayload, decodeMouseInput(&invalid));
    invalid = encoded;
    invalid[3] = 0x80;
    try std.testing.expectError(error.InvalidPayload, decodeMouseInput(&invalid));
    invalid = encoded;
    invalid[10] = 0;
    try std.testing.expectError(error.InvalidPayload, decodeMouseInput(&invalid));
    try std.testing.expectError(error.InvalidPayload, encodeMouseInput(&encoded, .{
        .kind = .press,
        .button = .left,
        .row = 0,
        .column = 0,
        .pixel_x = 1,
    }));

    var focus: [typed_input.focus_bytes]u8 = undefined;
    encodeFocusInput(&focus, .in);
    try std.testing.expectEqualSlices(u8, &.{1}, &focus);
    try std.testing.expectEqual(InputFocus.in, try decodeFocusInput(&focus));
    focus[0] = 3;
    try std.testing.expectError(error.InvalidPayload, decodeFocusInput(&focus));
}

test "interaction state snapshot is fixed and rejects reserved drift" {
    var encoded: [payload_bytes.interaction_state_snapshot]u8 = undefined;
    encodeInteractionStateSnapshot(&encoded, .{
        .terminal_revision = 0x0102_0304_0506_0708,
        .keyboard_action_mode = true,
        .auto_repeat = false,
        .newline_mode = true,
        .application_cursor_keys = true,
        .application_keypad = true,
        .meta_sends_escape = true,
        .report_key_up = true,
        .bracketed_paste = true,
        .focus_reporting = true,
        .termios_signals = true,
        .alternate_scroll = true,
        .paste_events = true,
        .inband_resize_notifications = true,
        .mouse_tracking = .any_event,
        .mouse_protocol = .sgr_pixel,
        .modify_other_keys = -1,
        .kitty_keyboard_flags = 0x7f,
        .key_format_resource_4 = 0x1234,
        .pointer_mode = 3,
    });
    try std.testing.expectEqualSlices(u8, &.{
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x00, 0x00, 0x1f, 0xfd, 0x04, 0x03, 0xff, 0x7f,
        0x12, 0x34, 0x03, 0x00,
    }, &encoded);
    const decoded = try decodeInteractionStateSnapshot(&encoded);
    try std.testing.expect(decoded.keyboard_action_mode);
    try std.testing.expect(!decoded.auto_repeat);
    try std.testing.expect(decoded.bracketed_paste);
    try std.testing.expectEqual(@as(i8, -1), decoded.modify_other_keys);
    try std.testing.expectEqual(InteractionMouseProtocol.sgr_pixel, decoded.mouse_protocol);
    var bad = encoded;
    bad[19] = 1;
    try std.testing.expectError(error.InvalidPayload, decodeInteractionStateSnapshot(&bad));
    bad = encoded;
    bad[15] = 0x80;
    try std.testing.expectError(error.InvalidPayload, decodeInteractionStateSnapshot(&bad));
}

test "version negotiation is explicit before protocol v1" {
    try std.testing.expectEqual(@as(?u16, 1), negotiateVersion(.{}));
    try std.testing.expectEqual(@as(?u16, 1), negotiateVersion(.{ .min_version = 0, .max_version = 2 }));
    try std.testing.expectEqual(@as(?u16, null), negotiateVersion(.{ .min_version = 2, .max_version = 3 }));
    try std.testing.expectEqual(@as(?u16, null), negotiateVersion(.{ .min_version = 2, .max_version = 1 }));
    try std.testing.expectEqual(supported_features, negotiateFeatures(.{}));
    try std.testing.expectEqual(
        feature(.resize_leader) | feature(.typed_input),
        negotiateFeatures(.{
            .features = feature(.resize_leader) | feature(.typed_input),
        }),
    );
}

test "resize leadership is explicit and disappears with its client" {
    var authority: ResizeAuthority = .{};
    try std.testing.expect(authority.leader() == null);
    try std.testing.expect(!authority.mayResize(7));

    const before = authority.revision;
    try std.testing.expect(authority.assign(7));
    try std.testing.expectEqual(before + 1, authority.revision);
    try std.testing.expect(authority.mayResize(7));
    try std.testing.expect(!authority.mayResize(8));
    try std.testing.expect(!authority.assign(7));

    try std.testing.expect(!authority.disconnected(8));
    try std.testing.expect(authority.disconnected(7));
    try std.testing.expect(authority.leader() == null);
    try std.testing.expect(!authority.mayResize(7));
}
