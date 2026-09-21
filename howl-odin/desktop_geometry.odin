package main

import "core:math"
import "core:sync"

BRIDGE_SIZE_NOT_LEADER :: i32(7)
BRIDGE_SIZE_REJECTED :: i32(8)
Instance_Size_Mode :: enum u8 { Fixed, Taking, Following }
Pane_Geometry :: struct { rows, columns, cell_width, cell_height: u16 }

// Presentation intent, not a second geometry authority. Only the Instance may
// accept a resize. One pending task bounds drag traffic; only ACKed sizes count.
Instance_Size_Control :: struct {
    mode: Instance_Size_Mode,
    generation: u64,
    pending: bool,
    applied: Pane_Geometry,
}

set_size_intent :: proc(state: ^Instance_Size_Control, take: bool) {
    state.generation += 1
    state.mode = take ? .Taking : .Fixed
    state.applied = {}
    // A request already on the wire cannot be unsent. Its completion still
    // retires pending, but never re-enables an intent changed after admission.
}

size_task_current :: proc(state: ^Instance_Size_Control, task: Control_Task) -> bool {
    return state.mode != .Fixed && state.generation == task.generation
}

next_size_task :: proc(state: ^Instance_Size_Control, geometry: Pane_Geometry) -> (Control_Task, bool) {
    if state.mode == .Fixed || state.pending || geometry == state.applied ||
       geometry.rows == 0 || geometry.columns == 0 || geometry.cell_width == 0 || geometry.cell_height == 0 {
        return {}, false
    }
    state.pending = true
    return {kind = .Resize, action = state.mode == .Taking ? u8(1) : u8(0),
            rows = geometry.rows, columns = geometry.columns,
            cell_width = geometry.cell_width, cell_height = geometry.cell_height,
            generation = state.generation}, true
}

finish_size_task :: proc(state: ^Instance_Size_Control, task: Control_Task, code: i32) -> bool {
    state.pending = false
    if !size_task_current(state, task) do return false
    if code != 0 {
        state.mode = .Fixed
        return false
    }
    state.applied = {task.rows, task.columns, task.cell_width, task.cell_height}
    state.mode = .Following
    return true
}

size_action_enabled :: proc(view: ^Instance_View, action: App_Action) -> bool {
    if view == nil || !instance_interactive(view) do return false
    sync.mutex_lock(&view.mutex)
    defer sync.mutex_unlock(&view.mutex)
    if action == .Take_Size_Control do return view.size_control.mode != .Taking
    return view.size_control.mode != .Fixed
}

pane_geometry :: proc(width, height, scale: f32, cell_width, cell_height: u16) -> (Pane_Geometry, bool) {
    if !valid_canvas_scale(scale) || width <= 0 || height <= 0 ||
       math.is_nan(width) || math.is_nan(height) || math.is_inf(width) || math.is_inf(height) ||
       cell_width == 0 || cell_height == 0 {
        return {}, false
    }
    columns := math.floor(width * scale / f32(cell_width))
    rows := math.floor(height * scale / f32(cell_height))
    return {u16(clamp(rows, 1, f32(render_maximum_rows()))),
            u16(clamp(columns, 1, f32(render_maximum_columns()))), cell_width, cell_height}, true
}

resize_instance_to_pane :: proc(app: ^App, view: ^Instance_View, width, height: f32) {
    if view == nil || view.control == nil || !instance_interactive(view) do return
    sync.mutex_lock(&view.mutex)
    enabled := view.size_control.mode != .Fixed
    sync.mutex_unlock(&view.mutex)
    if !enabled || !ensure_canvas(app, view) do return
    geometry, ok := pane_geometry(width, height, canvas_scale_value(view),
                                  render_cell_width(view.canvas), render_cell_height(view.canvas))
    if !ok do return
    sync.mutex_lock(&view.mutex)
    task, needed := next_size_task(&view.size_control, geometry)
    current_columns := view.columns
    sync.mutex_unlock(&view.mutex)
    if !needed do return
    if history_columns_changed(current_columns, geometry.columns) do _ = return_history_live(view)
    if queue_control(view, task) != 0 {
        sync.mutex_lock(&view.mutex)
        _ = finish_size_task(&view.size_control, task, 2)
        sync.mutex_unlock(&view.mutex)
    }
}
