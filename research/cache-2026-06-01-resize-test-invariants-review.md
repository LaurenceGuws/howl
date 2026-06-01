# Resize Test Invariants Review Cache

Role: Reviewer Agent.

Date: 2026-06-01.

Scope: Missing or wrong testable invariants for the window resize -> geometry sync -> render prepare -> host GL resource realization -> host texture upload -> present ack path.

## Findings

1. Missing end-to-end resize-to-present state-machine test.

   Existing tests validate isolated pieces only: surface layout change detection in `howl-linux-host/src/terminal/render/retained.zig:1814`, present token monotonicity in `howl-linux-host/src/display/display.zig:693`, render-surface validation in `howl-linux-host/src/terminal/render/retained.zig:1950`, and submit mutex/upload behavior in `howl-linux-host/src/terminal/context.zig:1755`. No test drives `Context.resize()` at `howl-linux-host/src/terminal/context.zig:190`, `surface_layout.maybeCommitGridResizeLocked()` at `howl-linux-host/src/terminal/render/surface_layout.zig:93`, render geometry sync at `howl-render/src/session/text.zig:524`, prepare at `howl-linux-host/src/terminal/context.zig:497`, host upload at `howl-linux-host/src/terminal/context.zig:553`, submit at `howl-linux-host/src/terminal/context.zig:752`, present submit at `howl-linux-host/src/app/present.zig:37`, and ack at `howl-linux-host/src/terminal/context.zig:1159` in one state-machine.

   TigerBeetle proof pattern: IO/state-machine tests drive the whole callback chain until completion and assert terminal state, not just local helpers, in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:41`, `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:70`, `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:72`, and `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:74`.

2. Resize geometry epoch correctness is not proved across host and render owners.

   `surface_layout.resize()` mutates pending render/grid sizes at `howl-linux-host/src/terminal/render/surface_layout.zig:56`, commits pending grid size at `howl-linux-host/src/terminal/render/surface_layout.zig:93`, and `State.syncSurfaceLayout()` calls C ABI geometry sync at `howl-linux-host/src/terminal/render/retained.zig:655`. `GeometryOwner.sync()` increments `geometry_epoch` on any render/grid/cell change at `howl-render/src/render/geometry.zig:10`. Existing tests only assert layout diff flags in `howl-linux-host/src/terminal/render/retained.zig:1814`.

   Missing invariant: after resize, exactly one non-zero `geometry_epoch` is observed by host retained state, render session owner, prepare request token, prepared info, render surface token, and submit result.

   TigerBeetle proof pattern: monotonic sequence and no-regression assertions after each transition in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:197`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:249`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:261`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:274`.

3. Prepared token and render-surface token are not tied tightly enough in tests.

   `acceptPrepared()` asserts prepared info matches the request at `howl-linux-host/src/terminal/render/retained.zig:908`, and `resetPrepared()` writes render-surface token fields at `howl-render/src/prepared/render_surface_emitter.zig:411`. Existing tests check token diagnostics in host texture diagnostics at `howl-linux-host/src/display/renderer/render_surface.zig:1833`, but not that a resize-generated request produces a surface token whose `snapshot_seq`, `surface_seq`, and `geometry_epoch` match the active prepared owner and host submit decision.

   Missing invariant: `surface.token.snapshot_seq == prepared.info.snapshot_seq`, `surface.token.geometry_epoch == prepared.info.geometry_epoch`, `surface.token.surface_seq == prepared.info.dirty_epoch`, and no zero token values after bootstrap.

   TigerBeetle proof pattern: every generated quorum state asserts exact result/error in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:212` and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:215`.

4. Stale prepared state after resize is under-tested.

   `acceptSubmitted()` forces full prepare if submitted geometry differs from current geometry at `howl-render/src/session/text.zig:609`, and `Submitted.prepareTokenForRetainedState()` forces full when retained base geometry mismatches at `howl-render/src/session/submitted.zig:86`. Existing tests cover stale latest snapshot in `howl-render/src/session/submitted.zig:155`, but not resize after prepare before submit.

   Missing invariant: if resize occurs after prepare but before submit, the old prepared handle must not submit; it must produce stale/needs-prepare behavior, release or retire pending state, and request a full prepare for the new geometry.

   TigerBeetle proof pattern: crash/recovery verification after each write prevents stale state from winning in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:213`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:231`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:246`.

5. Host GL surface lifecycle after resize is not proved.

   `ensureSurface()` deletes the old texture when dimensions differ at `howl-linux-host/src/display/renderer/render_surface.zig:2056`, zeros width/height before allocation at `howl-linux-host/src/display/renderer/render_surface.zig:2060`, and restores width/height only after `glTexImage2D` succeeds at `howl-linux-host/src/display/renderer/render_surface.zig:2085`. No unit test uses a fake GL backend to assert old texture deletion, new texture dimensions, failure rollback, and no stale `host_surface_id` reuse across resize.

   TigerBeetle proof pattern: cancellation tests assert no further buffer mutation after cancel/failure in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:809`, `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:828`, and `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:844`.

6. Render resource realization and host texture upload are not tested as one transactional boundary.

   `ContextSubmitBackend.upload()` realizes render-surface resources at `howl-linux-host/src/terminal/context.zig:553`, ensures the host surface at `howl-linux-host/src/terminal/context.zig:574`, uploads commands at `howl-linux-host/src/terminal/context.zig:582`, and invalidates host dimensions on upload failure at `howl-linux-host/src/terminal/context.zig:592`. Existing tests validate `RenderResourceStore.applySurface()` fail-closed behavior in `howl-linux-host/src/terminal/render/retained.zig:2515`, operation recorder behavior in `howl-linux-host/src/terminal/render/retained.zig:2755`, and host upload failure not submitting in `howl-linux-host/src/terminal/context.zig:1791`, but not the combined resource-realization-plus-host-upload path.

   Missing invariant: no submit if realization fails, no submit if host upload fails, no stale host dimensions after failure, and render resource slots remain rolled back or correctly retired.

   TigerBeetle proof pattern: fail-closed and no mutation on invalid input in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:849` and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:216`.

7. Resource epoch/token correctness is currently wrong or unproved.

   `render_surface_emitter.resetPrepared()` hard-codes `.resource_epoch = 0` at `howl-render/src/prepared/render_surface_emitter.zig:411`, while host diagnostics record `resource_epoch` at `howl-linux-host/src/display/renderer/render_surface.zig:123`. Tests accept arbitrary token values in `howl-linux-host/src/display/renderer/render_surface.zig:1863`, but no test asserts what `resource_epoch` means or that it changes when retained sprite/atlas resources change.

   Missing invariant: either `resource_epoch` must be intentionally zero with a documented C ABI meaning and tests proving host ignores it, or it must monotonically track retained render resource lifecycle.

   TigerBeetle proof pattern: hash/sequence fields are not decorative; tests assert parent/checksum/sequence relationships in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:349`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:356`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:363`.

8. Present ack path is locally tested but not connected to submitted render state.

   `recordSubmissionFor()` stores terminal present token at `howl-linux-host/src/app/present.zig:54`, `drainComplete()` routes matching display completion at `howl-linux-host/src/app/present.zig:77`, and `completePresentLockedWith()` acks VT publication at `howl-linux-host/src/terminal/context.zig:1159`. Existing tests cover matching/mismatched present tokens in `howl-linux-host/src/app/present.zig:423` and `howl-linux-host/src/terminal/context.zig:1834`, but not that the ack unblocks retained submit, retires pending sources, and allows the next resized frame to submit.

   Missing invariant: before ack, `workState.present_pending == true` and submit is blocked; wrong token leaves it blocked; matching token clears it, acks exactly the submitted snapshot, retires pending state, and next render turn can submit.

   TigerBeetle proof pattern: state-machine tests assert pending counts and callback identity before and after transitions in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:176`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:221`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:280`.

9. Retry/failure behavior for prepare after resize is not sufficiently proved.

   `TextSessionOwner.prepareHandle()` retries a taken prepare on `errdefer` at `howl-render/src/session/text.zig:439`, `PrepareRequests.retryTakenPrepare()` clears `taken` at `howl-render/src/source/prepare_request.zig:150`, and host `State.prepare()` releases prepared surface on idle/failure at `howl-linux-host/src/terminal/render/retained.zig:721`. Existing tests do not force prepare-handle failure after resize and then assert the same token can be prepared again without losing the pending publication.

   TigerBeetle proof pattern: queue-full and cancel tests force operating edge cases and assert final completion counts in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:406`, `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:430`, and `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:433`.

10. Debug counter truthfulness is local, not path-backed.

   Render texture diagnostics record tokens and counts at `howl-linux-host/src/display/renderer/render_surface.zig:521`, host retained probe counters at `howl-linux-host/src/terminal/render/retained.zig:861`, resource plan counters at `howl-linux-host/src/terminal/render/retained.zig:871`, and present diagnostics at `howl-linux-host/src/display/display.zig:303`. Existing tests assert isolated counters in `howl-linux-host/src/display/renderer/render_surface.zig:1833`, `howl-linux-host/src/terminal/render/retained.zig:2062`, `howl-linux-host/src/terminal/render/retained.zig:2475`, and `howl-linux-host/src/display/display.zig:722`.

   Missing invariant: after one resize-render-present cycle, counters must agree with actual observed operations: one prepare probe success, one resource plan success, one texture realization attempt, one host upload success, one present submit, one matching present completion, and no failure counters.

   TigerBeetle proof pattern: tests assert both payload result and side counters, for example IO transfer counts in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:679` and `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:680`.

11. Retained resource state is duplicated across host test store and GL texture store without a cross-check.

   The test-only `RenderResourceStore` validates retained lifecycle at `howl-linux-host/src/terminal/render/retained.zig:236`, while production GL store `RenderResourceTextures` mutates slots at `howl-linux-host/src/display/renderer/render_surface.zig:31`. Existing tests prove both separately, but no test asserts that the operation recorder from `RenderResourceStore.applySurfaceWithRecorder()` corresponds to GL create/upload/retire effects in `RenderResourceTextures.realizeSurface()`.

   Missing invariant: for the same surface, planned operations and realized GL diagnostics must match create/upload/retire counts and resource IDs.

   TigerBeetle proof pattern: repair tests compare independent views of the same state after every mutation in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:234`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:239`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:263`.

12. Partial/patch frames after host surface resize are risky and under-proved.

   `ContextSubmitBackend.uploadRenderSurfaceCommands()` only allows sprite/glyph patch paths when `had_matching_surface` is true at `howl-linux-host/src/terminal/context.zig:614` and `howl-linux-host/src/terminal/context.zig:634`; fill patch lacks the same `had_matching_surface` guard at `howl-linux-host/src/terminal/context.zig:645`. Since `ensureSurface()` can create a new blank texture after resize at `howl-linux-host/src/display/renderer/render_surface.zig:2056`, a partial fill patch on a new host surface could present stale/blank regions unless the render side guarantees full damage on geometry change.

   Missing invariant: after any resize where host surface dimensions change, first uploaded render surface must be full coverage/full damage or patch upload must be rejected until there is a matching retained host surface.

   TigerBeetle proof pattern: tests explicitly cover skipped/forked/partial sequences and negative space, not just valid paths, in `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:48`, `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:56`, and `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:64`.

13. Bounds assertions do not prove framebuffer/texture upload dimensions at the end-to-end boundary.

   `snapshotSurfaceLayoutLocked()` casts clamped `c_int` dimensions to `u16` at `howl-linux-host/src/terminal/render/surface_layout.zig:140`, `ensureSurface()` asserts width/height > 0 at `howl-linux-host/src/display/renderer/render_surface.zig:2056`, and `executionMatchesPrepared()` checks host surface dimensions against prepared render size at `howl-render/src/prepared/owner.zig:373`.

   Missing invariant: resize dimensions larger than `u16` must be rejected or clamped intentionally before C ABI conversion; host surface `width/height`, prepared `render_px`, render surface `render_px`, and submit result `host_surface` must be exactly equal.

   TigerBeetle proof pattern: explicit bounds and queue capacity tests in `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:406` and `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:417`.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1` through `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:511`.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1` through `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:710`.
- `AGENTS.md:1` through `AGENTS.md:259`.
- `loop.txt:1` through `loop.txt:278`.
- `howl-linux-host/src/terminal/context.zig:1` through `howl-linux-host/src/terminal/context.zig:1917` representative sections.
- `howl-linux-host/src/terminal/render/surface_layout.zig:1` through `howl-linux-host/src/terminal/render/surface_layout.zig:202`.
- `howl-linux-host/src/terminal/render/retained.zig:1` through `howl-linux-host/src/terminal/render/retained.zig:3139` representative sections.
- `howl-linux-host/src/display/renderer/render_surface.zig:1` through `howl-linux-host/src/display/renderer/render_surface.zig:2720` representative sections.
- `howl-linux-host/src/app/present.zig:1` through `howl-linux-host/src/app/present.zig:469`.
- `howl-linux-host/src/display/display.zig:1` through `howl-linux-host/src/display/display.zig:732`.
- `howl-render/src/session/text.zig:1` through `howl-render/src/session/text.zig:792`.
- `howl-render/src/prepared/owner.zig:1` through `howl-render/src/prepared/owner.zig:1059` representative sections.
- `howl-render/src/prepared/render_surface_emitter.zig:1` through `howl-render/src/prepared/render_surface_emitter.zig:2346` representative sections.
- `howl-render/src/render/render_surface_realizer.zig:1` through `howl-render/src/render/render_surface_realizer.zig:2086` representative sections.
- `howl-render/src/render/geometry.zig:1` through `howl-render/src/render/geometry.zig:46`.
- `howl-render/src/source/prepare_request.zig:1` through `howl-render/src/source/prepare_request.zig:299`.
- `howl-render/src/session/submitted.zig:1` through `howl-render/src/session/submitted.zig:178`.

## Representative TigerBeetle Docs And Tests Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`: simple explicit control flow and bounded execution.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96`: put a limit on everything.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104`: assertions detect programmer errors.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109`: assert function arguments, return values, pre/postconditions, and invariants.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:136`: assert positive and negative space.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:179`: do not do things directly in reaction to external events; run at own pace.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:281`: determinism.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:309`: simulation testing.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:408`: control plane/data plane separation.
- `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:23`: `open/write/read/close/statx` callback chain.
- `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:406`: submission queue full.
- `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:449`: tick to wait and external completion.
- `utils/dev_references/zig_maturity/tigerbeetle/src/io/test.zig:765`: cancel_all no mutation after cancel.
- `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:20`: quorum fault matrix.
- `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_quorums_fuzz.zig:100`: repair fuzzing.
- `utils/dev_references/zig_maturity/tigerbeetle/src/vsr/superblock_fuzz.zig:213`: verify recovery after every write.

## Proposed Test Matrix

- Resize no-op: same render/logical size produces no new geometry epoch, no prepare, no host texture recreation, no present.
- Resize render-only: render size changes, grid changes, geometry epoch increments once, PTY/VT resize called once, first render surface is full coverage, host texture recreated once, submit and present ack complete.
- Resize during prepared-before-submit: prepared handle becomes stale or needs full prepare; no host submit for stale geometry; retry/full prepare uses new geometry epoch.
- Resize while present pending: new submit is blocked until matching present ack; wrong token does not ack; matching token clears pending and allows next render turn.
- Host surface creation failure: old texture is deleted or retained according to explicit contract; width/height truth remains zero on failure; no submit; failure counters truthful.
- Render resource realization failure: no host upload, no submit, created GL resources rolled back, upload metadata not committed, diagnostics bucket correct.
- Host upload failure after realization: no submit, host dimensions invalidated as intended, render resource state not silently inconsistent, retry path can render a valid full frame.
- Retained sprite/glyph resource reuse across resize: resource plan, GL texture diagnostics, and submit metrics agree; no duplicate resource value reuse; retired resources stay tombstoned.
- Partial frame on changed host surface: rejected or converted to full; no patch upload to a newly allocated host texture unless matching prior dimensions exist.
- Debug counter integration: one successful cycle asserts exact prepare/probe/resource/upload/present/ack counters and zero failure counters.

## Minimum Acceptable Next Slice

- Add a single host-level deterministic test harness that fakes the backend enough to drive one resize through `Context.renderTurn()`, `ContextSubmitBackend.upload()`, `app.present.submitWith()`, `app.present.recordSubmissionFor()`, and `app.present.drainComplete()` without real SDL/GL.
- The slice must assert geometry epoch, prepared info, render surface token, host surface dimensions, upload success, submit result, present token, ack snapshot, pending-state clearing, and debug counters for one full successful resize-to-present cycle.
- Only after that exists should failure/retry cases be added, because without the success-path state-machine proof, isolated failure tests can still pass while the actual resize-to-present contract is broken.

## Reviewer Risks And Stop Conditions

- Stop if the proposed test requires a Zig-shaped host shortcut around the C ABI boundary. Howl rule: hosts depend on `howl-pty`, `howl-vt`, `howl-render`, and vendor contracts only, not internal Zig convenience imports (`AGENTS.md:119`).
- Stop if the test changes product behavior instead of proving it. This review authorizes test/accountability work only, not product implementation.
- Stop if a fake GL/SDL backend cannot prove texture lifecycle without depending on real platform GL behavior. The test must be deterministic and owner-true.
- Stop if the test only adds isolated unit assertions and still does not drive resize -> geometry -> prepare -> realization -> upload -> submit -> present -> ack in one state-machine.
- Stop if any failure path mutates retained state before validation. Existing Howl fail-closed expectations are in `howl-linux-host/src/terminal/render/retained.zig:2515`, `howl-linux-host/src/terminal/render/retained.zig:2784`, and `howl-linux-host/src/terminal/render/retained.zig:2817`.
- Stop if `resource_epoch` remains ambiguous in new tests. It must either be proven intentionally zero/ignored or promoted to a meaningful monotonic invariant.
- Stop if partial/patch upload after host-surface resize is allowed without proving a matching retained base/host texture exists.
- Stop if debug counters are asserted only locally. Counters must be proven against actual path events.
- Stop if tests are added through duplicate test roots or side-entry test files. Howl requires each module to have one curated test entrypoint (`AGENTS.md:158`).
