//! Proves the standalone howl-vt package through its declared module only.

const std = @import("std");
const howl_vt = @import("howl_vt");

test "external consumer observes VT mutation and publication" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const summary = try terminal.feed("A\x1b[2CB");
    try std.testing.expect(summary.state_changed);
    const publication = terminal.surfaceSnapshot();
    try std.testing.expectEqual(@as(u21, 'A'), publication.snapshot.view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), publication.snapshot.view.cellAt(0, 3));
    try std.testing.expect(terminal.ackSurface(publication.snapshot_seq));
}
