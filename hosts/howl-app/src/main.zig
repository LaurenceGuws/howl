//! Owns the local SDL window, pane layout, input routing and terminal workers.
const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
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
const settings = @import("settings.zig");
const discovery = @import("discovery.zig");
const picker = @import("picker.zig");
const palette_limit = picker.limit;
const appearance = @import("appearance.zig");
const color_config = @import("colors.zig");
const theme_presets = @import("themes.zig");
const font_chooser = @import("font_chooser.zig");
const selection = @import("selection.zig");
const find = @import("find.zig");
const scrollbar = @import("scrollbar.zig");
const desktop = @import("desktop.zig");
const allocator = std.heap.smp_allocator;
const version = "0.1.6-dev";
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
    rows: u16 = 0,
    columns: u16 = 0,
    size_control: bool = true,
    font_size: u16 = 15,
    font_overridden: bool = false,
    selection_serial: u64 = 0,
    selection_failure_reported: u64 = 0,
    selection_hit: ?SelectionHit = null,
    finder: ?FindEditor = null,
    cell_size: ?instance.render.terminal.Size = null,
    font_failure: ?terminal.ConfigureError = null,
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
    tree: layout.Tree = layout.Tree.init(),
    panes: [layout.pane_limit]?*Pane = @splat(null),
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
const SelectionHit = struct { point: instance.Terminal.TextPoint, columns: u16, alternate: bool };
const App = struct {
    init: std.process.Init,
    configuration: *config.Config,
    fonts: *font_owner.Fonts,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    ui_fonts: *font_owner.TextFonts,
    geometry: *canvas.Geometry,
    wake_event: u32,
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
    discovered: ?*discovery.Catalogue = null,
    settings_editor: ?settings.Editor = null,
    chooser: ?*font_chooser.Chooser = null,
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

    fn deinit(self: *App) void {
        if (!c.SDL_SetCursor(c.SDL_GetDefaultCursor())) self.report(error.SDL);
        for (self.cursors) |cursor| if (cursor) |owned| c.SDL_DestroyCursor(owned);
        if (self.discovered) |catalogue| catalogue.destroy(allocator);
        if (self.chooser) |chooser| chooser.destroy(allocator);
        for (self.tabs[0..self.tab_count]) |value| self.destroyTab(value.?);
    }
    fn tab(self: *App) *Tab {
        return self.tabs[self.active].?;
    }
    fn pane(self: *App) *Pane {
        return self.tab().panes[self.tab().tree.active].?;
    }
    fn isHovered(self: *const App, rect: layout.Rect) bool {
        return if (self.hover_point) |point| rect.contains(point.x, point.y) else false;
    }
    fn headerHover(self: *const App) chrome.HeaderTarget {
        if (self.headerHeight() == 0 or self.drag != .none) return .none;
        const point = self.hover_point orelse return .none;
        return chrome.headerAt(self.headerTabs(self.width), point.x, point.y);
    }
    fn headerTabs(self: *const App, width: f32) chrome.Tabs {
        return chrome.Tabs.init(self.tab_count, width, self.configuration.value.tab_width == .fit);
    }
    fn headerHeight(self: *const App) f32 {
        return if (self.configuration.value.hide_single_tab and self.tab_count <= 1) 0 else chrome.height;
    }
    fn terminalBody(self: *const App) layout.Rect {
        const top = self.headerHeight();
        return .{ .x = 0, .y = top, .width = @max(1, self.width), .height = @max(1, self.height - top) };
    }
    fn setNotice(self: *App, message: []const u8) void {
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
        if (self.cursor_deadline) |deadline| timeout = @min(timeout orelse std.math.maxInt(c_int), @max(1, deadline -| now));
        return if (timeout) |value| @intCast(@min(value, std.math.maxInt(c_int))) else null;
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
        return self.configuration.profile(try self.configuration.defaultProfile());
    }
    fn launch(self: *App, recipe: config.Profile, font_size: u16) CreationError!*terminal.Terminal {
        const inherited = if (recipe.environment.len != 0) try profileEnvironment(allocator, self.init.environ_map, recipe.environment) else self.init.minimal.environ;
        defer if (recipe.environment.len != 0) inherited.block.deinit(allocator);
        const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(font_size)) * self.scale));
        const presentation = try self.fonts.config(self.init.io, pixels);
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
        for (value.panes) |maybe| if (maybe) |p| self.destroyPane(p);
        value.recipe.deinit();
        allocator.destroy(value);
    }
    fn cancelComposition(self: *App) void {
        self.preedit.cancel(self.input_timestamp);
        if (!c.SDL_ClearComposition(self.window)) self.report(error.SDLComposition);
    }
    fn loseKeyboard(self: *App) !void {
        self.cursor_deadline = null;
        if (self.tab_count != 0) self.pane().blink.reset();
        self.hover_divider = null;
        self.setPointer(null) catch |failure| self.report(failure);
        self.cancelDrag();
        self.cancelComposition();
        try self.finishPointer();
        try self.keyboard.releaseTerminal();
        if (self.tab_count == 0 or !self.focused or (self.palette != null or self.settings_editor != null or self.pane().finder != null)) return;
        const owner = self.pane().owner orelse return;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .out } });
    }
    fn gainKeyboard(self: *App) !void {
        self.cancelComposition();
        if (self.tab_count == 0 or !self.focused or (self.palette != null or self.settings_editor != null or self.pane().finder != null)) return;
        const owner = self.pane().owner orelse return;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .in } });
    }
    fn syncVisible(self: *App) void {
        for (self.tabs[0..self.tab_count], 0..) |maybe, index| {
            const t = maybe.?;
            for (t.panes, 0..) |maybe_p, slot| if (maybe_p) |p| {
                const visible = index == self.active and (!t.tree.zoomed or slot == t.tree.active);
                if (!visible) p.canvas.invalidateContent();
                if (p.owner) |owner| owner.setVisible(visible);
            };
        }
    }
    fn selectTab(self: *App, index: u8) !void {
        if (index >= self.tab_count or index == self.active) return;
        try self.loseKeyboard();
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
        if (self.settings_editor != null) self.settings_editor = null;
        if (self.palette) |current| {
            if (current.profile == profile) {
                self.palette = null;
                try self.gainKeyboard();
                return;
            }
        }
        try self.loseKeyboard();
        if (profile) {
            if (self.discovered) |catalogue| catalogue.destroy(allocator);
            self.discovered = null;
            if (self.configuration.value.discover_shells or self.configuration.value.discover_ssh_hosts)
                self.discovered = discovery.Catalogue.create(allocator, self.init.io, self.init.environ_map, self.configuration.value) catch |failure| blk: {
                    self.report(failure);
                    break :blk null;
                };
        }
        self.palette = .{ .profile = profile };
    }
    fn recover(self: *App) !void {
        const previous = self.pane();
        const status = previous.snapshot();
        if (previous.owner != null and status.failure == null and !status.closed) {
            if (previous.font_failure != null or previous.graphics_failure != null)
                try self.configureFont(previous, previous.font_size, false);
            try previous.submit(.retry_render);
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
            .split_vertical, .split_horizontal => panes < layout.pane_limit,
            .toggle_pane_zoom, .next_pane, .previous_pane, .balance_panes => panes > 1,
            .next_tab, .previous_tab => self.tab_count > 1,
            .move_tab_left => self.active > 0,
            .move_tab_right => self.active + 1 < self.tab_count,
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
        if (self.settings_editor != null and !(target == .action and target.action == .open_settings)) {
            self.settings_editor = null;
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
                .new_window => try self.newWindow(),
                .split_vertical => try self.split(.horizontal),
                .split_horizontal => try self.split(.vertical),
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
    fn surfaceFor(self: *App, value: *Pane) ?instance.render.terminal.Size {
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
        const geometry = owner.reconfigure(try self.fonts.config(self.init.io, pixels), if (resize) self.surfaceFor(value) else null) catch |failure| {
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
    fn uiPalette(self: *const App) error{ InvalidTheme, InvalidColor }!appearance.Palette {
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
                if ((paths_changed or size != p.font_size) and status.failure == null and !status.closed) {
                    const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(size)) * self.scale));
                    // Stage presentation with the canonical grid unchanged. A failed save must
                    // not reset history through a temporary column change.
                    change.geometry = try owner.reconfigure(try fonts.config(self.init.io, pixels), null);
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
            const presentation = self.fonts.config(self.init.io, pixels) catch |failure| {
                p.font_failure = failure;
                continue;
            };
            const geometry = owner.reconfigure(presentation, null) catch |failure| {
                p.font_failure = failure;
                continue;
            };
            p.cell_size = geometry.cell_size;
            p.rows = geometry.rows;
            p.columns = geometry.columns;
        }
    }
    fn toggleSettings(self: *App) !void {
        if (self.settings_editor != null) {
            self.settings_editor = null;
            try self.gainKeyboard();
            return;
        }
        try self.loseKeyboard();
        self.palette = null;
        self.settings_editor = .{};
    }
    fn profileInUse(self: *App, index: u8) !bool {
        const id = (try self.configuration.profile(index)).id;
        for (self.tabs[0..self.tab_count]) |value| {
            const t = value.?;
            if (std.mem.eql(u8, t.recipe.value.id, id)) return true;
            for (t.panes) |maybe| if (maybe) |p| {
                if (std.mem.eql(u8, p.recipe.value.id, id)) return true;
            };
        }
        return false;
    }
    fn changeSetting(self: *App, target: settings.Target, text: []const u8) !void {
        if (target == .delete_profile and try self.profileInUse(target.delete_profile)) return error.ProfileInUse;
        var candidate = try settings.change(self.configuration, self.init.io, target, text);
        defer candidate.deinit();
        try self.applyConfiguration(&candidate);
        self.cancelComposition();
        self.settings_editor.?.cancel();
        self.setNotice("Saved");
    }
    fn activateSetting(self: *App, row: settings.Row) !void {
        const editor = &self.settings_editor.?;
        if (editor.search) {
            editor.search = false;
            editor.query_len = 0;
            editor.page = row.page;
            editor.profile = switch (row.target) {
                .profile => |field| field.index,
                .environment => |field| field.profile,
                .clone_profile, .set_default, .delete_profile, .add_environment => |index| index,
                .delete_environment => |field| field.profile,
                else => editor.profile,
            };
            editor.list = .{};
            editor.content_focus = true;
            var all: [settings.row_limit]settings.Row = undefined;
            var shown: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.configuration, &all);
            const visible = editor.indices(all[0..count], &shown);
            for (shown[0..visible], 0..) |index, number| {
                if (std.meta.eql(all[index].target, row.target)) {
                    editor.list.selected = number;
                    break;
                }
            }
            self.cancelComposition();
            return;
        }
        if (row.target == .information) return;
        if (row.target == .set_default and !editor.search) {
            editor.profile = row.target.set_default;
            editor.page = .profiles;
            editor.list = .{};
            editor.content_focus = true;
            return;
        }
        if (row.target == .font_family) {
            self.cancelComposition();
            self.chooser = try font_chooser.Chooser.create(allocator, self.init.io, self.configuration, self.fonts.paths[0]);
            return;
        }
        if (row.target == .delete_profile) {
            if (try self.profileInUse(row.target.delete_profile)) return error.ProfileInUse;
            if (self.settings_editor.?.delete_pending != row.target.delete_profile) {
                self.settings_editor.?.delete_pending = row.target.delete_profile;
                self.setNotice("Press Enter again to delete this profile");
                return;
            }
        }
        self.cancelComposition();
        if (row.editable()) {
            try self.settings_editor.?.begin(row, self.configuration);
            if (row.target == .binding) {
                self.settings_editor.?.recording = true;
                self.setNotice("Press a shortcut — Esc cancels");
            }
        } else try self.changeSetting(row.target, "");
    }
    fn chooserApply(self: *App, persist: bool) !void {
        const chooser = self.chooser.?;
        var candidate = try chooser.candidate(allocator, self.init.io);
        defer candidate.deinit();
        if (persist) try self.applyConfiguration(&candidate) else try self.updateConfiguration(&candidate, .cwd(), "", false);
        chooser.previewed = !persist;
        self.cancelComposition();
        if (persist) {
            chooser.destroy(allocator);
            self.chooser = null;
            self.setNotice("Font family saved");
        } else self.setNotice("Font preview — Enter saves; Esc restores");
    }
    fn chooserRestore(self: *App) !void {
        const chooser = self.chooser.?;
        if (chooser.previewed) {
            var candidate = try config.Config.fromValue(allocator, self.init.io, chooser.original.value);
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
        const box = self.settingsRect();
        return .{ .x = box.x + 12, .y = box.y + 44, .width = @max(1, box.width - 24), .height = 32 };
    }
    fn chooserList(self: *const App) layout.Rect {
        const box = self.settingsRect();
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
        const box = self.settingsRect();
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
        const box = self.settingsRect();
        const list = self.chooserList();
        const field = self.chooserField();
        try fill(self.renderer, box, colors.title);
        try outline(self.renderer, box, colors.border);
        try self.drawText(if (chooser.truncated) "Installed terminal fonts — first 256 families" else "Installed terminal fonts", box.x + 12, box.y + 12);
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
            try self.clippedText(try chooser.regularPath(), .{ .x = sample.x, .y = sample.y + 32, .width = sample.width, .height = 30 }, sample.x);
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
        for ([_][]const u8{ "Preview", "Save · Enter", "Cancel · Esc" }, 0..) |label, index| {
            const button: layout.Rect = .{ .x = box.x + 12 + @as(f32, @floatFromInt(index)) * button_width, .y = box.y + box.height - 38, .width = @max(1, button_width - 4), .height = 30 };
            try fill(self.renderer, button, colors.idle);
            try outline(self.renderer, button, if (chooser.button == @as(u8, @intCast(index))) colors.accent else colors.border);
            try self.clippedText(label, button, button.x + 6);
        }
    }
    fn textKey(self: *App, edit: *widgets.Text, buffer: []u8, len: *usize, event_value: c.SDL_KeyboardEvent) !bool {
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
    fn drawField(self: *App, rect: layout.Rect, edit: *widgets.Text, text: []const u8, placeholder: []const u8, active: bool) !void {
        const colors = try self.uiPalette();
        try fill(self.renderer, rect, colors.panel);
        try outline(self.renderer, rect, if (active) colors.accent else colors.border);
        const inner: layout.Rect = .{ .x = rect.x + 7, .y = rect.y + 3, .width = @max(1, rect.width - 14), .height = @max(1, rect.height - 6) };
        const caret = try self.textWidth(text[0..edit.cursor]);
        const scroll = edit.reveal(caret, try self.textWidth(text), inner.width - 2);
        try setClip(self.renderer, inner);
        defer clearClip(self.renderer);
        const origin = inner.x - scroll;
        const ink_y = rect.y + 6;
        try self.drawTextTint(self.ui_fonts.faces[0], if (text.len == 0) placeholder else text, origin, ink_y, if (text.len == 0) colors.muted else colors.text);
        if (active) if (edit.selected()) |range| {
            const left = origin + try self.textWidth(text[0..range.start]);
            const right = origin + try self.textWidth(text[0..range.end]);
            const highlight = widgets.intersection(inner, .{ .x = left, .y = inner.y, .width = right - left, .height = inner.height });
            if (highlight) |area| {
                const selected = appearance.selection(colors);
                try fill(self.renderer, area, selected.background);
                try setClip(self.renderer, area);
                try self.drawTextTint(self.ui_fonts.faces[0], text, origin, ink_y, selected.foreground);
                try setClip(self.renderer, inner);
            }
        };
        if (active and self.focused and self.preedit.len == 0) try fill(self.renderer, .{ .x = inner.x + caret - scroll, .y = rect.y + 6, .width = 1, .height = @min(18, inner.height) }, colors.accent);
    }

    fn drawListScroll(self: *App, rows: widgets.Rows, first: usize, count: usize) !void {
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
    fn drawListRow(self: *App, rect: layout.Rect, selected: bool, hovered: bool, focused: bool) !void {
        const colors = try self.uiPalette();
        if (selected or hovered) {
            const base = if (selected) colors.active else colors.idle;
            try fill(self.renderer, rect, if (hovered) appearance.hover(base) else base);
        }
        if (selected and focused) try fill(self.renderer, .{ .x = rect.x, .y = rect.y + 4, .width = 2, .height = @max(1, rect.height - 8) }, colors.accent);
    }
    fn settingsKey(self: *App, event_value: c.SDL_KeyboardEvent) !void {
        const e = &self.settings_editor.?;
        const key = event_value.key;
        const mods = input.semanticModifiers(event_value.mod);
        if (e.recording) {
            if (key == c.SDLK_ESCAPE) {
                self.cancelComposition();
                e.cancel();
                return;
            }
            if (key == c.SDLK_LCTRL or key == c.SDLK_RCTRL or key == c.SDLK_LSHIFT or key == c.SDLK_RSHIFT or
                key == c.SDLK_LALT or key == c.SDLK_RALT or key == c.SDLK_LGUI or key == c.SDLK_RGUI) return;
            self.keyboard.suppress_text = true;
            var buffer: [64]u8 = undefined;
            const shortcut = try keybindings.format(key, event_value.mod, &buffer);
            @memcpy(e.buffer[0..shortcut.len], shortcut);
            e.len = shortcut.len;
            e.edit = .{ .cursor = shortcut.len };
            e.recording = false;
            self.setNotice("Shortcut captured — Enter saves; Esc cancels");
            return;
        }
        if (e.editing) |target| {
            if (key == c.SDLK_ESCAPE) {
                self.cancelComposition();
                e.cancel();
            } else if (key == c.SDLK_TAB) {
                const position: u8 = if (e.button) |button| button + 1 else 0;
                const next = (position + @as(u8, if (mods.shift) 2 else 1)) % 3;
                e.button = if (next == 0) null else next - 1;
            } else if (key == c.SDLK_RETURN) {
                if (e.button == 1) e.cancel() else try self.changeSetting(target, e.buffer[0..e.len]);
            } else if (e.button == null) {
                const row: settings.Row = .{ .page = e.page, .label = "", .target = target };
                if (row.choice()) {
                    if (key == c.SDLK_LEFT or key == c.SDLK_UP or key == c.SDLK_RIGHT or key == c.SDLK_DOWN or key == c.SDLK_SPACE) try e.cycle(self.configuration, if (key == c.SDLK_LEFT or key == c.SDLK_UP) -1 else 1);
                } else if (try self.textKey(&e.edit, e.buffer[0 .. e.buffer.len - 1], &e.len, event_value)) self.cancelComposition();
            }
            return;
        }
        if (mods.control and key == c.SDLK_F) {
            self.cancelComposition();
            e.search = true;
            e.content_focus = false;
            e.query_len = 0;
            e.query_edit = .{};
            e.list = .{};
            e.delete_pending = null;
            return;
        }
        if (key == c.SDLK_ESCAPE) {
            self.cancelComposition();
            if (e.search) {
                e.search = false;
                e.query_len = 0;
                e.query_edit = .{};
                e.list = .{};
                e.content_focus = true;
            } else if (e.page == .profiles) {
                e.page = .defaults;
                e.list = .{ .selected = e.profile };
            } else if (e.content_focus) {
                e.content_focus = false;
            } else try self.toggleSettings();
            return;
        }
        if (e.search and (key == c.SDLK_LEFT or key == c.SDLK_RIGHT or key == c.SDLK_HOME or key == c.SDLK_END or key == c.SDLK_DELETE or key == c.SDLK_BACKSPACE or (mods.control and (key == c.SDLK_A or key == c.SDLK_C or key == c.SDLK_X or key == c.SDLK_V)))) {
            if (try self.textKey(&e.query_edit, &e.query, &e.query_len, event_value)) e.list = .{};
            return;
        }
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        if (key == c.SDLK_TAB) {
            e.content_focus = !e.content_focus;
            return;
        }
        if (!e.search and !e.content_focus) {
            if (key == c.SDLK_UP or key == c.SDLK_DOWN) {
                const page_number = @as(i16, @backingInt(e.page)) + @as(i16, if (key == c.SDLK_UP) -1 else 1);
                e.page = @fromBackingInt(@intCast(std.math.clamp(page_number, 0, settings.titles.len - 1)));
                e.list = .{};
                e.delete_pending = null;
            } else if (key == c.SDLK_RETURN or key == c.SDLK_RIGHT) e.content_focus = true;
            return;
        }
        if (visible == 0) return;
        e.list.selected = @min(e.list.selected, visible - 1);
        const row = all[indices[e.list.selected]];
        switch (key) {
            c.SDLK_UP, c.SDLK_PAGEUP => {
                e.list.selected -|= if (key == c.SDLK_UP) 1 else self.settingsVisible();
                e.delete_pending = null;
            },
            c.SDLK_DOWN, c.SDLK_PAGEDOWN => {
                e.list.selected = @min(visible - 1, e.list.selected + (if (key == c.SDLK_DOWN) @as(usize, 1) else self.settingsVisible()));
                e.delete_pending = null;
            },
            c.SDLK_RETURN => try self.activateSetting(row),
            c.SDLK_BACKSPACE, c.SDLK_DELETE => if (row.target == .binding or row.target == .font) {
                try e.begin(row, self.configuration);
                e.edit.selectAll(e.len);
                try e.append(if (key == c.SDLK_BACKSPACE and row.target == .binding) keybindings.definitions[row.target.binding].default_shortcut else "");
            },
            c.SDLK_LEFT, c.SDLK_RIGHT => {
                if (mods.alt and row.target == .environment) {
                    const field = row.target.environment;
                    try self.changeSetting(.{ .move_environment = .{ .profile = field.profile, .index = field.index, .delta = if (key == c.SDLK_LEFT) -1 else 1 } }, "");
                } else if (row.choice()) {
                    try e.begin(row, self.configuration);
                    try e.cycle(self.configuration, if (key == c.SDLK_LEFT) -1 else 1);
                } else if (key == c.SDLK_LEFT) e.content_focus = false;
            },
            else => {},
        }
        if (!e.search and e.page == .defaults) e.profile = @intCast(e.list.selected);
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
        return @as(usize, self.configuration.profileCount()) + (if (self.discovered) |catalogue| @as(usize, catalogue.count) else 0);
    }
    fn menuProfile(self: *const App, index: usize) !config.Profile {
        if (index < self.configuration.profileCount()) return self.configuration.profile(@intCast(index));
        const catalogue = self.discovered orelse return error.InvalidDefaultProfile;
        const offset = index - self.configuration.profileCount();
        if (offset >= catalogue.count) return error.InvalidDefaultProfile;
        return catalogue.entries[offset].recipe;
    }
    fn choosePalette(self: *App, index: usize) !void {
        if (!self.palette.?.profile) return self.dispatch(keybindings.definitions[index].target);
        if (index >= self.menuProfileCount()) {
            self.palette = null;
            if (index == self.menuProfileCount()) return self.openPalette(false);
            return self.toggleSettings();
        }
        const recipe = try self.menuProfile(index);
        // Keep the overlay and original input owner intact if construction cannot commit.
        try self.createTab(recipe, null);
        self.palette = null;
        try self.gainKeyboard();
    }
    fn paletteKey(self: *App, key: c.SDL_Keycode, mods: c.SDL_Keymod) !void {
        var matches: [palette_limit]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, self.discovered, &matches);
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
            p.reveal(try p.indices(self.configuration, self.discovered, &matches), self.paletteRows());
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
        if (try self.chromeEvent(value)) return;
        self.input_timestamp = value.common.timestamp;
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
                    if (self.chooser != null) break :blk null;
                    if (self.settings_editor) |e| {
                        if (e.editing != null or !(target == .action and target.action == .open_settings)) break :blk null;
                    }
                    break :blk target;
                } else null;
                const route = try self.keyboard.route(value.key, press, self.pane().owner, command, self.palette != null or self.settings_editor != null or self.pane().finder != null);
                switch (route) {
                    .handled => {},
                    .command => |target| try self.dispatch(target),
                    .overlay => if (self.chooser != null) try self.chooserKey(value.key) else if (self.settings_editor != null) try self.settingsKey(value.key) else if (self.palette != null) try self.paletteKey(value.key.key, value.key.mod) else try self.findKey(value.key),
                }
            },
            c.SDL_EVENT_TEXT_EDITING => {
                if (!self.focused or !self.preedit.accepts(value.edit.timestamp)) return;
                try self.preedit.set(std.mem.span(value.edit.text), value.edit.start, value.edit.length);
            },
            c.SDL_EVENT_TEXT_INPUT => {
                if (!self.focused or !self.preedit.accepts(value.text.timestamp)) return;
                self.preedit.clear();
                const text = std.mem.span(value.text.text);
                if (try self.keyboard.commitText(text)) return;
                if (self.chooser) |chooser| {
                    try chooser.append(text);
                } else if (self.settings_editor) |*e| {
                    if (!e.recording) try e.append(text);
                } else if (self.palette) |*p| {
                    try p.append(text);
                } else if (self.pane().finder != null) try self.findAppend(text) else try self.pane().submit(.{ .input = .{ .bytes = text } });
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (mouseButton(value.button.button)) |button|
                try self.pointerDown(value.button.x, value.button.y, button, input.semanticModifiers(c.SDL_GetModState()), value.button.clicks),
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button = mouseButton(value.button.button) orelse return;
                if (button == .left and self.color_drag != null) {
                    const channel = self.color_drag.?;
                    self.color_drag = null;
                    try self.colorPoint(channel, value.button.x);
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
                if (self.color_drag) |channel| {
                    try self.colorPoint(channel, value.motion.x);
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
                } else if (self.settings_editor == null) {
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
            c.SDL_EVENT_MOUSE_WHEEL => try self.pointerWheel(value.wheel),
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
    fn pointerDown(self: *App, x: f32, y: f32, button: instance.MouseButton, mods: instance.InputModifier, clicks: u8) !void {
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
            if (button == .left) try self.settingsClick(x, y, clicks);
            return;
        }
        if (self.palette != null) {
            if (button != .left) return;
            var matches: [palette_limit]usize = undefined;
            const count = try self.palette.?.indices(self.configuration, self.discovered, &matches);
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
            for (0..self.tab_count) |number| {
                const index: u8 = @intCast(number);
                const rect = self.headerTabs(self.width).tab(index);
                if (!rect.contains(x, y)) continue;
                try self.selectTab(index);
                if (if (self.headerTabs(self.width).close(index)) |close| close.contains(x, y) else false) {
                    try self.closeTab();
                    self.consume_left_release = true;
                } else self.drag = .{ .tab = chrome.Drag.begin(rect, x) };
                return;
            }
            if (self.headerTabs(self.width).plus().contains(x, y)) {
                try self.createTab(try self.startup(), null);
            } else if (self.headerTabs(self.width).profiles().contains(x, y)) {
                try self.openPalette(true);
            } else if (chrome.settings(self.width).contains(x, y)) {
                try self.toggleSettings();
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
            if (p.finder != null and findField(paneContent(place.rect)).contains(x, y)) {
                if (button == .left) self.consume_left_release = true;
                return;
            }
            const frame = p.canvas.frame() orelse return;
            const content = terminalPlacement(paneContent(place.rect), frame.surface, self.scale);
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
                if (kind == .start) {
                    self.selecting = .{ .pane = p, .x = x, .y = y };
                    self.selectionEdge();
                    self.selection_tick = c.SDL_GetTicksNS();
                } else self.consume_left_release = true;
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
        if (data == null or self.palette != null or self.settings_editor != null or self.pane().finder != null) return;
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
    fn drawScrollbar(self: *App, p: *Pane, rect: c.SDL_FRect, frame: instance.PublishedFrame) !void {
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
            const rect = terminalPlacement(paneContent(place.rect), frame.surface, self.scale);
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
            const rect = terminalPlacement(paneContent(place.rect), frame.surface, self.scale);
            return pointer.locate(.{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, self.scale, frame.cell_size, frame.surface, x, y, captured);
        };
        return null;
    }
    // SDL automatically captures held button gestures; this state binds their semantic owner.
    fn pointerPress(self: *App, p: *Pane, point: pointer.Location, button: instance.MouseButton, mods: instance.InputModifier) !void {
        const bit = pointer.buttonBit(button);
        const before: u8 = if (self.capture) |held| held.buttons else 0;
        if (before & bit != 0) return;
        const after = before | bit;
        try p.submit(.{ .input = point.event(.press, button, mods, after) });
        self.capture = .{ .pane = p, .buttons = after, .last = point };
    }
    fn pointerRelease(self: *App, button: instance.MouseButton, x: f32, y: f32, mods: instance.InputModifier) !void {
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
        for ([_]instance.MouseButton{ .left, .middle, .right }) |button|
            try self.pointerRelease(button, -std.math.inf(f32), -std.math.inf(f32), .{});
    }
    fn pointerWheel(self: *App, wheel: c.SDL_MouseWheelEvent) !void {
        if (self.chooser) |chooser| {
            if (std.math.isFinite(wheel.y)) chooser.list.scroll(@intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256)), chooser.result_count, self.chooserVisible());
            return;
        }
        if (self.settings_editor) |*editor| {
            if (!std.math.isFinite(wheel.y) or editor.editing != null) return;
            var rows: [settings.row_limit]settings.Row = undefined;
            var filtered: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.configuration, &rows);
            const visible = editor.indices(rows[0..count], &filtered);
            const offset: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
            editor.list.scroll(offset, visible, self.settingsVisible());
            editor.content_focus = true;
            return;
        }
        if (self.palette) |*palette| {
            if (!std.math.isFinite(wheel.y)) return;
            var matches: [palette_limit]usize = undefined;
            const count = try palette.indices(self.configuration, self.discovered, &matches);
            const delta: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
            palette.scroll(delta, count, self.paletteRows());
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
                const button: instance.MouseButton = if (steps > 0) .wheel_up else .wheel_down;
                for (0..@abs(steps)) |_| try p.submit(.{ .input = point.event(.wheel, button, mods, if (self.capture) |held| if (held.pane == p) held.buttons else 0 else 0) });
            },
            .alternate => {
                const key: instance.Key = .{ .named = if (steps > 0) .up else .down };
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
        self.palette.?.reveal(count, self.paletteRows());
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
        const count = try self.palette.?.indices(self.configuration, self.discovered, &matches);
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
        const count = try self.palette.?.indices(self.configuration, self.discovered, &matches);
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
        if (count == 0) try self.clippedTextColor("No matching entries", self.paletteRow(0), box.x + 18, colors.muted);
        const shown = @min(count - start, self.paletteRows());
        for (matches[start .. start + shown], start..) |index, number| {
            const row = self.paletteRow(number - start);
            try self.drawListRow(row, number == self.palette.?.list.selected, self.palette.?.list.hovered == number, true);
            if (profiles) {
                if (index < self.menuProfileCount()) {
                    const recipe = try self.menuProfile(index);
                    const default = index == try self.configuration.defaultProfile();
                    try self.clippedText(recipe.name, .{ .x = row.x + 10, .y = row.y, .width = @max(1, row.width - (if (default) @as(f32, 90) else 20)), .height = 23 }, row.x + 10);
                    var detail_buffer: [640]u8 = undefined;
                    const kind = if (index < self.configuration.profileCount()) "Saved" else switch (self.discovered.?.entries[index - self.configuration.profileCount()].kind) {
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
    fn settingsRect(self: *const App) layout.Rect {
        const width = @min(760, @max(1, self.width - 24));
        return .{ .x = self.width - width - 12, .y = 58, .width = width, .height = @max(1, self.height - 76) };
    }
    fn settingsBody(self: *const App) layout.Rect {
        const box = self.settingsRect();
        const sidebar = @min(178, box.width / 3);
        return .{ .x = box.x + sidebar + 16, .y = box.y + 92, .width = @max(1, box.width - sidebar - 32), .height = @max(1, box.height - 198) };
    }
    fn settingsRows(self: *const App) widgets.Rows {
        var body = self.settingsBody();
        body.width = @max(1, body.width - 8);
        return .{ .rect = body, .stride = 48, .gap = 4 };
    }
    fn settingsField(self: *const App) layout.Rect {
        const box = self.settingsRect();
        const body = self.settingsBody();
        if (self.settings_editor.?.editing != null) {
            const e = self.settings_editor.?;
            const rect = self.settingsRows().row(e.list.selected -| e.list.first);
            return .{ .x = rect.x + rect.width * 0.46, .y = rect.y + 5, .width = @max(1, rect.width * 0.54 - 6), .height = rect.height - 10 };
        }
        return .{ .x = body.x, .y = box.y + 48, .width = body.width, .height = 32 };
    }
    fn settingsVisible(self: *const App) usize {
        return self.settingsRows().visible();
    }
    fn settingsStart(self: *App, count: usize) usize {
        self.settings_editor.?.list.reveal(count, self.settingsVisible());
        return self.settings_editor.?.list.first;
    }
    fn settingsToolbarCount(self: *const App) usize {
        return if (self.settings_editor.?.editing != null) 2 else 3;
    }
    fn settingsToolbarButton(self: *const App, number: usize) layout.Rect {
        const box = self.settingsRect();
        const body = self.settingsBody();
        const count: f32 = @floatFromInt(self.settingsToolbarCount());
        const width = @max(1, (body.width - (count - 1) * 6) / count);
        return .{ .x = body.x + @as(f32, @floatFromInt(number)) * (width + 6), .y = box.y + 48, .width = width, .height = 32 };
    }
    fn settingsToolbarAction(self: *App, number: usize) !void {
        const e = &self.settings_editor.?;
        if (e.editing) |target| {
            if (number == 0) try self.changeSetting(target, e.buffer[0..e.len]) else {
                self.cancelComposition();
                e.cancel();
            }
            return;
        }
        if (e.page == .defaults) {
            switch (number) {
                0 => {
                    try self.changeSetting(.add_profile, "");
                    e.profile = self.configuration.profileCount() - 1;
                    e.page = .profiles;
                    e.list = .{};
                    try e.begin(.{ .page = .profiles, .label = "Name", .target = .{ .profile = .{ .index = e.profile, .field = .name } } }, self.configuration);
                },
                1 => {
                    try self.changeSetting(.{ .clone_profile = e.profile }, "");
                    e.profile = self.configuration.profileCount() - 1;
                    e.page = .profiles;
                    e.list = .{};
                },
                2 => {
                    try self.activateSetting(.{ .page = .profiles, .label = "Delete profile", .target = .{ .delete_profile = e.profile } });
                    e.profile = @min(e.profile, self.configuration.profileCount() - 1);
                },
                else => {},
            }
        } else if (e.page == .profiles) switch (number) {
            0 => {
                e.page = .defaults;
                e.list.selected = e.profile;
            },
            1 => {
                try self.changeSetting(.{ .clone_profile = e.profile }, "");
                e.profile = self.configuration.profileCount() - 1;
                e.list = .{};
            },
            2 => try self.changeSetting(.{ .set_default = e.profile }, ""),
            else => {},
        };
        e.content_focus = true;
    }
    fn colorBar(self: *const App, channel: usize) layout.Rect {
        const box = self.settingsRect();
        const body = self.settingsBody();
        return .{ .x = body.x + 24, .y = box.y + box.height - 100 + @as(f32, @floatFromInt(channel)) * 22, .width = @max(1, body.width - 120), .height = 18 };
    }
    fn colorReset(self: *const App) layout.Rect {
        const body = self.settingsBody();
        const bar = self.colorBar(0);
        return .{ .x = body.x + body.width - 82, .y = bar.y, .width = 78, .height = 62 };
    }
    fn editedColor(self: *App) !instance.Terminal.Rgb {
        const e = self.settings_editor.?;
        return color_config.parse(e.buffer[0..e.len]) catch (try self.settingRgb(.{ .page = e.page, .label = "", .target = e.editing.? })).?;
    }
    fn colorPoint(self: *App, channel: u8, x: f32) !void {
        const e = &self.settings_editor.?;
        const bar = self.colorBar(channel);
        var rgb = try self.editedColor();
        const value: u8 = @intFromFloat(@round(std.math.clamp((x - bar.x) / bar.width, 0, 1) * 255));
        switch (channel) {
            0 => rgb.r = value,
            1 => rgb.g = value,
            2 => rgb.b = value,
            else => return error.InvalidColorRole,
        }
        const text = try std.fmt.bufPrint(&e.buffer, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
        e.len = text.len;
        e.edit = .{ .kind = .color, .cursor = text.len };
        e.button = null;
    }
    fn drawColorEditor(self: *App) !void {
        const rgb = try self.editedColor();
        const colors = try self.uiPalette();
        for ([_]u8{ rgb.r, rgb.g, rgb.b }, [_][]const u8{ "R", "G", "B" }, 0..) |value, label, channel| {
            const bar = self.colorBar(channel);
            try self.clippedText(label, .{ .x = bar.x - 24, .y = bar.y - 4, .width = 24, .height = 24 }, bar.x - 24);
            for (0..64) |step| {
                var shade = rgb;
                const component: u8 = @intCast(step * 4);
                switch (channel) {
                    0 => shade.r = component,
                    1 => shade.g = component,
                    2 => shade.b = component,
                    else => return error.InvalidColorRole,
                }
                try fill(self.renderer, .{ .x = bar.x + @as(f32, @floatFromInt(step)) * bar.width / 64, .y = bar.y, .width = bar.width / 64 + 1, .height = bar.height }, .{ .r = shade.r, .g = shade.g, .b = shade.b, .a = 255 });
            }
            try outline(self.renderer, bar, colors.border);
            const thumb: layout.Rect = .{ .x = bar.x + @as(f32, @floatFromInt(value)) * bar.width / 255 - 2, .y = bar.y - 2, .width = 4, .height = bar.height + 4 };
            try fill(self.renderer, thumb, colors.text);
        }
        const reset = self.colorReset();
        try fill(self.renderer, reset, colors.idle);
        try outline(self.renderer, reset, colors.border);
        try self.clippedText("Preset", reset, reset.x + 8);
        const sample: layout.Rect = .{ .x = reset.x + 8, .y = reset.y + 30, .width = reset.width - 16, .height = 22 };
        try fill(self.renderer, sample, .{ .r = rgb.r, .g = rgb.g, .b = rgb.b, .a = 255 });
        try outline(self.renderer, sample, colors.border);
    }
    fn settingsClick(self: *App, x: f32, y: f32, clicks: u8) !void {
        const e = &self.settings_editor.?;
        const box = self.settingsRect();
        if (x >= box.x + box.width - 70 and y >= box.y and y < box.y + 40) return self.toggleSettings();
        if (e.editing != null) {
            for (0..self.settingsToolbarCount()) |number| if (self.settingsToolbarButton(number).contains(x, y)) return self.settingsToolbarAction(number);
            if (self.settingsField().contains(x, y)) e.button = null;
            if (e.edit.kind == .color) {
                for (0..3) |channel| if (self.colorBar(channel).contains(x, y)) {
                    self.color_drag = @intCast(channel);
                    return self.colorPoint(@intCast(channel), x);
                };
                if (self.colorReset().contains(x, y)) {
                    e.button = null;
                    e.len = 0;
                    e.edit = .{ .kind = .color };
                }
            }
            return;
        }
        if (!box.contains(x, y)) return;
        const body = self.settingsBody();
        if (x < body.x - 12 and y >= box.y + 52) {
            const page: usize = @intFromFloat(@floor((y - box.y - 52) / 34));
            if (page < settings.titles.len) {
                self.cancelComposition();
                e.page = @fromBackingInt(@intCast(page));
                e.content_focus = false;
                e.search = false;
                e.query_len = 0;
                e.list = .{};
                e.delete_pending = null;
            }
            return;
        }
        if (e.page == .defaults or e.page == .profiles or e.editing != null) {
            for (0..self.settingsToolbarCount()) |number| {
                if (self.settingsToolbarButton(number).contains(x, y)) return self.settingsToolbarAction(number);
            }
        }
        if (e.page == .defaults and y >= box.y + box.height - 96 and x >= body.x and x < body.x + 136) {
            return self.changeSetting(.{ .set_default = e.profile }, "");
        }
        const field = self.settingsField();
        if (field.contains(x, y)) {
            e.search = true;
            e.query_edit = .{ .cursor = e.query_len };
            e.list = .{};
            self.cancelComposition();
            return;
        }
        if (!body.contains(x, y)) return;
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        const row = self.settingsRows().hit(x, y) orelse return;
        const chosen = row + self.settingsStart(visible);
        if (chosen >= visible) return;
        if (e.list.selected != chosen) e.delete_pending = null;
        e.list.selected = chosen;
        if (all[indices[chosen]].target == .set_default) e.profile = all[indices[chosen]].target.set_default;
        e.content_focus = true;
        if (clicks >= 2) try self.activateSetting(all[indices[chosen]]);
    }

    fn clippedText(self: *App, text: []const u8, rect: layout.Rect, x: f32) !void {
        return self.clippedTextColor(text, rect, x, (try self.uiPalette()).text);
    }
    fn clippedTextColor(self: *App, text: []const u8, rect: layout.Rect, x: f32, color: c.SDL_Color) !void {
        try setClip(self.renderer, rect);
        defer clearClip(self.renderer);
        try self.drawTextTint(self.ui_fonts.faces[0], text, x, rect.y + 6, color);
    }
    fn settingRgb(self: *const App, row: settings.Row) !?instance.Terminal.Rgb {
        switch (row.target) {
            .app_color => |index| {
                const resolved = try self.uiPalette();
                inline for (@typeInfo(appearance.Palette).@"struct".field_names, 0..) |field, i| if (index == i) {
                    const rgb = @field(resolved, field);
                    return .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
                };
                return error.InvalidColorRole;
            },
            .terminal_color => |index| {
                const resolved = try self.configuration.value.terminal_colors.resolve(self.configuration.value.terminal_theme);
                return switch (index) {
                    0 => resolved.foreground,
                    1 => resolved.background,
                    2 => resolved.cursor orelse resolved.foreground,
                    3...18 => resolved.palette[index - 3],
                    19 => resolved.cursor_text orelse resolved.background,
                    else => error.InvalidColorRole,
                };
            },
            else => return null,
        }
    }
    fn drawSettings(self: *App) !void {
        const e = &self.settings_editor.?;
        const colors = try self.uiPalette();
        const box = self.settingsRect();
        const body = self.settingsBody();
        e.profile = @min(e.profile, self.configuration.profileCount() - 1);
        try fill(self.renderer, box, colors.title);
        try outline(self.renderer, box, colors.border);
        try fill(self.renderer, .{ .x = box.x, .y = box.y, .width = body.x - box.x - 16, .height = box.height }, colors.idle);
        try self.drawText("Settings", box.x + 18, box.y + 18);
        try self.drawText(if (e.search) "Search settings" else settings.titles[@backingInt(e.page)], body.x, box.y + 18);
        try self.drawText("Close", box.x + box.width - 60, box.y + 12);
        for (settings.titles, 0..) |title, index| {
            const row: layout.Rect = .{ .x = box.x + 8, .y = box.y + 52 + @as(f32, @floatFromInt(index)) * 34, .width = @max(1, body.x - box.x - 24), .height = 32 };
            if (!e.search and @backingInt(e.page) == index) {
                try fill(self.renderer, row, colors.active);
                try fill(self.renderer, .{ .x = row.x, .y = row.y + 4, .width = 2, .height = row.height - 8 }, colors.accent);
            }
            try self.clippedText(title, row, row.x + 6);
        }
        if (!e.search and (e.page == .defaults or e.page == .profiles or e.editing != null)) {
            const labels: [3][]const u8 = if (e.editing != null) .{ "Save", "Cancel", "" } else if (e.page == .defaults) .{ "New profile", "Duplicate", if (e.delete_pending != null) "Delete?" else "Delete" } else .{ "< Profiles", "Duplicate", "Set default" };
            for (labels[0..self.settingsToolbarCount()], 0..) |label, number| {
                const button = self.settingsToolbarButton(number);
                try fill(self.renderer, button, colors.idle);
                try outline(self.renderer, button, if (e.editing != null and e.button == @as(u8, @intCast(number))) colors.accent else colors.border);
                try self.clippedText(label, button, button.x + 8);
            }
        } else {
            const field = self.settingsField();
            if (e.search) try self.drawField(field, &e.query_edit, e.query[0..e.query_len], "Search settings", true) else try self.clippedTextColor("Enter or double-click to edit · Ctrl+F search", field, field.x + 6, colors.muted);
        }
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        e.list.selected = @min(e.list.selected, visible -| 1);
        const start = self.settingsStart(visible);
        for (indices[start..@min(visible, start + self.settingsVisible())], start..) |index, number| {
            const row = all[index];
            const rect = self.settingsRows().row(number - start);
            try self.drawListRow(rect, number == e.list.selected, e.list.hovered == number, e.content_focus);
            try outline(self.renderer, rect, colors.border);
            var label: [512]u8 = undefined;
            const name = if (row.scope.len == 0 or (!e.search and e.page != .colors)) row.label else try std.fmt.bufPrint(&label, "{s} / {s}", .{ row.scope, row.label });
            var value: [4096]u8 = undefined;
            const raw_contents = if (number == e.list.selected and e.editing != null) (if (e.recording) "Press a shortcut — Esc cancels" else e.buffer[0..e.len]) else try row.text(self.configuration, &value);
            const contents = if (raw_contents.len != 0 or (number == e.list.selected and e.editing != null)) raw_contents else switch (row.target) {
                .binding => "Unbound",
                .app_color, .terminal_color => "Preset",
                .font => "Inherited",
                .profile => |field| switch (field.field) {
                    .command => "Interactive shell",
                    .shell, .cwd, .font_pixels => "Inherited",
                    .arguments => "Shell mode",
                    .name => "",
                },
                else => "",
            };
            const left: layout.Rect = .{ .x = rect.x + 6, .y = rect.y, .width = @max(1, rect.width * 0.46 - 12), .height = rect.height };
            const right: layout.Rect = .{ .x = rect.x + rect.width * 0.46, .y = rect.y, .width = @max(1, rect.width * 0.54 - 6), .height = rect.height };
            if (number == e.list.selected and e.editing != null and !e.recording) {
                try self.clippedText(name, left, left.x);
                if (row.choice()) {
                    const display = if (row.target == .theme or row.target == .terminal_theme) theme_presets.label(contents) else contents;
                    try fill(self.renderer, self.settingsField(), colors.panel);
                    try outline(self.renderer, self.settingsField(), colors.accent);
                    try self.clippedText(display, self.settingsField(), self.settingsField().x + 7);
                } else try self.drawField(self.settingsField(), &e.edit, contents, if (e.edit.kind == .color) "#RRGGBB; blank = preset" else "", e.button == null);
            } else if (row.target == .set_default and !e.search) {
                try self.clippedText(row.label, .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - 94), .height = rect.height }, rect.x + 8);
                try self.clippedText("Edit", .{ .x = rect.x + rect.width - 74, .y = rect.y, .width = 70, .height = rect.height }, rect.x + rect.width - 66);
            } else {
                try self.clippedText(name, left, left.x);
                const rgb = try self.settingRgb(row);
                var value_rect = right;
                if (rgb) |swatch_color| {
                    value_rect.width = @max(1, right.width - 30);
                    const swatch: layout.Rect = .{ .x = rect.x + rect.width - 25, .y = rect.y + 12, .width = 16, .height = @min(20, rect.height - 16) };
                    try fill(self.renderer, swatch, .{ .r = swatch_color.r, .g = swatch_color.g, .b = swatch_color.b, .a = 255 });
                    try outline(self.renderer, swatch, colors.border);
                }
                try self.clippedTextColor(contents, value_rect, right.x, if (row.target == .information) colors.muted else colors.text);
            }
        }
        try self.drawListScroll(self.settingsRows(), start, visible);
        if (e.editing != null and e.edit.kind == .color) {
            try self.drawColorEditor();
        } else if (e.page == .colors) {
            const resolved = try self.configuration.value.terminal_colors.resolve(self.configuration.value.terminal_theme);
            const preview: layout.Rect = .{ .x = body.x, .y = box.y + box.height - 100, .width = body.width, .height = 32 };
            try fill(self.renderer, preview, .{ .r = resolved.background.r, .g = resolved.background.g, .b = resolved.background.b, .a = 255 });
            try self.clippedTextColor("Terminal  AaBb 0123", preview, preview.x + 8, .{ .r = resolved.foreground.r, .g = resolved.foreground.g, .b = resolved.foreground.b, .a = 255 });
            const width = body.width / 16;
            for (resolved.palette[0..16], 0..) |rgb, i| try fill(self.renderer, .{ .x = body.x + @as(f32, @floatFromInt(i)) * width, .y = preview.y + 38, .width = @max(1, width - 2), .height = 16 }, .{ .r = rgb.r, .g = rgb.g, .b = rgb.b, .a = 255 });
        }
        if (e.page == .defaults) {
            const button: layout.Rect = .{ .x = body.x, .y = box.y + box.height - 96, .width = 136, .height = 30 };
            try fill(self.renderer, button, colors.idle);
            try outline(self.renderer, button, colors.border);
            try self.clippedText(if (e.profile == try self.configuration.defaultProfile()) "Default" else "Set default", button, button.x + 8);
        }
        try self.clippedText(if (e.page == .profiles and e.profile == 0) "Read-only template · Duplicate to customize" else if (e.editing != null) (if ((settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice()) "←↑↓→ change · Enter saves · Esc cancels" else "Enter saves · Esc cancels · Tab: field / Save / Cancel") else "↑↓ choose · Enter edits · Tab focus · Esc back", .{ .x = body.x, .y = box.y + box.height - 36, .width = body.width, .height = 30 }, body.x);
    }
    fn drawText(self: *App, bytes: []const u8, x: f32, y: f32) !void {
        try self.drawTextFont(self.ui_fonts.faces[0], bytes, x, y);
    }
    fn drawTextFont(self: *App, font: *c.TTF_Font, bytes: []const u8, x: f32, y: f32) !void {
        return self.drawTextTint(font, bytes, x, y, (try self.uiPalette()).text);
    }
    fn drawTextTint(self: *App, font: *c.TTF_Font, bytes: []const u8, x: f32, y: f32, color: c.SDL_Color) !void {
        if (bytes.len == 0) return;
        const surface = c.TTF_RenderText_Blended(font, bytes.ptr, bytes.len, color) orelse return error.TTF;
        defer c.SDL_DestroySurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return error.SDL;
        defer c.SDL_DestroyTexture(texture);
        const rect: c.SDL_FRect = .{ .x = x, .y = y, .w = @as(f32, @floatFromInt(surface.*.w)) / self.scale, .h = @as(f32, @floatFromInt(surface.*.h)) / self.scale };
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
        if (self.chooser) |chooser| {
            clip = self.chooserField();
            x = clip.x + 7 + try self.textWidth(chooser.query[0..chooser.edit.cursor]) - chooser.edit.scroll;
            y = clip.y + 6;
        } else if (self.settings_editor) |e| {
            if ((e.editing == null and !e.search) or e.recording or (e.editing != null and (settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice()) or e.button != null) {
                if (!c.SDL_SetTextInputArea(self.window, null, 0)) return error.SDL;
                return;
            }
            clip = self.settingsField();
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
                clip = findField(paneContent(place.rect));
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
                const rect = terminalPlacement(paneContent(place.rect), frame.surface, self.scale);
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
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.configuration, &all);
            const shown = e.indices(all[0..count], &indices);
            const start = self.settingsStart(shown);
            e.list.hovered = if (self.settingsRows().hit(x, y)) |row| if (start + row < shown) start + row else null else null;
            return self.setPointer(if ((e.search or (e.editing != null and !(settings.Row{ .page = e.page, .label = "", .target = e.editing.? }).choice())) and self.settingsField().contains(x, y)) 2 else null);
        }
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
    fn drawTab(self: *App, index: u8, rect: layout.Rect) !void {
        const colors = try self.uiPalette();
        const value = self.tabs[index].?;
        const status = value.panes[value.tree.active].?.snapshot();
        try fill(self.renderer, rect, if (index == self.active) colors.active else colors.idle);
        if (index == self.active) try fill(self.renderer, .{ .x = rect.x, .y = rect.y + rect.height - 1, .width = rect.width, .height = 1 }, colors.accent);
        const target = self.headerHover();
        const close_width: f32 = if (self.headerTabs(self.width).close(index) != null) 30 else 0;
        if (target == .tab and target.tab == index) try fill(self.renderer, .{ .x = rect.x, .y = rect.y, .width = rect.width - close_width, .height = rect.height - 1 }, appearance.hover(if (index == self.active) colors.active else colors.idle));
        if (target == .tab_close and target.tab_close == index) try fill(self.renderer, .{ .x = rect.x + rect.width - close_width, .y = rect.y, .width = close_width, .height = rect.height - 1 }, appearance.hover(if (index == self.active) colors.active else colors.idle));
        try self.clippedText(status.title[0..status.title_len], .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - close_width - 12), .height = rect.height }, rect.x + 8);
        if (close_width != 0) try self.drawText("×", rect.x + rect.width - 18, rect.y + 6);
    }
    fn drawWindowControls(self: *App) !void {
        const colors = try self.uiPalette();
        for ([_]chrome.Button{ .minimize, .maximize, .close }) |button| {
            const rect = chrome.control(button, self.width);
            const target = self.headerHover();
            const hovered = target == .window and target.window == button;
            if (hovered) try fill(self.renderer, rect, appearance.hover(colors.title));
            const color = if (hovered) colors.text else colors.muted;
            // Switchyard's hand-tuned glyphs in a 42x26 box, centred in our caption.
            const y = rect.y + (rect.height - 26) / 2;
            switch (button) {
                .minimize => try fill(self.renderer, .{ .x = rect.x + 15, .y = y + 16, .width = 12, .height = 1 }, color),
                .maximize => {
                    const glyph = if (c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MAXIMIZED != 0) chrome.restore_icon else chrome.maximize_icon;
                    for (glyph) |part| try fill(self.renderer, .{ .x = rect.x + part.x, .y = y + part.y, .width = part.width, .height = part.height }, color);
                },
                .close => for (0..11) |step| {
                    const offset: f32 = @floatFromInt(step);
                    try fill(self.renderer, .{ .x = rect.x + 15 + offset, .y = y + 7 + offset, .width = 1, .height = 1 }, color);
                    if (step != 5) try fill(self.renderer, .{ .x = rect.x + 15 + offset, .y = y + 17 - offset, .width = 1, .height = 1 }, color);
                },
                .none => {},
            }
        }
    }
    fn drawHeader(self: *App) !void {
        if (self.headerHeight() == 0) return;
        const colors = try self.uiPalette();
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = self.width, .height = chrome.height }, colors.title);
        for (0..self.tab_count) |number| {
            const index: u8 = @intCast(number);
            const rect = self.headerTabs(self.width).tab(index);
            if (self.drag == .tab and index == self.active) {
                try outline(self.renderer, rect, colors.border);
            } else try self.drawTab(index, rect);
        }
        if (self.drag == .tab) {
            var rect = self.headerTabs(self.width).tab(self.active);
            rect.x = self.drag.tab.x;
            try self.drawTab(self.active, rect);
            try outline(self.renderer, rect, colors.accent);
        }
        if (self.headerHover() == .caption) try fill(self.renderer, self.headerTabs(self.width).caption(), appearance.hover(colors.title));
        for ([_]layout.Rect{ self.headerTabs(self.width).plus(), self.headerTabs(self.width).profiles(), chrome.settings(self.width) }, [_][]const layout.Rect{ chrome.plus_icon, chrome.profile_icon, chrome.settings_icon }) |rect, glyph| {
            if (self.isHovered(rect)) try fill(self.renderer, rect, appearance.hover(colors.title));
            for (glyph) |part| try fill(self.renderer, .{ .x = rect.x + part.x, .y = rect.y + part.y, .width = part.width, .height = part.height }, colors.text);
        }
        try self.drawWindowControls();
    }
    fn drawDivider(self: *App, divider: layout.Divider, color: c.SDL_Color) !void {
        var line = divider.rect;
        if (divider.axis == .horizontal) {
            line.x += @max(0, (line.width - 2) / 2);
            line.width = @min(2, line.width);
        } else {
            line.y += @max(0, (line.height - 2) / 2);
            line.height = @min(2, line.height);
        }
        try fill(self.renderer, line, color);
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
        try self.drawHeader();
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            const active = place.pane == self.tab().tree.active;
            try fill(self.renderer, place.rect, colors.panel);
            if (active and result.panes > 1) try outline(self.renderer, place.rect, colors.border);
            const rect = paneContent(place.rect);
            if (p.graphics_failure == null) {
                if (p.owner) |owner| p.canvas.update(self.renderer, owner) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            if (self.selecting) |dragging| if (dragging.pane == p and dragging.edge != 0)
                try self.selectPoint(p, dragging.x, dragging.y, .extend, true);
            const status = p.snapshot();
            if (active and status.selection_serial == p.selection_serial and status.selection_failure != null and p.selection_failure_reported != status.selection_serial) {
                p.selection_failure_reported = status.selection_serial;
                self.report(status.selection_failure.?);
            }
            if (p.canvas.frame()) |frame| {
                // A completed font transaction supplies the new lattice before its frame arrives.
                // An older accepted lease must not resize canonical geometry back to its old font.
                const cell = p.cell_size orelse frame.cell_size;
                const rows: u16 = @intFromFloat(std.math.clamp(@floor(rect.h * self.scale / @as(f32, @floatFromInt(cell.height))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_rows))));
                const columns: u16 = @intFromFloat(std.math.clamp(@floor(rect.w * self.scale / @as(f32, @floatFromInt(cell.width))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_columns))));
                if (p.size_control and status.failure == null and !status.closed and (rows != p.rows or columns != p.columns)) {
                    try p.submit(.{ .resize = .{ .rows = rows, .columns = columns } });
                    p.rows = rows;
                    p.columns = columns;
                }
                const placed = terminalPlacement(rect, frame.surface, self.scale);
                const cursor_focused = self.focused and active and !status.closed and p.graphics_failure == null and
                    self.palette == null and self.settings_editor == null and self.chooser == null and
                    c.SDL_GetWindowFlags(self.window) & (c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_MINIMIZED) == 0;
                const show_cursor = p.blink.update(c.SDL_GetTicks(), frame, cursor_focused, self.configuration.value.cursor_blink);
                const cursor_display: canvas.CursorDisplay = if (!cursor_focused) .outline else if (show_cursor) .shown else .hidden;
                if (p.blink.deadline) |deadline| self.cursor_deadline = deadline;
                if (p.graphics_failure == null) p.canvas.draw(self.renderer, self.geometry, placed, self.scale, cursor_display) catch |failure| {
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
                const clip: c.SDL_Rect = .{
                    .x = @intFromFloat(@floor(rect.x)),
                    .y = @intFromFloat(@floor(rect.y)),
                    .w = @as(c_int, @intFromFloat(@ceil(rect.x + rect.w))) - @as(c_int, @intFromFloat(@floor(rect.x))),
                    .h = @as(c_int, @intFromFloat(@ceil(rect.y + rect.h))) - @as(c_int, @intFromFloat(@floor(rect.y))),
                };
                if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
                defer clearClip(self.renderer);
                if (failure) |value| {
                    try fill(self.renderer, .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = @min(28, rect.h) }, .{ .r = 96, .g = 35, .b = 43, .a = 255 });
                    try self.drawText(@errorName(value), rect.x + 8, rect.y + 6);
                } else try self.drawText("Exited — Ctrl+Shift+R to restart", rect.x + 8, rect.y + 6);
            }
        }
        if (self.drag == .divider) {
            for (dividers[0..result.dividers]) |divider|
                if (self.drag.divider.contains(divider.node)) try self.drawDivider(divider, colors.accent);
        } else if (self.hover_divider) |held| {
            for (held.dividers[0..held.count]) |divider| try self.drawDivider(divider, colors.accent);
        }
        self.expireNotice(c.SDL_GetTicks());
        if (self.notice_len != 0) {
            const notice: layout.Rect = .{ .x = 6, .y = self.height - 28, .width = @max(1, self.width - 12), .height = 22 };
            try fill(self.renderer, notice, colors.title);
            try self.clippedText(self.notice[0..self.notice_len], notice, notice.x + 4);
        }
        if (self.palette != null) try self.drawPalette();
        if (self.settings_editor != null) try self.drawSettings();
        if (self.chooser != null) try self.drawChooser();
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
    geometry: ?instance.PresentationGeometry = null,
};
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
fn outline(renderer: *c.SDL_Renderer, rect: layout.Rect, color: c.SDL_Color) !void {
    const target: c.SDL_FRect = .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
    if (!c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) or !c.SDL_RenderRect(renderer, &target)) return error.SDL;
}
fn fill(renderer: *c.SDL_Renderer, rect: layout.Rect, color: c.SDL_Color) !void {
    const target: c.SDL_FRect = .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
    if (!c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) or !c.SDL_RenderFillRect(renderer, &target)) return error.SDL;
}
fn mouseButton(button: u8) ?instance.MouseButton {
    return switch (button) {
        c.SDL_BUTTON_LEFT => .left,
        c.SDL_BUTTON_MIDDLE => .middle,
        c.SDL_BUTTON_RIGHT => .right,
        else => null,
    };
}
fn setClip(renderer: *c.SDL_Renderer, rect: layout.Rect) error{SDL}!void {
    const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(rect.x)), .y = @intFromFloat(@floor(rect.y)), .w = @intFromFloat(@ceil(rect.x + rect.width) - @floor(rect.x)), .h = @intFromFloat(@ceil(rect.y + rect.height) - @floor(rect.y)) };
    if (!c.SDL_SetRenderClipRect(renderer, &clip)) return error.SDL;
}
fn clearClip(renderer: *c.SDL_Renderer) void {
    const success = c.SDL_SetRenderClipRect(renderer, null);
    std.debug.assert(success);
}
fn paneContent(rect: layout.Rect) c.SDL_FRect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
}
// Split sub-cell slack evenly around the accepted frame; the pane remains resize authority.
// Align absolute origins to physical pixels.
fn terminalPlacement(available: c.SDL_FRect, surface: instance.render.terminal.Size, scale: f32) c.SDL_FRect {
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
fn physicalSurface(rect: layout.Rect, scale: f32) instance.render.terminal.Size {
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
    std.testing.refAllDecls(@import("publication.zig"));
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
    std.testing.refAllDecls(color_config);
}

test "command palette exposes every mapping including directional multiplexing commands" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var p: Palette = .{};
    var indices: [palette_limit]usize = undefined;
    const count = try p.indices(&configuration, null, &indices);
    try std.testing.expectEqual(keybindings.definitions.len, count);
    const query = "FOCUS PANE";
    @memcpy(p.query[0..query.len], query);
    p.len = query.len;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, null, &indices));
    for (indices[0..4]) |index| try std.testing.expect(keybindings.definitions[index].target == .pane_focus);
    p = .{ .profile = true };
    try std.testing.expectEqual(@as(usize, 3), try p.indices(&configuration, null, &indices));
}

test "profile palette uses saved recipes and resolves its configured default" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"app_theme":"howl_dark","default_profile":"build","profiles":[{"id":"build","name":"Build shell","shell":"/bin/sh","command":"exec sh","font_pixels":19}]}
    );
    defer configuration.deinit();
    var p: Palette = .{ .profile = true };
    var indices: [palette_limit]usize = undefined;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, null, &indices));
    @memcpy(p.query[0..5], "BUILD");
    p.len = 5;
    try std.testing.expectEqual(@as(usize, 1), try p.indices(&configuration, null, &indices));
    try std.testing.expectEqual(try configuration.defaultProfile(), indices[0]);
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

fn testFonts(a: std.mem.Allocator) !font_owner.Fonts {
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
        .command = "printf '\\033[2;5H\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
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
    event_value.text.text = "COMMITTED\n";
    try app.event(event_value);
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
    try std.testing.expect(@as(f32, @floatFromInt(area.x)) >= app.settingsField().x);
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
            .command = "read start; i=0; while [ \"$i\" -lt 70 ]; do printf '%s\\n' \"$i\"; i=$((i+1)); done; printf '\\033]0;READY\\007'; while read line; do size=$(stty size); printf '\\033]0;%s:%s\\007' \"$line\" \"$size\"; printf '%s\\n' \"$line\"; done",
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
        if (frame.presentation_generation > generation and frame.history_count >= history) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempts < 5000);
    proof_stage = "accepted save";
    try app.applyConfigurationAt(&candidate, temporary.dir, "app.json");
    try std.testing.expectEqual(@as(i32, 23), current.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u16, 23), panes[0].font_size);
    try std.testing.expectEqual(@as(u16, 17), panes[1].font_size);
    try std.testing.expect(panes[1].font_overridden);
    var reopened = try config.Config.loadAt(a, threaded.io(), temporary.dir, "app.json");
    defer reopened.deinit();
    try std.testing.expectEqual(@as(i32, 23), reopened.value.terminal_font_pixels);
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
    const cell: instance.render.terminal.Size = .{ .width = 17, .height = 41 };
    for ([_]f32{ 1, 1.7, 2 }) |scale| {
        const surface: instance.render.terminal.Size = .{ .width = 850, .height = 492 };
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
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    const catalogue = try discovery.Catalogue.create(std.testing.allocator, std.testing.io, &env, configuration.value);
    defer catalogue.destroy(std.testing.allocator);
    for (0..100) |i| catalogue.entries[i] = .{ .kind = .ssh, .recipe = .{
        .name = try std.fmt.allocPrint(catalogue.arena.allocator(), "host-{d:0>3}", .{i}),
        .shell = "/usr/bin/ssh",
        .arguments = &.{ "-t", "--", "literal-alias" },
    } };
    catalogue.count = 100;
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
        .discovered = catalogue,
        .palette = .{ .profile = true },
    };
    var indices: [palette_limit]usize = undefined;
    catalogue.count = 0;
    try std.testing.expectEqual(@as(usize, 3), app.paletteRows());
    catalogue.count = 100;
    const count = try app.palette.?.indices(&configuration, catalogue, &indices);
    try std.testing.expectEqual(@as(usize, 103), count);
    try app.paletteKey(c.SDLK_END, c.SDL_KMOD_CTRL);
    try std.testing.expectEqual(count - 1, app.palette.?.list.selected);
    try std.testing.expect(app.paletteStart(count) + app.paletteRows() <= count);
    try app.paletteKey(c.SDLK_PAGEUP, 0);
    try std.testing.expectEqual(count - 1 - app.paletteRows(), app.palette.?.list.selected);
    const query = "HOST-099";
    @memcpy(app.palette.?.query[0..query.len], query);
    app.palette.?.len = query.len;
    try std.testing.expectEqual(@as(usize, 1), try app.palette.?.indices(&configuration, catalogue, &indices));
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
    try std.testing.expectEqual(@as(usize, 0), try app.palette.?.indices(&configuration, catalogue, &indices));
}

test "settings clicks select without saving; staged choices and Escape unwind focus before closing" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("settings focus proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"profiles":[{"id":"build","name":"Build"}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .content_focus = true },
    };
    var event_value = std.mem.zeroes(c.SDL_KeyboardEvent);
    event_value.key = c.SDLK_RETURN;
    try app.settingsKey(event_value);
    try std.testing.expectEqual(settings.Target.default_profile, app.settings_editor.?.editing.?);
    try app.settings_editor.?.append("not a profile");
    try std.testing.expectEqualStrings("local", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    event_value.key = c.SDLK_DOWN;
    try app.settingsKey(event_value);
    try std.testing.expectEqualStrings("build", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    try std.testing.expectEqual(@as(u8, 0), try configuration.defaultProfile());
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor.?.editing == null);

    const toggle = app.settingsRows().row(1);
    try app.settingsClick(toggle.x + toggle.width - 10, toggle.y + 12, 1);
    try std.testing.expect(app.settings_editor.?.editing == null);
    try std.testing.expect(!configuration.value.discover_shells);
    try app.settingsClick(toggle.x + toggle.width - 10, toggle.y + 12, 2);
    try std.testing.expect(app.settings_editor.?.editing.? == .discover_shells);
    event_value.key = c.SDLK_RIGHT;
    try app.settingsKey(event_value);
    try std.testing.expectEqualStrings("On", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    event_value.key = c.SDLK_TAB;
    try app.settingsKey(event_value);
    try std.testing.expectEqual(@as(?u8, 0), app.settings_editor.?.button);
    const field = app.settingsField();
    try app.settingsClick(field.x + 10, field.y + 10, 1);
    try std.testing.expect(app.settings_editor.?.button == null);
    try app.settingsKey(event_value);
    try app.settingsKey(event_value);
    try std.testing.expectEqual(@as(?u8, 1), app.settings_editor.?.button);
    event_value.key = c.SDLK_RETURN;
    try app.settingsKey(event_value);
    try std.testing.expect(!configuration.value.discover_shells);

    const ordinary = app.settingsRows().row(1);
    event_value.key = c.SDLK_F;
    event_value.mod = c.SDL_KMOD_CTRL;
    try app.settingsKey(event_value);
    try std.testing.expectEqual(ordinary, app.settingsRows().row(1));
    try app.settings_editor.?.append("palette");
    try std.testing.expect(app.settings_editor.?.search);
    event_value.mod = 0;
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(!app.settings_editor.?.search and app.settings_editor.?.content_focus);
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor != null and !app.settings_editor.?.content_focus);
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor == null);
}

fn testPixel(surface: *c.SDL_Surface, x: c_int, y: c_int) !c.SDL_Color {
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
                for ([_]instance.render.terminal.Size{
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
