//! SDL main-thread clipboard offer ownership. Protocol acknowledgement
//! means local provider acceptance, not compositor or receiving-client receipt.
const std = @import("std");
const c = @import("desktop");
const Terminal = @import("howl_vt").Terminal;
const clipboard = @import("clipboard_broker.zig");

const max_names = 256;
const max_name_bytes = 4096;

const Backend = struct {
    // zig-audit: acknowledge anyopaque
    // reason: Exact SDL C callback ABI, with userdata owned by the registered Offer.
    set: *const fn (c.SDL_ClipboardDataCallback, c.SDL_ClipboardCleanupCallback, ?*anyopaque, [*c]const [*c]const u8, usize) callconv(.c) bool,
    clear: *const fn () callconv(.c) bool,
};

const Offer = struct {
    owner: *Provider,
    data: ?Terminal.KittyWriteData,
    registering: bool = true,
    retired: bool = false,
    revoked: bool = false,

    fn release(self: *Offer) void {
        if (self.data) |*data| data.deinit();
        self.data = null;
    }
};

// zig-audit: acknowledge anyopaque
// reason: SDL's C ABI returns the exact registered Offer pointer.
fn offerFrom(userdata: ?*anyopaque) *Offer {
    // zig-audit: acknowledge ptr_cast
    // reason: Only Provider passes its live Offer allocation as SDL userdata.
    // zig-audit: acknowledge align_cast
    // reason: The original allocation supplies Offer alignment.
    return @ptrCast(@alignCast(userdata.?));
}

// zig-audit: acknowledge anyopaque
// reason: Exact SDL C callback ABI, with userdata owned by the registered Offer.
// zig-audit: acknowledge anyopaque
// reason: SDL borrows immutable bytes from the live Offer; it does not free the returned pointer.
fn provide(userdata: ?*anyopaque, mime: [*c]const u8, size: [*c]usize) callconv(.c) ?*const anyopaque {
    if (size == null) return null;
    size[0] = 0;
    if (userdata == null or mime == null) return null;
    const offer = offerFrom(userdata);
    if (offer.revoked) return null;
    const data = if (offer.data) |*value| value else return null;
    const bytes = data.view().get(std.mem.span(mime)) orelse return null;
    if (bytes.len == 0) return null;
    size[0] = bytes.len;
    return &bytes[0];
}

// zig-audit: acknowledge anyopaque
// reason: Exact SDL C callback ABI, with userdata owned by the registered Offer.
fn cleanup(userdata: ?*anyopaque) callconv(.c) void {
    const offer = offerFrom(userdata);
    const owner = offer.owner;
    std.debug.assert(!offer.retired);
    offer.release();
    offer.retired = true;
    // SDL can clean the candidate synchronously inside set/clear. Keep the
    // registration guard live until the caller has inspected that outcome.
    if (offer.registering) return;
    if (owner.current == offer) owner.current = null;
    if (owner.candidate == offer) owner.candidate = null;
    owner.allocator.destroy(offer);
}

/// Main-thread-only owner, at a stable address until SDL video has quit.
/// Callback cleanup determines allocation retirement, not SDL's bool result.
pub const Provider = struct {
    allocator: std.mem.Allocator,
    current: ?*Offer = null,
    candidate: ?*Offer = null,

    /// Create a lazy owner with no allocated payload or SDL operations.
    pub fn init(allocator: std.mem.Allocator) Provider {
        return .{ .allocator = allocator };
    }

    /// Call only after SDL has shut down its callback authority. An
    /// ambiguous failed registration may have retained a revoked shell.
    pub fn deinitAfterQuit(self: *Provider) void {
        if (self.current) |offer| {
            offer.release();
            self.allocator.destroy(offer);
        }
        if (self.candidate) |offer| {
            offer.release();
            self.allocator.destroy(offer);
        }
        self.current = null;
        self.candidate = null;
    }

    /// Read only the provider's cached MIME-name inventory on the main
    /// thread. Never request clipboard payload bytes or expose a partial list.
    pub fn inventory(_: *Provider) clipboard.InventoryResult {
        if (c.SDL_WasInit(c.SDL_INIT_VIDEO) & c.SDL_INIT_VIDEO == 0) return .unavailable;
        var count: usize = 0;
        const names = c.SDL_GetClipboardMimeTypes(&count) orelse return .busy;
        // zig-audit: acknowledge ptr_cast
        // reason: SDL returns one owned MIME vector and requires its base address in SDL_free.
        defer c.SDL_free(@ptrCast(names));
        return collectInventory(names, count);
    }

    /// Submit a prepared ordinary clipboard offer. On local acceptance
    /// SDL owns callback access until cleanup; no external receipt is claimed.
    pub fn publish(self: *Provider, data: *Terminal.KittyWriteData) Terminal.KittyWriteStatus {
        if (c.SDL_WasInit(c.SDL_INIT_VIDEO) & c.SDL_INIT_VIDEO == 0) return .ENOSYS;
        return self.submit(data, .{ .set = c.SDL_SetClipboardData, .clear = c.SDL_ClearClipboardData });
    }

    fn submit(self: *Provider, data: *Terminal.KittyWriteData, backend: Backend) Terminal.KittyWriteStatus {
        if (data.location != .clipboard) return .ENOSYS;
        // Do not accumulate possibly retained registrations after a
        // provider contract failure. Only cleanup or shutdown retires it.
        if (self.candidate != null) return .EBUSY;
        const view = data.view();
        if (view.count() == 0) return if (backend.clear()) .DONE else .EIO;
        if (view.count() > max_names) return .EINVAL;

        var name_bytes: usize = 0;
        for (0..view.count()) |index| {
            const entry = view.entry(index) orelse return .EINVAL;
            if (entry.mime.len == 0 or entry.mime.len > max_name_bytes or std.mem.indexOfScalar(u8, entry.mime, 0) != null) return .EINVAL;
            name_bytes += entry.mime.len + 1;
        }
        // SDL copies the MIME vector. Complete every own allocation before
        // calling it, so our own OOM cannot retire the preceding offer.
        const names = self.allocator.alloc(u8, name_bytes) catch return .EIO;
        defer self.allocator.free(names);
        var pointers: [max_names][*c]const u8 = undefined;
        var offset: usize = 0;
        for (pointers[0..view.count()], 0..) |*pointer, index| {
            const mime = view.entry(index).?.mime;
            @memcpy(names[offset..][0..mime.len], mime);
            names[offset + mime.len] = 0;
            pointer.* = names[offset..].ptr;
            offset += mime.len + 1;
        }
        const offer = self.allocator.create(Offer) catch return .EIO;
        offer.* = .{ .owner = self, .data = data.* };
        data.* = .{ .allocator = data.allocator, .location = data.location };
        self.candidate = offer;
        const accepted = backend.set(provide, cleanup, offer, &pointers, view.count());
        if (accepted and !offer.retired and self.current == null) {
            offer.registering = false;
            self.current = offer;
            self.candidate = null;
            return .DONE;
        }

        // A false result may still have installed the callback. Stop
        // exposing its bytes before clear, irrespective of clear's result.
        // Keep the guard across synchronous cleanup in both calls. Even
        // revoked bytes stay allocated until callback retirement: a pointer
        // already borrowed by the provider must not become dangling.
        offer.revoked = true;
        if (!offer.retired) {
            // zig-audit: acknowledge discard
            // reason: Clear success is not a cleanup oracle; callback retirement below is authoritative.
            _ = backend.clear();
        }
        offer.registering = false;
        if (offer.retired) {
            self.candidate = null;
            self.allocator.destroy(offer);
        }
        return .EIO;
    }
};

// SDL owns the valid NUL-terminated vector until SDL_free. Cap the
// application's copied snapshot before retaining or returning any names.
fn collectInventory(names: [*c]const [*c]const u8, count: usize) clipboard.InventoryResult {
    if (count > clipboard.Inventory.max_names) return .busy;
    var result: clipboard.Inventory = .{};
    for (0..count) |index| {
        const pointer = names[index];
        if (pointer == null) return .busy;
        var len: usize = 0;
        while (len < clipboard.Inventory.max_bytes and pointer[len] != 0) : (len += 1) {}
        if (len == clipboard.Inventory.max_bytes) return .busy;
        const name = pointer[0..len];
        // SDL's Wayland transport identity is not user clipboard data.
        if (std.mem.eql(u8, name, "application/x-sdl3-source-id")) continue;
        result.append(name) catch return .busy;
    }
    return .{ .available = result };
}

// All test data travels through the actual VT write decoder and ownership move.
fn prepared(allocator: std.mem.Allocator, location: Terminal.KittyLocation) !Terminal.KittyWriteData {
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const start = if (location == .primary) "\x1b]5522;type=write:loc=primary\x07" else "\x1b]5522;type=write\x07";
    try std.testing.expect((try terminal.feed(start)).stateChanged());
    try terminal.beginKittyClipboardWrite(terminal.consequenceHead().?.id(), location);
    try std.testing.expect((try terminal.feed("\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;AAEC/w==\x07\x1b]5522;type=walias:mime=dGV4dC9wbGFpbg==;dGV4dC9odG1s\x07\x1b]5522;type=wdata:mime=ZW1wdHk=;\x07\x1b]5522;type=wdata\x07")).stateChanged());
    for (0..3) |_| try std.testing.expectEqual(Terminal.KittyWriteProgress.staged, try terminal.stageKittyClipboardWrite(terminal.consequenceHead().?.id()));
    const end = terminal.consequenceHead().?.id();
    try std.testing.expectEqual(Terminal.KittyWriteProgress.ready, try terminal.stageKittyClipboardWrite(end));
    return terminal.takeKittyClipboardWrite(end);
}

const Fake = struct {
    const Mode = enum { success, early_failure, late_failure, no_cleanup, rejected_before_adoption };
    var mode: Mode = .success;
    // zig-audit: acknowledge anyopaque
    // reason: Exact SDL C callback ABI, with userdata owned by the registered Offer.
    var user: ?*anyopaque = null;
    var data_cb: c.SDL_ClipboardDataCallback = null;
    var cleanup_cb: c.SDL_ClipboardCleanupCallback = null;
    var clear_calls: usize = 0;
    var set_calls: usize = 0;
    var retire_calls: usize = 0;
    var valid_names: bool = false;
    var revoked_on_clear: bool = false;

    fn reset() void {
        std.debug.assert(user == null);
        mode = .success;
        clear_calls = 0;
        set_calls = 0;
        retire_calls = 0;
        valid_names = false;
        revoked_on_clear = false;
    }
    fn retire() void {
        if (user) |value| {
            cleanup_cb.?(value);
            retire_calls += 1;
        }
        user = null;
        cleanup_cb = null;
        data_cb = null;
    }
    // zig-audit: acknowledge anyopaque
    // reason: Exact SDL C callback ABI, with userdata owned by the registered Offer.
    fn set(callback: c.SDL_ClipboardDataCallback, clean: c.SDL_ClipboardCleanupCallback, userdata: ?*anyopaque, names: [*c]const [*c]const u8, count: usize) callconv(.c) bool {
        set_calls += 1;
        valid_names = count == 3 and std.mem.eql(u8, std.mem.span(names[0]), "text/plain") and
            std.mem.eql(u8, std.mem.span(names[1]), "text/html") and std.mem.eql(u8, std.mem.span(names[2]), "empty");
        if (mode == .rejected_before_adoption) return false;
        retire();
        user = userdata;
        cleanup_cb = clean;
        data_cb = callback;
        if (mode == .early_failure) retire();
        return mode == .success;
    }
    fn clear() callconv(.c) bool {
        clear_calls += 1;
        if (user != null) {
            var size: usize = 99;
            revoked_on_clear = data_cb.?(user, "text/plain", &size) == null and size == 0;
        }
        if (mode != .no_cleanup) retire();
        return false;
    }
    const backend: Backend = .{ .set = set, .clear = clear };
};

test "native clipboard callback retains moved binary aliases through replacement and cleanup" {
    Fake.reset();
    const a = std.testing.allocator;
    var provider = Provider.init(a);
    defer provider.deinitAfterQuit();
    defer Fake.retire();
    var data = try prepared(a, .clipboard);
    defer data.deinit();
    const address = data.view().get("text/plain").?.ptr;
    try std.testing.expectEqual(Terminal.KittyWriteStatus.DONE, provider.submit(&data, Fake.backend));
    try std.testing.expect(Fake.valid_names);
    try std.testing.expectEqual(@as(usize, 0), data.view().count());
    var size: usize = 0;
    const plain = Fake.data_cb.?(Fake.user, "text/plain", &size).?;
    try std.testing.expectEqual(@as(usize, 4), size);
    try std.testing.expectEqual(@intFromPtr(address), @intFromPtr(plain));
    try std.testing.expectEqual(plain, Fake.data_cb.?(Fake.user, "text/html", &size).?);
    try std.testing.expect(Fake.data_cb.?(Fake.user, "empty", &size) == null and size == 0);
    try std.testing.expect(Fake.data_cb.?(Fake.user, null, &size) == null and size == 0);
    try std.testing.expect(Fake.data_cb.?(Fake.user, "unknown", &size) == null and size == 0);
    var next = try prepared(a, .clipboard);
    defer next.deinit();
    try std.testing.expectEqual(Terminal.KittyWriteStatus.DONE, provider.submit(&next, Fake.backend));
    try std.testing.expectEqual(@as(usize, 1), Fake.retire_calls);
    Fake.retire();
    try std.testing.expect(provider.current == null and provider.candidate == null);
    try std.testing.expectEqual(@as(usize, 2), Fake.retire_calls);
}

test "native clipboard failed registrations separate retirement from return value" {
    const a = std.testing.allocator;
    for ([_]Fake.Mode{ .early_failure, .late_failure, .no_cleanup, .rejected_before_adoption }) |mode| {
        Fake.reset();
        var provider = Provider.init(a);
        defer provider.deinitAfterQuit();
        defer Fake.retire();
        var data = try prepared(a, .clipboard);
        defer data.deinit();
        Fake.mode = mode;
        try std.testing.expectEqual(Terminal.KittyWriteStatus.EIO, provider.submit(&data, Fake.backend));
        try std.testing.expectEqual(@as(usize, 0), data.view().count());
        try std.testing.expect(provider.current == null);
        if (mode == .early_failure) {
            try std.testing.expectEqual(@as(usize, 0), Fake.clear_calls);
            try std.testing.expectEqual(@as(usize, 1), Fake.retire_calls);
        } else {
            try std.testing.expectEqual(@as(usize, 1), Fake.clear_calls);
            if (mode != .rejected_before_adoption) try std.testing.expect(Fake.revoked_on_clear);
        }
        if (mode == .no_cleanup or mode == .rejected_before_adoption) {
            try std.testing.expect(provider.candidate != null);
            try std.testing.expect(provider.candidate.?.revoked);
            try std.testing.expect(provider.candidate.?.data != null);
            if (Fake.user != null) {
                var size: usize = 99;
                try std.testing.expect(Fake.data_cb.?(Fake.user, "text/plain", &size) == null and size == 0);
            }
            var next = try prepared(a, .clipboard);
            defer next.deinit();
            try std.testing.expectEqual(Terminal.KittyWriteStatus.EBUSY, provider.submit(&next, Fake.backend));
            try std.testing.expectEqual(@as(usize, 1), Fake.set_calls);
        } else {
            try std.testing.expect(provider.candidate == null);
        }
    }
}

test "native clipboard preflight failure leaves old offer and new caller data intact" {
    Fake.reset();
    const a = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(a, .{});
    var provider = Provider.init(failing.allocator());
    defer provider.deinitAfterQuit();
    defer Fake.retire();
    var original = try prepared(a, .clipboard);
    defer original.deinit();
    try std.testing.expectEqual(Terminal.KittyWriteStatus.DONE, provider.submit(&original, Fake.backend));
    const old = provider.current;
    var data = try prepared(a, .clipboard);
    defer data.deinit();
    const address = data.view().get("text/plain").?.ptr;
    for (0..2) |offset| {
        failing.fail_index = failing.alloc_index + offset;
        try std.testing.expectEqual(Terminal.KittyWriteStatus.EIO, provider.submit(&data, Fake.backend));
        try std.testing.expectEqual(old, provider.current);
        try std.testing.expectEqual(address, data.view().get("text/plain").?.ptr);
        try std.testing.expectEqual(@as(usize, 1), Fake.set_calls);
        try std.testing.expectEqual(@as(usize, 0), Fake.retire_calls);
    }
    failing.fail_index = std.math.maxInt(usize);
    var primary = try prepared(a, .primary);
    defer primary.deinit();
    try std.testing.expectEqual(Terminal.KittyWriteStatus.ENOSYS, provider.submit(&primary, Fake.backend));
    try std.testing.expectEqual(@as(usize, 1), Fake.set_calls);
}

test "native clipboard inventory copies only complete bounded metadata and filters provider identity" {
    const names = [_][*c]const u8{ "text/plain", "application/x-sdl3-source-id", "image/png" };
    const result = collectInventory(&names, names.len);
    try std.testing.expect(result == .available);
    try std.testing.expectEqual(@as(u16, 2), result.available.count);
    try std.testing.expectEqualStrings("text/plain\nimage/png\n", result.available.bytes[0..result.available.len]);
    try std.testing.expect(collectInventory(&names, 0) == .available);
    try std.testing.expectEqual(@as(u16, 0), collectInventory(&names, 0).available.count);
    try std.testing.expect(collectInventory(&names, clipboard.Inventory.max_names + 1) == .busy);
    const invalid = [_][*c]const u8{ "text/plain", "bad name" };
    try std.testing.expect(collectInventory(&invalid, invalid.len) == .busy);
    const null_name = [_][*c]const u8{null};
    try std.testing.expect(collectInventory(&null_name, 1) == .busy);
    const invalid_utf8 = [_][*c]const u8{"\xff"};
    try std.testing.expect(collectInventory(&invalid_utf8, 1) == .busy);
    const maximum: [4095:0]u8 = @splat('x');
    const excess: [4096:0]u8 = @splat('x');
    const exact = [_][*c]const u8{&maximum};
    try std.testing.expectEqual(@as(u16, 4096), collectInventory(&exact, 1).available.len);
    const over = [_][*c]const u8{&excess};
    try std.testing.expect(collectInventory(&over, 1) == .busy);
    const aggregate = [_][*c]const u8{ &maximum, "x" };
    try std.testing.expect(collectInventory(&aggregate, 2) == .busy);
    const many: [clipboard.Inventory.max_names][*c]const u8 = @splat("x");
    try std.testing.expectEqual(@as(u16, clipboard.Inventory.max_names), collectInventory(&many, many.len).available.count);
}
