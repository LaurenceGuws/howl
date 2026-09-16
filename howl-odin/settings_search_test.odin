package main

import "core:testing"

@(test)
settings_search_finds_pages_actions_and_profiles :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_builtin_profiles(&app))
	defer destroy_profiles(&app)
	testing.expect(t, initialize_action_bindings(&app))
	custom := [1]User_Profile_Config{{id = "lab", name = "Lab Recipe", mode = "launch"}}
	load_user_profiles(&app, custom[:])
	app.settings_open = true

	open_settings_search(&app)
	testing.expect(t, append_settings_search_query(&app, "window"))
	found_window := false
	for index in 0..<app.settings_search_result_count {
		result := app.settings_search_results[index]
		if result.kind == .Action {
			definition, _ := action_definition_at(result.index)
			if definition.action == .New_Window do found_window = true
		}
	}
	testing.expect(t, found_window)

	open_settings_search(&app)
	testing.expect(t, append_settings_search_query(&app, "lab"))
	found_profile := false
	for index in 0..<app.settings_search_result_count {
		result := app.settings_search_results[index]
		if result.kind == .Profile && result.index == 2 do found_profile = true
	}
	testing.expect(t, found_profile)

	open_settings_search(&app)
	testing.expect(t, append_settings_search_query(&app, "color"))
	found_colors := false
	for index in 0..<app.settings_search_result_count {
		result := app.settings_search_results[index]
		if result.kind == .Page && result.page == .Color_Schemes do found_colors = true
	}
	testing.expect(t, found_colors)
}

@(test)
settings_search_result_navigation_targets_exact_context :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, initialize_builtin_profiles(&app))
	defer destroy_profiles(&app)
	testing.expect(t, initialize_action_bindings(&app))
	custom := [1]User_Profile_Config{{id = "lab", name = "Lab Recipe", mode = "launch"}}
	load_user_profiles(&app, custom[:])
	app.settings_open = true

	testing.expect(t, apply_settings_search_result(&app, {.Action, .Actions, 1}))
	testing.expect_value(t, app.settings_page, Settings_Page.Actions)
	testing.expect(t, app.settings_content_focus)
	testing.expect_value(t, app.settings_action_selection, 1)

	app.settings_open = true
	testing.expect(t, apply_settings_search_result(&app, {.Profile, .Profile_Home, 2}))
	testing.expect_value(t, app.settings_page, Settings_Page.Profile_Home)
	testing.expect_value(t, app.settings_profile_selection, 2)
	testing.expect(t, app.settings_content_focus)
}

@(test)
settings_search_backspace_preserves_utf8_scalar_boundaries :: proc(t: ^testing.T) {
	app: App
	app.settings_open = true
	open_settings_search(&app)
	testing.expect(t, append_settings_search_query(&app, "aé界"))
	testing.expect(t, backspace_settings_search_query(&app))
	testing.expect_value(t, settings_search_query(&app), "aé")
}
