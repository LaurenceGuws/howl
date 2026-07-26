//! Small xkbcommon boundary. Wayland owns the keymap file descriptor and its
//! mapping; this module owns only the xkbcommon objects created from borrowed
//! keymap bytes and releases them in reverse order.

const c = @import("xkb_c");
const input = @import("input.zig");

/// Exact failures from context and keymap construction.
pub const Error = error{ ContextUnavailable, InvalidKeymap, StateUnavailable, KeyText, OutputTooSmall };
const ContextStorage = struct { ptr: *c.struct_xkb_context };
const KeymapStorage = struct { ptr: *c.struct_xkb_keymap };
const StateStorage = struct { ptr: *c.struct_xkb_state };
pub const Context = struct {
    /// Internal xkbcommon owner; callers use lifecycle methods only.
    storage: ContextStorage,

    /// Creates an xkb context. The returned context must be released with
    /// deinit and owns no Wayland descriptor or mapped keymap bytes.
    pub fn init() Error!Context {
        return .{ .storage = .{ .ptr = c.xkb_context_new(@as(c.enum_xkb_context_flags, 0)) orelse return error.ContextUnavailable } };
    }

    /// Releases the context after all keymaps and compose objects made from it.
    pub fn deinit(self: *Context) void {
        c.xkb_context_unref(self.storage.ptr);
        self.* = undefined;
    }
};

pub const Keymap = struct {
    /// Internal xkbcommon owner; mapped Wayland bytes are never retained.
    storage: KeymapStorage,

    /// Compiles UTF-8 keymap bytes borrowed for the duration of this call.
    /// The caller retains responsibility for the Wayland keymap FD, mapping,
    /// and unmapping; successful construction copies what xkbcommon needs.
    pub fn fromBuffer(context: *Context, bytes: []const u8) Error!Keymap {
        return .{ .storage = .{ .ptr = c.xkb_keymap_new_from_buffer(
            context.storage.ptr,
            bytes.ptr,
            bytes.len,
            @as(c.enum_xkb_keymap_format, 1),
            @as(c.enum_xkb_keymap_compile_flags, 0),
        ) orelse return error.InvalidKeymap } };
    }

    /// Releases the compiled keymap.
    pub fn deinit(self: *Keymap) void {
        c.xkb_keymap_unref(self.storage.ptr);
        self.* = undefined;
    }
};

pub const State = struct {
    /// Internal mutable xkbcommon state owner.
    storage: StateStorage,
    modifier_masks: ModifierMasks,
    effective_modifiers: u32 = 0,

    /// Creates mutable keyboard state for a compiled keymap.
    pub fn init(keymap: *Keymap) Error!State {
        return .{
            .storage = .{ .ptr = c.xkb_state_new(keymap.storage.ptr) orelse return error.StateUnavailable },
            .modifier_masks = ModifierMasks.init(keymap.storage.ptr),
        };
    }

    /// Releases keyboard state before its keymap.
    pub fn deinit(self: *State) void {
        c.xkb_state_unref(self.storage.ptr);
        self.* = undefined;
    }

    /// Returns the UTF-8 text for one key into caller storage.
    pub fn keyUtf8(self: *State, keycode: u32, output: []u8) Error!usize {
        if (output.len == 0) return error.OutputTooSmall;
        const required_raw = c.xkb_state_key_get_utf8(self.storage.ptr, @intCast(keycode), null, 0);
        if (required_raw < 0) return error.KeyText;
        const required: usize = @intCast(required_raw);
        if (required >= output.len) return error.OutputTooSmall;
        const result = c.xkb_state_key_get_utf8(self.storage.ptr, @intCast(keycode), output.ptr, output.len);
        if (result < 0) return error.KeyText;
        if (@as(usize, @intCast(result)) != required) return error.KeyText;
        return required;
    }

    /// Returns the mode-resolved keysym for one keycode.
    pub fn keySym(self: *State, keycode: u32) u32 {
        return c.xkb_state_key_get_one_sym(self.storage.ptr, @intCast(keycode));
    }

    /// Resolves semantic facts through the current keymap's real modifier
    /// encodings. Virtual aliases contribute only genuinely distinct bits.
    pub fn semanticModifiers(self: *State) input.SemanticModifiers {
        return self.modifier_masks.semantic(self.effective_modifiers);
    }

    /// Applies the exact depressed, latched, and locked modifier masks.
    pub fn updateModifiers(self: *State, modifiers: struct { depressed: u32, latched: u32, locked: u32, group: u32 }) bool {
        self.effective_modifiers = modifiers.depressed | modifiers.latched | modifiers.locked;
        return c.xkb_state_update_mask(self.storage.ptr, modifiers.depressed, modifiers.latched, modifiers.locked, 0, 0, modifiers.group) != 0;
    }
};

const ModifierMasks = struct {
    shift: u32,
    control: u32,
    alt: u32,
    super: u32,
    hyper: u32,
    meta: u32,
    caps_lock: u32,
    num_lock: u32,

    fn init(keymap: *c.xkb_keymap) ModifierMasks {
        return fromMappings(
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_SHIFT),
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_CTRL),
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_ALT),
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_LOGO),
            c.xkb_keymap_mod_get_mask(keymap, "Hyper"),
            c.xkb_keymap_mod_get_mask(keymap, "Meta"),
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_CAPS),
            c.xkb_keymap_mod_get_mask(keymap, c.XKB_MOD_NAME_NUM),
        );
    }

    fn fromMappings(shift: u32, control: u32, alt: u32, super: u32, hyper: u32, meta: u32, caps_lock: u32, num_lock: u32) ModifierMasks {
        const canonical = shift | control | alt | super | caps_lock | num_lock;
        return .{
            .shift = shift,
            .control = control,
            .alt = alt,
            .super = super,
            .hyper = hyper & ~canonical,
            .meta = meta & ~canonical,
            .caps_lock = caps_lock,
            .num_lock = num_lock,
        };
    }

    fn semantic(self: ModifierMasks, effective: u32) input.SemanticModifiers {
        return .{
            .shift = effective & self.shift != 0,
            .control = effective & self.control != 0,
            .alt = effective & self.alt != 0,
            .super = effective & self.super != 0,
            .hyper = effective & self.hyper != 0,
            .meta = effective & self.meta != 0,
            .caps_lock = effective & self.caps_lock != 0,
            .num_lock = effective & self.num_lock != 0,
        };
    }
};

test "xkb context rejects malformed borrowed keymap bytes without ownership transfer" {
    var context = try Context.init();
    defer context.deinit();
    try std.testing.expectError(error.InvalidKeymap, Keymap.fromBuffer(&context, "not a keymap"));
}

test "semantic modifier aliases do not reject canonical Alt or Super" {
    const aliased = ModifierMasks.fromMappings(1, 2, 4, 8, 4, 8, 64, 128);
    const alt = aliased.semantic(4);
    try std.testing.expect(alt.alt and !alt.hyper and !alt.meta);
    const super = aliased.semantic(8);
    try std.testing.expect(super.super and !super.hyper and !super.meta);
    const distinct_masks = ModifierMasks.fromMappings(1, 2, 4, 8, 16, 32, 64, 128);
    const distinct = distinct_masks.semantic(16 | 32);
    try std.testing.expect(distinct.hyper and distinct.meta);
}

const std = @import("std");
