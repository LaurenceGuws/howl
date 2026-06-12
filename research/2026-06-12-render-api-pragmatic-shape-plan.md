Render API pragmatic shape plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-render-api-pragmatic-shape-02`.
Reviewer session id: `review-2026-06-12-render-api-pragmatic-shape-01`.
Planning commit-hash receipt: implementation commits `howl-render` `975b723` and `howl-linux-host` `cf779db`; root accountability/submodule commit pending.

Question

- What is the first render-API simplification slice that kills or re-architects `contract`, `prepared`, and `session` around explicit `vt_sfc` input and `rdr_sfc` output naming, while pulling `howl-render` toward Alacritty and keeping the embeddable boundary honest?

Answer

- There is an honest first slice.
- The first cut should delete the token-only publish middle layer and collapse the live render path to one accountable chain: `vt_sfc` publication -> prepare request -> one `rdr_sfc` handle -> submit that same handle.
- The cut is source-backed because Alacritty has one content-preparation owner and one renderer owner, not a second mailbox that republishes only tokens after the render output already exists: `display/content.rs:27-39`, `40-88`, `153-185`; `display/mod.rs:775-879`; `renderer/mod.rs:177-191`; `renderer/text/mod.rs:49-95`, `111-172`.
- The cut is honest for the embeddable boundary because Howl still keeps the host-facing `vt_sfc` publication and `rdr_sfc` output seam, but removes the extra `prepared`/`submit` shuttle that has no Alacritty pressure and no distinct owner truth.
- `text/contract.zig` is not the first cut target for deletion. Current proof says it is already text-internal structure, while the fake API bulk sits in `prepared` plus `session` handoff state. The first slice should stop `contract` from participating in the render API story, not rename that deep file first.

Sources Read In Order

1. `/home/home/personal/projects/howl/AGENTS.md:1-265`
2. `/home/home/personal/projects/howl/loop/flow.md:1-137`
3. `/home/home/personal/projects/howl/loop/orcestrator.md:1-61`
4. `/home/home/personal/projects/howl/loop/researcher.md:1-86`
5. `/home/home/personal/projects/howl/loop/reviewer.md:1-57`
6. `/home/home/personal/projects/howl/loop/coder.md:1-60`
7. `/home/home/personal/projects/howl/reference-index.md:1-273`
8. `/home/home/personal/projects/howl/sprints/current.txt:1-35`
9. `/home/home/personal/projects/howl/loops/render-api-pragmatic-shape-live-loop.txt:1-54`
10. `/home/home/personal/projects/howl/research/2026-06-12-render-api-pragmatic-shape-plan.md:1-116`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1-260`
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1-260`
13. Current Howl render API and owners:
   - `/home/home/personal/projects/howl/howl-render/include/howl_render.h:520-617`
   - `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig:1-38`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/vt_surface.zig:13-92`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepare_request.zig:6-56`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig:8-97`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/submission.zig:8-150`
   - `/home/home/personal/projects/howl/howl-render/src/ffi/work_state.zig:5-32`
   - `/home/home/personal/projects/howl/howl-render/src/tv_surface/prepare_request.zig:8-241`
   - `/home/home/personal/projects/howl/howl-render/src/tv_surface/vt.zig:103-239`
   - `/home/home/personal/projects/howl/howl-render/src/tv_surface/slot.zig:68-192`
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig:143-171`, `220-283`, `431-778`
   - `/home/home/personal/projects/howl/howl-render/src/session/submitted.zig:16-118`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig:8-80`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:62-200`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:17-25`, `195-255`, `257-360`
   - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:1-320`
   - `/home/home/personal/projects/howl/howl-render/src/text/session.zig:4-111`
   - `/home/home/personal/projects/howl/howl-render/src/text/surface_preparer.zig:53-178`, `180-258`
   - `/home/home/personal/projects/howl/howl-render/src/geometry/tokens.zig:15-120`
   - `/home/home/personal/projects/howl/howl-render/src/geometry/render_surface_realizer.zig:17-109`, `192-249`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:150-265`
14. Alacritty render/content/text seams:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-39`, `40-88`, `153-185`, `187-299`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:775-879`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-191`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-95`, `111-172`, `182-197`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:17-26`, `42-99`, `200-277`, `311-317`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:14-31`, `33-61`, `118-140`, `247-260`
15. Kitty pressure:
   - none read. No material Kitty UX or protocol fact changed the owner decision for this first slice.

Exact Files And Line References Governing The Decision

- Public ABI currently exposes the whole extra dance in one cluster: `howl_render_text_session_prepare_handle`, `publish_prepared`, `publish_prepared_handle`, `take_submit_decision`, `take_submit_handle`, `submit`, `submit_handle`, and `prepared_surface_render_surface`: `howl-render/include/howl_render.h:560-617`.
- The exported symbols mirror that same oversized seam: `howl-render/src/libhowl_render.zig:21-38`.
- `PreparedHandle.create` allocates a handle, registers it, and immediately emits the render-surface payload before any publish/submit step happens: `howl-render/src/prepared/handle.zig:72-95`, `184-194`.
- `TextSessionOwner.publishPreparedHandle` does not build output; it only changes state, caches the handle, and republishes the same token: `howl-render/src/session/text.zig:652-659`.
- `Submitted` owns a mailbox of only `PreparedSurfaceToken`, not the output handle or surface payload: `howl-render/src/session/submitted.zig:27-54`.
- `TextSessionOwner.takeSubmitHandle` then reacquires the cached handle and asserts token equality against the mailbox result: `howl-render/src/session/text.zig:674-701`.
- Host retained code prepares a handle, immediately republishes that same handle back into the session, and later asks for it again: `howl-linux-host/src/terminal/render/retained.zig:155-167`, `181-219`, `239-265`.

Current-Code Facts

- `vt_surface` input is already a real owner seam. `reserveVtSurfaceSlot` and `commitVtSurface` publish `PublicationSource` into `PrepareRequests`: `howl-render/src/ffi/vt_surface.zig:13-42`; `howl-render/src/session/text.zig:602-610`; `howl-render/src/tv_surface/prepare_request.zig:37-127`.
- `prepare` is already distinct from `submit`. `takePrepareRequest` produces a token from queued VT publication state, and `prepareHandle` consumes the exact matching active publication: `howl-render/src/ffi/prepare_request.zig:6-23`; `howl-render/src/session/text.zig:514-535`, `629-646`; `howl-render/src/tv_surface/prepare_request.zig:98-127`.
- `PreparedSurface` is not just metadata. It already carries the full text-scene output plus render-surface emission-failure state: `howl-render/src/prepared/surface.zig:23-80`.
- `PreparedHandle` is not a lazy token. It owns `PreparedSurface` plus an emitted render-surface payload pointer: `howl-render/src/prepared/handle.zig:62-70`, `136-145`, `184-194`.
- The extra `publishPrepared` path is token-only state with no new render consequence: `howl-render/src/session/submitted.zig:34-54`; `howl-render/src/ffi/submission.zig:8-50`.
- `text/contract.zig` is broad and generic, but it is currently internal text machinery used by preparer/session/shaper code, not the live public render API seam: `howl-render/src/text/contract.zig:1-320`; `howl-render/src/text/surface_preparer.zig:111-178`; `howl-render/src/text/session.zig:4-111`.

Reference Facts

- Alacritty builds renderable content directly from terminal state in one owner, `RenderableContent`, which owns cursor/content derivation and yields renderable cells: `display/content.rs:27-39`, `40-88`, `153-185`.
- Alacritty draw flow is direct: gather `RenderableContent`, collect cells, then pass those cells into the renderer; there is no second token-mailbox owner between prepared output and renderer consumption: `display/mod.rs:783-879`.
- Alacritty renderer text path takes cells plus persistent glyph/atlas state and draws them; persistent render state is real, but an extra publish/submit token layer is not: `renderer/mod.rs:177-191`; `renderer/text/mod.rs:49-95`, `111-172`; `renderer/text/glyph_cache.rs:42-99`; `renderer/text/atlas.rs:33-61`, `118-140`.
- TigerBeetle pressure rejects the current duplicate middle layer because the same consequence is represented twice and revalidated through separate state paths instead of one smallest true owner path: `TIGER_STYLE.md:37-60`, `90-123`, `158-176`, `179-184`.

Compact Anchor Map

- Howl `vt_sfc` input owner today:
  - `howl-render/src/tv_surface/vt.zig:103-174`
  - `howl-render/src/tv_surface/slot.zig:68-192`
  - `howl-render/src/tv_surface/prepare_request.zig:37-241`
- Howl `rdr_sfc` output owner today, but named as `prepared`:
  - `howl-render/src/prepared/surface.zig:23-80`
  - `howl-render/src/prepared/handle.zig:62-200`
  - `howl-render/src/prepared/render_surface_emitter.zig:257-360`
- Howl oversized session handoff seam:
  - `howl-render/src/session/text.zig:441-445`, `648-729`
  - `howl-render/src/session/submitted.zig:27-84`
  - `howl-render/include/howl_render.h:560-617`
  - `howl-linux-host/src/terminal/render/retained.zig:176-265`
- Nearest Alacritty boundary:
  - content owner: `display/content.rs:27-39`, `153-185`
  - display draw spine: `display/mod.rs:783-879`
  - renderer text owner: `renderer/text/mod.rs:49-95`, `111-172`
  - persistent glyph/atlas state: `renderer/text/glyph_cache.rs:42-99`; `renderer/text/atlas.rs:33-61`
- Exact mismatch:
  - Alacritty: content owner -> renderer owner.
  - Howl today: `vt_sfc` owner -> prepare request -> prepared handle that already has `rdr_sfc` payload -> publish token mailbox -> submit handle reacquisition -> submit.

Owner Roles And Proposed Shape

- `vt_sfc` remains the input owner seam.
  - Real owner today: `tv_surface/*` plus `PrepareRequests`.
  - First-cut direction: rename this seam explicitly toward `vt_sfc` in owner names touched by the slice, but do not redesign publication semantics.
- `rdr_sfc` becomes the output owner seam.
  - Real owner today: `prepared/surface.zig`, `prepared/handle.zig`, `prepared/render_surface_emitter.zig`.
  - First-cut direction: treat this as the one render output owner and stop routing it through token-only publish state.
- `session` stays only as long-lived render state owner.
  - Real owner today: `TextSessionOwner` holds font state, geometry, VT publication state, and submit bookkeeping.
  - First-cut direction: keep persistent render state, but delete the fake publish/submit middle state that duplicates the output handle.
- `contract` stays text-internal for this cut.
  - Real owner today: `text/contract.zig` feeds shaping and scene building.
  - First-cut direction: do not edit `text/contract.zig` in slice one, but eliminate `contract` from the touched public/API seam so it no longer names or structures the first render API cut.

Sprint Scratchpad

- Core problem: the render API already materializes `rdr_sfc`, then pays a second state-machine cost to pretend the real output is still only a token.
- Why this is the first cut:
  - It deletes a fake middle layer with direct current-source proof.
  - It moves Howl closer to Alacritty's pragmatic content->renderer path without violating the embeddable boundary.
  - It is smaller and more accountable than a whole `contract` rename or a whole renderer rewrite.
- Why this is not a fake small cut:
  - It changes the live prepare/publish/submit contract, the host call path, and the owner state model.
  - It removes exported API surface instead of wrapping it.

Exact Mismatch Statement For The Chosen First Slice

- `PreparedHandle.create` already produces the `rdr_sfc` payload, but `publishPreparedHandle` plus `Submitted.submit_mailbox` republish only `PreparedSurfaceToken`, and `takeSubmitHandle` later reconstructs the same submit candidate by rejoining mailbox token state with a cached handle pointer.
- That split has no Alacritty pressure, adds state duplication, hides the true output owner behind `prepared` language, and forces the host to hand the same handle back to the session before the session will return it again.

Exact Symbols Or Namespaces To Delete, Collapse, Or Rename In The First Slice

- Delete exported ABI entrypoints:
  - `howl_render_text_session_publish_prepared`
  - `howl_render_text_session_publish_prepared_handle`
  - `howl_render_text_session_take_submit_decision`
- Delete owner methods:
  - `TextSessionOwner.publishPrepared`
  - `TextSessionOwner.publishPreparedHandle`
  - `Submitted.publishPrepared`
- Delete duplicated state:
  - `TextSessionOwner.prepared_publish_handle`
  - `TextSessionOwner.prepared_submit_handle`
  - `Submitted.submit_mailbox`
- Collapse owner flow:
  - `TextSessionOwner.takeSubmitHandle` becomes the only submit-readiness gate and validates the one cached `rdr_sfc` handle directly against latest `vt_sfc` / submitted-base facts.
- Exact first-slice naming rule:
  - no touched public C ABI symbol, touched FFI function, touched session method, touched host retained symbol, or touched docs line may keep the noun `prepared_surface` or ambiguous bare `surface` for the live input/output seam.
  - touched input-side nouns must read as `vt_sfc` or a reviewer-acceptable explicit VT-surface name.
  - touched output-side handle nouns must read as `rdr_sfc`.
  - exact first-slice public output noun: `HowlRenderRdrSfcHandle` in C-facing seams and `rdr_sfc_handle` in Zig-facing touched seams.
- Exact `contract` consequence for this slice:
  - `text/contract.zig` is not edited, but no touched public/API seam file may newly depend on it or use it as the naming source for the live input/output boundary.
  - in the allowed files, the public seam must be expressed through `vt_sfc`/`rdr_sfc` truth, not `contract` truth.

Explicit Ordered Slice Plan

1. Slice id: `render-api-vt-sfc-rdr-sfc-first-cut`

Allowed files

- `howl-render/include/howl_render.h`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/ffi/submission.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/ffi/work_state.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/session/submitted.zig`
- `howl-render/src/prepared/handle.zig`
- `howl-render/src/prepared/surface.zig`
- `howl-render/src/ffi/submission_test.zig`
- `howl-render/src/session/text_test.zig`
- `howl-render/src/ffi/test_support.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `docs/render-surface.md`

Required shape

- `prepare_handle` still creates the output handle, but the host stops republishing it back into the session.
- The session keeps at most one live submit candidate `rdr_sfc_handle` for the latest output.
- Submit validation reads the live candidate handle directly and compares its token against:
  - latest `vt_sfc` token
  - current submitted-base token when partial reuse is required
- `Submitted` keeps only submitted-base truth and validation helpers; it no longer owns pending `rdr_sfc` work.
- The host retained owner stores the `rdr_sfc_handle` after prepare and asks the session only whether that same handle is still submit-eligible.
- Output naming in touched code must read as `vt_sfc` input and `rdr_sfc` output, not ambiguous bare `surface` when the noun is specifically input or output.
- Touched public seam names must not retain `prepared_surface`.

Exact tests

- `zig build test` for `howl-render` unit and ABI roots already covering:
  - `howl-render/src/ffi/submission_test.zig`
  - `howl-render/src/session/text_test.zig`
  - `howl-render/src/ffi/prepared_surface_test.zig`
  - `howl-render/src/ffi/vt_surface_test.zig`
- Add or update exact proofs:
  - session returns submit-ready only for the currently retained `rdr_sfc_handle`
  - stale latest `vt_sfc` publication invalidates the cached `rdr_sfc` handle without mailbox state
  - partial submit still demands the correct submitted retained base
  - host retained flow works without calling publish-prepared ABI
  - removed ABI symbols are absent from header/export/tests

Exact non-goals

- no whole-renderer rewrite
- no `text/contract.zig` owner split or mass rename
- no `surface_preparer` algorithm rewrite
- no geometry or VT publication redesign
- no compatibility shims for deleted publish-prepared entrypoints
- no leaving `prepared_surface` as the touched public handle noun

Exact stop conditions

- stop if the worker cannot express submit-readiness from one cached `rdr_sfc` handle plus existing latest/submitted tokens
- stop if the slice broadens into `text/contract.zig` interior churn unrelated to the API seam
- stop if touched naming still hides whether a symbol is `vt_sfc` input or `rdr_sfc` output
- stop if any touched public/API seam symbol still uses `prepared_surface` after the slice

Exact receipt fields

- orchestrator session id
- researcher session id
- reviewer session id
- coder session id
- commit hash
- exact removed ABI symbols
- exact tests run and results

Required Assertions

- assert the one cached submit candidate belongs to the current session before any submit path continues
- assert the session never returns a submit-ready handle whose token is older than latest `vt_sfc` publication
- assert partial `rdr_sfc` output still points at the required submitted base sequence before submit succeeds
- assert host retained owner never stores more than one live prepared output handle for the session path touched by the slice

Required Tests

- positive: latest prepared handle submits without publish mailbox hop
- negative: stale prepared handle is rejected after newer `vt_sfc` publication wins
- negative: mismatched-session handle is rejected
- negative: partial output with wrong base is rejected and requests full prepare
- ABI/header proof: deleted publish-prepared declarations and exports are gone

Risks

- Public C ABI rename pressure is adjacent to this slice. If the team decides to rename handle nouns in the same cut, header, FFI, host cimport, and docs all move together.
- `prepared_surface` is still the public noun today. This slice explicitly replaces the touched public handle noun with `HowlRenderRdrSfcHandle`; if that rename proves broader than the allowed files, the worker must stop.
- Host retained code currently assumes session-owned submit readiness. That stays true, but the call sequence changes.

Proof Gaps

- Public output-handle noun is fixed for this slice as `HowlRenderRdrSfcHandle`, specifically to avoid collision with the borrowed `HowlRenderSurface` output struct.
- `tv_surface` folder/file names are still spelled `tv_surface` in current source even though the live noun is VT. The first slice can rename touched owner-local symbols, but a full folder rename likely belongs to the next naming-only cut.
- `text/contract.zig` remains large and generic. Current proof says it is not the first seam to cut, but it will need a later owner split once the outer API path is simplified.

Readiness Judgment

- Ready for reviewer on one first slice.
- Confidence: high on the `prepared` plus `session` delete/collapse direction.
- Confidence: medium on downstream blast radius, but the first-slice public output noun is now fixed and no longer open.
