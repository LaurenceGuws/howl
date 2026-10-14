#include "howl_server_client.h"
#include <string.h>

int howl_external_client_abi(void) {
    hsc_control *control = NULL;
    hsc_interrupt *interrupt = NULL;
    if (hsc_abi_version() != HSC_ABI_VERSION) return 1;
    if (hsc_control_open(0, NULL, 0, NULL, &control) != HSC_VERSION_MISMATCH || control != NULL) return 2;
    if (hsc_control_open(HSC_ABI_VERSION, NULL, 1, NULL, &control) != HSC_INVALID_ARGUMENT || control != NULL) return 3;
    if (hsc_interrupt_create(HSC_ABI_VERSION, &interrupt) != HSC_OK || interrupt == NULL) return 4;
    if (hsc_interrupt_cancel(interrupt) != HSC_OK) { hsc_interrupt_release(&interrupt); return 5; }
    hsc_interrupt_release(&interrupt);
    hsc_interrupt_release(&interrupt);
    if (interrupt != NULL) return 6;

    /* Resolve every additive query/cache symbol through the distribution artifact.
     * Live semantics belong to the package's real Server/PTY C proof. */
    hvt_search_match match;
    hvt_selection_range range;
    hsc_selection_span span;
    hsc_changes changes;
    hsc_text_view *text = NULL;
    hsc_cache *cache = NULL;
    hsc_snapshot *snapshot = NULL;
    uint32_t validity = 99;
    size_t required = 99;
    const uint8_t *data = (const uint8_t *)"sentinel";
    memset(&match, 1, sizeof match);
    if (hsc_snapshot_search_row(NULL, NULL, 0, 0, 0, 0, &match) != HSC_INVALID_ARGUMENT || match.found != 0) return 7;
    memset(&match, 1, sizeof match);
    if (hsc_snapshot_search(NULL, NULL, 0, 0, 0, &match) != HSC_INVALID_ARGUMENT || match.found != 0) return 8;
    memset(&range, 1, sizeof range);
    if (hsc_snapshot_expand_selection(NULL, HVT_SELECTION_WORD, 0, 0, &range) != HSC_INVALID_ARGUMENT || range.found != 0) return 9;
    if (hsc_snapshot_selection_validity(NULL, &range, &validity) != HSC_INVALID_ARGUMENT || validity != 0) return 10;
    memset(&span, 1, sizeof span);
    if (hsc_snapshot_selection_span(NULL, &range, 0, &span) != HSC_INVALID_ARGUMENT || span.found != 0) return 11;
    if (hsc_snapshot_row_shapes(NULL, NULL, 0, &required) != HSC_INVALID_ARGUMENT || required != 0) return 12;
    required = 99;
    if (hsc_snapshot_copy_hyperlink(NULL, 0, 0, NULL, 0, &required) != HSC_INVALID_ARGUMENT || required != 0) return 13;
    if (hsc_selection_extract(NULL, &range, &text) != HSC_INVALID_ARGUMENT || text != NULL) return 14;
    required = 99;
    if (hsc_text_view_data(NULL, &data, &required) != HSC_INVALID_ARGUMENT || data != NULL || required != 0) return 15;
    hsc_text_view_release(&text);
    hsc_text_view_release(NULL);
    if (hsc_cache_create(0, NULL, &cache) != HSC_VERSION_MISMATCH || cache != NULL) return 16;
    if (hsc_cache_create(HSC_ABI_VERSION, NULL, &cache) != HSC_INVALID_ARGUMENT || cache != NULL) return 17;
    if (hsc_observe_cached(NULL, NULL, 0, 0, &snapshot) != HSC_INVALID_ARGUMENT || snapshot != NULL) return 18;
    memset(&changes, 1, sizeof changes);
    if (hsc_snapshot_changes(NULL, &changes) != HSC_INVALID_ARGUMENT || changes.flags != 0) return 19;
    required = 99;
    if (hsc_snapshot_changed_rows(NULL, NULL, 0, &required) != HSC_INVALID_ARGUMENT || required != 0) return 20;
    hsc_cache_release(&cache);
    hsc_cache_release(NULL);
    return 0;
}
