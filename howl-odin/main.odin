package main

import "core:c"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

UI_FONT_PATH :: "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
HOME_ENDPOINT :: "tcp://127.0.0.1:39601"
SESSION_TEXT_BYTES :: 512 * 1024
SESSION_RETRY_MS :: 50
MAX_TABS :: 8
FONT_PRESET_MIN :: 0
FONT_PRESET_MAX :: 2

Tab_Kind :: enum {
    Session,
}

Tab :: struct {
    kind: Tab_Kind,
    title: string,
}

App_Action :: enum {
    New_Tab,
    Attach_Home,
    Open_Settings,
    Close_Tab,
}

Settings_Page :: enum {
    Startup,
    Interaction,
    Appearance,
    Color_Schemes,
    Actions,
    Profile_Defaults,
    Profile_Home,
}

Palette :: struct {
    window_bg: SDL.Color,
    title_bg: SDL.Color,
    tab_active: SDL.Color,
    tab_idle: SDL.Color,
    terminal_bg: SDL.Color,
    terminal_panel: SDL.Color,
    border: SDL.Color,
    text: SDL.Color,
    text_muted: SDL.Color,
    accent: SDL.Color,
}

palette := Palette{
    window_bg = {14, 17, 22, 255},
    title_bg = {26, 30, 38, 255},
    tab_active = {42, 48, 59, 255},
    tab_idle = {31, 36, 45, 255},
    terminal_bg = {9, 11, 14, 255},
    terminal_panel = {13, 16, 20, 255},
    border = {60, 68, 82, 255},
    text = {220, 226, 234, 255},
    text_muted = {137, 148, 164, 255},
    accent = {96, 165, 250, 255},
}

App :: struct {
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    text_engine: ^TTF.TextEngine,
    ui_font: ^TTF.Font,
    terminal_font: ^TTF.Font,
    terminal_font_preset: int,
    running: bool,
    tabs: [MAX_TABS]Tab,
    tab_count: int,
    active_tab: int,
    profile_menu_open: bool,
    profile_menu_selection: int,
    palette_open: bool,
    palette_selection: int,
    settings_open: bool,
    settings_page: Settings_Page,
    session: rawptr,
    session_text: []u8,
    session_text_len: int,
    session_revision: u64,
    session_terminal_revision: u64,
    session_rows: u16,
    session_columns: u16,
    session_cursor_row: u16,
    session_cursor_column: u16,
    session_cursor_visible: bool,
    session_cursor_shape: u8,
    session_history_count: u32,
    session_alternate_screen: bool,
    session_text_truncated: bool,
    session_error: [160]u8,
    session_error_len: int,
    session_mutex: sync.Mutex,
    session_worker_stop: bool,
}

Session_Worker :: struct {
    app: ^App,
    observer: rawptr,
    scratch: []u8,
}

font_size_for_preset :: proc(preset: int) -> f32 {
    switch preset {
    case 0: return 12
    case 1: return 15
    case:   return 18
    }
}

font_size_label :: proc(preset: int) -> string {
    switch preset {
    case 0: return "12 px"
    case 1: return "15 px"
    case:   return "18 px"
    }
}

adjust_terminal_font :: proc(app: ^App, delta: int) {
    next := clamp(app.terminal_font_preset + delta, FONT_PRESET_MIN, FONT_PRESET_MAX)
    if next == app.terminal_font_preset {
        return
    }
    if TTF.SetFontSize(app.terminal_font, font_size_for_preset(next)) {
        app.terminal_font_preset = next
    }
}

sdl_error :: proc(label: string) {
    fmt.eprintln(label, ": ", SDL.GetError())
}

set_draw_color :: proc(renderer: ^SDL.Renderer, color: SDL.Color) {
    _ = SDL.SetRenderDrawColor(renderer, color[0], color[1], color[2], color[3])
}

draw_fill :: proc(renderer: ^SDL.Renderer, rect: SDL.FRect, color: SDL.Color) {
    set_draw_color(renderer, color)
    draw_rect := rect
    _ = SDL.RenderFillRect(renderer, &draw_rect)
}

draw_outline :: proc(renderer: ^SDL.Renderer, rect: SDL.FRect, color: SDL.Color) {
    set_draw_color(renderer, color)
    draw_rect := rect
    _ = SDL.RenderRect(renderer, &draw_rect)
}

draw_text :: proc(app: ^App, font: ^TTF.Font, text: string, x, y: f32, color: SDL.Color) {
    if len(text) == 0 {
        return
    }
    label := TTF.CreateText(app.text_engine, font, cstring(raw_data(text)), c.size_t(len(text)))
    if label == nil {
        return
    }
    defer TTF.DestroyText(label)
    _ = TTF.SetTextColor(label, color[0], color[1], color[2], color[3])
    _ = TTF.DrawRendererText(label, x, y)
}

publish_bridge_error :: proc(app: ^App, handle: rawptr) {
    if handle == nil {
        return
    }
    message: [160]u8
    error_len: c.size_t
    copy_error(
        handle,
        raw_data(message[:]),
        c.size_t(len(message)),
        &error_len,
    )
    sync.mutex_lock(&app.session_mutex)
    copy(app.session_error[:], message[:int(error_len)])
    app.session_error_len = int(error_len)
    sync.mutex_unlock(&app.session_mutex)
}

observe_session :: proc(data: rawptr) {
    worker := (^Session_Worker)(data)
    app := worker.app
    observer := worker.observer
    after_revision: u64
    for {
        sync.mutex_lock(&app.session_mutex)
        stop := app.session_worker_stop
        sync.mutex_unlock(&app.session_mutex)
        if stop {
            break
        }

        output_len: c.size_t
        result := snapshot(
            observer,
            after_revision,
            0,
            raw_data(worker.scratch),
            c.size_t(len(worker.scratch)),
            &output_len,
        )
        if result != 0 {
            sync.mutex_lock(&app.session_mutex)
            stopped := app.session_worker_stop
            sync.mutex_unlock(&app.session_mutex)
            if stopped {
                break
            }
            publish_bridge_error(app, observer)
            after_revision = 0
            time.sleep(SESSION_RETRY_MS * time.Millisecond)
            continue
        }

        snapshot_revision := revision(observer)
        after_revision = snapshot_revision
        snapshot_terminal_revision := terminal_revision(observer)
        snapshot_rows := rows(observer)
        snapshot_columns := columns(observer)
        snapshot_cursor_row := cursor_row(observer)
        snapshot_cursor_column := cursor_column(observer)
        snapshot_cursor_visible := cursor_visible(observer) != 0
        snapshot_cursor_shape := cursor_shape(observer)
        snapshot_history_count := history_count(observer)
        snapshot_alternate_screen := alternate_screen(observer) != 0
        snapshot_text_truncated := text_truncated(observer) != 0

        sync.mutex_lock(&app.session_mutex)
        copy(app.session_text[:int(output_len)], worker.scratch[:int(output_len)])
        app.session_text_len = int(output_len)
        app.session_revision = snapshot_revision
        app.session_terminal_revision = snapshot_terminal_revision
        app.session_rows = snapshot_rows
        app.session_columns = snapshot_columns
        app.session_cursor_row = snapshot_cursor_row
        app.session_cursor_column = snapshot_cursor_column
        app.session_cursor_visible = snapshot_cursor_visible
        app.session_cursor_shape = snapshot_cursor_shape
        app.session_history_count = snapshot_history_count
        app.session_alternate_screen = snapshot_alternate_screen
        app.session_text_truncated = snapshot_text_truncated
        app.session_error_len = 0
        sync.mutex_unlock(&app.session_mutex)
    }
}

publish_initial_error :: proc(app: ^App, message: string) {
    sync.mutex_lock(&app.session_mutex)
    count := min(len(message), len(app.session_error))
    for byte, index in message[:count] {
        app.session_error[index] = u8(byte)
    }
    app.session_error_len = count
    sync.mutex_unlock(&app.session_mutex)
}

stop_session_worker :: proc(app: ^App) {
    sync.mutex_lock(&app.session_mutex)
    app.session_worker_stop = true
    sync.mutex_unlock(&app.session_mutex)
}

session_attached :: proc(app: ^App) -> bool {
    sync.mutex_lock(&app.session_mutex)
    attached := app.session != nil && app.session_revision != 0 && app.session_error_len == 0
    sync.mutex_unlock(&app.session_mutex)
    return attached
}

copy_bridge_error :: proc(app: ^App) {
    publish_bridge_error(app, app.session)
}

bridge_modifiers :: proc(mods: SDL.Keymod) -> u8 {
    result: u8
    if .LSHIFT in mods || .RSHIFT in mods do result |= BRIDGE_MOD_SHIFT
    if .LALT in mods || .RALT in mods do result |= BRIDGE_MOD_ALT
    if .LCTRL in mods || .RCTRL in mods do result |= BRIDGE_MOD_CTRL
    if .LGUI in mods || .RGUI in mods do result |= BRIDGE_MOD_SUPER
    if .CAPS in mods do result |= BRIDGE_MOD_CAPS
    if .NUM in mods do result |= BRIDGE_MOD_NUM
    return result
}

named_bridge_key :: proc(key: SDL.Keycode) -> (Bridge_Key, bool) {
    switch key {
    case SDL.K_RETURN:    return .Enter, true
    case SDL.K_TAB:       return .Tab, true
    case SDL.K_BACKSPACE: return .Backspace, true
    case SDL.K_ESCAPE:    return .Escape, true
    case SDL.K_UP:        return .Up, true
    case SDL.K_DOWN:      return .Down, true
    case SDL.K_LEFT:      return .Left, true
    case SDL.K_RIGHT:     return .Right, true
    case SDL.K_INSERT:    return .Insert, true
    case SDL.K_DELETE:    return .Delete, true
    case SDL.K_HOME:      return .Home, true
    case SDL.K_END:       return .End, true
    case SDL.K_PAGEUP:    return .Page_Up, true
    case SDL.K_PAGEDOWN:  return .Page_Down, true
    case:                  return .Enter, false
    }
}

send_bridge_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
    if app.session == nil || !active_tab_is_session(app) || app.profile_menu_open || app.palette_open || app.settings_open {
        return false
    }
    key, ok := named_bridge_key(event.key.key)
    if !ok {
        return false
    }
    action := Bridge_Key_Action.Press
    if event.type == .KEY_UP {
        action = .Release
    } else if event.key.repeat {
        action = .Repeat
    }
    result := send_named_key(
        app.session,
        u8(key),
        u8(action),
        bridge_modifiers(event.key.mod),
    )
    if result != 0 {
        copy_bridge_error(app)
    }
    return true
}

inside :: proc(x, y: f32, rect: SDL.FRect) -> bool {
    return x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h
}

tab_controls :: proc(tab_count: int, width: f32) -> (plus, menu, settings: SDL.FRect) {
    tab_w := f32(162)
    controls_x := f32(8) + f32(tab_count) * (tab_w + 4)
    plus = {controls_x, 7, 34, 32}
    menu = {controls_x + 38, 7, 34, 32}
    settings = {width - 114, 7, 104, 32}
    return
}

new_tab :: proc(app: ^App) {
    if app.tab_count >= MAX_TABS {
        return
    }
    app.tabs[app.tab_count] = Tab{kind = .Session, title = "Home Session"}
    app.tab_count += 1
    app.active_tab = app.tab_count - 1
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
}

close_tab :: proc(app: ^App, index: int) {
    if app.tab_count <= 1 || index < 0 || index >= app.tab_count {
        return
    }
    for i in index..<app.tab_count - 1 {
        app.tabs[i] = app.tabs[i + 1]
    }
    app.tabs[app.tab_count - 1] = {}
    app.tab_count -= 1
    if app.active_tab > index {
        app.active_tab -= 1
    } else if app.active_tab >= app.tab_count {
        app.active_tab = app.tab_count - 1
    }
}

active_tab_is_session :: proc(app: ^App) -> bool {
    return app.active_tab >= 0 && app.active_tab < app.tab_count && app.tabs[app.active_tab].kind == .Session
}

execute_action :: proc(app: ^App, action: App_Action) {
    switch action {
    case .New_Tab, .Attach_Home:
        new_tab(app)
    case .Open_Settings:
        app.profile_menu_open = false
        app.palette_open = false
        app.settings_open = true
    case .Close_Tab:
        close_tab(app, app.active_tab)
        app.palette_open = false
    }
}

palette_action :: proc(index: int) -> App_Action {
    switch index {
    case 0: return .New_Tab
    case 1: return .Attach_Home
    case 2: return .Open_Settings
    case:   return .Close_Tab
    }
}

handle_overlay_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
    if event.type != .KEY_DOWN {
        return false
    }
    if app.palette_open {
        switch event.key.key {
        case SDL.K_ESCAPE:
            app.palette_open = false
        case SDL.K_UP:
            app.palette_selection = (app.palette_selection + 3) % 4
        case SDL.K_DOWN, SDL.K_TAB:
            app.palette_selection = (app.palette_selection + 1) % 4
        case SDL.K_RETURN:
            execute_action(app, palette_action(app.palette_selection))
        case:
            return false
        }
        return true
    }
    if app.profile_menu_open {
        switch event.key.key {
        case SDL.K_ESCAPE:
            app.profile_menu_open = false
        case SDL.K_UP:
            app.profile_menu_selection = (app.profile_menu_selection + 2) % 3
        case SDL.K_DOWN, SDL.K_TAB:
            app.profile_menu_selection = (app.profile_menu_selection + 1) % 3
        case SDL.K_RETURN:
            if app.profile_menu_selection == 0 {
                execute_action(app, .Attach_Home)
            } else if app.profile_menu_selection == 1 {
                app.profile_menu_open = false
                app.palette_open = true
                app.palette_selection = 0
            } else {
                execute_action(app, .Open_Settings)
            }
        case:
            return false
        }
        return true
    }
    if app.settings_open {
        page := int(app.settings_page)
        switch event.key.key {
        case SDL.K_LEFT, SDL.K_MINUS:
            if app.settings_page == .Appearance {
                adjust_terminal_font(app, -1)
                return true
            }
            return false
        case SDL.K_RIGHT, SDL.K_EQUALS, SDL.K_PLUS:
            if app.settings_page == .Appearance {
                adjust_terminal_font(app, 1)
                return true
            }
            return false
        case SDL.K_UP:
            app.settings_page = Settings_Page((page + 6) % 7)
        case SDL.K_DOWN, SDL.K_TAB:
            app.settings_page = Settings_Page((page + 1) % 7)
        case SDL.K_HOME:
            app.settings_page = .Startup
        case SDL.K_END:
            app.settings_page = .Profile_Home
        case:
            return false
        }
        return true
    }
    return false
}

profile_menu_rect :: proc(tab_count: int) -> SDL.FRect {
    _, menu, _ := tab_controls(tab_count, 0)
    return {menu.x - 8, 44, 310, 166}
}

settings_panel_rect :: proc(width, height: f32) -> SDL.FRect {
    return {width - 620, 58, 602, height - 76}
}

settings_page_at :: proc(x, y: f32, width, height: f32) -> (Settings_Page, bool) {
    panel := settings_panel_rect(width, height)
    sidebar := SDL.FRect{panel.x, panel.y, 178, panel.h}
    if !inside(x, y, sidebar) {
        return .Startup, false
    }
    tops := [7]f32{52, 86, 120, 154, 188, 272, 306}
    for top, index in tops {
        row := SDL.FRect{sidebar.x + 8, sidebar.y + top, sidebar.w - 16, 30}
        if inside(x, y, row) {
            return Settings_Page(index), true
        }
    }
    return .Startup, false
}

handle_click :: proc(app: ^App, x, y, width, height: f32) {
    plus, menu, settings := tab_controls(app.tab_count, width)

    if app.settings_open {
        if page, ok := settings_page_at(x, y, width, height); ok {
            app.settings_page = page
            return
        }
    }

    if app.palette_open {
        box_w := f32(520)
        box := SDL.FRect{(width - box_w) / 2, 92, box_w, 252}
        for i in 0..<4 {
            row := SDL.FRect{box.x + 18, box.y + 70 + f32(i) * 36, box.w - 36, 34}
            if inside(x, y, row) {
                execute_action(app, palette_action(i))
                return
            }
        }
        if !inside(x, y, box) {
            app.palette_open = false
        }
    }

    if app.profile_menu_open {
        panel := profile_menu_rect(app.tab_count)
        if inside(x, y, {panel.x + 8, panel.y + 8, panel.w - 16, 40}) {
            execute_action(app, .Attach_Home)
            return
        }
        if inside(x, y, {panel.x + 8, panel.y + 62, panel.w - 16, 36}) {
            app.profile_menu_open = false
            app.palette_open = true
            app.palette_selection = 0
            return
        }
        if inside(x, y, {panel.x + 8, panel.y + 108, panel.w - 16, 36}) {
            execute_action(app, .Open_Settings)
            return
        }
        if !inside(x, y, panel) {
            app.profile_menu_open = false
        }
    }

    if inside(x, y, plus) {
        new_tab(app)
        return
    }
    if inside(x, y, menu) {
        app.profile_menu_open = !app.profile_menu_open
        app.profile_menu_selection = 0
        app.palette_open = false
        app.settings_open = false
        return
    }
    if inside(x, y, settings) {
        app.settings_open = !app.settings_open
        app.palette_open = false
        return
    }

    tab_x := f32(8)
    tab_w := f32(162)
    for i in 0..<app.tab_count {
        rect := SDL.FRect{tab_x, 7, tab_w, 32}
        if inside(x, y, rect) {
            close_rect := SDL.FRect{rect.x + rect.w - 30, rect.y, 30, rect.h}
            if app.tab_count > 1 && inside(x, y, close_rect) {
                close_tab(app, i)
                return
            }
            app.active_tab = i
            return
        }
        tab_x += tab_w + 4
    }
}

handle_event :: proc(app: ^App, event: ^SDL.Event) {
    #partial switch event.type {
    case .QUIT, .WINDOW_CLOSE_REQUESTED:
        app.running = false
    case .KEY_DOWN, .KEY_UP:
        ctrl := .LCTRL in event.key.mod || .RCTRL in event.key.mod
        shift := .LSHIFT in event.key.mod || .RSHIFT in event.key.mod
        alt := .LALT in event.key.mod || .RALT in event.key.mod
        if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_P {
            app.palette_open = !app.palette_open
            app.palette_selection = 0
            app.profile_menu_open = false
            app.settings_open = false
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_SPACE {
            app.profile_menu_open = !app.profile_menu_open
            app.profile_menu_selection = 0
            app.palette_open = false
            app.settings_open = false
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_COMMA {
            app.settings_open = !app.settings_open
            app.profile_menu_open = false
            app.palette_open = false
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_T {
            new_tab(app)
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_MINUS {
            adjust_terminal_font(app, -1)
        } else if event.type == .KEY_DOWN && ctrl && (event.key.key == SDL.K_EQUALS || event.key.key == SDL.K_PLUS) {
            adjust_terminal_font(app, 1)
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_W {
            execute_action(app, .Close_Tab)
        } else if event.type == .KEY_DOWN && event.key.key == SDL.K_ESCAPE && (app.profile_menu_open || app.palette_open || app.settings_open) {
            app.profile_menu_open = false
            app.palette_open = false
            app.settings_open = false
        } else if handle_overlay_key(app, event) {
            // Overlay-owned navigation never reaches the terminal.
        } else if send_bridge_key(app, event) {
            // The active real Session consumed this named physical key.
        } else if event.type == .KEY_DOWN && app.session != nil && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && (ctrl || alt) {
            scalar := u32(event.key.key)
            if scalar > 0 && scalar < 0x80 {
                action := event.key.repeat ? Bridge_Key_Action.Repeat : Bridge_Key_Action.Press
                result := send_unicode_key(
                    app.session,
                    scalar,
                    u8(action),
                    bridge_modifiers(event.key.mod),
                )
                if result != 0 {
                    copy_bridge_error(app)
                }
            }
        }
    case .TEXT_INPUT:
        if app.session != nil && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && event.text.text != nil {
            text := string(event.text.text)
            if len(text) != 0 {
                result := send_text(app.session, raw_data(text), c.size_t(len(text)))
                if result != 0 {
                    copy_bridge_error(app)
                }
            }
        }
    case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        w, h: c.int
        if event.type == .MOUSE_BUTTON_UP && SDL.GetWindowSize(app.window, &w, &h) {
            handle_click(app, event.button.x, event.button.y, f32(w), f32(h))
        }
    case:
    }
}

draw_tabs :: proc(app: ^App, width: f32) {
    tab_x := f32(8)
    tab_w := f32(162)

    for i in 0..<app.tab_count {
        active := i == app.active_tab
        rect := SDL.FRect{tab_x, 7, tab_w, 32}
        draw_fill(app.renderer, rect, active ? palette.tab_active : palette.tab_idle)
        if active {
            underline := SDL.FRect{tab_x + 10, 37, tab_w - 20, 2}
            draw_fill(app.renderer, underline, palette.accent)
        }

        draw_text(app, app.ui_font, app.tabs[i].title, tab_x + 14, 14, active ? palette.text : palette.text_muted)
        if app.tabs[i].kind == .Session && session_attached(app) {
            indicator_x := tab_x + tab_w - (app.tab_count > 1 ? 38 : 16)
            draw_fill(app.renderer, {indicator_x, 20, 5, 5}, palette.accent)
        }
        if app.tab_count > 1 {
            draw_text(app, app.ui_font, "x", tab_x + tab_w - 21, 14, palette.text_muted)
        }
        tab_x += tab_w + 4
    }

    plus, menu, settings := tab_controls(app.tab_count, width)
    draw_fill(app.renderer, plus, palette.tab_idle)
    draw_fill(app.renderer, menu, palette.tab_idle)
    draw_fill(app.renderer, settings, palette.tab_idle)
    draw_text(app, app.ui_font, "+", plus.x + 11, plus.y + 6, palette.text)
    draw_text(app, app.ui_font, "v", menu.x + 11, menu.y + 6, palette.text_muted)
    draw_text(app, app.ui_font, "Settings", settings.x + 12, settings.y + 6, palette.text_muted)
}

draw_profile_menu :: proc(app: ^App) {
    panel := profile_menu_rect(app.tab_count)
    draw_fill(app.renderer, panel, palette.title_bg)
    draw_outline(app.renderer, panel, palette.border)

    rows := [3]SDL.FRect{
        {panel.x + 8, panel.y + 8, panel.w - 16, 40},
        {panel.x + 8, panel.y + 62, panel.w - 16, 36},
        {panel.x + 8, panel.y + 108, panel.w - 16, 36},
    }
    draw_fill(app.renderer, rows[app.profile_menu_selection], palette.tab_active)
    draw_text(app, app.ui_font, "Home Session", panel.x + 18, panel.y + 17, palette.text)
    draw_text(app, app.ui_font, HOME_ENDPOINT, panel.x + 18, panel.y + 39, palette.text_muted)
    draw_fill(app.renderer, {panel.x + 10, panel.y + 57, panel.w - 20, 1}, palette.border)
    draw_text(app, app.ui_font, "Command Palette", panel.x + 18, panel.y + 72, palette.text)
    draw_text(app, app.ui_font, "Ctrl+Shift+P", panel.x + 178, panel.y + 72, palette.text_muted)
    draw_text(app, app.ui_font, "Settings", panel.x + 18, panel.y + 118, palette.text)
    draw_text(app, app.ui_font, "Ctrl+,", panel.x + 228, panel.y + 118, palette.text_muted)
}

draw_real_session :: proc(app: ^App, width, height: f32) {
    sync.mutex_lock(&app.session_mutex)
    defer sync.mutex_unlock(&app.session_mutex)

    origin_x := f32(28)
    origin_y := f32(58)
    if app.session_error_len != 0 {
        draw_text(app, app.ui_font, string(app.session_error[:app.session_error_len]), origin_x, origin_y, palette.accent)
        return
    }
    if app.session_text_len != 0 {
        draw_text(app, app.terminal_font, string(app.session_text[:app.session_text_len]), origin_x, origin_y, palette.text)
    }

    if app.session_cursor_visible && app.session_rows != 0 && app.session_columns != 0 {
        cell_w, cell_h: c.int
        if TTF.GetStringSize(app.terminal_font, "M", 1, &cell_w, &cell_h) {
            line_h := TTF.GetFontLineSkip(app.terminal_font)
            cursor_x := origin_x + f32(int(app.session_cursor_column) * int(cell_w))
            cursor_y := origin_y + f32(int(app.session_cursor_row) * int(line_h))
            switch app.session_cursor_shape {
            case 1:
                draw_fill(app.renderer, {cursor_x, cursor_y + f32(line_h - 2), f32(cell_w), 2}, palette.text)
            case 2:
                draw_fill(app.renderer, {cursor_x, cursor_y, 2, f32(line_h)}, palette.text)
            case 3:
            case:
                draw_outline(app.renderer, {cursor_x, cursor_y, f32(cell_w), f32(line_h)}, palette.text_muted)
            }
        }
    }

    if app.session_text_truncated {
        draw_text(app, app.ui_font, "visible-text projection truncated", width - 286, height - 26, palette.accent)
    }
}

draw_placeholder_session :: proc(app: ^App) {
    draw_text(app, app.terminal_font, "Profile shell placeholder", 34, 86, palette.text_muted)
    draw_text(app, app.terminal_font, "The Home tab is the real canonical Howl Session.", 34, 116, palette.text)
}

draw_terminal :: proc(app: ^App, width, height: f32) {
    body := SDL.FRect{0, 46, width, height - 46}
    draw_fill(app.renderer, body, palette.terminal_bg)

    inset := SDL.FRect{18, 52, width - 36, height - 64}
    draw_fill(app.renderer, inset, palette.terminal_panel)

    if active_tab_is_session(app) {
        draw_real_session(app, width, height)
    } else {
        draw_placeholder_session(app)
    }

}

draw_palette :: proc(app: ^App, width, height: f32) {
    box_w := f32(520)
    box_h := f32(252)
    box := SDL.FRect{(width - box_w) / 2, 92, box_w, box_h}
    draw_fill(app.renderer, box, palette.title_bg)
    draw_outline(app.renderer, box, palette.border)

    search := SDL.FRect{box.x + 18, box.y + 18, box.w - 36, 40}
    draw_fill(app.renderer, search, palette.terminal_bg)
    draw_outline(app.renderer, search, palette.accent)
    draw_text(app, app.ui_font, "> Command Palette", search.x + 12, search.y + 10, palette.text)

    labels := [4]string{"New tab", "Attach Home Session", "Open settings", "Close tab"}
    shortcuts := [4]string{"Ctrl+T", "", "Ctrl+,", "Ctrl+Shift+W"}
    for label, i in labels {
        row := SDL.FRect{box.x + 18, box.y + 70 + f32(i) * 36, box.w - 36, 34}
        if app.palette_selection == i {
            draw_fill(app.renderer, row, palette.tab_active)
        }
        enabled := i != 3 || app.tab_count > 1
        color := enabled ? palette.text : palette.text_muted
        draw_text(app, app.ui_font, label, row.x + 10, row.y + 8, color)
        if len(shortcuts[i]) != 0 {
            draw_text(app, app.ui_font, shortcuts[i], row.x + row.w - 132, row.y + 8, palette.text_muted)
        }
    }
}

settings_page_title :: proc(page: Settings_Page) -> string {
    switch page {
    case .Startup:          return "Startup"
    case .Interaction:      return "Interaction"
    case .Appearance:       return "Appearance"
    case .Color_Schemes:    return "Color schemes"
    case .Actions:          return "Actions"
    case .Profile_Defaults: return "Profile defaults"
    case .Profile_Home:     return "Home Session"
    }
    return ""
}

draw_setting_field :: proc(app: ^App, label, value: string, x, y, width: f32) {
    draw_text(app, app.ui_font, label, x, y, palette.text_muted)
    box := SDL.FRect{x, y + 24, width, 38}
    draw_fill(app.renderer, box, palette.terminal_bg)
    draw_outline(app.renderer, box, palette.border)
    draw_text(app, app.ui_font, value, box.x + 12, box.y + 9, palette.text)
}

draw_settings :: proc(app: ^App, width, height: f32) {
    panel := settings_panel_rect(width, height)
    draw_fill(app.renderer, panel, palette.title_bg)
    draw_outline(app.renderer, panel, palette.border)

    sidebar := SDL.FRect{panel.x, panel.y, 178, panel.h}
    draw_fill(app.renderer, sidebar, palette.tab_idle)
    draw_text(app, app.ui_font, "Settings", sidebar.x + 18, sidebar.y + 18, palette.text)

    labels := [7]string{"Startup", "Interaction", "Appearance", "Color schemes", "Actions", "  Defaults", "  Home Session"}
    tops := [7]f32{52, 86, 120, 154, 188, 272, 306}
    for label, index in labels {
        row := SDL.FRect{sidebar.x + 8, sidebar.y + tops[index], sidebar.w - 16, 30}
        selected := int(app.settings_page) == index
        if selected {
            draw_fill(app.renderer, row, palette.tab_active)
        }
        draw_text(app, app.ui_font, label, row.x + 10, row.y + 6, selected ? palette.accent : palette.text_muted)
    }
    draw_text(app, app.ui_font, "Profiles", sidebar.x + 18, sidebar.y + 250, palette.text)

    content_x := sidebar.x + sidebar.w + 28
    content_y := panel.y + 22
    draw_text(app, app.ui_font, settings_page_title(app.settings_page), content_x, content_y, palette.text)

    switch app.settings_page {
    case .Startup:
        draw_setting_field(app, "Default profile", "Home Session", content_x, content_y + 48, 300)
        draw_setting_field(app, "Startup action", "Attach existing Session", content_x, content_y + 126, 300)
        draw_setting_field(app, "Endpoint", HOME_ENDPOINT, content_x, content_y + 204, 360)
    case .Interaction:
        draw_setting_field(app, "Input path", "howl-client semantic actions", content_x, content_y + 48, 340)
        draw_setting_field(app, "Observation", "Blocking revision worker", content_x, content_y + 126, 340)
        draw_setting_field(app, "Clipboard / selection", "Not wired yet", content_x, content_y + 204, 340)
    case .Appearance:
        draw_setting_field(app, "Theme", "Dark", content_x, content_y + 48, 248)
        draw_setting_field(app, "Terminal font", "JetBrainsMono Nerd Font", content_x, content_y + 126, 340)
        draw_setting_field(app, "Font size   Left/Right or -/+", font_size_label(app.terminal_font_preset), content_x, content_y + 204, 248)
        draw_setting_field(app, "Coordinate space", "Window-logical / HiDPI scaled", content_x, content_y + 282, 340)
    case .Color_Schemes:
        draw_setting_field(app, "Current scheme", "Howl Dark", content_x, content_y + 48, 300)
        draw_text(app, app.ui_font, "Palette", content_x, content_y + 134, palette.text_muted)
        colors := [6]SDL.Color{palette.terminal_bg, palette.tab_idle, palette.border, palette.text_muted, palette.text, palette.accent}
        for color, index in colors {
            swatch := SDL.FRect{content_x + f32(index) * 52, content_y + 164, 40, 40}
            draw_fill(app.renderer, swatch, color)
            draw_outline(app.renderer, swatch, palette.border)
        }
    case .Actions:
        action_names := [5]string{"New tab", "Close tab", "Command Palette", "Profile menu", "Settings"}
        action_keys := [5]string{"Ctrl+T", "Ctrl+Shift+W", "Ctrl+Shift+P", "Ctrl+Shift+Space", "Ctrl+,"}
        for name, index in action_names {
            y := content_y + 54 + f32(index) * 42
            draw_text(app, app.ui_font, name, content_x, y, palette.text)
            draw_text(app, app.ui_font, action_keys[index], content_x + 230, y, palette.text_muted)
        }
    case .Profile_Defaults:
        draw_setting_field(app, "Profile kind", "Attach recipe", content_x, content_y + 48, 300)
        draw_setting_field(app, "Geometry leadership", "Observer only", content_x, content_y + 126, 300)
        draw_setting_field(app, "Session lifetime", "Node-owned canonical Session", content_x, content_y + 204, 340)
    case .Profile_Home:
        draw_setting_field(app, "Name", "Home Session", content_x, content_y + 48, 300)
        draw_setting_field(app, "Endpoint", HOME_ENDPOINT, content_x, content_y + 126, 360)
        draw_setting_field(app, "Transport", "TCP / howl-client", content_x, content_y + 204, 300)
        draw_setting_field(app, "Geometry", "Attach without resize leadership", content_x, content_y + 282, 360)
    }
}

draw :: proc(app: ^App) {
    w, h: c.int
    if !SDL.GetWindowSize(app.window, &w, &h) {
        return
    }
    _ = SDL.SetRenderLogicalPresentation(app.renderer, w, h, .STRETCH)
    width := f32(w)
    height := f32(h)

    set_draw_color(app.renderer, palette.window_bg)
    _ = SDL.RenderClear(app.renderer)

    tab_bar := SDL.FRect{0, 0, width, 46}
    draw_fill(app.renderer, tab_bar, palette.title_bg)
    draw_tabs(app, width)
    draw_terminal(app, width, height)

    if app.profile_menu_open {
        draw_profile_menu(app)
    }

    if app.palette_open {
        draw_palette(app, width, height)
    }
    if app.settings_open {
        draw_settings(app, width, height)
    }
    _ = SDL.RenderPresent(app.renderer)
}

main :: proc() {
    if !SDL.Init(SDL.INIT_VIDEO) {
        sdl_error("SDL_Init failed")
        return
    }
    defer SDL.Quit()

    if !TTF.Init() {
        sdl_error("TTF_Init failed")
        return
    }

    window: ^SDL.Window = nil
    renderer: ^SDL.Renderer = nil
    flags := SDL.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY}
    if !SDL.CreateWindowAndRenderer("Howl Desktop - Odin canary", 1180, 760, flags, &window, &renderer) {
        sdl_error("SDL_CreateWindowAndRenderer failed")
        return
    }
    defer SDL.DestroyRenderer(renderer)
    defer SDL.DestroyWindow(window)

    _ = SDL.StartTextInput(window)
    defer {
        _ = SDL.StopTextInput(window)
    }

    _ = SDL.SetRenderVSync(renderer, 1)

    engine := TTF.CreateRendererTextEngine(renderer)
    if engine == nil {
        sdl_error("TTF_CreateRendererTextEngine failed")
        return
    }
    defer TTF.DestroyRendererTextEngine(engine)

    ui_font := TTF.OpenFont(UI_FONT_PATH, 15)
    if ui_font == nil {
        sdl_error("TTF_OpenFont UI failed")
        return
    }
    defer TTF.CloseFont(ui_font)

    terminal_font := TTF.OpenFont(UI_FONT_PATH, 15)
    if terminal_font == nil {
        sdl_error("TTF_OpenFont terminal failed")
        return
    }
    defer TTF.CloseFont(terminal_font)

    session_text := make([]u8, SESSION_TEXT_BYTES)
    defer delete(session_text)
    observer_scratch := make([]u8, SESSION_TEXT_BYTES)
    defer delete(observer_scratch)

    endpoint: string = HOME_ENDPOINT
    control_diagnostic: [160]u8
    control_diagnostic_len: c.size_t
    session := create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(control_diagnostic[:]),
        c.size_t(len(control_diagnostic)),
        &control_diagnostic_len,
    )
    defer {
        if session != nil {
            destroy(session)
        }
    }

    observer_diagnostic: [160]u8
    observer_diagnostic_len: c.size_t
    observer := create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(observer_diagnostic[:]),
        c.size_t(len(observer_diagnostic)),
        &observer_diagnostic_len,
    )
    observer_cancellation := rawptr(nil)
    if observer != nil {
        observer_cancellation = cancellation_create(observer)
    }

    app := App{
        window = window,
        renderer = renderer,
        text_engine = engine,
        ui_font = ui_font,
        terminal_font = terminal_font,
        terminal_font_preset = 1,
        running = true,
        tab_count = 1,
        active_tab = 0,
        session = session,
        session_text = session_text,
    }
    app.tabs[0] = Tab{kind = .Session, title = "Home Session"}

    if session == nil {
        publish_initial_error(&app, string(control_diagnostic[:int(control_diagnostic_len)]))
    } else if observer == nil {
        publish_initial_error(&app, string(observer_diagnostic[:int(observer_diagnostic_len)]))
    } else if observer_cancellation == nil {
        publish_initial_error(&app, "observer_cancellation_failed")
    }

    worker_context := Session_Worker{
        app = &app,
        observer = observer,
        scratch = observer_scratch,
    }
    observer_thread: ^thread.Thread = nil
    if session != nil && observer != nil && observer_cancellation != nil {
        observer_thread = thread.create_and_start_with_data(
            rawptr(&worker_context),
            observe_session,
            name = "howl-odin-observe",
        )
        if observer_thread == nil {
            publish_initial_error(&app, "observer_thread_failed")
        }
    }

    for app.running {
        event: SDL.Event
        for SDL.PollEvent(&event) {
            handle_event(&app, &event)
        }
        draw(&app)
    }

    if observer_thread != nil {
        stop_session_worker(&app)
        _ = cancellation_cancel(observer_cancellation)
        thread.destroy(observer_thread)
    }
    if observer_cancellation != nil {
        cancellation_destroy(observer_cancellation)
    }
    if observer != nil {
        destroy(observer)
    }

}
