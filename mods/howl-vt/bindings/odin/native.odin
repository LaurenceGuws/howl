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
