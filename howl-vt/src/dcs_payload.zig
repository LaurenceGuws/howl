//! Defines borrowed DCS payload kinds passed from streaming capture to decoding.

/// Identifies the supported DCS family owning a captured payload.
pub const DcsPayloadKind = enum {
    xtsettcap,
    decrsps,
    decudk,
    decaupss,
};

/// Borrows one complete DCS payload for immediate semantic decoding.
pub const DcsPayload = struct {
    kind: DcsPayloadKind,
    payload: []const u8,
};
