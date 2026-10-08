const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const terminal = @import("terminal.zig");
const mappings = @import("keybindings.zig");

const Kind = enum { none, application, overlay, terminal, text };
const Held = struct {
    kind: Kind = .none,
    target: ?*terminal.Terminal = null,
    key: ?instance.Key = null,
    mods: instance.InputModifier = .{},
};

/// Keyboard routing result; terminal delivery happens synchronously through bounded admission.
pub const Route = union(enum) { handled, overlay, command: mappings.Target };

/// Owns each physical key's press/repeat/release route and prevents half app chords.
pub const Keyboard = struct {
    held: [c.SDL_SCANCODE_COUNT]Held = @splat(.{}),
    suppress_text: bool = false,

    /// Routes one key lifecycle to its original owner, regardless of later modifier state.
    pub fn route(
        self: *Keyboard,
        event: c.SDL_KeyboardEvent,
        press: bool,
        target: ?*terminal.Terminal,
        command: ?mappings.Target,
        overlay: bool,
    ) !Route {
        if (event.scancode >= self.held.len) return .handled;
        const entry = &self.held[event.scancode];
        if (!press) {
            const previous = entry.*;
            entry.* = .{};
            if (previous.kind == .terminal) {
                const owner = previous.target.?;
                const status = owner.snapshot();
                if (status.failure == null and !status.closed)
                    try owner.submit(.{ .input = .{ .key = .{ .key = previous.key.?, .mods = semanticModifiers(event.mod), .action = .release } } });
            }
            return .handled;
        }
        self.suppress_text = false;
        if (event.repeat) {
            switch (entry.kind) {
                .application => {
                    self.suppress_text = true;
                    return .handled;
                },
                .overlay => return if (overlay) .overlay else .handled,
                .terminal => {
                    self.suppress_text = true;
                    const owner = entry.target.?;
                    const status = owner.snapshot();
                    if (status.failure == null and !status.closed)
                        try owner.submit(.{ .input = .{ .key = .{ .key = entry.key.?, .mods = semanticModifiers(event.mod), .action = .repeat } } });
                    return .handled;
                },
                .none, .text => return .handled,
            }
        }
        if (command) |owned_command| {
            entry.* = .{ .kind = .application };
            self.suppress_text = true;
            return .{ .command = owned_command };
        }
        if (overlay) {
            entry.* = .{ .kind = .overlay };
            return .overlay;
        }
        const owner = target orelse return .handled;
        const status = owner.snapshot();
        if (status.failure != null or status.closed) return .handled;
        const mods = semanticModifiers(event.mod);
        const key: instance.Key = if (namedKey(event.key)) |named| .{ .named = named } else if ((mods.control or mods.alt or mods.super) and event.key >= 0x20 and event.key < 0x7f)
            try instance.Key.initUnicode(@intCast(event.key))
        else {
            entry.* = .{ .kind = .text };
            return .handled;
        };
        try owner.submit(.{ .input = .{ .key = .{ .key = key, .mods = mods, .action = .press } } });
        entry.* = .{ .kind = .terminal, .target = owner, .key = key, .mods = mods };
        self.suppress_text = true;
        return .handled;
    }

    /// Retires held terminal keys when keyboard ownership changes; application chords remain owned.
    pub fn releaseTerminal(self: *Keyboard) !void {
        for (&self.held) |*entry| {
            if (entry.kind != .terminal) continue;
            const previous = entry.*;
            entry.* = .{};
            const owner = previous.target.?;
            const status = owner.snapshot();
            if (status.failure == null and !status.closed)
                try owner.submit(.{ .input = .{ .key = .{ .key = previous.key.?, .mods = previous.mods, .action = .release } } });
        }
    }

    /// Removes every pointer to a retiring pane before its terminal owner is destroyed.
    pub fn forget(self: *Keyboard, target: *terminal.Terminal) void {
        for (&self.held) |*entry| if (entry.target == target) {
            entry.* = .{};
        };
    }

    /// Consumes committed text belonging to an application-owned or semantic key event.
    pub fn consumeText(self: *Keyboard) bool {
        const consumed = self.suppress_text;
        self.suppress_text = false;
        return consumed;
    }
};

/// Full factual modifiers forwarded to canonical VT; lock state is preserved here.
pub fn semanticModifiers(mod: c.SDL_Keymod) instance.InputModifier {
    return .{
        .shift = mod & c.SDL_KMOD_SHIFT != 0,
        .control = mod & c.SDL_KMOD_CTRL != 0,
        .alt = mod & c.SDL_KMOD_ALT != 0,
        .super = mod & c.SDL_KMOD_GUI != 0,
        .caps_lock = mod & c.SDL_KMOD_CAPS != 0,
        .num_lock = mod & c.SDL_KMOD_NUM != 0,
    };
}

/// Named physical keys, including function, lock and keypad identities.
pub fn namedKey(key: c.SDL_Keycode) ?instance.KeyName {
    return switch (key) {
        c.SDLK_RETURN => .enter,
        c.SDLK_TAB => .tab,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_ESCAPE => .escape,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        c.SDLK_INSERT => .insert,
        c.SDLK_DELETE => .delete,
        c.SDLK_HOME => .home,
        c.SDLK_END => .end,
        c.SDLK_PAGEUP => .page_up,
        c.SDLK_PAGEDOWN => .page_down,
        c.SDLK_F1 => .f1,
        c.SDLK_F2 => .f2,
        c.SDLK_F3 => .f3,
        c.SDLK_F4 => .f4,
        c.SDLK_F5 => .f5,
        c.SDLK_F6 => .f6,
        c.SDLK_F7 => .f7,
        c.SDLK_F8 => .f8,
        c.SDLK_F9 => .f9,
        c.SDLK_F10 => .f10,
        c.SDLK_F11 => .f11,
        c.SDLK_F12 => .f12,
        c.SDLK_CAPSLOCK => .caps_lock,
        c.SDLK_NUMLOCKCLEAR => .num_lock,
        c.SDLK_KP_0 => .keypad_0,
        c.SDLK_KP_1 => .keypad_1,
        c.SDLK_KP_2 => .keypad_2,
        c.SDLK_KP_3 => .keypad_3,
        c.SDLK_KP_4 => .keypad_4,
        c.SDLK_KP_5 => .keypad_5,
        c.SDLK_KP_6 => .keypad_6,
        c.SDLK_KP_7 => .keypad_7,
        c.SDLK_KP_8 => .keypad_8,
        c.SDLK_KP_9 => .keypad_9,
        c.SDLK_KP_PERIOD, c.SDLK_KP_DECIMAL => .keypad_decimal,
        c.SDLK_KP_PLUS => .keypad_add,
        c.SDLK_KP_MINUS => .keypad_subtract,
        c.SDLK_KP_MULTIPLY => .keypad_multiply,
        c.SDLK_KP_DIVIDE => .keypad_divide,
        c.SDLK_KP_COMMA => .keypad_separator,
        c.SDLK_KP_EQUALS => .keypad_equal,
        c.SDLK_KP_ENTER => .keypad_enter,
        else => null,
    };
}

test "an app paste chord owns repeat and release after its modifiers change" {
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_V;
    event.key = c.SDLK_V;
    event.mod = c.SDL_KMOD_CTRL | c.SDL_KMOD_SHIFT;
    const press = try keyboard.route(event, true, null, .paste_clipboard, false);
    try std.testing.expect(press == .command);
    try std.testing.expect(keyboard.consumeText());
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, null, null, false)) == .handled);
    try std.testing.expect(keyboard.consumeText());
    event.mod = c.SDL_KMOD_NONE;
    try std.testing.expect((try keyboard.route(event, false, null, null, false)) == .handled);
    try std.testing.expect(keyboard.held[event.scancode].kind == .none);
    try std.testing.expect((try keyboard.route(event, false, null, null, false)) == .handled);
}

test "overlay and unclaimed releases cannot become terminal keys; standalone modifiers stay withheld" {
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_F5;
    event.key = c.SDLK_F5;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .overlay);
    try std.testing.expect((try keyboard.route(event, false, null, null, false)) == .handled);
    try std.testing.expect(namedKey(c.SDLK_LCTRL) == null);
    try std.testing.expectEqual(@as(?instance.KeyName, .keypad_enter), namedKey(c.SDLK_KP_ENTER));
}
