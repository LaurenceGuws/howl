# Term Embedding Surface Sprint

## Goal

Make `howl-term` boring and intuitive as the end-user embedding package, with `howl-linux-host` proving the current public dependency/export structure while ownership boundaries are made pristine.

This sprint is not about adding new runtime behavior. It is about making the already working SDL/Linux path depend on a mature `howl-term` public surface instead of a broad grab bag of nested `HowlTerm.*` contracts and host-shaped methods. Android is parked until ownership boundaries are pristine; Android runtime proof remains open until real Android code proves it.

Ownership priority while boundaries are unclear:

- Embed intuitiveness follows `utils/dev_references/terminals/ghostty` first.
- Raw speed, efficiency, and rendering quality follow `utils/dev_references/terminals/alacritty` second.
- When those point in different directions, keep the embed boundary intuitive and move hot-path internals only when the owner is unambiguous.

## Ghostty Reference Shape

Use these Ghostty files as the comparison baseline:

- `utils/dev_references/terminals/ghostty/src/lib_vt.zig`: public VT root curates only ready API from `terminal/main.zig`; it deliberately withholds internal pieces.
- `utils/dev_references/terminals/ghostty/src/terminal/main.zig`: namespace wrapper aggregates owner modules and exposes selected types; it owns no behavior.
- `utils/dev_references/terminals/ghostty/src/main_c.zig`: embedding C API entrypoint for libghostty; global/embed lifecycle and C ABI glue live here rather than in terminal internals.
- `utils/dev_references/terminals/ghostty/src/apprt.zig`: application runtime selector; the host/runtime boundary is explicit.
- `utils/dev_references/terminals/ghostty/src/App.zig`: core app owner used by runtimes; public methods are lifecycle/event surface, not lower-module internals.
- `utils/dev_references/terminals/ghostty/src/Surface.zig`: terminal widget/surface owner; owns terminal I/O, renderer state, input callbacks, draw/size/focus, and runtime surface linkage.
- `utils/dev_references/terminals/ghostty/src/termio.zig`: terminal I/O namespace; exports `Termio`, `Thread`, backend, mailbox, and messages as a clear domain.
- `utils/dev_references/terminals/ghostty/src/renderer.zig`: renderer namespace; exports selected renderer runtime, thread, state, geometry/size contracts.

The important pattern is not the exact names. The pattern is that public roots and namespace files are catalogs, while app/surface/termio/renderer owners mature below them and are consumed through explicit dependency boundaries.

## Current Howl Structure

Current public/export route:

- `howl-term/src/howl_term.zig` is a catalog root with `HowlTerm`, `Input`, `Ffi`, and grouped `runtime`, `surface`, `viewport` aliases.
- `howl-term/src/term_namespace.zig` is the namespace wrapper and gates `c_api` on `options.c_abi`.
- `howl-term/src/terminal.zig` remains the broad public `HowlTerm` state container and method table.
- `howl-term/src/ffi.zig` remains the broad `howl_term_*` ABI catalog with stable extern structs and handle conversion.
- `howl-hosts/howl-linux-host/src/terminal/terminal.zig` consumes only the `howl_term` package root, which is correct, but it still reaches through nested `HowlTerm.*` type aliases and a large method table.
- `howl-hosts/howl-linux-host/src/terminal/thread.zig` owns host terminal child thread entrypoints.

Known good boundary:

- Linux host does not import `vt_core`, `howl_session`, `howl_render`, or lower private owner paths.
- `howl-term` imports lower modules and owns orchestration.
- FFI files do not import public roots.

Known immature boundary:

- `HowlTerm` is still the only convenient Zig embed type, so all host-facing contracts hang off `HowlTerm.*` or methods on that type.
- Root groups exist but are thin aliases; Linux host does not yet consume them consistently.
- `ffi.zig` still mixes ABI catalog, handle conversion, lifecycle setup, frame control, and compatibility render entrypoints.
- `terminal.zig` is becoming a facade, but checks do not yet prevent new behavior from accumulating there.

## Non-Negotiable Rules

- Hosts consume `howl-term` only.
- `howl-term` may consume session/render/VT roots; hosts may not.
- Public roots and namespace wrappers stay catalogs.
- No fake Android parity. Android proof closes only with real Android runtime code.
- No ABI churn unless explicitly marked as an ABI-changing checkpoint.
- Preserve all existing `howl_term_*` symbol names and extern struct fields, especially `FfiPrepareMetrics.term_us`.
- `terminal.zig` may keep the public method table, but behavior must move below it when an owner boundary is clear.
- `ffi.zig` may keep exported ABI names, handle conversion, and extern ABI structs, but C ABI behavior must move below it by domain.

## Target Shape

`howl-term` root surface should read like a small embed API catalog:

- `HowlTerm`: primary Zig runtime handle and stable method table.
- `Input`: VT input vocabulary pass-through.
- `Ffi`: C ABI namespace.
- `runtime`: lifecycle and frame request/result contracts.
- `surface`: surface handle/state/metrics contracts.
- `viewport`: scrollback, selection, link-hover contracts.
- `diagnostics`: renderer/runtime counters and proof readouts if they remain public.
- `config`: font/config mutation contracts if they become public enough to group.

Linux host should become the living embed proof:

- Import only `howl_term` root.
- Prefer root groups for contracts, e.g. `howl_term.surface.State`, `howl_term.runtime.FramePixels`, instead of `HowlTerm.SurfaceState` where practical.
- Keep host-owned UX/runtime code under `howl-linux-host`; do not push host concepts down into `howl-term`.
- Keep host thread loops in host `thread.zig`; keep terminal runtime thread in `howl-term/src/runtime/thread.zig`.

## Sprint 0: Export And Dependency Inventory

Purpose: make the current dependency/export shape explicit before moving more code.

Tasks:

- Inventory every `howl-term` public root export and group it as runtime, input, FFI, surface, viewport, diagnostics, config, or internal leak.
- Inventory every `HowlTerm.*` nested type consumed by Linux host.
- Inventory every `HowlTerm` method consumed by Linux host and classify as embed-stable, host-only, diagnostics, or internal leak.
- Inventory every `howl_term_*` ABI function by domain and current `c_api/*` owner.
- Record which Ghostty reference file most closely matches each Howl owner boundary.

Acceptance:

- This document has the inventory table filled in before implementation checkpoints continue.
- No code movement happens in this checkpoint except checks/docs needed to expose the inventory.

Initial inventory seed:

| Area | Current Howl surface | Linux host use | Ghostty comparison | Initial decision |
| --- | --- | --- | --- | --- |
| Root catalog | `howl_term.zig` exports `HowlTerm`, `Input`, `Ffi`, `runtime`, `surface`, `viewport` | host imports `howl_term` root only | `lib_vt.zig` | Keep root catalog; mature groups. |
| Namespace wrapper | `term_namespace.zig` aggregates terminal and `c_api` | indirect only | `terminal/main.zig` | Keep declarative. |
| Runtime handle | `HowlTerm` in `terminal.zig` | `Terminal.term: HowlTerm` | `Surface.zig` core surface owns terminal IO/render state | Keep as embed handle; make facade boring. |
| Runtime contracts | `HowlTerm.LifecycleState`, `FramePixels` and root `runtime` aliases | lifecycle and geometry | `App.zig`, `Surface.zig` callbacks/contracts | Move host to root groups where practical. |
| Surface contracts | `HowlTerm.SurfaceHandle`, `SurfaceState`, `SurfaceMetrics` and root `surface` aliases | presentation and metrics | `Surface.zig`, `apprt/surface.zig` | Mature root `surface` group. |
| Viewport contracts | `HowlTerm.ScrollState`, `LinkUnderlineStyle` and root `viewport` aliases | scrollbar, link hover, selection | `Surface.zig`, `terminal/main.zig` | Mature root `viewport` group. |
| Input vocabulary | `Input` pass-through from VT | host input conversion | `lib_vt.zig` `input` group | Keep pass-through; do not duplicate. |
| C ABI | `Ffi` and root-gated exports | native ABI build | `main_c.zig`, `lib_vt.zig` export block | Keep route; split behavior by ABI domain. |
| Host terminal widget | `howl-linux-host/src/terminal/terminal.zig` | SDL/Linux only | Ghostty `Surface.zig` plus apprt runtime | Keep host UX out of `howl-term`. |

Concrete root exports:

| Export | Current source | Area | Linux host use | Decision |
| --- | --- | --- | --- | --- |
| `HowlTerm` | `term_namespace.zig` alias to `terminal.HowlTerm` | runtime handle | Stored as `Terminal.term` and used as method receiver | Keep as primary embed handle. |
| `Input` | `term_namespace.zig` alias to VT input vocabulary | input | `terminal/input.zig` maps SDL input to `term.Input` | Keep pass-through; no duplication in host. |
| `Ffi` | `term_namespace.zig` `c_api` alias | C ABI | Native ABI build/export route | Keep as explicit ABI namespace. |
| `runtime` | root group alias | runtime contracts | not yet consumed by Linux host | Mature in Sprint 1. |
| `surface` | root group alias | surface contracts | not yet consumed by Linux host | Mature in Sprint 1. |
| `viewport` | root group alias | viewport contracts | not yet consumed by Linux host | Mature in Sprint 1. |

Linux host nested `HowlTerm.*` type consumption:

| Current use | File | Area | Preferred public group | Decision |
| --- | --- | --- | --- | --- |
| `HowlTerm.LifecycleState` | `terminal/terminal.zig` | runtime state | `howl_term.runtime.LifecycleState` | Move in Sprint 1. |
| `HowlTerm.FramePixels` | `terminal/terminal.zig` | runtime geometry | `howl_term.runtime.FramePixels` | Move in Sprint 1. |
| `HowlTerm.SurfaceHandle` | `terminal/terminal.zig` | surface presentation | `howl_term.surface.Handle` | Move in Sprint 1. |
| `HowlTerm.SurfaceMetrics` | `terminal/terminal.zig` | surface diagnostics | `howl_term.surface.Metrics` | Move in Sprint 1 if still needed. |
| `HowlTerm.SurfaceState` | `terminal/terminal.zig` | surface presentation | `howl_term.surface.State` | Move in Sprint 1. |
| `HowlTerm.ScrollState` | `terminal/terminal.zig` | viewport/scrollbar | `howl_term.viewport.ScrollState` | Move in Sprint 1. |
| `HowlTerm.LinkUnderlineStyle` | `terminal/terminal.zig` | viewport/link hover | `howl_term.viewport.LinkUnderlineStyle` | Move in Sprint 1. |

Linux host `HowlTerm` method consumption:

| Method group | Methods used by Linux host | Classification | Ghostty comparison | Decision |
| --- | --- | --- | --- | --- |
| Lifecycle | `initPty`, `start`, `deinit`, `isAlive` | embed-stable | `Surface.zig` owns terminal session lifecycle below app runtime | Keep methods; make lifecycle owner underneath boring. |
| Host config | `setFontSizePx`, `setPrimaryFontPath`, `setFallbackFontPaths` | embed-stable config | `Surface.zig` owns derived config/font state; `renderer.zig` owns renderer contracts | Keep methods for now; consider root `config` group only after host contract settles. |
| Frame geometry | `syncFrameGeometry`, `FramePixels.renderWidth`, `FramePixels.renderHeight`, `FramePixels.gridWidth`, `FramePixels.gridHeight` | embed-stable frame contract | `Surface.zig` size callbacks; `renderer.zig` size contracts | Keep; move type use to `runtime.FramePixels`. |
| Frame loop | `needsFrame`, `needsPrepare`, `prepareNextFrame`, `renderReadyFrame`, `awaitRenderWake`, `wakeSnapshotWaiters` | embed-stable but still broad | Ghostty renderer/termio threads are explicit domain owners | Keep methods while owners mature; `wakeSnapshotWaiters` is deinit-specific and should be reviewed before platform parity work. |
| Surface readout | `surfaceState`, `renderedSnapshotSeq` | embed-stable surface/pacing | `Surface.zig` draw/state and `apprt/surface.zig` messages | Keep methods; move type use to `surface.State`. |
| Host pacing diagnostics | `hasQueuedRenderWork`, `setRuntimeBackpressure` | host scheduling contract | Ghostty renderer thread/mailbox owns render pressure | Keep for Linux proof; decide whether public diagnostics or runtime contract before platform parity work. |
| Input | `publishInputBytes`, `publishInputKey`, `publishMouseEvent`, `publishPaste`, `setInputFocus` | embed-stable input | Ghostty `Surface.zig` input callbacks and `lib_vt.zig` input group | Keep methods; input vocabulary remains root `Input`. |
| Viewport/scrollbar | `scrollState`, `followLiveBottom`, `setScrollbackOffset` | embed-stable viewport | Ghostty `Surface.zig` scrollbar and viewport behavior | Keep methods; move type use to `viewport.ScrollState`. |
| Selection/link | `selectionInProgress`, `beginSelection`, `updateSelection`, `finishSelection`, `setHoveredLinkAtPixel`, `copyHyperlinkUriAtPixel` | host interaction contract | Ghostty `Surface.zig` mouse/selection/link handling | Keep methods; move link type use to `viewport.LinkUnderlineStyle`. |
| Clipboard/title | `drainPendingClipboardSet`, `copyCurrentTitle` | host UX contract | Ghostty `apprt/surface.zig` clipboard/title messages | Keep methods; consider host effect grouping later. |
| Text diagnostics | `renderedTextContains` | diagnostics/test convenience | Ghostty debug/test surfaces, not core app contract | Keep for now; classify under future `diagnostics` before platform parity work. |

Current ABI domain inventory:

| ABI domain | `howl_term_*` functions | Current implementation owner | Gap |
| --- | --- | --- | --- |
| Handle/lifecycle | `create`, `create_with_start_path`, `destroy` | `c_api/lifecycle.zig` | Owned; handle conversion and `TermHandle` remain in `ffi.zig`. |
| Frame loop/geometry | `has_queued_render_work`, `needs_frame`, `needs_prepare`, `prepare_next_frame`, `render_ready_frame`, `await_render_wake`, `sync_frame_geometry`, `set_runtime_backpressure`, `wake_snapshot_waiters`, `render_frame`, `render_latest_snapshot`, `render_frame_sized`, `await_snapshot_event` | `c_api/frame.zig` | Owned; `FfiFramePixels` ABI layout remains in `ffi.zig`. |
| Metrics/diagnostics | `take_prepare_metrics`, `take_surface_metrics`, `render_missing_glyphs`, `render_fallback_hits`, `render_fallback_misses`, `render_shaped_clusters`, `render_resolve_stage`, `last_render_metrics` | `c_api/metrics.zig` | Mostly owned; keep ABI struct layout in `ffi.zig`. |
| Surface/status/title/sequences | `surface_state`, `has_output_proof`, `surface_texture_id`, `surface_width`, `surface_height`, `surface_epoch`, `is_session_alive`, `input_bytes_applied`, `snapshot_event_seq`, `rendered_snapshot_seq`, `copy_current_title` | `c_api/surface.zig` | Mostly owned; `surface_state` fallback value remains in `ffi.zig`. |
| Input | `publish_input_bytes`, `publish_input_key`, `set_input_focus`, `publish_paste`, `publish_mouse_event`, `publish_control_signal` | `c_api/input.zig` | Owned. |
| Font/config | `set_font_size_px`, `set_primary_font_path`, `clear_fallback_font_paths`, `add_fallback_font_path` | `c_api/font.zig` | Owned; may become `config` only if scope grows. |
| Viewport/selection/link/text | `scroll_state`, `current_scrollback_count`, `current_scrollback_offset`, `set_scrollback_offset`, `follow_live_bottom`, `viewport_rows`, `is_alternate_screen`, `rendered_text_contains`, `visible_text_contains`, `selection_in_progress`, `begin_selection`, `update_selection`, `finish_selection`, `clear_selection`, `set_hovered_link_at_pixel`, `copy_hyperlink_uri_at_pixel`, `drain_pending_clipboard_set` | `c_api/viewport.zig` | Owned. |
| Input constants | `mod_*`, `key_*`, `mouse_*` | `c_api/constants.zig` | Owned. |

Ghostty boundary map for this sprint:

| Howl file | Role in this sprint | Ghostty reference | Comparison result |
| --- | --- | --- | --- |
| `howl-term/src/howl_term.zig` | public catalog and C export route | `lib_vt.zig` | Shape is close; groups need to become useful to hosts. |
| `howl-term/src/term_namespace.zig` | namespace wrapper | `terminal/main.zig` | Shape is close; keep declarative. |
| `howl-term/src/terminal.zig` | runtime handle/state/method facade | `Surface.zig` | Same embed importance, but Howl needs more owner maturity below it before it feels like an easy embed API. |
| `howl-term/src/runtime/thread.zig` | terminal runtime child thread | `termio/Thread.zig`, `renderer/Thread.zig` | Naming is aligned; ownership should stay domain-local. |
| `howl-term/src/ffi.zig` | C ABI catalog | `main_c.zig`, `lib_vt.zig` export block | Route is aligned; behavior split is incomplete. |
| `howl-hosts/howl-linux-host/src/terminal/terminal.zig` | SDL host terminal widget | `Surface.zig`, `apprt/gtk/Surface.zig` | Correctly host-owned; should prove public root groups. |
| `howl-hosts/howl-linux-host/src/terminal/thread.zig` | SDL host child thread loops | `renderer/Thread.zig`, `terminal/search/Thread.zig` | Naming is aligned; remains host-owned. |

Sprint 0 open findings:

- Linux host already has the correct package dependency boundary, but its type vocabulary still leans on `HowlTerm.*` instead of root groups.
- `terminal.zig` is mostly delegating methods now, but still exposes several compatibility/internal-looking methods to all embedders.
- `ffi.zig` route is correct, but lifecycle/frame/geometry and `scroll_state` conversion are not yet delegated to domain owners.
- There is not enough evidence yet to mark `diagnostics` or `config` root groups stable; they should remain future decisions until host and ABI needs are clearer.

## Sprint 1: Linux Host Uses The Public Groups

Purpose: make the existing SDL host prove the intended embed surface rather than reaching through nested runtime implementation aliases.

Tasks:

- Update Linux host type imports to prefer `howl_term.runtime`, `howl_term.surface`, and `howl_term.viewport` groups.
- Keep `HowlTerm` as the value type/handle, not as a bucket for every public contract.
- Add shape checks that forbid new lower-module imports from Linux host and require grouped contract use where practical.
- Avoid churn when a method naturally belongs on the runtime handle.

Acceptance:

- Linux host still imports only `howl_term` root for terminal core behavior.
- Linux host builds/tests pass.
- Parent checks enforce no lower-module imports and no private owner path imports.

Checkpoint 1 target:

- Move Linux host type aliases from nested `HowlTerm.*` contracts to root groups: `howl_term.runtime`, `howl_term.surface`, and `howl_term.viewport`.
- Do not change behavior or method calls in this checkpoint.
- Add a parent shape check that prevents those nested type aliases from returning.

Checkpoint 2 target:

- Keep Linux host input mapping on the package root as `howl_term.Input`, matching the visible embed package name.
- Do not duplicate VT input vocabulary or import lower VT modules.

Sprint 1 evidence:

- `howl-hosts/howl-linux-host/src/terminal/terminal.zig` imports `howl_term` root and keeps `HowlTerm` only as the runtime handle.
- Linux host terminal contract types come from `howl_term.runtime`, `howl_term.surface`, and `howl_term.viewport`.
- `howl-hosts/howl-linux-host/src/terminal/input.zig` maps host input through `howl_term.Input`.
- Parent checks reject lower-module host imports and reject nested `HowlTerm.*` runtime/surface/viewport contract aliases in the terminal widget.
- Parent checks require the host input mapper to stay on `howl_term.Input`.

Sprint 1 handoff state:

- Host dependency/export proof is sufficient to start Sprint 2.
- The full embedding sprint remains open: `terminal.zig` and `ffi.zig` still need facade/catalog maturity work.
- Platform parity remains blocked on real runtime proof, not on this host dependency/export checkpoint.

## Sprint 2: `terminal.zig` Facade Maturity

Purpose: reduce `terminal.zig` to a stable method table over mature owners.

Tasks:

- Audit each remaining non-trivial method body in `terminal.zig`.
- Move behavior only to the smallest clear owner: lifecycle, runtime query, input, frame, geometry, viewport, wake, config, diagnostics.
- Keep public method names stable unless the host and FFI are updated in the same checkpoint.
- Add checks that stop `terminal.zig` from importing lower-module private files directly where an owner already exists.

Acceptance:

- `terminal.zig` mostly contains state fields, public type aliases, and one-line delegating methods.
- No behavior moves upward into the root or namespace wrapper.
- SDL/Linux proof remains green.

Sprint 2 audit checkpoint 1:

Terminal facade classification:

| Classification | Current methods | Owner decision |
| --- | --- | --- |
| Stable lifecycle delegates | `init`, `initPty`, `deinit`, `start`, `stop`, `isAlive`, `hasOutputProof` | Keep on `HowlTerm`; behavior stays in `runtime/lifecycle.zig` and `runtime/query.zig`. |
| Stable input delegates | `publishInputBytes`, `input`, `publishInputKey`, `setInputFocus`, `publishPaste`, `publishMouseEvent`, `publishControlSignal` | Keep on `HowlTerm`; behavior stays in `input/input.zig`; input vocabulary remains `howl_term.Input`. |
| Stable viewport/selection delegates | `scrollState`, `currentScrollbackCount`, `currentScrollbackOffset`, `viewportRows`, `isAlternateScreen`, `setScrollbackOffset`, `followLiveBottom`, `selectionInProgress`, `beginSelection`, `updateSelection`, `finishSelection`, `clearSelection`, `setHoveredLinkAtPixel`, `copyHyperlinkUriAtPixel` | Keep on `HowlTerm`; behavior stays in `render/viewport.zig` and query readouts. |
| Stable surface/frame-loop delegates | `prepareNextFrame`, `renderReadyFrame`, `awaitRenderWake`, `awaitRenderWakeTimeout`, `needsFrame`, `needsPrepare`, `hasQueuedRenderWork`, `surfaceState`, `renderedSnapshotSeq`, `snapshotEventSeq`, `setRuntimeBackpressure`, `wakeSnapshotWaiters` | Keep on `HowlTerm`; behavior stays in `render/frame.zig`, `runtime/query.zig`, and `wake/wake.zig`. |
| Config delegates | `setPrimaryFontPath`, `setFontSizePx`, `setFallbackFontPaths`, `clearFallbackFontPaths`, `addFallbackFontPath` | Keep on `HowlTerm`; behavior stays in `config/fonts.zig`; do not add a public `config` group until the contract grows beyond font setup. |
| Diagnostics delegates | `takePrepareMetrics`, `takeSurfaceMetrics`, `lastRenderMetrics`, `renderMissingGlyphs`, `renderFallbackHits`, `renderFallbackMisses`, `renderShapedClusters`, `renderResolveStage`, `inputBytesApplied`, `renderedTextContains`, `visibleTextContains`, `copyCurrentTitle` | Keep for Linux and ABI proof; classify under future `diagnostics` only after runtime proof shows the same need. |
| Compatibility/internal render delegates | `renderFrame`, `renderLatestSnapshot`, `prepareLatestSnapshot`, `prepareSnapshotForRequest`, `prepareSnapshotForRequestIfDirty`, `submitPreparedSnapshot`, `renderFrameSized`, `syncSnapshotFromCore`, `syncFrameGeometry`, `snapshotToken`, `lastSubmittedFrame`, `shiftSelectionForHistoryGrowth` | Keep ABI-compatible methods for now, but treat as the main public-surface leak. Next code checkpoints should reduce direct public dependence where consumers are internal and move pure renderer-facing storage/model code to `howl-render-core`. |

Render ownership audit:

| File | Current role | Render-core fit | Sprint 2 decision |
| --- | --- | --- | --- |
| `howl-term/src/render/render.zig` | Coordinates term snapshot sync, geometry derivation, renderer prepare/submit, metrics, lifecycle-facing error mapping, wake completion, and submitted-frame bookkeeping. | Poor as-is because it depends on `HowlTerm`, VT/session-derived snapshot state, wake events, scrollback overlays, and term lifecycle errors. | Keep term-owned; future movement should first extract pure contracts, not move orchestration. |
| `howl-term/src/render/sync.zig` | Projects VT visible view, selection, cursor, dirty rows, scrollback, alternate-screen state, and link metadata into render snapshots. | Partial only for tiny conversion pieces; most logic depends on VT and term interaction state. | Keep term-owned; do not move to render-core in this sprint. |
| `howl-term/src/render/snapshot.zig` | Stores renderer-facing cells, cursor, dirty rows, damage, scroll offset, and exposes `SurfaceFrameData`. | Strong fit: no VT/session dependency and all stored types are already render-core surface types. | Move to `howl-render-core` as reusable frame snapshot storage. |
| `howl-term/src/render/pipeline.zig` | Defines snapshot tokens, retained-frame validation, latest-wins mailbox, and prepare/submit result contracts. | Strong fit: no VT/session/runtime dependency; this is reusable retained-frame scheduling. | Move to `howl-render-core` as frame pipeline contracts. |
| `howl-term/src/render/queue.zig` | Owns host-embeddable terminal frame scheduling, visibility, retained-target policy, prepared slot, and surface metrics. | Strong fit: no VT/session/runtime dependency; this is reusable render queue policy. | Move to `howl-render-core` as frame queue policy. |
| `howl-render-core/src/surface.zig` | Defines shared render surface data model: cells, colors, cursor, damage, viewport, frame data. | Correct owner for backend-agnostic frame data contracts. | Keep render-core-owned; term snapshots should continue producing this model. |
| `howl-render-core/src/frame_input.zig` | Converts terminal-like frame data into text scene input and applies renderer themes/damage mapping. | Correct owner for renderer/model conversion. | Keep render-core-owned; do not pull VT/session logic into it. |
| `howl-render-core/src/render_core.zig` | Public render-core orchestration catalog for geometry, surface types, text conversion, and renderer contracts. | Correct owner for reusable renderer entrypoints. | Keep as render-core boundary; term should call it through selected public APIs only. |

Audit conclusion:

- `terminal.zig` already satisfies most of the facade shape mechanically: public methods are one-line delegates except for the trivial `awaitRenderWake` timeout wrapper.
- The main maturity gap is public surface breadth: compatibility render methods and internal snapshot methods are visible on `HowlTerm` because FFI, tests, and term-owned modules still use them through the public method table.
- Most render orchestration does not belong in `howl-render-core` yet. Current frame prepare/submit flow is terminal orchestration, but pure renderer-facing snapshot storage belongs in render-core.
- The first safe implementation checkpoint introduced a term-owned frame domain route for FFI frame/geometry functions, with `ffi.zig` still preserving all `howl_term_*` ABI names and structs.
- A later checkpoint can reduce internal callers that go through `HowlTerm` public methods, but only after the remaining ABI catalog domains are clear and checked.

## Sprint 3: `ffi.zig` ABI Catalog Maturity

Purpose: make `ffi.zig` read like ABI declarations and delegation, not a behavior owner.

Tasks:

- Split remaining ABI behavior into domain owners only when boundaries are clear:
  - `c_api/lifecycle.zig` for create/destroy/start-path construction helpers.
  - `c_api/frame.zig` for frame prepare/render/wake/geometry ABI conversion.
  - `c_api/config.zig` if font/config behavior outgrows `font.zig`.
  - `c_api/diagnostics.zig` if metrics/surface split is not enough.
- Keep `ffi.zig` owning `TermHandle`, handle conversion, exported ABI function names, and extern ABI structs unless a deliberate ABI layout checkpoint says otherwise.
- Preserve all symbol names and return codes.

Acceptance:

- `zig build ffi:build` passes in `howl-term`.
- Parent checks require the new `c_api/*` owners and reject direct behavior calls from `ffi.zig` where a domain owner exists.
- ABI names and fields remain unchanged.

Sprint 3 checkpoint 1 evidence:

- `howl-term/src/c_api/frame.zig` owns C ABI frame-loop, wake, geometry, backpressure, and compatibility render return-code behavior.
- `howl-term/src/ffi.zig` keeps the exported `howl_term_*` function names and extern ABI structs, but delegates frame behavior through `c_api/frame.zig`.
- Parent shape checks now require `c_api/frame.zig` and reject direct frame/geometry behavior calls from `ffi.zig` once that owner exists.
- `FfiFramePixels`, `FfiSnapshotWake`, and all existing frame-related exported symbol names are unchanged.

Sprint 3 checkpoint 2 evidence:

- `howl-term/src/c_api/lifecycle.zig` owns C allocator runtime setup, startup, initial geometry sync, and teardown.
- `howl-term/src/ffi.zig` keeps `TermHandle`, handle conversion, exported lifecycle symbol names, and ABI pointer slicing, but no longer owns lifecycle behavior.
- `howl-term/src/c_api/viewport.zig` now owns `scroll_state` ABI conversion, closing the last known viewport inline conversion in `ffi.zig`.
- Parent shape checks now require `c_api/lifecycle.zig` and reject direct lifecycle and scroll-state behavior calls from `ffi.zig`.

Sprint 3 checkpoint 3 evidence:

- `howl-term/src/c_api/viewport.zig` owns link-hover ABI result conversion.
- `howl-term/src/ffi.zig` no longer carries local boolean conversion behavior; it delegates link-hover output shaping to the viewport ABI owner.
- Parent shape checks reject local `boolInt` conversion helpers in `ffi.zig`.

## Sprint 4: Minimal Embed Proof Surface

Purpose: prove the public embedding API without assuming SDL-specific host behavior.

Tasks:

- Add or identify a minimal non-SDL Zig embed proof inside `howl-term` tests/benchmarks that creates a term, drives input/geometry, observes wake/frame/surface state, and tears down cleanly.
- Keep it backend-agnostic and deterministic.
- Do not fake platform parity; this proof only validates package-level embed shape.

Acceptance:

- `howl-term` has a repeatable embed-shape proof below SDL.
- Linux host remains the visible runtime proof.
- Platform parity remains explicitly open unless real runtime code is restored.

Sprint 4 checkpoint 1 evidence:

- `howl-term/src/test/root.zig` includes `package root supports minimal non-SDL embedding flow`.
- The proof constructs `root.HowlTerm` through the public package root, uses `root.runtime.FramePixels`, drives input and focus, syncs geometry, observes wake publication, prepares/renders one frame, observes surface dimensions and rendered sequence, then tears down.
- This is a package-level embed proof only. SDL/Linux remains the visible runtime proof and platform parity remains explicitly open.

## Parked Android Gate

Purpose: document why Android is not active while ownership boundaries are still being cleaned up.

Android is parked until ownership boundaries are pristine. The notes below prevent fake parity from creeping in, but they are not the next implementation target.

Parked gate:

- `howl-hosts/howl-android-host/src/main/java/howl/term/Terminal.java` is absent.
- `tools/check_host_runtime_surface.sh` therefore reports `host_runtime_surface_skip=missing_android_runtime` and exits successfully without faking proof.
- No Android dependency/export boundary is being closed by this sprint. Android parity remains open until real runtime code exists.

## Sprint 5: Render Boundary Pristine Pass

Purpose: reduce rendering ownership in `howl-term` to terminal orchestration only.

Tasks:

- Move pure renderer-facing frame storage into `howl-render-core` when it has no VT/session/runtime dependency.
- Move pure retained-frame pipeline and queue mechanics into `howl-render-core` when they have no VT/session/runtime dependency.
- Keep VT visible-view projection, selection, scrollback policy, wake events, and frame prepare/submit orchestration in `howl-term`.
- Enforce that pure render-core owners do not return under `howl-term/src/render`.
- Use Ghostty as the primary embed-boundary reference and Alacritty as the rendering quality/speed reference.

Acceptance:

- `howl-render-core` owns reusable frame snapshot storage through `Core.FrameSnapshot`.
- `howl-render-core` owns reusable frame pipeline and queue mechanics through `Core.FramePipeline` and `Core.FrameQueue`.
- `howl-term` keeps `sync.zig`, `render.zig`, and `frame.zig` as term-owned orchestration unless a later boundary is unambiguous.
- Parent checks require the render-core snapshot/pipeline/queue owners and reject the old term-owned pure render files.

Sprint 5 checkpoint 1 evidence:

- `howl-render-core/src/frame_snapshot.zig` owns render-frame snapshot storage, dirty metadata, partial-copy scroll reuse, and `SurfaceFrameData` projection.
- `howl-render-core/src/render_core.zig` exposes `Core.FrameSnapshot` and related dirty/damage contracts.
- `howl-term` stores `howl_render.Core.FrameSnapshot` directly and no longer has `src/render/snapshot.zig`.
- `howl-term/src/render/sync.zig` remains term-owned because it projects VT, selection, cursor, scrollback, alternate-screen state, and wake events into the render-core snapshot model.

Sprint 5 checkpoint 2 evidence:

- `howl-render-core/src/frame_pipeline.zig` owns retained-frame snapshot tokens, damage kind, prepare request metadata, submit validation, and latest-wins mailbox behavior.
- `howl-render-core/src/frame_queue.zig` owns retained-frame queue policy, visibility drops, target invalidation, prepared-slot ownership, and scheduling metrics.
- `howl-render-core/src/render_core.zig` exposes `Core.FramePipeline` and `Core.FrameQueue`.
- `howl-term` consumes these render-core owners through `howl_render.Core` and no longer has `src/render/pipeline.zig` or `src/render/queue.zig`.

Sprint 5 checkpoint 3 evidence:

- `howl-render-core/src/frame_metrics.zig` owns prepare/render metric contracts.
- `howl-render-core/src/types.zig` owns `FramePixels` geometry input and clamping helpers.
- `howl-term/src/runtime/contract.zig` aliases render metrics and frame pixel geometry from `howl_render.Core` instead of defining those render contracts locally.
- `howl-term/src/render/render.zig` no longer re-exports `Core` or `Renderer`; term files consume render-core directly where orchestration needs it.

Sprint 5 checkpoint 4 evidence:

- `howl-render-core/src/renderer.zig` owns `Renderer.FrameRecord`, the renderer prepared-frame wrapper plus pipeline metadata.
- `howl-term/src/runtime/contract.zig` aliases `PreparedRenderFrame` from `howl_render.Renderer.FrameRecord` and no longer imports `render/render.zig` to shape a render contract.
- `howl-term/src/render/render.zig` keeps orchestration functions only and no longer defines a public prepared-frame wrapper struct.

Sprint 5 checkpoint 5 evidence:

- `howl-render-core/src/renderer.zig` owns submit-report conversion through `FrameRecord.renderMetrics` and `FrameRecord.submittedFrame`.
- `howl-term/src/render/render.zig` no longer translates renderer submit reports/counters into metric or retained-frame structs; it only stores render-core outputs and finishes wake bookkeeping.
- Parent checks reject direct submit-report/counter conversion in `howl-term/src/render/render.zig`.

## Verification Cadence

For every implementation checkpoint:

- `howl-term`: `zig build test && zig build ffi:build`
- `howl-linux-host`: `zig build test`
- parent: `zig build && zig build test && ./status.sh`

Use `--summary all` only to diagnose failures.

Commit and push every meaningful checkpoint.
