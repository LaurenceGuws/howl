//! Tiny typed ABI between the experimental Zig client and GTK4/Cairo.

pub const Application = opaque {};
pub const Window = opaque {};
pub const DrawingArea = opaque {};
pub const Controller = opaque {};
pub const Cairo = opaque {};
pub const Context = opaque {};

pub const ActivateFn = *const fn (?*Application, ?*Context) callconv(.c) void;
pub const DrawFn = *const fn (?*DrawingArea, ?*Cairo, c_int, c_int, ?*Context) callconv(.c) void;
pub const KeyFn = *const fn (?*Controller, c_uint, c_uint, c_uint, ?*Context) callconv(.c) c_int;

pub extern fn howl_gtk_application_new() ?*Application;
pub extern fn howl_gtk_connect_activate(application: *Application, callback: ActivateFn, data: ?*Context) void;
pub extern fn howl_gtk_application_run(application: *Application) c_int;
pub extern fn howl_gtk_application_unref(application: *Application) void;
pub extern fn howl_gtk_window_new(application: *Application) ?*Window;
pub extern fn howl_gtk_window_set_title(window: *Window, title: [*:0]const u8) void;
pub extern fn howl_gtk_window_set_default_size(window: *Window, width: c_int, height: c_int) void;
pub extern fn howl_gtk_drawing_area_new() ?*DrawingArea;
pub extern fn howl_gtk_drawing_area_set_draw_func(area: *DrawingArea, callback: DrawFn, data: ?*Context) void;
pub extern fn howl_gtk_window_set_child(window: *Window, child: *DrawingArea) void;
pub extern fn howl_gtk_window_present(window: *Window) void;
pub extern fn howl_gtk_window_add_key_controller(window: *Window, callback: KeyFn, data: ?*Context) void;
pub extern fn howl_gtk_drawing_area_ref(area: *DrawingArea) void;
pub extern fn howl_gtk_drawing_area_unref(area: *DrawingArea) void;
pub extern fn howl_gtk_queue_draw_async(area: *DrawingArea) void;
pub extern fn howl_gtk_keyval_bytes(keyval: c_uint, output: *[4]u8) c_int;
pub extern fn howl_cairo_clear(cairo: *Cairo, red: f64, green: f64, blue: f64) void;
pub extern fn howl_cairo_set_rgb(cairo: *Cairo, red: f64, green: f64, blue: f64) void;
pub extern fn howl_cairo_mask_a8(
    cairo: *Cairo,
    tight_pixels: [*]const u8,
    width: c_int,
    height: c_int,
    x: c_int,
    y: c_int,
) void;
