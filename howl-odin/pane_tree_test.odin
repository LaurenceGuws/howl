package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
pane_tree_nests_layout_without_moving_session_slots :: proc(t: ^testing.T) {
    tab: Tab
    first_view := new(Session_View)
    second_view := new(Session_View)
    third_view := new(Session_View)
    testing.expect(t, first_view != nil && second_view != nil && third_view != nil)
    if first_view == nil || second_view == nil || third_view == nil do return
    defer free(first_view)
    defer free(second_view)
    defer free(third_view)

    tab.root = new_pane_leaf(0)
    testing.expect(t, tab.root != nil)
    if tab.root == nil do return
    defer destroy_pane_nodes(tab.root)
    tab.panes[0] = first_view
    tab.pane_count = 1
    tab.active_pane = 0

    second_index, ok := split_pane_slot(&tab, 0, second_view, .Vertical)
    testing.expect(t, ok)
    testing.expect_value(t, second_index, 1)
    third_index: int
    third_index, ok = split_pane_slot(&tab, second_index, third_view, .Horizontal)
    testing.expect(t, ok)
    testing.expect_value(t, third_index, 2)
    testing.expect_value(t, tab.pane_count, 3)
    testing.expect(t, tab.panes[0] == first_view)
    testing.expect(t, tab.panes[1] == second_view)
    testing.expect(t, tab.panes[2] == third_view)

    layout := pane_layout(&tab, SDL.FRect{0, 0, 1000, 600})
    testing.expect_value(t, layout.entry_count, 3)
    testing.expect_value(t, layout.divider_count, 2)
    left, left_ok := pane_rect_from_layout(&layout, 0)
    upper_right, upper_ok := pane_rect_from_layout(&layout, 1)
    lower_right, lower_ok := pane_rect_from_layout(&layout, 2)
    testing.expect(t, left_ok && upper_ok && lower_ok)
    testing.expect(t, abs(left.w - upper_right.w) < 0.01)
    testing.expect(t, upper_right.x > left.x + left.w)
    testing.expect(t, upper_right.h < left.h)
    testing.expect(t, lower_right.y > upper_right.y + upper_right.h)
}

@(test)
pane_tree_close_promotes_sibling_subtree_and_keeps_survivor_identity :: proc(t: ^testing.T) {
    tab: Tab
    views: [3]^Session_View
    for index in 0..<3 {
        views[index] = new(Session_View)
        testing.expect(t, views[index] != nil)
        if views[index] == nil do return
        defer free(views[index])
    }
    tab.root = new_pane_leaf(0)
    testing.expect(t, tab.root != nil)
    if tab.root == nil do return
    defer destroy_pane_nodes(tab.root)
    tab.panes[0] = views[0]
    tab.pane_count = 1

    second, ok := split_pane_slot(&tab, 0, views[1], .Vertical)
    testing.expect(t, ok)
    third: int
    third, ok = split_pane_slot(&tab, second, views[2], .Vertical)
    testing.expect(t, ok)
    testing.expect_value(t, tab.pane_count, 3)

    removed: ^Session_View
    removed, ok = remove_pane_slot(&tab, second)
    testing.expect(t, ok)
    testing.expect(t, removed == views[1])
    testing.expect_value(t, tab.pane_count, 2)
    testing.expect(t, pane_leaf_for_index(tab.root, 0) != nil)
    testing.expect(t, pane_leaf_for_index(tab.root, third) != nil)
    testing.expect(t, pane_leaf_for_index(tab.root, second) == nil)
    testing.expect_value(t, tab.active_pane, third)

    removed, ok = remove_pane_slot(&tab, third)
    testing.expect(t, ok)
    testing.expect(t, removed == views[2])
    testing.expect_value(t, tab.pane_count, 1)
    testing.expect(t, tab.root.kind == .Leaf)
    testing.expect_value(t, tab.root.pane_index, 0)
    testing.expect_value(t, tab.active_pane, 0)
}
