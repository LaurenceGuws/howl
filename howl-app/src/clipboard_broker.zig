//! One process-wide clipboard admission and owned provider handoff.
//! The worker alone mutates VT; the main-thread provider never borrows VT.
//! No OS calls or consent UI live here. A host selects this service explicitly.
const std = @import("std");
const Terminal = @import("howl_vt").Terminal;

/// A request cannot survive a pane occurrence or reset-epoch change.
pub const Ticket = struct {
    owner: u64,
    epoch: u64,
    start: u64,
};
/// The exact final packet which requires the provider's recorded outcome.
pub const Completion = struct {
    ticket: Ticket,
    end: u64,
};
/// One copied prompt, with no untrusted program-supplied name or password.
pub const Prompt = struct {
    ticket: Ticket,
    expires_ns: u64,
};
/// Copied main-thread wake fact; neither variant borrows the worker.
pub const Notice = union(enum) {
    prompt: Prompt,
    prepared: Ticket,
    inventory: Ticket,
};

/// Complete bounded host inventory. Names are stored once with newline
/// separators; the worker borrows slices only during reply serialization.
pub const Inventory = struct {
    /// Maximum number of complete retained names.
    pub const max_names = 256;
    /// Maximum total metadata bytes including separators.
    pub const max_bytes = 4096;
    bytes: [max_bytes]u8 = undefined,
    len: u16 = 0,
    count: u16 = 0,

    /// Append a complete metadata token, never a partial or malformed name.
    pub fn append(self: *Inventory, name: []const u8) error{InvalidInventory}!void {
        if (self.count == max_names or name.len == 0 or name.len >= max_bytes - @as(usize, self.len) or
            std.mem.eql(u8, name, ".") or !std.unicode.utf8ValidateSlice(name)) return error.InvalidInventory;
        for (name) |byte| if (byte <= 0x20 or byte == 0x7f) return error.InvalidInventory;
        @memcpy(self.bytes[self.len..][0..name.len], name);
        self.len += @intCast(name.len);
        self.bytes[self.len] = '\n';
        self.len += 1;
        self.count += 1;
    }

    fn names(self: *const Inventory, scratch: *[max_names][]const u8) []const []const u8 {
        var tokens = std.mem.tokenizeScalar(u8, self.bytes[0..self.len], '\n');
        var count: usize = 0;
        while (tokens.next()) |name| : (count += 1) scratch[count] = name;
        std.debug.assert(count == self.count);
        return scratch[0..count];
    }
};

/// Provider returns metadata only, or an opening read failure.
pub const InventoryResult = union(enum) {
    available: Inventory,
    unavailable,
    busy,
};

/// Ownership has moved to the provider. It must retire or adopt the data
/// exactly once, then report its outcome; no mutable VT reference escapes.
pub const Publication = struct {
    completion: Completion,
    data: Terminal.KittyWriteData,
};

/// A bounded worker turn. Waiting does not request a zero-timeout retry.
pub const Service = enum { unhandled, progressed, waiting };
const deadline_ns: u64 = 30 * std.time.ns_per_s;
const Phase = union(enum) {
    pending,
    approved,
    staging,
    prepared: struct { end: u64, data: Terminal.KittyWriteData },
    publishing: u64,
    outcome: struct { end: u64, status: Terminal.KittyWriteStatus },
    revoked: bool, // true if VT has admitted a writer
    inventory_pending,
    inventory_fetching: bool, // true if revoked during provider call
    inventory_ready: InventoryResult,
    inventory_denied,
};
const Slot = struct {
    ticket: Ticket,
    expires_ns: u64,
    phase: Phase,
    retired: bool = false,
};

/// Shared mailbox for the selected host service. All state transitions are
/// serialized by this lock; no provider call or UI wait is made under it.
/// The main owner must wake affected workers after a decision/focus/result
/// change, and arrange a deadline wake. The default app has no provider.
pub const Broker = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    focused: ?u64 = null,
    slot: ?Slot = null,

    /// Initialize one broker shared by the process's selected workers.
    pub fn init(io: std.Io) Broker {
        return .{ .io = io };
    }

    /// After workers and the synchronous provider retire, free any offer.
    pub fn deinit(self: *Broker) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.clear();
    }

    fn clear(self: *Broker) void {
        if (self.slot) |*slot| {
            if (slot.phase == .prepared) slot.phase.prepared.data.deinit();
        }
        self.slot = null;
    }

    fn revoke(slot: *Slot) void {
        switch (slot.phase) {
            .pending, .approved => slot.phase = .{ .revoked = false },
            .staging => slot.phase = .{ .revoked = true },
            .prepared => |*prepared| {
                prepared.data.deinit();
                slot.phase = .{ .revoked = true };
            },
            // Provider admission is the irreversible boundary. A later
            // focus change cannot pretend an already published offer failed.
            .publishing, .outcome, .revoked => {},
            .inventory_pending, .inventory_ready => slot.phase = .inventory_denied,
            .inventory_fetching => slot.phase.inventory_fetching = true,
            .inventory_denied => {},
        }
    }

    fn expire(self: *Broker, now: u64) void {
        if (self.slot) |*slot| {
            if (now >= slot.expires_ns) revoke(slot);
        }
    }

    fn retire(self: *Broker, slot: *Slot) void {
        if (slot.phase == .publishing or slot.phase == .inventory_fetching) {
            // The provider still owns its data. Hold the global slot until
            // its matching result arrives, but never acknowledge a dead VT.
            slot.retired = true;
        } else {
            self.clear();
        }
    }

    /// Focus is trusted host state, not permission. Losing the exact owner
    /// revokes an uncommitted request even if focus later returns.
    pub fn setFocus(self: *Broker, owner: ?u64, now: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.focused = owner;
        self.expire(now);
        if (self.slot) |*slot| {
            if (owner != slot.ticket.owner) revoke(slot);
        }
    }

    /// An observed newer clipboard selection supersedes uncommitted work.
    /// Do not change focus, inherit consent or undo an admitted provider call.
    pub fn supersede(self: *Broker) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.slot) |*slot| revoke(slot);
    }

    /// Copied current focus fact, for main-thread reconciliation.
    pub fn focusedOwner(self: *Broker) ?u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.focused;
    }

    /// Exact copied wake fact for one worker. No allocation or VT borrow.
    pub fn noticeFor(self: *Broker, owner: u64) ?Notice {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return null;
        if (slot.ticket.owner != owner or slot.retired) return null;
        return switch (slot.phase) {
            .pending => .{ .prompt = .{ .ticket = slot.ticket, .expires_ns = slot.expires_ns } },
            .prepared => .{ .prepared = slot.ticket },
            .inventory_pending => .{ .inventory = slot.ticket },
            else => null,
        };
    }

    /// Exact worker deadline; idle sibling workers need not poll for it.
    pub fn deadlineFor(self: *Broker, owner: u64) ?u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return null;
        if (slot.ticket.owner != owner or slot.retired) return null;
        return switch (slot.phase) {
            .pending, .approved, .staging, .prepared, .inventory_pending, .inventory_ready => slot.expires_ns,
            .inventory_fetching => |revoked| if (revoked) null else slot.expires_ns,
            else => null,
        };
    }

    /// Before stop/join, prevent a new publication for this owner. The
    /// worker still owns staging until it has retired its actual bytes.
    pub fn revokeOwner(self: *Broker, owner: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.focused == owner) self.focused = null;
        if (self.slot) |*slot| if (slot.ticket.owner == owner) revoke(slot);
    }

    /// Borrow no VT data: return a small copied prompt to the main owner.
    pub fn prompt(self: *Broker, now: u64) ?Prompt {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        // Only the scheduled worker expires its slot. Read-only UI
        // queries must not remove the worker's pending deadline.
        const slot = if (self.slot) |*value| value else return null;
        if (slot.phase != .pending or now >= slot.expires_ns) return null;
        return .{ .ticket = slot.ticket, .expires_ns = slot.expires_ns };
    }

    /// Allow once or deny the exact pending request. A stale decision cannot
    /// authorize a later request even if its pane index has been reused.
    pub fn decide(self: *Broker, ticket: Ticket, allow: bool, now: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return false;
        if (!std.meta.eql(ticket, slot.ticket) or slot.phase != .pending or self.focused != ticket.owner or now >= slot.expires_ns) return false;
        if (allow) {
            slot.phase = .approved;
            slot.expires_ns = now +| deadline_ns;
        } else {
            revoke(slot);
        }
        return true;
    }

    /// Return the next absolute wake deadline to the host scheduler.
    pub fn deadline(self: *Broker) ?u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return null;
        return switch (slot.phase) {
            .pending, .approved, .staging, .prepared, .inventory_pending, .inventory_ready => slot.expires_ns,
            .inventory_fetching => |revoked| if (revoked) null else slot.expires_ns,
            else => null,
        };
    }

    /// Main-thread admission of one exact focused metadata-only query.
    /// Provider access is outside the lock and cannot borrow VT.
    pub fn takeInventory(self: *Broker, ticket: Ticket, now: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return false;
        if (!std.meta.eql(ticket, slot.ticket) or self.focused != ticket.owner or slot.phase != .inventory_pending or now >= slot.expires_ns) return false;
        slot.phase = .{ .inventory_fetching = false };
        return true;
    }

    /// Retain one complete snapshot or opening failure. A superseded,
    /// expired, retired or wrong-owner result cannot reach the child.
    pub fn recordInventory(self: *Broker, ticket: Ticket, result: InventoryResult, now: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return false;
        if (!std.meta.eql(ticket, slot.ticket) or slot.phase != .inventory_fetching) return false;
        if (slot.retired) {
            self.clear();
        } else if (slot.phase.inventory_fetching or self.focused != ticket.owner or now >= slot.expires_ns) {
            slot.phase = .inventory_denied;
        } else {
            slot.phase = .{ .inventory_ready = result };
        }
        return true;
    }

    /// Main-thread admission of the exact prepared offer. Call the provider
    /// synchronously after this move, outside the lock; do not yield to a
    /// different focus/permission event between admission and publication.
    pub fn takePublication(self: *Broker, ticket: Ticket, now: u64) ?Publication {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return null;
        if (!std.meta.eql(ticket, slot.ticket) or self.focused != ticket.owner or slot.phase != .prepared or now >= slot.expires_ns) return null;
        const prepared = slot.phase.prepared;
        slot.phase = .{ .publishing = prepared.end };
        return .{ .completion = .{ .ticket = ticket, .end = prepared.end }, .data = prepared.data };
    }

    /// Record one provider outcome. Reply-pressure retries serialize only
    /// this status and can never take the publication or invoke it again.
    pub fn recordOutcome(self: *Broker, completion: Completion, status: Terminal.KittyWriteStatus) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const slot = if (self.slot) |*value| value else return false;
        if (!std.meta.eql(completion.ticket, slot.ticket) or slot.phase != .publishing or slot.phase.publishing != completion.end) return false;
        if (slot.retired) {
            self.clear();
        } else {
            slot.phase = .{ .outcome = .{ .end = completion.end, .status = status } };
        }
        return true;
    }

    /// Call only after the exact worker has stopped and its VT is retired.
    /// A new pane cannot inherit the retired worker's grant.
    pub fn retireOwner(self: *Broker, owner: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.focused == owner) self.focused = null;
        if (self.slot) |*slot| if (slot.ticket.owner == owner) self.retire(slot);
    }

    /// Sole worker services the selected clipboard head or active revocation.
    /// Non-write heads retain the app's existing policy. No provider/GUI
    /// wait occurs in this turn; the broker retains at most one transaction.
    pub fn service(self: *Broker, terminal: *Terminal, now: u64) Terminal.KittyReadReplyError!Service {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const owner = terminal.observation().occurrenceIdentity();
        const epoch = terminal.resetSequence();
        if (self.slot) |*slot| {
            if (slot.ticket.owner == owner and !slot.retired) {
                if (slot.ticket.epoch != epoch) {
                    const inventory = switch (slot.phase) {
                        .inventory_pending, .inventory_fetching, .inventory_ready, .inventory_denied => true,
                        else => false,
                    };
                    // RIS retains unstarted raw consequences. Do not turn
                    // the old inventory request into a fresh permission
                    // just because its raw FIFO head survived the reset.
                    if (inventory) {
                        if (terminal.consequenceHead()) |head| {
                            if (head.id() == slot.ticket.start) {
                                try terminal.replyKittyClipboardRead(head.id(), .denied);
                                self.retire(slot);
                                return .progressed;
                            }
                        }
                    }
                    self.retire(slot);
                } else if (now >= slot.expires_ns) {
                    revoke(slot);
                }
            }
        }

        if (self.slot) |*slot| {
            if (slot.ticket.owner == owner and !slot.retired) {
                switch (slot.phase) {
                    .revoked => |started| {
                        if (started) {
                            const aborted = try terminal.abortKittyClipboardWrite(.EPERM);
                            std.debug.assert(aborted);
                        } else {
                            try terminal.rejectKittyClipboardWrite(slot.ticket.start, .EPERM);
                        }
                        self.clear();
                        return .progressed;
                    },
                    .pending, .prepared, .publishing => return .waiting,
                    .approved => {
                        terminal.beginKittyClipboardWrite(slot.ticket.start, .clipboard) catch |failure| switch (failure) {
                            error.OutOfMemory => {
                                try terminal.rejectKittyClipboardWrite(slot.ticket.start, .EIO);
                                self.clear();
                                return .progressed;
                            },
                            else => return failure,
                        };
                        slot.phase = .staging;
                        return .progressed;
                    },
                    .outcome => |result| {
                        try terminal.acknowledgeKittyClipboardWrite(result.end, result.status);
                        self.clear();
                        return .progressed;
                    },
                    .inventory_pending, .inventory_fetching => return .waiting,
                    .inventory_denied => {
                        try terminal.replyKittyClipboardRead(slot.ticket.start, .denied);
                        self.clear();
                        return .progressed;
                    },
                    .inventory_ready => |*result| {
                        switch (result.*) {
                            .available => |*inventory| {
                                var names: [Inventory.max_names][]const u8 = undefined;
                                try terminal.replyKittyClipboardInventory(slot.ticket.start, inventory.names(&names));
                            },
                            .unavailable => try terminal.replyKittyClipboardRead(slot.ticket.start, .unavailable),
                            .busy => try terminal.replyKittyClipboardRead(slot.ticket.start, .busy),
                        }
                        self.clear();
                        return .progressed;
                    },
                    .staging => {},
                }
            }
        }

        const head = terminal.consequenceHead() orelse return .unhandled;
        if (head != .clipboard or head.clipboard.protocol != .kitty_5522) return .unhandled;
        const id = head.id();
        var read_scratch: Terminal.KittyReadScratch = undefined;
        if (try terminal.inspectKittyClipboardRead(id, &read_scratch)) |read| {
            // Only the exact period request is a metadata query. Mixed
            // requests and all other MIME reads retain existing refusal.
            if (!std.mem.eql(u8, read.mime_types, ".")) return .unhandled;
            if (self.focused != owner) {
                try terminal.replyKittyClipboardRead(id, .denied);
            } else if (read.location != .clipboard) {
                try terminal.replyKittyClipboardRead(id, .unavailable);
            } else if (self.slot != null) {
                try terminal.replyKittyClipboardRead(id, .busy);
            } else {
                self.slot = .{
                    .ticket = .{ .owner = owner, .epoch = epoch, .start = id },
                    .expires_ns = now +| deadline_ns,
                    .phase = .inventory_pending,
                };
                return .waiting;
            }
            return .progressed;
        }
        if (try terminal.inspectKittyClipboardWrite(id)) |location| {
            if (self.slot) |*slot| {
                if (slot.ticket.owner == owner and slot.phase == .staging) {
                    // A replacement start cannot inherit consent. Reject it
                    // and retire the previous staging in the same VT action.
                    try terminal.rejectKittyClipboardWrite(id, .EBUSY);
                    self.clear();
                    return .progressed;
                }
            }
            const refusal: ?Terminal.KittyWriteFailure = if (self.focused != owner)
                .EPERM
            else if (location != .clipboard)
                .ENOSYS
            else if (self.slot != null)
                .EBUSY
            else
                null;
            if (refusal) |failure| {
                try terminal.rejectKittyClipboardWrite(id, failure);
                return .progressed;
            }
            self.slot = .{
                .ticket = .{ .owner = owner, .epoch = epoch, .start = id },
                .expires_ns = now +| deadline_ns,
                .phase = .pending,
            };
            return .waiting;
        }
        if (self.slot) |*slot| {
            if (slot.ticket.owner == owner and slot.phase == .staging) {
                const progress = terminal.stageKittyClipboardWrite(id) catch |failure| switch (failure) {
                    error.InvalidClipboardResponse => {
                        // A recognized malformed replacement start belongs
                        // to the refusal lane, not the old admitted writer.
                        try terminal.declineKittyClipboard(id);
                        self.clear();
                        return .progressed;
                    },
                    else => return failure,
                };
                switch (progress) {
                    .staged => return .progressed,
                    .ready => {
                        slot.phase = .{ .prepared = .{ .end = id, .data = try terminal.takeKittyClipboardWrite(id) } };
                        return .waiting;
                    },
                    .aborted, .ignored => {
                        self.clear();
                        return .progressed;
                    },
                }
            }
        }
        return .unhandled;
    }
};

const start_packet = "\x1b]5522;type=write:id=route\x07";
const data_packet = "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;AAEC/w==\x07";
const alias_packet = "\x1b]5522;type=walias:mime=dGV4dC9wbGFpbg==;dGV4dC9odG1s\x07";
const end_packet = "\x1b]5522;type=wdata\x07";

fn feed(terminal: *Terminal, bytes: []const u8) !void {
    try std.testing.expect((try terminal.feed(bytes)).stateChanged());
}

fn prepare(broker: *Broker, terminal: *Terminal, now: u64) !Ticket {
    const owner = terminal.observation().occurrenceIdentity();
    broker.setFocus(owner, now);
    try feed(terminal, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(terminal, now));
    const ticket = broker.prompt(now).?.ticket;
    try std.testing.expectEqual(owner, ticket.owner);
    try std.testing.expect(broker.decide(ticket, true, now));
    try std.testing.expectEqual(Service.progressed, try broker.service(terminal, now));
    try feed(terminal, data_packet ++ alias_packet ++ end_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(terminal, now));
    try std.testing.expectEqual(Service.progressed, try broker.service(terminal, now));
    try std.testing.expectEqual(Service.waiting, try broker.service(terminal, now));
    return ticket;
}

test "clipboard broker moves one complete offer and retries acknowledgement without replaying publication" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const ticket = try prepare(&broker, &terminal, 1);
    const end = terminal.consequenceHead().?.id();
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    // A synthetic provider is deliberately selected only on the main side.
    var publication = broker.takePublication(ticket, 2).?;
    defer publication.data.deinit();
    const view = publication.data.view();
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 255 }, view.get("text/plain").?);
    try std.testing.expectEqual(view.get("text/plain").?.ptr, view.get("text/html").?.ptr);
    try std.testing.expectEqual(end, publication.completion.end);
    try std.testing.expect(broker.takePublication(ticket, 2) == null);
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.takeKittyClipboardWrite(end));
    try std.testing.expectError(error.ReplyRequired, terminal.consumeConsequence(end));
    // Saturate the real reply queue before recording the provider result.
    while (terminal.replyBytes().len < 65532) {
        const before = terminal.replyBytes().len;
        const summary = try terminal.feed("\x1b[5n");
        try std.testing.expect(!summary.titleChanged());
        try std.testing.expectEqual(before + 4, terminal.replyBytes().len);
    }
    try std.testing.expectEqual(@as(usize, 65532), terminal.replyBytes().len);
    try std.testing.expect(!broker.recordOutcome(.{ .ticket = ticket, .end = end + 1 }, .DONE));
    try std.testing.expect(broker.recordOutcome(publication.completion, .DONE));
    try std.testing.expect(!broker.recordOutcome(publication.completion, .EIO));
    try std.testing.expectError(error.ReplyLimit, broker.service(&terminal, 3));
    try std.testing.expectEqual(end, terminal.consequenceHead().?.id());
    try std.testing.expect(broker.takePublication(ticket, 3) == null);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    // Focus loss after the admitted effect cannot falsify its outcome.
    broker.setFocus(null, 4);
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=DONE:id=route\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqual(Service.unhandled, try broker.service(&terminal, 4));
}

test "clipboard broker denies background and primary writes and never reuses revoked consent" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var first = try Terminal.init(std.testing.allocator, 3, 8);
    defer first.deinit();
    var second = try Terminal.init(std.testing.allocator, 3, 8);
    defer second.deinit();
    const a = first.observation().occurrenceIdentity();
    const b = second.observation().occurrenceIdentity();
    broker.setFocus(a, 0);
    try feed(&second, start_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(&second, 0));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=route\x1b\\", second.replyBytes());
    try second.consumeReplyBytes(second.replyBytes().len);
    try feed(&first, "\x1b]5522;type=write:loc=primary:id=p\x07");
    try std.testing.expectEqual(Service.progressed, try broker.service(&first, 0));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=ENOSYS:id=p\x1b\\", first.replyBytes());
    try first.consumeReplyBytes(first.replyBytes().len);
    try feed(&first, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(&first, 0));
    const original = broker.prompt(0).?.ticket;
    try std.testing.expect(!broker.decide(.{ .owner = b, .epoch = original.epoch, .start = original.start }, true, 0));
    try std.testing.expect(broker.decide(original, true, 0));
    try std.testing.expectEqual(Service.progressed, try broker.service(&first, 0));
    try feed(&first, data_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(&first, 0));
    // The process-wide budget cannot be reused before the old staging retires.
    broker.setFocus(b, 1);
    try feed(&second, start_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(&second, 1));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EBUSY:id=route\x1b\\", second.replyBytes());
    broker.setFocus(a, 2);
    try std.testing.expect(!broker.decide(original, true, 2));
    try std.testing.expectEqual(Service.progressed, try broker.service(&first, 2));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=route\x1b\\", first.replyBytes());
    try first.consumeReplyBytes(first.replyBytes().len);
    try feed(&first, end_packet);
    // The default unassociated-continuation lane may retire this stale end.
    try std.testing.expectEqual(Service.unhandled, try broker.service(&first, 2));
    try first.declineKittyClipboard(first.consequenceHead().?.id());
    try std.testing.expectEqualStrings("", first.replyBytes());
    try feed(&first, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(&first, 3));
    const fresh = broker.prompt(3).?.ticket;
    try std.testing.expect(fresh.start != original.start);
    try std.testing.expect(!broker.decide(original, true, 3));
    try std.testing.expect(broker.decide(fresh, false, 3));
    try std.testing.expectEqual(Service.progressed, try broker.service(&first, 3));
}

test "clipboard broker expires pending and prepared writes before provider admission" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    broker.setFocus(terminal.observation().occurrenceIdentity(), 0);
    try feed(&terminal, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(&terminal, 10));
    const prompt_value = broker.prompt(10).?;
    try std.testing.expectEqual(@as(?u64, 10 + deadline_ns), broker.deadline());
    try std.testing.expect(!broker.decide(prompt_value.ticket, true, prompt_value.expires_ns));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, prompt_value.expires_ns));
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const now = 2 * deadline_ns;
    const ticket = try prepare(&broker, &terminal, now);
    try std.testing.expect(broker.takePublication(ticket, now + deadline_ns) == null);
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, now + deadline_ns));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=route\x1b\\", terminal.replyBytes());
    try std.testing.expect(broker.deadline() == null);
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.takeKittyClipboardWrite(terminal.consequenceHead().?.id()));
    try terminal.declineKittyClipboard(terminal.consequenceHead().?.id());
}

test "clipboard broker reset and retired provider outcomes cannot authorize a successor" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const ticket = try prepare(&broker, &terminal, 1);
    terminal.hardReset();
    try std.testing.expectEqual(Service.unhandled, try broker.service(&terminal, 2));
    try std.testing.expect(broker.takePublication(ticket, 2) == null);
    try terminal.declineKittyClipboard(terminal.consequenceHead().?.id());
    const fresh = try prepare(&broker, &terminal, 3);
    try std.testing.expect(fresh.epoch != ticket.epoch);
    var publication = broker.takePublication(fresh, 4).?;
    defer publication.data.deinit();
    broker.retireOwner(fresh.owner);
    try std.testing.expect(broker.recordOutcome(publication.completion, .EIO));
    try std.testing.expect(!broker.recordOutcome(publication.completion, .DONE));
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    // Simulate the already stopped worker's actual VT retirement.
    terminal.hardReset();
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.acknowledgeKittyClipboardWrite(publication.completion.end, .DONE));
    try terminal.declineKittyClipboard(terminal.consequenceHead().?.id());
    const successor = try prepare(&broker, &terminal, 5);
    try std.testing.expect(!broker.decide(fresh, true, 5));
    try std.testing.expect(broker.takePublication(fresh, 5) == null);
    var next = broker.takePublication(successor, 5).?;
    defer next.data.deinit();
    try std.testing.expect(broker.recordOutcome(next.completion, .EIO));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 5));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EIO:id=route\x1b\\", terminal.replyBytes());
}

test "clipboard owner deadline survives expired main queries and unrelated worker turns" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var owner = try Terminal.init(std.testing.allocator, 3, 8);
    defer owner.deinit();
    var sibling = try Terminal.init(std.testing.allocator, 3, 8);
    defer sibling.deinit();
    const identity = owner.observation().occurrenceIdentity();
    broker.setFocus(identity, 1);
    try feed(&owner, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(&owner, 1));
    const prompt_value = broker.prompt(1).?;
    const deadline = prompt_value.expires_ns;
    try std.testing.expectEqual(@as(?u64, deadline), broker.deadlineFor(identity));
    try std.testing.expect(broker.deadlineFor(sibling.observation().occurrenceIdentity()) == null);
    try std.testing.expect(broker.prompt(deadline) == null);
    try std.testing.expect(!broker.decide(prompt_value.ticket, true, deadline));
    try std.testing.expectEqual(Service.unhandled, try broker.service(&sibling, deadline));
    try std.testing.expectEqual(@as(?u64, deadline), broker.deadlineFor(identity));
    try std.testing.expectEqual(Service.progressed, try broker.service(&owner, deadline));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=route\x1b\\", owner.replyBytes());
    try std.testing.expect(broker.deadlineFor(identity) == null);
}

test "clipboard supersession revokes prepared data without changing focus or replaying a provider" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(a, 3, 8);
    defer terminal.deinit();
    const ticket = try prepare(&broker, &terminal, 1);
    broker.supersede();
    try std.testing.expectEqual(@as(?u64, ticket.owner), broker.focusedOwner());
    try std.testing.expect(broker.takePublication(ticket, 2) == null);
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 2));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=route\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try terminal.declineKittyClipboard(terminal.consequenceHead().?.id());
    try std.testing.expect(broker.noticeFor(ticket.owner) == null);
    const fresh = try prepare(&broker, &terminal, 3);
    var publication = broker.takePublication(fresh, 3).?;
    defer publication.data.deinit();
    broker.supersede();
    try std.testing.expect(broker.recordOutcome(publication.completion, .DONE));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=DONE:id=route\x1b\\", terminal.replyBytes());
    try std.testing.expect(broker.takePublication(fresh, 4) == null);
}

const inventory_packet = "\x1b]5522;type=read:id=list;Lg==\x07";
const inventory_reply = "\x1b]5522;type=read:status=OK:id=list\x1b\\\x1b]5522;type=read:status=DATA:id=list:mime=Lg==;dGV4dC9wbGFpbgo=\x1b\\\x1b]5522;type=read:status=DONE:id=list\x1b\\";

fn requestInventory(broker: *Broker, terminal: *Terminal, now: u64) !Ticket {
    try feed(terminal, inventory_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(terminal, now));
    try std.testing.expect(broker.prompt(now) == null);
    const notice = broker.noticeFor(terminal.observation().occurrenceIdentity()) orelse return error.TestUnexpectedResult;
    try std.testing.expect(notice == .inventory);
    return notice.inventory;
}

test "clipboard inventory is focused exact period only and shares the one admission slot" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(a, 3, 8);
    defer terminal.deinit();
    var sibling = try Terminal.init(a, 3, 8);
    defer sibling.deinit();
    const owner = terminal.observation().occurrenceIdentity();
    broker.setFocus(owner, 0);
    try feed(&sibling, inventory_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(&sibling, 0));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=list\x1b\\", sibling.replyBytes());
    try std.testing.expect(broker.noticeFor(sibling.observation().occurrenceIdentity()) == null);
    try feed(&terminal, "\x1b]5522;type=read:loc=primary:id=p;Lg==\x07");
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 0));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=ENOSYS:id=p\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    for ([_][]const u8{ "dGV4dC9wbGFpbg==", "LiB0ZXh0L3BsYWlu", "IC4g" }) |payload| {
        var bytes: [96]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&bytes, "\x1b]5522;type=read;{s}\x07", .{payload}));
        try std.testing.expectEqual(Service.unhandled, try broker.service(&terminal, 0));
        try terminal.declineKittyClipboard(terminal.consequenceHead().?.id());
    }
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, start_packet);
    try std.testing.expectEqual(Service.waiting, try broker.service(&terminal, 1));
    const writer = broker.prompt(1).?.ticket;
    try std.testing.expect(broker.decide(writer, true, 1));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 1));
    try feed(&terminal, inventory_packet);
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 1));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EBUSY:id=list\x1b\\", terminal.replyBytes());
    try std.testing.expect(broker.noticeFor(owner) == null);
    broker.supersede();
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 2));
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const ticket = try requestInventory(&broker, &terminal, 3);
    try std.testing.expect(!broker.takeInventory(.{ .owner = owner, .epoch = ticket.epoch, .start = ticket.start + 1 }, 3));
    try std.testing.expect(broker.takeInventory(ticket, 3));
    try std.testing.expect(!broker.takeInventory(ticket, 3));
    var inventory: Inventory = .{};
    try inventory.append("text/plain");
    try std.testing.expect(broker.recordInventory(ticket, .{ .available = inventory }, 3));
    try std.testing.expect(!broker.recordInventory(ticket, .busy, 3));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 3));
    try std.testing.expectEqualStrings(inventory_reply, terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "clipboard inventory pressure retries the snapshot without another provider call and revokes before admission" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(a, 3, 8);
    defer terminal.deinit();
    broker.setFocus(terminal.observation().occurrenceIdentity(), 0);
    const ticket = try requestInventory(&broker, &terminal, 1);
    try std.testing.expect(broker.takeInventory(ticket, 1));
    var inventory: Inventory = .{};
    try inventory.append("text/plain");
    try std.testing.expect(broker.recordInventory(ticket, .{ .available = inventory }, 1));
    while (terminal.replyBytes().len < 65532) {
        const before = terminal.replyBytes().len;
        const summary = try terminal.feed("\x1b[5n");
        try std.testing.expect(!summary.titleChanged());
        try std.testing.expectEqual(before + 4, terminal.replyBytes().len);
    }
    const prefix = try a.dupe(u8, terminal.replyBytes());
    defer a.free(prefix);
    try std.testing.expectError(error.ReplyLimit, broker.service(&terminal, 2));
    try std.testing.expectEqualStrings(prefix, terminal.replyBytes());
    try std.testing.expectEqual(ticket.start, terminal.consequenceHead().?.id());
    try std.testing.expect(!broker.takeInventory(ticket, 2));
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    broker.supersede();
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 2));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=list\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const fresh = try requestInventory(&broker, &terminal, 3);
    try std.testing.expect(broker.takeInventory(fresh, 3));
    broker.setFocus(null, 4);
    try std.testing.expect(broker.recordInventory(fresh, .{ .available = inventory }, 4));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=list\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    broker.setFocus(fresh.owner, 5);
    const expired = try requestInventory(&broker, &terminal, 5);
    try std.testing.expect(!broker.takeInventory(expired, 5 + deadline_ns));
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 5 + deadline_ns));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=list\x1b\\", terminal.replyBytes());
}

test "clipboard inventory reset and dead owner retire outstanding provider results" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var broker = Broker.init(threaded.io());
    defer broker.deinit();
    var terminal = try Terminal.init(a, 3, 8);
    defer terminal.deinit();
    const owner = terminal.observation().occurrenceIdentity();
    broker.setFocus(owner, 0);
    const ticket = try requestInventory(&broker, &terminal, 1);
    try std.testing.expect(broker.takeInventory(ticket, 1));
    broker.retireOwner(owner);
    try std.testing.expect(broker.recordInventory(ticket, .{ .available = .{} }, 2));
    try std.testing.expect(broker.noticeFor(owner) == null);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try terminal.declineKittyClipboard(ticket.start);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    broker.setFocus(owner, 3);
    const fresh = try requestInventory(&broker, &terminal, 3);
    try std.testing.expect(broker.takeInventory(fresh, 3));
    terminal.hardReset();
    // Reset leaves unstarted raw consequences retained, but no prior grant.
    try std.testing.expectEqual(Service.progressed, try broker.service(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=list\x1b\\", terminal.replyBytes());
    try std.testing.expect(broker.recordInventory(fresh, .{ .available = .{} }, 4));
    try std.testing.expect(broker.noticeFor(owner) == null);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}
