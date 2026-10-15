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

static_assert(sizeof(hvt_search_match) == 32 && offsetof(hvt_search_match, scanned_snapshots) == 24);
static_assert(sizeof(hvt_selection_range) == 20 && offsetof(hvt_selection_range, _reserved) == 16);
static_assert(sizeof(hvt_interaction) == 16 && offsetof(hvt_interaction, mouse_tracking) == 12);
static_assert(sizeof(hvt_row_shape) == 4);

static_assert(sizeof(hvt_request) == 56 && offsetof(hvt_request, data) == 24);
static_assert(sizeof(hvt_request_data) == 32);
static_assert(offsetof(hvt_request, payload_len) == 16 && offsetof(hvt_request, kind) == 20);
static_assert(sizeof(hvt_request_container) == 28 && sizeof(hvt_request_pointer) == 16);

static_assert(offsetof(hvt_request_clipboard, operation) == 0 && offsetof(hvt_request_clipboard, selection_len) == 4);
static_assert(offsetof(hvt_request_drag, operation) == 4 && offsetof(hvt_request_drag, kind) == 12);
static_assert(offsetof(hvt_request_drag, has_client_id) == 16 && offsetof(hvt_request_drag, has_index) == 18);

/* Linux/x86_64 version-1 presentation records, including reserved fields. */
static_assert(sizeof(hi_font_source) == 40);
static_assert(alignof(hi_font_source) == 8);
static_assert(offsetof(hi_font_source, kind) == 0);
static_assert(offsetof(hi_font_source, reserved) == 1);
static_assert(offsetof(hi_font_source, primary) == 8);
static_assert(offsetof(hi_font_source, fallbacks) == 24);
static_assert(offsetof(hi_font_source, fallback_count) == 32);
static_assert(sizeof(hi_presentation_config) == 208);
static_assert(alignof(hi_presentation_config) == 8);
static_assert(offsetof(hi_presentation_config, fonts) == 0);
static_assert(offsetof(hi_presentation_config, pixel_size) == 160);
static_assert(offsetof(hi_presentation_config, reserved) == 162);
static_assert(offsetof(hi_presentation_config, max_sequence_scalars) == 164);
static_assert(offsetof(hi_presentation_config, shape_entries) == 168);
static_assert(offsetof(hi_presentation_config, shape_scalars) == 176);
static_assert(offsetof(hi_presentation_config, shape_glyphs) == 184);
static_assert(offsetof(hi_presentation_config, shaped_capacity) == 192);
static_assert(offsetof(hi_presentation_config, raster_bytes) == 200);
static_assert(sizeof(hi_cell_size) == 8);
static_assert(alignof(hi_cell_size) == 4);
static_assert(offsetof(hi_cell_size, width) == 0);
static_assert(offsetof(hi_cell_size, height) == 2);
static_assert(offsetof(hi_cell_size, reserved) == 4);
static_assert(sizeof(hi_presented_config) == 80);
static_assert(alignof(hi_presented_config) == 8);
static_assert(offsetof(hi_presented_config, stroke_points) == 0);
static_assert(offsetof(hi_presented_config, dpi_x_numerator) == 16);
static_assert(offsetof(hi_presented_config, dpi_x_denominator) == 20);
static_assert(offsetof(hi_presented_config, dpi_y_numerator) == 24);
static_assert(offsetof(hi_presented_config, dpi_y_denominator) == 28);
static_assert(offsetof(hi_presented_config, atlas_width) == 32);
static_assert(offsetof(hi_presented_config, atlas_height) == 34);
static_assert(offsetof(hi_presented_config, atlas_gap) == 36);
static_assert(offsetof(hi_presented_config, incremental_rows) == 38);
static_assert(offsetof(hi_presented_config, atlas_entries) == 40);
static_assert(offsetof(hi_presented_config, command_capacity) == 48);
static_assert(offsetof(hi_presented_config, command_limit) == 56);
static_assert(offsetof(hi_presented_config, incremental_commands) == 64);
static_assert(offsetof(hi_presented_config, reserved) == 72);

using hi_observation_signature = uint32_t(*)(uint32_t,hi_instance *,hvt_observation **);
static_assert(__is_same(decltype(&hi_observation_open),hi_observation_signature));
static_assert(HVT_MAX_OBSERVATION_REFERENCES==1024);

static_assert(sizeof(hvt_graphics)==56 && offsetof(hvt_graphics,image_count)==24);
static_assert(sizeof(hvt_image)==24 && sizeof(hvt_image_placement)==56);
template<typename A,typename B> constexpr bool graphics_same_type=false;
template<typename A> constexpr bool graphics_same_type<A,A> = true;
static_assert(graphics_same_type<decltype(&hi_copy_graphics),uint32_t(*)(const hi_instance *,uint32_t,hvt_image *,size_t,hvt_image_placement *,size_t,hvt_graphics *)>);
static_assert(graphics_same_type<decltype(&hi_copy_image_pixels),uint32_t(*)(const hi_instance *,uint64_t,uint32_t,uint64_t,uint8_t *,size_t,size_t *)>);

static_assert(graphics_same_type<decltype(&hi_output_open),uint32_t(*)(uint32_t,const hi_instance *,uint64_t,uint16_t,size_t,hvt_output **)>);
static_assert(sizeof(hvt_output_view)==96 && sizeof(hvt_output_loss)==24);
