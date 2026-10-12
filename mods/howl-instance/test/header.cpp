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

static_assert(sizeof(hi_frame_info) == 88);
static_assert(offsetof(hi_frame_info, command_count) == 40);
static_assert(offsetof(hi_frame_info, surface_width) == 72);
static_assert(sizeof(hrc_command) == 64 && sizeof(hrc_resource) == 40);
static_assert(offsetof(hrc_command, tag) == 56);
static_assert(sizeof(hrc_residency) == 24);

static_assert(sizeof(hrc_upload) == 56);
static_assert(offsetof(hrc_upload, pixels) == 40 && offsetof(hrc_upload, pixel_len) == 48);
static_assert(offsetof(hi_frame_info, sequence) == 0);
static_assert(offsetof(hi_frame_info, presentation_generation) == 8);
static_assert(offsetof(hi_frame_info, revision) == 16);
static_assert(offsetof(hi_frame_info, content_revision) == 24);
static_assert(offsetof(hi_frame_info, terminal_revision) == 32);
static_assert(offsetof(hi_frame_info, content_command_count) == 44);
static_assert(offsetof(hi_frame_info, upload_count) == 48);
static_assert(offsetof(hi_frame_info, removal_count) == 52);
static_assert(offsetof(hi_frame_info, history_offset) == 56);
static_assert(offsetof(hi_frame_info, history_count) == 60);
static_assert(offsetof(hi_frame_info, history_row_base) == 64);
static_assert(offsetof(hi_frame_info, background_rgba) == 68);
static_assert(offsetof(hi_frame_info, surface_height) == 74);
static_assert(offsetof(hi_frame_info, cell_width) == 76);
static_assert(offsetof(hi_frame_info, cell_height) == 78);
static_assert(offsetof(hi_frame_info, alternate_screen) == 80);
static_assert(offsetof(hi_frame_info, reserved) == 81);
