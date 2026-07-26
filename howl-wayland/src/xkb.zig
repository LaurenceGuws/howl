//! Small xkbcommon boundary. Wayland owns the keymap file descriptor and its
//! mapping; this module owns only the xkbcommon objects created from borrowed
//! keymap bytes and releases them in reverse order.

const c = @import("xkb_c");

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

    /// Creates mutable keyboard state for a compiled keymap.
    pub fn init(keymap: *Keymap) Error!State {
        return .{ .storage = .{ .ptr = c.xkb_state_new(keymap.storage.ptr) orelse return error.StateUnavailable } };
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

    /// Applies the exact depressed, latched, and locked modifier masks.
    pub fn updateModifiers(self: *State, modifiers: struct { depressed: u32, latched: u32, locked: u32, group: u32 }) bool {
        return c.xkb_state_update_mask(self.storage.ptr, modifiers.depressed, modifiers.latched, modifiers.locked, 0, 0, modifiers.group) != 0;
    }
};

test "xkb context rejects malformed borrowed keymap bytes without ownership transfer" {
    var context = try Context.init();
    defer context.deinit();
    try std.testing.expectError(error.InvalidKeymap, Keymap.fromBuffer(&context, "not a keymap"));
}

const std = @import("std");
