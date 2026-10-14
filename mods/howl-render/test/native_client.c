#include "howl_render_native.h"
#include "howl_vt_native.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"Render C proof line %d: %s\n",__LINE__,#x); return 1; } } while (0)
_Static_assert(sizeof(hrc_config)==288 && sizeof(hrc_frame_info)==72 && sizeof(hrc_frame_view)==96,"owner layouts");
_Static_assert(sizeof(hrc_command)==64 && sizeof(hrc_resource)==40 && sizeof(hrc_upload)==56 && sizeof(hrc_removal)==16 && sizeof(hrc_residency)==24,"payload layouts");
extern int howl_render_cpp(void);
static hrc_config config(const uint8_t *path,size_t len) {
    hrc_config c={0};
    c.fonts[0].kind=HRC_FONT_PATH; c.fonts[0].primary=(hrc_bytes){path,len};
    c.pixel_size=18; c.max_sequence_scalars=16;
    c.shape_entries=256; c.shape_scalars=1024; c.shape_glyphs=1024;
    c.shaped_capacity=1024; c.raster_bytes=65536;
    c.stroke_points[0]=0.001f; c.stroke_points[1]=1; c.stroke_points[2]=1.5f; c.stroke_points[3]=2;
    c.dpi_x_numerator=96; c.dpi_y_numerator=96; c.dpi_x_denominator=1; c.dpi_y_denominator=1;
    c.atlas_width=256; c.atlas_height=256; c.atlas_gap=1; c.atlas_entries=256;
    c.command_capacity=4; c.command_limit=4096; c.frame_pixel_limit=131072; c.frame_buffer_limit=2;
    return c;
}
static int zero(const void *p,size_t n) {
    const uint8_t *v=p;
    for (size_t i=0;i<n;++i) if (v[i]) return 0;
    return 1;
}
static uint64_t hash(const hrc_frame_view *v) {
    uint64_t h=UINT64_C(1469598103934665603);
    const uint8_t *p=(const uint8_t *)&v->info;
    for (size_t i=0;i<sizeof(v->info);++i) { h^=p[i]; h*=UINT64_C(1099511628211); }
    p=(const uint8_t *)v->commands;
    for (size_t i=0;i<v->info.command_count*sizeof(*v->commands);++i) { h^=p[i]; h*=UINT64_C(1099511628211); }
    for (size_t i=0;i<v->info.upload_count;++i) {
        const hrc_upload *u=&v->uploads[i];
        p=(const uint8_t *)&u->info;
        for (size_t j=0;j<sizeof(u->info);++j) { h^=p[j]; h*=UINT64_C(1099511628211); }
        for (size_t j=0;j<u->pixel_len;++j) { h^=u->pixels[j]; h*=UINT64_C(1099511628211); }
    }
    return h;
}
static int exercise(const char *path,int memory) {
    hvt_terminal *vt=0; hvt_observation *source=0;
    hrc_renderer *renderer=0; hrc_frame_buffer *a=0,*b=0,*extra=0;
    hvt_config cfg={3,12,8,0,8,16};
    CHECK(hvt_create(HVT_NATIVE_VERSION,&cfg,&vt)==HVT_OK);
    CHECK(hvt_observation_open(HVT_NATIVE_VERSION,vt,&source)==HVT_OK);
    const size_t path_len=strlen(path);
    CHECK(path_len && path_len<=HRC_MAX_FONT_PATH_BYTES);
    uint8_t *caller_path=malloc(path_len); CHECK(caller_path);
    memcpy(caller_path,path,path_len);
    hrc_config c=config(caller_path,path_len);
    uint8_t *font=0;
    if (memory) {
        FILE *f=fopen(path,"rb"); CHECK(f);
        CHECK(fseek(f,0,SEEK_END)==0); long n=ftell(f); CHECK(n>0);
        CHECK(fseek(f,0,SEEK_SET)==0); font=malloc((size_t)n); CHECK(font);
        CHECK(fread(font,1,(size_t)n,f)==(size_t)n); CHECK(fclose(f)==0);
        for (unsigned i=0;i<4;++i) { c.fonts[i].kind=HRC_FONT_MEMORY; c.fonts[i].primary=(hrc_bytes){font,(size_t)n}; }
    }
    CHECK(hrc_create(99,&c,source,&renderer)==HRC_VERSION_MISMATCH && !renderer);
    CHECK(hrc_create(HRC_NATIVE_VERSION,&c,source,&renderer)==HRC_OK && renderer);
    CHECK(hrc_create(HRC_NATIVE_VERSION,&c,source,&renderer)==HRC_INVALID_ARGUMENT && renderer);
    memset(caller_path,0,path_len); free(caller_path);
    if (font) { memset(font,0,c.fonts[0].primary.len); free(font); }
    CHECK(hvt_observation_release(&source)==HVT_OK && !source);
    hrc_cell_size cell; memset(&cell,0xa5,sizeof(cell));
    CHECK(hrc_get_cell_size(0,&cell)==HRC_INVALID_ARGUMENT && zero(&cell,sizeof(cell)));
    CHECK(hrc_get_cell_size(renderer,&cell)==HRC_OK && cell.width && cell.height && !cell.reserved);
    CHECK(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&a)==HRC_OK);
    CHECK(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&b)==HRC_OK);
    CHECK(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&extra)==HRC_RESOURCE_LIMIT && !extra);
    CHECK(hrc_frame_open(HRC_NATIVE_VERSION,renderer,&a)==HRC_INVALID_ARGUMENT && a);
    CHECK(hrc_try_destroy(&renderer)==HRC_BUSY && renderer);
    hrc_frame_info info; hrc_frame_view view;
    memset(&view,0xa5,sizeof(view));
    CHECK(hrc_frame_read(a,&view)==HRC_NO_FRAME && zero(&view,sizeof(view)));
    CHECK(hrc_frame_release(a)==HRC_NO_FRAME);
    memset(&info,0xa5,sizeof(info));
    CHECK(hrc_frame_capture(a,0,0,1,&info)==HRC_INVALID_ARGUMENT && zero(&info,sizeof(info)));
    CHECK(hrc_frame_capture(a,0,0,HRC_MAX_RESIDENCIES+1,&info)==HRC_RESOURCE_LIMIT && zero(&info,sizeof(info)));
    CHECK(hrc_frame_capture(a,0,(const hrc_residency *)(UINTPTR_MAX-7),1,&info)==HRC_INVALID_ARGUMENT && zero(&info,sizeof(info)));
    const char bytes[]="A\xcc\x81\xe7\x95\x8c\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\x1b\\";
    size_t at=0;
    while (at<sizeof(bytes)-1) {
        hvt_feed_progress progress;
        CHECK(hvt_feed(vt,(const uint8_t *)bytes+at,sizeof(bytes)-1-at,17,&progress)==HVT_OK && progress.consumed);
        at+=progress.consumed;
    }
    CHECK(hrc_frame_capture(a,0,0,0,&info)==HRC_OK);
    CHECK(info.upload_count==2 && info.command_count && info.surface_width==12*cell.width);
    CHECK(hrc_frame_read(a,&view)==HRC_OK && !memcmp(&info,&view.info,sizeof(info)));
    uint64_t before=hash(&view);
    CHECK(hrc_frame_capture(a,0,0,0,&info)==HRC_BUSY && zero(&info,sizeof(info)));
    CHECK(hrc_frame_try_close(&a)==HRC_BUSY && a);
    hrc_residency truth[8]={{0}};
    for (size_t i=0;i<view.info.upload_count;++i) {
        hrc_resource r=view.uploads[i].info;
        truth[i]=(hrc_residency){r.resource,r.generation,r.width,r.height,r.format,{0}};
        CHECK(view.uploads[i].pixel_len==r.pixel_count && view.uploads[i].pixels);
    }
    CHECK(hrc_frame_capture(b,0,truth,view.info.upload_count,&info)==HRC_OK && !info.upload_count);
    CHECK(hrc_frame_release(b)==HRC_OK);
    hrc_residency bad=truth[0]; bad._reserved[0]=1;
    CHECK(hrc_frame_capture(b,0,&bad,1,&info)==HRC_INVALID_ARGUMENT && zero(&info,sizeof(info)));
    bad=truth[0]; bad.format=99;
    CHECK(hrc_frame_capture(b,0,&bad,1,&info)==HRC_INVALID_ARGUMENT && zero(&info,sizeof(info)));
    bad=truth[0]; bad.resource=0;
    CHECK(hrc_frame_capture(b,0,&bad,1,&info)==HRC_INVALID_ARGUMENT);
    hrc_residency duplicate[2]={truth[0],truth[0]};
    CHECK(hrc_frame_capture(b,0,duplicate,2,&info)==HRC_INVALID_ARGUMENT);
    CHECK(hvt_reset(vt)==HVT_OK);
    CHECK(hrc_frame_capture(b,UINT32_MAX,truth,view.info.upload_count,&info)==HRC_OK && info.removal_count);
    CHECK(hrc_frame_release(b)==HRC_OK);
    CHECK(hrc_frame_read(a,&view)==HRC_OK && before==hash(&view));
    hvt_release(&vt);
    CHECK(!vt && hrc_frame_capture(b,0,0,0,&info)==HRC_SOURCE_CLOSED && zero(&info,sizeof(info)));
    CHECK(hrc_frame_read(b,&view)==HRC_NO_FRAME && zero(&view,sizeof(view)));
    CHECK(hrc_frame_read(a,&view)==HRC_OK && before==hash(&view));
    CHECK(hrc_frame_release(a)==HRC_OK);
    CHECK(hrc_frame_release(a)==HRC_NO_FRAME);
    CHECK(hrc_frame_try_close(&a)==HRC_OK && !a);
    CHECK(hrc_try_destroy(&renderer)==HRC_BUSY && renderer);
    CHECK(hrc_frame_try_close(&b)==HRC_OK && !b);
    CHECK(hrc_try_destroy(&renderer)==HRC_OK && !renderer);
    return 0;
}
int main(int argc,char **argv) {
    CHECK(argc==2);
    CHECK(hrc_abi_version()==HRC_NATIVE_VERSION && howl_render_cpp()==0);
    CHECK(hrc_try_destroy(0)==HRC_OK && hrc_frame_try_close(0)==HRC_OK);
    CHECK(hrc_frame_release(0)==HRC_INVALID_ARGUMENT);
    CHECK(exercise(argv[1],0)==0);
    CHECK(exercise(argv[1],1)==0);
    return 0;
}
