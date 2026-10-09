const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const font_owner = @import("fonts.zig");
const terminal = @import("terminal.zig");
const canvas = @import("canvas.zig");
const layout = @import("layout.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const pointer = @import("pointer.zig");
const composition = @import("composition.zig");
const config = @import("config.zig");
const settings = @import("settings.zig");
const appearance = @import("appearance.zig");
const allocator = std.heap.smp_allocator;
const version = "0.1.6-dev";
const tab_limit = 8;
const GraphicsFailure = @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.update)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.draw)).@"fn".return_type.?).error_union.error_set;

const CreationError = @typeInfo(@typeInfo(@TypeOf(terminal.Terminal.create)).@"fn".return_type.?).error_union.error_set ||
    error{ AttachmentNotImplemented, EnvironmentOverridesUnsupported };
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
        const limit = if (self.profile) configuration.profileCount() else keybindings.definitions.len;
        for (0..limit) |i| {
            const label = if (self.profile) (try configuration.profile(@intCast(i))).name else keybindings.definitions[i].label;
            if (self.len != 0 and !containsIgnoreCase(label, self.query[0..self.len])) continue;
            out[count] = i;
            count += 1;
        }
        return count;
    }
};
const Drag = union(enum) { none, divider: layout.Divider, tab };
const PointerCapture = struct { pane: *Pane, buttons: u8, last: pointer.Location };
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
    bindings: keybindings.Bindings,
    palette: ?Palette = null,
    settings_editor: ?settings.Editor = null,
    drag: Drag = .none,
    consume_left_release: bool = false,
    focused: bool = false,
    running: bool = true,
    fullscreen: bool = false,
    width: f32 = 1000,
    height: f32 = 650,
    notice: [256]u8 = @splat(0),
    notice_len: usize = 0,

    fn deinit(self: *App) void {
        for (self.tabs[0..self.tab_count]) |value| self.destroyTab(value.?);
    }
    fn tab(self: *App) *Tab {
        return self.tabs[self.active].?;
    }
    fn pane(self: *App) *Pane {
        return self.tab().panes[self.tab().tree.active].?;
    }
    fn terminalBody(self: *const App) layout.Rect {
        return .{ .x = 6, .y = 40, .width = @max(1, self.width - 12), .height = @max(1, self.height - 68) };
    }
    fn tabWidth(self: *const App) f32 {
        return std.math.clamp((self.width - 100) / @as(f32, @floatFromInt(@max(1, self.tab_count))), 60, 200);
    }
    fn setNotice(self: *App, message: []const u8) void {
        self.notice_len = @min(message.len, self.notice.len);
        @memcpy(self.notice[0..self.notice_len], message[0..self.notice_len]);
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
        if (std.ascii.eqlIgnoreCase(recipe.mode, "attach")) return error.AttachmentNotImplemented;
        if (recipe.environment.len != 0) return error.EnvironmentOverridesUnsupported;
        const pixels: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(font_size)) * self.scale));
        return terminal.Terminal.create(allocator, self.init.io, self.init.minimal.environ, .{
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
        self.cancelComposition();
        try self.finishPointer();
        try self.keyboard.releaseTerminal();
        if (self.tab_count == 0 or !self.focused or (self.palette != null or self.settings_editor != null)) return;
        const owner = self.pane().owner orelse return;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .out } });
    }
    fn gainKeyboard(self: *App) !void {
        self.cancelComposition();
        if (self.tab_count == 0 or !self.focused or (self.palette != null or self.settings_editor != null)) return;
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
    fn dispatch(self: *App, target: keybindings.Target) !void {
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
                .open_local => try self.createTab(try self.configuration.profile(1), null),
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
                    if (!c.SDL_SetWindowFullscreen(self.window, !self.fullscreen)) return error.SDL;
                    self.fullscreen = !self.fullscreen;
                },
                .recover_instance => try self.recover(),
                .take_size_control => self.pane().size_control = true,
                .stop_resizing => self.pane().size_control = false,
                .open_command_palette => try self.openPalette(false),
                .open_profile_menu => try self.openPalette(true),
                .open_settings => try self.toggleSettings(),
                .attach_home => try self.createTab(try self.configuration.profile(0), null),
            },
            .select_tab => |index| try self.selectTab(index),
            .paste_clipboard => {
                const text = c.SDL_GetClipboardText() orelse return error.SDL;
                defer c.SDL_free(text);
                try self.pane().submit(.{ .input = .{ .paste = std.mem.span(text) } });
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
            .toggle_find => return error.FindNotImplemented,
            .adjust_font => |delta| {
                const p = self.pane();
                const next: u16 = @intCast(std.math.clamp(@as(i32, p.font_size) + delta, 8, 48));
                if (next != p.font_size) {
                    try self.configureFont(p, next, true);
                    p.font_overridden = true;
                }
            },
            .copy_selection => return error.SelectionNotImplemented,
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
        try candidate.saveAt(self.init.io, dir, target);
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
            const pages = settings.titles.len;
            e.page = @fromBackingInt(@intCast((@backingInt(e.page) + (if (mods.shift) pages - 1 else @as(usize, 1))) % pages));
            e.selected = 0;
            e.delete_pending = null;
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
                } else if (row.target == .profile and row.target.profile.field == .mode) {
                    const recipe = try self.configuration.profile(row.target.profile.index);
                    try self.changeSetting(row.target, if (std.ascii.eqlIgnoreCase(recipe.mode, "launch")) "attach" else "launch");
                }
            },
            else => {},
        }
    }
    fn newWindow(self: *App) !void {
        // Linux fork/exec resolves this exact running image even after an on-disk upgrade.
        var child = try std.process.spawn(self.init.io, .{ .argv = &.{"/proc/self/exe"} });
        errdefer child.kill(self.init.io);
        const thread = try std.Thread.spawn(.{}, reapWindow, .{child.id.?});
        thread.detach();
    }
    fn cancelDrag(self: *App) void {
        if (self.drag == .none) return;
        self.drag = .none;
        self.consume_left_release = true;
    }
    fn choosePalette(self: *App, index: usize) !void {
        if (!self.palette.?.profile) return self.dispatch(keybindings.definitions[index].target);
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
    fn event(self: *App, value: c.SDL_Event) !void {
        self.input_timestamp = value.common.timestamp;
        switch (value.type) {
            c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.running = false,
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                const press = value.type == c.SDL_EVENT_KEY_DOWN;
                if (press) self.cancelDrag();
                const mapping = self.bindings.find(value.key.key, value.key.mod);
                const command = if (mapping) |index| blk: {
                    const target = keybindings.definitions[index].target;
                    if (self.settings_editor) |e| {
                        if (e.editing != null or !(target == .action and target.action == .open_settings)) break :blk null;
                    }
                    break :blk target;
                } else null;
                const route = try self.keyboard.route(value.key, press, self.pane().owner, command, self.palette != null or self.settings_editor != null);
                switch (route) {
                    .handled => {},
                    .command => |target| try self.dispatch(target),
                    .overlay => if (self.settings_editor != null) try self.settingsKey(value.key) else try self.paletteKey(value.key.key),
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
                if (self.settings_editor) |*e| {
                    if (!e.recording) try e.append(text);
                } else if (self.palette) |*p| {
                    if (text.len <= p.query.len - p.len) {
                        @memcpy(p.query[p.len..][0..text.len], text);
                        p.len += text.len;
                        p.selected = 0;
                    }
                } else try self.pane().submit(.{ .input = .{ .bytes = text } });
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (mouseButton(value.button.button)) |button|
                try self.pointerDown(value.button.x, value.button.y, button, input.semanticModifiers(c.SDL_GetModState())),
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button = mouseButton(value.button.button) orelse return;
                if (button == .left and self.consume_left_release) {
                    self.consume_left_release = false;
                    return;
                }
                if (self.capture != null) try self.pointerRelease(button, value.button.x, value.button.y, input.semanticModifiers(c.SDL_GetModState()));
                if (button == .left) self.drag = .none;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                if (self.capture) |*held| {
                    const point = self.pointerLocation(held.pane, value.motion.x, value.motion.y, true) orelse held.last;
                    try held.pane.submit(.{ .input = point.event(.move, .none, input.semanticModifiers(c.SDL_GetModState()), held.buttons) });
                    held.last = point;
                } else if (self.drag == .divider) {
                    self.tab().tree.drag(self.drag.divider, value.motion.x, value.motion.y);
                } else if (self.drag == .tab and value.motion.y < 40 and self.tab_count > 1) {
                    const index: u8 = @intFromFloat(std.math.clamp(@floor((value.motion.x - 8) / self.tabWidth()), 0, @as(f32, @floatFromInt(self.tab_count - 1))));
                    self.moveTab(index);
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
    fn pointerDown(self: *App, x: f32, y: f32, button: instance.MouseButton, mods: instance.InputModifier) !void {
        if (self.capture) |held| {
            const point = self.pointerLocation(held.pane, x, y, true) orelse held.last;
            return self.pointerPress(held.pane, point, button, mods);
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
            } else if (y >= box.y + 48) {
                const row: usize = @intFromFloat(@floor((y - box.y - 48) / 26));
                const start = self.paletteStart(count);
                if (row < 16 and row + start < count) try self.choosePalette(matches[row + start]);
            }
            return;
        }
        if (y < 36) {
            if (button != .left) return;
            const width = self.tabWidth();
            if (x >= 8 and x < 8 + width * @as(f32, @floatFromInt(self.tab_count))) {
                const index: u8 = @intFromFloat(@floor((x - 8) / width));
                try self.selectTab(index);
                if (x >= 8 + width * @as(f32, @floatFromInt(index + 1)) - 22) {
                    try self.closeTab();
                } else self.drag = .tab;
            } else if (x < 8 + width * @as(f32, @floatFromInt(self.tab_count)) + 32) {
                try self.createTab(try self.startup(), null);
            } else try self.openPalette(false);
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
            const frame = p.canvas.frame() orelse return;
            const state = p.snapshot().interaction orelse return;
            if (!mods.shift and frame.history_offset == 0 and state.mouse_tracking != .off) {
                const point = self.pointerLocation(p, x, y, false) orelse return;
                try self.pointerPress(p, point, button, mods);
            }
            return;
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
            const rect = paneContent(place.rect);
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
        if ((self.palette != null or self.settings_editor != null)) return;
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
    fn paletteRect(self: *const App) layout.Rect {
        const width = @min(600, @max(1, self.width - 24));
        return .{ .x = (self.width - width) / 2, .y = 52, .width = width, .height = @min(474, @max(1, self.height - 88)) };
    }
    fn paletteStart(self: *const App, count: usize) usize {
        const selected = @min(self.palette.?.selected, count -| 1);
        return if (selected >= 16) selected - 15 else 0;
    }
    fn drawPalette(self: *App) !void {
        var matches: [keybindings.definitions.len]usize = undefined;
        const count = try self.palette.?.indices(self.configuration, &matches);
        const box = self.paletteRect();
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = self.width, .height = self.height }, .{ .r = 0, .g = 0, .b = 0, .a = 155 });
        try fill(self.renderer, box, .{ .r = 39, .g = 42, .b = 56, .a = 255 });
        try self.drawText(if (self.palette.?.len != 0) self.palette.?.query[0..self.palette.?.len] else if (self.palette.?.profile) "Profiles — type to filter" else "Commands — type to filter", box.x + 12, box.y + 12);
        const start = self.paletteStart(count);
        const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(box.x)), .y = @intFromFloat(@floor(box.y + 48)), .w = @intFromFloat(@ceil(box.width)), .h = @intFromFloat(@ceil(@max(1, box.height - 48))) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
        defer clearClip(self.renderer);
        for (matches[start..@min(count, start + 16)], start..) |index, row| {
            const y = box.y + 48 + @as(f32, @floatFromInt(row - start)) * 26;
            if (row == self.palette.?.selected) try fill(self.renderer, .{ .x = box.x + 4, .y = y, .width = box.width - 8, .height = 26 }, .{ .r = 65, .g = 71, .b = 96, .a = 255 });
            if (self.palette.?.profile) {
                const recipe = try self.configuration.profile(@intCast(index));
                try self.drawText(recipe.name, box.x + 12, y + 4);
                if (index == try self.configuration.defaultProfile()) try self.drawText("default", box.x + box.width - 90, y + 4);
            } else {
                try self.drawText(keybindings.definitions[index].label, box.x + 12, y + 4);
                const binding = self.bindings.rows[index];
                if (binding.len != 0) try self.drawText(binding.text[0..binding.len], box.x + box.width - 174, y + 4);
            }
        }
    }
    fn settingsRect(self: *const App) layout.Rect {
        const width = @min(900, @max(1, self.width - 24));
        return .{ .x = (self.width - width) / 2, .y = 44, .width = width, .height = @max(1, self.height - 66) };
    }
    fn settingsBody(self: *const App) layout.Rect {
        const box = self.settingsRect();
        const sidebar = @min(180, box.width / 3);
        return .{ .x = box.x + sidebar + 12, .y = box.y + 88, .width = @max(1, box.width - sidebar - 24), .height = @max(1, box.height - 132) };
    }
    fn settingsField(self: *const App) layout.Rect {
        const box = self.settingsRect();
        const body = self.settingsBody();
        return .{ .x = body.x, .y = box.y + 44, .width = body.width, .height = 32 };
    }
    fn settingsVisible(self: *const App) usize {
        return @max(1, @as(usize, @intFromFloat(@floor(self.settingsBody().height / 32))));
    }
    fn settingsStart(self: *const App, count: usize) usize {
        const selected = @min(self.settings_editor.?.selected, count -| 1);
        return (selected + 1) -| self.settingsVisible();
    }
    fn settingsClick(self: *App, x: f32, y: f32) !void {
        const e = &self.settings_editor.?;
        const box = self.settingsRect();
        if (e.editing != null) return;
        if (!box.contains(x, y) or (x >= box.x + box.width - 70 and y < box.y + 36)) return self.toggleSettings();
        const body = self.settingsBody();
        if (x < body.x - 12 and y >= box.y + 48) {
            const page: usize = @intFromFloat(@floor((y - box.y - 48) / 34));
            if (page < settings.titles.len) {
                self.cancelComposition();
                e.page = @fromBackingInt(@intCast(page));
                e.search = false;
                e.query_len = 0;
                e.selected = 0;
                e.delete_pending = null;
            }
            return;
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
        const row: usize = @intFromFloat(@floor((y - body.y) / 32));
        const chosen = row + self.settingsStart(visible);
        if (row >= self.settingsVisible() or chosen >= visible) return;
        if (e.selected != chosen) e.delete_pending = null;
        e.selected = chosen;
        try self.activateSetting(all[indices[chosen]]);
    }
    fn clippedText(self: *App, text: []const u8, rect: layout.Rect, x: f32) !void {
        const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(rect.x)), .y = @intFromFloat(@floor(rect.y)), .w = @intFromFloat(@ceil(rect.width)), .h = @intFromFloat(@ceil(rect.height)) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
        defer clearClip(self.renderer);
        try self.drawText(text, x, rect.y + 6);
    }
    fn drawSettings(self: *App) !void {
        const e = &self.settings_editor.?;
        const colors = try self.uiPalette();
        const box = self.settingsRect();
        const body = self.settingsBody();
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = self.width, .height = self.height }, .{ .r = 0, .g = 0, .b = 0, .a = 180 });
        try fill(self.renderer, box, colors.panel);
        try self.drawText("Settings", box.x + 12, box.y + 12);
        try self.drawText("Close", box.x + box.width - 60, box.y + 12);
        for (settings.titles, 0..) |title, index| {
            const row: layout.Rect = .{ .x = box.x + 6, .y = box.y + 48 + @as(f32, @floatFromInt(index)) * 34, .width = @max(1, body.x - box.x - 24), .height = 32 };
            if (!e.search and @backingInt(e.page) == index) try fill(self.renderer, row, colors.active);
            try self.clippedText(title, row, row.x + 6);
        }
        const field = self.settingsField();
        try fill(self.renderer, field, colors.title);
        const text = if (e.editing != null) e.buffer[0..e.len] else if (e.search) e.query[0..e.query_len] else "Search settings — Ctrl+F";
        const scroll = if (e.editing != null or e.search) @max(0, try self.textWidth(text) - field.width + 12) else 0;
        try self.clippedText(if (e.recording) "Press a shortcut — Esc cancels" else text, field, field.x + 6 - scroll);
        if (e.select_all) try fill(self.renderer, .{ .x = field.x + 4, .y = field.y + 2, .width = @max(1, field.width - 8), .height = 2 }, colors.accent);
        var all: [settings.row_limit]settings.Row = undefined;
        var indices: [settings.row_limit]u16 = undefined;
        const count = try settings.rows(self.configuration, &all);
        const visible = e.indices(all[0..count], &indices);
        e.selected = @min(e.selected, visible -| 1);
        const start = self.settingsStart(visible);
        for (indices[start..@min(visible, start + self.settingsVisible())], start..) |index, number| {
            const row = all[index];
            const rect: layout.Rect = .{ .x = body.x, .y = body.y + @as(f32, @floatFromInt(number - start)) * 32, .width = body.width, .height = 30 };
            if (number == e.selected) try fill(self.renderer, rect, colors.active);
            var label: [192]u8 = undefined;
            const name = if (row.scope.len == 0) row.label else try std.fmt.bufPrint(&label, "{s} / {s}", .{ row.scope, row.label });
            var value: [32]u8 = undefined;
            const contents = try row.text(self.configuration, &value);
            const left: layout.Rect = .{ .x = rect.x + 6, .y = rect.y, .width = @max(1, rect.width * 0.52 - 12), .height = rect.height };
            const right: layout.Rect = .{ .x = rect.x + rect.width * 0.52, .y = rect.y, .width = @max(1, rect.width * 0.48 - 6), .height = rect.height };
            try self.clippedText(name, left, left.x);
            try self.clippedText(contents, right, right.x);
        }
        try self.clippedText("Enter edits · Tab page · ↑↓ choose · Backspace resets · Ctrl+F search", .{ .x = body.x, .y = box.y + box.height - 36, .width = body.width, .height = 30 }, body.x);
    }
    fn drawText(self: *App, bytes: []const u8, x: f32, y: f32) !void {
        if (bytes.len == 0) return;
        const surface = c.TTF_RenderText_Blended(self.ui_fonts.faces[0], bytes.ptr, bytes.len, (try self.uiPalette()).text) orelse return error.TTF;
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
        if (self.settings_editor) |e| {
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
            clip = .{ .x = box.x + 12, .y = box.y + 8, .width = @max(1, box.width - 24), .height = 32 };
            x = @min(clip.x + try self.textWidth(p.query[0..p.len]), clip.x + clip.width - 1);
            y = box.y + 12;
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
                const rect = paneContent(place.rect);
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
        try fill(self.renderer, .{ .x = x, .y = y + cell_height - 1, .width = @min(available, @max(2, text_width)), .height = 1 }, .{ .r = 130, .g = 170, .b = 255, .a = 255 });
    }
    fn draw(self: *App) !void {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) return error.SDL;
        self.width = @floatFromInt(@max(1, width));
        self.height = @floatFromInt(@max(1, height));
        self.displayScale();
        const colors = try self.uiPalette();
        if (!c.SDL_SetRenderScale(self.renderer, self.scale, self.scale) or !c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_BLEND) or
            !c.SDL_SetRenderDrawColor(self.renderer, colors.window.r, colors.window.g, colors.window.b, colors.window.a) or !c.SDL_RenderClear(self.renderer)) return error.SDL;
        const tab_width = self.tabWidth();
        for (self.tabs[0..self.tab_count], 0..) |maybe, index| {
            const value = maybe.?;
            const status = value.panes[value.tree.active].?.snapshot();
            const rect: layout.Rect = .{ .x = 8 + tab_width * @as(f32, @floatFromInt(index)), .y = 4, .width = tab_width - 3, .height = 30 };
            try fill(self.renderer, rect, if (index == self.active) colors.active else colors.idle);
            const title_clip: c.SDL_Rect = .{ .x = @intFromFloat(rect.x + 4), .y = 4, .w = @intFromFloat(@max(1, rect.width - 28)), .h = 30 };
            if (!c.SDL_SetRenderClipRect(self.renderer, &title_clip)) return error.SDL;
            try self.drawText(status.title[0..status.title_len], rect.x + 8, 10);
            clearClip(self.renderer);
            try self.drawText("×", rect.x + rect.width - 18, 10);
        }
        const after_tabs = 8 + tab_width * @as(f32, @floatFromInt(self.tab_count));
        try self.drawText("+", after_tabs + 8, 10);
        try self.drawText("⋯", self.width - 32, 10);
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.terminalBody(), &places, &dividers);
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            const active = place.pane == self.tab().tree.active;
            try fill(self.renderer, place.rect, if (active) colors.accent else colors.border);
            const rect = paneContent(place.rect);
            try fill(self.renderer, .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, colors.panel);
            if (p.graphics_failure == null) {
                if (p.owner) |owner| p.canvas.update(self.renderer, owner) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            const status = p.snapshot();
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
                if (p.graphics_failure == null) p.canvas.draw(self.renderer, self.geometry, rect, self.scale) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            clearClip(self.renderer);
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
        try self.drawText(if (self.notice_len == 0) (try savedRecipe(self.configuration, self.pane().recipe.value)).name else self.notice[0..self.notice_len], 10, self.height - 22);
        if (self.palette != null) try self.drawPalette();
        if (self.settings_editor != null) try self.drawSettings();
        try self.drawComposition();
        if (!c.SDL_RenderPresent(self.renderer)) return error.SDL;
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            if (p.graphics_failure == null) if (p.owner) |owner| owner.requestFrame();
        }
    }
};

/// Owns SDL/application lifetime and graphical leases; terminal workers retain canonical authority.
pub fn main(init: std.process.Init) !void {
    const args = init.minimal.args.vector;
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--version")) {
        std.debug.print("Howl {s} (Zig SDL app)\n", .{version});
        return;
    }
    if (args.len != 1) return error.InvalidArguments;
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
    try app.createTab(try app.startup(), null);
    while (app.running) {
        try app.draw();
        var event: c.SDL_Event = undefined;
        if (!c.SDL_WaitEvent(&event)) return error.SDL;
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
fn savedRecipe(current: *const config.Config, owned: config.Profile) !config.Profile {
    for (0..current.profileCount()) |index| {
        const value = try current.profile(@intCast(index));
        if (std.mem.eql(u8, value.id, owned.id)) return value;
    }
    return owned;
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

test "palette query is bounded and includes deliberately unbound directional commands" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var p: Palette = .{};
    var indices: [keybindings.definitions.len]usize = undefined;
    try std.testing.expectEqual(keybindings.definitions.len, try p.indices(&configuration, &indices));
    const query = "FOCUS PANE";
    @memcpy(p.query[0..query.len], query);
    p.len = query.len;
    try std.testing.expectEqual(@as(usize, 4), try p.indices(&configuration, &indices));
    for (indices[0..4]) |index| try std.testing.expect(keybindings.definitions[index].target == .pane_focus);
    p = .{ .profile = true };
    try std.testing.expectEqual(@as(usize, 2), try p.indices(&configuration, &indices));
}

test "profile palette uses saved recipes and resolves its configured default" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":4,"terminal_font_pixels":15,"app_theme":"howl_dark","default_profile":"build","profiles":[{"id":"build","name":"Build shell","mode":"launch","shell":"/bin/sh","command":"exec sh","font_pixels":19}]}
    );
    defer configuration.deinit();
    var p: Palette = .{ .profile = true };
    var indices: [keybindings.definitions.len]usize = undefined;
    try std.testing.expectEqual(@as(usize, 3), try p.indices(&configuration, &indices));
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
    var p: Pane = .{ .owner = owner, .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(1)), .canvas = canvas.Canvas.init(test_allocator) };
    defer p.recipe.deinit();
    defer p.canvas.deinit();
    var t: Tab = .{ .recipe = try config.Recipe.copy(test_allocator, try configuration.profile(1)) };
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
        var recipe = try config.Recipe.copy(a, try current.profile(1));
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
    var t: Tab = .{ .recipe = try config.Recipe.copy(a, try current.profile(1)) };
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
    try app.applyConfigurationAt(&candidate, temporary.dir, "odin.json");
    try std.testing.expectEqual(@as(i32, 23), current.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u16, 23), panes[0].font_size);
    try std.testing.expectEqual(@as(u16, 17), panes[1].font_size);
    try std.testing.expect(panes[1].font_overridden);
    var reopened = try config.Config.loadAt(a, threaded.io(), temporary.dir, "odin.json");
    defer reopened.deinit();
    try std.testing.expectEqual(@as(i32, 23), reopened.value.terminal_font_pixels);
}
