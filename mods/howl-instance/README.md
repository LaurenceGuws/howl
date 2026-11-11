# howl-instance

`howl-instance` has one composition: platform process-terminal transport (Linux
PTY or Windows ConPTY), canonical `howl-vt`, `howl-render`, and immutable frames
consumed by the embedder's GPU backend. Every Instance requires presentation
configuration and owns ordered child I/O, geometry, signals, renderer state and
publication storage. It is a module, not a daemon, listener, Session, or Server.

The sole `howl_instance` entry point constructs this path with
`init(allocator, environ, launch, presentation)` or nonwaiting `tryInit`.
Font metrics supply its canonical PTY/VT/Render cell lattice. The embedder owns
GPU residency, scheduling, windowing and display. A stalled or absent frame
consumer does not block canonical PTY/VT service.

An embedder that wants to compose terminal primitives itself uses `howl-vt` and
`howl-pty` directly. No alternate Instance composition or mutable terminal escape
hatch exists. Neither Instance nor its native interface imports a wire codec.

## Text ownership

An Instance owns its canonical VT, atlas, commands and three immutable
publication slots. Its font/shaping choice is required in `PresentationConfig.text`:

| Choice | Font and shape owner | Terminal-local state |
| --- | --- | --- |
| `.shared = store` | One `PresentationStore` reused by compatible terminals | One atlas, command set and exchange per Instance |
| `.private = family` | A new native font family and Store for this Instance | The same terminal-local state |

Create a shared owner with `initPresentationStore(allocator, io, family, bounds)`,
then pass its pointer to matching `init` and reconfiguration calls.
The family fixes paths/bytes, styles, fallbacks and physical pixel size. Store
bounds must match each borrower's shape/scratch configuration; mismatch fails
before canonical geometry or the old presentation changes. Use another owner
for a different font recipe or pixel size.

Each successful construction/reconfiguration retains one reference.
`releasePresentationStore` releases the embedding caller's reference; surviving
Instances keep the native faces alive. Release the caller reference exactly once
and stop using that pointer. The supplied Io must outlive the borrowers.
`presentationStoreReferences` lets an owner retire idle entries (one caller
reference, no Instance borrowers). There is no implicit global registry.

Only full text projection takes the native-face claim. Runtime contention returns
`PresentationBusy`; service PTY/VT normally and schedule a bounded retry.
Cursor-only updates and immutable frame transfer do not take this claim, and no
claim survives publication preparation. Ordinary synchronous construction/reconfiguration
may wait for a bounded projection. `tryInit` instead claims shared fonts
before allocation or child launch and returns `PresentationBusy` for caller retry. A held frame or hidden observer cannot hold
shared text. The owner admits at most 1023 Instance borrowers.

## Direct API boundary

Instance serializes semantic input, explicit geometry changes and canonical
consequence operations. The embedder schedules service, handles host consequences
and submits Render frames to its GPU backend. Session identity, orchestration,
networking and wire codecs belong outside this module.

## Retained rows

Render owns row-generation comparisons and their retained command/background
state. Instance forwards each selected VT observation without copying row
generations or manufacturing repair masks. Render checks the terminal occurrence,
screen bank, geometry and viewport before reuse, and invalidates failed work.

## Ordered large paste (direct Zig)

Use `beginPaste` only after acquiring and validating the payload. It snapshots
VT bracket mode and returns one nonreused `PasteToken`. `pasteChunk` copies a
whole chunk into the existing 64 KiB outbox or returns `WriteQueueFull` without
admitting a prefix. Limit each chunk to `maximum_paste_chunk_bytes`; larger
chunks return the permanent `PasteChunkTooLarge` error. There is no whole-paste
allocation, retained payload borrow, or total-payload limit inside Instance.

Only the first chunk opens the VT-owned framing. A final chunk closes it and
retires the token. Empty final completion matches ordinary VT paste encoding.
`cancelPaste` closes any admitted prefix using reserved outbox capacity and
retires the token without allocation. Cancellation cannot recall admitted bytes
or promise their delivery after transport failure. Destroying Instance closes
the whole process-terminal. Calls on one Instance remain caller-serialized.

During the operation, ordinary `input` returns `WriteQueueFull` before encoding.
Generated replies stay behind paste at the next VT reply-producing service
boundary, retaining the bounded unread suffix. Plain output can still advance;
a child whose input/output dependencies prevent progress applies normal
backpressure. The paste owner must continue submitting prepared chunks or cancel;
do not hold this lane while waiting for a clipboard producer or user decision.
Explicit signals and geometry remain separately available.

Poll writable readiness while `writePending`. Use `bufferedOutputRunnable` to
schedule immediate buffered output: `bufferedOutputPending` reports storage
only and may be waiting for reply space or paste completion. The foreign
interface exposes atomic paste; streaming adds no C ABI or wire operation.

## Native foreign interface

The optional module-owned [native contract](docs/native.md) exposes Linux
construction with required presentation, caller-driven service, VT-owned copied
queries/requests, and immutable frame leases. Explicit presentation owners copy
path or memory fonts and can be shared across Instances; caller release leaves
Instance references alive. Zig hosts can reuse the exact native contract helpers
without emitting or calling through C exports.

The static native archive and its exact VT companion can link into a caller-owned
executable or shared runtime shim; scheduling and application runtime stay with
the embedder. Linux/x86_64 C/C++ consumers qualify both forms.

On Linux, `Launch.arguments` supplies literal arguments (excluding argv[0]) for
`Launch.shell` as a direct executable. It is mutually exclusive with `command`;
no `-i` or `-c` is added. PTY owns the copied pre-fork argument snapshot and
uses the same launch handshake, I/O, signals and cleanup as the shell path.
Other platforms reject this optional launch mode with `UnsupportedPlatform`.
