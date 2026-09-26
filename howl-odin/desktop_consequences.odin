package main

import "core:c"
import "core:sync"
import "core:thread"
import SDL "vendor:sdl3"

MAX_CONSEQUENCE_OWNERS :: MAX_TABS * MAX_PANES_PER_TAB
CONSEQUENCE_ENDPOINT_BYTES :: PROFILE_ENDPOINT_BYTES
CONSEQUENCE_PAYLOAD_SCRATCH :: 4096

Desktop_Consequence_Action :: enum u8 {
	Consume,
	Attention,
	Reply_Clipboard_Empty,
	Reply_Pointer_Default,
	Reply_Color_Dark,
	Reply_Container_Screen,
	Reply_Container_Decline,
}

Consequence_Owner :: struct {
	route_kind: Bridge_Route_Kind,
	endpoint: [CONSEQUENCE_ENDPOINT_BYTES]u8,
	endpoint_len: int,
	server_id: u64,
	session_id: u64,
	instance_id: u64,
	handle: rawptr,
    interrupt: rawptr,
	client_id: u64,
	worker: ^thread.Thread,
	mutex: sync.Mutex,
	cond: sync.Cond,
	stop: bool,
	wake: bool,
	seen: bool,
	attention_pending: bool,
	authority_lost: bool,
	rows: u16,
	columns: u16,
	error: [160]u8,
	error_len: int,
}

consequence_endpoint :: proc(owner: ^Consequence_Owner) -> string {
	if owner == nil || owner.endpoint_len <= 0 || owner.endpoint_len > len(owner.endpoint) do return ""
	return string(owner.endpoint[:owner.endpoint_len])
}

consequence_action_for :: proc(info: Consequence_Info) -> Desktop_Consequence_Action {
	kind := Bridge_Consequence_Kind(info.kind)
	switch kind {
	case .Bell:
		return .Attention
	case .Notification:
		// Message is caller-neutral and currently consumed silently. Focus-steal
		// and request-attention become modest desktop attention, never focus theft.
		if info.metadata[0] == 2 || info.metadata[0] == 3 do return .Attention
		return .Consume
	case .Clipboard:
		if info.reply_required != 0 do return .Reply_Clipboard_Empty
	case .Pointer_Shape:
		if info.reply_required != 0 do return .Reply_Pointer_Default
	case .Color_Preference:
		if info.reply_required != 0 do return .Reply_Color_Dark
	case .Container:
		if info.reply_required != 0 {
			if info.metadata[0] == 12 do return .Reply_Container_Screen
			return .Reply_Container_Decline
		}
	case .None, .File_Transfer, .Drag_Drop, .Media_Copy, .Legacy_Control, .Dcs, .String_Control:
	}
	return .Consume
}

write_u32_be :: proc(output: []u8, value: u32) -> bool {
	if len(output) < 4 do return false
	output[0] = u8(value >> 24)
	output[1] = u8(value >> 16)
	output[2] = u8(value >> 8)
	output[3] = u8(value)
	return true
}

copy_consequence_error :: proc(owner: ^Consequence_Owner) {
	if owner == nil || owner.handle == nil do return
	message: [160]u8
	count: c.size_t
	consequence_copy_error(owner.handle, raw_data(message[:]), c.size_t(len(message)), &count)
	sync.mutex_lock(&owner.mutex)
	n := min(int(count), len(owner.error))
	copy(owner.error[:n], message[:n])
	owner.error_len = n
	sync.mutex_unlock(&owner.mutex)
}

consequence_reply_empty :: proc(owner: ^Consequence_Owner, generation: u64, kind: Bridge_Consequence_Reply) -> bool {
	dummy: [1]u8
	return consequence_reply(owner.handle, generation, u8(kind), raw_data(dummy[:]), 0) == 0
}

consequence_reply_bytes :: proc(owner: ^Consequence_Owner, generation: u64, kind: Bridge_Consequence_Reply, body: []u8) -> bool {
	if len(body) == 0 do return consequence_reply_empty(owner, generation, kind)
	return consequence_reply(owner.handle, generation, u8(kind), raw_data(body), c.size_t(len(body))) == 0
}

apply_consequence_action :: proc(owner: ^Consequence_Owner, info: Consequence_Info) -> bool {
	if owner == nil || owner.handle == nil || info.generation == 0 do return false
	action := consequence_action_for(info)
	switch action {
	case .Consume:
		if consequence_consume(owner.handle, info.generation) != 0 {
			copy_consequence_error(owner)
			return false
		}
	case .Attention:
		if consequence_consume(owner.handle, info.generation) != 0 {
			copy_consequence_error(owner)
			return false
		}
		sync.mutex_lock(&owner.mutex)
		owner.attention_pending = true
		sync.mutex_unlock(&owner.mutex)
		notify_instance_update()
	case .Reply_Clipboard_Empty:
		if !consequence_reply_empty(owner, info.generation, .Clipboard) {
			copy_consequence_error(owner)
			return false
		}
	case .Reply_Pointer_Default:
		body := []u8{'d','e','f','a','u','l','t'}
		if !consequence_reply_bytes(owner, info.generation, .Pointer_Shape, body) {
			copy_consequence_error(owner)
			return false
		}
	case .Reply_Color_Dark:
		body := []u8{1}
		if !consequence_reply_bytes(owner, info.generation, .Color_Preference, body) {
			copy_consequence_error(owner)
			return false
		}
	case .Reply_Container_Screen:
		sync.mutex_lock(&owner.mutex)
		rows, columns := owner.rows, owner.columns
		sync.mutex_unlock(&owner.mutex)
		body: [8]u8
		_ = write_u32_be(body[0:4], u32(rows))
		_ = write_u32_be(body[4:8], u32(columns))
		if !consequence_reply_bytes(owner, info.generation, .Container_Screen_Cells, body[:]) {
			copy_consequence_error(owner)
			return false
		}
	case .Reply_Container_Decline:
		if !consequence_reply_empty(owner, info.generation, .Container_Decline) {
			copy_consequence_error(owner)
			return false
		}
	}
	return true
}

process_consequence_owner :: proc(owner: ^Consequence_Owner) {
	if owner == nil || owner.handle == nil do return
	payload: [CONSEQUENCE_PAYLOAD_SCRATCH]u8
	for {
		info: Consequence_Info
		copied: c.size_t
		if consequence_observe(
			owner.handle,
			&info,
			raw_data(payload[:]),
			c.size_t(len(payload)),
			&copied,
		) != 0 {
			copy_consequence_error(owner)
			return
		}
		if info.authority_client_id == 0 {
			if consequence_acquire(owner.handle) != 0 {
				copy_consequence_error(owner)
				return
			}
			continue
		}
		if info.authority_client_id != owner.client_id {
			sync.mutex_lock(&owner.mutex)
			owner.authority_lost = true
			sync.mutex_unlock(&owner.mutex)
			return
		}
		sync.mutex_lock(&owner.mutex)
		owner.authority_lost = false
		owner.error_len = 0
		sync.mutex_unlock(&owner.mutex)
		if Bridge_Consequence_Kind(info.kind) == .None {
			return
		}
		if !apply_consequence_action(owner, info) {
			return
		}
	}
}

consequence_owner_worker :: proc(data: rawptr) {
	owner := (^Consequence_Owner)(data)
    endpoint := consequence_endpoint(owner)
    diagnostic: [160]u8
    count: c.size_t
    owner.handle = consequence_create(desktop_io_runtime, owner.interrupt, u8(owner.route_kind),
                                       raw_data(endpoint), c.size_t(len(endpoint)), owner.server_id, owner.session_id, owner.instance_id,
                                       raw_data(diagnostic[:]), c.size_t(len(diagnostic)), &count)
    if owner.handle == nil {
        sync.mutex_lock(&owner.mutex)
        owner.error_len = int(count)
        copy(owner.error[:int(count)], diagnostic[:int(count)])
        sync.mutex_unlock(&owner.mutex)
        notify_instance_update()
        return
    }
    owner.client_id = consequence_client_id(owner.handle)
	for {
		sync.mutex_lock(&owner.mutex)
		for !owner.stop && !owner.wake {
			sync.cond_wait(&owner.cond, &owner.mutex)
		}
		stop := owner.stop
		owner.wake = false
		sync.mutex_unlock(&owner.mutex)
		if stop do break
		process_consequence_owner(owner)
	}
}

create_consequence_owner :: proc(view: ^Instance_View, rows, columns: u16) -> ^Consequence_Owner {
    if view == nil do return nil
    endpoint := instance_endpoint(view)
    if len(endpoint) >= CONSEQUENCE_ENDPOINT_BYTES || (view.route_kind != .Local && len(endpoint) == 0) do return nil
    owner := new(Consequence_Owner)
    if owner == nil do return nil
    owner^ = Consequence_Owner{
        route_kind = view.route_kind,
        server_id = view.server_id,
        session_id = view.session_id,
        instance_id = view.instance_id,
        rows = rows,
        columns = columns,
        wake = true,
    }
    copy(owner.endpoint[:len(endpoint)], transmute([]u8)endpoint)
    owner.endpoint_len = len(endpoint)
    owner.interrupt = interrupt_create()
    if owner.interrupt == nil { free(owner); return nil }
    owner.worker = thread.create_and_start_with_data(rawptr(owner), consequence_owner_worker, name = "howl-odin-host-policy")
    if owner.worker == nil { interrupt_destroy(owner.interrupt); free(owner); return nil }
    return owner
}

destroy_consequence_owner :: proc(owner: ^Consequence_Owner) {
	if owner == nil do return
	sync.mutex_lock(&owner.mutex)
	owner.stop = true
	sync.mutex_unlock(&owner.mutex)
    if owner.interrupt != nil do _ = interrupt_cancel(owner.interrupt)
	sync.cond_signal(&owner.cond)
	if owner.worker != nil {
		thread.destroy(owner.worker)
		owner.worker = nil
	}
	if owner.handle != nil {
		consequence_destroy(owner.handle)
		owner.handle = nil
	}
    if owner.interrupt != nil do interrupt_destroy(owner.interrupt)
	free(owner)
}

find_consequence_owner :: proc(app: ^App, view: ^Instance_View) -> ^Consequence_Owner {
	if app == nil || view == nil do return nil
    endpoint := instance_endpoint(view)
	if view.route_kind != .Local && len(endpoint) == 0 do return nil
	for index in 0..<app.consequence_owner_count {
		owner := app.consequence_owners[index]
        if owner != nil && owner.route_kind == view.route_kind &&
           owner.server_id == view.server_id && owner.session_id == view.session_id && owner.instance_id == view.instance_id &&
           consequence_endpoint(owner) == endpoint {
            return owner
        }
	}
	return nil
}

wake_consequence_owner :: proc(owner: ^Consequence_Owner) {
	if owner == nil do return
	sync.mutex_lock(&owner.mutex)
	if !owner.stop do owner.wake = true
	sync.mutex_unlock(&owner.mutex)
	sync.cond_signal(&owner.cond)
}

wake_consequence_owners :: proc(app: ^App) {
	if app == nil do return
	for index in 0..<app.consequence_owner_count do wake_consequence_owner(app.consequence_owners[index])
}

reconcile_consequence_owners :: proc(app: ^App) {
	if app == nil do return
	for index in 0..<app.consequence_owner_count {
		if app.consequence_owners[index] != nil do app.consequence_owners[index].seen = false
	}
	for tab_index in 0..<app.tab_count {
		for view in app.tabs[tab_index].panes {
			if view == nil || view.control == nil || !instance_interactive(view) do continue
			endpoint := instance_endpoint(view)
			if len(endpoint) == 0 do continue
			owner := find_consequence_owner(app, view)
			if owner == nil {
				if app.consequence_owner_count >= MAX_CONSEQUENCE_OWNERS do continue
				sync.mutex_lock(&view.mutex)
				rows, columns := view.rows, view.columns
				sync.mutex_unlock(&view.mutex)
				owner = create_consequence_owner(view, rows, columns)
				if owner == nil do continue
				app.consequence_owners[app.consequence_owner_count] = owner
				app.consequence_owner_count += 1
			}
			owner.seen = true
			sync.mutex_lock(&view.mutex)
			rows, columns := view.rows, view.columns
			sync.mutex_unlock(&view.mutex)
			sync.mutex_lock(&owner.mutex)
			owner.rows = rows
			owner.columns = columns
			sync.mutex_unlock(&owner.mutex)
		}
	}
	index := 0
	for index < app.consequence_owner_count {
		owner := app.consequence_owners[index]
		if owner != nil && owner.seen {
			index += 1
			continue
		}
		destroy_consequence_owner(owner)
		for shift in index..<app.consequence_owner_count - 1 {
			app.consequence_owners[shift] = app.consequence_owners[shift + 1]
		}
		app.consequence_owner_count -= 1
		app.consequence_owners[app.consequence_owner_count] = nil
	}
}

destroy_consequence_owners :: proc(app: ^App) {
	if app == nil do return
	for app.consequence_owner_count > 0 {
		app.consequence_owner_count -= 1
		destroy_consequence_owner(app.consequence_owners[app.consequence_owner_count])
		app.consequence_owners[app.consequence_owner_count] = nil
	}
}

apply_desktop_attention :: proc(app: ^App) -> bool {
	if app == nil || app.window == nil do return false
	attention := false
	for index in 0..<app.consequence_owner_count {
		owner := app.consequence_owners[index]
		if owner == nil do continue
		sync.mutex_lock(&owner.mutex)
		if owner.attention_pending {
			attention = true
			owner.attention_pending = false
		}
		sync.mutex_unlock(&owner.mutex)
	}
	if !attention do return false
	flags := SDL.GetWindowFlags(app.window)
	if .INPUT_FOCUS in flags do return true
	return SDL.FlashWindow(app.window, .BRIEFLY)
}
