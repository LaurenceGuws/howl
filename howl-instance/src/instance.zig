//! Owns one canonical PTY and VT instance independently of attached observers.

const std = @import("std");
const pty = @import("howl_pty");
const howl_render = @import("howl_render");
const vt = @import("howl_vt");
const terminal_render = howl_render.terminal;
const publication = @import("publication.zig");

/// Shared-instance wire and geometry-authority contract.
pub const protocol = @import("howl_instance_protocol");
/// Exact backend-neutral Render package composed by this Instance package.
pub const render = howl_render;
/// Exact text package instance used by this Instance package's Render owner.
pub const text = howl_render.text;
/// Opaque SPSC exchange shared with one embedding backend thread.
pub const RenderExchange = publication.Exchange;
/// One immutable backend-facing Render publication lease.
pub const RenderLease = publication.Lease;
/// One immutable self-contained Render transaction.
pub const PublishedFrame = publication.PublishedFrame;
/// Acquires only the newest unread Render publication.
pub const acquirePublishedFrame = publication.acquireLatest;

const write_queue_bytes: usize = 64 * 1024;
const read_buffer_bytes: usize = 16 * 1024;
const read_calls_per_turn: u8 = 8;
const write_bytes_per_turn: usize = 64 * 1024;
const write_calls_per_turn: usize = 4;

/// Opaque handle to one canonical PTY + VT lifetime owner.
// zig-audit: acknowledge opaque_type
// reason: This handle intentionally hides its backing owner layout so callers can use only the bounded public lifetime/API.
pub const Instance = opaque {};
/// Canonical terminal engine type owned by one Instance.
pub const Terminal = vt.Terminal;
/// Platform-native PTY readiness descriptor exposed only to platform service owners.
pub const Descriptor = pty.Descriptor;
/// Host-neutral input accepted by the canonical VT owner.
pub const Input = vt.Terminal.InputEvent;
/// Names physical non-Unicode key identities accepted by canonical input encoding.
pub const KeyName = vt.Terminal.NamedKey;
/// Validates Unicode or named physical-key identity.
pub const Key = vt.Terminal.Key;
/// Names one key press/repeat/release transition.
pub const KeyAction = vt.Terminal.KeyAction;
/// Copies full keyboard/mouse modifier state.
pub const InputModifier = vt.Terminal.InputModifier;
/// Names one mouse event class.
pub const MouseEventKind = vt.Terminal.MouseEventKind;
/// Names one mouse button identity.
pub const MouseButton = vt.Terminal.MouseButton;
/// Bounds committed key text accepted by the canonical VT encoder.
pub const maximum_key_text_bytes = vt.Terminal.maximum_key_text_bytes;
/// Bounds legacy key bytes while leaving canonical Meta prefix headroom.
pub const maximum_legacy_key_bytes = vt.Terminal.maximum_legacy_key_bytes;
/// Maximum scalars retained by one bounded terminal grapheme.
pub const maximum_cell_scalars = vt.scalar.maximum_scalars;
/// Fixed process-group signal vocabulary.
pub const Signal = pty.Signal;
/// Exact process-group signal delivery outcome.
pub const SignalResult = pty.SignalResult;
/// One ordered host-facing consequence retained by the canonical VT.
pub const Consequence = vt.Terminal.Consequence;
/// Reports stale occurrence identity or a consequence requiring a typed reply.
pub const ConsumeConsequenceError = vt.Terminal.ConsumeConsequenceError;
/// Reports clipboard reply admission failure without consuming a stale query.
pub const ClipboardReplyError = vt.Terminal.ClipboardReplyError;
/// Reports pointer-shape reply admission or identity failure.
pub const PointerShapeReplyError = vt.Terminal.PointerShapeReplyError;
/// Terminal-owned light/dark color preference vocabulary.
pub const ColorSchemePreference = vt.Terminal.ColorSchemePreference;
/// Reports color-preference reply admission or identity failure.
pub const ColorPreferenceReplyError = vt.Terminal.ColorPreferenceReplyError;
/// Typed container/window query reply vocabulary.
pub const ContainerReply = vt.Terminal.ContainerReply;
/// Reports container reply admission, identity, or type mismatch.
pub const ContainerReplyError = vt.Terminal.ContainerReplyError;
/// Selects whether a service turn applies deterministic headless host policy or retains host consequences.
pub const ConsequencePolicy = enum { headless, retain };
/// Exact child-process termination observation.
pub const ChildExit = pty.ChildExit;
/// Exact generated box-drawing configuration consumed by Instance-owned Render.
pub const BoxDrawingConfig = @FieldType(terminal_render.Config, "box_drawing");

/// Selects one owned font source for presented Instance construction.
pub const FontConfig = union(enum) {
    path: text.Config,
    memory: text.MemoryConfig,
};

/// Supplies one required regular font and optional style variants.
pub const FontFamilyConfig = struct {
    regular: FontConfig,
    italic: ?FontConfig = null,
    bold: ?FontConfig = null,
    bold_italic: ?FontConfig = null,
};

/// Supplies bounded text and renderer policy for one presented Instance.
///
/// The canonical cell lattice is derived from the regular font metrics. The
/// caller does not separately choose PTY/VT and Render pixel geometry.
pub const PresentationConfig = struct {
    fonts: FontFamilyConfig,
    box_drawing: BoxDrawingConfig,
    shape_cache: terminal_render.ShapeCacheConfig,
    atlas: terminal_render.AtlasConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
    command_capacity: usize,
    command_limit: usize = 0,
    incremental_row_capacity: u16 = 0,
    incremental_command_capacity: usize = 0,
};

/// Reports the exact grid and cell lattice chosen for one presented surface.
pub const PresentationGeometry = struct {
    cell_size: terminal_render.Size,
    rows: u16,
    columns: u16,
};

/// Supplies one local shell launch and bounded canonical terminal geometry.
pub const Launch = struct {
    shell: []const u8,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16,
    columns: u16,
    /// Stable canonical terminal pixel lattice used by graphics/window queries.
    cell_pixel_width: u32 = 10,
    cell_pixel_height: u32 = 20,
    history_rows: u16 = 4096,
    term: []const u8 = "xterm-256color",
    colorterm: ?[]const u8 = "truecolor",
};

/// Reports construction failure before a instance becomes observable.
pub const InitError = pty.InitError || pty.StartError || vt.Terminal.InitError;
/// Reports construction failure before a presented Instance becomes observable.
pub const PresentedInitError = InitError || text.InitError || terminal_render.InitError || terminal_render.Error;
/// Reports terminal input encoding, signal, or bounded write admission failure.
pub const InputError = vt.Terminal.InputError || pty.TermiosSignalError || error{WriteQueueFull};
/// Reports atomic PTY and VT geometry transition failure.
pub const ResizeError = pty.ResizeError || vt.Terminal.ResizeError;
/// Reports PTY, VT, reply, or headless policy progress failure.
pub const ServiceError = pty.ReadError || pty.WriteError || pty.ObserveError ||
    vt.Terminal.FeedError || vt.Terminal.ClipboardReplyError ||
    vt.Terminal.ColorPreferenceReplyError || vt.Terminal.ContainerReplyError ||
    vt.Terminal.PointerShapeReplyError || error{WriteQueueFull};
/// Reports a backend-frame request before presentation exists, or Render failure.
pub const RenderError = terminal_render.Error || error{PresentationUnavailable};
/// Reports publication preparation or bounded exchange failure.
pub const PublishError = RenderError || std.mem.Allocator.Error || error{PublicationBusy};
/// Reports transactional font/renderer replacement or canonical geometry failure.
pub const ReconfigurePresentationError =
    text.InitError || terminal_render.InitError || terminal_render.Error ||
    ResizeError || error{
        PresentationUnavailable,
        PublicationCapacityMismatch,
        GenerationOverflow,
    };

/// Summarizes one bounded service turn without exposing PTY or VT ownership.
pub const Service = struct {
    changed: bool,
    /// True when this service turn changed visible-row or scroll/history state.
    viewport_changed: bool,
    /// Ordered semantic release/tail facts. Publication policy belongs to the caller.
    synchronized_output: Terminal.SynchronizedOutputProgress = .{},
    /// True when retained caller work exceeded its bounded queue and Instance
    /// applied deterministic headless policy to at least one older consequence.
    retained_consequence_fallback: bool = false,
    stream_closed: bool,
    child_exit: ?ChildExit,
    write_pending: bool,
    /// Milliseconds until the next retained terminal-animation boundary.
    animation_wait_ms: ?u32,
};

/// Constructs one PTY and VT owner from an explicit inherited environment.
pub fn init(
    allocator: std.mem.Allocator,
    inherited_environment: std.process.Environ,
    launch: Launch,
) InitError!*Instance {
    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    try state.initInto(allocator, inherited_environment, launch);
    // zig-audit: acknowledge ptr_cast
    // reason: This boundary owns or proves the concrete pointee layout; the cast only adapts it to the C/opaque ABI without changing address or lifetime.
    return @ptrCast(state);
}

/// Constructs one PTY -> VT -> Render owner on one caller-serialized thread.
///
/// Instance owns the supplied font family, canonical VT and Howl Renderer.
/// Initial PTY/VT pixel geometry comes from the regular font metrics.
pub fn initPresented(
    allocator: std.mem.Allocator,
    inherited_environment: std.process.Environ,
    launch: Launch,
    presentation: PresentationConfig,
) PresentedInitError!*Instance {
    var fonts = try OwnedFonts.init(allocator, presentation.fonts);
    var fonts_live = true;
    defer if (fonts_live) fonts.deinit();

    const metrics = fonts.regular.metrics();
    var canonical_launch = launch;
    canonical_launch.cell_pixel_width = metrics.advance_width;
    canonical_launch.cell_pixel_height = metrics.line_height;

    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    try state.initInto(allocator, inherited_environment, canonical_launch);
    errdefer state.deinit();

    state.presentation = try PresentationState.initWithFonts(
        allocator,
        &fonts,
        presentation,
        state.terminal.observation(),
    );
    fonts_live = false;

    // zig-audit: acknowledge ptr_cast
    // reason: This boundary owns the concrete State allocation and adapts it to the stable opaque Instance handle without changing address or lifetime.
    return @ptrCast(state);
}

/// Stops the child, releases VT state, and destroys the opaque owner.
pub fn deinit(instance: *Instance) void {
    const state = stateMut(instance);
    const allocator = state.allocator;
    state.deinit();
    allocator.destroy(state);
}

/// Returns the PTY descriptor for caller-owned poll integration.
pub fn descriptor(instance: *const Instance) error{NotStarted}!pty.Descriptor {
    return stateConst(instance).transport.masterFd();
}

/// True while a prior service turn retains child output in its bounded read buffer.
pub fn bufferedOutputPending(instance: *const Instance) bool {
    const state = stateConst(instance);
    return state.read_start < state.read_end;
}

/// True while caller input or terminal replies are queued for the child PTY.
///
/// Poll owners include writable readiness whenever this is true; unlike the
/// previous Service result, this reflects input admitted since the last turn.
pub fn writePending(instance: *const Instance) bool {
    return stateConst(instance).writes.count != 0;
}

/// Reports whether this Instance owns canonical text/Render presentation state.
pub fn presented(instance: *const Instance) bool {
    return stateConst(instance).presentation != null;
}

/// Reports current Instance-owned Render usage without exposing mutable Renderer state.
pub fn renderUsage(instance: *const Instance) error{PresentationUnavailable}!terminal_render.Usage {
    const presentation = stateConst(instance).presentation orelse return error.PresentationUnavailable;
    return terminal_render.usage(presentation.renderer);
}

/// Derives one backend-neutral frame from the current Instance-owned Render state.
///
/// Returned slices borrow caller buffers and remain valid until those buffers or
/// this Instance's Render state are mutated.
pub fn renderFrame(
    instance: *Instance,
    residency: []const terminal_render.Residency,
    buffers: terminal_render.FrameBuffers,
) RenderError!terminal_render.Frame {
    const state = stateMut(instance);
    const presentation = state.presentation orelse return error.PresentationUnavailable;
    try presentation.refresh(state.terminal.observation(), 0);
    return terminal_render.frame(presentation.renderer, residency, buffers);
}

/// Reports visible Host-owned terminal-image resources missing from backend residency.
pub fn missingRenderResources(
    instance: *Instance,
    residency: []const terminal_render.Residency,
    output: []terminal_render.FrameExternalResource,
) RenderError![]const terminal_render.FrameExternalResource {
    const state = stateMut(instance);
    const presentation = state.presentation orelse return error.PresentationUnavailable;
    try presentation.refresh(state.terminal.observation(), 0);
    return terminal_render.missingExternalResources(presentation.renderer, residency, output);
}

/// Borrows the backend-only exchange handle owned by this presented Instance.
///
/// The embedding render thread may retain this handle until Instance teardown,
/// but must not retain the Instance itself. All leases must be released before
/// the terminal thread destroys the Instance.
pub fn renderExchange(instance: *const Instance) error{PresentationUnavailable}!*RenderExchange {
    const presentation = stateConst(instance).presentation orelse return error.PresentationUnavailable;
    return presentation.exchange;
}

/// Publishes the newest canonical VT cut as one immutable backend transaction.
///
/// This is a terminal-thread operation. It never waits for the backend: an
/// unread older frame is replaceable, while a frame currently leased by the
/// backend remains immutable until release.
pub fn publishRender(instance: *Instance) PublishError!void {
    return publishRenderAt(instance, 0);
}

/// Publishes one canonical history cut through the same Instance-owned Renderer.
///
/// The history offset is clamped by VT observation semantics. View selection
/// stays on the terminal thread; the backend still receives only final Render work.
pub fn publishRenderAt(instance: *Instance, history_offset: u32) PublishError!void {
    const state = stateMut(instance);
    const presentation = state.presentation orelse return error.PresentationUnavailable;
    try presentation.publish(state.terminal.observation(), history_offset);
}

/// Transactionally replaces Instance-owned fonts and Renderer on the terminal thread.
///
/// The publication exchange survives the replacement. Its presentation generation
/// advances so a backend may safely release an older lease without making stale
/// residency visible to the new Renderer.
pub fn reconfigurePresentation(
    instance: *Instance,
    config: PresentationConfig,
) ReconfigurePresentationError!terminal_render.Size {
    const state = stateMut(instance);
    const view = state.terminal.semanticView(0);
    return (try state.reconfigurePresentationTarget(
        config,
        .{ .grid = .{ .rows = view.rows, .columns = view.cols } },
    )).cell_size;
}

/// Transactionally replaces presentation and canonical terminal geometry.
///
/// Font/Renderer construction and validation complete before PTY/VT geometry
/// commits, so after the resize succeeds the remaining owner swap is infallible.
pub fn reconfigurePresentationGeometry(
    instance: *Instance,
    config: PresentationConfig,
    rows: u16,
    columns: u16,
) ReconfigurePresentationError!terminal_render.Size {
    return (try stateMut(instance).reconfigurePresentationTarget(
        config,
        .{ .grid = .{ .rows = rows, .columns = columns } },
    )).cell_size;
}

/// Replaces presentation and derives the canonical grid from a physical surface.
///
/// Font metrics, rows/columns, PTY pixels, VT pixels and Render cell geometry
/// are chosen on the same terminal-thread transaction.
pub fn reconfigurePresentationSurface(
    instance: *Instance,
    config: PresentationConfig,
    surface: terminal_render.Size,
) ReconfigurePresentationError!PresentationGeometry {
    return stateMut(instance).reconfigurePresentationTarget(
        config,
        .{ .surface = surface },
    );
}

/// Borrows the canonical VT observation capability until the next Instance mutation.
///
/// Mutation remains Instance-owned so PTY writes, replies, resize and child
/// lifetime cannot be bypassed through this embedder observation seam.
pub fn terminal(instance: *const Instance) *const Terminal.Observation {
    return stateConst(instance).terminal.observation();
}

/// Borrows the oldest retained host consequence until canonical terminal mutation.
pub fn consequenceHead(instance: *const Instance) ?Consequence {
    return terminal(instance).consequenceHead();
}

/// Returns the bounded count of retained host consequences.
pub fn consequenceCount(instance: *const Instance) u16 {
    return terminal(instance).consequenceCount();
}

/// Consumes one non-reply consequence by exact global FIFO identity.
pub fn consumeConsequence(instance: *Instance, id: u64) ConsumeConsequenceError!void {
    return stateMut(instance).terminal.consumeConsequence(id);
}

/// Replies to one exact pending OSC 52 clipboard query.
pub fn replyClipboard(instance: *Instance, id: u64, bytes: []const u8) ClipboardReplyError!bool {
    return stateMut(instance).terminal.replyClipboard(id, bytes);
}

/// Replies to one exact pending OSC 22 pointer-shape query.
pub fn replyPointerShape(instance: *Instance, id: u64, payload: []const u8) PointerShapeReplyError!void {
    return stateMut(instance).terminal.replyPointerShape(id, payload);
}

/// Replies to one exact pending color-preference query.
pub fn replyColorPreference(
    instance: *Instance,
    id: u64,
    preference: ColorSchemePreference,
) ColorPreferenceReplyError!void {
    return stateMut(instance).terminal.replyColorPreference(id, preference);
}

/// Replies to one exact pending container query.
pub fn replyContainer(instance: *Instance, id: u64, reply: ContainerReply) ContainerReplyError!void {
    return stateMut(instance).terminal.replyContainer(id, reply);
}

/// Declines one exact pending container query without fabricating host state.
pub fn declineContainerQuery(
    instance: *Instance,
    id: u64,
) error{ StaleContainerRequest, ContainerReplyMismatch }!void {
    return stateMut(instance).terminal.declineContainerQuery(id);
}

/// Encodes and admits one input event in canonical instance order.
pub fn input(instance: *Instance, event: Input) InputError!void {
    return stateMut(instance).input(event);
}

/// Atomically applies one explicit canonical PTY and VT geometry.
pub fn resize(instance: *Instance, rows: u16, columns: u16) ResizeError!void {
    return stateMut(instance).resize(rows, columns);
}

/// Applies explicit cell-pixel metrics with canonical rows/columns and PTY size.
/// A zero pair preserves the previously accepted pixel lattice.
pub fn resizeGeometry(instance: *Instance, rows: u16, columns: u16, cell_width: u16, cell_height: u16) ResizeError!void {
    const state = stateMut(instance);
    if ((cell_width == 0) != (cell_height == 0)) return error.InvalidDimensions;
    if (state.presentation) |presentation| {
        const expected = presentation.cellSize();
        if (cell_width != 0 and
            (cell_width != expected.width or cell_height != expected.height))
            return error.InvalidDimensions;
        return state.resizeGeometry(rows, columns, .{
            .width = expected.width,
            .height = expected.height,
        });
    }
    const cell = if (cell_width == 0) state.terminal.cellPixelSize().? else vt.Terminal.CellPixelSize{ .width = cell_width, .height = cell_height };
    return state.resizeGeometry(rows, columns, cell);
}

fn ptyPixelExtent(cells: u16, pixels: u32) error{InvalidDimensions}!u16 {
    if (cells == 0 or pixels == 0) return error.InvalidDimensions;
    return std.math.cast(u16, @as(u64, cells) * pixels) orelse error.InvalidDimensions;
}

/// Delivers one fixed signal to the canonical child process group.
pub fn signal(instance: *Instance, requested: Signal) SignalResult {
    return stateMut(instance).transport.signal(requested);
}

/// Services bounded PTY read/write progress and canonical VT consequences.
pub fn service(
    instance: *Instance,
    readable: bool,
    writable: bool,
    timestamp_ns: u64,
) ServiceError!Service {
    return serviceWithConsequencePolicy(instance, readable, writable, timestamp_ns, .headless);
}

/// Services one turn, yielding on synchronized release and retaining any unread tail.
/// Callers continue while bufferedOutputPending, including without PTY readiness.
///
/// `.retain` leaves canonical VT consequences queued for an external authority;
/// `.headless` applies the existing deterministic fallback policy. Switching a
/// retained instance back to `.headless` drains already-pending consequences on
/// that same service turn, so authority loss cannot strand a terminal query.
pub fn serviceWithConsequencePolicy(
    instance: *Instance,
    readable: bool,
    writable: bool,
    timestamp_ns: u64,
    policy: ConsequencePolicy,
) ServiceError!Service {
    return stateMut(instance).service(readable, writable, timestamp_ns, policy);
}

const WriteQueue = struct {
    bytes: [write_queue_bytes]u8 = undefined,
    count: usize = 0,

    fn remaining(self: *const WriteQueue) usize {
        return self.bytes.len - self.count;
    }

    fn append(self: *WriteQueue, bytes: []const u8) error{WriteQueueFull}!void {
        if (bytes.len > self.remaining()) return error.WriteQueueFull;
        @memcpy(self.bytes[self.count..][0..bytes.len], bytes);
        self.count += bytes.len;
    }

    fn consume(self: *WriteQueue, count: usize) void {
        std.debug.assert(count <= self.count);
        std.mem.copyForwards(u8, self.bytes[0 .. self.count - count], self.bytes[count..self.count]);
        self.count -= count;
    }
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

    fn faces(self: *const OwnedFonts) terminal_render.FontFaces {
        return .{
            .regular = self.regular,
            .italic = self.italic,
            .bold = self.bold,
            .bold_italic = self.bold_italic,
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

const PresentationState = struct {
    renderer: *terminal_render.Renderer,
    fonts: OwnedFonts,
    exchange: *publication.Exchange,
    image_bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined,
    image_binding_count: usize = 0,
    terminal_revision: ?u64 = null,
    terminal_history_offset: u32 = 0,
    backend_residency: [publication.maximum_residencies]terminal_render.Residency = undefined,
    backend_residency_count: usize = 0,
    atlas_pixel_capacity: usize,
    command_capacity: usize,
    presentation_generation: u64 = 1,

    fn initWithFonts(
        allocator: std.mem.Allocator,
        fonts: *OwnedFonts,
        config: PresentationConfig,
        observation: *const Terminal.Observation,
    ) (terminal_render.InitError || terminal_render.Error)!*PresentationState {
        const metrics = fonts.regular.metrics();
        const renderer = try terminal_render.init(
            allocator,
            fonts.faces(),
            .{
                .cell_size = .{
                    .width = metrics.advance_width,
                    .height = metrics.line_height,
                },
                .box_drawing = config.box_drawing,
                .shape_cache = config.shape_cache,
                .atlas = config.atlas,
                .shaped_capacity = config.shaped_capacity,
                .raster_bytes = config.raster_bytes,
                .command_capacity = config.command_capacity,
                .command_limit = config.command_limit,
                .incremental_row_capacity = config.incremental_row_capacity,
                .incremental_command_capacity = config.incremental_command_capacity,
            },
        );
        errdefer terminal_render.deinit(renderer);
        const exchange = publication.init(allocator, config.command_capacity) catch |failure| switch (failure) {
            error.InvalidCapacity => return error.InvalidConfig,
            else => |err| return err,
        };
        errdefer publication.deinit(exchange);
        const atlas_pixel_capacity = std.math.mul(
            usize,
            @as(usize, config.atlas.width),
            @as(usize, config.atlas.height),
        ) catch return error.InvalidConfig;

        const state = try allocator.create(PresentationState);
        errdefer allocator.destroy(state);
        state.* = .{
            .renderer = renderer,
            .fonts = fonts.*,
            .exchange = exchange,
            .atlas_pixel_capacity = atlas_pixel_capacity,
            .command_capacity = config.command_capacity,
        };
        state.refresh(observation, 0) catch |failure| {
            allocator.destroy(state);
            return failure;
        };
        return state;
    }

    fn deinit(self: *PresentationState, allocator: std.mem.Allocator) void {
        publication.deinit(self.exchange);
        terminal_render.deinit(self.renderer);
        self.fonts.deinit();
        self.* = undefined;
        allocator.destroy(self);
    }

    fn cellSize(self: *const PresentationState) terminal_render.Size {
        const metrics = self.fonts.regular.metrics();
        return .{ .width = metrics.advance_width, .height = metrics.line_height };
    }

    fn refresh(
        self: *PresentationState,
        observation: *const Terminal.Observation,
        history_offset: u32,
    ) terminal_render.Error!void {
        const revision = observation.semanticSequence();
        const view = observation.semanticView(history_offset);
        if (self.terminal_revision != null and
            self.terminal_revision.? == revision and
            self.terminal_history_offset == view.history_offset)
            return;
        var candidate: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
        const bindings = try terminal_render.planObservationImageBindings(
            self.image_bindings[0..self.image_binding_count],
            terminal_render.usage(self.renderer),
            observation,
            view.history_offset,
            &candidate,
        );
        try terminal_render.updateObservation(
            self.renderer,
            observation,
            view.history_offset,
            bindings,
        );
        @memcpy(self.image_bindings[0..bindings.len], bindings);
        self.image_binding_count = bindings.len;
        self.terminal_revision = revision;
        self.terminal_history_offset = view.history_offset;
    }

    fn publish(
        self: *PresentationState,
        observation: *const Terminal.Observation,
        history_offset: u32,
    ) PublishError!void {
        try self.refresh(observation, history_offset);
        if (publication.takeLatestResidency(
            self.exchange,
            self.presentation_generation,
            &self.backend_residency,
        )) |accepted|
            self.backend_residency_count = accepted.len;

        var missing_storage: [terminal_render.maximum_external_images]terminal_render.FrameExternalResource = undefined;
        const missing = try terminal_render.missingExternalResources(
            self.renderer,
            self.backend_residency[0..self.backend_residency_count],
            &missing_storage,
        );

        var prospective: [publication.maximum_prospective_residencies]terminal_render.Residency = undefined;
        @memcpy(
            prospective[0..self.backend_residency_count],
            self.backend_residency[0..self.backend_residency_count],
        );
        var prospective_count = self.backend_residency_count;
        var external_pixel_count: usize = 0;
        const view = observation.semanticView(history_offset);
        var graphics = observation.images(view.history_offset);

        for (missing) |external| {
            if (external.format != .rgba8) return error.FormatMismatch;
            const binding = findImageBinding(
                self.image_bindings[0..self.image_binding_count],
                external.resource,
            ) orelse return error.InvalidImageBinding;
            const image = findTerminalImage(&graphics, binding.image_id, binding.generation) orelse
                return error.InvalidImageBinding;
            const stride = std.math.mul(
                usize,
                @as(usize, external.size.width),
                4,
            ) catch return error.ArithmeticOverflow;
            const bytes = std.math.mul(
                usize,
                stride,
                @as(usize, external.size.height),
            ) catch return error.ArithmeticOverflow;
            if (external.stride != stride or
                image.width != external.size.width or
                image.height != external.size.height)
                return error.ExtentMismatch;
            if (image.pixels.len != bytes) return error.InvalidPixels;
            external_pixel_count = std.math.add(
                usize,
                external_pixel_count,
                bytes,
            ) catch return error.ArithmeticOverflow;
            try upsertResidency(&prospective, &prospective_count, .{
                .resource = external.resource,
                .format = external.format,
                .size = external.size,
            });
        }

        var writer = publication.beginWrite(self.exchange) orelse
            return error.PublicationBusy;
        defer writer.abort();
        const pixel_capacity = std.math.add(
            usize,
            external_pixel_count,
            self.atlas_pixel_capacity,
        ) catch return error.ArithmeticOverflow;
        const pixels = try writer.pixelStorage(pixel_capacity);
        const uploads = writer.uploadStorage();

        var pixel_at: usize = 0;
        for (missing, 0..) |external, index| {
            const binding = findImageBinding(
                self.image_bindings[0..self.image_binding_count],
                external.resource,
            ).?;
            const image = findTerminalImage(&graphics, binding.image_id, binding.generation).?;
            const end = std.math.add(usize, pixel_at, image.pixels.len) catch
                return error.ArithmeticOverflow;
            @memcpy(pixels[pixel_at..end], image.pixels);
            uploads[index] = .{
                .resource = external.resource,
                .format = external.format,
                .size = external.size,
                .pixel_offset = pixel_at,
                .pixel_count = image.pixels.len,
                .stride = external.stride,
            };
            pixel_at = end;
        }
        std.debug.assert(pixel_at == external_pixel_count);

        const frame = try terminal_render.frame(
            self.renderer,
            prospective[0..prospective_count],
            .{
                .uploads = uploads[missing.len..],
                .removals = writer.removalStorage(),
                .commands = writer.commandStorage(),
                .pixels = pixels[external_pixel_count..],
            },
        );
        for (uploads[missing.len..][0..frame.uploads.len]) |*upload|
            upload.pixel_offset = std.math.add(
                usize,
                upload.pixel_offset,
                external_pixel_count,
            ) catch return error.ArithmeticOverflow;

        const cell_size = self.cellSize();
        const surface = terminal_render.Size{
            .width = std.math.mul(u16, view.cols, cell_size.width) catch
                return error.InvalidPresentationGeometry,
            .height = std.math.mul(u16, view.rows, cell_size.height) catch
                return error.InvalidPresentationGeometry,
        };
        writer.finish(
            self.presentation_generation,
            frame.revision,
            observation.semanticSequence(),
            view.history_offset,
            view.history_count,
            view.history_row_base,
            view.is_alternate_screen,
            surface,
            cell_size,
            missing.len + frame.uploads.len,
            frame.removals.len,
            frame.commands.len,
            external_pixel_count + frame.pixels.len,
        );
    }
};

fn findImageBinding(
    bindings: []const terminal_render.ExternalImageBinding,
    resource: terminal_render.ResourceRef,
) ?terminal_render.ExternalImageBinding {
    for (bindings) |binding| {
        if (binding.resource.resource == resource.resource and
            binding.resource.generation == resource.generation)
            return binding;
    }
    return null;
}

fn findTerminalImage(
    images: *const Terminal.Images,
    image_id: u32,
    generation: u64,
) ?Terminal.Image {
    var index: usize = 0;
    while (index < images.imageCount()) : (index += 1) {
        const image = images.image(index) orelse continue;
        if (image.id == image_id and image.generation == generation) return image;
    }
    return null;
}

fn upsertResidency(
    storage: *[publication.maximum_prospective_residencies]terminal_render.Residency,
    count: *usize,
    value: terminal_render.Residency,
) terminal_render.Error!void {
    var index: usize = 0;
    while (index < count.*) : (index += 1) {
        if (storage[index].resource.resource == value.resource.resource) {
            storage[index] = value;
            return;
        }
    }
    if (count.* == storage.len) return error.ResourceLimit;
    storage[count.*] = value;
    count.* += 1;
}

const State = struct {
    allocator: std.mem.Allocator,
    transport: pty.Owned,
    terminal: vt.Terminal,
    presentation: ?*PresentationState = null,
    writes: WriteQueue = .{},
    reads: [read_buffer_bytes]u8 = undefined,
    read_start: usize = 0,
    read_end: usize = 0,
    child_exit: ?ChildExit = null,
    stream_closed: bool = false,

    fn initInto(
        self: *State,
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        launch: Launch,
    ) InitError!void {
        if (launch.rows == 0 or launch.columns == 0 or
            launch.cell_pixel_width == 0 or launch.cell_pixel_height == 0)
            return error.InvalidDimensions;
        var transport = try pty.Owned.init(
            allocator,
            inherited_environment,
            launch.shell,
            launch.command,
            launch.cwd,
            .{ .term = launch.term, .colorterm = launch.colorterm },
        );
        errdefer transport.deinit();
        const pixel_width = try ptyPixelExtent(launch.columns, launch.cell_pixel_width);
        const pixel_height = try ptyPixelExtent(launch.rows, launch.cell_pixel_height);
        try transport.startWithPixels(launch.columns, launch.rows, pixel_width, pixel_height);

        self.allocator = allocator;
        self.transport = transport;
        self.writes = .{};
        self.read_start = 0;
        self.read_end = 0;
        self.child_exit = null;
        self.stream_closed = false;
        self.presentation = null;
        try vt.Terminal.initWithHistoryInto(
            &self.terminal,
            allocator,
            launch.rows,
            launch.columns,
            launch.history_rows,
        );
        errdefer self.terminal.deinit();
        try self.terminal.setCellPixelSize(launch.cell_pixel_width, launch.cell_pixel_height);
    }

    fn deinit(self: *State) void {
        if (self.presentation) |presentation| presentation.deinit(self.allocator);
        self.terminal.deinit();
        self.transport.deinit();
        self.* = undefined;
    }

    const PresentationTarget = union(enum) {
        grid: struct {
            rows: u16,
            columns: u16,
        },
        surface: terminal_render.Size,
    };

    fn reconfigurePresentationTarget(
        self: *State,
        config: PresentationConfig,
        target: PresentationTarget,
    ) ReconfigurePresentationError!PresentationGeometry {
        const presentation = self.presentation orelse
            return error.PresentationUnavailable;
        if (config.command_capacity != presentation.command_capacity)
            return error.PublicationCapacityMismatch;

        var fonts = try OwnedFonts.init(self.allocator, config.fonts);
        var fonts_live = true;
        defer if (fonts_live) fonts.deinit();

        const metrics = fonts.regular.metrics();
        const cell_size = terminal_render.Size{
            .width = metrics.advance_width,
            .height = metrics.line_height,
        };
        const rows, const columns = switch (target) {
            .grid => |grid| .{ grid.rows, grid.columns },
            .surface => |surface| choose: {
                if (surface.width == 0 or surface.height == 0)
                    return error.InvalidDimensions;
                const rows = surface.height / cell_size.height;
                const columns = surface.width / cell_size.width;
                if (rows == 0 or columns < 2) return error.InvalidDimensions;
                break :choose .{ rows, columns };
            },
        };
        const renderer = try terminal_render.init(
            self.allocator,
            fonts.faces(),
            .{
                .cell_size = cell_size,
                .box_drawing = config.box_drawing,
                .shape_cache = config.shape_cache,
                .atlas = config.atlas,
                .shaped_capacity = config.shaped_capacity,
                .raster_bytes = config.raster_bytes,
                .command_capacity = config.command_capacity,
                .command_limit = config.command_limit,
                .incremental_row_capacity = config.incremental_row_capacity,
                .incremental_command_capacity = config.incremental_command_capacity,
            },
        );
        var renderer_live = true;
        defer if (renderer_live) terminal_render.deinit(renderer);

        const observation = self.terminal.observation();
        const old_revision = observation.semanticSequence();
        var candidate_bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
        const bindings = try terminal_render.planObservationImageBindings(
            &.{},
            terminal_render.usage(renderer),
            observation,
            0,
            &candidate_bindings,
        );
        try terminal_render.updateObservation(
            renderer,
            observation,
            0,
            bindings,
        );
        const atlas_pixel_capacity = std.math.mul(
            usize,
            @as(usize, config.atlas.width),
            @as(usize, config.atlas.height),
        ) catch return error.InvalidConfig;

        const next_generation = std.math.add(
            u64,
            presentation.presentation_generation,
            1,
        ) catch return error.GenerationOverflow;

        const previous_cell = self.terminal.cellPixelSize().?;
        const current = observation.semanticView(0);
        if (current.rows != rows or current.cols != columns or
            previous_cell.width != cell_size.width or
            previous_cell.height != cell_size.height)
        {
            try self.resizeGeometry(
                rows,
                columns,
                .{ .width = cell_size.width, .height = cell_size.height },
            );
        }

        terminal_render.deinit(presentation.renderer);
        presentation.fonts.deinit();
        presentation.renderer = renderer;
        renderer_live = false;
        presentation.fonts = fonts;
        fonts_live = false;
        @memcpy(presentation.image_bindings[0..bindings.len], bindings);
        presentation.image_binding_count = bindings.len;
        presentation.terminal_revision = old_revision;
        presentation.terminal_history_offset = 0;
        presentation.backend_residency_count = 0;
        presentation.atlas_pixel_capacity = atlas_pixel_capacity;
        presentation.presentation_generation = next_generation;
        return .{
            .cell_size = cell_size,
            .rows = rows,
            .columns = columns,
        };
    }

    fn input(self: *State, event: Input) InputError!void {
        const admission = try inputAdmissionBytes(event);
        const required = std.math.add(usize, admission, self.terminal.replyBytes().len) catch
            return error.WriteQueueFull;
        if (required > self.writes.remaining()) return error.WriteQueueFull;
        var scratch: vt.Terminal.InputScratch = undefined;
        var encoded = try self.terminal.encodeInput(self.allocator, &scratch, event);
        defer encoded.deinit();
        if (encoded.bytes.len == 1 and self.terminal.termiosSignals() and
            try self.transport.handleTermiosSignal(encoded.bytes[0]))
        {
            try collectReplies(&self.terminal, &self.writes);
            return;
        }
        try collectReplies(&self.terminal, &self.writes);
        try self.writes.append(encoded.bytes);
    }

    fn resize(self: *State, rows: u16, columns: u16) ResizeError!void {
        return self.resizeGeometry(rows, columns, self.terminal.cellPixelSize().?);
    }

    fn resizeGeometry(self: *State, rows: u16, columns: u16, cell: vt.Terminal.CellPixelSize) ResizeError!void {
        const width = try ptyPixelExtent(columns, cell.width);
        const height = try ptyPixelExtent(rows, cell.height);
        var prepared = try self.terminal.prepareResizeGeometry(rows, columns, cell);
        defer prepared.deinit();
        try self.transport.resizeWithPixels(columns, rows, width, height);
        prepared.commit();
    }

    fn service(
        self: *State,
        readable: bool,
        writable: bool,
        timestamp_ns: u64,
        consequence_policy: ConsequencePolicy,
    ) ServiceError!Service {
        const revision_before = self.terminal.semanticSequence();
        var viewport_changed = false;
        var synchronized_output: Terminal.SynchronizedOutputProgress = .{};
        var retained_consequence_fallback = false;
        if (consequence_policy == .headless) try self.drainConsequences();
        if (writable and self.writes.count != 0) try flushWrites(&self.transport, &self.writes);
        collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
            error.WriteQueueFull => return self.serviceResult(
                revision_before,
                timestamp_ns,
                viewport_changed,
                synchronized_output,
                retained_consequence_fallback,
            ),
        };
        try self.processBuffered(
            timestamp_ns,
            consequence_policy,
            &viewport_changed,
            &synchronized_output,
            &retained_consequence_fallback,
        );
        if (self.read_start == self.read_end and readable and !self.stream_closed) {
            var read_calls: u8 = 0;
            while (read_calls < read_calls_per_turn and self.read_start == self.read_end and
                !self.stream_closed and !synchronized_output.ended)
            {
                const count = self.transport.read(&self.reads) catch |failure| switch (failure) {
                    error.Interrupted, error.WouldBlock => 0,
                    error.EndOfStream => closed: {
                        self.stream_closed = true;
                        break :closed 0;
                    },
                    else => return failure,
                };
                if (count == 0) break;
                read_calls += 1;
                self.read_start = 0;
                self.read_end = count;
                try self.processBuffered(
                    timestamp_ns,
                    consequence_policy,
                    &viewport_changed,
                    &synchronized_output,
                    &retained_consequence_fallback,
                );
                // Yield as soon as this service turn has caller-visible work.
                // Pure output may drain a few immediately-ready PTY reads, but
                // releases, replies, consequences, or a partial VT boundary get
                // control back before another read is admitted.
                if (self.read_start != self.read_end or self.writes.count != 0) break;
                if (consequence_policy == .retain and self.terminal.consequenceHead() != null) break;
            }
        }
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |value| self.child_exit = value,
        }
        return self.serviceResult(
            revision_before,
            timestamp_ns,
            viewport_changed,
            synchronized_output,
            retained_consequence_fallback,
        );
    }

    fn processBuffered(
        self: *State,
        timestamp_ns: u64,
        consequence_policy: ConsequencePolicy,
        viewport_changed: *bool,
        synchronized_output: *Terminal.SynchronizedOutputProgress,
        retained_consequence_fallback: *bool,
    ) ServiceError!void {
        while (self.read_start < self.read_end) {
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
            const progress = if (consequence_policy == .retain)
                try self.terminal.feedAtServiceBoundaryRelievingConsequences(
                    self.reads[self.read_start..self.read_end],
                    timestamp_ns,
                    relieveConsequencePressure,
                )
            else
                try self.terminal.feedAtServiceBoundary(
                    self.reads[self.read_start..self.read_end],
                    timestamp_ns,
                );
            std.debug.assert(progress.consumed > 0);
            std.debug.assert(progress.consumed <= self.read_end - self.read_start);
            self.read_start += progress.consumed;
            viewport_changed.* = viewport_changed.* or progress.summary.mutations.viewport;
            synchronized_output.merge(progress.summary.synchronized_output);
            retained_consequence_fallback.* =
                retained_consequence_fallback.* or progress.consequence_pressure_relieved;
            std.debug.assert(!progress.summary.titleChanged() or progress.summary.stateChanged());
            if (consequence_policy == .headless) try self.drainConsequences();
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
            if (progress.summary.synchronized_output.ended and self.read_start < self.read_end) return;
        }
        self.read_start = 0;
        self.read_end = 0;
    }

    fn drainConsequences(self: *State) ServiceError!void {
        while (self.terminal.consequenceHead() != null)
            try relieveConsequencePressure(&self.terminal);
        std.debug.assert(self.terminal.consequenceHead() == null);
    }

    fn serviceResult(
        self: *State,
        revision_before: u64,
        timestamp_ns: u64,
        viewport_changed: bool,
        synchronized_output: Terminal.SynchronizedOutputProgress,
        retained_consequence_fallback: bool,
    ) Service {
        const animation = self.terminal.serviceAnimations(timestamp_ns);
        return .{
            .changed = self.terminal.semanticSequence() != revision_before,
            .viewport_changed = viewport_changed,
            .synchronized_output = synchronized_output,
            .retained_consequence_fallback = retained_consequence_fallback,
            .stream_closed = self.stream_closed,
            .child_exit = self.child_exit,
            .write_pending = self.writes.count != 0,
            .animation_wait_ms = animation.next_ms,
        };
    }
};

/// Applies one deterministic headless fallback to the global consequence head.
/// Service-boundary VT feeds use this only when a valid new consequence cannot
/// fit because already-retained caller work exhausted its bounded family.
fn relieveConsequencePressure(machine: *vt.Terminal) vt.Terminal.FeedError!void {
    const current = machine.consequenceHead() orelse return error.ConsequencePressure;
    const identity = current.id();
    switch (current) {
        .clipboard => |request| if (request.kind == .query) {
            const replied = machine.replyClipboard(identity, "") catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
                error.StaleClipboardRequest => unreachable,
                else => |err| return err,
            };
            std.debug.assert(replied);
            return;
        },
        .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
            machine.replyPointerShape(identity, "default") catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
                error.StalePointerShape, error.PointerShapeReplyMismatch => unreachable,
                else => |err| return err,
            };
            return;
        },
        .container => |occurrence| switch (occurrence.request) {
            .report_screen_cells => {
                const terminal_view = machine.semanticView(0);
                machine.replyContainer(identity, .{ .screen_cells = .{
                    .rows = terminal_view.rows,
                    .cols = terminal_view.cols,
                } }) catch |failure| switch (failure) {
                    // zig-audit: acknowledge unreachable
                    // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
                    error.StaleContainerRequest, error.ContainerReplyMismatch => unreachable,
                    else => |err| return err,
                };
                return;
            },
            .report_state, .report_position, .report_icon_title => {
                // zig-audit: acknowledge catch_unreachable
                // reason: The operation runs on state or storage already validated/reserved by this owner; failure would contradict the established invariant.
                machine.declineContainerQuery(identity) catch unreachable;
                return;
            },
            else => {},
        },
        .color_preference_query => {
            machine.replyColorPreference(identity, .dark) catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
                error.StaleColorPreferenceQuery => unreachable,
                else => |err| return err,
            };
            return;
        },
        else => {},
    }
    machine.consumeConsequence(identity) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
        error.StaleConsequence, error.ReplyRequired => unreachable,
    };
}

fn stateMut(instance: *Instance) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: This boundary owns or proves the concrete pointee layout; the cast only adapts it to the C/opaque ABI without changing address or lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The originating allocation/ABI preserves this type alignment; the cast asserts that invariant before recovering the concrete view.
    return @ptrCast(@alignCast(instance));
}

fn stateConst(instance: *const Instance) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: This boundary owns or proves the concrete pointee layout; the cast only adapts it to the C/opaque ABI without changing address or lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The originating allocation/ABI preserves this type alignment; the cast asserts that invariant before recovering the concrete view.
    return @ptrCast(@alignCast(instance));
}

fn collectReplies(machine: *vt.Terminal, queue: *WriteQueue) error{WriteQueueFull}!void {
    const bytes = machine.replyBytes();
    if (bytes.len == 0) return;
    try queue.append(bytes);
    // zig-audit: acknowledge catch_unreachable
    // reason: The operation runs on state or storage already validated/reserved by this owner; failure would contradict the established invariant.
    machine.consumeReplyBytes(bytes.len) catch unreachable;
}

fn flushWrites(owner: *pty.Owned, queue: *WriteQueue) pty.WriteError!void {
    var calls: usize = 0;
    var written: usize = 0;
    while (calls < write_calls_per_turn and written < write_bytes_per_turn and queue.count != 0) {
        calls += 1;
        const budget = @min(queue.count, write_bytes_per_turn - written);
        const accepted = owner.write(queue.bytes[0..budget]) catch |failure| switch (failure) {
            error.Interrupted => continue,
            error.WouldBlock => return,
            else => return failure,
        };
        std.debug.assert(accepted <= budget);
        queue.consume(accepted);
        written += accepted;
    }
}

fn inputAdmissionBytes(event: Input) error{WriteQueueFull}!usize {
    return switch (event) {
        .bytes => |bytes| bytes.len,
        .paste => |bytes| std.math.add(usize, bytes.len, 12) catch return error.WriteQueueFull,
        .key, .mouse, .focus => @sizeOf(vt.Terminal.InputScratch),
    };
}

fn snapshotAscii(instance: *const Instance, output: []u8) error{SnapshotLimit}![]const u8 {
    const current = terminal(instance).semanticView(0);
    if (current.cols > 512) return error.SnapshotLimit;
    var offset: usize = 0;
    var row: u16 = 0;
    while (row < current.rows) : (row += 1) {
        var column: u16 = 0;
        while (column < current.cols) : (column += 1) {
            const cell = current.cellInfoAt(row, column);
            if (offset == output.len) return error.SnapshotLimit;
            output[offset] = if (cell.x == 0 and cell.y == 0 and cell.codepoint >= 0x20 and cell.codepoint <= 0x7e)
                @intCast(cell.codepoint)
            else
                ' ';
            offset += 1;
        }
        if (offset == output.len) return error.SnapshotLimit;
        output[offset] = '\n';
        offset += 1;
    }
    return output[0..offset];
}

fn testTerminalImage(machine: *const Terminal.Observation, image_id: u32, generation: u64) ?Terminal.Image {
    var images = machine.images(0);
    var index: usize = 0;
    while (index < images.imageCount()) : (index += 1) {
        const candidate = images.image(index) orelse continue;
        if (candidate.id == image_id and candidate.generation == generation) return candidate;
    }
    return null;
}

fn sleepOneMillisecond() void {
    std.Io.sleep(std.testing.io, .fromMilliseconds(1), .awake) catch
        // zig-audit: acknowledge panic
        // reason: Test scaffolding treats setup/protocol failure as an immediate proof failure instead of widening the product error surface.
        @panic("test sleep failed");
}

fn serviceUntilContains(instance: *Instance, needle: []const u8) !void {
    var snapshot_text: [4096]u8 = undefined;
    var attempts: u16 = 0;
    while (attempts < 2000) : (attempts += 1) {
        const serviced = try service(instance, true, true, 0);
        if (serviced.stream_closed and serviced.child_exit != null) return error.ChildExited;
        if (std.mem.indexOf(u8, try snapshotAscii(instance, &snapshot_text), needle) != null) return;
        sleepOneMillisecond();
    }
    return error.Timeout;
}

test "headless instance drains host consequences without an observer" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 4,
        .columns = 20,
        .history_rows = 16,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    const before = terminal(instance).semanticView(0);
    const prepared = try state.terminal.feed(
        "\x1b]22;?__current__\x1b\\" ++
            "\x1b]52;c;?\x07" ++
            "\x1b]9;notice\x07" ++
            "\x1b[8;12;34t" ++
            "\x1b[?2031h\x1b[?996n",
    );
    try std.testing.expect(prepared.stateChanged());
    try state.drainConsequences();
    const after = terminal(instance).semanticView(0);
    try std.testing.expectEqual(before.rows, after.rows);
    try std.testing.expectEqual(before.cols, after.cols);
    try std.testing.expect(state.terminal.consequenceHead() == null);
    try std.testing.expect(std.mem.indexOf(u8, state.terminal.replyBytes(), "default") != null);
}

test "service separates in-place text from viewport mutation" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 4,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    state.reads[0] = 'A';
    state.read_start = 0;
    state.read_end = 1;
    const text_service = try state.service(false, false, 1, .headless);
    try std.testing.expect(text_service.changed);
    try std.testing.expect(!text_service.viewport_changed);

    @memcpy(state.reads[0..2], "\n\n");
    state.read_start = 0;
    state.read_end = 2;
    const scroll = try state.service(false, false, 2, .headless);
    try std.testing.expect(scroll.changed);
    try std.testing.expect(scroll.viewport_changed);
}

test "instance services terminal animation without PTY readiness" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 3,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=20,C=1,q=2;/wAA/w==\x1b\\",
    )).stateChanged());
    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=f,f=32,i=20,s=1,v=1,r=2,z=50,C=1,q=2;AAD/gA==\x1b\\",
    )).stateChanged());
    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=a,i=20,s=3,r=1,z=40,q=2\x1b\\",
    )).stateChanged());

    var initial_images = terminal(instance).images(0);
    const initial = initial_images.image(0) orelse return error.MissingImage;
    const image_id = initial.id;
    const initial_generation = initial.generation;
    const started_revision = terminal(instance).semanticSequence();

    const started = try service(instance, false, false, 100 * std.time.ns_per_ms);
    try std.testing.expect(!started.changed);
    try std.testing.expectEqual(@as(?u32, 40), started.animation_wait_ms);
    try std.testing.expectEqual(started_revision, terminal(instance).semanticSequence());

    const advanced = try service(instance, false, false, 140 * std.time.ns_per_ms);
    try std.testing.expect(advanced.changed);
    try std.testing.expectEqual(@as(?u32, 50), advanced.animation_wait_ms);
    try std.testing.expectEqual(started_revision + 1, terminal(instance).semanticSequence());
    var advanced_images = terminal(instance).images(0);
    const current = advanced_images.image(0) orelse return error.MissingImage;
    try std.testing.expect(current.generation > initial_generation);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 128 }, current.pixels);
    try std.testing.expect(testTerminalImage(terminal(instance), image_id, initial_generation) == null);
    try std.testing.expect(testTerminalImage(terminal(instance), image_id, current.generation) != null);
}

test "retained host query falls back headlessly when external authority disappears" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo -icanon min 1 time 0; " ++
            "printf '\\033]52;c;?\\007'; " ++
            "bytes=$(dd bs=1 count=9 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'); " ++
            "printf 'RESULT:%s\n' \"$bytes\"; cat",
        .rows = 4,
        .columns = 40,
        .history_rows = 16,
    });
    defer deinit(instance);

    var attempts: u16 = 0;
    while (consequenceHead(instance) == null and attempts < 2000) : (attempts += 1) {
        const serviced = try serviceWithConsequencePolicy(instance, true, true, 0, .retain);
        try std.testing.expect(!serviced.stream_closed);
        sleepOneMillisecond();
    }
    const pending = consequenceHead(instance) orelse return error.Timeout;
    try std.testing.expectEqual(@as(u16, 1), consequenceCount(instance));
    try std.testing.expect(std.meta.activeTag(pending) == .clipboard);
    try std.testing.expectEqualStrings("c", pending.clipboard.selection);
    try std.testing.expect(pending.clipboard.kind == .query);

    var snapshot_text: [4096]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, try snapshotAscii(instance, &snapshot_text), "RESULT:") == null);

    // Losing explicit external authority restores today's deterministic
    // headless reply policy on the next turn, without waiting for new PTY bytes.
    const fallback = try serviceWithConsequencePolicy(instance, false, true, 0, .headless);
    try std.testing.expect(fallback.write_pending);
    try std.testing.expect(consequenceHead(instance) == null);
    try serviceUntilContains(instance, "RESULT:1b5d35323b633b1b5c");
}

test "one PTY and VT remain canonical for independent observers" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'READY\\n'; cat",
        .rows = 8,
        .columns = 40,
        .history_rows = 64,
    });
    defer deinit(instance);
    try serviceUntilContains(instance, "READY");

    const before = terminal(instance).semanticSequence();
    try input(instance, .{ .bytes = "SHARED-LINE\n" });
    try serviceUntilContains(instance, "SHARED-LINE");
    try std.testing.expect(terminal(instance).semanticSequence() > before);

    var first: [4096]u8 = undefined;
    var second: [4096]u8 = undefined;
    const first_view = try snapshotAscii(instance, &first);
    const second_view = try snapshotAscii(instance, &second);
    try std.testing.expectEqualSlices(u8, first_view, second_view);
}

test "headless service drains consequence bursts at VT service boundaries" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "i=0; while [ $i -lt 64 ]; do printf '\\007'; i=$((i+1)); done; printf 'BOUNDARY-DONE\\n'; cat",
        .rows = 4,
        .columns = 32,
        .history_rows = 16,
    });
    defer deinit(instance);

    try serviceUntilContains(instance, "BOUNDARY-DONE");
    try std.testing.expectEqual(@as(u16, 0), consequenceCount(instance));
}

test "Instance pixel geometry agrees with PTY reports and rejects overflow transactionally" {
    if (comptime @import("builtin").os.tag != .linux) return error.SkipZigTest;
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 3,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);
    const fd = try descriptor(instance);
    var size: std.posix.winsize = undefined;
    const linux = std.os.linux;
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqual(@as(u16, 80), size.xpixel);
    try std.testing.expectEqual(@as(u16, 60), size.ypixel);
    const before = terminal(instance).semanticSequence();
    try resizeGeometry(instance, 3, 8, 11, 24);
    try std.testing.expect(terminal(instance).semanticSequence() > before);
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqual(@as(u16, 88), size.xpixel);
    try std.testing.expectEqual(@as(u16, 72), size.ypixel);
    const queried = try state.terminal.feed("\x1b[14t\x1b[16t");
    try std.testing.expect(queried.stateChanged());
    try std.testing.expectEqualStrings("\x1b[4;72;88t\x1b[6;24;11t", state.terminal.replyBytes());
    try resize(instance, 4, 9);
    try std.testing.expectEqual(@as(u32, 11), state.terminal.cellPixelSize().?.width);
    const accepted = terminal(instance).semanticView(0);
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    const accepted_pty = size;
    try std.testing.expectError(error.InvalidDimensions, resizeGeometry(instance, 4, 9, 11, 0));
    try std.testing.expectError(error.InvalidDimensions, resizeGeometry(instance, 4, 9, 65535, 24));
    try std.testing.expectEqualDeep(accepted, terminal(instance).semanticView(0));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqualDeep(accepted_pty, size);
    state.transport.stop();
    try std.testing.expectError(error.NotStarted, resizeGeometry(instance, 5, 10, 12, 26));
    try std.testing.expectEqualDeep(accepted, terminal(instance).semanticView(0));
    try std.testing.expectEqual(@as(u32, 11), state.terminal.cellPixelSize().?.width);
}

test "Instance lends only the opaque VT observation capability" {
    const return_type = @typeInfo(@TypeOf(terminal)).@"fn".return_type.?;
    const pointer = @typeInfo(return_type).pointer;
    try std.testing.expect(pointer.attrs.@"const");
    try std.testing.expect(pointer.child == Terminal.Observation);
    try std.testing.expect(@typeInfo(pointer.child) == .@"opaque");
}

test "retained consequence pressure preserves canonical progress within fixed bounds" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    var bytes: [66]u8 = undefined;
    bytes[0] = 'X';
    @memset(bytes[1..65], 0x07);
    bytes[65] = 'Y';
    @memcpy(state.reads[0..bytes.len], &bytes);
    state.read_start = 0;
    state.read_end = bytes.len;

    const serviced = try state.service(false, false, 1, .retain);
    try std.testing.expect(serviced.changed);
    try std.testing.expect(serviced.retained_consequence_fallback);
    try std.testing.expectEqual(@as(u16, 32), state.terminal.consequenceCount());
    const view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(@as(usize, 0), state.read_end);
}

test "retained reply-required pressure defaults oldest query and admits newest" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    for (0..8) |_| {
        try std.testing.expect((try state.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    }
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());

    const pressure = "X\x1b]52;c;?\x07Y";
    @memcpy(state.reads[0..pressure.len], pressure);
    state.read_start = 0;
    state.read_end = pressure.len;
    const serviced = try state.service(false, false, 2, .retain);

    try std.testing.expect(serviced.changed);
    try std.testing.expect(serviced.retained_consequence_fallback);
    try std.testing.expect(serviced.write_pending);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), state.terminal.consequenceHead().?.id());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", state.writes.bytes[0..state.writes.count]);
    const view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
}

test "fragmented retained clipboard pressure preserves exact text and FIFO identity" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 16,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    for (0..8) |_| {
        try std.testing.expect((try state.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    }
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());

    const prefix = "X\x1b]52;c;";
    @memcpy(state.reads[0..prefix.len], prefix);
    state.read_start = 0;
    state.read_end = prefix.len;
    const first = try state.service(false, false, 1, .retain);
    try std.testing.expect(first.changed);
    try std.testing.expect(!first.retained_consequence_fallback);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());
    var view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));

    const suffix = "?\x07Y";
    @memcpy(state.reads[0..suffix.len], suffix);
    state.read_start = 0;
    state.read_end = suffix.len;
    const second = try state.service(false, false, 2, .retain);
    try std.testing.expect(second.changed);
    try std.testing.expect(second.retained_consequence_fallback);
    try std.testing.expect(second.write_pending);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), state.terminal.consequenceHead().?.id());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", state.writes.bytes[0..state.writes.count]);

    view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(@as(usize, 0), state.read_end);

    var expected_id: u64 = 2;
    while (state.terminal.consequenceHead()) |head| : (expected_id += 1) {
        try std.testing.expectEqual(expected_id, head.id());
        const replied = try state.terminal.replyClipboard(head.id(), "");
        try std.testing.expect(replied);
    }
    try std.testing.expectEqual(@as(u64, 10), expected_id);
}

test "write backpressure preserves reply ordering and unread PTY suffix" {
    const instance = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 16,
        .history_rows = 8,
    });
    defer deinit(instance);
    const state = stateMut(instance);

    for (0..8) |_| {
        try std.testing.expect((try state.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    }
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());

    // One older terminal reply is already waiting to enter Instance's bounded
    // child-write queue.
    const dsr = try state.terminal.feed("\x1b[5n");
    try std.testing.expect(dsr.stateChanged());
    try std.testing.expectEqualStrings("\x1b[0n", state.terminal.replyBytes());
    const older_reply_len = state.terminal.replyBytes().len;

    @memset(&state.writes.bytes, 'W');
    state.writes.count = state.writes.bytes.len;

    const pressure = "X\x1b]52;c;?\x07Y";
    @memcpy(state.reads[0..pressure.len], pressure);
    state.read_start = 0;
    state.read_end = pressure.len;

    const blocked = try state.service(false, false, 1, .retain);
    try std.testing.expect(!blocked.changed);
    try std.testing.expect(blocked.write_pending);
    try std.testing.expect(!blocked.retained_consequence_fallback);
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(pressure.len, state.read_end);
    try std.testing.expectEqualStrings("\x1b[0n", state.terminal.replyBytes());

    // Make room for exactly the older reply. It must transfer before PTY input
    // advances. The pressure-causing query then defaults generation 1 and
    // creates its own fallback reply, but that new reply remains in VT because
    // the Instance queue is full again.
    state.writes.count -= older_reply_len;
    const partial = try state.service(false, false, 2, .retain);
    try std.testing.expect(partial.changed);
    try std.testing.expect(partial.write_pending);
    try std.testing.expect(partial.retained_consequence_fallback);
    try std.testing.expectEqual(state.writes.bytes.len, state.writes.count);
    try std.testing.expectEqualStrings(
        "\x1b[0n",
        state.writes.bytes[state.writes.count - older_reply_len .. state.writes.count],
    );
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", state.terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), state.terminal.consequenceHead().?.id());
    try std.testing.expectEqual(@as(usize, pressure.len - 1), state.read_start);
    try std.testing.expectEqual(pressure.len, state.read_end);
    var view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));

    // Simulate bounded transport progress. The pending fallback reply transfers
    // first on the next service turn, then the unread Y applies exactly once.
    state.writes.consume(state.writes.count);
    const resumed = try state.service(false, false, 3, .retain);
    try std.testing.expect(resumed.changed);
    try std.testing.expect(resumed.write_pending);
    try std.testing.expect(!resumed.retained_consequence_fallback);
    try std.testing.expectEqualStrings(
        "\x1b]52;c;\x1b\\",
        state.writes.bytes[0..state.writes.count],
    );
    try std.testing.expectEqual(@as(usize, 0), state.terminal.replyBytes().len);
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(@as(usize, 0), state.read_end);
    view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
}

test "service preserves synchronized release across buffered feeds and reply boundaries" {
    const Case = struct { bytes: []const u8, ended: bool, held: bool, tail: []const u8 = "" };
    const cases = [_]Case{
        .{ .bytes = "A", .ended = false, .held = false },
        .{ .bytes = "\x1b[?2026hA\x1b[?2026l", .ended = true, .held = false },
        .{ .bytes = "\x1b[?2026hA\x1b[6n\x1b[?2026l", .ended = true, .held = false },
        .{ .bytes = "\x1bP=1s\x1b\\A\x1bP=2s\x1b\\", .ended = true, .held = false },
        .{ .bytes = "\x1b[?2026hA\x1b[?2026l\x1b[?2026hB", .ended = true, .held = false, .tail = "\x1b[?2026hB" },
        .{ .bytes = "\x1bP=1s\x1b\\A\x1bP=2s\x1b\\\x1b[?2026hB", .ended = true, .held = false, .tail = "\x1b[?2026hB" },
        .{ .bytes = "\x1b[?2026hA\x1b[6n\x1b[?2026l\x1b[?2026hB", .ended = true, .held = false, .tail = "\x1b[?2026hB" },
        .{ .bytes = "A\x1b[?2026lB", .ended = false, .held = false },
    };
    for (cases) |case| {
        const instance = try init(std.testing.allocator, std.testing.environ, .{
            .shell = "/bin/sh",
            .command = "exec sleep 30",
            .rows = 2,
            .columns = 24,
            .history_rows = 2,
        });
        defer deinit(instance);
        const state = stateMut(instance);
        @memcpy(state.reads[0..case.bytes.len], case.bytes);
        state.read_end = case.bytes.len;
        const result = try state.service(false, false, 1, .headless);
        try std.testing.expectEqual(case.ended, result.synchronized_output.ended);
        try std.testing.expectEqual(case.held, terminal(instance).synchronizedOutput());
        try std.testing.expectEqualStrings(case.tail, state.reads[state.read_start..state.read_end]);
        try std.testing.expectEqual(case.tail.len != 0, bufferedOutputPending(instance));
        if (case.tail.len != 0) {
            const next = try state.service(false, false, 2, .headless);
            try std.testing.expect(!next.synchronized_output.ended);
            try std.testing.expect(terminal(instance).synchronizedOutput());
            try std.testing.expectEqual(@as(u21, 'A'), terminal(instance).semanticView(0).cellAt(0, 0));
            try std.testing.expectEqual(@as(u21, 'B'), terminal(instance).semanticView(0).cellAt(0, 1));
        }
        try std.testing.expectEqual(@as(usize, 0), state.read_end);
        try std.testing.expect(!bufferedOutputPending(instance));
        const idle = try state.service(false, false, 3, .headless);
        try std.testing.expect(!idle.synchronized_output.ended);
    }
}

test "presented Instance owns direct VT to Render progression" {
    const fonts = @import("test_fonts");
    const font_config = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 18 },
    };
    const expected_font = try text.FontSet.init(std.testing.allocator, font_config);
    defer expected_font.deinit();
    const expected_metrics = expected_font.metrics();

    const instance = try initPresented(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "printf 'DIRECT_RENDER'; sleep 30",
            .rows = 2,
            .columns = 16,
            .history_rows = 8,
        },
        .{
            .fonts = .{ .regular = .{ .path = font_config } },
            .box_drawing = .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .shape_cache = .{
                .entry_capacity = 32,
                .scalar_capacity = 128,
                .glyph_capacity = 128,
                .max_sequence_scalars = 16,
            },
            .atlas = .{
                .width = 256,
                .height = 256,
                .entry_capacity = 128,
            },
            .shaped_capacity = 128,
            .raster_bytes = 256 * 256,
            .command_capacity = 256,
        },
    );
    defer deinit(instance);

    try std.testing.expect(presented(instance));
    const pixels = terminal(instance).cellPixelSize() orelse return error.MissingCellPixels;
    try std.testing.expectEqual(expected_metrics.advance_width, pixels.width);
    try std.testing.expectEqual(expected_metrics.line_height, pixels.height);

    const before = try renderUsage(instance);
    try serviceUntilContains(instance, "DIRECT_RENDER");

    var uploads: [terminal_render.maximum_external_images + 1]terminal_render.FrameResourceUpload = undefined;
    var removals: [terminal_render.maximum_external_images + 1]terminal_render.ResourceRef = undefined;
    var commands: [512]terminal_render.Command = undefined;
    var frame_pixels: [256 * 256]u8 = undefined;
    const frame = try renderFrame(instance, &.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &frame_pixels,
    });
    const after = try renderUsage(instance);
    try std.testing.expect(after.revision > before.revision);
    try std.testing.expect(frame.commands.len != 0);
    try std.testing.expectEqual(after.revision, frame.revision);
}

test "presented publication owns canonical VT image bytes and consumes residency feedback" {
    const fonts = @import("test_fonts");
    const font_config = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 18 },
    };
    const instance = try initPresented(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "sleep 30",
            .rows = 3,
            .columns = 8,
            .history_rows = 8,
        },
        .{
            .fonts = .{ .regular = .{ .path = font_config } },
            .box_drawing = .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .shape_cache = .{
                .entry_capacity = 32,
                .scalar_capacity = 128,
                .glyph_capacity = 128,
                .max_sequence_scalars = 16,
            },
            .atlas = .{
                .width = 256,
                .height = 256,
                .entry_capacity = 128,
            },
            .shaped_capacity = 128,
            .raster_bytes = 256 * 256,
            .command_capacity = 256,
        },
    );
    defer deinit(instance);

    const state = stateMut(instance);
    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=20,C=1,q=2;/wAA/w==\x1b\\",
    )).stateChanged());

    try publishRender(instance);
    const exchange = try renderExchange(instance);
    var lease = acquirePublishedFrame(exchange) orelse return error.MissingPublication;

    var rgba_upload: ?terminal_render.FrameResourceUpload = null;
    for (lease.value.uploads) |upload| {
        if (upload.format == .rgba8) {
            rgba_upload = upload;
            break;
        }
    }
    const image_upload = rgba_upload orelse return error.MissingImageUpload;
    try std.testing.expectEqualDeep(
        terminal_render.Size{ .width = 1, .height = 1 },
        image_upload.size,
    );
    try std.testing.expectEqual(@as(usize, 4), image_upload.pixel_count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 0, 255 },
        lease.value.pixels[image_upload.pixel_offset..][0..image_upload.pixel_count],
    );

    var accepted: [publication.maximum_residencies]terminal_render.Residency = undefined;
    var accepted_count: usize = 0;
    for (lease.value.uploads) |upload| {
        accepted[accepted_count] = .{
            .resource = upload.resource,
            .format = upload.format,
            .size = upload.size,
        };
        accepted_count += 1;
    }
    try lease.release(accepted[0..accepted_count]);

    // No terminal mutation occurred. The next terminal-side publication consumes
    // only the residency feedback and therefore does not resend the image.
    try publishRender(instance);
    var settled = acquirePublishedFrame(exchange) orelse return error.MissingPublication;
    for (settled.value.uploads) |upload|
        try std.testing.expect(upload.format != .rgba8);
    try settled.release(accepted[0..accepted_count]);
}

test "presentation reconfigure invalidates late old-generation residency" {
    const fonts = @import("test_fonts");
    const first_font = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 18 },
    };
    const second_font = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 24 },
    };
    const base_config = PresentationConfig{
        .fonts = .{ .regular = .{ .path = first_font } },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 32,
            .scalar_capacity = 128,
            .glyph_capacity = 128,
            .max_sequence_scalars = 16,
        },
        .atlas = .{
            .width = 256,
            .height = 256,
            .entry_capacity = 128,
        },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
    };
    const instance = try initPresented(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "printf 'A'; sleep 30",
            .rows = 2,
            .columns = 8,
            .history_rows = 8,
        },
        base_config,
    );
    defer deinit(instance);

    try serviceUntilContains(instance, "A");
    try publishRender(instance);
    const exchange = try renderExchange(instance);
    var old = acquirePublishedFrame(exchange) orelse return error.MissingPublication;
    try std.testing.expectEqual(@as(u64, 1), old.value.presentation_generation);

    var old_residency: [publication.maximum_residencies]terminal_render.Residency = undefined;
    var old_count: usize = 0;
    var old_had_alpha = false;
    for (old.value.uploads) |upload| {
        if (upload.format == .alpha8) old_had_alpha = true;
        old_residency[old_count] = .{
            .resource = upload.resource,
            .format = upload.format,
            .size = upload.size,
        };
        old_count += 1;
    }
    try std.testing.expect(old_had_alpha);

    var next_config = base_config;
    next_config.fonts = .{ .regular = .{ .path = second_font } };
    const next_cell = try reconfigurePresentation(instance, next_config);
    const canonical_cell = terminal(instance).cellPixelSize() orelse
        return error.MissingCellPixels;
    try std.testing.expectEqual(next_cell.width, canonical_cell.width);
    try std.testing.expectEqual(next_cell.height, canonical_cell.height);

    // The old backend finishes after the presentation swap. Its generation-1
    // residency must not satisfy generation-2 Render resources.
    try old.release(old_residency[0..old_count]);
    try publishRender(instance);

    var current = acquirePublishedFrame(exchange) orelse return error.MissingPublication;
    try std.testing.expectEqual(@as(u64, 2), current.value.presentation_generation);
    try std.testing.expectEqualDeep(next_cell, current.value.cell_size);
    var current_had_alpha = false;
    var current_residency: [publication.maximum_residencies]terminal_render.Residency = undefined;
    var current_count: usize = 0;
    for (current.value.uploads) |upload| {
        if (upload.format == .alpha8) current_had_alpha = true;
        current_residency[current_count] = .{
            .resource = upload.resource,
            .format = upload.format,
            .size = upload.size,
        };
        current_count += 1;
    }
    try std.testing.expect(current_had_alpha);
    try current.release(current_residency[0..current_count]);

    // Exact current-generation acceptance now suppresses the atlas upload.
    try publishRender(instance);
    var settled = acquirePublishedFrame(exchange) orelse return error.MissingPublication;
    for (settled.value.uploads) |upload|
        try std.testing.expect(upload.format != .alpha8);
    try settled.release(current_residency[0..current_count]);
}

test "presentation surface reconfigure derives canonical grid from new font metrics" {
    const fonts = @import("test_fonts");
    const first_font = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 18 },
    };
    const second_font = text.Config{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 24 },
    };
    const base_config = PresentationConfig{
        .fonts = .{ .regular = .{ .path = first_font } },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 32,
            .scalar_capacity = 128,
            .glyph_capacity = 128,
            .max_sequence_scalars = 16,
        },
        .atlas = .{
            .width = 256,
            .height = 256,
            .entry_capacity = 128,
        },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
    };
    const value = try initPresented(
        std.testing.allocator,
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "sleep 30",
            .rows = 2,
            .columns = 8,
            .history_rows = 8,
        },
        base_config,
    );
    defer deinit(value);

    var next_config = base_config;
    next_config.fonts = .{ .regular = .{ .path = second_font } };
    const surface = terminal_render.Size{ .width = 640, .height = 360 };
    const geometry = try reconfigurePresentationSurface(
        value,
        next_config,
        surface,
    );
    try std.testing.expectEqual(
        surface.width / geometry.cell_size.width,
        geometry.columns,
    );
    try std.testing.expectEqual(
        surface.height / geometry.cell_size.height,
        geometry.rows,
    );

    const observation = terminal(value);
    const view = observation.semanticView(0);
    const pixels = observation.cellPixelSize() orelse
        return error.MissingCellPixels;
    try std.testing.expectEqual(geometry.rows, view.rows);
    try std.testing.expectEqual(geometry.columns, view.cols);
    try std.testing.expectEqual(@as(u32, geometry.cell_size.width), pixels.width);
    try std.testing.expectEqual(@as(u32, geometry.cell_size.height), pixels.height);
}
