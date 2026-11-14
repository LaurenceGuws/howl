#include "howl_instance_native.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stddef.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"foreign frame proof line %d: %s\n",__LINE__,#x); return __LINE__; } } while (0)
_Static_assert(sizeof(hi_frame_info) == 88, "Instance frame envelope");
_Static_assert(offsetof(hi_frame_info, command_count) == 40, "frame counts");
_Static_assert(offsetof(hi_frame_info, history_offset) == 56, "frame history");
_Static_assert(offsetof(hi_frame_info, surface_width) == 72, "frame geometry");
_Static_assert(sizeof(hrc_command) == 64 && sizeof(hrc_resource) == 40, "Render payloads");
_Static_assert(offsetof(hrc_command,destination_width) == 36 && offsetof(hrc_command,tag) == 56, "command projection");
_Static_assert(sizeof(hrc_residency) == 24, "residency record");
static uint64_t pixels_hash(const uint8_t *p, size_t n) {
    uint64_t h=UINT64_C(1469598103934665603);
    for (size_t i=0;i<n;++i) { h^=p[i]; h*=UINT64_C(1099511628211); }
    return h;
}
/* The C peer calls only public headers. Setup/advance uses the normal public
 * producer API; no canonical layout or mutable terminal pointer crosses here. */
int howl_native_frame_peer(hi_instance *parent, int (*advance)(void *), void *context) {
    hi_frame_stream *stream=NULL, *duplicate=NULL;
    CHECK(hi_frame_open(HI_ABI_VERSION,parent,&stream) == HI_OK && stream);
    CHECK(hi_frame_open(HI_ABI_VERSION,parent,&duplicate) == HI_BUSY && !duplicate);
    hi_instance *attempt=parent;
    CHECK(hi_destroy(&attempt) == HI_BUSY && attempt == parent);
    hi_frame_info info;
    memset(&info,0xa5,sizeof(info));
    CHECK(hi_frame_acquire(stream,&info) == HI_NO_FRAME && info.sequence == 0);
    CHECK(hi_publish_frame(parent,0) == HI_OK);
    CHECK(hi_frame_acquire(stream,&info) == HI_OK && info.command_count > 0);
    hi_frame_info blocked;
    CHECK(hi_frame_acquire(stream,&blocked) == HI_BUSY && blocked.sequence == 0);
    hrc_command *commands=calloc(info.command_count,sizeof(*commands));
    hrc_upload *uploads=calloc(info.upload_count ? info.upload_count : 1,sizeof(*uploads));
    hrc_removal *removals=calloc(info.removal_count ? info.removal_count : 1,sizeof(*removals));
    CHECK(commands && uploads && removals);
    commands[0].tag=99;
    CHECK(hi_frame_commands(stream,commands,0) == HI_RESOURCE_LIMIT && commands[0].tag == 99);
    CHECK(hi_frame_commands(stream,commands,info.command_count) == HI_OK);
    CHECK(hi_frame_uploads(stream,uploads,info.upload_count) == HI_OK);
    CHECK(hi_frame_removals(stream,removals,info.removal_count) == HI_OK);
    CHECK(info.upload_count > 0 && uploads[0].pixels && uploads[0].pixel_len > 0);
    const uint64_t hash=pixels_hash(uploads[0].pixels,uploads[0].pixel_len);
    const hrc_command first=commands[0];
    /* The canonical producer advances/publishes while this frame stays leased. */
    CHECK(advance(context) == 0);
    CHECK(pixels_hash(uploads[0].pixels,uploads[0].pixel_len) == hash);
    CHECK(hi_frame_commands(stream,commands,info.command_count) == HI_OK);
    CHECK(memcmp(&first,&commands[0],sizeof(first)) == 0);
    hrc_residency invalid={0};
    CHECK(hi_frame_release(stream,&invalid,1) == HI_INVALID_ARGUMENT);
    CHECK(hi_frame_commands(stream,commands,info.command_count) == HI_OK);
    hrc_residency *accepted=calloc(info.upload_count,sizeof(*accepted));
    CHECK(accepted);
    for (uint32_t n=0;n<info.upload_count;++n) {
        accepted[n].resource=uploads[n].info.resource;
        accepted[n].generation=uploads[n].info.generation;
        accepted[n].width=uploads[n].info.width;
        accepted[n].height=uploads[n].info.height;
        accepted[n].format=uploads[n].info.format;
    }
    CHECK(hi_frame_release(stream,accepted,info.upload_count) == HI_OK);
    CHECK(hi_frame_commands(stream,commands,info.command_count) == HI_NO_FRAME);
    /* The endpoint itself pins storage between leases. */
    CHECK(hi_destroy(&attempt) == HI_BUSY && attempt == parent);
    free(accepted); free(removals); free(uploads); free(commands);
    hi_frame_close(&stream);
    CHECK(!stream);
    /* Replacement starts empty even after the old peer accepted texture residency. */
    CHECK(hi_frame_open(HI_ABI_VERSION,parent,&stream) == HI_OK);
    CHECK(hi_publish_frame(parent,0) == HI_OK);
    CHECK(hi_frame_acquire(stream,&info) == HI_OK && info.upload_count > 0);
    CHECK(hi_frame_abandon(stream) == HI_OK);
    hi_frame_close(&stream);
    CHECK(!stream);
    return 0;
}

/* The producer uses a valid explicit command limit above the maintained host
 * envelope. The ABI must copy the actual advertised extent, not impose a second
 * unrelated envelope, and must not touch caller storage beyond that extent. */
int howl_native_large_frame_peer(hi_instance *parent, size_t maintained_envelope) {
    hi_frame_stream *stream=NULL;
    CHECK(hi_frame_open(HI_ABI_VERSION,parent,&stream) == HI_OK);
    CHECK(hi_publish_frame(parent,0) == HI_OK);
    hi_frame_info info;
    CHECK(hi_frame_acquire(stream,&info) == HI_OK);
    CHECK(info.command_count > maintained_envelope);
    hrc_command *commands=calloc((size_t)info.command_count+1,sizeof(*commands));
    CHECK(commands);
    commands[0].tag=99;
    commands[info.command_count].tag=98;
    CHECK(hi_frame_commands(stream,commands,info.command_count-1) == HI_RESOURCE_LIMIT);
    CHECK(commands[0].tag == 99 && commands[info.command_count].tag == 98);
    CHECK(hi_frame_commands(stream,commands,info.command_count) == HI_OK);
    CHECK(commands[0].tag != 99 && commands[info.command_count].tag == 98);
    CHECK(hi_frame_commands(stream,commands,SIZE_MAX) == HI_OK);
    CHECK(commands[info.command_count].tag == 98);
    CHECK(hi_frame_abandon(stream) == HI_OK);
    hi_frame_close(&stream);
    free(commands);
    CHECK(!stream);
    return 0;
}
