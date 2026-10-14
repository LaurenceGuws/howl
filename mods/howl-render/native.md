# Optional standalone Render native owner

The existing `howl_render_native` Zig module remains the schema/projection leaf used by Instance and its clients. The separate `howl_render_owner_native` module owns a private Renderer, four optional canonical Text styles, one retained VT Reader and explicit reusable frame buffers. The `howl_render_native` static artifact exports nine C operations through `include/howl_render_native.h`. Parents forward the exact child-owned modules/artifact; consumers do not import private sources.

This first cut is native Linux/x86_64 using stable Zig 0.17.0 and the qualified matching build. The development compiler's static Text-link panic is closed for this graph. Link the archive and its exact VT companion into an executable or the embedder's own shared runtime shim. Maintained C/C++ consumers exercise both forms; the shared proof has no text relocations or Howl shared-library dependency. System FreeType/HarfBuzz remain link dependencies. No compiler substitution, app runtime or other target qualification is implied.

## Source lifetime

Open `hvt_observation` from a matching bare VT or C Instance, then pass it to `hrc_create`. Render retains one Reader; the caller may immediately release its original reference. A Reader grants no terminal mutation or retirement authority and retains no terminal state. The source owner may close while Render exists. Subsequent capture reports `HRC_SOURCE_CLOSED`; already captured frames remain CPU-readable. Render never makes source destruction busy.

Use headers and originating modules/libraries from the same qualified build. Keep those libraries loaded while their handles and leases live; arbitrary mixed-build handles and unloading with outstanding references are not supported.

## Frame lifecycle

One producer serializes create/open/capture/close/destruction and source mutation/destruction/capture. Open 1..64 explicit buffers within the configured ceiling. An open buffer pins its parent namespace even between leases. Parent destruction is busy until every buffer closes.

Capture targets an available buffer and publishes one immutable read lease only after all commands, records, pixels and metadata are copied. A leased buffer rejects capture/close as busy. Other buffers may capture newer source state; no source slice or canonical command scratch is retained by a frame. Backend read/release may run on a handed-off thread. Backend release publishes availability as its last buffer access; producer reuse acquires that publication. Never race read with release, or close with use.

Release ends the CPU lease. It acknowledges no GPU upload and is no GPU fence. Command/resource numbers belong to this one live Renderer occurrence. A backend must preserve resources needed by an unapplied frame, or discard/recapture it against current residency. Retire that namespace's backend objects after successful renderer destruction.

## Residency and failure

Every successful capture contains complete commands. Up to eight caller residency records describe actual backend truth for this owner. Exact identity/generation/format/extent suppresses upload; well-formed stale metadata requests replacement. Missing/failed uploads stay absent from the next supplied residency. Empty residency requests all required bytes. The private prospective set holds up to eight caller records plus seven missing external RGBA images. Replacement of one logical ID emits no contradictory same-ID removal.

Zero identity, unknown format, invalid extent/generation, reserved fields, duplicates and an identity above this owner's existing high-water mark are invalid. Numeric coincidence cannot identify another owner's resources; cross-owner mixing remains a caller violation. Every valid/aligned output, slot and input range must be disjoint, as specified by the header.

A failed capture publishes no lease and zeros its fixed C output. Other held frames remain unchanged. Private caches, revisions, bindings and bounded capacity may already have advanced; no full rollback is promised. Retry re-observes current source and current backend truth.

## Composition and bounds

Regular font input is required; other styles are optional and must have compatible canonical metrics. Path/memory inputs are copied by Text during construction; no discovery, reconfiguration, point sizing or shared Store is supplied. Cell size comes from the font. Capture never changes source geometry. Source pixel geometry and image scaling follow canonical VT/Render rules, including explicit failure for unknown source image geometry.

The header owns numeric ceilings and statuses. Canonical child limits are checked at compilation. Frame buffers retain only native commands, fixed upload/removal arrays, pixels and metadata; the Renderer has one shared canonical command scratch lane. Storage grows lazily within admitted command/pixel budgets and reuses capacity after release.

The owner contains no Instance/Server dependency, codec, socket, process, timer, worker, queue, GPU, window, publication exchange or host scheduling policy. Direct local and existing schema paths do not import it.

## Maintained proofs

Run `zig build check test -Doptimize=ReleaseSafe -j2` in this package. `test:owner` exercises injected allocation prefixes, source retirement, buffer lifetime, canonical command equivalence, exact/stale residency, held-frame independence, bounded capacity/retry and real backend-to-producer release handoff. `test:foreign` compiles and runs C11/C++17 against the child artifacts and installed headers, including copied font inputs and source closure. `test:static-embedding` runs the same C/C++ proof inside an embedder-owned shared library; the proof shim is not installed. The separate root consumer composes a C Instance source with Render without an upward production dependency. Complete default and ReleaseSafe root gates pass and include the structural isolation audit.

The full VT package Safe graph now passes on stable Zig 0.17.0 after its allocator-dependent fault numbering was corrected in the test campaign. No production encoder behavior changed. Platform qualification remains explicit.
