const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const font_owner = @import("fonts.zig");
const terminal = @import("terminal.zig");
const canvas = @import("canvas.zig");
const allocator = std.heap.smp_allocator;
const version = "0.1.6-dev";

const Pane = struct {
    owner: *terminal.Terminal,
    canvas: canvas.Canvas,
    rows: u16 = 0,
    columns: u16 = 0,
};

/// Owns SDL/application lifetime and graphical leases; terminal workers retain canonical authority.
pub fn main(init: std.process.Init) !void {
    const args = init.minimal.args.vector;
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--version")) {
        std.debug.print("Howl {s} (Zig SDL app)\n", .{version});
        return;
    }
    if (args.len != 1) return error.InvalidArguments;
    if (!c.SDL_SetAppMetadata("Howl", version, "io.github.laurenceguws.howl")) return error.SDL;
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    var fonts = try font_owner.Fonts.discover(allocator, init.environ_map);
    defer fonts.deinit();
    const font_path = try allocator.dupeSentinel(u8, fonts.paths[0], 0);
    defer allocator.free(font_path);
    const ui_font = c.TTF_OpenFont(font_path, 15) orelse return error.TTF;
    defer c.TTF_CloseFont(ui_font);
    const window = c.SDL_CreateWindow("Howl", 1000, 650, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const renderer = c.SDL_CreateRenderer(window, null) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    if (!c.SDL_SetRenderVSync(renderer, 1) or !c.SDL_StartTextInput(window)) return error.SDL;
    const wake_event = c.SDL_RegisterEvents(1);
    if (wake_event == std.math.maxInt(u32)) return error.SDL;
    const geometry = try allocator.create(canvas.Geometry);
    defer allocator.destroy(geometry);
    geometry.* = .{};

    var scale = c.SDL_GetWindowDisplayScale(window);
    if (!std.math.isFinite(scale) or scale <= 0 or scale > 8) return error.DisplayScale;
    const physical_font: u16 = @intFromFloat(@round(15 * scale));
    var pane = Pane{
        .owner = try terminal.Terminal.create(allocator, init.io, init.minimal.environ, .{
            .shell = init.environ_map.get("SHELL") orelse "/bin/sh",
            .rows = 37,
            .columns = 80,
        }, fonts.config(physical_font), wake_event, true),
        .canvas = canvas.Canvas.init(allocator),
    };
    defer pane.owner.destroy();
    defer pane.canvas.deinit();
    var running = true;
    while (running) {
        if (pane.owner.takeFrame()) try pane.canvas.update(renderer, pane.owner.renderExchange());
        const status = pane.owner.snapshot();
        if (status.failure) |failure| return failure;
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(window, &width, &height)) return error.SDL;
        const next_scale = c.SDL_GetWindowDisplayScale(window);
        if (next_scale != scale) {
            // Font reconfiguration is part of the next daily-shell cut.
            scale = next_scale;
        }
        if (!c.SDL_SetRenderScale(renderer, scale, scale) or
            !c.SDL_SetRenderDrawColor(renderer, 24, 25, 33, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
        try drawText(renderer, ui_font, "Howl", 12, 10);
        const rect: c.SDL_FRect = .{ .x = 8, .y = 42, .w = @floatFromInt(@max(1, width - 16)), .h = @floatFromInt(@max(1, height - 50)) };
        if (pane.canvas.frame()) |frame| {
            const rows: u16 = @intFromFloat(std.math.clamp(@floor(rect.h * scale / @as(f32, @floatFromInt(frame.cell_size.height))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_rows))));
            const columns: u16 = @intFromFloat(std.math.clamp(@floor(rect.w * scale / @as(f32, @floatFromInt(frame.cell_size.width))), 1, @as(f32, @floatFromInt(instance.render.limits.maximum_columns))));
            if (rows != pane.rows or columns != pane.columns) {
                try pane.owner.submit(.{ .resize = .{ .rows = rows, .columns = columns } });
                pane.rows = rows;
                pane.columns = columns;
            }
            try pane.canvas.draw(renderer, geometry, rect, scale);
        }
        if (!c.SDL_RenderPresent(renderer)) return error.SDL;
        pane.owner.requestFrame();
        var event: c.SDL_Event = undefined;
        if (!c.SDL_WaitEvent(&event)) return error.SDL;
        while (true) {
            switch (event.type) {
                c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => running = false,
                c.SDL_EVENT_TEXT_INPUT => {
                    const text = std.mem.span(event.text.text);
                    try pane.owner.submit(.{ .input = .{ .bytes = text } });
                },
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                    const mods = modifiers(event.key.mod);
                    if (event.type == c.SDL_EVENT_KEY_DOWN and mods.control and mods.shift and event.key.key == c.SDLK_V) {
                        const text = c.SDL_GetClipboardText();
                        if (text != null) {
                            defer c.SDL_free(text);
                            try pane.owner.submit(.{ .input = .{ .paste = std.mem.span(text) } });
                        }
                    } else if (namedKey(event.key.key)) |key| {
                        try pane.owner.submit(.{ .input = .{ .key = .{
                            .key = .{ .named = key },
                            .mods = mods,
                            .action = if (event.type == c.SDL_EVENT_KEY_UP) .release else if (event.key.repeat) .repeat else .press,
                        } } });
                    } else if (mods.control and event.key.key >= c.SDLK_A and event.key.key <= c.SDLK_Z) {
                        try pane.owner.submit(.{ .input = .{ .key = .{
                            .key = try instance.Key.initUnicode(@intCast(event.key.key)),
                            .mods = mods,
                            .action = if (event.type == c.SDL_EVENT_KEY_UP) .release else if (event.key.repeat) .repeat else .press,
                        } } });
                    }
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    try pane.owner.submit(.{ .scroll = @intFromFloat(@round(event.wheel.y * 3)) });
                },
                c.SDL_EVENT_WINDOW_FOCUS_GAINED => try pane.owner.submit(.{ .input = .{ .focus = .in } }),
                c.SDL_EVENT_WINDOW_FOCUS_LOST => try pane.owner.submit(.{ .input = .{ .focus = .out } }),
                else => {},
            }
            if (!c.SDL_PollEvent(&event)) break;
        }
    }
}

fn drawText(renderer: *c.SDL_Renderer, font: *c.TTF_Font, text: []const u8, x: f32, y: f32) !void {
    const surface = c.TTF_RenderText_Blended(font, text.ptr, text.len, .{ .r = 224, .g = 226, .b = 238, .a = 255 }) orelse return error.TTF;
    defer c.SDL_DestroySurface(surface);
    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return error.SDL;
    defer c.SDL_DestroyTexture(texture);
    const rect: c.SDL_FRect = .{ .x = x, .y = y, .w = @floatFromInt(surface.*.w), .h = @floatFromInt(surface.*.h) };
    if (!c.SDL_RenderTexture(renderer, texture, null, &rect)) return error.SDL;
}

fn modifiers(mod: c.SDL_Keymod) instance.InputModifier {
    return .{
        .shift = mod & c.SDL_KMOD_SHIFT != 0,
        .control = mod & c.SDL_KMOD_CTRL != 0,
        .alt = mod & c.SDL_KMOD_ALT != 0,
        .super = mod & c.SDL_KMOD_GUI != 0,
        .caps_lock = mod & c.SDL_KMOD_CAPS != 0,
        .num_lock = mod & c.SDL_KMOD_NUM != 0,
    };
}

fn namedKey(key: c.SDL_Keycode) ?instance.KeyName {
    return switch (key) {
        c.SDLK_RETURN => .enter,
        c.SDLK_TAB => .tab,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_ESCAPE => .escape,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        c.SDLK_INSERT => .insert,
        c.SDLK_DELETE => .delete,
        c.SDLK_HOME => .home,
        c.SDLK_END => .end,
        c.SDLK_PAGEUP => .page_up,
        c.SDLK_PAGEDOWN => .page_down,
        c.SDLK_F1 => .f1,
        c.SDLK_F2 => .f2,
        c.SDLK_F3 => .f3,
        c.SDLK_F4 => .f4,
        c.SDLK_F5 => .f5,
        c.SDLK_F6 => .f6,
        c.SDLK_F7 => .f7,
        c.SDLK_F8 => .f8,
        c.SDLK_F9 => .f9,
        c.SDLK_F10 => .f10,
        c.SDLK_F11 => .f11,
        c.SDLK_F12 => .f12,
        else => null,
    };
}

test {
    std.testing.refAllDecls(@import("publication.zig"));
    std.testing.refAllDecls(canvas);
    std.testing.refAllDecls(terminal);
    std.testing.refAllDecls(font_owner);
}
