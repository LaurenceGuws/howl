package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
all_registry_default_shortcuts_parse_and_roundtrip :: proc(t: ^testing.T) {
	for definition in ACTION_DEFINITIONS {
		if len(definition.default_shortcut) == 0 {
			continue
		}
		shortcut, ok := parse_shortcut(definition.default_shortcut)
		testing.expect(t, ok)
		buffer: [SHORTCUT_TEXT_BYTES]u8
		formatted, formatted_ok := format_shortcut(shortcut, buffer[:])
		testing.expect(t, formatted_ok)
		testing.expect_value(t, formatted, definition.default_shortcut)
	}
}

@(test)
shortcut_parser_rejects_ambiguous_or_modifier_only_chords :: proc(t: ^testing.T) {
	cases := [6]string{"", "Ctrl", "Ctrl+", "Ctrl+Ctrl+T", "Ctrl+T+N", "Nope+T"}
	for text in cases {
		_, ok := parse_shortcut(text)
		testing.expect(t, !ok)
	}
}

@(test)
shortcut_event_matching_ignores_lock_state_and_rejects_repeat :: proc(t: ^testing.T) {
	shortcut, ok := parse_shortcut("Ctrl+Shift+P")
	testing.expect(t, ok)
	event := SDL.Event{}
	event.type = .KEY_DOWN
	event.key.key = SDL.K_P
	event.key.mod = {.LCTRL, .RSHIFT, .CAPS, .NUM}
	testing.expect(t, shortcut_matches_event(shortcut, &event))
	event.key.repeat = true
	testing.expect(t, !shortcut_matches_event(shortcut, &event))
}

@(test)
shortcut_parser_supports_punctuation_navigation_and_functions :: proc(t: ^testing.T) {
	cases := [6]string{"Ctrl+,", "Alt+Shift+-", "Ctrl+Plus", "Alt+Left", "F12", "Super+Space"}
	for text in cases {
		shortcut, ok := parse_shortcut(text)
		testing.expect(t, ok)
		buffer: [SHORTCUT_TEXT_BYTES]u8
		formatted, formatted_ok := format_shortcut(shortcut, buffer[:])
		testing.expect(t, formatted_ok)
		testing.expect_value(t, formatted, text)
	}
}

@(test)
effective_bindings_reject_conflicts_transactionally :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_action_bindings(&app))
	before := action_binding_text(&app, .New_Window)
	result := set_action_binding(&app, .New_Window, "Ctrl+T")
	testing.expect_value(t, result, Binding_Update_Result.Conflict)
	testing.expect_value(t, action_binding_text(&app, .New_Window), before)
	testing.expect_value(t, action_binding_text(&app, .New_Tab), "Ctrl+T")
}

@(test)
effective_bindings_apply_unbind_and_reset :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_action_bindings(&app))
	testing.expect_value(t, set_action_binding(&app, .New_Window, "Super+N"), Binding_Update_Result.Applied)
	testing.expect_value(t, action_binding_text(&app, .New_Window), "Super+N")
	testing.expect_value(t, set_action_binding(&app, .New_Window, ""), Binding_Update_Result.Applied)
	testing.expect_value(t, action_binding_text(&app, .New_Window), "")
	testing.expect(t, reset_action_binding(&app, .New_Window))
	testing.expect_value(t, action_binding_text(&app, .New_Window), "Ctrl+Shift+N")
}

@(test)
registered_shortcut_lookup_uses_effective_binding :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_action_bindings(&app))
	testing.expect_value(t, set_action_binding(&app, .New_Window, "Super+N"), Binding_Update_Result.Applied)
	event := SDL.Event{}
	event.type = .KEY_DOWN
	event.key.key = SDL.K_N
	event.key.mod = {.LGUI}
	action, ok := action_for_shortcut_event(&app, &event)
	testing.expect(t, ok)
	testing.expect_value(t, action, App_Action.New_Window)
}

@(test)
shortcut_recording_ignores_modifier_only_and_captures_final_key :: proc(t: ^testing.T) {
	event := SDL.Event{}
	event.type = .KEY_DOWN
	event.key.key = SDL.K_LCTRL
	event.key.mod = {.LCTRL}
	_, ok := shortcut_from_key_event(&event)
	testing.expect(t, !ok)

	event.key.key = SDL.K_K
	event.key.mod = {.LCTRL, .LSHIFT}
	shortcut, captured := shortcut_from_key_event(&event)
	testing.expect(t, captured)
	buffer: [SHORTCUT_TEXT_BYTES]u8
	formatted, formatted_ok := format_shortcut(shortcut, buffer[:])
	testing.expect(t, formatted_ok)
	testing.expect_value(t, formatted, "Ctrl+Shift+K")
}

@(test)
config_binding_overrides_are_transactional_and_allow_swaps :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_action_bindings(&app))
	overrides := [2]User_Keybinding_Config{
		{action = "new_tab", shortcut = "Ctrl+Shift+N"},
		{action = "new_window", shortcut = "Ctrl+T"},
	}
	testing.expect(t, apply_user_keybindings(&app, overrides[:]))
	testing.expect_value(t, action_binding_text(&app, .New_Tab), "Ctrl+Shift+N")
	testing.expect_value(t, action_binding_text(&app, .New_Window), "Ctrl+T")
}

@(test)
invalid_config_binding_set_preserves_defaults_and_names_bad_field :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_action_bindings(&app))
	overrides := [1]User_Keybinding_Config{{action = "new_window", shortcut = "Ctrl+Ctrl+N"}}
	testing.expect(t, !apply_user_keybindings(&app, overrides[:]))
	testing.expect_value(t, action_binding_text(&app, .New_Window), "Ctrl+Shift+N")
	testing.expect(t, app.config_notice_len != 0)
	notice := string(app.config_notice[:app.config_notice_len])
	testing.expect(t, len(notice) >= len("keybindings[0]") && notice[:len("keybindings[0]")] == "keybindings[0]")
}
