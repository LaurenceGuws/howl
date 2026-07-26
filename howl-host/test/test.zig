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
    const planes = [shared.plane_limit]shared.Plane{
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
        .{ .offset = 0, .stride = 256 },
    };
    const offers = [_]shared.SlotOffer{
        .{ .dma_fd = 3, .acquire_timeline_fd = 9, .release_timeline_fd = 4, .plane_count = 1, .planes = planes },
        .{ .dma_fd = 5, .acquire_timeline_fd = 10, .release_timeline_fd = 6, .plane_count = 1, .planes = planes },
        .{ .dma_fd = 7, .acquire_timeline_fd = 11, .release_timeline_fd = 8, .plane_count = 1, .planes = planes },
    };
    try value.publishOffers(offers);
    const taken = value.takeOffers().?;
    try std.testing.expectEqual(@as(i32, 7), taken[2].dma_fd);
    try std.testing.expect(value.takeOffers() == null);
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

test "eventfd lifetime failure becomes the first runtime failure" {
    var value = try boundary();
    defer value.deinit();
    const descriptor = value.window_fd;
    value.window_fd = -1;
    value.requestStop(null);
    value.window_fd = descriptor;
    try std.testing.expectEqual(shared.Failure.signal, value.failure.?);
    value.requestStop(.window);
    try std.testing.expectEqual(shared.Failure.signal, value.failure.?);
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
