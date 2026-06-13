Historical authority: accepted research plan during the 2026-06-13 render folder/file owner structure sprint.

Why superseded or done: sprint closed with final root receipts `5cfc1d9` and `52418d9`.

Must not be used for: current sprint authority, host folder/file owner planning, or execution authorization.

# Render Folder Owner Structure Plan

Date: 2026-06-13.

Status: reviewer-accepted planning committed; Slice 1 seeded for execution.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-render-folder-structure-01`.

Researcher session id: `research-2026-06-13-render-folder-structure-01`.

Reviewer session id: `review-2026-06-13-render-folder-structure-01`.

Planning commit-hash receipt: root commit `ca6f1c4`.

Question:

- What full source-backed sprint plan restructures `howl-render/src` so only curated owner units live at the top level, child folders remain shallow and owner-true, dead/empty folder debt is removed, and file/folder names approach the deliberateness seen in Ghostty terminal structure without violating Howl's render and C ABI boundaries?

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/loop/researcher.md` reread as active role contract
7. `/home/home/personal/projects/howl/sprints/current.txt`
8. `/home/home/personal/projects/howl/loops/render-folder-owner-structure-live-loop.txt`
9. `/home/home/personal/projects/howl/research/2026-06-13-render-folder-owner-structure-plan.md`
10. `/home/home/personal/projects/howl/reference-index.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal` directory tree
14. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/main.zig`
15. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/lib.zig`
16. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
17. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/osc.zig`
18. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/render.zig`
19. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer` directory tree
20. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
21. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
22. `/home/home/personal/projects/howl/howl-render/src` directory tree
23. `/home/home/personal/projects/howl/howl-render/src/session` directory tree
24. `/home/home/personal/projects/howl/howl-render/src/text` directory tree
25. `/home/home/personal/projects/howl/howl-render/src/surface` directory tree
26. `/home/home/personal/projects/howl/howl-render/src/geometry` directory tree
27. `/home/home/personal/projects/howl/howl-render/src/renderable_content` directory tree
28. `/home/home/personal/projects/howl/howl-render/src/damage` directory tree
29. `/home/home/personal/projects/howl/howl-render/src/prepare` directory tree
30. `/home/home/personal/projects/howl/howl-render/src/storage` directory tree
31. `/home/home/personal/projects/howl/howl-render/src/vt_publication` directory tree
32. `/home/home/personal/projects/howl/howl-render/build.zig`
33. `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig`
34. `/home/home/personal/projects/howl/howl-render/src/render_session.zig`
35. `/home/home/personal/projects/howl/howl-render/src/text_session.zig`
36. `/home/home/personal/projects/howl/howl-render/src/prepared_surface.zig`
37. `/home/home/personal/projects/howl/howl-render/src/submission.zig`
38. `/home/home/personal/projects/howl/howl-render/src/prepare_request.zig`
39. `/home/home/personal/projects/howl/howl-render/src/work_state.zig`
40. `/home/home/personal/projects/howl/howl-render/src/surface_geometry.zig`
41. `/home/home/personal/projects/howl/howl-render/src/handle.zig`
42. `/home/home/personal/projects/howl/howl-render/src/submitted_surface.zig`
43. `/home/home/personal/projects/howl/howl-render/src/test_unit.zig`
44. `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
45. `/home/home/personal/projects/howl/howl-render/src/test_abi.zig`
46. `/home/home/personal/projects/howl/howl-render/src/surface/prepared_surface.zig`
47. `/home/home/personal/projects/howl/howl-render/src/surface/handle.zig`
48. `/home/home/personal/projects/howl/howl-render/src/surface/realizer.zig`
49. `/home/home/personal/projects/howl/howl-render/src/surface/resource_store.zig`
50. `/home/home/personal/projects/howl/howl-render/src/text/surface_preparer.zig`
51. `/home/home/personal/projects/howl/howl-render/src/geometry/geometry.zig`
52. `/home/home/personal/projects/howl/howl-render/src/vt_publication/abi.zig`
53. `/home/home/personal/projects/howl/howl-render/src/vt_publication/publication.zig`
54. `/home/home/personal/projects/howl/howl-render/src/storage/publication_storage.zig`
55. `/home/home/personal/projects/howl/howl-render/src/prepare/queue.zig`
56. `/home/home/personal/projects/howl/howl-render/src/damage/publication_damage.zig`
57. `/home/home/personal/projects/howl/howl-render/src/renderable_content/content.zig`
58. `/home/home/personal/projects/howl/howl-render/src/renderable_content/color.zig`
59. `/home/home/personal/projects/howl/howl-render/src/renderable_content/cursor.zig`

## Exact Files And Line References

- Workflow gate: `loop/flow.md:24-41`, `loop/flow.md:103-108` require a full sequential slice plan, receipts, and a loop note.
- Research output contract: `loop/researcher.md:60-74` defines the mandatory sections in this artifact.
- Active sprint direction: `sprints/current.txt:22-35` fixes the current step as planning only and names the structure debt explicitly.
- Active loop non-goals and stop conditions: `loops/render-folder-owner-structure-live-loop.txt:45-57` ban implementation, narrowing, and rename theater.
- TigerBeetle assertion and naming pressure: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109-139`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:278-281`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315-332`.
- TigerBeetle intentionality and bounded-memory pressure: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-223`.
- Ghostty curated terminal root and C subfolder seam: `utils/dev_references/terminals/ghostty/src/terminal/main.zig:1-28`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:74-79`.
- Ghostty terminal aggregate owner as top-level file: `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:1-4`, `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:40-83`.
- Ghostty render-facing state kept near terminal owners rather than under a generic bucket: `utils/dev_references/terminals/ghostty/src/terminal/render.zig:20-25`, `utils/dev_references/terminals/ghostty/src/terminal/render.zig:37-48`.
- Ghostty protocol subdomain example: `utils/dev_references/terminals/ghostty/src/terminal/osc.zig:16-22`, `utils/dev_references/terminals/ghostty/src/terminal/osc.zig:25-38`.
- Alacritty renderer root keeps only a few root files plus one true child subdomain: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:23-35`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:88-95`.
- Alacritty text renderer subdomain is shallow and explicit: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-75`.
- Build roots currently point at top-level wrapper files: `howl-render/build.zig:53-71`, `howl-render/build.zig:103-127`.
- Public export root currently imports only top-level wrappers: `howl-render/src/libhowl_render.zig:1-28`.
- Current aggregate owner imports across nearly every subdomain and singleton folder: `howl-render/src/render_session.zig:2-30`.
- Current session aggregate owner fields show the actual owner seams: `howl-render/src/render_session.zig:463-477`.
- Current session aggregate owner owns session lifecycle, geometry sync, prepare/submit flow, and cached prepared-handle state: `howl-render/src/render_session.zig:494-507`, `howl-render/src/render_session.zig:510-520`, `howl-render/src/render_session.zig:610-618`, `howl-render/src/render_session.zig:649-731`.
- Current top-level `text_session.zig` is a C wrapper, not the real owner: `howl-render/src/text_session.zig:8-66`.
- Current top-level `prepare_request.zig` is a C wrapper, not the real owner: `howl-render/src/prepare_request.zig:7-64`.
- Current top-level `prepared_surface.zig` is a C wrapper, while the actual owner lives under `surface/`: `howl-render/src/prepared_surface.zig:9-107`, `howl-render/src/surface/prepared_surface.zig:23-98`.
- Current top-level `submission.zig` is a C wrapper, while submit-state ownership lives in `render_session.zig` and `submitted_surface.zig`: `howl-render/src/submission.zig:8-185`, `howl-render/src/submitted_surface.zig:16-94`.
- Current top-level `surface_geometry.zig` and `work_state.zig` are C wrappers: `howl-render/src/surface_geometry.zig:5-65`, `howl-render/src/work_state.zig:6-36`.
- Current top-level `handle.zig` is only a cast helper for C session handles: `howl-render/src/handle.zig:1-7`.
- Current internal prepared-handle owner lives under `surface/` and duplicates the generic `handle` name: `howl-render/src/surface/handle.zig:62-204`.
- Current `session/` directory is empty and therefore pure debt: `/home/home/personal/projects/howl/howl-render/src/session` directory listing showed zero entries.
- Current singleton folders are `damage/`, `prepare/`, and `storage/`; `renderable_content/` has three files but is a generic bucket name rather than a tight owner noun.
- Current curated unit-test root imports owner files directly: `howl-render/src/test/unit/root.zig:1-12`.
- Current ABI test root imports the library root and wrapper tests directly: `howl-render/src/test_abi.zig:4-11`, `howl-render/src/test_abi.zig:13-64`.
- Current VT publication boundary and validation owners live in `vt_publication/`: `howl-render/src/vt_publication/abi.zig:27-77`, `howl-render/src/vt_publication/publication.zig:18-45`, `howl-render/src/vt_publication/publication.zig:91-119`.
- Current dirty-metadata owner is isolated in a singleton folder: `howl-render/src/damage/publication_damage.zig:5-39`, `howl-render/src/damage/publication_damage.zig:86-106`.
- Current retained VT slot owner is isolated in a singleton folder: `howl-render/src/storage/publication_storage.zig:13-66`, `howl-render/src/storage/publication_storage.zig:68-139`.
- Current prepare queue owner is isolated in a singleton folder: `howl-render/src/prepare/queue.zig:8-20`, `howl-render/src/prepare/queue.zig:21-140`.
- Current renderable-content bucket is actually VT-publication mapping work: `howl-render/src/renderable_content/content.zig:2-15`, `howl-render/src/renderable_content/content.zig:67-104`, `howl-render/src/renderable_content/color.zig:5-17`, `howl-render/src/renderable_content/color.zig:78-120`, `howl-render/src/renderable_content/cursor.zig:7-36`.

## Current-Code Facts

- `howl-render/src` currently mixes package roots, real owners, and C ABI translation shims at one level. The proof is `libhowl_render.zig:1-28`, `text_session.zig:8-66`, `prepare_request.zig:7-64`, `prepared_surface.zig:9-107`, `submission.zig:8-185`, `surface_geometry.zig:5-65`, `work_state.zig:6-36`, and `handle.zig:1-7`.
- The actual session owner is `render_session.zig`, not `text_session.zig`. `render_session.zig:463-477` owns the session aggregate fields, while `text_session.zig:8-66` only translates C handles and arguments.
- The actual prepared-surface owner is `surface/prepared_surface.zig`, not top-level `prepared_surface.zig`. Top-level `prepared_surface.zig:9-107` translates ABI calls; `surface/prepared_surface.zig:23-98` owns prepared-surface state and invariants.
- The actual prepared-handle owner is `surface/handle.zig`, while top-level `handle.zig:1-7` is only a cast helper. This is avoidable duplicate naming debt.
- `render_session.zig:2-30` depends directly on `damage/publication_damage.zig`, `storage/publication_storage.zig`, `prepare/queue.zig`, `renderable_content/*`, `geometry/*`, `surface/*`, `vt_publication/*`, and `text/*`. The folder structure exposes too many one-file staging folders rather than a deliberate owner tree.
- `session/` is empty. Keeping it active would be pure fake structure.
- `damage/`, `prepare/`, and `storage/` each contain one file only. They are not pulling their weight as folders.
- `renderable_content/` is not empty, but its name is a generic stage bucket. The files themselves prove a tighter domain: they all convert VT publication state into theme, cursor, and text input for render preparation.
- The curated test roots are already good and should remain curated. `test_unit.zig:1-3`, `test/unit/root.zig:1-12`, and `test_abi.zig:4-11` give one unit root and one ABI root.
- The build graph is already organized around three explicit roots: unit tests, ABI tests, and the C ABI library root. The restructuring should preserve that accountability surface rather than invent new test roots.

## Reference Facts

- Ghostty terminal keeps a long but intentional top-level owner list and uses child folders only for real subdomains like `c/`, `osc/`, `search/`, `kitty/`, and `tmux/`. `main.zig:1-28` plus the terminal directory listing show that pressure.
- Ghostty keeps the C ABI under a dedicated `c/` child folder and exposes it from the curated root through `main.zig:77-79`. That is the strongest local pressure for moving Howl's C shims out of `src/` top level and into `src/c/`.
- Ghostty keeps its aggregate terminal owner as a top-level file, `Terminal.zig:1-4`, rather than burying the primary owner under a generic folder. That supports keeping Howl's aggregate render session owner as a top-level file.
- Ghostty keeps render-facing conversion state near terminal owners rather than under a vague bucket. `render.zig:20-25` explicitly says the render-facing state belongs near terminal state because it converts terminal state into renderer-ready form.
- Alacritty renderer root is shallow. `renderer/mod.rs:26-35` keeps only a small root list plus the `text` subdomain. That is pressure against Howl keeping multiple singleton folders under `src`.
- Alacritty's `renderer/text/mod.rs:11-21` shows that a child folder is justified when it contains a true internal owner family. That supports keeping `text/`, `surface/`, and likely `geometry/` and `vt_publication/`, while deleting weak one-file folders.
- TigerBeetle requires exact names and rejects vague buckets. `TIGER_STYLE.md:273-281` requires file names to be precise nouns in `snake_case`. `renderable_content` is weaker than the actual proven owner names `theme`, `cursor`, `text_input`, `damage`, `prepare_queue`, and `source_slot`.
- TigerBeetle also requires explicit assertions and positive/negative-space checks. `TIGER_STYLE.md:109-139` means the restructure must not weaken the existing validation and invariant surfaces while files move.
- TigerBeetle's architecture doc demands intentional design before implementation. `ARCHITECTURE.md:94-101` and `ARCHITECTURE.md:189-223` support doing one full folder-owner plan now rather than incremental rename drift.

## Compact Anchor Map

- Workflow contract: `loop/flow.md:24-41`, `loop/flow.md:103-108`
- Research contract: `loop/researcher.md:60-74`
- Active sprint scope: `sprints/current.txt:22-35`
- Active loop stop conditions: `loops/render-folder-owner-structure-live-loop.txt:45-57`
- Ghostty curated root and `c/` seam: `utils/dev_references/terminals/ghostty/src/terminal/main.zig:1-28`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:77-79`
- Ghostty aggregate owner: `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:1-4`
- Ghostty render-facing owner placement: `utils/dev_references/terminals/ghostty/src/terminal/render.zig:20-25`
- Alacritty renderer root: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:26-35`
- Alacritty text subdomain: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:11-21`
- TigerBeetle naming/assertion law: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109-139`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273-281`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315-332`
- Howl render public root: `howl-render/src/libhowl_render.zig:1-28`
- Howl render aggregate owner: `howl-render/src/render_session.zig:463-477`, `howl-render/src/render_session.zig:494-507`, `howl-render/src/render_session.zig:649-731`
- Howl render current C shim sprawl: `howl-render/src/text_session.zig:8-66`, `howl-render/src/prepare_request.zig:7-64`, `howl-render/src/prepared_surface.zig:9-107`, `howl-render/src/submission.zig:8-185`, `howl-render/src/surface_geometry.zig:5-65`, `howl-render/src/work_state.zig:6-36`, `howl-render/src/handle.zig:1-7`
- Howl render singleton/dead folders: `howl-render/src/session` directory listing, `howl-render/src/damage/publication_damage.zig:5-39`, `howl-render/src/storage/publication_storage.zig:68-139`, `howl-render/src/prepare/queue.zig:21-140`
- Howl render weak bucket to fold into VT publication subdomain: `howl-render/src/renderable_content/content.zig:2-15`, `howl-render/src/renderable_content/color.zig:78-120`, `howl-render/src/renderable_content/cursor.zig:7-36`

## Owner Roles And Proposed Folder/File Shape

Owner roles:

- `libhowl_render.zig` stays the curated public export root only.
- `render_session.zig` stays the aggregate render-session owner, analogous to Ghostty's top-level `Terminal.zig`.
- `submitted_surface.zig` stays a top-level sibling owner because it owns retained submit-state truth and is not a C shim.
- `geometry/`, `surface/`, `text/`, and `vt_publication/` remain as the only non-test render subdomains.
- A new shallow `c/` folder becomes the only home for C ABI translation shims.

Required shape after the sprint:

```text
howl-render/src/
  benchmark_main.zig
  libhowl_render.zig
  render_session.zig
  submitted_surface.zig
  test_abi.zig
  test_unit.zig
  c/
    text_session.zig
    text_session_handle.zig
    surface_geometry.zig
    prepare_request.zig
    prepared_surface.zig
    submission.zig
    work_state.zig
    test_support.zig
    text_session_test.zig
    surface_geometry_test.zig
    prepare_request_test.zig
    prepared_surface_test.zig
    submission_test.zig
  geometry/
    geometry.zig
    geometry_contract.zig
    grid_geometry.zig
    tokens.zig
  surface/
    compositor.zig
    emitter.zig
    handle.zig
    prepared_surface.zig
    realizer.zig
    realizer_resource_store.zig
    resource_store.zig
  text/
    classify/
    ft_hb/
    raster/
    shape/
    ...existing owner files...
  vt_publication/
    abi.zig
    publication.zig
    damage.zig
    source_slot.zig
    prepare_queue.zig
    theme.zig
    cursor.zig
    text_input.zig
  test/
    unit/
      root.zig
```

Folders that must disappear by sprint end:

- `src/session/`
- `src/damage/`
- `src/prepare/`
- `src/storage/`
- `src/renderable_content/`

Folders that remain shallow because the references justify them:

- `src/c/` because Ghostty keeps the C surface under `terminal/c/`.
- `src/text/` because Alacritty keeps `renderer/text/` as a true renderer subdomain and Howl text already has internal owner families.
- `src/surface/` because prepared-surface/resource realization is a real owner cluster with internal tests and retained-resource state.
- `src/geometry/` because geometry contracts, owner state, and tokens already form a coherent shared subdomain.
- `src/vt_publication/` because ABI validation, retained source slots, damage classification, prepare staging, and publication-to-text mapping are one true ingress subdomain.

Naming decisions that are required, not optional:

- Top-level generic `handle.zig` must stop existing. The C cast helper moves to `c/text_session_handle.zig`.
- Top-level `test_support.zig` must stop existing. The C-wrapper test helper moves to `c/test_support.zig` so wrapper tests stay sibling to the `c/` owners they prove.
- Top-level wrapper-test files must stop existing. `text_session_test.zig`, `surface_geometry_test.zig`, `prepare_request_test.zig`, `prepared_surface_test.zig`, and `submission_test.zig` move to sibling files under `c/`.
- The `renderable_content` bucket name must stop existing. Its work becomes explicit VT-publication ingress owners: `theme.zig`, `cursor.zig`, and `text_input.zig`.
- The singleton-folder file names must become owner-true inside `vt_publication/`: `damage.zig`, `source_slot.zig`, and `prepare_queue.zig`.

## Sprint Scratchpad

- Main debt: top-level `src` is polluted with ABI shims, duplicate names, and weak singleton folders.
- Strongest reference pressure: Ghostty `terminal/main.zig` plus `terminal/c/` for the C surface; Alacritty `renderer/mod.rs` plus `renderer/text/` for shallow renderer organization.
- Minimal true owner outcome: keep one aggregate owner at top level, keep only true subdomains, move all C translation into one child folder, and fold the VT ingress bucket work into `vt_publication/`.
- Explicitly rejected shapes:
  - keeping `session/` empty for future work
  - keeping top-level ABI shims beside real owners
  - preserving `damage/`, `prepare/`, `storage/` as one-file folders
  - preserving `renderable_content/` as a generic stage bucket
  - inventing a new umbrella runtime or `utils`/`common` folder

## Explicit Ordered Slice Plan

### Slice 1

- Name: C boundary quarantine.
- Accountable sessions:
  - orchestrator: `orch-2026-06-13-render-folder-structure-01`
  - researcher: `research-2026-06-13-render-folder-structure-01`
  - reviewer: `review-2026-06-13-render-folder-structure-01`
  - coder: assigned later by orchestrator
- Commit-hash receipt demand: required before Slice 2 can start.
- Allowed files:
  - `howl-render/src/libhowl_render.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/text_session.zig` to move/delete
  - `howl-render/src/handle.zig` to move/delete
  - `howl-render/src/surface_geometry.zig` to move/delete
  - `howl-render/src/prepare_request.zig` to move/delete
  - `howl-render/src/prepared_surface.zig` to move/delete
  - `howl-render/src/submission.zig` to move/delete
  - `howl-render/src/work_state.zig` to move/delete
  - `howl-render/src/test_support.zig` to move/delete
  - `howl-render/src/text_session_test.zig` to move/delete
  - `howl-render/src/surface_geometry_test.zig` to move/delete
  - `howl-render/src/prepare_request_test.zig` to move/delete
  - `howl-render/src/prepared_surface_test.zig` to move/delete
  - `howl-render/src/submission_test.zig` to move/delete
  - `howl-render/src/surface/handle_test.zig`
  - `howl-render/src/surface/emitter_test.zig`
  - `howl-render/src/c/text_session.zig`
  - `howl-render/src/c/text_session_handle.zig`
  - `howl-render/src/c/surface_geometry.zig`
  - `howl-render/src/c/prepare_request.zig`
  - `howl-render/src/c/prepared_surface.zig`
  - `howl-render/src/c/submission.zig`
  - `howl-render/src/c/work_state.zig`
  - `howl-render/src/c/test_support.zig`
  - `howl-render/src/c/text_session_test.zig`
  - `howl-render/src/c/surface_geometry_test.zig`
  - `howl-render/src/c/prepare_request_test.zig`
  - `howl-render/src/c/prepared_surface_test.zig`
  - `howl-render/src/c/submission_test.zig`
  - `howl-render/src/test_abi.zig`
  - `howl-render/src/test/unit/root.zig`
- Exact required shape:
  - `libhowl_render.zig` must import C shims only from `src/c/`.
  - No top-level C shim files may remain.
  - The old generic top-level `handle.zig` must be gone.
  - `test_support.zig` must move to `src/c/test_support.zig`.
  - The five top-level wrapper-test files must move to sibling files under `src/c/`.
  - `render_session.zig` must rewire its current `@import("test_support.zig")` test use to `@import("c/test_support.zig")`.
  - `surface/handle_test.zig` and `surface/emitter_test.zig` must rewire their current `../test_support.zig` imports to `../c/test_support.zig`.
  - `test_abi.zig` must import the wrapper-test files from `src/c/` paths only.
  - `test/unit/root.zig` must import `text_session_test.zig` and `submission_test.zig` from `src/c/` paths only.
  - Function names and ABI exports must stay byte-for-byte identical.
- Exact tests:
  - `zig build test:abi`
  - `zig build test:unit`
- Exact non-goals:
  - no owner redesign inside `render_session.zig`
  - no movement of `surface/`, `text/`, `geometry/`, or `vt_publication/` owners yet
  - no ABI symbol additions or removals
- Exact stop conditions:
  - stop if any build root outside `libhowl_render.zig` requires a new public entrypoint name
  - stop if any caller outside `howl-render/src` depends on the deleted top-level shim paths directly
  - stop if reviewer judges the `c/` folder insufficiently source-backed

### Slice 2

- Name: VT publication ingress consolidation.
- Accountable sessions:
  - orchestrator: `orch-2026-06-13-render-folder-structure-01`
  - researcher: `research-2026-06-13-render-folder-structure-01`
  - reviewer: `review-2026-06-13-render-folder-structure-01`
  - coder: assigned later by orchestrator
- Commit-hash receipt demand: required before Slice 3 can start.
- Allowed files:
  - `howl-render/src/render_session.zig`
  - `howl-render/src/benchmark_main.zig`
  - `howl-render/src/damage/publication_damage.zig` to move/delete
  - `howl-render/src/storage/publication_storage.zig` to move/delete
  - `howl-render/src/prepare/queue.zig` to move/delete
  - `howl-render/src/renderable_content/content.zig` to move/delete
  - `howl-render/src/renderable_content/color.zig` to move/delete
  - `howl-render/src/renderable_content/cursor.zig` to move/delete
  - `howl-render/src/text/direct_normal.zig`
  - `howl-render/src/text/surface_preparer.zig`
  - `howl-render/src/text/shape/cluster.zig`
  - `howl-render/src/vt_publication/abi.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/damage.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/vt_publication/prepare_queue.zig`
  - `howl-render/src/vt_publication/theme.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/vt_publication/text_input.zig`
- Exact required shape:
  - `damage/`, `prepare/`, `storage/`, and `renderable_content/` must be removed.
  - Their owners must live under `vt_publication/` with the exact file names listed above.
  - `render_session.zig` imports must point only at `vt_publication/*`, `geometry/*`, `surface/*`, and `text/*` for this ingress path.
  - `benchmark_main.zig`, `text/direct_normal.zig`, `text/surface_preparer.zig`, and `text/shape/cluster.zig` must rewire their old `renderable_content/*` imports to the exact `vt_publication/*` owners named in this slice.
  - No new generic folder may replace the removed ones.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:abi`
  - `zig build check`
- Exact non-goals:
  - no changes to exported C symbol names
  - no changes to `surface/` or `text/` internal folder shape
  - no owner extraction from `render_session.zig`
- Exact stop conditions:
  - stop if any moved file reveals that `vt_publication/` is not the true owner seam
  - stop if the rename from `renderable_content` to explicit ingress owner names forces semantic behavior changes rather than path-only rewiring
  - stop if reviewer finds remaining generic or duplicate naming debt inside the new `vt_publication/` shape

### Slice 3

- Name: Tree cleanup and proof-root closure.
- Accountable sessions:
  - orchestrator: `orch-2026-06-13-render-folder-structure-01`
  - researcher: `research-2026-06-13-render-folder-structure-01`
  - reviewer: `review-2026-06-13-render-folder-structure-01`
  - coder: assigned later by orchestrator
- Commit-hash receipt demand: required for sprint acceptance.
- Allowed files:
  - `howl-render/build.zig`
  - `howl-render/src/test_unit.zig`
  - `howl-render/src/test/unit/root.zig`
  - `howl-render/src/test_abi.zig`
  - `howl-render/src/libhowl_render.zig`
  - `howl-render/src/benchmark_main.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/submitted_surface.zig`
  - `howl-render/src/c/text_session.zig`
  - `howl-render/src/c/text_session_handle.zig`
  - `howl-render/src/c/surface_geometry.zig`
  - `howl-render/src/c/prepare_request.zig`
  - `howl-render/src/c/prepared_surface.zig`
  - `howl-render/src/c/submission.zig`
  - `howl-render/src/c/work_state.zig`
  - `howl-render/src/c/test_support.zig`
  - `howl-render/src/c/text_session_test.zig`
  - `howl-render/src/c/surface_geometry_test.zig`
  - `howl-render/src/c/prepare_request_test.zig`
  - `howl-render/src/c/prepared_surface_test.zig`
  - `howl-render/src/c/submission_test.zig`
  - `howl-render/src/geometry/geometry.zig`
  - `howl-render/src/geometry/geometry_contract.zig`
  - `howl-render/src/geometry/grid_geometry.zig`
  - `howl-render/src/geometry/tokens.zig`
  - `howl-render/src/surface/compositor.zig`
  - `howl-render/src/surface/emitter.zig`
  - `howl-render/src/surface/handle.zig`
  - `howl-render/src/surface/prepared_surface.zig`
  - `howl-render/src/surface/realizer.zig`
  - `howl-render/src/surface/realizer_resource_store.zig`
  - `howl-render/src/surface/resource_store.zig`
  - `howl-render/src/vt_publication/abi.zig`
  - `howl-render/src/vt_publication/publication.zig`
  - `howl-render/src/vt_publication/damage.zig`
  - `howl-render/src/vt_publication/source_slot.zig`
  - `howl-render/src/vt_publication/prepare_queue.zig`
  - `howl-render/src/vt_publication/theme.zig`
  - `howl-render/src/vt_publication/cursor.zig`
  - `howl-render/src/vt_publication/text_input.zig`
  - deletion of `howl-render/src/session/`
- Exact required shape:
  - `src/session/` must be deleted.
  - Build roots must still point at one unit test root, one ABI test root, one library root, and one benchmark root.
  - No stale imports to deleted paths may remain.
  - `src/` top level must contain only these files: `benchmark_main.zig`, `libhowl_render.zig`, `render_session.zig`, `submitted_surface.zig`, `test_abi.zig`, and `test_unit.zig`.
  - `src/` top level must not contain `test_support.zig`, `text_session_test.zig`, `surface_geometry_test.zig`, `prepare_request_test.zig`, `prepared_surface_test.zig`, or `submission_test.zig`.
  - Final location truth for the helper and wrapper-test owners is exact:
    - `test_support.zig` lives at `src/c/test_support.zig`.
    - `text_session_test.zig` lives at `src/c/text_session_test.zig`.
    - `surface_geometry_test.zig` lives at `src/c/surface_geometry_test.zig`.
    - `prepare_request_test.zig` lives at `src/c/prepare_request_test.zig`.
    - `prepared_surface_test.zig` lives at `src/c/prepared_surface_test.zig`.
    - `submission_test.zig` lives at `src/c/submission_test.zig`.
  - The only top-level folders that may remain are `c/`, `geometry/`, `surface/`, `text/`, `vt_publication/`, and `test/`.
- Exact tests:
  - `zig build check`
  - `zig build test:unit`
  - `zig build test:abi`
- Exact non-goals:
  - no new public roots
  - no new test roots
  - no behavior changes beyond path/name preservation
- Exact stop conditions:
  - stop if any deleted folder still has live owner content not covered by earlier slices
  - stop if any external build path or generated artifact still hardcodes removed source paths
  - stop if reviewer sees rename theater rather than a materially cleaner tree

## Required Assertions

- All current ABI boundary validations must survive file moves without weakening:
  - `howl-render/src/vt_publication/abi.zig:27-77`
  - `howl-render/src/vt_publication/publication.zig:91-119`
  - `howl-render/src/damage/publication_damage.zig:5-39`
- Geometry invariants must survive unchanged:
  - `howl-render/src/geometry/geometry.zig:33-45`
- Prepared-surface invariants must survive unchanged:
  - `howl-render/src/surface/prepared_surface.zig:39-97`
- Prepared-handle ownership and lifecycle assertions must survive unchanged:
  - `howl-render/src/surface/handle.zig:103-203`
- Session-owner lifecycle and prepare/submit state assertions must survive unchanged:
  - `howl-render/src/render_session.zig:495-507`, `howl-render/src/render_session.zig:563-566`, `howl-render/src/render_session.zig:610-618`, `howl-render/src/render_session.zig:649-731`
- New folder moves must not replace assertions with comments. TigerBeetle pressure forbids that.

## Required Tests

- Mandatory proof commands for every slice unless the slice contract narrows them further:
  - `zig build test:unit`
  - `zig build test:abi`
- Mandatory final sprint proof:
  - `zig build check`
  - `zig build test:unit`
  - `zig build test:abi`
- Existing coverage that specifically guards this structure work and must keep passing:
  - `howl-render/src/test_abi.zig:13-64`
  - `howl-render/src/test/unit/root.zig:1-12`
  - `howl-render/src/render_session.zig:777-938`
  - `howl-render/src/submitted_surface.zig:96-153`
  - `howl-render/src/damage/publication_damage.zig:134-175`
  - `howl-render/src/storage/publication_storage.zig:259-404`
  - `howl-render/src/prepare/queue.zig:216-318`

## Risks

- Slice 2 is the sharp edge. Moving the weak ingress folders into `vt_publication/` is source-backed, but it touches the highest number of imports.
- `render_session.zig` is the central dependency hub. Path-only changes can still produce accidental behavioral edits if the coder broadens scope.
- The naming change from `renderable_content` to `theme`, `cursor`, and `text_input` is justified by the file contents, but reviewer scrutiny should be severe because naming mistakes here would become long-lived debt.
- Build-root drift is possible because `build.zig` still points at top-level roots. Slice 3 must close that receipt explicitly.

## Proof Gaps

- I did not inspect downstream package imports outside `howl-render/` for source-path references because the sprint target is folder-owner planning, not execution. The coder must verify no external source-path dependence exists before deleting moved files.
- I did not inspect generated docs or editor tooling that might mention old paths. That is acceptable at planning time but must be checked during execution if any tooling breaks.
- I did not prove that `geometry/` should be collapsed further. Current evidence is strong enough to keep it, not strong enough to demand another reshape.

## Readiness Judgment

- Reviewer gate readiness: ready.
- Coding authorization: not authorized.
- Reason: the folder/file target shape, disappearing folders, surviving folders, exact slice order, tests, assertions, non-goals, stop conditions, and receipt demands are now explicit and source-backed enough for reviewer pressure.
