# All Src Shallow Owner Structure Plan

Date: 2026-06-13.

Status: researcher corrected after reviewer rejection; ready for reviewer gate.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.

Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.

Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.

Planning seed commit-hash receipt: root `16a877d`.

Planning package commit-hash receipt: root `c69e039`.

Question:

- What full source-backed sprint plan makes every current package `src/` tree in the workspace as shallow as possible, deletes fake abstraction directories, preserves only true owner subdomains, and proves each cut with owner truth, tests, and receipt-ready slices?

## Required Research Output

- Sources read in order.
- Exact files and line references.
- Current-code facts.
- Reference facts.
- Compact anchor map.
- Owner roles and proposed folder/file shape.
- Sprint scratchpad.
- Explicit ordered slice plan.
- Required assertions.
- Required tests.
- Risks.
- Proof gaps.
- Readiness judgment.

## Mandatory Research Pressure

- Current workspace package `src/` trees.
- Current package build/test roots affected by any planned moves.
- Reference-backed folder pressure from `reference-index.md`.
- TigerBeetle ownership, directness, source order, and test discipline.
- The completed `howl-vt/src/terminal/` deletion is local precedent only; current source and references must still prove each new cut.

## Planning Constraints

- No implementation in research.
- No compatibility shims.
- No fake wrapper folders.
- No vague `**` where exact files are knowable.
- No broad package movement without exact tests and stop conditions.
- No C ABI symbol, enum, struct, or exported-name changes.

## Reviewer Gate

- Reviewer must reject fake abstraction preservation, stale local-history reasoning, missing exact files, missing tests, broad globs where exact files are knowable, or any plan that leaves coder invention about folder boundaries.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md` lines 1-137.
2. `/home/home/personal/projects/howl/loop/orcestrator.md` lines 1-61.
3. `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86.
4. `/home/home/personal/projects/howl/loop/reviewer.md` lines 1-57.
5. `/home/home/personal/projects/howl/loop/coder.md` lines 1-60.
6. Reread `/home/home/personal/projects/howl/loop/researcher.md` lines 1-86.
7. `/home/home/personal/projects/howl/sprints/current.txt` lines 1-40.
8. `/home/home/personal/projects/howl/loops/all-src-shallow-owner-structure-live-loop.txt` lines 1-86.
9. `/home/home/personal/projects/howl/research/2026-06-13-all-src-shallow-owner-structure-plan.md` seed lines 1-56.
10. `/home/home/personal/projects/howl/reference-index.md` lines 1-273.
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 1-511.
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 1-710.
13. Current package `src/` inventories for `howl-pty`, `howl-vt`, `howl-render`, and `howl-linux-host`.
14. Current package build/test roots: `/home/home/personal/projects/howl/build.zig`, `/home/home/personal/projects/howl/howl-pty/build.zig`, `/home/home/personal/projects/howl/howl-vt/build.zig`, `/home/home/personal/projects/howl/howl-render/build.zig`, `/home/home/personal/projects/howl/howl-linux-host/build.zig`.
15. Reference anchors: Alacritty terminal root, PTY seam, display root, renderer root; Ghostty VT public root and terminal root.

## Compact Anchor Map

- Workflow authority: `loop/flow.md` requires planning completion only after exact slice files, shape, tests, non-goals, stop conditions, session ids, and commit receipt status are recorded at lines 22-41.
- Active sprint authority: `sprints/current.txt` lines 20-29 records the restart, all-`src/` scope, user direction, session ids, and root planning receipt `16a877d`; lines 31-40 prohibit coding until reviewer-gated planning exists.
- Live loop authority: `loops/all-src-shallow-owner-structure-live-loop.txt` lines 37-56 records exact user direction, non-goals, and stop conditions.
- Reference order: `reference-index.md` lines 19-36 says references win over Howl history unless explicit override is recorded; lines 60-69 make Alacritty first for host/runtime/display/input/render organization; lines 71-115 make Ghostty first for VT; lines 215-253 make TigerBeetle first for bounds, assertions, naming, structure, directness, and tests.
- TigerBeetle style: `TIGER_STYLE.md` lines 90-95 rejects unnecessary abstractions; lines 104-140 require assertions and exhaustive positive/negative tests; lines 273-282 require exact names; lines 315-335 require source order and putting important things near the top.
- TigerBeetle architecture: `ARCHITECTURE.md` lines 247-249 says dependencies and extra complexity must not hide behind APIs; lines 408-422 supports explicit control/data-plane separation where it is real, not folder theater.
- Alacritty terminal crate root: `alacritty_terminal/src/lib.rs` lines 7-16 exposes shallow first-level owner modules (`event`, `event_loop`, `grid`, `selection`, `term`, `tty`) rather than nested wrapper directories for every file group.
- Alacritty PTY seam: `alacritty_terminal/src/tty/mod.rs` lines 11-19 keeps OS variants under the true `tty` owner; lines 21-44 place interface options in that owner, not in an extra abstraction bucket.
- Alacritty display root: `alacritty/src/display/mod.rs` lines 60-68 keeps `color`, `content`, `cursor`, `hint`, `window`, `bell`, `damage`, and `meter` as direct display modules; this supports a real `display/` owner but not arbitrary nested one-file wrappers under it.
- Alacritty renderer root: `alacritty/src/renderer/mod.rs` lines 26-31 keeps `platform`, `rects`, `shader`, and `text` as direct renderer modules; text is a real renderer subdomain, but small classifications under text need owner proof rather than default nesting.
- Ghostty VT public root: `ghostty/src/lib_vt.zig` lines 15-20 explains the public root curates terminal internals; lines 97-133 keeps terminal input encoding as a targeted `input` package because importing the whole input package brings unwanted dependencies.
- Ghostty terminal root: `ghostty/src/terminal/main.zig` lines 1-28 curates protocol/domain modules directly; lines 43-58 exports `PageList`, `Parser`, `Screen`, `ScreenSet`, `Selection`, `Terminal`, and stream types directly; lines 77-88 keeps C API and tests explicit.

## Current-Code Facts

- Workspace source scope is exactly four current package `src/` trees: `howl-pty/src`, `howl-vt/src`, `howl-render/src`, and `howl-linux-host/src`.
- Root workspace build aggregates package-local steps only; `/home/home/personal/projects/howl/build.zig` lines 20-31 maps `check` and `test` over the four package dirs, lines 41-45 maps ABI tests over product ABI packages, and lines 84-87 shells into package-local builds instead of importing source across package boundaries.
- `howl-pty/build.zig` lines 35-43 builds ABI tests from `src/ffi.zig`; lines 74-88 builds the shipped library from `src/libhowl_pty.zig`; lines 56-72 define package check/test/unit/ABI/integration gates.
- `howl-pty/src/pty.zig` imports `pty/unix.zig` at line 131, while `howl-pty/src/pty/unix.zig` lines 1-3 imports `posix.zig` and `../pty.zig`; `howl-pty/src/pty/posix.zig` lines 1-3 imports `std` and `../pty.zig`. The `pty/` folder exists only to hold two platform implementation files under the already named `pty.zig` owner.
- PTY tests directly depend on the nested path: `howl-pty/test/integration/pty_integration_test.zig` lines 3-4 imports `src/pty.zig` and `src/pty/posix.zig`; `howl-pty/test/unit/pty/posix_test.zig` lines 2-3 imports the same nested file; `howl-pty/test/unit.zig` lines 5-7 wires unit proof files.
- `howl-vt/build.zig` lines 16-31 builds internal/unit roots from `src/howl_vt.zig` and `test_unit.zig`; lines 33-49 builds ABI proof roots; lines 64-78 builds shipped C ABI from `src/libhowl_vt.zig`; lines 80-97 wires simulation.
- `howl-vt/src/howl_vt.zig` lines 1-11 curates parser/input/screen/terminal owner imports; lines 18-30 uses a test block as the root declaration proof.
- `howl-vt/src/libhowl_vt.zig` lines 1-32 exports C ABI functions from `ffi/main.zig`; this makes `ffi/` an ABI translator boundary and not a fake folder.
- `howl-vt/src/csi.zig` lines 1-5 imports `csi/intermediate.zig`, `csi/leader.zig`, `csi/plain.zig`, `csi/private.zig`, and `csi/params.zig`; Ghostty keeps `csi.zig` as a direct terminal module at `terminal/main.zig` line 4, so the Howl `csi/` folder is avoidable extra depth.
- `howl-vt/src/host/apply.zig` lines 1-14 and `howl-vt/src/host/state.zig` lines 1-6 are a two-file host-output subfolder. The C ABI translator is already `ffi/`, and Ghostty public C surface is under its own C path (`reference-index.md` lines 108-115), so `host/` is a fake extra owner in current Howl source.
- `howl-vt/src/selection/projection.zig` and `howl-vt/src/selection/state.zig` form a two-file selection folder, but Ghostty exports `Selection` directly from `terminal/main.zig` line 51 and Alacritty exposes `selection` as a direct owner module at `alacritty_terminal/src/lib.rs` line 11. Current Howl can keep selection ownership with root-level `selection.zig` and `selection_projection.zig`.
- Reviewer rejection re-proof for Slice 2: `howl-vt/src/screen_set.zig` line 3 and `src/terminal.zig` line 7 import `selection/state.zig`; `src/osc_color.zig` line 3, `src/report.zig` line 7, `src/locator.zig` line 4, `src/route.zig` lines 2 and 12, `src/terminal.zig` line 4, `src/ffi/main.zig` line 2, `src/ffi/host_output.zig` line 1, `src/ffi/surface.zig` lines 5-7, `src/ffi/selection.zig` lines 2-3, `src/kitty/apply.zig` line 6, `src/kitty/key.zig` line 2, `src/kitty/color.zig` line 3, and `src/kitty/pointer.zig` line 2 all still depend on `host/`, `selection/`, or `csi/` paths. Slice 2 must authorize every live importer, not only the moved files.
- `howl-vt/src/input/` has five files and is directly curated by `howl_vt.zig` lines 3-7; Ghostty `lib_vt.zig` lines 97-133 supports a targeted input package. Keep `input/`.
- `howl-vt/src/parser/` has parser state, table, UTF-8, owned actions, events, and string controls. Ghostty exports `Parser` directly but also separates parse table and stream ownership in `terminal/main.zig` lines 1-6 and 21. Keep `parser/` for now because it is a real state-machine subdomain with tests under `test/unit/parser/`.
- `howl-vt/src/screen/` has many screen mutation owner files and tests under `test/unit/screen/`; Ghostty exports `Screen` and `ScreenSet` as central owners at `terminal/main.zig` lines 48-49. Keep `screen/`.
- `howl-vt/src/kitty/` has protocol/apply/state/key/color/pointer protocol files. Reference order limits Kitty to UX/protocol maturity (`reference-index.md` lines 255-263), but this folder is protocol ownership rather than a wrapper. Keep `kitty/`.
- `howl-render/build.zig` lines 11-20 pins test font fixtures under `src/text/ft_hb/testdata`; lines 53-68 wires unit tests from `src/test_unit.zig`; lines 70-85 wires ABI tests from `src/test_abi.zig`; lines 103-123 builds shipped C ABI from `src/libhowl_render.zig`; lines 126-152 builds benchmark from `src/benchmark_main.zig`.
- `howl-render/src/libhowl_render.zig` lines 1-7 imports C translator files under `c/`; lines 8-28 exports C ABI symbols. This makes `c/` a true FFI translator boundary.
- `howl-render/src/render_session.zig` lines 2-30 imports `geometry/`, `vt_publication/`, `surface/`, `text/ft_hb/`, `text/raster/`, and `text/shape/` paths. These are the active render owner seams that any move must update.
- `howl-render/src/test/unit/root.zig` lines 2-11 wires render unit proofs explicitly and imports `geometry/geometry_test.zig`, surface tests, C tests, `text/ft_hb/support_test.zig`, and `text/raster/special_test.zig`.
- `howl-render/src/text/surface_preparer.zig` lines 7-21 imports `text/raster`, `text/shape`, `text/ft_hb`, `text/classify`, and `vt_publication`. `shape/`, `raster/`, and `ft_hb/` are real text subdomains; `classify/` is a shallow classification bucket that can be direct text files.
- `howl-render/src/text/classify/symbol_map.zig` line 1 and `text/classify/lane.zig` line 2 import `../contract.zig`; `text/raster/special_test.zig` lines 3-4 imports `../contract.zig` and `../classify/special_glyphs.zig`. The classification files do not require a nested package to preserve ownership.
- `howl-render/src/submitted_surface.zig` line 2 imports `geometry/tokens.zig`; `src/c/surface_geometry.zig` line 3 imports `../geometry/geometry_contract.zig`; `geometry/` is a small owner bucket under render root with no reference-backed folder pressure. Move its files to root with exact names.
- Reviewer rejection re-proof for Slice 3: geometry path users also include `howl-render/src/vt_publication/prepare_queue.zig` lines 2-3, `src/vt_publication/damage.zig` line 2, `src/surface/handle.zig` lines 2-3, `src/surface/handle_test.zig` line 2, `src/surface/prepared_surface.zig` lines 2-3, `src/surface/emitter.zig` line 5, and `src/text/ft_hb/support.zig` line 9. Classification path users also include `src/text/shape/grouping.zig` line 6, `src/text/resolver.zig` line 5, `src/text/direct_normal.zig` line 7, and `src/text/raster/special.zig` line 3. Slice 3 must authorize those importer updates so the deleted folders have zero survivors.
- `howl-render/src/surface/` has prepared surface, handle, compositor, emitter, realizer, resource store, tests, and realizer resource store. The render build comment says it targets one owner-true surface package path at `howl-render/build.zig` line 3; keep `surface/` unless a later source-backed render owner sprint reopens it.
- `howl-render/src/vt_publication/` has ABI/input/theme/cursor/damage/publication/source-slot/queue ownership. This is not a wrapper over C ABI; it is the render-owned publication input contract from VT. Keep `vt_publication/`.
- `howl-linux-host/build.zig` lines 75-120 resolve C ABI deps and translate host-side C headers; lines 111-115 currently imports `src/display/renderer/gl_c.h`; lines 233-335 wire unit/integration tests; lines 338-356 make tests depend on `src/terminal/render/retained.zig` and `src/display/render_surface.zig`.
- `howl-linux-host/src/main.zig` lines 2-10 imports `config/config.zig`, `polling/event_loop.zig`, `input/input.zig`, `display/tab_bar.zig`, and `terminal/tab_slots.zig`; `src/event.zig` lines 4-15 imports the same first-level owners plus `terminal/pty/wait_thread.zig` and `terminal/surface.zig`.
- `howl-linux-host/src/config/config.zig` lines 1-5 imports terminal/window/tab_bar config; the folder is a real config owner and is reference-backed by Alacritty host config pressure.
- `howl-linux-host/src/polling/event_loop.zig` lines 1-4 and `polling/window_wake.zig` lines 1-2 form a two-file wrapper folder. Alacritty exposes `event_loop.rs` at terminal crate root (`alacritty_terminal/src/lib.rs` line 8) and `scheduler.rs` at host root (`reference-index.md` lines 187-193); delete `polling/` by moving both files to root.
- `howl-linux-host/src/display/renderer/gl_c.h` is a one-file nested wrapper under the real display owner. Alacritty renderer modules are direct under renderer (`renderer/mod.rs` lines 26-31), and Howl host GL C translation is display-owned in `build.zig` line 115. Move it to `src/display/gl_c.h`.
- `howl-linux-host/src/terminal/pty/`, `src/terminal/vt/`, and `src/terminal/render/` are avoidable one-extra-depth folders under the true host terminal owner. The host terminal folder itself is owner-true because it owns the embedded terminal surface/session/selection/links/chrome consequences, but its nested folders should collapse to root-level terminal files with owner prefixes.
- Reviewer rejection re-proof for Slice 4: old host paths are still used by `howl-linux-host/src/main.zig` line 5, `src/event.zig` lines 7 and 12, `src/host_test_root.zig` lines 2 and 6, `src/terminal/surface.zig` lines 2, 10-15, 17, 25-28, `src/terminal/input.zig` lines 2, 9-10, `src/terminal/scrollbar.zig` lines 2 and 6, `src/terminal/links.zig` lines 4-5, `src/terminal/selection.zig` lines 3-4, `src/terminal/term.zig` line 4, `src/terminal/surface_test.zig` lines 6 and 9-10, `src/terminal/pty/wait_thread.zig` line 3, `src/terminal/pty/pump.zig` lines 4-5, `src/terminal/vt/input.zig` line 2, and `src/terminal/render/surface_layout.zig` lines 2, 5, 7-8. `howl-linux-host/build.zig` lines 115 and 340 also still name deleted-path files. Slice 4 must include each importer/build user in its allowed-file list.

## Reference Facts

- Real owner subdomains can be first-level modules when they carry state, lifecycle, or protocol truth; Alacritty terminal root proves this with direct modules at `alacritty_terminal/src/lib.rs` lines 7-16.
- OS-specific PTY variants can live under a PTY/TTY owner when the owner itself is a module root; Alacritty `tty/mod.rs` lines 11-19 does this. In Howl Zig, `pty.zig` is already the owner file, so `src/pty/` is one extra directory under the same noun.
- Display is a real host owner; Alacritty `display/mod.rs` lines 60-68 keeps display children one level below display and does not add a one-file `display/renderer/` folder.
- Renderer text is a real subdomain; Alacritty `renderer/mod.rs` lines 26-31 keeps `text` as a renderer submodule. This supports keeping `howl-render/src/text/` while flattening small fake folders inside it when owner truth does not require them.
- VT public roots curate exports and may withhold internals; Ghostty `lib_vt.zig` lines 15-20 and `terminal/main.zig` lines 77-88 support Howl keeping ABI roots and curated package roots explicit.
- VT input encoding is a true targeted package; Ghostty `lib_vt.zig` lines 97-133 explicitly avoids importing the whole input package and exposes focus/key/mouse/paste encoding from input-specific files.
- CSI, OSC, DCS, parser, screen, terminal, selection are VT protocol/state nouns. Ghostty `terminal/main.zig` lines 1-28 imports CSI/OSC/DCS as direct modules and lines 43-58 exposes Parser/Screen/ScreenSet/Selection/Terminal directly. This supports deleting Howl's `csi/`, `host/`, and `selection/` folders while keeping parser/screen/input/kitty/ffi folders that are demonstrably more than wrappers.

## Owner Roles And Proposed Shape

- `howl-pty/src`: keep root owners `libhowl_pty.zig`, `ffi.zig`, `pty.zig`, `session.zig`; move platform implementation files to `posix.zig` and `unix.zig`; delete `src/pty/`.
- `howl-vt/src`: keep true folders `ffi/`, `input/`, `kitty/`, `parser/`, `screen/`; move `host/apply.zig` to `host_apply.zig`; move `host/state.zig` to `host_state.zig`; move `selection/state.zig` to `selection.zig`; move `selection/projection.zig` to `selection_projection.zig`; move `csi/plain.zig`, `csi/private.zig`, `csi/params.zig`, `csi/intermediate.zig`, and `csi/leader.zig` to `csi_plain.zig`, `csi_private.zig`, `csi_params.zig`, `csi_intermediate.zig`, and `csi_leader.zig`; delete `src/host/`, `src/selection/`, and `src/csi/`.
- `howl-render/src`: keep true folders `c/`, `surface/`, `vt_publication/`, `text/`, `text/ft_hb/`, `text/raster/`, and `text/shape/`; move `geometry/geometry.zig`, `geometry/grid_geometry.zig`, `geometry/geometry_contract.zig`, `geometry/tokens.zig`, and `geometry/geometry_test.zig` to root as `geometry.zig`, `grid_geometry.zig`, `geometry_contract.zig`, `tokens.zig`, and `geometry_test.zig`; move `text/classify/special_glyphs.zig`, `text/classify/symbol_map.zig`, `text/classify/lane.zig`, and `text/classify/symbol.zig` to `text/special_glyphs.zig`, `text/symbol_map.zig`, `text/lane.zig`, and `text/symbol.zig`; delete `src/geometry/` and `src/text/classify/`.
- `howl-linux-host/src`: keep true folders `config/`, `display/`, `input/`, and `terminal/`; move `polling/event_loop.zig` and `polling/window_wake.zig` to `event_loop.zig` and `window_wake.zig`; move `display/renderer/gl_c.h` to `display/gl_c.h`; move `terminal/pty/pump.zig`, `terminal/pty/session.zig`, and `terminal/pty/wait_thread.zig` to `terminal/pty_pump.zig`, `terminal/pty_session.zig`, and `terminal/pty_wait_thread.zig`; move `terminal/vt/input.zig`, `terminal/vt/retained.zig`, and `terminal/vt/surface.zig` to `terminal/vt_input.zig`, `terminal/vt_retained.zig`, and `terminal/vt_surface.zig`; move `terminal/render/font_size.zig`, `terminal/render/fonts_linux.zig`, `terminal/render/retained.zig`, and `terminal/render/surface_layout.zig` to `terminal/render_font_size.zig`, `terminal/render_fonts_linux.zig`, `terminal/render_retained.zig`, and `terminal/render_surface_layout.zig`; delete `src/polling/`, `src/display/renderer/`, `src/terminal/pty/`, `src/terminal/vt/`, and `src/terminal/render/`.

## Sprint Scratchpad

- Scope is full current package `src/` trees, not the historical PTY+VT sprint.
- Do not change C headers, exported symbol names, enum/struct layouts, ABI function names, public C include names, or package build step names.
- Do not add compatibility shim files at old import paths. Every move must update imports/tests directly and leave the old directory deleted.
- Use the completed `howl-vt/src/terminal/` deletion as local precedent only: root-level owner files and direct imports beat wrapper directories.
- Keep one true owner folder level when the folder is reference-backed and carries multiple owner files or fixtures: VT `parser`, `screen`, `input`, `kitty`, `ffi`; render `c`, `surface`, `vt_publication`, `text`, text `ft_hb`, text `raster`, text `shape`; host `config`, `display`, `input`, `terminal`.
- Delete one-file and two-file wrapper folders and folders whose files can keep owner truth with direct prefixed names.
- Commit-hash receipt demand for every execution slice: orchestrator must record pre-slice seed commit and accepted slice commit hash; coder must report no staging/commit action and final diff files; reviewer must record acceptance against the exact commit/diff.

## Explicit Ordered Slice Plan

### Slice 1: PTY `src/pty/` Depth Deletion

Allowed files:

- `/home/home/personal/projects/howl/howl-pty/src/pty.zig`
- `/home/home/personal/projects/howl/howl-pty/src/pty/unix.zig`
- `/home/home/personal/projects/howl/howl-pty/src/pty/posix.zig`
- `/home/home/personal/projects/howl/howl-pty/src/unix.zig`
- `/home/home/personal/projects/howl/howl-pty/src/posix.zig`
- `/home/home/personal/projects/howl/howl-pty/test/integration/pty_integration_test.zig`
- `/home/home/personal/projects/howl/howl-pty/test/unit/pty/posix_test.zig`

Required shape:

- Move `src/pty/unix.zig` to `src/unix.zig`.
- Move `src/pty/posix.zig` to `src/posix.zig`.
- Update `src/pty.zig` line 131 equivalent from `pty/unix.zig` to `unix.zig`.
- Update moved file imports from `../pty.zig` to `pty.zig` and from local `posix.zig` as needed.
- Update PTY tests importing `src/pty/posix.zig` to `src/posix.zig`.
- Delete now-empty `src/pty/`.

Required tests:

- From `/home/home/personal/projects/howl/howl-pty`: `zig build test:unit`.
- From `/home/home/personal/projects/howl/howl-pty`: `zig build test:abi`.
- From `/home/home/personal/projects/howl/howl-pty`: `zig build test:integration`.

Non-goals:

- No PTY API behavior change.
- No C ABI header/export change.
- No test root restructuring beyond import path updates.

Stop conditions:

- Stop if `src/pty/` cannot be deleted without changing public PTY ABI or behavior.
- Stop if any old-path shim file is proposed.

Receipts:

- Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.
- Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.
- Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.
- Coder session id: required in execution seed.
- Commit-hash receipt: required on accepted slice.

### Slice 2: VT Fake Folder Deletion

Allowed files:

- `/home/home/personal/projects/howl/howl-vt/src/csi.zig`
- `/home/home/personal/projects/howl/howl-vt/src/report.zig`
- `/home/home/personal/projects/howl/howl-vt/src/locator.zig`
- `/home/home/personal/projects/howl/howl-vt/src/route.zig`
- `/home/home/personal/projects/howl/howl-vt/src/osc.zig`
- `/home/home/personal/projects/howl/howl-vt/src/osc_color.zig`
- `/home/home/personal/projects/howl/howl-vt/src/screen_set.zig`
- `/home/home/personal/projects/howl/howl-vt/src/terminal.zig`
- `/home/home/personal/projects/howl/howl-vt/src/howl_vt.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/main.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/selection.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/runtime.zig`
- `/home/home/personal/projects/howl/howl-vt/src/ffi/host_output.zig`
- `/home/home/personal/projects/howl/howl-vt/src/kitty/apply.zig`
- `/home/home/personal/projects/howl/howl-vt/src/kitty/color.zig`
- `/home/home/personal/projects/howl/howl-vt/src/kitty/key.zig`
- `/home/home/personal/projects/howl/howl-vt/src/kitty/pointer.zig`
- `/home/home/personal/projects/howl/howl-vt/src/host/apply.zig`
- `/home/home/personal/projects/howl/howl-vt/src/host/state.zig`
- `/home/home/personal/projects/howl/howl-vt/src/host_apply.zig`
- `/home/home/personal/projects/howl/howl-vt/src/host_state.zig`
- `/home/home/personal/projects/howl/howl-vt/src/selection/state.zig`
- `/home/home/personal/projects/howl/howl-vt/src/selection/projection.zig`
- `/home/home/personal/projects/howl/howl-vt/src/selection.zig`
- `/home/home/personal/projects/howl/howl-vt/src/selection_projection.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi/plain.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi/private.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi/params.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi/intermediate.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi/leader.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi_plain.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi_private.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi_params.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi_intermediate.zig`
- `/home/home/personal/projects/howl/howl-vt/src/csi_leader.zig`
- `/home/home/personal/projects/howl/howl-vt/test/support/screen_capture.zig`
- `/home/home/personal/projects/howl/howl-vt/test/unit/terminal_snapshot_test.zig`
- `/home/home/personal/projects/howl/howl-vt/test/unit/terminal_modes_test.zig`
- `/home/home/personal/projects/howl/howl-vt/test/unit/terminal_surface_test.zig`
- `/home/home/personal/projects/howl/howl-vt/test/unit/terminal_osc_test.zig`

Required shape:

- Move `host/apply.zig` to `host_apply.zig` and `host/state.zig` to `host_state.zig`; update all `host/...` imports.
- Move `selection/state.zig` to `selection.zig` and `selection/projection.zig` to `selection_projection.zig`; update all imports.
- Move `csi/plain.zig`, `csi/private.zig`, `csi/params.zig`, `csi/intermediate.zig`, and `csi/leader.zig` to root-level prefixed files and update `csi.zig` plus internal CSI imports.
- Update root files, ABI translator files, and Kitty protocol files that still import `host/`, `selection/`, or `csi/` paths so the deleted folders have zero live users.
- Delete `src/host/`, `src/selection/`, and `src/csi/`.
- Keep `ffi/`, `input/`, `kitty/`, `parser/`, and `screen/` unchanged as folders.

Required tests:

- From `/home/home/personal/projects/howl/howl-vt`: `zig build test:unit`.
- From `/home/home/personal/projects/howl/howl-vt`: `zig build test:abi`.
- From `/home/home/personal/projects/howl/howl-vt`: `zig build simulate -- --iterations 1` if the simulation CLI accepts that existing argument; otherwise `zig build simulate:build` is the minimum required simulation proof.

Non-goals:

- No C ABI symbol/header/export changes.
- No parser/screen/input/kitty/ffi folder reshaping in this slice.
- No compatibility old-path shims.

Stop conditions:

- Stop if any moved VT file requires semantic changes beyond import paths due to hidden owner coupling.
- Stop if a test root demands a new wrapper file to keep old imports alive.
- Stop if current source proves `host/`, `selection/`, or `csi/` has a lifecycle owner not captured by direct root files.

Receipts:

- Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.
- Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.
- Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.
- Coder session id: required in execution seed.
- Commit-hash receipt: required on accepted slice.

### Slice 3: Render Root Geometry And Text Classification Flattening

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig`
- `/home/home/personal/projects/howl/howl-render/src/render_session.zig`
- `/home/home/personal/projects/howl/howl-render/src/submitted_surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
- `/home/home/personal/projects/howl/howl-render/src/c/surface_geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/c/submission.zig`
- `/home/home/personal/projects/howl/howl-render/src/c/prepare_request.zig`
- `/home/home/personal/projects/howl/howl-render/src/c/test_support.zig`
- `/home/home/personal/projects/howl/howl-render/src/vt_publication/prepare_queue.zig`
- `/home/home/personal/projects/howl/howl-render/src/vt_publication/damage.zig`
- `/home/home/personal/projects/howl/howl-render/src/surface/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/surface/handle_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/surface/prepared_surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/surface/emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry/geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry/grid_geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry/geometry_contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry/tokens.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry/geometry_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/grid_geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry_contract.zig`
- `/home/home/personal/projects/howl/howl-render/src/tokens.zig`
- `/home/home/personal/projects/howl/howl-render/src/geometry_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/surface_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/ft_hb/support.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/grouping.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/resolver.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/raster/special_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/raster/special.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/classify/special_glyphs.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/classify/symbol_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/classify/lane.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/classify/symbol.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/special_glyphs.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/symbol_map.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/lane.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/symbol.zig`

Required shape:

- Move render `geometry/` files to render root with the same filenames except `grid_geometry.zig` remains `grid_geometry.zig`; update all imports from `geometry/...` and `../geometry/...` to root-level paths.
- Move `text/classify/` files to direct `text/` files with same basename; update all imports from `classify/...` and `../classify/...`.
- Update geometry importers under `vt_publication/`, `surface/`, `c/`, and `text/ft_hb/`, plus classification importers under `text/shape/`, `text/raster/`, and direct `text/` files, so no deleted-folder path remains.
- Delete `src/geometry/` and `src/text/classify/`.
- Keep `c/`, `surface/`, `vt_publication/`, `text/ft_hb/`, `text/raster/`, and `text/shape/`.

Required tests:

- From `/home/home/personal/projects/howl/howl-render`: `zig build test:unit`.
- From `/home/home/personal/projects/howl/howl-render`: `zig build test:abi`.
- From `/home/home/personal/projects/howl/howl-render`: `zig build check`.

Non-goals:

- No render ABI symbol/header/export changes.
- No surface, C ABI translator, vt-publication, ft_hb, raster, or shape reshaping.
- No font fixture movement.

Stop conditions:

- Stop if `src/geometry/` cannot be deleted without changing render ABI or geometry semantics.
- Stop if `text/classify/` files need a new replacement folder or wrapper module.
- Stop if font fixture paths in `build.zig` lines 11-20 are affected.

Receipts:

- Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.
- Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.
- Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.
- Coder session id: required in execution seed.
- Commit-hash receipt: required on accepted slice.

### Slice 4: Host One-Extra-Depth Deletion

Allowed files:

- `/home/home/personal/projects/howl/howl-linux-host/build.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/event.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/host_test_root.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/polling/event_loop.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/polling/window_wake.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/event_loop.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/window_wake.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/display.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/render_surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/render_surface_test.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/gl_c.h`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/gl_c.h`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/links.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/scrollbar.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/input.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/selection.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/surface_test.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/session.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/wait_thread.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty_pump.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty_session.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty_wait_thread.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/input.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt_input.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt_retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt_surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/font_size.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/fonts_linux.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render_font_size.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render_fonts_linux.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render_retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render_surface_layout.zig`

Required shape:

- Move `polling/event_loop.zig` to `event_loop.zig` and `polling/window_wake.zig` to `window_wake.zig`; update imports in `main.zig`, `event.zig`, `host_test_root.zig`, and moved files.
- Move `display/renderer/gl_c.h` to `display/gl_c.h`; update `build.zig` line 115 equivalent to translate from `src/display/gl_c.h`.
- Move terminal nested files to direct `terminal/` prefixed files: `pty_*`, `vt_*`, and `render_*`; update imports in terminal files, host roots, build test modules, and event/main files.
- Update terminal dependents such as `links.zig`, `scrollbar.zig`, `selection.zig`, `term.zig`, `surface.zig`, `surface_test.zig`, and `build.zig` so no `polling/`, `terminal/pty/`, `terminal/vt/`, `terminal/render/`, or `display/renderer/` path survives.
- Delete `src/polling/`, `src/display/renderer/`, `src/terminal/pty/`, `src/terminal/vt/`, and `src/terminal/render/`.
- Keep `config/`, `display/`, `input/`, and `terminal/` as true first-level host owners.

Required tests:

- From `/home/home/personal/projects/howl/howl-linux-host`: `zig build test:unit`.
- From `/home/home/personal/projects/howl/howl-linux-host`: `zig build test:integration`.
- From `/home/home/personal/projects/howl/howl-linux-host`: `zig build check`.

Non-goals:

- No host runtime behavior changes.
- No C ABI import/header content changes except `build.zig` path to the moved host-local `gl_c.h`.
- No deletion of true first-level owners `config/`, `display/`, `input/`, or `terminal/`.

Stop conditions:

- Stop if moving terminal nested files exposes a semantic owner split that cannot be expressed with direct prefixed file names.
- Stop if `gl_c.h` movement changes include resolution or generated C bindings beyond the path.
- Stop if host tests require compatibility shims at old nested paths.

Receipts:

- Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.
- Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.
- Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.
- Coder session id: required in execution seed.
- Commit-hash receipt: required on accepted slice.

### Slice 5: Workspace Aggregate Verification And Empty-Directory Audit

Allowed files:

- No product source edits allowed by default.
- If and only if a prior slice missed a path update, allowed files are limited to files already listed in the failed prior slice and must be returned to that slice for reviewer correction.

Required shape:

- Verify deleted fake folders are absent: `howl-pty/src/pty/`, `howl-vt/src/host/`, `howl-vt/src/selection/`, `howl-vt/src/csi/`, `howl-render/src/geometry/`, `howl-render/src/text/classify/`, `howl-linux-host/src/polling/`, `howl-linux-host/src/display/renderer/`, `howl-linux-host/src/terminal/pty/`, `howl-linux-host/src/terminal/vt/`, and `howl-linux-host/src/terminal/render/`.
- Verify no source import references those old paths.
- Verify no shim files were added to preserve old paths.

Required tests:

- From `/home/home/personal/projects/howl`: `zig build check`.
- From `/home/home/personal/projects/howl`: `zig build test:unit`.
- From `/home/home/personal/projects/howl`: `zig build test:abi`.
- From `/home/home/personal/projects/howl`: `zig build test:integration`.

Non-goals:

- No new reshaping in this slice.
- No benchmark or performance work.
- No implementation fixups beyond returning a failed prior slice to its exact allowed-file list.

Stop conditions:

- Stop if any old fake directory remains.
- Stop if any old path import remains.
- Stop if root aggregate tests fail from a semantic behavior change rather than a path update.

Receipts:

- Orchestrator session id: `orch-2026-06-13-all-src-shallow-structure-01`.
- Researcher session id: `research-2026-06-13-all-src-shallow-structure-01`.
- Reviewer session id: `review-2026-06-13-all-src-shallow-structure-01`.
- Coder session id: required in execution seed if a coder performs verification.
- Commit-hash receipt: final sprint acceptance commit hash required.

## Required Assertions

- Build-path assertions already present in render font fixture validation must remain intact: `howl-render/build.zig` lines 173-180 must still assert test fixture identity.
- Existing C ABI export blocks in `howl-vt/src/libhowl_vt.zig` lines 3-32 and `howl-render/src/libhowl_render.zig` lines 8-28 must remain symbol-identical.
- No old-path shim assertions should be added; the proof is direct import updates plus deleted directories.
- If any moved file currently asserts owner invariants, those assertions must move with the file unchanged except import paths.

## Required Tests

- Package-local tests per slice as listed above are mandatory.
- Final workspace gates from root are mandatory: `zig build check`, `zig build test:unit`, `zig build test:abi`, and `zig build test:integration`.
- VT simulation build/run proof is required for the VT slice as listed because `howl-vt/build.zig` lines 80-97 exposes simulation as a first-class proof surface.
- No test root may be deleted or weakened.

## Risks

- Moving many files can hide a semantic change inside path churn. Reviewer should inspect for import-only/product-no-op changes and reject behavior edits.
- Some package builds may have implicit current-working-directory assumptions for moved files. The stop condition is to fix direct imports only, not add shims.
- Host `gl_c.h` movement touches C translation path in `howl-linux-host/build.zig`; failure mode is include resolution, not render behavior.
- Root workspace aggregate may fail because package build artifacts are nested repositories or local dependency state is dirty; that must be reported as verification output, not papered over.

## Proof Gaps

- I did not inspect every line of every moved implementation file; the folder-shape proof is from source inventories, import seams, build roots, and reference owner pressure. Coder must still update imports mechanically and run the listed gates.
- I did not use archived historical folder plans as authority. Prior done artifacts remain navigation only under active workflow rules.
- I did not prove whether `howl-render/src/surface/` could be flattened in a future sprint. Current source and `howl-render/build.zig` line 3 support keeping it owner-true for this full sprint.
- I did not prove whether `howl-linux-host/src/terminal/` itself could be deleted. Current source shows it owns multiple embedded-terminal host consequences, while the user model targets fake abstraction folders; flattening its nested folders is the source-backed shallow cut without erasing a true owner.

## Readiness Judgment

- Ready for reviewer gate after re-proving the rejected Slice 2, Slice 3, and Slice 4 deletion users from current source and expanding the allowed-file lists to every live importer/build user found.
- The plan covers every current package `src/` tree in the workspace.
- The plan deletes identified fake abstraction folders and avoidable one-extra-depth structures without C ABI symbol, enum, struct, or exported-name changes.
- Implementation is not authorized until reviewer accepts this research package and the orchestrator seeds Slice 1 with a coder session id and commit-hash receipt demand.
