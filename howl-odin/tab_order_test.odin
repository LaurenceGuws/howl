package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
tab_move_preserves_order_and_active_identity :: proc(t: ^testing.T) {
    app: App
    app.tab_count = 4
    app.active_tab = 1
    app.tabs[0].title = "A"
    app.tabs[1].title = "B"
    app.tabs[2].title = "C"
    app.tabs[3].title = "D"

    testing.expect(t, move_tab(&app, 1, 3))
    testing.expect_value(t, app.tabs[0].title, "A")
    testing.expect_value(t, app.tabs[1].title, "C")
    testing.expect_value(t, app.tabs[2].title, "D")
    testing.expect_value(t, app.tabs[3].title, "B")
    testing.expect_value(t, app.active_tab, 3)

    testing.expect(t, move_tab(&app, 0, 2))
    testing.expect_value(t, app.tabs[0].title, "C")
    testing.expect_value(t, app.tabs[1].title, "D")
    testing.expect_value(t, app.tabs[2].title, "A")
    testing.expect_value(t, app.tabs[3].title, "B")
    testing.expect_value(t, app.active_tab, 3)

    testing.expect(t, move_tab(&app, 3, 1))
    testing.expect_value(t, app.tabs[0].title, "C")
    testing.expect_value(t, app.tabs[1].title, "B")
    testing.expect_value(t, app.tabs[2].title, "D")
    testing.expect_value(t, app.tabs[3].title, "A")
    testing.expect_value(t, app.active_tab, 1)
}

@(test)
tab_reorder_target_tracks_nearest_tab_center :: proc(t: ^testing.T) {
    testing.expect_value(t, tab_reorder_target(TAB_X, 4), 0)
    testing.expect_value(t, tab_reorder_target(TAB_X + TAB_STEP * 0.6, 4), 1)
    testing.expect_value(t, tab_reorder_target(TAB_X + TAB_STEP * 1.6, 4), 2)
    testing.expect_value(t, tab_reorder_target(-1000, 4), 0)
    testing.expect_value(t, tab_reorder_target(10000, 4), 3)
}

@(test)
numeric_tab_keys_are_direct_and_bounded :: proc(t: ^testing.T) {
    keys := [8]SDL.Keycode{
        SDL.K_1, SDL.K_2, SDL.K_3, SDL.K_4,
        SDL.K_5, SDL.K_6, SDL.K_7, SDL.K_8,
    }
    for key, expected in keys {
        index, ok := tab_index_for_number_key(key)
        testing.expect(t, ok)
        testing.expect_value(t, index, expected)
    }
    _, ok := tab_index_for_number_key(SDL.K_9)
    testing.expect(t, !ok)
}

@(test)
close_last_single_pane_requests_window_shutdown :: proc(t: ^testing.T) {
    app: App
    app.running = true
    app.tab_count = 1
    app.active_tab = 0
    app.tabs[0].pane_count = 1
    close_active_pane(&app)
    testing.expect(t, !app.running)
    testing.expect_value(t, app.tab_count, 1)
}
