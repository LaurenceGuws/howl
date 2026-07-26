const std = @import("std");
const c = @import("host_c");
const shared = @import("shared");
const chrome_state = @import("chrome_state");
const render = @import("howl_render");
const wayland = @import("howl_wayland");

fn boundary() !shared.Boundary {
    return shared.Boundary.init(std.testing.io);
}

test "feedback and ring offers transfer complete copied ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 0x1234, .fourcc = 0x34324241, .modifier = 7 });
    try std.testing.expectEqual(@as(u64, 0x1234), value.readFeedback().?.device);
    try value.publishConfigure(64, 64);
    const offers = try realOffers();
    try value.publishOffers(offers);
    const taken = value.takeOffers().?;
    for (taken) |offer| {
        try std.testing.expect(offer.dma_fd >= 0);
        try std.testing.expectEqual(@as(c_int, 0), c.close(offer.dma_fd));
        try std.testing.expectEqual(@as(c_int, 0), c.close(offer.acquire_timeline_fd));
        try std.testing.expectEqual(@as(c_int, 0), c.close(offer.release_timeline_fd));
    }
    try std.testing.expect(value.takeOffers() == null);
}

test "malformed offers preserve Boundary and caller descriptor ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64);
    var offers = try realOffers();
    offers[1].plane_count = shared.plane_limit + 1;
    try std.testing.expectError(error.InvalidOffer, value.publishOffers(offers));
    try std.testing.expectEqual(@as(u8, 0), value.offer_count);
    try std.testing.expect(value.takeOffers() == null);
    closeOffers(offers);

    offers = try realOffers();
    const displaced = offers[2].dma_fd;
    offers[2].dma_fd = -1;
    try std.testing.expectError(error.InvalidOffer, value.publishOffers(offers));
    try std.testing.expectEqual(@as(u8, 0), value.offer_count);
    try std.testing.expect(value.takeOffers() == null);
    try std.testing.expectEqual(@as(c_int, 0), c.close(displaced));
    offers[2].dma_fd = -1;
    closeOffers(offers);

    offers = try realOffers();
    offers[1].width = 65;
    try std.testing.expectError(error.InvalidOffer, value.publishOffers(offers));
    try std.testing.expectEqual(@as(u8, 0), value.offer_count);
    closeOffers(offers);
}

test "pending offers remain exact and reject a second ownership transfer" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64);
    const first = try realOffers();
    const second = try realOffers();
    try value.publishOffers(first);
    const retained_count = value.offer_count;
    const retained_first_fd = value.offers[0].?.dma_fd;
    try std.testing.expectError(error.OffersPending, value.publishOffers(second));
    try std.testing.expectEqual(retained_count, value.offer_count);
    try std.testing.expectEqual(retained_first_fd, value.offers[0].?.dma_fd);
    const taken = value.takeOffers().?;
    try std.testing.expectEqual(retained_first_fd, taken[0].dma_fd);
    closeOffers(taken);
    closeOffers(second);
}

test "Boundary cleanup closes every retained offered descriptor" {
    var value = try boundary();
    const planes = [shared.plane_limit]shared.Plane{
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
    };
    var offers: [shared.slot_count]shared.SlotOffer = @splat(.{
        .generation = 1,
        .width = 64,
        .height = 64,
        .dma_fd = -1,
        .acquire_timeline_fd = -1,
        .release_timeline_fd = -1,
        .plane_count = 1,
        .planes = planes,
    });
    errdefer closeOffers(offers);
    for (&offers) |*offer| {
        offer.dma_fd = try eventDescriptor();
        offer.acquire_timeline_fd = try eventDescriptor();
        offer.release_timeline_fd = try eventDescriptor();
    }
    try value.publishConfigure(64, 64);
    try value.publishOffers(offers);
    value.deinit();
    for (offers) |offer| {
        try std.testing.expectEqual(@as(c_int, -1), c.close(offer.dma_fd));
        try std.testing.expectEqual(@as(c_int, -1), c.close(offer.acquire_timeline_fd));
        try std.testing.expectEqual(@as(c_int, -1), c.close(offer.release_timeline_fd));
    }
}

test "completion queue is bounded ordered and never acknowledges Render" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try value.publishCompletion(.{ .generation = 1, .revision = 3, .slot = 2, .acquire_point = 3, .release_point = 1 });
    try std.testing.expectError(error.CompletionLimit, value.publishCompletion(.{ .generation = 1, .revision = 4, .slot = 0, .acquire_point = 4, .release_point = 2 }));
    try std.testing.expectEqual(@as(u64, 1), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 3), value.takeCompletion().?.revision);
    try std.testing.expect(value.takeCompletion() == null);
}

test "invalid and stale revisions preserve queued completion" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 2, .acquire_point = 3, .release_point = 1 }));
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .generation = 1, .revision = 3, .slot = 3, .acquire_point = 4, .release_point = 1 }));
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
}

test "stop is monotonic and preserves the first runtime failure" {
    var value = try boundary();
    defer value.deinit();
    value.requestStop(.window);
    value.requestStop(.render);
    try std.testing.expect(value.shouldStop());
    try std.testing.expectEqual(shared.Failure.window, value.failure.?);
    try std.testing.expectError(error.Stopping, value.publishFeedback(.{ .device = 1, .fourcc = 1, .modifier = 1 }));
    value.markStopped(.window);
    value.markStopped(.render);
    const stopped = value.stopped();
    try std.testing.expect(stopped.window and stopped.render);
}

test "directional wakes follow fact ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 1, .fourcc = 2, .modifier = 3 });
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    try value.publishConfigure(64, 64);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try expectReadable(value.windowFd());
    try value.drainWindowWake();
}

test "Window input facts cross the shared boundary without policy" {
    var value = try boundary();
    defer value.deinit();
    try value.publishInput(.{ .key = .{ .keycode = 44, .time = 17, .state = .repeated, .serial = 9, .modifiers = .{ .serial = 8, .depressed = 1, .latched = 2, .locked = 4, .group = 3 }, .keysym = 0, .text_len = 0, .text = std.mem.zeroes([wayland.input.key_text_limit]u8) } });
    try value.publishMotion(.{ .time = 18, .point = .{ .x = 12.5, .y = 8.25 } });
    try value.publishModifiers(.{ .serial = 9, .depressed = 1, .latched = 2, .locked = 4, .group = 3 });
    try value.publishRepeat(.{ .rate = 25, .delay = 500 });
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    const event = value.takeInput().?.key;
    try std.testing.expectEqual(@as(u32, 44), event.keycode);
    try std.testing.expectEqual(@as(u32, 17), event.time);
    try std.testing.expectEqual(wayland.input.KeyState.repeated, event.state);
    const snapshot = value.takeInputSnapshots();
    try std.testing.expectEqual(@as(u32, 1), snapshot.modifiers.depressed);
    try std.testing.expectEqual(@as(u32, 25), snapshot.repeat.?.rate);
    try std.testing.expectEqual(@as(f64, 12.5), snapshot.motion.?.point.x);
}

test "configure facts coalesce and stale generations cannot cross the boundary" {
    var value = try boundary();
    defer value.deinit();
    try std.testing.expectError(error.InvalidConfigure, value.publishConfigure(0, 480));
    try value.publishConfigure(640, 480);
    const first = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u64, 1), first.generation);
    try value.publishConfigure(640, 480);
    try std.testing.expect(value.takeConfigure() == null);
    try value.publishConfigure(700, 500);
    try value.publishConfigure(800, 600);
    const second = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u64, 3), second.generation);
    var stale_offers = try realOffers();
    stale_offers[0].generation = first.generation;
    try std.testing.expectError(error.InvalidOffer, value.publishOffers(stale_offers));
    closeOffers(stale_offers);
    value.markWindowRingReady(second.generation);
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .generation = first.generation, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 }));
    try value.publishCompletion(.{ .generation = second.generation, .revision = 2, .slot = 0, .acquire_point = 2, .release_point = 1 });
}

test "replacement readiness cancels queued stale completions" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    value.markWindowRingReady(2);
    try std.testing.expect(value.takeCompletion() == null);
}

test "renderer chrome state retains stable identities through pane and tab changes" {
    var state = try chrome_state.Topology.init(.{ .width = 640, .height = 480 }, 24);
    const tab = state.tabId(0).?;
    const pane = state.paneId(0, 0).?;
    const split = try state.split(pane, .vertical);
    try state.renameTab(tab, "主");
    try std.testing.expectEqual(pane, state.paneId(0, 0).?);
    try std.testing.expectEqual(split, state.paneId(0, 1).?);
    var primitives: [128]render.chrome.Primitive = undefined;
    var text: [1024]u8 = undefined;
    const output = try state.project(.{
        .style = .{
            .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
            .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
            .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
        },
        .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
        .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
    }, &primitives, &text);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expectEqualStrings("主", output.text[0.."主".len]);
    try state.closePane(split);
    try std.testing.expectEqual(@as(usize, 1), state.paneCount(0));
}

fn expectReadable(descriptor: i32) !void {
    var poll_descriptor = c.pollfd{ .fd = descriptor, .events = c.POLLIN, .revents = 0 };
    try std.testing.expectEqual(@as(c_int, 1), c.poll(&poll_descriptor, 1, 0));
    try std.testing.expect((poll_descriptor.revents & c.POLLIN) != 0);
}

fn eventDescriptor() !i32 {
    const value = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (value < 0) return error.Descriptor;
    return value;
}

fn realOffers() ![shared.slot_count]shared.SlotOffer {
    const planes = [shared.plane_limit]shared.Plane{
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
    };
    var offers: [shared.slot_count]shared.SlotOffer = @splat(.{
        .generation = 1,
        .width = 64,
        .height = 64,
        .dma_fd = -1,
        .acquire_timeline_fd = -1,
        .release_timeline_fd = -1,
        .plane_count = 1,
        .planes = planes,
    });
    errdefer closeOffers(offers);
    for (&offers) |*offer| {
        offer.dma_fd = try eventDescriptor();
        offer.acquire_timeline_fd = try eventDescriptor();
        offer.release_timeline_fd = try eventDescriptor();
    }
    return offers;
}

fn closeOffers(offers: [shared.slot_count]shared.SlotOffer) void {
    for (offers) |offer| {
        if (offer.dma_fd >= 0) std.debug.assert(c.close(offer.dma_fd) == 0);
        if (offer.acquire_timeline_fd >= 0) std.debug.assert(c.close(offer.acquire_timeline_fd) == 0);
        if (offer.release_timeline_fd >= 0) std.debug.assert(c.close(offer.release_timeline_fd) == 0);
    }
}
