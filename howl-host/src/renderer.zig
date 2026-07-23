//! Owns one concrete EGL/GLES render thread for one retained terminal grid.
//!
//! Submission copies caller-owned visual state into one bounded pending slot.
//! The render thread takes that slot before shaping, rasterization, texture
//! upload, drawing, and swap, so no terminal borrow or caller storage crosses
//! the thread boundary. New submissions replace only pending work.

const std = @import("std");
const render = @import("howl_render");
const terminal = render.terminal;
const text = render.terminal_text;
const viewport = @import("viewport.zig");

const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("errno.h");
    @cInclude("sys/eventfd.h");
    @cInclude("unistd.h");
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
});

// Bounds one admitted terminal dimension before C integer narrowing.
const max_dimension: u16 = 512;
// Bounds retained visual cells for the initial one-terminal owner.
const max_cells: usize = 512 * 256;
// Bounds resident glyph masks independently of terminal dimensions.
const texture_capacity: usize = 2_048;
// Bounds resident alpha bytes shared by every terminal glyph identity.
const texture_byte_capacity: usize = 16 * 1024 * 1024;

/// Supplies one nonzero concrete EGL window extent.
pub const PixelSize = struct {
    /// Sets width before checked C integer narrowing.
    width: u32,
    /// Sets height before checked C integer narrowing.
    height: u32,
};

/// Supplies borrowed Wayland and font construction facts through startup.
pub const Init = struct {
    /// Borrows the connected display through renderer shutdown.
    display: *c.struct_wl_display,
    /// Borrows the live surface through renderer shutdown.
    surface: *c.struct_wl_surface,
    /// Sets the initial nonzero surface extent.
    size: PixelSize,
    /// Sizes each retained snapshot for the initial nonzero row count.
    rows: u16,
    /// Sizes each retained snapshot for the initial nonzero column count.
    cols: u16,
    /// Borrows exact font configurations through synchronous startup only.
    fonts: []const text.FontConfig,
};

/// Borrows one complete immutable executable-retained visual grid for submit.
pub const Submission = struct {
    /// Is strictly increasing and nonzero for accepted work.
    generation: u64,
    /// Sets the current nonzero terminal row count.
    rows: u16,
    /// Sets the current nonzero terminal column count.
    cols: u16,
    /// Borrows exactly `rows * cols` cells for the duration of submit.
    cells: []const terminal.Cell,
    /// Borrows exactly one DEC geometry fact per visible row for submit.
    row_geometry: []const terminal.LineGeometry,
    /// Copies the current cursor overlay.
    cursor: terminal.Cursor,
    /// Sets the current nonzero presentation extent.
    size: PixelSize,
    /// Copies optional host-owned scrollbar pixels for this visual state.
    scrollbar: ?viewport.Scrollbar = null,
};

/// Reports exact construction, admission, preparation, or device failure.
pub const Error = std.mem.Allocator.Error || std.Thread.SpawnError ||
    text.FontMapInitError || text.PrepareError || text.RasterError || error{
    InvalidSubmission,
    StaleGeneration,
    Stopping,
    EglDisplay,
    EglInitialize,
    EglConfig,
    EglContext,
    EglSurface,
    Shader,
    Texture,
    CacheFull,
    UnsupportedPresentation,
    Draw,
    Swap,
    Signal,
    Cleanup,
};

const Snapshot = struct {
    allocator: std.mem.Allocator,
    cells: []terminal.Cell,
    row_geometry: []terminal.LineGeometry,
    generation: u64 = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    cursor: terminal.Cursor = undefined,
    size: PixelSize = undefined,
    scrollbar: ?viewport.Scrollbar = null,

    fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!Snapshot {
        const cells = try allocator.alloc(terminal.Cell, @as(usize, rows) * cols);
        errdefer allocator.free(cells);
        const row_geometry = try allocator.alloc(terminal.LineGeometry, rows);
        return .{ .allocator = allocator, .cells = cells, .row_geometry = row_geometry };
    }

    fn ensureCapacity(self: *Snapshot, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        const required_cells = @as(usize, rows) * cols;
        if (required_cells <= self.cells.len and rows <= self.row_geometry.len) return;
        const cells = if (required_cells > self.cells.len)
            try self.allocator.alloc(terminal.Cell, required_cells)
        else
            null;
        errdefer if (cells) |owned| self.allocator.free(owned);
        const geometry = if (rows > self.row_geometry.len)
            try self.allocator.alloc(terminal.LineGeometry, rows)
        else
            null;
        if (cells) |owned| {
            self.allocator.free(self.cells);
            self.cells = owned;
        }
        if (geometry) |owned| {
            self.allocator.free(self.row_geometry);
            self.row_geometry = owned;
        }
        self.generation = 0;
        self.rows = 0;
        self.cols = 0;
    }

    fn deinit(self: *Snapshot) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.row_geometry);
        self.* = undefined;
    }

    fn write(self: *Snapshot, submission: Submission) void {
        const count = @as(usize, submission.rows) * submission.cols;
        std.debug.assert(count <= self.cells.len);
        @memcpy(self.cells[0..count], submission.cells);
        @memcpy(self.row_geometry[0..submission.rows], submission.row_geometry);
        self.generation = submission.generation;
        self.rows = submission.rows;
        self.cols = submission.cols;
        self.cursor = submission.cursor;
        self.size = submission.size;
        self.scrollbar = submission.scrollbar;
    }

    fn view(self: *const Snapshot) Submission {
        const count = @as(usize, self.rows) * self.cols;
        return .{
            .generation = self.generation,
            .rows = self.rows,
            .cols = self.cols,
            .cells = self.cells[0..count],
            .row_geometry = self.row_geometry[0..self.rows],
            .cursor = self.cursor,
            .size = self.size,
            .scrollbar = self.scrollbar,
        };
    }
};

const Mailbox = struct {
    pending: ?*Snapshot = null,
    active: ?*Snapshot = null,
    free_first: ?*Snapshot = null,
    free_second: ?*Snapshot = null,

    fn release(self: *Mailbox, slot: *Snapshot) void {
        if (self.free_first == null) {
            self.free_first = slot;
        } else {
            std.debug.assert(self.free_second == null);
            self.free_second = slot;
        }
    }

    fn writable(self: *Mailbox) ?*Snapshot {
        if (self.free_second) |slot| {
            self.free_second = null;
            return slot;
        }
        const slot = self.free_first;
        self.free_first = null;
        return slot;
    }

    fn write(self: *Mailbox, submission: Submission) std.mem.Allocator.Error!void {
        if (self.writable()) |slot| {
            errdefer self.release(slot);
            try slot.ensureCapacity(submission.rows, submission.cols);
            slot.write(submission);
            if (self.admit(slot)) |replaced| self.release(replaced);
            return;
        }
        const slot = self.pending.?;
        try slot.ensureCapacity(submission.rows, submission.cols);
        slot.write(submission);
    }

    fn admit(self: *Mailbox, slot: *Snapshot) ?*Snapshot {
        const replaced = self.pending;
        self.pending = slot;
        return replaced;
    }

    fn take(self: *Mailbox) ?*Snapshot {
        std.debug.assert(self.active == null);
        const slot = self.pending orelse return null;
        self.pending = null;
        self.active = slot;
        return slot;
    }

    fn complete(self: *Mailbox) void {
        const slot = self.active.?;
        self.active = null;
        self.release(slot);
    }
};

const Texture = struct {
    key: text.GlyphKey,
    name: c.GLuint,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    bytes: usize,
    used: u64,
};

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const Device = struct {
    allocator: std.mem.Allocator,
    display: c.EGLDisplay,
    context: c.EGLContext,
    surface: c.EGLSurface,
    window: *c.struct_wl_egl_window,
    program: c.GLuint,
    buffer: c.GLuint,
    white: c.GLuint,
    fonts: text.FontMap,
    metrics: text.CellMetrics,
    textures: [texture_capacity]Texture = undefined,
    texture_count: usize = 0,
    texture_bytes: usize = 0,
    size: PixelSize,

    fn init(allocator: std.mem.Allocator, values: Init) Error!Device {
        try validateSize(values.size);
        var fonts = try text.FontMap.init(allocator, values.fonts);
        errdefer fonts.deinit();
        const default_key = text.FontKey{ .slot = 0, .style = .normal };
        const metrics = fonts.cellMetrics(default_key) orelse return error.InvalidSubmission;
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
        var config_count: c.EGLint = 0;
        if (c.eglChooseConfig(display, &attributes, &config, 1, &config_count) != c.EGL_TRUE or
            config_count != 1) return error.EglConfig;
        const context_attributes = [_]c.EGLint{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE };
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
        var white: c.GLuint = 0;
        c.glGenTextures(1, &white);
        if (white == 0) return error.Texture;
        errdefer c.glDeleteTextures(1, &white);
        const pixel = [_]u8{255};
        configureTexture(white);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, 1, 1, 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &pixel);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        return .{
            .allocator = allocator,
            .display = display,
            .context = context,
            .surface = surface,
            .window = window,
            .program = program,
            .buffer = buffer,
            .white = white,
            .fonts = fonts,
            .metrics = metrics,
            .size = values.size,
        };
    }

    fn draw(self: *Device, snapshot: *const Snapshot) Error!void {
        const work = snapshot.view();
        if (!std.meta.eql(self.size, work.size)) {
            try validateSize(work.size);
            c.wl_egl_window_resize(self.window, @intCast(work.size.width), @intCast(work.size.height), 0, 0);
            self.size = work.size;
        }
        c.glViewport(0, 0, @intCast(self.size.width), @intCast(self.size.height));
        const clear_component: f32 = @as(f32, @floatFromInt(0x28)) / 255.0;
        c.glClearColor(clear_component, clear_component, clear_component, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.buffer);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        for (0..work.rows) |row| try self.drawRow(work, @intCast(row));
        try self.drawCursor(work);
        try self.drawScrollbar(work.scrollbar);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        if (c.eglSwapBuffers(self.display, self.surface) != c.EGL_TRUE) return error.Swap;
    }

    fn drawScrollbar(self: *Device, value: ?viewport.Scrollbar) Error!void {
        const scrollbar = value orelse return;
        try self.quad(
            @intCast(scrollbar.track.x),
            @intCast(scrollbar.track.y),
            scrollbar.track.width,
            @intCast(scrollbar.track.height),
            .{ .r = 0x50, .g = 0x49, .b = 0x45 },
            self.white,
        );
        try self.quad(
            @intCast(scrollbar.thumb.x),
            @intCast(scrollbar.thumb.y),
            scrollbar.thumb.width,
            @intCast(scrollbar.thumb.height),
            .{ .r = 0x92, .g = 0x83, .b = 0x74 },
            self.white,
        );
    }

    fn drawRow(self: *Device, work: Submission, row: u16) Error!void {
        const start = @as(usize, row) * work.cols;
        const cells = work.cells[start..][0..work.cols];
        try validateRowPresentation(work.row_geometry[row], cells);
        for (cells, 0..) |cell, col| {
            const cursor_block = work.cursor.visible and work.cursor.shape == .block and
                work.cursor.row == row and work.cursor.col == col;
            try self.quad(
                @as(i32, @intCast(col)) * self.metrics.width_px,
                @as(i32, row) * self.metrics.height_px,
                self.metrics.width_px,
                self.metrics.height_px,
                cellFill(cell, work.cursor, cursor_block),
                self.white,
            );
        }
        var at: u16 = 0;
        while (at < work.cols) {
            var prepared = try text.prepareNextRun(self.allocator, &self.fonts, .{
                .cells = cells,
                .affected_start = at,
                .affected_end = work.cols - 1,
                .geometry = work.row_geometry[row],
                .metrics = self.metrics,
            }, at);
            defer prepared.deinit();
            try self.drawPrepared(work.generation, row, cells, work.cursor, prepared);
            std.debug.assert(prepared.end_cell > at);
            at = prepared.end_cell;
        }
    }

    fn drawPrepared(
        self: *Device,
        generation: u64,
        row: u16,
        cells: []const terminal.Cell,
        cursor: terminal.Cursor,
        prepared: text.PreparedRun,
    ) Error!void {
        switch (prepared.glyphs) {
            .none => {},
            .generated => |glyph| try self.drawGlyph(generation, row, cells, cursor, prepared, glyph),
            .native => |owned| for (owned.values) |glyph|
                try self.drawGlyph(generation, row, cells, cursor, prepared, glyph),
        }
    }

    fn drawGlyph(
        self: *Device,
        generation: u64,
        row: u16,
        cells: []const terminal.Cell,
        cursor: terminal.Cursor,
        prepared: text.PreparedRun,
        glyph: text.PositionedGlyph,
    ) Error!void {
        std.debug.assert(glyph.source_start < glyph.source_end and glyph.source_end <= cells.len);
        const cached = try self.texture(generation, glyph.key);
        if (cached.width == 0 or cached.height == 0) return;
        std.debug.assert(prepared.baseline == .normal);
        const x = glyphPixelX(
            prepared.first_cell,
            self.metrics.width_px,
            cached.left,
            glyph.x_26_6,
        );
        const y = @as(i32, row) * self.metrics.height_px + self.metrics.baseline_px -
            cached.top - @divTrunc(glyph.y_26_6, 64);
        c.glEnable(c.GL_SCISSOR_TEST);
        defer c.glDisable(c.GL_SCISSOR_TEST);
        var col = glyph.source_start;
        while (col < glyph.source_end) : (col += 1) {
            c.glScissor(
                @as(c_int, col) * self.metrics.width_px,
                0,
                self.metrics.width_px,
                @intCast(self.size.height),
            );
            const cursor_block = cursor.visible and cursor.shape == .block and
                cursor.row == row and cursor.col == col;
            try self.quad(
                x,
                y,
                cached.width,
                cached.height,
                glyphColor(cells[col], cursor, cursor_block),
                cached.name,
            );
        }
    }

    fn drawCursor(self: *Device, work: Submission) Error!void {
        if (!work.cursor.visible or work.cursor.shape == .block) return;
        std.debug.assert(work.cursor.row < work.rows and work.cursor.col < work.cols);
        const width: u16 = switch (work.cursor.shape) {
            .bar => @max(1, self.metrics.width_px / 8),
            else => self.metrics.width_px,
        };
        const height: u16 = switch (work.cursor.shape) {
            .underline => @max(1, self.metrics.height_px / 8),
            .none => return,
            else => self.metrics.height_px,
        };
        const y_offset = if (work.cursor.shape == .underline) self.metrics.height_px - height else 0;
        try self.quad(
            @as(i32, work.cursor.col) * self.metrics.width_px,
            @as(i32, work.cursor.row) * self.metrics.height_px + y_offset,
            width,
            height,
            work.cursor.color,
            self.white,
        );
    }

    fn texture(self: *Device, generation: u64, key: text.GlyphKey) Error!*Texture {
        for (self.textures[0..self.texture_count]) |*entry| {
            if (!std.meta.eql(entry.key, key)) continue;
            entry.used = generation;
            return entry;
        }
        var raster = try text.rasterizeGlyph(self.allocator, &self.fonts, key);
        defer raster.deinit();
        if (raster.pixels.len > texture_byte_capacity) return error.CacheFull;
        while (self.texture_count == texture_capacity or
            raster.pixels.len > texture_byte_capacity - self.texture_bytes)
        {
            const victim = self.oldestTexture(generation) orelse return error.CacheFull;
            self.removeTexture(victim);
        }
        var name: c.GLuint = 0;
        if (raster.width != 0 and raster.height != 0) {
            c.glGenTextures(1, &name);
            if (name == 0) return error.Texture;
            errdefer c.glDeleteTextures(1, &name);
            configureTexture(name);
            c.glTexImage2D(
                c.GL_TEXTURE_2D,
                0,
                c.GL_ALPHA,
                raster.width,
                raster.height,
                0,
                c.GL_ALPHA,
                c.GL_UNSIGNED_BYTE,
                raster.pixels.ptr,
            );
            if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        }
        const entry = &self.textures[self.texture_count];
        entry.* = .{
            .key = key,
            .name = name,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
            .bytes = raster.pixels.len,
            .used = generation,
        };
        self.texture_count += 1;
        self.texture_bytes += raster.pixels.len;
        return entry;
    }

    fn oldestTexture(self: *const Device, generation: u64) ?usize {
        var oldest: ?usize = null;
        for (self.textures[0..self.texture_count], 0..) |entry, index| {
            if (entry.used == generation) continue;
            if (oldest == null or entry.used < self.textures[oldest.?].used) oldest = index;
        }
        return oldest;
    }

    fn removeTexture(self: *Device, index: usize) void {
        const removed = self.textures[index];
        c.glDeleteTextures(1, &removed.name);
        self.texture_bytes -= removed.bytes;
        self.texture_count -= 1;
        if (index != self.texture_count) self.textures[index] = self.textures[self.texture_count];
    }

    fn quad(
        self: *Device,
        x: i32,
        y: i32,
        width: u16,
        height: u16,
        color: terminal.Rgb,
        texture_name: c.GLuint,
    ) Error!void {
        if (width == 0 or height == 0) return;
        const left = pixelToNdc(x, self.size.width);
        const right = pixelToNdc(x + width, self.size.width);
        const top = -pixelToNdc(y, self.size.height);
        const bottom = -pixelToNdc(y + height, self.size.height);
        const red = @as(f32, @floatFromInt(color.r)) / 255.0;
        const green = @as(f32, @floatFromInt(color.g)) / 255.0;
        const blue = @as(f32, @floatFromInt(color.b)) / 255.0;
        const vertices = [_]Vertex{
            .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = bottom, .u = 0, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = top, .u = 1, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
            .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
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
        while (self.texture_count != 0) self.removeTexture(self.texture_count - 1);
        self.fonts.deinit();
        c.glDeleteTextures(1, &self.white);
        c.glDeleteBuffers(1, &self.buffer);
        c.glDeleteProgram(self.program);
        var failed = c.glGetError() != c.GL_NO_ERROR;
        if (c.eglMakeCurrent(self.display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT) != c.EGL_TRUE)
            failed = true;
        if (c.eglDestroySurface(self.display, self.surface) != c.EGL_TRUE) failed = true;
        if (c.eglDestroyContext(self.display, self.context) != c.EGL_TRUE) failed = true;
        if (c.eglTerminate(self.display) != c.EGL_TRUE) failed = true;
        c.wl_egl_window_destroy(self.window);
        self.* = undefined;
        if (failed) return error.Cleanup;
    }
};

/// Owns two bounded visual snapshots, one render thread, fonts, and GLES state.
pub const Renderer = struct {
    /// Retains the caller allocator through renderer cleanup.
    allocator: std.mem.Allocator,
    /// Retains the process I/O implementation used by mutexes and conditions.
    io: std.Io,
    /// Serializes bounded snapshot admission and completion facts.
    mutex: std.Io.Mutex = .init,
    /// Wakes the renderer for work and startup/shutdown transitions.
    condition: std.Io.Condition = .init,
    /// Owns the sole EGL/GLES device thread until deinit joins it.
    thread: std.Thread,
    /// Signals coalesced draw completion or failure to the Wayland loop.
    signal_fd: c_int,
    /// Borrows native startup values only until `start` returns.
    init_values: Init,
    /// Owns exactly two independently growable immutable snapshots.
    slots: [2]Snapshot,
    /// Tracks free, pending, and active snapshot ownership.
    mailbox: Mailbox,
    /// Revokes new work and asks the render thread to exit.
    stopping: bool = false,
    /// Reports completion of synchronous device construction.
    started: bool = false,
    /// Retains exact device construction failure until `start` observes it.
    startup_failure: ?Error = null,
    /// Retains the first draw or cleanup failure.
    failure: ?Error = null,
    /// Identifies the newest accepted generation.
    submitted: u64 = 0,
    /// Identifies the newest swapped generation.
    completed: u64 = 0,
    /// Copies immutable cell metrics established during startup.
    metrics_value: text.CellMetrics = undefined,

    /// Allocates two geometry-sized snapshots and starts the sole EGL/GLES owner.
    pub fn start(allocator: std.mem.Allocator, io: std.Io, values: Init) Error!*Renderer {
        try validateInit(values);
        const self = try allocator.create(Renderer);
        errdefer allocator.destroy(self);
        const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (signal_fd < 0) return error.Signal;
        errdefer closeSignal(signal_fd);
        var first = try Snapshot.init(allocator, values.rows, values.cols);
        var first_owned = true;
        errdefer if (first_owned) first.deinit();
        var second = try Snapshot.init(allocator, values.rows, values.cols);
        var second_owned = true;
        errdefer if (second_owned) second.deinit();
        self.* = .{
            .allocator = allocator,
            .io = io,
            .thread = undefined,
            .signal_fd = signal_fd,
            .init_values = values,
            .slots = .{ first, second },
            .mailbox = .{
                .free_first = &self.slots[0],
                .free_second = &self.slots[1],
            },
        };
        first_owned = false;
        second_owned = false;
        var snapshots_owned_by_thread_owner = true;
        errdefer if (snapshots_owned_by_thread_owner) {
            self.slots[1].deinit();
            self.slots[0].deinit();
        };
        self.thread = try .spawn(.{}, threadMain, .{self});
        snapshots_owned_by_thread_owner = false;
        self.mutex.lockUncancelable(io);
        while (!self.started) self.condition.waitUncancelable(io, &self.mutex);
        const failure = self.startup_failure;
        self.init_values.fonts = &.{};
        self.mutex.unlock(io);
        if (failure) |cause| {
            self.thread.join();
            self.slots[1].deinit();
            self.slots[0].deinit();
            return cause;
        }
        return self;
    }

    /// Copies and coalesces one complete visual state without waiting for draw.
    pub fn submit(self: *Renderer, submission: Submission) Error!void {
        try validateSubmission(submission);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.Stopping;
        if (submission.generation <= self.submitted) return error.StaleGeneration;
        try self.mailbox.write(submission);
        self.submitted = submission.generation;
        self.condition.signal(self.io);
    }

    /// Returns the immutable cell metrics established during synchronous startup.
    pub fn metrics(self: *const Renderer) text.CellMetrics {
        return self.metrics_value;
    }

    /// Exposes the pollable completion/failure descriptor until deinit.
    pub fn signalFd(self: *const Renderer) c_int {
        return self.signal_fd;
    }

    /// Drains coalesced completion signals and reports the newest swapped generation.
    pub fn completedGeneration(self: *Renderer) Error!u64 {
        try drainSignal(self.signal_fd);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        return self.completed;
    }

    /// Revokes submission, joins the thread, and releases every owner.
    pub fn deinit(self: *Renderer) Error!void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.condition.broadcast(self.io);
        self.mutex.unlock(self.io);
        self.thread.join();
        const failure = self.failure;
        self.slots[1].deinit();
        self.slots[0].deinit();
        closeSignal(self.signal_fd);
        const allocator = self.allocator;
        allocator.destroy(self);
        if (failure) |cause| return cause;
    }

    fn threadMain(self: *Renderer) void {
        var device = Device.init(self.allocator, self.init_values) catch |failure| {
            self.mutex.lockUncancelable(self.io);
            self.startup_failure = failure;
            self.started = true;
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            return;
        };
        self.mutex.lockUncancelable(self.io);
        self.metrics_value = device.metrics;
        self.started = true;
        self.condition.broadcast(self.io);
        self.mutex.unlock(self.io);

        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (self.mailbox.pending == null and !self.stopping)
                self.condition.waitUncancelable(self.io, &self.mutex);
            if (self.stopping) {
                self.mutex.unlock(self.io);
                break;
            }
            const slot = self.mailbox.take().?;
            self.mutex.unlock(self.io);

            device.draw(slot) catch |failure| {
                self.mutex.lockUncancelable(self.io);
                self.failure = failure;
                self.mailbox.complete();
                self.condition.broadcast(self.io);
                self.mutex.unlock(self.io);
                signal(self.signal_fd);
                break;
            };
            self.mutex.lockUncancelable(self.io);
            self.completed = slot.generation;
            self.mailbox.complete();
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            signal(self.signal_fd);
        }
        device.deinit() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            if (self.failure) |prior| {
                if (prior != failure) @panic("device cleanup failed after distinct render failure");
            } else {
                self.failure = failure;
            }
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            signal(self.signal_fd);
        };
    }
};

fn validateInit(values: Init) error{ InvalidSubmission, MissingDefaultConfiguration }!void {
    try validateSize(values.size);
    if (values.rows == 0 or values.cols == 0 or values.rows > max_dimension or
        values.cols > max_dimension or @as(usize, values.rows) * values.cols > max_cells)
        return error.InvalidSubmission;
    if (values.fonts.len == 0) return error.MissingDefaultConfiguration;
}

fn validateSize(size: PixelSize) error{InvalidSubmission}!void {
    if (size.width == 0 or size.height == 0 or
        size.width > std.math.maxInt(c_int) or size.height > std.math.maxInt(c_int))
        return error.InvalidSubmission;
}

fn validateSubmission(value: Submission) error{InvalidSubmission}!void {
    try validateSize(value.size);
    if (value.generation == 0 or value.rows == 0 or value.cols == 0 or
        value.rows > max_dimension or value.cols > max_dimension)
        return error.InvalidSubmission;
    const count = @as(usize, value.rows) * value.cols;
    if (count > max_cells or value.cells.len != count or value.row_geometry.len != value.rows)
        return error.InvalidSubmission;
    if (value.cursor.visible and
        (value.cursor.row >= value.rows or value.cursor.col >= value.cols))
        return error.InvalidSubmission;
    if (value.scrollbar) |scrollbar| {
        if (!validRect(scrollbar.track, value.size) or
            !validRect(scrollbar.thumb, value.size) or
            scrollbar.thumb.x != scrollbar.track.x or
            scrollbar.thumb.width != scrollbar.track.width or
            scrollbar.thumb.y < scrollbar.track.y or
            @as(u64, scrollbar.thumb.y) + scrollbar.thumb.height >
                @as(u64, scrollbar.track.y) + scrollbar.track.height or
            scrollbar.history_count == 0 or scrollbar.offset > scrollbar.history_count)
            return error.InvalidSubmission;
    }
}

fn validRect(rect: viewport.Rect, size: PixelSize) bool {
    return rect.width != 0 and rect.height != 0 and
        @as(u64, rect.x) + rect.width <= size.width and
        @as(u64, rect.y) + rect.height <= size.height;
}

fn validateRowPresentation(
    geometry: terminal.LineGeometry,
    cells: []const terminal.Cell,
) error{UnsupportedPresentation}!void {
    if (geometry != .single_width) return error.UnsupportedPresentation;
    for (cells) |cell| if (cell.baseline != .normal)
        return error.UnsupportedPresentation;
}

fn signal(fd: c_int) void {
    const value: u64 = 1;
    while (true) {
        const count = c.write(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64) or (count < 0 and std.posix.errno(count) == .AGAIN)) return;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        @panic("render completion signal failed");
    }
}

fn drainSignal(fd: c_int) error{Signal}!void {
    while (true) {
        var value: u64 = 0;
        const count = c.read(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) return;
        return error.Signal;
    }
}

fn closeSignal(fd: c_int) void {
    const result = c.close(fd);
    if (result != 0 and std.posix.errno(result) != .INTR)
        @panic("render completion descriptor close failed");
}

fn createProgram() Error!c.GLuint {
    const vertex_source: [:0]const u8 =
        \\attribute vec2 position;
        \\attribute vec2 texture_coordinate;
        \\attribute vec4 color;
        \\varying vec2 texture_coordinate_out;
        \\varying vec4 color_out;
        \\void main() {
        \\  gl_Position = vec4(position, 0.0, 1.0);
        \\  texture_coordinate_out = texture_coordinate;
        \\  color_out = color;
        \\}
    ;
    const fragment_source: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D image;
        \\varying vec2 texture_coordinate_out;
        \\varying vec4 color_out;
        \\void main() {
        \\  float alpha = texture2D(image, texture_coordinate_out).a;
        \\  gl_FragColor = vec4(color_out.rgb, color_out.a * alpha);
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
    const image = c.glGetUniformLocation(program, "image");
    if (image < 0) return error.Shader;
    c.glUniform1i(image, 0);
    if (c.glGetError() != c.GL_NO_ERROR) return error.Shader;
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

fn glyphPixelX(run_start: u16, cell_width: u16, raster_left: i16, shaped_x_26_6: i32) i32 {
    return @as(i32, run_start) * cell_width + raster_left + @divTrunc(shaped_x_26_6, 64);
}

fn cellFill(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.color else cell.background;
}

fn glyphColor(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.text_color else cell.foreground;
}

test "mailbox replaces only pending work while active ownership remains exact" {
    var slots = [_]Snapshot{
        try Snapshot.init(std.testing.allocator, 1, 1),
        try Snapshot.init(std.testing.allocator, 1, 1),
    };
    defer for (&slots) |*slot| slot.deinit();
    var mailbox = Mailbox{};
    mailbox.release(&slots[0]);
    mailbox.release(&slots[1]);
    const first = mailbox.writable().?;
    try std.testing.expect(mailbox.admit(first) == null);
    const second = mailbox.writable().?;
    const replaced = mailbox.admit(second).?;
    try std.testing.expect(replaced == first);
    mailbox.release(replaced);
    try std.testing.expect(mailbox.take() == second);
    try std.testing.expect(mailbox.active == second);
    const pending = mailbox.writable().?;
    try std.testing.expect(mailbox.admit(pending) == null);
    try std.testing.expect(mailbox.writable() == null);
    mailbox.complete();
    try std.testing.expect(mailbox.active == null);
    try std.testing.expect(mailbox.pending == first);
    try std.testing.expect(mailbox.writable() == second);
}

test "mailbox growth failure preserves every slot owner and pending work" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var slots = [_]Snapshot{
        try Snapshot.init(failing.allocator(), 1, 1),
        try Snapshot.init(failing.allocator(), 1, 1),
    };
    defer for (&slots) |*slot| slot.deinit();
    var mailbox = Mailbox{};
    mailbox.release(&slots[0]);
    mailbox.release(&slots[1]);
    const cells = [_]terminal.Cell{
        testCell('a'), testCell('b'), testCell('c'),
        testCell('d'), testCell('e'), testCell('f'),
        testCell('g'), testCell('h'), testCell('i'),
    };
    const geometry = [_]terminal.LineGeometry{
        .single_width, .single_width, .single_width,
    };

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, mailbox.write(.{
        .generation = 1,
        .rows = 2,
        .cols = 2,
        .cells = cells[0..4],
        .row_geometry = geometry[0..2],
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 20 },
    }));
    try std.testing.expect(mailbox.pending == null);
    try std.testing.expect(mailbox.active == null);
    try std.testing.expect(mailbox.free_first == &slots[0]);
    try std.testing.expect(mailbox.free_second == &slots[1]);

    failing.fail_index = std.math.maxInt(usize);
    try mailbox.write(.{
        .generation = 2,
        .rows = 2,
        .cols = 2,
        .cells = cells[0..4],
        .row_geometry = geometry[0..2],
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 20 },
    });
    try std.testing.expect(mailbox.pending == &slots[1]);
    try std.testing.expect(mailbox.take() == &slots[1]);
    try mailbox.write(.{
        .generation = 3,
        .rows = 1,
        .cols = 1,
        .cells = cells[0..1],
        .row_geometry = geometry[0..1],
        .cursor = testCursor(),
        .size = .{ .width = 10, .height = 10 },
    });
    const pending = mailbox.pending.?;
    const pending_generation = pending.generation;
    const pending_rows = pending.rows;
    const pending_cols = pending.cols;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, mailbox.write(.{
        .generation = 4,
        .rows = 3,
        .cols = 3,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 30, .height = 30 },
    }));
    try std.testing.expect(mailbox.active == &slots[1]);
    try std.testing.expect(mailbox.pending == pending);
    try std.testing.expect(mailbox.free_first == null);
    try std.testing.expect(mailbox.free_second == null);
    try std.testing.expectEqual(pending_generation, pending.generation);
    try std.testing.expectEqual(pending_rows, pending.rows);
    try std.testing.expectEqual(pending_cols, pending.cols);

    failing.fail_index = std.math.maxInt(usize);
    try mailbox.write(.{
        .generation = 5,
        .rows = 3,
        .cols = 3,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 30, .height = 30 },
    });
    try std.testing.expect(mailbox.active == &slots[1]);
    try std.testing.expect(mailbox.pending == pending);
    try std.testing.expectEqual(@as(u64, 5), pending.generation);
}

test "snapshot copy has no caller lifetime and preserves newest identity" {
    var snapshot = try Snapshot.init(std.testing.allocator, 1, 2);
    defer snapshot.deinit();
    var cells = [_]terminal.Cell{ testCell('a'), testCell('b') };
    const geometry = [_]terminal.LineGeometry{.single_width};
    const bar = viewport.scrollbar(
        .{ .history_count = 20, .offset = 4, .rows = 1 },
        20,
        10,
        10,
        10,
    ).?;
    snapshot.write(.{
        .generation = 7,
        .rows = 1,
        .cols = 2,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 10 },
        .scrollbar = bar,
    });
    cells[0].codepoint = 'z';
    const copy = snapshot.view();
    try std.testing.expectEqual(@as(u21, 'a'), copy.cells[0].codepoint);
    try std.testing.expectEqual(@as(u64, 7), copy.generation);
    try std.testing.expectEqual(bar, copy.scrollbar.?);
}

test "snapshot growth is transactional and unchanged geometry allocates nothing" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var snapshot = try Snapshot.init(failing.allocator(), 1, 2);
    defer snapshot.deinit();
    snapshot.generation = 9;
    snapshot.rows = 1;
    snapshot.cols = 2;
    const allocation_count = failing.alloc_index;
    try snapshot.ensureCapacity(1, 2);
    try std.testing.expectEqual(allocation_count, failing.alloc_index);

    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, snapshot.ensureCapacity(3, 4));
    try std.testing.expectEqual(@as(usize, 2), snapshot.cells.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.row_geometry.len);
    try std.testing.expectEqual(@as(u64, 9), snapshot.generation);
    try std.testing.expectEqual(@as(u16, 1), snapshot.rows);
    try std.testing.expectEqual(@as(u16, 2), snapshot.cols);

    var row_growth = try Snapshot.init(std.testing.allocator, 1, 4);
    defer row_growth.deinit();
    const cells_before = row_growth.cells.ptr;
    try row_growth.ensureCapacity(2, 2);
    try std.testing.expect(cells_before == row_growth.cells.ptr);
    try std.testing.expectEqual(@as(usize, 4), row_growth.cells.len);
    try std.testing.expectEqual(@as(usize, 2), row_growth.row_geometry.len);
}

test "submission rejects hostile bounds before snapshot mutation" {
    var snapshot = try Snapshot.init(std.testing.allocator, 1, 1);
    defer snapshot.deinit();
    snapshot.generation = 19;
    const cell = testCell('x');
    const geometry = [_]terminal.LineGeometry{.single_width};
    try std.testing.expectError(error.InvalidSubmission, validateSubmission(.{
        .generation = 1,
        .rows = 1,
        .cols = 2,
        .cells = (&cell)[0..1],
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 1, .height = 1 },
    }));
    try std.testing.expectEqual(@as(u64, 19), snapshot.generation);

    try std.testing.expectError(error.InvalidSubmission, validateSubmission(.{
        .generation = 1,
        .rows = 1,
        .cols = 1,
        .cells = (&cell)[0..1],
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 10, .height = 10 },
        .scrollbar = .{
            .track = .{ .x = 9, .y = 0, .width = 1, .height = 10 },
            .thumb = .{ .x = 9, .y = 9, .width = 1, .height = 2 },
            .history_count = 1,
            .offset = 0,
        },
    }));
}

test "renderer construction rejects missing fonts before device work" {
    try std.testing.expectError(error.MissingDefaultConfiguration, validateInit(.{
        .display = @ptrFromInt(1),
        .surface = @ptrFromInt(1),
        .size = .{ .width = 1, .height = 1 },
        .rows = 1,
        .cols = 1,
        .fonts = &.{},
    }));
}

test "glyph cache identity includes exact font and generated raster facts" {
    const native_a = text.GlyphKey{ .native = .{
        .font = .{ .slot = 0, .style = .normal },
        .face_index = 0,
        .glyph_id = 4,
        .cell_span = 1,
    } };
    const native_b = text.GlyphKey{ .native = .{
        .font = .{ .slot = 1, .style = .normal },
        .face_index = 0,
        .glyph_id = 4,
        .cell_span = 1,
    } };
    try std.testing.expect(!std.meta.eql(native_a, native_b));
    const generated_a = text.GlyphKey{ .generated = .{
        .codepoint = 0x2500,
        .width_px = 8,
        .height_px = 16,
        .baseline_px = 12,
    } };
    const generated_b = text.GlyphKey{ .generated = .{
        .codepoint = 0x2500,
        .width_px = 8,
        .height_px = 16,
        .baseline_px = 13,
    } };
    try std.testing.expect(!std.meta.eql(generated_a, generated_b));
}

test "shaped glyph placement anchors the pen once at the run start" {
    try std.testing.expectEqual(@as(i32, 89), glyphPixelX(8, 10, -1, 10 * 64));
}

test "draw colors consume projected cell and cursor facts exactly" {
    var cell = testCell('x');
    cell.foreground = .{ .r = 1, .g = 2, .b = 3 };
    cell.background = .{ .r = 4, .g = 5, .b = 6 };
    var cursor = testCursor();
    cursor.color = .{ .r = 7, .g = 8, .b = 9 };
    cursor.text_color = .{ .r = 10, .g = 11, .b = 12 };
    try std.testing.expectEqual(cell.background, cellFill(cell, cursor, false));
    try std.testing.expectEqual(cell.foreground, glyphColor(cell, cursor, false));
    try std.testing.expectEqual(cursor.color, cellFill(cell, cursor, true));
    try std.testing.expectEqual(cursor.text_color, glyphColor(cell, cursor, true));
}

test "unresolved line scaling and baseline facts fail before drawing" {
    var cells = [_]terminal.Cell{testCell('x')};
    try validateRowPresentation(.single_width, &cells);
    try std.testing.expectError(
        error.UnsupportedPresentation,
        validateRowPresentation(.double_width, &cells),
    );
    cells[0].baseline = .raised;
    try std.testing.expectError(
        error.UnsupportedPresentation,
        validateRowPresentation(.single_width, &cells),
    );
}

fn testCell(codepoint: u21) terminal.Cell {
    return .{
        .codepoint = codepoint,
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 255, .g = 255, .b = 255 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
        .underline_color = .{ .r = 255, .g = 255, .b = 255 },
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
        .underline_style = .none,
        .selected = false,
        .link_id = 0,
    };
}

fn testCursor() terminal.Cursor {
    return .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
}
