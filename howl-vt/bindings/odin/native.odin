package howl_vt_native

// Version-1 VT native input bindings. Values belong to howl_vt_native.h,
// not Server framing or a host runtime. No process, worker or transport ownership.

Mouse_Kind :: enum u8 {
    Press = 1,
    Release = 2,
    Move = 3,
    Wheel = 4,
}

Mouse_Button :: enum u8 {
    None = 0,
    Left = 1,
    Middle = 2,
    Right = 3,
    Wheel_Up = 4,
    Wheel_Down = 5,
}

Focus :: enum u8 {
    In = 1,
    Out = 2,
}

Key :: enum u8 {
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

Key_Action :: enum u8 {
    Press   = 1,
    Repeat  = 2,
    Release = 3,
}

MOD_SHIFT :: u8(1 << 0)
MOD_ALT :: u8(1 << 1)
MOD_CONTROL :: u8(1 << 2)
MOD_SUPER :: u8(1 << 3)
MOD_CAPS_LOCK :: u8(1 << 6)
MOD_NUM_LOCK :: u8(1 << 7)
MOD_HYPER :: u8(1 << 4)
MOD_META :: u8(1 << 5)

// Copied VT-owned observation records; no live terminal pointers cross this surface.
Search_Match_Info :: struct {
    cut_revision: u64,
    row: i32,
    start_column, end_column, columns: u16,
    found, complete, alternate_screen, _reserved: u8,
    scanned_snapshots: u32,
}
Selection_Range_Info :: struct {
    start_row, end_row: i32,
    start_column, end_column, columns: u16,
    found, alternate_screen: u8,
    _reserved: [2]u8,
}
Row_Shape :: struct {
    content_end_exclusive: u16,
    wrapped, _reserved: u8,
}
Interaction_State_Info :: struct {
    terminal_revision: u64,
    flags: u32,
    mouse_tracking, mouse_protocol, pointer_mode, _reserved: u8,
}

// Native pending terminal-request tags and copied C layouts.
Request_Kind :: enum u8 {
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
Clipboard_Operation :: enum u8 {
    Set = 1,
    Query = 2,
    Packet = 3,
}
Clipboard_Protocol :: enum u8 {
    Osc52 = 1,
    Kitty_5522 = 2,
}
Notification_Kind :: enum u8 {
    Message = 1,
    Steal_Focus = 2,
    Request_Attention = 3,
}
File_Protocol :: enum u8 {
    Iterm2_1337 = 1,
    Kitty_5113 = 2,
}
Drag_Kind :: enum u8 {
    Enable = 1,
    Disable = 2,
    Accept = 3,
    Request = 4,
    Complete = 5,
    Query = 6,
    Continuation = 7,
    Unsupported = 8,
}
Container_Operation :: enum u8 {
    Deiconify = 1,
    Iconify = 2,
    Move = 3,
    Resize_Pixels = 4,
    Raise = 5,
    Lower = 6,
    Resize_Rows = 7,
    Resize_Columns = 8,
    Resize_Cells = 9,
    Report_State = 10,
    Report_Position = 11,
    Report_Screen_Cells = 12,
    Report_Icon_Title = 13,
}
Legacy_Operation :: enum u8 {
    Tek_Point_Plot = 1,
    Tek_Graph = 2,
    Tek_Incremental_Plot = 3,
    Tek_Alpha = 4,
    Tek_Copy = 5,
    Tek_Special_Point_Plot = 6,
    Tek_Write_Thru_Short_Dashed = 7,
    Hp_Memory_Lock = 8,
}
Dcs_Operation :: enum u8 {
    Xtsettcap = 1,
    Decudk = 2,
    Decaupss = 3,
    Iterm_Tmux_Hook = 4,
    Iterm_Ssh_Hook = 5,
    Iterm_Tmux_Wrap = 6,
    Kitty_Remote_Command = 7,
    Kitty_Overlay_Ready = 8,
    Kitty_Result = 9,
    Kitty_Print = 10,
    Kitty_Echo = 11,
    Kitty_Ssh = 12,
    Kitty_Askpass = 13,
    Kitty_Clone = 14,
    Kitty_Edit = 15,
}
String_Operation :: enum u8 {
    Apc = 1,
    Pm = 2,
    Sos = 3,
}
Color_Preference :: enum u8 {
    Dark = 1,
    Light = 2,
}
Container_State :: enum u8 {
    Normal = 1,
    Iconified = 2,
}
Request_Clipboard :: struct { operation, protocol: u8, _reserved: u16, selection_len: u32, }
Request_Notification :: struct { command: u16, kind, _reserved: u8, }
Request_Pointer :: struct { reset_generation: u64, alternate_screen, query_requested: u8, _reserved: [6]u8, }
Request_File :: struct { protocol: u8, _reserved: [7]u8, }
Request_Drag :: struct {
    client_id, operation, index: u32,
    kind, command, more, remote, has_client_id, has_operation, has_index, _reserved: u8,
}
Request_Container :: struct {
    operation: u8,
    _reserved: [3]u8,
    x, y, width, height, rows, columns: u32,
}
Request_Media :: struct { parameter: u16, is_private, _reserved: u8, }
Request_Legacy :: struct { operation: u8, _reserved: [7]u8, }
Request_Dcs :: struct { operation: u8, _reserved: [7]u8, }
Request_String :: struct { operation: u8, _reserved: [7]u8, }
Request_Data :: struct #raw_union {
    clipboard: Request_Clipboard,
    notification: Request_Notification,
    pointer_shape: Request_Pointer,
    file_transfer: Request_File,
    drag_drop: Request_Drag,
    container: Request_Container,
    media_copy: Request_Media,
    legacy_control: Request_Legacy,
    dcs: Request_Dcs,
    string_control: Request_String,
}
Request_Info :: struct {
    occurrence_id, terminal_revision: u64,
    payload_len: u32,
    kind, reply_required: u8,
    _reserved: u16,
    data: Request_Data,
}
