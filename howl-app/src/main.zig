//! Owns the local SDL window, pane layout, input routing and terminal workers.
const std = @import("std");
const c = @import("desktop");
const vt = @import("howl_vt");
const commands = @import("howl_vt_output_commands");
const limits = @import("howl_vt_output_limits");
const app_presentation = @import("presentation.zig");
const font_owner = @import("fonts.zig");
const terminal = @import("terminal.zig");
const canvas = @import("canvas.zig");
const terminal_cursor = @import("cursor.zig");
const chrome = @import("chrome.zig");
const layout = @import("layout.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const pointer = @import("pointer.zig");
const composition = @import("composition.zig");
const config = @import("config.zig");
const widgets = @import("widgets.zig");
const tab_title = @import("tab_title.zig");
const host_status = @import("program_status.zig");
const status_toast = @import("status_toast.zig");
const settings = @import("settings.zig");
const pages = @import("settings_pages.zig");
const settings_input = @import("settings_input.zig");
const settings_paint = @import("settings_paint.zig");
const discovery = @import("discovery.zig");
const picker = @import("picker.zig");
const palette_limit = picker.limit;
const appearance = @import("appearance.zig");
const color_config = @import("colors.zig");
const font_chooser = @import("font_chooser.zig");
const selection = @import("selection.zig");
const find = @import("find.zig");
const scrollbar = @import("scrollbar.zig");
const desktop = @import("desktop.zig");
const drawing = @import("pixels.zig");
const icons = @import("icons.zig");
const allocator = std.heap.smp_allocator;
const version = "0.1.9-dev";
const tab_limit = 8;
const GraphicsFailure = @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.update)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.draw)).@"fn".return_type.?).error_union.error_set;

const CreationError = @typeInfo(@typeInfo(@TypeOf(terminal.Terminal.create)).@"fn".return_type.?).error_union.error_set || error{ InvalidColor, InvalidTheme };
const Pane = struct {
    owner: ?*terminal.Terminal = null,
    recipe: config.Recipe,
    creation_failure: ?CreationError = null,
    canvas: canvas.Canvas,
    blink: terminal_cursor.Blink = .{},
    motion: terminal_cursor.Motion = .{},
    rows: u16 = 0,
    columns: u16 = 0,
    size_control: bool = true,
    font_size: u16 = 15,
    font_overridden: bool = false,
    selection_serial: u64 = 0,
    selection_failure_reported: u64 = 0,
    selection_hit: ?SelectionHit = null,
    finder: ?FindEditor = null,
    cell_size: ?commands.Size = null,
    font_failure: ?terminal.ConfigureError = null,
    // A settings rollback may be rejected behind PTY input pressure. Until a
    // later configuration reconciles it, the staged lattice remains canonical.
    font_repair_pending: bool = false,
    graphics_failure: ?GraphicsFailure = null,
    wheel: pointer.Wheel = .{},

    fn requireOwner(self: *Pane) error{PaneUnavailable}!*terminal.Terminal {
        return self.owner orelse error.PaneUnavailable;
    }
    fn snapshot(self: *Pane) terminal.Status {
        return if (self.owner) |owner| owner.snapshot() else .{};
    }
    fn submit(self: *Pane, task: terminal.Task) !void {
        try (try self.requireOwner()).submit(task);
    }
};
const Tab = struct {
    recipe: config.Recipe,
    title: tab_title.Title = .{},
    tree: layout.Tree = layout.Tree.init(),
    panes: [layout.pane_limit]?*Pane = @splat(null),
};
const RenameEditor = struct {
    tab: *Tab,
    edit: widgets.Text = .{},
    bytes: [tab_title.limit]u8 = undefined,
    len: usize = 0,
};
const Palette = picker.Picker;
const FindEditor = struct {
    edit: widgets.Text = .{},
    serial: u64 = 0,
    bytes: [find.query_limit]u8 = undefined,
    len: usize = 0,
};
const Drag = union(enum) { none, divider: layout.Drag, tab: chrome.Drag };
const PointerCapture = struct { pane: *Pane, buttons: u8, last: pointer.Location };
const ScrollDrag = struct { pane: *Pane, bar: scrollbar.Bar, grab: f32, last: ?u32 = null };
const SelectionDrag = struct { pane: *Pane, x: f32, y: f32, edge: i8 = 0 };
const SelectionHit = struct { point: vt.Terminal.TextPoint, columns: u16, alternate: bool };
const SettingsHeaderAction = pages.SettingsHeaderAction;
const settings_header_height = pages.settings_header_height;
const settings_nav_top = pages.settings_nav_top;
const settings_card_padding = pages.settings_card_padding;
const HeaderLabel = struct {
    bytes: [1024]u8 = @splat(0),
    len: usize = 0,

    fn set(self: *HeaderLabel, title: []const u8) void {
        std.debug.assert(title.len <= self.bytes.len);
        self.len = title.len;
        @memcpy(self.bytes[0..title.len], title);
    }
    fn text(self: *const HeaderLabel) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Exact current chrome paint inputs; terminal content changes are deliberately
/// absent. The host can reuse this image even while panes publish new frames.
const HeaderPicture = struct {
    width: f32,
    scale: f32,
    count: u8,
    active: u8,
    fitted: bool,
    hovered: chrome.HeaderTarget,
    /// Action hover remains visible during tab drags, unlike tab-body hover.
    action_hover: chrome.HeaderTarget = .none,
    dragging_tab: bool,
    drag_x: f32,
    maximized: bool,
    colors: appearance.Palette,
    labels: [tab_limit]HeaderLabel = @splat(.{}),

    fn eql(a: *const HeaderPicture, b: *const HeaderPicture) bool {
        if (a.width != b.width or a.scale != b.scale or a.count != b.count or a.active != b.active or
            a.fitted != b.fitted or !std.meta.eql(a.hovered, b.hovered) or !std.meta.eql(a.action_hover, b.action_hover) or a.dragging_tab != b.dragging_tab or
            a.drag_x != b.drag_x or a.maximized != b.maximized or !std.meta.eql(a.colors, b.colors)) return false;
        for (a.labels[0..a.count], b.labels[0..b.count]) |left, right| {
            if (!std.mem.eql(u8, left.text(), right.text())) return false;
        }
        return true;
    }
};

test "top-right OSC 7501 toast leaves tab labels unchanged" {
    const plain: host_status.Summary = .{ .state = .working, .progress = 32, .count = 1 };
    var status = plain;
    @memcpy(status.app[0..3], "zig");
    status.app_len = 3;
    const view = status_toast.fromStatus(status, .{}, "", 0).?;
    try std.testing.expectEqualStrings("⣾ 32% - zig", view.text());
    const geometry = status_toast.geometry(900, 650, chrome.height, 120, .top_right).?;
    try std.testing.expect(geometry.x > 700);
    try std.testing.expect(geometry.y >= chrome.height);
    var label: HeaderLabel = .{};
    label.set("SHELL");
    try std.testing.expectEqualStrings("SHELL", label.text());
}

test "tab chip labels remain only terminal or manual titles, never status" {
    var label: HeaderLabel = .{};
    label.set("AUTOMATIC");
    try std.testing.expectEqualStrings("AUTOMATIC", label.text());
    label.set("MANUAL");
    try std.testing.expectEqualStrings("MANUAL", label.text());
    var full: [1024]u8 = @splat('x');
    @memcpy(full[1021..1024], "界");
    label.set(&full);
    try std.testing.expectEqual(@as(usize, 1024), label.text().len);
    try std.testing.expect(std.unicode.utf8ValidateSlice(label.text()));
}

const HeaderCache = struct {
    texture: ?*c.SDL_Texture = null,
    width: c_int = 0,
    height: c_int = 0,
    picture: ?HeaderPicture = null,

    fn deinit(self: *HeaderCache) void {
        if (self.texture) |texture| c.SDL_DestroyTexture(texture);
        self.* = .{};
    }
};
/// Direct SDL host for terminal panes, Settings state and desktop lifecycle.
pub const App = struct {
    init: std.process.Init,
    configuration: *config.Config,
    fonts: *font_owner.Fonts,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    header_cache: HeaderCache = .{},
    ui_fonts: *font_owner.TextFonts,
    geometry: *canvas.Geometry,
    wake_event: u32,
    window_visibility: c.SDL_WindowFlags = 0,
    visibility_retry_pending: bool = false,
    scale: f32,
    tabs: [tab_limit]?*Tab = @splat(null),
    tab_count: u8 = 0,
    active: u8 = 0,
    keyboard: input.Keyboard = .{},
    preedit: composition.Composition = .{},
    input_timestamp: u64 = 0,
    capture: ?PointerCapture = null,
    selecting: ?SelectionDrag = null,
    scrolling: ?ScrollDrag = null,
    selection_tick: u64 = 0,
    bindings: keybindings.Bindings,
    palette: ?Palette = null,
    rename_editor: ?RenameEditor = null,
    settings_editor: ?settings.Editor = null,
    settings_draft: ?config.Config = null,
    settings_scroll_offset: f32 = 0,
    settings_scroll_grab: ?f32 = null,
    chooser: ?*font_chooser.Chooser = null,
    chooser_preview_base: ?config.Config = null,
    drag: Drag = .none,
    chrome_pressed: chrome.Button = .none,
    hover_point: ?struct { x: f32, y: f32 } = null,
    pointer_buttons: u32 = 0,
    hover_divider: ?layout.Drag = null,
    color_drag: ?u8 = null,
    cursors: [4]?*c.SDL_Cursor = @splat(null),
    cursor_shape: ?usize = null,
    cursor_deadline: ?u64 = null,
    consume_left_release: bool = false,
    focused: bool = false,
    running: bool = true,
    width: f32 = 1000,
    height: f32 = 650,
    notice: [256]u8 = @splat(0),
    notice_len: usize = 0,
    notice_until: u64 = 0,
    // UI-only transient lifetime and Braille refresh, never PTY state.
    toast_owner: ?u16 = null,
    toast_last_summary: host_status.Summary = .{},
    toast_done_until: u64 = 0,
    toast_animated: bool = false,

    const InputUI = settings_input.ForHost(@This());
    const PaintUI = settings_paint.ForHost(@This());

    fn deinit(self: *App) void {
        self.discardSettings();
        self.header_cache.deinit();
        if (!c.SDL_SetCursor(c.SDL_GetDefaultCursor())) self.report(error.SDL);
        for (self.cursors) |cursor| if (cursor) |owned| c.SDL_DestroyCursor(owned);
        if (self.chooser) |chooser| chooser.destroy(allocator);
        if (self.chooser_preview_base) |*original| original.deinit();
        for (self.tabs[0..self.tab_count]) |value| self.destroyTab(value.?);
    }
    fn tab(self: *App) *Tab {
        return self.tabs[self.active].?;
    }
    fn pane(self: *App) *Pane {
        return self.tab().panes[self.tab().tree.active].?;
    }
    /// Check pointer hover against one exact painted control rectangle.
    pub fn isHovered(self: *const App, rect: layout.Rect) bool {
        return if (self.hover_point) |point| rect.contains(point.x, point.y) else false;
    }
    fn headerTabs(self: *const App, width: f32) chrome.Tabs {
        return chrome.Tabs.init(self.tab_count, width, self.configuration.value.tab_width == .fit);
    }
    /// Height of the visible or hidden native tab header.
    pub fn headerHeight(self: *const App) f32 {
        return if (self.configuration.value.hide_single_tab and self.tab_count <= 1) 0 else chrome.height;
    }
    fn terminalBody(self: *const App) layout.Rect {
        const top = self.headerHeight();
        return .{ .x = 0, .y = top, .width = @max(1, self.width), .height = @max(1, self.height - top) };
    }
    /// Stage a bounded, transient notice for the host overlay.
    pub fn setNotice(self: *App, message: []const u8) void {
        self.notice_len = @min(message.len, self.notice.len);
        @memcpy(self.notice[0..self.notice_len], message[0..self.notice_len]);
        self.notice_until = c.SDL_GetTicks() +| 5000;
    }
    fn expireNotice(self: *App, now: u64) void {
        if (now >= self.notice_until) self.notice_len = 0;
    }
    fn waitTimeout(self: *const App, now: u64) ?c_int {
        const scrolling = self.selecting != null and self.selecting.?.edge != 0;
        var timeout: ?u64 = if (scrolling) 50 else null;
        if (self.notice_len != 0) timeout = @min(timeout orelse std.math.maxInt(c_int), @max(1, self.notice_until -| now));
        if (self.toast_animated) timeout = @min(timeout orelse std.math.maxInt(c_int), status_toast.frame_ms - now % status_toast.frame_ms);
        if (self.toast_done_until != 0) timeout = @min(timeout orelse std.math.maxInt(c_int), @max(1, self.toast_done_until -| now));
        if (self.cursor_deadline) |deadline| timeout = @min(timeout orelse std.math.maxInt(c_int), @max(1, deadline -| now));
        return if (timeout) |value| @intCast(@min(value, std.math.maxInt(c_int))) else null;
    }
    fn toastState(self: *App, now: u64) ?status_toast.View {
        self.expireNotice(now);
        self.toast_animated = false;
        var status: terminal.Status = .{};
        var owner: ?u16 = null;
        if (self.tab_count != 0) {
            const current_tab = self.tab();
            owner = @as(u16, self.active) * layout.pane_limit + current_tab.tree.active;
            if (current_tab.panes[current_tab.tree.active]) |owned_pane| status = owned_pane.snapshot();
        }
        // A completion is visible briefly. A blocked/failed job remains
        // until the existing host program-status policy resolves/acknowledges it.
        if (self.toast_owner != owner or !std.meta.eql(self.toast_last_summary, status.program_status)) {
            self.toast_owner = owner;
            self.toast_last_summary = status.program_status;
            self.toast_done_until = if (status.program_status.state == .done) now +| 3000 else 0;
        }
        if (self.toast_done_until != 0 and now >= self.toast_done_until) self.toast_done_until = 0;
        const notice = self.notice[0..self.notice_len];
        if (status.program_status.state == .done and self.toast_done_until == 0 and notice.len == 0) return null;
        const view = status_toast.fromStatus(status.program_status, status.task_progress, notice, now) orelse return null;
        self.toast_animated = view.animated;
        return view;
    }

    // One non-interactive overlay for user notices and program progress.
    // This draws after panes without reserving rows or touching the header
    // texture cache, so status changes cannot redraw tab-chip titles.
    fn drawToast(self: *App, now: u64) !void {
        const view = self.toastState(now) orelse return;
        const text_width = try self.textWidth(view.text());
        const rect = status_toast.geometry(
            self.width,
            self.height,
            self.headerHeight(),
            text_width,
            self.configuration.value.status_toast_position,
        ) orelse return;
        const colors = try self.uiPalette();
        const surface = switch (view.kind) {
            .failed => appearance.closeHover(colors.title),
            .blocked => appearance.hover(colors.title),
            .notice, .running, .done => colors.title,
        };
        // Follow the same four-pixel corners as the tab chips and Settings
        // cards. The prior 12px pill looked foreign to the chrome theme.
        const radius = chrome.Geometry.chip_radius;
        try drawing.fillRounded(self.renderer, rect, colors.border, radius);
        const inner: layout.Rect = .{
            .x = rect.x + 1,
            .y = rect.y + 1,
            .width = @max(0, rect.width - 2),
            .height = @max(0, rect.height - 2),
        };
        try drawing.fillRounded(self.renderer, inner, surface, radius - 1);
        const label: layout.Rect = .{
            .x = inner.x + 12,
            .y = inner.y,
            .width = @max(0, inner.width - 24),
            .height = inner.height,
        };
        if (label.width > 0)
            try self.clippedTextColor(view.text(), label, label.x, colors.text);
    }

    // zig-audit: acknowledge anytype
    // reason: The UI formats exact inferred error sets from distinct owned operations; it neither erases nor returns their error authority.
    fn report(self: *App, failure: anytype) void {
        self.setNotice(@errorName(failure));
    }
    fn profileFont(self: *const App, recipe: config.Profile) u16 {
        return @intCast(if (recipe.font_pixels != 0) recipe.font_pixels else self.configuration.value.terminal_font_pixels);
    }
    fn startup(self: *const App) !config.Profile {
        return self.configuration.defaultProfile();
    }
    fn presentationConfig(self: *App, fonts: *font_owner.Fonts, pixels: u16, stroke: u8) !app_presentation.Config {
        var result = try fonts.config(self.init.io, pixels);
        result.cursor_stroke_pixels = drawing.cursorStroke(pixels, stroke);
        return result;
    }
    fn launch(self: *App, recipe: config.Profile, font_size: u16) CreationError!*terminal.Terminal {
        const inherited = if (recipe.environment.len != 0) try profileEnvironment(allocator, self.init.environ_map, recipe.environment) else self.init.minimal.environ;
        defer if (recipe.environment.len != 0) inherited.block.deinit(allocator);
        const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(font_size)) * self.scale));
        const presentation = try self.presentationConfig(self.fonts, pixels, self.configuration.value.cursor_stroke_pixels);
        errdefer self.fonts.collect();
        return terminal.Terminal.create(allocator, self.init.io, inherited, .{
            .shell = if (recipe.shell.len != 0) recipe.shell else self.init.environ_map.get("SHELL") orelse "/bin/sh",
            .command = if (recipe.command.len != 0) recipe.command else null,
            .arguments = recipe.arguments,
            .cwd = if (recipe.cwd.len != 0) recipe.cwd else null,
            .color_defaults = try self.configuration.value.terminal_colors.resolve(self.configuration.value.terminal_theme),
            .cursor_style = self.configuration.value.cursor_shape.style(),
            .rows = 37,
            .columns = 80,
        }, presentation, self.wake_event, false);
    }
    fn createPane(self: *App, supplied: config.Profile, font_size: ?u16) !*Pane {
        const result = try allocator.create(Pane);
        errdefer allocator.destroy(result);
        result.* = .{
            .recipe = try config.Recipe.copy(allocator, supplied),
            .canvas = canvas.Canvas.init(allocator),
            .font_size = font_size orelse self.profileFont(supplied),
        };
        result.owner = self.launch(result.recipe.value, result.font_size) catch |failure| blk: {
            result.creation_failure = failure;
            break :blk null;
        };
        return result;
    }
    fn destroyPane(self: *App, value: *Pane) void {
        if (self.scrolling) |dragging| if (dragging.pane == value) self.cancelDrag();
        if (self.selecting) |dragging| if (dragging.pane == value) self.cancelDrag();
        if (self.capture) |held| if (held.pane == value) {
            self.finishPointer() catch |failure| self.report(failure);
            self.capture = null;
        };
        if (value.owner) |owner| self.keyboard.forget(owner);
        value.canvas.deinit();
        if (value.owner) |owner| owner.destroy();
        self.fonts.collect();
        value.recipe.deinit();
        allocator.destroy(value);
    }
    fn destroyTab(self: *App, value: *Tab) void {
        if (self.rename_editor) |editor| if (editor.tab == value) self.clearRename();
        for (value.panes) |maybe| if (maybe) |p| self.destroyPane(p);
        value.recipe.deinit();
        allocator.destroy(value);
    }
    /// Discard text preedit before changing the active input owner.
    pub fn cancelComposition(self: *App) void {
        self.preedit.cancel(self.input_timestamp);
        if (!c.SDL_ClearComposition(self.window)) self.report(error.SDLComposition);
    }
    fn loseKeyboard(self: *App) !void {
        self.cursor_deadline = null;
        if (self.tab_count != 0) {
            self.pane().blink.reset();
            self.pane().motion.reset();
        }
        self.hover_divider = null;
        self.setPointer(null) catch |failure| self.report(failure);
        self.cancelDrag();
        self.cancelComposition();
        try self.finishPointer();
        try self.keyboard.releaseTerminal();
        if (self.tab_count == 0 or !self.focused or (self.rename_editor != null or self.palette != null or self.settings_editor != null or self.pane().finder != null)) return;
        const owner = self.pane().owner orelse return;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .out } });
    }
    fn gainKeyboard(self: *App) !void {
        self.cancelComposition();
        if (self.tab_count == 0 or !self.focused or (self.rename_editor != null or self.palette != null or self.settings_editor != null or self.pane().finder != null)) return;
        const owner = self.pane().owner orelse return;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .in } });
    }
    fn panePotentiallyVisible(self: *const App, tab_index: usize, slot: usize) bool {
        const tree = &self.tabs[tab_index].?.tree;
        return self.window_visibility == 0 and tab_index == self.active and (!tree.zoomed or slot == tree.active);
    }

    fn syncVisible(self: *App) void {
        self.visibility_retry_pending = false;
        for (self.tabs[0..self.tab_count], 0..) |maybe, index| {
            const t = maybe.?;
            for (t.panes, 0..) |maybe_p, slot| if (maybe_p) |p| {
                const visible = self.panePotentiallyVisible(index, slot);
                if (!visible) {
                    p.canvas.invalidateContent();
                    p.motion.reset();
                }
                if (p.owner) |owner| owner.setVisible(visible) catch |failure| {
                    self.visibility_retry_pending = true;
                    self.report(failure);
                };
            };
        }
    }
    fn selectTab(self: *App, index: u8) !void {
        if (index >= self.tab_count or index == self.active) return;
        try self.loseKeyboard();
        self.clearRename();
        self.active = index;
        self.syncVisible();
        try self.gainKeyboard();
    }
    fn createTab(self: *App, supplied: config.Profile, font_size: ?u16) !void {
        if (self.tab_count == tab_limit) return error.TabLimit;
        const value = try allocator.create(Tab);
        errdefer allocator.destroy(value);
        value.* = .{ .recipe = try config.Recipe.copy(allocator, supplied) };
        errdefer value.recipe.deinit();
        value.panes[0] = try self.createPane(value.recipe.value, font_size);
        errdefer self.destroyPane(value.panes[0].?);
        try self.loseKeyboard();
        self.clearRename();
        self.tabs[self.tab_count] = value;
        self.active = self.tab_count;
        self.tab_count += 1;
        self.syncVisible();
        self.gainKeyboard() catch |failure| self.report(failure);
    }
    fn closeTab(self: *App) !void {
        try self.loseKeyboard();
        const value = self.tab();
        var i: usize = self.active;
        while (i + 1 < self.tab_count) : (i += 1) self.tabs[i] = self.tabs[i + 1];
        self.tab_count -= 1;
        self.tabs[self.tab_count] = null;
        self.destroyTab(value);
        if (self.tab_count == 0) {
            self.running = false;
            return;
        }
        self.active = @min(self.active, self.tab_count - 1);
        self.syncVisible();
        try self.gainKeyboard();
    }
    fn split(self: *App, axis: layout.Axis) !void {
        var candidate = self.tab().tree;
        const slot = try candidate.split(axis);
        const value = try self.createPane(try self.startup(), null);
        errdefer self.destroyPane(value);
        try self.loseKeyboard();
        self.tab().panes[slot] = value;
        self.tab().tree = candidate;
        self.syncVisible();
        self.gainKeyboard() catch |failure| self.report(failure);
    }
    fn closePane(self: *App) !void {
        if (self.tab().tree.count == 1) return self.closeTab();
        try self.loseKeyboard();
        const retiring = try self.tab().tree.close();
        self.destroyPane(self.tab().panes[retiring].?);
        self.tab().panes[retiring] = null;
        self.syncVisible();
        try self.gainKeyboard();
    }
    fn focusPane(self: *App, slot: u8) !void {
        if (slot == self.tab().tree.active or self.tab().panes[slot] == null) return;
        try self.loseKeyboard();
        self.tab().tree.active = slot;
        self.syncVisible();
        try self.gainKeyboard();
    }
    fn moveTab(self: *App, destination: u8) void {
        if (destination >= self.tab_count or destination == self.active) return;
        const value = self.tab();
        if (destination < self.active) {
            var i: usize = self.active;
            while (i > destination) : (i -= 1) self.tabs[i] = self.tabs[i - 1];
        } else {
            var i: usize = self.active;
            while (i < destination) : (i += 1) self.tabs[i] = self.tabs[i + 1];
        }
        self.tabs[destination] = value;
        self.active = destination;
    }
    fn openPalette(self: *App, profile: bool) !void {
        try self.finishRename(false);
        if (self.settings_editor != null) self.closeSettings();
        if (self.palette) |current| {
            if (current.profile == profile) {
                self.palette = null;
                try self.gainKeyboard();
                return;
            }
        }
        try self.loseKeyboard();
        self.palette = .{ .profile = profile };
    }
    fn recover(self: *App) !void {
        const previous = self.pane();
        const status = previous.snapshot();
        if (previous.owner != null and status.failure == null and !status.closed) {
            if (previous.font_failure != null or previous.graphics_failure != null)
                try self.configureFont(previous, previous.font_size, false);
            try previous.submit(.retry_projection);
            return;
        }
        const next = try self.createPane(try savedRecipe(self.configuration, previous.recipe.value), previous.font_size);
        next.font_overridden = previous.font_overridden;
        errdefer self.destroyPane(next);
        try self.loseKeyboard();
        self.tab().panes[self.tab().tree.active] = next;
        self.destroyPane(previous);
        self.syncVisible();
        self.gainKeyboard() catch |failure| self.report(failure);
    }
    fn actionEnabled(self: *App, action: keybindings.Action) bool {
        var panes: usize = 0;
        for (self.tab().panes) |p| if (p != null) {
            panes += 1;
        };
        return switch (action) {
            .new_tab, .duplicate_tab, .open_local => self.tab_count < tab_limit,
            .split_right, .split_down => panes < layout.pane_limit,
            .toggle_pane_zoom, .next_pane, .previous_pane, .balance_panes => panes > 1,
            .next_tab, .previous_tab => self.tab_count > 1,
            .move_tab_left => self.active > 0,
            .move_tab_right => self.active + 1 < self.tab_count,
            .reset_tab_title => self.tab().title.len != 0,
            .take_size_control => !self.pane().size_control,
            .stop_resizing => self.pane().size_control,
            else => true,
        };
    }
    fn targetEnabled(self: *App, target: keybindings.Target) bool {
        return switch (target) {
            .action => |action| self.actionEnabled(action),
            .select_tab => |index| index < self.tab_count,
            .pane_focus, .pane_swap => |direction| self.tab().tree.neighbor(self.terminalBody(), direction) != null,
            .pane_resize => self.tab().tree.count > 1 and !self.tab().tree.zoomed,
            else => true,
        };
    }
    fn dispatch(self: *App, target: keybindings.Target) !void {
        if (!self.targetEnabled(target)) return;
        self.notice_len = 0;
        if (!(target == .action and target.action == .rename_tab)) try self.finishRename(false);
        if (self.settings_editor != null and !(target == .action and target.action == .open_settings)) {
            self.closeSettings();
            try self.gainKeyboard();
        }
        if (self.palette != null and !(target == .action and
            (target.action == .open_command_palette or target.action == .open_profile_menu)))
        {
            self.palette = null;
            try self.gainKeyboard();
        }
        switch (target) {
            .action => |action| switch (action) {
                .new_tab => try self.createTab(try self.startup(), null),
                .open_local => try self.createTab(try self.configuration.profile(0), null),
                .duplicate_tab => try self.createTab(try savedRecipe(self.configuration, self.tab().recipe.value), null),
                .rename_tab => try self.beginRename(),
                .reset_tab_title => self.tab().title.clear(),
                .new_window => try self.newWindow(),
                .split_right => try self.split(.horizontal),
                .split_down => try self.split(.vertical),
                .toggle_pane_zoom => {
                    self.tab().tree.zoomed = !self.tab().tree.zoomed;
                    self.syncVisible();
                },
                .next_pane, .previous_pane => try self.focusPane(self.tab().tree.cycle(action == .previous_pane)),
                .balance_panes => self.tab().tree.balance(),
                .close_pane => try self.closePane(),
                .close_tab => try self.closeTab(),
                .next_tab => try self.selectTab((self.active + 1) % self.tab_count),
                .previous_tab => try self.selectTab(if (self.active == 0) self.tab_count - 1 else self.active - 1),
                .move_tab_left => if (self.active > 0) self.moveTab(self.active - 1),
                .move_tab_right => self.moveTab(self.active + 1),
                .toggle_fullscreen => {
                    if (!c.SDL_SetWindowFullscreen(self.window, c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_FULLSCREEN == 0)) return error.SDL;
                },
                .recover_instance => try self.recover(),
                .take_size_control => self.pane().size_control = true,
                .stop_resizing => self.pane().size_control = false,
                .open_command_palette => try self.openPalette(false),
                .open_profile_menu => try self.openPalette(true),
                .open_settings => try self.toggleSettings(),
            },
            .select_tab => |index| try self.selectTab(index),
            .paste_clipboard => {
                const text = c.SDL_GetClipboardText() orelse return error.SDL;
                defer c.SDL_free(text);
                if (self.pane().finder != null) try self.findAppend(std.mem.span(text)) else try self.pane().submit(.{ .input = .{ .paste = std.mem.span(text) } });
            },
            .history_oldest => try self.pane().submit(.{ .seek = std.math.maxInt(u32) }),
            .history_live => try self.pane().submit(.{ .seek = 0 }),
            .history_page => |direction| try self.pane().submit(.{ .scroll = @as(i32, @intCast(@max(1, self.pane().rows))) * direction }),
            .pane_focus => |direction| if (self.tab().tree.neighbor(self.terminalBody(), direction)) |slot| try self.focusPane(slot),
            .pane_swap => |direction| {
                if (self.tab().tree.neighbor(self.terminalBody(), direction)) |slot| {
                    const changed = self.tab().tree.swap(slot);
                    std.debug.assert(changed);
                }
            },
            .pane_resize => |direction| {
                const changed = self.tab().tree.resize(self.terminalBody(), direction);
                if (!changed) self.setNotice("No divider in that direction");
            },
            .toggle_find => try self.toggleFind(),
            .adjust_font => |delta| {
                const p = self.pane();
                const next: u16 = @intCast(std.math.clamp(@as(i32, p.font_size) + delta, 8, 48));
                if (next != p.font_size) {
                    try self.configureFont(p, next, true);
                    p.font_overridden = true;
                }
            },
            .copy_selection => {
                const bytes = try (try self.pane().requireOwner()).copySelection(allocator, 1024 * 1024);
                defer allocator.free(bytes);
                try setClipboard(bytes);
            },
        }
    }
    fn surfaceFor(self: *App, value: *Pane) ?commands.Size {
        if (!value.size_control) return null;
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const visible = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..visible.panes]) |place| if (self.tab().panes[place.pane] == value)
            return physicalSurface(place.rect, self.scale);
        return null;
    }
    fn configureFont(self: *App, value: *Pane, logical_size: u16, resize: bool) terminal.ConfigureError!void {
        const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(logical_size)) * self.scale));
        const owner = value.owner orelse {
            value.font_size = logical_size;
            return;
        };
        defer self.fonts.collect();
        const geometry = owner.reconfigure(try self.presentationConfig(self.fonts, pixels, self.configuration.value.cursor_stroke_pixels), if (resize) self.surfaceFor(value) else null) catch |failure| {
            value.font_failure = failure;
            return failure;
        };
        if (value.graphics_failure != null) {
            // The new generation ignores retired GPU residency and supplies complete resources.
            value.canvas.deinit();
            value.canvas = canvas.Canvas.init(allocator);
            value.graphics_failure = null;
        }
        value.font_size = logical_size;
        value.cell_size = geometry.cell_size;
        value.rows = geometry.rows;
        value.columns = geometry.columns;
        value.font_failure = null;
        value.font_repair_pending = false;
    }
    fn displayScale(self: *App) void {
        const next = c.SDL_GetWindowDisplayScale(self.window);
        if (next == self.scale) return;
        if (!std.math.isFinite(next) or next <= 0 or next > 8) {
            self.report(error.DisplayScale);
            return;
        }
        self.scale = next;
        self.ui_fonts.setSize(15 * next) catch |failure| self.report(failure);
        for (self.tabs[0..self.tab_count]) |maybe_tab| for (maybe_tab.?.panes) |maybe_pane| if (maybe_pane) |value| {
            const status = value.snapshot();
            if (value.owner == null or status.failure != null or status.closed) continue;
            self.configureFont(value, value.font_size, true) catch |failure| self.report(failure);
        };
    }
    /// Resolve the staged or live Settings palette for all host chrome.
    pub fn uiPalette(self: *const App) error{ InvalidTheme, InvalidColor }!appearance.Palette {
        return appearance.resolve(self.configuration.value.app_theme, self.configuration.value.app_colors);
    }
    fn applyConfiguration(self: *App, candidate: *config.Config) !void {
        const target = try config.Config.path(allocator, self.init.environ_map);
        defer allocator.free(target);
        try self.applyConfigurationAt(candidate, .cwd(), target);
    }
    fn applyConfigurationAt(self: *App, candidate: *config.Config, dir: std.Io.Dir, target: []const u8) !void {
        try self.updateConfiguration(candidate, dir, target, true);
    }
    fn updateConfiguration(self: *App, candidate: *config.Config, dir: std.Io.Dir, target: []const u8, persist: bool) !void {
        defer self.fonts.collect();
        const bindings = try keybindings.Bindings.fromOverrides(candidate.value.keybindings);
        const previous_colors = try self.configuration.value.terminal_colors.resolve(self.configuration.value.terminal_theme);
        const next_colors = try candidate.value.terminal_colors.resolve(candidate.value.terminal_theme);
        const colors_changed = !std.meta.eql(previous_colors, next_colors);
        const cursor_changed = self.configuration.value.cursor_shape != candidate.value.cursor_shape;
        const stroke_changed = self.configuration.value.cursor_stroke_pixels != candidate.value.cursor_stroke_pixels;
        var paths_changed = false;
        for (self.configuration.value.font.paths(), candidate.value.font.paths()) |old, new| {
            paths_changed = paths_changed or !std.mem.eql(u8, old, new);
        }
        var next_fonts: ?font_owner.Fonts = null;
        defer if (next_fonts) |*owned| owned.deinit();
        var next_ui: ?font_owner.TextFonts = null;
        defer if (next_ui) |*owned| owned.deinit();
        if (paths_changed) {
            next_fonts = try font_owner.Fonts.discover(allocator, self.init.environ_map, candidate.value.font.paths());
            next_fonts.?.atlas_height_limit = self.fonts.atlas_height_limit;
            next_ui = try font_owner.TextFonts.open(allocator, &next_fonts.?, 15 * self.scale);
        }
        const fonts = if (next_fonts) |*value| value else self.fonts;
        var changes: [tab_limit * layout.pane_limit]FontChange = undefined;
        var count: usize = 0;
        errdefer self.rollbackFonts(changes[0..count]);
        for (self.tabs[0..self.tab_count]) |maybe_tab| for (maybe_tab.?.panes) |maybe_pane| if (maybe_pane) |p| {
            const old = try savedRecipe(self.configuration, p.recipe.value);
            const new = try savedRecipe(candidate, p.recipe.value);
            const reset = old.font_pixels != new.font_pixels;
            const overridden = p.font_overridden and !reset;
            const size: u16 = if (overridden) p.font_size else @intCast(if (new.font_pixels != 0) new.font_pixels else candidate.value.terminal_font_pixels);
            var change: FontChange = .{ .pane = p, .size = size, .overridden = overridden };
            const status = p.snapshot();
            if (p.owner) |owner| {
                if ((paths_changed or size != p.font_size or stroke_changed or p.font_repair_pending) and status.failure == null and !status.closed) {
                    const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(size)) * self.scale));
                    // Stage presentation with the canonical grid unchanged. A failed save must
                    // not reset history through a temporary column change.
                    change.geometry = try owner.reconfigure(try self.presentationConfig(fonts, pixels, candidate.value.cursor_stroke_pixels), null);
                }
            }
            changes[count] = change;
            count += 1;
        };
        // The private atomic file is replaced only after every font transaction succeeds.
        if (persist) try candidate.saveAt(self.init.io, dir, target);
        for (changes[0..count]) |change| {
            const p = change.pane;
            p.font_size = change.size;
            p.font_overridden = change.overridden;
            if (change.geometry) |geometry| {
                p.cell_size = geometry.cell_size;
                p.rows = geometry.rows;
                p.columns = geometry.columns;
                p.font_failure = null;
                p.font_repair_pending = false;
                if (p.graphics_failure != null) {
                    p.canvas.deinit();
                    p.canvas = canvas.Canvas.init(allocator);
                    p.graphics_failure = null;
                }
            }
        }
        // Swapping returns the old configuration to the caller's existing cleanup path.
        std.mem.swap(config.Config, self.configuration, candidate);
        self.bindings = bindings;
        if (colors_changed) {
            for (self.tabs[0..self.tab_count]) |maybe_tab| for (maybe_tab.?.panes) |maybe_pane| if (maybe_pane) |target_pane| {
                if (target_pane.owner) |owner| owner.setColorDefaults(next_colors);
            };
        }
        if (cursor_changed) {
            for (self.tabs[0..self.tab_count]) |maybe_tab| for (maybe_tab.?.panes) |maybe_pane| if (maybe_pane) |target_pane| {
                if (target_pane.owner) |owner| owner.setDefaultCursorStyle(self.configuration.value.cursor_shape.style());
            };
        }
        if (next_ui) |owned| {
            self.ui_fonts.deinit();
            self.ui_fonts.* = owned;
            self.header_cache.picture = null;
            next_ui = null;
        }
        if (next_fonts) |owned| {
            self.fonts.deinit();
            self.fonts.* = owned;
            next_fonts = null;
        }
    }
    fn rollbackFonts(self: *App, changes: []const FontChange) void {
        for (changes) |change| {
            if (change.geometry == null) continue;
            const p = change.pane;
            const owner = p.owner orelse continue;
            const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(p.font_size)) * self.scale));
            const presentation = self.presentationConfig(self.fonts, pixels, self.configuration.value.cursor_stroke_pixels) catch |failure| {
                preserveStagedFont(change, failure);
                continue;
            };
            const geometry = owner.reconfigure(presentation, null) catch |failure| {
                preserveStagedFont(change, failure);
                continue;
            };
            p.cell_size = geometry.cell_size;
            p.rows = geometry.rows;
            p.columns = geometry.columns;
            p.font_failure = null;
            p.font_repair_pending = false;
        }
    }
    /// Enter or leave Settings while preserving the staged edit contract.
    pub fn toggleSettings(self: *App) !void {
        try self.finishRename(false);
        if (self.settings_editor != null) {
            self.closeSettings();
            try self.gainKeyboard();
            return;
        }
        try self.loseKeyboard();
        self.palette = null;
        self.settings_editor = .{};
        self.settings_scroll_offset = 0;
        self.settings_scroll_grab = null;
    }
    /// Return the staged Settings configuration when one exists.
    pub fn settingsConfiguration(self: *const App) *const config.Config {
        return if (self.settings_draft) |*draft| draft else self.configuration;
    }
    /// Release a staged Settings draft and clear its editor state.
    pub fn discardSettings(self: *App) void {
        if (self.settings_draft) |*draft| draft.deinit();
        self.settings_draft = null;
        if (self.settings_editor) |*editor| {
            editor.cancel();
            // An unsaved new profile can vanish on Cancel. Never keep its
            // now-invalid index as an expanded disclosure.
            if (editor.profile >= self.configuration.profileCount()) {
                editor.profile = 0;
                editor.details_open = false;
                editor.form_row = 0;
            }
        }
    }
    fn closeSettings(self: *App) void {
        const pending = self.settings_draft != null or (if (self.settings_editor) |editor| editor.editing != null else false);
        self.discardSettings();
        self.settings_editor = null;
        self.settings_scroll_grab = null;
        if (pending) self.setNotice("Unsaved settings discarded");
    }
    /// Discard pending Settings edits without mutating live configuration.
    pub fn settingsCancel(self: *App) void {
        const had_changes = self.settings_draft != null or self.settings_editor.?.editing != null;
        self.discardSettings();
        if (had_changes) self.setNotice("Unsaved settings discarded");
    }
    /// Commit staged Settings using the configured application path.
    pub fn settingsSave(self: *App) !void {
        if (self.settings_draft == null and self.settings_editor.?.editing == null) return;
        const target = try config.Config.path(allocator, self.init.environ_map);
        defer allocator.free(target);
        try self.settingsSaveAt(.cwd(), target);
    }
    /// Commit a validated Settings draft at an explicit testable path.
    pub fn settingsSaveAt(self: *App, dir: std.Io.Dir, target: []const u8) !void {
        const editor = &self.settings_editor.?;
        if (editor.recording) {
            self.setNotice("Capture a shortcut or press Esc first");
            return;
        }
        if (editor.editing) |field_target| try self.changeSetting(field_target, editor.buffer[0..editor.len]);
        if (self.settings_draft) |*draft| {
            try self.applyConfigurationAt(draft, dir, target);
            draft.deinit();
            self.settings_draft = null;
            self.setNotice("Settings saved");
        }
    }
    /// Guard profile retirement while any live terminal still borrows its recipe.
    pub fn profileInUse(self: *App, index: u8) !bool {
        const id = (try self.settingsConfiguration().profile(index)).id;
        for (self.tabs[0..self.tab_count]) |value| {
            const t = value.?;
            if (std.mem.eql(u8, t.recipe.value.id, id)) return true;
            for (t.panes) |maybe| if (maybe) |p| {
                if (std.mem.eql(u8, p.recipe.value.id, id)) return true;
            };
        }
        return false;
    }
    /// Stage one validated Settings mutation without writing a file.
    pub fn changeSetting(self: *App, target: settings.Target, text: []const u8) !void {
        if (target == .delete_profile and try self.profileInUse(target.delete_profile)) return error.ProfileInUse;
        const candidate = try settings.change(self.settingsConfiguration(), self.init.io, target, text);
        if (self.settings_draft) |*draft| draft.deinit();
        self.settings_draft = candidate;
        self.cancelComposition();
        self.settings_editor.?.cancel();
        self.setNotice("Pending changes — Save to apply");
    }
    /// Open the app-owned font picker for one Settings field.
    pub fn openFontChooser(self: *App, mode: font_chooser.Mode, current_path: []const u8) !void {
        self.cancelComposition();
        var original_live: ?config.Config = if (self.settings_editor != null) try config.Config.fromValue(allocator, self.init.io, self.configuration.value) else null;
        errdefer if (original_live) |*value| value.deinit();
        self.chooser = try font_chooser.Chooser.create(allocator, self.init.io, self.settingsConfiguration(), mode, current_path);
        self.chooser_preview_base = original_live;
    }
    fn chooserApply(self: *App, persist: bool) !void {
        const chooser = self.chooser.?;
        var candidate = try chooser.candidate(allocator, self.init.io);
        defer candidate.deinit();
        if (persist and self.settings_editor != null) {
            // Font selection joins the global Settings transaction; the chooser
            // never writes a file while that transaction is open.
            if (chooser.previewed) try self.chooserRestore();
            if (self.settings_draft) |*draft| draft.deinit();
            self.settings_draft = candidate;
            candidate = config.Config.defaults(allocator); // transferred into the draft
        } else if (persist) {
            try self.applyConfiguration(&candidate);
        } else try self.updateConfiguration(&candidate, .cwd(), "", false);
        chooser.previewed = !persist;
        self.cancelComposition();
        if (persist) {
            const notice = if (self.settings_editor != null) "Font pending — Save settings to apply" else if (chooser.mode == .family) "Font family saved" else "Font face saved";
            chooser.destroy(allocator);
            self.chooser = null;
            if (self.chooser_preview_base) |*original| original.deinit();
            self.chooser_preview_base = null;
            self.setNotice(notice);
        } else self.setNotice(if (self.settings_editor != null) "Font preview — Enter stages; Esc restores" else "Font preview — Enter saves; Esc restores");
    }
    fn chooserRestore(self: *App) !void {
        const chooser = self.chooser.?;
        if (chooser.previewed) {
            const original = if (self.chooser_preview_base) |*live| live else &chooser.original;
            var candidate = try config.Config.fromValue(allocator, self.init.io, original.value);
            defer candidate.deinit();
            try self.updateConfiguration(&candidate, .cwd(), "", false);
            chooser.previewed = false;
        }
        self.cancelComposition();
        self.setNotice("Original font restored");
    }
    fn chooserCancel(self: *App) !void {
        try self.chooserRestore();
        self.chooser.?.destroy(allocator);
        self.chooser = null;
        if (self.chooser_preview_base) |*original| original.deinit();
        self.chooser_preview_base = null;
    }
    fn chooserKey(self: *App, event_value: c.SDL_KeyboardEvent) !void {
        const chooser = self.chooser.?;
        const key = event_value.key;
        switch (key) {
            c.SDLK_ESCAPE => try self.chooserCancel(),
            c.SDLK_TAB => {
                const position: u8 = if (chooser.button) |button| button + 1 else 0;
                const next = (position + @as(u8, if (event_value.mod & c.SDL_KMOD_SHIFT != 0) 3 else 1)) % 4;
                chooser.button = if (next == 0) null else next - 1;
            },
            c.SDLK_RETURN => if (chooser.button == 0) try self.chooserApply(false) else if (chooser.button == 2) try self.chooserCancel() else try self.chooserApply(true),
            c.SDLK_UP => chooser.move(-1),
            c.SDLK_DOWN => chooser.move(1),
            c.SDLK_PAGEUP => chooser.move(-@as(i16, @intCast(self.chooserVisible()))),
            c.SDLK_PAGEDOWN => chooser.move(@intCast(self.chooserVisible())),
            else => if (chooser.button == null and try self.textKey(&chooser.edit, chooser.query[0 .. chooser.query.len - 1], &chooser.query_len, event_value)) {
                chooser.list = .{};
                chooser.refresh();
            },
        }
    }
    fn chooserField(self: *const App) layout.Rect {
        const box = InputUI.settingsRect(self);
        return .{ .x = box.x + 12, .y = box.y + 44, .width = @max(1, box.width - 24), .height = 32 };
    }
    fn chooserList(self: *const App) layout.Rect {
        const box = InputUI.settingsRect(self);
        return .{ .x = box.x + 12, .y = box.y + 86, .width = @max(1, (box.width - 36) * 0.45), .height = @max(1, box.height - 142) };
    }
    fn chooserRows(self: *const App) widgets.Rows {
        return .{ .rect = self.chooserList(), .stride = 36 };
    }
    fn chooserVisible(self: *const App) usize {
        return self.chooserRows().visible();
    }
    fn chooserStart(self: *App) usize {
        self.chooser.?.list.reveal(self.chooser.?.result_count, self.chooserVisible());
        return self.chooser.?.list.first;
    }
    fn chooserClick(self: *App, x: f32, y: f32) !void {
        const box = InputUI.settingsRect(self);
        if (!box.contains(x, y)) return self.chooserCancel();
        if (self.chooserField().contains(x, y)) {
            self.chooser.?.button = null;
            return;
        }
        const list = self.chooserList();
        if (y >= box.y + box.height - 42) {
            const third = @max(1, box.width / 3);
            if (x < box.x + third) try self.chooserApply(false) else if (x < box.x + 2 * third) try self.chooserApply(true) else try self.chooserCancel();
        } else if (list.contains(x, y)) {
            const row = self.chooserRows().hit(x, y) orelse return;
            const chosen = row + self.chooserStart();
            if (chosen < self.chooser.?.result_count) self.chooser.?.list.selected = chosen;
        }
    }
    fn drawChooser(self: *App) !void {
        const chooser = self.chooser.?;
        const colors = try self.uiPalette();
        const box = InputUI.settingsRect(self);
        const list = self.chooserList();
        const field = self.chooserField();
        try fill(self.renderer, box, colors.title);
        try outline(self.renderer, box, colors.border);
        try self.drawText(if (chooser.truncated) "Installed fonts — first 256 families" else chooser.title(), box.x + 12, box.y + 12);
        try self.drawField(field, &chooser.edit, chooser.query[0..chooser.query_len], "Search installed font families", chooser.button == null);
        const start = self.chooserStart();
        for (start..@min(chooser.result_count, start + self.chooserVisible())) |index| {
            const row = self.chooserRows().row(index - start);
            try self.drawListRow(row, index == chooser.list.selected, chooser.list.hovered == index, true);
            try self.clippedText(try chooser.label(@intCast(index)), row, row.x + 6);
        }
        try self.drawListScroll(self.chooserRows(), start, chooser.result_count);
        const sample: layout.Rect = .{ .x = list.x + list.width + 12, .y = list.y, .width = @max(1, box.x + box.width - 12 - list.x - list.width - 12), .height = list.height };
        if (chooser.result_count == 0) try self.clippedText("No matching terminal font families", sample, sample.x) else {
            try self.clippedText(try chooser.label(chooser.list.selected), .{ .x = sample.x, .y = sample.y, .width = sample.width, .height = 30 }, sample.x);
            try self.clippedText(try chooser.selectedPath(), .{ .x = sample.x, .y = sample.y + 32, .width = sample.width, .height = 30 }, sample.x);
            const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(sample.x)), .y = @intFromFloat(@floor(sample.y + 68)), .w = @intFromFloat(@ceil(sample.width)), .h = @intFromFloat(@ceil(@max(1, sample.height - 68))) };
            if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
            defer clearClip(self.renderer);
            if (try chooser.sample(self.scale)) |font| {
                for ([_][]const u8{
                    "abcdefghijklmnopqrstuvwxyz",
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                    "0123456789   Il1|  O0  rn m",
                    "() [] {} <> /\\\\ @#$%&",
                    "-> => != == <= >= := ::",
                    "─━│┃┌┬┐╔╦╗╭╮ └┴┘╚╩╝╰╯",
                    "▀▄█▓▒░ ▖▗▘▝ ◀▶▲▼ ●○",
                    "     󰆍 󰘳",
                    "éèêë ñøå ß œ  café naïve",
                    "Ελληνικά  Русский",
                    "العربية  עברית",
                    "日本語  中文  한글",
                }, 0..) |line, number| {
                    try self.drawTextFont(font, line, sample.x, sample.y + 76 + @as(f32, @floatFromInt(number)) * 26);
                }
            }
        }
        const button_width = @max(1, (box.width - 24) / 3);
        const action_labels: [3][]const u8 = .{ "Preview", if (self.settings_editor != null) "Choose · Enter" else "Save · Enter", "Cancel · Esc" };
        for (action_labels, 0..) |label, index| {
            const button: layout.Rect = .{ .x = box.x + 12 + @as(f32, @floatFromInt(index)) * button_width, .y = box.y + box.height - 38, .width = @max(1, button_width - 4), .height = 30 };
            try fill(self.renderer, button, colors.idle);
            try outline(self.renderer, button, if (chooser.button == @as(u8, @intCast(index))) colors.accent else colors.border);
            try self.clippedText(label, button, button.x + 6);
        }
    }
    fn beginRename(self: *App) !void {
        if (self.rename_editor != null) return;
        var editor: RenameEditor = .{ .tab = self.tab() };
        const status = self.pane().snapshot();
        const current = self.tab().title.resolve(status.title[0..status.title_len]);
        // An oversized or malformed application title must not prevent a manual name.
        if (current.len <= editor.bytes.len and tab_title.valid(current))
            try editor.edit.insert(&editor.bytes, &editor.len, current);
        editor.edit.selectAll(editor.len);
        try self.loseKeyboard();
        self.keyboard.retireOverlay();
        self.palette = null;
        self.closeSettings();
        self.rename_editor = editor;
        self.setNotice("Rename tab: Enter saves · Esc cancels · empty restores automatic title");
    }
    fn clearRename(self: *App) void {
        if (self.rename_editor == null) return;
        self.rename_editor = null;
        self.keyboard.retireOverlay();
        self.keyboard.suppress_text = true;
        self.notice_len = 0;
    }
    fn finishRename(self: *App, commit: bool) !void {
        const editor = self.rename_editor orelse return;
        if (commit) {
            var owned = false;
            for (self.tabs[0..self.tab_count]) |value| if (value == editor.tab) {
                owned = true;
                break;
            };
            if (!owned) return error.TabClosed;
            try editor.tab.title.set(editor.bytes[0..editor.len]);
        }
        self.clearRename();
        try self.gainKeyboard();
    }
    fn renameField(self: *const App) !layout.Rect {
        const editor = self.rename_editor orelse return error.TabClosed;
        for (self.tabs[0..self.tab_count], 0..) |value, index| if (value == editor.tab) {
            // A hidden one-tab header stays hidden: editing floats above the pane
            // rather than resizing the canonical terminal for a transient field.
            if (self.headerHeight() == 0) return .{
                .x = 8,
                .y = 8,
                .width = @max(1, @min(400, self.width - 16)),
                .height = 30,
            };
            const rect = self.headerTabs(self.width).body(@intCast(index));
            return .{ .x = rect.x + 3, .y = rect.y + 2, .width = @max(1, rect.width - 6), .height = @max(1, rect.height - 4) };
        };
        return error.TabClosed;
    }
    fn renameKey(self: *App, key: c.SDL_KeyboardEvent) !void {
        if (key.key == c.SDLK_ESCAPE) return self.finishRename(false);
        if (key.key == c.SDLK_RETURN) return self.finishRename(true);
        const editor = &self.rename_editor.?;
        if (try self.textKey(&editor.edit, &editor.bytes, &editor.len, key)) self.cancelComposition();
    }
    fn renameClick(self: *App, x: f32, clicks: u8, extend: bool) !void {
        const rect = try self.renameField();
        const editor = &self.rename_editor.?;
        if (clicks >= 2) {
            editor.edit.selectAll(editor.len);
        } else {
            const point = x - rect.x - 7 + editor.edit.scroll;
            var offset: usize = 0;
            var left: f32 = 0;
            while (offset < editor.len) {
                var next = offset + 1;
                while (next < editor.len and editor.bytes[next] & 0xc0 == 0x80) next += 1;
                const right = try self.textWidth(editor.bytes[0..next]);
                if (point < (left + right) / 2) break;
                offset = next;
                left = right;
            }
            editor.edit.jump(offset, extend);
        }
        self.cancelComposition();
        self.consume_left_release = true;
    }

    /// Apply UTF-8 keyboard edits to a caller-owned bounded text buffer.
    pub fn textKey(self: *App, edit: *widgets.Text, buffer: []u8, len: *usize, event_value: c.SDL_KeyboardEvent) !bool {
        const key = event_value.key;
        const mods = input.semanticModifiers(event_value.mod);
        if (mods.control and key == c.SDLK_A) {
            edit.selectAll(len.*);
            self.keyboard.suppress_text = true;
        } else if (mods.control and (key == c.SDLK_C or key == c.SDLK_X)) {
            self.keyboard.suppress_text = true;
            if (edit.selected()) |range| {
                try setClipboard(buffer[range.start..range.end]);
                if (key == c.SDLK_X) {
                    edit.erase(buffer, len, false);
                    return true;
                }
            }
        } else if (mods.control and key == c.SDLK_V) {
            self.keyboard.suppress_text = true;
            const text = c.SDL_GetClipboardText() orelse return error.SDL;
            defer c.SDL_free(text);
            try edit.insert(buffer, len, std.mem.span(text));
            return true;
        } else switch (key) {
            c.SDLK_LEFT, c.SDLK_RIGHT => edit.navigate(buffer[0..len.*], if (key == c.SDLK_LEFT) -1 else 1, mods.shift),
            c.SDLK_HOME, c.SDLK_END => edit.jump(if (key == c.SDLK_HOME) 0 else len.*, mods.shift),
            c.SDLK_BACKSPACE, c.SDLK_DELETE => {
                if (mods.control and key == c.SDLK_BACKSPACE) edit.selectAll(len.*);
                edit.erase(buffer, len, key == c.SDLK_DELETE);
                return true;
            },
            else => {},
        }
        return false;
    }
    /// Paint an editable text field using the shared UI style.
    pub fn drawField(self: *App, rect: layout.Rect, edit: *widgets.Text, text: []const u8, placeholder: []const u8, active: bool) !void {
        return self.drawFieldStyled(rect, edit, text, placeholder, active, false);
    }
    /// Paint a text field with explicit rounded or square styling.
    pub fn drawFieldStyled(self: *App, rect: layout.Rect, edit: *widgets.Text, text: []const u8, placeholder: []const u8, active: bool, rounded: bool) !void {
        const colors = try self.uiPalette();
        if (rounded) {
            try drawing.fillRounded(self.renderer, rect, if (active) colors.accent else colors.border, chrome.Geometry.chip_radius);
            try drawing.fillRounded(self.renderer, .{ .x = rect.x + 1, .y = rect.y + 1, .width = @max(1, rect.width - 2), .height = @max(1, rect.height - 2) }, colors.panel, chrome.Geometry.chip_radius - 1);
        } else {
            try fill(self.renderer, rect, colors.panel);
            try outline(self.renderer, rect, if (active) colors.accent else colors.border);
        }
        const inner: layout.Rect = .{ .x = rect.x + 7, .y = rect.y + 3, .width = @max(1, rect.width - 14), .height = @max(1, rect.height - 6) };
        const caret = try self.textWidth(text[0..edit.cursor]);
        const scroll = edit.reveal(caret, try self.textWidth(text), inner.width - 2);
        try setClip(self.renderer, inner);
        defer clearClip(self.renderer);
        const origin = inner.x - scroll;
        const ink_y = rect.y + 6;
        try self.drawTextTint(self.ui_fonts.faces[0], if (text.len == 0) placeholder else text, origin, ink_y, if (text.len == 0) colors.muted else colors.text, self.scale);
        if (active) if (edit.selected()) |range| {
            const left = origin + try self.textWidth(text[0..range.start]);
            const right = origin + try self.textWidth(text[0..range.end]);
            const highlight = widgets.intersection(inner, .{ .x = left, .y = inner.y, .width = right - left, .height = inner.height });
            if (highlight) |area| {
                const selected = appearance.selection(colors);
                try fill(self.renderer, area, selected.background);
                try setClip(self.renderer, area);
                try self.drawTextTint(self.ui_fonts.faces[0], text, origin, ink_y, selected.foreground, self.scale);
                try setClip(self.renderer, inner);
            }
        };
        if (active and self.focused and self.preedit.len == 0) try fill(self.renderer, .{ .x = inner.x + caret - scroll, .y = rect.y + 6, .width = 1, .height = @min(18, inner.height) }, colors.accent);
    }

    /// Paint the search or chooser list scrollbar.
    pub fn drawListScroll(self: *App, rows: widgets.Rows, first: usize, count: usize) !void {
        const shown = @min(count, rows.visible());
        if (count <= shown) return;
        const colors = try self.uiPalette();
        const height = @as(f32, @floatFromInt(rows.visible())) * rows.stride - rows.gap;
        const thumb = @max(16, height * @as(f32, @floatFromInt(shown)) / @as(f32, @floatFromInt(count)));
        const offset = @as(f32, @floatFromInt(first)) / @as(f32, @floatFromInt(count - shown));
        const track: layout.Rect = .{ .x = rows.rect.x + rows.rect.width - 3, .y = rows.rect.y, .width = 3, .height = height };
        const chip: layout.Rect = .{ .x = track.x, .y = track.y + (height - thumb) * offset, .width = 3, .height = thumb };
        try fill(self.renderer, track, if (self.isHovered(track)) appearance.hover(colors.border) else colors.border);
        try fill(self.renderer, chip, if (self.isHovered(chip)) appearance.hover(colors.muted) else colors.muted);
    }
    /// Paint selection and hover for a list-style row.
    pub fn drawListRow(self: *App, rect: layout.Rect, selected: bool, hovered: bool, focused: bool) !void {
        const colors = try self.uiPalette();
        if (selected or hovered) {
            const base = if (selected) colors.active else colors.idle;
            try fill(self.renderer, rect, if (hovered) appearance.hover(base) else base);
        }
        if (selected and focused) try fill(self.renderer, .{ .x = rect.x, .y = rect.y + 4, .width = 2, .height = @max(1, rect.height - 8) }, colors.accent);
    }
    fn newWindow(self: *App) !void {
        // Linux fork/exec resolves this exact running image even after an on-disk upgrade.
        var child = try std.process.spawn(self.init.io, .{ .argv = &.{"/proc/self/exe"} });
        errdefer child.kill(self.init.io);
        const thread = try std.Thread.spawn(.{}, reapWindow, .{child.id.?});
        thread.detach();
    }
    fn cancelDrag(self: *App) void {
        self.color_drag = null;
        if (self.settings_scroll_grab != null) {
            self.settings_scroll_grab = null;
            self.consume_left_release = true;
        }
        if (self.scrolling != null) {
            self.scrolling = null;
            self.consume_left_release = true;
        }
        if (self.selecting != null) {
            self.selecting = null;
            self.consume_left_release = true;
        }
        if (self.drag == .none) return;
        self.drag = .none;
        self.consume_left_release = true;
    }
    fn menuProfileCount(self: *const App) usize {
        return @as(usize, self.configuration.profileCount()) + self.configuration.value.scanned_profiles.len;
    }
    fn menuProfile(self: *const App, index: usize) !config.Profile {
        if (index < self.configuration.profileCount()) return self.configuration.profile(@intCast(index));
        const offset = index - self.configuration.profileCount();
        if (offset >= self.configuration.value.scanned_profiles.len) return error.InvalidDefaultProfile;
        return self.configuration.value.scanned_profiles[offset].recipe;
    }
    fn choosePalette(self: *App, index: usize) !void {
        if (!self.palette.?.profile) return self.dispatch(keybindings.definitions[index].target);
        if (index >= self.menuProfileCount()) {
            self.palette = null;
            if (index == self.menuProfileCount()) return self.openPalette(false);
            return self.toggleSettings();
        }
        if (index >= self.configuration.profileCount()) {
            const entry = self.configuration.value.scanned_profiles[index - self.configuration.profileCount()];
            if (!entry.enabled or entry.stale) return error.InactiveScannedProfile;
        }
        const recipe = try self.menuProfile(index);
        // Keep the overlay and original input owner intact if construction cannot commit.
        try self.createTab(recipe, null);
        self.palette = null;
        try self.gainKeyboard();
    }
    fn paletteKey(self: *App, key: c.SDL_Keycode, mods: c.SDL_Keymod) !void {
        var matches: [palette_limit]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        switch (key) {
            c.SDLK_ESCAPE => {
                self.palette = null;
                try self.gainKeyboard();
            },
            c.SDLK_UP => if (count != 0) {
                self.palette.?.list.selected -|= 1;
            },
            c.SDLK_DOWN => if (count != 0) {
                self.palette.?.list.selected = @min(count - 1, self.palette.?.list.selected + 1);
            },
            c.SDLK_PAGEUP, c.SDLK_PAGEDOWN => if (count != 0) {
                const delta = self.paletteRows();
                const selected = &self.palette.?.list.selected;
                selected.* = if (key == c.SDLK_PAGEUP) selected.* -| delta else @min(count - 1, selected.* + delta);
            },
            c.SDLK_HOME, c.SDLK_END => if (mods & c.SDL_KMOD_CTRL != 0) {
                self.palette.?.list.selected = if (key == c.SDLK_HOME) 0 else count -| 1;
            } else {
                self.palette.?.edit.jump(if (key == c.SDLK_HOME) 0 else self.palette.?.len, mods & c.SDL_KMOD_SHIFT != 0);
            },
            c.SDLK_TAB => self.palette.?.cycle(mods & c.SDL_KMOD_SHIFT != 0),

            c.SDLK_RETURN => if (count != 0) try self.choosePalette(matches[@min(self.palette.?.list.selected, count - 1)]),
            else => {
                var event_value = std.mem.zeroes(c.SDL_KeyboardEvent);
                event_value.key = key;
                event_value.mod = mods;
                const p = &self.palette.?;
                if (try self.textKey(&p.edit, &p.query, &p.len, event_value)) p.reset();
            },
        }
        if (self.palette) |*p| {
            p.list.hovered = null;
            p.list.reveal(try p.indices(self.configuration, &matches), self.paletteRows());
        }
    }
    fn findRequest(self: *App, p: *Pane, request: find.Request) !void {
        if (p.selection_serial == std.math.maxInt(u64)) return error.SelectionSerialLimit;
        var admitted = request;
        admitted.serial = p.selection_serial + 1;
        try p.submit(.{ .find = admitted });
        p.selection_serial = admitted.serial;
        if (p.finder) |*editor| editor.serial = admitted.serial;
        p.selection_hit = null;
        self.notice_len = 0;
        self.cancelComposition();
    }
    fn toggleFind(self: *App) !void {
        const p = self.pane();
        try self.loseKeyboard();
        if (p.finder != null) {
            try self.findRequest(p, .{ .serial = 0, .kind = .close });
            p.finder = null;
        } else {
            try self.findRequest(p, try find.Request.query(0, ""));
            p.finder = .{ .serial = p.selection_serial };
        }
        try self.gainKeyboard();
    }
    fn findAppend(self: *App, text: []const u8) !void {
        const p = self.pane();
        var editor = p.finder.?;
        try editor.edit.insert(&editor.bytes, &editor.len, text);
        try self.findRequest(p, try find.Request.query(0, editor.bytes[0..editor.len]));
        editor.serial = p.selection_serial;
        p.finder = editor;
    }
    fn findKey(self: *App, event_key: c.SDL_KeyboardEvent) !void {
        const p = self.pane();
        switch (event_key.key) {
            c.SDLK_ESCAPE => try self.toggleFind(),
            c.SDLK_RETURN, c.SDLK_KP_ENTER, c.SDLK_DOWN, c.SDLK_UP => try self.findRequest(p, .{
                .serial = 0,
                .kind = if (event_key.key == c.SDLK_UP or event_key.mod & c.SDL_KMOD_SHIFT != 0) .previous else .next,
            }),
            else => {
                var editor = p.finder.?;
                if (try self.textKey(&editor.edit, &editor.bytes, &editor.len, event_key)) {
                    try self.findRequest(p, try find.Request.query(0, editor.bytes[0..editor.len]));
                    editor.serial = p.selection_serial;
                }
                p.finder = editor;
            },
        }
    }
    fn findField(rect: c.SDL_FRect) layout.Rect {
        return .{ .x = rect.x, .y = rect.y + @max(0, rect.h - 28), .width = rect.w, .height = @min(28, rect.h) };
    }
    fn drawFind(self: *App, p: *Pane, rect: c.SDL_FRect, status: terminal.Status) !void {
        const editor = if (p.finder) |*value| value else return;
        const field = findField(rect);
        const colors = try self.uiPalette();
        try fill(self.renderer, field, colors.active);
        const query_rect: layout.Rect = .{ .x = field.x + 6, .y = field.y, .width = @max(1, field.width * 0.55 - 12), .height = field.height };
        try self.drawField(query_rect, &editor.edit, editor.bytes[0..editor.len], "Find — type text", true);
        const progress = status.search;
        var buffer: [128]u8 = undefined;
        const text = if (progress.serial != editor.serial) "Waiting…" else if (progress.failure) |failure| @errorName(failure) else switch (progress.phase) {
            .idle => "Enter next · Shift+Enter previous · Esc",
            .scanning => try std.fmt.bufPrint(&buffer, "{d} matches · searching {d}/{d}", .{ progress.count, progress.scanned, progress.total }),
            .complete, .incomplete => try std.fmt.bufPrint(&buffer, "{d}/{d}{s} · Enter next · Esc", .{ if (progress.current) |index| index + 1 else @as(u16, 0), progress.count, if (progress.phase == .incomplete) " · capped" else "" }),
            .stale => "Changed — Enter refreshes · Esc",
            .failed => "Search failed · Enter retries",
        };
        const info_rect: layout.Rect = .{ .x = field.x + field.width * 0.55, .y = field.y, .width = @max(1, field.width * 0.45 - 6), .height = field.height };
        try self.clippedText(text, info_rect, info_rect.x);
    }

    /// Processes every event; unchanged composition acknowledgments cannot repaint themselves.
    fn processEvent(self: *App, value: c.SDL_Event) bool {
        // SDL_SetTextInputArea can elicit an empty editing acknowledgment.
        // Drawing that unchanged preedit sends another caret area and feeds itself.
        const unchanged = value.type == c.SDL_EVENT_TEXT_EDITING and self.preedit.len == 0 and std.mem.span(value.edit.text).len == 0;
        self.event(value) catch |failure| {
            self.report(failure);
            return true;
        };
        return !unchanged;
    }
    fn event(self: *App, value: c.SDL_Event) !void {
        // These events can submit terminal input or change its owner. Retire
        // earlier key intent first, but allow unrelated worker/render wakes
        // between a key-down and its immediate SDL text event.
        switch (value.type) {
            c.SDL_EVENT_MOUSE_BUTTON_DOWN,
            c.SDL_EVENT_MOUSE_BUTTON_UP,
            c.SDL_EVENT_MOUSE_MOTION,
            c.SDL_EVENT_MOUSE_WHEEL,
            c.SDL_EVENT_DROP_FILE,
            c.SDL_EVENT_DROP_TEXT,
            c.SDL_EVENT_WINDOW_FOCUS_GAINED,
            c.SDL_EVENT_WINDOW_FOCUS_LOST,
            => try self.keyboard.flushPending(),
            else => {},
        }
        if (try self.chromeEvent(value)) return;
        self.input_timestamp = value.common.timestamp;
        if (self.visibility_retry_pending and value.type == self.wake_event) self.syncVisible();
        switch (value.type) {
            c.SDL_EVENT_RENDER_TARGETS_RESET => {
                for (self.tabs[0..self.tab_count]) |tab_value| {
                    for (tab_value.?.panes) |maybe_pane| {
                        if (maybe_pane) |p| p.canvas.invalidateContent();
                    }
                }
            },
            c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.running = false,
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                const press = value.type == c.SDL_EVENT_KEY_DOWN;
                if (press) self.cancelDrag();
                const mapping = self.bindings.find(value.key.key, value.key.mod);
                const command = if (mapping) |index| blk: {
                    const target = keybindings.definitions[index].target;
                    if (self.chooser != null or self.rename_editor != null) break :blk null;
                    if (self.settings_editor) |e| {
                        if (e.editing != null or !(target == .action and target.action == .open_settings)) break :blk null;
                    }
                    break :blk target;
                } else null;
                const route = try self.keyboard.route(value.key, press, self.pane().owner, command, self.rename_editor != null or self.palette != null or self.settings_editor != null or self.pane().finder != null);
                switch (route) {
                    .handled => {},
                    .command => |target| try self.dispatch(target),
                    .overlay => if (self.rename_editor != null) try self.renameKey(value.key) else if (self.chooser != null) try self.chooserKey(value.key) else if (self.settings_editor != null) try InputUI.settingsKey(self, value.key) else if (self.palette != null) try self.paletteKey(value.key.key, value.key.mod) else try self.findKey(value.key),
                }
            },
            c.SDL_EVENT_TEXT_EDITING => {
                if (!self.focused or !self.preedit.accepts(value.edit.timestamp)) return;
                const text = std.mem.span(value.edit.text);
                if (text.len != 0) self.keyboard.beginComposition();
                try self.preedit.set(text, value.edit.start, value.edit.length);
            },
            c.SDL_EVENT_TEXT_INPUT => {
                if (!self.focused or !self.preedit.accepts(value.text.timestamp)) return;
                self.preedit.clear();
                const text = std.mem.span(value.text.text);
                if (try self.keyboard.commitText(text)) return;
                if (self.rename_editor) |*editor| {
                    try editor.edit.insert(&editor.bytes, &editor.len, text);
                } else if (self.chooser) |chooser| {
                    try chooser.append(text);
                } else if (self.settings_editor) |*e| {
                    if (!e.recording) try e.append(text);
                } else if (self.palette) |*p| {
                    try p.append(text);
                } else if (self.pane().finder != null) try self.findAppend(text) else try self.pane().submit(.{ .input = .{ .committed_text = text } });
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (mouseButton(value.button.button)) |button|
                try self.pointerDown(value.button.x, value.button.y, button, input.semanticModifiers(c.SDL_GetModState()), value.button.clicks),
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button = mouseButton(value.button.button) orelse return;
                if (button == .left and self.settings_scroll_grab != null) {
                    defer self.settings_scroll_grab = null;
                    InputUI.settingsScrollbarMove(self, value.button.y);
                    return;
                }
                if (button == .left and self.color_drag != null) {
                    const channel = self.color_drag.?;
                    self.color_drag = null;
                    try InputUI.colorPoint(self, channel, value.button.x);
                    return;
                }
                if (button == .left and self.scrolling != null) {
                    defer self.scrolling = null;
                    try self.scrollPoint(value.button.y);
                    return;
                }
                if (button == .left and self.consume_left_release) {
                    self.consume_left_release = false;
                    return;
                }
                if (button == .left and self.selecting != null) {
                    const p = self.selecting.?.pane;
                    self.selecting = null;
                    try self.selectPoint(p, value.button.x, value.button.y, .extend, true);
                    return;
                }
                if (self.capture != null) try self.pointerRelease(button, value.button.x, value.button.y, input.semanticModifiers(c.SDL_GetModState()));
                if (button == .left) self.drag = .none;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                if (self.settings_scroll_grab != null) {
                    InputUI.settingsScrollbarMove(self, value.motion.y);
                } else if (self.color_drag) |channel| {
                    try InputUI.colorPoint(self, channel, value.motion.x);
                } else if (self.scrolling != null) {
                    try self.scrollPoint(value.motion.y);
                } else if (self.selecting) |*dragging| {
                    dragging.x = value.motion.x;
                    dragging.y = value.motion.y;
                    try self.selectPoint(dragging.pane, dragging.x, dragging.y, .extend, true);
                    self.selectionEdge();
                } else if (self.capture) |*held| {
                    const point = self.pointerLocation(held.pane, value.motion.x, value.motion.y, true) orelse held.last;
                    try held.pane.submit(.{ .input = point.event(.move, .none, input.semanticModifiers(c.SDL_GetModState()), held.buttons) });
                    held.last = point;
                } else if (self.drag == .divider) {
                    self.tab().tree.drag(self.drag.divider, value.motion.x, value.motion.y);
                } else if (self.drag == .tab) {
                    self.moveTab(self.drag.tab.move(value.motion.x, self.headerTabs(self.width)));
                } else if (self.palette != null) {
                    try self.paletteHover(value.motion.x, value.motion.y);
                } else if (self.settings_editor == null and self.rename_editor == null) {
                    if (self.pointerPane(value.motion.x, value.motion.y)) |slot| {
                        const p = self.tab().panes[slot].?;
                        const state = p.snapshot().interaction orelse return;
                        if (state.mouse_tracking != .any_event) return;
                        const frame = p.canvas.frame() orelse return;
                        if (frame.history_offset != 0) return;
                        const point = self.pointerLocation(p, value.motion.x, value.motion.y, false) orelse return;
                        try p.submit(.{ .input = point.event(.move, .none, input.semanticModifiers(c.SDL_GetModState()), 0) });
                    }
                }
            },
            c.SDL_EVENT_DROP_FILE, c.SDL_EVENT_DROP_TEXT => {
                if (value.drop.windowID != c.SDL_GetWindowID(self.window)) return;
                try self.drop(value.drop.data, value.type == c.SDL_EVENT_DROP_FILE);
            },
            c.SDL_EVENT_MOUSE_WHEEL => if (self.rename_editor == null) try self.pointerWheel(value.wheel),
            c.SDL_EVENT_WINDOW_HIDDEN => {
                self.window_visibility |= c.SDL_WINDOW_HIDDEN;
                self.syncVisible();
            },
            c.SDL_EVENT_WINDOW_SHOWN => {
                self.window_visibility &= ~c.SDL_WINDOW_HIDDEN;
                self.syncVisible();
            },
            c.SDL_EVENT_WINDOW_MINIMIZED => {
                self.window_visibility |= c.SDL_WINDOW_MINIMIZED;
                self.syncVisible();
            },
            c.SDL_EVENT_WINDOW_RESTORED, c.SDL_EVENT_WINDOW_MAXIMIZED => {
                self.window_visibility &= ~c.SDL_WINDOW_MINIMIZED;
                self.syncVisible();
            },
            c.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                self.focused = true;
                try self.gainKeyboard();
            },
            c.SDL_EVENT_WINDOW_FOCUS_LOST => {
                self.cancelDrag();
                try self.loseKeyboard();
                self.focused = false;
            },
            else => {},
        }
    }
    fn pointerDown(self: *App, x: f32, y: f32, button: vt.Terminal.MouseButton, mods: vt.Terminal.InputModifier, clicks: u8) !void {
        if (self.rename_editor != null) {
            if (button == .left and (try self.renameField()).contains(x, y)) return self.renameClick(x, clicks, mods.shift);
            // Commit an outside click, but do not deliver that same click to the
            // terminal. Header clicks may still select, close or reorder tabs.
            try self.finishRename(true);
            if (y >= self.headerHeight()) {
                if (button == .left) self.consume_left_release = true;
                return;
            }
        }
        if (self.selecting != null or self.scrolling != null) return;
        if (self.capture) |held| {
            const point = self.pointerLocation(held.pane, x, y, true) orelse held.last;
            return self.pointerPress(held.pane, point, button, mods);
        }
        if (self.chooser != null) {
            if (button == .left) try self.chooserClick(x, y);
            return;
        }
        if (self.settings_editor != null) {
            if (button == .left) try InputUI.settingsClick(self, x, y, clicks);
            return;
        }
        if (self.palette != null) {
            if (button != .left) return;
            var matches: [palette_limit]usize = undefined;
            const count = try self.palette.?.indices(self.configuration, &matches);
            const box = self.paletteRect();
            if (!box.contains(x, y)) {
                self.palette = null;
                try self.gainKeyboard();
            } else {
                if (self.palette.?.profile) for (0..picker.labels.len) |index| {
                    if (self.paletteFilterRect(index).contains(x, y)) {
                        self.palette.?.filter = @fromBackingInt(@intCast(index));
                        self.palette.?.reset();
                        return;
                    }
                };
                const start = self.paletteStart(count);
                for (0..@min(count - start, self.paletteRows())) |row| {
                    if (self.paletteRow(row).contains(x, y)) {
                        try self.choosePalette(matches[row + start]);
                        break;
                    }
                }
            }
            return;
        }
        if (y < self.headerHeight()) {
            if (button != .left) return;
            const tabs = self.headerTabs(self.width);
            switch (chrome.headerAt(tabs, x, y)) {
                .tab_close => |index| {
                    // Keep the original selected-tab handoff before retirement.
                    try self.selectTab(index);
                    try self.closeTab();
                    self.consume_left_release = true;
                    return;
                },
                .tab => |index| {
                    try self.selectTab(index);
                    if (clicks >= 2) {
                        try self.beginRename();
                        self.consume_left_release = true;
                    } else self.drag = .{ .tab = chrome.Drag.begin(tabs.tab(index), x) };
                    return;
                },
                .plus => try self.createTab(try self.startup(), null),
                .profiles => try self.openPalette(true),
                .settings => try self.toggleSettings(),
                // Native caption controls are handled earlier by chromeEvent.
                else => {},
            }
            self.consume_left_release = true;
            return;
        }
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        if (button == .left) if (self.tab().tree.grab(self.terminalBody(), x, y)) |held| {
            self.drag = .{ .divider = held };
            return;
        };
        for (places[0..result.panes]) |place| if (place.rect.contains(x, y)) {
            try self.focusPane(place.pane);
            const p = self.pane();
            if (p.finder != null and findField(terminalContent(place.rect, p.snapshot().closed)).contains(x, y)) {
                if (button == .left) self.consume_left_release = true;
                return;
            }
            const frame = p.canvas.frame() orelse return;
            const content = terminalPlacement(terminalContent(place.rect, p.snapshot().closed), frame.surface, self.scale);
            if (scrollbar.Bar.fromFrame(.{ .x = content.x, .y = content.y, .width = content.w, .height = content.h }, frame, self.scale)) |bar| {
                if (button == .left and bar.track.contains(x, y)) {
                    self.scrolling = .{ .pane = p, .bar = bar, .grab = if (bar.thumb.contains(x, y)) y - bar.thumb.y else bar.thumb.height / 2 };
                    try self.scrollPoint(y);
                    return;
                }
            }
            if (button == .left and mods.control) {
                self.consume_left_release = true;
                try self.openHyperlink(p, x, y);
                return;
            }
            const state = p.snapshot().interaction orelse return;
            if (!mods.shift and frame.history_offset == 0 and state.mouse_tracking != .off) {
                const point = self.pointerLocation(p, x, y, false) orelse return;
                try self.pointerPress(p, point, button, mods);
            } else if (button == .left) {
                const kind: terminal.SelectKind = if (clicks >= 3) .row else if (clicks == 2) .word else .start;
                try self.selectPoint(p, x, y, kind, false);
                self.selecting = .{ .pane = p, .x = x, .y = y };
                self.selectionEdge();
                self.selection_tick = c.SDL_GetTicksNS();
            }
            return;
        };
    }
    fn openHyperlink(self: *App, p: *Pane, x: f32, y: f32) !void {
        const frame = p.canvas.frame() orelse return;
        const location = self.pointerLocation(p, x, y, false) orelse return;
        const context = try selection.Context.fromFrame(frame);
        const bytes = try (try p.requireOwner()).copyHyperlink(allocator, context, .{ .row = try context.row(@intCast(location.row)), .col = location.col });
        defer allocator.free(bytes);
        if (!desktop.uriAllowed(bytes)) return error.InvalidHyperlink;
        const uri = try allocator.dupeSentinel(u8, bytes, 0);
        defer allocator.free(uri);
        if (!c.SDL_OpenURL(uri)) return error.SDLBrowser;
    }
    fn drop(self: *App, data: ?[*:0]const u8, file: bool) !void {
        if (data == null or self.rename_editor != null or self.palette != null or self.settings_editor != null or self.pane().finder != null) return;
        const p = self.pane();
        const status = p.snapshot();
        if (p.owner == null or status.failure != null or status.closed) return;
        const supplied = try desktop.eventText(data.?, file);
        var quoted: [desktop.quoted_limit]u8 = undefined;
        const bytes = if (file) try desktop.quoteFile(supplied, &quoted) else try desktop.dropText(supplied);
        self.cancelComposition();
        try p.submit(.{ .input = .{ .paste = bytes } });
    }
    fn desktopHost(self: *App) !void {
        var attention = false;
        for (self.tabs[0..self.tab_count]) |t| for (t.?.panes) |p| if (p) |value| if (value.owner) |owner| {
            if (try owner.takeClipboardSet(allocator)) |bytes| {
                defer allocator.free(bytes);
                try setClipboard(bytes);
            }
            if (owner.takeAttention()) attention = true;
        };
        if (attention and c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_INPUT_FOCUS == 0)
            if (!c.SDL_FlashWindow(self.window, c.SDL_FLASH_BRIEFLY)) return error.SDLAttention;
    }

    fn scrollPoint(self: *App, y: f32) !void {
        const dragging = if (self.scrolling) |*value| value else return;
        const offset = dragging.bar.seek(y, dragging.grab) orelse return;
        if (dragging.last == offset) return;
        try dragging.pane.submit(.{ .seek = offset });
        dragging.last = offset;
    }
    fn drawScrollbar(self: *App, p: *Pane, rect: c.SDL_FRect, frame: @import("frame_info.zig").Info) !void {
        const bar = scrollbar.Bar.fromFrame(.{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, frame, self.scale) orelse return;
        const colors = try self.uiPalette();
        const dragging = if (self.scrolling) |held| held.pane == p else false;
        try fill(self.renderer, bar.track, if (self.isHovered(bar.track) or dragging) appearance.hover(colors.idle) else colors.idle);
        try fill(self.renderer, bar.thumb, if (self.isHovered(bar.thumb) or dragging) appearance.hover(colors.border) else colors.border);
    }

    fn selectPoint(self: *App, p: *Pane, x: f32, y: f32, kind: terminal.SelectKind, captured: bool) !void {
        const frame = p.canvas.frame() orelse return;
        const location = self.pointerLocation(p, x, y, captured) orelse return;
        const context = try selection.Context.fromFrame(frame);
        const hit: SelectionHit = .{ .point = .{ .row = try context.row(@intCast(location.row)), .col = location.col }, .columns = context.columns, .alternate = context.alternate };
        if (kind == .extend and p.selection_hit != null and std.meta.eql(p.selection_hit.?, hit)) return;
        if (p.selection_serial == std.math.maxInt(u64)) return error.SelectionSerialLimit;
        const serial = p.selection_serial + 1;
        try p.submit(.{ .select = .{ .serial = serial, .kind = kind, .context = context, .point = hit.point } });
        p.selection_serial = serial;
        p.selection_hit = hit;
    }
    fn selectionEdge(self: *App) void {
        const dragging = if (self.selecting) |*value| value else return;
        dragging.edge = 0;
        const frame = dragging.pane.canvas.frame() orelse return;
        if (frame.alternate_screen) return;
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| if (self.tab().panes[place.pane] == dragging.pane) {
            const rect = terminalPlacement(terminalContent(place.rect, dragging.pane.snapshot().closed), frame.surface, self.scale);
            const bottom = rect.y + @min(rect.h, @as(f32, @floatFromInt(frame.surface.height)) / self.scale);
            const band = @min(@as(f32, @floatFromInt(frame.cell_size.height)) / self.scale * 2, (bottom - rect.y) / 2);
            if (dragging.y < rect.y + band and frame.history_offset < frame.history_count) dragging.edge = 1 else if (dragging.y >= bottom - band and frame.history_offset != 0) dragging.edge = -1;
        };
    }
    fn selectionTick(self: *App) !void {
        self.selectionEdge();
        const dragging = self.selecting orelse return;
        if (dragging.edge == 0) return;
        const now = c.SDL_GetTicksNS();
        if (now - self.selection_tick < 50 * std.time.ns_per_ms) return;
        self.selection_tick = now;
        try dragging.pane.submit(.{ .scroll = dragging.edge });
    }
    fn pointerPane(self: *App, x: f32, y: f32) ?u8 {
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| if (place.rect.contains(x, y)) return place.pane;
        return null;
    }
    fn pointerLocation(self: *App, p: *Pane, x: f32, y: f32, captured: bool) ?pointer.Location {
        const frame = p.canvas.frame() orelse return null;
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| if (self.tab().panes[place.pane] == p) {
            const rect = terminalPlacement(terminalContent(place.rect, p.snapshot().closed), frame.surface, self.scale);
            return pointer.locate(.{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, self.scale, frame.cell_size, frame.surface, x, y, captured);
        };
        return null;
    }
    // SDL automatically captures held button gestures; this state binds their semantic owner.
    fn pointerPress(self: *App, p: *Pane, point: pointer.Location, button: vt.Terminal.MouseButton, mods: vt.Terminal.InputModifier) !void {
        const bit = pointer.buttonBit(button);
        const before: u8 = if (self.capture) |held| held.buttons else 0;
        if (before & bit != 0) return;
        const after = before | bit;
        try p.submit(.{ .input = point.event(.press, button, mods, after) });
        self.capture = .{ .pane = p, .buttons = after, .last = point };
    }
    fn pointerRelease(self: *App, button: vt.Terminal.MouseButton, x: f32, y: f32, mods: vt.Terminal.InputModifier) !void {
        const held = self.capture orelse return;
        const bit = pointer.buttonBit(button);
        if (held.buttons & bit == 0) return;
        const point = self.pointerLocation(held.pane, x, y, true) orelse held.last;
        const after = held.buttons & ~bit;
        held.pane.submit(.{ .input = point.event(.release, button, mods, after) }) catch |failure| {
            if (failure != error.TerminalStopped) return failure;
        };
        self.capture = if (after == 0) null else .{ .pane = held.pane, .buttons = after, .last = point };
    }
    fn finishPointer(self: *App) !void {
        for ([_]vt.Terminal.MouseButton{ .left, .middle, .right }) |button|
            try self.pointerRelease(button, -std.math.inf(f32), -std.math.inf(f32), .{});
    }
    /// Route wheel input to the current modal, page or terminal owner.
    pub fn pointerWheel(self: *App, wheel: c.SDL_MouseWheelEvent) !void {
        if (self.chooser) |chooser| {
            if (std.math.isFinite(wheel.y)) chooser.list.scroll(@intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256)), chooser.result_count, self.chooserVisible());
            return;
        }
        if (self.settings_editor) |*editor| {
            if (!std.math.isFinite(wheel.y)) return;
            if (editor.editing) |target| {
                if (settings.choiceCount(target, self.settingsConfiguration()) != 0 and InputUI.settingsDropdown(self).rect.contains(wheel.mouse_x, wheel.mouse_y)) {
                    const offset: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
                    editor.choice_list.scroll(offset, settings.choiceCount(target, self.settingsConfiguration()), InputUI.settingsDropdown(self).rows.visible());
                    try editor.selectChoice(self.settingsConfiguration(), editor.choice_list.selected);
                    return;
                }
            }
            if (InputUI.settingsFormView(self)) |view| {
                if (view.bounds.contains(wheel.mouse_x, wheel.mouse_y)) InputUI.settingsScrollBy(self, -wheel.y * 48);
                return;
            }
            if (editor.editing != null) return;
            var rows: [settings.row_limit]settings.Row = undefined;
            var filtered: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &rows);
            const visible = editor.indices(rows[0..count], &filtered);
            const offset: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
            editor.list.scroll(offset, visible, InputUI.settingsVisible(self));
            editor.content_focus = true;
            return;
        }
        if (self.palette) |*palette| {
            if (!std.math.isFinite(wheel.y)) return;
            var matches: [palette_limit]usize = undefined;
            const count = try palette.indices(self.configuration, &matches);
            const delta: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
            palette.list.scroll(delta, count, self.paletteRows());
            return;
        }
        if (self.pane().finder != null) return;
        const slot = self.pointerPane(wheel.mouse_x, wheel.mouse_y) orelse return;
        const p = self.tab().panes[slot].?;
        const frame = p.canvas.frame() orelse return;
        const mods = input.semanticModifiers(c.SDL_GetModState());
        const route = pointer.wheelRoute(frame.history_offset != 0, mods.shift, p.snapshot().interaction, frame.alternate_screen);
        const steps = p.wheel.consume(wheel.y * @as(f32, if (wheel.direction == c.SDL_MOUSEWHEEL_FLIPPED) -1 else 1), route);
        if (steps == 0) return;
        switch (route) {
            .history => try p.submit(.{ .scroll = steps }),
            .terminal => {
                const point = self.pointerLocation(p, wheel.mouse_x, wheel.mouse_y, false) orelse return;
                const button: vt.Terminal.MouseButton = if (steps > 0) .wheel_up else .wheel_down;
                for (0..@abs(steps)) |_| try p.submit(.{ .input = point.event(.wheel, button, mods, if (self.capture) |held| if (held.pane == p) held.buttons else 0 else 0) });
            },
            .alternate => {
                const key: vt.Terminal.Key = .{ .named = if (steps > 0) .up else .down };
                for (0..@abs(steps)) |_| {
                    try p.submit(.{ .input = .{ .key = .{ .key = key, .action = .press } } });
                    try p.submit(.{ .input = .{ .key = .{ .key = key, .action = .release } } });
                }
            },
            .wait, .ignore => {},
        }
    }
    fn paletteRows(self: *const App) usize {
        if (self.palette.?.profile) return @min(self.menuProfileCount() + 2, @max(1, @as(usize, @intFromFloat(@floor(@max(0, self.height - self.headerHeight() - 148) / 44)))));
        return @max(1, @min(keybindings.definitions.len, @as(usize, @intFromFloat(@floor(@max(0, self.height - 134) / 36)))));
    }
    fn paletteRect(self: *const App) layout.Rect {
        if (self.palette.?.profile) {
            const width = @min(480, @max(1, self.width - 24));
            return .{ .x = @min(self.headerTabs(self.width).profiles().x, @max(0, self.width - width - 12)), .y = self.headerHeight(), .width = width, .height = @min(@max(1, self.height - self.headerHeight() - 12), 136 + @as(f32, @floatFromInt(self.paletteRows())) * 44) };
        }
        const tall = @min(@max(1, self.height - 32), 102 + @as(f32, @floatFromInt(self.paletteRows())) * 36);
        const width = @min(580, @max(1, self.width - 32));
        return .{ .x = (self.width - width) / 2, .y = @min(92, @max(0, (self.height - tall) / 2)), .width = width, .height = tall };
    }
    fn paletteField(self: *const App) layout.Rect {
        const box = self.paletteRect();
        return .{ .x = box.x + 12, .y = box.y + 12, .width = @max(1, box.width - 24), .height = 34 };
    }
    fn paletteFilterRect(self: *const App, index: usize) layout.Rect {
        const box = self.paletteRect();
        const width = @max(1, (box.width - 24) / @as(f32, @floatFromInt(picker.labels.len)));
        return .{ .x = box.x + 12 + @as(f32, @floatFromInt(index)) * width, .y = box.y + 54, .width = @max(1, width - 4), .height = 28 };
    }
    fn paletteStart(self: *App, count: usize) usize {
        self.palette.?.list.reveal(count, self.paletteRows());
        return self.palette.?.list.first;
    }
    fn paletteList(self: *const App) widgets.Rows {
        const box = self.paletteRect();
        const profiles = self.palette.?.profile;
        const stride: f32 = if (profiles) 44 else 36;
        return .{ .rect = .{ .x = box.x + (if (profiles) @as(f32, 8) else 18), .y = box.y + (if (profiles) @as(f32, 94) else 62), .width = @max(1, box.width - (if (profiles) @as(f32, 24) else 44)), .height = @as(f32, @floatFromInt(self.paletteRows())) * stride }, .stride = stride };
    }
    fn paletteRow(self: *const App, number: usize) layout.Rect {
        return self.paletteList().row(number);
    }
    fn paletteHover(self: *App, x: f32, y: f32) !void {
        var matches: [palette_limit]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        const first = self.paletteStart(count);
        self.palette.?.list.hovered = null;
        for (0..@min(count - first, self.paletteRows())) |row| {
            if (self.paletteRow(row).contains(x, y)) {
                self.palette.?.list.hovered = first + row;
                break;
            }
        }
    }
    fn drawPalette(self: *App) !void {
        var matches: [palette_limit]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        const box = self.paletteRect();
        const colors = try self.uiPalette();
        const profiles = self.palette.?.profile;
        try fill(self.renderer, box, colors.title);
        try outline(self.renderer, box, colors.border);
        const field = self.paletteField();
        try self.drawField(field, &self.palette.?.edit, self.palette.?.query[0..self.palette.?.len], if (profiles) "Search profiles" else "Search commands", true);
        if (profiles) for (picker.labels, 0..) |label, index| {
            const chip = self.paletteFilterRect(index);
            const active = @backingInt(self.palette.?.filter) == index;
            const base = if (active) colors.active else colors.idle;
            try fill(self.renderer, chip, if (self.isHovered(chip)) appearance.hover(base) else base);
            try outline(self.renderer, chip, if (active) colors.accent else colors.border);
            try self.clippedTextColor(label, .{ .x = chip.x + 7, .y = chip.y, .width = @max(1, chip.width - 14), .height = chip.height }, chip.x + 7, if (active) colors.text else colors.muted);
        };
        const start = self.paletteStart(count);
        const default_id = if (profiles) (try self.configuration.defaultProfile()).id else "";
        if (count == 0) try self.clippedTextColor("No matching entries", self.paletteRow(0), box.x + 18, colors.muted);
        const shown = @min(count - start, self.paletteRows());
        for (matches[start .. start + shown], start..) |index, number| {
            const row = self.paletteRow(number - start);
            try self.drawListRow(row, number == self.palette.?.list.selected, self.palette.?.list.hovered == number, true);
            if (profiles) {
                if (index < self.menuProfileCount()) {
                    const recipe = try self.menuProfile(index);
                    const default = std.mem.eql(u8, recipe.id, default_id);
                    try self.clippedText(recipe.name, .{ .x = row.x + 10, .y = row.y, .width = @max(1, row.width - (if (default) @as(f32, 90) else 20)), .height = 23 }, row.x + 10);
                    var detail_buffer: [640]u8 = undefined;
                    const kind = if (index < self.configuration.profileCount()) "Saved" else switch (self.configuration.value.scanned_profiles[index - self.configuration.profileCount()].kind) {
                        .shell => "Shell",
                        .repl => "REPL",
                        .ssh => "Remote",
                    };
                    const detail = try std.fmt.bufPrint(&detail_buffer, "{s} · {s}", .{ kind, if (recipe.shell.len != 0) recipe.shell else "default shell" });
                    try self.clippedTextColor(detail, .{ .x = row.x + 10, .y = row.y + 18, .width = @max(1, row.width - 20), .height = 23 }, row.x + 10, colors.muted);
                    if (default) try self.clippedTextColor("default", .{ .x = row.x + row.width - 72, .y = row.y, .width = 68, .height = 23 }, row.x + row.width - 72, colors.muted);
                } else try self.clippedText(if (index == self.menuProfileCount()) "Command Palette" else "Settings", row, row.x + 10);
            } else {
                const binding = self.bindings.rows[index];
                const label: layout.Rect = .{ .x = row.x + 10, .y = row.y + 2, .width = @max(1, row.width - 205), .height = 28 };
                try self.clippedTextColor(keybindings.definitions[index].label, label, label.x, if (self.targetEnabled(keybindings.definitions[index].target)) colors.text else colors.muted);
                if (binding.len != 0) try self.clippedText(binding.text[0..binding.len], .{ .x = row.x + row.width - 195, .y = row.y + 2, .width = 185, .height = 28 }, row.x + row.width - 195);
            }
        }
        try self.drawListScroll(self.paletteList(), start, count);
        var footer: [128]u8 = undefined;
        const text = if (count > self.paletteRows())
            try std.fmt.bufPrint(&footer, "{d}–{d} of {d} · {s}", .{ start + 1, start + shown, count, if (profiles) "Tab: category" else "↑↓: select" })
        else if (profiles)
            try std.fmt.bufPrint(&footer, "{d} entries · Tab: category", .{count})
        else
            "Enter: run · Esc: close";
        try self.clippedTextColor(text, .{ .x = box.x + 18, .y = box.y + box.height - 32, .width = @max(1, box.width - 36), .height = 26 }, box.x + 18, colors.muted);
    }
    /// Paint UI text clipped to the specified rectangle.
    pub fn clippedText(self: *App, text: []const u8, rect: layout.Rect, x: f32) !void {
        return self.clippedTextColor(text, rect, x, (try self.uiPalette()).text);
    }
    /// Paint tinted UI text without escaping its clipping bounds.
    pub fn clippedTextColor(self: *App, text: []const u8, rect: layout.Rect, x: f32, color: c.SDL_Color) !void {
        return self.clippedTextColorAtScale(text, rect, x, color, self.scale);
    }
    /// Borrow an accepted header's scale instead of the mutable window scale.
    fn clippedTextColorAtScale(self: *App, text: []const u8, rect: layout.Rect, x: f32, color: c.SDL_Color, scale: f32) !void {
        const nested = c.SDL_RenderClipEnabled(self.renderer);
        var previous: c.SDL_Rect = undefined;
        if (nested and !c.SDL_GetRenderClipRect(self.renderer, &previous)) return error.SDL;
        var clip = rect;
        if (nested) {
            const left = @max(rect.x, @as(f32, @floatFromInt(previous.x)));
            const top = @max(rect.y, @as(f32, @floatFromInt(previous.y)));
            const right = @min(rect.x + rect.width, @as(f32, @floatFromInt(previous.x + previous.w)));
            const bottom = @min(rect.y + rect.height, @as(f32, @floatFromInt(previous.y + previous.h)));
            if (right <= left or bottom <= top) return;
            clip = .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
        }
        try setClip(self.renderer, clip);
        defer if (nested) {
            std.debug.assert(c.SDL_SetRenderClipRect(self.renderer, &previous));
        } else clearClip(self.renderer);
        try self.drawTextTint(self.ui_fonts.faces[0], text, x, rect.y + 6, color, scale);
    }
    /// Paint a string using the app's active text font.
    pub fn drawText(self: *App, bytes: []const u8, x: f32, y: f32) !void {
        try self.drawTextFont(self.ui_fonts.faces[0], bytes, x, y);
    }
    fn drawTextFont(self: *App, font: *c.TTF_Font, bytes: []const u8, x: f32, y: f32) !void {
        return self.drawTextTint(font, bytes, x, y, (try self.uiPalette()).text, self.scale);
    }
    fn drawTextTint(self: *App, font: *c.TTF_Font, bytes: []const u8, x: f32, y: f32, color: c.SDL_Color, scale: f32) !void {
        if (bytes.len == 0) return;
        const surface = c.TTF_RenderText_Blended(font, bytes.ptr, bytes.len, color) orelse return error.TTF;
        defer c.SDL_DestroySurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return error.SDL;
        defer c.SDL_DestroyTexture(texture);
        const rect: c.SDL_FRect = .{ .x = x, .y = y, .w = @as(f32, @floatFromInt(surface.*.w)) / scale, .h = @as(f32, @floatFromInt(surface.*.h)) / scale };
        if (!c.SDL_RenderTexture(self.renderer, texture, null, &rect)) return error.SDL;
    }
    fn textWidth(self: *App, bytes: []const u8) !f32 {
        if (bytes.len == 0) return 0;
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.TTF_GetStringSize(self.ui_fonts.faces[0], bytes.ptr, bytes.len, &width, &height)) return error.TTF;
        return @as(f32, @floatFromInt(width)) / self.scale;
    }
    fn drawComposition(self: *App) !void {
        if (!self.focused) return;
        var clip: layout.Rect = undefined;
        var x: f32 = undefined;
        var y: f32 = undefined;
        var cell_height: f32 = 20;
        var logical_font: f32 = 15;
        if (self.rename_editor) |editor| {
            clip = try self.renameField();
            x = clip.x + 7 + try self.textWidth(editor.bytes[0..editor.edit.cursor]) - editor.edit.scroll;
            y = clip.y + 6;
        } else if (self.chooser) |chooser| {
            clip = self.chooserField();
            x = clip.x + 7 + try self.textWidth(chooser.query[0..chooser.edit.cursor]) - chooser.edit.scroll;
            y = clip.y + 6;
        } else if (self.settings_editor) |e| {
            if ((e.editing == null and !e.search) or e.recording or (e.editing != null and (settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice()) or e.button != null) {
                if (!c.SDL_SetTextInputArea(self.window, null, 0)) return error.SDL;
                return;
            }
            clip = InputUI.settingsField(self);
            const text = if (e.editing != null) e.buffer[0..e.len] else e.query[0..e.query_len];
            const edit = if (e.editing != null) e.edit else e.query_edit;
            x = clip.x + 7 + try self.textWidth(text[0..edit.cursor]) - edit.scroll;
            y = clip.y + 6;
        } else if (self.palette) |p| {
            clip = self.paletteField();
            x = clip.x + 7 + try self.textWidth(p.query[0..p.edit.cursor]) - p.edit.scroll;
            y = clip.y + 1;
        } else if (self.pane().finder) |editor| {
            const p = self.pane();
            var places: [layout.pane_limit]layout.Placement = undefined;
            var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
            const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
            var found = false;
            for (places[0..result.panes]) |place| if (self.tab().panes[place.pane] == p) {
                clip = findField(terminalContent(place.rect, p.snapshot().closed));
                clip.width = @max(1, clip.width * 0.55 - 6);
                found = true;
                break;
            };
            if (!found) return;
            x = clip.x + 13 + try self.textWidth(editor.bytes[0..editor.edit.cursor]) - editor.edit.scroll;
            y = clip.y + @min(6, @max(0, clip.height - 1));
        } else {
            const p = self.pane();
            const frame = p.canvas.frame() orelse {
                if (!c.SDL_SetTextInputArea(self.window, null, 0)) return error.SDL;
                return;
            };
            if (frame.history_offset != 0) {
                if (!c.SDL_SetTextInputArea(self.window, null, 0)) return error.SDL;
                return;
            }
            var places: [layout.pane_limit]layout.Placement = undefined;
            var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
            const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
            var found = false;
            for (places[0..result.panes]) |place| if (self.tab().panes[place.pane] == p) {
                const rect = terminalPlacement(terminalContent(place.rect, p.snapshot().closed), frame.surface, self.scale);
                clip = .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h };
                found = true;
                break;
            };
            if (!found) return;
            const status = p.snapshot();
            const cell_width = @as(f32, @floatFromInt(frame.cell_size.width)) / self.scale;
            cell_height = @as(f32, @floatFromInt(frame.cell_size.height)) / self.scale;
            x = clip.x + @as(f32, @floatFromInt(status.cursor_col)) * cell_width;
            y = clip.y + @as(f32, @floatFromInt(status.cursor_row)) * cell_height;
            x = std.math.clamp(x, clip.x, clip.x + clip.width - @min(1, clip.width));
            y = std.math.clamp(y, clip.y, clip.y + clip.height - @min(cell_height, clip.height));
            logical_font = @floatFromInt(p.font_size);
        }
        if (self.preedit.len != 0) try self.ui_fonts.setSize(logical_font * self.scale);
        defer if (self.preedit.len != 0) self.ui_fonts.setSize(15 * self.scale) catch |failure| self.report(failure);
        const text = self.preedit.text();
        const text_width = try self.textWidth(text);
        const caret = try self.textWidth(text[0..composition.byteOffset(text, self.preedit.start)]);
        const available = @max(1, clip.x + clip.width - x);
        const area: c.SDL_Rect = .{
            .x = @intFromFloat(@floor(x)),
            .y = @intFromFloat(@floor(y)),
            .w = @intFromFloat(@ceil(@min(available, @max(2, @max(text_width, caret + 2))))),
            .h = @intFromFloat(@ceil(@min(cell_height, clip.y + clip.height - y))),
        };
        if (!c.SDL_SetTextInputArea(self.window, &area, @intFromFloat(@floor(@min(caret, @as(f32, @floatFromInt(area.w - 1))))))) return error.SDL;
        if (text.len == 0) return;
        const target: c.SDL_Rect = .{ .x = @intFromFloat(@floor(clip.x)), .y = @intFromFloat(@floor(clip.y)), .w = @intFromFloat(@ceil(clip.width)), .h = @intFromFloat(@ceil(clip.height)) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &target)) return error.SDL;
        defer clearClip(self.renderer);
        try fill(self.renderer, .{ .x = x, .y = y, .width = @min(available, @max(2, text_width)), .height = cell_height }, .{ .r = 24, .g = 25, .b = 33, .a = 255 });
        try self.drawText(text, x, y);
        try fill(self.renderer, .{ .x = x, .y = y + cell_height - 1, .width = @min(available, @max(2, text_width)), .height = 1 }, (try self.uiPalette()).accent);
    }
    fn setPointer(self: *App, shape: ?usize) !void {
        if (shape == self.cursor_shape) return;
        if (shape) |index| {
            if (self.cursors[index] == null) self.cursors[index] = c.SDL_CreateSystemCursor(([_]c.SDL_SystemCursor{ c.SDL_SYSTEM_CURSOR_EW_RESIZE, c.SDL_SYSTEM_CURSOR_NS_RESIZE, c.SDL_SYSTEM_CURSOR_TEXT, c.SDL_SYSTEM_CURSOR_MOVE })[index]) orelse return error.SDL;
            if (!c.SDL_SetCursor(self.cursors[index].?)) return error.SDL;
        } else if (!c.SDL_SetCursor(c.SDL_GetDefaultCursor())) return error.SDL;
        self.cursor_shape = shape;
    }
    fn pointerHover(self: *App, x: f32, y: f32) !void {
        self.hover_divider = null;
        if (self.chooser) |chooser| {
            const start = self.chooserStart();
            chooser.list.hovered = if (self.chooserRows().hit(x, y)) |row| if (start + row < chooser.result_count) start + row else null else null;
            return self.setPointer(if (self.chooserField().contains(x, y)) 2 else null);
        }
        if (self.settings_editor) |*e| {
            if (InputUI.settingsFormView(self) != null) {
                e.list.hovered = null;
                const text_field = e.editing != null and !(settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice();
                return self.setPointer(if (text_field and InputUI.settingsField(self).contains(x, y)) 2 else null);
            }
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const shown = e.indices(all[0..count], &indices);
            const start = InputUI.settingsStart(self, shown);
            e.list.hovered = if (InputUI.settingsRows(self).hit(x, y)) |row| if (start + row < shown) start + row else null else null;
            return self.setPointer(if ((e.search or (e.editing != null and !(settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice())) and InputUI.settingsField(self).contains(x, y)) 2 else null);
        }
        if (self.rename_editor != null) return self.setPointer(if ((try self.renameField()).contains(x, y)) 2 else null);
        if (self.palette != null) return self.setPointer(if (self.paletteField().contains(x, y)) 2 else null);
        if (self.drag == .divider) {
            const held = self.drag.divider;
            return self.setPointer(if (held.corner()) 3 else if (held.dividers[0].axis == .horizontal) 0 else 1);
        }
        self.hover_divider = self.tab().tree.hover(self.terminalBody(), x, y);
        if (self.hover_divider) |held|
            return self.setPointer(if (held.corner()) 3 else if (held.dividers[0].axis == .horizontal) 0 else 1);
        try self.setPointer(null);
    }
    fn chromeEvent(self: *App, event_value: c.SDL_Event) !bool {
        if (event_value.type == c.SDL_EVENT_WINDOW_FOCUS_LOST) {
            self.pointer_buttons = 0;
            self.chrome_pressed = .none;
            self.hover_point = null;
        }
        if (event_value.type == c.SDL_EVENT_WINDOW_MOUSE_LEAVE) {
            self.hover_point = null;
            self.hover_divider = null;
            try self.setPointer(null);
        }
        if (event_value.type == c.SDL_EVENT_MOUSE_MOTION) {
            self.hover_point = .{ .x = event_value.motion.x, .y = event_value.motion.y };
            try self.pointerHover(event_value.motion.x, event_value.motion.y);
            return self.chrome_pressed != .none;
        }
        const down = event_value.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
        if (!down and event_value.type != c.SDL_EVENT_MOUSE_BUTTON_UP) return false;
        const event_button = event_value.button;
        if (event_button.button > 0 and event_button.button < 32) {
            const bit = @as(u32, 1) << @as(u5, @intCast(event_button.button));
            if (down) self.pointer_buttons |= bit else self.pointer_buttons &= ~bit;
        }
        if (self.headerHeight() == 0) return false;
        const target = chrome.buttonAt(event_button.x, event_button.y, self.width);
        if (event_button.button == c.SDL_BUTTON_LEFT) {
            if (down and target != .none) {
                self.chrome_pressed = target;
                return true;
            }
            if (!down and self.chrome_pressed != .none) {
                const pressed = self.chrome_pressed;
                self.chrome_pressed = .none;
                if (pressed == target) switch (target) {
                    .none => {},
                    .minimize => if (!c.SDL_MinimizeWindow(self.window)) return error.SDL,
                    .maximize => {
                        const flags = c.SDL_GetWindowFlags(self.window);
                        if (flags & c.SDL_WINDOW_FULLSCREEN == 0) {
                            if (flags & c.SDL_WINDOW_MAXIMIZED != 0) {
                                if (!c.SDL_RestoreWindow(self.window)) return error.SDL;
                            } else if (!c.SDL_MaximizeWindow(self.window)) return error.SDL;
                        }
                    },
                    .close => self.running = false,
                };
                return true;
            }
        }
        if (down and event_button.button == c.SDL_BUTTON_RIGHT and self.headerTabs(self.width).caption().contains(event_button.x, event_button.y)) {
            if (!c.SDL_ShowWindowSystemMenu(self.window, @intFromFloat(event_button.x), @intFromFloat(event_button.y))) return error.SDL;
            return true;
        }
        return false;
    }
    fn drawTab(self: *App, picture: *const HeaderPicture, tabs: chrome.Tabs, index: u8, rect: layout.Rect) !void {
        const colors = picture.colors;
        const target = picture.hovered;
        const base = if (index == picture.active) colors.active else colors.idle;
        const body_hovered = target == .tab and target.tab == index;
        try drawing.fillRounded(self.renderer, rect, if (body_hovered) appearance.hover(base) else base, chrome.Geometry.chip_radius);
        const close_width: f32 = if (tabs.close(index) != null) chrome.Geometry.close_width else 0;
        if (target == .tab_close and target.tab_close == index) {
            const close_rect: layout.Rect = .{ .x = rect.x + rect.width - close_width, .y = rect.y, .width = close_width, .height = rect.height };
            try drawing.fillRounded(self.renderer, chrome.closeSurface(close_rect), appearance.closeHover(base), chrome.Geometry.hover_radius);
        }
        if (index == picture.active) try fill(self.renderer, .{ .x = rect.x + chrome.Geometry.chip_radius, .y = rect.y + rect.height - chrome.Geometry.accent_bottom, .width = @max(0, rect.width - chrome.Geometry.chip_radius * 2), .height = chrome.Geometry.accent_height }, colors.accent);
        const title = chrome.titleArea(rect, close_width != 0);
        if (title.width > 0) try self.clippedTextColorAtScale(picture.labels[index].text(), title, title.x, colors.text, picture.scale);
        if (close_width != 0) try icons.draw(self.renderer, .x, .{ .x = rect.x + rect.width - close_width + 7, .y = rect.y + 7, .width = 16, .height = 16 }, colors.text);
    }
    fn drawWindowControls(self: *App, picture: *const HeaderPicture) !void {
        const colors = picture.colors;
        for ([_]chrome.Button{ .minimize, .maximize, .close }) |button| {
            const rect = chrome.control(button, picture.width);
            const target = picture.hovered;
            const hovered = target == .window and target.window == button;
            if (hovered) try drawing.fillRounded(self.renderer, rect, if (button == .close) appearance.closeHover(colors.title) else appearance.hover(colors.title), chrome.Geometry.chip_radius);
            const color = if (hovered) colors.text else colors.muted;
            const icon_rect: layout.Rect = .{ .x = rect.x + (rect.width - 20) / 2, .y = rect.y + (rect.height - 20) / 2, .width = 20, .height = 20 };
            // Retain the native maximize/restore geometry until an equivalent
            // rounded Lucide pair is present in our small icon vocabulary.
            const y = rect.y + (rect.height - 26) / 2;
            switch (button) {
                .minimize => try icons.draw(self.renderer, .minus, icon_rect, color),
                .maximize => {
                    const glyph = if (picture.maximized) chrome.restore_icon else chrome.maximize_icon;
                    for (glyph) |part| try fill(self.renderer, .{ .x = rect.x + part.x, .y = y + part.y, .width = part.width, .height = part.height }, color);
                },
                .close => try icons.draw(self.renderer, .x, icon_rect, color),
                .none => {},
            }
        }
    }
    fn headerPicture(self: *App) !HeaderPicture {
        const hit: chrome.HeaderTarget = if (self.hover_point) |point| chrome.headerAt(self.headerTabs(self.width), point.x, point.y) else .none;
        var picture: HeaderPicture = .{
            .width = self.width,
            .scale = self.scale,
            .count = self.tab_count,
            .active = self.active,
            .fitted = self.configuration.value.tab_width == .fit,
            .hovered = if (self.drag == .none) hit else .none,
            .action_hover = switch (hit) {
                .plus, .profiles, .settings => hit,
                else => .none,
            },
            .dragging_tab = self.drag == .tab,
            .drag_x = if (self.drag == .tab) self.drag.tab.x else 0,
            .maximized = c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MAXIMIZED != 0,
            .colors = try self.uiPalette(),
        };
        for (0..self.tab_count) |index| {
            const value = self.tabs[index].?;
            // A tab with a manually supplied display name need not yet
            // have an attached pane (e.g. during initial UI construction).
            const status = if (value.panes[value.tree.active]) |owned_pane| owned_pane.snapshot() else terminal.Status{};
            // Tab labels retain their original semantics; OSC 7501 and
            // OSC 9;4 now render only in the independent top-edge toast.
            picture.labels[index].set(value.title.resolve(status.title[0..status.title_len]));
        }
        return picture;
    }
    fn drawHeader(self: *App, picture: *const HeaderPicture) !void {
        const colors = picture.colors;
        const tabs = chrome.Tabs.init(picture.count, picture.width, picture.fitted);
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = picture.width, .height = chrome.height }, colors.title);
        for (0..picture.count) |number| {
            const index: u8 = @intCast(number);
            const rect = tabs.tab(index);
            if (picture.dragging_tab and index == picture.active) {
                try drawing.fillRounded(self.renderer, rect, colors.border, chrome.Geometry.chip_radius);
                try drawing.fillRounded(self.renderer, chrome.dragInterior(rect), colors.title, chrome.Geometry.hover_radius);
            } else try self.drawTab(picture, tabs, index, rect);
        }
        if (picture.dragging_tab) {
            var rect = tabs.tab(picture.active);
            rect.x = picture.drag_x;
            try drawing.fillRounded(self.renderer, rect, colors.accent, chrome.Geometry.chip_radius);
            try self.drawTab(picture, tabs, picture.active, chrome.dragInterior(rect));
        }
        for ([_]layout.Rect{ tabs.plus(), tabs.profiles(), chrome.settings(picture.width) }, [_]icons.Name{ .plus, .chevron_right, .ellipsis }, [_]chrome.HeaderTarget{ .plus, .profiles, .settings }) |rect, glyph, hit| {
            if (std.meta.eql(picture.action_hover, hit)) try drawing.fillRounded(self.renderer, rect, appearance.hover(colors.idle), chrome.Geometry.chip_radius);
            try icons.draw(self.renderer, glyph, .{ .x = rect.x + 6, .y = rect.y + 5, .width = 20, .height = 20 }, colors.text);
        }
        try self.drawWindowControls(picture);
    }
    fn drawRetainedHeader(self: *App) !void {
        if (self.headerHeight() == 0) {
            self.header_cache.deinit();
            return;
        }
        const picture = try self.headerPicture();
        const width: c_int = @intFromFloat(@ceil(picture.width * picture.scale));
        const height: c_int = @intFromFloat(@ceil(chrome.height * picture.scale));
        // A single bounded chrome surface, not one allocation per tab/icon.
        if (width <= 0 or height <= 0 or @as(u64, @intCast(width)) * @as(u64, @intCast(height)) * 4 > 2 * 1024 * 1024) {
            self.header_cache.deinit();
            return self.drawHeader(&picture);
        }
        if (self.header_cache.width != width or self.header_cache.height != height) self.header_cache.deinit();
        if (self.header_cache.texture == null) {
            const texture = c.SDL_CreateTexture(self.renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, width, height) orelse return self.drawHeader(&picture);
            if (!c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_NONE) or !c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST)) {
                c.SDL_DestroyTexture(texture);
                return self.drawHeader(&picture);
            }
            self.header_cache.texture = texture;
            self.header_cache.width = width;
            self.header_cache.height = height;
        }
        if (self.header_cache.picture == null or !self.header_cache.picture.?.eql(&picture)) {
            self.header_cache.picture = null;
            if (!c.SDL_SetRenderTarget(self.renderer, self.header_cache.texture)) return error.SDL;
            // zig-audit: acknowledge discard
            // reason: On a failed chrome paint the window target must be restored best-effort before unwinding.
            errdefer _ = c.SDL_SetRenderTarget(self.renderer, null);
            if (!c.SDL_SetRenderScale(self.renderer, picture.scale, picture.scale) or
                !c.SDL_SetRenderDrawColor(self.renderer, picture.colors.title.r, picture.colors.title.g, picture.colors.title.b, 255) or
                !c.SDL_RenderClear(self.renderer)) return error.SDL;
            try self.drawHeader(&picture);
            if (!c.SDL_SetRenderTarget(self.renderer, null) or !c.SDL_SetRenderScale(self.renderer, picture.scale, picture.scale)) return error.SDL;
            self.header_cache.picture = picture;
        }
        const destination: c.SDL_FRect = .{ .x = 0, .y = 0, .w = picture.width, .h = chrome.height };
        if (!c.SDL_RenderTexture(self.renderer, self.header_cache.texture, null, &destination)) return error.SDL;
    }
    fn drawDivider(self: *App, divider: layout.Divider, color: c.SDL_Color) !void {
        try drawing.divider(self.renderer, divider.rect, divider.axis, 2, color);
    }

    fn draw(self: *App) !void {
        try self.desktopHost();
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) return error.SDL;
        self.width = @floatFromInt(@max(1, width));
        self.height = @floatFromInt(@max(1, height));
        self.displayScale();
        self.cursor_deadline = null;
        if (self.hover_point) |point| try self.pointerHover(point.x, point.y);
        const colors = try self.uiPalette();
        if (!c.SDL_SetRenderScale(self.renderer, self.scale, self.scale) or !c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_BLEND) or
            !c.SDL_SetRenderDrawColor(self.renderer, colors.window.r, colors.window.g, colors.window.b, colors.window.a) or !c.SDL_RenderClear(self.renderer)) return error.SDL;
        try self.drawRetainedHeader();
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            const active = place.pane == self.tab().tree.active;
            try fill(self.renderer, place.rect, colors.panel);
            const status = p.snapshot();
            const outer = paneContent(place.rect);
            const rect = terminalContent(place.rect, status.closed);
            if (p.graphics_failure == null) {
                if (p.owner) |owner| p.canvas.update(self.renderer, owner) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            if (self.selecting) |dragging| if (dragging.pane == p and dragging.edge != 0)
                try self.selectPoint(p, dragging.x, dragging.y, .extend, true);
            if (p.owner) |owner| if (owner.takeInputActivity()) p.blink.reset();
            if (active and status.selection_serial == p.selection_serial and status.selection_failure != null and p.selection_failure_reported != status.selection_serial) {
                p.selection_failure_reported = status.selection_serial;
                self.report(status.selection_failure.?);
            }
            if (p.canvas.frame()) |frame| {
                // A completed font transaction supplies the new lattice before its frame arrives.
                // An older accepted lease must not resize canonical geometry back to its old font.
                const cell = p.cell_size orelse frame.cell_size;
                const rows: u16 = @intFromFloat(std.math.clamp(@floor(rect.h * self.scale / @as(f32, @floatFromInt(cell.height))), 1, @as(f32, @floatFromInt(limits.maximum_rows))));
                const columns: u16 = @intFromFloat(std.math.clamp(@floor(rect.w * self.scale / @as(f32, @floatFromInt(cell.width))), 1, @as(f32, @floatFromInt(limits.maximum_columns))));
                if (p.size_control and status.failure == null and !status.closed and (rows != p.rows or columns != p.columns)) {
                    try p.submit(.{ .resize = .{ .rows = rows, .columns = columns } });
                    p.rows = rows;
                    p.columns = columns;
                }
                const placed = terminalPlacement(rect, frame.surface, self.scale);
                const cursor_focused = self.focused and active and !status.closed and p.graphics_failure == null and
                    self.rename_editor == null and self.palette == null and self.settings_editor == null and self.chooser == null and p.finder == null and
                    c.SDL_GetWindowFlags(self.window) & (c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_MINIMIZED) == 0;
                const cursor_now = c.SDL_GetTicks();
                const cursor_view = frame;
                const show_cursor = p.blink.update(cursor_now, cursor_view, cursor_focused, .{ .policy = self.configuration.value.cursor_blink, .interval_ms = self.configuration.value.cursor_blink_interval_ms, .idle_ms = self.configuration.value.cursor_blink_idle_ms });
                const cursor_display: canvas.CursorDisplay = if (!cursor_focused) .outline else if (show_cursor) .shown else .hidden;
                const cursor_visual = p.motion.update(cursor_now, cursor_view, cursor_focused and show_cursor, .{ .enabled = self.configuration.value.cursor_motion, .duration_ms = self.configuration.value.cursor_motion_ms, .easing = self.configuration.value.cursor_easing, .effect = self.configuration.value.cursor_effect }, .{ placed.x, placed.y, placed.w, placed.h });
                if (p.blink.deadline) |deadline| self.cursor_deadline = @min(self.cursor_deadline orelse deadline, deadline);
                if (p.motion.deadline) |deadline| self.cursor_deadline = @min(self.cursor_deadline orelse deadline, deadline);
                if (p.graphics_failure == null) p.canvas.draw(self.renderer, self.geometry, placed, self.scale, cursor_display, drawing.cursorStroke(@intFromFloat(@round(@as(f32, @floatFromInt(p.font_size)) * self.scale)), self.configuration.value.cursor_outline_pixels), cursor_visual) catch |failure| {
                    p.graphics_failure = failure;
                };
                if (p.graphics_failure == null) {
                    clearClip(self.renderer);
                    try self.drawScrollbar(p, placed, frame);
                }
            }
            clearClip(self.renderer);
            try self.drawFind(p, rect, status);
            const failure: ?(CreationError || GraphicsFailure || terminal.Failure || terminal.PresentationFailure || terminal.ConfigureError) = if (p.creation_failure) |value| value else if (p.graphics_failure) |value| value else if (status.failure) |value| value else if (status.presentation_failure) |value| value else if (p.font_failure) |value| value else null;
            if (failure != null or status.closed) {
                const clip = drawing.clipBounds(outer);
                if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
                defer clearClip(self.renderer);
                if (failure) |value| {
                    try fill(self.renderer, .{ .x = outer.x, .y = outer.y, .width = outer.w, .height = @min(28, outer.h) }, .{ .r = 96, .g = 35, .b = 43, .a = 255 });
                    try self.drawText(@errorName(value), outer.x + 8, outer.y + 6);
                } else {
                    try self.drawText("Exited — Ctrl+Shift+R to restart", outer.x + 8, outer.y + 6);
                }
            }
        }
        if (result.panes > 1) for (places[0..result.panes]) |place| {
            if (place.pane == self.tab().tree.active) try outline(self.renderer, place.rect, colors.border);
        };
        for (dividers[0..result.dividers]) |divider| try drawing.divider(self.renderer, divider.rect, divider.axis, 1, colors.border);
        if (self.drag == .divider) {
            for (dividers[0..result.dividers]) |divider|
                if (self.drag.divider.contains(divider.node)) try self.drawDivider(divider, colors.accent);
        } else if (self.hover_divider) |held| {
            for (held.dividers[0..held.count]) |divider| try self.drawDivider(divider, colors.accent);
        }
        try self.drawToast(c.SDL_GetTicks());
        if (self.palette != null) try self.drawPalette();
        if (self.settings_editor != null) try PaintUI.drawSettings(self);
        if (self.chooser != null) try self.drawChooser();
        if (self.rename_editor) |*editor| try self.drawField(try self.renameField(), &editor.edit, editor.bytes[0..editor.len], "Automatic title", true);
        try self.drawComposition();
        if (!c.SDL_RenderPresent(self.renderer)) return error.SDL;
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            if (p.graphics_failure == null) if (p.owner) |owner| owner.requestFrame();
        }
    }
};

/// Owns SDL/application lifetime and graphical leases; terminal workers retain canonical authority.
pub fn main(initial: std.process.Init) !void {
    var init = initial;
    const args = init.minimal.args.vector;
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--version")) {
        std.debug.print("Howl {s} (Zig SDL app)\n", .{version});
        return;
    }
    if (args.len != 1) return error.InvalidArguments;
    // Zig 0.17.0-dev.1980+e78ea8f2c retains the original POSIX environment length.
    // SDL consumes Wayland activation tokens with unsetenv, invalidating that view.
    // Own both child inheritance and I/O's environment before entering SDL.
    const inherited = try profileEnvironment(allocator, init.environ_map, &.{});
    defer inherited.block.deinit(allocator);
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = inherited });
    defer threaded.deinit();
    init.minimal.environ = inherited;
    init.io = threaded.io();
    if (!c.SDL_SetAppMetadata("Howl", version, "io.github.laurenceguws.howl") or !c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    var configuration = try config.Config.load(allocator, init.io, init.environ_map);
    defer configuration.deinit();
    var fonts = try font_owner.Fonts.discover(allocator, init.environ_map, configuration.value.font.paths());
    defer fonts.deinit();
    const window = c.SDL_CreateWindow("Howl", 1000, 650, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const scale = c.SDL_GetWindowDisplayScale(window);
    if (!std.math.isFinite(scale) or scale <= 0 or scale > 8) return error.DisplayScale;
    var ui_fonts = try font_owner.TextFonts.open(allocator, &fonts, 15 * scale);
    defer ui_fonts.deinit();
    const renderer = c.SDL_CreateRenderer(window, null) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try fonts.configureTextureLimit(c.SDL_GetNumberProperty(c.SDL_GetRendererProperties(renderer), c.SDL_PROP_RENDERER_MAX_TEXTURE_SIZE_NUMBER, 0));
    if (!c.SDL_SetRenderVSync(renderer, 1) or !c.SDL_StartTextInput(window)) return error.SDL;
    const wake_event = c.SDL_RegisterEvents(1);
    if (wake_event == std.math.maxInt(u32)) return error.SDL;
    const geometry = try allocator.create(canvas.Geometry);
    defer allocator.destroy(geometry);
    geometry.* = .{};
    var app: App = .{
        .init = init,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = geometry,
        .wake_event = wake_event,
        .window_visibility = c.SDL_GetWindowFlags(window) & (c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_MINIMIZED),
        .scale = scale,
        .bindings = try keybindings.Bindings.fromOverrides(configuration.value.keybindings),
        .focused = c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_INPUT_FOCUS != 0,
    };
    defer app.deinit();
    if (!c.SDL_SetWindowHitTest(window, windowHitTest, &app) or !c.SDL_SetWindowBordered(window, false)) return error.SDL;
    // zig-audit: acknowledge discard
    // reason: Callback retirement is best-effort immediately before SDL destroys this owned window.
    defer _ = c.SDL_SetWindowHitTest(window, null, null);
    try app.createTab(try app.startup(), null);
    var redraw = true;
    while (app.running) {
        if (redraw) try app.draw();
        redraw = false;
        app.selectionTick() catch |failure| app.report(failure);
        var event: c.SDL_Event = undefined;
        if (app.waitTimeout(c.SDL_GetTicks())) |timeout| {
            if (!c.SDL_WaitEventTimeout(&event, timeout)) {
                redraw = true;
                continue;
            }
        } else if (!c.SDL_WaitEvent(&event)) return error.SDL;
        while (true) {
            if (app.processEvent(event)) redraw = true;
            if (!app.running or !c.SDL_PollEvent(&event)) break;
        }
        if (app.running) app.keyboard.flushPending() catch |failure| {
            app.report(failure);
            redraw = true;
        };
    }
}
fn setClipboard(bytes: []const u8) !void {
    const text = try allocator.dupeSentinel(u8, bytes, 0);
    defer allocator.free(text);
    if (!c.SDL_SetClipboardText(text)) return error.SDLClipboard;
}

const FontChange = struct {
    pane: *Pane,
    size: u16,
    overridden: bool,
    geometry: ?app_presentation.Geometry = null,
};

fn preserveStagedFont(change: FontChange, failure: terminal.ConfigureError) void {
    const geometry = change.geometry.?;
    const pane = change.pane;
    // A failed rollback does not undo the worker's successful staged commit.
    // Keep the observed lattice authoritative for drawing and future resizing;
    // the next settings transaction retries the saved recipe explicitly.
    pane.cell_size = geometry.cell_size;
    pane.rows = geometry.rows;
    pane.columns = geometry.columns;
    pane.font_failure = failure;
    pane.font_repair_pending = true;
}
fn profileEnvironment(gpa: std.mem.Allocator, parent: *const std.process.Environ.Map, entries: []const config.Environment) std.mem.Allocator.Error!std.process.Environ {
    var child = try parent.clone(gpa);
    defer child.deinit();
    for (entries) |entry| try child.put(entry.name, entry.value);
    const block = try gpa.allocSentinel(?[*:0]const u8, child.count(), null);
    var initialized: usize = 0;
    errdefer {
        for (block[0..initialized]) |entry| gpa.free(std.mem.span(entry.?));
        gpa.free(block);
    }
    var entries_iter = child.iterator();
    while (entries_iter.next()) |entry| {
        const bytes = try std.fmt.allocPrintSentinel(gpa, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }, 0);
        block[initialized] = bytes.ptr;
        initialized += 1;
    }
    return .{ .block = .{ .slice = block } };
}

fn savedRecipe(current: *const config.Config, owned: config.Profile) !config.Profile {
    for (0..current.profileCount()) |index| {
        const value = try current.profile(@intCast(index));
        if (std.mem.eql(u8, value.id, owned.id)) return value;
    }
    return owned;
}
// zig-audit: acknowledge anyopaque
// reason: SDL callback userdata is the stable application owner; never retained by a terminal worker.
fn windowHitTest(window: ?*c.SDL_Window, point: [*c]const c.SDL_Point, data: ?*anyopaque) callconv(.c) c.SDL_HitTestResult {
    // zig-audit: acknowledge ptr_cast
    // reason: SDL returns the stable App address installed for this owned window.
    // zig-audit: acknowledge align_cast
    // reason: SDL returns the stable App address installed for this window; callback ends before App retirement.
    const app: *App = @ptrCast(@alignCast(data.?));
    if (app.drag != .none or app.chrome_pressed != .none or app.pointer_buttons != 0) return c.SDL_HITTEST_NORMAL;
    var width: c_int = 0;
    var height: c_int = 0;
    if (!c.SDL_GetWindowSize(window, &width, &height)) return c.SDL_HITTEST_NORMAL;
    return chrome.hit(@floatFromInt(point.*.x), @floatFromInt(point.*.y), @floatFromInt(width), @floatFromInt(height), app.headerTabs(@floatFromInt(width)), c.SDL_GetWindowFlags(window), app.headerHeight() != 0);
}
const outline = drawing.outline;
const fill = drawing.fill;
const setClip = drawing.setClip;
const clearClip = drawing.clearClip;
fn mouseButton(button: u8) ?vt.Terminal.MouseButton {
    return switch (button) {
        c.SDL_BUTTON_LEFT => .left,
        c.SDL_BUTTON_MIDDLE => .middle,
        c.SDL_BUTTON_RIGHT => .right,
        else => null,
    };
}
fn paneContent(rect: layout.Rect) c.SDL_FRect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
}
fn terminalContent(rect: layout.Rect, closed: bool) c.SDL_FRect {
    var content = paneContent(rect);
    if (closed) {
        // A dead PTY keeps its final frame, with a separate restart banner above it.
        const banner = @min(28, @max(0, content.h - 1));
        content.y += banner;
        content.h -= banner;
    }
    return content;
}
// Split sub-cell slack evenly around the accepted frame; the pane remains resize authority.
// Align absolute origins to physical pixels.
fn terminalPlacement(available: c.SDL_FRect, surface: commands.Size, scale: f32) c.SDL_FRect {
    const width = @min(available.w, @as(f32, @floatFromInt(surface.width)) / scale);
    const height = @min(available.h, @as(f32, @floatFromInt(surface.height)) / scale);
    // Subtract extents before adding the origin. An oversized stale frame
    // has zero slack; (origin + extent) - extent can round below origin.
    const slack_x = available.w - width;
    const slack_y = available.h - height;
    return .{
        .x = std.math.clamp(@round((available.x + slack_x / 2) * scale) / scale, available.x, available.x + slack_x),
        .y = std.math.clamp(@round((available.y + slack_y / 2) * scale) / scale, available.y, available.y + slack_y),
        .w = width,
        .h = height,
    };
}
fn physicalSurface(rect: layout.Rect, scale: f32) commands.Size {
    const content = paneContent(rect);
    return .{
        .width = @intFromFloat(std.math.clamp(@round(@as(f64, content.w) * scale), 1, @as(f64, @floatFromInt(std.math.maxInt(u32))))),
        .height = @intFromFloat(std.math.clamp(@round(@as(f64, content.h) * scale), 1, @as(f64, @floatFromInt(std.math.maxInt(u32))))),
    };
}
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |i| if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return true;
    return false;
}
fn reapWindow(pid: std.posix.pid_t) void {
    var status: c_int = 0;
    while (true) {
        const result = std.posix.system.waitpid(pid, &status, 0);
        switch (std.posix.errno(result)) {
            .INTR => continue,
            .SUCCESS, .CHILD => return,
            else => return,
        }
    }
}

test {
    std.testing.refAllDecls(canvas);
    std.testing.refAllDecls(terminal);
    std.testing.refAllDecls(font_owner);
    std.testing.refAllDecls(layout);
    std.testing.refAllDecls(keybindings);
    std.testing.refAllDecls(input);
    std.testing.refAllDecls(pointer);
    std.testing.refAllDecls(composition);
    std.testing.refAllDecls(@import("config.zig"));
    std.testing.refAllDecls(settings);
    std.testing.refAllDecls(discovery);
    std.testing.refAllDecls(picker);
    std.testing.refAllDecls(appearance);
    std.testing.refAllDecls(drawing);
    std.testing.refAllDecls(color_config);
    std.testing.refAllDecls(@import("settings_ui_test.zig"));
}

test "retained chrome identity ignores terminal work and detects every painted header input" {
    var initial: HeaderPicture = .{
        .width = 900,
        .scale = 1,
        .count = 2,
        .active = 0,
        .fitted = false,
        .hovered = .none,
        .dragging_tab = false,
        .drag_x = 0,
        .maximized = false,
        .colors = try appearance.palette("howl_dark"),
    };
    initial.labels[0].set("shell");
    initial.labels[1].set("editor");
    var changed = initial;
    try std.testing.expect(initial.eql(&changed));
    changed.labels[1].set("build");
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.hovered = .{ .tab_close = 1 };
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.action_hover = .plus;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.dragging_tab = true;
    changed.drag_x = 70;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.width = 901;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.scale = 1.25;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.colors.accent.r +%= 1;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.maximized = true;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.fitted = true;
    try std.testing.expect(!initial.eql(&changed));
    changed = initial;
    changed.active = 1;
    try std.testing.expect(!initial.eql(&changed));
}

test "retained and direct header pixels agree across hover, drag, fitted widths and scale" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("header retention", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(1050, 72, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    var first: Tab = .{ .recipe = undefined };
    var second: Tab = .{ .recipe = undefined };
    try first.title.set("Shell");
    try second.title.set("Editor 界");
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 1000,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .tab_count = 2,
    };
    app.tabs[0] = &first;
    app.tabs[1] = &second;
    defer app.header_cache.deinit();
    const expected = try a.alloc(c.SDL_Color, 1050 * 72);
    defer a.free(expected);

    for (0..13) |step| {
        app.hover_point = null;
        app.drag = .none;
        app.active = if (step >= 8) 1 else 0;
        configuration.value.tab_width = if (step >= 9) .fit else .fixed;
        configuration.value.app_theme = if (step >= 10) "slate" else "howl_dark";
        app.width = if (step >= 11) 760 else 1000;
        app.scale = if (step >= 11) 1.25 else 1;
        const tabs = app.headerTabs(app.width);
        const hovered: ?layout.Rect = switch (step) {
            1 => tabs.body(0),
            2 => tabs.close(1).?,
            3, 7 => tabs.plus(),
            4 => tabs.profiles(),
            5 => chrome.settings(app.width),
            6 => chrome.control(.close, app.width),
            else => null,
        };
        if (hovered) |rect| app.hover_point = .{ .x = rect.x + rect.width / 2, .y = rect.y + rect.height / 2 };
        if (step == 7) {
            app.drag = .{ .tab = chrome.Drag.begin(tabs.tab(0), tabs.tab(0).x + 15) };
            app.drag.tab.x += 70;
        }
        if (step == 12) try second.title.set("Renamed tab");
        const picture = try app.headerPicture();
        if (step == 7) {
            try std.testing.expect(picture.hovered == .none);
            try std.testing.expect(picture.action_hover == .plus);
        }
        const width: usize = @intFromFloat(@ceil(app.width * app.scale));
        const height: usize = @intFromFloat(@ceil(chrome.height * app.scale));
        try std.testing.expect(width <= 1050 and height <= 72);
        if (!c.SDL_SetRenderTarget(renderer, null) or !c.SDL_SetRenderClipRect(renderer, null) or
            !c.SDL_SetRenderScale(renderer, app.scale, app.scale) or
            !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
        try app.drawHeader(&picture);
        if (!c.SDL_RenderPresent(renderer)) return error.SDL;
        for (0..height) |y| {
            for (0..width) |x| expected[y * width + x] = try testPixel(surface, @intCast(x), @intCast(y));
        }

        if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
        try app.drawRetainedHeader();
        if (!c.SDL_RenderPresent(renderer)) return error.SDL;
        try std.testing.expect(app.header_cache.picture.?.eql(&picture));
        if (app.scale != 1) {
            // SDL target-texture resampling differs from direct primitive
            // rasterization at fractional scale. Compare the actual retained
            // path against a fresh rebuild instead of accepting a wide pixel
            // tolerance against a different rendering path.
            for (0..height) |y| {
                for (0..width) |x| expected[y * width + x] = try testPixel(surface, @intCast(x), @intCast(y));
            }
            app.header_cache.deinit();
        }
        for (0..2) |pass| {
            if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
            try app.drawRetainedHeader();
            if (!c.SDL_RenderPresent(renderer)) return error.SDL;
            for (0..height) |y| for (0..width) |x| {
                const actual = try testPixel(surface, @intCast(x), @intCast(y));
                if (!std.meta.eql(expected[y * width + x], actual)) {
                    std.debug.print("header mismatch step={d} pass={d} xy={d},{d} expected={any} actual={any}\n", .{ step, pass, x, y, expected[y * width + x], actual });
                    return error.HeaderPixelMismatch;
                }
            };
        }
        const retained = app.header_cache.texture.?;
        try app.drawRetainedHeader();
        try std.testing.expectEqual(retained, app.header_cache.texture.?);
    }

    // A captured picture, including glyph colour and maximize shape, must not
    // consult the current app state when it paints a previously accepted cut.
    const frozen = try app.headerPicture();
    const width: usize = @intFromFloat(@ceil(frozen.width * frozen.scale));
    const height: usize = @intFromFloat(@ceil(chrome.height * frozen.scale));
    if (!c.SDL_SetRenderTarget(renderer, null) or !c.SDL_SetRenderClipRect(renderer, null) or
        !c.SDL_SetRenderScale(renderer, frozen.scale, frozen.scale) or
        !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
    try app.drawHeader(&frozen);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    for (0..height) |y| {
        for (0..width) |x| expected[y * width + x] = try testPixel(surface, @intCast(x), @intCast(y));
    }
    app.hover_point = .{ .x = 15, .y = 15 };
    app.active = 0;
    app.width = 1000;
    app.scale = 1;
    configuration.value.tab_width = .fixed;
    configuration.value.app_theme = "howl_dark";
    if (!c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
    try app.drawHeader(&frozen);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    for (0..height) |y| for (0..width) |x| {
        try std.testing.expectEqual(expected[y * width + x], try testPixel(surface, @intCast(x), @intCast(y)));
    };

    var maximized = frozen;
    maximized.maximized = !frozen.maximized;
    if (!c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
    try app.drawHeader(&maximized);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    const control = chrome.control(.maximize, frozen.width);
    var changed: usize = 0;
    const left: usize = @intFromFloat(@floor(control.x * frozen.scale));
    const right: usize = @intFromFloat(@ceil((control.x + control.width) * frozen.scale));
    const top: usize = @intFromFloat(@floor(control.y * frozen.scale));
    const bottom: usize = @intFromFloat(@ceil((control.y + control.height) * frozen.scale));
    for (top..bottom) |y| for (left..right) |x| {
        if (!std.meta.eql(expected[y * width + x], try testPixel(surface, @intCast(x), @intCast(y)))) changed += 1;
    };
    try std.testing.expect(changed > 0);
}

test "header pointer dispatch matches chrome targets and preserves close, drag and overlays" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("header click routing", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    // An empty font catalogue makes tab creation exercise the host's
    // unavailable-pane path without launching a process or opening a font.
    var fonts: font_owner.Fonts = .{ .allocator = allocator };
    defer fonts.deinit();
    for ([_]f32{ 600, 600, 1000, 1000 }, [_]bool{ false, true, false, true }) |width, fit| {
        configuration.value.tab_width = if (fit) .fit else .fixed;
        var app: App = .{
            .init = .{
                .minimal = .{ .environ = .empty, .args = undefined },
                .arena = undefined,
                .gpa = allocator,
                .io = threaded.io(),
                .environ_map = &environment,
                .preopens = undefined,
            },
            .configuration = &configuration,
            .fonts = &fonts,
            .window = window,
            .renderer = undefined,
            .ui_fonts = undefined,
            .geometry = undefined,
            .wake_event = 0,
            .scale = 1,
            .width = width,
            .height = 650,
            .bindings = try keybindings.Bindings.init(),
        };
        defer app.deinit();
        try app.createTab(try configuration.profile(0), null);
        try app.createTab(try configuration.profile(0), null);
        try std.testing.expect(app.tabs[0].?.panes[0].?.owner == null);
        try std.testing.expect(app.tabs[1].?.panes[0].?.owner == null);
        const survivor = app.tabs[1].?;
        const tabs = app.headerTabs(app.width);
        const close = tabs.close(0).?;
        const close_x = close.x + close.width / 2;
        const y = close.y + close.height / 2;
        try std.testing.expectEqualDeep(chrome.HeaderTarget{ .tab_close = 0 }, chrome.headerAt(tabs, close_x, y));
        try app.pointerDown(close_x, y, .left, .{}, 1);
        try std.testing.expectEqual(@as(u8, 1), app.tab_count);
        try std.testing.expectEqual(@as(u8, 0), app.active);
        try std.testing.expectEqual(survivor, app.tabs[0].?);
        try std.testing.expect(app.consume_left_release and app.running);
        app.consume_left_release = false;

        const plus = app.headerTabs(app.width).plus();
        try app.pointerDown(plus.x + 10, plus.y + 15, .left, .{}, 1);
        try std.testing.expectEqual(@as(u8, 2), app.tab_count);
        try std.testing.expectEqual(@as(u8, 1), app.active);
        try std.testing.expect(app.consume_left_release);
        app.consume_left_release = false;

        const body = app.headerTabs(app.width).body(0);
        try app.pointerDown(body.x + 12, body.y + 12, .left, .{}, 1);
        try std.testing.expectEqual(@as(u8, 0), app.active);
        try std.testing.expect(app.drag == .tab);
        try std.testing.expectEqual(app.headerTabs(app.width).tab(0).x, app.drag.tab.x);
        app.cancelDrag();
        app.consume_left_release = false;
        try app.pointerDown(body.x + 12, body.y + 12, .left, .{}, 2);
        try std.testing.expect(app.rename_editor != null and app.drag == .none);
        try app.finishRename(false);

        const menu = app.headerTabs(app.width).profiles();
        try app.pointerDown(menu.x + 10, menu.y + 15, .left, .{}, 1);
        try std.testing.expect(app.palette != null and app.palette.?.profile);
        app.palette = null;
        const settings_rect = chrome.settings(app.width);
        try app.pointerDown(settings_rect.x + 10, settings_rect.y + 15, .left, .{}, 1);
        try std.testing.expect(app.settings_editor != null);
        try app.toggleSettings();
        try std.testing.expect(app.settings_editor == null);

        // Native caption actions intercept before tab dispatch, and a release
        // outside the pressed control must never close the window.
        const native = chrome.control(.close, app.width);
        var event_value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        event_value.button = .{ .type = c.SDL_EVENT_MOUSE_BUTTON_DOWN, .button = c.SDL_BUTTON_LEFT, .x = native.x + 8, .y = native.y + 8 };
        try app.event(event_value);
        try std.testing.expectEqual(chrome.Button.close, app.chrome_pressed);
        event_value.button.type = c.SDL_EVENT_MOUSE_BUTTON_UP;
        event_value.button.x = app.headerTabs(app.width).caption().x;
        try app.event(event_value);
        try std.testing.expectEqual(chrome.Button.none, app.chrome_pressed);
        try std.testing.expect(app.running);
        const caption = app.headerTabs(app.width).caption();
        if (caption.width > 0) {
            try std.testing.expectEqualDeep(chrome.HeaderTarget.caption, chrome.headerAt(app.headerTabs(app.width), caption.x + caption.width / 2, caption.y + 15));
        }
    }
}

test "command palette exposes every mapping including directional multiplexing commands" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var p: Palette = .{};
    var indices: [palette_limit]usize = undefined;
    const count = try p.indices(&configuration, &indices);
    try std.testing.expectEqual(keybindings.definitions.len, count);
    const query = "FOCUS PANE";
    @memcpy(p.query[0..query.len], query);
    p.len = query.len;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, &indices));
    for (indices[0..4]) |index| try std.testing.expect(keybindings.definitions[index].target == .pane_focus);
    p = .{ .profile = true };
    try std.testing.expectEqual(@as(usize, 3), try p.indices(&configuration, &indices));
}

test "profile palette uses saved recipes and resolves its configured default" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"app_theme":"howl_dark","default_profile":"build","profiles":[{"id":"build","name":"Build shell","shell":"/bin/sh","command":"exec sh","font_pixels":19}]}
    );
    defer configuration.deinit();
    var p: Palette = .{ .profile = true };
    var indices: [palette_limit]usize = undefined;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, &indices));
    @memcpy(p.query[0..5], "BUILD");
    p.len = 5;
    try std.testing.expectEqual(@as(usize, 1), try p.indices(&configuration, &indices));
    try std.testing.expectEqualStrings((try configuration.defaultProfile()).id, (try configuration.profile(@intCast(indices[0]))).id);
    const recipe = try configuration.profile(@intCast(indices[0]));
    try std.testing.expectEqualStrings("exec sh", recipe.command);
    try std.testing.expectEqual(@as(i32, 19), recipe.font_pixels);
}

test "pane content uses its whole layout owner and has a bounded positive configuration surface" {
    for ([_]f32{ 0.125, 1, 4, 6, 40 }) |width| {
        const outer: layout.Rect = .{ .x = 10, .y = 20, .width = width, .height = 0.25 };
        const content = paneContent(outer);
        try std.testing.expectEqual(outer.x, content.x);
        try std.testing.expectEqual(outer.y, content.y);
        try std.testing.expectEqual(outer.width, content.w);
        try std.testing.expectEqual(outer.height, content.h);
        const surface = physicalSurface(outer, 1.7);
        try std.testing.expect(surface.width >= 1 and surface.height >= 1);
    }
}

test "exited pane reserves a restart band without shifting live terminal geometry" {
    for ([_]f32{ 0.125, 1, 4, 40, 650 }) |height| {
        const outer: layout.Rect = .{ .x = 10, .y = 42, .width = 1000, .height = height };
        const live = terminalContent(outer, false);
        const dead = terminalContent(outer, true);
        try std.testing.expectEqualDeep(paneContent(outer), live);
        try std.testing.expectEqual(outer.x, dead.x);
        try std.testing.expectEqual(outer.width, dead.w);
        try std.testing.expect(dead.y >= live.y and dead.y <= live.y + 28);
        try std.testing.expect(dead.h > 0);
        try std.testing.expectApproxEqAbs(live.y + live.h, dead.y + dead.h, 0.001);
        if (height >= 29) try std.testing.expectEqual(@as(f32, 28), dead.y - live.y);
    }
}

/// Construct disposable fonts for SDL host rendering tests.
pub fn testFonts(a: std.mem.Allocator) !font_owner.Fonts {
    var fonts: font_owner.Fonts = .{ .allocator = a };
    errdefer fonts.deinit();
    for (&fonts.paths) |*path| path.* = try a.dupe(u8, @import("test_fonts").primary_font);
    return fonts;
}

test "SDL composition stays local, uses its caret area and clears before pane input ownership changes" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const test_allocator = std.testing.allocator;
    const window = c.SDL_CreateWindow("composition proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    try std.testing.expect(c.SDL_StartTextInput(window));
    const surface = c.SDL_CreateSurface(1000, 650, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const geometry = try test_allocator.create(canvas.Geometry);
    defer test_allocator.destroy(geometry);
    geometry.* = .{};
    var fonts = try testFonts(test_allocator);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(test_allocator, &fonts, 15);
    defer ui_fonts.deinit();
    var threaded = std.Io.Threaded.init(test_allocator, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(test_allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033[2;5H\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; read step; stty raw -echo; printf '\\033[=31u\\033]0;IME-READY\\007'; value=$(dd bs=1 count=15 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf '\\033]0;%s\\007' \"$value\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, try fonts.config(threaded.io(), 15), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var configuration = config.Config.defaults(test_allocator);
    defer configuration.deinit();
    var p: Pane = .{ .owner = owner, .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(0)), .canvas = canvas.Canvas.init(test_allocator) };
    defer p.recipe.deinit();
    defer p.canvas.deinit();
    var t: Tab = .{ .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(0)) };
    defer t.recipe.deinit();
    t.panes[0] = &p;
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = geometry,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .focused = true,
        .tab_count = 1,
    };
    app.tabs[0] = &t;
    var attempts: u16 = 0;
    while (p.canvas.frame() == null and attempts < 5000) : (attempts += 1) {
        try p.canvas.update(renderer, owner);
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(p.canvas.frame() != null);
    var event_value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    event_value.edit = .{ .type = c.SDL_EVENT_TEXT_EDITING, .reserved = 0, .timestamp = 100, .windowID = c.SDL_GetWindowID(window), .text = "aéz", .start = 2, .length = 1 };
    const before = owner.snapshot().revision;
    try std.testing.expect(app.processEvent(event_value));
    try std.testing.expectEqualStrings("aéz", app.preedit.text());
    try std.testing.expectEqual(before, owner.snapshot().revision);
    try app.drawComposition();
    var area: c.SDL_Rect = undefined;
    var caret: c_int = 0;
    try std.testing.expect(c.SDL_GetTextInputArea(window, &area, &caret));
    try std.testing.expect(area.x > 9 and area.y > 43 and area.w > 0 and area.h > 0);
    try std.testing.expect(caret > 0 and caret < area.w);
    event_value.edit.text = "";
    event_value.edit.timestamp = 101;
    try std.testing.expect(app.processEvent(event_value));
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    try std.testing.expect(!app.processEvent(event_value));
    try std.testing.expectEqual(before, owner.snapshot().revision);
    const oversized: [1025:0]u8 = @splat('x');
    event_value.edit.text = &oversized;
    try std.testing.expect(app.processEvent(event_value));
    try std.testing.expect(app.notice_len != 0);
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    event_value.edit.text = "";
    try std.testing.expect(!app.processEvent(event_value));
    event_value.common.timestamp = 200;
    app.input_timestamp = 200;
    try app.openPalette(false);
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 150, .windowID = c.SDL_GetWindowID(window), .text = "OLD-OWNER\n" };
    try app.event(event_value);
    try std.testing.expectEqual(@as(usize, 0), app.palette.?.len);
    event_value.text.timestamp = 201;
    event_value.text.text = "filter";
    try app.event(event_value);
    try std.testing.expectEqualStrings("filter", app.palette.?.query[0..app.palette.?.len]);
    try app.drawComposition();
    try app.openPalette(true);
    try std.testing.expect(app.palette.?.profile);
    try std.testing.expectEqual(@as(usize, 0), app.palette.?.len);
    try app.openPalette(false);
    try std.testing.expect(!app.palette.?.profile);
    try app.palette.?.append("profile menu");
    try app.paletteKey(c.SDLK_RETURN, 0);
    try std.testing.expect(app.palette.?.profile);
    try app.openPalette(true);
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    const profile_button = chrome.profiles(app.tab_count, app.width);
    try app.pointerDown(profile_button.x + 16, profile_button.y + 15, .left, .{}, 1);
    try std.testing.expect(app.palette.?.profile);
    try app.openPalette(true);
    try std.testing.expect(app.palette == null);
    event_value.text.timestamp = 202;
    event_value.text.text = "COMMITTED";
    try app.event(event_value);
    // The newline is an explicit key, not an IME text scalar.
    try owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter } } } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "COMMITTED")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    try app.toggleSettings();
    app.settings_editor.?.search = true;
    event_value.text.timestamp = 203;
    event_value.text.text = "regular";
    try app.event(event_value);
    try std.testing.expectEqualStrings("regular", app.settings_editor.?.query[0..app.settings_editor.?.query_len]);
    const field: settings.Row = .{ .page = .appearance, .label = "Regular font", .target = .{ .font = 0 } };
    try app.settings_editor.?.begin(field, &configuration);
    app.input_timestamp = 205;
    app.cancelComposition();
    event_value.text.timestamp = 204;
    event_value.text.text = "/old-field";
    try app.event(event_value);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.len);
    const canonical_before_edit = owner.snapshot().revision;
    event_value.edit = .{ .type = c.SDL_EVENT_TEXT_EDITING, .reserved = 0, .timestamp = 206, .windowID = c.SDL_GetWindowID(window), .text = "é", .start = 1, .length = 0 };
    try app.event(event_value);
    try app.drawComposition();
    try std.testing.expect(c.SDL_GetTextInputArea(window, &area, &caret));
    try std.testing.expect(@as(f32, @floatFromInt(area.x)) >= App.InputUI.settingsField(&app).x);
    try std.testing.expectEqual(canonical_before_edit, owner.snapshot().revision);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 207, .windowID = c.SDL_GetWindowID(window), .text = "/owned-field" };
    try app.event(event_value);
    try std.testing.expectEqualStrings("/owned-field", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    try std.testing.expectEqual(canonical_before_edit, owner.snapshot().revision);
    app.settings_editor.?.cancel();
    app.chooser = try allocator.create(font_chooser.Chooser);
    app.chooser.?.* = .{ .original = config.Config.defaults(allocator) };
    defer if (app.chooser) |chooser| chooser.destroy(allocator);
    app.input_timestamp = 209;
    app.cancelComposition();
    event_value.text.timestamp = 208;
    event_value.text.text = "OLD-FIELD";
    try app.event(event_value);
    try std.testing.expectEqual(@as(usize, 0), app.chooser.?.query_len);
    event_value.edit = .{ .type = c.SDL_EVENT_TEXT_EDITING, .reserved = 0, .timestamp = 210, .windowID = c.SDL_GetWindowID(window), .text = "é", .start = 1, .length = 0 };
    try app.event(event_value);
    try app.drawComposition();
    try std.testing.expect(c.SDL_GetTextInputArea(window, &area, &caret));
    try std.testing.expect(@as(f32, @floatFromInt(area.x)) >= app.chooserField().x);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 211, .windowID = c.SDL_GetWindowID(window), .text = "jbmono" };
    try app.event(event_value);
    try std.testing.expectEqualStrings("jbmono", app.chooser.?.query[0..app.chooser.?.query_len]);
    try std.testing.expectEqual(canonical_before_edit, owner.snapshot().revision);
    try app.chooserCancel();
    try std.testing.expect(app.chooser == null);
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    try app.toggleSettings();
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
    const point: pointer.Location = .{ .row = 1, .col = 2, .pixel_x = 20, .pixel_y = 20 };
    try app.pointerPress(&p, point, .left, .{});
    try std.testing.expect(app.capture.?.pane == &p);
    try app.pointerRelease(.right, 0, 0, .{});
    try std.testing.expectEqual(@as(u8, 1), app.capture.?.buttons);
    event_value.common = .{ .type = c.SDL_EVENT_WINDOW_FOCUS_LOST, .reserved = 0, .timestamp = 300 };
    try app.event(event_value);
    try std.testing.expect(app.capture == null);
    event_value.button = .{ .type = c.SDL_EVENT_MOUSE_BUTTON_UP, .reserved = 0, .timestamp = 301, .windowID = c.SDL_GetWindowID(window), .which = 0, .button = c.SDL_BUTTON_LEFT, .down = false, .clicks = 1, .padding = 0, .x = 0, .y = 0 };
    try app.event(event_value);
    try std.testing.expect(app.capture == null);

    // A text commit with no physical key must follow negotiated report-all,
    // even when the worker receives it after a mode transition.
    try owner.submit(.{ .input = .{ .bytes = "next\n" } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "IME-READY")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    app.focused = true;
    var key_event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    key_event.key = c.SDLK_A;
    key_event.scancode = c.SDL_SCANCODE_A;
    try std.testing.expect((try app.keyboard.route(key_event, true, owner, null, false)) == .handled);
    try std.testing.expect(app.keyboard.pending_text != null);
    event_value.edit = .{ .type = c.SDL_EVENT_TEXT_EDITING, .reserved = 0, .timestamp = 302, .windowID = c.SDL_GetWindowID(window), .text = "é界", .start = 2, .length = 0 };
    try app.event(event_value);
    try std.testing.expect(app.keyboard.pending_text == null);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 303, .windowID = c.SDL_GetWindowID(window), .text = "é界" };
    try app.event(event_value);
    const expected = std.fmt.bytesToHex("\x1b[0;;233:30028u", .lower);
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], &expected)) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
}

test "failed settings save restores fonts without changing canonical history or held leases; acceptance preserves pane overrides" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("settings transaction proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(1000, 650, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var current = config.Config.defaults(a);
    defer current.deinit();
    var panes: [2]Pane = undefined;
    var count: usize = 0;
    var proof_stage: []const u8 = "construction";

    defer for (panes[0..count]) |*p| {
        p.canvas.deinit();
        p.owner.?.destroy();
        p.recipe.deinit();
    };
    errdefer if (count == 2) {
        const status = panes[0].snapshot();
        std.debug.print("settings proof stage={s} title={s} p0_history={d} p1_history={d}\n", .{
            proof_stage,                                                     status.title[0..status.title_len],
            if (panes[0].canvas.frame()) |frame| frame.history_count else 0, if (panes[1].canvas.frame()) |frame| frame.history_count else 0,
        });
    };
    for (&panes, 0..) |*p, index| {
        var recipe = try config.Recipe.copy(a, try current.profile(0));
        errdefer recipe.deinit();
        const size: u16 = if (index == 0) 15 else 17;
        const owner = try terminal.Terminal.create(a, threaded.io(), std.testing.environ, .{
            .shell = "/bin/sh",
            .command = "read start; i=0; while [ \"$i\" -lt 70 ]; do printf '%s\\n' \"$i\"; i=$((i+1)); done; printf '\\033[6 q\\033]0;READY\\007'; while read line; do size=$(stty size); printf '\\033]0;%s:%s\\007' \"$line\" \"$size\"; printf '%s\\n' \"$line\"; done",
            .rows = 4,
            .columns = 20,
            .history_rows = 64,
        }, try fonts.config(threaded.io(), size), c.SDL_RegisterEvents(1), true);
        p.* = .{ .owner = owner, .recipe = recipe, .canvas = canvas.Canvas.init(a), .font_size = size, .font_overridden = index != 0, .rows = 4, .columns = 20 };
        count += 1;
    }
    var t: Tab = .{ .recipe = try config.Recipe.copy(a, try current.profile(0)) };
    defer t.recipe.deinit();
    const second = try t.tree.split(.horizontal);
    t.panes[0] = &panes[0];
    t.panes[second] = &panes[1];
    var app: App = .{ .init = undefined, .configuration = &current, .fonts = &fonts, .window = window, .renderer = renderer, .ui_fonts = &ui_fonts, .geometry = undefined, .wake_event = 0, .scale = 1, .bindings = try keybindings.Bindings.init(), .tab_count = 1 };
    app.init.io = threaded.io();
    app.tabs[0] = &t;
    proof_stage = "initial empty publication";
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        for (&panes) |*p| try p.canvas.update(renderer, p.owner.?);
        if (panes[0].canvas.frame() != null and panes[1].canvas.frame() != null) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    for (&panes) |*p| try p.submit(.{ .input = .{ .bytes = "START\n" } });
    proof_stage = "initial publication";
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        for (&panes) |*p| try p.canvas.update(renderer, p.owner.?);
        if (panes[0].canvas.frame() != null and panes[1].canvas.frame() != null and
            panes[0].canvas.frame().?.history_count >= 60 and panes[1].canvas.frame().?.history_count >= 60) break;
        // This observer must acknowledge early publications before waiting for later output.
        for (&panes) |*p| p.owner.?.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    const held = panes[0].canvas.frame().?;
    const generation = held.presentation_generation;
    const history = held.history_count;
    var candidate = try settings.change(&current, threaded.io(), .default_font, "23");
    defer candidate.deinit();
    candidate.value.cursor_stroke_pixels = 4;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(threaded.io(), "occupied", .default_dir);
    proof_stage = "save rollback";
    try std.testing.expectError(error.IsDir, app.applyConfigurationAt(&candidate, temporary.dir, "occupied"));
    try std.testing.expectEqual(@as(i32, 15), current.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u16, 15), panes[0].font_size);
    try std.testing.expectEqual(@as(u16, 17), panes[1].font_size);
    try std.testing.expectEqual(generation, panes[0].canvas.frame().?.presentation_generation);
    try std.testing.expectEqual(history, panes[0].canvas.frame().?.history_count);
    try std.testing.expectEqual(@as(u8, 2), current.value.cursor_stroke_pixels);
    proof_stage = "canonical continuity";
    try panes[0].submit(.{ .input = .{ .bytes = "CHECK\n" } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = panes[0].snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "CHECK:4 20")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    proof_stage = "restored publication";
    panes[0].owner.?.requestFrame();
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        try panes[0].canvas.update(renderer, panes[0].owner.?);
        const frame = panes[0].canvas.frame().?;
        if (frame.presentation_generation > generation and frame.history_count >= history and frame.terminal_revision == panes[0].snapshot().revision) break;
        // A real observer acknowledges presentation before waiting for a later cut.
        panes[0].owner.?.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    const restored = panes[0].canvas.frame().?;
    const restored_direct = panes[0].canvas.lease.?.snapshot;
    try std.testing.expectEqual(@as(u16, 2), restored_direct.cursor.?.solid.rect.width);
    proof_stage = "accepted save";
    try app.applyConfigurationAt(&candidate, temporary.dir, "app.json");
    try std.testing.expectEqual(@as(i32, 23), current.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u16, 23), panes[0].font_size);
    try std.testing.expectEqual(@as(u16, 17), panes[1].font_size);
    try std.testing.expect(panes[1].font_overridden);
    var reopened = try config.Config.loadAt(a, threaded.io(), temporary.dir, "app.json");
    defer reopened.deinit();
    try std.testing.expectEqual(@as(i32, 23), reopened.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u8, 4), reopened.value.cursor_stroke_pixels);
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        try panes[0].canvas.update(renderer, panes[0].owner.?);
        const frame = panes[0].canvas.frame().?;
        if (frame.presentation_generation > restored.presentation_generation) {
            const direct = panes[0].canvas.lease.?.snapshot;
            try std.testing.expectEqual(@as(u16, 6), direct.cursor.?.solid.rect.width);
            break;
        }
        panes[0].owner.?.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    // The same live pane follows font/display changes without fixed-pixel bars.
    for ([_]u16{ 6, 9, 15, 23, 30, 15 }, [_]f32{ 1, 1, 1.25, 1.5, 1.7, 2 }, [_]u16{ 2, 2, 5, 9, 14, 8 }) |logical, factor, expected| {
        const before_generation = panes[0].canvas.frame().?.presentation_generation;
        app.scale = factor;
        try app.configureFont(&panes[0], logical, false);
        attempts = 0;
        while (attempts < 5000) : (attempts += 1) {
            try panes[0].canvas.update(renderer, panes[0].owner.?);
            const frame = panes[0].canvas.frame().?;
            if (frame.presentation_generation > before_generation) {
                try std.testing.expectEqual(.bar, frame.cursor.?.shape);
                const direct = panes[0].canvas.lease.?.snapshot;
                try std.testing.expectEqual(@min(expected, frame.cursor.?.rect.width), direct.cursor.?.solid.rect.width);
                break;
            }
            panes[0].owner.?.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        try std.testing.expect(attempts < 5000);
    }

    // Simulate a staged A font commit followed by a rejected B transaction and
    // rejected A rollback. The old saved recipe must not make GUI geometry lie.
    proof_stage = "rejected rollback and later reconciliation";
    app.scale = 1;
    try app.configureFont(&panes[0], 23, false);
    const saved_cell = panes[0].cell_size.?;
    const staged = try panes[0].owner.?.reconfigure(try app.presentationConfig(&fonts, 27, current.value.cursor_stroke_pixels), null);
    try std.testing.expect(!std.meta.eql(saved_cell, staged.cell_size));
    preserveStagedFont(.{ .pane = &panes[0], .size = 23, .overridden = false, .geometry = staged }, error.InputBackpressured);
    try std.testing.expect(panes[0].font_repair_pending);
    try std.testing.expectEqual(@as(?terminal.ConfigureError, error.InputBackpressured), panes[0].font_failure);
    try std.testing.expectEqualDeep(staged.cell_size, panes[0].cell_size.?);
    try std.testing.expectEqual(staged.rows, panes[0].rows);
    try std.testing.expectEqual(staged.columns, panes[0].columns);
    try std.testing.expectEqual(@as(i32, 23), current.value.terminal_font_pixels);

    var retry = try settings.change(&current, threaded.io(), .default_font, "23");
    defer retry.deinit();
    try app.updateConfiguration(&retry, temporary.dir, "unchanged.json", false);
    try std.testing.expect(!panes[0].font_repair_pending);
    try std.testing.expectEqual(@as(?terminal.ConfigureError, null), panes[0].font_failure);
    try std.testing.expectEqual(@as(u16, 23), panes[0].font_size);
    try std.testing.expectEqualDeep(saved_cell, panes[0].cell_size.?);
    // The saved configuration did not change; the retry corrected the worker.
    try std.testing.expectEqual(@as(i32, 23), current.value.terminal_font_pixels);
}

test {
    // zig-audit: acknowledge discard
    // reason: Loads the independent selection module behavior proofs without a runtime operation or result.
    _ = selection;
}

test "SDL drop events keep modal input owners isolated and copy event bytes before retirement" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("drop proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(a, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
    }, try fonts.config(threaded.io(), 15), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    var p: Pane = .{ .owner = owner, .recipe = try config.Recipe.copy(a, try configuration.profile(0)), .canvas = canvas.Canvas.init(a) };
    defer p.recipe.deinit();
    defer p.canvas.deinit();
    var t: Tab = .{ .recipe = try config.Recipe.copy(a, try configuration.profile(0)) };
    defer t.recipe.deinit();
    t.panes[0] = &p;
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .focused = true,
        .tab_count = 1,
    };
    app.tabs[0] = &t;
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "READY")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    var event_value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    event_value.drop.type = c.SDL_EVENT_DROP_TEXT;
    event_value.drop.windowID = c.SDL_GetWindowID(window);
    event_value.drop.data = "wrong-owner\\n";
    app.palette = .{};
    try app.event(event_value);
    app.palette = null;
    app.settings_editor = .{};
    try app.event(event_value);
    app.settings_editor = null;
    p.finder = .{};
    try app.event(event_value);
    p.finder = null;
    event_value.drop.windowID += 1;
    try app.event(event_value);
    event_value.drop.windowID = c.SDL_GetWindowID(window);
    event_value.drop.data = null;
    try app.event(event_value);
    var text: [4:0]u8 = .{ 'y', 'e', 's', '\n' };
    event_value.drop.data = &text;
    try app.event(event_value);
    @memset(&text, '?');
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], "yes")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
}

fn environmentAllocationProof(gpa: std.mem.Allocator, parent: *const std.process.Environ.Map) !void {
    const value = try profileEnvironment(gpa, parent, &.{
        .{ .name = "HOWL_OVERRIDE", .value = "界 south" },
        .{ .name = "HOWL_EMPTY", .value = "" },
    });
    defer value.block.deinit(gpa);
    try std.testing.expectEqualStrings("north", std.process.Environ.getPosix(value, "HOWL_BASE").?);
    try std.testing.expectEqualStrings("界 south", std.process.Environ.getPosix(value, "HOWL_OVERRIDE").?);
    try std.testing.expectEqualStrings("", std.process.Environ.getPosix(value, "HOWL_EMPTY").?);
}
test "profile environment owns inherited replacements and empty Unicode values across allocation failure" {
    var parent = std.process.Environ.Map.init(std.testing.allocator);
    defer parent.deinit();
    try parent.put("HOWL_BASE", "north");
    try parent.put("HOWL_OVERRIDE", "original");
    try parent.put("HOWL_EMPTY", "nonempty");
    try std.testing.checkAllAllocationFailures(std.testing.allocator, environmentAllocationProof, .{&parent});
    try std.testing.expectEqualStrings("original", parent.get("HOWL_OVERRIDE").?);
    try std.testing.expectEqualStrings("nonempty", parent.get("HOWL_EMPTY").?);
}

test "startup environment snapshot survives activation removal and parent retirement" {
    const a = std.testing.allocator;
    const owned = snapshot: {
        var parent = std.process.Environ.Map.init(a);
        defer parent.deinit();
        try parent.put("XDG_ACTIVATION_TOKEN", "one-use");
        try parent.put("HOWL_BASE", "retained");
        const value = try profileEnvironment(a, &parent, &.{});
        errdefer value.block.deinit(a);
        try std.testing.expect(parent.orderedRemove("XDG_ACTIVATION_TOKEN"));
        break :snapshot value;
    };
    defer owned.block.deinit(a);
    try std.testing.expectEqualStrings("retained", std.process.Environ.getPosix(owned, "HOWL_BASE").?);
    try std.testing.expectEqualStrings("one-use", std.process.Environ.getPosix(owned, "XDG_ACTIVATION_TOKEN").?);
}
test "Local child keeps copied profile environment after caller retirement and terminal identity stays canonical" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const a = std.testing.allocator;
    var parent = try std.process.Environ.createMap(std.testing.environ, a);
    defer parent.deinit();
    try parent.put("HOWL_BASE", "inherited");
    var provided = try profileEnvironment(a, &parent, &.{
        .{ .name = "HOWL_BASE", .value = "overridden" },
        .{ .name = "HOWL_OVERRIDE", .value = "界 south" },
        .{ .name = "HOWL_EMPTY", .value = "" },
        .{ .name = "TERM", .value = "must-not-replace-terminal-identity" },
    });
    var provided_live = true;
    defer if (provided_live) provided.block.deinit(a);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(a, threaded.io(), provided, .{
        .shell = "/bin/sh",
        .command = "stty -echo; read line; printf '\\033]0;%s|%s|%s|%s\\007' \"$HOWL_BASE\" \"$HOWL_OVERRIDE\" \"$HOWL_EMPTY\" \"$TERM\"; sleep 30",
        .rows = 4,
        .columns = 20,
    }, try fonts.config(threaded.io(), 15), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    provided.block.deinit(a);
    provided_live = false;
    try parent.put("HOWL_BASE", "changed-after-launch");
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], "overridden|界 south||xterm-256color")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    try std.testing.expectEqualStrings("changed-after-launch", parent.get("HOWL_BASE").?);
}

test "centred terminal lattice shares slack, clips stale frames and maps input at fractional scale" {
    const available: c.SDL_FRect = .{ .x = 9, .y = 55, .w = 983, .h = 527 };
    const cell: commands.Size = .{ .width = 17, .height = 41 };
    for ([_]f32{ 1, 1.7, 2 }) |scale| {
        const surface: commands.Size = .{ .width = 850, .height = 492 };
        const placed = terminalPlacement(available, surface, scale);
        try std.testing.expect(placed.x >= available.x and placed.y >= available.y);
        try std.testing.expect(placed.x + placed.w <= available.x + available.w);
        try std.testing.expect(placed.y + placed.h <= available.y + available.h);
        try std.testing.expectApproxEqAbs(@round(placed.x * scale), placed.x * scale, 0.001);
        try std.testing.expectApproxEqAbs(@round(placed.y * scale), placed.y * scale, 0.001);
        const left = placed.x - available.x;
        const right = available.x + available.w - placed.x - placed.w;
        const top = placed.y - available.y;
        const bottom = available.y + available.h - placed.y - placed.h;
        try std.testing.expect(@abs(left - right) <= 1 / scale + 0.001);
        try std.testing.expect(@abs(top - bottom) <= 1 / scale + 0.001);
        const rect: layout.Rect = .{ .x = placed.x, .y = placed.y, .width = placed.w, .height = placed.h };
        const hit = pointer.locate(rect, scale, cell, surface, placed.x + 18 / scale, placed.y + 42 / scale, false).?;
        try std.testing.expectEqual(@as(u16, 1), hit.col);
        try std.testing.expectEqual(@as(i32, 1), hit.row);
        try std.testing.expect(pointer.locate(rect, scale, cell, surface, available.x, available.y, false) == null);
    }
    const oversized = terminalPlacement(available, .{ .width = 2000, .height = 2000 }, 1);
    try std.testing.expectEqualDeep(available, oversized);
    const tiny: c.SDL_FRect = .{ .x = 10, .y = 20, .w = 0.125, .h = 0.25 };
    try std.testing.expectEqualDeep(tiny, terminalPlacement(tiny, .{ .width = 1, .height = 1 }, 1.7));
}

test "top-right toast paints only a compact corner and reuses the notice surface" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("top-right toast pixels", 320, 110, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(320, 110, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    configuration.value.hide_single_tab = true;
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .width = 320,
        .height = 110,
    };
    const message = "Settings saved";
    @memcpy(app.notice[0..message.len], message);
    app.notice_len = message.len;
    app.notice_until = 5000;
    const sentinel: c.SDL_Color = .{ .r = 7, .g = 33, .b = 91, .a = 255 };
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, sentinel.r, sentinel.g, sentinel.b, sentinel.a));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try app.drawToast(100);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const right = status_toast.geometry(320, 110, 0, try app.textWidth(message), .top_right).?;
    try std.testing.expectEqual(sentinel, try testPixel(surface, 8, 18));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 160, 96));
    try std.testing.expect(!std.meta.eql(sentinel, try testPixel(
        surface,
        @intFromFloat(right.x + 8),
        @intFromFloat(right.y + 15),
    )));
    // At x+5,y+1 a 4px chrome corner is filled. The old 12px pill
    // would leave this pixel at the untouched sentinel background.
    try std.testing.expect(!std.meta.eql(sentinel, try testPixel(
        surface,
        @intFromFloat(right.x + 5),
        @intFromFloat(right.y + 1),
    )));
    configuration.value.status_toast_position = .top_left;
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, sentinel.r, sentinel.g, sentinel.b, sentinel.a));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try app.drawToast(101);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    try std.testing.expectEqual(sentinel, try testPixel(
        surface,
        @intFromFloat(right.x + 8),
        @intFromFloat(right.y + 15),
    ));
    try std.testing.expect(!std.meta.eql(sentinel, try testPixel(surface, 20, 23)));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 160, 96));
}

test "toast spinner and completion share bounded deadlines without idle polling" {
    var app: App = .{
        .init = undefined,
        .configuration = undefined,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
    };
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(0));
    app.toast_animated = true;
    try std.testing.expectEqual(@as(?c_int, 120), app.waitTimeout(0));
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(119));
    app.toast_done_until = 300;
    try std.testing.expectEqual(@as(?c_int, 60), app.waitTimeout(240));
    app.toast_animated = false;
    try std.testing.expectEqual(@as(?c_int, 60), app.waitTimeout(240));
    app.toast_done_until = 0;
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(240));
}

test "notice expiry wakes a quiet window once and preserves bounded selection scrolling" {
    var app: App = .{ .init = undefined, .configuration = undefined, .fonts = undefined, .window = undefined, .renderer = undefined, .ui_fonts = undefined, .geometry = undefined, .wake_event = 0, .scale = 1, .bindings = try keybindings.Bindings.init() };
    app.notice_len = 5;
    app.notice_until = 5000;
    try std.testing.expectEqual(@as(?c_int, 5000), app.waitTimeout(0));
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(4999));
    // Crossing the deadline after draw still earns a repaint before indefinite wait.
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(5000));
    try std.testing.expectEqual(@as(usize, 5), app.notice_len);
    app.expireNotice(5000);
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(5000));
    try std.testing.expectEqual(@as(usize, 0), app.notice_len);
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(9000));
    app.selecting = .{ .pane = undefined, .x = 0, .y = 0, .edge = 1 };
    app.notice_len = 5;
    app.notice_until = 10000;
    try std.testing.expectEqual(@as(?c_int, 50), app.waitTimeout(9000));
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(9999));
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(10000));
    app.expireNotice(10000);
    try std.testing.expectEqual(@as(?c_int, 50), app.waitTimeout(10000));
    app.selecting = null;
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(10000));
}

test "single-tab header gives all space and former caption hits back to the terminal" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .tab_count = 1,
    };
    const shown = app.terminalBody();
    try std.testing.expectEqual(chrome.height, shown.y);
    configuration.value.hide_single_tab = true;
    try std.testing.expectEqual(@as(f32, 0), app.terminalBody().y);
    try std.testing.expectEqual(app.height, app.terminalBody().height);
    var event_value: c.SDL_Event = undefined;
    event_value.button = .{
        .type = c.SDL_EVENT_MOUSE_BUTTON_DOWN,
        .reserved = 0,
        .timestamp = 0,
        .windowID = 0,
        .which = 0,
        .button = c.SDL_BUTTON_LEFT,
        .down = true,
        .clicks = 1,
        .padding = 0,
        .x = app.width - 20,
        .y = 16,
    };
    try std.testing.expect(!try app.chromeEvent(event_value));
    try std.testing.expectEqual(chrome.Button.none, app.chrome_pressed);
    try std.testing.expect(app.running);
    app.tab_count = 2;
    try std.testing.expectEqualDeep(shown, app.terminalBody());
    app.tab_count = 1;
    try std.testing.expectEqual(@as(f32, 0), app.terminalBody().y);
    app.palette = .{ .profile = true };
    try std.testing.expectEqual(@as(f32, 0), app.paletteRect().y);
}

test "large discovered menus filter and page independently of saved settings" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var cached: [100]config.ScannedProfile = undefined;
    for (&cached, 0..) |*entry, i| entry.* = .{ .kind = .ssh, .recipe = .{
        .id = try std.fmt.allocPrint(arena.allocator(), "auto.ssh.{d:0>3}", .{i}),
        .name = try std.fmt.allocPrint(arena.allocator(), "host-{d:0>3}", .{i}),
        .shell = "/usr/bin/ssh",
        .arguments = &.{ "-t", "--", "literal-alias" },
    } };
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .tab_count = 1,
        .palette = .{ .profile = true },
    };
    var indices: [palette_limit]usize = undefined;
    configuration.value.scanned_profiles = &.{};
    try std.testing.expectEqual(@as(usize, 3), app.paletteRows());
    configuration.value.scanned_profiles = &cached;
    const count = try app.palette.?.indices(&configuration, &indices);
    try std.testing.expectEqual(@as(usize, 103), count);
    try app.paletteKey(c.SDLK_END, c.SDL_KMOD_CTRL);
    try std.testing.expectEqual(count - 1, app.palette.?.list.selected);
    try std.testing.expect(app.paletteStart(count) + app.paletteRows() <= count);
    try app.paletteKey(c.SDLK_PAGEUP, 0);
    try std.testing.expectEqual(count - 1 - app.paletteRows(), app.palette.?.list.selected);
    const query = "HOST-099";
    @memcpy(app.palette.?.query[0..query.len], query);
    app.palette.?.len = query.len;
    try std.testing.expectEqual(@as(usize, 1), try app.palette.?.indices(&configuration, &indices));
    try std.testing.expectEqualStrings("host-099", (try app.menuProfile(indices[0])).name);
    try std.testing.expectEqual(@as(u8, 1), configuration.profileCount());
    app.palette.?.erase(true);
    app.palette.?.list.selected = 2;
    const hovered = app.paletteRow(4);
    try app.paletteHover(hovered.x + 10, hovered.y + 10);
    try std.testing.expectEqual(@as(usize, 2), app.palette.?.list.selected);
    try std.testing.expectEqual(@as(?usize, 4), app.palette.?.list.hovered);
    const remote = app.paletteFilterRect(@backingInt(picker.Filter.remote));
    try app.pointerDown(remote.x + 10, remote.y + 10, .left, .{}, 1);
    try std.testing.expectEqual(picker.Filter.remote, app.palette.?.filter);
    try app.paletteKey(c.SDLK_TAB, c.SDL_KMOD_SHIFT);
    try std.testing.expectEqual(picker.Filter.repl, app.palette.?.filter);
    try std.testing.expectEqual(@as(usize, 0), try app.palette.?.indices(&configuration, &indices));
}

/// Read one exact software-rendered pixel for paint assertions.
pub fn testPixel(surface: *c.SDL_Surface, x: c_int, y: c_int) !c.SDL_Color {
    var result: c.SDL_Color = undefined;
    if (!c.SDL_ReadSurfacePixel(surface, x, y, &result.r, &result.g, &result.b, &result.a)) return error.SDL;
    return result;
}
test "Gruvbox selected text stays inside even a short scrolled text field" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("field clipping proof", 240, 100, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(240, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    configuration.value.app_theme = "gruvbox_dark";
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .focused = true,
    };
    const colors = try app.uiPalette();
    const sentinel: c.SDL_Color = .{ .r = 235, .g = 1, .b = 201, .a = 255 };
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, sentinel.r, sentinel.g, sentinel.b, sentinel.a));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    const text = "a long field that scrolls well beyond its content box";
    var edit: widgets.Text = .{};
    edit.selectAll(text.len);
    try app.drawField(.{ .x = 10, .y = 10, .width = 80, .height = 28 }, &edit, text, "", true);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    try std.testing.expect(edit.scroll > 0);
    try std.testing.expectEqual(appearance.selection(colors).background, try testPixel(surface, 18, 14));
    try std.testing.expectEqual(colors.panel, try testPixel(surface, 88, 18));
    try std.testing.expectEqual(colors.panel, try testPixel(surface, 18, 36));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 9, 20));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 90, 20));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 18, 9));
    try std.testing.expectEqual(sentinel, try testPixel(surface, 18, 38));
    const viewport: layout.Rect = .{ .x = 30, .y = 52, .width = 55, .height = 28 };
    try setClip(renderer, viewport);
    try app.clippedTextColor("nested form field", .{ .x = 10, .y = 50, .width = 110, .height = 30 }, 10, colors.text);
    try std.testing.expect(c.SDL_RenderClipEnabled(renderer));
    var restored: c.SDL_Rect = undefined;
    try std.testing.expect(c.SDL_GetRenderClipRect(renderer, &restored));
    try std.testing.expectEqual(c.SDL_Rect{ .x = 30, .y = 52, .w = 55, .h = 28 }, restored);
    clearClip(renderer);
}

test "split reversal clips an oversized stale frame at fractional pane origins" {
    // Captain's core: (855.000061 + 1537) - 1537 rounds down to 855.
    // A clamp over absolute coordinates therefore inverted its bounds.
    const available: c.SDL_FRect = .{ .x = 855.000061, .y = 34, .w = 1537, .h = 1308 };
    const placed = terminalPlacement(available, .{ .width = 2670, .height = 2072 }, 1.6);
    try std.testing.expectEqual(available.x, placed.x);
    try std.testing.expectEqual(available.w, placed.w);
    for ([_]f32{ 1, 1.25, 1.6, 1.7, 2 }) |scale| {
        for (0..10000) |i| {
            const ratio = @as(f32, @floatFromInt(1000 + i % 8001)) / 10000;
            const first = @as(f32, 2392) * ratio;
            // Exercise both sides, horizontal/vertical, and frames both older
            // (oversized) and newer (smaller) than the current pane geometry.
            for ([_]c.SDL_FRect{
                .{ .x = 0, .y = 34, .w = first, .h = 1308 },
                .{ .x = first, .y = 34, .w = 2392 - first, .h = 1308 },
                .{ .x = 0, .y = first, .w = 2392, .h = 2392 - first },
            }) |pane| {
                for ([_]commands.Size{
                    .{ .width = 4000, .height = 4000 },
                    .{ .width = 17, .height = 41 },
                    .{ .width = 2670, .height = 2072 },
                }) |surface| {
                    const rect = terminalPlacement(pane, surface, scale);
                    try std.testing.expect(rect.x >= pane.x and rect.y >= pane.y);
                    try std.testing.expect(rect.w <= pane.w and rect.h <= pane.h);
                    try std.testing.expect(rect.x + rect.w <= pane.x + pane.w + 0.001);
                    try std.testing.expect(rect.y + rect.h <= pane.y + pane.h + 0.001);
                    if (rect.w == pane.w) try std.testing.expectEqual(pane.x, rect.x);
                    if (rect.h == pane.h) try std.testing.expectEqual(pane.y, rect.y);
                }
            }
        }
    }
}

test "cursor deadline shares notice and selection waits and retires without polling" {
    var app: App = .{ .init = undefined, .configuration = undefined, .fonts = undefined, .window = undefined, .renderer = undefined, .ui_fonts = undefined, .geometry = undefined, .wake_event = 0, .scale = 1, .bindings = try keybindings.Bindings.init() };
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(0));
    app.cursor_deadline = 500;
    try std.testing.expectEqual(@as(?c_int, 500), app.waitTimeout(0));
    app.notice_len = 1;
    app.notice_until = 200;
    try std.testing.expectEqual(@as(?c_int, 200), app.waitTimeout(0));
    app.selecting = .{ .pane = undefined, .x = 0, .y = 0, .edge = 1 };
    try std.testing.expectEqual(@as(?c_int, 50), app.waitTimeout(0));
    app.selecting = null;
    app.notice_len = 0;
    try std.testing.expectEqual(@as(?c_int, 1), app.waitTimeout(500));
    app.cursor_deadline = null;
    try std.testing.expectEqual(@as(?c_int, null), app.waitTimeout(500));
}

test "tab rename owns text, follows its tab, resets and never leaks a commit to the shell" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("tab rename proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    try std.testing.expect(c.SDL_StartTextInput(window));
    const surface = c.SDL_CreateSurface(1000, 650, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const geometry = try a.create(canvas.Geometry);
    defer a.destroy(geometry);
    geometry.* = .{};
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(a, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;AUTO\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, try fonts.config(threaded.io(), 15), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    var pane_a: Pane = .{ .owner = owner, .recipe = try config.Recipe.copy(a, try configuration.profile(0)), .canvas = canvas.Canvas.init(a) };
    defer pane_a.recipe.deinit();
    defer pane_a.canvas.deinit();
    var pane_b: Pane = .{ .recipe = try config.Recipe.copy(a, try configuration.profile(0)), .canvas = canvas.Canvas.init(a) };
    defer pane_b.recipe.deinit();
    defer pane_b.canvas.deinit();
    var tab_a: Tab = .{ .recipe = try config.Recipe.copy(a, try configuration.profile(0)) };
    defer tab_a.recipe.deinit();
    var tab_b: Tab = .{ .recipe = try config.Recipe.copy(a, try configuration.profile(0)) };
    defer tab_b.recipe.deinit();
    tab_a.panes[0] = &pane_a;
    tab_b.panes[0] = &pane_b;
    try tab_b.title.set("Second");
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = geometry,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .focused = true,
        .tab_count = 2,
        .input_timestamp = 100,
    };
    app.tabs[0] = &tab_a;
    app.tabs[1] = &tab_b;
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "AUTO")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    attempts = 0;
    while (pane_a.canvas.frame() == null and attempts < 5000) : (attempts += 1) {
        try pane_a.canvas.update(renderer, owner);
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(pane_a.canvas.frame() != null);
    configuration.value.cursor_blink = .always;
    try app.draw();
    try std.testing.expect(app.cursor_deadline != null);
    const body = app.headerTabs(app.width).body(0);
    try app.pointerDown(body.x + 12, body.y + 12, .left, .{}, 2);
    try std.testing.expect(app.rename_editor != null);
    try std.testing.expect(app.drag == .none);
    try app.draw();
    try std.testing.expect(app.cursor_deadline == null);
    try std.testing.expect(pane_a.blink.deadline == null);
    var event_value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 110, .windowID = c.SDL_GetWindowID(window), .text = "Hannes 界" };
    try app.event(event_value);
    try std.testing.expectEqualStrings("Hannes 界", app.rename_editor.?.bytes[0..app.rename_editor.?.len]);
    try std.testing.expectEqual(@as(usize, 0), tab_a.title.len);
    try app.drawField(try app.renameField(), &app.rename_editor.?.edit, app.rename_editor.?.bytes[0..app.rename_editor.?.len], "Automatic title", true);
    try app.drawComposition();
    event_value.key = std.mem.zeroes(c.SDL_KeyboardEvent);
    event_value.key.type = c.SDL_EVENT_KEY_DOWN;
    event_value.key.timestamp = 120;
    event_value.key.key = c.SDLK_RETURN;
    event_value.key.scancode = c.SDL_SCANCODE_RETURN;
    try app.event(event_value);
    try std.testing.expect(app.rename_editor == null);
    try std.testing.expectEqual(@as(usize, 0), app.notice_len);
    try std.testing.expectEqualStrings("Hannes 界", tab_a.title.resolve("changed by shell"));
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 121, .windowID = c.SDL_GetWindowID(window), .text = "ENTER-LEAK\n" };
    try app.event(event_value);
    try app.beginRename();
    try app.rename_editor.?.edit.insert(&app.rename_editor.?.bytes, &app.rename_editor.?.len, "discard");
    try app.finishRename(false);
    try std.testing.expectEqualStrings("Hannes 界", tab_a.title.resolve("automatic"));
    try app.beginRename();
    try app.rename_editor.?.edit.insert(&app.rename_editor.?.bytes, &app.rename_editor.?.len, "Moved");
    app.moveTab(1);
    try std.testing.expect(app.rename_editor.?.tab == app.tab());
    try app.finishRename(true);
    try std.testing.expectEqualStrings("Moved", tab_a.title.resolve("automatic"));
    try std.testing.expectEqualStrings("Second", tab_b.title.resolve("automatic"));
    try app.dispatch(.{ .action = .reset_tab_title });
    try std.testing.expectEqualStrings("new automatic", tab_a.title.resolve("new automatic"));
    app.moveTab(0);
    app.tab_count = 1;
    app.tabs[1] = null;
    configuration.value.hide_single_tab = true;
    const terminal_body = app.terminalBody();
    try app.beginRename();
    try std.testing.expectEqualDeep(terminal_body, app.terminalBody());
    try std.testing.expectEqual(@as(f32, 0), app.headerHeight());
    try std.testing.expect((try app.renameField()).height > 0);
    try app.finishRename(false);
    event_value.key = std.mem.zeroes(c.SDL_KeyboardEvent);
    event_value.key.type = c.SDL_EVENT_KEY_DOWN;
    event_value.key.timestamp = 200;
    event_value.key.key = c.SDLK_S;
    event_value.key.scancode = c.SDL_SCANCODE_S;
    try app.event(event_value);
    event_value.text = .{ .type = c.SDL_EVENT_TEXT_INPUT, .reserved = 0, .timestamp = 201, .windowID = c.SDL_GetWindowID(window), .text = "sentinel" };
    try app.event(event_value);
    try owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter } } } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "sentinel")) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
}

test "retiring a tab clears its rename target before freeing it" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var owned: ?*Tab = try allocator.create(Tab);
    defer if (owned) |value| allocator.destroy(value);
    const value = owned.?;
    value.* = .{ .recipe = try config.Recipe.copy(allocator, try configuration.profile(0)) };
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = undefined,
        .rename_editor = .{ .tab = value },
    };
    app.destroyTab(value);
    owned = null;
    try std.testing.expect(app.rename_editor == null);
    try std.testing.expect(app.keyboard.suppress_text);
}

test "SDL single double and triple clicks retain selection through motion and release" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const test_allocator = std.testing.allocator;
    const window = c.SDL_CreateWindow("selection drag proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    try std.testing.expect(c.SDL_StartTextInput(window));
    const surface = c.SDL_CreateSurface(1000, 650, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const geometry = try test_allocator.create(canvas.Geometry);
    defer test_allocator.destroy(geometry);
    geometry.* = .{};
    var fonts = try testFonts(test_allocator);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(test_allocator, &fonts, 15);
    defer ui_fonts.deinit();
    var threaded = std.Io.Threaded.init(test_allocator, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(test_allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf 'one two three\\r\\nfour five\\r\\nsix seven\\033]0;READY\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, try fonts.config(threaded.io(), 15), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var configuration = config.Config.defaults(test_allocator);
    defer configuration.deinit();
    var p: Pane = .{ .owner = owner, .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(0)), .canvas = canvas.Canvas.init(test_allocator) };
    defer p.recipe.deinit();
    defer p.canvas.deinit();
    var t: Tab = .{ .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(0)) };
    defer t.recipe.deinit();
    t.panes[0] = &p;
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = geometry,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .focused = true,
        .tab_count = 1,
    };
    app.tabs[0] = &t;
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        try p.canvas.update(renderer, owner);
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "READY") and p.canvas.frame() != null) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);

    const frame = p.canvas.frame().?;
    const rect = terminalPlacement(paneContent(app.terminalBody()), frame.surface, app.scale);
    const cw: f32 = @floatFromInt(frame.cell_size.width);
    const ch: f32 = @floatFromInt(frame.cell_size.height);
    for ([_]u8{ 1, 2, 3 }) |clicks| {
        for ([_]bool{ false, true }) |drag| {
            var event_value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
            event_value.button.type = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
            event_value.button.button = c.SDL_BUTTON_LEFT;
            event_value.button.clicks = clicks;
            event_value.button.x = rect.x + 5.5 * cw;
            event_value.button.y = rect.y + 0.5 * ch;
            try app.event(event_value);
            try std.testing.expect(app.selecting != null);
            if (drag) {
                event_value = std.mem.zeroes(c.SDL_Event);
                event_value.motion.type = c.SDL_EVENT_MOUSE_MOTION;
                event_value.motion.x = rect.x + 10.5 * cw;
                event_value.motion.y = rect.y + (if (clicks == 3) @as(f32, 1.5) else 0.5) * ch;
                try app.event(event_value);
                try std.testing.expectEqual(event_value.motion.x, app.selecting.?.x);
            }
            const held = app.selecting.?;
            event_value = std.mem.zeroes(c.SDL_Event);
            event_value.button.type = c.SDL_EVENT_MOUSE_BUTTON_UP;
            event_value.button.button = c.SDL_BUTTON_LEFT;
            event_value.button.x = held.x;
            event_value.button.y = held.y;
            try app.event(event_value);
            try std.testing.expect(app.selecting == null);
            const text = try owner.copySelection(test_allocator, 128);
            defer test_allocator.free(text);
            const expected: []const u8 = switch (clicks) {
                1 => if (drag) "wo thr" else "w",
                2 => if (drag) "two three" else "two",
                else => if (drag) "one two three\nfour five" else "one two three",
            };
            try std.testing.expectEqualStrings(expected, text);
        }
    }
}

test "session visibility follows tab zoom and explicit window state not focus" {
    var first: Tab = .{ .recipe = undefined };
    var second: Tab = .{ .recipe = undefined };
    const split_slot = try first.tree.split(.horizontal);
    var app: App = .{
        .init = undefined,
        .configuration = undefined,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .tab_count = 2,
    };
    app.tabs[0] = &first;
    app.tabs[1] = &second;
    try std.testing.expect(app.panePotentiallyVisible(0, 0));
    try std.testing.expect(app.panePotentiallyVisible(0, split_slot));
    try std.testing.expect(!app.panePotentiallyVisible(1, 0));
    app.focused = false;
    try std.testing.expect(app.panePotentiallyVisible(0, 0));
    first.tree.zoomed = true;
    first.tree.active = split_slot;
    try std.testing.expect(!app.panePotentiallyVisible(0, 0));
    try std.testing.expect(app.panePotentiallyVisible(0, split_slot));
    app.active = 1;
    try std.testing.expect(!app.panePotentiallyVisible(0, split_slot));
    try std.testing.expect(app.panePotentiallyVisible(1, 0));
    const Check = struct {
        fn event(a: *App, kind: u32) !void {
            var value: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
            value.type = kind;
            try a.event(value);
        }
    };
    try Check.event(&app, c.SDL_EVENT_WINDOW_HIDDEN);
    try Check.event(&app, c.SDL_EVENT_WINDOW_MINIMIZED);
    try Check.event(&app, c.SDL_EVENT_WINDOW_SHOWN);
    try std.testing.expect(!app.panePotentiallyVisible(1, 0));
    try Check.event(&app, c.SDL_EVENT_WINDOW_RESTORED);
    try std.testing.expect(app.panePotentiallyVisible(1, 0));
    // SDL occlusion/exposure alone is not the local authority for invisibility.
    try Check.event(&app, c.SDL_EVENT_WINDOW_OCCLUDED);
    try std.testing.expect(app.panePotentiallyVisible(1, 0));
    try Check.event(&app, c.SDL_EVENT_WINDOW_HIDDEN);
    try Check.event(&app, c.SDL_EVENT_WINDOW_MAXIMIZED);
    try std.testing.expect(!app.panePotentiallyVisible(1, 0));
    try Check.event(&app, c.SDL_EVENT_WINDOW_SHOWN);
    try std.testing.expect(app.panePotentiallyVisible(1, 0));
}
