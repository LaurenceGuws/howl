package main

import "core:c"

foreign import howl_bridge "bridge:libhowl_odin_bridge.so"

@(default_calling_convention="c", link_prefix="howl_odin_bridge_")
foreign howl_bridge {
    version            :: proc() -> u32 ---
    owned_session_create :: proc(runtime_dir: [^]u8, runtime_dir_len: c.size_t, shell: [^]u8, shell_len: c.size_t, rows, columns: u16, identity: u32, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    owned_session_destroy :: proc(handle: rawptr) ---
    owned_session_copy_endpoint :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
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
    render_create      :: proc(endpoint: [^]u8, endpoint_len: c.size_t, font: [^]u8, font_len: c.size_t, font_pixels: u16, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    render_destroy     :: proc(handle: rawptr) ---
    render_observe     :: proc(handle: rawptr) -> i32 ---
    render_surface_width  :: proc(handle: rawptr) -> u16 ---
    render_surface_height :: proc(handle: rawptr) -> u16 ---
    render_frame_revision :: proc(handle: rawptr) -> u64 ---
    render_session_revision :: proc(handle: rawptr) -> u64 ---
    render_upload_count  :: proc(handle: rawptr) -> u32 ---
    render_removal_count :: proc(handle: rawptr) -> u32 ---
    render_command_count :: proc(handle: rawptr) -> u32 ---
    render_upload_info    :: proc(handle: rawptr, index: u32, output: ^Canvas_Resource_Info) -> i32 ---
    render_upload_copy    :: proc(handle: rawptr, index: u32, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    render_removal_info   :: proc(handle: rawptr, index: u32, output: ^Canvas_Removal_Info) -> i32 ---
    render_command_info   :: proc(handle: rawptr, index: u32, output: ^Canvas_Command_Info) -> i32 ---
    render_copy_error     :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    render_resource_info_size :: proc() -> u32 ---
    render_removal_info_size  :: proc() -> u32 ---
    render_command_info_size  :: proc() -> u32 ---
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

Canvas_Resource_Info :: struct {
    source: u64,
    resource: u64,
    generation: u64,
    pixel_count: u64,
    stride: u64,
    width: u16,
    height: u16,
    format: u8,
    _reserved: [7]u8,
}

Canvas_Removal_Info :: struct {
    source: u64,
    resource: u64,
    generation: u64,
}

Canvas_Command_Info :: struct {
    resource_source: u64,
    resource: u64,
    generation: u64,
    color_rgba: u32,
    destination_x: i32,
    destination_y: i32,
    clip_x: i32,
    clip_y: i32,
    destination_width: u16,
    destination_height: u16,
    clip_width: u16,
    clip_height: u16,
    source_x: u16,
    source_y: u16,
    source_width: u16,
    source_height: u16,
    resource_width: u16,
    resource_height: u16,
    tag: u8,
    format: u8,
    cursor_component: u8,
    _reserved: u8,
}
