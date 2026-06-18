# Howl Render Cleanup Plan

Status: active planning correction after reviewer rejection and first-slice gate repair.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
Researcher session id: `research-2026-06-18-render-cleanup-gate-repair-03`.
Prior researcher ids: `research-2026-06-18-render-cleanup-inventory-01`, `research-2026-06-18-render-cleanup-correction-02`.
Reviewer session id: pending corrected-plan review.
Commit-hash receipt status: planning-only artifact, no dedicated cleanup commit yet.

## Scope Rule

- The cleanup sprint is indefinite until deterministic evidence says no cleanup remains in `howl-render`.
- `style.py` is quantitative pressure only. It is not sufficient proof because it misses forbidden terms such as `contract`, `session`, `owner`, `context`, and `state`.
- Every executable slice must combine the four evidence lanes below: style pressure, forbidden tokens, dead-code/reachability, and duplicate-shape evidence.
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
- `loops/howl-render-cleanup-loop.txt`, including reviewer rejection note at the end
- `research/howl-render-cleanup-plan.md` as it existed before this correction
- `AGENTS.md`
- `reference-index.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Reviewer rejection repaired in this pass:

- `review-2026-06-18-render-cleanup-re-gate-02` rejected the first-slice package-root search because it forbade legitimate live `HostCursorCadence` / `HostCursorCadenceRect` names in broader cursor/render-session owners that this slice explicitly does not rename.
- The same rejection found that first-slice receipts did not require before/after forbidden-token evidence for allowed files and package-root totals despite the four-lane model.

Current Howl render sources inspected for this correction:

- `style.py`
- `howl-render/include/howl_render.h`
- `howl-vt/include/howl_vt.h`
- `howl-render/src/test_abi.zig`
- `howl-render/src/c/text_session.zig`
- `howl-render/src/cursor_presentation.zig`
- `howl-render/src/render_session.zig`
- `howl-render/src/text/cursor_presentation.zig`
- `howl-render/src/text/cursor_trail.zig`
- `howl-render/src/tokens.zig`
- `howl-render/src/submitted_surface.zig`
- `howl-render/src/text/effects.zig`
- Package-root scans across `howl-render/src/**/*.zig` and `howl-render/include/**/*.h`

## Reference Anchor Map

- TigerStyle naming: `TIGER_STYLE.md:273-276` requires exact nouns and verbs; `TIGER_STYLE.md:337-347` rejects overloaded names.
- TigerStyle ownership/directness: `TIGER_STYLE.md:315-333` requires top-down order and top-level complex types; `TIGER_STYLE.md:416-429` requires narrow scope and simple dimensionality.
- TigerStyle assertions/proof: `TIGER_STYLE.md:104-140` requires assertions for arguments, return values, invariants, positive space, and negative space.
- TigerStyle duplication: `TIGER_STYLE.md:372-387` rejects duplicate variables/aliases that can diverge and backs in-place construction for larger shapes.
- TigerBeetle architecture: `ARCHITECTURE.md:189-222` treats explicit bounds as a forcing function; `ARCHITECTURE.md:408-423` backs clear control/data-plane separation.
- Howl project law: `AGENTS.md:178-196` rejects bucket files/structs and generic `Context`, `State`, `Options`, `Info`, `Data`, `Result`, `Config`, and similar names unless source-backed and owner-true.
- Howl ABI law: `AGENTS.md:25-37`, `AGENTS.md:159-166`, and `AGENTS.md:168-176` make the C ABI the product and limit hosts to C contracts.

## Evidence Model

### Lane 1: Style Pressure

Command for whole-package quantitative baseline:

```sh
python3 style.py --by-file --format json --sort prod howl-render
```

Output shape:

- JSON array.
- Row 0 is `(sum)`.
- Subsequent rows are file records with `path`, `repo`, `files`, `lines`, `blank`, `comments`, `code`, `tests`, `prod`, `proof`, `test_hooks`, `benchmark`, `asserts`, `usizes`, `anytypes`, `casts`, `funcs`, `long_funcs`, `test_blocks`, `structs_top_level`, `bucket_named_structs`, and `bucket_struct_lines`.

Current baseline top rows by `prod`:

| path | prod | tests | benchmark | lines | asserts | usizes | anytypes | casts | funcs | long_funcs | structs_top_level | bucket_named_structs | bucket_struct_lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `(sum)` | 13516 | 7141 | 904 | 24159 | 314 | 147 | 66 | 2119 | 1120 | 4 | 209 | 1 | 4 |
| `howl-render/src/render_session.zig` | 832 | 128 | 0 | 1084 | 17 | 8 | 1 | 67 | 72 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/scene_rects.zig` | 771 | 70 | 0 | 934 | 8 | 26 | 27 | 296 | 63 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/raster/special_legacy_computing.zig` | 725 | 0 | 0 | 776 | 2 | 0 | 0 | 124 | 37 | 2 | 0 | 0 | 0 |
| `howl-render/src/surface/emitter.zig` | 717 | 0 | 0 | 784 | 79 | 0 | 0 | 18 | 15 | 1 | 2 | 0 | 0 |
| `howl-render/src/surface/realizer.zig` | 713 | 0 | 0 | 788 | 1 | 3 | 4 | 46 | 49 | 0 | 2 | 0 | 0 |
| `howl-render/src/text/ft_hb/support.zig` | 628 | 0 | 0 | 708 | 1 | 1 | 1 | 62 | 57 | 0 | 5 | 0 | 0 |
| `howl-render/src/text/shape/cluster.zig` | 594 | 276 | 0 | 987 | 9 | 2 | 1 | 86 | 53 | 0 | 8 | 0 | 0 |
| `howl-render/src/text/scene.zig` | 587 | 552 | 0 | 1232 | 5 | 19 | 2 | 153 | 36 | 0 | 10 | 0 | 0 |
| `howl-render/src/text/surface_preparer.zig` | 566 | 368 | 0 | 1017 | 10 | 2 | 1 | 80 | 43 | 0 | 6 | 0 | 0 |
| `howl-render/src/surface/resource_store.zig` | 555 | 109 | 0 | 707 | 35 | 0 | 0 | 29 | 22 | 0 | 3 | 0 | 0 |
| `howl-render/src/text/direct_normal.zig` | 477 | 203 | 0 | 770 | 19 | 26 | 1 | 66 | 33 | 0 | 6 | 0 | 0 |
| `howl-render/src/text/cursor_trail.zig` | 137 | 50 | 0 | 213 | 4 | 2 | 1 | 26 | 9 | 0 | 3 | 1 | 4 |
| `howl-render/src/c/text_session.zig` | 130 | 17 | 0 | 161 | 0 | 2 | 0 | 3 | 8 | 0 | 2 | 0 | 0 |

Style-lane classification:

- `render_session.zig`, `scene_rects.zig`, `special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, `text/ft_hb/support.zig`, `text/scene.zig`, `text/surface_preparer.zig`, and `surface/resource_store.zig` are the metric-dominant wounds.
- `text/cursor_trail.zig` is the only current `style.py` bucket-struct offender: `bucket_named_structs=1`, `bucket_struct_lines=4`, from `pub const Config = struct` at `src/text/cursor_trail.zig:13-16`.
- `src/c/text_session.zig` is not metric-dominant. It can be first only as a safe closure slice because it deletes a concrete ABI mirror without broadening into the metric-dominant files.

Every slice must record before/after rows for its allowed files and the `(sum)` row with this command. A slice is not closed if it improves local code while increasing `usizes`, `anytypes`, `long_funcs`, `bucket_named_structs`, or `bucket_struct_lines` in its allowed files unless the plan explicitly permits the increase and proves why.

### Lane 2: Forbidden Token Lane

`style.py` does not prove this lane. Run package-root scans over product source and shipped headers, excluding generated/cache output.

Content scan command:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
```

Path scan command:

```sh
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Current package-root token totals from source/header files:

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

Current product/ABI files with highest forbidden-token pressure:

| hits | file | dominant terms |
| ---: | --- | --- |
| 664 | `howl-render/src/render_session.zig` | `state:195`, `session:158`, `owner:72`, `context:66`, `config:57`, `contract:43`, `support:34` |
| 438 | `howl-render/src/text/ft_hb/support.zig` | `state:152`, `config:116`, `contract:68`, `session:48`, `support:31` |
| 233 | `howl-render/src/text/surface_preparer.zig` | `contract:109`, `session:64`, `options:57`, `config:3` |
| 213 | `howl-render/src/text/scene.zig` | `contract:162`, `options:47` |
| 178 | `howl-render/src/text/shape/cluster.zig` | `contract:163`, `config:11`, `owner:4` |
| 164 | `howl-render/src/text/scene_rects.zig` | `contract:162`, `config:2` |
| 154 | `howl-render/src/text/direct_normal.zig` | `session:101`, `contract:41` |
| 101 | `howl-render/src/text/lane.zig` | `contract:101` |
| 105 | `howl-render/src/text/resolver.zig` | `contract:56`, `session:39`, `config:8` |
| 75 | `howl-render/src/c/test_support.zig` | `state:25`, `session:16`, `options:16`, `contract:13` |
| 58 | `howl-render/src/c/text_session.zig` | `owner:30`, `session:23`, `support:5` |
| 50 | `howl-render/include/howl_render.h` | ABI-forced `session`, `state`, `result`, `info` |

Classification rules:

- ABI names in `howl-render/include/howl_render.h` are allowed only when they are shipped C ABI nouns. They must not justify non-ABI Zig mirrors.
- `contract` is allowed only for C ABI product contracts or curated package roots that re-export exact owners and no behavior. `text/scene_contract.zig` is not clean because it owns many concrete scene shapes under a bucket name.
- `session` is allowed for shipped `HowlRenderTextSession*` ABI names and exact lifecycle owners only. Broad imports or fake internal session nouns remain cleanup targets.
- `owner` is forbidden unless the symbol is the true owner at a lifecycle boundary and no exact domain noun exists. Current `GeometryOwner` and many `owner` locals remain pressure points.
- `context`, `state`, `options`, `info`, `data`, `result`, `Config`, and `support` are presumptively bucket/fake terms unless the slice proves ABI force or exact domain ownership.
- `helper` and `support` in comments count when they describe product terminology. Test-only support must stay confined and must not become a public internal namespace.

### Lane 3: Dead-Code And Reachability

Reachability command template for each candidate symbol:

```sh
rg -n '\bSYMBOL\b' howl-render/src howl-render/include
```

Classification roots:

- Product roots: `howl-render/src/libhowl_render.zig`, `howl-render/src/render_session.zig`, `howl-render/src/surface/**/*.zig`, `howl-render/src/text/**/*.zig`, `howl-render/src/c/**/*.zig` excluding `*_test.zig`.
- Shipped ABI root: `howl-render/include/howl_render.h`.
- ABI proof root: `howl-render/src/test_abi.zig` and `howl-render/src/c/*_test.zig` reached from `test_abi.zig`.
- Unit proof root: `howl-render/src/test_unit.zig` and owner-local tests reached from it.
- Benchmark root: `howl-render/src/benchmark_main.zig`, wired by `howl-render/build.zig` as benchmark, not product ABI proof.

Classification:

- `live`: reached from product or shipped ABI roots.
- `proof-only`: reached only from tests that prove a live product owner.
- `self-test-only`: declaration reached only by its own local test. Delete with that test unless the test proves another live owner.
- `benchmark-only`: reached only by benchmark root. Keep out of product cleanup unless the slice is benchmark cleanup.
- `dead`: declaration has no reachability outside itself.

Current deterministic dead/self-test-only candidates:

- `tokens.PreparedSurfaceTokenWith`: declaration `src/tokens.zig:61-80`; reached only by local test `src/tokens.zig:200-216`. Classification: `self-test-only`, delete.
- `tokens.RenderResult`: declaration `src/tokens.zig:102-107`; no product/test use outside declaration. Classification: `dead`, delete.
- `tokens.SurfaceLostReason`: declaration `src/tokens.zig:115-119`; only payload of unused `RenderResult`. Classification: `dead`, delete.
- `tokens.LatestMailbox`: declaration `src/tokens.zig:121-155`; reached only by local test `src/tokens.zig:218-230`. Its private `ThreadMutex` and `lockMutex` at `src/tokens.zig:3-13` exist only for this mailbox. Classification: `self-test-only`, delete.
- `submitted_surface.SubmitDecision`: declaration `src/submitted_surface.zig:16-21`; no use outside declaration. Classification: `dead`, delete.
- `submitted_surface.SubmittedWorkState` and `SubmittedSurface.workState`: declaration/use `src/submitted_surface.zig:23-25` and `49-54`; reached only by local test `src/submitted_surface.zig:137-141` unless `c/work_state.zig` proves otherwise during slice execution. Classification: delete if package-root search still proves no product reachability.
- `submitted_surface.SubmittedSurface.fullPrepareReason`: `src/submitted_surface.zig:81-88`; no product use. Classification: `dead`, delete.
- `text.effects.BackendCaps`: declaration `src/text/effects.zig:11-16`; reached only by its own defaults test `src/text/effects.zig:39-45` and broad re-export pressure through `text/contract.zig`. Classification: `self-test-only`, delete.
- `text.cursor_trail.Config`: declaration `src/text/cursor_trail.zig:13-16`; style bucket offender. It is not dead because `CursorTrail.update` uses it, but it is a rename/shape cleanup candidate, not a reachability deletion.

### Lane 4: Duplicate-Shape Evidence

Duplicate evidence must name both shapes and the bridge that keeps them in sync. Vibes are rejected.

- ABI cursor cadence mirror: canonical header `include/howl_render.h:351-378` defines `HowlRenderHostCursorTrailRect` and `HowlRenderHostCursorCadence`; `src/c/text_session.zig:62-89` hand-writes matching `extern struct` shapes; bridge is `setCursorCadence` at `src/c/text_session.zig:91-130`. Classification: exact duplicate, first safe closure slice.
- Cursor presentation split: root cursor behavior lives in `src/cursor_presentation.zig`; text scene cursor payload lives in `src/text/cursor_presentation.zig:1-85`; bridge from host cadence/render session into text payload is in `render_session.zig` cursor translation code. Classification: live duplicate-ish shape, needs cursor/scene owner slice.
- Cursor trail rect limit: C ABI limit `HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX` at `include/howl_render.h:33`; text scene local `max_cursor_trail_rects = 16` at `src/text/cursor_presentation.zig:2`; C boundary uses the translated C constant in `src/c/text_session.zig`; render session also has cursor-limit translation pressure. Classification: duplicate constant, clean after ABI mirror deletion.
- Fallback font limit: C ABI limit `HOWL_RENDER_MAX_FALLBACK_FONTS` at `include/howl_render.h:18`; text owner local `max_fallback_fonts` at `src/text/paths.zig`; test-only assertion in `src/c/test_support.zig`. Classification: duplicate constant/proof weakness, needs production assertion or single owner.
- Thread mutex shapes: `src/tokens.zig:3-13` and `src/submitted_surface.zig:4-14` duplicate a small mutex wrapper. `tokens` copy is deletable with `LatestMailbox`; submitted copy needs lifecycle review. Classification: partial duplicate, delete dead copy first.
- Scene contract aggregation: `src/text/contract.zig` is a curated re-export root, but `src/text/scene_contract.zig` owns concrete scene/glyph/sprite/raster/missing-glyph shapes under `contract`. Classification: bucket file requiring later split.

## Corrected Ordered Cleanup Plan

1. ABI cursor cadence mirror deletion closure slice. This is not the metric-dominant wound. It is first only because it is exact, ABI-safe, already isolated to the C boundary, deletes a shipped-contract duplicate, requires no folder approval, and creates a clean closure before broader metric/token surgery. The next slices are forced by recorded style/token metrics, so this cannot be used to dodge main cleanup.
2. Dead-code deletion slice for `tokens.zig`, `submitted_surface.zig`, and `text/effects.zig`: delete dead/self-test-only token/mailbox/result/submitted/effects shapes, their private tests, and broad re-exports. This attacks reachability proof and forbidden-token pressure.
3. Cursor-trail bucket cleanup: remove `text/cursor_trail.zig` `Config` bucket by passing exact decay fields or replacing it with an owner-true noun if the slice proves one. The `style.py` bucket count must reach zero for allowed files.
4. Cursor duplicate/limit cleanup: unify cursor presentation payload names and cursor trail limit ownership without adding compatibility aliases. This must remove the second ambiguous `CursorPresentation` noun or rename both roles exactly.
5. Metric/token dominant render-session slice: split or rename only source-proved lifecycle pieces in `render_session.zig`, with before/after style row and forbidden-token row. No broad new runtime or manager layer.
6. `text/ft_hb/support.zig` cleanup: rename/split `support` into exact FT/HB owners and remove fake support terminology, with package-root path scan proving no `support` product owner remains unless test-only and justified.
7. Text scene contract cleanup: split `text/scene_contract.zig`, reduce `contract` imports in `scene_rects.zig`, `scene.zig`, `lane.zig`, `shape/cluster.zig`, and `surface_preparer.zig`, and preserve only curated re-export roots where exact.
8. Long-function/cast-heavy renderer cleanup: target `text/raster/special_legacy_computing.zig`, `surface/emitter.zig`, `surface/realizer.zig`, and `text/scene_rects.zig` using metric deltas plus owner-local tests. Long functions in product files must trend to zero.
9. Test-support cleanup: shrink `src/c/test_support.zig` aliases and move proof helpers to owner-local tests where still needed.
10. Benchmark cleanup: rename benchmark-only bucket nouns in `benchmark_main.zig` after product/ABI cleanup, without hiding benchmark proof inside unit/ABI roots.

The sprint remains live after each slice. The orchestrator/reviewer must rerun the four evidence lanes and choose the next strongest deterministic target from remaining metrics/tokens/reachability/duplicates.

## First Executable Slice

Name: ABI cursor cadence mirror deletion closure.

Why this can be first despite not being metric-dominant:

- The duplicate is exact and isolated: `include/howl_render.h:351-378` is canonical C ABI truth, while `src/c/text_session.zig:62-89` duplicates it by hand.
- Deleting the mirror cannot hide the main cleanup because this plan records the metric-dominant and forbidden-token-dominant files and orders them immediately after this closure slice.
- The slice has a narrow negative search proving no Zig code still names `text_session.HostCursorCadence` or `text_session.HostCursorCadenceRect`.
- The slice creates no new names, folders, owners, or compatibility aliases.

Allowed files:

- `howl-render/src/c/text_session.zig`
- `howl-render/src/test_abi.zig`
- `research/howl-render-cleanup-plan.md` only for execution receipt updates if the orchestrator asks after review
- `loops/howl-render-cleanup-loop.txt` only for required teammate note after execution/review

Required changes:

- Delete `pub const HostCursorCadenceRect = extern struct` at `src/c/text_session.zig:62-71`.
- Delete `pub const HostCursorCadence = extern struct` at `src/c/text_session.zig:73-89`.
- Change `setCursorCadence` at `src/c/text_session.zig:91` to accept `?*const c.HowlRenderHostCursorCadence`.
- Preserve every existing validation in `setCursorCadence`: shape range, three color checks, positive beam/underline thickness, positive fast/slow decay, and `cursor_trail_count <= c.HOWL_RENDER_CURSOR_TRAIL_RECTS_MAX`.
- Preserve the copy into `render_session.TextSessionOwner.HostCursorCadenceRect`; only the source type changes to the translated C type.
- Update the local cadence test in `src/c/text_session.zig:142-161` to use `std.mem.zeroes(c.HowlRenderHostCursorCadence)`.
- Add exact ABI layout proof to `src/test_abi.zig`:
  - `@sizeOf(c.HowlRenderHostCursorTrailRect) == 16`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "row") == 0`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "col") == 2`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "rows") == 4`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "cols") == 6`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "opacity") == 8`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "reserved0") == 9`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "reserved1") == 10`
  - `@offsetOf(c.HowlRenderHostCursorTrailRect, "color") == 12`
  - `@sizeOf(c.HowlRenderHostCursorCadence) == 312`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "focused") == 0`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_opacity") == 1`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "text_blink_opacity") == 2`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "effective_shape") == 3`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_color") == 4`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_text_color") == 12`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_trail_color") == 20`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_beam_thickness") == 28`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_underline_thickness") == 32`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_trail_decay_fast_s") == 36`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_trail_decay_slow_s") == 40`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_trail_count") == 44`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "reserved0") == 46`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "cursor_trail_rects") == 48`
  - `@offsetOf(c.HowlRenderHostCursorCadence, "now_ns") == 304`

Deletion and stale-mirror searches after the change:

```sh
rg -n 'pub const HostCursorCadenceRect = extern struct|pub const HostCursorCadence = extern struct' howl-render/src howl-render/include
rg -n 'text_session\.HostCursorCadence|text_session\.HostCursorCadenceRect' howl-render/src howl-render/include
rg -n 'pub const HostCursorCadence(Rect)? = extern struct|\?\*const HostCursorCadence\b|std\.mem\.zeroes\(HostCursorCadence\)' howl-render/src/c/text_session.zig
rg -n 'HowlRenderHostCursorCadence|HowlRenderHostCursorTrailRect' howl-render/src/c/text_session.zig howl-render/src/test_abi.zig howl-render/include/howl_render.h
```

Expected search result:

- First command returns no matches.
- Second command returns no matches, proving no outside source still imports or names the deleted local `text_session` mirror types.
- Third command returns no matches, proving `src/c/text_session.zig` no longer declares the mirror structs, accepts the deleted local mirror as the `setCursorCadence` parameter type, or builds tests with the deleted local mirror type.
- Fourth command returns only canonical header declarations, `setCursorCadence` translated C parameter/use sites, and ABI layout tests.

Allowed retained names in this first slice:

- `HostCursorCadence` and `HostCursorCadenceRect` may still appear as live internal renderer/text owner names outside the deleted `src/c/text_session.zig` ABI mirror, including `src/cursor_presentation.zig:7-9`, `src/render_session.zig:654-655`, and `render_session.TextSessionOwner.HostCursorCadenceRect` use from `src/c/text_session.zig`.
- This slice does not rename broader cursor presentation or render-session owners. Those names remain targets for the later cursor duplicate/limit cleanup slice.

Metric recording required before and after:

```sh
python3 style.py --by-file --format json --sort prod howl-render
python3 style.py --by-file --format json --sort path howl-render/src/c/text_session.zig howl-render/src/test_abi.zig
```

Expected metric consequence:

- `src/c/text_session.zig` `structs_top_level` decreases by `2`.
- `src/c/text_session.zig` `prod` and `lines` decrease.
- No allowed file may add `long_funcs`, `bucket_named_structs`, or `bucket_struct_lines`.
- `src/test_abi.zig` may gain proof lines and `usizes` only for exact ABI layout assertions using `@as(usize, ...)`.

Forbidden-token recording required before and after:

```sh
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src/c/text_session.zig howl-render/src/test_abi.zig
rg -n -i --glob '*.zig' --glob '*.h' --glob '!**/.zig-cache/**' --glob '!**/zig-out/**' --glob '!**/vendor/**' '(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)' howl-render/src howl-render/include
rg --files howl-render/src howl-render/include | rg -i '(^|/)[^/]*(contract|session|owner|pipeline|context|state|options|config|info|data|result|manager|controller|types|utils|helper|support)[^/]*$'
```

Expected forbidden-token evidence:

- Record per-token before/after counts for the allowed files as one table: `src/c/text_session.zig`, `src/test_abi.zig`, and the two-file allowed-files total.
- Record per-token before/after package-root content totals for `howl-render/src howl-render/include` using the same token list as Lane 2.
- Record before/after package-root path-scan matches with exact path list and total count.
- `src/c/text_session.zig` must not increase any forbidden-token count. Remaining `session`, `owner`, or `support` hits in `src/c/text_session.zig` are not closure blockers for this slice if the before/after evidence shows the slice did not add them and the explicit stale-mirror searches above pass.
- `src/test_abi.zig` may add ABI proof text only when the added tokens are part of exact shipped C ABI names or test names required for the size/offset proof.
- Package-root totals may remain nonzero because this slice intentionally does not rename broader live owners. Any increase outside the allowed ABI proof exception blocks the slice.

Required tests:

- `zig build test:abi` in `howl-render`
- `zig build test:unit` in `howl-render`
- `zig build check` in `howl-render`
- `zig build check` at workspace root after package check passes

Non-goals:

- Do not move cursor files.
- Do not rename `TextSessionOwner`, `GeometryOwner`, `contract`, `session`, `support`, or `Config` in this slice.
- Do not delete dead token/submitted/effects candidates in this slice.
- Do not change `include/howl_render.h` or `howl-vt/include/howl_vt.h`.
- Do not change render behavior or shipped ABI names.
- Do not introduce compatibility aliases.
- Do not create new folders.

Stop conditions:

- Any C ABI header change becomes necessary.
- Any host-visible symbol or struct layout changes.
- The translated C module cannot express `c.HowlRenderHostCursorCadence` directly.
- The exact size/offset tests above fail.
- Worker needs to touch files outside the allowed list to complete the slice.
- Worker finds existing source uses `text_session.HostCursorCadence` or `text_session.HostCursorCadenceRect` outside `src/c/text_session.zig`.

Receipt fields required:

- Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.
- Researcher session id: `research-2026-06-18-render-cleanup-gate-repair-03`.
- Reviewer session id that accepts this corrected planning slice.
- Coder/worker session id.
- Commit hash for accepted implementation or explicit open commit-hash handoff status.
- Before/after metric rows for `(sum)`, `src/c/text_session.zig`, and `src/test_abi.zig`.
- Before/after forbidden-token evidence for allowed files, package-root content totals, and package-root path-scan matches.
- Results for all required tests and all deletion/stale-mirror searches.

## Next-Slice Forcing Gates

After first-slice acceptance, the next planning/execution seed must choose from these remaining deterministic targets unless fresh evidence shows a stronger one:

- Dead/self-test-only deletion in `tokens.zig`, `submitted_surface.zig`, and `text/effects.zig`.
- `style.py` bucket offender `text/cursor_trail.zig:13-16`.
- Forbidden-token dominant files `render_session.zig`, `text/ft_hb/support.zig`, `text/surface_preparer.zig`, `text/scene.zig`, `text/shape/cluster.zig`, `text/scene_rects.zig`, and `text/direct_normal.zig`.
- Duplicate cursor presentation and cursor limit shapes.

The sprint cannot be declared complete until all four lanes produce either clean negative results or explicit, source-backed retained-shape receipts in this artifact or its accepted successor.
