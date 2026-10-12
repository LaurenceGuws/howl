package main

import "core:testing"
import vt_native "../../mods/howl-vt/bindings/odin"

@(test)
native_query_layout :: proc(t: ^testing.T) {
    testing.expect(t, size_of(vt_native.Search_Match_Info) == 32)
    testing.expect(t, offset_of(vt_native.Search_Match_Info, scanned_snapshots) == 24)
    testing.expect(t, size_of(vt_native.Selection_Range_Info) == 20)
    testing.expect(t, offset_of(vt_native.Selection_Range_Info, _reserved) == 16)
    testing.expect(t, size_of(vt_native.Interaction_State_Info) == 16)
    testing.expect(t, offset_of(vt_native.Interaction_State_Info, mouse_tracking) == 12)
    testing.expect(t, size_of(vt_native.Row_Shape) == 4)
}
