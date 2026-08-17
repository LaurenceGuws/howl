//! Adds retained native-label production to the canonical Chrome contract.

const std = @import("std");
const canonical = @import("chrome_impl");
const canvas = @import("canvas");
const text = @import("howl_text");

/// Projects canonical Chrome failures directly.
pub const Error = canonical.Error;
/// Projects canonical stable tab identity directly.
pub const TabId = canonical.TabId;
/// Projects canonical stable pane identity directly.
pub const PaneId = canonical.PaneId;
/// Projects canonical Canvas surface extent directly.
pub const Size = canonical.Size;
/// Projects canonical Canvas rectangles directly.
pub const Rect = canonical.Rect;
/// Projects canonical Canvas colors directly.
pub const Color = canonical.Color;
/// Projects canonical Chrome style directly.
pub const Style = canonical.Style;
/// Projects canonical immutable tab descriptions directly.
pub const Tab = canonical.Tab;
/// Projects canonical pane layers directly.
pub const PaneLayer = canonical.PaneLayer;
/// Projects canonical scroll state directly.
pub const Scroll = canonical.Scroll;
/// Projects canonical immutable pane descriptions directly.
pub const Pane = canonical.Pane;
/// Projects canonical caller-owned selection directly.
pub const Selection = canonical.Selection;
/// Projects canonical complete Chrome input directly.
pub const Input = canonical.Input;
/// Projects canonical hit-test points directly.
pub const Point = canonical.Point;
/// Projects canonical hit identities directly.
pub const Hit = canonical.Hit;
/// Projects canonical border ownership directly.
pub const BorderEdges = canonical.BorderEdges;
/// Projects canonical Chrome primitives directly.
pub const Primitive = canonical.Primitive;
/// Projects canonical complete Chrome output directly.
pub const Output = canonical.Output;
/// Projects canonical stateless Chrome projection directly.
pub const project = canonical.project;
/// Projects canonical stateless Chrome hit testing directly.
pub const hitTest = canonical.hitTest;

const GlyphKey = struct {
    face: u8,
    glyph: u32,
};

const GlyphEntry = struct {
    key: GlyphKey,
    resource: ?canvas.ResourceRef,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

/// Retains one copied complete Chrome output and transfers Canvas updates.
pub const Content = struct {
    /// Fixes every retained and synchronous work ceiling at initialization.
    pub const Limits = struct {
        /// Bounds copied canonical primitives in each state bank.
        primitives: usize,
        /// Bounds copied label bytes in each state bank.
        text_bytes: usize,
        /// Bounds decoded scalars in one label.
        label_scalars: usize,
        /// Bounds shaped glyphs in one label.
        shaped_glyphs: usize,
        /// Bounds currently referenced native glyph resources.
        glyphs: usize,
        /// Bounds complete ordered Canvas commands.
        commands: usize,
        /// Bounds uploads and removals in one transferred update.
        resources_per_update: usize,
        /// Bounds copied alpha bytes in one transferred update.
        upload_bytes: usize,
        /// Bounds one temporary native raster.
        raster_bytes: usize,
    };

    /// Reports invalid fixed bounds, font construction, or allocation failure.
    pub const InitError = error{
        InvalidLimits,
        OutOfMemory,
    } || text.InitError || text.ShapeBufferInitError;

    /// Reports malformed or over-capacity complete Chrome state.
    pub const ApplyError = error{
        InvalidOutput,
        PrimitiveLimit,
        TextLimit,
        IdentityExhausted,
        ArithmeticOverflow,
    };

    /// Reports shaping, rasterization, or transfer-capacity failure.
    pub const TakeError = error{
        InvalidState,
        InvalidOutput,
        CommandLimit,
        GlyphLimit,
        ResourceMutationLimit,
        UploadByteLimit,
        IdentityExhausted,
        ArithmeticOverflow,
        OutOfMemory,
    } || text.ShapeError || text.RasterError;

    allocator: std.mem.Allocator,
    limits: Limits,
    fonts: *text.FontSet,
    shape: *text.ShapeBuffer,
    primitives_a: []Primitive,
    primitives_b: []Primitive,
    text_a: []u8,
    text_b: []u8,
    state_a_active: bool = true,
    primitive_count: usize = 0,
    text_count: usize = 0,
    surface: Size = .{ .width = 0, .height = 0 },
    initialized: bool = false,
    glyphs: []GlyphEntry,
    glyph_candidates: []GlyphEntry,
    glyph_count: usize = 0,
    glyph_candidate_count: usize = 0,
    codepoints: []u32,
    clusters: []u32,
    shaped: []text.Glyph,
    inputs: []canvas.Input,
    input_count: usize = 0,
    uploads: []canvas.ResourceUpload,
    upload_pixels: []u8,
    removals: []canvas.ResourceRemoval,
    raster_arena: []u8,
    next_resource_id: u64 = 1,
    producer_revision: u64 = 1,

    /// Copies the font configuration and allocates every retained, candidate,
    /// shaping, raster, command, and resource-transfer bound.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: Limits,
        font: text.Config,
    ) InitError!Content {
        try validateLimits(limits);
        const primitives_a = allocator.alloc(Primitive, limits.primitives) catch
            return error.OutOfMemory;
        errdefer allocator.free(primitives_a);
        const primitives_b = allocator.alloc(Primitive, limits.primitives) catch
            return error.OutOfMemory;
        errdefer allocator.free(primitives_b);
        const text_a = allocator.alloc(u8, limits.text_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(text_a);
        const text_b = allocator.alloc(u8, limits.text_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(text_b);
        const glyphs = allocator.alloc(GlyphEntry, limits.glyphs) catch
            return error.OutOfMemory;
        errdefer allocator.free(glyphs);
        const glyph_candidates = allocator.alloc(GlyphEntry, limits.glyphs) catch
            return error.OutOfMemory;
        errdefer allocator.free(glyph_candidates);
        const codepoints = allocator.alloc(u32, limits.label_scalars) catch
            return error.OutOfMemory;
        errdefer allocator.free(codepoints);
        const clusters = allocator.alloc(u32, limits.label_scalars) catch
            return error.OutOfMemory;
        errdefer allocator.free(clusters);
        const shaped = allocator.alloc(text.Glyph, limits.shaped_glyphs) catch
            return error.OutOfMemory;
        errdefer allocator.free(shaped);
        const inputs = allocator.alloc(canvas.Input, limits.commands) catch
            return error.OutOfMemory;
        errdefer allocator.free(inputs);
        const uploads = allocator.alloc(
            canvas.ResourceUpload,
            limits.resources_per_update,
        ) catch return error.OutOfMemory;
        errdefer allocator.free(uploads);
        const upload_pixels = allocator.alloc(u8, limits.upload_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(upload_pixels);
        const removals = allocator.alloc(
            canvas.ResourceRemoval,
            limits.resources_per_update,
        ) catch return error.OutOfMemory;
        errdefer allocator.free(removals);
        const raster_arena = allocator.alloc(u8, limits.raster_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(raster_arena);
        const fonts = try text.FontSet.init(allocator, font);
        errdefer fonts.deinit();
        const shape = try text.ShapeBuffer.init(allocator, @intCast(limits.shaped_glyphs));
        errdefer shape.deinit();
        return .{
            .allocator = allocator,
            .limits = limits,
            .fonts = fonts,
            .shape = shape,
            .primitives_a = primitives_a,
            .primitives_b = primitives_b,
            .text_a = text_a,
            .text_b = text_b,
            .glyphs = glyphs,
            .glyph_candidates = glyph_candidates,
            .codepoints = codepoints,
            .clusters = clusters,
            .shaped = shaped,
            .inputs = inputs,
            .uploads = uploads,
            .upload_pixels = upload_pixels,
            .removals = removals,
            .raster_arena = raster_arena,
        };
    }

    /// Releases native owners and every allocation in reverse ownership order.
    pub fn deinit(self: *Content) void {
        self.shape.deinit();
        self.fonts.deinit();
        self.allocator.free(self.raster_arena);
        self.allocator.free(self.removals);
        self.allocator.free(self.upload_pixels);
        self.allocator.free(self.uploads);
        self.allocator.free(self.inputs);
        self.allocator.free(self.shaped);
        self.allocator.free(self.clusters);
        self.allocator.free(self.codepoints);
        self.allocator.free(self.glyph_candidates);
        self.allocator.free(self.glyphs);
        self.allocator.free(self.text_b);
        self.allocator.free(self.text_a);
        self.allocator.free(self.primitives_b);
        self.allocator.free(self.primitives_a);
        self.* = undefined;
    }

    /// Copies one complete immutable canonical output transactionally.
    ///
    /// Accepted caller storage may be released or reused immediately.
    pub fn apply(self: *Content, output: Output) ApplyError!void {
        try validateOutput(output);
        if (output.primitives.len > self.limits.primitives)
            return error.PrimitiveLimit;
        if (output.text.len > self.limits.text_bytes) return error.TextLimit;
        if (self.initialized and self.outputEqual(output)) return;
        if (self.producer_revision == std.math.maxInt(u64))
            return error.IdentityExhausted;

        const target_primitives = self.inactivePrimitives();
        const target_text = self.inactiveText();
        @memcpy(target_text[0..output.text.len], output.text);
        var text_used: usize = 0;
        for (output.primitives, 0..) |primitive, index| {
            target_primitives[index] = switch (primitive) {
                .fill => |value| .{ .fill = value },
                .border => |value| .{ .border = value },
                .scrollbar => |value| .{ .scrollbar = value },
                .label => |value| label: {
                    const end = std.math.add(usize, text_used, value.text.len) catch
                        return error.ArithmeticOverflow;
                    break :label .{ .label = .{
                        .rect = value.rect,
                        .text = target_text[text_used..end],
                        .color = value.color,
                    } };
                },
            };
            if (primitive == .label) text_used += primitive.label.text.len;
        }
        self.state_a_active = !self.state_a_active;
        self.primitive_count = output.primitives.len;
        self.text_count = output.text.len;
        self.surface = output.surface;
        self.initialized = true;
        self.producer_revision += 1;
    }

    /// Transfers complete Canvas commands and pending sparse glyph resources.
    ///
    /// The caller secures destination capacity before calling and copies or
    /// synchronously applies every returned slice before any later Content
    /// operation. A successful call consumes resource mutations and commits
    /// the candidate cache. Returned slices borrow Content storage.
    pub fn takeUpdate(self: *Content) TakeError!canvas.ProducerUpdate {
        if (!self.initialized) return error.InvalidState;
        self.input_count = 0;
        self.glyph_candidate_count = 0;
        var upload_count: usize = 0;
        var upload_bytes: usize = 0;
        var removal_count: usize = 0;
        const next_resource_before = self.next_resource_id;
        const revision_before = self.producer_revision;
        errdefer {
            self.input_count = 0;
            self.glyph_candidate_count = 0;
            self.next_resource_id = next_resource_before;
            self.producer_revision = revision_before;
        }
        for (self.activePrimitives()) |primitive| switch (primitive) {
            .fill => |value| try self.solid(value.rect, self.surfaceRect(), value.color),
            .border => |value| try self.border(value),
            .scrollbar => |value| {
                try self.solid(value.track, self.surfaceRect(), value.color);
                try self.solid(value.thumb, value.track, value.thumb_color);
            },
            .label => |value| try self.label(value, &upload_count, &upload_bytes),
        };
        const glyph_changed = try self.retireGlyphs(&removal_count);
        if (glyph_changed) try self.advanceRevision();
        std.mem.swap([]GlyphEntry, &self.glyphs, &self.glyph_candidates);
        self.glyph_count = self.glyph_candidate_count;
        self.glyph_candidate_count = 0;
        return .{
            .revision = @fromBackingInt(@intCast(self.producer_revision)),
            .uploads = self.uploads[0..upload_count],
            .removals = self.removals[0..removal_count],
            .commands = self.inputs[0..self.input_count],
        };
    }

    fn outputEqual(self: *const Content, output: Output) bool {
        if (!std.meta.eql(self.surface, output.surface) or
            self.primitive_count != output.primitives.len or
            self.text_count != output.text.len or
            !std.mem.eql(u8, self.activeText(), output.text))
            return false;
        for (self.activePrimitives(), output.primitives) |left, right| {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
            switch (left) {
                .fill => |value| if (!std.meta.eql(value, right.fill)) return false,
                .border => |value| if (!std.meta.eql(value, right.border)) return false,
                .scrollbar => |value| if (!std.meta.eql(value, right.scrollbar)) return false,
                .label => |value| {
                    if (!std.meta.eql(value.rect, right.label.rect) or
                        !std.meta.eql(value.color, right.label.color) or
                        !std.mem.eql(u8, value.text, right.label.text))
                        return false;
                },
            }
        }
        return true;
    }

    fn label(
        self: *Content,
        value: @FieldType(Primitive, "label"),
        upload_count: *usize,
        upload_bytes: *usize,
    ) TakeError!void {
        const scalar_count = try self.decode(value.text);
        const run = try self.fonts.shape(
            self.shape,
            .{
                .codepoints = self.codepoints[0..scalar_count],
                .clusters = self.clusters[0..scalar_count],
            },
            self.shaped,
        );
        var pen_x = @as(i64, value.rect.x) * 64;
        const baseline = (@as(i64, value.rect.y) + self.fonts.metrics().baseline) * 64;
        for (run.glyphs) |shaped_glyph| {
            const entry = try self.glyph(
                run.face_index,
                shaped_glyph.id,
                upload_count,
                upload_bytes,
            );
            if (entry.resource) |resource| {
                const x = std.math.add(
                    i64,
                    pen_x,
                    shaped_glyph.x_offset,
                ) catch return error.ArithmeticOverflow;
                const left = std.math.add(
                    i64,
                    x,
                    @as(i64, entry.left) * 64,
                ) catch return error.ArithmeticOverflow;
                const y = std.math.sub(
                    i64,
                    baseline,
                    shaped_glyph.y_offset,
                ) catch return error.ArithmeticOverflow;
                const top = std.math.sub(
                    i64,
                    y,
                    @as(i64, entry.top) * 64,
                ) catch return error.ArithmeticOverflow;
                try self.alpha(
                    .{
                        .x = try fixed26_6(left),
                        .y = try fixed26_6(top),
                        .width = entry.width,
                        .height = entry.height,
                    },
                    value.rect,
                    resource,
                    .{ .width = entry.width, .height = entry.height },
                    value.color,
                );
            }
            pen_x = std.math.add(i64, pen_x, shaped_glyph.x_advance) catch
                return error.ArithmeticOverflow;
        }
    }

    fn decode(self: *Content, bytes: []const u8) TakeError!usize {
        var byte_index: usize = 0;
        var count: usize = 0;
        while (byte_index < bytes.len) {
            if (count >= self.codepoints.len) return error.TextTooLong;
            const sequence = std.unicode.utf8ByteSequenceLength(bytes[byte_index]) catch
                return error.InvalidOutput;
            const end = std.math.add(usize, byte_index, sequence) catch
                return error.ArithmeticOverflow;
            if (end > bytes.len) return error.InvalidOutput;
            self.codepoints[count] = std.unicode.utf8Decode(bytes[byte_index..end]) catch
                return error.InvalidOutput;
            self.clusters[count] = std.math.cast(u32, byte_index) orelse
                return error.TextTooLong;
            count += 1;
            byte_index = end;
        }
        if (count == 0) return error.InvalidOutput;
        return count;
    }

    fn glyph(
        self: *Content,
        face: u8,
        glyph_id: u32,
        upload_count: *usize,
        upload_bytes: *usize,
    ) TakeError!*const GlyphEntry {
        const key = GlyphKey{ .face = face, .glyph = glyph_id };
        for (self.glyph_candidates[0..self.glyph_candidate_count]) |*entry|
            if (std.meta.eql(entry.key, key)) return entry;
        if (self.glyph_candidate_count >= self.glyph_candidates.len)
            return error.GlyphLimit;
        for (self.glyphs[0..self.glyph_count]) |entry| {
            if (!std.meta.eql(entry.key, key)) continue;
            self.glyph_candidates[self.glyph_candidate_count] = entry;
            self.glyph_candidate_count += 1;
            return &self.glyph_candidates[self.glyph_candidate_count - 1];
        }
        var fixed = std.heap.FixedBufferAllocator.init(self.raster_arena);
        var raster = try self.fonts.rasterize(
            fixed.allocator(),
            face,
            glyph_id,
            self.fonts.metrics().advance_width,
        );
        defer raster.deinit();
        const resource = if (raster.width == 0 or raster.height == 0)
            null
        else
            try self.issueResource();
        if (resource) |identity| try self.appendUpload(
            upload_count,
            upload_bytes,
            identity,
            raster.width,
            raster.height,
            raster.pixels,
        );
        self.glyph_candidates[self.glyph_candidate_count] = .{
            .key = key,
            .resource = resource,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
        };
        self.glyph_candidate_count += 1;
        return &self.glyph_candidates[self.glyph_candidate_count - 1];
    }

    fn retireGlyphs(
        self: *Content,
        removal_count: *usize,
    ) TakeError!bool {
        var changed = self.glyph_count != self.glyph_candidate_count;
        for (self.glyphs[0..self.glyph_count]) |entry| {
            var retained = false;
            for (self.glyph_candidates[0..self.glyph_candidate_count]) |candidate| {
                if (!std.meta.eql(entry.key, candidate.key)) continue;
                retained = true;
                break;
            }
            if (retained) continue;
            changed = true;
            const resource = entry.resource orelse continue;
            if (removal_count.* >= self.removals.len)
                return error.ResourceMutationLimit;
            self.removals[removal_count.*] = .{ .resource = resource };
            removal_count.* += 1;
        }
        return changed;
    }

    fn appendUpload(
        self: *Content,
        upload_count: *usize,
        bytes_used: *usize,
        resource: canvas.ResourceRef,
        width: u16,
        height: u16,
        pixels: []const u8,
    ) TakeError!void {
        if (upload_count.* >= self.uploads.len)
            return error.ResourceMutationLimit;
        const required = std.math.mul(usize, width, height) catch
            return error.ArithmeticOverflow;
        if (required != pixels.len) return error.InvalidOutput;
        if (bytes_used.* > self.upload_pixels.len or
            pixels.len > self.upload_pixels.len - bytes_used.*)
            return error.UploadByteLimit;
        const destination = self.upload_pixels[bytes_used.*..][0..pixels.len];
        @memcpy(destination, pixels);
        self.uploads[upload_count.*] = .{
            .resource = resource,
            .format = .alpha8,
            .pixels = .{
                .bytes = destination,
                .width = width,
                .height = height,
                .stride = width,
            },
        };
        upload_count.* += 1;
        bytes_used.* += pixels.len;
    }

    fn solid(
        self: *Content,
        rect: Rect,
        clip: Rect,
        color: Color,
    ) TakeError!void {
        if (self.input_count >= self.inputs.len) return error.CommandLimit;
        self.inputs[self.input_count] = .{ .solid = .{
            .rect = rect,
            .clip = clip,
            .color = color,
        } };
        self.input_count += 1;
    }

    fn alpha(
        self: *Content,
        destination: Rect,
        clip: Rect,
        resource: canvas.ResourceRef,
        size: Size,
        color: Color,
    ) TakeError!void {
        if (self.input_count >= self.inputs.len) return error.CommandLimit;
        self.inputs[self.input_count] = .{ .alpha_mask = .{
            .destination = destination,
            .clip = clip,
            .resource = .{
                .resource = resource,
                .format = .alpha8,
                .size = size,
            },
            .color = color,
        } };
        self.input_count += 1;
    }

    fn border(self: *Content, value: @FieldType(Primitive, "border")) TakeError!void {
        const rect = value.rect;
        if (value.edges.top)
            try self.solid(
                .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 },
                rect,
                value.color,
            );
        if (value.edges.right)
            try self.solid(
                .{
                    .x = try borderEdgeCoordinate(rect.x, rect.width),
                    .y = rect.y,
                    .width = 1,
                    .height = rect.height,
                },
                rect,
                value.color,
            );
        if (value.edges.bottom)
            try self.solid(
                .{
                    .x = rect.x,
                    .y = try borderEdgeCoordinate(rect.y, rect.height),
                    .width = rect.width,
                    .height = 1,
                },
                rect,
                value.color,
            );
        if (value.edges.left)
            try self.solid(
                .{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height },
                rect,
                value.color,
            );
    }

    fn issueResource(self: *Content) error{IdentityExhausted}!canvas.ResourceRef {
        if (self.next_resource_id == 0 or
            self.next_resource_id > canvas.ResourceId.max_identity)
            return error.IdentityExhausted;
        const value = self.next_resource_id;
        self.next_resource_id += 1;
        return .{
            .resource = canvas.ResourceId.local(value) catch return error.IdentityExhausted,
            .generation = @fromBackingInt(@intCast(1)),
        };
    }

    fn advanceRevision(self: *Content) error{IdentityExhausted}!void {
        if (self.producer_revision == std.math.maxInt(u64))
            return error.IdentityExhausted;
        self.producer_revision += 1;
    }

    fn activePrimitives(self: *const Content) []const Primitive {
        const storage = if (self.state_a_active) self.primitives_a else self.primitives_b;
        return storage[0..self.primitive_count];
    }

    fn inactivePrimitives(self: *Content) []Primitive {
        return if (self.state_a_active) self.primitives_b else self.primitives_a;
    }

    fn activeText(self: *const Content) []const u8 {
        const storage = if (self.state_a_active) self.text_a else self.text_b;
        return storage[0..self.text_count];
    }

    fn inactiveText(self: *Content) []u8 {
        return if (self.state_a_active) self.text_b else self.text_a;
    }

    fn surfaceRect(self: *const Content) Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = self.surface.width,
            .height = self.surface.height,
        };
    }
};

fn validateLimits(limits: Content.Limits) error{InvalidLimits}!void {
    if (limits.primitives == 0 or limits.text_bytes == 0 or
        limits.label_scalars == 0 or limits.shaped_glyphs == 0 or
        limits.shaped_glyphs > std.math.maxInt(u32) or limits.glyphs == 0 or
        limits.commands == 0 or limits.resources_per_update == 0 or
        limits.upload_bytes == 0 or limits.raster_bytes == 0)
        return error.InvalidLimits;
}

fn validateOutput(output: Output) Content.ApplyError!void {
    if (output.surface.width == 0 or output.surface.height == 0)
        return error.InvalidOutput;
    var text_used: usize = 0;
    for (output.primitives) |primitive| switch (primitive) {
        .fill => |value| try validateRect(value.rect, output.surface),
        .border => |value| try validateRect(value.rect, output.surface),
        .scrollbar => |value| {
            try validateRect(value.track, output.surface);
            try validateRect(value.thumb, output.surface);
            if (!contained(value.thumb, value.track)) return error.InvalidOutput;
        },
        .label => |value| {
            try validateRect(value.rect, output.surface);
            if (value.text.len == 0 or !std.unicode.utf8ValidateSlice(value.text))
                return error.InvalidOutput;
            const expected = std.math.add(
                usize,
                @intFromPtr(output.text.ptr),
                text_used,
            ) catch return error.ArithmeticOverflow;
            if (@intFromPtr(value.text.ptr) != expected)
                return error.InvalidOutput;
            text_used = std.math.add(usize, text_used, value.text.len) catch
                return error.ArithmeticOverflow;
            if (text_used > output.text.len) return error.InvalidOutput;
        },
    };
    if (text_used != output.text.len) return error.InvalidOutput;
}

fn validateRect(rect: Rect, surface: Size) Content.ApplyError!void {
    if (rect.x < 0 or rect.y < 0 or rect.width == 0 or rect.height == 0)
        return error.InvalidOutput;
    const right = std.math.add(i64, rect.x, rect.width) catch
        return error.ArithmeticOverflow;
    const bottom = std.math.add(i64, rect.y, rect.height) catch
        return error.ArithmeticOverflow;
    if (right > surface.width or bottom > surface.height)
        return error.InvalidOutput;
}

fn contained(inner: Rect, outer: Rect) bool {
    return inner.x >= outer.x and inner.y >= outer.y and
        @as(i64, inner.x) + inner.width <= @as(i64, outer.x) + outer.width and
        @as(i64, inner.y) + inner.height <= @as(i64, outer.y) + outer.height;
}

fn fixed26_6(value: i64) error{ArithmeticOverflow}!i32 {
    const pixels = @divFloor(value, 64);
    return std.math.cast(i32, pixels) orelse error.ArithmeticOverflow;
}

fn borderEdgeCoordinate(
    origin: i32,
    extent: u16,
) error{ArithmeticOverflow}!i32 {
    const exclusive = std.math.add(i64, origin, extent) catch
        return error.ArithmeticOverflow;
    return std.math.cast(i32, exclusive - 1) orelse
        error.ArithmeticOverflow;
}

test "Chrome local resource exhaustion preserves its high-water mark" {
    var content = std.mem.zeroes(Content);
    content.next_resource_id = canvas.ResourceId.max_identity + 1;
    try std.testing.expectError(
        error.IdentityExhausted,
        content.issueResource(),
    );
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity + 1,
        content.next_resource_id,
    );
    content.next_resource_id = canvas.ResourceId.max_identity;
    const last = try content.issueResource();
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity,
        try last.resource.identity(),
    );
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity + 1,
        content.next_resource_id,
    );
}
