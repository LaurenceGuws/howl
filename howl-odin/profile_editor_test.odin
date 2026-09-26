package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
profile_editor_respects_builtin_and_mode_field_ownership :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_builtin_profiles(&app))
	defer destroy_profiles(&app)
	app.settings_profile_selection = 0
	testing.expect(t, !begin_profile_edit(&app, .Name))
	copy_index := duplicate_user_profile(&app, 0)
	testing.expect(t, copy_index >= 0)
	app.settings_profile_selection = copy_index
	profile := selected_settings_profile(&app)
	testing.expect(t, profile != nil && !profile.built_in && profile.mode == .Attach)
	testing.expect(t, profile_text_field_editable(profile, .Name))
	testing.expect(t, profile_text_field_editable(profile, .Endpoint))
	testing.expect(t, !profile_text_field_editable(profile, .Command))
}

@(test)
profile_editor_copies_bounded_source_and_backspaces_utf8_scalar :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_builtin_profiles(&app))
	defer destroy_profiles(&app)
	copy_index := duplicate_user_profile(&app, 1)
	testing.expect(t, copy_index >= 0)
	app.settings_profile_selection = copy_index
	testing.expect(t, begin_profile_edit(&app, .Name))
	testing.expect_value(t, string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len]), "Local shell copy")
	app.settings_profile_edit_len = 0
	testing.expect(t, append_profile_edit_text(&app, "aé界"))
	testing.expect_value(t, string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len]), "aé界")
	testing.expect(t, backspace_profile_edit(&app))
	testing.expect_value(t, string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len]), "aé")
}

@(test)
profile_keyboard_duplicate_arms_exactly_one_text_input_guard :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_builtin_profiles(&app))
	defer destroy_profiles(&app)
	app.settings_open = true
	app.settings_page = .Profile_Defaults
	app.settings_content_focus = true
	app.settings_profile_selection = 1
	event: SDL.Event
	event.type = .KEY_DOWN
	event.key.key = SDL.K_D
	testing.expect(t, handle_profile_list_key(&app, &event))
	testing.expect(t, app.settings_profile_editing)
	testing.expect(t, app.settings_profile_discard_text_input_once)
	testing.expect_value(t, profile_name(selected_settings_profile(&app)), "Local shell copy")
}

@(test)
profile_editor_environment_name_conflict_ignores_current_entry_only :: proc(t: ^testing.T) {
	profile: Profile = {mode = .Launch}
	profile.env_count = 2
	testing.expect(t, profile_set_text(profile.env[0].name[:], &profile.env[0].name_len, "ONE"))
	testing.expect(t, profile_set_text(profile.env[1].name[:], &profile.env[1].name_len, "TWO"))
	testing.expect(t, !profile_env_name_conflict(&profile, "ONE", 0))
	testing.expect(t, profile_env_name_conflict(&profile, "TWO", 0))
	testing.expect(t, !profile_env_name_conflict(&profile, "THREE", 0))
}

@(test)
profile_editor_field_relevance_tracks_launch_vs_attach :: proc(t: ^testing.T) {
	profile: Profile = {mode = .Launch}
	testing.expect(t, profile_field_relevant(&profile, .Shell))
	testing.expect(t, !profile_field_relevant(&profile, .Endpoint))
	profile.mode = .Attach
	testing.expect(t, !profile_field_relevant(&profile, .Shell))
	testing.expect(t, profile_field_relevant(&profile, .Endpoint))
	testing.expect(t, profile_field_relevant(&profile, .Name))
	testing.expect(t, profile_field_relevant(&profile, .Font))
}
