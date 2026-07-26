const std = @import("std");
const c = @import("host_c");
const shared = @import("shared");

fn boundary() !shared.Boundary {
    return shared.Boundary.init(std.testing.io);
}

test "feedback and ring offers transfer complete copied ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 0x1234, .fourcc = 0x34324241, .modifier = 7 });
    try std.testing.expectEqual(@as(u64, 0x1234), value.readFeedback().?.device);
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
}

test "pending offers remain exact and reject a second ownership transfer" {
    var value = try boundary();
    defer value.deinit();
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
    try value.publishCompletion(.{ .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try value.publishCompletion(.{ .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try value.publishCompletion(.{ .revision = 3, .slot = 2, .acquire_point = 3, .release_point = 1 });
    try std.testing.expectError(error.CompletionLimit, value.publishCompletion(.{ .revision = 4, .slot = 0, .acquire_point = 4, .release_point = 2 }));
    try std.testing.expectEqual(@as(u64, 1), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 3), value.takeCompletion().?.revision);
    try std.testing.expect(value.takeCompletion() == null);
}

test "invalid and stale revisions preserve queued completion" {
    var value = try boundary();
    defer value.deinit();
    try value.publishCompletion(.{ .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .revision = 2, .slot = 2, .acquire_point = 3, .release_point = 1 }));
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .revision = 3, .slot = 3, .acquire_point = 4, .release_point = 1 }));
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
    try value.publishCompletion(.{ .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try expectReadable(value.windowFd());
    try value.drainWindowWake();
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
