//! Owns the compile-time parser state transition table.

const std = @import("std");

/// Names every state in the generated VT parser automaton.
pub const ParseState = enum {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_param,
    csi_intermediate,
    csi_ignore,
    osc_string,
    dcs_entry,
    dcs_param,
    dcs_intermediate,
    dcs_ignore,
    dcs_passthrough,
    sos_pm_apc_string,
};

/// Names the byte action performed while crossing a parser transition.
pub const TransitionAction = enum {
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

/// Pairs the next parser state with its transition action.
pub const Transition = struct {
    state: ParseState,
    action: TransitionAction,
};

/// Provides the compile-time-complete byte-by-state transition table.
pub const table = genTable();

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
    range(result, 0x80, 0xFF, .ground, .ground, .ground);
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
            final[i][j] = result[i][j] orelse transition(@enumFromInt(j), .none);
        }
    }
    return final;
}

fn single(t: *OptionalTable, c: u8, s0: ParseState, s1: ParseState, a: TransitionAction) void {
    t[c][@intFromEnum(s0)] = transition(s1, a);
}

fn range(t: *OptionalTable, from: u8, to: u8, s0: ParseState, s1: ParseState, a: TransitionAction) void {
    var i = from;
    while (i <= to) : (i += 1) {
        single(t, i, s0, s1, a);
        if (i == to) break;
    }
}

fn transition(state: ParseState, action: TransitionAction) Transition {
    return .{ .state = state, .action = action };
}
