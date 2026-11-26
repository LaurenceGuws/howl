const std = @import("std");
const c = @import("desktop");
const VT = @import("howl_vt").Terminal;
const terminal = @import("terminal.zig");
const mappings = @import("keybindings.zig");

const Kind = enum { none, application, overlay, terminal, text };
const Identity = struct {
    key: VT.Key,
    shifted: ?u21 = null,
    alternate: ?u21 = null,

    fn event(self: Identity, mods: VT.InputModifier, action: VT.KeyAction, text: []const u8) VT.InputEvent {
        return .{ .key = .{
            .key = self.key,
            .mods = mods,
            .action = action,
            .shifted = self.shifted,
            .alternate = self.alternate,
            .text = text,
        } };
    }
};

const Held = struct {
    kind: Kind = .none,
    target: ?*terminal.Terminal = null,
    identity: ?Identity = null,
    mods: VT.InputModifier = .{},
    platform_text: bool = false,

    fn releaseEvent(self: Held, mods: VT.InputModifier) VT.InputEvent {
        var result = self.identity.?.event(mods, .release, "");
        result.key.platform_text = self.platform_text;
        return result;
    }
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
        // Another physical transition ends the preceding text association,
        // even if it is a modifier or the original key's release.
        try self.flushPending();
        self.last_mods = event.mod;
        const entry = &self.held[event.scancode];
        if (!press) {
            const previous = entry.*;
            entry.* = .{};
            if (previous.kind == .terminal) {
                const owner = previous.target.?;
                const status = owner.snapshot();
                if (status.failure == null and !status.closed)
                    try owner.submit(.{ .input = previous.releaseEvent(semanticModifiers(event.mod)) });
            }
            return .handled;
        }
        const named = eventNamedKey(event);
        const modifier = if (named) |key| VT.isModifierKey(key) else false;
        if (!modifier) self.suppress_text = false;
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
                    if (status.failure != null or status.closed) return .handled;
                    const mods = semanticModifiers(event.mod);
                    if (entry.identity.?.key == .unicode and !shortcutModifiers(mods)) {
                        self.pending_text = event.scancode;
                        entry.mods = mods;
                        self.pending_repeat = true;
                        return .handled;
                    }
                    if (!modifier) self.suppress_text = true;
                    try owner.submit(.{ .input = entry.identity.?.event(mods, .repeat, "") });
                    entry.platform_text = false;
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
        const flags = if (status.interaction) |interaction| interaction.kitty_keyboard_flags else 0;
        const report_all = flags & 8 != 0;
        if (modifier and !report_all) return .handled;
        const identity: Identity = if (named) |key| .{ .key = .{ .named = key } } else blk: {
            const shortcut = shortcutModifiers(mods);
            const negotiated = flags & (1 | 2 | 8) != 0;
            // Printable events retain factual identity even in legacy mode:
            // the worker may observe a different negotiation when text arrives.
            const layout = if (negotiated or !shortcut) queryLayoutIdentity(event.scancode, event.mod) else null;
            if (shortcut) {
                // Preserve the existing normalized ASCII shortcut lane when
                // no enhancement selects encoded Unicode events.
                if (negotiated) {
                    if (layout) |key| break :blk key;
                } else if (event.key >= 0x20 and event.key < 0x7f) {
                    break :blk .{ .key = try VT.Key.initUnicode(@intCast(event.key)) };
                }
            }
            entry.* = .{ .kind = .text };
            if (!shortcut and layout != null) {
                entry.target = owner;
                entry.identity = layout;
                entry.mods = mods;
                self.pending_text = event.scancode;
                self.pending_repeat = false;
            }
            return .handled;
        };
        try owner.submit(.{ .input = identity.event(mods, .press, "") });
        entry.* = .{ .kind = .terminal, .target = owner, .identity = identity, .mods = mods };
        if (!modifier) self.suppress_text = true;
        return .handled;
    }

    /// Retires held terminal keys when keyboard ownership changes; application chords remain owned.
    pub fn releaseTerminal(self: *Keyboard) !void {
        try self.flushPending();
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
            const identity = previous.identity.?;
            if (identity.key == .named) mods &= ~modifierSideMask(identity.key.named);
            if (status.failure == null and !status.closed)
                try owner.submit(.{ .input = previous.releaseEvent(semanticModifiers(mods)) });
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
        if (self.pending_text) |scan| {
            if (self.held[scan].target == target) self.beginComposition();
        }
        for (&self.held) |*entry| if (entry.target == target) {
            entry.* = .{};
        };
    }

    /// A composition no longer identifies one physical key. Only nonempty
    /// preedit starts this fence; SDL also emits empty caret acknowledgments.
    pub fn beginComposition(self: *Keyboard) void {
        self.pending_text = null;
        self.pending_repeat = false;
    }

    /// Close a text association at an input boundary or drained SDL batch.
    /// No timer or inferred character: VT decides whether the bare key has
    /// a wire representation under its current negotiated mode.
    pub fn flushPending(self: *Keyboard) !void {
        try self.finishPending("");
    }

    /// Attaches an immediate SDL commit to its pending physical event.
    /// The worker owns the bytes before SDL may retire this event.
    pub fn commitText(self: *Keyboard, text: []const u8) !bool {
        if (self.consumeText()) return true;
        if (self.pending_text == null) return false;
        try self.finishPending(text);
        return true;
    }

    fn finishPending(self: *Keyboard, text: []const u8) !void {
        const scan = self.pending_text orelse return;
        const action: VT.KeyAction = if (self.pending_repeat) .repeat else .press;
        self.beginComposition();
        const entry = &self.held[scan];
        const owner = entry.target orelse return;
        const status = owner.snapshot();
        if (status.failure != null or status.closed) return;
        if (text.len > VT.maximum_key_text_bytes) {
            // A commit beyond the physical-key text bound is still complete
            // text input. Do not truncate it or invent additional key events.
            try owner.submit(.{ .input = .{ .committed_text = text } });
            return;
        }
        var event = entry.identity.?.event(entry.mods, action, text);
        event.key.platform_text = true;
        try owner.submit(.{ .input = event });
        entry.kind = .terminal;
        entry.platform_text = true;
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

fn shortcutModifiers(mods: VT.InputModifier) bool {
    return mods.control or mods.alt or mods.super or mods.hyper or mods.meta;
}

// SDL's event keycode may have french_numbers/latin_letters normalization.
// Query the active layout directly, retaining unreported AltGr/level-5
// selection but excluding Ctrl/Alt/Super, Shift and lock state.
fn queryLayoutIdentity(scan: c.SDL_Scancode, mods: c.SDL_Keymod) ?Identity {
    if (scan == c.SDL_SCANCODE_UNKNOWN) return null;
    const level = mods & @as(c.SDL_Keymod, c.SDL_KMOD_MODE | c.SDL_KMOD_LEVEL5);
    return layoutIdentity(
        scan,
        c.SDL_GetKeyFromScancode(scan, level, false),
        c.SDL_GetKeyFromScancode(scan, level | @as(c.SDL_Keymod, c.SDL_KMOD_SHIFT), false),
    );
}

fn printableScalar(code: c.SDL_Keycode) ?u21 {
    if (code < 32 or (code >= 127 and code <= 159) or code > 0x10ffff) return null;
    const scalar: u21 = @intCast(code);
    return if (std.unicode.utf8ValidCodepoint(scalar)) scalar else null;
}

// Only a known Unicode identity can carry alternatives. SDL does not expose
// a portable default-layout lookup distinct from its current keymap.
fn layoutIdentity(scan: c.SDL_Scancode, unshifted: c.SDL_Keycode, shifted: c.SDL_Keycode) ?Identity {
    const primary = printableScalar(unshifted) orelse return null;
    const shift = printableScalar(shifted);
    const base = pc101Key(scan);
    return .{
        .key = VT.Key.initUnicode(primary) catch return null,
        .shifted = if (shift == primary) null else shift,
        .alternate = if (base == primary) null else base,
    };
}

// Printable positions of the standard US PC-101 layout. SDL scancodes name
// USB keyboard usage positions, not current-layout characters. ISO-only,
// international, keypad and nonprintable positions have no base scalar.
fn pc101Key(scan: c.SDL_Scancode) ?u21 {
    return switch (scan) {
        c.SDL_SCANCODE_A...c.SDL_SCANCODE_Z => @intCast('a' + scan - c.SDL_SCANCODE_A),
        c.SDL_SCANCODE_1...c.SDL_SCANCODE_9 => @intCast('1' + scan - c.SDL_SCANCODE_1),
        c.SDL_SCANCODE_0 => '0',
        c.SDL_SCANCODE_SPACE => ' ',
        c.SDL_SCANCODE_MINUS => '-',
        c.SDL_SCANCODE_EQUALS => '=',
        c.SDL_SCANCODE_LEFTBRACKET => '[',
        c.SDL_SCANCODE_RIGHTBRACKET => ']',
        c.SDL_SCANCODE_BACKSLASH => 0x5c,
        c.SDL_SCANCODE_SEMICOLON => ';',
        c.SDL_SCANCODE_APOSTROPHE => 0x27,
        c.SDL_SCANCODE_GRAVE => 0x60,
        c.SDL_SCANCODE_COMMA => ',',
        c.SDL_SCANCODE_PERIOD => '.',
        c.SDL_SCANCODE_SLASH => '/',
        else => null,
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
        .iso_level3_shift => c.SDL_KMOD_MODE,
        .iso_level5_shift => c.SDL_KMOD_LEVEL5,
        else => c.SDL_KMOD_NONE,
    };
}

// Recover keypad provenance only from an explicit matching SDL pair.
// Do not infer navigation from Num Lock or guess the platform keymap.
fn eventNamedKey(event: c.SDL_KeyboardEvent) ?VT.NamedKey {
    return switch (event.scancode) {
        c.SDL_SCANCODE_KP_1 => if (event.key == c.SDLK_END) .keypad_end else namedKey(event.key),
        c.SDL_SCANCODE_KP_2 => if (event.key == c.SDLK_DOWN) .keypad_down else namedKey(event.key),
        c.SDL_SCANCODE_KP_3 => if (event.key == c.SDLK_PAGEDOWN) .keypad_page_down else namedKey(event.key),
        c.SDL_SCANCODE_KP_4 => if (event.key == c.SDLK_LEFT) .keypad_left else namedKey(event.key),
        c.SDL_SCANCODE_KP_5 => if (event.key == c.SDLK_CLEAR) .keypad_begin else namedKey(event.key),
        c.SDL_SCANCODE_KP_6 => if (event.key == c.SDLK_RIGHT) .keypad_right else namedKey(event.key),
        c.SDL_SCANCODE_KP_7 => if (event.key == c.SDLK_HOME) .keypad_home else namedKey(event.key),
        c.SDL_SCANCODE_KP_8 => if (event.key == c.SDLK_UP) .keypad_up else namedKey(event.key),
        c.SDL_SCANCODE_KP_9 => if (event.key == c.SDLK_PAGEUP) .keypad_page_up else namedKey(event.key),
        c.SDL_SCANCODE_KP_0 => if (event.key == c.SDLK_INSERT) .keypad_insert else namedKey(event.key),
        c.SDL_SCANCODE_KP_PERIOD => if (event.key == c.SDLK_DELETE) .keypad_delete else namedKey(event.key),
        else => namedKey(event.key),
    };
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
        c.SDLK_F13 => .f13,
        c.SDLK_F14 => .f14,
        c.SDLK_F15 => .f15,
        c.SDLK_F16 => .f16,
        c.SDLK_F17 => .f17,
        c.SDLK_F18 => .f18,
        c.SDLK_F19 => .f19,
        c.SDLK_F20 => .f20,
        c.SDLK_F21 => .f21,
        c.SDLK_F22 => .f22,
        c.SDLK_F23 => .f23,
        c.SDLK_F24 => .f24,
        c.SDLK_SCROLLLOCK => .scroll_lock,
        c.SDLK_PRINTSCREEN => .print_screen,
        c.SDLK_PAUSE => .pause,
        c.SDLK_APPLICATION, c.SDLK_MENU => .menu,
        c.SDLK_MEDIA_PLAY => .media_play,
        c.SDLK_MEDIA_PAUSE => .media_pause,
        c.SDLK_MEDIA_PLAY_PAUSE => .media_play_pause,
        c.SDLK_MEDIA_STOP => .media_stop,
        c.SDLK_MEDIA_FAST_FORWARD => .media_fast_forward,
        c.SDLK_MEDIA_REWIND => .media_rewind,
        c.SDLK_MEDIA_NEXT_TRACK => .media_track_next,
        c.SDLK_MEDIA_PREVIOUS_TRACK => .media_track_previous,
        c.SDLK_MEDIA_RECORD => .media_record,
        c.SDLK_VOLUMEDOWN => .lower_volume,
        c.SDLK_VOLUMEUP => .raise_volume,
        c.SDLK_MUTE => .mute_volume,
        c.SDLK_MODE => .iso_level3_shift,
        c.SDLK_LEVEL5_SHIFT => .iso_level5_shift,
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
    const expected = "\x1b[119;;119u\x1b[119;1:2;119u\x1b[119;1:3u\x1b[119;;119u\x1b[119;1:3u" ++
        "\x1b[97:65;6u\x1b[97:65;6:2u\x1b[97;5:2u\x1b[97;5:3u\x1b[61:43;2;43u\x1b[61:43;2:2;43u\x1b[61;1:3u" ++
        "\x1b[119;;119u\x1b[119;5:2u\x1b[119;5:3u" ++
        "\x1b[57376u\x1b[57376;1:3u\x1b[57430u\x1b[57430;1:3u\x1b[57361u\x1b[57361;1:3u" ++
        "\x1b[57363u\x1b[57363;1:3u\x1b[57359u\x1b[57359;1:3u\x1b[57453u\x1b[57453;1:3u" ++
        "\x1b[57417u\x1b[57417;1:3u" ++
        "\x1b[98u\x1b[98;1:2u\x1b[98;1:3u\x1b[99u\x1b[57442;5u\x1b[57442;1:3u\x1b[99;1:3u" ++
        "\x1b[100u\x1b[100;1:3u";
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
    // Headless SDL supplies the default layout. A normalized event key
    // must not replace that direct-layout identity in a negotiated event.
    try std.testing.expectEqual(@as(c.SDL_Keycode, 'a'), c.SDL_GetKeyFromScancode(c.SDL_SCANCODE_A, c.SDL_KMOD_NONE, false));
    try std.testing.expectEqual(@as(c.SDL_Keycode, 'A'), c.SDL_GetKeyFromScancode(c.SDL_SCANCODE_A, c.SDL_KMOD_SHIFT, false));
    event.scancode = c.SDL_SCANCODE_A;
    event.key = c.SDLK_Q;
    event.mod = c.SDL_KMOD_CTRL | c.SDL_KMOD_SHIFT;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(keyboard.consumeText());
    event.repeat = true;
    event.key = c.SDLK_Z;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(keyboard.consumeText());
    event.mod = c.SDL_KMOD_CTRL;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(keyboard.consumeText());
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    event.scancode = c.SDL_SCANCODE_EQUALS;
    event.key = c.SDLK_EQUALS;
    event.mod = c.SDL_KMOD_SHIFT;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("+"));
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("+"));
    event.repeat = false;
    event.mod = c.SDL_KMOD_NONE;
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    // A repeat uses the current modifier state, not the press's text route.
    event.scancode = c.SDL_SCANCODE_W;
    event.key = c.SDLK_W;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(try keyboard.commitText("w"));
    event.mod = c.SDL_KMOD_CTRL;
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    try std.testing.expect(keyboard.consumeText());
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    // Named functional events do not require a following SDL text commit.
    const functional = [_]struct { scan: c.SDL_Scancode, key: c.SDL_Keycode }{
        .{ .scan = c.SDL_SCANCODE_F13, .key = c.SDLK_F13 },
        .{ .scan = c.SDL_SCANCODE_MEDIA_PLAY_PAUSE, .key = c.SDLK_MEDIA_PLAY_PAUSE },
        .{ .scan = c.SDL_SCANCODE_PRINTSCREEN, .key = c.SDLK_PRINTSCREEN },
        .{ .scan = c.SDL_SCANCODE_APPLICATION, .key = c.SDLK_APPLICATION },
        .{ .scan = c.SDL_SCANCODE_SCROLLLOCK, .key = c.SDLK_SCROLLLOCK },
        .{ .scan = c.SDL_SCANCODE_MODE, .key = c.SDLK_MODE },
        .{ .scan = c.SDL_SCANCODE_KP_4, .key = c.SDLK_LEFT },
    };
    for (functional) |item| {
        event.scancode = item.scan;
        event.key = item.key;
        event.mod = c.SDL_KMOD_NONE;
        try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
        try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    }
    // These printable events have no accompanying SDL_TEXT_INPUT.
    // The next physical event must retire the previous pending transition.
    event.scancode = c.SDL_SCANCODE_B;
    event.key = c.SDLK_B;
    event.mod = c.SDL_KMOD_NONE;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    event.repeat = true;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    event.repeat = false;
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    event.scancode = c.SDL_SCANCODE_C;
    event.key = c.SDLK_C;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
    var ctrl: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    ctrl.scancode = c.SDL_SCANCODE_LCTRL;
    ctrl.key = c.SDLK_LCTRL;
    ctrl.mod = c.SDL_KMOD_LCTRL;
    try std.testing.expect((try keyboard.route(ctrl, true, owner, null, false)) == .handled);
    ctrl.mod = c.SDL_KMOD_NONE;
    try std.testing.expect((try keyboard.route(ctrl, false, owner, null, false)) == .handled);
    try std.testing.expect((try keyboard.route(event, false, owner, null, false)) == .handled);
    event.scancode = c.SDL_SCANCODE_D;
    event.key = c.SDLK_D;
    try std.testing.expect((try keyboard.route(event, true, owner, null, false)) == .handled);
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

test "PC101 base identity is confined to standard printable positions" {
    const letters = "abcdefghijklmnopqrstuvwxyz";
    for (letters, 0..) |letter, i| {
        const scan: c.SDL_Scancode = @intCast(c.SDL_SCANCODE_A + i);
        try std.testing.expectEqual(@as(?u21, letter), pc101Key(scan));
    }
    const digits = "1234567890";
    for (digits, 0..) |digit, i| {
        const scan: c.SDL_Scancode = @intCast(c.SDL_SCANCODE_1 + i);
        try std.testing.expectEqual(@as(?u21, digit), pc101Key(scan));
    }
    const cases = [_]struct { scan: c.SDL_Scancode, key: u21 }{
        .{ .scan = c.SDL_SCANCODE_SPACE, .key = ' ' },
        .{ .scan = c.SDL_SCANCODE_MINUS, .key = '-' },
        .{ .scan = c.SDL_SCANCODE_EQUALS, .key = '=' },
        .{ .scan = c.SDL_SCANCODE_LEFTBRACKET, .key = '[' },
        .{ .scan = c.SDL_SCANCODE_RIGHTBRACKET, .key = ']' },
        .{ .scan = c.SDL_SCANCODE_BACKSLASH, .key = 0x5c },
        .{ .scan = c.SDL_SCANCODE_SEMICOLON, .key = ';' },
        .{ .scan = c.SDL_SCANCODE_APOSTROPHE, .key = 0x27 },
        .{ .scan = c.SDL_SCANCODE_GRAVE, .key = 0x60 },
        .{ .scan = c.SDL_SCANCODE_COMMA, .key = ',' },
        .{ .scan = c.SDL_SCANCODE_PERIOD, .key = '.' },
        .{ .scan = c.SDL_SCANCODE_SLASH, .key = '/' },
    };
    for (cases) |case| try std.testing.expectEqual(@as(?u21, case.key), pc101Key(case.scan));
    var count: usize = 0;
    for (0..c.SDL_SCANCODE_COUNT) |i| {
        if (pc101Key(@intCast(i)) != null) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 48), count);
    for ([_]c.SDL_Scancode{ c.SDL_SCANCODE_UNKNOWN, c.SDL_SCANCODE_NONUSHASH, c.SDL_SCANCODE_NONUSBACKSLASH, c.SDL_SCANCODE_INTERNATIONAL1, c.SDL_SCANCODE_KP_1, c.SDL_SCANCODE_F1 }) |scan|
        try std.testing.expectEqual(@as(?u21, null), pc101Key(scan));
}

test "SDL layout identities encode Cyrillic French and missing alternate facts without substitution" {
    var vt = try VT.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    try std.testing.expect((try vt.feed("\x1b[=31u")).stateChanged());
    var scratch: VT.InputScratch = .{};
    const cases = [_]struct {
        scan: c.SDL_Scancode,
        primary: c.SDL_Keycode,
        shift: c.SDL_Keycode,
        press: []const u8,
        release: []const u8,
    }{
        .{ .scan = c.SDL_SCANCODE_C, .primary = 0x441, .shift = 0x421, .press = "\x1b[1089:1057:99;6u", .release = "\x1b[1089::99;5:3u" },
        .{ .scan = c.SDL_SCANCODE_1, .primary = '&', .shift = '1', .press = "\x1b[38:49:49;6u", .release = "\x1b[38::49;5:3u" },
        .{ .scan = c.SDL_SCANCODE_A, .primary = 'a', .shift = 'A', .press = "\x1b[97:65;6u", .release = "\x1b[97;5:3u" },
        .{ .scan = c.SDL_SCANCODE_NONUSBACKSLASH, .primary = 'é', .shift = 'É', .press = "\x1b[233:201;6u", .release = "\x1b[233;5:3u" },
        .{ .scan = c.SDL_SCANCODE_C, .primary = 0x441, .shift = c.SDLK_UNKNOWN, .press = "\x1b[1089::99;6u", .release = "\x1b[1089::99;5:3u" },
        .{ .scan = c.SDL_SCANCODE_SPACE, .primary = ' ', .shift = ' ', .press = "\x1b[32;6u", .release = "\x1b[32;5:3u" },
    };
    for (cases) |case| {
        const identity = layoutIdentity(case.scan, case.primary, case.shift) orelse return error.MissingIdentity;
        var press = try vt.encodeInput(std.testing.allocator, &scratch, identity.event(.{ .control = true, .shift = true }, .press, ""));
        defer press.deinit();
        try std.testing.expectEqualStrings(case.press, press.bytes);
        var released = try vt.encodeInput(std.testing.allocator, &scratch, identity.event(.{ .control = true }, .release, ""));
        defer released.deinit();
        try std.testing.expectEqualStrings(case.release, released.bytes);
    }
    for ([_]c.SDL_Keycode{ c.SDLK_UNKNOWN, c.SDLK_F1, 0xd800, 0x110000, 127, 159 }) |invalid| {
        try std.testing.expect(layoutIdentity(c.SDL_SCANCODE_A, invalid, 'A') == null);
        const identity = layoutIdentity(c.SDL_SCANCODE_A, 'a', invalid) orelse return error.MissingIdentity;
        try std.testing.expectEqual(@as(?u21, null), identity.shifted);
    }
}

test "SDL extended functional key mapping preserves explicit keypad provenance" {
    try std.testing.expectEqual(@as(?VT.NamedKey, .f13), namedKey(c.SDLK_F13));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f14), namedKey(c.SDLK_F14));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f15), namedKey(c.SDLK_F15));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f16), namedKey(c.SDLK_F16));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f17), namedKey(c.SDLK_F17));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f18), namedKey(c.SDLK_F18));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f19), namedKey(c.SDLK_F19));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f20), namedKey(c.SDLK_F20));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f21), namedKey(c.SDLK_F21));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f22), namedKey(c.SDLK_F22));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f23), namedKey(c.SDLK_F23));
    try std.testing.expectEqual(@as(?VT.NamedKey, .f24), namedKey(c.SDLK_F24));
    try std.testing.expectEqual(@as(?VT.NamedKey, .scroll_lock), namedKey(c.SDLK_SCROLLLOCK));
    try std.testing.expectEqual(@as(?VT.NamedKey, .print_screen), namedKey(c.SDLK_PRINTSCREEN));
    try std.testing.expectEqual(@as(?VT.NamedKey, .pause), namedKey(c.SDLK_PAUSE));
    try std.testing.expectEqual(@as(?VT.NamedKey, .menu), namedKey(c.SDLK_APPLICATION));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_play), namedKey(c.SDLK_MEDIA_PLAY));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_pause), namedKey(c.SDLK_MEDIA_PAUSE));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_play_pause), namedKey(c.SDLK_MEDIA_PLAY_PAUSE));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_stop), namedKey(c.SDLK_MEDIA_STOP));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_fast_forward), namedKey(c.SDLK_MEDIA_FAST_FORWARD));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_rewind), namedKey(c.SDLK_MEDIA_REWIND));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_track_next), namedKey(c.SDLK_MEDIA_NEXT_TRACK));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_track_previous), namedKey(c.SDLK_MEDIA_PREVIOUS_TRACK));
    try std.testing.expectEqual(@as(?VT.NamedKey, .media_record), namedKey(c.SDLK_MEDIA_RECORD));
    try std.testing.expectEqual(@as(?VT.NamedKey, .lower_volume), namedKey(c.SDLK_VOLUMEDOWN));
    try std.testing.expectEqual(@as(?VT.NamedKey, .raise_volume), namedKey(c.SDLK_VOLUMEUP));
    try std.testing.expectEqual(@as(?VT.NamedKey, .mute_volume), namedKey(c.SDLK_MUTE));
    try std.testing.expectEqual(@as(?VT.NamedKey, .iso_level3_shift), namedKey(c.SDLK_MODE));
    try std.testing.expectEqual(@as(?VT.NamedKey, .iso_level5_shift), namedKey(c.SDLK_LEVEL5_SHIFT));
    try std.testing.expectEqual(@as(?VT.NamedKey, .menu), namedKey(c.SDLK_MENU));
    var event: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
    const cases = [_]struct { scan: c.SDL_Scancode, code: c.SDL_Keycode, key: VT.NamedKey }{
        .{ .scan = c.SDL_SCANCODE_KP_1, .code = c.SDLK_END, .key = .keypad_end },
        .{ .scan = c.SDL_SCANCODE_KP_2, .code = c.SDLK_DOWN, .key = .keypad_down },
        .{ .scan = c.SDL_SCANCODE_KP_3, .code = c.SDLK_PAGEDOWN, .key = .keypad_page_down },
        .{ .scan = c.SDL_SCANCODE_KP_4, .code = c.SDLK_LEFT, .key = .keypad_left },
        .{ .scan = c.SDL_SCANCODE_KP_5, .code = c.SDLK_CLEAR, .key = .keypad_begin },
        .{ .scan = c.SDL_SCANCODE_KP_6, .code = c.SDLK_RIGHT, .key = .keypad_right },
        .{ .scan = c.SDL_SCANCODE_KP_7, .code = c.SDLK_HOME, .key = .keypad_home },
        .{ .scan = c.SDL_SCANCODE_KP_8, .code = c.SDLK_UP, .key = .keypad_up },
        .{ .scan = c.SDL_SCANCODE_KP_9, .code = c.SDLK_PAGEUP, .key = .keypad_page_up },
        .{ .scan = c.SDL_SCANCODE_KP_0, .code = c.SDLK_INSERT, .key = .keypad_insert },
        .{ .scan = c.SDL_SCANCODE_KP_PERIOD, .code = c.SDLK_DELETE, .key = .keypad_delete },
    };
    for (cases) |case| {
        event.scancode = case.scan;
        event.key = case.code;
        for ([_]c.SDL_Keymod{ c.SDL_KMOD_NONE, c.SDL_KMOD_NUM }) |mods| {
            event.mod = mods;
            try std.testing.expectEqual(@as(?VT.NamedKey, case.key), eventNamedKey(event));
        }
    }
    event.scancode = c.SDL_SCANCODE_LEFT;
    event.key = c.SDLK_LEFT;
    try std.testing.expectEqual(@as(?VT.NamedKey, .left), eventNamedKey(event));
    event.scancode = c.SDL_SCANCODE_KP_4;
    event.key = c.SDLK_KP_4;
    event.mod = c.SDL_KMOD_NONE;
    try std.testing.expectEqual(@as(?VT.NamedKey, .keypad_4), eventNamedKey(event));
    try std.testing.expect(namedKey(c.SDLK_MULTI_KEY_COMPOSE) == null);
    try std.testing.expect(namedKey(c.SDLK_MEDIA_EJECT) == null);
    try std.testing.expect(namedKey(c.SDLK_LHYPER) == null);
    try std.testing.expect(namedKey(c.SDLK_LMETA) == null);
}

test "pending platform keys follow live negotiation and close at the SDL batch boundary" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const long_commit: [VT.maximum_key_text_bytes + 1]u8 = @splat('z');
    const long_frame = "\x1b[0;;122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122:122u";
    const enhanced_bytes = "\x1b[98;;98u\x1b[98;1:3u\x1b[99u\x1b[0;;233u\x1b[99;1:3u" ++ long_frame ++ "DOWN";
    const command = try std.fmt.allocPrint(std.testing.allocator, "stty raw -echo; printf '\\033[=0u\\033]0;LEGACY\\007'; " ++
        "read_hex() {{ dd bs=1 count=\"$1\" 2>/dev/null | od -v -An -tx1 | tr -d ' \\n'; }}; " ++
        "value=$(read_hex 2); printf '\\033[=31u\\033]0;UP-%s\\007' \"$value\"; " ++
        "value=$(read_hex {d}); printf '\\033[=0u\\033]0;DOWN-%s\\007' \"$value\"; " ++
        "value=$(read_hex 5); printf '\\033[=31u\\033]0;UP2-%s\\007' \"$value\"; " ++
        "value=$(read_hex 5); printf '\\033[=0u\\033]0;DOWN2-%s\\007' \"$value\"; " ++
        "value=$(read_hex 6); printf '\\033]0;DONE-%s\\007' \"$value\"; sleep 30", .{enhanced_bytes.len});
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
        fn wait(t: *terminal.Terminal, io: std.Io, title: []const u8, flags: u8) !void {
            for (0..5000) |_| {
                const status = t.snapshot();
                if (status.failure) |failure| return failure;
                if (status.interaction != null and status.interaction.?.kitty_keyboard_flags == flags and
                    std.mem.eql(u8, status.title[0..status.title_len], title)) return;
                try std.Io.sleep(io, .fromMilliseconds(1), .awake);
            }
            const observed = t.snapshot();
            std.debug.print("platform text proof expected title={s} flags={d}; actual title={s} flags={?d}\n", .{
                title,
                flags,
                observed.title[0..observed.title_len],
                if (observed.interaction) |interaction| interaction.kitty_keyboard_flags else null,
            });
            return error.Timeout;
        }
        fn key(k: *Keyboard, t: *terminal.Terminal, scan: c.SDL_Scancode, code: c.SDL_Keycode, press: bool) !void {
            var e: c.SDL_KeyboardEvent = std.mem.zeroes(c.SDL_KeyboardEvent);
            e.scancode = scan;
            e.key = code;
            try std.testing.expect((try k.route(e, press, t, null, false)) == .handled);
        }
    };
    var keyboard: Keyboard = .{};
    try Check.wait(owner, threaded.io(), "LEGACY", 0);
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_A, c.SDLK_A, true);
    try keyboard.flushPending();
    try keyboard.flushPending();
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_A, c.SDLK_A, false);
    try std.testing.expect(!owner.takeInputActivity());

    // Explicit raw markers let the child change modes while a physical
    // event is still waiting for text on the UI side.
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_B, c.SDLK_B, true);
    try std.testing.expect(keyboard.pending_text != null);
    try owner.submit(.{ .input = .{ .bytes = "UP" } });
    try Check.wait(owner, threaded.io(), "UP-" ++ std.fmt.bytesToHex("UP", .lower), 31);
    try std.testing.expect(try keyboard.commitText("b"));
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_B, c.SDLK_B, false);

    // A drained batch with no text sends exactly one bare key. A later
    // text-only event has no longer a known originating physical event.
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_C, c.SDLK_C, true);
    try keyboard.flushPending();
    try keyboard.flushPending();
    try std.testing.expect(!try keyboard.commitText("é"));
    try owner.submit(.{ .input = .{ .committed_text = "é" } });
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_C, c.SDLK_C, false);
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_H, c.SDLK_H, true);
    try std.testing.expect(try keyboard.commitText(&long_commit));
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_H, c.SDLK_H, false);

    try Check.key(&keyboard, owner, c.SDL_SCANCODE_E, c.SDLK_E, true);
    try owner.submit(.{ .input = .{ .bytes = "DOWN" } });
    try Check.wait(owner, threaded.io(), "DOWN-" ++ std.fmt.bytesToHex(enhanced_bytes, .lower), 0);
    try keyboard.flushPending();
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_E, c.SDLK_E, false);
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_F, c.SDLK_F, true);
    try std.testing.expect(try keyboard.commitText("é"));
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_F, c.SDLK_F, false);
    try owner.submit(.{ .input = .{ .bytes = "UP2" } });
    try Check.wait(owner, threaded.io(), "UP2-" ++ std.fmt.bytesToHex("éUP2", .lower), 31);

    try Check.key(&keyboard, owner, c.SDL_SCANCODE_G, c.SDLK_G, true);
    try owner.submit(.{ .input = .{ .bytes = "DOWN2" } });
    try Check.wait(owner, threaded.io(), "DOWN2-" ++ std.fmt.bytesToHex("DOWN2", .lower), 0);
    try std.testing.expect(try keyboard.commitText("界"));
    try Check.key(&keyboard, owner, c.SDL_SCANCODE_G, c.SDLK_G, false);
    try owner.submit(.{ .input = .{ .bytes = "END" } });
    try Check.wait(owner, threaded.io(), "DONE-" ++ std.fmt.bytesToHex("界END", .lower), 0);
    try std.testing.expect(keyboard.pending_text == null);
    try std.testing.expectEqual(Kind.none, keyboard.held[c.SDL_SCANCODE_G].kind);
}
