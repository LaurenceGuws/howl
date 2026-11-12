# Experimental optional VT output

This is an opt-in direct native-cell-to-command owner, not the current app path.
Plain `howl_vt` imports neither Text nor output. Existing Instance, Render, native C
and Odin APIs remain supported and unchanged.

## Selection and identity

`howl-vt/build.zig:addOutputModules` takes the package LazyPath and the caller's
exact VT, Text, commands and limits module objects. It returns the opaque owner
and the one glyph-cache and internal text-support module objects. Full Render selects
this factory once and uses the shared lane without importing the owner at runtime. Instance and the workspace
root forward that exact owner. A standalone VT + Text consumer uses the same
factory with no Render dependency. Dependency arguments for canonical VT do not
change. Limits-only Render returns before selecting Text or the factory.

`commands.zig` owns final command/resource/rectangle vocabulary and stateless
validation. `limits.zig` is dependency-free. Render's frame module remains the
owner of legacy Input, projection and CursorRows; its final types alias the
canonical vocabulary. There is no schema conversion at the direct consumer.

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
This is an internal integration seam, not an app cutover.

Borrowed-font mode retains its original private shape cache/raster allocations and
bounded transient shape scratch. All supplied regular/bold/italic/bold-italic
FontSets remain borrowed: serialize native-face use across every borrower.

Shared mode retains the exact owning PresentationStore also accepted by Instance.
The internal `text_support.zig` owns one font family, refcount and Io mutex around
one Store lane (ShapeCache, clusters, shaped glyphs and raster scratch). Render's
borrowed Store API aliases that same lane and remains externally serialized.
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
and survives final store destruction. This is no app configuration hook, new
scheduler, shared-store reset protocol or exchange retirement.

## Proof ownership

`test/output_owner.zig` uses only the opaque default API and runs through full
Render's check/test graph. It also runs through the standalone VT + Text factory
fixture. Root external consumers assert final type identity and execute the owner.
`test/output_shared.zig` qualifies actual owning-store behavior; internal identity
checks prove one scratch lane rather than duplicated shape stores.
The retained workstream proofs qualify ordered native commands, real no-window
Canvas pixels, held output, failure/retry, font retirement and concurrent pinning.
Those remain bounded experimental evidence, not whole-app or GPU performance.
