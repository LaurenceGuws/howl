//! Deliberately small GTK4 pressure client for one shared Howl session.

const std = @import("std");
const native = @import("gtk_native");
const client = @import("howl_client");
const text = @import("howl_text");

const margin: i32 = 8;
const default_font = "/usr/share/fonts/noto/NotoSansMono-Regular.ttf";

const State = struct {
    allocator: std.mem.Allocator,
    mutex: std.atomic.Mutex = .unlocked,
    snapshot: client.Snapshot,
    observer: client.Connection,
    control: client.Connection,
    font: *text.FontSet,
    metrics: text.Metrics,
    area: ?*native.DrawingArea = null,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    worker_failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    control_failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn lock(self: *State) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }

    fn unlock(self: *State) void {
        self.mutex.unlock();
    }

    fn init(allocator: std.mem.Allocator, socket_path: []const u8, font_path: []const u8) !State {
        var observer = try client.Connection.connect(allocator, socket_path);
        errdefer observer.deinit();
        var snapshot = try observer.observe(0);
        errdefer snapshot.deinit();
        var control = try client.Connection.connect(allocator, socket_path);
        errdefer control.deinit();
        const font = try text.FontSet.init(allocator, .{
            .primary = font_path,
            .size = .{ .pixels = 18 },
        });
        errdefer font.deinit();
        return .{
            .allocator = allocator,
            .snapshot = snapshot,
            .observer = observer,
            .control = control,
            .font = font,
            .metrics = font.metrics(),
        };
    }

    fn deinit(self: *State) void {
        if (self.area) |area| native.howl_gtk_drawing_area_unref(area);
        self.font.deinit();
        self.control.deinit();
        self.observer.deinit();
        self.snapshot.deinit();
        self.* = undefined;
    }
};

/// Attaches one real session to a GTK4 window. Usage: `howl-gtk SOCKET [FONT]`.
pub fn main(init: std.process.Init) !void {
    const argv = init.minimal.args.vector;
    if (argv.len < 2 or argv.len > 3) return error.InvalidArguments;
    const socket_path = std.mem.span(argv[1]);
    const font_path = if (argv.len == 3) std.mem.span(argv[2]) else default_font;

    var state = try State.init(std.heap.page_allocator, socket_path, font_path);
    defer state.deinit();
    const observer_thread = try std.Thread.spawn(.{}, observeLoop, .{&state});
    var observer_joined = false;
    defer if (!observer_joined) {
        state.stop.store(true, .release);
        state.observer.interrupt();
        observer_thread.join();
    };

    const application = native.howl_gtk_application_new() orelse return error.GtkApplication;
    defer native.howl_gtk_application_unref(application);
    native.howl_gtk_connect_activate(application, activate, @ptrCast(&state));
    const status = native.howl_gtk_application_run(application);

    state.stop.store(true, .release);
    state.observer.interrupt();
    observer_thread.join();
    observer_joined = true;

    if (state.worker_failed.load(.acquire)) return error.ObserveWorker;
    if (state.control_failed.load(.acquire)) return error.ControlConnection;
    if (status != 0) return error.GtkRun;
}

fn observeLoop(state: *State) void {
    state.lock();
    var after_revision = state.snapshot.revision;
    state.unlock();

    while (!state.stop.load(.acquire)) {
        const next = state.observer.observe(after_revision) catch {
            if (!state.stop.load(.acquire)) state.worker_failed.store(true, .release);
            return;
        };
        after_revision = next.revision;

        state.lock();
        state.snapshot.deinit();
        state.snapshot = next;
        const area = state.area;
        state.unlock();

        if (area) |widget| native.howl_gtk_queue_draw_async(widget);
    }
}

fn activate(application: ?*native.Application, user_data: ?*native.Context) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data orelse return));
    const app = application orelse return;
    const window = native.howl_gtk_window_new(app) orelse return;
    native.howl_gtk_window_set_title(window, "Howl shared session");

    state.lock();
    const width_pixels = @as(i64, state.snapshot.columns) * state.metrics.advance_width + margin * 2;
    const height_pixels = @as(i64, state.snapshot.rows) * state.metrics.line_height + margin * 2;
    state.unlock();
    const width = std.math.cast(c_int, width_pixels) orelse 900;
    const height = std.math.cast(c_int, height_pixels) orelse 600;
    native.howl_gtk_window_set_default_size(window, width, height);

    const area = native.howl_gtk_drawing_area_new() orelse return;
    native.howl_gtk_drawing_area_set_draw_func(area, draw, @ptrCast(state));
    native.howl_gtk_window_set_child(window, area);
    native.howl_gtk_window_add_key_controller(window, keyPressed, @ptrCast(state));

    native.howl_gtk_drawing_area_ref(area);
    state.lock();
    if (state.area == null) state.area = area else native.howl_gtk_drawing_area_unref(area);
    state.unlock();

    native.howl_gtk_window_present(window);
}

fn keyPressed(
    _: ?*native.Controller,
    keyval: c_uint,
    _: c_uint,
    _: c_uint,
    user_data: ?*native.Context,
) callconv(.c) c_int {
    const state: *State = @ptrCast(@alignCast(user_data orelse return 0));
    var encoded: [4]u8 = undefined;
    const count = native.howl_gtk_keyval_bytes(keyval, &encoded);
    if (count <= 0 or count > encoded.len) return 0;
    state.control.input(encoded[0..@intCast(count)]) catch {
        state.control_failed.store(true, .release);
        return 0;
    };
    return 1;
}

fn draw(
    _: ?*native.DrawingArea,
    cairo: ?*native.Cairo,
    _: c_int,
    _: c_int,
    user_data: ?*native.Context,
) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(user_data orelse return));
    const cr = cairo orelse return;
    native.howl_cairo_clear(cr, 0.035, 0.04, 0.05);
    native.howl_cairo_set_rgb(cr, 0.92, 0.93, 0.95);

    state.lock();
    defer state.unlock();
    var row: u16 = 0;
    while (row < state.snapshot.rows) : (row += 1) {
        var column: u16 = 0;
        while (column < state.snapshot.columns) : (column += 1) {
            const cell = state.snapshot.cell(row, column);
            if (cell.x != 0 or cell.y != 0 or cell.codepoint == 0 or cell.codepoint == ' ') continue;
            drawCell(state, cr, row, column, cell.codepoint);
        }
    }
}

fn drawCell(state: *State, cr: *native.Cairo, row: u16, column: u16, codepoint: u32) void {
    if (codepoint > 0x10ffff or codepoint >= 0xd800 and codepoint <= 0xdfff) return;
    const sequence = [1]u32{codepoint};
    const face = (state.font.faceFor(&sequence) catch return) orelse return;
    const scalar = std.math.cast(u21, codepoint) orelse return;
    const glyph = state.font.glyphForCodepoint(face, scalar) catch return;
    if (glyph == 0) return;
    var raster = state.font.rasterize(
        state.allocator,
        face,
        glyph,
        state.metrics.advance_width,
    ) catch return;
    defer raster.deinit();
    if (raster.width == 0 or raster.height == 0) return;

    const x = margin + @as(i32, column) * state.metrics.advance_width + raster.left;
    const baseline = margin + @as(i32, row) * state.metrics.line_height + state.metrics.baseline;
    const y_position = baseline - raster.top;
    native.howl_cairo_mask_a8(
        cr,
        raster.pixels.ptr,
        @intCast(raster.width),
        @intCast(raster.height),
        x,
        y_position,
    );
}
