const std = @import("std");
const owned_actions = @import("../../../src/parser_owned_actions.zig");
const parser_mod = @import("../../../src/parser.zig");

const Parser = parser_mod.Parser;
const Action = parser_mod.Action;

const Output = struct {
    arena: std.heap.ArenaAllocator,
    actions: std.ArrayList(Action),

    fn init(allocator: std.mem.Allocator) !Output {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .actions = try std.ArrayList(Action).initCapacity(allocator, 8),
        };
    }

    fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        self.actions.deinit(allocator);
        self.arena.deinit();
    }

    fn clear(self: *Output) void {
        self.actions.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
    }

    fn appendPhases(self: *Output, phases: parser_mod.PhaseActions) void {
        owned_actions.appendOwnedPhases(std.testing.allocator, self.arena.allocator(), &self.actions, phases) catch unreachable;
    }
};

fn expectActionCount(actions: []const Action, count: usize) !void {
    try std.testing.expectEqual(count, actions.len);
}

test "parser: nextStep returns ordered phase actions directly" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    const esc = parser.next(0x1B);
    try std.testing.expectEqual(@as(?Action, null), esc[0]);
    try std.testing.expectEqual(@as(?Action, null), esc[1]);
    try std.testing.expectEqual(@as(?Action, null), esc[2]);

    const csi = parser.next('[');
    try std.testing.expectEqual(@as(?Action, null), csi[0]);
    try std.testing.expectEqual(@as(?Action, null), csi[1]);
    try std.testing.expectEqual(@as(?Action, null), csi[2]);

    const final = parser.next('m');
    try std.testing.expectEqual(@as(?Action, null), final[0]);
    try std.testing.expect(final[1].? == .csi_dispatch);
    try std.testing.expectEqual(@as(u8, 'm'), final[1].?.csi_dispatch.final);
    try std.testing.expectEqual(@as(?Action, null), final[2]);
}

test "parser: mixed stream exact sequence (ASCII+CSI+ASCII)" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("AB\x1b[31mC") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 4);
    try std.testing.expectEqual(@as(u21, 'A'), output.actions.items[0].print);
    try std.testing.expectEqual(@as(u21, 'B'), output.actions.items[1].print);
    try std.testing.expect(output.actions.items[2] == .csi_dispatch);
    try std.testing.expectEqual(@as(u8, 'm'), output.actions.items[2].csi_dispatch.final);
    try std.testing.expectEqual(@as(i32, 31), output.actions.items[2].csi_dispatch.params[0]);
    try std.testing.expectEqual(@as(u21, 'C'), output.actions.items[3].print);
}

test "parser: ASCII fast path preserves spaces" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("A B") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 3);
    try std.testing.expectEqual(@as(u21, 'A'), output.actions.items[0].print);
    try std.testing.expectEqual(@as(u21, ' '), output.actions.items[1].print);
    try std.testing.expectEqual(@as(u21, 'B'), output.actions.items[2].print);
}

test "parser: ESC final passthrough (ESC M)" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1bM") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, 'M'), output.actions.items[0].esc_dispatch.final);
    try std.testing.expectEqual(@as(u8, 0), output.actions.items[0].esc_dispatch.intermediates_len);
}

test "parser: split input - partial UTF-8 then completion" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    output.appendPhases(parser.next(0xE2));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next(0x82));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next(0xAC));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .print);
    try std.testing.expectEqual(@as(u21, 0x20AC), output.actions.items[0].print);
}

test "parser: split input - partial CSI then final byte" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    output.appendPhases(parser.next(0x1B));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next('['));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next('3'));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next('1'));
    try expectActionCount(output.actions.items, 0);
    output.clear();
    output.appendPhases(parser.next('m'));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .csi_dispatch);
    try std.testing.expectEqual(@as(u8, 'm'), output.actions.items[0].csi_dispatch.final);
    try std.testing.expectEqual(@as(i32, 31), output.actions.items[0].csi_dispatch.params[0]);
}
test "parser: CSI with multiple parameters exact order" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b[1;31;40m") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .csi_dispatch);
    try std.testing.expectEqual(@as(i32, 1), output.actions.items[0].csi_dispatch.params[0]);
    try std.testing.expectEqual(@as(i32, 31), output.actions.items[0].csi_dispatch.params[1]);
    try std.testing.expectEqual(@as(i32, 40), output.actions.items[0].csi_dispatch.params[2]);
    try std.testing.expectEqual(@as(u8, 3), output.actions.items[0].csi_dispatch.count);
}

test "parser: charset designate emits ESC dispatch and leaves stream bytes raw" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b(0lqkxmj\x1b(Bq") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 9);
    try std.testing.expect(output.actions.items[0] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, '('), output.actions.items[0].esc_dispatch.intermediates[0]);
    try std.testing.expectEqual(@as(u8, '0'), output.actions.items[0].esc_dispatch.final);
    try std.testing.expectEqual(@as(u21, 'l'), output.actions.items[1].print);
    try std.testing.expectEqual(@as(u21, 'q'), output.actions.items[2].print);
    try std.testing.expectEqual(@as(u21, 'k'), output.actions.items[3].print);
    try std.testing.expectEqual(@as(u21, 'x'), output.actions.items[4].print);
    try std.testing.expectEqual(@as(u21, 'm'), output.actions.items[5].print);
    try std.testing.expectEqual(@as(u21, 'j'), output.actions.items[6].print);
    try std.testing.expect(output.actions.items[7] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, 'B'), output.actions.items[7].esc_dispatch.final);
    try std.testing.expectEqual(@as(u21, 'q'), output.actions.items[8].print);
}

test "parser: SO SI stay stream controls and do not mutate parser-owned charset state" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b)0\x0eq\x0fq") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 5);
    try std.testing.expect(output.actions.items[0] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, ')'), output.actions.items[0].esc_dispatch.intermediates[0]);
    try std.testing.expectEqual(@as(u8, '0'), output.actions.items[0].esc_dispatch.final);
    try std.testing.expectEqual(@as(u8, 0x0E), output.actions.items[1].execute);
    try std.testing.expectEqual(@as(u21, 'q'), output.actions.items[2].print);
    try std.testing.expectEqual(@as(u8, 0x0F), output.actions.items[3].execute);
    try std.testing.expectEqual(@as(u21, 'q'), output.actions.items[4].print);
}

test "parser: C1 string controls replace active DCS passthrough control" {
    var parser = try Parser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.next(0x1B);
    _ = parser.next('P');
    const dcs_hook = parser.next('q');
    try std.testing.expectEqual(Action.dcs_hook, std.meta.activeTag(dcs_hook[2].?));

    const apc_start = parser.next(0x9F);
    try std.testing.expectEqual(Action.dcs_unhook, apc_start[0].?);
    try std.testing.expectEqual(Action.apc_start, apc_start[2].?);

    parser.reset();

    _ = parser.next(0x1B);
    _ = parser.next('P');
    const second_dcs_hook = parser.next('q');
    try std.testing.expectEqual(Action.dcs_hook, std.meta.activeTag(second_dcs_hook[2].?));

    const pm_start = parser.next(0x9E);
    try std.testing.expectEqual(Action.dcs_unhook, pm_start[0].?);
    try std.testing.expectEqual(Action.pm_start, pm_start[2].?);
}
