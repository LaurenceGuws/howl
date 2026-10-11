//! External headless composition proof with no Render/Text imports.
const std = @import("std");
const instance = @import("howl_instance_headless");

test "headless public owner serves canonical VT and explicit geometry" {
    std.testing.refAllDecls(instance);
    inline for (.{
        "render",      "text",          "initPresented", "PresentationConfig",
        "renderFrame", "publishRender", "protocol",      "codec",
    }) |name| try std.testing.expect(!@hasDecl(instance, name));
    const owner = try instance.init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 4,
        .history_rows = 4,
    });
    defer instance.deinit(owner);
    try instance.resizeGeometry(owner, 3, 6, 11, 22);
    const observation = instance.terminal(owner);
    const view = observation.semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), view.rows);
    try std.testing.expectEqual(@as(u16, 6), view.cols);
    try std.testing.expectEqual(@as(u32, 11), observation.cellPixelSize().?.width);
    try std.testing.expectError(error.InvalidDimensions, instance.resizeGeometry(owner, 4, 8, 0, 22));
    try std.testing.expectEqualDeep(view, observation.semanticView(0));
    const result = try instance.service(owner, false, false, 0);
    try std.testing.expect(!result.changed);
    try std.testing.expect(!result.write_pending);
}
