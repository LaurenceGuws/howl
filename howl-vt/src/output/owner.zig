//! Optional rendered VT owner: native rows become immutable row-local commands.
//! Plain VT does not import this module or allocate presentation state.
//! Bounded to 1..192 rows, 1..512 columns, history capacity bounded by u16, one selected view
//! and one held output. Unsupported visual properties fail flush after canonical
//! input has committed. This is not a PTY service owner.
const std = @import("std");
const vt = @import("howl_vt");
const text = @import("howl_text");
const cache = @import("glyph_cache");
const state = @import("output_state");
const support = @import("text_support");
const Impl = state.State(false);

/// Immutable borrowed commands/pixels, valid until release, including across
/// feed, resize, failed flush and font replacement under the synchronization
/// contract below. The borrow does not retain working font or canonical storage.
pub const Snapshot = state.Snapshot;
/// Owner-bound immutable borrow. Copies refer to one lease, not extra pins.
/// Canonical occurrence identity rejects stale copies even if an owner address
/// is reused after destruction; release still requires a live receiving owner.
pub const Lease = struct { snapshot: Snapshot, owner: *const Terminal, occurrence: u64, serial: u64 };
/// Caller-owned font variants; every supplied FontSet must remain alive until
/// successful replacement or owner destruction. Mutable FreeType/HarfBuzz faces
/// allow one exclusive caller: serialize the same borrowed FontSet across ALL
/// owners and other native-face users, including init, replacement, flush and
/// cache reset where they access it. Per-owner transfer locking alone is not
/// sufficient. Borrowed-font mode adds no shared lock or Store ownership.
/// Shared mode instead retains an owning PresentationStore and claims its work lane.
pub const FontFaces = cache.FontFaces;
/// Exact backend-independent final command/resource vocabulary.
pub const commands = @import("frame");
/// Private atlas capacity policy; font/cache ownership remains with this owner.
pub const AtlasConfig = cache.AtlasConfig;
/// Bounded output configuration. No eager warming or proof instrumentation.
pub const Config = struct {
    history_capacity: u16 = 0,
    cursor_stroke_pixels: u8 = 2,
    faces: ?FontFaces = null,
    box_drawing: text.generated.BoxDrawingConfig = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
    atlas: AtlasConfig = .{ .width = 64, .height = 16, .entry_capacity = 16, .growth = .{ .entry_limit = 256, .alpha_height_limit = 512, .color_height_limit = 16 } },
    raster_bytes: usize = 512 * 512,
    /// Zero derives a ceiling from shaping capacities and font width; storage grows on demand.
    command_limit: usize = 0,

    fn internal(self: Config) state.Config {
        return .{ .history_capacity = self.history_capacity, .cursor_stroke_pixels = self.cursor_stroke_pixels, .faces = self.faces, .box_drawing = self.box_drawing, .atlas = self.atlas, .raster_bytes = self.raster_bytes, .command_limit = self.command_limit };
    }
};
/// Owned family and shared work lane for direct VT output.
pub const PresentationStore = support.PresentationStore;
/// Owned family face specification.
pub const FontConfig = support.FontConfig;
/// Owned regular and optional style faces.
pub const FontFamilyConfig = support.FontFamilyConfig;
/// Shared shaping and raster scratch bounds.
pub const StoreConfig = support.StoreConfig;
/// Owned store construction errors.
pub const PresentationStoreInitError = support.PresentationStoreInitError;
/// Creates one refcounted family/work lane; its Io must outlive every retained reference.
pub const initPresentationStore = support.initPresentationStore;
/// Releases the caller's owning reference.
pub const releasePresentationStore = support.releasePresentationStore;
/// Reads immutable regular metrics without entering the work lane.
pub const presentationStoreCellSize = support.presentationStoreCellSize;
/// Reports retained ownership references.
pub const presentationStoreReferences = support.presentationStoreReferences;
/// Reads shared cache usage under the store claim.
pub const presentationStoreUsage = support.presentationStoreUsage;
/// Local output policy only; font and scratch configuration belong to the shared store.
pub const SharedConfig = state.SharedConfig;
/// Shared setup allocation and ownership admission errors.
pub const SharedInitError = Impl.SharedInitError;
/// Shared replacement preserves accepted output on failure.
pub const SharedReplaceError = Impl.SharedReplaceError;
/// Dimensions of the last successfully accepted output, not pending native state.
pub const AcceptedMetrics = struct { rows: u16, columns: u16, cell_width: u16, cell_height: u16 };

/// Allocation, canonical initialization and private working-cache setup failures.
pub const InitError = Impl.InitError;
/// Canonical whole-slice feed failures.
pub const FeedError = vt.Terminal.FeedError;
/// Bounded canonical resize failures.
pub const ResizeError = Impl.ResizeError;
/// Invalid native reply prefix acknowledgment.
pub const ReplyError = vt.Terminal.ReplyConsumeError;
/// Working atlas generation exhaustion.
pub const ResetError = error{GenerationOverflow};
/// Transactional working-font replacement failures.
pub const ReplaceError = Impl.ReplaceError;
/// Supported output preparation errors, excluding injected proof faults.
pub const FlushError = Impl.FlushError;
/// Output lease admission and monotonic serial exhaustion.
pub const HoldError = Impl.HoldError || error{LeaseSequenceOverflow};

/// Owns canonical VT, working text resources and bounded immutable output storage.
/// Mutation is available only through these operations, never a raw VT pointer.
/// One producer exclusively serializes feed, resize, view selection, reply
/// consumption, working cache resets and font replacement. These operations touch
/// canonical/working state, not accepted output or pin slots, and may proceed
/// while the consumer holds the external transfer mutex.
/// Shared initialization/replacement may wait for the family claim and must occur
/// outside the transfer mutex. Shared flush only tries the claim when rows need work.
/// Producer flush and consumer hold/release/acceptedMetrics must use that same
/// external transfer mutex. Skipping a busy flush never blocks canonical feed.
/// Observation access remains producer-serialized, not concurrent consumer access.
/// Hold/release read only the canonical occurrence identity, immutable for the
/// owner's lifetime, alongside transfer-protected accepted/pin state.
/// A consumer may draw immutable snapshot data outside the mutex while its lease
/// stays pinned. Release waits for drawing to finish; abandoning a draw means
/// releasing its lease, not assuming upload acknowledgment completed it.
/// Teardown requires a quiescent producer and consumer, with no outstanding lease.
// zig-audit: acknowledge opaque_type
// reason: The public handle must prevent mutation of canonical state and immutable output pins.
pub const Terminal = opaque {
    fn impl(self: *Terminal) *Impl {
        // zig-audit: acknowledge ptr_cast
        // reason: Terminal denotes this exact stable allocator-owned State(false) allocation.
        // zig-audit: acknowledge align_cast
        // reason: State allocation alignment is preserved by the opaque handle.
        return @ptrCast(@alignCast(self));
    }
    fn read(self: *const Terminal) *const Impl {
        // zig-audit: acknowledge ptr_cast
        // reason: Terminal denotes this exact State(false) allocation without dropping const.
        // zig-audit: acknowledge align_cast
        // reason: The originating State allocation guarantees the recovered alignment.
        return @ptrCast(@alignCast(self));
    }

    /// Initializes a 24x80 terminal. Font data is borrowed, never destroyed by this owner.
    pub fn init(allocator: std.mem.Allocator, font: *text.FontSet) InitError!*Terminal {
        return initConfig(allocator, font, .{});
    }
    /// Initializes bounded history and private output resources transactionally.
    pub fn initConfig(allocator: std.mem.Allocator, font: *text.FontSet, config: Config) InitError!*Terminal {
        const value = try Impl.initConfig(allocator, font, config.internal());
        // zig-audit: acknowledge ptr_cast
        // reason: The opaque handle preserves the stable allocator-owned State address.
        return @ptrCast(value);
    }
    /// Retains an owning shared presentation lane and allocates a private atlas.
    /// Setup may wait for the shared lane: call outside the output transfer lock.
    pub fn initShared(allocator: std.mem.Allocator, store: *PresentationStore, config: SharedConfig) SharedInitError!*Terminal {
        const value = try Impl.initShared(allocator, store, config);
        // zig-audit: acknowledge ptr_cast
        // reason: Terminal denotes this exact stable State(false) allocation.
        return @ptrCast(value);
    }
    /// Stages a new retained store and local atlas. Success drops this owner's old
    /// reference only after its old atlas is destroyed; held output needs neither.
    /// Producer-only setup may wait: never call while holding the output transfer lock.
    pub fn replaceWorkingShared(self: *Terminal, store: *PresentationStore, config: SharedConfig) SharedReplaceError!void {
        try self.impl().replaceWorkingShared(store, config);
    }
    /// Requires release of the outstanding output first; fonts remain caller-owned.
    pub fn deinit(self: *Terminal) error{LeaseBusy}!void {
        if (self.impl().leased) return error.LeaseBusy;
        self.impl().deinit();
    }
    /// Whole-slice native feed, not Instance's consumed-tail service protocol.
    /// Errors may commit a prefix; output failure never rolls canonical VT back.
    pub fn feed(self: *Terminal, bytes: []const u8) FeedError!void {
        try self.impl().feed(bytes);
    }
    /// Commits native resize before subsequent fallible output preparation.
    pub fn resize(self: *Terminal, rows: u16, columns: u16) ResizeError!void {
        try self.impl().resize(rows, columns);
    }
    /// Selects a numeric history offset; user-view anchoring belongs to the caller.
    pub fn selectHistoryOffset(self: *Terminal, offset: u32) void {
        self.impl().selectHistoryOffset(offset);
    }
    /// Borrows canonical replies under producer serialization. The slice expires
    /// at the next feed, reply consumption, resize or owner destruction.
    pub fn replyBytes(self: *const Terminal) []const u8 {
        return self.read().vt.replyBytes();
    }
    /// Consumes acknowledged native replies without changing accepted output.
    pub fn consumeReplyBytes(self: *Terminal, count: usize) ReplyError!void {
        try self.impl().consumeReplyBytes(count);
    }
    /// Resets only this owner's working glyph atlas; held output stays immutable.
    pub fn resetAtlas(self: *Terminal) ResetError!void {
        try self.impl().resetAtlas();
    }
    /// Resets private shaping; shared mode rejects with SharedStore and changes nothing.
    pub fn resetShapes(self: *Terminal) error{SharedStore}!void {
        try self.impl().resetShapes();
    }
    /// On success old fonts may retire if no other borrower remains; on failure
    /// old fonts remain required and new fonts may retire. Held pixels need neither.
    /// Success updates canonical cell pixels immediately; accepted output metrics
    /// remain unchanged until flush succeeds. Setup failure changes neither.
    pub fn replaceWorkingBorrowed(self: *Terminal, font: *text.FontSet, config: Config) ReplaceError!void {
        try self.impl().replaceWorkingBorrowed(font, config.internal());
    }
    /// Accepts an entire output transaction or preserves the previous accepted
    /// commands/resources. Unsupported scenes recover after supported native input.
    pub fn flush(self: *Terminal) FlushError!void {
        try self.impl().flush();
    }
    /// Acquires the single immutable lease. Release before another hold or deinit.
    pub fn hold(self: *Terminal) HoldError!Lease {
        const value = self.impl();
        if (value.lease_serial == std.math.maxInt(u64)) return error.LeaseSequenceOverflow;
        const snapshot = try self.impl().hold();
        value.lease_serial += 1;
        return .{ .snapshot = snapshot, .owner = self, .occurrence = value.vt.observation().occurrenceIdentity(), .serial = value.lease_serial };
    }
    /// Ends the outstanding borrow; all snapshot slices become invalid afterward.
    pub fn release(self: *Terminal, lease: Lease) error{InvalidLease}!void {
        if (lease.owner != self or lease.occurrence != self.observation().occurrenceIdentity() or !self.impl().leased or lease.serial != self.impl().lease_serial)
            return error.InvalidLease;
        self.impl().release();
    }
    /// Borrows native opaque read-only observation; not an immutable snapshot.
    /// Its views expire at the next canonical mutation or owner destruction.
    /// Access it only under producer serialization, including the returned views.
    pub fn observation(self: *const Terminal) *const vt.Terminal.Observation {
        return self.read().vt.observation();
    }
    /// Returns null until the first successful flush. Font replacement changes
    /// working metrics first; these accepted metrics change only at successful flush.
    pub fn acceptedMetrics(self: *const Terminal) ?AcceptedMetrics {
        const value = self.read();
        if (!value.ready) return null;
        return .{ .rows = value.accepted_rows, .columns = value.accepted_cols, .cell_width = value.cell_width, .cell_height = value.cell_height };
    }
};
