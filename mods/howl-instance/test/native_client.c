#define _POSIX_C_SOURCE 200809L
#include "howl_instance_native.h"
#include <poll.h>
#include <string.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "native Instance proof failed line %d: %s\n", __LINE__, #x); return __LINE__; } } while (0)
static uint64_t now_ns(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}
static int text_has(hi_instance *instance, const char *needle) {
    char text[4 * 81 + 1]; size_t at = 0;
    for (uint16_t row = 0; row < 4; ++row) {
        for (uint16_t col = 0; col < 80; ++col) {
            hvt_cell cell;
            if (hi_copy_cell(instance, 0, row, col, &cell) != HI_OK) return 0;
            text[at++] = cell.scalar_count && cell.scalars[0] < 128 ? (char)cell.scalars[0] : ' ';
        }
        text[at++] = '\n';
    }
    text[at] = 0;
    return strstr(text, needle) != NULL;
}
/* Foreign retained request proof. Policy, clock, poll and child recipe are caller-owned. */
static int retained_requests(void) {
    hi_instance *owner=NULL;
    const char shell[]="/bin/sh", env_text[]="PATH=/usr/bin:/bin";
    const char command[]="stty -echo -icanon min 1 time 0; printf '\033]52;c;?\007'; dd bs=1 count=9 status=none | od -An -tx1; exit 0";
    hi_bytes environment={(const uint8_t *)env_text,sizeof(env_text)-1};
    hi_launch launch={{(const uint8_t *)shell,sizeof(shell)-1},{(const uint8_t *)command,sizeof(command)-1},{NULL,0},&environment,1,4,80,16,0,10,20};
    REQUIRE(hi_create(HI_ABI_VERSION,&launch,&owner) == HI_OK);
    hi_service state;
    REQUIRE(hi_service_turn_policy(owner,HI_SERVICE_RETAIN,0,0,now_ns(),&state) == HI_OK);
    hvt_request first={0};
    const uint64_t deadline=now_ns()+UINT64_C(5000000000);
    while (now_ns() < deadline) {
        struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
        if (state.write_pending) fd.events |= POLLOUT;
        REQUIRE(poll(&fd,1,state.buffered_output_pending ? 0 : 10) >= 0);
        REQUIRE(hi_service_turn_policy(owner,HI_SERVICE_RETAIN,(fd.revents & (POLLIN|POLLHUP)) != 0,(fd.revents & POLLOUT) != 0,now_ns(),&state) == HI_OK);
        REQUIRE(hi_request_head(owner,&first) == HI_OK);
        if (first.kind != HVT_REQUEST_NONE) break;
    }
    REQUIRE(first.kind == HVT_REQUEST_CLIPBOARD && first.occurrence_id && first.reply_required);
    REQUIRE(first.data.clipboard.operation == HVT_CLIPBOARD_QUERY && first.data.clipboard.protocol == HVT_CLIPBOARD_OSC52 && first.data.clipboard.selection_len == 1);
    hvt_request again;
    hi_service bad;
    REQUIRE(hi_service_turn_policy(owner,0,0,0,now_ns(),&bad) == HI_INVALID_ARGUMENT && bad.terminal_revision == 0);
    REQUIRE(hi_request_head(owner,&again) == HI_OK && memcmp(&first,&again,sizeof(first)) == 0);
    uint8_t copied[32]; copied[0]=77; size_t required=99;
    REQUIRE(hi_copy_request_payload(owner,first.occurrence_id+1,copied,sizeof(copied),&required) == HI_STALE_REQUEST && required == 0 && copied[0] == 77);
    REQUIRE(hi_copy_request_payload(owner,first.occurrence_id,copied,1,&required) == HI_BUFFER_TOO_SMALL && required == 3 && copied[0] == 77);
    REQUIRE(hi_copy_request_payload(owner,first.occurrence_id,copied,sizeof(copied),&required) == HI_OK && required == 3 && memcmp(copied,"c;?",3) == 0);
    REQUIRE(hi_consume_request(owner,first.occurrence_id) == HI_REPLY_REQUIRED);
    REQUIRE(hi_reply_clipboard(owner,first.occurrence_id+1,NULL,0) == HI_STALE_REQUEST);
    REQUIRE(hi_reply_pointer_shape(owner,first.occurrence_id,(const uint8_t *)"default",7) == HI_STALE_REQUEST);
    REQUIRE(hi_reply_color_preference(owner,first.occurrence_id,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_reply_container_state(owner,first.occurrence_id,99) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_reply_container_position(owner,first.occurrence_id,1,2) == HI_STALE_REQUEST);
    REQUIRE(hi_request_head(owner,&again) == HI_OK && memcmp(&first,&again,sizeof(first)) == 0);
    REQUIRE(hi_reply_clipboard(owner,first.occurrence_id,NULL,0) == HI_OK);
    REQUIRE(hi_request_head(owner,&again) == HI_OK && again.kind == HVT_REQUEST_NONE);
    REQUIRE(memcmp(copied,"c;?",3) == 0);
    REQUIRE(hi_service_turn_policy(owner,HI_SERVICE_RETAIN,0,0,now_ns(),&state) == HI_OK);
    REQUIRE(state.write_pending);
    while (now_ns() < deadline && !state.stream_closed) {
        struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
        if (state.write_pending) fd.events |= POLLOUT;
        REQUIRE(poll(&fd,1,state.buffered_output_pending ? 0 : 10) >= 0);
        REQUIRE(hi_service_turn_policy(owner,HI_SERVICE_RETAIN,(fd.revents & (POLLIN|POLLHUP)) != 0,(fd.revents & POLLOUT) != 0,now_ns(),&state) == HI_OK);
    }
    REQUIRE(state.stream_closed);
    REQUIRE(text_has(owner,"1b 5d 35 32 3b 63 3b 1b 5c"));
    REQUIRE(hi_destroy(&owner) == HI_OK && !owner);
    REQUIRE(memcmp(copied,"c;?",3) == 0 && first.kind == HVT_REQUEST_CLIPBOARD);
    return 0;
}
/* Reader references cross the two exact module artifacts; they neither keep the
 * process alive nor make Instance destruction busy. */
static int observation_lifetime(void) {
    int result=1;
    hi_instance *owner=NULL,*fresh=NULL;
    hvt_observation *reader=NULL,*peer=NULL,*next=NULL;
    hvt_observation *extra[HVT_MAX_OBSERVATION_REFERENCES-3u]={0};
    size_t count=0;
    const char shell[]="/bin/sh", command[]="exec sleep 30", env[]="PATH=/usr/bin:/bin";
    const hi_bytes environment={(const uint8_t *)env,sizeof(env)-1};
    const hi_launch launch={{(const uint8_t *)shell,sizeof(shell)-1},
        {(const uint8_t *)command,sizeof(command)-1},{NULL,0},&environment,1,2,8,0,0,8,16};
    hvt_interaction before={0},after={0};
#define SOURCE_REQUIRE(x) do { if (!(x)) { fprintf(stderr,"source C proof line %d: %s\n",__LINE__,#x); goto cleanup; } } while (0)
    SOURCE_REQUIRE(hi_observation_open(0,NULL,&reader)==HI_VERSION_MISMATCH && !reader);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,NULL,&reader)==HI_INVALID_ARGUMENT && !reader);
    SOURCE_REQUIRE(hi_create(HI_ABI_VERSION,&launch,&owner)==HI_OK && owner);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,NULL)==HI_INVALID_ARGUMENT);
    SOURCE_REQUIRE(hi_interaction(owner,&before)==HI_OK);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&reader)==HI_OK && reader);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&peer)==HI_OK && peer==reader);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&peer)==HI_INVALID_ARGUMENT && peer==reader);
    for (size_t n=0;n<sizeof extra/sizeof extra[0];++n) {
        SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&extra[n])==HI_OK && extra[n]==reader);
        ++count;
    }
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&next)==HI_RESOURCE_LIMIT && !next);
    SOURCE_REQUIRE(hi_interaction(owner,&after)==HI_OK && memcmp(&before,&after,sizeof before)==0);
    SOURCE_REQUIRE(hvt_observation_release(&extra[count-1])==HVT_OK && !extra[count-1]);
    --count;
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,owner,&extra[count])==HI_OK && extra[count]==reader);
    ++count;
    SOURCE_REQUIRE(hi_destroy(&owner)==HI_OK && !owner);
    SOURCE_REQUIRE(hi_create(HI_ABI_VERSION,&launch,&fresh)==HI_OK && fresh);
    SOURCE_REQUIRE(hi_observation_open(HI_ABI_VERSION,fresh,&next)==HI_OK && next && next!=reader);
    SOURCE_REQUIRE(hi_destroy(&fresh)==HI_OK && !fresh);
    result=0;
cleanup:
    if (owner && hi_destroy(&owner)!=HI_OK) result=1;
    if (fresh && hi_destroy(&fresh)!=HI_OK) result=1;
    for (size_t n=0;n<count;++n) if (hvt_observation_release(&extra[n])!=HVT_OK || extra[n]) result=1;
    if (hvt_observation_release(&next)!=HVT_OK || next) result=1;
    if (hvt_observation_release(&peer)!=HVT_OK || peer) result=1;
    if (hvt_observation_release(&reader)!=HVT_OK || reader) result=1;
    if (hvt_observation_release(&reader)!=HVT_OK || hvt_observation_release(NULL)!=HVT_OK) result=1;
#undef SOURCE_REQUIRE
    return result;
}
extern int howl_instance_cpp_header(void);

/* Actual process bytes reach the same VT-owned copied graphics helper. */
static int copied_graphics(void) {
    int result=1;
    hi_instance *owner=NULL;
    const char shell[]="/bin/sh", env[]="PATH=/usr/bin:/bin";
    const char command[]="printf '\\033_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\\033\\\\'; exec sleep 30";
    const hi_bytes environment={(const uint8_t *)env,sizeof env-1};
    const hi_launch launch={{(const uint8_t *)shell,sizeof shell-1},{(const uint8_t *)command,sizeof command-1},{NULL,0},&environment,1,2,8,0,0,8,16};
    hvt_image images[2];
    hvt_image_placement placements[2];
    hvt_graphics manifest={0},zero={0};
    uint8_t pixels[5]={0xa5,0xa5,0xa5,0xa5,0xa5};
    size_t required=99;
    hi_service state={0};
#define GRAPHICS_REQUIRE(x) do { if (!(x)) { fprintf(stderr,"Instance graphics proof line %d: %s\n",__LINE__,#x); goto cleanup; } } while (0)
    GRAPHICS_REQUIRE(hi_copy_graphics(NULL,0,NULL,0,NULL,0,&manifest)==HI_INVALID_ARGUMENT && memcmp(&manifest,&zero,sizeof zero)==0);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(NULL,0,1,1,pixels,sizeof pixels,&required)==HI_INVALID_ARGUMENT && required==0);
    GRAPHICS_REQUIRE(hi_create(HI_ABI_VERSION,&launch,&owner)==HI_OK);
    GRAPHICS_REQUIRE(hi_service_turn(owner,0,0,now_ns(),&state)==HI_OK);
    const uint64_t deadline=now_ns()+UINT64_C(5000000000);
    do {
        struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
        if (state.write_pending) fd.events |= POLLOUT;
        GRAPHICS_REQUIRE(poll(&fd,1,state.buffered_output_pending ? 0 : 10)>=0);
        GRAPHICS_REQUIRE(hi_service_turn(owner,(fd.revents & (POLLIN|POLLHUP))!=0,(fd.revents & POLLOUT)!=0,now_ns(),&state)==HI_OK);
        GRAPHICS_REQUIRE(hi_copy_graphics(owner,0,images,2,placements,2,&manifest)==HI_OK);
    } while (!manifest.image_count && now_ns()<deadline);
    GRAPHICS_REQUIRE(manifest.image_count==1 && manifest.placement_count==1 && manifest.cell_width==8 && manifest.cell_height==16);
    GRAPHICS_REQUIRE(images[0].byte_count==4 && placements[0].image_id==images[0].image_id);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(owner,manifest.terminal_revision,images[0].image_id,images[0].generation,pixels,3,&required)==HI_BUFFER_TOO_SMALL && required==4 && pixels[0]==0xa5);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(owner,manifest.terminal_revision,images[0].image_id,images[0].generation,pixels,sizeof pixels,&required)==HI_OK && required==4 && memcmp(pixels,"\1\2\3\4",4)==0 && pixels[4]==0xa5);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(owner,manifest.terminal_revision-1,images[0].image_id,images[0].generation,pixels,sizeof pixels,&required)==HI_CONTEXT_CHANGED && required==0 && pixels[0]==1);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(owner,manifest.terminal_revision,0,images[0].generation,pixels,sizeof pixels,&required)==HI_INVALID_ARGUMENT && required==0);
    GRAPHICS_REQUIRE(hi_copy_image_pixels(owner,manifest.terminal_revision,images[0].image_id,images[0].generation,pixels,HVT_MAX_IMAGE_BYTES+1u,&required)==HI_RESOURCE_LIMIT && required==0);
    GRAPHICS_REQUIRE(hi_copy_graphics(owner,0,NULL,0,NULL,0,&manifest)==HI_BUFFER_TOO_SMALL && manifest.image_count==1 && manifest.placement_count==1);
    GRAPHICS_REQUIRE(hi_destroy(&owner)==HI_OK && !owner);
    GRAPHICS_REQUIRE(images[0].byte_count==4 && memcmp(pixels,"\1\2\3\4",4)==0);
    result=0;
cleanup:
    if (hi_destroy(&owner)!=HI_OK) result=1;
#undef GRAPHICS_REQUIRE
    return result;
}


/* Result owns only copied output; the exact VT companion reads/releases it after
 * the Instance process owner is gone. No frame or presentation owner is used. */
static int copied_output(void) {
    int result=1;
    hi_instance *owner=NULL;
    hvt_output *snapshot=NULL;
    hvt_output_view view={0},after={0};
    const char shell[]="/bin/sh",env[]="PATH=/usr/bin:/bin";
    const char command[]="printf 'one\\r\\ntwo\\r\\nopen'; exec sleep 30";
    const hi_bytes environment={(const uint8_t *)env,sizeof env-1};
    const hi_launch launch={{(const uint8_t *)shell,sizeof shell-1},{(const uint8_t *)command,sizeof command-1},{NULL,0},&environment,1,2,8,4,0,8,16};
    hi_service state={0};
#define OUTPUT_REQUIRE(x) do { if (!(x)) { fprintf(stderr,"Instance output proof line %d: %s\n",__LINE__,#x); goto cleanup; } } while (0)
    OUTPUT_REQUIRE(hi_output_open(0,NULL,0,0,0,NULL)==HI_VERSION_MISMATCH);
    OUTPUT_REQUIRE(hi_output_open(HI_ABI_VERSION,NULL,0,1,1,&snapshot)==HI_INVALID_ARGUMENT && !snapshot);
    OUTPUT_REQUIRE(hi_create(HI_ABI_VERSION,&launch,&owner)==HI_OK);
    OUTPUT_REQUIRE(hi_output_open(HI_ABI_VERSION,owner,0,0,1,&snapshot)==HI_INVALID_ARGUMENT && !snapshot);
    OUTPUT_REQUIRE(hi_output_open(HI_ABI_VERSION,owner,0,1,HVT_MAX_COPY_BYTES+1u,&snapshot)==HI_INVALID_ARGUMENT && !snapshot);
    OUTPUT_REQUIRE(hi_service_turn(owner,0,0,now_ns(),&state)==HI_OK);
    const uint64_t deadline=now_ns()+UINT64_C(5000000000);
    do {
        struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
        if (state.write_pending) fd.events |= POLLOUT;
        OUTPUT_REQUIRE(poll(&fd,1,state.buffered_output_pending ? 0 : 10)>=0);
        OUTPUT_REQUIRE(hi_service_turn(owner,(fd.revents & (POLLIN|POLLHUP))!=0,(fd.revents & POLLOUT)!=0,now_ns(),&state)==HI_OK);
        hvt_output_release(&snapshot);
        OUTPUT_REQUIRE(hi_output_open(HI_ABI_VERSION,owner,0,4,64,&snapshot)==HI_OK);
        OUTPUT_REQUIRE(hvt_output_read(snapshot,&view)==HVT_OK);
    } while ((view.kind!=HVT_OUTPUT_DATA || view.text_len<7) && now_ns()<deadline);
    OUTPUT_REQUIRE(view.kind==HVT_OUTPUT_DATA && view.line_count==2 && view.text_len==7 && memcmp(view.text,"one\ntwo",7)==0);
    OUTPUT_REQUIRE(view.open_line_len==4 && memcmp(view.open_line,"open",4)==0 && view.loss_count==0);
    hvt_output *saved=snapshot;
    OUTPUT_REQUIRE(hi_output_open(HI_ABI_VERSION,owner,0,4,64,&snapshot)==HI_INVALID_ARGUMENT && snapshot==saved);
    OUTPUT_REQUIRE(hi_destroy(&owner)==HI_OK && !owner);
    OUTPUT_REQUIRE(hvt_output_read(snapshot,&after)==HVT_OK && after.text==view.text && after.open_line==view.open_line);
    OUTPUT_REQUIRE(after.text_len==7 && memcmp(after.text,"one\ntwo",7)==0 && memcmp(after.open_line,"open",4)==0);
    hvt_output_release(&snapshot);
    OUTPUT_REQUIRE(!snapshot);
    result=0;
cleanup:
    hvt_output_release(&snapshot);
    if (hi_destroy(&owner)!=HI_OK) result=1;
#undef OUTPUT_REQUIRE
    return result;
}

int main(void) {
    REQUIRE(howl_instance_cpp_header() == 0);
    REQUIRE(observation_lifetime() == 0);
    REQUIRE(retained_requests() == 0);
    REQUIRE(copied_graphics() == 0);
    REQUIRE(copied_output() == 0);
    hi_instance *instance = NULL;
    char shell[] = "/bin/sh";
    const char command[] = "stty -echo; printf READY; IFS= read -r line; printf '\r\nREPLY:%s:%s:%s:%s' \"$line\" \"$ABI_TEST\" \"$TERM\" \"$COLORTERM\"; exit 7";
    char env0[] = "PATH=/usr/bin:/bin", env1[] = "ABI_TEST=OWNED";
    char old_term[] = "TERM=WRONG", old_color[] = "COLORTERM=WRONG";
    hi_bytes env[] = {{(const uint8_t *)env0,sizeof(env0)-1},{(const uint8_t *)env1,sizeof(env1)-1},{(const uint8_t *)old_term,sizeof(old_term)-1},{(const uint8_t *)old_color,sizeof(old_color)-1}};
    hi_launch launch = {
        {(const uint8_t *)shell,sizeof(shell)-1},
        {(const uint8_t *)command,sizeof(command)-1}, {NULL,0},
        env,4,4,80,16,0,10,20
    };
    REQUIRE(hi_abi_version() == HI_ABI_VERSION);
    REQUIRE(hi_create(99, &launch, &instance) == HI_VERSION_MISMATCH && instance == NULL);
    hi_launch bad = launch; bad.reserved = 1;
    REQUIRE(hi_create(HI_ABI_VERSION,&bad,&instance) == HI_INVALID_ARGUMENT && instance == NULL);
    hi_bytes duplicates[] = {env[1],env[1]}; bad = launch; bad.environment=duplicates; bad.environment_count=2;
    REQUIRE(hi_create(HI_ABI_VERSION,&bad,&instance) == HI_INVALID_ARGUMENT && instance == NULL);
    bad = launch; bad.environment_count=1025;
    REQUIRE(hi_create(HI_ABI_VERSION,&bad,&instance) == HI_RESOURCE_LIMIT && instance == NULL);
    const uint8_t invalid_name[] = "=bad";
    const uint8_t no_equals[] = "BAD";
    const uint8_t embedded_nul[] = {'A','=','x',0,'y'};
    hi_bytes malformed[] = {{invalid_name,sizeof(invalid_name)-1},{no_equals,sizeof(no_equals)-1},{embedded_nul,sizeof(embedded_nul)}};
    for (size_t n=0;n<3;++n) {
        bad = launch; bad.environment=&malformed[n]; bad.environment_count=1;
        REQUIRE(hi_create(HI_ABI_VERSION,&bad,&instance) == HI_INVALID_ARGUMENT && instance == NULL);
    }
    uint8_t *large = malloc(1024 * 1024);
    REQUIRE(large != NULL);
    memset(large,'a',1024 * 1024); large[0]='A'; large[1]='=';
    hi_bytes excessive = {large,1024 * 1024 - 1};
    bad = launch; bad.environment=&excessive; bad.environment_count=1;
    REQUIRE(hi_create(HI_ABI_VERSION,&bad,&instance) == HI_RESOURCE_LIMIT && instance == NULL);
    free(large);
    REQUIRE(hi_create(HI_ABI_VERSION,&launch,&instance) == HI_OK && instance != NULL);
    env1[9] = 'X'; shell[1] = 'X';
    REQUIRE(hi_send_named_key(instance,0,HVT_PRESS,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_unicode_key(instance,0xd800,HVT_PRESS,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_focus(instance,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_named_key(instance,HVT_KEY_ENTER,0,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_mouse(instance,0,HVT_BUTTON_LEFT,0,0,0,0,0,0,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_mouse(instance,HVT_MOUSE_PRESS,99,0,0,0,0,0,0,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_mouse(instance,HVT_MOUSE_PRESS,HVT_BUTTON_LEFT,0,0,0,0,2,0,0) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_send_text(instance,NULL,1) == HI_INVALID_ARGUMENT);
    REQUIRE(hi_resize(instance,0,80,10,20) == HI_INVALID_ARGUMENT);
    uint8_t signal_result = 99;
    REQUIRE(hi_signal_group(instance,0,&signal_result) == HI_INVALID_ARGUMENT && signal_result == 0);
    hi_service state;
    memset(&state,0xa5,sizeof(state));
    REQUIRE(hi_service_turn(instance,2,0,now_ns(),&state) == HI_INVALID_ARGUMENT);
    REQUIRE(state.terminal_revision == 0 && state.descriptor_kind == 0);
    REQUIRE(hi_service_turn(instance,0,0,now_ns(),&state) == HI_OK);
    REQUIRE(state.descriptor_kind == 1 && state.descriptor >= 0);
    const uint64_t deadline = now_ns() + UINT64_C(5000000000);
    int sent = 0, exited = 0;
    while (now_ns() < deadline) {
        struct pollfd fd = {state.descriptor, POLLIN | POLLHUP, 0};
        if (state.write_pending) fd.events |= POLLOUT;
        int timeout = state.buffered_output_pending ? 0 : 10;
        REQUIRE(poll(&fd,1,timeout) >= 0);
        REQUIRE(hi_service_turn(instance,(fd.revents & (POLLIN|POLLHUP)) != 0,(fd.revents & POLLOUT) != 0,now_ns(),&state) == HI_OK);
        if (!sent && text_has(instance,"READY")) {
            uint8_t input[] = "hello\n";
            REQUIRE(hi_send_text(instance,input,sizeof(input)-1) == HI_OK);
            input[0] = 'X';
            sent = 1;
            /* Re-query current pending writes after input admission. */
            REQUIRE(hi_service_turn(instance,0,0,now_ns(),&state) == HI_OK);
            REQUIRE(state.write_pending);
        }
        if (state.exit_kind) { exited = 1; break; }
    }
    REQUIRE(sent && exited);
    /* Child exit may be observed before the final buffered PTY tail is drained. */
    for (int n=0;n<100 && !state.stream_closed;++n)
        REQUIRE(hi_service_turn(instance,1,1,now_ns(),&state) == HI_OK);
    REQUIRE(state.exit_kind == 1 && state.exit_value == 7);
    REQUIRE(text_has(instance,"REPLY:hello:OWNED:xterm-256color:truecolor"));
    REQUIRE(hi_signal_group(instance,HI_INTERRUPT,&signal_result) == HI_OK && signal_result == HI_SIGNAL_TARGET_MISSING);
    hvt_search_match match;
    REQUIRE(hi_search(instance,(const uint8_t *)"READY",5,0,0,0,0,&match) == HI_OK);
    REQUIRE(match.found && match.complete && match.row == 0 && match.start_column == 0 && match.end_column == 4);
    hvt_selection_range range;
    REQUIRE(hi_expand_selection(instance,HVT_SELECTION_WORD,0,0,2,80,0,&range) == HI_OK);
    REQUIRE(range.found && range.start_column == 0 && range.end_column == 4);
    uint8_t selected[32]; size_t selected_len=99;
    selected[0]=77;
    REQUIRE(hi_copy_selection(instance,0,0,0,4,80,0,selected,4,&selected_len) == HI_BUFFER_TOO_SMALL);
    REQUIRE(selected_len == 0 && selected[0] == 77);
    REQUIRE(hi_copy_selection(instance,0,0,0,4,80,0,selected,sizeof(selected),&selected_len) == HI_OK);
    REQUIRE(selected_len == 5 && memcmp(selected,"READY",5) == 0);
    REQUIRE(hi_expand_selection(instance,HVT_SELECTION_WORD,0,0,2,79,0,&range) == HI_CONTEXT_CHANGED && !range.found);
    memset(&match,0xa5,sizeof(match));
    REQUIRE(hi_search(instance,(const uint8_t *)"READY",5,2,0,0,0,&match) == HI_INVALID_ARGUMENT);
    REQUIRE(match.cut_revision == 0 && match.complete == 0);
    REQUIRE(hi_search(instance,NULL,1,0,0,0,0,&match) == HI_INVALID_ARGUMENT);
    hvt_row_shape shapes[5]; shapes[0].content_end_exclusive=77; shapes[4].content_end_exclusive=78;
    size_t row_count=0;
    REQUIRE(hi_copy_row_shapes(instance,0,shapes,3,&row_count) == HI_BUFFER_TOO_SMALL && row_count == 4);
    REQUIRE(shapes[0].content_end_exclusive == 77);
    REQUIRE(hi_copy_row_shapes(instance,0,shapes,SIZE_MAX,&row_count) == HI_OK && row_count == 4);
    REQUIRE(shapes[4].content_end_exclusive == 78);
    hvt_cell copied;
    REQUIRE(hi_copy_cell(instance,0,0,0,&copied) == HI_OK);
    REQUIRE(hi_destroy(&instance) == HI_OK && instance == NULL);
    REQUIRE(copied.scalar_count > 0 && copied.scalars[0] == 'R');
    REQUIRE(hi_destroy(&instance) == HI_OK);
    shell[1] = 'b';
    const char occupancy[] = "printf '\033]8;;https://example.invalid/x\007\347\225\214\033]8;;\007\033[2;1H\033]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\007\033[?1003h\033[?1016h\033[?1004h\033[?1007h'; exit 0";
    launch.command.data = (const uint8_t *)occupancy;
    launch.command.len = sizeof(occupancy)-1;
    REQUIRE(hi_create(HI_ABI_VERSION,&launch,&instance) == HI_OK);
    uint64_t occupancy_deadline = now_ns() + UINT64_C(5000000000);
    do {
        REQUIRE(hi_service_turn(instance,1,1,now_ns(),&state) == HI_OK);
        if (state.stream_closed) break;
        struct pollfd fd = {state.descriptor,POLLIN|POLLHUP,0};
        REQUIRE(poll(&fd,1,10) >= 0);
    } while (now_ns() < occupancy_deadline);
    REQUIRE(state.stream_closed);
    hvt_cell wide_lead, wide_tail, sized_tail;
    REQUIRE(hi_copy_cell(instance,0,0,0,&wide_lead) == HI_OK);
    REQUIRE(hi_copy_cell(instance,0,0,1,&wide_tail) == HI_OK);
    REQUIRE(wide_lead.width == 2 && wide_lead.x == 0 && wide_tail.x == 1);
    REQUIRE(wide_lead.scalars[0] == 0x754c && wide_tail.scalars[0] == 0x754c);
    REQUIRE(hi_copy_cell(instance,0,2,3,&sized_tail) == HI_OK);
    REQUIRE(sized_tail.width == 4 && sized_tail.height == 2 && sized_tail.x == 3 && sized_tail.y == 1);
    hvt_interaction interaction;
    REQUIRE(hi_interaction(instance,&interaction) == HI_OK);
    REQUIRE(interaction.mouse_tracking == HVT_TRACK_ANY_EVENT && interaction.mouse_protocol == HVT_MOUSE_SGR_PIXEL);
    REQUIRE(interaction.flags == (HVT_INTERACTION_ALTERNATE_SCROLL | HVT_INTERACTION_FOCUS_REPORTING));
    uint8_t uri[64]; uri[0]=77; size_t required=0;
    REQUIRE(hi_copy_hyperlink(instance,0,0,1,80,0,uri,1,&required) == HI_BUFFER_TOO_SMALL);
    REQUIRE(uri[0] == 77 && required == strlen("https://example.invalid/x"));
    REQUIRE(hi_copy_hyperlink(instance,0,0,1,80,0,uri,sizeof(uri),&required) == HI_OK);
    REQUIRE(memcmp(uri,"https://example.invalid/x",required) == 0);
    REQUIRE(hi_destroy(&instance) == HI_OK);
    REQUIRE(memcmp(uri,"https://example.invalid/x",required) == 0);
    REQUIRE(sized_tail.scalar_count == 2 && sized_tail.scalars[0] == 'H' && sized_tail.scalars[1] == 'i');
    REQUIRE(wide_tail.x == 1 && wide_tail.scalars[0] == 0x754c);
    const char tall_wrap[] = "printf '\033]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\007abcde'; exit 0";
    launch.command.data=(const uint8_t *)tall_wrap; launch.command.len=sizeof(tall_wrap)-1;
    launch.rows=2; launch.columns=8; launch.history_rows=0;
    REQUIRE(hi_create(HI_ABI_VERSION,&launch,&instance) == HI_OK);
    uint64_t wrap_deadline=now_ns()+UINT64_C(5000000000);
    do {
        REQUIRE(hi_service_turn(instance,1,1,now_ns(),&state) == HI_OK);
        if (state.stream_closed) break;
        struct pollfd fd={state.descriptor,POLLIN|POLLHUP,0};
        REQUIRE(poll(&fd,1,10) >= 0);
    } while (now_ns() < wrap_deadline);
    REQUIRE(state.stream_closed);
    /* A regression to non-progressing traversal must fail this foreign process,
     * rather than hang its caller indefinitely. This deadline is proof-owned. */
    alarm(5);
    REQUIRE(hi_expand_selection(instance,HVT_SELECTION_WORD,0,0,4,8,0,&range) == HI_OK);
    alarm(0);
    REQUIRE(range.found && range.start_row == 0 && range.start_column == 0 && range.end_row == 1 && range.end_column == 4);
    REQUIRE(hi_copy_selection(instance,range.start_row,range.start_column,range.end_row,range.end_column,8,0,selected,sizeof(selected),&selected_len) == HI_OK);
    REQUIRE(selected_len == 7 && memcmp(selected,"Hiabcde",7) == 0);
    REQUIRE(hi_destroy(&instance) == HI_OK);
    return 0;
}
