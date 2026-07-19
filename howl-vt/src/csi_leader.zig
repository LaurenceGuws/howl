//! Decodes CSI commands distinguished by a private leader byte.

const events = @import("semantic_event.zig");
const params_mod = @import("csi_params.zig");

const SemanticEvent = events.SemanticEvent;

/// Decodes one leader-qualified CSI sequence; unsupported forms return null.
pub fn process(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'f' => keyFormatChange(params),
            'q' => if (!params_mod.intermediatesHas(intermediates, ' ') and
                params_mod.paramAtOrDefault0(params, 0) == 0)
                SemanticEvent.xtversion
            else
                null,
            'm' => if (params_mod.paramAtOrDefault0(params, 0) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (params.len >= 2) params[1] else 0, 0)) } else null,
            'n' => if (params_mod.paramAtOrDefault0(params, 0) == 4) SemanticEvent.modify_other_keys_disable else null,
            'p' => pointerMode(params),
            'u' => SemanticEvent{ .kitty_keyboard_push = keyboardFlags(params) },
            else => null,
        },
        '=' => switch (final) {
            'c' => SemanticEvent.tertiary_device_attributes,
            'u' => kittyKeyboardSet(params),
            else => null,
        },
        '<' => switch (final) {
            'u' => SemanticEvent{ .kitty_keyboard_pop = params_mod.paramAtOrDefault1(params, 0) },
            else => null,
        },
        else => null,
    };
}

fn kittyKeyboardSet(params: []const i32) ?SemanticEvent {
    const raw_mode = if (params.len >= 2) params[1] else 1;
    if (raw_mode < 1 or raw_mode > 3) return null;
    return SemanticEvent{ .kitty_keyboard_set = .{
        .flags = keyboardFlags(params),
        .mode = @intCast(raw_mode),
    } };
}

fn keyboardFlags(params: []const i32) u8 {
    return @intCast(@min(@max(if (params.len != 0) params[0] else 0, 0), 0x7f));
}

fn keyFormatChange(params: []const i32) SemanticEvent {
    if (params.len == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource = params_mod.keyFormatParamAtOrDefault0(params, 0);
    if (params.len == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = params_mod.paramAtOrDefault0(params, 1) } };
}

fn pointerMode(params: []const i32) SemanticEvent {
    const value = if (params.len == 0) 1 else params_mod.paramAtOrDefault0(params, 0);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}
