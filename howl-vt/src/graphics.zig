//! Owns bounded terminal images, animation frames, and cell-relative placements.

const std = @import("std");
const png = @import("png.zig");
const properties = @import("properties.zig");

// File map:
//   - fixed bounds and graphics command vocabulary
//   - retained Plane lifecycle, admission, placement, and animation
//   - Kitty command parsing, geometry, and RGBA composition
//   - transactional placement, frame, animation, and failure proofs

// =============================================================================
// Graphics vocabulary and fixed bounds
// =============================================================================

/// Bounds decoded image bytes retained by one terminal.
pub const max_storage_bytes: usize = 64 * 1024 * 1024;
/// Bounds one decoded RGBA image.
pub const max_image_bytes: usize = 16 * 1024 * 1024;
/// Bounds retained image identities.
pub const max_images: usize = 256;
// Cell-tiled previews at the supported image limit can need thousands of
// distinct placement identities. The v8 1 MiB external graphics manifest
// still uses its fixed 52-byte placement records; this Plane's private
// parent graph does not extend the published manifest or renderer ABI.
/// Bounds distinct retained image placements without merging client identities.
pub const max_placements: usize = 16 * 1024;
/// Physical placement ancestry is bounded independently of the image quota.
const max_parent_depth: u8 = 16;
/// Bounds retained animation frames across one terminal.
const max_frames: usize = 256;
/// Bounds either image dimension before byte-count validation.
pub const max_dimension: u32 = 4096;
/// Bounds one encoded Kitty APC command chunk.
pub const max_command_bytes: usize = 8192;
// The packet ceiling also includes metadata. Only the encoded data has
// the author protocol's separate 4096-byte per-chunk ceiling.
const max_chunk_bytes: usize = 4096;
/// Bounds one in-flight compressed direct payload above decoded image quota.
const max_compressed_bytes: usize = max_image_bytes + 128 * 1024;
// Indexed images retain their source indices as well as the public RGBA view.
// f=16 can require two extra bytes per pixel above the 16 MiB RGBA limit.
const max_indexed_retained_bytes: usize = max_image_bytes + max_image_bytes / 2;
const default_indexed_colors: properties.ColorState = .{};

/// Identifies the screen bank owning one placement.
pub const Bank = enum { primary, alternate };

/// Borrows immutable decoded RGBA pixels until plane mutation.
pub const ImageView = struct {
    /// Plane-owned nonzero image identity.
    id: u32,
    /// Pixel width.
    width: u32,
    /// Pixel height.
    height: u32,
    /// Monotonic content identity used by retained image storage.
    generation: u64,
    /// Exact row-major RGBA8 pixels.
    pixels: []const u8,
};

/// Copies one ordinary cell-relative placement.
const Placement = struct {
    /// Image identity resolved by the plane.
    image_id: u32,
    /// Optional application-selected Kitty placement identity.
    kitty_id: u32,
    /// Monotonic placement identity.
    generation: u64,
    /// Stable placement identity across re-put, unlike render generation.
    identity: u64 = 0,
    /// Zero denotes a normal cursor-anchored placement.
    parent_identity: u64 = 0,
    /// Dense index validated against stable parent_identity. Retirement
    /// rebinds this in one bounded scan instead of searching per draw.
    parent_slot: ?u16 = null,
    parent_col_offset: i32 = 0,
    parent_row_offset: i32 = 0,
    /// Screen bank owning this placement.
    bank: Bank,
    /// Primary absolute projected row or alternate screen row.
    row: u64,
    /// Physical terminal column.
    col: u16,
    /// Selects the first decoded source column.
    source_x: u32,
    /// Selects the first decoded source row.
    source_y: u32,
    /// Counts selected decoded source columns.
    source_width: u32,
    /// Counts selected decoded source rows.
    source_height: u32,
    /// Offsets the destination within its anchor cell horizontally.
    cell_x: u32,
    /// Offsets the destination within its anchor cell vertically.
    cell_y: u32,
    /// Cell height at placement admission, needed for exact scroll clipping.
    cell_height: u32,
    /// Counts destination pixels horizontally.
    pixel_width: u32,
    /// Counts destination pixels vertically.
    pixel_height: u32,
    /// Signed Kitty layer relative to terminal text.
    z: i32,
    /// Counts occupied terminal rows at placement time.
    rows: u16,
    /// Counts occupied physical terminal columns at placement time.
    cols: u16,
    /// Retains an invisible Kitty Unicode-placeholder prototype.
    virtual: bool = false,
};

const Image = struct {
    id: u32,
    /// Screen bank in which the retained decoded bytes were admitted.
    /// Placements can be tracked separately, including across banks.
    bank: Bank,
    kitty_id: ?u32,
    kitty_number: ?u32,
    width: u32,
    height: u32,
    generation: u64,
    pixels: []u8,
    /// Original one/two-byte indices, retained for live palette changes.
    /// Null keeps RGB/RGBA/PNG and animation-frame ownership unchanged.
    indexed_pixels: ?[]u8 = null,
    indexed_format: u8 = 0,
    /// Exact palette index set for skipping unrelated OSC color mutations.
    indexed_used: [4]u64 = @splat(0),
    current_frame: u16 = 0,
    root_gap_ms: u32 = 0,
    animation: AnimationState = .stopped,
    max_loops: u32 = 0,
    loops_remaining: u32 = 0,
    frame_started_ms: ?u64 = null,
};

// The first 248 Kitty indexed colors share the canonical SGR palette. The
// remaining slots name terminal-wide presentation values, not palette[248..].
// Howl does not currently expose a dedicated hovered-URL color (254), so it
// uses its normal foreground until the host adds that independent policy.
fn indexedColor(colors: *const properties.ColorState, index: u8) properties.Rgb {
    return switch (index) {
        0...247 => colors.palette[index],
        248 => colors.background,
        249, 255 => colors.foreground,
        250 => colors.selection_background orelse colors.foreground,
        251 => colors.selection_foreground orelse colors.background,
        252 => colors.cursor orelse colors.foreground,
        253 => colors.cursor_text orelse colors.background,
        254 => colors.foreground,
    };
}

// Every pixel remains a canonical index until this owned RGBA projection.
// The same routine services initial indexed admission and later color changes.
fn recolorIndexed(
    rgba: []u8,
    source: []const u8,
    format: u8,
    colors: *const properties.ColorState,
    initial: bool,
) bool {
    std.debug.assert(format == 8 or format == 16);
    const channels: usize = format / 8;
    std.debug.assert(rgba.len / 4 == source.len / channels and rgba.len % 4 == 0);
    var changed = false;
    for (0..rgba.len / 4) |pixel| {
        const color = indexedColor(colors, source[pixel * channels]);
        const alpha: u8 = if (format == 8) 255 else source[pixel * channels + 1];
        const output = rgba[pixel * 4 ..][0..4];
        // First admission owns uninitialized destination bytes. Never read
        // them before writing the initial canonical RGBA projection.
        if (initial or output[0] != color.r or output[1] != color.g or output[2] != color.b or output[3] != alpha) {
            output.* = .{ color.r, color.g, color.b, alpha };
            changed = true;
        }
    }
    return changed;
}

fn indexedUse(source: []const u8, format: u8) [4]u64 {
    std.debug.assert(format == 8 or format == 16);
    const stride: usize = format / 8;
    std.debug.assert(source.len % stride == 0);
    var used: [4]u64 = @splat(0);
    for (0..source.len / stride) |pixel| {
        const index = source[pixel * stride];
        used[index / 64] |= @as(u64, 1) << @as(u6, @intCast(index % 64));
    }
    return used;
}

const AnimationState = enum { stopped, loading, running };

const Frame = struct {
    image_id: u32,
    number: u16,
    gap_ms: u32,
    pixels: []u8,
};

const Loading = struct {
    action: u8,
    format: u8,
    /// True when the application omitted both Kitty image id and image number.
    /// Kitty calls this protocol-visible image id zero. The Plane still owns a
    /// separate nonzero internal Image.id for storage/resource identity.
    anonymous: bool,
    id: u32,
    image_number: u32,
    placement_id: u32,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    columns: u32,
    rows: u32,
    cell_x: u32,
    cell_y: u32,
    background_rgba: u32,
    z: i32,
    compose_mode: u2,
    unicode_placement: bool,
    compression: u8,
    expected_bytes: usize,
    width: u32,
    height: u32,
    quiet: u2,
    bytes: []u8,
    used: usize = 0,
};

/// Reports one Kitty placement-driven terminal cursor consequence.
pub const CursorAdvance = struct {
    cols: u16,
    rows: u16,
};

/// Reports exact bounded Kitty graphics admission.
const Result = struct {
    /// True when retained images or placements changed.
    changed: bool = false,
    /// True when a semantic change alters the currently visible image plane.
    visual_changed: bool = true,
    /// Image identity echoed by a protocol response.
    response_id: ?u32 = null,
    /// Image number echoed alongside generated or selected identity.
    response_number: ?u32 = null,
    /// Placement identity echoed by a placement acknowledgement.
    response_placement: ?u32 = null,
    /// Admitted frame number, or the requested number on rejection.
    response_frame: ?u32 = null,
    /// Null identifies success; otherwise supplies Kitty's stable short error.
    failure: ?Failure = null,
    /// Moves the terminal cursor after one successful ordinary placement.
    cursor_advance: ?CursorAdvance = null,
    /// Suppresses success or all responses according to `q`.
    quiet: u2 = 0,
    /// Borrows a completed feature query for reply formatting. No graphics
    /// mutation occurs, and the borrowed bytes outlive the synchronous reply.
    feature_query: ?[]const u8 = null,
};

/// Names one bounded terminal-graphics rejection.
pub const Failure = enum {
    invalid,
    unsupported,
    quota,
    missing,
    parent_missing,
    cycle,
    too_deep,

    /// Returns the Kitty response token.
    pub fn bytes(self: Failure) []const u8 {
        return switch (self) {
            .invalid => "EINVAL",
            .unsupported => "ENOTSUP",
            .quota => "ENOSPC",
            .missing => "ENOENT",
            .parent_missing => "ENOPARENT",
            .cycle => "ECYCLE",
            .too_deep => "ETOODEEP",
        };
    }
};

/// Reports one monotonic animation service result.
pub const AnimationTick = struct {
    /// True when a currently displayed frame changed.
    changed: bool,
    /// True when frame or run-state mutation was accepted.
    semantic_changed: bool,
    /// Milliseconds until the next frame boundary, or null when idle.
    next_ms: ?u32,
};

const Command = struct {
    action: u8 = 't',
    medium: u8 = 'd',
    format: u8 = 32,
    compression: u8 = 0,
    uncompressed_bytes: usize = 0,
    id: u32 = 0,
    image_number: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    more: bool = false,
    quiet: u2 = 0,
    delete: u8 = 0,
    placement_id: u32 = 0,
    parent_id: u32 = 0,
    parent_placement_id: u32 = 0,
    parent_col_offset: i32 = 0,
    parent_row_offset: i32 = 0,
    source_width: u32 = 0,
    source_height: u32 = 0,
    columns: u32 = 0,
    rows: u32 = 0,
    cell_x: u32 = 0,
    cell_y: u32 = 0,
    z: i32 = 0,
    compose_mode: u2 = 0,
    unicode_placement: bool = false,
    /// Advisory Kitty usage-hint bitmask. Howl intentionally owns no cache
    /// policy here; accepting and ignoring hints is protocol-compliant.
    usage_hints: u32 = 0,
    /// Kitty 0.50+ e=ACTION is meaningful only on a=q feature queries.
    feature_action: u8 = 0,
    /// Presence bits prevent reporting default values never queried.
    present: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    payload: []const u8 = "",
};

const ReplyIdentity = struct {
    id: ?u32,
    number: ?u32,
    placement: ?u32,
    frame: ?u32,

    fn command(value: Command) ReplyIdentity {
        return .{
            .id = nonzero(value.id),
            .number = nonzero(value.image_number),
            .placement = nonzero(value.placement_id),
            .frame = if (value.action == 'f') nonzero(value.rows) else null,
        };
    }

    fn loading(value: *const Loading) ReplyIdentity {
        return .{
            .id = if (value.anonymous) null else nonzero(value.id),
            .number = nonzero(value.image_number),
            .placement = nonzero(value.placement_id),
            .frame = if (value.action == 'f') nonzero(value.rows) else null,
        };
    }

    fn complete(self: ReplyIdentity, result: Result) Result {
        // Incomplete chunks and silent deletions have no response identity.
        if (result.failure == null and result.response_id == null and
            result.response_number == null and result.response_frame == null) return result;
        var reply = result;
        reply.response_id = nonzero(reply.response_id orelse 0) orelse self.id;
        reply.response_number = reply.response_number orelse self.number;
        if (reply.response_id != null or reply.response_number != null)
            reply.response_placement = self.placement;
        reply.response_frame = reply.response_frame orelse self.frame;
        return reply;
    }
};

// Every selector admitted by Plane.delete also qualifies for e=d queries.
// The query formatter uses the same vocabulary, but only reports fields
// consumed by the selected deletion mode.
const delete_selectors = "afinrpqxyzc";

// =============================================================================
// Retained graphics plane
// =============================================================================

/// Owns decoded image/frame bytes, placements, animation state, and one transfer.
pub const Plane = struct {
    /// Borrowed only for one synchronous graphics command invocation.
    // zig-audit: acknowledge anyopaque
    // reason: The plain image owner cannot depend on the terminal's canonical Unicode view type; the caller restores its exact short-lived type in the callback.
    pub const AnchorContext = *anyopaque;
    /// Optional read-only canonical Unicode anchor resolver for geometric
    /// deletions. Plain Planes remain independently usable without a screen.
    /// The caller owns the context and may use it only for this command.
    pub const AnchorSource = struct {
        context: AnchorContext,
        resolve: *const fn (AnchorContext, u16) ?Anchor,
    };
    // -------------------------------------------------------------------------
    // Retained graphics ownership
    // -------------------------------------------------------------------------

    // Decoded image storage and internal/application identities.
    allocator: std.mem.Allocator,
    images: [max_images]Image = undefined,
    image_count: u16 = 0,
    // Cell-relative placements across the primary and alternate banks.
    placements: [max_placements]Placement = undefined,
    placement_count: u16 = 0,
    // Animation-frame storage shared by retained images.
    frames: [max_frames]Frame = undefined,
    frame_count: u16 = 0,
    // Global storage accounting and monotonic mutation identities.
    storage_bytes: usize = 0,
    next_generation: u64 = 0,
    next_image_id: u32 = 0,
    content_generation: u64 = 0,
    // One optional chunked transfer under construction.
    loading: ?Loading = null,

    // -------------------------------------------------------------------------
    // Construction, teardown, and command dispatch
    // -------------------------------------------------------------------------

    /// Initializes an empty plane borrowing `allocator` through `deinit`.
    pub fn init(allocator: std.mem.Allocator) Plane {
        return .{ .allocator = allocator };
    }

    /// Releases transfer and retained image allocations.
    pub fn deinit(self: *Plane) void {
        self.cancel();
        for (self.images[0..self.image_count]) |retained| {
            self.allocator.free(retained.pixels);
            if (retained.indexed_pixels) |source| self.allocator.free(source);
        }
        for (self.frames[0..self.frame_count]) |retained| self.allocator.free(retained.pixels);
        self.* = undefined;
    }

    /// Cancels one incomplete transfer without changing retained images.
    pub fn cancel(self: *Plane) void {
        if (self.loading) |loading| self.allocator.free(loading.bytes);
        self.loading = null;
    }

    /// Reprojects retained palette-indexed image pixels only when an indexed
    /// color they actually use changes. The canonical index bytes stay owned
    /// here; held native output copies remain immutable across color updates.
    /// No allocations or image-data replacement are needed for a recolor.
    pub fn refreshIndexedColors(self: *Plane, prior: *const properties.ColorState, current: *const properties.ColorState) bool {
        if (self.image_count == 0 or std.meta.eql(prior.*, current.*)) return false;
        var has_indexed = false;
        for (self.images[0..self.image_count]) |retained| {
            if (retained.indexed_pixels != null) {
                has_indexed = true;
                break;
            }
        }
        if (!has_indexed) return false;
        var affected: [4]u64 = @splat(0);
        for (0..256) |index| {
            if (!std.meta.eql(indexedColor(prior, @intCast(index)), indexedColor(current, @intCast(index)))) {
                affected[index / 64] |= @as(u64, 1) << @as(u6, @intCast(index % 64));
            }
        }
        if (std.mem.allEqual(u64, &affected, 0)) return false;
        var mutated: [max_images]bool = @splat(false);
        var changed = false;
        for (self.images[0..self.image_count], 0..) |*retained, index| {
            const source = retained.indexed_pixels orelse continue;
            var intersects = false;
            for (retained.indexed_used, affected) |used, changed_indices| {
                if (used & changed_indices != 0) {
                    intersects = true;
                    break;
                }
            }
            if (!intersects) continue;
            mutated[index] = recolorIndexed(retained.pixels, source, retained.indexed_format, current, false);
            changed = changed or mutated[index];
        }
        if (!changed) return false;
        self.advance();
        self.content_generation = self.next_generation;
        for (self.images[0..self.image_count], 0..) |*retained, index| {
            if (mutated[index]) retained.generation = self.next_generation;
        }
        return true;
    }

    /// Applies one complete `_G` APC body after the leading `G`.
    ///
    /// Allocation and rejected commands preserve all retained images and placements.
    /// Successful Kitty image admission may reclaim older retained image data
    /// when needed to stay inside the fixed graphics storage quota.
    pub fn command(
        self: *Plane,
        bytes: []const u8,
        bank: Bank,
        screen_origin: u64,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) std.mem.Allocator.Error!Result {
        return self.commandWithAnchors(bytes, bank, screen_origin, row, col, cell_width, cell_height, null, null);
    }

    // Use the same admission classification for preflight and dispatch.
    // No borrowed loading bytes escape this synchronous decision.
    fn continuation(self: *const Plane, value: Command) ?*const Loading {
        const loading = if (self.loading) |*active| active else return null;
        if (value.medium != 'd' or value.feature_action != 0) return null;
        if (value.id != 0 or value.image_number != 0) return null;
        if (value.action == 'f') return loading;
        if (value.action != 't' and value.action != 'T' and value.action != 'q') return null;
        if (value.width != 0 or value.height != 0 or value.placement_id != 0) return null;
        return loading;
    }

    /// Reports whether an ordinary command needs preflight reply headroom.
    /// Valid feature queries reserve their exact bytes separately.
    pub fn mayRespond(self: *const Plane, bytes: []const u8) bool {
        const value = parseCommand(bytes) orelse return true;
        if (value.quiet == 2) return false;
        if (value.feature_action != 0)
            return value.action != 'q' or value.id == 0 or value.image_number != 0;
        // A conflicting identity pair is rejected before ordinary dispatch.
        if (value.id != 0 and value.image_number != 0) return true;
        if (value.medium != 'd') return true;
        if (value.action == 'd') return false;
        if (value.quiet == 0) if (self.continuation(value)) |loading|
            return loading.quiet != 2;
        return true;
    }

    /// Applies a graphics command with optional text-derived virtual-parent
    /// positions for geometry deletions. An absent resolver keeps the Plane
    /// independent from terminal cell storage and ignores unanchored hits.
    pub fn commandWithAnchors(
        self: *Plane,
        bytes: []const u8,
        bank: Bank,
        screen_origin: u64,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        anchors: ?AnchorSource,
        colors: ?*const properties.ColorState,
    ) std.mem.Allocator.Error!Result {
        if (bytes.len > max_command_bytes) return .{ .failure = .quota };
        const command_value = parseCommand(bytes) orelse {
            self.cancel();
            return .{ .failure = .invalid };
        };
        const continuation_load = self.continuation(command_value);
        const identity = if (continuation_load) |loading|
            ReplyIdentity.loading(loading)
        else
            ReplyIdentity.command(command_value);
        if (command_value.id != 0 and command_value.image_number != 0)
            return identity.complete(.{ .failure = .invalid, .quiet = command_value.quiet });
        if (command_value.feature_action != 0) {
            // Kitty feature queries are observations. They must not cancel
            // an ongoing chunked image upload, even if they carry a payload.
            if (command_value.action != 'q' or command_value.id == 0 or
                command_value.image_number != 0)
                return identity.complete(.{ .failure = .invalid, .quiet = command_value.quiet });
            // Current Kitty rejects invalid delete-selector bytes at parse
            // time. A feature query must neither fabricate an e=d success
            // nor cancel a suspended upload when d has an unknown value.
            if (command_value.delete != 0 and
                std.mem.indexOfScalar(u8, delete_selectors, std.ascii.toLower(command_value.delete)) == null)
                return .{ .quiet = 2 };
            return .{
                .response_id = command_value.id,
                .feature_query = bytes,
                .quiet = command_value.quiet,
            };
        }
        if (command_value.medium != 'd') {
            self.cancel();
            return identity.complete(.{ .failure = .unsupported, .quiet = command_value.quiet });
        }
        const result: Result = switch (command_value.action) {
            't', 'T', 'q' => try self.transmit(command_value, bank, row, col, cell_width, cell_height, colors orelse &default_indexed_colors),
            'f' => if (continuation_load != null)
                try self.continueChunk(command_value, bank, row, col, cell_width, cell_height, colors orelse &default_indexed_colors)
            else
                try self.frame(command_value),
            'a' => self.animate(command_value),
            'c' => try self.composeFrames(command_value),
            'p' => self.put(command_value, bank, row, col, cell_width, cell_height),
            'd' => self.delete(command_value, bank, screen_origin, row, col, anchors),
            else => .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .unsupported,
                .quiet = command_value.quiet,
            },
        };
        return identity.complete(result);
    }

    // -------------------------------------------------------------------------
    // Chunked image transmission
    // -------------------------------------------------------------------------

    fn transmit(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        colors: *const properties.ColorState,
    ) std.mem.Allocator.Error!Result {
        errdefer self.cancel();
        if (self.loading != null) {
            // Preserve the existing recovery policy: an unmistakable new
            // image header abandons an unfinished transfer. Otherwise
            // validate the continuation by field presence, not values.
            if (self.continuation(command_value) != null)
                return self.continueChunk(command_value, bank, row, col, cell_width, cell_height, colors);
            self.cancel();
        }
        if (!validChunk(command_value)) return .{
            .response_id = nonzero(command_value.id),
            .response_number = nonzero(command_value.image_number),
            .failure = .invalid,
            .quiet = command_value.quiet,
        };
        const is_png = command_value.format == 100;
        if ((command_value.id != 0 and command_value.image_number != 0) or
            (!is_png and (command_value.width == 0 or command_value.height == 0)) or
            command_value.width > max_dimension or command_value.height > max_dimension or
            (command_value.format != 8 and command_value.format != 16 and
                command_value.format != 24 and command_value.format != 32 and !is_png))
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .invalid,
                .quiet = command_value.quiet,
            };
        const channels: usize = switch (command_value.format) {
            8 => 1,
            16 => 2,
            24 => 3,
            else => 4,
        };
        const pixels = std.math.mul(usize, command_value.width, command_value.height) catch
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .quota,
                .quiet = command_value.quiet,
            };
        const rgba_bytes = std.math.mul(usize, pixels, 4) catch
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .quota,
                .quiet = command_value.quiet,
            };
        const input_bytes = std.math.mul(usize, pixels, channels) catch
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .quota,
                .quiet = command_value.quiet,
            };
        if (rgba_bytes > max_image_bytes)
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .quota,
                .quiet = command_value.quiet,
            };
        const anonymous = command_value.id == 0 and command_value.image_number == 0;
        const kitty_id = if (command_value.id != 0)
            command_value.id
        else if (anonymous)
            0
        else
            self.allocateKittyId() orelse
                return .{ .response_number = command_value.image_number, .failure = .quota, .quiet = command_value.quiet };
        if (command_value.compression != 0 and command_value.compression != 'z')
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .unsupported,
                .quiet = command_value.quiet,
            };
        if (is_png and command_value.compression == 'z' and
            (command_value.uncompressed_bytes == 0 or command_value.uncompressed_bytes > max_compressed_bytes))
            return .{ .response_id = nonzero(command_value.id), .failure = .invalid, .quiet = command_value.quiet };
        if (!is_png and command_value.uncompressed_bytes != 0 and
            command_value.uncompressed_bytes != input_bytes)
            return .{ .response_id = nonzero(command_value.id), .failure = .invalid, .quiet = command_value.quiet };
        const expected_bytes = if (is_png) command_value.uncompressed_bytes else input_bytes;
        const storage_bytes = if (is_png)
            @as(usize, max_command_bytes)
        else if (command_value.compression == 'z')
            compressedInputCapacity(input_bytes) orelse
                return .{
                    .response_id = nonzero(command_value.id),
                    .response_number = nonzero(command_value.image_number),
                    .failure = .quota,
                    .quiet = command_value.quiet,
                }
        else
            input_bytes;
        const input = try self.allocator.alloc(u8, storage_bytes);
        self.loading = .{
            .action = command_value.action,
            .format = command_value.format,
            .anonymous = anonymous,
            .id = kitty_id,
            .image_number = command_value.image_number,
            .placement_id = command_value.placement_id,
            .source_x = command_value.x,
            .source_y = command_value.y,
            .source_width = command_value.source_width,
            .source_height = command_value.source_height,
            .columns = command_value.columns,
            .rows = command_value.rows,
            .cell_x = command_value.cell_x,
            .cell_y = command_value.cell_y,
            .background_rgba = 0,
            .z = command_value.z,
            .compose_mode = command_value.compose_mode,
            .unicode_placement = command_value.unicode_placement,
            .compression = command_value.compression,
            .expected_bytes = expected_bytes,
            .width = command_value.width,
            .height = command_value.height,
            .quiet = command_value.quiet,
            .bytes = input,
        };
        return self.appendChunk(command_value, bank, row, col, cell_width, cell_height, colors);
    }

    fn validChunk(command_value: Command) bool {
        return command_value.payload.len <= max_chunk_bytes and
            (!command_value.more or command_value.payload.len % 4 == 0);
    }

    fn rejectLoading(self: *Plane, failure: Failure) Result {
        const loading = self.loading.?;
        const result: Result = .{
            .response_id = if (loading.anonymous) null else loading.id,
            .response_number = nonzero(loading.image_number),
            .failure = failure,
            .quiet = loading.quiet,
        };
        self.cancel();
        return result;
    }

    fn continueChunk(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        colors: *const properties.ColorState,
    ) std.mem.Allocator.Error!Result {
        const loading = &self.loading.?;
        // The pinned implementation inherits an earlier quiet value
        // unless a nonzero override is sent. Retain one effective value.
        if (command_value.quiet != 0) loading.quiet = command_value.quiet;
        const continuation_fields: u32 = (1 << 6) | (1 << 7); // m, q
        const action_field: u32 = 1 << 0;
        const explicit_frame = loading.action == 'f' and command_value.action == 'f';
        const allowed = continuation_fields | (if (explicit_frame) action_field else 0);
        if (command_value.present & ~allowed != 0)
            return self.rejectLoading(.invalid);
        return self.appendChunk(command_value, bank, row, col, cell_width, cell_height, colors);
    }

    fn appendChunk(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        colors: *const properties.ColorState,
    ) std.mem.Allocator.Error!Result {
        errdefer self.cancel();
        if (!validChunk(command_value)) return self.rejectLoading(.invalid);
        const loading = &self.loading.?;
        // kitten icat emits unpadded base64; both forms are valid Kitty data.
        const decoder = if (std.mem.endsWith(u8, command_value.payload, "="))
            std.base64.standard.Decoder
        else
            std.base64.standard_no_pad.Decoder;
        const decoded_len = decoder.calcSizeForSlice(command_value.payload) catch {
            return self.rejectLoading(.invalid);
        };
        if (loading.format == 100 and decoded_len > loading.bytes.len - loading.used) {
            const maximum = if (loading.compression == 'z')
                compressedInputCapacity(loading.expected_bytes) orelse max_compressed_bytes
            else
                max_compressed_bytes;
            const total = std.math.add(usize, loading.used, decoded_len) catch maximum + 1;
            if (total <= maximum) {
                const capacity = @min(maximum, @max(total, loading.bytes.len * 2));
                loading.bytes = try self.allocator.realloc(loading.bytes, capacity);
            }
        }
        if (decoded_len > loading.bytes.len - loading.used) {
            return self.rejectLoading(.quota);
        }
        decoder.decode(
            loading.bytes[loading.used..][0..decoded_len],
            command_value.payload,
        ) catch {
            return self.rejectLoading(.invalid);
        };
        loading.used += decoded_len;
        if (command_value.more) return .{ .quiet = loading.quiet };
        if (loading.format == 100) {
            if (loading.compression == 'z' and !(try inflateLoading(self))) {
                return self.rejectLoading(.invalid);
            }
            const decoded = png.decode(self.allocator, self.loading.?.bytes[0..self.loading.?.used]) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.rejectLoading(switch (err) {
                    error.Quota => .quota,
                    error.Unsupported => .unsupported,
                    else => .invalid,
                });
            };
            if ((loading.width != 0 and loading.width != decoded.width) or
                (loading.height != 0 and loading.height != decoded.height))
            {
                self.allocator.free(decoded.pixels);
                return self.rejectLoading(.invalid);
            }
            self.allocator.free(loading.bytes);
            loading.bytes = decoded.pixels;
            loading.used = decoded.pixels.len;
            loading.expected_bytes = decoded.pixels.len;
            loading.width = decoded.width;
            loading.height = decoded.height;
            loading.format = 32;
            loading.compression = 0;
        } else if (loading.compression == 0) {
            if (loading.used != loading.expected_bytes) {
                return self.rejectLoading(.invalid);
            }
        } else if (!(try inflateLoading(self))) {
            return self.rejectLoading(.invalid);
        }
        return try self.finish(bank, row, col, cell_width, cell_height, colors);
    }

    // -------------------------------------------------------------------------
    // Animation frame admission and composition
    // -------------------------------------------------------------------------

    fn frame(self: *Plane, command_value: Command) std.mem.Allocator.Error!Result {
        if (self.loading != null) {
            self.cancel();
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        }
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = self.images[image_index];
        if (image_value.indexed_pixels != null)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (command_value.cell_x > 1)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const documented_compose_mode: u2 = @intCast(command_value.cell_x);
        if (documented_compose_mode != 0 and command_value.compose_mode != 0 and
            documented_compose_mode != command_value.compose_mode)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const compose_mode = if (documented_compose_mode != 0)
            documented_compose_mode
        else
            command_value.compose_mode;
        const width = if (command_value.width == 0) image_value.width else command_value.width;
        const height = if (command_value.height == 0) image_value.height else command_value.height;
        if (width > image_value.width or height > image_value.height or
            command_value.x > image_value.width - width or command_value.y > image_value.height - height or
            (command_value.format != 24 and command_value.format != 32))
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (command_value.compression != 0 and command_value.compression != 'z')
            return .{ .response_id = image_value.kitty_id, .failure = .unsupported, .quiet = command_value.quiet };
        const channels: usize = if (command_value.format == 24) 3 else 4;
        const input_bytes = std.math.mul(usize, width, height) catch
            return .{ .response_id = image_value.kitty_id, .failure = .quota, .quiet = command_value.quiet };
        const byte_count = std.math.mul(usize, input_bytes, channels) catch
            return .{ .response_id = image_value.kitty_id, .failure = .quota, .quiet = command_value.quiet };
        const storage_bytes = if (command_value.compression == 'z')
            compressedInputCapacity(byte_count) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .quota, .quiet = command_value.quiet }
        else
            byte_count;
        if (!validChunk(command_value)) return .{
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .failure = .invalid,
            .quiet = command_value.quiet,
        };
        const input = try self.allocator.alloc(u8, storage_bytes);
        self.loading = .{
            .action = 'f',
            .format = command_value.format,
            .anonymous = false,
            .id = image_value.kitty_id.?,
            .image_number = image_value.kitty_number orelse 0,
            .placement_id = 0,
            .source_x = command_value.x,
            .source_y = command_value.y,
            .source_width = 0,
            .source_height = 0,
            .columns = command_value.columns,
            .rows = command_value.rows,
            .cell_x = 0,
            .cell_y = 0,
            .background_rgba = command_value.cell_y,
            .z = command_value.z,
            .compose_mode = compose_mode,
            .unicode_placement = false,
            .compression = command_value.compression,
            .expected_bytes = byte_count,
            .width = width,
            .height = height,
            .quiet = command_value.quiet,
            .bytes = input,
        };
        return self.appendChunk(command_value, .primary, 0, 0, 1, 1, &default_indexed_colors);
    }

    fn finishFrame(self: *Plane, loading: Loading) std.mem.Allocator.Error!Result {
        const image_index = self.kittyImageIndex(loading.id) orelse
            return .{ .response_id = loading.id, .failure = .missing, .quiet = loading.quiet };
        const image_value = self.images[image_index];
        const next_number = self.nextFrameNumber(image_value.id) orelse
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const requested = if (loading.rows == 0)
            next_number
        else
            std.math.cast(u16, loading.rows) orelse
                return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet };
        if (requested == 0)
            return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet };
        const frame_number = @min(requested, next_number);
        const root = frame_number == 1;
        const existing = self.frameIndex(image_value.id, frame_number);
        const editing_existing = root or existing != null;
        if (!root and existing == null and self.frame_count == max_frames)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const canvas_bytes = image_value.pixels.len;
        const prior_bytes = if (root)
            image_value.pixels.len
        else if (existing) |index|
            self.frames[index].pixels.len
        else
            0;
        if (canvas_bytes > max_image_bytes or self.storage_bytes - prior_bytes > max_storage_bytes - canvas_bytes)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        const base: ?[]const u8 = if (root)
            image_value.pixels
        else if (existing) |index|
            self.frames[index].pixels
        else if (loading.columns == 0)
            null
        else
            self.framePixels(image_value, loading.columns) orelse
                return .{ .response_id = loading.id, .failure = .missing, .quiet = loading.quiet };
        const canvas = try self.allocator.alloc(u8, canvas_bytes);
        errdefer self.allocator.free(canvas);
        if (base) |pixels|
            @memcpy(canvas, pixels)
        else
            fillRgba(canvas, loading.background_rgba);
        composeRgba(
            canvas,
            image_value.width,
            loading.bytes,
            loading.width,
            0,
            0,
            loading.format,
            loading.width,
            loading.height,
            loading.source_x,
            loading.source_y,
            loading.compose_mode != 1,
        );
        const prior_gap: u32 = if (root)
            image_value.root_gap_ms
        else if (existing) |index|
            self.frames[index].gap_ms
        else
            40;
        const gap: u32 = if (loading.z > 0)
            @intCast(loading.z)
        else if (loading.z < 0)
            0
        else if (editing_existing)
            prior_gap
        else
            40;
        if (root) {
            self.storage_bytes -= self.images[image_index].pixels.len;
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = canvas;
            self.images[image_index].root_gap_ms = gap;
        } else if (existing) |index| {
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
            self.frames[index] = .{ .image_id = image_value.id, .number = frame_number, .gap_ms = gap, .pixels = canvas };
        } else {
            self.frames[self.frame_count] = .{
                .image_id = image_value.id,
                .number = frame_number,
                .gap_ms = gap,
                .pixels = canvas,
            };
            self.frame_count += 1;
        }
        self.storage_bytes += canvas.len;
        const visible = self.images[image_index].current_frame + 1 == frame_number;
        if (visible) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{
            .changed = true,
            .visual_changed = visible,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .response_frame = frame_number,
            .quiet = loading.quiet,
        };
    }

    fn composeFrames(self: *Plane, command_value: Command) std.mem.Allocator.Error!Result {
        if ((command_value.id == 0) == (command_value.image_number == 0) or
            command_value.rows == 0 or command_value.columns == 0)
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = self.images[image_index];
        if (image_value.indexed_pixels != null)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const source = self.framePixels(image_value, command_value.rows) orelse
            return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        const destination_number = std.math.cast(u16, command_value.columns) orelse
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const destination_index = if (destination_number == 1)
            null
        else
            self.frameIndex(image_value.id, destination_number) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        // Kitty a79f376 names the composition rectangle w/h. Keep the
        // earlier Howl s/v spelling as a fallback, but documented w/h wins
        // whenever both are supplied. This is the same canonical parser
        // data used for a=c feature negotiation; no second rectangle owner.
        const copy_width = if (command_value.source_width != 0)
            command_value.source_width
        else if (command_value.width != 0)
            command_value.width
        else
            image_value.width;
        const copy_height = if (command_value.source_height != 0)
            command_value.source_height
        else if (command_value.height != 0)
            command_value.height
        else
            image_value.height;
        if (copy_width == 0 or copy_height == 0 or
            copy_width > image_value.width or copy_height > image_value.height or
            command_value.x > image_value.width -| copy_width or
            command_value.y > image_value.height -| copy_height or
            command_value.cell_x > image_value.width -| copy_width or
            command_value.cell_y > image_value.height -| copy_height)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (command_value.rows == command_value.columns and
            rectanglesOverlap(
                command_value.cell_x,
                command_value.cell_y,
                command_value.x,
                command_value.y,
                copy_width,
                copy_height,
            ))
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const destination = if (destination_index) |index|
            self.frames[index].pixels
        else
            image_value.pixels;
        const replacement = try self.allocator.dupe(u8, destination);
        errdefer self.allocator.free(replacement);
        composeRgba(
            replacement,
            image_value.width,
            source,
            image_value.width,
            command_value.cell_x,
            command_value.cell_y,
            32,
            copy_width,
            copy_height,
            command_value.x,
            command_value.y,
            command_value.compose_mode != 1,
        );
        if (destination_index) |index| {
            self.allocator.free(self.frames[index].pixels);
            self.frames[index].pixels = replacement;
        } else {
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = replacement;
        }
        const visible = image_value.current_frame + 1 == destination_number;
        if (visible) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{
            .changed = true,
            .visual_changed = visible,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
    }

    // -------------------------------------------------------------------------
    // Image finalization, placement, and deletion
    // -------------------------------------------------------------------------

    fn finish(
        self: *Plane,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        colors: *const properties.ColorState,
    ) std.mem.Allocator.Error!Result {
        const loading = self.loading.?;
        self.loading = null;
        defer self.allocator.free(loading.bytes);
        if (loading.action == 'f') return try self.finishFrame(loading);
        const rgba_len = @as(usize, loading.width) * loading.height * 4;
        if (loading.action == 'q')
            return .{ .response_id = if (loading.anonymous) null else loading.id, .quiet = loading.quiet };
        const prior_index = if (loading.anonymous or loading.image_number != 0)
            null
        else
            self.kittyImageIndex(loading.id);
        const protected_image_id = if (prior_index) |index| self.images[index].id else null;
        const display = loading.action == 'T';
        const replaced_placement = if (display and prior_index != null)
            self.placementIndex(self.images[prior_index.?].id, loading.placement_id)
        else
            null;
        if (replaced_placement) |index| {
            // A virtual placeholder needs a different text-owned anchor.
            // Until it is implemented, never strand children of an existing
            // physical placement by converting that parent in place.
            if (self.hasChildren(self.placements[index].identity) and
                (loading.unicode_placement or self.placements[index].bank != bank))
                return .{ .response_id = loading.id, .failure = .unsupported, .quiet = loading.quiet };
        }
        if (display and self.placement_count == max_placements and replaced_placement == null)
            return .{ .response_id = loading.id, .failure = .quota, .quiet = loading.quiet };
        var planned_placement = if (display)
            makePlacement(
                1,
                loading.placement_id,
                bank,
                row,
                col,
                cell_width,
                cell_height,
                loading.width,
                loading.height,
                loading.source_x,
                loading.source_y,
                loading.source_width,
                loading.source_height,
                loading.columns,
                loading.rows,
                loading.cell_x,
                loading.cell_y,
                loading.z,
                1,
            ) orelse return .{ .response_id = loading.id, .failure = .invalid, .quiet = loading.quiet }
        else
            null;
        if (planned_placement) |*placement_value| {
            placement_value.virtual = loading.unicode_placement;
            if (placement_value.virtual) {
                placement_value.row = 0;
                placement_value.col = 0;
            }
        }
        const rgba = try self.allocator.alloc(u8, rgba_len);
        errdefer self.allocator.free(rgba);
        const is_indexed = loading.format == 8 or loading.format == 16;
        const indexed_source: ?[]u8 = if (is_indexed)
            try self.allocator.dupe(u8, loading.bytes[0..loading.used])
        else
            null;
        errdefer if (indexed_source) |source| self.allocator.free(source);
        if (indexed_source) |source| {
            std.debug.assert(source.len == rgba_len / 4 * @as(usize, loading.format / 8));
            // Every admitted indexed image has at least one pixel; initial
            // projection must initialize the complete fresh RGBA allocation.
            std.debug.assert(recolorIndexed(rgba, source, loading.format, colors, true));
        } else if (loading.format == 32) {
            @memcpy(rgba, loading.bytes);
        } else {
            var source: usize = 0;
            var destination: usize = 0;
            while (source < loading.bytes.len) : ({
                source += 3;
                destination += 4;
            }) {
                @memcpy(rgba[destination..][0..3], loading.bytes[source..][0..3]);
                rgba[destination + 3] = 255;
            }
        }
        const retained_bytes = rgba.len + if (indexed_source) |source| source.len else @as(usize, 0);
        std.debug.assert(retained_bytes <= max_indexed_retained_bytes);
        self.reclaimForKittyAdmission(retained_bytes, protected_image_id);
        const admitted_prior_index = if (protected_image_id) |image_id|
            // zig-audit: acknowledge orelse_unreachable
            // reason: The owner invariant established before this lookup guarantees the value exists; absence would mean internal state corruption.
            self.imageIndex(image_id) orelse unreachable
        else
            null;
        const admitted_replaced_placement = if (display and protected_image_id != null)
            self.placementIndex(protected_image_id.?, loading.placement_id)
        else
            null;
        self.advance();
        const content_generation = self.next_generation;
        self.content_generation = content_generation;
        if (admitted_prior_index) |index| {
            const image_id = self.images[index].id;
            self.removeFrames(image_id);
            self.storage_bytes -= self.images[index].pixels.len;
            self.allocator.free(self.images[index].pixels);
            if (self.images[index].indexed_pixels) |source| {
                self.storage_bytes -= source.len;
                self.allocator.free(source);
            }
            self.images[index] = .{
                .id = image_id,
                .bank = bank,
                .kitty_id = loading.id,
                .kitty_number = nonzero(loading.image_number),
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
                .indexed_pixels = indexed_source,
                .indexed_format = if (is_indexed) loading.format else 0,
                .indexed_used = if (indexed_source) |source| indexedUse(source, loading.format) else @splat(0),
            };
        } else {
            const image_id = self.allocateImageId();
            self.images[self.image_count] = .{
                .id = image_id,
                .bank = bank,
                .kitty_id = loading.id,
                .kitty_number = nonzero(loading.image_number),
                .width = loading.width,
                .height = loading.height,
                .generation = content_generation,
                .pixels = rgba,
                .indexed_pixels = indexed_source,
                .indexed_format = if (is_indexed) loading.format else 0,
                .indexed_used = if (indexed_source) |source| indexedUse(source, loading.format) else @splat(0),
            };
            self.image_count += 1;
        }
        self.storage_bytes += retained_bytes;
        if (display) {
            const image_id = self.images[admitted_prior_index orelse self.image_count - 1].id;
            planned_placement.?.image_id = image_id;
            planned_placement.?.generation = content_generation;
            if (admitted_replaced_placement) |index| {
                // Updating one existing Kitty placement preserves its stable
                // identity so children follow the new parent geometry.
                planned_placement.?.identity = self.placements[index].identity;
                self.placements[index] = planned_placement.?;
            } else {
                planned_placement.?.identity = content_generation;
                self.placements[self.placement_count] = planned_placement.?;
                self.placement_count += 1;
            }
        }
        return .{
            .changed = true,
            .response_id = if (loading.anonymous) null else loading.id,
            .response_number = nonzero(loading.image_number),
            .cursor_advance = if (display and !loading.unicode_placement and loading.compose_mode != 1) .{
                .cols = planned_placement.?.cols,
                .rows = planned_placement.?.rows,
            } else null,
            .quiet = loading.quiet,
        };
    }

    fn put(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) Result {
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .invalid,
                .quiet = command_value.quiet,
            };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{
                .response_id = nonzero(command_value.id),
                .response_number = nonzero(command_value.image_number),
                .failure = .missing,
                .quiet = command_value.quiet,
            };
        const retained = self.images[image_index];
        var planned = makePlacement(
            retained.id,
            command_value.placement_id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            retained.width,
            retained.height,
            command_value.x,
            command_value.y,
            command_value.source_width,
            command_value.source_height,
            command_value.columns,
            command_value.rows,
            command_value.cell_x,
            command_value.cell_y,
            command_value.z,
            1,
        ) orelse return .{ .response_id = command_value.id, .failure = .invalid, .quiet = command_value.quiet };
        planned.virtual = command_value.unicode_placement;
        if (planned.virtual) {
            planned.row = 0;
            planned.col = 0;
        }
        const replacing = self.placementIndex(retained.id, command_value.placement_id);
        if (replacing) |index| {
            const previous = self.placements[index];
            if (self.hasChildren(previous.identity) and (planned.virtual or previous.bank != bank))
                return .{ .response_id = command_value.id, .failure = .unsupported, .quiet = command_value.quiet };
        }
        if (command_value.parent_id != 0) {
            if (planned.virtual) return .{ .response_id = command_value.id, .failure = .invalid, .quiet = command_value.quiet };
            const parent_index = self.parentPlacementIndex(command_value.parent_id, command_value.parent_placement_id, bank) orelse
                return .{ .response_id = command_value.id, .failure = .parent_missing, .quiet = command_value.quiet };
            const parent = self.placements[parent_index];
            // A virtual parent has no cursor anchor. The read-only native
            // projection resolves its location from matching U+10EEEE text;
            // admit the stable graph reference even before that text exists.
            if (replacing) |index| if (parent.identity == self.placements[index].identity)
                return .{ .response_id = command_value.id, .failure = .invalid, .quiet = command_value.quiet };
            if (self.parentError(parent.identity, if (replacing) |index| self.placements[index].identity else 0)) |failure|
                return .{ .response_id = command_value.id, .failure = failure, .quiet = command_value.quiet };
            if (replacing) |index| {
                if (self.hasChildren(self.placements[index].identity) and self.reparentExceedsDepth(index, parent_index))
                    return .{ .response_id = command_value.id, .failure = .too_deep, .quiet = command_value.quiet };
            }
            planned.parent_identity = parent.identity;
            planned.parent_slot = @intCast(parent_index);
            planned.parent_col_offset = command_value.parent_col_offset;
            planned.parent_row_offset = command_value.parent_row_offset;
        }
        if (self.placement_count == max_placements)
            if (replacing == null)
                return .{ .response_id = command_value.id, .failure = .quota, .quiet = command_value.quiet };
        self.advance();
        const placement_generation = self.next_generation;
        planned.generation = placement_generation;
        if (replacing) |index| {
            planned.identity = self.placements[index].identity;
            self.placements[index] = planned;
        } else {
            planned.identity = placement_generation;
            self.placements[self.placement_count] = planned;
            self.placement_count += 1;
        }
        return .{
            .changed = true,
            .response_id = retained.kitty_id,
            .response_number = retained.kitty_number,
            .cursor_advance = if (!command_value.unicode_placement and command_value.parent_id == 0 and command_value.compose_mode != 1) .{
                .cols = planned.cols,
                .rows = planned.rows,
            } else null,
            .quiet = command_value.quiet,
        };
    }

    fn delete(
        self: *Plane,
        command_value: Command,
        bank: Bank,
        screen_origin: u64,
        cursor_row: u64,
        cursor_col: u16,
        anchors: ?AnchorSource,
    ) Result {
        self.cancel();
        const selector = if (command_value.delete == 0) 'a' else command_value.delete;
        const remove_data = std.ascii.isUpper(selector);
        const normalized = std.ascii.toLower(selector);
        if (std.mem.indexOfScalar(u8, delete_selectors, normalized) == null)
            return .{ .quiet = 2 };
        if (normalized == 'f') return self.deleteFrame(command_value, remove_data);
        if (normalized == 'i' and command_value.id == 0) return .{ .quiet = 2 };
        if (normalized == 'n' and command_value.image_number == 0) return .{ .quiet = 2 };
        if (normalized == 'r' and command_value.x > command_value.y) return .{ .quiet = 2 };
        const numbered_image_id = if (normalized == 'n')
            if (self.kittyImageNumberIndex(command_value.image_number)) |index| self.images[index].id else null
        else
            null;

        // Uppercase deletion may reclaim only images whose matching
        // placements this command actually removed. An unplaced retained
        // image is not a match for a geometric or global placement selector.
        var matched_images: [max_images]bool = @splat(false);
        var changed = false;
        var placement_index: usize = 0;
        while (placement_index < self.placement_count) {
            const placement_value = self.placements[placement_index];
            if (placement_value.virtual and normalized != 'i' and normalized != 'n' and normalized != 'r') {
                placement_index += 1;
                continue;
            }
            if (normalized == 'n' and placement_value.image_id != numbered_image_id) {
                placement_index += 1;
                continue;
            }
            const kitty_id = self.kittyIdForImage(placement_value.image_id);
            const kitty_number = self.kittyNumberForImage(placement_value.image_id);
            if (kitty_id == null or placement_value.bank != bank) {
                placement_index += 1;
                continue;
            }
            // Identity and range deletion also apply to invisible virtual
            // prototypes and children whose Unicode parent has no current
            // text anchor. Geometry selectors require a resolved position.
            const anchor: Anchor = if (normalized == 'i' or normalized == 'n' or normalized == 'r')
                .{ .row = 0, .col = 0 }
            else blk: {
                const root = self.placementRoot(placement_index) orelse {
                    placement_index += 1;
                    continue;
                };
                if (root.virtual_index) |virtual_index| {
                    const source = anchors orelse {
                        placement_index += 1;
                        continue;
                    };
                    const base = source.resolve(source.context, virtual_index) orelse {
                        placement_index += 1;
                        continue;
                    };
                    break :blk .{ .row = base.row + root.offset.row, .col = base.col + root.offset.col };
                }
                break :blk root.offset;
            };
            if (!deleteMatches(
                placement_value,
                anchor,
                kitty_id,
                kitty_number,
                normalized,
                command_value,
                screen_origin,
                cursor_row,
                cursor_col,
            )) {
                placement_index += 1;
                continue;
            }
            if (self.imageIndex(placement_value.image_id)) |image_index|
                matched_images[image_index] = true;
            self.removePlacement(placement_index);
            changed = true;
        }

        var content_changed = false;
        if (remove_data) {
            var image_index: usize = 0;
            while (image_index < self.image_count) {
                const image_id = self.images[image_index].id;
                const kitty_id = self.images[image_index].kitty_id;
                // Kitty explicitly permits uppercase identity/range
                // deletion of already-unreferenced data without a
                // placement restriction. Other selectors require a match.
                const unplaced_identity = self.images[image_index].bank == bank and
                    command_value.placement_id == 0 and switch (normalized) {
                    'i' => kitty_id == command_value.id,
                    'n' => image_id == numbered_image_id,
                    'r' => if (kitty_id) |id| command_value.x <= id and id <= command_value.y else false,
                    else => false,
                };
                if ((!matched_images[image_index] and !unplaced_identity) or self.hasPlacement(image_id)) {
                    image_index += 1;
                    continue;
                }
                self.removeImage(image_index);
                // removeImage compacts storage by moving the last image
                // into this slot. Keep match identities aligned with it.
                matched_images[image_index] = matched_images[self.image_count];
                content_changed = true;
                changed = true;
            }
        }
        if (changed) {
            self.advance();
            if (content_changed) self.content_generation = self.next_generation;
        }
        // Kitty deletion commands deliberately produce no protocol response.
        return .{ .changed = changed, .quiet = 2 };
    }

    fn deleteFrame(self: *Plane, command_value: Command, remove_image: bool) Result {
        if ((command_value.id == 0) == (command_value.image_number == 0)) return .{ .quiet = 2 };
        const image_index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse return .{ .quiet = 2 };
        const image_id = self.images[image_index].id;
        const frame_count = self.frameCount(image_id);
        if (frame_count == 0) {
            if (!remove_image) return .{ .quiet = 2 };
            self.removePlacements(image_id);
            self.removeImage(image_index);
            self.advance();
            self.content_generation = self.next_generation;
            return .{ .changed = true, .quiet = 2 };
        }
        const requested = if (command_value.rows == 0)
            1
        else
            @min(std.math.cast(u16, command_value.rows) orelse return .{ .quiet = 2 }, frame_count + 1);
        const prior_current = self.images[image_index].current_frame;
        const visible_changed = prior_current + 1 == requested;
        if (requested == 1) {
            const promoted_index = self.frameIndex(image_id, 2).?;
            const promoted_gap = self.frames[promoted_index].gap_ms;
            self.storage_bytes -= self.images[image_index].pixels.len;
            self.allocator.free(self.images[image_index].pixels);
            self.images[image_index].pixels = self.frames[promoted_index].pixels;
            self.images[image_index].root_gap_ms = promoted_gap;
            self.removeFrameSlot(promoted_index, false);
        } else {
            const removed_index = self.frameIndex(image_id, requested).?;
            self.removeFrameSlot(removed_index, true);
        }
        for (self.frames[0..self.frame_count]) |*retained_frame| {
            if (retained_frame.image_id == image_id and retained_frame.number > requested) {
                retained_frame.number -= 1;
            }
        }
        const remaining = self.frameCount(image_id);
        if (prior_current + 1 == requested or prior_current > remaining) {
            self.images[image_index].current_frame = @min(prior_current, remaining);
        } else if (prior_current + 1 > requested) {
            self.images[image_index].current_frame -= 1;
        }
        if (visible_changed) {
            self.advance();
            self.content_generation = self.next_generation;
            self.images[image_index].generation = self.next_generation;
        }
        return .{ .changed = true, .visual_changed = visible_changed, .quiet = 2 };
    }

    // -------------------------------------------------------------------------
    // Decoded image and screen integration
    // -------------------------------------------------------------------------

    /// Removes every image and placement, preserving no protocol transfer.
    pub fn reset(self: *Plane) bool {
        self.cancel();
        const changed = self.image_count != 0 or self.placement_count != 0 or self.frame_count != 0;
        for (self.images[0..self.image_count]) |retained| {
            self.allocator.free(retained.pixels);
            if (retained.indexed_pixels) |source| self.allocator.free(source);
        }
        for (self.frames[0..self.frame_count]) |retained| self.allocator.free(retained.pixels);
        self.image_count = 0;
        self.placement_count = 0;
        self.frame_count = 0;
        self.storage_bytes = 0;
        if (changed) {
            self.advance();
            self.content_generation = self.next_generation;
        }
        return changed;
    }

    /// Transactionally retains one decoded RGBA image and ordinary placement.
    ///
    /// Ownership of `pixels` transfers only on success. Sixel and other
    /// terminal-owned decoders use a plane identity that cannot collide with a
    /// Kitty application-selected identity.
    pub fn admitDecoded(
        self: *Plane,
        pixels: []u8,
        width: u32,
        height: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
    ) error{Quota}!void {
        if (width == 0 or height == 0 or width > max_dimension or height > max_dimension or
            pixels.len > max_image_bytes or pixels.len > max_storage_bytes - self.storage_bytes or
            self.image_count == max_images or self.placement_count == max_placements)
            return error.Quota;
        const expected = std.math.mul(usize, width, height) catch return error.Quota;
        const expected_bytes = std.math.mul(usize, expected, 4) catch return error.Quota;
        if (expected_bytes != pixels.len)
            return error.Quota;
        const image_id = self.allocateImageId();
        self.advance();
        self.content_generation = self.next_generation;
        self.images[self.image_count] = .{
            .id = image_id,
            .bank = bank,
            .kitty_id = null,
            .kitty_number = null,
            .width = width,
            .height = height,
            .generation = self.next_generation,
            .pixels = pixels,
        };
        self.image_count += 1;
        self.storage_bytes += pixels.len;
        const added = self.addPlacement(
            image_id,
            0,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            width,
            height,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            self.next_generation,
        );
        std.debug.assert(added != null);
    }

    /// Removes all placements owned by one bank while retaining image data.
    pub fn clearBank(self: *Plane, bank: Bank) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            if (self.placements[index].bank != bank) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Retains only placement anchors representable by one resized screen bank.
    ///
    /// Primary callers pass the replacement screen's absolute retained-row
    /// interval (`history_row_base`, `history_count + rows`). Alternate callers
    /// pass row zero and the replacement visible-row count. Pixel geometry and
    /// placement generations remain unchanged for every retained anchor.
    pub fn retainBankBounds(
        self: *Plane,
        bank: Bank,
        row_start: u64,
        row_count: u64,
        columns: u16,
    ) bool {
        const row_end = std.math.add(u64, row_start, row_count) catch
            // zig-audit: acknowledge panic
            // reason: This path represents an internal invariant breach with no safe caller recovery; continuing would corrupt owned state.
            @panic("terminal graphics retained-row interval overflow");
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = self.placements[index];
            if (retained.bank != bank or retained.virtual) {
                index += 1;
                continue;
            }
            if (retained.parent_identity == 0 and (retained.row < row_start or retained.row >= row_end or
                retained.col >= columns))
            {
                self.removePlacement(index);
                changed = true;
                continue;
            }
            index += 1;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Drops primary placements whose complete anchor row was evicted.
    pub fn evictBefore(self: *Plane, absolute_row: u64) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = self.placements[index];
            if (retained.bank != .primary or retained.virtual or retained.parent_identity != 0 or retained.row >= absolute_row) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Removes placements intersecting one cell rectangle.
    pub fn erase(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        left: u16,
        right: u16,
    ) bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = self.placements[index];
            const retained_bottom = retained.row + retained.rows - 1;
            const retained_right = @as(u32, retained.col) + retained.cols - 1;
            if (retained.virtual or retained.parent_identity != 0 or retained.bank != bank or retained.row > bottom or retained_bottom < top or
                retained.col > right or retained_right < left)
            {
                index += 1;
                continue;
            }
            self.removePlacement(index);
            changed = true;
        }
        if (changed) self.advance();
        return changed;
    }

    /// Moves full-screen placements while maintaining existing scrollback
    /// lifetime. Partial-margin clipping is a separate admitted operation.
    pub fn scroll(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        count: u16,
        upward: bool,
    ) bool {
        return self.scrollColumnRows(bank, top, bottom, 0, std.math.maxInt(u32), count, upward, false);
    }

    /// Scrolls within vertical margins, trimming image content at the new
    /// top/bottom edge rather than retaining invisible out-of-region rows.
    pub fn scrollWithinMargins(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        count: u16,
        upward: bool,
    ) bool {
        return self.scrollColumnRows(bank, top, bottom, 0, std.math.maxInt(u32), count, upward, true);
    }

    /// Scrolls the accepted horizontal region with vertical-margin clipping.
    /// A placement straddling a horizontal boundary cannot move atomically;
    /// its decoded image bytes remain independently retained.
    pub fn scrollColumns(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        left: u32,
        right: u32,
        count: u16,
        upward: bool,
    ) bool {
        return self.scrollColumnRows(bank, top, bottom, left, right, count, upward, true);
    }

    fn scrollColumnRows(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        left: u32,
        right: u32,
        count: u16,
        upward: bool,
        clip_margins: bool,
    ) bool {
        if (count == 0 or top > bottom) return false;
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = &self.placements[index];
            if (retained.virtual or retained.parent_identity != 0 or retained.bank != bank or retained.row < top or retained.row > bottom) {
                index += 1;
                continue;
            }
            const placement_right: u32 = @as(u32, retained.col) + retained.cols - 1;
            if (retained.col > right or placement_right < left) {
                index += 1;
                continue;
            }
            if (retained.col < left or placement_right > right) {
                self.removePlacement(index);
                changed = true;
                continue;
            }
            // Pinned Kitty's margin filter moves only references wholly
            // inside the original region. A crossing placement is stationary.
            if (clip_margins and retained.rows - 1 > bottom - retained.row) {
                index += 1;
                continue;
            }
            if (upward) {
                const prior_offset = retained.row - top;
                if (prior_offset < count) {
                    const clipped = @as(u64, count) - prior_offset;
                    if (clipped >= retained.rows or !trimScrolledPlacement(retained, clipped, true)) {
                        self.removePlacement(index);
                        changed = true;
                        continue;
                    }
                    retained.row = top;
                } else {
                    retained.row -= count;
                }
            } else {
                if (count > bottom - retained.row) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.row += count;
                if (clip_margins) {
                    const available_rows = bottom - retained.row + 1;
                    if (available_rows < retained.rows and
                        !trimScrolledPlacement(retained, retained.rows - available_rows, false))
                    {
                        self.removePlacement(index);
                        changed = true;
                        continue;
                    }
                }
            }
            changed = true;
            index += 1;
        }
        if (changed) self.advance();
        return changed;
    }

    // Clip the destination pixel rectangle first, then project the same
    // fraction into its existing decoded image source rectangle. Leave image
    // allocations and their content generation alone. This remains bounded
    // even for scaled/cropped placements and large cell pixel sizes.
    fn trimScrolledPlacement(target: *Placement, clipped_rows: u64, from_top: bool) bool {
        std.debug.assert(clipped_rows > 0 and target.cell_height > 0);
        const requested_pixels = clipped_rows * target.cell_height;
        const trim_pixels = if (from_top)
            requested_pixels - target.cell_y
        else blk: {
            const available_rows = @as(u64, target.rows) - clipped_rows;
            const allowed_pixels = available_rows * target.cell_height - target.cell_y;
            break :blk @as(u64, target.pixel_height) -| allowed_pixels;
        };
        if (trim_pixels >= target.pixel_height) return false;
        if (trim_pixels == 0) return true;
        const old_height = target.pixel_height;
        const source_trim = @min(
            @as(u64, target.source_height - 1),
            @as(u64, target.source_height) * trim_pixels / old_height,
        );
        if (from_top) {
            target.source_y += @intCast(source_trim);
            target.cell_y = 0;
        }
        target.source_height -= @intCast(source_trim);
        target.pixel_height -= @intCast(trim_pixels);
        const revised_rows = (@as(u64, target.cell_y) + target.pixel_height + target.cell_height - 1) / target.cell_height;
        std.debug.assert(revised_rows >= 1 and revised_rows <= target.rows);
        target.rows = @intCast(revised_rows);
        return true;
    }

    /// Moves or clips placement anchors with one terminal column shift.
    pub fn shiftColumns(
        self: *Plane,
        bank: Bank,
        row: u64,
        left: u16,
        right: u16,
        count: u16,
        toward_left: bool,
    ) bool {
        return self.shiftColumnRows(bank, row, row, left, right, count, toward_left);
    }

    /// Applies one bounded column shift across a row range in a single
    /// placement scan; the decoded image allocations remain unchanged.
    pub fn shiftColumnRows(
        self: *Plane,
        bank: Bank,
        top: u64,
        bottom: u64,
        left: u16,
        right: u16,
        count: u16,
        toward_left: bool,
    ) bool {
        if (count == 0 or top > bottom or left > right) return false;
        var changed = false;
        var index: usize = 0;
        while (index < self.placement_count) {
            const retained = &self.placements[index];
            if (retained.virtual or retained.parent_identity != 0 or retained.bank != bank or retained.row < top or retained.row > bottom or
                retained.col > right)
            {
                index += 1;
                continue;
            }
            const placement_right = @as(u32, retained.col) + retained.cols - 1;
            if (placement_right < left) {
                index += 1;
                continue;
            }
            // A placement overlapping the boundary cannot be translated as
            // one anchor without changing pixels in unshifted columns.
            if (retained.col < left or placement_right > right) {
                self.removePlacement(index);
                changed = true;
                continue;
            }
            if (toward_left) {
                if (@as(u32, retained.col) < @as(u32, left) + count) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.col -= count;
            } else {
                if (placement_right + count > right) {
                    self.removePlacement(index);
                    changed = true;
                    continue;
                }
                retained.col += count;
            }
            changed = true;
            index += 1;
        }
        if (changed) self.advance();
        return changed;
    }

    // -------------------------------------------------------------------------
    // Borrowed observation and animation
    // -------------------------------------------------------------------------

    /// Borrows one retained image by dense index.
    pub fn image(self: *const Plane, index: usize) ?ImageView {
        if (index >= self.image_count) return null;
        const retained = self.images[index];
        const pixels = if (retained.current_frame == 0)
            retained.pixels
        else
            self.frameByNumber(retained.id, retained.current_frame + 1).?.pixels;
        return .{
            .id = retained.id,
            .width = retained.width,
            .height = retained.height,
            .generation = retained.generation,
            .pixels = pixels,
        };
    }

    /// Copies one retained placement by dense index.
    pub fn placement(self: *const Plane, index: usize) ?Placement {
        if (index >= self.placement_count) return null;
        return self.placements[index];
    }

    /// Returns the monotonic image-plane mutation identity.
    pub fn generation(self: *const Plane) u64 {
        return self.next_generation;
    }

    /// Returns the monotonic identity of retained decoded image content.
    pub fn imageGeneration(self: *const Plane) u64 {
        return self.content_generation;
    }

    /// Advances running Kitty animations against caller monotonic milliseconds.
    pub fn advanceAnimations(self: *Plane, now_ms: u64) AnimationTick {
        const virtual_visible: [max_images]bool = @splat(false);
        return self.advanceAnimationsWithVisibility(now_ms, &virtual_visible);
    }

    /// Advances animations while accepting caller-projected virtual visibility.
    ///
    /// `virtual_visible` is dense-image-indexed. Graphics still owns frame
    /// selection and ordinary placement visibility; Terminal supplies only the
    /// read-only U+10EEEE projection fact that the plane cannot derive from
    /// screen cells itself.
    pub fn advanceAnimationsWithVisibility(
        self: *Plane,
        now_ms: u64,
        virtual_visible: *const [max_images]bool,
    ) AnimationTick {
        var changed = false;
        var semantic_changed = false;
        var next_ms: ?u32 = null;
        var running = false;
        for (self.images[0..self.image_count]) |image_value| {
            if (image_value.animation != .stopped) {
                running = true;
                break;
            }
        }
        if (!running) return .{ .changed = false, .semantic_changed = false, .next_ms = null };
        const independent_visible = self.independentPhysicalVisibility();
        for (self.images[0..self.image_count], 0..) |*image_value, image_index| {
            const visible = independent_visible[image_index] or virtual_visible[image_index];
            if (image_value.animation == .stopped or self.frameCount(image_value.id) == 0 or
                !visible or self.animationDuration(image_value.*) == 0)
                continue;
            if (image_value.frame_started_ms == null) image_value.frame_started_ms = now_ms;
            const gap = self.currentGap(image_value.*);
            const elapsed = now_ms -| image_value.frame_started_ms.?;
            if (elapsed >= gap) {
                const initial_last = self.lastFrameNumber(image_value.id);
                const initial_number = image_value.current_frame + 1;
                if (initial_number == initial_last and image_value.animation == .loading) continue;
                if (initial_number == initial_last and image_value.loops_remaining == 1) {
                    image_value.animation = .stopped;
                    image_value.loops_remaining = 0;
                    semantic_changed = true;
                    continue;
                }
                var advanced = false;
                var steps: u16 = 0;
                while (steps <= self.frameCount(image_value.id)) : (steps += 1) {
                    const last = self.lastFrameNumber(image_value.id);
                    const current_number = image_value.current_frame + 1;
                    if (current_number < last) {
                        image_value.current_frame += 1;
                    } else if (image_value.animation == .loading) {
                        break;
                    } else if (image_value.loops_remaining == 1) {
                        image_value.animation = .stopped;
                        image_value.loops_remaining = 0;
                        break;
                    } else {
                        image_value.current_frame = 0;
                        if (image_value.loops_remaining > 1) image_value.loops_remaining -= 1;
                    }
                    advanced = true;
                    if (self.currentGap(image_value.*) != 0) break;
                }
                if (advanced) {
                    image_value.frame_started_ms = now_ms;
                    self.advance();
                    self.content_generation = self.next_generation;
                    image_value.generation = self.next_generation;
                    changed = true;
                    semantic_changed = true;
                }
            }
            if (image_value.animation != .stopped) {
                const remaining: u32 = @intCast(@min(
                    @as(u64, self.currentGap(image_value.*)) -|
                        (now_ms -| image_value.frame_started_ms.?),
                    std.math.maxInt(u32),
                ));
                next_ms = if (next_ms) |prior| @min(prior, @max(1, remaining)) else @max(1, remaining);
            }
        }
        return .{ .changed = changed, .semantic_changed = semantic_changed, .next_ms = next_ms };
    }

    fn animate(self: *Plane, command_value: Command) Result {
        if ((command_value.id == 0) == (command_value.image_number == 0))
            return .{ .failure = .invalid, .quiet = command_value.quiet };
        const index = (if (command_value.id != 0)
            self.kittyImageIndex(command_value.id)
        else
            self.kittyImageNumberIndex(command_value.image_number)) orelse
            return .{ .failure = .missing, .quiet = command_value.quiet };
        const image_value = &self.images[index];
        if (image_value.indexed_pixels != null)
            return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const selected_frame: ?u16 = if (command_value.columns == 0)
            null
        else
            std.math.cast(u16, command_value.columns) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        if (selected_frame) |number| {
            if (number == 0)
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
            if (number != 1 and self.frameByNumber(image_value.id, number) == null)
                return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet };
        }
        const gap_frame: ?u16 = if (command_value.rows == 0 or command_value.z == 0)
            null
        else
            std.math.cast(u16, command_value.rows) orelse
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet };
        const gap_index: ?usize = if (gap_frame) |number|
            if (number == 0)
                return .{ .response_id = image_value.kitty_id, .failure = .invalid, .quiet = command_value.quiet }
            else if (number == 1)
                null
            else
                self.frameIndex(image_value.id, number) orelse
                    return .{ .response_id = image_value.kitty_id, .failure = .missing, .quiet = command_value.quiet }
        else
            null;
        const requested_animation: ?AnimationState = if (command_value.width == 0)
            null
        else switch (command_value.width) {
            1 => .stopped,
            2 => .loading,
            3 => .running,
            else => return .{
                .response_id = image_value.kitty_id,
                .failure = .invalid,
                .quiet = command_value.quiet,
            },
        };
        var semantic_changed = false;
        var visible_changed = false;
        if (selected_frame) |number| {
            if (image_value.current_frame + 1 != number) {
                image_value.current_frame = number - 1;
                semantic_changed = true;
                visible_changed = true;
            }
        }
        if (gap_frame) |number| {
            const gap: u32 = if (command_value.z > 0) @intCast(command_value.z) else 0;
            if (number == 1) {
                if (image_value.root_gap_ms != gap) {
                    image_value.root_gap_ms = gap;
                    semantic_changed = true;
                }
            } else {
                if (self.frames[gap_index.?].gap_ms != gap) {
                    self.frames[gap_index.?].gap_ms = gap;
                    semantic_changed = true;
                }
            }
        }
        if (requested_animation) |animation| {
            if (image_value.animation != animation) {
                const was_stopped = image_value.animation == .stopped;
                image_value.animation = animation;
                if (animation == .stopped or was_stopped) image_value.loops_remaining = image_value.max_loops;
                semantic_changed = true;
            }
        }
        if (command_value.height != 0) {
            const loops = command_value.height - 1;
            if (image_value.max_loops != loops) {
                image_value.max_loops = loops;
                image_value.loops_remaining = loops;
                semantic_changed = true;
            }
        }
        if (semantic_changed) image_value.frame_started_ms = null;
        if (!semantic_changed) return .{
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
        if (visible_changed) {
            self.advance();
            self.content_generation = self.next_generation;
            image_value.generation = self.next_generation;
        }
        return .{
            .changed = semantic_changed,
            .visual_changed = visible_changed,
            .response_id = image_value.kitty_id,
            .response_number = image_value.kitty_number,
            .quiet = command_value.quiet,
        };
    }

    // -------------------------------------------------------------------------
    // Placement planning
    // -------------------------------------------------------------------------

    fn addPlacement(
        self: *Plane,
        image_id: u32,
        kitty_id: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        pixel_width: u32,
        pixel_height: u32,
        source_x: u32,
        source_y: u32,
        source_width: u32,
        source_height: u32,
        columns: u32,
        rows: u32,
        cell_x: u32,
        cell_y: u32,
        z: i32,
        placement_generation: u64,
    ) ?void {
        self.placements[self.placement_count] = makePlacement(
            image_id,
            kitty_id,
            bank,
            row,
            col,
            cell_width,
            cell_height,
            pixel_width,
            pixel_height,
            source_x,
            source_y,
            source_width,
            source_height,
            columns,
            rows,
            cell_x,
            cell_y,
            z,
            placement_generation,
        ) orelse return null;
        self.placements[self.placement_count].identity = placement_generation;
        self.placement_count += 1;
    }

    fn placementIndex(self: *const Plane, image_id: u32, kitty_id: u32) ?usize {
        if (kitty_id == 0) return null;
        for (self.placements[0..self.placement_count], 0..) |retained, index|
            if (retained.image_id == image_id and retained.kitty_id == kitty_id) return index;
        return null;
    }

    fn identityIndex(self: *const Plane, identity: u64) ?usize {
        if (identity == 0) return null;
        for (self.placements[0..self.placement_count], 0..) |retained, index|
            if (retained.identity == identity) return index;
        return null;
    }

    fn hasChildren(self: *const Plane, identity: u64) bool {
        if (identity == 0) return false;
        for (self.placements[0..self.placement_count]) |value|
            if (value.parent_identity == identity) return true;
        return false;
    }

    fn parentPlacementIndex(self: *const Plane, kitty_image_id: u32, kitty_placement_id: u32, bank: Bank) ?usize {
        const parent_image = self.kittyImageIndex(kitty_image_id) orelse return null;
        const parent_id = self.images[parent_image].id;
        var earliest: ?usize = null;
        for (self.placements[0..self.placement_count], 0..) |retained, index| {
            if (retained.image_id != parent_id or retained.bank != bank or
                (kitty_placement_id != 0 and retained.kitty_id != kitty_placement_id)) continue;
            if (earliest == null or retained.identity < self.placements[earliest.?].identity)
                earliest = index;
        }
        return earliest;
    }

    fn parentError(self: *const Plane, parent_identity: u64, replacing_identity: u64) ?Failure {
        var ancestor = parent_identity;
        var depth: u8 = 0;
        while (ancestor != 0) {
            if (ancestor == replacing_identity) return .cycle;
            if (depth == max_parent_depth) return .too_deep;
            const index = self.identityIndex(ancestor) orelse return .parent_missing;
            const value = self.placements[index];
            if (value.virtual and value.parent_identity != 0) return .invalid;
            ancestor = value.parent_identity;
            depth += 1;
        }
        return null;
    }

    /// Reparenting an existing placement must preserve the depth of its
    /// whole subtree, not only the new path above the modified root. This
    /// admission-only scan is bounded by the placement quota and 16 links.
    fn reparentExceedsDepth(self: *const Plane, replacing_index: usize, parent_index: usize) bool {
        var new_depth: usize = 1;
        var above = self.placements[parent_index].parent_slot;
        while (above) |index| {
            new_depth += 1;
            above = self.placements[index].parent_slot;
        }
        const moving_identity = self.placements[replacing_index].identity;
        for (self.placements[0..self.placement_count], 0..) |_, child_index| {
            var current = child_index;
            var distance: usize = 0;
            while (self.placements[current].parent_slot) |ancestor_index| {
                distance += 1;
                if (self.placements[ancestor_index].identity == moving_identity) {
                    if (new_depth + distance > max_parent_depth) return true;
                    break;
                }
                current = ancestor_index;
            }
        }
        return false;
    }

    /// Resolves a bounded parent chain without editing retained anchors.
    /// Virtual roots preserve only offsets: canonical text owns their anchor.
    pub const Anchor = struct { row: i128, col: i128 };
    /// Distinguishes an independent physical root from an unpositioned
    /// virtual prototype, carrying signed offsets in either case.
    pub const PlacementRoot = struct {
        offset: Anchor,
        virtual_index: ?u16 = null,
    };
    /// Finds a physical absolute anchor or a virtual root and its signed
    /// child offset, using only validated compaction-aware parent links.
    pub fn placementRoot(self: *const Plane, index: usize) ?PlacementRoot {
        if (index >= self.placement_count) return null;
        var value = self.placements[index];
        var current_index = index;
        var row: i128 = 0;
        var col: i128 = 0;
        var depth: u8 = 0;
        while (true) {
            row += value.parent_row_offset;
            col += value.parent_col_offset;
            if (value.parent_identity == 0) {
                if (value.virtual) return .{ .offset = .{ .row = row, .col = col }, .virtual_index = @intCast(current_index) };
                return .{ .offset = .{ .row = row + value.row, .col = col + value.col } };
            }
            if (depth == max_parent_depth) return null;
            const expected_parent = value.parent_identity;
            const parent_index = value.parent_slot orelse return null;
            if (parent_index >= self.placement_count) return null;
            value = self.placements[parent_index];
            current_index = parent_index;
            if (value.identity != expected_parent) return null;
            depth += 1;
        }
    }

    /// Resolves only rooted physical graphs. Virtual roots deliberately
    /// require Images' existing Unicode-placeholder read-only scanner.
    pub fn placementAnchor(self: *const Plane, index: usize) ?Anchor {
        const root = self.placementRoot(index) orelse return null;
        return if (root.virtual_index == null) root.offset else null;
    }

    fn makePlacement(
        image_id: u32,
        kitty_id: u32,
        bank: Bank,
        row: u64,
        col: u16,
        cell_width: u32,
        cell_height: u32,
        pixel_width: u32,
        pixel_height: u32,
        source_x: u32,
        source_y: u32,
        requested_width: u32,
        requested_height: u32,
        requested_cols: u32,
        requested_rows: u32,
        cell_x: u32,
        cell_y: u32,
        z: i32,
        placement_generation: u64,
    ) ?Placement {
        std.debug.assert(cell_width != 0 and cell_height != 0);
        if (source_x >= pixel_width or source_y >= pixel_height or
            cell_x >= cell_width or cell_y >= cell_height) return null;
        const source_width = if (requested_width == 0) pixel_width - source_x else requested_width;
        const source_height = if (requested_height == 0) pixel_height - source_y else requested_height;
        if (source_width == 0 or source_height == 0 or
            source_width > pixel_width - source_x or source_height > pixel_height - source_y) return null;
        var destination_width = source_width;
        var destination_height = source_height;
        if (requested_cols != 0) {
            destination_width = std.math.mul(u32, requested_cols, cell_width) catch return null;
            if (destination_width <= cell_x) return null;
            destination_width -= cell_x;
        }
        if (requested_rows != 0) {
            destination_height = std.math.mul(u32, requested_rows, cell_height) catch return null;
            if (destination_height <= cell_y) return null;
            destination_height -= cell_y;
        }
        if (requested_cols == 0 and requested_rows != 0)
            destination_width = ceilRatio(destination_height, source_width, source_height) orelse return null;
        if (requested_rows == 0 and requested_cols != 0)
            destination_height = ceilRatio(destination_width, source_height, source_width) orelse return null;
        const occupied_cols = ceilRatio(
            1,
            std.math.add(u32, destination_width, cell_x) catch return null,
            cell_width,
        ) orelse return null;
        const occupied_rows = ceilRatio(
            1,
            std.math.add(u32, destination_height, cell_y) catch return null,
            cell_height,
        ) orelse return null;
        return .{
            .image_id = image_id,
            .kitty_id = kitty_id,
            .generation = placement_generation,
            .bank = bank,
            .row = row,
            .col = col,
            .source_x = source_x,
            .source_y = source_y,
            .source_width = source_width,
            .source_height = source_height,
            .cell_x = cell_x,
            .cell_y = cell_y,
            .cell_height = cell_height,
            .pixel_width = destination_width,
            .pixel_height = destination_height,
            .z = z,
            .rows = @intCast(@min(occupied_rows, std.math.maxInt(u16))),
            .cols = @intCast(@min(occupied_cols, std.math.maxInt(u16))),
        };
    }

    // -------------------------------------------------------------------------
    // Retained storage, indexes, and identities
    // -------------------------------------------------------------------------

    /// Reclaims the oldest retained images needed for one successful Kitty
    /// image admission. Images without placements are always preferred, as
    /// required by the Kitty graphics storage-quota contract. A same-id
    /// replacement protects its existing internal image until the replacement
    /// bytes are ready to take ownership.
    fn reclaimForKittyAdmission(
        self: *Plane,
        incoming_bytes: usize,
        protected_image_id: ?u32,
    ) void {
        std.debug.assert(incoming_bytes <= max_indexed_retained_bytes);
        const replacement_bytes = if (protected_image_id) |image_id|
            if (self.imageIndex(image_id)) |index|
                self.images[index].pixels.len +
                    (if (self.images[index].indexed_pixels) |source| source.len else @as(usize, 0)) +
                    self.frameBytes(image_id)
            else
                0
        else
            0;
        const needs_slot = protected_image_id == null;

        while (self.storage_bytes - replacement_bytes > max_storage_bytes - incoming_bytes or
            (needs_slot and self.image_count == max_images))
        {
            const candidate = self.oldestEvictionCandidate(protected_image_id, true) orelse
                // zig-audit: acknowledge orelse_unreachable
                // reason: The owner invariant established before this lookup guarantees the value exists; absence would mean internal state corruption.
                self.oldestEvictionCandidate(protected_image_id, false) orelse unreachable;
            const image_id = self.images[candidate].id;
            self.removePlacements(image_id);
            self.removeImage(candidate);
        }
    }

    fn oldestEvictionCandidate(
        self: *const Plane,
        protected_image_id: ?u32,
        require_unplaced: bool,
    ) ?usize {
        var oldest: ?usize = null;
        for (self.images[0..self.image_count], 0..) |image_value, index| {
            if (protected_image_id != null and image_value.id == protected_image_id.?) continue;
            if (require_unplaced and self.hasPlacement(image_value.id)) continue;
            if (oldest == null or image_value.generation < self.images[oldest.?].generation)
                oldest = index;
        }
        return oldest;
    }

    fn removePlacements(self: *Plane, image_id: u32) void {
        var index: usize = 0;
        while (index < self.placement_count) {
            if (self.placements[index].image_id != image_id) {
                index += 1;
                continue;
            }
            self.removePlacement(index);
        }
    }

    fn removePlacement(self: *Plane, index: usize) void {
        std.debug.assert(index < self.placement_count);
        const removed = self.placements[index];
        if (!self.hasChildren(removed.identity)) {
            // Ordinary leaf deletion must not allocate or run a full graph
            // compaction. Only a moved parent's direct children need their
            // validated dense slot updated after the swap.
            self.placement_count -= 1;
            if (index != self.placement_count) {
                const moved = self.placements[self.placement_count];
                self.placements[index] = moved;
                if (self.hasChildren(moved.identity)) {
                    for (self.placements[0..self.placement_count]) |*placement_value| {
                        if (placement_value.parent_identity == moved.identity)
                            placement_value.parent_slot = @intCast(index);
                    }
                }
            }
            if (!self.hasPlacement(removed.image_id)) {
                for (self.images[0..self.image_count]) |*image_value| {
                    if (image_value.id == removed.image_id) {
                        image_value.frame_started_ms = null;
                        break;
                    }
                }
            }
            return;
        }
        // One bounded closure over parent links, not recursive per-child
        // scans. At most 16 ancestry rounds over the declared 16K placement
        // bound, regardless of a group's fan-out or dense slot ordering.
        var doomed: [max_placements]bool = @splat(false);
        doomed[index] = true;
        for (0..max_parent_depth) |_| {
            var extended = false;
            for (self.placements[0..self.placement_count], 0..) |placement_value, i| {
                if (doomed[i]) continue;
                if (placement_value.parent_slot) |parent_slot| {
                    std.debug.assert(parent_slot < self.placement_count);
                    if (doomed[parent_slot]) {
                        doomed[i] = true;
                        extended = true;
                    }
                }
            }
            if (!extended) break;
        }
        var map: [max_placements]u16 = undefined;
        var retained: usize = 0;
        for (self.placements[0..self.placement_count], 0..) |placement_value, prior| {
            if (doomed[prior]) continue;
            map[prior] = @intCast(retained);
            self.placements[retained] = placement_value;
            retained += 1;
        }
        self.placement_count = @intCast(retained);
        for (self.placements[0..retained]) |*placement_value| {
            if (placement_value.parent_slot) |parent_slot| {
                // The pre-commit link graph was cycle-free and bounded;
                // every surviving child must still own a surviving parent.
                std.debug.assert(!doomed[parent_slot]);
                placement_value.parent_slot = map[parent_slot];
            }
        }
        for (self.images[0..self.image_count]) |*image_value| {
            if (!self.hasPlacement(image_value.id)) image_value.frame_started_ms = null;
        }
    }

    fn removeImage(self: *Plane, index: usize) void {
        const removed = self.images[index];
        self.removeFrames(removed.id);
        self.storage_bytes -= removed.pixels.len;
        self.allocator.free(removed.pixels);
        if (removed.indexed_pixels) |source| {
            self.storage_bytes -= source.len;
            self.allocator.free(source);
        }
        self.image_count -= 1;
        if (index != self.image_count) self.images[index] = self.images[self.image_count];
    }

    fn removeFrames(self: *Plane, image_id: u32) void {
        var index: usize = 0;
        while (index < self.frame_count) {
            if (self.frames[index].image_id != image_id) {
                index += 1;
                continue;
            }
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
            self.frame_count -= 1;
            if (index != self.frame_count) self.frames[index] = self.frames[self.frame_count];
        }
    }

    fn removeFrameSlot(self: *Plane, index: usize, free_pixels: bool) void {
        if (free_pixels) {
            self.storage_bytes -= self.frames[index].pixels.len;
            self.allocator.free(self.frames[index].pixels);
        }
        self.frame_count -= 1;
        if (index != self.frame_count) self.frames[index] = self.frames[self.frame_count];
    }

    fn frameByNumber(self: *const Plane, image_id: u32, number: u16) ?*const Frame {
        for (self.frames[0..self.frame_count]) |*retained_frame|
            if (retained_frame.image_id == image_id and retained_frame.number == number) return retained_frame;
        return null;
    }

    fn framePixels(self: *const Plane, image_value: Image, number_value: u32) ?[]const u8 {
        const number = std.math.cast(u16, number_value) orelse return null;
        if (number == 1) return image_value.pixels;
        const retained = self.frameByNumber(image_value.id, number) orelse return null;
        return retained.pixels;
    }

    fn frameIndex(self: *const Plane, image_id: u32, number: u16) ?usize {
        for (self.frames[0..self.frame_count], 0..) |retained_frame, index|
            if (retained_frame.image_id == image_id and retained_frame.number == number) return index;
        return null;
    }

    fn frameCount(self: *const Plane, image_id: u32) u16 {
        var count: u16 = 0;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_id) count += 1;
        }
        return count;
    }

    fn frameBytes(self: *const Plane, image_id: u32) usize {
        var bytes: usize = 0;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_id) bytes += retained_frame.pixels.len;
        }
        return bytes;
    }

    fn animationDuration(self: *const Plane, image_value: Image) u64 {
        var duration: u64 = image_value.root_gap_ms;
        for (self.frames[0..self.frame_count]) |retained_frame| {
            if (retained_frame.image_id == image_value.id) duration += retained_frame.gap_ms;
        }
        return duration;
    }

    fn nextFrameNumber(self: *const Plane, image_id: u32) ?u16 {
        const count = self.frameCount(image_id);
        if (count == std.math.maxInt(u16) - 1) return null;
        return count + 2;
    }

    fn lastFrameNumber(self: *const Plane, image_id: u32) u16 {
        return self.frameCount(image_id) + 1;
    }

    fn currentGap(self: *const Plane, image_value: Image) u32 {
        if (image_value.current_frame == 0) return image_value.root_gap_ms;
        return self.frameByNumber(image_value.id, image_value.current_frame + 1).?.gap_ms;
    }

    fn hasPlacement(self: *const Plane, image_id: u32) bool {
        for (self.placements[0..self.placement_count]) |value|
            if (value.image_id == image_id) return true;
        return false;
    }

    /// One bounded scan produces physical visibility for all image identities.
    /// A child of a virtual prototype is not independently visible, even if
    /// its placement has a physical pixel resource.
    fn independentPhysicalVisibility(self: *const Plane) [max_images]bool {
        var visible: [max_images]bool = @splat(false);
        for (self.placements[0..self.placement_count], 0..) |value, index| {
            if (value.virtual) continue;
            const root = self.placementRoot(index) orelse continue;
            if (root.virtual_index != null) continue;
            for (self.images[0..self.image_count], 0..) |image_value, image_index| {
                if (image_value.id != value.image_id) continue;
                visible[image_index] = true;
                break;
            }
        }
        return visible;
    }

    /// Reports whether one running image needs caller-projected virtual visibility.
    pub fn needsVirtualAnimationVisibility(self: *const Plane, bank: Bank) bool {
        var running = false;
        for (self.images[0..self.image_count]) |image_value| {
            if (image_value.animation != .stopped) {
                running = true;
                break;
            }
        }
        if (!running) return false;
        const independent_visible = self.independentPhysicalVisibility();
        for (self.placements[0..self.placement_count], 0..) |placement_value, index| {
            if (placement_value.bank != bank) continue;
            const virtual_dependent = placement_value.virtual or blk: {
                const root = self.placementRoot(index) orelse break :blk false;
                break :blk root.virtual_index != null;
            };
            if (!virtual_dependent) continue;
            for (self.images[0..self.image_count], 0..) |image_value, image_index| {
                if (image_value.id != placement_value.image_id) continue;
                if (independent_visible[image_index]) break;
                if (image_value.animation != .stopped and self.frameCount(image_value.id) != 0 and
                    self.animationDuration(image_value) != 0)
                    return true;
                break;
            }
        }
        return false;
    }

    /// Copies one invisible Kitty Unicode-placeholder prototype and its image geometry.
    pub const VirtualPrototype = struct {
        image_id: u32,
        placement_identity: u64,
        image_width: u32,
        image_height: u32,
        image_generation: u64,
        placement_generation: u64,
        cols: u16,
        rows: u16,
    };

    /// Finds one invisible Kitty Unicode-placeholder prototype by client image/placement id.
    pub fn virtualPrototype(
        self: *const Plane,
        bank: Bank,
        kitty_image_id: u32,
        kitty_placement_id: u32,
    ) ?VirtualPrototype {
        const image_index = self.kittyImageIndex(kitty_image_id) orelse return null;
        const image_value = self.images[image_index];
        var oldest: ?Placement = null;
        for (self.placements[0..self.placement_count]) |placement_value| {
            if (!placement_value.virtual or placement_value.bank != bank or
                placement_value.image_id != image_value.id)
                continue;
            if (kitty_placement_id != 0 and placement_value.kitty_id != kitty_placement_id) continue;
            if (oldest == null or placement_value.identity < oldest.?.identity) oldest = placement_value;
        }
        const placement_value = oldest orelse return null;
        return .{
            .image_id = image_value.id,
            .placement_identity = placement_value.identity,
            .image_width = image_value.width,
            .image_height = image_value.height,
            .image_generation = image_value.generation,
            .placement_generation = placement_value.generation,
            .cols = placement_value.cols,
            .rows = placement_value.rows,
        };
    }

    /// Reports whether one screen bank retains any invisible Unicode-placeholder prototype.
    pub fn hasVirtualPlacement(self: *const Plane, bank: Bank) bool {
        for (self.placements[0..self.placement_count]) |placement_value|
            if (placement_value.virtual and placement_value.bank == bank) return true;
        return false;
    }

    fn kittyImageIndex(self: *const Plane, id: u32) ?usize {
        for (self.images[0..self.image_count], 0..) |retained, index|
            if (retained.kitty_id == id) return index;
        return null;
    }

    fn imageIndex(self: *const Plane, id: u32) ?usize {
        for (self.images[0..self.image_count], 0..) |retained, index|
            if (retained.id == id) return index;
        return null;
    }

    fn kittyImageNumberIndex(self: *const Plane, number: u32) ?usize {
        // Kitty resolves duplicate client numbers by the newest internal
        // image identity. Dense slot compaction does not preserve that order.
        var newest: ?usize = null;
        for (self.images[0..self.image_count], 0..) |retained, index| {
            if (retained.kitty_number != number) continue;
            if (newest == null or retained.id > self.images[newest.?].id)
                newest = index;
        }
        return newest;
    }

    fn kittyIdForImage(self: *const Plane, id: u32) ?u32 {
        for (self.images[0..self.image_count]) |retained|
            if (retained.id == id) return retained.kitty_id;
        return null;
    }

    fn kittyNumberForImage(self: *const Plane, id: u32) ?u32 {
        for (self.images[0..self.image_count]) |retained|
            if (retained.id == id) return retained.kitty_number;
        return null;
    }

    fn allocateKittyId(self: *const Plane) ?u32 {
        var candidate: u32 = 1;
        while (candidate != std.math.maxInt(u32)) : (candidate += 1)
            if (self.kittyImageIndex(candidate) == null) return candidate;
        return null;
    }

    fn allocateImageId(self: *Plane) u32 {
        if (self.next_image_id == std.math.maxInt(u32))
            // zig-audit: acknowledge panic
            // reason: This process-lifetime identity/revision space is deliberately non-wrapping; exhaustion is an unrecoverable invariant breach.
            @panic("terminal image identity exhausted");
        self.next_image_id += 1;
        return self.next_image_id;
    }

    fn advance(self: *Plane) void {
        if (self.next_generation == std.math.maxInt(u64))
            // zig-audit: acknowledge panic
            // reason: This process-lifetime identity/revision space is deliberately non-wrapping; exhaustion is an unrecoverable invariant breach.
            @panic("terminal image generation exhausted");
        self.next_generation += 1;
    }
};

// =============================================================================
// Kitty command grammar and pixel composition
// =============================================================================

fn parseCommand(bytes: []const u8) ?Command {
    const separator = std.mem.indexOfScalar(u8, bytes, ';');
    const metadata = if (separator) |index| bytes[0..index] else bytes;
    var result = Command{ .payload = if (separator) |index| bytes[index + 1 ..] else "" };
    var seen: u32 = 0;
    var fields = std.mem.splitScalar(u8, metadata, ',');
    while (fields.next()) |field| {
        if (field.len < 3 or field[1] != '=') return null;
        const key = field[0];
        const bit: u32 = switch (key) {
            'a' => 1 << 0,
            't' => 1 << 1,
            'f' => 1 << 2,
            'i' => 1 << 3,
            's' => 1 << 4,
            'v' => 1 << 5,
            'm' => 1 << 6,
            'q' => 1 << 7,
            'd' => 1 << 8,
            'x' => 1 << 9,
            'y' => 1 << 10,
            'p' => 1 << 11,
            'w' => 1 << 12,
            'h' => 1 << 13,
            'c' => 1 << 14,
            'r' => 1 << 15,
            'X' => 1 << 16,
            'Y' => 1 << 17,
            'z' => 1 << 18,
            'I' => 1 << 19,
            'C' => 1 << 20,
            'N' => 1 << 21,
            'o' => 1 << 22,
            'U' => 1 << 23,
            'S' => 1 << 24,
            'e' => 1 << 25,
            'P' => 1 << 26,
            'Q' => 1 << 27,
            'H' => 1 << 28,
            'V' => 1 << 29,
            else => return null,
        };
        if (seen & bit != 0) return null;
        seen |= bit;
        const value = field[2..];
        switch (key) {
            'a' => if (value.len == 1) {
                result.action = value[0];
            } else return null,
            't' => if (value.len == 1) {
                result.medium = value[0];
            } else return null,
            'f' => result.format = std.fmt.parseInt(u8, value, 10) catch return null,
            'i' => result.id = std.fmt.parseInt(u32, value, 10) catch return null,
            's' => result.width = std.fmt.parseInt(u32, value, 10) catch return null,
            'v' => result.height = std.fmt.parseInt(u32, value, 10) catch return null,
            'm' => {
                const more = std.fmt.parseInt(u8, value, 10) catch return null;
                if (more > 1) return null;
                result.more = more == 1;
            },
            'q' => {
                const quiet = std.fmt.parseInt(u8, value, 10) catch return null;
                if (quiet > 2) return null;
                result.quiet = @intCast(quiet);
            },
            'd' => if (value.len == 1) {
                result.delete = value[0];
            } else return null,
            'x' => result.x = std.fmt.parseInt(u32, value, 10) catch return null,
            'y' => result.y = std.fmt.parseInt(u32, value, 10) catch return null,
            'p' => result.placement_id = std.fmt.parseInt(u32, value, 10) catch return null,
            'w' => result.source_width = std.fmt.parseInt(u32, value, 10) catch return null,
            'h' => result.source_height = std.fmt.parseInt(u32, value, 10) catch return null,
            'c' => result.columns = std.fmt.parseInt(u32, value, 10) catch return null,
            'r' => result.rows = std.fmt.parseInt(u32, value, 10) catch return null,
            'X' => result.cell_x = std.fmt.parseInt(u32, value, 10) catch return null,
            'Y' => result.cell_y = std.fmt.parseInt(u32, value, 10) catch return null,
            'z' => result.z = std.fmt.parseInt(i32, value, 10) catch return null,
            'I' => result.image_number = std.fmt.parseInt(u32, value, 10) catch return null,
            'C' => {
                result.compose_mode = std.fmt.parseInt(u2, value, 10) catch return null;
                if (result.compose_mode > 1) return null;
            },
            'N' => result.usage_hints = std.fmt.parseInt(u32, value, 10) catch return null,
            'o' => if (value.len == 1) {
                result.compression = value[0];
            } else return null,
            'U' => {
                const placement = std.fmt.parseInt(u8, value, 10) catch return null;
                if (placement > 1) return null;
                result.unicode_placement = placement == 1;
            },
            'S' => result.uncompressed_bytes = std.fmt.parseInt(usize, value, 10) catch return null,
            'e' => if (value.len == 1 and std.ascii.isAlphabetic(value[0])) {
                result.feature_action = value[0];
            } else return null,
            'P' => result.parent_id = std.fmt.parseInt(u32, value, 10) catch return null,
            'Q' => result.parent_placement_id = std.fmt.parseInt(u32, value, 10) catch return null,
            'H' => result.parent_col_offset = std.fmt.parseInt(i32, value, 10) catch return null,
            'V' => result.parent_row_offset = std.fmt.parseInt(i32, value, 10) catch return null,
            else => return null,
        }
    }
    const parent_fields: u32 = (1 << 26) | (1 << 27) | (1 << 28) | (1 << 29);
    if (result.feature_action == 0 and seen & parent_fields != 0 and
        (result.action != 'p' or result.parent_id == 0)) return null;
    result.present = seen;
    return result;
}

// The feature-query encoder uses the same canonical command grammar as the
// Plane. Only this rare read-only path decodes twice, avoiding a retained full
// Command in every ordinary graphics Result. All output uses caller scratch.
const FeatureWriter = struct {
    bytes: []u8,
    used: usize = 0,

    fn text(self: *FeatureWriter, part: []const u8) error{ReplyLimit}!void {
        if (part.len > self.bytes.len - self.used) return error.ReplyLimit;
        @memcpy(self.bytes[self.used..][0..part.len], part);
        self.used += part.len;
    }

    fn number(self: *FeatureWriter, comptime key: u8, value: i64) error{ReplyLimit}!void {
        var local: [32]u8 = undefined;
        const part = std.fmt.bufPrint(&local, ",{c}={d}", .{ key, value }) catch return error.ReplyLimit;
        try self.text(part);
    }

    fn flag(self: *FeatureWriter, comptime key: u8, value: u8) error{ReplyLimit}!void {
        const part: [4]u8 = .{ ',', key, '=', value };
        try self.text(&part);
    }
};

/// Encodes only confirmed Kitty 0.50+ graphics feature-query keys into borrowed
/// scratch. Unsupported actions and values are deliberately not advertised.
/// The caller has already received Plane.command's read-only feature result;
/// this repeated decode does not admit image data or alter Plane state.
pub fn formatFeatureQuery(packet: []const u8, scratch: []u8) error{ReplyLimit}![]const u8 {
    const command_value = parseCommand(packet) orelse return error.ReplyLimit;
    if (command_value.action != 'q' or command_value.feature_action == 0) return error.ReplyLimit;
    // Direct callers also must never receive a success-looking capability
    // string for a selector that current Kitty rejects at parse admission.
    if (command_value.delete != 0 and
        std.mem.indexOfScalar(u8, delete_selectors, std.ascii.toLower(command_value.delete)) == null)
        return scratch[0..0];
    var out: FeatureWriter = .{ .bytes = scratch };
    const action = command_value.feature_action;
    const transmitting = action == 't' or action == 'T' or action == 'f';
    const placing = action == 'T' or action == 'p';
    const deleting = action == 'd';
    const animating = action == 'a';
    const composing = action == 'c';
    if (!transmitting and !placing and !deleting and !animating and !composing) return scratch[0..0];
    try out.flag('e', action);

    // Both supported action families reuse the actual encoded command values;
    // never report default/unrequested keys or transmit-only keys for e=p.
    const present = command_value.present;
    if (transmitting) {
        if (present & (1 << 1) != 0 and command_value.medium == 'd') try out.flag('t', 'd');
        if (present & (1 << 22) != 0 and command_value.compression == 'z') try out.flag('o', 'z');
        if (present & (1 << 2) != 0 and
            (command_value.format == 24 or command_value.format == 32 or
                (action != 'f' and (command_value.format == 8 or command_value.format == 16 or command_value.format == 100))))
            try out.number('f', command_value.format);
        if (present & (1 << 4) != 0 and command_value.width > 0 and command_value.width <= max_dimension)
            try out.number('s', command_value.width);
        if (present & (1 << 5) != 0 and command_value.height > 0 and command_value.height <= max_dimension)
            try out.number('v', command_value.height);
        // N=1 is a permitted advisory no-op; other N bits are not claimed.
        if (present & (1 << 21) != 0 and command_value.usage_hints == 1) try out.number('N', 1);
    }
    if (action == 'f') {
        // Existing frame admissions own only RGBA/RGB, the current image
        // dimensions, numbered frame bases/edits, overwrite X=1 and a full
        // 32-bit RGBA Y background. PNG and indexed input remain unsupported.
        if (present & (1 << 9) != 0 and command_value.x != 0 and command_value.x < max_dimension)
            try out.number('x', command_value.x);
        if (present & (1 << 10) != 0 and command_value.y != 0 and command_value.y < max_dimension)
            try out.number('y', command_value.y);
        if (present & (1 << 14) != 0 and command_value.columns != 0 and command_value.columns <= max_frames + 1)
            try out.number('c', command_value.columns);
        if (present & (1 << 15) != 0 and command_value.rows != 0 and command_value.rows <= max_frames + 1)
            try out.number('r', command_value.rows);
        if (present & (1 << 18) != 0 and command_value.z != 0) try out.number('z', command_value.z);
        if (present & (1 << 16) != 0 and command_value.cell_x == 1) try out.number('X', 1);
        if (present & (1 << 17) != 0 and command_value.cell_y != 0) try out.number('Y', command_value.cell_y);
    }
    if (placing) {
        // Kitty's source orders these independently of the query input. The
        // supported fields already map to Plane.put / makePlacement.
        if (present & (1 << 11) != 0 and command_value.placement_id != 0)
            try out.number('p', command_value.placement_id);
        if (present & (1 << 9) != 0 and command_value.x != 0 and command_value.x < max_dimension)
            try out.number('x', command_value.x);
        if (present & (1 << 10) != 0 and command_value.y != 0 and command_value.y < max_dimension)
            try out.number('y', command_value.y);
        if (present & (1 << 12) != 0 and command_value.source_width > 0 and command_value.source_width <= max_dimension)
            try out.number('w', command_value.source_width);
        if (present & (1 << 13) != 0 and command_value.source_height > 0 and command_value.source_height <= max_dimension)
            try out.number('h', command_value.source_height);
        if (present & (1 << 16) != 0 and command_value.cell_x > 0 and command_value.cell_x < max_dimension)
            try out.number('X', command_value.cell_x);
        if (present & (1 << 17) != 0 and command_value.cell_y > 0 and command_value.cell_y < max_dimension)
            try out.number('Y', command_value.cell_y);
        if (present & (1 << 14) != 0 and command_value.columns > 0 and command_value.columns <= std.math.maxInt(u16))
            try out.number('c', command_value.columns);
        if (present & (1 << 15) != 0 and command_value.rows > 0 and command_value.rows <= std.math.maxInt(u16))
            try out.number('r', command_value.rows);
        if (present & (1 << 20) != 0 and command_value.compose_mode == 1) try out.number('C', 1);
        if (present & (1 << 23) != 0 and command_value.unicode_placement) try out.number('U', 1);
        if (present & (1 << 18) != 0 and command_value.z != 0) try out.number('z', command_value.z);
        // Physical P/Q/H/V now works. Do not advertise complete relative
        // placement query parity until Unicode-placeholder parents have
        // their canonical text-derived anchor and lifetime implemented.
    }
    if (deleting and present & (1 << 8) != 0 and
        std.mem.indexOfScalar(u8, delete_selectors, std.ascii.toLower(command_value.delete)) != null)
    {
        const selector = command_value.delete;
        try out.flag('d', selector);
        const mode = std.ascii.toLower(selector);
        // Only image/number selectors consume the placement ID. Geometry
        // selectors and range deletions never claim that unrelated field.
        if (mode == 'i' or mode == 'n') {
            if (present & (1 << 11) != 0 and command_value.placement_id != 0)
                try out.number('p', command_value.placement_id);
        }
        // Coordinates are source-visible only for geometry, layer+point and
        // image-ID range selection. Preserve full u32 ranges without inventing
        // arbitrary pixel-dimension caps on image-ID identity ranges.
        if (std.mem.indexOfScalar(u8, "pqrxy", mode) != null) {
            if (mode != 'y' and present & (1 << 9) != 0 and command_value.x != 0)
                try out.number('x', command_value.x);
            if (mode != 'x' and present & (1 << 10) != 0 and command_value.y != 0)
                try out.number('y', command_value.y);
        }
        if ((mode == 'q' or mode == 'z') and present & (1 << 18) != 0 and command_value.z != 0)
            try out.number('z', command_value.z);
    }
    if (animating) {
        // a=s switches the owned three-state animation machine, a=v sets
        // loop count, and r/c/z select a frame, current frame and its gap.
        if (present & (1 << 4) != 0 and command_value.width >= 1 and command_value.width <= 3)
            try out.number('s', command_value.width);
        if (present & (1 << 5) != 0 and command_value.height != 0)
            try out.number('v', command_value.height);
        if (present & (1 << 15) != 0 and command_value.rows != 0 and command_value.rows <= max_frames + 1)
            try out.number('r', command_value.rows);
        if (present & (1 << 14) != 0 and command_value.columns != 0 and command_value.columns <= max_frames + 1)
            try out.number('c', command_value.columns);
        if (present & (1 << 18) != 0 and command_value.z != 0) try out.number('z', command_value.z);
    }
    if (composing) {
        // Composition C=1 is overwrite; unlike frame X=1, source X/Y are
        // pixel coordinates in composeFrames. Keep their meanings separate.
        if (present & (1 << 15) != 0 and command_value.rows != 0 and command_value.rows <= max_frames + 1)
            try out.number('r', command_value.rows);
        if (present & (1 << 14) != 0 and command_value.columns != 0 and command_value.columns <= max_frames + 1)
            try out.number('c', command_value.columns);
        if (present & (1 << 9) != 0 and command_value.x != 0 and command_value.x < max_dimension)
            try out.number('x', command_value.x);
        if (present & (1 << 10) != 0 and command_value.y != 0 and command_value.y < max_dimension)
            try out.number('y', command_value.y);
        if (present & (1 << 12) != 0 and command_value.source_width != 0 and command_value.source_width <= max_dimension)
            try out.number('w', command_value.source_width);
        if (present & (1 << 13) != 0 and command_value.source_height != 0 and command_value.source_height <= max_dimension)
            try out.number('h', command_value.source_height);
        if (present & (1 << 16) != 0 and command_value.cell_x != 0 and command_value.cell_x < max_dimension)
            try out.number('X', command_value.cell_x);
        if (present & (1 << 17) != 0 and command_value.cell_y != 0 and command_value.cell_y < max_dimension)
            try out.number('Y', command_value.cell_y);
        if (present & (1 << 20) != 0 and command_value.compose_mode == 1) try out.number('C', 1);
    }
    return scratch[0..out.used];
}

fn compressedInputCapacity(raw_bytes: usize) ?usize {
    const zlib_bound = std.math.add(usize, raw_bytes, raw_bytes >> 12) catch return null;
    const with_small_blocks = std.math.add(usize, zlib_bound, raw_bytes >> 14) catch return null;
    const with_large_blocks = std.math.add(usize, with_small_blocks, raw_bytes >> 25) catch return null;
    const framed = std.math.add(usize, with_large_blocks, 13 + 64 * 1024) catch return null;
    return @min(framed, max_compressed_bytes);
}

fn inflateLoading(self: *Plane) std.mem.Allocator.Error!bool {
    const loading = &self.loading.?;
    if (loading.compression != 'z' or loading.expected_bytes == 0 or loading.used == 0) return false;
    const raw = try self.allocator.alloc(u8, loading.expected_bytes);
    var adopted = false;
    defer if (!adopted) self.allocator.free(raw);
    const work = try self.allocator.alloc(u8, std.compress.flate.max_window_len);
    defer self.allocator.free(work);
    var output: std.Io.Writer = .fixed(raw);
    var input: std.Io.Reader = .fixed(loading.bytes[0..loading.used]);
    var decompressor: std.compress.flate.Decompress = .init(&input, .zlib, work);
    const decoded_count = decompressor.reader.streamRemaining(&output) catch return false;
    if (decoded_count != loading.expected_bytes or output.buffered().len != loading.expected_bytes or
        input.seek != input.end)
        return false;
    if (std.hash.Adler32.hash(raw) != decompressor.container_metadata.zlib.adler)
        return false;
    self.allocator.free(loading.bytes);
    loading.bytes = raw;
    loading.used = loading.expected_bytes;
    loading.compression = 0;
    adopted = true;
    return true;
}

fn ceilRatio(a: u32, b: u32, divisor: u32) ?u32 {
    if (divisor == 0) return null;
    const product = std.math.mul(u64, a, b) catch return null;
    return @intCast((product + divisor - 1) / divisor);
}

fn rectanglesOverlap(
    source_x: u32,
    source_y: u32,
    destination_x: u32,
    destination_y: u32,
    width: u32,
    height: u32,
) bool {
    return @max(source_x, destination_x) < @min(source_x, destination_x) + width and
        @max(source_y, destination_y) < @min(source_y, destination_y) + height;
}

fn fillRgba(canvas: []u8, rgba: u32) void {
    std.debug.assert(canvas.len % 4 == 0);
    const pixel = [4]u8{
        @truncate(rgba >> 24),
        @truncate(rgba >> 16),
        @truncate(rgba >> 8),
        @truncate(rgba),
    };
    var offset: usize = 0;
    while (offset < canvas.len) : (offset += 4) @memcpy(canvas[offset..][0..4], &pixel);
}

fn composeRgba(
    canvas: []u8,
    canvas_width: u32,
    source: []const u8,
    source_stride: u32,
    source_x: u32,
    source_y: u32,
    format: u8,
    width: u32,
    height: u32,
    offset_x: u32,
    offset_y: u32,
    blend: bool,
) void {
    const channels: usize = if (format == 24) 3 else 4;
    for (0..height) |y| {
        for (0..width) |x| {
            const source_offset = ((@as(usize, source_y) + y) * source_stride + source_x + x) * channels;
            const destination_offset = ((@as(usize, offset_y) + y) * canvas_width +
                offset_x + x) * 4;
            const alpha: u16 = if (format == 24) 255 else source[source_offset + 3];
            if (!blend or alpha == 255) {
                @memcpy(canvas[destination_offset..][0..3], source[source_offset..][0..3]);
                canvas[destination_offset + 3] = @intCast(alpha);
                continue;
            }
            if (alpha == 0) continue;
            const inverse: u32 = 255 - alpha;
            const destination_alpha: u32 = canvas[destination_offset + 3];
            const alpha_numerator: u32 = @as(u32, alpha) * 255 + destination_alpha * inverse;
            for (0..3) |channel| {
                const mixed = @as(u32, source[source_offset + channel]) * alpha * 255 +
                    @as(u32, canvas[destination_offset + channel]) * destination_alpha * inverse;
                canvas[destination_offset + channel] = @intCast(
                    (mixed + alpha_numerator / 2) / alpha_numerator,
                );
            }
            canvas[destination_offset + 3] = @intCast((alpha_numerator + 127) / 255);
        }
    }
}

fn deleteMatches(
    placement_value: Placement,
    anchor: Plane.Anchor,
    kitty_id: ?u32,
    kitty_number: ?u32,
    selector: u8,
    command_value: Command,
    screen_origin: u64,
    cursor_row: u64,
    cursor_col: u16,
) bool {
    const bottom = anchor.row + placement_value.rows - 1;
    const right = anchor.col + placement_value.cols - 1;
    const explicit_row = if (command_value.y == 0)
        null
    else
        std.math.add(u64, screen_origin, command_value.y - 1) catch null;
    return switch (selector) {
        'a' => true,
        'i' => kitty_id == command_value.id and
            (command_value.placement_id == 0 or placement_value.kitty_id == command_value.placement_id),
        'n' => kitty_number == command_value.image_number and
            (command_value.placement_id == 0 or placement_value.kitty_id == command_value.placement_id),
        'r' => if (kitty_id) |id| command_value.x <= id and id <= command_value.y else false,
        'p' => command_value.x != 0 and explicit_row != null and
            anchor.col <= @as(i128, command_value.x - 1) and command_value.x - 1 <= right and
            anchor.row <= explicit_row.? and explicit_row.? <= bottom,
        'q' => placement_value.z == command_value.z and command_value.x != 0 and explicit_row != null and
            anchor.col <= @as(i128, command_value.x - 1) and command_value.x - 1 <= right and
            anchor.row <= explicit_row.? and explicit_row.? <= bottom,
        'x' => command_value.x != 0 and
            anchor.col <= @as(i128, command_value.x - 1) and command_value.x - 1 <= right,
        'y' => explicit_row != null and
            anchor.row <= explicit_row.? and explicit_row.? <= bottom,
        'z' => placement_value.z == command_value.z,
        'c' => anchor.col <= cursor_col and cursor_col <= right and
            anchor.row <= cursor_row and cursor_row <= bottom,
        else => false,
    };
}

fn nonzero(value: u32) ?u32 {
    return if (value == 0) null else value;
}

// =============================================================================
// Image admission, placement, and deletion proofs
// =============================================================================

test "static plane admission is transactional across chunks replacement put and delete" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const first = try plane.command("a=T,f=32,s=1,v=1,i=7,m=1;/wA=", .primary, 0, 4, 2, 1, 1);
    try std.testing.expect(!first.changed);
    const completed = try plane.command("m=0;AP8=", .primary, 0, 4, 2, 1, 1);
    try std.testing.expect(completed.changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    const generation = plane.generation();
    const malformed = try plane.command("a=t,f=32,s=1,v=1,i=8;%%", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, malformed.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expect((try plane.command("a=p,i=7", .alternate, 0, 1, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=I,i=7", .primary, 0, 0, 0, 1, 1)).changed);
    // Uppercase I is scoped to the active bank's references. It must not
    // destroy decoded data still retained by a placement in another bank.
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect(plane.placement(0).?.bank == .alternate);
    try std.testing.expect((try plane.command("a=d,d=I,i=7", .alternate, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "invalid Kitty base64 length cancels transfer without losing response metadata or retained pixels" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    try std.testing.expect(!(try plane.command("a=T,f=32,s=1,v=1,i=7,m=1;/wA=", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("m=0;AP8=", .primary, 0, 0, 0, 1, 1)).changed);
    const before = plane.generation();

    const initial = try plane.command("a=t,f=32,s=1,v=1,i=91,q=0;A", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, initial.failure.?);
    try std.testing.expectEqual(@as(?u32, 91), initial.response_id);
    try std.testing.expectEqual(@as(u2, 0), initial.quiet);
    try std.testing.expect(plane.loading == null);

    const partial = try plane.command("a=t,f=32,s=1,v=1,i=92,q=2,m=1;/wA=", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(!partial.changed);
    try std.testing.expect(plane.loading != null);
    const continued = try plane.command("m=0;A", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, continued.failure.?);
    try std.testing.expectEqual(@as(?u32, 92), continued.response_id);
    try std.testing.expectEqual(@as(u2, 2), continued.quiet);
    try std.testing.expect(plane.loading == null);

    const bad_padding = try plane.command("a=t,f=32,s=1,v=1,i=94,q=1;A=", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, bad_padding.failure.?);
    try std.testing.expectEqual(@as(?u32, 94), bad_padding.response_id);
    try std.testing.expectEqual(@as(u2, 1), bad_padding.quiet);
    try std.testing.expect(plane.loading == null);

    try std.testing.expectEqual(before, plane.generation());
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);

    // A malformed transfer cannot poison the next valid transfer.
    const recovered = try plane.command("a=t,f=32,s=1,v=1,i=93,q=0;/wAA/w==", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(recovered.changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
}

test "Kitty anonymous transmit-display retains distinct id-zero images" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    // Yazi's KgpOld preview path intentionally omits both i= and I=. Kitty
    // defines that as protocol image id zero; C=1 keeps the terminal cursor
    // stationary while z=-1 places the preview behind text.
    const first = try plane.command(
        "q=2,a=T,z=-1,C=1,f=24,s=2,v=1,m=1;/wAA",
        .alternate,
        0,
        3,
        4,
        10,
        20,
    );
    try std.testing.expect(!first.changed);
    try std.testing.expect(first.cursor_advance == null);
    const completed = try plane.command("m=0;AP8A", .alternate, 0, 3, 4, 10, 20);
    try std.testing.expect(completed.changed);
    try std.testing.expect(completed.cursor_advance == null);
    try std.testing.expect(completed.response_id == null);
    try std.testing.expectEqual(@as(u2, 2), completed.quiet);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(?u32, 0), plane.images[0].kitty_id);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 0, 255, 0, 255, 0, 255 },
        plane.images[0].pixels,
    );
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(@as(i32, -1), plane.placements[0].z);

    // A second anonymous image is distinct. Protocol id zero is not a
    // replacement key; the Plane's private Image.id owns storage identity.
    const second = try plane.command(
        "q=2,a=T,z=-1,C=1,f=24,s=1,v=1;AQID",
        .alternate,
        0,
        8,
        5,
        10,
        20,
    );
    try std.testing.expect(second.changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expect(plane.images[0].id != plane.images[1].id);
    try std.testing.expectEqual(@as(?u32, 0), plane.images[1].kitty_id);

    // Yazi clears previews with uppercase A, which removes the visible
    // placements and their now-unreferenced Kitty-owned image data.
    const deleted = try plane.command("q=2,a=d,d=A", .alternate, 0, 0, 0, 10, 20);
    try std.testing.expect(deleted.changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
}

test "Kitty direct zlib transmission is exact bounded and shared by frames" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    try std.testing.expect(compressedInputCapacity(4).? >= 12);
    try std.testing.expect(compressedInputCapacity(max_image_bytes).? <= max_compressed_bytes);

    const one_shot = try plane.command(
        "a=t,f=32,s=1,v=1,i=81,o=z,q=2;eJz7z8DwHwAE/wH/",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(one_shot.changed);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);

    const first_chunk = try plane.command(
        "a=t,f=32,s=2,v=2,i=81,o=z,m=1,q=2;eJxjYGRiZmFlY+fg",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(!first_chunk.changed);
    const second_chunk = try plane.command(
        "m=0,q=2;5OLm4eXjBwACuAB5",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(second_chunk.changed);
    try std.testing.expectEqual(@as(u32, 2), plane.image(0).?.width);
    try std.testing.expectEqual(@as(u32, 2), plane.image(0).?.height);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
        plane.image(0).?.pixels,
    );

    try std.testing.expect((try plane.command(
        "a=t,f=24,s=2,v=1,i=82,o=z,q=2;eJxjZGJmYWUDAAA+ABY=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 255, 4, 5, 6, 255 },
        plane.image(1).?.pixels,
    );

    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=83,q=2;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const compressed_frame = try plane.command(
        "a=f,f=32,s=1,v=1,i=83,r=2,o=z,C=1,q=2;eJxjYPj/HwADAQH/",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(compressed_frame.changed);
    try std.testing.expectEqual(@as(?u32, 2), compressed_frame.response_frame);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 255, 255 },
        plane.frameByNumber(plane.image(2).?.id, 2).?.pixels,
    );

    const generation = plane.generation();
    const image_count = plane.image_count;
    const trailing = try plane.command(
        "a=t,f=32,s=1,v=1,i=84,o=z,q=2;eJz7z8DwHwAE/wH/AA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, trailing.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(image_count, plane.image_count);

    const truncated = try plane.command(
        "a=t,f=32,s=1,v=1,i=84,o=z,q=2;eJz7z8DwHwAE/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, truncated.failure.?);
    try std.testing.expectEqual(generation, plane.generation());

    const oversized = try plane.command(
        "a=t,f=32,s=1,v=1,i=84,o=z,q=2;eJxLTEpOSQUABcgB8A==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, oversized.failure.?);
    try std.testing.expectEqual(generation, plane.generation());

    const unknown = try plane.command(
        "a=t,f=32,s=1,v=1,i=84,o=x,q=2;eJz7z8DwHwAE/wH/",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.unsupported, unknown.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
}

test "RGB conversion quota cancellation and bank cleanup preserve exact ownership" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=24,s=1,v=1,i=1;AQID",
        .alternate,
        0,
        2,
        4,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, plane.image(0).?.pixels);
    try std.testing.expect(plane.clearBank(.alternate));
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    const before = plane.generation();
    const rejected = try plane.command("a=t,f=32,s=4096,v=4096,i=2;", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.quota, rejected.failure.?);
    try std.testing.expectEqual(before, plane.generation());
}

test "Kitty quota admission evicts oldest unplaced image before visible data" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        1,
        1,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);

    // Synthesize storage pressure without allocating a 64 MiB test fixture.
    plane.storage_bytes = max_storage_bytes;
    const admitted = try plane.command(
        "a=t,f=32,s=1,v=1,i=3;CQoLDA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(admitted.changed);
    try std.testing.expect(plane.kittyImageIndex(1) != null);
    try std.testing.expect(plane.kittyImageIndex(2) == null);
    try std.testing.expect(plane.kittyImageIndex(3) != null);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(max_storage_bytes, plane.storage_bytes);
}

test "Kitty quota admission reclaims oldest placed image as fallback" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        1,
        1,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);

    plane.storage_bytes = max_storage_bytes;
    const admitted = try plane.command(
        "a=t,f=32,s=1,v=1,i=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(admitted.changed);
    try std.testing.expect(plane.kittyImageIndex(1) == null);
    try std.testing.expect(plane.kittyImageIndex(2) != null);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(max_storage_bytes, plane.storage_bytes);
}

test "new transmission cancels an incomplete stream without retained mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const incomplete = try plane.command(
        "a=t,f=32,s=1,v=1,i=2,m=1;AQ==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(!incomplete.changed);
    try std.testing.expectEqual(@as(u64, 0), plane.generation());
    const replacement = try plane.command(
        "a=t,f=32,s=1,v=1,i=3;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(replacement.changed);
    try std.testing.expectEqual(@as(u32, 1), plane.image(0).?.id);
}

test "Kitty virtual placements stay invisible and use image selectors for lifetime" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();

    const virtual = try plane.command(
        "a=T,f=32,s=2,v=1,i=42,p=22,c=2,r=1,U=1,q=2;AQAA/wIAAP8=",
        .primary,
        10,
        12,
        3,
        10,
        20,
    );
    try std.testing.expect(virtual.changed);
    try std.testing.expect(virtual.cursor_advance == null);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect(plane.placement(0).?.virtual);
    const prototype = plane.virtualPrototype(.primary, 42, 22) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 1), prototype.image_id);
    try std.testing.expectEqual(@as(u16, 2), prototype.cols);
    try std.testing.expectEqual(@as(u16, 1), prototype.rows);
    try std.testing.expect(plane.virtualPrototype(.primary, 42, 0) != null);
    try std.testing.expect(plane.virtualPrototype(.primary, 42, 23) == null);
    try std.testing.expect(plane.hasVirtualPlacement(.primary));

    const generation = plane.generation();
    try std.testing.expect(!plane.scroll(.primary, 10, 20, 1, true));
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expect(!plane.erase(.primary, 10, 20, 0, 20));
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expect(!(try plane.command("a=d,d=a", .primary, 10, 12, 3, 10, 20)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);

    try std.testing.expect((try plane.command("a=d,d=i,i=42,p=22", .primary, 10, 0, 0, 10, 20)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
}

test "static delete selectors preserve placement and image ownership distinctions" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        10,
        11,
        2,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=1", .primary, 10, 13, 4, 1, 1)).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=2;BQYHCA==",
        .primary,
        10,
        12,
        5,
        1,
        1,
    )).changed);

    try std.testing.expect((try plane.command("a=d,d=p,x=3,y=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=C", .primary, 10, 13, 4, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u32, 2), plane.image(0).?.id);

    try std.testing.expect((try plane.command("a=d,d=i,i=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expect((try plane.command("a=p,i=2", .primary, 10, 12, 5, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=I,i=2", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=3;AQIDBA==",
        .primary,
        10,
        12,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=4;AQIDBA==",
        .primary,
        10,
        13,
        1,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=d,d=x,x=1", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=y,y=4", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=R,x=3,y=4", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=5;AQIDBA==",
        .primary,
        10,
        10,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=6;AQIDBA==",
        .primary,
        10,
        11,
        1,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=d", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    // Pinned Kitty A only frees images whose placements this same command
    // matched. Once lowercase a already removed the refs, uppercase A
    // cannot sweep the independently retained image bytes.
    try std.testing.expect(!(try plane.command("a=d,d=A", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expect((try plane.command("a=d,d=I,i=5", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=I,i=6", .primary, 10, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
}

test "plane identities survive Kitty replacement and isolate decoded images from Kitty deletion" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=99;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const kitty_identity = plane.image(0).?.id;
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=99;BAIDAg==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(kitty_identity, plane.image(0).?.id);

    const decoded = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 });
    try plane.admitDecoded(decoded, 1, 1, .primary, 1, 1, 1, 1);
    const decoded_identity = plane.image(1).?.id;
    try std.testing.expect(decoded_identity != kitty_identity);
    try std.testing.expect((try plane.command("a=d,d=A", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
    try std.testing.expectEqual(decoded_identity, plane.image(0).?.id);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);

    const rejected = try std.testing.allocator.dupe(u8, &.{ 5, 6, 7, 8 });
    defer std.testing.allocator.free(rejected);
    const before = .{
        plane.image_count,
        plane.placement_count,
        plane.storage_bytes,
        plane.generation(),
        plane.imageGeneration(),
    };
    try std.testing.expectError(
        error.Quota,
        plane.admitDecoded(rejected, max_dimension + 1, 1, .primary, 0, 0, 1, 1),
    );
    try std.testing.expectEqualDeep(before, .{
        plane.image_count,
        plane.placement_count,
        plane.storage_bytes,
        plane.generation(),
        plane.imageGeneration(),
    });
}

test "Kitty placement identity replaces and deletes only the exact retained placement" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=9;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=9,p=4", .primary, 0, 2, 3, 1, 1)).changed);
    const first_generation = plane.placement(0).?.generation;
    try std.testing.expect((try plane.command("a=p,i=9,p=4", .primary, 0, 5, 6, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);
    try std.testing.expectEqual(@as(u64, 5), plane.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 6), plane.placement(0).?.col);
    try std.testing.expect(plane.placement(0).?.generation > first_generation);

    try std.testing.expect(!(try plane.command("a=d,d=i,i=9,p=3", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=i,i=9,p=4", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 0), plane.placement_count);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
}

test "Kitty uppercase identity deletion honors placement id before reclaiming image data" {
    inline for (.{ "i=9", "I=44" }) |identity| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        const transmit = if (comptime std.mem.eql(u8, identity, "i=9"))
            "a=t,f=32,s=1,v=1,i=9;AQIDBA=="
        else
            "a=t,f=32,s=1,v=1,I=44;AQIDBA==";
        try std.testing.expect((try plane.command(transmit, .primary, 0, 0, 0, 1, 1)).changed);
        const put = if (comptime std.mem.eql(u8, identity, "i=9"))
            "a=p,i=9"
        else
            "a=p,I=44";
        const delete = if (comptime std.mem.eql(u8, identity, "i=9"))
            "a=d,d=I,i=9"
        else
            "a=d,d=N,I=44";
        try std.testing.expect((try plane.command(put ++ ",p=4", .primary, 0, 1, 2, 1, 1)).changed);
        try std.testing.expect((try plane.command(put ++ ",p=5", .primary, 0, 2, 3, 1, 1)).changed);
        const image_id = plane.image(0).?.id;
        const stored = plane.storage_bytes;
        const generation = plane.generation();
        try std.testing.expect(!(try plane.command(delete ++ ",p=3", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expectEqual(generation, plane.generation());
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
        try std.testing.expectEqual(stored, plane.storage_bytes);
        try std.testing.expect((try plane.command(delete ++ ",p=4", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        try std.testing.expectEqual(image_id, plane.placement(0).?.image_id);
        try std.testing.expectEqual(@as(u32, 5), plane.placement(0).?.kitty_id);
        try std.testing.expect((try plane.command(delete ++ ",p=5", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expectEqual(@as(u16, 0), plane.image_count);
        try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
        try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
    }
}

test "Kitty uppercase all deletion preserves unrelated initially unplaced images" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=5;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=6;BQYHCA==", .primary, 0, 1, 1, 1, 1)).changed);
    const unplaced_id = plane.image(0).?.id;
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=A", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(unplaced_id, plane.image(0).?.id);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    // An uppercase all command with no matched placements cannot evict
    // retained data never referenced by the affected active bank.
    const generation = plane.generation();
    try std.testing.expect(!(try plane.command("a=d,d=A", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
}

test "Kitty uppercase range deletion cannot reclaim unplaced data from another bank" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=7;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    const primary_id = plane.image(0).?.id;
    const primary_bytes = plane.storage_bytes;
    const initial_generation = plane.generation();
    const other_bank = try plane.command("a=d,d=R,x=7,y=7", .alternate, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(@as(u2, 2), other_bank.quiet);
    try std.testing.expect(!other_bank.changed);
    try std.testing.expectEqual(initial_generation, plane.generation());
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(primary_id, plane.image(0).?.id);
    try std.testing.expectEqual(primary_bytes, plane.storage_bytes);

    // The matching upper-case range in the owning primary bank reclaims it.
    try std.testing.expect((try plane.command("a=d,d=R,x=7,y=7", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);

    // An explicit placement filter suppresses the unplaced-data shortcut.
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=9;AQIDBA==", .alternate, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect(!(try plane.command("a=d,d=R,x=9,y=9,p=3", .alternate, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expect((try plane.command("a=d,d=R,x=9,y=9", .alternate, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    // A placement in another bank is not eligible for this range filter,
    // and must continue to own its decoded bytes.
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=12;AQIDBA==", .primary, 0, 1, 2, 1, 1)).changed);
    const still_placed = plane.image(0).?.id;
    const before_placed = plane.generation();
    try std.testing.expect(!(try plane.command("a=d,d=R,x=12,y=12", .alternate, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(before_placed, plane.generation());
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(still_placed, plane.placement(0).?.image_id);
    try std.testing.expect((try plane.command("a=d,d=R,x=12,y=12", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "Kitty unplaced uppercase ID and number deletions respect admitting screen bank" {
    inline for (.{
        .{
            .transmit = "a=t,f=32,s=1,v=1,i=17;AQIDBA==",
            .delete = "a=d,d=I,i=17",
        },
        .{
            .transmit = "a=t,f=32,s=1,v=1,I=44;AQIDBA==",
            .delete = "a=d,d=N,I=44",
        },
    }) |case| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        try std.testing.expect((try plane.command(case.transmit, .alternate, 0, 0, 0, 1, 1)).changed);
        const original_id = plane.image(0).?.id;
        const before_generation = plane.generation();
        const before_bytes = plane.storage_bytes;
        const wrong_bank = try plane.command(case.delete, .primary, 0, 0, 0, 1, 1);
        try std.testing.expect(!wrong_bank.changed);
        try std.testing.expectEqual(@as(u2, 2), wrong_bank.quiet);
        try std.testing.expectEqual(before_generation, plane.generation());
        try std.testing.expectEqual(before_bytes, plane.storage_bytes);
        try std.testing.expectEqual(original_id, plane.image(0).?.id);
        try std.testing.expect((try plane.command(case.delete, .alternate, 0, 0, 0, 1, 1)).changed);
        try std.testing.expectEqual(@as(u16, 0), plane.image_count);
        try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
    }
}

test "Kitty margin scroll clips image geometry before row deletion" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=2,i=70,C=1,q=2;AQIDBAUGBwg=",
        .primary,
        0,
        1,
        2,
        1,
        1,
    )).changed);
    const before = plane.placement(0).?;
    try std.testing.expectEqual(@as(u16, 2), before.rows);
    try std.testing.expectEqual(@as(u32, 2), before.pixel_height);
    const content_before = plane.content_generation;
    try std.testing.expect(plane.scrollColumns(.primary, 1, 2, 0, 7, 1, false));
    const clipped = plane.placement(0).?;
    try std.testing.expectEqual(@as(u64, 2), clipped.row);
    try std.testing.expectEqual(@as(u16, 1), clipped.rows);
    try std.testing.expectEqual(@as(u32, 1), clipped.pixel_height);
    try std.testing.expectEqual(@as(u32, 1), clipped.source_height);
    try std.testing.expectEqual(content_before, plane.content_generation);
    // A clipped-off row is not still eligible for geometric deletion.
    try std.testing.expect(!(try plane.command(
        "a=d,d=y,y=4",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=d,d=y,y=3",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
}

test "Kitty margin scroll up clips image top and preserves decoded data" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=2,i=73,C=1,q=2;AQIDBAUGBwg=",
        .primary,
        0,
        1,
        0,
        1,
        1,
    )).changed);
    const image_id = plane.image(0).?.id;
    const before_content = plane.content_generation;
    const before_storage = plane.storage_bytes;
    try std.testing.expect(plane.scrollColumns(.primary, 1, 2, 0, 7, 1, true));
    const clipped = plane.placement(0).?;
    try std.testing.expectEqual(@as(u64, 1), clipped.row);
    try std.testing.expectEqual(@as(u16, 1), clipped.rows);
    try std.testing.expectEqual(@as(u32, 1), clipped.source_y);
    try std.testing.expectEqual(@as(u32, 1), clipped.source_height);
    try std.testing.expectEqual(@as(u32, 1), clipped.pixel_height);
    try std.testing.expectEqual(before_content, plane.content_generation);
    try std.testing.expectEqual(before_storage, plane.storage_bytes);
    try std.testing.expectEqual(image_id, plane.image(0).?.id);
    try std.testing.expect(!(try plane.command("a=d,d=p,x=1,y=1", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=p,x=1,y=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 0), plane.placement_count);
    try std.testing.expectEqual(before_storage, plane.storage_bytes);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
}

test "Kitty margin scroll leaves initially boundary-crossing placements stationary" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=2,i=74,C=1,q=2;AQIDBAUGBwg=",
        .primary,
        0,
        2,
        0,
        1,
        1,
    )).changed);
    const before = plane.placement(0).?;
    const generation = plane.generation();
    // Pinned Kitty moves only fully contained references inside margins.
    try std.testing.expect(!plane.scrollColumns(.primary, 1, 2, 0, 7, 1, true));
    try std.testing.expectEqualDeep(before, plane.placement(0).?);
    try std.testing.expectEqual(generation, plane.generation());
    // Full-screen scrolling retains its separate historic behavior.
    try std.testing.expect(plane.scroll(.primary, 1, 2, 1, true));
    try std.testing.expectEqual(@as(u64, 1), plane.placement(0).?.row);
}

test "Kitty margin scroll scales clipping without changing image allocation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    // Four source pixels displayed across four destination pixels, one
    // physical cell consumes two pixels. Remove a full lower cell.
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=4,i=75,r=2,C=1,q=2;AQIDBAUGBwgJCgsMDQ4PEA==",
        .primary,
        0,
        1,
        0,
        1,
        2,
    )).changed);
    const before = plane.placement(0).?;
    try std.testing.expectEqual(@as(u16, 2), before.rows);
    try std.testing.expectEqual(@as(u32, 4), before.pixel_height);
    const storage_before = plane.storage_bytes;
    try std.testing.expect(plane.scrollColumns(.primary, 1, 2, 0, 7, 1, false));
    const after = plane.placement(0).?;
    try std.testing.expectEqual(@as(u64, 2), after.row);
    try std.testing.expectEqual(@as(u16, 1), after.rows);
    try std.testing.expectEqual(@as(u32, 2), after.pixel_height);
    try std.testing.expectEqual(@as(u32, 2), after.source_height);
    try std.testing.expectEqual(storage_before, plane.storage_bytes);
    try std.testing.expectEqual(@as(u32, 4), plane.image(0).?.height);
}

test "Kitty six geometric deletions exclude virtual placement prototypes" {
    // Pinned Kitty graphics.c x/y/z/point/point3d/cursor filters exclude
    // virtual references; image id and placement id are separate selectors.
    const requests = [_][]const u8{
        "a=d,d=P,x=1,y=1",
        "a=d,d=Q,x=1,y=1,z=0",
        "a=d,d=X,x=1",
        "a=d,d=Y,y=1",
        "a=d,d=Z,z=0",
        "a=d,d=C",
    };
    for (requests) |request| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        try std.testing.expect((try plane.command(
            "a=T,f=32,s=2,v=1,i=42,p=22,c=2,r=1,U=1,q=2;AQAA/wIAAP8=",
            .primary,
            10,
            12,
            3,
            10,
            20,
        )).changed);
        const original = plane.placement(0).?;
        const before_generation = plane.generation();
        const before_image_generation = plane.content_generation;
        const before_bytes = plane.storage_bytes;
        const skipped = try plane.command(request, .primary, 10, 10, 0, 10, 20);
        try std.testing.expect(!skipped.changed);
        try std.testing.expectEqual(@as(u2, 2), skipped.quiet);
        try std.testing.expectEqual(before_generation, plane.generation());
        try std.testing.expectEqual(before_image_generation, plane.content_generation);
        try std.testing.expectEqual(before_bytes, plane.storage_bytes);
        try std.testing.expectEqualDeep(original, plane.placement(0).?);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        // Exact image-plus-placement selectors may retire the virtual ref.
        try std.testing.expect((try plane.command(
            "a=d,d=i,i=42,p=22",
            .primary,
            10,
            0,
            0,
            10,
            20,
        )).changed);
        try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    }
}

test "Kitty geometric upper Q retires animation frames only after final matched placement" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=71,p=1,z=-3,q=2,C=1;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=71,r=99,c=1,z=50,q=2;AAD/gA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=p,i=71,p=2,z=-3,q=2,C=1",
        .primary,
        0,
        0,
        1,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
    const generation = plane.content_generation;
    const bytes = plane.storage_bytes;
    const first = try plane.command("a=d,d=Q,x=1,y=1,z=-3", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(first.changed);
    try std.testing.expectEqual(@as(u2, 2), first.quiet);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
    try std.testing.expectEqual(bytes, plane.storage_bytes);
    try std.testing.expectEqual(generation, plane.content_generation);
    try std.testing.expectEqual(@as(u32, 2), plane.placement(0).?.kitty_id);
    const miss = try plane.command("a=d,d=Q,x=1,y=1,z=-3", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(!miss.changed);
    try std.testing.expectEqual(generation, plane.content_generation);
    const last = try plane.command("a=d,d=Q,x=2,y=1,z=-3", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(last.changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
    try std.testing.expect(plane.content_generation > generation);
}

test "Kitty virtual child cannot itself be relative to another placement" {
    // A virtual prototype gets its anchor from U+10EEEE text, and may have
    // physical descendants. The virtual prototype itself cannot be a child.
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=91,p=3,U=1,C=1,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=92,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const parent = plane.placement(0).?;
    const prior_generation = plane.generation();
    const prior_content_generation = plane.content_generation;
    const prior_storage = plane.storage_bytes;
    const relative_put = try plane.command(
        "a=p,i=92,p=4,P=91,Q=3,U=1,q=2",
        .primary,
        0,
        1,
        1,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, relative_put.failure.?);
    try std.testing.expect(!relative_put.changed);
    try std.testing.expectEqual(prior_generation, plane.generation());
    try std.testing.expectEqual(prior_content_generation, plane.content_generation);
    try std.testing.expectEqual(prior_storage, plane.storage_bytes);
    try std.testing.expectEqualDeep(parent, plane.placement(0).?);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqual(@as(?u32, 91), plane.images[0].kitty_id);
    try std.testing.expectEqual(@as(?u32, 92), plane.images[1].kitty_id);
}

test "Kitty virtual parent admits a physically rendered child without cursor motion" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=42,p=3,U=1,C=1,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=43,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const before = plane.generation();
    const added = try plane.command("a=p,i=43,p=4,P=42,Q=3,H=2,V=-1,q=2", .primary, 0, 1, 6, 1, 1);
    try std.testing.expect(added.changed and added.failure == null);
    try std.testing.expect(added.cursor_advance == null);
    try std.testing.expect(plane.generation() > before);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expectEqual(plane.placement(0).?.identity, plane.placement(1).?.parent_identity);
    // The relative offset is retained, not mistaken for an ordinary cursor
    // anchor before any U+10EEEE text exists.
    try std.testing.expect(plane.placementAnchor(1) == null);
    try std.testing.expect((try plane.command("a=d,d=i,i=42,p=3", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "Kitty physical P Q placement admits signed offsets without moving the cursor and cascades deletion" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=91,p=3,C=1,q=2;AQIDBA==",
        .primary,
        0,
        2,
        3,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=92,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const generation = plane.generation();
    const added = try plane.command("a=p,i=92,p=4,P=91,Q=3,H=2,V=1,q=2", .primary, 0, 1, 1, 1, 1);
    try std.testing.expect(added.changed);
    try std.testing.expect(added.failure == null);
    try std.testing.expect(added.cursor_advance == null);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expect(plane.generation() > generation);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 3, .col = 5 }, plane.placementAnchor(1).?);

    const missed = try plane.command("a=p,i=92,p=5,P=999,Q=3,H=1,q=2", .primary, 0, 1, 1, 1, 1);
    try std.testing.expect(missed.failure != null);
    try std.testing.expect(!missed.changed);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=i,i=91,p=3", .primary, 0, 2, 3, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "Kitty physical ancestry keeps sixteen bounded parent links and rejects cycles transactionally" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=71,p=1,C=1,q=2;AQIDBA==",
        .primary,
        0,
        2,
        3,
        1,
        1,
    )).changed);
    const parent_identity = plane.placement(0).?.identity;
    try std.testing.expect(parent_identity != 0);
    var text: [96]u8 = undefined;
    for (2..18) |placement_id| {
        const put = try std.fmt.bufPrint(&text, "a=p,i=71,p={d},P=71,Q={d},H=1,V=0,q=2", .{ placement_id, placement_id - 1 });
        const result = try plane.command(put, .primary, 0, 0, 0, 1, 1);
        try std.testing.expect(result.changed and result.failure == null and result.cursor_advance == null);
        try std.testing.expectEqualDeep(Plane.Anchor{ .row = 2, .col = @intCast(3 + placement_id - 1) }, plane.placementAnchor(placement_id - 1).?);
    }
    try std.testing.expectEqual(@as(u16, 17), plane.placement_count);
    const last = plane.generation();
    const too_deep = try plane.command("a=p,i=71,p=18,P=71,Q=17,H=1,q=2", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.too_deep, too_deep.failure.?);
    try std.testing.expect(!too_deep.changed);
    const self_reference = try plane.command("a=p,i=71,p=1,P=71,Q=1,q=2", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, self_reference.failure.?);
    const cycle = try plane.command("a=p,i=71,p=1,P=71,Q=17,q=2", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.cycle, cycle.failure.?);
    try std.testing.expect(!cycle.changed);
    try std.testing.expectEqual(last, plane.generation());
    try std.testing.expectEqual(parent_identity, plane.placement(0).?.identity);

    // Reparenting the root of an already deep subtree must account for
    // existing descendants, not merely validate its newly selected parent.
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=72,p=1,C=1,q=2;AQIDBA==",
        .primary,
        0,
        7,
        0,
        1,
        1,
    )).changed);
    const before_reparent = plane.generation();
    const excessive_reparent = try plane.command("a=p,i=71,p=1,P=72,Q=1,q=2", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(@as(?Failure, .too_deep), excessive_reparent.failure);
    try std.testing.expect(!excessive_reparent.changed);
    try std.testing.expectEqual(before_reparent, plane.generation());
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 2, .col = 19 }, plane.placementAnchor(16).?);

    // Re-put changes the root anchor, not any of its children's identity.
    try std.testing.expect((try plane.command("a=p,i=71,p=1,C=1,q=2", .primary, 0, 5, 1, 1, 1)).changed);
    try std.testing.expectEqual(parent_identity, plane.placement(0).?.identity);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 5, .col = 17 }, plane.placementAnchor(16).?);
    try std.testing.expect(plane.scroll(.primary, 0, 9, 1, true));
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 4, .col = 17 }, plane.placementAnchor(16).?);
    try std.testing.expect((try plane.command("a=d,d=i,i=71,p=1", .primary, 0, 4, 1, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expect((try plane.command("a=d,d=i,i=72,p=1", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "Kitty physical P Q validates bank and ancestor lifetime without evicting unrelated data" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=81,p=1,C=1,q=2;AQIDBA==", .primary, 0, 2, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=82,q=2;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    const generation = plane.generation();
    const bytes = plane.storage_bytes;
    const other_bank = try plane.command("a=p,i=82,p=2,P=81,Q=1,q=2", .alternate, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.parent_missing, other_bank.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    const unknown_ref = try plane.command("a=p,i=82,p=2,P=81,Q=9,q=2", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.parent_missing, unknown_ref.failure.?);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(bytes, plane.storage_bytes);
    try std.testing.expect((try plane.command("a=p,i=82,p=2,P=81,Q=1,H=-5,V=-1,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 1, .col = -2 }, plane.placementAnchor(1).?);
    const child_identity = plane.placement(1).?.identity;
    const unsupported_bank_change = try plane.command("a=p,i=81,p=1,C=1,q=2", .alternate, 0, 1, 1, 1, 1);
    try std.testing.expectEqual(Failure.unsupported, unsupported_bank_change.failure.?);
    try std.testing.expectEqual(child_identity, plane.placement(1).?.identity);
    try std.testing.expect((try plane.command("a=d,d=i,i=82,p=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 2, .col = 3 }, plane.placementAnchor(0).?);
    try std.testing.expectEqual(bytes, plane.storage_bytes);
}

test "Kitty relative placement keeps parent identity across unrelated dense-slot retirement" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=80,p=9,C=1,q=2;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=82,p=2,C=1,q=2;AQIDBA==", .primary, 0, 1, 1, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=81,p=1,C=1,q=2;AQIDBA==", .primary, 0, 3, 4, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=p,i=82,p=2,P=81,Q=1,H=-1,V=2,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 5, .col = 3 }, plane.placementAnchor(1).?);
    const parent_id = plane.placement(2).?.identity;
    const child_id = plane.placement(1).?.identity;
    try std.testing.expectEqual(@as(?u16, 2), plane.placement(1).?.parent_slot);
    try std.testing.expect((try plane.command("a=d,d=i,i=80,p=9", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    const moved_parent = plane.identityIndex(parent_id) orelse return error.MissingParent;
    const child = plane.identityIndex(child_id) orelse return error.MissingChild;
    try std.testing.expectEqual(@as(?u16, @intCast(moved_parent)), plane.placement(child).?.parent_slot);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 5, .col = 3 }, plane.placementAnchor(child).?);
    try std.testing.expect((try plane.command("a=d,d=i,i=81,p=1", .primary, 0, 3, 4, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
}

test "Kitty relative placement deletes at resolved geometry and default Q selects oldest parent" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=51,p=1,C=1,q=2;AQIDBA==", .primary, 0, 2, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=p,i=51,p=2,C=1,q=2", .primary, 0, 5, 2, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=52,q=2;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    // Q omitted: select the oldest retained parent placement, not the
    // newest or a coordinate copied from the current cursor.
    try std.testing.expect((try plane.command("a=p,i=52,p=3,P=51,H=2,V=1,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 3, .col = 5 }, plane.placementAnchor(2).?);
    const before = plane.generation();
    const miss = try plane.command("a=d,d=p,x=1,y=1", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(!miss.changed);
    try std.testing.expectEqual(before, plane.generation());
    try std.testing.expectEqual(@as(u16, 3), plane.placement_count);
    const hit = try plane.command("a=d,d=p,x=6,y=4", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(hit.changed);
    try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 2, .col = 3 }, plane.placementAnchor(0).?);
    try std.testing.expectEqualDeep(Plane.Anchor{ .row = 5, .col = 2 }, plane.placementAnchor(1).?);
}

test "Kitty physical parent retires a wide child fanout with one bounded graph closure" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=41,p=1,C=1,q=2;AQIDBA==", .primary, 0, 1, 1, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=42,q=2;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
    var text: [88]u8 = undefined;
    for (2..258) |placement_id| {
        const bytes = try std.fmt.bufPrint(&text, "a=p,i=42,p={d},P=41,Q=1,H=0,V=0,q=2", .{placement_id});
        const result = try plane.command(bytes, .primary, 0, 0, 0, 1, 1);
        try std.testing.expect(result.changed and result.failure == null);
    }
    try std.testing.expectEqual(@as(u16, 257), plane.placement_count);
    const storage = plane.storage_bytes;
    try std.testing.expect((try plane.command("a=d,d=i,i=41,p=1", .primary, 0, 1, 1, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    // Lowercase deletion retains image bytes; the graph closes without
    // deleting unrelated decoded resources or leaking live placements.
    try std.testing.expectEqual(storage, plane.storage_bytes);
}

test "Kitty physical relative placements participate in all six geometry deletion selectors" {
    for ([_]struct { miss: []const u8, hit: []const u8 }{
        .{ .miss = "a=d,d=p,x=2,y=4", .hit = "a=d,d=p,x=6,y=4" },
        .{ .miss = "a=d,d=q,x=2,y=4,z=-7", .hit = "a=d,d=q,x=6,y=4,z=-7" },
        .{ .miss = "a=d,d=x,x=2", .hit = "a=d,d=x,x=6" },
        .{ .miss = "a=d,d=y,y=2", .hit = "a=d,d=y,y=4" },
        .{ .miss = "a=d,d=z,z=2", .hit = "a=d,d=z,z=-7" },
        .{ .miss = "a=d,d=c", .hit = "a=d,d=c" },
    }) |case| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        try std.testing.expect((try plane.command("a=T,f=32,s=1,v=1,i=101,p=1,C=1,q=2;AQIDBA==", .primary, 0, 2, 3, 1, 1)).changed);
        try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=102,q=2;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expect((try plane.command("a=p,i=102,p=2,P=101,Q=1,H=2,V=1,z=-7,q=2", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expectEqualDeep(Plane.Anchor{ .row = 3, .col = 5 }, plane.placementAnchor(1).?);
        const generation = plane.generation();
        const miss = try plane.command(case.miss, .primary, 0, 0, 0, 1, 1);
        try std.testing.expect(!miss.changed);
        try std.testing.expectEqual(generation, plane.generation());
        try std.testing.expectEqual(@as(u16, 2), plane.placement_count);
        const hit = try plane.command(case.hit, .primary, 0, 3, 5, 1, 1);
        try std.testing.expect(hit.changed);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        try std.testing.expectEqualDeep(Plane.Anchor{ .row = 2, .col = 3 }, plane.placementAnchor(0).?);
    }
}

test "Kitty clipped margin geometry respects all six matched-only deletion selectors" {
    const cases = [_]struct {
        miss: []const u8,
        hit: []const u8,
        miss_row: u64 = 0,
        hit_row: u64 = 0,
        miss_col: u16 = 0,
        hit_col: u16 = 0,
    }{
        .{ .miss = "a=d,d=P,x=2,y=4", .hit = "a=d,d=P,x=2,y=3" },
        .{ .miss = "a=d,d=Q,x=2,y=4,z=-4", .hit = "a=d,d=Q,x=2,y=3,z=-4" },
        .{ .miss = "a=d,d=X,x=3", .hit = "a=d,d=X,x=2" },
        .{ .miss = "a=d,d=Y,y=4", .hit = "a=d,d=Y,y=3" },
        .{ .miss = "a=d,d=Z,z=5", .hit = "a=d,d=Z,z=-4" },
        .{ .miss = "a=d,d=C", .hit = "a=d,d=C", .miss_row = 3, .hit_row = 2, .miss_col = 1, .hit_col = 1 },
    };
    for (cases) |case| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        // Initially unplaced decoded data is never a geometric hit.
        try std.testing.expect((try plane.command(
            "a=t,f=32,s=1,v=1,i=77,q=2;AQIDBA==",
            .primary,
            0,
            0,
            0,
            1,
            1,
        )).changed);
        try std.testing.expect((try plane.command(
            "a=T,f=32,s=1,v=2,i=76,z=-4,C=1,q=2;AQIDBAUGBwg=",
            .primary,
            0,
            1,
            1,
            1,
            1,
        )).changed);
        try std.testing.expect(plane.scrollColumns(.primary, 1, 2, 0, 7, 1, false));
        try std.testing.expectEqual(@as(u64, 2), plane.placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 1), plane.placement(0).?.rows);
        const generation = plane.generation();
        const content = plane.content_generation;
        const storage = plane.storage_bytes;
        const miss = try plane.command(case.miss, .primary, 0, case.miss_row, case.miss_col, 1, 1);
        try std.testing.expect(!miss.changed);
        try std.testing.expectEqual(@as(u2, 2), miss.quiet);
        try std.testing.expectEqual(generation, plane.generation());
        try std.testing.expectEqual(content, plane.content_generation);
        try std.testing.expectEqual(storage, plane.storage_bytes);
        const hit = try plane.command(case.hit, .primary, 0, case.hit_row, case.hit_col, 1, 1);
        try std.testing.expect(hit.changed);
        try std.testing.expectEqual(@as(u2, 2), hit.quiet);
        try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(usize, 4), plane.storage_bytes);
        try std.testing.expectEqual(@as(?u32, 77), plane.images[0].kitty_id);
    }
}

test "Kitty uppercase geometric selectors reclaim matched data without sweeping other images" {
    const cases = [_]struct {
        no_hit: []const u8,
        hit: []const u8,
    }{
        .{ .no_hit = "a=d,d=P,x=8,y=8", .hit = "a=d,d=P,x=3,y=2" },
        .{ .no_hit = "a=d,d=Q,x=8,y=8,z=-2", .hit = "a=d,d=Q,x=3,y=2,z=-2" },
        .{ .no_hit = "a=d,d=X,x=8", .hit = "a=d,d=X,x=3" },
        .{ .no_hit = "a=d,d=Y,y=8", .hit = "a=d,d=Y,y=2" },
        .{ .no_hit = "a=d,d=Z,z=4", .hit = "a=d,d=Z,z=-2" },
        .{ .no_hit = "a=d,d=C", .hit = "a=d,d=C" },
    };
    for (cases, 0..) |case, index| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=55;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expect((try plane.command("a=t,f=32,s=1,v=1,i=7;AQIDBA==", .primary, 0, 0, 0, 1, 1)).changed);
        try std.testing.expect((try plane.command("a=p,i=7,p=3,z=-2", .primary, 0, 1, 2, 1, 1)).changed);
        const orphan_image = plane.image(0).?.id;
        const live_image = plane.image(1).?.id;
        const before_bytes = plane.storage_bytes;
        const before_generation = plane.generation();
        const miss_row: u64 = if (index == 5) 7 else 0;
        const miss_col: u16 = if (index == 5) 7 else 0;
        const miss = try plane.command(case.no_hit, .primary, 0, miss_row, miss_col, 1, 1);
        try std.testing.expect(!miss.changed);
        try std.testing.expectEqual(@as(u2, 2), miss.quiet);
        try std.testing.expectEqual(before_generation, plane.generation());
        try std.testing.expectEqual(before_bytes, plane.storage_bytes);
        try std.testing.expectEqual(@as(u16, 2), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);

        const hit = try plane.command(case.hit, .primary, 0, 1, 2, 1, 1);
        try std.testing.expect(hit.changed);
        try std.testing.expectEqual(@as(u2, 2), hit.quiet);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
        try std.testing.expectEqual(orphan_image, plane.image(0).?.id);
        try std.testing.expect(plane.image(0).?.id != live_image);
        try std.testing.expectEqual(before_bytes - 4, plane.storage_bytes);
    }
}

test "Kitty image-number lookup selects newest identity after dense image compaction" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    for ([_][]const u8{
        "a=t,f=32,s=1,v=1,i=1;AQIDBA==",
        "a=t,f=32,s=1,v=1,I=44;AQIDBA==",
        "a=t,f=32,s=1,v=1,i=3;AQIDBA==",
        "a=t,f=32,s=1,v=1,I=44;AQIDBA==",
    }) |transmit|
        try std.testing.expect((try plane.command(transmit, .primary, 0, 0, 0, 1, 1)).changed);
    const newest_id = plane.image(3).?.id;
    try std.testing.expect((try plane.command("a=d,d=I,i=1", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 3), plane.image_count);
    // removeImage uses swap-with-last, not insertion-preserving order.
    try std.testing.expectEqual(newest_id, plane.image(0).?.id);
    try std.testing.expect((try plane.command("a=p,I=44,p=7", .primary, 0, 1, 1, 1, 1)).changed);
    try std.testing.expectEqual(newest_id, plane.placement(0).?.image_id);
    try std.testing.expect((try plane.command("a=d,d=N,I=44,p=7", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
}

test "Kitty crop destination offsets and layer preflight before placement mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=2,i=11;AQIDBAUGBwgJCgsMDQ4PEA==",
        .primary,
        0,
        0,
        0,
        8,
        16,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=p,i=11,p=3,x=1,y=0,w=1,h=2,c=2,r=3,X=2,Y=4,z=-7",
        .primary,
        0,
        4,
        5,
        8,
        16,
    )).changed);
    const placed = plane.placement(0).?;
    try std.testing.expectEqual(@as(u32, 1), placed.source_x);
    try std.testing.expectEqual(@as(u32, 1), placed.source_width);
    try std.testing.expectEqual(@as(u32, 14), placed.pixel_width);
    try std.testing.expectEqual(@as(u32, 44), placed.pixel_height);
    try std.testing.expectEqual(@as(i32, -7), placed.z);
    const generation = plane.next_generation;
    const unchanged = plane.placement(0).?;
    const invalid = try plane.command("a=p,i=11,p=3,x=2", .primary, 0, 7, 7, 8, 16);
    try std.testing.expectEqual(Failure.invalid, invalid.failure.?);
    try std.testing.expectEqual(generation, plane.next_generation);
    try std.testing.expectEqualDeep(unchanged, plane.placement(0).?);
}

test "Kitty z and point3d deletion preserve unmatched layers and image data" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=12;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=p,i=12,p=1,z=-2", .primary, 10, 10, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=p,i=12,p=2,z=4", .primary, 10, 10, 3, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=q,x=4,y=1,z=-2", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 1), plane.placement_count);
    try std.testing.expectEqual(@as(i32, 4), plane.placement(0).?.z);
    try std.testing.expectEqual(@as(usize, 1), plane.image_count);
    try std.testing.expect(!(try plane.command("a=d,d=z,z=-2", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=Z,z=4", .primary, 10, 10, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(usize, 0), plane.placement_count);
    try std.testing.expectEqual(@as(usize, 0), plane.image_count);
}

// =============================================================================
// Animation frame and composition proofs
// =============================================================================

test "Kitty frames compose transactionally and advance on monotonic gaps" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=20;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const frame = try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=99,c=1,z=50;AAD/gA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(frame.changed);
    try std.testing.expect(!frame.visual_changed);
    try std.testing.expectEqual(@as(?u32, 2), frame.response_frame);
    try std.testing.expectEqual(@as(usize, 1), plane.frame_count);
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 128, 255 }, plane.frames[0].pixels);
    const generation_before_bad_composition = plane.generation();
    const bad_composition = try plane.command(
        "a=c,i=20,r=1,c=2,C=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, bad_composition.failure.?);
    try std.testing.expectEqual(generation_before_bad_composition, plane.generation());
    const generation_before_invalid_control = plane.generation();
    const invalid_control = try plane.command(
        "a=a,i=20,c=2,r=99,z=10",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.missing, invalid_control.failure.?);
    try std.testing.expectEqual(@as(u16, 0), plane.images[0].current_frame);
    try std.testing.expectEqual(generation_before_invalid_control, plane.generation());

    const started = plane.advanceAnimations(100);
    try std.testing.expect(!started.changed);
    try std.testing.expectEqual(@as(?u32, null), started.next_ms);
    try std.testing.expect((try plane.command(
        "a=a,i=20,s=3,r=1,z=40",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(100).next_ms);
    const second = plane.advanceAnimations(140);
    try std.testing.expect(second.changed);
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 128, 255 }, plane.image(0).?.pixels);
    const root = plane.advanceAnimations(190);
    try std.testing.expect(root.changed);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);

    try std.testing.expect((try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=3,C=1;AP8A/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=c,i=20,r=2,c=3",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const internal_id = plane.image(0).?.id;
    try std.testing.expectEqualSlices(u8, plane.frames[0].pixels, plane.frameByNumber(internal_id, 3).?.pixels);
    try std.testing.expect((try plane.command("a=d,d=f,i=20,r=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
    try std.testing.expect(plane.frameByNumber(internal_id, 2) != null);
    const bytes_before_root_edit = plane.storage_bytes;
    const root_prefix = try plane.command(
        "a=f,f=32,i=20,s=1,v=1,r=1,C=1,z=70,m=1;AAH+",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(!root_prefix.changed);
    const root_edit = try plane.command(
        "m=0;/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(root_edit.changed);
    try std.testing.expect(root_edit.visual_changed);
    try std.testing.expectEqual(@as(?u32, 1), root_edit.response_frame);
    try std.testing.expectEqual(bytes_before_root_edit, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 254, 255 }, plane.images[0].pixels);
    try std.testing.expectEqual(@as(u32, 70), plane.images[0].root_gap_ms);
    try std.testing.expect(plane.reset());
    try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
}

test "Kitty frame loading preserves edits background bases and action-specific composition" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=2,i=25,q=2;/wAA/wD/AP8AAP///////w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const image_id = plane.image(0).?.id;
    try std.testing.expectEqual(@as(u32, 0), plane.images[0].root_gap_ms);

    // New extra frame: 40 ms default gap and exact full-frame bytes.
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=2,v=2,i=25,r=2,z=77,C=1,q=2;CgoK/xQUFP8eHh7/KCgo/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u32, 77), plane.frameByNumber(image_id, 2).?.gap_ms);

    // Partial edit of an existing frame preserves every untouched pixel and,
    // with z=0, preserves the existing 77 ms gap.
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=25,r=2,x=1,y=1,X=1,q=2;yAEC/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{
            10, 10, 10, 255, 20,  20, 20, 255,
            30, 30, 30, 255, 200, 1,  2,  255,
        },
        plane.frameByNumber(image_id, 2).?.pixels,
    );
    try std.testing.expectEqual(@as(u32, 77), plane.frameByNumber(image_id, 2).?.gap_ms);

    // Root edits are edits too: preserve untouched pixels and root's default
    // zero gap when no z change is requested.
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=25,r=1,x=0,y=1,C=1,q=2;A8kE/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{
            255, 0,   0, 255, 0,   255, 0,   255,
            3,   201, 4, 255, 255, 255, 255, 255,
        },
        plane.image(0).?.pixels,
    );
    try std.testing.expectEqual(@as(u32, 0), plane.images[0].root_gap_ms);

    // A new frame with no c=base starts from the exact Y RGBA canvas. Use the
    // documented X=1 overwrite spelling to prove its action-specific alias.
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=25,r=3,x=1,y=0,X=1,Y=287454020,q=2;BQbK/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{
            0x11, 0x22, 0x33, 0x44, 5,    6,    202,  255,
            0x11, 0x22, 0x33, 0x44, 0x11, 0x22, 0x33, 0x44,
        },
        plane.frameByNumber(image_id, 3).?.pixels,
    );
    try std.testing.expectEqual(@as(u32, 40), plane.frameByNumber(image_id, 3).?.gap_ms);

    // c=base wins over Y for a new frame, preserving the selected base frame
    // outside the transmitted patch.
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=25,r=4,c=2,x=0,y=0,C=1,Y=4278190335,q=2;BQbK/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{
            5,  6,  202, 255, 20,  20, 20, 255,
            30, 30, 30,  255, 200, 1,  2,  255,
        },
        plane.frameByNumber(image_id, 4).?.pixels,
    );

    // Invalid documented compose modes remain transactional.
    const generation = plane.generation();
    const storage = plane.storage_bytes;
    const invalid = try plane.command(
        "a=f,f=32,s=1,v=1,i=25,r=2,X=2,q=2;BQbK/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, invalid.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(storage, plane.storage_bytes);
}

test "Kitty composition owns root and nonoverlapping same-frame edits" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=1,i=30,q=2;AQAA/wIAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=2,v=1,i=30,r=2,C=1,q=2;CgAA/xQAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const image_id = plane.image(0).?.id;
    const storage = plane.storage_bytes;
    const same = try plane.command(
        "a=c,i=30,r=2,c=2,s=1,v=1,x=1,X=0,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(same.changed);
    try std.testing.expect(!same.visual_changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 10, 0, 0, 255, 10, 0, 0, 255 },
        plane.frameByNumber(image_id, 2).?.pixels,
    );
    const generation = plane.generation();
    const overlap = try plane.command(
        "a=c,i=30,r=2,c=2,s=1,v=1,x=0,X=0,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.invalid, overlap.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(storage, plane.storage_bytes);
    const root = try plane.command(
        "a=c,i=30,r=2,c=1,s=1,v=1,x=0,X=1,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(root.changed);
    try std.testing.expect(root.visual_changed);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 10, 0, 0, 255, 2, 0, 0, 255 },
        plane.images[0].pixels,
    );
    try std.testing.expectEqual(storage, plane.storage_bytes);
}

test "Kitty frame composition honors documented w/h rectangle without using s/v" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=2,v=1,i=30,q=2;AQAA/wIAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=2,v=1,i=30,r=2,C=1,q=2;CgAA/xQAAP8=",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const before = plane.generation();
    // Kitty a79f376 graphics.c::handle_compose_command uses w/h for its
    // rectangle and x/y as destination, X/Y as source. The undocumented
    // s/v aliases cannot override a specified documented rectangle.
    const composed = try plane.command(
        "a=c,i=30,r=2,c=1,x=1,X=0,w=1,h=1,s=2,v=1,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(@as(?Failure, null), composed.failure);
    try std.testing.expect(composed.changed);
    try std.testing.expect(plane.generation() > before);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 255, 10, 0, 0, 255 }, plane.image(0).?.pixels);
    try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
}

test "Kitty animation control compose and frame deletion retain Howl shared-plane bank policy" {
    // Pinned Kitty screen.c owns separate main_grman and alt_grman. The
    // same client ID in the other bank cannot resolve this primary image
    // there. Howl deliberately keeps one shared bounded decoded image
    // plane, so these global-ID actions can mutate primary image data.
    // This negative compatibility proof must not be mislabelled full.
    for ([_]struct {
        command: []const u8,
        operation: enum { select_frame, compose, delete_frame },
    }{
        .{ .command = "a=a,i=90,c=2,q=2", .operation = .select_frame },
        .{ .command = "a=c,i=90,r=2,c=1,s=1,v=1,C=1,q=2", .operation = .compose },
        .{ .command = "a=d,d=f,i=90,r=2", .operation = .delete_frame },
    }) |case| {
        var plane = Plane.init(std.testing.allocator);
        defer plane.deinit();
        try std.testing.expect((try plane.command(
            "a=T,f=32,s=1,v=1,i=90,p=1,C=1,q=2;AQIDBA==",
            .primary,
            0,
            0,
            0,
            1,
            1,
        )).changed);
        try std.testing.expect((try plane.command(
            "a=f,f=32,s=1,v=1,i=90,r=2,C=1,q=2;BQYHCA==",
            .primary,
            0,
            0,
            0,
            1,
            1,
        )).changed);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
        const retained = plane.placement(0).?;
        try std.testing.expectEqual(Bank.primary, retained.bank);
        const original_content_generation = plane.content_generation;
        const changed_by_other_bank = try plane.command(
            case.command,
            .alternate,
            0,
            0,
            0,
            1,
            1,
        );
        try std.testing.expect(changed_by_other_bank.changed);
        try std.testing.expectEqual(@as(?Failure, null), changed_by_other_bank.failure);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        try std.testing.expectEqualDeep(retained, plane.placement(0).?);
        try std.testing.expectEqual(Bank.primary, plane.images[0].bank);
        switch (case.operation) {
            .select_frame => {
                try std.testing.expectEqual(@as(u16, 1), plane.images[0].current_frame);
                try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.image(0).?.pixels);
                try std.testing.expect(plane.content_generation > original_content_generation);
                try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
            },
            .compose => {
                try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.image(0).?.pixels);
                try std.testing.expect(plane.content_generation > original_content_generation);
                try std.testing.expectEqual(@as(u16, 1), plane.frame_count);
            },
            .delete_frame => {
                try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
                try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, plane.image(0).?.pixels);
                try std.testing.expectEqual(original_content_generation, plane.content_generation);
                try std.testing.expectEqual(@as(u2, 2), changed_by_other_bank.quiet);
            },
        }
    }
}

test "Kitty frame deletion defaults to root and uppercase retires frame-less image" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=40,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=40,r=2,C=1,q=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const after_root = try plane.command("a=d,d=f,i=40", .primary, 0, 0, 0, 1, 1);
    try std.testing.expect(after_root.changed);
    try std.testing.expect(after_root.visual_changed);
    try std.testing.expectEqual(@as(u16, 0), plane.frame_count);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.image(0).?.pixels);
    try std.testing.expect(!(try plane.command("a=d,d=f,i=40", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expect((try plane.command("a=d,d=F,i=40", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(usize, 0), plane.storage_bytes);
}

test "Kitty animation requires a placement and nonzero total duration" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=41,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=41,r=2,z=-1,C=1,q=2;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command("a=a,i=41,s=3,r=1,z=40,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(100).next_ms);
    try std.testing.expect((try plane.command("a=p,i=41,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(100).next_ms);
    try std.testing.expect((try plane.command("a=d,d=a", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(1000).next_ms);
    try std.testing.expect((try plane.command("a=p,i=41,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    try std.testing.expectEqual(@as(?u32, 40), plane.advanceAnimations(1000).next_ms);
    try std.testing.expect((try plane.command(
        "a=a,i=41,r=1,z=-1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(?u32, null), plane.advanceAnimations(200).next_ms);
}

test "Kitty root frame is gapless until its gap is explicitly configured" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=42,C=1,q=2;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expect((try plane.command(
        "a=f,f=32,s=1,v=1,i=42,r=2,z=50,C=1,q=2;AAD//w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u32, 0), plane.images[0].root_gap_ms);
    try std.testing.expect((try plane.command("a=a,i=42,s=3,q=2", .primary, 0, 0, 0, 1, 1)).changed);
    const first = plane.advanceAnimations(100);
    try std.testing.expect(first.changed);
    try std.testing.expectEqual(@as(?u32, 50), first.next_ms);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, plane.image(0).?.pixels);
}

test "Kitty PNG f=100 is chunked bounded and transactional through the graphics plane" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const encoded = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";

    var first: [256]u8 = undefined;
    const first_command = try std.fmt.bufPrint(&first, "a=T,f=100,i=91,p=4,m=1,q=2;{s}", .{encoded[0..48]});
    const partial = try plane.command(first_command, .primary, 0, 2, 3, 8, 16);
    try std.testing.expect(!partial.changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    var continuation: [256]u8 = undefined;
    const last_command = try std.fmt.bufPrint(&continuation, "m=0,q=2;{s}", .{encoded[48..]});
    const admitted = try plane.command(last_command, .primary, 0, 2, 3, 8, 16);
    try std.testing.expect(admitted.changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
    try std.testing.expectEqual(@as(u32, 2), plane.image(0).?.width);
    try std.testing.expectEqual(@as(u32, 1), plane.image(0).?.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, plane.image(0).?.pixels);
    const generation = plane.generation();
    const identity = plane.image(0).?.id;

    // The PNG itself supplies geometry. An explicit contradictory size is
    // rejected after decoding without destroying the existing image.
    var mismatch_command: [256]u8 = undefined;
    const mismatch_text = try std.fmt.bufPrint(&mismatch_command, "a=t,f=100,i=91,s=3,v=1,q=2;{s}", .{encoded});
    const mismatch = try plane.command(mismatch_text, .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(Failure.invalid, mismatch.failure.?);
    try std.testing.expectEqual(generation, plane.generation());

    // Corrupt the PNG CRC but keep the base64 framing valid.
    const allocator = std.testing.allocator;
    const byte_count = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const corrupted = try allocator.alloc(u8, byte_count);
    defer allocator.free(corrupted);
    try std.base64.standard.Decoder.decode(corrupted, encoded);
    corrupted[corrupted.len - 8] ^= 0x01;
    const bad_payload = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(corrupted.len));
    defer allocator.free(bad_payload);
    const bad_text = std.base64.standard.Encoder.encode(bad_payload, corrupted);
    const bad_command = try std.fmt.allocPrint(allocator, "a=t,f=100,i=91,q=2;{s}", .{bad_text});
    defer allocator.free(bad_command);
    const rejected = try plane.command(bad_command, .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(Failure.invalid, rejected.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqual(identity, plane.image(0).?.id);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, plane.image(0).?.pixels);

    // Kitty also permits the entire PNG to be zlib-compressed when S gives
    // the inner PNG byte length. A stored zlib block makes an exact oracle.
    const wrapped = try allocator.alloc(u8, corrupted.len + 11);
    defer allocator.free(wrapped);
    corrupted[corrupted.len - 8] ^= 0x01;
    wrapped[0] = 0x78;
    wrapped[1] = 0x01;
    wrapped[2] = 1;
    const inner_len: u16 = @intCast(corrupted.len);
    std.mem.writeInt(u16, wrapped[3..5], inner_len, .little);
    std.mem.writeInt(u16, wrapped[5..7], ~inner_len, .little);
    @memcpy(wrapped[7..][0..corrupted.len], corrupted);
    std.mem.writeInt(u32, wrapped[wrapped.len - 4 ..][0..4], std.hash.Adler32.hash(corrupted), .big);
    const wrapped_payload = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(wrapped.len));
    defer allocator.free(wrapped_payload);
    const wrapped_text = std.base64.standard.Encoder.encode(wrapped_payload, wrapped);
    const compressed_command = try std.fmt.allocPrint(
        allocator,
        "a=t,f=100,i=92,o=z,S={d},q=2;{s}",
        .{ corrupted.len, wrapped_text },
    );
    defer allocator.free(compressed_command);
    const compressed_result = try plane.command(compressed_command, .primary, 0, 0, 0, 8, 16);
    try std.testing.expect(compressed_result.changed);
    try std.testing.expectEqual(@as(u16, 2), plane.image_count);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, plane.image(1).?.pixels);

    // Exact payload shape emitted by kitten icat: unpadded base64 and explicit
    // PNG dimensions. The image is yellow 64x40 RGBA.
    const icat = "a=T,q=2,f=100,s=64,v=40;" ++
        "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAYAAABOzvzpAAAAaElEQVRo3u3QQREAIAzAsIF/z0NGHjQKej27s/OxqwO0BugArQE6QGuADtAaoAO0BugArQE6QGuADtAaoAO0BugArQE6QGuADtAaoAO0BugArQE6QGuADtAaoAO0BugArQE6QGuADtAeblkDTdoY5TUAAAAASUVORK5CYII";
    const icat_result = try plane.command(icat, .primary, 0, 0, 0, 8, 16);
    try std.testing.expect(icat_result.changed);
    try std.testing.expectEqual(@as(u32, 64), plane.image(2).?.width);
    try std.testing.expectEqual(@as(u32, 40), plane.image(2).?.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 0, 255 }, plane.image(2).?.pixels[0..4]);
}

test "Kitty graphics detection accepts a direct query with exact S size" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const result = try plane.command("a=q,f=24,s=1,v=1,S=3,i=1;MTIz", .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(@as(?Failure, null), result.failure);
    try std.testing.expectEqual(@as(?u32, 1), result.response_id);
    try std.testing.expect(!result.changed);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    const mismatched = try plane.command("a=q,f=24,s=1,v=1,S=2,i=1;MTIz", .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(Failure.invalid, mismatched.failure.?);
}

test "Kitty PNG grows bounded chunk storage without admitting a partial image" {
    const allocator = std.testing.allocator;
    var plane = Plane.init(allocator);
    defer plane.deinit();
    const tiny = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const tiny_len = try std.base64.standard.Decoder.calcSizeForSlice(tiny);
    const original = try allocator.alloc(u8, tiny_len);
    defer allocator.free(original);
    try std.base64.standard.Decoder.decode(original, tiny);

    // A valid ancillary chunk larger than the initial 8 KiB transfer buffer
    // forces bounded growth. Its bytes have no effect on decoded pixels.
    const text_len = 9 * 1024;
    const chunk_start = original.len - 12;
    const expanded = try allocator.alloc(u8, original.len + 12 + text_len);
    defer allocator.free(expanded);
    @memcpy(expanded[0..chunk_start], original[0..chunk_start]);
    std.mem.writeInt(u32, expanded[chunk_start..][0..4], text_len, .big);
    @memcpy(expanded[chunk_start + 4 ..][0..4], "tEXt");
    const payload = expanded[chunk_start + 8 ..][0..text_len];
    @memset(payload, 'x');
    @memcpy(payload[0..5], "Note\x00");
    var crc = std.hash.Crc32.init();
    crc.update("tEXt");
    crc.update(payload);
    std.mem.writeInt(u32, expanded[chunk_start + 8 + text_len ..][0..4], crc.final(), .big);
    @memcpy(expanded[chunk_start + 12 + text_len ..], original[chunk_start..]);

    const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(expanded.len));
    defer allocator.free(encoded);
    const text = std.base64.standard.Encoder.encode(encoded, expanded);
    var offset: usize = 0;
    var chunk_count: usize = 0;
    while (offset < text.len) {
        const end = @min(text.len, offset + 4096);
        const more = end < text.len;
        const prefix = if (chunk_count == 0)
            (if (more) "a=t,f=100,i=17,m=1,q=2;" else "a=t,f=100,i=17,m=0,q=2;")
        else if (more)
            "m=1,q=2;"
        else
            "m=0,q=2;";
        var command: [max_command_bytes]u8 = undefined;
        const body = try std.fmt.bufPrint(&command, "{s}{s}", .{ prefix, text[offset..end] });
        const result = try plane.command(body, .primary, 0, 0, 0, 8, 16);
        try std.testing.expectEqual(!more, result.changed);
        try std.testing.expectEqual(@as(u16, if (more) 0 else 1), plane.image_count);
        chunk_count += 1;
        offset = end;
    }
    try std.testing.expect(chunk_count >= 3);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, plane.image(0).?.pixels);
}

test "Kitty graphics feature queries return exact advertised keys without changing the plane" {
    const request = parseCommand("a=q,i=31,e=T,U=1,C=1") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 'T'), request.feature_action);
    var output: [128]u8 = undefined;
    try std.testing.expectEqualStrings(",e=T,C=1,U=1", try formatFeatureQuery("a=q,i=31,e=T,U=1,C=1", &output));
    try std.testing.expectEqualStrings(",e=t,f=24,s=1,v=1", try formatFeatureQuery("a=q,i=31,e=t,f=24,s=1,v=1", &output));
    try std.testing.expectEqualStrings(
        ",e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3",
        try formatFeatureQuery("a=q,i=31,e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3,s=1", &output),
    );
    try std.testing.expectEqualStrings(",e=p", try formatFeatureQuery("a=q,i=31,e=p,C=0,U=0,s=1,f=24", &output));
    try std.testing.expectEqualStrings(",e=d,d=i,p=7", try formatFeatureQuery("a=q,i=31,e=d,d=i,p=7", &output));
    try std.testing.expectEqualStrings(",e=d,d=q,x=2,y=3,z=-7", try formatFeatureQuery("a=q,i=31,e=d,d=q,x=2,y=3,z=-7", &output));
    try std.testing.expectEqualStrings(",e=d,d=R,x=99,y=101", try formatFeatureQuery("a=q,i=31,e=d,d=R,x=99,y=101", &output));
    try std.testing.expectEqualStrings(",e=d,d=c", try formatFeatureQuery("a=q,i=31,e=d,d=c,p=7,x=2,y=3,z=-7", &output));
    try std.testing.expectEqualStrings("", try formatFeatureQuery("a=q,i=31,e=d,d=U", &output));
    try std.testing.expectEqualStrings("", try formatFeatureQuery("a=q,i=31,e=T,d=U", &output));
    try std.testing.expectEqualStrings(",e=d,d=F", try formatFeatureQuery("a=q,i=31,e=d,d=F", &output));
    try std.testing.expectEqualStrings(",e=d,d=Z,z=-3", try formatFeatureQuery("a=q,i=31,e=d,d=Z,z=-3", &output));
    try std.testing.expectEqualStrings(
        ",e=f,t=d,o=z,f=24,s=1,v=1,N=1,x=1,y=2,c=2,r=3,z=-40,X=1,Y=4278255615",
        try formatFeatureQuery("a=q,i=31,e=f,t=d,o=z,f=24,s=1,v=1,N=1,x=1,y=2,c=2,r=3,z=-40,X=1,Y=4278255615", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=f",
        try formatFeatureQuery("a=q,i=31,e=f,f=100,s=5000,v=5000,N=6,X=2,c=999,r=999", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=a,s=3,v=1,r=2,c=1,z=-1",
        try formatFeatureQuery("a=q,i=31,e=a,s=3,v=1,r=2,c=1,z=-1", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=a,v=1",
        try formatFeatureQuery("a=q,i=31,e=a,s=4,v=1,r=999,c=999", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=c,r=1,c=2,x=1,y=2,w=3,h=4,X=5,Y=6,C=1",
        try formatFeatureQuery("a=q,i=31,e=c,r=1,c=2,x=1,y=2,w=3,h=4,X=5,Y=6,C=1,U=1", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=c,C=1",
        try formatFeatureQuery("a=q,i=31,e=c,r=999,c=999,x=5000,y=5000,w=5000,h=5000,C=1", &output),
    );
    try std.testing.expectEqualStrings(
        ",e=p,p=2,C=1",
        try formatFeatureQuery("a=q,i=31,e=p,p=2,P=123,Q=456,H=-8,V=7,C=1", &output),
    );
    try std.testing.expectEqualStrings(",e=p", try formatFeatureQuery(
        "a=q,i=31,e=p,x=4096,y=4096,w=4097,h=4097,X=4096,Y=4096,c=65536,r=65536",
        &output,
    ));
    try std.testing.expect(parseCommand("a=p,i=31,P=123") != null);
    try std.testing.expect(parseCommand("a=T,i=31,P=123") == null);
    try std.testing.expect(parseCommand("a=q,i=31,e=p,P=4294967296") == null);
    try std.testing.expect(parseCommand("a=q,i=31,e=p,H=-2147483649") == null);
    try std.testing.expectEqualStrings(",e=T,p=2,x=1,w=2,U=1", try formatFeatureQuery("a=q,i=31,e=T,p=2,x=1,w=2,U=1", &output));
    try std.testing.expectEqualStrings(",e=T,f=8", try formatFeatureQuery("a=q,i=31,e=T,f=8,t=f,N=6", &output));
    try std.testing.expectEqualStrings("", try formatFeatureQuery("a=q,i=31,e=Z", &output));
    var tiny: [3]u8 = undefined;
    try std.testing.expectError(error.ReplyLimit, formatFeatureQuery("a=q,i=31,e=T", &tiny));
    try std.testing.expect(parseCommand("a=q,i=31,e=TT") == null);
    try std.testing.expect(parseCommand("a=q,i=31,e=3") == null);
    try std.testing.expect(parseCommand("a=q,i=31,e=T,e=t") == null);

    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const generation = plane.generation();
    const selected = try plane.command("a=q,i=31,e=T,U=1,C=1", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(@as(?Failure, null), selected.failure);
    try std.testing.expectEqualStrings("a=q,i=31,e=T,U=1,C=1", selected.feature_query.?);
    try std.testing.expectEqual(@as(?u32, 31), selected.response_id);
    try std.testing.expect(!selected.changed);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);

    // An e key on a mutating action is not a license to execute that action.
    const invalid = try plane.command("a=T,i=31,e=T,s=1,v=1;AQIDBA==", .primary, 0, 0, 0, 1, 1);
    try std.testing.expectEqual(Failure.invalid, invalid.failure.?);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);
}

test "Kitty usage hints are bounded advisory no-op metadata" {
    const parsed = parseCommand("a=t,f=32,s=1,v=1,i=80,N=1,q=2;/wAA/w==") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 1), parsed.usage_hints);
    const future = parseCommand("a=t,f=32,s=1,v=1,i=80,N=4294967295,q=2;/wAA/w==") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(std.math.maxInt(u32), future.usage_hints);
    try std.testing.expect(parseCommand("a=t,f=32,s=1,v=1,i=80,N=4294967296,q=2;/wAA/w==") == null);
    try std.testing.expect(parseCommand("a=t,f=32,s=1,v=1,i=80,N=1,N=1,q=2;/wAA/w==") == null);

    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=80,N=1,C=1,q=2;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
    try std.testing.expectEqual(@as(u16, 1), plane.placement_count);

    const frame = try plane.command(
        "a=f,f=32,i=80,s=1,v=1,r=2,z=50,N=1,C=1,q=2;AAD//w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(frame.changed);
    try std.testing.expect(!frame.visual_changed);
    try std.testing.expectEqual(@as(?u32, 2), frame.response_frame);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 255, 255 },
        plane.frameByNumber(plane.image(0).?.id, 2).?.pixels,
    );
}

// =============================================================================
// Allocation and capacity proofs
// =============================================================================

test "static image allocation failure leaves the plane reusable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, frameAllocationFailure, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, indexedAllocationFailure, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, indexedAllocationFailure, .{true});
}

fn indexedAllocationFailure(allocator: std.mem.Allocator, starts_indexed: bool) !void {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    const baseline: []const u8 = if (starts_indexed)
        "a=T,f=16,s=1,v=1,i=72,p=3,C=1,q=2;AoA="
    else
        "a=T,f=32,s=1,v=1,i=72,p=3,C=1,q=2;AQIDBA==";
    try std.testing.expect((try plane.command(baseline, .primary, 0, 0, 0, 1, 1)).changed);
    const initial_generation = plane.generation();
    const initial_content = plane.content_generation;
    const image_id = plane.image(0).?.id;
    const placement = plane.placement(0).?;
    const old_bytes = plane.storage_bytes;
    const prior: [4]u8 = plane.image(0).?.pixels[0..4].*;
    // Inject each possible allocation failure only into replacement, not
    // the established old image. Cleanup must be symmetric for RGBA and
    // indexed index+alpha source ownership.
    plane.allocator = allocator;
    defer plane.allocator = std.testing.allocator;
    const replacement: []const u8 = if (starts_indexed)
        "a=T,f=32,s=1,v=1,i=72,p=3,C=1,q=2;BQYHCA=="
    else
        "a=T,f=16,s=1,v=1,i=72,p=3,C=1,q=2;AoA=";
    const result = plane.command(replacement, .primary, 0, 0, 0, 1, 1) catch |err| {
        try std.testing.expectEqual(initial_generation, plane.generation());
        try std.testing.expectEqual(initial_content, plane.content_generation);
        try std.testing.expectEqual(old_bytes, plane.storage_bytes);
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqual(@as(u16, 1), plane.placement_count);
        try std.testing.expectEqual(image_id, plane.image(0).?.id);
        try std.testing.expectEqualDeep(placement, plane.placement(0).?);
        try std.testing.expectEqualSlices(u8, &prior, plane.image(0).?.pixels);
        return err;
    };
    try std.testing.expect(result.changed and result.failure == null);
    try std.testing.expectEqual(image_id, plane.image(0).?.id);
    try std.testing.expectEqual(placement.identity, plane.placement(0).?.identity);
    try std.testing.expectEqual(if (starts_indexed) @as(usize, 4) else @as(usize, 6), plane.storage_bytes);
}

test "Kitty frame capacity rejects the next frame without retained mutation" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=70,q=2;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    var number: usize = 2;
    while (number < max_frames + 2) : (number += 1) {
        var command_bytes: [80]u8 = undefined;
        const command_value = try std.fmt.bufPrint(
            &command_bytes,
            "a=f,f=32,s=1,v=1,i=70,r={d},q=2;BQYHCA==",
            .{number},
        );
        try std.testing.expect((try plane.command(
            command_value,
            .primary,
            0,
            0,
            0,
            1,
            1,
        )).changed);
    }
    const generation = plane.generation();
    const bytes = plane.storage_bytes;
    const rejected = try plane.command(
        "a=f,f=32,s=1,v=1,i=70,r=258,q=2;CQoLDA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expectEqual(Failure.quota, rejected.failure.?);
    try std.testing.expectEqual(@as(u16, max_frames), plane.frame_count);
    try std.testing.expectEqual(generation, plane.generation());
    try std.testing.expectEqual(bytes, plane.storage_bytes);
}

fn frameAllocationFailure(allocator: std.mem.Allocator) !void {
    var plane = Plane.init(allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const before = plane.storage_bytes;
    try std.testing.expect((try plane.command(
        "a=f,f=32,i=1,s=1,v=1;BQYHCA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(before + 4, plane.storage_bytes);
    const with_frame = plane.storage_bytes;
    try std.testing.expect((try plane.command(
        "a=f,f=32,i=1,s=1,v=1,r=1,C=1;CQoLDA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(with_frame, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 9, 10, 11, 12 }, plane.images[0].pixels);
    try std.testing.expect((try plane.command(
        "a=c,i=1,r=2,c=1,C=1,q=2",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(with_frame, plane.storage_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, plane.images[0].pixels);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var plane = Plane.init(allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=T,f=32,s=1,v=1,i=1;AQIDBA==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
}

test "Kitty zlib checksum failures preserve images and frames before valid recovery" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command(
        "a=t,f=32,s=1,v=1,i=81,q=2;/wAA/w==",
        .primary,
        0,
        0,
        0,
        1,
        1,
    )).changed);
    const identity = plane.image(0).?.id;
    const generation = plane.generation();
    const valid = "eJxjYPj/HwADAQH/";
    var compressed: [12]u8 = undefined;
    try std.base64.standard.Decoder.decode(&compressed, valid);
    for (1..5) |offset| {
        compressed[compressed.len - offset] ^= 1;
        defer compressed[compressed.len - offset] ^= 1;
        var encoded: [16]u8 = undefined;
        const payload = std.base64.standard.Encoder.encode(&encoded, &compressed);
        for ([_][]const u8{
            "a=t,f=32,s=1,v=1,i=82,o=z,q=2;",
            "a=t,f=32,s=1,v=1,i=81,o=z,q=2;",
            "a=f,f=32,s=1,v=1,i=81,r=2,o=z,C=1,q=2;",
        }) |prefix| {
            var command: [128]u8 = undefined;
            const text = try std.fmt.bufPrint(&command, "{s}{s}", .{ prefix, payload });
            const rejected = try plane.command(text, .primary, 0, 0, 0, 1, 1);
            try std.testing.expectEqual(Failure.invalid, rejected.failure.?);
            try std.testing.expect(!rejected.changed);
            try std.testing.expectEqual(generation, plane.generation());
            try std.testing.expectEqual(@as(u16, 1), plane.image_count);
            try std.testing.expectEqual(identity, plane.image(0).?.id);
            try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, plane.image(0).?.pixels);
            try std.testing.expect(plane.frameByNumber(identity, 2) == null);
        }
    }
    const frame = try plane.command(
        "a=f,f=32,s=1,v=1,i=81,r=2,o=z,C=1,q=2;" ++ valid,
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(frame.changed);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, plane.frameByNumber(identity, 2).?.pixels);
    const replacement = try plane.command(
        "a=t,f=32,s=1,v=1,i=81,o=z,q=2;" ++ valid,
        .primary,
        0,
        0,
        0,
        1,
        1,
    );
    try std.testing.expect(replacement.changed);
    try std.testing.expectEqual(@as(u16, 1), plane.image_count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, plane.image(0).?.pixels);
}

test "Kitty direct chunks enforce encoded bounds and nonfinal quantum before image admission" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    var packet: [max_command_bytes]u8 = undefined;
    const payload: [4100]u8 = @splat('A');
    const large = try std.fmt.bufPrint(&packet, "a=t,f=24,i=7,s=1025,v=1;{s}", .{&payload});
    const rejected = try plane.command(large, .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(@as(?Failure, .invalid), rejected.failure);
    try std.testing.expectEqual(@as(?u32, 7), rejected.response_id);
    try std.testing.expect(plane.loading == null);
    try std.testing.expectEqual(@as(u16, 0), plane.image_count);

    const first = try std.fmt.bufPrint(&packet, "a=T,f=24,i=7,s=1025,v=1,C=1,m=1;{s}", .{payload[0..4096]});
    const started = try plane.command(first, .primary, 0, 0, 0, 8, 16);
    try std.testing.expectEqual(@as(?Failure, null), started.failure);
    try std.testing.expect(!started.changed and plane.loading != null);
    try std.testing.expectEqual(@as(u16, 0), plane.placement_count);
    const last = try plane.command("m=0;AQID", .primary, 0, 2, 3, 8, 16);
    try std.testing.expect(last.changed);
    try std.testing.expectEqual(@as(u64, 2), plane.placements[0].row);
    try std.testing.expectEqual(@as(u16, 3), plane.placements[0].col);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, plane.image(0).?.pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, plane.image(0).?.pixels[4096..4100]);
    const generation = plane.generation();
    for ([_][]const u8{ "AQ", "AQI" }) |partial| {
        const bad = try std.fmt.bufPrint(&packet, "a=t,i=7,s=1,v=1,m=1;{s}", .{partial});
        const result = try plane.command(bad, .primary, 0, 0, 0, 8, 16);
        try std.testing.expectEqual(@as(?Failure, .invalid), result.failure);
        try std.testing.expectEqual(@as(?u32, 7), result.response_id);
        try std.testing.expect(plane.loading == null);
        try std.testing.expectEqual(generation, plane.generation());
    }
}

test "Kitty continuation admits only continuation metadata and retains rejection identity" {
    var plane = Plane.init(std.testing.allocator);
    defer plane.deinit();
    try std.testing.expect((try plane.command("a=t,i=7,s=1,v=1;AQIDBA==", .primary, 0, 0, 0, 8, 16)).changed);
    const generation = plane.generation();
    for ([_][]const u8{ "f=32", "s=0", "p=0", "C=0", "U=0", "N=0", "t=d", "a=t", "z=0", "S=0" }) |extra| {
        const first = try plane.command("a=t,I=44,s=1,v=1,m=1;AQID", .primary, 0, 0, 0, 8, 16);
        try std.testing.expect(!first.changed and plane.loading != null);
        const id = plane.loading.?.id;
        var bytes: [128]u8 = undefined;
        const body = try std.fmt.bufPrint(&bytes, "m=0,{s};BA==", .{extra});
        const rejected = try plane.command(body, .primary, 0, 0, 0, 8, 16);
        try std.testing.expectEqual(@as(?Failure, .invalid), rejected.failure);
        try std.testing.expectEqual(@as(?u32, id), rejected.response_id);
        try std.testing.expectEqual(@as(?u32, 44), rejected.response_number);
        try std.testing.expect(plane.loading == null);
        try std.testing.expectEqual(generation, plane.generation());
        try std.testing.expectEqual(@as(u16, 1), plane.image_count);
        try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, plane.image(0).?.pixels);
    }
}
