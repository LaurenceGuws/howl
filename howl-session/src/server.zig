//! Runs one node-local shared Howl session behind one Unix-domain socket.
//!
//! One process owns one PTY, one VT, and one socket. Clients are bounded
//! observers/controllers. Socket output is always nonblocking and each client
//! owns at most one materialized response, so an observer cannot pace PTY/VT
//! progress.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const howl = @import("howl_session");
const protocol = howl.protocol;

const maximum_clients: usize = 8;
const maximum_request_payload: usize = 64 * 1024;
const input_buffer_bytes: usize = protocol.header_bytes + maximum_request_payload;
const client_send_buffer_bytes: c_int = 64 * 1024;
const listen_backlog: u32 = 16;
const lifecycle_poll_ms: i32 = 100;

comptime {
    if (howl.maximum_cell_scalars != protocol.text_v1.maximum_cell_scalars)
        @compileError("text_v1 scalar bound must match canonical VT grapheme bound");
    if (howl.maximum_hyperlinks != protocol.text_v1.maximum_hyperlinks)
        @compileError("text_v1 hyperlink identity bound must match canonical VT bound");
    if (howl.maximum_hyperlink_uri_bytes != protocol.text_v1.maximum_hyperlink_uri_bytes)
        @compileError("text_v1 hyperlink URI bound must match canonical VT bound");
    if (howl.maximum_key_text_bytes != protocol.typed_input.maximum_key_text_bytes)
        @compileError("typed key committed-text bound must match canonical VT bound");
    if (howl.maximum_legacy_key_bytes != protocol.typed_input.maximum_legacy_key_bytes)
        @compileError("typed key legacy-text bound must match canonical VT scratch bound");
}

const Client = struct {
    fd: posix.fd_t,
    id: protocol.ClientId,
    phase: enum { hello, ready } = .hello,
    features: u64 = 0,
    input: [input_buffer_bytes]u8 = undefined,
    input_len: usize = 0,
    output: std.ArrayList(u8) = .empty,
    output_offset: usize = 0,
    observe: ?protocol.Observe = null,

    fn outputPending(self: *const Client) bool {
        return self.output_offset < self.output.items.len;
    }

    fn resetOutput(self: *Client, allocator: std.mem.Allocator) void {
        self.output.deinit(allocator);
        self.output = .empty;
        self.output_offset = 0;
    }

    fn deinit(self: *Client, allocator: std.mem.Allocator) void {
        closeFd(self.fd);
        self.output.deinit(allocator);
        self.* = undefined;
    }
};

const Server = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    session: *howl.Session,
    listener: posix.fd_t,
    socket_path: [108]u8 = @splat(0),
    socket_path_len: u8,
    clients: [maximum_clients]?Client = @splat(null),
    next_client_id: protocol.ClientId = 1,
    authority: protocol.ResizeAuthority = .{},
    observation_revision: u64 = 1,
    terminal_revision: u64,
    stream_closed: bool = false,
    child_exited: bool = false,
    pty_write_pending: bool = false,

    fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        inherited_environment: std.process.Environ,
        socket_path: []const u8,
        launch: howl.Launch,
    ) !Server {
        const session = try howl.init(allocator, inherited_environment, launch);
        errdefer howl.deinit(session);
        const listener = try listenUnix(socket_path);
        errdefer closeFd(listener);
        errdefer unlinkPath(socket_path);

        var server = Server{
            .allocator = allocator,
            .io = io,
            .session = session,
            .listener = listener,
            .socket_path_len = @intCast(socket_path.len),
            .terminal_revision = howl.revision(session),
        };
        @memcpy(server.socket_path[0..socket_path.len], socket_path);
        return server;
    }

    fn deinit(self: *Server) void {
        for (&self.clients) |*client| {
            if (client.*) |*active| active.deinit(self.allocator);
            client.* = null;
        }
        closeFd(self.listener);
        unlinkPath(self.socket_path[0..self.socket_path_len]);
        howl.deinit(self.session);
        self.* = undefined;
    }

    fn turn(self: *Server, timeout_ms: i32) !void {
        try self.materializeObservers();
        try self.processBufferedRequests();

        var descriptors: [2 + maximum_clients]posix.pollfd = undefined;
        descriptors[0] = .{ .fd = self.listener, .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 };
        var pty_poll_events: i16 = 0;
        if (!self.stream_closed) pty_poll_events |= posix.POLL.IN | posix.POLL.HUP;
        if (self.pty_write_pending) pty_poll_events |= posix.POLL.OUT;
        descriptors[1] = .{
            .fd = if (self.stream_closed and !self.pty_write_pending) -1 else try howl.descriptor(self.session),
            .events = pty_poll_events,
            .revents = 0,
        };
        for (self.clients, 0..) |client, index| {
            var client_poll_events: i16 = posix.POLL.HUP | posix.POLL.ERR;
            if (client) |active| {
                client_poll_events |= if (active.outputPending()) posix.POLL.OUT else posix.POLL.IN;
            }
            descriptors[2 + index] = if (client) |active| .{
                .fd = active.fd,
                .events = client_poll_events,
                .revents = 0,
            } else .{ .fd = -1, .events = 0, .revents = 0 };
        }

        const poll_timeout = if (timeout_ms < 0 or timeout_ms > lifecycle_poll_ms)
            lifecycle_poll_ms
        else
            timeout_ms;
        const ready_count = try posix.poll(&descriptors, poll_timeout);
        std.debug.assert(ready_count <= descriptors.len);

        const pty_events = descriptors[1].revents;
        const pty_present = descriptors[1].fd >= 0;
        const result = try howl.service(
            self.session,
            pty_present and pty_events & (posix.POLL.IN | posix.POLL.HUP) != 0,
            pty_present and pty_events & posix.POLL.OUT != 0,
            nowNs(self.io),
        );
        self.applyServiceResult(result);

        if (descriptors[0].revents & posix.POLL.IN != 0) try self.acceptClients();

        var index: usize = 0;
        while (index < self.clients.len) : (index += 1) {
            const events = descriptors[2 + index].revents;
            if (events == 0 or self.clients[index] == null) continue;
            if (events & (posix.POLL.HUP | posix.POLL.ERR | posix.POLL.NVAL) != 0) {
                self.closeClient(index);
                continue;
            }
            if (events & posix.POLL.OUT != 0) self.writeClient(index);
            if (self.clients[index] != null and events & posix.POLL.IN != 0) self.readClient(index);
        }

        try self.processBufferedRequests();
        try self.materializeObservers();
    }

    fn acceptClients(self: *Server) !void {
        while (true) {
            const accepted = linux.accept4(
                self.listener,
                null,
                null,
                linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK,
            );
            switch (linux.errno(accepted)) {
                .SUCCESS => {},
                .AGAIN => return,
                .INTR => continue,
                else => return error.AcceptFailed,
            }
            const fd: posix.fd_t = @intCast(accepted);
            errdefer closeFd(fd);
            setSendBuffer(fd, client_send_buffer_bytes) catch {
                closeFd(fd);
                continue;
            };
            const slot = self.freeClientSlot() orelse {
                closeFd(fd);
                continue;
            };
            const id = self.nextClientId();
            self.clients[slot] = .{ .fd = fd, .id = id };
        }
    }

    fn freeClientSlot(self: *Server) ?usize {
        for (self.clients, 0..) |client, index| if (client == null) return index;
        return null;
    }

    fn nextClientId(self: *Server) protocol.ClientId {
        const id = self.next_client_id;
        self.next_client_id = std.math.add(protocol.ClientId, id, 1) catch 1;
        if (self.next_client_id == protocol.no_client) self.next_client_id = 1;
        return id;
    }

    fn readClient(self: *Server, index: usize) void {
        const client = if (self.clients[index]) |*active| active else return;
        if (client.outputPending() or client.input_len == client.input.len) return;
        const room = client.input[client.input_len..];
        const result = linux.read(client.fd, room.ptr, room.len);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > room.len) {
                    self.closeClient(index);
                    return;
                }
                client.input_len += result;
            },
            .AGAIN, .INTR => {},
            else => self.closeClient(index),
        }
    }

    fn writeClient(self: *Server, index: usize) void {
        const client = if (self.clients[index]) |*active| active else return;
        if (!client.outputPending()) return;
        const bytes = client.output.items[client.output_offset..];
        const result = linux.write(client.fd, bytes.ptr, bytes.len);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len) {
                    self.closeClient(index);
                    return;
                }
                client.output_offset += result;
                if (!client.outputPending()) client.resetOutput(self.allocator);
            },
            .AGAIN, .INTR => {},
            .PIPE, .CONNRESET => self.closeClient(index),
            else => self.closeClient(index),
        }
    }

    fn processBufferedRequests(self: *Server) !void {
        var index: usize = 0;
        while (index < self.clients.len) : (index += 1) {
            while (self.clients[index]) |*client| {
                if (client.outputPending() or client.observe != null) break;
                if (client.input_len < protocol.header_bytes) break;
                var header_bytes: [protocol.header_bytes]u8 = undefined;
                @memcpy(&header_bytes, client.input[0..protocol.header_bytes]);
                const header = protocol.decodeHeader(&header_bytes) catch {
                    self.closeClient(index);
                    break;
                };
                if (header.payload_len > maximum_request_payload) {
                    self.closeClient(index);
                    break;
                }
                const frame_len = protocol.header_bytes + @as(usize, header.payload_len);
                if (client.input_len < frame_len) break;
                var payload: [maximum_request_payload]u8 = undefined;
                @memcpy(payload[0..header.payload_len], client.input[protocol.header_bytes..frame_len]);
                const remaining = client.input_len - frame_len;
                std.mem.copyForwards(u8, client.input[0..remaining], client.input[frame_len..client.input_len]);
                client.input_len = remaining;
                try self.handleFrame(index, header.kind, payload[0..header.payload_len]);
            }
        }
    }

    fn handleFrame(self: *Server, index: usize, kind: protocol.Kind, payload: []const u8) !void {
        const client = if (self.clients[index]) |*active| active else return;
        if (client.phase == .hello) {
            if (kind != .hello) {
                self.closeClient(index);
                return;
            }
            const hello = protocol.decodeHello(payload) catch {
                self.closeClient(index);
                return;
            };
            const version = protocol.negotiateVersion(hello) orelse {
                self.closeClient(index);
                return;
            };
            const features = protocol.negotiateFeatures(hello);
            if (features & protocol.feature(.grid_snapshot) == 0) {
                self.closeClient(index);
                return;
            }
            client.phase = .ready;
            client.features = features;
            var encoded: [protocol.payload_bytes.welcome]u8 = undefined;
            protocol.encodeWelcome(&encoded, .{ .version = version, .features = features, .client_id = client.id });
            try self.queueFrame(client, .welcome, &encoded);
            return;
        }

        switch (kind) {
            .observe => {
                const request = protocol.decodeObserve(payload) catch {
                    try self.queueResult(client, .observe, .malformed);
                    return;
                };
                if (request.after_revision > self.observation_revision) {
                    try self.queueResult(client, .observe, .malformed);
                    return;
                }
                client.observe = request;
            },
            .input => try self.handleInput(client, payload),
            .assign_leader => try self.handleAssignLeader(client, payload),
            .resize => try self.handleResize(client, payload),
            .signal => try self.handleSignal(client, payload),
            else => try self.queueResult(client, kind, .unsupported),
        }
    }

    fn handleInput(self: *Server, client: *Client, payload: []const u8) !void {
        if (payload.len == 0) return self.queueResult(client, .input, .malformed);
        const kind: protocol.InputKind = switch (payload[0]) {
            @backingInt(protocol.InputKind.bytes) => .bytes,
            @backingInt(protocol.InputKind.paste) => .paste,
            @backingInt(protocol.InputKind.key) => .key,
            @backingInt(protocol.InputKind.mouse) => .mouse,
            @backingInt(protocol.InputKind.focus) => .focus,
            else => return self.queueResult(client, .input, .unsupported),
        };
        const event: howl.Input = switch (kind) {
            .bytes => .{ .bytes = payload[1..] },
            .paste => .{ .paste = payload[1..] },
            .key => blk: {
                if (client.features & protocol.feature(.typed_input) == 0)
                    return self.queueResult(client, .input, .unsupported);
                const value = protocol.decodeKeyInput(payload[1..]) catch
                    return self.queueResult(client, .input, .malformed);
                const key: howl.Key = switch (value.kind) {
                    .named => .{ .named = typedKeyName(value.key_value) orelse
                        return self.queueResult(client, .input, .malformed) },
                    .unicode => howl.Key.initUnicode(@intCast(value.key_value)) catch
                        return self.queueResult(client, .input, .malformed),
                };
                break :blk .{ .key = .{
                    .key = key,
                    .mods = typedModifiers(value.modifiers),
                    .action = typedKeyAction(value.action),
                    .shifted = if (value.shifted) |scalar| @intCast(scalar) else null,
                    .alternate = if (value.alternate) |scalar| @intCast(scalar) else null,
                    .legacy_text = value.legacy_text,
                    .text = value.text,
                } };
            },
            .mouse => blk: {
                if (client.features & protocol.feature(.typed_input) == 0)
                    return self.queueResult(client, .input, .unsupported);
                const value = protocol.decodeMouseInput(payload[1..]) catch
                    return self.queueResult(client, .input, .malformed);
                break :blk .{ .mouse = .{
                    .kind = typedMouseKind(value.kind),
                    .button = typedMouseButton(value.button),
                    .row = value.row,
                    .col = value.column,
                    .pixel_x = value.pixel_x,
                    .pixel_y = value.pixel_y,
                    .mod = typedModifiers(value.modifiers),
                    .buttons_down = value.buttons_down,
                } };
            },
            .focus => blk: {
                if (client.features & protocol.feature(.typed_input) == 0)
                    return self.queueResult(client, .input, .unsupported);
                const value = protocol.decodeFocusInput(payload[1..]) catch
                    return self.queueResult(client, .input, .malformed);
                break :blk .{ .focus = switch (value) {
                    .in => .in,
                    .out => .out,
                } };
            },
        };
        howl.input(self.session, event) catch return self.queueResult(client, .input, .rejected);
        const serviced = try howl.service(self.session, false, true, nowNs(self.io));
        self.applyServiceResult(serviced);
        try self.queueResult(client, .input, .ok);
    }

    fn handleAssignLeader(self: *Server, client: *Client, payload: []const u8) !void {
        if (client.features & protocol.feature(.resize_leader) == 0)
            return self.queueResult(client, .assign_leader, .unsupported);
        const request = protocol.decodeAssignLeader(payload) catch
            return self.queueResult(client, .assign_leader, .malformed);
        if (request.client_id != protocol.no_client and !self.hasClient(request.client_id))
            return self.queueResult(client, .assign_leader, .no_such_client);
        if (self.authority.assign(request.client_id)) self.bumpObservation();
        try self.queueResult(client, .assign_leader, .ok);
    }

    fn handleResize(self: *Server, client: *Client, payload: []const u8) !void {
        if (client.features & protocol.feature(.resize_leader) == 0)
            return self.queueResult(client, .resize, .unsupported);
        if (!self.authority.mayResize(client.id)) return self.queueResult(client, .resize, .not_leader);
        const request = protocol.decodeResize(payload) catch return self.queueResult(client, .resize, .malformed);
        howl.resize(self.session, request.rows, request.columns) catch
            return self.queueResult(client, .resize, .rejected);
        self.refreshObservation();
        try self.queueResult(client, .resize, .ok);
    }

    fn handleSignal(self: *Server, client: *Client, payload: []const u8) !void {
        const requested = protocol.decodeSignal(payload) catch return self.queueResult(client, .signal, .malformed);
        const native: howl.Signal = switch (requested) {
            .hangup => .hangup,
            .interrupt => .interrupt,
            .resize_notify => .resize_notify,
            .kill => .kill,
            .terminate => .terminate,
        };
        const result = howl.signal(self.session, native);
        try self.queueResult(client, .signal, if (result == .delivered) .ok else .rejected);
    }

    fn hasClient(self: *Server, id: protocol.ClientId) bool {
        for (self.clients) |client| if (client) |active| if (active.id == id) return true;
        return false;
    }

    fn closeClient(self: *Server, index: usize) void {
        const client = if (self.clients[index]) |*active| active else return;
        const id = client.id;
        client.deinit(self.allocator);
        self.clients[index] = null;
        if (self.authority.disconnected(id)) self.bumpObservation();
    }

    fn refreshObservation(self: *Server) void {
        const current = howl.revision(self.session);
        if (current == self.terminal_revision) return;
        self.terminal_revision = current;
        self.bumpObservation();
    }

    fn applyServiceResult(self: *Server, result: howl.Service) void {
        const next_stream_closed = result.stream_closed;
        const next_child_exited = result.child_exit != null;
        const lifecycle_changed = self.stream_closed != next_stream_closed or
            self.child_exited != next_child_exited;
        self.pty_write_pending = result.write_pending;
        self.stream_closed = next_stream_closed;
        self.child_exited = next_child_exited;

        const current_terminal_revision = howl.revision(self.session);
        const terminal_changed = current_terminal_revision != self.terminal_revision;
        if (terminal_changed) self.terminal_revision = current_terminal_revision;
        if (terminal_changed or lifecycle_changed) self.bumpObservation();
    }

    fn bumpObservation(self: *Server) void {
        self.observation_revision = std.math.add(u64, self.observation_revision, 1) catch
            @panic("session observation revision exhausted");
    }

    fn materializeObservers(self: *Server) !void {
        var index: usize = 0;
        while (index < self.clients.len) : (index += 1) {
            const client = if (self.clients[index]) |*active| active else continue;
            const request = client.observe orelse continue;
            if (client.outputPending()) continue;
            if (request.after_revision != 0 and request.after_revision >= self.observation_revision) continue;
            self.queueSnapshot(client, request.history_offset) catch |err| {
                if (err != error.SnapshotTooLarge) return err;
                client.observe = null;
                try self.queueResult(client, .observe, .rejected);
                continue;
            };
            client.observe = null;
        }
    }

    fn queueSnapshot(self: *Server, client: *Client, history_offset: u32) !void {
        if (client.features & protocol.feature(.text_snapshot) != 0)
            return self.queueTextSnapshot(client, history_offset);
        return self.queueGridSnapshot(client, history_offset);
    }

    fn queueGridSnapshot(self: *Server, client: *Client, history_offset: u32) !void {
        const status = howl.status(self.session, history_offset);
        const row_bytes = std.math.add(usize, 4, std.math.mul(usize, status.columns, 8) catch
            return error.SnapshotTooLarge) catch return error.SnapshotTooLarge;
        const body_bytes = std.math.mul(usize, status.rows, row_bytes) catch return error.SnapshotTooLarge;
        const maximum_payload: usize = protocol.maximum_payload_bytes;
        if (row_bytes > maximum_payload) return error.SnapshotTooLarge;
        const rows_per_frame = @max(@as(usize, 1), maximum_payload / row_bytes);
        const row_count: usize = status.rows;
        const data_frames = if (row_count == 0) 0 else (row_count + rows_per_frame - 1) / rows_per_frame;
        const frame_count = std.math.add(usize, data_frames, 2) catch return error.SnapshotTooLarge;
        const frame_headers = std.math.mul(usize, frame_count, protocol.header_bytes) catch
            return error.SnapshotTooLarge;
        const fixed_payloads = std.math.add(
            usize,
            protocol.payload_bytes.snapshot_begin,
            protocol.payload_bytes.snapshot_end,
        ) catch return error.SnapshotTooLarge;
        const framed_body = std.math.add(usize, body_bytes, frame_headers) catch return error.SnapshotTooLarge;
        const total_bound = std.math.add(usize, framed_body, fixed_payloads) catch return error.SnapshotTooLarge;
        if (total_bound > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;

        client.resetOutput(self.allocator);
        errdefer client.resetOutput(self.allocator);
        try client.output.ensureTotalCapacity(self.allocator, total_bound);

        var begin_payload: [protocol.payload_bytes.snapshot_begin]u8 = undefined;
        protocol.encodeSnapshotBegin(&begin_payload, .{
            .revision = self.observation_revision,
            .terminal_revision = status.revision,
            .history_offset = status.history_offset,
            .history_count = status.history_count,
            .history_row_base = status.history_row_base,
            .rows = status.rows,
            .columns = status.columns,
            .cursor_row = status.cursor_row,
            .cursor_column = status.cursor_column,
            .cursor_shape = @intCast(@backingInt(status.cursor_shape)),
            .cursor_visible = status.cursor_visible,
            .cursor_blink = status.cursor_blink,
            .alternate_screen = status.alternate_screen,
            .stream_closed = self.stream_closed,
            .child_exited = self.child_exited,
            .leader_present = self.authority.leader() != null,
            .you_are_leader = self.authority.mayResize(client.id),
        });
        try self.appendFrame(&client.output, .snapshot_begin, &begin_payload);

        if (status.rows != 0) {
            const cells = try self.allocator.alloc(howl.Cell, status.columns);
            defer self.allocator.free(cells);
            var frame_header_offset: ?usize = null;
            var frame_payload_start: usize = 0;
            var row: u16 = 0;
            while (row < status.rows) : (row += 1) {
                if (frame_header_offset == null or
                    client.output.items.len - frame_payload_start + row_bytes > protocol.maximum_payload_bytes)
                {
                    if (frame_header_offset) |offset| try finishDataFrame(&client.output, offset, frame_payload_start);
                    frame_header_offset = client.output.items.len;
                    try client.output.appendNTimes(self.allocator, 0, protocol.header_bytes);
                    frame_payload_start = client.output.items.len;
                }
                var row_header: [4]u8 = .{
                    @intFromBool(howl.rowWrapped(self.session, status.history_offset, row)),
                    @intCast(@backingInt(howl.lineGeometry(self.session, status.history_offset, row))),
                    @truncate(status.columns >> 8),
                    @truncate(status.columns),
                };
                try client.output.appendSlice(self.allocator, &row_header);
                const copied = try howl.copyRow(self.session, status.history_offset, row, cells);
                for (copied) |cell| {
                    var encoded: [8]u8 = undefined;
                    encodeU32(encoded[0..4], cell.codepoint);
                    encoded[4] = cell.width;
                    encoded[5] = cell.height;
                    encoded[6] = cell.x;
                    encoded[7] = cell.y;
                    try client.output.appendSlice(self.allocator, &encoded);
                }
            }
            if (frame_header_offset) |offset| try finishDataFrame(&client.output, offset, frame_payload_start);
        }

        var end_payload: [protocol.payload_bytes.snapshot_end]u8 = undefined;
        protocol.encodeSnapshotEnd(&end_payload, .{ .revision = self.observation_revision });
        try self.appendFrame(&client.output, .snapshot_end, &end_payload);
        client.output_offset = 0;
    }

    fn queueTextSnapshot(self: *Server, client: *Client, history_offset: u32) !void {
        const status = howl.status(self.session, history_offset);
        const observed_ns = nowNs(self.io);
        const cursor_age_ns = if (status.cursor_movement_timestamp_ns == 0)
            protocol.text_v1.no_cursor_movement_age_ns
        else
            observed_ns -| status.cursor_movement_timestamp_ns;
        var referenced_links: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
        var referenced_link_count: usize = 0;
        const cells = try self.allocator.alloc(howl.Cell, status.columns);
        defer self.allocator.free(cells);

        var body_bytes: usize = protocol.text_v1.record_header_bytes +
            protocol.text_v1.presentation_bytes;
        var row: u16 = 0;
        while (row < status.rows) : (row += 1) {
            const copied = try howl.copyRow(self.session, status.history_offset, row, cells);
            var row_payload_bytes: usize = protocol.text_v1.row_header_bytes;
            for (copied, 0..) |cell, column| {
                var scalar_storage: [howl.maximum_cell_scalars]u21 = undefined;
                const scalars: []const u21 = if (cell.codepoint != 0 and cell.x == 0 and cell.y == 0)
                    howl.copyCellScalars(
                        self.session,
                        status.history_offset,
                        row,
                        @intCast(column),
                        &scalar_storage,
                    )
                else
                    &.{};
                if (scalars.len > protocol.text_v1.maximum_cell_scalars)
                    return error.InvalidSnapshot;
                if (cell.codepoint != 0 and cell.x == 0 and cell.y == 0) {
                    if (scalars.len == 0 or scalars[0] != cell.codepoint)
                        return error.InvalidSnapshot;
                } else if (scalars.len != 0) return error.InvalidSnapshot;

                const scalar_bytes = std.math.mul(usize, scalars.len, 4) catch
                    return error.SnapshotTooLarge;
                row_payload_bytes = std.math.add(
                    usize,
                    row_payload_bytes,
                    protocol.text_v1.cell_header_bytes + scalar_bytes,
                ) catch return error.SnapshotTooLarge;

                if (cell.attrs.link_id != 0) {
                    if (cell.attrs.link_id > protocol.text_v1.maximum_hyperlinks)
                        return error.InvalidSnapshot;
                    const link_index: usize = @intCast(cell.attrs.link_id);
                    if (!referenced_links[link_index]) {
                        const uri = howl.hyperlinkUri(self.session, cell.attrs.link_id) orelse
                            return error.InvalidSnapshot;
                        if (uri.len > protocol.text_v1.maximum_hyperlink_uri_bytes)
                            return error.InvalidSnapshot;
                        referenced_links[link_index] = true;
                        referenced_link_count += 1;
                    }
                }
            }
            const record_bytes = std.math.add(
                usize,
                protocol.text_v1.record_header_bytes,
                row_payload_bytes,
            ) catch return error.SnapshotTooLarge;
            if (record_bytes > protocol.maximum_payload_bytes) return error.SnapshotTooLarge;
            body_bytes = std.math.add(usize, body_bytes, record_bytes) catch
                return error.SnapshotTooLarge;
        }

        var link_id: usize = 1;
        while (link_id < referenced_links.len) : (link_id += 1) {
            if (!referenced_links[link_id]) continue;
            const uri = howl.hyperlinkUri(self.session, @intCast(link_id)) orelse
                return error.InvalidSnapshot;
            const link_payload_bytes = std.math.add(
                usize,
                protocol.text_v1.hyperlink_header_bytes,
                uri.len,
            ) catch return error.SnapshotTooLarge;
            body_bytes = std.math.add(
                usize,
                body_bytes,
                protocol.text_v1.record_header_bytes + link_payload_bytes,
            ) catch return error.SnapshotTooLarge;
        }

        const data_frame_count = std.math.add(
            usize,
            @as(usize, status.rows) + 1,
            referenced_link_count,
        ) catch return error.SnapshotTooLarge;
        const frame_count = std.math.add(usize, data_frame_count, 2) catch
            return error.SnapshotTooLarge;
        const frame_headers = std.math.mul(usize, frame_count, protocol.header_bytes) catch
            return error.SnapshotTooLarge;
        const fixed_payloads = protocol.payload_bytes.snapshot_begin +
            protocol.payload_bytes.snapshot_end;
        const total_bound = std.math.add(
            usize,
            std.math.add(usize, body_bytes, frame_headers) catch return error.SnapshotTooLarge,
            fixed_payloads,
        ) catch return error.SnapshotTooLarge;
        if (total_bound > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;

        client.resetOutput(self.allocator);
        errdefer client.resetOutput(self.allocator);
        try client.output.ensureTotalCapacity(self.allocator, total_bound);

        var begin_payload: [protocol.payload_bytes.snapshot_begin]u8 = undefined;
        protocol.encodeSnapshotBegin(&begin_payload, .{
            .revision = self.observation_revision,
            .terminal_revision = status.revision,
            .format = .text_v1,
            .history_offset = status.history_offset,
            .history_count = status.history_count,
            .history_row_base = status.history_row_base,
            .rows = status.rows,
            .columns = status.columns,
            .cursor_row = status.cursor_row,
            .cursor_column = status.cursor_column,
            .cursor_shape = @intCast(@backingInt(status.cursor_shape)),
            .cursor_visible = status.cursor_visible,
            .cursor_blink = status.cursor_blink,
            .alternate_screen = status.alternate_screen,
            .stream_closed = self.stream_closed,
            .child_exited = self.child_exited,
            .leader_present = self.authority.leader() != null,
            .you_are_leader = self.authority.mayResize(client.id),
        });
        try self.appendFrame(&client.output, .snapshot_begin, &begin_payload);

        try self.appendPresentationRecord(&client.output, cursor_age_ns);

        row = 0;
        while (row < status.rows) : (row += 1) {
            const copied = try howl.copyRow(self.session, status.history_offset, row, cells);
            const record = try self.beginTextRecord(&client.output, .row);
            var row_header: [protocol.text_v1.row_header_bytes]u8 = .{
                @intFromBool(howl.rowWrapped(self.session, status.history_offset, row)),
                richLineGeometry(howl.lineGeometry(self.session, status.history_offset, row)),
                @truncate(status.columns >> 8),
                @truncate(status.columns),
            };
            try client.output.appendSlice(self.allocator, &row_header);
            for (copied, 0..) |cell, column| {
                var scalar_storage: [howl.maximum_cell_scalars]u21 = undefined;
                const scalars: []const u21 = if (cell.codepoint != 0 and cell.x == 0 and cell.y == 0)
                    howl.copyCellScalars(
                        self.session,
                        status.history_offset,
                        row,
                        @intCast(column),
                        &scalar_storage,
                    )
                else
                    &.{};
                try self.appendTextCell(&client.output, cell, scalars);
            }
            try finishTextRecord(&client.output, record);
        }

        link_id = 1;
        while (link_id < referenced_links.len) : (link_id += 1) {
            if (!referenced_links[link_id]) continue;
            const uri = howl.hyperlinkUri(self.session, @intCast(link_id)) orelse
                return error.InvalidSnapshot;
            const record = try self.beginTextRecord(&client.output, .hyperlink);
            var link_header: [protocol.text_v1.hyperlink_header_bytes]u8 = undefined;
            encodeU32(link_header[0..4], @intCast(link_id));
            link_header[4] = @truncate(uri.len >> 8);
            link_header[5] = @truncate(uri.len);
            try client.output.appendSlice(self.allocator, &link_header);
            try client.output.appendSlice(self.allocator, uri);
            try finishTextRecord(&client.output, record);
        }

        var end_payload: [protocol.payload_bytes.snapshot_end]u8 = undefined;
        protocol.encodeSnapshotEnd(&end_payload, .{ .revision = self.observation_revision });
        try self.appendFrame(&client.output, .snapshot_end, &end_payload);
        std.debug.assert(client.output.items.len == total_bound);
        client.output_offset = 0;
    }

    fn appendPresentationRecord(
        self: *Server,
        output: *std.ArrayList(u8),
        cursor_age_ns: u64,
    ) !void {
        const record = try self.beginTextRecord(output, .presentation);
        const payload_start = output.items.len;
        const presentation = howl.presentation(self.session);
        var fixed: [12]u8 = @splat(0);
        encodeU64(fixed[0..8], cursor_age_ns);
        if (presentation.cursor != null)
            fixed[8] |= protocol.text_v1.presentation_presence.cursor;
        if (presentation.cursor_text != null)
            fixed[8] |= protocol.text_v1.presentation_presence.cursor_text;
        if (presentation.selection_background != null)
            fixed[8] |= protocol.text_v1.presentation_presence.selection_background;
        if (presentation.selection_foreground != null)
            fixed[8] |= protocol.text_v1.presentation_presence.selection_foreground;
        if (presentation.reverse_screen)
            fixed[9] |= protocol.text_v1.presentation_flags.reverse_screen;
        try output.appendSlice(self.allocator, &fixed);
        for (presentation.palette) |rgb| try appendRgba(self.allocator, output, rgb);
        try appendRgba(self.allocator, output, presentation.foreground);
        try appendRgba(self.allocator, output, presentation.background);
        try appendOptionalRgba(self.allocator, output, presentation.cursor);
        try appendOptionalRgba(self.allocator, output, presentation.cursor_text);
        try appendOptionalRgba(self.allocator, output, presentation.selection_background);
        try appendOptionalRgba(self.allocator, output, presentation.selection_foreground);
        if (output.items.len - payload_start != protocol.text_v1.presentation_bytes)
            return error.InvalidSnapshot;
        try finishTextRecord(output, record);
    }

    fn appendTextCell(
        self: *Server,
        output: *std.ArrayList(u8),
        cell: howl.Cell,
        scalars: []const u21,
    ) !void {
        var encoded: [protocol.text_v1.cell_header_bytes]u8 = @splat(0);
        encoded[0] = @intCast(scalars.len);
        encoded[1] = cell.width;
        encoded[2] = cell.height;
        encoded[3] = cell.x;
        encoded[4] = cell.y;
        encoded[5] = cell.subscale_n;
        encoded[6] = cell.subscale_d;
        encoded[7] = cell.vertical_align;
        encoded[8] = cell.horizontal_align;
        encoded[9] = @intFromBool(cell.semantic_width);
        encoded[10] = cell.attrs.font;
        encoded[11] = richBaseline(cell.attrs.baseline);
        encoded[12] = richUnderlineStyle(cell.attrs.underline_style);
        encoded[13] = richProtection(cell.attrs.protected);
        const style = richStyle(cell.attrs);
        encoded[14] = @truncate(style >> 8);
        encoded[15] = @truncate(style);
        try encodeRichColor(encoded[16..21], cell.attrs.fg);
        try encodeRichColor(encoded[21..26], cell.attrs.bg);
        try encodeRichColor(encoded[26..31], cell.attrs.underline_color);
        encodeU32(encoded[31..35], cell.attrs.link_id);
        try output.appendSlice(self.allocator, &encoded);
        for (scalars) |scalar| {
            var scalar_bytes: [4]u8 = undefined;
            encodeU32(&scalar_bytes, scalar);
            try output.appendSlice(self.allocator, &scalar_bytes);
        }
    }

    const TextRecordOffsets = struct {
        frame_header: usize,
        record_header: usize,
        payload_start: usize,
        kind: protocol.TextRecordKind,
    };

    fn beginTextRecord(
        self: *Server,
        output: *std.ArrayList(u8),
        kind: protocol.TextRecordKind,
    ) !TextRecordOffsets {
        const frame_header = output.items.len;
        try output.appendNTimes(self.allocator, 0, protocol.header_bytes);
        const record_header = output.items.len;
        try output.appendNTimes(self.allocator, 0, protocol.text_v1.record_header_bytes);
        return .{
            .frame_header = frame_header,
            .record_header = record_header,
            .payload_start = output.items.len,
            .kind = kind,
        };
    }

    fn queueResult(self: *Server, client: *Client, request_kind: protocol.Kind, code: protocol.ResultCode) !void {
        var payload: [protocol.payload_bytes.result]u8 = undefined;
        protocol.encodeResult(&payload, .{ .request_kind = request_kind, .code = code });
        try self.queueFrame(client, .result, &payload);
    }

    fn queueFrame(self: *Server, client: *Client, kind: protocol.Kind, payload: []const u8) !void {
        if (client.outputPending()) return error.ResponseAlreadyPending;
        client.resetOutput(self.allocator);
        errdefer client.resetOutput(self.allocator);
        try self.appendFrame(&client.output, kind, payload);
        client.output_offset = 0;
    }

    fn appendFrame(self: *Server, output: *std.ArrayList(u8), kind: protocol.Kind, payload: []const u8) !void {
        if (payload.len > protocol.maximum_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try output.appendSlice(self.allocator, &header);
        try output.appendSlice(self.allocator, payload);
    }
};

fn finishDataFrame(output: *std.ArrayList(u8), header_offset: usize, payload_start: usize) !void {
    const payload_len = output.items.len - payload_start;
    var header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&header, .{ .kind = .snapshot_data, .payload_len = @intCast(payload_len) });
    @memcpy(output.items[header_offset..payload_start], &header);
}

fn typedKeyName(value: u32) ?howl.KeyName {
    return switch (value) {
        @backingInt(protocol.InputKeyName.enter) => .enter,
        @backingInt(protocol.InputKeyName.tab) => .tab,
        @backingInt(protocol.InputKeyName.backspace) => .backspace,
        @backingInt(protocol.InputKeyName.escape) => .escape,
        @backingInt(protocol.InputKeyName.up) => .up,
        @backingInt(protocol.InputKeyName.down) => .down,
        @backingInt(protocol.InputKeyName.left) => .left,
        @backingInt(protocol.InputKeyName.right) => .right,
        @backingInt(protocol.InputKeyName.insert) => .insert,
        @backingInt(protocol.InputKeyName.delete) => .delete,
        @backingInt(protocol.InputKeyName.home) => .home,
        @backingInt(protocol.InputKeyName.end) => .end,
        @backingInt(protocol.InputKeyName.page_up) => .page_up,
        @backingInt(protocol.InputKeyName.page_down) => .page_down,
        @backingInt(protocol.InputKeyName.left_shift) => .left_shift,
        @backingInt(protocol.InputKeyName.right_shift) => .right_shift,
        @backingInt(protocol.InputKeyName.left_control) => .left_control,
        @backingInt(protocol.InputKeyName.right_control) => .right_control,
        @backingInt(protocol.InputKeyName.left_alt) => .left_alt,
        @backingInt(protocol.InputKeyName.right_alt) => .right_alt,
        @backingInt(protocol.InputKeyName.left_super) => .left_super,
        @backingInt(protocol.InputKeyName.right_super) => .right_super,
        @backingInt(protocol.InputKeyName.left_hyper) => .left_hyper,
        @backingInt(protocol.InputKeyName.right_hyper) => .right_hyper,
        @backingInt(protocol.InputKeyName.left_meta) => .left_meta,
        @backingInt(protocol.InputKeyName.right_meta) => .right_meta,
        @backingInt(protocol.InputKeyName.caps_lock) => .caps_lock,
        @backingInt(protocol.InputKeyName.num_lock) => .num_lock,
        @backingInt(protocol.InputKeyName.f1) => .f1,
        @backingInt(protocol.InputKeyName.f2) => .f2,
        @backingInt(protocol.InputKeyName.f3) => .f3,
        @backingInt(protocol.InputKeyName.f4) => .f4,
        @backingInt(protocol.InputKeyName.f5) => .f5,
        @backingInt(protocol.InputKeyName.f6) => .f6,
        @backingInt(protocol.InputKeyName.f7) => .f7,
        @backingInt(protocol.InputKeyName.f8) => .f8,
        @backingInt(protocol.InputKeyName.f9) => .f9,
        @backingInt(protocol.InputKeyName.f10) => .f10,
        @backingInt(protocol.InputKeyName.f11) => .f11,
        @backingInt(protocol.InputKeyName.f12) => .f12,
        @backingInt(protocol.InputKeyName.keypad_0) => .keypad_0,
        @backingInt(protocol.InputKeyName.keypad_1) => .keypad_1,
        @backingInt(protocol.InputKeyName.keypad_2) => .keypad_2,
        @backingInt(protocol.InputKeyName.keypad_3) => .keypad_3,
        @backingInt(protocol.InputKeyName.keypad_4) => .keypad_4,
        @backingInt(protocol.InputKeyName.keypad_5) => .keypad_5,
        @backingInt(protocol.InputKeyName.keypad_6) => .keypad_6,
        @backingInt(protocol.InputKeyName.keypad_7) => .keypad_7,
        @backingInt(protocol.InputKeyName.keypad_8) => .keypad_8,
        @backingInt(protocol.InputKeyName.keypad_9) => .keypad_9,
        @backingInt(protocol.InputKeyName.keypad_decimal) => .keypad_decimal,
        @backingInt(protocol.InputKeyName.keypad_add) => .keypad_add,
        @backingInt(protocol.InputKeyName.keypad_subtract) => .keypad_subtract,
        @backingInt(protocol.InputKeyName.keypad_multiply) => .keypad_multiply,
        @backingInt(protocol.InputKeyName.keypad_divide) => .keypad_divide,
        @backingInt(protocol.InputKeyName.keypad_separator) => .keypad_separator,
        @backingInt(protocol.InputKeyName.keypad_equal) => .keypad_equal,
        @backingInt(protocol.InputKeyName.keypad_enter) => .keypad_enter,
        else => null,
    };
}

fn typedKeyAction(value: protocol.InputKeyAction) howl.KeyAction {
    return switch (value) {
        .press => .press,
        .repeat => .repeat,
        .release => .release,
    };
}

fn typedModifiers(value: u8) howl.InputModifier {
    return .{
        .shift = value & protocol.typed_input.modifiers.shift != 0,
        .alt = value & protocol.typed_input.modifiers.alt != 0,
        .control = value & protocol.typed_input.modifiers.control != 0,
        .super = value & protocol.typed_input.modifiers.super != 0,
        .hyper = value & protocol.typed_input.modifiers.hyper != 0,
        .meta = value & protocol.typed_input.modifiers.meta != 0,
        .caps_lock = value & protocol.typed_input.modifiers.caps_lock != 0,
        .num_lock = value & protocol.typed_input.modifiers.num_lock != 0,
    };
}

fn typedMouseKind(value: protocol.InputMouseKind) howl.MouseEventKind {
    return switch (value) {
        .press => .press,
        .release => .release,
        .move => .move,
        .wheel => .wheel,
    };
}

fn typedMouseButton(value: protocol.InputMouseButton) howl.MouseButton {
    return switch (value) {
        .none => .none,
        .left => .left,
        .middle => .middle,
        .right => .right,
        .wheel_up => .wheel_up,
        .wheel_down => .wheel_down,
    };
}

fn finishTextRecord(output: *std.ArrayList(u8), offsets: Server.TextRecordOffsets) !void {
    const payload_len = output.items.len - offsets.payload_start;
    const frame_payload_len = std.math.add(
        usize,
        protocol.text_v1.record_header_bytes,
        payload_len,
    ) catch return error.PayloadTooLarge;
    if (frame_payload_len > protocol.maximum_payload_bytes) return error.PayloadTooLarge;

    var record_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
    protocol.encodeTextRecordHeader(&record_header, .{
        .kind = offsets.kind,
        .payload_len = @intCast(payload_len),
    });
    @memcpy(
        output.items[offsets.record_header..offsets.payload_start],
        &record_header,
    );

    var frame_header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&frame_header, .{
        .kind = .snapshot_data,
        .payload_len = @intCast(frame_payload_len),
    });
    @memcpy(
        output.items[offsets.frame_header..offsets.record_header],
        &frame_header,
    );
}

fn richLineGeometry(value: howl.LineGeometry) u8 {
    return switch (value) {
        .single_width => 0,
        .double_width => 1,
        .double_height_top => 2,
        .double_height_bottom => 3,
    };
}

fn richBaseline(value: @TypeOf(@as(howl.Cell, undefined).attrs.baseline)) u8 {
    return switch (value) {
        .normal => 0,
        .raised => 1,
        .lowered => 2,
    };
}

fn richUnderlineStyle(value: @TypeOf(@as(howl.Cell, undefined).attrs.underline_style)) u8 {
    return switch (value) {
        .straight => 0,
        .double => 1,
        .curly => 2,
        .dotted => 3,
        .dashed => 4,
    };
}

fn richProtection(value: @TypeOf(@as(howl.Cell, undefined).attrs.protected)) u8 {
    return switch (value) {
        .none => 0,
        .iso => 1,
        .dec => 2,
    };
}

fn richStyle(attrs: @TypeOf(@as(howl.Cell, undefined).attrs)) u16 {
    var result: u16 = 0;
    if (attrs.bold) result |= protocol.text_v1.style.bold;
    if (attrs.dim) result |= protocol.text_v1.style.dim;
    if (attrs.italic) result |= protocol.text_v1.style.italic;
    if (attrs.blink) result |= protocol.text_v1.style.blink;
    if (attrs.blink_fast) result |= protocol.text_v1.style.blink_fast;
    if (attrs.reverse) result |= protocol.text_v1.style.reverse;
    if (attrs.invisible) result |= protocol.text_v1.style.invisible;
    if (attrs.underline) result |= protocol.text_v1.style.underline;
    if (attrs.strikethrough) result |= protocol.text_v1.style.strikethrough;
    return result;
}

fn encodeRichColor(output: []u8, color: @TypeOf(@as(howl.Cell, undefined).attrs.fg)) !void {
    std.debug.assert(output.len == protocol.text_v1.color_bytes);
    const kind: protocol.TextColorKind = switch (color.colorKind()) {
        .default => .default,
        .indexed => .indexed,
        .rgb => .rgb,
    };
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    try protocol.encodeTextColor(&encoded, .{
        .kind = kind,
        .value = color.colorValue(),
    });
    @memcpy(output, &encoded);
}

fn appendRgba(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    rgb: @TypeOf(@as(howl.Presentation, undefined).palette[0]),
) !void {
    try output.appendSlice(allocator, &.{ rgb.r, rgb.g, rgb.b, rgb.a });
}

fn appendOptionalRgba(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    rgb: ?@TypeOf(@as(howl.Presentation, undefined).palette[0]),
) !void {
    if (rgb) |value| return appendRgba(allocator, output, value);
    try output.appendSlice(allocator, &.{ 0, 0, 0, 0 });
}

fn encodeU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    output[0] = @truncate(value >> 56);
    output[1] = @truncate(value >> 48);
    output[2] = @truncate(value >> 40);
    output[3] = @truncate(value >> 32);
    output[4] = @truncate(value >> 24);
    output[5] = @truncate(value >> 16);
    output[6] = @truncate(value >> 8);
    output[7] = @truncate(value);
}

fn listenUnix(path: []const u8) !posix.fd_t {
    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);

    var address: linux.sockaddr.un = undefined;
    const length = try unixAddress(path, &address);
    if (linux.errno(linux.bind(fd, @ptrCast(&address), length)) != .SUCCESS) return error.SocketBindFailed;
    var path_buffer: [109]u8 = @splat(0);
    @memcpy(path_buffer[0..path.len], path);
    if (linux.errno(linux.chmod(@ptrCast(&path_buffer), 0o600)) != .SUCCESS) return error.SocketModeFailed;
    if (linux.errno(linux.listen(fd, listen_backlog)) != .SUCCESS) return error.SocketListenFailed;
    return fd;
}

fn unixAddress(path: []const u8, address: *linux.sockaddr.un) error{SocketPathTooLong}!linux.socklen_t {
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPathTooLong;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    return @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
}

fn setSendBuffer(fd: posix.fd_t, bytes: c_int) !void {
    const result = linux.setsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.SNDBUF,
        std.mem.asBytes(&bytes).ptr,
        @sizeOf(c_int),
    );
    if (linux.errno(result) != .SUCCESS) return error.SocketOptionFailed;
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

fn unlinkPath(path: []const u8) void {
    if (path.len == 0 or path.len >= 108) return;
    var buffer: [109]u8 = @splat(0);
    @memcpy(buffer[0..path.len], path);
    const result = linux.unlink(@ptrCast(&buffer));
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .NOENT);
}

fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.awake.now(io).toNanoseconds());
}

fn encodeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

/// Starts one shared session process. Usage:
/// `howl-sessiond SOCKET SHELL ROWS COLUMNS [COMMAND]`.
pub fn main(init: std.process.Init) error{
    InvalidArguments,
    InvalidRows,
    InvalidColumns,
    SessionServerFailed,
}!void {
    const argv = init.minimal.args.vector;
    if (argv.len < 5 or argv.len > 6) return error.InvalidArguments;
    const rows = std.fmt.parseInt(u16, std.mem.span(argv[3]), 10) catch return error.InvalidRows;
    const columns = std.fmt.parseInt(u16, std.mem.span(argv[4]), 10) catch return error.InvalidColumns;
    var server = Server.init(std.heap.page_allocator, init.io, init.minimal.environ, std.mem.span(argv[1]), .{
        .shell = std.mem.span(argv[2]),
        .command = if (argv.len == 6) std.mem.span(argv[5]) else null,
        .rows = rows,
        .columns = columns,
    }) catch return error.SessionServerFailed;
    defer server.deinit();
    while (true) server.turn(-1) catch return error.SessionServerFailed;
}

const TestFrame = struct {
    allocator: std.mem.Allocator,
    kind: protocol.Kind,
    payload: []u8,

    fn deinit(self: *TestFrame) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

const TestPeer = struct {
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    incoming: std.ArrayList(u8) = .empty,

    fn connect(allocator: std.mem.Allocator, path: []const u8) !TestPeer {
        const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(raw) != .SUCCESS) return error.TestSocketCreateFailed;
        const fd: posix.fd_t = @intCast(raw);
        errdefer closeFd(fd);

        var address: linux.sockaddr.un = undefined;
        const length = try unixAddress(path, &address);
        while (true) {
            const result = linux.connect(fd, @ptrCast(&address), length);
            switch (linux.errno(result)) {
                .SUCCESS => break,
                .INTR => continue,
                else => return error.TestSocketConnectFailed,
            }
        }
        try setNonBlocking(fd);
        return .{ .allocator = allocator, .fd = fd };
    }

    fn deinit(self: *TestPeer) void {
        self.closeSocket();
        self.incoming.deinit(self.allocator);
        self.* = undefined;
    }

    fn closeSocket(self: *TestPeer) void {
        if (self.fd < 0) return;
        closeFd(self.fd);
        self.fd = -1;
    }

    fn sendFrame(self: *TestPeer, server: *Server, kind: protocol.Kind, payload: []const u8) !void {
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try self.sendAll(server, &header);
        try self.sendAll(server, payload);
    }

    fn sendAll(self: *TestPeer, server: *Server, bytes: []const u8) !void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const result = linux.write(self.fd, bytes[offset..].ptr, bytes.len - offset);
            switch (linux.errno(result)) {
                .SUCCESS => {
                    if (result == 0 or result > bytes.len - offset) return error.TestSocketWriteFailed;
                    offset += result;
                },
                .INTR => continue,
                .AGAIN => try server.turn(0),
                else => return error.TestSocketWriteFailed,
            }
        }
    }

    fn readAvailable(self: *TestPeer) !void {
        var scratch: [64 * 1024]u8 = undefined;
        while (true) {
            const result = linux.read(self.fd, &scratch, scratch.len);
            switch (linux.errno(result)) {
                .SUCCESS => {
                    if (result == 0) return error.TestPeerClosed;
                    if (result > scratch.len) return error.TestSocketReadFailed;
                    try self.incoming.appendSlice(self.allocator, scratch[0..result]);
                },
                .INTR => continue,
                .AGAIN => return,
                else => return error.TestSocketReadFailed,
            }
        }
    }

    fn popFrame(self: *TestPeer) !?TestFrame {
        if (self.incoming.items.len < protocol.header_bytes) return null;
        var encoded_header: [protocol.header_bytes]u8 = undefined;
        @memcpy(&encoded_header, self.incoming.items[0..protocol.header_bytes]);
        const header = try protocol.decodeHeader(&encoded_header);
        const frame_bytes = protocol.header_bytes + @as(usize, header.payload_len);
        if (self.incoming.items.len < frame_bytes) return null;
        const payload = try self.allocator.dupe(u8, self.incoming.items[protocol.header_bytes..frame_bytes]);
        const remaining = self.incoming.items.len - frame_bytes;
        std.mem.copyForwards(u8, self.incoming.items[0..remaining], self.incoming.items[frame_bytes..]);
        self.incoming.shrinkRetainingCapacity(remaining);
        return .{ .allocator = self.allocator, .kind = header.kind, .payload = payload };
    }
};

const TestSnapshot = struct {
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    text: []u8,

    fn deinit(self: *TestSnapshot) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }
};

const TestTextSnapshot = struct {
    begin: protocol.SnapshotBegin,
    presentation_seen: bool = false,
    cursor_age_ns: u64 = protocol.text_v1.no_cursor_movement_age_ns,
    row_count: u16 = 0,
    styled_link_id: u32 = 0,
    saw_styled_a: bool = false,
    saw_combining: bool = false,
    saw_wide_lead: bool = false,
    saw_wide_continuation: bool = false,
    saw_osc66_lead: bool = false,
    saw_osc66_continuation: bool = false,
    saw_hyperlink: bool = false,
};

fn setNonBlocking(fd: posix.fd_t) !void {
    const flags_result = linux.fcntl(fd, linux.F.GETFL, 0);
    if (linux.errno(flags_result) != .SUCCESS) return error.TestSocketConfigureFailed;
    const nonblock: usize = @intCast(@as(u32, @bitCast(linux.O{ .NONBLOCK = true })));
    const set_result = linux.fcntl(fd, linux.F.SETFL, flags_result | nonblock);
    if (linux.errno(set_result) != .SUCCESS) return error.TestSocketConfigureFailed;
}

fn setReceiveBuffer(fd: posix.fd_t, bytes: c_int) !void {
    const result = linux.setsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.RCVBUF,
        std.mem.asBytes(&bytes).ptr,
        @sizeOf(c_int),
    );
    if (linux.errno(result) != .SUCCESS) return error.TestSocketConfigureFailed;
}

fn awaitFrame(peer: *TestPeer, server: *Server) !TestFrame {
    var turns: usize = 0;
    while (turns < 20_000) : (turns += 1) {
        try peer.readAvailable();
        if (try peer.popFrame()) |frame| return frame;
        try server.turn(1);
    }
    return error.TestTimeout;
}

const legacy_test_features = protocol.feature(.grid_snapshot) |
    protocol.feature(.resize_leader) |
    protocol.feature(.history_window);

fn handshakeWithFeatures(
    peer: *TestPeer,
    server: *Server,
    features: u64,
) !protocol.Welcome {
    var payload: [protocol.payload_bytes.hello]u8 = undefined;
    protocol.encodeHello(&payload, .{ .features = features });
    try peer.sendFrame(server, .hello, &payload);
    var frame = try awaitFrame(peer, server);
    defer frame.deinit();
    try std.testing.expectEqual(protocol.Kind.welcome, frame.kind);
    const welcome = try protocol.decodeWelcome(frame.payload);
    try std.testing.expectEqual(protocol.protocol_max_version, welcome.version);
    try std.testing.expect(welcome.features & protocol.feature(.grid_snapshot) != 0);
    return welcome;
}

fn handshake(peer: *TestPeer, server: *Server) !protocol.Welcome {
    const welcome = try handshakeWithFeatures(peer, server, legacy_test_features);
    try std.testing.expect(welcome.features & protocol.feature(.text_snapshot) == 0);
    try std.testing.expect(welcome.features & protocol.feature(.typed_input) == 0);
    return welcome;
}

fn sendObserve(peer: *TestPeer, server: *Server, after_revision: u64) !void {
    var payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&payload, .{ .after_revision = after_revision });
    try peer.sendFrame(server, .observe, &payload);
}

fn receiveSnapshot(peer: *TestPeer, server: *Server) !TestSnapshot {
    var begin_frame = try awaitFrame(peer, server);
    defer begin_frame.deinit();
    try std.testing.expectEqual(protocol.Kind.snapshot_begin, begin_frame.kind);
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
    if (begin.format != .grid_v1) return error.MalformedTestSnapshot;

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(peer.allocator);
    while (true) {
        var frame = try awaitFrame(peer, server);
        defer frame.deinit();
        switch (frame.kind) {
            .snapshot_data => try body.appendSlice(peer.allocator, frame.payload),
            .snapshot_end => {
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                try std.testing.expectEqual(begin.revision, end.revision);
                break;
            },
            else => return error.UnexpectedTestFrame,
        }
    }

    const row_bytes = 4 + @as(usize, begin.columns) * 8;
    const expected_body = @as(usize, begin.rows) * row_bytes;
    if (body.items.len != expected_body) return error.MalformedTestSnapshot;
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(peer.allocator);
    try text.ensureTotalCapacity(peer.allocator, @as(usize, begin.rows) * (@as(usize, begin.columns) + 1));
    var offset: usize = 0;
    var row: u16 = 0;
    while (row < begin.rows) : (row += 1) {
        if (body.items[offset] > 1) return error.MalformedTestSnapshot;
        if (readU16(body.items[offset + 2 .. offset + 4]) != begin.columns) return error.MalformedTestSnapshot;
        offset += 4;
        var column: u16 = 0;
        while (column < begin.columns) : (column += 1) {
            const cell = body.items[offset .. offset + 8];
            const codepoint = readU32(cell[0..4]);
            const byte: u8 = if (cell[6] != 0 or cell[7] != 0 or codepoint == 0)
                ' '
            else if (codepoint <= 0x7f)
                @intCast(codepoint)
            else
                '?';
            try text.append(peer.allocator, byte);
            offset += 8;
        }
        try text.append(peer.allocator, '\n');
    }
    return .{ .allocator = peer.allocator, .begin = begin, .text = try text.toOwnedSlice(peer.allocator) };
}

fn receiveTextSnapshot(peer: *TestPeer, server: *Server) !TestTextSnapshot {
    var begin_frame = try awaitFrame(peer, server);
    defer begin_frame.deinit();
    if (begin_frame.kind != .snapshot_begin) return error.UnexpectedTestFrame;
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
    if (begin.format != .text_v1) return error.MalformedTestSnapshot;

    var result = TestTextSnapshot{ .begin = begin };
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var phase: enum { presentation, rows, hyperlinks } = .presentation;

    while (true) {
        var frame = try awaitFrame(peer, server);
        defer frame.deinit();
        switch (frame.kind) {
            .snapshot_data => {
                if (frame.payload.len < protocol.text_v1.record_header_bytes)
                    return error.MalformedTestSnapshot;
                var header_bytes: [protocol.text_v1.record_header_bytes]u8 = undefined;
                @memcpy(&header_bytes, frame.payload[0..protocol.text_v1.record_header_bytes]);
                const record = protocol.decodeTextRecordHeader(&header_bytes) catch
                    return error.MalformedTestSnapshot;
                if (record.payload_len != frame.payload.len - protocol.text_v1.record_header_bytes)
                    return error.MalformedTestSnapshot;
                const payload = frame.payload[protocol.text_v1.record_header_bytes..];
                switch (record.kind) {
                    .presentation => {
                        if (phase != .presentation or result.presentation_seen or
                            payload.len != protocol.text_v1.presentation_bytes)
                            return error.MalformedTestSnapshot;
                        if (payload[8] & ~protocol.text_v1.presentation_presence.known != 0 or
                            payload[9] & ~protocol.text_v1.presentation_flags.known != 0 or
                            payload[10] != 0 or payload[11] != 0)
                            return error.MalformedTestSnapshot;
                        result.cursor_age_ns = readU64(payload[0..8]);
                        result.presentation_seen = true;
                        phase = .rows;
                    },
                    .row => {
                        if (phase != .rows or !result.presentation_seen or
                            result.row_count >= begin.rows)
                            return error.MalformedTestSnapshot;
                        try inspectTextRow(
                            begin,
                            payload,
                            &result,
                            &referenced,
                        );
                        result.row_count += 1;
                        if (result.row_count == begin.rows) phase = .hyperlinks;
                    },
                    .hyperlink => {
                        if (phase != .hyperlinks or payload.len < protocol.text_v1.hyperlink_header_bytes)
                            return error.MalformedTestSnapshot;
                        const id = readU32(payload[0..4]);
                        const uri_len = readU16(payload[4..6]);
                        if (id == 0 or id > protocol.text_v1.maximum_hyperlinks or
                            uri_len == 0 or uri_len > protocol.text_v1.maximum_hyperlink_uri_bytes or
                            payload.len != protocol.text_v1.hyperlink_header_bytes + uri_len or
                            resolved[id])
                            return error.MalformedTestSnapshot;
                        resolved[id] = true;
                        if (id == result.styled_link_id and
                            std.mem.eql(u8, payload[6..], "https://howl.example"))
                            result.saw_hyperlink = true;
                    },
                }
            },
            .snapshot_end => {
                const end = protocol.decodeSnapshotEnd(frame.payload) catch
                    return error.MalformedTestSnapshot;
                if (end.revision != begin.revision or !result.presentation_seen or
                    result.row_count != begin.rows)
                    return error.MalformedTestSnapshot;
                for (referenced, resolved) |needed, present| if (needed != present)
                    return error.MalformedTestSnapshot;
                return result;
            },
            else => return error.UnexpectedTestFrame,
        }
    }
}

fn inspectTextRow(
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    result: *TestTextSnapshot,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) !void {
    if (payload.len < protocol.text_v1.row_header_bytes or payload[0] > 1 or
        payload[1] > 3 or readU16(payload[2..4]) != begin.columns)
        return error.MalformedTestSnapshot;
    var offset: usize = protocol.text_v1.row_header_bytes;
    var column: u16 = 0;
    while (column < begin.columns) : (column += 1) {
        if (payload.len - offset < protocol.text_v1.cell_header_bytes)
            return error.MalformedTestSnapshot;
        const cell = payload[offset..][0..protocol.text_v1.cell_header_bytes];
        const scalar_count = cell[0];
        if (scalar_count > protocol.text_v1.maximum_cell_scalars or
            cell[1] == 0 or cell[2] == 0 or cell[3] >= cell[1] or cell[4] >= cell[2] or
            cell[5] > 15 or cell[6] > 15 or cell[7] > 3 or cell[8] > 3 or
            cell[9] > 1 or cell[10] > 15 or cell[11] > 2 or cell[12] > 4 or cell[13] > 2)
            return error.MalformedTestSnapshot;
        const style = readU16(cell[14..16]);
        if (style & ~protocol.text_v1.style.known != 0)
            return error.MalformedTestSnapshot;
        try validateTextColorBytes(cell[16..21]);
        try validateTextColorBytes(cell[21..26]);
        try validateTextColorBytes(cell[26..31]);
        const link_id = readU32(cell[31..35]);
        if (link_id > protocol.text_v1.maximum_hyperlinks)
            return error.MalformedTestSnapshot;
        if (link_id != 0) referenced[link_id] = true;

        const scalar_bytes = @as(usize, scalar_count) * 4;
        offset += protocol.text_v1.cell_header_bytes;
        if (payload.len - offset < scalar_bytes) return error.MalformedTestSnapshot;
        const scalars = payload[offset..][0..scalar_bytes];
        if ((cell[3] != 0 or cell[4] != 0) and scalar_count != 0)
            return error.MalformedTestSnapshot;
        var scalar_index: usize = 0;
        while (scalar_index < scalar_count) : (scalar_index += 1) {
            const scalar = readU32(scalars[scalar_index * 4 ..][0..4]);
            if (scalar > 0x10ffff or scalar >= 0xd800 and scalar <= 0xdfff)
                return error.MalformedTestSnapshot;
        }

        if (scalar_count == 1 and readU32(scalars[0..4]) == 'A') {
            var fg_bytes: [protocol.text_v1.color_bytes]u8 = undefined;
            var bg_bytes: [protocol.text_v1.color_bytes]u8 = undefined;
            var underline_bytes: [protocol.text_v1.color_bytes]u8 = undefined;
            @memcpy(&fg_bytes, cell[16..21]);
            @memcpy(&bg_bytes, cell[21..26]);
            @memcpy(&underline_bytes, cell[26..31]);
            const fg = try protocol.decodeTextColor(&fg_bytes);
            const bg = try protocol.decodeTextColor(&bg_bytes);
            const underline = try protocol.decodeTextColor(&underline_bytes);
            if (style & protocol.text_v1.style.bold != 0 and
                style & protocol.text_v1.style.italic != 0 and
                style & protocol.text_v1.style.underline != 0 and
                cell[12] == 2 and
                fg.kind == .rgb and fg.value == 0x112233 and
                bg.kind == .indexed and bg.value == 4 and
                underline.kind == .rgb and underline.value == 0x445566 and
                link_id != 0)
            {
                result.saw_styled_a = true;
                result.styled_link_id = link_id;
            }
        }
        if (scalar_count == 2 and readU32(scalars[0..4]) == 'e' and
            readU32(scalars[4..8]) == 0x0301)
            result.saw_combining = true;
        if (scalar_count == 1 and readU32(scalars[0..4]) == 0x4e2d and
            cell[1] == 2 and cell[3] == 0 and cell[9] == 1)
            result.saw_wide_lead = true;
        if (scalar_count == 0 and cell[1] == 2 and cell[3] == 1 and cell[9] == 1)
            result.saw_wide_continuation = true;
        if (scalar_count == 2 and readU32(scalars[0..4]) == 'H' and
            readU32(scalars[4..8]) == 'i' and cell[1] == 4 and cell[2] == 2 and
            cell[3] == 0 and cell[4] == 0 and cell[5] == 1 and cell[6] == 2 and
            cell[7] == 1 and cell[8] == 2)
            result.saw_osc66_lead = true;
        if (scalar_count == 0 and cell[1] == 4 and cell[2] == 2 and
            (cell[3] != 0 or cell[4] != 0) and cell[5] == 1 and cell[6] == 2 and
            cell[7] == 1 and cell[8] == 2)
            result.saw_osc66_continuation = true;

        offset += scalar_bytes;
    }
    if (offset != payload.len) return error.MalformedTestSnapshot;
}

fn validateTextColorBytes(bytes: []const u8) !void {
    if (bytes.len != protocol.text_v1.color_bytes) return error.MalformedTestSnapshot;
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    @memcpy(&encoded, bytes);
    const color = protocol.decodeTextColor(&encoded) catch return error.MalformedTestSnapshot;
    switch (color.kind) {
        .default, .indexed, .rgb => {},
    }
}

fn observeUntilContains(
    peer: *TestPeer,
    server: *Server,
    after_revision: u64,
    needle: []const u8,
) !TestSnapshot {
    var revision = after_revision;
    var attempts: usize = 0;
    while (attempts < 256) : (attempts += 1) {
        try sendObserve(peer, server, revision);
        var snapshot = try receiveSnapshot(peer, server);
        if (std.mem.indexOf(u8, snapshot.text, needle) != null) return snapshot;
        revision = snapshot.begin.revision;
        snapshot.deinit();
    }
    return error.TestTimeout;
}

fn sendInput(peer: *TestPeer, server: *Server, bytes: []const u8) !void {
    const payload = try peer.allocator.alloc(u8, bytes.len + 1);
    defer peer.allocator.free(payload);
    payload[0] = @backingInt(protocol.InputKind.bytes);
    @memcpy(payload[1..], bytes);
    try peer.sendFrame(server, .input, payload);
}

fn sendPaste(peer: *TestPeer, server: *Server, bytes: []const u8) !void {
    const payload = try peer.allocator.alloc(u8, bytes.len + 1);
    defer peer.allocator.free(payload);
    payload[0] = @backingInt(protocol.InputKind.paste);
    @memcpy(payload[1..], bytes);
    try peer.sendFrame(server, .input, payload);
}

fn sendTypedKey(peer: *TestPeer, server: *Server, value: protocol.KeyInput) !void {
    const body_bytes = try protocol.keyInputBytes(value);
    const payload = try peer.allocator.alloc(u8, body_bytes + 1);
    defer peer.allocator.free(payload);
    payload[0] = @backingInt(protocol.InputKind.key);
    const encoded = try protocol.encodeKeyInput(payload[1..], value);
    std.debug.assert(encoded.len == body_bytes);
    try peer.sendFrame(server, .input, payload);
}

fn sendTypedMouse(peer: *TestPeer, server: *Server, value: protocol.MouseInput) !void {
    var payload: [1 + protocol.typed_input.mouse_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.mouse);
    var encoded: [protocol.typed_input.mouse_bytes]u8 = undefined;
    try protocol.encodeMouseInput(&encoded, value);
    @memcpy(payload[1..], &encoded);
    try peer.sendFrame(server, .input, &payload);
}

fn sendTypedFocus(peer: *TestPeer, server: *Server, value: protocol.InputFocus) !void {
    var payload: [1 + protocol.typed_input.focus_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.focus);
    var encoded: [protocol.typed_input.focus_bytes]u8 = undefined;
    protocol.encodeFocusInput(&encoded, value);
    @memcpy(payload[1..], &encoded);
    try peer.sendFrame(server, .input, &payload);
}

fn sendAssignLeader(peer: *TestPeer, server: *Server, client_id: protocol.ClientId) !void {
    var payload: [protocol.payload_bytes.assign_leader]u8 = undefined;
    protocol.encodeAssignLeader(&payload, .{ .client_id = client_id });
    try peer.sendFrame(server, .assign_leader, &payload);
}

fn sendResize(peer: *TestPeer, server: *Server, rows: u16, columns: u16) !void {
    var payload: [protocol.payload_bytes.resize]u8 = undefined;
    protocol.encodeResize(&payload, .{ .rows = rows, .columns = columns });
    try peer.sendFrame(server, .resize, &payload);
}

fn sendSignal(peer: *TestPeer, server: *Server, signal_value: protocol.Signal) !void {
    var payload: [protocol.payload_bytes.signal]u8 = undefined;
    protocol.encodeSignal(&payload, signal_value);
    try peer.sendFrame(server, .signal, &payload);
}

fn expectResult(peer: *TestPeer, server: *Server, kind: protocol.Kind, code: protocol.ResultCode) !void {
    var frame = try awaitFrame(peer, server);
    defer frame.deinit();
    try std.testing.expectEqual(protocol.Kind.result, frame.kind);
    const result = try protocol.decodeResult(frame.payload);
    try std.testing.expectEqual(kind, result.request_kind);
    try std.testing.expectEqual(code, result.code);
}

fn serverClient(server: *Server, client_id: protocol.ClientId) ?*Client {
    for (&server.clients) |*slot| {
        if (slot.*) |*client| if (client.id == client_id) return client;
    }
    return null;
}

fn readU16(input: []const u8) u16 {
    std.debug.assert(input.len == 2);
    return (@as(u16, input[0]) << 8) | @as(u16, input[1]);
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        @as(u32, input[3]);
}

fn readU64(input: []const u8) u64 {
    std.debug.assert(input.len == 8);
    var value: u64 = 0;
    for (input) |byte| value = (value << 8) | byte;
    return value;
}

test "typed input is negotiated and encoded by live terminal modes" {
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buffer,
        "/tmp/howl-session-{d}-typed-input.sock",
        .{linux.getpid()},
    );
    unlinkPath(path);
    var server = try Server.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        path,
        .{
            .shell = "/bin/sh",
            .command = "stty -echo -icanon min 1 time 0; " ++
                "capture() { printf '%s:' \"$1\"; " ++
                "dd bs=1 count=\"$2\" 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'; " ++
                "printf '\\n'; }; " ++
                "printf 'NORMAL\\n'; capture normal 3; " ++
                "printf '\\033[?1hAPP_CURSOR\\n'; capture app_cursor 3; " ++
                "printf '\\033=APP_KEYPAD\\n'; capture app_keypad 3; " ++
                "printf '\\033[?1004hFOCUS\\n'; capture focus 3; " ++
                "printf '\\033[?1003h\\033[?1016hMOUSE\\n'; capture mouse 14; " ++
                "printf '\\033[?2004hPASTE\\n'; capture paste 15; " ++
                "printf '\\033[=31uKITTY_PRESS\\n'; capture kitty_press 5; " ++
                "printf 'KITTY_REPEAT\\n'; capture kitty_repeat 19; " ++
                "printf 'KITTY_RELEASE\\n'; capture kitty_release 9; " ++
                "printf 'DONE\\n'; cat",
            .rows = 24,
            .columns = 96,
            .history_rows = 64,
        },
    );
    defer server.deinit();

    var legacy = try TestPeer.connect(std.testing.allocator, path);
    defer legacy.deinit();
    const legacy_welcome = try handshake(&legacy, &server);
    try std.testing.expect(legacy_welcome.client_id != protocol.no_client);
    try std.testing.expect(legacy_welcome.features & protocol.feature(.typed_input) == 0);
    try sendTypedKey(&legacy, &server, .{
        .kind = .named,
        .key_value = @backingInt(protocol.InputKeyName.up),
        .action = .press,
    });
    try expectResult(&legacy, &server, .input, .unsupported);

    var peer = try TestPeer.connect(std.testing.allocator, path);
    defer peer.deinit();
    const welcome = try handshakeWithFeatures(
        &peer,
        &server,
        legacy_test_features | protocol.feature(.typed_input),
    );
    try std.testing.expect(welcome.features & protocol.feature(.typed_input) != 0);

    try peer.sendFrame(&server, .input, &.{ @backingInt(protocol.InputKind.key), 0xff });
    try expectResult(&peer, &server, .input, .malformed);

    var ready = try observeUntilContains(&peer, &server, 0, "NORMAL");
    var revision = ready.begin.revision;
    ready.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .named,
        .key_value = @backingInt(protocol.InputKeyName.up),
        .action = .press,
    });
    try expectResult(&peer, &server, .input, .ok);
    var app_cursor = try observeUntilContains(&peer, &server, revision, "APP_CURSOR");
    try std.testing.expect(std.mem.indexOf(u8, app_cursor.text, "normal:1b5b41") != null);
    revision = app_cursor.begin.revision;
    app_cursor.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .named,
        .key_value = @backingInt(protocol.InputKeyName.up),
        .action = .press,
    });
    try expectResult(&peer, &server, .input, .ok);
    var app_keypad = try observeUntilContains(&peer, &server, revision, "APP_KEYPAD");
    try std.testing.expect(std.mem.indexOf(u8, app_keypad.text, "app_cursor:1b4f41") != null);
    revision = app_keypad.begin.revision;
    app_keypad.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .named,
        .key_value = @backingInt(protocol.InputKeyName.keypad_add),
        .action = .press,
    });
    try expectResult(&peer, &server, .input, .ok);
    var focus = try observeUntilContains(&peer, &server, revision, "FOCUS");
    try std.testing.expect(std.mem.indexOf(u8, focus.text, "app_keypad:1b4f6b") != null);
    revision = focus.begin.revision;
    focus.deinit();

    try sendTypedFocus(&peer, &server, .in);
    try expectResult(&peer, &server, .input, .ok);
    var mouse = try observeUntilContains(&peer, &server, revision, "MOUSE");
    try std.testing.expect(std.mem.indexOf(u8, mouse.text, "focus:1b5b49") != null);
    revision = mouse.begin.revision;
    mouse.deinit();

    try sendTypedMouse(&peer, &server, .{
        .kind = .press,
        .button = .left,
        .modifiers = protocol.typed_input.modifiers.control,
        .buttons_down = 1,
        .row = 1,
        .column = 2,
        .pixel_x = 319,
        .pixel_y = 239,
    });
    try expectResult(&peer, &server, .input, .ok);
    var paste = try observeUntilContains(&peer, &server, revision, "PASTE");
    try std.testing.expect(std.mem.indexOf(
        u8,
        paste.text,
        "mouse:1b5b3c31363b3332303b3234304d",
    ) != null);
    revision = paste.begin.revision;
    paste.deinit();

    try sendPaste(&peer, &server, "x\x00y");
    try expectResult(&peer, &server, .input, .ok);
    var kitty_press = try observeUntilContains(&peer, &server, revision, "KITTY_PRESS");
    try std.testing.expect(std.mem.indexOf(
        u8,
        kitty_press.text,
        "paste:1b5b3230307e7800791b5b3230317e",
    ) != null);
    revision = kitty_press.begin.revision;
    kitty_press.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .unicode,
        .key_value = 'a',
        .action = .press,
    });
    try expectResult(&peer, &server, .input, .ok);
    var kitty_repeat = try observeUntilContains(&peer, &server, revision, "KITTY_REPEAT");
    try std.testing.expect(std.mem.indexOf(u8, kitty_repeat.text, "kitty_press:1b5b393775") != null);
    revision = kitty_repeat.begin.revision;
    kitty_repeat.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .unicode,
        .key_value = 'a',
        .action = .repeat,
        .modifiers = protocol.typed_input.modifiers.shift,
        .shifted = 'A',
        .alternate = 'q',
        .text = "A",
    });
    try expectResult(&peer, &server, .input, .ok);
    var kitty_release = try observeUntilContains(&peer, &server, revision, "KITTY_RELEASE");
    try std.testing.expect(std.mem.indexOf(
        u8,
        kitty_release.text,
        "kitty_repeat:1b5b39373a36353a3131333b323a323b363575",
    ) != null);
    revision = kitty_release.begin.revision;
    kitty_release.deinit();

    try sendTypedKey(&peer, &server, .{
        .kind = .unicode,
        .key_value = 'a',
        .action = .release,
    });
    try expectResult(&peer, &server, .input, .ok);
    var done = try observeUntilContains(&peer, &server, revision, "DONE");
    defer done.deinit();
    try std.testing.expect(std.mem.indexOf(u8, done.text, "kitty_release:1b5b39373b313a3375") != null);
}

test "text_v1 preserves renderer-complete terminal text semantics" {
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buffer,
        "/tmp/howl-session-{d}-text-v1.sock",
        .{linux.getpid()},
    );
    unlinkPath(path);
    var server = try Server.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        path,
        .{
            .shell = "/bin/sh",
            .command = "stty -echo -icanon min 1 time 0; " ++
                "printf '\\033[1;1H'; " ++
                "printf '\\033[1;3;4:3;38;2;17;34;51;48;5;4;58;2;68;85;102m'; " ++
                "printf '\\033]8;id=rich;https://howl.example\\033\\\\'; " ++
                "printf 'A'; " ++
                "printf '\\033]8;;\\033\\\\'; " ++
                "printf 'e\\314\\201\\344\\270\\255'; " ++
                "printf '\\033]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\\033\\\\'; " ++
                "printf '\\033[0m\\n'; cat",
            .rows = 6,
            .columns = 16,
            .history_rows = 64,
        },
    );
    defer server.deinit();

    var peer = try TestPeer.connect(std.testing.allocator, path);
    defer peer.deinit();
    const welcome = try handshakeWithFeatures(
        &peer,
        &server,
        legacy_test_features | protocol.feature(.text_snapshot),
    );
    try std.testing.expect(welcome.features & protocol.feature(.text_snapshot) != 0);

    var attempts: usize = 0;
    var revision: u64 = 0;
    while (attempts < 256) : (attempts += 1) {
        try sendObserve(&peer, &server, revision);
        const snapshot = try receiveTextSnapshot(&peer, &server);
        revision = snapshot.begin.revision;
        if (!snapshot.saw_styled_a or !snapshot.saw_combining or
            !snapshot.saw_wide_lead or !snapshot.saw_wide_continuation or
            !snapshot.saw_osc66_lead or !snapshot.saw_osc66_continuation or
            !snapshot.saw_hyperlink)
            continue;

        try std.testing.expect(snapshot.presentation_seen);
        try std.testing.expectEqual(@as(u16, 6), snapshot.begin.rows);
        try std.testing.expectEqual(@as(u16, 16), snapshot.begin.columns);
        try std.testing.expect(snapshot.styled_link_id != 0);
        try std.testing.expect(snapshot.cursor_age_ns != protocol.text_v1.no_cursor_movement_age_ns);
        return;
    }
    return error.TestTimeout;
}

test "Unix clients share one session and explicit geometry authority" {
    var stage: []const u8 = "server init";
    errdefer std.debug.print("shared-session proof failed during {s}\n", .{stage});
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "/tmp/howl-session-{d}-shared.sock", .{linux.getpid()});
    unlinkPath(path);
    var server = try Server.init(std.testing.allocator, std.testing.io, std.testing.environ, path, .{
        .shell = "/bin/sh",
        .command = "stty -echo -icanon min 1 time 0; printf 'READY\\n'; cat",
        .rows = 8,
        .columns = 40,
        .history_rows = 512,
    });
    defer server.deinit();

    var first = try TestPeer.connect(std.testing.allocator, path);
    defer first.deinit();
    var second = try TestPeer.connect(std.testing.allocator, path);
    defer second.deinit();
    stage = "handshake";
    const first_welcome = try handshake(&first, &server);
    const second_welcome = try handshake(&second, &server);
    try std.testing.expect(first_welcome.client_id != second_welcome.client_id);

    stage = "initial observation";
    var first_ready = try observeUntilContains(&first, &server, 0, "READY");
    defer first_ready.deinit();
    var second_ready = try observeUntilContains(&second, &server, 0, "READY");
    defer second_ready.deinit();

    stage = "shared input";
    try sendInput(&first, &server, "SHARED-LINE\n");
    try expectResult(&first, &server, .input, .ok);
    var shared = try observeUntilContains(&second, &server, second_ready.begin.revision, "SHARED-LINE");
    defer shared.deinit();

    stage = "resize authority";
    try sendAssignLeader(&first, &server, first_welcome.client_id);
    try expectResult(&first, &server, .assign_leader, .ok);
    try sendResize(&second, &server, 10, 50);
    try expectResult(&second, &server, .resize, .not_leader);
    try sendResize(&first, &server, 10, 50);
    try expectResult(&first, &server, .resize, .ok);

    stage = "resized observation";
    try sendObserve(&second, &server, shared.begin.revision);
    var resized = try receiveSnapshot(&second, &server);
    defer resized.deinit();
    try std.testing.expectEqual(@as(u16, 10), resized.begin.rows);
    try std.testing.expectEqual(@as(u16, 50), resized.begin.columns);
    try std.testing.expect(resized.begin.leader_present);
    try std.testing.expect(!resized.begin.you_are_leader);

    stage = "loaded continuation";
    var load: std.ArrayList(u8) = .empty;
    defer load.deinit(std.testing.allocator);
    try load.appendNTimes(std.testing.allocator, 'x', 12_000);
    try load.appendSlice(std.testing.allocator, "\nFINAL-REATTACH\n");
    try sendInput(&second, &server, load.items);
    try expectResult(&second, &server, .input, .ok);
    var loaded = try observeUntilContains(&second, &server, resized.begin.revision, "FINAL-REATTACH");
    defer loaded.deinit();

    stage = "leader disconnect";
    first.closeSocket();
    try sendObserve(&second, &server, loaded.begin.revision);
    var leader_gone = try receiveSnapshot(&second, &server);
    defer leader_gone.deinit();
    try std.testing.expect(!leader_gone.begin.leader_present);
    try std.testing.expectEqual(@as(u16, 10), leader_gone.begin.rows);
    try std.testing.expectEqual(@as(u16, 50), leader_gone.begin.columns);

    stage = "reattach";
    var reattached = try TestPeer.connect(std.testing.allocator, path);
    defer reattached.deinit();
    const reattached_welcome = try handshake(&reattached, &server);
    try std.testing.expect(reattached_welcome.client_id != protocol.no_client);
    var current = try observeUntilContains(&reattached, &server, 0, "FINAL-REATTACH");
    defer current.deinit();
    try std.testing.expectEqual(@as(u16, 10), current.begin.rows);
    try std.testing.expectEqual(@as(u16, 50), current.begin.columns);
    try std.testing.expect(!current.begin.leader_present);

    stage = "child exit";
    try sendSignal(&reattached, &server, .terminate);
    try expectResult(&reattached, &server, .signal, .ok);
    var lifecycle_revision = current.begin.revision;
    var observed_exit = false;
    var attempts: usize = 0;
    while (attempts < 16 and !observed_exit) : (attempts += 1) {
        try sendObserve(&reattached, &server, lifecycle_revision);
        var exited = try receiveSnapshot(&reattached, &server);
        defer exited.deinit();
        lifecycle_revision = exited.begin.revision;
        observed_exit = exited.begin.child_exited;
    }
    try std.testing.expect(observed_exit);
}

test "slow Unix observer cannot pace PTY or healthy client" {
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "/tmp/howl-session-{d}-slow.sock", .{linux.getpid()});
    unlinkPath(path);
    var server = try Server.init(std.testing.allocator, std.testing.io, std.testing.environ, path, .{
        .shell = "/bin/sh",
        .command = "stty -echo -icanon min 1 time 0; cat",
        .rows = 512,
        .columns = 512,
        .history_rows = 16,
    });
    defer server.deinit();

    var slow = try TestPeer.connect(std.testing.allocator, path);
    defer slow.deinit();
    var healthy = try TestPeer.connect(std.testing.allocator, path);
    defer healthy.deinit();
    const slow_welcome = try handshake(&slow, &server);
    const healthy_welcome = try handshake(&healthy, &server);
    try std.testing.expect(healthy_welcome.client_id != protocol.no_client);
    try setReceiveBuffer(slow.fd, 4096);

    try sendObserve(&slow, &server, 0);
    var turn: usize = 0;
    while (turn < 64) : (turn += 1) try server.turn(0);
    const blocked = serverClient(&server, slow_welcome.client_id) orelse return error.SlowClientMissing;
    try std.testing.expect(blocked.output.items.len > 1024 * 1024);
    try std.testing.expect(blocked.outputPending());
    try std.testing.expect(blocked.output_offset < blocked.output.items.len);

    try sendInput(&healthy, &server, "FLOW-CONTINUES\n");
    try expectResult(&healthy, &server, .input, .ok);
    var progressed = try observeUntilContains(&healthy, &server, 0, "FLOW-CONTINUES");
    defer progressed.deinit();
    try std.testing.expectEqual(@as(u16, 512), progressed.begin.rows);
    try std.testing.expectEqual(@as(u16, 512), progressed.begin.columns);

    const still_blocked = serverClient(&server, slow_welcome.client_id) orelse return error.SlowClientMissing;
    try std.testing.expect(still_blocked.outputPending());
    try std.testing.expect(still_blocked.output_offset < still_blocked.output.items.len);
}

test "oversized observation is local rejection not session failure" {
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "/tmp/howl-session-{d}-oversize.sock", .{linux.getpid()});
    unlinkPath(path);
    var server = try Server.init(std.testing.allocator, std.testing.io, std.testing.environ, path, .{
        .shell = "/bin/sh",
        .command = "stty -echo -icanon min 1 time 0; printf 'ALIVE\\n'; cat",
        .rows = 512,
        .columns = 1024,
        .history_rows = 16,
    });
    defer server.deinit();

    var peer = try TestPeer.connect(std.testing.allocator, path);
    defer peer.deinit();
    const welcome = try handshake(&peer, &server);

    try sendObserve(&peer, &server, 0);
    try expectResult(&peer, &server, .observe, .rejected);

    try sendAssignLeader(&peer, &server, welcome.client_id);
    try expectResult(&peer, &server, .assign_leader, .ok);
    try sendResize(&peer, &server, 8, 40);
    try expectResult(&peer, &server, .resize, .ok);

    var recovered = try observeUntilContains(&peer, &server, 0, "ALIVE");
    defer recovered.deinit();
    try std.testing.expectEqual(@as(u16, 8), recovered.begin.rows);
    try std.testing.expectEqual(@as(u16, 40), recovered.begin.columns);
    try std.testing.expect(recovered.begin.you_are_leader);
}

test "oversized text_v1 observation is local rejection and recovers" {
    var path_buffer: [108]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buffer,
        "/tmp/howl-session-{d}-text-oversize.sock",
        .{linux.getpid()},
    );
    unlinkPath(path);
    var server = try Server.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        path,
        .{
            .shell = "/bin/sh",
            .command = "stty -echo -icanon min 1 time 0; printf 'TEXT-ALIVE\\n'; cat",
            .rows = 512,
            .columns = 1024,
            .history_rows = 16,
        },
    );
    defer server.deinit();

    var peer = try TestPeer.connect(std.testing.allocator, path);
    defer peer.deinit();
    const welcome = try handshakeWithFeatures(
        &peer,
        &server,
        legacy_test_features | protocol.feature(.text_snapshot),
    );
    try std.testing.expect(welcome.features & protocol.feature(.text_snapshot) != 0);

    try sendObserve(&peer, &server, 0);
    try expectResult(&peer, &server, .observe, .rejected);

    try sendAssignLeader(&peer, &server, welcome.client_id);
    try expectResult(&peer, &server, .assign_leader, .ok);
    try sendResize(&peer, &server, 8, 40);
    try expectResult(&peer, &server, .resize, .ok);

    try sendObserve(&peer, &server, 0);
    const recovered = try receiveTextSnapshot(&peer, &server);
    try std.testing.expectEqual(@as(u16, 8), recovered.begin.rows);
    try std.testing.expectEqual(@as(u16, 40), recovered.begin.columns);
    try std.testing.expect(recovered.begin.you_are_leader);
}
