const std = @import("std");
const owned_actions = @import("../src/parser.zig");
const parser_mod = @import("../src/parser.zig");
const terminal_mod = @import("../src/terminal.zig");

const Terminal = terminal_mod.Terminal;

const OscTerminator = parser_mod.OscTerminator;
const xterm_ctlseqs = @embedFile("assets/xterm-ctlseqs.ms");

const IterationCount = u32;
const OpCount = u32;
const ChunkLen = u16;
const CaseOffset = u32;
const AssetOffset = u32;
const TextLen = u8;

fn byteCount(bytes: []const u8) CaseOffset {
    std.debug.assert(bytes.len <= std.math.maxInt(CaseOffset));
    return @intCast(bytes.len);
}

fn assetByteCount() AssetOffset {
    std.debug.assert(xterm_ctlseqs.len <= std.math.maxInt(AssetOffset));
    return @intCast(xterm_ctlseqs.len);
}

fn chunkLen(rand: std.Random, remaining: CaseOffset, max_chunk_len: ChunkLen) CaseOffset {
    return 1 + rand.uintLessThan(CaseOffset, @min(remaining, @as(CaseOffset, max_chunk_len)));
}

pub const DeterminismOptions = struct {
    iterations: IterationCount = 32,
    ops_per_case: OpCount = 64,
    max_chunk_len: ChunkLen = 32,
};

const FeedMode = enum {
    whole_slice,
    bytewise,
    chunked,
};

const OpKind = enum {
    prose,
    csi,
    osc,
    dcs,
    apc,
    pm,
    esc_dispatch,
    utf8,
    control,
};

const Event = union(enum) {
    print: u21,
    execute: u8,
    invalid,
    csi: struct {
        final: u8,
        leader: u8,
        private: bool,
        params: [parser_mod.max_params]i32,
        count: u8,
        intermediates: [parser_mod.max_intermediates]u8,
        intermediates_len: u8,
    },
    osc: parser_mod.OscAction,
    screen_title: []u8,
    apc_start,
    apc_put: u8,
    apc_end,
    apc_cancel,
    dcs_hook: struct {
        final: u8,
        params: [parser_mod.max_params]i32,
        count: u8,
        intermediates: [parser_mod.max_intermediates]u8,
        intermediates_len: u8,
    },
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
    esc_dispatch: parser_mod.EscAction,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    fn init(allocator: std.mem.Allocator) Harness {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).empty,
        };
    }

    fn deinit(self: *Harness) void {
        for (self.events.items) |event| {
            switch (event) {
                .osc => |osc| self.allocator.free(osc.payload()),
                .screen_title => |title| self.allocator.free(title),
                else => {},
            }
        }
        self.events.deinit(self.allocator);
    }

    fn appendActions(self: *Harness, actions: []const parser_mod.Action) error{OutOfMemory}!void {
        for (actions) |parser_action| switch (parser_action) {
            .print => |cp| try self.events.append(self.allocator, Event{ .print = cp }),
            .execute => |ctrl| try self.events.append(self.allocator, Event{ .execute = ctrl }),
            .invalid => try self.events.append(self.allocator, .invalid),
            .csi_dispatch => |csi| try self.events.append(self.allocator, Event{ .csi = .{
                .final = csi.final,
                .leader = csi.leader,
                .private = csi.private,
                .params = copyFixedI32(csi.params),
                .count = csi.count,
                .intermediates = copyFixedU8(csi.intermediates),
                .intermediates_len = csi.intermediates_len,
            } }),
            .osc_dispatch => |osc| {
                const owned = try self.allocator.dupe(u8, osc.payload());
                errdefer self.allocator.free(owned);
                try self.events.append(self.allocator, Event{ .osc = cloneOscAction(osc, owned) });
            },
            .screen_title => |title| {
                const owned = try self.allocator.dupe(u8, title);
                errdefer self.allocator.free(owned);
                try self.events.append(self.allocator, .{ .screen_title = owned });
            },
            .apc_start => try self.events.append(self.allocator, .apc_start),
            .apc_put => |byte| try self.events.append(self.allocator, Event{ .apc_put = byte }),
            .apc_end => try self.events.append(self.allocator, .apc_end),
            .apc_cancel => try self.events.append(self.allocator, .apc_cancel),
            .dcs_hook => |hook| try self.events.append(self.allocator, Event{ .dcs_hook = .{
                .final = hook.final,
                .params = copyFixedI32(hook.params),
                .count = hook.count,
                .intermediates = copyFixedU8(hook.intermediates),
                .intermediates_len = hook.intermediates_len,
            } }),
            .dcs_put => |byte| try self.events.append(self.allocator, Event{ .dcs_put = byte }),
            .dcs_unhook => try self.events.append(self.allocator, .dcs_unhook),
            .dcs_cancel => try self.events.append(self.allocator, .dcs_cancel),
            .pm_start => try self.events.append(self.allocator, .pm_start),
            .pm_put => |byte| try self.events.append(self.allocator, Event{ .pm_put = byte }),
            .pm_end => try self.events.append(self.allocator, .pm_end),
            .pm_cancel => try self.events.append(self.allocator, .pm_cancel),
            .sos_start => try self.events.append(self.allocator, .sos_start),
            .sos_put => |byte| try self.events.append(self.allocator, Event{ .sos_put = byte }),
            .sos_end => try self.events.append(self.allocator, .sos_end),
            .sos_cancel => try self.events.append(self.allocator, .sos_cancel),
            .esc_dispatch => |esc| try self.events.append(self.allocator, Event{ .esc_dispatch = esc }),
        };
    }
};

const VtDigest = struct {
    hash: u64,
    rows: u16,
    cols: u16,
    history_count: u32,
    alt_active: bool,
};

const ParserOutput = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    actions: std.ArrayList(parser_mod.Action),

    fn init(allocator: std.mem.Allocator) !ParserOutput {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .actions = try std.ArrayList(parser_mod.Action).initCapacity(allocator, 16),
        };
    }

    fn deinit(self: *ParserOutput) void {
        self.actions.deinit(self.allocator);
        self.arena.deinit();
    }

    fn clear(self: *ParserOutput) void {
        self.actions.clearRetainingCapacity();
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
    }

    fn appendPhases(self: *ParserOutput, phases: parser_mod.PhaseActions) error{OutOfMemory}!void {
        try owned_actions.appendOwnedPhases(self.allocator, self.arena.allocator(), &self.actions, phases);
    }
};

pub fn defaultOptions(events_max: ?OpCount) DeterminismOptions {
    return .{
        .iterations = 32,
        .ops_per_case = events_max orelse 64,
        .max_chunk_len = 32,
    };
}

pub fn runSmoke(gpa: std.mem.Allocator) !void {
    const seeds = [_]u64{
        0x70726f746f3031,
        0x70726f746f3032,
        0x70726f746f3033,
    };
    for (seeds) |seed| {
        try runDeterminism(gpa, seed, defaultOptions(null));
    }
}

fn copyFixedI32(data: []const i32) [parser_mod.max_params]i32 {
    std.debug.assert(data.len <= parser_mod.max_params);
    var out = @as([parser_mod.max_params]i32, @splat(0));
    std.mem.copyForwards(i32, out[0..data.len], data);
    return out;
}

fn copyFixedU8(data: []const u8) [parser_mod.max_intermediates]u8 {
    std.debug.assert(data.len <= parser_mod.max_intermediates);
    var out = @as([parser_mod.max_intermediates]u8, @splat(0));
    std.mem.copyForwards(u8, out[0..data.len], data);
    return out;
}

pub fn runDeterminism(gpa: std.mem.Allocator, seed: u64, options: DeterminismOptions) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var case_index: IterationCount = 0;
    while (case_index < options.iterations) : (case_index += 1) {
        var bytes = std.ArrayList(u8).empty;
        defer bytes.deinit(gpa);

        try buildCase(gpa, &bytes, rand, options.ops_per_case);
        try assertParserDeterminism(gpa, seed, case_index, bytes.items, rand, options.max_chunk_len);
        try assertTerminalDeterminism(gpa, seed, case_index, bytes.items, rand, options.max_chunk_len);
    }
}

fn buildCase(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, ops_per_case: OpCount) !void {
    try bytes.ensureTotalCapacityPrecise(allocator, @intCast(@as(u64, ops_per_case) * 16));

    var op_index: OpCount = 0;
    while (op_index < ops_per_case) : (op_index += 1) {
        const op: OpKind = rand.enumValue(OpKind);
        switch (op) {
            .prose => try appendAssetText(allocator, bytes, rand, 1 + rand.uintLessThan(TextLen, 48)),
            .csi => try appendCsi(allocator, bytes, rand),
            .osc => try appendStringCommand(allocator, bytes, rand, ']'),
            .dcs => try appendStringCommand(allocator, bytes, rand, 'P'),
            .apc => try appendStringCommand(allocator, bytes, rand, '_'),
            .pm => try appendStringCommand(allocator, bytes, rand, '^'),
            .esc_dispatch => try appendEscFinal(allocator, bytes, rand),
            .utf8 => try appendUtf8Burst(allocator, bytes, rand),
            .control => try appendControlBurst(allocator, bytes, rand),
        }
    }
}

fn assertParserDeterminism(gpa: std.mem.Allocator, seed: u64, case_index: IterationCount, bytes: []const u8, rand: std.Random, max_chunk_len: ChunkLen) !void {
    var whole = try runParser(gpa, bytes, .whole_slice, rand, max_chunk_len);
    defer whole.deinit();
    var bytewise = try runParser(gpa, bytes, .bytewise, rand, max_chunk_len);
    defer bytewise.deinit();
    var chunked = try runParser(gpa, bytes, .chunked, rand, max_chunk_len);
    defer chunked.deinit();

    if (!eventsEqual(whole.events.items, bytewise.events.items) or
        !eventsEqual(whole.events.items, chunked.events.items))
    {
        std.log.err("protocol parser mismatch seed={} case={} bytes={}", .{
            seed,
            case_index,
            bytes.len,
        });
        return error.ParserDeterminismMismatch;
    }
}

fn eventsEqual(a: []const Event, b: []const Event) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        if (left == .osc) {
            const left_osc = left.osc;
            const right_osc = right.osc;
            if (std.meta.activeTag(left_osc) != std.meta.activeTag(right_osc))
                return false;
            if (left_osc.command() != right_osc.command() or
                left_osc.term() != right_osc.term() or
                !std.mem.eql(u8, left_osc.payload(), right_osc.payload()))
            {
                return false;
            }
            continue;
        }
        if (left == .screen_title) {
            if (!std.mem.eql(u8, left.screen_title, right.screen_title)) return false;
            continue;
        }
        if (!std.meta.eql(left, right)) return false;
    }
    return true;
}

fn assertTerminalDeterminism(gpa: std.mem.Allocator, seed: u64, case_index: IterationCount, bytes: []const u8, rand: std.Random, max_chunk_len: ChunkLen) !void {
    const whole = try runTerminal(gpa, bytes, .whole_slice, rand, max_chunk_len);
    const bytewise = try runTerminal(gpa, bytes, .bytewise, rand, max_chunk_len);
    const chunked = try runTerminal(gpa, bytes, .chunked, rand, max_chunk_len);

    if (!std.meta.eql(whole, bytewise) or !std.meta.eql(whole, chunked)) {
        std.log.err("protocol terminal mismatch seed={} case={} bytes={} whole_hash={} bytewise_hash={} chunked_hash={}", .{
            seed,
            case_index,
            bytes.len,
            whole.hash,
            bytewise.hash,
            chunked.hash,
        });
        return error.TerminalDeterminismMismatch;
    }
}

fn runParser(gpa: std.mem.Allocator, bytes: []const u8, mode: FeedMode, rand: std.Random, max_chunk_len: ChunkLen) !Harness {
    var harness = Harness.init(gpa);
    errdefer harness.deinit();

    var parser = try parser_mod.Parser.init(gpa);
    defer parser.deinit();
    var output = try ParserOutput.init(gpa);
    defer output.deinit();

    try feedBytesToParser(&parser, &output, &harness, bytes, mode, rand, max_chunk_len);
    return harness;
}

fn runTerminal(gpa: std.mem.Allocator, bytes: []const u8, mode: FeedMode, rand: std.Random, max_chunk_len: ChunkLen) !VtDigest {
    var terminal = try Terminal.initWithHistory(gpa, 24, 80, 256);
    defer terminal.deinit();

    try feedBytesToTerminal(&terminal, bytes, mode, rand, max_chunk_len);
    return digestTerminal(&terminal);
}

fn feedBytesToParser(
    parser: *parser_mod.Parser,
    output: *ParserOutput,
    harness: *Harness,
    bytes: []const u8,
    mode: FeedMode,
    rand: std.Random,
    max_chunk_len: ChunkLen,
) error{OutOfMemory}!void {
    switch (mode) {
        .whole_slice => {
            output.clear();
            for (bytes) |byte| try output.appendPhases(parser.next(byte));
            try harness.appendActions(output.actions.items);
        },
        .bytewise => for (bytes) |byte| {
            output.clear();
            try output.appendPhases(parser.next(byte));
            try harness.appendActions(output.actions.items);
        },
        .chunked => {
            const bytes_len = byteCount(bytes);
            var offset: CaseOffset = 0;
            while (offset < bytes_len) {
                const remaining = bytes_len - offset;
                const count = chunkLen(rand, remaining, max_chunk_len);
                output.clear();
                for (bytes[@intCast(offset)..][0..@intCast(count)]) |byte|
                    try output.appendPhases(parser.next(byte));
                try harness.appendActions(output.actions.items);
                offset += count;
            }
        },
    }
}

fn feedBytesToTerminal(
    terminal: *Terminal,
    bytes: []const u8,
    mode: FeedMode,
    rand: std.Random,
    max_chunk_len: ChunkLen,
) error{ ConsequenceLimit, OutOfMemory, ParsedEventLimit, StringControlLimit }!void {
    switch (mode) {
        .whole_slice => try feedChecked(terminal, bytes),
        .bytewise => {
            for (bytes) |byte| try feedChecked(terminal, &.{byte});
        },
        .chunked => {
            const bytes_len = byteCount(bytes);
            var offset: CaseOffset = 0;
            while (offset < bytes_len) {
                const remaining = bytes_len - offset;
                const count = chunkLen(rand, remaining, max_chunk_len);
                try feedChecked(terminal, bytes[@intCast(offset)..][0..@intCast(count)]);
                offset += count;
            }
        },
    }
}

fn feedChecked(
    terminal: *Terminal,
    bytes: []const u8,
) error{ ConsequenceLimit, OutOfMemory, ParsedEventLimit, StringControlLimit }!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.history_lost or summary.state_changed);
}

fn digestTerminal(terminal: *Terminal) VtDigest {
    var hasher = std.hash.Fnv1a_64.init();
    const view = terminal.semanticView(0);

    hashValue(&hasher, view.rows);
    hashValue(&hasher, view.cols);
    hashValue(&hasher, view.is_alternate_screen);

    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            hashCell(&hasher, view.cellInfoAt(row, col));
        }
    }

    const history_count = view.history_count;
    hashValue(&hasher, history_count);
    var history_idx: u32 = 0;
    while (history_idx < history_count) : (history_idx += 1) {
        // Rebase a copied view to each history row without exposing terminal storage.
        var history_view = view;
        history_view.start = history_count - 1 - history_idx;
        for (history_view.rowCells(0)) |cell| {
            hashCell(&hasher, cell);
        }
    }

    return .{
        .hash = hasher.final(),
        .rows = view.rows,
        .cols = view.cols,
        .history_count = history_count,
        .alt_active = view.is_alternate_screen,
    };
}

fn hashCell(hasher: *std.hash.Fnv1a_64, cell: anytype) void {
    hashValue(hasher, cell.codepoint);
    hashValue(hasher, cell.combining_len);
    for (cell.combining) |cp| hashValue(hasher, cp);
    hashValue(hasher, cell.width);
    hashValue(hasher, cell.height);
    hashValue(hasher, cell.x);
    hashValue(hasher, cell.y);
    hashColor(hasher, cell.attrs.fg);
    hashColor(hasher, cell.attrs.bg);
    hashValue(hasher, cell.attrs.bold);
    hashValue(hasher, cell.attrs.blink);
    hashValue(hasher, cell.attrs.blink_fast);
    hashValue(hasher, cell.attrs.reverse);
    hashValue(hasher, cell.attrs.underline);
    hashValue(hasher, @backingInt(cell.attrs.underline_style));
    hashColor(hasher, cell.attrs.underline_color);
    hashValue(hasher, cell.attrs.link_id);
}

fn hashColor(hasher: *std.hash.Fnv1a_64, color: anytype) void {
    hashValue(hasher, color.kind);
    hashValue(hasher, color.value);
}

fn hashValue(hasher: *std.hash.Fnv1a_64, value: anytype) void {
    const bytes = std.mem.asBytes(&value);
    hasher.update(bytes);
}

fn appendCsi(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    try bytes.appendSlice(allocator, "\x1b[");

    if (rand.boolean()) {
        const leaders = [_]u8{ '?', '>', '<', '=' };
        try bytes.append(allocator, leaders[@intCast(rand.uintLessThan(u8, @intCast(leaders.len)))]);
    }

    const param_count: u8 = 1 + rand.uintLessThan(u8, 4);
    var param_idx: u8 = 0;
    while (param_idx < param_count) : (param_idx += 1) {
        const value = rand.uintLessThan(u16, 1000);
        var buf: [16]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "{d}", .{value});
        try bytes.appendSlice(allocator, text);
        if (param_idx + 1 < param_count) {
            try bytes.append(allocator, if (rand.boolean()) ';' else ':');
        }
    }

    if (rand.boolean()) {
        const intermediates = [_]u8{ ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+' };
        const count: u8 = 1 + rand.uintLessThan(u8, 2);
        var inter_idx: u8 = 0;
        while (inter_idx < count) : (inter_idx += 1) {
            try bytes.append(allocator, intermediates[@intCast(rand.uintLessThan(u8, @intCast(intermediates.len)))]);
        }
    }

    const finals = "@ABCDEFGHJKLMPSTX`abcdefghlmnprsuxt";
    try bytes.append(allocator, finals[@intCast(rand.uintLessThan(u8, @intCast(finals.len)))]);
}

fn appendStringCommand(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, introducer: u8) !void {
    try bytes.append(allocator, 0x1B);
    try bytes.append(allocator, introducer);
    try appendAssetPayload(allocator, bytes, rand, 1 + rand.uintLessThan(TextLen, 48));
    if (rand.boolean()) {
        try bytes.append(allocator, 0x07);
    } else {
        try bytes.appendSlice(allocator, "\x1b\\");
    }
}

fn appendEscFinal(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const finals = "78DEHM=>cnop";
    try bytes.append(allocator, 0x1B);
    try bytes.append(allocator, finals[@intCast(rand.uintLessThan(u8, @intCast(finals.len)))]);
}

fn appendUtf8Burst(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const codepoints = [_]u21{ 0x00A9, 0x03BB, 0x2500, 0x2603, 0x20AC, 0x1F600 };
    const count: u8 = 1 + rand.uintLessThan(u8, 6);
    var idx: u8 = 0;
    while (idx < count) : (idx += 1) {
        var buf: [4]u8 = undefined;
        const cp = codepoints[@intCast(rand.uintLessThan(u8, @intCast(codepoints.len)))];
        const len = try std.unicode.utf8Encode(cp, &buf);
        try bytes.appendSlice(allocator, buf[0..len]);
    }
}

fn appendControlBurst(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const controls = [_]u8{ 0x00, 0x07, 0x08, 0x09, 0x0A, 0x0D, 0x7F };
    const count: u8 = 1 + rand.uintLessThan(u8, 4);
    var idx: u8 = 0;
    while (idx < count) : (idx += 1) {
        try bytes.append(allocator, controls[@intCast(rand.uintLessThan(u8, @intCast(controls.len)))]);
    }
}

fn appendAssetText(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, desired_len: TextLen) !void {
    try appendAssetSample(allocator, bytes, rand, desired_len, sanitizeTextByte);
}

fn appendAssetPayload(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, desired_len: TextLen) !void {
    try appendAssetSample(allocator, bytes, rand, desired_len, sanitizePayloadByte);
}

fn appendAssetSample(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, desired_len: TextLen, sanitize: *const fn (u8) u8) !void {
    var idx = pickAssetStart(rand);
    const asset_len = assetByteCount();
    var written: TextLen = 0;
    while (idx < asset_len and written < desired_len) : (idx += 1) {
        try bytes.append(allocator, sanitize(xterm_ctlseqs[@intCast(idx)]));
        written += 1;
    }
}

fn sanitizeTextByte(byte: u8) u8 {
    return switch (byte) {
        0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F => ' ',
        else => byte,
    };
}

fn sanitizePayloadByte(byte: u8) u8 {
    return switch (byte) {
        0x1B => '.',
        0x00...0x1A, 0x1C...0x1F, 0x7F => ' ',
        else => byte,
    };
}

fn pickAssetStart(rand: std.Random) AssetOffset {
    const len = assetByteCount();
    if (len == 0) return 0;
    return rand.uintLessThan(AssetOffset, len);
}

fn cloneOscAction(osc: parser_mod.OscAction, payload: []u8) parser_mod.OscAction {
    return switch (osc) {
        .raw_title => .{ .raw_title = .{ .payload = payload, .term = osc.term() } },
        .raw_other => .{ .raw_other = .{ .payload = payload, .term = osc.term() } },
        .title => |v| .{ .title = .{ .command = v.command, .payload = payload, .term = v.term } },
        .icon => .{ .icon = .{ .payload = payload, .term = osc.term() } },
        .palette_control => |v| .{ .palette_control = .{ .command = v.command, .payload = payload, .term = v.term } },
        .palette_reset => |v| .{ .palette_reset = .{ .command = v.command, .payload = payload, .term = v.term } },
        .dynamic_color => |v| .{ .dynamic_color = .{ .command = v.command, .payload = payload, .term = v.term } },
        .dynamic_reset => |v| .{ .dynamic_reset = .{ .command = v.command, .payload = payload, .term = v.term } },
        .report_pwd => .{ .report_pwd = .{ .payload = payload, .term = osc.term() } },
        .hyperlink => .{ .hyperlink = .{ .payload = payload, .term = osc.term() } },
        .notification => |v| .{ .notification = .{ .command = v.command, .payload = payload, .term = v.term } },
        .pointer_shape => .{ .pointer_shape = .{ .payload = payload, .term = osc.term() } },
        .clipboard => |v| .{ .clipboard = .{ .command = v.command, .payload = payload, .term = v.term } },
        .kitty_color => |v| .{ .kitty_color = .{ .command = v.command, .payload = payload, .term = v.term } },
        .kitty_text_size => .{ .kitty_text_size = .{ .payload = payload, .term = osc.term() } },
        .kitty_drag_drop => .{ .kitty_drag_drop = .{ .payload = payload, .term = osc.term() } },
        .shell_mark => .{ .shell_mark = .{ .payload = payload, .term = osc.term() } },
        .rxvt_extension => .{ .rxvt_extension = .{ .payload = payload, .term = osc.term() } },
        .iterm2 => |v| .{ .iterm2 = .{
            .command = v.command,
            .payload = payload,
            .term = v.term,
        } },
        .context_signal => .{ .context_signal = .{ .payload = payload, .term = osc.term() } },
        .kitty_color_stack_push => .{ .kitty_color_stack_push = osc.term() },
        .kitty_color_stack_pop => .{ .kitty_color_stack_pop = osc.term() },
        .kitty_file_transfer => .{ .kitty_file_transfer = .{ .payload = payload, .term = osc.term() } },
        .kitty_clipboard => .{ .kitty_clipboard = .{ .payload = payload, .term = osc.term() } },
    };
}
