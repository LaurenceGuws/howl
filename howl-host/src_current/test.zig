//! Runs every directly owned first-party host proof.

const std = @import("std");
const main = @import("main.zig");
const runtime_exchange = @import("runtime_exchange.zig");
const screen = @import("screen.zig");
const tab = @import("tab.zig");
const tiled_panes = @import("tiled_panes.zig");
const window = @import("window.zig");

test {
    std.testing.refAllDecls(main);
    std.testing.refAllDecls(runtime_exchange);
    std.testing.refAllDecls(screen);
    std.testing.refAllDecls(tab);
    std.testing.refAllDecls(tiled_panes);
    std.testing.refAllDecls(window);
}
