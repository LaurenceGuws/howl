//! Owns one EGL/OpenGL ES thread and coalesced complete-layout rendering.

const std = @import("std");
const howl_text = @import("howl_text");
const howl_vt = @import("howl_vt");
const layout = @import("layout.zig");
const terminal = @import("terminal.zig");
const text = @import("text.zig");
const c = @import("native.zig").c;

/// Reports an exact render-device or owner-state failure.
pub const Error = std.mem.Allocator.Error || howl_text.ShapeError ||
    howl_text.RasterError || howl_text.GeneratedError || text.Error || error{
    egl_display_failed,
    egl_initialize_failed,
    egl_config_failed,
    egl_context_failed,
    egl_surface_failed,
    shader_failed,
    upload_failed,
    draw_failed,
    swap_failed,
    stale_generation,
    render_stopping,
    render_signal_failed,
    egl_cleanup_failed,
    transcript_mismatch,
    transcript_incomplete,
    invalid_terminal_snapshot,
    vertex_limit,
};

/// Reports allocation, thread creation, signaling, or render-device startup failure.
pub const StartError = std.Thread.SpawnError || howl_text.InitError || Error;

/// Carries native objects borrowed for the render owner's lifetime.
pub const NativeInit = struct {
    display: *c.struct_wl_display,
    surface: *c.struct_wl_surface,
    size: layout.Size,
    font_path: []const u8,
};

/// Describes one render operation consumed by deterministic transcripts.
const Operation = union(enum) {
    initialize: struct {
        size: layout.Size,
        metrics: howl_text.Metrics,
    },
    frame: FrameRecord,
    cleanup,
};

const Frame = struct {
    generation: u64,
    layout: layout.Snapshot,
    terminals: [layout.terminal_count]terminal.Snapshot,
};

const TerminalRecord = struct {
    terminal: layout.TerminalId,
    generation: u64,
    rows: u16,
    cols: u16,
    count: u32,
};

const FrameRecord = struct {
    generation: u64,
    layout: layout.Snapshot,
    terminals: [layout.terminal_count]TerminalRecord,
};

/// Supplies one expected render operation and its optional exact failure.
const Step = struct {
    operation: Operation,
    failure: ?Error = null,
};

/// Strictly consumes an exact bounded sequence of render operations.
const Transcript = struct {
    steps: []const Step,
    index: usize = 0,

    /// Consumes one exact operation and returns its configured failure.
    fn consume(self: *Transcript, operation: Operation) Error!void {
        if (self.index == self.steps.len) return error.transcript_mismatch;
        const step = self.steps[self.index];
        if (!std.meta.eql(step.operation, operation)) return error.transcript_mismatch;
        self.index += 1;
        if (step.failure) |failure| return failure;
    }

    /// Proves that every expected operation was consumed exactly once.
    fn finish(self: *const Transcript) Error!void {
        if (self.index != self.steps.len) return error.transcript_incomplete;
    }
};

const Source = union(enum) {
    native: NativeInit,
    transcript: struct {
        transcript: *Transcript,
        size: layout.Size,
        metric_values: howl_text.Metrics,
    },
};

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    red: f32,
    green: f32,
    blue: f32,
    opacity: f32,
};

const max_decoration_quads: usize = 5;
const max_vertices: usize =
    (terminal.max_cells * (1 + text.max_cell_glyphs +
        max_decoration_quads) + 3) * 6;

const PixelRect = struct {
    x: i32,
    y: i32,
    width: u16,
    height: u16,
};

const TerminalFacts = struct {
    cells: usize,
    glyph_cells: usize,
    cursor: bool,
};

const CellColors = struct {
    foreground: [3]f32,
    background: [3]f32,
    underline: [3]f32,
    foreground_opacity: f32,
    visible: bool,
};

const BatchFacts = struct {
    terminals: u2,
    cells: usize,
    glyph_cells: usize,
    cursors: u2,
};

const Native = struct {
    egl_display: c.EGLDisplay,
    context: c.EGLContext,
    egl_surface: c.EGLSurface,
    window: *c.struct_wl_egl_window,
    program: c.GLuint,
    vertex_buffer: c.GLuint,
    vertices: []Vertex,
    text: text.Text,
    size: layout.Size,

    fn init(allocator: std.mem.Allocator, values: NativeInit) StartError!Native {
        const window = c.wl_egl_window_create(
            values.surface,
            @intCast(values.size.width),
            @intCast(values.size.height),
        ) orelse return error.egl_surface_failed;
        errdefer c.wl_egl_window_destroy(window);

        const egl_display = c.eglGetDisplay(@ptrCast(values.display));
        if (egl_display == c.EGL_NO_DISPLAY) return error.egl_display_failed;
        if (c.eglInitialize(egl_display, null, null) != c.EGL_TRUE)
            return error.egl_initialize_failed;
        errdefer terminateRollback(egl_display);
        if (c.eglBindAPI(c.EGL_OPENGL_ES_API) != c.EGL_TRUE)
            return error.egl_context_failed;

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
        if (c.eglChooseConfig(
            egl_display,
            &attributes,
            &config,
            1,
            &count,
        ) != c.EGL_TRUE or count != 1) return error.egl_config_failed;

        const context_attributes = [_]c.EGLint{
            c.EGL_CONTEXT_CLIENT_VERSION,
            2,
            c.EGL_NONE,
        };
        const context = c.eglCreateContext(
            egl_display,
            config,
            c.EGL_NO_CONTEXT,
            &context_attributes,
        );
        if (context == c.EGL_NO_CONTEXT) return error.egl_context_failed;
        errdefer destroyContextRollback(egl_display, context);
        const egl_surface = c.eglCreateWindowSurface(
            egl_display,
            config,
            @intFromPtr(window),
            null,
        );
        if (egl_surface == c.EGL_NO_SURFACE) return error.egl_surface_failed;
        errdefer destroySurfaceRollback(egl_display, egl_surface);
        if (c.eglMakeCurrent(
            egl_display,
            egl_surface,
            egl_surface,
            context,
        ) != c.EGL_TRUE) return error.egl_context_failed;
        errdefer releaseCurrentRollback(egl_display);
        const program = try createProgram();
        errdefer c.glDeleteProgram(program);
        const atlas_uniform = c.glGetUniformLocation(program, "atlas");
        if (atlas_uniform < 0) return error.shader_failed;
        c.glUseProgram(program);
        c.glUniform1i(atlas_uniform, 0);
        if (c.glGetError() != c.GL_NO_ERROR) return error.shader_failed;
        var vertex_buffer: c.GLuint = 0;
        c.glGenBuffers(1, &vertex_buffer);
        if (vertex_buffer == 0 or c.glGetError() != c.GL_NO_ERROR)
            return error.upload_failed;
        errdefer c.glDeleteBuffers(1, &vertex_buffer);
        const vertices = try allocator.alloc(Vertex, max_vertices);
        errdefer allocator.free(vertices);
        var text_owner = try text.Text.init(allocator, values.font_path);
        errdefer text_owner.deinit() catch
            @panic("text owner rejected initialization rollback");

        return .{
            .egl_display = egl_display,
            .context = context,
            .egl_surface = egl_surface,
            .window = window,
            .program = program,
            .vertex_buffer = vertex_buffer,
            .vertices = vertices,
            .text = text_owner,
            .size = values.size,
        };
    }

    fn draw(self: *Native, frame: Frame) Error!void {
        const snapshot = frame.layout;
        const facts = try batchFacts(frame, self.text.metrics);
        const maximum_quads = @as(usize, facts.terminals) +
            facts.cells * (1 + max_decoration_quads) +
            facts.glyph_cells * text.max_cell_glyphs + facts.cursors;
        if (maximum_quads > self.vertices.len / 6) return error.vertex_limit;
        try self.text.beginFrame(frame.generation);
        if (!std.meta.eql(self.size, snapshot.size)) {
            c.wl_egl_window_resize(
                self.window,
                @intCast(snapshot.size.width),
                @intCast(snapshot.size.height),
                0,
                0,
            );
            self.size = snapshot.size;
        }
        var vertex_count: usize = 0;
        const solid_uv = self.text.textureRect(0, 1, 1);
        for (snapshot.visible(), 0..) |placement, placement_index| {
            try appendQuad(
                self.vertices,
                &vertex_count,
                .{
                    .x = placement.rect.x,
                    .y = placement.rect.y,
                    .width = placement.rect.width,
                    .height = placement.rect.height,
                },
                placement.rect,
                snapshot.size,
                solid_uv,
                if (placement_index == 0)
                    .{ 0.09, 0.11, 0.14 }
                else
                    .{ 0.12, 0.14, 0.17 },
                1.0,
            );
            try self.appendTerminal(
                &vertex_count,
                placement,
                frame.terminals[placement.terminal.index()],
                snapshot.size,
                solid_uv,
            );
        }
        // Every glyph is resolved before the frame reaches GPU draw state.
        // Atlas exhaustion therefore rejects the complete frame before buffer
        // upload, draw, or swap.
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.text.texture);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vertex_buffer);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(vertex_count * @sizeOf(Vertex)),
            self.vertices.ptr,
            c.GL_STREAM_DRAW,
        );
        if (c.glGetError() != c.GL_NO_ERROR) return error.upload_failed;

        c.glViewport(0, 0, @intCast(self.size.width), @intCast(self.size.height));
        c.glClearColor(0.035, 0.039, 0.045, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        c.glEnableVertexAttribArray(3);
        c.glVertexAttribPointer(
            0,
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            null,
        );
        c.glVertexAttribPointer(
            1,
            3,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "red")),
        );
        c.glVertexAttribPointer(
            2,
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "u")),
        );
        c.glVertexAttribPointer(
            3,
            1,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "opacity")),
        );
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(vertex_count));
        c.glDisable(c.GL_BLEND);
        c.glDisableVertexAttribArray(2);
        c.glDisableVertexAttribArray(3);
        c.glDisableVertexAttribArray(1);
        c.glDisableVertexAttribArray(0);
        if (c.glGetError() != c.GL_NO_ERROR) return error.draw_failed;
        // A KWin 6.7.3 virtual-compositor probe completed 32 swaps here while
        // only the main thread dispatched Wayland. EGL use and swap therefore
        // stay on this thread; Wayland dispatch and configure stay on main.
        if (c.eglSwapBuffers(self.egl_display, self.egl_surface) != c.EGL_TRUE)
            return error.swap_failed;
    }

    fn appendTerminal(
        self: *Native,
        vertex_count: *usize,
        placement: layout.Placement,
        snapshot: terminal.Snapshot,
        size: layout.Size,
        solid_uv: [4]f32,
    ) Error!void {
        const facts = try terminalFacts(placement, snapshot, self.text.metrics);
        const cell_width = self.text.metrics.cell_width;
        const cell_height = self.text.metrics.cell_height;
        const cols = snapshot.cols;
        const rows = snapshot.rows;
        for (0..rows) |row| for (0..cols) |col| {
            const cell = snapshot.visible()[row * cols + col];
            if (cell.width == 0 or cell.height == 0 or
                cell.combining_len > terminal.max_combining or
                cell.x >= cell.width or cell.y >= cell.height)
                return error.invalid_terminal_snapshot;
            const continuation = cell.x != 0 or cell.y != 0;
            if (!continuation and
                (col + cell.width > cols or row + cell.height > rows))
                return error.invalid_terminal_snapshot;
            const cursor_here = facts.cursor and
                row == snapshot.cursor_row and col == snapshot.cursor_col;
            const colors = cellColors(snapshot, cell, cursor_here);
            const cell_x = @as(i32, placement.rect.x) +
                @as(i32, @intCast(col * cell_width));
            const cell_y = @as(i32, placement.rect.y) +
                @as(i32, @intCast(row * cell_height));
            try appendQuad(
                self.vertices,
                vertex_count,
                .{
                    .x = cell_x,
                    .y = cell_y,
                    .width = cell_width,
                    .height = cell_height,
                },
                placement.rect,
                size,
                solid_uv,
                colors.background,
                1.0,
            );
            if (continuation or cell.codepoint == 0 or
                !colors.visible) continue;
            var codepoint_storage: [terminal.max_combining + 1]u32 = undefined;
            const glyphs = try self.text.resolve(
                cell.copyCodepoints(&codepoint_storage),
                cell.width,
            );
            for (glyphs.slice()) |glyph| {
                if (glyph.width == 0 or glyph.height == 0) continue;
                const x_offset = @divTrunc(glyph.x_offset, 64);
                const y_offset = @divTrunc(glyph.y_offset, 64);
                try appendQuad(
                    self.vertices,
                    vertex_count,
                    .{
                        .x = cell_x + glyph.left + x_offset,
                        .y = cell_y + self.text.metrics.baseline - glyph.top - y_offset,
                        .width = glyph.width,
                        .height = glyph.height,
                    },
                    placement.rect,
                    size,
                    self.text.textureRect(
                        glyph.slot,
                        glyph.width,
                        glyph.height,
                    ),
                    colors.foreground,
                    colors.foreground_opacity,
                );
            }
            try appendDecorations(
                self.vertices,
                vertex_count,
                cell,
                cell_x,
                cell_y,
                cell_width,
                self.text.metrics,
                placement.rect,
                size,
                solid_uv,
                colors.underline,
                colors.foreground,
            );
        };
        if (facts.cursor and snapshot.cursor_shape != .block and
            snapshot.cursor_shape != .none)
            try appendQuad(
                self.vertices,
                vertex_count,
                .{
                    .x = @as(i32, placement.rect.x) +
                        @as(i32, snapshot.cursor_col) * cell_width,
                    .y = @as(i32, placement.rect.y) +
                        @as(i32, snapshot.cursor_row) * cell_height +
                        if (snapshot.cursor_shape == .underline)
                            cell_height - 2
                        else
                            0,
                    .width = if (snapshot.cursor_shape == .bar) 2 else cell_width,
                    .height = if (snapshot.cursor_shape == .bar) cell_height else 2,
                },
                placement.rect,
                size,
                solid_uv,
                rgbFloats(snapshot.cursor_color),
                1.0,
            );
    }

    fn deinit(self: *Native) Error!void {
        var failed = false;
        const allocator = self.text.allocator;
        self.text.deinit() catch {
            failed = true;
        };
        allocator.free(self.vertices);
        c.glDeleteBuffers(1, &self.vertex_buffer);
        c.glDeleteProgram(self.program);
        if (c.glGetError() != c.GL_NO_ERROR) failed = true;
        if (c.eglMakeCurrent(
            self.egl_display,
            c.EGL_NO_SURFACE,
            c.EGL_NO_SURFACE,
            c.EGL_NO_CONTEXT,
        ) != c.EGL_TRUE) failed = true;
        if (c.eglDestroySurface(self.egl_display, self.egl_surface) != c.EGL_TRUE)
            failed = true;
        if (c.eglDestroyContext(self.egl_display, self.context) != c.EGL_TRUE)
            failed = true;
        if (c.eglTerminate(self.egl_display) != c.EGL_TRUE) failed = true;
        c.wl_egl_window_destroy(self.window);
        if (failed) return error.egl_cleanup_failed;
    }
};

fn createProgram() Error!c.GLuint {
    const vertex_source: [:0]const u8 =
        \\attribute vec2 position;
        \\attribute vec2 texture_position;
        \\attribute vec3 color;
        \\attribute float opacity;
        \\varying vec2 fragment_texture_position;
        \\varying vec3 fragment_color;
        \\varying float fragment_opacity;
        \\void main() {
        \\    fragment_texture_position = texture_position;
        \\    fragment_color = color;
        \\    fragment_opacity = opacity;
        \\    gl_Position = vec4(position, 0.0, 1.0);
        \\}
    ;
    const fragment_source: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D atlas;
        \\varying vec2 fragment_texture_position;
        \\varying vec3 fragment_color;
        \\varying float fragment_opacity;
        \\void main() {
        \\    float alpha = texture2D(atlas, fragment_texture_position).a;
        \\    gl_FragColor = vec4(fragment_color, alpha * fragment_opacity);
        \\}
    ;
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_source);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment);
    const program = c.glCreateProgram();
    if (program == 0) return error.shader_failed;
    errdefer c.glDeleteProgram(program);
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glBindAttribLocation(program, 0, "position");
    c.glBindAttribLocation(program, 1, "color");
    c.glBindAttribLocation(program, 2, "texture_position");
    c.glBindAttribLocation(program, 3, "opacity");
    c.glLinkProgram(program);
    var linked: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &linked);
    if (linked != c.GL_TRUE or c.glGetError() != c.GL_NO_ERROR)
        return error.shader_failed;
    return program;
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) Error!c.GLuint {
    const shader = c.glCreateShader(kind);
    if (shader == 0) return error.shader_failed;
    errdefer c.glDeleteShader(shader);
    const source_pointer: [*c]const u8 = source.ptr;
    c.glShaderSource(shader, 1, &source_pointer, null);
    c.glCompileShader(shader);
    var compiled: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &compiled);
    if (compiled != c.GL_TRUE or c.glGetError() != c.GL_NO_ERROR)
        return error.shader_failed;
    return shader;
}

fn batchFacts(frame: Frame, metrics: howl_text.Metrics) Error!BatchFacts {
    var facts = BatchFacts{
        .terminals = frame.layout.count,
        .cells = 0,
        .glyph_cells = 0,
        .cursors = 0,
    };
    for (frame.layout.visible()) |placement| {
        const terminal_facts = try terminalFacts(
            placement,
            frame.terminals[placement.terminal.index()],
            metrics,
        );
        facts.cells += terminal_facts.cells;
        facts.glyph_cells += terminal_facts.glyph_cells;
        facts.cursors += @intFromBool(terminal_facts.cursor);
    }
    return facts;
}

fn terminalFacts(
    placement: layout.Placement,
    snapshot: terminal.Snapshot,
    metrics: howl_text.Metrics,
) Error!TerminalFacts {
    const cell_size = terminal.CellSize{
        .width = metrics.cell_width,
        .height = metrics.cell_height,
    };
    if (!terminal.matchesPlacement(&snapshot, placement, cell_size))
        return error.invalid_terminal_snapshot;
    const cols = snapshot.cols;
    const rows = snapshot.rows;
    var glyph_cells: usize = 0;
    for (0..rows) |row| for (0..cols) |col| {
        const cell = snapshot.visible()[row * cols + col];
        if (cell.width == 0 or cell.height == 0 or
            cell.combining_len > terminal.max_combining or
            cell.x >= cell.width or cell.y >= cell.height)
            return error.invalid_terminal_snapshot;
        if (cell.x != 0 or cell.y != 0) continue;
        if (col + cell.width > cols or row + cell.height > rows)
            return error.invalid_terminal_snapshot;
        if (cell.codepoint == 0) continue;
        glyph_cells += 1;
    };
    return .{
        .cells = @as(usize, rows) * cols,
        .glyph_cells = glyph_cells,
        .cursor = snapshot.cursor_visible and
            snapshot.cursor_row < rows and snapshot.cursor_col < cols,
    };
}

fn cellColors(
    snapshot: terminal.Snapshot,
    cell: terminal.Cell,
    cursor_here: bool,
) CellColors {
    var foreground = cell.foreground;
    var background = cell.background;
    if (cursor_here and snapshot.cursor_shape == .block) {
        foreground = snapshot.cursor_text_color;
        background = snapshot.cursor_color;
    }
    return .{
        .foreground = rgbFloats(foreground),
        .background = rgbFloats(background),
        .underline = rgbFloats(cell.underline_color),
        // Kitty's default DIM intensity is 0.4; applying it to mask opacity
        // preserves correct compositing over the resolved cell background.
        .foreground_opacity = if (cell.dim) 0.4 else 1.0,
        .visible = !cell.invisible,
    };
}

fn rgbFloats(value: howl_vt.Terminal.Rgb) [3]f32 {
    return .{
        @as(f32, @floatFromInt(value.r)) / 255.0,
        @as(f32, @floatFromInt(value.g)) / 255.0,
        @as(f32, @floatFromInt(value.b)) / 255.0,
    };
}

fn appendDecorations(
    vertices: []Vertex,
    count: *usize,
    cell: terminal.Cell,
    x: i32,
    y: i32,
    cell_width: u16,
    metrics: howl_text.Metrics,
    clip: layout.Rect,
    size: layout.Size,
    texture: [4]f32,
    underline_color: [3]f32,
    foreground_color: [3]f32,
) Error!void {
    const width = std.math.mul(u16, cell_width, cell.width) catch
        return error.invalid_terminal_snapshot;
    if (cell.underline) switch (cell.underline_style) {
        .straight => try appendLine(
            vertices,
            count,
            x,
            y + metrics.underline_y,
            width,
            metrics.underline_height,
            clip,
            size,
            texture,
            underline_color,
            if (cell.dim) 0.4 else 1.0,
        ),
        .double => {
            const upper = metrics.underline_y -| metrics.underline_height -| 1;
            try appendLine(
                vertices,
                count,
                x,
                y + upper,
                width,
                metrics.underline_height,
                clip,
                size,
                texture,
                underline_color,
                if (cell.dim) 0.4 else 1.0,
            );
            try appendLine(
                vertices,
                count,
                x,
                y + metrics.underline_y,
                width,
                metrics.underline_height,
                clip,
                size,
                texture,
                underline_color,
                if (cell.dim) 0.4 else 1.0,
            );
        },
        .curly => try appendSegments(
            vertices,
            count,
            x,
            y + metrics.underline_y,
            width,
            metrics.underline_height,
            4,
            true,
            clip,
            size,
            texture,
            underline_color,
            if (cell.dim) 0.4 else 1.0,
        ),
        .dotted => try appendSegments(
            vertices,
            count,
            x,
            y + metrics.underline_y,
            width,
            metrics.underline_height,
            4,
            false,
            clip,
            size,
            texture,
            underline_color,
            if (cell.dim) 0.4 else 1.0,
        ),
        .dashed => try appendSegments(
            vertices,
            count,
            x,
            y + metrics.underline_y,
            width,
            metrics.underline_height,
            3,
            false,
            clip,
            size,
            texture,
            underline_color,
            if (cell.dim) 0.4 else 1.0,
        ),
    };
    if (cell.strikethrough)
        try appendLine(
            vertices,
            count,
            x,
            y + metrics.strike_y,
            width,
            metrics.strike_height,
            clip,
            size,
            texture,
            foreground_color,
            if (cell.dim) 0.4 else 1.0,
        );
}

fn appendLine(
    vertices: []Vertex,
    count: *usize,
    x: i32,
    y: i32,
    width: u16,
    height: u16,
    clip: layout.Rect,
    size: layout.Size,
    texture: [4]f32,
    color: [3]f32,
    opacity: f32,
) Error!void {
    try appendQuad(
        vertices,
        count,
        .{ .x = x, .y = y, .width = width, .height = height },
        clip,
        size,
        texture,
        color,
        opacity,
    );
}

fn appendSegments(
    vertices: []Vertex,
    count: *usize,
    x: i32,
    y: i32,
    width: u16,
    height: u16,
    segment_count: u8,
    wave: bool,
    clip: layout.Rect,
    size: layout.Size,
    texture: [4]f32,
    color: [3]f32,
    opacity: f32,
) Error!void {
    for (0..segment_count) |index| {
        const left: u16 = @intCast(@as(u32, width) * index / segment_count);
        const right: u16 = @intCast(@as(u32, width) * (index + 1) /
            segment_count);
        const segment_width = @max(@as(u16, 1), (right -| left) / 2);
        try appendLine(
            vertices,
            count,
            x + left,
            y + if (wave and index % 2 == 1) height else 0,
            segment_width,
            height,
            clip,
            size,
            texture,
            color,
            opacity,
        );
    }
}

fn appendQuad(
    vertices: []Vertex,
    count: *usize,
    rect: PixelRect,
    clip: layout.Rect,
    size: layout.Size,
    texture: [4]f32,
    color: [3]f32,
    opacity: f32,
) Error!void {
    const rect_right = @as(i64, rect.x) + rect.width;
    const rect_bottom = @as(i64, rect.y) + rect.height;
    const clip_right = @as(i64, clip.x) + clip.width;
    const clip_bottom = @as(i64, clip.y) + clip.height;
    const clipped_left = @max(@as(i64, rect.x), clip.x);
    const clipped_top = @max(@as(i64, rect.y), clip.y);
    const clipped_right = @min(rect_right, clip_right);
    const clipped_bottom = @min(rect_bottom, clip_bottom);
    if (clipped_left >= clipped_right or clipped_top >= clipped_bottom) return;
    if (count.* + 6 > vertices.len) return error.vertex_limit;
    const width: f32 = @floatFromInt(size.width);
    const height: f32 = @floatFromInt(size.height);
    const left = @as(f32, @floatFromInt(clipped_left)) / width * 2.0 - 1.0;
    const right = @as(f32, @floatFromInt(clipped_right)) / width * 2.0 - 1.0;
    const top = 1.0 - @as(f32, @floatFromInt(clipped_top)) / height * 2.0;
    const bottom = 1.0 - @as(f32, @floatFromInt(clipped_bottom)) / height * 2.0;
    const x_fraction_left = @as(f32, @floatFromInt(clipped_left - @as(i64, rect.x))) /
        @as(f32, @floatFromInt(rect.width));
    const x_fraction_right = @as(f32, @floatFromInt(clipped_right - @as(i64, rect.x))) /
        @as(f32, @floatFromInt(rect.width));
    const y_fraction_top = @as(f32, @floatFromInt(clipped_top - @as(i64, rect.y))) /
        @as(f32, @floatFromInt(rect.height));
    const y_fraction_bottom = @as(f32, @floatFromInt(clipped_bottom - @as(i64, rect.y))) /
        @as(f32, @floatFromInt(rect.height));
    const u_left = texture[0] + (texture[2] - texture[0]) * x_fraction_left;
    const u_right = texture[0] + (texture[2] - texture[0]) * x_fraction_right;
    const v_top = texture[1] + (texture[3] - texture[1]) * y_fraction_top;
    const v_bottom = texture[1] + (texture[3] - texture[1]) * y_fraction_bottom;
    const values = [6][4]f32{
        .{ left, top, u_left, v_top },
        .{ left, bottom, u_left, v_bottom },
        .{ right, bottom, u_right, v_bottom },
        .{ left, top, u_left, v_top },
        .{ right, bottom, u_right, v_bottom },
        .{ right, top, u_right, v_top },
    };
    for (values) |value| {
        vertices[count.*] = .{
            .x = value[0],
            .y = value[1],
            .u = value[2],
            .v = value[3],
            .red = color[0],
            .green = color[1],
            .blue = color[2],
            .opacity = opacity,
        };
        count.* += 1;
    }
}

const Device = union(enum) {
    native: Native,
    transcript: *Transcript,

    fn init(allocator: std.mem.Allocator, source: Source) StartError!Device {
        return switch (source) {
            .native => |values| .{ .native = try .init(allocator, values) },
            .transcript => |values| initialized: {
                try values.transcript.consume(.{ .initialize = .{
                    .size = values.size,
                    .metrics = values.metric_values,
                } });
                break :initialized .{ .transcript = values.transcript };
            },
        };
    }

    fn metrics(self: *const Device, source: Source) howl_text.Metrics {
        return switch (self.*) {
            .native => |native| native.text.metrics,
            .transcript => source.transcript.metric_values,
        };
    }

    fn draw(self: *Device, frame: Frame) Error!void {
        switch (self.*) {
            .native => |*native| try native.draw(frame),
            .transcript => |transcript| try transcript.consume(.{
                .frame = recordFrame(frame),
            }),
        }
    }

    fn deinit(self: *Device) Error!void {
        switch (self.*) {
            .native => |*native| try native.deinit(),
            .transcript => |transcript| try transcript.consume(.cleanup),
        }
    }
};

const Frames = struct {
    pending: ?Frame = null,
    completed_generation: u64 = 0,

    fn publish(self: *Frames, frame: Frame) Error!void {
        if (frame.generation <= self.completed_generation) return error.stale_generation;
        if (self.pending) |pending| {
            if (frame.generation <= pending.generation) return error.stale_generation;
        }
        self.pending = frame;
    }

    fn take(self: *Frames) ?Frame {
        const pending = self.pending;
        self.pending = null;
        return pending;
    }

    fn complete(self: *Frames, generation: u64) void {
        std.debug.assert(generation > self.completed_generation);
        self.completed_generation = generation;
    }
};

/// Owns one render thread, one coalesced frame, and exact startup/shutdown state.
pub const Render = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    condition: std.Io.Condition = .init,
    thread: std.Thread,
    source: Source,
    frames: Frames = .{},
    stopping: bool = false,
    started: bool = false,
    failure: ?Error = null,
    startup_failure: ?StartError = null,
    metrics_value: howl_text.Metrics = undefined,
    signal_fd: c_int,

    /// Starts the native EGL/GLES owner and waits for context initialization.
    pub fn startNative(
        allocator: std.mem.Allocator,
        io: std.Io,
        values: NativeInit,
    ) StartError!*Render {
        return start(allocator, io, .{ .native = values });
    }

    /// Starts a strict deterministic render owner for lifecycle simulation.
    fn startTranscript(
        allocator: std.mem.Allocator,
        io: std.Io,
        transcript: *Transcript,
        size: layout.Size,
        metric_values: howl_text.Metrics,
    ) StartError!*Render {
        return start(allocator, io, .{ .transcript = .{
            .transcript = transcript,
            .size = size,
            .metric_values = metric_values,
        } });
    }

    fn start(allocator: std.mem.Allocator, io: std.Io, source: Source) StartError!*Render {
        const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (signal_fd < 0) return error.render_signal_failed;
        errdefer closeRollback(signal_fd);
        const self = try allocator.create(Render);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .thread = undefined,
            .source = source,
            .signal_fd = signal_fd,
        };
        self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
        self.mutex.lockUncancelable(self.io);
        while (!self.started) self.condition.waitUncancelable(self.io, &self.mutex);
        const failure = self.startup_failure;
        self.mutex.unlock(self.io);
        if (failure) |cause| {
            self.thread.join();
            return cause;
        }
        return self;
    }

    /// Copies immutable font-derived geometry after render-thread startup.
    pub fn metrics(self: *const Render) howl_text.Metrics {
        return self.metrics_value;
    }

    /// Returns the event descriptor signaled after frame completion or failure.
    pub fn signalFd(self: *const Render) c_int {
        return self.signal_fd;
    }

    /// Publishes a newer complete frame, replacing an unconsumed older frame.
    pub fn submit(
        self: *Render,
        generation: u64,
        snapshot: layout.Snapshot,
        terminals: [layout.terminal_count]terminal.Snapshot,
    ) Error!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.render_stopping;
        try self.frames.publish(.{
            .generation = generation,
            .layout = snapshot,
            .terminals = terminals,
        });
        self.condition.signal(self.io);
    }

    /// Drains the completion signal and returns any render-thread failure.
    pub fn completed(self: *Render) Error!void {
        var value: u64 = 0;
        const count = c.read(self.signal_fd, &value, @sizeOf(u64));
        if (count != @sizeOf(u64) and
            !(count < 0 and std.posix.errno(count) == .AGAIN))
            return error.render_signal_failed;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
    }

    /// Stops, joins, and releases the render owner exactly once.
    pub fn deinit(self: *Render) Error!void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
        self.thread.join();
        const failure = self.failure;
        const close_failed = c.close(self.signal_fd) != 0;
        const allocator = self.allocator;
        allocator.destroy(self);
        if (failure) |cause| return cause;
        if (close_failed) return error.render_signal_failed;
    }

    fn threadMain(self: *Render) void {
        var device = Device.init(self.allocator, self.source) catch |failure| {
            self.finishStart(failure);
            return;
        };
        self.finishStartSuccess(device.metrics(self.source));
        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (self.frames.pending == null and !self.stopping)
                self.condition.waitUncancelable(self.io, &self.mutex);
            if (self.stopping) {
                self.mutex.unlock(self.io);
                break;
            }
            const frame = self.frames.take().?;
            self.mutex.unlock(self.io);

            device.draw(frame) catch |failure| {
                self.setFailure(failure);
                break;
            };
            self.mutex.lockUncancelable(self.io);
            self.frames.complete(frame.generation);
            self.mutex.unlock(self.io);
            self.signal();
        }
        device.deinit() catch |failure| self.setFailure(failure);
    }

    fn finishStart(self: *Render, failure: StartError) void {
        self.mutex.lockUncancelable(self.io);
        self.startup_failure = failure;
        self.started = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
    }

    fn finishStartSuccess(self: *Render, metric_values: howl_text.Metrics) void {
        self.mutex.lockUncancelable(self.io);
        self.metrics_value = metric_values;
        self.started = true;
        self.condition.signal(self.io);
        self.mutex.unlock(self.io);
    }

    fn setFailure(self: *Render, failure: Error) void {
        self.mutex.lockUncancelable(self.io);
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
        self.signal();
    }

    fn signal(self: *Render) void {
        const value: u64 = 1;
        const count = c.write(self.signal_fd, &value, @sizeOf(u64));
        if (count != @sizeOf(u64) and
            !(count < 0 and std.posix.errno(count) == .AGAIN))
        {
            self.mutex.lockUncancelable(self.io);
            if (self.failure == null) self.failure = error.render_signal_failed;
            self.mutex.unlock(self.io);
        }
    }
};

fn terminateRollback(display: c.EGLDisplay) void {
    // Initialization rollback has no surviving owner to receive teardown errors.
    if (c.eglTerminate(display) != c.EGL_TRUE)
        @panic("EGL rejected an owned display during rollback");
}

fn destroyContextRollback(display: c.EGLDisplay, context: c.EGLContext) void {
    // Initialization rollback has no surviving owner to receive teardown errors.
    if (c.eglDestroyContext(display, context) != c.EGL_TRUE)
        @panic("EGL rejected an owned context during rollback");
}

fn destroySurfaceRollback(display: c.EGLDisplay, surface: c.EGLSurface) void {
    // Initialization rollback has no surviving owner to receive teardown errors.
    if (c.eglDestroySurface(display, surface) != c.EGL_TRUE)
        @panic("EGL rejected an owned surface during rollback");
}

fn releaseCurrentRollback(display: c.EGLDisplay) void {
    // Rollback releases thread ownership before destroying its EGL objects.
    if (c.eglMakeCurrent(
        display,
        c.EGL_NO_SURFACE,
        c.EGL_NO_SURFACE,
        c.EGL_NO_CONTEXT,
    ) != c.EGL_TRUE) @panic("EGL rejected current-context release during rollback");
}

fn closeRollback(fd: c_int) void {
    // The descriptor has no surviving owner after initialization rollback.
    if (c.close(fd) != 0)
        @panic("Linux rejected an owned render descriptor during rollback");
}

fn recordFrame(frame: Frame) FrameRecord {
    var terminals: [layout.terminal_count]TerminalRecord = undefined;
    for (frame.terminals, 0..) |snapshot, index| terminals[index] = .{
        .terminal = snapshot.terminal,
        .generation = snapshot.generation,
        .rows = snapshot.rows,
        .cols = snapshot.cols,
        .count = snapshot.count,
    };
    return .{
        .generation = frame.generation,
        .layout = frame.layout,
        .terminals = terminals,
    };
}

test "one frame slot retains only the newest complete generation" {
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 24 });
    var frames = Frames{};
    const first = try value.snapshot();
    const terminals = testTerminals();
    try frames.publish(.{ .generation = 1, .layout = first, .terminals = terminals });
    const second = try value.selectTab(1);
    try frames.publish(.{ .generation = 2, .layout = second, .terminals = terminals });
    try std.testing.expectError(
        error.stale_generation,
        frames.publish(.{ .generation = 1, .layout = first, .terminals = terminals }),
    );
    try std.testing.expectEqualDeep(second, frames.take().?.layout);
    frames.complete(second.generation);
    try std.testing.expectError(
        error.stale_generation,
        frames.publish(.{ .generation = 2, .layout = second, .terminals = terminals }),
    );
}

test "batch facts include active split text and cursor while excluding hidden tab" {
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const split = try value.snapshot();
    var terminals = testTerminalsFor(split, test_metrics);
    terminals[0].cells[0] = .{ .codepoint = 'A', .width = 1 };
    terminals[1].cells[0] = .{ .codepoint = 0x2500, .width = 1 };
    terminals[1].cursor_visible = false;
    terminals[2].rows = 0;
    const split_facts = try batchFacts(.{
        .generation = 1,
        .layout = split,
        .terminals = terminals,
    }, test_metrics);
    try std.testing.expectEqual(@as(u2, 2), split_facts.terminals);
    try std.testing.expect(split_facts.cells > split_facts.glyph_cells);
    try std.testing.expectEqual(@as(usize, 2), split_facts.glyph_cells);
    try std.testing.expectEqual(@as(u2, 1), split_facts.cursors);

    const single = try value.selectTab(1);
    terminals = testTerminalsFor(single, test_metrics);
    terminals[0].rows = 0;
    terminals[1].rows = 0;
    terminals[2].cells[0] = .{ .codepoint = 'B', .width = 1 };
    const single_facts = try batchFacts(.{
        .generation = 2,
        .layout = single,
        .terminals = terminals,
    }, test_metrics);
    try std.testing.expectEqual(@as(u2, 1), single_facts.terminals);
    try std.testing.expectEqual(@as(usize, 1), single_facts.glyph_cells);
}

test "batch facts reject mismatched geometry and invalid wide-cell bounds" {
    const value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 32 });
    const snapshot = try value.snapshot();
    var terminals = testTerminalsFor(snapshot, test_metrics);
    terminals[0].cols += 1;
    try std.testing.expectError(error.invalid_terminal_snapshot, batchFacts(.{
        .generation = 1,
        .layout = snapshot,
        .terminals = terminals,
    }, test_metrics));
    terminals = testTerminalsFor(snapshot, test_metrics);
    terminals[0].cells[terminals[0].cols - 1] = .{ .codepoint = 'W', .width = 2 };
    try std.testing.expectError(error.invalid_terminal_snapshot, batchFacts(.{
        .generation = 1,
        .layout = snapshot,
        .terminals = terminals,
    }, test_metrics));

    terminals = testTerminalsFor(snapshot, test_metrics);
    terminals[0].cells[0] = .{ .codepoint = 'W', .width = 2 };
    terminals[0].cells[1] = .{
        .codepoint = 0,
        .width = 2,
        .x = 1,
    };
    const continuation = try batchFacts(.{
        .generation = 1,
        .layout = snapshot,
        .terminals = terminals,
    }, test_metrics);
    try std.testing.expectEqual(@as(usize, 1), continuation.glyph_cells);
}

test "resolved presentation preserves background and cursor precedence" {
    var snapshot = testTerminals()[0];
    snapshot.cursor_color = .{ .r = 1, .g = 2, .b = 3 };
    snapshot.cursor_text_color = .{ .r = 4, .g = 5, .b = 6 };
    const cell = terminal.Cell{
        .codepoint = 'A',
        .width = 1,
        .foreground = .{ .r = 10, .g = 20, .b = 30 },
        .background = .{ .r = 40, .g = 50, .b = 60 },
        .underline_color = .{ .r = 70, .g = 80, .b = 90 },
        .dim = true,
        .invisible = true,
    };
    const ordinary = cellColors(snapshot, cell, false);
    try std.testing.expectEqual(rgbFloats(cell.foreground), ordinary.foreground);
    try std.testing.expectEqual(rgbFloats(cell.background), ordinary.background);
    try std.testing.expectEqual(@as(f32, 0.4), ordinary.foreground_opacity);
    try std.testing.expect(!ordinary.visible);

    const cursor = cellColors(snapshot, cell, true);
    try std.testing.expectEqual(
        rgbFloats(snapshot.cursor_text_color),
        cursor.foreground,
    );
    try std.testing.expectEqual(
        rgbFloats(snapshot.cursor_color),
        cursor.background,
    );
}

test "every retained underline style has bounded distinct geometry" {
    const styles = [_]struct {
        style: howl_vt.Terminal.UnderlineStyle,
        quads: usize,
    }{
        .{ .style = .straight, .quads = 1 },
        .{ .style = .double, .quads = 2 },
        .{ .style = .curly, .quads = 4 },
        .{ .style = .dotted, .quads = 4 },
        .{ .style = .dashed, .quads = 3 },
    };
    for (styles) |case| {
        var vertices: [max_decoration_quads * 6]Vertex = undefined;
        var count: usize = 0;
        try appendDecorations(
            &vertices,
            &count,
            .{
                .codepoint = 'A',
                .width = 1,
                .underline = true,
                .underline_style = case.style,
                .strikethrough = true,
            },
            0,
            0,
            test_metrics.cell_width,
            test_metrics,
            .{
                .x = 0,
                .y = 0,
                .width = test_metrics.cell_width,
                .height = test_metrics.cell_height,
            },
            .{
                .width = test_metrics.cell_width,
                .height = test_metrics.cell_height,
            },
            .{ 0, 0, 1, 1 },
            .{ 1, 1, 1 },
            .{ 1, 1, 1 },
        );
        try std.testing.expectEqual((case.quads + 1) * 6, count);
    }
}

test "render transcript proves frame cleanup and successful reuse" {
    var value = try layout.Layout.init(.horizontal, .{ .width = 80, .height = 24 });
    const snapshot = try value.snapshot();
    const steps = [_]Step{
        .{ .operation = .{ .initialize = .{
            .size = snapshot.size,
            .metrics = test_metrics,
        } } },
        .{ .operation = .{ .frame = testFrameRecord(
            snapshot.generation,
            snapshot,
        ) } },
        .{ .operation = .cleanup },
    };
    var transcript = Transcript{ .steps = &steps };
    const owner = try Render.startTranscript(
        std.testing.allocator,
        std.testing.io,
        &transcript,
        snapshot.size,
        test_metrics,
    );
    try owner.submit(snapshot.generation, snapshot, testTerminals());
    try wait(owner);
    try owner.deinit();
    try transcript.finish();

    value = try layout.Layout.init(.vertical, .{ .width = 100, .height = 40 });
    const reused = try value.snapshot();
    const reuse_steps = [_]Step{
        .{ .operation = .{ .initialize = .{
            .size = reused.size,
            .metrics = test_metrics,
        } } },
        .{ .operation = .{ .frame = testFrameRecord(
            reused.generation,
            reused,
        ) } },
        .{ .operation = .cleanup },
    };
    var reuse = Transcript{ .steps = &reuse_steps };
    const second = try Render.startTranscript(
        std.testing.allocator,
        std.testing.io,
        &reuse,
        reused.size,
        test_metrics,
    );
    try second.submit(reused.generation, reused, testTerminals());
    try wait(second);
    try second.deinit();
    try reuse.finish();
}

test "render startup and frame failures clean up exactly" {
    const size = layout.Size{ .width = 80, .height = 24 };
    const init_steps = [_]Step{
        .{
            .operation = .{ .initialize = .{
                .size = size,
                .metrics = test_metrics,
            } },
            .failure = error.egl_context_failed,
        },
    };
    var init_failure = Transcript{ .steps = &init_steps };
    try std.testing.expectError(
        error.egl_context_failed,
        Render.startTranscript(
            std.testing.allocator,
            std.testing.io,
            &init_failure,
            size,
            test_metrics,
        ),
    );
    try init_failure.finish();

    for ([_]Error{
        error.upload_failed,
        error.draw_failed,
        error.swap_failed,
    }) |failure| try expectFrameFailure(size, failure);
}

test "render owner rolls back every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        ownerAllocation,
        .{},
    );
}

fn ownerAllocation(allocator: std.mem.Allocator) !void {
    const size = layout.Size{ .width = 80, .height = 24 };
    const steps = [_]Step{
        .{ .operation = .{ .initialize = .{
            .size = size,
            .metrics = test_metrics,
        } } },
        .{ .operation = .cleanup },
    };
    var transcript = Transcript{ .steps = &steps };
    const owner = try Render.startTranscript(
        allocator,
        std.testing.io,
        &transcript,
        size,
        test_metrics,
    );
    try owner.deinit();
    try transcript.finish();
}

fn expectFrameFailure(size: layout.Size, failure: Error) !void {
    const value = try layout.Layout.init(.horizontal, size);
    const snapshot = try value.snapshot();
    const steps = [_]Step{
        .{ .operation = .{ .initialize = .{
            .size = size,
            .metrics = test_metrics,
        } } },
        .{
            .operation = .{ .frame = testFrameRecord(
                snapshot.generation,
                snapshot,
            ) },
            .failure = failure,
        },
        .{ .operation = .cleanup },
    };
    var transcript = Transcript{ .steps = &steps };
    const owner = try Render.startTranscript(
        std.testing.allocator,
        std.testing.io,
        &transcript,
        size,
        test_metrics,
    );
    try owner.submit(snapshot.generation, snapshot, testTerminals());
    try std.testing.expectError(failure, wait(owner));
    try std.testing.expectError(failure, owner.deinit());
    try transcript.finish();
}

fn wait(owner: *Render) Error!void {
    var fds = [_]std.posix.pollfd{.{
        .fd = owner.signalFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = std.posix.poll(&fds, 5_000) catch return error.render_signal_failed;
    if (ready == 0) return error.render_signal_failed;
    return owner.completed();
}

fn testTerminals() [layout.terminal_count]terminal.Snapshot {
    var values: [layout.terminal_count]terminal.Snapshot = undefined;
    for (std.enums.values(layout.TerminalId)) |id| values[id.index()] = .{
        .terminal = id,
        .generation = 1,
        .rows = 1,
        .cols = 1,
        .cursor_row = 0,
        .cursor_col = 0,
        .cursor_visible = true,
        .count = 1,
        .cells = .{terminal.Cell{ .codepoint = 0, .width = 1 }} **
            (@as(usize, terminal.max_cols) * terminal.max_rows),
    };
    return values;
}

fn testFrameRecord(generation: u64, snapshot: layout.Snapshot) FrameRecord {
    var terminals: [layout.terminal_count]TerminalRecord = undefined;
    for (std.enums.values(layout.TerminalId)) |id| terminals[id.index()] = .{
        .terminal = id,
        .generation = 1,
        .rows = 1,
        .cols = 1,
        .count = 1,
    };
    return .{
        .generation = generation,
        .layout = snapshot,
        .terminals = terminals,
    };
}

fn testTerminalsFor(
    snapshot: layout.Snapshot,
    metrics: howl_text.Metrics,
) [layout.terminal_count]terminal.Snapshot {
    var values = testTerminals();
    for (snapshot.visible()) |placement| {
        const cols = @max(@as(u16, 1), placement.rect.width / metrics.cell_width);
        const rows = @max(@as(u16, 1), placement.rect.height / metrics.cell_height);
        const value = &values[placement.terminal.index()];
        value.cols = cols;
        value.rows = rows;
        value.count = @intCast(@as(usize, cols) * rows);
    }
    return values;
}

const test_metrics = howl_text.Metrics{
    .cell_width = 8,
    .cell_height = 16,
    .baseline = 12,
    .underline_y = 14,
    .underline_height = 1,
    .strike_y = 8,
    .strike_height = 1,
};
