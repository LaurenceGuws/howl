//! One shared native text lane: borrowed external serialization or owned claims.
const std = @import("std");
const text = @import("howl_text");
const glyph_cache = @import("glyph_cache");
const commands = @import("frame");
const FontFaces = glyph_cache.FontFaces;
const ShapeCacheConfig = glyph_cache.ShapeCacheConfig;
const ShapeCacheUsage = glyph_cache.ShapeCacheUsage;
const ShapeCacheInitError = glyph_cache.ShapeCacheInitError;
const ShapeCache = glyph_cache.ShapeCache;
const Metrics = text.Metrics;
/// Process render knowledge shared by externally serialized terminal renderers.
///
/// FontFaces remain caller-owned and must
/// outlive the Store. The Store owns retained shaping knowledge and reusable
/// shape/raster scratch. Callers must serialize mutable Store use.
// zig-audit: acknowledge opaque_type
// reason: Store intentionally hides the allocator-owned StoreImpl layout so shared shaping state remains bounded and externally serialized.
pub const Store = opaque {};

/// Bounds reusable process render knowledge for one exact font/raster lane.
pub const StoreConfig = struct {
    shape_cache: ShapeCacheConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
};

/// Reports retained shared process-render knowledge without terminal-local state.
pub const StoreUsage = struct {
    shape: ShapeCacheUsage,
};

/// Reports allocation, shaping-cache construction, configuration, or font-family failure during Store initialization.
pub const StoreInitError = std.mem.Allocator.Error || ShapeCacheInitError || error{
    InvalidConfig,
    InvalidFontFaces,
};

const StoreImpl = struct {
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: StoreConfig,
    shape_cache: *ShapeCache,
    clusters: []u32,
    shaped: []text.Glyph,
    raster: []u8,
};

fn validateStoreConfig(config: StoreConfig) error{InvalidConfig}!void {
    if (config.shaped_capacity == 0 or config.raster_bytes == 0 or
        config.shape_cache.entry_capacity == 0 or
        config.shape_cache.scalar_capacity == 0 or
        config.shape_cache.glyph_capacity == 0 or
        config.shape_cache.max_sequence_scalars == 0)
        return error.InvalidConfig;
}

/// Allocates one process render lane for one exact caller-owned font recipe.
/// Mutable Store operations are externally serialized.
pub fn initStore(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: StoreConfig,
) StoreInitError!*Store {
    try validateStoreConfig(config);
    if (!fonts.terminalMetricsCompatible()) return error.InvalidFontFaces;

    const impl = try allocator.create(StoreImpl);
    errdefer allocator.destroy(impl);
    const shape_cache = try glyph_cache.initShapeCache(allocator, fonts, config.shape_cache);
    errdefer glyph_cache.deinitShapeCache(shape_cache);
    const clusters = try allocator.alloc(u32, @intCast(config.shape_cache.max_sequence_scalars));
    errdefer allocator.free(clusters);
    const shaped = try allocator.alloc(text.Glyph, config.shaped_capacity);
    errdefer allocator.free(shaped);
    const raster = try allocator.alloc(u8, config.raster_bytes);
    errdefer allocator.free(raster);
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .config = config,
        .shape_cache = shape_cache,
        .clusters = clusters,
        .shaped = shaped,
        .raster = raster,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Store is the opaque handle for this exact allocator-owned StoreImpl allocation and preserves its address.
    return @ptrCast(impl);
}

/// Releases one process render lane. No Renderer may still borrow it.
pub fn deinitStore(owner: *Store) void {
    const impl = storeImpl(owner);
    const allocator = impl.allocator;
    const shape_cache = impl.shape_cache;
    const clusters = impl.clusters;
    const shaped = impl.shaped;
    const raster = impl.raster;
    impl.* = undefined;
    allocator.free(raster);
    allocator.free(shaped);
    allocator.free(clusters);
    glyph_cache.deinitShapeCache(shape_cache);
    allocator.destroy(impl);
}

/// Returns exact metrics for this Store's fixed font/raster lane.
pub fn storeMetrics(owner: *const Store) Metrics {
    return constStoreImpl(owner).fonts.metrics();
}

/// Reports retained process-shared cache usage.
pub fn storeUsage(owner: *const Store) StoreUsage {
    return .{ .shape = glyph_cache.shapeCacheUsage(constStoreImpl(owner).shape_cache) };
}

/// Forgets shared shaping knowledge without invalidating terminal-local atlases.
pub fn resetStore(owner: *Store) void {
    glyph_cache.resetShapeCache(storeImpl(owner).shape_cache);
}

fn storeImpl(content: *Store) *StoreImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every mutable Store originates from a StoreImpl allocation in initStore at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating StoreImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

fn constStoreImpl(content: *const Store) *const StoreImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every borrowed Store originates from a StoreImpl allocation in initStore at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating StoreImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

/// Selects one owned font source for VT presentation construction.
pub const FontConfig = union(enum) {
    path: text.Config,
    memory: text.MemoryConfig,
};

/// Optional host discovery, owned for the exact lifetime of a presentation store.
/// Creation may decline availability; existing configured fonts still render.
/// Only cache misses call find, while the owning native text lane is claimed.
pub const FallbackFactory = struct {
    create: *const fn (std.mem.Allocator) ?glyph_cache.FallbackContext,
    find: *const fn (glyph_cache.FallbackContext, glyph_cache.FontVariant, []const u32) ?text.FallbackFile,
    destroy: *const fn (glyph_cache.FallbackContext) void,
};

/// Supplies one required regular font and optional style variants.
pub const FontFamilyConfig = struct {
    regular: FontConfig,
    italic: ?FontConfig = null,
    bold: ?FontConfig = null,
    bold_italic: ?FontConfig = null,
    fallback_factory: ?FallbackFactory = null,
};

fn initFont(allocator: std.mem.Allocator, config: FontConfig) text.InitError!*text.FontSet {
    return switch (config) {
        .path => |value| text.FontSet.init(allocator, value),
        .memory => |value| text.FontSet.initMemory(allocator, value),
    };
}

const OwnedFonts = struct {
    regular: *text.FontSet,
    italic: ?*text.FontSet,
    bold: ?*text.FontSet,
    bold_italic: ?*text.FontSet,

    fn init(allocator: std.mem.Allocator, config: FontFamilyConfig) text.InitError!OwnedFonts {
        const regular = try initFont(allocator, config.regular);
        errdefer regular.deinit();
        const italic = if (config.italic) |value| try initFont(allocator, value) else null;
        errdefer if (italic) |value| value.deinit();
        const bold = if (config.bold) |value| try initFont(allocator, value) else null;
        errdefer if (bold) |value| value.deinit();
        const bold_italic = if (config.bold_italic) |value| try initFont(allocator, value) else null;
        errdefer if (bold_italic) |value| value.deinit();
        return .{
            .regular = regular,
            .italic = italic,
            .bold = bold,
            .bold_italic = bold_italic,
        };
    }

    fn faces(self: *const OwnedFonts, fallback_lookup: ?glyph_cache.FallbackLookup) FontFaces {
        return .{
            .regular = self.regular,
            .italic = self.italic,
            .bold = self.bold,
            .bold_italic = self.bold_italic,
            .fallback_lookup = fallback_lookup,
        };
    }

    fn deinit(self: *OwnedFonts) void {
        if (self.bold_italic) |value| value.deinit();
        if (self.bold) |value| value.deinit();
        if (self.italic) |value| value.deinit();
        self.regular.deinit();
        self.* = undefined;
    }
};

/// Owning native font family and the same borrowed Store lane, with bounded references.
/// Its supplied Io must outlive every retained borrower, including after caller release.
// zig-audit: acknowledge opaque_type
// reason: Owning references and native-face claims must not expose mutable fonts or scratch layout.
pub const PresentationStore = opaque {};

/// Retains one live owning reference; the maximum is 1024.
pub fn retain(self: *PresentationStore) error{PresentationStoreLimit}!void {
    const value = ownerImpl(self);
    var before = value.references.load(.monotonic);
    while (true) {
        if (before >= 1024) return error.PresentationStoreLimit;
        before = value.references.cmpxchgWeak(before, before + 1, .monotonic, .monotonic) orelse return;
    }
}
/// Releases ownership after every local atlas borrowing its fonts is destroyed.
pub fn release(self: *PresentationStore) void {
    const value = ownerImpl(self);
    const before = value.references.fetchSub(1, .acq_rel);
    std.debug.assert(before != 0);
    if (before != 1) return;
    deinitStore(value.store);
    value.fonts.deinit();
    if (value.fallback_context) |context| value.fallback_destroy.?(context);
    value.allocator.destroy(value);
}
/// Waits for exclusive native-face use; keep this outside transfer-critical paths.
pub fn claim(self: *PresentationStore) void {
    const value = ownerImpl(self);
    value.mutex.lockUncancelable(value.io);
}
/// Attempts exclusive native-face use without waiting.
pub fn tryClaim(self: *PresentationStore) bool {
    return ownerImpl(self).mutex.tryLock();
}
/// Ends the caller's exclusive native-face claim.
pub fn unclaim(self: *PresentationStore) void {
    const value = ownerImpl(self);
    value.mutex.unlock(value.io);
}
/// Borrows the exact lane; mutable use requires this owner's claim.
pub fn borrowStore(self: *PresentationStore) *Store {
    return ownerImpl(self).store;
}

const OwnerImpl = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    fonts: OwnedFonts,
    store: *Store,
    fallback_context: ?glyph_cache.FallbackContext = null,
    fallback_destroy: ?*const fn (glyph_cache.FallbackContext) void = null,
    mutex: std.Io.Mutex = .init,
    references: std.atomic.Value(u32) = .init(1),
};
fn ownerImpl(owner: *PresentationStore) *OwnerImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: This handle denotes the exact allocator-owned OwnerImpl address.
    // zig-audit: acknowledge align_cast
    // reason: The originating OwnerImpl allocation guarantees this alignment.
    return @ptrCast(@alignCast(owner));
}
/// Reports owned-font, lane construction, or bounded retain admission failure.
pub const PresentationStoreInitError = text.InitError || StoreInitError || error{PresentationStoreLimit};
/// Copies a font recipe and creates one owning caller reference.
/// The supplied Io must outlive all retained borrowers, even after this reference is released.
pub fn initPresentationStore(allocator: std.mem.Allocator, io: std.Io, config: FontFamilyConfig, lane_config: StoreConfig) PresentationStoreInitError!*PresentationStore {
    const owner = try allocator.create(OwnerImpl);
    errdefer allocator.destroy(owner);
    const fallback_context = if (config.fallback_factory) |factory| factory.create(allocator) else null;
    errdefer if (fallback_context) |context| config.fallback_factory.?.destroy(context);
    var fonts = try OwnedFonts.init(allocator, config);
    errdefer fonts.deinit();
    const lookup: ?glyph_cache.FallbackLookup = if (fallback_context) |context| .{
        .context = context,
        .find = config.fallback_factory.?.find,
    } else null;
    const lane = try initStore(allocator, fonts.faces(lookup), lane_config);
    owner.* = .{
        .allocator = allocator,
        .io = io,
        .fonts = fonts,
        .store = lane,
        .fallback_context = fallback_context,
        .fallback_destroy = if (fallback_context != null) config.fallback_factory.?.destroy else null,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Opaque ownership preserves the exact allocator-owned OwnerImpl address.
    return @ptrCast(owner);
}
/// Releases the caller reference without invalidating remaining borrowers.
pub const releasePresentationStore = release;
/// Copies immutable regular metrics while the caller retains a live reference.
pub fn presentationStoreCellSize(owner: *PresentationStore) commands.Size {
    const metrics = storeMetrics(borrowStore(owner));
    return .{ .width = metrics.advance_width, .height = metrics.line_height };
}
/// Counts all live caller and terminal references for idle-owner collection.
pub fn presentationStoreReferences(owner: *PresentationStore) u32 {
    return ownerImpl(owner).references.load(.acquire);
}
/// Reads mutable cache usage under the owning native-face claim.
pub fn presentationStoreUsage(owner: *PresentationStore) StoreUsage {
    claim(owner);
    defer unclaim(owner);
    return storeUsage(borrowStore(owner));
}
/// Immutable lane capacity recipe; native faces remain hidden.
pub fn storeConfig(store: *const Store) StoreConfig {
    return constStoreImpl(store).config;
}
/// Scratch borrowed only under external serialization or an owning claim.
pub const Work = struct { shape_cache: *ShapeCache, clusters: []u32, shaped: []text.Glyph, raster: []u8 };
/// Borrows the lane's actual shared cache and scratch, never a private copy.
pub fn work(store: *Store) Work {
    const value = storeImpl(store);
    return .{ .shape_cache = value.shape_cache, .clusters = value.clusters, .shaped = value.shaped, .raster = value.raster };
}
/// Creates a terminal-local atlas from hidden lane fonts under caller serialization.
pub fn initAtlasFromStore(allocator: std.mem.Allocator, store: *Store, drawing: text.generated.BoxDrawingConfig, config: glyph_cache.AtlasConfig) glyph_cache.AtlasInitError!*glyph_cache.Atlas {
    return glyph_cache.initAtlas(allocator, constStoreImpl(store).fonts, drawing, config);
}
/// Test-only reference-cap injection; no production declaration can execute it.
pub fn setReferenceCountForTest(owner: *PresentationStore, count: u32) void {
    if (!@import("builtin").is_test) @compileError("reference injection is test-only");
    ownerImpl(owner).references.store(count, .monotonic);
}
/// Test-only observation of the existing mutex, without added synchronization state.
pub fn claimContendedForTest(owner: *PresentationStore) bool {
    if (!@import("builtin").is_test) @compileError("claim observation is test-only");
    return ownerImpl(owner).mutex.state.load(.acquire) == .contended;
}
