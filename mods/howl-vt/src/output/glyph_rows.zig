//! Experimental direct native Screen -> final row-local commands. No Source/Input.
//! Caller owns transaction staging, resource rebinding, and global phase order.
const std = @import("std");
const VT = @import("howl_vt").Terminal;
const text = @import("howl_text");
const cache = @import("glyph_cache");
const frame = @import("frame");
/// Specializes the same native row algorithm without production counters.
pub fn Emitter(comptime instrumented: bool) type {
    return struct {
        /// Native shaping/raster, final-geometry and supported-row admission errors.
        pub const BuildError = cache.ShapeCacheError || cache.AtlasError || frame.Error || error{ CommandLimit, UnsupportedScene, FontSetMismatch };
        /// Supported cursor geometry and canonical color admission errors.
        pub const CursorError = error{UnsupportedScene};
        /// Borrows working font/cache state and caller-supplied geometry for one row.
        pub const Context = struct {
            atlas: *cache.Atlas,
            shapes: *cache.ShapeCache,
            raster: []u8,
            clusters: ?[]u32 = null,
            shaped: ?[]text.Glyph = null,
            cell_width: u16,
            cell_height: u16,
            baseline: u16,
            pending_resource: frame.ResourceRef,
            command_bytes_written: if (instrumented) ?*u64 else void = if (instrumented) null else {},
            full_ascii_rows: if (instrumented) ?*u64 else void = if (instrumented) null else {},
            presentation: *const VT.Presentation,
        };
        /// Partitions the caller’s output into background, decoration and glyph spans.
        pub const Counts = struct { background_end: usize, decoration_end: usize, count: usize };
        // Fixed view limits scratch, not retained output. Output capacity is caller-owned.
        const max_columns = @import("limits").maximum_columns;
        const scalar_limit = 24;
        const glyph_limit = max_columns * 2;

        fn append(counter: if (instrumented) ?*u64 else void, output: []frame.Command, used: *usize, command: frame.Command) !void {
            if (used.* == output.len) return error.CommandLimit;
            output[used.*] = command;
            used.* += 1;
            if (instrumented) if (counter) |value| {
                value.* += @sizeOf(frame.Command);
            };
        }
        fn rgba(c: VT.Rgb) frame.Color {
            return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
        }
        // zig-audit: acknowledge anytype
        // reason: The private caller supplies canonical VT color and presentation values only.
        // zig-audit: acknowledge anytype
        // reason: Presentation borrowing accepts the canonical value or its pointer without a copied palette.
        fn resolve(c: anytype, p: anytype, foreground: bool) !frame.Color {
            if (c.kind == .indexed and c.value > 255) return error.UnsupportedScene;
            return rgba(c.resolve(if (foreground) p.foreground else p.background, &p.palette));
        }
        const Colors = struct { fg: frame.Color, bg: frame.Color, underline: frame.Color };
        // zig-audit: acknowledge anytype
        // reason: Only canonical VT presentation values or borrowed pointers reach this private helper.
        fn colors(cell: VT.Cell, p: anytype) !Colors {
            var fg = try resolve(cell.attrs.fg, p, true);
            var bg = try resolve(cell.attrs.bg, p, false);
            if (cell.attrs.reverse != p.reverse_screen) std.mem.swap(frame.Color, &fg, &bg);
            if (cell.attrs.dim) fg.a = @intCast((@as(u16, fg.a) * 55 + 50) / 100);
            return .{ .fg = fg, .bg = bg, .underline = try resolve(cell.attrs.underline_color, p, true) };
        }
        fn variant(a: VT.CellAttrs) cache.FontVariant {
            return if (a.bold) (if (a.italic) .bold_italic else .bold) else (if (a.italic) .italic else .regular);
        }
        fn operator(cell: VT.Cell, sequence: []const u32) bool {
            if (sequence.len != 1 or cell.width != 1 or cell.x != 0 or cell.attrs.invisible or
                cell.attrs.font != 0 or cell.attrs.baseline != .normal) return false;
            const v = sequence[0];
            return (v >= 0x21 and v <= 0x2f) or (v >= 0x3a and v <= 0x40) or (v >= 0x5b and v <= 0x60) or (v >= 0x7b and v <= 0x7e);
        }
        fn fitColor(ink: frame.Rect, cell: frame.Rect) frame.Rect {
            const scale = @min(@as(f64, 1), @min(
                @as(f64, @floatFromInt(cell.width)) / @as(f64, @floatFromInt(ink.width)),
                @as(f64, @floatFromInt(cell.height)) / @as(f64, @floatFromInt(ink.height)),
            ));
            const width: u16 = @intFromFloat(@max(1, @floor(@as(f64, @floatFromInt(ink.width)) * scale)));
            const height: u16 = @intFromFloat(@max(1, @floor(@as(f64, @floatFromInt(ink.height)) * scale)));
            return .{ .x = cell.x + @as(i32, @intCast((cell.width - width) / 2)), .y = cell.y + @as(i32, @intCast((cell.height - height) / 2)), .width = width, .height = height };
        }
        fn preservesCells(glyphs: []const text.Glyph, count: usize) bool {
            if (glyphs.len == 0 or glyphs[0].cluster != 0) return false;
            var previous: u32 = 0;
            for (glyphs) |g| {
                if (g.cluster >= count or g.cluster < previous) return false;
                previous = g.cluster;
            }
            return true;
        }
        fn validate(cell: VT.Cell) !void {
            if (cell.height == 0 or cell.y >= cell.height) return error.UnsupportedScene;
            if (cell.semantic_width) {
                if (cell.height != 1 or cell.width != 2 or cell.x > 1) return error.UnsupportedScene;
            } else if (cell.width == 0 or cell.x >= cell.width or cell.width % cell.height != 0) return error.UnsupportedScene;
            if (cell.codepoint == 0x10eeee) return error.UnsupportedScene;
        }
        fn needsScale(cell: VT.Cell) bool {
            return cell.height > 1 or cell.subscale_n != 0 or cell.subscale_d != 0 or
                cell.vertical_align != 0 or cell.horizontal_align != 0;
        }
        fn solid(counter: if (instrumented) ?*u64 else void, output: []frame.Command, used: *usize, rect: frame.Rect, clip: frame.Rect, color: frame.Color) !void {
            const visible = (try frame.intersectRects(rect, clip)) orelse return;
            try append(counter, output, used, .{ .solid = .{ .rect = visible, .color = color } });
        }

        fn underline(
            ctx: Context,
            output: []frame.Command,
            used: *usize,
            allocation: frame.Rect,
            y: i32,
            thickness: u16,
            line_height: u16,
            style: @FieldType(@FieldType(VT.Cell, "attrs"), "underline_style"),
            color: frame.Color,
        ) !void {
            const height = @max(@as(u16, 1), thickness);
            switch (style) {
                .straight, .double => {
                    try solid(ctx.command_bytes_written, output, used, .{ .x = allocation.x, .y = y, .width = allocation.width, .height = height }, allocation, color);
                    if (style == .double) {
                        try solid(ctx.command_bytes_written, output, used, .{
                            .x = allocation.x,
                            .y = y + height + 1,
                            .width = allocation.width,
                            .height = height,
                        }, allocation, color);
                    }
                },
                .dotted, .dashed => {
                    const pattern = try cache.resolveUnderlinePatternAtlas(ctx.atlas, allocation.width, height, style == .dashed, ctx.raster);
                    const destination: frame.Rect = .{ .x = allocation.x, .y = y, .width = pattern.width, .height = pattern.height };
                    // zig-audit: acknowledge discard
                    // reason: Empty intersections produce no visible decoration command.
                    _ = (try frame.intersectRects(destination, allocation)) orelse return;
                    const size = cache.atlasSize(ctx.atlas);
                    try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{
                        .destination = destination,
                        .clip = allocation,
                        .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = pattern.atlas_x, .y = pattern.atlas_y, .width = pattern.width, .height = pattern.height } },
                        .color = color,
                    } });
                },
                .curly => {
                    const wave = try cache.resolveSmoothWaveAtlas(ctx.atlas, allocation.width, height, line_height, ctx.raster);
                    const destination: frame.Rect = .{ .x = allocation.x, .y = y - wave.top, .width = wave.width, .height = wave.height };
                    // zig-audit: acknowledge discard
                    // reason: Empty intersections produce no visible decoration command.
                    _ = (try frame.intersectRects(destination, allocation)) orelse return;
                    const size = cache.atlasSize(ctx.atlas);
                    try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{
                        .destination = destination,
                        .clip = allocation,
                        .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = wave.atlas_x, .y = wave.atlas_y, .width = wave.width, .height = wave.height } },
                        .color = color,
                    } });
                },
            }
        }

        /// Writes private caller staging only; on error its prefix is unspecified.
        /// Accepted output must not alias this storage. All backgrounds must be visited
        /// before all decorations, then all glyphs. No retained normalized scene exists.
        /// FontFaces selects real faces; absent bold/italic use regular, absent combined
        /// prefers bold then italic then regular. No synthetic style is generated.
        pub fn buildRow(ctx: Context, vt: *const VT, logical_row: u16, output: []frame.Command) BuildError!Counts {
            return buildSelectedRow(ctx, vt, logical_row, null, output);
        }
        /// Emits one live or history row into bounded private staging storage.
        pub fn buildSelectedRow(ctx: Context, vt: *const VT, logical_row: u16, history: ?u32, output: []frame.Command) BuildError!Counts {
            if (ctx.clusters != null and ctx.shaped != null) return buildWithScratch(ctx, vt, logical_row, history, output);
            return buildPrivateScratch(ctx, vt, logical_row, history, output);
        }
        // Isolate private scratch so shared work never reserves another shaping lane.
        noinline fn buildPrivateScratch(ctx: Context, vt: *const VT, logical_row: u16, history: ?u32, output: []frame.Command) BuildError!Counts {
            var clusters: [max_columns]u32 = undefined;
            var glyphs: [glyph_limit]text.Glyph = undefined;
            var supplied = ctx;
            supplied.clusters = &clusters;
            supplied.shaped = &glyphs;
            return buildWithScratch(supplied, vt, logical_row, history, output);
        }
        fn buildWithScratch(ctx: Context, vt: *const VT, logical_row: u16, history: ?u32, output: []frame.Command) BuildError!Counts {
            const screen = if (vt.screen_state.alt_active) &vt.screen_state.alternate else &vt.screen_state.primary;
            const columns = screen.cols;
            if (columns == 0 or columns > max_columns or screen.rows == 0 or screen.rows > @import("limits").maximum_rows or logical_row >= screen.rows) return error.UnsupportedScene;
            if (!cache.sameFontFaces(ctx.shapes, ctx.atlas)) return error.FontSetMismatch;
            const geometry = if (history) |recency| screen.historyLineGeometry(recency) else screen.lineGeometry(logical_row);
            const visible_columns = if (geometry == .single_width) columns else @max(@as(u16, 1), columns / 2);
            const counts = if (history) |recency|
                try buildHistory(ctx, vt, logical_row, recency, visible_columns, output)
            else blk: {
                const physical = (@as(usize, logical_row) + screen.row_origin) % screen.rows;
                break :blk try buildCells(ctx, vt, logical_row, null, screen.cells.?[physical * columns ..][0..visible_columns], output);
            };
            if (geometry == .single_width) return counts;
            return transformLine(output, counts, geometry, columns * ctx.cell_width, ctx.cell_height);
        }
        fn scaleLineRect(rect: frame.Rect, geometry: VT.LineGeometry, cell_height: u16) frame.Error!frame.Rect {
            const scale_y: u16 = if (geometry == .double_width) 1 else 2;
            return .{
                .x = rect.x * 2,
                .y = rect.y * @as(i32, scale_y) - (if (geometry == .double_height_bottom) @as(i32, cell_height) else 0),
                .width = std.math.mul(u16, rect.width, 2) catch return error.ArithmeticOverflow,
                .height = std.math.mul(u16, rect.height, scale_y) catch return error.ArithmeticOverflow,
            };
        }
        fn transformLine(output: []frame.Command, counts: Counts, geometry: VT.LineGeometry, width: u16, height: u16) frame.Error!Counts {
            const strip: frame.Rect = .{ .x = 0, .y = 0, .width = width, .height = height };
            var used: usize = 0;
            var background_end: usize = 0;
            var decoration_end: usize = 0;
            for (output[0..counts.count], 0..) |original, i| {
                if (i == counts.background_end) background_end = used;
                if (i == counts.decoration_end) decoration_end = used;
                var command = original;
                const visible = switch (command) {
                    .solid => |*solid_cmd| blk: {
                        solid_cmd.rect = (try frame.intersectRects(try scaleLineRect(solid_cmd.rect, geometry, height), strip)) orelse break :blk false;
                        break :blk true;
                    },
                    .alpha_mask => |*mask| blk: {
                        mask.destination = try scaleLineRect(mask.destination, geometry, height);
                        mask.clip = (try frame.intersectRects(try scaleLineRect(mask.clip, geometry, height), strip)) orelse break :blk false;
                        break :blk true;
                    },
                    .rgba => |*image| blk: {
                        image.destination = try scaleLineRect(image.destination, geometry, height);
                        image.clip = (try frame.intersectRects(try scaleLineRect(image.clip, geometry, height), strip)) orelse break :blk false;
                        break :blk true;
                    },
                };
                if (visible) {
                    output[used] = command;
                    used += 1;
                }
            }
            if (counts.background_end == counts.count) background_end = used;
            if (counts.decoration_end == counts.count) decoration_end = used;
            return .{ .background_end = background_end, .decoration_end = decoration_end, .count = used };
        }
        // History decoding is the only case that needs a full temporary row.
        // Keep that storage off the live-screen path.
        noinline fn buildHistory(ctx: Context, vt: *const VT, logical_row: u16, recency: u32, visible_columns: u16, output: []frame.Command) BuildError!Counts {
            if (vt.screen_state.alt_active) return error.UnsupportedScene;
            const screen = &vt.screen_state.primary;
            if (recency >= screen.historyCount()) return error.UnsupportedScene;
            var decoded: [max_columns]VT.Cell = undefined;
            for (decoded[0..visible_columns], 0..) |*cell, col| cell.* = screen.historyCellAt(recency, @intCast(col));
            return buildCells(ctx, vt, logical_row, recency, decoded[0..visible_columns], output);
        }
        fn buildCells(ctx: Context, vt: *const VT, logical_row: u16, history: ?u32, cells: []const VT.Cell, output: []frame.Command) BuildError!Counts {
            const screen = if (vt.screen_state.alt_active) &vt.screen_state.alternate else &vt.screen_state.primary;
            const columns: u16 = @intCast(cells.len);
            const p = ctx.presentation;
            const physical = (@as(usize, logical_row) + screen.row_origin) % screen.rows;
            // Canonical exact physical-row fact: ordinary geometry and identical attrs.
            // The name does not guarantee printable ASCII; codepoints are checked below.
            const span = screen.row_metadata.?[physical].ascii;
            const uniform = history == null and span.start == 0 and span.end == columns;
            const shared_cell: VT.Cell = .{ .codepoint = 0, .attrs = span.attrs };
            if (uniform) {
                try validate(shared_cell);
                for (cells) |cell| {
                    if (cell.codepoint == 0x10eeee) return error.UnsupportedScene;
                }
            }
            const shared_colors = if (uniform) try colors(shared_cell, p) else null;
            const shared_style = if (uniform) variant(span.attrs) else undefined;
            if (!uniform) for (cells, 0..) |cell, col| {
                try validate(cell);
                if (needsScale(cell)) {
                    if (history != null or cell.y > logical_row or screen.lineGeometry(logical_row) != .single_width or
                        @as(u32, logical_row - cell.y) + cell.height > screen.rows or
                        (cell.y != 0 and (cell.codepoint != 0 or cell.combining_len != 0)))
                        return error.UnsupportedScene;
                    const origin = screen.cellInfoAt(logical_row - cell.y, @intCast(col -| cell.x));
                    if (cell.x > col or origin.x != 0 or origin.y != 0 or origin.width != cell.width or
                        origin.height != cell.height or origin.semantic_width or
                        !std.meta.eql(origin.attrs, cell.attrs)) return error.UnsupportedScene;
                }
                if (cell.width > 1) {
                    if (cell.x > col) return error.UnsupportedScene;
                    const start = col - cell.x;
                    const end = start + cell.width;
                    if (end > columns) return error.UnsupportedScene;
                    const lead = cells[start];
                    if (lead.x != 0 or lead.width != cell.width or lead.height != cell.height or
                        lead.y != cell.y or lead.semantic_width != cell.semantic_width) return error.UnsupportedScene;
                    if (cell.x == 0) for (cells[start + 1 .. end], 1..) |tail, x| {
                        if (tail.x != x or tail.width != cell.width or tail.height != cell.height or
                            tail.y != cell.y or tail.semantic_width != cell.semantic_width or
                            tail.codepoint != 0 or tail.combining_len != 0) return error.UnsupportedScene;
                    };
                }
            };
            const row_clip: frame.Rect = .{ .x = 0, .y = 0, .width = columns * ctx.cell_width, .height = ctx.cell_height };
            var used: usize = 0;
            var column: usize = 0;
            // Maximal non-default background runs match the native oracle's phase.
            if (shared_colors) |c| {
                if (!std.meta.eql(c.bg, rgba(p.background)))
                    try solid(ctx.command_bytes_written, output, &used, row_clip, row_clip, c.bg);
            } else while (column < columns) {
                const attrs = cells[column].attrs;
                if (attrs.reverse == p.reverse_screen and attrs.bg.kind == .default) {
                    column += 1;
                    continue;
                }
                const c = try colors(cells[column], p);
                if (std.meta.eql(c.bg, rgba(p.background))) {
                    column += 1;
                    continue;
                }
                const start = column;
                column += 1;
                while (column < columns and std.meta.eql((try colors(cells[column], p)).bg, c.bg)) column += 1;
                try solid(ctx.command_bytes_written, output, &used, .{ .x = @as(i32, @intCast(start)) * ctx.cell_width, .y = 0, .width = @as(u16, @intCast(column - start)) * ctx.cell_width, .height = ctx.cell_height }, row_clip, c.bg);
            }
            const background_end = used;
            const metrics = cache.fontFaces(ctx.atlas).metrics();
            const line_offset = @divFloor(@as(i32, ctx.cell_height) - metrics.line_height, 2);
            if (!uniform or span.attrs.underline or span.attrs.strikethrough) for (cells, 0..) |cell, col| {
                if (cell.x != 0 or cell.attrs.invisible or
                    (!cell.attrs.underline and !cell.attrs.strikethrough)) continue;
                if (needsScale(cell)) {
                    const lead = screen.cellInfoAt(logical_row - cell.y, @intCast(col));
                    if (lead.codepoint != 0) try appendScaledDecorations(ctx, output, &used, lead, col, cell.y, row_clip, line_offset, metrics, try colors(lead, p));
                    continue;
                }
                if (cell.codepoint == 0) continue;
                const c = shared_colors orelse try colors(cell, p);
                const allocation: frame.Rect = .{ .x = @as(i32, @intCast(col)) * ctx.cell_width, .y = 0, .width = ctx.cell_width * cell.width, .height = ctx.cell_height };
                if (cell.attrs.underline) try underline(ctx, output, &used, allocation, line_offset + metrics.underline_y, metrics.underline_height, metrics.line_height, cell.attrs.underline_style, c.underline);
                if (cell.attrs.strikethrough) try solid(ctx.command_bytes_written, output, &used, .{ .x = allocation.x, .y = line_offset + metrics.strike_y, .width = allocation.width, .height = @max(@as(u16, 1), metrics.strike_height) }, allocation, c.underline);
            };
            const decoration_end = used;
            var scalars: [scalar_limit]u32 = undefined;
            const clusters = ctx.clusters.?;
            const glyphs = ctx.shaped.?;
            var operators: [max_columns]u32 = undefined;
            column = 0;
            while (column < columns) {
                const col = column;
                column += 1;
                const cell = cells[col];
                if (cell.x != 0 or cell.attrs.invisible) continue;
                if (needsScale(cell)) {
                    const lead_row = logical_row - cell.y;
                    const lead = screen.cellInfoAt(lead_row, @intCast(col));
                    const sequence = screen.cellScalarsAt(lead_row, @intCast(col), &scalars);
                    if (sequence.len != 0 and !(sequence.len == 1 and sequence[0] == ' ')) {
                        const c = try colors(lead, p);
                        try appendScaled(ctx, output, &used, sequence, variant(lead.attrs), lead, col, cell.y, row_clip, c.fg);
                    }
                    continue;
                }
                const sequence = if (cell.combining_len == 0) blk: {
                    scalars[0] = cell.codepoint;
                    break :blk scalars[0..@as(usize, if (cell.codepoint == 0) 0 else 1)];
                } else if (history) |recency| screen.historyCellScalarsAt(recency, @intCast(col), &scalars) else screen.cellScalarsAt(logical_row, @intCast(col), &scalars);
                if (sequence.len == 0 or (sequence.len == 1 and sequence[0] == ' ')) continue;
                const c = shared_colors orelse try colors(cell, p);
                const style = if (uniform) shared_style else variant(cell.attrs);
                if (sequence.len == 1 and text.generated.classify(sequence[0]) != null) {
                    const allocation: frame.Rect = .{ .x = @as(i32, @intCast(col)) * ctx.cell_width, .y = 0, .width = ctx.cell_width * cell.width, .height = ctx.cell_height };
                    const generated = try cache.resolveGeneratedAtlas(ctx.atlas, sequence[0], allocation.width, allocation.height, .{}, ctx.raster);
                    const size = cache.atlasSize(ctx.atlas);
                    try append(ctx.command_bytes_written, output, &used, .{ .alpha_mask = .{
                        .destination = allocation,
                        .clip = allocation,
                        .color = c.fg,
                        .cursor_component = true,
                        .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = generated.atlas_x, .y = generated.atlas_y, .width = generated.width, .height = generated.height } },
                    } });
                    continue;
                }
                const ascii_index = cache.printableAsciiIndex(sequence);
                if (cell.width == 1 and !operator(cell, sequence)) {
                    if (ascii_index) |index| {
                        if (cache.asciiPlacement(ctx.atlas, style, index)) |placed| {
                            const raster = placed.raster;
                            const destination: frame.Rect = .{
                                .x = @as(i32, @intCast(col)) * ctx.cell_width + placed.x,
                                .y = @as(i32, ctx.baseline) + placed.y,
                                .width = raster.width,
                                .height = raster.height,
                            };
                            if (try frame.intersectRects(destination, row_clip)) |clip| {
                                const size = cache.atlasSize(ctx.atlas);
                                try append(ctx.command_bytes_written, output, &used, .{ .alpha_mask = .{
                                    .destination = destination,
                                    .clip = clip,
                                    .color = c.fg,
                                    .cursor_component = true,
                                    .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                                } });
                            }
                            continue;
                        }
                    }
                }
                var contextual = false;
                var run: text.Run = undefined;
                if (operator(cell, sequence)) {
                    operators[0] = sequence[0];
                    var end = col + 1;
                    while (end < columns) : (end += 1) {
                        var next_scalars: [scalar_limit]u32 = undefined;
                        const next = cells[end];
                        const seq = if (next.combining_len == 0) blk: {
                            next_scalars[0] = next.codepoint;
                            break :blk next_scalars[0..@as(usize, if (next.codepoint == 0) 0 else 1)];
                        } else if (history) |recency| screen.historyCellScalarsAt(recency, @intCast(end), &next_scalars) else screen.cellScalarsAt(logical_row, @intCast(end), &next_scalars);
                        if (!operator(next, seq)) break;
                        if (!uniform and (variant(next.attrs) != style or
                            !std.meta.eql((try colors(next, p)).fg, c.fg))) break;
                        operators[end - col] = seq[0];
                    }
                    if (end - col >= 2) {
                        const count = end - col;
                        if (count > clusters.len or count * 2 > glyphs.len) {
                            if (try appendLongContextual(ctx, output, &used, operators[0..count], style, cell, col, row_clip, c.fg)) {
                                column = end;
                                continue;
                            }
                        } else if (try cache.shapeContextualPrimary(ctx.shapes, style, operators[0 .. end - col], clusters, glyphs)) |shaped| {
                            if (preservesCells(shaped.glyphs, end - col)) {
                                run = shaped;
                                contextual = true;
                                column = end;
                            }
                        }
                    }
                }
                if (!contextual) {
                    run = try cache.resolveShape(ctx.shapes, style, sequence, clusters, glyphs);
                    // Cache hits obey the same lane bound as freshly shaped runs.
                    if (run.glyphs.len > glyphs.len) return error.InsufficientGlyphs;
                }
                try appendRun(ctx, output, &used, run, contextual, sequence, style, cell, col, row_clip, c.fg);
            }
            if (instrumented) if (uniform) if (ctx.full_ascii_rows) |counter| {
                counter.* += 1;
            };
            return .{ .background_end = background_end, .decoration_end = decoration_end, .count = used };
        }

        // Only an oversized contextual run needs this full-row stack lane.
        noinline fn appendLongContextual(
            ctx: Context,
            output: []frame.Command,
            used: *usize,
            operators: []const u32,
            style: cache.FontVariant,
            cell: VT.Cell,
            col: usize,
            row_clip: frame.Rect,
            color: frame.Color,
        ) BuildError!bool {
            var clusters: [max_columns]u32 = undefined;
            var glyphs: [glyph_limit]text.Glyph = undefined;
            const run = (try cache.shapeContextualPrimary(ctx.shapes, style, operators, &clusters, &glyphs)) orelse return false;
            if (!preservesCells(run.glyphs, operators.len)) return false;
            try appendRun(ctx, output, used, run, true, operators[0..1], style, cell, col, row_clip, color);
            return true;
        }
        fn scaledExtent(value: u16, numerator: u16, denominator: u16) BuildError!u16 {
            const product: u32 = @as(u32, value) * numerator;
            return std.math.cast(u16, (product + denominator - 1) / denominator) orelse error.ArithmeticOverflow;
        }

        const ScaledLayout = struct {
            allocation: frame.Rect,
            base_width: u16,
            numerator: u16,
            denominator: u16,
            offset_x: u16,
            offset_y: u16,

            fn transform(self: ScaledLayout, rect: frame.Rect) BuildError!frame.Rect {
                const x = @as(i64, self.allocation.x) + self.offset_x +
                    @divFloor((@as(i64, rect.x) - self.allocation.x) * self.numerator, self.denominator);
                const y = @as(i64, self.allocation.y) + self.offset_y +
                    @divFloor(@as(i64, rect.y) * self.numerator, self.denominator);
                return .{ .x = std.math.cast(i32, x) orelse return error.ArithmeticOverflow, .y = std.math.cast(i32, y) orelse return error.ArithmeticOverflow, .width = try scaledExtent(rect.width, self.numerator, self.denominator), .height = try scaledExtent(rect.height, self.numerator, self.denominator) };
            }
        };

        fn scaledLayout(ctx: Context, cell: VT.Cell, col: usize, row_offset: u8) BuildError!ScaledLayout {
            const allocation: frame.Rect = .{ .x = @intCast(col * ctx.cell_width), .y = -@as(i32, row_offset) * @as(i32, ctx.cell_height), .width = ctx.cell_width * cell.width, .height = ctx.cell_height * cell.height };
            var numerator: u16 = cell.height;
            var denominator: u16 = 1;
            if (cell.subscale_n != 0 and cell.subscale_d != 0 and cell.subscale_n < cell.subscale_d) {
                numerator *= cell.subscale_n;
                denominator = cell.subscale_d;
            }
            const base_width = ctx.cell_width * (cell.width / cell.height);
            const scaled_width = try scaledExtent(base_width, numerator, denominator);
            const scaled_height = try scaledExtent(ctx.cell_height, numerator, denominator);
            if (scaled_width > allocation.width or scaled_height > allocation.height) return error.UnsupportedScene;
            const remaining_x = allocation.width - scaled_width;
            const remaining_y = allocation.height - scaled_height;
            return .{ .allocation = allocation, .base_width = base_width, .numerator = numerator, .denominator = denominator, .offset_x = switch (cell.horizontal_align) {
                2 => remaining_x / 2,
                1, 3 => remaining_x,
                else => 0,
            }, .offset_y = switch (cell.vertical_align) {
                1 => remaining_y,
                2 => remaining_y / 2,
                else => 0,
            } };
        }

        // Project scaled decorations into each row-local strip.
        fn appendScaledDecorations(ctx: Context, output: []frame.Command, used: *usize, cell: VT.Cell, col: usize, row_offset: u8, row_clip: frame.Rect, line_offset: i32, metrics: text.Metrics, resolved: Colors) BuildError!void {
            const sizing = try scaledLayout(ctx, cell, col, row_offset);
            const clip = (try frame.intersectRects(sizing.allocation, row_clip)) orelse return;
            if (cell.attrs.underline) {
                const height = @max(@as(u16, 1), metrics.underline_height);
                const y = line_offset + metrics.underline_y;
                switch (cell.attrs.underline_style) {
                    .straight, .double => {
                        try solid(ctx.command_bytes_written, output, used, try sizing.transform(.{ .x = sizing.allocation.x, .y = y, .width = sizing.base_width, .height = height }), clip, resolved.underline);
                        if (cell.attrs.underline_style == .double)
                            try solid(ctx.command_bytes_written, output, used, try sizing.transform(.{ .x = sizing.allocation.x, .y = y + height + 1, .width = sizing.base_width, .height = height }), clip, resolved.underline);
                    },
                    .dotted, .dashed => {
                        // Transform each segment, rather than scaling a bitmap:
                        // fractional rounding is defined per rectangle.
                        const step: usize = if (cell.attrs.underline_style == .dotted) 2 else 5;
                        const width: usize = if (cell.attrs.underline_style == .dotted) 1 else 3;
                        var offset: usize = 0;
                        while (offset < sizing.base_width) : (offset += step) {
                            try solid(ctx.command_bytes_written, output, used, try sizing.transform(.{
                                .x = sizing.allocation.x + @as(i32, @intCast(offset)),
                                .y = y,
                                .width = @intCast(@min(width, sizing.base_width - offset)),
                                .height = height,
                            }), clip, resolved.underline);
                        }
                    },
                    .curly => {
                        const wave = try cache.resolveSmoothWaveAtlas(ctx.atlas, sizing.base_width, height, metrics.line_height, ctx.raster);
                        const destination = try sizing.transform(.{ .x = sizing.allocation.x, .y = y - wave.top, .width = wave.width, .height = wave.height });
                        if (try frame.intersectRects(destination, clip) != null) {
                            const size = cache.atlasSize(ctx.atlas);
                            try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{ .destination = destination, .clip = clip, .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = wave.atlas_x, .y = wave.atlas_y, .width = wave.width, .height = wave.height } }, .color = resolved.underline } });
                        }
                    },
                }
            }
            if (cell.attrs.strikethrough) try solid(ctx.command_bytes_written, output, used, try sizing.transform(.{ .x = sizing.allocation.x, .y = line_offset + metrics.strike_y, .width = sizing.base_width, .height = @max(@as(u16, 1), metrics.strike_height) }), clip, resolved.underline);
        }

        // Project a live scaled cluster into one row-local strip. Retaining
        // strips independently lets the VT's existing row generations drive repair.
        fn appendScaled(ctx: Context, output: []frame.Command, used: *usize, sequence: []const u32, style: cache.FontVariant, cell: VT.Cell, col: usize, row_offset: u8, row_clip: frame.Rect, color: frame.Color) BuildError!void {
            const sizing = try scaledLayout(ctx, cell, col, row_offset);
            const strip = (try frame.intersectRects(sizing.allocation, row_clip)) orelse return;
            if (sequence.len == 1 and text.generated.classify(sequence[0]) != null) {
                const destination = try sizing.transform(.{ .x = sizing.allocation.x, .y = 0, .width = sizing.base_width, .height = ctx.cell_height });
                const proper_fraction = cell.subscale_n != 0 and cell.subscale_d != 0 and cell.subscale_n < cell.subscale_d;
                const raster = try cache.resolveGeneratedAtlas(ctx.atlas, sequence[0], destination.width, destination.height, .{ .scale = cell.height, .subscale_n = if (proper_fraction) cell.subscale_n else 0, .subscale_d = if (proper_fraction) cell.subscale_d else 0 }, ctx.raster);
                if (try frame.intersectRects(destination, strip)) |clip| {
                    const size = cache.atlasSize(ctx.atlas);
                    try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{
                        .destination = destination,
                        .clip = clip,
                        .color = color,
                        .cursor_component = true,
                        .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                    } });
                }
                return;
            }
            if (sequence.len == 1 and ((sequence[0] >= 0x2190 and sequence[0] <= 0x21ff) or
                (sequence[0] >= 0x25a0 and sequence[0] <= 0x25ff))) return error.UnsupportedScene;
            const run = try cache.resolveShape(ctx.shapes, style, sequence, ctx.clusters.?, ctx.shaped.?);
            if (run.glyphs.len > ctx.shaped.?.len) return error.InsufficientGlyphs;
            const x = sizing.allocation.x;
            var pen_x: i64 = @as(i64, x) * 64;
            var pen_y: i64 = 0;
            for (run.glyphs) |g| {
                const raster = try cache.resolveFontAtlas(ctx.atlas, style, run.face_index, g.id, ctx.raster, null, 0);
                if (raster.width != 0 and raster.height != 0) {
                    const raw_x = @divFloor(pen_x + g.x_offset, 64) + raster.left;
                    const raw_y = @as(i64, ctx.baseline) + @divFloor(pen_y - g.y_offset, 64) - raster.top;
                    const destination = try sizing.transform(.{
                        .x = std.math.cast(i32, raw_x) orelse return error.ArithmeticOverflow,
                        .y = std.math.cast(i32, raw_y) orelse return error.ArithmeticOverflow,
                        .width = raster.width,
                        .height = raster.height,
                    });
                    if (raster.format == .rgba8) {
                        const fitted = fitColor(destination, sizing.allocation);
                        if (try frame.intersectRects(fitted, strip)) |clip| {
                            const size = cache.colorAtlasSize(ctx.atlas);
                            try append(ctx.command_bytes_written, output, used, .{ .rgba = .{
                                .destination = fitted,
                                .clip = clip,
                                .resource = .{ .resource = ctx.pending_resource, .format = .rgba8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                            } });
                        }
                    } else if (try frame.intersectRects(destination, strip)) |clip| {
                        const size = cache.atlasSize(ctx.atlas);
                        try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{
                            .destination = destination,
                            .clip = clip,
                            .color = color,
                            .cursor_component = true,
                            .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                        } });
                    }
                }
                pen_x += g.x_advance;
                pen_y += g.y_advance;
            }
        }

        fn appendRun(
            ctx: Context,
            output: []frame.Command,
            used: *usize,
            run: text.Run,
            contextual: bool,
            sequence: []const u32,
            style: cache.FontVariant,
            cell: VT.Cell,
            col: usize,
            row_clip: frame.Rect,
            color: frame.Color,
        ) BuildError!void {
            const ascii_index = cache.printableAsciiIndex(sequence);
            const bounded_symbol = !contextual and sequence.len == 1 and run.glyphs.len == 1 and
                ((sequence[0] >= 0x2190 and sequence[0] <= 0x21ff) or (sequence[0] >= 0x25a0 and sequence[0] <= 0x25ff));
            const allocation: frame.Rect = .{ .x = @as(i32, @intCast(col)) * ctx.cell_width, .y = 0, .width = ctx.cell_width * cell.width, .height = ctx.cell_height };
            var pen_x: i64 = @as(i64, allocation.x) * 64;
            var pen_y: i64 = 0;
            var previous: ?u32 = null;
            for (run.glyphs) |g| {
                if (contextual and previous != g.cluster) {
                    pen_x = (@as(i64, allocation.x) + @as(i64, g.cluster) * ctx.cell_width) * 64;
                    pen_y = 0;
                    previous = g.cluster;
                }
                const raster = try cache.resolveFontAtlas(ctx.atlas, style, run.face_index, g.id, ctx.raster, if (!contextual and run.glyphs.len == 1) cache.printableAsciiIndex(sequence) else null, if (bounded_symbol) allocation.width else 0);
                if (raster.format == .alpha8 and cell.width == 1 and !contextual and run.glyphs.len == 1) {
                    if (ascii_index) |index| cache.rememberAsciiPlacement(ctx.atlas, style, index, g, raster);
                }
                if (raster.width != 0 and raster.height != 0) {
                    var destination: frame.Rect = .{
                        .x = @intCast(@divFloor(pen_x + g.x_offset, 64) + raster.left),
                        .y = @intCast(@as(i64, ctx.baseline) + @divFloor(pen_y - g.y_offset, 64) - raster.top),
                        .width = raster.width,
                        .height = raster.height,
                    };
                    if (bounded_symbol) {
                        const latest = allocation.x + @as(i32, allocation.width) - destination.width;
                        destination.x = std.math.clamp(destination.x, allocation.x, @max(allocation.x, latest));
                        destination.y = @max(destination.y, allocation.y);
                    }
                    if (raster.format == .rgba8) {
                        const size = cache.colorAtlasSize(ctx.atlas);
                        try append(ctx.command_bytes_written, output, used, .{ .rgba = .{
                            .destination = fitColor(destination, allocation),
                            .clip = allocation,
                            .resource = .{ .resource = ctx.pending_resource, .format = .rgba8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                        } });
                    } else {
                        const clip = try frame.intersectRects(destination, if (bounded_symbol or (!cell.semantic_width and cell.width > 1)) allocation else row_clip);
                        if (clip) |visible| {
                            const size = cache.atlasSize(ctx.atlas);
                            try append(ctx.command_bytes_written, output, used, .{ .alpha_mask = .{
                                .destination = destination,
                                .clip = visible,
                                .color = color,
                                .cursor_component = true,
                                .resource = .{ .resource = ctx.pending_resource, .format = .alpha8, .size = .{ .width = size.width, .height = size.height }, .source = .{ .x = raster.atlas_x, .y = raster.atlas_y, .width = raster.width, .height = raster.height } },
                            } });
                        }
                    }
                }
                pen_x += g.x_advance;
                pen_y += g.y_advance;
            }
        }

        /// Native cursor geometry and implicit-color policy for the supported subset.
        /// A wide continuation resolves to its lead and spans both semantic cells.
        pub const Cursor = struct { command: frame.Command, cell: frame.Rect, text_color: frame.Color, shape: VT.CursorShape };
        /// Resolves cursor fill and optional block-glyph color from canonical VT state.
        pub fn cursorCommand(vt: *const VT, cell_width: u16, cell_height: u16, stroke: u8) CursorError!?Cursor {
            const screen = if (vt.screen_state.alt_active) &vt.screen_state.alternate else &vt.screen_state.primary;
            const cursor = screen.cursor;
            if (!cursor.visible) return null;
            const columns = screen.cols;
            if (columns == 0 or columns > max_columns or screen.rows == 0 or screen.rows > @import("limits").maximum_rows) return error.UnsupportedScene;
            if (cursor.row >= screen.rows or cursor.col >= screen.cols) return null;
            const geometry = screen.lineGeometry(cursor.row);
            const line_columns = if (geometry == .single_width) columns else @max(@as(u16, 1), columns / 2);
            if (cursor.col >= line_columns) return null;
            const physical = (@as(usize, cursor.row) + screen.row_origin) % screen.rows;
            const cells = screen.cells.?[physical * columns ..][0..columns];
            var column = cursor.col;
            var cell = cells[column];
            try validate(cell);
            var width: u16 = 1;
            if (cell.semantic_width) {
                if (cell.x > column) return error.UnsupportedScene;
                column -= cell.x;
                if (@as(usize, column) + 1 >= line_columns) return error.UnsupportedScene;
                const lead = cells[column];
                const tail = cells[column + 1];
                try validate(lead);
                try validate(tail);
                if (!lead.semantic_width or lead.width != 2 or lead.x != 0 or
                    !tail.semantic_width or tail.width != 2 or tail.x != 1) return error.UnsupportedScene;
                cell = lead;
                width = 2;
            }
            const scale: u32 = if (geometry == .single_width) 1 else 2;
            const surface_width: u32 = @as(u32, columns) * cell_width;
            const left: u32 = @as(u32, column) * cell_width * scale;
            const right = @min(surface_width, left + @as(u32, cell_width) * width * scale);
            if (right <= left or right > std.math.maxInt(u16)) return error.UnsupportedScene;
            var rect: frame.Rect = .{ .x = @intCast(left), .y = @as(i32, cursor.row) * cell_height, .width = @intCast(right - left), .height = cell_height };
            const cell_rect = rect;
            switch (cursor.effective_shape) {
                .block => {},
                .none => return null,
                .bar => rect.width = @min(rect.width, stroke),
                .underline => {
                    const thickness = @min(rect.height, stroke);
                    rect.y += rect.height - thickness;
                    rect.height = thickness;
                },
            }
            const p = vt.presentation();
            const resolved = try colors(cell, p);
            var color = if (p.cursor) |explicit| rgba(explicit) else resolved.fg;
            if (p.cursor == null) {
                color.a = 255;
                if (color.r == resolved.bg.r and color.g == resolved.bg.g and color.b == resolved.bg.b) {
                    const brightness = @as(u32, resolved.bg.r) * 299 + @as(u32, resolved.bg.g) * 587 + @as(u32, resolved.bg.b) * 114;
                    const channel: u8 = if (brightness >= 128000) 0 else 255;
                    color = .{ .r = channel, .g = channel, .b = channel, .a = 255 };
                }
            }
            var ink = if (p.cursor_text) |explicit| rgba(explicit) else resolved.bg;
            if (p.cursor_text == null) {
                ink.a = 255;
                if (ink.r == color.r and ink.g == color.g and ink.b == color.b) {
                    const brightness = @as(u32, color.r) * 299 + @as(u32, color.g) * 587 + @as(u32, color.b) * 114;
                    const channel: u8 = if (brightness >= 128000) 0 else 255;
                    ink = .{ .r = channel, .g = channel, .b = channel, .a = 255 };
                }
            }
            return .{ .command = .{ .solid = .{ .rect = rect, .color = color } }, .cell = cell_rect, .text_color = ink, .shape = cursor.effective_shape };
        }
    };
}
