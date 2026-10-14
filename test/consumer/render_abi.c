#include "howl_instance_native.h"
#include "howl_render_native.h"
#include <string.h>
#define REQUIRE(x) do { if (!(x)) return __LINE__; } while (0)
int howl_external_render_abi(const uint8_t *font,size_t font_len) {
    /* Resolve an actual headless C Instance through its owned source capability.
     * Render itself depends only on VT and Text; this composition lives here. */
    hi_instance *instance=0;
    const char shell[]="/bin/sh", command[]="exit 0";
    hi_launch launch={{(const uint8_t *)shell,sizeof(shell)-1},
        {(const uint8_t *)command,sizeof(command)-1},{0,0},0,0,3,12,8,0,8,16};
    REQUIRE(hi_create(HI_ABI_VERSION,&launch,&instance)==HI_OK);
    hvt_observation *source=0;
    REQUIRE(hi_observation_open(HI_ABI_VERSION,instance,&source)==HI_OK);
    hrc_config c={0};
    c.fonts[0].kind=HRC_FONT_PATH; c.fonts[0].primary=(hrc_bytes){font,font_len};
    c.pixel_size=18; c.max_sequence_scalars=16;
    c.shape_entries=256; c.shape_scalars=1024; c.shape_glyphs=1024;
    c.shaped_capacity=1024; c.raster_bytes=65536;
    c.stroke_points[0]=0.001f; c.stroke_points[1]=1; c.stroke_points[2]=1.5f; c.stroke_points[3]=2;
    c.dpi_x_numerator=96; c.dpi_y_numerator=96; c.dpi_x_denominator=1; c.dpi_y_denominator=1;
    c.atlas_width=256; c.atlas_height=256; c.atlas_entries=256;
    c.command_capacity=4; c.command_limit=4096; c.frame_pixel_limit=131072; c.frame_buffer_limit=2;
    hrc_renderer *renderer=0;
    REQUIRE(hrc_create(HRC_NATIVE_VERSION,&c,source,&renderer)==HRC_OK);
    REQUIRE(hvt_observation_release(&source)==HVT_OK && !source);
    hrc_frame_buffer *frame=0,*other=0;
    REQUIRE(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&frame)==HRC_OK);
    REQUIRE(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&other)==HRC_OK);
    hrc_frame_info info;
    REQUIRE(hrc_frame_capture(frame,0,0,0,&info)==HRC_OK);
    hrc_frame_view first,after;
    REQUIRE(hrc_frame_read(frame,&first)==HRC_OK);
    REQUIRE(hi_destroy(&instance)==HI_OK && !instance);
    REQUIRE(hrc_frame_capture(other,0,0,0,&info)==HRC_SOURCE_CLOSED);
    REQUIRE(hrc_frame_read(frame,&after)==HRC_OK);
    REQUIRE(!memcmp(&first.info,&after.info,sizeof(first.info)));
    REQUIRE(first.commands==after.commands && first.uploads==after.uploads);
    REQUIRE(hrc_try_destroy(&renderer)==HRC_BUSY && renderer);
    REQUIRE(hrc_frame_release(frame)==HRC_OK);
    REQUIRE(hrc_frame_try_close(&frame)==HRC_OK && !frame);
    REQUIRE(hrc_frame_try_close(&other)==HRC_OK && !other);
    REQUIRE(hrc_try_destroy(&renderer)==HRC_OK && !renderer);
    return 0;
}
