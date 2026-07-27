//! Projects caller-supplied chrome facts into bounded backend-neutral primitives.

const std = @import("std");
const canvas = @import("canvas");

/// Describes projection failures before any caller storage is changed.
pub const Error = error{
    InvalidSurface,
    InvalidRectangle,
    InvalidTabBar,
    InvalidScrollbar,
    InvalidText,
    InvalidScroll,
    InvalidIdentity,
    InvalidOrder,
    ArithmeticOverflow,
    InsufficientOutput,
    InsufficientText,
    AliasedStorage,
};

/// Stable caller identity for one tab. Render never issues or retains it.
pub const TabId = enum(u64) { _ };
/// Stable caller identity for one pane. Render never issues or retains it.
pub const PaneId = enum(u64) { _ };

/// Uses the canonical Canvas surface extent.
pub const Size = canvas.Size;

/// Uses the canonical Canvas signed rectangle.
pub const Rect = canvas.Rect;

/// Uses the canonical Canvas RGBA color.
pub const Color = canvas.Color;

/// Supplies caller-selected foreground, background, and frame colors.
pub const Style = struct {
    /// Color used for labels and focused frames.
    foreground: Color,
    /// Color used for the tab-bar background.
    background: Color,
    /// Color used for unfocused frames and scrollbar tracks.
    border: Color,
};

/// Supplies one ordered tab label and its active appearance fact.
pub const Tab = struct {
    /// Supplies the stable nonzero caller identity.
    id: TabId,
    /// Borrows validated UTF-8 label bytes for this call.
    label: []const u8,
    /// Selects active versus inactive tab styling.
    active: bool,
};

/// Selects tiled coverage or caller-ordered floating overlap.
pub const PaneLayer = enum { tiled, floating };

/// Supplies bounded scroll-model facts; no viewport policy is retained.
pub const Scroll = struct {
    /// Supplies the positive visible item count.
    visible: u32,
    /// Supplies the total item count, at least `visible`.
    total: u32,
    /// Supplies the first visible item, at most `total - visible`.
    start: u32,
};

/// Supplies one immutable pane rectangle, label, focus fact, and scroll model.
pub const Pane = struct {
    /// Supplies the stable nonzero caller identity.
    id: PaneId,
    /// Supplies the pane rectangle before surface clipping.
    rect: Rect,
    /// Borrows validated UTF-8 pane-label bytes for this call.
    label: []const u8,
    /// Selects focused versus unfocused frame styling.
    focused: bool,
    /// Supplies scroll facts when a scrollbar should be projected.
    scroll: ?Scroll,
    /// Supplies the pane composition layer. Tiled panes precede floating panes.
    layer: PaneLayer,
};

/// Supplies one caller-owned selected pixel range and its appearance.
pub const Selection = struct {
    /// Identifies the pane whose content owns this range before surface and
    /// pane clipping.
    pane: PaneId,
    /// Supplies the selected range before surface clipping.
    rect: Rect,
    /// Supplies the caller-selected highlight color.
    color: Color,
};

/// Supplies all immutable caller facts for one chrome projection.
pub const Input = struct {
    /// Bounds every emitted primitive after clipping.
    surface: Size,
    /// Sets the tab-bar height; zero hides it and larger values clamp to surface height.
    tab_bar_height: u16,
    /// Borrows ordered tab facts.
    tabs: []const Tab,
    /// Borrows ordered pane facts.
    panes: []const Pane,
    /// Borrows caller-mapped selection ranges in deterministic draw order.
    selections: []const Selection,
    /// Supplies shared chrome colors.
    style: Style,
    /// Supplies active tab background color.
    tab_active_background: Color,
    /// Supplies inactive tab background color.
    tab_inactive_background: Color,
    /// Supplies scrollbar width when a scrollbar is emitted.
    scrollbar_width: u16,
    /// Supplies the minimum scrollbar thumb height when emitted.
    scrollbar_min_thumb: u16,
};

/// Supplies one surface-local pixel coordinate for stateless hit testing.
pub const Point = struct {
    /// Horizontal pixel coordinate.
    x: i32,
    /// Vertical pixel coordinate.
    y: i32,
};

/// Identifies the topmost tab or pane under one caller coordinate.
pub const Hit = union(enum) {
    /// Identifies one tab-bar entry.
    tab: TabId,
    /// Identifies one tiled or floating pane.
    pane: PaneId,
};

/// Identifies which frame edges are owned by one primitive.
pub const BorderEdges = packed struct(u4) {
    /// Emits the top edge.
    top: bool = true,
    /// Emits the right edge when structurally owned or needed for focus.
    right: bool = true,
    /// Emits the bottom edge when structurally owned or needed for focus.
    bottom: bool = true,
    /// Emits the left edge.
    left: bool = true,
};

/// Describes one deterministic backend draw primitive borrowing caller text.
pub const Primitive = union(enum) {
    /// Fills one clipped rectangle.
    fill: struct { rect: Rect, color: Color },
    /// Draws UTF-8 bytes copied into caller output text storage within one clipped rectangle.
    label: struct { rect: Rect, text: []const u8, color: Color },
    /// Draws the selected frame edges of one clipped pane.
    border: struct { rect: Rect, edges: BorderEdges, color: Color },
    /// Draws one scrollbar track and thumb.
    scrollbar: struct { track: Rect, thumb: Rect, color: Color, thumb_color: Color },
};

/// Borrows accepted primitives and copied label bytes until caller storage is reused.
pub const Output = struct {
    /// Retains the nonzero surface that clipped every primitive.
    surface: Size,
    /// Borrows the initialized primitive prefix of caller storage.
    primitives: []const Primitive,
    /// Borrows copied UTF-8 label bytes in caller text storage.
    text: []const u8,
};

/// Projects one chrome frame without allocation; failures leave both buffers unchanged.
pub fn project(input: Input, primitives: []Primitive, text_storage: []u8) Error!Output {
    if (input.surface.width == 0 or input.surface.height == 0) return error.InvalidSurface;
    const primitive_bytes = try byteLen(primitives.len, @sizeOf(Primitive));
    const tab_bytes = try byteLen(input.tabs.len, @sizeOf(Tab));
    const pane_bytes = try byteLen(input.panes.len, @sizeOf(Pane));
    const selection_bytes = try byteLen(input.selections.len, @sizeOf(Selection));
    const primitive_start = @intFromPtr(primitives.ptr);
    const text_start = @intFromPtr(text_storage.ptr);
    const tab_start = @intFromPtr(input.tabs.ptr);
    const pane_start = @intFromPtr(input.panes.ptr);
    const selection_start = @intFromPtr(input.selections.ptr);
    if (overlapsRanges(primitive_start, primitive_bytes, tab_start, tab_bytes) or
        overlapsRanges(primitive_start, primitive_bytes, pane_start, pane_bytes) or
        overlapsRanges(primitive_start, primitive_bytes, selection_start, selection_bytes) or
        overlapsRanges(primitive_start, primitive_bytes, text_start, text_storage.len) or
        overlapsRanges(text_start, text_storage.len, tab_start, tab_bytes) or
        overlapsRanges(text_start, text_storage.len, pane_start, pane_bytes) or
        overlapsRanges(text_start, text_storage.len, selection_start, selection_bytes))
        return error.AliasedStorage;
    for (input.tabs) |tab| {
        if (overlapsRanges(primitive_start, primitive_bytes, @intFromPtr(tab.label.ptr), tab.label.len) or
            overlapsRanges(text_start, text_storage.len, @intFromPtr(tab.label.ptr), tab.label.len))
            return error.AliasedStorage;
    }
    for (input.panes) |pane| {
        if (overlapsRanges(primitive_start, primitive_bytes, @intFromPtr(pane.label.ptr), pane.label.len) or
            overlapsRanges(text_start, text_storage.len, @intFromPtr(pane.label.ptr), pane.label.len))
            return error.AliasedStorage;
    }

    const tab_height = @min(input.tab_bar_height, input.surface.height);
    var needed: usize = 0;
    var text_needed: usize = 0;
    try validateIdentitiesAndOrder(input);
    for (input.selections) |selection| {
        if (@backingInt(selection.pane) == 0 or !hasPane(input.panes, selection.pane)) return error.InvalidIdentity;
        try validateRect(selection.rect, input.surface);
    }
    if (tab_height != 0) {
        if (input.tabs.len > input.surface.width) return error.InvalidTabBar;
        try add(&needed, 1);
        if (input.tabs.len != 0) {
            const unit = input.surface.width / @as(u16, @intCast(input.tabs.len));
            for (input.tabs, 0..) |tab, index| {
                const width = if (index + 1 == input.tabs.len)
                    input.surface.width - unit * @as(u16, @intCast(index))
                else
                    unit;
                if (width == 0) continue;
                try validateUtf8(tab.label);
                try add(&needed, 1);
                if (tab.label.len != 0) {
                    try add(&needed, 1);
                    try add(&text_needed, tab.label.len);
                }
            }
        }
    }
    for (input.panes) |pane| {
        try validateRect(pane.rect, input.surface);
        const rect = clipRect(pane.rect, input.surface);
        for (input.selections) |selection| {
            if (selection.pane == pane.id) {
                const clipped = clipRectToPane(selection.rect, rect);
                if (clipped.width != 0 and clipped.height != 0) try add(&needed, 1);
            }
        }
        try add(&needed, 1);
        try validateUtf8(pane.label);
        if (pane.label.len != 0) {
            try add(&needed, 1);
            try add(&text_needed, pane.label.len);
        }
        if (pane.scroll) |scroll| {
            try validateScroll(scroll);
            if (scroll.visible < scroll.total) {
                try validateScrollbarInput(rect, input.scrollbar_width, input.scrollbar_min_thumb);
                try add(&needed, 1);
            }
        }
    }
    if (needed > primitives.len) return error.InsufficientOutput;
    if (text_needed > text_storage.len) return error.InsufficientText;

    var used: usize = 0;
    var text_used: usize = 0;
    if (tab_height != 0) {
        primitives[used] = .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = input.surface.width, .height = tab_height }, .color = input.style.background } };
        used += 1;
        const unit = if (input.tabs.len == 0) 0 else input.surface.width / @as(u16, @intCast(input.tabs.len));
        for (input.tabs, 0..) |tab, index| {
            const width = if (index + 1 == input.tabs.len) input.surface.width - unit * @as(u16, @intCast(index)) else unit;
            if (width == 0) continue;
            const x: i32 = @intCast(@as(u32, @intCast(index)) * unit);
            primitives[used] = .{ .fill = .{ .rect = .{ .x = x, .y = 0, .width = width, .height = tab_height }, .color = if (tab.active) input.tab_active_background else input.tab_inactive_background } };
            used += 1;
            if (tab.label.len != 0) {
                const copied = copyLabel(text_storage, &text_used, tab.label);
                primitives[used] = .{ .label = .{ .rect = .{ .x = x, .y = 0, .width = width, .height = tab_height }, .text = copied, .color = input.style.foreground } };
                used += 1;
            }
        }
    }
    for (input.panes) |pane| {
        const rect = clipRect(pane.rect, input.surface);
        for (input.selections) |selection| {
            if (selection.pane == pane.id) {
                const clipped = clipRectToPane(selection.rect, rect);
                if (clipped.width != 0 and clipped.height != 0) {
                    primitives[used] = .{ .fill = .{ .rect = clipped, .color = selection.color } };
                    used += 1;
                }
            }
        }
        primitives[used] = .{ .border = .{ .rect = rect, .edges = edgeMask(pane, input.panes), .color = if (pane.focused) input.style.foreground else input.style.border } };
        used += 1;
        if (pane.label.len != 0) {
            const copied = copyLabel(text_storage, &text_used, pane.label);
            primitives[used] = .{ .label = .{ .rect = rect, .text = copied, .color = input.style.foreground } };
            used += 1;
        }
        if (pane.scroll) |scroll| if (scroll.visible < scroll.total) {
            const bars = scrollbar(rect, scroll, input.scrollbar_width, input.scrollbar_min_thumb);
            primitives[used] = .{ .scrollbar = .{ .track = bars.track, .thumb = bars.thumb, .color = input.style.border, .thumb_color = input.style.foreground } };
            used += 1;
        };
    }
    return .{
        .surface = input.surface,
        .primitives = primitives[0..used],
        .text = text_storage[0..text_used],
    };
}

/// Returns the topmost caller identity at `point` without allocation or retained
/// state. Hit-relevant geometry, identity, and order facts fail before a hit is
/// returned.
pub fn hitTest(input: Input, point: Point) Error!?Hit {
    if (input.surface.width == 0 or input.surface.height == 0) return error.InvalidSurface;
    try validateIdentitiesAndOrder(input);
    const tab_height = @min(input.tab_bar_height, input.surface.height);
    if (tab_height != 0 and input.tabs.len > input.surface.width) return error.InvalidTabBar;
    for (input.panes) |pane| try validateRect(pane.rect, input.surface);
    if (point.x >= 0 and point.y >= 0 and point.x < input.surface.width and point.y < tab_height and input.tabs.len != 0) {
        const unit = input.surface.width / @as(u16, @intCast(input.tabs.len));
        for (input.tabs, 0..) |tab, index| {
            const width = if (index + 1 == input.tabs.len) input.surface.width - unit * @as(u16, @intCast(index)) else unit;
            const x: i32 = @intCast(@as(u32, @intCast(index)) * unit);
            if (point.x >= x and point.x < @as(i64, x) + width) return .{ .tab = tab.id };
        }
    }
    var index = input.panes.len;
    while (index > 0) {
        index -= 1;
        const pane = input.panes[index];
        const rect = clipRect(pane.rect, input.surface);
        if (contains(rect, point)) return .{ .pane = pane.id };
    }
    return null;
}

fn add(value: *usize, amount: usize) Error!void {
    value.* = std.math.add(usize, value.*, amount) catch return error.ArithmeticOverflow;
}
fn validateUtf8(value: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidText;
}
fn copyLabel(storage: []u8, used: *usize, source: []const u8) []const u8 {
    const start = used.*;
    @memcpy(storage[start .. start + source.len], source);
    used.* += source.len;
    return storage[start .. start + source.len];
}
fn validateRect(rect: Rect, surface: Size) Error!void {
    if (rect.width == 0 or rect.height == 0) return error.InvalidRectangle;
    const right = std.math.add(i64, rect.x, rect.width) catch return error.ArithmeticOverflow;
    const bottom = std.math.add(i64, rect.y, rect.height) catch return error.ArithmeticOverflow;
    if (right <= 0 or bottom <= 0 or rect.x >= surface.width or rect.y >= surface.height) return error.InvalidRectangle;
}
fn clipRect(rect: Rect, surface: Size) Rect {
    const left = @max(@as(i64, 0), rect.x);
    const top = @max(@as(i64, 0), rect.y);
    const right = @min(@as(i64, surface.width), @as(i64, rect.x) + rect.width);
    const bottom = @min(@as(i64, surface.height), @as(i64, rect.y) + rect.height);
    return .{ .x = @intCast(left), .y = @intCast(top), .width = @intCast(right - left), .height = @intCast(bottom - top) };
}
fn clipRectToPane(rect: Rect, pane: Rect) Rect {
    const left = @max(@as(i64, pane.x), @as(i64, rect.x));
    const top = @max(@as(i64, pane.y), @as(i64, rect.y));
    const right = @min(@as(i64, pane.x) + pane.width, @as(i64, rect.x) + rect.width);
    const bottom = @min(@as(i64, pane.y) + pane.height, @as(i64, rect.y) + rect.height);
    return .{ .x = @intCast(left), .y = @intCast(top), .width = @intCast(@max(@as(i64, 0), right - left)), .height = @intCast(@max(@as(i64, 0), bottom - top)) };
}
fn overlapsRanges(a: usize, a_len: usize, b: usize, b_len: usize) bool {
    if (a_len == 0 or b_len == 0) return false;
    return if (a <= b) b - a < a_len else a - b < b_len;
}

fn byteLen(count: usize, size: usize) Error!usize {
    return std.math.mul(usize, count, size) catch return error.ArithmeticOverflow;
}
fn validateIdentitiesAndOrder(input: Input) Error!void {
    var active_count: usize = 0;
    for (input.tabs, 0..) |tab, index| {
        if (@backingInt(tab.id) == 0) return error.InvalidIdentity;
        if (tab.active) active_count += 1;
        for (input.tabs[0..index]) |prior| {
            if (prior.id == tab.id) return error.InvalidIdentity;
        }
    }
    if (input.tabs.len != 0 and active_count != 1) return error.InvalidIdentity;
    var floating = false;
    for (input.panes, 0..) |pane, index| {
        if (@backingInt(pane.id) == 0) return error.InvalidIdentity;
        if (pane.layer == .floating) floating = true else if (floating) return error.InvalidOrder;
        for (input.panes[0..index]) |prior| {
            if (prior.id == pane.id) return error.InvalidIdentity;
        }
    }
}
fn hasPane(panes: []const Pane, id: PaneId) bool {
    for (panes) |pane| if (pane.id == id) return true;
    return false;
}
fn contains(rect: Rect, point: Point) bool {
    if (point.x < rect.x or point.y < rect.y) return false;
    return @as(i64, point.x) < @as(i64, rect.x) + rect.width and
        @as(i64, point.y) < @as(i64, rect.y) + rect.height;
}
fn edgeMask(pane: Pane, panes: []const Pane) BorderEdges {
    var edges = BorderEdges{};
    // Shared-edge suppression owns ordinary tiled structure. Focus is an
    // overlay fact and must remain complete on every pane edge.
    if (pane.layer == .floating or pane.focused) return edges;
    const left = @as(i64, pane.rect.x);
    const top = @as(i64, pane.rect.y);
    const right = left + pane.rect.width;
    const bottom = top + pane.rect.height;
    for (panes) |other| {
        if (other.layer == .floating) continue;
        const other_left = @as(i64, other.rect.x);
        const other_top = @as(i64, other.rect.y);
        const other_right = other_left + other.rect.width;
        const other_bottom = other_top + other.rect.height;
        if (other_left == right and other_top < bottom and other_bottom > top) edges.right = false;
        if (other_top == bottom and other_left < right and other_right > left) edges.bottom = false;
    }
    return edges;
}
fn validateScroll(scroll: Scroll) Error!void {
    if (scroll.visible == 0 or scroll.visible > scroll.total or scroll.start > scroll.total - scroll.visible) return error.InvalidScroll;
}
fn validateScrollbarInput(rect: Rect, width: u16, min_thumb: u16) Error!void {
    if (width == 0 or min_thumb == 0 or width > rect.width or rect.height == 0) return error.InvalidScrollbar;
}
fn scrollbar(rect: Rect, scroll: Scroll, width: u16, min_thumb: u16) struct { track: Rect, thumb: Rect } {
    const thumb_u64 = @max(@as(u64, min_thumb), @as(u64, rect.height) * scroll.visible / scroll.total);
    const thumb: u16 = @intCast(@min(@as(u64, rect.height), thumb_u64));
    const range = rect.height - thumb;
    const offset: u16 = @intCast(@as(u64, range) * scroll.start / (scroll.total - scroll.visible));
    const x = rect.x + rect.width - width;
    return .{ .track = .{ .x = x, .y = rect.y, .width = width, .height = rect.height }, .thumb = .{ .x = x, .y = rect.y + offset, .width = width, .height = thumb } };
}
