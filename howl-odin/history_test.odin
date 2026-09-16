package main

import "core:testing"

@(test)
history_scroll_rows_clamps_and_tracks_anchor :: proc(t: ^testing.T) {
    view := Session_View{
        history_count = 100,
        history_row_base = 50,
    }

    testing.expect(t, scroll_history_rows(&view, 20))
    testing.expect_value(t, view.history_target_offset, u32(20))
    testing.expect_value(t, view.history_anchor_top_row, u64(130))
    testing.expect(t, view.history_anchor_valid)

    testing.expect(t, scroll_history_rows(&view, -5))
    testing.expect_value(t, view.history_target_offset, u32(15))
    testing.expect_value(t, view.history_anchor_top_row, u64(135))

    testing.expect(t, scroll_history_rows(&view, 1000))
    testing.expect_value(t, view.history_target_offset, u32(100))
    testing.expect_value(t, view.history_anchor_top_row, u64(50))

    testing.expect(t, scroll_history_rows(&view, -1000))
    testing.expect_value(t, view.history_target_offset, u32(0))
    testing.expect_value(t, view.history_anchor_top_row, u64(0))
    testing.expect(t, !view.history_anchor_valid)
}

@(test)
history_follow_live_preserves_absolute_top_row :: proc(t: ^testing.T) {
    view := Session_View{
        history_count = 100,
        history_row_base = 50,
        history_target_offset = 20,
        history_anchor_top_row = 130,
        history_anchor_valid = true,
    }

    follow_history_locked(&view, 110, 50, false)
    testing.expect_value(t, view.history_target_offset, u32(30))
    testing.expect_value(t, view.history_anchor_top_row, u64(130))
    testing.expect(t, view.history_anchor_valid)
}

@(test)
history_follow_live_clamps_to_oldest_retained_row_after_eviction :: proc(t: ^testing.T) {
    view := Session_View{
        history_count = 100,
        history_row_base = 50,
        history_target_offset = 20,
        history_anchor_top_row = 130,
        history_anchor_valid = true,
    }

    follow_history_locked(&view, 50, 140, false)
    testing.expect_value(t, view.history_target_offset, u32(50))
    testing.expect_value(t, view.history_anchor_top_row, u64(140))
    testing.expect(t, view.history_anchor_valid)
}

@(test)
history_follow_live_resets_for_alternate_screen :: proc(t: ^testing.T) {
    view := Session_View{
        history_count = 100,
        history_row_base = 50,
        history_target_offset = 20,
        history_anchor_top_row = 130,
        history_anchor_valid = true,
    }

    follow_history_locked(&view, 100, 50, true)
    testing.expect_value(t, view.history_target_offset, u32(0))
    testing.expect_value(t, view.history_anchor_top_row, u64(0))
    testing.expect(t, !view.history_anchor_valid)
}

@(test)
history_accept_snapshot_uses_server_clamp :: proc(t: ^testing.T) {
    view: Session_View
    accept_history_snapshot(&view, 150, 100, 40, false)
    testing.expect_value(t, view.history_target_offset, u32(100))
    testing.expect_value(t, view.history_anchor_top_row, u64(40))
    testing.expect(t, view.history_anchor_valid)

    accept_history_snapshot(&view, 0, 100, 40, false)
    testing.expect_value(t, view.history_target_offset, u32(0))
    testing.expect(t, !view.history_anchor_valid)
}

@(test)
history_scrollbar_geometry_maps_oldest_middle_and_live :: proc(t: ^testing.T) {
    live_top, height, ok := history_scrollbar_thumb(0, 100, 25, 200)
    testing.expect(t, ok)
    testing.expect_value(t, height, f32(40))
    testing.expect_value(t, live_top, f32(160))

    middle_top, middle_height, middle_ok := history_scrollbar_thumb(50, 100, 25, 200)
    testing.expect(t, middle_ok)
    testing.expect_value(t, middle_height, f32(40))
    testing.expect_value(t, middle_top, f32(80))

    oldest_top, oldest_height, oldest_ok := history_scrollbar_thumb(100, 100, 25, 200)
    testing.expect(t, oldest_ok)
    testing.expect_value(t, oldest_height, f32(40))
    testing.expect_value(t, oldest_top, f32(0))

    testing.expect_value(t, history_offset_for_scrollbar_thumb(0, 200, 40, 100), u32(100))
    testing.expect_value(t, history_offset_for_scrollbar_thumb(80, 200, 40, 100), u32(50))
    testing.expect_value(t, history_offset_for_scrollbar_thumb(160, 200, 40, 100), u32(0))
}

@(test)
history_reset_does_not_steal_pointer_drag_lifecycle :: proc(t: ^testing.T) {
    view := Session_View{
        history_target_offset = 12,
        history_anchor_top_row = 88,
        history_anchor_valid = true,
        history_scrollbar_dragging = true,
        history_scrollbar_grab_y = 7,
    }
    reset_history_locked(&view)
    testing.expect_value(t, view.history_target_offset, u32(0))
    testing.expect(t, !view.history_anchor_valid)
    testing.expect(t, view.history_scrollbar_dragging)
    testing.expect_value(t, view.history_scrollbar_grab_y, f32(7))
}

@(test)
history_horizontal_geometry_change_returns_to_live :: proc(t: ^testing.T) {
    view := Session_View{
        columns = 120,
        history_count = 300,
        history_target_offset = 140,
        history_anchor_top_row = 160,
        history_anchor_valid = true,
        history_scrollbar_dragging = true,
    }
    apply_history_geometry_locked(&view, 60)
    testing.expect_value(t, view.history_target_offset, u32(0))
    testing.expect(t, !view.history_anchor_valid)
    testing.expect(t, view.history_scrollbar_dragging)
}

@(test)
history_same_columns_preserve_anchor :: proc(t: ^testing.T) {
    view := Session_View{
        columns = 120,
        history_target_offset = 140,
        history_anchor_top_row = 160,
        history_anchor_valid = true,
    }
    apply_history_geometry_locked(&view, 120)
    testing.expect_value(t, view.history_target_offset, u32(140))
    testing.expect_value(t, view.history_anchor_top_row, u64(160))
    testing.expect(t, view.history_anchor_valid)
}

@(test)
history_column_change_detection_ignores_unknown_and_same_geometry :: proc(t: ^testing.T) {
    testing.expect(t, !history_columns_changed(0, 80))
    testing.expect(t, !history_columns_changed(80, 80))
    testing.expect(t, history_columns_changed(80, 120))
}
