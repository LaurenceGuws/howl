package main

import "core:testing"

@(test)
desktop_font_path_copy_is_bounded_and_requires_real_files :: proc(t: ^testing.T) {
	storage: [FONT_PATH_BYTES]u8
	used := 0
	testing.expect(t, !copy_font_path(storage[:], &used, "/definitely/missing/howl-font.ttf"))
	testing.expect_value(t, used, 0)
}

@(test)
desktop_fontconfig_parser_accepts_exact_family_and_path :: proc(t: ^testing.T) {
	path, ok := fontconfig_output_path(
		"Noto Sans CJK JP,Noto Sans CJK JP Medium\n/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc\n",
		"Noto Sans CJK JP",
	)
	testing.expect(t, ok)
	testing.expect_value(t, path, "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc")
}

@(test)
desktop_fontconfig_parser_rejects_silent_family_substitution :: proc(t: ^testing.T) {
	_, ok := fontconfig_output_path(
		"DejaVu Sans\n/usr/share/fonts/TTF/DejaVuSans.ttf\n",
		"Noto Sans Arabic",
	)
	testing.expect(t, !ok)
}

@(test)
desktop_fontconfig_parser_rejects_missing_path_line :: proc(t: ^testing.T) {
	_, ok := fontconfig_output_path("Noto Sans Arabic\n", "Noto Sans Arabic")
	testing.expect(t, !ok)
}

@(test)
desktop_fontconfig_style_parser_requires_family_style_and_path :: proc(t: ^testing.T) {
	path, ok := fontconfig_style_output_path(
		"JetBrainsMono Nerd Font,JetBrainsMono NF\nBold Italic\n/usr/share/fonts/TTF/JetBrainsMonoNerdFont-BoldItalic.ttf\n",
		"JetBrainsMono Nerd Font",
		"Bold Italic",
	)
	testing.expect(t, ok)
	testing.expect_value(t, path, "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-BoldItalic.ttf")
	_, wrong_style := fontconfig_style_output_path(
		"JetBrainsMono Nerd Font\nBold Italic\n/font.ttf\n",
		"JetBrainsMono Nerd Font",
		"Italic",
	)
	testing.expect(t, !wrong_style)
}
