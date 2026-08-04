const std = @import("std");
const linux = std.os.linux;
const window_render_boundary = @import("window_render_boundary");
const session_chrome_adapter = @import("session_chrome_adapter");
const session = @import("session_domain");
const render = @import("howl_render");
const wayland = @import("howl_wayland");

fn boundary() !window_render_boundary.Boundary {
    return window_render_boundary.Boundary.init(std.testing.io);
}

fn closeDescriptor(descriptor: i32) std.posix.E {
    return std.posix.errno(std.posix.system.close(descriptor));
}

test "feedback and ring offers transfer complete copied ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 0x1234, .fourcc = 0x34324241, .modifier = 7 });
    try std.testing.expectEqual(@as(u64, 0x1234), value.readFeedback().?.device);
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    const offers = try realOffers();
    try value.publishOffers(offers);
    const taken = value.takeOffers().?;
    for (taken.slots) |offer| {
        try std.testing.expect(offer.dma_fd >= 0);
        try std.testing.expectEqual(std.posix.E.SUCCESS, closeDescriptor(offer.dma_fd));
        try std.testing.expectEqual(std.posix.E.SUCCESS, closeDescriptor(offer.acquire_timeline_fd));
        try std.testing.expectEqual(std.posix.E.SUCCESS, closeDescriptor(offer.release_timeline_fd));
    }
    try std.testing.expect(value.takeOffers() == null);
}

test "malformed offers preserve Boundary and caller descriptor ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    var offers = try realOffers();
    offers[1].plane_count = window_render_boundary.plane_limit + 1;
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
    try std.testing.expectEqual(std.posix.E.SUCCESS, closeDescriptor(displaced));
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
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    const first = try realOffers();
    const second = try realOffers();
    try value.publishOffers(first);
    const retained_count = value.offer_count;
    const retained_first_fd = value.offers[0].?.dma_fd;
    try std.testing.expectError(error.OffersPending, value.publishOffers(second));
    try std.testing.expectEqual(retained_count, value.offer_count);
    try std.testing.expectEqual(retained_first_fd, value.offers[0].?.dma_fd);
    const taken = value.takeOffers().?;
    try std.testing.expectEqual(retained_first_fd, taken.slots[0].dma_fd);
    closeOffers(taken.slots);
    closeOffers(second);
}

test "Boundary cleanup closes every retained offered descriptor" {
    var value = try boundary();
    const planes = [window_render_boundary.plane_limit]window_render_boundary.Plane{
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
    };
    var offers: [window_render_boundary.slot_count]window_render_boundary.SlotOffer = @splat(.{
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
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    try value.publishOffers(offers);
    value.deinit();
    for (offers) |offer| {
        try std.testing.expectEqual(std.posix.E.BADF, closeDescriptor(offer.dma_fd));
        try std.testing.expectEqual(std.posix.E.BADF, closeDescriptor(offer.acquire_timeline_fd));
        try std.testing.expectEqual(std.posix.E.BADF, closeDescriptor(offer.release_timeline_fd));
    }
}

test "completion queue is bounded ordered and never acknowledges Render" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?.slots);
    value.markWindowRingReady(1);
    try std.testing.expect(value.canPublishCompletion(1));
    try std.testing.expect(!value.canPublishCompletion(2));
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try value.publishCompletion(.{ .generation = 1, .revision = 3, .slot = 2, .acquire_point = 3, .release_point = 1 });
    try std.testing.expect(!value.canPublishCompletion(1));
    try std.testing.expectError(error.CompletionLimit, value.publishCompletion(.{ .generation = 1, .revision = 4, .slot = 0, .acquire_point = 4, .release_point = 2 }));
    try std.testing.expectEqual(@as(u64, 1), value.takeCompletion().?.revision);
    try std.testing.expect(value.canPublishCompletion(1));
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
    try std.testing.expectEqual(@as(u64, 3), value.takeCompletion().?.revision);
    try std.testing.expect(value.takeCompletion() == null);
}

test "invalid and stale revisions preserve queued completion" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?.slots);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 });
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .generation = 1, .revision = 2, .slot = 2, .acquire_point = 3, .release_point = 1 }));
    try std.testing.expectError(error.InvalidRevision, value.publishCompletion(.{ .generation = 1, .revision = 3, .slot = 3, .acquire_point = 4, .release_point = 1 }));
    try std.testing.expectEqual(@as(u64, 2), value.takeCompletion().?.revision);
}

test "completion batch validates fully before publishing any member" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?.slots);
    value.markWindowRingReady(1);
    const valid = [_]window_render_boundary.Completion{
        .{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 },
        .{ .generation = 1, .revision = 2, .slot = 1, .acquire_point = 2, .release_point = 1 },
        .{ .generation = 1, .revision = 3, .slot = 2, .acquire_point = 3, .release_point = 1 },
    };
    var malformed = valid;
    malformed[2].revision = 2;
    try std.testing.expectError(
        error.InvalidRevision,
        value.prepareCompletions(&malformed),
    );
    try std.testing.expect(value.takeCompletion() == null);
    var prepared = try value.prepareCompletions(&valid);
    defer prepared.deinit();
    try std.testing.expect(!value.canPublishCompletion(1));
    prepared.commit();
    for (valid) |expected|
        try std.testing.expectEqual(expected, value.takeCompletion().?);
    try std.testing.expect(value.takeCompletion() == null);
}

test "stop is monotonic and preserves the first runtime failure" {
    var value = try boundary();
    defer value.deinit();
    value.requestStop(.window);
    value.requestStop(.render);
    try std.testing.expect(value.shouldStop());
    try std.testing.expectEqual(window_render_boundary.Failure.window, value.failure.?);
    try std.testing.expectError(error.Stopping, value.publishFeedback(.{ .device = 1, .fourcc = 1, .modifier = 1 }));
    value.markStopped(.window);
    value.markStopped(.render);
    const stopped = value.stopped();
    try std.testing.expect(stopped.window and stopped.render);
}

test "clean stop cannot be relabeled by a later owner callback" {
    var value = try boundary();
    defer value.deinit();
    value.requestStop(null);
    value.requestStop(.window);
    value.requestStop(.render);
    try std.testing.expect(value.shouldStop());
    try std.testing.expect(value.failure == null);
}

test "directional wakes follow fact ownership" {
    var value = try boundary();
    defer value.deinit();
    try value.publishFeedback(.{ .device = 1, .fourcc = 2, .modifier = 3 });
    try expectReadable(value.renderFd());
    try value.drainRenderWake();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    try value.publishOffers(try realOffers());
    closeOffers(value.takeOffers().?.slots);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    try expectReadable(value.windowFd());
    try value.drainWindowWake();
}

test "Window input facts cross the Window/Render boundary without policy" {
    var value = try boundary();
    defer value.deinit();
    try value.publishInput(.{ .key = .{ .keycode = 44, .time = 17, .state = .repeated, .serial = 9, .modifiers = .{ .serial = 8, .depressed = 1, .latched = 2, .locked = 4, .group = 3 }, .semantic_modifiers = .{}, .keysym = @fromBackingInt(@intCast(0)), .text_len = 0, .text = std.mem.zeroes([wayland.input.key_text_limit]u8) } });
    try value.publishMotion(.{
        .time = 18,
        .point = .{ .x = 12.5, .y = 8.25 },
        .semantic_modifiers = .{},
    });
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
    try std.testing.expectError(error.InvalidConfigure, value.publishConfigure(0, 480, 640, 480, 0, null, null, 1, false));
    try value.publishConfigure(640, 480, 640, 480, 0, null, null, 1, false);
    const first = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u64, 1), first.generation);
    try value.publishConfigure(640, 480, 640, 480, 0, null, null, 1, false);
    try std.testing.expect(value.takeConfigure() == null);
    try value.publishConfigure(700, 500, 700, 500, 0, null, null, 1, false);
    try value.publishConfigure(800, 600, 800, 600, 0, null, null, 1, false);
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

test "logical and physical configure facts remain paired transactionally" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(640, 480, 960, 720, 4, null, null, 1, true);
    const first = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u32, 640), first.logical_width);
    try std.testing.expectEqual(@as(u32, 960), first.physical_width);
    try std.testing.expectEqual(@as(u64, 4), first.scale_revision);
    try std.testing.expect(first.use_viewport);
    try std.testing.expectError(error.InvalidConfigure, value.publishConfigure(640, 480, 9000, 720, 5, null, null, 1, true));
    try std.testing.expectEqual(@as(u64, 1), value.latest_generation);
    try value.publishConfigure(640, 480, 1280, 960, 5, null, null, 2, false);
    const second = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u64, 2), second.generation);
    try std.testing.expectEqual(@as(u32, 1280), second.physical_width);
    try std.testing.expectEqual(@as(u32, 2), second.buffer_scale);
    try std.testing.expect(!second.use_viewport);
}

test "SurfaceConfig transports factual DPI without fabricating provisional facts" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(
        100,
        80,
        100,
        80,
        0,
        null,
        null,
        1,
        false,
    );
    const provisional = value.takeConfigure().?;
    try std.testing.expect(provisional.dpi_x == null);
    try std.testing.expect(provisional.dpi_y == null);

    const dpi = window_render_boundary.ExactRational{
        .numerator = 768,
        .denominator = 5,
    };
    try value.publishConfigure(100, 80, 160, 128, 3, dpi, dpi, 1, true);
    const accepted = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u64, 3), accepted.scale_revision);
    try std.testing.expectEqual(dpi, accepted.dpi_x.?);
    try std.testing.expectEqual(dpi, accepted.dpi_y.?);

    try std.testing.expectError(
        error.InvalidConfigure,
        value.publishConfigure(100, 80, 160, 128, 0, dpi, dpi, 1, true),
    );
    try std.testing.expectError(
        error.InvalidConfigure,
        value.publishConfigure(
            100,
            80,
            160,
            128,
            4,
            .{ .numerator = 192, .denominator = 2 },
            dpi,
            1,
            true,
        ),
    );
    try std.testing.expect(value.takeConfigure() == null);
}

test "taken ring retains its exact configure while a newer ring is offered" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 1, null, null, 1, false);
    const generation = value.takeConfigure().?.generation;
    var offers = try realOffers();
    offers[0].generation = generation;
    offers[1].generation = generation;
    offers[2].generation = generation;
    try value.publishOffers(offers);
    const taken = value.takeOffers().?;
    try std.testing.expectEqual(generation, taken.config.generation);
    try std.testing.expectEqual(@as(u32, 64), taken.config.physical_width);

    try value.publishConfigure(64, 64, 96, 96, 2, null, null, 1, true);
    const newer = value.takeConfigure().?;
    var newer_offers = try realOffers();
    for (&newer_offers) |*offer| {
        offer.generation = newer.generation;
        offer.width = newer.physical_width;
        offer.height = newer.physical_height;
    }
    try value.publishOffers(newer_offers);
    const newer_taken = value.takeOffers().?;
    try std.testing.expectEqual(newer, newer_taken.config);
    try std.testing.expectEqual(generation, taken.config.generation);

    closeOffers(taken.slots);
    closeOffers(newer_taken.slots);
    value.markWindowRingReady(generation);
}

test "1.6x Boundary offer transaction retains logical Canvas and physical ring facts" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(1000, 600, 1600, 960, 1, null, null, 1, true);
    const config = value.takeConfigure().?;
    try std.testing.expectEqual(@as(u32, 1000), config.logical_width);
    try std.testing.expectEqual(@as(u32, 1600), config.physical_width);

    var topology = try session.SessionState.init(.{
        .width = @intCast(config.logical_width),
        .height = @intCast(config.logical_height - 24),
    });
    var primitives: [128]render.chrome.Primitive = undefined;
    var text: [1024]u8 = undefined;
    const projected = try session_chrome_adapter.project(&topology, .{
        .style = .{
            .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
            .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
            .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
        },
        .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
        .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
    }, .{ .width = 1000, .height = 600 }, .{ .y = 24 }, &.{}, &primitives, &text);
    try std.testing.expectEqual(render.canvas.Size{ .width = 1000, .height = 600 }, projected.surface);

    var offers = try realOffers();
    for (&offers) |*offer| {
        offer.generation = config.generation;
        offer.width = config.physical_width;
        offer.height = config.physical_height;
    }
    try value.publishOffers(offers);
    const taken = value.takeOffers().?;
    try std.testing.expectEqual(config, taken.config);
    for (taken.slots) |offer| {
        try std.testing.expectEqual(config.physical_width, offer.width);
        try std.testing.expectEqual(config.physical_height, offer.height);
    }
    closeOffers(taken.slots);
    value.markWindowRingReady(config.generation);
}

test "fractional offers retain viewport ownership across a newer integer configure" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(100, 80, 160, 128, 1, null, null, 1, true);
    const fractional_generation = value.takeConfigure().?.generation;
    var offers = try realOffers();
    for (&offers) |*offer| {
        offer.generation = fractional_generation;
        offer.width = 160;
        offer.height = 128;
    }
    try value.publishOffers(offers);
    try std.testing.expect(value.pendingOffersUseViewport());

    // Capability removal may publish the integer successor before Window has
    // taken the already-transferred fractional ring.
    try value.publishConfigure(100, 80, 200, 160, 2, null, null, 2, false);
    try std.testing.expect(value.pendingOffersUseViewport());
    const taken = value.takeOffers().?;
    try std.testing.expect(taken.config.use_viewport);
    try std.testing.expectEqual(fractional_generation, taken.config.generation);
    closeOffers(taken.slots);
    try std.testing.expect(!value.pendingOffersUseViewport());
    const integer = value.takeConfigure().?;
    try std.testing.expect(!integer.use_viewport);
    try std.testing.expect(integer.generation > fractional_generation);
}

test "replacement readiness cancels queued stale completions" {
    var value = try boundary();
    defer value.deinit();
    try value.publishConfigure(64, 64, 64, 64, 0, null, null, 1, false);
    value.markWindowRingReady(1);
    try value.publishCompletion(.{ .generation = 1, .revision = 1, .slot = 0, .acquire_point = 1, .release_point = 1 });
    value.markWindowRingReady(2);
    try std.testing.expect(value.takeCompletion() == null);
}

test "session adapter retains stable identities through pane and tab changes" {
    var state = try session.SessionState.init(.{ .width = 640, .height = 456 });
    const tab = state.tabId(0).?;
    const pane = state.paneId(0, 0).?;
    const split = try state.split(pane, .vertical);
    try state.renameTab(tab, "主");
    try std.testing.expectEqual(pane, state.paneId(0, 0).?);
    try std.testing.expectEqual(split, state.paneId(0, 1).?);
    var primitives: [128]render.chrome.Primitive = undefined;
    var text: [1024]u8 = undefined;
    const output = try session_chrome_adapter.project(&state, .{
        .style = .{
            .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
            .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
            .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
        },
        .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
        .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
    }, .{ .width = 640, .height = 480 }, .{ .y = 24 }, &.{}, &primitives, &text);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expectEqualStrings("主", output.text[0.."主".len]);
    try state.closePane(split);
    try std.testing.expectEqual(@as(usize, 1), state.paneCount(0));
}

fn expectReadable(descriptor: i32) !void {
    var poll_descriptor = std.posix.pollfd{
        .fd = descriptor,
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        try std.posix.poll((&poll_descriptor)[0..1], 0),
    );
    try std.testing.expect((poll_descriptor.revents & std.posix.POLL.IN) != 0);
}

fn eventDescriptor() !i32 {
    const value = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
    if (linux.errno(value) != .SUCCESS) return error.Descriptor;
    return std.math.cast(i32, value) orelse return error.Descriptor;
}

fn realOffers() ![window_render_boundary.slot_count]window_render_boundary.SlotOffer {
    const planes = [window_render_boundary.plane_limit]window_render_boundary.Plane{
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
    };
    var offers: [window_render_boundary.slot_count]window_render_boundary.SlotOffer = @splat(.{
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

fn closeOffers(offers: [window_render_boundary.slot_count]window_render_boundary.SlotOffer) void {
    for (offers) |offer| {
        if (offer.dma_fd >= 0) std.debug.assert(closeDescriptor(offer.dma_fd) == .SUCCESS);
        if (offer.acquire_timeline_fd >= 0) std.debug.assert(closeDescriptor(offer.acquire_timeline_fd) == .SUCCESS);
        if (offer.release_timeline_fd >= 0) std.debug.assert(closeDescriptor(offer.release_timeline_fd) == .SUCCESS);
    }
}
