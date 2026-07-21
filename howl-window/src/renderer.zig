//! Owns one concrete EGL/GLES render thread and its coalesced terminal frame.

const std = @import("std");
const howl_control = @import("howl_control");
const howl_frame = @import("howl_frame");
const howl_render = @import("howl_render");
const howl_text = @import("howl_text");
const howl_vt = @import("howl_vt");
const c = @import("native.zig").c;

const texture_capacity = howl_render.cache_capacity;
const texture_byte_capacity = howl_render.cache_byte_capacity;

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
    MailboxFull,
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
    terminal: *howl_control.Terminal,
    frame: howl_control.Frame,
};

// With one two-slot frame publisher, the render thread can own either active
// plus pending, or superseded plus pending, never all three. The second form
// exists only after active release makes a newer publication borrowable before
// the render thread takes the prior pending work.
const Mailbox = struct {
    pending: ?Work = null,
    superseded: ?Work = null,

    fn admit(self: *Mailbox, active: bool, work: *Work) error{MailboxFull}!void {
        if (self.pending) |pending| {
            if (active or self.superseded != null) return error.MailboxFull;
            self.superseded = pending;
        }
        self.pending = work.*;
        work.* = undefined;
    }

    fn takeSuperseded(self: *Mailbox) ?Work {
        const work = self.superseded;
        self.superseded = null;
        return work;
    }

    fn takePending(self: *Mailbox) ?Work {
        const work = self.pending;
        self.pending = null;
        return work;
    }

    fn empty(self: *const Mailbox) bool {
        return self.pending == null and self.superseded == null;
    }
};

const Texture = struct {
    identity: u64,
    name: c.GLuint,
    bytes: usize,
    last_generation: u64,
};

const Vertex = extern struct { x: f32, y: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };

const Device = struct {
    allocator: std.mem.Allocator,
    display: c.EGLDisplay,
    context: c.EGLContext,
    surface: c.EGLSurface,
    window: *c.struct_wl_egl_window,
    program: c.GLuint,
    buffer: c.GLuint,
    white: c.GLuint,
    core: howl_render.Renderer,
    textures: [texture_capacity]Texture = undefined,
    texture_count: u16 = 0,
    texture_bytes: usize = 0,
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
        const program = try createProgram();
        errdefer c.glDeleteProgram(program);
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
            .program = program,
            .buffer = buffer,
            .white = white,
            .core = core,
            .size = values.size,
        };
    }

    fn draw(self: *Device, work: Work) Error!void {
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
        const pane = howl_render.Pane{
            .x = 0,
            .y = 0,
            .width = self.size.width,
            .height = self.size.height,
            .frame = work.frame.frame,
        };
        const prepared = try self.core.prepare(
            work.generation,
            self.size.width,
            self.size.height,
            &.{pane},
        );
        std.debug.assert(prepared.panes == 1);
        c.glViewport(0, 0, @intCast(self.size.width), @intCast(self.size.height));
        c.glClearColor(0.035, 0.039, 0.045, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.buffer);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        const frame = work.frame.frame;
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
            );
            if (cell.codepoint == 0 or cell.x != 0 or cell.y != 0 or cell.invisible) continue;
            const glyphs = try self.core.preparedGlyphs(cell);
            for (glyphs.slice()) |glyph| {
                if (glyph.width == 0 or glyph.height == 0) continue;
                const texture_name = try self.texture(work.generation, glyph);
                try self.quad(
                    @as(i32, @intCast(col * metrics.cell_width)) + glyph.left + @divTrunc(glyph.x_offset, 64),
                    @as(i32, @intCast(row * metrics.cell_height)) + metrics.baseline -
                        glyph.top - @divTrunc(glyph.y_offset, 64),
                    glyph.width,
                    glyph.height,
                    foreground,
                    texture_name,
                );
            }
        };
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        if (c.eglSwapBuffers(self.display, self.surface) != c.EGL_TRUE) return error.Swap;
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
        self: *Device,
        x: i32,
        y: i32,
        width: u16,
        height: u16,
        color: howl_vt.Terminal.Rgb,
        texture_name: c.GLuint,
    ) Error!void {
        const left = pixelToNdc(x, self.size.width);
        const right = pixelToNdc(x + width, self.size.width);
        const top = -pixelToNdc(y, self.size.height);
        const bottom = -pixelToNdc(y + height, self.size.height);
        const red: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
        const green: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
        const blue: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;
        const vertices = [_]Vertex{
            .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = bottom, .u = 0, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = top, .u = 1, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
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
        for (self.textures[0..self.texture_count]) |entry| c.glDeleteTextures(1, &entry.name);
        self.core.deinit();
        c.glDeleteTextures(1, &self.white);
        c.glDeleteBuffers(1, &self.buffer);
        c.glDeleteProgram(self.program);
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
        size.width > std.math.maxInt(c_int) or size.height > std.math.maxInt(c_int))
        return error.InvalidSize;
}

fn validateInit(values: Init) error{ InvalidSize, InvalidFonts }!void {
    try validateSize(values.size);
    if (values.font_paths.len == 0) return error.InvalidFonts;
}

fn createProgram() Error!c.GLuint {
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
    const fragment_source: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D mask;
        \\varying vec2 fragment_texture_coordinate;
        \\varying vec4 fragment_color;
        \\void main() {
        \\  float alpha = texture2D(mask, fragment_texture_coordinate).a;
        \\  gl_FragColor = vec4(fragment_color.rgb, fragment_color.a * alpha);
        \\}
    ;
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
    c.glUniform1i(c.glGetUniformLocation(program, "mask"), 0);
    return program;
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
    active: bool = false,
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

    /// Transfers one valid borrowed frame into bounded render-thread ownership.
    /// Every rejection retains caller ownership; acceptance transfers it until
    /// render completion, supersession, or defensive shutdown drainage.
    pub fn submit(
        self: *Render,
        generation: u64,
        size: Size,
        terminal: *howl_control.Terminal,
        frame: *howl_control.Frame,
    ) Error!void {
        try validateSize(size);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.Stopping;
        if (generation == 0 or generation <= self.submitted_generation)
            return error.StaleGeneration;
        var work = Work{ .generation = generation, .size = size, .terminal = terminal, .frame = frame.* };
        try self.mailbox.admit(self.active, &work);
        frame.* = undefined;
        self.submitted_generation = generation;
        self.condition.signal(self.io);
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

    /// Stops, releases pending work, and destroys GLES/EGL in owner order.
    pub fn deinit(self: *Render) Error!void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
        self.thread.join();
        self.mutex.lockUncancelable(self.io);
        var superseded = self.mailbox.takeSuperseded();
        var pending = self.mailbox.takePending();
        var failure = self.failure;
        self.mutex.unlock(self.io);
        releaseOwned(&superseded) catch |cause| if (failure == null) {
            failure = cause;
        };
        releaseOwned(&pending) catch |cause| if (failure == null) {
            failure = cause;
        };
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
                var superseded = self.mailbox.takeSuperseded();
                var pending = self.mailbox.takePending();
                self.mutex.unlock(self.io);
                releaseOwned(&superseded) catch |failure| self.storeFailure(failure);
                releaseOwned(&pending) catch |failure| self.storeFailure(failure);
                break;
            }
            var superseded = self.mailbox.takeSuperseded();
            if (superseded != null) {
                self.mutex.unlock(self.io);
                releaseOwned(&superseded) catch |failure| {
                    self.failAndDrain(failure);
                    break;
                };
                continue;
            }
            const pending = self.mailbox.takePending();
            self.active = pending != null;
            self.mutex.unlock(self.io);
            const work = pending orelse continue;
            device.draw(work) catch |failure| {
                self.finishActive();
                var active: ?Work = work;
                releaseOwned(&active) catch |release_failure| {
                    self.failAndDrain(release_failure);
                    break;
                };
                self.failAndDrain(failure);
                break;
            };
            self.finishActive();
            var active: ?Work = work;
            releaseOwned(&active) catch |failure| {
                self.failAndDrain(failure);
                break;
            };
            self.mutex.lockUncancelable(self.io);
            self.completed_generation = work.generation;
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
        self.mutex.unlock(self.io);
    }

    fn failAndDrain(self: *Render, failure: Error) void {
        self.storeFailure(failure);
        self.mutex.lockUncancelable(self.io);
        var superseded = self.mailbox.takeSuperseded();
        var pending = self.mailbox.takePending();
        self.mutex.unlock(self.io);
        releaseOwned(&superseded) catch |cause| self.storeFailure(cause);
        releaseOwned(&pending) catch |cause| self.storeFailure(cause);
        self.signal();
    }

    fn finishActive(self: *Render) void {
        self.mutex.lockUncancelable(self.io);
        std.debug.assert(self.active);
        self.active = false;
        self.mutex.unlock(self.io);
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

fn releaseOwned(work: *?Work) howl_control.FrameReleaseError!void {
    if (work.*) |owned_value| {
        var owned = owned_value;
        work.* = null;
        try owned.terminal.releaseFrame(&owned.frame);
    }
}

fn testWork(generation: u64) Work {
    return .{
        .generation = generation,
        .size = .{ .width = 1, .height = 1 },
        .terminal = undefined,
        .frame = undefined,
    };
}

test "two-slot mailbox coalesces only after active ownership is absent" {
    var mailbox = Mailbox{};
    var first = testWork(1);
    try mailbox.admit(false, &first);
    const active = mailbox.takePending().?;
    try std.testing.expectEqual(@as(u64, 1), active.generation);

    var second = testWork(2);
    try mailbox.admit(false, &second);
    var third = testWork(3);
    try mailbox.admit(false, &third);
    try std.testing.expectEqual(@as(u64, 2), mailbox.superseded.?.generation);
    try std.testing.expectEqual(@as(u64, 3), mailbox.pending.?.generation);

    var impossible = testWork(4);
    try std.testing.expectError(error.MailboxFull, mailbox.admit(false, &impossible));
    try std.testing.expectEqual(@as(u64, 4), impossible.generation);

    var active_mailbox = Mailbox{};
    var pending = testWork(5);
    try active_mailbox.admit(true, &pending);
    var blocked = testWork(6);
    try std.testing.expectError(error.MailboxFull, active_mailbox.admit(true, &blocked));
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

test "failed render owner rejects late submission without taking its frame" {
    var render = Render{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .thread = undefined,
        .init_values = undefined,
        .started = true,
        .failure = error.Draw,
        .signal_fd = -1,
    };
    var frame: howl_control.Frame = undefined;
    try std.testing.expectError(
        error.Draw,
        render.submit(1, .{ .width = 1, .height = 1 }, undefined, &frame),
    );
    try std.testing.expect(render.mailbox.empty());
    try std.testing.expectEqual(@as(u64, 0), render.submitted_generation);
}

test "shutdown drains a dead render thread frame before terminal destruction" {
    const terminal = try howl_control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 2, .rows = 1 },
        .{},
    );
    var frame = terminal.borrowFrame().?;
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
    var work = Work{
        .generation = 1,
        .size = .{ .width = 1, .height = 1 },
        .terminal = terminal,
        .frame = frame,
    };
    try render.mailbox.admit(false, &work);
    frame = undefined;
    try std.testing.expectError(error.Draw, render.deinit());
    try std.testing.expect(terminal.borrowFrame() == null);
    terminal.deinit();
}

fn finishedTestThread() void {}

test "public submission rejects invalid size before frame transfer" {
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
    var frame: howl_control.Frame = undefined;
    try std.testing.expectError(error.InvalidSize, render.submit(
        1,
        .{ .width = 0, .height = 1 },
        undefined,
        &frame,
    ));
    try std.testing.expect(render.mailbox.empty());
    try std.testing.expectError(error.InvalidSize, validateInit(.{
        .display = invalid_display,
        .surface = invalid_surface,
        .size = .{ .width = @as(u32, std.math.maxInt(c_int)) + 1, .height = 1 },
        .font_paths = &.{"unused"},
    }));
}
