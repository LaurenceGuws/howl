# Howl Render Cleanup Plan

Status: active next-slice planning after accepted ABI cursor cadence cleanup.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
Researcher session id: `research-2026-06-18-render-cleanup-next-slice-04`.
Prior researcher ids: `research-2026-06-18-render-cleanup-inventory-01`, `research-2026-06-18-render-cleanup-correction-02`, `research-2026-06-18-render-cleanup-gate-repair-03`.
Last accepted reviewer id: `review-2026-06-18-render-cleanup-abi-cadence-01`.
Reviewer id for this next-slice package: pending.
Commit-hash receipt status: prior executable slice closed as `howl-render` `864ea8b Use C cursor cadence ABI directly`, root `f84e1c8 Track cursor cadence ABI cleanup`; this artifact has no dedicated planning commit yet.

## Scope Rule

- The cleanup sprint is indefinite until deterministic evidence says no cleanup remains in `howl-render`.
- `style.py` is quantitative pressure only. It is not sufficient proof because it misses forbidden terms such as `contract`, `session`, `owner`, `context`, and `state`.
- Every executable slice must combine style pressure, forbidden tokens, dead-code/reachability, and duplicate-shape evidence where applicable.
- Passing tests are never sufficient when stale names, stale paths, dead shapes, compatibility mirrors, or fake owners remain.
- No compatibility shims, aliases, bridges, fallback names, or fake partial cleanup are allowed.

## Sources Read

Mandatory live accountability and project law, in order:

- `loop/flow.md`
- `loop/orcestrator.md`
- `loop/researcher.md`
- `loop/reviewer.md`
- `loop/coder.md`
- `loop/researcher.md` again as active role contract
- `sprints/current.txt`
- `loops/howl-render-cleanup-loop.txt`
- `research/howl-render-cleanup-plan.md` before this update
- `AGENTS.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Current source/evidence inspected in this pass:

- `style.py`
- `howl-render/src/tokens.zig`
- `howl-render/src/submitted_surface.zig`
- `howl-render/src/text/effects.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/test_unit.zig`
- `howl-render/src/test_abi.zig`
- `howl-render/src/c/work_state.zig`
- Package-root searches across `howl-render/src/**/*.zig` and `howl-render/include/**/*.h`

## Reference Anchor Map

- TigerStyle naming: `TIGER_STYLE.md:273-276` requires exact nouns and verbs; `TIGER_STYLE.md:337-347` rejects overloaded names.
- TigerStyle ownership/directness: `TIGER_STYLE.md:315-333` requires top-down order and top-level complex types; `TIGER_STYLE.md:416-429` requires narrow scope and simple dimensionality.
- TigerStyle assertions/proof: `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, positive space, and negative space.
- TigerStyle duplication: `TIGER_STYLE.md:372-387` rejects duplicate variables/aliases that can diverge and backs in-place construction for larger shapes.
- TigerBeetle architecture: `ARCHITECTURE.md:189-222` treats explicit bounds as a forcing function; `ARCHITECTURE.md:408-423` backs clear control/data-plane separation.
- Howl project law: `AGENTS.md:178-196` rejects bucket files/structs and generic `Context`, `State`, `Options`, `Info`, `Data`, `Result`, `Config`, and similar names unless source-backed and owner-true.
- Howl ABI law: `AGENTS.md:25-37`, `AGENTS.md:159-166`, and `AGENTS.md:168-176` make the C ABI the product and limit hosts to C contracts.

## Current Evidence Baseline

Whole-package style command:

```sh
python3 style.py --by-file --format json --sort prod howl-render
```

Current top style rows by `prod` after accepted first slice:

| path | prod | tests | benchmark | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 13489 | 7168 | 904 | 24159 | 314 | 172 | 66 | 2144 | 1120 | 4 | 207 | 1 | 4 |
| `howl-render/src/render_session.zig` | 832 | 128 | 0 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 0 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/raster/special_legacy_computing.zig` | 725 | 0 | 0 | 776 | 2 | 0 | 0 | 124 | 37 | 2 | 0 | 0 | 0 |
| `howl-render/src/surface/emitter.zig` | 717 | 0 | 0 | 784 | 79 | 0 | 0 | 18 | 15 | 1 | 2 | 0 | 0 |
| `howl-render/src/surface/realizer.zig` | 713 | 0 | 0 | 788 | 1 | 3 | 4 | 46 | 49 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/cursor_trail.zig` | 137 | 50 | 0 | 213 | 4 | 2 | 1 | 26 | 9 | 0 | 3 | 1 | 4 |
| `howl-render/src/tokens.zig` | 127 | 62 | 0 | 230 | 0 | 0 | 0 | 2 | 9 | 0 | 5 | 0 | 0 |
| `howl-render/src/submitted_surface.zig` | 81 | 50 | 0 | 154 | 2 | 0 | 0 | 4 | 10 | 0 | 3 | 0 | 0 |
| `howl-render/src/text/effects.zig` | 32 | 16 | 0 | 55 | 0 | 0 | 0 | 14 | 0 | 0 | 1 | 0 | 0 |

Forbidden-token content command:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
```

Current package-root token totals:

| token | content files | content lines | path files |
| --- | ---: | ---: | ---: |
| `contract` | 51 | 1177 | 3 |
| `session` | 33 | 707 | 5 |
| `owner` | 22 | 269 | 0 |
| `pipeline` | 0 | 0 | 0 |
| `context` | 3 | 71 | 0 |
| `state` | 21 | 396 | 1 |
| `options` | 8 | 138 | 0 |
| `config` | 20 | 202 | 0 |
| `info` | 9 | 48 | 0 |
| `data` | 3 | 26 | 0 |
| `result` | 19 | 139 | 0 |
| `manager` | 0 | 0 | 0 |
| `controller` | 0 | 0 | 0 |
| `types` | 0 | 0 | 0 |
| `utils` | 0 | 0 | 0 |
| `helper` | 1 | 1 | 0 |
| `support` | 20 | 270 | 3 |

Current forbidden-token path matches:

```text
howl-render/src/geometry_contract.zig
howl-render/src/c/text_session_handle.zig
howl-render/src/c/test_support.zig
howl-render/src/c/text_session_test.zig
howl-render/src/c/work_state.zig
howl-render/src/c/text_session.zig
howl-render/src/text/contract.zig
howl-render/src/render_session.zig
howl-render/src/text/session.zig
howl-render/src/text/scene_contract.zig
howl-render/src/text/ft_hb/support.zig
howl-render/src/text/ft_hb/support_test.zig
```

Reachability command template:

```sh
rg -n '\bSYMBOL\b' howl-render/src howl-render/include
```

Current deterministic dead/self-test-only findings:

- `tokens.PreparedSurfaceTokenWith`: declaration `howl-render/src/tokens.zig:61-80`; only current outside-declaration use is its own local test at `howl-render/src/tokens.zig:200-216`. Classification: `self-test-only`, delete with that local test.
- `tokens.RenderResult`: declaration `howl-render/src/tokens.zig:102-107`; no product/test use outside the declaration. Classification: `dead`, delete.
- `tokens.FullPrepareReason`: declaration `howl-render/src/tokens.zig:109-113`; only reached by dead `RenderResult`, dead `submitted_surface.SubmitDecision`, and dead `submitted_surface.fullPrepareReason`. Classification: `dead`, delete after deleting those dependents.
- `tokens.SurfaceLostReason`: declaration `howl-render/src/tokens.zig:115-119`; only payload of dead `RenderResult`. Classification: `dead`, delete.
- `tokens.LatestMailbox`: declaration `howl-render/src/tokens.zig:121-155`; only current outside-declaration use is its own local test at `howl-render/src/tokens.zig:218-230`. Classification: `self-test-only`, delete with that local test.
- `tokens.ThreadMutex` and `tokens.lockMutex`: `howl-render/src/tokens.zig:3-13`; exist only for `LatestMailbox`. Classification: `dead after LatestMailbox deletion`, delete.
- `submitted_surface.SubmitDecision`: declaration `howl-render/src/submitted_surface.zig:16-21`; no use outside declaration. Classification: `dead`, delete.
- `submitted_surface.SubmittedWorkState`: declaration `howl-render/src/submitted_surface.zig:23-25`; only current use is `SubmittedSurface.workState` at `howl-render/src/submitted_surface.zig:49-54` and local assertion at `howl-render/src/submitted_surface.zig:137-141`. The live C ABI work-state path uses `render_session.TextSessionOwner.workState` through `howl-render/src/c/work_state.zig:6-17`, not `SubmittedSurface.workState`. Classification: `self-test-only`, delete with method/test assertion.
- `submitted_surface.fullPrepareReason`: declaration `howl-render/src/submitted_surface.zig:81-88`; no use outside declaration. Classification: `dead`, delete.
- `text.effects.BackendCaps`: declaration `howl-render/src/text/effects.zig:11-16`; only current uses are re-export at `howl-render/src/text/contract.zig:15` and its own local defaults test at `howl-render/src/text/effects.zig:39-45`. Classification: `self-test-only plus unused re-export`, delete declaration, re-export, and test.

Duplicate-shape evidence still active after the accepted first slice:

- Thread mutex wrapper appears in `howl-render/src/tokens.zig:3-13`, `howl-render/src/submitted_surface.zig:4-14`, `howl-render/src/text/ft_hb/support.zig:26-33`, and `howl-render/src/render_session.zig:52-63`. The `tokens.zig` copy is deletable now because it exists only for `LatestMailbox`; remaining copies require lifecycle-owner review and are not part of this slice.
- Cursor presentation split, cursor trail rect limit duplication, fallback font limit duplication, and scene contract aggregation remain live later slices. They are not required to delete the dead/self-test-only shapes above.

## Ordered Cleanup Plan

1. Accepted: ABI cursor cadence mirror deletion closure. Product receipt: `howl-render` `864ea8b`; root receipt: `f84e1c8`.
2. Active next slice: dead/self-test-only deletion across `tokens.zig`, `submitted_surface.zig`, `text/effects.zig`, and the one unused `BackendCaps` re-export in `text/contract.zig`.
3. Cursor-trail bucket cleanup: remove `text/cursor_trail.zig` `Config` bucket by passing exact decay fields or replacing it with an owner-true noun if the slice proves one. The `style.py` bucket count must reach zero for allowed files.
4. Cursor duplicate/limit cleanup: unify cursor presentation payload names and cursor trail limit ownership without adding compatibility aliases. This must remove the second ambiguous `CursorPresentation` noun or rename both roles exactly.
5. Metric/token dominant render-session slice: split or rename only source-proved lifecycle pieces in `render_session.zig`, with before/after style row and forbidden-token row. No broad new runtime or manager layer.
6. `text/ft_hb/support.zig` cleanup: rename/split `support` into exact FT/HB owners and remove fake support terminology, with package-root path scan proving no `support` product owner remains unless test-only and justified.
7. Text scene contract cleanup: split `text/scene_contract.zig`, reduce `contract` imports in `scene_rects.zig`, `scene.zig`, `lane.zig`, `shape/cluster.zig`, and `surface_preparer.zig`, and preserve only curated re-export roots where exact.
8. Long-function/cast-heavy renderer cleanup: target `text/raster/special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, and `text/scene_rects.zig` using metric deltas plus owner-local tests. Long functions in product files must trend to zero.
9. Test-support cleanup: shrink `src/c/test_support.zig` aliases and move proof helpers to owner-local tests where still needed.
10. Benchmark cleanup: rename benchmark-only bucket nouns in `benchmark_main.zig` after product/ABI cleanup, without hiding benchmark proof inside unit/ABI roots.

The sprint remains live after each slice. The orchestrator/reviewer must rerun the four evidence lanes and choose the next strongest deterministic target from remaining metrics/tokens/reachability/duplicates.

## Active Executable Slice

Name: dead/self-test-only render shape deletion.

Why this is the strongest next slice:

- The first safe ABI closure slice is accepted and committed; the forcing gates require the next target to attack remaining deterministic lanes instead of feature work.
- This slice deletes known-unreachable shapes before renaming live owners, which follows accountability and safety: no worker invention, no folder moves, no ABI choices, no user approval needed.
- It removes concrete `Result`, `State`, `Config`, and duplicate mutex pressure from current source while preserving live render behavior.
- It lowers `style.py` product/proof/struct/function counts in allowed files and should not increase any metric.
- It leaves metric-dominant live owners (`render_session.zig`, `text/ft_hb/support.zig`, scene contract files) for later slices because those require exact owner reshaping, not deletion.

Allowed files:

- `howl-render/src/tokens.zig`
- `howl-render/src/submitted_surface.zig`
- `howl-render/src/text/effects.zig`
- `howl-render/src/text/contract.zig`
- `research/howl-render-cleanup-plan.md` only for execution receipt updates if the orchestrator asks after review
- `loops/howl-render-cleanup-loop.txt` only for required teammate note after execution/review

Required changes:

- In `howl-render/src/tokens.zig`, delete `ThreadMutex`, `lockMutex`, `PreparedSurfaceTokenWith`, `RenderResult`, `FullPrepareReason`, `SurfaceLostReason`, `LatestMailbox`, test `prepared surface token payload keeps validation in the header`, and test `latest mailbox drops stale work`.
- Preserve live `DamageKind`, `SnapshotToken`, `RenderRequest`, `PreparedSurfaceToken`, `SubmittedSurfaceToken`, `SubmitValidation`, `validatePreparedSurfaceToken`, and their existing tests.
- In `howl-render/src/submitted_surface.zig`, delete `SubmitDecision`, `SubmittedWorkState`, `SubmittedSurface.workState`, and `SubmittedSurface.fullPrepareReason`.
- In `howl-render/src/submitted_surface.zig`, replace test `submitted owner has no vt surface state` with `test "submitted surface starts without submitted token"` containing only `var submitted = SubmittedSurface{};` and `try std.testing.expect(submitted.submittedToken() == null);`.
- In `howl-render/src/text/effects.zig`, delete `BackendCaps` and test `effect defaults are deterministic`.
- In `howl-render/src/text/contract.zig`, delete `pub const BackendCaps = effects.BackendCaps;` and leave all live effect enum re-exports intact.
- Do not add replacement structs, aliases, compatibility names, helper wrappers, or new test roots.

Required reachability/deletion searches after the change:

```sh
rg -n '\b(PreparedSurfaceTokenWith|RenderResult|FullPrepareReason|SurfaceLostReason|LatestMailbox)\b' howl-render/src howl-render/include
rg -n '\b(SubmitDecision|SubmittedWorkState|BackendCaps)\b' howl-render/src howl-render/include
rg -n '\bfullPrepareReason\b|\.workState\(' howl-render/src/submitted_surface.zig
rg -n '\b(ThreadMutex|lockMutex)\b' howl-render/src/tokens.zig
rg -n 'pub const BackendCaps = effects\.BackendCaps' howl-render/src/text/contract.zig
```

Expected search result:

- First command returns no matches.
- Second command returns no matches.
- Third command returns no matches in `submitted_surface.zig`; live `workState` in `render_session.zig` and `c/work_state.zig` is not searched by this command and must not be changed.
- Fourth command returns no matches in `tokens.zig`; duplicate mutex wrappers outside `tokens.zig` remain explicitly out of scope.
- Fifth command returns no matches.

Metric recording required before and after:

```sh
python3 style.py --by-file --format json --sort prod howl-render
python3 style.py --by-file --format json --sort path howl-render/src/tokens.zig howl-render/src/submitted_surface.zig howl-render/src/text/effects.zig howl-render/src/text/contract.zig
```

Current allowed-file metric baseline:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 305 | 134 | 517 | 2 | 0 | 0 | 20 | 19 | 0 | 9 | 0 | 0 |
| `howl-render/src/tokens.zig` | 127 | 62 | 230 | 0 | 0 | 0 | 2 | 9 | 0 | 5 | 0 | 0 |
| `howl-render/src/submitted_surface.zig` | 81 | 50 | 154 | 2 | 0 | 0 | 4 | 10 | 0 | 3 | 0 | 0 |
| `howl-render/src/text/effects.zig` | 32 | 16 | 55 | 0 | 0 | 0 | 14 | 0 | 0 | 1 | 0 | 0 |
| `howl-render/src/text/contract.zig` | 65 | 6 | 78 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Expected metric consequence:

- Allowed-files `(sum)` `lines`, `prod`, `proof`, `funcs`, and `structs_top_level` decrease.
- `howl-render/src/tokens.zig` `structs_top_level` decreases by at least `3`; `funcs` decreases by at least `5`; `proof` decreases only for deleted self-test-only proof.
- `howl-render/src/submitted_surface.zig` `structs_top_level` decreases by at least `2`; `funcs` decreases by at least `2`.
- `howl-render/src/text/effects.zig` `structs_top_level` decreases by `1`; `proof` decreases only for deleted self-test-only proof.
- No allowed file may increase `usizes`, `anytypes`, `long_funcs`, `bucket_named_structs`, or `bucket_struct_lines`.

Forbidden-token recording required before and after:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src/tokens.zig howl-render/src/submitted_surface.zig howl-render/src/text/effects.zig howl-render/src/text/contract.zig
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Current allowed-file forbidden-token baseline:

| file | hits |
| --- | --- |
| `howl-render/src/tokens.zig` | `state:5`, `result:2` |
| `howl-render/src/submitted_surface.zig` | `owner:13`, `state:8` |
| `howl-render/src/text/effects.zig` | `config:2` |
| `howl-render/src/text/contract.zig` | `contract:34`, `owner:1` |

Expected forbidden-token consequence:

- `tokens.zig` `result` decreases to `0`; `state` decreases when the local mutex state is deleted.
- `submitted_surface.zig` `state` decreases when `SubmittedWorkState` and the local `workState` method/test use are deleted.
- `text/effects.zig` `config` decreases to `0` when `BackendCaps` is deleted.
- `text/contract.zig` keeps its broader `contract` pressure for a later scene-contract slice but loses the unused `BackendCaps` re-export line.
- Package-root path-scan total remains `12` because this slice does not rename path-level `contract`, `session`, `state`, or `support` files.
- Any forbidden-token increase in allowed files blocks the slice unless the reviewer explicitly accepts a test-name-only decrease/increase tradeoff backed by exact output.

Required tests:

- `zig build test:unit` in `howl-render`
- `zig build test:abi` in `howl-render`
- `zig build check` in `howl-render`
- `zig build check` at workspace root after package check passes

Non-goals:

- Do not touch `render_session.zig`, `text/ft_hb/support.zig`, `text/cursor_trail.zig`, scene contract files, C ABI files, shipped headers, build files, or README files.
- Do not rename live `workState` C ABI or `render_session.TextSessionOwner.workState` behavior.
- Do not merge or rename remaining mutex wrappers outside `tokens.zig`.
- Do not alter retained-base validation behavior or submitted-token behavior.
- Do not add new folders, move files, add compatibility aliases, or create aggregate re-export roots.
- Do not change shipped C ABI names or layouts.

Stop conditions:

- Any required deletion search still finds one of the targeted dead/self-test-only names after the change.
- Worker finds product reachability for a targeted symbol outside the current source evidence above.
- Worker needs to touch files outside the allowed list to keep tests passing.
- Any C ABI header or host-visible layout change appears necessary.
- Any retained live behavior test must be weakened instead of updated to prove only retained behavior.
- Metrics or forbidden-token counts increase in an allowed file outside a reviewer-accepted test-name-only exception.

Receipt fields required:

- Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
- Researcher session id: `research-2026-06-18-render-cleanup-next-slice-04`.
- Reviewer session id that accepts this next-slice package.
- Coder/worker session id.
- Commit hash for accepted implementation or explicit open commit-hash handoff status.
- Before/after metric rows for whole-package `(sum)` and all allowed product files.
- Before/after forbidden-token evidence for allowed files, package-root content totals, and package-root path-scan matches.
- Results for all required tests and all deletion/reachability searches.

## Next-Slice Forcing Gates

After this dead/self-test-only deletion slice is accepted, the next planning/execution seed must choose from these remaining deterministic targets unless fresh evidence shows a stronger one:

- `style.py` bucket offender `text/cursor_trail.zig:13-16`.
- Duplicate cursor presentation and cursor limit shapes.
- Forbidden-token dominant files `render_session.zig`, `text/ft_hb/support.zig`, `text/surface_preparer.zig`, `text/scene.zig`, `text/shape/cluster.zig`, `text/scene_rects.zig`, and `text/direct_normal.zig`.
- Scene contract aggregation in `text/scene_contract.zig` and `text/contract.zig`.

The sprint cannot be declared complete until all four lanes produce either clean negative results or explicit, source-backed retained-shape receipts in this artifact or its accepted successor.
