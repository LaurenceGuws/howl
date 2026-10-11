#include "howl_server_client.h"

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
    return interrupt == NULL ? 0 : 6;
}
