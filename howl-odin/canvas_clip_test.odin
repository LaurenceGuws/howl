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

@(test)
canvas_reset_can_preserve_failure_diagnostic :: proc(t: ^testing.T) {
    view: Instance_View
    set_canvas_error(&view, "boom")
    testing.expect_value(t, view.canvas_error_len, 4)

    reset_canvas(&view, false)
    testing.expect_value(t, string(view.canvas_error[:view.canvas_error_len]), "boom")

    reset_canvas(&view)
    testing.expect_value(t, view.canvas_error_len, 0)
}

@(test)
canvas_renderer_restart_keeps_only_last_accepted_frame :: proc(t: ^testing.T) {
    view: Instance_View
    view.canvas_commands = make([]Canvas_Command_Info, 1)
    view.canvas_scale = 1
    view.canvas_frame_font_pixels = 15
    view.canvas_frame_background_rgba = 0x112233ff
    view.canvas_surface_width = 640
    view.canvas_surface_height = 480
    view.canvas_frame_revision = 9
    view.canvas_font_pixels = 15
    view.canvas_worker_has_frame = true

    testing.expect(t, canvas_frame_available(&view))
    restart_canvas_renderer(&view)

    testing.expect(t, canvas_frame_available(&view))
    testing.expect_value(t, len(view.canvas_commands), 1)
    testing.expect_value(t, view.canvas_scale, f32(1))
    testing.expect_value(t, view.canvas_frame_font_pixels, u16(15))
    testing.expect_value(t, view.canvas_frame_background_rgba, u32(0x112233ff))
    testing.expect_value(t, view.canvas_surface_width, u16(640))
    testing.expect_value(t, view.canvas_surface_height, u16(480))
    testing.expect_value(t, view.canvas_frame_revision, u64(9))
    testing.expect_value(t, view.canvas_font_pixels, u16(0))
    testing.expect(t, !view.canvas_worker_has_frame)
    testing.expect(t, !canvas_frame_current(&view))

    reset_canvas(&view)
    testing.expect(t, !canvas_frame_available(&view))
    testing.expect_value(t, len(view.canvas_commands), 0)
    testing.expect_value(t, view.canvas_surface_width, u16(0))
    testing.expect_value(t, view.canvas_surface_height, u16(0))
}
