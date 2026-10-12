#include "howl_instance_native.h"
static_assert(sizeof(hvt_cell) == 104);
static_assert(sizeof(hi_service) == 32);
static_assert(sizeof(hi_launch) == 4 * sizeof(hi_bytes) + 16);
extern "C" int howl_instance_cpp_header(void) { return hi_abi_version() == HI_ABI_VERSION ? 0 : 1; }
static_assert(alignof(hvt_cell) == alignof(uint32_t));
static_assert(offsetof(hvt_cell, scalar_count) == 96);
static_assert(offsetof(hvt_cell, x) == 99 && offsetof(hvt_cell, y) == 100);
static_assert(offsetof(hi_service, descriptor) == 8);
static_assert(offsetof(hi_service, changed) == 16);
static_assert(offsetof(hi_service, exit_kind) == 22);
static_assert(offsetof(hi_service, sync_trailing_effect) == 25);
static_assert(offsetof(hi_service, reserved) == 28);
static_assert(offsetof(hi_launch, rows) == 4 * sizeof(hi_bytes));
static_assert(offsetof(hi_launch, cell_width) == 4 * sizeof(hi_bytes) + 8);
