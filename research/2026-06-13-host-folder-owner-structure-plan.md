# Host Folder Owner Structure Plan

Date: 2026-06-13.

Status: reviewer-accepted planning; planning commit-hash receipt pending.

Role owner: researcher.

Orchestrator session id: `orch-2026-06-13-host-folder-structure-01`.

Researcher session id: `research-2026-06-13-host-folder-structure-01`.

Reviewer session id: `review-2026-06-13-host-folder-structure-01`.

Planning commit-hash receipt: pending.

Question:

- What full source-backed sprint plan restructures `howl-linux-host/src` so only curated host owner units live at the top level, child folders remain shallow and owner-true, dead/weak folder boundaries are removed, and file/folder names move toward Alacritty-grade intentionality without violating host/render/vt/pty boundaries?

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

- `howl-linux-host/src`
- `utils/dev_references/terminals/alacritty/alacritty/src`
- relevant Ghostty host/runtime folders only where Alacritty has no analogue
- current host public roots, C-header placement, test roots, and broad child folders

## Planning Constraints

- No implementation in research.
- No cosmetic rename-only plan.
- No Howl-only folder inventions while Alacritty/other references still provide pressure.
- No umbrella buckets, misc folders, or generic staging roots.
- No reverse dependency or boundary violations across host/render/vt/pty.

## Reviewer Gate

- Reviewer must reject vague folder pressure, missing current-source proof, under-scoped rename theater, stale active artifacts, or any plan that leaves coder invention about folder boundaries, file moves, imports, tests, or stop conditions.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/loop/researcher.md` reread as the active role contract
7. `/home/home/personal/projects/howl/sprints/current.txt`
8. `/home/home/personal/projects/howl/loops/host-folder-owner-structure-live-loop.txt`
9. `/home/home/personal/projects/howl/research/2026-06-13-host-folder-owner-structure-plan.md`
10. `/home/home/personal/projects/howl/reference-index.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. `/home/home/personal/projects/howl/howl-linux-host/build.zig`
14. `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
15. `/home/home/personal/projects/howl/howl-linux-host/src/event_loop.zig`
16. `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
17. `/home/home/personal/projects/howl/howl-linux-host/src/app/present.zig`
18. `/home/home/personal/projects/howl/howl-linux-host/src/display/display.zig`
19. `/home/home/personal/projects/howl/howl-linux-host/src/input/input.zig`
20. `/home/home/personal/projects/howl/howl-linux-host/src/config/config.zig`
21. `/home/home/personal/projects/howl/howl-linux-host/src/tab_bar/tab_bar.zig`
22. `/home/home/personal/projects/howl/howl-linux-host/src/tab_bar/slots.zig`
23. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
24. `/home/home/personal/projects/howl/howl-linux-host/src/window_chrome/window.zig`
25. `/home/home/personal/projects/howl/howl-linux-host/src/polling/window_wake.zig`
26. `/home/home/personal/projects/howl/howl-linux-host/src/host_test_root.zig`
27. `/home/home/personal/projects/howl/howl-linux-host/src/integration_test_root.zig`
28. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs`
29. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
30. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
31. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
32. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`
33. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/config/mod.rs`
34. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/polling/mod.rs`
35. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/App.zig`
36. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/apprt.zig`
37. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/Surface.zig`
38. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Termio.zig`

## Exact Files And Line References

### Current Host

- Broad top-level host roots are proved by `howl-linux-host/src/main.zig:2-11`, which imports `cli/`, `config/`, `display/`, `event_loop.zig`, `input/`, `app/`, `tab_bar/`, `terminal/`, and `window_chrome/` as peer roots.
- The actual host control spine lives in `howl-linux-host/src/app/processor.zig:20-33` and `howl-linux-host/src/app/processor.zig:125-200`, while the low-level SDL pump and wake semantics live separately in `howl-linux-host/src/event_loop.zig:17-80` and `howl-linux-host/src/event_loop.zig:82-166`.
- Window lifecycle and host UI side effects live in `howl-linux-host/src/window_chrome/window.zig:16-87` and `howl-linux-host/src/window_chrome/window.zig:97-182`, while display/present lifecycle lives in `howl-linux-host/src/display/display.zig:57-109` and `howl-linux-host/src/display/display.zig:122-225`.
- The tab-bar folder currently mixes display labeling with runtime tab-slot ownership: `howl-linux-host/src/tab_bar/tab_bar.zig:3-27` is snapshot/UI text work, while `howl-linux-host/src/tab_bar/slots.zig:10-98` is active-slot state and bounds management over terminal contexts.
- The per-tab embedded terminal owner is `howl-linux-host/src/terminal/context.zig:52-125` and `howl-linux-host/src/terminal/context.zig:137-219`; the file owns PTY, VT, render-surface, input, title, geometry, scrollbar, links, and selection, so the file is a surface owner, not a generic context helper.
- The one-file `polling/` folder is currently weak: `howl-linux-host/src/polling/window_wake.zig:7-65` is the only file there.
- C-header and C-source placement is inconsistent in the current source tree: `howl-linux-host/build.zig:111-118` reads `src/howl_pty_c.h`, `src/howl_vt_c.h`, `src/howl_render_c.h`, `src/sdl_c.h`, nested `src/display/renderer/gl_c.h`, and `src/window_chrome/stb_image.c`.
- The current import edges that the slice contracts must cover are explicit: `howl-linux-host/src/terminal/context.zig:2-5` imports `../event_loop.zig`, `../window_chrome/window.zig`, and `../display/renderer/render_surface.zig`; `howl-linux-host/src/terminal/input.zig:2` imports `../event_loop.zig`; `howl-linux-host/src/terminal/scrollbar.zig:2` imports `../event_loop.zig`; `howl-linux-host/src/terminal/context_test.zig:7` imports `../display/renderer/render_surface.zig`; `howl-linux-host/src/terminal/links.zig:6` imports `../window_chrome/window.zig`; `howl-linux-host/src/host_test_root.zig:2,5,7,12-13` imports `event_loop.zig`, `terminal/context.zig`, `window_chrome/window.zig`, `display/renderer/render_surface_test.zig`, and `terminal/context_test.zig`.
- Test-root placement is also inconsistent: `howl-linux-host/build.zig:312-365` uses top-level `src/host_test_root.zig` and `src/integration_test_root.zig`, while the dedicated `src/test/` directory exists but is empty.
- The current test roots are real curated roots, just misplaced: `howl-linux-host/src/host_test_root.zig:1-14` and `howl-linux-host/src/integration_test_root.zig:1-8`.

### References

- Alacritty keeps its host top level curated around runtime owners, not feature buckets: `alacritty/src/main.rs:30-49` declares `cli`, `config`, `display`, `event`, `input`, `polling`, `renderer`, `scheduler`, and `window_context` as intentional peers.
- Alacritty startup flows through one main runtime spine: config load, env application, optional polling setup, `Processor::new`, then `Processor::run` in `alacritty/src/main.rs:132-215`.
- Alacritty's host event processor is the primary runtime owner: `alacritty/src/event.rs:83-145` defines `Processor`, and `alacritty/src/event.rs:147-205` keeps window creation and loop ownership there.
- Alacritty's per-window owner is explicit and named after the domain: `alacritty/src/window_context.rs:47-70` and `alacritty/src/window_context.rs:168-220` keep terminal, display, notifier, window-local state, and PTY wiring together.
- Alacritty's display package is a true display owner with shallow child modules: `alacritty/src/display/mod.rs:60-68` exposes `color`, `content`, `cursor`, `hint`, and `window`, while `alacritty/src/display/mod.rs:82-141` keeps display/window/render error seams explicit.
- Alacritty's input package is a single owner root with a shallow child for keyboard specifics: `alacritty/src/input/mod.rs:53-80`.
- Alacritty's config package is a curated root with real subdomains, not one-file buckets: `alacritty/src/config/mod.rs:13-29` and `alacritty/src/config/mod.rs:120-166`.
- Alacritty's polling package is a real subdomain only because it owns more than one concern: `alacritty/src/polling/mod.rs:19-29` and `alacritty/src/polling/mod.rs:36-92`.
- Ghostty provides the better host analogue where Alacritty lacks a tabbed embedded-surface shape: `ghostty/src/Surface.zig:1-12` names the embedded terminal owner `Surface`, and `ghostty/src/Surface.zig:67-73` plus `ghostty/src/Surface.zig:126-130` show that one surface owns runtime, PTY, renderer, and IO state together.
- Ghostty's app root owns the collection of surfaces, not the display widget: `ghostty/src/App.zig:21-27` and `ghostty/src/App.zig:164-217`.
- Ghostty's runtime package is explicit about app/runtime ownership being distinct from surface ownership: `ghostty/src/apprt.zig:1-10` and `ghostty/src/apprt.zig:51-52`.
- TigerBeetle requires simple explicit control flow, minimal excellent abstractions, and limits on everything in `tigerbeetle/docs/TIGER_STYLE.md:90-100`.
- TigerBeetle requires assertion-heavy owner code and pair assertions in `tigerbeetle/docs/TIGER_STYLE.md:104-149`.
- TigerBeetle pressures names and source order directly, including file naming and putting important things near the top, in `tigerbeetle/docs/TIGER_STYLE.md:273-281` and `tigerbeetle/docs/TIGER_STYLE.md:315-317`.
- TigerBeetle architecture pressures intentional design up front rather than rename drift or incremental accident in `tigerbeetle/docs/ARCHITECTURE.md:94-101`.

## Current-Code Facts

- `app/` is a weak top-level bucket. `processor.zig` is the runtime owner and `present.zig` is display-present logic, so the folder name hides two different owners instead of clarifying one.
- `cli/` is a one-file folder today, and Alacritty uses a single top-level `cli` owner rather than a child folder for one file.
- `tab_bar/` is weak and mixed. The label snapshot owner belongs with display presentation, but the slot owner belongs with the terminal-surface collection or runtime owner.
- `window_chrome/` is a weak and misleading folder name. The current `window.zig` owns far more than chrome and is much closer to Alacritty's `display/window` seam.
- `polling/` is not currently justified as a folder, but it becomes justified if the low-level event pump is moved under it beside `window_wake.zig`.
- `terminal/context.zig` is the clearest current naming offender inside the terminal host tree. The file is an owner and should be named for the owned thing, not for a bucket noun.
- The existing `display/renderer/` child is weak. The files there are display-private helpers plus a translated GL header, not an independently exposed host renderer architecture.
- The test roots already prove the right class separation, but their placement at `src/` top level violates the user's request to keep only curated owner units under `src`.

## Reference Facts

- The strongest Alacritty pressure is to keep `src` top level limited to named owners for runtime, config, display, input, polling, and window/runtime context.
- The strongest Ghostty pressure for the tabbed embedded host is to call the per-terminal owner a surface-like noun and to keep the surface list with app/runtime ownership rather than with tab-bar drawing.
- TigerBeetle blocks any plan that merely renames folders without sharpening owner truth, test roots, and boundary clarity.

## Compact Anchor Map

| Anchor | Governing pressure for this sprint |
| --- | --- |
| `howl-linux-host/src/main.zig:2-11` | Current top-level root sprawl that the sprint must remove. |
| `howl-linux-host/src/app/processor.zig:20-33` | Real host control spine owner that should move toward an Alacritty-style `event` root. |
| `howl-linux-host/src/terminal/context.zig:52-125` | Current vague terminal-surface owner that needs a surface-true name. |
| `howl-linux-host/build.zig:111-118` | Current inconsistent C-header/C-source placement that needs one explicit translation seam. |
| `howl-linux-host/build.zig:312-365` | Current curated but misplaced test roots that need a real `src/test/` home. |
| `alacritty/src/main.rs:30-49` | Top-level host root model for runtime/config/display/input/polling layout. |
| `alacritty/src/event.rs:83-145` | Event processor as the main runtime owner. |
| `alacritty/src/display/mod.rs:60-68` | Shallow display child folders only for true display subdomains. |
| `alacritty/src/polling/mod.rs:19-29` | Polling folder justified only when it holds multiple real polling owners. |
| `ghostty/src/Surface.zig:1-12` | Best available naming/model pressure for embedded tabbed terminal owners. |
| `tigerbeetle/docs/TIGER_STYLE.md:90-149` | Owner truth, bounds, assertions, and anti-bucket law. |

## Owner Roles And Proposed Shape

- `main.zig` remains startup only.
- `event.zig` becomes the host runtime control spine, replacing the vague `app/processor.zig` root.
- `cli.zig` becomes the single CLI owner, replacing the one-file `cli/` folder.
- `display/` becomes the only display/window/present/tab-visual package. It owns the display state, frame pacing, layout, window lifecycle, icon loading, render-surface helpers, rect helpers, and tab-bar label snapshot logic.
- `input/` remains a real shallow subdomain and stays as a folder.
- `config/` remains a real shallow subdomain and stays as a folder.
- `polling/` becomes a true polling subdomain by owning both the low-level SDL event pump and the SDL wake helpers.
- `terminal/` remains a real shallow subdomain. Inside it, the current `context.zig` must be renamed to `surface.zig`, and the current tab-slot owner must move there as `tab_slots.zig` because it manages terminal surfaces, not tab-bar drawing.
- `terminal/pty/`, `terminal/render/`, and `terminal/vt/` remain justified child folders because they are true terminal subdomains with multiple owners.
- `c/` becomes the single translated-C seam for host-local headers.
- `test/` becomes the single curated home for host test roots.

Required target tree:

```text
howl-linux-host/src/
  main.zig
  cli.zig
  event.zig
  c/
    gl_c.h
    howl_pty_c.h
    howl_render_c.h
    howl_vt_c.h
    sdl_c.h
  config/
    config.zig
    env.zig
    tab_bar.zig
    terminal.zig
    window.zig
  display/
    display.zig
    frame_timer.zig
    icon.zig
    layout.zig
    present.zig
    rects.zig
    render_surface.zig
    render_surface_test.zig
    stb_image.c
    tab_bar.zig
    window.zig
  input/
    input.zig
    keys.zig
    mouse.zig
  polling/
    event_loop.zig
    window_wake.zig
  terminal/
    cursor_blink.zig
    input.zig
    links.zig
    scrollbar.zig
    selection.zig
    surface.zig
    surface_test.zig
    tab_slots.zig
    term.zig
    pty/
      pump.zig
      session.zig
      wait_thread.zig
    render/
      font_size.zig
      fonts_linux.zig
      retained.zig
      surface_layout.zig
    vt/
      input.zig
      retained.zig
      surface.zig
  test/
    host_test_root.zig
    integration_test_root.zig
```

Roots that must be removed by the end of the sprint:

- `src/app/`
- `src/cli/`
- `src/tab_bar/`
- `src/window_chrome/`
- `src/display/renderer/`
- top-level `src/howl_pty_c.h`
- top-level `src/howl_vt_c.h`
- top-level `src/howl_render_c.h`
- top-level `src/sdl_c.h`
- top-level `src/host_test_root.zig`
- top-level `src/integration_test_root.zig`

## Sprint Scratchpad

- The sprint is not allowed to stop at path renames. It has to leave `src` with only owner-true roots.
- The main Alacritty pressure is structural, not semantic parity. The host remains tabbed and embeddable, so Ghostty pressure is needed only for the per-terminal embedded-surface owner and the surface list.
- The cleanest path is to collapse weak roots first, then rename the vague terminal owner, then finish by relocating C headers and test roots once final import paths are stable.
- `display/renderer/` is too small and too private to survive as a child folder under the user's rule. The files there belong under `display/`.
- `tab_bar/slots.zig` must not stay with the tab-bar visual owner; it is a terminal-surface collection owner.

## Explicit Ordered Slice Plan

### Slice 1: Control-Spine Root Cleanup

- Accountable planning session ids: orchestrator `orch-2026-06-13-host-folder-structure-01`, researcher `research-2026-06-13-host-folder-structure-01`, reviewer `review-2026-06-13-host-folder-structure-01`.
- Allowed files: `howl-linux-host/src/main.zig`, `howl-linux-host/src/app/processor.zig`, `howl-linux-host/src/cli/args.zig`, `howl-linux-host/src/event_loop.zig`, `howl-linux-host/src/polling/window_wake.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/input.zig`, `howl-linux-host/src/terminal/scrollbar.zig`, `howl-linux-host/src/host_test_root.zig`, `howl-linux-host/src/integration_test_root.zig`, `howl-linux-host/build.zig`.
- Required shape: move `src/app/processor.zig` to `src/event.zig`; move `src/cli/args.zig` to `src/cli.zig`; move `src/event_loop.zig` to `src/polling/event_loop.zig`; rewire every direct import site that currently names `event_loop.zig`, specifically `src/main.zig`, `src/terminal/context.zig`, `src/terminal/input.zig`, `src/terminal/scrollbar.zig`, and `src/host_test_root.zig`; update build references so `app/` and `cli/` become removable and `polling/` becomes a real subdomain with more than one owner.
- Required tests: `zig build test:unit`, `zig build test:integration`.
- Required assertions: preserve the wake-event assertions and event-turn bound from current `event_loop.zig:31-37`, `event_loop.zig:56-64`, and `event_loop.zig:101-105`; preserve the host control-spine tab bounds and quit-path assertions from `app/processor.zig:134-154`, `app/processor.zig:216-249`, and all existing inline tests that move with the files.
- Non-goals: no tab-model redesign, no new runtime abstractions, no behavior changes to event processing, no new public host API.
- Stop conditions: stop if the move cannot be completed without inventing a second event owner, or if `polling/` still ends the slice as a one-file folder.
- Commit-hash receipt demand: mandatory on reviewer acceptance; orchestrator must record the exact commit hash before the slice can be marked accepted.

### Slice 2: Display, Window, And Tab-Visual Owner Cleanup

- Accountable planning session ids: orchestrator `orch-2026-06-13-host-folder-structure-01`, researcher `research-2026-06-13-host-folder-structure-01`, reviewer `review-2026-06-13-host-folder-structure-01`.
- Allowed files: `howl-linux-host/src/display/display.zig`, `howl-linux-host/src/display/frame_timer.zig`, `howl-linux-host/src/display/layout.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-linux-host/src/display/renderer/render_surface_test.zig`, `howl-linux-host/src/display/renderer/rects.zig`, `howl-linux-host/src/window_chrome/window.zig`, `howl-linux-host/src/window_chrome/icon.zig`, `howl-linux-host/src/window_chrome/stb_image.c`, `howl-linux-host/src/tab_bar/tab_bar.zig`, `howl-linux-host/src/tab_bar/slots.zig`, `howl-linux-host/src/app/present.zig`, `howl-linux-host/src/main.zig`, `howl-linux-host/src/event.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/context_test.zig`, `howl-linux-host/src/terminal/links.zig`, `howl-linux-host/src/host_test_root.zig`, `howl-linux-host/src/integration_test_root.zig`, `howl-linux-host/build.zig`.
- Required shape: move `app/present.zig` to `display/present.zig`; move `window_chrome/window.zig` to `display/window.zig`; move `window_chrome/icon.zig` and `window_chrome/stb_image.c` under `display/`; move `display/renderer/render_surface.zig`, `display/renderer/render_surface_test.zig`, and `display/renderer/rects.zig` directly under `display/`; move `tab_bar/tab_bar.zig` to `display/tab_bar.zig`; move `tab_bar/slots.zig` out of the display package and into the terminal package as `terminal/tab_slots.zig`; rewire every direct import site that currently names `window_chrome/window.zig` or `display/renderer/render_surface.zig`, specifically `src/terminal/context.zig`, `src/terminal/context_test.zig`, `src/terminal/links.zig`, and `src/host_test_root.zig`; remove the weak `window_chrome/`, `tab_bar/`, and `display/renderer/` folders.
- Required tests: `zig build test:unit`, `zig build test:integration`.
- Required assertions: preserve display present token assertions from `display/display.zig:122-164`; preserve present-reason and pending-terminal assertions from `app/present.zig:30-77`; preserve tab-slot bounds assertions from `tab_bar/slots.zig:47-98`; preserve tab-bar snapshot tests from `tab_bar/tab_bar.zig:37-58`.
- Non-goals: no renderer-architecture redesign, no new top-level `renderer/` root, no tab feature changes, no host/render ABI changes, and no `gl_c.h` move in this slice.
- Stop conditions: stop if the move would create another bucket folder under `display/`, or if `tab_slots` cannot be placed without clear terminal-surface ownership.
- Commit-hash receipt demand: mandatory on reviewer acceptance; orchestrator must record the exact commit hash before the slice can be marked accepted.

### Slice 3: Terminal Surface Naming Cleanup

- Accountable planning session ids: orchestrator `orch-2026-06-13-host-folder-structure-01`, researcher `research-2026-06-13-host-folder-structure-01`, reviewer `review-2026-06-13-host-folder-structure-01`.
- Allowed files: `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/context_test.zig`, `howl-linux-host/src/terminal/cursor_blink.zig`, `howl-linux-host/src/terminal/input.zig`, `howl-linux-host/src/terminal/links.zig`, `howl-linux-host/src/terminal/scrollbar.zig`, `howl-linux-host/src/terminal/selection.zig`, `howl-linux-host/src/terminal/tab_slots.zig`, `howl-linux-host/src/terminal/term.zig`, `howl-linux-host/src/terminal/pty/pump.zig`, `howl-linux-host/src/terminal/pty/session.zig`, `howl-linux-host/src/terminal/pty/wait_thread.zig`, `howl-linux-host/src/terminal/render/font_size.zig`, `howl-linux-host/src/terminal/render/fonts_linux.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/terminal/render/surface_layout.zig`, `howl-linux-host/src/terminal/vt/input.zig`, `howl-linux-host/src/terminal/vt/retained.zig`, `howl-linux-host/src/terminal/vt/surface.zig`, `howl-linux-host/src/main.zig`, `howl-linux-host/src/event.zig`, `howl-linux-host/src/display/present.zig`, `howl-linux-host/src/display/tab_bar.zig`, `howl-linux-host/src/display/window.zig`, `howl-linux-host/src/input/input.zig`, `howl-linux-host/src/host_test_root.zig`, `howl-linux-host/src/integration_test_root.zig`, `howl-linux-host/build.zig`.
- Required shape: rename `terminal/context.zig` to `terminal/surface.zig`; rename `terminal/context_test.zig` to `terminal/surface_test.zig`; update all imports and test references; keep the current `terminal/pty/`, `terminal/render/`, and `terminal/vt/` child folders; ensure the renamed owner now reads as the embedded terminal surface owner under Ghostty pressure rather than a generic context bucket.
- Required tests: `zig build test:unit`, `zig build test:integration`.
- Required assertions: preserve terminal-surface initialization, deinit, and geometry assertions from `terminal/context.zig:137-219`; preserve existing surface tests; preserve any bounds or lifecycle assertions in `terminal/tab_slots.zig` after the rename.
- Non-goals: no PTY, VT, or render behavior changes; no surface lifecycle redesign beyond owner naming and import rewiring.
- Stop conditions: stop if the rename reveals that `surface.zig` is not the real owner and would need a broader runtime redesign not already scoped here.
- Commit-hash receipt demand: mandatory on reviewer acceptance; orchestrator must record the exact commit hash before the slice can be marked accepted.

### Slice 4: C-Translation And Test-Root Placement Cleanup

- Accountable planning session ids: orchestrator `orch-2026-06-13-host-folder-structure-01`, researcher `research-2026-06-13-host-folder-structure-01`, reviewer `review-2026-06-13-host-folder-structure-01`.
- Allowed files: `howl-linux-host/build.zig`, `howl-linux-host/src/howl_pty_c.h`, `howl-linux-host/src/howl_vt_c.h`, `howl-linux-host/src/howl_render_c.h`, `howl-linux-host/src/sdl_c.h`, `howl-linux-host/src/display/renderer/gl_c.h`, `howl-linux-host/src/c/gl_c.h`, `howl-linux-host/src/c/howl_pty_c.h`, `howl-linux-host/src/c/howl_render_c.h`, `howl-linux-host/src/c/howl_vt_c.h`, `howl-linux-host/src/c/sdl_c.h`, `howl-linux-host/src/host_test_root.zig`, `howl-linux-host/src/integration_test_root.zig`, `howl-linux-host/src/test/host_test_root.zig`, `howl-linux-host/src/test/integration_test_root.zig`, `howl-linux-host/src/display/display.zig`, `howl-linux-host/src/display/render_surface.zig`.
- Required shape: create `src/c/` and move every translated-C header there, including `src/display/renderer/gl_c.h` to the exact final target `src/c/gl_c.h`; create `src/test/` and move the curated test roots there; update `build.zig` so all translated-C module paths and test-root paths point to the new owner-true locations; rewire any direct `gl_c` or test-root import sites touched by the path changes; leave no C headers or curated test roots at `src/` top level.
- Required tests: `zig build test:unit`, `zig build test:integration`, `zig build test:unit:build`, `zig build test:integration:build`.
- Required assertions: preserve all current test-root imports from `host_test_root.zig:1-14` and `integration_test_root.zig:1-8`; do not weaken any existing test coverage gates wired in `build.zig:233-375`.
- Non-goals: no new test classes, no removal of owner-local tests, no ABI/header content changes beyond path relocation.
- Stop conditions: stop if test-root placement requires adding a second competing test root per class, or if any translated-C header move would force an ABI content rewrite rather than a pure owner-path cleanup.
- Commit-hash receipt demand: mandatory on reviewer acceptance; orchestrator must record the exact commit hash before the slice can be marked accepted.

## Required Assertions

- The host event pump must keep its bounded SDL turn limit and wake classification assertions.
- Terminal tab-slot ownership must keep explicit bounds assertions on active/free counts and slot indexes.
- Display present submission and completion must keep token validity assertions and no-double-submit assertions.
- Surface lifecycle must keep explicit init/deinit and live-state assertions after the `surface` rename.
- Build/test wiring must keep one curated unit root and one curated integration root only.

## Required Tests

- Slice-local gate for every slice: `zig build test:unit` and `zig build test:integration`.
- Final sprint gate after Slice 4: `zig build test:unit`, `zig build test:integration`, `zig build test:unit:build`, and `zig build test:integration:build`.
- Owner-local tests that must survive path moves: the current event-loop tests, tab-bar snapshot tests, tab-slot bounds/order tests, display present tests, terminal surface tests, and window title idempotence test.

## Risks

- Import churn is high because nearly every current top-level host root appears in `main.zig` and/or the host test roots.
- Moving `tab_bar/slots.zig` is the highest ownership-risk move because it is stateful runtime bookkeeping currently living beside a visual owner.
- Moving `display/renderer/*` and the GL header can accidentally broaden into render redesign if the worker starts inventing a host renderer package. That is explicitly forbidden in this sprint.
- Renaming `terminal/context.zig` to `surface.zig` is source-backed, but the worker must not use the rename as cover for PTY or VT behavior changes.

## Proof Gaps

- Alacritty does not provide a direct tabbed embedded-surface equivalent, so the `surface` naming and terminal-surface collection placement rely on Ghostty as the secondary pressure. This is acceptable under the seeded reference priority because Alacritty lacks that exact host shape.
- Alacritty does not have a direct translated-C header folder analogue for the host. The `src/c/` decision is therefore driven by current Howl build reality plus the project FFI rule and Ghostty's explicit C seams. The exact final path for `gl_c.h` is `src/c/gl_c.h`, and only Slice 4 is allowed to move it.
- The research did not inspect every file inside `terminal/render/` and `terminal/vt/` because the current sprint question is folder owner structure, not terminal-core redesign. Those child folders remain justified by current multiplicity and must not be relitigated unless a slice proves they are weak.

## Readiness Judgment

- Ready for reviewer gate.
- The plan is full-sprint, sequential, source-backed, and specific enough to seed execution without coder invention.
- No implementation is authorized from this artifact alone.
