//! Owns bounded terminal-thread native font groups and shared font declarations.
//!
//! Every method is terminal-runtime-thread-only. Native maps have stable
//! addresses for the lifetime of an acquired `GroupRef`. Synchronous shaping
//! and raster users must hold a `Borrow`. Shared identities describe terminal
//! font resources only; terminal images remain source-local and are rejected.

const std = @import("std");
const render = struct {
    const canvas = @import("canvas");
    const terminal_text = @import("terminal_text_capability");
};

/// Maximum live pane references admitted by the terminal runtime owner.
const pane_limit: usize = 64;
/// Maximum immutable native groups retained by the bounded owner.
const active_group_limit: usize = 64;
/// Maximum staged native-group candidates in one bounded transition.
const staged_group_limit: usize = 64;
/// Maximum native groups waiting for synchronous-borrow retirement.
const retiring_group_limit: usize = 64;
/// Total fixed native-group slots across active, staged and retiring states.
const group_limit: usize = active_group_limit + staged_group_limit + retiring_group_limit;
/// Maximum source-independent shared resource identities interned by the owner.
const resource_limit: usize = 2048;
/// Maximum declaration batches retained across pool publication.
const batch_limit: usize = 16;
/// Maximum resource mutations represented by one declaration batch.
const mutation_limit: usize = 648;

/// Reports exact native-group construction, admission, identity and retirement failures.
pub const GroupError = render.terminal_text.FontMapInitError || error{
    GroupLimit,
    IdentityExhausted,
    InvalidConfiguration,
    InvalidMetrics,
    InvalidGroup,
    RetirementPending,
};
/// Reports exact shared font-resource validation, admission and retirement failures.
pub const ResourceError = error{
    ResourceLimit,
    IdentityExhausted,
    InvalidResource,
    InvalidIdentity,
    ConflictingResource,
    RetirementPending,
    ArithmeticOverflow,
};
/// Reports exact declaration-batch validation and bounded ownership failures.
pub const BatchError = GroupError || ResourceError || error{ BatchLimit, InvalidBatch, DuplicateResource };

/// Identifies one immutable resolved native group configuration.
pub const GroupKey = struct {
    configuration_generation: u64,
    point_size: f64,
    logical_dpi_x: render.terminal_text.Dpi,
    logical_dpi_y: render.terminal_text.Dpi,

    fn validate(self: GroupKey) GroupError!void {
        if (self.configuration_generation == 0)
            return error.InvalidConfiguration;
        if (!std.math.isFinite(self.point_size) or
            std.math.isNan(self.point_size) or self.point_size <= 0.0)
            return error.InvalidMetrics;
        const native_size = render.terminal_text.PointSize{
            .points = self.point_size,
            .dpi_x = self.logical_dpi_x,
            .dpi_y = self.logical_dpi_y,
        };
        native_size.validate() catch return error.InvalidMetrics;
    }
};

/// Names one exact stable native-group slot generation.
pub const GroupRef = struct {
    slot: u8,
    generation: u64,
};

/// Owns one completely preflighted pane-group replacement until commit/cancel.
pub const PreparedGroupTransition = struct {
    owner: *Owner,
    old: [pane_limit]GroupRef = undefined,
    staged: [pane_limit]GroupRef = undefined,
    count: u8,
    active: bool = true,

    /// Atomically exchanges every old pane claim for its staged replacement.
    pub fn commit(self: *PreparedGroupTransition) void {
        if (!self.active) return;
        self.owner.commitGroupTransition(
            self.old[0..self.count],
            self.staged[0..self.count],
        );
        self.active = false;
    }

    /// Cancels every staged claim without changing accepted pane ownership.
    pub fn deinit(self: *PreparedGroupTransition) void {
        if (!self.active) return;
        var index: usize = self.count;
        while (index != 0) {
            index -= 1;
            self.owner.discardGroup(self.staged[index]) catch
                @panic("preflighted terminal font transition lost staged ownership");
        }
        self.active = false;
    }
};

/// Identifies one exact raster-affecting terminal font resource.
pub const SharedFontResourceKey = union(enum) {
    native: struct {
        configuration_generation: u64,
        point_size: f64,
        logical_dpi_x: render.terminal_text.Dpi,
        logical_dpi_y: render.terminal_text.Dpi,
        font_slot: u4,
        style_slot: u2,
        face_index: u16,
        glyph_index: u32,
        load_flags: u32,
        cell_span: u16,
    },
    generated: struct {
        configuration_generation: u64,
        point_size: f64,
        logical_dpi_x: render.terminal_text.Dpi,
        logical_dpi_y: render.terminal_text.Dpi,
        codepoint: u21,
        cell_span: u16,
        cell_width_px: u16,
        cell_height_px: u16,
        stroke_variant: u8,
    },
    decoration_mask: struct {
        configuration_generation: u64,
        point_size: f64,
        logical_dpi_x: render.terminal_text.Dpi,
        logical_dpi_y: render.terminal_text.Dpi,
        style: u8,
        cell_span: u16,
        cell_width_px: u16,
        cell_height_px: u16,
        thickness_px: u16,
        position_px: i16,
    },

    fn validate(self: SharedFontResourceKey) ResourceError!void {
        switch (self) {
            .native => |value| {
                if (value.configuration_generation == 0 or
                    !validResourceSize(value.point_size, value.logical_dpi_x, value.logical_dpi_y) or
                    value.cell_span == 0)
                    return error.InvalidResource;
            },
            .generated => |value| {
                if (value.configuration_generation == 0 or
                    !validResourceSize(value.point_size, value.logical_dpi_x, value.logical_dpi_y) or
                    value.cell_span == 0 or
                    value.cell_width_px == 0 or
                    value.cell_height_px == 0)
                    return error.InvalidResource;
            },
            .decoration_mask => |value| {
                if (value.configuration_generation == 0 or
                    !validResourceSize(value.point_size, value.logical_dpi_x, value.logical_dpi_y) or
                    value.cell_span == 0 or
                    value.cell_width_px == 0 or
                    value.cell_height_px == 0 or
                    value.thickness_px == 0)
                    return error.InvalidResource;
            },
        }
    }
};

fn validResourceSize(
    point_size: f64,
    dpi_x: render.terminal_text.Dpi,
    dpi_y: render.terminal_text.Dpi,
) bool {
    if (!std.math.isFinite(point_size) or std.math.isNan(point_size) or
        point_size <= 0.0)
        return false;
    const native_size = render.terminal_text.PointSize{
        .points = point_size,
        .dpi_x = dpi_x,
        .dpi_y = dpi_y,
    };
    native_size.validate() catch return false;
    return true;
}

/// Retains identity-independent raster structure for exact declaration checks.
pub const ResourceFacts = struct {
    format: render.canvas.ResourceFormat,
    size: render.canvas.Size,
    stride: usize,
    byte_count: usize,

    /// Derives exact structural format, extent, stride and length facts from one borrowed raster.
    pub fn fromBytes(
        format: render.canvas.ResourceFormat,
        size: render.canvas.Size,
        stride: usize,
        bytes: []const u8,
    ) ResourceError!ResourceFacts {
        if (size.width == 0 or size.height == 0 or stride == 0)
            return error.InvalidResource;
        const channels: usize = switch (format) {
            .alpha8 => 1,
            .rgba8 => 4,
        };
        const row_bytes = std.math.mul(usize, size.width, channels) catch
            return error.ArithmeticOverflow;
        if (stride < row_bytes) return error.InvalidResource;
        const padded = std.math.mul(usize, size.height - 1, stride) catch
            return error.ArithmeticOverflow;
        const required = std.math.add(usize, padded, row_bytes) catch
            return error.ArithmeticOverflow;
        if (required != bytes.len) return error.InvalidResource;
        return .{
            .format = format,
            .size = size,
            .stride = stride,
            .byte_count = bytes.len,
        };
    }
};

/// Identifies one exact pool declaration/reference batch.
pub const BatchIdentity = struct {
    /// Identifies the exact immutable pool reservation.
    reservation_id: u64,
    /// Identifies the pane-local Composer source carrying the references.
    source: render.canvas.SourceId,
    /// Identifies the complete producer update carried by the reservation.
    producer_revision: render.canvas.ProducerRevision,
};

/// Reports fixed-owner allocation failure during initialization.
const InitError = error{OutOfMemory};

const GroupState = enum(u8) { free, candidate, active, retiring };

const NativeGroup = struct {
    state: GroupState = .free,
    key: GroupKey = undefined,
    generation: u64 = 0,
    pane_users: u8 = 0,
    staged_users: u8 = 0,
    borrows: u16 = 0,
    map: ?render.terminal_text.FontMap = null,
};

const ResourceState = enum(u8) { free, interned, accepted, retiring };

const SharedResource = struct {
    state: ResourceState = .free,
    key: SharedFontResourceKey = undefined,
    facts: ResourceFacts = undefined,
    resource: render.canvas.ResourceRef = undefined,
    pane_references: u16 = 0,
    declaration_pins: u8 = 0,
};

const BatchState = enum(u8) { free, reserved, ready_or_draining };

const Batch = struct {
    state: BatchState = .free,
    identity: BatchIdentity = undefined,
    declarations: [mutation_limit]render.canvas.ResourceRef = undefined,
    references: [mutation_limit]render.canvas.ResourceRef = undefined,
    declaration_count: u16 = 0,
    reference_count: u16 = 0,
};

/// Borrows one stable native map until `deinit`.
const Borrow = struct {
    owner: *Owner,
    group: GroupRef,
    map: *render.terminal_text.FontMap,
    active: bool = true,

    /// Ends the synchronous borrow exactly once; repeated cleanup is a no-op.
    fn deinit(self: *Borrow) void {
        if (!self.active) return;
        self.owner.endBorrow(self.group);
        self.active = false;
    }
};

/// Returns one canonical shared identity and whether Composer still requires
/// its exact declaration bytes.
pub const InternedResource = struct {
    resource: render.canvas.ResourceRef,
    declaration_required: bool,
};

/// Borrows one exact active native group while Content constructs a complete
/// terminal update. The Runtime owns the backing Owner and this session.
pub const Producer = struct {
    borrow: Borrow,
    session: u64,

    /// Ends the exact synchronous native-group borrow.
    pub fn deinit(self: *Producer) void {
        self.cancelUpdate();
        self.borrow.deinit();
    }

    /// Commits every resource acquisition performed by one complete update.
    pub fn commitUpdate(self: *Producer) void {
        self.borrow.owner.commitProducerSession(self.session);
    }

    /// Rolls back every resource acquisition from an incomplete update.
    pub fn cancelUpdate(self: *Producer) void {
        self.borrow.owner.cancelProducerSession(self.session);
    }

    /// Interns one native or generated glyph using exact group and raster facts.
    pub fn internGlyph(
        self: *Producer,
        key: render.terminal_text.GlyphKey,
        format: render.canvas.ResourceFormat,
        size: render.canvas.Size,
        stride: usize,
        bytes: []const u8,
    ) ResourceError!InternedResource {
        const group_entry = self.borrow.owner.lookupGroup(self.borrow.group) catch
            return error.InvalidResource;
        if (group_entry.state != .active) return error.InvalidResource;
        const resource_key: SharedFontResourceKey =
            if (comptime @hasField(render.terminal_text.GlyphKey, "generated"))
                switch (key) {
                    .native => |value| nativeResourceKey(group_entry.key, value),
                    .generated => |value| .{ .generated = .{
                        .configuration_generation = group_entry.key.configuration_generation,
                        .point_size = group_entry.key.point_size,
                        .logical_dpi_x = group_entry.key.logical_dpi_x,
                        .logical_dpi_y = group_entry.key.logical_dpi_y,
                        .codepoint = value.codepoint,
                        .cell_span = 1,
                        .cell_width_px = value.width_px,
                        .cell_height_px = value.height_px,
                        .stroke_variant = 0,
                    } },
                }
            else switch (key) {
                .native => |value| nativeResourceKey(group_entry.key, value),
            };
        return self.borrow.owner.internProducerResult(
            self.session,
            resource_key,
            try ResourceFacts.fromBytes(format, size, stride, bytes),
        );
    }

    /// Interns one generated decoration mask using its exact style and geometry.
    pub fn internDecoration(
        self: *Producer,
        style: u8,
        width: u16,
        height: u16,
        thickness: u16,
        position: i16,
        bytes: []const u8,
    ) ResourceError!InternedResource {
        const group_entry = self.borrow.owner.lookupGroup(self.borrow.group) catch
            return error.InvalidResource;
        if (group_entry.state != .active) return error.InvalidResource;
        return self.borrow.owner.internProducerResult(self.session, .{ .decoration_mask = .{
            .configuration_generation = group_entry.key.configuration_generation,
            .point_size = group_entry.key.point_size,
            .logical_dpi_x = group_entry.key.logical_dpi_x,
            .logical_dpi_y = group_entry.key.logical_dpi_y,
            .style = style,
            .cell_span = 1,
            .cell_width_px = width,
            .cell_height_px = height,
            .thickness_px = thickness,
            .position_px = position,
        } }, try ResourceFacts.fromBytes(
            .alpha8,
            .{ .width = width, .height = height },
            width,
            bytes,
        ));
    }

    /// Reports whether the exact shared identity still needs declaration bytes.
    pub fn declarationRequired(
        self: *Producer,
        reference: render.canvas.ResourceRef,
    ) ResourceError!bool {
        const entry = try self.borrow.owner.lookupResource(reference);
        return entry.state != .accepted;
    }

    /// Releases one producer-side pane resource reference.
    pub fn release(
        self: *Producer,
        reference: render.canvas.ResourceRef,
    ) ResourceError!void {
        try self.borrow.owner.releaseResource(reference);
    }

    /// Releases one prevalidated pane reference during an infallible Content commit.
    pub fn releaseCommitted(
        self: *Producer,
        reference: render.canvas.ResourceRef,
    ) void {
        self.borrow.owner.releaseResource(reference) catch
            @panic("committed terminal font resource lost owner identity");
        self.borrow.owner.completeRetiredResources();
    }
};

fn nativeResourceKey(
    group: GroupKey,
    glyph: render.terminal_text.NativeGlyphKey,
) SharedFontResourceKey {
    return .{ .native = .{
        .configuration_generation = group.configuration_generation,
        .point_size = group.point_size,
        .logical_dpi_x = group.logical_dpi_x,
        .logical_dpi_y = group.logical_dpi_y,
        .font_slot = glyph.font.slot,
        .style_slot = @backingInt(glyph.font.style),
        .face_index = glyph.face_index,
        .glyph_index = glyph.glyph_id,
        .load_flags = 0,
        .cell_span = glyph.cell_span,
    } };
}

/// Owns every bounded cross-pane font group, shared identity, and retry batch.
pub const Owner = struct {
    allocator: std.mem.Allocator,
    groups: []NativeGroup,
    resources: []SharedResource,
    batches: []Batch,
    group_generation_high_water: u64 = 0,
    shared_identity_high_water: u64 = 0,
    pane_users_total: u8 = 0,
    active_group_count: u8 = 0,
    staged_group_count: u8 = 0,
    staged_claim_count: u8 = 0,
    retiring_group_count: u8 = 0,
    producer_session_high_water: u64 = 0,
    producer_session: u64 = 0,
    producer_acquisitions: [mutation_limit]render.canvas.ResourceRef = undefined,
    producer_acquisition_count: u16 = 0,

    /// Allocates all fixed owner storage without constructing native groups.
    pub fn init(allocator: std.mem.Allocator) InitError!Owner {
        const groups = try allocator.alloc(NativeGroup, group_limit);
        errdefer allocator.free(groups);
        const resources = try allocator.alloc(SharedResource, resource_limit);
        errdefer allocator.free(resources);
        const batches = try allocator.alloc(Batch, batch_limit);
        @memset(groups, .{});
        @memset(resources, .{});
        @memset(batches, .{});
        return .{
            .allocator = allocator,
            .groups = groups,
            .resources = resources,
            .batches = batches,
        };
    }

    /// Releases batches, resources, and native groups in reverse owner order.
    pub fn deinit(self: *Owner) void {
        if (self.producer_session != 0)
            @panic("terminal font owner deinit with active producer session");
        for (self.groups) |entry| if (entry.borrows != 0)
            @panic("native font owner deinit with live borrow");
        var batch_index = self.batches.len;
        while (batch_index != 0) {
            batch_index -= 1;
            if (self.batches[batch_index].state != .free)
                self.clearBatch(&self.batches[batch_index]);
        }
        for (self.resources) |*entry| entry.state = .free;
        var group_index = self.groups.len;
        while (group_index != 0) {
            group_index -= 1;
            const entry = &self.groups[group_index];
            if (entry.map) |*map| map.deinit();
            entry.* = .{};
        }
        self.allocator.free(self.batches);
        self.allocator.free(self.resources);
        self.allocator.free(self.groups);
        self.* = undefined;
    }

    /// Acquires an equal group or transactionally constructs one candidate.
    pub fn acquireGroup(
        self: *Owner,
        key: GroupKey,
        configs: []const render.terminal_text.FontConfig,
    ) GroupError!GroupRef {
        try key.validate();
        for (self.groups, 0..) |*entry, index| {
            if (entry.state == .active and std.meta.eql(entry.key, key)) {
                if (self.pane_users_total == pane_limit) return error.GroupLimit;
                entry.pane_users += 1;
                self.pane_users_total += 1;
                return .{ .slot = @intCast(index), .generation = entry.generation };
            }
        }
        for (self.groups) |entry| if (entry.state == .candidate and std.meta.eql(entry.key, key))
            return error.GroupLimit;
        if (self.pane_users_total == pane_limit) return error.GroupLimit;
        const candidate = try self.stageGroup(key, configs);
        try self.activateGroup(candidate);
        return candidate;
    }

    /// Constructs one candidate group without exposing it to pane ownership.
    pub fn stageGroup(
        self: *Owner,
        key: GroupKey,
        configs: []const render.terminal_text.FontConfig,
    ) GroupError!GroupRef {
        try key.validate();
        if (!configsMatchGroup(key, configs)) return error.InvalidConfiguration;
        for (self.groups, 0..) |*entry, index| {
            if (entry.state == .active and std.meta.eql(entry.key, key)) {
                if (entry.staged_users == std.math.maxInt(u8) or
                    self.staged_claim_count == staged_group_limit)
                    return error.GroupLimit;
                entry.staged_users += 1;
                self.staged_claim_count += 1;
                return .{
                    .slot = @intCast(index),
                    .generation = entry.generation,
                };
            }
        }
        for (self.groups, 0..) |*entry, index| {
            if (entry.state == .candidate and std.meta.eql(entry.key, key)) {
                if (entry.staged_users == std.math.maxInt(u8) or self.staged_claim_count == staged_group_limit)
                    return error.GroupLimit;
                entry.staged_users += 1;
                self.staged_claim_count += 1;
                return .{ .slot = @intCast(index), .generation = entry.generation };
            }
        }
        if (self.staged_group_count == staged_group_limit or self.staged_claim_count == staged_group_limit)
            return error.GroupLimit;
        const free_index = for (self.groups, 0..) |entry, index| {
            if (entry.state == .free) break index;
        } else return error.GroupLimit;
        if (self.group_generation_high_water == std.math.maxInt(u64))
            return error.IdentityExhausted;
        var candidate = try render.terminal_text.FontMap.init(self.allocator, configs);
        errdefer candidate.deinit();
        const generation = self.group_generation_high_water + 1;
        self.groups[free_index] = .{
            .state = .candidate,
            .key = key,
            .generation = generation,
            .pane_users = 0,
            .staged_users = 1,
            .map = candidate,
        };
        self.group_generation_high_water = generation;
        self.staged_group_count += 1;
        self.staged_claim_count += 1;
        return .{ .slot = @intCast(free_index), .generation = generation };
    }

    /// Cancels one staged claim and releases its native map when the last claim ends.
    pub fn discardGroup(self: *Owner, reference: GroupRef) GroupError!void {
        const entry = try self.lookupGroup(reference);
        if ((entry.state != .candidate and entry.state != .active) or
            entry.staged_users == 0)
            return error.InvalidGroup;
        entry.staged_users -= 1;
        self.staged_claim_count -= 1;
        if (entry.state == .active) return;
        if (entry.staged_users != 0) return;
        if (self.staged_group_count == 0) @panic("staged group count underflow");
        self.staged_group_count -= 1;
        entry.map.?.deinit();
        entry.* = .{};
    }

    /// Commits one staged group as the first pane-owned reference.
    fn activateGroup(self: *Owner, reference: GroupRef) GroupError!void {
        const entry = try self.lookupGroup(reference);
        if (entry.state != .candidate) return error.InvalidGroup;
        if (entry.staged_users > pane_limit - self.pane_users_total) return error.GroupLimit;
        entry.state = .active;
        entry.pane_users = entry.staged_users;
        self.staged_claim_count -= entry.staged_users;
        entry.staged_users = 0;
        self.staged_group_count -= 1;
        self.active_group_count += 1;
        self.pane_users_total += entry.pane_users;
    }

    /// Releases one pane reference; zero-user groups retire eagerly.
    pub fn releaseGroup(self: *Owner, reference: GroupRef) GroupError!void {
        const entry = try self.lookupGroup(reference);
        if (entry.pane_users == 0) return error.InvalidGroup;
        if (entry.pane_users == 1 and entry.borrows != 0 and self.retiring_group_count == retiring_group_limit)
            return error.RetirementPending;
        entry.pane_users -= 1;
        self.pane_users_total -= 1;
        self.maybeRetireGroup(entry);
    }

    /// Returns the stable map owned by one active pane reference.
    pub fn mapFor(
        self: *Owner,
        reference: GroupRef,
    ) GroupError!*render.terminal_text.FontMap {
        const entry = try self.lookupGroup(reference);
        if (entry.state != .active or entry.pane_users == 0)
            return error.InvalidGroup;
        return &entry.map.?;
    }

    /// Copies the immutable identity key for one active pane group.
    pub fn keyFor(self: *Owner, reference: GroupRef) GroupError!GroupKey {
        const entry = try self.lookupGroup(reference);
        if (entry.state != .active or entry.pane_users == 0)
            return error.InvalidGroup;
        return entry.key;
    }

    /// Returns the stable map owned by one exact staged pane claim.
    pub fn stagedMapFor(
        self: *Owner,
        reference: GroupRef,
    ) GroupError!*render.terminal_text.FontMap {
        const entry = try self.lookupGroup(reference);
        if ((entry.state != .candidate and entry.state != .active) or
            entry.staged_users == 0)
            return error.InvalidGroup;
        return &entry.map.?;
    }

    /// Preflights one complete fixed pane-group exchange without mutation.
    pub fn prepareGroupTransition(
        self: *Owner,
        old: []const GroupRef,
        staged: []const GroupRef,
    ) GroupError!PreparedGroupTransition {
        if (old.len != staged.len or old.len > pane_limit)
            return error.GroupLimit;
        var old_counts: [group_limit]u8 = @splat(0);
        var staged_counts: [group_limit]u8 = @splat(0);
        for (old) |reference| {
            const entry = try self.lookupGroup(reference);
            if (entry.state != .active or entry.pane_users == 0)
                return error.InvalidGroup;
            old_counts[reference.slot] = std.math.add(
                u8,
                old_counts[reference.slot],
                1,
            ) catch return error.GroupLimit;
        }
        for (staged) |reference| {
            const entry = try self.lookupGroup(reference);
            if ((entry.state != .active and entry.state != .candidate) or
                entry.staged_users == 0)
                return error.InvalidGroup;
            staged_counts[reference.slot] = std.math.add(
                u8,
                staged_counts[reference.slot],
                1,
            ) catch return error.GroupLimit;
        }
        var added_retiring: usize = 0;
        for (self.groups, 0..) |entry, index| {
            if (old_counts[index] > entry.pane_users or
                staged_counts[index] > entry.staged_users)
                return error.InvalidGroup;
            if (entry.state == .candidate and
                staged_counts[index] != entry.staged_users)
                return error.InvalidGroup;
            if (entry.state != .active) continue;
            const retained = entry.pane_users - old_counts[index];
            const final = std.math.add(
                u8,
                retained,
                staged_counts[index],
            ) catch return error.GroupLimit;
            if (final == 0 and entry.borrows != 0)
                added_retiring += 1;
        }
        if (added_retiring > retiring_group_limit - self.retiring_group_count)
            return error.RetirementPending;
        var result = PreparedGroupTransition{
            .owner = self,
            .count = @intCast(old.len),
        };
        @memcpy(result.old[0..old.len], old);
        @memcpy(result.staged[0..staged.len], staged);
        return result;
    }

    /// Borrows the resource-production authority for one active pane group.
    pub fn producer(
        self: *Owner,
        reference: GroupRef,
    ) GroupError!Producer {
        if (self.producer_session_high_water == std.math.maxInt(u64))
            return error.IdentityExhausted;
        const borrow_value = try self.borrow(reference);
        self.producer_session_high_water += 1;
        return .{
            .borrow = borrow_value,
            .session = self.producer_session_high_water,
        };
    }

    /// Reserves exact declaration and complete-reference ownership for one
    /// canonical Content update before immutable pool publication.
    pub fn prepareBatch(
        self: *Owner,
        identity: BatchIdentity,
        group: GroupRef,
        update: render.canvas.ProducerUpdate,
    ) BatchError!void {
        var declarations: [mutation_limit]render.canvas.ResourceRef = undefined;
        var references: [mutation_limit]render.canvas.ResourceRef = undefined;
        var declaration_count: usize = 0;
        var reference_count: usize = 0;
        for (update.uploads) |upload| {
            if (!upload.resource.resource.isShared()) continue;
            if (declaration_count == declarations.len) return error.BatchLimit;
            declarations[declaration_count] = upload.resource;
            declaration_count += 1;
        }
        for (update.commands) |command| {
            const reference = switch (command) {
                .solid => continue,
                .alpha_mask => |value| value.resource.resource,
                .rgba => |value| value.resource.resource,
            };
            if (!reference.resource.isShared() or
                containsRef(references[0..reference_count], reference))
                continue;
            if (reference_count == references.len) return error.BatchLimit;
            references[reference_count] = reference;
            reference_count += 1;
        }
        const slot = try self.reserveBatch(
            identity,
            group,
            declarations[0..declaration_count],
            references[0..reference_count],
        );
        std.debug.assert(slot < self.batches.len);
    }

    /// Transfers exact retry ownership to immutable ready/draining pool bytes.
    pub fn markBatchReady(
        self: *Owner,
        identity: BatchIdentity,
    ) BatchError!void {
        try self.markReady(identity);
    }

    /// Cancels one exact pre-ready declaration batch after publication fails.
    pub fn cancelBatchBeforeReady(
        self: *Owner,
        identity: BatchIdentity,
    ) BatchError!void {
        try self.cancelBeforeReady(identity);
        self.completeRetiredResources();
    }

    /// Reconciles the exact accepted source revision without inferring
    /// declaration acceptance from an unrelated monotonic revision.
    pub fn observeAccepted(
        self: *Owner,
        source: render.canvas.SourceId,
        revision: render.canvas.ProducerRevision,
    ) BatchError!void {
        var exact: ?*Batch = null;
        for (self.batches) |*batch| {
            if (batch.state == .ready_or_draining and
                batch.identity.source == source and
                batch.identity.producer_revision == revision)
            {
                exact = batch;
                break;
            }
        }
        const accepted = exact orelse {
            for (self.batches) |batch|
                if (batch.state != .free and batch.identity.source == source and
                    @backingInt(batch.identity.producer_revision) <=
                        @backingInt(revision))
                    return error.InvalidBatch;
            return;
        };
        for (accepted.declarations[0..accepted.declaration_count]) |reference|
            (try self.lookupResource(reference)).state = .accepted;
        for (self.batches) |*batch| {
            if (batch.state == .free or batch.identity.source != source or
                @backingInt(batch.identity.producer_revision) >
                    @backingInt(revision))
                continue;
            self.clearBatch(batch);
        }
        self.completeRetiredResources();
    }

    /// Cancels every exact batch owned by one retiring pane source.
    pub fn cancelSourceBatches(
        self: *Owner,
        source: render.canvas.SourceId,
    ) void {
        for (self.batches) |*batch|
            if (batch.state != .free and batch.identity.source == source)
                self.clearBatch(batch);
        self.completeRetiredResources();
    }

    /// Begins one synchronous shaping/raster borrow.
    fn borrow(self: *Owner, reference: GroupRef) GroupError!Borrow {
        const entry = try self.lookupGroup(reference);
        if (entry.state != .active or entry.borrows == std.math.maxInt(u16))
            return error.RetirementPending;
        entry.borrows += 1;
        return .{ .owner = self, .group = reference, .map = &entry.map.? };
    }

    /// Interns one exact resource without retaining its raster bytes.
    fn intern(
        self: *Owner,
        key: SharedFontResourceKey,
        facts: ResourceFacts,
    ) ResourceError!render.canvas.ResourceRef {
        try key.validate();
        for (self.resources) |*entry| {
            if (entry.state == .free or !std.meta.eql(entry.key, key))
                continue;
            if (!std.meta.eql(entry.facts, facts))
                return error.ConflictingResource;
            if (entry.state == .retiring) return error.RetirementPending;
            if (entry.pane_references == std.math.maxInt(u16))
                return error.ResourceLimit;
            entry.pane_references += 1;
            return entry.resource;
        }
        const free_index = for (self.resources, 0..) |resource, index| {
            if (resource.state == .free) break index;
        } else return error.ResourceLimit;
        if (self.shared_identity_high_water == render.canvas.ResourceId.max_identity)
            return error.IdentityExhausted;
        const next = self.shared_identity_high_water + 1;
        const id = render.canvas.ResourceId.shared(next) catch
            return error.IdentityExhausted;
        self.resources[free_index] = .{
            .state = .interned,
            .key = key,
            .facts = facts,
            .resource = .{
                .resource = id,
                .generation = @fromBackingInt(1),
            },
            .pane_references = 1,
        };
        self.shared_identity_high_water = next;
        return self.resources[free_index].resource;
    }

    fn internProducerResult(
        self: *Owner,
        session: u64,
        key: SharedFontResourceKey,
        facts: ResourceFacts,
    ) ResourceError!InternedResource {
        if (self.producer_session != 0 and self.producer_session != session)
            return error.RetirementPending;
        if (self.producer_acquisition_count == mutation_limit)
            return error.ResourceLimit;
        const reference = try self.intern(key, facts);
        if (self.producer_session == 0) self.producer_session = session;
        self.producer_acquisitions[self.producer_acquisition_count] = reference;
        self.producer_acquisition_count += 1;
        const entry = try self.lookupResource(reference);
        return .{
            .resource = reference,
            .declaration_required = entry.state != .accepted,
        };
    }

    fn commitProducerSession(self: *Owner, session: u64) void {
        if (self.producer_session == 0) return;
        if (self.producer_session != session)
            @panic("terminal font producer committed another session");
        self.producer_session = 0;
        self.producer_acquisition_count = 0;
    }

    fn cancelProducerSession(self: *Owner, session: u64) void {
        if (self.producer_session == 0) return;
        if (self.producer_session != session) return;
        var index: usize = self.producer_acquisition_count;
        while (index != 0) {
            index -= 1;
            self.releaseResource(self.producer_acquisitions[index]) catch
                @panic("terminal font producer rollback lost an acquisition");
        }
        self.producer_session = 0;
        self.producer_acquisition_count = 0;
        self.completeRetiredResources();
    }

    /// Releases one producer-side pane reference only.
    fn releaseResource(
        self: *Owner,
        reference: render.canvas.ResourceRef,
    ) ResourceError!void {
        const entry = try self.lookupResource(reference);
        if (entry.pane_references == 0) return error.InvalidResource;
        entry.pane_references -= 1;
        maybeRetireResource(entry);
    }

    /// Completes zero-reference shared-resource retirement and releases its slot.
    fn completeResourceRetirement(
        self: *Owner,
        reference: render.canvas.ResourceRef,
    ) ResourceError!void {
        const entry = try self.lookupResource(reference);
        if (entry.state != .retiring or entry.pane_references != 0 or entry.declaration_pins != 0)
            return error.RetirementPending;
        entry.* = .{};
    }

    /// Reserves one exact declaration/reference batch before pool readiness.
    fn reserveBatch(
        self: *Owner,
        identity: BatchIdentity,
        group_ref: GroupRef,
        declarations: []const render.canvas.ResourceRef,
        references: []const render.canvas.ResourceRef,
    ) BatchError!usize {
        if (identity.reservation_id == 0 or
            @backingInt(identity.source) == 0 or
            @backingInt(identity.producer_revision) == 0)
            return error.InvalidBatch;
        if (declarations.len > mutation_limit or references.len > mutation_limit)
            return error.BatchLimit;
        for (declarations, 0..) |declaration, index| {
            if (containsRef(declarations[0..index], declaration)) return error.DuplicateResource;
            if (!containsRef(references, declaration)) return error.InvalidBatch;
        }
        for (references, 0..) |reference, index| {
            if (containsRef(references[0..index], reference)) return error.DuplicateResource;
        }
        for (self.batches) |batch|
            if (batch.state != .free and
                std.meta.eql(batch.identity, identity))
                return error.InvalidBatch;
        const free_index = for (self.batches, 0..) |batch, index| {
            if (batch.state == .free) break index;
        } else return error.BatchLimit;
        for (declarations) |reference| {
            const entry = try self.lookupResource(reference);
            if (entry.state != .interned and entry.state != .accepted)
                return error.InvalidBatch;
            if (entry.declaration_pins == std.math.maxInt(u8))
                return error.BatchLimit;
        }
        for (references) |reference| {
            const entry = try self.lookupResource(reference);
            if (entry.state != .interned and entry.state != .accepted)
                return error.InvalidBatch;
            if (entry.state != .accepted and !containsRef(declarations, reference))
                return error.InvalidBatch;
        }
        const entry = try self.lookupGroup(group_ref);
        if (entry.state != .active) return error.InvalidBatch;
        for (declarations) |reference|
            if (!resourceMatchesGroup((try self.lookupResource(reference)).key, entry.key))
                return error.InvalidBatch;
        for (references) |reference|
            if (!resourceMatchesGroup((try self.lookupResource(reference)).key, entry.key))
                return error.InvalidBatch;

        const batch_entry = &self.batches[free_index];
        batch_entry.* = .{
            .state = .reserved,
            .identity = identity,
            .declaration_count = @intCast(declarations.len),
            .reference_count = @intCast(references.len),
        };
        @memcpy(batch_entry.declarations[0..declarations.len], declarations);
        @memcpy(batch_entry.references[0..references.len], references);
        for (declarations) |reference|
            (try self.lookupResource(reference)).declaration_pins += 1;
        return free_index;
    }

    /// Marks the exact batch as owned by immutable ready/draining pool bytes.
    fn markReady(self: *Owner, identity: BatchIdentity) BatchError!void {
        const entry = try self.lookupBatch(identity);
        if (entry.state != .reserved) return error.InvalidBatch;
        entry.state = .ready_or_draining;
    }

    /// Cancels only a pre-ready batch and marks declarations for reraster.
    fn cancelBeforeReady(self: *Owner, identity: BatchIdentity) BatchError!void {
        const entry = try self.lookupBatch(identity);
        if (entry.state != .reserved) return error.InvalidBatch;
        self.clearBatch(entry);
    }

    /// Leaves an exact ready/draining batch unchanged after Composer rejection.
    fn observeRejection(self: *Owner, identity: BatchIdentity) BatchError!void {
        const entry = try self.lookupBatch(identity);
        if (entry.state != .ready_or_draining) return error.InvalidBatch;
    }

    /// Reconciles only an exactly accepted source/revision and complete sets.
    fn reconcileAcceptance(
        self: *Owner,
        identity: BatchIdentity,
        declarations: []const render.canvas.ResourceRef,
        references: []const render.canvas.ResourceRef,
    ) BatchError!void {
        const entry = try self.lookupBatch(identity);
        if (entry.state != .ready_or_draining or
            !refsEqual(entry.declarations[0..entry.declaration_count], declarations) or
            !refsEqual(entry.references[0..entry.reference_count], references))
            return error.InvalidBatch;
        for (declarations) |reference| {
            const resource_entry = try self.lookupResource(reference);
            resource_entry.state = .accepted;
        }
        self.clearBatch(entry);
    }

    fn endBorrow(self: *Owner, reference: GroupRef) void {
        const entry = self.lookupGroup(reference) catch
            @panic("native font borrow outlived its exact group");
        if (entry.borrows == 0)
            @panic("native font borrow released twice");
        entry.borrows -= 1;
        self.maybeRetireGroup(entry);
    }

    fn lookupGroup(self: *Owner, reference: GroupRef) GroupError!*NativeGroup {
        if (reference.slot >= self.groups.len) return error.InvalidGroup;
        const entry = &self.groups[reference.slot];
        if (entry.state == .free or entry.generation != reference.generation)
            return error.InvalidGroup;
        return entry;
    }

    fn lookupResource(
        self: *Owner,
        reference: render.canvas.ResourceRef,
    ) ResourceError!*SharedResource {
        if (!reference.resource.isShared() or
            @backingInt(reference.generation) == 0)
            return error.InvalidIdentity;
        for (self.resources) |*entry|
            if (entry.state != .free and
                std.meta.eql(entry.resource, reference))
                return entry;
        return error.InvalidIdentity;
    }

    fn lookupBatch(self: *Owner, identity: BatchIdentity) BatchError!*Batch {
        for (self.batches) |*entry|
            if (entry.state != .free and std.meta.eql(entry.identity, identity))
                return entry;
        return error.InvalidBatch;
    }

    fn clearBatch(self: *Owner, entry: *Batch) void {
        for (entry.declarations[0..entry.declaration_count]) |reference| {
            const resource_entry = self.lookupResource(reference) catch
                @panic("batch declaration lost its exact resource");
            if (resource_entry.declaration_pins == 0)
                @panic("batch declaration pin released twice");
            resource_entry.declaration_pins -= 1;
            maybeRetireResource(resource_entry);
        }
        entry.* = .{};
    }

    fn completeRetiredResources(self: *Owner) void {
        for (self.resources) |*entry| {
            if (entry.state == .retiring and entry.pane_references == 0 and
                entry.declaration_pins == 0)
                entry.* = .{};
        }
    }

    fn commitGroupTransition(
        self: *Owner,
        old: []const GroupRef,
        staged: []const GroupRef,
    ) void {
        var old_counts: [group_limit]u8 = @splat(0);
        var staged_counts: [group_limit]u8 = @splat(0);
        for (old) |reference| old_counts[reference.slot] += 1;
        for (staged) |reference| staged_counts[reference.slot] += 1;

        for (self.groups, 0..) |*entry, index| {
            if (entry.state != .active) continue;
            entry.pane_users -= old_counts[index];
            entry.pane_users += staged_counts[index];
            entry.staged_users -= staged_counts[index];
            self.staged_claim_count -= staged_counts[index];
        }
        for (self.groups) |*entry|
            if (entry.state == .active and entry.pane_users == 0)
                self.maybeRetireGroup(entry);
        for (self.groups, 0..) |*entry, index| {
            if (entry.state != .candidate) continue;
            const claims = staged_counts[index];
            if (claims == 0) continue;
            entry.state = .active;
            entry.pane_users = claims;
            entry.staged_users = 0;
            self.staged_claim_count -= claims;
            self.staged_group_count -= 1;
            self.active_group_count += 1;
        }
    }

    fn maybeRetireGroup(self: *Owner, entry: *NativeGroup) void {
        if (entry.pane_users != 0) return;
        if (entry.borrows != 0) {
            entry.state = .retiring;
            if (self.active_group_count == 0) @panic("active group count underflow");
            self.active_group_count -= 1;
            self.retiring_group_count += 1;
            return;
        }
        const was_retiring = entry.state == .retiring;
        entry.map.?.deinit();
        if (was_retiring) {
            if (self.retiring_group_count == 0) @panic("retiring group count underflow");
            self.retiring_group_count -= 1;
        } else {
            if (self.active_group_count == 0) @panic("active group count underflow");
            self.active_group_count -= 1;
        }
        entry.* = .{};
    }

    fn maybeRetireResource(entry: *SharedResource) void {
        if (entry.pane_references != 0 or entry.declaration_pins != 0)
            return;
        entry.state = .retiring;
    }
};

fn configsMatchGroup(
    key: GroupKey,
    configs: []const render.terminal_text.FontConfig,
) bool {
    if (configs.len == 0) return false;
    for (configs) |config| switch (config.native.size) {
        .pixels => return false,
        .points => |value| {
            if (value.points != key.point_size or
                !std.meta.eql(value.dpi_x, key.logical_dpi_x) or
                !std.meta.eql(value.dpi_y, key.logical_dpi_y))
                return false;
        },
    };
    return true;
}

fn refsEqual(
    expected: []const render.canvas.ResourceRef,
    actual: []const render.canvas.ResourceRef,
) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |left, right|
        if (!std.meta.eql(left, right)) return false;
    return true;
}

fn containsRef(haystack: []const render.canvas.ResourceRef, needle: render.canvas.ResourceRef) bool {
    for (haystack) |candidate| if (std.meta.eql(candidate, needle)) return true;
    return false;
}

fn resourceMatchesGroup(resource_key: SharedFontResourceKey, group_key: GroupKey) bool {
    const generation = switch (resource_key) {
        .native => |value| value.configuration_generation,
        .generated => |value| value.configuration_generation,
        .decoration_mask => |value| value.configuration_generation,
    };
    const point_size = switch (resource_key) {
        .native => |value| value.point_size,
        .generated => |value| value.point_size,
        .decoration_mask => |value| value.point_size,
    };
    const dpi_x = switch (resource_key) {
        .native => |value| value.logical_dpi_x,
        .generated => |value| value.logical_dpi_x,
        .decoration_mask => |value| value.logical_dpi_x,
    };
    const dpi_y = switch (resource_key) {
        .native => |value| value.logical_dpi_y,
        .generated => |value| value.logical_dpi_y,
        .decoration_mask => |value| value.logical_dpi_y,
    };
    return generation == group_key.configuration_generation and
        point_size == group_key.point_size and
        std.meta.eql(dpi_x, group_key.logical_dpi_x) and
        std.meta.eql(dpi_y, group_key.logical_dpi_y);
}

const test_facts = if (@import("builtin").is_test)
    struct {
        const font_path = "testdata/primary.ttf";
    }
else
    struct {};

fn testConfigs(point_size: u16) [4]render.terminal_text.FontConfig {
    return testConfigsAt(
        point_size,
        .{ .numerator = 96, .denominator = 1 },
        .{ .numerator = 96, .denominator = 1 },
    );
}

fn testConfigsAt(
    point_size: u16,
    dpi_x: render.terminal_text.Dpi,
    dpi_y: render.terminal_text.Dpi,
) [4]render.terminal_text.FontConfig {
    const size = render.terminal_text.Size{ .points = .{
        .points = @floatFromInt(point_size),
        .dpi_x = dpi_x,
        .dpi_y = dpi_y,
    } };
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{
            .primary = test_facts.font_path,
            .size = size,
        } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{
            .primary = test_facts.font_path,
            .size = size,
        } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{
            .primary = test_facts.font_path,
            .size = size,
        } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{
            .primary = test_facts.font_path,
            .size = size,
        } },
    };
}

fn testGroupKey(point_size: u32) GroupKey {
    return .{
        .configuration_generation = 1,
        .point_size = @floatFromInt(point_size),
        .logical_dpi_x = .{ .numerator = 96, .denominator = 1 },
        .logical_dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
}

fn testResourceKey(glyph: u32) SharedFontResourceKey {
    return testResourceKeyAt(glyph, 16);
}

fn testResourceKeyAt(glyph: u32, point_size: u32) SharedFontResourceKey {
    return .{ .native = .{
        .configuration_generation = 1,
        .point_size = @floatFromInt(point_size),
        .logical_dpi_x = .{ .numerator = 96, .denominator = 1 },
        .logical_dpi_y = .{ .numerator = 96, .denominator = 1 },
        .font_slot = 0,
        .style_slot = 0,
        .face_index = 0,
        .glyph_index = glyph,
        .load_flags = 0,
        .cell_span = 1,
    } };
}

fn testFacts(bytes: []const u8) !ResourceFacts {
    return ResourceFacts.fromBytes(
        .alpha8,
        .{ .width = @intCast(bytes.len), .height = 1 },
        bytes.len,
        bytes,
    );
}

fn batchIdentity(reservation: u64, source: u64, revision: u64) BatchIdentity {
    return .{
        .reservation_id = reservation,
        .source = @fromBackingInt(source),
        .producer_revision = @fromBackingInt(revision),
    };
}

test "equal panes share one native group and one logical resource" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const first_group = try owner.acquireGroup(testGroupKey(16), &configs);
    const second_group = try owner.acquireGroup(testGroupKey(16), &configs);
    try std.testing.expectEqual(first_group, second_group);
    try std.testing.expectEqual(@as(u8, 2), owner.groups[first_group.slot].pane_users);

    const pixels = [_]u8{ 1, 2, 3, 4 };
    const first = try owner.intern(testResourceKey(7), try testFacts(&pixels));
    const second = try owner.intern(testResourceKey(7), try testFacts(&pixels));
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(u16, 2), owner.resources[0].pane_references);
}

test "canonical point and factual DPI keys share exactly without collapse" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const key = testGroupKey(16);
    const first = try owner.acquireGroup(key, &configs);
    const equal = try owner.acquireGroup(key, &configs);
    try std.testing.expectEqual(first, equal);
    var distinct = key;
    distinct.logical_dpi_x = .{ .numerator = 768, .denominator = 5 };
    const distinct_configs = testConfigsAt(
        16,
        distinct.logical_dpi_x,
        distinct.logical_dpi_y,
    );
    const other = try owner.acquireGroup(distinct, &distinct_configs);
    try std.testing.expect(!std.meta.eql(first, other));
    try std.testing.expectEqual(@as(u8, 2), owner.active_group_count);
}

test "group admission matches complete Render native representability" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    var subunit_dpi = testGroupKey(16);
    subunit_dpi.logical_dpi_y = .{ .numerator = 1, .denominator = 2 };
    try std.testing.expectError(
        error.InvalidMetrics,
        owner.acquireGroup(subunit_dpi, &configs),
    );
    var excessive_pixels = testGroupKey(16);
    excessive_pixels.point_size = 100_000.0;
    try std.testing.expectError(
        error.InvalidMetrics,
        owner.acquireGroup(excessive_pixels, &configs),
    );
    try std.testing.expectEqual(@as(u64, 0), owner.group_generation_high_water);
    try std.testing.expectEqual(@as(u8, 0), owner.active_group_count);
}

test "pane group mutation cannot invalidate another pane" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs_16 = testConfigs(16);
    const configs_17 = testConfigs(17);
    const shared = try owner.acquireGroup(testGroupKey(16), &configs_16);
    const configs_group = try owner.acquireGroup(testGroupKey(16), &configs_16);
    try std.testing.expect(configs_group.generation != 0);
    const changed = try owner.acquireGroup(testGroupKey(17), &configs_17);
    try owner.releaseGroup(shared);
    var old_borrow = try owner.borrow(shared);
    defer old_borrow.deinit();
    try std.testing.expect(old_borrow.map.cellMetrics(.{
        .slot = 0,
        .style = .normal,
    }) != null);
    try std.testing.expect(changed.generation != shared.generation);
}

test "failed candidate construction preserves accepted native group" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const accepted = try owner.acquireGroup(testGroupKey(16), &configs);
    var invalid = testConfigs(17);
    invalid[1].key = invalid[0].key;
    try std.testing.expectError(
        error.DuplicateConfiguration,
        owner.acquireGroup(testGroupKey(17), &invalid),
    );
    var borrow = try owner.borrow(accepted);
    defer borrow.deinit();
    try std.testing.expect(borrow.map.cellMetrics(.{
        .slot = 0,
        .style = .normal,
    }) != null);
}

test "zero-user native retirement waits for synchronous borrow" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const reference = try owner.acquireGroup(testGroupKey(16), &configs);
    var borrow = try owner.borrow(reference);
    try owner.releaseGroup(reference);
    try std.testing.expectEqual(GroupState.retiring, owner.groups[reference.slot].state);
    borrow.deinit();
    try std.testing.expectEqual(GroupState.free, owner.groups[reference.slot].state);
    try std.testing.expectError(error.InvalidGroup, owner.borrow(reference));
}

test "resource conflict and identity exhaustion are transactional" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const first_bytes = [_]u8{ 1, 2, 3, 4 };
    const resource = try owner.intern(
        testResourceKey(9),
        try testFacts(&first_bytes),
    );
    const before = owner.resources[0];
    const conflicting_facts = try ResourceFacts.fromBytes(
        .rgba8,
        .{ .width = 1, .height = 1 },
        4,
        &.{ 1, 2, 3, 4 },
    );
    try std.testing.expectError(
        error.ConflictingResource,
        owner.intern(testResourceKey(9), conflicting_facts),
    );
    try std.testing.expectEqualDeep(before, owner.resources[0]);
    try std.testing.expectEqualDeep(before, owner.resources[0]);
    try std.testing.expectEqual(resource, owner.resources[0].resource);
    const retiring = try owner.intern(testResourceKey(30), try testFacts(&first_bytes));
    try owner.releaseResource(retiring);
    try std.testing.expectEqual(ResourceState.retiring, owner.resources[1].state);
    try std.testing.expectError(error.RetirementPending, owner.intern(testResourceKey(30), try testFacts(&first_bytes)));
    try owner.completeResourceRetirement(retiring);
    const reused = try owner.intern(testResourceKey(31), try testFacts(&first_bytes));
    try std.testing.expect(reused.resource.isShared());
    try std.testing.expect(@backingInt(reused.resource) != @backingInt(retiring.resource));
    try std.testing.expectError(error.InvalidIdentity, owner.releaseResource(retiring));
    owner.shared_identity_high_water = render.canvas.ResourceId.max_identity;
    try std.testing.expectError(error.IdentityExhausted, owner.intern(testResourceKey(10), try testFacts(&first_bytes)));
}

test "exact batches repeat reject and reconcile without false acceptance" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const group = try owner.acquireGroup(testGroupKey(16), &configs);
    const bytes = [_]u8{ 8, 7, 6, 5 };
    const resource = try owner.intern(testResourceKey(11), try testFacts(&bytes));
    const exact = batchIdentity(1, 1, 4);
    const exact_slot = try owner.reserveBatch(exact, group, &.{resource}, &.{resource});
    try std.testing.expectEqual(BatchState.reserved, owner.batches[exact_slot].state);
    try owner.markReady(exact);
    try owner.observeRejection(exact);
    try std.testing.expectEqual(
        BatchState.ready_or_draining,
        (try owner.lookupBatch(exact)).state,
    );

    const superseding = batchIdentity(2, 1, 5);
    const superseding_slot = try owner.reserveBatch(superseding, group, &.{}, &.{});
    try std.testing.expectEqual(BatchState.reserved, owner.batches[superseding_slot].state);
    try owner.markReady(superseding);
    try owner.reconcileAcceptance(superseding, &.{}, &.{});
    try std.testing.expectEqual(
        BatchState.ready_or_draining,
        (try owner.lookupBatch(exact)).state,
    );
    try std.testing.expectEqual(ResourceState.interned, owner.resources[0].state);

    const wrong_source = batchIdentity(1, 2, 4);
    try std.testing.expectError(
        error.InvalidBatch,
        owner.reconcileAcceptance(wrong_source, &.{resource}, &.{resource}),
    );
    try owner.reconcileAcceptance(exact, &.{resource}, &.{resource});
    try std.testing.expectEqual(ResourceState.accepted, owner.resources[0].state);
}

test "sixteen independently accepted sources release batches for a seventeenth" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const group = try owner.acquireGroup(testGroupKey(16), &configs);
    var identities: [batch_limit]BatchIdentity = undefined;
    for (&identities, 0..) |*identity, index| {
        identity.* = batchIdentity(
            @intCast(index + 1),
            @intCast(index + 1),
            1,
        );
        const slot = try owner.reserveBatch(identity.*, group, &.{}, &.{});
        try std.testing.expect(slot < batch_limit);
        try owner.markReady(identity.*);
    }
    try std.testing.expectError(
        error.BatchLimit,
        owner.reserveBatch(batchIdentity(17, 17, 1), group, &.{}, &.{}),
    );
    for (identities) |identity|
        try owner.observeAccepted(identity.source, identity.producer_revision);
    for (owner.batches) |batch|
        try std.testing.expectEqual(BatchState.free, batch.state);
    const seventeenth = batchIdentity(17, 17, 1);
    const slot = try owner.reserveBatch(seventeenth, group, &.{}, &.{});
    try std.testing.expect(slot < batch_limit);
    try owner.markReady(seventeenth);
    try owner.observeAccepted(
        seventeenth.source,
        seventeenth.producer_revision,
    );
}

test "pre-ready cancellation requires recovery while ready rejection retains batch" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const group = try owner.acquireGroup(testGroupKey(16), &configs);
    const bytes = [_]u8{ 3, 1, 4, 1 };
    const resource = try owner.intern(testResourceKey(12), try testFacts(&bytes));
    const cancelled = batchIdentity(1, 1, 1);
    const cancelled_slot = try owner.reserveBatch(cancelled, group, &.{resource}, &.{resource});
    try std.testing.expectEqual(BatchState.reserved, owner.batches[cancelled_slot].state);
    try owner.cancelBeforeReady(cancelled);
    try std.testing.expectError(error.InvalidBatch, owner.lookupBatch(cancelled));

    const ready = batchIdentity(2, 2, 1);
    const ready_slot = try owner.reserveBatch(ready, group, &.{resource}, &.{resource});
    try std.testing.expectEqual(BatchState.reserved, owner.batches[ready_slot].state);
    try owner.markReady(ready);
    const before = owner.batches[0];
    try owner.observeRejection(ready);
    try std.testing.expectEqualDeep(before, owner.batches[0]);
}

test "batch and retirement admission reject every invalid ownership form" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const group = try owner.acquireGroup(testGroupKey(16), &configs);
    const bytes = [_]u8{ 1, 2, 3, 4 };
    const first = try owner.intern(testResourceKey(20), try testFacts(&bytes));
    const second = try owner.intern(testResourceKey(21), try testFacts(&bytes));
    try std.testing.expectError(error.DuplicateResource, owner.reserveBatch(batchIdentity(1, 1, 1), group, &.{ first, first }, &.{first}));
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(2, 1, 1), group, &.{first}, &.{}));
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(3, 1, 1), group, &.{}, &.{second}));
    const configs_17 = testConfigs(17);
    const other_active = try owner.acquireGroup(testGroupKey(17), &configs_17);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(7, 1, 1), other_active, &.{first}, &.{first}));
    const configs_99 = testConfigs(99);
    const staged = try owner.stageGroup(testGroupKey(99), &configs_99);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(4, 1, 1), staged, &.{}, &.{}));
    try owner.discardGroup(staged);
    var borrow = try owner.borrow(group);
    try owner.releaseGroup(group);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(5, 1, 1), group, &.{}, &.{}));
    borrow.deinit();
    const active_group = try owner.acquireGroup(testGroupKey(17), &configs_17);
    try owner.releaseResource(second);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(6, 1, 1), active_group, &.{second}, &.{second}));
    try owner.completeResourceRetirement(second);
}

test "fixed owner memory and declaration bounds are exact" {
    try std.testing.expectEqual(@as(usize, 10472), @sizeOf(Owner));
    try std.testing.expectEqual(@as(usize, 192), group_limit);
    try std.testing.expectEqual(@as(usize, 64), active_group_limit);
    try std.testing.expectEqual(@as(usize, 2048), resource_limit);
    try std.testing.expectEqual(@as(usize, 16), batch_limit);
    try std.testing.expectEqual(@as(usize, 648), mutation_limit);
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(SharedFontResourceKey));
    try std.testing.expectEqual(@as(usize, 6200), @sizeOf(NativeGroup));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(SharedResource));
    try std.testing.expectEqual(@as(usize, 20768), @sizeOf(Batch));
    try std.testing.expectEqual(@as(usize, 1735680), @sizeOf(NativeGroup) * group_limit +
        @sizeOf(SharedResource) * resource_limit +
        @sizeOf(Batch) * batch_limit);
    try std.testing.expectEqual(
        @as(usize, 1746152),
        @sizeOf(Owner) +
            @sizeOf(NativeGroup) * group_limit +
            @sizeOf(SharedResource) * resource_limit +
            @sizeOf(Batch) * batch_limit,
    );
    try std.testing.expectEqual(
        @sizeOf(NativeGroup) * group_limit +
            @sizeOf(SharedResource) * resource_limit +
            @sizeOf(Batch) * batch_limit,
        @sizeOf(NativeGroup) * 192 +
            @sizeOf(SharedResource) * 2048 +
            @sizeOf(Batch) * 16,
    );
}

test "capacity cohorts, total pane bound, padded rows and batch bound are explicit" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = testConfigs(16);
    const group = try owner.acquireGroup(testGroupKey(16), &configs);
    var pane_refs: [pane_limit]GroupRef = undefined;
    pane_refs[0] = group;
    var index: usize = 1;
    while (index < pane_limit) : (index += 1)
        pane_refs[index] = try owner.acquireGroup(testGroupKey(16), &configs);
    try std.testing.expectError(error.GroupLimit, owner.acquireGroup(testGroupKey(16), &configs));
    const replacement_configs = testConfigs(17);
    var replacements: [pane_limit]GroupRef = undefined;
    for (&replacements) |*reference|
        reference.* = try owner.stageGroup(
            testGroupKey(17),
            &replacement_configs,
        );
    var transition = try owner.prepareGroupTransition(
        &pane_refs,
        &replacements,
    );
    transition.commit();
    try std.testing.expectEqual(@as(u8, pane_limit), owner.pane_users_total);
    try std.testing.expectEqual(@as(u8, 0), owner.staged_claim_count);
    try std.testing.expectEqual(@as(u8, 1), owner.active_group_count);
    try std.testing.expectError(error.InvalidGroup, owner.mapFor(pane_refs[0]));
    for (replacements) |reference| try owner.releaseGroup(reference);

    const padded = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const padded_facts = try ResourceFacts.fromBytes(.rgba8, .{ .width = 1, .height = 2 }, 5, &padded);
    try std.testing.expectEqual(@as(usize, 9), padded_facts.byte_count);
    try std.testing.expectError(
        error.InvalidResource,
        ResourceFacts.fromBytes(.rgba8, .{ .width = 1, .height = 2 }, 5, padded[0..8]),
    );
    const batch_group = try owner.acquireGroup(testGroupKey(16), &configs);
    const one_byte = [_]u8{7};
    const one_facts = try testFacts(&one_byte);
    var resource_index: usize = 0;
    while (resource_index < resource_limit) : (resource_index += 1) {
        const key = testResourceKey(@intCast(resource_index + 1000));
        const interned = try owner.intern(key, one_facts);
        if (resource_index == 0) try std.testing.expect(interned.resource.isShared());
    }
    try std.testing.expectError(error.ResourceLimit, owner.intern(testResourceKey(999999), one_facts));
    var batches: [batch_limit]BatchIdentity = undefined;
    var batch_index: usize = 0;
    while (batch_index < batch_limit) : (batch_index += 1) {
        batches[batch_index] = batchIdentity(@intCast(batch_index + 1), 1, @intCast(batch_index + 1));
        const slot = try owner.reserveBatch(batches[batch_index], batch_group, &.{}, &.{});
        try std.testing.expectEqual(BatchState.reserved, owner.batches[slot].state);
    }
    try std.testing.expectError(error.BatchLimit, owner.reserveBatch(batchIdentity(99, 1, 99), batch_group, &.{}, &.{}));
}

test "active staged and retiring cohorts coexist at their exact bounds" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    var active: [active_group_limit]GroupRef = undefined;
    var borrows: [active_group_limit]Borrow = undefined;
    for (&active, 0..) |*slot, index| {
        const point_size: u16 = @intCast(16 + index);
        const configs = testConfigs(point_size);
        slot.* = try owner.acquireGroup(testGroupKey(point_size), &configs);
    }
    for (&active, 0..) |*slot, index| borrows[index] = try owner.borrow(slot.*);
    for (active) |slot| try owner.releaseGroup(slot);
    try std.testing.expectEqual(@as(u8, active_group_limit), owner.retiring_group_count);
    var replacement_active: [active_group_limit]GroupRef = undefined;
    for (&replacement_active, 0..) |*slot, index| {
        const point_size: u16 = @intCast(300 + index);
        const configs = testConfigs(point_size);
        slot.* = try owner.acquireGroup(testGroupKey(point_size), &configs);
    }
    try std.testing.expectEqual(@as(u8, active_group_limit), owner.active_group_count);
    const configs_500 = testConfigs(500);
    const equal_a = try owner.stageGroup(testGroupKey(500), &configs_500);
    const equal_b = try owner.stageGroup(testGroupKey(500), &configs_500);
    try std.testing.expectEqual(equal_a, equal_b);
    try owner.discardGroup(equal_a);
    try owner.discardGroup(equal_b);
    var staged: [staged_group_limit]GroupRef = undefined;
    for (&staged, 0..) |*slot, index| {
        const point_size: u16 = @intCast(100 + index);
        const configs = testConfigs(point_size);
        slot.* = try owner.stageGroup(testGroupKey(point_size), &configs);
    }
    try std.testing.expectEqual(@as(u8, staged_group_limit), owner.staged_group_count);
    try std.testing.expectEqual(@as(u8, retiring_group_limit), owner.retiring_group_count);
    for (staged) |slot| try owner.discardGroup(slot);
    for (&borrows) |*borrow| borrow.deinit();
    try std.testing.expectEqual(@as(u8, 0), owner.retiring_group_count);
}

test "sixty-four distinct groups replace while old declaration batches remain pending" {
    var owner = try Owner.init(std.testing.allocator);
    defer owner.deinit();
    var old: [active_group_limit]GroupRef = undefined;
    var staged: [staged_group_limit]GroupRef = undefined;
    var borrows: [active_group_limit]Borrow = undefined;
    const bytes = [_]u8{1};
    for (&old, 0..) |*reference, index| {
        const point_size: u16 = @intCast(16 + index);
        const configs = testConfigs(point_size);
        reference.* = try owner.acquireGroup(
            testGroupKey(point_size),
            &configs,
        );
        borrows[index] = try owner.borrow(reference.*);
        if (index < batch_limit) {
            const resource = try owner.intern(
                testResourceKeyAt(@intCast(index + 1), point_size),
                try testFacts(&bytes),
            );
            const identity = batchIdentity(
                @intCast(index + 1),
                @intCast(index + 1),
                1,
            );
            const slot = try owner.reserveBatch(
                identity,
                reference.*,
                &.{resource},
                &.{resource},
            );
            try std.testing.expect(slot < batch_limit);
            try owner.markReady(identity);
        }
    }
    for (&staged, 0..) |*reference, index| {
        const point_size: u16 = @intCast(100 + index);
        const configs = testConfigs(point_size);
        reference.* = try owner.stageGroup(
            testGroupKey(point_size),
            &configs,
        );
    }
    try std.testing.expectEqual(@as(u8, 64), owner.active_group_count);
    try std.testing.expectEqual(@as(u8, 64), owner.staged_group_count);
    try std.testing.expectEqual(@as(u8, 0), owner.retiring_group_count);
    var transition = try owner.prepareGroupTransition(&old, &staged);
    transition.commit();
    try std.testing.expectEqual(@as(u8, 64), owner.active_group_count);
    try std.testing.expectEqual(@as(u8, 0), owner.staged_group_count);
    try std.testing.expectEqual(@as(u8, 64), owner.retiring_group_count);
    for (owner.batches[0..batch_limit]) |batch|
        try std.testing.expectEqual(
            BatchState.ready_or_draining,
            batch.state,
        );
    for (&borrows) |*borrow| borrow.deinit();
    try std.testing.expectEqual(@as(u8, 64), owner.active_group_count);
    try std.testing.expectEqual(@as(u8, 0), owner.retiring_group_count);
    for (0..batch_limit) |index|
        try owner.observeAccepted(
            @fromBackingInt(@intCast(index + 1)),
            @fromBackingInt(1),
        );
    for (staged) |reference| try owner.releaseGroup(reference);
}

test "owner allocation failure rolls back every fixed allocation" {
    var failure_index: usize = 0;
    while (failure_index < 3) : (failure_index += 1) {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = failure_index });
        try std.testing.expectError(error.OutOfMemory, Owner.init(failing.allocator()));
    }
    var owner = try Owner.init(std.testing.allocator);
    owner.deinit();
}
