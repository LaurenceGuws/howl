//! Private compile-time selection of one canonical PTY/VT composition.
const std = @import("std");
const pty = @import("howl_pty");
const vt = @import("howl_vt");

/// Selects presentation at compilation; both roots retain the same canonical service lane.
pub fn Runtime(comptime Presentation: ?type) type {
    return struct {
        const howl_render = Presentation.?.render;
        const publication = Presentation.?.publication;
        const terminal_render = howl_render.terminal;

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
        const bracketed_paste: vt.Terminal.PasteFraming = .{ .bracketed = true };
        /// Largest chunk that always fits the empty outbox with both paste delimiters.
        /// Larger chunks fail permanently; WriteQueueFull instead means retry after progress.
        pub const maximum_paste_chunk_bytes: usize = write_queue_bytes - bracketed_paste.prefix().len - bracketed_paste.suffix().len;
        /// Nonreused identity for one streaming paste in this composition.
        pub const PasteToken = enum(u64) { _ };
        /// Reports an occupied input lane, pending older replies, or exhausted identities.
        pub const BeginPasteError = error{ PasteActive, WriteQueueFull, PasteIdentityExhausted };
        /// Reports stale operation identity or whole-chunk admission failure.
        pub const PasteError = error{ StalePaste, PasteChunkTooLarge, WriteQueueFull };

        // Process-wide per composition, so a retired token cannot target a later
        // Instance even when its allocator reuses the same address.
        var paste_identity: std.atomic.Value(u64) = .init(0);

        fn nextPasteIdentity(counter: *std.atomic.Value(u64)) error{PasteIdentityExhausted}!PasteToken {
            var before = counter.load(.monotonic);
            while (true) {
                if (before == std.math.maxInt(u64)) return error.PasteIdentityExhausted;
                before = counter.cmpxchgWeak(before, before + 1, .monotonic, .monotonic) orelse
                    return @fromBackingInt(before + 1);
            }
        }

        const Paste = struct {
            token: ?PasteToken = null,
            framing: vt.Terminal.PasteFraming = .{ .bracketed = false },
            started: bool = false,
        };

        const read_buffer_bytes: usize = 16 * 1024;
        const read_calls_per_turn: u8 = 8;
        const write_bytes_per_turn: usize = 64 * 1024;
        const write_calls_per_turn: usize = 4;

        /// Opaque handle to one canonical PTY + VT lifetime owner.
        // zig-audit: acknowledge opaque_type
        // reason: This handle intentionally hides its backing owner layout so callers can use only the bounded public lifetime/API.
        pub const Instance = opaque {
            // Capture the selection: Zig otherwise shares an empty opaque type
            // across generic instantiations despite their different State layouts.
            const composition = Presentation;
        };
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
            /// Choose process sharing deliberately; private opens a separate native family.
            text: union(enum) { private: FontFamilyConfig, shared: *PresentationStore },
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

        /// Owns one fixed native font family, shared shape cache and reusable scratch.
        /// Matching terminals borrow this owner; atlases, commands and frames remain local.
        /// Mutable native faces are serialized internally. The supplied Io outlives all
        /// borrowers, including those surviving release of the caller's reference.
        // zig-audit: acknowledge opaque_type
        // reason: Only this module can retain, serialize, and release the native font and Store owner.
        pub const PresentationStore = opaque {};
        /// Reports font, bounded Store, or ownership admission failure.
        pub const PresentationStoreInitError = text.InitError || terminal_render.StoreInitError || error{PresentationStoreLimit};

        /// Creates one caller reference for a compatible font recipe and pixel size.
        /// Share the returned pointer through PresentationConfig.text.shared. Construction
        /// copies font sources; the input recipe does not need to survive this call.
        pub fn initPresentationStore(
            allocator: std.mem.Allocator,
            io: std.Io,
            fonts: FontFamilyConfig,
            config: terminal_render.StoreConfig,
        ) PresentationStoreInitError!*PresentationStore {
            const owner = try allocator.create(TextStore);
            errdefer allocator.destroy(owner);
            var owned_fonts = try OwnedFonts.init(allocator, fonts);
            errdefer owned_fonts.deinit();
            const store = try terminal_render.initStore(allocator, owned_fonts.faces(), config);
            owner.* = .{ .allocator = allocator, .io = io, .fonts = owned_fonts, .store = store };
            // zig-audit: acknowledge ptr_cast
            // reason: The opaque handle preserves the address of this exact allocator-owned TextStore.
            return @ptrCast(owner);
        }

        /// Releases the caller reference. Existing presented Instances retain the owner
        /// until their renderers retire; the caller must not reuse its released pointer.
        pub fn releasePresentationStore(store: *PresentationStore) void {
            textStore(store).release();
        }

        /// Copies the immutable regular-font lattice without claiming mutable faces.
        /// The caller keeps its Store reference alive throughout this synchronous read.
        pub fn presentationStoreCellSize(store: *PresentationStore) terminal_render.Size {
            const metrics = terminal_render.storeMetrics(textStore(store).store);
            return .{ .width = metrics.advance_width, .height = metrics.line_height };
        }

        /// Includes the caller's reference and all presented borrowers. Caller ownership
        /// must remain live; a count of one permits an embedder to retire an idle owner.
        pub fn presentationStoreReferences(store: *PresentationStore) u32 {
            return textStore(store).references.load(.acquire);
        }

        /// Reads shared cache usage under the native-face claim.
        pub fn presentationStoreUsage(store: *PresentationStore) terminal_render.StoreUsage {
            const owner = textStore(store);
            owner.mutex.lockUncancelable(owner.io);
            defer owner.mutex.unlock(owner.io);
            return terminal_render.storeUsage(owner.store);
        }

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
            /// Literal program arguments excluding argv[0]. On Linux, executes
            /// shell as the program path without -i/-c; mutually exclusive with
            /// command. Unsupported on other PTY platforms until implemented.
            arguments: ?[]const []const u8 = null,
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
        pub const PresentedInitError = InitError || PresentationStoreInitError || terminal_render.InitError || terminal_render.Error;
        /// Reports construction failure or a shared font claim that would wait.
        pub const TryPresentedInitError = PresentedInitError || error{PresentationBusy};
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
        pub const RenderError = terminal_render.Error || error{ PresentationUnavailable, PresentationBusy };
        /// Reports publication preparation or bounded exchange failure.
        pub const PublishError = RenderError || std.mem.Allocator.Error || error{PublicationBusy};
        /// Reports transactional font/renderer replacement or canonical geometry failure.
        pub const ReconfigurePresentationError =
            PresentationStoreInitError || terminal_render.InitError || terminal_render.Error ||
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
        /// Text ownership is explicit in PresentationConfig; Instance retains a shared
        /// owner or creates the requested private owner, alongside its VT and Renderer.
        /// Initial PTY/VT pixel geometry comes from the regular font metrics.
        pub fn initPresented(
            allocator: std.mem.Allocator,
            inherited_environment: std.process.Environ,
            launch: Launch,
            presentation: PresentationConfig,
        ) PresentedInitError!*Instance {
            return initPresentedMode(false, allocator, inherited_environment, launch, presentation);
        }

        /// Tries shared font access before State allocation or child launch.
        /// PresentationBusy leaves no child or attempted Instance reference alive.
        pub fn tryInitPresented(
            allocator: std.mem.Allocator,
            inherited_environment: std.process.Environ,
            launch: Launch,
            presentation: PresentationConfig,
        ) TryPresentedInitError!*Instance {
            return initPresentedMode(true, allocator, inherited_environment, launch, presentation);
        }

        fn initPresentedMode(
            comptime try_claim: bool,
            allocator: std.mem.Allocator,
            inherited_environment: std.process.Environ,
            launch: Launch,
            presentation: PresentationConfig,
        ) (if (try_claim) TryPresentedInitError else PresentedInitError)!*Instance {
            const store = try TextStore.acquire(allocator, presentation);
            errdefer store.release();
            if (comptime try_claim) {
                if (!store.mutex.tryLock()) return error.PresentationBusy;
            }
            // Registered after the release guard: every failure unlocks first.
            defer if (try_claim) store.mutex.unlock(store.io);
            const metrics = terminal_render.storeMetrics(store.store);
            var canonical_launch = launch;
            canonical_launch.cell_pixel_width = metrics.advance_width;
            canonical_launch.cell_pixel_height = metrics.line_height;

            const state = try allocator.create(State);
            errdefer allocator.destroy(state);
            try state.initInto(allocator, inherited_environment, canonical_launch);
            errdefer state.deinit();

            state.presentation = try PresentationState.initWithStoreMode(
                try_claim,
                allocator,
                store,
                presentation,
                state.terminal.observation(),
            );

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

        /// Checks native backend/lease lifetimes before any child or owner mutation.
        /// Caller must serialize new endpoint creation and quiesce raw Zig borrowers.
        pub fn tryDeinit(instance: *Instance) error{PublicationBorrowed}!void {
            if (comptime Presentation != null) {
                if (stateConst(instance).presentation) |presented_state|
                    if (!publication.canDeinit(presented_state.exchange)) return error.PublicationBorrowed;
            }
            deinit(instance);
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

        /// True when retained child output can progress without another PTY write
        /// or paste chunk. Use this for immediate service scheduling; pending bytes
        /// alone can be blocked by ordered reply admission.
        pub fn bufferedOutputRunnable(instance: *const Instance) bool {
            const state = stateConst(instance);
            return state.outputRunnable();
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
            presentation.store.mutex.lockUncancelable(presentation.store.io);
            defer presentation.store.mutex.unlock(presentation.store.io);
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

        /// Registers one native backend on the terminal-owner thread.
        /// New backend residency starts empty; old unread publications/feedback are discarded.
        /// This affects presentation only. The caller explicitly publishes a new cut.
        pub fn borrowRenderExchange(instance: *Instance) error{ PresentationUnavailable, PublicationBorrowed }!*RenderExchange {
            const presentation = stateMut(instance).presentation orelse return error.PresentationUnavailable;
            if (!publication.retainBackend(presentation.exchange)) return error.PublicationBorrowed;
            // zig-audit: acknowledge discard
            // reason: A replacement backend has no accepted resources; consume old feedback without adopting it.
            _ = publication.takeLatestResidency(presentation.exchange, presentation.presentation_generation, &presentation.backend_residency);
            presentation.backend_residency_count = 0;
            publication.discardReady(presentation.exchange);
            return presentation.exchange;
        }

        /// Releases a registered backend after its last lease, as its final exchange access.
        pub fn releaseRenderExchange(exchange: *RenderExchange) void {
            publication.releaseBackend(exchange);
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

        /// Copies one decoded FIFO-head OSC 52 set without consuming it.
        pub fn copyClipboard(
            instance: *Instance,
            id: u64,
            allocator: std.mem.Allocator,
            max_bytes: usize,
        ) error{ OutOfMemory, StaleClipboardRequest, ClipboardLimit }!?[]u8 {
            return stateMut(instance).terminal.copyClipboard(id, allocator, max_bytes);
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
        /// An active streaming paste returns WriteQueueFull before encoding;
        /// its owner must finish/cancel before later input can be retried.
        pub fn input(instance: *Instance, event: Input) InputError!void {
            return stateMut(instance).input(event);
        }

        /// Opens one ordered paste lane and snapshots canonical bracket mode.
        /// Begin only after payload acquisition/validation: callers supply progress
        /// or cancellation, and Instance retains no payload borrow or allocation.
        /// Older queued writes/replies precede the paste. Later inputs/replies wait.
        pub fn beginPaste(instance: *Instance) BeginPasteError!PasteToken {
            return stateMut(instance).beginPaste();
        }

        /// Atomically copies a complete chunk, or retains none on failure.
        /// final=true appends the closing delimiter and retires the token. An empty
        /// final chunk completes an empty paste using the ordinary VT framing.
        /// Chunks are raw payload, never reinterpreted as termios signal events.
        pub fn pasteChunk(instance: *Instance, token: PasteToken, bytes: []const u8, final: bool) PasteError!void {
            return stateMut(instance).pasteChunk(token, bytes, final);
        }

        /// Retires the token and closes any admitted prefix without allocation.
        /// Already admitted bytes cannot be recalled; delivery still depends on
        /// PTY progress. Destruction instead closes the whole process-terminal.
        pub fn cancelPaste(instance: *Instance, token: PasteToken) error{StalePaste}!void {
            return stateMut(instance).cancelPaste(token);
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
            if (comptime Presentation != null) {
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
                self.appendAssumeCapacity(bytes);
            }

            fn appendAssumeCapacity(self: *WriteQueue, bytes: []const u8) void {
                std.debug.assert(bytes.len <= self.remaining());
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

        const TextStore = struct {
            allocator: std.mem.Allocator,
            io: std.Io,
            fonts: OwnedFonts,
            store: *terminal_render.Store,
            mutex: std.Io.Mutex = .init,
            references: std.atomic.Value(u32) = .init(1),

            fn acquire(allocator: std.mem.Allocator, config: PresentationConfig) PresentationStoreInitError!*TextStore {
                switch (config.text) {
                    .private => |fonts| return textStore(try initPresentationStore(allocator, .failing, fonts, .{
                        .shape_cache = config.shape_cache,
                        .shaped_capacity = config.shaped_capacity,
                        .raster_bytes = config.raster_bytes,
                    })),
                    .shared => |shared| {
                        const owner = textStore(shared);
                        var before = owner.references.load(.monotonic);
                        while (true) {
                            if (before >= 1024) return error.PresentationStoreLimit;
                            before = owner.references.cmpxchgWeak(before, before + 1, .monotonic, .monotonic) orelse return owner;
                        }
                    },
                }
            }

            fn release(self: *TextStore) void {
                const before = self.references.fetchSub(1, .acq_rel);
                std.debug.assert(before != 0);
                if (before != 1) return;
                terminal_render.deinitStore(self.store);
                self.fonts.deinit();
                self.allocator.destroy(self);
            }
        };

        fn textStore(store: *PresentationStore) *TextStore {
            // zig-audit: acknowledge align_cast
            // reason: Every public handle originates from this module's aligned TextStore allocation.
            const aligned: *align(@alignOf(TextStore)) PresentationStore = @alignCast(store);
            // zig-audit: acknowledge ptr_cast
            // reason: The opaque handle has the same address and concrete pointee layout as its TextStore owner.
            return @ptrCast(aligned);
        }

        const PresentationState = struct {
            renderer: *terminal_render.Renderer,
            store: *TextStore,
            exchange: *publication.Exchange,
            image_bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined,
            image_binding_count: usize = 0,
            terminal_revision: ?u64 = null,
            content_revision: ?u64 = null,
            terminal_history_offset: u32 = 0,
            backend_residency: [publication.maximum_residencies]terminal_render.Residency = undefined,
            backend_residency_count: usize = 0,
            atlas_pixel_capacity: usize,
            command_capacity: usize,
            command_limit: usize,
            presentation_generation: u64 = 1,
            row_reuse_capacity: u16,
            row_generations: [render.limits.maximum_rows]u64 = @splat(0),
            row_repairs: [render.limits.maximum_rows]bool = undefined,
            row_rows: u16 = 0,
            row_columns: u16 = 0,
            row_alternate_screen: bool = false,

            fn initWithStore(
                allocator: std.mem.Allocator,
                store: *TextStore,
                config: PresentationConfig,
                observation: *const Terminal.Observation,
            ) (terminal_render.InitError || terminal_render.Error)!*PresentationState {
                return initWithStoreMode(false, allocator, store, config, observation);
            }

            fn initWithStoreMode(
                comptime claimed: bool,
                allocator: std.mem.Allocator,
                store: *TextStore,
                config: PresentationConfig,
                observation: *const Terminal.Observation,
            ) (terminal_render.InitError || terminal_render.Error)!*PresentationState {
                const metrics = terminal_render.storeMetrics(store.store);
                const renderer = try terminal_render.initWithStore(
                    allocator,
                    store.store,
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
                const command_limit = if (config.command_limit == 0)
                    config.command_capacity
                else
                    config.command_limit;
                state.* = .{
                    .renderer = renderer,
                    .store = store,
                    .exchange = exchange,
                    .atlas_pixel_capacity = atlas_pixel_capacity,
                    .command_capacity = config.command_capacity,
                    .command_limit = command_limit,
                    .row_reuse_capacity = config.incremental_row_capacity,
                };
                // Ordinary construction keeps its existing late waiting claim.
                // The try factory already holds this claim from before child launch.
                if (!claimed) store.mutex.lockUncancelable(store.io);
                defer if (!claimed) store.mutex.unlock(store.io);
                try state.refreshClaimed(observation, 0);
                return state;
            }

            fn deinit(self: *PresentationState, allocator: std.mem.Allocator) void {
                publication.deinit(self.exchange);
                terminal_render.deinit(self.renderer);
                self.store.release();
                self.* = undefined;
                allocator.destroy(self);
            }

            fn cellSize(self: *const PresentationState) terminal_render.Size {
                const metrics = terminal_render.storeMetrics(self.store.store);
                return .{ .width = metrics.advance_width, .height = metrics.line_height };
            }

            fn refresh(
                self: *PresentationState,
                observation: *const Terminal.Observation,
                history_offset: u32,
            ) RenderError!void {
                const revision = observation.semanticSequence();
                const view = observation.semanticView(history_offset);
                if (self.terminal_revision != null and
                    self.terminal_revision.? == revision and
                    self.terminal_history_offset == view.history_offset)
                    return;
                const content_revision = observation.contentSequence();
                reuse: {
                    if (self.content_revision == content_revision and
                        self.terminal_history_offset == view.history_offset)
                    {
                        terminal_render.updateObservationCursor(self.renderer, observation, view.history_offset) catch |failure| switch (failure) {
                            error.InvalidView => break :reuse,
                            else => return failure,
                        };
                        self.terminal_revision = revision;
                        return;
                    }
                }
                if (!self.store.mutex.tryLock()) return error.PresentationBusy;
                defer self.store.mutex.unlock(self.store.io);
                try self.refreshClaimed(observation, view.history_offset);
            }

            fn refreshClaimed(
                self: *PresentationState,
                observation: *const Terminal.Observation,
                history_offset: u32,
            ) terminal_render.Error!void {
                const revision = observation.semanticSequence();
                const content_revision = observation.contentSequence();
                const view = observation.semanticView(history_offset);
                var candidate: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
                const bindings = try terminal_render.planObservationImageBindings(
                    self.image_bindings[0..self.image_binding_count],
                    terminal_render.usage(self.renderer),
                    observation,
                    view.history_offset,
                    &candidate,
                );
                var changes: ?terminal_render.RowChanges = null;
                var captured_rows = false;
                if (view.rows <= self.row_reuse_capacity and view.rows <= self.row_generations.len) {
                    const same_base = self.content_revision != null and
                        self.row_rows == view.rows and self.row_columns == view.cols and
                        self.terminal_history_offset == view.history_offset and
                        self.row_alternate_screen == view.is_alternate_screen;
                    var known = true;
                    var repaired_rows: u16 = 0;
                    for (0..view.rows) |row| {
                        const generation = view.rowGeneration(@intCast(row)) orelse {
                            known = false;
                            break;
                        };
                        self.row_repairs[row] = !same_base or self.row_generations[row] != generation;
                        repaired_rows += @intFromBool(self.row_repairs[row]);
                        self.row_generations[row] = generation;
                    }
                    captured_rows = known;
                    // Broad repairs use the direct full-projection lane. Keep the
                    // successful observer baseline without priming an unused cache.
                    if (known and (!same_base or repaired_rows <= terminal_render.rowReuseLimit(view.rows))) changes = .{
                        .base_revision = if (same_base) self.content_revision else null,
                        .rows = self.row_repairs[0..view.rows],
                    };
                }
                // Staging row scalars never leaves a usable baseline after failed work.
                self.row_rows = 0;
                try terminal_render.updateObservationRows(
                    self.renderer,
                    observation,
                    view.history_offset,
                    changes,
                    bindings,
                );
                if (captured_rows) {
                    self.row_rows = view.rows;
                    self.row_columns = view.cols;
                    self.row_alternate_screen = view.is_alternate_screen;
                }
                @memcpy(self.image_bindings[0..bindings.len], bindings);
                self.image_binding_count = bindings.len;
                self.terminal_revision = revision;
                self.content_revision = content_revision;
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

                const frame = while (true) {
                    const current = terminal_render.frame(
                        self.renderer,
                        prospective[0..prospective_count],
                        .{
                            .retained_content = writer.retainedContent(self.presentation_generation),
                            .uploads = uploads[missing.len..],
                            .removals = writer.removalStorage(),
                            .commands = writer.commandStorage(),
                            .pixels = pixels[external_pixel_count..],
                        },
                    ) catch |failure| switch (failure) {
                        error.CommandLimit => {
                            const current_capacity = writer.commandStorage().len;
                            if (current_capacity >= self.command_limit)
                                return error.CommandLimit;
                            const doubled = std.math.mul(
                                usize,
                                current_capacity,
                                2,
                            ) catch self.command_limit;
                            const next = @min(
                                self.command_limit,
                                @max(current_capacity + 1, doubled),
                            );
                            try writer.ensureCommandCapacity(next);
                            continue;
                        },
                        else => |err| return err,
                    };
                    break current;
                };
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
                    frame.content_revision,
                    frame.content_command_count,
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
            presentation: if (Presentation != null) ?*PresentationState else void = if (Presentation != null) null else {},
            writes: WriteQueue = .{},
            paste: Paste = .{},
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
                var transport = if (launch.arguments) |arguments| blk: {
                    if (comptime @import("builtin").os.tag != .linux)
                        return error.UnsupportedPlatform;
                    if (launch.command != null) return error.InvalidArgument;
                    break :blk try pty.Owned.initProgram(
                        allocator,
                        inherited_environment,
                        launch.shell,
                        arguments,
                        launch.cwd,
                        .{ .term = launch.term, .colorterm = launch.colorterm },
                    );
                } else try pty.Owned.init(
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
                self.paste = .{};
                self.read_start = 0;
                self.read_end = 0;
                self.child_exit = null;
                self.stream_closed = false;
                if (comptime Presentation != null) self.presentation = null;
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
                if (comptime Presentation != null) {
                    if (self.presentation) |presentation| presentation.deinit(self.allocator);
                }
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

                const store = try TextStore.acquire(self.allocator, config);
                var store_live = true;
                defer if (store_live) store.release();
                const metrics = terminal_render.storeMetrics(store.store);
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
                const renderer = try terminal_render.initWithStore(
                    self.allocator,
                    store.store,
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
                const old_content_revision = observation.contentSequence();
                var candidate_bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
                const bindings = prepare: {
                    store.mutex.lockUncancelable(store.io);
                    defer store.mutex.unlock(store.io);
                    const planned = try terminal_render.planObservationImageBindings(
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
                        planned,
                    );
                    break :prepare planned;
                };
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
                presentation.store.release();
                presentation.renderer = renderer;
                renderer_live = false;
                presentation.store = store;
                store_live = false;
                @memcpy(presentation.image_bindings[0..bindings.len], bindings);
                presentation.image_binding_count = bindings.len;
                presentation.terminal_revision = old_revision;
                presentation.content_revision = old_content_revision;
                presentation.terminal_history_offset = 0;
                presentation.backend_residency_count = 0;
                presentation.atlas_pixel_capacity = atlas_pixel_capacity;
                presentation.command_limit = if (config.command_limit == 0)
                    config.command_capacity
                else
                    config.command_limit;
                presentation.presentation_generation = next_generation;
                return .{
                    .cell_size = cell_size,
                    .rows = rows,
                    .columns = columns,
                };
            }

            fn beginPaste(self: *State) BeginPasteError!PasteToken {
                if (self.paste.token != null) return error.PasteActive;
                try self.collectReplies();
                const token = try nextPasteIdentity(&paste_identity);
                self.paste = .{
                    .token = token,
                    .framing = .{ .bracketed = self.terminal.interactionState().bracketed_paste },
                };
                return token;
            }

            fn pasteChunk(self: *State, token: PasteToken, bytes: []const u8, final: bool) PasteError!void {
                if (self.paste.token != token) return error.StalePaste;
                if (bytes.len > maximum_paste_chunk_bytes) return error.PasteChunkTooLarge;
                if (bytes.len == 0 and !final) return;
                const prefix = if (self.paste.started) "" else self.paste.framing.prefix();
                const suffix = self.paste.framing.suffix();
                // Keep closing capacity reserved even on a nonfinal chunk.
                const required = prefix.len + bytes.len + suffix.len;
                if (required > self.writes.remaining()) return error.WriteQueueFull;
                self.writes.appendAssumeCapacity(prefix);
                self.writes.appendAssumeCapacity(bytes);
                if (final) {
                    self.writes.appendAssumeCapacity(suffix);
                    self.paste = .{};
                } else self.paste.started = true;
            }

            fn cancelPaste(self: *State, token: PasteToken) error{StalePaste}!void {
                if (self.paste.token != token) return error.StalePaste;
                if (self.paste.started) self.writes.appendAssumeCapacity(self.paste.framing.suffix());
                self.paste = .{};
            }

            fn collectReplies(self: *State) error{WriteQueueFull}!void {
                // The first reply-producing VT boundary retains its reply and
                // unread tail until paste ends. This uses the existing bounded
                // queues rather than mixing replies into payload or buffering
                // unbounded output behind a stalled input operation.
                if (self.paste.token != null and self.terminal.replyBytes().len != 0)
                    return error.WriteQueueFull;
                return transferReplies(&self.terminal, &self.writes);
            }

            fn input(self: *State, event: Input) InputError!void {
                if (self.paste.token != null) return error.WriteQueueFull;
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
                    try self.collectReplies();
                    return;
                }
                try self.collectReplies();
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

            fn outputRunnable(self: *const State) bool {
                const replies = self.terminal.replyBytes().len;
                return self.read_start < self.read_end and
                    (replies == 0 or (self.paste.token == null and replies <= self.writes.remaining()));
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
                self.collectReplies() catch |failure| switch (failure) {
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
                    self.collectReplies() catch |failure| switch (failure) {
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
                    self.collectReplies() catch |failure| switch (failure) {
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

        fn transferReplies(machine: *vt.Terminal, queue: *WriteQueue) error{WriteQueueFull}!void {
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

        // These proofs exercise only VT/input storage; no fake transport is used.
        fn pasteTestState() !State {
            var state: State = undefined;
            state.allocator = std.testing.failing_allocator;
            state.terminal = try Terminal.init(std.testing.allocator, 2, 16);
            state.writes = .{};
            state.paste = .{};
            state.read_start = 0;
            state.read_end = 0;
            return state;
        }

        test "paste chunks match one atomic VT encoding across every split and mode changes" {
            const payload = "\x03hi\xf0\x9f\x98\x80\n";
            for ([_]bool{ false, true }) |bracketed| {
                for (0..payload.len + 1) |split| {
                    var state = try pasteTestState();
                    defer state.terminal.deinit();
                    if (bracketed) try std.testing.expect((try state.terminal.feed("\x1b[?2004h")).stateChanged());
                    var scratch: Terminal.InputScratch = undefined;
                    var expected = try state.terminal.encodeInput(std.testing.allocator, &scratch, .{ .paste = payload });
                    defer expected.deinit();
                    const token = try state.beginPaste();
                    // The mode changes after acquisition, and a one-byte control
                    // chunk must remain payload rather than invoke PTY signals.
                    try std.testing.expect((try state.terminal.feed(if (bracketed) "\x1b[?2004l" else "\x1b[?2004h")).stateChanged());
                    try state.pasteChunk(token, payload[0..split], false);
                    try std.testing.expectError(error.WriteQueueFull, state.input(.{ .bytes = "later" }));
                    try state.pasteChunk(token, payload[split..], true);
                    try std.testing.expectEqualStrings(expected.bytes, state.writes.bytes[0..state.writes.count]);
                    try std.testing.expectError(error.StalePaste, state.pasteChunk(token, "", true));
                    try state.input(.{ .bytes = "ok" });
                    try std.testing.expectEqualStrings("ok", state.writes.bytes[state.writes.count - 2 .. state.writes.count]);
                }
            }
        }

        test "paste cancellation retains its closing credit at the exact outbox bound" {
            var state = try pasteTestState();
            defer state.terminal.deinit();
            try std.testing.expect((try state.terminal.feed("\x1b[?2004h")).stateChanged());
            try state.writes.append("old");
            const token = try state.beginPaste();
            try std.testing.expectError(error.PasteActive, state.beginPaste());
            var payload: [maximum_paste_chunk_bytes - 3]u8 = undefined;
            @memset(&payload, 'x');
            try state.pasteChunk(token, &payload, false);
            try std.testing.expectEqual(@as(usize, 6), state.writes.remaining());
            const count = state.writes.count;
            try std.testing.expectError(error.WriteQueueFull, state.pasteChunk(token, "y", false));
            try std.testing.expectEqual(count, state.writes.count);
            try state.cancelPaste(token);
            try std.testing.expectEqual(write_queue_bytes, state.writes.count);
            try std.testing.expectEqualStrings("old\x1b[200~", state.writes.bytes[0..9]);
            try std.testing.expectEqualStrings("\x1b[201~", state.writes.bytes[state.writes.count - 6 .. state.writes.count]);
            try std.testing.expectError(error.StalePaste, state.cancelPaste(token));
        }

        test "paste identities reject another owner and never wrap at exhaustion" {
            var first = try pasteTestState();
            defer first.terminal.deinit();
            var second = try pasteTestState();
            defer second.terminal.deinit();
            const first_token = try first.beginPaste();
            const second_token = try second.beginPaste();
            try std.testing.expect(first_token != second_token);
            try std.testing.expectError(error.StalePaste, second.pasteChunk(first_token, "wrong", true));
            try std.testing.expectError(error.StalePaste, first.cancelPaste(second_token));
            try std.testing.expectEqual(@as(usize, 0), first.writes.count);
            try std.testing.expectEqual(@as(usize, 0), second.writes.count);
            try first.cancelPaste(first_token);
            const next = try first.beginPaste();
            try std.testing.expect(next != first_token);
            try std.testing.expectError(error.StalePaste, first.pasteChunk(first_token, "old", true));
            try first.cancelPaste(next);
            try second.cancelPaste(second_token);
            var counter: std.atomic.Value(u64) = .init(std.math.maxInt(u64) - 1);
            try std.testing.expectEqual(std.math.maxInt(u64), @backingInt(try nextPasteIdentity(&counter)));
            try std.testing.expectError(error.PasteIdentityExhausted, nextPasteIdentity(&counter));
            try std.testing.expectEqual(std.math.maxInt(u64), counter.load(.monotonic));
        }

        test "empty paste completion matches VT while pre-content cancellation emits nothing" {
            var state = try pasteTestState();
            defer state.terminal.deinit();
            try std.testing.expect((try state.terminal.feed("\x1b[?2004h")).stateChanged());
            const cancelled = try state.beginPaste();
            try state.pasteChunk(cancelled, "", false);
            try state.cancelPaste(cancelled);
            try std.testing.expectEqual(@as(usize, 0), state.writes.count);
            const empty = try state.beginPaste();
            try state.pasteChunk(empty, "", true);
            try std.testing.expectEqualStrings("\x1b[200~\x1b[201~", state.writes.bytes[0..state.writes.count]);
        }

        test "paste permanent size failure and transient pressure both retain the whole chunk" {
            var state = try pasteTestState();
            defer state.terminal.deinit();
            const token = try state.beginPaste();
            var oversized: [maximum_paste_chunk_bytes + 1]u8 = undefined;
            @memset(&oversized, 'x');
            try std.testing.expectError(error.PasteChunkTooLarge, state.pasteChunk(token, &oversized, true));
            try std.testing.expectEqual(@as(usize, 0), state.writes.count);
            state.writes.count = write_queue_bytes;
            try std.testing.expectError(error.WriteQueueFull, state.pasteChunk(token, "abc", true));
            try std.testing.expectEqual(write_queue_bytes, state.writes.count);
            try std.testing.expect(!state.paste.started);
            state.writes.consume(state.writes.count);
            try state.pasteChunk(token, "abc", true);
            try std.testing.expectEqualStrings("abc", state.writes.bytes[0..state.writes.count]);
        }

        test "paste fences generated replies at the bounded VT boundary without a runnable busy loop" {
            var state = try pasteTestState();
            defer state.terminal.deinit();
            try std.testing.expect((try state.terminal.feed("\x1b[?2004h\x1b[5n")).stateChanged());
            try state.writes.append("old");
            const token = try state.beginPaste();
            try std.testing.expectEqualStrings("old\x1b[0n", state.writes.bytes[0..state.writes.count]);
            try state.pasteChunk(token, "payload", false);
            const output = "A\x1b[5nB";
            @memcpy(state.reads[0..output.len], output);
            state.read_end = output.len;
            var viewport = false;
            var synchronized: Terminal.SynchronizedOutputProgress = .{};
            var fallback = false;
            try std.testing.expect(state.outputRunnable());
            try state.processBuffered(1, .headless, &viewport, &synchronized, &fallback);
            try std.testing.expectEqual(output.len - 1, state.read_start);
            try std.testing.expectEqualStrings("\x1b[0n", state.terminal.replyBytes());
            try std.testing.expect(!state.outputRunnable());
            try std.testing.expectEqualStrings("old\x1b[0n\x1b[200~payload", state.writes.bytes[0..state.writes.count]);
            const before = state.terminal.semanticSequence();
            try state.processBuffered(2, .headless, &viewport, &synchronized, &fallback);
            try std.testing.expectEqual(before, state.terminal.semanticSequence());
            try state.cancelPaste(token);
            try std.testing.expect(state.outputRunnable());
            try state.processBuffered(3, .headless, &viewport, &synchronized, &fallback);
            try std.testing.expectEqualStrings("old\x1b[0n\x1b[200~payload\x1b[201~\x1b[0n", state.writes.bytes[0..state.writes.count]);
            try std.testing.expectEqual(@as(usize, 0), state.read_end);
            const view = state.terminal.semanticView(0);
            try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
            try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 1));
            // Ordinary reply pressure also waits for a writable descriptor.
            try std.testing.expect((try state.terminal.feed("\x1b[5n")).stateChanged());
            state.read_end = 1;
            state.writes.count = write_queue_bytes;
            try std.testing.expect(!state.outputRunnable());
            state.writes.consume(state.writes.count);
            try std.testing.expect(state.outputRunnable());
        }

        test "large paste crosses the real PTY with one delimiter pair and deferred terminal reply" {
            if (comptime @import("builtin").os.tag != .linux) return error.SkipZigTest;
            const payload_len = maximum_paste_chunk_bytes * 4 + 17;
            const wire_len = payload_len + 12 + 4 + 2;
            var command: [512]u8 = undefined;
            const script = try std.fmt.bufPrint(
                &command,
                "stty raw -echo; printf '\\033[?2004hREADY'; " ++
                    "{{ head -c 1024; printf '\\033[5n' > /dev/tty; head -c {d}; }} | sha256sum; printf DONE",
                .{wire_len - 1024},
            );
            const instance = try init(std.testing.allocator, std.testing.environ, .{
                .shell = "/bin/sh",
                .command = script,
                .rows = 4,
                .columns = 80,
                .history_rows = 0,
            });
            defer deinit(instance);
            try serviceUntilContains(instance, "READY");
            const token = try beginPaste(instance);
            var chunk: [maximum_paste_chunk_bytes]u8 = undefined;
            @memset(&chunk, 'x');
            var admitted: usize = 0;
            var finished = false;
            var later = false;
            var fenced_reply = false;
            var pressure = false;
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update("\x1b[200~");
            for (0..4) |_| hasher.update(&chunk);
            hasher.update(chunk[0..17]);
            hasher.update("\x1b[201~\x1b[0nOK");
            var digest: [32]u8 = undefined;
            hasher.final(&digest);
            const expected = std.fmt.bytesToHex(&digest, .lower);
            var matched = false;
            for (0..3000) |_| {
                const progress = try service(instance, true, true, 0);
                if (progress.child_exit != null and !finished) return error.ChildExited;
                if (stateConst(instance).terminal.replyBytes().len != 0 and !finished)
                    fenced_reply = true;
                if (!finished) {
                    const count = @min(chunk.len, payload_len - admitted);
                    const final = admitted + count == payload_len;
                    if (pasteChunk(instance, token, chunk[0..count], final)) |_| {
                        admitted += count;
                        finished = final;
                    } else |err| switch (err) {
                        error.WriteQueueFull => pressure = true,
                        else => return err,
                    }
                } else if (!later) {
                    input(instance, .{ .bytes = "OK" }) catch |err| switch (err) {
                        error.WriteQueueFull => continue,
                        else => return err,
                    };
                    later = true;
                }
                var snapshot: [4096]u8 = undefined;
                if (std.mem.indexOf(u8, try snapshotAscii(instance, &snapshot), &expected) != null) {
                    matched = true;
                    break;
                }
                sleepOneMillisecond();
            }
            try std.testing.expect(matched);
            try std.testing.expect(finished and later and fenced_reply and pressure);
            try std.testing.expectEqual(payload_len, admitted);
        }

        test "literal program arguments reach the canonical terminal without command interpolation" {
            if (comptime @import("builtin").os.tag != .linux) return error.SkipZigTest;
            const instance = try init(std.testing.allocator, std.testing.environ, .{
                .shell = "/bin/sh",
                .arguments = &.{
                    "-c", "printf '%s\\n' \"$1\"; exec cat", "probe", "ARGV ;$(untouched)",
                },
                .rows = 4,
                .columns = 40,
                .history_rows = 0,
            });
            defer deinit(instance);
            try serviceUntilContains(instance, "ARGV ;$(untouched)");
            try std.testing.expectError(error.InvalidArgument, init(std.testing.allocator, std.testing.environ, .{
                .shell = "/bin/sh",
                .command = "must not execute",
                .arguments = &.{},
                .rows = 4,
                .columns = 40,
                .history_rows = 0,
            }));
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

        fn initAllocationProof(allocator: std.mem.Allocator) !void {
            const owner = try init(allocator, std.testing.environ, .{
                .shell = "/bin/sh",
                .command = "sleep 30",
                .rows = 2,
                .columns = 4,
                .history_rows = 4,
            });
            defer deinit(owner);
            try std.testing.expectEqual(@as(u16, 2), terminal(owner).semanticView(0).rows);
        }

        test "canonical Instance construction unwinds every allocation failure" {
            try std.testing.checkAllAllocationFailures(std.testing.allocator, initAllocationProof, .{});
        }

        test "selected composition has exact presentation storage" {
            try std.testing.expectEqual(
                if (Presentation != null) @sizeOf(?*PresentationState) else 0,
                @sizeOf(@FieldType(State, "presentation")),
            );
        }

        test {
            std.testing.refAllDecls(PresentationProofs);
        }

        const PresentationProofs = if (Presentation != null) struct {
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
                        .text = .{ .private = .{ .regular = .{ .path = font_config } } },
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

            test "presented publication grows frame command storage to configured limit" {
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
                        .rows = 2,
                        .columns = 8,
                        .history_rows = 8,
                    },
                    .{
                        .text = .{ .private = .{ .regular = .{ .path = font_config } } },
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
                        .command_capacity = 1,
                        .command_limit = 64,
                    },
                );
                defer deinit(instance);

                const state = stateMut(instance);
                try std.testing.expect((try state.terminal.feed("ABCDEFGH")).stateChanged());
                try publishRender(instance);

                const exchange = try renderExchange(instance);
                var lease = acquirePublishedFrame(exchange) orelse return error.MissingPublication;
                defer lease.abandon();
                try std.testing.expect(lease.value.commands.len > 1);
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
                        .text = .{ .private = .{ .regular = .{ .path = font_config } } },
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
                    .text = .{ .private = .{ .regular = .{ .path = first_font } } },
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
                // A refresh failure after allocation must unwind the staged owner only once.
                const staged_store = try TextStore.acquire(std.testing.allocator, base_config);
                defer staged_store.release();
                var limited = base_config;
                limited.command_capacity = 1;
                try std.testing.expectError(error.CommandLimit, PresentationState.initWithStore(
                    std.testing.allocator,
                    staged_store,
                    limited,
                    terminal(instance),
                ));
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
                next_config.text = .{ .private = .{ .regular = .{ .path = second_font } } };
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
                    .text = .{ .private = .{ .regular = .{ .path = first_font } } },
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
                next_config.text = .{ .private = .{ .regular = .{ .path = second_font } } };
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

            test "cursor and content cuts agree with complete projection across native mutations and stalled leases" {
                const allocator = std.testing.allocator;
                var canonical = try Terminal.initWithHistory(allocator, 4, 8, 8);
                defer canonical.deinit();
                const config = PresentationConfig{
                    .text = .{ .private = .{ .regular = .{ .path = .{
                        .primary = @import("test_fonts").primary_font,
                        .size = .{ .pixels = 18 },
                    } } } },
                    .box_drawing = .{
                        .dpi_x = .{ .numerator = 96, .denominator = 1 },
                        .dpi_y = .{ .numerator = 96, .denominator = 1 },
                    },
                    .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
                    .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
                    .shaped_capacity = 128,
                    .raster_bytes = 512 * 512,
                    .command_capacity = 256,
                    .incremental_row_capacity = 4,
                    .incremental_command_capacity = 256,
                };
                const fonts = try TextStore.acquire(allocator, config);
                const candidate = PresentationState.initWithStore(allocator, fonts, config, canonical.observation()) catch |failure| {
                    fonts.release();
                    return failure;
                };
                defer candidate.deinit(allocator);
                const cell = candidate.cellSize();
                try canonical.setCellPixelSize(cell.width, cell.height);
                const baseline = try terminal_render.initPrivate(allocator, candidate.store.fonts.faces(), .{
                    .cell_size = candidate.cellSize(),
                    .box_drawing = config.box_drawing,
                    .shape_cache = config.shape_cache,
                    .atlas = config.atlas,
                    .shaped_capacity = config.shaped_capacity,
                    .raster_bytes = config.raster_bytes,
                    .command_capacity = config.command_capacity,
                });
                defer terminal_render.deinit(baseline);

                const cuts = [_]struct { bytes: []const u8, history: u32 = 0 }{
                    .{ .bytes = "ABCDEFGH\x1b[2;1Hijklmnop\x1b[3;1Hqrstuvwx" },
                    .{ .bytes = "\x1b[2;2HX" }, // First small edit re-primes after broad repairs.
                    .{ .bytes = "\x1b[2;2HZ" },
                    .{ .bytes = "\x1b[4;2H\x1b[4mU\x1b[0m" },
                    .{ .bytes = "\x1b[4;2HR" },
                    .{ .bytes = "\x1b[4;2H\x1b[7mV\x1b[0m" },
                    .{ .bytes = "\x1b[4;2HR" },
                    .{ .bytes = "\x1b[4;2H\x1b[41mB\x1b[0m" },
                    .{ .bytes = "\x1b[4;2HR" },
                    .{ .bytes = "\x1b[4;1H\x1b#6" },
                    .{ .bytes = "\x1b[4;1H\x1b#5" },
                    .{ .bytes = "\x1b[1;2HX\x1b[3;2HY" },
                    .{ .bytes = "\x1b[1;3HJ\x1b[2;3HK\x1b[3;3HL" },
                    .{ .bytes = "\x1b[2J\x1b[1;1Hprompt> " },
                    .{ .bytes = "\x1b[1;3H" },
                    .{ .bytes = "\x1b[?2026h\x1b[3;2H\x1b[?2026l" },
                    .{ .bytes = "\x1b[?2026;5h\x1b[?2026l" },
                    .{ .bytes = "\x1b[?5l" },
                    .{ .bytes = "\x1b[2;4H\x1b[3 q" },
                    .{ .bytes = "\x1b[?25l" },
                    .{ .bytes = "\x1b[?25h\x1b[0 q" },
                    .{ .bytes = "\x1b[?25l\x1b[1;1Hhidden" },
                    .{ .bytes = "\x1b[2;3H" },
                    .{ .bytes = "\x1b[3 q\x1b[?25h" },
                    .{ .bytes = "\x1b[0 q" },
                    .{ .bytes = "\x1b[2;1H\x1b[4;9;44mQ\x1b[0m" },
                    .{ .bytes = "\x1b[1;1H\x1b#6" },
                    .{ .bytes = "\x1b[1;2H" },
                    .{ .bytes = "\x1b]4;1;#102030\x07\x1b[?5h" },
                    .{ .bytes = "\x1b[2;2H" },
                    .{ .bytes = "\x1b[?5l\x1b[2K" },
                    .{ .bytes = "\x1b[4;1H\r\nnew\r\nlast" },
                    .{ .bytes = "\x1b[1;2H", .history = 1 },
                    .{ .bytes = "\x1b[2;3H" },
                    .{ .bytes = "\x1b[?1049hALT" },
                    .{ .bytes = "\x1b[2;2H" },
                    .{ .bytes = "\x1b[?1049l" },
                    .{ .bytes = "\x1bcRESET" },
                    .{ .bytes = "\x1b[2;1H\u{754c}e\u{0301}" },
                    .{ .bytes = "\x1b[2;2H" },
                    .{ .bytes = "\x1b_Ga=T,f=32,s=1,v=1,i=1,q=2;/wAA/w==\x1b\\" },
                    .{ .bytes = "\x1b[1;1H" },
                    .{ .bytes = "\x1b_Ga=d,d=A,q=2;\x1b\\" },
                };
                try candidate.publish(canonical.observation(), 0);
                var held = acquirePublishedFrame(candidate.exchange) orelse return error.MissingPublication;
                defer held.abandon();
                const held_commands = try allocator.dupe(terminal_render.Command, held.value.commands);
                defer allocator.free(held_commands);
                var baseline_bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
                var baseline_binding_count: usize = 0;
                for (cuts) |cut| {
                    const old_history = candidate.terminal_history_offset;
                    const old_content = canonical.contentSequence();
                    const old_render = terminal_render.usage(candidate.renderer).content_revision;
                    try std.testing.expect((try canonical.feed(cut.bytes)).stateChanged());
                    try candidate.publish(canonical.observation(), cut.history);
                    if (canonical.contentSequence() == old_content and cut.history == old_history)
                        try std.testing.expectEqual(old_render, terminal_render.usage(candidate.renderer).content_revision);
                    var bindings: [terminal_render.maximum_external_images]terminal_render.ExternalImageBinding = undefined;
                    const images = try terminal_render.planObservationImageBindings(baseline_bindings[0..baseline_binding_count], terminal_render.usage(baseline), canonical.observation(), cut.history, &bindings);
                    try terminal_render.updateObservation(baseline, canonical.observation(), cut.history, images);
                    @memcpy(baseline_bindings[0..images.len], images);
                    baseline_binding_count = images.len;
                    if (std.mem.eql(u8, cut.bytes, "\x1b[2;2HZ")) {
                        const scene = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                        try std.testing.expectEqual(terminal_render.RowSceneKind.patch, scene.kind);
                        try std.testing.expect(scene.repairs[1]);
                        try std.testing.expect(!scene.repairs[0] and !scene.repairs[2] and !scene.repairs[3]);
                    }
                    if (std.mem.eql(u8, cut.bytes, "\x1b[1;2HX\x1b[3;2HY")) {
                        const scene = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                        try std.testing.expectEqual(terminal_render.RowSceneKind.patch, scene.kind);
                    }
                    if (std.mem.eql(u8, cut.bytes, "\x1b[1;3HJ\x1b[2;3HK\x1b[3;3HL"))
                        try std.testing.expect(terminal_render.rowScene(candidate.renderer) == null);
                    if (std.mem.eql(u8, cut.bytes, "\x1b[4;2H\x1b[4mU\x1b[0m") or
                        std.mem.eql(u8, cut.bytes, "\x1b[4;2H\x1b[7mV\x1b[0m") or
                        std.mem.eql(u8, cut.bytes, "\x1b[4;2H\x1b[41mB\x1b[0m") or
                        std.mem.eql(u8, cut.bytes, "\x1b[4;1H\x1b#6"))
                        try std.testing.expect(terminal_render.rowScene(candidate.renderer) == null);
                    try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                }
                try std.testing.expectEqualDeep(held_commands, held.value.commands);
                held.abandon();
                // A complete leased frame must match the full projection after both free
                // slots have warmed their content prefixes and then only the cursor moves.
                const content_revision = terminal_render.usage(candidate.renderer).content_revision;
                for ([_][]const u8{
                    "\x1b[1;2H", "\x1b[2;2H", "\x1b[2;3H", "\x1b[3;4H",
                    "\x1b[?25l", "\x1b[?25h", "\x1b[3 q",  "\x1b[0 q",
                }) |bytes| {
                    try std.testing.expect((try canonical.feed(bytes)).stateChanged());
                    try candidate.publish(canonical.observation(), 0);
                    try std.testing.expectEqual(content_revision, terminal_render.usage(candidate.renderer).content_revision);
                    try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                    var latest = acquirePublishedFrame(candidate.exchange) orelse return error.MissingPublication;
                    defer latest.abandon();
                    try expectPresentationCommandsEqual(candidate.renderer, baseline, latest.value.commands);
                }

                // A same-size return after two resizes cannot alias older row identities.
                try canonical.resize(3, 6);
                try canonical.resize(4, 8);
                try candidate.refresh(canonical.observation(), 0);
                try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                // An externally reset renderer cannot reuse an older private base.
                try terminal_render.resetCaches(candidate.renderer);
                try terminal_render.resetCaches(baseline);
                try std.testing.expect((try canonical.feed("\x1b[3;2H")).stateChanged());
                try candidate.refresh(canonical.observation(), 0);
                try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                try expectPresentationCommandsEqual(candidate.renderer, baseline, null);

                var small = try Terminal.init(allocator, 2, 4);
                defer small.deinit();
                var limited_config = config;
                limited_config.command_capacity = 1;
                const limited_fonts = try TextStore.acquire(allocator, limited_config);
                const limited = PresentationState.initWithStore(allocator, limited_fonts, limited_config, small.observation()) catch |failure| {
                    limited_fonts.release();
                    return failure;
                };
                defer limited.deinit(allocator);
                try std.testing.expect((try small.feed("A")).stateChanged());
                try std.testing.expectError(error.CommandLimit, limited.refresh(small.observation(), 0));
                try std.testing.expect((try small.feed("\r\x1b[2K\x1b[2;1H")).stateChanged());
                try limited.refresh(small.observation(), 0);
                try terminal_render.updateObservation(baseline, small.observation(), 0, &.{});
                try expectPresentationCommandsEqual(limited.renderer, baseline, null);
            }

            fn expectPresentationCommandsEqual(candidate: *terminal_render.Renderer, baseline: *terminal_render.Renderer, published: ?[]const terminal_render.Command) !void {
                var commands: [2][512]terminal_render.Command = undefined;
                var uploads: [2][terminal_render.maximum_external_images + 1]terminal_render.FrameResourceUpload = undefined;
                var removals: [2][terminal_render.maximum_external_images + 1]terminal_render.ResourceRef = undefined;
                var pixels: [2][512 * 512]u8 = undefined;
                var residency: [terminal_render.maximum_external_images]terminal_render.Residency = undefined;
                var frames: [2]terminal_render.Frame = undefined;
                var external_storage: [terminal_render.maximum_external_images]terminal_render.FrameExternalResource = undefined;
                for ([_]*terminal_render.Renderer{ candidate, baseline }, 0..) |renderer, index| {
                    const missing = try terminal_render.missingExternalResources(renderer, &.{}, &external_storage);
                    for (missing, 0..) |external, i| residency[i] = .{ .resource = external.resource, .format = external.format, .size = external.size };
                    frames[index] = try terminal_render.frame(renderer, residency[0..missing.len], .{
                        .commands = &commands[index],
                        .uploads = &uploads[index],
                        .removals = &removals[index],
                        .pixels = &pixels[index],
                    });
                }
                try std.testing.expectEqualDeep(frames[0].commands, frames[1].commands);
                if (published) |commands_value| try std.testing.expectEqualDeep(frames[0].commands, commands_value);
            }

            test "shared text owner survives caller release and isolates cache pressure, stalled frames and canonical service" {
                const a = std.testing.allocator;
                var threaded = std.Io.Threaded.init(a, .{});
                defer threaded.deinit();
                var config = PresentationConfig{
                    .text = .{ .private = .{ .regular = .{ .path = .{
                        .primary = @import("test_fonts").primary_font,
                        .size = .{ .pixels = 18 },
                    } } } },
                    .box_drawing = .{
                        .dpi_x = .{ .numerator = 96, .denominator = 1 },
                        .dpi_y = .{ .numerator = 96, .denominator = 1 },
                    },
                    .shape_cache = .{ .entry_capacity = 4, .scalar_capacity = 16, .glyph_capacity = 16, .max_sequence_scalars = 16 },
                    .atlas = .{ .width = 256, .height = 256, .entry_capacity = 32 },
                    .shaped_capacity = 32,
                    .raster_bytes = 256 * 256,
                    .command_capacity = 256,
                    .incremental_row_capacity = 4,
                    .incremental_command_capacity = 256,
                };
                const shared = try initPresentationStore(a, threaded.io(), config.text.private, .{
                    .shape_cache = config.shape_cache,
                    .shaped_capacity = config.shaped_capacity,
                    .raster_bytes = config.raster_bytes,
                });
                var caller_live = true;
                defer if (caller_live) releasePresentationStore(shared);
                config.text = .{ .shared = shared };
                const launch = Launch{ .shell = "/bin/sh", .command = "printf A; sleep 30", .rows = 2, .columns = 8, .history_rows = 8 };
                const first = try initPresented(a, std.testing.environ, launch, config);
                defer deinit(first);
                const second = try initPresented(a, std.testing.environ, launch, config);
                defer deinit(second);
                try std.testing.expectEqual(@as(u32, 3), presentationStoreReferences(shared));
                try serviceUntilContains(first, "A");
                try serviceUntilContains(second, "A");
                try publishRender(first);
                const warm = presentationStoreUsage(shared);
                try publishRender(second);
                try std.testing.expectEqualDeep(warm, presentationStoreUsage(shared));

                // Reject duplicated/mismatched Store bounds without touching the old surface.
                var mismatch = config;
                mismatch.raster_bytes -= 1;
                try std.testing.expectError(error.InvalidConfig, reconfigurePresentation(second, mismatch));
                try std.testing.expectEqual(@as(u32, 3), presentationStoreReferences(shared));

                const one = stateMut(first).presentation.?;
                const two = stateMut(second).presentation.?;
                var held = acquirePublishedFrame(one.exchange) orelse return error.MissingPublication;
                defer held.abandon();
                var saved: [256]terminal_render.Command = undefined;
                const commands = held.value.commands;
                @memcpy(saved[0..commands.len], commands);
                const first_usage = try renderUsage(first);
                // A terminal atlas reset must not flush process shaping or its neighbour.
                try terminal_render.resetCaches(two.renderer);
                try std.testing.expectEqualDeep(warm, presentationStoreUsage(shared));
                for ([_][]const u8{ "\r\x1b[2KB", "\r\x1b[2KC", "\r\x1b[2KD", "\r\x1b[2KE", "\r\x1b[2KF" }) |bytes| {
                    try std.testing.expect((try stateMut(second).terminal.feed(bytes)).stateChanged());
                    try publishRender(second);
                }
                const after = try renderUsage(first);
                try std.testing.expectEqual(first_usage.resource_generation, after.resource_generation);
                try std.testing.expectEqual(first_usage.atlas_entries, after.atlas_entries);
                try std.testing.expectEqualDeep(saved[0..commands.len], commands);
                try std.testing.expect(presentationStoreUsage(shared).shape.entries <= 4);

                const owner = textStore(shared);
                owner.references.store(1024, .monotonic);
                try std.testing.expectError(error.PresentationStoreLimit, initPresented(a, std.testing.environ, launch, config));
                try std.testing.expectEqual(@as(u32, 1024), owner.references.load(.monotonic));
                owner.references.store(3, .monotonic);
                owner.mutex.lockUncancelable(owner.io);
                {
                    defer owner.mutex.unlock(owner.io);
                    // Cursor-only work requires no shared text claim.
                    try std.testing.expect((try stateMut(first).terminal.feed("\x1b[2;2H")).stateChanged());
                    try publishRender(first);
                    try std.testing.expect((try stateMut(first).terminal.feed("Z")).stateChanged());
                    try std.testing.expectError(error.PresentationBusy, publishRender(first));
                    // Canonical I/O still runs while another projection owns native text.
                    // Echo stays within the deliberately tiny whole-frame shape budget.
                    try input(second, .{ .bytes = "AAA\n" });
                    const turn = try service(second, true, true, 0);
                    try std.testing.expect(!turn.stream_closed);
                }
                try publishRender(first);
                releasePresentationStore(shared);
                caller_live = false;
                // Both instances own a reference even though the embedding owner has retired.
                try publishRender(second);
            }

            fn storeAllocationProof(allocator: std.mem.Allocator) !void {
                const store = try initPresentationStore(allocator, .failing, .{
                    .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } } },
                    .bold = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } } },
                }, .{
                    .shape_cache = .{ .entry_capacity = 4, .scalar_capacity = 16, .glyph_capacity = 16, .max_sequence_scalars = 16 },
                    .shaped_capacity = 32,
                    .raster_bytes = 256 * 256,
                });
                defer releasePresentationStore(store);
            }

            test "shared text construction unwinds every Zig allocation failure" {
                try std.testing.checkAllAllocationFailures(std.testing.allocator, storeAllocationProof, .{});
            }

            test "row cache budgets preserve complete frames across fixed-buffer fallback and command limits" {
                const allocator = std.testing.allocator;
                for ([_]usize{ 4, 32, 512 }) |budget| {
                    var canonical = try Terminal.init(allocator, 4, 8);
                    defer canonical.deinit();
                    const config = PresentationConfig{
                        .text = .{ .private = .{ .regular = .{ .path = .{
                            .primary = @import("test_fonts").primary_font,
                            .size = .{ .pixels = 18 },
                        } } } },
                        .box_drawing = .{
                            .dpi_x = .{ .numerator = 96, .denominator = 1 },
                            .dpi_y = .{ .numerator = 96, .denominator = 1 },
                        },
                        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
                        .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
                        .shaped_capacity = 128,
                        .raster_bytes = 512 * 512,
                        .command_capacity = 1,
                        .command_limit = 64,
                        .incremental_row_capacity = 4,
                        .incremental_command_capacity = budget,
                    };
                    const fonts = try TextStore.acquire(allocator, config);
                    const candidate = PresentationState.initWithStore(allocator, fonts, config, canonical.observation()) catch |failure| {
                        fonts.release();
                        return failure;
                    };
                    defer candidate.deinit(allocator);
                    const cell = candidate.cellSize();
                    try canonical.setCellPixelSize(cell.width, cell.height);
                    const baseline = try terminal_render.initPrivate(allocator, candidate.store.fonts.faces(), .{
                        .cell_size = cell,
                        .box_drawing = config.box_drawing,
                        .shape_cache = config.shape_cache,
                        .atlas = config.atlas,
                        .shaped_capacity = config.shaped_capacity,
                        .raster_bytes = config.raster_bytes,
                        .command_capacity = 64,
                        .command_limit = 64,
                    });
                    defer terminal_render.deinit(baseline);
                    try std.testing.expect((try canonical.feed("\x1b[?25lABCD")).stateChanged());
                    try candidate.publish(canonical.observation(), 0);
                    try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                    try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                    const initial_scene = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                    try std.testing.expectEqual(@as(usize, 4), initial_scene.commands.len);
                    try std.testing.expect(terminal_render.usage(candidate.renderer).command_capacity <= config.command_limit);
                    if (budget == 4) try std.testing.checkAllAllocationFailures(
                        allocator,
                        rowCommandBufferAllocationProof,
                        .{ candidate.store.fonts.faces(), cell, config },
                    );
                    var held = acquirePublishedFrame(candidate.exchange) orelse return error.MissingPublication;
                    defer held.abandon();
                    const held_commands = try allocator.dupe(terminal_render.Command, held.value.commands);
                    defer allocator.free(held_commands);
                    for ([_][]const u8{
                        "\x1b[2J\x1b[HABCDEFGH\x1b[2;1HABCDEFGH\x1b[3;1HABCDEFGH\x1b[4;1HABCDEFGH",
                        "\x1b[2J\x1b[HABCD",
                        "\x1b[1;2HZ",
                    }, 0..) |bytes, index| {
                        try std.testing.expect((try canonical.feed(bytes)).stateChanged());
                        try candidate.publish(canonical.observation(), 0);
                        try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                        try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                        try std.testing.expect(terminal_render.usage(candidate.renderer).command_capacity <= config.command_limit);
                        if (index < 2) {
                            try std.testing.expect(terminal_render.rowScene(candidate.renderer) == null);
                        } else {
                            const scene = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                            try std.testing.expect(scene.commands.len <= budget);
                            if (index != 0) try std.testing.expectEqual(@as(usize, 4), scene.commands.len);
                        }
                    }
                    const primed = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                    try std.testing.expectEqual(terminal_render.RowSceneKind.baseline, primed.kind);
                    try std.testing.expect((try canonical.feed("\x1b[1;3HY")).stateChanged());
                    try candidate.publish(canonical.observation(), 0);
                    try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                    try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                    const patched = terminal_render.rowScene(candidate.renderer) orelse return error.MissingRowScene;
                    try std.testing.expectEqual(terminal_render.RowSceneKind.patch, patched.kind);
                    try std.testing.expect(patched.repairs[0]);
                    try std.testing.expect(!patched.repairs[1] and !patched.repairs[2] and !patched.repairs[3]);
                    // An oversized cache budget cannot widen the declared command limit.
                    try canonical.resize(4, 16);
                    try std.testing.expect((try canonical.feed("\x1b[2J\x1b[HABCDEFGHIJKLMNOP\x1b[2;1HABCDEFGHIJKLMNOP\x1b[3;1HABCDEFGHIJKLMNOP\x1b[4;1HABCDEFGHIJKLMNOP")).stateChanged());
                    try std.testing.expectError(error.CommandLimit, candidate.refresh(canonical.observation(), 0));
                    // Match failed atlas work before comparing exact resource generations.
                    try std.testing.expectError(error.CommandLimit, terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{}));
                    try std.testing.expect(terminal_render.rowScene(candidate.renderer) == null);
                    try std.testing.expect((try canonical.feed("\x1b[2J\x1b[HABCD")).stateChanged());
                    try candidate.publish(canonical.observation(), 0);
                    try terminal_render.updateObservation(baseline, canonical.observation(), 0, &.{});
                    try expectPresentationCommandsEqual(candidate.renderer, baseline, null);
                    try std.testing.expect(terminal_render.rowScene(candidate.renderer) != null);
                    try std.testing.expectEqualDeep(held_commands, held.value.commands);
                }
            }

            fn rowCommandBufferAllocationProof(
                allocator: std.mem.Allocator,
                faces: terminal_render.FontFaces,
                cell_size: terminal_render.Size,
                config: PresentationConfig,
            ) !void {
                // Canonical mutations are outside the presentation allocator being faulted.
                var canonical = try Terminal.init(std.testing.allocator, 4, 8);
                defer canonical.deinit();
                try canonical.setCellPixelSize(cell_size.width, cell_size.height);
                const renderer = try terminal_render.initPrivate(allocator, faces, .{
                    .cell_size = cell_size,
                    .box_drawing = config.box_drawing,
                    .shape_cache = config.shape_cache,
                    .atlas = config.atlas,
                    .shaped_capacity = config.shaped_capacity,
                    .raster_bytes = config.raster_bytes,
                    .command_capacity = 1,
                    .command_limit = 64,
                    .incremental_row_capacity = 4,
                    .incremental_command_capacity = 4,
                });
                defer terminal_render.deinit(renderer);
                const repairs = [_]bool{ true, true, true, true };
                var base_revision: ?u64 = null;
                for ([_][]const u8{
                    "\x1b[?25lABCD",
                    "\x1b[2J\x1b[HABCDEFGH\x1b[2;1HABCDEFGH\x1b[3;1HABCDEFGH\x1b[4;1HABCDEFGH",
                    "\x1b[2J\x1b[HABCD",
                    "\x1b[1;2HZ",
                }, 0..) |bytes, index| {
                    try std.testing.expect((try canonical.feed(bytes)).stateChanged());
                    try terminal_render.updateObservationRows(renderer, canonical.observation(), 0, .{
                        .base_revision = base_revision,
                        .rows = &repairs,
                    }, &.{});
                    base_revision = canonical.observation().contentSequence();
                    try std.testing.expect(terminal_render.usage(renderer).command_capacity <= 64);
                    if (index == 1) {
                        try std.testing.expect(terminal_render.rowScene(renderer) == null);
                    } else {
                        const scene = terminal_render.rowScene(renderer) orelse return error.MissingRowScene;
                        try std.testing.expectEqual(@as(usize, 4), scene.commands.len);
                    }
                }
            }

            fn foreignConstructionConfig(store: *PresentationStore) PresentationConfig {
                return .{
                    .text = .{ .shared = store },
                    .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
                    .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
                    .shaped_capacity = 1024,
                    .raster_bytes = 64 * 1024,
                    .atlas = .{ .width = 128, .height = 128, .entry_capacity = 256 },
                    .command_capacity = 256,
                    .command_limit = 256,
                };
            }

            fn foreignConstructionStore(allocator: std.mem.Allocator, io: std.Io) !*PresentationStore {
                return initPresentationStore(allocator, io, .{
                    .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } } },
                }, .{
                    .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
                    .shaped_capacity = 1024,
                    .raster_bytes = 64 * 1024,
                });
            }

            test "try presented admission precedes allocation and restores references and claims" {
                const store = try foreignConstructionStore(std.testing.allocator, .failing);
                defer releasePresentationStore(store);
                const owner = textStore(store);
                var config = foreignConstructionConfig(store);
                const launch = Launch{ .shell = "/bin/sh", .command = "exec sleep 30", .rows = 2, .columns = 4, .history_rows = 0 };
                var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
                try std.testing.expect(owner.mutex.tryLock());
                var held = true;
                defer if (held) owner.mutex.unlock(owner.io);
                for (0..32) |_| {
                    try std.testing.expectError(error.PresentationBusy, tryInitPresented(failing.allocator(), std.testing.environ, launch, config));
                    try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
                    try std.testing.expect(!failing.has_induced_failure);
                }
                owner.mutex.unlock(owner.io);
                held = false;
                try std.testing.expectError(error.OutOfMemory, tryInitPresented(failing.allocator(), std.testing.environ, launch, config));
                try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
                try std.testing.expect(owner.mutex.tryLock());
                owner.mutex.unlock(owner.io);
                // Atlas validation occurs after State/PTY startup; this forces a
                // deterministic late failure even when the initial VT is blank.
                config.atlas.width = 0;
                try std.testing.expectError(error.InvalidAtlasConfig, tryInitPresented(std.testing.allocator, std.testing.environ, launch, config));
                try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
                try std.testing.expect(owner.mutex.tryLock());
                owner.mutex.unlock(owner.io);
                config.atlas.width = 128;
                const value = try tryInitPresented(std.testing.allocator, std.testing.environ, launch, config);
                try std.testing.expectEqual(@as(u32, 2), presentationStoreReferences(store));
                deinit(value);
                try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
            }

            fn tryPresentedAllocationProof(allocator: std.mem.Allocator, store: *PresentationStore) !void {
                const value = tryInitPresented(allocator, std.testing.environ, .{
                    .shell = "/bin/sh",
                    .command = "exec sleep 30",
                    .rows = 2,
                    .columns = 4,
                    .history_rows = 0,
                }, foreignConstructionConfig(store)) catch |failure| {
                    try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
                    const owner = textStore(store);
                    try std.testing.expect(owner.mutex.tryLock());
                    owner.mutex.unlock(owner.io);
                    return failure;
                };
                deinit(value);
                try std.testing.expectEqual(@as(u32, 1), presentationStoreReferences(store));
            }

            test "try presented construction unwinds every allocation prefix" {
                const store = try foreignConstructionStore(std.testing.allocator, .failing);
                defer releasePresentationStore(store);
                try std.testing.checkAllAllocationFailures(std.testing.allocator, tryPresentedAllocationProof, .{store});
            }

            test "ordinary presented construction keeps its waiting shared font lane" {
                var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
                defer threaded.deinit();
                const io = threaded.io();
                const store = try foreignConstructionStore(std.testing.allocator, io);
                defer releasePresentationStore(store);
                const owner = textStore(store);
                const Context = struct {
                    store: *PresentationStore,
                    done: std.atomic.Value(bool) = .init(false),
                    result: ?*Instance = null,
                    failure: ?PresentedInitError = null,
                    fn run(context: *@This()) void {
                        context.result = initPresented(std.testing.allocator, std.testing.environ, .{
                            .shell = "/bin/sh",
                            .command = "exec sleep 30",
                            .rows = 2,
                            .columns = 4,
                            .history_rows = 0,
                        }, foreignConstructionConfig(context.store)) catch |failure| blk: {
                            context.failure = failure;
                            break :blk null;
                        };
                        context.done.store(true, .release);
                    }
                };
                var context = Context{ .store = store };
                try std.testing.expect(owner.mutex.tryLock());
                var held = true;
                const worker = std.Thread.spawn(.{}, Context.run, .{&context}) catch |failure| {
                    owner.mutex.unlock(io);
                    return failure;
                };
                var joined = false;
                defer {
                    if (held) owner.mutex.unlock(io);
                    if (!joined) worker.join();
                    if (context.result) |value| deinit(value);
                }
                for (0..5000) |_| {
                    if (owner.mutex.state.load(.acquire) == .contended) break;
                    if (context.done.load(.acquire)) return error.DidNotWait;
                    try std.Io.sleep(io, .fromMilliseconds(1), .awake);
                } else return error.Timeout;
                try std.testing.expect(!context.done.load(.acquire));
                try std.testing.expectEqual(@as(u32, 2), presentationStoreReferences(store));
                owner.mutex.unlock(io);
                held = false;
                worker.join();
                joined = true;
                try std.testing.expect(context.failure == null);
                try std.testing.expect(context.result != null);
                try std.testing.expectEqual(@as(u32, 2), presentationStoreReferences(store));
            }
        } else struct {};
    };
}

test {
    const selected = if (@import("composition_options").presentation) struct {
        /// Exact Render package for the presented composition proofs.
        pub const render = @import("howl_render");
        /// Exact immutable publication owner for the presented composition proofs.
        pub const publication = @import("instance_publication");
    } else null;
    const runtime = Runtime(selected);
    try std.testing.expect(runtime.Terminal == vt.Terminal);
}
