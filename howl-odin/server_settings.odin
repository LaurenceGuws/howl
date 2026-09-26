package main

import SDL "vendor:sdl3"

SERVER_SETTINGS_FIELD_COUNT :: 2

Server_Settings_State :: struct {
    selection: int,
    delete_pending: bool,
    editing: bool,
    new_server: bool,
    edit_index: int,
    field: int,
    label: [SERVER_LABEL_BYTES]u8,
    label_len: int,
    endpoint: [SERVER_ENDPOINT_BYTES]u8,
    endpoint_len: int,
    select_all: bool,
    discard_text_input_once: bool,
}

server_settings_selected :: proc(app: ^App) -> ^Server_Connection {
    if app == nil || app.server_count == 0 {
        return nil
    }
    index := clamp(app.server_settings.selection, 0, app.server_count - 1)
    return &app.servers[index]
}

server_settings_copy_text :: proc(buffer: []u8, used: ^int, value: string) -> bool {
    if used == nil || len(value) >= len(buffer) {
        return false
    }
    used^ = len(value)
    if len(value) != 0 {
        copy(buffer[:len(value)], transmute([]u8)value)
    }
    return true
}

server_settings_begin_new :: proc(app: ^App) -> bool {
    if app == nil || app.server_count >= MAX_SERVERS {
        return false
    }
    app.server_settings = {
        editing = true,
        new_server = true,
        edit_index = app.server_count,
        field = 0,
        select_all = true,
    }
    if !server_settings_copy_text(app.server_settings.label[:], &app.server_settings.label_len, "New server") ||
       !server_settings_copy_text(app.server_settings.endpoint[:], &app.server_settings.endpoint_len, "tcp://") {
        app.server_settings = {}
        return false
    }
    app.settings_notice_len = 0
    return true
}

server_settings_begin_edit :: proc(app: ^App) -> bool {
    server := server_settings_selected(app)
    if app == nil || server == nil {
        return false
    }
    index := clamp(app.server_settings.selection, 0, app.server_count - 1)
    label := server_label(server)
    endpoint := server_endpoint(server)
    app.server_settings.editing = true
    app.server_settings.new_server = false
    app.server_settings.edit_index = index
    app.server_settings.field = 0
    app.server_settings.select_all = true
    app.server_settings.delete_pending = false
    app.server_settings.discard_text_input_once = false
    if !server_settings_copy_text(app.server_settings.label[:], &app.server_settings.label_len, label) ||
       !server_settings_copy_text(app.server_settings.endpoint[:], &app.server_settings.endpoint_len, endpoint) {
        app.server_settings.editing = false
        return false
    }
    app.settings_notice_len = 0
    return true
}

cancel_server_settings_edit :: proc(app: ^App) {
    if app == nil do return
    selection := app.server_settings.selection
    delete_pending := app.server_settings.delete_pending
    app.server_settings = {selection = selection, delete_pending = delete_pending}
}

server_settings_field_text_at :: proc(app: ^App, field: int) -> string {
    if app == nil do return ""
    if field == 0 {
        return string(app.server_settings.label[:app.server_settings.label_len])
    }
    return string(app.server_settings.endpoint[:app.server_settings.endpoint_len])
}

server_settings_field_text :: proc(app: ^App) -> string {
    return app == nil ? "" : server_settings_field_text_at(app, app.server_settings.field)
}

server_settings_append_text :: proc(app: ^App, text: string) -> bool {
    if app == nil || !app.server_settings.editing || len(text) == 0 {
        return false
    }
    buffer: []u8
    used: ^int
    if app.server_settings.field == 0 {
        buffer = app.server_settings.label[:]
        used = &app.server_settings.label_len
    } else {
        buffer = app.server_settings.endpoint[:]
        used = &app.server_settings.endpoint_len
    }
    start := app.server_settings.select_all ? 0 : used^
    if start + len(text) >= len(buffer) {
        set_settings_notice(app, "Server field limit reached")
        return false
    }
    used^ = start
    app.server_settings.select_all = false
    copy(buffer[used^:used^ + len(text)], transmute([]u8)text)
    used^ += len(text)
    return true
}

server_settings_backspace :: proc(app: ^App) -> bool {
    if app == nil || !app.server_settings.editing {
        return false
    }
    buffer: []u8
    used: ^int
    if app.server_settings.field == 0 {
        buffer = app.server_settings.label[:]
        used = &app.server_settings.label_len
    } else {
        buffer = app.server_settings.endpoint[:]
        used = &app.server_settings.endpoint_len
    }
    if app.server_settings.select_all {
        used^ = 0
        app.server_settings.select_all = false
        return true
    }
    if used^ == 0 do return false
    next := used^ - 1
    for next > 0 && buffer[next] & 0xc0 == 0x80 {
        next -= 1
    }
    used^ = next
    return true
}

server_settings_duplicate_endpoint :: proc(app: ^App, endpoint: string, ignored_index: int) -> bool {
    if app == nil do return false
    for index in 0..<app.server_count {
        if index != ignored_index && server_endpoint(&app.servers[index]) == endpoint {
            return true
        }
    }
    return false
}

server_settings_commit :: proc(app: ^App, persist := true) -> bool {
    if app == nil || !app.server_settings.editing {
        return false
    }
    label := string(app.server_settings.label[:app.server_settings.label_len])
    endpoint := string(app.server_settings.endpoint[:app.server_settings.endpoint_len])
    if !valid_server_label(label) {
        set_settings_notice(app, "Server label is required")
        return false
    }
    if !valid_server_endpoint(endpoint) {
        set_settings_notice(app, "Endpoint must use tcp:// or unix:")
        return false
    }
    ignored := app.server_settings.new_server ? -1 : app.server_settings.edit_index
    if server_settings_duplicate_endpoint(app, endpoint, ignored) {
        set_settings_notice(app, "Server endpoint is already configured")
        return false
    }
    server: Server_Connection
    if !server_connection_from_config({label = label, endpoint = endpoint}, &server) {
        set_settings_notice(app, "Server could not be saved")
        return false
    }
    index := app.server_settings.edit_index
    if app.server_settings.new_server {
        if app.server_count >= MAX_SERVERS do return false
        index = app.server_count
        app.server_count += 1
    } else if index < 0 || index >= app.server_count {
        return false
    }
    app.servers[index] = server
    app.server_settings.selection = index
    app.server_settings.editing = false
    app.server_settings.new_server = false
    app.server_settings.select_all = false
    app.server_settings.discard_text_input_once = false
    app.server_settings.delete_pending = false
    if persist do save_user_config(app)
    set_settings_notice(app, "Server saved")
    return true
}

server_settings_delete_selected :: proc(app: ^App, persist := true) -> bool {
    if app == nil || app.server_count == 0 || app.server_settings.editing {
        return false
    }
    index := clamp(app.server_settings.selection, 0, app.server_count - 1)
    if !app.server_settings.delete_pending {
        app.server_settings.delete_pending = true
        set_settings_notice(app, "Press Delete again to remove this server")
        return true
    }
    for current in index..<app.server_count - 1 {
        app.servers[current] = app.servers[current + 1]
    }
    app.server_count -= 1
    app.servers[app.server_count] = {}
    app.server_settings.selection = clamp(index, 0, max(0, app.server_count - 1))
    app.server_settings.delete_pending = false
    if persist do save_user_config(app)
    set_settings_notice(app, "Server deleted")
    return true
}

server_settings_open_selected :: proc(app: ^App) -> bool {
    if app == nil || app.server_count == 0 || app.server_settings.editing {
        return false
    }
    index := clamp(app.server_settings.selection, 0, app.server_count - 1)
    return open_server_browser(app, index)
}

open_server_settings :: proc(app: ^App) {
    if app == nil do return
    if app.search_open do close_search(app)
    close_settings_search(app)
    cancel_profile_edit(app)
    cancel_server_settings_edit(app)
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = true
    app.settings_page = .Servers
    app.settings_content_focus = true
    app.server_settings.selection = clamp(app.server_settings.selection, 0, max(0, app.server_count - 1))
    app.settings_binding_recording = false
    app.settings_notice_len = 0
}

handle_server_settings_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
    if app == nil || !app.settings_open || app.settings_page != .Servers || event == nil {
        return false
    }
    if event.type != .KEY_DOWN {
        return true
    }
    ctrl := .LCTRL in event.key.mod || .RCTRL in event.key.mod
    if app.server_settings.editing {
        if ctrl && event.key.key == SDL.K_A {
            app.server_settings.select_all = true
            return true
        }
        switch event.key.key {
        case SDL.K_ESCAPE:
            cancel_server_settings_edit(app)
            set_settings_notice(app, "Server edit canceled")
        case SDL.K_TAB, SDL.K_DOWN:
            app.server_settings.field = (app.server_settings.field + 1) % SERVER_SETTINGS_FIELD_COUNT
            app.server_settings.select_all = true
        case SDL.K_UP:
            app.server_settings.field = (app.server_settings.field + SERVER_SETTINGS_FIELD_COUNT - 1) % SERVER_SETTINGS_FIELD_COUNT
            app.server_settings.select_all = true
        case SDL.K_RETURN:
            if app.server_settings.field == 0 {
                app.server_settings.field = 1
                app.server_settings.select_all = true
            } else {
                _ = server_settings_commit(app)
            }
        case SDL.K_BACKSPACE, SDL.K_DELETE:
            _ = server_settings_backspace(app)
        case:
        }
        return true
    }

    if event.key.key != SDL.K_DELETE && event.key.key != SDL.K_BACKSPACE {
        app.server_settings.delete_pending = false
    }
    switch event.key.key {
    case SDL.K_TAB, SDL.K_ESCAPE:
        app.settings_content_focus = false
    case SDL.K_UP:
        if app.server_count > 0 {
            app.server_settings.selection = (app.server_settings.selection + app.server_count - 1) % app.server_count
        }
    case SDL.K_DOWN:
        if app.server_count > 0 {
            app.server_settings.selection = (app.server_settings.selection + 1) % app.server_count
        }
    case SDL.K_RETURN:
        if app.server_count == 0 {
            _ = server_settings_begin_new(app)
        } else {
            _ = server_settings_open_selected(app)
        }
    case SDL.K_N:
        if event.key.repeat do return true
        if server_settings_begin_new(app) do app.server_settings.discard_text_input_once = true
    case SDL.K_E:
        if event.key.repeat do return true
        if server_settings_begin_edit(app) do app.server_settings.discard_text_input_once = true
    case SDL.K_DELETE, SDL.K_BACKSPACE:
        if event.key.repeat do return true
        _ = server_settings_delete_selected(app)
    case:
        return false
    }
    return true
}
