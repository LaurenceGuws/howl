# Experimental optional VT output

This is an opt-in direct native-cell-to-command owner and the current experimental
`howl-app` presentation path. Plain `howl_vt` imports neither Text nor output.
`howl-app` composes its own PTY/VT/Text runtime and selects the optional VT-owned
output directly. The former Instance and Render packages are retired; historical
contracts remain available from Git history, not current build exports.

Canonical `Terminal.SemanticView` is a borrowed read-only query of the one VT
state, not a competing rendered output format. Selection, history, hyperlinks
and native cell queries still use it. Final command snapshots are a separately
selected optional VT/Text composition; plain VT allocates none of that output
state. `State(true/false)` selects test instrumentation only. There is no
comptime semantic-versus-rendered format switch to maintain or retire.

## Selection and identity

`howl-vt/build.zig:addOutputModules` takes the package LazyPath and the caller's
exact VT, Text, commands and limits module objects. It returns the opaque owner
and the one glyph-cache and internal text-support module objects. `howl-app`
selects the factory using its exact local modules; the workspace root selects
it separately for VT-owned output tests. A standalone VT + Text consumer can
select the same factory. Neither plain canonical VT nor the external native
consumer must select this optional output. Canonical VT dependencies do not change.

`commands.zig` owns final command/resource/rectangle vocabulary and stateless
validation. `limits.zig` is dependency-free. Direct output consumers use this
final vocabulary without an intermediate frame schema conversion.

## Ownership and limits

`owner.zig` exposes opaque Terminal, Config and one owner-bound Lease. The private
`state.zig` algorithm is instantiated without instrumentation for production;
`testing.zig` is an explicitly test-only build root, never a public module export.
The public owner admits 1..192 rows, 1..512 columns, history capacity bounded by u16, one numeric
view and one held output. Block-cursor ink is emitted as final clipped commands
following the cursor fill; it is not reconstructed by the consumer. Unsupported
visual scenes fail flush after canonical input commits. No Input/Renderer adapter
is used by the direct owner.

One producer owns canonical and working state. Feed can proceed before trying the
external transfer mutex. Flush and accepted-output pin/release/getters use that
mutex; immutable leased rows/pixels can be drawn outside it. Wrong-owner, stale
occurrence and duplicate leases reject before mutation. Release after drawing,
then quiesce before destruction. No queue, synchronization timer or PTY service
boundary is provided here.

The internal shared binding can instead borrow an existing canonical VT. Its
producer owns and serializes that VT and must outlive the output binding. The
configured history capacity and cell pixels must match the existing terminal;
external resizes are admitted at the next flush and do not mutate a held frame.
The app uses this binding directly, without a second canonical VT or
independent output scheduler.

Borrowed-font mode retains its original private shape cache/raster allocations and
bounded transient shape scratch. All supplied regular/bold/italic/bold-italic
FontSets remain borrowed: serialize native-face use across every borrower.

Shared mode retains the VT output owner's PresentationStore.
The internal `text_support.zig` owns one font family, refcount and Io mutex around
one Store lane (ShapeCache, clusters, shaped glyphs and raster scratch).
Neither public root exposes the support module, work borrow or claim helpers.
Shared output allocates only its local atlas and immutable output storage, not a
second shape cache or raster/shape scratch lane. Local atlases remain independent.
`resetShapes` provisionally rejects shared mode with `SharedStore`; private mode
really resets. A caller needing per-owner shared-cache reset cannot use this mode.
An explicit coordinated Store-wide reset would be a separate contract, not an
implicit neighbor mutation or a silent no-op.

`initShared` and `replaceWorkingShared` may wait during setup and must run outside
the output transfer mutex. Shared flush only tries the lane claim after no-op and
cursor-only row-reuse decisions; `PresentationBusy` preserves accepted output and
canonical input is never replayed. Replacement retains and stages before commit;
old local atlas destruction precedes releasing its old store reference. Io must
outlive all store references. Immutable held output borrows no mutable font data
and survives final store destruction. App configuration is app-owned; this owner
introduces no second scheduler, shared-store reset protocol or exchange.

## Proof ownership

`test/output_owner.zig` uses only the opaque default API through the standalone
VT + Text factory selected by the workspace root. The root also checks the
module identities and the app's separately constructed direct output.
`test/output_shared.zig` qualifies actual owning-store behavior; internal identity
checks prove one scratch lane rather than duplicated shape stores.
The retained workstream proofs qualify ordered native commands, real no-window
Canvas pixels, held output, failure/retry, font retirement and concurrent pinning.
Those remain bounded experimental evidence, not whole-app or GPU performance.
