# Six-Target Pragmatic Shape Sprint

Status:

- Active execution sprint contract.
- Orchestrator session id: `orch-2026-06-14-six-target-pragmatic-shape-01`.
- Researcher session id: `research-2026-06-14-six-target-pragmatic-shape-01`.
- Reviewer session id: `review-2026-06-14-six-target-pragmatic-shape-01`.
- Planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`.
- Accepted planning receipt: `9f20f26` `Accept six-target pragmatic-shape planning`.
- Sprint seed receipt: `1f2c1cc` `Seed six-target pragmatic-shape sprint`.

Problem:

- Remove remaining low-level pragmatic ugliness without treating size as debt.
- Preserve owner-true large files and clean them from within when references prove they should stay centralized.
- Remove support buckets, ownership-probing generics, excess local protocol/result nouns, transitional names, and narrated runtime code where direct owner code is clearer.

## Slice 1 support direct-owner cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-01`.
- Allowed files:
  - `howl-render/src/text/ft_hb/support.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/text/ft_hb/support_test.zig`
- Required shape:
  - Keep `FtHbSupport` as the sole state owner in `support.zig`.
  - Move context extraction to the render-session boundary.
  - Delete ownership-probing helpers `textState`, `configView`, `lockFt`, and `unlockFt`.
  - Change support internals to take explicit state/config inputs instead of `anytype`.
  - Do not add a new vague `Context`, `State`, `Options`, or `Info` bucket to replace the removed generics.
  - Keep external behavior and fallback order unchanged.
- Exact tests:
  - from `howl-render`, run `zig build test:unit`
  - required test file: `howl-render/src/text/ft_hb/support_test.zig`
  - required test names:
    - `provider loads fallback face for symbol glyph with primary present`
    - `ft hb state configures explicit retained cache and input capacities`
    - `shape run input assembly reuses retained bounded buffers`
- Non-goals:
  - No `glyph_raster.zig` redesign.
  - No cache policy change.
  - No font-session API redesign beyond what direct support ownership requires.
- Stop conditions:
  - Stop if generic removal requires inventing a replacement bucket with weaker ownership truth.
  - Stop if the change spreads into non-target render files outside the allowed list.
  - Stop if fallback behavior changes.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 2 surface direct-owner cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-02`.
- Allowed files:
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Required shape:
  - Keep `Surface` as the one host-surface owner.
  - Remove internal `anytype`/`Ops` narration where the real owner is already `Surface` or `HowlTerm`.
  - Prefer direct owner code over `ContextDriveOps`, `ContextSubmitBackend`, and local generic present/clipboard helpers.
  - Inline or delete local request/result buckets that survive only as scaffolding after helper removal.
  - Preserve the centralized render/progress and submit/present spine.
- Exact tests:
  - from `howl-linux-host`, run `zig build test:unit`
  - required test file: `howl-linux-host/src/terminal/surface_test.zig`
  - required test names:
    - `pending VT clipboard write follows OSC 52 policy`
    - `drive progress keeps per-terminal continuation admission until a later non-keep turn`
    - `inactive tab continuation re-enters from per-terminal continuation admission`
    - `present pending blocks submit path until host present ack`
    - `submit path runs once no host present is in flight`
    - `submit backend upload observes terminal mutex unlocked`
    - `render submit runs under terminal mutex after backend upload`
    - `host upload failure returns failed submit without render submit`
    - `prepared handle mutation after upload does not submit`
    - `resize success path submits full surface and acks matching present token`
    - `resize upload failure zeros host dimensions and retry submits same full frame`
    - `resize while present pending waits for matching ack before resized submit`
    - `complete present acks matching host-owned token once and clears`
    - `mismatched complete present does not ack or clear`
- Non-goals:
  - No surface split.
  - No event-loop redesign.
  - No input policy change.
  - No VT/render ABI change.
- Stop conditions:
  - Stop if direct helper removal forces a weaker test seam than the current proof.
  - Stop if mutex or submit/present control flow becomes less centralized.
  - Stop if the change spreads outside the allowed files.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-linux-host`, commit-hash handoff required on slice acceptance.

## Slice 3 cluster assembly cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-03`.
- Allowed files:
  - `howl-render/src/text/shape/cluster.zig`
- Required shape:
  - Keep `cluster.zig` as one cluster/text-cache assembly owner.
  - Delete `InputRenderableAssembly` and `CellLineTextCacheAssembly`.
  - Keep `RetainedScratch` as the explicit bounded retained owner.
  - Rewrite direct build paths through scratch/local slices without moving ownership into a new helper file.
- Exact tests:
  - from `howl-render`, run `zig build test:unit`
  - required test file: `howl-render/src/text/shape/cluster.zig`
  - required test names:
    - `cell inputs build text cache renderable cells and clusters`
    - `cell inputs retain combining sequences in text cache`
    - `cell inputs preserve style and presentation into renderables and clusters`
    - `partial damage filters clean clusters before shaping`
    - `sparse cells keep only damaged base cells`
    - `sparse cells intern repeated codepoints`
    - `sparse cells keep empty background witnesses for scene ownership`
    - `rich cell text interning deduplicates codepoint sequences`
    - `rich cell text renderables resolve exact interned text ids`
    - `retained scratch bounds sparse cell assembly`
    - `retained scratch bounds rich input codepoint assembly`
- Non-goals:
  - No split into new files.
  - No lane classification change.
  - No text interning behavior change.
- Stop conditions:
  - Stop if a replacement helper just moves the same narration sideways.
  - Stop if `RetainedScratch` is targeted without new reference proof.
  - Stop if proof requires weakening current inline tests.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 4 special legacy raster bucket cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-04`.
- Allowed files:
  - `howl-render/src/text/raster/special_legacy_computing.zig`
  - `howl-render/src/text/raster/special_test.zig`
- Required shape:
  - Keep `special_legacy_computing.zig` as one special-raster owner.
  - Remove `SpriteShade` and `BranchNode` option buckets.
  - Replace them with exact draw verbs or exact argument lists.
  - Add explicit degenerate-size assertions where width/height math assumes positive sizes.
- Exact tests:
  - from `howl-render`, run `zig build test:unit`
  - required test file: `howl-render/src/text/raster/special_test.zig`
  - required preserved test names:
    - `generated shade preserves fallback intensity levels`
    - `generated branch nodes preserve filled and unfilled variants`
  - required added test name:
    - `generated legacy computing raster guards degenerate size bounds`
- Non-goals:
  - No Unicode coverage expansion.
  - No generated table rewrite.
  - No visual redesign beyond bucket removal.
- Stop conditions:
  - Stop if cleanup cannot be proved with bounded tests.
  - Stop if the replacement requires a new generic options bucket elsewhere.
  - Stop if the required test root cannot stay owner-true and single-purpose.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 5 emitter pragmatic no-op or micro-cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-05`.
- Allowed files:
  - `howl-render/src/surface/emitter.zig`
  - `howl-render/src/surface/emitter_test.zig`
  - `howl-render/src/surface/handle_test.zig`
- Required shape:
  - Re-verify during execution that `emitter.zig` is still owner-true and direct.
  - If no clearer reference-backed cleanup survives, record an explicit no-op acceptance for this slice.
  - If a cleanup is still justified, limit it to collapsing the four identical fill-pass wrappers or removing tiny testing pass-through wrappers.
  - Keep `Emitter(comptime limits)` and all explicit bounded arrays/counters.
- Exact tests:
  - verification-only no-op path or micro-cleanup path both require from `howl-render`: `zig build test:unit`
  - required test files:
    - `howl-render/src/surface/emitter_test.zig`
    - `howl-render/src/surface/handle_test.zig`
  - required test names:
    - `render surface surface emitter coalesces adjacent prepared fill commands`
    - `render surface surface emitter does not coalesce distinct prepared fills`
    - `render surface surface emitter rejects command bound overflow`
    - `render surface surface emitter rejects upload bound overflow`
    - `render surface surface emitter rejects retire bound overflow`
    - `render surface surface emitter rejects upload byte total overflow`
    - `render surface surface emitter emits transient sprite beyond persistent budget`
    - `render surface surface emitter reports exact transient retire bound`
    - `prepared handle reports missing surface when render_surface emission overflows`
- Non-goals:
  - No removal of compile-time bounds.
  - No resource lifetime policy change.
  - No ABI consequence change.
- Stop conditions:
  - Stop and convert to explicit no-op if cleanup is metric-only.
  - Stop if a replacement abstraction is less direct than current explicit arrays/counters.
  - Stop if tests would need widening just to justify a cosmetic rewrite.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 6 parser minor directness cleanup

- Coder session id: `coder-2026-06-14-six-target-pragmatic-shape-slice-06`.
- Allowed files:
  - `howl-vt/src/parser.zig`
- Required shape:
  - Keep parser control flow centralized in `next`, `nextActive`, `buildPhases`, `exitPhase`, `entryPhase`, and `doAction`.
  - Remove `bufferedPut(anytype)` if exact inline control handling is clearer.
  - Remove transitional `CsiActionData` if publishing `CsiAction` directly remains readable.
  - Do not split parser ownership or string-control protocol handling into extra files.
- Exact tests:
  - from `howl-vt`, run `zig build test:unit`
  - required test file: `howl-vt/src/parser.zig`
  - required test names:
    - `parser control spine orders populated phase slots in one next call`
    - `parser keeps active string controls exclusive`
    - `parser assembles CSI params and separators`
    - `parser DCS hook stays on the hook boundary`
- Non-goals:
  - No parser split.
  - No OSC/DCS/APC/PM policy change.
  - No protocol expansion.
- Stop conditions:
  - Stop if any change threatens the centralized control spine.
  - Stop if cleanup broadens into protocol redesign.
  - Stop if generic removal does not make the file clearer on direct reading.
- Required receipt fields: planning seed receipt `117b860`, accepted planning receipt `9f20f26`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-vt`, commit-hash handoff required on slice acceptance.
