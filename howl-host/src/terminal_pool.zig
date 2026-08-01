//! Owns fixed shared storage for immutable terminal producer updates.
//!
//! The terminal thread exclusively owns descriptors, group admission, block
//! reservation, publication, and retirement. Renderer owns only
//! `beginDrain`, `drainingUpdate`, `retryDrain`, and `completeDrain`. Renderer
//! acquires a ready block before reading immutable metadata and payload and
//! never mutates descriptor storage. Terminal detaches a descriptor only after
//! acquire-observing the associated block as free or atomically claiming ready
//! ownership itself.

const std = @import("std");
const render = @import("howl_render");
const canvas = render.canvas;
const PaneId = render.chrome.PaneId;

const descriptor_limit: usize = 64;
const block_limit: usize = 16;
const resource_limit: usize = 1024;
const command_limit: usize = 32_768;
const pixel_limit: usize = 4 * 1024 * 1024;

/// Reports invalid fixed-layout arithmetic or allocation failure.
pub const InitError = error{
    ArithmeticOverflow,
    OutOfMemory,
};

/// Reports invalid descriptor registration.
pub const RegisterError = error{
    InvalidDescriptor,
    InvalidIdentity,
    Occupied,
};

/// Reports exact ordinary or group block-admission failure.
pub const ReserveError = error{
    Busy,
    DuplicateMember,
    GroupPriority,
    InvalidCandidateRevision,
    InvalidDescriptor,
    InvalidIdentity,
    NoCapacity,
    ReservationExhausted,
    Stale,
};

/// Reports an invalid or stale immutable block transition.
pub const TransitionError = error{
    Busy,
    InvalidCounts,
    InvalidProducerRevision,
    Stale,
};

/// Reports malformed or oversized canonical producer payload publication.
pub const PublishError = TransitionError || error{
    ArithmeticOverflow,
    InvalidPixels,
};

/// Reports a descriptor whose block ownership prevents retirement.
pub const RetireError = error{
    Busy,
    InvalidDescriptor,
    Stale,
};

/// Reports stale or incomplete successful group finalization.
pub const CompleteGroupError = error{
    Partial,
    Stale,
};

/// Tracks one logical terminal descriptor independently of shared blocks.
pub const DescriptorState = enum(u8) {
    inactive,
    live,
    retiring,
    retired,
};

/// Tracks reusable immutable-update block ownership.
pub const BlockState = enum(u8) {
    free,
    reserved,
    ready,
    draining,
};

const GroupPhase = enum(u8) {
    idle,
    prepared,
};

const Descriptor = struct {
    state: std.atomic.Value(u8),
    pane_id: PaneId,
    source_id: canvas.SourceId,
    revision: canvas.ProducerRevision,
    candidate_revision: u64,
    block_index: ?u8,
    upload_count: usize,
    removal_count: usize,
    command_count: usize,
};

const BlockOwner = struct {
    state: std.atomic.Value(u8),
    descriptor_index: u16,
    reserved: [5]u8,
    pane_id: PaneId,
    source_id: canvas.SourceId,
    revision: canvas.ProducerRevision,
    candidate_revision: u64,
    reservation_id: u64,
    upload_count: usize,
    removal_count: usize,
    /// Counts the complete cursor-free command list in the command bank.
    command_count: usize,
    /// Binds the separately composed cursor overlay to its semantic publication.
    cursor_binding: ?canvas.CursorBinding,
};

const PoolMeta = struct {
    candidate_revision: u64,
    candidate_high_water: u64,
    reservation_high_water: u64,
    group_phase: std.atomic.Value(u8),
};

/// Identifies one exact live descriptor required by group reservation.
pub const Member = struct {
    /// Selects one of the fixed descriptor records.
    descriptor_index: u8,
    /// Repeats the globally never-reused pane identity for stale rejection.
    pane_id: PaneId,
    /// Repeats the Composer-issued source identity for stale rejection.
    source_id: canvas.SourceId,
};

/// Identifies one exact reservation across storage reuse.
pub const Token = struct {
    /// Selects the fixed descriptor record.
    descriptor_index: u8,
    /// Selects the reusable block record.
    block_index: u8,
    /// Rejects a token retained across descriptor identity changes.
    pane_id: PaneId,
    /// Rejects a token routed to another Composer source.
    source_id: canvas.SourceId,
    /// Identifies group reservation, or zero for ordinary reservation.
    candidate_revision: u64,
    /// Uniquely identifies this reservation for the complete Pool lifetime.
    reservation_id: u64,
    /// Identifies the immutable producer update after publication.
    producer_revision: canvas.ProducerRevision,
};

/// Owns the tokens created by one all-or-none group reservation.
pub const Group = struct {
    /// Identifies the exact group and prevents stale cancellation.
    candidate_revision: u64,
    /// Contains initialized tokens in the prefix selected by `count`.
    tokens: [block_limit]Token,
    /// Counts the exact reservation group.
    count: u8,
};

/// Reports the deterministic contiguous allocation.
const Layout = struct {
    /// Locates pool state metadata.
    metadata_offset: usize,
    /// Locates all descriptor records.
    descriptors_offset: usize,
    /// Locates the first block owner and payload.
    blocks_offset: usize,
    /// Advances between fixed block records.
    block_stride: usize,
    /// Counts the exact requested backing bytes.
    total: usize,
};

const BlockLayout = struct {
    owner_offset: usize,
    uploads_offset: usize,
    removals_offset: usize,
    commands_offset: usize,
    pixels_offset: usize,
    total: usize,
};

/// Owns one checked contiguous backing allocation for all pool storage.
///
/// The pool must remain at a stable address while tokens are in use. Methods
/// provide the only state transitions; copied structs would duplicate
/// allocation ownership and are forbidden. `deinit` requires every descriptor
/// retired or inactive and every block free, and may be called exactly once.
pub const Pool = struct {
    allocator: std.mem.Allocator,
    backing: []u64,
    layout: Layout,

    /// Allocates and initializes the complete fixed pool transactionally.
    pub fn init(allocator: std.mem.Allocator) InitError!Pool {
        const computed = calculateLayout() catch return error.ArithmeticOverflow;
        if (computed.total % @sizeOf(u64) != 0)
            return error.ArithmeticOverflow;
        const backing = allocator.alloc(
            u64,
            computed.total / @sizeOf(u64),
        ) catch return error.OutOfMemory;
        errdefer allocator.free(backing);
        @memset(backing, 0);
        var self = Pool{
            .allocator = allocator,
            .backing = backing,
            .layout = computed,
        };
        self.initializeRecords();
        return self;
    }

    /// Releases the single backing allocation after reverse owner retirement.
    pub fn deinit(self: *Pool) void {
        for (self.descriptors()) |*descriptor| {
            const state = descriptorState(descriptor);
            std.debug.assert(state == .inactive or state == .retired);
        }
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            std.debug.assert(blockState(owner) == .free);
        }
        self.allocator.free(self.backing);
        self.* = undefined;
    }

    /// Registers one exact descriptor without allocating or consuming a block.
    pub fn register(
        self: *Pool,
        descriptor_index: u8,
        pane_id: PaneId,
        source_id: canvas.SourceId,
    ) RegisterError!void {
        if (!validIdentity(pane_id, source_id)) return error.InvalidIdentity;
        const descriptor = self.descriptorAt(descriptor_index) orelse
            return error.InvalidDescriptor;
        if (descriptorState(descriptor) != .inactive) return error.Occupied;
        descriptor.pane_id = pane_id;
        descriptor.source_id = source_id;
        descriptor.revision = zeroProducerRevision();
        descriptor.candidate_revision = 0;
        descriptor.block_index = null;
        descriptor.upload_count = 0;
        descriptor.removal_count = 0;
        descriptor.command_count = 0;
        descriptor.state.store(@backingInt(DescriptorState.live), .release);
    }

    /// Reserves one ordinary block with a never-reused reservation identity.
    pub fn reserve(
        self: *Pool,
        member: Member,
    ) ReserveError!Token {
        if (groupPhase(self.metaPtr()) != .idle) return error.GroupPriority;
        const descriptor = try self.validateLiveMember(member);
        const reservation_id = try self.nextReservationId(1);
        const block_index = if (descriptor.block_index) |owned| block: {
            if (blockState(self.blockOwner(owned)) != .free) return error.Busy;
            break :block owned;
        } else self.firstUnreferencedFreeBlock() orelse return error.NoCapacity;
        descriptor.block_index = null;
        descriptor.candidate_revision = 0;
        self.metaPtr().reservation_high_water = reservation_id;
        return self.reserveBlock(
            descriptor,
            member,
            block_index,
            0,
            reservation_id,
        );
    }

    /// Preflights the non-member conditions required to reserve the exact
    /// descriptor block immediately after a ready supersession is released.
    /// Boundary calls this while its identity lock is held so discarding a
    /// ready block cannot strand the Runtime's recovery identity behind a
    /// predictable pool admission failure.
    pub fn recoveryReservePossible(self: *Pool) ReserveError!void {
        if (groupPhase(self.metaPtr()) != .idle) return error.GroupPriority;
        const next = self.nextReservationId(1) catch return error.ReservationExhausted;
        std.debug.assert(next != 0);
    }

    /// Reserves one complete validated group or leaves all pool bytes unchanged.
    pub fn reserveGroup(
        self: *Pool,
        candidate_revision: u64,
        members: []const Member,
    ) ReserveError!Group {
        if (candidate_revision == 0) return error.InvalidCandidateRevision;
        if (members.len == 0 or members.len > block_limit)
            return error.InvalidDescriptor;
        const meta = self.metaPtr();
        if (groupPhase(meta) != .idle) return error.GroupPriority;
        if (candidate_revision <= meta.candidate_high_water)
            return error.InvalidCandidateRevision;

        var free_indices: [block_limit]u8 = undefined;
        var selected_count: usize = 0;
        for (members, 0..) |member, index| {
            const descriptor = try self.validateLiveMember(member);
            if (descriptor.block_index) |owned| {
                if (blockState(self.blockOwner(owned)) != .free)
                    return error.Busy;
                free_indices[index] = owned;
                selected_count += 1;
            } else free_indices[index] = noBlockIndex();
            for (members[0..index]) |prior| {
                if (prior.descriptor_index == member.descriptor_index or
                    prior.pane_id == member.pane_id or
                    prior.source_id == member.source_id)
                    return error.DuplicateMember;
            }
        }
        for (members, 0..) |_, member_index| {
            if (free_indices[member_index] != noBlockIndex()) continue;
            for (0..block_limit) |block_index| {
                if (blockState(self.blockOwner(block_index)) == .free and
                    !containsBlock(free_indices[0..members.len], block_index) and
                    !self.blockReferenced(block_index))
                {
                    free_indices[member_index] = @intCast(block_index);
                    selected_count += 1;
                    break;
                }
            }
        }
        if (selected_count < members.len) return error.NoCapacity;
        const first_reservation_id = try self.nextReservationId(members.len);

        meta.candidate_revision = candidate_revision;
        meta.candidate_high_water = candidate_revision;
        meta.reservation_high_water =
            first_reservation_id + @as(u64, @intCast(members.len)) - 1;
        meta.group_phase.store(@backingInt(GroupPhase.prepared), .release);
        var group = Group{
            .candidate_revision = candidate_revision,
            .tokens = std.mem.zeroes([block_limit]Token),
            .count = @intCast(members.len),
        };
        for (members, 0..) |member, index| {
            const descriptor = self.descriptorAt(member.descriptor_index).?;
            descriptor.block_index = null;
            descriptor.candidate_revision = 0;
            group.tokens[index] = self.reserveBlock(
                descriptor,
                member,
                free_indices[index],
                candidate_revision,
                first_reservation_id + @as(u64, @intCast(index)),
            );
        }
        return group;
    }

    /// Cancels exactly one still-reserved group without touching other blocks.
    pub fn cancelGroup(
        self: *Pool,
        candidate_revision: u64,
    ) error{Stale}!void {
        const meta = self.metaPtr();
        if (groupPhase(meta) != .prepared or
            meta.candidate_revision != candidate_revision)
            return error.Stale;
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            if (blockState(owner) == .reserved and
                owner.candidate_revision == candidate_revision)
            {
                const descriptor = self.descriptorAt(
                    @intCast(owner.descriptor_index),
                ) orelse return error.Stale;
                if (descriptor.block_index != @as(u8, @intCast(index)))
                    return error.Stale;
                if (owner.reservation_id == 0) return error.Stale;
            }
        }
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            if (blockState(owner) == .reserved and
                owner.candidate_revision == candidate_revision)
            {
                const descriptor = self.descriptorAt(
                    @intCast(owner.descriptor_index),
                ).?;
                descriptor.block_index = null;
                descriptor.candidate_revision = 0;
                releaseBlock(owner);
            }
        }
        clearGroup(meta);
    }

    /// Finalizes one completely published group without releasing its blocks.
    ///
    /// The terminal thread calls this only after every group member has
    /// published or otherwise left `reserved`. Ready and Renderer-owned
    /// draining blocks remain intact. Partial or stale completion changes no
    /// pool byte and retains group priority.
    pub fn completeGroup(
        self: *Pool,
        candidate_revision: u64,
    ) CompleteGroupError!void {
        const meta = self.metaPtr();
        if (groupPhase(meta) != .prepared or
            meta.candidate_revision != candidate_revision)
            return error.Stale;
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            if (blockState(owner) == .reserved and
                owner.candidate_revision == candidate_revision)
                return error.Partial;
        }
        clearGroup(meta);
    }

    /// Copies and publishes one canonical immutable producer update.
    ///
    /// The complete byte count is checked before payload mutation. Successful
    /// release publication transfers immutable payload ownership to Renderer.
    pub fn publishUpdate(
        self: *Pool,
        token: Token,
        update: canvas.ProducerUpdate,
    ) PublishError!Token {
        const command_count = update.commands.len;
        if (update.uploads.len > resource_limit or
            update.removals.len > resource_limit or
            command_count > command_limit)
            return error.InvalidCounts;
        const descriptor = try self.claimDescriptor(token);
        const owner = try self.claimBlock(token, .reserved);
        if (@backingInt(update.revision) == 0 or
            @backingInt(update.revision) <= @backingInt(descriptor.revision))
            return error.InvalidProducerRevision;
        var pixel_count: usize = 0;
        for (update.uploads) |upload| {
            pixel_count = std.math.add(
                usize,
                pixel_count,
                upload.pixels.bytes.len,
            ) catch return error.ArithmeticOverflow;
            if (pixel_count > pixel_limit) return error.InvalidPixels;
        }
        const uploads = self.blockUploads(token.block_index);
        const removals = self.blockRemovals(token.block_index);
        const commands = self.blockCommands(token.block_index);
        const pixels = self.blockPixels(token.block_index);
        var pixel_offset: usize = 0;
        for (update.uploads, 0..) |upload, index| {
            const source_bytes = upload.pixels.bytes;
            @memcpy(
                pixels[pixel_offset..][0..source_bytes.len],
                source_bytes,
            );
            uploads[index] = upload;
            uploads[index].pixels.bytes =
                pixels[pixel_offset..][0..source_bytes.len];
            pixel_offset += source_bytes.len;
        }
        @memcpy(removals[0..update.removals.len], update.removals);
        @memcpy(commands[0..update.commands.len], update.commands);
        owner.revision = update.revision;
        owner.upload_count = update.uploads.len;
        owner.removal_count = update.removals.len;
        owner.command_count = update.commands.len;
        owner.cursor_binding = update.cursor_binding;
        descriptor.revision = update.revision;
        descriptor.upload_count = update.uploads.len;
        descriptor.removal_count = update.removals.len;
        descriptor.command_count = update.commands.len;
        owner.state.store(@backingInt(BlockState.ready), .release);
        var published = token;
        published.producer_revision = update.revision;
        return published;
    }

    /// Discards one unconsumed terminal reservation without publishing bytes.
    pub fn cancel(
        self: *Pool,
        token: Token,
    ) TransitionError!void {
        const descriptor = try self.claimDescriptor(token);
        std.debug.assert(descriptor.block_index == token.block_index);
        const owner = try self.claimBlock(token, .reserved);
        releaseBlock(owner);
    }

    fn publishMetadata(
        self: *Pool,
        token: Token,
        revision: canvas.ProducerRevision,
        upload_count: usize,
        removal_count: usize,
        command_count: usize,
    ) TransitionError!Token {
        if (upload_count > resource_limit or
            removal_count > resource_limit or
            command_count > command_limit)
            return error.InvalidCounts;
        const descriptor = try self.claimDescriptor(token);
        const owner = try self.claimBlock(token, .reserved);
        if (@backingInt(revision) == 0 or
            @backingInt(revision) <= @backingInt(descriptor.revision))
            return error.InvalidProducerRevision;
        owner.revision = revision;
        owner.upload_count = upload_count;
        owner.removal_count = removal_count;
        owner.command_count = command_count;
        owner.cursor_binding = null;
        descriptor.revision = revision;
        descriptor.upload_count = upload_count;
        descriptor.removal_count = removal_count;
        descriptor.command_count = command_count;
        owner.state.store(@backingInt(BlockState.ready), .release);
        var published = token;
        published.producer_revision = revision;
        return published;
    }

    /// Transfers one exact ready block into Renderer drainage ownership.
    pub fn beginDrain(
        self: *Pool,
        token: Token,
    ) TransitionError!void {
        if (token.block_index >= block_limit) return error.Stale;
        const owner = self.blockOwner(token.block_index);
        const actual = owner.state.cmpxchgStrong(
            @backingInt(BlockState.ready),
            @backingInt(BlockState.draining),
            .acq_rel,
            .acquire,
        );
        if (actual) |state| {
            return if (state == @backingInt(BlockState.draining))
                error.Busy
            else
                error.Stale;
        }
        errdefer owner.state.store(@backingInt(BlockState.ready), .release);
        try validateClaimedBlock(owner, token);
        if (@backingInt(token.producer_revision) == 0 or
            owner.revision != token.producer_revision)
            return error.Stale;
    }

    /// Borrows one ready update for ownership validation without changing its
    /// producer-owned state. The borrow ends when the caller discards or
    /// drains the exact token.
    pub fn readyUpdate(
        self: *Pool,
        token: Token,
    ) TransitionError!canvas.ProducerUpdate {
        const owner = try self.claimBlock(token, .ready);
        if (owner.revision != token.producer_revision)
            return error.Stale;
        return .{
            .revision = owner.revision,
            .uploads = self.blockUploads(token.block_index)[0..owner.upload_count],
            .removals = self.blockRemovals(token.block_index)[0..owner.removal_count],
            .commands = self.blockCommands(token.block_index)[0..owner.command_count],
            .cursor_binding = owner.cursor_binding,
        };
    }

    /// Releases one ready update that a newer semantic target superseded
    /// before Composer acceptance.
    pub fn discardReady(
        self: *Pool,
        token: Token,
    ) TransitionError!void {
        try self.beginDrain(token);
        try self.completeDrain(token);
    }

    /// Borrows the immutable canonical update held by Renderer drainage.
    ///
    /// The slices remain valid until `retryDrain` or `completeDrain` transfers
    /// ownership. No terminal-thread operation may access this block meanwhile.
    pub fn drainingUpdate(
        self: *Pool,
        token: Token,
    ) TransitionError!canvas.ProducerUpdate {
        const owner = try self.claimBlock(token, .draining);
        if (owner.revision != token.producer_revision)
            return error.Stale;
        return .{
            .revision = owner.revision,
            .uploads = self.blockUploads(token.block_index)[0..owner.upload_count],
            .removals = self.blockRemovals(token.block_index)[0..owner.removal_count],
            .commands = self.blockCommands(token.block_index)[0..owner.command_count],
            .cursor_binding = owner.cursor_binding,
        };
    }

    /// Republishes unchanged immutable bytes after Renderer rejection.
    pub fn retryDrain(
        self: *Pool,
        token: Token,
    ) TransitionError!void {
        const owner = try self.claimBlock(token, .draining);
        if (owner.revision != token.producer_revision)
            return error.Stale;
        owner.state.store(@backingInt(BlockState.ready), .release);
    }

    /// Releases one successfully drained block to global reuse.
    pub fn completeDrain(
        self: *Pool,
        token: Token,
    ) TransitionError!void {
        const owner = try self.claimBlock(token, .draining);
        if (owner.revision != token.producer_revision) return error.Stale;
        releaseBlock(owner);
    }

    /// Moves a live descriptor to retiring without changing block ownership.
    pub fn beginRetire(
        self: *Pool,
        descriptor_index: u8,
        pane_id: PaneId,
        source_id: canvas.SourceId,
    ) RetireError!void {
        const descriptor = self.descriptorAt(descriptor_index) orelse
            return error.InvalidDescriptor;
        if (descriptorState(descriptor) != .live or
            descriptor.pane_id != pane_id or
            descriptor.source_id != source_id)
            return error.Stale;
        descriptor.state.store(@backingInt(DescriptorState.retiring), .release);
    }

    /// Completes retirement, discarding ready ownership but waiting for work.
    pub fn finishRetire(
        self: *Pool,
        descriptor_index: u8,
        pane_id: PaneId,
        source_id: canvas.SourceId,
    ) RetireError!void {
        const descriptor = self.descriptorAt(descriptor_index) orelse
            return error.InvalidDescriptor;
        if (descriptorState(descriptor) != .retiring or
            descriptor.pane_id != pane_id or
            descriptor.source_id != source_id)
            return error.Stale;
        if (descriptor.block_index) |block_index| {
            const owner = self.blockOwner(block_index);
            switch (blockState(owner)) {
                .reserved, .draining => return error.Busy,
                .ready => {
                    if (owner.state.cmpxchgStrong(
                        @backingInt(BlockState.ready),
                        @backingInt(BlockState.draining),
                        .acq_rel,
                        .acquire,
                    ) != null) return error.Busy;
                    if (owner.descriptor_index != descriptor_index or
                        owner.pane_id != pane_id or
                        owner.source_id != source_id)
                    {
                        owner.state.store(
                            @backingInt(BlockState.ready),
                            .release,
                        );
                        return error.Stale;
                    }
                    releaseBlock(owner);
                },
                .free => {},
            }
            descriptor.block_index = null;
        }
        descriptor.state.store(@backingInt(DescriptorState.retired), .release);
    }

    fn initializeRecords(self: *Pool) void {
        const meta = self.metaPtr();
        meta.group_phase = .init(@backingInt(GroupPhase.idle));
        meta.candidate_revision = 0;
        meta.candidate_high_water = 0;
        meta.reservation_high_water = 0;
        for (self.descriptors()) |*descriptor| {
            descriptor.state = .init(@backingInt(DescriptorState.inactive));
            descriptor.block_index = null;
        }
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            owner.state = .init(@backingInt(BlockState.free));
            owner.descriptor_index = 0;
        }
    }

    fn validateLiveMember(
        self: *Pool,
        member: Member,
    ) ReserveError!*Descriptor {
        if (!validIdentity(member.pane_id, member.source_id))
            return error.InvalidIdentity;
        const descriptor = self.descriptorAt(member.descriptor_index) orelse
            return error.InvalidDescriptor;
        if (descriptorState(descriptor) != .live or
            descriptor.pane_id != member.pane_id or
            descriptor.source_id != member.source_id)
            return error.Stale;
        return descriptor;
    }

    fn reserveBlock(
        self: *Pool,
        descriptor: *Descriptor,
        member: Member,
        block_index: u8,
        candidate_revision: u64,
        reservation_id: u64,
    ) Token {
        const owner = self.blockOwner(block_index);
        std.debug.assert(blockState(owner) == .free);
        owner.descriptor_index = member.descriptor_index;
        owner.pane_id = member.pane_id;
        owner.source_id = member.source_id;
        owner.revision = zeroProducerRevision();
        owner.candidate_revision = candidate_revision;
        owner.reservation_id = reservation_id;
        owner.upload_count = 0;
        owner.removal_count = 0;
        owner.command_count = 0;
        owner.cursor_binding = null;
        descriptor.block_index = block_index;
        descriptor.candidate_revision = candidate_revision;
        owner.state.store(@backingInt(BlockState.reserved), .release);
        return .{
            .descriptor_index = member.descriptor_index,
            .block_index = block_index,
            .pane_id = member.pane_id,
            .source_id = member.source_id,
            .candidate_revision = candidate_revision,
            .reservation_id = reservation_id,
            .producer_revision = zeroProducerRevision(),
        };
    }

    fn claimDescriptor(
        self: *Pool,
        token: Token,
    ) TransitionError!*Descriptor {
        const descriptor = self.descriptorAt(token.descriptor_index) orelse
            return error.Stale;
        const state = descriptorState(descriptor);
        if ((state != .live and state != .retiring) or
            descriptor.pane_id != token.pane_id or
            descriptor.source_id != token.source_id or
            descriptor.block_index != token.block_index or
            descriptor.candidate_revision != token.candidate_revision)
            return error.Stale;
        return descriptor;
    }

    fn claimBlock(
        self: *Pool,
        token: Token,
        expected: BlockState,
    ) TransitionError!*BlockOwner {
        if (token.block_index >= block_limit) return error.Stale;
        const owner = self.blockOwner(token.block_index);
        if (blockState(owner) != expected or
            owner.descriptor_index != token.descriptor_index or
            owner.pane_id != token.pane_id or
            owner.source_id != token.source_id or
            owner.candidate_revision != token.candidate_revision or
            owner.reservation_id != token.reservation_id)
            return error.Stale;
        return owner;
    }

    fn nextReservationId(
        self: *Pool,
        count: usize,
    ) error{ReservationExhausted}!u64 {
        const high_water = self.metaPtr().reservation_high_water;
        const issued = std.math.cast(u64, count) orelse
            return error.ReservationExhausted;
        if (issued == 0 or issued > std.math.maxInt(u64) - high_water)
            return error.ReservationExhausted;
        return high_water + 1;
    }

    fn firstUnreferencedFreeBlock(self: *Pool) ?u8 {
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            if (blockState(owner) == .free and !self.blockReferenced(index))
                return @intCast(index);
        }
        for (0..block_limit) |index| {
            const owner = self.blockOwner(index);
            if (blockState(owner) != .free) continue;
            for (self.descriptors()) |*descriptor| {
                if (descriptor.block_index == null or
                    descriptor.block_index.? != index)
                    continue;
                descriptor.block_index = null;
                descriptor.candidate_revision = 0;
                return @intCast(index);
            }
        }
        return null;
    }

    fn blockReferenced(self: *const Pool, block_index: usize) bool {
        for (self.descriptorsConst()) |*descriptor| {
            if (descriptor.block_index != null and
                descriptor.block_index.? == block_index)
                return true;
        }
        return false;
    }

    fn metaPtr(self: *Pool) *PoolMeta {
        return pointerAt(PoolMeta, self.bytes(), self.layout.metadata_offset);
    }

    fn descriptors(self: *Pool) []Descriptor {
        return sliceAt(
            Descriptor,
            self.bytes(),
            self.layout.descriptors_offset,
            descriptor_limit,
        );
    }

    fn descriptorsConst(self: *const Pool) []const Descriptor {
        return sliceAtConst(
            Descriptor,
            self.bytesConst(),
            self.layout.descriptors_offset,
            descriptor_limit,
        );
    }

    fn descriptorAt(self: *Pool, index: u8) ?*Descriptor {
        if (index >= descriptor_limit) return null;
        return &self.descriptors()[index];
    }

    fn descriptorAtConst(self: *const Pool, index: u8) ?*const Descriptor {
        if (index >= descriptor_limit) return null;
        return &self.descriptorsConst()[index];
    }

    fn blockOwner(self: *Pool, index: usize) *BlockOwner {
        const offset = self.layout.blocks_offset +
            index * self.layout.block_stride;
        return pointerAt(BlockOwner, self.bytes(), offset);
    }

    fn blockUploads(self: *Pool, index: usize) []canvas.ResourceUpload {
        const block = blockLayout();
        return sliceAt(
            canvas.ResourceUpload,
            self.bytes(),
            self.blockOffset(index) + block.uploads_offset,
            resource_limit,
        );
    }

    fn blockRemovals(self: *Pool, index: usize) []canvas.ResourceRemoval {
        const block = blockLayout();
        return sliceAt(
            canvas.ResourceRemoval,
            self.bytes(),
            self.blockOffset(index) + block.removals_offset,
            resource_limit,
        );
    }

    fn blockCommands(self: *Pool, index: usize) []canvas.Input {
        const block = blockLayout();
        return sliceAt(
            canvas.Input,
            self.bytes(),
            self.blockOffset(index) + block.commands_offset,
            command_limit,
        );
    }

    fn blockPixels(self: *Pool, index: usize) []u8 {
        const block = blockLayout();
        return self.bytes()[self.blockOffset(index) + block.pixels_offset ..][0..pixel_limit];
    }

    fn blockOffset(self: *const Pool, index: usize) usize {
        std.debug.assert(index < block_limit);
        return self.layout.blocks_offset + index * self.layout.block_stride;
    }

    fn bytes(self: *Pool) []u8 {
        return std.mem.sliceAsBytes(self.backing);
    }

    fn bytesConst(self: *const Pool) []const u8 {
        return std.mem.sliceAsBytes(self.backing);
    }
};

fn descriptorState(descriptor: *const Descriptor) DescriptorState {
    return @fromBackingInt(@intCast(descriptor.state.load(.acquire)));
}

fn validateClaimedBlock(
    owner: *const BlockOwner,
    token: Token,
) error{Stale}!void {
    if (owner.descriptor_index != token.descriptor_index or
        owner.pane_id != token.pane_id or
        owner.source_id != token.source_id or
        owner.candidate_revision != token.candidate_revision or
        owner.reservation_id != token.reservation_id)
        return error.Stale;
    if (owner.command_count > command_limit) return error.Stale;
    if (owner.cursor_binding) |binding|
        if (binding.source != token.source_id or
            binding.pane != @backingInt(token.pane_id)) return error.Stale;
}

fn blockState(owner: *const BlockOwner) BlockState {
    return @fromBackingInt(@intCast(owner.state.load(.acquire)));
}

fn groupPhase(meta: *const PoolMeta) GroupPhase {
    return @fromBackingInt(@intCast(meta.group_phase.load(.acquire)));
}

fn releaseBlock(owner: *BlockOwner) void {
    std.debug.assert(blockState(owner) == .reserved or
        blockState(owner) == .draining);
    owner.descriptor_index = 0;
    owner.pane_id = @fromBackingInt(@intCast(0));
    owner.source_id = @fromBackingInt(@intCast(0));
    owner.revision = zeroProducerRevision();
    owner.candidate_revision = 0;
    owner.reservation_id = 0;
    owner.upload_count = 0;
    owner.removal_count = 0;
    owner.command_count = 0;
    owner.cursor_binding = null;
    owner.state.store(@backingInt(BlockState.free), .release);
}

fn clearGroup(meta: *PoolMeta) void {
    meta.candidate_revision = 0;
    meta.group_phase.store(@backingInt(GroupPhase.idle), .release);
}

fn validIdentity(pane_id: PaneId, source_id: canvas.SourceId) bool {
    return @backingInt(pane_id) != 0 and @backingInt(source_id) != 0;
}

fn noBlockIndex() u8 {
    return std.math.maxInt(u8);
}

fn containsBlock(indices: []const u8, block_index: usize) bool {
    for (indices) |index| {
        if (index == block_index) return true;
    }
    return false;
}

fn zeroProducerRevision() canvas.ProducerRevision {
    return @fromBackingInt(@intCast(0));
}

fn pointerAt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
) *T {
    return @ptrCast(@alignCast(bytes[offset..].ptr));
}

fn sliceAt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    count: usize,
) []T {
    const pointer: [*]T = @ptrCast(@alignCast(bytes[offset..].ptr));
    return pointer[0..count];
}

fn sliceAtConst(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
    count: usize,
) []const T {
    const pointer: [*]const T = @ptrCast(@alignCast(bytes[offset..].ptr));
    return pointer[0..count];
}

fn checkedAdd(left: usize, right: usize) error{ArithmeticOverflow}!usize {
    return std.math.add(usize, left, right) catch error.ArithmeticOverflow;
}

fn checkedMul(left: usize, right: usize) error{ArithmeticOverflow}!usize {
    return std.math.mul(usize, left, right) catch error.ArithmeticOverflow;
}

fn checkedAlign(
    value: usize,
    alignment: usize,
) error{ArithmeticOverflow}!usize {
    const mask = alignment - 1;
    return (try checkedAdd(value, mask)) & ~mask;
}

fn calculateBlockLayout() error{ArithmeticOverflow}!BlockLayout {
    var cursor: usize = 0;
    const owner_offset = try checkedAlign(cursor, @alignOf(BlockOwner));
    cursor = try checkedAdd(owner_offset, @sizeOf(BlockOwner));
    const uploads_offset = try checkedAlign(
        cursor,
        @alignOf(canvas.ResourceUpload),
    );
    cursor = try checkedAdd(
        uploads_offset,
        try checkedMul(resource_limit, @sizeOf(canvas.ResourceUpload)),
    );
    const removals_offset = try checkedAlign(
        cursor,
        @alignOf(canvas.ResourceRemoval),
    );
    cursor = try checkedAdd(
        removals_offset,
        try checkedMul(resource_limit, @sizeOf(canvas.ResourceRemoval)),
    );
    const commands_offset = try checkedAlign(cursor, @alignOf(canvas.Input));
    cursor = try checkedAdd(
        commands_offset,
        try checkedMul(command_limit, @sizeOf(canvas.Input)),
    );
    const pixels_offset = try checkedAlign(cursor, @alignOf(u8));
    cursor = try checkedAdd(pixels_offset, pixel_limit);
    return .{
        .owner_offset = owner_offset,
        .uploads_offset = uploads_offset,
        .removals_offset = removals_offset,
        .commands_offset = commands_offset,
        .pixels_offset = pixels_offset,
        .total = try checkedAlign(cursor, @alignOf(BlockOwner)),
    };
}

fn blockLayout() BlockLayout {
    return calculateBlockLayout() catch
        @panic("terminal pool compile-time layout overflow");
}

fn calculateLayout() error{ArithmeticOverflow}!Layout {
    const block = try calculateBlockLayout();
    var cursor: usize = 0;
    const metadata_offset = try checkedAlign(cursor, @alignOf(PoolMeta));
    cursor = try checkedAdd(metadata_offset, @sizeOf(PoolMeta));
    const descriptors_offset = try checkedAlign(cursor, @alignOf(Descriptor));
    cursor = try checkedAdd(
        descriptors_offset,
        try checkedMul(descriptor_limit, @sizeOf(Descriptor)),
    );
    const blocks_offset = try checkedAlign(cursor, @alignOf(BlockOwner));
    const block_stride = try checkedAlign(block.total, @alignOf(BlockOwner));
    cursor = try checkedAdd(
        blocks_offset,
        try checkedMul(block_limit, block_stride),
    );
    return .{
        .metadata_offset = metadata_offset,
        .descriptors_offset = descriptors_offset,
        .blocks_offset = blocks_offset,
        .block_stride = block_stride,
        .total = cursor,
    };
}

test "fixed pool layout matches checked executable receipt" {
    const block = try calculateBlockLayout();
    const layout = try calculateLayout();
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Descriptor));
    try std.testing.expectEqual(@as(usize, 176), @sizeOf(BlockOwner));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(PoolMeta));
    try std.testing.expectEqual(@as(usize, 176), block.uploads_offset);
    try std.testing.expectEqual(@as(usize, 57_520), block.removals_offset);
    try std.testing.expectEqual(@as(usize, 73_904), block.commands_offset);
    try std.testing.expectEqual(@as(usize, 2_433_200), block.pixels_offset);
    try std.testing.expectEqual(@as(usize, 6_627_504), block.total);
    try std.testing.expectEqual(@as(usize, 0), layout.metadata_offset);
    try std.testing.expectEqual(@as(usize, 32), layout.descriptors_offset);
    try std.testing.expectEqual(@as(usize, 4_128), layout.blocks_offset);
    try std.testing.expectEqual(@as(usize, 106_044_192), layout.total);
    try std.testing.expectError(
        error.ArithmeticOverflow,
        checkedAdd(std.math.maxInt(usize), 1),
    );
    try std.testing.expectError(
        error.ArithmeticOverflow,
        checkedMul(std.math.maxInt(usize), 2),
    );
}

test "allocation failure and reverse cleanup preserve allocator ownership" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(error.OutOfMemory, Pool.init(failing.allocator()));
    var pool = try Pool.init(std.testing.allocator);
    pool.deinit();
}

test "group reservation is atomic and cancellation is exact" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    var members: [block_limit]Member = undefined;
    for (&members, 0..) |*member, index| {
        const pane: PaneId = @fromBackingInt(@intCast(index + 1));
        const source: canvas.SourceId = @fromBackingInt(@intCast(index + 101));
        try pool.register(@intCast(index), pane, source);
        member.* = .{
            .descriptor_index = @intCast(index),
            .pane_id = pane,
            .source_id = source,
        };
    }
    const group = try pool.reserveGroup(9, &members);
    try std.testing.expectEqual(@as(u8, block_limit), group.count);
    for (group.tokens) |token| {
        try std.testing.expectEqual(
            BlockState.reserved,
            blockState(pool.blockOwner(token.block_index)),
        );
    }
    const first_descriptor = pool.descriptorAt(members[0].descriptor_index).?;
    const first_block = first_descriptor.block_index.?;
    first_descriptor.block_index = @intCast((@as(usize, first_block) + 1) %
        block_limit);
    try std.testing.expectError(error.Stale, pool.cancelGroup(9));
    for (group.tokens) |token| {
        try std.testing.expectEqual(
            BlockState.reserved,
            blockState(pool.blockOwner(token.block_index)),
        );
    }
    first_descriptor.block_index = first_block;
    const first = group.tokens[0];
    try std.testing.expectError(error.Stale, pool.cancelGroup(8));
    try pool.cancelGroup(9);
    for (group.tokens) |token| {
        try std.testing.expectEqual(
            BlockState.free,
            blockState(pool.blockOwner(token.block_index)),
        );
    }
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(first, @fromBackingInt(@intCast(1)), 0, 0, 1),
    );
    for (members) |member| {
        try pool.beginRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
}

test "group completion rejects partial publication and preserves successful blocks" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    const first = Member{
        .descriptor_index = 0,
        .pane_id = @fromBackingInt(@intCast(21)),
        .source_id = @fromBackingInt(@intCast(31)),
    };
    const second = Member{
        .descriptor_index = 1,
        .pane_id = @fromBackingInt(@intCast(22)),
        .source_id = @fromBackingInt(@intCast(32)),
    };
    const ordinary = Member{
        .descriptor_index = 2,
        .pane_id = @fromBackingInt(@intCast(23)),
        .source_id = @fromBackingInt(@intCast(33)),
    };
    for ([_]Member{ first, second, ordinary }) |member| {
        try pool.register(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
    const group = try pool.reserveGroup(50, &.{ first, second });
    const first_ready = try pool.publishMetadata(
        group.tokens[0],
        @fromBackingInt(@intCast(1)),
        1,
        0,
        1,
    );
    const meta_before_partial = pool.metaPtr().*;
    try std.testing.expectError(error.Partial, pool.completeGroup(50));
    try std.testing.expectEqualDeep(meta_before_partial, pool.metaPtr().*);
    try std.testing.expectEqual(
        BlockState.ready,
        blockState(pool.blockOwner(first_ready.block_index)),
    );
    try std.testing.expectEqual(
        BlockState.reserved,
        blockState(pool.blockOwner(group.tokens[1].block_index)),
    );
    try std.testing.expectError(error.GroupPriority, pool.reserve(ordinary));

    const second_ready = try pool.publishMetadata(
        group.tokens[1],
        @fromBackingInt(@intCast(1)),
        1,
        0,
        1,
    );
    try pool.beginDrain(second_ready);
    try pool.completeGroup(50);
    try std.testing.expectEqual(
        BlockState.ready,
        blockState(pool.blockOwner(first_ready.block_index)),
    );
    try std.testing.expectEqual(
        BlockState.draining,
        blockState(pool.blockOwner(second_ready.block_index)),
    );
    const meta_after_completion = pool.metaPtr().*;
    try std.testing.expectError(error.Stale, pool.completeGroup(50));
    try std.testing.expectEqualDeep(meta_after_completion, pool.metaPtr().*);

    const ordinary_token = try pool.reserve(ordinary);
    try pool.beginDrain(first_ready);
    try pool.completeDrain(first_ready);
    try pool.completeDrain(second_ready);
    const ordinary_ready = try pool.publishMetadata(
        ordinary_token,
        @fromBackingInt(@intCast(1)),
        0,
        0,
        0,
    );
    try pool.beginDrain(ordinary_ready);
    try pool.completeDrain(ordinary_ready);
    for ([_]Member{ first, second, ordinary }) |member| {
        try pool.beginRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
}

test "fifteen free blocks and invalid groups preserve state" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    var members: [block_limit]Member = undefined;
    for (&members, 0..) |*member, index| {
        const pane: PaneId = @fromBackingInt(@intCast(index + 1));
        const source: canvas.SourceId = @fromBackingInt(@intCast(index + 201));
        try pool.register(@intCast(index), pane, source);
        member.* = .{
            .descriptor_index = @intCast(index),
            .pane_id = pane,
            .source_id = source,
        };
    }
    const occupied = Member{
        .descriptor_index = block_limit,
        .pane_id = @fromBackingInt(@intCast(99)),
        .source_id = @fromBackingInt(@intCast(299)),
    };
    try pool.register(
        occupied.descriptor_index,
        occupied.pane_id,
        occupied.source_id,
    );
    const ordinary = try pool.reserve(occupied);
    try std.testing.expectError(error.NoCapacity, pool.reserveGroup(7, &members));
    try std.testing.expectEqual(
        BlockState.reserved,
        blockState(pool.blockOwner(ordinary.block_index)),
    );
    var duplicate = members;
    duplicate[2] = duplicate[1];
    try std.testing.expectError(
        error.DuplicateMember,
        pool.reserveGroup(8, duplicate[1..]),
    );
    try std.testing.expectError(
        error.InvalidCandidateRevision,
        pool.reserveGroup(0, members[1..2]),
    );
    const published = try pool.publishMetadata(
        ordinary,
        @fromBackingInt(@intCast(1)),
        0,
        0,
        1,
    );
    try pool.beginDrain(published);
    try pool.completeDrain(published);
    try pool.beginRetire(
        occupied.descriptor_index,
        occupied.pane_id,
        occupied.source_id,
    );
    try pool.finishRetire(
        occupied.descriptor_index,
        occupied.pane_id,
        occupied.source_id,
    );
    for (members) |member| {
        try pool.beginRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
}

test "group cancellation preserves unrelated ownership and payload bytes" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    var members: [block_limit]Member = undefined;
    for (&members, 0..) |*member, index| {
        const pane: PaneId = @fromBackingInt(@intCast(index + 1));
        const source: canvas.SourceId = @fromBackingInt(@intCast(index + 301));
        try pool.register(@intCast(index), pane, source);
        member.* = .{
            .descriptor_index = @intCast(index),
            .pane_id = pane,
            .source_id = source,
        };
    }

    const reserved = try pool.reserve(members[0]);
    const ready = try pool.publishMetadata(
        try pool.reserve(members[1]),
        @fromBackingInt(@intCast(1)),
        1,
        1,
        1,
    );
    const draining = try pool.publishMetadata(
        try pool.reserve(members[2]),
        @fromBackingInt(@intCast(1)),
        1,
        1,
        1,
    );
    try pool.beginDrain(draining);
    const block_layout = try calculateBlockLayout();
    const marks = [3]u8{ 0xa1, 0xb2, 0xc3 };
    const tokens = [3]Token{ reserved, ready, draining };
    for (tokens, marks) |token, mark| {
        const offset = pool.layout.blocks_offset +
            @as(usize, token.block_index) * pool.layout.block_stride +
            block_layout.pixels_offset;
        pool.bytes()[offset] = mark;
    }

    const group = try pool.reserveGroup(77, members[3..]);
    try std.testing.expectEqual(@as(u8, 13), group.count);
    try std.testing.expectError(error.Stale, pool.cancelGroup(76));
    try pool.cancelGroup(77);
    try std.testing.expectEqual(
        BlockState.reserved,
        blockState(pool.blockOwner(reserved.block_index)),
    );
    try std.testing.expectEqual(
        BlockState.ready,
        blockState(pool.blockOwner(ready.block_index)),
    );
    try std.testing.expectEqual(
        BlockState.draining,
        blockState(pool.blockOwner(draining.block_index)),
    );
    for (tokens, marks) |token, mark| {
        const offset = pool.layout.blocks_offset +
            @as(usize, token.block_index) * pool.layout.block_stride +
            block_layout.pixels_offset;
        try std.testing.expectEqual(mark, pool.bytes()[offset]);
    }

    const reserved_ready = try pool.publishMetadata(
        reserved,
        @fromBackingInt(@intCast(1)),
        0,
        0,
        0,
    );
    try pool.beginDrain(reserved_ready);
    try pool.completeDrain(reserved_ready);
    try pool.beginDrain(ready);
    try pool.completeDrain(ready);
    try pool.completeDrain(draining);
    for (members) |member| {
        try pool.beginRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
}

test "ordinary priority stale tokens and retirement preserve ownership" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    const first = Member{
        .descriptor_index = 0,
        .pane_id = @fromBackingInt(@intCast(1)),
        .source_id = @fromBackingInt(@intCast(11)),
    };
    const second = Member{
        .descriptor_index = 1,
        .pane_id = @fromBackingInt(@intCast(2)),
        .source_id = @fromBackingInt(@intCast(12)),
    };
    try pool.register(first.descriptor_index, first.pane_id, first.source_id);
    try pool.register(second.descriptor_index, second.pane_id, second.source_id);
    const group = try pool.reserveGroup(41, &.{first});
    try std.testing.expectError(error.GroupPriority, pool.reserve(second));
    try pool.cancelGroup(41);

    const reserved = try pool.reserve(first);
    try pool.beginRetire(first.descriptor_index, first.pane_id, first.source_id);
    try std.testing.expectError(
        error.Busy,
        pool.finishRetire(first.descriptor_index, first.pane_id, first.source_id),
    );
    try std.testing.expectError(
        error.InvalidCounts,
        pool.publishMetadata(reserved, @fromBackingInt(@intCast(3)), resource_limit + 1, 0, 0),
    );
    try std.testing.expectError(
        error.InvalidProducerRevision,
        pool.publishMetadata(reserved, @fromBackingInt(@intCast(0)), 0, 0, 0),
    );
    const published = try pool.publishMetadata(
        reserved,
        @fromBackingInt(@intCast(2)),
        resource_limit,
        resource_limit,
        command_limit,
    );
    try std.testing.expectError(
        error.Stale,
        pool.beginDrain(group.tokens[0]),
    );
    try pool.finishRetire(first.descriptor_index, first.pane_id, first.source_id);
    try std.testing.expectEqual(
        DescriptorState.retired,
        descriptorState(pool.descriptorAt(first.descriptor_index).?),
    );
    try std.testing.expectError(error.Stale, pool.beginDrain(published));

    const second_token = try pool.reserve(second);
    const second_published = try pool.publishMetadata(
        second_token,
        @fromBackingInt(@intCast(1)),
        1,
        1,
        1,
    );
    try pool.beginDrain(second_published);
    try pool.beginRetire(second.descriptor_index, second.pane_id, second.source_id);
    try std.testing.expectError(
        error.Busy,
        pool.finishRetire(second.descriptor_index, second.pane_id, second.source_id),
    );
    try pool.retryDrain(second_published);
    try pool.finishRetire(second.descriptor_index, second.pane_id, second.source_id);
}

test "every token identity and revision rejects stale storage claims" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    const member = Member{
        .descriptor_index = 0,
        .pane_id = @fromBackingInt(@intCast(91)),
        .source_id = @fromBackingInt(@intCast(92)),
    };
    try pool.register(member.descriptor_index, member.pane_id, member.source_id);
    const reserved = try pool.reserve(member);

    var wrong = reserved;
    wrong.descriptor_index = descriptor_limit;
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(wrong, @fromBackingInt(@intCast(1)), 0, 0, 0),
    );
    wrong = reserved;
    wrong.pane_id = @fromBackingInt(@intCast(93));
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(wrong, @fromBackingInt(@intCast(1)), 0, 0, 0),
    );
    wrong = reserved;
    wrong.source_id = @fromBackingInt(@intCast(94));
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(wrong, @fromBackingInt(@intCast(1)), 0, 0, 0),
    );
    wrong = reserved;
    wrong.candidate_revision = 8;
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(wrong, @fromBackingInt(@intCast(1)), 0, 0, 0),
    );

    const published = try pool.publishMetadata(
        reserved,
        @fromBackingInt(@intCast(7)),
        0,
        0,
        0,
    );
    wrong = published;
    wrong.producer_revision = @fromBackingInt(@intCast(6));
    try std.testing.expectError(error.Stale, pool.beginDrain(wrong));
    try pool.beginDrain(published);
    try pool.completeDrain(published);
    try pool.beginRetire(member.descriptor_index, member.pane_id, member.source_id);
    try pool.finishRetire(member.descriptor_index, member.pane_id, member.source_id);
}

test "both ready-drain retirement outcomes are deterministic" {
    {
        var pool = try Pool.init(std.testing.allocator);
        defer pool.deinit();
        const member = Member{
            .descriptor_index = 0,
            .pane_id = @fromBackingInt(@intCast(611)),
            .source_id = @fromBackingInt(@intCast(711)),
        };
        const token = try raceFixture(&pool, member, 1);
        try pool.beginDrain(token);
        try std.testing.expectError(
            error.Busy,
            pool.finishRetire(
                member.descriptor_index,
                member.pane_id,
                member.source_id,
            ),
        );
        try pool.completeDrain(token);
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
    }
    {
        var pool = try Pool.init(std.testing.allocator);
        defer pool.deinit();
        const member = Member{
            .descriptor_index = 0,
            .pane_id = @fromBackingInt(@intCast(612)),
            .source_id = @fromBackingInt(@intCast(712)),
        };
        const token = try raceFixture(&pool, member, 1);
        try pool.finishRetire(
            member.descriptor_index,
            member.pane_id,
            member.source_id,
        );
        try std.testing.expectError(error.Stale, pool.beginDrain(token));
    }
}

test "reservation and candidate identities never repeat across reuse" {
    var pool = try Pool.init(std.testing.allocator);
    defer pool.deinit();
    const member = Member{
        .descriptor_index = 0,
        .pane_id = @fromBackingInt(@intCast(501)),
        .source_id = @fromBackingInt(@intCast(601)),
    };
    try pool.register(member.descriptor_index, member.pane_id, member.source_id);

    const old_reserved = try pool.reserve(member);
    const old_ready = try pool.publishMetadata(
        old_reserved,
        @fromBackingInt(@intCast(1)),
        0,
        0,
        1,
    );
    try pool.beginDrain(old_ready);
    try pool.completeDrain(old_ready);
    const replacement = try pool.reserve(member);
    try std.testing.expect(replacement.reservation_id > old_reserved.reservation_id);
    try std.testing.expectEqual(old_reserved.block_index, replacement.block_index);
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(old_reserved, @fromBackingInt(@intCast(2)), 0, 0, 1),
    );
    try std.testing.expectError(error.Stale, pool.beginDrain(old_ready));
    try std.testing.expectError(error.Stale, pool.retryDrain(old_ready));
    try std.testing.expectError(error.Stale, pool.completeDrain(old_ready));
    const replacement_ready = try pool.publishMetadata(
        replacement,
        @fromBackingInt(@intCast(2)),
        0,
        0,
        1,
    );
    try std.testing.expectError(error.Stale, pool.beginDrain(old_ready));
    try pool.beginDrain(replacement_ready);
    try pool.completeDrain(replacement_ready);

    const first_group = try pool.reserveGroup(9, &.{member});
    try pool.cancelGroup(9);
    try std.testing.expectError(
        error.InvalidCandidateRevision,
        pool.reserveGroup(9, &.{member}),
    );
    const second_group = try pool.reserveGroup(10, &.{member});
    try std.testing.expect(
        second_group.tokens[0].reservation_id >
            first_group.tokens[0].reservation_id,
    );
    try std.testing.expectError(error.Stale, pool.cancelGroup(9));
    try std.testing.expectError(
        error.Stale,
        pool.publishMetadata(
            first_group.tokens[0],
            @fromBackingInt(@intCast(3)),
            0,
            0,
            1,
        ),
    );
    try std.testing.expectError(
        error.Stale,
        pool.beginDrain(first_group.tokens[0]),
    );
    try std.testing.expectError(
        error.Stale,
        pool.retryDrain(first_group.tokens[0]),
    );
    try std.testing.expectError(
        error.Stale,
        pool.completeDrain(first_group.tokens[0]),
    );
    try pool.cancelGroup(10);

    pool.metaPtr().reservation_high_water = std.math.maxInt(u64);
    const descriptor_before = pool.descriptorAt(member.descriptor_index).?.*;
    try std.testing.expectError(error.ReservationExhausted, pool.reserve(member));
    try std.testing.expectEqualDeep(
        descriptor_before,
        pool.descriptorAt(member.descriptor_index).?.*,
    );
    pool.metaPtr().reservation_high_water = second_group.tokens[0].reservation_id;
    pool.metaPtr().candidate_high_water = std.math.maxInt(u64);
    try std.testing.expectError(
        error.InvalidCandidateRevision,
        pool.reserveGroup(11, &.{member}),
    );
    try pool.beginRetire(member.descriptor_index, member.pane_id, member.source_id);
    try pool.finishRetire(member.descriptor_index, member.pane_id, member.source_id);
}

const RaceResult = enum(u8) {
    pending,
    success,
    busy,
    stale,
    unexpected,
};

const RaceContext = struct {
    pool: *Pool,
    token: Token,
    member: Member,
    start: std.atomic.Value(bool) = .init(false),
    renderer_result: RaceResult = .pending,
    terminal_result: RaceResult = .pending,
};

fn awaitRaceStart(context: *RaceContext) void {
    while (!context.start.load(.acquire)) std.atomic.spinLoopHint();
}

fn raceBeginDrain(context: *RaceContext) void {
    awaitRaceStart(context);
    context.pool.beginDrain(context.token) catch |err| {
        context.renderer_result = switch (err) {
            error.Busy => .busy,
            error.Stale => .stale,
            error.InvalidCounts, error.InvalidProducerRevision => .unexpected,
        };
        return;
    };
    context.renderer_result = .success;
}

fn raceCompleteDrain(context: *RaceContext) void {
    awaitRaceStart(context);
    context.pool.completeDrain(context.token) catch |err| {
        context.renderer_result = switch (err) {
            error.Busy => .busy,
            error.Stale => .stale,
            error.InvalidCounts, error.InvalidProducerRevision => .unexpected,
        };
        return;
    };
    context.renderer_result = .success;
}

fn raceRetryDrain(context: *RaceContext) void {
    awaitRaceStart(context);
    context.pool.retryDrain(context.token) catch |err| {
        context.renderer_result = switch (err) {
            error.Busy => .busy,
            error.Stale => .stale,
            error.InvalidCounts, error.InvalidProducerRevision => .unexpected,
        };
        return;
    };
    context.renderer_result = .success;
}

const RaceOperation = enum {
    begin,
    complete,
    retry,
};

fn raceRenderer(context: *RaceContext, operation: RaceOperation) void {
    switch (operation) {
        .begin => raceBeginDrain(context),
        .complete => raceCompleteDrain(context),
        .retry => raceRetryDrain(context),
    }
}

fn raceFinishRetire(context: *RaceContext) void {
    awaitRaceStart(context);
    context.pool.finishRetire(
        context.member.descriptor_index,
        context.member.pane_id,
        context.member.source_id,
    ) catch |err| {
        context.terminal_result = switch (err) {
            error.Busy => .busy,
            error.Stale, error.InvalidDescriptor => .stale,
        };
        return;
    };
    context.terminal_result = .success;
}

fn runRace(
    context: *RaceContext,
    operation: RaceOperation,
) !void {
    const renderer_thread = try std.Thread.spawn(
        .{},
        raceRenderer,
        .{ context, operation },
    );
    const terminal_thread = try std.Thread.spawn(
        .{},
        raceFinishRetire,
        .{context},
    );
    context.start.store(true, .release);
    renderer_thread.join();
    terminal_thread.join();
    try std.testing.expect(context.renderer_result != .unexpected);
    try std.testing.expect(context.terminal_result != .unexpected);
}

fn raceFixture(
    pool: *Pool,
    member: Member,
    revision: u64,
) !Token {
    try pool.register(member.descriptor_index, member.pane_id, member.source_id);
    const token = try pool.publishMetadata(
        try pool.reserve(member),
        @fromBackingInt(@intCast(revision)),
        1,
        1,
        1,
    );
    try pool.beginRetire(member.descriptor_index, member.pane_id, member.source_id);
    return token;
}

test "Renderer drainage races preserve exclusive block retirement" {
    {
        var pool = try Pool.init(std.testing.allocator);
        defer pool.deinit();
        const member = Member{
            .descriptor_index = 0,
            .pane_id = @fromBackingInt(@intCast(701)),
            .source_id = @fromBackingInt(@intCast(801)),
        };
        const token = try raceFixture(&pool, member, 1);
        var context = RaceContext{
            .pool = &pool,
            .token = token,
            .member = member,
        };
        try runRace(&context, .begin);
        if (context.renderer_result == .success) {
            try std.testing.expectEqual(RaceResult.busy, context.terminal_result);
            try pool.completeDrain(token);
            try pool.finishRetire(
                member.descriptor_index,
                member.pane_id,
                member.source_id,
            );
        } else {
            try std.testing.expectEqual(RaceResult.success, context.terminal_result);
            try std.testing.expect(
                context.renderer_result == .stale or
                    context.renderer_result == .busy,
            );
        }
        try std.testing.expectEqual(BlockState.free, blockState(pool.blockOwner(token.block_index)));
        try std.testing.expectError(error.Stale, pool.beginDrain(token));
    }
    {
        var pool = try Pool.init(std.testing.allocator);
        defer pool.deinit();
        const member = Member{
            .descriptor_index = 0,
            .pane_id = @fromBackingInt(@intCast(702)),
            .source_id = @fromBackingInt(@intCast(802)),
        };
        const token = try raceFixture(&pool, member, 1);
        try pool.beginDrain(token);
        var context = RaceContext{
            .pool = &pool,
            .token = token,
            .member = member,
        };
        try runRace(&context, .complete);
        try std.testing.expectEqual(RaceResult.success, context.renderer_result);
        if (context.terminal_result == .busy) {
            try pool.finishRetire(
                member.descriptor_index,
                member.pane_id,
                member.source_id,
            );
        } else try std.testing.expectEqual(
            RaceResult.success,
            context.terminal_result,
        );
        try std.testing.expectEqual(BlockState.free, blockState(pool.blockOwner(token.block_index)));
    }
    {
        var pool = try Pool.init(std.testing.allocator);
        defer pool.deinit();
        const member = Member{
            .descriptor_index = 0,
            .pane_id = @fromBackingInt(@intCast(703)),
            .source_id = @fromBackingInt(@intCast(803)),
        };
        const token = try raceFixture(&pool, member, 1);
        try pool.beginDrain(token);
        var context = RaceContext{
            .pool = &pool,
            .token = token,
            .member = member,
        };
        try runRace(&context, .retry);
        try std.testing.expectEqual(RaceResult.success, context.renderer_result);
        if (context.terminal_result == .busy) {
            try pool.finishRetire(
                member.descriptor_index,
                member.pane_id,
                member.source_id,
            );
        } else try std.testing.expectEqual(
            RaceResult.success,
            context.terminal_result,
        );
        try std.testing.expectEqual(BlockState.free, blockState(pool.blockOwner(token.block_index)));
        try std.testing.expectError(error.Stale, pool.beginDrain(token));
    }
}
