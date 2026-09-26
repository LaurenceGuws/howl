package main

import "core:testing"
import SDL "vendor:sdl3"

@(test)
server_settings_new_edit_and_delete_preserve_exact_model :: proc(t: ^testing.T) {
    app: App
    testing.expect(t, server_settings_begin_new(&app))
    testing.expect(t, app.server_settings.editing)
    testing.expect(t, server_settings_append_text(&app, "Lab"))
    app.server_settings.field = 1
    app.server_settings.select_all = true
    testing.expect(t, server_settings_append_text(&app, "tcp://100.96.0.4:43150"))
    testing.expect(t, server_settings_commit(&app, false))
    testing.expect_value(t, app.server_count, 1)
    testing.expect_value(t, server_label(&app.servers[0]), "Lab")
    testing.expect_value(t, server_endpoint(&app.servers[0]), "tcp://100.96.0.4:43150")

    testing.expect(t, server_settings_begin_edit(&app))
    app.server_settings.field = 0
    app.server_settings.select_all = true
    testing.expect(t, server_settings_append_text(&app, "Home"))
    testing.expect(t, server_settings_commit(&app, false))
    testing.expect_value(t, server_label(&app.servers[0]), "Home")

    testing.expect(t, server_settings_delete_selected(&app, false))
    testing.expect_value(t, app.server_count, 1)
    testing.expect(t, app.server_settings.delete_pending)
    testing.expect(t, server_settings_delete_selected(&app, false))
    testing.expect_value(t, app.server_count, 0)
}

@(test)
server_settings_reject_duplicate_endpoint_without_mutating_catalog :: proc(t: ^testing.T) {
    app: App
    first := User_Server_Config{label = "One", endpoint = "tcp://100.96.0.4:43150"}
    second := User_Server_Config{label = "Two", endpoint = "tcp://100.96.0.7:43150"}
    load_server_connections(&app, []User_Server_Config{first, second})
    app.server_settings.selection = 1
    testing.expect(t, server_settings_begin_edit(&app))
    app.server_settings.field = 1
    app.server_settings.select_all = true
    testing.expect(t, server_settings_append_text(&app, "tcp://100.96.0.4:43150"))
    testing.expect(t, !server_settings_commit(&app, false))
    testing.expect_value(t, server_endpoint(&app.servers[1]), "tcp://100.96.0.7:43150")
}

@(test)
server_keyboard_new_arms_one_text_input_guard :: proc(t: ^testing.T) {
    app := App{settings_open = true, settings_page = .Servers, settings_content_focus = true}
    event: SDL.Event
    event.type = .KEY_DOWN
    event.key.key = SDL.K_N
    testing.expect(t, handle_server_settings_key(&app, &event))
    testing.expect(t, app.server_settings.editing)
    testing.expect(t, app.server_settings.discard_text_input_once)
    testing.expect_value(t, server_settings_field_text(&app), "New server")
}
