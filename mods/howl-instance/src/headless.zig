//! One canonical PTY/VT owner without presentation dependencies.
const std = @import("std");
const runtime = @import("instance_runtime").Runtime(null);

/// Opaque handle to one canonical PTY + VT lifetime owner.
pub const Instance = runtime.Instance;
/// Canonical terminal engine type owned by one Instance.
pub const Terminal = runtime.Terminal;
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
/// Supplies one local shell launch and bounded canonical terminal geometry.
pub const Launch = runtime.Launch;
/// Reports construction failure before a instance becomes observable.
pub const InitError = runtime.InitError;
/// Reports terminal input encoding, signal, or bounded write admission failure.
pub const InputError = runtime.InputError;
/// Reports atomic PTY and VT geometry transition failure.
pub const ResizeError = runtime.ResizeError;
/// Reports PTY, VT, reply, or headless policy progress failure.
pub const ServiceError = runtime.ServiceError;
/// Summarizes one bounded service turn without exposing PTY or VT ownership.
pub const Service = runtime.Service;
/// Constructs one PTY and VT owner from an explicit inherited environment.
pub const init = runtime.init;
/// Stops the child, releases VT state, and destroys the opaque owner.
pub const deinit = runtime.deinit;
/// Returns the PTY descriptor for caller-owned poll integration.
pub const descriptor = runtime.descriptor;
/// True while a prior service turn retains child output in its bounded read buffer.
pub const bufferedOutputPending = runtime.bufferedOutputPending;
/// True while caller input or terminal replies are queued for the child PTY.
///
/// Poll owners include writable readiness whenever this is true; unlike the
/// previous Service result, this reflects input admitted since the last turn.
pub const writePending = runtime.writePending;
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
pub const input = runtime.input;
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
