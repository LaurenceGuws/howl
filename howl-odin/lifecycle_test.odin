package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
lifecycle_reducer_distinguishes_connecting_active_closed_and_unavailable :: proc(t: ^testing.T) {
    testing.expect_value(t, instance_lifecycle_state_values(0, 0, true, false, false), Instance_Lifecycle_State.Connecting)
    testing.expect_value(t, instance_lifecycle_state_values(9, 0, true, false, false), Instance_Lifecycle_State.Active)
    testing.expect_value(t, instance_lifecycle_state_values(9, 0, true, true, false), Instance_Lifecycle_State.Closed)
    testing.expect_value(t, instance_lifecycle_state_values(9, 0, true, false, true), Instance_Lifecycle_State.Closed)
    testing.expect_value(t, instance_lifecycle_state_values(9, 3, true, false, false), Instance_Lifecycle_State.Unavailable)
    testing.expect_value(t, instance_lifecycle_state_values(0, 0, false, false, false), Instance_Lifecycle_State.Unavailable)
}

@(test)
failed_owned_launch_retains_owned_recovery_identity :: proc(t: ^testing.T) {
    view := allocate_instance_view(.Owned)
    testing.expect(t, view != nil)
    if view == nil do return
    defer destroy_instance_view(view)
    publish_initial_error(view, "launch failed")
    testing.expect(t, instance_is_owned(view))
    testing.expect_value(t, instance_lifecycle_state(view), Instance_Lifecycle_State.Unavailable)
    testing.expect(t, instance_recoverable(view))
    testing.expect(t, !instance_interactive(view))
}


@(test)
lifecycle_presentation_keeps_owned_and_attached_recovery_distinct :: proc(t: ^testing.T) {
    owned := instance_lifecycle_presentation(.Closed, .Owned)
    testing.expect_value(t, owned.message, "Process exited")
    testing.expect_value(t, owned.action, "Restart")
    testing.expect(t, owned.recoverable)

    attached := instance_lifecycle_presentation(.Unavailable, .Attached)
    testing.expect_value(t, attached.message, "Attached Instance unavailable")
    testing.expect_value(t, attached.action, "Reconnect")
    testing.expect(t, attached.recoverable)

    active := instance_lifecycle_presentation(.Active, .Owned)
    testing.expect(t, !active.visible)
    testing.expect(t, !active.recoverable)
}

@(test)
lifecycle_action_hit_stays_inside_status_bar :: proc(t: ^testing.T) {
    pane := SDL.FRect{20, 40, 800, 500}
    bar := instance_lifecycle_bar_rect(pane)
    action := instance_lifecycle_action_rect(pane)
    testing.expect(t, action.x >= bar.x)
    testing.expect(t, action.y >= bar.y)
    testing.expect(t, action.x + action.w <= bar.x + bar.w)
    testing.expect(t, action.y + action.h <= bar.y + bar.h)
}


@(test)
startup_arguments_separate_information_from_window_lifecycle :: proc(t: ^testing.T) {
    testing.expect_value(t, startup_intent(nil), Startup_Intent.Run)
    testing.expect_value(t, startup_intent([]string{"--help"}), Startup_Intent.Help)
    testing.expect_value(t, startup_intent([]string{"-h"}), Startup_Intent.Help)
    testing.expect_value(t, startup_intent([]string{"--version"}), Startup_Intent.Version)
    testing.expect_value(t, startup_intent([]string{"--server", "tcp://127.0.0.1:43130", "7", "3"}), Startup_Intent.Server)
    target, ok := startup_server_target([]string{"--server", "tcp://127.0.0.1:43130", "7", "3"})
    testing.expect(t, ok)
    testing.expect_value(t, target.endpoint, "tcp://127.0.0.1:43130")
    testing.expect_value(t, target.session_id, u64(7))
    testing.expect_value(t, target.instance_id, u64(3))
    invalid := [6][]string{{""}, {"--unknown"}, {"file"}, {"--help", "file"}, {"--server", "tcp://127.0.0.1:1", "0", "1"}, {"--server", "tcp://127.0.0.1:1", "x", "1"}}
    for args in invalid {
        testing.expect_value(t, startup_intent(args), Startup_Intent.Invalid)
    }
}
