package main

import "core:c"
import "core:strings"
import "core:unicode/utf8"
import SDL "vendor:sdl3"

HYPERLINK_URI_BYTES :: 2048

browser_uri_allowed :: proc(uri: string) -> bool {
	if len(uri) == 0 || len(uri) > HYPERLINK_URI_BYTES || !utf8.valid_string(uri) {
		return false
	}
	for byte in transmute([]u8)uri {
		if byte <= 0x20 || byte == 0x7f {
			return false
		}
	}
	http := len(uri) > len("http://") && strings.equal_fold(uri[:len("http://")], "http://")
	https := len(uri) > len("https://") && strings.equal_fold(uri[:len("https://")], "https://")
	return http || https
}

open_platform_browser_uri :: proc(uri: string) -> bool {
	if !browser_uri_allowed(uri) {
		return false
	}
	terminated: [HYPERLINK_URI_BYTES + 1]u8
	copy(terminated[:len(uri)], transmute([]u8)uri)
	terminated[len(uri)] = 0
	return SDL.OpenURL(cstring(raw_data(terminated[:])))
}

open_hyperlink_at :: proc(
	app: ^App,
	view: ^Session_View,
	pane: SDL.FRect,
	x, y: f32,
) -> (handled: bool, opened: bool) {
	if app == nil || view == nil || view.control == nil || view.canvas == nil {
		return false, false
	}
	stable_row, column, columns, alternate, hit := selection_stable_point_at(
		app,
		view,
		pane,
		x,
		y,
	)
	if !hit {
		return false, false
	}
	uri_storage: [HYPERLINK_URI_BYTES]u8
	uri_len: c.size_t
	result := hyperlink_copy(
		view.control,
		render_history_offset(view.canvas),
		stable_row,
		column,
		columns,
		alternate ? u8(1) : u8(0),
		raw_data(uri_storage[:]),
		c.size_t(len(uri_storage)),
		&uri_len,
	)
	if result != 0 {
		copy_bridge_error(view)
		return true, false
	}
	if uri_len == 0 {
		return false, false
	}
	uri := string(uri_storage[:int(uri_len)])
	return true, open_platform_browser_uri(uri)
}
