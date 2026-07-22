//! Owns one concrete EGL/GLES render thread and its coalesced terminal frame.

const std = @import("std");
const howl_control = @import("howl_control");
const howl_frame = @import("howl_frame");
const howl_render = @import("howl_render");
const howl_text = @import("howl_text");
const howl_vt = @import("howl_vt");
const labels = @import("labels.zig");
const workspace = @import("workspace.zig");
const c = @import("native.zig").c;

const texture_capacity = howl_render.cache_capacity;
const texture_byte_capacity = howl_render.cache_byte_capacity;
/// Bounds simultaneously composed panes and frame borrows in one visible tab.
pub const max_visible_panes: usize = workspace.max_panes_per_tab;
/// Bounds each nonzero Wayland/GLES width or height before C-int narrowing.
pub const max_window_dimension: u32 = 8_192;
const max_backing_bytes: usize = 128 * 1024 * 1024;
const palette = struct {
    const background = howl_vt.Terminal.Rgb{ .r = 0x28, .g = 0x28, .b = 0x28 };
    const foreground = howl_vt.Terminal.Rgb{ .r = 0xeb, .g = 0xdb, .b = 0xb2 };
    const active_foreground = howl_vt.Terminal.Rgb{ .r = 0xee, .g = 0xee, .b = 0xee };
    const active_background = howl_vt.Terminal.Rgb{ .r = 0xd6, .g = 0x5d, .b = 0x0e };
    const inactive_background = howl_vt.Terminal.Rgb{ .r = 0x20, .g = 0x20, .b = 0x20 };
    const unavailable = howl_vt.Terminal.Rgb{ .r = 0xbd, .g = 0xae, .b = 0x93 };
};

/// Carries one nonzero logical Wayland surface extent in pixels.
pub const Size = struct {
    /// Reports nonzero logical width.
    width: u32,
    /// Reports nonzero logical height.
    height: u32,
};

/// Reports exact shared preparation, frame release, EGL/GLES, or wake failure.
pub const Error = howl_render.Error || howl_control.FrameReleaseError || error{
    EglDisplay,
    EglInitialize,
    EglConfig,
    EglContext,
    EglSurface,
    Shader,
    Texture,
    Draw,
    Swap,
    Signal,
    Stopping,
    StaleGeneration,
    BackingLimit,
    FrameUnavailable,
    InvalidSize,
    InvalidFonts,
    Cleanup,
};

/// Reports construction failure before the render thread becomes available.
pub const StartError = std.Thread.SpawnError || howl_text.InitError || Error;

/// Borrows stable Wayland values and a font path through render-thread startup.
pub const Init = struct {
    /// Borrows the connected Wayland display during render-thread lifetime.
    display: *c.struct_wl_display,
    /// Borrows the live Wayland surface during render-thread lifetime.
    surface: *c.struct_wl_surface,
    /// Supplies the initial nonzero logical surface size.
    size: Size,
    /// Borrows one primary followed by bounded fallback paths through startup.
    font_paths: []const []const u8,
};

const Work = struct {
    generation: u64,
    size: Size,
    panes: [max_visible_panes]Pane = undefined,
    pane_count: u8,
    live: [workspace.max_panes]PaneId = undefined,
    live_count: u8,
    dirty: [workspace.max_panes]*howl_control.Terminal = undefined,
    dirty_count: u8,
    label_cells: [workspace.max_cols]labels.Cell = undefined,
    label_count: u16,
    label_height: u16,
};

const Mailbox = struct {
    pending: ?Work = null,

    fn admit(self: *Mailbox, work: Work) void {
        var newest = work;
        if (self.pending) |pending| {
            for (pending.dirty[0..pending.dirty_count]) |terminal| {
                if (!containsAvailableTerminal(newest.panes[0..newest.pane_count], terminal) or
                    containsDirty(newest.dirty[0..newest.dirty_count], terminal)) continue;
                newest.dirty[newest.dirty_count] = terminal;
                newest.dirty_count += 1;
            }
        }
        self.pending = newest;
    }

    fn takePending(self: *Mailbox) ?Work {
        const work = self.pending;
        self.pending = null;
        return work;
    }

    fn empty(self: *const Mailbox) bool {
        return self.pending == null;
    }
};

/// Gives one stable nonzero identity to a composed pane.
pub const PaneId = workspace.PaneId;

/// Places one terminal in a bounded visible pane without borrowing its frame.
pub const Pane = struct {
    /// Identifies this pane backing; zero is invalid and identities are stable.
    id: PaneId,
    /// Borrows the terminal through render shutdown; the window loop owns it.
    terminal: *howl_control.Terminal,
    /// Places the pane's left edge within the submitted window width.
    x: u32,
    /// Places the pane's top edge within the submitted window height.
    y: u32,
    /// Supplies a nonzero extent contained by the submitted window width.
    width: u32,
    /// Supplies a nonzero extent contained by the submitted window height.
    height: u32,
    /// Marks exactly one submitted pane as the current input destination.
    focused: bool,
    /// False preserves and scales the last backing without requesting a frame.
    terminal_available: bool,
};

const Texture = struct {
    identity: u64,
    name: c.GLuint,
    bytes: usize,
    last_generation: u64,
};

const Backing = struct {
    id: PaneId,
    terminal: *howl_control.Terminal,
    texture: c.GLuint,
    framebuffer: c.GLuint,
    width: u32,
    height: u32,
    initialized: bool = false,
};

const Borrowed = struct {
    terminal: *howl_control.Terminal,
    frame: howl_control.Frame,
    pane: Pane,
};

const Vertex = extern struct { x: f32, y: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };

const Device = struct {
    allocator: std.mem.Allocator,
    display: c.EGLDisplay,
    context: c.EGLContext,
    surface: c.EGLSurface,
    window: *c.struct_wl_egl_window,
    mask_program: c.GLuint,
    copy_program: c.GLuint,
    buffer: c.GLuint,
    white: c.GLuint,
    core: howl_render.Renderer,
    textures: [texture_capacity]Texture = undefined,
    texture_count: u16 = 0,
    texture_bytes: usize = 0,
    backings: [workspace.max_panes]Backing = undefined,
    backing_count: u8 = 0,
    backing_bytes: usize = 0,
    size: Size,

    fn init(allocator: std.mem.Allocator, values: Init) StartError!Device {
        try validateInit(values);
        const window = c.wl_egl_window_create(
            values.surface,
            @intCast(values.size.width),
            @intCast(values.size.height),
        ) orelse return error.EglSurface;
        errdefer c.wl_egl_window_destroy(window);
        const display = c.eglGetDisplay(@ptrCast(values.display));
        if (display == c.EGL_NO_DISPLAY) return error.EglDisplay;
        if (c.eglInitialize(display, null, null) != c.EGL_TRUE) return error.EglInitialize;
        errdefer if (c.eglTerminate(display) != c.EGL_TRUE)
            @panic("EGL display rollback failed");
        if (c.eglBindAPI(c.EGL_OPENGL_ES_API) != c.EGL_TRUE) return error.EglContext;
        const attributes = [_]c.EGLint{
            c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
            c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES2_BIT,
            c.EGL_RED_SIZE,        8,
            c.EGL_GREEN_SIZE,      8,
            c.EGL_BLUE_SIZE,       8,
            c.EGL_NONE,
        };
        var config: c.EGLConfig = null;
        var count: c.EGLint = 0;
        if (c.eglChooseConfig(display, &attributes, &config, 1, &count) != c.EGL_TRUE or count != 1)
            return error.EglConfig;
        const context_attributes = [_]c.EGLint{
            c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE,
        };
        const context = c.eglCreateContext(display, config, c.EGL_NO_CONTEXT, &context_attributes);
        if (context == c.EGL_NO_CONTEXT) return error.EglContext;
        errdefer if (c.eglDestroyContext(display, context) != c.EGL_TRUE)
            @panic("EGL context rollback failed");
        const surface = c.eglCreateWindowSurface(display, config, @intFromPtr(window), null);
        if (surface == c.EGL_NO_SURFACE) return error.EglSurface;
        errdefer if (c.eglDestroySurface(display, surface) != c.EGL_TRUE)
            @panic("EGL surface rollback failed");
        if (c.eglMakeCurrent(display, surface, surface, context) != c.EGL_TRUE)
            return error.EglContext;
        errdefer if (c.eglMakeCurrent(
            display,
            c.EGL_NO_SURFACE,
            c.EGL_NO_SURFACE,
            c.EGL_NO_CONTEXT,
        ) != c.EGL_TRUE) @panic("EGL current-context rollback failed");
        const mask_program = try createProgram(.mask);
        errdefer c.glDeleteProgram(mask_program);
        const copy_program = try createProgram(.copy);
        errdefer c.glDeleteProgram(copy_program);
        var buffer: c.GLuint = 0;
        c.glGenBuffers(1, &buffer);
        if (buffer == 0 or c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        errdefer c.glDeleteBuffers(1, &buffer);
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        var white: c.GLuint = 0;
        c.glGenTextures(1, &white);
        if (white == 0) return error.Texture;
        errdefer c.glDeleteTextures(1, &white);
        const pixel = [_]u8{255};
        configureTexture(white);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, 1, 1, 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &pixel);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        var core = try howl_render.Renderer.init(allocator, .{
            .primary = values.font_paths[0],
            .fallbacks = values.font_paths[1..],
            .pixel_height = 18,
        });
        errdefer core.deinit();
        return .{
            .allocator = allocator,
            .display = display,
            .context = context,
            .surface = surface,
            .window = window,
            .mask_program = mask_program,
            .copy_program = copy_program,
            .buffer = buffer,
            .white = white,
            .core = core,
            .size = values.size,
        };
    }

    fn draw(self: *Device, work: Work) Error!void {
        var borrowed: [max_visible_panes]Borrowed = undefined;
        var borrowed_count: usize = 0;
        var failure: ?Error = null;
        self.drawBorrowed(work, &borrowed, &borrowed_count) catch |cause| {
            failure = cause;
        };
        releaseBorrowed(borrowed[0..borrowed_count]) catch |cause| {
            if (failure != null and failure.? != cause)
                @panic("frame release failed after a distinct render failure");
            failure = cause;
        };
        if (failure) |cause| return cause;
    }

    fn drawBorrowed(
        self: *Device,
        work: Work,
        borrowed: *[max_visible_panes]Borrowed,
        borrowed_count: *usize,
    ) Error!void {
        if (!std.meta.eql(self.size, work.size)) {
            c.wl_egl_window_resize(
                self.window,
                @intCast(work.size.width),
                @intCast(work.size.height),
                0,
                0,
            );
            self.size = work.size;
        }
        try self.reconcile(work.live[0..work.live_count], work.panes[0..work.pane_count]);
        for (work.panes[0..work.pane_count]) |pane| {
            const backing = self.findBacking(pane.id).?;
            const dirty = containsDirty(work.dirty[0..work.dirty_count], pane.terminal);
            if (!needsFrame(pane, backing.initialized, dirty)) continue;
            const frame = pane.terminal.borrowFrame() orelse {
                if (backing.initialized) continue;
                return error.FrameUnavailable;
            };
            borrowed[borrowed_count.*] = .{
                .terminal = pane.terminal,
                .frame = frame,
                .pane = pane,
            };
            borrowed_count.* += 1;
        }
        if (borrowed_count.* != 0) {
            var prepared_panes: [max_visible_panes]howl_render.Pane = undefined;
            for (borrowed[0..borrowed_count.*], 0..) |owned, index| {
                var complete = owned.frame.frame;
                // A pane backing is rebuilt as complete state; terminal damage
                // only bounds transport into a renderer that retains cell pixels.
                complete.damage.full = true;
                prepared_panes[index] = .{
                    .x = 0,
                    .y = 0,
                    .width = owned.pane.width,
                    .height = owned.pane.height,
                    .frame = complete,
                };
            }
            const prepared = try self.core.prepare(
                work.generation,
                work.size.width,
                work.size.height,
                prepared_panes[0..borrowed_count.*],
            );
            std.debug.assert(prepared.panes == borrowed_count.*);
        }
        var label_cells: [workspace.max_cols]howl_frame.Cell = undefined;
        for (work.label_cells[0..work.label_count], label_cells[0..work.label_count]) |source, *cell|
            cell.* = labelFrameCell(source);
        try self.core.prepareCells(work.generation, label_cells[0..work.label_count]);
        for (borrowed[0..borrowed_count.*]) |owned| {
            try self.drawFrame(work.generation, owned.pane, owned.frame.frame);
            self.findBacking(owned.pane.id).?.initialized = true;
        }
        c.glViewport(0, 0, @intCast(self.size.width), @intCast(self.size.height));
        clearColor(palette.background);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.copy_program);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.buffer);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        const white = howl_vt.Terminal.Rgb{ .r = 255, .g = 255, .b = 255 };
        try self.drawLabels(work);
        for (work.panes[0..work.pane_count]) |pane| {
            const backing = self.findBacking(pane.id).?;
            c.glUseProgram(self.copy_program);
            try self.quad(
                @intCast(pane.x),
                @intCast(pane.y),
                @intCast(pane.width),
                @intCast(pane.height),
                white,
                backing.texture,
                self.size,
                true,
            );
            if (pane.focused) {
                c.glUseProgram(self.mask_program);
                const focus = howl_vt.Terminal.Rgb{ .r = 142, .g = 192, .b = 124 };
                const thickness: u16 = @intCast(@min(2, @min(pane.width, pane.height)));
                try self.quad(
                    @intCast(pane.x),
                    @intCast(pane.y),
                    @intCast(pane.width),
                    thickness,
                    focus,
                    self.white,
                    self.size,
                    false,
                );
                try self.quad(
                    @intCast(pane.x),
                    @intCast(pane.y + pane.height - thickness),
                    @intCast(pane.width),
                    thickness,
                    focus,
                    self.white,
                    self.size,
                    false,
                );
                try self.quad(
                    @intCast(pane.x),
                    @intCast(pane.y),
                    thickness,
                    @intCast(pane.height),
                    focus,
                    self.white,
                    self.size,
                    false,
                );
                try self.quad(
                    @intCast(pane.x + pane.width - thickness),
                    @intCast(pane.y),
                    thickness,
                    @intCast(pane.height),
                    focus,
                    self.white,
                    self.size,
                    false,
                );
            }
        }
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        if (c.eglSwapBuffers(self.display, self.surface) != c.EGL_TRUE) return error.Swap;
    }

    fn drawFrame(
        self: *Device,
        generation: u64,
        pane: Pane,
        frame: howl_frame.TerminalFrame,
    ) Error!void {
        const backing = self.findBacking(pane.id).?;
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, backing.framebuffer);
        c.glViewport(0, 0, @intCast(pane.width), @intCast(pane.height));
        clearColor(palette.background);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.mask_program);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.buffer);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        const metrics = self.core.metrics();
        for (0..frame.rows) |row| for (0..frame.cols) |col| {
            const cell = frame.cells[row * frame.cols + col];
            const cursor = frame.cursor.visible and frame.cursor.row == row and frame.cursor.col == col;
            const foreground = if (cursor and frame.cursor.shape == .block)
                frame.cursor.text_color
            else
                cell.foreground;
            const background = if (cursor and frame.cursor.shape == .block)
                frame.cursor.color
            else
                cell.background;
            try self.quad(
                @intCast(col * metrics.cell_width),
                @intCast(row * metrics.cell_height),
                metrics.cell_width,
                metrics.cell_height,
                background,
                self.white,
                .{ .width = pane.width, .height = pane.height },
                false,
            );
            if (cell.codepoint == 0 or cell.x != 0 or cell.y != 0 or cell.invisible) continue;
            const glyphs = try self.core.preparedGlyphs(cell);
            for (glyphs.slice()) |glyph| {
                if (glyph.width == 0 or glyph.height == 0) continue;
                const texture_name = try self.texture(generation, glyph);
                try self.quad(
                    @as(i32, @intCast(col * metrics.cell_width)) + glyph.left + @divTrunc(glyph.x_offset, 64),
                    @as(i32, @intCast(row * metrics.cell_height)) + metrics.baseline -
                        glyph.top - @divTrunc(glyph.y_offset, 64),
                    glyph.width,
                    glyph.height,
                    foreground,
                    texture_name,
                    .{ .width = pane.width, .height = pane.height },
                    false,
                );
            }
        };
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
    }

    fn drawLabels(self: *Device, work: Work) Error!void {
        const metrics = self.core.metrics();
        c.glEnable(c.GL_SCISSOR_TEST);
        defer c.glDisable(c.GL_SCISSOR_TEST);
        c.glScissor(
            0,
            @intCast(self.size.height - work.label_height),
            @intCast(self.size.width),
            work.label_height,
        );
        c.glUseProgram(self.mask_program);
        for (work.label_cells[0..work.label_count], 0..) |source, col| {
            const bounds = labels.pixelBounds(
                self.size.width,
                work.label_count,
                @intCast(col),
            ) catch return error.InvalidPane;
            const colors = labelColors(source);
            try self.quad(
                @intCast(bounds.start),
                0,
                @intCast(bounds.end - bounds.start),
                work.label_height,
                colors.background,
                self.white,
                self.size,
                false,
            );
            if (source.codepoint == ' ' or bounds.end - bounds.start < metrics.cell_width) continue;
            const glyphs = try self.core.preparedGlyphs(labelFrameCell(source));
            for (glyphs.slice()) |glyph| {
                if (glyph.width == 0 or glyph.height == 0) continue;
                const texture_name = try self.texture(work.generation, glyph);
                try self.quad(
                    @as(i32, @intCast(bounds.start)) + glyph.left + @divTrunc(glyph.x_offset, 64),
                    @as(i32, metrics.baseline) - glyph.top - @divTrunc(glyph.y_offset, 64),
                    glyph.width,
                    glyph.height,
                    colors.foreground,
                    texture_name,
                    self.size,
                    false,
                );
            }
        }
    }

    fn reconcile(self: *Device, live: []const PaneId, panes: []const Pane) Error!void {
        var backing_index: u8 = 0;
        while (backing_index < self.backing_count) {
            if (containsPaneId(live, self.backings[backing_index].id)) {
                backing_index += 1;
            } else {
                self.removeBacking(backing_index);
            }
        }
        for (panes) |pane| {
            if (self.findBacking(pane.id)) |existing| {
                if (existing.terminal != pane.terminal) return error.InvalidPane;
                if (existing.width == pane.width and existing.height == pane.height) continue;
                if (!pane.terminal_available) continue;
                const old_bytes = backingBytes(existing.width, existing.height);
                const new_bytes = backingBytes(pane.width, pane.height);
                if (new_bytes > old_bytes and
                    new_bytes - old_bytes > max_backing_bytes - self.backing_bytes)
                    return error.BackingLimit;
                const replacement = try createBacking(pane);
                const old = existing.*;
                existing.* = replacement;
                self.backing_bytes -= old_bytes;
                self.backing_bytes += new_bytes;
                destroyBacking(old);
                continue;
            }
            if (self.backing_count == workspace.max_panes) return error.InvalidPane;
            const bytes = backingBytes(pane.width, pane.height);
            if (bytes > max_backing_bytes - self.backing_bytes) return error.BackingLimit;
            self.backings[self.backing_count] = try createBacking(pane);
            // A terminal that stopped before first visibility has no frame to
            // initialize this pane. Its cleared backing is the retained fact.
            self.backings[self.backing_count].initialized = !pane.terminal_available;
            self.backing_count += 1;
            self.backing_bytes += bytes;
        }
    }

    fn findBacking(self: *Device, id: PaneId) ?*Backing {
        for (self.backings[0..self.backing_count]) |*value|
            if (value.id == id) return value;
        return null;
    }

    fn removeBacking(self: *Device, index: u8) void {
        const old = self.backings[index];
        self.backing_bytes -= backingBytes(old.width, old.height);
        destroyBacking(old);
        self.backing_count -= 1;
        if (index != self.backing_count) self.backings[index] = self.backings[self.backing_count];
    }

    fn texture(self: *Device, generation: u64, glyph: howl_render.Glyph) Error!c.GLuint {
        for (self.textures[0..self.texture_count]) |*entry| {
            if (entry.identity != glyph.identity) continue;
            entry.last_generation = generation;
            return entry.name;
        }
        while (self.texture_count == texture_capacity or
            self.texture_bytes > texture_byte_capacity - glyph.pixels.len)
        {
            var victim: ?u16 = null;
            for (self.textures[0..self.texture_count], 0..) |entry, index| {
                if (entry.last_generation == generation) continue;
                if (victim == null or entry.last_generation < self.textures[victim.?].last_generation)
                    victim = @intCast(index);
            }
            const index = victim orelse return error.Texture;
            const removed = self.textures[index];
            c.glDeleteTextures(1, &removed.name);
            self.texture_bytes -= removed.bytes;
            self.texture_count -= 1;
            if (index != self.texture_count) self.textures[index] = self.textures[self.texture_count];
        }
        var name: c.GLuint = 0;
        c.glGenTextures(1, &name);
        if (name == 0) return error.Texture;
        errdefer c.glDeleteTextures(1, &name);
        configureTexture(name);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_ALPHA,
            glyph.width,
            glyph.height,
            0,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            glyph.pixels.ptr,
        );
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        self.textures[self.texture_count] = .{
            .identity = glyph.identity,
            .name = name,
            .bytes = glyph.pixels.len,
            .last_generation = generation,
        };
        self.texture_count += 1;
        self.texture_bytes += glyph.pixels.len;
        return name;
    }

    fn quad(
        _: *Device,
        x: i32,
        y: i32,
        width: u16,
        height: u16,
        color: howl_vt.Terminal.Rgb,
        texture_name: c.GLuint,
        extent: Size,
        flip_vertical: bool,
    ) Error!void {
        const left = pixelToNdc(x, extent.width);
        const right = pixelToNdc(x + width, extent.width);
        const top = -pixelToNdc(y, extent.height);
        const bottom = -pixelToNdc(y + height, extent.height);
        const red: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
        const green: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
        const blue: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;
        const top_v: f32 = if (flip_vertical) 1 else 0;
        const bottom_v: f32 = if (flip_vertical) 0 else 1;
        const vertices = [_]Vertex{
            .{ .x = left, .y = top, .u = 0, .v = top_v, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = bottom, .u = 0, .v = bottom_v, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = bottom_v, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = top, .u = 0, .v = top_v, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = bottom_v, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = top, .u = 1, .v = top_v, .r = red, .g = green, .b = blue, .a = 1 },
        };
        c.glBindTexture(c.GL_TEXTURE_2D, texture_name);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STREAM_DRAW);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(0));
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(2 * @sizeOf(f32)));
        c.glVertexAttribPointer(2, 4, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(4 * @sizeOf(f32)));
        c.glDrawArrays(c.GL_TRIANGLES, 0, vertices.len);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
    }

    fn deinit(self: *Device) Error!void {
        while (self.backing_count != 0) self.removeBacking(self.backing_count - 1);
        for (self.textures[0..self.texture_count]) |entry| c.glDeleteTextures(1, &entry.name);
        self.core.deinit();
        c.glDeleteTextures(1, &self.white);
        c.glDeleteBuffers(1, &self.buffer);
        c.glDeleteProgram(self.copy_program);
        c.glDeleteProgram(self.mask_program);
        var failed = c.glGetError() != c.GL_NO_ERROR;
        if (c.eglMakeCurrent(
            self.display,
            c.EGL_NO_SURFACE,
            c.EGL_NO_SURFACE,
            c.EGL_NO_CONTEXT,
        ) != c.EGL_TRUE) failed = true;
        if (c.eglDestroySurface(self.display, self.surface) != c.EGL_TRUE) failed = true;
        if (c.eglDestroyContext(self.display, self.context) != c.EGL_TRUE) failed = true;
        if (c.eglTerminate(self.display) != c.EGL_TRUE) failed = true;
        c.wl_egl_window_destroy(self.window);
        if (failed) return error.Cleanup;
    }
};

fn validateSize(size: Size) error{InvalidSize}!void {
    if (size.width == 0 or size.height == 0 or
        size.width > max_window_dimension or size.height > max_window_dimension or
        size.width > std.math.maxInt(c_int) or size.height > std.math.maxInt(c_int))
        return error.InvalidSize;
}

fn validateSubmission(
    size: Size,
    live: []const PaneId,
    panes: []const Pane,
    dirty: []const *howl_control.Terminal,
    label_cells: []const labels.Cell,
    label_height: u16,
) error{ InvalidSize, InvalidPane }!void {
    try validateSize(size);
    if (live.len == 0 or live.len > workspace.max_panes or panes.len == 0 or
        panes.len > max_visible_panes or dirty.len > workspace.max_panes or
        label_cells.len == 0 or label_cells.len > workspace.max_cols or
        label_cells.len > size.width or label_height == 0 or label_height >= size.height)
        return error.InvalidPane;
    for (label_cells) |cell| if (cell.codepoint == 0 or
        !std.unicode.utf8ValidCodepoint(cell.codepoint)) return error.InvalidPane;
    for (live, 0..) |id, index| {
        if (@intFromEnum(id) == 0 or containsPaneId(live[0..index], id)) return error.InvalidPane;
    }
    var bytes: usize = 0;
    var focused: u8 = 0;
    for (panes, 0..) |pane, index| {
        if (@intFromEnum(pane.id) == 0 or pane.width == 0 or pane.height == 0 or
            pane.x >= size.width or pane.y < label_height or pane.y >= size.height or
            pane.width > size.width - pane.x or pane.height > size.height - pane.y or
            !containsPaneId(live, pane.id))
            return error.InvalidPane;
        if (pane.focused) focused += 1;
        bytes = std.math.add(usize, bytes, backingBytes(pane.width, pane.height)) catch
            return error.InvalidPane;
        if (bytes > max_backing_bytes) return error.InvalidPane;
        for (panes[0..index]) |prior| {
            if (prior.id == pane.id or prior.terminal == pane.terminal or overlaps(prior, pane))
                return error.InvalidPane;
        }
    }
    if (focused != 1) return error.InvalidPane;
    for (dirty, 0..) |terminal, index| {
        if (!containsAvailableTerminal(panes, terminal) or
            containsDirty(dirty[0..index], terminal))
            return error.InvalidPane;
    }
}

fn containsPaneId(values: []const PaneId, id: PaneId) bool {
    for (values) |value| if (value == id) return true;
    return false;
}

fn containsTerminal(panes: []const Pane, terminal: *howl_control.Terminal) bool {
    for (panes) |pane| if (pane.terminal == terminal) return true;
    return false;
}

fn containsAvailableTerminal(panes: []const Pane, terminal: *howl_control.Terminal) bool {
    for (panes) |pane| if (pane.terminal == terminal) return pane.terminal_available;
    return false;
}

fn containsDirty(values: []const *howl_control.Terminal, terminal: *howl_control.Terminal) bool {
    for (values) |value| if (value == terminal) return true;
    return false;
}

fn needsFrame(pane: Pane, initialized: bool, dirty: bool) bool {
    return pane.terminal_available and (!initialized or dirty);
}

fn overlaps(a: Pane, b: Pane) bool {
    return a.x < b.x + b.width and b.x < a.x + a.width and
        a.y < b.y + b.height and b.y < a.y + a.height;
}

fn releaseBorrowed(values: []Borrowed) howl_control.FrameReleaseError!void {
    var failure: ?howl_control.FrameReleaseError = null;
    for (values) |value| {
        var frame = value.frame;
        value.terminal.releaseFrame(&frame) catch |cause| {
            if (failure != null and failure.? != cause)
                @panic("distinct frame release failures in one composition");
            failure = cause;
        };
    }
    if (failure) |cause| return cause;
}

fn validateInit(values: Init) error{ InvalidSize, InvalidFonts }!void {
    try validateSize(values.size);
    if (values.font_paths.len == 0) return error.InvalidFonts;
}

const Fragment = enum { mask, copy };

fn createProgram(fragment_kind: Fragment) Error!c.GLuint {
    const vertex_source: [:0]const u8 =
        \\attribute vec2 position;
        \\attribute vec2 texture_coordinate;
        \\attribute vec4 color;
        \\varying vec2 fragment_texture_coordinate;
        \\varying vec4 fragment_color;
        \\void main() {
        \\  gl_Position = vec4(position, 0.0, 1.0);
        \\  fragment_texture_coordinate = texture_coordinate;
        \\  fragment_color = color;
        \\}
    ;
    const mask_fragment: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D image;
        \\varying vec2 fragment_texture_coordinate;
        \\varying vec4 fragment_color;
        \\void main() {
        \\  float alpha = texture2D(image, fragment_texture_coordinate).a;
        \\  gl_FragColor = vec4(fragment_color.rgb, fragment_color.a * alpha);
        \\}
    ;
    const copy_fragment: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D image;
        \\varying vec2 fragment_texture_coordinate;
        \\varying vec4 fragment_color;
        \\void main() {
        \\  gl_FragColor = texture2D(image, fragment_texture_coordinate) * fragment_color;
        \\}
    ;
    const fragment_source = switch (fragment_kind) {
        .mask => mask_fragment,
        .copy => copy_fragment,
    };
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_source);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment);
    const program = c.glCreateProgram();
    if (program == 0) return error.Shader;
    errdefer c.glDeleteProgram(program);
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glBindAttribLocation(program, 0, "position");
    c.glBindAttribLocation(program, 1, "texture_coordinate");
    c.glBindAttribLocation(program, 2, "color");
    c.glLinkProgram(program);
    var linked: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &linked);
    if (linked != c.GL_TRUE) return error.Shader;
    c.glUseProgram(program);
    const image = c.glGetUniformLocation(program, "image");
    if (image < 0) return error.Shader;
    c.glUniform1i(image, 0);
    if (c.glGetError() != c.GL_NO_ERROR) return error.Shader;
    return program;
}

fn createBacking(pane: Pane) Error!Backing {
    var texture: c.GLuint = 0;
    c.glGenTextures(1, &texture);
    if (texture == 0) return error.Texture;
    errdefer c.glDeleteTextures(1, &texture);
    c.glBindTexture(c.GL_TEXTURE_2D, texture);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(pane.width),
        @intCast(pane.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        null,
    );
    if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
    var framebuffer: c.GLuint = 0;
    c.glGenFramebuffers(1, &framebuffer);
    if (framebuffer == 0) return error.Draw;
    errdefer c.glDeleteFramebuffers(1, &framebuffer);
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, framebuffer);
    c.glFramebufferTexture2D(
        c.GL_FRAMEBUFFER,
        c.GL_COLOR_ATTACHMENT0,
        c.GL_TEXTURE_2D,
        texture,
        0,
    );
    if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE)
        return error.Draw;
    c.glViewport(0, 0, @intCast(pane.width), @intCast(pane.height));
    clearColor(palette.background);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
    return .{
        .id = pane.id,
        .terminal = pane.terminal,
        .texture = texture,
        .framebuffer = framebuffer,
        .width = pane.width,
        .height = pane.height,
    };
}

fn destroyBacking(backing: Backing) void {
    c.glDeleteFramebuffers(1, &backing.framebuffer);
    c.glDeleteTextures(1, &backing.texture);
}

fn backingBytes(width: u32, height: u32) usize {
    return @as(usize, width) * height * 4;
}

fn labelFrameCell(source: labels.Cell) howl_frame.Cell {
    return .{
        .codepoint = source.codepoint,
        .combining_len = 0,
        .combining = @splat(0),
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .foreground = palette.foreground,
        .background = palette.background,
        .underline_color = palette.foreground,
        .font = 0,
        .baseline = .normal,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .invisible = false,
        .underline = false,
        .strikethrough = false,
        .underline_style = .straight,
        .link_id = 0,
    };
}

fn labelColors(source: labels.Cell) struct {
    foreground: howl_vt.Terminal.Rgb,
    background: howl_vt.Terminal.Rgb,
} {
    return .{
        .foreground = if (source.availability == .unavailable)
            palette.unavailable
        else if (source.active)
            palette.active_foreground
        else
            palette.foreground,
        .background = if (source.active) palette.active_background else palette.inactive_background,
    };
}

fn clearColor(color: howl_vt.Terminal.Rgb) void {
    c.glClearColor(
        @as(f32, @floatFromInt(color.r)) / 255.0,
        @as(f32, @floatFromInt(color.g)) / 255.0,
        @as(f32, @floatFromInt(color.b)) / 255.0,
        1.0,
    );
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) Error!c.GLuint {
    const shader = c.glCreateShader(kind);
    if (shader == 0) return error.Shader;
    errdefer c.glDeleteShader(shader);
    const pointer: [*c]const c.GLchar = source.ptr;
    c.glShaderSource(shader, 1, &pointer, null);
    c.glCompileShader(shader);
    var compiled: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &compiled);
    if (compiled != c.GL_TRUE) return error.Shader;
    return shader;
}

fn configureTexture(name: c.GLuint) void {
    c.glBindTexture(c.GL_TEXTURE_2D, name);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
}

fn pixelToNdc(value: i32, extent: u32) f32 {
    return @as(f32, @floatFromInt(value)) * 2.0 / @as(f32, @floatFromInt(extent)) - 1.0;
}

fn closeSignal(fd: c_int) bool {
    const result = c.close(fd);
    return result == 0 or std.posix.errno(result) == .INTR;
}

/// Owns one render thread, one replaceable pending frame, and completion wake.
pub const Render = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    condition: std.Io.Condition = .init,
    thread: std.Thread,
    init_values: Init,
    mailbox: Mailbox = .{},
    stopping: bool = false,
    started: bool = false,
    startup_failure: ?StartError = null,
    failure: ?Error = null,
    submitted_generation: u64 = 0,
    completed_generation: u64 = 0,
    metrics_value: @import("howl_text").Metrics = undefined,
    signal_fd: c_int,

    pub fn start(allocator: std.mem.Allocator, io: std.Io, values: Init) StartError!*Render {
        try validateInit(values);
        const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (signal_fd < 0) return error.Signal;
        errdefer if (!closeSignal(signal_fd)) @panic("render eventfd rollback failed");
        const self = try allocator.create(Render);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .thread = undefined,
            .init_values = values,
            .signal_fd = signal_fd,
        };
        self.thread = try .spawn(.{}, threadMain, .{self});
        self.mutex.lockUncancelable(io);
        while (!self.started) self.condition.waitUncancelable(io, &self.mutex);
        const failure = self.startup_failure;
        self.mutex.unlock(io);
        if (failure) |cause| {
            self.thread.join();
            return cause;
        }
        return self;
    }

    /// Returns immutable text metrics after successful render-thread startup.
    pub fn metrics(self: *const Render) howl_text.Metrics {
        return self.metrics_value;
    }
    /// Exposes the nonblocking completion eventfd polled by the window loop.
    pub fn signalFd(self: *const Render) c_int {
        return self.signal_fd;
    }

    /// Coalesces one complete visible layout and terminal-change set. Frame
    /// borrowing and release occur later on the render thread only.
    pub fn submit(
        self: *Render,
        generation: u64,
        size: Size,
        live: []const PaneId,
        panes: []const Pane,
        dirty: []const *howl_control.Terminal,
        label_cells: []const labels.Cell,
        label_height: u16,
    ) Error!void {
        try validateSubmission(size, live, panes, dirty, label_cells, label_height);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.Stopping;
        if (generation == 0 or generation <= self.submitted_generation)
            return error.StaleGeneration;
        var work = Work{
            .generation = generation,
            .size = size,
            .pane_count = @intCast(panes.len),
            .live_count = @intCast(live.len),
            .dirty_count = @intCast(dirty.len),
            .label_count = @intCast(label_cells.len),
            .label_height = label_height,
        };
        @memcpy(work.panes[0..panes.len], panes);
        @memcpy(work.live[0..live.len], live);
        @memcpy(work.dirty[0..dirty.len], dirty);
        @memcpy(work.label_cells[0..label_cells.len], label_cells);
        self.mailbox.admit(work);
        self.submitted_generation = generation;
        self.condition.signal(self.io);
    }

    /// Wait until the render thread has consumed one admitted generation.
    /// This is the terminal-retirement boundary; it never borrows a frame.
    pub fn quiesce(self: *Render, generation: u64) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.completed_generation < generation and self.failure == null and !self.stopping)
            self.condition.waitUncancelable(self.io, &self.mutex);
        if (self.failure) |failure| return failure;
        if (self.completed_generation < generation) return error.Stopping;
    }

    /// Drains completion wake and returns the newest swapped generation.
    pub fn completed(self: *Render) Error!u64 {
        var value: u64 = 0;
        const count = c.read(self.signal_fd, &value, @sizeOf(u64));
        if (count != @sizeOf(u64) and !(count < 0 and std.posix.errno(count) == .AGAIN))
            return error.Signal;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        return self.completed_generation;
    }

    /// Stops pending metadata work and destroys GLES/EGL in owner order.
    pub fn deinit(self: *Render) Error!void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
        self.thread.join();
        self.mutex.lockUncancelable(self.io);
        self.mailbox.pending = null;
        const failure = self.failure;
        self.mutex.unlock(self.io);
        const close_failed = !closeSignal(self.signal_fd);
        const allocator = self.allocator;
        allocator.destroy(self);
        if (close_failed) {
            if (failure != null) @panic("render eventfd close failed after render failure");
            return error.Signal;
        }
        if (failure) |cause| return cause;
    }

    fn threadMain(self: *Render) void {
        var device = Device.init(self.allocator, self.init_values) catch |failure| {
            self.finishStart(failure);
            return;
        };
        self.mutex.lockUncancelable(self.io);
        self.metrics_value = device.core.metrics();
        self.started = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (self.mailbox.empty() and !self.stopping)
                self.condition.waitUncancelable(self.io, &self.mutex);
            if (self.stopping) {
                self.mailbox.pending = null;
                self.mutex.unlock(self.io);
                break;
            }
            const pending = self.mailbox.takePending();
            self.mutex.unlock(self.io);
            const work = pending orelse continue;
            device.draw(work) catch |failure| {
                self.failAndDrain(failure);
                break;
            };
            self.mutex.lockUncancelable(self.io);
            self.completed_generation = work.generation;
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            self.signal();
        }
        device.deinit() catch |failure| self.storeFailure(failure);
    }

    fn finishStart(self: *Render, failure: StartError) void {
        self.mutex.lockUncancelable(self.io);
        self.startup_failure = failure;
        self.started = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
    }

    fn storeFailure(self: *Render, failure: Error) void {
        self.mutex.lockUncancelable(self.io);
        if (self.failure == null) self.failure = failure;
        self.condition.broadcast(self.io);
        self.mutex.unlock(self.io);
    }

    fn failAndDrain(self: *Render, failure: Error) void {
        self.storeFailure(failure);
        self.mutex.lockUncancelable(self.io);
        self.mailbox.pending = null;
        self.mutex.unlock(self.io);
        self.signal();
    }

    fn signal(self: *Render) void {
        const value: u64 = 1;
        const count = c.write(self.signal_fd, &value, @sizeOf(u64));
        if (count != @sizeOf(u64) and !(count < 0 and std.posix.errno(count) == .AGAIN)) {
            self.mutex.lockUncancelable(self.io);
            if (self.failure == null) self.failure = error.Signal;
            self.mutex.unlock(self.io);
        }
    }
};

test "mailbox keeps newest layout and unions only still-visible terminal dirtiness" {
    const first_terminal: *howl_control.Terminal = @ptrFromInt(16);
    const second_terminal: *howl_control.Terminal = @ptrFromInt(32);
    const third_terminal: *howl_control.Terminal = @ptrFromInt(48);
    var mailbox = Mailbox{};
    mailbox.admit(testWork(1, &.{
        testPane(1, first_terminal, 0, 50),
        testPane(2, second_terminal, 50, 50),
    }, &.{first_terminal}));
    mailbox.admit(testWork(2, &.{testPane(3, third_terminal, 0, 100)}, &.{third_terminal}));
    const switched = mailbox.takePending().?;
    try std.testing.expectEqual(@as(u64, 2), switched.generation);
    try std.testing.expectEqual(@as(u8, 1), switched.dirty_count);
    try std.testing.expect(switched.dirty[0] == third_terminal);

    mailbox.admit(testWork(3, &.{
        testPane(1, first_terminal, 0, 50),
        testPane(2, second_terminal, 50, 50),
    }, &.{first_terminal}));
    mailbox.admit(testWork(4, &.{
        testPane(1, first_terminal, 0, 50),
        testPane(2, second_terminal, 50, 50),
    }, &.{second_terminal}));
    const merged = mailbox.takePending().?;
    try std.testing.expectEqual(@as(u64, 4), merged.generation);
    try std.testing.expectEqual(@as(u8, 2), merged.dirty_count);
    try std.testing.expect(containsDirty(merged.dirty[0..2], first_terminal));
    try std.testing.expect(containsDirty(merged.dirty[0..2], second_terminal));

    mailbox.admit(testWork(5, &.{testPane(1, first_terminal, 0, 100)}, &.{first_terminal}));
    var stopped = testPane(1, first_terminal, 0, 100);
    stopped.terminal_available = false;
    mailbox.admit(testWork(6, &.{stopped}, &.{}));
    const unavailable = mailbox.takePending().?;
    try std.testing.expectEqual(@as(u8, 0), unavailable.dirty_count);
}

test "unavailable pane retains its backing without requesting another frame" {
    const terminal: *howl_control.Terminal = @ptrFromInt(16);
    var pane = testPane(1, terminal, 0, 100);
    try std.testing.expect(needsFrame(pane, false, false));
    try std.testing.expect(needsFrame(pane, true, true));

    pane.terminal_available = false;
    try std.testing.expect(!needsFrame(pane, false, false));
    try std.testing.expect(!needsFrame(pane, true, true));
}

test "public start rejects empty fonts and invalid size before native work" {
    const invalid_display: *c.struct_wl_display = undefined;
    const invalid_surface: *c.struct_wl_surface = undefined;
    try std.testing.expectError(error.InvalidFonts, Render.start(
        std.testing.allocator,
        std.testing.io,
        .{
            .display = invalid_display,
            .surface = invalid_surface,
            .size = .{ .width = 1, .height = 1 },
            .font_paths = &.{},
        },
    ));
    try std.testing.expectError(error.InvalidSize, Render.start(
        std.testing.allocator,
        std.testing.io,
        .{
            .display = invalid_display,
            .surface = invalid_surface,
            .size = .{ .width = 0, .height = 1 },
            .font_paths = &.{"unused"},
        },
    ));
    try std.testing.expectError(error.InvalidSize, Render.start(
        std.testing.allocator,
        std.testing.io,
        .{
            .display = invalid_display,
            .surface = invalid_surface,
            .size = .{ .width = @as(u32, @intCast(std.math.maxInt(c_int))) + 1, .height = 1 },
            .font_paths = &.{"unused"},
        },
    ));
}

test "failed render owner rejects late bounded metadata submission" {
    var render = Render{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .thread = undefined,
        .init_values = undefined,
        .started = true,
        .failure = error.Draw,
        .signal_fd = -1,
    };
    const terminal: *howl_control.Terminal = @ptrFromInt(16);
    try std.testing.expectError(
        error.Draw,
        render.submit(1, .{ .width = 100, .height = 100 }, &.{@as(PaneId, @enumFromInt(1))}, &.{
            testPane(1, terminal, 0, 100),
        }, &.{terminal}, &test_label_cells, 10),
    );
    try std.testing.expect(render.mailbox.empty());
    try std.testing.expectEqual(@as(u64, 0), render.submitted_generation);
}

test "terminal retirement quiescence reports completed and failed render facts" {
    var render = Render{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .thread = undefined,
        .init_values = undefined,
        .started = true,
        .completed_generation = 7,
        .signal_fd = -1,
    };
    try render.quiesce(7);
    render.failure = error.Draw;
    try std.testing.expectError(error.Draw, render.quiesce(8));
}

test "shutdown joins a dead failed render owner with pending metadata" {
    const terminal: *howl_control.Terminal = @ptrFromInt(16);
    const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (signal_fd < 0) return error.Signal;
    const render = try std.testing.allocator.create(Render);
    render.* = .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .thread = try .spawn(.{}, finishedTestThread, .{}),
        .init_values = undefined,
        .started = true,
        .failure = error.Draw,
        .signal_fd = signal_fd,
    };
    render.mailbox.admit(testWork(1, &.{testPane(1, terminal, 0, 100)}, &.{terminal}));
    try std.testing.expectError(error.Draw, render.deinit());
}

fn finishedTestThread() void {}

test "render-owned release returns every frame before terminal shutdown" {
    const first = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 2, .rows = 1 },
        .{},
    );
    errdefer first.deinit();
    const second = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 2, .rows = 1 },
        .{},
    );
    errdefer second.deinit();
    var borrowed = [_]Borrowed{
        .{ .terminal = first, .frame = first.borrowFrame().?, .pane = testPane(1, first, 0, 50) },
        .{ .terminal = second, .frame = second.borrowFrame().?, .pane = testPane(2, second, 50, 50) },
    };
    try releaseBorrowed(&borrowed);
    first.deinit();
    second.deinit();
}

test "public submission rejects invalid composition before mailbox mutation" {
    const invalid_display: *c.struct_wl_display = undefined;
    const invalid_surface: *c.struct_wl_surface = undefined;
    var render = Render{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .thread = undefined,
        .init_values = undefined,
        .started = true,
        .signal_fd = -1,
    };
    const terminal: *howl_control.Terminal = @ptrFromInt(16);
    try std.testing.expectError(error.InvalidSize, render.submit(
        1,
        .{ .width = 0, .height = 1 },
        &.{@as(PaneId, @enumFromInt(1))},
        &.{testPane(1, terminal, 0, 1)},
        &.{terminal},
        &test_label_cells,
        10,
    ));
    try std.testing.expectError(error.InvalidPane, render.submit(
        1,
        .{ .width = 100, .height = 100 },
        &.{ @as(PaneId, @enumFromInt(1)), @enumFromInt(2) },
        &.{
            testPane(1, terminal, 0, 60),
            testPane(2, @ptrFromInt(32), 50, 50),
        },
        &.{terminal},
        &test_label_cells,
        10,
    ));
    var overlap = testPane(1, terminal, 0, 100);
    overlap.y = 0;
    try std.testing.expectError(error.InvalidPane, render.submit(
        1,
        .{ .width = 100, .height = 100 },
        &.{@as(PaneId, @enumFromInt(1))},
        &.{overlap},
        &.{},
        &test_label_cells,
        10,
    ));
    var unavailable = testPane(1, terminal, 0, 100);
    unavailable.terminal_available = false;
    try std.testing.expectError(error.InvalidPane, render.submit(
        1,
        .{ .width = 100, .height = 100 },
        &.{@as(PaneId, @enumFromInt(1))},
        &.{unavailable},
        &.{terminal},
        &test_label_cells,
        10,
    ));
    try std.testing.expect(render.mailbox.empty());
    try std.testing.expectError(error.InvalidSize, validateInit(.{
        .display = invalid_display,
        .surface = invalid_surface,
        .size = .{ .width = @as(u32, std.math.maxInt(c_int)) + 1, .height = 1 },
        .font_paths = &.{"unused"},
    }));
}

test "renderer preserves full stable pane identity and bounded live roster" {
    const terminal: *howl_control.Terminal = @ptrFromInt(16);
    const largest: PaneId = @enumFromInt(std.math.maxInt(u64));
    var pane = testPane(1, terminal, 0, 100);
    pane.id = largest;
    var live: [workspace.max_panes]PaneId = undefined;
    for (&live, 1..) |*id, value| id.* = @enumFromInt(value);
    live[live.len - 1] = largest;
    try validateSubmission(.{ .width = 100, .height = 100 }, &live, &.{pane}, &.{}, &test_label_cells, 10);
    live[1] = live[0];
    try std.testing.expectError(
        error.InvalidPane,
        validateSubmission(.{ .width = 100, .height = 100 }, &live, &.{pane}, &.{}, &test_label_cells, 10),
    );
}

fn testPane(
    id: u64,
    terminal: *howl_control.Terminal,
    x: u32,
    width: u32,
) Pane {
    return .{
        .id = @enumFromInt(id),
        .terminal = terminal,
        .x = x,
        .y = 10,
        .width = width,
        .height = 90,
        .focused = id == 1,
        .terminal_available = true,
    };
}

const test_label_cells = [_]labels.Cell{.{ .codepoint = 't', .active = true }};

test "label palette keeps active inactive and unavailable facts distinct" {
    const active = labelColors(.{ .codepoint = 'a', .active = true });
    const inactive = labelColors(.{ .codepoint = 'i' });
    const unavailable = labelColors(.{ .codepoint = '!', .availability = .unavailable });
    try std.testing.expectEqual(palette.active_foreground, active.foreground);
    try std.testing.expectEqual(palette.active_background, active.background);
    try std.testing.expectEqual(palette.foreground, inactive.foreground);
    try std.testing.expectEqual(palette.inactive_background, inactive.background);
    try std.testing.expectEqual(palette.unavailable, unavailable.foreground);
}

fn testWork(
    generation: u64,
    panes: []const Pane,
    dirty: []const *howl_control.Terminal,
) Work {
    var work = Work{
        .generation = generation,
        .size = .{ .width = 100, .height = 100 },
        .pane_count = @intCast(panes.len),
        .live_count = @intCast(panes.len),
        .dirty_count = @intCast(dirty.len),
        .label_count = test_label_cells.len,
        .label_height = 10,
    };
    @memcpy(work.panes[0..panes.len], panes);
    for (panes, work.live[0..panes.len]) |pane, *id| id.* = pane.id;
    @memcpy(work.dirty[0..dirty.len], dirty);
    @memcpy(work.label_cells[0..test_label_cells.len], &test_label_cells);
    return work;
}
