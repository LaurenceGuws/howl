package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
contained_texture_quads_share_pane_scissor_without_changing_geometry :: proc(t: ^testing.T) {
    pane := SDL.Rect{0, 46, 960, 700}
    cell := SDL.Rect{106, 102, 11, 24}
    cases := [4]SDL.FRect{
        {107, 103, 9, 22}, {106, 102, 11, 24},
        {106.25, 102.5, 10.5, 23}, {106, 102, 0, 0},
    }
    for destination in cases {
        testing.expect_value(t, canvas_effective_clip(destination, cell, pane), pane)
    }
}

@(test)
overhanging_glyphs_and_cropped_images_keep_their_requested_scissor :: proc(t: ^testing.T) {
    pane := SDL.Rect{0, 46, 960, 700}
    clip := SDL.Rect{106, 102, 11, 24}
    cases := [5]SDL.FRect{
        {105.5, 102, 11, 24}, {106, 101.5, 11, 24},
        {106, 102, 11.5, 24}, {106, 102, 11, 24.5},
        {-100, 46, 640, 400},
    }
    for destination in cases {
        testing.expect_value(t, canvas_effective_clip(destination, clip, pane), clip)
    }
}
