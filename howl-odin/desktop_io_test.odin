package main
import "core:testing"

@(test)
control_queue_is_fifo_bounded_and_does_not_replay_after_stop :: proc(t: ^testing.T) {
    view: Session_View
    for i in 0..<CONTROL_QUEUE_ITEMS {
        testing.expect(t, control_queue_push_locked(&view, {kind = .Unicode, scalar = u32(i)}))
    }
    testing.expect(t, !control_queue_push_locked(&view, {kind = .Text}))
    for i in 0..<CONTROL_QUEUE_ITEMS {
        task, ok := control_queue_pop_locked(&view)
        testing.expect(t, ok)
        testing.expect_value(t, task.scalar, u32(i))
    }
    _, present := control_queue_pop_locked(&view)
    testing.expect(t, !present)
    view.worker_stop = true
    testing.expect(t, !control_queue_push_locked(&view, {kind = .Named}))
    testing.expect_value(t, view.control_count, 0)
}

@(test)
control_queue_bytes_are_bounded_separately_from_event_count :: proc(t: ^testing.T) {
    view: Session_View
    payload: [65535]u8
    testing.expect(t, control_queue_push_locked(&view, {kind = .Paste, payload = payload[:]}))
    testing.expect(t, control_queue_push_locked(&view, {kind = .Paste, payload = payload[:]}))
    testing.expect(t, !control_queue_push_locked(&view, {kind = .Paste, payload = payload[:3]}))
    testing.expect_value(t, view.control_bytes, 131070)
    _, removed := control_queue_pop_locked(&view)
    testing.expect(t, removed)
    testing.expect(t, control_queue_push_locked(&view, {kind = .Paste, payload = payload[:3]}))
    view.io_failed = true
    testing.expect(t, !control_queue_push_locked(&view, {kind = .Named}))
}

@(test)
async_selection_and_clipboard_results_require_current_view_intent :: proc(t: ^testing.T) {
    testing.expect(t, control_result_current(0, 4, 4, true))
    testing.expect(t, !control_result_current(0, 4, 5, true))
    testing.expect(t, !control_result_current(0, 4, 4, false))
    testing.expect(t, !control_result_current(2, 4, 4, true))
}


@(test)
clipboard_requests_are_ordered_independently_from_selection_motion :: proc(t: ^testing.T) {
    testing.expect(t, clipboard_request_current(7, 7, 7))
    testing.expect(t, !clipboard_request_current(7, 8, 7))
    testing.expect(t, !clipboard_request_current(7, 7, 6))
    testing.expect(t, !clipboard_request_current(0, 0, 0))
}


@(test)
completed_query_decline_preserves_input_but_transport_failure_does_not :: proc(t: ^testing.T) {
    kinds := [4]Control_Kind{.Expand, .Extract, .Link, .Clipboard}
    for kind in kinds {
        testing.expect(t, !control_failure_is_fatal(kind, BRIDGE_QUERY_DECLINED))
        testing.expect(t, control_failure_is_fatal(kind, 4))
        testing.expect(t, !control_failure_is_fatal(kind, 0))
    }
    testing.expect(t, control_failure_is_fatal(.Text, BRIDGE_QUERY_DECLINED))
    testing.expect(t, control_failure_is_fatal(.Paste, 2))
}

@(test)
selection_motion_after_copy_does_not_erase_newer_range :: proc(t: ^testing.T) {
    view := Session_View{selection_generation = 10, selection_focus_row = 3, selection_focus_column = 8}
    issued := view.selection_generation
    testing.expect(t, !extend_selection_focus_locked(&view, 3, 8))
    testing.expect_value(t, view.selection_generation, issued)
    testing.expect(t, extend_selection_focus_locked(&view, 3, 12))
    testing.expect(t, !control_result_current(0, issued, view.selection_generation, true))
    testing.expect(t, clipboard_request_current(7, 7, 7))
    testing.expect_value(t, view.selection_focus_column, u16(12))
}
