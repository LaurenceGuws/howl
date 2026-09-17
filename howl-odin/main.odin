package main

import "core:c"
import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:time"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

UI_FONT_PATH :: "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
HOME_ENDPOINT :: "tcp://127.0.0.1:39601"
APP_NAME :: "Howl"
APP_VERSION :: "0.1.6-dev"
APP_IDENTIFIER :: "io.github.laurenceguws.howl"
APP_WINDOW_ICON :: "howl-window-icon.bmp"
SESSION_TEXT_BYTES :: 512 * 1024
SELECTION_TEXT_BYTES :: 1024 * 1024
SEARCH_QUERY_BYTES :: 512
SESSION_RETRY_MS :: 50
SELECTION_EDGE_SCROLL_MS :: 100
INTERACTION_CACHE_MS :: 120
IME_PREEDIT_BYTES :: 1024
MAX_TABS :: 8
MAX_PANES_PER_TAB :: 8
MAX_CANVAS_RESOURCES :: 8
OWNED_SESSION_ROWS :: u16(37)
OWNED_SESSION_COLUMNS :: u16(80)
FONT_PRESET_MIN :: 0
FONT_PRESET_MAX :: 2
CONFIG_SCHEMA :: 3

User_Keybinding_Config :: struct {
    action: string `json:"action"`,
    shortcut: string `json:"shortcut"`,
}

User_Config :: struct {
    schema: int `json:"schema"`,
    terminal_font_pixels: int `json:"terminal_font_pixels"`,
    startup_profile: int `json:"startup_profile"`,
    default_profile: string `json:"default_profile"`,
    profiles: []User_Profile_Config `json:"profiles"`,
    keybindings: []User_Keybinding_Config `json:"keybindings"`,
    app_theme: string `json:"app_theme"`,
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

Desktop_Primary_Pointer_Route :: enum u8 {
    Local_Selection,
    Terminal_Mouse,
    Interaction_State,
}

Desktop_Wheel_Route :: enum u8 {
    History,
    Terminal_Mouse,
    Alternate_Scroll,
    Ignore,
    Interaction_State,
}

Session_Ownership :: enum u8 {
    Attached,
    Owned,
}

Session_Lifecycle_State :: enum u8 {
    Connecting,
    Active,
    Closed,
    Unavailable,
}

Pane_Node_Kind :: enum u8 {
    Leaf,
    Split,
}

Pane_Split_Orientation :: enum u8 {
    Vertical,
    Horizontal,
}

Pane_Direction :: enum u8 {
    Left,
    Right,
    Up,
    Down,
}

Pane_Node :: struct {
    kind: Pane_Node_Kind,
    pane_index: int,
    orientation: Pane_Split_Orientation,
    ratio: f32,
    parent: ^Pane_Node,
    first: ^Pane_Node,
    second: ^Pane_Node,
}

Tab :: struct {
    kind: Tab_Kind,
    title: string,
    profile: int,
    panes: [MAX_PANES_PER_TAB]^Session_View,
    pane_count: int,
    root: ^Pane_Node,
    active_pane: int,
    zoomed: bool,
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
    ownership: Session_Ownership,
    owned_process: rawptr,
    profile_index: int,
    profile_font_pixels: u16,
    control: rawptr,
    control_pending_handle: rawptr,
    control_connect_done: bool,
    control_failed: bool,
    control_notice: [160]u8,
    control_notice_len: int,
    io_failed: bool,
    ui_dirty: bool,
    control_interrupt: rawptr,
    observer_interrupt: rawptr,
    control_thread: ^thread.Thread,
    control_cond: sync.Cond,
    control_tasks: [CONTROL_QUEUE_ITEMS]Control_Task,
    control_head, control_count, control_bytes: int,
    control_result: Control_Result,
    control_result_ready: bool,
    copy_pending, copy_completed: bool,
    copy_pending_request, copy_completed_request: u64,
    clipboard_reply: []u8,
    clipboard_reply_code: i32,
    selection_generation: u64,
    observer: rawptr,
    observer_thread: ^thread.Thread,
    // Single latest immutable live projection. Main moves it to a render job.
    reusable_view: rawptr,
    search: rawptr,
    search_interrupt: rawptr,
    search_failed: bool,
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
    interaction_state: Interaction_State_Info,
    interaction_state_valid: bool,
    terminal_mouse_buttons: u8,
    terminal_mouse_captured: bool,
    terminal_mouse_last_row: i32,
    terminal_mouse_last_column: u16,
    terminal_mouse_last_pixel_x: u32,
    terminal_mouse_last_pixel_y: u32,
    endpoint: [PROFILE_ENDPOINT_BYTES]u8,
    endpoint_len: int,
    text: []u8,
    scratch: []u8,
    text_len: int,
    display_title: [1024]u8,
    display_title_len: int,
    task_progress: u16,
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
    history_generation: u64,
    history_anchor_top_row: u64,
    history_anchor_valid: bool,
    history_wheel_rows: f32,
    history_scrollbar_dragging: bool,
    history_scrollbar_grab_y: f32,
    alternate_screen: bool,
    stream_closed: bool,
    child_exited: bool,
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
    render_work: ^Render_Work,
    canvas_font_pixels: u16,
    canvas_scale: f32,
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
    size_control: Session_Size_Control,
}

App_Action :: enum {
    New_Tab,
    New_Window,
    Duplicate_Tab,
    Split_Vertical,
    Split_Horizontal,
    Toggle_Pane_Zoom,
    Open_Local,
    Attach_Home,
    Recover_Session,
    Open_Settings,
    Open_Command_Palette,
    Open_Profile_Menu,
    Close_Pane,
    Toggle_Fullscreen,
    Next_Tab,
    Previous_Tab,
    Close_Tab,
    Move_Tab_Left,
    Move_Tab_Right,
    Take_Size_Control,
    Stop_Resizing,
}

Action_Category :: enum u8 {
    Window,
    Tab,
    Pane,
    Profile,
    Application,
}

Action_Definition :: struct {
    action: App_Action,
    id: string,
    label: string,
    default_shortcut: string,
    category: Action_Category,
}

ACTION_DEFINITIONS :: [21]Action_Definition{
    {.New_Tab, "new_tab", "New tab", "Ctrl+T", .Tab},
    {.New_Window, "new_window", "New window", "Ctrl+Shift+N", .Window},
    {.Duplicate_Tab, "duplicate_tab", "Duplicate tab recipe", "Ctrl+Shift+D", .Tab},
    {.Split_Vertical, "split_right", "Split pane right", "Alt+Shift+D", .Pane},
    {.Split_Horizontal, "split_down", "Split pane down", "Alt+Shift+-", .Pane},
    {.Toggle_Pane_Zoom, "toggle_pane_zoom", "Toggle pane zoom", "Ctrl+Shift+Z", .Pane},
    {.Open_Local, "open_local", "Open Local shell", "", .Profile},
    {.Attach_Home, "attach_home", "Attach Home Session", "", .Profile},
    {.Recover_Session, "recover_session", "Restart / reconnect pane", "Ctrl+Shift+R", .Pane},
    {.Open_Settings, "open_settings", "Open settings", "Ctrl+,", .Application},
    {.Open_Command_Palette, "command_palette", "Command Palette", "Ctrl+Shift+P", .Application},
    {.Open_Profile_Menu, "profile_menu", "Profile menu", "Ctrl+Shift+Space", .Application},
    {.Close_Pane, "close_pane", "Close pane / tab", "Ctrl+Shift+W", .Pane},
    {.Toggle_Fullscreen, "toggle_fullscreen", "Toggle fullscreen", "F11", .Window},
    {.Next_Tab, "next_tab", "Next tab", "Ctrl+Tab", .Tab},
    {.Previous_Tab, "previous_tab", "Previous tab", "Ctrl+Shift+Tab", .Tab},
    {.Close_Tab, "close_tab", "Close entire tab", "", .Tab},
    {.Move_Tab_Left, "move_tab_left", "Move tab left", "Ctrl+Shift+PageUp", .Tab},
    {.Move_Tab_Right, "move_tab_right", "Move tab right", "Ctrl+Shift+PageDown", .Tab},
    {.Take_Size_Control, "take_size_control", "Take Session size control", "", .Pane},
    {.Stop_Resizing, "stop_resizing", "Stop resizing Session", "", .Pane},
}

PALETTE_ACTIONS :: [19]App_Action{
    .New_Tab,
    .New_Window,
    .Duplicate_Tab,
    .Split_Vertical,
    .Split_Horizontal,
    .Toggle_Pane_Zoom,
    .Open_Local,
    .Attach_Home,
    .Recover_Session,
    .Take_Size_Control,
    .Stop_Resizing,
    .Open_Settings,
    .Close_Pane,
    .Toggle_Fullscreen,
    .Next_Tab,
    .Previous_Tab,
    .Close_Tab,
    .Move_Tab_Left,
    .Move_Tab_Right,
}



action_from_id :: proc(id: string) -> (App_Action, bool) {
    for definition in ACTION_DEFINITIONS {
        if definition.id == id {
            return definition.action, true
        }
    }
    return .New_Tab, false
}

action_definition :: proc(action: App_Action) -> (Action_Definition, bool) {
    for definition in ACTION_DEFINITIONS {
        if definition.action == action {
            return definition, true
        }
    }
    return {}, false
}

action_enabled :: proc(app: ^App, action: App_Action) -> bool {
    switch action {
    case .New_Tab, .Duplicate_Tab, .Open_Local, .Attach_Home:
        return app != nil && app.tab_count < MAX_TABS
    case .Split_Vertical, .Split_Horizontal:
        return app != nil && app.active_tab >= 0 && app.active_tab < app.tab_count &&
               app.tabs[app.active_tab].pane_count < MAX_PANES_PER_TAB
    case .Toggle_Pane_Zoom:
        return app != nil && app.active_tab >= 0 && app.active_tab < app.tab_count &&
               app.tabs[app.active_tab].pane_count > 1
    case .Take_Size_Control, .Stop_Resizing:
        return app != nil && size_action_enabled(active_session_view(app), action)
    case .Recover_Session:
        return app != nil && session_recoverable(active_session_view(app))
    case .Close_Pane, .Close_Tab:
        return app != nil && app.tab_count > 0 && app.active_tab >= 0 && app.active_tab < app.tab_count
    case .Next_Tab, .Previous_Tab:
        return app != nil && app.tab_count > 1 && app.active_tab >= 0 && app.active_tab < app.tab_count
    case .Move_Tab_Left:
        return app != nil && app.active_tab > 0 && app.active_tab < app.tab_count
    case .Move_Tab_Right:
        return app != nil && app.active_tab >= 0 && app.active_tab + 1 < app.tab_count
    case .Toggle_Fullscreen:
        return app != nil && app.window != nil
    case .New_Window, .Open_Settings, .Open_Command_Palette, .Open_Profile_Menu:
        return app != nil
    }
    return false
}

action_label :: proc(action: App_Action) -> string {
    if definition, ok := action_definition(action); ok {
        return definition.label
    }
    return "Unknown action"
}

action_default_shortcut :: proc(action: App_Action) -> string {
    if definition, ok := action_definition(action); ok {
        return definition.default_shortcut
    }
    return ""
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

desktop_io_runtime: rawptr
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
    clipboard_request: u64,
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    ui_font: ^TTF.Font,
    terminal_font: ^TTF.Font,
    terminal_fonts: Desktop_Fonts,
    terminal_font_preset: int,
    text_scale: f32,
    app_theme: App_Theme,
    running: bool,
    client_chrome: bool,
    chrome_pressed: Window_Button,
    chrome_hover: Window_Button,
    window_pointer_buttons: u32,
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
    ime_preedit: [IME_PREEDIT_BYTES]u8,
    ime_preedit_len: int,
    ime_preedit_start: i32,
    ime_preedit_length: i32,
    next_session_identity: u32,
    profiles: [MAX_PROFILES]^Profile,
    profile_count: int,
    startup_profile: int,
    tab_dragging: bool,
    tab_drag_index: int,
    tab_drag_x: f32,
    tab_drag_grab_x: f32,
    discard_local_drag_release: bool,
    pane_resize_node: ^Pane_Node,
    pane_resize_tab: int,
    action_bindings: [len(ACTION_DEFINITIONS)]Action_Binding,
    action_keys_owned: [512]bool,
    config_notice: [192]u8,
    config_notice_len: int,
    settings_content_focus: bool,
    settings_scroll_y: f32,
    settings_scroll_page: Settings_Page,
    settings_delete_pending: bool,
    settings_delete_profile: int,
    settings_profile_select_all: bool,
    settings_action_selection: int,
    settings_binding_recording: bool,
    settings_profile_selection: int,
    settings_profile_field: int,
    settings_profile_env_selection: int,
    settings_profile_editing: bool,
    settings_profile_edit_field: Profile_Edit_Field,
    settings_profile_edit_env_index: int,
    settings_profile_edit_buffer: [PROFILE_EDIT_BYTES]u8,
    settings_profile_edit_len: int,
    settings_notice: [192]u8,
    settings_notice_len: int,
    settings_search_open: bool,
    settings_search_query: [SETTINGS_SEARCH_BYTES]u8,
    settings_search_query_len: int,
    settings_search_results: [MAX_SETTINGS_SEARCH_RESULTS]Settings_Search_Result,
    settings_search_result_count: int,
    settings_search_selection: int,
    consequence_owners: [MAX_CONSEQUENCE_OWNERS]^Consequence_Owner,
    consequence_owner_count: int,
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
    result := User_Config{schema = CONFIG_SCHEMA, terminal_font_pixels = 15, startup_profile = 0, app_theme = "howl_dark"}
    _, path, _, ok := config_paths()
    if !ok {
        return result
    }
    data, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil {
        return result
    }
    candidate: User_Config
    if json.unmarshal(data, &candidate, allocator=context.temp_allocator) != nil ||
       (candidate.schema != 1 && candidate.schema != 2 && candidate.schema != CONFIG_SCHEMA) {
        return result
    }
    if candidate.terminal_font_pixels == 12 || candidate.terminal_font_pixels == 15 || candidate.terminal_font_pixels == 18 {
        result.terminal_font_pixels = candidate.terminal_font_pixels
    }
    if candidate.startup_profile >= 0 && candidate.startup_profile <= 1 {
        result.startup_profile = candidate.startup_profile
    }
    if candidate.schema >= 2 {
        result.keybindings = candidate.keybindings
    }
    if candidate.schema >= 3 {
        result.default_profile = candidate.default_profile
        result.profiles = candidate.profiles
        if _, theme_ok := parse_app_theme(candidate.app_theme); theme_ok {
            result.app_theme = candidate.app_theme
        }
    }
    return result
}

save_user_config :: proc(app: ^App) {
    directory, path, temporary, ok := config_paths()
    if !ok {
        return
    }
    if err := os.make_directory_all(directory); err != nil && err != .Exist {
        return
    }
    overrides: [len(ACTION_DEFINITIONS)]User_Keybinding_Config
    override_count := 0
    for binding in app.action_bindings {
        if !binding.customized {
            continue
        }
        definition, defined := action_definition(binding.action)
        if !defined || override_count >= len(overrides) {
            continue
        }
        overrides[override_count] = User_Keybinding_Config{
            action = definition.id,
            shortcut = action_binding_text(app, binding.action),
        }
        override_count += 1
    }

    profile_configs: [MAX_PROFILES]User_Profile_Config
    profile_env_configs: [MAX_PROFILES][MAX_PROFILE_ENV]User_Profile_Env_Config
    profile_config_count := 0
    for index in 0..<app.profile_count {
        profile := app.profiles[index]
        if profile == nil || profile.built_in {
            continue
        }
        env_count := 0
        for env_index in 0..<profile.env_count {
            entry := &profile.env[env_index]
            profile_env_configs[profile_config_count][env_count] = User_Profile_Env_Config{
                name = profile_env_name(entry),
                value = profile_env_value(entry),
            }
            env_count += 1
        }
        profile_configs[profile_config_count] = User_Profile_Config{
            id = profile_id(profile),
            name = profile_name(profile),
            mode = profile_mode_text(profile.mode),
            shell = profile_shell(profile),
            command = profile_command(profile),
            cwd = profile_cwd(profile),
            endpoint = profile_endpoint(profile),
            environment = profile_env_configs[profile_config_count][:env_count],
            font_pixels = int(profile.font_pixels),
        }
        profile_config_count += 1
    }

    default_profile := profile_at(app, app.startup_profile)
    default_id := profile_id(default_profile)
    value := User_Config{
        schema = CONFIG_SCHEMA,
        terminal_font_pixels = int(font_pixels_for_preset(app.terminal_font_preset)),
        startup_profile = default_id == "local" ? 1 : 0,
        default_profile = default_id,
        profiles = profile_configs[:profile_config_count],
        keybindings = overrides[:override_count],
        app_theme = app_theme_id(app.app_theme),
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

startup_profile_label :: proc(app: ^App, value: int) -> string {
    return profile_name(profile_at(app, value))
}

startup_action_label :: proc(app: ^App, value: int) -> string {
    profile := profile_at(app, value)
    if profile == nil {
        return "Unavailable"
    }
    return profile.mode == .Launch ? "Create owned Session" : "Attach existing Session"
}

adjust_startup_profile :: proc(app: ^App, delta: int) {
    if app == nil || app.profile_count == 0 {
        return
    }
    next := clamp(app.startup_profile + delta, 0, app.profile_count - 1)
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
    scale := app.text_scale
    if !valid_canvas_scale(scale) {
        scale = 1
    }
    if set_font_display_scale(app.terminal_font, font_size_for_preset(next), scale) {
        app.terminal_font_preset = next
        for index in 0..<app.tab_count {
            for view in app.tabs[index].panes {
                if view != nil do reset_canvas(view)
            }
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

CANVAS_SCALE_MAX :: f32(8)

valid_canvas_scale :: proc(scale: f32) -> bool {
    return scale == scale && scale > 0 && scale <= CANVAS_SCALE_MAX
}

scaled_canvas_font_pixels :: proc(logical_pixels: u16, scale: f32) -> (u16, bool) {
    if logical_pixels == 0 || !valid_canvas_scale(scale) {
        return 0, false
    }
    scaled := f32(logical_pixels) * scale
    if scaled <= 0 || scaled > f32(0xffff) - 0.5 {
        return 0, false
    }
    pixels := int(math.floor(scaled + 0.5))
    if pixels <= 0 || pixels > 0xffff {
        return 0, false
    }
    return u16(pixels), true
}

TEXT_DPI_BASE :: f32(72)

scaled_text_dpi :: proc(scale: f32) -> (c.int, bool) {
    if !valid_canvas_scale(scale) {
        return 0, false
    }
    scaled := TEXT_DPI_BASE * scale
    if scaled <= 0 || scaled > f32(0x7fffffff) - 0.5 {
        return 0, false
    }
    dpi := int(math.floor(scaled + 0.5))
    if dpi <= 0 || dpi > 0x7fffffff {
        return 0, false
    }
    return c.int(dpi), true
}

set_font_display_scale :: proc(font: ^TTF.Font, logical_points, scale: f32) -> bool {
    if font == nil || logical_points <= 0 {
        return false
    }
    dpi, ok := scaled_text_dpi(scale)
    if !ok {
        return false
    }
    return TTF.SetFontSizeDPI(font, logical_points, dpi, dpi)
}

update_text_display_scale :: proc(app: ^App) -> bool {
    if app == nil || app.window == nil || app.ui_font == nil || app.terminal_font == nil {
        return false
    }
    scale := SDL.GetWindowDisplayScale(app.window)
    if !valid_canvas_scale(scale) {
        return false
    }
    if app.text_scale == scale {
        return true
    }
    previous := app.text_scale
    if !valid_canvas_scale(previous) {
        previous = 1
    }
    if !set_font_display_scale(app.ui_font, 15, scale) {
        return false
    }
    if !set_font_display_scale(app.terminal_font, font_size_for_preset(app.terminal_font_preset), scale) {
        _ = set_font_display_scale(app.ui_font, 15, previous)
        return false
    }
    app.text_scale = scale
    return true
}

canvas_scale_value :: proc(view: ^Session_View) -> f32 {
    if view != nil && valid_canvas_scale(view.canvas_scale) {
        return view.canvas_scale
    }
    return 1
}

canvas_logical_extent :: proc(view: ^Session_View, physical: u16) -> f32 {
    return f32(physical) / canvas_scale_value(view)
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
    if view.render_work != nil {
        stop_render_worker(view.render_work)
        view.render_work = nil
    }
    view.canvas = nil
    if view.canvas_commands != nil {
        delete(view.canvas_commands)
        view.canvas_commands = nil
    }
    view.canvas_font_pixels = 0
    view.canvas_scale = 0
    view.canvas_session_revision = 0
    view.canvas_history_offset = 0
    view.canvas_frame_revision = 0
    view.canvas_surface_width = 0
    view.canvas_surface_height = 0
    view.canvas_error_len = 0
    sync.mutex_lock(&view.mutex)
    view.size_control.applied = {}
    sync.mutex_unlock(&view.mutex)
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
    if app == nil || app.window == nil || view == nil do return false
    logical_pixels := view.profile_font_pixels
    if logical_pixels == 0 do logical_pixels = font_pixels_for_preset(app.terminal_font_preset)
    scale := SDL.GetWindowDisplayScale(app.window)
    pixels, scaled := scaled_canvas_font_pixels(logical_pixels, scale)
    if !scaled { set_canvas_error(view, "invalid display scale"); return false }
    if view.render_work != nil && view.canvas_font_pixels != pixels do reset_canvas(view)
    if view.render_work == nil {
        if len(session_endpoint(view)) == 0 do return false
        view.render_work = start_render_worker(app, view, pixels)
        if view.render_work == nil { set_canvas_error(view, "render worker creation failed"); return false }
        view.canvas_font_pixels = pixels
    }
    view.canvas_scale = scale
    work := view.render_work
    sync.mutex_lock(&work.mutex)
    if work.created && view.canvas == nil {
        view.canvas = work.handle
        if work.failed {
            set_canvas_error(view, string(work.error[:work.error_len]))
            publish_initial_error(view, string(work.error[:work.error_len]))
        }
    }
    sync.mutex_unlock(&work.mutex)
    return view.canvas != nil
}

update_canvas :: proc(app: ^App, view: ^Session_View) -> bool {
    if !ensure_canvas(app, view) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    target_revision := view.revision
    requested_history_offset := view.history_target_offset
    requested_history_generation := view.history_generation
    sync.mutex_unlock(&view.mutex)
    if target_revision == 0 do return false
    work := view.render_work
    sync.mutex_lock(&work.mutex)
    ready := work.ready
    code := work.code
    prepared_history_generation := work.history_generation
    sync.mutex_unlock(&work.mutex)
    if !ready {
        if view.canvas_session_revision < target_revision || view.canvas_history_offset != requested_history_offset || len(view.canvas_commands) == 0 {
            request_render(work, view, target_revision, requested_history_offset, requested_history_generation)
        }
        return len(view.canvas_commands) != 0
    }
    if code != 0 {
        copy_canvas_bridge_error(view)
        publish_initial_error(view, string(view.canvas_error[:view.canvas_error_len]))
        sync.mutex_lock(&work.mutex)
        work.ready = false
        sync.mutex_unlock(&work.mutex)
        return len(view.canvas_commands) != 0
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
    render_accept(view.canvas)
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
        prepared_history_generation,
    )
    view.canvas_error_len = 0
    sync.mutex_lock(&work.mutex)
    work.ready = false
    sync.mutex_unlock(&work.mutex)
    sync.mutex_lock(&view.mutex)
    latest_revision := view.revision
    latest_history := view.history_target_offset
    latest_generation := view.history_generation
    sync.mutex_unlock(&view.mutex)
    if view.canvas_session_revision < latest_revision || view.canvas_history_offset != latest_history {
        request_render(work, view, latest_revision, latest_history, latest_generation)
    }
    return true
}

rgba_channel :: proc(bits: u32, shift: u32) -> u8 {
    return u8((bits >> shift) & 0xff)
}

draw_canvas_session :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect, origin_x, origin_y: f32) -> bool {
    if !update_canvas(app, view) {
        return false
    }
    color := render_background_rgba(view.canvas)
    draw_fill(app.renderer, pane, {rgba_channel(color, 0), rgba_channel(color, 8), rgba_channel(color, 16), rgba_channel(color, 24)})
    scale := canvas_scale_value(view)
    pane_left := c.int(math.floor(pane.x))
    pane_top := c.int(math.floor(pane.y))
    pane_right := c.int(math.ceil(pane.x + pane.w))
    pane_bottom := c.int(math.ceil(pane.y + pane.h))
    pane_clip := SDL.Rect{pane_left, pane_top, pane_right - pane_left, pane_bottom - pane_top}
    defer {
        _ = SDL.SetRenderClipRect(app.renderer, nil)
    }
    for command in view.canvas_commands {
        destination := SDL.FRect{
            origin_x + f32(command.destination_x) / scale,
            origin_y + f32(command.destination_y) / scale,
            f32(command.destination_width) / scale,
            f32(command.destination_height) / scale,
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
        clip_left_f := origin_x + f32(command.clip_x) / scale
        clip_top_f := origin_y + f32(command.clip_y) / scale
        clip_right_f := origin_x + f32(command.clip_x + i32(command.clip_width)) / scale
        clip_bottom_f := origin_y + f32(command.clip_y + i32(command.clip_height)) / scale
        clip_left := c.int(math.floor(clip_left_f))
        clip_top := c.int(math.floor(clip_top_f))
        clip_right := c.int(math.ceil(clip_right_f))
        clip_bottom := c.int(math.ceil(clip_bottom_f))
        command_clip := SDL.Rect{clip_left, clip_top, clip_right - clip_left, clip_bottom - clip_top}
        clip: SDL.Rect
        if !SDL.GetRectIntersection(command_clip, pane_clip, &clip) {
            continue
        }
        clip = canvas_effective_clip(destination, clip, pane_clip)
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
    if app == nil || app.renderer == nil || font == nil || len(text) == 0 {
        return
    }
    surface := TTF.RenderText_Blended(font, cstring(raw_data(text)), c.size_t(len(text)), color)
    if surface == nil {
        return
    }
    defer SDL.DestroySurface(surface)
    texture := SDL.CreateTextureFromSurface(app.renderer, surface)
    if texture == nil {
        return
    }
    defer SDL.DestroyTexture(texture)
    scale := app.text_scale
    if !valid_canvas_scale(scale) {
        scale = 1
    }
    destination := SDL.FRect{
        x,
        y,
        f32(surface.w) / scale,
        f32(surface.h) / scale,
    }
    _ = SDL.RenderTexture(app.renderer, texture, nil, &destination)
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
    view.io_failed = true
    view.ui_dirty = true
    sync.mutex_unlock(&view.mutex)
}

observe_session :: proc(data: rawptr) {
    view := (^Session_View)(data)
    observer := connect_view_channel(view, view.observer_interrupt)
    if observer == nil do return
    view.observer = observer
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
            break // Explicit reconnect owns a fresh channel, never replay old input.
        }

        fresh_interaction: Interaction_State_Info
        if interaction_state(observer, &fresh_interaction) != 0 {
            publish_bridge_error(view, observer)
            notify_session_update()
            break
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
        snapshot_stream_closed := stream_closed(observer) != 0
        snapshot_child_exited := child_exited(observer) != 0
        snapshot_text_truncated := text_truncated(observer) != 0
        title_bytes: [1024]u8
        title_len := int(snapshot_title(observer, raw_data(title_bytes[:]), c.size_t(len(title_bytes))))
        progress := snapshot_progress(observer)

        transferred := snapshot_take_view(observer)
        sync.mutex_lock(&view.mutex)
        displaced := view.reusable_view
        view.reusable_view = transferred
        chrome_changed := view.revision == 0 || view.stream_closed != snapshot_stream_closed ||
                          view.child_exited != snapshot_child_exited || view.task_progress != progress ||
                          string(view.display_title[:view.display_title_len]) != string(title_bytes[:title_len])
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
        view.interaction_state = fresh_interaction
        view.interaction_state_valid = true
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
        view.stream_closed = snapshot_stream_closed
        view.child_exited = snapshot_child_exited
        view.text_truncated = snapshot_text_truncated
        copy(view.display_title[:title_len], title_bytes[:title_len])
        view.display_title_len = title_len
        view.task_progress = progress
        view.ui_dirty = view.ui_dirty || chrome_changed
        if !view.control_failed && !view.io_failed do view.error_len = 0
        validate_search_result_locked(view)
        sync.mutex_unlock(&view.mutex)
        if displaced != nil do view_destroy(displaced)
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
        view.history_generation += 1
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
    endpoint := session_endpoint(view)
    diagnostic: [160]u8
    count: c.size_t
    handle := create(desktop_io_runtime, view.search_interrupt, raw_data(endpoint), c.size_t(len(endpoint)),
                     raw_data(diagnostic[:]), c.size_t(len(diagnostic)), &count)
    view.search = handle
    if handle == nil {
        sync.mutex_lock(&view.mutex)
        view.search_failed = true
        view.ui_dirty = true
        view.search_pending = false
        view.search_state = .Error
        view.search_error_len = int(count)
        copy(view.search_error[:int(count)], diagnostic[:int(count)])
        sync.mutex_unlock(&view.mutex)
        notify_session_update()
        return
    }
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
        view.ui_dirty = true
        if !view.worker_stop && generation == view.search_generation {
            view.search_last_reverse = reverse
            view.search_last_complete = rc == 0 && result.complete != 0
            view.search_error_len = 0
            if rc != 0 {
                count := min(error_len, len(view.search_error))
                copy(view.search_error[:count], error_message[:count])
                view.search_error_len = count
                view.search_state = .Error
                view.search_failed = true
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
        if rc != 0 do break
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
    if view == nil || view.control == nil do return false
    sync.mutex_lock(&view.mutex)
    failed := view.search_failed
    sync.mutex_unlock(&view.mutex)
    if failed do return false
    if view.search_thread != nil do return true
    if len(session_endpoint(view)) == 0 do return false
    view.search_interrupt = interrupt_create()
    if view.search_interrupt == nil do return false
    view.search_thread = thread.create_and_start_with_data(rawptr(view), search_session, name = "howl-odin-search")
    if view.search_thread == nil {
        interrupt_destroy(view.search_interrupt)
        view.search_interrupt = nil
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
    text := len(message) != 0 ? message : "Session I/O failed without a diagnostic"
    count := min(len(text), len(view.error))
    for byte, index in text[:count] {
        view.error[index] = u8(byte)
    }
    view.error_len = count
    view.io_failed = true
    view.ui_dirty = true
    sync.mutex_unlock(&view.mutex)
}

session_lifecycle_state_values :: proc(
    revision: u64,
    error_len: int,
    control_present, stream_is_closed, child_has_exited: bool,
) -> Session_Lifecycle_State {
    if stream_is_closed || child_has_exited {
        return .Closed
    }
    if error_len != 0 || !control_present {
        return .Unavailable
    }
    if revision == 0 {
        return .Connecting
    }
    return .Active
}

session_lifecycle_state :: proc(view: ^Session_View) -> Session_Lifecycle_State {
    if view == nil {
        return .Unavailable
    }
    sync.mutex_lock(&view.mutex)
    if view.error_len == 0 && view.control_thread != nil && !view.control_connect_done {
        sync.mutex_unlock(&view.mutex)
        return .Connecting
    }
    state := session_lifecycle_state_values(
        view.revision,
        view.error_len,
        view.control != nil,
        view.stream_closed,
        view.child_exited,
    )
    sync.mutex_unlock(&view.mutex)
    return state
}

session_is_owned :: proc(view: ^Session_View) -> bool {
    return view != nil && view.ownership == .Owned
}

session_interactive :: proc(view: ^Session_View) -> bool {
    return session_lifecycle_state(view) == .Active
}

session_recoverable :: proc(view: ^Session_View) -> bool {
    state := session_lifecycle_state(view)
    return state == .Closed || state == .Unavailable
}

session_attached :: proc(view: ^Session_View) -> bool {
    return session_interactive(view)
}

copy_bridge_error :: proc(view: ^Session_View) {
    if view == nil do return
    sync.mutex_lock(&view.mutex)
    if view.error_len == 0 {
        message := "Input not admitted; nothing was replayed"
        copy(view.error[:], transmute([]u8)message)
        view.error_len = len(message)
        view.control_failed = true
    }
    sync.mutex_unlock(&view.mutex)
}

clear_selection_locked :: proc(view: ^Session_View) {
    view.selection_generation += 1
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
    view.history_generation += 1
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
    view.history_generation += 1
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
    requested_generation: u64,
) {
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    // A prepared older frame may be displayed, but cannot overwrite a newer
    // wheel/drag/search/return-to-LIVE intent while route I/O was outstanding.
    if requested_generation != view.history_generation do return
    if alternate_screen || history_offset == 0 || history_count == 0 {
        reset_history_locked(view)
        return
    }
    accepted := min(history_offset, history_count)
    if accepted == 0 {
        reset_history_locked(view)
        return
    }
    view.history_generation += 1
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
    view.history_generation += 1
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
    view.history_generation += 1
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

    view.history_generation += 1

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

displayed_alternate_screen :: proc(view: ^Session_View) -> bool {
    if view == nil {
        return false
    }
    if view.canvas != nil {
        return render_alternate_screen(view.canvas) != 0
    }
    sync.mutex_lock(&view.mutex)
    value := view.alternate_screen
    sync.mutex_unlock(&view.mutex)
    return value
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

allocate_session_view :: proc(owned_process: rawptr, ownership: Session_Ownership) -> ^Session_View {
    view := new(Session_View)
    if view == nil {
        return nil
    }
    view.ownership = ownership
    view.owned_process = owned_process
    if ownership == .Owned do view.size_control.mode = .Taking
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

create_session_view :: proc(endpoint: string, owned_process: rawptr, ownership: Session_Ownership) -> ^Session_View {
    view := allocate_session_view(owned_process, ownership)
    if view == nil do return nil
    if len(endpoint) == 0 || len(endpoint) >= len(view.endpoint) {
        publish_initial_error(view, "Session endpoint is empty or too long")
        return view
    }
    copy(view.endpoint[:len(endpoint)], transmute([]u8)endpoint)
    view.endpoint_len = len(endpoint)
    view.control_interrupt = interrupt_create()
    view.observer_interrupt = interrupt_create()
    if view.control_interrupt == nil || view.observer_interrupt == nil {
        publish_initial_error(view, "Session I/O cancellation allocation failed")
        return view
    }
    view.control_thread = thread.create_and_start_with_data(rawptr(view), control_session, name = "howl-odin-control")
    view.observer_thread = thread.create_and_start_with_data(rawptr(view), observe_session, name = "howl-odin-observe")
    if view.control_thread == nil || view.observer_thread == nil do publish_initial_error(view, "Session I/O worker creation failed")
    return view
}

create_error_session_view :: proc(message: string, ownership: Session_Ownership = .Attached) -> ^Session_View {
    view := allocate_session_view(rawptr(nil), ownership)
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
    sync.cond_signal(&view.control_cond)
    if view.control_interrupt != nil do _ = interrupt_cancel(view.control_interrupt)
    if view.observer_interrupt != nil do _ = interrupt_cancel(view.observer_interrupt)
    if view.search_interrupt != nil do _ = interrupt_cancel(view.search_interrupt)
    if view.control_thread != nil {
        thread.destroy(view.control_thread)
        view.control_thread = nil
    }
    if view.observer_thread != nil {
        thread.destroy(view.observer_thread)
        view.observer_thread = nil
    }
    if view.search_thread != nil {
        thread.destroy(view.search_thread)
        view.search_thread = nil
    }
    if view.search_interrupt != nil do interrupt_destroy(view.search_interrupt)
    if view.observer != nil {
        destroy(view.observer)
    }
    if view.search != nil {
        destroy(view.search)
    }
    if view.control_pending_handle != nil do destroy(view.control_pending_handle)
    if view.control_interrupt != nil do interrupt_destroy(view.control_interrupt)
    if view.observer_interrupt != nil do interrupt_destroy(view.observer_interrupt)
    for view.control_count > 0 {
        task, ok := control_queue_pop_locked(view)
        if ok && task.payload != nil do delete(task.payload)
    }
    if view.control_result.bytes != nil do delete(view.control_result.bytes)
    if view.clipboard_reply != nil do delete(view.clipboard_reply)
    if view.owned_process != nil {
        owned_session_destroy(view.owned_process)
    }
    if view.reusable_view != nil do view_destroy(view.reusable_view)
    delete(view.scratch)
    delete(view.text)
    free(view)
}

tab_pane_view :: proc(tab: ^Tab, pane_index: int) -> ^Session_View {
    if tab == nil || pane_index < 0 || pane_index >= len(tab.panes) {
        return nil
    }
    return tab.panes[pane_index]
}

active_session_view :: proc(app: ^App) -> ^Session_View {
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return nil
    }
    tab := &app.tabs[app.active_tab]
    return tab_pane_view(tab, tab.active_pane)
}

clear_all_search_results :: proc(app: ^App) {
    for index in 0..<app.tab_count {
        for view in app.tabs[index].panes {
            if view != nil do clear_search_result(view)
        }
    }
}

open_search :: proc(app: ^App) {
    clear_ime_preedit(app)
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
    clear_ime_preedit(app)
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

create_owned_profile_session_view :: proc(app: ^App, profile: ^Profile, profile_index: int) -> ^Session_View {
    if app == nil || profile == nil || profile.mode != .Launch {
        return create_error_session_view("Invalid launch profile", .Owned)
    }
    runtime_dir := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
    if len(runtime_dir) == 0 {
        view := create_error_session_view("Missing XDG_RUNTIME_DIR", .Owned)
        if view != nil do view.profile_index = profile_index
        return view
    }
    shell := profile_shell(profile)
    if len(shell) == 0 {
        shell = os.get_env("SHELL", context.temp_allocator)
    }
    if len(shell) == 0 {
        shell = "/bin/sh"
    }
    command := profile_command(profile)
    cwd := profile_cwd(profile)
    env_entries: [MAX_PROFILE_ENV]Profile_Env_Info
    for index in 0..<profile.env_count {
        source := &profile.env[index]
        name := profile_env_name(source)
        value := profile_env_value(source)
        env_entries[index] = Profile_Env_Info{
            name = raw_data(name),
            name_len = c.size_t(len(name)),
            value = raw_data(value),
            value_len = c.size_t(len(value)),
        }
    }
    identity := app.next_session_identity
    app.next_session_identity += 1
    diagnostic: [160]u8
    diagnostic_len: c.size_t
    owned := owned_session_create(
        desktop_io_runtime,
        raw_data(runtime_dir),
        c.size_t(len(runtime_dir)),
        raw_data(shell),
        c.size_t(len(shell)),
        raw_data(command),
        c.size_t(len(command)),
        raw_data(cwd),
        c.size_t(len(cwd)),
        raw_data(env_entries[:]),
        c.size_t(profile.env_count),
        OWNED_SESSION_ROWS,
        OWNED_SESSION_COLUMNS,
        identity,
        raw_data(diagnostic[:]),
        c.size_t(len(diagnostic)),
        &diagnostic_len,
    )
    if owned == nil {
        view := create_error_session_view(string(diagnostic[:int(diagnostic_len)]), .Owned)
        if view != nil {
            view.profile_index = profile_index
            view.profile_font_pixels = profile.font_pixels
        }
        return view
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
        view := create_error_session_view("owned_session_endpoint_failed", .Owned)
        if view != nil do view.profile_index = profile_index
        return view
    }
    endpoint := string(endpoint_storage[:int(endpoint_len)])
    view := create_session_view(endpoint, owned, .Owned)
    if view == nil {
        owned_session_destroy(owned)
        return nil
    }
    view.profile_index = profile_index
    view.profile_font_pixels = profile.font_pixels
    return view
}

create_owned_session_view :: proc(app: ^App) -> ^Session_View {
    return create_owned_profile_session_view(app, profile_at(app, 1), 1)
}

interaction_mouse_tracking_enabled :: proc(state: Interaction_State_Info) -> bool {
    return state.mouse_tracking != 0
}

interaction_alternate_scroll :: proc(state: Interaction_State_Info) -> bool {
    return state.flags & INTERACTION_ALT_SCROLL != 0
}

interaction_focus_reporting :: proc(state: Interaction_State_Info) -> bool {
    return state.flags & INTERACTION_FOCUS_REPORTING != 0
}

route_desktop_primary_pointer :: proc(
    history_is_active, force_selection, state_known, mouse_tracking_enabled: bool,
) -> Desktop_Primary_Pointer_Route {
    if history_is_active || force_selection {
        return .Local_Selection
    }
    if !state_known {
        return .Interaction_State
    }
    return mouse_tracking_enabled ? .Terminal_Mouse : .Local_Selection
}

route_desktop_wheel :: proc(
    history_is_active, force_history, state_known, mouse_tracking_enabled,
    alternate_screen, alternate_scroll: bool,
) -> Desktop_Wheel_Route {
    if history_is_active || force_history {
        return .History
    }
    if !state_known {
        return .Interaction_State
    }
    if mouse_tracking_enabled {
        return .Terminal_Mouse
    }
    if !alternate_screen {
        return .History
    }
    return alternate_scroll ? .Alternate_Scroll : .Ignore
}

current_interaction_state :: proc(view: ^Session_View) -> (state: Interaction_State_Info, ok: bool) {
    if view == nil || view.control == nil do return {}, false
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    return view.interaction_state, view.interaction_state_valid
}

terminal_pointer_location :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    clamp_to_surface := false,
) -> (row: i32, column: u16, pixel_x, pixel_y: u32, ok: bool) {
    if view == nil || view.canvas == nil {
        return 0, 0, 0, 0, false
    }
    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 || view.canvas_surface_width == 0 || view.canvas_surface_height == 0 {
        return 0, 0, 0, 0, false
    }
    scale := canvas_scale_value(view)
    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    right := origin_x + canvas_logical_extent(view, view.canvas_surface_width)
    bottom := origin_y + canvas_logical_extent(view, view.canvas_surface_height)
    local_x := x
    local_y := y
    if clamp_to_surface {
        local_x = clamp(local_x, origin_x, max(origin_x, right - 1 / scale))
        local_y = clamp(local_y, origin_y, max(origin_y, bottom - 1 / scale))
    } else if local_x < origin_x || local_x >= right || local_y < origin_y || local_y >= bottom {
        return 0, 0, 0, 0, false
    }
    px := int(math.floor((local_x - origin_x) * scale))
    py := int(math.floor((local_y - origin_y) * scale))
    columns := int(view.canvas_surface_width / cell_width)
    rows := int(view.canvas_surface_height / cell_height)
    col := px / int(cell_width)
    r := py / int(cell_height)
    if col < 0 || col >= columns || r < 0 || r >= rows {
        return 0, 0, 0, 0, false
    }
    return i32(r), u16(col), u32(px), u32(py), true
}

bridge_mouse_button :: proc(button: u8) -> (mapped: Bridge_Mouse_Button, bit: u8, ok: bool) {
    switch button {
    case SDL.BUTTON_LEFT:   return .Left, 1, true
    case SDL.BUTTON_MIDDLE: return .Middle, 2, true
    case SDL.BUTTON_RIGHT:  return .Right, 4, true
    case:                   return .None, 0, false
    }
}

sdl_mouse_buttons_down :: proc(state: SDL.MouseButtonFlags) -> u8 {
    result: u8
    if .LEFT in state do result |= 1
    if .MIDDLE in state do result |= 2
    if .RIGHT in state do result |= 4
    return result
}

send_terminal_mouse :: proc(
    view: ^Session_View,
    kind: Bridge_Mouse_Kind,
    button: Bridge_Mouse_Button,
    modifiers, buttons_down: u8,
    row: i32,
    column: u16,
    pixel_x, pixel_y: u32,
) -> bool {
    if view == nil || view.control == nil {
        return false
    }
    if queue_mouse(
        view,
        u8(kind),
        u8(button),
        modifiers,
        buttons_down,
        row,
        column,
        1,
        pixel_x,
        pixel_y,
    ) != 0 {
        copy_bridge_error(view)
        return false
    }
    return true
}

terminal_mouse_press :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    button: u8,
    modifiers: u8,
) -> bool {
    mapped, bit, button_ok := bridge_mouse_button(button)
    if !button_ok {
        return false
    }
    row, column, pixel_x, pixel_y, located := terminal_pointer_location(view, pane, x, y)
    if !located {
        return false
    }
    sync.mutex_lock(&view.mutex)
    buttons := view.terminal_mouse_buttons | bit
    sync.mutex_unlock(&view.mutex)
    if !send_terminal_mouse(view, .Press, mapped, modifiers, buttons, row, column, pixel_x, pixel_y) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    view.terminal_mouse_buttons = buttons
    view.terminal_mouse_captured = true
    view.terminal_mouse_last_row = row
    view.terminal_mouse_last_column = column
    view.terminal_mouse_last_pixel_x = pixel_x
    view.terminal_mouse_last_pixel_y = pixel_y
    sync.mutex_unlock(&view.mutex)
    _ = SDL.CaptureMouse(true)
    return true
}

terminal_mouse_release :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    button: u8,
    modifiers: u8,
) -> bool {
    mapped, bit, button_ok := bridge_mouse_button(button)
    if !button_ok || view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    before := view.terminal_mouse_buttons
    last_row := view.terminal_mouse_last_row
    last_column := view.terminal_mouse_last_column
    last_pixel_x := view.terminal_mouse_last_pixel_x
    last_pixel_y := view.terminal_mouse_last_pixel_y
    sync.mutex_unlock(&view.mutex)
    if before & bit == 0 {
        return false
    }
    row, column, pixel_x, pixel_y, located := terminal_pointer_location(view, pane, x, y, true)
    if !located {
        row, column, pixel_x, pixel_y = last_row, last_column, last_pixel_x, last_pixel_y
    }
    after := before & ~bit
    _ = send_terminal_mouse(view, .Release, mapped, modifiers, after, row, column, pixel_x, pixel_y)
    sync.mutex_lock(&view.mutex)
    view.terminal_mouse_buttons = after
    view.terminal_mouse_captured = after != 0
    view.terminal_mouse_last_row = row
    view.terminal_mouse_last_column = column
    view.terminal_mouse_last_pixel_x = pixel_x
    view.terminal_mouse_last_pixel_y = pixel_y
    sync.mutex_unlock(&view.mutex)
    if after == 0 {
        _ = SDL.CaptureMouse(false)
    }
    return true
}

terminal_mouse_move :: proc(
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    modifiers: u8,
    captured: bool,
) -> bool {
    if view == nil {
        return false
    }
    row, column, pixel_x, pixel_y, located := terminal_pointer_location(view, pane, x, y, captured)
    if !located {
        return false
    }
    sync.mutex_lock(&view.mutex)
    buttons := view.terminal_mouse_buttons
    sync.mutex_unlock(&view.mutex)
    if !send_terminal_mouse(view, .Move, .None, modifiers, buttons, row, column, pixel_x, pixel_y) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    view.terminal_mouse_last_row = row
    view.terminal_mouse_last_column = column
    view.terminal_mouse_last_pixel_x = pixel_x
    view.terminal_mouse_last_pixel_y = pixel_y
    sync.mutex_unlock(&view.mutex)
    return true
}

finish_terminal_mouse_capture :: proc(view: ^Session_View, modifiers: u8 = 0) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    buttons := view.terminal_mouse_buttons
    row := view.terminal_mouse_last_row
    column := view.terminal_mouse_last_column
    pixel_x := view.terminal_mouse_last_pixel_x
    pixel_y := view.terminal_mouse_last_pixel_y
    view.terminal_mouse_buttons = 0
    view.terminal_mouse_captured = false
    sync.mutex_unlock(&view.mutex)
    if buttons == 0 {
        return false
    }
    held := buttons
    if held & 1 != 0 {
        held &= ~u8(1)
        _ = send_terminal_mouse(view, .Release, .Left, modifiers, held, row, column, pixel_x, pixel_y)
    }
    if held & 2 != 0 {
        held &= ~u8(2)
        _ = send_terminal_mouse(view, .Release, .Middle, modifiers, held, row, column, pixel_x, pixel_y)
    }
    if held & 4 != 0 {
        held &= ~u8(4)
        _ = send_terminal_mouse(view, .Release, .Right, modifiers, held, row, column, pixel_x, pixel_y)
    }
    _ = SDL.CaptureMouse(false)
    return true
}

send_semantic_focus :: proc(view: ^Session_View, focused: bool) -> bool {
    if view == nil || view.control == nil {
        return false
    }
    if queue_focus(view, u8(focused ? Bridge_Focus.In : Bridge_Focus.Out)) != 0 {
        copy_bridge_error(view)
        return false
    }
    return true
}

send_named_key_cycle :: proc(view: ^Session_View, key: Bridge_Key) -> bool {
    if view == nil || view.control == nil {
        return false
    }
    if queue_named_key(view, u8(key), u8(Bridge_Key_Action.Press), 0) != 0 {
        copy_bridge_error(view)
        return false
    }
    if queue_named_key(view, u8(key), u8(Bridge_Key_Action.Release), 0) != 0 {
        copy_bridge_error(view)
        return false
    }
    return true
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
    case SDL.K_PAGEUP:       return .Page_Up, true
    case SDL.K_PAGEDOWN:     return .Page_Down, true
    case SDL.K_CAPSLOCK:     return .Caps_Lock, true
    case SDL.K_NUMLOCKCLEAR: return .Num_Lock, true
    case SDL.K_F1:           return .F1, true
    case SDL.K_F2:           return .F2, true
    case SDL.K_F3:           return .F3, true
    case SDL.K_F4:           return .F4, true
    case SDL.K_F5:           return .F5, true
    case SDL.K_F6:           return .F6, true
    case SDL.K_F7:           return .F7, true
    case SDL.K_F8:           return .F8, true
    case SDL.K_F9:           return .F9, true
    case SDL.K_F10:          return .F10, true
    case SDL.K_F11:          return .F11, true
    case SDL.K_F12:          return .F12, true
    case SDL.K_KP_0:         return .Keypad_0, true
    case SDL.K_KP_1:         return .Keypad_1, true
    case SDL.K_KP_2:         return .Keypad_2, true
    case SDL.K_KP_3:         return .Keypad_3, true
    case SDL.K_KP_4:         return .Keypad_4, true
    case SDL.K_KP_5:         return .Keypad_5, true
    case SDL.K_KP_6:         return .Keypad_6, true
    case SDL.K_KP_7:         return .Keypad_7, true
    case SDL.K_KP_8:         return .Keypad_8, true
    case SDL.K_KP_9:         return .Keypad_9, true
    case SDL.K_KP_DECIMAL:   return .Keypad_Decimal, true
    case SDL.K_KP_PLUS:      return .Keypad_Add, true
    case SDL.K_KP_MINUS:     return .Keypad_Subtract, true
    case SDL.K_KP_MULTIPLY:  return .Keypad_Multiply, true
    case SDL.K_KP_DIVIDE:    return .Keypad_Divide, true
    case SDL.K_KP_COMMA:     return .Keypad_Separator, true
    case SDL.K_KP_EQUALS:    return .Keypad_Equal, true
    case SDL.K_KP_ENTER:     return .Keypad_Enter, true
    case:                     return .Enter, false
    }
}

send_bridge_key :: proc(app: ^App, event: ^SDL.Event) -> bool {
    view := active_session_view(app)
    if view == nil || !active_tab_is_session(app) || app.profile_menu_open || app.palette_open || app.settings_open {
        return false
    }
    key, ok := named_bridge_key(event.key.key)
    if !ok {
        return false
    }
    if view.control == nil || !session_interactive(view) {
        return true
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
    result := queue_named_key(
        view,
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
    return {0, HEADER_HEIGHT, max(f32(0), width), max(f32(0), height - HEADER_HEIGHT)}
}

PANE_GAP :: f32(4)

Pane_Layout_Entry :: struct {
    pane_index: int,
    rect: SDL.FRect,
}

Pane_Layout_Divider :: struct {
    node: ^Pane_Node,
    rect: SDL.FRect,
    container: SDL.FRect,
}

Pane_Layout :: struct {
    entries: [MAX_PANES_PER_TAB]Pane_Layout_Entry,
    entry_count: int,
    dividers: [MAX_PANES_PER_TAB - 1]Pane_Layout_Divider,
    divider_count: int,
}

new_pane_leaf :: proc(pane_index: int, parent: ^Pane_Node = nil) -> ^Pane_Node {
    node := new(Pane_Node)
    if node == nil {
        return nil
    }
    node^ = Pane_Node{kind = .Leaf, pane_index = pane_index, ratio = 0.5, parent = parent}
    return node
}

destroy_pane_nodes :: proc(node: ^Pane_Node) {
    if node == nil {
        return
    }
    if node.kind == .Split {
        destroy_pane_nodes(node.first)
        destroy_pane_nodes(node.second)
    }
    free(node)
}

pane_leaf_for_index :: proc(node: ^Pane_Node, pane_index: int) -> ^Pane_Node {
    if node == nil {
        return nil
    }
    if node.kind == .Leaf {
        return node.pane_index == pane_index ? node : nil
    }
    if found := pane_leaf_for_index(node.first, pane_index); found != nil {
        return found
    }
    return pane_leaf_for_index(node.second, pane_index)
}

first_pane_leaf :: proc(node: ^Pane_Node) -> ^Pane_Node {
    current := node
    for current != nil && current.kind == .Split {
        current = current.first
    }
    return current
}

free_pane_slot :: proc(tab: ^Tab) -> int {
    if tab == nil {
        return -1
    }
    for view, index in tab.panes {
        if view == nil {
            return index
        }
    }
    return -1
}

layout_pane_node :: proc(node: ^Pane_Node, rect: SDL.FRect, layout: ^Pane_Layout) {
    if node == nil || layout == nil || rect.w <= 0 || rect.h <= 0 {
        return
    }
    if node.kind == .Leaf {
        if layout.entry_count < len(layout.entries) {
            layout.entries[layout.entry_count] = Pane_Layout_Entry{pane_index = node.pane_index, rect = rect}
            layout.entry_count += 1
        }
        return
    }

    ratio := clamp(node.ratio, f32(0.1), f32(0.9))
    if node.orientation == .Vertical {
        first_width := max(f32(0), (rect.w - PANE_GAP) * ratio)
        first := SDL.FRect{rect.x, rect.y, first_width, rect.h}
        second := SDL.FRect{rect.x + first_width + PANE_GAP, rect.y, max(f32(0), rect.w - first_width - PANE_GAP), rect.h}
        if layout.divider_count < len(layout.dividers) {
            layout.dividers[layout.divider_count] = Pane_Layout_Divider{
                node = node,
                rect = SDL.FRect{first.x + first.w, rect.y, PANE_GAP, rect.h},
                container = rect,
            }
            layout.divider_count += 1
        }
        layout_pane_node(node.first, first, layout)
        layout_pane_node(node.second, second, layout)
        return
    }

    first_height := max(f32(0), (rect.h - PANE_GAP) * ratio)
    first := SDL.FRect{rect.x, rect.y, rect.w, first_height}
    second := SDL.FRect{rect.x, rect.y + first_height + PANE_GAP, rect.w, max(f32(0), rect.h - first_height - PANE_GAP)}
    if layout.divider_count < len(layout.dividers) {
        layout.dividers[layout.divider_count] = Pane_Layout_Divider{
            node = node,
            rect = SDL.FRect{rect.x, first.y + first.h, rect.w, PANE_GAP},
            container = rect,
        }
        layout.divider_count += 1
    }
    layout_pane_node(node.first, first, layout)
    layout_pane_node(node.second, second, layout)
}

pane_layout :: proc(tab: ^Tab, inset: SDL.FRect) -> Pane_Layout {
    layout: Pane_Layout
    if tab == nil {
        return layout
    }
    if tab.zoomed {
        if tab_pane_view(tab, tab.active_pane) != nil {
            layout.entries[0] = Pane_Layout_Entry{pane_index = tab.active_pane, rect = inset}
            layout.entry_count = 1
        }
        return layout
    }
    layout_pane_node(tab.root, inset, &layout)
    return layout
}

pane_rect_from_layout :: proc(layout: ^Pane_Layout, pane_index: int) -> (SDL.FRect, bool) {
    if layout == nil {
        return {}, false
    }
    for index in 0..<layout.entry_count {
        if layout.entries[index].pane_index == pane_index {
            return layout.entries[index].rect, true
        }
    }
    return {}, false
}

rect_center :: proc(rect: SDL.FRect) -> (x, y: f32) {
    return rect.x + rect.w / 2, rect.y + rect.h / 2
}

pane_neighbor_index :: proc(
    layout: ^Pane_Layout,
    pane_index: int,
    direction: Pane_Direction,
) -> (neighbor: int, ok: bool) {
    current, current_ok := pane_rect_from_layout(layout, pane_index)
    if !current_ok {
        return 0, false
    }
    current_x, current_y := rect_center(current)
    best_score := f32(1.0e30)
    best := -1
    for index in 0..<layout.entry_count {
        candidate := layout.entries[index]
        if candidate.pane_index == pane_index {
            continue
        }
        x, y := rect_center(candidate.rect)
        primary, secondary: f32
        eligible := false
        switch direction {
        case .Left:
            eligible = candidate.rect.x + candidate.rect.w <= current.x + 0.01
            primary = current.x - (candidate.rect.x + candidate.rect.w)
            secondary = abs(current_y - y)
        case .Right:
            eligible = candidate.rect.x >= current.x + current.w - 0.01
            primary = candidate.rect.x - (current.x + current.w)
            secondary = abs(current_y - y)
        case .Up:
            eligible = candidate.rect.y + candidate.rect.h <= current.y + 0.01
            primary = current.y - (candidate.rect.y + candidate.rect.h)
            secondary = abs(current_x - x)
        case .Down:
            eligible = candidate.rect.y >= current.y + current.h - 0.01
            primary = candidate.rect.y - (current.y + current.h)
            secondary = abs(current_x - x)
        }
        if !eligible {
            continue
        }
        score := primary * 10000 + secondary
        if score < best_score {
            best_score = score
            best = candidate.pane_index
        }
    }
    return best, best >= 0
}

focus_pane_direction :: proc(tab: ^Tab, inset: SDL.FRect, direction: Pane_Direction) -> bool {
    if tab == nil || tab.zoomed {
        return false
    }
    layout := pane_layout(tab, inset)
    neighbor, ok := pane_neighbor_index(&layout, tab.active_pane, direction)
    if !ok || tab_pane_view(tab, neighbor) == nil {
        return false
    }
    tab.active_pane = neighbor
    return true
}

resize_active_divider :: proc(tab: ^Tab, direction: Pane_Direction, step: f32 = 0.05) -> bool {
    if tab == nil || tab.zoomed || step <= 0 {
        return false
    }
    leaf := pane_leaf_for_index(tab.root, tab.active_pane)
    if leaf == nil {
        return false
    }
    wanted := (direction == .Left || direction == .Right) ? Pane_Split_Orientation.Vertical : Pane_Split_Orientation.Horizontal
    node := leaf.parent
    for node != nil && (node.kind != .Split || node.orientation != wanted) {
        node = node.parent
    }
    if node == nil {
        return false
    }
    delta := (direction == .Left || direction == .Up) ? -step : step
    next := clamp(node.ratio + delta, f32(0.15), f32(0.85))
    if abs(next - node.ratio) < 0.0001 {
        return false
    }
    node.ratio = next
    return true
}

swap_active_pane_direction :: proc(tab: ^Tab, inset: SDL.FRect, direction: Pane_Direction) -> bool {
    if tab == nil || tab.zoomed {
        return false
    }
    layout := pane_layout(tab, inset)
    neighbor, ok := pane_neighbor_index(&layout, tab.active_pane, direction)
    if !ok || tab_pane_view(tab, neighbor) == nil {
        return false
    }
    active := tab.active_pane
    tab.panes[active], tab.panes[neighbor] = tab.panes[neighbor], tab.panes[active]
    tab.active_pane = neighbor
    return true
}

toggle_pane_zoom :: proc(tab: ^Tab) -> bool {
    if tab == nil || tab.pane_count <= 1 {
        if tab != nil do tab.zoomed = false
        return false
    }
    tab.zoomed = !tab.zoomed
    return true
}

pane_divider_hit_rect :: proc(divider: Pane_Layout_Divider) -> SDL.FRect {
    if divider.node != nil && divider.node.orientation == .Horizontal {
        return {divider.rect.x, divider.rect.y - 5, divider.rect.w, divider.rect.h + 10}
    }
    return {divider.rect.x - 5, divider.rect.y, divider.rect.w + 10, divider.rect.h}
}

pane_divider_ratio_for_pointer :: proc(
    orientation: Pane_Split_Orientation,
    container: SDL.FRect,
    x, y: f32,
) -> f32 {
    if orientation == .Vertical {
        denominator := max(f32(1), container.w - PANE_GAP)
        return clamp((x - container.x) / denominator, f32(0.15), f32(0.85))
    }
    denominator := max(f32(1), container.h - PANE_GAP)
    return clamp((y - container.y) / denominator, f32(0.15), f32(0.85))
}

finish_pane_resize_drag :: proc(app: ^App) -> bool {
    if app == nil || app.pane_resize_node == nil {
        return false
    }
    app.pane_resize_node = nil
    app.pane_resize_tab = -1
    _ = SDL.CaptureMouse(false)
    return true
}

update_pane_resize_drag :: proc(app: ^App, x, y, width, height: f32) -> bool {
    if app == nil || app.pane_resize_node == nil || app.pane_resize_tab != app.active_tab ||
       app.active_tab < 0 || app.active_tab >= app.tab_count {
        return false
    }
    tab := &app.tabs[app.active_tab]
    layout := pane_layout(tab, terminal_inset(width, height))
    for index in 0..<layout.divider_count {
        divider := layout.dividers[index]
        if divider.node != app.pane_resize_node {
            continue
        }
        next := pane_divider_ratio_for_pointer(divider.node.orientation, divider.container, x, y)
        if abs(next - divider.node.ratio) < 0.0001 {
            return false
        }
        divider.node.ratio = next
        return true
    }
    _ = finish_pane_resize_drag(app)
    return false
}

begin_pane_resize_drag :: proc(app: ^App, x, y, width, height: f32) -> bool {
    if app == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return false
    }
    tab := &app.tabs[app.active_tab]
    if tab.zoomed || tab.pane_count <= 1 {
        return false
    }
    layout := pane_layout(tab, terminal_inset(width, height))
    for index in 0..<layout.divider_count {
        divider := layout.dividers[index]
        if !inside(x, y, pane_divider_hit_rect(divider)) {
            continue
        }
        app.pane_resize_node = divider.node
        app.pane_resize_tab = app.active_tab
        // SDL/Wayland already auto-captures active button drags. Explicit capture
        // is a best-effort extension for outside-window delivery, not admission
        // to the gesture itself; focus loss/window close still terminate state.
        _ = SDL.CaptureMouse(true)
        _ = update_pane_resize_drag(app, x, y, width, height)
        return true
    }
    return false
}

split_pane_slot :: proc(
    tab: ^Tab,
    pane_index: int,
    view: ^Session_View,
    orientation: Pane_Split_Orientation,
) -> (new_index: int, ok: bool) {
    if tab == nil || view == nil || tab.pane_count >= MAX_PANES_PER_TAB {
        return -1, false
    }
    leaf := pane_leaf_for_index(tab.root, pane_index)
    slot := free_pane_slot(tab)
    if leaf == nil || slot < 0 {
        return -1, false
    }
    first := new_pane_leaf(pane_index, leaf)
    if first == nil {
        return -1, false
    }
    second := new_pane_leaf(slot, leaf)
    if second == nil {
        free(first)
        return -1, false
    }
    old_parent := leaf.parent
    leaf^ = Pane_Node{
        kind = .Split,
        pane_index = -1,
        orientation = orientation,
        ratio = 0.5,
        parent = old_parent,
        first = first,
        second = second,
    }
    first.parent = leaf
    second.parent = leaf
    tab.panes[slot] = view
    tab.pane_count += 1
    tab.active_pane = slot
    return slot, true
}

remove_pane_slot :: proc(tab: ^Tab, pane_index: int) -> (removed: ^Session_View, ok: bool) {
    if tab == nil || tab.pane_count <= 1 || pane_index < 0 || pane_index >= len(tab.panes) {
        return nil, false
    }
    leaf := pane_leaf_for_index(tab.root, pane_index)
    if leaf == nil || leaf.parent == nil {
        return nil, false
    }
    parent := leaf.parent
    sibling := parent.first == leaf ? parent.second : parent.first
    if sibling == nil {
        return nil, false
    }
    grandparent := parent.parent
    promoted := sibling^
    parent^ = promoted
    parent.parent = grandparent
    if parent.first != nil do parent.first.parent = parent
    if parent.second != nil do parent.second.parent = parent

    removed = tab.panes[pane_index]
    tab.panes[pane_index] = nil
    tab.pane_count -= 1
    free(leaf)
    free(sibling)

    survivor := first_pane_leaf(parent)
    tab.active_pane = survivor != nil ? survivor.pane_index : 0
    return removed, true
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
    layout := pane_layout(tab, inset)
    for index in 0..<layout.entry_count {
        entry := layout.entries[index]
        if inside(x, y, entry.rect) {
            view = tab_pane_view(tab, entry.pane_index)
            return view, entry.pane_index, view != nil
        }
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
    layout := pane_layout(&app.tabs[app.active_tab], terminal_inset(width, height))
    return pane_rect_from_layout(&layout, pane_index)
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
    scale := canvas_scale_value(view)
    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    right := origin_x + canvas_logical_extent(view, view.canvas_surface_width)
    bottom := origin_y + canvas_logical_extent(view, view.canvas_surface_height)
    local_x := x
    local_y := y
    if clamp_to_surface {
        local_x = clamp(local_x, origin_x, max(origin_x, right - 1 / scale))
        local_y = clamp(local_y, origin_y, max(origin_y, bottom - 1 / scale))
    } else if local_x < origin_x || local_x >= right || local_y < origin_y || local_y >= bottom {
        return 0, 0, false
    }
    selected_column := int(math.floor((local_x - origin_x) * scale)) / int(cell_width)
    selected_row := int(math.floor((local_y - origin_y) * scale)) / int(cell_height)
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

apply_selection_range :: proc(view: ^Session_View, info: Selection_Range_Info) -> bool {
    if view == nil {
        return false
    }
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    clear_selection_locked(view)
    if info.found == 0 || info.columns == 0 || info.start_column >= info.columns ||
       info.end_column >= info.columns || info.alternate_screen > 1 {
        return false
    }
    view.selection_active = true
    view.selection_dragging = false
    view.selection_anchor_row = info.start_row
    view.selection_anchor_column = info.start_column
    view.selection_focus_row = info.end_row
    view.selection_focus_column = info.end_column
    view.selection_columns = info.columns
    view.selection_alternate_screen = info.alternate_screen != 0
    return true
}

expand_selection_at :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    x, y: f32,
    kind: u8,
) -> bool {
    if view == nil || view.control == nil || view.canvas == nil {
        return false
    }
    stable_row, column, columns, alternate, hit := selection_stable_point_at(
        app,
        view,
        pane,
        x,
        y,
    )
    if !hit {
        clear_selection(view)
        return true
    }
    sync.mutex_lock(&view.mutex)
    view.selection_generation += 1
    generation := view.selection_generation
    sync.mutex_unlock(&view.mutex)
    _ = queue_control(view, {kind = .Expand, action = kind, history = render_history_offset(view.canvas),
                            row = stable_row, column = column, columns = columns,
                            alternate = alternate ? u8(1) : u8(0), generation = generation})
    return true
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
    view.selection_generation += 1
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
        _ = extend_selection_focus_locked(view, row, column)
        sync.mutex_unlock(&view.mutex)
        return true
    }
    sync.mutex_unlock(&view.mutex)
    return false
}

// Moving the selected endpoint retires the old visual intent, but not an explicit
// Copy request already issued for that earlier range.
extend_selection_focus_locked :: proc(view: ^Session_View, row: i32, column: u16) -> bool {
    if view.selection_focus_row == row && view.selection_focus_column == column do return false
    view.selection_generation += 1
    view.selection_focus_row = row
    view.selection_focus_column = column
    return true
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
    scale := canvas_scale_value(view)
    surface_top := terminal_content_rect(pane).y
    surface_bottom := surface_top + canvas_logical_extent(view, view.canvas_surface_height)
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
        f32(cell_height) / scale,
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

copy_selection_to_clipboard :: proc(app: ^App, view: ^Session_View) -> bool {
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
    generation := view.selection_generation
    app.clipboard_request += 1
    request := app.clipboard_request
    view.copy_pending = true
    view.copy_pending_request = request
    sync.mutex_unlock(&view.mutex)
    result := queue_control(view, {kind = .Extract, row = anchor_row, column = anchor_column,
                                end_row = focus_row, end_column = focus_column, columns = selected_columns,
                                alternate = selected_alternate ? u8(1) : u8(0), generation = generation, request = request})
    if result != 0 {
        sync.mutex_lock(&view.mutex)
        view.copy_pending = false
        sync.mutex_unlock(&view.mutex)
    }
    return result == 0
}

paste_clipboard :: proc(view: ^Session_View) -> bool {
    if view == nil || view.control == nil || !session_interactive(view) {
        return false
    }
    sync.mutex_lock(&view.mutex)
    pending := view.copy_pending
    request := view.copy_pending_request
    sync.mutex_unlock(&view.mutex)
    if pending {
        // Preserve the copy's exact selection intent until its queued result
        // reaches the clipboard. Successful Copy will clear it normally.
        _ = return_history_live_navigation(view)
        return queue_control(view, {kind = .Clipboard, request = request}) == 0
    }
    if !SDL.HasClipboardText() do return false
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
    if queue_text(view, raw_data(text), c.size_t(len(text)), true) != 0 {
        copy_bridge_error(view)
        return false
    }
    return true
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

    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    scale := canvas_scale_value(view)
    pane_clip := SDL.Rect{c.int(pane.x), c.int(pane.y), c.int(pane.w), c.int(pane.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &pane_clip)
    defer {
        _ = SDL.SetRenderClipRect(app.renderer, nil)
    }
    color := SDL.Color{palette.accent[0], palette.accent[1], palette.accent[2], 72}
    for viewport_row in 0..<int(rows) {
        first, last: u16
        if render_selection_span(
            view.canvas, anchor_row, anchor_column, focus_row, focus_column,
            selected_columns, selected_alternate ? 1 : 0, u16(viewport_row), &first, &last,
        ) == 0 {
            continue
        }
        rect := SDL.FRect{
            origin_x + f32(u32(first) * u32(cell_width)) / scale,
            origin_y + f32(viewport_row * int(cell_height)) / scale,
            f32(u32(last - first + 1) * u32(cell_width)) / scale,
            f32(cell_height) / scale,
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

    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    scale := canvas_scale_value(view)
    rect := SDL.FRect{
        origin_x + f32(result.start_column * cell_width) / scale,
        origin_y + f32(viewport_row * i64(cell_height)) / scale,
        f32((result.end_column - result.start_column + 1) * cell_width) / scale,
        f32(cell_height) / scale,
    }
    fill := palette.accent
    fill[3] = 62
    draw_fill(app.renderer, rect, fill)
    edge := palette.accent
    edge[3] = 180
    draw_outline(app.renderer, rect, edge)
}

tab_width_for_count :: proc(count: int, width: f32, custom := true) -> f32 {
    if width <= 0 || count <= 0 do return TAB_WIDTH
    right := header_settings_rect(width, custom).x
    available := max(f32(0), right - TAB_X - 76 - 32)
    return max(f32(16), min(TAB_WIDTH, available / f32(count) - TAB_GAP))
}

tab_controls :: proc(tab_count: int, width: f32, custom := true) -> (plus, menu, settings: SDL.FRect) {
    controls_x := TAB_X + f32(tab_count) * (tab_width_for_count(tab_count, width, custom) + TAB_GAP)
    plus = {controls_x, 7, 34, 32}
    menu = {controls_x + 38, 7, 34, 32}
    settings = header_settings_rect(width, custom)
    return
}

TAB_X :: f32(8)
TAB_WIDTH :: f32(162)
TAB_GAP :: f32(4)
TAB_STEP :: f32(TAB_WIDTH + TAB_GAP)

move_tab :: proc(app: ^App, from, to: int) -> bool {
    if app == nil || from < 0 || to < 0 || from >= app.tab_count || to >= app.tab_count || from == to {
        return false
    }
    moving := app.tabs[from]
    if from < to {
        for index in from..<to {
            app.tabs[index] = app.tabs[index + 1]
        }
    } else {
        index := from
        for index > to {
            app.tabs[index] = app.tabs[index - 1]
            index -= 1
        }
    }
    app.tabs[to] = moving

    active := app.active_tab
    if active == from {
        app.active_tab = to
    } else if from < active && active <= to {
        app.active_tab -= 1
    } else if to <= active && active < from {
        app.active_tab += 1
    }
    return true
}

select_tab_index :: proc(app: ^App, index: int) -> bool {
    if app == nil || index < 0 || index >= app.tab_count || index == app.active_tab {
        return false
    }
    _ = finish_pane_resize_drag(app)
    clear_ime_preedit(app)
    if app.search_open do close_search(app)
    app.active_tab = index
    return true
}

tab_rect_for_index :: proc(index: int, count := 1, width := f32(0), custom := true) -> SDL.FRect {
    tab_width := tab_width_for_count(count, width, custom)
    return {TAB_X + f32(index) * (tab_width + TAB_GAP), 7, tab_width, 32}
}

tab_close_rect_for_index :: proc(index: int, count := 1, width := f32(0), custom := true) -> SDL.FRect {
    rect := tab_rect_for_index(index, count, width, custom)
    if count <= 1 || rect.w < 96 do return {}
    return {rect.x + rect.w - 30, rect.y, 30, rect.h}
}

tab_index_at :: proc(x, y: f32, count: int, width := f32(0), custom := true) -> (int, bool) {
    if count <= 0 || y < 7 || y >= 39 {
        return 0, false
    }
    for index in 0..<count {
        if inside(x, y, tab_rect_for_index(index, count, width, custom)) {
            return index, true
        }
    }
    return 0, false
}

tab_reorder_target :: proc(x: f32, count: int, width := f32(0), custom := true) -> int {
    if count <= 1 {
        return 0
    }
    step := tab_width_for_count(count, width, custom) + TAB_GAP
    value := int((x - TAB_X + step / 2) / step)
    return clamp(value, 0, count - 1)
}

finish_tab_drag :: proc(app: ^App) -> bool {
    if app == nil || !app.tab_dragging {
        return false
    }
    app.tab_dragging = false
    app.tab_drag_index = -1
    app.tab_drag_x = 0
    app.tab_drag_grab_x = 0
    _ = SDL.CaptureMouse(false)
    return true
}

begin_tab_drag :: proc(app: ^App, index: int, pointer_x: f32) -> bool {
    if app == nil || index < 0 || index >= app.tab_count {
        return false
    }
    _ = finish_pane_resize_drag(app)
    clear_ime_preedit(app)
    if app.search_open do close_search(app)
    app.active_tab = index
    app.tab_dragging = true
    app.tab_drag_index = index
    rect := tab_rect_for_index(index, app.tab_count, window_logical_width(app), app.client_chrome)
    app.tab_drag_x = rect.x
    app.tab_drag_grab_x = clamp(pointer_x - rect.x, f32(0), rect.w)
    _ = SDL.CaptureMouse(true)
    return true
}

// Follow the original grab point using the real chip, not a captured texture.
// Slot order stays canonical and changes only at its existing midpoint boundary.
tab_drag_rect :: proc(app: ^App, width: f32) -> SDL.FRect {
    if app == nil || !app.tab_dragging || app.tab_drag_index < 0 ||
       app.tab_drag_index >= app.tab_count {
        return {}
    }
    rect := tab_rect_for_index(app.tab_drag_index, app.tab_count, width, app.client_chrome)
    last := tab_rect_for_index(app.tab_count - 1, app.tab_count, width, app.client_chrome)
    rect.x = clamp(app.tab_drag_x, TAB_X, last.x)
    return rect
}

update_tab_drag_at_width :: proc(app: ^App, x, width: f32) -> bool {
    if app == nil || !app.tab_dragging || app.tab_count <= 1 do return false
    last := tab_rect_for_index(app.tab_count - 1, app.tab_count, width, app.client_chrome)
    next_x := clamp(x - app.tab_drag_grab_x, TAB_X, last.x)
    changed := next_x != app.tab_drag_x
    app.tab_drag_x = next_x
    target := tab_reorder_target(next_x, app.tab_count, width, app.client_chrome)
    if target != app.tab_drag_index && move_tab(app, app.tab_drag_index, target) {
        app.tab_drag_index = target
        return true
    }
    return changed
}

update_tab_drag :: proc(app: ^App, x: f32) -> bool {
    return update_tab_drag_at_width(app, x, window_logical_width(app))
}

tab_index_for_number_key :: proc(key: SDL.Keycode) -> (int, bool) {
    switch key {
    case SDL.K_1: return 0, true
    case SDL.K_2: return 1, true
    case SDL.K_3: return 2, true
    case SDL.K_4: return 3, true
    case SDL.K_5: return 4, true
    case SDL.K_6: return 5, true
    case SDL.K_7: return 6, true
    case SDL.K_8: return 7, true
    case: return 0, false
    }
}

duplicate_active_tab :: proc(app: ^App) -> bool {
    if app == nil || app.active_tab < 0 || app.active_tab >= app.tab_count || app.tab_count >= MAX_TABS {
        return false
    }
    profile := app.tabs[app.active_tab].profile
    open_profile_tab(app, profile)
    return true
}

destroy_tab_contents :: proc(tab: ^Tab) {
    if tab == nil {
        return
    }
    for view, index in tab.panes {
        if view != nil {
            destroy_session_view(view)
            tab.panes[index] = nil
        }
    }
    destroy_pane_nodes(tab.root)
    tab.root = nil
    tab.pane_count = 0
    tab.active_pane = 0
}

add_session_tab :: proc(app: ^App, view: ^Session_View, title: string, profile: int) -> bool {
    _ = finish_tab_drag(app)
    _ = finish_pane_resize_drag(app)
    if app.tab_count >= MAX_TABS {
        if view != nil do destroy_session_view(view)
        return false
    }
    if view == nil {
        return false
    }
    root := new_pane_leaf(0)
    if root == nil {
        destroy_session_view(view)
        return false
    }
    tab := &app.tabs[app.tab_count]
    tab^ = Tab{kind = .Session, title = title, profile = profile, pane_count = 1, root = root, active_pane = 0}
    tab.panes[0] = view
    app.tab_count += 1
    clear_ime_preedit(app)
    app.active_tab = app.tab_count - 1
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
    return true
}

profile_view :: proc(app: ^App, profile_index: int) -> (view: ^Session_View, title: string) {
    profile := profile_at(app, profile_index)
    if profile == nil {
        return create_error_session_view("Unknown profile", .Attached), "Unknown profile"
    }
    title = profile_name(profile)
    if profile.mode == .Launch {
        return create_owned_profile_session_view(app, profile, profile_index), title
    }
    endpoint := profile_endpoint(profile)
    view = create_session_view(endpoint, rawptr(nil), .Attached)
    if view != nil {
        view.profile_index = profile_index
        view.profile_font_pixels = profile.font_pixels
    }
    return view, title
}

open_profile_tab :: proc(app: ^App, profile: int) {
    view, title := profile_view(app, profile)
    _ = add_session_tab(app, view, title, profile)
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

replace_active_session_view :: proc(app: ^App, replacement: ^Session_View) -> bool {
    _ = finish_pane_resize_drag(app)
    if app == nil || replacement == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return false
    }
    clear_ime_preedit(app)
    if app.search_open {
        close_search(app)
    }
    tab := &app.tabs[app.active_tab]
    old := tab_pane_view(tab, tab.active_pane)
    if old == nil {
        return false
    }
    tab.panes[tab.active_pane] = replacement
    if old != nil {
        _ = finish_terminal_mouse_capture(old, 0)
        destroy_session_view(old)
    }
    return true
}

recover_active_session :: proc(app: ^App) -> bool {
    view := active_session_view(app)
    if view == nil || !session_recoverable(view) {
        return false
    }
    replacement, _ := profile_view(app, view.profile_index)
    if replacement == nil {
        return false
    }
    return replace_active_session_view(app, replacement)
}

close_tab :: proc(app: ^App, index: int) {
    _ = finish_tab_drag(app)
    _ = finish_pane_resize_drag(app)
    if app.tab_count <= 1 || index < 0 || index >= app.tab_count {
        return
    }
    clear_ime_preedit(app)
    retiring := app.tabs[index]
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
    destroy_tab_contents(&retiring)
}

split_active_pane :: proc(
    app: ^App,
    orientation: Pane_Split_Orientation = .Vertical,
) {
    _ = finish_pane_resize_drag(app)
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return
    }
    clear_ime_preedit(app)
    tab := &app.tabs[app.active_tab]
    tab.zoomed = false
    if tab.pane_count >= MAX_PANES_PER_TAB {
        return
    }
    view, _ := profile_view(app, app.startup_profile)
    if view == nil {
        return
    }
    if _, ok := split_pane_slot(tab, tab.active_pane, view, orientation); !ok {
        destroy_session_view(view)
        return
    }
    app.profile_menu_open = false
    app.palette_open = false
    app.settings_open = false
}

close_active_pane :: proc(app: ^App) {
    _ = finish_pane_resize_drag(app)
    if app.active_tab < 0 || app.active_tab >= app.tab_count {
        return
    }
    clear_ime_preedit(app)
    tab := &app.tabs[app.active_tab]
    if tab.pane_count <= 1 {
        if app.tab_count <= 1 {
            app.running = false
        } else {
            close_tab(app, app.active_tab)
        }
        return
    }
    removed, ok := remove_pane_slot(tab, tab.active_pane)
    if !ok {
        return
    }
    if tab.pane_count <= 1 {
        tab.zoomed = false
    }
    destroy_session_view(removed)
}

pane_direction_for_key :: proc(key: SDL.Keycode) -> (Pane_Direction, bool) {
    switch key {
    case SDL.K_LEFT:  return .Left, true
    case SDL.K_RIGHT: return .Right, true
    case SDL.K_UP:    return .Up, true
    case SDL.K_DOWN:  return .Down, true
    case:             return .Left, false
    }
}

active_tab_inset :: proc(app: ^App) -> (SDL.FRect, bool) {
    if app == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return {}, false
    }
    w, h: c.int
    if !SDL.GetWindowSize(app.window, &w, &h) {
        return {}, false
    }
    return terminal_inset(f32(w), f32(h)), true
}

focus_active_pane_direction :: proc(app: ^App, direction: Pane_Direction) -> bool {
    inset, ok := active_tab_inset(app)
    if !ok {
        return false
    }
    clear_ime_preedit(app)
    return focus_pane_direction(&app.tabs[app.active_tab], inset, direction)
}

resize_active_pane_direction :: proc(app: ^App, direction: Pane_Direction) -> bool {
    if app == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return false
    }
    clear_ime_preedit(app)
    return resize_active_divider(&app.tabs[app.active_tab], direction)
}

swap_active_pane_direction_app :: proc(app: ^App, direction: Pane_Direction) -> bool {
    inset, ok := active_tab_inset(app)
    if !ok {
        return false
    }
    clear_ime_preedit(app)
    return swap_active_pane_direction(&app.tabs[app.active_tab], inset, direction)
}

active_tab_is_session :: proc(app: ^App) -> bool {
    return app.active_tab >= 0 && app.active_tab < app.tab_count && app.tabs[app.active_tab].kind == .Session
}

reap_child_window :: proc(process: os.Process) {
    _, _ = os.process_wait(process)
}

launch_new_window :: proc() -> bool {
    executable, err := os.get_executable_path(context.temp_allocator)
    if err != nil || len(executable) == 0 {
        return false
    }
    command := []string{executable}
    process, start_err := os.process_start(os.Process_Desc{command = command})
    if start_err != nil {
        return false
    }
    reaper := thread.create_and_start_with_poly_data(
        process,
        reap_child_window,
        self_cleanup = true,
        name = "howl-odin-window",
    )
    if reaper == nil {
        _ = os.process_kill(process)
        _, _ = os.process_wait(process)
        return false
    }
    return true
}

execute_action :: proc(app: ^App, action: App_Action) {
    if app == nil || !action_enabled(app, action) {
        return
    }
    switch action {
    case .Next_Tab, .Previous_Tab:
        app.palette_open = false
        _ = finish_tab_drag(app)
        step := action == .Next_Tab ? 1 : app.tab_count - 1
        _ = select_tab_index(app, (app.active_tab + step) % app.tab_count)
    case .Move_Tab_Left, .Move_Tab_Right:
        app.palette_open = false
        _ = finish_tab_drag(app)
        _ = finish_pane_resize_drag(app)
        _ = move_tab(app, app.active_tab, app.active_tab + (action == .Move_Tab_Left ? -1 : 1))
    case .Close_Tab:
        app.palette_open = false
        if app.tab_count == 1 {
            // Normal application teardown retires every owned pane, not just
            // the active split. Externally attached Sessions remain untouched.
            app.running = false
        } else {
            if app.search_open do close_search(app)
            close_tab(app, app.active_tab)
        }
    case .New_Tab:
        new_tab(app)
    case .New_Window:
        _ = launch_new_window()
    case .Toggle_Fullscreen:
        app.palette_open = false
        _ = toggle_window_fullscreen(app)
    case .Duplicate_Tab:
        _ = duplicate_active_tab(app)
    case .Split_Vertical:
        split_active_pane(app, .Vertical)
    case .Split_Horizontal:
        split_active_pane(app, .Horizontal)
    case .Toggle_Pane_Zoom:
        if app.active_tab >= 0 && app.active_tab < app.tab_count {
            clear_ime_preedit(app)
            _ = toggle_pane_zoom(&app.tabs[app.active_tab])
        }
    case .Open_Local:
        open_local_tab(app)
    case .Attach_Home:
        attach_home_tab(app)
    case .Take_Size_Control, .Stop_Resizing:
        app.palette_open = false
        view := active_session_view(app)
        sync.mutex_lock(&view.mutex)
        set_size_intent(&view.size_control, action == .Take_Size_Control)
        view.ui_dirty = true
        sync.mutex_unlock(&view.mutex)
        if action == .Stop_Resizing {
            publish_control_notice(view, "Auto-sizing stopped here; the last Session size is kept")
        } else {
            publish_control_notice(view, "Taking Session size control...")
        }
    case .Recover_Session:
        _ = recover_active_session(app)
    case .Open_Settings:
        next := !app.settings_open
        if app.search_open do close_search(app)
        close_settings_search(app)
        cancel_profile_edit(app)
        app.profile_menu_open = false
        app.palette_open = false
        app.settings_open = next
        app.settings_content_focus = false
        app.settings_binding_recording = false
        app.settings_notice_len = 0
    case .Open_Command_Palette:
        next := !app.palette_open
        app.palette_open = next
        app.palette_selection = 0
        app.profile_menu_open = false
        app.settings_open = false
    case .Open_Profile_Menu:
        next := !app.profile_menu_open
        app.profile_menu_open = next
        app.profile_menu_selection = 0
        app.palette_open = false
        app.settings_open = false
    case .Close_Pane:
        close_active_pane(app)
        app.palette_open = false
    }
}

palette_action :: proc(index: int) -> (App_Action, bool) {
    if index < 0 {
        return .New_Tab, false
    }
    for action, action_index in PALETTE_ACTIONS {
        if action_index == index {
            return action, true
        }
    }
    return .New_Tab, false
}

set_settings_notice :: proc(app: ^App, message: string) {
    if app == nil {
        return
    }
    app.settings_notice_len = min(len(message), len(app.settings_notice))
    if app.settings_notice_len != 0 {
        copy(app.settings_notice[:app.settings_notice_len], transmute([]u8)message[:app.settings_notice_len])
    }
}

action_definition_at :: proc(index: int) -> (Action_Definition, bool) {
    if index < 0 {
        return {}, false
    }
    for definition, definition_index in ACTION_DEFINITIONS {
        if definition_index == index {
            return definition, true
        }
    }
    return {}, false
}

handle_settings_binding_recording :: proc(app: ^App, event: ^SDL.Event) -> bool {
    if app == nil || !app.settings_open || !app.settings_binding_recording {
        return false
    }
    if event.type != .KEY_DOWN {
        return true
    }
    if event.key.key == SDL.K_ESCAPE {
        app.settings_binding_recording = false
        set_settings_notice(app, "Shortcut recording canceled")
        return true
    }
    if shortcut_modifier_key(event.key.key) {
        return true
    }
    definition, selected := action_definition_at(app.settings_action_selection)
    if !selected {
        app.settings_binding_recording = false
        set_settings_notice(app, "Selected action is unavailable")
        return true
    }
    shortcut, captured := shortcut_from_key_event(event)
    if !captured {
        set_settings_notice(app, "Unsupported shortcut key")
        return true
    }
    if conflict_action, conflict := binding_conflict(app, definition.action, shortcut); conflict {
        buffer: [192]u8
        set_settings_notice(app, fmt.bprintf(buffer[:], "Shortcut already used by %s", action_label(conflict_action)))
        return true
    }
    storage: [SHORTCUT_TEXT_BYTES]u8
    text, formatted := format_shortcut(shortcut, storage[:])
    if !formatted || set_action_binding(app, definition.action, text) != .Applied {
        set_settings_notice(app, "Shortcut could not be assigned")
        return true
    }
    app.settings_binding_recording = false
    save_user_config(app)
    buffer: [192]u8
    set_settings_notice(app, fmt.bprintf(buffer[:], "Saved %s", text))
    return true
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
            app.palette_selection = (app.palette_selection + len(PALETTE_ACTIONS) - 1) % len(PALETTE_ACTIONS)
        case SDL.K_DOWN, SDL.K_TAB:
            app.palette_selection = (app.palette_selection + 1) % len(PALETTE_ACTIONS)
        case SDL.K_RETURN:
            if action, ok := palette_action(app.palette_selection); ok {
                execute_action(app, action)
            }
        case:
            return false
        }
        return true
    }
    if app.profile_menu_open {
        item_count := app.profile_count + 2
        switch event.key.key {
        case SDL.K_ESCAPE:
            app.profile_menu_open = false
        case SDL.K_UP:
            app.profile_menu_selection = (app.profile_menu_selection + item_count - 1) % item_count
        case SDL.K_DOWN, SDL.K_TAB:
            app.profile_menu_selection = (app.profile_menu_selection + 1) % item_count
        case SDL.K_RETURN:
            if app.profile_menu_selection < app.profile_count {
                open_profile_tab(app, app.profile_menu_selection)
            } else if app.profile_menu_selection == app.profile_count {
                execute_action(app, .Open_Command_Palette)
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
        if app.settings_content_focus && app.settings_page == .Profile_Defaults {
            return handle_profile_list_key(app, event)
        }
        if app.settings_content_focus && app.settings_page == .Profile_Home {
            return handle_profile_editor_key(app, event)
        }
        if app.settings_content_focus && app.settings_page == .Actions {
            switch event.key.key {
            case SDL.K_TAB:
                app.settings_content_focus = false
            case SDL.K_UP:
                app.settings_action_selection = (app.settings_action_selection + len(ACTION_DEFINITIONS) - 1) % len(ACTION_DEFINITIONS)
            case SDL.K_DOWN:
                app.settings_action_selection = (app.settings_action_selection + 1) % len(ACTION_DEFINITIONS)
            case SDL.K_RETURN:
                app.settings_binding_recording = true
                set_settings_notice(app, "Press a new shortcut · Esc cancels")
            case SDL.K_DELETE, SDL.K_BACKSPACE:
                if definition, ok := action_definition_at(app.settings_action_selection); ok {
                    if set_action_binding(app, definition.action, "") == .Applied {
                        save_user_config(app)
                        set_settings_notice(app, "Action unbound")
                    }
                }
            case SDL.K_R:
                if definition, ok := action_definition_at(app.settings_action_selection); ok && reset_action_binding(app, definition.action) {
                    save_user_config(app)
                    set_settings_notice(app, "Restored default shortcut")
                }
            case:
                return false
            }
            return true
        }
        switch event.key.key {
        case SDL.K_TAB:
            if app.settings_page == .Actions || app.settings_page == .Profile_Defaults || app.settings_page == .Profile_Home {
                app.settings_content_focus = true
                if app.settings_page == .Profile_Defaults {
                    app.settings_profile_selection = clamp(app.settings_profile_selection, 0, max(0, app.profile_count - 1))
                }
                return true
            }
            return false
        case SDL.K_LEFT, SDL.K_MINUS:
            if app.settings_page == .Startup {
                adjust_startup_profile(app, -1)
                return true
            }
            if app.settings_page == .Appearance {
                adjust_terminal_font(app, -1)
                return true
            }
            if app.settings_page == .Color_Schemes {
                _ = adjust_app_theme(app, -1)
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
            if app.settings_page == .Color_Schemes {
                _ = adjust_app_theme(app, 1)
                return true
            }
            return false
        case SDL.K_UP:
            cancel_profile_edit(app)
            app.settings_binding_recording = false
            app.settings_page = Settings_Page((page + 6) % 7)
            app.settings_content_focus = false
        case SDL.K_DOWN:
            cancel_profile_edit(app)
            app.settings_binding_recording = false
            app.settings_page = Settings_Page((page + 1) % 7)
            app.settings_content_focus = false
        case SDL.K_HOME:
            cancel_profile_edit(app)
            app.settings_binding_recording = false
            app.settings_page = .Startup
            app.settings_content_focus = false
        case SDL.K_END:
            cancel_profile_edit(app)
            app.settings_binding_recording = false
            app.settings_page = .Profile_Home
            app.settings_content_focus = false
        case:
            return false
        }
        return true
    }
    return false
}

profile_menu_rect :: proc(app: ^App) -> SDL.FRect {
    tab_count := app != nil ? app.tab_count : 0
    profile_count := app != nil ? app.profile_count : 0
    width := window_logical_width(app)
    _, menu, _ := tab_controls(tab_count, width, app != nil && app.client_chrome)
    height := f32(20 + profile_count * 48 + 92)
    return {clamp(menu.x - 8, f32(8), max(f32(8), width - 358)), HEADER_HEIGHT, 350, height}
}

settings_panel_rect :: proc(width, height: f32) -> SDL.FRect {
    w := min(f32(760), max(f32(0), width - 24))
    return {width - w - 12, 58, w, max(f32(0), height - 76)}
}

settings_page_at :: proc(x, y: f32, width, height: f32) -> (Settings_Page, bool) {
    panel := settings_panel_rect(width, height)
    sidebar := SDL.FRect{panel.x, panel.y, 178, panel.h}
    if !inside(x, y, sidebar) {
        return .Startup, false
    }
    for index in 0..<7 {
        row := settings_sidebar_row(panel, index)
        if inside(x, y, row) {
            return Settings_Page(index), true
        }
    }
    return .Startup, false
}

handle_click :: proc(app: ^App, x, y, width, height: f32) {
    plus, menu, settings := tab_controls(app.tab_count, width, app.client_chrome)

    if app.search_open && inside(x, y, search_bar_rect(width)) {
        return
    }

    if app.settings_open {
        if app.settings_search_open {
            if result, ok := settings_search_result_at(app, x, y, width, height); ok {
                _ = apply_settings_search_result(app, result)
                return
            }
            search_content := settings_search_content_rect(width, height)
            if inside(x, y, search_content) {
                return
            }
            close_settings_search(app)
        }
        if settings_control_click(app, x, y, width, height) do return
        if page, ok := settings_page_at(x, y, width, height); ok {
            cancel_profile_edit(app)
            app.settings_page = page
            app.settings_content_focus = false
            app.settings_binding_recording = false
            app.settings_notice_len = 0
            return
        }
    }

    if app.palette_open {
        layout := palette_layout(width, height, app.palette_selection)
        for visible_index in 0..<layout.count {
            if inside(x, y, palette_row_rect(layout, visible_index)) {
                if action, ok := palette_action(layout.first + visible_index); ok { execute_action(app, action) }
                return
            }
        }
        if !inside(x, y, layout.box) do app.palette_open = false
        return
    }

    if app.profile_menu_open {
        panel := profile_menu_rect(app)
        for profile_index in 0..<app.profile_count {
            row := SDL.FRect{panel.x + 8, panel.y + 8 + f32(profile_index) * 48, panel.w - 16, 42}
            if inside(x, y, row) {
                open_profile_tab(app, profile_index)
                return
            }
        }
        actions_y := panel.y + 14 + f32(app.profile_count) * 48
        if inside(x, y, {panel.x + 8, actions_y, panel.w - 16, 36}) {
            execute_action(app, .Open_Command_Palette)
            return
        }
        if inside(x, y, {panel.x + 8, actions_y + 42, panel.w - 16, 36}) {
            execute_action(app, .Open_Settings)
            return
        }
        if !inside(x, y, panel) {
            app.profile_menu_open = false
        }
    }

    if inside(x, y, plus) {
        close_search(app)
        execute_action(app, .New_Tab)
        return
    }
    if inside(x, y, menu) {
        close_search(app)
        execute_action(app, .Open_Profile_Menu)
        return
    }
    if inside(x, y, settings) {
        close_search(app)
        execute_action(app, .Open_Settings)
        return
    }

    if i, ok := tab_index_at(x, y, app.tab_count, width, app.client_chrome); ok {
        close_search(app)
        if app.tab_count > 1 && inside(x, y, tab_close_rect_for_index(i, app.tab_count, width, app.client_chrome)) {
            close_tab(app, i)
            return
        }
        _ = select_tab_index(app, i)
        return
    }
}

// Keyboard interaction ends the local drag before tab/overlay routing. Its
// eventual left release belongs to that canceled gesture, not newly exposed UI.
// TUI mouse-reporting captures remain on their own semantic input path.
handle_local_drag_interruption :: proc(app: ^App, event: ^SDL.Event) -> bool {
    if app == nil || event == nil do return false
    #partial switch event.type {
    case .KEY_DOWN:
        tab_ended := finish_tab_drag(app)
        history_ended := finish_all_history_scrollbar_drags(app)
        if tab_ended || history_ended do app.discard_local_drag_release = true
    case .MOUSE_BUTTON_DOWN:
        if event.button.button == SDL.BUTTON_LEFT do app.discard_local_drag_release = false
    case .MOUSE_BUTTON_UP:
        if event.button.button == SDL.BUTTON_LEFT && app.discard_local_drag_release {
            app.discard_local_drag_release = false
            return true
        }
    case .WINDOW_FOCUS_LOST, .WINDOW_CLOSE_REQUESTED, .QUIT:
        app.discard_local_drag_release = false
    }
    return false
}

handle_event :: proc(app: ^App, event: ^SDL.Event) {
    apply_control_completions(app)
    defer {
        if event != nil && event.type == .KEY_DOWN do settings_reveal_selection(app)
    }
    track_window_pointer_cycle(app, event)
    if handle_local_drag_interruption(app, event) do return
    if handle_window_chrome_event(app, event) do return
    if consume_owned_action_key(app, event) {
        return
    }
    if event != nil && u32(event.type) == session_update_event_type {
        reconcile_consequence_owners(app)
        wake_consequence_owners(app)
        _ = apply_desktop_attention(app)
        return
    }
    #partial switch event.type {
    case .QUIT, .WINDOW_CLOSE_REQUESTED:
        _ = finish_tab_drag(app)
        _ = finish_pane_resize_drag(app)
        _ = finish_all_terminal_mouse_captures(app)
        _ = finish_all_history_scrollbar_drags(app)
        _ = finish_all_selections(app)
        _ = send_semantic_focus(active_session_view(app), false)
        app.running = false
    case .WINDOW_FOCUS_LOST:
        app.chrome_pressed = .None
        app.chrome_hover = .None
        clear_ime_preedit(app)
        _ = finish_tab_drag(app)
        _ = finish_pane_resize_drag(app)
        _ = finish_all_terminal_mouse_captures(app)
        _ = finish_all_history_scrollbar_drags(app)
        _ = finish_all_selections(app)
        _ = send_semantic_focus(active_session_view(app), false)
    case .WINDOW_FOCUS_GAINED:
        _ = send_semantic_focus(active_session_view(app), true)
        wake_consequence_owners(app)
    case .WINDOW_DISPLAY_SCALE_CHANGED:
        if !update_text_display_scale(app) {
            sdl_error("TTF display scale update failed")
        }
    case .DROP_FILE:
        _ = drop_into_active_terminal(app, event.drop.data, true)
    case .DROP_TEXT:
        _ = drop_into_active_terminal(app, event.drop.data, false)
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
        } else if event.type == .KEY_DOWN && app.settings_open && ctrl && !shift && !alt && event.key.key == SDL.K_F &&
                  !app.settings_profile_editing && !app.settings_binding_recording {
            if app.settings_search_open {
                close_settings_search(app)
            } else {
                open_settings_search(app)
            }
            return
        } else if app.settings_open && app.settings_search_open {
            _ = handle_settings_search_key(app, event)
            return
        } else if app.settings_open && app.settings_profile_editing {
            _ = handle_profile_edit_key(app, event)
            return
        } else if app.settings_open && app.settings_binding_recording {
            _ = handle_settings_binding_recording(app, event)
            return
        } else if handle_registered_action_shortcut(app, event) {
            // Concrete desktop actions are consumed by the effective binding table.
        } else if event.type == .KEY_DOWN && ctrl && !shift && !alt &&
                  event.key.key >= SDL.K_1 && event.key.key <= SDL.K_8 {
            if index, numeric := tab_index_for_number_key(event.key.key); numeric && index < app.tab_count {
                _ = select_tab_index(app, index)
            }
        } else if event.type == .KEY_DOWN && ctrl && alt {
            if direction, ok := pane_direction_for_key(event.key.key); ok {
                _ = swap_active_pane_direction_app(app, direction)
            }
        } else if event.type == .KEY_DOWN && alt && shift {
            if direction, ok := pane_direction_for_key(event.key.key); ok {
                _ = resize_active_pane_direction(app, direction)
            }
        } else if event.type == .KEY_DOWN && alt {
            if direction, ok := pane_direction_for_key(event.key.key); ok {
                _ = focus_active_pane_direction(app, direction)
            }
        } else if event.type == .KEY_DOWN && ctrl && event.key.key == SDL.K_MINUS {
            adjust_terminal_font(app, -1)
        } else if event.type == .KEY_DOWN && ctrl && (event.key.key == SDL.K_EQUALS || event.key.key == SDL.K_PLUS) {
            adjust_terminal_font(app, 1)
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_C {
            _ = copy_selection_to_clipboard(app, active_session_view(app))
        } else if event.type == .KEY_DOWN && ctrl && shift && event.key.key == SDL.K_V {
            _ = paste_clipboard(active_session_view(app))
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
            close_settings_search(app)
            cancel_profile_edit(app)
            app.profile_menu_open = false
            app.palette_open = false
            app.settings_open = false
            app.settings_content_focus = false
            app.settings_binding_recording = false
        } else if handle_overlay_key(app, event) {
            // Overlay-owned navigation never reaches the terminal.
        } else if send_bridge_key(app, event) {
            // The active real Session consumed this named physical key.
        } else if event.type == .KEY_DOWN && active_session_view(app) != nil && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && (ctrl || alt) {
            view := active_session_view(app)
            if !session_interactive(view) {
                return
            }
            scalar := u32(event.key.key)
            if scalar > 0 && scalar < 0x80 {
                _ = return_history_live(view)
                action := event.key.repeat ? Bridge_Key_Action.Repeat : Bridge_Key_Action.Press
                result := queue_unicode_key(
                    view,
                    scalar,
                    u8(action),
                    bridge_modifiers(event.key.mod),
                )
                if result != 0 {
                    copy_bridge_error(view)
                }
            }
        }
    case .TEXT_EDITING:
        if event.edit.text != nil {
            _ = set_ime_preedit(
                app,
                string(event.edit.text),
                i32(event.edit.start),
                i32(event.edit.length),
            )
        } else {
            clear_ime_preedit(app)
        }
    case .TEXT_INPUT:
        clear_ime_preedit(app)
        if app.settings_open && app.settings_search_open {
            if event.text.text != nil {
                text := string(event.text.text)
                if len(text) != 0 {
                    _ = append_settings_search_query(app, text)
                }
            }
            return
        }
        if app.settings_open && app.settings_profile_editing {
            if event.text.text != nil {
                text := string(event.text.text)
                if len(text) != 0 {
                    _ = append_profile_edit_text(app, text)
                }
            }
            return
        }
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
        if view != nil && view.control != nil && session_interactive(view) && active_tab_is_session(app) && !app.profile_menu_open && !app.palette_open && !app.settings_open && event.text.text != nil {
            text := string(event.text.text)
            if len(text) != 0 {
                _ = return_history_live(view)
                result := queue_text(view, raw_data(text), c.size_t(len(text)))
                if result != 0 {
                    copy_bridge_error(view)
                }
            }
        }
    case .MOUSE_MOTION:
        if app.profile_menu_open || app.palette_open || app.settings_open || app.search_open {
            break
        }
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        if app.tab_dragging {
            _ = update_tab_drag(app, event.motion.x)
            return
        }
        if app.pane_resize_node != nil {
            w, h: c.int
            if SDL.GetWindowSize(app.window, &w, &h) {
                _ = update_pane_resize_drag(app, event.motion.x, event.motion.y, f32(w), f32(h))
            }
            return
        }
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
                    sync.mutex_lock(&view.mutex)
                    selection_dragging := view.selection_dragging
                    terminal_captured := view.terminal_mouse_captured
                    sync.mutex_unlock(&view.mutex)
                    if selection_dragging {
                        if extend_selection(app, view, pane, event.motion.x, event.motion.y) {
                            _ = update_selection_edge_scroll_intent(
                                view,
                                pane,
                                event.motion.x,
                                event.motion.y,
                            )
                        }
                        return
                    }
                    modifiers := bridge_modifiers(SDL.GetModState())
                    if terminal_captured {
                        _ = terminal_mouse_move(
                            view,
                            pane,
                            event.motion.x,
                            event.motion.y,
                            modifiers,
                            true,
                        )
                        return
                    }
                    if session_interactive(view) && !history_active(view) {
                        if state, state_ok := current_interaction_state(view); state_ok &&
                           interaction_mouse_tracking_enabled(state) {
                            _ = terminal_mouse_move(
                                view,
                                pane,
                                event.motion.x,
                                event.motion.y,
                                modifiers,
                                false,
                            )
                        }
                    }
                }
            }
        }
    case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
        _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
        w, h: c.int
        if SDL.GetWindowSize(app.window, &w, &h) {
            if handle_overlay_pointer(app, event, f32(w), f32(h)) {
                return
            }
            if event.type == .MOUSE_BUTTON_UP && event.button.button == SDL.BUTTON_LEFT && app.tab_dragging {
                _ = finish_tab_drag(app)
                return
            }
            if event.type == .MOUSE_BUTTON_UP && app.pane_resize_node != nil {
                _ = update_pane_resize_drag(app, event.button.x, event.button.y, f32(w), f32(h))
                _ = finish_pane_resize_drag(app)
                return
            }
            if event.type == .MOUSE_BUTTON_UP {
                view := active_session_view(app)
                if view != nil && app.active_tab >= 0 && app.active_tab < app.tab_count {
                    tab := &app.tabs[app.active_tab]
                    if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok {
                        if terminal_mouse_release(
                            view,
                            pane,
                            event.button.x,
                            event.button.y,
                            event.button.button,
                            bridge_modifiers(SDL.GetModState()),
                        ) {
                            return
                        }
                    }
                    if event.button.button == SDL.BUTTON_LEFT {
                        if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok &&
                           session_lifecycle_chrome_hit(view, pane, event.button.x, event.button.y) {
                            if session_lifecycle_recovery_hit(view, pane, event.button.x, event.button.y) {
                                _ = recover_active_session(app)
                            }
                            return
                        }
                        if history_scrollbar_drag_active(view) {
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
                            if pane, ok := pane_rect_for_index(app, tab.active_pane, f32(w), f32(h)); ok {
                                _ = extend_selection(app, view, pane, event.button.x, event.button.y)
                            }
                            finish_selection(view)
                            return
                        }
                    }
                }
                handle_click(app, event.button.x, event.button.y, f32(w), f32(h))
                return
            }

            if event.button.button == SDL.BUTTON_LEFT {
                if tab_index, tab_ok := tab_index_at(event.button.x, event.button.y, app.tab_count, f32(w), app.client_chrome); tab_ok {
                    if !(app.tab_count > 1 && inside(event.button.x, event.button.y, tab_close_rect_for_index(tab_index, app.tab_count, f32(w), app.client_chrome))) {
                        _ = begin_tab_drag(app, tab_index, event.button.x)
                        return
                    }
                }
            }
            if event.button.button == SDL.BUTTON_LEFT &&
               begin_pane_resize_drag(app, event.button.x, event.button.y, f32(w), f32(h)) {
                return
            }
            view, pane_index, ok := session_view_at(
                app,
                event.button.x,
                event.button.y,
                f32(w), f32(h),
            )
            if !ok || view == nil {
                return
            }
            if app.active_tab >= 0 && app.active_tab < app.tab_count {
                if app.tabs[app.active_tab].active_pane != pane_index {
                    clear_ime_preedit(app)
                }
                app.tabs[app.active_tab].active_pane = pane_index
            }
            pane, pane_ok := pane_rect_for_index(app, pane_index, f32(w), f32(h))
            if !pane_ok {
                return
            }
            if event.button.button == SDL.BUTTON_LEFT &&
               session_lifecycle_chrome_hit(view, pane, event.button.x, event.button.y) {
                return
            }
            if event.button.button == SDL.BUTTON_LEFT &&
               begin_history_scrollbar_drag(view, pane, event.button.x, event.button.y) {
                return
            }

            modifiers_state := SDL.GetModState()
            modifiers := bridge_modifiers(modifiers_state)
            shift := .LSHIFT in modifiers_state || .RSHIFT in modifiers_state
            ctrl := .LCTRL in modifiers_state || .RCTRL in modifiers_state
            history_is_active := history_active(view)

            if event.button.button == SDL.BUTTON_LEFT {
                if ctrl {
                    if handled, _ := open_hyperlink_at(
                        app,
                        view,
                        pane,
                        event.button.x,
                        event.button.y,
                    ); handled {
                        clear_selection(view)
                        return
                    }
                }
                route := session_interactive(view) ? route_desktop_primary_pointer(
                    history_is_active,
                    shift,
                    false,
                    false,
                ) : Desktop_Primary_Pointer_Route.Local_Selection
                if route == .Interaction_State {
                    if state, state_ok := current_interaction_state(view); state_ok {
                        route = route_desktop_primary_pointer(
                            history_is_active,
                            shift,
                            true,
                            interaction_mouse_tracking_enabled(state),
                        )
                    } else {
                        return
                    }
                }
                if route == .Terminal_Mouse {
                    clear_selection(view)
                    _ = terminal_mouse_press(
                        view,
                        pane,
                        event.button.x,
                        event.button.y,
                        event.button.button,
                        modifiers,
                    )
                    return
                }
                if event.button.clicks >= 3 {
                    _ = expand_selection_at(app, view, pane, event.button.x, event.button.y, 2)
                    return
                }
                if event.button.clicks == 2 {
                    _ = expand_selection_at(app, view, pane, event.button.x, event.button.y, 1)
                    return
                }
                _ = begin_selection(app, view, pane, event.button.x, event.button.y)
                return
            }

            if session_interactive(view) && !history_is_active {
                if state, state_ok := current_interaction_state(view); state_ok &&
                   interaction_mouse_tracking_enabled(state) {
                    _ = terminal_mouse_press(
                        view,
                        pane,
                        event.button.x,
                        event.button.y,
                        event.button.button,
                        modifiers,
                    )
                    return
                }
            }
        }
    case .MOUSE_WHEEL:
        if app.settings_open && !app.settings_search_open {
            _ = SDL.ConvertEventToRenderCoordinates(app.renderer, event)
            w, h: c.int
            if SDL.GetWindowSize(app.window, &w, &h) {
                body := settings_layout(f32(w), f32(h)).body
                limit := settings_sync_scroll(app, body)
                if !app.settings_profile_editing && inside(event.wheel.mouse_x, event.wheel.mouse_y, body) {
                    app.settings_scroll_y = clamp(app.settings_scroll_y - event.wheel.y * 48, 0, limit)
                }
            }
            return
        }
        if app.profile_menu_open || app.palette_open || app.settings_open || app.search_open {
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
                pane, pane_ok := pane_rect_for_index(app, pane_index, f32(w), f32(h))
                if !pane_ok {
                    return
                }
                mods := SDL.GetModState()
                interactive := session_interactive(view)
                force_history := .LSHIFT in mods || .RSHIFT in mods || !interactive
                history_is_active := history_active(view)
                state: Interaction_State_Info
                state_ok := false
                if interactive && !force_history {
                    state, state_ok = current_interaction_state(view)
                }
                route := route_desktop_wheel(
                    history_is_active,
                    force_history,
                    state_ok,
                    state_ok && interaction_mouse_tracking_enabled(state),
                    displayed_alternate_screen(view),
                    state_ok && interaction_alternate_scroll(state),
                )
                if route == .Interaction_State {
                    if state, state_ok = current_interaction_state(view); state_ok {
                        route = route_desktop_wheel(
                            history_is_active,
                            force_history,
                            true,
                            interaction_mouse_tracking_enabled(state),
                            displayed_alternate_screen(view),
                            interaction_alternate_scroll(state),
                        )
                    } else {
                        return
                    }
                }
                switch route {
                case .History:
                    wheel_rows := event.wheel.y
                    if wheel_rows == 0 && event.wheel.integer_y != 0 {
                        wheel_rows = f32(event.wheel.integer_y)
                    }
                    if wheel_rows != 0 {
                        _ = scroll_history_wheel(view, wheel_rows)
                    }
                case .Terminal_Mouse:
                    ticks := int(event.wheel.integer_y)
                    if ticks == 0 {
                        if event.wheel.y >= 1 {
                            ticks = 1
                        } else if event.wheel.y <= -1 {
                            ticks = -1
                        }
                    }
                    if ticks != 0 {
                        row, column, pixel_x, pixel_y, located := terminal_pointer_location(
                            view,
                            pane,
                            event.wheel.mouse_x,
                            event.wheel.mouse_y,
                        )
                        if located {
                            count := min(abs(ticks), 16)
                            button := ticks > 0 ? Bridge_Mouse_Button.Wheel_Up : Bridge_Mouse_Button.Wheel_Down
                            for _ in 0..<count {
                                _ = send_terminal_mouse(
                                    view,
                                    .Wheel,
                                    button,
                                    bridge_modifiers(mods),
                                    0,
                                    row,
                                    column,
                                    pixel_x,
                                    pixel_y,
                                )
                            }
                        }
                    }
                case .Alternate_Scroll:
                    ticks := int(event.wheel.integer_y)
                    if ticks == 0 {
                        if event.wheel.y >= 1 {
                            ticks = 1
                        } else if event.wheel.y <= -1 {
                            ticks = -1
                        }
                    }
                    if ticks != 0 {
                        count := min(abs(ticks), 16)
                        key := ticks > 0 ? Bridge_Key.Up : Bridge_Key.Down
                        for _ in 0..<count {
                            _ = send_named_key_cycle(view, key)
                        }
                    }
                case .Ignore, .Interaction_State:
                }
            }
        }
    case:
    }
}

draw_tab_chip :: proc(app: ^App, i: int, rect: SDL.FRect, width: f32) {
    active := i == app.active_tab
    close_rect := tab_close_rect_for_index(i, app.tab_count, width, app.client_chrome)
    compact := rect.w < 64
    draw_fill(app.renderer, rect, active ? palette.tab_active : palette.tab_idle)
    if active {
        underline := SDL.FRect{rect.x + 10, 37, rect.w - 20, 2}
        draw_fill(app.renderer, underline, palette.accent)
    }

    title_right_pad := close_rect.w > 0 ? f32(52) : (compact ? f32(0) : f32(20))
    title_clip := SDL.Rect{c.int(rect.x + 8), c.int(rect.y), c.int(max(f32(0), rect.w - 12 - title_right_pad)), c.int(rect.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &title_clip)
    property_text: [1024]u8
    title, progress := tab_property_presentation(&app.tabs[i], property_text[:])
    if compact {
        number: [16]u8
        title = fmt.bprintf(number[:], "%d", i + 1)
        draw_text(app, app.ui_font, title, rect.x + 8, 14, active ? palette.text : palette.text_muted)
    } else {
        draw_text(app, app.ui_font, title, rect.x + 10, 14, active ? palette.text : palette.text_muted)
    }
    _ = SDL.SetRenderClipRect(app.renderer, nil)
    if !compact && app.tabs[i].kind == .Session && session_attached(tab_pane_view(&app.tabs[i], app.tabs[i].active_pane)) {
        indicator_x := rect.x + rect.w - (close_rect.w > 0 ? 38 : 12)
        draw_fill(app.renderer, {indicator_x, 20, 5, 5}, palette.accent)
    }
    if close_rect.w > 0 {
        draw_text(app, app.ui_font, "x", rect.x + rect.w - 21, 14, palette.text_muted)
    }
    draw_tab_progress(app, rect, progress)
}

draw_tabs :: proc(app: ^App, width: f32) {
    for i in 0..<app.tab_count {
        rect := tab_rect_for_index(i, app.tab_count, width, app.client_chrome)
        if app.tab_dragging && i == app.tab_drag_index {
            draw_outline(app.renderer, rect, palette.border)
        } else {
            draw_tab_chip(app, i, rect, width)
        }
    }
    if app.tab_dragging && app.tab_drag_index >= 0 && app.tab_drag_index < app.tab_count {
        rect := tab_drag_rect(app, width)
        draw_tab_chip(app, app.tab_drag_index, rect, width)
        draw_outline(app.renderer, rect, palette.accent)
    }

    plus, menu, settings := tab_controls(app.tab_count, width, app.client_chrome)
    draw_fill(app.renderer, plus, palette.tab_idle)
    draw_fill(app.renderer, menu, palette.tab_idle)
    draw_fill(app.renderer, settings, palette.tab_idle)
    draw_text(app, app.ui_font, "+", plus.x + 11, plus.y + 6, palette.text)
    draw_text(app, app.ui_font, "v", menu.x + 11, menu.y + 6, palette.text_muted)
    draw_text(app, app.ui_font, "Settings", settings.x + 12, settings.y + 6, palette.text_muted)
}

draw_profile_menu :: proc(app: ^App) {
    panel := profile_menu_rect(app)
    draw_fill(app.renderer, panel, palette.title_bg)
    draw_outline(app.renderer, panel, palette.border)
    for profile_index in 0..<app.profile_count {
        profile := app.profiles[profile_index]
        row := SDL.FRect{panel.x + 8, panel.y + 8 + f32(profile_index) * 48, panel.w - 16, 42}
        if app.profile_menu_selection == profile_index {
            draw_fill(app.renderer, row, palette.tab_active)
        }
        draw_text(app, app.ui_font, profile_name(profile), row.x + 10, row.y + 5, palette.text)
        detail := profile.mode == .Launch ? "Create Session" : "Attach Session"
        draw_text(app, app.ui_font, detail, row.x + 10, row.y + 23, palette.text_muted)
        if app.startup_profile == profile_index {
            draw_text(app, app.ui_font, "default", row.x + row.w - 72, row.y + 13, palette.accent)
        }
    }
    actions_y := panel.y + 14 + f32(app.profile_count) * 48
    palette_row := SDL.FRect{panel.x + 8, actions_y, panel.w - 16, 36}
    settings_row := SDL.FRect{panel.x + 8, actions_y + 42, panel.w - 16, 36}
    if app.profile_menu_selection == app.profile_count do draw_fill(app.renderer, palette_row, palette.tab_active)
    if app.profile_menu_selection == app.profile_count + 1 do draw_fill(app.renderer, settings_row, palette.tab_active)
    draw_text(app, app.ui_font, action_label(.Open_Command_Palette), palette_row.x + 10, palette_row.y + 8, palette.text)
    draw_text(app, app.ui_font, action_binding_text(app, .Open_Command_Palette), palette_row.x + 190, palette_row.y + 8, palette.text_muted)
    draw_text(app, app.ui_font, action_label(.Open_Settings), settings_row.x + 10, settings_row.y + 8, palette.text)
    draw_text(app, app.ui_font, action_binding_text(app, .Open_Settings), settings_row.x + 252, settings_row.y + 8, palette.text_muted)
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

    content := terminal_content_rect(pane)
    track := SDL.FRect{pane.x + pane.w - 8, content.y, 3, content.h}
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
    hit := SDL.FRect{pane.x + pane.w - 16, track.y, 12, track.h}
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
        for view in app.tabs[index].panes {
            if view != nil && finish_selection_if_dragging(view) {
                changed = true
            }
        }
    }
    return changed
}

finish_all_terminal_mouse_captures :: proc(app: ^App, modifiers: u8 = 0) -> bool {
    changed := false
    for index in 0..<app.tab_count {
        for view in app.tabs[index].panes {
            if view != nil && finish_terminal_mouse_capture(view, modifiers) {
                changed = true
            }
        }
    }
    return changed
}

finish_all_history_scrollbar_drags :: proc(app: ^App) -> bool {
    changed := false
    for index in 0..<app.tab_count {
        for view in app.tabs[index].panes {
            if view != nil && finish_history_scrollbar_drag(view) {
                changed = true
            }
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
    // Match selection/divider drags: delivered button-down owns this gesture.
    // SDL auto-capture / Wayland's implicit grab supplies held-button events;
    // unsupported explicit capture must not reduce dragging to the first seek.
    // Release, focus loss, and application transitions retire it normally.
    _ = SDL.CaptureMouse(true)
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

Session_Lifecycle_Presentation :: struct {
    message: string,
    action: string,
    visible: bool,
    recoverable: bool,
}

session_lifecycle_presentation :: proc(
    state: Session_Lifecycle_State,
    ownership: Session_Ownership,
) -> Session_Lifecycle_Presentation {
    switch state {
    case .Active:
        return {}
    case .Connecting:
        return {message = ownership == .Owned ? "Starting Local Session..." : "Connecting to Session...", visible = true}
    case .Closed:
        if ownership == .Owned {
            return {message = "Process exited", action = "Restart", visible = true, recoverable = true}
        }
        return {message = "Attached Session closed", action = "Reconnect", visible = true, recoverable = true}
    case .Unavailable:
        if ownership == .Owned {
            return {message = "Local Session unavailable", action = "Restart", visible = true, recoverable = true}
        }
        return {message = "Attached Session unavailable", action = "Reconnect", visible = true, recoverable = true}
    }
    return {}
}

session_lifecycle_bar_rect :: proc(pane: SDL.FRect) -> SDL.FRect {
    return {pane.x + 8, pane.y + pane.h - 42, max(f32(0), pane.w - 24), 34}
}

session_lifecycle_action_rect :: proc(pane: SDL.FRect) -> SDL.FRect {
    bar := session_lifecycle_bar_rect(pane)
    width := min(f32(224), max(f32(140), bar.w * 0.44))
    return {bar.x + bar.w - width - 5, bar.y + 4, width, bar.h - 8}
}

session_lifecycle_chrome_hit :: proc(view: ^Session_View, pane: SDL.FRect, x, y: f32) -> bool {
    if view == nil {
        return false
    }
    presentation := session_lifecycle_presentation(session_lifecycle_state(view), view.ownership)
    return presentation.visible && inside(x, y, session_lifecycle_bar_rect(pane))
}

session_lifecycle_recovery_hit :: proc(view: ^Session_View, pane: SDL.FRect, x, y: f32) -> bool {
    if view == nil {
        return false
    }
    presentation := session_lifecycle_presentation(session_lifecycle_state(view), view.ownership)
    return presentation.recoverable && inside(x, y, session_lifecycle_action_rect(pane))
}

draw_session_lifecycle :: proc(
    app: ^App,
    view: ^Session_View,
    pane: SDL.FRect,
    state: Session_Lifecycle_State,
) {
    if view == nil {
        return
    }
    presentation := session_lifecycle_presentation(state, view.ownership)
    if !presentation.visible {
        return
    }
    bar := session_lifecycle_bar_rect(pane)
    if bar.w <= 0 || bar.h <= 0 {
        return
    }
    background := palette.title_bg
    background[3] = 238
    draw_fill(app.renderer, bar, background)
    draw_outline(app.renderer, bar, palette.border)
    draw_text(app, app.ui_font, presentation.message, bar.x + 10, bar.y + 8, palette.text)
    if presentation.recoverable {
        action := session_lifecycle_action_rect(pane)
        draw_fill(app.renderer, action, palette.tab_active)
        draw_outline(app.renderer, action, palette.accent)
        shortcut := action_binding_text(app, .Recover_Session)
        label_storage: [128]u8
        label := presentation.action
        if len(shortcut) != 0 {
            label = fmt.bprintf(label_storage[:], "%s  %s", presentation.action, shortcut)
        }
        draw_text(app, app.ui_font, label, action.x + 9, action.y + 5, palette.accent)
    }
}

draw_real_session :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    if view == nil {
        return
    }
    lifecycle_state := session_lifecycle_state(view)
    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    content := terminal_content_rect(pane)
    resize_session_to_pane(app, view, content.w, content.h)
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
        draw_control_notice(app, view, pane)
        draw_session_lifecycle(app, view, pane, lifecycle_state)
        return
    }

    pane_clip := SDL.Rect{c.int(pane.x), c.int(pane.y), c.int(pane.w), c.int(pane.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &pane_clip)
    defer {
        _ = SDL.SetRenderClipRect(app.renderer, nil)
    }

    sync.mutex_lock(&view.mutex)
    error_text := view.error
    error_count := view.error_len
    text := make([]u8, view.text_len)
    copy(text, view.text[:view.text_len])
    cursor_is_visible := view.cursor_visible
    current_rows, current_columns := view.rows, view.columns
    cursor_row_value, cursor_column_value := view.cursor_row, view.cursor_column
    shape := view.cursor_shape
    truncated := view.text_truncated
    sync.mutex_unlock(&view.mutex)
    defer delete(text)

    if error_count != 0 {
        draw_text(app, app.ui_font, string(error_text[:error_count]), origin_x, origin_y, palette.accent)
        draw_control_notice(app, view, pane)
        draw_session_lifecycle(app, view, pane, lifecycle_state)
        return
    }
    if len(text) != 0 {
        draw_text(app, app.terminal_font, string(text), origin_x, origin_y, palette.text)
    }

    if cursor_is_visible && current_rows != 0 && current_columns != 0 {
        cell_w, cell_h: c.int
        if TTF.GetStringSize(app.terminal_font, "M", 1, &cell_w, &cell_h) {
            line_h := TTF.GetFontLineSkip(app.terminal_font)
            cursor_x := origin_x + f32(int(cursor_column_value) * int(cell_w))
            cursor_y := origin_y + f32(int(cursor_row_value) * int(line_h))
            switch shape {
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

    if truncated {
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
    draw_control_notice(app, view, pane)
        draw_session_lifecycle(app, view, pane, lifecycle_state)
}

clear_ime_preedit :: proc(app: ^App) {
    app.ime_preedit_len = 0
    app.ime_preedit_start = 0
    app.ime_preedit_length = 0
}

set_ime_preedit :: proc(app: ^App, text: string, start, length: i32) -> bool {
    clear_ime_preedit(app)
    if len(text) == 0 {
        return true
    }
    if len(text) > len(app.ime_preedit) {
        return false
    }
    copy(app.ime_preedit[:len(text)], transmute([]u8)text)
    app.ime_preedit_len = len(text)
    app.ime_preedit_start = start
    app.ime_preedit_length = length
    return true
}

search_input_field :: proc(width: f32) -> SDL.FRect {
    box := search_bar_rect(width)
    return {box.x + 58, box.y + 6, max(f32(160), box.w - 340), 34}
}

text_width :: proc(app: ^App, font: ^TTF.Font, text: string) -> f32 {
    if font == nil || len(text) == 0 {
        return 0
    }
    width, height: c.int
    if !TTF.GetStringSize(font, cstring(raw_data(text)), c.size_t(len(text)), &width, &height) {
        return 0
    }
    scale := f32(1)
    if app != nil && valid_canvas_scale(app.text_scale) {
        scale = app.text_scale
    }
    return f32(width) / scale
}

ime_preedit_cursor_byte_offset :: proc(text: string, character_index: i32) -> int {
    if character_index <= 0 || len(text) == 0 {
        return 0
    }
    characters: i32
    for byte, index in transmute([]u8)text {
        if byte & 0xc0 == 0x80 {
            continue
        }
        if characters == character_index {
            return index
        }
        characters += 1
    }
    return len(text)
}

ime_preedit_caret_pixels :: proc(app: ^App, font: ^TTF.Font) -> c.int {
    if app == nil || app.ime_preedit_len == 0 || app.ime_preedit_start < 0 {
        return 0
    }
    preedit := string(app.ime_preedit[:app.ime_preedit_len])
    offset := ime_preedit_cursor_byte_offset(preedit, app.ime_preedit_start)
    return c.int(math.ceil(text_width(app, font, preedit[:offset])))
}

active_terminal_cursor_rect :: proc(
    app: ^App,
    width, height: f32,
) -> (pane: SDL.FRect, cursor: SDL.Rect, ok: bool) {
    view := active_session_view(app)
    if view == nil || view.canvas == nil || app.active_tab < 0 || app.active_tab >= app.tab_count {
        return {}, {}, false
    }
    tab := &app.tabs[app.active_tab]
    pane_value, pane_ok := pane_rect_for_index(app, tab.active_pane, width, height)
    if !pane_ok {
        return {}, {}, false
    }
    pane = pane_value
    cell_width := render_cell_width(view.canvas)
    cell_height := render_cell_height(view.canvas)
    if cell_width == 0 || cell_height == 0 {
        return {}, {}, false
    }
    rows := u16(view.canvas_surface_height / cell_height)
    columns := u16(view.canvas_surface_width / cell_width)
    if rows == 0 || columns == 0 {
        return {}, {}, false
    }
    sync.mutex_lock(&view.mutex)
    row := min(view.cursor_row, rows - 1)
    column := min(view.cursor_column, columns - 1)
    sync.mutex_unlock(&view.mutex)
    origin_x := terminal_content_rect(pane).x
    origin_y := terminal_content_rect(pane).y
    scale := canvas_scale_value(view)
    cursor = {
        c.int(math.floor(origin_x + f32(u32(column) * u32(cell_width)) / scale)),
        c.int(math.floor(origin_y + f32(u32(row) * u32(cell_height)) / scale)),
        max(c.int(1), c.int(math.ceil(f32(cell_width) / scale))),
        max(c.int(1), c.int(math.ceil(f32(cell_height) / scale))),
    }
    return pane, cursor, true
}

update_text_input_area :: proc(app: ^App, width, height: f32) {
    if app.settings_open && app.settings_search_open {
        field := settings_search_input_rect(width, height)
        query := settings_search_query(app)
        input_x := min(field.x + 10 + text_width(app, app.ui_font, query), field.x + field.w - 10)
        caret := ime_preedit_caret_pixels(app, app.ui_font)
        available := max(c.int(2), c.int(field.x + field.w - 8 - input_x))
        area_width := max(c.int(2), caret + 2)
        if app.ime_preedit_len != 0 {
            preedit := string(app.ime_preedit[:app.ime_preedit_len])
            area_width = max(area_width, c.int(text_width(app, app.ui_font, preedit)))
        }
        area_width = min(area_width, available)
        caret = min(caret, max(c.int(0), area_width - 1))
        area := SDL.Rect{c.int(input_x), c.int(field.y + 5), area_width, c.int(field.h - 10)}
        _ = SDL.SetTextInputArea(app.window, &area, caret)
        return
    }
    if app.settings_open && app.settings_profile_editing {
        if field, ok := profile_editor_input_rect(app, width, height); ok {
            text := string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len])
            input_x := min(field.x + 7 + text_width(app, app.ui_font, text), field.x + field.w - 10)
            caret := ime_preedit_caret_pixels(app, app.ui_font)
            available := max(c.int(2), c.int(field.x + field.w - 8 - input_x))
            area_width := max(c.int(2), caret + 2)
            if app.ime_preedit_len != 0 {
                preedit := string(app.ime_preedit[:app.ime_preedit_len])
                area_width = max(area_width, c.int(text_width(app, app.ui_font, preedit)))
            }
            area_width = min(area_width, available)
            caret = min(caret, max(c.int(0), area_width - 1))
            area := SDL.Rect{c.int(input_x), c.int(field.y + 5), area_width, c.int(field.h - 10)}
            _ = SDL.SetTextInputArea(app.window, &area, caret)
            return
        }
    }
    if app.search_open {
        field := search_input_field(width)
        query := string(app.search_query[:app.search_query_len])
        input_x := field.x + 9 + text_width(app, app.ui_font, query)
        input_x = min(input_x, field.x + field.w - 10)
        caret := ime_preedit_caret_pixels(app, app.ui_font)
        available := max(c.int(2), c.int(field.x + field.w - 9 - input_x))
        area_width := max(c.int(2), caret + 2)
        if app.ime_preedit_len != 0 {
            preedit := string(app.ime_preedit[:app.ime_preedit_len])
            area_width = max(area_width, c.int(text_width(app, app.ui_font, preedit)))
        }
        area_width = min(area_width, available)
        caret = min(caret, max(c.int(0), area_width - 1))
        area := SDL.Rect{c.int(input_x), c.int(field.y + 7), area_width, c.int(field.h - 14)}
        _ = SDL.SetTextInputArea(app.window, &area, caret)
        return
    }
    pane, cursor, ok := active_terminal_cursor_rect(app, width, height)
    if !ok {
        _ = SDL.SetTextInputArea(app.window, nil, 0)
        return
    }
    caret := ime_preedit_caret_pixels(app, app.terminal_font)
    available := max(c.int(2), c.int(pane.x + pane.w - 2) - cursor.x)
    area_width := max(cursor.w, caret + 2)
    if app.ime_preedit_len != 0 {
        preedit := string(app.ime_preedit[:app.ime_preedit_len])
        area_width = max(area_width, c.int(text_width(app, app.terminal_font, preedit)))
    }
    area_width = min(area_width, available)
    caret = min(caret, max(c.int(0), area_width - 1))
    area := SDL.Rect{cursor.x, cursor.y, area_width, cursor.h}
    _ = SDL.SetTextInputArea(app.window, &area, caret)
}

draw_ime_preedit :: proc(app: ^App, width, height: f32) {
    if app.ime_preedit_len == 0 {
        return
    }
    preedit := string(app.ime_preedit[:app.ime_preedit_len])
    if app.settings_open && app.settings_search_open {
        field := settings_search_input_rect(width, height)
        query := settings_search_query(app)
        x := min(field.x + 10 + text_width(app, app.ui_font, query), field.x + field.w - 12)
        clip := SDL.Rect{c.int(field.x + 8), c.int(field.y), c.int(max(f32(1), field.w - 16)), c.int(field.h)}
        _ = SDL.SetRenderClipRect(app.renderer, &clip)
        draw_text(app, app.ui_font, preedit, x, field.y + 10, palette.accent)
        underline_width := max(f32(4), min(text_width(app, app.ui_font, preedit), field.x + field.w - 10 - x))
        draw_fill(app.renderer, {x, field.y + field.h - 5, underline_width, 1}, palette.accent)
        _ = SDL.SetRenderClipRect(app.renderer, nil)
        return
    }
    if app.settings_open && app.settings_profile_editing {
        if field, ok := profile_editor_input_rect(app, width, height); ok {
            text := string(app.settings_profile_edit_buffer[:app.settings_profile_edit_len])
            x := min(field.x + 7 + text_width(app, app.ui_font, text), field.x + field.w - 12)
            clip := SDL.Rect{c.int(field.x + 5), c.int(field.y), c.int(max(f32(1), field.w - 10)), c.int(field.h)}
            _ = SDL.SetRenderClipRect(app.renderer, &clip)
            draw_text(app, app.ui_font, preedit, x, field.y + 8, palette.accent)
            underline_width := max(f32(4), min(text_width(app, app.ui_font, preedit), field.x + field.w - 7 - x))
            draw_fill(app.renderer, {x, field.y + field.h - 5, underline_width, 1}, palette.accent)
            _ = SDL.SetRenderClipRect(app.renderer, nil)
            return
        }
    }
    if app.search_open {
        field := search_input_field(width)
        query := string(app.search_query[:app.search_query_len])
        x := min(field.x + 9 + text_width(app, app.ui_font, query), field.x + field.w - 12)
        clip := SDL.Rect{c.int(field.x + 8), c.int(field.y), c.int(field.w - 16), c.int(field.h)}
        _ = SDL.SetRenderClipRect(app.renderer, &clip)
        draw_text(app, app.ui_font, preedit, x, field.y + 8, palette.accent)
        underline_width := max(f32(4), min(text_width(app, app.ui_font, preedit), field.x + field.w - 9 - x))
        draw_fill(app.renderer, {x, field.y + field.h - 6, underline_width, 1}, palette.accent)
        _ = SDL.SetRenderClipRect(app.renderer, nil)
        return
    }
    pane, cursor, ok := active_terminal_cursor_rect(app, width, height)
    if !ok {
        return
    }
    preedit_width := max(f32(cursor.w), text_width(app, app.terminal_font, preedit))
    x := f32(cursor.x)
    y := f32(cursor.y)
    preedit_width = min(preedit_width, max(f32(cursor.w), pane.x + pane.w - 2 - x))
    background := SDL.FRect{x, y, preedit_width, f32(cursor.h)}
    draw_fill(app.renderer, background, palette.terminal_bg)
    draw_text(app, app.terminal_font, preedit, x, y, palette.text)
    draw_fill(app.renderer, {x, y + f32(cursor.h) - 2, preedit_width, 1}, palette.accent)
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

    field := search_input_field(width)
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
    inset := terminal_inset(width, height)
    draw_fill(app.renderer, inset, palette.terminal_panel)

    if !active_tab_is_session(app) {
        draw_placeholder_session(app)
        return
    }
    tab := &app.tabs[app.active_tab]
    layout := pane_layout(tab, inset)
    for index in 0..<layout.divider_count {
        draw_fill(app.renderer, layout.dividers[index].rect, palette.border)
    }
    for index in 0..<layout.entry_count {
        entry := layout.entries[index]
        view := tab_pane_view(tab, entry.pane_index)
        if view == nil {
            continue
        }
        draw_fill(app.renderer, entry.rect, palette.terminal_panel)
        draw_real_session(app, view, entry.rect)
        if tab.pane_count > 1 && entry.pane_index == tab.active_pane {
            draw_outline(app.renderer, entry.rect, palette.accent)
        }
    }
}

draw_palette :: proc(app: ^App, width, height: f32) {
    layout := palette_layout(width, height, app.palette_selection)
    box := layout.box
    draw_fill(app.renderer, box, palette.title_bg)
    draw_outline(app.renderer, box, palette.border)
    settings_clipped_text(app, {box.x + 18, box.y + 18, max(f32(0), box.w - 36), 22},
                          "> Command Palette", palette.text)
    for visible_index in 0..<layout.count {
        index := layout.first + visible_index
        action, ok := palette_action(index)
        if !ok do continue
        row := palette_row_rect(layout, visible_index)
        if app.palette_selection == index do draw_fill(app.renderer, row, palette.tab_active)
        color := action_enabled(app, action) ? palette.text : palette.text_muted
        shortcut := action_binding_text(app, action)
        label_width := max(f32(0), row.w - 20 - (len(shortcut) > 0 ? f32(195) : f32(0)))
        settings_clipped_text(app, {row.x + 10, row.y + 8, label_width, 22}, action_label(action), color)
        if len(shortcut) > 0 {
            settings_clipped_text(app, {row.x + row.w - 195, row.y + 8, 185, 22}, shortcut, palette.text_muted)
        }
    }
    if layout.count < len(PALETTE_ACTIONS) {
        buffer: [96]u8
        label := fmt.bprintf(buffer[:], "%d-%d of %d  |  Up/Down to navigate", layout.first + 1, layout.first + layout.count, len(PALETTE_ACTIONS))
        settings_clipped_text(app, {box.x + 18, box.y + box.h - 28, max(f32(0), box.w - 36), 20}, label, palette.text_muted)
    }
}

settings_page_title :: proc(page: Settings_Page) -> string {
    switch page {
    case .Startup:          return "Startup"
    case .Interaction:      return "Interaction"
    case .Appearance:       return "Appearance"
    case .Color_Schemes:    return "Color schemes"
    case .Actions:          return "Actions"
    case .Profile_Defaults: return "Profiles"
    case .Profile_Home:     return "Edit profile"
    }
    return ""
}

draw_setting_field :: proc(app: ^App, label, value: string, x, y, width: f32) {
    // Informational values deliberately do not impersonate editable controls.
    settings_clipped_text(app, {x, y, width, 22}, label, palette.text_muted)
    settings_clipped_text(app, {x + 8, y + 30, max(f32(0), width - 16), 24}, value, palette.text)
}

draw_settings :: proc(app: ^App, width, height: f32) {
    layout := settings_layout(width, height)
    panel, body := layout.panel, layout.body
    panel_clip := SDL.Rect{c.int(panel.x), c.int(panel.y), c.int(panel.w), c.int(panel.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &panel_clip)
    defer { _ = SDL.SetRenderClipRect(app.renderer, nil) }
    limit := settings_sync_scroll(app, body)
    draw_fill(app.renderer, panel, palette.title_bg)
    draw_outline(app.renderer, panel, palette.border)
    sidebar := SDL.FRect{panel.x, panel.y, 178, panel.h}
    draw_fill(app.renderer, sidebar, palette.tab_idle)
    draw_text(app, app.ui_font, "Settings", sidebar.x + 18, sidebar.y + 18, palette.text)
    for index in 0..<7 {
        page := Settings_Page(index)
        row := settings_sidebar_row(panel, index)
        selected := app.settings_page == page
        if selected do draw_fill(app.renderer, row, palette.tab_active)
        if selected && !app.settings_content_focus do draw_outline(app.renderer, row, palette.accent)
        settings_clipped_text(app, {row.x + 10, row.y + 6, row.w - 20, row.h - 6}, settings_page_title(page),
                              selected ? palette.accent : palette.text_muted)
    }
    settings_clipped_text(app, {body.x, panel.y + 18, max(f32(0), body.w - 78), 24},
                          settings_page_title(app.settings_page), palette.text)
    settings_draw_button(app, {panel.x + panel.w - 76, panel.y + 10, 64, 30}, "Close", !app.settings_profile_editing)
    if app.settings_page == .Profile_Defaults || app.settings_page == .Profile_Home {
        settings_draw_profile_toolbar(app, layout)
    } else {
        settings_clipped_text(app, layout.toolbar, app.settings_page == .Interaction ? "Information only" : "Changes save automatically", palette.text_muted)
    }

    content_x := body.x + 8
    content_y := body.y - 48 - app.settings_scroll_y
    available := max(f32(0), body.w - 16)
    clip := SDL.Rect{c.int(body.x), c.int(body.y), c.int(body.w), c.int(body.h)}
    if !SDL.GetRectIntersection(clip, panel_clip, &clip) do clip = {}
    _ = SDL.SetRenderClipRect(app.renderer, &clip)
    switch app.settings_page {
    case .Startup:
        draw_text(app, app.ui_font, "Default profile", content_x, content_y + 48, palette.text_muted)
        settings_draw_stepper(app, settings_choice_rect(body, app.settings_scroll_y, 0),
                              startup_profile_label(app, app.startup_profile), app.startup_profile > 0, app.startup_profile + 1 < app.profile_count)
        draw_setting_field(app, "Session ownership", startup_action_label(app, app.startup_profile), content_x, content_y + 126, available)
        startup := profile_at(app, app.startup_profile)
        if startup != nil && startup.mode == .Launch {
            detail := profile_command(startup)
            if len(detail) == 0 do detail = "Your interactive shell"
            draw_setting_field(app, "Launch", detail, content_x, content_y + 204, available)
        } else {
            draw_setting_field(app, "Existing Session endpoint", profile_endpoint(startup), content_x, content_y + 204, available)
        }
    case .Interaction:
        draw_setting_field(app, "Input path", "howl-client semantic actions", content_x, content_y + 48, available)
        draw_setting_field(app, "Observation", "Blocking revision worker", content_x, content_y + 126, available)
        draw_setting_field(app, "Selection / clipboard", "Drag select / Ctrl+Shift+C,V", content_x, content_y + 204, available)
    case .Appearance:
        draw_text(app, app.ui_font, "Default terminal size", content_x, content_y + 48, palette.text_muted)
        settings_draw_stepper(app, settings_choice_rect(body, app.settings_scroll_y, 0), font_size_label(app.terminal_font_preset),
                              app.terminal_font_preset > FONT_PRESET_MIN, app.terminal_font_preset < FONT_PRESET_MAX, true)
        draw_setting_field(app, "Font family (fixed for now)", "JetBrainsMono Nerd Font", content_x, content_y + 126, available)
        settings_draw_note(app, {content_x, content_y + 192, available, 40}, "Font family selection is not available yet.")
        draw_setting_field(app, "Application theme (see Color schemes)", app_theme_label(app.app_theme), content_x, content_y + 246, available)
    case .Color_Schemes:
        draw_text(app, app.ui_font, "Application colors", content_x, content_y + 48, palette.text_muted)
        settings_draw_stepper(app, settings_choice_rect(body, app.settings_scroll_y, 0), app_theme_label(app.app_theme), true, true)
        draw_text(app, app.ui_font, "Chrome palette", content_x, content_y + 134, palette.text_muted)
        colors := [6]SDL.Color{palette.terminal_bg, palette.tab_idle, palette.border, palette.text_muted, palette.text, palette.accent}
        swatch_w := min(f32(40), max(f32(0), (available - 5 * 12) / 6))
        for color, index in colors {
            swatch := SDL.FRect{content_x + f32(index) * (swatch_w + 12), content_y + 164, swatch_w, 40}
            draw_fill(app.renderer, swatch, color)
            draw_outline(app.renderer, swatch, palette.border)
        }
    case .Actions:
        for definition, index in ACTION_DEFINITIONS {
            y := content_y + 54 + f32(index) * 32
            selected := app.settings_content_focus && app.settings_action_selection == index
            row := SDL.FRect{body.x, y - 5, body.w - 8, 28}
            if selected do draw_fill(app.renderer, row, palette.tab_active)
            draw_outline(app.renderer, row, selected ? palette.accent : palette.border)
            split := max(f32(0), (available - 16) * 0.56)
            settings_clipped_text(app, {content_x, y, split, 22}, definition.label, selected ? palette.accent : palette.text)
            shortcut := action_binding_text(app, definition.action)
            if len(shortcut) == 0 do shortcut = "Unbound"
            settings_clipped_text(app, {content_x + split + 8, y, available - split - 8, 22}, shortcut, palette.text_muted)
        }
    case .Profile_Defaults:
        draw_profiles_settings(app, body)
    case .Profile_Home:
        draw_profile_editor_settings(app, body)
    }
    _ = SDL.SetRenderClipRect(app.renderer, &panel_clip)
    if limit > 0 && body.h > 0 {
        track := SDL.FRect{body.x + body.w - 3, body.y, 3, body.h}
        draw_fill(app.renderer, track, palette.tab_idle)
        thumb_h := min(body.h, max(f32(20), body.h * body.h / settings_content_height(app)))
        draw_fill(app.renderer, {track.x, track.y + app.settings_scroll_y / limit * (body.h - thumb_h), 3, thumb_h}, palette.accent)
    }
    note_y := layout.footer.y
    if app.settings_page == .Profile_Defaults {
        profile := selected_settings_profile(app)
        is_default := profile != nil && app.startup_profile == app.settings_profile_selection
        settings_draw_button(app, {layout.footer.x, note_y, 136, 30}, is_default ? "Default" : "Set default",
                              profile_ui_action_enabled(app, .Default), is_default)
        if profile != nil {
            settings_clipped_text(app, {layout.footer.x + 148, note_y + 7, max(f32(0), layout.footer.w - 148), 24},
                                  profile_name(profile), palette.text)
        }
        note_y += 38
    } else if app.settings_page == .Profile_Home && !app.settings_profile_editing {
        profile := selected_settings_profile(app)
        if profile != nil && !profile.built_in && profile.mode == .Launch {
            labels := [4]string{"Add variable", "Remove", "<", ">"}
            enabled := [4]bool{profile.env_count < MAX_PROFILE_ENV, profile.env_count > 0,
                               app.settings_profile_env_selection > 0, app.settings_profile_env_selection + 1 < profile.env_count}
            for label, index in labels {
                settings_draw_button(app, settings_button_rect({layout.footer.x, note_y, layout.footer.w, 30}, index, 4), label, enabled[index])
            }
            note_y += 38
        }
    }
    settings_draw_note(app, {layout.footer.x, note_y, layout.footer.w, layout.footer.y + layout.footer.h - note_y}, settings_footer_note(app))
}

draw :: proc(app: ^App) {
    if app == nil || app.window == nil || !window_presentation_allowed(SDL.GetWindowFlags(app.window)) {
        return
    }
    w, h: c.int
    if !SDL.GetWindowSize(app.window, &w, &h) {
        return
    }
    _ = SDL.SetRenderLogicalPresentation(app.renderer, w, h, .STRETCH)
    width := f32(w)
    height := f32(h)

    set_draw_color(app.renderer, palette.window_bg)
    _ = SDL.RenderClear(app.renderer)

    tab_bar := SDL.FRect{0, 0, width, HEADER_HEIGHT}
    draw_fill(app.renderer, tab_bar, palette.title_bg)
    draw_tabs(app, width)
    draw_window_controls(app, width)
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
        if app.settings_search_open {
            draw_settings_search(app, width, height)
        }
    }
    update_text_input_area(app, width, height)
    draw_ime_preedit(app, width, height)
    _ = SDL.RenderPresent(app.renderer)
}

main :: proc() {
    if version() != 8 { fmt.eprintln("Howl bridge version mismatch"); return }
    desktop_io_runtime = runtime_create()
    if desktop_io_runtime == nil { fmt.eprintln("Howl host I/O initialization failed"); return }
    defer { runtime_destroy(desktop_io_runtime); desktop_io_runtime = nil }
    assert(size_of(Canvas_Resource_Info) == int(render_resource_info_size()))
    assert(size_of(Canvas_Removal_Info) == int(render_removal_info_size()))
    assert(size_of(Canvas_Command_Info) == int(render_command_info_size()))
    assert(size_of(Search_Match_Info) == int(search_match_info_size()))
    assert(size_of(Selection_Range_Info) == int(selection_range_info_size()))
    assert(size_of(Interaction_State_Info) == int(interaction_state_info_size()))
    assert(size_of(Profile_Env_Info) == int(profile_env_info_size()))
    assert(size_of(Consequence_Info) == int(consequence_info_size()))
    if !SDL.SetAppMetadata(APP_NAME, APP_VERSION, APP_IDENTIFIER) {
        sdl_error("SDL_SetAppMetadata failed")
        return
    }
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
    window := SDL.CreateWindow(APP_NAME, 1180, 760, flags)
    if window == nil {
        sdl_error("SDL_CreateWindow failed")
        return
    }
    defer SDL.DestroyWindow(window)

    if base_path := SDL.GetBasePath(); base_path != nil {
        icon_path_buffer: [4096]u8
        icon_path := fmt.bprintf(icon_path_buffer[:len(icon_path_buffer)-1], "%s%s", string(base_path), APP_WINDOW_ICON)
        icon_path_buffer[len(icon_path)] = 0
        if icon := SDL.LoadBMP(cstring(raw_data(icon_path_buffer[:]))); icon != nil {
            _ = SDL.SetWindowIcon(window, icon)
            SDL.DestroySurface(icon)
        }
    }

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

    ui_font := TTF.OpenFont(UI_FONT_PATH, 15)
    if ui_font == nil {
        sdl_error("TTF_OpenFont UI failed")
        return
    }
    defer TTF.CloseFont(ui_font)

    user_config := load_user_config()
    terminal_fonts: Desktop_Fonts
    if font_error, fonts_ok := resolve_desktop_fonts(&terminal_fonts); !fonts_ok {
        sdl_error(font_error)
        return
    }
    app_theme, theme_ok := parse_app_theme(user_config.app_theme)
    if !theme_ok {
        app_theme = .Howl_Dark
    }
    palette = palette_for_theme(app_theme)
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
        ui_font = ui_font,
        terminal_font = terminal_font,
        terminal_fonts = terminal_fonts,
        terminal_font_preset = terminal_font_preset,
        text_scale = 1,
        app_theme = app_theme,
        running = true,
        tab_count = 0,
        active_tab = -1,
        tab_drag_index = -1,
        pane_resize_tab = -1,
        next_session_identity = 1,
        startup_profile = 0,
    }
    _ = SDL.SetWindowMinimumSize(window, 640, 320)
    if !install_window_chrome(&app) {
        sdl_error("Unified header unavailable; keeping native window decorations")
    }
    defer _ = SDL.SetWindowHitTest(window, nil, nil)
    if !update_text_display_scale(&app) {
        sdl_error("TTF display scale initialization failed")
        return
    }
    if !initialize_builtin_profiles(&app) {
        sdl_error("Built-in profile initialization failed")
        return
    }
    defer destroy_profiles(&app)
    load_user_profiles(&app, user_config.profiles)
    app.startup_profile = default_profile_index_from_config(&app, user_config)
    if !initialize_action_bindings(&app) {
        sdl_error("Default action bindings invalid")
        return
    }
    _ = apply_user_keybindings(&app, user_config.keybindings)
    new_tab(&app)
    reconcile_consequence_owners(&app)

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
        input_dirty := u32(event.type) != session_update_event_type
        handle_event(&app, &event)
        for SDL.PollEvent(&event) {
            input_dirty = input_dirty || u32(event.type) != session_update_event_type
            handle_event(&app, &event)
        }
        if app.running {
            reconcile_consequence_owners(&app)
            _ = apply_desktop_attention(&app)
            io_dirty := service_desktop_io(&app)
            if input_dirty || io_dirty do draw(&app)
        }
    }

    destroy_consequence_owners(&app)
    for app.tab_count > 0 {
        app.tab_count -= 1
        destroy_tab_contents(&app.tabs[app.tab_count])
        app.tabs[app.tab_count] = {}
    }
}
