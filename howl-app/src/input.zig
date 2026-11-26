const std = @import("std");
const c = @import("desktop");
const VT = @import("howl_vt").Terminal;
const terminal = @import("terminal.zig");
const mappings = @import("keybindings.zig");

const Kind = enum { none, application, overlay, terminal, text };
const Held = struct {
    kind: Kind = .none,
    target: ?*terminal.Terminal = null,
    key: ?VT.Key = null,
    mods: VT.InputModifier = .{},
};

/// Keyboard routing result; terminal delivery happens synchronously through bounded admission.
pub const Route = union(enum) { handled, overlay, command: mappings.Target };

/// Owns each physical key's press/repeat/release route and prevents half app chords.
pub const Keyboard = struct {
    held: [c.SDL_SCANCODE_COUNT]Held = @splat(.{}),
    suppress_text: bool = false,
    pending_text: ?c.SDL_Scancode = null,
    pending_repeat: bool = false,
    last_mods: c.SDL_Keymod = c.SDL_KMOD_NONE,

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
        self.last_mods = event.mod;
        const entry = &self.held[event.scancode];
        if (!press) {
            if (self.pending_text == event.scancode) self.pending_text = null;
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
        const named = namedKey(event.key);
        const modifier = if (named) |key| isModifier(key) else false;
        if (!modifier) {
            self.suppress_text = false;
            self.pending_text = null;
        }
        if (event.repeat) {
            switch (entry.kind) {
                .application => {
                    self.suppress_text = true;
                    return .handled;
                },
                .overlay => {
                    // A held editor key must not commit text into the terminal
                    // after that editor has closed.
                    self.suppress_text = !overlay;
                    return if (overlay) .overlay else .handled;
                },
                .terminal => {
                    const owner = entry.target.?;
                    const status = owner.snapshot();
                    if (entry.key.? == .unicode and !entry.mods.control and !entry.mods.alt and !entry.mods.super) {
                        self.pending_text = event.scancode;
                        entry.mods = semanticModifiers(event.mod);
                        self.pending_repeat = true;
                        return .handled;
                    }
                    if (!modifier) self.suppress_text = true;
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
        const report_all = status.interaction != null and status.interaction.?.kitty_keyboard_flags & 8 != 0;
        if (modifier and !report_all) return .handled;
        const key: VT.Key = if (named) |identity| .{ .named = identity } else if ((mods.control or mods.alt or mods.super) and event.key >= 0x20 and event.key < 0x7f)
            try VT.Key.initUnicode(@intCast(event.key))
        else {
            entry.* = .{ .kind = .text };
            if (status.interaction != null and status.interaction.?.kitty_keyboard_flags & 8 != 0 and event.key >= 0x20 and event.key <= 0x10ffff) {
                entry.target = owner;
                entry.key = try VT.Key.initUnicode(@intCast(event.key));
                entry.mods = mods;
                self.pending_text = event.scancode;
                self.pending_repeat = false;
            }
            return .handled;
        };
        try owner.submit(.{ .input = .{ .key = .{ .key = key, .mods = mods, .action = .press } } });
        entry.* = .{ .kind = .terminal, .target = owner, .key = key, .mods = mods };
        if (!modifier) self.suppress_text = true;
        return .handled;
    }

    /// Retires held terminal keys when keyboard ownership changes; application chords remain owned.
    pub fn releaseTerminal(self: *Keyboard) !void {
        self.pending_text = null;
        // Retire logical terminal holds in order without altering SDL's
        // factual physical state. Preserve the other side and locked bits.
        var mods = self.last_mods;
        for (&self.held) |*entry| {
            if (entry.kind == .text) {
                entry.* = .{};
                continue;
            }
            if (entry.kind != .terminal) continue;
            const previous = entry.*;
            entry.* = .{};
            const owner = previous.target.?;
            const status = owner.snapshot();
            const key = previous.key.?;
            if (key == .named) mods &= ~modifierSideMask(key.named);
            if (status.failure == null and !status.closed)
                try owner.submit(.{ .input = .{ .key = .{ .key = key, .mods = semanticModifiers(mods), .action = .release } } });
        }
    }

    /// A retiring editor's held keys stay consumed until release, even if another editor opens.
    pub fn retireOverlay(self: *Keyboard) void {
        for (&self.held) |*entry| if (entry.kind == .overlay) {
            entry.* = .{ .kind = .application };
            self.suppress_text = true;
        };
    }

    /// Removes every pointer to a retiring pane before its terminal owner is destroyed.
    pub fn forget(self: *Keyboard, target: *terminal.Terminal) void {
        for (&self.held) |*entry| if (entry.target == target) {
            entry.* = .{};
        };
    }

    /// Attaches SDL's committed text to the physical key requested by report-all.
    /// The worker copies the bytes before SDL may retire this event.
    pub fn commitText(self: *Keyboard, text: []const u8) !bool {
        if (self.consumeText()) return true;
        const scan = self.pending_text orelse return false;
        self.pending_text = null;
        const entry = &self.held[scan];
        const owner = entry.target orelse return false;
        const status = owner.snapshot();
        if (status.failure != null or status.closed) return true;
        try owner.submit(.{ .input = .{ .key = .{ .key = entry.key.?, .mods = entry.mods, .action = if (self.pending_repeat) .repeat else .press, .text = text } } });
        entry.kind = .terminal;
        return true;
    }

    /// Consumes committed text belonging to an application-owned or semantic key event.
    pub fn consumeText(self: *Keyboard) bool {
        const consumed = self.suppress_text;
        self.suppress_text = false;
        return consumed;
    }
};

/// Full factual modifiers forwarded to canonical VT; lock state is preserved here.
pub fn semanticModifiers(mod: c.SDL_Keymod) VT.InputModifier {
    return .{
        .shift = mod & c.SDL_KMOD_SHIFT != 0,
        .control = mod & c.SDL_KMOD_CTRL != 0,
        .alt = mod & c.SDL_KMOD_ALT != 0,
        .super = mod & c.SDL_KMOD_GUI != 0,
        .caps_lock = mod & c.SDL_KMOD_CAPS != 0,
        .num_lock = mod & c.SDL_KMOD_NUM != 0,
    };
}

fn modifierSideMask(key: VT.NamedKey) c.SDL_Keymod {
    return switch (key) {
        .left_shift => c.SDL_KMOD_LSHIFT,
        .right_shift => c.SDL_KMOD_RSHIFT,
        .left_control => c.SDL_KMOD_LCTRL,
        .right_control => c.SDL_KMOD_RCTRL,
        .left_alt => c.SDL_KMOD_LALT,
        .right_alt => c.SDL_KMOD_RALT,
        .left_super => c.SDL_KMOD_LGUI,
        .right_super => c.SDL_KMOD_RGUI,
        else => c.SDL_KMOD_NONE,
    };
}

fn isModifier(key: VT.NamedKey) bool {
    return modifierSideMask(key) != c.SDL_KMOD_NONE or key == .caps_lock or key == .num_lock;
}

/// Named physical keys, including function, lock and keypad identities.
pub fn namedKey(key: c.SDL_Keycode) ?VT.NamedKey {
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
        c.SDLK_LSHIFT => .left_shift,
        c.SDLK_RSHIFT => .right_shift,
        c.SDLK_LCTRL => .left_control,
        c.SDLK_RCTRL => .right_control,
        c.SDLK_LALT => .left_alt,
        c.SDLK_RALT => .right_alt,
        c.SDLK_LGUI => .left_super,
        c.SDLK_RGUI => .right_super,
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

test "overlay and unclaimed releases cannot become terminal keys" {
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_F5;
    event.key = c.SDLK_F5;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .overlay);
    try std.testing.expect((try keyboard.route(event, false, null, null, false)) == .handled);
    try std.testing.expectEqual(@as(?VT.NamedKey, .left_control), namedKey(c.SDLK_LCTRL));
    try std.testing.expectEqual(@as(?VT.NamedKey, .keypad_enter), namedKey(c.SDLK_KP_ENTER));
}

test "report-all alphabet keys carry committed text repeat release and focus cleanup exactly once" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const expected = "\x1b[119;;119u\x1b[119;1:2;119u\x1b[119;1:3u\x1b[119;;119u\x1b[119;1:3u";
    const command = try std.fmt.allocPrint(std.testing.allocator, "stty raw -echo; printf '\\033[>31u\\033]0;READY\\007'; value=$(dd bs=1 count={d} 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf '\\033]0;%s\\007' \"$value\"; sleep 30", .{expected.len});
    defer std.testing.allocator.free(command);
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = command,
        .rows = 4,
        .columns = 80,
        .history_rows = 8,
    }, .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
    }, c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    var attempt: u16 = 0;
    while (attempt < 5000) : (attempt += 1) {
        const status = owner.snapshot();
        if (status.interaction != null and status.interaction.?.kitty_keyboard_flags == 31) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempt < 5000);
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_W;
    event.key = c.SDLK_W;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("w"));
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("w"));
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("w"));
    try keyboard.releaseTerminal();
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    const expected_hex = std.fmt.bytesToHex(expected, .lower);
    attempt = 0;
    while (attempt < 5000) : (attempt += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], &expected_hex)) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(attempt < 5000);
    try std.testing.expectEqual(Kind.none, keyboard.held[event.scancode].kind);
}

test "held overlay repeats cannot commit into a newly focused terminal" {
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_A;
    event.key = c.SDLK_A;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .overlay);
    event.repeat = true;
    for (0..3) |_| {
        try std.testing.expect((try keyboard.route(event, true, null, null, false)) == .handled);
        try std.testing.expect(try keyboard.commitText("a"));
    }
    try std.testing.expect((try keyboard.route(event, false, null, null, false)) == .handled);
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, true, null, null, false)) == .handled);
    try std.testing.expect(!try keyboard.commitText("new owner"));
}

test "changing overlay owners fences held Enter before the new editor opens" {
    var keyboard: Keyboard = .{};
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    event.scancode = c.SDL_SCANCODE_RETURN;
    event.key = c.SDLK_RETURN;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .overlay);
    keyboard.retireOverlay();
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .handled);
    try std.testing.expect(try keyboard.commitText("\n"));
    try std.testing.expect((try keyboard.route(event, false, null, null, true)) == .handled);
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, true, null, null, true)) == .overlay);
}

test "Kitty live modifier lifecycle preserves both sides and does not acknowledge Rex" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const expected = "\x1b[57442;5u\x1b[57448;5u\x1b[57442;5:3u\x1b[57448;1:3u" ++
        "\x1b[57441;2u\x1b[57447;2u\x1b[57441;2:3u\x1b[57447;1:3u" ++
        "\x1b[57358;65u\x1b[57358;65:3u\x1b[57360;193u\x1b[57360;193:3u";
    const command = try std.fmt.allocPrint(std.testing.allocator, "stty raw -echo; printf '\\033[=0u\\033]0;LEGACY\\007'; first=$(dd bs=1 count=1 2>/dev/null); printf '\\033[=31u\\033]7501;state=done:id=job\\007\\033]0;READY\\007'; value=$(dd bs=1 count={d} 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf '\\033]0;%s-%s\\007' \"$first\" \"$value\"; sleep 30", .{expected.len});
    defer std.testing.allocator.free(command);
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = command,
        .rows = 4,
        .columns = 80,
        .history_rows = 8,
    }, .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
    }, c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    const Check = struct {
        fn wait(t: *terminal.Terminal, io: std.Io, title: []const u8) !void {
            for (0..5000) |_| {
                const status = t.snapshot();
                if (status.failure) |failure| return failure;
                if (std.mem.eql(u8, status.title[0..status.title_len], title)) return;
                try std.Io.sleep(io, .fromMilliseconds(1), .awake);
            }
            return error.Timeout;
        }
        fn event(k: *Keyboard, t: *terminal.Terminal, scan: c.SDL_Scancode, key: c.SDL_Keycode, mods: c.SDL_Keymod, press: bool) !void {
            var e: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
            e.scancode = scan;
            e.key = key;
            e.mod = mods;
            try std.testing.expect((try k.route(e, press, t, null, false)) == .handled);
            try std.testing.expect(!k.consumeText());
        }
    };
    var keyboard: Keyboard = .{};
    try Check.wait(owner, threaded.io(), "LEGACY");
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LCTRL, c.SDLK_LCTRL, c.SDL_KMOD_LCTRL, true);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LCTRL, c.SDLK_LCTRL, c.SDL_KMOD_NONE, false);
    try std.testing.expect(!owner.takeInputActivity());
    try owner.submit(.{ .input = .{ .bytes = "x" } });
    try Check.wait(owner, threaded.io(), "READY");
    try std.testing.expect(owner.takeInputActivity());
    try std.testing.expectEqual(@as(?VT.ProgramStatus.State, .done), owner.snapshot().program_status.state);

    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LCTRL, c.SDLK_LCTRL, c.SDL_KMOD_LCTRL, true);
    try std.testing.expectEqual(Kind.terminal, keyboard.held[c.SDL_SCANCODE_LCTRL].kind);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_RCTRL, c.SDLK_RCTRL, c.SDL_KMOD_CTRL, true);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LCTRL, c.SDLK_LCTRL, c.SDL_KMOD_RCTRL, false);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_RCTRL, c.SDLK_RCTRL, c.SDL_KMOD_NONE, false);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LSHIFT, c.SDLK_LSHIFT, c.SDL_KMOD_LSHIFT, true);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_RSHIFT, c.SDLK_RSHIFT, c.SDL_KMOD_SHIFT, true);
    try keyboard.releaseTerminal();
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_LSHIFT, c.SDLK_LSHIFT, c.SDL_KMOD_RSHIFT, false);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_RSHIFT, c.SDLK_RSHIFT, c.SDL_KMOD_NONE, false);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_CAPSLOCK, c.SDLK_CAPSLOCK, c.SDL_KMOD_CAPS, true);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_CAPSLOCK, c.SDLK_CAPSLOCK, c.SDL_KMOD_CAPS, false);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_NUMLOCKCLEAR, c.SDLK_NUMLOCKCLEAR, c.SDL_KMOD_CAPS | c.SDL_KMOD_NUM, true);
    try Check.event(&keyboard, owner, c.SDL_SCANCODE_NUMLOCKCLEAR, c.SDLK_NUMLOCKCLEAR, c.SDL_KMOD_CAPS | c.SDL_KMOD_NUM, false);
    const expected_hex = std.fmt.bytesToHex(expected, .lower);
    try Check.wait(owner, threaded.io(), "x-" ++ expected_hex);
    try std.testing.expect(!owner.takeInputActivity());
    try std.testing.expectEqual(@as(?VT.ProgramStatus.State, .done), owner.snapshot().program_status.state);
}
