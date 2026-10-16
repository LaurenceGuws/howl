# howl-instance

`howl-instance` is the batteries-included local terminal composition: one platform process-terminal transport (Linux PTY or Windows ConPTY), one canonical `howl-vt` terminal, ordered child I/O, explicit geometry, signals, and deterministic headless consequence policy. It is a module, not a daemon, listener, Session, or Server.

An embedder may use `howl-vt` directly and omit PTY/Instance composition entirely. Higher-level Session/Server orchestration is optional and must depend on Instance; Instance never depends on it.

The package exports two compile-time entry points. `howl_instance` keeps optional direct Render presentation; `howl_instance_headless` exposes only PTY/VT operations and imports no Render or Text module. Server selects the latter. Both select the same private lifetime and service implementation and retain the exact child-owned PTY/VT module identities. Their opaque Instance handles belong to the selected composition and cannot be exchanged. Neither entry point imports the optional VT codec.

## Presented text ownership

A presented Instance owns its canonical VT, atlas, commands and three immutable
publication slots. Its font/shaping choice is required in `PresentationConfig.text`:

| Choice | Font and shape owner | Terminal-local state |
| --- | --- | --- |
| `.shared = store` | One `PresentationStore` reused by compatible terminals | One atlas, command set and exchange per Instance |
| `.private = family` | A new native font family and Store for this Instance | The same terminal-local state |

Create a shared owner with `initPresentationStore(allocator, io, family, bounds)`,
then pass its pointer to matching `initPresented` and reconfiguration calls.
The family fixes paths/bytes, styles, fallbacks and physical pixel size. Store
bounds must match each borrower's shape/scratch configuration; mismatch fails
before canonical geometry or the old presentation changes. Use another owner
for a different font recipe or pixel size.

Each successful presented construction/reconfiguration retains one reference.
`releasePresentationStore` releases the embedding caller's reference; surviving
Instances keep the native faces alive. Release the caller reference exactly once
and stop using that pointer. The supplied Io must outlive the borrowers.
`presentationStoreReferences` lets an owner retire idle entries (one caller
reference, no Instance borrowers). There is no implicit global registry.

Only full text projection takes the native-face claim. Runtime contention returns
`PresentationBusy`; service PTY/VT normally and schedule a bounded retry.
Cursor-only updates and immutable frame transfer do not take this claim, and no
claim survives publication preparation. Ordinary synchronous construction/reconfiguration
may wait for a bounded projection. `tryInitPresented` instead claims shared fonts
before allocation or child launch and returns `PresentationBusy` for caller retry. A held frame or hidden observer cannot hold
shared text. The owner admits at most 1023 Instance borrowers.

Advanced Render embedders use `render.terminal.initStore` plus `initWithStore`
and serialize the borrowed native faces themselves. The convenience constructor
is deliberately named `initPrivate`. `resetStore` forgets shared shaping;
`resetCaches` resets only the caller's terminal atlas. Each pressure retry is
bounded independently, and one atlas does not flush the shared shape store.

## Direct API boundary

Instance exposes semantic operations and canonical observation. Server communications,
remote client identities, resize/consequence authority and wire codecs belong to the
optional Server implementation above this package.

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
only and may be waiting for reply space or paste completion. Both direct roots
select this same implementation. The existing foreign interface still exposes
atomic paste; this streaming API adds no C ABI or Server wire operation.

## Native foreign interface

The optional module-owned [native contract](docs/native.md) exposes Linux
unpresented and presented construction, caller-driven service, VT-owned copied
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
