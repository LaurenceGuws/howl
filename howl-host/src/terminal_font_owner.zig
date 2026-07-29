//! Owns bounded terminal-thread native font groups and shared font declarations.
//!
//! Every method is terminal-runtime-thread-only. Native maps have stable
//! addresses for the lifetime of an acquired `GroupRef`. Synchronous shaping
//! and raster users must hold a `Borrow`. Shared identities describe terminal
//! font resources only; terminal images remain source-local and are rejected.

const std = @import("std");
const render = @import("howl_render");

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

const GroupError = render.terminal_text.FontMapInitError || error{
    GroupLimit,
    IdentityExhausted,
    InvalidConfiguration,
    InvalidMetrics,
    InvalidGroup,
    RetirementPending,
};
const ResourceError = error{
    ResourceLimit,
    IdentityExhausted,
    InvalidResource,
    InvalidIdentity,
    ConflictingResource,
    RetirementPending,
    ArithmeticOverflow,
};
const BatchError = GroupError || ResourceError || error{ BatchLimit, InvalidBatch, DuplicateResource };

/// Identifies one immutable resolved native group configuration.
const GroupKey = struct {
    configuration_generation: u64,
    point_size_26_6: u32,
    logical_dpi_x_26_6: u32,
    logical_dpi_y_26_6: u32,

    fn validate(self: GroupKey) GroupError!void {
        if (self.configuration_generation == 0)
            return error.InvalidConfiguration;
        if (self.point_size_26_6 == 0 or
            self.logical_dpi_x_26_6 == 0 or
            self.logical_dpi_y_26_6 == 0)
            return error.InvalidMetrics;
        if (self.point_size_26_6 > std.math.maxInt(i32))
            return error.InvalidMetrics;
    }
};

/// Names one exact stable native-group slot generation.
const GroupRef = struct {
    slot: u8,
    generation: u64,
};

/// Names every currently implemented shared terminal-font raster family.
const SharedFontResourceKey = union(enum) {
    native: struct {
        configuration_generation: u64,
        point_size_26_6: i32,
        logical_dpi_x_26_6: u32,
        logical_dpi_y_26_6: u32,
        style_slot: u2,
        face_index: u16,
        glyph_index: u32,
        load_flags: u32,
        cell_span: u8,
    },
    generated: struct {
        configuration_generation: u64,
        point_size_26_6: i32,
        logical_dpi_x_26_6: u32,
        logical_dpi_y_26_6: u32,
        codepoint: u21,
        cell_span: u8,
        cell_width_px: u16,
        cell_height_px: u16,
        stroke_variant: u8,
    },
    decoration_mask: struct {
        configuration_generation: u64,
        point_size_26_6: i32,
        logical_dpi_x_26_6: u32,
        logical_dpi_y_26_6: u32,
        style: u8,
        cell_span: u8,
        cell_width_px: u16,
        cell_height_px: u16,
        thickness_px: u16,
        position_px: i16,
    },

    fn validate(self: SharedFontResourceKey) ResourceError!void {
        switch (self) {
            .native => |value| {
                if (value.configuration_generation == 0 or
                    value.point_size_26_6 <= 0 or
                    value.logical_dpi_x_26_6 == 0 or value.logical_dpi_y_26_6 == 0 or
                    value.cell_span == 0)
                    return error.InvalidResource;
            },
            .generated => |value| {
                if (value.configuration_generation == 0 or
                    value.point_size_26_6 <= 0 or
                    value.logical_dpi_x_26_6 == 0 or value.logical_dpi_y_26_6 == 0 or
                    value.cell_span == 0 or
                    value.cell_width_px == 0 or
                    value.cell_height_px == 0)
                    return error.InvalidResource;
            },
            .decoration_mask => |value| {
                if (value.configuration_generation == 0 or
                    value.point_size_26_6 <= 0 or
                    value.logical_dpi_x_26_6 == 0 or value.logical_dpi_y_26_6 == 0 or
                    value.cell_span == 0 or
                    value.cell_width_px == 0 or
                    value.cell_height_px == 0 or
                    value.thickness_px == 0)
                    return error.InvalidResource;
            },
        }
    }
};

/// Retains identity-independent raster facts used for exact redeclaration.
const ResourceFacts = struct {
    format: render.canvas.ResourceFormat,
    size: render.canvas.Size,
    stride: usize,
    byte_count: usize,

    /// Derives exact structural format, extent, stride and length facts from one borrowed raster.
    fn fromBytes(
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
const BatchIdentity = struct {
    reservation_id: u64,
    source: render.canvas.SourceId,
    producer_revision: render.canvas.ProducerRevision,
};

/// Reports bounded ownership and exact validation failures.
/// Reports fixed-owner allocation failure during initialization.
const InitError = error{OutOfMemory};

const GroupState = enum(u8) { free, candidate, active, retiring };

const NativeGroup = struct {
    state: GroupState = .free,
    key: GroupKey = undefined,
    generation: u64 = 0,
    pane_users: u8 = 0,
    staged_users: u8 = 0,
    retry_users: u8 = 0,
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
    group: GroupRef = undefined,
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

/// Owns every bounded cross-pane font group, shared identity, and retry batch.
const Owner = struct {
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

    /// Allocates all fixed owner storage without constructing native groups.
    fn init(allocator: std.mem.Allocator) InitError!Owner {
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
    fn deinit(self: *Owner) void {
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
    fn acquireGroup(
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
    fn stageGroup(
        self: *Owner,
        key: GroupKey,
        configs: []const render.terminal_text.FontConfig,
    ) GroupError!GroupRef {
        try key.validate();
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
    fn discardGroup(self: *Owner, reference: GroupRef) GroupError!void {
        const entry = try self.lookupGroup(reference);
        if (entry.state != .candidate or entry.staged_users == 0)
            return error.InvalidGroup;
        entry.staged_users -= 1;
        self.staged_claim_count -= 1;
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
    fn releaseGroup(self: *Owner, reference: GroupRef) GroupError!void {
        const entry = try self.lookupGroup(reference);
        if (entry.pane_users == 0) return error.InvalidGroup;
        if (entry.pane_users == 1 and entry.borrows != 0 and self.retiring_group_count == retiring_group_limit)
            return error.RetirementPending;
        entry.pane_users -= 1;
        self.pane_users_total -= 1;
        self.maybeRetireGroup(entry);
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
        if (entry.retry_users == std.math.maxInt(u8)) return error.BatchLimit;
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
            .group = group_ref,
            .declaration_count = @intCast(declarations.len),
            .reference_count = @intCast(references.len),
        };
        @memcpy(batch_entry.declarations[0..declarations.len], declarations);
        @memcpy(batch_entry.references[0..references.len], references);
        for (declarations) |reference|
            (try self.lookupResource(reference)).declaration_pins += 1;
        entry.retry_users += 1;
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
        const group_entry = self.lookupGroup(entry.group) catch
            @panic("batch lost its exact native group");
        if (group_entry.retry_users == 0)
            @panic("batch native retry pin released twice");
        group_entry.retry_users -= 1;
        self.maybeRetireGroup(group_entry);
        entry.* = .{};
    }

    fn maybeRetireGroup(self: *Owner, entry: *NativeGroup) void {
        if (entry.pane_users != 0 or entry.retry_users != 0) return;
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
        .native => |value| value.point_size_26_6,
        .generated => |value| value.point_size_26_6,
        .decoration_mask => |value| value.point_size_26_6,
    };
    const dpi_x = switch (resource_key) {
        .native => |value| value.logical_dpi_x_26_6,
        .generated => |value| value.logical_dpi_x_26_6,
        .decoration_mask => |value| value.logical_dpi_x_26_6,
    };
    const dpi_y = switch (resource_key) {
        .native => |value| value.logical_dpi_y_26_6,
        .generated => |value| value.logical_dpi_y_26_6,
        .decoration_mask => |value| value.logical_dpi_y_26_6,
    };
    return generation == group_key.configuration_generation and
        point_size == @as(i32, @intCast(group_key.point_size_26_6)) and
        dpi_x == group_key.logical_dpi_x_26_6 and dpi_y == group_key.logical_dpi_y_26_6;
}

const test_facts = if (@import("builtin").is_test)
    struct {
        const font_path = "../howl-render/testdata/primary.ttf";
    }
else
    struct {};

fn testConfigs(pixel_height: u16) [4]render.terminal_text.FontConfig {
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{
            .primary = test_facts.font_path,
            .pixel_height = pixel_height,
        } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{
            .primary = test_facts.font_path,
            .pixel_height = pixel_height,
        } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{
            .primary = test_facts.font_path,
            .pixel_height = pixel_height,
        } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{
            .primary = test_facts.font_path,
            .pixel_height = pixel_height,
        } },
    };
}

fn testGroupKey(point_size: u32) GroupKey {
    return .{
        .configuration_generation = 1,
        .point_size_26_6 = point_size * 64,
        .logical_dpi_x_26_6 = 96 * 64,
        .logical_dpi_y_26_6 = 96 * 64,
    };
}

fn testResourceKey(glyph: u32) SharedFontResourceKey {
    return .{ .native = .{
        .configuration_generation = 1,
        .point_size_26_6 = 16 * 64,
        .logical_dpi_x_26_6 = 96 * 64,
        .logical_dpi_y_26_6 = 96 * 64,
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
    const other_active = try owner.acquireGroup(testGroupKey(17), &configs);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(7, 1, 1), other_active, &.{first}, &.{first}));
    const staged = try owner.stageGroup(testGroupKey(99), &configs);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(4, 1, 1), staged, &.{}, &.{}));
    try owner.discardGroup(staged);
    var borrow = try owner.borrow(group);
    try owner.releaseGroup(group);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(5, 1, 1), group, &.{}, &.{}));
    borrow.deinit();
    const active_group = try owner.acquireGroup(testGroupKey(17), &configs);
    try owner.releaseResource(second);
    try std.testing.expectError(error.InvalidBatch, owner.reserveBatch(batchIdentity(6, 1, 1), active_group, &.{second}, &.{second}));
    try owner.completeResourceRetirement(second);
}

test "fixed owner memory and declaration bounds are exact" {
    try std.testing.expectEqual(@as(usize, 192), group_limit);
    try std.testing.expectEqual(@as(usize, 64), active_group_limit);
    try std.testing.expectEqual(@as(usize, 2048), resource_limit);
    try std.testing.expectEqual(@as(usize, 16), batch_limit);
    try std.testing.expectEqual(@as(usize, 648), mutation_limit);
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(SharedFontResourceKey));
    try std.testing.expectEqual(@as(usize, 4656), @sizeOf(NativeGroup));
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(SharedResource));
    try std.testing.expectEqual(@as(usize, 20784), @sizeOf(Batch));
    try std.testing.expectEqual(@as(usize, 1406720), @sizeOf(NativeGroup) * group_limit +
        @sizeOf(SharedResource) * resource_limit +
        @sizeOf(Batch) * batch_limit);
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
    for (pane_refs) |reference| try owner.releaseGroup(reference);

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
    const configs = testConfigs(16);
    var active: [active_group_limit]GroupRef = undefined;
    var borrows: [active_group_limit]Borrow = undefined;
    for (&active, 0..) |*slot, index| slot.* = try owner.acquireGroup(testGroupKey(@intCast(16 + index)), &configs);
    for (&active, 0..) |*slot, index| borrows[index] = try owner.borrow(slot.*);
    for (active) |slot| try owner.releaseGroup(slot);
    try std.testing.expectEqual(@as(u8, active_group_limit), owner.retiring_group_count);
    var replacement_active: [active_group_limit]GroupRef = undefined;
    for (&replacement_active, 0..) |*slot, index|
        slot.* = try owner.acquireGroup(testGroupKey(@intCast(300 + index)), &configs);
    try std.testing.expectEqual(@as(u8, active_group_limit), owner.active_group_count);
    const equal_a = try owner.stageGroup(testGroupKey(500), &configs);
    const equal_b = try owner.stageGroup(testGroupKey(500), &configs);
    try std.testing.expectEqual(equal_a, equal_b);
    try owner.discardGroup(equal_a);
    try owner.discardGroup(equal_b);
    var staged: [staged_group_limit]GroupRef = undefined;
    for (&staged, 0..) |*slot, index| slot.* = try owner.stageGroup(testGroupKey(@intCast(100 + index)), &configs);
    try std.testing.expectEqual(@as(u8, staged_group_limit), owner.staged_group_count);
    try std.testing.expectEqual(@as(u8, retiring_group_limit), owner.retiring_group_count);
    for (staged) |slot| try owner.discardGroup(slot);
    for (&borrows) |*borrow| borrow.deinit();
    try std.testing.expectEqual(@as(u8, 0), owner.retiring_group_count);
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
