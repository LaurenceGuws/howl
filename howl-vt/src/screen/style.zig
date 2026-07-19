//! Applies rectangular cell-attribute operations.

const cell_mod = @import("cell.zig");

const CellAttrs = cell_mod.CellAttrs;

/// Applies bounded rectangular attribute operations to one cell in protocol order.
pub fn applyRectAttrOps(target: *CellAttrs, attrs: []const u16, reverse: bool) void {
    for (attrs) |attr| {
        switch (attr) {
            0 => if (!reverse) {
                target.bold = false;
                target.dim = false;
                target.italic = false;
                target.underline = false;
                target.underline_style = .straight;
                target.blink = false;
                target.blink_fast = false;
                target.reverse = false;
                target.invisible = false;
                target.strikethrough = false;
            },
            1 => {
                if (reverse) target.bold = !target.bold else target.bold = true;
            },
            2 => {
                if (reverse) target.dim = !target.dim else target.dim = true;
            },
            3 => {
                if (reverse) target.italic = !target.italic else target.italic = true;
            },
            4 => {
                if (reverse) {
                    target.underline = !target.underline;
                    if (target.underline) target.underline_style = .straight;
                } else {
                    target.underline = true;
                    target.underline_style = .straight;
                }
            },
            5 => {
                if (reverse) target.blink = !target.blink else target.blink = true;
            },
            7 => {
                if (reverse) target.reverse = !target.reverse else target.reverse = true;
            },
            8 => {
                if (reverse) target.invisible = !target.invisible else target.invisible = true;
            },
            9 => {
                if (reverse) target.strikethrough = !target.strikethrough else target.strikethrough = true;
            },
            22 => {
                if (!reverse) {
                    target.bold = false;
                    target.dim = false;
                }
            },
            23 => {
                if (!reverse) target.italic = false;
            },
            24 => {
                if (!reverse) {
                    target.underline = false;
                    target.underline_style = .straight;
                }
            },
            25 => {
                if (!reverse) {
                    target.blink = false;
                    target.blink_fast = false;
                }
            },
            27 => {
                if (!reverse) target.reverse = false;
            },
            28 => {
                if (!reverse) target.invisible = false;
            },
            29 => {
                if (!reverse) target.strikethrough = false;
            },
            else => {},
        }
    }
}
