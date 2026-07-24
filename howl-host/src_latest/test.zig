//! Runs every directly owned first-party host proof.

const std = @import("std");
const main = @import("main.zig");
const window = @import("window.zig");

test {
    std.testing.refAllDecls(main);
    std.testing.refAllDecls(window);
}
