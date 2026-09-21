package main

import "core:c"
import "core:sync"
import "core:thread"

// One pending/prepared frame per renderer. CPU composition and exact resource
// fetching stay on this worker; the main thread alone consumes SDL uploads.
// The worker cannot overwrite a prepared frame before main acknowledges it.
Render_Work :: struct {
    route_kind: Bridge_Route_Kind,
    endpoint: [PROFILE_ENDPOINT_BYTES]u8,
    endpoint_len: int,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    font, fallback, secondary: [1024]u8,
    font_len, fallback_len, secondary_len: int,
    pixels: u16,
    interrupt: rawptr,
    handle: rawptr,
    offered_view: rawptr,
    worker: ^thread.Thread,
    mutex: sync.Mutex,
    cond: sync.Cond,
    stop, created, failed, pending, ready, busy: bool,
    history: u32,
    history_generation: u64,
    code: i32,
    error: [160]u8,
    error_len: int,
}

render_worker :: proc(data: rawptr) {
    work := (^Render_Work)(data)
    diagnostic: [160]u8
    count: c.size_t
    handle := render_create(desktop_io_runtime, work.interrupt, u8(work.route_kind),
                            raw_data(work.endpoint[:]), c.size_t(work.endpoint_len), work.server_id, work.session_id, work.instance_id,
                            raw_data(work.font[:]), c.size_t(work.font_len),
                            raw_data(work.fallback[:]), c.size_t(work.fallback_len),
                            raw_data(work.secondary[:]), c.size_t(work.secondary_len), work.pixels,
                            raw_data(diagnostic[:]), c.size_t(len(diagnostic)), &count)
    sync.mutex_lock(&work.mutex)
    work.handle = handle
    work.created = true
    work.failed = handle == nil
    work.error_len = int(count)
    copy(work.error[:int(count)], diagnostic[:int(count)])
    sync.mutex_unlock(&work.mutex)
    notify_instance_update()
    if handle == nil do return
    for {
        sync.mutex_lock(&work.mutex)
        for !work.stop && (!work.pending || work.ready) {
            sync.cond_wait(&work.cond, &work.mutex)
        }
        if work.stop { sync.mutex_unlock(&work.mutex); break }
        history := work.history
        offered := work.offered_view
        work.offered_view = nil
        work.pending = false
        work.busy = true
        sync.mutex_unlock(&work.mutex)
        code: i32 = 9
        if offered != nil {
            code = render_prepare_view(handle, offered)
            view_destroy(offered)
        }
        if code == 9 do code = render_prepare(handle, history)
        sync.mutex_lock(&work.mutex)
        work.busy = false
        work.ready = true
        work.code = code
        work.failed = code != 0
        sync.mutex_unlock(&work.mutex)
        notify_instance_update()
        if code != 0 do break
    }
}

start_render_worker :: proc(app: ^App, view: ^Instance_View, pixels: u16) -> ^Render_Work {
    work := new(Render_Work)
    if work == nil do return nil
    endpoint := instance_endpoint(view)
    font := terminal_primary_font(&app.terminal_fonts)
    fallback := terminal_fallback_font(&app.terminal_fonts)
    secondary := terminal_secondary_fallback_font(&app.terminal_fonts)
    if len(endpoint) >= len(work.endpoint) || len(font) >= len(work.font) ||
       len(fallback) >= len(work.fallback) || len(secondary) >= len(work.secondary) {
        free(work)
        return nil
    }
    work.route_kind = view.route_kind
    copy(work.endpoint[:], transmute([]u8)endpoint); work.endpoint_len = len(endpoint)
    work.server_id = view.server_id
    work.session_id = view.session_id
    work.instance_id = view.instance_id
    copy(work.font[:], transmute([]u8)font); work.font_len = len(font)
    copy(work.fallback[:], transmute([]u8)fallback); work.fallback_len = len(fallback)
    copy(work.secondary[:], transmute([]u8)secondary); work.secondary_len = len(secondary)
    work.pixels = pixels
    work.interrupt = interrupt_create()
    if work.interrupt == nil { free(work); return nil }
    work.worker = thread.create_and_start_with_data(rawptr(work), render_worker, name = "howl-odin-render")
    if work.worker == nil { interrupt_destroy(work.interrupt); free(work); return nil }
    return work
}

stop_render_worker :: proc(work: ^Render_Work) {
    if work == nil do return
    sync.mutex_lock(&work.mutex)
    work.stop = true
    sync.mutex_unlock(&work.mutex)
    _ = interrupt_cancel(work.interrupt)
    sync.cond_signal(&work.cond)
    if work.worker != nil do thread.destroy(work.worker)
    if work.offered_view != nil do view_destroy(work.offered_view)
    if work.handle != nil do render_destroy(work.handle)
    interrupt_destroy(work.interrupt)
    free(work)
}

request_render :: proc(work: ^Render_Work, view: ^Instance_View, revision: u64, history: u32, history_generation: u64) {
    if work == nil || revision == 0 do return
    sync.mutex_lock(&work.mutex)
    if !work.stop && !work.failed && !work.ready && !work.busy && !work.pending {
        // Lock order is render job -> pane. Observer only takes the pane lock;
        // no connection or resource fetching is shared between these workers.
        if history == 0 {
            sync.mutex_lock(&view.mutex)
            work.offered_view = view.reusable_view
            view.reusable_view = nil
            sync.mutex_unlock(&view.mutex)
        }
        work.history_generation = history_generation
        work.history = history
        work.pending = true
    }
    sync.mutex_unlock(&work.mutex)
    sync.cond_signal(&work.cond)
}
