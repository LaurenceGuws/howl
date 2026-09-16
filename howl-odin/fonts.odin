package main

import "core:os"
import "core:strings"

FONT_PATH_BYTES :: 4096

Desktop_Fonts :: struct {
	primary: [FONT_PATH_BYTES]u8,
	primary_len: int,
	fallback: [FONT_PATH_BYTES]u8,
	fallback_len: int,
	secondary: [FONT_PATH_BYTES]u8,
	secondary_len: int,
}

font_path :: proc(storage: []u8, used: int) -> string {
	if used <= 0 || used > len(storage) do return ""
	return string(storage[:used])
}

terminal_primary_font :: proc(fonts: ^Desktop_Fonts) -> string {
	if fonts == nil do return ""
	return font_path(fonts.primary[:], fonts.primary_len)
}

terminal_fallback_font :: proc(fonts: ^Desktop_Fonts) -> string {
	if fonts == nil do return ""
	return font_path(fonts.fallback[:], fonts.fallback_len)
}

terminal_secondary_fallback_font :: proc(fonts: ^Desktop_Fonts) -> string {
	if fonts == nil do return ""
	return font_path(fonts.secondary[:], fonts.secondary_len)
}

copy_font_path :: proc(output: []u8, used: ^int, path: string) -> bool {
	if used == nil || len(path) == 0 || len(path) >= len(output) || !os.exists(path) {
		return false
	}
	copy(output[:len(path)], transmute([]u8)path)
	used^ = len(path)
	return true
}

fontconfig_output_path :: proc(text, family: string) -> (path: string, ok: bool) {
	if len(text) == 0 || len(family) == 0 {
		return "", false
	}
	first_break := strings.index_byte(text, '\n')
	if first_break <= 0 {
		return "", false
	}
	family_line := text[:first_break]
	if !strings.contains(family_line, family) {
		return "", false
	}
	rest := text[first_break + 1:]
	second_break := strings.index_byte(rest, '\n')
	path = second_break < 0 ? rest : rest[:second_break]
	return path, len(path) != 0
}

fontconfig_result :: proc(family: string) -> (path: string, ok: bool) {
	command := []string{"fc-match", "-f", "%{family}\n%{file}\n", family}
	state, stdout, _, err := os.process_exec(
		os.Process_Desc{command = command},
		context.temp_allocator,
	)
	if err != nil || !state.success {
		return "", false
	}
	resolved, parsed := fontconfig_output_path(string(stdout), family)
	if !parsed || !os.exists(resolved) {
		return "", false
	}
	return resolved, true
}

configured_font :: proc(variable, family: string) -> (string, bool) {
	configured := os.get_env(variable, context.temp_allocator)
	if len(configured) != 0 {
		return configured, os.exists(configured)
	}
	return fontconfig_result(family)
}

resolve_desktop_fonts :: proc(fonts: ^Desktop_Fonts) -> (message: string, ok: bool) {
	if fonts == nil do return "font_storage", false
	fonts^ = {}
	primary, primary_ok := configured_font("HOWL_FONT", "JetBrainsMono Nerd Font")
	if !primary_ok || !copy_font_path(fonts.primary[:], &fonts.primary_len, primary) {
		return "primary_font_missing", false
	}
	fallback, fallback_ok := configured_font("HOWL_FALLBACK_FONT", "Noto Sans Arabic")
	if !fallback_ok || !copy_font_path(fonts.fallback[:], &fonts.fallback_len, fallback) {
		return "fallback_font_missing", false
	}
	secondary, secondary_ok := configured_font("HOWL_SECONDARY_FALLBACK_FONT", "Noto Sans CJK JP")
	if !secondary_ok || !copy_font_path(fonts.secondary[:], &fonts.secondary_len, secondary) {
		return "secondary_fallback_font_missing", false
	}
	return "", true
}
