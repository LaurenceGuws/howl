Historical authority: accepted research and repaired planning artifact during the 2026-06-13 PTY+VT folder/file owner structure sprint.

Why superseded or done: sprint closed with final root receipts `610ea74` and `2ec1f24`.

Must not be used for: current all-src shallow directory sprint authority, execution authorization, or live planning.

# PTY VT Folder Owner Structure Plan

Date: 2026-06-13.

Status: researcher-repaired after reviewer rejection of stale proof buckets and broad Slice 4/5 dependency globs; ready for reviewer gate.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`.

Researcher session id: `research-2026-06-13-pty-vt-folder-structure-01`.

Slice 3 correction researcher session id: `research-2026-06-13-pty-vt-folder-structure-01`.

Slice 4 and Slice 5 repair researcher session id: `research-2026-06-13-pty-vt-folder-structure-01`.

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
17. Slice 3 correction current-source import proof after Slice 2 acceptance:
    - `rg -n '@import\("(\.\./)*(src/)?(terminal\.zig|screen\.zig|screen_set\.zig|stream_terminal\.zig|parser/main\.zig|parser/events\.zig|parser/owned_actions\.zig|selection/state\.zig|selection/projection\.zig|surface/publication\.zig|screen/|parser/)' howl-vt`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/lifecycle.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/runtime.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/surface.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/handle.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/selection.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/action/vocabulary.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/action/route.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/host/apply.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/host/state.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/control/report.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/control/osc_color.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/xterm/osc.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/xterm/dcs.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/xterm/csi/params.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/libhowl_vt.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/ffi/main.zig`
    - `/home/home/personal/projects/howl/howl-vt/build.zig`
18. Slice 4 and Slice 5 repair proof after nested `howl-vt` commit `20fb714` and explicit user override:
    - Current `howl-vt/src` tree from `Glob("**/*.zig", path="/home/home/personal/projects/howl/howl-vt/src")`
    - Current `howl-vt/test` tree from `Glob("**/*.zig", path="/home/home/personal/projects/howl/howl-vt/test")`
    - Current `howl-vt/benchmark` tree from `Glob("**/*.zig", path="/home/home/personal/projects/howl/howl-vt/benchmark")`
    - Current direct import proof from `Grep("@import\\(", path="/home/home/personal/projects/howl/howl-vt/src", include="*.zig")`
    - Current direct import proof from `Grep("@import\\(", path="/home/home/personal/projects/howl/howl-vt/test", include="*.zig")`
    - Current direct import proof from `Grep("@import\\(", path="/home/home/personal/projects/howl/howl-vt/benchmark", include="*.zig")`
    - `/home/home/personal/projects/howl/howl-vt/src/howl_vt.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/terminal/main.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/terminal/terminal.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/action/route.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/action/vocabulary.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/host/state.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/host/apply.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/control/mode.zig`
    - `/home/home/personal/projects/howl/howl-vt/src/xterm/csi.zig`
19. Slice 4 and Slice 5 rejection repair proof for exact allowed files:
    - Current old protocol-bucket import proof from `Grep("src/(action|control|xterm)|\\.\\./(action|control|xterm)/|\\.\\.\\.*/src/(action|control|xterm)|\"(action|control|xterm)/", path="/home/home/personal/projects/howl/howl-vt", include="*.zig")`
    - Current temporary terminal-wrapper import proof from `Grep("src/terminal|terminal/main\\.zig|\\.\\./terminal/|\"terminal/", path="/home/home/personal/projects/howl/howl-vt", include="*.zig")`

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

### Slice 3 Block Correction Facts

- `howl-vt/build.zig:33-49` and `howl-vt/build.zig:53-58` prove `zig build test:abi:build` compiles the ABI test artifact and its `ffi` import module, so stale FFI imports are a Slice 3 blocker, not a later cleanup.
- `howl-vt/src/libhowl_vt.zig:1-32` exports the shipped C ABI through `src/ffi/main.zig`; Slice 3 must not change exported names, but `src/ffi/**` must stay buildable after terminal-core paths move.
- `howl-vt/src/ffi/main.zig:1-13` imports host state plus FFI leaf owners; its children compile the terminal-core dependencies that `test:abi:build` reaches.
- `howl-vt/src/ffi/lifecycle.zig:2-3`, `howl-vt/src/ffi/runtime.zig:2`, `howl-vt/src/ffi/surface.zig:2-7`, `howl-vt/src/ffi/handle.zig:1`, and `howl-vt/src/ffi/selection.zig:2-3` directly import old top-level terminal, screen, screen_set, selection, and projection paths. These files must be allowed for import-path updates in Slice 3.
- `howl-vt/src/action/vocabulary.zig:1` and `howl-vt/src/action/route.zig:6` directly import parser paths that move under `src/terminal/`; these are import-path consequences only, not protocol-owner absorption.
- `howl-vt/src/host/apply.zig:4` and `howl-vt/src/host/state.zig:6` directly import screen and parser paths that move under `src/terminal/`; host consequence ownership remains in place until Slice 4.
- `howl-vt/src/control/report.zig:2` and `howl-vt/src/control/osc_color.zig:2` directly import `../screen.zig`; control owner movement remains Slice 4, but these import paths must be corrected in Slice 3.
- `howl-vt/src/xterm/osc.zig:3`, `howl-vt/src/xterm/dcs.zig:1`, and `howl-vt/src/xterm/csi/params.zig:3` directly import parser paths that move under `src/terminal/`; xterm owner absorption remains Slice 4.
- `rg` proof after Slice 2 shows benchmark and proof support files also import old terminal-core paths, including `howl-vt/benchmark/terminal_benchmark.zig:2`, `howl-vt/benchmark/pty_feed_record.zig:3`, `howl-vt/test/support/screen_capture.zig:2-3`, and `howl-vt/test/support/stream_harness.zig:1`; Slice 3 must update those direct imports rather than leave stale paths or add compatibility shims.
- `rg` proof also shows no `howl-vt/src/kitty/**` file directly imports the terminal-core paths moved in Slice 3, so `src/kitty/**` is not required in the Slice 3 allowed file list.
- Decision: Slice 3 can remain `VT terminal core root establishment` with an expanded allowed file list for direct import-path updates. Splitting or reordering would create an artificial compatibility window or require stale ABI/benchmark/proof imports, both of which violate the no-shim and proof requirements.

### Slice 4 And Slice 5 Override Repair Facts After `howl-vt` `20fb714`

- Current `howl-vt/src` contains temporary terminal-core owners under `src/terminal/`: `main.zig`, `terminal.zig`, `screen.zig`, `screen_set.zig`, `stream_terminal.zig`, `publication.zig`, `parser/**`, `screen/**`, and `selection/**`.
- Current `howl-vt/src` still contains package-top `action/`, `control/`, `host/`, `kitty/`, and `xterm/` folders after Slice 3.
- `howl-vt/src/howl_vt.zig:1-8` imports `action/route.zig`, `action/vocabulary.zig`, `input/**`, and `terminal/main.zig`; this root must change once `action/` disappears and again when `terminal/main.zig` is deleted.
- `howl-vt/src/terminal/main.zig:1-8` is only a temporary curated terminal wrapper exporting parser, screen, selection, stream, and terminal owners; under the user override, Slice 5 must delete this wrapper instead of preserving it.
- `howl-vt/src/terminal/terminal.zig:2-10` imports `../control/mode.zig`, `../host/state.zig`, `../kitty/state.zig`, and local terminal-core files; this file proves Slice 4 import churn is required before the final Slice 5 wrapper deletion.
- `howl-vt/src/action/route.zig:1-12` is a routing owner that imports `host`, `kitty`, `control`, terminal parser events, and `xterm` protocol roots; it is not an owner-true final `action/` folder.
- `howl-vt/src/action/vocabulary.zig:1-5` is a semantic vocabulary owner coupled to parser bounds; it should become a direct `src/vocabulary.zig` owner, not a folder wrapper.
- `howl-vt/src/host/state.zig:27-44` keeps explicit host consequence bounds and `howl-vt/src/host/apply.zig:16-54` applies host consequences; `host/` remains a true shallow consequence subdomain in the final no-`terminal/` tree.
- `howl-vt/src/control/mode.zig:11-30` owns terminal mode state and `howl-vt/src/control/mode.zig:32-67` owns mode mutation; it should become direct `src/mode.zig`, not remain in a generic `control/` folder.
- `howl-vt/src/xterm/csi.zig:1-15` routes CSI handling through helper files under `xterm/csi/`; final layout should move the owner root to direct `src/csi.zig` and retain `src/csi/` only as the true helper subdomain.
- Current proof imports still name pre-Slice-4 top-level folders in `test/unit/action/route_test.zig:2-3`, `test/unit/control/report_test.zig:2`, `test/unit/xterm/csi_mapping_test.zig:2-3`, `test/unit/terminal_modes_test.zig:2`, `test/unit/screen_test.zig:3`, and `test/unit/screen/{cursor,history,resize,tabs,write}_test.zig`; Slice 4 must update and re-home the stale proof paths to final owner-true proof files without preserving `action/`, `control/`, or `xterm/` proof buckets.
- Current direct old-bucket import proof also requires exact Slice 4 import edits in `src/host/apply.zig`, `src/host/state.zig`, `src/input/encode.zig`, `src/kitty/apply.zig`, `src/kitty/color.zig`, `src/kitty/protocol.zig`, `src/terminal/terminal.zig`, `src/terminal/stream_terminal.zig`, `src/terminal/screen.zig`, `src/terminal/screen/{apply,cursor,erase,rect}.zig`, and the moving owners under `src/action/**`, `src/control/**`, and `src/xterm/**`; these are import consequences of deleting `action/`, `control/`, and `xterm/`, not behavior authority.
- Current temporary terminal-wrapper import proof for Slice 5 requires exact dependency edits in `src/ffi/{handle,lifecycle,runtime,surface,selection}.zig`, `src/host/{apply,state}.zig`, final `src/{route,vocabulary,report,osc_color,osc,dcs}.zig`, `src/csi/params.zig`, all unit proof files that currently import `src/terminal/**`, `test/support/{screen_capture,stream_harness}.zig`, and `benchmark/{terminal_benchmark,pty_feed_record}.zig`.
- Decision: Slice 4 must move directly toward the final no-wrapper layout by deleting `src/action/`, `src/control/`, and `src/xterm/` as package-top buckets and re-homing their owners under `src/` and `src/csi/`. Moving those folders under `src/terminal/` temporarily would create known throwaway depth after an explicit override and would force Slice 5 to undo extra work.
- Decision: Slice 4 should not move `src/host/` or `src/kitty/` under `src/terminal/`. In the final no-wrapper layout, `host/` and `kitty/` are shallow true subdomains at `src/host/` and `src/kitty/`.
- Decision: Slice 5 must delete `src/terminal/` entirely by moving terminal-core contents back under `src/`, deleting `src/terminal/main.zig`, and updating all product, proof, support, and benchmark imports to the final direct paths.

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
- VT still does not have the final top-level discipline after Slice 3. It temporarily clusters terminal-core owners under `src/terminal/`, while protocol routing remains split through package-top `action/`, `control/`, and `xterm/` folders.
- VT already has genuine owner seams. The problem is placement, not absence: `terminal.zig`, `screen.zig`, `screen_set.zig`, `stream_terminal.zig`, parser bounds, mode state, host consequence bounds, kitty state, and protocol routers are all real owners or owner subdomains.
- The current `src/ffi.zig` plus `src/ffi/` split is structurally weak. It duplicates the same concept across file and folder form.
- Slice 2 removed VT proof, simulation, and benchmark roots from `src`; remaining proof and benchmark work in Slice 4 and Slice 5 is import-path correction only.
- The explicit user override makes `src/terminal/` a temporary migration folder only. It must not survive Slice 5.

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
- VT aggregate owner after Slice 3: `howl-vt/src/terminal/terminal.zig`, final Slice 5 target `howl-vt/src/terminal.zig`.
- VT screen owners after Slice 3: `howl-vt/src/terminal/screen.zig` and `howl-vt/src/terminal/screen_set.zig`, final Slice 5 targets `howl-vt/src/screen.zig` and `howl-vt/src/screen_set.zig`.
- VT parser owner and parser bounds after Slice 3: `howl-vt/src/terminal/parser/main.zig`, final Slice 5 target `howl-vt/src/parser/main.zig`.
- VT stream mutation owner after Slice 3: `howl-vt/src/terminal/stream_terminal.zig`, final Slice 5 target `howl-vt/src/stream_terminal.zig`.
- VT mode owner before Slice 4: `howl-vt/src/control/mode.zig`, final Slice 4 target `howl-vt/src/mode.zig`.
- VT host consequence owner: `howl-vt/src/host/state.zig`, retained as a shallow true subdomain in the final no-wrapper tree.

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

- `test_unit.zig`
- `test_integration.zig`
- `test_abi.zig`
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
- Zig 0.16 module-boundary enforcement requires the test module root to sit at package root when out-of-`src` test files import `src` owners directly; package-root `test_unit.zig`, `test_integration.zig`, and `test_abi.zig` are proof entrypoints, while test bodies and support live under `test/`.

### VT

Final VT shape must not retain `src/terminal/` because the user explicitly overrode Ghostty's terminal wrapper pressure for this case. Keep curated terminal-core owners directly under `src`, keep shallow child folders only for true subdomains or per-owner definitions, and move non-product proof or simulation surfaces out of `src`.

Target `howl-vt/src/` shape:

- `howl_vt.zig`
- `libhowl_vt.zig`
- `terminal.zig`
- `screen.zig`
- `screen_set.zig`
- `stream_terminal.zig`
- `publication.zig`
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
- `ffi/`
  - `main.zig`
  - existing per-ABI translation owners now under `src/ffi/`
- `input/`
  - existing input encoding owners
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
  - `state.zig`
- `csi/`
  - existing CSI helper files

Target VT proof and non-product roots outside `src`:

- `test/abi.zig`
- `test_unit.zig`
- `test_abi.zig`
- `test_ffi.zig`
- `test/unit.zig`
- `benchmark_m7_baseline.zig`
- `test/unit/terminal_end_to_end_test.zig`
- `test/unit/terminal_snapshot_test.zig`
- `test/unit/terminal_modes_test.zig`
- `test/unit/screen_test.zig`
- `test/unit/terminal_osc_test.zig`
- `test/unit/terminal_surface_test.zig`
- `test/unit/route_test.zig`
- `test/unit/report_test.zig`
- `test/unit/screen/cursor_test.zig`
- `test/unit/screen/history_test.zig`
- `test/unit/screen/resize_test.zig`
- `test/unit/screen/tabs_test.zig`
- `test/unit/screen/write_test.zig`
- `test/unit/parser/csi_test.zig`
- `test/unit/parser/events_test.zig`
- `test/unit/parser/main_test.zig`
- `test/unit/parser/string_control_test.zig`
- `test/unit/csi_mapping_test.zig`
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

- Ghostty pressure says VT core should cluster under one deliberate terminal subdomain, but the explicit user override rejects that extra folder depth for Howl's final tree.
- TigerBeetle pressure says keep snake_case file names, so Howl should take Ghostty's folder boundary lesson without copying Ghostty's CamelCase file names.
- `screen/`, `parser/`, `selection/`, `kitty/`, `host/`, and `csi/` qualify as shallow child folders because they are true subdomains or per-owner definition groups.
- `xterm/`, `action/`, `control/`, `surface/`, and the temporary `terminal/` wrapper are not accepted final package concepts under the override; final proof folders must not preserve those deleted owner buckets either.
- `src/ffi.zig` should become `src/ffi/main.zig` so the `ffi` concept exists in one place only.
- Zig 0.16 module-boundary enforcement requires package-root build entrypoints for out-of-`src` tests, ABI module exposure, and benchmark roots when those proof files import both `src` owners and sibling proof helpers.

## Sprint Scratchpad

- The sprint must do real owner-boundary cleanup, not rename theater.
- PTY is small enough to finish in one slice because its structural debt is concentrated in proof-root placement.
- VT is the larger problem. The real cleanup is not just moving files; it is reducing `src/` to curated roots, deleting weak package-top buckets, and deleting the temporary `terminal/` wrapper after the explicit user override.
- The plan deliberately does not create any new runtime umbrella. PTY remains PTY. VT remains VT. Host runtime remains host-side.
- No slice may change shipped ABI names or widen product scope.
- No slice may leave both old and new folder concepts live at the same time after acceptance.
- After Slice 4, no `action/`, `control/`, or `xterm/` package-top bucket may remain. After Slice 5, no `src/terminal/` directory may remain.

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
  - `howl-pty/test_unit.zig`
  - `howl-pty/test_integration.zig`
  - `howl-pty/test_abi.zig`
  - `howl-pty/test/**`
- Required shape:
  - `src` keeps only PTY product owners and the true PTY platform subdomain.
  - All PTY proof roots move to `test/` outside `src`.
  - PTY build roots point to package-root `test_unit.zig`, `test_integration.zig`, and `test_abi.zig`, because Zig 0.16 rejects direct `../src` imports when the module root is `test/`.
  - Package-root proof entrypoints load the actual test bodies and ABI proof files under `test/`.
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
  - `howl-vt/src/ffi/**`
  - `howl-vt/src/action/route.zig`
  - `howl-vt/src/action/vocabulary.zig`
  - `howl-vt/src/host/apply.zig`
  - `howl-vt/src/host/state.zig`
  - `howl-vt/src/control/report.zig`
  - `howl-vt/src/control/osc_color.zig`
  - `howl-vt/src/xterm/osc.zig`
  - `howl-vt/src/xterm/dcs.zig`
  - `howl-vt/src/xterm/csi/params.zig`
  - `howl-vt/src/terminal/**`
  - `howl-vt/test/unit.zig`
  - `howl-vt/test/unit/**`
  - `howl-vt/test/support/**`
  - `howl-vt/benchmark/terminal_benchmark.zig`
  - `howl-vt/benchmark/pty_feed_record.zig`
- Required shape:
  - Create `src/terminal/main.zig` as the curated VT-core root.
  - Move the terminal aggregate owner, screen owners, parser owner, stream owner, selection owner, point owner, and publication owner into `src/terminal/`.
  - Preserve snake_case file names.
  - Keep `screen/` and `parser/` as shallow per-owner definition folders under `src/terminal/`.
  - Update `src/howl_vt.zig` to import VT core through `src/terminal/`, not package-top owner files.
  - Update every current direct import of moved terminal-core paths in the same slice, including `src/ffi/**`, `src/action/{route,vocabulary}.zig`, `src/host/{apply,state}.zig`, `src/control/{report,osc_color}.zig`, `src/xterm/{osc,dcs}.zig`, `src/xterm/csi/params.zig`, `test/unit/**`, `test/support/**`, and the two benchmark files named above.
  - These dependent files may receive import-path edits only. They must not absorb protocol owners, host consequence owners, ABI behavior, benchmark behavior, or test semantics in Slice 3.
  - Tests, proof helpers, and benchmark files must follow the moved owner paths directly and must not rely on package-top compatibility shims.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:abi:build`
  - `zig build benchmark:m7_baseline:build`
  - all in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no protocol-owner consolidation yet for `action`, `control`, `xterm`, `kitty`, or `host`
  - no behavior rewrites
  - no C ABI symbol, enum, struct, or exported-name changes
  - no benchmark or proof behavior changes beyond import-path updates
- Stop conditions:
  - stop if terminal aggregate ownership is still split between top-level and `src/terminal/`
  - stop if old top-level owner files remain as compatibility shims after acceptance
  - stop if the coder needs to invent a second curated VT-core root
  - stop if any product, ABI/FFI, benchmark, support, or unit proof file still imports old terminal-core source paths after acceptance
  - stop if any allowed `src/ffi/**`, `src/action/**`, `src/host/**`, `src/control/**`, or `src/xterm/**` edit changes behavior instead of only correcting imports required by the terminal-core move
  - stop if `zig build test:abi:build` fails from stale ABI/FFI imports after terminal-core paths move
  - stop if current-source proof finds a direct moved-path import in a file not named here; return to research instead of guessing or adding a shim

### Slice 4

- Name: VT protocol bucket removal toward final no-wrapper layout
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Explicit override receipt fields:
  - exact user decision: "ok slice 5 will be deleting terminal anmd moving all its content into src/ terminal makes the fodlers all 1 deeper for no reason. you can delegate until all that is done"
  - exact reference overridden: Ghostty `src/terminal/` final VT-core subdomain pressure
  - reason: user rejects the extra folder depth as unjustified in Howl
  - orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`
  - user approval receipt: quoted user message recorded in this active planning artifact
- Allowed files:
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/action/**`
  - `howl-vt/src/control/**`
  - `howl-vt/src/xterm/**`
  - `howl-vt/src/route.zig`
  - `howl-vt/src/vocabulary.zig`
  - `howl-vt/src/mode.zig`
  - `howl-vt/src/report.zig`
  - `howl-vt/src/locator.zig`
  - `howl-vt/src/osc_color.zig`
  - `howl-vt/src/c0.zig`
  - `howl-vt/src/esc.zig`
  - `howl-vt/src/csi.zig`
  - `howl-vt/src/osc.zig`
  - `howl-vt/src/dcs.zig`
  - `howl-vt/src/csi/**`
  - `howl-vt/src/host/apply.zig`
  - `howl-vt/src/host/state.zig`
  - `howl-vt/src/kitty/apply.zig`
  - `howl-vt/src/kitty/color.zig`
  - `howl-vt/src/kitty/protocol.zig`
  - `howl-vt/src/input/encode.zig`
  - `howl-vt/src/terminal/terminal.zig`
  - `howl-vt/src/terminal/stream_terminal.zig`
  - `howl-vt/src/terminal/screen.zig`
  - `howl-vt/src/terminal/screen/apply.zig`
  - `howl-vt/src/terminal/screen/cursor.zig`
  - `howl-vt/src/terminal/screen/erase.zig`
  - `howl-vt/src/terminal/screen/rect.zig`
  - `howl-vt/test/unit.zig`
  - `howl-vt/test/unit/action/route_test.zig`
  - `howl-vt/test/unit/route_test.zig`
  - `howl-vt/test/unit/control/report_test.zig`
  - `howl-vt/test/unit/report_test.zig`
  - `howl-vt/test/unit/xterm/csi_mapping_test.zig`
  - `howl-vt/test/unit/csi_mapping_test.zig`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/screen_test.zig`
  - `howl-vt/test/unit/screen/cursor_test.zig`
  - `howl-vt/test/unit/screen/history_test.zig`
  - `howl-vt/test/unit/screen/resize_test.zig`
  - `howl-vt/test/unit/screen/tabs_test.zig`
  - `howl-vt/test/unit/screen/write_test.zig`
- Required shape:
  - Do not move protocol or consequence folders under `src/terminal/` temporarily; the override makes that known throwaway work.
  - Remove package-top `action/`, `control/`, and `xterm/` buckets.
  - Move `src/action/route.zig` to `src/route.zig` and `src/action/vocabulary.zig` to `src/vocabulary.zig`.
  - Move `src/control/mode.zig`, `src/control/report.zig`, `src/control/locator.zig`, and `src/control/osc_color.zig` to direct `src/{mode,report,locator,osc_color}.zig` owners.
  - Move `src/xterm/c0.zig`, `src/xterm/esc.zig`, `src/xterm/csi.zig`, `src/xterm/osc.zig`, and `src/xterm/dcs.zig` to direct `src/{c0,esc,csi,osc,dcs}.zig` owners.
  - Move `src/xterm/csi/**` to `src/csi/**`; retain `src/csi/` only as the CSI helper subdomain.
  - Keep `src/host/` and `src/kitty/` as final shallow true subdomains; do not move them under `src/terminal/`.
  - Keep `src/terminal/**` terminal-core files in place for Slice 4 except for import-path updates required by the moved protocol owners.
  - Update product and proof imports in the allowed files directly to the new paths.
  - Rename `test/unit/action/route_test.zig` to `test/unit/route_test.zig`, `test/unit/control/report_test.zig` to `test/unit/report_test.zig`, and `test/unit/xterm/csi_mapping_test.zig` to `test/unit/csi_mapping_test.zig`; final proof folders must not preserve deleted `action/`, `control/`, or `xterm/` buckets.
  - No package-top compatibility mirrors, re-export shims, or duplicate old/new owner paths may survive acceptance.
- Exact tests:
  - `zig build test:unit`
  - `zig build test:abi`
  - `zig build benchmark:m7_baseline:build`
  - all in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no deletion of `src/terminal/` in Slice 4
  - no movement of terminal-core files out of `src/terminal/` in Slice 4
  - no host runtime architecture change
  - no new public Zig API
  - no convenience wrapper layer
  - no C ABI symbol, enum, struct, or exported-name changes
  - no proof or benchmark behavior changes beyond import-path updates
- Stop conditions:
  - stop if any `howl-vt/src/action/`, `howl-vt/src/control/`, or `howl-vt/src/xterm/` path remains after acceptance
  - stop if any `howl-vt/test/unit/action/`, `howl-vt/test/unit/control/`, or `howl-vt/test/unit/xterm/` proof bucket remains after acceptance
  - stop if `src/host/` or `src/kitty/` is moved under `src/terminal/`
  - stop if `src/terminal/**` is deleted or moved in Slice 4 instead of saved for Slice 5
  - stop if imported paths depend on compatibility mirrors
  - stop if any unit proof still imports old `action/`, `control/`, or `xterm/` source paths after acceptance
  - stop if current-source proof finds a direct old protocol-bucket import in a file not named here; return to research instead of guessing or adding a shim

### Slice 5

- Name: Delete temporary VT terminal wrapper and finalize shallow `src` layout
- Sessions:
  - Orchestrator: `orch-2026-06-13-pty-vt-folder-structure-01`
  - Researcher: `research-2026-06-13-pty-vt-folder-structure-01`
  - Reviewer: `review-2026-06-13-pty-vt-folder-structure-01`
  - Coder: assigned during execution
- Commit-hash receipt demand: required on acceptance
- Explicit override receipt fields:
  - exact user decision: "ok slice 5 will be deleting terminal anmd moving all its content into src/ terminal makes the fodlers all 1 deeper for no reason. you can delegate until all that is done"
  - exact reference overridden: Ghostty `src/terminal/` final VT-core subdomain pressure
  - reason: user rejects the extra folder depth as unjustified in Howl
  - orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`
  - user approval receipt: quoted user message recorded in this active planning artifact
- Allowed files:
  - `howl-vt/src/howl_vt.zig`
  - `howl-vt/src/terminal/**`
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/screen.zig`
  - `howl-vt/src/screen_set.zig`
  - `howl-vt/src/stream_terminal.zig`
  - `howl-vt/src/publication.zig`
  - `howl-vt/src/parser/**`
  - `howl-vt/src/screen/**`
  - `howl-vt/src/selection/**`
  - `howl-vt/src/ffi/handle.zig`
  - `howl-vt/src/ffi/lifecycle.zig`
  - `howl-vt/src/ffi/runtime.zig`
  - `howl-vt/src/ffi/surface.zig`
  - `howl-vt/src/ffi/selection.zig`
  - `howl-vt/src/route.zig`
  - `howl-vt/src/vocabulary.zig`
  - `howl-vt/src/report.zig`
  - `howl-vt/src/osc_color.zig`
  - `howl-vt/src/osc.zig`
  - `howl-vt/src/dcs.zig`
  - `howl-vt/src/csi/params.zig`
  - `howl-vt/src/host/apply.zig`
  - `howl-vt/src/host/state.zig`
  - `howl-vt/test/unit.zig`
  - `howl-vt/test/unit/terminal_end_to_end_test.zig`
  - `howl-vt/test/unit/terminal_snapshot_test.zig`
  - `howl-vt/test/unit/terminal_osc_test.zig`
  - `howl-vt/test/unit/terminal_surface_test.zig`
  - `howl-vt/test/unit/terminal_modes_test.zig`
  - `howl-vt/test/unit/terminal_test.zig`
  - `howl-vt/test/unit/screen_test.zig`
  - `howl-vt/test/unit/route_test.zig`
  - `howl-vt/test/unit/report_test.zig`
  - `howl-vt/test/unit/csi_mapping_test.zig`
  - `howl-vt/test/unit/parser/csi_test.zig`
  - `howl-vt/test/unit/parser/events_test.zig`
  - `howl-vt/test/unit/parser/main_test.zig`
  - `howl-vt/test/unit/parser/string_control_test.zig`
  - `howl-vt/test/unit/screen/cursor_test.zig`
  - `howl-vt/test/unit/screen/history_test.zig`
  - `howl-vt/test/unit/screen/resize_test.zig`
  - `howl-vt/test/unit/screen/tabs_test.zig`
  - `howl-vt/test/unit/screen/write_test.zig`
  - `howl-vt/test/support/screen_capture.zig`
  - `howl-vt/test/support/stream_harness.zig`
  - `howl-vt/benchmark/terminal_benchmark.zig`
  - `howl-vt/benchmark/pty_feed_record.zig`
- Required shape:
  - Delete `howl-vt/src/terminal/` completely.
  - Delete `howl-vt/src/terminal/main.zig` instead of recreating an equivalent wrapper elsewhere.
  - Move `src/terminal/terminal.zig` to `src/terminal.zig`.
  - Move `src/terminal/screen.zig` to `src/screen.zig` and `src/terminal/screen_set.zig` to `src/screen_set.zig`.
  - Move `src/terminal/stream_terminal.zig` to `src/stream_terminal.zig` and `src/terminal/publication.zig` to `src/publication.zig`.
  - Move `src/terminal/parser/**` to `src/parser/**`, `src/terminal/screen/**` to `src/screen/**`, and `src/terminal/selection/**` to `src/selection/**`.
  - Update `src/howl_vt.zig` to import the final direct owners and to stop importing `terminal/main.zig`.
  - Update all allowed product, proof, support, and benchmark imports directly to final paths.
  - Final `src` may contain direct terminal-core owner files plus shallow true subdomains `ffi/`, `input/`, `host/`, `kitty/`, `screen/`, `parser/`, `selection/`, and `csi/` only.
  - No `src/terminal/` wrapper, compatibility shim, or duplicate old/new terminal path may survive acceptance.
- Exact tests:
  - `zig build test` in `/home/home/personal/projects/howl/howl-pty`
  - `zig build test` in `/home/home/personal/projects/howl/howl-vt`
  - `zig build simulate:build` in `/home/home/personal/projects/howl/howl-vt`
  - `zig build benchmark:m7_baseline:build` in `/home/home/personal/projects/howl/howl-vt`
- Non-goals:
  - no new cleanup outside PTY or VT
  - no execution-phase redesign
  - no protocol bucket redesign beyond imports required after Slice 4
  - no host or kitty movement
  - no public ABI or behavior changes
  - no proof, benchmark, or simulation behavior changes beyond import-path updates
- Stop conditions:
  - stop if `howl-vt/src/terminal/` exists after acceptance
  - stop if any source, test, support, benchmark, simulation, or build file imports `src/terminal/` or `terminal/main.zig` after acceptance
  - stop if any stale path survives only because imports still reference it
  - stop if final build roots still mention old locations
  - stop if reviewer cannot diff the final tree without reconstructing hidden moves
  - stop if current-source proof finds a direct temporary terminal-wrapper import in a file not named here; return to research instead of guessing or adding a shim

## Slice 3 Split Or Reorder Decision

- Slice 3 remains `VT terminal core root establishment`.
- Required repair is expanded import-update authorization, not a new implementation slice, because current source proves the blocked files only need direct path updates to keep the same owners buildable after the terminal-core move.
- Do not split Slice 3 into a move slice and an import-fix slice: the move slice would necessarily leave deleted package-top terminal-core paths referenced by `src/ffi/**`, and `zig build test:abi:build` would be invalid for that intermediate state.
- Do not reorder protocol/consequence absorption before terminal-core establishment: `action`, `control`, `host`, `xterm`, and `kitty` owner absorption remains Slice 4, and current-source proof does not require semantic protocol-owner movement to complete Slice 3.
- Replacement slices are not required. If reviewer rejects the expanded import-update scope, the only safe replacement would be Slice 3A `VT terminal-core move plus all current direct import-path updates` followed by Slice 3B `no-op verification receipt`, which is worse accountability than the repaired single Slice 3 because it creates an artificial boundary with no independent product state.

## Slice 4 And Slice 5 Override Repair Decision

- Slice 4 must not absorb protocol or consequence folders under `src/terminal/` temporarily.
- Current-source import proof after `howl-vt` `20fb714` shows Slice 4 can move directly toward the final no-wrapper layout by deleting weak `action/`, `control/`, and `xterm/` buckets and updating their direct import consequences.
- `host/` and `kitty/` are not moved in Slice 4 because, after the user override, they are already shallow final subdomains under `src/`.
- Slice 5 is the explicit deletion of the temporary `src/terminal/` wrapper. It moves terminal-core owner files and true child subdomains back under `src/` and updates all direct imports.
- This two-step sequence avoids a known throwaway `src/terminal/{action,control,host,kitty,xterm}` intermediate, preserves buildable checkpoints, and gives the reviewer one exact bucket-removal diff followed by one exact wrapper-deletion diff.

## Explicit User Override For Final VT Folder Shape

- Exact user decision: "ok slice 5 will be deleting terminal anmd moving all its content into src/ terminal makes the fodlers all 1 deeper for no reason. you can delegate until all that is done".
- Exact reference being overridden: Ghostty's VT folder pressure where `src/lib_vt.zig` delegates into `src/terminal/main.zig`, and terminal-core owners sit under the `terminal/` subdomain.
- Reason for override: the user explicitly decided that Howl's `src/terminal/` wrapper adds one folder depth for no reason and should not survive the final tree.
- Accountable orchestrator session id: `orch-2026-06-13-pty-vt-folder-structure-01`.
- User approval receipt: the quoted user message above in the active PTY+VT planning artifact.
- Consequence: remaining Slice 4 and Slice 5 must be replanned before coding. Slice 5 must remove `howl-vt/src/terminal/` and move all retained terminal-core owners back under `howl-vt/src/`, while still preserving shallow true subdomains and no compatibility shims.

## Required Assertions

- Preserve PTY exported symbols exactly as listed in `howl-pty/src/libhowl_pty.zig:3-18`.
- Preserve VT exported symbols exactly as listed in `howl-vt/src/libhowl_vt.zig:3-31`.
- Keep PTY transport burst constants unchanged unless a separate source-backed sprint reopens the policy in `howl-pty/src/session.zig:85-105`.
- Keep VT parser bounds unchanged unless a separate source-backed sprint reopens them in `howl-vt/src/parser/main.zig:23-54`.
- Assert there is only one active root for each concept after the move: one `ffi` root, one terminal-core root, one unit test root per package, one benchmark root, one simulation root, one ABI test root per package.
- Assert build roots resolve only through final paths.
- Assert any deleted folder is actually empty and unreferenced before acceptance.
- Assert `src` contains no `*_test.zig` files after Slice 2 acceptance.
- Assert `howl-vt/src/action/`, `howl-vt/src/control/`, and `howl-vt/src/xterm/` do not exist after Slice 4 acceptance.
- Assert `howl-vt/src/terminal/` does not exist after Slice 5 acceptance.

## Required Tests

- PTY:
  - `zig build test:unit`
  - `zig build test:integration`
  - `zig build test:abi`
  - `zig build test`
- VT:
  - `zig build test:unit`
  - `zig build test:abi:build`
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

- Ready for reviewer gate after Slice 4 and Slice 5 repair.
- Current-source proof after nested `howl-vt` `20fb714` shows remaining top-level protocol bucket debt is `action/`, `control/`, and `xterm/`; these should move directly to final `src` paths in Slice 4 rather than under temporary `src/terminal/`.
- Current-source proof shows `src/terminal/main.zig` is now only a temporary wrapper; under the explicit user override, Slice 5 must delete `src/terminal/` and move all retained contents back under `src/`.
- No compatibility shims, C ABI changes, benchmark behavior changes, proof semantic changes, or final umbrella `terminal/` wrapper are authorized.
- This artifact remains planning/correction only and does not authorize coding.

## Coding Authorization

- None. This artifact plans the sprint only.
