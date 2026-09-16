package main

import "core:c"
import "core:math"
import "core:testing"

@(test)
display_scale_keeps_logical_font_identity_at_one_x :: proc(t: ^testing.T) {
    pixels, ok := scaled_canvas_font_pixels(15, 1)
    testing.expect(t, ok)
    testing.expect_value(t, pixels, u16(15))
}

@(test)
display_scale_rounds_terminal_raster_to_backing_pixels :: proc(t: ^testing.T) {
    pixels_150, ok_150 := scaled_canvas_font_pixels(15, 1.5)
    pixels_200, ok_200 := scaled_canvas_font_pixels(15, 2)
    pixels_fraction, ok_fraction := scaled_canvas_font_pixels(18, 1.25)
    testing.expect(t, ok_150)
    testing.expect(t, ok_200)
    testing.expect(t, ok_fraction)
    testing.expect_value(t, pixels_150, u16(23))
    testing.expect_value(t, pixels_200, u16(30))
    testing.expect_value(t, pixels_fraction, u16(23))
}

@(test)
display_scale_rejects_invalid_or_hostile_values :: proc(t: ^testing.T) {
    _, zero_ok := scaled_canvas_font_pixels(15, 0)
    _, negative_ok := scaled_canvas_font_pixels(15, -1)
    _, huge_ok := scaled_canvas_font_pixels(15, CANVAS_SCALE_MAX + 1)
    _, zero_font_ok := scaled_canvas_font_pixels(0, 1)
    testing.expect(t, !zero_ok)
    testing.expect(t, !negative_ok)
    testing.expect(t, !huge_ok)
    testing.expect(t, !zero_font_ok)
}

@(test)
display_scale_maps_sdl_ttf_dpi_from_logical_points :: proc(t: ^testing.T) {
    dpi_100, ok_100 := scaled_text_dpi(1)
    dpi_150, ok_150 := scaled_text_dpi(1.5)
    dpi_200, ok_200 := scaled_text_dpi(2)
    testing.expect(t, ok_100)
    testing.expect(t, ok_150)
    testing.expect(t, ok_200)
    testing.expect_value(t, dpi_100, c.int(72))
    testing.expect_value(t, dpi_150, c.int(108))
    testing.expect_value(t, dpi_200, c.int(144))
}

@(test)
display_scale_rejects_invalid_sdl_ttf_dpi :: proc(t: ^testing.T) {
    _, zero_ok := scaled_text_dpi(0)
    _, nan_ok := scaled_text_dpi(math.nan_f32())
    _, huge_ok := scaled_text_dpi(CANVAS_SCALE_MAX + 1)
    testing.expect(t, !zero_ok)
    testing.expect(t, !nan_ok)
    testing.expect(t, !huge_ok)
}
