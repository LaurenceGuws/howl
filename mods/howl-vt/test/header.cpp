#include "howl_vt_native.h"
template<typename A,typename B> constexpr bool same_type=false;
template<typename A> constexpr bool same_type<A,A> = true;
static_assert(sizeof(hvt_config)==16 && alignof(hvt_config)==4);
static_assert(offsetof(hvt_config,rows)==0);
static_assert(offsetof(hvt_config,columns)==2);
static_assert(offsetof(hvt_config,history_rows)==4);
static_assert(offsetof(hvt_config,reserved)==6);
static_assert(offsetof(hvt_config,cell_width)==8);
static_assert(offsetof(hvt_config,cell_height)==12);
static_assert(sizeof(hvt_state)==48 && alignof(hvt_state)==8);
static_assert(offsetof(hvt_state,terminal_revision)==0);
static_assert(offsetof(hvt_state,content_revision)==8);
static_assert(offsetof(hvt_state,history_row_base)==16);
static_assert(offsetof(hvt_state,history_count)==20);
static_assert(offsetof(hvt_state,history_offset)==24);
static_assert(offsetof(hvt_state,cell_width)==28);
static_assert(offsetof(hvt_state,cell_height)==32);
static_assert(offsetof(hvt_state,rows)==36);
static_assert(offsetof(hvt_state,columns)==38);
static_assert(offsetof(hvt_state,cursor_row)==40);
static_assert(offsetof(hvt_state,cursor_column)==42);
static_assert(offsetof(hvt_state,alternate_screen)==44);
static_assert(offsetof(hvt_state,cursor_visible)==45);
static_assert(offsetof(hvt_state,synchronized_output)==46);
static_assert(offsetof(hvt_state,reserved)==47);
static_assert(sizeof(hvt_feed_progress)==32 && alignof(hvt_feed_progress)==8);
static_assert(offsetof(hvt_feed_progress,terminal_revision)==0);
static_assert(offsetof(hvt_feed_progress,content_revision)==8);
static_assert(offsetof(hvt_feed_progress,consumed)==16);
static_assert(offsetof(hvt_feed_progress,mutations)==24);
static_assert(offsetof(hvt_feed_progress,synchronized_ended)==28);
static_assert(offsetof(hvt_feed_progress,trailing_effect)==29);
static_assert(offsetof(hvt_feed_progress,held)==30);
static_assert(offsetof(hvt_feed_progress,reserved)==31);
static_assert(sizeof(hvt_animation)==8 && alignof(hvt_animation)==4);
static_assert(offsetof(hvt_animation,next_ms)==0);
static_assert(offsetof(hvt_animation,changed)==4);
static_assert(offsetof(hvt_animation,deadline_present)==5);
static_assert(offsetof(hvt_animation,reserved)==6);
static_assert(HVT_NATIVE_VERSION==1);
static_assert(HVT_MAX_SCREEN_CELLS==1048576);
static_assert(HVT_MAX_INPUT_BYTES==65536);
static_assert(HVT_INPUT_BUFFER_BYTES==512);
static_assert(HVT_PASTE_EXTRA_BYTES==12);
static_assert(HVT_MAX_COPY_BYTES==1048576);
static_assert(HVT_OK==0);
static_assert(HVT_INVALID_ARGUMENT==1);
static_assert(HVT_VERSION_MISMATCH==2);
static_assert(HVT_OUT_OF_MEMORY==3);
static_assert(HVT_RESOURCE_LIMIT==4);
static_assert(HVT_BUFFER_TOO_SMALL==5);
static_assert(HVT_STALE_REQUEST==6);
static_assert(HVT_REPLY_REQUIRED==7);
static_assert(HVT_CONTEXT_CHANGED==8);
static_assert(HVT_REQUEST_MISMATCH==9);
static_assert(HVT_INTERNAL==10);
static_assert(HVT_MUTATION_CURSOR==1);
static_assert(HVT_MUTATION_TEXT==2);
static_assert(HVT_MUTATION_VIEWPORT==4);
static_assert(HVT_MUTATION_IMAGES==8);
static_assert(HVT_MUTATION_MODE==16);
static_assert(HVT_MUTATION_TITLE==32);
static_assert(HVT_MUTATION_ICON==64);
static_assert(HVT_MUTATION_HISTORY_LOSS==128);
extern "C" {
uint32_t expected_hvt_abi_version(void);
uint32_t expected_hvt_create(uint32_t version, const hvt_config *, hvt_terminal **out);
void expected_hvt_release(hvt_terminal **);
uint32_t expected_hvt_observe(const hvt_terminal *, uint32_t history_offset, hvt_state *);
uint32_t expected_hvt_feed(hvt_terminal *, const uint8_t *, size_t length,
    uint64_t timestamp_ns, hvt_feed_progress *);
uint32_t expected_hvt_resize(hvt_terminal *, uint16_t rows, uint16_t columns,
    uint32_t cell_width, uint32_t cell_height);
uint32_t expected_hvt_reset(hvt_terminal *);
uint32_t expected_hvt_service_animations(hvt_terminal *, uint64_t timestamp_ns, hvt_animation *);
uint32_t expected_hvt_encode_named_key(hvt_terminal *, uint8_t key, uint8_t action, uint8_t mods,
    uint8_t *out, size_t capacity, size_t *written);
uint32_t expected_hvt_encode_unicode_key(hvt_terminal *, uint32_t scalar, uint8_t action, uint8_t mods,
    uint8_t *out, size_t capacity, size_t *written);
uint32_t expected_hvt_encode_mouse(hvt_terminal *, uint8_t kind, uint8_t button, uint8_t mods,
    uint8_t buttons_down, int32_t row, uint16_t column, uint8_t pixels_present,
    uint32_t pixel_x, uint32_t pixel_y, uint8_t *out, size_t capacity, size_t *written);
uint32_t expected_hvt_encode_focus(hvt_terminal *, uint8_t focus, uint8_t *out,
    size_t capacity, size_t *written);
uint32_t expected_hvt_encode_paste(hvt_terminal *, const uint8_t *, size_t length,
    uint8_t *out, size_t capacity, size_t *written);
uint32_t expected_hvt_copy_replies(const hvt_terminal *, uint8_t *, size_t capacity, size_t *required);
uint32_t expected_hvt_consume_replies(hvt_terminal *, size_t count);
uint32_t expected_hvt_copy_cell(const hvt_terminal *, uint32_t history_offset,
    uint16_t row, uint16_t column, hvt_cell *);
uint32_t expected_hvt_search(const hvt_terminal *, const uint8_t *, size_t length,
    uint8_t reverse, uint8_t origin_present, int32_t row, uint16_t column, hvt_search_match *);
uint32_t expected_hvt_expand_selection(const hvt_terminal *, uint8_t kind, uint32_t history_offset,
    int32_t row, uint16_t column, uint16_t expected_columns, uint8_t alternate, hvt_selection_range *);
uint32_t expected_hvt_copy_selection(const hvt_terminal *, int32_t start_row, uint16_t start_column,
    int32_t end_row, uint16_t end_column, uint16_t expected_columns, uint8_t alternate,
    uint8_t *, size_t capacity, size_t *written);
uint32_t expected_hvt_copy_hyperlink(const hvt_terminal *, uint32_t history_offset,
    int32_t row, uint16_t column, uint16_t expected_columns, uint8_t alternate,
    uint8_t *, size_t capacity, size_t *required);
uint32_t expected_hvt_copy_row_shapes(const hvt_terminal *, uint32_t history_offset,
    hvt_row_shape *, size_t capacity, size_t *required);
uint32_t expected_hvt_get_interaction(const hvt_terminal *, hvt_interaction *);
uint32_t expected_hvt_request_head(const hvt_terminal *, hvt_request *);
uint32_t expected_hvt_copy_request_payload(const hvt_terminal *, uint64_t id,
    uint8_t *, size_t capacity, size_t *required);
uint32_t expected_hvt_consume_request(hvt_terminal *, uint64_t id);
uint32_t expected_hvt_reply_clipboard(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t expected_hvt_reply_pointer_shape(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t expected_hvt_reply_color_preference(hvt_terminal *, uint64_t id, uint8_t preference);
uint32_t expected_hvt_reply_container_state(hvt_terminal *, uint64_t id, uint8_t state);
uint32_t expected_hvt_reply_container_position(hvt_terminal *, uint64_t id, uint32_t x, uint32_t y);
uint32_t expected_hvt_reply_container_screen_cells(hvt_terminal *, uint64_t id, uint32_t rows, uint32_t columns);
uint32_t expected_hvt_reply_container_icon_title(hvt_terminal *, uint64_t id, const uint8_t *, size_t length);
uint32_t expected_hvt_decline_container(hvt_terminal *, uint64_t id);
}
static_assert(same_type<decltype(&hvt_abi_version),decltype(&expected_hvt_abi_version)>);
static_assert(same_type<decltype(&hvt_create),decltype(&expected_hvt_create)>);
static_assert(same_type<decltype(&hvt_release),decltype(&expected_hvt_release)>);
static_assert(same_type<decltype(&hvt_observe),decltype(&expected_hvt_observe)>);
static_assert(same_type<decltype(&hvt_feed),decltype(&expected_hvt_feed)>);
static_assert(same_type<decltype(&hvt_resize),decltype(&expected_hvt_resize)>);
static_assert(same_type<decltype(&hvt_reset),decltype(&expected_hvt_reset)>);
static_assert(same_type<decltype(&hvt_service_animations),decltype(&expected_hvt_service_animations)>);
static_assert(same_type<decltype(&hvt_encode_named_key),decltype(&expected_hvt_encode_named_key)>);
static_assert(same_type<decltype(&hvt_encode_unicode_key),decltype(&expected_hvt_encode_unicode_key)>);
static_assert(same_type<decltype(&hvt_encode_mouse),decltype(&expected_hvt_encode_mouse)>);
static_assert(same_type<decltype(&hvt_encode_focus),decltype(&expected_hvt_encode_focus)>);
static_assert(same_type<decltype(&hvt_encode_paste),decltype(&expected_hvt_encode_paste)>);
static_assert(same_type<decltype(&hvt_copy_replies),decltype(&expected_hvt_copy_replies)>);
static_assert(same_type<decltype(&hvt_consume_replies),decltype(&expected_hvt_consume_replies)>);
static_assert(same_type<decltype(&hvt_copy_cell),decltype(&expected_hvt_copy_cell)>);
static_assert(same_type<decltype(&hvt_search),decltype(&expected_hvt_search)>);
static_assert(same_type<decltype(&hvt_expand_selection),decltype(&expected_hvt_expand_selection)>);
static_assert(same_type<decltype(&hvt_copy_selection),decltype(&expected_hvt_copy_selection)>);
static_assert(same_type<decltype(&hvt_copy_hyperlink),decltype(&expected_hvt_copy_hyperlink)>);
static_assert(same_type<decltype(&hvt_copy_row_shapes),decltype(&expected_hvt_copy_row_shapes)>);
static_assert(same_type<decltype(&hvt_get_interaction),decltype(&expected_hvt_get_interaction)>);
static_assert(same_type<decltype(&hvt_request_head),decltype(&expected_hvt_request_head)>);
static_assert(same_type<decltype(&hvt_copy_request_payload),decltype(&expected_hvt_copy_request_payload)>);
static_assert(same_type<decltype(&hvt_consume_request),decltype(&expected_hvt_consume_request)>);
static_assert(same_type<decltype(&hvt_reply_clipboard),decltype(&expected_hvt_reply_clipboard)>);
static_assert(same_type<decltype(&hvt_reply_pointer_shape),decltype(&expected_hvt_reply_pointer_shape)>);
static_assert(same_type<decltype(&hvt_reply_color_preference),decltype(&expected_hvt_reply_color_preference)>);
static_assert(same_type<decltype(&hvt_reply_container_state),decltype(&expected_hvt_reply_container_state)>);
static_assert(same_type<decltype(&hvt_reply_container_position),decltype(&expected_hvt_reply_container_position)>);
static_assert(same_type<decltype(&hvt_reply_container_screen_cells),decltype(&expected_hvt_reply_container_screen_cells)>);
static_assert(same_type<decltype(&hvt_reply_container_icon_title),decltype(&expected_hvt_reply_container_icon_title)>);
static_assert(same_type<decltype(&hvt_decline_container),decltype(&expected_hvt_decline_container)>);
extern "C" int hvt_cpp_proof(void) { return hvt_abi_version()==HVT_NATIVE_VERSION ? 0 : 1; }

static_assert(HVT_MAX_OBSERVATION_REFERENCES==1024);
static_assert(same_type<decltype(&hvt_observation_open),uint32_t(*)(uint32_t,hvt_terminal *,hvt_observation **)>);
static_assert(same_type<decltype(&hvt_observation_release),uint32_t(*)(hvt_observation **)>);

static_assert(sizeof(hvt_image)==24 && alignof(hvt_image)==8);
static_assert(offsetof(hvt_image,generation)==0);
static_assert(offsetof(hvt_image,image_id)==8);
static_assert(offsetof(hvt_image,width)==12);
static_assert(offsetof(hvt_image,height)==16);
static_assert(offsetof(hvt_image,byte_count)==20);
static_assert(sizeof(hvt_image_placement)==56 && alignof(hvt_image_placement)==8);
static_assert(offsetof(hvt_image_placement,generation)==0);
static_assert(offsetof(hvt_image_placement,image_id)==8);
static_assert(offsetof(hvt_image_placement,source_x)==12);
static_assert(offsetof(hvt_image_placement,source_y)==16);
static_assert(offsetof(hvt_image_placement,source_width)==20);
static_assert(offsetof(hvt_image_placement,source_height)==24);
static_assert(offsetof(hvt_image_placement,cell_x)==28);
static_assert(offsetof(hvt_image_placement,cell_y)==32);
static_assert(offsetof(hvt_image_placement,pixel_width)==36);
static_assert(offsetof(hvt_image_placement,pixel_height)==40);
static_assert(offsetof(hvt_image_placement,z)==44);
static_assert(offsetof(hvt_image_placement,row)==48);
static_assert(offsetof(hvt_image_placement,column)==50);
static_assert(offsetof(hvt_image_placement,reserved)==52);
static_assert(sizeof(hvt_graphics)==56 && alignof(hvt_graphics)==8);
static_assert(offsetof(hvt_graphics,terminal_revision)==0);
static_assert(offsetof(hvt_graphics,graphics_revision)==8);
static_assert(offsetof(hvt_graphics,content_revision)==16);
static_assert(offsetof(hvt_graphics,image_count)==24);
static_assert(offsetof(hvt_graphics,placement_count)==28);
static_assert(offsetof(hvt_graphics,history_offset)==32);
static_assert(offsetof(hvt_graphics,cell_width)==36);
static_assert(offsetof(hvt_graphics,cell_height)==40);
static_assert(offsetof(hvt_graphics,rows)==44);
static_assert(offsetof(hvt_graphics,columns)==46);
static_assert(offsetof(hvt_graphics,alternate_screen)==48);
static_assert(offsetof(hvt_graphics,reserved)==49);
static_assert(HVT_MAX_IMAGES==256);
static_assert(HVT_MAX_IMAGE_PLACEMENTS==16384);
static_assert(HVT_MAX_IMAGE_DIMENSION==4096);
static_assert(HVT_MAX_IMAGE_BYTES==16777216);
static_assert(HVT_MAX_IMAGE_STORAGE_BYTES==67108864);
static_assert(same_type<decltype(&hvt_copy_graphics),uint32_t(*)(const hvt_terminal *,uint32_t,hvt_image *,size_t,hvt_image_placement *,size_t,hvt_graphics *)>);
static_assert(same_type<decltype(&hvt_copy_image_pixels),uint32_t(*)(const hvt_terminal *,uint64_t,uint32_t,uint64_t,uint8_t *,size_t,size_t *)>);

static_assert(sizeof(hvt_output_loss)==24 && alignof(hvt_output_loss)==8);
static_assert(offsetof(hvt_output_loss,id)==0);
static_assert(offsetof(hvt_output_loss,byte_count)==8);
static_assert(offsetof(hvt_output_loss,reason)==16);
static_assert(offsetof(hvt_output_loss,reserved)==17);
static_assert(sizeof(hvt_output_view)==96 && alignof(hvt_output_view)==8);
static_assert(offsetof(hvt_output_view,text)==0);
static_assert(offsetof(hvt_output_view,text_len)==8);
static_assert(offsetof(hvt_output_view,open_line)==16);
static_assert(offsetof(hvt_output_view,open_line_len)==24);
static_assert(offsetof(hvt_output_view,losses)==32);
static_assert(offsetof(hvt_output_view,loss_count)==40);
static_assert(offsetof(hvt_output_view,terminal_revision)==48);
static_assert(offsetof(hvt_output_view,oldest)==56);
static_assert(offsetof(hvt_output_view,cursor)==64);
static_assert(offsetof(hvt_output_view,newest)==72);
static_assert(offsetof(hvt_output_view,reported_id)==80);
static_assert(offsetof(hvt_output_view,line_count)==88);
static_assert(offsetof(hvt_output_view,kind)==90);
static_assert(offsetof(hvt_output_view,more)==91);
static_assert(offsetof(hvt_output_view,open_line_omitted)==92);
static_assert(offsetof(hvt_output_view,reserved)==93);
static_assert(HVT_OUTPUT_DATA==1);
static_assert(HVT_OUTPUT_CURSOR_STALE==2);
static_assert(HVT_OUTPUT_CURSOR_AHEAD==3);
static_assert(HVT_OUTPUT_LINE_TOO_LONG==4);
static_assert(HVT_OUTPUT_OPEN_LINE_TOO_LONG==5);
static_assert(HVT_OUTPUT_LOSS_LINE_TOO_LONG==1);
static_assert(same_type<decltype(&hvt_output_open),uint32_t(*)(uint32_t,const hvt_terminal *,uint64_t,uint16_t,size_t,hvt_output **)>);
static_assert(same_type<decltype(&hvt_output_read),uint32_t(*)(const hvt_output *,hvt_output_view *)>);
static_assert(same_type<decltype(&hvt_output_release),void(*)(hvt_output **)>);
