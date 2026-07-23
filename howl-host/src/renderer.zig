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

const PixelRect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

const Scale = struct {
    x: u2,
    y: u2,
    y_offset_cells: i2,
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
        for (0..work.rows) |row| try self.drawRowBackground(work, @intCast(row));
        for (0..work.rows) |row| try self.drawRowContent(work, @intCast(row));
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

    fn drawRowBackground(self: *Device, work: Submission, row: u16) Error!void {
        const start = @as(usize, row) * work.cols;
        const cells = work.cells[start..][0..work.cols];
        const geometry = work.row_geometry[row];
        const logical_cols = rowColumns(geometry, work.cols);
        for (cells[0..logical_cols], 0..) |cell, col| {
            const cursor_block = cursorBlockCovers(work, row, @intCast(col));
            const rect = planCell(row, @intCast(col), geometry, self.metrics) orelse
                return error.InvalidSubmission;
            try self.quad(
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                cellFill(cell, work.cursor, cursor_block),
                self.white,
            );
        }
        const row_width = @as(u32, work.cols) * self.metrics.width_px;
        const covered = @as(u32, logical_cols) * self.metrics.width_px * lineScale(geometry).x;
        if (covered < row_width) {
            const tail = cells[logical_cols];
            try self.quad(
                @intCast(covered),
                @as(i32, row) * self.metrics.height_px,
                row_width - covered,
                self.metrics.height_px,
                tail.background,
                self.white,
            );
        }
    }

    fn drawRowContent(self: *Device, work: Submission, row: u16) Error!void {
        const start = @as(usize, row) * work.cols;
        const cells = work.cells[start..][0..work.cols];
        const geometry = work.row_geometry[row];
        const logical_cols = rowColumns(geometry, work.cols);
        var at: u16 = 0;
        while (at < logical_cols) {
            var prepared = try text.prepareNextRun(self.allocator, &self.fonts, .{
                .cells = cells[0..logical_cols],
                .affected_start = at,
                .affected_end = logical_cols - 1,
                .geometry = geometry,
                .metrics = self.metrics,
            }, at);
            defer prepared.deinit();
            try self.drawPrepared(work, row, cells, prepared);
            std.debug.assert(prepared.end_cell > at);
            at = prepared.end_cell;
        }
        try self.drawDecorations(row, cells[0..logical_cols], geometry);
    }

    fn drawPrepared(
        self: *Device,
        work: Submission,
        row: u16,
        cells: []const terminal.Cell,
        prepared: text.PreparedRun,
    ) Error!void {
        switch (prepared.glyphs) {
            .none => {},
            .generated => |glyph| try self.drawGlyph(work, row, cells, prepared, glyph),
            .native => |owned| for (owned.values) |glyph|
                try self.drawGlyph(work, row, cells, prepared, glyph),
        }
    }

    fn drawGlyph(
        self: *Device,
        work: Submission,
        row: u16,
        cells: []const terminal.Cell,
        prepared: text.PreparedRun,
        glyph: text.PositionedGlyph,
    ) Error!void {
        std.debug.assert(glyph.source_start < glyph.source_end and glyph.source_end <= cells.len);
        const cached = try self.texture(work.generation, glyph.key);
        if (cached.width == 0 or cached.height == 0) return;
        const base_x = glyphPixelX(
            prepared.first_cell,
            self.metrics.width_px,
            cached.left,
            glyph.x_26_6,
        );
        const base_y = @as(i32, self.metrics.baseline_px) -
            cached.top - @divTrunc(glyph.y_26_6, 64);
        const rect = planContent(
            row,
            glyph.source_start,
            prepared.geometry,
            prepared.baseline,
            self.metrics,
            planTextSizing(prepared.first_cell, prepared.sizing, self.metrics, .{
                .x = base_x,
                .y = base_y,
                .width = cached.width,
                .height = cached.height,
            }) orelse return error.InvalidSubmission,
        ) orelse return error.InvalidSubmission;
        c.glEnable(c.GL_SCISSOR_TEST);
        defer c.glDisable(c.GL_SCISSOR_TEST);
        const cursor_block = cursorBlockCovers(work, row, prepared.first_cell);
        if (prepared.sizing.width > 1 or prepared.sizing.height > 1) {
            const clip = clipToSurface(
                clusterCellRect(
                    row,
                    prepared.first_cell,
                    prepared.geometry,
                    prepared.sizing,
                    self.metrics,
                ) orelse return error.InvalidSubmission,
                self.size,
            ) orelse return;
            setScissor(clip, self.size);
            try self.quad(
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                glyphColor(cells[glyph.source_start], work.cursor, cursor_block),
                cached.name,
            );
            return;
        }
        var col = glyph.source_start;
        while (col < glyph.source_end) : (col += 1) {
            const clip = clipToSurface(
                planCell(row, col, prepared.geometry, self.metrics) orelse
                    return error.InvalidSubmission,
                self.size,
            ) orelse continue;
            setScissor(clip, self.size);
            try self.quad(
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                glyphColor(cells[col], work.cursor, cursorBlockCovers(work, row, col)),
                cached.name,
            );
        }
    }

    fn drawDecorations(
        self: *Device,
        row: u16,
        cells: []const terminal.Cell,
        geometry: terminal.LineGeometry,
    ) Error!void {
        for (cells, 0..) |cell, col_usize| {
            if (cell.sizing.x != 0 or cell.sizing.y != 0) continue;
            if (!cell.strikethrough and !cell.underline) continue;
            const col: u16 = @intCast(col_usize);
            const decorations = self.fonts.decorationMetrics(cellFontKey(cell)) orelse
                return error.MissingFontConfiguration;
            if (cell.strikethrough) try self.drawDecoration(
                row,
                col,
                geometry,
                cell.baseline,
                cell.sizing,
                decorations.strike_y,
                decorations.strike_height,
                .single,
                cell.foreground,
            );
            if (cell.underline) try self.drawDecoration(
                row,
                col,
                geometry,
                cell.baseline,
                cell.sizing,
                decorations.underline_y,
                decorations.underline_height,
                cell.underline_style,
                cell.underline_color,
            );
        }
    }

    fn drawDecoration(
        self: *Device,
        row: u16,
        col: u16,
        geometry: terminal.LineGeometry,
        baseline: terminal.CellBaseline,
        sizing: terminal.TextSizing,
        y: u16,
        height: u16,
        style: terminal.UnderlineStyle,
        color: terminal.Rgb,
    ) Error!void {
        const clip = clipToSurface(
            clusterCellRect(row, col, geometry, sizing, self.metrics) orelse
                return error.InvalidSubmission,
            self.size,
        ) orelse return;
        c.glEnable(c.GL_SCISSOR_TEST);
        defer c.glDisable(c.GL_SCISSOR_TEST);
        setScissor(clip, self.size);
        const base = PixelRect{
            .x = @as(i32, col) * self.metrics.width_px,
            .y = y,
            .width = std.math.cast(u16, @as(u32, self.metrics.width_px) * sizing.width) orelse
                return error.InvalidSubmission,
            .height = height,
        };
        switch (style) {
            .none => {},
            .single => try self.drawDecorationRect(row, col, geometry, baseline, sizing, base, color),
            .double => {
                const upper_y = y -| (height + 1);
                var upper = base;
                upper.y = upper_y;
                try self.drawDecorationRect(row, col, geometry, baseline, sizing, upper, color);
                try self.drawDecorationRect(row, col, geometry, baseline, sizing, base, color);
            },
            .curly, .dotted, .dashed => {
                const unit = @max(@as(u16, 1), height);
                var x: u16 = 0;
                while (x < base.width) : (x += 1) {
                    const rise = decorationRise(style, x, unit) orelse continue;
                    var segment = base;
                    segment.x += x;
                    segment.width = 1;
                    segment.y -|= @min(segment.y, rise);
                    try self.drawDecorationRect(row, col, geometry, baseline, sizing, segment, color);
                }
            },
        }
    }

    fn drawDecorationRect(
        self: *Device,
        row: u16,
        col: u16,
        geometry: terminal.LineGeometry,
        baseline: terminal.CellBaseline,
        sizing: terminal.TextSizing,
        base: PixelRect,
        color: terminal.Rgb,
    ) Error!void {
        const sized = planTextSizing(col, sizing, self.metrics, base) orelse
            return error.InvalidSubmission;
        const rect = planContent(row, col, geometry, baseline, self.metrics, sized) orelse
            return error.InvalidSubmission;
        try self.quad(rect.x, rect.y, rect.width, rect.height, color, self.white);
    }

    fn drawCursor(self: *Device, work: Submission) Error!void {
        if (!work.cursor.visible or work.cursor.shape == .block) return;
        std.debug.assert(work.cursor.row < work.rows and work.cursor.col < work.cols);
        const cursor_cell = work.cells[@as(usize, work.cursor.row) * work.cols + work.cursor.col];
        const anchor_row = work.cursor.row -| cursor_cell.sizing.y;
        const anchor_col = work.cursor.col -| cursor_cell.sizing.x;
        const width: u16 = switch (work.cursor.shape) {
            .bar => @max(1, self.metrics.width_px / 8),
            else => std.math.cast(
                u16,
                @as(u32, self.metrics.width_px) * cursor_cell.sizing.width,
            ) orelse return error.InvalidSubmission,
        };
        const height: u16 = switch (work.cursor.shape) {
            .underline => @max(1, self.metrics.height_px / 8),
            .none => return,
            else => std.math.cast(
                u16,
                @as(u32, self.metrics.height_px) * cursor_cell.sizing.height,
            ) orelse return error.InvalidSubmission,
        };
        const cluster_height = @as(u32, self.metrics.height_px) * cursor_cell.sizing.height;
        const y_offset: u16 = if (work.cursor.shape == .underline)
            std.math.cast(u16, cluster_height - height) orelse return error.InvalidSubmission
        else
            0;
        const geometry = work.row_geometry[anchor_row];
        const rect = planContent(
            anchor_row,
            anchor_col,
            geometry,
            .normal,
            self.metrics,
            .{
                .x = @as(i32, anchor_col) * self.metrics.width_px,
                .y = y_offset,
                .width = width,
                .height = height,
            },
        ) orelse return error.InvalidSubmission;
        var cluster = planCell(anchor_row, anchor_col, geometry, self.metrics) orelse
            return error.InvalidSubmission;
        const cluster_width = @as(u64, cluster.width) * cursor_cell.sizing.width;
        const cluster_height_u64 = @as(u64, cluster.height) * cursor_cell.sizing.height;
        if (cluster_width > std.math.maxInt(u32) or cluster_height_u64 > std.math.maxInt(u32))
            return error.InvalidSubmission;
        cluster.width = @intCast(cluster_width);
        cluster.height = @intCast(cluster_height_u64);
        const clip = clipToSurface(cluster, self.size) orelse return;
        c.glEnable(c.GL_SCISSOR_TEST);
        defer c.glDisable(c.GL_SCISSOR_TEST);
        setScissor(clip, self.size);
        try self.quad(
            rect.x,
            rect.y,
            rect.width,
            rect.height,
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
        width: u32,
        height: u32,
        color: terminal.Rgb,
        texture_name: c.GLuint,
    ) Error!void {
        if (width == 0 or height == 0) return;
        const vertices = quadVertices(x, y, width, height, self.size, color);
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

fn pixelToNdc(value: i64, extent: u32) f32 {
    return @as(f32, @floatFromInt(value)) * 2.0 / @as(f32, @floatFromInt(extent)) - 1.0;
}

fn quadVertices(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    size: PixelSize,
    color: terminal.Rgb,
) [6]Vertex {
    std.debug.assert(width != 0 and height != 0);
    const left = pixelToNdc(x, size.width);
    const right = pixelToNdc(@as(i64, x) + width, size.width);
    const top = -pixelToNdc(y, size.height);
    const bottom = -pixelToNdc(@as(i64, y) + height, size.height);
    const red = @as(f32, @floatFromInt(color.r)) / 255.0;
    const green = @as(f32, @floatFromInt(color.g)) / 255.0;
    const blue = @as(f32, @floatFromInt(color.b)) / 255.0;
    return .{
        .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = left, .y = bottom, .u = 0, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = left, .y = top, .u = 0, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = top, .u = 1, .v = 0, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = bottom, .u = 1, .v = 1, .r = red, .g = green, .b = blue, .a = 1 },
    };
}

fn lineScale(geometry: terminal.LineGeometry) Scale {
    // DEC double-height rows share one 2x canvas; the bottom row shifts that
    // canvas up before both halves are clipped to their physical row.
    return switch (geometry) {
        .single_width => .{ .x = 1, .y = 1, .y_offset_cells = 0 },
        .double_width => .{ .x = 2, .y = 1, .y_offset_cells = 0 },
        .double_height_top => .{ .x = 2, .y = 2, .y_offset_cells = 0 },
        .double_height_bottom => .{ .x = 2, .y = 2, .y_offset_cells = -1 },
    };
}

fn rowColumns(geometry: terminal.LineGeometry, cols: u16) u16 {
    return switch (geometry) {
        .single_width => cols,
        else => @max(1, cols / 2),
    };
}

fn planCell(
    row: u16,
    col: u16,
    geometry: terminal.LineGeometry,
    metrics: text.CellMetrics,
) ?PixelRect {
    const scale = lineScale(geometry);
    const x = @as(u64, col) * metrics.width_px * scale.x;
    const y = @as(u64, row) * metrics.height_px;
    const width = @as(u32, metrics.width_px) * scale.x;
    if (x > std.math.maxInt(i32) or y > std.math.maxInt(i32)) return null;
    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = width,
        .height = metrics.height_px,
    };
}

fn clusterCellRect(
    row: u16,
    col: u16,
    geometry: terminal.LineGeometry,
    sizing: terminal.TextSizing,
    metrics: text.CellMetrics,
) ?PixelRect {
    var rect = planCell(row, col, geometry, metrics) orelse return null;
    const width = @as(u64, rect.width) * sizing.width;
    const height = @as(u64, rect.height) * sizing.height;
    if (width > std.math.maxInt(u32) or height > std.math.maxInt(u32)) return null;
    rect.width = @intCast(width);
    rect.height = @intCast(height);
    return rect;
}

fn planTextSizing(
    anchor_col: u16,
    sizing: terminal.TextSizing,
    metrics: text.CellMetrics,
    base: PixelRect,
) ?PixelRect {
    std.debug.assert(sizing.width > 0 and sizing.height > 0);
    std.debug.assert(sizing.x == 0 and sizing.y == 0);
    const fractional = sizing.subscale_n > 0 and sizing.subscale_d > 0 and
        sizing.subscale_n < sizing.subscale_d;
    const numerator: u32 = @as(u32, sizing.height) *
        (if (fractional) sizing.subscale_n else 1);
    const denominator: u32 = if (fractional) sizing.subscale_d else 1;
    const block_width = @as(u64, sizing.width) * metrics.width_px;
    const block_height = @as(u64, sizing.height) * metrics.height_px;
    const area_width = block_width * numerator / (@as(u64, sizing.height) * denominator);
    const area_height = block_height * numerator / (@as(u64, sizing.height) * denominator);
    const x_offset: u64 = switch (sizing.horizontal_align) {
        1 => block_width - area_width,
        2 => (block_width - area_width) / 2,
        else => 0,
    };
    const y_offset: u64 = switch (sizing.vertical_align) {
        1 => block_height - area_height,
        2 => (block_height - area_height) / 2,
        else => 0,
    };
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    const x = anchor_x + @divFloor((@as(i64, base.x) - anchor_x) * numerator, denominator) +
        @as(i64, @intCast(x_offset));
    const y = @divFloor(@as(i64, base.y) * numerator, denominator) +
        @as(i64, @intCast(y_offset));
    const width = @as(u64, base.width) * numerator / denominator;
    const height = @as(u64, base.height) * numerator / denominator;
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or
        y < std.math.minInt(i32) or y > std.math.maxInt(i32) or
        width > std.math.maxInt(u32) or height > std.math.maxInt(u32))
        return null;
    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

fn planContent(
    row: u16,
    anchor_col: u16,
    geometry: terminal.LineGeometry,
    baseline: terminal.CellBaseline,
    metrics: text.CellMetrics,
    base: PixelRect,
) ?PixelRect {
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    var x = @as(i64, base.x);
    var y = @as(i64, base.y);
    var width = @as(u64, base.width);
    var height = @as(u64, base.height);
    if (baseline != .normal) {
        // SGR 73/74 use Kitty's explicit half-size top/bottom alignment while
        // retaining the normal shaped mask and its cache identity.
        x = anchor_x + @divFloor(x - anchor_x, 2);
        width = (width + 1) / 2;
        height = (height + 1) / 2;
        y = @divFloor(y, 2);
        if (baseline == .lowered) y += metrics.height_px - (metrics.height_px + 1) / 2;
    }
    const scale = lineScale(geometry);
    x *= scale.x;
    y = @as(i64, row) * metrics.height_px +
        @as(i64, scale.y_offset_cells) * metrics.height_px + y * scale.y;
    width *= scale.x;
    height *= scale.y;
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or
        y < std.math.minInt(i32) or y > std.math.maxInt(i32) or
        width > std.math.maxInt(u32) or height > std.math.maxInt(u32))
        return null;
    return .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(width), .height = @intCast(height) };
}

fn clipToSurface(rect: PixelRect, size: PixelSize) ?PixelRect {
    const left = @max(@as(i64, 0), rect.x);
    const top = @max(@as(i64, 0), rect.y);
    const right = @min(@as(i64, size.width), @as(i64, rect.x) + rect.width);
    const bottom = @min(@as(i64, size.height), @as(i64, rect.y) + rect.height);
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

fn intersectRect(a: PixelRect, b: PixelRect) ?PixelRect {
    const left = @max(@as(i64, a.x), b.x);
    const top = @max(@as(i64, a.y), b.y);
    const right = @min(@as(i64, a.x) + a.width, @as(i64, b.x) + b.width);
    const bottom = @min(@as(i64, a.y) + a.height, @as(i64, b.y) + b.height);
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

fn setScissor(rect: PixelRect, size: PixelSize) void {
    std.debug.assert(rect.x >= 0 and rect.y >= 0);
    std.debug.assert(@as(u64, @intCast(rect.x)) + rect.width <= size.width);
    std.debug.assert(@as(u64, @intCast(rect.y)) + rect.height <= size.height);
    c.glScissor(
        @intCast(rect.x),
        @intCast(size.height - @as(u32, @intCast(rect.y)) - rect.height),
        @intCast(rect.width),
        @intCast(rect.height),
    );
}

fn glyphPixelX(run_start: u16, cell_width: u16, raster_left: i16, shaped_x_26_6: i32) i32 {
    return @as(i32, run_start) * cell_width + raster_left + @divTrunc(shaped_x_26_6, 64);
}

fn cursorBlockCovers(work: Submission, row: u16, col: u16) bool {
    if (!work.cursor.visible or work.cursor.shape != .block or
        row >= work.rows or col >= work.cols or
        work.cursor.row >= work.rows or work.cursor.col >= work.cols)
        return false;
    const candidate = work.cells[@as(usize, row) * work.cols + col];
    const cursor_cell = work.cells[@as(usize, work.cursor.row) * work.cols + work.cursor.col];
    return row -| candidate.sizing.y == work.cursor.row -| cursor_cell.sizing.y and
        col -| candidate.sizing.x == work.cursor.col -| cursor_cell.sizing.x;
}

fn cellFill(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.color else cell.background;
}

fn glyphColor(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.text_color else cell.foreground;
}

fn cellFontKey(cell: terminal.Cell) text.FontKey {
    return .{
        .slot = cell.font,
        .style = if (cell.bold and cell.italic)
            .bold_italic
        else if (cell.bold)
            .bold
        else if (cell.italic)
            .italic
        else
            .normal,
    };
}

fn decorationRise(style: terminal.UnderlineStyle, x: u16, unit: u16) ?u16 {
    std.debug.assert(unit != 0);
    return switch (style) {
        .curly => if (x % (unit *| 2) >= unit) unit else 0,
        .dotted => if (x % (unit *| 2) < unit) 0 else null,
        .dashed => if (x % (unit *| 4) < unit *| 3) 0 else null,
        else => null,
    };
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
    cells[0].baseline = .raised;
    var geometry = [_]terminal.LineGeometry{.double_width};
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
    cells[0].baseline = .normal;
    geometry[0] = .single_width;
    const copy = snapshot.view();
    try std.testing.expectEqual(@as(u21, 'a'), copy.cells[0].codepoint);
    try std.testing.expectEqual(terminal.CellBaseline.raised, copy.cells[0].baseline);
    try std.testing.expectEqual(terminal.LineGeometry.double_width, copy.row_geometry[0]);
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

test "decoration metrics use the exact projected font identity" {
    var cell = testCell('x');
    cell.font = 15;
    cell.bold = true;
    cell.italic = true;
    try std.testing.expectEqual(
        text.FontKey{ .slot = 15, .style = .bold_italic },
        cellFontKey(cell),
    );
}

test "row plans preserve logical columns and odd physical edges" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    try std.testing.expectEqual(@as(u16, 5), rowColumns(.single_width, 5));
    try std.testing.expectEqual(@as(u16, 2), rowColumns(.double_width, 5));
    try std.testing.expectEqual(@as(u16, 1), rowColumns(.double_height_top, 1));
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 30, .width = 18, .height = 15 },
        planCell(2, 1, .double_width, metrics).?,
    );
}

test "double-height halves share one scaled canvas with exact row clipping" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const base = PixelRect{ .x = 9, .y = 2, .width = 7, .height = 9 };
    const top = planContent(1, 1, .double_height_top, .normal, metrics, base).?;
    const bottom = planContent(2, 1, .double_height_bottom, .normal, metrics, base).?;
    try std.testing.expectEqual(PixelRect{ .x = 18, .y = 19, .width = 14, .height = 18 }, top);
    try std.testing.expectEqual(top, bottom);
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 19, .width = 14, .height = 11 },
        intersectRect(top, planCell(1, 1, .double_height_top, metrics).?).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 30, .width = 14, .height = 7 },
        intersectRect(bottom, planCell(2, 1, .double_height_bottom, metrics).?).?,
    );
}

test "raised and lowered placement use half scale and top bottom alignment" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const base = PixelRect{ .x = 11, .y = 2, .width = 7, .height = 9 };
    try std.testing.expectEqual(
        PixelRect{ .x = 10, .y = 1, .width = 4, .height = 5 },
        planContent(0, 1, .single_width, .raised, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 10, .y = 8, .width = 4, .height = 5 },
        planContent(0, 1, .single_width, .lowered, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 20, .y = 2, .width = 8, .height = 10 },
        planContent(0, 1, .double_height_top, .raised, metrics, base).?,
    );
}

test "baseline scaling anchors every shaped glyph to its source cell" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const second = planContent(
        0,
        3,
        .single_width,
        .raised,
        metrics,
        .{ .x = 28, .y = 2, .width = 7, .height = 9 },
    ).?;
    try std.testing.expectEqual(@as(i32, 27), second.x);
    try std.testing.expect(second.x >= planCell(0, 3, .single_width, metrics).?.x);
    try std.testing.expect(second.x < planCell(0, 4, .single_width, metrics).?.x);
}

test "cursor and decoration rectangles share geometry and baseline transforms" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const cursor = PixelRect{ .x = 9, .y = 13, .width = 9, .height = 2 };
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 26, .width = 18, .height = 4 },
        planContent(0, 1, .double_height_top, .normal, metrics, cursor).?,
    );
    const underline = PixelRect{ .x = 9, .y = 12, .width = 9, .height = 1 };
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 12, .width = 10, .height = 2 },
        planContent(0, 1, .double_height_top, .raised, metrics, underline).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 26, .width = 10, .height = 2 },
        planContent(0, 1, .double_height_top, .lowered, metrics, underline).?,
    );
}

test "OSC 66 draw planning scales and aligns within the exact cell block" {
    const metrics = text.CellMetrics{ .width_px = 8, .height_px = 16, .baseline_px = 12 };
    const base = PixelRect{ .x = 0, .y = 4, .width = 8, .height = 8 };
    try std.testing.expectEqual(
        PixelRect{ .x = 0, .y = 8, .width = 16, .height = 16 },
        planTextSizing(0, .{ .width = 4, .height = 2 }, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 26, .y = 8, .width = 16, .height = 16 },
        planTextSizing(
            3,
            .{ .width = 4, .height = 2 },
            metrics,
            .{ .x = 25, .y = 4, .width = 8, .height = 8 },
        ).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 16, .y = 12, .width = 8, .height = 8 },
        planTextSizing(0, .{
            .width = 4,
            .height = 2,
            .subscale_n = 1,
            .subscale_d = 2,
            .vertical_align = 2,
            .horizontal_align = 1,
        }, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 8, .y = 16, .width = 32, .height = 32 },
        clusterCellRect(1, 1, .single_width, .{ .width = 4, .height = 2 }, metrics).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 24, .y = 16, .width = 8, .height = 16 },
        planCell(1, 3, .single_width, metrics).?,
    );

    var cells: [8]terminal.Cell = @splat(testCell('x'));
    for (&cells, 0..) |*cell, index| {
        cell.sizing = .{
            .width = 4,
            .height = 2,
            .x = @intCast(index % 4),
            .y = @intCast(index / 4),
        };
    }
    var cursor = testCursor();
    cursor.visible = true;
    cursor.shape = .block;
    cursor.row = 1;
    cursor.col = 2;
    const geometry = [_]terminal.LineGeometry{ .single_width, .single_width };
    const work = Submission{
        .generation = 1,
        .rows = 2,
        .cols = 4,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = cursor,
        .size = .{ .width = 32, .height = 32 },
    };
    try std.testing.expect(cursorBlockCovers(work, 0, 0));
    try std.testing.expect(cursorBlockCovers(work, 1, 3));
    const native_metrics = text.CellMetrics{ .width_px = 8, .height_px = 20, .baseline_px = 16 };
    const raster = PixelRect{ .x = 0, .y = 3, .width = 8, .height = 13 };
    const scale_two = planTextSizing(0, .{ .width = 2, .height = 2 }, native_metrics, raster).?;
    const scale_two_clip = clusterCellRect(
        0,
        0,
        .single_width,
        .{ .width = 2, .height = 2 },
        native_metrics,
    ).?;
    try std.testing.expectEqual(scale_two, intersectRect(scale_two, scale_two_clip).?);
    const scale_three = planTextSizing(0, .{ .width = 3, .height = 3 }, native_metrics, raster).?;
    const scale_three_clip = clusterCellRect(
        0,
        0,
        .single_width,
        .{ .width = 3, .height = 3 },
        native_metrics,
    ).?;
    try std.testing.expectEqual(PixelRect{ .x = 0, .y = 9, .width = 24, .height = 39 }, scale_three);
    try std.testing.expectEqual(scale_three, intersectRect(scale_three, scale_three_clip).?);
}

test "decoration patterns are bounded and deterministic" {
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.curly, 0, 2));
    try std.testing.expectEqual(@as(?u16, 2), decorationRise(.curly, 2, 2));
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.dotted, 1, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.dotted, 2, 2));
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.dashed, 5, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.dashed, 6, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.single, 0, 2));
}

test "scaled quads retain complete texture coordinates for scissor cropping" {
    const vertices = quadVertices(
        -4,
        3,
        18,
        30,
        .{ .width = 45, .height = 30 },
        .{ .r = 1, .g = 2, .b = 3 },
    );
    try std.testing.expectEqual(@as(f32, 0), vertices[0].u);
    try std.testing.expectEqual(@as(f32, 0), vertices[0].v);
    try std.testing.expectEqual(@as(f32, 1), vertices[1].u);
    try std.testing.expectEqual(@as(f32, 1), vertices[1].v);
    try std.testing.expect(vertices[0].x < vertices[1].x);
    try std.testing.expect(vertices[0].y > vertices[1].y);
}

test "surface clipping rejects empty and bounds hostile rectangles" {
    try std.testing.expect(clipToSurface(
        .{ .x = -10, .y = -20, .width = 5, .height = 5 },
        .{ .width = 40, .height = 30 },
    ) == null);
    try std.testing.expectEqual(
        PixelRect{ .x = 0, .y = 0, .width = 7, .height = 9 },
        clipToSurface(
            .{ .x = -3, .y = -2, .width = 10, .height = 11 },
            .{ .width = 40, .height = 30 },
        ).?,
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
