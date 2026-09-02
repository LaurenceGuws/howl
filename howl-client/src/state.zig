//! Coherent terminal interaction state for mode-aware native clients.

const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

pub const Error = client.Error || protocol.PayloadError || error{
    UnexpectedFrame,
};

pub fn get(connection: *client.Connection) Error!protocol.InteractionStateSnapshot {
    try connection.send(.interaction_state, &.{});
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .interaction_state_snapshot) return error.UnexpectedFrame;
    return protocol.decodeInteractionStateSnapshot(frame.payload);
}
