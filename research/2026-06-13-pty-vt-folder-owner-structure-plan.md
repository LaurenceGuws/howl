# PTY VT Folder Owner Structure Plan

Date: 2026-06-13.

Status: reviewer-repaired; ready for acceptance.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`.

Researcher session id: `research-2026-06-13-pty-vt-folder-structure-01`.

Reviewer session id: `review-2026-06-13-pty-vt-folder-structure-01`.

Planning commit-hash receipt: root `efbd9ad`.

Question:

- What full source-backed sprint plan restructures `howl-pty/src` and `howl-vt/src` so only curated PTY and VT owner units live at the top level, child folders remain shallow and owner-true, dead or weak folder boundaries are removed, and file or folder names move toward Ghostty-grade intentionality without violating PTY, VT, host, and C ABI boundaries?

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/loop/researcher.md` reread
7. `/home/home/personal/projects/howl/sprints/current.txt`
8. `/home/home/personal/projects/howl/loops/pty-vt-folder-owner-structure-live-loop.txt`
9. `/home/home/personal/projects/howl/research/2026-06-13-pty-vt-folder-owner-structure-plan.md`
10. `/home/home/personal/projects/howl/reference-index.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. Current PTY package roots and tests:
   - `/home/home/personal/projects/howl/howl-pty/build.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/libhowl_pty.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/ffi.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/pty.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/session.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/test_unit.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/test_integration.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/test/abi.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/test/ffi.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/pty/unix.zig`
   - `/home/home/personal/projects/howl/howl-pty/src/pty/posix.zig`
14. Current VT package roots and tests:
   - `/home/home/personal/projects/howl/howl-vt/build.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/libhowl_vt.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/howl_vt.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/ffi.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/terminal.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/stream_terminal.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/screen.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/screen_set.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/parser/main.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/action/route.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/action/vocabulary.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/control/mode.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/host/state.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/host/apply.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/xterm/csi.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/abi.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/screen_capture.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/stream_harness.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/pty_feed_record.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/terminal_benchmark.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/terminal_benchmark_main.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/simulation/main.zig`
15. Ghostty VT and termio references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/lib_vt.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/main.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Screen.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/csi.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/osc.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/dcs.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/Selection.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/point.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/pty.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Termio.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Exec.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Thread.zig`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/mailbox.zig`
16. Alacritty PTY pressure references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/mod.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`

## Exact Files And Line References

### Workflow And Role Contract

- `loop/flow.md:24-41` requires every slice to carry exact allowed files, required shape, tests, non-goals, stop conditions, session ids, and commit-hash receipt status.
- `loop/flow.md:98-109` requires a loop scratchpad note for each non-trivial pass.
- `loop/researcher.md:60-74` defines the active research output contract for this artifact.
- `sprints/current.txt:22-35` fixes the active step as planning only and names the PTY plus VT folder-owner sprint sessions.
- `loops/pty-vt-folder-owner-structure-live-loop.txt:37-57` records the exact user direction, non-goals, and stop conditions.

### Current PTY Facts

- `howl-pty/build.zig:17-54` roots PTY unit, ABI, and integration proofs in `src/test_unit.zig`, `src/test/abi.zig`, and `src/test_integration.zig`.
- `howl-pty/src/test_unit.zig:3-8` proves unit coverage is currently driven by a `src` test root that reaches more `src/*_test.zig` files.
- `howl-pty/src/test_integration.zig:1-4` proves integration coverage is also rooted in `src`.
- `howl-pty/src/test/abi.zig:1-103` and `howl-pty/src/test/ffi.zig:1-88` prove ABI-only tests also live under `src`.
- `howl-pty/src/libhowl_pty.zig:1-19` is a pure export root and already fits the curated-top-level rule.
- `howl-pty/src/ffi.zig:1-211` is a single C-ABI translation owner; it is not a generic utility bucket.
- `howl-pty/src/pty.zig:4-131` owns the PTY contract surface, control signal enum, and backend vtable seam.
- `howl-pty/src/session.zig:17-24`, `howl-pty/src/session.zig:57-83`, and `howl-pty/src/session.zig:222-258` show `session.zig` is the real queue and lifecycle owner.
- `howl-pty/src/pty/unix.zig:1-27` and `howl-pty/src/pty/posix.zig:50-260` prove the `pty/` folder is a true platform subdomain, not a random bucket.

### Current VT Facts

- `howl-vt/build.zig:16-25` and `howl-vt/src/howl_vt.zig:1-45` root VT unit proofs in `src/howl_vt.zig`.
- `howl-vt/build.zig:26-42` roots VT ABI proofs in `src/test/abi.zig`.
- `howl-vt/build.zig:73-107` roots simulation and benchmark entrypoints under `src/simulation/main.zig` and `src/terminal_benchmark_main.zig`.
- `howl-vt/src/libhowl_vt.zig:1-32` is a pure export root and already fits the curated-top-level rule.
- `howl-vt/src/ffi.zig:5-13` and `howl-vt/src/ffi.zig:48-80` prove VT currently duplicates the `ffi` concept at both `src/ffi.zig` and `src/ffi/`.
- `howl-vt/src/howl_vt.zig:1-18` imports `action/`, `parser/`, `screen.zig`, `screen_set.zig`, `selection/`, and `terminal.zig` directly from the top level, proving the current top-level VT surface is too broad.
- `howl-vt/src/terminal.zig:17-37` shows `terminal.zig` is the actual terminal aggregate owner.
- `howl-vt/src/terminal.zig:250-254` proves surface publication is terminal-owned state, not a separate top-level product root.
- `howl-vt/src/stream_terminal.zig:116-144` and `howl-vt/src/stream_terminal.zig:192-259` show stream application is a terminal-core owner, not a package-top concept.
- `howl-vt/src/screen.zig:25-47` and `howl-vt/src/screen.zig:91-108` show `screen.zig` is a real aggregate owner with many per-owner definitions already under `screen/`.
- `howl-vt/src/screen_set.zig:72-78` and `howl-vt/src/screen_set.zig:168-246` prove `screen_set.zig` is a separate owner from `screen.zig`.
- `howl-vt/src/parser/main.zig:23-54` and `howl-vt/src/parser/main.zig:185-220` show parser bounds and parser-owned action shapes already exist, but the parser owner lives in `parser/main.zig` rather than a curated VT-core folder.
- `howl-vt/src/action/route.zig:1-13` and `howl-vt/src/action/route.zig:29-94` show semantic routing is terminal-internal glue spanning `host`, `kitty`, `control`, and `xterm`.
- `howl-vt/src/control/mode.zig:11-30` and `howl-vt/src/control/mode.zig:32-67` show mode state and mutation are terminal-owned protocol state, not a package-top subproduct.
- `howl-vt/src/host/state.zig:27-44` and `howl-vt/src/host/state.zig:56-93` show retained host consequences are bounded and owner-true, but still terminal-internal.
- `howl-vt/src/host/apply.zig:16-54` shows host consequence application is a small terminal subdomain.
- `howl-vt/src/xterm/csi.zig:1-15` shows Xterm routing is a protocol owner split, not a top-level package owner.
- `howl-vt/src/test/screen_capture.zig:1-107`, `howl-vt/src/test/stream_harness.zig:1-23`, and `howl-vt/src/test/pty_feed_record.zig:1-120` prove `src/test/` currently mixes ABI tests with reusable proof helpers and replay support.
- `howl-vt/src/test/terminal_benchmark.zig:1-220` and `howl-vt/src/terminal_benchmark_main.zig:1-6` show benchmark code currently lives under `src`, which violates the requested curated-owner-only rule for `src`.
- `howl-vt/src/simulation/main.zig:5-7` explicitly says simulation is not a unit test, yet it still lives under `src`.

### Reference Facts

- `reference-index.md:71-129` names Ghostty terminal and termio as the first pressure for VT and PTY folder shape.
- `reference-index.md:154-178` names Alacritty `event_loop` and `tty` as the secondary PTY and runtime seam pressure.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100` requires explicit, bounded control flow.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104-149` requires assertions and pair-assertion pressure.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273-281` requires strong nouns and snake_case file names.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315-335` requires source order and top-down readability.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-223` ties static bounds to explicit owner structures.
- `utils/dev_references/terminals/ghostty/src/lib_vt.zig:15-20` shows Ghostty keeps a curated public root that delegates to `terminal/main.zig`.
- `utils/dev_references/terminals/ghostty/src/terminal/main.zig:8-28` and `utils/dev_references/terminals/ghostty/src/terminal/main.zig:30-78` show VT core presented as one curated `terminal/` subdomain root.
- `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:40-83` shows the terminal aggregate owner sits inside that `terminal/` subdomain with screen, modes, and protocol state under it.
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig:1-16` and `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig:33-95` show screen switching is its own owner under `terminal/`, not top-level.
- `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:14-31`, `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:49-85`, and `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:187-203` show parser ownership and bounds live under terminal.
- `utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig:19-39` shows stream-to-terminal mutation also lives under terminal.
- `utils/dev_references/terminals/ghostty/src/terminal/csi.zig:3-55`, `.../osc.zig:25-197`, and `.../dcs.zig:10-25` show protocol owners sit directly in the terminal subdomain, not in a generic `xterm/` bucket.
- `utils/dev_references/terminals/ghostty/src/terminal/Selection.zig:23-52` and `.../point.zig:6-50` show typed selection and coordinate owners are part of terminal core.
- `utils/dev_references/terminals/ghostty/src/pty.zig:19-37` and `utils/dev_references/terminals/ghostty/src/pty.zig:106-123` show PTY boundary ownership remains one explicit owner, while platform detail stays internal.
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:1-5`, `.../Termio.zig:38-64`, and `.../Termio.zig:218-260` show termio owns runtime orchestration while terminal remains a sub-owner it contains, which sharpens the PTY and VT split.
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig:18-45` and `.../stream_handler.zig:62-99` show host-effect and DCS or APC handling belong to the termio or terminal seam, not to package-top buckets.
- `utils/dev_references/terminals/ghostty/src/termio/Exec.zig:1-4` and `.../Exec.zig:85-155` show subprocess and PTY lifecycle ownership belongs at the PTY or termio seam, not mixed into VT package roots.
- `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:1-12` and `.../mailbox.zig:10-18` show runtime thread or mailbox concepts belong under termio, not under VT core folders.
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7-16` keeps PTY, event loop, and term as first-class package roots, not mixed inside terminal core.
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:23-28` gives the exact PTY burst constants already mirrored in `howl-pty/src/session.zig:85-105`.
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/mod.rs:21-44` and `.../tty/mod.rs:61-97` show PTY configuration and PTY trait boundaries stay in a dedicated PTY seam.
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:194-260` shows platform PTY process setup belongs under the PTY seam, not under terminal core.

## Current-Code Facts

- PTY already has the right product owners at `src/libhowl_pty.zig`, `src/ffi.zig`, `src/pty.zig`, `src/session.zig`, and `src/pty/`; its main debt is proof-root placement inside `src`, not a missing owner concept.
- VT does not have the right top-level discipline. It spreads terminal-core owners, protocol routing, host consequence plumbing, test helpers, simulation, and benchmark entrypoints across too many `src` roots.
- VT already has genuine owner seams. The problem is placement, not absence: `terminal.zig`, `screen.zig`, `screen_set.zig`, `stream_terminal.zig`, parser bounds, mode state, host consequence bounds, and protocol routers are all real owners or owner subdomains.
- The current `src/ffi.zig` plus `src/ffi/` split is structurally weak. It duplicates the same concept across file and folder form.
- The current VT `src/test/` folder is also structurally weak. It mixes ABI proof entrypoints with reusable capture and replay helpers and benchmark support.
- Simulation and benchmark code under VT `src/` directly violate the user requirement to keep only curated owner units under `src`.

## Compact Anchor Map

### Stable References

- Ghostty VT public-root pattern: `src/lib_vt.zig` delegates to `src/terminal/main.zig`.
- Ghostty VT owner cluster: `terminal/main.zig`, `terminal/Terminal.zig`, `terminal/Screen.zig`, `terminal/ScreenSet.zig`, `terminal/Parser.zig`, `terminal/stream_terminal.zig`, `terminal/csi.zig`, `terminal/osc.zig`, `terminal/dcs.zig`, `terminal/Selection.zig`, `terminal/point.zig`.
- Ghostty PTY boundary pattern: one explicit `pty.zig` owner; runtime orchestration stays in `termio/`.
- Alacritty PTY pressure: `tty/` and `event_loop.rs` keep PTY lifecycle and bounded read policy outside terminal core.
- TigerBeetle style pressure: snake_case names, no bucket folders, explicit bounded owners, top-down curated roots, tests and simulations kept explicit.

### Current Howl Owner Seams That Govern This Sprint

- PTY contract owner: `howl-pty/src/pty.zig`.
- PTY queue and lifecycle owner: `howl-pty/src/session.zig`.
- VT aggregate owner: `howl-vt/src/terminal.zig`.
- VT screen owners: `howl-vt/src/screen.zig` and `howl-vt/src/screen_set.zig`.
- VT parser owner and parser bounds: `howl-vt/src/parser/main.zig`.
- VT stream mutation owner: `howl-vt/src/stream_terminal.zig`.
- VT mode owner: `howl-vt/src/control/mode.zig`.
- VT host consequence owner: `howl-vt/src/host/state.zig`.

## Owner Roles And Proposed Shape

### PTY

Keep PTY product owners in `src` and move PTY proof roots out of `src`.

Target `howl-pty/src/` shape:

- `libhowl_pty.zig`
- `ffi.zig`
- `pty.zig`
- `session.zig`
- `pty/`
  - `unix.zig`
  - `posix.zig`

Target `howl-pty/` proof shape outside `src`:

- `test/unit.zig`
- `test/integration.zig`
- `test/abi.zig`
- `test/ffi.zig`
- `test/unit/session_test.zig`
- `test/unit/pty_test.zig`
- `test/unit/pty_posix_test.zig`
- `test/unit/pty_backend_test.zig`
- `test/integration/session_integration_test.zig`
- `test/integration/pty_integration_test.zig`

Rationale:

- Ghostty and Alacritty both keep PTY as an explicit boundary owner, not as terminal-core spillover.
- The PTY `pty/` folder already qualifies as a shallow true subdomain because it holds platform implementation details only.
- The real PTY debt is that tests live under `src`; that is placement debt, not owner debt.

### VT

Create one Ghostty-shaped VT-core subdomain under `src/terminal/`, keep only curated top-level roots or true subdomains under `src`, and move non-product proof or simulation surfaces out of `src`.

Target `howl-vt/src/` shape:

- `howl_vt.zig`
- `libhowl_vt.zig`
- `ffi/`
  - `main.zig`
  - existing per-ABI translation owners now under `src/ffi/`
- `input/`
  - existing input encoding owners
- `terminal/`
  - `main.zig`
  - `terminal.zig`
  - `screen.zig`
  - `screen_set.zig`
  - `parser.zig`
  - `stream_terminal.zig`
  - `selection.zig`
  - `point.zig`
  - `route.zig`
  - `vocabulary.zig`
  - `mode.zig`
  - `report.zig`
  - `locator.zig`
  - `osc_color.zig`
  - `c0.zig`
  - `esc.zig`
  - `csi.zig`
  - `osc.zig`
  - `dcs.zig`
  - `publication.zig`
  - `host/`
    - `apply.zig`
    - `state.zig`
  - `kitty/`
    - `apply.zig`
    - `state.zig`
    - `protocol.zig`
    - `key.zig`
    - `color.zig`
    - `pointer.zig`
  - `screen/`
    - existing per-screen definition files
  - `parser/`
    - existing parser definition files
  - `selection/`
    - `projection.zig`
  - `csi/`
    - existing CSI helper files

Target VT proof and non-product roots outside `src`:

- `test/abi.zig`
- `test/unit.zig`
- `test/unit/terminal_end_to_end_test.zig`
- `test/unit/terminal_snapshot_test.zig`
- `test/unit/terminal_modes_test.zig`
- `test/unit/screen_test.zig`
- `test/unit/terminal_osc_test.zig`
- `test/unit/terminal_surface_test.zig`
- `test/unit/action/route_test.zig`
- `test/unit/control/report_test.zig`
- `test/unit/screen/cursor_test.zig`
- `test/unit/screen/history_test.zig`
- `test/unit/screen/resize_test.zig`
- `test/unit/screen/tabs_test.zig`
- `test/unit/screen/write_test.zig`
- `test/unit/parser/csi_test.zig`
- `test/unit/parser/events_test.zig`
- `test/unit/parser/main_test.zig`
- `test/unit/parser/string_control_test.zig`
- `test/unit/xterm/csi_mapping_test.zig`
- `test/support/screen_capture.zig`
- `test/support/stream_harness.zig`
- `benchmark/terminal_benchmark.zig`
- `benchmark/pty_feed_record.zig`
- `benchmark/m7_baseline.zig`
- `simulation/main.zig`
- `simulation/protocol.zig`
- `simulation/scrollback.zig`
- `simulation/assets/xterm-ctlseqs.ms`

Rationale:

- Ghostty pressure says VT core should cluster under one deliberate terminal subdomain, not across many top-level folders.
- TigerBeetle pressure says keep snake_case file names, so Howl should take Ghostty's folder boundary lesson without copying Ghostty's CamelCase file names.
- `screen/`, `parser/`, `kitty/`, `host/`, and `csi/` qualify as shallow child folders because they are true subdomains or per-owner definition groups.
- `xterm/`, `action/`, `control/`, `surface/`, and top-level `selection/` are not good top-level package concepts once VT core is clustered under `terminal/`.
- `src/ffi.zig` should become `src/ffi/main.zig` so the `ffi` concept exists in one place only.

## Sprint Scratchpad

- The sprint must do real owner-boundary cleanup, not rename theater.
- PTY is small enough to finish in one slice because its structural debt is concentrated in proof-root placement.
- VT is the larger problem. The real cleanup is not just moving files; it is reducing `src/` to curated roots and moving terminal-internal concepts under one `terminal/` owner cluster.
- The plan deliberately does not create any new runtime umbrella. PTY remains PTY. VT remains VT. Host runtime remains host-side.
- No slice may change shipped ABI names or widen product scope.
- No slice may leave both old and new folder concepts live at the same time after acceptance.

## Explicit Ordered Slice Plan

### Slice 1

- Name: PTY proof-root relocation out of `src`
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Allowed files:
  - `howl-pty/build.zig`
  - `howl-pty/src/test_unit.zig`
  - `howl-pty/src/test_integration.zig`
  - `howl-pty/src/test/abi.zig`
  - `howl-pty/src/test/ffi.zig`
  - `howl-pty/src/session_test.zig`
  - `howl-pty/src/pty_test.zig`
  - `howl-pty/src/session_integration_test.zig`
  - `howl-pty/src/pty_integration_test.zig`
  - `howl-pty/src/pty/posix_test.zig`
  - `howl-pty/src/pty/pty_test.zig`
  - `howl-pty/test/**`
- Required shape:
  - `src` keeps only PTY product owners and the true PTY platform subdomain.
  - All PTY proof roots move to `test/` outside `src`.
  - PTY build roots point to `test/unit.zig`, `test/integration.zig`, and `test/abi.zig`.
  - ABI support helpers also move out of `src`.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:integration`
  - `zig build test:abi`
  - all in `/home/home/personal/projects/howl/howl-pty`
- Non-goals:
  - no PTY transport logic changes
  - no ABI enum or symbol changes
  - no PTY owner renames beyond proof-root relocation
- Stop conditions:
  - stop if any PTY test file remains under `src`
  - stop if build roots still point at `src` proof files
  - stop if product logic changes beyond import-path churn are required

### Slice 2

- Name: VT proof and non-product roots out of `src`
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Allowed files:
  - `howl-vt/build.zig`
  - `howl-vt/src/ffi.zig`
  - `howl-vt/src/libhowl_vt.zig`
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/test/abi.zig`
  - `howl-vt/src/test/screen_capture.zig`
  - `howl-vt/src/test/stream_harness.zig`
  - `howl-vt/src/test/pty_feed_record.zig`
  - `howl-vt/src/test/terminal_benchmark.zig`
  - `howl-vt/src/terminal_benchmark_main.zig`
  - `howl-vt/src/simulation/**`
  - `howl-vt/src/ffi/**`
  - `howl-vt/src/**/*_test.zig`
  - `howl-vt/test/**`
  - `howl-vt/benchmark/**`
  - `howl-vt/simulation/**`
- Required shape:
  - `src/ffi.zig` becomes `src/ffi/main.zig`; `ffi` exists in one place only.
  - VT unit test root moves from `src/howl_vt.zig` to `test/unit.zig`; `src/howl_vt.zig` stops importing unit proof files.
  - All VT unit proof files move from `src/**/*_test.zig` to `test/unit/` with owner-shaped subfolders preserved.
  - VT ABI test root moves to `test/abi.zig`.
  - Benchmark entrypoint and helpers move to `benchmark/`.
  - Simulation entrypoint and assets move to `simulation/`.
  - `src` no longer contains proof, benchmark, or simulation-only roots.
- Exact tests:
  - `zig build test:abi`
  - `zig build test:unit:build`
  - `zig build simulate:build`
  - `zig build benchmark:m7_baseline:build`
  - all in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no VT semantic changes
  - no terminal-core folder moves yet beyond `ffi` root cleanup
  - no new benchmark features or simulation features
- Stop conditions:
  - stop if any VT `*_test.zig` file remains under `src`
  - stop if any benchmark or simulation file remains under `src`
  - stop if both `src/ffi.zig` and `src/ffi/main.zig` survive together
  - stop if build step names or shipped library outputs change

### Slice 3

- Name: VT terminal core root establishment
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Allowed files:
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/screen.zig`
  - `howl-vt/src/screen_set.zig`
  - `howl-vt/src/stream_terminal.zig`
  - `howl-vt/src/parser/main.zig`
  - `howl-vt/src/parser/**`
  - `howl-vt/src/screen/**`
  - `howl-vt/src/selection/**`
  - `howl-vt/src/surface/publication.zig`
  - `howl-vt/src/terminal/**`
  - `howl-vt/test/unit.zig`
  - `howl-vt/test/unit/**`
- Required shape:
  - Create `src/terminal/main.zig` as the curated VT-core root.
  - Move the terminal aggregate owner, screen owners, parser owner, stream owner, selection owner, point owner, and publication owner into `src/terminal/`.
  - Preserve snake_case file names.
  - Keep `screen/` and `parser/` as shallow per-owner definition folders under `src/terminal/`.
  - Update `src/howl_vt.zig` to import VT core through `src/terminal/`, not package-top owner files.
  - Update `test/unit/` imports in the same slice; tests must follow the moved owner paths directly and must not rely on package-top compatibility shims.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:abi:build`
  - all in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no protocol-owner consolidation yet for `action`, `control`, `xterm`, `kitty`, or `host`
  - no behavior rewrites
- Stop conditions:
  - stop if terminal aggregate ownership is still split between top-level and `src/terminal/`
  - stop if old top-level owner files remain as compatibility shims after acceptance
  - stop if the coder needs to invent a second curated VT-core root
  - stop if any unit proof file still imports old terminal-core source paths after acceptance

### Slice 4

- Name: VT protocol and consequence subdomain absorption
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Allowed files:
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/ffi/**`
  - `howl-vt/src/action/**`
  - `howl-vt/src/control/**`
  - `howl-vt/src/host/**`
  - `howl-vt/src/kitty/**`
  - `howl-vt/src/xterm/**`
  - `howl-vt/src/terminal/**`
  - `howl-vt/test/**`
  - `howl-vt/benchmark/**`
- Required shape:
  - Remove package-top `action/`, `control/`, `host/`, `kitty/`, and `xterm/` folders.
  - Re-home those owners under `src/terminal/`, using direct terminal-owned file names for protocol roots and shallow child folders only where the owner has multiple definitions.
  - `xterm/` disappears as an umbrella bucket; protocol roots become `src/terminal/c0.zig`, `esc.zig`, `csi.zig`, `osc.zig`, and `dcs.zig`, with `csi/` retained only as a true subdomain.
  - `host/` and `kitty/` remain only as `src/terminal/host/` and `src/terminal/kitty/`.
  - Update `test/unit/`, `test/abi.zig`, and benchmark imports in the same slice; tests and proof helpers must follow the moved owner paths directly and must not rely on package-top compatibility shims.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:abi`
  - `zig build benchmark:m7_baseline:build`
  - all in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no host runtime architecture change
  - no new public Zig API
  - no convenience wrapper layer
- Stop conditions:
  - stop if stale top-level VT buckets remain in `src`
  - stop if imported paths depend on compatibility mirrors
  - stop if any owner becomes harder to name or harder to test than before
  - stop if any unit, ABI, or benchmark proof still imports old protocol or consequence source paths after acceptance

### Slice 5

- Name: Final proof wiring and dead-path removal
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Allowed files:
  - `howl-pty/build.zig`
  - `howl-vt/build.zig`
  - moved PTY and VT proof roots created by earlier slices
  - any now-empty PTY or VT source paths that must be deleted
- Required shape:
  - no stale PTY or VT active source paths remain after the re-home
  - build roots prove only the final locations
  - `src` trees for both packages contain curated product owners only
  - no `*_test.zig`, benchmark, simulation, or proof-support file remains under either package `src`
- Exact tests:
  - `zig build test` in `/home/home/personal/projects/howl/howl-pty`
  - `zig build test` in `/home/home/personal/projects/howl/howl-vt`
  - `zig build simulate:build` in `/home/home/personal/projects/howl/howl-vt`
  - `zig build benchmark:m7_baseline:build` in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no new cleanup outside PTY or VT
  - no execution-phase redesign
- Stop conditions:
  - stop if any stale path survives only because imports still reference it
  - stop if final build roots still mention old locations
  - stop if reviewer cannot diff the final tree without reconstructing hidden moves

## Required Assertions

- Preserve PTY exported symbols exactly as listed in `howl-pty/src/libhowl_pty.zig:3-18`.
- Preserve VT exported symbols exactly as listed in `howl-vt/src/libhowl_vt.zig:3-31`.
- Keep PTY transport burst constants unchanged unless a separate source-backed sprint reopens the policy in `howl-pty/src/session.zig:85-105`.
- Keep VT parser bounds unchanged unless a separate source-backed sprint reopens them in `howl-vt/src/parser/main.zig:23-54`.
- Assert there is only one active root for each concept after the move: one `ffi` root, one terminal-core root, one unit test root per package, one benchmark root, one simulation root, one ABI test root per package.
- Assert build roots resolve only through final paths.
- Assert any deleted folder is actually empty and unreferenced before acceptance.
- Assert `src` contains no `*_test.zig` files after Slice 2 acceptance.

## Required Tests

- PTY:
  - `zig build test:unit`
  - `zig build test:integration`
  - `zig build test:abi`
  - `zig build test`
- VT:
  - `zig build test:unit`
  - `zig build test:abi`
  - `zig build test`
  - `zig build simulate:build`
  - `zig build benchmark:m7_baseline:build`

## Risks

- VT import churn is large. The main risk is leaving stale path mirrors or partial folder moves that weaken ownership instead of clarifying it.
- VT proof helpers currently live in `src/test/`; moving them without reclassifying unit, ABI, benchmark, simulation, and replay helpers could create a second weak bucket outside `src`.
- Ghostty uses CamelCase file names for some owners, while Howl is bound by TigerBeetle snake_case discipline. The sprint must take Ghostty's folder and owner lessons without copying Ghostty file naming literally.
- Build-root churn can silently reintroduce duplicate proof entrypoints if old `src` test roots are left behind.

## Proof Gaps

- I did not inspect every VT test file body because the planning question is folder and owner structure, not behavioral review. The slice plan therefore treats the unit-root inventory and moved proof surfaces as the accountable object, not individual test semantics.
- I did not inspect the archived historical planning artifacts because the live workflow and stable references were sufficient and the role contract says archived prose is navigation only.
- I did not inspect Ghostty `terminal/c/` in detail because this sprint is about PTY and VT source tree owner structure, not redesigning the C ABI surface.

## Readiness Judgment

- Ready for reviewer acceptance after repair.
- Reviewer gate found a real planning defect in the first draft: VT top-level and nested unit proof files would have remained under `src`, and later slices did not explicitly allow updating those proof imports after terminal-core and protocol re-homing.
- The plan is repaired to move all VT `src/**/*_test.zig` files to `test/unit/` in Slice 2, make `test/unit.zig` the unit proof root, and allow later slices to update those proof imports alongside owner moves.
- The repaired plan is full-sprint, sequential, reference-backed, and does not authorize coding.

## Coding Authorization

- None. This artifact plans the sprint only.
