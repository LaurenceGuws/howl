//! Typed terminal input facts and mode-directed byte encoders.

const std = @import("std");

// Caller-to-child input encoding.

/// Caller-owned fixed storage for nonallocating input encodings.
pub const Scratch = struct {
    buf: [512]u8 = undefined,
};

/// Reports paste length overflow or allocation failure.
pub const PasteError = error{ LengthOverflow, OutOfMemory };

/// Encode borrowed paste text for the active bracketed-paste mode.
///
/// Plain paste returns a borrowed view of `text` without allocating. Bracketed
/// paste allocates one caller-owned result containing the fixed CSI 200/201
/// pair. Encoded-length overflow is distinct from allocator exhaustion. The
/// caller must call `Encoded.deinit` once for either successful result.
pub fn encodePaste(bracketed_paste: bool, allocator: std.mem.Allocator, text: []const u8) PasteError!Encoded {
    const start = if (bracketed_paste) "\x1b[200~" else "";
    const end = if (bracketed_paste) "\x1b[201~" else "";
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const encoded_len = try bracketedPasteLength(text.len);
    const out = try allocator.alloc(u8, encoded_len);
    std.debug.assert(out.len == encoded_len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

fn bracketedPasteLength(text_len: usize) error{LengthOverflow}!usize {
    const with_start = std.math.add(usize, "\x1b[200~".len, text_len) catch return error.LengthOverflow;
    return std.math.add(usize, with_start, "\x1b[201~".len) catch return error.LengthOverflow;
}

/// Copy fixed protocol bytes into caller scratch storage.
///
/// The returned slice borrows `scratch` until its next use.
pub fn writeScratch(scratch: *Scratch, bytes: []const u8) []const u8 {
    std.debug.assert(bytes.len <= scratch.buf.len);
    @memcpy(scratch.buf[0..bytes.len], bytes);
    return scratch.buf[0..bytes.len];
}

test "bracketed paste length reports arithmetic overflow" {
    try std.testing.expectEqual(@as(usize, 15), try bracketedPasteLength(3));
    try std.testing.expectError(error.LengthOverflow, bracketedPasteLength(std.math.maxInt(usize)));
}

/// Holds encoded bytes that either borrow caller scratch or own one allocation.
pub const Encoded = struct {
    allocator: ?std.mem.Allocator = null,
    bytes: []const u8 = "",

    /// Release owned bytes, or only clear a borrowed result.
    ///
    /// Every successful input encoding result accepts one call. The value is
    /// reset afterward so it retains neither ownership nor a borrowed slice.
    pub fn deinit(self: *Encoded) void {
        if (self.allocator) |allocator| allocator.free(self.bytes);
        self.* = .{};
    }
};

test "encoded owner deinit releases owned buffer" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, "payload");
    var encoded: Encoded = .{ .allocator = allocator, .bytes = bytes };

    encoded.deinit();

    try std.testing.expectEqual(@as(?std.mem.Allocator, null), encoded.allocator);
    try std.testing.expectEqualStrings("", encoded.bytes);
}

test "paste encoding distinguishes borrowed and owned results" {
    const text = "paste";
    var no_storage: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_storage);

    var plain = try encodePaste(false, fixed.allocator(), text);
    try std.testing.expectEqualStrings(text, plain.bytes);
    try std.testing.expectEqual(text.ptr, plain.bytes.ptr);
    try std.testing.expectEqual(@as(?std.mem.Allocator, null), plain.allocator);
    plain.deinit();
    try std.testing.expectEqualStrings("", plain.bytes);

    try std.testing.expectError(error.OutOfMemory, encodePaste(true, fixed.allocator(), text));

    var bracketed = try encodePaste(true, std.testing.allocator, text);
    try std.testing.expectEqualStrings("\x1b[200~paste\x1b[201~", bracketed.bytes);
    try std.testing.expect(bracketed.allocator != null);
    bracketed.deinit();
    try std.testing.expectEqualStrings("", bracketed.bytes);
    try std.testing.expectEqual(@as(?std.mem.Allocator, null), bracketed.allocator);
}

/// Borrow-free physical key event with typed identity and complete modifiers.
pub const KeyEvent = struct {
    key: InputKey,
    mods: Modifier = .{},
    action: Action = .press,
    shifted: ?u21 = null,
    alternate: ?u21 = null,
    /// Borrows the exact bytes used only by legacy terminal encoding.
    legacy_text: []const u8 = "",
    /// Borrows committed text for this press/repeat until encoding returns.
    text: []const u8 = "",
};

/// Identifies caller focus gained or lost for terminal focus reporting.
pub const FocusEvent = enum {
    in,
    out,
};

/// Caller input borrowed by one terminal encoding call.
///
/// `bytes` carries committed text, while `key` carries a named or validated
/// Unicode physical-key event for terminal keyboard protocol encoding. Byte
/// and paste slices must remain valid until `Terminal.encodeInput` returns.
pub const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

test "event owner exposes input union tags" {
    const key_event: Event = .{ .key = .{ .key = .{ .named = .enter } } };
    const focus_event: Event = .{ .focus = .in };

    try std.testing.expectEqual(@as(std.meta.Tag(Event), .key), std.meta.activeTag(key_event));
    try std.testing.expectEqual(@as(std.meta.Tag(Event), .focus), std.meta.activeTag(focus_event));
}

/// Named physical key whose terminal identity is distinct from Unicode text.
pub const KeyName = enum {
    enter,
    tab,
    backspace,
    escape,
    up,
    down,
    left,
    right,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    left_hyper,
    right_hyper,
    left_meta,
    right_meta,
    caps_lock,
    num_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_add,
    keypad_subtract,
    keypad_multiply,
    keypad_divide,
    keypad_separator,
    keypad_equal,
    keypad_enter,
};

/// Valid Unicode scalar produced by one physical key event.
const UnicodeScalar = struct {
    value: u21,

    /// Validate one scalar before it enters terminal keyboard encoding.
    ///
    /// Surrogate halves and values outside Unicode's scalar range are rejected.
    fn init(value: u21) error{InvalidUnicodeScalar}!UnicodeScalar {
        if (!std.unicode.utf8ValidCodepoint(value)) return error.InvalidUnicodeScalar;
        return .{ .value = value };
    }
};

/// Physical key identity consumed by terminal keyboard protocols.
pub const InputKey = union(enum) {
    named: KeyName,
    unicode: UnicodeScalar,

    /// Construct a Unicode key, rejecting non-scalar values.
    pub fn initUnicode(value: u21) error{InvalidUnicodeScalar}!InputKey {
        return .{ .unicode = try UnicodeScalar.init(value) };
    }
};

/// Identifies one physical key transition for Kitty event reporting.
pub const Action = enum(u2) { press = 1, repeat = 2, release = 3 };

/// Bounds committed key text before decimal Kitty encoding.
const max_text_bytes: u8 = 64;

/// Complete modifier state accepted by terminal keyboard and mouse protocols.
///
/// The packed representation has no spare bits, so every value is valid.
pub const Modifier = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    control: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    fn protocolBits(self: Modifier) u8 {
        return @bitCast(self);
    }

    fn protocolParameter(self: Modifier) u16 {
        return 1 + @as(u16, self.protocolBits());
    }

    fn none(self: Modifier) bool {
        return self.protocolBits() == 0;
    }

    fn legacy(self: Modifier) Modifier {
        return .{ .shift = self.shift, .alt = self.alt, .control = self.control };
    }
};

const max_encoded_len: usize = 32;
// One-byte UTF-8 scalars maximize decimal text bytes: three digits plus one
// separator per source byte. The remaining fields use their exact maxima.
const max_associated_encoded_bytes: usize = @as(usize, max_text_bytes) * 4;
/// Bounds one complete Kitty key encoding under the 64-byte text limit.
pub const max_kitty_encoded_bytes: usize = 2 + 7 + 1 + 7 + 1 + 7 +
    1 + 3 + 1 + 1 + max_associated_encoded_bytes + 1;

/// Encode one caller key for the active terminal keyboard modes.
pub fn encodeKey(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_keyboard_flags: u8,
) []const u8 {
    const report_all = kitty_keyboard_flags & 8 != 0;
    const disambiguate = kitty_keyboard_flags & 1 != 0;
    if (report_all) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    } else if (disambiguate) {
        if (encodeDisambiguatedKey(buf, key, mod)) |encoded| return encoded;
    }
    const legacy_mod = mod.legacy();
    return switch (key) {
        .named => |named| encodeNamedKey(buf, named, legacy_mod, application_cursor_keys, application_keypad),
        .unicode => |scalar| encodeTextKey(buf, scalar.value, legacy_mod, modify_other_keys, format_other_keys),
    };
}

/// Encodes one complete physical key fact under current terminal modes.
pub fn encodeEvent(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    action: Action,
    shifted: ?u21,
    alternate: ?u21,
    legacy_text: []const u8,
    text: []const u8,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_flags: u8,
) error{ InvalidUtf8, InvalidText, KeyTextLimit, EncodingLimit }![]const u8 {
    if (text.len > max_text_bytes) return error.KeyTextLimit;
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (kitty_flags & 16 != 0 and kitty_flags & 8 != 0) {
        var text_view = std.unicode.Utf8View.initUnchecked(text);
        var text_iterator = text_view.iterator();
        while (text_iterator.nextCodepoint()) |codepoint|
            if (codepoint < 32 or (codepoint >= 127 and codepoint <= 159))
                return error.InvalidText;
    }
    const report_all = kitty_flags & 8 != 0;
    if (key == .named and isModifier(key.named) and !report_all)
        return buf[0..0];
    if (key == .named and isLegacyControl(key.named) and !report_all and mod.none()) {
        if (action == .release) return buf[0..0];
        return encodeKey(
            buf,
            key,
            mod,
            application_cursor_keys,
            application_keypad,
            modify_other_keys,
            format_other_keys,
            0,
        );
    }
    const report_events = kitty_flags & 2 != 0;
    if (action == .release and !report_events) return buf[0..0];
    if (legacy_text.len != 0 and !report_all and action != .release)
        return legacy_text;
    if (kitty_flags & (2 | 4 | 8 | 16) != 0)
        return try encodeKittyEvent(buf, key, mod, action, shifted, alternate, text, kitty_flags);
    return encodeKey(
        buf,
        legacyKey(key, mod, shifted),
        mod,
        application_cursor_keys,
        application_keypad,
        modify_other_keys,
        format_other_keys,
        kitty_flags,
    );
}

// Legacy terminals consume the produced Shift identity, while extended key
// protocols retain physical, shifted, and alternate identities separately.
fn legacyKey(key: InputKey, mod: Modifier, shifted: ?u21) InputKey {
    if (!mod.shift) return key;
    return switch (key) {
        .named => key,
        .unicode => if (shifted) |value| InputKey.initUnicode(value) catch key else key,
    };
}

fn isLegacyControl(key: KeyName) bool {
    return key == .enter or key == .tab or key == .backspace;
}

fn isModifier(key: KeyName) bool {
    return switch (key) {
        .left_shift,
        .right_shift,
        .left_control,
        .right_control,
        .left_alt,
        .right_alt,
        .left_super,
        .right_super,
        .left_hyper,
        .right_hyper,
        .left_meta,
        .right_meta,
        .caps_lock,
        .num_lock,
        => true,
        else => false,
    };
}

fn encodeKittyEvent(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    action: Action,
    shifted: ?u21,
    alternate: ?u21,
    text: []const u8,
    flags: u8,
) error{EncodingLimit}![]const u8 {
    if (buf.len < max_kitty_encoded_bytes) return error.EncodingLimit;
    var builder = Builder.init(buf);
    try builder.append("\x1b[");
    const identity = kittyIdentityForKey(key);
    try builder.decimal(identity.code);
    if (flags & 4 != 0 and (shifted != null or alternate != null)) {
        try builder.append(":");
        if (shifted) |value| try builder.decimal(value);
        if (alternate) |value| {
            try builder.append(":");
            try builder.decimal(value);
        }
    }
    const add_action = flags & 2 != 0 and action != .press;
    const add_text = flags & 16 != 0 and flags & 8 != 0 and text.len != 0;
    if (!mod.none() or add_action or add_text) {
        try builder.append(";");
        if (!mod.none() or add_action) try builder.decimal(mod.protocolParameter());
        if (add_action) {
            try builder.append(":");
            try builder.decimal(@backingInt(action));
        }
    }
    if (add_text) {
        var view = std.unicode.Utf8View.initUnchecked(text);
        var iterator = view.iterator();
        var first = true;
        while (iterator.nextCodepoint()) |codepoint| {
            try builder.append(if (first) ";" else ":");
            first = false;
            try builder.decimal(codepoint);
        }
    }
    try builder.append(&.{identity.trailer});
    return builder.written();
}

const KittyIdentity = struct { code: u32, trailer: u8 = 'u' };

fn kittyIdentityForKey(key: InputKey) KittyIdentity {
    return switch (key) {
        .unicode => |scalar| .{ .code = scalar.value },
        .named => |named| switch (named) {
            .escape => .{ .code = 27 },
            .enter => .{ .code = 13 },
            .tab => .{ .code = 9 },
            .backspace => .{ .code = 127 },
            .insert => .{ .code = 2, .trailer = '~' },
            .delete => .{ .code = 3, .trailer = '~' },
            .up => .{ .code = 1, .trailer = 'A' },
            .down => .{ .code = 1, .trailer = 'B' },
            .right => .{ .code = 1, .trailer = 'C' },
            .left => .{ .code = 1, .trailer = 'D' },
            .home => .{ .code = 1, .trailer = 'H' },
            .end => .{ .code = 1, .trailer = 'F' },
            .page_up => .{ .code = 5, .trailer = '~' },
            .page_down => .{ .code = 6, .trailer = '~' },
            .f1 => .{ .code = 1, .trailer = 'P' },
            .f2 => .{ .code = 1, .trailer = 'Q' },
            .f3 => .{ .code = 13, .trailer = '~' },
            .f4 => .{ .code = 1, .trailer = 'S' },
            .f5 => .{ .code = 15, .trailer = '~' },
            .f6 => .{ .code = 17, .trailer = '~' },
            .f7 => .{ .code = 18, .trailer = '~' },
            .f8 => .{ .code = 19, .trailer = '~' },
            .f9 => .{ .code = 20, .trailer = '~' },
            .f10 => .{ .code = 21, .trailer = '~' },
            .f11 => .{ .code = 23, .trailer = '~' },
            .f12 => .{ .code = 24, .trailer = '~' },
            .keypad_0 => .{ .code = 57399 },
            .keypad_1 => .{ .code = 57400 },
            .keypad_2 => .{ .code = 57401 },
            .keypad_3 => .{ .code = 57402 },
            .keypad_4 => .{ .code = 57403 },
            .keypad_5 => .{ .code = 57404 },
            .keypad_6 => .{ .code = 57405 },
            .keypad_7 => .{ .code = 57406 },
            .keypad_8 => .{ .code = 57407 },
            .keypad_9 => .{ .code = 57408 },
            .keypad_decimal => .{ .code = 57409 },
            .keypad_divide => .{ .code = 57410 },
            .keypad_multiply => .{ .code = 57411 },
            .keypad_subtract => .{ .code = 57412 },
            .keypad_add => .{ .code = 57413 },
            .keypad_enter => .{ .code = 57414 },
            .keypad_equal => .{ .code = 57415 },
            .keypad_separator => .{ .code = 57416 },
            .left_shift => .{ .code = 57441 },
            .left_control => .{ .code = 57442 },
            .left_alt => .{ .code = 57443 },
            .left_super => .{ .code = 57444 },
            .right_shift => .{ .code = 57447 },
            .right_control => .{ .code = 57448 },
            .right_alt => .{ .code = 57449 },
            .right_super => .{ .code = 57450 },
            .left_hyper => .{ .code = 57445 },
            .left_meta => .{ .code = 57446 },
            .right_hyper => .{ .code = 57451 },
            .right_meta => .{ .code = 57452 },
            .caps_lock => .{ .code = 57358 },
            .num_lock => .{ .code = 57360 },
        },
    };
}

const Builder = struct {
    bytes: []u8,
    len: usize = 0,

    fn init(bytes: []u8) Builder {
        return .{ .bytes = bytes };
    }

    fn append(self: *Builder, bytes: []const u8) error{EncodingLimit}!void {
        if (self.len > self.bytes.len or bytes.len > self.bytes.len - self.len)
            return error.EncodingLimit;
        @memcpy(self.bytes[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    fn decimal(self: *Builder, value: u32) error{EncodingLimit}!void {
        const digits = std.fmt.bufPrint(self.bytes[self.len..], "{d}", .{value}) catch
            return error.EncodingLimit;
        self.len += digits.len;
    }

    fn written(self: *const Builder) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn encodeDisambiguatedKey(buf: []u8, key: InputKey, mod: Modifier) ?[]const u8 {
    return switch (key) {
        .unicode => null,
        .named => |named| switch (named) {
            .escape => csiU(buf, 27, mod.protocolParameter()),
            .enter, .tab, .backspace => if (mod.none()) null else encodeKittyKey(buf, key, mod),
            else => encodeKittyKey(buf, key, mod),
        },
    };
}

fn encodeNamedKey(
    buf: []u8,
    key: KeyName,
    mod: Modifier,
    application_cursor_keys: bool,
    application_keypad: bool,
) []const u8 {
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    if (encodeControlKey(buf, key, mod)) |encoded| return encoded;
    if (encodeCursorKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeHomeEndKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeTildeKey(buf, key, mod)) |encoded| return encoded;
    if (encodeFunctionKey(buf, key, mod)) |encoded| return encoded;
    return buf[0..0];
}

fn encodeKeypadKey(buf: []u8, key: KeyName, application_keypad: bool) ?[]const u8 {
    const normal: ?u8 = switch (key) {
        .keypad_0 => '0',
        .keypad_1 => '1',
        .keypad_2 => '2',
        .keypad_3 => '3',
        .keypad_4 => '4',
        .keypad_5 => '5',
        .keypad_6 => '6',
        .keypad_7 => '7',
        .keypad_8 => '8',
        .keypad_9 => '9',
        .keypad_decimal => '.',
        .keypad_add => '+',
        .keypad_subtract => '-',
        .keypad_multiply => '*',
        .keypad_divide => '/',
        .keypad_separator => ',',
        .keypad_equal => '=',
        .keypad_enter => '\r',
        else => null,
    };
    const ch = normal orelse return null;
    if (!application_keypad) {
        std.debug.assert(buf.len >= 1);
        buf[0] = ch;
        return buf[0..1];
    }
    const final: u8 = switch (key) {
        .keypad_0 => 'p',
        .keypad_1 => 'q',
        .keypad_2 => 'r',
        .keypad_3 => 's',
        .keypad_4 => 't',
        .keypad_5 => 'u',
        .keypad_6 => 'v',
        .keypad_7 => 'w',
        .keypad_8 => 'x',
        .keypad_9 => 'y',
        .keypad_decimal => 'n',
        .keypad_add => 'k',
        .keypad_subtract => 'm',
        .keypad_multiply => 'j',
        .keypad_divide => 'o',
        .keypad_separator => 'l',
        .keypad_equal => 'X',
        .keypad_enter => 'M',
        else => return null,
    };
    std.debug.assert(buf.len >= 3);
    buf[0] = '\x1b';
    buf[1] = 'O';
    buf[2] = final;
    return buf[0..3];
}

fn encodeModifyOtherKey(
    buf: []u8,
    codepoint: u21,
    mod: Modifier,
    modify_other_keys: i8,
    format_other_keys: u16,
) ?[]const u8 {
    if (modify_other_keys < 2 and !(modify_other_keys == 1 and format_other_keys == 1)) return null;
    if (mod.none() and modify_other_keys < 3) return null;
    if (format_other_keys == 1) {
        return std.fmt.bufPrint(
            buf,
            "\x1b[{d};{d}u",
            .{ codepoint, mod.protocolParameter() },
        ) catch null;
    }
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ mod.protocolParameter(), codepoint }) catch null;
}

fn encodeKittyKey(buf: []u8, key: InputKey, mod: Modifier) ?[]const u8 {
    const modifier = mod.protocolParameter();
    return switch (key) {
        .unicode => |scalar| csiU(buf, scalar.value, modifier),
        .named => |named| switch (named) {
            .enter => csiU(buf, 13, modifier),
            .tab => csiU(buf, 9, modifier),
            .backspace => csiU(buf, 127, modifier),
            .escape => csiU(buf, 27, modifier),
            .up => csiFinal(buf, 'A', modifier),
            .down => csiFinal(buf, 'B', modifier),
            .right => csiFinal(buf, 'C', modifier),
            .left => csiFinal(buf, 'D', modifier),
            .home => csiFinal(buf, 'H', modifier),
            .end => csiFinal(buf, 'F', modifier),
            .f1 => csiFinal(buf, 'P', modifier),
            .f2 => csiFinal(buf, 'Q', modifier),
            .f3 => csiTilde(buf, 13, modifier),
            .f4 => csiFinal(buf, 'S', modifier),
            .insert => csiTilde(buf, 2, modifier),
            .delete => csiTilde(buf, 3, modifier),
            .page_up => csiTilde(buf, 5, modifier),
            .page_down => csiTilde(buf, 6, modifier),
            .f5 => csiTilde(buf, 15, modifier),
            .f6 => csiTilde(buf, 17, modifier),
            .f7 => csiTilde(buf, 18, modifier),
            .f8 => csiTilde(buf, 19, modifier),
            .f9 => csiTilde(buf, 20, modifier),
            .f10 => csiTilde(buf, 21, modifier),
            .f11 => csiTilde(buf, 23, modifier),
            .f12 => csiTilde(buf, 24, modifier),
            else => null,
        },
    };
}

fn encodeControlKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const bytes = switch (key) {
        .enter => "\r",
        .tab => if (mod.shift) "\x1b[Z" else "\t",
        .backspace => "\x7f",
        .escape => "\x1b",
        else => null,
    } orelse return null;
    if (!mod.alt) return writeBytes(buf, bytes);
    buf[0] = '\x1b';
    @memcpy(buf[1 .. bytes.len + 1], bytes);
    return buf[0 .. bytes.len + 1];
}

fn encodeCursorKey(buf: []u8, key: KeyName, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        .up => 'A',
        .down => 'B',
        .right => 'C',
        .left => 'D',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeHomeEndKey(buf: []u8, key: KeyName, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        .home => 'H',
        .end => 'F',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTildeKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const code: u8 = switch (key) {
        .insert => 2,
        .delete => 3,
        .page_up => 5,
        .page_down => 6,
        .f5 => 15,
        .f6 => 17,
        .f7 => 18,
        .f8 => 19,
        .f9 => 20,
        .f10 => 21,
        .f11 => 23,
        .f12 => 24,
        else => return null,
    };
    return if (!mod.none())
        csiTildeModified(buf, code, mod)
    else
        csiTildePlain(buf, code);
}

fn encodeFunctionKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        .f1 => 'P',
        .f2 => 'Q',
        .f3 => 'R',
        .f4 => 'S',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', 'O', final);
}

fn encodeTextKey(buf: []u8, codepoint: u21, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) []const u8 {
    if (codepoint > 31 and codepoint < 127) {
        if (encodeModifyOtherKey(buf, codepoint, mod, modify_other_keys, format_other_keys)) |encoded| return encoded;
    }
    if (mod.control) if (legacyControlByte(codepoint)) |byte| {
        if (!mod.alt) return writeBytes(buf, &.{byte});
        buf[0] = '\x1b';
        buf[1] = byte;
        return buf[0..2];
    };
    const prefix_len: usize = @intFromBool(mod.alt);
    if (mod.alt) buf[0] = '\x1b';
    if (codepoint > 31 and codepoint < 127) {
        buf[prefix_len] = @intCast(codepoint);
        return buf[0 .. prefix_len + 1];
    }
    if (codepoint > 127) {
        const len = std.unicode.utf8Encode(codepoint, buf[prefix_len..]) catch unreachable;
        std.debug.assert(prefix_len + len <= buf.len);
        return buf[0 .. prefix_len + len];
    }
    return buf[0..0];
}

fn writeBytes(buf: []u8, bytes: []const u8) []const u8 {
    std.debug.assert(bytes.len <= buf.len);
    @memcpy(buf[0..bytes.len], bytes);
    return buf[0..bytes.len];
}

// ASCII control chords are legacy byte semantics; lock state has already been
// removed by Modifier.legacy and remains available only to extended protocols.
fn legacyControlByte(codepoint: u21) ?u8 {
    return switch (codepoint) {
        ' ' => 0,
        '@'...'_' => @intCast(codepoint - '@'),
        'a'...'z' => @intCast(codepoint - 'a' + 1),
        '?' => 0x7f,
        else => null,
    };
}

fn fixed3(buf: []u8, a: u8, b: u8, c: u8) []const u8 {
    std.debug.assert(buf.len >= 3);
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    return buf[0..3];
}

fn csi1ModifiedFinal(buf: []u8, final: u8, mod: Modifier) []const u8 {
    std.debug.assert(buf.len >= 6);
    buf[0] = '\x1b';
    buf[1] = '[';
    buf[2] = '1';
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = final;
    return buf[0..6];
}

fn csiTildePlain(buf: []u8, code: u8) []const u8 {
    std.debug.assert(buf.len >= 5);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = '~';
        return buf[0..5];
    }
    buf[2] = '0' + code;
    buf[3] = '~';
    return buf[0..4];
}

fn csiTildeModified(buf: []u8, code: u8, mod: Modifier) []const u8 {
    std.debug.assert(buf.len >= 7);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = ';';
        buf[5] = modifierParamDigit(mod);
        buf[6] = '~';
        return buf[0..7];
    }
    buf[2] = '0' + code;
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = '~';
    return buf[0..6];
}

fn modifierParamDigit(mod: Modifier) u8 {
    return '0' + @as(u8, @intCast(mod.legacy().protocolParameter()));
}

fn csiU(buf: []u8, code: u32, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}u", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ code, modifier }) catch "";
}

fn csiFinal(buf: []u8, final: u8, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{c}", .{final}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[1;{d}{c}", .{ modifier, final }) catch "";
}

fn csiTilde(buf: []u8, code: u32, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}~", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}~", .{ code, modifier }) catch "";
}

test "typed key identity separates old integer collisions" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};
    const unicode_soh = try InputKey.initUnicode(1);

    try std.testing.expectEqualStrings("\r", encodeKey(&buf, .{ .named = .enter }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[1u", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 8));
    try std.testing.expectError(error.InvalidUnicodeScalar, InputKey.initUnicode(0xD800));
}

test "named key classes retain exact legacy encodings" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};

    try std.testing.expectEqualStrings("\t", encodeKey(&buf, .{ .named = .tab }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[H", encodeKey(&buf, .{ .named = .home }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[3~", encodeKey(&buf, .{ .named = .delete }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOP", encodeKey(&buf, .{ .named = .f1 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[24~", encodeKey(&buf, .{ .named = .f12 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("+", encodeKey(&buf, .{ .named = .keypad_add }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings(
        "\x1bOk",
        encodeKey(&buf, .{ .named = .keypad_add }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        ",",
        encodeKey(&buf, .{ .named = .keypad_separator }, none, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1bOl",
        encodeKey(&buf, .{ .named = .keypad_separator }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "=",
        encodeKey(&buf, .{ .named = .keypad_equal }, none, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1bOX",
        encodeKey(&buf, .{ .named = .keypad_equal }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings("", encodeKey(&buf, .{ .named = .left_shift }, none, false, false, 0, 0, 0));
}

test "legacy keys preserve application modes modifiers and text boundaries" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};

    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&buf, .{ .named = .up }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOH", encodeKey(&buf, .{ .named = .home }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOF", encodeKey(&buf, .{ .named = .end }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOQ", encodeKey(&buf, .{ .named = .f2 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings(
        "\x1b\x03",
        encodeKey(&buf, try InputKey.initUnicode('c'), .{ .alt = true, .control = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\u{e9}",
        encodeKey(&buf, try InputKey.initUnicode('é'), .{ .alt = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\x1b[Z",
        encodeKey(&buf, .{ .named = .tab }, .{ .shift = true, .alt = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\x1b",
        encodeKey(&buf, .{ .named = .escape }, .{ .alt = true }, false, false, 0, 0, 0),
    );
}

test "every modifier combination has one Kitty parameter" {
    var buf: [max_encoded_len]u8 = undefined;
    const scalar = try InputKey.initUnicode('a');
    const cases = [_]struct { modifier: Modifier, expected: []const u8 }{
        .{ .modifier = .{}, .expected = "\x1b[97u" },
        .{ .modifier = .{ .shift = true }, .expected = "\x1b[97;2u" },
        .{ .modifier = .{ .alt = true }, .expected = "\x1b[97;3u" },
        .{ .modifier = .{ .shift = true, .alt = true }, .expected = "\x1b[97;4u" },
        .{ .modifier = .{ .control = true }, .expected = "\x1b[97;5u" },
        .{ .modifier = .{ .shift = true, .control = true }, .expected = "\x1b[97;6u" },
        .{ .modifier = .{ .alt = true, .control = true }, .expected = "\x1b[97;7u" },
        .{ .modifier = .{ .shift = true, .alt = true, .control = true }, .expected = "\x1b[97;8u" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(
            case.expected,
            encodeKey(&buf, scalar, case.modifier, false, false, 0, 0, 8),
        );
    }
}

test "legacy control encoding ignores num lock" {
    var buf: [max_encoded_len]u8 = undefined;
    const cases = [_]struct { key: u21, modifier: Modifier, expected: []const u8 }{
        .{ .key = 'b', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x02" },
        .{ .key = 'c', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x03" },
        .{ .key = 'r', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x12" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(
            case.expected,
            try encodeEvent(
                &buf,
                try InputKey.initUnicode(case.key),
                case.modifier,
                .press,
                if (case.modifier.shift) '?' else null,
                case.key,
                "",
                "",
                false,
                false,
                0,
                0,
                0,
            ),
        );
    }
}

test "legacy shift identity ignores num lock" {
    var buf: [max_encoded_len]u8 = undefined;
    try std.testing.expectEqualStrings(
        "?",
        try encodeEvent(
            &buf,
            try InputKey.initUnicode('/'),
            .{ .shift = true, .num_lock = true },
            .press,
            '?',
            '/',
            "",
            "",
            false,
            false,
            0,
            0,
            0,
        ),
    );
}

test "Kitty encoder honors its exact scratch bound" {
    var exact: [max_kitty_encoded_bytes]u8 = undefined;
    const direct = try encodeEvent(
        &exact,
        try InputKey.initUnicode('a'),
        .{},
        .press,
        null,
        null,
        "a",
        "a",
        false,
        false,
        0,
        0,
        31,
    );
    try std.testing.expect(direct.len <= exact.len);
    try std.testing.expectError(error.EncodingLimit, encodeEvent(
        exact[0 .. max_kitty_encoded_bytes - 1],
        try InputKey.initUnicode('a'),
        .{},
        .press,
        null,
        null,
        "a",
        "a",
        false,
        false,
        0,
        0,
        31,
    ));
}

/// Mouse button values.
pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Mouse event kinds.
pub const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

/// Caller mouse event payload.
pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    row: i32,
    col: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mod: Modifier,
    buttons_down: u8,
};

/// Selects which caller mouse events the terminal has requested.
pub const MouseTrackingMode = enum(u8) {
    off,
    x10,
    normal,
    button_event,
    any_event,
};

/// Selects the negotiated byte encoding for mouse reports.
pub const MouseProtocol = enum(u8) {
    none,
    utf8,
    sgr,
    sgr_pixel,
    urxvt,
};

fn wouldEncodeMouse(event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) bool {
    if (tracking == .off) return false;

    const emit = switch (event.kind) {
        .press, .wheel => true,
        .release => tracking != .x10 and event.button != .wheel_up and event.button != .wheel_down,
        .move => switch (tracking) {
            .button_event => event.buttons_down != 0,
            .any_event => true,
            else => false,
        },
    };
    if (!emit) return false;

    const row1 = mouseRow1(event.row);
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    if (protocol == .sgr_pixel) {
        const pixel_x = event.pixel_x orelse return false;
        const pixel_y = event.pixel_y orelse return false;
        return pixel_x < std.math.maxInt(u32) and pixel_y < std.math.maxInt(u32);
    }
    if (protocol == .sgr or protocol == .urxvt) return true;
    if (protocol == .utf8) {
        return validMouseCodepoint(cb + 32) and
            validMouseCodepoint(col1 + 32) and
            validMouseCodepoint(row1 + 32);
    }
    return cb <= 223 and col1 <= 223 and row1 <= 223;
}

// Caller rows are signed so callers can report positions above the visible grid.
// Normalizing in u32 preserves that policy and makes maxInt(i32) + 1 exact.
fn mouseRow1(row: i32) u32 {
    return if (row < 0) 1 else @as(u32, @intCast(row)) + 1;
}

fn validMouseCodepoint(value: u32) bool {
    return value <= 0x10FFFF and std.unicode.utf8ValidCodepoint(@intCast(value));
}

/// Encode one caller mouse event for the active terminal mouse protocol.
pub fn encodeMouse(buf: []u8, event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) []const u8 {
    if (!wouldEncodeMouse(event, tracking, protocol)) return buf[0..0];

    const row1 = mouseRow1(event.row);
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    return switch (protocol) {
        .sgr => encodeSgrMouse(buf, cb, col1, row1, event.kind == .release),
        .sgr_pixel => encodeSgrMouse(
            buf,
            cb,
            event.pixel_x.? + 1,
            event.pixel_y.? + 1,
            event.kind == .release,
        ),
        .urxvt => encodeUrxvtMouse(buf, cb, col1, row1),
        .utf8 => encodeCsiMMouse(buf, cb, col1, row1, true),
        .none => encodeCsiMMouse(buf, cb, col1, row1, false),
    };
}

fn mouseCode(event: MouseEvent, tracking: MouseTrackingMode) u16 {
    var code: u16 = switch (event.kind) {
        .press => pressButtonCode(event.button),
        .release => 3,
        .wheel => wheelButtonCode(event.button),
        .move => moveBaseCode(event),
    };
    if (tracking != .x10) {
        if (event.mod.shift) code += 4;
        if (event.mod.alt) code += 8;
        if (event.mod.control) code += 16;
    }
    if (event.kind == .move) code += 32;
    return code;
}

fn encodeSgrMouse(buf: []u8, cb: u16, col1: u32, row1: u32, release: bool) []const u8 {
    const final: u8 = if (release) 'm' else 'M';
    return std.fmt.bufPrint(buf, "\x1b[<{d};{d};{d}{c}", .{ cb, col1, row1, final }) catch buf[0..0];
}

fn encodeUrxvtMouse(buf: []u8, cb: u16, col1: u32, row1: u32) []const u8 {
    return std.fmt.bufPrint(buf, "\x1b[{d};{d};{d}M", .{ cb + 32, col1, row1 }) catch buf[0..0];
}

fn encodeCsiMMouse(buf: []u8, cb: u16, col1: u32, row1: u32, utf8: bool) []const u8 {
    if (!utf8 and (cb > 223 or col1 > 223 or row1 > 223)) return buf[0..0];
    var idx: u8 = 0;
    buf[idx] = '\x1b';
    idx += 1;
    buf[idx] = '[';
    idx += 1;
    buf[idx] = 'M';
    idx += 1;
    idx += encodeMouseNumber(buf[idx..], cb + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], col1 + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], row1 + 32, utf8);
    return buf[0..idx];
}

fn encodeMouseNumber(out: []u8, value: u32, utf8: bool) u8 {
    if (!utf8 or value < 128) {
        out[0] = @intCast(value);
        return 1;
    }
    return @intCast(std.unicode.utf8Encode(@intCast(value), out) catch 0);
}

fn pressButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .wheel_up => 64,
        .wheel_down => 65,
        .none => 3,
    };
}

fn wheelButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .wheel_up => 64,
        .wheel_down => 65,
        else => pressButtonCode(button),
    };
}

fn moveBaseCode(event: MouseEvent) u16 {
    if ((event.buttons_down & 0x01) != 0) return 0;
    if ((event.buttons_down & 0x02) != 0) return 1;
    if ((event.buttons_down & 0x04) != 0) return 2;
    return 3;
}

test "mouse protocols encode boundaries without partial sequences" {
    var buf: [max_encoded_len]u8 = undefined;
    const base: MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = 4,
        .col = 6,
        .mod = .{ .shift = true, .alt = true, .control = true },
        .buttons_down = 1,
    };

    try std.testing.expectEqualStrings("\x1b[<28;7;5M", encodeMouse(&buf, base, .normal, .sgr));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, base, .normal, .sgr_pixel));
    try std.testing.expectEqualStrings("\x1b[<28;320;240M", encodeMouse(
        &buf,
        .{
            .kind = .press,
            .button = .left,
            .row = 4,
            .col = 6,
            .pixel_x = 319,
            .pixel_y = 239,
            .mod = .{ .shift = true, .alt = true, .control = true },
            .buttons_down = 1,
        },
        .normal,
        .sgr_pixel,
    ));
    try std.testing.expectEqualStrings("\x1b[60;7;5M", encodeMouse(&buf, base, .normal, .urxvt));
    try std.testing.expectEqualStrings("\x1b[M#\"!", encodeMouse(
        &buf,
        .{ .kind = .release, .button = .left, .row = 0, .col = 1, .mod = .{}, .buttons_down = 0 },
        .normal,
        .none,
    ));
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{ .kind = .press, .button = .left, .row = 223, .col = 0, .mod = .{}, .buttons_down = 1 },
        .normal,
        .none,
    ));

    // A UTF-8 mouse field must be a Unicode scalar; rejecting the whole event
    // prevents an ESC [ M prefix from escaping without all three fields.
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{ .kind = .press, .button = .left, .row = 0xD800 - 33, .col = 0, .mod = .{}, .buttons_down = 1 },
        .normal,
        .utf8,
    ));

    const last_row: MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = std.math.maxInt(i32),
        .col = 0,
        .mod = .{},
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("\x1b[<0;1;2147483648M", encodeMouse(&buf, last_row, .normal, .sgr));
    try std.testing.expectEqualStrings("\x1b[32;1;2147483648M", encodeMouse(&buf, last_row, .normal, .urxvt));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, last_row, .normal, .utf8));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, last_row, .normal, .none));
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{
            .kind = .press,
            .button = .left,
            .row = 0,
            .col = 0,
            .pixel_x = std.math.maxInt(u32),
            .pixel_y = 0,
            .mod = .{},
            .buttons_down = 1,
        },
        .normal,
        .sgr_pixel,
    ));
    try std.testing.expectEqual(@as(u32, 1), mouseRow1(std.math.minInt(i32)));
}
