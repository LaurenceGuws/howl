package main

import "core:c"

foreign import howl_bridge "bridge:libhowl_odin_bridge.so"

@(default_calling_convention="c", link_prefix="howl_odin_bridge_")
foreign howl_bridge {
    version            :: proc() -> u32 ---
    create             :: proc(endpoint: [^]u8, endpoint_len: c.size_t, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    destroy            :: proc(handle: rawptr) ---
    cancellation_create  :: proc(handle: rawptr) -> rawptr ---
    cancellation_cancel  :: proc(handle: rawptr) -> i32 ---
    cancellation_destroy :: proc(handle: rawptr) ---
    snapshot           :: proc(handle: rawptr, after_revision: u64, history_offset: u32, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    send_text          :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    send_named_key     :: proc(handle: rawptr, key, action, modifiers: u8) -> i32 ---
    send_unicode_key   :: proc(handle: rawptr, scalar: u32, action, modifiers: u8) -> i32 ---
    copy_error         :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    revision           :: proc(handle: rawptr) -> u64 ---
    terminal_revision  :: proc(handle: rawptr) -> u64 ---
    rows               :: proc(handle: rawptr) -> u16 ---
    columns            :: proc(handle: rawptr) -> u16 ---
    cursor_row         :: proc(handle: rawptr) -> u16 ---
    cursor_column      :: proc(handle: rawptr) -> u16 ---
    cursor_visible     :: proc(handle: rawptr) -> u8 ---
    cursor_shape       :: proc(handle: rawptr) -> u8 ---
    alternate_screen   :: proc(handle: rawptr) -> u8 ---
    history_count      :: proc(handle: rawptr) -> u32 ---
    text_truncated     :: proc(handle: rawptr) -> u8 ---
}

Bridge_Key :: enum u8 {
    Enter     = 1,
    Tab       = 2,
    Backspace = 3,
    Escape    = 4,
    Up        = 5,
    Down      = 6,
    Left      = 7,
    Right     = 8,
    Insert    = 9,
    Delete    = 10,
    Home      = 11,
    End       = 12,
    Page_Up   = 13,
    Page_Down = 14,
}

Bridge_Key_Action :: enum u8 {
    Press   = 1,
    Repeat  = 2,
    Release = 3,
}

BRIDGE_MOD_SHIFT :: u8(1 << 0)
BRIDGE_MOD_ALT   :: u8(1 << 1)
BRIDGE_MOD_CTRL  :: u8(1 << 2)
BRIDGE_MOD_SUPER :: u8(1 << 3)
BRIDGE_MOD_CAPS  :: u8(1 << 6)
BRIDGE_MOD_NUM   :: u8(1 << 7)
