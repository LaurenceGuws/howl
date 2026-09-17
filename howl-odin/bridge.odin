package main

import "core:c"

foreign import howl_bridge "bridge:libhowl_odin_bridge.so"

@(default_calling_convention="c", link_prefix="howl_odin_bridge_")
foreign howl_bridge {
    version            :: proc() -> u32 ---
    owned_session_create :: proc(runtime_dir: [^]u8, runtime_dir_len: c.size_t, shell: [^]u8, shell_len: c.size_t, command: [^]u8, command_len: c.size_t, cwd: [^]u8, cwd_len: c.size_t, env: [^]Profile_Env_Info, env_count: c.size_t, rows, columns: u16, identity: u32, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    owned_session_destroy :: proc(handle: rawptr) ---
    owned_session_copy_endpoint :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    create             :: proc(endpoint: [^]u8, endpoint_len: c.size_t, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    destroy            :: proc(handle: rawptr) ---
    cancellation_create  :: proc(handle: rawptr) -> rawptr ---
    cancellation_cancel  :: proc(handle: rawptr) -> i32 ---
    cancellation_destroy :: proc(handle: rawptr) ---
    consequence_create :: proc(endpoint: [^]u8, endpoint_len: c.size_t, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    consequence_destroy :: proc(handle: rawptr) ---
    consequence_client_id :: proc(handle: rawptr) -> u64 ---
    consequence_acquire :: proc(handle: rawptr) -> i32 ---
    consequence_info_size :: proc() -> u32 ---
    consequence_observe :: proc(handle: rawptr, info: ^Consequence_Info, payload: [^]u8, payload_capacity: c.size_t, copied_len: ^c.size_t) -> i32 ---
    consequence_consume :: proc(handle: rawptr, generation: u64) -> i32 ---
    consequence_reply :: proc(handle: rawptr, generation: u64, kind: u8, body: [^]u8, body_len: c.size_t) -> i32 ---
    consequence_copy_error :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    snapshot           :: proc(handle: rawptr, after_revision: u64, history_offset: u32, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    snapshot_title     :: proc(handle: rawptr, output: [^]u8, capacity: c.size_t) -> c.size_t ---
    snapshot_progress  :: proc(handle: rawptr) -> u16 ---
    search_find        :: proc(handle: rawptr, query: [^]u8, query_len: c.size_t, reverse, origin_present: u8, origin_row: i32, origin_column: u16, output: ^Search_Match_Info) -> i32 ---
    search_match_info_size :: proc() -> u32 ---
    selection_expand   :: proc(handle: rawptr, kind: u8, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: ^Selection_Range_Info) -> i32 ---
    hyperlink_copy     :: proc(handle: rawptr, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    selection_range_info_size :: proc() -> u32 ---
    interaction_state :: proc(handle: rawptr, output: ^Interaction_State_Info) -> i32 ---
    interaction_state_info_size :: proc() -> u32 ---
    profile_env_info_size :: proc() -> u32 ---
    send_text          :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    send_paste         :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    selection_extract  :: proc(handle: rawptr, start_row: i32, start_column: u16, end_row: i32, end_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    send_named_key     :: proc(handle: rawptr, key, action, modifiers: u8) -> i32 ---
    send_unicode_key   :: proc(handle: rawptr, scalar: u32, action, modifiers: u8) -> i32 ---
    send_mouse         :: proc(handle: rawptr, kind, button, modifiers, buttons_down: u8, row: i32, column: u16, pixels_present: u8, pixel_x, pixel_y: u32) -> i32 ---
    send_focus         :: proc(handle: rawptr, focus: u8) -> i32 ---
    send_resize        :: proc(handle: rawptr, rows, columns, cell_width, cell_height: u16) -> i32 ---
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
    stream_closed      :: proc(handle: rawptr) -> u8 ---
    child_exited       :: proc(handle: rawptr) -> u8 ---
    history_offset     :: proc(handle: rawptr) -> u32 ---
    history_count      :: proc(handle: rawptr) -> u32 ---
    history_row_base   :: proc(handle: rawptr) -> u32 ---
    text_truncated     :: proc(handle: rawptr) -> u8 ---
    render_create      :: proc(endpoint: [^]u8, endpoint_len: c.size_t, font: [^]u8, font_len: c.size_t, fallback: [^]u8, fallback_len: c.size_t, secondary_fallback: [^]u8, secondary_fallback_len: c.size_t, font_pixels: u16, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    render_destroy     :: proc(handle: rawptr) ---
    render_observe     :: proc(handle: rawptr, history_offset: u32) -> i32 ---
    render_background_rgba :: proc(handle: rawptr) -> u32 ---
    render_surface_width  :: proc(handle: rawptr) -> u16 ---
    render_surface_height :: proc(handle: rawptr) -> u16 ---
    render_cell_width     :: proc(handle: rawptr) -> u16 ---
    render_cell_height    :: proc(handle: rawptr) -> u16 ---
    render_maximum_rows   :: proc() -> u16 ---
    render_maximum_columns :: proc() -> u16 ---
    render_frame_revision :: proc(handle: rawptr) -> u64 ---
    render_session_revision :: proc(handle: rawptr) -> u64 ---
    render_history_offset :: proc(handle: rawptr) -> u32 ---
    render_history_count :: proc(handle: rawptr) -> u32 ---
    render_history_row_base :: proc(handle: rawptr) -> u32 ---
    render_alternate_screen :: proc(handle: rawptr) -> u8 ---
    render_selection_span :: proc(handle: rawptr, anchor_row: i32, anchor_column: u16, focus_row: i32, focus_column: u16, columns: u16, alternate_screen: u8, viewport_row: u16, first, last: ^u16) -> u8 ---
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

Consequence_Info :: struct {
    terminal_revision: u64,
    authority_client_id: u64,
    generation: u64,
    payload_len: u32,
    kind: u8,
    reply_required: u8,
    _reserved: [2]u8,
    metadata: [32]u8,
}

Bridge_Consequence_Kind :: enum u8 {
    None = 0,
    Clipboard = 1,
    Notification = 2,
    Pointer_Shape = 3,
    File_Transfer = 4,
    Drag_Drop = 5,
    Container = 6,
    Color_Preference = 7,
    Media_Copy = 8,
    Bell = 9,
    Legacy_Control = 10,
    Dcs = 11,
    String_Control = 12,
}

Bridge_Consequence_Reply :: enum u8 {
    Clipboard = 1,
    Pointer_Shape = 2,
    Color_Preference = 3,
    Container_State = 4,
    Container_Position = 5,
    Container_Screen_Cells = 6,
    Container_Icon_Title = 7,
    Container_Decline = 8,
}

Profile_Env_Info :: struct {
    name: [^]u8,
    name_len: c.size_t,
    value: [^]u8,
    value_len: c.size_t,
}

Search_Match_Info :: struct {
    cut_revision: u64,
    row: i32,
    start_column: u16,
    end_column: u16,
    columns: u16,
    found: u8,
    complete: u8,
    alternate_screen: u8,
    _reserved: u8,
    scanned_snapshots: u32,
}

Selection_Range_Info :: struct {
    start_row: i32,
    end_row: i32,
    start_column: u16,
    end_column: u16,
    columns: u16,
    found: u8,
    alternate_screen: u8,
    _reserved: [2]u8,
}

Interaction_State_Info :: struct {
    terminal_revision: u64,
    flags: u32,
    mouse_tracking: u8,
    mouse_protocol: u8,
    pointer_mode: u8,
    _reserved: u8,
}

INTERACTION_ALT_SCROLL :: u32(1 << 0)
INTERACTION_FOCUS_REPORTING :: u32(1 << 1)

Bridge_Mouse_Kind :: enum u8 {
    Press = 1,
    Release = 2,
    Move = 3,
    Wheel = 4,
}

Bridge_Mouse_Button :: enum u8 {
    None = 0,
    Left = 1,
    Middle = 2,
    Right = 3,
    Wheel_Up = 4,
    Wheel_Down = 5,
}

Bridge_Focus :: enum u8 {
    In = 1,
    Out = 2,
}

Bridge_Key :: enum u8 {
    Enter             = 1,
    Tab               = 2,
    Backspace         = 3,
    Escape            = 4,
    Up                = 5,
    Down              = 6,
    Left              = 7,
    Right             = 8,
    Insert            = 9,
    Delete            = 10,
    Home              = 11,
    End               = 12,
    Page_Up           = 13,
    Page_Down         = 14,
    Left_Shift        = 15,
    Right_Shift       = 16,
    Left_Control      = 17,
    Right_Control     = 18,
    Left_Alt          = 19,
    Right_Alt         = 20,
    Left_Super        = 21,
    Right_Super       = 22,
    Left_Hyper        = 23,
    Right_Hyper       = 24,
    Left_Meta         = 25,
    Right_Meta        = 26,
    Caps_Lock         = 27,
    Num_Lock          = 28,
    F1                = 29,
    F2                = 30,
    F3                = 31,
    F4                = 32,
    F5                = 33,
    F6                = 34,
    F7                = 35,
    F8                = 36,
    F9                = 37,
    F10               = 38,
    F11               = 39,
    F12               = 40,
    Keypad_0          = 41,
    Keypad_1          = 42,
    Keypad_2          = 43,
    Keypad_3          = 44,
    Keypad_4          = 45,
    Keypad_5          = 46,
    Keypad_6          = 47,
    Keypad_7          = 48,
    Keypad_8          = 49,
    Keypad_9          = 50,
    Keypad_Decimal    = 51,
    Keypad_Add        = 52,
    Keypad_Subtract   = 53,
    Keypad_Multiply   = 54,
    Keypad_Divide     = 55,
    Keypad_Separator  = 56,
    Keypad_Equal      = 57,
    Keypad_Enter      = 58,
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
