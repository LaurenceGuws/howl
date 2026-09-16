package main

import "core:c"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:time"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

UI_FONT_PATH :: "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
HOME_ENDPOINT :: "tcp://127.0.0.1:39601"
SESSION_TEXT_BYTES :: 512 * 1024
SELECTION_TEXT_BYTES :: 1024 * 1024
SEARCH_QUERY_BYTES :: 512
SESSION_RETRY_MS :: 50
SELECTION_EDGE_SCROLL_MS :: 100
MAX_TABS :: 8
MAX_CANVAS_RESOURCES :: 8
OWNED_SESSION_ROWS :: u16(37)
OWNED_SESSION_COLUMNS :: u16(80)
FONT_PRESET_MIN :: 0
FONT_PRESET_MAX :: 2
CONFIG_SCHEMA :: 1

User_Config :: struct {
    schema: int `json:"schema"`,
    terminal_font_pixels: int `json:"terminal_font_pixels"`,
    startup_profile: int `json:"startup_profile"`,
}

Tab_Kind :: enum {
    Session,
}

Search_State :: enum u8 {
    Idle,
    Found,
    Not_Found,
    Stale,
    Error,
}

Tab :: struct {
    kind: Tab_Kind,
    title: string,
    session: ^Session_View,
    secondary_session: ^Session_View,
    active_pane: int,
}

Canvas_Texture :: struct {
    source: u64,
    resource: u64,
    generation: u64,
    texture: ^SDL.Texture,
    format: u8,
    width: u16,
    height: u16,
}

History_Scrollbar_Geometry :: struct {
    track: SDL.FRect,
    thumb: SDL.FRect,
    hit: SDL.FRect,
    history_offset: u32,
    history_count: u32,
    visible_rows: u32,
}

Session_View :: struct {
    owned_process: rawptr,
    control: rawptr,
    observer: rawptr,
    cancellation: rawptr,
    observer_thread: ^thread.Thread,
    search: rawptr,
    search_cancellation: rawptr,
    search_thread: ^thread.Thread,
    search_cond: sync.Cond,
    search_pending: bool,
    search_generation: u64,
    search_query: [SEARCH_QUERY_BYTES]u8,
    search_query_len: int,
    search_reverse: bool,
    search_origin_present: bool,
    search_origin_row: i32,
    search_origin_column: u16,
    search_running: bool,
    search_running_generation: u64,
    search_state: Search_State,
    search_last_reverse: bool,
    search_last_complete: bool,
    search_result_active: bool,
    search_result: Search_Match_Info,
    search_error: [160]u8,
    search_error_len: int,
    endpoint: [160]u8,
    endpoint_len: int,
    text: []u8,
    scratch: []u8,
    text_len: int,
    revision: u64,
    terminal_revision: u64,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_visible: bool,
    cursor_shape: u8,
    history_count: u32,
    history_row_base: u32,
    history_target_offset: u32,
    history_anchor_top_row: u64,
    history_anchor_valid: bool,
    history_wheel_rows: f32,
    history_scrollbar_dragging: bool,
    history_scrollbar_grab_y: f32,
    alternate_screen: bool,
    selection_active: bool,
    selection_dragging: bool,
    selection_anchor_row: i32,
    selection_anchor_column: u16,
    selection_focus_row: i32,
    selection_focus_column: u16,
    selection_edge_scroll_rows: i8,
    selection_pointer_x: f32,
    selection_pointer_y: f32,
    selection_columns: u16,
    selection_alternate_screen: bool,
    text_truncated: bool,
    error: [160]u8,
    error_len: int,
    mutex: sync.Mutex,
    worker_stop: bool,
    canvas: rawptr,
    canvas_font_pixels: u16,
    canvas_session_revision: u64,
    canvas_history_offset: u32,
    canvas_frame_revision: u64,
    canvas_surface_width: u16,
    canvas_surface_height: u16,
    canvas_resources: [MAX_CANVAS_RESOURCES]Canvas_Texture,
    canvas_resource_count: int,
    canvas_commands: []Canvas_Command_Info,
    canvas_error: [160]u8,
    canvas_error_len: int,
    requested_rows: u16,
    requested_columns: u16,
}

App_Action :: enum {
    New_Tab,
    Split_Pane,
    Open_Local,
    Attach_Home,
    Open_Settings,
    Close_Pane,
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

session_update_event_type: u32

notify_session_update :: proc() {
    if session_update_event_type == 0 {
        return
    }
    event := SDL.Event{}
    event.type = SDL.EventType(session_update_event_type)
    _ = SDL.PushEvent(&event)
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
    search_open: bool,
    search_query: [SEARCH_QUERY_BYTES]u8,
    search_query_len: int,
    next_session_identity: u32,
    startup_profile: int,
}

config_paths :: proc() -> (directory, path, temporary: string, ok: bool) {
    root := os.get_env("XDG_CONFIG_HOME", context.temp_allocator)
    if len(root) == 0 {
        home := os.get_env("HOME", context.temp_allocator)
        if len(home) == 0 {
            return "", "", "", false
        }
        value, err := filepath.join([]string{home, ".config"}, allocator=context.temp_allocator)
        if err != nil {
            return "", "", "", false
        }
        root = value
    }
    directory_value, directory_err := filepath.join([]string{root, "howl"}, allocator=context.temp_allocator)
    if directory_err != nil {
        return "", "", "", false
    }
    directory = directory_value
    path_value, path_err := filepath.join([]string{directory, "odin.json"}, allocator=context.temp_allocator)
    if path_err != nil {
        return "", "", "", false
    }
    path = path_value
    temporary_value, temporary_err := filepath.join([]string{directory, "odin.json.tmp"}, allocator=context.temp_allocator)
    if temporary_err != nil {
        return "", "", "", false
    }
    temporary = temporary_value
    return directory, path, temporary, true
}

font_preset_from_pixels :: proc(pixels: int) -> int {
    switch pixels {
    case 12: return 0
    case 18: return 2
    case:    return 1
    }
}

load_user_config :: proc() -> User_Config {
    result := User_Config{schema = CONFIG_SCHEMA, terminal_font_pixels = 15, startup_profile = 0}
    _, path, _, ok := config_paths()
    if !ok {
        return result
    }
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil {
        return result
    }
    candidate := result
    if json.unmarshal(data, &candidate) != nil || candidate.schema != CONFIG_SCHEMA {
        return result
    }
    if candidate.terminal_font_pixels != 12 && candidate.terminal_font_pixels != 15 && candidate.terminal_font_pixels != 18 {
        return result
    }
    if candidate.startup_profile < 0 || candidate.startup_profile > 1 {
        return result
    }
    return candidate
}

save_user_config :: proc(app: ^App) {
    directory, path, temporary, ok := config_paths()
    if !ok {
        return
    }
    if err := os.make_directory_all(directory); err != nil && err != .Exist {
        return
    }
    value := User_Config{
        schema = CONFIG_SCHEMA,
        terminal_font_pixels = int(font_pixels_for_preset(app.terminal_font_preset)),
        startup_profile = app.startup_profile,
    }
    data, err := json.marshal(value, json.Marshal_Options{pretty = true, use_spaces = true, spaces = 2}, allocator=context.temp_allocator)
    if err != nil {
        return
    }
    if os.write_entire_file(temporary, data) != nil {
        return
    }
    if os.rename(temporary, path) != nil {
        _ = os.remove(temporary)
    }
}

startup_profile_label :: proc(value: int) -> string {
    return value == 1 ? "Local shell" : "Home Session"
}

startup_action_label :: proc(value: int) -> string {
    return value == 1 ? "Create owned Session" : "Attach existing Session"
}

adjust_startup_profile :: proc(app: ^App, delta: int) {
    next := clamp(app.startup_profile + delta, 0, 1)
    if next == app.startup_profile {
        return
    }
    app.startup_profile = next
    save_user_config(app)
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
        for index in 0..<app.tab_count {
            reset_canvas(app.tabs[index].session)
            reset_canvas(app.tabs[index].secondary_session)
        }
        save_user_config(app)
    }
}


font_pixels_for_preset :: proc(preset: int) -> u16 {
    switch preset {
    case 0: return 12
    case 1: return 15
    case:   return 18
    }
}

set_canvas_error :: proc(view: ^Session_View, message: string) {
    if view == nil {
        return
    }
    count := min(len(message), len(view.canvas_error))
    for byte, index in message[:count] {
        view.canvas_error[index] = u8(byte)
    }
    view.canvas_error_len = count
}

copy_canvas_bridge_error :: proc(view: ^Session_View) {
    if view == nil || view.canvas == nil {
        return
    }
    count: c.size_t
    render_copy_error(
        view.canvas,
        raw_data(view.canvas_error[:]),
        c.size_t(len(view.canvas_error)),
        &count,
    )
    view.canvas_error_len = int(count)
}

remove_canvas_resource_at :: proc(view: ^Session_View, index: int) {
    if index < 0 || index >= view.canvas_resource_count {
        return
    }
    texture := view.canvas_resources[index].texture
    if texture != nil {
        SDL.DestroyTexture(texture)
    }
    view.canvas_resource_count -= 1
    if index != view.canvas_resource_count {
        view.canvas_resources[index] = view.canvas_resources[view.canvas_resource_count]
    }
    view.canvas_resources[view.canvas_resource_count] = {}
}

clear_canvas_resources :: proc(view: ^Session_View) {
    for view.canvas_resource_count > 0 {
        remove_canvas_resource_at(view, view.canvas_resource_count - 1)
    }
}

reset_canvas :: proc(view: ^Session_View) {
    if view == nil {
        return
    }
    clear_selection(view)
    clear_canvas_resources(view)
    if view.canvas != nil {
        render_destroy(view.canvas)
        view.canvas = nil
    }
    if view.canvas_commands != nil {
        delete(view.canvas_commands)
        view.canvas_commands = nil
    }
    view.canvas_font_pixels = 0
    view.canvas_session_revision = 0
    view.canvas_history_offset = 0
    view.canvas_frame_revision = 0
    view.canvas_surface_width = 0
    view.canvas_surface_height = 0
    view.canvas_error_len = 0
    view.requested_rows = 0
    view.requested_columns = 0
}

resize_owned_session_to_pane :: proc(
    app: ^App,
    view: ^Session_View,
    available_width, available_height: f32,
) {
    if view == nil || view.owned_process == nil || view.control == nil {
        return
    }
    if !ensure_canvas(app, view) {
        return
    }
    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 {
        return
    }
    width_cells := max(1, int(available_width))
    height_cells := max(1, int(available_height))
    desired_columns := u16(clamp(
        width_cells / int(cell_width),
        1,
        int(render_maximum_columns()),
    ))
    desired_rows := u16(clamp(
        height_cells / int(cell_height),
        1,
        int(render_maximum_rows()),
    ))
    if view.requested_rows == desired_rows && view.requested_columns == desired_columns {
        return
    }
    sync.mutex_lock(&view.mutex)
    current_columns := view.columns
    sync.mutex_unlock(&view.mutex)
    if history_columns_changed(current_columns, desired_columns) {
        _ = return_history_live(view)
    }
    if send_resize(view.control, desired_rows, desired_columns) != 0 {
        copy_bridge_error(view)
        return
    }
    view.requested_rows = desired_rows
    view.requested_columns = desired_columns
}

find_canvas_resource :: proc(view: ^Session_View, source, resource, generation: u64) -> ^Canvas_Texture {
    for index in 0..<view.canvas_resource_count {
        value := &view.canvas_resources[index]
        if value.source == source && value.resource == resource && value.generation == generation {
            return value
        }
    }
    return nil
}

remove_canvas_resource_key :: proc(view: ^Session_View, source, resource, generation: u64, exact_generation: bool) {
    index := 0
    for index < view.canvas_resource_count {
        value := view.canvas_resources[index]
        if value.source == source && value.resource == resource && (!exact_generation || value.generation == generation) {
            remove_canvas_resource_at(view, index)
            if !exact_generation {
                continue
            }
            return
        }
        index += 1
    }
}

create_canvas_texture :: proc(app: ^App, view: ^Session_View, index: u32) -> bool {
    info: Canvas_Resource_Info
    if render_upload_info(view.canvas, index, &info) != 0 || info.width == 0 || info.height == 0 {
        set_canvas_error(view, "invalid Canvas upload metadata")
        return false
    }
    if info.pixel_count == 0 || info.pixel_count > 16 * 1024 * 1024 {
        set_canvas_error(view, "invalid Canvas upload bytes")
        return false
    }
    source_bytes := make([]u8, int(info.pixel_count))
    defer delete(source_bytes)
    copied: c.size_t
    if render_upload_copy(
        view.canvas,
        index,
        raw_data(source_bytes),
        c.size_t(len(source_bytes)),
        &copied,
    ) != 0 || int(copied) != len(source_bytes) {
        set_canvas_error(view, "Canvas upload copy failed")
        return false
    }

    rgba: []u8
    converted: []u8
    defer {
        if converted != nil {
            delete(converted)
        }
    }
    pitch: c.int
    if info.format == 0 {
        converted = make([]u8, int(info.width) * int(info.height) * 4)
        rgba = converted
        if info.stride < u64(info.width) {
            set_canvas_error(view, "invalid alpha atlas stride")
            return false
        }
        for y in 0..<int(info.height) {
            for x in 0..<int(info.width) {
                src := y * int(info.stride) + x
                dst := (y * int(info.width) + x) * 4
                rgba[dst + 0] = 255
                rgba[dst + 1] = 255
                rgba[dst + 2] = 255
                rgba[dst + 3] = source_bytes[src]
            }
        }
        pitch = c.int(int(info.width) * 4)
    } else if info.format == 1 {
        rgba = source_bytes
        pitch = c.int(info.stride)
    } else {
        set_canvas_error(view, "unsupported Canvas resource format")
        return false
    }

    texture := SDL.CreateTexture(
        app.renderer,
        .RGBA32,
        .STATIC,
        c.int(info.width),
        c.int(info.height),
    )
    if texture == nil {
        set_canvas_error(view, string(SDL.GetError()))
        return false
    }
    if !SDL.SetTextureScaleMode(texture, .NEAREST) ||
       !SDL.SetTextureBlendMode(texture, SDL.BLENDMODE_BLEND) ||
       !SDL.UpdateTexture(texture, nil, raw_data(rgba), pitch) {
        set_canvas_error(view, string(SDL.GetError()))
        SDL.DestroyTexture(texture)
        return false
    }

    remove_canvas_resource_key(view, info.source, info.resource, 0, false)
    if view.canvas_resource_count >= MAX_CANVAS_RESOURCES {
        set_canvas_error(view, "Canvas resource cache full")
        SDL.DestroyTexture(texture)
        return false
    }
    view.canvas_resources[view.canvas_resource_count] = Canvas_Texture{
        source = info.source,
        resource = info.resource,
        generation = info.generation,
        texture = texture,
        format = info.format,
        width = info.width,
        height = info.height,
    }
    view.canvas_resource_count += 1
    return true
}

ensure_canvas :: proc(app: ^App, view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    pixels := font_pixels_for_preset(app.terminal_font_preset)
    if view.canvas != nil && view.canvas_font_pixels == pixels {
        return true
    }
    reset_canvas(view)
    endpoint := session_endpoint(view)
    if len(endpoint) == 0 {
        set_canvas_error(view, "missing Session endpoint")
        return false
    }
    font: string = UI_FONT_PATH
    diagnostic: [160]u8
    diagnostic_len: c.size_t
    view.canvas = render_create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(font),
        c.size_t(len(font)),
        pixels,
        raw_data(diagnostic[:]),
        c.size_t(len(diagnostic)),
        &diagnostic_len,
    )
    if view.canvas == nil {
        set_canvas_error(view, string(diagnostic[:int(diagnostic_len)]))
        return false
    }
    view.canvas_font_pixels = pixels
    return true
}

update_canvas :: proc(app: ^App, view: ^Session_View) -> bool {
    if !ensure_canvas(app, view) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    target_revision := view.revision
    requested_history_offset := view.history_target_offset
    sync.mutex_unlock(&view.mutex)
    if target_revision == 0 {
        return false
    }
    if view.canvas_session_revision >= target_revision &&
       view.canvas_history_offset == requested_history_offset &&
       len(view.canvas_commands) != 0 {
        return true
    }
    if render_observe(view.canvas, requested_history_offset) != 0 {
        copy_canvas_bridge_error(view)
        return false
    }

    for index in 0..<int(render_removal_count(view.canvas)) {
        info: Canvas_Removal_Info
        if render_removal_info(view.canvas, u32(index), &info) != 0 {
            set_canvas_error(view, "Canvas removal decode failed")
            reset_canvas(view)
            return false
        }
        remove_canvas_resource_key(view, info.source, info.resource, info.generation, true)
    }
    for index in 0..<int(render_upload_count(view.canvas)) {
        if !create_canvas_texture(app, view, u32(index)) {
            reset_canvas(view)
            return false
        }
    }

    count := int(render_command_count(view.canvas))
    commands := make([]Canvas_Command_Info, count)
    for index in 0..<count {
        if render_command_info(view.canvas, u32(index), &commands[index]) != 0 {
            delete(commands)
            set_canvas_error(view, "Canvas command decode failed")
            reset_canvas(view)
            return false
        }
    }
    if view.canvas_commands != nil {
        delete(view.canvas_commands)
    }
    view.canvas_commands = commands
    view.canvas_surface_width = render_surface_width(view.canvas)
    view.canvas_surface_height = render_surface_height(view.canvas)
    view.canvas_frame_revision = render_frame_revision(view.canvas)
    view.canvas_session_revision = render_session_revision(view.canvas)
    view.canvas_history_offset = render_history_offset(view.canvas)
    accept_history_snapshot(
        view,
        view.canvas_history_offset,
        render_history_count(view.canvas),
        render_history_row_base(view.canvas),
        render_alternate_screen(view.canvas) != 0,
    )
    view.canvas_error_len = 0
    return true
}

rgba_channel :: proc(bits: u32, shift: u32) -> u8 {
    return u8((bits >> shift) & 0xff)
}

draw_canvas_session :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect, origin_x, origin_y: f32) -> bool {
    if !update_canvas(app, view) {
        return false
    }
    pane_clip := SDL.Rect{c.int(pane.x), c.int(pane.y), c.int(pane.w), c.int(pane.h)}
    for command in view.canvas_commands {
        destination := SDL.FRect{
            origin_x + f32(command.destination_x),
            origin_y + f32(command.destination_y),
            f32(command.destination_width),
            f32(command.destination_height),
        }
        if command.tag == 0 {
            _ = SDL.SetRenderClipRect(app.renderer, &pane_clip)
            set_draw_color(app.renderer, SDL.Color{
                rgba_channel(command.color_rgba, 0),
                rgba_channel(command.color_rgba, 8),
                rgba_channel(command.color_rgba, 16),
                rgba_channel(command.color_rgba, 24),
            })
            draw_rect := destination
            _ = SDL.RenderFillRect(app.renderer, &draw_rect)
            continue
        }
        resource := find_canvas_resource(view, command.resource_source, command.resource, command.generation)
        if resource == nil || resource.texture == nil {
            set_canvas_error(view, "Canvas command references missing texture")
            return false
        }
        command_clip := SDL.Rect{
            c.int(origin_x) + c.int(command.clip_x),
            c.int(origin_y) + c.int(command.clip_y),
            c.int(command.clip_width),
            c.int(command.clip_height),
        }
        clip: SDL.Rect
        if !SDL.GetRectIntersection(command_clip, pane_clip, &clip) {
            continue
        }
        _ = SDL.SetRenderClipRect(app.renderer, &clip)
        source := SDL.FRect{
            f32(command.source_x),
            f32(command.source_y),
            f32(command.source_width),
            f32(command.source_height),
        }
        if command.tag == 1 {
            _ = SDL.SetTextureColorMod(
                resource.texture,
                rgba_channel(command.color_rgba, 0),
                rgba_channel(command.color_rgba, 8),
                rgba_channel(command.color_rgba, 16),
            )
            _ = SDL.SetTextureAlphaMod(resource.texture, rgba_channel(command.color_rgba, 24))
        } else {
            _ = SDL.SetTextureColorMod(resource.texture, 255, 255, 255)
            _ = SDL.SetTextureAlphaMod(resource.texture, 255)
        }
        _ = SDL.RenderTexture(app.renderer, resource.texture, &source, &destination)
    }
    _ = SDL.SetRenderClipRect(app.renderer, nil)
    return true
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

publish_bridge_error :: proc(view: ^Session_View, handle: rawptr) {
    if view == nil || handle == nil {
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
    sync.mutex_lock(&view.mutex)
    copy(view.error[:], message[:int(error_len)])
    view.error_len = int(error_len)
    sync.mutex_unlock(&view.mutex)
}

observe_session :: proc(data: rawptr) {
    view := (^Session_View)(data)
    observer := view.observer
    after_revision: u64
    for {
        sync.mutex_lock(&view.mutex)
        stop := view.worker_stop
        sync.mutex_unlock(&view.mutex)
        if stop {
            break
        }

        output_len: c.size_t
        result := snapshot(
            observer,
            after_revision,
            0,
            raw_data(view.scratch),
            c.size_t(len(view.scratch)),
            &output_len,
        )
        if result != 0 {
            sync.mutex_lock(&view.mutex)
            stopped := view.worker_stop
            sync.mutex_unlock(&view.mutex)
            if stopped {
                break
            }
            publish_bridge_error(view, observer)
            notify_session_update()
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
        snapshot_history_row_base := history_row_base(observer)
        snapshot_alternate_screen := alternate_screen(observer) != 0
        snapshot_text_truncated := text_truncated(observer) != 0

        sync.mutex_lock(&view.mutex)
        validate_selection_context_locked(
            view,
            snapshot_columns,
            snapshot_rows,
            snapshot_history_count,
            snapshot_history_row_base,
            snapshot_alternate_screen,
        )
        apply_history_geometry_locked(view, snapshot_columns)
        copy(view.text[:int(output_len)], view.scratch[:int(output_len)])
        view.text_len = int(output_len)
        view.revision = snapshot_revision
        view.terminal_revision = snapshot_terminal_revision
        view.rows = snapshot_rows
        view.columns = snapshot_columns
        view.cursor_row = snapshot_cursor_row
        view.cursor_column = snapshot_cursor_column
        view.cursor_visible = snapshot_cursor_visible
        view.cursor_shape = snapshot_cursor_shape
        follow_history_locked(
            view,
            snapshot_history_count,
            snapshot_history_row_base,
            snapshot_alternate_screen,
        )
        view.history_count = snapshot_history_count
        view.history_row_base = snapshot_history_row_base
        view.alternate_screen = snapshot_alternate_screen
        view.text_truncated = snapshot_text_truncated
        view.error_len = 0
        validate_search_result_locked(view)
        sync.mutex_unlock(&view.mutex)
        notify_session_update()
    }
}

search_result_retained_locked :: proc(view: ^Session_View, result: Search_Match_Info) -> bool {
    if result.found == 0 || result.columns != view.columns ||
       (result.alternate_screen != 0) != view.alternate_screen {
        return false
    }
    row := i64(result.row)
    if view.alternate_screen {
        return row >= 0 && row < i64(view.rows)
    }
    first := i64(view.history_row_base)
    last := first + i64(view.history_count) + i64(view.rows) - 1
    return row >= first && row <= last
}

validate_search_result_locked :: proc(view: ^Session_View) {
    if view.search_result_active && !search_result_retained_locked(view, view.search_result) {
        view.search_result_active = false
        view.search_state = .Stale
    }
}

apply_search_result_locked :: proc(view: ^Session_View, result: Search_Match_Info) -> bool {
    if !search_result_retained_locked(view, result) {
        return false
    }
    clear_selection_locked(view)
    view.history_wheel_rows = 0
    if view.alternate_screen {
        reset_history_locked(view)
    } else {
        first := i64(view.history_row_base)
        live_top := first + i64(view.history_count)
        row := i64(result.row)
        half_rows := i64(view.rows) / 2
        target_top := clamp(row - half_rows, first, live_top)
        offset := live_top - target_top
        view.history_target_offset = u32(offset)
        if offset == 0 {
            view.history_anchor_top_row = 0
            view.history_anchor_valid = false
        } else {
            view.history_anchor_top_row = u64(target_top)
            view.history_anchor_valid = true
        }
    }
    view.search_result = result
    view.search_result_active = true
    return true
}

copy_search_error :: proc(view: ^Session_View, handle: rawptr, destination: ^[160]u8, destination_len: ^int) {
    count: c.size_t
    copy_error(handle, raw_data(destination[:]), c.size_t(len(destination)), &count)
    destination_len^ = int(count)
}

search_session :: proc(data: rawptr) {
    view := (^Session_View)(data)
    local_query: [SEARCH_QUERY_BYTES]u8
    for {
        sync.mutex_lock(&view.mutex)
        for !view.worker_stop && !view.search_pending {
            sync.cond_wait(&view.search_cond, &view.mutex)
        }
        if view.worker_stop {
            sync.mutex_unlock(&view.mutex)
            break
        }
        generation := view.search_generation
        query_len := view.search_query_len
        copy(local_query[:query_len], view.search_query[:query_len])
        reverse := view.search_reverse
        origin_present := view.search_origin_present
        origin_row := view.search_origin_row
        origin_column := view.search_origin_column
        view.search_pending = false
        view.search_running = true
        view.search_running_generation = generation
        sync.mutex_unlock(&view.mutex)

        result: Search_Match_Info
        rc := search_find(
            view.search,
            raw_data(local_query[:]),
            c.size_t(query_len),
            reverse ? u8(1) : u8(0),
            origin_present ? u8(1) : u8(0),
            origin_row,
            origin_column,
            &result,
        )
        error_message: [160]u8
        error_len := 0
        if rc != 0 {
            copy_search_error(view, view.search, &error_message, &error_len)
        }

        sync.mutex_lock(&view.mutex)
        view.search_running = false
        if !view.worker_stop && generation == view.search_generation {
            view.search_last_reverse = reverse
            view.search_last_complete = rc == 0 && result.complete != 0
            view.search_error_len = 0
            if rc != 0 {
                count := min(error_len, len(view.search_error))
                copy(view.search_error[:count], error_message[:count])
                view.search_error_len = count
                view.search_state = .Error
            } else if result.found == 0 {
                view.search_state = .Not_Found
            } else if apply_search_result_locked(view, result) {
                view.search_state = .Found
            } else {
                message := "search_result_stale"
                copy(view.search_error[:], transmute([]u8)message)
                view.search_error_len = len(message)
                view.search_state = .Error
                view.search_result_active = false
            }
        }
        sync.mutex_unlock(&view.mutex)
        notify_session_update()
    }
}

clear_search_result :: proc(view: ^Session_View) {
    if view == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    view.search_generation += 1
    view.search_pending = false
    view.search_result_active = false
    view.search_state = .Idle
    view.search_last_complete = true
    view.search_error_len = 0
    sync.mutex_unlock(&view.mutex)
}

ensure_search_worker :: proc(view: ^Session_View) -> bool {
    if view == nil || view.control == nil {
        return false
    }
    if view.search != nil && view.search_thread != nil {
        return true
    }

    endpoint := session_endpoint(view)
    if len(endpoint) == 0 {
        return false
    }
    diagnostic: [160]u8
    diagnostic_len: c.size_t
    handle := create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(diagnostic[:]),
        c.size_t(len(diagnostic)),
        &diagnostic_len,
    )
    if handle == nil {
        sync.mutex_lock(&view.mutex)
        count := min(int(diagnostic_len), len(view.search_error))
        copy(view.search_error[:count], diagnostic[:count])
        view.search_error_len = count
        view.search_state = .Error
        sync.mutex_unlock(&view.mutex)
        return false
    }

    cancellation := cancellation_create(handle)
    if cancellation == nil {
        destroy(handle)
        sync.mutex_lock(&view.mutex)
        message := "search_cancellation_failed"
        copy(view.search_error[:len(message)], transmute([]u8)message)
        view.search_error_len = len(message)
        view.search_state = .Error
        sync.mutex_unlock(&view.mutex)
        return false
    }

    view.search = handle
    view.search_cancellation = cancellation
    view.search_thread = thread.create_and_start_with_data(
        rawptr(view),
        search_session,
        name = "howl-odin-search",
    )
    if view.search_thread == nil {
        cancellation_destroy(cancellation)
        destroy(handle)
        view.search = nil
        view.search_cancellation = nil
        sync.mutex_lock(&view.mutex)
        message := "search_thread_failed"
        copy(view.search_error[:len(message)], transmute([]u8)message)
        view.search_error_len = len(message)
        view.search_state = .Error
        sync.mutex_unlock(&view.mutex)
        return false
    }
    return true
}

queue_search :: proc(view: ^Session_View, query: []u8, reverse: bool) -> bool {
    if view == nil || len(query) == 0 || len(query) > SEARCH_QUERY_BYTES ||
       !ensure_search_worker(view) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    view.search_generation += 1
    view.search_query_len = len(query)
    copy(view.search_query[:len(query)], query)
    view.search_reverse = reverse
    view.search_origin_present = view.search_result_active
    if view.search_result_active {
        view.search_origin_row = view.search_result.row
        view.search_origin_column = reverse ? view.search_result.start_column : view.search_result.end_column
    } else {
        view.search_origin_row = 0
        view.search_origin_column = 0
    }
    view.search_pending = true
    view.search_state = .Idle
    view.search_error_len = 0
    sync.mutex_unlock(&view.mutex)
    sync.cond_signal(&view.search_cond)
    return true
}

publish_initial_error :: proc(view: ^Session_View, message: string) {
    if view == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    count := min(len(message), len(view.error))
    for byte, index in message[:count] {
        view.error[index] = u8(byte)
    }
    view.error_len = count
    sync.mutex_unlock(&view.mutex)
}

session_attached :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    attached := view.control != nil && view.revision != 0 && view.error_len == 0
    sync.mutex_unlock(&view.mutex)
    return attached
}

copy_bridge_error :: proc(view: ^Session_View) {
    if view != nil {
        publish_bridge_error(view, view.control)
    }
}

clear_selection_locked :: proc(view: ^Session_View) {
    view.selection_active = false
    view.selection_dragging = false
    view.selection_anchor_row = 0
    view.selection_anchor_column = 0
    view.selection_focus_row = 0
    view.selection_focus_column = 0
    view.selection_edge_scroll_rows = 0
    view.selection_pointer_x = 0
    view.selection_pointer_y = 0
    view.selection_columns = 0
    view.selection_alternate_screen = false
}

clear_selection :: proc(view: ^Session_View) {
    if view == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    clear_selection_locked(view)
    sync.mutex_unlock(&view.mutex)
}

selection_point_retained :: proc(
    row: i32,
    column, columns, rows: u16,
    history_count, history_row_base: u32,
    alternate_screen: bool,
) -> bool {
    if columns == 0 || rows == 0 || column >= columns {
        return false
    }
    if alternate_screen {
        return row >= 0 && row < i32(rows)
    }
    first := i64(history_row_base)
    last := first + i64(history_count) + i64(rows) - 1
    value := i64(row)
    return value >= first && value <= last
}

validate_selection_context_locked :: proc(
    view: ^Session_View,
    columns, rows: u16,
    history_count, history_row_base: u32,
    alternate_screen: bool,
) {
    if !view.selection_active {
        return
    }
    if view.selection_columns != columns ||
       view.selection_alternate_screen != alternate_screen ||
       !selection_point_retained(
           view.selection_anchor_row,
           view.selection_anchor_column,
           columns,
           rows,
           history_count,
           history_row_base,
           alternate_screen,
       ) ||
       !selection_point_retained(
           view.selection_focus_row,
           view.selection_focus_column,
           columns,
           rows,
           history_count,
           history_row_base,
           alternate_screen,
       ) {
        clear_selection_locked(view)
    }
}

reset_history_locked :: proc(view: ^Session_View) {
    view.history_target_offset = 0
    view.history_anchor_top_row = 0
    view.history_anchor_valid = false
    view.history_wheel_rows = 0
}

follow_history_locked :: proc(
    view: ^Session_View,
    history_count: u32,
    history_row_base: u32,
    alternate_screen: bool,
) {
    if view.history_target_offset == 0 {
        return
    }
    if alternate_screen || history_count == 0 || !view.history_anchor_valid {
        reset_history_locked(view)
        return
    }
    newest_history_end := u64(history_row_base) + u64(history_count)
    if newest_history_end <= view.history_anchor_top_row {
        reset_history_locked(view)
        return
    }
    requested := newest_history_end - view.history_anchor_top_row
    clamped := min(requested, u64(history_count))
    if clamped == 0 {
        reset_history_locked(view)
        return
    }
    view.history_target_offset = u32(clamped)
    if clamped != requested {
        view.history_anchor_top_row = newest_history_end - clamped
    }
}

apply_history_geometry_locked :: proc(view: ^Session_View, columns: u16) {
    if history_columns_changed(view.columns, columns) {
        reset_history_locked(view)
    }
}

history_columns_changed :: proc(current_columns, next_columns: u16) -> bool {
    return current_columns != 0 && next_columns != current_columns
}

accept_history_snapshot :: proc(
    view: ^Session_View,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    alternate_screen: bool,
) {
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    if alternate_screen || history_offset == 0 || history_count == 0 {
        reset_history_locked(view)
        return
    }
    accepted := min(history_offset, history_count)
    if accepted == 0 {
        reset_history_locked(view)
        return
    }
    view.history_target_offset = accepted
    view.history_anchor_top_row = u64(history_row_base) + u64(history_count) - u64(accepted)
    view.history_anchor_valid = true
}

scroll_history_rows :: proc(view: ^Session_View, rows_delta: int) -> bool {
    if view == nil || rows_delta == 0 {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    if view.alternate_screen || view.history_count == 0 {
        return false
    }
    view.history_wheel_rows = 0
    requested := int(view.history_target_offset) + rows_delta
    clamped := clamp(requested, 0, int(view.history_count))
    if clamped == int(view.history_target_offset) {
        return false
    }
    view.history_target_offset = u32(clamped)
    if clamped == 0 {
        view.history_anchor_top_row = 0
        view.history_anchor_valid = false
    } else {
        view.history_anchor_top_row =
            u64(view.history_row_base) + u64(view.history_count) - u64(clamped)
        view.history_anchor_valid = true
    }
    return true
}

set_history_offset :: proc(view: ^Session_View, requested_offset: u32) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    if view.alternate_screen || view.history_count == 0 {
        return false
    }
    view.history_wheel_rows = 0
    clamped := min(requested_offset, view.history_count)
    if clamped == view.history_target_offset {
        return false
    }
    view.history_target_offset = clamped
    if clamped == 0 {
        view.history_anchor_top_row = 0
        view.history_anchor_valid = false
    } else {
        view.history_anchor_top_row =
            u64(view.history_row_base) + u64(view.history_count) - u64(clamped)
        view.history_anchor_valid = true
    }
    return true
}

scroll_history_wheel :: proc(view: ^Session_View, wheel_rows: f32) -> bool {
    if view == nil || wheel_rows == 0 {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    if view.alternate_screen || view.history_count == 0 {
        view.history_wheel_rows = 0
        return false
    }

    view.history_wheel_rows += wheel_rows * 3
    rows_delta := int(view.history_wheel_rows)
    if rows_delta == 0 {
        return false
    }
    view.history_wheel_rows -= f32(rows_delta)

    requested := int(view.history_target_offset) + rows_delta
    clamped := clamp(requested, 0, int(view.history_count))
    if clamped != requested {
        view.history_wheel_rows = 0
    }
    if clamped == int(view.history_target_offset) {
        view.history_wheel_rows = 0
        return false
    }

    view.history_target_offset = u32(clamped)
    if clamped == 0 {
        view.history_anchor_top_row = 0
        view.history_anchor_valid = false
    } else {
        view.history_anchor_top_row =
            u64(view.history_row_base) + u64(view.history_count) - u64(clamped)
        view.history_anchor_valid = true
    }
    return true
}

scroll_history_oldest :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    count := view.history_count
    sync.mutex_unlock(&view.mutex)
    if count == 0 {
        return false
    }
    return scroll_history_rows(view, int(count))
}

return_history_live_with_selection_policy :: proc(view: ^Session_View, clear_selection_state: bool) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    changed := view.history_target_offset != 0 || view.history_anchor_valid
    if clear_selection_state {
        clear_selection_locked(view)
    }
    reset_history_locked(view)
    return changed
}

return_history_live :: proc(view: ^Session_View) -> bool {
    return return_history_live_with_selection_policy(view, true)
}

return_history_live_navigation :: proc(view: ^Session_View) -> bool {
    return return_history_live_with_selection_policy(view, false)
}

history_active :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    return view.history_target_offset != 0
}

history_scrollbar_thumb :: proc(
    history_offset, history_count_value, visible_rows: u32,
    track_height: f32,
) -> (top, height: f32, ok: bool) {
    if history_count_value == 0 || visible_rows == 0 || track_height <= 0 {
        return 0, 0, false
    }
    total_rows := f32(history_count_value + visible_rows)
    height = max(f32(22), track_height * f32(visible_rows) / total_rows)
    height = min(height, track_height)
    travel := max(f32(0), track_height - height)
    if travel == 0 {
        return 0, height, true
    }
    accepted_offset := min(history_offset, history_count_value)
    live_progress := f32(history_count_value - accepted_offset) /
                     f32(history_count_value)
    top = travel * live_progress
    return top, height, true
}

history_offset_for_scrollbar_thumb :: proc(
    thumb_top, track_height, thumb_height: f32,
    history_count_value: u32,
) -> u32 {
    if history_count_value == 0 || track_height <= 0 {
        return 0
    }
    travel := max(f32(0), track_height - thumb_height)
    if travel == 0 {
        return 0
    }
    progress := clamp(thumb_top / travel, f32(0), f32(1))
    requested := int(f32(history_count_value) * (1 - progress) + 0.5)
    return u32(clamp(requested, 0, int(history_count_value)))
}

allocate_session_view :: proc(owned_process: rawptr) -> ^Session_View {
    view := new(Session_View)
    if view == nil {
        return nil
    }
    view.owned_process = owned_process
    view.text = make([]u8, SESSION_TEXT_BYTES)
    view.scratch = make([]u8, SESSION_TEXT_BYTES)
    if view.text == nil || view.scratch == nil {
        if view.text != nil do delete(view.text)
        if view.scratch != nil do delete(view.scratch)
        free(view)
        return nil
    }
    return view
}

create_session_view :: proc(endpoint: string, owned_process: rawptr) -> ^Session_View {
    view := allocate_session_view(owned_process)
    if view == nil {
        return nil
    }
    endpoint_count := min(len(endpoint), len(view.endpoint))
    for byte, index in endpoint[:endpoint_count] {
        view.endpoint[index] = u8(byte)
    }
    view.endpoint_len = endpoint_count

    control_diagnostic: [160]u8
    control_diagnostic_len: c.size_t
    view.control = create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(control_diagnostic[:]),
        c.size_t(len(control_diagnostic)),
        &control_diagnostic_len,
    )
    if view.control == nil {
        publish_initial_error(view, string(control_diagnostic[:int(control_diagnostic_len)]))
        return view
    }

    observer_diagnostic: [160]u8
    observer_diagnostic_len: c.size_t
    view.observer = create(
        raw_data(endpoint),
        c.size_t(len(endpoint)),
        raw_data(observer_diagnostic[:]),
        c.size_t(len(observer_diagnostic)),
        &observer_diagnostic_len,
    )
    if view.observer == nil {
        publish_initial_error(view, string(observer_diagnostic[:int(observer_diagnostic_len)]))
        return view
    }
    view.cancellation = cancellation_create(view.observer)
    if view.cancellation == nil {
        publish_initial_error(view, "observer_cancellation_failed")
        return view
    }
    view.observer_thread = thread.create_and_start_with_data(
        rawptr(view),
        observe_session,
        name = "howl-odin-observe",
    )
    if view.observer_thread == nil {
        publish_initial_error(view, "observer_thread_failed")
    }

    return view
}

create_error_session_view :: proc(message: string) -> ^Session_View {
    view := allocate_session_view(rawptr(nil))
    if view != nil {
        publish_initial_error(view, message)
    }
    return view
}

destroy_session_view :: proc(view: ^Session_View) {
    if view == nil {
        return
    }
    _ = finish_history_scrollbar_drag(view)
    reset_canvas(view)
    sync.mutex_lock(&view.mutex)
    view.worker_stop = true
    sync.mutex_unlock(&view.mutex)
    sync.cond_signal(&view.search_cond)
    if view.cancellation != nil {
        _ = cancellation_cancel(view.cancellation)
    }
    if view.search_cancellation != nil {
        _ = cancellation_cancel(view.search_cancellation)
    }
    if view.observer_thread != nil {
        thread.destroy(view.observer_thread)
        view.observer_thread = nil
    }
    if view.search_thread != nil {
        thread.destroy(view.search_thread)
        view.search_thread = nil
    }
    if view.cancellation != nil {
        cancellation_destroy(view.cancellation)
    }
    if view.search_cancellation != nil {
        cancellation_destroy(view.search_cancellation)
    }
    if view.observer != nil {
        destroy(view.observer)
    }
    if view.search != nil {
        destroy(view.search)
    }
    if view.control != nil {
        destroy(view.control)
    }
    if view.owned_process != nil {
        owned_session_destroy(view.owned_process)
    }
    delete(view.scratch)
    delete(view.text)
    free(view)
}

active_session_view :: proc(app: ^App) -> ^Session_View {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return nil
    }
    tab := &app.tabs[app.active_tab]
    if tab.active_pane == 1 && tab.secondary_session != nil {
        return tab.secondary_session
    }
    return tab.session
}

clear_all_search_results :: proc(app: ^App) {
    for index in 0..<app.tab_count {
        clear_search_result(app.tabs[index].session)
        clear_search_result(app.tabs[index].secondary_session)
    }
}

open_search :: proc(app: ^App) {
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
    app.search_open = true
    app.search_query_len = 0
    clear_all_search_results(app)
    clear_selection(active_session_view(app))
}

close_search :: proc(app: ^App) {
    if !app.search_open {
        return
    }
    app.search_open = false
    app.search_query_len = 0
    clear_all_search_results(app)
}

append_search_query :: proc(app: ^App, text: string) -> bool {
    if len(text) == 0 || app.search_query_len + len(text) > len(app.search_query) {
        return false
    }
    copy(
        app.search_query[app.search_query_len:app.search_query_len + len(text)],
        transmute([]u8)text,
    )
    app.search_query_len += len(text)
    clear_search_result(active_session_view(app))
    return true
}

backspace_search_query :: proc(app: ^App) -> bool {
    if app.search_query_len == 0 {
        return false
    }
    next := app.search_query_len - 1
    for next > 0 && app.search_query[next] & 0xc0 == 0x80 {
        next -= 1
    }
    app.search_query_len = next
    clear_search_result(active_session_view(app))
    return true
}

request_search :: proc(app: ^App, reverse: bool) -> bool {
    if !app.search_open || app.search_query_len == 0 {
        return false
    }
    view := active_session_view(app)
    if view == nil {
        return false
    }
    return queue_search(view, app.search_query[:app.search_query_len], reverse)
}

session_endpoint :: proc(view: ^Session_View) -> string {
    if view == nil || view.endpoint_len <= 0 {
        return ""
    }
    return string(view.endpoint[:view.endpoint_len])
}

create_owned_session_view :: proc(app: ^App) -> ^Session_View {
    runtime_dir := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
    if len(runtime_dir) == 0 {
        return create_error_session_view("Missing XDG_RUNTIME_DIR")
    }
    shell := os.get_env("SHELL", context.temp_allocator)
    if len(shell) == 0 {
        shell = "/bin/sh"
    }
    identity := app.next_session_identity
    app.next_session_identity += 1
    diagnostic: [160]u8
    diagnostic_len: c.size_t
    owned := owned_session_create(
        raw_data(runtime_dir),
        c.size_t(len(runtime_dir)),
        raw_data(shell),
        c.size_t(len(shell)),
        OWNED_SESSION_ROWS,
        OWNED_SESSION_COLUMNS,
        identity,
        raw_data(diagnostic[:]),
        c.size_t(len(diagnostic)),
        &diagnostic_len,
    )
    if owned == nil {
        return create_error_session_view(string(diagnostic[:int(diagnostic_len)]))
    }
    endpoint_storage: [160]u8
    endpoint_len: c.size_t
    if owned_session_copy_endpoint(
        owned,
        raw_data(endpoint_storage[:]),
        c.size_t(len(endpoint_storage)),
        &endpoint_len,
    ) != 0 {
        owned_session_destroy(owned)
        return create_error_session_view("owned_session_endpoint_failed")
    }
    endpoint := string(endpoint_storage[:int(endpoint_len)])
    view := create_session_view(endpoint, owned)
    if view == nil {
        owned_session_destroy(owned)
    }
    return view
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
    view := active_session_view(app)
    if view == nil || view.control == nil || !active_tab_is_session(app) || app.profile_menu_open || app.palette_open || app.settings_open {
        return false
    }
    key, ok := named_bridge_key(event.key.key)
    if !ok {
        return false
    }
    if event.type == .KEY_DOWN {
        _ = return_history_live(view)
    }
    action := Bridge_Key_Action.Press
    if event.type == .KEY_UP {
        action = .Release
    } else if event.key.repeat {
        action = .Repeat
    }
    result := send_named_key(
        view.control,
        u8(key),
        u8(action),
        bridge_modifiers(event.key.mod),
    )
    if result != 0 {
        copy_bridge_error(view)
    }
    return true
}

history_page_rows :: proc(view: ^Session_View) -> int {
    if view == nil {
        return 1
    }
    sync.mutex_lock(&view.mutex)
    value := max(1, int(view.rows) - 2)
    sync.mutex_unlock(&view.mutex)
    return value
}

inside :: proc(x, y: f32, rect: SDL.FRect) -> bool {
    return x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h
}

terminal_inset :: proc(width, height: f32) -> SDL.FRect {
    return {18, 52, width - 36, height - 64}
}

split_pane_rects :: proc(inset: SDL.FRect) -> (left, right: SDL.FRect) {
    gap := f32(4)
    left_width := (inset.w - gap) / 2
    left = {inset.x, inset.y, left_width, inset.h}
    right = {inset.x + left_width + gap, inset.y, inset.w - left_width - gap, inset.h}
    return
}

session_view_at :: proc(
    app: ^App,
    x, y, width, height: f32,
) -> (view: ^Session_View, pane_index: int, ok: bool) {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return nil, 0, false
    }
    inset := terminal_inset(width, height)
    if !inside(x, y, inset) {
        return nil, 0, false
    }
    tab := &app.tabs[app.active_tab]
    if tab.secondary_session == nil {
        return tab.session, 0, true
    }
    left, right := split_pane_rects(inset)
    if inside(x, y, left) {
        return tab.session, 0, true
    }
    if inside(x, y, right) {
        return tab.secondary_session, 1, true
    }
    return nil, 0, false
}

pane_rect_for_index :: proc(
    app: ^App,
    pane_index: int,
    width, height: f32,
) -> (pane: SDL.FRect, ok: bool) {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return {}, false
    }
    inset := terminal_inset(width, height)
    tab := &app.tabs[app.active_tab]
    if tab.secondary_session == nil {
        return inset, pane_index == 0
    }
    left, right := split_pane_rects(inset)
    if pane_index == 0 {
        return left, true
    }
    if pane_index == 1 {
        return right, true
    }
    return {}, false
}

selection_cell_at :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    clamp_to_surface := false,
) -> (row, column: u16, ok: bool) {
    if view == nil || !ensure_canvas(app, view) ||
       view.canvas_surface_width == 0 || view.canvas_surface_height == 0 {
        return 0, 0, false
    }
    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 {
        return 0, 0, false
    }
    origin_x := pane.x + 10
    origin_y := pane.y + 6
    right := origin_x + f32(view.canvas_surface_width)
    bottom := origin_y + f32(view.canvas_surface_height)
    local_x := x
    local_y := y
    if clamp_to_surface {
        local_x = clamp(local_x, origin_x, max(origin_x, right - 1))
        local_y = clamp(local_y, origin_y, max(origin_y, bottom - 1))
    } else if local_x < origin_x || local_x >= right || local_y < origin_y || local_y >= bottom {
        return 0, 0, false
    }
    selected_column := int((local_x - origin_x) / f32(cell_width))
    selected_row := int((local_y - origin_y) / f32(cell_height))
    columns := int(view.canvas_surface_width / cell_width)
    rows := int(view.canvas_surface_height / cell_height)
    if selected_column < 0 || selected_column >= columns || selected_row < 0 || selected_row >= rows {
        return 0, 0, false
    }
    return u16(selected_row), u16(selected_column), true
}

selection_stable_row :: proc(
    viewport_row: u16,
    history_offset, history_count_value, history_row_base_value: u32,
    alternate: bool,
) -> (row: i32, ok: bool) {
    if alternate {
        return i32(viewport_row), true
    }
    if history_offset > history_count_value {
        return 0, false
    }
    stable := i64(history_row_base_value) + i64(history_count_value) -
              i64(history_offset) + i64(viewport_row)
    if stable < 0 || stable > 0x7fffffff {
        return 0, false
    }
    return i32(stable), true
}

selection_stable_point_at :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    clamp_to_surface := false,
) -> (row: i32, column, columns: u16, alternate: bool, ok: bool) {
    viewport_row, viewport_column, hit := selection_cell_at(
        app,
        view,
        pane,
        x,
        y,
        clamp_to_surface,
    )
    if !hit || view.canvas == nil {
        return 0, 0, 0, false, false
    }
    cell_width := render_cell_width(view.canvas)
    if cell_width == 0 {
        return 0, 0, 0, false, false
    }
    columns = u16(view.canvas_surface_width / cell_width)
    if columns == 0 || viewport_column >= columns {
        return 0, 0, 0, false, false
    }
    alternate = render_alternate_screen(view.canvas) != 0
    stable_row, stable_ok := selection_stable_row(
        viewport_row,
        render_history_offset(view.canvas),
        render_history_count(view.canvas),
        render_history_row_base(view.canvas),
        alternate,
    )
    if !stable_ok {
        return 0, 0, 0, false, false
    }
    return stable_row, viewport_column, columns, alternate, true
}

begin_selection :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
) -> bool {
    row, column, columns, alternate, ok := selection_stable_point_at(
        app,
        view,
        pane,
        x,
        y,
    )
    if !ok {
        return false
    }
    sync.mutex_lock(&view.mutex)
    view.selection_active = true
    view.selection_dragging = true
    view.selection_anchor_row = row
    view.selection_anchor_column = column
    view.selection_focus_row = row
    view.selection_focus_column = column
    view.selection_edge_scroll_rows = 0
    view.selection_pointer_x = x
    view.selection_pointer_y = y
    view.selection_columns = columns
    view.selection_alternate_screen = alternate
    sync.mutex_unlock(&view.mutex)
    _ = SDL.CaptureMouse(true)
    return true
}

extend_selection :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    dragging := view.selection_dragging
    selected_columns := view.selection_columns
    selected_alternate := view.selection_alternate_screen
    sync.mutex_unlock(&view.mutex)
    if !dragging {
        return false
    }
    row, column, columns, alternate, ok := selection_stable_point_at(
        app,
        view,
        pane,
        x,
        y,
        true,
    )
    if !ok || columns != selected_columns || alternate != selected_alternate {
        return false
    }
    sync.mutex_lock(&view.mutex)
    if view.selection_dragging && view.selection_columns == columns &&
       view.selection_alternate_screen == alternate {
        view.selection_focus_row = row
        view.selection_focus_column = column
        sync.mutex_unlock(&view.mutex)
        return true
    }
    sync.mutex_unlock(&view.mutex)
    return false
}

selection_edge_scroll_direction :: proc(
    pointer_y, surface_top, surface_bottom, row_height: f32,
    can_scroll_older, can_scroll_newer: bool,
) -> i8 {
    if row_height <= 0 || surface_bottom <= surface_top {
        return 0
    }
    band := min(row_height * 2, (surface_bottom - surface_top) / 2)
    if pointer_y < surface_top + band && can_scroll_older {
        return 1
    }
    if pointer_y >= surface_bottom - band && can_scroll_newer {
        return -1
    }
    return 0
}

update_selection_edge_scroll_intent :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    pointer_x, pointer_y: f32,
) -> bool {
    if view == nil || view.canvas == nil {
        return false
    }
    cell_height := render_cell_height(view.canvas)
    if cell_height == 0 {
        return false
    }
    surface_top := pane.y + 6
    surface_bottom := surface_top + f32(view.canvas_surface_height)
    alternate := render_alternate_screen(view.canvas) != 0

    sync.mutex_lock(&view.mutex)
    dragging := view.selection_dragging
    target_offset := view.history_target_offset
    count := view.history_count
    old_direction := view.selection_edge_scroll_rows
    if !dragging {
        view.selection_edge_scroll_rows = 0
        sync.mutex_unlock(&view.mutex)
        return old_direction != 0
    }
    direction := selection_edge_scroll_direction(
        pointer_y,
        surface_top,
        surface_bottom,
        f32(cell_height),
        !alternate && target_offset < count,
        !alternate && target_offset > 0,
    )
    view.selection_edge_scroll_rows = direction
    view.selection_pointer_x = pointer_x
    view.selection_pointer_y = pointer_y
    sync.mutex_unlock(&view.mutex)
    return direction != old_direction
}

selection_edge_scroll_active :: proc(app: ^App) -> bool {
    view := active_session_view(app)
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    active := view.selection_dragging && view.selection_edge_scroll_rows != 0
    sync.mutex_unlock(&view.mutex)
    return active
}

selection_edge_scroll_tick :: proc(app: ^App) -> bool {
    view := active_session_view(app)
    if view == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return false
    }
    sync.mutex_lock(&view.mutex)
    dragging := view.selection_dragging
    direction := view.selection_edge_scroll_rows
    pointer_x := view.selection_pointer_x
    pointer_y := view.selection_pointer_y
    sync.mutex_unlock(&view.mutex)
    if !dragging || direction == 0 {
        return false
    }

    if !scroll_history_rows(view, int(direction)) {
        sync.mutex_lock(&view.mutex)
        view.selection_edge_scroll_rows = 0
        sync.mutex_unlock(&view.mutex)
        return false
    }

    w, h: c.int
    if !SDL.GetWindowSize(app.window, &w, &h) {
        return true
    }
    tab := &app.tabs[app.active_tab]
    pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h))
    if !ok {
        return true
    }
    if update_canvas(app, view) {
        _ = extend_selection(app, view, pane, pointer_x, pointer_y)
        _ = update_selection_edge_scroll_intent(view, pane, pointer_x, pointer_y)
    }
    return true
}

finish_selection :: proc(view: ^Session_View) {
    if view == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    was_dragging := view.selection_dragging
    view.selection_dragging = false
    view.selection_edge_scroll_rows = 0
    view.selection_pointer_x = 0
    view.selection_pointer_y = 0
    if view.selection_active &&
       view.selection_anchor_row == view.selection_focus_row &&
       view.selection_anchor_column == view.selection_focus_column {
        clear_selection_locked(view)
    }
    sync.mutex_unlock(&view.mutex)
    if was_dragging {
        _ = SDL.CaptureMouse(false)
    }
}

copy_selection_to_clipboard :: proc(view: ^Session_View) -> bool {
    if view == nil || view.control == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    if !view.selection_active {
        sync.mutex_unlock(&view.mutex)
        return false
    }
    anchor_row := view.selection_anchor_row
    anchor_column := view.selection_anchor_column
    focus_row := view.selection_focus_row
    focus_column := view.selection_focus_column
    selected_columns := view.selection_columns
    selected_alternate := view.selection_alternate_screen
    sync.mutex_unlock(&view.mutex)

    buffer := make([]u8, SELECTION_TEXT_BYTES)
    defer delete(buffer)
    output_len: c.size_t
    result := selection_extract(
        view.control,
        anchor_row,
        anchor_column,
        focus_row,
        focus_column,
        selected_columns,
        selected_alternate ? u8(1) : u8(0),
        raw_data(buffer),
        c.size_t(len(buffer)),
        &output_len,
    )
    if result != 0 || output_len == 0 {
        copy_bridge_error(view)
        return false
    }
    terminated := make([]u8, int(output_len) + 1)
    defer delete(terminated)
    copy(terminated[:int(output_len)], buffer[:int(output_len)])
    terminated[int(output_len)] = 0
    if !SDL.SetClipboardText(cstring(raw_data(terminated))) {
        return false
    }
    clear_selection(view)
    return true
}

paste_clipboard :: proc(view: ^Session_View) -> bool {
    if view == nil || view.control == nil || !SDL.HasClipboardText() {
        return false
    }
    bytes := SDL.GetClipboardText()
    if bytes == nil {
        return false
    }
    defer SDL.free(rawptr(bytes))
    text := string(cstring(bytes))
    if len(text) == 0 {
        return false
    }
    _ = return_history_live(view)
    if send_paste(view.control, raw_data(text), c.size_t(len(text))) != 0 {
        copy_bridge_error(view)
        return false
    }
    return true
}

selection_before_or_equal :: proc(
    left_row: i32,
    left_column: u16,
    right_row: i32,
    right_column: u16,
) -> bool {
    return left_row < right_row ||
           (left_row == right_row && left_column <= right_column)
}

Selection_Visible_Span :: struct {
    start_column: u16,
    end_column: u16,
}

selection_visible_span :: proc(
    anchor_row: i32,
    anchor_column: u16,
    focus_row: i32,
    focus_column: u16,
    stable_row: i32,
    columns: u16,
) -> (span: Selection_Visible_Span, ok: bool) {
    if columns == 0 {
        return {}, false
    }
    start_row, start_column := anchor_row, anchor_column
    end_row, end_column := focus_row, focus_column
    if !selection_before_or_equal(start_row, start_column, end_row, end_column) {
        start_row, end_row = end_row, start_row
        start_column, end_column = end_column, start_column
    }
    if stable_row < start_row || stable_row > end_row {
        return {}, false
    }
    first := u16(0)
    last := columns - 1
    if stable_row == start_row {
        first = min(start_column, columns - 1)
    }
    if stable_row == end_row {
        last = min(end_column, columns - 1)
    }
    if last < first {
        return {}, false
    }
    return Selection_Visible_Span{ start_column = first, end_column = last }, true
}

draw_selection :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    if view == nil || view.canvas == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    if !view.selection_active {
        sync.mutex_unlock(&view.mutex)
        return
    }
    anchor_row := view.selection_anchor_row
    anchor_column := view.selection_anchor_column
    focus_row := view.selection_focus_row
    focus_column := view.selection_focus_column
    selected_columns := view.selection_columns
    selected_alternate := view.selection_alternate_screen
    sync.mutex_unlock(&view.mutex)

    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 {
        return
    }
    columns := u16(view.canvas_surface_width / cell_width)
    rows := u16(view.canvas_surface_height / cell_height)
    alternate := render_alternate_screen(view.canvas) != 0
    if selected_columns != columns || selected_alternate != alternate || rows == 0 {
        return
    }

    top_row: i64 = 0
    if !alternate {
        history_offset := render_history_offset(view.canvas)
        history_count_value := render_history_count(view.canvas)
        if history_offset > history_count_value {
            return
        }
        top_row = i64(render_history_row_base(view.canvas)) +
                  i64(history_count_value) - i64(history_offset)
    }

    origin_x := pane.x + 10
    origin_y := pane.y + 6
    pane_clip := SDL.Rect{c.int(pane.x), c.int(pane.y), c.int(pane.w), c.int(pane.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &pane_clip)
    defer {
        _ = SDL.SetRenderClipRect(app.renderer, nil)
    }
    color := SDL.Color{palette.accent[0], palette.accent[1], palette.accent[2], 72}
    for viewport_row in 0..<int(rows) {
        stable_row_i64 := top_row + i64(viewport_row)
        if stable_row_i64 < -0x80000000 || stable_row_i64 > 0x7fffffff {
            continue
        }
        span, visible := selection_visible_span(
            anchor_row,
            anchor_column,
            focus_row,
            focus_column,
            i32(stable_row_i64),
            columns,
        )
        if !visible {
            continue
        }
        first := int(span.start_column)
        last := int(span.end_column)
        rect := SDL.FRect{
            origin_x + f32(first * int(cell_width)),
            origin_y + f32(viewport_row * int(cell_height)),
            f32((last - first + 1) * int(cell_width)),
            f32(cell_height),
        }
        draw_fill(app.renderer, rect, color)
    }
}

draw_search_highlight :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    if view == nil || view.canvas == nil {
        return
    }
    sync.mutex_lock(&view.mutex)
    active := view.search_result_active
    result := view.search_result
    sync.mutex_unlock(&view.mutex)
    if !active {
        return
    }

    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 {
        return
    }
    columns := u16(view.canvas_surface_width / cell_width)
    rows := u16(view.canvas_surface_height / cell_height)
    alternate := render_alternate_screen(view.canvas) != 0
    if result.columns != columns || (result.alternate_screen != 0) != alternate {
        return
    }
    top_row: i64 = 0
    if !alternate {
        top_row = i64(render_history_row_base(view.canvas)) +
                  i64(render_history_count(view.canvas)) -
                  i64(render_history_offset(view.canvas))
    }
    viewport_row := i64(result.row) - top_row
    if viewport_row < 0 || viewport_row >= i64(rows) ||
       result.start_column >= columns || result.end_column >= columns {
        return
    }

    origin_x := pane.x + 10
    origin_y := pane.y + 6
    rect := SDL.FRect{
        origin_x + f32(result.start_column * cell_width),
        origin_y + f32(viewport_row * i64(cell_height)),
        f32((result.end_column - result.start_column + 1) * cell_width),
        f32(cell_height),
    }
    fill := palette.accent
    fill[3] = 62
    draw_fill(app.renderer, rect, fill)
    edge := palette.accent
    edge[3] = 180
    draw_outline(app.renderer, rect, edge)
}

tab_controls :: proc(tab_count: int, width: f32) -> (plus, menu, settings: SDL.FRect) {
    tab_w := f32(162)
    controls_x := f32(8) + f32(tab_count) * (tab_w + 4)
    plus = {controls_x, 7, 34, 32}
    menu = {controls_x + 38, 7, 34, 32}
    settings = {width - 114, 7, 104, 32}
    return
}

add_session_tab :: proc(app: ^App, view: ^Session_View, title: string) -> bool {
    if app.tab_count >= MAX_TABS {
        if view != nil do destroy_session_view(view)
        return false
    }
    if view == nil {
        return false
    }
    app.tabs[app.tab_count] = Tab{kind = .Session, title = title, session = view}
    app.tab_count += 1
    app.active_tab = app.tab_count - 1
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
    return true
}

profile_view :: proc(app: ^App, profile: int) -> (view: ^Session_View, title: string) {
    if profile == 1 {
        return create_owned_session_view(app), "Local shell"
    }
    return create_session_view(HOME_ENDPOINT, rawptr(nil)), "Home Session"
}

open_profile_tab :: proc(app: ^App, profile: int) {
    view, title := profile_view(app, profile)
    _ = add_session_tab(app, view, title)
}

new_tab :: proc(app: ^App) {
    open_profile_tab(app, app.startup_profile)
}

open_local_tab :: proc(app: ^App) {
    open_profile_tab(app, 1)
}

attach_home_tab :: proc(app: ^App) {
    open_profile_tab(app, 0)
}

close_tab :: proc(app: ^App, index: int) {
    if app.tab_count <= 1 || index < 0 || index >= app.tab_count {
        return
    }
    retiring := app.tabs[index].session
    retiring_secondary := app.tabs[index].secondary_session
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
    destroy_session_view(retiring)
    destroy_session_view(retiring_secondary)
}

split_active_pane :: proc(app: ^App) {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return
    }
    tab := &app.tabs[app.active_tab]
    if tab.secondary_session != nil {
        tab.active_pane = 1
        return
    }
    view, _ := profile_view(app, app.startup_profile)
    if view == nil {
        return
    }
    tab.secondary_session = view
    tab.active_pane = 1
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
}

close_active_pane :: proc(app: ^App) {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return
    }
    tab := &app.tabs[app.active_tab]
    if tab.secondary_session == nil {
        close_tab(app, app.active_tab)
        return
    }
    if tab.active_pane == 1 {
        destroy_session_view(tab.secondary_session)
        tab.secondary_session = nil
    } else {
        destroy_session_view(tab.session)
        tab.session = tab.secondary_session
        tab.secondary_session = nil
    }
    tab.active_pane = 0
}

active_tab_is_session :: proc(app: ^App) -> bool {
    return app.active_tab >= 0 && app.active_tab < app.tab_count && app.tabs[app.active_tab].kind == .Session
}

execute_action :: proc(app: ^App, action: App_Action) {
    switch action {
    case .New_Tab:
        new_tab(app)
    case .Split_Pane:
        split_active_pane(app)
    case .Open_Local:
        open_local_tab(app)
    case .Attach_Home:
        attach_home_tab(app)
    case .Open_Settings:
        app.profile_menu_open = false
        app.palette_open = false
        app.settings_open = true
    case .Close_Pane:
        close_active_pane(app)
        app.palette_open = false
    }
}

palette_action :: proc(index: int) -> App_Action {
    switch index {
    case 0: return .New_Tab
    case 1: return .Split_Pane
    case 2: return .Attach_Home
    case 3: return .Open_Settings
    case:   return .Close_Pane
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
            app.palette_selection = (app.palette_selection + 4) % 5
        case SDL.K_DOWN, SDL.K_TAB:
            app.palette_selection = (app.palette_selection + 1) % 5
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
            app.profile_menu_selection = (app.profile_menu_selection + 3) % 4
        case SDL.K_DOWN, SDL.K_TAB:
            app.profile_menu_selection = (app.profile_menu_selection + 1) % 4
        case SDL.K_RETURN:
            if app.profile_menu_selection == 0 {
                execute_action(app, .Open_Local)
            } else if app.profile_menu_selection == 1 {
                execute_action(app, .Attach_Home)
            } else if app.profile_menu_selection == 2 {
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
            if app.settings_page == .Startup {
                adjust_startup_profile(app, -1)
                return true
            }
            if app.settings_page == .Appearance {
                adjust_terminal_font(app, -1)
                return true
            }
            return false
        case SDL.K_RIGHT, SDL.K_EQUALS, SDL.K_PLUS:
            if app.settings_page == .Startup {
                adjust_startup_profile(app, 1)
                return true
            }
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
    return {menu.x - 8, 44, 330, 224}
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

    if app.search_open && inside(x, y, search_bar_rect(width)) {
        return
    }

    if app.settings_open {
        if page, ok := settings_page_at(x, y, width, height); ok {
            app.settings_page = page
            return
        }
    }

    if app.palette_open {
        box_w := f32(520)
        box := SDL.FRect{(width - box_w) / 2, 92, box_w, 288}
        for i in 0..<5 {
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
        if inside(x, y, {panel.x + 8, panel.y + 8, panel.w - 16, 48}) {
            execute_action(app, .Open_Local)
            return
        }
        if inside(x, y, {panel.x + 8, panel.y + 60, panel.w - 16, 48}) {
            execute_action(app, .Attach_Home)
            return
        }
        if inside(x, y, {panel.x + 8, panel.y + 126, panel.w - 16, 36}) {
            app.profile_menu_open = false
            app.palette_open = true
            app.palette_selection = 0
            return
        }
        if inside(x, y, {panel.x + 8, panel.y + 172, panel.w - 16, 36}) {
            execute_action(app, .Open_Settings)
            return
        }
        if !inside(x, y, panel) {
            app.profile_menu_open = false
        }
    }

    if inside(x, y, plus) {
        close_search(app)
        new_tab(app)
        return
    }
    if inside(x, y, menu) {
        close_search(app)
        app.profile_menu_open = !app.profile_menu_open
        app.profile_menu_selection = 0
        app.palette_open = false
        app.settings_open = false
        return
    }
    if inside(x, y, settings) {
        close_search(app)
        app.settings_open = !app.settings_open
        app.palette_open = false
        return
    }

    tab_x := f32(8)
    tab_w := f32(162)
    for i in 0..<app.tab_count {
        rect := SDL.FRect{tab_x, 7, tab_w, 32}
        if inside(x, y, rect) {
            close_search(app)
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
        _ = finish_all_history_scrollbar_drags(app)
        _ = finish_all_selections(app)
        app.running = false
    case .WINDOW_FOCUS_LOST:
        _ = finish_all_history_scrollbar_drags(app)
        _ = finish_all_selections(app)
    case .KEY_DOWN, .KEY_UP:
        ctrl := .LCTRL in event.key.mod || .RCTRL in event.key.mod
        shift := .LSHIFT in event.key.mod || .RSHIFT in event.key.mod
        alt := .LALT in event.key.mod || .RALT in event.key.mod
        if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_F {
            if app.search_open {
                close_search(app)
            } else {
                open_search(app)
            }
        } else if app.search_open {
            if event.type == .KEY_DOWN {
                switch event.key.key {
                case SDL.K_ESCAPE:
                    close_search(app)
                case SDL.K_BACKSPACE:
                    _ = backspace_search_query(app)
                case SDL.K_RETURN:
                    _ = request_search(app, !shift)
                case:
                }
            }
            return
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_P {
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
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_TAB && app.tab_count > 1 {
            if shift {
                app.active_tab = (app.active_tab + app.tab_count - 1) % app.tab_count
            } else {
                app.active_tab = (app.active_tab + 1) % app.tab_count
            }
        } else if event.type == .KEY_DOWN && alt && shift && event.key.key == SDL.K_D {
            execute_action(app, .Split_Pane)
        } else if event.type == .KEY_DOWN && alt && (event.key.key == SDL.K_LEFT || event.key.key == SDL.K_RIGHT) {
            if app.active_tab >= 0 && app.active_tab < app.tab_count && app.tabs[app.active_tab].secondary_session != nil {
                app.tabs[app.active_tab].active_pane = event.key.key == SDL.K_RIGHT ? 1 : 0
            }
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_MINUS {
            adjust_terminal_font(app, -1)
        } else if event.type == .KEY_DOWN && ctrl && (event.key.key == SDL.K_EQUALS || event.key.key == SDL.K_PLUS) {
            adjust_terminal_font(app, 1)
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_C {
            _ = copy_selection_to_clipboard(active_session_view(app))
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_V {
            _ = paste_clipboard(active_session_view(app))
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_W {
            execute_action(app, .Close_Pane)
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_HOME &&
                  !app.profile_menu_open && !app.palette_open && !app.settings_open {
            _ = scroll_history_oldest(active_session_view(app))
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_END &&
                  !app.profile_menu_open && !app.palette_open && !app.settings_open {
            _ = return_history_live_navigation(active_session_view(app))
        } else if event.type == .KEY_DOWN && shift && event.key.key == SDL.K_PAGEUP &&
                  !app.profile_menu_open && !app.palette_open && !app.settings_open {
            view := active_session_view(app)
            if view != nil {
                _ = scroll_history_rows(view, history_page_rows(view))
            }
        } else if event.type == .KEY_DOWN && shift && event.key.key == SDL.K_PAGEDOWN &&
                  !app.profile_menu_open && !app.palette_open && !app.settings_open {
            view := active_session_view(app)
            if view != nil {
                _ = scroll_history_rows(view, -history_page_rows(view))
            }
        } else if event.type == .KEY_DOWN && event.key.key == SDL.K_ESCAPE && (app.profile_menu_open || app.palette_open || app.settings_open) {
            app.profile_menu_open = false
            app.palette_open = false
            app.settings_open = false
        } else if handle_overlay_key(app, event) {
            // Overlay-owned navigation never reaches the terminal.
        } else if send_bridge_key(app, event) {
            // The active real Session consumed this named physical key.
        } else if event.type == .KEY_DOWN && active_session_view(app) != nil && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && (ctrl || alt) {
            view := active_session_view(app)
            scalar := u32(event.key.key)
            if scalar > 0 && scalar < 0x80 {
                _ = return_history_live(view)
                action := event.key.repeat ? Bridge_Key_Action.Repeat : Bridge_Key_Action.Press
                result := send_unicode_key(
                    view.control,
                    scalar,
                    u8(action),
                    bridge_modifiers(event.key.mod),
                )
                if result != 0 {
                    copy_bridge_error(view)
                }
            }
        }
    case .TEXT_INPUT:
        if app.search_open {
            if event.text.text != nil {
                text := string(event.text.text)
                if len(text) != 0 {
                    _ = append_search_query(app, text)
                }
            }
            return
        }
        view := active_session_view(app)
        if view != nil && view.control != nil && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && event.text.text != nil {
            text := string(event.text.text)
            if len(text) != 0 {
                _ = return_history_live(view)
                result := send_text(view.control, raw_data(text), c.size_t(len(text)))
                if result != 0 {
                    copy_bridge_error(view)
                }
            }
        }
    case .MOUSE_MOTION:
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        if app.active_tab >= 0 && app.active_tab < app.tab_count {
            tab := &app.tabs[app.active_tab]
            view := active_session_view(app)
            w, h: c.int
            if view != nil && SDL.GetWindowSize(app.window, &w, &h) {
                if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok {
                    if history_scrollbar_drag_active(view) {
                        _ = update_history_scrollbar_drag(view, pane, event.motion.y)
                        return
                    }
                    if extend_selection(app, view, pane, event.motion.x, event.motion.y) {
                        _ = update_selection_edge_scroll_intent(
                            view,
                            pane,
                            event.motion.x,
                            event.motion.y,
                        )
                    }
                }
            }
        }
    case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        w, h: c.int
        if SDL.GetWindowSize(app.window, &w, &h) {
            if event.button.button == SDL.BUTTON_LEFT && event.type == .MOUSE_BUTTON_DOWN &&
               !app.profile_menu_open && !app.palette_open && !app.settings_open {
                view, pane_index, ok := session_view_at(
                    app,
                    event.button.x,
                    event.button.y,
                    f32(w), f32(h),
                )
                if ok && view != nil {
                    if app.active_tab >= 0 && app.active_tab < app.tab_count {
                        app.tabs[app.active_tab].active_pane = pane_index
                    }
                    if pane, pane_ok := pane_rect_for_index(app, pane_index, f32(w), f32(h)); pane_ok {
                        if begin_history_scrollbar_drag(view, pane, event.button.x, event.button.y) {
                            return
                        }
                        if begin_selection(app, view, pane, event.button.x, event.button.y) {
                            return
                        }
                    }
                }
            }
            if event.button.button == SDL.BUTTON_LEFT && event.type == .MOUSE_BUTTON_UP {
                view := active_session_view(app)
                if view != nil {
                    if history_scrollbar_drag_active(view) {
                        tab := &app.tabs[app.active_tab]
                        if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok {
                            _ = update_history_scrollbar_drag(view, pane, event.button.y)
                        }
                        _ = finish_history_scrollbar_drag(view)
                        return
                    }
                    sync.mutex_lock(&view.mutex)
                    dragging := view.selection_dragging
                    sync.mutex_unlock(&view.mutex)
                    if dragging {
                        tab := &app.tabs[app.active_tab]
                        if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok {
                            _ = extend_selection(app, view, pane, event.button.x, event.button.y)
                        }
                        finish_selection(view)
                        return
                    }
                }
                handle_click(app, event.button.x, event.button.y, f32(w), f32(h))
            } else if event.type == .MOUSE_BUTTON_UP {
                handle_click(app, event.button.x, event.button.y, f32(w), f32(h))
            }
        }
    case .MOUSE_WHEEL:
        if app.profile_menu_open || app.palette_open || app.settings_open {
            break
        }
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        w, h: c.int
        if SDL.GetWindowSize(app.window, &w, &h) {
            view, pane_index, ok := session_view_at(
                app,
                event.wheel.mouse_x,
                event.wheel.mouse_y,
                f32(w),
                f32(h),
            )
            if ok && view != nil {
                if app.active_tab >= 0 && app.active_tab < app.tab_count {
                    app.tabs[app.active_tab].active_pane = pane_index
                }
                wheel_rows := event.wheel.y
                if wheel_rows == 0 && event.wheel.integer_y != 0 {
                    wheel_rows = f32(event.wheel.integer_y)
                }
                if wheel_rows != 0 {
                    _ = scroll_history_wheel(view, wheel_rows)
                }
            }
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
        if app.tabs[i].kind == .Session && session_attached(app.tabs[i].session) {
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

    rows := [4]SDL.FRect{
        {panel.x + 8, panel.y + 8, panel.w - 16, 48},
        {panel.x + 8, panel.y + 60, panel.w - 16, 48},
        {panel.x + 8, panel.y + 126, panel.w - 16, 36},
        {panel.x + 8, panel.y + 172, panel.w - 16, 36},
    }
    draw_fill(app.renderer, rows[app.profile_menu_selection], palette.tab_active)

    draw_text(app, app.ui_font, "Local shell", panel.x + 18, panel.y + 14, palette.text)
    draw_text(app, app.ui_font, "Create owned Session", panel.x + 18, panel.y + 34, palette.text_muted)
    if app.startup_profile == 1 {
        draw_text(app, app.ui_font, "default", panel.x + 254, panel.y + 14, palette.accent)
    }

    draw_text(app, app.ui_font, "Home Session", panel.x + 18, panel.y + 66, palette.text)
    draw_text(app, app.ui_font, HOME_ENDPOINT, panel.x + 18, panel.y + 86, palette.text_muted)
    if app.startup_profile == 0 {
        draw_text(app, app.ui_font, "default", panel.x + 254, panel.y + 66, palette.accent)
    }

    draw_fill(app.renderer, {panel.x + 10, panel.y + 116, panel.w - 20, 1}, palette.border)
    draw_text(app, app.ui_font, "Command Palette", panel.x + 18, panel.y + 136, palette.text)
    draw_text(app, app.ui_font, "Ctrl+Shift+P", panel.x + 190, panel.y + 136, palette.text_muted)
    draw_text(app, app.ui_font, "Settings", panel.x + 18, panel.y + 182, palette.text)
    draw_text(app, app.ui_font, "Ctrl+,", panel.x + 248, panel.y + 182, palette.text_muted)
}

history_scrollbar_geometry :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
) -> (geometry: History_Scrollbar_Geometry, ok: bool) {
    if view == nil {
        return {}, false
    }

    history_offset: u32
    history_count_value: u32
    visible_rows: u32
    alternate := false
    if view.canvas != nil {
        history_offset = render_history_offset(view.canvas)
        history_count_value = render_history_count(view.canvas)
        alternate = render_alternate_screen(view.canvas) != 0
        cell_height := render_cell_height(view.canvas)
        if cell_height != 0 {
            visible_rows = u32(view.canvas_surface_height / cell_height)
        }
    } else {
        sync.mutex_lock(&view.mutex)
        history_offset = view.history_target_offset
        history_count_value = view.history_count
        visible_rows = u32(view.rows)
        alternate = view.alternate_screen
        sync.mutex_unlock(&view.mutex)
    }
    if alternate || history_count_value == 0 || visible_rows == 0 {
        return {}, false
    }

    track := SDL.FRect{pane.x + pane.w - 5, pane.y + 6, 3, pane.h - 12}
    if track.h <= 0 {
        return {}, false
    }
    thumb_top, thumb_height, thumb_ok := history_scrollbar_thumb(
        history_offset,
        history_count_value,
        visible_rows,
        track.h,
    )
    if !thumb_ok {
        return {}, false
    }
    thumb := SDL.FRect{
        track.x - 1,
        track.y + thumb_top,
        5,
        thumb_height,
    }
    hit := SDL.FRect{pane.x + pane.w - 14, track.y, 14, track.h}
    return History_Scrollbar_Geometry{
        track = track,
        thumb = thumb,
        hit = hit,
        history_offset = history_offset,
        history_count = history_count_value,
        visible_rows = visible_rows,
    }, true
}

history_scrollbar_drag_active :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    return view.history_scrollbar_dragging
}

finish_selection_if_dragging :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    dragging := view.selection_dragging
    sync.mutex_unlock(&view.mutex)
    if !dragging {
        return false
    }
    finish_selection(view)
    return true
}

finish_all_selections :: proc(app: ^App) -> bool {
    changed := false
    for index in 0..<app.tab_count {
        if finish_selection_if_dragging(app.tabs[index].session) {
            changed = true
        }
        if finish_selection_if_dragging(app.tabs[index].secondary_session) {
            changed = true
        }
    }
    return changed
}

finish_all_history_scrollbar_drags :: proc(app: ^App) -> bool {
    changed := false
    for index in 0..<app.tab_count {
        if finish_history_scrollbar_drag(app.tabs[index].session) {
            changed = true
        }
        if finish_history_scrollbar_drag(app.tabs[index].secondary_session) {
            changed = true
        }
    }
    return changed
}

update_history_scrollbar_drag :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    pointer_y: f32,
) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    dragging := view.history_scrollbar_dragging
    grab_y := view.history_scrollbar_grab_y
    sync.mutex_unlock(&view.mutex)
    if !dragging {
        return false
    }

    geometry, ok := history_scrollbar_geometry(view, pane)
    if !ok {
        _ = finish_history_scrollbar_drag(view)
        return false
    }
    relative_top := clamp(
        pointer_y - geometry.track.y - grab_y,
        f32(0),
        max(f32(0), geometry.track.h - geometry.thumb.h),
    )
    requested := history_offset_for_scrollbar_thumb(
        relative_top,
        geometry.track.h,
        geometry.thumb.h,
        geometry.history_count,
    )
    _ = set_history_offset(view, requested)
    return true
}

begin_history_scrollbar_drag :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
) -> bool {
    geometry, ok := history_scrollbar_geometry(view, pane)
    if !ok || !inside(x, y, geometry.hit) {
        return false
    }
    grab_y := geometry.thumb.h / 2
    if inside(x, y, geometry.thumb) {
        grab_y = y - geometry.thumb.y
    }
    sync.mutex_lock(&view.mutex)
    view.history_scrollbar_dragging = true
    view.history_scrollbar_grab_y = grab_y
    sync.mutex_unlock(&view.mutex)
    _ = update_history_scrollbar_drag(view, pane, y)
    if !SDL.CaptureMouse(true) {
        // Keep the initial click/seek, but never leave a drag active when SDL
        // cannot guarantee delivery after the pointer leaves the window.
        _ = finish_history_scrollbar_drag(view)
    }
    return true
}

finish_history_scrollbar_drag :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    was_dragging := view.history_scrollbar_dragging
    view.history_scrollbar_dragging = false
    view.history_scrollbar_grab_y = 0
    sync.mutex_unlock(&view.mutex)
    if was_dragging {
        _ = SDL.CaptureMouse(false)
    }
    return was_dragging
}

draw_history_scrollbar :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    geometry, ok := history_scrollbar_geometry(view, pane)
    if !ok {
        return
    }
    track_color := palette.border
    track_color[3] = 80
    draw_fill(app.renderer, geometry.track, track_color)

    thumb_color := geometry.history_offset == 0 ? palette.text_muted : palette.accent
    thumb_color[3] = geometry.history_offset == 0 ? 110 : 190
    draw_fill(app.renderer, geometry.thumb, thumb_color)
}

draw_real_session :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    if view == nil {
        return
    }
    origin_x := pane.x + 10
    origin_y := pane.y + 6
    resize_owned_session_to_pane(app, view, pane.w - 20, pane.h - 12)
    if draw_canvas_session(app, view, pane, origin_x, origin_y) {
        draw_search_highlight(app, view, pane)
        draw_selection(app, view, pane)
        draw_history_scrollbar(app, view, pane)
        if history_active(view) {
            badge := SDL.FRect{pane.x + pane.w - 92, pane.y + 8, 76, 26}
            draw_fill(app.renderer, badge, palette.title_bg)
            draw_outline(app.renderer, badge, palette.accent)
            draw_text(app, app.ui_font, "HISTORY", badge.x + 8, badge.y + 5, palette.accent)
        }
        return
    }

    pane_clip := SDL.Rect{c.int(pane.x), c.int(pane.y), c.int(pane.w), c.int(pane.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &pane_clip)
    defer {
        _ = SDL.SetRenderClipRect(app.renderer, nil)
    }

    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)

    if view.error_len != 0 {
        draw_text(app, app.ui_font, string(view.error[:view.error_len]), origin_x, origin_y, palette.accent)
        return
    }
    if view.text_len != 0 {
        draw_text(app, app.terminal_font, string(view.text[:view.text_len]), origin_x, origin_y, palette.text)
    }

    if view.cursor_visible && view.rows != 0 && view.columns != 0 {
        cell_w, cell_h: c.int
        if TTF.GetStringSize(app.terminal_font, "M", 1, &cell_w, &cell_h) {
            line_h := TTF.GetFontLineSkip(app.terminal_font)
            cursor_x := origin_x + f32(int(view.cursor_column) * int(cell_w))
            cursor_y := origin_y + f32(int(view.cursor_row) * int(line_h))
            switch view.cursor_shape {
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

    if view.text_truncated {
        draw_text(app, app.ui_font, "visible-text projection truncated", pane.x + 12, pane.y + pane.h - 24, palette.accent)
    }
    draw_selection(app, view, pane)
    draw_history_scrollbar(app, view, pane)
    if history_active(view) {
        badge := SDL.FRect{pane.x + pane.w - 92, pane.y + 8, 76, 26}
        draw_fill(app.renderer, badge, palette.title_bg)
        draw_outline(app.renderer, badge, palette.accent)
        draw_text(app, app.ui_font, "HISTORY", badge.x + 8, badge.y + 5, palette.accent)
    }
}

search_bar_rect :: proc(width: f32) -> SDL.FRect {
    box_width := min(f32(640), max(f32(360), width - 72))
    return {width - box_width - 22, 54, box_width, 46}
}

draw_search_bar :: proc(app: ^App, width: f32) {
    box := search_bar_rect(width)
    draw_fill(app.renderer, box, palette.title_bg)
    draw_outline(app.renderer, box, palette.border)
    draw_text(app, app.ui_font, "Find", box.x + 12, box.y + 12, palette.text_muted)

    field := SDL.FRect{box.x + 58, box.y + 6, max(f32(160), box.w - 340), 34}
    draw_fill(app.renderer, field, palette.terminal_bg)
    draw_outline(app.renderer, field, palette.accent)
    query := string(app.search_query[:app.search_query_len])
    query_color := palette.text
    if app.search_query_len == 0 {
        query = "type to search"
        query_color = palette.text_muted
    }
    clip := SDL.Rect{c.int(field.x + 8), c.int(field.y), c.int(field.w - 16), c.int(field.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &clip)
    draw_text(app, app.ui_font, query, field.x + 9, field.y + 8, query_color)
    _ = SDL.SetRenderClipRect(app.renderer, nil)

    status := "Enter older  Shift+Enter newer"
    status_color := palette.text_muted
    view := active_session_view(app)
    if view != nil {
        sync.mutex_lock(&view.mutex)
        running := view.search_pending ||
                   (view.search_running && view.search_running_generation == view.search_generation)
        state := view.search_state
        last_complete := view.search_last_complete
        search_available := view.control != nil
        sync.mutex_unlock(&view.mutex)
        if !search_available {
            status = "search unavailable"
            status_color = palette.accent
        } else if running {
            status = "searching..."
            status_color = palette.accent
        } else {
            switch state {
            case .Found:
                status = last_complete ? "match" : "match · history moved"
                status_color = palette.accent
            case .Not_Found:
                status = last_complete ? "no match" : "history moved · retry"
                status_color = palette.accent
            case .Stale:
                status = "match expired"
                status_color = palette.accent
            case .Error:
                status = "search failed"
                status_color = palette.accent
            case .Idle:
            }
        }
    }
    draw_text(app, app.ui_font, status, field.x + field.w + 14, box.y + 13, status_color)
}

draw_placeholder_session :: proc(app: ^App) {
    draw_text(app, app.terminal_font, "Profile shell placeholder", 34, 86, palette.text_muted)
    draw_text(app, app.terminal_font, "The Home tab is the real canonical Howl Session.", 34, 116, palette.text)
}

draw_terminal :: proc(app: ^App, width, height: f32) {
    body := SDL.FRect{0, 46, width, height - 46}
    draw_fill(app.renderer, body, palette.terminal_bg)

    inset := terminal_inset(width, height)
    draw_fill(app.renderer, inset, palette.terminal_panel)

    if !active_tab_is_session(app) {
        draw_placeholder_session(app)
        return
    }
    tab := &app.tabs[app.active_tab]
    if tab.secondary_session == nil {
        draw_real_session(app, tab.session, inset)
        return
    }

    gap := f32(4)
    left, right := split_pane_rects(inset)
    draw_fill(app.renderer, left, palette.terminal_panel)
    draw_fill(app.renderer, right, palette.terminal_panel)
    divider := SDL.FRect{left.x + left.w, inset.y, gap, inset.h}
    draw_fill(app.renderer, divider, palette.border)

    draw_real_session(app, tab.session, left)
    draw_real_session(app, tab.secondary_session, right)
    draw_outline(app.renderer, tab.active_pane == 0 ? left : right, palette.accent)
}

draw_palette :: proc(app: ^App, width, height: f32) {
    box_w := f32(520)
    box_h := f32(288)
    box := SDL.FRect{(width - box_w) / 2, 92, box_w, box_h}
    draw_fill(app.renderer, box, palette.title_bg)
    draw_outline(app.renderer, box, palette.border)

    search := SDL.FRect{box.x + 18, box.y + 18, box.w - 36, 40}
    draw_fill(app.renderer, search, palette.terminal_bg)
    draw_outline(app.renderer, search, palette.accent)
    draw_text(app, app.ui_font, "> Command Palette", search.x + 12, search.y + 10, palette.text)

    labels := [5]string{"New tab", "Split pane", "Attach Home Session", "Open settings", "Close pane / tab"}
    shortcuts := [5]string{"Ctrl+T", "Alt+Shift+D", "", "Ctrl+,", "Ctrl+Shift+W"}
    for label, i in labels {
        row := SDL.FRect{box.x + 18, box.y + 70 + f32(i) * 36, box.w - 36, 34}
        if app.palette_selection == i {
            draw_fill(app.renderer, row, palette.tab_active)
        }
        has_split := app.active_tab >= 0 && app.active_tab < app.tab_count && app.tabs[app.active_tab].secondary_session != nil
        enabled := i != 4 || has_split || app.tab_count > 1
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
        draw_setting_field(app, "Default profile   Left/Right", startup_profile_label(app.startup_profile), content_x, content_y + 48, 300)
        draw_setting_field(app, "Startup action", startup_action_label(app.startup_profile), content_x, content_y + 126, 300)
        draw_setting_field(app, app.startup_profile == 1 ? "Session owner" : "Endpoint", app.startup_profile == 1 ? "Sibling howl-sessiond" : HOME_ENDPOINT, content_x, content_y + 204, 360)
    case .Interaction:
        draw_setting_field(app, "Input path", "howl-client semantic actions", content_x, content_y + 48, 340)
        draw_setting_field(app, "Observation", "Blocking revision worker", content_x, content_y + 126, 340)
        draw_setting_field(app, "Selection / clipboard", "Drag select / Ctrl+Shift+C,V", content_x, content_y + 204, 340)
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
        action_names := [7]string{"New tab", "Split pane", "Close pane / tab", "Focus left pane", "Focus right pane", "Command Palette", "Profile menu"}
        action_keys := [7]string{"Ctrl+T", "Alt+Shift+D", "Ctrl+Shift+W", "Alt+Left", "Alt+Right", "Ctrl+Shift+P", "Ctrl+Shift+Space"}
        for name, index in action_names {
            y := content_y + 54 + f32(index) * 42
            draw_text(app, app.ui_font, name, content_x, y, palette.text)
            draw_text(app, app.ui_font, action_keys[index], content_x + 230, y, palette.text_muted)
        }
    case .Profile_Defaults:
        draw_setting_field(app, "Profile kind", "Created local shell", content_x, content_y + 48, 300)
        draw_setting_field(app, "Geometry leadership", "Pane-owned", content_x, content_y + 126, 300)
        draw_setting_field(app, "Session lifetime", "Tab / pane-owned child Session", content_x, content_y + 204, 340)
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

    if app.search_open {
        draw_search_bar(app, width)
    }

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
    assert(size_of(Canvas_Resource_Info) == int(render_resource_info_size()))
    assert(size_of(Canvas_Removal_Info) == int(render_removal_info_size()))
    assert(size_of(Canvas_Command_Info) == int(render_command_info_size()))
    assert(size_of(Search_Match_Info) == int(search_match_info_size()))
    if !SDL.Init(SDL.INIT_VIDEO) {
        sdl_error("SDL_Init failed")
        return
    }
    defer SDL.Quit()

    session_update_event_type = SDL.RegisterEvents(1)
    if session_update_event_type == 0 {
        sdl_error("SDL_RegisterEvents failed")
        return
    }

    if !TTF.Init() {
        sdl_error("TTF_Init failed")
        return
    }

    flags := SDL.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY}
    window := SDL.CreateWindow("Howl Desktop - Odin canary", 1180, 760, flags)
    if window == nil {
        sdl_error("SDL_CreateWindow failed")
        return
    }
    defer SDL.DestroyWindow(window)

    renderer_name: cstring = nil
    if os.get_env("HOWL_ODIN_SDL_RENDERER", context.temp_allocator) == "software" {
        renderer_name = "software"
    }
    renderer := SDL.CreateRenderer(window, renderer_name)
    if renderer == nil {
        sdl_error("SDL_CreateRenderer failed")
        return
    }
    defer SDL.DestroyRenderer(renderer)

    _ = SDL.StartTextInput(window)
    defer {
        _ = SDL.StopTextInput(window)
    }

    _ = SDL.SetRenderVSync(renderer, 1)
    _ = SDL.SetRenderDrawBlendMode(renderer, SDL.BLENDMODE_BLEND)

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

    user_config := load_user_config()
    terminal_font_preset := font_preset_from_pixels(user_config.terminal_font_pixels)
    terminal_font := TTF.OpenFont(UI_FONT_PATH, font_size_for_preset(terminal_font_preset))
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
        terminal_font_preset = terminal_font_preset,
        running = true,
        tab_count = 0,
        active_tab = -1,
        next_session_identity = 1,
        startup_profile = user_config.startup_profile,
    }
    new_tab(&app)

    draw(&app)
    for app.running {
        event: SDL.Event
        if selection_edge_scroll_active(&app) {
            if !SDL.WaitEventTimeout(&event, SELECTION_EDGE_SCROLL_MS) {
                if selection_edge_scroll_tick(&app) && app.running {
                    draw(&app)
                }
                continue
            }
        } else if !SDL.WaitEvent(&event) {
            continue
        }
        handle_event(&app, &event)
        for SDL.PollEvent(&event) {
            handle_event(&app, &event)
        }
        if app.running {
            draw(&app)
        }
    }

    for app.tab_count > 0 {
        app.tab_count -= 1
        destroy_session_view(app.tabs[app.tab_count].session)
        destroy_session_view(app.tabs[app.tab_count].secondary_session)
        app.tabs[app.tab_count] = {}
    }
}
