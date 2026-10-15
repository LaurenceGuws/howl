#ifndef HOWL_VT_NATIVE_H
#define HOWL_VT_NATIVE_H
#include <stdint.h>
#include <stddef.h>
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

#ifdef __cplusplus
extern "C" {
#endif
/* Standalone VT native owner contract.
 * Callers supply valid aligned storage for every advertised logical extent.
 * Fixed results/counts and owner slots must be disjoint from other argument storage.
 * Length/ceiling, address-addition and required-capacity admission precedes slices.
 * Null byte pointers are allowed only for zero logical input/copy extents.
 * All reserved input fields must be zero; every reserved output is zero.
 * Buffers remain untouched on failure; only fixed records/counts are initialized. */
#define HVT_MAX_SCREEN_CELLS 1048576u
#define HVT_MAX_INPUT_BYTES 65536u
#define HVT_INPUT_BUFFER_BYTES 512u
#define HVT_PASTE_EXTRA_BYTES 12u
#define HVT_MAX_COPY_BYTES 1048576u
/* Copied graphics is independent of Render and Server encoding. */
#define HVT_MAX_IMAGES 256u
#define HVT_MAX_IMAGE_PLACEMENTS 16384u
#define HVT_MAX_IMAGE_DIMENSION 4096u
#define HVT_MAX_IMAGE_BYTES 16777216u
#define HVT_MAX_IMAGE_STORAGE_BYTES 67108864u
typedef struct hvt_image {
    uint64_t generation;
    uint32_t image_id, width, height, byte_count;
} hvt_image;
typedef struct hvt_image_placement {
    uint64_t generation;
    uint32_t image_id, source_x, source_y, source_width, source_height;
    uint32_t cell_x, cell_y, pixel_width, pixel_height;
    int32_t z;
    uint16_t row, column;
    uint32_t reserved;
} hvt_image_placement;
typedef struct hvt_graphics {
    uint64_t terminal_revision, graphics_revision, content_revision;
    uint32_t image_count, placement_count, history_offset, cell_width, cell_height;
    uint16_t rows, columns;
    uint8_t alternate_screen, reserved[7];
} hvt_graphics;
/* Immutable logical-output snapshots own their copied bytes and loss records.
 * DATA preserves canonical primary output even while alternate screen is active.
 * max_entries counts text AND loss entries; line_count counts text entries only.
 * max_bytes (1..HVT_MAX_COPY_BYTES) bounds text+open line, not the loss array.
 * Non-DATA kinds retain only reported_id; every other field is zero/null. */
enum hvt_output_kind {
    HVT_OUTPUT_DATA=1, HVT_OUTPUT_CURSOR_STALE=2, HVT_OUTPUT_CURSOR_AHEAD=3,
    HVT_OUTPUT_LINE_TOO_LONG=4, HVT_OUTPUT_OPEN_LINE_TOO_LONG=5
};
enum hvt_output_loss_reason { HVT_OUTPUT_LOSS_LINE_TOO_LONG=1 };
typedef struct hvt_output hvt_output;
typedef struct hvt_output_loss {
    uint64_t id, byte_count;
    uint8_t reason, reserved[7];
} hvt_output_loss;
typedef struct hvt_output_view {
    const uint8_t *text; size_t text_len;
    const uint8_t *open_line; size_t open_line_len;
    const hvt_output_loss *losses; size_t loss_count;
    uint64_t terminal_revision, oldest, cursor, newest, reported_id;
    uint16_t line_count;
    uint8_t kind, more, open_line_omitted, reserved[3];
} hvt_output_view;
enum hvt_status {
    HVT_OK=0, HVT_INVALID_ARGUMENT=1, HVT_VERSION_MISMATCH=2,
    HVT_OUT_OF_MEMORY=3, HVT_RESOURCE_LIMIT=4, HVT_BUFFER_TOO_SMALL=5,
    HVT_STALE_REQUEST=6, HVT_REPLY_REQUIRED=7, HVT_CONTEXT_CHANGED=8,
    HVT_REQUEST_MISMATCH=9, HVT_INTERNAL=10 /* reserved; not a canonical error catch-all */
};
enum hvt_mutation {
    HVT_MUTATION_CURSOR=1, HVT_MUTATION_TEXT=2, HVT_MUTATION_VIEWPORT=4,
    HVT_MUTATION_IMAGES=8, HVT_MUTATION_MODE=16, HVT_MUTATION_TITLE=32,
    HVT_MUTATION_ICON=64, HVT_MUTATION_HISTORY_LOSS=128
};
typedef struct hvt_terminal hvt_terminal;
#define HVT_MAX_OBSERVATION_REFERENCES 1024u
typedef struct hvt_observation hvt_observation;
typedef struct hvt_config {
    uint16_t rows, columns, history_rows, reserved;
    uint32_t cell_width, cell_height;
} hvt_config;
typedef struct hvt_state {
    uint64_t terminal_revision, content_revision;
    uint32_t history_row_base, history_count, history_offset, cell_width, cell_height;
    uint16_t rows, columns, cursor_row, cursor_column;
    uint8_t alternate_screen, cursor_visible, synchronized_output, reserved;
} hvt_state;
typedef struct hvt_feed_progress {
    uint64_t terminal_revision, content_revision;
    size_t consumed;
    uint32_t mutations;
    uint8_t synchronized_ended, trailing_effect, held, reserved;
} hvt_feed_progress;
typedef struct hvt_animation {
    uint32_t next_ms;
    uint8_t changed, deadline_present, reserved[2];
} hvt_animation;

/* One serialized caller per owner; no thread, transport, process, scheduler or clock.
 * All fixed outputs/counts are initialized before later validation.
 * Ordinary query buffers/records are caller-owned copies. Optional hvt_observation
 * grants only retired-safe, synchronous module composition and owns no VT state.
 * Copying a handle creates no owner. Release once after all calls finish.
 * Constructor requires a null slot and publishes only complete state.
 * Rows/columns nonzero, rows*columns<=MAX_SCREEN_CELLS, config reserved=0.
 * Create cell dimensions are both zero (initially unknown) or both nonzero.
 * Release accepts both NULL slot pointer and NULL contained owner as no-ops. */
uint32_t hvt_abi_version(void);

/* An optional-native read capability: no C-readable VT data or mutation.
 * Source owner and one reference per successful open retain a small wrapper.
 * It never keeps terminal state alive or blocks source destruction.
 * Open requires matching version and a null out slot, preserves it on failure,
 * performs lazy allocation/reference admission and changes no VT revision.
 * All calls on source owner serialize with capture and source destruction.
 * Every reference must release once; copying a pointer adds no reference.
 * After source destruction it is safe to release, and Render reports its source
 * closed without touching freed VT. A new VT cannot revive the old capability.
 * Output slot/handle storage and all other input/result ranges are disjoint. */
uint32_t hvt_observation_open(uint32_t version, hvt_terminal *, hvt_observation **out);
/* Clears a caller reference, including a closed-source capability.
 * NULL slot/value are successful no-ops. Serializes with use of that reference;
 * independent retained references may release concurrently. */
uint32_t hvt_observation_release(hvt_observation **owner);


uint32_t hvt_create(uint32_t version, const hvt_config *, hvt_terminal **out);
void hvt_release(hvt_terminal **);
uint32_t hvt_observe(const hvt_terminal *, uint32_t history_offset, hvt_state *);

/* One serialized observation cut: ALL retained images in canonical order, and
 * only visible physical/Unicode-placeholder placements, densely filtered.
 * history_offset is clamped; zero cell dimensions mean unknown.
 * content_revision is graphics image-content identity, not VT contentSequence.
 * RGBA8 image bytes are tightly packed; byte_count == width*height*4.
 * Both arrays and fixed output must be disjoint. Capacities above their named
 * ceilings are rejected. Null arrays require zero capacity.
 * BUFFER_TOO_SMALL returns the coherent manifest and required counts without
 * writing either array. Other failures zero the fixed record. Unused tails
 * remain untouched. No terminal borrow or allocation escapes this call. */
uint32_t hvt_copy_graphics(const hvt_terminal *, uint32_t history_offset,
    hvt_image *, size_t image_capacity,
    hvt_image_placement *, size_t placement_capacity, hvt_graphics *);
/* Copy exact current image bytes for a manifest from THIS live owner. Caller
 * serializes mutation across calls or retries a fresh manifest on CONTEXT_CHANGED.
 * The guard rejects ANY intervening terminal mutation, including unrelated text.
 * Zero id/generation is invalid. Missing/replaced identity is CONTEXT_CHANGED.
 * BUFFER_TOO_SMALL alone reports required bytes; other failures zero the count.
 * Capacity is bounded by HVT_MAX_IMAGE_BYTES. Copies survive source destruction;
 * no shared snapshot cache, locking or automatic retry is supplied. */
uint32_t hvt_copy_image_pixels(const hvt_terminal *, uint64_t terminal_revision,
    uint32_t image_id, uint64_t image_generation, uint8_t *, size_t capacity, size_t *required);

/* Source mutation/destruction and open serialize externally. Version is checked
 * first; out requires a null slot and publishes only a complete immutable result.
 * Canonical cursor/retention/size outcomes are successful query kinds, not ABI
 * errors: reported_id is oldest/newest/line id/0 respectively. DATA has id=0.
 * No source, Instance, Reader or worker is retained. Existing result owners
 * survive source mutation/destruction; creating one never changes VT state. */
uint32_t hvt_output_open(uint32_t version, const hvt_terminal *, uint64_t cursor,
    uint16_t max_entries, size_t max_bytes, hvt_output **out);
/* Result-owned immutable spans, no NUL terminator promise. Empty spans are null.
 * Borrowed pointers last only until result release; no read/use may race release.
 * DATA.more concerns further finalized entries; open_line_omitted is independent.
 * Read is allocation-free and zeros its fixed output on invalid-null failure. */
uint32_t hvt_output_read(const hvt_output *, hvt_output_view *);
/* End all reads/borrows first. Both null forms are no-ops; clears slot before free.
 * Keep all originating matching-build libraries loaded through result release. */
void hvt_output_release(hvt_output **);


/* Feed exactly one canonical service-boundary prefix, input<=MAX_INPUT_BYTES.
 * On OK, consumed is exact (positive for nonempty input); continue at that offset.
 * Replies, retained requests and synchronized release may end the prefix.
 * Time is caller-supplied monotonic nanoseconds.
 * On failure progress is zero/invalid and a prefix MAY ALREADY HAVE MUTATED VT.
 * Never blindly replay the failed input. Caller chooses observation, draining,
 * explicit reset or destruction; this ABI does not guess consumed or auto-recover. */
uint32_t hvt_feed(hvt_terminal *, const uint8_t *, size_t length,
    uint64_t timestamp_ns, hvt_feed_progress *);
/* Resize is atomic on failure; history capacity is fixed by construction.
 * A zero cell pair preserves current known-or-unknown pixels. A nonzero pair
 * replaces pixels atomically with topology/replies; mixed zero pair is invalid. */
uint32_t hvt_resize(hvt_terminal *, uint16_t rows, uint16_t columns,
    uint32_t cell_width, uint32_t cell_height);
/* Apply canonical RIS and advance semantic/content identity exactly once.
 * Preserve dimensions, retained history, cell pixels and allocations, previously
 * queued reply bytes and retained requests. This is not constructor state or
 * a fresh byte stream; caller still services retained work explicitly. */
uint32_t hvt_reset(hvt_terminal *);
uint32_t hvt_service_animations(hvt_terminal *, uint64_t timestamp_ns, hvt_animation *);

/* Preflight capacity before encoding, including stateful locator/mouse effects.
 * Key/mouse/focus require INPUT_BUFFER_BYTES; paste requires length+PASTE_EXTRA_BYTES,
 * even when current mode needs fewer bytes. These are capacity bounds, not size queries.
 * Success writes only actual bytes. Failure writes no bytes and written=0.
 * Tags/booleans must be defined. buttons_down bits 0/1/2 mean left/middle/right;
 * bits 3..7 are invalid. Every modifier bit is defined. When pixels_present=0,
 * pixel_x/y are ignored. Paste input and required output prefix must be disjoint.
 * Canonical locator allocation/reply failure may retain latest pointer facts;
 * facade capacity/metadata rejection occurs before that operation.
 * No pointer into input/output is retained. Plain committed bytes need no encoding. */
uint32_t hvt_encode_named_key(hvt_terminal *, uint8_t key, uint8_t action, uint8_t mods,
    uint8_t *out, size_t capacity, size_t *written);
uint32_t hvt_encode_unicode_key(hvt_terminal *, uint32_t scalar, uint8_t action, uint8_t mods,
    uint8_t *out, size_t capacity, size_t *written);
uint32_t hvt_encode_mouse(hvt_terminal *, uint8_t kind, uint8_t button, uint8_t mods,
    uint8_t buttons_down, int32_t row, uint16_t column, uint8_t pixels_present,
    uint32_t pixel_x, uint32_t pixel_y, uint8_t *out, size_t capacity, size_t *written);
uint32_t hvt_encode_focus(hvt_terminal *, uint8_t focus, uint8_t *out,
    size_t capacity, size_t *written);
uint32_t hvt_encode_paste(hvt_terminal *, const uint8_t *, size_t length,
    uint8_t *out, size_t capacity, size_t *written);

/* Complete-or-untouched reply copy reports exact required bytes.
 * Explicit consume advances only the prefix successfully written externally.
 * Invalid consume count preserves queue; count zero is a no-op. */
uint32_t hvt_copy_replies(const hvt_terminal *, uint8_t *, size_t capacity, size_t *required);
uint32_t hvt_consume_replies(hvt_terminal *, size_t count);

/* Native copied VT queries; snapshots are synchronous copies, not a C view owner.
 * Search follows native VT bounded retained-history semantics; exact row-local
 * UTF-8 matching excludes concealed content, never joins soft wraps.
 * Search result complete/cut_revision/scanned_snapshots retain existing VT semantics.
 * Selection/link coordinates are stable with explicit columns/bank context.
 * All one-byte boolean input parameters are strictly 0 or 1. Byte copy capacities<=MAX_COPY_BYTES.
 * Selection shortage writes nothing, written=0; exact required length is not promised.
 * Hyperlink reports exact required bytes; no link is required=0.
 * Row-shape shortage writes nothing and reports exact required rows;
 * oversized arrays write only the advertised rows, preserving trailing storage.
 * Copied records/bytes survive all later terminal mutation and destruction. */
uint32_t hvt_copy_cell(const hvt_terminal *, uint32_t history_offset,
    uint16_t row, uint16_t column, hvt_cell *);
uint32_t hvt_search(const hvt_terminal *, const uint8_t *, size_t length,
    uint8_t reverse, uint8_t origin_present, int32_t row, uint16_t column, hvt_search_match *);
uint32_t hvt_expand_selection(const hvt_terminal *, uint8_t kind, uint32_t history_offset,
    int32_t row, uint16_t column, uint16_t expected_columns, uint8_t alternate, hvt_selection_range *);
uint32_t hvt_copy_selection(const hvt_terminal *, int32_t start_row, uint16_t start_column,
    int32_t end_row, uint16_t end_column, uint16_t expected_columns, uint8_t alternate,
    uint8_t *, size_t capacity, size_t *written);
uint32_t hvt_copy_hyperlink(const hvt_terminal *, uint32_t history_offset,
    int32_t row, uint16_t column, uint16_t expected_columns, uint8_t alternate,
    uint8_t *, size_t capacity, size_t *required);
uint32_t hvt_copy_row_shapes(const hvt_terminal *, uint32_t history_offset,
    hvt_row_shape *, size_t capacity, size_t *required);
uint32_t hvt_get_interaction(const hvt_terminal *, hvt_interaction *);

/* Exact FIFO-head request access and canonical named replies. No implicit host policy.
 * Reply bodies<=MAX_INPUT_BYTES; canonical reply/pointer/title limits also apply.
 * Payload copy is complete-or-untouched with exact required<=MAX_REQUEST_PAYLOAD_BYTES.
 * IDs are scoped to one terminal lifetime; stale/type/required-reply rejection preserves head.
 * Pointer query_requested remains distinct from canonical reply_required. */
uint32_t hvt_request_head(const hvt_terminal *, hvt_request *);
uint32_t hvt_copy_request_payload(const hvt_terminal *, uint64_t id,
    uint8_t *, size_t capacity, size_t *required);
uint32_t hvt_consume_request(hvt_terminal *, uint64_t id);
uint32_t hvt_reply_clipboard(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t hvt_reply_pointer_shape(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t hvt_reply_color_preference(hvt_terminal *, uint64_t id, uint8_t preference);
uint32_t hvt_reply_container_state(hvt_terminal *, uint64_t id, uint8_t state);
uint32_t hvt_reply_container_position(hvt_terminal *, uint64_t id, uint32_t x, uint32_t y);
uint32_t hvt_reply_container_screen_cells(hvt_terminal *, uint64_t id, uint32_t rows, uint32_t columns);
uint32_t hvt_reply_container_icon_title(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t hvt_decline_container(hvt_terminal *, uint64_t id);

#ifdef __cplusplus
}
#endif
#endif
