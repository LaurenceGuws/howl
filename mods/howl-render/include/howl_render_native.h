#ifndef HOWL_RENDER_NATIVE_H
#define HOWL_RENDER_NATIVE_H
#include <stdint.h>
#include <stddef.h>
/* Render-owned version-1 payload definitions. No Instance, transport, window or scheduler.
 * RGBA integer low-to-high bytes are R,G,B,A. Rectangles use signed pixel origins.
 * Resource identities/generations are exact opaque numbers, not texture handles. */
#define HRC_NATIVE_VERSION 1u
enum hrc_command_kind { HRC_SOLID=0, HRC_ALPHA_MASK=1, HRC_RGBA=2 };
enum hrc_pixel_format { HRC_ALPHA8=0, HRC_RGBA8=1 };
typedef struct hrc_resource {
    uint64_t resource;
    uint64_t generation;
    uint64_t pixel_count;
    uint64_t stride;
    uint16_t width;
    uint16_t height;
    uint8_t format;
    uint8_t _reserved[3];
} hrc_resource;
typedef struct hrc_removal {
    uint64_t resource;
    uint64_t generation;
} hrc_removal;
typedef struct hrc_command {
    uint64_t resource;
    uint64_t generation;
    uint32_t color_rgba;
    int32_t destination_x;
    int32_t destination_y;
    int32_t clip_x;
    int32_t clip_y;
    uint16_t destination_width;
    uint16_t destination_height;
    uint16_t clip_width;
    uint16_t clip_height;
    uint16_t source_x;
    uint16_t source_y;
    uint16_t source_width;
    uint16_t source_height;
    uint16_t resource_width;
    uint16_t resource_height;
    uint8_t tag;
    uint8_t format;
    uint8_t cursor_component;
    uint8_t _reserved;
} hrc_command;
/* One upload borrows exact immutable pixels from its owning frame lease.
 * The pointer is invalid after lease release; no copying is required for synchronous upload. */
typedef struct hrc_upload {
    hrc_resource info;
    const uint8_t *pixels;
    size_t pixel_len;
} hrc_upload;
typedef struct hrc_residency {
    uint64_t resource, generation;
    uint16_t width, height;
    uint8_t format;
    uint8_t _reserved[3];
} hrc_residency;

/* Optional additive version-1 owner contract. Forward-declared VT-owned source
 * capability; no terminal layout or Instance dependency enters this header. */
struct hvt_observation;
typedef struct hrc_renderer hrc_renderer;
typedef struct hrc_frame_buffer hrc_frame_buffer;
enum hrc_status {
    HRC_OK=0, HRC_INVALID_ARGUMENT=1, HRC_VERSION_MISMATCH=2,
    HRC_OUT_OF_MEMORY=3, HRC_RESOURCE_LIMIT=4, HRC_BUSY=5,
    HRC_NO_FRAME=6, HRC_SOURCE_CLOSED=7, HRC_OPERATION_FAILED=8
};
#define HRC_MAX_FONT_FALLBACKS 24u
#define HRC_MAX_FONT_PATH_BYTES 4096u
#define HRC_MAX_FONT_BYTES (32u * 1024u * 1024u)
#define HRC_MAX_FONT_SET_BYTES (64u * 1024u * 1024u)
#define HRC_MAX_CONFIG_ITEMS 1048576u
#define HRC_MAX_SHAPED 65536u
#define HRC_MAX_RASTER_BYTES (16u * 1024u * 1024u)
#define HRC_MAX_ROWS 192u
#define HRC_MAX_COLUMNS 512u
#define HRC_MAX_FRAME_COMMANDS 114689u
#define HRC_MAX_FRAME_PIXEL_BYTES (80u * 1024u * 1024u)
#define HRC_MAX_FRAME_BUFFERS 64u
#define HRC_MAX_RESIDENCIES 9u
enum hrc_font_kind { HRC_FONT_NONE=0, HRC_FONT_PATH=1, HRC_FONT_MEMORY=2 };
enum hrc_font_variant { HRC_FONT_REGULAR=0, HRC_FONT_ITALIC=1, HRC_FONT_BOLD=2, HRC_FONT_BOLD_ITALIC=3 };
typedef struct hrc_bytes { const uint8_t *data; size_t len; } hrc_bytes;
typedef struct hrc_font_source {
    uint8_t kind, reserved[7];
    hrc_bytes primary;
    const hrc_bytes *fallbacks;
    size_t fallback_count;
} hrc_font_source;
typedef struct hrc_config {
    hrc_font_source fonts[4];
    uint16_t pixel_size, reserved;
    uint32_t max_sequence_scalars;
    size_t shape_entries, shape_scalars, shape_glyphs;
    size_t shaped_capacity, raster_bytes;
    float stroke_points[4];
    uint32_t dpi_x_numerator, dpi_x_denominator, dpi_y_numerator, dpi_y_denominator;
    uint16_t atlas_width, atlas_height, atlas_gap, reserved2;
    size_t atlas_entries, command_capacity, command_limit;
    size_t frame_pixel_limit;
    uint32_t frame_buffer_limit, reserved3;
} hrc_config;
typedef struct hrc_cell_size {
    uint16_t width, height;
    uint32_t reserved;
} hrc_cell_size;
typedef struct hrc_frame_info {
    /* content_revision identifies reusable drawing and may stay unchanged across newer terminal cuts. */
    uint64_t revision, content_revision, terminal_revision;
    uint32_t command_count, content_command_count, upload_count, removal_count;
    uint32_t history_offset, history_count, history_row_base, background_rgba;
    uint16_t surface_width, surface_height, cell_width, cell_height;
    uint8_t alternate_screen, reserved[7];
} hrc_frame_info;
/* All arrays/pixels borrow exactly the read lease on this frame buffer.
 * Counts come from info. Empty arrays may have NULL pointers. */
typedef struct hrc_frame_view {
    hrc_frame_info info;
    const hrc_command *commands;
    const hrc_upload *uploads;
    const hrc_removal *removals;
} hrc_frame_view;

#ifdef __cplusplus
extern "C" {
#endif
uint32_t hrc_abi_version(void);
/* One producer serializes owner/open/capture/close/destruction.
 * All valid/aligned fixed outputs, slots, records and input ranges are disjoint.
 * Fixed outputs are zeroed before later validation. Constructors require null
 * slots, preserve non-null slots on rejection, and publish only complete owners.
 *
 * Source is a retained VT-owned read capability, never a mutable terminal.
 * Construction binds to this source occurrence permanently and retains one
 * reference. Caller may release its source reference immediately after success.
 * Closed source rejects construction before font access; capture later reports
 * SOURCE_CLOSED after source-owner destruction. Copied frames remain readable.
 * Source open/mutation/destruction, Render construction and capture serialize.
 *
 * All reserved inputs are zero. Regular font required; optional NONE variants
 * have every other field zero. Sources borrow this call only; Text owns copied
 * paths/memory on success. Paths are nonempty/NUL-free/bounded; memory limits
 * apply individually and per style, fallbacks<=MAX_FONT_FALLBACKS. All styles use
 * the same positive pixel_size and compatible canonical metrics/fallback rules.
 * No discovery, point sizing, reconfiguration or shared font Store.
 *
 * Shape item/atlas-entry capacities are positive<=MAX_CONFIG_ITEMS. Sequence
 * and shaped scratch are positive<=MAX_SHAPED; sequence<=shape_scalars.
 * Raster is positive<=MAX_RASTER_BYTES. Atlas dimensions nonzero, area<=RASTER.
 * Canonical finite stroke/positive normalized DPI rules apply.
 * Command initial/limit positive, initial<=limit<=MAX_FRAME_COMMANDS.
 * Frame pixel limit is >=atlas area and <=MAX_FRAME_PIXEL_BYTES.
 * Buffer limit is 1..MAX_FRAME_BUFFERS. Frame memory grows lazily within limits.
 * Renderer/font creation is canonical; no VT/process geometry is changed. */
uint32_t hrc_create(uint32_t version, const hrc_config *,
                    struct hvt_observation *source, hrc_renderer **out);
/* Busy while any frame buffer is open, even between read leases. Busy preserves
 * the slot/owner. Otherwise destroys Renderer before its private FontSets and
 * ends its resource namespace. NULL slot/value are successful no-ops. */
uint32_t hrc_try_destroy(hrc_renderer **owner);
uint32_t hrc_get_cell_size(const hrc_renderer *, hrc_cell_size *out);

/* Opening pins the parent resource namespace. Storage is separate from other
 * buffers and reused after lease release. Count ceiling never evicts old buffers. */
uint32_t hrc_frame_open(uint32_t version, hrc_renderer *, hrc_frame_buffer **out);
/* Producer only, after backend handoff has returned. Busy if still leased.
 * NULL slot/value are successful no-ops; successful close clears the slot and
 * drops the parent borrow as its final parent access. Never race close/use. */
uint32_t hrc_frame_try_close(hrc_frame_buffer **buffer);
/* Producer captures into an available buffer, then publishes one read lease.
 * Leased target returns BUSY without mutation. Output info is pre-zeroed.
 * Source view clamps history_offset canonically. Rows<=MAX_ROWS, columns<=
 * MAX_COLUMNS and nonzero presentation pixel extents fit u16. Source pixels
 * retain canonical presentation scaling; capture never resizes the source.
 *
 * Residency is caller truth for this exact live renderer namespace: <=8,
 * pointer/count paired (NULL permitted only when count=0), valid addresses,
 * known formats, nonzero identities/generations/extents, reserved=0 and no
 * duplicate logical identities. Do not mix another owner or a prior destroyed
 * owner's resources. Matching exact occurrences suppress uploads. Missing or
 * failed uploads must remain absent in the next supplied residency.
 * CPU immutability does not retain GPU resources: preserve referenced residency
 * until application, or discard/recapture against actual state. Release is no
 * GPU fence. Empty residency requests all required upload bytes.
 *
 * Full commands, source RGBA, atlas pixels and native records are copied before
 * success. Upload/removal differences are residency-relative. Capture success
 * acknowledges no GPU work. No VT borrow/slice survives capture.
 *
 * Failure publishes no lease and keeps info zero. Other leased buffers remain
 * byte-identical. Private Renderer caches/bindings/capacity/revisions may already
 * have changed; no rollback/replay/reset promise. Available target may lose its
 * old unleased contents, retaining bounded reusable storage. Read returns
 * NO_FRAME until a later successful capture. Retry re-observes caller truth.
 * No clocks, threads, queues, backend, handoff or scheduling are supplied. */
uint32_t hrc_frame_capture(hrc_frame_buffer *, uint32_t history_offset,
                           const hrc_residency *, size_t residency_count,
                           hrc_frame_info *out);
/* Backend reads only a successfully captured, still-leased buffer. Immutable
 * arrays/pixels remain valid through newer captures in OTHER buffers, source
 * mutation/destruction and busy parent destruction, until this lease releases.
 * Do not read concurrently with release or reuse. No source access occurs. */
uint32_t hrc_frame_read(const hrc_frame_buffer *, hrc_frame_view *out);
/* Ends this lease; no residency acknowledgement. NO_FRAME if not leased.
 * After calling release, use no old array/pixel pointers. Release publishes
 * availability as its last buffer access; producer may then capture again. */
uint32_t hrc_frame_release(hrc_frame_buffer *);
#ifdef __cplusplus
}
#endif
#endif
