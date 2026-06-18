# Howl Render Cleanup Plan

Status: active next-slice planning after accepted dead-shape cleanup.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
Researcher session id: `research-2026-06-18-render-cleanup-next-slice-05`.
Prior researcher ids: `research-2026-06-18-render-cleanup-inventory-01`, `research-2026-06-18-render-cleanup-correction-02`, `research-2026-06-18-render-cleanup-gate-repair-03`, `research-2026-06-18-render-cleanup-next-slice-04`.
Last accepted reviewer id: `review-2026-06-18-render-cleanup-dead-shape-01`.
Reviewer id for this next-slice package: pending.
Commit-hash receipt status: accepted executable slices closed as `howl-render` `864ea8b Use C cursor cadence ABI directly`, root `f84e1c8 Track cursor cadence ABI cleanup`; `howl-render` `7af878b Delete dead render shapes`, root `6d0e393`. This planning update has no dedicated planning commit yet.

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
- `howl-render/src/text/cursor_trail.zig`
- `howl-render/src/cursor_presentation.zig`
- `howl-render/src/text/contract.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/text/ft_hb/support.zig`
- `howl-render/src/text/scene_contract.zig`
- `howl-render/src/text/scene_rects.zig`
- Package-root searches across `howl-render/src/**/*.zig` and `howl-render/include/**/*.h`
- Workspace status before edits: only untracked `temp.md` and `temp.txt`; untouched.

## Reference Anchor Map

- TigerStyle assertions/proof: `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, positive space, and negative space.
- TigerStyle naming/directness: `TIGER_STYLE.md:273-276` requires exact nouns and verbs; `TIGER_STYLE.md:337-347` rejects overloaded names; `TIGER_STYLE.md:416-429` requires narrow scope and low dimensionality.
- TigerStyle duplicate state: `TIGER_STYLE.md:372-387` rejects duplicate variables/aliases that can diverge and backs direct construction for larger shapes.
- TigerBeetle limits: `ARCHITECTURE.md:189-222` treats explicit bounds as a forcing function.
- Howl owner law: `AGENTS.md:178-196` rejects bucket files/structs and generic `Context`, `State`, `Options`, `Info`, `Data`, `Result`, `Config`, and similar names unless source-backed and owner-true.
- Howl ABI law: `AGENTS.md:25-37`, `AGENTS.md:159-166`, and `AGENTS.md:168-176` make the C ABI the product and limit hosts to C contracts.

## Current Evidence Baseline

Whole-package style command:

```sh
python3 style.py --by-file --format json --sort prod howl-render
```

Current top style rows by `prod` after accepted dead-shape cleanup:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 13388 | 7133 | 23995 | 314 | 172 | 66 | 2141 | 1114 | 4 | 204 | 1 | 4 |
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
python3 style.py --by-file --format json --sort path howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig howl-render/src/render_session.zig howl-render/src/text/ft_hb/support.zig howl-render/src/text/scene_contract.zig howl-render/src/text/scene_rects.zig
```

Current candidate metrics:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 2822 | 341 | 3550 | 32 | 37 | 30 | 485 | 217 | 0 | 51 | 1 | 4 |
| `howl-render/src/cursor_presentation.zig` | 224 | 62 | 315 | 2 | 0 | 0 | 24 | 16 | 0 | 4 | 0 | 0 |
| `howl-render/src/render_session.zig` | 832 | 128 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/cursor_trail.zig` | 137 | 50 | 213 | 4 | 2 | 1 | 26 | 9 | 0 | 3 | 1 | 4 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/scene_contract.zig` | 230 | 31 | 296 | 0 | 0 | 0 | 10 | 0 | 0 | 27 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |

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
| `config` | 19 | 293 | 0 |
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

- `text/cursor_trail.zig:13-16` is the only package-wide `style.py` `bucket_named_structs` offender. The name `Config` is generic under `AGENTS.md:190-196`, carries only two decay facts, and has no ABI or reference-backed owner pressure.
- `text/cursor_trail.zig:48`, `text/cursor_trail.zig:62`, and `text/cursor_trail.zig:95` pass `Config` only inside the same owner. The only product caller is `cursor_presentation.zig:138`, which already owns the two exact decay fields as `cursor_trail_decay_fast_s` and `cursor_trail_decay_slow_s`.
- `text/cursor_trail.zig:143`, `text/cursor_trail.zig:156`, and `text/cursor_trail.zig:168` use anonymous `Config` literals in owner-local tests only.
- `cursor_presentation.zig:71-72` stores host cadence decay fields directly; `c/text_session.zig:70` validates they are positive before entering `CursorPresentation`. The cursor-trail owner also asserts both decay fields are positive and must keep doing so after the bucket deletion.
- `render_session.zig`, `text/ft_hb/support.zig`, scene contracts, and scene rect cleanup remain stronger by raw size/token pressure but require live owner renames, function/folder splits, or contract aggregation decisions. The `Config` bucket deletion is stronger for the next executable slice because it closes the only bucket metric with no folder move, no ABI change, and no worker-invented ownership.

Reachability command template:

```sh
rg -n '\b(Config|decay_fast_s|decay_slow_s)\b' howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig
rg -n 'cursor_trail\.update\(\.\{' howl-render/src
rg -n '\bcursor_trail\.Config\b|\btext_cursor_trail\.Config\b' howl-render/src howl-render/include
```

Duplicate-shape evidence still active after the accepted first two slices:

- Cursor-trail decay values are duplicated as an anonymous `Config` bucket in `text/cursor_trail.zig` and exact host-cadence fields in `cursor_presentation.zig`. The bucket can be removed by passing `cursor_trail_decay_fast_s` and `cursor_trail_decay_slow_s` directly into the cursor-trail owner.
- `max_cursor_trail_rects` remains duplicated between `cursor_presentation.zig:2` and `render_session.zig:27`; this is not part of the `Config` bucket slice because it touches render-session cursor-read logic and ABI limit ownership.
- Thread mutex wrappers remain in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig`; they require lifecycle-owner review and are not part of this slice.
- Scene contract aggregation, `support` path pressure, and metric-dominant render/session files remain live later targets.

## Ordered Cleanup Plan

1. Accepted: ABI cursor cadence mirror deletion closure. Product receipt: `howl-render` `864ea8b`; root receipt: `f84e1c8`.
2. Accepted: dead/self-test-only render shape deletion. Product receipt: `howl-render` `7af878b`; root receipt: `6d0e393`.
3. Active next slice: delete `text/cursor_trail.zig` `Config` bucket by passing exact cursor-trail decay fields directly through the cursor-trail owner.
4. Cursor duplicate/limit cleanup: unify cursor presentation payload names and cursor trail limit ownership without compatibility aliases. This must remove the duplicated `max_cursor_trail_rects` owner or record why a second owner is ABI-forced.
5. Metric/token dominant render-session slice: split or rename only source-proved lifecycle pieces in `render_session.zig`, with before/after style row and forbidden-token row. No broad new runtime or manager layer.
6. `text/ft_hb/support.zig` cleanup: rename/split `support` into exact FT/HB owners and remove fake support terminology, with package-root path scan proving no `support` product owner remains unless test-only and justified.
7. Text scene contract cleanup: split `text/scene_contract.zig`, reduce `contract` imports in `scene_rects.zig`, `scene.zig`, `lane.zig`, `shape/cluster.zig`, and `surface_preparer.zig`, and preserve only curated re-export roots where exact.
8. Long-function/cast-heavy renderer cleanup: target `text/raster/special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, and `text/scene_rects.zig` using metric deltas plus owner-local tests. Long functions in product files must trend to zero.
9. Test-support cleanup: shrink `src/c/test_support.zig` aliases and move proof helpers to owner-local tests where still needed.
10. Benchmark cleanup: rename benchmark-only bucket nouns in `benchmark_main.zig` after product/ABI cleanup, without hiding benchmark proof inside unit/ABI roots.

The sprint remains live after each slice. The orchestrator/reviewer must rerun the four evidence lanes and choose the next strongest deterministic target from remaining metrics/tokens/reachability/duplicates.

## Active Executable Slice

Name: cursor trail decay bucket deletion.

Why this is the strongest next slice:

- The accepted dead-shape slice closed the known unreachable shapes. The remaining deterministic lanes now identify exactly one bucket-named struct in the whole package: `text/cursor_trail.zig` `Config`.
- The `Config` bucket is not ABI-forced, not reference-backed, and not owner-true. It only groups two decay fields that already have exact names at the caller boundary.
- The worker can delete it without new folders, file moves, C ABI changes, or scene/render-session ownership decisions.
- The expected metric result is exact and reviewable: package-wide `bucket_named_structs` and `bucket_struct_lines` must become zero.

Allowed files:

- `howl-render/src/text/cursor_trail.zig`
- `howl-render/src/cursor_presentation.zig`
- `loops/howl-render-cleanup-loop.txt` only for required teammate note after execution/review

Required changes:

- In `howl-render/src/text/cursor_trail.zig`, delete `pub const Config = struct { decay_fast_s: f32, decay_slow_s: f32 };`.
- Change `CursorTrail.update` to take exact fields: `decay_fast_s: f32`, `decay_slow_s: f32`, `now_ns: u64`, `cursor_visible: bool`. Keep both positive assertions inside `update`, now against the exact parameters.
- Change `updateCorners` to take `decay_fast_s: f32`, `decay_slow_s: f32`, and `dt_s: f32`; replace all `config.*` uses with exact parameter names.
- Change `updateOpacity` to take `decay_slow_s: f32`, `dt_s: f32`, and `cursor_visible: bool`; replace `config.decay_slow_s` with the exact parameter.
- In `howl-render/src/cursor_presentation.zig`, change the one product call at `cursor_trail.update` to pass `self.cursor_trail_decay_fast_s` and `self.cursor_trail_decay_slow_s` directly, not an anonymous struct literal.
- In `howl-render/src/text/cursor_trail.zig` tests, update the three `trail.update(.{ .decay_fast_s = 0.1, .decay_slow_s = 0.4 }, ...)` calls to pass `0.1, 0.4, ...` directly.
- Do not add replacement structs, aliases, compatibility names, helper wrappers, new files, or new test roots.

Required reachability/deletion searches after the change:

```sh
rg -n '\bpub const Config\b|\bConfig\b' howl-render/src/text/cursor_trail.zig
rg -n 'cursor_trail\.update\(\.\{' howl-render/src
rg -n '\bcursor_trail\.Config\b|\btext_cursor_trail\.Config\b' howl-render/src howl-render/include
rg -n '\bdecay_fast_s\b|\bdecay_slow_s\b' howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig
```

Expected search result:

- First command returns no matches in `text/cursor_trail.zig`.
- Second command returns no matches.
- Third command returns no matches.
- Fourth command returns only exact decay parameter names, assertions, local tests, and the existing `cursor_trail_decay_fast_s`/`cursor_trail_decay_slow_s` fields/call in `cursor_presentation.zig`; no generic `Config` shape may remain.

Metric recording required before and after:

```sh
python3 style.py --by-file --format json --sort prod howl-render
python3 style.py --by-file --format json --sort path howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig
```

Current allowed-file metric baseline:

| path | prod | proof | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 361 | 112 | 528 | 6 | 2 | 1 | 50 | 25 | 0 | 7 | 1 | 4 |
| `howl-render/src/cursor_presentation.zig` | 224 | 62 | 315 | 2 | 0 | 0 | 24 | 16 | 0 | 4 | 0 | 0 |
| `howl-render/src/text/cursor_trail.zig` | 137 | 50 | 213 | 4 | 2 | 1 | 26 | 9 | 0 | 3 | 1 | 4 |

Expected metric consequence:

- Whole-package `(sum)` `bucket_named_structs` decreases from `1` to `0` and `bucket_struct_lines` decreases from `4` to `0`.
- `howl-render/src/text/cursor_trail.zig` `structs_top_level` decreases by `1`, `bucket_named_structs` becomes `0`, and `bucket_struct_lines` becomes `0`.
- `howl-render/src/cursor_presentation.zig` may have a small line/cast-neutral call-site change but must not increase `structs_top_level`, `bucket_named_structs`, `bucket_struct_lines`, `anytypes`, `usizes`, or `long_funcs`.
- No allowed file may increase `bucket_named_structs`, `bucket_struct_lines`, `long_funcs`, or `anytypes`.

Forbidden-token recording required before and after:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src/text/cursor_trail.zig howl-render/src/cursor_presentation.zig
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Current allowed-file forbidden-token baseline:

- `howl-render/src/text/cursor_trail.zig`: `contract` import/use pressure and `config` hits from the `Config` bucket plus local parameter names.
- `howl-render/src/cursor_presentation.zig`: no path-level forbidden token; content retains live `contract` import/use and cadence field names.

Expected forbidden-token consequence:

- `text/cursor_trail.zig` must lose the `Config` declaration hit.
- Package-root `config` hits must not increase; a decrease is expected but not sufficient unless the bucket metric also reaches zero.
- Package-root path-scan total remains unchanged because this slice does not rename path-level `contract`, `session`, `state`, or `support` files.
- Any forbidden-token increase in allowed files blocks the slice unless the reviewer explicitly accepts a test-name-only exception backed by exact output.

Required tests:

- `zig build test:unit` in `howl-render`
- `zig build test:abi` in `howl-render`
- `zig build check` in `howl-render`
- `zig build check` at workspace root after package check passes

Non-goals:

- Do not touch C ABI files, shipped headers, `render_session.zig`, `text/ft_hb/support.zig`, scene contract files, scene rect files, build files, README files, or benchmark files.
- Do not rename `cursor_trail_decay_fast_s` or `cursor_trail_decay_slow_s`; they are exact host-cadence fields and ABI-adjacent source facts.
- Do not change cursor trail math, opacity behavior, animation behavior, or cadence validation behavior.
- Do not merge cursor presentation data shapes, cursor trail limits, or scene cursor trail rect shapes in this slice.
- Do not add new folders, move files, add compatibility aliases, or create aggregate re-export roots.

Stop conditions:

- Any `Config` type or `cursor_trail.update(.{ ... })` anonymous bucket call remains after the change.
- Worker finds a product caller that depends on `cursor_trail.Config` as a named type outside current source evidence.
- Worker needs files outside the allowed list to keep tests passing.
- Any C ABI header, host-visible layout, or render-session change appears necessary.
- Cursor trail tests must be weakened instead of mechanically updated to the direct argument shape.
- Metrics fail to drive whole-package `bucket_named_structs` and `bucket_struct_lines` to zero.
- Forbidden-token counts increase in an allowed file outside a reviewer-accepted test-name-only exception.

Receipt fields required:

- Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
- Researcher session id: `research-2026-06-18-render-cleanup-next-slice-05`.
- Reviewer session id that accepts this next-slice package.
- Coder/worker session id.
- Commit hash for accepted implementation or explicit open commit-hash handoff status.
- Before/after metric rows for whole-package `(sum)` and all allowed product files.
- Before/after forbidden-token evidence for allowed files, package-root content totals, and package-root path-scan matches.
- Results for all required tests and all deletion/reachability searches.

## Next-Slice Forcing Gates

After this cursor-trail bucket deletion slice is accepted, the next planning/execution seed must choose from these remaining deterministic targets unless fresh evidence shows a stronger one:

- Cursor duplicate/limit cleanup: `cursor_presentation.zig` and `render_session.zig` both define cursor-trail rect limits.
- Metric/token dominant files `render_session.zig`, `text/ft_hb/support.zig`, `text/surface_preparer.zig`, `text/scene.zig`, `text/shape/cluster.zig`, `text/scene_rects.zig`, and `text/direct_normal.zig`.
- Scene contract aggregation in `text/scene_contract.zig` and `text/contract.zig`.
- Remaining duplicate mutex wrappers in `submitted_surface.zig`, `text/ft_hb/support.zig`, and `render_session.zig` after lifecycle-owner proof.

The sprint cannot be declared complete until all four lanes produce either clean negative results or explicit, source-backed retained-shape receipts in this artifact or its accepted successor.
