package main

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl3"

SHORTCUT_TEXT_BYTES :: 64
SHORTCUT_MOD_CTRL  :: u8(1 << 0)
SHORTCUT_MOD_SHIFT :: u8(1 << 1)
SHORTCUT_MOD_ALT   :: u8(1 << 2)
SHORTCUT_MOD_SUPER :: u8(1 << 3)

Shortcut :: struct {
	key: SDL.Keycode,
	modifiers: u8,
}

shortcut_valid :: proc(value: Shortcut) -> bool {
	return value.key != SDL.K_UNKNOWN
}

shortcut_modifiers_from_sdl :: proc(mods: SDL.Keymod) -> u8 {
	result: u8
	if .LCTRL in mods || .RCTRL in mods do result |= SHORTCUT_MOD_CTRL
	if .LSHIFT in mods || .RSHIFT in mods do result |= SHORTCUT_MOD_SHIFT
	if .LALT in mods || .RALT in mods do result |= SHORTCUT_MOD_ALT
	if .LGUI in mods || .RGUI in mods do result |= SHORTCUT_MOD_SUPER
	return result
}

shortcut_key_from_token :: proc(token: string) -> (SDL.Keycode, bool) {
	if len(token) == 1 {
		value := token[0]
		if value >= 'A' && value <= 'Z' do value += 'a' - 'A'
		if value >= 0x20 && value <= 0x7e && value != '+' {
			return SDL.Keycode(value), true
		}
	}
	if strings.equal_fold(token, "Space") do return SDL.K_SPACE, true
	if strings.equal_fold(token, "Plus") do return SDL.K_PLUS, true
	if strings.equal_fold(token, "Enter") do return SDL.K_RETURN, true
	if strings.equal_fold(token, "Tab") do return SDL.K_TAB, true
	if strings.equal_fold(token, "Escape") || strings.equal_fold(token, "Esc") do return SDL.K_ESCAPE, true
	if strings.equal_fold(token, "Backspace") do return SDL.K_BACKSPACE, true
	if strings.equal_fold(token, "Delete") do return SDL.K_DELETE, true
	if strings.equal_fold(token, "Insert") do return SDL.K_INSERT, true
	if strings.equal_fold(token, "Home") do return SDL.K_HOME, true
	if strings.equal_fold(token, "End") do return SDL.K_END, true
	if strings.equal_fold(token, "PageUp") do return SDL.K_PAGEUP, true
	if strings.equal_fold(token, "PageDown") do return SDL.K_PAGEDOWN, true
	if strings.equal_fold(token, "Left") do return SDL.K_LEFT, true
	if strings.equal_fold(token, "Right") do return SDL.K_RIGHT, true
	if strings.equal_fold(token, "Up") do return SDL.K_UP, true
	if strings.equal_fold(token, "Down") do return SDL.K_DOWN, true
	if strings.equal_fold(token, "F1") do return SDL.K_F1, true
	if strings.equal_fold(token, "F2") do return SDL.K_F2, true
	if strings.equal_fold(token, "F3") do return SDL.K_F3, true
	if strings.equal_fold(token, "F4") do return SDL.K_F4, true
	if strings.equal_fold(token, "F5") do return SDL.K_F5, true
	if strings.equal_fold(token, "F6") do return SDL.K_F6, true
	if strings.equal_fold(token, "F7") do return SDL.K_F7, true
	if strings.equal_fold(token, "F8") do return SDL.K_F8, true
	if strings.equal_fold(token, "F9") do return SDL.K_F9, true
	if strings.equal_fold(token, "F10") do return SDL.K_F10, true
	if strings.equal_fold(token, "F11") do return SDL.K_F11, true
	if strings.equal_fold(token, "F12") do return SDL.K_F12, true
	return SDL.K_UNKNOWN, false
}

parse_shortcut :: proc(text: string) -> (Shortcut, bool) {
	if len(text) == 0 || len(text) >= SHORTCUT_TEXT_BYTES {
		return {}, false
	}
	mods: u8
	key: SDL.Keycode = SDL.K_UNKNOWN
	start := 0
	for index in 0..=len(text) {
		if index != len(text) && text[index] != '+' {
			continue
		}
		if index == start {
			return {}, false
		}
		token := text[start:index]
		modifier: u8
		if strings.equal_fold(token, "Ctrl") || strings.equal_fold(token, "Control") {
			modifier = SHORTCUT_MOD_CTRL
		} else if strings.equal_fold(token, "Shift") {
			modifier = SHORTCUT_MOD_SHIFT
		} else if strings.equal_fold(token, "Alt") {
			modifier = SHORTCUT_MOD_ALT
		} else if strings.equal_fold(token, "Super") || strings.equal_fold(token, "Meta") {
			modifier = SHORTCUT_MOD_SUPER
		} else {
			if key != SDL.K_UNKNOWN {
				return {}, false
			}
			parsed, ok := shortcut_key_from_token(token)
			if !ok {
				return {}, false
			}
			key = parsed
		}
		if modifier != 0 {
			if mods & modifier != 0 {
				return {}, false
			}
			mods |= modifier
		}
		start = index + 1
	}
	if key == SDL.K_UNKNOWN {
		return {}, false
	}
	return Shortcut{key = key, modifiers = mods}, true
}

shortcut_matches_event :: proc(shortcut: Shortcut, event: ^SDL.Event) -> bool {
	if event == nil || event.type != .KEY_DOWN || event.key.repeat || !shortcut_valid(shortcut) {
		return false
	}
	return event.key.key == shortcut.key &&
	       shortcut_modifiers_from_sdl(event.key.mod) == shortcut.modifiers
}

append_shortcut_text :: proc(buffer: []u8, used: ^int, text: string) -> bool {
	if used == nil || used^ < 0 || used^ + len(text) > len(buffer) {
		return false
	}
	copy(buffer[used^:used^ + len(text)], transmute([]u8)text)
	used^ += len(text)
	return true
}

shortcut_key_name :: proc(key: SDL.Keycode, scratch: []u8) -> (string, bool) {
	if key == SDL.K_SPACE do return "Space", true
	value := u32(key)
	if value >= 0x20 && value <= 0x7e && value != u32('+') {
		if len(scratch) == 0 do return "", false
		byte := u8(value)
		if byte >= 'a' && byte <= 'z' do byte -= 'a' - 'A'
		scratch[0] = byte
		return string(scratch[:1]), true
	}
	switch key {
	case SDL.K_PLUS:     return "Plus", true
	case SDL.K_RETURN:   return "Enter", true
	case SDL.K_TAB:      return "Tab", true
	case SDL.K_ESCAPE:   return "Escape", true
	case SDL.K_BACKSPACE:return "Backspace", true
	case SDL.K_DELETE:   return "Delete", true
	case SDL.K_INSERT:   return "Insert", true
	case SDL.K_HOME:     return "Home", true
	case SDL.K_END:      return "End", true
	case SDL.K_PAGEUP:   return "PageUp", true
	case SDL.K_PAGEDOWN: return "PageDown", true
	case SDL.K_LEFT:     return "Left", true
	case SDL.K_RIGHT:    return "Right", true
	case SDL.K_UP:       return "Up", true
	case SDL.K_DOWN:     return "Down", true
	case SDL.K_SPACE:    return "Space", true
	case SDL.K_F1:       return "F1", true
	case SDL.K_F2:       return "F2", true
	case SDL.K_F3:       return "F3", true
	case SDL.K_F4:       return "F4", true
	case SDL.K_F5:       return "F5", true
	case SDL.K_F6:       return "F6", true
	case SDL.K_F7:       return "F7", true
	case SDL.K_F8:       return "F8", true
	case SDL.K_F9:       return "F9", true
	case SDL.K_F10:      return "F10", true
	case SDL.K_F11:      return "F11", true
	case SDL.K_F12:      return "F12", true
	case:
		_ = fmt.bprintf(scratch, "0x%X", value)
		return "", false
	}
}

format_shortcut :: proc(value: Shortcut, output: []u8) -> (string, bool) {
	if !shortcut_valid(value) || len(output) == 0 {
		return "", false
	}
	used := 0
	if value.modifiers & SHORTCUT_MOD_CTRL != 0 {
		if !append_shortcut_text(output, &used, "Ctrl+") do return "", false
	}
	if value.modifiers & SHORTCUT_MOD_ALT != 0 {
		if !append_shortcut_text(output, &used, "Alt+") do return "", false
	}
	if value.modifiers & SHORTCUT_MOD_SHIFT != 0 {
		if !append_shortcut_text(output, &used, "Shift+") do return "", false
	}
	if value.modifiers & SHORTCUT_MOD_SUPER != 0 {
		if !append_shortcut_text(output, &used, "Super+") do return "", false
	}
	scratch: [16]u8
	name, ok := shortcut_key_name(value.key, scratch[:])
	if !ok || !append_shortcut_text(output, &used, name) {
		return "", false
	}
	return string(output[:used]), true
}

Action_Binding :: struct {
	action: App_Action,
	shortcut: Shortcut,
	text: [SHORTCUT_TEXT_BYTES]u8,
	text_len: int,
	customized: bool,
}

Binding_Update_Result :: enum u8 {
	Applied,
	Invalid,
	Unknown_Action,
	Conflict,
}

binding_for_action :: proc(app: ^App, action: App_Action) -> ^Action_Binding {
	if app == nil {
		return nil
	}
	for &binding in app.action_bindings {
		if binding.action == action {
			return &binding
		}
	}
	return nil
}

action_binding_text :: proc(app: ^App, action: App_Action) -> string {
	binding := binding_for_action(app, action)
	if binding == nil || binding.text_len <= 0 {
		return ""
	}
	return string(binding.text[:binding.text_len])
}

write_binding :: proc(binding: ^Action_Binding, action: App_Action, shortcut: Shortcut, text: string, customized: bool) -> bool {
	if binding == nil || len(text) >= len(binding.text) {
		return false
	}
	binding^ = Action_Binding{action = action, shortcut = shortcut, customized = customized}
	if len(text) != 0 {
		copy(binding.text[:len(text)], transmute([]u8)text)
		binding.text_len = len(text)
	}
	return true
}

initialize_action_bindings :: proc(app: ^App) -> bool {
	if app == nil {
		return false
	}
	for definition, index in ACTION_DEFINITIONS {
		shortcut: Shortcut
		text := definition.default_shortcut
		if len(text) != 0 {
			parsed, ok := parse_shortcut(text)
			if !ok {
				return false
			}
			shortcut = parsed
		}
		if !write_binding(&app.action_bindings[index], definition.action, shortcut, text, false) {
			return false
		}
	}
	for binding, index in app.action_bindings {
		if !shortcut_valid(binding.shortcut) {
			continue
		}
		for other, other_index in app.action_bindings {
			if other_index > index && shortcut_valid(other.shortcut) && other.shortcut == binding.shortcut {
				return false
			}
		}
	}
	return true
}

binding_conflict :: proc(app: ^App, action: App_Action, shortcut: Shortcut) -> (App_Action, bool) {
	if app == nil || !shortcut_valid(shortcut) {
		return .New_Tab, false
	}
	for binding in app.action_bindings {
		if binding.action != action && shortcut_valid(binding.shortcut) && binding.shortcut == shortcut {
			return binding.action, true
		}
	}
	return .New_Tab, false
}

set_action_binding :: proc(app: ^App, action: App_Action, text: string) -> Binding_Update_Result {
	binding := binding_for_action(app, action)
	if binding == nil {
		return .Unknown_Action
	}
	if len(text) == 0 {
		_ = write_binding(binding, action, {}, "", true)
		return .Applied
	}
	shortcut, ok := parse_shortcut(text)
	if !ok {
		return .Invalid
	}
	if _, conflict := binding_conflict(app, action, shortcut); conflict {
		return .Conflict
	}
	canonical_storage: [SHORTCUT_TEXT_BYTES]u8
	canonical, formatted := format_shortcut(shortcut, canonical_storage[:])
	if !formatted || !write_binding(binding, action, shortcut, canonical, true) {
		return .Invalid
	}
	return .Applied
}

reset_action_binding :: proc(app: ^App, action: App_Action) -> bool {
	definition, ok := action_definition(action)
	if !ok {
		return false
	}
	binding := binding_for_action(app, action)
	if binding == nil {
		return false
	}
	shortcut: Shortcut
	if len(definition.default_shortcut) != 0 {
		parsed, parsed_ok := parse_shortcut(definition.default_shortcut)
		if !parsed_ok {
			return false
		}
		shortcut = parsed
	}
	return write_binding(binding, action, shortcut, definition.default_shortcut, false)
}

action_for_shortcut_event :: proc(app: ^App, event: ^SDL.Event) -> (App_Action, bool) {
	if app == nil || event == nil {
		return .New_Tab, false
	}
	for binding in app.action_bindings {
		if shortcut_matches_event(binding.shortcut, event) {
			return binding.action, true
		}
	}
	return .New_Tab, false
}

handle_registered_action_shortcut :: proc(app: ^App, event: ^SDL.Event) -> bool {
	action, ok := action_for_shortcut_event(app, event)
	if !ok {
		return false
	}
	if action_enabled(app, action) {
		execute_action(app, action)
	}
	return true
}

set_config_notice :: proc(app: ^App, message: string) {
	if app == nil {
		return
	}
	app.config_notice_len = min(len(message), len(app.config_notice))
	if app.config_notice_len != 0 {
		copy(app.config_notice[:app.config_notice_len], transmute([]u8)message[:app.config_notice_len])
	}
}

binding_index_for_action :: proc(bindings: ^[13]Action_Binding, action: App_Action) -> int {
	if bindings == nil {
		return -1
	}
	for binding, index in bindings {
		if binding.action == action {
			return index
		}
	}
	return -1
}

apply_user_keybindings :: proc(app: ^App, overrides: []User_Keybinding_Config) -> bool {
	if app == nil || len(overrides) == 0 {
		return true
	}
	if len(overrides) > len(app.action_bindings) {
		set_config_notice(app, "keybindings: too many overrides")
		return false
	}
	candidate := app.action_bindings
	mentioned: [13]bool
	actions: [13]App_Action
	shortcuts: [13]Shortcut
	texts: [13][SHORTCUT_TEXT_BYTES]u8
	text_lengths: [13]int

	for override, index in overrides {
		action, known := action_from_id(override.action)
		if !known {
			buffer: [192]u8
			set_config_notice(app, fmt.bprintf(buffer[:], "keybindings[%d]: unknown action %s", index, override.action))
			return false
		}
		binding_index := binding_index_for_action(&candidate, action)
		if binding_index < 0 || mentioned[binding_index] {
			buffer: [192]u8
			set_config_notice(app, fmt.bprintf(buffer[:], "keybindings[%d]: duplicate action %s", index, override.action))
			return false
		}
		mentioned[binding_index] = true
		actions[index] = action
		candidate[binding_index].shortcut = {}
		candidate[binding_index].text_len = 0
		candidate[binding_index].customized = true
		if len(override.shortcut) == 0 {
			continue
		}
		shortcut, parsed := parse_shortcut(override.shortcut)
		if !parsed {
			buffer: [192]u8
			set_config_notice(app, fmt.bprintf(buffer[:], "keybindings[%d]: invalid shortcut for %s", index, override.action))
			return false
		}
		canonical, formatted := format_shortcut(shortcut, texts[index][:])
		if !formatted {
			set_config_notice(app, "keybindings: shortcut formatting failed")
			return false
		}
		shortcuts[index] = shortcut
		text_lengths[index] = len(canonical)
	}

	for _, index in overrides {
		action := actions[index]
		binding_index := binding_index_for_action(&candidate, action)
		candidate[binding_index].shortcut = shortcuts[index]
		candidate[binding_index].text_len = text_lengths[index]
		candidate[binding_index].customized = true
		if text_lengths[index] != 0 {
			copy(candidate[binding_index].text[:text_lengths[index]], texts[index][:text_lengths[index]])
		}
	}
	for binding, index in candidate {
		if !shortcut_valid(binding.shortcut) {
			continue
		}
		for other, other_index in candidate {
			if other_index > index && shortcut_valid(other.shortcut) && other.shortcut == binding.shortcut {
				left, _ := action_definition(binding.action)
				right, _ := action_definition(other.action)
				buffer: [192]u8
				set_config_notice(app, fmt.bprintf(buffer[:], "keybindings: %s conflicts with %s", left.id, right.id))
				return false
			}
		}
	}
	app.action_bindings = candidate
	return true
}

shortcut_modifier_key :: proc(key: SDL.Keycode) -> bool {
	switch key {
	case SDL.K_LCTRL, SDL.K_RCTRL, SDL.K_LSHIFT, SDL.K_RSHIFT,
	     SDL.K_LALT, SDL.K_RALT, SDL.K_LGUI, SDL.K_RGUI:
		return true
	case:
		return false
	}
}

shortcut_from_key_event :: proc(event: ^SDL.Event) -> (Shortcut, bool) {
	if event == nil || event.type != .KEY_DOWN || event.key.repeat ||
	   event.key.key == SDL.K_UNKNOWN || shortcut_modifier_key(event.key.key) {
		return {}, false
	}
	return Shortcut{
		key = event.key.key,
		modifiers = shortcut_modifiers_from_sdl(event.key.mod),
	}, true
}
