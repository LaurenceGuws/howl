//! Routes parsed CSI commands to the semantic event family that owns their meaning.

const csi_params = @import("csi_params.zig");
const events = @import("semantic_event.zig");
const intermediate = @import("csi_intermediate.zig");
const leader = @import("csi_leader.zig");
const plain = @import("csi_plain.zig");
const private = @import("csi_private.zig");

const SemanticEvent = events.SemanticEvent;
const CsiSeparatorList = csi_params.CsiSeparatorList;

/// Routes one completed borrowed CSI sequence; unsupported combinations return null.
pub fn process(final: u8, params: []const i32, separators: CsiSeparatorList, leader_byte: u8, is_private: bool, intermediates: []const u8) ?SemanticEvent {
    if (is_private) return private.process(final, params, leader_byte, intermediates);
    if (leader_byte != 0) return leader.process(final, params, leader_byte, intermediates);
    if (intermediate.process(final, params, intermediates)) |event| return event;
    return plain.process(final, params, separators, intermediates);
}
