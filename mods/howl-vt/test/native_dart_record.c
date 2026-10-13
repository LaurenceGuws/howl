#include "howl_vt_native.h"
#include <stdio.h>
#include <stddef.h>
_Static_assert(HVT_NATIVE_VERSION == 1, "review Dart binding for a new VT ABI");
_Static_assert(sizeof(hvt_interaction) == 16, "native interaction layout");
_Static_assert(offsetof(hvt_interaction, flags) == 8, "flags offset");
_Static_assert(offsetof(hvt_interaction, mouse_tracking) == 12, "tracking offset");
_Static_assert(offsetof(hvt_interaction, mouse_protocol) == 13, "protocol offset");
_Static_assert(offsetof(hvt_interaction, pointer_mode) == 14, "pointer offset");
_Static_assert(offsetof(hvt_interaction, _reserved) == 15, "reserved offset");
int main(void) {
    hvt_interaction record = {0};
    record.terminal_revision = UINT64_C(0x1122334455667788);
    record.flags = HVT_INTERACTION_ALTERNATE_SCROLL | HVT_INTERACTION_FOCUS_REPORTING;
    record.mouse_tracking = HVT_TRACK_ANY_EVENT;
    record.mouse_protocol = HVT_MOUSE_SGR_PIXEL;
    record.pointer_mode = 2;
    return fwrite(&record, sizeof(record), 1, stdout) != 1;
}
