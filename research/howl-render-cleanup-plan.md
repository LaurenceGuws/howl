# Howl Render Cleanup Plan

Status: active next-slice planning after accepted cursor-trail `Config` deletion.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
Researcher session id: `research-2026-06-18-render-cleanup-next-slice-06`.
Prior researcher ids: `research-2026-06-18-render-cleanup-inventory-01`, `research-2026-06-18-render-cleanup-correction-02`, `research-2026-06-18-render-cleanup-gate-repair-03`, `research-2026-06-18-render-cleanup-next-slice-04`, `research-2026-06-18-render-cleanup-next-slice-05`.
Last accepted reviewer id: `review-2026-06-18-render-cleanup-cursor-trail-config-02`.
Reviewer id for this next-slice package: pending.
Commit-hash receipt status: accepted executable slices closed as `howl-render` `864ea8b Use C cursor cadence ABI directly`, root `f84e1c8 Track cursor cadence ABI cleanup`; `howl-render` `7af878b Delete dead render shapes`, root `6d0e393`; `howl-render` `d7f93b7 Delete cursor trail config bucket`, root `398da7f`. This planning update has no dedicated planning commit yet.

## Scope Rule

- The cleanup sprint is indefinite until deterministic evidence says no cleanup remains in `howl-render`.
- `style.py` is quantitative pressure only. It is not sufficient proof because it misses forbidden terms such as `contract`, `session`, `owner`, `context`, and `state`.
- Every executable slice must combine style pressure, forbidden tokens, dead-code/reachability, and duplicate-shape evidence where applicable.
- Passing tests are never sufficient when stale names, stale paths, dead shapes, compatibility mirrors, duplicated limits, or fake owners remain.
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
- `reference-index.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Current source/evidence inspected in this pass:

- `style.py`
- `howl-render/include/howl_render.h`
- `howl-render/src/c/text_session.zig`
- `howl-render/src/cursor_presentation.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/text/cursor_presentation.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/text/scene_rects.zig`
- `howl-render/src/text/scene.zig`
- `howl-render/src/text/surface_preparer.zig`
- `howl-render/src/text/direct_normal.zig`
- `howl-render/src/text/ft_hb/support.zig`
- Package-root searches across `howl-render/src/**/*.zig` and `howl-render/include/**/*.h`
- Workspace status before edits: only untracked `temp.md` and `temp.txt`; untouched.

## Reference Anchor Map

- TigerStyle assertions/proof: `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, positive space, and negative space.
- TigerStyle naming/directness: `TIGER_STYLE.md:273-276` requires exact nouns and verbs; `TIGER_STYLE.md:337-347` rejects overloaded names; `TIGER_STYLE.md:416-429` requires narrow scope and low dimensionality.
- TigerStyle duplicate state: `TIGER_STYLE.md:372-387` rejects duplicate variables/aliases that can diverge.
- TigerBeetle limits: `ARCHITECTURE.md:189-222` treats explicit bounds as a forcing function.
- Howl owner law: `AGENTS.md:178-196` rejects fake owners, bucket structs, and vague ownership.
- Howl ABI law: `AGENTS.md:25-37`, `AGENTS.md:159-166`, and `AGENTS.md:168-176` make the C ABI the product and limit hosts to C contracts.

## Current Evidence Baseline

Whole-package style command:

```sh
python3 style.py --by-file --format json --sort prod howl-render
```

Current top style rows by `prod` after accepted cursor-trail `Config` deletion:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 13387 | 7133 | 23993 | 314 | 172 | 66 | 2141 | 1114 | 4 | 203 | 0 | 0 |
| `howl-render/src/render_session.zig` | 832 | 128 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/raster/special_legacy_computing.zig` | 725 | 0 | 776 | 2 | 0 | 0 | 124 | 37 | 2 | 0 | 0 | 0 |
| `howl-render/src/surface/emitter.zig` | 717 | 0 | 784 | 79 | 0 | 0 | 18 | 15 | 1 | 2 | 0 | 0 |
| `howl-render/src/surface/realizer.zig` | 713 | 0 | 788 | 1 | 3 | 4 | 46 | 49 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/shape/cluster.zig` | 594 | 276 | 987 | 9 | 2 | 1 | 86 | 53 | 0 | 8 | 0 | 0 |
| `howl-render/src/text/scene.zig` | 587 | 552 | 1232 | 5 | 19 | 2 | 153 | 36 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/surface_preparer.zig` | 566 | 368 | 1017 | 10 | 2 | 1 | 80 | 43 | 0 | 6 | 0 | 0 |
| `howl-render/src/surface/resource_store.zig` | 555 | 109 | 707 | 35 | 0 | 0 | 29 | 22 | 0 | 3 | 0 | 0 |
| `howl-render/src/text/direct_normal.zig` | 477 | 203 | 770 | 19 | 26 | 1 | 66 | 33 | 0 | 6 | 0 | 0 |

Candidate-file metric command:

```sh
python3 style.py --by-file --format json --sort path howl-render/src/render_session.zig howl-render/src/cursor_presentation.zig howl-render/src/text/contract.zig howl-render/src/text/scene_rects.zig howl-render/src/text/scene.zig howl-render/src/text/surface_preparer.zig howl-render/src/text/direct_normal.zig howl-render/src/text/ft_hb/support.zig
```

Current candidate metrics:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 4149 | 1389 | 6137 | 62 | 82 | 33 | 748 | 320 | 0 | 43 | 0 | 0 |
| `howl-render/src/cursor_presentation.zig` | 224 | 62 | 315 | 2 | 0 | 0 | 24 | 16 | 0 | 4 | 0 | 0 |
| `howl-render/src/render_session.zig` | 832 | 128 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/contract.zig` | 64 | 6 | 77 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `howl-render/src/text/direct_normal.zig` | 477 | 203 | 770 | 19 | 26 | 1 | 66 | 33 | 0 | 6 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/scene.zig` | 587 | 552 | 1232 | 5 | 19 | 2 | 153 | 36 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/surface_preparer.zig` | 566 | 368 | 1017 | 10 | 2 | 1 | 80 | 43 | 0 | 6 | 0 | 0 |

Forbidden-token content command:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
```

Current package-root token totals from this pass:

| token | content files | token hits | path files |
| --- | ---: | ---: | ---: |
| `contract` | 51 | 1550 | 3 |
| `session` | 33 | 1458 | 5 |
| `owner` | 22 | 393 | 0 |
| `pipeline` | 0 | 0 | 0 |
| `context` | 3 | 107 | 0 |
| `state` | 21 | 522 | 1 |
| `options` | 8 | 170 | 0 |
| `config` | 18 | 277 | 0 |
| `info` | 9 | 63 | 0 |
| `data` | 3 | 26 | 0 |
| `result` | 18 | 163 | 0 |
| `manager` | 0 | 0 | 0 |
| `controller` | 0 | 0 | 0 |
| `types` | 0 | 0 | 0 |
| `utils` | 0 | 0 | 0 |
| `helper` | 1 | 1 | 0 |
| `support` | 21 | 613 | 3 |

Current deterministic findings:

- `style.py` now reports zero package-wide `bucket_named_structs` and zero `bucket_struct_lines`; the cursor-trail `Config` bucket is gone.
- `render_session.zig:27` still owns a private `const max_cursor_trail_rects = 16`, while the C ABI already defines `HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX` in `include/howl_render.h:33` and uses it in `include/howl_render.h:376`.
- `cursor_presentation.zig:22`, `cursor_presentation.zig:53`, `cursor_presentation.zig:123`, `cursor_presentation.zig:139`, `c/text_session.zig:71-72`, and `render_session.zig:1013` already consume `c.HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX` for C-facing payload capacity.
- `text/cursor_presentation.zig:2` owns a second Zig literal `pub const max_cursor_trail_rects = 16`, and `text/contract.zig:28` re-exports it as the text scene contract limit.
- `render_session.zig:260` allocates `[max_cursor_trail_rects]contract.CursorTrailRect` and `render_session.zig:262` bounds copying with `@min(facts.cursor_trail_count, max_cursor_trail_rects)`. This duplicates the C ABI limit and can diverge from the host-facing array size.
- `text/scene_rects.zig:851` and `text/scene.zig:443` correctly consume `contract.max_cursor_trail_rects`; they should not be edited for this slice.
- `render_session.zig`, `text/ft_hb/support.zig`, scene contracts, scene rects, and special raster files remain stronger by raw metric/token pressure, but they require live owner splits, folder moves, or contract aggregation decisions. The cursor-trail limit cleanup is the strongest next executable slice because it removes an active duplicate bound without new folders, C header changes, or worker-invented ownership.

Reachability command template:

```sh
rg -n '\b(max_cursor_trail_rects|HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX|cursor_trail_rects|cursor_trail_count)\b' howl-render/src howl-render/include
rg -n '^const max_cursor_trail_rects = 16;' howl-render/src/render_session.zig
rg -n '^pub const max_cursor_trail_rects = 16;' howl-render/src/text/cursor_presentation.zig
rg -n 'contract\.max_cursor_trail_rects|@import\("howl_render_c"\)\.HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX' howl-render/src/render_session.zig howl-render/src/text/cursor_presentation.zig howl-render/src/text/contract.zig
```

Duplicate-shape evidence still active after accepted cursor-trail `Config` deletion:

- Cursor trail capacity is duplicated as `16` in `text/cursor_presentation.zig:2`, `render_session.zig:27`, and the C ABI macro. The C ABI macro is the product authority; the two Zig literals are cleanup targets.
- Remaining mutex wrappers in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig` require lifecycle-owner proof and are not part of this slice.
- Scene contract aggregation, `support` path pressure, metric-dominant render/session files, and special raster long functions remain live later targets.

## Ordered Cleanup Plan

1. Accepted: ABI cursor cadence mirror deletion closure. Product receipt: `howl-render` `864ea8b`; root receipt: `f84e1c8`.
2. Accepted: dead/self-test-only render shape deletion. Product receipt: `howl-render` `7af878b`; root receipt: `6d0e393`.
3. Accepted: cursor trail decay bucket deletion. Product receipt: `howl-render` `d7f93b7`; root receipt: `398da7f`.
4. Active next slice: delete duplicated Zig cursor trail limit literals by deriving `text/cursor_presentation.zig` from the C ABI macro and making `render_session.zig` consume `contract.max_cursor_trail_rects`.
5. Metric/token dominant render-session slice: split or rename only source-proved lifecycle pieces in `render_session.zig`, with before/after style row and forbidden-token row. No broad new runtime or manager layer.
6. `text/ft_hb/support.zig` cleanup: rename/split `support` into exact FT/HB owners and remove fake support terminology, with package-root path scan proving no `support` product owner remains unless test-only and justified.
7. Text scene contract cleanup: split `text/scene_contract.zig`, reduce `contract` imports in `scene_rects.zig`, `scene.zig`, `lane.zig`, `shape/cluster.zig`, and `surface_preparer.zig`, and preserve only curated re-export roots where exact.
8. Long-function/cast-heavy renderer cleanup: target `text/raster/special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, and `text/scene_rects.zig` using metric deltas plus owner-local tests. Long functions in product files must trend to zero.
9. Test-support cleanup: shrink `src/c/test_support.zig` aliases and move proof helpers to owner-local tests where still needed.
10. Benchmark cleanup: rename benchmark-only bucket nouns in `benchmark_main.zig` after product/ABI cleanup, without hiding benchmark proof inside unit/ABI roots.

The sprint remains live after each slice. The orchestrator/reviewer must rerun the four evidence lanes and choose the next strongest deterministic target from remaining metrics/tokens/reachability/duplicates.

## Active Executable Slice

Name: cursor trail limit authority cleanup.

Why this is the strongest next slice:

- The accepted cursor-trail bucket deletion closed the only bucket metric. The next deterministic duplicate lane exposes two Zig literals for the same cursor-trail capacity governed by the C ABI.
- The C ABI is the product authority. `render_session.zig` and `text/cursor_presentation.zig` must not own independent `16` literals that can diverge from `HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX`.
- The worker can remove the duplication without new folders, file moves, header changes, scene contract reshaping, render-session lifecycle splits, or new public aliases.
- The expected result is exact and reviewable: no Zig-side cursor trail limit literal remains outside the C ABI header, and `render_session.zig` consumes the contract limit.

Allowed files:

- `howl-render/src/text/cursor_presentation.zig`
- `howl-render/src/render_session.zig`
- `loops/howl-render-cleanup-loop.txt` only for required teammate note after execution/review

Required changes:

- In `howl-render/src/text/cursor_presentation.zig`, replace `pub const max_cursor_trail_rects = 16;` with `pub const max_cursor_trail_rects = @import("howl_render_c").HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX;`.
- In `howl-render/src/render_session.zig`, delete the private `const max_cursor_trail_rects = 16;`.
- In `readCursorPresentation`, replace the two uses of the deleted private constant with `contract.max_cursor_trail_rects`:
  - the `trail_rects` fixed array repeat count
  - the `@min(facts.cursor_trail_count, ...)` copy bound
- Do not change the C ABI header, `src/c/text_session.zig`, root `cursor_presentation.zig` C-facing payload arrays, scene files, tests, build files, README files, or benchmark files.
- Do not add a replacement constant in `render_session.zig`, compatibility alias, helper wrapper, new file, new folder, or aggregate re-export root.

Required reachability/deletion searches after the change:

```sh
rg -n '^const max_cursor_trail_rects = 16;' howl-render/src/render_session.zig
rg -n '^pub const max_cursor_trail_rects = 16;' howl-render/src/text/cursor_presentation.zig
rg -n '\bmax_cursor_trail_rects\b' howl-render/src/render_session.zig howl-render/src/text/cursor_presentation.zig howl-render/src/text/contract.zig howl-render/src/text/scene.zig howl-render/src/text/scene_rects.zig
rg -n 'HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX' howl-render/include/howl_render.h howl-render/src/c/text_session.zig howl-render/src/cursor_presentation.zig howl-render/src/text/cursor_presentation.zig howl-render/src/render_session.zig
```

Expected search result:

- First command returns no matches.
- Second command returns no matches.
- Third command shows `text/cursor_presentation.zig` exporting `max_cursor_trail_rects` from the C ABI macro, `text/contract.zig` re-exporting it, `render_session.zig` consuming `contract.max_cursor_trail_rects`, and existing scene tests/fixtures consuming `contract.max_cursor_trail_rects`; no private `render_session.zig` declaration may remain.
- Fourth command shows the C ABI header, existing C-boundary validation/copy uses, existing root cursor-presentation C-facing arrays, and the new text cursor-presentation authority import. `render_session.zig` should not mention the C macro directly.

Metric recording required before and after:

```sh
python3 style.py --by-file --format json --sort prod howl-render
python3 style.py --by-file --format json --sort path howl-render/src/text/cursor_presentation.zig howl-render/src/render_session.zig
```

Current allowed-file metric baseline:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 907 | 128 | 1169 | 17 | 8 | 1 | 67 | 72 | 0 | 17 | 0 | 0 |
| `howl-render/src/render_session.zig` | 832 | 128 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/cursor_presentation.zig` | 75 | 0 | 85 | 0 | 0 | 0 | 0 | 0 | 0 | 7 | 0 | 0 |

Expected metric consequence:

- Whole-package `bucket_named_structs` and `bucket_struct_lines` remain `0`.
- `render_session.zig` line/prod count should decrease by deletion of the private constant; it must not increase `long_funcs`, `anytypes`, `usizes`, `structs_top_level`, `bucket_named_structs`, or `bucket_struct_lines`.
- `text/cursor_presentation.zig` must not increase `structs_top_level`, `bucket_named_structs`, `bucket_struct_lines`, `long_funcs`, `anytypes`, `usizes`, or `casts`.
- Any allowed-file metric increase outside a reviewer-accepted one-token import consequence blocks the slice.

Forbidden-token recording required before and after:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src/text/cursor_presentation.zig howl-render/src/render_session.zig
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Expected forbidden-token consequence:

- Allowed-file forbidden-token counts must not increase.
- Package-root `contract`, `session`, `owner`, `state`, `config`, `result`, and `support` totals may remain unchanged; this slice is duplicate-limit cleanup, not live owner renaming.
- Package-root path-scan total remains unchanged because this slice does not rename path-level `contract`, `session`, `state`, or `support` files.

Required tests:

- `zig build test:unit` in `howl-render`
- `zig build test:abi` in `howl-render`
- `zig build check` in `howl-render`
- `zig build check` at workspace root after package check passes

Non-goals:

- Do not change `HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX` or any shipped C ABI layout.
- Do not change host cursor cadence validation, cursor trail math, animation behavior, scene cursor trail rendering, or text scene contract shapes.
- Do not rename `cursor_trail_count`, `cursor_trail_rects`, `HostCursorCadence`, `CursorPresentation`, or scene cursor primitive structs.
- Do not touch `text/scene.zig`, `text/scene_rects.zig`, `text/contract.zig`, `src/c/text_session.zig`, `src/cursor_presentation.zig`, build files, README files, or benchmark files.
- Do not attempt render-session owner renames, mutex wrapper cleanup, scene contract splitting, or `support` path cleanup in this slice.

Stop conditions:

- The worker needs any file outside the allowed list to keep tests passing.
- Any C ABI header/layout change appears necessary.
- Any private cursor trail limit literal remains in `render_session.zig` or `text/cursor_presentation.zig` after the change.
- `render_session.zig` imports `howl_render_c` only to reach the cursor trail capacity instead of consuming `contract.max_cursor_trail_rects`.
- `text/cursor_presentation.zig` cannot import the C ABI macro without dependency or build failure; stop rather than inventing a new owner or fallback literal.
- Tests must be weakened or skipped.
- Forbidden-token counts or style metrics increase outside the accepted gates above.

Receipt fields required:

- Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
- Researcher session id: `research-2026-06-18-render-cleanup-next-slice-06`.
- Reviewer session id that accepts this next-slice package.
- Coder/worker session id.
- Commit hash for accepted implementation or explicit open commit-hash handoff status.
- Before/after metric rows for whole-package `(sum)` and all allowed product files.
- Before/after forbidden-token evidence for allowed files, package-root content totals, and package-root path-scan matches.
- Results for all required tests and all deletion/reachability searches.

## Next-Slice Forcing Gates

After this cursor-trail limit authority cleanup slice is accepted, the next planning/execution seed must choose from these remaining deterministic targets unless fresh evidence shows a stronger one:

- Metric/token dominant files `render_session.zig`, `text/ft_hb/support.zig`, `text/surface_preparer.zig`, `text/scene.zig`, `text/shape/cluster.zig`, `text/scene_rects.zig`, `text/direct_normal.zig`, and `text/raster/special_legacy_computing.zig`.
- Scene contract aggregation in `text/scene_contract.zig` and `text/contract.zig`.
- Remaining duplicate mutex wrappers in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig` after lifecycle-owner proof.
- Test-support cleanup in `src/c/test_support.zig`.

The sprint cannot be declared complete until all four lanes produce either clean negative results or explicit, source-backed retained-shape receipts in this artifact or its accepted successor.
