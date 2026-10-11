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
claim survives publication preparation. Synchronous construction/reconfiguration
may wait for a bounded projection. A held frame or hidden observer cannot hold
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
