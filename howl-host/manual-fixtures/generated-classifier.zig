//! Emits Render's complete generated-glyph classifier census for maintained
//! Host fixture validation. Each classified scalar is written as uppercase
//! hexadecimal, a tab, and its Render-owned family name. The scan covers the
//! complete Unicode codepoint value range U+000000-U+10FFFF; every output
//! failure propagates to the process entrypoint.

const std = @import("std");
const render = @import("howl_render");

/// Scans every Unicode codepoint value and emits exactly the entries accepted
/// by `render.generated.classify`; it retains no classifier or fixture state.
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    var codepoint: u32 = 0;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        const family = render.generated.classify(codepoint) orelse continue;
        try stdout.interface.print(
            "{X}\t{s}\n",
            .{ codepoint, @tagName(family) },
        );
    }
    try stdout.interface.flush();
}
