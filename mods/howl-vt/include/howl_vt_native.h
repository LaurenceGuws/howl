#ifndef HOWL_VT_NATIVE_H
#define HOWL_VT_NATIVE_H
#include <stdint.h>
/* VT-owned native vocabulary, independent of Server framing and Zig enum layout.
 * Version 1. Fixed-width values; unknown tags are rejected before terminal mutation. */
#define HVT_NATIVE_VERSION 1u
#define HVT_MAXIMUM_CELL_SCALARS 24u
#define HVT_MAX_SEARCH_QUERY_BYTES 4096u
enum hvt_named_key {
    HVT_KEY_ENTER = 1,
    HVT_KEY_TAB = 2,
    HVT_KEY_BACKSPACE = 3,
    HVT_KEY_ESCAPE = 4,
    HVT_KEY_UP = 5,
    HVT_KEY_DOWN = 6,
    HVT_KEY_LEFT = 7,
    HVT_KEY_RIGHT = 8,
    HVT_KEY_INSERT = 9,
    HVT_KEY_DELETE = 10,
    HVT_KEY_HOME = 11,
    HVT_KEY_END = 12,
    HVT_KEY_PAGE_UP = 13,
    HVT_KEY_PAGE_DOWN = 14,
    HVT_KEY_LEFT_SHIFT = 15,
    HVT_KEY_RIGHT_SHIFT = 16,
    HVT_KEY_LEFT_CONTROL = 17,
    HVT_KEY_RIGHT_CONTROL = 18,
    HVT_KEY_LEFT_ALT = 19,
    HVT_KEY_RIGHT_ALT = 20,
    HVT_KEY_LEFT_SUPER = 21,
    HVT_KEY_RIGHT_SUPER = 22,
    HVT_KEY_LEFT_HYPER = 23,
    HVT_KEY_RIGHT_HYPER = 24,
    HVT_KEY_LEFT_META = 25,
    HVT_KEY_RIGHT_META = 26,
    HVT_KEY_CAPS_LOCK = 27,
    HVT_KEY_NUM_LOCK = 28,
    HVT_KEY_F1 = 29,
    HVT_KEY_F2 = 30,
    HVT_KEY_F3 = 31,
    HVT_KEY_F4 = 32,
    HVT_KEY_F5 = 33,
    HVT_KEY_F6 = 34,
    HVT_KEY_F7 = 35,
    HVT_KEY_F8 = 36,
    HVT_KEY_F9 = 37,
    HVT_KEY_F10 = 38,
    HVT_KEY_F11 = 39,
    HVT_KEY_F12 = 40,
    HVT_KEY_KEYPAD_0 = 41,
    HVT_KEY_KEYPAD_1 = 42,
    HVT_KEY_KEYPAD_2 = 43,
    HVT_KEY_KEYPAD_3 = 44,
    HVT_KEY_KEYPAD_4 = 45,
    HVT_KEY_KEYPAD_5 = 46,
    HVT_KEY_KEYPAD_6 = 47,
    HVT_KEY_KEYPAD_7 = 48,
    HVT_KEY_KEYPAD_8 = 49,
    HVT_KEY_KEYPAD_9 = 50,
    HVT_KEY_KEYPAD_DECIMAL = 51,
    HVT_KEY_KEYPAD_ADD = 52,
    HVT_KEY_KEYPAD_SUBTRACT = 53,
    HVT_KEY_KEYPAD_MULTIPLY = 54,
    HVT_KEY_KEYPAD_DIVIDE = 55,
    HVT_KEY_KEYPAD_SEPARATOR = 56,
    HVT_KEY_KEYPAD_EQUAL = 57,
    HVT_KEY_KEYPAD_ENTER = 58,
};
enum hvt_key_action { HVT_PRESS=1, HVT_REPEAT=2, HVT_RELEASE=3 };
enum hvt_mouse_kind { HVT_MOUSE_PRESS=1, HVT_MOUSE_RELEASE=2, HVT_MOUSE_MOVE=3, HVT_MOUSE_WHEEL=4 };
enum hvt_mouse_button { HVT_BUTTON_NONE=0, HVT_BUTTON_LEFT=1, HVT_BUTTON_MIDDLE=2, HVT_BUTTON_RIGHT=3, HVT_BUTTON_WHEEL_UP=4, HVT_BUTTON_WHEEL_DOWN=5 };
enum hvt_focus { HVT_FOCUS_IN=1, HVT_FOCUS_OUT=2 };
enum hvt_modifier { HVT_SHIFT=1, HVT_ALT=2, HVT_CONTROL=4, HVT_SUPER=8, HVT_HYPER=16, HVT_META=32, HVT_CAPS_LOCK=64, HVT_NUM_LOCK=128 };
/* Copied scalar/occupancy observation, not a renderer-complete cell.
 * All scalar slots are initialized. x/y are offsets from the cluster lead;
 * x==0 && y==0 identifies the lead. Continuations resolve the same scalars.
 * width/height describe the full occupied cluster, including OSC 66 multi-cell text.
 * Caller storage survives subsequent terminal mutation. */
typedef struct hvt_cell {
    uint32_t scalars[HVT_MAXIMUM_CELL_SCALARS];
    uint8_t scalar_count, width, height, x, y;
    uint8_t reserved[3];
} hvt_cell;
/* Copied query records use stable history/screen row coordinates. A matching
 * columns/alternate-screen context is required for selection and link lookup.
 * Search is exact, case-sensitive UTF-8 within one row; concealed text is excluded.
 * cut_revision is the observation source cut; scanned_snapshots counts row cuts
 * for a live VT search. These records own no pointer or lifetime. */
enum hvt_selection_kind { HVT_SELECTION_WORD=1, HVT_SELECTION_VISUAL_ROW=2 };
typedef struct hvt_search_match {
    uint64_t cut_revision;
    int32_t row;
    uint16_t start_column, end_column, columns;
    uint8_t found, complete, alternate_screen, _reserved;
    uint32_t scanned_snapshots;
} hvt_search_match;
typedef struct hvt_selection_range {
    int32_t start_row, end_row;
    uint16_t start_column, end_column, columns;
    uint8_t found, alternate_screen, _reserved[2];
} hvt_selection_range;
typedef struct hvt_row_shape { uint16_t content_end_exclusive; uint8_t wrapped, _reserved; } hvt_row_shape;
enum hvt_interaction_flags { HVT_INTERACTION_ALTERNATE_SCROLL=1, HVT_INTERACTION_FOCUS_REPORTING=2 };
enum hvt_mouse_tracking { HVT_TRACK_OFF=0, HVT_TRACK_X10=1, HVT_TRACK_NORMAL=2, HVT_TRACK_BUTTON_EVENT=3, HVT_TRACK_ANY_EVENT=4 };
enum hvt_mouse_protocol { HVT_MOUSE_NONE_PROTOCOL=0, HVT_MOUSE_UTF8=1, HVT_MOUSE_SGR=2, HVT_MOUSE_SGR_PIXEL=3, HVT_MOUSE_URXVT=4 };
typedef struct hvt_interaction {
    uint64_t terminal_revision;
    uint32_t flags;
    uint8_t mouse_tracking, mouse_protocol, pointer_mode, _reserved;
} hvt_interaction;

/* Copied pending terminal requests. kind selects the native data union arm.
 * These are C-defined layouts, never Zig unions or Server wire metadata.
 * occurrence_id is scoped to the matching Instance/Terminal lifetime.
 * reply_required describes canonical consume refusal; pointer query_requested
 * separately permits caller policy to reply or consume. Payload copies are
 * complete-or-untouched and checked against the exact current occurrence. */
#define HVT_MAX_REQUEST_PAYLOAD_BYTES 1048576u
enum hvt_request_kind { HVT_REQUEST_NONE=0, HVT_REQUEST_CLIPBOARD=1, HVT_REQUEST_NOTIFICATION=2, HVT_REQUEST_POINTER_SHAPE=3, HVT_REQUEST_FILE_TRANSFER=4, HVT_REQUEST_DRAG_DROP=5, HVT_REQUEST_CONTAINER=6, HVT_REQUEST_COLOR_PREFERENCE=7, HVT_REQUEST_MEDIA_COPY=8, HVT_REQUEST_BELL=9, HVT_REQUEST_LEGACY_CONTROL=10, HVT_REQUEST_DCS=11, HVT_REQUEST_STRING_CONTROL=12 };
enum hvt_clipboard_operation { HVT_CLIPBOARD_SET=1, HVT_CLIPBOARD_QUERY=2, HVT_CLIPBOARD_PACKET=3 };
enum hvt_clipboard_protocol { HVT_CLIPBOARD_OSC52=1, HVT_CLIPBOARD_KITTY_5522=2 };
enum hvt_notification_kind { HVT_NOTIFICATION_MESSAGE=1, HVT_NOTIFICATION_STEAL_FOCUS=2, HVT_NOTIFICATION_REQUEST_ATTENTION=3 };
enum hvt_file_protocol { HVT_FILE_ITERM2_1337=1, HVT_FILE_KITTY_5113=2 };
enum hvt_drag_kind { HVT_DRAG_ENABLE=1, HVT_DRAG_DISABLE=2, HVT_DRAG_ACCEPT=3, HVT_DRAG_REQUEST=4, HVT_DRAG_COMPLETE=5, HVT_DRAG_QUERY=6, HVT_DRAG_CONTINUATION=7, HVT_DRAG_UNSUPPORTED=8 };
enum hvt_container_operation { HVT_CONTAINER_DEICONIFY=1, HVT_CONTAINER_ICONIFY=2, HVT_CONTAINER_MOVE=3, HVT_CONTAINER_RESIZE_PIXELS=4, HVT_CONTAINER_RAISE=5, HVT_CONTAINER_LOWER=6, HVT_CONTAINER_RESIZE_ROWS=7, HVT_CONTAINER_RESIZE_COLUMNS=8, HVT_CONTAINER_RESIZE_CELLS=9, HVT_CONTAINER_REPORT_STATE=10, HVT_CONTAINER_REPORT_POSITION=11, HVT_CONTAINER_REPORT_SCREEN_CELLS=12, HVT_CONTAINER_REPORT_ICON_TITLE=13 };
enum hvt_legacy_operation { HVT_LEGACY_TEK_POINT_PLOT=1, HVT_LEGACY_TEK_GRAPH=2, HVT_LEGACY_TEK_INCREMENTAL_PLOT=3, HVT_LEGACY_TEK_ALPHA=4, HVT_LEGACY_TEK_COPY=5, HVT_LEGACY_TEK_SPECIAL_POINT_PLOT=6, HVT_LEGACY_TEK_WRITE_THRU_SHORT_DASHED=7, HVT_LEGACY_HP_MEMORY_LOCK=8 };
enum hvt_dcs_operation { HVT_DCS_XTSETTCAP=1, HVT_DCS_DECUDK=2, HVT_DCS_DECAUPSS=3, HVT_DCS_ITERM_TMUX_HOOK=4, HVT_DCS_ITERM_SSH_HOOK=5, HVT_DCS_ITERM_TMUX_WRAP=6, HVT_DCS_KITTY_REMOTE_COMMAND=7, HVT_DCS_KITTY_OVERLAY_READY=8, HVT_DCS_KITTY_RESULT=9, HVT_DCS_KITTY_PRINT=10, HVT_DCS_KITTY_ECHO=11, HVT_DCS_KITTY_SSH=12, HVT_DCS_KITTY_ASKPASS=13, HVT_DCS_KITTY_CLONE=14, HVT_DCS_KITTY_EDIT=15 };
enum hvt_string_operation { HVT_STRING_APC=1, HVT_STRING_PM=2, HVT_STRING_SOS=3 };
enum hvt_color_preference { HVT_COLOR_DARK=1, HVT_COLOR_LIGHT=2 };
enum hvt_container_state { HVT_CONTAINER_STATE_NORMAL=1, HVT_CONTAINER_STATE_ICONIFIED=2 };
typedef struct hvt_request_clipboard {
    uint8_t operation, protocol; uint16_t _reserved; uint32_t selection_len;
} hvt_request_clipboard;
typedef struct hvt_request_notification {
    uint16_t command; uint8_t kind, _reserved;
} hvt_request_notification;
typedef struct hvt_request_pointer {
    uint64_t reset_generation;
    uint8_t alternate_screen, query_requested, _reserved[6];
} hvt_request_pointer;
typedef struct hvt_request_file { uint8_t protocol, _reserved[7]; } hvt_request_file;
typedef struct hvt_request_drag {
    uint32_t client_id, operation, index;
    uint8_t kind, command, more, remote, has_client_id, has_operation, has_index, _reserved;
} hvt_request_drag;
typedef struct hvt_request_container {
    uint8_t operation, _reserved[3];
    uint32_t x, y, width, height, rows, columns;
} hvt_request_container;
typedef struct hvt_request_media { uint16_t parameter; uint8_t is_private, _reserved; } hvt_request_media;
typedef struct hvt_request_legacy { uint8_t operation, _reserved[7]; } hvt_request_legacy;
typedef struct hvt_request_dcs { uint8_t operation, _reserved[7]; } hvt_request_dcs;
typedef struct hvt_request_string { uint8_t operation, _reserved[7]; } hvt_request_string;
typedef union hvt_request_data {
    hvt_request_clipboard clipboard;
    hvt_request_notification notification;
    hvt_request_pointer pointer_shape;
    hvt_request_file file_transfer;
    hvt_request_drag drag_drop;
    hvt_request_container container;
    hvt_request_media media_copy;
    hvt_request_legacy legacy_control;
    hvt_request_dcs dcs;
    hvt_request_string string_control;
} hvt_request_data;
typedef struct hvt_request {
    uint64_t occurrence_id, terminal_revision;
    uint32_t payload_len;
    uint8_t kind, reply_required; uint16_t _reserved;
    hvt_request_data data;
} hvt_request;
#endif
