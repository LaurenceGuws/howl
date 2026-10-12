#ifndef HOWL_INSTANCE_NATIVE_H
#define HOWL_INSTANCE_NATIVE_H
#include <stddef.h>
#include <stdint.h>
#include "howl_vt_native.h"
#ifdef __cplusplus
extern "C" {
#endif
#define HI_ABI_VERSION 1u
#if HVT_NATIVE_VERSION != 1u
#error "Instance ABI v1 incorporates VT native v1; changing its layout requires Instance ABI review/versioning"
#endif
typedef struct hi_instance hi_instance;
enum hi_status { HI_OK=0, HI_INVALID_ARGUMENT=1, HI_OUT_OF_MEMORY=2, HI_RESOURCE_LIMIT=3, HI_OPERATION_FAILED=4, HI_UNSUPPORTED=5, HI_VERSION_MISMATCH=6 };
enum hi_signal { HI_HANGUP=1, HI_INTERRUPT=2, HI_RESIZE_NOTIFY=3, HI_KILL=9, HI_TERMINATE=15 };
enum hi_signal_result { HI_SIGNAL_DELIVERED=1, HI_SIGNAL_TARGET_MISSING=2, HI_SIGNAL_PERMISSION_DENIED=3, HI_SIGNAL_NATIVE_FAILURE=4 };
typedef struct hi_bytes { const uint8_t *data; size_t len; } hi_bytes;
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
 * No clocks, waits, wake sources, renderer or host queue are owned by this API. */
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
 * Retained host requests and presentation require their later matching contracts. */
uint32_t hi_abi_version(void);
uint32_t hi_create(uint32_t version, const hi_launch *launch, hi_instance **out);
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
uint32_t hi_copy_cell(const hi_instance *, uint32_t history_offset, uint16_t row, uint16_t column, hvt_cell *out);
#ifdef __cplusplus
}
#endif
#endif
