#define _POSIX_C_SOURCE 200809L
#include "howl_instance_native.h"
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Linux/x86_64 version-1 presentation records, including reserved fields. */
_Static_assert(sizeof(hi_font_source) == 40, "presentation layout");
_Static_assert(_Alignof(hi_font_source) == 8, "presentation layout");
_Static_assert(offsetof(hi_font_source, kind) == 0, "presentation layout");
_Static_assert(offsetof(hi_font_source, reserved) == 1, "presentation layout");
_Static_assert(offsetof(hi_font_source, primary) == 8, "presentation layout");
_Static_assert(offsetof(hi_font_source, fallbacks) == 24, "presentation layout");
_Static_assert(offsetof(hi_font_source, fallback_count) == 32, "presentation layout");
_Static_assert(sizeof(hi_presentation_config) == 208, "presentation layout");
_Static_assert(_Alignof(hi_presentation_config) == 8, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, fonts) == 0, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, pixel_size) == 160, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, reserved) == 162, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, max_sequence_scalars) == 164, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, shape_entries) == 168, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, shape_scalars) == 176, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, shape_glyphs) == 184, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, shaped_capacity) == 192, "presentation layout");
_Static_assert(offsetof(hi_presentation_config, raster_bytes) == 200, "presentation layout");
_Static_assert(sizeof(hi_cell_size) == 8, "presentation layout");
_Static_assert(_Alignof(hi_cell_size) == 4, "presentation layout");
_Static_assert(offsetof(hi_cell_size, width) == 0, "presentation layout");
_Static_assert(offsetof(hi_cell_size, height) == 2, "presentation layout");
_Static_assert(offsetof(hi_cell_size, reserved) == 4, "presentation layout");
_Static_assert(sizeof(hi_presented_config) == 80, "presentation layout");
_Static_assert(_Alignof(hi_presented_config) == 8, "presentation layout");
_Static_assert(offsetof(hi_presented_config, stroke_points) == 0, "presentation layout");
_Static_assert(offsetof(hi_presented_config, dpi_x_numerator) == 16, "presentation layout");
_Static_assert(offsetof(hi_presented_config, dpi_x_denominator) == 20, "presentation layout");
_Static_assert(offsetof(hi_presented_config, dpi_y_numerator) == 24, "presentation layout");
_Static_assert(offsetof(hi_presented_config, dpi_y_denominator) == 28, "presentation layout");
_Static_assert(offsetof(hi_presented_config, atlas_width) == 32, "presentation layout");
_Static_assert(offsetof(hi_presented_config, atlas_height) == 34, "presentation layout");
_Static_assert(offsetof(hi_presented_config, atlas_gap) == 36, "presentation layout");
_Static_assert(offsetof(hi_presented_config, incremental_rows) == 38, "presentation layout");
_Static_assert(offsetof(hi_presented_config, atlas_entries) == 40, "presentation layout");
_Static_assert(offsetof(hi_presented_config, command_capacity) == 48, "presentation layout");
_Static_assert(offsetof(hi_presented_config, command_limit) == 56, "presentation layout");
_Static_assert(offsetof(hi_presented_config, incremental_commands) == 64, "presentation layout");
_Static_assert(offsetof(hi_presented_config, reserved) == 72, "presentation layout");

/* This process uses only installed C contracts. It owns fonts, child recipes,
 * readiness, clocks and all backend state; no Zig setup/advance callback exists. */
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "presented C proof line %d: %s\n", __LINE__, #x); result=__LINE__; goto cleanup; } } while (0)
static uint64_t now_ns(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC,&value) != 0) return 0;
    return (uint64_t)value.tv_sec*UINT64_C(1000000000)+(uint64_t)value.tv_nsec;
}
static uint64_t hash_bytes(const void *bytes, size_t count) {
    const uint8_t *p=bytes;
    uint64_t h=UINT64_C(1469598103934665603);
    for (size_t n=0;n<count;++n) { h^=p[n]; h*=UINT64_C(1099511628211); }
    return h;
}
static int turn(hi_instance *owner) {
    hi_service state;
    if (hi_service_turn(owner,0,0,now_ns(),&state) != HI_OK) return 1;
    struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
    if (state.write_pending) fd.events|=POLLOUT;
    int ready=poll(&fd,1,state.buffered_output_pending ? 0 : 5);
    if (ready < 0) return errno == EINTR ? 0 : 1;
    return hi_service_turn(owner,(fd.revents&(POLLIN|POLLHUP)) != 0,
        (fd.revents&POLLOUT) != 0,now_ns(),&state) != HI_OK;
}
static int text_has(hi_instance *owner, const char *needle) {
    char bytes[4*33+1]; size_t used=0;
    for (uint16_t row=0;row<4;++row) {
        for (uint16_t col=0;col<32;++col) {
            hvt_cell cell;
            if (hi_copy_cell(owner,0,row,col,&cell) != HI_OK) return 0;
            bytes[used++]=cell.scalar_count && cell.scalars[0]<128 ? (char)cell.scalars[0] : ' ';
        }
        bytes[used++]='\n';
    }
    bytes[used]=0;
    return strstr(bytes,needle) != NULL;
}
static int await_text(hi_instance *a, hi_instance *b, hi_instance *target, const char *needle) {
    const uint64_t deadline=now_ns()+UINT64_C(5000000000);
    for (unsigned n=0;n<1000 && now_ns()<deadline;++n) {
        if ((a && turn(a)) || (b && turn(b))) return 1;
        if (text_has(target,needle)) return 0;
    }
    return 1;
}
static hi_presentation_config store_config(void) {
    hi_presentation_config c={0};
    c.pixel_size=18; c.max_sequence_scalars=16;
    c.shape_entries=256; c.shape_scalars=1024; c.shape_glyphs=1024;
    c.shaped_capacity=1024; c.raster_bytes=64*1024;
    return c;
}
static hi_presented_config presented_config(void) {
    hi_presented_config c={0};
    c.stroke_points[0]=0.001f; c.stroke_points[1]=1;
    c.stroke_points[2]=1.5f; c.stroke_points[3]=2;
    c.dpi_x_numerator=96; c.dpi_x_denominator=1;
    c.dpi_y_numerator=96; c.dpi_y_denominator=1;
    c.atlas_width=256; c.atlas_height=256; c.atlas_gap=1;
    c.atlas_entries=256; c.command_capacity=2048; c.command_limit=4096;
    c.incremental_rows=4; c.incremental_commands=2048;
    return c;
}
static int exercise(const char *font_path, int memory) {
    int result=0;
    FILE *file=NULL;
    uint8_t *source=NULL;
    size_t source_len=0;
    hi_presentation *store=NULL;
    hi_instance *a=NULL, *b=NULL;
    hi_frame_stream *stream=NULL, *peer=NULL;
    hrc_command *commands=NULL, *again=NULL;
    hrc_upload *uploads=NULL;
    hrc_residency *accepted=NULL;
    uint64_t *hashes=NULL;
    hi_frame_info first={0}, next={0};
    hi_cell_size cell={0}, copied={0};
    hi_presentation_config sc=store_config();
    hi_presented_config pc=presented_config();
    const char shell[]="/bin/sh", environment[]="PATH=/usr/bin:/bin";
    const char recipe_a[]="stty -echo; printf READY-A; while IFS= read -r line; do printf '\\r\\n\\033[1;3mA:%s\\033[0m\\r\\n' \"$line\"; done";
    const char recipe_b[]="stty -echo; printf READY-B; while IFS= read -r line; do printf '\\r\\n\\033[3mB:%s\\033[0m\\r\\n' \"$line\"; done";
    hi_bytes env={(const uint8_t *)environment,sizeof(environment)-1};
    hi_launch launch={{(const uint8_t *)shell,sizeof(shell)-1},
        {(const uint8_t *)recipe_a,sizeof(recipe_a)-1},{NULL,0},&env,1,4,32,8,0,0,0};
    CHECK(now_ns() != 0);
    if (memory) {
        file=fopen(font_path,"rb"); CHECK(file);
        CHECK(fseek(file,0,SEEK_END) == 0);
        long length=ftell(file); CHECK(length>0 && (unsigned long)length<=HI_MAX_FONT_BYTES);
        source_len=(size_t)length;
        CHECK(fseek(file,0,SEEK_SET) == 0);
        source=malloc(source_len); CHECK(source);
        CHECK(fread(source,1,source_len,file) == source_len);
        int closed=fclose(file); file=NULL; CHECK(closed == 0);
    } else {
        source_len=strlen(font_path);
        source=malloc(source_len); CHECK(source);
        memcpy(source,font_path,source_len);
    }
    hi_bytes fallback={source,source_len};
    sc.fonts[HI_FONT_REGULAR]=(hi_font_source){memory ? HI_FONT_MEMORY : HI_FONT_PATH,
        {0},{source,source_len},&fallback,1};
    sc.fonts[HI_FONT_ITALIC]=sc.fonts[HI_FONT_REGULAR];
    sc.fonts[HI_FONT_BOLD_ITALIC]=sc.fonts[HI_FONT_REGULAR];
    CHECK(hi_presentation_release(NULL) == HI_INVALID_ARGUMENT);
    CHECK(hi_presentation_release(&store) == HI_OK && !store);
    CHECK(hi_presentation_create(99,&sc,&store) == HI_VERSION_MISMATCH && !store);
    hi_presentation_config bad_store=sc;
    bad_store.fonts[0].reserved[6]=1;
    CHECK(hi_presentation_create(HI_ABI_VERSION,&bad_store,&store) == HI_INVALID_ARGUMENT && !store);
    bad_store=sc; bad_store.fonts[0].fallbacks=NULL;
    CHECK(hi_presentation_create(HI_ABI_VERSION,&bad_store,&store) == HI_INVALID_ARGUMENT && !store);
    bad_store=sc; bad_store.raster_bytes=HI_MAX_PRESENTATION_RASTER_BYTES+1u;
    CHECK(hi_presentation_create(HI_ABI_VERSION,&bad_store,&store) == HI_RESOURCE_LIMIT && !store);
    CHECK(hi_presentation_create(HI_ABI_VERSION,&sc,&store) == HI_OK && store);
    hi_presentation *saved_store=store;
    CHECK(hi_presentation_create(HI_ABI_VERSION,&sc,&store) == HI_INVALID_ARGUMENT && store == saved_store);
    /* Both descriptor arrays and every source byte can disappear immediately. */
    memset(source,0xa5,source_len); free(source); source=NULL;
    memset(&fallback,0xa5,sizeof(fallback)); memset(&sc,0xa5,sizeof(sc));
    memset(&cell,0xa5,sizeof(cell));
    CHECK(hi_presentation_cell_size(NULL,&cell) == HI_INVALID_ARGUMENT &&
        !cell.width && !cell.height && !cell.reserved);
    CHECK(hi_presentation_cell_size(store,&cell) == HI_OK && cell.width && cell.height && !cell.reserved);
    copied=cell;
    CHECK(hi_create_presented(99,&launch,store,&pc,&a) == HI_VERSION_MISMATCH && !a);
    hi_launch bad_launch=launch; bad_launch.cell_width=cell.width;
    CHECK(hi_create_presented(HI_ABI_VERSION,&bad_launch,store,&pc,&a) == HI_INVALID_ARGUMENT && !a);
    hi_presented_config bad_pc=pc; bad_pc.command_limit=0;
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&bad_pc,&a) == HI_INVALID_ARGUMENT && !a);
    bad_pc=pc; bad_pc.incremental_commands=0;
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&bad_pc,&a) == HI_INVALID_ARGUMENT && !a);
    bad_pc=pc; bad_pc.atlas_width=65535; bad_pc.atlas_height=65535;
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&bad_pc,&a) == HI_RESOURCE_LIMIT && !a);
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&pc,&a) == HI_OK && a);
    hi_instance *saved_a=a;
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&pc,&a) == HI_INVALID_ARGUMENT && a == saved_a);
    launch.command=(hi_bytes){(const uint8_t *)recipe_b,sizeof(recipe_b)-1};
    CHECK(hi_create_presented(HI_ABI_VERSION,&launch,store,&pc,&b) == HI_OK && b && b != a);
    CHECK(hi_presentation_release(&store) == HI_OK && !store);
    CHECK(hi_presentation_release(&store) == HI_OK);
    CHECK(copied.width == cell.width && copied.height == cell.height);
    CHECK(hi_resize(a,4,32,0,0) == HI_OK);
    CHECK(hi_resize(a,4,32,cell.width+1u,cell.height) == HI_INVALID_ARGUMENT);
    CHECK(await_text(a,b,a,"READY-A") == 0 && await_text(a,b,b,"READY-B") == 0);
    CHECK(hi_frame_open(HI_ABI_VERSION,a,&stream) == HI_OK && stream);
    CHECK(hi_publish_frame(a,0) == HI_OK);
    CHECK(hi_frame_acquire(stream,&first) == HI_OK && first.command_count>1 && first.upload_count);
    CHECK(first.cell_width == cell.width && first.cell_height == cell.height);
    CHECK(first.surface_width == 32u*cell.width && first.surface_height == 4u*cell.height);
    commands=calloc(first.command_count,sizeof(*commands));
    again=calloc(first.command_count,sizeof(*again));
    uploads=calloc(first.upload_count,sizeof(*uploads));
    accepted=calloc(first.upload_count,sizeof(*accepted));
    hashes=calloc(first.upload_count,sizeof(*hashes));
    CHECK(commands && again && uploads && accepted && hashes);
    CHECK(hi_frame_commands(stream,commands,first.command_count) == HI_OK);
    CHECK(hi_frame_uploads(stream,uploads,first.upload_count) == HI_OK);
    int alpha=0, ink=0;
    for (uint32_t n=0;n<first.command_count;++n) if (commands[n].tag == HRC_ALPHA_MASK) alpha=1;
    for (uint32_t n=0;n<first.upload_count;++n) {
        CHECK(uploads[n].pixels && uploads[n].pixel_len);
        hashes[n]=hash_bytes(uploads[n].pixels,uploads[n].pixel_len);
        for (size_t k=0;k<uploads[n].pixel_len;++k) if (uploads[n].pixels[k]) { ink=1; break; }
        accepted[n]=(hrc_residency){uploads[n].info.resource,uploads[n].info.generation,
            uploads[n].info.width,uploads[n].info.height,uploads[n].info.format,{0}};
    }
    CHECK(alpha && ink);
    CHECK(hi_destroy(&a) == HI_BUSY && a == saved_a);
    CHECK(hi_send_text(a,(const uint8_t *)"first\n",6) == HI_OK);
    CHECK(hi_send_text(b,(const uint8_t *)"peer\n",5) == HI_OK);
    CHECK(await_text(a,b,a,"A:first") == 0 && await_text(a,b,b,"B:peer") == 0);
    for (unsigned n=0;n<3;++n) CHECK(hi_publish_frame(a,0) == HI_OK);
    CHECK(hi_frame_commands(stream,again,first.command_count) == HI_OK);
    CHECK(memcmp(commands,again,first.command_count*sizeof(*commands)) == 0);
    for (uint32_t n=0;n<first.upload_count;++n)
        CHECK(hash_bytes(uploads[n].pixels,uploads[n].pixel_len) == hashes[n]);
    CHECK(hi_frame_release(stream,accepted,first.upload_count) == HI_OK);
    CHECK(hi_destroy(&a) == HI_BUSY && a == saved_a); /* Also between leases. */
    CHECK(hi_frame_acquire(stream,&next) == HI_OK && next.sequence>first.sequence &&
        next.terminal_revision>first.terminal_revision);
    CHECK(hi_frame_abandon(stream) == HI_OK);
    hi_frame_close(&stream); CHECK(!stream);
    CHECK(hi_destroy(&a) == HI_OK && !a);
    /* The surviving borrower still shapes/rasterizes after caller and peer exit. */
    CHECK(hi_send_text(b,(const uint8_t *)"survivor\n",9) == HI_OK);
    CHECK(await_text(NULL,b,b,"B:survivor") == 0);
    CHECK(hi_frame_open(HI_ABI_VERSION,b,&peer) == HI_OK);
    CHECK(hi_publish_frame(b,0) == HI_OK);
    CHECK(hi_frame_acquire(peer,&next) == HI_OK && next.command_count>1 && next.upload_count);
    CHECK(hi_frame_abandon(peer) == HI_OK);
    hi_frame_close(&peer); CHECK(!peer);
    CHECK(hi_destroy(&b) == HI_OK && !b);
cleanup:
    hi_frame_close(&stream); hi_frame_close(&peer);
    if (a && hi_destroy(&a) != HI_OK) result=result ? result : 1;
    if (b && hi_destroy(&b) != HI_OK) result=result ? result : 1;
    if (hi_presentation_release(&store) != HI_OK) result=result ? result : 1;
    free(hashes); free(accepted); free(uploads); free(again); free(commands);
    free(source); if (file) fclose(file);
    return result;
}
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    alarm(20); /* Proof-owned deadline, never a library timer. */
    int result=exercise(argv[1],0);
    if (!result) result=exercise(argv[1],1);
    alarm(0);
    return result;
}
