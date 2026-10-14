#ifndef HOWL_INSTANCE_NATIVE_H
#define HOWL_INSTANCE_NATIVE_H
#include <stddef.h>
#include <stdint.h>
#include "howl_vt_native.h"
#include "howl_render_native.h"
#ifdef __cplusplus
extern "C" {
#endif
#define HI_ABI_VERSION 1u
#if HRC_NATIVE_VERSION != 1u
#error "Instance ABI v1 incorporates Render native v1; changing its layout requires ABI review/versioning"
#endif
#if HVT_NATIVE_VERSION != 1u
#error "Instance ABI v1 incorporates VT native v1; changing its layout requires Instance ABI review/versioning"
#endif
typedef struct hi_instance hi_instance;
enum hi_status { HI_OK=0, HI_INVALID_ARGUMENT=1, HI_OUT_OF_MEMORY=2, HI_RESOURCE_LIMIT=3, HI_OPERATION_FAILED=4, HI_UNSUPPORTED=5, HI_VERSION_MISMATCH=6, HI_BUSY=7, HI_NO_FRAME=8, HI_PRESENTATION_UNAVAILABLE=9, HI_CONTEXT_CHANGED=10, HI_BUFFER_TOO_SMALL=11, HI_STALE_REQUEST=12, HI_REPLY_REQUIRED=13, HI_REQUEST_MISMATCH=14 };
enum hi_service_policy { HI_SERVICE_HEADLESS=1, HI_SERVICE_RETAIN=2 };
enum hi_signal { HI_HANGUP=1, HI_INTERRUPT=2, HI_RESIZE_NOTIFY=3, HI_KILL=9, HI_TERMINATE=15 };
enum hi_signal_result { HI_SIGNAL_DELIVERED=1, HI_SIGNAL_TARGET_MISSING=2, HI_SIGNAL_PERMISSION_DENIED=3, HI_SIGNAL_NATIVE_FAILURE=4 };
/* Endpoint open is producer-thread-only; frame acquire/read/release/close are
 * single-backend-thread operations after explicit handoff. No live Instance is
 * handed to the backend. An open endpoint pins parent publication storage even
 * between frames. Checked parent destruction returns HI_BUSY without mutation.
 * Opening resets backend residency to empty. Caller publishes a fresh cut before
 * handoff. Presented construction uses the matching hi_create_presented contract. */
typedef struct hi_frame_stream hi_frame_stream;
typedef struct hi_frame_info {
    uint64_t sequence, presentation_generation, revision, content_revision, terminal_revision;
    uint32_t command_count, content_command_count, upload_count, removal_count;
    uint32_t history_offset, history_count, history_row_base;
    uint32_t background_rgba;
    uint16_t surface_width, surface_height, cell_width, cell_height;
    uint8_t alternate_screen;
    uint8_t reserved[7];
} hi_frame_info;

typedef struct hi_bytes { const uint8_t *data; size_t len; } hi_bytes;
#define HI_MAX_FONT_FALLBACKS 24u
#define HI_MAX_FONT_PATH_BYTES 4096u
#define HI_MAX_FONT_BYTES (32u * 1024u * 1024u)
#define HI_MAX_FONT_SET_BYTES (64u * 1024u * 1024u)
#define HI_MAX_PRESENTATION_ITEMS 1048576u
#define HI_MAX_PRESENTATION_SHAPED 65536u
#define HI_MAX_PRESENTATION_ROWS 192u
#define HI_MAX_PRESENTATION_RASTER_BYTES (16u * 1024u * 1024u)

typedef struct hi_presentation hi_presentation;
enum hi_font_kind { HI_FONT_NONE=0, HI_FONT_PATH=1, HI_FONT_MEMORY=2 };
enum hi_font_variant { HI_FONT_REGULAR=0, HI_FONT_ITALIC=1, HI_FONT_BOLD=2, HI_FONT_BOLD_ITALIC=3 };
typedef struct hi_font_source {
    uint8_t kind, reserved[7];
    hi_bytes primary;
    const hi_bytes *fallbacks;
    size_t fallback_count;
} hi_font_source;
/* Required capacities are positive. Shape item capacities <= ITEMS; sequence
 * and shaped scratch <= SHAPED; sequence <= shape_scalars; raster <= RASTER_BYTES.
 * One physical pixel_size applies to every variant and fallback. */
typedef struct hi_presentation_config {
    hi_font_source fonts[4];
    uint16_t pixel_size, reserved;
    uint32_t max_sequence_scalars;
    size_t shape_entries, shape_scalars, shape_glyphs;
    size_t shaped_capacity, raster_bytes;
} hi_presentation_config;
typedef struct hi_cell_size {
    uint16_t width, height;
    uint32_t reserved;
} hi_cell_size;
/* Positive normalized DPI and canonical finite strokes. Atlas pixels <=
 * RASTER_BYTES. Entries/command capacities <= ITEMS; hard limit >= initial > 0.
 * Retained rows <= ROWS; rows and incremental_commands are both zero or positive.
 * Reserved fields in every input record must be zero. */
typedef struct hi_presented_config {
    float stroke_points[4];
    uint32_t dpi_x_numerator, dpi_x_denominator;
    uint32_t dpi_y_numerator, dpi_y_denominator;
    uint16_t atlas_width, atlas_height, atlas_gap, incremental_rows;
    size_t atlas_entries, command_capacity, command_limit, incremental_commands;
    uint8_t reserved[8];
} hi_presented_config;

/* Creation requires *out==NULL and preserves it on failure. The regular font
 * is required; other styles may be NONE only with every other source field zero.
 * All source descriptors and data borrow only this call. Text owns copied paths
 * or memory fonts on success; source files follow its path-backed contract.
 * Memory sources are bounded to FONT_BYTES each and FONT_SET_BYTES per variant;
 * paths to FONT_PATH_BYTES each. Fallback count <= FONT_FALLBACKS.
 * Pixel sizing is explicit. Font discovery and point-size configuration are
 * outside this initial composed C interface. Capacity limits are explicit.
 * Existing Instances retain the canonical Store after caller release.
 * Operations on this caller handle must serialize against release. */
uint32_t hi_presentation_create(uint32_t version, const hi_presentation_config *, hi_presentation **out);
uint32_t hi_presentation_release(hi_presentation **owner);
/* Output is initialized whenever non-null. Returns copied canonical geometry. */
uint32_t hi_presentation_cell_size(const hi_presentation *, hi_cell_size *out);


typedef struct hi_launch {
    hi_bytes shell, command, cwd;
    const hi_bytes *environment;
    size_t environment_count;
    uint16_t rows, columns, history_rows, reserved;
    uint32_t cell_width, cell_height;
} hi_launch;
/* All fields are initialized on entry when the output pointer is non-null.
 * exit_kind: 0=not observed, 1=normal code, 2=signal.
 * animation_wait_present distinguishes no deadline from a zero-ms deadline.
 * descriptor_kind: 1=borrowed POSIX fd; never close it.
 * No clocks, waits, wake sources, graphics backend or host queue are owned by this API. */
typedef struct hi_service {
    uint64_t terminal_revision;
    int32_t descriptor;
    uint32_t animation_wait_ms;
    uint8_t changed, viewport_changed, stream_closed, write_pending;
    uint8_t buffered_output_pending, animation_wait_present, exit_kind, exit_value;
    uint8_t sync_ended, sync_trailing_effect, retained_fallback, descriptor_kind;
    uint8_t reserved[4];
} hi_service;
/* Live handles are constructor-owned, caller-serialized and invalid after destroy.
 * Different Instance specializations and Server handles must never be cast here.
 * Arrays/strings borrow caller memory only for the duration of each call.
 * create requires *out==NULL; failure preserves it.
 * Linux create copies an explicit environment (<=1024 entries, <=1MiB including
 * terminators and terminal identity replacements). Entries are NAME=VALUE with
 * nonempty names and no embedded NUL; duplicate names are rejected.
 * TERM/COLORTERM are replaced by canonical Instance policy. Empty environment is
 * explicit, never an implicit capture of the embedding process environment.
 * Initial standalone native lifecycle is Linux-qualified; other targets return
 * HI_UNSUPPORTED. The artifact selects the exact local Instance composition.
 * First service contract applies deterministic headless consequence policy.
 * hi_create_presented derives its lattice from an explicit presentation owner. */
uint32_t hi_abi_version(void);
uint32_t hi_create(uint32_t version, const hi_launch *launch, hi_instance **out);
/* A matching presentation is required.
 * Launch cell_width/cell_height must both be zero: regular-font metrics supply
 * the sole canonical pixel lattice. Construction only tries shared font access.
 * HI_BUSY publishes no owner and launches no child; the caller chooses retry.
 * Other construction failures release staged resources; child-side effects of a
 * late failure cannot be undone. No worker, clock, wait backend or UI is owned.
 * hi_destroy and all existing operations use this same exact local handle type. */
uint32_t hi_create_presented(uint32_t version, const hi_launch *,
    hi_presentation *, const hi_presented_config *, hi_instance **out);

uint32_t hi_destroy(hi_instance **owner);
uint32_t hi_send_text(hi_instance *, const uint8_t *, size_t);
uint32_t hi_send_paste(hi_instance *, const uint8_t *, size_t);
uint32_t hi_send_named_key(hi_instance *, uint8_t key, uint8_t action, uint8_t modifiers);
uint32_t hi_send_unicode_key(hi_instance *, uint32_t scalar, uint8_t action, uint8_t modifiers);
uint32_t hi_send_mouse(hi_instance *, uint8_t kind, uint8_t button, uint8_t modifiers, uint8_t buttons_down, int32_t row, uint16_t column, uint8_t pixels_present, uint32_t pixel_x, uint32_t pixel_y);
uint32_t hi_send_focus(hi_instance *, uint8_t focus);
uint32_t hi_resize(hi_instance *, uint16_t rows, uint16_t columns, uint32_t cell_width, uint32_t cell_height);
uint32_t hi_signal_group(hi_instance *, uint8_t signal, uint8_t *result);
uint32_t hi_service_turn(hi_instance *, uint8_t readable, uint8_t writable, uint64_t monotonic_ns, hi_service *out);
/* Explicit per-turn consequence policy. Retain preserves canonical bounded queue
 * pressure fallback and reports retained_fallback. Switching to headless drains
 * pending requests with the existing deterministic policy on that same turn. */
uint32_t hi_service_turn_policy(hi_instance *, uint8_t policy, uint8_t readable, uint8_t writable, uint64_t monotonic_ns, hi_service *out);
/* Copied pending request facts and exact-head operations, serialized by the owner.
 * head does not consume and may return kind NONE. Payload capacity <=1MiB;
 * required reports complete length on HI_BUFFER_TOO_SMALL, with no byte writes.
 * Caller copies survive owner mutation/destruction; occurrence IDs remain scoped
 * to their matching live owner. Stale/wrong/malformed replies leave the head live.
 * Named reply calls borrow bytes during the call, serialize/copy them canonically,
 * and consume only after successful admission. They do not flush/poll/wait.
 * Re-query service facts after replies before deciding I/O readiness. */
uint32_t hi_request_head(const hi_instance *, hvt_request *out);
uint32_t hi_copy_request_payload(const hi_instance *, uint64_t occurrence_id, uint8_t *output, size_t capacity, size_t *required);
uint32_t hi_consume_request(hi_instance *, uint64_t occurrence_id);
uint32_t hi_reply_clipboard(hi_instance *, uint64_t occurrence_id, const uint8_t *bytes, size_t length);
uint32_t hi_reply_pointer_shape(hi_instance *, uint64_t occurrence_id, const uint8_t *bytes, size_t length);
uint32_t hi_reply_color_preference(hi_instance *, uint64_t occurrence_id, uint8_t preference);
uint32_t hi_reply_container_state(hi_instance *, uint64_t occurrence_id, uint8_t state);
uint32_t hi_reply_container_position(hi_instance *, uint64_t occurrence_id, uint32_t x, uint32_t y);
uint32_t hi_reply_container_screen_cells(hi_instance *, uint64_t occurrence_id, uint32_t rows, uint32_t columns);
uint32_t hi_reply_container_icon_title(hi_instance *, uint64_t occurrence_id, const uint8_t *bytes, size_t length);
uint32_t hi_decline_container(hi_instance *, uint64_t occurrence_id);
uint32_t hi_copy_cell(const hi_instance *, uint32_t history_offset, uint16_t row, uint16_t column, hvt_cell *out);
/* Synchronous copied VT queries on the serialized owner thread. No borrowed
 * terminal pointer escapes. Selection/link context is exact columns+screen bank.
 * Search query is <=HVT_MAX_SEARCH_QUERY_BYTES; text/link output capacity <=1MiB.
 * Text copy is complete or fails; byte output is untouched on capacity failure.
 * Hyperlink length reports the full required length even on HI_BUFFER_TOO_SMALL;
 * selection length is zero on failure. Row count likewise reports required rows
 * on capacity failure. Match/range/interaction records are initialized on entry. */
uint32_t hi_search(const hi_instance *, const uint8_t *query, size_t query_len, uint8_t reverse, uint8_t origin_present, int32_t origin_row, uint16_t origin_column, hvt_search_match *out);
uint32_t hi_expand_selection(const hi_instance *, uint8_t kind, uint32_t history_offset, int32_t target_row, uint16_t target_column, uint16_t expected_columns, uint8_t expected_alternate, hvt_selection_range *out);
uint32_t hi_copy_selection(const hi_instance *, int32_t start_row, uint16_t start_column, int32_t end_row, uint16_t end_column, uint16_t expected_columns, uint8_t expected_alternate, uint8_t *output, size_t capacity, size_t *length);
uint32_t hi_copy_hyperlink(const hi_instance *, uint32_t history_offset, int32_t target_row, uint16_t target_column, uint16_t expected_columns, uint8_t expected_alternate, uint8_t *output, size_t capacity, size_t *required);
uint32_t hi_copy_row_shapes(const hi_instance *, uint32_t history_offset, hvt_row_shape *output, size_t capacity, size_t *count);
uint32_t hi_interaction(const hi_instance *, hvt_interaction *out);
/* Arrays are caller-owned copies. Upload pixel pointers borrow the immutable
 * frame only until release/abandon/close. Bulk capacity failure modifies no arrays. Command capacity may exceed the leased
 * count; only the advertised count is written. Counts exceeding uint32_t are
 * rejected at acquisition with HI_RESOURCE_LIMIT and no active lease.
 * Invalid or busy feedback leaves the lease active for correction/retry.
 * Abandon is for a candidate that established no new backend resource state.
 * Producer open must be serialized against new opens and parent destruction. */
uint32_t hi_publish_frame(hi_instance *, uint32_t history_offset);
uint32_t hi_frame_open(uint32_t version, hi_instance *, hi_frame_stream **out);
void hi_frame_close(hi_frame_stream **owner);
uint32_t hi_frame_acquire(hi_frame_stream *, hi_frame_info *out);
uint32_t hi_frame_commands(hi_frame_stream *, hrc_command *out, size_t capacity);
uint32_t hi_frame_uploads(hi_frame_stream *, hrc_upload *out, size_t capacity);
uint32_t hi_frame_removals(hi_frame_stream *, hrc_removal *out, size_t capacity);
uint32_t hi_frame_release(hi_frame_stream *, const hrc_residency *, size_t count);
uint32_t hi_frame_abandon(hi_frame_stream *);
#ifdef __cplusplus
}
#endif
#endif
