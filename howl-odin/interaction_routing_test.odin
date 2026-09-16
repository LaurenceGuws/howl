package main

import "core:testing"

@(test)
primary_pointer_routing_gives_history_and_shift_local_precedence :: proc(t: ^testing.T) {
    testing.expect_value(t, route_desktop_primary_pointer(true, false, true, true), Desktop_Primary_Pointer_Route.Local_Selection)
    testing.expect_value(t, route_desktop_primary_pointer(false, true, true, true), Desktop_Primary_Pointer_Route.Local_Selection)
    testing.expect_value(t, route_desktop_primary_pointer(false, false, false, false), Desktop_Primary_Pointer_Route.Interaction_State)
    testing.expect_value(t, route_desktop_primary_pointer(false, false, true, true), Desktop_Primary_Pointer_Route.Terminal_Mouse)
    testing.expect_value(t, route_desktop_primary_pointer(false, false, true, false), Desktop_Primary_Pointer_Route.Local_Selection)
}

@(test)
wheel_routing_follows_history_mouse_and_alternate_scroll :: proc(t: ^testing.T) {
    testing.expect_value(t, route_desktop_wheel(true, false, true, true, true, true), Desktop_Wheel_Route.History)
    testing.expect_value(t, route_desktop_wheel(false, true, true, true, true, true), Desktop_Wheel_Route.History)
    testing.expect_value(t, route_desktop_wheel(false, false, false, false, false, false), Desktop_Wheel_Route.Interaction_State)
    testing.expect_value(t, route_desktop_wheel(false, false, true, true, true, false), Desktop_Wheel_Route.Terminal_Mouse)
    testing.expect_value(t, route_desktop_wheel(false, false, true, false, false, false), Desktop_Wheel_Route.History)
    testing.expect_value(t, route_desktop_wheel(false, false, true, false, true, true), Desktop_Wheel_Route.Alternate_Scroll)
    testing.expect_value(t, route_desktop_wheel(false, false, true, false, true, false), Desktop_Wheel_Route.Ignore)
}

@(test)
interaction_info_flags_are_small_routing_facts :: proc(t: ^testing.T) {
    state := Interaction_State_Info{flags = INTERACTION_ALT_SCROLL | INTERACTION_FOCUS_REPORTING, mouse_tracking = 2}
    testing.expect(t, interaction_mouse_tracking_enabled(state))
    testing.expect(t, interaction_alternate_scroll(state))
    testing.expect(t, interaction_focus_reporting(state))
    testing.expect(t, !interaction_mouse_tracking_enabled(Interaction_State_Info{}))
}
