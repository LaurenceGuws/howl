#include "howl_instance_native.h"
_Static_assert(sizeof(hvt_cell) == 104, "VT scalar record");
_Static_assert(sizeof(hi_service) == 32, "Instance service record");
_Static_assert(HVT_KEY_ENTER == 1 && HVT_KEY_KEYPAD_ENTER == 58, "native key vocabulary");
int howl_external_instance_abi(void) {
    hi_instance *instance = 0;
    if (hi_abi_version() != HI_ABI_VERSION) return 1;
    if (hi_create(99, 0, &instance) != HI_VERSION_MISMATCH || instance) return 2;
    if (hi_send_named_key(0, HVT_KEY_ENTER, HVT_PRESS, 0) != HI_INVALID_ARGUMENT) return 3;
    if (hi_destroy(&instance) != HI_OK || instance) return 4;
    return 0;
}
_Static_assert(_Alignof(hvt_cell) == _Alignof(uint32_t), "VT cell alignment");
_Static_assert(offsetof(hvt_cell, scalar_count) == 96, "VT scalar count offset");
_Static_assert(offsetof(hvt_cell, x) == 99 && offsetof(hvt_cell, y) == 100, "VT lead offsets");
_Static_assert(offsetof(hi_service, descriptor) == 8 && offsetof(hi_service, changed) == 16, "service header");
_Static_assert(offsetof(hi_service, sync_trailing_effect) == 25, "service sync facts");
_Static_assert(offsetof(hi_service, reserved) == 28, "service initialized tail");
_Static_assert(sizeof(hi_launch) == 4 * sizeof(hi_bytes) + 16, "launch layout");
_Static_assert(offsetof(hi_launch, rows) == 4 * sizeof(hi_bytes), "launch dimensions");
