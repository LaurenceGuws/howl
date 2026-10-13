//! Optional Instance-owned native foreign boundary over the exact local owner.
//! No host clocks, waits, queues, wake sources or Server/codec imports.
const instance = @import("howl_instance");
/// VT-owned native vocabulary and copied semantic projection.
pub const vt = @import("howl_vt_native");
/// Artifact-owned C declarations.
pub const c = @import("instance_native_types");
/// Validation and canonical ordered-input failures used by C and Zig host adapters.
pub const InputError = instance.InputError || vt.Error;
/// Exact local composition; never interchangeable with a headless handle.
pub const Instance = instance.Instance;

/// Converts fixed native process-group signal tags without host or queue policy.
/// Unknown tags are rejected before the caller schedules any canonical mutation.
pub fn signalFromTag(tag: u8) ?instance.Signal {
    return switch (tag) {
        c.HI_HANGUP => .hangup,
        c.HI_INTERRUPT => .interrupt,
        c.HI_RESIZE_NOTIFY => .resize_notify,
        c.HI_KILL => .kill,
        c.HI_TERMINATE => .terminate,
        else => null,
    };
}

/// Native named input conversion and canonical mutation share one implementation.
pub fn sendNamedKey(value: *Instance, key: u8, action: u8, mods: u8) InputError!void {
    try instance.input(value, try vt.namedInput(key, action, mods));
}
/// Native Unicode conversion rejects non-scalars before canonical mutation.
pub fn sendUnicodeKey(value: *Instance, scalar: u32, action: u8, mods: u8) InputError!void {
    try instance.input(value, try vt.unicodeInput(scalar, action, mods));
}
/// Native mouse conversion rejects unknown metadata before canonical mutation.
pub fn sendMouse(value: *Instance, kind: u8, button: u8, mods: u8, buttons: u8, row: i32, col: u16, pixels: u8, x: u32, y: u32) InputError!void {
    try instance.input(value, try vt.mouseInput(kind, button, mods, buttons, row, col, pixels, x, y));
}
/// Native focus conversion rejects unknown values before canonical mutation.
pub fn sendFocus(value: *Instance, focus: u8) InputError!void {
    try instance.input(value, try vt.focusInput(focus));
}

/// Native reply validation and canonical atomic exact-head reply failures.
pub const ReplyError = instance.ClipboardReplyError || instance.PointerShapeReplyError || instance.ColorPreferenceReplyError || instance.ContainerReplyError || error{ InvalidArgument, RequestMismatch };
/// Canonical exact-head acknowledgement; mandatory queries require a typed reply.
pub const consumeRequest = instance.consumeConsequence;

/// Serializes a bounded clipboard reply without consuming a non-query occurrence.
pub fn replyClipboard(value: *Instance, id: u64, text: []const u8) ReplyError!void {
    if (text.len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return error.ReplyLimit;
    if (!try instance.replyClipboard(value, id, text)) return error.RequestMismatch;
}
/// Serializes one matching pointer query reply; caller bytes are borrowed only during the call.
pub fn replyPointerShape(value: *Instance, id: u64, text: []const u8) ReplyError!void {
    if (text.len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return error.ReplyLimit;
    try instance.replyPointerShape(value, id, text);
}
/// Rejects unknown preference tags before canonical terminal mutation.
pub fn replyColorPreference(value: *Instance, id: u64, preference: u8) ReplyError!void {
    const selected: instance.ColorSchemePreference = switch (preference) {
        vt.c.HVT_COLOR_DARK => .dark,
        vt.c.HVT_COLOR_LIGHT => .light,
        else => return error.InvalidArgument,
    };
    try instance.replyColorPreference(value, id, selected);
}
/// Rejects unknown state tags before canonical typed container reply.
pub fn replyContainerState(value: *Instance, id: u64, state: u8) ReplyError!void {
    const reply: instance.ContainerReply = .{ .state = switch (state) {
        vt.c.HVT_CONTAINER_STATE_NORMAL => .normal,
        vt.c.HVT_CONTAINER_STATE_ICONIFIED => .iconified,
        else => return error.InvalidArgument,
    } };
    try instance.replyContainer(value, id, reply);
}
/// Serializes native position integers through the canonical VT reply owner.
pub fn replyContainerPosition(value: *Instance, id: u64, x: u32, y: u32) ReplyError!void {
    try instance.replyContainer(value, id, .{ .position = .{ .x = x, .y = y } });
}
/// Serializes native screen dimensions without a caller-encoded byte body.
pub fn replyContainerScreenCells(value: *Instance, id: u64, rows: u32, columns: u32) ReplyError!void {
    try instance.replyContainer(value, id, .{ .screen_cells = .{ .rows = rows, .cols = columns } });
}
/// Serializes one bounded exact icon-title reply into owner-held child reply storage.
pub fn replyContainerIconTitle(value: *Instance, id: u64, text: []const u8) ReplyError!void {
    if (text.len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return error.ReplyLimit;
    try instance.replyContainer(value, id, .{ .icon_title = text });
}
/// Declines only a matching container query, without fabricating host state.
pub const declineContainer = instance.declineContainerQuery;
