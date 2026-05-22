# Scratchpad

Purpose: next comprehensive style-breach list built from 5 reference-gated audits.

Rule:

- Ghostty first.
- Alacritty second.
- TigerBeetle third.
- Anything outside that order is stale debt or style breach unless proved otherwise.

## Cross-repo

### 1. PTY stop/wait seam is incomplete across the shipped ABI
- Offenders
  - `howl-pty/include/howl_pty.h:88-100`
  - `howl-pty/src/ffi.zig:172-220`
  - `howl-pty/src/session.zig:223-226`
  - `howl-pty/src/session.zig:303-316`
  - `howl-pty/src/session.zig:441-446`
  - `howl-linux-host/src/terminal/runtime/thread.zig:7-17`
  - `howl-linux-host/src/terminal/runtime/thread.zig:49-57`
  - `howl-linux-host/src/terminal/runtime/thread.zig:66-76`
  - `howl-linux-host/src/terminal/terminal_panel.zig:132-145`
- Breach
  - Host still compensates for missing authoritative PTY wake/stop seam; join can depend on PTY activity/backend exit.
- Reference against it
  - `howl-pty/design.md:125-131`
  - `AGENTS.md:38-42`
  - `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:98-131`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:251-316`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:278-369`
- Fix according to reference
  - Export an authoritative PTY wake seam through the ABI or make stop break `wait_readable` directly.

### 2. VT benchmark reaches into host-owned replay artifacts
- Offenders
  - `howl-vt/src/test/terminal_benchmark.zig:650-679`
- Breach
  - VT proof code hardcodes host-owned replay artifact paths.
- Reference against it
  - `AGENTS.md:14-19,21-26`
  - `howl-vt/design.md:6-12,192-205`
- Fix according to reference
  - Move replay fixtures under `howl-vt` ownership or inject explicit paths.

### 3. Render proof code reaches into host-owned font assets
- Offenders
  - `howl-render/src/text/font/ft_hb/support.zig:640-667`
- Breach
  - Render proof depends on host-owned font asset layout.
- Reference against it
  - `AGENTS.md:21-26`
  - `howl-render/design.md:54-57,163-176`
  - `howl-linux-host/design.md:63-65`
- Fix according to reference
  - Put proof fonts under render ownership or inject test font paths.

## howl-pty

### 4. Public PTY facade still exists as a parallel Zig surface
- Offenders
  - `howl-pty/src/pty.zig:19-74`
- Breach
  - Still publishes package-visible PTY facade nouns despite the locked ABI-only posture.
- Reference against it
  - `howl-pty/design.md:11-20,48-53,113-118,125-131`
  - `AGENTS.md:14-19,30-34`
  - `utils/dev_references/terminals/ghostty/src/pty.zig`
- Fix according to reference
  - Demote `src/pty.zig` to internal plumbing and keep build-selected PTY construction behind `Session`.

### 5. `Session` still publishes repo-local helpers as API shape
- Offenders
  - `howl-pty/src/session.zig:5-8`
  - `howl-pty/src/session.zig:207-215`
  - `howl-pty/src/session.zig:286-290`
  - `howl-pty/src/session.zig:494-500`
- Breach
  - Repo-local/testing conveniences preserve a second public story beside the C ABI.
- Reference against it
  - `howl-pty/design.md:11-20,111-118,125-131`
  - `AGENTS.md:17-19,30-34`
- Fix according to reference
  - Keep those helpers internal to tests/repo wiring only.

### 6. Outbound queue is bounded by policy but still heap-grows during steady state
- Offenders
  - `howl-pty/src/session.zig:127-128`
  - `howl-pty/src/session.zig:135-150`
  - `howl-pty/src/session.zig:240-261`
- Breach
  - Queue limit exists, but storage still grows dynamically on hot path.
- Reference against it
  - `AGENTS.md:39-42,57`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-104,151-156,179-184`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/ring_buffer.zig`
- Fix according to reference
  - Preallocate full queue capacity at init and use a fixed-capacity owner queue.

### 7. Child exec hygiene is below Ghostty/Alacritty PTY lifecycle shape
- Offenders
  - `howl-pty/src/pty/pty_unix.zig:54-75`
  - `howl-pty/src/pty/pty_android.zig:57-93`
  - `howl-pty/src/pty/pty_platform.zig:119-151`
- Breach
  - Missing CLOEXEC/close discipline and signal-reset hygiene in child pre-exec path.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/pty.zig:153-169,227-265`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:248-275`
- Fix according to reference
  - Add explicit child-pre-exec setup with signal reset, fd close discipline, and CLOEXEC backstop.

### 8. Unix and Android PTY owners duplicate the same control spine
- Offenders
  - `howl-pty/src/pty/pty_unix.zig:24-230`
  - `howl-pty/src/pty/pty_android.zig:27-247`
- Breach
  - Shared lifecycle/wake/read/write/resize/control logic is duplicated.
- Reference against it
  - `AGENTS.md:32-42,63-66`
  - `utils/dev_references/terminals/ghostty/src/pty.zig`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- Fix according to reference
  - Factor shared PTY transport state machine into one internal owner and keep only backend-specific leaves.

### 9. PTY interface erases operating contracts with `anyerror`
- Offenders
  - `howl-pty/src/pty/pty_platform.zig:24-62`
  - `howl-pty/src/pty/pty_unix.zig:49,128,136,151,167,197`
  - `howl-pty/src/pty/pty_android.zig:52,145,153,168,184,214`
  - `howl-pty/src/pty/pty_test.zig:27,38,44,55,64,94,105,113,118,126,149,158,163,168,176`
- Breach
  - PTY vtable and implementations hide the real transport contract.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/pty.zig`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-114,213-229`
- Fix according to reference
  - Define narrow PTY error sets and thread them explicitly through Session and FFI.

## howl-vt

### 10. Title OSC bypass in the router
- Offenders
  - `howl-vt/src/action/route.zig:64-67`
- Breach
  - Parent router special-cases raw OSC title events instead of letting xterm OSC owner handle them.
- Reference against it
  - `howl-vt/design.md`
  - `utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig`
- Fix according to reference
  - Map title/raw_title in `src/xterm/osc.zig` and let host consequence owner apply it.

### 11. Router-owned reset composition mutates multiple owners directly
- Offenders
  - `howl-vt/src/action/route.zig:79-108`
- Breach
  - Parent router directly resets screen, kitty, and host locator state.
- Reference against it
  - `howl-vt/design.md`
  - `AGENTS.md`
  - `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
- Fix according to reference
  - Move reset composition into terminal owner and let it delegate to subowners.

### 12. Mode owner reaches into selection during alt-screen switching
- Offenders
  - `howl-vt/src/control/mode.zig:187-195`
- Breach
  - Mode owner clears selection during alt-screen transitions.
- Reference against it
  - `howl-vt/design.md`
  - `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig`
- Fix according to reference
  - Move selection clearing into `screen_set` or selection owner.

### 13. Kitty retained-state helpers silently drop allocation failures
- Offenders
  - `howl-vt/src/kitty/apply.zig:55-77`
- Breach
  - Allocation failure is swallowed and retained state is partially lost.
- Reference against it
  - `howl-vt/design.md:170-175`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- Fix according to reference
  - Make helpers fallible and propagate OOM/limit failures through feed.

### 14. Kitty graphics state is unbounded and non-fallible
- Offenders
  - `howl-vt/src/kitty/graphics.zig:54-59`
  - `howl-vt/src/kitty/graphics.zig:122-137`
  - `howl-vt/src/kitty/graphics.zig:183-260`
  - `howl-vt/src/kitty/graphics.zig:403-410`
- Breach
  - Graphics images/placements/frames/uploads use unbounded growth and silent failure paths.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
  - `utils/dev_references/terminals/ghostty/src/terminal/Screen.zig`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- Fix according to reference
  - Add explicit byte/count caps and make graphics handling fallible.

### 15. Scratch-buffer formatting failures silently drop protocol output
- Offenders
  - `howl-vt/src/control/report.zig:193-246`
  - `howl-vt/src/control/report.zig:266-312`
  - `howl-vt/src/control/locator.zig:83-90`
  - `howl-vt/src/control/locator.zig:130-135`
  - `howl-vt/src/control/osc_color.zig:296-299`
  - `howl-vt/src/control/osc_color.zig:329-356`
  - `howl-vt/src/kitty/key.zig:36-38`
  - `howl-vt/src/kitty/graphics.zig:403-410`
- Breach
  - `bufPrint(... ) catch return` turns local sizing bugs into silent protocol loss.
- Reference against it
  - `howl-vt/design.md:170-175`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- Fix according to reference
  - Either assert buffer sufficiency as invariant or make formatting fallible and propagate failure.

## howl-render

### 16. Reserve-publish FFI adds a second allocation/copy layer
- Offenders
  - `howl-render/src/frame/surface_text_ffi.zig:15-35`
  - `howl-render/src/frame/surface_text_ffi.zig:138-180`
- Breach
  - Reserve-publish path allocates shadow buffers and copies again into render-owned slot.
- Reference against it
  - `howl-render/design.md:133-150`
  - `AGENTS.md:30-34`
- Fix according to reference
  - Expose render-owned reserved slot directly through ABI spans and commit only metadata.

### 17. Publish-slot storage is heap-allocated per reservation instead of retained by owner
- Offenders
  - `howl-render/src/frame/queue.zig:321-373`
- Breach
  - Cells and dirty arrays are allocated every reservation.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-100,151-156`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig`
- Fix according to reference
  - Pre-size one owner-held publication slot from geometry/session limits and reuse it.

### 18. Prepare path heap-copies the full VT grid before text preparation
- Offenders
  - `howl-render/src/frame/surface_text.zig:114-127`
  - `howl-render/src/frame/input.zig:176-259`
- Breach
  - Full temporary `CellInput` array is allocated per prepare.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/terminal/render.zig:28-48`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-49,153-183`
- Fix according to reference
  - Use retained owner scratch or borrowed owner state directly instead of full temporary grid copies.

### 19. Scene build recreates all draw lists as fresh heap-owned slices each frame
- Offenders
  - `howl-render/src/text/scene.zig:76-98`
  - `howl-render/src/text/scene.zig:107-139`
- Breach
  - Per-frame owned slices are rebuilt for multiple draw categories.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/terminal/render.zig:44-48`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs:24-73`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:151-156`
- Fix according to reference
  - Move these lists into retained owner scratch with explicit capacities.

### 20. Resolver uses unbounded per-call ArrayLists and AutoHashMap scratch
- Offenders
  - `howl-render/src/text/font/resolver.zig:73-165`
- Breach
  - Resolve scratch allocates growable containers per call with no explicit cap.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-100,151-156`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig:61-84`
- Fix according to reference
  - Replace per-call growable containers with fixed-capacity resolve scratch sized from session limits.

### 21. FT/HB caches and shape-input assembly are still unbounded heap structures
- Offenders
  - `howl-render/src/text/font/ft_hb/cache.zig:39-124`
  - `howl-render/src/text/font/ft_hb/support.zig:120-129`
  - `howl-render/src/text/font/ft_hb/support.zig:167-193`
  - `howl-render/src/text/font/ft_hb/support.zig:277-283`
  - `howl-render/src/text/font/ft_hb/support.zig:581-590`
- Breach
  - Caches are unbounded maps and shape-input assembly uses growable lists.
- Reference against it
  - `utils/dev_references/terminals/ghostty/src/font/Atlas.zig:90-119`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:11-18,72-110`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-100`
- Fix according to reference
  - Give caches explicit capacities and use retained bounded buffers.

### 22. Cluster extraction/build path stacks multiple growable assembly layers
- Offenders
  - `howl-render/src/text/shape/cluster.zig:98-166`
  - `howl-render/src/text/shape/cluster.zig:235-345`
  - `howl-render/src/text/shape/cluster.zig:376-432`
  - `howl-render/src/text/shape/cluster.zig:489-512`
- Breach
  - Multiple growable maps/lists/realloc transitions remain in hot text-shape path.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100,158-175`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig:74-124`
- Fix according to reference
  - Collapse into fewer owner-held bounded buffers with explicit precomputed counts.

### 23. Benchmark control spine violates the 70-line function limit
- Offenders
  - `howl-render/src/test/benchmark.zig:586-756`
- Breach
  - `runWorkload` is 171 lines.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:161-175`
- Fix according to reference
  - Split cold setup, warm loop, observation extraction, and summary aggregation into helpers.

## howl-linux-host

### 24. Unbounded SDL burst drain per host turn
- Offenders
  - `howl-linux-host/src/input/input.zig:166-210`
  - especially `howl-linux-host/src/input/input.zig:203-210`
- Breach
  - `drainPendingEvents` polls until SDL is empty, so one host turn can absorb an unbounded burst.
- Reference against it
  - `howl-linux-host/design.md:66-72`
  - `AGENTS.md:38-42`
- Fix according to reference
  - Add an explicit per-turn SDL event cap and continue on the next turn.

### 25. Wake thread blocks forever instead of waiting in bounded slices
- Offenders
  - `howl-linux-host/src/terminal/runtime/thread.zig:7-7`
  - `howl-linux-host/src/terminal/runtime/thread.zig:49-76`
  - `howl-linux-host/src/terminal/pty/session.zig:106-108`
- Breach
  - `transport_wait_timeout_ms = -1` makes background wait path unbounded.
- Reference against it
  - `howl-linux-host/design.md:66-70`
  - `AGENTS.md:38-42`
- Fix according to reference
  - Replace infinite wait with finite timeout slices and re-check stop/handoff state each slice.

### 26. Bounded queues implemented with O(n) front-shifts instead of a ring
- Offenders
  - `howl-linux-host/src/input/input.zig:106-117`
  - `howl-linux-host/src/input/input.zig:125-136`
- Breach
  - Bounded queues still memmove the live tail on dequeue.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/ring_buffer.zig:8-18,174-245`
- Fix according to reference
  - Replace both queues with fixed-capacity ring buffers.

### 27. Fixed 9-tab host still relies on runtime heap growth/churn
- Offenders
  - `howl-linux-host/src/main.zig:22-22`
  - `howl-linux-host/src/main.zig:90-93`
  - `howl-linux-host/src/main.zig:482-506`
  - `howl-linux-host/src/terminal/terminal_panel.zig:74-96`
- Breach
  - Host has a hard tab cap of 9 but still uses heap-backed list growth and per-tab create/destroy churn.
- Reference against it
  - `howl-linux-host/src/tab_bar/tab_bar.zig:5-6`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-97,151-159`
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222`
  - `utils/dev_references/zig_maturity/tigerbeetle/src/stdx/bounded_array.zig:5-27`
- Fix according to reference
  - Preallocate tab slots up to `max_tabs` and store them in a bounded owner container/free-list.

### 28. Invariant failures use `@panic` instead of assertion-style contracts
- Offenders
  - `howl-linux-host/src/tab_bar/tab_bar.zig:16-19`
  - `howl-linux-host/src/tab_bar/tab_bar.zig:30-32`
- Breach
  - Programmer-error invariants use ad hoc `@panic`.
- Reference against it
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104-123`
- Fix according to reference
  - Replace panics with explicit asserts near the owner boundary.
