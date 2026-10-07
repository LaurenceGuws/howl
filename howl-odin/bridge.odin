package main

import "core:c"

when ODIN_OS == .Windows {
    foreign import howl_bridge "bridge:howl_odin_bridge.lib"
} else {
    foreign import howl_bridge "bridge:libhowl_odin_bridge.so"
}

@(default_calling_convention="c", link_prefix="howl_odin_bridge_")
foreign howl_bridge {
    version            :: proc() -> u32 ---
    runtime_create :: proc() -> rawptr ---
    runtime_destroy :: proc(runtime: rawptr) ---
    native_local_instance_create :: proc(
        runtime: rawptr,
        shell: [^]u8, shell_len: c.size_t,
        command: [^]u8, command_len: c.size_t,
        cwd: [^]u8, cwd_len: c.size_t,
        rows, columns, history_rows: u16,
        font: [^]u8, font_len: c.size_t,
        italic: [^]u8, italic_len: c.size_t,
        bold: [^]u8, bold_len: c.size_t,
        bold_italic: [^]u8, bold_italic_len: c.size_t,
        fallback: [^]u8, fallback_len: c.size_t,
        secondary_fallback: [^]u8, secondary_fallback_len: c.size_t,
        font_pixels: u16,
        diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t,
    ) -> u64 ---
    native_local_instance_destroy :: proc(runtime: rawptr, instance_id: u64) -> i32 ---
    native_terminal_claim :: proc(runtime: rawptr, instance_id: u64, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    native_terminal_release :: proc(handle: rawptr) ---
    native_terminal_service :: proc(handle: rawptr, timestamp_ns: u64) -> i32 ---
    native_terminal_wait :: proc(handle: rawptr, timeout_ms: i32) -> i32 ---
    native_terminal_wake :: proc(handle: rawptr) ---
    native_terminal_send_text :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    native_terminal_send_paste :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    native_terminal_send_named_key :: proc(handle: rawptr, key, action, modifiers: u8) -> i32 ---
    native_terminal_send_unicode_key :: proc(handle: rawptr, scalar: u32, action, modifiers: u8) -> i32 ---
    native_terminal_send_mouse :: proc(handle: rawptr, kind, button, modifiers, buttons_down: u8, row: i32, column: u16, pixels_present: u8, pixel_x, pixel_y: u32) -> i32 ---
    native_terminal_send_focus :: proc(handle: rawptr, focus: u8) -> i32 ---
    native_terminal_send_resize :: proc(handle: rawptr, rows, columns, cell_width, cell_height: u16, claim: u8) -> i32 ---
    native_terminal_selection_expand :: proc(handle: rawptr, kind: u8, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: ^Selection_Range_Info) -> i32 ---
    native_terminal_selection_extract :: proc(handle: rawptr, start_row: i32, start_column: u16, end_row: i32, end_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    native_terminal_hyperlink_copy :: proc(handle: rawptr, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    native_terminal_search_find :: proc(handle: rawptr, query: [^]u8, query_len: c.size_t, reverse, origin_present: u8, origin_row: i32, origin_column: u16, output: ^Search_Match_Info) -> i32 ---
    native_terminal_consequence_observe :: proc(handle: rawptr, info: ^Consequence_Info, payload: [^]u8, payload_capacity: c.size_t, copied_len: ^c.size_t) -> i32 ---
    native_terminal_consequence_consume :: proc(handle: rawptr, generation: u64) -> i32 ---
    native_terminal_consequence_reply :: proc(handle: rawptr, generation: u64, kind: u8, body: [^]u8, body_len: c.size_t) -> i32 ---
    native_terminal_copy_error :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    native_terminal_render_exchange :: proc(handle: rawptr) -> rawptr ---
    native_terminal_publish_history :: proc(handle: rawptr, history_offset: u32) -> i32 ---
    native_terminal_reconfigure_presentation :: proc(
        handle: rawptr,
        font: [^]u8, font_len: c.size_t,
        italic: [^]u8, italic_len: c.size_t,
        bold: [^]u8, bold_len: c.size_t,
        bold_italic: [^]u8, bold_italic_len: c.size_t,
        fallback: [^]u8, fallback_len: c.size_t,
        secondary_fallback: [^]u8, secondary_fallback_len: c.size_t,
        font_pixels: u16,
    ) -> i32 ---
    native_canvas_create :: proc(exchange: rawptr) -> rawptr ---
    native_canvas_destroy :: proc(handle: rawptr) ---
    native_canvas_prepare :: proc(handle: rawptr) -> i32 ---
    native_canvas_accept :: proc(handle: rawptr) -> i32 ---
    native_canvas_discard :: proc(handle: rawptr) -> i32 ---
    native_canvas_presentation_generation :: proc(handle: rawptr) -> u64 ---
    native_canvas_background_rgba :: proc(handle: rawptr) -> u32 ---
    native_canvas_surface_width :: proc(handle: rawptr) -> u16 ---
    native_canvas_surface_height :: proc(handle: rawptr) -> u16 ---
    native_canvas_cell_width :: proc(handle: rawptr) -> u16 ---
    native_canvas_cell_height :: proc(handle: rawptr) -> u16 ---
    native_canvas_frame_revision :: proc(handle: rawptr) -> u64 ---
    native_canvas_terminal_revision :: proc(handle: rawptr) -> u64 ---
    native_canvas_history_offset :: proc(handle: rawptr) -> u32 ---
    native_canvas_history_count :: proc(handle: rawptr) -> u32 ---
    native_canvas_history_row_base :: proc(handle: rawptr) -> u32 ---
    native_canvas_alternate_screen :: proc(handle: rawptr) -> u8 ---
    native_canvas_upload_count :: proc(handle: rawptr) -> u32 ---
    native_canvas_removal_count :: proc(handle: rawptr) -> u32 ---
    native_canvas_command_count :: proc(handle: rawptr) -> u32 ---
    native_canvas_upload_info :: proc(handle: rawptr, index: u32, output: ^Canvas_Resource_Info) -> i32 ---
    native_canvas_upload_copy :: proc(handle: rawptr, index: u32, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    native_canvas_removal_info :: proc(handle: rawptr, index: u32, output: ^Canvas_Removal_Info) -> i32 ---
    native_canvas_command_info :: proc(handle: rawptr, index: u32, output: ^Canvas_Command_Info) -> i32 ---
    native_canvas_copy_error :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    native_terminal_info_size :: proc() -> u32 ---
    native_terminal_snapshot :: proc(
        handle: rawptr,
        history_offset: u32,
        info: ^Native_Terminal_Info,
        text: [^]u8, text_capacity: c.size_t, text_len: ^c.size_t,
        title: [^]u8, title_capacity: c.size_t, title_len: ^c.size_t,
        row_shapes: [^]Native_Row_Shape, row_shape_capacity: c.size_t, row_shape_count: ^c.size_t,
    ) -> i32 ---
    interrupt_create :: proc() -> rawptr ---
    interrupt_cancel :: proc(token: rawptr) -> i32 ---
    interrupt_destroy :: proc(token: rawptr) ---
    create             :: proc(runtime, interrupt: rawptr, route_kind: u8, endpoint: [^]u8, endpoint_len: c.size_t, server_id, session_id, instance_id: u64, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    destroy            :: proc(handle: rawptr) ---
    consequence_create :: proc(runtime, interrupt: rawptr, route_kind: u8, endpoint: [^]u8, endpoint_len: c.size_t, server_id, session_id, instance_id: u64, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    consequence_destroy :: proc(handle: rawptr) ---
    consequence_client_id :: proc(handle: rawptr) -> u64 ---
    consequence_acquire :: proc(handle: rawptr) -> i32 ---
    consequence_info_size :: proc() -> u32 ---
    consequence_kind_signature :: proc() -> u64 ---
    consequence_reply_signature :: proc() -> u64 ---
    consequence_observe :: proc(handle: rawptr, info: ^Consequence_Info, payload: [^]u8, payload_capacity: c.size_t, copied_len: ^c.size_t) -> i32 ---
    consequence_consume :: proc(handle: rawptr, generation: u64) -> i32 ---
    consequence_reply :: proc(handle: rawptr, generation: u64, kind: u8, body: [^]u8, body_len: c.size_t) -> i32 ---
    consequence_copy_error :: proc(handle: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) ---
    snapshot           :: proc(handle: rawptr, after_revision: u64, history_offset: u32, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    snapshot_take_rich_loan :: proc(handle: rawptr) -> rawptr ---
    snapshot_release_rich_loan :: proc(handle: rawptr) ---
    snapshot_take_view :: proc(handle: rawptr) -> rawptr ---
    view_destroy       :: proc(view: rawptr) ---
    snapshot_title     :: proc(handle: rawptr, output: [^]u8, capacity: c.size_t) -> c.size_t ---
    snapshot_progress  :: proc(handle: rawptr) -> u16 ---
    search_find        :: proc(handle: rawptr, query: [^]u8, query_len: c.size_t, reverse, origin_present: u8, origin_row: i32, origin_column: u16, output: ^Search_Match_Info) -> i32 ---
    search_match_info_size :: proc() -> u32 ---
    selection_expand   :: proc(handle: rawptr, kind: u8, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: ^Selection_Range_Info) -> i32 ---
    hyperlink_copy     :: proc(handle: rawptr, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    selection_range_info_size :: proc() -> u32 ---
    interaction_state :: proc(handle: rawptr, output: ^Interaction_State_Info) -> i32 ---
    interaction_state_info_size :: proc() -> u32 ---
    send_text          :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    send_paste         :: proc(handle: rawptr, bytes: [^]u8, bytes_len: c.size_t) -> i32 ---
    selection_extract  :: proc(handle: rawptr, start_row: i32, start_column: u16, end_row: i32, end_column: u16, expected_columns: u16, expected_alternate_screen: u8, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t) -> i32 ---
    send_named_key     :: proc(handle: rawptr, key, action, modifiers: u8) -> i32 ---
    send_unicode_key   :: proc(handle: rawptr, scalar: u32, action, modifiers: u8) -> i32 ---
    send_mouse         :: proc(handle: rawptr, kind, button, modifiers, buttons_down: u8, row: i32, column: u16, pixels_present: u8, pixel_x, pixel_y: u32) -> i32 ---
    send_focus         :: proc(handle: rawptr, focus: u8) -> i32 ---
    send_resize        :: proc(handle: rawptr, rows, columns, cell_width, cell_height: u16, claim: u8) -> i32 ---
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
    render_create      :: proc(runtime, interrupt: rawptr, route_kind: u8, endpoint: [^]u8, endpoint_len: c.size_t, server_id, session_id, instance_id: u64, font: [^]u8, font_len: c.size_t, italic: [^]u8, italic_len: c.size_t, bold: [^]u8, bold_len: c.size_t, bold_italic: [^]u8, bold_italic_len: c.size_t, fallback: [^]u8, fallback_len: c.size_t, secondary_fallback: [^]u8, secondary_fallback_len: c.size_t, font_pixels: u16, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> rawptr ---
    render_destroy     :: proc(handle: rawptr) ---
    render_observe     :: proc(handle: rawptr, history_offset: u32) -> i32 ---
    render_prepare :: proc(handle: rawptr, history_offset: u32) -> i32 ---
    render_prepare_view :: proc(handle, snapshot: rawptr) -> i32 ---
    render_prepare_rich_loan :: proc(handle, loan: rawptr) -> i32 ---
    render_accept :: proc(handle: rawptr) ---
    render_discard :: proc(handle: rawptr) ---
    render_background_rgba :: proc(handle: rawptr) -> u32 ---
    render_surface_width  :: proc(handle: rawptr) -> u16 ---
    render_surface_height :: proc(handle: rawptr) -> u16 ---
    render_cell_width     :: proc(handle: rawptr) -> u16 ---
    render_cell_height    :: proc(handle: rawptr) -> u16 ---
    render_maximum_rows   :: proc() -> u16 ---
    render_maximum_columns :: proc() -> u16 ---
    render_frame_revision :: proc(handle: rawptr) -> u64 ---
    render_instance_revision :: proc(handle: rawptr) -> u64 ---
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
    server_tree       :: proc(endpoint: [^]u8, endpoint_len: c.size_t, interrupt: rawptr, output: [^]u8, output_capacity: c.size_t, output_len: ^c.size_t, diagnostic: [^]u8, diagnostic_capacity: c.size_t, diagnostic_len: ^c.size_t) -> i32 ---
}

Native_Terminal_Info :: struct {
    revision: u64,
    terminal_revision: u64,
    history_count: u32,
    history_row_base: u32,
    interaction_flags: u32,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    task_progress: u16,
    cursor_shape: u8,
    cursor_visible: u8,
    alternate_screen: u8,
    stream_closed: u8,
    child_exited: u8,
    text_truncated: u8,
    mouse_tracking: u8,
    mouse_protocol: u8,
    pointer_mode: u8,
    _reserved: [3]u8,
}

Native_Row_Shape :: struct {
    content_end_exclusive: u16,
    wrapped: u8,
    _reserved: u8,
}

Bridge_Route_Kind :: enum u8 {
    Direct = 0,
    Server = 1,
    Local = 2,
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

bridge_consequence_signature :: proc(values: []u8) -> u64 {
    assert(len(values) <= 14)
    result := u64(len(values)) << 56
    for value, index in values {
        assert(value <= 0x0f)
        result |= u64(value) << u64(index * 4)
    }
    return result
}

bridge_consequence_kind_signature :: proc() -> u64 {
    values := [13]u8{
        u8(Bridge_Consequence_Kind.None),
        u8(Bridge_Consequence_Kind.Clipboard),
        u8(Bridge_Consequence_Kind.Notification),
        u8(Bridge_Consequence_Kind.Pointer_Shape),
        u8(Bridge_Consequence_Kind.File_Transfer),
        u8(Bridge_Consequence_Kind.Drag_Drop),
        u8(Bridge_Consequence_Kind.Container),
        u8(Bridge_Consequence_Kind.Color_Preference),
        u8(Bridge_Consequence_Kind.Media_Copy),
        u8(Bridge_Consequence_Kind.Bell),
        u8(Bridge_Consequence_Kind.Legacy_Control),
        u8(Bridge_Consequence_Kind.Dcs),
        u8(Bridge_Consequence_Kind.String_Control),
    }
    return bridge_consequence_signature(values[:])
}

bridge_consequence_reply_signature :: proc() -> u64 {
    values := [8]u8{
        u8(Bridge_Consequence_Reply.Clipboard),
        u8(Bridge_Consequence_Reply.Pointer_Shape),
        u8(Bridge_Consequence_Reply.Color_Preference),
        u8(Bridge_Consequence_Reply.Container_State),
        u8(Bridge_Consequence_Reply.Container_Position),
        u8(Bridge_Consequence_Reply.Container_Screen_Cells),
        u8(Bridge_Consequence_Reply.Container_Icon_Title),
        u8(Bridge_Consequence_Reply.Container_Decline),
    }
    return bridge_consequence_signature(values[:])
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
    resource: u64,
    generation: u64,
    pixel_count: u64,
    stride: u64,
    width: u16,
    height: u16,
    format: u8,
    _reserved: [3]u8,
}

Canvas_Removal_Info :: struct {
    resource: u64,
    generation: u64,
}

Canvas_Command_Info :: struct {
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
