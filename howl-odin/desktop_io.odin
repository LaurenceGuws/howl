package main

import "core:c"
import "core:sync"
import "core:thread"
import "core:time"
import SDL "vendor:sdl3"

// A pane owns one ordered command worker. Admission is not an acknowledgement:
// failures are published explicitly and no queued input is replayed on reconnect.
// Main-thread code never calls a network operation on the control handle.
BRIDGE_QUERY_DECLINED :: i32(6)
CONTROL_QUEUE_ITEMS :: 128
CONTROL_QUEUE_BYTES :: 128 * 1024
CONTROL_PAYLOAD_BYTES :: 65535

Control_Kind :: enum u8 { Text, Paste, Named, Unicode, Mouse, Focus, Resize, Expand, Extract, Link, Clipboard }
Control_Task :: struct {
    kind: Control_Kind,
    key, action, modifiers, button, buttons, alternate: u8,
    scalar, pixel_x, pixel_y, history: u32,
    row, end_row: i32,
    column, end_column, columns, rows, cell_width, cell_height: u16,
    generation, request: u64,
    payload: []u8,
}
Control_Result :: struct {
    kind: Control_Kind,
    generation, request: u64,
    range: Selection_Range_Info,
    bytes: []u8,
    length: int,
    code: i32,
}

connect_view_channel :: proc(view: ^Session_View, token: rawptr) -> rawptr {
    endpoint := session_endpoint(view)
    diagnostic: [160]u8
    count: c.size_t
    handle := create(desktop_io_runtime, token, raw_data(endpoint), c.size_t(len(endpoint)),
                     raw_data(diagnostic[:]), c.size_t(len(diagnostic)), &count)
    if handle == nil {
        publish_initial_error(view, string(diagnostic[:int(count)]))
        notify_session_update()
    }
    return handle
}

control_queue_push_locked :: proc(view: ^Session_View, task: Control_Task) -> bool {
    if view.worker_stop || view.control_failed || view.io_failed || view.control_count >= CONTROL_QUEUE_ITEMS ||
       len(task.payload) > CONTROL_PAYLOAD_BYTES || view.control_bytes + len(task.payload) > CONTROL_QUEUE_BYTES {
        return false
    }
    index := (view.control_head + view.control_count) % CONTROL_QUEUE_ITEMS
    view.control_tasks[index] = task
    view.control_count += 1
    view.control_bytes += len(task.payload)
    if view.control_notice_len != 0 {
        view.control_notice_len = 0
        view.ui_dirty = true
    }
    return true
}

control_queue_pop_locked :: proc(view: ^Session_View) -> (Control_Task, bool) {
    if view.control_count == 0 do return {}, false
    task := view.control_tasks[view.control_head]
    view.control_tasks[view.control_head] = {}
    view.control_head = (view.control_head + 1) % CONTROL_QUEUE_ITEMS
    view.control_count -= 1
    view.control_bytes -= len(task.payload)
    return task, true
}

queue_control :: proc(view: ^Session_View, task: Control_Task) -> i32 {
    if view == nil || view.control == nil do return 1
    sync.mutex_lock(&view.mutex)
    accepted := control_queue_push_locked(view, task)
    sync.mutex_unlock(&view.mutex)
    if !accepted {
        sync.mutex_lock(&view.mutex)
        view.control_failed = true
        sync.mutex_unlock(&view.mutex)
        if view.control_interrupt != nil do _ = interrupt_cancel(view.control_interrupt)
        publish_initial_error(view, "Input queue full/closed; new operation rejected, prior delivery may be incomplete")
        return 2
    }
    sync.cond_signal(&view.control_cond)
    return 0
}

queue_text :: proc(view: ^Session_View, data: [^]u8, length: c.size_t, paste: bool = false) -> i32 {
    if length == 0 || length > CONTROL_PAYLOAD_BYTES do return 1
    bytes := make([]u8, int(length))
    if bytes == nil do return 2
    copy(bytes, data[:int(length)])
    result := queue_control(view, Control_Task{kind = paste ? .Paste : .Text, payload = bytes})
    if result != 0 do delete(bytes)
    return result
}

queue_named_key :: proc(view: ^Session_View, key, action, modifiers: u8) -> i32 {
    return queue_control(view, {kind = .Named, key = key, action = action, modifiers = modifiers})
}
queue_unicode_key :: proc(view: ^Session_View, scalar: u32, action, modifiers: u8) -> i32 {
    return queue_control(view, {kind = .Unicode, scalar = scalar, action = action, modifiers = modifiers})
}
queue_mouse :: proc(view: ^Session_View, kind, button, modifiers, buttons: u8, row: i32, column: u16, pixels: u8, x, y: u32) -> i32 {
    return queue_control(view, {kind = .Mouse, action = kind, button = button, modifiers = modifiers,
                               buttons = buttons, row = row, column = column, alternate = pixels, pixel_x = x, pixel_y = y})
}
queue_focus :: proc(view: ^Session_View, focus: u8) -> i32 {
    return queue_control(view, {kind = .Focus, action = focus})
}
queue_resize :: proc(view: ^Session_View, rows, columns, cell_width, cell_height: u16) -> i32 {
    return queue_control(view, {kind = .Resize, rows = rows, columns = columns, cell_width = cell_width, cell_height = cell_height})
}

execute_control :: proc(handle: rawptr, task: Control_Task, result: ^Control_Result) -> i32 {
    switch task.kind {
    case .Text: return send_text(handle, raw_data(task.payload), c.size_t(len(task.payload)))
    case .Paste: return send_paste(handle, raw_data(task.payload), c.size_t(len(task.payload)))
    case .Named: return send_named_key(handle, task.key, task.action, task.modifiers)
    case .Unicode: return send_unicode_key(handle, task.scalar, task.action, task.modifiers)
    case .Mouse: return send_mouse(handle, task.action, task.button, task.modifiers, task.buttons, task.row, task.column, task.alternate, task.pixel_x, task.pixel_y)
    case .Clipboard: return 1 // Serialized platform handoff is handled before this dispatcher.
    case .Focus: return send_focus(handle, task.action)
    case .Resize: return send_resize(handle, task.rows, task.columns, task.cell_width, task.cell_height)
    case .Expand:
        return selection_expand(handle, task.action, task.history, task.row, task.column, task.columns, task.alternate, &result.range)
    case .Extract, .Link:
        capacity := task.kind == .Extract ? SELECTION_TEXT_BYTES : HYPERLINK_URI_BYTES
        result.bytes = make([]u8, capacity + 1)
        if result.bytes == nil do return 3
        count: c.size_t
        code: i32
        if task.kind == .Extract {
            code = selection_extract(handle, task.row, task.column, task.end_row, task.end_column,
                                     task.columns, task.alternate, raw_data(result.bytes), c.size_t(capacity), &count)
        } else {
            code = hyperlink_copy(handle, task.history, task.row, task.column, task.columns, task.alternate,
                                  raw_data(result.bytes), c.size_t(capacity), &count)
        }
        result.length = int(count)
        result.bytes[result.length] = 0
        return code
    }
    return 1
}

control_session :: proc(data: rawptr) {
    view := (^Session_View)(data)
    handle := connect_view_channel(view, view.control_interrupt)
    sync.mutex_lock(&view.mutex)
    view.control_pending_handle = handle
    view.control_connect_done = true
    view.control_failed = handle == nil
    sync.mutex_unlock(&view.mutex)
    notify_session_update()
    if handle == nil do return
    // Handle remains owned by this pane until main cancels and joins the worker.
    for {
        sync.mutex_lock(&view.mutex)
        for !view.worker_stop && (view.control_count == 0 || view.control_result_ready) {
            sync.cond_wait(&view.control_cond, &view.mutex)
        }
        if view.worker_stop { sync.mutex_unlock(&view.mutex); break }
        task, ok := control_queue_pop_locked(view)
        sync.mutex_unlock(&view.mutex)
        if !ok do continue
        result := Control_Result{kind = task.kind, generation = task.generation, request = task.request}
        clipboard_failed := false
        if task.kind == .Clipboard {
            // Paste immediately after asynchronous Copy waits for that exact
            // copy's platform completion, rather than sending the old clipboard.
            sync.mutex_lock(&view.mutex)
            view.control_result = result
            view.control_result_ready = true
            sync.mutex_unlock(&view.mutex)
            notify_session_update()
            sync.mutex_lock(&view.mutex)
            for !view.worker_stop && view.control_result_ready do sync.cond_wait(&view.control_cond, &view.mutex)
            reply := view.clipboard_reply
            view.clipboard_reply = nil
            reply_code := view.clipboard_reply_code
            stopped := view.worker_stop
            sync.mutex_unlock(&view.mutex)
            if stopped { if reply != nil do delete(reply); break }
            if reply_code != 0 {
                clipboard_failed = true
                result.code = BRIDGE_QUERY_DECLINED
                publish_control_notice(view, "Paste not sent: preceding copy did not complete")
            } else if len(reply) != 0 {
                result.code = send_paste(handle, raw_data(reply), c.size_t(len(reply)))
            }
            if reply != nil do delete(reply)
        } else {
            result.code = execute_control(handle, task, &result)
        }
        if task.payload != nil do delete(task.payload)
        fatal := control_failure_is_fatal(task.kind, result.code)
        if result.code != 0 && !fatal && !clipboard_failed {
            message: [160]u8
            count: c.size_t
            copy_error(handle, raw_data(message[:]), c.size_t(len(message)), &count)
            publish_control_notice(view, string(message[:int(count)]))
        }
        if fatal {
            if !clipboard_failed do publish_bridge_error(view, handle)
            sync.mutex_lock(&view.mutex)
            view.control_failed = true
            // A failed mutating transaction is not permission to replay it.
            // Keep the exact bridge error after an explicit delivery warning.
            if task.kind != .Expand && task.kind != .Extract && task.kind != .Link {
                original := view.error
                original_len := view.error_len
                prefix := "Input failed/unconfirmed; not replayed: "
                count := min(original_len, len(view.error) - len(prefix))
                copy(view.error[:], transmute([]u8)prefix)
                copy(view.error[len(prefix):][:count], original[:count])
                view.error_len = len(prefix) + count
            }
            sync.mutex_unlock(&view.mutex)
        }
        if task.kind == .Expand || task.kind == .Extract || task.kind == .Link {
            sync.mutex_lock(&view.mutex)
            view.control_result = result
            view.control_result_ready = true
            sync.mutex_unlock(&view.mutex)
            notify_session_update()
        }
        if fatal { notify_session_update(); break }
    }
}

// Called only by the graphical thread. Result buffers transfer here once; a
// closed/replaced pane cannot deliver a stale clipboard, selection or URL action.
apply_control_completions :: proc(app: ^App) {
    for tab_index in 0..<app.tab_count {
        for view in app.tabs[tab_index].panes {
            if view == nil do continue
            sync.mutex_lock(&view.mutex)
            if view.control_connect_done && view.control == nil {
                view.control = view.control_pending_handle
                view.ui_dirty = true
            }
            ready := view.control_result_ready
            result := view.control_result
            current := control_result_current(result.code, result.generation, view.selection_generation, active_session_view(app) == view)
            copy_current := result.code == 0 && view.copy_pending &&
                            clipboard_request_current(result.request, app.clipboard_request, view.copy_pending_request)
            copied := view.copy_completed && clipboard_request_current(result.request, app.clipboard_request, view.copy_completed_request)
            sync.mutex_unlock(&view.mutex)
            if !ready do continue
            copy_applied := false
            clipboard_reply: []u8
            clipboard_code: i32
            if result.kind == .Clipboard {
                if copied && SDL.HasClipboardText() {
                    if raw := SDL.GetClipboardText(); raw != nil {
                        text := string(cstring(raw))
                        if len(text) <= CONTROL_PAYLOAD_BYTES {
                            clipboard_reply = make([]u8, len(text))
                            copy(clipboard_reply, transmute([]u8)text)
                        } else { clipboard_code = 2 }
                        SDL.free(rawptr(raw))
                    } else { clipboard_code = 2 }
                } else { clipboard_code = 2 }
            } else if result.kind == .Extract {
                if copy_current && result.length > 0 && SDL.SetClipboardText(cstring(raw_data(result.bytes))) {
                    copy_applied = true
                    // Typing or a newer selection can retire the visual range
                    // without changing the earlier explicit Copy request.
                    if current do clear_selection(view)
                }
            } else if current {
                switch result.kind {
                case .Expand: _ = apply_selection_range(view, result.range)
                case .Link:
                    if result.length > 0 do _ = open_platform_browser_uri(string(result.bytes[:result.length]))
                case .Text, .Paste, .Named, .Unicode, .Mouse, .Focus, .Resize, .Clipboard, .Extract:
                }
            }
            if result.bytes != nil do delete(result.bytes)
            sync.mutex_lock(&view.mutex)
            if result.kind == .Extract {
                view.copy_completed = copy_applied
                view.copy_completed_request = result.request
                if view.copy_pending_request == result.request do view.copy_pending = false
            }
            if result.kind == .Clipboard {
                view.clipboard_reply = clipboard_reply
                view.clipboard_reply_code = clipboard_code
            }
            view.control_result = {}
            view.control_result_ready = false
            view.ui_dirty = true
            sync.mutex_unlock(&view.mutex)
            sync.cond_signal(&view.control_cond)
        }
    }
}

control_result_current :: proc(code: i32, result_generation, current_generation: u64, view_is_active: bool) -> bool {
    return code == 0 && result_generation == current_generation && view_is_active
}

// A worker wake can mean only "new work is available". Schedule it and paint
// only a newly accepted frame or changed UI metadata, not the old frame followed
// by the new one. Input/resize/expose events still invalidate normally.
service_desktop_io :: proc(app: ^App) -> bool {
    changed := false
    if app.active_tab >= 0 && app.active_tab < app.tab_count {
        width, height: c.int
        _ = SDL.GetWindowSize(app.window, &width, &height)
        tab := &app.tabs[app.active_tab]
        layout := pane_layout(tab, terminal_inset(f32(width), f32(height)))
        for i in 0..<layout.entry_count {
            view := tab_pane_view(tab, layout.entries[i].pane_index)
            if view == nil do continue
            before := view.canvas_session_revision
            old_history := view.canvas_history_offset
            old_error := view.canvas_error_len
            had_canvas := view.canvas != nil
            _ = update_canvas(app, view)
            changed = changed || before != view.canvas_session_revision || old_history != view.canvas_history_offset ||
                      old_error != view.canvas_error_len || had_canvas != (view.canvas != nil)
        }
    }
    for i in 0..<app.tab_count {
        for view in app.tabs[i].panes {
            if view == nil do continue
            sync.mutex_lock(&view.mutex)
            changed = changed || view.ui_dirty
            view.ui_dirty = false
            sync.mutex_unlock(&view.mutex)
        }
    }
    return changed
}

// Clipboard requests have their own application-wide order. A visual selection
// can be cleared by later typing, but an older tab's late Copy cannot overwrite
// a newer Copy request from another tab.
clipboard_request_current :: proc(request, newest_request, owned_request: u64) -> bool {
    return request != 0 && request == newest_request && request == owned_request
}

control_failure_is_fatal :: proc(kind: Control_Kind, code: i32) -> bool {
    if code == 0 do return false
    query := kind == .Expand || kind == .Extract || kind == .Link || kind == .Clipboard
    return !(query && code == BRIDGE_QUERY_DECLINED)
}

publish_control_notice :: proc(view: ^Session_View, message: string) {
    sync.mutex_lock(&view.mutex)
    view.control_notice_len = min(len(message), len(view.control_notice))
    copy(view.control_notice[:view.control_notice_len], transmute([]u8)message[:view.control_notice_len])
    view.ui_dirty = true
    sync.mutex_unlock(&view.mutex)
    notify_session_update()
}

draw_control_notice :: proc(app: ^App, view: ^Session_View, pane: SDL.FRect) {
    sync.mutex_lock(&view.mutex)
    bytes := view.control_notice
    count := view.control_notice_len
    failed := view.io_failed || view.control_failed
    sync.mutex_unlock(&view.mutex)
    if count == 0 || failed do return
    box := SDL.FRect{pane.x + 6, pane.y + pane.h - 28, max(f32(0), pane.w - 22), 22}
    clip := SDL.Rect{c.int(box.x), c.int(box.y), c.int(box.w), c.int(box.h)}
    _ = SDL.SetRenderClipRect(app.renderer, &clip)
    draw_fill(app.renderer, box, palette.title_bg)
    draw_text(app, app.ui_font, string(bytes[:count]), box.x + 5, box.y + 3, palette.text_muted)
    _ = SDL.SetRenderClipRect(app.renderer, nil)
}
