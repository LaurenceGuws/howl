//! Bounded, per-family terminal consequences.

const std = @import("std");

const ClipboardRequestOwned = struct {
    generation: u64,
    raw: []u8,
    selection_len: u8,
    kind: ClipboardRequestKind,
    protocol: ClipboardProtocol,

    fn view(self: *const ClipboardRequestOwned) ClipboardRequestView {
        return .{
            .generation = self.generation,
            .selection = self.raw[0..self.selection_len],
            .payload = self.raw,
            .kind = self.kind,
            .protocol = self.protocol,
        };
    }
};

/// Classifies one retained clipboard occurrence.
pub const ClipboardRequestKind = enum { set, query, packet };
/// Identifies the protocol governing one clipboard payload.
pub const ClipboardProtocol = enum { osc52, kitty_5522 };

/// Borrows one retained clipboard occurrence until owner mutation.
pub const ClipboardRequestView = struct {
    /// Monotonic identity advancing for every accepted operation, including repeated bytes.
    generation: u64,
    /// Borrows exact OSC 52 selection bytes; empty selection leaves the choice to embedder policy.
    selection: []const u8,
    /// Borrows the exact protocol payload for caller parsing and policy.
    payload: []const u8,
    /// Distinguishes OSC 52 replacement/query operations from one Kitty packet.
    kind: ClipboardRequestKind,
    /// Identifies the framing and semantics governing `payload`.
    protocol: ClipboardProtocol,
};

/// Reports allocation failure or an exact family bound.
pub const Error = error{ OutOfMemory, ConsequenceLimit };
/// Reports an identity that is not the current global head.
const ConsumeError = error{StaleIdentity};

/// OSC 52 is unchunked; retain at most the parser's 1 MiB clipboard packet.
const clipboard_max_bytes: u32 = 1024 * 1024;
/// Maximum retained packet accepted by Kitty clipboard and file-transfer owners.
/// Terminal proves this remains equal to the parser's chunk-control boundary.
pub const retained_packet_bytes_max: u32 = 8 * 1024;
/// Bounds one ordered clipboard burst while the caller applies access policy.
const clipboard_capacity: u8 = 8;
/// Bounds aggregate bytes retained across configuration, delegated protocol, and caller-directed DCS consequences.
const dcs_payload_max_bytes: u32 = 2 * 1024;
// Holds the nine-command Kitty family, three iTerm2 protocol families, and a bounded mixed-family burst.
const dcs_payload_capacity: u8 = 16;
// Bounds one ordered APC, PM, and SOS fallback burst within the same metadata scale.
const string_payload_capacity: u8 = 32;
/// Bounds one retained consequence payload owned by this composition state.
const consequence_payload_max_bytes: u32 = 1024;
// Bounds one notification, focus, or attention burst while a caller applies policy.
const notification_capacity: u8 = 8;
const bell_capacity: u8 = 32;
const legacy_control_capacity: u8 = 16;
// Bounds one pointer-request burst while a caller applies validation and presentation policy.
const pointer_shape_capacity: u8 = 8;
// Bounds one opaque file-transfer burst while its caller applies policy and storage.
const file_transfer_capacity: u8 = 8;

/// Identifies one ordered caller-neutral notification consequence.
pub const NotificationKind = enum {
    message,
    steal_focus,
    request_attention,
};

/// Borrows one caller-neutral notification, focus, or attention occurrence until terminal mutation.
pub const Notification = struct {
    /// Monotonic identity advancing for every accepted occurrence, including repeated values.
    generation: u64,
    /// Selects message presentation, focus admission, or attention policy.
    kind: NotificationKind,
    /// Original OSC command identifying the protocol family.
    command: u16,
    /// Raw bounded message body or attention argument; interpretation belongs to the caller.
    payload: []const u8,
};

// Owns one bounded notification-consequence queue slot without allocation.
const NotificationOwned = struct {
    generation: u64,
    kind: NotificationKind,
    command: u16,
    payload_len: u16,
    payload: [consequence_payload_max_bytes]u8,

    fn view(self: *const NotificationOwned) Notification {
        return .{
            .generation = self.generation,
            .kind = self.kind,
            .command = self.command,
            .payload = self.payload[0..self.payload_len],
        };
    }
};

/// Borrows one raw OSC 22 pointer-shape request until terminal mutation.
pub const PointerShapeRequest = struct {
    /// Monotonic identity advancing for every accepted request, including repeated bytes.
    generation: u64,
    /// Orders this request against terminal resets that clear both stacks.
    reset_generation: u64,
    /// Retains the screen bank active when this ordered request was accepted.
    alternate_screen: bool,
    /// Raw bounded shape, stack operation, or query; interpretation and replies belong to the caller.
    payload: []const u8,
};

// Owns one bounded pointer-request queue slot without allocation.
const PointerShapeOwned = struct {
    generation: u64,
    reset_generation: u64,
    alternate_screen: bool,
    payload_len: u16,
    payload: [consequence_payload_max_bytes]u8,

    fn view(self: *const PointerShapeOwned) PointerShapeRequest {
        return .{
            .generation = self.generation,
            .reset_generation = self.reset_generation,
            .alternate_screen = self.alternate_screen,
            .payload = self.payload[0..self.payload_len],
        };
    }
};

/// Identifies the opaque file-transfer grammar governing one retained packet.
pub const FileTransferProtocol = enum { iterm2_1337, kitty_5113 };

/// Borrows one ordered file-transfer packet until terminal mutation.
pub const FileTransferPacket = struct {
    /// Monotonic identity advancing for every retained packet, including repeated bytes.
    generation: u64,
    /// Selects the protocol whose caller layer interprets `payload`.
    protocol: FileTransferProtocol,
    /// Preserves the exact bounded command payload without executing embedder policy.
    payload: []const u8,
};

const FileTransferPacketOwned = struct {
    generation: u64,
    protocol: FileTransferProtocol,
    payload: []u8,

    fn view(self: *const FileTransferPacketOwned) FileTransferPacket {
        return .{ .generation = self.generation, .protocol = self.protocol, .payload = self.payload };
    }
};

const drag_drop_capacity: u8 = 16;
const drag_drop_packet_max_bytes: u32 = 4096;
const drag_drop_aggregate_max_bytes: u32 = 32 * 1024;

/// Classifies one syntactically valid Kitty OSC 72 command from the child.
pub const DragDropCommandKind = enum {
    enable,
    disable,
    accept,
    request,
    complete,
    query,
    continuation,
    unsupported,
};

/// Borrows one ordered, parsed Kitty OSC 72 command until terminal mutation.
pub const DragDropCommandView = struct {
    /// Monotonic occurrence identity never reused during one terminal lifetime.
    generation: u64,
    /// Selects the supported incoming-drop command or an explicitly unsupported family.
    kind: DragDropCommandKind,
    /// Preserves the protocol type byte for exact unsupported-family policy.
    command: u8,
    /// Retains Kitty's optional multiplexer identity.
    client_id: ?u32,
    /// Retains the chunk continuation flag.
    more: bool,
    /// Retains the requested or completed operation.
    operation: ?u2,
    /// Retains the one-based offered MIME index for a data request.
    index: ?u32,
    /// Reports a remote-file or directory request excluded from Howl policy.
    remote: bool,
    /// Borrows the exact bounded payload bytes.
    payload: []const u8,
};

const DragDropCommandOwned = struct {
    generation: u64,
    kind: DragDropCommandKind,
    command: u8,
    client_id: ?u32,
    more: bool,
    operation: ?u2,
    index: ?u32,
    remote: bool,
    payload: []u8,

    fn view(self: *const DragDropCommandOwned) DragDropCommandView {
        return .{
            .generation = self.generation,
            .kind = self.kind,
            .command = self.command,
            .client_id = self.client_id,
            .more = self.more,
            .operation = self.operation,
            .index = self.index,
            .remote = self.remote,
            .payload = self.payload,
        };
    }
};

/// Names one caller-neutral CSI-t request for an embedder to interpret.
pub const ContainerRequest = union(enum) {
    deiconify,
    iconify,
    move: struct { x: u32, y: u32 },
    resize_pixels: struct { height: u32, width: u32 },
    raise,
    lower,
    resize_rows: u8,
    resize_columns: enum(u8) { columns_80 = 80, columns_132 = 132 },
    resize_cells: struct { rows: u32, cols: u32 },
    report_state,
    report_position,
    report_screen_cells,
    report_icon_title,
};

// Bounds one FIFO burst while a caller applies policy or supplies query values.
const container_request_capacity: u8 = 32;

/// Borrows one accepted container request until head consumption.
pub const ContainerOccurrence = struct {
    /// Monotonic identity advancing for every accepted request, including repeated values.
    generation: u64,
    /// Exact bounded operation and arguments; execution and authorization belong to the caller.
    request: ContainerRequest,
};

// Bounds one burst of identical caller color-preference queries without allocation.
const color_preference_query_capacity: u8 = 16;

/// Preserves one ANSI or DEC media-copy command for caller printing policy.
pub const MediaCopyRequest = struct {
    /// Distinguishes `CSI ? Ps i` from the ordinary ANSI command.
    private: bool,
    /// Retains the exact bounded scalar parameter accepted from the child.
    parameter: u16,
};

// Bounds one print-command burst while a caller performs potentially slow policy.
const media_copy_capacity: u8 = 8;

/// Borrows one accepted media-copy command until its queue head is consumed.
pub const MediaCopyOccurrence = struct {
    /// Monotonic identity advancing for every command, including repeated values.
    generation: u64,
    /// Exact command family and parameter retained for caller interpretation.
    request: MediaCopyRequest,
};

comptime {
    std.debug.assert(notification_capacity > 0);
    std.debug.assert(pointer_shape_capacity > 0);
    std.debug.assert(file_transfer_capacity > 0);
    std.debug.assert(clipboard_capacity > 0);
    std.debug.assert(@sizeOf(NotificationOwned) <= consequence_payload_max_bytes + 16);
    std.debug.assert(@sizeOf(PointerShapeOwned) <= consequence_payload_max_bytes + 24);
    std.debug.assert(dcs_payload_max_bytes > 0);
    const total_capacity: u16 =
        clipboard_capacity + notification_capacity + pointer_shape_capacity +
        file_transfer_capacity + drag_drop_capacity + container_request_capacity +
        color_preference_query_capacity + media_copy_capacity + bell_capacity +
        legacy_control_capacity + dcs_payload_capacity + string_payload_capacity;
    std.debug.assert(total_capacity <= std.math.maxInt(u16));
}

// Converts a slice length after asserting it fits the protocol-owned u32 domain.
fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

fn ensureRetainedBound(len: u32, max_len: u32) Error!void {
    if (len > max_len) return error.ConsequenceLimit;
}

/// Identifies one retained configuration, delegated protocol, or caller-directed DCS consequence family.
pub const DcsPayloadKind = enum {
    xtsettcap,
    decudk,
    decaupss,
    iterm_tmux_hook,
    iterm_ssh_hook,
    iterm_tmux_wrap,
    kitty_remote_command,
    kitty_overlay_ready,
    kitty_result,
    kitty_print,
    kitty_echo,
    kitty_ssh,
    kitty_askpass,
    kitty_clone,
    kitty_edit,
};

/// Borrows the FIFO-head configuration, delegated protocol, or caller-directed DCS consequence.
/// Its payload remains valid until terminal mutation or matching consumption.
pub const DcsPayloadOccurrence = struct {
    /// Monotonic identity advancing for every retained consequence, including repeated bytes.
    generation: u64,
    /// Identifies the exact DCS consequence family owning `payload`.
    kind: DcsPayloadKind,
    /// Borrows the exact bounded family payload until terminal mutation.
    payload: []const u8,
};

/// Identifies one generic string-control family delegated to the embedding caller.
pub const StringPayloadKind = enum { apc, pm, sos };

/// Borrows one ordered generic string-control payload until consumption.
pub const StringPayloadOccurrence = struct {
    /// Monotonic identity advancing for every retained control, including repeated bytes.
    generation: u64,
    /// Identifies the framing family that carried `payload`.
    kind: StringPayloadKind,
    /// Borrows exact bounded payload bytes until terminal mutation.
    payload: []const u8,
};

/// Admits one parsed generic string-control payload.
pub const StringInput = struct {
    kind: StringPayloadKind,
    payload: []const u8,
};

/// Admits one parsed DCS payload.
pub const DcsInput = struct {
    kind: DcsPayloadKind,
    payload: []const u8,
};

/// Identifies a legacy terminal mode transition retained for caller observation.
pub const LegacyControlKind = enum {
    tek_point_plot,
    tek_graph,
    tek_incremental_plot,
    tek_alpha,
    tek_copy,
    tek_special_point_plot,
    tek_write_thru_short_dashed,
    hp_memory_lock,
};

/// Copies one ordered legacy terminal-mode transition.
pub const LegacyControlOccurrence = struct {
    /// Monotonic identity shared with every retained consequence family.
    generation: u64,
    /// Identifies the child-requested legacy terminal mode.
    kind: LegacyControlKind,
};

/// Admits one parsed Kitty drag-and-drop command.
const DragDropInput = struct { kind: DragDropCommandKind, command: u8, client_id: ?u32 = null, more: bool = false, operation: ?u2 = null, index: ?u32 = null, remote: bool = false, payload: []const u8 };

/// Borrows the global FIFO head across every consequence family.
pub const Consequence = union(enum) {
    clipboard: ClipboardRequestView,
    notification: Notification,
    pointer_shape: PointerShapeRequest,
    file_transfer: FileTransferPacket,
    drag_drop: DragDropCommandView,
    container: ContainerOccurrence,
    color_preference: u64,
    media_copy: MediaCopyOccurrence,
    bell: u64,
    legacy_control: LegacyControlOccurrence,
    dcs: DcsPayloadOccurrence,
    string: StringPayloadOccurrence,

    /// Returns the process-lifetime occurrence identity.
    pub fn generation(self: Consequence) u64 {
        return switch (self) {
            .color_preference, .bell => |value| value,
            inline else => |value| value.generation,
        };
    }
};

/// Owns bounded per-family queues under one monotonic identity sequence.
pub const State = struct {
    // Heap-backed consequences are bounded before allocation. Configuration,
    // delegated protocol, and caller-directed DCS families share count and aggregate-byte bounds.
    const DcsPayloadOwned = struct {
        generation: u64,
        kind: DcsPayloadKind,
        payload: []u8,

        fn view(self: *const DcsPayloadOwned) DcsPayloadOccurrence {
            return .{ .generation = self.generation, .kind = self.kind, .payload = self.payload };
        }
    };

    const StringPayloadOwned = struct {
        generation: u64,
        kind: StringPayloadKind,
        payload: []u8,

        fn view(self: *const StringPayloadOwned) StringPayloadOccurrence {
            return .{ .generation = self.generation, .kind = self.kind, .payload = self.payload };
        }
    };

    allocator: std.mem.Allocator,
    consequence_generation: u64 = 0,
    clipboard_requests: [clipboard_capacity]ClipboardRequestOwned = undefined,
    clipboard_requests_start: u8 = 0,
    clipboard_requests_count: u8 = 0,
    clipboard_retained_bytes: u32 = 0,
    notifications: [notification_capacity]NotificationOwned = undefined,
    notifications_start: u8 = 0,
    notifications_count: u8 = 0,
    pointer_shape_reset_generation: u64 = 1,
    pointer_shapes: [pointer_shape_capacity]PointerShapeOwned = undefined,
    pointer_shapes_start: u8 = 0,
    pointer_shapes_count: u8 = 0,
    file_transfer_packets: [file_transfer_capacity]FileTransferPacketOwned = undefined,
    file_transfer_start: u8 = 0,
    file_transfer_count: u8 = 0,
    drag_drop_commands: [drag_drop_capacity]DragDropCommandOwned = undefined,
    drag_drop_start: u8 = 0,
    drag_drop_count: u8 = 0,
    drag_drop_retained_bytes: u32 = 0,
    container_requests: [container_request_capacity]ContainerOccurrence = undefined,
    container_requests_start: u8 = 0,
    container_requests_count: u8 = 0,
    color_preference_queries: [color_preference_query_capacity]u64 = undefined,
    color_preference_query_start: u8 = 0,
    color_preference_query_count: u8 = 0,
    media_copy_requests: [media_copy_capacity]MediaCopyOccurrence = undefined,
    media_copy_start: u8 = 0,
    media_copy_count: u8 = 0,
    bells: [bell_capacity]u64 = undefined,
    bells_start: u8 = 0,
    bells_count: u8 = 0,
    legacy_controls: [legacy_control_capacity]LegacyControlOccurrence = undefined,
    legacy_controls_start: u8 = 0,
    legacy_controls_count: u8 = 0,
    dcs_payloads: [dcs_payload_capacity]DcsPayloadOwned = undefined,
    dcs_payloads_start: u8 = 0,
    dcs_payloads_count: u8 = 0,
    dcs_retained_bytes: u32 = 0,
    string_payloads: [string_payload_capacity]StringPayloadOwned = undefined,
    string_payloads_start: u8 = 0,
    string_payloads_count: u8 = 0,
    string_retained_bytes: u32 = 0,

    /// Initialize empty consequence state borrowing `allocator` until deinit.
    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator };
    }

    /// Releases every retained allocation through the initializer allocator.
    pub fn deinit(self: *State) void {
        for (0..self.clipboard_requests_count) |offset| {
            const index = (@as(usize, self.clipboard_requests_start) + offset) % clipboard_capacity;
            self.allocator.free(self.clipboard_requests[index].raw);
        }
        for (0..self.file_transfer_count) |offset| {
            const index = (@as(usize, self.file_transfer_start) + offset) % file_transfer_capacity;
            self.allocator.free(self.file_transfer_packets[index].payload);
        }
        for (0..self.drag_drop_count) |offset| {
            const index = (@as(usize, self.drag_drop_start) + offset) % drag_drop_capacity;
            self.allocator.free(self.drag_drop_commands[index].payload);
        }
        for (0..self.dcs_payloads_count) |offset| {
            const index = (@as(usize, self.dcs_payloads_start) + offset) % dcs_payload_capacity;
            self.allocator.free(self.dcs_payloads[index].payload);
        }
        for (0..self.string_payloads_count) |offset| {
            const index = (@as(usize, self.string_payloads_start) + offset) % string_payload_capacity;
            self.allocator.free(self.string_payloads[index].payload);
        }
    }

    /// Records a terminal reset without discarding previously retained occurrences.
    pub fn resetTerminal(self: *State) void {
        self.pointer_shape_reset_generation = std.math.add(u64, self.pointer_shape_reset_generation, 1) catch
            @panic("pointer reset identity exhausted");
    }

    /// Returns the globally earliest retained occurrence, or null when empty.
    pub fn head(self: *const State) ?Consequence {
        var result: ?Consequence = null;
        considerHead(&result, if (self.pendingClipboardRequest()) |value| .{ .clipboard = value } else null);
        considerHead(&result, if (self.notificationView()) |value| .{ .notification = value } else null);
        considerHead(&result, if (self.pointerShapeView()) |value| .{ .pointer_shape = value } else null);
        considerHead(&result, if (self.fileTransferHead()) |value| .{ .file_transfer = value } else null);
        considerHead(&result, if (self.dragDropHead()) |value| .{ .drag_drop = value } else null);
        considerHead(&result, if (self.containerRequestHead()) |value| .{ .container = value } else null);
        considerHead(&result, if (self.colorPreferenceQueryGeneration()) |value| .{ .color_preference = value } else null);
        considerHead(&result, if (self.mediaCopyHead()) |value| .{ .media_copy = value } else null);
        considerHead(&result, if (self.bellHead()) |value| .{ .bell = value } else null);
        considerHead(&result, if (self.legacyControlHead()) |value| .{ .legacy_control = value } else null);
        considerHead(&result, if (self.dcsPayloadHead()) |value| .{ .dcs = value } else null);
        considerHead(&result, if (self.stringPayloadHead()) |value| .{ .string = value } else null);
        return result;
    }

    /// Counts retained occurrences within the compile-time-proven u16 capacity bound.
    pub fn count(self: *const State) u16 {
        var result: u16 = 0;
        inline for (.{
            self.clipboard_requests_count,     self.notifications_count, self.pointer_shapes_count,
            self.file_transfer_count,          self.drag_drop_count,     self.container_requests_count,
            self.color_preference_query_count, self.media_copy_count,    self.bells_count,
            self.legacy_controls_count,        self.dcs_payloads_count,  self.string_payloads_count,
        }) |value| result += value;
        return result;
    }

    /// Consumes only the current global head with the exact supplied identity.
    pub fn consumeHead(self: *State, generation: u64) ConsumeError!void {
        const current = self.head() orelse return error.StaleIdentity;
        if (current.generation() != generation) return error.StaleIdentity;
        switch (current) {
            .clipboard => self.consumeClipboardRequest(),
            .notification => self.consumeNotification(),
            .pointer_shape => self.consumePointerShape(),
            .file_transfer => self.consumeFileTransfer(),
            .drag_drop => self.consumeDragDrop(),
            .container => self.consumeContainerRequestHead(),
            .color_preference => self.consumeColorPreferenceQuery(),
            .media_copy => self.consumeMediaCopy(),
            .bell => self.consumeBell(),
            .legacy_control => self.consumeLegacyControl(),
            .dcs => self.consumeDcsPayload(),
            .string => self.consumeStringPayload(),
        }
    }

    fn nextConsequenceId(self: *const State) Error!u64 {
        return std.math.add(u64, self.consequence_generation, 1) catch
            error.ConsequenceLimit;
    }

    fn commitConsequenceId(self: *State, id: u64) void {
        std.debug.assert(id == self.consequence_generation + 1);
        self.consequence_generation = id;
    }

    /// Retain one notification, focus, or attention occurrence without choosing embedder policy.
    pub fn retainNotification(
        self: *State,
        kind: NotificationKind,
        command: u16,
        payload: []const u8,
    ) Error!void {
        try ensureRetainedBound(byteCount(payload), consequence_payload_max_bytes);
        if (self.notifications_count == notification_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const index = (self.notifications_start + self.notifications_count) % notification_capacity;
        const slot = &self.notifications[index];
        @memcpy(slot.payload[0..payload.len], payload);
        self.commitConsequenceId(occurrence_id);
        slot.generation = occurrence_id;
        slot.kind = kind;
        slot.command = command;
        slot.payload_len = @intCast(payload.len);
        self.notifications_count += 1;
    }

    /// Retain one OSC 22 request without selecting a caller pointer or answering queries.
    pub fn retainPointerShape(
        self: *State,
        payload: []const u8,
        alternate_screen: bool,
    ) Error!void {
        try ensureRetainedBound(byteCount(payload), consequence_payload_max_bytes);
        if (self.pointer_shapes_count == pointer_shape_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const index = (self.pointer_shapes_start + self.pointer_shapes_count) % pointer_shape_capacity;
        const slot = &self.pointer_shapes[index];
        @memcpy(slot.payload[0..payload.len], payload);
        self.commitConsequenceId(occurrence_id);
        slot.generation = occurrence_id;
        slot.reset_generation = self.pointer_shape_reset_generation;
        slot.alternate_screen = alternate_screen;
        slot.payload_len = @intCast(payload.len);
        self.pointer_shapes_count += 1;
    }

    // Retain one opaque packet only after every queue and allocation bound succeeds.
    /// Retains one bounded opaque file-transfer packet.
    pub fn retainFileTransfer(self: *State, protocol: FileTransferProtocol, payload: []const u8) Error!void {
        try ensureRetainedBound(byteCount(payload), retained_packet_bytes_max);
        if (self.file_transfer_count == file_transfer_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const owned = try self.allocator.dupe(u8, payload);
        const index = (self.file_transfer_start + self.file_transfer_count) % file_transfer_capacity;
        self.commitConsequenceId(occurrence_id);
        self.file_transfer_packets[index] = .{
            .generation = occurrence_id,
            .protocol = protocol,
            .payload = owned,
        };
        self.file_transfer_count += 1;
    }

    fn fileTransferHead(self: *const State) ?FileTransferPacket {
        if (self.file_transfer_count == 0) return null;
        return self.file_transfer_packets[self.file_transfer_start].view();
    }

    fn consumeFileTransfer(self: *State) void {
        std.debug.assert(self.file_transfer_count > 0);
        const packet = &self.file_transfer_packets[self.file_transfer_start];
        self.allocator.free(packet.payload);
        self.file_transfer_start = (self.file_transfer_start + 1) % file_transfer_capacity;
        self.file_transfer_count -= 1;
    }

    /// Retains one parsed bounded Kitty drag-and-drop command.
    pub fn retainDragDrop(self: *State, command: DragDropInput) Error!void {
        try ensureRetainedBound(byteCount(command.payload), drag_drop_packet_max_bytes);
        if (self.drag_drop_count == drag_drop_capacity) return error.ConsequenceLimit;
        const retained = std.math.add(
            u32,
            self.drag_drop_retained_bytes,
            @intCast(command.payload.len),
        ) catch return error.ConsequenceLimit;
        if (retained > drag_drop_aggregate_max_bytes) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const payload = try self.allocator.dupe(u8, command.payload);
        const index = (self.drag_drop_start + self.drag_drop_count) % drag_drop_capacity;
        self.commitConsequenceId(occurrence_id);
        self.drag_drop_commands[index] = .{
            .generation = occurrence_id,
            .kind = command.kind,
            .command = command.command,
            .client_id = command.client_id,
            .more = command.more,
            .operation = command.operation,
            .index = command.index,
            .remote = command.remote,
            .payload = payload,
        };
        self.drag_drop_count += 1;
        self.drag_drop_retained_bytes = retained;
    }

    fn dragDropHead(self: *const State) ?DragDropCommandView {
        if (self.drag_drop_count == 0) return null;
        return self.drag_drop_commands[self.drag_drop_start].view();
    }

    fn consumeDragDrop(self: *State) void {
        std.debug.assert(self.drag_drop_count > 0);
        const command = &self.drag_drop_commands[self.drag_drop_start];
        std.debug.assert(command.payload.len <= self.drag_drop_retained_bytes);
        self.drag_drop_retained_bytes -= @intCast(command.payload.len);
        self.allocator.free(command.payload);
        self.drag_drop_start = (self.drag_drop_start + 1) % drag_drop_capacity;
        self.drag_drop_count -= 1;
    }

    /// Retain one container request occurrence without executing embedder policy.
    pub fn retainContainerRequest(self: *State, request: ContainerRequest) Error!void {
        if (self.container_requests_count == container_request_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        self.commitConsequenceId(occurrence_id);
        const index = (self.container_requests_start + self.container_requests_count) % container_request_capacity;
        self.container_requests[index] = .{ .generation = occurrence_id, .request = request };
        self.container_requests_count += 1;
    }

    fn containerRequestHead(self: *const State) ?ContainerOccurrence {
        if (self.container_requests_count == 0) return null;
        return self.container_requests[self.container_requests_start];
    }

    fn consumeContainerRequestHead(self: *State) void {
        std.debug.assert(self.container_requests_count > 0);
        self.container_requests_start = (self.container_requests_start + 1) % container_request_capacity;
        self.container_requests_count -= 1;
    }

    /// Retains one ordered color-preference query.
    pub fn retainColorPreferenceQuery(self: *State) Error!void {
        if (self.color_preference_query_count == color_preference_query_capacity)
            return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        self.commitConsequenceId(occurrence_id);
        const index = (self.color_preference_query_start + self.color_preference_query_count) %
            color_preference_query_capacity;
        self.color_preference_queries[index] = occurrence_id;
        self.color_preference_query_count += 1;
    }

    fn colorPreferenceQueryGeneration(self: *const State) ?u64 {
        if (self.color_preference_query_count == 0) return null;
        return self.color_preference_queries[self.color_preference_query_start];
    }

    fn consumeColorPreferenceQuery(self: *State) void {
        std.debug.assert(self.color_preference_query_count > 0);
        self.color_preference_query_start =
            (self.color_preference_query_start + 1) % color_preference_query_capacity;
        self.color_preference_query_count -= 1;
    }

    /// Retains one ordered media-copy request.
    pub fn retainMediaCopy(self: *State, request: MediaCopyRequest) Error!void {
        if (self.media_copy_count == media_copy_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        self.commitConsequenceId(occurrence_id);
        const index = (self.media_copy_start + self.media_copy_count) % media_copy_capacity;
        self.media_copy_requests[index] = .{ .generation = occurrence_id, .request = request };
        self.media_copy_count += 1;
    }

    fn mediaCopyHead(self: *const State) ?MediaCopyOccurrence {
        if (self.media_copy_count == 0) return null;
        return self.media_copy_requests[self.media_copy_start];
    }

    fn consumeMediaCopy(self: *State) void {
        std.debug.assert(self.media_copy_count > 0);
        self.media_copy_start = (self.media_copy_start + 1) % media_copy_capacity;
        self.media_copy_count -= 1;
    }

    fn notificationView(self: *const State) ?Notification {
        if (self.notifications_count == 0) return null;
        return self.notifications[self.notifications_start].view();
    }

    fn consumeNotification(self: *State) void {
        std.debug.assert(self.notifications_count > 0);
        self.notifications_start = (self.notifications_start + 1) % notification_capacity;
        self.notifications_count -= 1;
    }

    fn pointerShapeView(self: *const State) ?PointerShapeRequest {
        if (self.pointer_shapes_count == 0) return null;
        return self.pointer_shapes[self.pointer_shapes_start].view();
    }

    fn consumePointerShape(self: *State) void {
        std.debug.assert(self.pointer_shapes_count > 0);
        self.pointer_shapes_start = (self.pointer_shapes_start + 1) % pointer_shape_capacity;
        self.pointer_shapes_count -= 1;
    }

    /// Retain one BEL occurrence without choosing an audible or visual policy.
    pub fn ringBell(self: *State) Error!void {
        if (self.bells_count == bell_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const index = (self.bells_start + self.bells_count) % bell_capacity;
        self.commitConsequenceId(occurrence_id);
        self.bells[index] = occurrence_id;
        self.bells_count += 1;
    }

    fn bellHead(self: *const State) ?u64 {
        if (self.bells_count == 0) return null;
        return self.bells[self.bells_start];
    }

    fn consumeBell(self: *State) void {
        std.debug.assert(self.bells_count > 0);
        self.bells_start = (self.bells_start + 1) % bell_capacity;
        self.bells_count -= 1;
    }

    /// Retains one ordered legacy control transition.
    pub fn retainLegacyControl(self: *State, kind: LegacyControlKind) Error!void {
        if (self.legacy_controls_count == legacy_control_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const index = (self.legacy_controls_start + self.legacy_controls_count) %
            legacy_control_capacity;
        self.commitConsequenceId(occurrence_id);
        self.legacy_controls[index] = .{ .generation = occurrence_id, .kind = kind };
        self.legacy_controls_count += 1;
    }

    fn legacyControlHead(self: *const State) ?LegacyControlOccurrence {
        if (self.legacy_controls_count == 0) return null;
        return self.legacy_controls[self.legacy_controls_start];
    }

    fn consumeLegacyControl(self: *State) void {
        std.debug.assert(self.legacy_controls_count > 0);
        self.legacy_controls_start = (self.legacy_controls_start + 1) %
            legacy_control_capacity;
        self.legacy_controls_count -= 1;
    }

    /// Retain one valid clipboard occurrence transactionally without choosing caller access policy.

    // Retain one exact Kitty OSC 5522 packet for ordered caller parsing and policy.
    /// Retains one exact Kitty clipboard packet.
    pub fn retainKittyClipboard(self: *State, payload: []const u8) Error!void {
        try ensureRetainedBound(byteCount(payload), retained_packet_bytes_max);
        try self.admitClipboard(payload, 0, .packet, .kitty_5522);
    }

    /// Retains one already-parsed clipboard occurrence.
    pub fn admitClipboard(
        self: *State,
        payload: []const u8,
        selection_len: u8,
        kind: ClipboardRequestKind,
        protocol: ClipboardProtocol,
    ) Error!void {
        if (self.clipboard_requests_count == clipboard_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const retained_bytes = std.math.add(u32, self.clipboard_retained_bytes, byteCount(payload)) catch
            return error.ConsequenceLimit;
        if (retained_bytes > clipboard_max_bytes) return error.ConsequenceLimit;
        const owned = try self.allocator.dupe(u8, payload);
        const index = (self.clipboard_requests_start + self.clipboard_requests_count) % clipboard_capacity;
        self.commitConsequenceId(occurrence_id);
        self.clipboard_requests[index] = .{
            .generation = occurrence_id,
            .raw = owned,
            .selection_len = selection_len,
            .kind = kind,
            .protocol = protocol,
        };
        self.clipboard_requests_count += 1;
        self.clipboard_retained_bytes = retained_bytes;
    }

    /// Retain one ordered configuration, delegated protocol, or caller-directed DCS consequence.
    /// Count, byte, generation, and allocation bounds succeed before queue mutation.
    pub fn retainDcsPayload(self: *State, payload: DcsInput) Error!void {
        try ensureRetainedBound(byteCount(payload.payload), dcs_payload_max_bytes);
        if (self.dcs_payloads_count == dcs_payload_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const retained_bytes = std.math.add(u32, self.dcs_retained_bytes, byteCount(payload.payload)) catch
            return error.ConsequenceLimit;
        if (retained_bytes > dcs_payload_max_bytes) return error.ConsequenceLimit;
        const owned = try self.allocator.dupe(u8, payload.payload);
        const index = (self.dcs_payloads_start + self.dcs_payloads_count) % dcs_payload_capacity;
        self.commitConsequenceId(occurrence_id);
        self.dcs_payloads[index] = .{
            .generation = occurrence_id,
            .kind = payload.kind,
            .payload = owned,
        };
        self.dcs_payloads_count += 1;
        self.dcs_retained_bytes = retained_bytes;
    }

    fn dcsPayloadHead(self: *const State) ?DcsPayloadOccurrence {
        if (self.dcs_payloads_count == 0) return null;
        return self.dcs_payloads[self.dcs_payloads_start].view();
    }

    fn consumeDcsPayload(self: *State) void {
        std.debug.assert(self.dcs_payloads_count > 0);
        const payload = &self.dcs_payloads[self.dcs_payloads_start];
        const payload_len = byteCount(payload.payload);
        std.debug.assert(payload_len <= self.dcs_retained_bytes);
        self.allocator.free(payload.payload);
        self.dcs_retained_bytes -= payload_len;
        self.dcs_payloads_start = (self.dcs_payloads_start + 1) % dcs_payload_capacity;
        self.dcs_payloads_count -= 1;
    }

    /// Retain one generic string control after every count, byte, generation, and allocation bound succeeds.
    pub fn retainStringPayload(self: *State, payload: StringInput) Error!void {
        try ensureRetainedBound(byteCount(payload.payload), dcs_payload_max_bytes);
        if (self.string_payloads_count == string_payload_capacity) return error.ConsequenceLimit;
        const occurrence_id = try self.nextConsequenceId();
        const retained_bytes = std.math.add(u32, self.string_retained_bytes, byteCount(payload.payload)) catch
            return error.ConsequenceLimit;
        if (retained_bytes > dcs_payload_max_bytes) return error.ConsequenceLimit;
        const owned = try self.allocator.dupe(u8, payload.payload);
        const index = (self.string_payloads_start + self.string_payloads_count) % string_payload_capacity;
        self.commitConsequenceId(occurrence_id);
        self.string_payloads[index] = .{
            .generation = occurrence_id,
            .kind = payload.kind,
            .payload = owned,
        };
        self.string_payloads_count += 1;
        self.string_retained_bytes = retained_bytes;
    }

    fn stringPayloadHead(self: *const State) ?StringPayloadOccurrence {
        if (self.string_payloads_count == 0) return null;
        return self.string_payloads[self.string_payloads_start].view();
    }

    fn consumeStringPayload(self: *State) void {
        std.debug.assert(self.string_payloads_count > 0);
        const payload = &self.string_payloads[self.string_payloads_start];
        const payload_len = byteCount(payload.payload);
        std.debug.assert(payload_len <= self.string_retained_bytes);
        self.allocator.free(payload.payload);
        self.string_retained_bytes -= payload_len;
        self.string_payloads_start = (self.string_payloads_start + 1) % string_payload_capacity;
        self.string_payloads_count -= 1;
    }

    /// Borrow the FIFO-head raw clipboard set until terminal mutation.
    fn pendingClipboardSet(self: *const State) ?[]const u8 {
        const request = self.clipboardRequestHead() orelse return null;
        if (request.kind == .set) return request.raw;
        return null;
    }

    /// Borrow the FIFO-head OSC 52 operation or Kitty OSC 5522 packet.
    fn pendingClipboardRequest(self: *const State) ?ClipboardRequestView {
        const request = self.clipboardRequestHead() orelse return null;
        return request.view();
    }

    fn clipboardRequestHead(self: *const State) ?*const ClipboardRequestOwned {
        if (self.clipboard_requests_count == 0) return null;
        return &self.clipboard_requests[self.clipboard_requests_start];
    }

    // Release and consume only the FIFO head after its caller operation completes.
    fn consumeClipboardRequest(self: *State) void {
        std.debug.assert(self.clipboard_requests_count > 0);
        const request = &self.clipboard_requests[self.clipboard_requests_start];
        const request_len = byteCount(request.raw);
        std.debug.assert(request_len <= self.clipboard_retained_bytes);
        self.clipboard_retained_bytes -= request_len;
        self.allocator.free(request.raw);
        self.clipboard_requests_start = (self.clipboard_requests_start + 1) % clipboard_capacity;
        self.clipboard_requests_count -= 1;
    }
};

fn considerHead(result: *?Consequence, candidate: ?Consequence) void {
    const value = candidate orelse return;
    if (result.* == null or value.generation() < result.*.?.generation()) result.* = value;
}

test "mixed families retain one global order and reject stale consumption" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try state.ringBell();
    try state.retainNotification(.message, 9, "same");
    try state.ringBell();
    try std.testing.expectEqual(@as(u8, 3), state.count());
    try std.testing.expectEqual(@as(u64, 1), state.head().?.generation());
    try std.testing.expectError(error.StaleIdentity, state.consumeHead(2));
    try state.consumeHead(1);
    try std.testing.expectEqual(@as(u64, 2), state.head().?.generation());
    try state.consumeHead(2);
    try state.consumeHead(3);
    try std.testing.expectEqual(@as(u8, 0), state.count());
}

test "family saturation preserves the accepted FIFO" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    for (0..bell_capacity) |_| try state.ringBell();
    try std.testing.expectError(error.ConsequenceLimit, state.ringBell());
    try std.testing.expectEqual(@as(u8, bell_capacity), state.count());
    try std.testing.expectEqual(@as(u64, 1), state.head().?.generation());
}

test "every family rejects its exact queue saturation" {
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..clipboard_capacity) |_| try state.admitClipboard("", 0, .set, .osc52);
        try std.testing.expectError(error.ConsequenceLimit, state.admitClipboard("", 0, .set, .osc52));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..notification_capacity) |_| try state.retainNotification(.message, 9, "");
        try std.testing.expectError(error.ConsequenceLimit, state.retainNotification(.message, 9, ""));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..pointer_shape_capacity) |_| try state.retainPointerShape("", false);
        try std.testing.expectError(error.ConsequenceLimit, state.retainPointerShape("", false));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..file_transfer_capacity) |_| try state.retainFileTransfer(.iterm2_1337, "");
        try std.testing.expectError(error.ConsequenceLimit, state.retainFileTransfer(.iterm2_1337, ""));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..drag_drop_capacity) |_| try state.retainDragDrop(.{ .kind = .query, .command = 'q', .payload = "" });
        try std.testing.expectError(error.ConsequenceLimit, state.retainDragDrop(.{ .kind = .query, .command = 'q', .payload = "" }));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..container_request_capacity) |_| try state.retainContainerRequest(.report_state);
        try std.testing.expectError(error.ConsequenceLimit, state.retainContainerRequest(.report_state));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..color_preference_query_capacity) |_| try state.retainColorPreferenceQuery();
        try std.testing.expectError(error.ConsequenceLimit, state.retainColorPreferenceQuery());
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..media_copy_capacity) |_| try state.retainMediaCopy(.{ .private = false, .parameter = 0 });
        try std.testing.expectError(error.ConsequenceLimit, state.retainMediaCopy(.{ .private = false, .parameter = 0 }));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..legacy_control_capacity) |_| try state.retainLegacyControl(.tek_graph);
        try std.testing.expectError(error.ConsequenceLimit, state.retainLegacyControl(.tek_graph));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..dcs_payload_capacity) |_| try state.retainDcsPayload(.{ .kind = .kitty_result, .payload = "" });
        try std.testing.expectError(error.ConsequenceLimit, state.retainDcsPayload(.{ .kind = .kitty_result, .payload = "" }));
    }
    {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        for (0..string_payload_capacity) |_| try state.retainStringPayload(.{ .kind = .apc, .payload = "" });
        try std.testing.expectError(error.ConsequenceLimit, state.retainStringPayload(.{ .kind = .apc, .payload = "" }));
    }
}

fn retainDcsAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    state.retainDcsPayload(.{ .kind = .kitty_result, .payload = "result" }) catch |failure| {
        try std.testing.expectEqual(@as(u64, 0), state.consequence_generation);
        try std.testing.expectEqual(@as(u8, 0), state.dcs_payloads_count);
        try std.testing.expectEqual(@as(u32, 0), state.dcs_retained_bytes);
        return failure;
    };
    try std.testing.expectEqualStrings("result", state.head().?.dcs.payload);
}

test "allocation failure preserves DCS identity bytes and count" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainDcsAllocation, .{});
}

fn retainClipboardAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.admitClipboard("c;b2xk", 1, .set, .osc52);
    state.admitClipboard("c;bmV3", 1, .set, .osc52) catch |failure| {
        try std.testing.expectEqualStrings("c;b2xk", state.head().?.clipboard.payload);
        try std.testing.expectEqual(@as(u8, 1), state.count());
        return failure;
    };
    try std.testing.expectEqual(@as(u8, 2), state.count());
}

fn retainFileTransferAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.retainFileTransfer(.iterm2_1337, "old");
    state.retainFileTransfer(.kitty_5113, "new") catch |failure| {
        try std.testing.expectEqualStrings("old", state.head().?.file_transfer.payload);
        return failure;
    };
    try std.testing.expectEqual(@as(u8, 2), state.count());
}

fn retainDragDropAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.retainDragDrop(.{ .kind = .query, .command = 'q', .payload = "old" });
    state.retainDragDrop(.{ .kind = .enable, .command = 'a', .payload = "new" }) catch |failure| {
        try std.testing.expectEqualStrings("old", state.head().?.drag_drop.payload);
        return failure;
    };
    try std.testing.expectEqual(@as(u8, 2), state.count());
}

fn retainStringAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    state.retainStringPayload(.{ .kind = .apc, .payload = "first" }) catch |failure| {
        try std.testing.expectEqual(@as(u64, 0), state.consequence_generation);
        try std.testing.expectEqual(@as(u8, 0), state.string_payloads_count);
        try std.testing.expectEqual(@as(u32, 0), state.string_retained_bytes);
        return failure;
    };
    try std.testing.expectEqualStrings("first", state.head().?.string.payload);
}

test "allocating families preserve their accepted heads on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainClipboardAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainFileTransferAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainDragDropAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainStringAllocation, .{});
}

test "terminal reset advances pointer identity without consuming occurrences" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try state.retainPointerShape("query", false);
    const before = state.head().?.pointer_shape;
    state.resetTerminal();
    try std.testing.expectEqual(@as(u8, 1), state.count());
    try std.testing.expectEqual(before.generation, state.head().?.pointer_shape.generation);
    try std.testing.expectEqual(before.reset_generation + 1, state.pointer_shape_reset_generation);
}
