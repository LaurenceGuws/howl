//! Owns the local SDL window, pane layout, input routing and terminal workers.
const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const font_owner = @import("fonts.zig");
const terminal = @import("terminal.zig");
const canvas = @import("canvas.zig");
const chrome = @import("chrome.zig");
const layout = @import("layout.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const pointer = @import("pointer.zig");
const composition = @import("composition.zig");
const config = @import("config.zig");
const settings = @import("settings.zig");
const appearance = @import("appearance.zig");
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

const CreationError = @typeInfo(@typeInfo(@TypeOf(terminal.Terminal.create)).@"fn".return_type.?).error_union.error_set;
const Pane = struct {
    owner: ?*terminal.Terminal = null,
    recipe: config.Recipe,
    creation_failure: ?CreationError = null,
    canvas: canvas.Canvas,
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
const Palette = struct {
    query: [128]u8 = @splat(0),
    len: usize = 0,
    selected: usize = 0,
    profile: bool = false,

    fn indices(self: *const Palette, configuration: *const config.Config, out: *[keybindings.definitions.len]usize) error{InvalidDefaultProfile}!usize {
        var count: usize = 0;
        const limit = if (self.profile) configuration.profileCount() + 2 else keybindings.definitions.len;
        for (0..limit) |i| {
            if (!self.profile and keybindings.definitions[i].target != .action) continue;
            const label = if (self.profile) (if (i < configuration.profileCount()) (try configuration.profile(@intCast(i))).name else if (i == configuration.profileCount()) "Command Palette" else "Settings") else keybindings.definitions[i].label;
            if (self.len != 0 and !containsIgnoreCase(label, self.query[0..self.len])) continue;
            out[count] = i;
            count += 1;
        }
        return count;
    }
};
const FindEditor = struct {
    serial: u64 = 0,
    bytes: [find.query_limit]u8 = undefined,
    len: usize = 0,
};
const Drag = union(enum) { none, divider: layout.Divider, tab: chrome.Drag };
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
    settings_editor: ?settings.Editor = null,
    chooser: ?*font_chooser.Chooser = null,
    drag: Drag = .none,
    chrome_pressed: chrome.Button = .none,
    chrome_hover: chrome.Button = .none,
    pointer_buttons: u32 = 0,
    consume_left_release: bool = false,
    focused: bool = false,
    running: bool = true,
    width: f32 = 1000,
    height: f32 = 650,
    notice: [256]u8 = @splat(0),
    notice_len: usize = 0,
    notice_until: u64 = 0,

    fn deinit(self: *App) void {
        if (self.chooser) |chooser| chooser.destroy(allocator);
        for (self.tabs[0..self.tab_count]) |value| self.destroyTab(value.?);
    }
    fn tab(self: *App) *Tab {
        return self.tabs[self.active].?;
    }
    fn pane(self: *App) *Pane {
        return self.tab().panes[self.tab().tree.active].?;
    }
    fn terminalBody(self: *const App) layout.Rect {
        return .{ .x = 6, .y = chrome.height + 6, .width = @max(1, self.width - 12), .height = @max(1, self.height - chrome.height - 12) };
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
        if (self.notice_len != 0) return @intCast(@max(1, @min(self.notice_until -| now, if (scrolling) @as(u64, 50) else std.math.maxInt(c_int))));
        return if (scrolling) 50 else null;
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
        return terminal.Terminal.create(allocator, self.init.io, inherited, .{
            .shell = if (recipe.shell.len != 0) recipe.shell else self.init.environ_map.get("SHELL") orelse "/bin/sh",
            .command = if (recipe.command.len != 0) recipe.command else null,
            .cwd = if (recipe.cwd.len != 0) recipe.cwd else null,
            .rows = 37,
            .columns = 80,
        }, self.fonts.config(pixels), self.wake_event, false);
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
            for (t.panes, 0..) |maybe_p, slot| if (maybe_p) |p|
                if (p.owner) |owner| owner.setVisible(index == self.active and (!t.tree.zoomed or slot == t.tree.active));
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
        if (self.palette != null) {
            self.palette = null;
            try self.gainKeyboard();
            return;
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
            .toggle_pane_zoom => panes > 1,
            .next_tab, .previous_tab => self.tab_count > 1,
            .move_tab_left => self.active > 0,
            .move_tab_right => self.active + 1 < self.tab_count,
            .take_size_control => !self.pane().size_control,
            .stop_resizing => self.pane().size_control,
            else => true,
        };
    }
    fn dispatch(self: *App, target: keybindings.Target) !void {
        if (target == .action and !self.actionEnabled(target.action)) return;
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
                const changed = self.tab().tree.resize(direction);
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
                const text = try allocator.dupeSentinel(u8, bytes, 0);
                defer allocator.free(text);
                if (!c.SDL_SetClipboardText(text)) return error.SDLClipboard;
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
        const geometry = owner.reconfigure(self.fonts.config(pixels), if (resize) self.surfaceFor(value) else null) catch |failure| {
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
    fn uiPalette(self: *const App) error{InvalidTheme}!appearance.Palette {
        return appearance.palette(self.configuration.value.app_theme);
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
        const bindings = try keybindings.Bindings.fromOverrides(candidate.value.keybindings);
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
                    change.geometry = try owner.reconfigure(fonts.config(pixels), null);
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
            const geometry = owner.reconfigure(self.fonts.config(pixels), null) catch |failure| {
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
            editor.selected = 0;
            editor.content_focus = true;
            var all: [settings.row_limit]settings.Row = undefined;
            var shown: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.configuration, &all);
            const visible = editor.indices(all[0..count], &shown);
            for (shown[0..visible], 0..) |index, number| {
                if (std.meta.eql(all[index].target, row.target)) {
                    editor.selected = number;
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
            editor.selected = 0;
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
    fn chooserKey(self: *App, key: c.SDL_Keycode) !void {
        const chooser = self.chooser.?;
        switch (key) {
            c.SDLK_ESCAPE => try self.chooserCancel(),
            c.SDLK_RETURN => try self.chooserApply(true),
            c.SDLK_RIGHT => try self.chooserApply(false),
            c.SDLK_LEFT => try self.chooserRestore(),
            c.SDLK_UP => chooser.move(-1),
            c.SDLK_DOWN => chooser.move(1),
            c.SDLK_PAGEUP => chooser.move(-10),
            c.SDLK_PAGEDOWN => chooser.move(10),
            c.SDLK_HOME => chooser.selected = 0,
            c.SDLK_END => chooser.selected = chooser.result_count -| 1,
            c.SDLK_BACKSPACE => chooser.backspace(),
            else => {},
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
    fn chooserVisible(self: *const App) u16 {
        return @intFromFloat(std.math.clamp(@floor(self.chooserList().height / 32), 1, 10));
    }
    fn chooserStart(self: *const App) u16 {
        return (self.chooser.?.selected + 1) -| self.chooserVisible();
    }
    fn chooserClick(self: *App, x: f32, y: f32) !void {
        const box = self.settingsRect();
        if (!box.contains(x, y)) return self.chooserCancel();
        const list = self.chooserList();
        if (y >= box.y + box.height - 42) {
            const third = @max(1, box.width / 3);
            if (x < box.x + third) try self.chooserApply(false) else if (x < box.x + 2 * third) try self.chooserApply(true) else try self.chooserCancel();
        } else if (list.contains(x, y)) {
            const relative = @floor((y - list.y) / 32);
            if (relative >= @as(f32, @floatFromInt(self.chooserVisible()))) return;
            const row: u16 = @intFromFloat(relative);
            const chosen = row + self.chooserStart();
            if (row < self.chooserVisible() and chosen < self.chooser.?.result_count) self.chooser.?.selected = chosen;
        }
    }
    fn drawChooser(self: *App) !void {
        const chooser = self.chooser.?;
        const colors = try self.uiPalette();
        const box = self.settingsRect();
        const list = self.chooserList();
        const field = self.chooserField();
        try fill(self.renderer, box, colors.panel);
        try self.drawText(if (chooser.truncated) "Installed terminal fonts — first 256 families" else "Installed terminal fonts", box.x + 12, box.y + 12);
        try fill(self.renderer, field, colors.title);
        try self.clippedText(if (chooser.query_len == 0) "Type to search families" else chooser.query[0..chooser.query_len], field, field.x + 6);
        const start = self.chooserStart();
        for (start..@min(chooser.result_count, start + self.chooserVisible())) |index| {
            const row: layout.Rect = .{ .x = list.x, .y = list.y + @as(f32, @floatFromInt(index - start)) * 32, .width = list.width, .height = 30 };
            if (index == chooser.selected) try fill(self.renderer, row, colors.active);
            try self.clippedText(try chooser.label(@intCast(index)), row, row.x + 6);
        }
        const sample: layout.Rect = .{ .x = list.x + list.width + 12, .y = list.y, .width = @max(1, box.x + box.width - 12 - list.x - list.width - 12), .height = list.height };
        if (chooser.result_count == 0) try self.clippedText("No matching terminal font families", sample, sample.x) else {
            try self.clippedText(try chooser.label(chooser.selected), .{ .x = sample.x, .y = sample.y, .width = sample.width, .height = 30 }, sample.x);
            try self.clippedText(try chooser.regularPath(), .{ .x = sample.x, .y = sample.y + 32, .width = sample.width, .height = 30 }, sample.x);
            const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(sample.x)), .y = @intFromFloat(@floor(sample.y + 68)), .w = @intFromFloat(@ceil(sample.width)), .h = @intFromFloat(@ceil(@max(1, sample.height - 68))) };
            if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
            defer clearClip(self.renderer);
            if (try chooser.sample(self.scale)) |font| {
                for ([_][]const u8{ "abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "0123456789  ()[]{}<> +-*/", "Il1 O0  -> => != ==  $@" }, 0..) |line, number| {
                    try self.drawTextFont(font, line, sample.x, sample.y + 76 + @as(f32, @floatFromInt(number)) * 34);
                }
            }
        }
        const button_width = @max(1, (box.width - 24) / 3);
        for ([_][]const u8{ "Preview →", "Save Enter", "Cancel Esc" }, 0..) |label, index| {
            const button: layout.Rect = .{ .x = box.x + 12 + @as(f32, @floatFromInt(index)) * button_width, .y = box.y + box.height - 38, .width = @max(1, button_width - 4), .height = 30 };
            try fill(self.renderer, button, colors.active);
            try self.clippedText(label, button, button.x + 6);
        }
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
            try self.changeSetting(e.editing.?, try keybindings.format(key, event_value.mod, &buffer));
            return;
        }
        if (e.editing) |target| {
            if (mods.control and key == c.SDLK_A) e.select_all = true else if (mods.control and key == c.SDLK_V) {
                self.keyboard.suppress_text = true;
                const text = c.SDL_GetClipboardText() orelse return error.SDL;
                defer c.SDL_free(text);
                try e.append(std.mem.span(text));
            } else switch (key) {
                c.SDLK_ESCAPE => {
                    self.cancelComposition();
                    e.cancel();
                },
                c.SDLK_RETURN => try self.changeSetting(target, e.buffer[0..e.len]),
                c.SDLK_BACKSPACE, c.SDLK_DELETE => e.backspace(),
                else => {},
            }
            return;
        }
        if (mods.control and key == c.SDLK_F) {
            self.cancelComposition();
            e.search = !e.search;
            e.query_len = 0;
            e.selected = 0;
            e.delete_pending = null;
            return;
        }
        if (key == c.SDLK_ESCAPE) {
            self.cancelComposition();
            if (e.search) {
                e.search = false;
                e.query_len = 0;
                e.selected = 0;
            } else try self.toggleSettings();
            return;
        }
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        if (key == c.SDLK_TAB and !e.search) {
            e.content_focus = !e.content_focus;
            return;
        }
        if (!e.search and !e.content_focus) {
            if (key == c.SDLK_UP or key == c.SDLK_DOWN) {
                const page_number = @as(i16, @backingInt(e.page)) + @as(i16, if (key == c.SDLK_UP) -1 else 1);
                e.page = @fromBackingInt(@intCast(std.math.clamp(page_number, 0, settings.titles.len - 1)));
                e.selected = 0;
                e.delete_pending = null;
            } else if (key == c.SDLK_RETURN or key == c.SDLK_RIGHT) e.content_focus = true;
            return;
        }
        if (visible == 0) return;
        e.selected = @min(e.selected, visible - 1);
        const row = all[indices[e.selected]];
        switch (key) {
            c.SDLK_UP, c.SDLK_PAGEUP => {
                e.selected -|= if (key == c.SDLK_UP) 1 else 10;
                e.delete_pending = null;
            },
            c.SDLK_DOWN, c.SDLK_PAGEDOWN => {
                e.selected = @min(visible - 1, e.selected + (if (key == c.SDLK_DOWN) @as(usize, 1) else 10));
                e.delete_pending = null;
            },
            c.SDLK_RETURN => try self.activateSetting(row),
            c.SDLK_BACKSPACE => if (e.search) {
                e.backspace();
            } else if (row.target == .binding) {
                try self.changeSetting(row.target, keybindings.definitions[row.target.binding].default_shortcut);
            } else if (row.target == .font) {
                try self.changeSetting(row.target, "");
            },
            c.SDLK_DELETE => if (row.target == .binding) try self.changeSetting(row.target, ""),
            c.SDLK_LEFT, c.SDLK_RIGHT => {
                const delta: i8 = if (key == c.SDLK_LEFT) -1 else 1;
                if (mods.alt and row.target == .environment) {
                    const field = row.target.environment;
                    try self.changeSetting(.{ .move_environment = .{ .profile = field.profile, .index = field.index, .delta = delta } }, "");
                } else if (row.target == .default_font) {
                    const next = std.math.clamp(self.configuration.value.terminal_font_pixels + delta, 8, 48);
                    var text: [16]u8 = undefined;
                    try self.changeSetting(row.target, try std.fmt.bufPrint(&text, "{d}", .{next}));
                } else if (row.target == .default_profile) {
                    const index = try self.configuration.defaultProfile();
                    const next: u8 = @intCast(std.math.clamp(@as(i16, index) + delta, 0, @as(i16, self.configuration.profileCount()) - 1));
                    try self.changeSetting(.{ .set_default = next }, "");
                } else if (row.target == .theme) {
                    const themes = [_][]const u8{ "howl_dark", "slate", "high_contrast" };
                    var index: i16 = 0;
                    for (themes, 0..) |theme, i| if (std.mem.eql(u8, theme, self.configuration.value.app_theme)) {
                        index = @intCast(i);
                        break;
                    };
                    try self.changeSetting(row.target, themes[@intCast(@mod(index + delta, 3))]);
                }
            },
            else => {},
        }
        if (!e.search and e.page == .defaults) e.profile = @intCast(e.selected);
    }
    fn newWindow(self: *App) !void {
        // Linux fork/exec resolves this exact running image even after an on-disk upgrade.
        var child = try std.process.spawn(self.init.io, .{ .argv = &.{"/proc/self/exe"} });
        errdefer child.kill(self.init.io);
        const thread = try std.Thread.spawn(.{}, reapWindow, .{child.id.?});
        thread.detach();
    }
    fn cancelDrag(self: *App) void {
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
    fn choosePalette(self: *App, index: usize) !void {
        if (!self.palette.?.profile) return self.dispatch(keybindings.definitions[index].target);
        if (index >= self.configuration.profileCount()) {
            self.palette = null;
            if (index == self.configuration.profileCount()) return self.openPalette(false);
            return self.toggleSettings();
        }
        const recipe = try self.configuration.profile(@intCast(index));
        // Keep the overlay and original input owner intact if construction cannot commit.
        try self.createTab(recipe, null);
        self.palette = null;
        try self.gainKeyboard();
    }
    fn paletteKey(self: *App, key: c.SDL_Keycode) !void {
        var matches: [keybindings.definitions.len]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        switch (key) {
            c.SDLK_ESCAPE => {
                self.palette = null;
                try self.gainKeyboard();
            },
            c.SDLK_UP => if (count != 0) {
                self.palette.?.selected = if (self.palette.?.selected == 0) count - 1 else self.palette.?.selected - 1;
            },
            c.SDLK_DOWN => if (count != 0) {
                self.palette.?.selected = (self.palette.?.selected + 1) % count;
            },
            c.SDLK_BACKSPACE => {
                var p = &self.palette.?;
                if (p.len > 0) {
                    p.len -= 1;
                    while (p.len > 0 and p.query[p.len] & 0xc0 == 0x80) p.len -= 1;
                    p.selected = 0;
                }
            },
            c.SDLK_RETURN => if (count != 0) try self.choosePalette(matches[@min(self.palette.?.selected, count - 1)]),
            else => {},
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
        if (text.len > editor.bytes.len - editor.len) return error.InvalidQuery;
        @memcpy(editor.bytes[editor.len..][0..text.len], text);
        editor.len += text.len;
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
            c.SDLK_BACKSPACE => {
                var editor = p.finder.?;
                if (editor.len == 0) return;
                editor.len -= 1;
                while (editor.len != 0 and editor.bytes[editor.len] & 0xc0 == 0x80) editor.len -= 1;
                try self.findRequest(p, try find.Request.query(0, editor.bytes[0..editor.len]));
                editor.serial = p.selection_serial;
                p.finder = editor;
            },
            else => {},
        }
    }
    fn findField(rect: c.SDL_FRect) layout.Rect {
        return .{ .x = rect.x, .y = rect.y + @max(0, rect.h - 28), .width = rect.w, .height = @min(28, rect.h) };
    }
    fn drawFind(self: *App, p: *Pane, rect: c.SDL_FRect, status: terminal.Status) !void {
        const editor = p.finder orelse return;
        const field = findField(rect);
        const colors = try self.uiPalette();
        try fill(self.renderer, field, colors.active);
        const query_rect: layout.Rect = .{ .x = field.x + 6, .y = field.y, .width = @max(1, field.width * 0.55 - 12), .height = field.height };
        const query_text = if (editor.len == 0) "Find — type text" else editor.bytes[0..editor.len];
        const query_scroll = if (editor.len == 0) 0 else @max(0, try self.textWidth(query_text) - query_rect.width + 12);
        try self.clippedText(query_text, query_rect, query_rect.x - query_scroll);
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

    fn event(self: *App, value: c.SDL_Event) !void {
        if (try self.chromeEvent(value)) return;
        self.input_timestamp = value.common.timestamp;
        switch (value.type) {
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
                    .overlay => if (self.chooser != null) try self.chooserKey(value.key.key) else if (self.settings_editor != null) try self.settingsKey(value.key) else if (self.palette != null) try self.paletteKey(value.key.key) else try self.findKey(value.key),
                }
            },
            c.SDL_EVENT_TEXT_EDITING => {
                if (!self.focused or !self.preedit.accepts(value.edit.timestamp)) return;
                try self.preedit.set(std.mem.span(value.edit.text), value.edit.start, value.edit.length);
            },
            c.SDL_EVENT_TEXT_INPUT => {
                if (!self.focused or !self.preedit.accepts(value.text.timestamp)) return;
                self.preedit.clear();
                if (self.keyboard.consumeText()) return;
                const text = std.mem.span(value.text.text);
                if (self.chooser) |chooser| {
                    try chooser.append(text);
                } else if (self.settings_editor) |*e| {
                    if (!e.recording) try e.append(text);
                } else if (self.palette) |*p| {
                    if (text.len <= p.query.len - p.len) {
                        @memcpy(p.query[p.len..][0..text.len], text);
                        p.len += text.len;
                        p.selected = 0;
                    }
                } else if (self.pane().finder != null) try self.findAppend(text) else try self.pane().submit(.{ .input = .{ .bytes = text } });
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (mouseButton(value.button.button)) |button|
                try self.pointerDown(value.button.x, value.button.y, button, input.semanticModifiers(c.SDL_GetModState()), value.button.clicks),
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button = mouseButton(value.button.button) orelse return;
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
                if (self.scrolling != null) {
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
                    self.moveTab(self.drag.tab.move(value.motion.x, self.tab_count, self.width));
                } else if (self.palette == null and self.settings_editor == null) {
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
            if (button == .left) try self.settingsClick(x, y);
            return;
        }
        if (self.palette != null) {
            if (button != .left) return;
            var matches: [keybindings.definitions.len]usize = undefined;
            const count = try self.palette.?.indices(self.configuration, &matches);
            const box = self.paletteRect();
            if (!box.contains(x, y)) {
                self.palette = null;
                try self.gainKeyboard();
            } else {
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
        if (y < chrome.height) {
            if (button != .left) return;
            for (0..self.tab_count) |number| {
                const index: u8 = @intCast(number);
                const rect = chrome.tab(index, self.tab_count, self.width);
                if (!rect.contains(x, y)) continue;
                try self.selectTab(index);
                if (self.tab_count > 1 and rect.width >= 96 and x >= rect.x + rect.width - 30) {
                    try self.closeTab();
                    self.consume_left_release = true;
                } else self.drag = .{ .tab = chrome.Drag.begin(rect, x) };
                return;
            }
            if (chrome.plus(self.tab_count, self.width).contains(x, y)) {
                try self.createTab(try self.startup(), null);
            } else if (chrome.settings(self.width).contains(x, y)) {
                try self.toggleSettings();
            }
            self.consume_left_release = true;
            return;
        }
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (dividers[0..result.dividers]) |divider| if (button == .left and divider.rect.contains(x, y)) {
            self.drag = .{ .divider = divider };
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
    fn desktopAttention(self: *App) !void {
        var attention = false;
        for (self.tabs[0..self.tab_count]) |t| for (t.?.panes) |p| if (p) |value| if (value.owner) |owner| {
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
    fn drawScrollbar(self: *App, rect: c.SDL_FRect, frame: instance.PublishedFrame) !void {
        const bar = scrollbar.Bar.fromFrame(.{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, frame, self.scale) orelse return;
        const colors = try self.uiPalette();
        try fill(self.renderer, bar.track, colors.idle);
        try fill(self.renderer, bar.thumb, colors.border);
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
    fn drawSelection(self: *App, p: *Pane, rect: c.SDL_FRect, frame: instance.PublishedFrame) !void {
        const paint = &p.canvas.selection_paint;
        // Paint belongs to the accepted frame, not a newer queued drag intent.
        const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(rect.x)), .y = @intFromFloat(@floor(rect.y)), .w = @intFromFloat(@ceil(rect.w)), .h = @intFromFloat(@ceil(rect.h)) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
        defer clearClip(self.renderer);
        const width = @as(f32, @floatFromInt(frame.cell_size.width)) / self.scale;
        const height = @as(f32, @floatFromInt(frame.cell_size.height)) / self.scale;
        const color: c.SDL_Color = .{ .r = 180, .g = 180, .b = 180, .a = 100 };
        for (paint.spans[0..paint.rows], 0..) |span, row| if (span) |range| {
            try fill(self.renderer, .{ .x = rect.x + @as(f32, @floatFromInt(range.first)) * width, .y = rect.y + @as(f32, @floatFromInt(row)) * height, .width = @as(f32, @floatFromInt(range.last - range.first + 1)) * width, .height = height }, color);
        };
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
            if (std.math.isFinite(wheel.y)) chooser.move(@intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256)));
            return;
        }
        if (self.settings_editor) |*editor| {
            if (!std.math.isFinite(wheel.y) or editor.editing != null) return;
            var rows: [settings.row_limit]settings.Row = undefined;
            var filtered: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.configuration, &rows);
            const visible = editor.indices(rows[0..count], &filtered);
            const offset: i32 = @intFromFloat(std.math.clamp(-wheel.y * 3, -256, 256));
            editor.selected = @intCast(std.math.clamp(@as(i32, @intCast(editor.selected)) + offset, 0, @as(i32, @intCast(visible -| 1))));
            editor.content_focus = true;
            return;
        }
        if (self.palette != null or self.pane().finder != null) return;
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
        if (self.palette.?.profile) return self.configuration.profileCount() + 2;
        return @min(keybindings.definitions.len, @as(usize, @intFromFloat(@floor(@max(0, self.height - 134) / 36))));
    }
    fn paletteRect(self: *const App) layout.Rect {
        if (self.palette.?.profile) {
            const width = @min(420, @max(1, self.width - 24));
            return .{ .x = @min(chrome.plus(self.tab_count, self.width).x, @max(0, self.width - width - 12)), .y = 46, .width = width, .height = @min(@max(1, self.height - 58), 16 + @as(f32, @floatFromInt(self.paletteRows())) * 48) };
        }
        const tall = @min(@max(1, self.height - 32), 102 + @as(f32, @floatFromInt(self.paletteRows())) * 36);
        const width = @min(580, @max(1, self.width - 32));
        return .{ .x = (self.width - width) / 2, .y = @min(92, @max(0, (self.height - tall) / 2)), .width = width, .height = tall };
    }
    fn paletteStart(self: *const App, count: usize) usize {
        const rows = @max(1, self.paletteRows());
        return @min((@min(self.palette.?.selected, count -| 1) / rows) * rows, count -| rows);
    }
    fn paletteRow(self: *const App, number: usize) layout.Rect {
        const box = self.paletteRect();
        const profiles = self.palette.?.profile;
        return .{ .x = box.x + (if (profiles) @as(f32, 8) else 18), .y = box.y + (if (profiles) @as(f32, 8) else 62) + @as(f32, @floatFromInt(number)) * (if (profiles) @as(f32, 48) else 36), .width = @max(1, box.width - (if (profiles) @as(f32, 16) else 36)), .height = if (profiles) 42 else 34 };
    }
    fn drawPalette(self: *App) !void {
        var matches: [keybindings.definitions.len]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        const box = self.paletteRect();
        const colors = try self.uiPalette();
        try fill(self.renderer, box, colors.title);
        try outline(self.renderer, box, colors.border);
        if (!self.palette.?.profile) try self.clippedText(if (self.palette.?.len != 0) self.palette.?.query[0..self.palette.?.len] else "> Command Palette", .{ .x = box.x + 18, .y = box.y + 12, .width = @max(1, box.width - 36), .height = 28 }, box.x + 18);
        const start = self.paletteStart(count);
        for (matches[start..@min(count, start + self.paletteRows())], start..) |index, number| {
            const row = self.paletteRow(number - start);
            if (number == self.palette.?.selected) {
                try fill(self.renderer, row, colors.active);
                try fill(self.renderer, .{ .x = row.x, .y = row.y + 4, .width = 2, .height = row.height - 8 }, colors.accent);
            }
            if (self.palette.?.profile) {
                if (index < self.configuration.profileCount()) {
                    const recipe = try self.configuration.profile(@intCast(index));
                    try self.clippedText(recipe.name, row, row.x + 10);
                    try self.drawText("Create Instance", row.x + 10, row.y + 24);
                    if (index == try self.configuration.defaultProfile()) try self.drawText("default", row.x + row.width - 72, row.y + 13);
                } else try self.clippedText(if (index == self.configuration.profileCount()) "Command Palette" else "Settings", row, row.x + 10);
            } else {
                const binding = self.bindings.rows[index];
                const label: layout.Rect = .{ .x = row.x + 10, .y = row.y + 2, .width = @max(1, row.width - 205), .height = 28 };
                try self.clippedTextColor(keybindings.definitions[index].label, label, label.x, if (self.actionEnabled(keybindings.definitions[index].target.action)) colors.text else colors.muted);
                if (binding.len != 0) try self.clippedText(binding.text[0..binding.len], .{ .x = row.x + row.width - 195, .y = row.y + 2, .width = 185, .height = 28 }, row.x + row.width - 195);
            }
        }
        if (!self.palette.?.profile and count > self.paletteRows()) {
            var footer: [96]u8 = undefined;
            const text = try std.fmt.bufPrint(&footer, "{d}–{d} of {d} · ↑↓ to navigate", .{ start + 1, @min(count, start + self.paletteRows()), count });
            try self.clippedTextColor(text, .{ .x = box.x + 18, .y = box.y + box.height - 32, .width = @max(1, box.width - 36), .height = 26 }, box.x + 18, colors.muted);
        }
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
    fn settingsField(self: *const App) layout.Rect {
        const box = self.settingsRect();
        const body = self.settingsBody();
        if (self.settings_editor.?.editing != null and !self.settings_editor.?.search) {
            const row: usize = @min(self.settings_editor.?.selected, self.settingsVisible() - 1);
            return .{ .x = body.x + body.width * 0.46, .y = body.y + @as(f32, @floatFromInt(row)) * self.settingsRowHeight() + 5, .width = @max(1, body.width * 0.54 - 8), .height = self.settingsRowHeight() - 10 };
        }
        return .{ .x = body.x, .y = box.y + 48, .width = body.width, .height = 32 };
    }
    fn settingsRowHeight(self: *const App) f32 {
        const e = self.settings_editor.?;
        return if (e.search or e.page == .mappings) 32 else 48;
    }
    fn settingsVisible(self: *const App) usize {
        return @max(1, @as(usize, @intFromFloat(@floor(self.settingsBody().height / self.settingsRowHeight()))));
    }
    fn settingsStart(self: *const App, count: usize) usize {
        const selected = @min(self.settings_editor.?.selected, count -| 1);
        return (selected + 1) -| self.settingsVisible();
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
                    e.selected = 0;
                    try e.begin(.{ .page = .profiles, .label = "Name", .target = .{ .profile = .{ .index = e.profile, .field = .name } } }, self.configuration);
                },
                1 => {
                    try self.changeSetting(.{ .clone_profile = e.profile }, "");
                    e.profile = self.configuration.profileCount() - 1;
                    e.page = .profiles;
                    e.selected = 0;
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
                e.selected = e.profile;
            },
            1 => {
                try self.changeSetting(.{ .clone_profile = e.profile }, "");
                e.profile = self.configuration.profileCount() - 1;
                e.selected = 0;
            },
            2 => try self.changeSetting(.{ .set_default = e.profile }, ""),
            else => {},
        };
        e.content_focus = true;
    }
    fn settingsClick(self: *App, x: f32, y: f32) !void {
        const e = &self.settings_editor.?;
        const box = self.settingsRect();
        if (e.editing != null) {
            for (0..self.settingsToolbarCount()) |number| if (self.settingsToolbarButton(number).contains(x, y)) return self.settingsToolbarAction(number);
            return;
        }
        if (x >= box.x + box.width - 70 and y >= box.y and y < box.y + 40) return self.toggleSettings();
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
                e.selected = 0;
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
            e.query_len = 0;
            e.selected = 0;
            self.cancelComposition();
            return;
        }
        if (!body.contains(x, y)) return;
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        const row: usize = @intFromFloat(@floor((y - body.y) / self.settingsRowHeight()));
        const chosen = row + self.settingsStart(visible);
        if (row >= self.settingsVisible() or chosen >= visible) return;
        if (e.selected != chosen) e.delete_pending = null;
        e.selected = chosen;
        if (all[indices[chosen]].target == .set_default) e.profile = all[indices[chosen]].target.set_default;
        e.content_focus = true;
        const target_row = all[indices[chosen]];
        if ((target_row.target == .default_font or target_row.target == .default_profile or target_row.target == .theme) and (x < body.x + 36 or x >= body.x + body.width - 36)) {
            var key_event = std.mem.zeroes(c.SDL_KeyboardEvent);
            key_event.key = if (x < body.x + 36) c.SDLK_LEFT else c.SDLK_RIGHT;
            return self.settingsKey(key_event);
        }
        if (target_row.target == .set_default and x < body.x + body.width - 82) return;
        if (target_row.editable() and target_row.target != .default_font and target_row.target != .default_profile and target_row.target != .theme and x < body.x + body.width * 0.46) return;
        try self.activateSetting(target_row);
    }
    fn clippedText(self: *App, text: []const u8, rect: layout.Rect, x: f32) !void {
        return self.clippedTextColor(text, rect, x, (try self.uiPalette()).text);
    }
    fn clippedTextColor(self: *App, text: []const u8, rect: layout.Rect, x: f32, color: c.SDL_Color) !void {
        const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(rect.x)), .y = @intFromFloat(@floor(rect.y)), .w = @intFromFloat(@ceil(rect.width)), .h = @intFromFloat(@ceil(rect.height)) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
        defer clearClip(self.renderer);
        try self.drawTextTint(self.ui_fonts.faces[0], text, x, rect.y + 6, color);
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
        try self.drawText(settings.titles[@backingInt(e.page)], body.x, box.y + 18);
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
                try outline(self.renderer, button, colors.border);
                try self.clippedText(label, button, button.x + 8);
            }
        } else {
            const field = self.settingsField();
            try fill(self.renderer, field, if (e.search) colors.panel else colors.title);
            const text = if (e.search) e.query[0..e.query_len] else "Changes save automatically · Ctrl+F search";
            try self.clippedText(text, field, field.x + 6);
        }
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        e.selected = @min(e.selected, visible -| 1);
        const start = self.settingsStart(visible);
        for (indices[start..@min(visible, start + self.settingsVisible())], start..) |index, number| {
            const row = all[index];
            const rect: layout.Rect = .{ .x = body.x, .y = body.y + @as(f32, @floatFromInt(number - start)) * self.settingsRowHeight(), .width = body.width - 8, .height = self.settingsRowHeight() - 4 };
            if (number == e.selected and e.content_focus) try fill(self.renderer, rect, colors.active);
            try outline(self.renderer, rect, if (number == e.selected and e.content_focus) colors.accent else colors.border);
            var label: [192]u8 = undefined;
            const name = if (row.scope.len == 0 or !e.search) row.label else try std.fmt.bufPrint(&label, "{s} / {s}", .{ row.scope, row.label });
            var value: [32]u8 = undefined;
            const raw_contents = if (number == e.selected and e.editing != null) (if (e.recording) "Press a shortcut — Esc cancels" else e.buffer[0..e.len]) else try row.text(self.configuration, &value);
            const contents = if (raw_contents.len != 0 or (number == e.selected and e.editing != null)) raw_contents else switch (row.target) {
                .binding => "Unbound",
                .font => "Inherited",
                .profile => |field| switch (field.field) {
                    .command => "Interactive shell",
                    .shell, .cwd, .font_pixels => "Inherited",
                    .name => "",
                },
                else => "",
            };
            const left: layout.Rect = .{ .x = rect.x + 6, .y = rect.y, .width = @max(1, rect.width * 0.46 - 12), .height = rect.height };
            const right: layout.Rect = .{ .x = rect.x + rect.width * 0.46, .y = rect.y, .width = @max(1, rect.width * 0.54 - 6), .height = rect.height };
            if (row.target == .default_font or row.target == .default_profile or row.target == .theme) {
                try self.clippedText(if (row.target == .default_font) "-" else "<", .{ .x = rect.x, .y = rect.y, .width = 36, .height = rect.height }, rect.x + 12);
                try self.clippedText(row.label, .{ .x = rect.x + 40, .y = rect.y - 2, .width = @max(1, rect.width - 80), .height = 22 }, rect.x + 48);
                try self.clippedText(contents, .{ .x = rect.x + 40, .y = rect.y + 18, .width = @max(1, rect.width - 80), .height = 24 }, rect.x + 48);
                try self.clippedText(if (row.target == .default_font) "+" else ">", .{ .x = rect.x + rect.width - 36, .y = rect.y, .width = 36, .height = rect.height }, rect.x + rect.width - 24);
            } else if (row.target == .set_default and !e.search) {
                try self.clippedText(row.label, .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - 94), .height = rect.height }, rect.x + 8);
                try self.clippedText("Edit", .{ .x = rect.x + rect.width - 74, .y = rect.y, .width = 70, .height = rect.height }, rect.x + rect.width - 66);
            } else {
                try self.clippedText(name, left, left.x);
                try self.clippedTextColor(contents, right, right.x, if (row.target == .information) colors.muted else colors.text);
            }
        }
        if (visible > self.settingsVisible()) {
            const tall = body.height * @as(f32, @floatFromInt(self.settingsVisible())) / @as(f32, @floatFromInt(visible));
            const offset = @as(f32, @floatFromInt(start)) / @as(f32, @floatFromInt(visible - self.settingsVisible()));
            try fill(self.renderer, .{ .x = body.x + body.width - 3, .y = body.y, .width = 3, .height = body.height }, colors.idle);
            try fill(self.renderer, .{ .x = body.x + body.width - 3, .y = body.y + offset * (body.height - tall), .width = 3, .height = tall }, colors.accent);
        }
        if (e.page == .defaults) {
            const button: layout.Rect = .{ .x = body.x, .y = box.y + box.height - 96, .width = 136, .height = 30 };
            try fill(self.renderer, button, colors.idle);
            try outline(self.renderer, button, colors.border);
            try self.clippedText(if (e.profile == try self.configuration.defaultProfile()) "Default" else "Set default", button, button.x + 8);
        }
        try self.clippedText(if (e.page == .profiles and e.profile == 0) "Read-only template · Duplicate to customize" else "Enter edits · Tab focus · ↑↓ choose · Ctrl+F search", .{ .x = body.x, .y = box.y + box.height - 36, .width = body.width, .height = 30 }, body.x);
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
            x = clip.x + @min(@max(1, clip.width - 8), 6 + try self.textWidth(chooser.query[0..chooser.query_len]));
            y = clip.y + 6;
        } else if (self.settings_editor) |e| {
            if ((e.editing == null and !e.search) or e.recording) {
                if (!c.SDL_SetTextInputArea(self.window, null, 0)) return error.SDL;
                return;
            }
            clip = self.settingsField();
            const text = if (e.editing != null) e.buffer[0..e.len] else e.query[0..e.query_len];
            x = clip.x + @min(@max(1, clip.width - 8), 6 + try self.textWidth(text));
            y = clip.y + 6;
        } else if (self.palette) |p| {
            const box = self.paletteRect();
            clip = .{ .x = box.x + 12, .y = box.y + 12, .width = @max(1, box.width - 24), .height = 32 };
            x = @min(clip.x + try self.textWidth(p.query[0..p.len]), clip.x + clip.width - 1);
            y = box.y + 12;
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
            x = clip.x + @min(@max(1, clip.width - 8), 6 + try self.textWidth(editor.bytes[0..editor.len]));
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
    fn chromeEvent(self: *App, event_value: c.SDL_Event) !bool {
        if (event_value.type == c.SDL_EVENT_WINDOW_FOCUS_LOST) {
            self.pointer_buttons = 0;
            self.chrome_pressed = .none;
        }
        if (event_value.type == c.SDL_EVENT_WINDOW_MOUSE_LEAVE) self.chrome_hover = .none;
        if (event_value.type == c.SDL_EVENT_MOUSE_MOTION) {
            self.chrome_hover = chrome.buttonAt(event_value.motion.x, event_value.motion.y, self.width);
            return self.chrome_pressed != .none;
        }
        const down = event_value.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
        if (!down and event_value.type != c.SDL_EVENT_MOUSE_BUTTON_UP) return false;
        const event_button = event_value.button;
        if (event_button.button > 0 and event_button.button < 32) {
            const bit = @as(u32, 1) << @as(u5, @intCast(event_button.button));
            if (down) self.pointer_buttons |= bit else self.pointer_buttons &= ~bit;
        }
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
        if (down and event_button.button == c.SDL_BUTTON_RIGHT and chrome.caption(self.tab_count, self.width).contains(event_button.x, event_button.y)) {
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
        const close_width: f32 = if (self.tab_count > 1 and rect.width >= 96) 30 else 0;
        try self.clippedText(status.title[0..status.title_len], .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - close_width - 12), .height = rect.height }, rect.x + 8);
        if (close_width != 0) try self.drawText("×", rect.x + rect.width - 18, rect.y + 6);
    }
    fn drawWindowControls(self: *App) !void {
        const colors = try self.uiPalette();
        for ([_]chrome.Button{ .minimize, .maximize, .close }) |button| {
            const rect = chrome.control(button, self.width);
            if (self.chrome_hover == button) try fill(self.renderer, rect, if (button == .close) .{ .r = 184, .g = 46, .b = 56, .a = 255 } else colors.active);
            const color = if (self.chrome_hover == button) colors.text else colors.muted;
            // Switchyard's hand-tuned glyphs in a 42x26 box, centred in our caption.
            const y = rect.y + 8;
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
    fn draw(self: *App) !void {
        try self.desktopAttention();
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) return error.SDL;
        self.width = @floatFromInt(@max(1, width));
        self.height = @floatFromInt(@max(1, height));
        self.displayScale();
        const colors = try self.uiPalette();
        if (!c.SDL_SetRenderScale(self.renderer, self.scale, self.scale) or !c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_BLEND) or
            !c.SDL_SetRenderDrawColor(self.renderer, colors.window.r, colors.window.g, colors.window.b, colors.window.a) or !c.SDL_RenderClear(self.renderer)) return error.SDL;
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = self.width, .height = chrome.height }, colors.title);
        for (0..self.tab_count) |number| {
            const index: u8 = @intCast(number);
            const rect = chrome.tab(index, self.tab_count, self.width);
            if (self.drag == .tab and index == self.active) {
                try outline(self.renderer, rect, colors.border);
            } else try self.drawTab(index, rect);
        }
        if (self.drag == .tab) {
            var rect = chrome.tab(self.active, self.tab_count, self.width);
            rect.x = self.drag.tab.x;
            try self.drawTab(self.active, rect);
            try outline(self.renderer, rect, colors.accent);
        }
        for ([_]layout.Rect{ chrome.plus(self.tab_count, self.width), chrome.settings(self.width) }, [_][]const u8{ "+", "⋯" }) |rect, label| {
            try self.drawText(label, rect.x + 8, rect.y + 6);
        }
        try self.drawWindowControls();
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            const active = place.pane == self.tab().tree.active;
            try fill(self.renderer, place.rect, colors.panel);
            if (active and result.panes > 1) try outline(self.renderer, place.rect, colors.border);
            const rect = paneContent(place.rect);
            try fill(self.renderer, .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, colors.panel);
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
                if (p.graphics_failure == null) p.canvas.draw(self.renderer, self.geometry, placed, self.scale) catch |failure| {
                    p.graphics_failure = failure;
                };
                if (p.graphics_failure == null) {
                    try self.drawSelection(p, placed, frame);
                    clearClip(self.renderer);
                    try self.drawScrollbar(placed, frame);
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
    while (app.running) {
        try app.draw();
        app.selectionTick() catch |failure| app.report(failure);
        var event: c.SDL_Event = undefined;
        if (app.waitTimeout(c.SDL_GetTicks())) |timeout| {
            if (!c.SDL_WaitEventTimeout(&event, timeout)) continue;
        } else if (!c.SDL_WaitEvent(&event)) return error.SDL;
        while (true) {
            app.event(event) catch |failure| app.report(failure);
            if (!app.running or !c.SDL_PollEvent(&event)) break;
        }
    }
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
    return chrome.hit(@floatFromInt(point.*.x), @floatFromInt(point.*.y), @floatFromInt(width), @floatFromInt(height), app.tab_count, c.SDL_GetWindowFlags(window));
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
fn clearClip(renderer: *c.SDL_Renderer) void {
    const success = c.SDL_SetRenderClipRect(renderer, null);
    std.debug.assert(success);
}
fn paneContent(rect: layout.Rect) c.SDL_FRect {
    const x_padding = @min(3, rect.width / 4);
    const y_padding = @min(3, rect.height / 4);
    return .{ .x = rect.x + x_padding, .y = rect.y + y_padding, .w = rect.width - 2 * x_padding, .h = rect.height - 2 * y_padding };
}
// Centre only the accepted frame; available pane size remains the resize authority.
// Align the absolute origin to physical pixels, including the pane inset.
fn terminalPlacement(available: c.SDL_FRect, surface: instance.render.terminal.Size, scale: f32) c.SDL_FRect {
    const width = @min(available.w, @as(f32, @floatFromInt(surface.width)) / scale);
    const height = @min(available.h, @as(f32, @floatFromInt(surface.height)) / scale);
    return .{
        .x = std.math.clamp(@round((available.x + (available.w - width) / 2) * scale) / scale, available.x, available.x + available.w - width),
        .y = std.math.clamp(@round((available.y + (available.h - height) / 2) * scale) / scale, available.y, available.y + available.h - height),
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
    std.testing.refAllDecls(appearance);
}

test "command palette stays action-oriented while profile menu retains application entry points" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var p: Palette = .{};
    var indices: [keybindings.definitions.len]usize = undefined;
    const count = try p.indices(&configuration, &indices);
    try std.testing.expect(count > 0 and count < keybindings.definitions.len);
    for (indices[0..count]) |index| try std.testing.expect(keybindings.definitions[index].target == .action);
    const query = "FOCUS PANE";
    @memcpy(p.query[0..query.len], query);
    p.len = query.len;
    try std.testing.expectEqual(@as(usize, 0), try p.indices(&configuration, &indices));
    p = .{ .profile = true };
    try std.testing.expectEqual(@as(usize, 3), try p.indices(&configuration, &indices));
}

test "profile palette uses saved recipes and resolves its configured default" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"app_theme":"howl_dark","default_profile":"build","profiles":[{"id":"build","name":"Build shell","shell":"/bin/sh","command":"exec sh","font_pixels":19}]}
    );
    defer configuration.deinit();
    var p: Palette = .{ .profile = true };
    var indices: [keybindings.definitions.len]usize = undefined;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, &indices));
    @memcpy(p.query[0..5], "BUILD");
    p.len = 5;
    try std.testing.expectEqual(@as(usize, 1), try p.indices(&configuration, &indices));
    try std.testing.expectEqual(try configuration.defaultProfile(), indices[0]);
    const recipe = try configuration.profile(@intCast(indices[0]));
    try std.testing.expectEqualStrings("exec sh", recipe.command);
    try std.testing.expectEqual(@as(i32, 19), recipe.font_pixels);
}

test "tiny nested pane content never crosses its layout owner and has a bounded positive configuration surface" {
    for ([_]f32{ 0.125, 1, 4, 6, 40 }) |width| {
        const outer: layout.Rect = .{ .x = 10, .y = 20, .width = width, .height = 0.25 };
        const content = paneContent(outer);
        try std.testing.expect(content.x >= outer.x and content.x + content.w <= outer.x + outer.width);
        try std.testing.expect(content.y >= outer.y and content.y + content.h <= outer.y + outer.height);
        const surface = physicalSurface(outer, 1.7);
        try std.testing.expect(surface.width >= 1 and surface.height >= 1);
    }
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
    var fonts: font_owner.Fonts = .{ .allocator = test_allocator, .paths = @splat(@import("test_fonts").primary_font) };
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
    }, fonts.config(15), c.SDL_RegisterEvents(1), true);
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
    try app.event(event_value);
    try std.testing.expectEqualStrings("aéz", app.preedit.text());
    try std.testing.expectEqual(before, owner.snapshot().revision);
    try app.drawComposition();
    var area: c.SDL_Rect = undefined;
    var caret: c_int = 0;
    try std.testing.expect(c.SDL_GetTextInputArea(window, &area, &caret));
    try std.testing.expect(area.x > 9 and area.y > 43 and area.w > 0 and area.h > 0);
    try std.testing.expect(caret > 0 and caret < area.w);
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
    try app.openPalette(false);
    try std.testing.expectEqual(@as(usize, 0), app.preedit.len);
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
    try std.testing.expectEqual(@as(u8, 0), app.chooser.?.query_len);
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
    var fonts: font_owner.Fonts = .{ .allocator = a, .paths = @splat(@import("test_fonts").primary_font) };
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
        }, fonts.config(size), c.SDL_RegisterEvents(1), true);
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
    var fonts: font_owner.Fonts = .{ .allocator = a, .paths = @splat(@import("test_fonts").primary_font) };
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(a, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
    }, fonts.config(15), c.SDL_RegisterEvents(1), false);
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
    var fonts: font_owner.Fonts = .{ .allocator = a, .paths = @splat(@import("test_fonts").primary_font) };
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const owner = try terminal.Terminal.create(a, threaded.io(), provided, .{
        .shell = "/bin/sh",
        .command = "stty -echo; read line; printf '\\033]0;%s|%s|%s|%s\\007' \"$HOWL_BASE\" \"$HOWL_OVERRIDE\" \"$HOWL_EMPTY\" \"$TERM\"; sleep 30",
        .rows = 4,
        .columns = 20,
    }, fonts.config(15), c.SDL_RegisterEvents(1), false);
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

test "centred accepted terminal lattice shares slack, clips stale frames and maps input at fractional scale" {
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

test "pending drag requests retain accepted selection paint; accepted clear removes it" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(40, 20, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var p: Pane = .{ .recipe = undefined, .canvas = canvas.Canvas.init(std.testing.allocator), .selection_serial = 999 };
    defer p.canvas.deinit();
    p.canvas.selection_paint = .{ .serial = 11, .rows = 1 };
    p.canvas.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
    var app: App = .{ .init = undefined, .configuration = &configuration, .fonts = undefined, .window = undefined, .renderer = renderer, .ui_fonts = undefined, .geometry = undefined, .wake_event = 0, .scale = 1, .bindings = try keybindings.Bindings.init() };
    const frame: instance.PublishedFrame = .{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = .{ .width = 40, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
        .pixels = &.{},
    };
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    for ([_]bool{ false, true }) |cleared| {
        if (cleared) p.canvas.selection_paint = .{ .serial = 999 };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try app.drawSelection(&p, .{ .x = 0, .y = 0, .w = 40, .h = 20 }, frame);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 5, 5, &red, null, null, null));
        try std.testing.expect(if (cleared) red == 0 else red > 0);
        try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
    }
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
