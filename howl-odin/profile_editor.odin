package main

import "core:c"
import "core:fmt"
import SDL "vendor:sdl3"

Profile_Edit_Field :: enum u8 {
	Name,
	Mode,
	Shell,
	Command,
	Cwd,
	Endpoint,
	Font,
	Env_Name,
	Env_Value,
}

PROFILE_EDIT_FIELD_COUNT :: 9
PROFILE_EDIT_BYTES :: PROFILE_COMMAND_BYTES

profile_edit_field_at :: proc(index: int) -> (Profile_Edit_Field, bool) {
	if index < 0 || index >= PROFILE_EDIT_FIELD_COUNT {
		return .Name, false
	}
	return Profile_Edit_Field(index), true
}

selected_settings_profile :: proc(app: ^App) -> ^Profile {
	if app == nil {
		return nil
	}
	return profile_at(app, app.settings_profile_selection)
}

profile_field_label :: proc(field: Profile_Edit_Field, env_index, env_count: int, storage: []u8) -> string {
	switch field {
	case .Name:     return "Name"
	case .Mode:     return "Mode"
	case .Shell:    return "Shell"
	case .Command:  return "Command"
	case .Cwd:      return "Working directory"
	case .Endpoint: return "Endpoint"
	case .Font:     return "Font size"
	case .Env_Name:
		if env_count == 0 do return "Env name"
		return fmt.bprintf(storage, "Env name  %d/%d", env_index + 1, env_count)
	case .Env_Value:
		if env_count == 0 do return "Env value"
		return fmt.bprintf(storage, "Env value  %d/%d", env_index + 1, env_count)
	}
	return ""
}

profile_font_label :: proc(font_pixels: u16) -> string {
	switch font_pixels {
	case 0:  return "Inherit global"
	case 12: return "12 px"
	case 15: return "15 px"
	case 18: return "18 px"
	}
	return "Invalid"
}

profile_field_value :: proc(profile: ^Profile, field: Profile_Edit_Field, env_index: int) -> string {
	if profile == nil {
		return ""
	}
	switch field {
	case .Name:     return profile_name(profile)
	case .Mode:     return profile.mode == .Launch ? "Launch" : "Attach"
	case .Shell:
		if profile.mode != .Launch do return "Not used by attach profiles"
		value := profile_shell(profile)
		return len(value) == 0 ? "Inherit $SHELL" : value
	case .Command:
		if profile.mode != .Launch do return "Not used by attach profiles"
		value := profile_command(profile)
		return len(value) == 0 ? "Interactive shell" : value
	case .Cwd:
		if profile.mode != .Launch do return "Not used by attach profiles"
		value := profile_cwd(profile)
		return len(value) == 0 ? "Inherit desktop cwd" : value
	case .Endpoint:
		if profile.mode != .Attach do return "Not used by launch profiles"
		return profile_endpoint(profile)
	case .Font:
		return profile_font_label(profile.font_pixels)
	case .Env_Name:
		if profile.mode != .Launch do return "Not used by attach profiles"
		if profile.env_count == 0 do return "No environment overrides"
		index := clamp(env_index, 0, profile.env_count - 1)
		return profile_env_name(&profile.env[index])
	case .Env_Value:
		if profile.mode != .Launch do return "Not used by attach profiles"
		if profile.env_count == 0 do return "Press N to add an override"
		index := clamp(env_index, 0, profile.env_count - 1)
		return profile_env_value(&profile.env[index])
	}
	return ""
}

profile_text_field_editable :: proc(profile: ^Profile, field: Profile_Edit_Field) -> bool {
	if profile == nil || profile.built_in {
		return false
	}
	switch field {
	case .Name:
		return true
	case .Shell, .Command, .Cwd:
		return profile.mode == .Launch
	case .Endpoint:
		return profile.mode == .Attach
	case .Env_Name, .Env_Value:
		return profile.mode == .Launch && profile.env_count != 0
	case .Mode, .Font:
		return false
	}
	return false
}

profile_edit_field_capacity :: proc(field: Profile_Edit_Field) -> int {
	switch field {
	case .Name:      return PROFILE_NAME_BYTES - 1
	case .Shell:     return PROFILE_SHELL_BYTES - 1
	case .Command:   return PROFILE_COMMAND_BYTES - 1
	case .Cwd:       return PROFILE_CWD_BYTES - 1
	case .Endpoint:  return PROFILE_ENDPOINT_BYTES - 1
	case .Env_Name:  return PROFILE_ENV_NAME_BYTES - 1
	case .Env_Value: return PROFILE_ENV_VALUE_BYTES - 1
	case .Mode, .Font:
		return 0
	}
	return 0
}

profile_edit_field_source :: proc(profile: ^Profile, field: Profile_Edit_Field, env_index: int) -> string {
	if profile == nil {
		return ""
	}
	switch field {
	case .Name:     return profile_name(profile)
	case .Shell:    return profile_shell(profile)
	case .Command:  return profile_command(profile)
	case .Cwd:      return profile_cwd(profile)
	case .Endpoint: return profile_endpoint(profile)
	case .Env_Name:
		if profile.env_count == 0 do return ""
		return profile_env_name(&profile.env[clamp(env_index, 0, profile.env_count - 1)])
	case .Env_Value:
		if profile.env_count == 0 do return ""
		return profile_env_value(&profile.env[clamp(env_index, 0, profile.env_count - 1)])
	case .Mode, .Font:
		return ""
	}
	return ""
}

cancel_profile_edit :: proc(app: ^App) {
	if app == nil {
		return
	}
	app.settings_profile_editing = false
	app.settings_profile_edit_len = 0
	clear_ime_preedit(app)
}

begin_profile_edit :: proc(app: ^App, field: Profile_Edit_Field) -> bool {
	profile := selected_settings_profile(app)
	if !profile_text_field_editable(profile, field) {
		if profile != nil && profile.built_in {
			set_settings_notice(app, "Built-in profile · duplicate it to customize")
		}
		return false
	}
	source := profile_edit_field_source(profile, field, app.settings_profile_env_selection)
	capacity := profile_edit_field_capacity(field)
	if capacity <= 0 || len(source) > capacity || len(source) >= len(app.settings_profile_edit_buffer) {
		set_settings_notice(app, "Profile field exceeds editor bound")
		return false
	}
	app.settings_profile_edit_len = len(source)
	if len(source) != 0 {
		copy(app.settings_profile_edit_buffer[:len(source)], transmute([]u8)source)
	}
	app.settings_profile_edit_field = field
	app.settings_profile_edit_env_index = app.settings_profile_env_selection
	app.settings_profile_editing = true
	app.settings_notice_len = 0
	clear_ime_preedit(app)
	return true
}

append_profile_edit_text :: proc(app: ^App, text: string) -> bool {
	if app == nil || !app.settings_profile_editing || len(text) == 0 {
		return false
	}
	capacity := profile_edit_field_capacity(app.settings_profile_edit_field)
	if app.settings_profile_edit_len + len(text) > capacity ||
	   app.settings_profile_edit_len + len(text) >= len(app.settings_profile_edit_buffer) {
		set_settings_notice(app, "Profile field limit reached")
		return false
	}
	copy(
		app.settings_profile_edit_buffer[app.settings_profile_edit_len:app.settings_profile_edit_len + len(text)],
		transmute([]u8)text,
	)
	app.settings_profile_edit_len += len(text)
	return true
}

backspace_profile_edit :: proc(app: ^App) -> bool {
	if app == nil || !app.settings_profile_editing || app.settings_profile_edit_len == 0 {
		return false
	}
	next := app.settings_profile_edit_len - 1
	for next > 0 && app.settings_profile_edit_buffer[next] & 0xc0 == 0x80 {
		next -= 1
	}
	app.settings_profile_edit_len = next
	return true
}

profile_env_name_conflict :: proc(profile: ^Profile, name: string, ignored_index: int) -> bool {
	if profile == nil {
		return false
	}
	for index in 0..<profile.env_count {
		if index != ignored_index && profile_env_name(&profile.env[index]) == name {
			return true
		}
	}
	return false
}

apply_profile_name_to_tabs :: proc(app: ^App, profile_index: int) {
	if app == nil {
		return
	}
	profile := profile_at(app, profile_index)
	if profile == nil {
		return
	}
	for tab_index in 0..<app.tab_count {
		if app.tabs[tab_index].profile == profile_index {
			app.tabs[tab_index].title = profile_name(profile)
		}
	}
}

commit_profile_edit :: proc(app: ^App) -> bool {
	if app == nil || !app.settings_profile_editing {
		return false
	}
	profile := selected_settings_profile(app)
	if profile == nil || profile.built_in {
		cancel_profile_edit(app)
		return false
	}
	value := string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len])
	field := app.settings_profile_edit_field
	ok := false
	switch field {
	case .Name:
		if len(value) == 0 {
			set_settings_notice(app, "Profile name cannot be empty")
			return false
		}
		ok = profile_set_text(profile.name[:], &profile.name_len, value)
		if ok do apply_profile_name_to_tabs(app, app.settings_profile_selection)
	case .Shell:
		ok = profile.mode == .Launch && profile_set_text(profile.shell[:], &profile.shell_len, value)
	case .Command:
		ok = profile.mode == .Launch && profile_set_text(profile.command[:], &profile.command_len, value)
	case .Cwd:
		ok = profile.mode == .Launch && profile_set_text(profile.cwd[:], &profile.cwd_len, value)
	case .Endpoint:
		if profile.mode != .Attach || len(value) == 0 {
			set_settings_notice(app, "Attach endpoint cannot be empty")
			return false
		}
		ok = profile_set_text(profile.endpoint[:], &profile.endpoint_len, value)
	case .Env_Name:
		index := app.settings_profile_edit_env_index
		if profile.mode != .Launch || index < 0 || index >= profile.env_count ||
		   !valid_profile_env_name(value) || profile_env_name_conflict(profile, value, index) {
			set_settings_notice(app, "Environment name is invalid or duplicated")
			return false
		}
		ok = profile_set_text(profile.env[index].name[:], &profile.env[index].name_len, value)
	case .Env_Value:
		index := app.settings_profile_edit_env_index
		if profile.mode != .Launch || index < 0 || index >= profile.env_count {
			return false
		}
		ok = profile_set_text(profile.env[index].value[:], &profile.env[index].value_len, value)
	case .Mode, .Font:
		return false
	}
	if !ok {
		set_settings_notice(app, "Profile field could not be saved")
		return false
	}
	cancel_profile_edit(app)
	save_user_config(app)
	set_settings_notice(app, "Saved · launch edits apply after restart")
	return true
}

adjust_profile_mode :: proc(app: ^App, delta: int) -> bool {
	profile := selected_settings_profile(app)
	if app == nil || profile == nil || profile.built_in || delta == 0 {
		return false
	}
	next := profile.mode == .Launch ? Profile_Mode.Attach : Profile_Mode.Launch
	if next == profile.mode {
		return false
	}
	profile.mode = next
	if next == .Attach {
		profile.shell_len = 0
		profile.command_len = 0
		profile.cwd_len = 0
		profile.env_count = 0
		if profile.endpoint_len == 0 {
			_ = profile_set_text(profile.endpoint[:], &profile.endpoint_len, HOME_ENDPOINT)
		}
	} else {
		profile.endpoint_len = 0
	}
	app.settings_profile_env_selection = 0
	save_user_config(app)
	set_settings_notice(app, "Profile mode saved · affects future/restarted Sessions")
	return true
}

adjust_profile_font :: proc(app: ^App, delta: int) -> bool {
	profile := selected_settings_profile(app)
	if app == nil || profile == nil || profile.built_in || delta == 0 {
		return false
	}
	values := [4]u16{0, 12, 15, 18}
	current := 0
	for value, index in values {
		if value == profile.font_pixels do current = index
	}
	next := clamp(current + delta, 0, len(values) - 1)
	if next == current {
		return false
	}
	profile.font_pixels = values[next]
	profile_apply_font_to_views(app, app.settings_profile_selection)
	save_user_config(app)
	set_settings_notice(app, "Profile font saved")
	return true
}

add_profile_environment :: proc(app: ^App) -> bool {
	profile := selected_settings_profile(app)
	if app == nil || profile == nil || profile.built_in || profile.mode != .Launch || profile.env_count >= MAX_PROFILE_ENV {
		return false
	}
	storage: [PROFILE_ENV_NAME_BYTES]u8
	name: string
	for identity in 1..=999 {
		candidate := fmt.bprintf(storage[:], "NEW_VAR_%d", identity)
		if !profile_env_duplicate(profile, candidate) {
			name = candidate
			break
		}
	}
	if len(name) == 0 {
		return false
	}
	entry := &profile.env[profile.env_count]
	entry^ = {}
	if !profile_set_text(entry.name[:], &entry.name_len, name) {
		return false
	}
	app.settings_profile_env_selection = profile.env_count
	profile.env_count += 1
	save_user_config(app)
	set_settings_notice(app, "Environment override added")
	return true
}

delete_profile_environment :: proc(app: ^App) -> bool {
	profile := selected_settings_profile(app)
	if app == nil || profile == nil || profile.built_in || profile.env_count == 0 {
		return false
	}
	index := clamp(app.settings_profile_env_selection, 0, profile.env_count - 1)
	for current in index..<profile.env_count - 1 {
		profile.env[current] = profile.env[current + 1]
	}
	profile.env_count -= 1
	profile.env[profile.env_count] = {}
	app.settings_profile_env_selection = clamp(index, 0, max(0, profile.env_count - 1))
	save_user_config(app)
	set_settings_notice(app, "Environment override removed")
	return true
}

handle_profile_edit_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
	if app == nil || !app.settings_profile_editing {
		return false
	}
	if event.type != .KEY_DOWN {
		return true
	}
	switch event.key.key {
	case SDL.K_ESCAPE:
		cancel_profile_edit(app)
		set_settings_notice(app, "Profile edit canceled")
	case SDL.K_RETURN:
		_ = commit_profile_edit(app)
	case SDL.K_BACKSPACE:
		_ = backspace_profile_edit(app)
	case:
		// TEXT_INPUT owns printable committed text while the editor is active.
	}
	return true
}

open_profile_editor :: proc(app: ^App, profile_index: int, focus_name := false) -> bool {
	if app == nil || profile_at(app, profile_index) == nil {
		return false
	}
	cancel_profile_edit(app)
	app.settings_profile_selection = profile_index
	app.settings_page = .Profile_Home
	app.settings_content_focus = true
	app.settings_profile_field = int(Profile_Edit_Field.Name)
	app.settings_profile_env_selection = 0
	app.settings_notice_len = 0
	if focus_name {
		_ = begin_profile_edit(app, .Name)
	}
	return true
}

handle_profile_list_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
	if app == nil || event.type != .KEY_DOWN || app.profile_count == 0 {
		return false
	}
	switch event.key.key {
	case SDL.K_TAB:
		app.settings_content_focus = false
	case SDL.K_UP:
		app.settings_profile_selection = (app.settings_profile_selection + app.profile_count - 1) % app.profile_count
	case SDL.K_DOWN:
		app.settings_profile_selection = (app.settings_profile_selection + 1) % app.profile_count
	case SDL.K_RETURN:
		_ = open_profile_editor(app, app.settings_profile_selection)
	case SDL.K_N:
		index := create_user_profile(app)
		if index >= 0 {
			save_user_config(app)
			_ = open_profile_editor(app, index, true)
		} else {
			set_settings_notice(app, "Profile limit reached")
		}
	case SDL.K_D:
		index := duplicate_user_profile(app, app.settings_profile_selection)
		if index >= 0 {
			save_user_config(app)
			_ = open_profile_editor(app, index, true)
		} else {
			set_settings_notice(app, "Profile could not be duplicated")
		}
	case SDL.K_DELETE, SDL.K_BACKSPACE:
		selected := app.settings_profile_selection
		profile := profile_at(app, selected)
		if profile == nil {
			return true
		}
		if profile.built_in {
			set_settings_notice(app, "Built-in profile · duplicate to customize")
		} else if profile_in_use(app, selected) {
			set_settings_notice(app, "Profile is in use · close its tabs/panes first")
		} else if delete_user_profile(app, selected) {
			app.settings_profile_selection = clamp(selected, 0, app.profile_count - 1)
			save_user_config(app)
			set_settings_notice(app, "Profile deleted")
		}
	case:
		return false
	}
	return true
}

handle_profile_editor_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
	if app == nil || event.type != .KEY_DOWN {
		return false
	}
	profile := selected_settings_profile(app)
	if profile == nil {
		return false
	}
	field, field_ok := profile_edit_field_at(app.settings_profile_field)
	if !field_ok {
		app.settings_profile_field = 0
		field = .Name
	}
	switch event.key.key {
	case SDL.K_TAB:
		app.settings_content_focus = false
	case SDL.K_UP:
		app.settings_profile_field = (app.settings_profile_field + PROFILE_EDIT_FIELD_COUNT - 1) % PROFILE_EDIT_FIELD_COUNT
	case SDL.K_DOWN:
		app.settings_profile_field = (app.settings_profile_field + 1) % PROFILE_EDIT_FIELD_COUNT
	case SDL.K_RETURN:
		if profile.built_in {
			set_settings_notice(app, "Built-in profile · press D to duplicate")
		} else if field == .Mode {
			_ = adjust_profile_mode(app, 1)
		} else if field == .Font {
			_ = adjust_profile_font(app, 1)
		} else {
			_ = begin_profile_edit(app, field)
		}
	case SDL.K_LEFT:
		if field == .Mode do _ = adjust_profile_mode(app, -1)
		if field == .Font do _ = adjust_profile_font(app, -1)
		if (field == .Env_Name || field == .Env_Value) && profile.env_count != 0 {
			app.settings_profile_env_selection = (app.settings_profile_env_selection + profile.env_count - 1) % profile.env_count
		}
	case SDL.K_RIGHT:
		if field == .Mode do _ = adjust_profile_mode(app, 1)
		if field == .Font do _ = adjust_profile_font(app, 1)
		if (field == .Env_Name || field == .Env_Value) && profile.env_count != 0 {
			app.settings_profile_env_selection = (app.settings_profile_env_selection + 1) % profile.env_count
		}
	case SDL.K_N:
		if field == .Env_Name || field == .Env_Value {
			_ = add_profile_environment(app)
			return true
		}
		return false
	case SDL.K_DELETE, SDL.K_BACKSPACE:
		if field == .Env_Name || field == .Env_Value {
			_ = delete_profile_environment(app)
			return true
		}
		return false
	case SDL.K_D:
		if profile.built_in {
			index := duplicate_user_profile(app, app.settings_profile_selection)
			if index >= 0 {
				save_user_config(app)
				_ = open_profile_editor(app, index, true)
			}
			return true
		}
		return false
	case:
		return false
	}
	return true
}

profile_list_row_rect :: proc(x, y, width: f32, index: int) -> SDL.FRect {
	return {x - 8, y + 44 + f32(index) * 44, width, 40}
}

profile_field_row_rect :: proc(x, y, width: f32, index: int) -> SDL.FRect {
	return {x - 8, y + 44 + f32(index) * 48, width, 44}
}

profile_field_value_rect :: proc(content_x, content_y, width: f32, field_index: int) -> SDL.FRect {
	row := profile_field_row_rect(content_x, content_y, width, field_index)
	value_x := row.x + 174
	return {value_x, row.y + 5, max(f32(80), row.x + row.w - value_x - 8), row.h - 10}
}

profile_editor_input_rect :: proc(app: ^App, width, height: f32) -> (SDL.FRect, bool) {
	if app == nil || !app.settings_open || app.settings_page != .Profile_Home || !app.settings_profile_editing {
		return {}, false
	}
	panel := settings_panel_rect(width, height)
	content_x := panel.x + 178 + 28
	content_y := panel.y + 22
	field_index := int(app.settings_profile_edit_field)
	if field_index < 0 || field_index >= PROFILE_EDIT_FIELD_COUNT {
		return {}, false
	}
	return profile_field_value_rect(content_x, content_y, panel.x + panel.w - content_x - 12, field_index), true
}

profile_field_relevant :: proc(profile: ^Profile, field: Profile_Edit_Field) -> bool {
	if profile == nil {
		return false
	}
	switch field {
	case .Shell, .Command, .Cwd, .Env_Name, .Env_Value:
		return profile.mode == .Launch
	case .Endpoint:
		return profile.mode == .Attach
	case .Name, .Mode, .Font:
		return true
	}
	return false
}

draw_profiles_settings :: proc(app: ^App, panel: SDL.FRect, content_x, content_y: f32) {
	available := panel.x + panel.w - content_x - 12
	draw_text(app, app.ui_font, "Profile catalogue", content_x, content_y + 18, palette.text_muted)
	for index in 0..<app.profile_count {
		profile := app.profiles[index]
		row := profile_list_row_rect(content_x, content_y, available, index)
		selected := app.settings_content_focus && app.settings_profile_selection == index
		if selected do draw_fill(app.renderer, row, palette.tab_active)
		name_color := selected ? palette.accent : palette.text
		draw_text(app, app.ui_font, profile_name(profile), row.x + 10, row.y + 4, name_color)
		kind := profile.built_in ? "Built-in" : "User"
		mode := profile.mode == .Launch ? "Launch" : "Attach"
		detail_storage: [96]u8
		detail := fmt.bprintf(detail_storage[:], "%s · %s", kind, mode)
		draw_text(app, app.ui_font, detail, row.x + 10, row.y + 22, palette.text_muted)
		if app.startup_profile == index {
			draw_text(app, app.ui_font, "default", row.x + row.w - 70, row.y + 13, palette.accent)
		}
	}
	hint_y := content_y + 52 + f32(app.profile_count) * 44
	if app.settings_content_focus {
		draw_text(app, app.ui_font, "Enter edit · N new · D copy · Del delete", content_x, hint_y, palette.text_muted)
		draw_text(app, app.ui_font, "Tab returns to sidebar", content_x, hint_y + 22, palette.text_muted)
	} else {
		draw_text(app, app.ui_font, "Tab to manage profiles", content_x, hint_y, palette.text_muted)
	}
	if app.settings_notice_len != 0 {
		draw_text(app, app.ui_font, string(app.settings_notice[:app.settings_notice_len]), content_x, hint_y + 48, palette.accent)
	} else if app.config_notice_len != 0 {
		draw_text(app, app.ui_font, string(app.config_notice[:app.config_notice_len]), content_x, hint_y + 48, palette.accent)
	}
}

draw_profile_editor_settings :: proc(app: ^App, panel: SDL.FRect, content_x, content_y: f32) {
	profile := selected_settings_profile(app)
	if profile == nil {
		draw_text(app, app.ui_font, "No profile selected", content_x, content_y + 52, palette.text_muted)
		return
	}
	available := panel.x + panel.w - content_x - 12
	meta_storage: [160]u8
	meta := fmt.bprintf(
		meta_storage[:],
		"%s · id %s · %s",
		profile.built_in ? "Built-in" : "User-owned",
		profile_id(profile),
		profile.mode == .Launch ? "launch" : "attach",
	)
	draw_text(app, app.ui_font, meta, content_x, content_y + 18, profile.built_in ? palette.text_muted : palette.accent)

	for field_index in 0..<PROFILE_EDIT_FIELD_COUNT {
		field, _ := profile_edit_field_at(field_index)
		row := profile_field_row_rect(content_x, content_y, available, field_index)
		selected := app.settings_content_focus && app.settings_profile_field == field_index
		if selected do draw_fill(app.renderer, row, palette.tab_active)
		label_storage: [96]u8
		label := profile_field_label(field, app.settings_profile_env_selection, profile.env_count, label_storage[:])
		relevant := profile_field_relevant(profile, field)
		label_color := selected ? palette.accent : (relevant ? palette.text_muted : palette.border)
		draw_text(app, app.ui_font, label, row.x + 10, row.y + 13, label_color)

		value_rect := profile_field_value_rect(content_x, content_y, available, field_index)
		value := profile_field_value(profile, field, app.settings_profile_env_selection)
		editing := app.settings_profile_editing && int(app.settings_profile_edit_field) == field_index
		if editing {
			value = string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len])
			draw_outline(app.renderer, value_rect, palette.accent)
		}
		clip := SDL.Rect{c.int(value_rect.x + 5), c.int(value_rect.y), c.int(max(f32(1), value_rect.w - 10)), c.int(value_rect.h)}
		_ = SDL.SetRenderClipRect(app.renderer, &clip)
		value_color := editing || (selected && relevant && !profile.built_in) ? palette.text : palette.text_muted
		if !relevant do value_color = palette.border
		draw_text(app, app.ui_font, value, value_rect.x + 7, value_rect.y + 8, value_color)
		_ = SDL.SetRenderClipRect(app.renderer, nil)
	}

	hint_y := content_y + 54 + f32(PROFILE_EDIT_FIELD_COUNT) * 48
	if profile.built_in {
		draw_text(app, app.ui_font, "Built-in · D duplicate to customize", content_x, hint_y, palette.text_muted)
	} else if app.settings_profile_editing {
		draw_text(app, app.ui_font, "Enter save · Esc cancel · Backspace edit", content_x, hint_y, palette.accent)
	} else if app.settings_content_focus {
		draw_text(app, app.ui_font, "Enter edit/toggle · Left/Right adjust", content_x, hint_y, palette.text_muted)
		draw_text(app, app.ui_font, "Env: N add · Del remove · Tab sidebar", content_x, hint_y + 22, palette.text_muted)
	} else {
		draw_text(app, app.ui_font, "Tab to edit this profile", content_x, hint_y, palette.text_muted)
	}
	notice_y := hint_y + (app.settings_content_focus && !profile.built_in && !app.settings_profile_editing ? f32(48) : f32(28))
	if app.settings_notice_len != 0 {
		draw_text(app, app.ui_font, string(app.settings_notice[:app.settings_notice_len]), content_x, notice_y, palette.accent)
	} else if app.config_notice_len != 0 {
		draw_text(app, app.ui_font, string(app.config_notice[:app.config_notice_len]), content_x, notice_y, palette.accent)
	}
}
