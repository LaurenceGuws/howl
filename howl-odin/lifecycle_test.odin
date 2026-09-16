package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
lifecycle_reducer_distinguishes_connecting_active_closed_and_unavailable :: proc(t: ^testing.T) {
    testing.expect_value(t, session_lifecycle_state_values(0, 0, true, false, false), Session_Lifecycle_State.Connecting)
    testing.expect_value(t, session_lifecycle_state_values(9, 0, true, false, false), Session_Lifecycle_State.Active)
    testing.expect_value(t, session_lifecycle_state_values(9, 0, true, true, false), Session_Lifecycle_State.Closed)
    testing.expect_value(t, session_lifecycle_state_values(9, 0, true, false, true), Session_Lifecycle_State.Closed)
    testing.expect_value(t, session_lifecycle_state_values(9, 3, true, false, false), Session_Lifecycle_State.Unavailable)
    testing.expect_value(t, session_lifecycle_state_values(0, 0, false, false, false), Session_Lifecycle_State.Unavailable)
}

@(test)
failed_owned_launch_retains_owned_recovery_identity :: proc(t: ^testing.T) {
    view := allocate_session_view(nil, .Owned)
    testing.expect(t, view != nil)
    if view == nil do return
    defer destroy_session_view(view)
    publish_initial_error(view, "launch failed")
    testing.expect(t, session_is_owned(view))
    testing.expect_value(t, session_lifecycle_state(view), Session_Lifecycle_State.Unavailable)
    testing.expect(t, session_recoverable(view))
    testing.expect(t, !session_interactive(view))
}


@(test)
lifecycle_presentation_keeps_owned_and_attached_recovery_distinct :: proc(t: ^testing.T) {
    owned := session_lifecycle_presentation(.Closed, .Owned)
    testing.expect_value(t, owned.message, "Process exited")
    testing.expect_value(t, owned.action, "Restart")
    testing.expect(t, owned.recoverable)

    attached := session_lifecycle_presentation(.Unavailable, .Attached)
    testing.expect_value(t, attached.message, "Attached Session unavailable")
    testing.expect_value(t, attached.action, "Reconnect")
    testing.expect(t, attached.recoverable)

    active := session_lifecycle_presentation(.Active, .Owned)
    testing.expect(t, !active.visible)
    testing.expect(t, !active.recoverable)
}

@(test)
lifecycle_action_hit_stays_inside_status_bar :: proc(t: ^testing.T) {
    pane := SDL.FRect{20, 40, 800, 500}
    bar := session_lifecycle_bar_rect(pane)
    action := session_lifecycle_action_rect(pane)
    testing.expect(t, action.x >= bar.x)
    testing.expect(t, action.y >= bar.y)
    testing.expect(t, action.x + action.w <= bar.x + bar.w)
    testing.expect(t, action.y + action.h <= bar.y + bar.h)
}
