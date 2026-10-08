const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const font_owner = @import("fonts.zig");
const terminal = @import("terminal.zig");
const canvas = @import("canvas.zig");
const layout = @import("layout.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const allocator = std.heap.smp_allocator;
const version = "0.1.6-dev";
const tab_limit = 8;
const GraphicsFailure = @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.update)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(canvas.Canvas.draw)).@"fn".return_type.?).error_union.error_set;

const Pane = struct {
    owner: *terminal.Terminal,
    canvas: canvas.Canvas,
    rows: u16 = 0,
    columns: u16 = 0,
    size_control: bool = true,
    graphics_failure: ?GraphicsFailure = null,
};
const Tab = struct {
    tree: layout.Tree = layout.Tree.init(),
    panes: [layout.pane_limit]?*Pane = @splat(null),
};
const Palette = struct {
    query: [128]u8 = @splat(0),
    len: usize = 0,
    selected: usize = 0,
    profile: bool = false,

    fn matches(self: *const Palette, index: usize) bool {
        if (self.profile) return keybindings.definitions[index].target == .action and
            (keybindings.definitions[index].target.action == .open_local or keybindings.definitions[index].target.action == .attach_home);
        return self.len == 0 or containsIgnoreCase(keybindings.definitions[index].label, self.query[0..self.len]);
    }
    fn indices(self: *const Palette, out: *[keybindings.definitions.len]usize) usize {
        var count: usize = 0;
        for (keybindings.definitions, 0..) |_, i| if (self.matches(i)) {
            out[count] = i;
            count += 1;
        };
        return count;
    }
};
const Drag = union(enum) { none, divider: layout.Divider, tab };
const App = struct {
    init: std.process.Init,
    fonts: *const font_owner.Fonts,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    ui_font: *c.TTF_Font,
    geometry: *canvas.Geometry,
    wake_event: u32,
    scale: f32,
    tabs: [tab_limit]?*Tab = @splat(null),
    tab_count: u8 = 0,
    active: u8 = 0,
    keyboard: input.Keyboard = .{},
    bindings: keybindings.Bindings,
    palette: ?Palette = null,
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
    fn body(self: *const App) layout.Rect {
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
    fn createPane(self: *App) !*Pane {
        const result = try allocator.create(Pane);
        errdefer allocator.destroy(result);
        const font_size: u16 = @intFromFloat(@round(15 * self.scale));
        result.* = .{
            .owner = try terminal.Terminal.create(allocator, self.init.io, self.init.minimal.environ, .{
                .shell = self.init.environ_map.get("SHELL") orelse "/bin/sh",
                .rows = 37,
                .columns = 80,
            }, self.fonts.config(font_size), self.wake_event, false),
            .canvas = canvas.Canvas.init(allocator),
        };
        return result;
    }
    fn destroyPane(self: *App, value: *Pane) void {
        self.keyboard.forget(value.owner);
        value.canvas.deinit();
        value.owner.destroy();
        allocator.destroy(value);
    }
    fn destroyTab(self: *App, value: *Tab) void {
        for (value.panes) |maybe| if (maybe) |p| self.destroyPane(p);
        allocator.destroy(value);
    }
    fn loseKeyboard(self: *App) !void {
        try self.keyboard.releaseTerminal();
        if (self.tab_count == 0 or !self.focused or self.palette != null) return;
        const owner = self.pane().owner;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .out } });
    }
    fn gainKeyboard(self: *App) !void {
        if (self.tab_count == 0 or !self.focused or self.palette != null) return;
        const owner = self.pane().owner;
        const status = owner.snapshot();
        if (status.failure == null and !status.closed) try owner.submit(.{ .input = .{ .focus = .in } });
    }
    fn syncVisible(self: *App) void {
        for (self.tabs[0..self.tab_count], 0..) |maybe, index| {
            const t = maybe.?;
            for (t.panes, 0..) |maybe_p, slot| if (maybe_p) |p|
                p.owner.setVisible(index == self.active and (!t.tree.zoomed or slot == t.tree.active));
        }
    }
    fn selectTab(self: *App, index: u8) !void {
        if (index >= self.tab_count or index == self.active) return;
        try self.loseKeyboard();
        self.active = index;
        self.syncVisible();
        try self.gainKeyboard();
    }
    fn createTab(self: *App) !void {
        if (self.tab_count == tab_limit) return error.TabLimit;
        const value = try allocator.create(Tab);
        errdefer allocator.destroy(value);
        value.* = .{};
        value.panes[0] = try self.createPane();
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
        const value = try self.createPane();
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
        const status = previous.owner.snapshot();
        if (status.failure == null and !status.closed) {
            if (previous.graphics_failure != null) {
                previous.canvas.deinit();
                previous.canvas = canvas.Canvas.init(allocator);
                previous.graphics_failure = null;
            }
            try previous.owner.submit(.retry_render);
            return;
        }
        const next = try self.createPane();
        errdefer self.destroyPane(next);
        try self.loseKeyboard();
        self.tab().panes[self.tab().tree.active] = next;
        self.destroyPane(previous);
        self.syncVisible();
        self.gainKeyboard() catch |failure| self.report(failure);
    }
    fn dispatch(self: *App, target: keybindings.Target) !void {
        self.notice_len = 0;
        if (self.palette != null and !(target == .action and
            (target.action == .open_command_palette or target.action == .open_profile_menu)))
        {
            self.palette = null;
            try self.gainKeyboard();
        }
        switch (target) {
            .action => |action| switch (action) {
                .new_tab, .duplicate_tab, .open_local => try self.createTab(),
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
                .open_settings => return error.SettingsNotImplemented,
                .attach_home => return error.HomeAttachmentNotImplemented,
            },
            .select_tab => |index| try self.selectTab(index),
            .paste_clipboard => {
                const text = c.SDL_GetClipboardText() orelse return error.SDL;
                defer c.SDL_free(text);
                try self.pane().owner.submit(.{ .input = .{ .paste = std.mem.span(text) } });
            },
            .history_oldest => try self.pane().owner.submit(.{ .seek = std.math.maxInt(u32) }),
            .history_live => try self.pane().owner.submit(.{ .seek = 0 }),
            .history_page => |direction| try self.pane().owner.submit(.{ .scroll = @as(i32, @intCast(@max(1, self.pane().rows))) * direction }),
            .pane_focus => |direction| if (self.tab().tree.neighbor(self.body(), direction)) |slot| try self.focusPane(slot),
            .pane_swap => |direction| {
                if (self.tab().tree.neighbor(self.body(), direction)) |slot| {
                    const changed = self.tab().tree.swap(slot);
                    std.debug.assert(changed);
                }
            },
            .pane_resize => |direction| {
                const changed = self.tab().tree.resize(direction);
                if (!changed) self.setNotice("No divider in that direction");
            },
            .toggle_find => return error.FindNotImplemented,
            .adjust_font => return error.FontChangeNotImplemented,
            .copy_selection => return error.SelectionNotImplemented,
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
    fn paletteKey(self: *App, key: c.SDL_Keycode) !void {
        var matches: [keybindings.definitions.len]usize = undefined;
        const count = self.palette.?.indices(&matches);
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
            c.SDLK_RETURN => if (count != 0) try self.dispatch(keybindings.definitions[matches[@min(self.palette.?.selected, count - 1)]].target),
            else => {},
        }
    }
    fn event(self: *App, value: c.SDL_Event) !void {
        switch (value.type) {
            c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.running = false,
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                const press = value.type == c.SDL_EVENT_KEY_DOWN;
                if (press) self.cancelDrag();
                const mapping = self.bindings.find(value.key.key, value.key.mod);
                const command = if (mapping) |index| keybindings.definitions[index].target else null;
                const route = try self.keyboard.route(value.key, press, self.pane().owner, command, self.palette != null);
                switch (route) {
                    .handled => {},
                    .command => |target| try self.dispatch(target),
                    .overlay => try self.paletteKey(value.key.key),
                }
            },
            c.SDL_EVENT_TEXT_INPUT => {
                if (self.keyboard.consumeText()) return;
                const text = std.mem.span(value.text.text);
                if (self.palette) |*p| {
                    if (!p.profile and text.len <= p.query.len - p.len) {
                        @memcpy(p.query[p.len..][0..text.len], text);
                        p.len += text.len;
                        p.selected = 0;
                    }
                } else try self.pane().owner.submit(.{ .input = .{ .bytes = text } });
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (value.button.button == c.SDL_BUTTON_LEFT) try self.pointerDown(value.button.x, value.button.y),
            c.SDL_EVENT_MOUSE_BUTTON_UP => if (value.button.button == c.SDL_BUTTON_LEFT) {
                if (self.consume_left_release) self.consume_left_release = false;
                self.drag = .none;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                if (self.drag == .divider) self.tab().tree.drag(self.drag.divider, value.motion.x, value.motion.y);
                if (self.drag == .tab and value.motion.y < 40 and self.tab_count > 1) {
                    const index: u8 = @intFromFloat(std.math.clamp(@floor((value.motion.x - 8) / self.tabWidth()), 0, @as(f32, @floatFromInt(self.tab_count - 1))));
                    self.moveTab(index);
                }
            },
            c.SDL_EVENT_MOUSE_WHEEL => {
                if (self.palette != null) return;
                try self.pane().owner.submit(.{ .scroll = @intFromFloat(std.math.clamp(@round(value.wheel.y * 3), -1000, 1000)) });
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
    fn pointerDown(self: *App, x: f32, y: f32) !void {
        if (self.palette != null) {
            var matches: [keybindings.definitions.len]usize = undefined;
            const count = self.palette.?.indices(&matches);
            const box = self.paletteRect();
            if (!box.contains(x, y)) {
                self.palette = null;
                try self.gainKeyboard();
            } else if (y >= box.y + 48) {
                const row: usize = @intFromFloat(@floor((y - box.y - 48) / 26));
                const start = self.paletteStart(count);
                if (row < 16 and row + start < count) try self.dispatch(keybindings.definitions[matches[row + start]].target);
            }
            return;
        }
        if (y < 36) {
            const width = self.tabWidth();
            if (x >= 8 and x < 8 + width * @as(f32, @floatFromInt(self.tab_count))) {
                const index: u8 = @intFromFloat(@floor((x - 8) / width));
                try self.selectTab(index);
                if (x >= 8 + width * @as(f32, @floatFromInt(index + 1)) - 22) {
                    try self.closeTab();
                } else self.drag = .tab;
            } else if (x < 8 + width * @as(f32, @floatFromInt(self.tab_count)) + 32) {
                try self.createTab();
            } else try self.openPalette(false);
            return;
        }
        var places: [layout.pane_limit]layout.Placement = undefined;
        var dividers: [layout.pane_limit - 1]layout.Divider = undefined;
        const result = self.tab().tree.layout(self.body(), &places, &dividers);
        for (dividers[0..result.dividers]) |divider| if (divider.rect.contains(x, y)) {
            self.drag = .{ .divider = divider };
            return;
        };
        for (places[0..result.panes]) |place| if (place.rect.contains(x, y)) {
            try self.focusPane(place.pane);
            return;
        };
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
        const count = self.palette.?.indices(&matches);
        const box = self.paletteRect();
        try fill(self.renderer, .{ .x = 0, .y = 0, .width = self.width, .height = self.height }, .{ .r = 0, .g = 0, .b = 0, .a = 155 });
        try fill(self.renderer, box, .{ .r = 39, .g = 42, .b = 56, .a = 255 });
        try self.drawText(if (self.palette.?.profile) "Profiles" else if (self.palette.?.len == 0) "Commands — type to filter" else self.palette.?.query[0..self.palette.?.len], box.x + 12, box.y + 12);
        const start = self.paletteStart(count);
        const clip: c.SDL_Rect = .{ .x = @intFromFloat(@floor(box.x)), .y = @intFromFloat(@floor(box.y + 48)), .w = @intFromFloat(@ceil(box.width)), .h = @intFromFloat(@ceil(@max(1, box.height - 48))) };
        if (!c.SDL_SetRenderClipRect(self.renderer, &clip)) return error.SDL;
        defer clearClip(self.renderer);
        for (matches[start..@min(count, start + 16)], start..) |index, row| {
            const y = box.y + 48 + @as(f32, @floatFromInt(row - start)) * 26;
            if (row == self.palette.?.selected) try fill(self.renderer, .{ .x = box.x + 4, .y = y, .width = box.width - 8, .height = 26 }, .{ .r = 65, .g = 71, .b = 96, .a = 255 });
            try self.drawText(keybindings.definitions[index].label, box.x + 12, y + 4);
            const binding = self.bindings.rows[index];
            if (binding.len != 0) try self.drawText(binding.text[0..binding.len], box.x + box.width - 174, y + 4);
        }
    }
    fn drawText(self: *App, bytes: []const u8, x: f32, y: f32) !void {
        if (bytes.len == 0) return;
        const surface = c.TTF_RenderText_Blended(self.ui_font, bytes.ptr, bytes.len, .{ .r = 224, .g = 226, .b = 238, .a = 255 }) orelse return error.TTF;
        defer c.SDL_DestroySurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return error.SDL;
        defer c.SDL_DestroyTexture(texture);
        const rect: c.SDL_FRect = .{ .x = x, .y = y, .w = @as(f32, @floatFromInt(surface.*.w)) / self.scale, .h = @as(f32, @floatFromInt(surface.*.h)) / self.scale };
        if (!c.SDL_RenderTexture(self.renderer, texture, null, &rect)) return error.SDL;
    }
    fn draw(self: *App) !void {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) return error.SDL;
        self.width = @floatFromInt(@max(1, width));
        self.height = @floatFromInt(@max(1, height));
        // Live display-scale/font reconfiguration is a remaining qualification gap.
        if (!c.SDL_SetRenderScale(self.renderer, self.scale, self.scale) or !c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_BLEND) or
            !c.SDL_SetRenderDrawColor(self.renderer, 24, 25, 33, 255) or !c.SDL_RenderClear(self.renderer)) return error.SDL;
        const tab_width = self.tabWidth();
        for (self.tabs[0..self.tab_count], 0..) |maybe, index| {
            const value = maybe.?;
            const status = value.panes[value.tree.active].?.owner.snapshot();
            const rect: layout.Rect = .{ .x = 8 + tab_width * @as(f32, @floatFromInt(index)), .y = 4, .width = tab_width - 3, .height = 30 };
            try fill(self.renderer, rect, if (index == self.active) .{ .r = 56, .g = 60, .b = 78, .a = 255 } else .{ .r = 34, .g = 36, .b = 47, .a = 255 });
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
        const result = self.tab().tree.layout(self.body(), &places, &dividers);
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            const active = place.pane == self.tab().tree.active;
            try fill(self.renderer, place.rect, if (active) .{ .r = 76, .g = 85, .b = 112, .a = 255 } else .{ .r = 31, .g = 33, .b = 43, .a = 255 });
            const rect: c.SDL_FRect = .{ .x = place.rect.x + 3, .y = place.rect.y + 3, .w = @max(1, place.rect.width - 6), .h = @max(1, place.rect.height - 6) };
            if (p.graphics_failure == null and p.owner.takeFrame()) {
                p.canvas.update(self.renderer, p.owner.renderExchange()) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            const status = p.owner.snapshot();
            if (p.canvas.frame()) |frame| {
                const rows: u16 = @intFromFloat(std.math.clamp(@floor(rect.h * self.scale / @as(f32, @floatFromInt(frame.cell_size.height))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_rows))));
                const columns: u16 = @intFromFloat(std.math.clamp(@floor(rect.w * self.scale / @as(f32, @floatFromInt(frame.cell_size.width))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_columns))));
                if (p.size_control and status.failure == null and !status.closed and (rows != p.rows or columns != p.columns)) {
                    try p.owner.submit(.{ .resize = .{ .rows = rows, .columns = columns } });
                    p.rows = rows;
                    p.columns = columns;
                }
                if (p.graphics_failure == null) p.canvas.draw(self.renderer, self.geometry, rect, self.scale) catch |failure| {
                    p.graphics_failure = failure;
                };
            }
            const failure: ?(GraphicsFailure || terminal.Failure || terminal.PresentationFailure) = if (p.graphics_failure) |value| value else if (status.failure) |value| value else if (status.presentation_failure) |value| value else null;
            if (failure) |value| {
                try fill(self.renderer, .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = 28 }, .{ .r = 96, .g = 35, .b = 43, .a = 255 });
                try self.drawText(@errorName(value), rect.x + 8, rect.y + 6);
            } else if (status.closed) try self.drawText("Exited — Ctrl+Shift+R to restart", rect.x + 8, rect.y + 6);
        }
        try self.drawText(if (self.notice_len == 0) "Local" else self.notice[0..self.notice_len], 10, self.height - 22);
        if (self.palette != null) try self.drawPalette();
        if (!c.SDL_RenderPresent(self.renderer)) return error.SDL;
        for (places[0..result.panes]) |place| {
            const p = self.tab().panes[place.pane].?;
            if (p.graphics_failure == null) p.owner.requestFrame();
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
    var fonts = try font_owner.Fonts.discover(allocator, init.environ_map);
    defer fonts.deinit();
    const window = c.SDL_CreateWindow("Howl", 1000, 650, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const scale = c.SDL_GetWindowDisplayScale(window);
    if (!std.math.isFinite(scale) or scale <= 0 or scale > 8) return error.DisplayScale;
    const font_path = try allocator.dupeSentinel(u8, fonts.paths[0], 0);
    defer allocator.free(font_path);
    const ui_font = c.TTF_OpenFont(font_path, 15 * scale) orelse return error.TTF;
    defer c.TTF_CloseFont(ui_font);
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
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_font = ui_font,
        .geometry = geometry,
        .wake_event = wake_event,
        .scale = scale,
        .bindings = try keybindings.Bindings.init(),
        .focused = c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_INPUT_FOCUS != 0,
    };
    defer app.deinit();
    try app.createTab();
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
fn fill(renderer: *c.SDL_Renderer, rect: layout.Rect, color: c.SDL_Color) !void {
    const target: c.SDL_FRect = .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
    if (!c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) or !c.SDL_RenderFillRect(renderer, &target)) return error.SDL;
}
fn clearClip(renderer: *c.SDL_Renderer) void {
    const success = c.SDL_SetRenderClipRect(renderer, null);
    std.debug.assert(success);
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
}

test "palette query is bounded and includes deliberately unbound directional commands" {
    var p: Palette = .{};
    var indices: [keybindings.definitions.len]usize = undefined;
    try std.testing.expectEqual(keybindings.definitions.len, p.indices(&indices));
    const query = "FOCUS PANE";
    @memcpy(p.query[0..query.len], query);
    p.len = query.len;
    try std.testing.expectEqual(@as(usize, 4), p.indices(&indices));
    for (indices[0..4]) |index| try std.testing.expect(keybindings.definitions[index].target == .pane_focus);
    p = .{ .profile = true };
    try std.testing.expectEqual(@as(usize, 2), p.indices(&indices));
}
