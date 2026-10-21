//! One canonical PTY/VT owner with optional direct Render presentation.
const std = @import("std");
const runtime = @import("instance_runtime").Runtime(struct {
    /// Exact Render package selected only by the local entry point.
    pub const render = @import("howl_render");
    /// Exact immutable publication owner selected only by the local entry point.
    pub const publication = @import("instance_publication");
});

/// Exact backend-neutral Render package composed by this Instance package.
pub const render = runtime.render;
/// Exact text package instance used by this Instance package's Render owner.
pub const text = runtime.text;
/// Opaque SPSC exchange shared with one embedding backend thread.
pub const RenderExchange = runtime.RenderExchange;
/// One immutable backend-facing Render publication lease.
pub const RenderLease = runtime.RenderLease;
/// One immutable self-contained Render transaction.
pub const PublishedFrame = runtime.PublishedFrame;
/// Acquires only the newest unread Render publication.
pub const acquirePublishedFrame = runtime.acquirePublishedFrame;
/// Opaque handle to one canonical PTY + VT lifetime owner.
pub const Instance = runtime.Instance;
/// Canonical terminal engine type owned by one Instance.
pub const Terminal = runtime.Terminal;
/// Largest streaming paste chunk admitted without a permanent size failure.
pub const maximum_paste_chunk_bytes = runtime.maximum_paste_chunk_bytes;
/// Nonreused identity for one streaming paste in this composition.
pub const PasteToken = runtime.PasteToken;
/// Reports occupied input lane, older reply pressure, or exhausted identity.
pub const BeginPasteError = runtime.BeginPasteError;
/// Reports stale operation identity or whole-chunk admission failure.
pub const PasteError = runtime.PasteError;
/// Platform-native PTY readiness descriptor exposed only to platform service owners.
pub const Descriptor = runtime.Descriptor;
/// Host-neutral input accepted by the canonical VT owner.
pub const Input = runtime.Input;
/// Names physical non-Unicode key identities accepted by canonical input encoding.
pub const KeyName = runtime.KeyName;
/// Validates Unicode or named physical-key identity.
pub const Key = runtime.Key;
/// Names one key press/repeat/release transition.
pub const KeyAction = runtime.KeyAction;
/// Copies full keyboard/mouse modifier state.
pub const InputModifier = runtime.InputModifier;
/// Names one mouse event class.
pub const MouseEventKind = runtime.MouseEventKind;
/// Names one mouse button identity.
pub const MouseButton = runtime.MouseButton;
/// Bounds committed key text accepted by the canonical VT encoder.
pub const maximum_key_text_bytes = runtime.maximum_key_text_bytes;
/// Bounds legacy key bytes while leaving canonical Meta prefix headroom.
pub const maximum_legacy_key_bytes = runtime.maximum_legacy_key_bytes;
/// Maximum scalars retained by one bounded terminal grapheme.
pub const maximum_cell_scalars = runtime.maximum_cell_scalars;
/// Fixed process-group signal vocabulary.
pub const Signal = runtime.Signal;
/// Exact process-group signal delivery outcome.
pub const SignalResult = runtime.SignalResult;
/// One ordered host-facing consequence retained by the canonical VT.
pub const Consequence = runtime.Consequence;
/// Reports stale occurrence identity or a consequence requiring a typed reply.
pub const ConsumeConsequenceError = runtime.ConsumeConsequenceError;
/// Reports clipboard reply admission failure without consuming a stale query.
pub const ClipboardReplyError = runtime.ClipboardReplyError;
/// Reports pointer-shape reply admission or identity failure.
pub const PointerShapeReplyError = runtime.PointerShapeReplyError;
/// Terminal-owned light/dark color preference vocabulary.
pub const ColorSchemePreference = runtime.ColorSchemePreference;
/// Reports color-preference reply admission or identity failure.
pub const ColorPreferenceReplyError = runtime.ColorPreferenceReplyError;
/// Typed container/window query reply vocabulary.
pub const ContainerReply = runtime.ContainerReply;
/// Reports container reply admission, identity, or type mismatch.
pub const ContainerReplyError = runtime.ContainerReplyError;
/// Selects whether a service turn applies deterministic headless host policy or retains host consequences.
pub const ConsequencePolicy = runtime.ConsequencePolicy;
/// Exact child-process termination observation.
pub const ChildExit = runtime.ChildExit;
/// Exact generated box-drawing configuration consumed by Instance-owned Render.
pub const BoxDrawingConfig = runtime.BoxDrawingConfig;
/// Selects one owned font source for presented Instance construction.
pub const FontConfig = runtime.FontConfig;
/// Supplies one required regular font and optional style variants.
pub const FontFamilyConfig = runtime.FontFamilyConfig;
/// Supplies bounded text and renderer policy for one presented Instance.
///
/// The canonical cell lattice is derived from the regular font metrics. The
/// caller does not separately choose PTY/VT and Render pixel geometry.
pub const PresentationConfig = runtime.PresentationConfig;
/// Owns one fixed native font family, shared shape cache and reusable scratch.
/// Matching terminals borrow this owner; atlases, commands and frames remain local.
/// Mutable native faces are serialized internally. The supplied Io outlives all
/// borrowers, including those surviving release of the caller's reference.
pub const PresentationStore = runtime.PresentationStore;
/// Reports font, bounded Store, or ownership admission failure.
pub const PresentationStoreInitError = runtime.PresentationStoreInitError;
/// Creates one caller reference for a compatible font recipe and pixel size.
/// Share the returned pointer through PresentationConfig.text.shared. Construction
/// copies font sources; the input recipe does not need to survive this call.
pub const initPresentationStore = runtime.initPresentationStore;
/// Releases the caller reference. Existing presented Instances retain the owner
/// until their renderers retire; the caller must not reuse its released pointer.
pub const releasePresentationStore = runtime.releasePresentationStore;
/// Copies immutable font-derived cell geometry without claiming mutable faces.
pub const presentationStoreCellSize = runtime.presentationStoreCellSize;
/// Includes the caller's reference and all presented borrowers. Caller ownership
/// must remain live; a count of one permits an embedder to retire an idle owner.
pub const presentationStoreReferences = runtime.presentationStoreReferences;
/// Reads shared cache usage under the native-face claim.
pub const presentationStoreUsage = runtime.presentationStoreUsage;
/// Reports the exact grid and cell lattice chosen for one presented surface.
pub const PresentationGeometry = runtime.PresentationGeometry;
/// Supplies one local shell launch and bounded canonical terminal geometry.
pub const Launch = runtime.Launch;
/// Applies the host-configured VT color baseline without parsing synthetic output.
pub const setColorDefaults = runtime.setColorDefaults;
/// Replaces canonical cursor defaults without clearing application overrides.
pub const setDefaultCursorStyle = runtime.setDefaultCursorStyle;
/// Reports opt-in color-preference notification admission failure.
pub const ColorPreferenceNotificationError = runtime.ColorPreferenceNotificationError;
/// Notifies a program only when its canonical mode2031 requests host preference changes.
pub const reportColorSchemePreference = runtime.reportColorSchemePreference;
/// Reports construction failure before a instance becomes observable.
pub const InitError = runtime.InitError;
/// Reports construction failure before a presented Instance becomes observable.
pub const PresentedInitError = runtime.PresentedInitError;
/// Reports construction failure or shared font access that would wait.
pub const TryPresentedInitError = runtime.TryPresentedInitError;
/// Reports terminal input encoding, signal, or bounded write admission failure.
pub const InputError = runtime.InputError;
/// Reports atomic PTY and VT geometry transition failure.
pub const ResizeError = runtime.ResizeError;
/// Reports PTY, VT, reply, or headless policy progress failure.
pub const ServiceError = runtime.ServiceError;
/// Reports a backend-frame request before presentation exists, or Render failure.
pub const RenderError = runtime.RenderError;
/// Reports publication preparation or bounded exchange failure.
pub const PublishError = runtime.PublishError;
/// Reports transactional font/renderer replacement or canonical geometry failure.
pub const ReconfigurePresentationError = runtime.ReconfigurePresentationError;
/// Summarizes one bounded service turn without exposing PTY or VT ownership.
pub const Service = runtime.Service;
/// Constructs one PTY and VT owner from an explicit inherited environment.
pub const init = runtime.init;
/// Constructs one PTY -> VT -> Render owner on one caller-serialized thread.
///
/// Text ownership is explicit in PresentationConfig; Instance retains a shared
/// owner or creates the requested private owner, alongside its VT and Renderer.
/// Initial PTY/VT pixel geometry comes from the regular font metrics.
pub const initPresented = runtime.initPresented;
/// Tries font access before allocating State or launching a child; never waits for that claim.
pub const tryInitPresented = runtime.tryInitPresented;
/// Stops the child, releases VT state, and destroys the opaque owner.
pub const deinit = runtime.deinit;
/// Checked teardown rejects outstanding native backend endpoints or frame leases.
pub const tryDeinit = runtime.tryDeinit;
/// Returns the PTY descriptor for caller-owned poll integration.
pub const descriptor = runtime.descriptor;
/// True while a prior service turn retains child output in its bounded read buffer.
pub const bufferedOutputPending = runtime.bufferedOutputPending;
/// True when buffered child output can progress without another write/paste chunk.
pub const bufferedOutputRunnable = runtime.bufferedOutputRunnable;
/// True while caller input or terminal replies are queued for the child PTY.
///
/// Poll owners include writable readiness whenever this is true; unlike the
/// previous Service result, this reflects input admitted since the last turn.
pub const writePending = runtime.writePending;
/// Reports whether this Instance owns canonical text/Render presentation state.
pub const presented = runtime.presented;
/// Reports current Instance-owned Render usage without exposing mutable Renderer state.
pub const renderUsage = runtime.renderUsage;
/// Derives one backend-neutral frame from the current Instance-owned Render state.
///
/// Returned slices borrow caller buffers and remain valid until those buffers or
/// this Instance's Render state are mutated.
pub const renderFrame = runtime.renderFrame;
/// Reports visible Host-owned terminal-image resources missing from backend residency.
pub const missingRenderResources = runtime.missingRenderResources;
/// Borrows the backend-only exchange handle owned by this presented Instance.
///
/// The embedding render thread may retain this handle until Instance teardown,
/// but must not retain the Instance itself. All leases must be released before
/// the terminal thread destroys the Instance.
pub const renderExchange = runtime.renderExchange;
/// Registers a sole native backend and resets presentation residency on the owner thread.
pub const borrowRenderExchange = runtime.borrowRenderExchange;
/// Drops the registered backend only after its last frame lease.
pub const releaseRenderExchange = runtime.releaseRenderExchange;
/// Publishes the newest canonical VT cut as one immutable backend transaction.
///
/// This is a terminal-thread operation. It never waits for the backend: an
/// unread older frame is replaceable, while a frame currently leased by the
/// backend remains immutable until release.
pub const publishRender = runtime.publishRender;
/// Publishes one canonical history cut through the same Instance-owned Renderer.
///
/// The history offset is clamped by VT observation semantics. View selection
/// stays on the terminal thread; the backend still receives only final Render work.
pub const publishRenderAt = runtime.publishRenderAt;
/// Transactionally replaces Instance-owned fonts and Renderer on the terminal thread.
///
/// The publication exchange survives the replacement. Its presentation generation
/// advances so a backend may safely release an older lease without making stale
/// residency visible to the new Renderer.
pub const reconfigurePresentation = runtime.reconfigurePresentation;
/// Transactionally replaces presentation and canonical terminal geometry.
///
/// Font/Renderer construction and validation complete before PTY/VT geometry
/// commits, so after the resize succeeds the remaining owner swap is infallible.
pub const reconfigurePresentationGeometry = runtime.reconfigurePresentationGeometry;
/// Replaces presentation and derives the canonical grid from a physical surface.
///
/// Font metrics, rows/columns, PTY pixels, VT pixels and Render cell geometry
/// are chosen on the same terminal-thread transaction.
pub const reconfigurePresentationSurface = runtime.reconfigurePresentationSurface;
/// Borrows the canonical VT observation capability until the next Instance mutation.
///
/// Mutation remains Instance-owned so PTY writes, replies, resize and child
/// lifetime cannot be bypassed through this embedder observation seam.
pub const terminal = runtime.terminal;
/// Borrows the oldest retained host consequence until canonical terminal mutation.
pub const consequenceHead = runtime.consequenceHead;
/// Returns the bounded count of retained host consequences.
pub const consequenceCount = runtime.consequenceCount;
/// Consumes one non-reply consequence by exact global FIFO identity.
pub const consumeConsequence = runtime.consumeConsequence;
/// Copies one decoded FIFO-head OSC 52 set without consuming it.
pub const copyClipboard = runtime.copyClipboard;
/// Replies to one exact pending OSC 52 clipboard query.
pub const replyClipboard = runtime.replyClipboard;
/// Replies to one exact pending OSC 22 pointer-shape query.
pub const replyPointerShape = runtime.replyPointerShape;
/// Replies to one exact pending color-preference query.
pub const replyColorPreference = runtime.replyColorPreference;
/// Replies to one exact pending container query.
pub const replyContainer = runtime.replyContainer;
/// Declines one exact pending container query without fabricating host state.
pub const declineContainerQuery = runtime.declineContainerQuery;
/// Encodes and admits one input event in canonical instance order.
/// Active streaming paste returns WriteQueueFull before encoding.
pub const input = runtime.input;
/// Opens one ordered paste after payload acquisition/validation; snapshots bracket mode.
pub const beginPaste = runtime.beginPaste;
/// Atomically copies one bounded chunk; final closes the paste and retires the token.
pub const pasteChunk = runtime.pasteChunk;
/// Closes an admitted prefix and retires its token without allocation.
pub const cancelPaste = runtime.cancelPaste;
/// Atomically applies one explicit canonical PTY and VT geometry.
pub const resize = runtime.resize;
/// Applies explicit cell-pixel metrics with canonical rows/columns and PTY size.
/// A zero pair preserves the previously accepted pixel lattice.
pub const resizeGeometry = runtime.resizeGeometry;
/// Delivers one fixed signal to the canonical child process group.
pub const signal = runtime.signal;
/// Services bounded PTY read/write progress and canonical VT consequences.
pub const service = runtime.service;
/// Services one turn, yielding on synchronized release and retaining any unread tail.
/// Callers continue while bufferedOutputPending, including without PTY readiness.
///
/// `.retain` leaves canonical VT consequences queued for an external authority;
/// `.headless` applies the existing deterministic fallback policy. Switching a
/// retained instance back to `.headless` drains already-pending consequences on
/// that same service turn, so authority loss cannot strand a terminal query.
pub const serviceWithConsequencePolicy = runtime.serviceWithConsequencePolicy;

test {
    std.testing.refAllDecls(@This());
}
