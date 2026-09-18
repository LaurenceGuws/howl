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
        .ring_revision = 1,
        .dma_fd = -1,
        .acquire_timeline_fd = -1,
        .release_timeline_fd = -1,
        .width = 64,
        .height = 64,
        .logical_width = 64,
        .logical_height = 64,
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

test "ring readiness and retirement preserve exact generation identity" {
    var value = try boundary();
    defer value.deinit();
    value.markWindowRingReady(7);
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    try std.testing.expect(value.isWindowRingReady(7));
    try std.testing.expect(!value.isWindowRingReady(6));

    try value.publishRingRetired(7);
    try expectReadable(value.windowFd());
    try value.drainWindowWake();
    try std.testing.expectEqual(@as(u64, 7), value.takeRingRetired().?);
    try std.testing.expect(value.takeRingRetired() == null);
    try std.testing.expectError(error.InvalidRevision, value.publishRingRetired(0));
}

test "control wake persists until size and scale facts are both consumed" {
    var value = try boundary();
    defer value.deinit();
    try value.publishWindowSize(.{ .width = 901, .height = 477 });
    try value.publishDisplayScale(.{ .scale_120 = 204 });
    try expectReadable(value.controlFd());
    try value.drainControlWake();
    try std.testing.expectEqual(shared.WindowSize{ .width = 901, .height = 477 }, value.takeWindowSize().?);
    try expectReadable(value.controlFd());
    try value.drainControlWake();
    try std.testing.expectEqual(@as(u32, 204), value.takeDisplayScale().?.scale_120);
}

test "display scale is latest-wins and rejects invalid protocol units" {
    var value = try boundary();
    defer value.deinit();
    try value.publishDisplayScale(.{ .scale_120 = 120 });
    try value.publishDisplayScale(.{ .scale_120 = 204 });
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    try std.testing.expectEqual(@as(u32, 204), value.takeDisplayScale().?.scale_120);
    try std.testing.expect(value.takeDisplayScale() == null);
    try std.testing.expectError(error.InvalidDisplayScale, value.publishDisplayScale(.{ .scale_120 = 0 }));
}

test "window size is latest-wins and wakes only Render control" {
    var value = try boundary();
    defer value.deinit();
    try value.publishWindowSize(.{ .width = 1001, .height = 501 });
    try value.publishWindowSize(.{ .width = 1203, .height = 607 });
    try expectReadable(value.controlFd());
    try value.drainControlWake();
    try std.testing.expectEqual(shared.WindowSize{ .width = 1203, .height = 607 }, value.takeWindowSize().?);
    try std.testing.expect(value.takeWindowSize() == null);
    try std.testing.expectError(error.InvalidWindowSize, value.publishWindowSize(.{ .width = 0, .height = 1 }));
}

test "completion queue is bounded ordered and never acknowledges Render" {
    var value = try boundary();
    defer value.deinit();
    try value.publishCompletion(.{ .ring_revision = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try value.publishCompletion(.{ .ring_revision = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try value.publishCompletion(.{ .ring_revision = 1, .revision = 3, .slot = 2, .acquire_point = 3, .release_point = 1 });
    try std.testing.expectError(error.CompletionLimit, value.publishCompletion(.{ .ring_revision = 1, .revision = 4, .slot = 0, .acquire_point = 4, .release_point = 2 }));
    try std.testing.expectEqual(@as(u64, 1), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 3), value.takeCompletion().?.revision);
    try std.testing.expect(value.takeCompletion() == null);
}

test "invalid and stale revisions preserve queued completion" {
    var value = try boundary();
    defer value.deinit();
    try value.publishCompletion(.{ .ring_revision = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .ring_revision = 1, .revision = 2, .slot = 2, .acquire_point = 3, .release_point = 1 }));
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .ring_revision = 1, .revision = 3, .slot = 3, .acquire_point = 4, .release_point = 1 }));
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
    value.markStopped(.input);
    const stopped = value.stopped();
    try std.testing.expect(stopped.window and stopped.render and stopped.input);
}

test "directional wakes follow fact ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 1, .fourcc = 2, .modifier = 3 });
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    try value.publishCompletion(.{ .ring_revision = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try expectReadable(value.windowFd());
    try value.drainWindowWake();
    try value.publishInput(.{ .focus = true });
    try expectReadable(value.inputFd());
    try value.drainInputWake();
    try std.testing.expect(value.takeInput().?.focus);
}

test "input queue is ordered bounded and stop rejects admission" {
    var value = try boundary();
    defer value.deinit();
    try value.publishInput(.{ .focus = true });
    try value.publishInput(.{ .focus = false });
    try std.testing.expect(value.takeInput().?.focus);
    try std.testing.expect(!value.takeInput().?.focus);
    try std.testing.expect(value.takeInput() == null);
    for (0..shared.input_capacity) |index| {
        try value.publishInput(.{ .focus = index % 2 == 0 });
    }
    try std.testing.expectError(error.InputLimit, value.publishInput(.{ .focus = true }));
    for (0..shared.input_capacity) |_| try std.testing.expect(value.takeInput() != null);
    value.requestStop(null);
    try std.testing.expectError(error.Stopping, value.publishInput(.{ .focus = true }));
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
        .ring_revision = 1,
        .dma_fd = -1,
        .acquire_timeline_fd = -1,
        .release_timeline_fd = -1,
        .width = 64,
        .height = 64,
        .logical_width = 64,
        .logical_height = 64,
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

test "pane focus is latest-wins and wakes Input" {
    var value = try boundary();
    defer value.deinit();
    try value.publishPaneFocus(0);
    try value.publishPaneFocus(1);
    try expectReadable(value.inputFd());
    try value.drainInputWake();
    try std.testing.expectEqual(@as(u8, 1), value.takePaneFocus().?);
    try std.testing.expect(value.takePaneFocus() == null);
}

test "pointer motion coalesces while button and wheel occurrences stay ordered" {
    var value = try boundary();
    defer value.deinit();

    const first_motion = shared.PointerEvent{
        .kind = .move,
        .button = .none,
        .modifiers = 1,
        .buttons_down = 0,
        .point = .{ .x = 10, .y = 20 },
    };
    const latest_motion = shared.PointerEvent{
        .kind = .move,
        .button = .none,
        .modifiers = 4,
        .buttons_down = 1,
        .point = .{ .x = 30, .y = 40 },
    };
    const press = shared.PointerEvent{
        .kind = .press,
        .button = .left,
        .modifiers = 4,
        .buttons_down = 1,
        .point = .{ .x = 30, .y = 40 },
    };
    const wheel = shared.PointerEvent{
        .kind = .wheel,
        .button = .wheel_down,
        .modifiers = 0,
        .buttons_down = 1,
        .point = .{ .x = 31, .y = 41 },
    };

    try value.publishPointerMotion(first_motion);
    try value.publishPointerMotion(latest_motion);
    try value.publishPointerEvent(press);
    try value.publishPointerEvent(wheel);
    try expectReadable(value.controlFd());
    try value.drainControlWake();

    try std.testing.expectEqualDeep(latest_motion, value.takePointer().?);
    try std.testing.expectEqualDeep(press, value.takePointer().?);
    try std.testing.expectEqualDeep(wheel, value.takePointer().?);
    try std.testing.expect(value.takePointer() == null);

    try std.testing.expectError(error.InvalidPointerEvent, value.publishPointerEvent(first_motion));
    try std.testing.expectError(error.InvalidPointerEvent, value.publishPointerMotion(press));
}

test "pointer occurrence queue is bounded without consuming motion state" {
    var value = try boundary();
    defer value.deinit();

    const motion = shared.PointerEvent{
        .kind = .move,
        .button = .none,
        .modifiers = 0,
        .buttons_down = 0,
        .point = .{ .x = 7, .y = 9 },
    };
    try value.publishPointerMotion(motion);
    for (0..shared.pointer_event_capacity) |index| {
        try value.publishPointerEvent(.{
            .kind = .wheel,
            .button = if (index % 2 == 0) .wheel_up else .wheel_down,
            .modifiers = 0,
            .buttons_down = 0,
            .point = .{ .x = 7, .y = 9 },
        });
    }
    try std.testing.expectError(error.PointerEventLimit, value.publishPointerEvent(.{
        .kind = .press,
        .button = .left,
        .modifiers = 0,
        .buttons_down = 1,
        .point = .{ .x = 7, .y = 9 },
    }));
    try std.testing.expectEqualDeep(motion, value.takePointer().?);
    for (0..shared.pointer_event_capacity) |_| try std.testing.expect(value.takePointer() != null);
}

test "semantic modifier bits are identical for keyboard and pointer transport" {
    const bits = shared.semanticModifierBits(.{
        .shift = true,
        .control = true,
        .alt = true,
        .super = true,
        .hyper = true,
        .meta = true,
        .caps_lock = true,
        .num_lock = true,
    });
    try std.testing.expectEqual(@as(u8, 0xff), bits);
}

test "routed mouse input preserves target pane and canonical coordinates" {
    var value = try boundary();
    defer value.deinit();

    const routed = shared.RoutedMouse{
        .scene_index = 1,
        .history_offset = 7,
        .alternate_screen = false,
        .value = .{
            .kind = .press,
            .button = .right,
            .modifiers = 5,
            .buttons_down = 4,
            .row = 12,
            .column = 34,
            .pixel_x = 345,
            .pixel_y = 678,
        },
    };
    try value.publishInput(.{ .mouse = routed });
    const event = value.takeInput().?;
    try std.testing.expect(event == .mouse);
    try std.testing.expectEqualDeep(routed, event.mouse);
}

test "coalesced drag motion cannot cross an ordered release" {
    var value = try boundary();
    defer value.deinit();

    const press = shared.PointerEvent{
        .kind = .press,
        .button = .left,
        .modifiers = 0,
        .buttons_down = 1,
        .point = .{ .x = 10, .y = 10 },
    };
    const drag = shared.PointerEvent{
        .kind = .move,
        .button = .none,
        .modifiers = 0,
        .buttons_down = 1,
        .point = .{ .x = 20, .y = 20 },
    };
    const release = shared.PointerEvent{
        .kind = .release,
        .button = .left,
        .modifiers = 0,
        .buttons_down = 0,
        .point = .{ .x = 20, .y = 20 },
    };
    try value.publishPointerEvent(press);
    try value.publishPointerMotion(drag);
    try value.publishPointerEvent(release);

    try std.testing.expectEqualDeep(press, value.takePointer().?);
    try std.testing.expectEqualDeep(drag, value.takePointer().?);
    try std.testing.expectEqualDeep(release, value.takePointer().?);
    try std.testing.expect(value.takePointer() == null);
}
