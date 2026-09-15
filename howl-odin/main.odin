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
SESSION_POLL_MS :: u64(50)

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
    running: bool,
    tab_count: int,
    active_tab: int,
    palette_open: bool,
    settings_open: bool,
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
            0,
            0,
            raw_data(worker.scratch),
            c.size_t(len(worker.scratch)),
            &output_len,
        )
        if result != 0 {
            publish_bridge_error(app, observer)
            time.sleep(time.Duration(SESSION_POLL_MS) * time.Millisecond)
            continue
        }

        snapshot_revision := revision(observer)
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

        time.sleep(time.Duration(SESSION_POLL_MS) * time.Millisecond)
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
    if app.session == nil || app.active_tab != 0 || app.palette_open || app.settings_open {
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
    if app.tab_count >= 4 {
        return
    }
    app.tab_count += 1
    app.active_tab = app.tab_count - 1
}

handle_click :: proc(app: ^App, x, y, width, height: f32) {
    plus, menu, settings := tab_controls(app.tab_count, width)

    if inside(x, y, plus) {
        new_tab(app)
        return
    }
    if inside(x, y, menu) {
        app.palette_open = !app.palette_open
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
            app.settings_open = false
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_COMMA {
            app.settings_open = !app.settings_open
            app.palette_open = false
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_T {
            new_tab(app)
        } else if event.type == .KEY_DOWN && event.key.key == SDL.K_ESCAPE && (app.palette_open || app.settings_open) {
            app.palette_open = false
            app.settings_open = false
        } else if send_bridge_key(app, event) {
            // The active real Session consumed this named physical key.
        } else if event.type == .KEY_DOWN && app.session != nil && app.active_tab == 0 && !app.palette_open && !app.settings_open && (ctrl || alt) {
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
        if app.session != nil && app.active_tab == 0 && !app.palette_open && !app.settings_open && event.text.text != nil {
            text := string(event.text.text)
            if len(text) != 0 {
                result := send_text(app.session, raw_data(text), c.size_t(len(text)))
                if result != 0 {
                    copy_bridge_error(app)
                }
            }
        }
    case .MOUSE_BUTTON_DOWN:
        w, h: c.int
        if SDL.GetCurrentRenderOutputSize(app.renderer, &w, &h) {
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

        if i == 0 {
            draw_text(app, app.ui_font, "Home", tab_x + 14, 14, active ? palette.text : palette.text_muted)
            if session_attached(app) {
                draw_fill(app.renderer, {tab_x + tab_w - 16, 20, 5, 5}, palette.accent)
            }
        } else if i == 1 {
            draw_text(app, app.ui_font, "PowerShell", tab_x + 14, 14, active ? palette.text : palette.text_muted)
        } else if i == 2 {
            draw_text(app, app.ui_font, "Development", tab_x + 14, 14, active ? palette.text : palette.text_muted)
        } else {
            draw_text(app, app.ui_font, "Session", tab_x + 14, 14, active ? palette.text : palette.text_muted)
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

    if app.active_tab == 0 {
        draw_real_session(app, width, height)
    } else {
        draw_placeholder_session(app)
    }

}

draw_palette :: proc(app: ^App, width, height: f32) {
    box_w := f32(520)
    box_h := f32(286)
    box := SDL.FRect{(width - box_w) / 2, 92, box_w, box_h}
    draw_fill(app.renderer, box, palette.title_bg)
    draw_outline(app.renderer, box, palette.border)

    search := SDL.FRect{box.x + 18, box.y + 18, box.w - 36, 40}
    draw_fill(app.renderer, search, palette.terminal_bg)
    draw_outline(app.renderer, search, palette.accent)
    draw_text(app, app.ui_font, "> Command Palette", search.x + 12, search.y + 10, palette.text)

    draw_text(app, app.ui_font, "New tab", box.x + 28, box.y + 82, palette.text)
    draw_text(app, app.ui_font, "Split pane", box.x + 28, box.y + 116, palette.text)
    draw_text(app, app.ui_font, "Attach session", box.x + 28, box.y + 150, palette.text)
    draw_text(app, app.ui_font, "Open settings", box.x + 28, box.y + 184, palette.text)
    draw_text(app, app.ui_font, "Close pane", box.x + 28, box.y + 218, palette.text_muted)
}

draw_settings :: proc(app: ^App, width, height: f32) {
    panel := SDL.FRect{width - 620, 58, 602, height - 76}
    draw_fill(app.renderer, panel, palette.title_bg)
    draw_outline(app.renderer, panel, palette.border)

    sidebar := SDL.FRect{panel.x, panel.y, 178, panel.h}
    draw_fill(app.renderer, sidebar, palette.tab_idle)
    draw_text(app, app.ui_font, "Settings", sidebar.x + 18, sidebar.y + 18, palette.text)
    draw_text(app, app.ui_font, "Startup", sidebar.x + 18, sidebar.y + 64, palette.text_muted)
    draw_text(app, app.ui_font, "Interaction", sidebar.x + 18, sidebar.y + 98, palette.text_muted)
    draw_text(app, app.ui_font, "Appearance", sidebar.x + 18, sidebar.y + 132, palette.accent)
    draw_text(app, app.ui_font, "Color schemes", sidebar.x + 18, sidebar.y + 166, palette.text_muted)
    draw_text(app, app.ui_font, "Actions", sidebar.x + 18, sidebar.y + 200, palette.text_muted)
    draw_text(app, app.ui_font, "Profiles", sidebar.x + 18, sidebar.y + 250, palette.text)
    draw_text(app, app.ui_font, "  Defaults", sidebar.x + 18, sidebar.y + 284, palette.text_muted)
    draw_text(app, app.ui_font, "  Home", sidebar.x + 18, sidebar.y + 318, palette.text_muted)

    content_x := sidebar.x + sidebar.w + 28
    draw_text(app, app.ui_font, "Appearance", content_x, panel.y + 22, palette.text)
    draw_text(app, app.ui_font, "Theme", content_x, panel.y + 74, palette.text_muted)
    value := SDL.FRect{content_x, panel.y + 100, 248, 38}
    draw_fill(app.renderer, value, palette.terminal_bg)
    draw_outline(app.renderer, value, palette.border)
    draw_text(app, app.ui_font, "Dark", value.x + 12, value.y + 9, palette.text)

    draw_text(app, app.ui_font, "Tab width mode", content_x, panel.y + 162, palette.text_muted)
    value2 := SDL.FRect{content_x, panel.y + 188, 248, 38}
    draw_fill(app.renderer, value2, palette.terminal_bg)
    draw_outline(app.renderer, value2, palette.border)
    draw_text(app, app.ui_font, "Equal", value2.x + 12, value2.y + 9, palette.text)
}

draw :: proc(app: ^App) {
    w, h: c.int
    if !SDL.GetCurrentRenderOutputSize(app.renderer, &w, &h) {
        return
    }
    width := f32(w)
    height := f32(h)

    set_draw_color(app.renderer, palette.window_bg)
    _ = SDL.RenderClear(app.renderer)

    tab_bar := SDL.FRect{0, 0, width, 46}
    draw_fill(app.renderer, tab_bar, palette.title_bg)
    draw_tabs(app, width)
    draw_terminal(app, width, height)

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

    app := App{
        window = window,
        renderer = renderer,
        text_engine = engine,
        ui_font = ui_font,
        terminal_font = terminal_font,
        running = true,
        tab_count = 2,
        active_tab = 0,
        session = session,
        session_text = session_text,
    }

    if session == nil {
        publish_initial_error(&app, string(control_diagnostic[:int(control_diagnostic_len)]))
    } else if observer == nil {
        publish_initial_error(&app, string(observer_diagnostic[:int(observer_diagnostic_len)]))
    }

    worker_context := Session_Worker{
        app = &app,
        observer = observer,
        scratch = observer_scratch,
    }
    observer_thread: ^thread.Thread = nil
    if session != nil && observer != nil {
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
        thread.destroy(observer_thread)
    }
    if observer != nil {
        destroy(observer)
    }

}
