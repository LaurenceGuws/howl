const std = @import("std");
const c = @import("desktop");
const layout = @import("layout.zig");

/// Daily action vocabulary; execution and contextual availability stay in the app.
pub const Action = enum {
    new_tab,
    new_window,
    duplicate_tab,
    split_vertical,
    split_horizontal,
    toggle_pane_zoom,
    open_local,
    attach_home,
    recover_instance,
    open_settings,
    open_command_palette,
    open_profile_menu,
    close_pane,
    toggle_fullscreen,
    next_tab,
    previous_tab,
    close_tab,
    move_tab_left,
    move_tab_right,
    take_size_control,
    stop_resizing,
};
/// UI grouping only; no terminal authority.
pub const Category = enum { window, tab, pane, profile, application };
/// A typed action or parameterized daily command.
pub const Target = union(enum) {
    action: Action,
    toggle_find,
    select_tab: u8,
    adjust_font: i8,
    copy_selection,
    paste_clipboard,
    history_oldest,
    history_live,
    history_page: i8,
    pane_focus: layout.Direction,
    pane_resize: layout.Direction,
    pane_swap: layout.Direction,
};
/// One stable persisted mapping id, human label and default binding.
pub const Definition = struct { target: Target, id: []const u8, label: []const u8, default_shortcut: []const u8, category: Category };

/// The daily fifty-row registry, including unbound directional commands.
pub const definitions = [_]Definition{
    .{ .target = .{ .action = .new_tab }, .id = "new_tab", .label = "New tab", .default_shortcut = "Ctrl+T", .category = .tab },
    .{ .target = .{ .action = .new_window }, .id = "new_window", .label = "New window", .default_shortcut = "Ctrl+Shift+N", .category = .window },
    .{ .target = .{ .action = .duplicate_tab }, .id = "duplicate_tab", .label = "Duplicate tab recipe", .default_shortcut = "Ctrl+Shift+D", .category = .tab },
    .{ .target = .{ .action = .split_vertical }, .id = "split_right", .label = "Split pane right", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .action = .split_horizontal }, .id = "split_down", .label = "Split pane down", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .action = .toggle_pane_zoom }, .id = "toggle_pane_zoom", .label = "Toggle pane zoom", .default_shortcut = "Ctrl+Shift+Z", .category = .pane },
    .{ .target = .{ .action = .open_local }, .id = "open_local", .label = "Open Local shell", .default_shortcut = "", .category = .profile },
    .{ .target = .{ .action = .attach_home }, .id = "attach_home", .label = "Attach Home Instance", .default_shortcut = "", .category = .profile },
    .{ .target = .{ .action = .recover_instance }, .id = "recover_instance", .label = "Restart / reconnect pane", .default_shortcut = "Ctrl+Shift+R", .category = .pane },
    .{ .target = .{ .action = .open_settings }, .id = "open_settings", .label = "Open settings", .default_shortcut = "Ctrl+,", .category = .application },
    .{ .target = .{ .action = .open_command_palette }, .id = "command_palette", .label = "Command Palette", .default_shortcut = "Ctrl+Shift+P", .category = .application },
    .{ .target = .{ .action = .open_profile_menu }, .id = "profile_menu", .label = "Profile menu", .default_shortcut = "Ctrl+Shift+Space", .category = .application },
    .{ .target = .{ .action = .close_pane }, .id = "close_pane", .label = "Close pane / tab", .default_shortcut = "Ctrl+Shift+W", .category = .pane },
    .{ .target = .{ .action = .toggle_fullscreen }, .id = "toggle_fullscreen", .label = "Toggle fullscreen", .default_shortcut = "F11", .category = .window },
    .{ .target = .{ .action = .next_tab }, .id = "next_tab", .label = "Next tab", .default_shortcut = "Ctrl+Tab", .category = .tab },
    .{ .target = .{ .action = .previous_tab }, .id = "previous_tab", .label = "Previous tab", .default_shortcut = "Ctrl+Shift+Tab", .category = .tab },
    .{ .target = .{ .action = .close_tab }, .id = "close_tab", .label = "Close entire tab", .default_shortcut = "", .category = .tab },
    .{ .target = .{ .action = .move_tab_left }, .id = "move_tab_left", .label = "Move tab left", .default_shortcut = "Ctrl+Shift+PageUp", .category = .tab },
    .{ .target = .{ .action = .move_tab_right }, .id = "move_tab_right", .label = "Move tab right", .default_shortcut = "Ctrl+Shift+PageDown", .category = .tab },
    .{ .target = .{ .action = .take_size_control }, .id = "take_size_control", .label = "Take Instance size control", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .action = .stop_resizing }, .id = "stop_resizing", .label = "Stop resizing Instance", .default_shortcut = "", .category = .pane },
    .{ .target = .toggle_find, .id = "toggle_find", .label = "Toggle terminal find", .default_shortcut = "Ctrl+Shift+F", .category = .pane },
    .{ .target = .{ .select_tab = 0 }, .id = "select_tab_1", .label = "Select tab 1", .default_shortcut = "Ctrl+1", .category = .tab },
    .{ .target = .{ .select_tab = 1 }, .id = "select_tab_2", .label = "Select tab 2", .default_shortcut = "Ctrl+2", .category = .tab },
    .{ .target = .{ .select_tab = 2 }, .id = "select_tab_3", .label = "Select tab 3", .default_shortcut = "Ctrl+3", .category = .tab },
    .{ .target = .{ .select_tab = 3 }, .id = "select_tab_4", .label = "Select tab 4", .default_shortcut = "Ctrl+4", .category = .tab },
    .{ .target = .{ .select_tab = 4 }, .id = "select_tab_5", .label = "Select tab 5", .default_shortcut = "Ctrl+5", .category = .tab },
    .{ .target = .{ .select_tab = 5 }, .id = "select_tab_6", .label = "Select tab 6", .default_shortcut = "Ctrl+6", .category = .tab },
    .{ .target = .{ .select_tab = 6 }, .id = "select_tab_7", .label = "Select tab 7", .default_shortcut = "Ctrl+7", .category = .tab },
    .{ .target = .{ .select_tab = 7 }, .id = "select_tab_8", .label = "Select tab 8", .default_shortcut = "Ctrl+8", .category = .tab },
    .{ .target = .{ .adjust_font = -1 }, .id = "font_decrease", .label = "Decrease terminal font", .default_shortcut = "Ctrl+-", .category = .pane },
    .{ .target = .{ .adjust_font = 1 }, .id = "font_increase", .label = "Increase terminal font", .default_shortcut = "Ctrl+Plus", .category = .pane },
    .{ .target = .copy_selection, .id = "copy_selection", .label = "Copy terminal selection", .default_shortcut = "Ctrl+Shift+C", .category = .pane },
    .{ .target = .paste_clipboard, .id = "paste_clipboard", .label = "Paste clipboard", .default_shortcut = "Ctrl+Shift+V", .category = .pane },
    .{ .target = .history_oldest, .id = "history_oldest", .label = "Jump to oldest history", .default_shortcut = "Ctrl+Shift+Home", .category = .pane },
    .{ .target = .history_live, .id = "history_live", .label = "Return history to LIVE", .default_shortcut = "Ctrl+Shift+End", .category = .pane },
    .{ .target = .{ .history_page = 1 }, .id = "history_page_up", .label = "History page up", .default_shortcut = "Shift+PageUp", .category = .pane },
    .{ .target = .{ .history_page = -1 }, .id = "history_page_down", .label = "History page down", .default_shortcut = "Shift+PageDown", .category = .pane },
    .{ .target = .{ .pane_focus = .left }, .id = "focus_pane_left", .label = "Focus pane left", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_focus = .right }, .id = "focus_pane_right", .label = "Focus pane right", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_focus = .up }, .id = "focus_pane_up", .label = "Focus pane up", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_focus = .down }, .id = "focus_pane_down", .label = "Focus pane down", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_resize = .left }, .id = "resize_pane_left", .label = "Resize pane left", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_resize = .right }, .id = "resize_pane_right", .label = "Resize pane right", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_resize = .up }, .id = "resize_pane_up", .label = "Resize pane up", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_resize = .down }, .id = "resize_pane_down", .label = "Resize pane down", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_swap = .left }, .id = "swap_pane_left", .label = "Swap pane left", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_swap = .right }, .id = "swap_pane_right", .label = "Swap pane right", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_swap = .up }, .id = "swap_pane_up", .label = "Swap pane up", .default_shortcut = "", .category = .pane },
    .{ .target = .{ .pane_swap = .down }, .id = "swap_pane_down", .label = "Swap pane down", .default_shortcut = "", .category = .pane },
};

/// Only application modifier bits participate; lock state never changes a shortcut.
pub fn modifiers(mod: c.SDL_Keymod) u8 {
    return @as(u8, if (mod & c.SDL_KMOD_SHIFT != 0) 1 else 0) |
        @as(u8, if (mod & c.SDL_KMOD_CTRL != 0) 2 else 0) |
        @as(u8, if (mod & c.SDL_KMOD_ALT != 0) 4 else 0) |
        @as(u8, if (mod & c.SDL_KMOD_GUI != 0) 8 else 0);
}

/// One normalized chord; key zero represents deliberately unbound.
pub const Shortcut = struct {
    key: c.SDL_Keycode = 0,
    mods: u8 = 0,

    /// Matches physical SDL keys, treating shifted equals as the Plus key.
    pub fn matches(self: Shortcut, key: c.SDL_Keycode, mod: c.SDL_Keymod) bool {
        if (self.key == 0) return false;
        var actual = modifiers(mod);
        if (self.key == c.SDLK_PLUS and (key == c.SDLK_PLUS or (key == c.SDLK_EQUALS and actual & 1 != 0))) {
            if (self.mods & 1 == 0) actual &= ~@as(u8, 1);
            return actual == self.mods;
        }
        return self.key == key and self.mods == actual;
    }
};

/// Parses bounded persisted shortcuts; unknown keys or duplicate modifiers are errors.
pub fn parse(text: []const u8) error{InvalidShortcut}!Shortcut {
    if (text.len == 0) return .{};
    if (text.len > 63) return error.InvalidShortcut;
    var result: Shortcut = .{};
    var tokens = std.mem.splitScalar(u8, text, '+');
    while (tokens.next()) |token| {
        if (token.len == 0) return error.InvalidShortcut;
        const bit: u8 = if (std.ascii.eqlIgnoreCase(token, "Shift")) 1 else if (std.ascii.eqlIgnoreCase(token, "Ctrl") or std.ascii.eqlIgnoreCase(token, "Control")) 2 else if (std.ascii.eqlIgnoreCase(token, "Alt")) 4 else if (std.ascii.eqlIgnoreCase(token, "Super") or std.ascii.eqlIgnoreCase(token, "Win") or std.ascii.eqlIgnoreCase(token, "Meta")) 8 else 0;
        if (bit != 0) {
            if (result.mods & bit != 0) return error.InvalidShortcut;
            result.mods |= bit;
            continue;
        }
        if (result.key != 0) return error.InvalidShortcut;
        result.key = try parseKey(token);
        if (result.key == c.SDLK_UNKNOWN) return error.InvalidShortcut;
    }
    if (result.key == 0) return error.InvalidShortcut;
    return result;
}

/// Owns bounded editable binding text and the parsed runtime chord.
pub const Binding = struct { shortcut: Shortcut = .{}, text: [64]u8 = @splat(0), len: u8 = 0, customized: bool = false };
/// Precise binding validation failures; collision never mutates either row.
pub const SetError = error{ InvalidMapping, InvalidShortcut, BindingConflict };
/// Fixed registry state; one owner serves dispatch, palette and settings.
pub const Bindings = struct {
    rows: [definitions.len]Binding = @splat(.{}),

    /// Loads every default, including deliberately unbound rows.
    pub fn init() !Bindings {
        var bindings: Bindings = .{};
        for (definitions, 0..) |definition, index| {
            bindings.rows[index].shortcut = try parse(definition.default_shortcut);
            bindings.rows[index].len = @intCast(definition.default_shortcut.len);
            @memcpy(bindings.rows[index].text[0..definition.default_shortcut.len], definition.default_shortcut);
        }
        return bindings;
    }

    /// Returns the one mapping matching a physical chord.
    pub fn find(self: *const Bindings, key: c.SDL_Keycode, mod: c.SDL_Keymod) ?usize {
        for (self.rows, 0..) |binding, index| if (binding.shortcut.matches(key, mod)) return index;
        return null;
    }

    /// Applies one valid conflict-free chord atomically.
    pub fn set(self: *Bindings, index: usize, text: []const u8) SetError!void {
        if (index >= self.rows.len) return error.InvalidMapping;
        const shortcut = try parse(text);
        if (shortcut.key != 0) for (self.rows, 0..) |binding, other| {
            if (other != index and overlaps(binding.shortcut, shortcut)) return error.BindingConflict;
        };
        var next: Binding = .{ .shortcut = shortcut, .len = @intCast(text.len), .customized = !std.mem.eql(u8, text, definitions[index].default_shortcut) };
        @memcpy(next.text[0..text.len], text);
        self.rows[index] = next;
    }
};

/// Resolves an exact persisted id; unknown ids are never silently ignored.
pub fn indexForId(id: []const u8) ?usize {
    for (definitions, 0..) |definition, index| if (std.mem.eql(u8, definition.id, id)) return index;
    return null;
}

test "daily defaults preserve fifty mappings, unbound Alt directions and shifted Plus" {
    const bindings = try Bindings.init();
    try std.testing.expectEqual(@as(usize, 50), definitions.len);
    for (definitions, bindings.rows) |definition, binding| {
        if (definition.target == .pane_focus or definition.target == .pane_resize or definition.target == .pane_swap)
            try std.testing.expectEqual(@as(c.SDL_Keycode, 0), binding.shortcut.key);
    }
    const plus = try parse("Ctrl+Plus");
    try std.testing.expect(plus.matches(c.SDLK_EQUALS, c.SDL_KMOD_CTRL | c.SDL_KMOD_SHIFT));
    try std.testing.expect(!plus.matches(c.SDLK_EQUALS, c.SDL_KMOD_SHIFT));
}

test "invalid or conflicting saved bindings leave every registry row unchanged" {
    var bindings = try Bindings.init();
    const before = bindings;
    try std.testing.expectError(error.BindingConflict, bindings.set(2, "Ctrl+T"));
    try std.testing.expectError(error.InvalidShortcut, bindings.set(2, "Ctrl+Ctrl+D"));
    try std.testing.expectError(error.InvalidShortcut, bindings.set(2, "Ctrl+"));
    try std.testing.expectEqualDeep(before, bindings);
    try bindings.set(2, "");
    try std.testing.expectEqual(@as(c.SDL_Keycode, 0), bindings.rows[2].shortcut.key);
    try std.testing.expect(indexForId("no_such_mapping") == null);
}

fn parseKey(token: []const u8) error{InvalidShortcut}!c.SDL_Keycode {
    if (token.len == 1 and token[0] >= 0x20 and token[0] <= 0x7e and token[0] != '+') return std.ascii.toLower(token[0]);
    const names = [_][]const u8{ "Space", "Plus", "Enter", "Tab", "Escape", "Esc", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown", "Left", "Right", "Up", "Down" };
    const keys = [_]c.SDL_Keycode{ c.SDLK_SPACE, c.SDLK_PLUS, c.SDLK_RETURN, c.SDLK_TAB, c.SDLK_ESCAPE, c.SDLK_ESCAPE, c.SDLK_BACKSPACE, c.SDLK_DELETE, c.SDLK_INSERT, c.SDLK_HOME, c.SDLK_END, c.SDLK_PAGEUP, c.SDLK_PAGEDOWN, c.SDLK_LEFT, c.SDLK_RIGHT, c.SDLK_UP, c.SDLK_DOWN };
    for (names, keys) |name, key| if (std.ascii.eqlIgnoreCase(token, name)) return key;
    if (token.len >= 2 and (token[0] == 'F' or token[0] == 'f')) {
        const number = std.fmt.parseInt(u8, token[1..], 10) catch return error.InvalidShortcut;
        if (number >= 1 and number <= 12) return c.SDLK_F1 + number - 1;
    }
    return error.InvalidShortcut;
}

fn overlaps(a: Shortcut, b: Shortcut) bool {
    if (a.key == 0 or b.key == 0) return false;
    for ([_]c.SDL_Keycode{ a.key, b.key, c.SDLK_PLUS, c.SDLK_EQUALS }) |key| {
        for (0..16) |bits| {
            const mods: c.SDL_Keymod = (if (bits & 1 != 0) @as(c.SDL_Keymod, c.SDL_KMOD_SHIFT) else 0) |
                (if (bits & 2 != 0) @as(c.SDL_Keymod, c.SDL_KMOD_CTRL) else 0) |
                (if (bits & 4 != 0) @as(c.SDL_Keymod, c.SDL_KMOD_ALT) else 0) |
                (if (bits & 8 != 0) @as(c.SDL_Keymod, c.SDL_KMOD_GUI) else 0);
            if (a.matches(key, mods) and b.matches(key, mods)) return true;
        }
    }
    return false;
}

test "Plus aliases cannot shadow another active binding and legacy modifier order remains readable" {
    var bindings = try Bindings.init();
    const before = bindings;
    try std.testing.expectError(error.BindingConflict, bindings.set(2, "Ctrl+Shift+="));
    try std.testing.expectEqualDeep(before, bindings);
    const legacy = try parse("F5+Meta");
    try std.testing.expect(legacy.matches(c.SDLK_F5, c.SDL_KMOD_GUI));
    try std.testing.expectError(error.InvalidShortcut, parse("Ctrl+F13"));
}
