//! Owns bounded backend-neutral drawing facts and exact surface clipping.

const std = @import("std");
const validation = @import("canvas_validation");

/// Reports invalid identities, resource views, geometry, aliases, arithmetic,
/// or capacity before any caller output byte changes.
pub const Error = error{
    InvalidSurface,
    InvalidRectangle,
    InvalidIdentity,
    InvalidGeneration,
    FormatMismatch,
    ExtentMismatch,
    ArithmeticOverflow,
    AliasedStorage,
    InsufficientCommands,
};

const ResourceFactError = error{
    InvalidIdentity,
    InvalidGeneration,
    InvalidRevision,
    InvalidPixels,
    FormatMismatch,
    ExtentMismatch,
    ArithmeticOverflow,
};

/// Defines explicit RGBA channels without prescribing a GPU byte layout.
pub const Color = packed struct(u32) {
    /// Red channel.
    r: u8,
    /// Green channel.
    g: u8,
    /// Blue channel.
    b: u8,
    /// Alpha channel.
    a: u8,
};

/// Names a nonzero pixel extent.
pub const Size = struct {
    /// Pixel width.
    width: u16,
    /// Pixel height.
    height: u16,
};

/// Names a nonzero signed rectangle which may extend outside its clip.
pub const Rect = struct {
    /// Signed left coordinate.
    x: i32,
    /// Signed top coordinate.
    y: i32,
    /// Nonzero width.
    width: u16,
    /// Nonzero height.
    height: u16,
};

/// Selects one nonzero source-pixel rectangle.
pub const SourceRect = struct {
    /// First source column.
    x: u16,
    /// First source row.
    y: u16,
    /// Selected source width.
    width: u16,
    /// Selected source height.
    height: u16,
};

/// Identifies one resource in the disjoint local or shared namespace.
///
/// The high bit selects shared ownership. The remaining 63 bits contain one
/// nonzero identity. Callers construct values through `local` or `shared`;
/// accepting boundaries validate the source/namespace relationship again.
pub const ResourceId = enum(u64) {
    _,

    const shared_bit: u64 = @as(u64, 1) << 63;
    /// Largest identity admitted independently in either namespace.
    pub const max_identity: u64 = shared_bit - 1;
    /// Reports malformed zero or exhausted identity input.
    pub const InitError = error{InvalidIdentity};

    /// Constructs one source-local identity.
    pub fn local(identity_value: u64) InitError!ResourceId {
        if (identity_value == 0 or identity_value > max_identity)
            return error.InvalidIdentity;
        return @fromBackingInt(@intCast(identity_value));
    }

    /// Constructs one source-independent shared identity.
    pub fn shared(identity_value: u64) InitError!ResourceId {
        if (identity_value == 0 or identity_value > max_identity)
            return error.InvalidIdentity;
        return @fromBackingInt(@intCast(identity_value | shared_bit));
    }

    /// Validates and preserves one already encoded namespace identity.
    pub fn fromEncoded(encoded: u64) InitError!ResourceId {
        const result: ResourceId = @fromBackingInt(@intCast(encoded));
        try result.validate();
        return result;
    }

    /// Validates the nonzero encoded identity without changing it.
    pub fn validate(self: ResourceId) InitError!void {
        if (@backingInt(self) & max_identity == 0)
            return error.InvalidIdentity;
    }

    /// Reports whether this value selects shared ownership.
    pub fn isShared(self: ResourceId) bool {
        return @backingInt(self) & shared_bit != 0;
    }

    /// Returns the nonzero identity without its namespace bit.
    pub fn identity(self: ResourceId) InitError!u64 {
        const value = @backingInt(self) & max_identity;
        try self.validate();
        return value;
    }
};

/// Identifies one Composer-issued collision-free source scope.
pub const SourceId = enum(u64) { _ };

/// Orders replacement content for one logical resource.
pub const ResourceGeneration = enum(u64) { _ };

/// Orders complete accepted updates from one producer source.
pub const ProducerRevision = enum(u64) { _ };

/// Orders complete visible frames derived by one Composer.
pub const FrameRevision = enum(u64) { _ };

/// Selects the exact stored pixel representation.
pub const ResourceFormat = enum(u8) {
    alpha8,
    rgba8,
};

/// Refers to one producer resource generation in either namespace.
pub const ResourceRef = struct {
    /// Identifies the namespace and exact logical resource.
    resource: ResourceId,
    /// Identifies the exact resource content generation.
    generation: ResourceGeneration,
};

/// Refers to one exact resource generation in a derived frame.
pub const FrameResourceRef = struct {
    /// Supplies the collision-free local source, or zero for shared.
    source: SourceId,
    /// Identifies the disjoint local or shared resource.
    resource: ResourceId,
    /// Identifies the exact resource content generation.
    generation: ResourceGeneration,

    /// Constructs one phase-qualified frame reference.
    pub fn init(
        source: SourceId,
        resource: ResourceId,
        generation: ResourceGeneration,
    ) error{ InvalidIdentity, InvalidGeneration }!FrameResourceRef {
        const result = FrameResourceRef{
            .source = source,
            .resource = resource,
            .generation = generation,
        };
        try result.validate();
        return result;
    }

    /// Qualifies one local producer resource with its nonzero source.
    pub fn local(
        source: SourceId,
        value: ResourceRef,
    ) error{ InvalidIdentity, InvalidGeneration }!FrameResourceRef {
        const result = FrameResourceRef{
            .source = source,
            .resource = value.resource,
            .generation = value.generation,
        };
        try result.validate();
        return result;
    }

    /// Qualifies one source-independent shared producer resource.
    pub fn shared(
        value: ResourceRef,
    ) error{ InvalidIdentity, InvalidGeneration }!FrameResourceRef {
        const result = FrameResourceRef{
            .source = @fromBackingInt(@intCast(0)),
            .resource = value.resource,
            .generation = value.generation,
        };
        try result.validate();
        return result;
    }

    /// Validates namespace, source, identity and generation facts.
    pub fn validate(self: FrameResourceRef) error{ InvalidIdentity, InvalidGeneration }!void {
        try self.resource.validate();
        if ((@backingInt(self.source) == 0) != self.resource.isShared())
            return error.InvalidIdentity;
        if (@backingInt(self.generation) == 0) return error.InvalidGeneration;
    }
};

/// Borrows one bounded pixel plane for logical resource acceptance.
pub const Pixels = struct {
    /// Borrows bytes only through the accepting producer or Composer call.
    bytes: []const u8,
    /// Counts plane pixels horizontally.
    width: u16,
    /// Counts plane pixels vertically.
    height: u16,
    /// Counts bytes between adjacent rows.
    stride: usize,
};

/// Supplies one producer-local resource upload without transferring bytes.
pub const ResourceUpload = struct {
    /// Identifies the accepted local resource generation.
    resource: ResourceRef,
    /// Selects the stored pixel representation.
    format: ResourceFormat,
    /// Borrows complete pixel bytes for the duration of acceptance.
    ///
    /// `pixels.width` and `pixels.height` are the sole authoritative logical
    /// extent. No parallel size fact may disagree with them.
    pixels: Pixels,
};

/// Removes one exact producer-local resource generation.
pub const ResourceRemoval = struct {
    /// Identifies the exact logical generation to remove.
    resource: ResourceRef,
};

/// Describes one backend-retained frame resource without transferring ownership.
pub const Residency = struct {
    /// Identifies the exact qualified resource generation.
    resource: FrameResourceRef,
    /// Reports the resident pixel representation.
    format: ResourceFormat,
    /// Reports the resident extent.
    size: Size,
};

/// Locates one copied upload in caller-owned frame pixel storage.
pub const ResourceUploadFact = struct {
    /// Identifies the exact qualified resource generation.
    resource: FrameResourceRef,
    /// Selects the copied pixel representation.
    format: ResourceFormat,
    /// Reports the complete resource extent.
    size: Size,
    /// Locates the first byte in caller-owned frame storage.
    pixel_offset: usize,
    /// Counts initialized bytes in caller-owned frame storage.
    pixel_count: usize,
    /// Counts bytes between adjacent copied rows.
    stride: usize,
};

/// Selects one retained producer-local resource region.
pub const ResourceView = struct {
    /// Identifies the exact local resource generation.
    resource: ResourceRef,
    /// Declares the stored pixel representation.
    format: ResourceFormat,
    /// Declares the complete retained extent.
    size: Size,
    /// Selects a source region, or the complete resource when null.
    source: ?SourceRect = null,
};

/// Selects one Composer-qualified resource region in a frame.
pub const FrameResourceView = struct {
    /// Identifies the exact qualified resource generation.
    resource: FrameResourceRef,
    /// Declares the stored pixel representation.
    format: ResourceFormat,
    /// Declares the complete retained extent.
    size: Size,
    /// Selects a source region, or the complete resource when null.
    source: ?SourceRect = null,
};

/// Supplies one ordered producer-local backend-neutral drawing fact.
pub const Input = union(enum) {
    /// Fills one rectangle after intersection with its clip and the surface.
    solid: struct {
        /// Rectangle to fill.
        rect: Rect,
        /// Restricts drawing in caller coordinates.
        clip: Rect,
        /// Fill color.
        color: Color,
    },
    /// Draws one retained alpha-mask region.
    alpha_mask: struct {
        /// Places and optionally scales the resource.
        destination: Rect,
        /// Restricts drawing in caller coordinates.
        clip: Rect,
        /// Selects one alpha resource region.
        resource: ResourceView,
        /// Colors the sampled alpha mask.
        color: Color,
    },
    /// Draws one retained RGBA region.
    rgba: struct {
        /// Places and optionally scales the resource.
        destination: Rect,
        /// Restricts drawing in caller coordinates.
        clip: Rect,
        /// Selects one RGBA resource region.
        resource: ResourceView,
    },
};

/// Borrows one complete producer state transition for one source.
///
/// `commands` is the complete ordered local command list after this update;
/// uploads and removals are sparse resource mutations. Every slice is borrowed
/// only through the accepting call. Canvas validates syntax only: logical
/// ordering, duplicate/conflict policy, retention, and revision monotonicity
/// belong to Composer.
pub const ProducerUpdate = struct {
    /// Supplies the nonzero producer-owned update revision.
    revision: ProducerRevision,
    /// Borrows sparse resource creations and replacements.
    uploads: []const ResourceUpload,
    /// Borrows sparse exact-generation removals.
    removals: []const ResourceRemoval,
    /// Borrows the complete ordered producer-local command list.
    commands: []const Input,
};

/// Retains bounded producer state and derives complete backend-neutral frames.
///
/// The initializer allocator owns every retained allocation through `deinit`.
/// Successful initialization performs all allocation; every later operation is
/// allocation-free and transactional.
pub const Composer = struct {
    /// Fixes every retained, candidate, composition, and frame bound.
    pub const Limits = struct {
        /// Maximum identities issued by this Composer.
        sources: u16,
        /// Maximum resources retained across live sources.
        retained_resources: u32,
        /// Maximum commands retained across live sources.
        retained_commands: u32,
        /// Maximum copied resource bytes retained across live sources.
        retained_pixel_bytes: usize,
        /// Maximum visible sources in one composition.
        composition_sources: u16,
        /// Maximum resources in one candidate source.
        candidate_resources: u32,
        /// Maximum commands in one candidate source.
        candidate_commands: u32,
        /// Maximum copied bytes in one candidate source.
        candidate_pixel_bytes: usize,
    };

    /// Reports exact bounded ownership, identity, revision, or frame failures.
    pub const Error = error{
        OutOfMemory,
        SourceLimit,
        ResourceLimit,
        CommandLimit,
        PixelLimit,
        CompositionLimit,
        IdentityExhausted,
        RevisionExhausted,
        InvalidSource,
        RetiredSource,
        InvalidResidency,
        InvalidIdentity,
        InvalidRevision,
        InvalidGeneration,
        DuplicateSource,
        DuplicateResource,
        ConflictingResourceOperation,
        ReferencedRemoval,
        MissingResource,
        FormatMismatch,
        ExtentMismatch,
        InvalidGeometry,
        AliasedStorage,
        ArithmeticOverflow,
    };

    /// Supplies one signed source origin.
    pub const Point = struct {
        /// Horizontal surface offset.
        x: i32,
        /// Vertical surface offset.
        y: i32,
    };

    /// Places one retained source into the ordered visible composition.
    pub const Placement = struct {
        /// Selects one live Composer-issued source.
        source: SourceId,
        /// Translates source-local coordinates into surface coordinates.
        origin: Point,
        /// Restricts this source in surface coordinates.
        clip: Rect,
    };

    /// Supplies the complete visible surface and ordered source placement.
    pub const Composition = struct {
        /// Defines the nonzero derived surface extent.
        surface: Size,
        /// Borrows the complete back-to-front visible source order.
        sources: []const Placement,
    };

    /// Supplies caller-owned bounded storage for one frame derivation.
    ///
    /// Every initialized prefix is unchanged on failure.
    pub const FrameBuffers = struct {
        /// Receives missing or replacement logical resource facts.
        uploads: []ResourceUploadFact,
        /// Receives backend resources absent from the visible logical frame.
        removals: []FrameResourceRef,
        /// Receives the complete visible surface command list.
        commands: []Command,
        /// Receives copied bytes referenced by `uploads`.
        pixels: []u8,
    };

    /// Borrows initialized caller storage produced by `frame`.
    pub const Frame = struct {
        /// Identifies the current visible logical frame.
        revision: FrameRevision,
        /// Missing or replacement logical resources.
        uploads: []const ResourceUploadFact,
        /// Backend resources no longer required by the visible frame.
        removals: []const FrameResourceRef,
        /// Complete ordered surface commands.
        commands: []const Command,
        /// Complete initialized upload-byte prefix.
        pixels: []const u8,
    };

    const Source = struct {
        id: SourceId,
        revision: u64 = 0,
        local_high_water: u64 = 0,
        resource_start: usize = 0,
        resource_count: usize = 0,
        command_start: usize = 0,
        command_count: usize = 0,
        pixel_start: usize = 0,
        pixel_count: usize = 0,
        live: bool = true,
    };

    const Resource = struct {
        local: ResourceRef,
        format: ResourceFormat,
        size: Size,
        stride: usize,
        pixel_start: usize,
        pixel_count: usize,
    };

    allocator: std.mem.Allocator,
    limits: Limits,
    sources: []Source,
    source_count: usize = 0,
    resources: []Resource,
    resource_count: usize = 0,
    commands: []Input,
    command_count: usize = 0,
    pixels: []u8,
    pixel_count: usize = 0,
    composition: []Placement,
    composition_count: usize = 0,
    surface: Size = .{ .width = 1, .height = 1 },
    candidate_resources: []Resource,
    candidate_resource_count: usize = 0,
    candidate_commands: []Input,
    candidate_command_count: usize = 0,
    candidate_pixels: []u8,
    candidate_pixel_count: usize = 0,
    candidate_high_water: u64 = 0,
    next_source_id: u64 = 1,
    frame_revision: u64 = 1,

    /// Allocates every retained and candidate bank transactionally.
    pub fn init(allocator: std.mem.Allocator, limits: Limits) Composer.Error!Composer {
        try validateComposerLimits(limits);
        const sources = allocator.alloc(Source, limits.sources) catch
            return error.OutOfMemory;
        errdefer allocator.free(sources);
        const resources = allocator.alloc(Resource, limits.retained_resources) catch
            return error.OutOfMemory;
        errdefer allocator.free(resources);
        const commands = allocator.alloc(Input, limits.retained_commands) catch
            return error.OutOfMemory;
        errdefer allocator.free(commands);
        const pixels = allocator.alloc(u8, limits.retained_pixel_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(pixels);
        const composition = allocator.alloc(Placement, limits.composition_sources) catch
            return error.OutOfMemory;
        errdefer allocator.free(composition);
        const candidate_resources = allocator.alloc(Resource, limits.candidate_resources) catch
            return error.OutOfMemory;
        errdefer allocator.free(candidate_resources);
        const candidate_commands = allocator.alloc(Input, limits.candidate_commands) catch
            return error.OutOfMemory;
        errdefer allocator.free(candidate_commands);
        const candidate_pixels = allocator.alloc(u8, limits.candidate_pixel_bytes) catch
            return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .limits = limits,
            .sources = sources,
            .resources = resources,
            .commands = commands,
            .pixels = pixels,
            .composition = composition,
            .candidate_resources = candidate_resources,
            .candidate_commands = candidate_commands,
            .candidate_pixels = candidate_pixels,
        };
    }

    /// Releases every initializer-owned allocation in reverse order.
    pub fn deinit(self: *Composer) void {
        self.allocator.free(self.candidate_pixels);
        self.allocator.free(self.candidate_commands);
        self.allocator.free(self.candidate_resources);
        self.allocator.free(self.composition);
        self.allocator.free(self.pixels);
        self.allocator.free(self.commands);
        self.allocator.free(self.resources);
        self.allocator.free(self.sources);
        self.* = undefined;
    }

    /// Issues one nonzero source identity which is never reused.
    ///
    /// Registration alone does not alter the visible frame revision.
    pub fn registerSource(self: *Composer) Composer.Error!SourceId {
        if (self.source_count >= self.sources.len) return error.SourceLimit;
        if (self.next_source_id == 0 or self.next_source_id == std.math.maxInt(u64))
            return error.IdentityExhausted;
        const id: SourceId = @fromBackingInt(@intCast(self.next_source_id));
        self.sources[self.source_count] = .{
            .id = id,
            .resource_start = self.resource_count,
            .command_start = self.command_count,
            .pixel_start = self.pixel_count,
        };
        self.source_count += 1;
        self.next_source_id += 1;
        return id;
    }

    /// Retires one live source and all its local identities.
    ///
    /// Visible removal advances the frame once; hidden removal does not.
    pub fn removeSource(self: *Composer, source: SourceId) Composer.Error!void {
        const index = try self.sourceIndex(source);
        const visible_index = self.placementIndex(source);
        if (visible_index != null and self.frame_revision == std.math.maxInt(u64))
            return error.RevisionExhausted;

        self.removeRetainedRanges(index, 0, 0, 0);
        self.sources[index].live = false;
        if (visible_index) |placement_index| {
            std.mem.copyForwards(
                Placement,
                self.composition[placement_index .. self.composition_count - 1],
                self.composition[placement_index + 1 .. self.composition_count],
            );
            self.composition_count -= 1;
            self.frame_revision += 1;
        }
    }

    /// Copies one strictly newer complete producer state transactionally.
    pub fn apply(
        self: *Composer,
        source: SourceId,
        update: ProducerUpdate,
    ) Composer.Error!void {
        const index = try self.sourceIndex(source);
        const old = self.sources[index];
        const revision = @backingInt(update.revision);
        if (revision == 0) return error.InvalidRevision;
        if (revision <= old.revision) return error.InvalidRevision;
        try self.buildCandidate(old, update);

        const retained_resources = self.resource_count - old.resource_count +
            self.candidate_resource_count;
        if (retained_resources > self.resources.len) return error.ResourceLimit;
        const retained_commands = self.command_count - old.command_count +
            self.candidate_command_count;
        if (retained_commands > self.commands.len) return error.CommandLimit;
        const retained_pixels = self.pixel_count - old.pixel_count +
            self.candidate_pixel_count;
        if (retained_pixels > self.pixels.len) return error.PixelLimit;
        var visible_changed = false;
        if (self.placementIndex(source)) |placement_index| {
            const placement = self.composition[placement_index];
            for (self.candidate_commands[0..self.candidate_command_count]) |command| {
                try validatePlacedCommand(
                    self.surface,
                    placement,
                    command,
                );
            }
            visible_changed = !try self.visibleContributionEqual(old, placement);
        }
        if (visible_changed and self.frame_revision == std.math.maxInt(u64))
            return error.RevisionExhausted;

        self.commitCandidate(index, revision);
        if (visible_changed) self.frame_revision += 1;
    }

    /// Replaces the complete ordered visible composition transactionally.
    pub fn setComposition(
        self: *Composer,
        value: Composition,
    ) Composer.Error!void {
        if (value.surface.width == 0 or value.surface.height == 0)
            return error.InvalidGeometry;
        if (value.sources.len > self.composition.len)
            return error.CompositionLimit;
        for (value.sources, 0..) |placement, index| {
            const source_index = self.sourceIndex(placement.source) catch |err|
                return err;
            if (!self.sources[source_index].live) return error.RetiredSource;
            validateComposerRect(placement.clip) catch |err| return err;
            const source = self.sources[source_index];
            for (self.commands[source.command_start .. source.command_start + source.command_count]) |command| {
                try validatePlacedCommand(
                    value.surface,
                    placement,
                    command,
                );
            }
            for (value.sources[0..index]) |prior| {
                if (prior.source == placement.source) return error.DuplicateSource;
            }
        }
        if (std.meta.eql(self.surface, value.surface) and
            self.composition_count == value.sources.len and
            placementsEqual(
                self.composition[0..self.composition_count],
                value.sources,
            ))
            return;
        if (self.frame_revision == std.math.maxInt(u64))
            return error.RevisionExhausted;
        @memcpy(self.composition[0..value.sources.len], value.sources);
        self.composition_count = value.sources.len;
        self.surface = value.surface;
        self.frame_revision += 1;
    }

    /// Derives one complete frame against borrowed backend residency.
    ///
    /// This operation is read-only and repeatable. It performs complete
    /// preflight before changing any caller-owned output byte.
    pub fn frame(
        self: *const Composer,
        residency: []const Residency,
        buffers: FrameBuffers,
    ) Composer.Error!Frame {
        try self.validateFrameAliases(residency, buffers);
        try self.validateResidencies(residency);

        var needed_commands: usize = 0;
        var needed_uploads: usize = 0;
        var needed_removals: usize = 0;
        var needed_pixels: usize = 0;
        try self.measureFrame(
            residency,
            &needed_commands,
            &needed_uploads,
            &needed_removals,
            &needed_pixels,
        );
        if (needed_commands > buffers.commands.len) return error.CommandLimit;
        if (needed_uploads > buffers.uploads.len) return error.ResourceLimit;
        if (needed_removals > buffers.removals.len) return error.ResourceLimit;
        if (needed_pixels > buffers.pixels.len) return error.PixelLimit;

        var command_count: usize = 0;
        var upload_count: usize = 0;
        var removal_count: usize = 0;
        var pixel_count: usize = 0;
        try self.writeFrame(
            residency,
            buffers,
            &command_count,
            &upload_count,
            &removal_count,
            &pixel_count,
        );
        return .{
            .revision = @fromBackingInt(@intCast(self.frame_revision)),
            .uploads = buffers.uploads[0..upload_count],
            .removals = buffers.removals[0..removal_count],
            .commands = buffers.commands[0..command_count],
            .pixels = buffers.pixels[0..pixel_count],
        };
    }

    fn sourceIndex(self: *const Composer, source: SourceId) Composer.Error!usize {
        const value = @backingInt(source);
        if (value == 0 or value >= self.next_source_id) return error.InvalidSource;
        const index: usize = @intCast(value - 1);
        if (index >= self.source_count) return error.InvalidSource;
        if (!self.sources[index].live) return error.RetiredSource;
        return index;
    }

    fn placementIndex(self: *const Composer, source: SourceId) ?usize {
        for (self.composition[0..self.composition_count], 0..) |placement, index| {
            if (placement.source == source) return index;
        }
        return null;
    }

    fn buildCandidate(
        self: *Composer,
        old: Source,
        update: ProducerUpdate,
    ) Composer.Error!void {
        self.candidate_resource_count = 0;
        self.candidate_command_count = 0;
        self.candidate_pixel_count = 0;
        self.candidate_high_water = old.local_high_water;
        errdefer {
            self.candidate_resource_count = 0;
            self.candidate_command_count = 0;
            self.candidate_pixel_count = 0;
            self.candidate_high_water = old.local_high_water;
        }
        validateProducerUpdate(update) catch |err| return mapFactError(err);
        if (update.commands.len > self.candidate_commands.len)
            return error.CommandLimit;

        for (update.uploads, 0..) |upload, index| {
            for (update.uploads[0..index]) |prior| {
                if (prior.resource.resource == upload.resource.resource)
                    return error.DuplicateResource;
            }
            for (update.removals) |removal| {
                if (removal.resource.resource == upload.resource.resource)
                    return error.ConflictingResourceOperation;
            }
        }
        for (update.removals, 0..) |removal, index| {
            for (update.removals[0..index]) |prior| {
                if (prior.resource.resource == removal.resource.resource)
                    return error.DuplicateResource;
            }
        }

        var high_water = old.local_high_water;
        const old_resources = self.resources[old.resource_start .. old.resource_start + old.resource_count];
        for (old_resources) |resource| {
            const removal = findRemoval(update.removals, resource.local.resource);
            const replacement = findUpload(update.uploads, resource.local.resource);
            if (removal) |value| {
                if (value.resource.generation != resource.local.generation)
                    return error.InvalidGeneration;
                continue;
            }
            if (replacement) |value| {
                if (@backingInt(value.resource.generation) <=
                    @backingInt(resource.local.generation))
                    return error.InvalidGeneration;
                try self.appendCandidateUpload(value);
                continue;
            }
            try self.appendCandidateRetained(resource);
        }
        for (update.removals) |removal| {
            if (findResource(old_resources, removal.resource.resource) == null)
                return error.MissingResource;
        }
        for (update.uploads) |upload| {
            if (findResource(old_resources, upload.resource.resource) != null)
                continue;
            const local = @backingInt(upload.resource.resource);
            if (local == 0) return error.InvalidIdentity;
            if (local <= old.local_high_water) return error.InvalidIdentity;
            high_water = @max(high_water, local);
            try self.appendCandidateUpload(upload);
        }

        for (update.commands) |command| {
            try self.validateCandidateCommand(command, update.removals);
            self.candidate_commands[self.candidate_command_count] = command;
            self.candidate_command_count += 1;
        }
        self.candidate_high_water = high_water;
    }

    fn appendCandidateRetained(
        self: *Composer,
        resource: Resource,
    ) Composer.Error!void {
        if (self.candidate_resource_count >= self.candidate_resources.len)
            return error.ResourceLimit;
        if (resource.pixel_count > self.candidate_pixels.len -
            @min(self.candidate_pixel_count, self.candidate_pixels.len))
            return error.PixelLimit;
        const source_pixels = self.pixels[resource.pixel_start .. resource.pixel_start + resource.pixel_count];
        @memcpy(
            self.candidate_pixels[self.candidate_pixel_count .. self.candidate_pixel_count + resource.pixel_count],
            source_pixels,
        );
        var candidate = resource;
        candidate.pixel_start = self.candidate_pixel_count;
        self.candidate_resources[self.candidate_resource_count] = candidate;
        self.candidate_resource_count += 1;
        self.candidate_pixel_count += resource.pixel_count;
    }

    fn appendCandidateUpload(
        self: *Composer,
        upload: ResourceUpload,
    ) Composer.Error!void {
        if (self.candidate_resource_count >= self.candidate_resources.len)
            return error.ResourceLimit;
        if (upload.pixels.bytes.len > self.candidate_pixels.len -
            @min(self.candidate_pixel_count, self.candidate_pixels.len))
            return error.PixelLimit;
        @memcpy(
            self.candidate_pixels[self.candidate_pixel_count .. self.candidate_pixel_count + upload.pixels.bytes.len],
            upload.pixels.bytes,
        );
        self.candidate_resources[self.candidate_resource_count] = .{
            .local = upload.resource,
            .format = upload.format,
            .size = .{
                .width = upload.pixels.width,
                .height = upload.pixels.height,
            },
            .stride = upload.pixels.stride,
            .pixel_start = self.candidate_pixel_count,
            .pixel_count = upload.pixels.bytes.len,
        };
        self.candidate_resource_count += 1;
        self.candidate_pixel_count += upload.pixels.bytes.len;
    }

    fn validateCandidateCommand(
        self: *const Composer,
        command: Input,
        removals: []const ResourceRemoval,
    ) Composer.Error!void {
        switch (command) {
            .solid => |value| {
                try validateComposerRect(value.rect);
                try validateComposerRect(value.clip);
            },
            .alpha_mask => |value| try self.validateCandidateResourceCommand(
                value.destination,
                value.clip,
                value.resource,
                .alpha8,
                removals,
            ),
            .rgba => |value| try self.validateCandidateResourceCommand(
                value.destination,
                value.clip,
                value.resource,
                .rgba8,
                removals,
            ),
        }
    }

    fn validateCandidateResourceCommand(
        self: *const Composer,
        destination: Rect,
        clip: Rect,
        view: ResourceView,
        format: ResourceFormat,
        removals: []const ResourceRemoval,
    ) Composer.Error!void {
        try validateComposerRect(destination);
        try validateComposerRect(clip);
        if (view.format != format) return error.FormatMismatch;
        const resource = findResource(
            self.candidate_resources[0..self.candidate_resource_count],
            view.resource.resource,
        ) orelse {
            if (findRemoval(removals, view.resource.resource) != null)
                return error.ReferencedRemoval;
            return error.MissingResource;
        };
        if (resource.local.generation != view.resource.generation)
            return error.InvalidGeneration;
        if (resource.format != view.format) return error.FormatMismatch;
        if (!std.meta.eql(resource.size, view.size)) return error.ExtentMismatch;
        validateExtent(view.size, view.source) catch |err| return mapFactError(err);
    }

    fn commitCandidate(self: *Composer, index: usize, revision: u64) void {
        const old = self.sources[index];
        const resource_delta = signedDelta(
            self.candidate_resource_count,
            old.resource_count,
        );
        const command_delta = signedDelta(
            self.candidate_command_count,
            old.command_count,
        );
        const pixel_delta = signedDelta(
            self.candidate_pixel_count,
            old.pixel_count,
        );
        replaceSlice(
            u8,
            self.pixels,
            &self.pixel_count,
            old.pixel_start,
            old.pixel_count,
            self.candidate_pixels[0..self.candidate_pixel_count],
        );
        for (self.resources[old.resource_start + old.resource_count .. self.resource_count]) |*resource|
            resource.pixel_start = applyDelta(resource.pixel_start, pixel_delta);
        replaceSlice(
            Resource,
            self.resources,
            &self.resource_count,
            old.resource_start,
            old.resource_count,
            self.candidate_resources[0..self.candidate_resource_count],
        );
        for (self.resources[old.resource_start .. old.resource_start + self.candidate_resource_count]) |*resource|
            resource.pixel_start += old.pixel_start;
        replaceSlice(
            Input,
            self.commands,
            &self.command_count,
            old.command_start,
            old.command_count,
            self.candidate_commands[0..self.candidate_command_count],
        );
        for (self.sources[0..self.source_count], 0..) |*source, source_index| {
            if (source_index == index) continue;
            if (source_index > index)
                source.resource_start = applyDelta(source.resource_start, resource_delta);
            if (source_index > index)
                source.command_start = applyDelta(source.command_start, command_delta);
            if (source_index > index)
                source.pixel_start = applyDelta(source.pixel_start, pixel_delta);
        }
        self.sources[index].revision = revision;
        self.sources[index].local_high_water = self.candidate_high_water;
        self.sources[index].resource_count = self.candidate_resource_count;
        self.sources[index].command_count = self.candidate_command_count;
        self.sources[index].pixel_count = self.candidate_pixel_count;
    }

    fn removeRetainedRanges(
        self: *Composer,
        index: usize,
        new_resources: usize,
        new_commands: usize,
        new_pixels: usize,
    ) void {
        self.candidate_resource_count = new_resources;
        self.candidate_command_count = new_commands;
        self.candidate_pixel_count = new_pixels;
        self.candidate_high_water = self.sources[index].local_high_water;
        self.commitCandidate(index, self.sources[index].revision);
    }

    fn validateResidencies(
        self: *const Composer,
        residency: []const Residency,
    ) Composer.Error!void {
        if (residency.len > self.resources.len) return error.InvalidResidency;
        for (residency, 0..) |value, index| {
            validateResidency(value) catch return error.InvalidResidency;
            const source_value = @backingInt(value.resource.source);
            if (source_value == 0 or source_value >= self.next_source_id)
                return error.InvalidResidency;
            for (residency[0..index]) |prior| {
                if (prior.resource.source == value.resource.source and
                    prior.resource.resource == value.resource.resource)
                    return error.InvalidResidency;
            }
        }
    }

    fn validateFrameAliases(
        self: *const Composer,
        residency: []const Residency,
        buffers: FrameBuffers,
    ) Composer.Error!void {
        const ranges = [_]ByteRange{
            try byteRange(Residency, residency),
            try byteRange(ResourceUploadFact, buffers.uploads),
            try byteRange(FrameResourceRef, buffers.removals),
            try byteRange(Command, buffers.commands),
            try byteRange(u8, buffers.pixels),
        };
        try self.rejectInternalFrameAliases(ranges[1..]);
        for (ranges, 0..) |left, index| {
            for (ranges[index + 1 ..]) |right| {
                if (overlaps(left.start, left.len, right.start, right.len))
                    return error.AliasedStorage;
            }
        }
    }

    fn rejectInternalFrameAliases(
        self: *const Composer,
        outputs: []const ByteRange,
    ) Composer.Error!void {
        const retained = [_]ByteRange{
            try byteRange(Source, self.sources),
            try byteRange(Resource, self.resources),
            try byteRange(Input, self.commands),
            try byteRange(u8, self.pixels),
            try byteRange(Placement, self.composition),
            try byteRange(Resource, self.candidate_resources),
            try byteRange(Input, self.candidate_commands),
            try byteRange(u8, self.candidate_pixels),
        };
        for (outputs) |output| {
            for (retained) |owned| {
                if (overlaps(output.start, output.len, owned.start, owned.len))
                    return error.AliasedStorage;
            }
        }
    }

    fn measureFrame(
        self: *const Composer,
        residency: []const Residency,
        commands_needed: *usize,
        uploads_needed: *usize,
        removals_needed: *usize,
        pixels_needed: *usize,
    ) Composer.Error!void {
        for (self.composition[0..self.composition_count]) |placement| {
            const source = self.sources[
                @intCast(@backingInt(placement.source) - 1)
            ];
            for (self.commands[source.command_start .. source.command_start + source.command_count]) |command| {
                if (try self.frameCommand(placement, command) != null)
                    commands_needed.* = std.math.add(usize, commands_needed.*, 1) catch
                        return error.ArithmeticOverflow;
            }
            for (self.resources[source.resource_start .. source.resource_start + source.resource_count]) |resource| {
                if (!try self.resourceVisible(placement, source, resource.local))
                    continue;
                if (!residencyMatches(residency, source.id, resource)) {
                    uploads_needed.* = std.math.add(usize, uploads_needed.*, 1) catch
                        return error.ArithmeticOverflow;
                    pixels_needed.* = std.math.add(
                        usize,
                        pixels_needed.*,
                        resource.pixel_count,
                    ) catch return error.ArithmeticOverflow;
                }
            }
        }
        for (residency) |value| {
            if (!try self.residencyRequired(value))
                removals_needed.* = std.math.add(usize, removals_needed.*, 1) catch
                    return error.ArithmeticOverflow;
        }
    }

    fn writeFrame(
        self: *const Composer,
        residency: []const Residency,
        buffers: FrameBuffers,
        command_count: *usize,
        upload_count: *usize,
        removal_count: *usize,
        pixel_count: *usize,
    ) Composer.Error!void {
        for (self.composition[0..self.composition_count]) |placement| {
            const source = self.sources[
                @intCast(@backingInt(placement.source) - 1)
            ];
            for (self.commands[source.command_start .. source.command_start + source.command_count]) |command| {
                const output = (try self.frameCommand(placement, command)) orelse
                    continue;
                buffers.commands[command_count.*] = output;
                command_count.* += 1;
            }
            for (self.resources[source.resource_start .. source.resource_start + source.resource_count]) |resource| {
                if (!try self.resourceVisible(placement, source, resource.local) or
                    residencyMatches(residency, source.id, resource))
                    continue;
                const destination = buffers.pixels[pixel_count.* .. pixel_count.* + resource.pixel_count];
                @memcpy(destination, self.pixels[resource.pixel_start .. resource.pixel_start + resource.pixel_count]);
                buffers.uploads[upload_count.*] = .{
                    .resource = qualifyResource(source.id, resource.local),
                    .format = resource.format,
                    .size = resource.size,
                    .pixel_offset = pixel_count.*,
                    .pixel_count = resource.pixel_count,
                    .stride = resource.stride,
                };
                upload_count.* += 1;
                pixel_count.* += resource.pixel_count;
            }
        }
        for (residency) |value| {
            if (try self.residencyRequired(value)) continue;
            buffers.removals[removal_count.*] = value.resource;
            removal_count.* += 1;
        }
    }

    fn frameCommand(
        self: *const Composer,
        placement: Placement,
        input: Input,
    ) Composer.Error!?Command {
        return frameCommandAt(self.surface, placement, input);
    }

    fn visibleContributionEqual(
        self: *const Composer,
        old: Source,
        placement: Placement,
    ) Composer.Error!bool {
        const old_commands = self.commands[old.command_start .. old.command_start + old.command_count];
        const candidate_commands =
            self.candidate_commands[0..self.candidate_command_count];
        var old_index: usize = 0;
        var candidate_index: usize = 0;
        while (true) {
            const old_command = try nextVisibleCommand(
                self.surface,
                placement,
                old_commands,
                &old_index,
            );
            const candidate_command = try nextVisibleCommand(
                self.surface,
                placement,
                candidate_commands,
                &candidate_index,
            );
            if (old_command == null or candidate_command == null) {
                if (old_command != null or candidate_command != null) return false;
                break;
            }
            if (!std.meta.eql(old_command.?, candidate_command.?)) return false;
        }
        const old_resources = self.resources[old.resource_start .. old.resource_start + old.resource_count];
        const candidate_resources =
            self.candidate_resources[0..self.candidate_resource_count];
        for (old_resources) |resource| {
            if (!try resourceReferencedVisibly(
                self.surface,
                placement,
                old_commands,
                resource.local,
            )) continue;
            const candidate = findResource(
                candidate_resources,
                resource.local.resource,
            ) orelse return false;
            if (!resourceFactsEqual(resource, candidate)) return false;
            if (!std.mem.eql(
                u8,
                self.pixels[resource.pixel_start .. resource.pixel_start + resource.pixel_count],
                self.candidate_pixels[candidate.pixel_start .. candidate.pixel_start + candidate.pixel_count],
            )) return false;
        }
        for (candidate_resources) |resource| {
            if (!try resourceReferencedVisibly(
                self.surface,
                placement,
                candidate_commands,
                resource.local,
            )) continue;
            if (findResource(old_resources, resource.local.resource) == null)
                return false;
        }
        return true;
    }

    fn resourceVisible(
        self: *const Composer,
        placement: Placement,
        source: Source,
        local: ResourceRef,
    ) Composer.Error!bool {
        for (self.commands[source.command_start .. source.command_start + source.command_count]) |command| switch (command) {
            .solid => {},
            .alpha_mask => |value| {
                if (std.meta.eql(value.resource.resource, local) and
                    try self.frameCommand(placement, command) != null)
                    return true;
            },
            .rgba => |value| {
                if (std.meta.eql(value.resource.resource, local) and
                    try self.frameCommand(placement, command) != null)
                    return true;
            },
        };
        return false;
    }

    fn residencyRequired(
        self: *const Composer,
        residency: Residency,
    ) Composer.Error!bool {
        const placement_index = self.placementIndex(residency.resource.source) orelse
            return false;
        const source = self.sources[
            @intCast(@backingInt(self.composition[placement_index].source) - 1)
        ];
        const resource = findResource(
            self.resources[source.resource_start .. source.resource_start + source.resource_count],
            residency.resource.resource,
        ) orelse return false;
        return try self.resourceVisible(
            self.composition[placement_index],
            source,
            resource.local,
        );
    }
};

const ByteRange = struct {
    start: usize,
    len: usize,
};

fn validateComposerLimits(limits: Composer.Limits) Composer.Error!void {
    if (limits.sources == 0 or limits.retained_resources == 0 or
        limits.retained_commands == 0 or limits.retained_pixel_bytes == 0 or
        limits.composition_sources == 0 or limits.candidate_resources == 0 or
        limits.candidate_commands == 0 or limits.candidate_pixel_bytes == 0)
        return error.InvalidGeometry;
    if (limits.composition_sources > limits.sources)
        return error.CompositionLimit;
    try validateAllocationSize(limits.sources, @sizeOf(Composer.Source));
    try validateAllocationSize(
        limits.retained_resources,
        @sizeOf(Composer.Resource),
    );
    try validateAllocationSize(limits.retained_commands, @sizeOf(Input));
    try validateAllocationSize(
        limits.composition_sources,
        @sizeOf(Composer.Placement),
    );
    try validateAllocationSize(
        limits.candidate_resources,
        @sizeOf(Composer.Resource),
    );
    try validateAllocationSize(limits.candidate_commands, @sizeOf(Input));
}

fn validateAllocationSize(count: usize, item_size: usize) Composer.Error!void {
    const bytes = std.math.mul(usize, count, item_size) catch
        return error.ArithmeticOverflow;
    if (count != 0 and bytes / count != item_size)
        return error.ArithmeticOverflow;
}

fn validateComposerRect(rect: Rect) Composer.Error!void {
    const value = edges(rect) catch |err| return mapCanvasGeometry(err);
    if (value.right <= value.left or value.bottom <= value.top)
        return error.InvalidGeometry;
}

fn placementsEqual(
    left: []const Composer.Placement,
    right: []const Composer.Placement,
) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!std.meta.eql(a, b)) return false;
    }
    return true;
}

fn mapFactError(err: ResourceFactError) Composer.Error {
    return switch (err) {
        error.InvalidIdentity => error.InvalidIdentity,
        error.InvalidGeneration => error.InvalidGeneration,
        error.InvalidRevision => error.InvalidRevision,
        error.InvalidPixels => error.ExtentMismatch,
        error.FormatMismatch => error.FormatMismatch,
        error.ExtentMismatch => error.ExtentMismatch,
        error.ArithmeticOverflow => error.ArithmeticOverflow,
    };
}

fn findUpload(
    uploads: []const ResourceUpload,
    id: ResourceId,
) ?ResourceUpload {
    for (uploads) |upload| {
        if (upload.resource.resource == id) return upload;
    }
    return null;
}

fn findRemoval(
    removals: []const ResourceRemoval,
    id: ResourceId,
) ?ResourceRemoval {
    for (removals) |removal| {
        if (removal.resource.resource == id) return removal;
    }
    return null;
}

fn findResource(
    resources: []const Composer.Resource,
    id: ResourceId,
) ?Composer.Resource {
    for (resources) |resource| {
        if (resource.local.resource == id) return resource;
    }
    return null;
}

fn replaceSlice(
    comptime T: type,
    storage: []T,
    count: *usize,
    start: usize,
    old_count: usize,
    replacement: []const T,
) void {
    const old_end = start + old_count;
    const tail_count = count.* - old_end;
    const new_end = start + replacement.len;
    if (replacement.len > old_count) {
        std.mem.copyBackwards(
            T,
            storage[new_end .. new_end + tail_count],
            storage[old_end .. old_end + tail_count],
        );
        @memcpy(storage[start..new_end], replacement);
    } else {
        @memcpy(storage[start..new_end], replacement);
        std.mem.copyForwards(
            T,
            storage[new_end .. new_end + tail_count],
            storage[old_end .. old_end + tail_count],
        );
    }
    count.* = count.* - old_count + replacement.len;
}

fn signedDelta(new_count: usize, old_count: usize) isize {
    if (new_count >= old_count) return @intCast(new_count - old_count);
    return -@as(isize, @intCast(old_count - new_count));
}

fn applyDelta(value: usize, delta: isize) usize {
    if (delta >= 0) return value + @as(usize, @intCast(delta));
    return value - @as(usize, @intCast(-delta));
}

fn byteRange(comptime T: type, slice: []const T) Composer.Error!ByteRange {
    return .{
        .start = @intFromPtr(slice.ptr),
        .len = std.math.mul(usize, slice.len, @sizeOf(T)) catch
            return error.ArithmeticOverflow,
    };
}

fn translated(rect: Rect, origin: Composer.Point) Composer.Error!Rect {
    return .{
        .x = std.math.add(i32, rect.x, origin.x) catch
            return error.ArithmeticOverflow,
        .y = std.math.add(i32, rect.y, origin.y) catch
            return error.ArithmeticOverflow,
        .width = rect.width,
        .height = rect.height,
    };
}

fn validatePlacedCommand(
    surface: Size,
    placement: Composer.Placement,
    input: Input,
) Composer.Error!void {
    if (try frameCommandAt(surface, placement, input) != null) return;
}

fn nextVisibleCommand(
    surface: Size,
    placement: Composer.Placement,
    commands: []const Input,
    index: *usize,
) Composer.Error!?Command {
    while (index.* < commands.len) {
        const command = commands[index.*];
        index.* += 1;
        if (try frameCommandAt(surface, placement, command)) |visible|
            return visible;
    }
    return null;
}

fn resourceReferencedVisibly(
    surface: Size,
    placement: Composer.Placement,
    commands: []const Input,
    resource: ResourceRef,
) Composer.Error!bool {
    for (commands) |command| {
        const referenced = switch (command) {
            .solid => false,
            .alpha_mask => |value| std.meta.eql(value.resource.resource, resource),
            .rgba => |value| std.meta.eql(value.resource.resource, resource),
        };
        if (referenced and try frameCommandAt(surface, placement, command) != null)
            return true;
    }
    return false;
}

fn resourceFactsEqual(
    left: Composer.Resource,
    right: Composer.Resource,
) bool {
    return std.meta.eql(left.local, right.local) and
        left.format == right.format and
        std.meta.eql(left.size, right.size) and
        left.stride == right.stride and
        left.pixel_count == right.pixel_count;
}

fn frameCommandAt(
    surface: Size,
    placement: Composer.Placement,
    input: Input,
) Composer.Error!?Command {
    const translated_clip = try translated(placement.clip, .{ .x = 0, .y = 0 });
    return switch (input) {
        .solid => |value| solid: {
            const rect = try translated(value.rect, placement.origin);
            const local_clip = try translated(value.clip, placement.origin);
            const visible = try clippedThree(
                rect,
                local_clip,
                translated_clip,
                surface,
            ) orelse break :solid null;
            break :solid .{ .solid = .{ .rect = visible, .color = value.color } };
        },
        .alpha_mask => |value| alpha: {
            const destination = try translated(value.destination, placement.origin);
            const local_clip = try translated(value.clip, placement.origin);
            const visible = try clippedThree(
                destination,
                local_clip,
                translated_clip,
                surface,
            ) orelse break :alpha null;
            break :alpha .{ .alpha_mask = .{
                .destination = destination,
                .clip = visible,
                .resource = qualifyView(placement.source, value.resource),
                .color = value.color,
            } };
        },
        .rgba => |value| rgba: {
            const destination = try translated(value.destination, placement.origin);
            const local_clip = try translated(value.clip, placement.origin);
            const visible = try clippedThree(
                destination,
                local_clip,
                translated_clip,
                surface,
            ) orelse break :rgba null;
            break :rgba .{ .rgba = .{
                .destination = destination,
                .clip = visible,
                .resource = qualifyView(placement.source, value.resource),
            } };
        },
    };
}

fn clippedThree(
    rect: Rect,
    first_clip: Rect,
    second_clip: Rect,
    surface: Size,
) Composer.Error!?Rect {
    const rect_edges = edges(rect) catch |err| return mapCanvasGeometry(err);
    const first_edges = edges(first_clip) catch |err| return mapCanvasGeometry(err);
    const second_edges = edges(second_clip) catch |err| return mapCanvasGeometry(err);
    const left = @max(
        @as(i64, 0),
        @max(rect_edges.left, @max(first_edges.left, second_edges.left)),
    );
    const top = @max(
        @as(i64, 0),
        @max(rect_edges.top, @max(first_edges.top, second_edges.top)),
    );
    const right = @min(
        @as(i64, surface.width),
        @min(rect_edges.right, @min(first_edges.right, second_edges.right)),
    );
    const bottom = @min(
        @as(i64, surface.height),
        @min(rect_edges.bottom, @min(first_edges.bottom, second_edges.bottom)),
    );
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

fn mapCanvasGeometry(err: Error) Composer.Error {
    return switch (err) {
        error.InvalidRectangle, error.InvalidSurface => error.InvalidGeometry,
        error.InvalidIdentity => error.InvalidIdentity,
        error.InvalidGeneration => error.InvalidGeneration,
        error.FormatMismatch => error.FormatMismatch,
        error.ExtentMismatch => error.ExtentMismatch,
        error.ArithmeticOverflow => error.ArithmeticOverflow,
        error.AliasedStorage => error.AliasedStorage,
        error.InsufficientCommands => error.CommandLimit,
    };
}

fn qualifyResource(
    source: SourceId,
    local: ResourceRef,
) FrameResourceRef {
    return .{
        .source = source,
        .resource = local.resource,
        .generation = local.generation,
    };
}

fn qualifyView(source: SourceId, local: ResourceView) FrameResourceView {
    return .{
        .resource = qualifyResource(source, local.resource),
        .format = local.format,
        .size = local.size,
        .source = local.source,
    };
}

fn residencyMatches(
    residency: []const Residency,
    source: SourceId,
    resource: Composer.Resource,
) bool {
    for (residency) |value| {
        if (value.resource.source == source and
            value.resource.resource == resource.local.resource)
            return value.resource.generation == resource.local.generation and
                value.format == resource.format and
                std.meta.eql(value.size, resource.size);
    }
    return false;
}

/// Copies one accepted draw with an exact surface-local scissor rectangle.
pub const Command = union(enum) {
    /// Fills the clipped rectangle.
    solid: struct {
        /// Exact visible rectangle.
        rect: Rect,
        /// Fill color.
        color: Color,
    },
    /// Draws one retained alpha resource through an exact clip.
    alpha_mask: struct {
        /// Original destination retained for exact texture mapping.
        destination: Rect,
        /// Exact visible scissor.
        clip: Rect,
        /// Selects the qualified retained alpha region.
        resource: FrameResourceView,
        /// Mask color.
        color: Color,
    },
    /// Draws one retained RGBA resource through an exact clip.
    rgba: struct {
        /// Original destination retained for exact texture mapping.
        destination: Rect,
        /// Exact visible scissor.
        clip: Rect,
        /// Selects the qualified retained RGBA region.
        resource: FrameResourceView,
    },
};

/// Clips and qualifies ordered producer facts into caller command storage.
///
/// Canvas retains no resource or residency state. It validates identity syntax,
/// formats, extents, geometry, clipping, arithmetic, aliases, and capacity
/// before writing. Returned commands borrow only caller storage until reused.
pub fn project(
    surface: Size,
    source: SourceId,
    inputs: []const Input,
    commands: []Command,
) Error![]const Command {
    if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
    try validateSourceId(source);
    const command_bytes = try bytesFor(commands.len, @sizeOf(Command));
    const input_bytes = try bytesFor(inputs.len, @sizeOf(Input));
    if (overlaps(
        @intFromPtr(commands.ptr),
        command_bytes,
        @intFromPtr(inputs.ptr),
        input_bytes,
    )) return error.AliasedStorage;

    var needed: usize = 0;
    for (inputs) |input| {
        if (try validate(input, surface) != null)
            needed = std.math.add(usize, needed, 1) catch
                return error.ArithmeticOverflow;
    }
    if (commands.len < needed) return error.InsufficientCommands;

    var used: usize = 0;
    for (inputs) |input| {
        const visible = (try validate(input, surface)) orelse continue;
        commands[used] = switch (input) {
            .solid => |value| .{ .solid = .{
                .rect = visible,
                .color = value.color,
            } },
            .alpha_mask => |value| .{ .alpha_mask = .{
                .destination = value.destination,
                .clip = visible,
                .resource = qualify(source, value.resource),
                .color = value.color,
            } },
            .rgba => |value| .{ .rgba = .{
                .destination = value.destination,
                .clip = visible,
                .resource = qualify(source, value.resource),
            } },
        };
        used += 1;
    }
    return commands[0..used];
}

fn qualify(source: SourceId, resource: ResourceView) FrameResourceView {
    return .{
        .resource = .{
            .source = source,
            .resource = resource.resource.resource,
            .generation = resource.resource.generation,
        },
        .format = resource.format,
        .size = resource.size,
        .source = resource.source,
    };
}

fn validate(input: Input, surface: Size) Error!?Rect {
    return switch (input) {
        .solid => |value| try clipped(value.rect, value.clip, surface),
        .alpha_mask => |value| alpha: {
            try validateLocalView(value.resource, .alpha8);
            break :alpha try clipped(value.destination, value.clip, surface);
        },
        .rgba => |value| rgba: {
            try validateLocalView(value.resource, .rgba8);
            break :rgba try clipped(value.destination, value.clip, surface);
        },
    };
}

fn validateLocalView(view: ResourceView, required: ResourceFormat) Error!void {
    try validateLocalRef(view.resource);
    if (view.format != required) return error.FormatMismatch;
    try validateExtent(view.size, view.source);
}

fn validateFrameRef(resource: FrameResourceRef) error{ InvalidIdentity, InvalidGeneration }!void {
    try resource.validate();
}

fn validateSourceId(source: SourceId) error{InvalidIdentity}!void {
    try validation.sourceIdentity(@backingInt(source));
}

fn validateExtent(size: Size, source: ?SourceRect) error{ ExtentMismatch, ArithmeticOverflow }!void {
    if (source) |value| {
        try validation.extent(
            size.width,
            size.height,
            value.x,
            value.y,
            value.width,
            value.height,
        );
    } else {
        try validation.extent(
            size.width,
            size.height,
            null,
            null,
            null,
            null,
        );
    }
}

fn validateUpload(upload: ResourceUpload) ResourceFactError!void {
    try validateLocalRef(upload.resource);
    try validatePixels(upload.pixels, upload.format);
}

fn validateRemoval(removal: ResourceRemoval) ResourceFactError!void {
    try validateLocalRef(removal.resource);
}

fn validateLocalRef(resource: ResourceRef) error{ InvalidIdentity, InvalidGeneration }!void {
    if (resource.resource.isShared()) return error.InvalidIdentity;
    const identity_value = try resource.resource.identity();
    try validation.localIdentity(
        identity_value,
        @backingInt(resource.generation),
    );
}

fn validateResidency(residency: Residency) ResourceFactError!void {
    try validateFrameRef(residency.resource);
    try validateExtent(residency.size, null);
}

fn validateUploadFact(fact: ResourceUploadFact, pixels_len: usize) ResourceFactError!void {
    try validateFrameRef(fact.resource);
    try validateExtent(fact.size, null);
    const bytes_per_pixel: usize = switch (fact.format) {
        .alpha8 => 1,
        .rgba8 => 4,
    };
    const row_bytes = std.math.mul(usize, fact.size.width, bytes_per_pixel) catch
        return error.ArithmeticOverflow;
    if (fact.stride < row_bytes) return error.InvalidPixels;
    const preceding = std.math.mul(usize, fact.size.height - 1, fact.stride) catch
        return error.ArithmeticOverflow;
    const required = std.math.add(usize, preceding, row_bytes) catch
        return error.ArithmeticOverflow;
    if (required != fact.pixel_count) return error.ExtentMismatch;
    const end = std.math.add(usize, fact.pixel_offset, fact.pixel_count) catch
        return error.ArithmeticOverflow;
    if (end > pixels_len) return error.InvalidPixels;
}

fn validatePixels(pixels: Pixels, format: ResourceFormat) ResourceFactError!void {
    switch (format) {
        .alpha8 => try validation.alpha8(
            pixels.bytes.len,
            pixels.width,
            pixels.height,
            pixels.stride,
        ),
        .rgba8 => try validation.rgba8(
            pixels.bytes.len,
            pixels.width,
            pixels.height,
            pixels.stride,
        ),
    }
}

fn validateProducerUpdate(update: ProducerUpdate) ResourceFactError!void {
    if (@backingInt(update.revision) == 0) return error.InvalidRevision;
    for (update.uploads) |upload| try validateUpload(upload);
    for (update.removals) |removal| try validateRemoval(removal);
    for (update.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            validation.localIdentity(
                @backingInt(value.resource.resource.resource),
                @backingInt(value.resource.resource.generation),
            ) catch |err| return err;
            if (value.resource.format != .alpha8) return error.FormatMismatch;
            validateExtent(value.resource.size, value.resource.source) catch |err| return err;
        },
        .rgba => |value| {
            validation.localIdentity(
                @backingInt(value.resource.resource.resource),
                @backingInt(value.resource.resource.generation),
            ) catch |err| return err;
            if (value.resource.format != .rgba8) return error.FormatMismatch;
            validateExtent(value.resource.size, value.resource.source) catch |err| return err;
        },
    };
}

fn clipped(rect: Rect, clip: Rect, surface: Size) Error!?Rect {
    const rect_edges = try edges(rect);
    const clip_edges = try edges(clip);
    const left = @max(@as(i64, 0), @max(rect_edges.left, clip_edges.left));
    const top = @max(@as(i64, 0), @max(rect_edges.top, clip_edges.top));
    const right = @min(@as(i64, surface.width), @min(rect_edges.right, clip_edges.right));
    const bottom = @min(@as(i64, surface.height), @min(rect_edges.bottom, clip_edges.bottom));
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

const Edges = struct { left: i64, top: i64, right: i64, bottom: i64 };

fn edges(rect: Rect) Error!Edges {
    if (rect.width == 0 or rect.height == 0) return error.InvalidRectangle;
    const left: i64 = rect.x;
    const top: i64 = rect.y;
    return .{
        .left = left,
        .top = top,
        .right = std.math.add(i64, left, rect.width) catch return error.ArithmeticOverflow,
        .bottom = std.math.add(i64, top, rect.height) catch return error.ArithmeticOverflow,
    };
}

fn bytesFor(count: usize, size: usize) Error!usize {
    return std.math.mul(usize, count, size) catch error.ArithmeticOverflow;
}

fn overlaps(a: usize, a_len: usize, b: usize, b_len: usize) bool {
    if (a_len == 0 or b_len == 0) return false;
    if (a > std.math.maxInt(usize) - a_len or b > std.math.maxInt(usize) - b_len)
        return true;
    return a < b + b_len and b < a + a_len;
}

test "resource fact syntax is exact and stateless" {
    const local = ResourceRef{
        .resource = try ResourceId.local(7),
        .generation = @fromBackingInt(@intCast(9)),
    };
    try validateUpload(.{
        .resource = local,
        .format = .alpha8,
        .pixels = .{ .bytes = &.{ 1, 2 }, .width = 2, .height = 1, .stride = 2 },
    });
    try validateRemoval(.{ .resource = local });
    const frame = try FrameResourceRef.local(@fromBackingInt(@intCast(3)), local);
    try validateResidency(.{
        .resource = frame,
        .format = .alpha8,
        .size = .{ .width = 2, .height = 1 },
    });
    try validateUploadFact(.{
        .resource = frame,
        .format = .alpha8,
        .size = .{ .width = 2, .height = 1 },
        .pixel_offset = 1,
        .pixel_count = 2,
        .stride = 2,
    }, 3);

    var malformed = local;
    malformed.generation = @fromBackingInt(@intCast(0));
    try std.testing.expectError(
        error.InvalidGeneration,
        validateUpload(.{
            .resource = malformed,
            .format = .alpha8,
            .pixels = .{ .bytes = &.{1}, .width = 1, .height = 1, .stride = 1 },
        }),
    );
    try std.testing.expectError(error.InvalidIdentity, ResourceId.fromEncoded(0));
    var invalid_residency = Residency{
        .resource = frame,
        .format = .rgba8,
        .size = .{ .width = 0, .height = 1 },
    };
    try std.testing.expectError(
        error.ExtentMismatch,
        validateResidency(invalid_residency),
    );
    invalid_residency.size.width = 1;
    invalid_residency.resource.source = @fromBackingInt(@intCast(0));
    try std.testing.expectError(
        error.InvalidIdentity,
        validateResidency(invalid_residency),
    );
    try std.testing.expectError(
        error.ExtentMismatch,
        validateUploadFact(.{
            .resource = frame,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
            .pixel_offset = 0,
            .pixel_count = 3,
            .stride = 4,
        }, 4),
    );
    try validateUpload(.{
        .resource = local,
        .format = .rgba8,
        .pixels = .{
            .bytes = &.{ 1, 2, 3, 4 },
            .width = 1,
            .height = 1,
            .stride = 4,
        },
    });
    try std.testing.expectError(
        error.InvalidPixels,
        validateUpload(.{
            .resource = local,
            .format = .rgba8,
            .pixels = .{
                .bytes = &.{ 1, 2, 3, 4, 5 },
                .width = 1,
                .height = 1,
                .stride = 4,
            },
        }),
    );
}

test "compact resource namespaces preserve phase identity and reject malformed facts" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(ResourceRef));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(FrameResourceRef));
    const local_id = try ResourceId.local(17);
    const shared_id = try ResourceId.shared(17);
    try std.testing.expect(local_id != shared_id);
    try std.testing.expect(!local_id.isShared());
    try std.testing.expect(shared_id.isShared());
    try std.testing.expectEqual(@as(u64, 17), try local_id.identity());
    try std.testing.expectEqual(@as(u64, 17), try shared_id.identity());
    try std.testing.expectError(error.InvalidIdentity, ResourceId.local(0));
    try std.testing.expectError(error.InvalidIdentity, ResourceId.shared(0));
    try std.testing.expectError(
        error.InvalidIdentity,
        ResourceId.local(ResourceId.max_identity + 1),
    );
    try std.testing.expectError(
        error.InvalidIdentity,
        ResourceId.shared(ResourceId.max_identity + 1),
    );

    const generation: ResourceGeneration = @fromBackingInt(@intCast(3));
    const source: SourceId = @fromBackingInt(@intCast(9));
    const local_frame = try FrameResourceRef.local(source, .{
        .resource = local_id,
        .generation = generation,
    });
    const shared_frame = try FrameResourceRef.shared(.{
        .resource = shared_id,
        .generation = generation,
    });
    try local_frame.validate();
    try shared_frame.validate();
    try std.testing.expect(local_frame.source != shared_frame.source);
    try std.testing.expect(local_frame.resource != shared_frame.resource);

    var malformed = local_frame;
    malformed.source = @fromBackingInt(@intCast(0));
    try std.testing.expectError(error.InvalidIdentity, malformed.validate());
    malformed = shared_frame;
    malformed.source = source;
    try std.testing.expectError(error.InvalidIdentity, malformed.validate());
    malformed = local_frame;
    malformed.generation = @fromBackingInt(@intCast(0));
    try std.testing.expectError(error.InvalidGeneration, malformed.validate());
}

test "producer update syntax is canonical and complete" {
    const local = ResourceRef{
        .resource = try ResourceId.local(4),
        .generation = @fromBackingInt(@intCast(7)),
    };
    const upload = ResourceUpload{
        .resource = local,
        .format = .alpha8,
        .pixels = .{ .bytes = &.{255}, .width = 1, .height = 1, .stride = 1 },
    };
    const command = Input{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = local,
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    } };
    try validateProducerUpdate(.{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{upload},
        .removals = &.{},
        .commands = &.{command},
    });
    try std.testing.expectError(
        error.InvalidRevision,
        validateProducerUpdate(.{
            .revision = @fromBackingInt(@intCast(0)),
            .uploads = &.{upload},
            .removals = &.{},
            .commands = &.{command},
        }),
    );
    var malformed = upload;
    malformed.pixels.width = 0;
    try std.testing.expectError(
        error.ExtentMismatch,
        validateProducerUpdate(.{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{malformed},
            .removals = &.{},
            .commands = &.{command},
        }),
    );
    malformed = upload;
    malformed.pixels.bytes = &.{ 255, 0 };
    try std.testing.expectError(
        error.ExtentMismatch,
        validateProducerUpdate(.{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{malformed},
            .removals = &.{},
            .commands = &.{command},
        }),
    );
}

const ComposerRetainedSnapshot = struct {
    source: Composer.Source,
    resource: Composer.Resource,
    command: Input,
    pixels: [1]u8,
    source_count: usize,
    resource_count: usize,
    command_count: usize,
    pixel_count: usize,
    next_source_id: u64,
    frame_revision: u64,
};

fn composerRetainedSnapshot(composer: *const Composer) ComposerRetainedSnapshot {
    return .{
        .source = composer.sources[0],
        .resource = composer.resources[0],
        .command = composer.commands[0],
        .pixels = .{composer.pixels[0]},
        .source_count = composer.source_count,
        .resource_count = composer.resource_count,
        .command_count = composer.command_count,
        .pixel_count = composer.pixel_count,
        .next_source_id = composer.next_source_id,
        .frame_revision = composer.frame_revision,
    };
}

fn expectComposerRetained(
    expected: ComposerRetainedSnapshot,
    composer: *const Composer,
) !void {
    try std.testing.expectEqualDeep(expected, composerRetainedSnapshot(composer));
}

test "composer rejects shared producer facts without retained mutation" {
    var composer = try Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 2,
        .retained_commands = 2,
        .retained_pixel_bytes = 2,
        .composition_sources = 1,
        .candidate_resources = 2,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 2,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    const local_one = ResourceRef{
        .resource = try ResourceId.local(1),
        .generation = @fromBackingInt(1),
    };
    const baseline_upload = ResourceUpload{
        .resource = local_one,
        .format = .alpha8,
        .pixels = .{
            .bytes = &.{0x5a},
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    const baseline_command = Input{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = local_one,
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    } };
    try composer.apply(source, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{baseline_upload},
        .removals = &.{},
        .commands = &.{baseline_command},
    });
    try composer.setComposition(.{
        .surface = .{ .width = 1, .height = 1 },
        .sources = &.{.{
            .source = source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        }},
    });
    const before = composerRetainedSnapshot(&composer);
    const shared = ResourceRef{
        .resource = try ResourceId.shared(1),
        .generation = @fromBackingInt(1),
    };
    const shared_upload = ResourceUpload{
        .resource = shared,
        .format = .alpha8,
        .pixels = .{
            .bytes = &.{0xa5},
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    try std.testing.expectError(error.InvalidIdentity, composer.apply(source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{shared_upload},
        .removals = &.{},
        .commands = &.{baseline_command},
    }));
    try expectComposerRetained(before, &composer);

    try std.testing.expectError(error.InvalidIdentity, composer.apply(source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{ResourceRemoval{ .resource = shared }},
        .commands = &.{baseline_command},
    }));
    try expectComposerRetained(before, &composer);

    var alpha_shared = baseline_command;
    alpha_shared.alpha_mask.resource.resource = shared;
    try std.testing.expectError(error.InvalidIdentity, composer.apply(source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{alpha_shared},
    }));
    try expectComposerRetained(before, &composer);

    const rgba_shared = Input{ .rgba = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = shared,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
        },
    } };
    try std.testing.expectError(error.InvalidIdentity, composer.apply(source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{rgba_shared},
    }));
    try expectComposerRetained(before, &composer);

    const local_two = ResourceRef{
        .resource = local_one.resource,
        .generation = @fromBackingInt(2),
    };
    var replacement_upload = baseline_upload;
    replacement_upload.resource = local_two;
    replacement_upload.pixels.bytes = &.{0x7c};
    var replacement_command = baseline_command;
    replacement_command.alpha_mask.resource.resource = local_two;
    try composer.apply(source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{replacement_upload},
        .removals = &.{},
        .commands = &.{replacement_command},
    });
    try std.testing.expectEqual(@as(u64, 2), composer.sources[0].revision);
    try std.testing.expectEqual(@as(u64, 1), composer.sources[0].local_high_water);
    try std.testing.expectEqual(@as(u8, 0x7c), composer.pixels[0]);
    try std.testing.expectEqual(before.frame_revision + 1, composer.frame_revision);
}

test "visible contribution exhaustion rejects only required frame increments" {
    var composer = try Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 2,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    const first = Input{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    try composer.apply(source, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{first},
    });
    const placement = [_]Composer.Placement{.{
        .source = source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    }};
    try composer.setComposition(.{
        .surface = .{ .width = 1, .height = 1 },
        .sources = &placement,
    });
    composer.frame_revision = std.math.maxInt(u64);
    try composer.apply(source, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{first},
    });
    try std.testing.expectEqual(@as(u64, 2), composer.sources[0].revision);
    try std.testing.expectEqual(std.math.maxInt(u64), composer.frame_revision);

    var changed = first;
    changed.solid.color.r = 9;
    try std.testing.expectError(
        error.RevisionExhausted,
        composer.apply(source, .{
            .revision = @fromBackingInt(@intCast(3)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{changed},
        }),
    );
    try std.testing.expectEqual(@as(u64, 2), composer.sources[0].revision);
    try std.testing.expectEqualDeep(first, composer.commands[0]);
    composer.frame_revision = std.math.maxInt(u64) - 1;
    try composer.apply(source, .{
        .revision = @fromBackingInt(@intCast(3)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{changed},
    });
    try std.testing.expectEqual(std.math.maxInt(u64), composer.frame_revision);
}
