Text sprint scratchpad

Date: 2026-06-10.
Status: reviewer-accepted planning package; archive after current index handoff.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Researcher session id: `research-2026-06-10-text-sprint-01`.
Researcher correction receipt id: `research-2026-06-10-text-sprint-01-c1`.
Researcher blocker-slice receipt id: `research-2026-06-10-text-sprint-01-c2`.
Researcher render-owner receipt id: `research-2026-06-10-text-sprint-01-c3`.
Reviewer session id: `review-2026-06-10-text-sprint-01`.
Acceptance date: `2026-06-11`.
Acceptance verdict: `accept`.
Planning commit-hash receipt: fulfilled by orchestrator archive commit after active-surface cleanup.

Preload receipt:

- Role: researcher
- Read order completed:
  - `/home/home/personal/projects/howl/loop/flow.md`
  - `/home/home/personal/projects/howl/loop/orcestrator.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/loop/reviewer.md`
  - `/home/home/personal/projects/howl/loop/coder.md`
  - `/home/home/personal/projects/howl/loop/researcher.md`
  - `/home/home/personal/projects/howl/sprints/current.txt`
  - `/home/home/personal/projects/howl/loops/render-source-cell-model-research.txt`
  - `/home/home/personal/projects/howl/research/2026-06-10-text-sprint-scratchpad.md`
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-10-text-sprint-research.md`
- Active loops:
  - `/home/home/personal/projects/howl/loops/render-source-cell-model-research.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-10-text-sprint-scratchpad.md`
- Hygiene issues:
  - none
- Execution authorized:
  - no implementation is authorized from this planning loop

Reviewer finding closure

1. Finding: slice 1 required one authoritative dim/invisible owner even though no seeded reference proves the dim factor and current owners disagree.
- Closure:
  - slice 1 is reseated to source-backed mapper truth only: default-background truth, inverse/selection preservation, and empty-cell classification.
  - slice 1 no longer authorizes a coder to choose a dim factor or converge dim/invisible behavior by local policy.
  - the unresolved dim/invisible owner was isolated in a later blocked slice during correction pass `research-2026-06-10-text-sprint-01-c1`; item 5 below closes that numeric blocker and reseats the slice on Kitty `dim_opacity = 0.4`:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:183-195`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:102-106`

2. Finding: the artifact called `source text input keeps fg-colored blanks empty` stale against Alacritty, then still required it to pass.
- Closure:
  - the stale empty-cell proof is no longer a pass gate.
  - the authoritative empty-cell truth in this artifact is now:
    - Alacritty-empty classification remains the mapper rule:
      - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`
    - opaque default-background truth remains the Howl mapper proof:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:518-653`
      - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`
  - the current stale proofs are rewrite/delete obligations, not acceptance proofs:
    - `source text input converts VT source to text scene input` in its current transparent-background form:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-492`
    - `source text input keeps fg-colored blanks empty`:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:887-903`

3. Finding: `text-publication-full-path` did not require publication-specific proof after `preparePublicationWithSessionOptions` stops returning `null`.
- Closure:
  - the publication slice now requires exact non-null mixed-publication and complex-publication frame tests in `frame_preparer.zig`.
  - the reason is current source truth, not inference: publication still returns `null` immediately after direct-normal rejection:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-168`
  - the new slice contract points those proofs at the existing frame-preparer proof root:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:827-883`

4. Finding: slice contracts were missing accountable planning session ids.
- Closure:
  - every slice contract now records accountable planning session ids for orchestrator, researcher, researcher correction receipt, and reviewer.

5. Dim/faint blocker closure against reviewer session `review-2026-06-10-text-sprint-01`.
- Closure:
  - the expanded local reference set now settles the numeric faint policy for this planning round because the active planning artifact already carries a receipted Kitty-primary override for the text stack.
  - Kitty upstream defines `dim_opacity` with a default value of `0.4` and applies it as text alpha when DIM/FAINT is present:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py:1826-1831`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/types.py:547-547`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl:320-322`
  - Ghostty and Alacritty diverge (`0.5` opacity default and `0.66` RGB factor), so they do not provide consensus. They are recorded as secondary divergence checks, not owners for this product decision under the existing Kitty receipt:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/config/Config.zig:3710-3715`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/generic.zig:623-623`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/color.rs:15-17`

6. Render-time owner closure against reviewer session `review-2026-06-10-text-sprint-01`.
- Closure:
  - the expanded current-source read pack does not prove a single current Howl render-time dim owner file.
  - current Howl loses the dim/faint fact at the text contract seam, so no later owner can apply Kitty `dim_opacity = 0.4` honestly today:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:119-132`
  - both text draw-construction paths only forward already-resolved `fg` into draw color:
    - direct-normal path:
      - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:300-304`
    - shaped-lane scene path:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:665-674`
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:951-953`
    - direct-scene decoration path:
      - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:214-244`
  - prepared realization owners consume `draw.color.a` at render time, but they do not own dim policy:
    - oracle/path realization:
      - `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig:202-215`
    - host-facing render-surface emission:
      - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:543-567`
  - this means reviewer finding 1 is closed by explicit blocker truth, not by pretending a current single owner exists. The slice remains not coder-ready until the owner seam is narrowed.

Problem statement

- The current Howl text lane destroys semantic text truth too early, duplicates the source-to-text mapping owner, and keeps two draw-construction owners alive at once.
- `source/cell.zig` and `source/vt.zig` already preserve terminal-semantic color identity as `default|indexed|rgb`, plus underline style, inverse, invisible, selection, and continuation truth:
  - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig:1-49`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:13-65`
- `text/contract.zig` then flattens the text seam to resolved RGBA plus `empty`, so the text stack cannot distinguish semantic default background from explicit RGB background after mapping:
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
- `source/text_input.zig` and `source/publication_cell_map.zig` both convert semantic colors to RGBA, both implement style transforms, and already disagree on dim/invisible/empty behavior:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:72-245`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-149`
- `text/direct_normal.zig` rebuilds renderables from four source variants instead of consuming one renderable owner:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:46-57`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:222-253`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:357-470`
- `text/direct_scene.zig` and `text/scene.zig` both own damage normalization, backgrounds, clears, cursor draws, and decoration generation:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:5-123`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:126-210`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:128-155`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:609-880`
- Kitty pressure says text-stack truth must preserve default foreground/background, selection colors or reverse-video dynamic behavior, underline style/color, and independent bold/faint control as terminal semantics, not as one local alpha convention:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:7-29`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:59-105`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:168-178`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md:11-60`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/misc-protocol.md:30-36`
- The full sprint is therefore not “fix four tests”. The full sprint is to migrate the whole text lane so semantic source truth survives the contract seam, both fast and complex lanes consume the same owner-true renderable model, publication reaches the same pipeline as raw VT input, and the proof surface stops encoding contradictory owner stories.

Sources read in order

1. `/home/home/personal/projects/howl/AGENTS.md`
2. `/home/home/personal/projects/howl/loop/flow.md`
3. `/home/home/personal/projects/howl/loop/orcestrator.md`
4. `/home/home/personal/projects/howl/loop/researcher.md`
5. `/home/home/personal/projects/howl/loop/reviewer.md`
6. `/home/home/personal/projects/howl/loop/coder.md`
7. `/home/home/personal/projects/howl/loop/researcher.md`
8. `/home/home/personal/projects/howl/sprints/current.txt`
9. `/home/home/personal/projects/howl/loops/render-source-cell-model-research.txt`
10. `/home/home/personal/projects/howl/research/2026-06-10-text-sprint-scratchpad.md`
11. `/home/home/personal/projects/howl/sprints/2026-06-10-text-sprint-research.md`
12. `/home/home/personal/projects/howl/reference-index.md`
13. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
14. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
15. archive navigation only:
  - `/home/home/personal/projects/howl/research/defered/2026-06-10-test-accountability-research.md`
  - targeted grep over `research/done/` and `research/defered/`
16. `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
17. `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
18. `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
19. `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
20. `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
21. `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
22. `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
23. `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
24. `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
25. `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
26. `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
27. `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig`
28. `/home/home/personal/projects/howl/howl-render/build.zig`
29. `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
30. `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md`
31. `/home/home/personal/projects/howl/utils/official_docs/kitty/misc-protocol.md`
32. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig`
33. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`
34. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
35. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs`
36. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
37. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
38. runtime proof:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
39. blocker navigation grep over archived research caches and expanded terminal references for `dim|faint|dim_opacity|faint-opacity|DIM_FACTOR`
40. `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/misc-protocol.rst`
41. `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/changelog.rst`
42. `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py`
43. `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/types.py`
44. `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl`
45. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/config/Config.zig`
46. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/generic.zig`
47. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`
48. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
49. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/color.rs`
50. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
51. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/extra/man/alacritty.5.scd`
52. `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
53. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
54. `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
55. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
56. `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface_test.zig`

Current-code facts

1. Source truth is already semantic, not RGBA:
  - `source/cell.zig` `Color.Kind` is `default|indexed|rgb`, and `Cell` stores semantic fg/bg/underline colors plus attrs, underline style, and continuation:
    - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig:1-49`
  - `source/vt.zig` preserves the same semantic source color kind/value in the shipped source/publication ABI:
    - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:13-65`

2. The text contract discards that semantic distinction:
  - `contract.CellInput` holds `fg`, `bg`, and `underline_color` as resolved `Rgba8`, plus `empty`, with no semantic color kind/value:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
  - `RenderableCell` repeats the same flattened RGBA shape:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:119-132`

3. `source/text_input.zig` resolves semantic colors to RGBA before the text contract seam and derives emptiness from RGBA alpha:
  - default/indexed/rgb are converted in `colorToRgba8` and `publicationColorToRgba8`:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:72-87`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:125-140`
  - Alacritty-empty detection consumes resolved `bg.a` instead of semantic background kind:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:116-123`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:154-160`
  - the VT mapping owner sets `.empty = isAlacrittyEmptyCell(src, bg)` after color resolution:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:224-245`

4. Publication mapping is duplicated and already diverges from the VT/publication bridge:
  - `text_input.zig` publication mapping delegates cell construction to `publication_cell_map.mapPublicationCellInput`, but still owns separate color helpers, cursor mapping, dirty mapping, and partial-damage mapping:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:248-418`
  - `publication_cell_map.zig` independently owns dim, inverse, invisible, selection, and empty decisions:
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-149`
  - the dim transforms are already inconsistent:
    - `text_input.zig` dims to 66%:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:183-195`
    - `publication_cell_map.zig` dims by `/2`:
      - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:102-106`
  - both current dim owners mutate mapper-side RGB immediately instead of preserving DIM/FAINT as a semantic style fact until one render-policy owner realizes it:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:224-245`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-45`
  - invisible handling is also inconsistent:
    - `text_input.zig` blanks the codepoint, combining, underline, and strikethrough:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:205-212`
    - `publication_cell_map.zig` only zeros foreground:
      - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:116-118`

5. `shape/cluster.zig` is already the strongest current owner for renderable-cell, cluster, span, and damage-filter truth:
  - it builds sparse cells, line text caches, renderable cells, clusters, and runs:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:250-420`
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:551-690`
  - it owns a bounded `DamageFilter` and span inference:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:511-548`
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:627-645`

6. `direct_normal.zig` bypasses that owner and reconstructs renderables locally from four source variants:
  - the source union mixes raw cells, publication cells, rich inputs, and already-prepared renderables:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:46-57`
  - `sourceItem` remaps publication cells and rebuilds raw/input renderables instead of consuming a single renderable owner:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:222-253`
  - local constructors duplicate cluster owner logic:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:357-470`

7. `frame_preparer.zig` only gives publication the direct-normal fast path today:
  - raw cells and rich inputs fall back from direct normal into sparse/cluster/complex shaping:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:111-153`
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:171-227`
  - publication returns a direct-normal frame or `null`; it does not enter the same complex pipeline:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-168`

8. Draw construction is split across two owners:
  - `direct_scene.zig` owns damage normalization, backgrounds, clears, cursor draws, and decorations for the direct-normal lane:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:5-123`
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:126-210`
  - `scene.zig` owns the same responsibilities for the shaped lane, with its own damage normalization, background merge rules, clear-color policy, cursor geometry, and decoration generation:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:128-155`
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:609-880`
  - the clear policy is not the same:
    - `direct_scene.zig` always emits opaque black clears:
      - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:126-145`
    - `scene.zig` derives clear color from overlapping transparent cells before falling back to black:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:758-805`

9. There is a generic bucket struct in active text owners:
  - `direct_scene.MergedBuffers` is a bucket for six unrelated slices of draw state:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:25-32`

10. The shipped render surface is still C ABI first:
  - `libhowl_render.zig` exports the C ABI entrypoints and no privileged Zig API:
    - `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig:10-38`
  - `build.zig` wires unit and ABI proof roots around the shipped header and exported symbols:
    - `/home/home/personal/projects/howl/howl-render/build.zig:1-151`

Reference facts

1. Kitty treats default foreground/background, selection colors, cursor color, and palette colors as terminal-semantic state that must be saveable/restorable:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:7-29`

2. Kitty’s color protocol distinguishes dynamic colors from reset-to-default and explicitly names default foreground/background, selection colors, cursor color, and cursor text:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:59-105`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:168-178`

3. Kitty defines underline style as terminal-semantic state and requires underline color to survive reverse video:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md:11-60`

4. Kitty exposes bold and faint as independently resettable semantics:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/misc-protocol.md:30-36`

5. Ghostty keeps cell content, semantic content, and style lookup separate on the C-facing cell surface:
  - `content_tag`, `has_text`, `style_id`, `semantic_content`, and background-color payload kind are queried independently:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig:13-100`

6. Ghostty’s style owner preserves semantic fg/bg/underline color source as a tagged union and computes RGB only against palette/default inputs:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig:18-120`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig:149-220`

7. Ghostty’s shaping run owner splits runs on style boundaries, selection boundaries, and cursor boundaries, while explicitly allowing background colors to differ because background fill is a separate owner concern:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:10-120`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:398-406`

8. Alacritty keeps semantic fg/bg colors in the terminal cell model and uses named default colors in `Cell::default`:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:131-152`

9. Alacritty’s terminal-cell emptiness check is semantic, not RGB-equality based:
  - empty means blank char or tab, named default background, named default foreground, no visible flags, and no zerowidth payload:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`

10. Alacritty computes render-time RGB, inverse, selection styling, and background alpha in display/content, not in the terminal cell owner:
  - renderable content iterates non-empty cells:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:158-181`
  - `RenderableCell::new` applies inverse, selection, search, and cursor colors at render-content time:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:208-280`
  - background alpha is computed from whether the original background is `NamedColor::Background`:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:301-395`

11. Alacritty’s text renderer only batches/draws renderable cells and glyphs; it does not own semantic color derivation:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:35-172`

12. TigerBeetle law requires zero technical debt, explicit control flow, bounded work, paired assertions, and explicit control-plane/data-plane separation:
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:63-129`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:180-259`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:282-360`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:440-470`

Dim/faint blocker slice evidence

- Exact current-code facts:
  - `source/text_input.zig` applies DIM by multiplying foreground and underline RGB to `66%` inside the source-to-text mapper before the text contract seam:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:183-195`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:224-245`
  - `source/publication_cell_map.zig` applies DIM by halving foreground RGB inside the publication mapper before the same text contract seam:
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:102-106`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-45`
  - the live ABI proof for publication DIM currently encodes the `66%` mapper-side RGB rule directly in its assertions:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:734-797`
    - exact stale assertions:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783-787`

- Exact reference facts:
  - Kitty protocol docs define SGR `2` as faint and Kitty supports independent faint reset with `222`, keeping faint as an explicit text attribute:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/misc-protocol.rst:24-30`
  - Kitty’s changelog records faint support as making text blend into the background, not as a mapper-side RGB rewrite:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/changelog.rst:4384-4385`
  - Kitty’s option definition sets `dim_opacity` default to `0.4` and defines `1` as no dimming and `0` as fully invisible:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py:1826-1831`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/types.py:547-547`
  - Kitty’s renderer multiplies `effective_text_alpha` by `dim_opacity` when the DIM bit is present:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl:320-322`
  - Ghostty treats faint as configurable opacity with a default of `0.5` and applies that opacity at render time when `style.flags.faint` is set:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/config/Config.zig:3710-3715`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/generic.zig:623-623`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/generic.zig:2877-2879`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig:434-437`
  - Alacritty defines `DIM_FACTOR = 0.66`, derives dim colors from normal colors with that factor, and also multiplies RGB by that factor for dim cells in display/content:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/color.rs:15-17`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/color.rs:62-87`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:330-349`
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/extra/man/alacritty.5.scd:450-455`

- Verdict on the dim/faint factor:
  - Under the user-approved Kitty-primary override already receipted in the active planning artifact, the authoritative factor for this sprint is Kitty `dim_opacity = 0.4`.
  - The proved factor is an opacity multiplier at render time. It is not a mapper-side RGB scale.
  - Ghostty (`0.5` opacity default) and Alacritty (`0.66` RGB factor) diverge from Kitty, so they do not provide cross-terminal numeric consensus. They only prove that the visual consequence of SGR `2` is terminal-owned render policy, not source-cell semantic truth.

- Slice status:
  - Slice `text-style-attrs-render-policy-owner` is unblocked on numeric factor proof.
  - The slice is not yet coder-ready because current source still does not expose one text-side render-time dim owner. The slice becomes honest only after the contract preserves the dim fact and the scene owner convergence slice leaves one draw-construction owner.

Render-time dim owner seam evidence

- Exact current-code facts:
  - `contract.CellInput` and `contract.RenderableCell` carry resolved RGBA only. They do not preserve `dim`, `faint`, or any equivalent style fact for later render policy:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:119-132`
  - `direct_normal.zig` writes sprite draw color directly from `renderable.fg`, so the direct lane consumes mapper-resolved color and has no dim policy of its own:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:300-304`
  - `scene.zig` writes sprite and decoration colors from `RenderableCell` foreground and underline colors without any dim-specific transform:
    - group sprite draw color:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:665-674`
    - strikethrough and decoration color:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:852-874`
    - foreground lookup:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:951-953`
  - `direct_scene.zig` does the same on the direct lane by forwarding `cell.fg` and `cell.underline_color` into decoration draws:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:214-244`
  - `prepared/buffer.zig` is a render-time alpha consumer: for alpha sprites, it multiplies glyph-mask alpha by `draw.color.a` before blending:
    - `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig:202-215`
  - `prepared/render_surface_emitter.zig` is the host-facing render-time alpha consumer: it packs `draw.color` into emitted glyph refs/commands, but does not decide the value:
    - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:543-567`
    - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:595-607`

- Exact reference facts:
  - Kitty applies dim at render time by multiplying text alpha with `dim_opacity` in the cell shader:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl:318-322`
  - Alacritty applies dim in the render-content owner when computing foreground RGB for renderable cells:
    - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:325-350`
  - Both references apply dim after semantic cell state exists. Neither pushes dim into the VT/source mapper.

- Owner verdict:
  - No current Howl file is a proved render-time dim policy owner.
  - Current Howl has:
    - duplicate text draw-construction owners:
      - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
      - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
    - generic render-time alpha consumers:
      - `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
      - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - The first provable future render-time dim owner after slice `text-scene-owner-convergence` is `text/scene.zig`, but that is future slice shape, not current-source truth.

Current owner map

- Semantic source-cell truth:
  - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
- VT/publication-to-text bridge:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- Text seam data shapes:
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
- Renderable/cluster/run preparation:
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- Direct-normal fast lane:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
- Mixed/complex frame preparation:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
- C ABI export and proof roots:
  - `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig`
  - `/home/home/personal/projects/howl/howl-render/build.zig`

Reference owner map

- Kitty semantic text-stack owner pressure:
  - terminal-semantic color, selection, cursor, underline, and bold/faint state stay explicit until the terminal chooses how to realize them:
    - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:7-29`
    - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md:59-105`
    - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md:11-60`
    - `/home/home/personal/projects/howl/utils/official_docs/kitty/misc-protocol.md:30-36`
- Ghostty owner split:
  - cell content owner exposes semantic cell facts
  - style owner carries semantic colors and attrs
  - shaping run owner consumes style/text but does not own background fill policy
- Alacritty owner split:
  - terminal `Cell` owns semantic fg/bg/attrs
  - display/content derives render RGB, bg alpha, cursor, and selection per frame
  - renderer/text batches glyph draws only
- TigerBeetle owner law:
  - one owner per fact
  - no duplicate control paths
  - no vague buckets
  - assertions and tests must police both positive and negative space

Owner mismatch map

1. Semantic color truth exists in source owners, but the text contract erases it:
  - source semantic owner:
    - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig:1-49`
  - flattened text seam:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`

2. Publication mapping is split between two owners and the behavior already diverges:
  - duplicate owners:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:248-418`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-149`
  - divergent dim/invisible logic:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:183-212`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:102-124`

3. `cluster.zig` is the best current renderable owner, but `direct_normal.zig` rebuilds the same facts locally:
  - cluster owner:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:359-390`
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:551-645`
  - duplicate local rebuild:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:222-253`
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:357-470`

4. Publication cannot enter the full mixed/complex frame pipeline today:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-168`

5. Draw construction is duplicated in `direct_scene.zig` and `scene.zig`, and the clear policy already differs:
  - direct owner:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:82-145`
  - shaped owner:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:710-805`

6. The current `empty` bit is carrying multiple incompatible meanings:
  - “blank/default background” proof:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863-903`
  - “transparent default background” proof:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-580`
  - publication map proves opaque default background simultaneously:
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`

Stale-debt map

1. `contract.CellInput.empty` is stale debt because it is asked to stand in for semantic default background, render transparency, and “skip text cluster” policy at once:
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:283-303`

2. `publication_cell_map.zig` is stale duplicate owner debt, not a smallest true owner:
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:24-149`

3. `direct_scene.MergedBuffers` is a generic bucket struct rejected by owner law:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:25-32`

4. `direct_normal.Source` is stale owner debt because it makes one file responsible for mapping four distinct input shapes into renderables:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:46-57`

5. `preparePublicationWithSessionOptions` is stale product debt because publication still has a special-case fast lane instead of the same text stack as raw cells and rich inputs:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:155-168`

6. Multiple damage owners repeat the same validation idea:
  - `source/text_input.zig`:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:258-309`
  - `direct_scene.zig`:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:5-23`
  - `cluster.zig`:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:511-548`
  - `scene.zig`:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:573-614`

ABI boundary and no-go map

- The shipped source/publication ABI shape is `source/vt.zig`. This sprint does not get to change `SourceColor`, `SourceCell`, `SourceColors`, `PublicationSource`, or their C layout without an explicit new user receipt:
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:13-119`
- The shipped render ABI surface is exported from `libhowl_render.zig`. This sprint does not add Zig-only host shortcuts or bypass the C ABI boundary:
  - `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig:10-38`
- `build.zig` establishes `test:unit` and `test:abi` as the proof roots. This sprint does not weaken or delete those gates:
  - `/home/home/personal/projects/howl/howl-render/build.zig:37-83`
- `prepared/handle.zig` is not the text migration owner. Current live `zig build test:abi` no longer shows the archived prepared-handle crash, so it is not a current sprint blocker and should not be dragged into text slices without fresh evidence:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:62-202`

Proof surface map

- Runtime ABI receipt on 2026-06-10:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
  - result: `190` pass, `4` fail, `0` current prepared-handle crashes
  - failing tests:
    - `source text input converts VT source to text scene input`
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-492`
      - failure point:
        - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:487`
    - `source text input maps publication style attrs dim and invisible`
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:734-797`
      - failure point:
        - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783`
    - `source text input marks Alacritty-empty cells before color mapping`
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863-885`
      - failure point:
        - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:880`
    - `source text input keeps fg-colored blanks empty`
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:887-903`
      - failure point:
        - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:901`

- Stable unit-proof owners already exist:
  - contract defaults:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:362-370`
  - publication default background and inverse/selection semantics:
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`
  - cluster/renderable/span/damage proof:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:754-1050`
  - scene background/clear/cursor proof:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:1047-1135`
  - frame-preparer direct-vs-complex lane proof:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:827-883`

- Stale or contradictory proof currently in the tree:
  - `text_input` still expects transparent default background in one ABI test:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-492`
    - this test must be rewritten before it is counted as proof; the assertion at `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:487` cannot survive the sprint
  - the same file and `publication_cell_map` prove opaque default background elsewhere:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:518-653`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`
  - `keeps fg-colored blanks empty` conflicts with Alacritty’s semantic empty-cell definition because Alacritty requires both default background and default foreground:
    - Howl test:
      - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:887-903`
    - Alacritty reference:
      - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`
    - this stale proof must be deleted or rewritten to an exact non-empty proof before sprint completion
  - `maps publication style attrs dim and invisible` is not allowed to settle dim-factor policy by local choice because current owners disagree and no seeded reference proves the factor:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:734-797`
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:183-195`
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:102-106`
  - `maps publication style attrs dim and invisible` also encodes stale `66%` mapper-side RGB dim assertions that cannot survive Kitty `dim_opacity = 0.4` render policy:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783-787`

Coder reading packs by future slice

1. Slice `text-source-mapper-proof-owner`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

2. Slice `text-renderable-normal-lane-owner`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

3. Slice `text-scene-owner-convergence`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

4. Slice `text-publication-full-path`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

5. Slice `text-style-attrs-render-policy-owner`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`

6. Slice `text-proof-surface-consolidation`
- current-source reads:
  - `/home/home/personal/projects/howl/howl-render/build.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- reference reads:
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Explicit ordered slice plan for the full sprint

1. `text-source-mapper-proof-owner`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- required shape:
  - make one owner authoritative for default-background truth, inverse/selection background preservation, and empty-cell classification at the source-to-text mapping seam
  - rewrite mapper proof so opaque default background and Alacritty-empty semantics are the only accepted truths for source mapping
  - do not choose or encode a new faint/dim factor in this slice
  - keep source ABI owners unchanged:
    - no edits to `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
    - no edits to `/home/home/personal/projects/howl/howl-render/include/howl_render.h`
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/cell.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs`
- required shape targets inside the allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:470-492`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:518-653`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:863-903`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`
- assertions:
  - assert `combining_len <= combining.len` at each VT/publication mapper entry
  - assert inverse/selection transforms do not erase semantic default-background provenance
  - assert empty-cell classification runs on semantic cell truth before any color-resolution shortcut
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input converts VT source to text scene input"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input keeps opaque default background for blank VT cell"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input keeps opaque default background for blank publication cell"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input keeps default background truth through inverse VT cell"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input keeps default background truth through publication selection"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input marks Alacritty-empty cells before color mapping"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input treats foreground-colored blanks as non-empty"`
- non-goals:
  - no semantic contract-shape migration
  - no scene owner changes
  - no frame-preparer control-flow changes
  - no dim/invisible factor choice
  - no source/publication C ABI changes
- stop conditions:
  - if the slice requires changing `SourceCell`, `SourceColor`, or any exported C ABI layout
  - if fixing the stale mapper proofs requires choosing a numeric dim/faint factor
  - if empty-cell truth cannot be expressed without contradicting Alacritty-empty semantics at `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`

2. `text-renderable-normal-lane-owner`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- required shape:
  - preserve semantic fg/bg/underline provenance through the text contract seam instead of flattening source semantics to one RGBA fact before cluster/render policy runs
  - `cluster.zig` becomes the sole owner for renderable-cell construction, text interning, span inference, and damage-filter inclusion
  - `direct_normal.zig` consumes one renderable/text owner for raw cells, publication cells, rich inputs, and prepared renderables
  - publication cell mapping must not happen cell-by-cell inside `direct_normal.sourceItem`
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/underlines.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/c/cell.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- assertions:
  - assert mapped semantic color kind is within the shipped source range before constructing any contract value that reaches cluster/renderable owners
  - assert continuation spans are computed once and reused
  - assert direct-normal rejection happens before any partial draw state is emitted when a non-normal candidate appears under `require_all_normal`
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "cell inputs build text cache renderable cells clusters and runs"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "partial damage filters clean clusters before shaping"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation keeps mixed cell text normals out of legacy path"`
- non-goals:
  - no glyph shaping algorithm changes
  - no scene owner convergence
  - no ABI export changes
- stop conditions:
  - if the slice needs unread shaping owners outside the current read pack to stay correct

3. `text-scene-owner-convergence`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- required shape:
  - backgrounds, clears, cursor draws, and non-glyph decoration draws must have one owner
  - `direct_scene.zig` must become an adapter or be reduced to data-transport; it must not keep a second behavioral implementation of draw construction
  - clear-color policy must be identical across normal-only and mixed/complex frames
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- assertions:
  - assert damage metadata lengths match grid rows at the chosen scene boundary
  - assert merged scene slices remain sorted by `first_cell`
  - assert cursor draw count matches cursor shape geometry on both normal-only and mixed frames
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "scene emits background draws from non-continuation cells"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "scene emits explicit clears for transparent default backgrounds on partial damage"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation direct-renders pure normal cell text inputs"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation marks curly underline cells complex before shaping"`
- non-goals:
  - no font resolver or shaper redesign
  - no render-surface backend or host changes
- stop conditions:
  - if the slice needs host renderer ownership changes outside `howl-render`

4. `text-publication-full-path`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
- required shape:
  - publication must enter the same normal-then-complex pipeline as raw VT cells and rich inputs
  - `preparePublicationWithSessionOptions` may not return `null` for mixed or complex text once the sprint lands
  - publication damage, cursor, selection, and color-state facts must arrive at the same cluster/scene owners as VT source facts
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/color-stack.md`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/style.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- assertions:
  - assert publication complex-cell counts match lane-report complex-cell counts before shaping
  - assert publication path reaches the same scene owner as raw cells when direct normal rejects
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input borrowed publication mapping reuses caller storage"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input borrowed publication mapping applies selection styling across scrollback rows"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation prepares mixed publication cells through non-null publication frame"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation prepares complex publication cells through non-null publication frame"`
- test file targets:
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- non-goals:
  - no `SourceCell` layout changes
  - no exported symbol changes
- stop conditions:
  - if publication needs a different host-facing ABI contract instead of the current source/publication contract
  - if the slice cannot prove non-null mixed and complex publication frames inside `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`

5. `text-style-attrs-render-policy-owner`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
- required shape:
  - preserve dim and invisible as semantic style facts through `text/contract.zig` instead of resolving them inside source/publication mappers
  - this slice may start only after slice `text-scene-owner-convergence` leaves one text draw-construction owner; until then there is no single current render-time dim owner
  - once that prerequisite lands, `text/scene.zig` is the planned render-time dim policy owner and must apply Kitty `dim_opacity = 0.4` when constructing draw colors
  - `prepared/buffer.zig` and `prepared/render_surface_emitter.zig` must remain generic alpha consumers of `draw.color.a`; they must not invent dim policy
  - delete both current mapper-side dim rules (`66%` and `50%`) from the source/publication bridge owners
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - researcher blocker-slice receipt: `research-2026-06-10-text-sprint-01-c2`
  - researcher render-owner receipt: `research-2026-06-10-text-sprint-01-c3`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/buffer.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/misc-protocol.rst`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/docs/changelog.rst`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/types.py`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/cell_vertex.glsl`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- assertions:
  - assert invisible does not erase background truth needed by scene clear/background policy
  - assert dim behavior is entered through one owner only
  - assert the surviving text draw-construction owner writes draw alpha from Kitty `dim_opacity = 0.4`, leaving RGB unchanged
  - assert prepared realization consumes `draw.color.a` unchanged rather than recomputing dim in `prepared/buffer.zig` or `prepared/render_surface_emitter.zig`
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input maps publication style attrs dim and invisible"` only after its current RGB assertions at `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783-787` are rewritten to stop proving mapper-side dim multiplication
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text scene applies kitty dim opacity at render-time for sprite draws"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "render surface surface emitter realizes kitty dim alpha sprite equal to full rgba oracle"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "render surface prepared owner surface equals kitty dim rgba oracle"`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "publication cell map keeps default background truth through inverse and selection"`
- test file targets:
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
- non-goals:
  - no new faint/dim factor invention
  - no host/backend styling work
- stop conditions:
  - if slice `text-scene-owner-convergence` has not yet reduced draw construction to one owner
  - if `text/contract.zig` still cannot carry a dim semantic fact to the render-policy owner
  - if the slice needs a factor other than Kitty `dim_opacity = 0.4`
  - if the slice cannot move dim realization out of mapper-side RGB mutation without changing shipped source/publication ABI layouts

6. `text-proof-surface-consolidation`
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/howl-render/build.zig`
- required shape:
  - delete or rewrite stale tests that encode alpha-hack semantics or duplicated owner behavior
  - leave one proof owner for mapper truth, one for renderable/cluster truth, one for scene draw truth, and one full-pipeline frame proof
  - preserve `test:unit` and `test:abi` as the shipped proof roots
- accountable planning session ids:
  - orchestrator: `orch-2026-06-10-test-accountability-01`
  - researcher: `research-2026-06-10-text-sprint-01`
  - researcher correction receipt: `research-2026-06-10-text-sprint-01-c1`
  - reviewer: `review-2026-06-10-text-sprint-01`
- coder reading paths:
  - `/home/home/personal/projects/howl/howl-render/build.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- assertions:
  - assert build-time test font options resolve to tracked repo-owned fixtures
  - assert no text-stack failures remain in the full ABI suite
- tests:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`
- non-goals:
  - no benchmark work
  - no host runtime changes
- stop conditions:
  - if unrelated non-text failures appear, record them as external blockers and stop instead of hiding them inside the text sprint

Required assertions

- The mapper owner must assert semantic color-kind validity before constructing any text-contract color fact:
  - source kind range:
    - `/home/home/personal/projects/howl/howl-render/src/source/vt.zig:214-225`
- The mapper owner must assert `combining_len <= combining.len` for VT and publication paths:
  - current precedent:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:214-221`
- The cluster owner must assert bounded scratch capacity before appending text/renderable/cluster data:
  - current precedent:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:1037-1060`
- The direct-normal owner must assert rejection happens before partial output on non-normal candidates under `require_all_normal`.
- The scene owner must assert damage metadata lengths match `grid.rows` and that partial-damage spans stay row-bounded:
  - current precedents:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:11-23`
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:518-548`
- The merged-frame owner must assert complex-cell and complex-cluster counts equal the lane report before shaping:
  - current precedent:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:240-252`
- Pair assertions are required for semantic default-background truth:
  - one assertion at mapper construction
  - one assertion at the scene/draw owner boundary before empty/clear/background policy is applied
- Dim requires paired assertions too:
  - one assertion that the semantic dim fact survives the text contract seam
  - one assertion that the surviving draw-construction owner turns that fact into `draw.color.a == 102` for Kitty `dim_opacity = 0.4`

Required tests

- ABI tests that must pass before the sprint is called complete:
  - `source text input converts VT source to text scene input` only after its transparent-default-background assertion at `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:487` is removed or rewritten owner-truly
  - `source text input keeps opaque default background for blank VT cell`
  - `source text input keeps opaque default background for blank publication cell`
  - `source text input keeps default background truth through inverse VT cell`
  - `source text input keeps default background truth through publication selection`
  - `source text input marks Alacritty-empty cells before color mapping`
  - `source text input treats foreground-colored blanks as non-empty`
  - `source text input maps publication style attrs dim and invisible` only after its mapper-side `66%` RGB assertions at `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:783-787` are rewritten to match Kitty `dim_opacity = 0.4` render-policy ownership
  - all borrowed publication mapping ABI tests in:
    - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig:957-1245`
- Unit tests that must remain passing or be rewritten owner-truly:
  - publication map default/inverse selection tests:
    - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig:159-206`
  - cluster renderable/damage tests:
    - `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig:754-1050`
  - scene background/clear/cursor tests:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:1047-1135`
  - frame-preparer fast/complex lane tests:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:827-883`
  - publication non-null frame tests that must be added in:
    - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
    - exact names:
      - `text preparation prepares mixed publication cells through non-null publication frame`
      - `text preparation prepares complex publication cells through non-null publication frame`
  - dim render-time proof tests that must be added:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig`
    - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
    - `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
    - exact names:
      - `text scene applies kitty dim opacity at render-time for sprite draws`
      - `render surface surface emitter realizes kitty dim alpha sprite equal to full rgba oracle`
      - `render surface prepared owner surface equals kitty dim rgba oracle`
- Full-suite gates at sprint end:
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
  - `cd /home/home/personal/projects/howl/howl-render && zig build test:abi`

Risks

- The biggest product risk is “fixing” the four failing ABI tests by another local alpha rule while leaving publication, direct-normal, and scene owners inconsistent.
- The biggest owner risk is moving semantic color truth into `contract.zig` in a way that duplicates `source/cell.zig` instead of narrowing to one authoritative semantic color owner.
- The biggest proof risk is keeping contradictory tests alive and forcing coders to guess which one is authoritative.
- The biggest scope risk is allowing the sprint to drift into font resolver, shaper, or host renderer work before the source-to-renderable and scene-owner seams are repaired.

Proof gaps

- No official protocol/spec source in this expanded local read pack defines one universal cross-terminal numeric faint factor. Kitty, Ghostty, and Alacritty diverge (`0.4` opacity, `0.5` opacity default, `0.66` RGB factor):
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/kitty/options/definition.py:1826-1831`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/config/Config.zig:3710-3715`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/color.rs:15-17`
- That divergence is not a blocker for this sprint because the active planning artifact already records Kitty as the primary pressure for this text-stack decision. If that receipted override is withdrawn, the numeric factor reopens as a blocker immediately.
- Current Howl still has no single render-time dim owner because:
  - `text/contract.zig` drops the dim fact before render policy:
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:81-95`
    - `/home/home/personal/projects/howl/howl-render/src/text/contract.zig:119-132`
  - `text/scene.zig` and `text/direct_scene.zig` both construct draw colors from already-resolved `fg`:
    - `/home/home/personal/projects/howl/howl-render/src/text/scene.zig:665-674`
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:214-244`
- Because of that owner gap, slice `text-style-attrs-render-policy-owner` is still not coder-ready even though the numeric factor is proved. It must stop until the prior scene-owner convergence slice lands and the dim fact survives the contract seam.
- The read pack did not include `font_resolver`, `shape_run`, or grouping owners, so this artifact does not authorize shaping-owner redesign beyond the frame-preparer seams already read:
  - any slice that needs those files must stop and request additional research instead of guessing
- Kitty docs do not define “empty cell” in renderer terms. This artifact therefore uses the user-approved Kitty-first pressure for semantic color/underline truth and Alacritty secondary pressure for empty-cell semantics:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/cell.rs:224-239`
- I did not inspect `include/howl_render.h` in this pass. This sprint draft therefore treats all shipped source/publication/exported layouts as no-go and stops rather than inventing C ABI changes.

Readiness judgment

- This migration can be expressed as sequential coder slices without a new user product decision.
- Ghostty and Alacritty diverge from Kitty on the numeric faint realization (`0.5` opacity default and `0.66` RGB factor versus Kitty `0.4` opacity), but that divergence is not a blocker in this planning round because the active planning artifact already records Kitty as the primary pressure for this text-stack decision.
- This scratchpad is accepted as the planning package for the text sprint. Coding is still not authorized until the orchestrator seeds one accepted execution slice into the live active surface.
- After reviewer acceptance, the first coder slice is ready. The first honest slice is `text-source-mapper-proof-owner`, not a local ABI patch and not a host/backend detour.
- The dim/faint numeric blocker is closed for this planning round, but slice `text-style-attrs-render-policy-owner` is still not genuinely coder-ready because current Howl does not yet expose one render-time dim owner.
- Main blocker inside the current tree:
  - the remaining blocker is owner migration: current Howl still realizes dim inside duplicated mapper owners (`66%` and `50%`), the text contract drops the dim fact before render policy, and scene construction still has duplicate owners instead of one proved render-time dim owner.
