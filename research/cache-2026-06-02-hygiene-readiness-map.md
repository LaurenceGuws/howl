# Hygiene Readiness Map - 2026-06-02

Research cache. Research only. No product code, scratchpads, `current.txt`, or git edits.

## User Correction

Only the user narrows sprint scope. Researcher authority is limited to facts, dependencies, contradictions, exact questions, and readiness. Every hygiene offender already identified remains in sprint-level research scope until the user decides otherwise.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`: TigerBeetle pressure for simple control flow, assertions, owner-true nouns, small scopes, reduced status dimensionality, and rejection of duplicated state.
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`: TigerBeetle pressure for control-plane/data-plane separation, exact ownership, and bounded accountable state.
3. Existing `research/*.md` caches via grep only, as navigation index.
4. `reference-index.md`: Ghostty for VT-core and embedding seams, Alacritty for host/runtime/display/window/input/presentation/renderer organization, TigerBeetle for Zig discipline.
5. Current offender caches used only as navigation after re-checking current source: `research/cache-2026-06-02-hygiene-offenders-a.md`, `research/cache-2026-06-02-hygiene-offenders-b.md`, `research/cache-2026-06-02-hygiene-offenders-c.md`.
6. Current Howl host source: `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-linux-host/src/test_root.zig`, `howl-linux-host/src/test/host.zig`, `howl-linux-host/build.zig`.
7. Current Howl render source: `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/render/render_surface_realizer.zig`, `howl-render/src/text/scene.zig`, `howl-render/src/source/text_input.zig`, `howl-render/src/session/text.zig`, `howl-render/src/prepared/owner.zig`, `howl-render/src/ffi/render_surface.zig`, `howl-render/src/ffi/prepared_surface.zig`, `howl-render/src/test/ffi.zig`, `howl-render/include/howl_render.h`.
8. Current Howl VT source: `howl-vt/src/parser/main.zig`, `howl-vt/src/action/vocabulary.zig`, `howl-vt/src/parser/events.zig`, `howl-vt/src/ffi.zig`, `howl-vt/include/howl_vt.h`.
9. Current Howl PTY source: `howl-pty/src/ffi.zig`, `howl-pty/include/howl_pty.h`.
10. References: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`, `utils/dev_references/terminals/ghostty/src/renderer.zig`.

## Research Cache Grep Terms And Leads

Terms used against `research/*.md`:

- `retained|render_surface|RenderSurface|probe|status|validation|validate`
- `context.zig|retained.zig|render_surface.zig|render_surface_emitter|render_surface_realizer|howl_render.h|howl_vt.h|howl_pty.h|scene.zig|text_input.zig|parser/main.zig|action/vocabulary.zig|parser/events.zig|session/text.zig|prepared/owner.zig|ffi.zig`
- `offender|hygiene|status|result|enum|FFI|ABI|render|host|protocol|validation|execution|probe|mirror|bundle|responsibility|sprawl|fat`

Leads found:

- All offender caches converge on the first dependency cluster: `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, and `howl-linux-host/src/terminal/context.zig` duplicate render-surface validation/status/probe facts.
- Render ABI thickness appears in `howl-render/include/howl_render.h` and mirrors in `howl-render/src/ffi/render_surface.zig` and `howl-render/src/ffi/prepared_surface.zig`.
- Render data-plane bundling appears in `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/render/render_surface_realizer.zig`, `howl-render/src/session/text.zig`, and `howl-render/src/prepared/owner.zig`.
- VT ABI/parser/action bundling appears in `howl-vt/src/ffi.zig`, `howl-vt/src/parser/main.zig`, `howl-vt/src/parser/events.zig`, and `howl-vt/src/action/vocabulary.zig`.
- PTY ABI pressure appears in `howl-pty/src/ffi.zig` and `howl-pty/include/howl_pty.h`, but current source shows a smaller translator than render and VT.
- Old cache claims were navigation only. Findings below are tied back to current files and source-order pressure.

## Reference Facts

- `reference-index.md` lines 17-93 make Ghostty the first reference for VT-core shape, embedding seams, C-facing VT surface shape, and renderer/text seam pressure.
- `reference-index.md` lines 94-160 make Alacritty the reference for host runtime, display/window/input/presentation, and pragmatic renderer organization.
- `reference-index.md` lines 161-190 make TigerBeetle the hard gate for bounds, assertions, naming, structure, directness, and tests.
- Alacritty `renderer/mod.rs` keeps renderer roots and GL execution under renderer ownership. This supports keeping Howl host GL resource realization in `howl-linux-host/src/display/renderer/render_surface.zig`, not in terminal retained state.
- Alacritty `renderer/text/glyph_cache.rs` and `renderer/text/atlas.rs` split cache/loader/atlas responsibilities. This supports separating pure render-surface contract validation from GL texture mutation without moving GL ownership out of display renderer.
- Ghostty `renderer.zig` describes renderer output assuming backend-specific resources such as OpenGL context or Vulkan surface are already prepared. This supports preserving host backend preparation/resource realization as host/display work, not window chrome or retained terminal state.
- TigerBeetle style rejects vague owner nouns, duplicated status/state, hidden bounds, broad result dimensionality, and generic buckets. This is the governing pressure for all readiness judgments.

## Full Offender Coverage Table

| Rank | Area | Current files | Offender facts | Dependency | Readiness |
| --- | --- | --- | --- | --- | --- |
| 1 | Host retained render mirror/probe/status cluster | `howl-linux-host/src/terminal/render/retained.zig` lines 4-1563 and tests from 1565 onward | Retained submit/present state is mixed with `PreparedRenderResourcePlan`, `PreparedRenderSurfaceProbe`, `RenderResourceStore`, three validation status families, counters, and software resource lifecycle validation. | Depends on deciding one host render-surface contract validation owner shared by retained and display renderer. | Worker-ready only for a narrow first cut if reviewer accepts exact owner path/name and no ABI changes. |
| 2 | Host GL render-surface validation/resource/upload cluster | `howl-linux-host/src/display/renderer/render_surface.zig` lines 1-2587 | `RenderResourceTextures` owns true GL texture realization, but also owns pure surface validation, command shape taxonomy, failure buckets, GL upload/draw, shape classification, and large tests. | Same contract-validation decision as rank 1; GL lifecycle must remain display renderer. | Worker-ready only for validation/status extraction after owner path is accepted. |
| 3 | Terminal context render submit/upload policy | `howl-linux-host/src/terminal/context.zig` lines 39-958 and tests from 1144 onward | `Context` centralizes host turn flow, but nested submit backend owns resource realization calls, upload policy, shape dispatch, ABI emit-status translation, and submit failure mirrors. | Depends on rank 1/2 because context currently consumes retained resource-plan status and display shape classifiers. | Not worker-ready as a broad cleanup; narrow call-site adjustment may be worker-ready inside rank 1/2. |
| 4 | Render C ABI thickness and mirrors | `howl-render/include/howl_render.h`, `howl-render/src/ffi/render_surface.zig`, `howl-render/src/ffi/prepared_surface.zig`, `howl-render/src/test/ffi.zig` | Public header carries many limits, status enums, render surface resource stream structs, VT source mirrors, prepared info, submit execution, and session calls. FFI mirrors assert layout field-by-field. | Product C ABI authority. Internal validation cleanup can happen without ABI changes; ABI shape changes need user decision. | Not worker-ready for ABI reshaping; worker-ready only for no-ABI internal mirror/status reductions after a reviewed slice. |
| 5 | Render surface emitter/resource store/atlas cluster | `howl-render/src/prepared/render_surface_emitter.zig` lines 18-2600 | `Emitter` owns C surface assembly, persistent sprite resource store, atlas packing, resource create/upload/retire, fixture vocabulary, broad `Limits`, error set, and tests. | Depends on render ABI and prepared-owner facts; independent of host GL extraction if no ABI change. | Not worker-ready until resource-store vs emitter ownership is source-backed against Ghostty/Alacritty atlas references. |
| 6 | Render software realizer mirror | `howl-render/src/render/render_surface_realizer.zig` | Software realization owns another `ResourceStore` and realizes render-surface commands without host GL. This may be legitimate oracle/software backend or another validation mirror. | Depends on deciding whether realizer is test oracle, software backend, or render-owned contract consequence. | Not worker-ready; exact lifecycle and test role must be proved. |
| 7 | Render text scene/source input shape | `howl-render/src/text/scene.zig`, `howl-render/src/source/text_input.zig` | Scene/input files participate in VT-source-to-render text truth and may carry bucket/options pressure. They feed render preparation and emitter paths. | Depends on render text-session/source ownership and Ghostty/Alacritty text seam comparison. | Not worker-ready; current facts identify pressure but not exact owner cut. |
| 8 | Render text session owner bundle | `howl-render/src/session/text.zig` lines 32-846 | `TextSessionOwner` aggregates geometry, source slot, prepare requests, submitted state, font paths, prepared handles, sprite resources, config, cursor blink, and failure counters. | Depends on prepared owner, emitter resource store, font/provider callback pressure. | Not worker-ready; exact split requires source-backed owner map. |
| 9 | Render prepared owner lifecycle/payload/status bundle | `howl-render/src/prepared/owner.zig` lines 15-836 | Prepared handle owner stores flattened prepared facts, optional render-surface payload, lifecycle state, token/geometry copies, upload count, and emit status; creation emits payload. | Depends on emitter and ABI prepared surface facts. | Not worker-ready; exact payload owner and cached-field proof required. |
| 10 | VT FFI breadth | `howl-vt/src/ffi.zig`, `howl-vt/include/howl_vt.h` | FFI combines ABI extern structs, terminal lifecycle/feed, surface copy, selection, input encoding, runtime progress, translations, and tests. | Depends on public VT ABI shape and Ghostty C-facing VT surface references. | Not worker-ready for public ABI movement; helper-only split may become worker-ready after Ghostty comparison. |
| 11 | VT action vocabulary bucket | `howl-vt/src/action/vocabulary.zig` | Protocol/action file aggregates semantic events, screen actions, report actions, mode actions, Kitty actions, host actions, and repeated subsets. | Depends on parser, terminal execution owners, Ghostty VT parser/action shape, and Kitty protocol facts. | Not worker-ready; exact event/action ownership must be researched. |
| 12 | VT parser event storage/materialization | `howl-vt/src/parser/main.zig`, `howl-vt/src/parser/events.zig` | Parser events store combines parser callback materialization, byte/int/aux payload stores, DCS/APC/PM bytes, charset state, rollback, compaction, and iteration. | Depends on Ghostty parser/event storage shape and current parser capacity invariants. | Not worker-ready; exact storage split and capacity assertions must be proved. |
| 13 | PTY FFI breadth | `howl-pty/src/ffi.zig`, `howl-pty/include/howl_pty.h` | PTY FFI has status enum, snapshot/pump/read/limits result structs, launch translation, lifecycle/control/read/pump calls. It is compact and mostly translation-only. | Depends on public PTY ABI and Ghostty/Alacritty PTY seam only if behavior grows. | Not first implementation pressure; worker-ready only for preserving growth guardrails or tiny helper moves after ABI check. |

## Ranked Sprint-Level Dependency Map

1. Host render-surface validation/status/probe duplication is the first dependency because `retained.zig`, `render_surface.zig`, and `context.zig` currently share duplicated truth about the same borrowed C render surface. This does not require public ABI changes if the first cut only collapses internal host validation/status paths.
2. Terminal context cleanup depends on the host render-surface validation decision because context currently reads retained resource-plan status and calls display renderer shape/upload policy.
3. Render ABI thickness is a product-boundary decision. Internal cleanup should avoid ABI changes unless the user explicitly authorizes public contract movement.
4. Render emitter/prepared/text-session cleanup depends on preserving `HowlRenderSurface` layout, prepared handle lifetime, render-surface payload borrowing, and text session C ABI behavior.
5. VT FFI/parser/action cleanup depends on Ghostty VT-core and C-facing surface comparison, then Kitty/official protocol facts for protocol actions.
6. PTY FFI is lower current pressure because it is compact and mostly translates contracts, but it remains in scope as an ABI breadth pattern and should not absorb new unrelated behavior.

## Per-Area Readiness

### Host Render-Surface Validation Cluster

Facts known:

- `retained.zig` defines retained sequencing enums at lines 4-26 and true retained state/mutation around lines 612-919.
- `retained.zig` also defines `PreparedRenderResourcePlan`, `PreparedRenderResourcePlanStatus`, `RenderResourceStoreStatus`, `PreparedRenderSurfaceProbe`, `PreparedRenderSurfaceProbeStatus`, `RenderResourceStore`, and validators from lines 77-1563.
- `render_surface.zig` defines `RenderResourceTextures` at lines 35-75 and GL realization from lines 81-489, but also validates pure contract facts from lines 164-312 and command shapes from lines 523-742.
- `context.zig` consumes `PreparedUpload` and retained resource-plan status around lines 539-570 and 656-660.
- Alacritty supports renderer-side ownership for backend resources. TigerBeetle rejects duplicated state/status taxonomies.

Facts missing:

- Reviewer acceptance of exact owner path/name. Prior `render_surface_contract.zig` path is plausible but not accepted proof; `contract` naming may read as a broad bucket if not tied to exact behavior.
- Exact single status/fact shape name for host validation that avoids generic `Result`, `Info`, or bucket pressure.
- Exact host test wiring path for a new owner without duplicate test roots.

Exact next research question if not accepted:

- What exact owner noun/path does Alacritty-backed host renderer organization and TigerBeetle naming pressure allow for pure borrowed `HowlRenderSurface` validation consumed by both retained submit and display GL resource realization?

Possible worker slice if reviewer accepts owner path:

- Add one host display-renderer child owner for pure borrowed render-surface validation; move span/version/upload byte/resource lifecycle/command/glyph validation from retained and display into it; keep GL mutation in `render_surface.zig`; keep retained prepare/submit/present sequencing in `retained.zig`; adjust only the necessary context call sites; run host unit tests.

### Terminal Context

Facts known:

- `Context` fields aggregate terminal core, wait thread, host texture, render-surface textures, input, event loop, title, geometry, focus, scrollbar, links, selection, and cursor blink around lines 80-99.
- `ContextSubmitBackend` owns backend resource realization call-through, host texture ensure, upload shape dispatch, upload policy, emit-error mapping, and submit execution construction around lines 539-719.
- Submit transaction locking/unlocking and handle stability checks around lines 721-758 are central host orchestration and should remain centralized.

Facts missing:

- Exact display-renderer API shape after validation extraction.
- Whether upload shape policy remains display renderer or becomes a narrow terminal-render submit owner.

Exact next research question:

- Which Alacritty host/display boundary most closely matches Howl's `ContextSubmitBackend` responsibilities once pure render-surface validation is removed?

Possible worker slice:

- Only adjust context imports/status call sites required by the host render-surface validation first cut. Do not broadly split `Context` until display upload policy owner is proved.

### Render ABI And FFI Mirrors

Facts known:

- `howl_render.h` defines many render limits, statuses, resource structs, VT source mirrors, prepared info, submit execution/result, and text-session calls in one public C ABI.
- `howl-render/src/ffi/render_surface.zig` mirrors render-surface structs and performs layout assertions.
- `howl-render/src/ffi/prepared_surface.zig` is thinner and points more strongly to prepared owner and ABI shape than to itself as first target.
- Public C ABI is the product; host must not bypass it with Zig-shaped imports.

Facts missing:

- User-authorized ABI contract movement, if any.
- Exact unused/duplicated fields and status values proved by current source and tests.

Exact next research question:

- Which `howl_render.h` status fields and structs are internally duplicated versus externally required by the C ABI product boundary?

Possible worker slice:

- No public ABI worker slice from current evidence. Internal host validation cleanup can proceed with no header edits.

### Render Emitter, Realizer, Prepared Owner, Text Session, Text Scene/Input

Facts known:

- `render_surface_emitter.zig` owns command emission plus persistent sprite resource/atlas lifecycle and fixture/test vocabulary.
- `render_surface_realizer.zig` owns software resource realization and may duplicate validation/resource-store concepts.
- `prepared/owner.zig` couples prepared handle lifecycle with render-surface payload emission/status and cached prepared facts.
- `session/text.zig` aggregates font config, source slot, prepare queue, submitted state, prepared handles, sprite resources, and FFI handle lifecycle.
- `scene.zig` and `text_input.zig` participate in source-to-text-scene truth and need exact owner mapping before movement.

Facts missing:

- Whether `render_surface_realizer.zig` is product software backend, test oracle, or render-owned validation consequence.
- Exact atlas/resource owner shape from Alacritty `atlas.rs`/`glyph_cache.rs` and Ghostty font atlas references.
- Exact prepared payload ownership after preserving C ABI borrow lifetime.

Exact next research question:

- What is the source-backed ownership map from text session source publication to prepared handle to render-surface payload emission to software/host realization, and where do atlas/resource lifecycle facts belong?

Possible worker slice:

- None yet. Research must first produce a source-backed owner map with exact files, symbols, tests, and stop conditions.

### VT FFI, Parser Events, Action Vocabulary

Facts known:

- `howl-vt/src/ffi.zig` combines many C-facing VT calls, translation helpers, surface copy, selection, runtime, input encoding, and tests.
- `howl-vt/src/action/vocabulary.zig` is a vocabulary bucket spanning semantic events, screen actions, reports, modes, Kitty actions, and host actions.
- `howl-vt/src/parser/events.zig` combines event storage, payload storage, DCS/string body reconstruction, charset state, rollback, compaction, and iteration.
- `howl-vt/src/parser/main.zig` is part of parser ownership and must be checked before changing parser event materialization.

Facts missing:

- Ghostty parser/event/action owner comparison with exact files and line-backed shape.
- Kitty/official protocol facts for action vocabulary if semantic tags move.
- Current test entrypoint and capacity invariant map for parser events.

Exact next research question:

- Against Ghostty VT-core shape, which Howl action/event types belong near parser output, screen execution, mode state, host reporting, Kitty protocol handling, and C-facing FFI translation?

Possible worker slice:

- None yet. VT cleanup needs dedicated research before any movement.

### PTY FFI

Facts known:

- `howl-pty/src/ffi.zig` is compact compared with render/VT and mostly translates lifecycle/control/transport/read calls and result structs.
- `howl-pty/include/howl_pty.h` is the public C ABI boundary.

Facts missing:

- Exact public ABI field/status necessity, if a PTY ABI cleanup is desired.
- Ghostty/Alacritty PTY seam comparison for any growth beyond current translator shape.

Exact next research question:

- Which PTY FFI result structs are ABI-forced and which are only internal convenience mirrors?

Possible worker slice:

- No first implementation slice. Current readiness supports a guardrail: do not add more unrelated PTY behavior or status/result families to `ffi.zig` without a PTY ABI slice.

## User-Decision Questions

- Should public C ABI cleanup be authorized during this hygiene sprint, or should initial implementation slices be limited to internal owner/status cleanup with no header changes?
- Should the first implementation slice target only host render-surface validation/status duplication, with `context.zig` edits limited to necessary call-site updates?
- Is a new host display-renderer child owner for borrowed render-surface validation acceptable if named with an exact behavior noun and reviewed before worker handoff?

## Reviewer Handoff

Accept if:

- The map keeps every identified offender in sprint-level research scope and reports readiness instead of narrowing scope.
- The first dependency is host render-surface validation/status/probe duplication across `retained.zig`, `render_surface.zig`, and `context.zig`.
- No public ABI change is authorized by this cache.
- GL texture ownership remains in display renderer, retained prepare/submit/present sequencing remains in retained, and host turn control remains centralized in context.
- Areas outside the first dependency are marked as needing exact source-backed research questions, not implementation design by worker.

Reject if:

- A worker is allowed to choose owner names, paths, status shapes, or test wiring.
- Public C ABI changes are implied without user approval.
- A generic owner, bucket, manager, controller, engine, `types.zig`, or convenience Zig host import is proposed.
- Validation movement weakens assertions, bounds, C ABI layout checks, or host defense against malformed borrowed render surfaces.
- Test wiring creates duplicate side-entry roots or bypasses the module's curated test entrypoint.
