package main

import "core:c"
import "core:fmt"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

UI_FONT_PATH :: "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"

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

draw_text :: proc(app: ^App, font: ^TTF.Font, text: cstring, x, y: f32, color: SDL.Color) {
    label := TTF.CreateText(app.text_engine, font, text, 0)
    if label == nil {
        return
    }
    defer TTF.DestroyText(label)
    _ = TTF.SetTextColor(label, color[0], color[1], color[2], color[3])
    _ = TTF.DrawRendererText(label, x, y)
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
    case .KEY_DOWN:
        ctrl := .LCTRL in event.key.mod || .RCTRL in event.key.mod
        shift := .LSHIFT in event.key.mod || .RSHIFT in event.key.mod
        if ctrl && shift && event.key.key == SDL.K_P {
            app.palette_open = !app.palette_open
            app.settings_open = false
        } else if ctrl && event.key.key == SDL.K_COMMA {
            app.settings_open = !app.settings_open
            app.palette_open = false
        } else if ctrl && event.key.key == SDL.K_T {
            new_tab(app)
        } else if event.key.key == SDL.K_ESCAPE {
            if app.palette_open || app.settings_open {
                app.palette_open = false
                app.settings_open = false
            } else {
                app.running = false
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

draw_terminal :: proc(app: ^App, width, height: f32) {
    body := SDL.FRect{0, 46, width, height - 46}
    draw_fill(app.renderer, body, palette.terminal_bg)

    inset := SDL.FRect{18, 64, width - 36, height - 84}
    draw_fill(app.renderer, inset, palette.terminal_panel)

    draw_text(app, app.terminal_font, "Howl Desktop / Odin canary", 34, 86, palette.text_muted)
    draw_text(app, app.terminal_font, "Session protocol: not attached yet", 34, 116, palette.text_muted)
    draw_text(app, app.terminal_font, "", 34, 144, palette.text_muted)
    draw_text(app, app.terminal_font, "PS C:\\Users\\Captain> ", 34, 158, palette.text)

    cursor := SDL.FRect{236, 158, 9, 20}
    draw_fill(app.renderer, cursor, palette.text)

    hint := SDL.FRect{34, height - 62, 370, 30}
    draw_outline(app.renderer, hint, palette.border)
    draw_text(app, app.ui_font, "+ new tab    v palette    Settings", 46, height - 55, palette.text_muted)
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

    terminal_font := TTF.OpenFont(UI_FONT_PATH, 17)
    if terminal_font == nil {
        sdl_error("TTF_OpenFont terminal failed")
        return
    }
    defer TTF.CloseFont(terminal_font)

    app := App{
        window = window,
        renderer = renderer,
        text_engine = engine,
        ui_font = ui_font,
        terminal_font = terminal_font,
        running = true,
        tab_count = 2,
        active_tab = 0,
    }

    for app.running {
        event: SDL.Event
        for SDL.PollEvent(&event) {
            handle_event(&app, &event)
        }
        draw(&app)
    }
}
