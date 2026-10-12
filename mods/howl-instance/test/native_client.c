#define _POSIX_C_SOURCE 200809L
#include "howl_instance_native.h"
#include <poll.h>
#include <string.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>

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
extern int howl_instance_cpp_header(void);
int main(void) {
    REQUIRE(howl_instance_cpp_header() == 0);
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
    hvt_cell copied;
    REQUIRE(hi_copy_cell(instance,0,0,0,&copied) == HI_OK);
    REQUIRE(hi_destroy(&instance) == HI_OK && instance == NULL);
    REQUIRE(copied.scalar_count > 0 && copied.scalars[0] == 'R');
    REQUIRE(hi_destroy(&instance) == HI_OK);
    shell[1] = 'b';
    const char occupancy[] = "printf '\347\225\214\033[2;1H\033]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\007'; exit 0";
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
    REQUIRE(hi_destroy(&instance) == HI_OK);
    REQUIRE(sized_tail.scalar_count == 2 && sized_tail.scalars[0] == 'H' && sized_tail.scalars[1] == 'i');
    REQUIRE(wide_tail.x == 1 && wide_tail.scalars[0] == 0x754c);
    return 0;
}
