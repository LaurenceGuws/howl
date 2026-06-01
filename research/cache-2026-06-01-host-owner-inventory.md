# Host Owner Inventory Cache

## Date

2026-06-01

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `howl-linux-host/README.md`
- `howl-linux-host/design.md`
- `howl-linux-host/build.zig`
- `howl-linux-host/build_support/host_tests.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/app/present.zig`
- `howl-linux-host/src/app/process_accounting.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/input/keys.zig`
- `howl-linux-host/src/input/mouse.zig`
- `howl-linux-host/src/input/window.zig`
- `howl-linux-host/src/window/window.zig`
- `howl-linux-host/src/window/pacing.zig`
- `howl-linux-host/src/window/present.zig`
- `howl-linux-host/src/window/draw.zig`
- `howl-linux-host/src/window/layout.zig`
- `howl-linux-host/src/window/texture.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/window/scrollbar.zig`
- `howl-linux-host/src/window/icon.zig`
- `howl-linux-host/src/tab_bar/tab_bar.zig`
- `howl-linux-host/src/tab_bar/slots.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/term.zig`
- `howl-linux-host/src/terminal/selection.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/terminal/pty/session.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/pty/retained.zig`
- `howl-linux-host/src/terminal/pty/feed_record.zig`
- `howl-linux-host/src/terminal/vt/input.zig`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/terminal/vt/retained.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/render/surface_layout.zig`
- `howl-linux-host/src/terminal/render/fonts_linux.zig`
- `howl-linux-host/src/terminal/render/font_size.zig`
- `howl-linux-host/src/config/config.zig`
- `howl-linux-host/src/config/terminal.zig`
- `howl-linux-host/src/config/window.zig`
- `howl-linux-host/src/config/tab_bar.zig`
- `howl-linux-host/src/config/env.zig`
- `howl-linux-host/src/cli/args.zig`
- `howl-linux-host/src/test_root.zig`
- `howl-linux-host/src/test/test_entry.zig`
- `howl-linux-host/src/test/host.zig`
- `howl-linux-host/src/test/integration_entry.zig`

## Question

Inventory `howl-linux-host` as a whole and produce a source-backed ownership map: true owners, stale or misnamed owners, files that over-own behavior, files that look maintained versus stale, and the top host-wide structural risks. This cache records research only. It does not define implementation slices.

## Findings

- The intended public host boundary is explicit: the host embeds `howl-pty`, `howl-vt`, and `howl-render` through C ABIs and owns app lifecycle, input, tabs, wake policy, frame pacing, backend resources, upload, and presentation in `howl-linux-host/README.md:3-6`.
- The README owner map names `src/main.zig`, `src/input/`, `src/window/`, `src/tab_bar/`, and `src/terminal/` as top-level owners in `howl-linux-host/README.md:20-28`.
- The design document sharpens this boundary: the host owns platform UX, SDL input, app event loop, wake policy, tab/window orchestration, presentation cadence, backend resource realization, and process-level launch policy, and does not own PTY internals, VT semantics, render internals, or terminal-state truth in `howl-linux-host/design.md:7-12`.
- The design document declares C ABI integration as the only public surface and rejects Zig imports into subrepos as an integration surface in `howl-linux-host/design.md:13-18`.
- The design owner map is specific enough to audit against: `main.zig`, `config`, `cli`, `input`, `tab_bar`, `window`, `terminal/context.zig`, terminal selection/links, PTY, VT, and render seams are listed in `howl-linux-host/design.md:20-38`.
- The design invariants require centralized event-loop control, background threads that only wait/wake owner thread, terminal mutation through `terminal/context.zig` or smaller terminal owners, C ABI consumption only, SDL/OpenGL calls in host owners, and complete-surface upload semantics in `howl-linux-host/design.md:57-65`.
- `build.zig` reinforces the ABI harness boundary: internal terminal modules are consumed through shipped C headers and exported symbols only, with no privileged Zig-shaped integration path in `howl-linux-host/build.zig:1-4`.
- `build.zig` translates C headers for PTY, VT, render, SDL, and GL in `howl-linux-host/build.zig:145-149` and wires host link inputs in `howl-linux-host/build.zig:199-212`.
- `src/main.zig` is the real app owner: it owns bootstrap/config/window/tab/input allocation and first tab open in `howl-linux-host/src/main.zig:90-174`.
- `src/main.zig` owns centralized loop admission and progression in `howl-linux-host/src/main.zig:221-288`.
- `src/main.zig` owns tab lifecycle and active-tab focus/title synchronization in `howl-linux-host/src/main.zig:798-857`.
- `src/main.zig` owns active render snapshot and present orchestration in `howl-linux-host/src/main.zig:561-646`.
- `src/app/present.zig` owns present reason derivation, submit routing, terminal-present token recording, and completion drain in `howl-linux-host/src/app/present.zig:29-85`.
- `src/app/process_accounting.zig` owns Linux `/proc` debug accounting state and counters in `howl-linux-host/src/app/process_accounting.zig:108-239` and `/proc` sampling/logging in `howl-linux-host/src/app/process_accounting.zig:296-442`.
- `src/input/input.zig` owns a fixed bounded input ring and SDL event burst bound in `howl-linux-host/src/input/input.zig:8-60`.
- `src/input/input.zig` owns the typed input queues, redraw/focus/geometry state, mouse policy, and SDL window wake state fields in `howl-linux-host/src/input/input.zig:63-106`.
- `src/input/input.zig` owns SDL pump/wait/drain flow with one bounded SDL burst per turn in `howl-linux-host/src/input/input.zig:201-254`.
- `src/input/input.zig` owns SDL event classification into host input events and owner flags in `howl-linux-host/src/input/input.zig:256-324`.
- `src/input/keys.zig` owns host key names, byte input shape, binding actions, binding parse, focus-tab action mapping, and binding resolution in `howl-linux-host/src/input/keys.zig:6-293`.
- `src/input/mouse.zig` is a clean type-only owner for modifier, button, kind, buttons, and mouse event shapes in `howl-linux-host/src/input/mouse.zig:1-37`.
- `src/input/window.zig` owns SDL wake event state, quit timer, wake semaphore, and SDL time wrappers in `howl-linux-host/src/input/window.zig:14-98`.
- `src/window/window.zig` owns SDL window lifecycle, GL present state containment, geometry, title, focus, and host presentation forwarding in `howl-linux-host/src/window/window.zig:84-206`.
- `src/window/window.zig` owns SDL video init/quit, window create/destroy, clipboard, texture deletion, cursor, and URL calls in `howl-linux-host/src/window/window.zig:214-301`.
- `src/window/pacing.zig` owns frame permit, redraw/render-work state, present-in-flight, present-complete drain state, wait admission, render permission, and present submission permission in `howl-linux-host/src/window/pacing.zig:18-151`.
- `src/window/present.zig` owns host GL present state, proof state, token state, and diagnostics in `howl-linux-host/src/window/present.zig:65-82`.
- `src/window/present.zig` owns GL context init and present submission in `howl-linux-host/src/window/present.zig:88-180`.
- `src/window/present.zig` owns readiness/swap diagnostics in `howl-linux-host/src/window/present.zig:198-280`.
- `src/window/present.zig` owns tab-bar texture cache update and draw in `howl-linux-host/src/window/present.zig:283-336`.
- `src/window/present.zig` owns test-only framebuffer/texture proof capture and observation in `howl-linux-host/src/window/present.zig:388-491`.
- `src/window/draw.zig` owns immediate-mode GL chrome drawing for tab bar labels and scrollbar in `howl-linux-host/src/window/draw.zig:5-104`.
- `src/window/layout.zig` owns presentation structs and logical-to-pixel scaling helpers in `howl-linux-host/src/window/layout.zig:3-51`.
- `src/window/texture.zig` owns generic GL textured-quad draw and swap wrappers in `howl-linux-host/src/window/texture.zig:1-60`.
- `src/window/scrollbar.zig` owns host scrollbar model, view, mouse result, state, layout, hover/drag, and offset calculation in `howl-linux-host/src/window/scrollbar.zig:13-168`.
- `src/window/scrollbar.zig` owns scrollbar geometry/focus functions and view conversion support in `howl-linux-host/src/window/scrollbar.zig:170-275`.
- `src/window/icon.zig` owns direct icon loading through SDL and stb_image in `howl-linux-host/src/window/icon.zig:3-47`; this matches the design's direct `@cImport` exception in `howl-linux-host/design.md:43-44`.
- `src/window/term_texture.zig` owns render resource texture slots, slot diagnostics, create/upload/retire metadata, and GL resource lifecycle in `howl-linux-host/src/window/term_texture.zig:24-125` and `howl-linux-host/src/window/term_texture.zig:349-447`.
- `src/window/term_texture.zig` owns host-side render-surface validation and state transition simulation in `howl-linux-host/src/window/term_texture.zig:199-347`.
- `src/window/term_texture.zig` owns host surface creation and render-surface upload entry points in `howl-linux-host/src/window/term_texture.zig:1922-2018`.
- `src/window/term_texture.zig` owns render-surface shape classifiers in `howl-linux-host/src/window/term_texture.zig:2110-2260` and command drawing in `howl-linux-host/src/window/term_texture.zig:2390-2504`.
- `src/tab_bar/tab_bar.zig` owns bounded tab label snapshots in `howl-linux-host/src/tab_bar/tab_bar.zig:3-35`.
- `src/tab_bar/slots.zig` owns bounded active/free terminal context storage and ordered removal in `howl-linux-host/src/tab_bar/slots.zig:10-98`.
- `src/terminal/context.zig` owns the terminal aggregate state, including PTY wait progress, render host surface, render resource textures, diagnostics, config/input pointers, geometry, focus, scrollbar, links, selection, hover publish, and cursor blink in `howl-linux-host/src/terminal/context.zig:53-147`.
- `src/terminal/context.zig` owns terminal initialization/deinitialization in `howl-linux-host/src/terminal/context.zig:148-214` and terminal ABI object initialization/runtime start in `howl-linux-host/src/terminal/context.zig:460-492`.
- `src/terminal/context.zig` owns input routing from host input to text fast path, pointer/UI path, and scroll path in `howl-linux-host/src/terminal/context.zig:237-277` and `howl-linux-host/src/terminal/context.zig:1519-1591`.
- `src/terminal/context.zig` owns render turn, present submission notification, and present completion in `howl-linux-host/src/terminal/context.zig:412-449`.
- `src/terminal/context.zig` owns render backend upload, render-surface realization, host surface ensure/upload, and render submit execution in `howl-linux-host/src/terminal/context.zig:611-830`.
- `src/terminal/context.zig` owns render-surface submit diagnostics state in `howl-linux-host/src/terminal/context.zig:82-122` and diagnostic logging in `howl-linux-host/src/terminal/context.zig:919-1197`.
- `src/terminal/term.zig` owns the terminal aggregate and fair/unfair mutex wrapper in `howl-linux-host/src/terminal/term.zig:10-58`.
- `src/terminal/selection.zig` owns host selection gesture adaptation over context fields and VT retained selection calls in `howl-linux-host/src/terminal/selection.zig:14-76`.
- `src/terminal/links.zig` owns link hover/open behavior, hover decoration, cursor switching, and link lookup in `howl-linux-host/src/terminal/links.zig:14-128`.
- `src/terminal/scrollbar.zig` owns terminal scroll-page/mouse/layout adaptation between VT retained scroll state and window scrollbar owner in `howl-linux-host/src/terminal/scrollbar.zig:18-85`.
- `src/terminal/cursor_blink.zig` owns cursor blink cadence state and planning in `howl-linux-host/src/terminal/cursor_blink.zig:6-54`.
- `src/terminal/pty/session.zig` owns PTY ABI handle init/deinit/start/stop/resize/snapshot/outcome and input publication in `howl-linux-host/src/terminal/pty/session.zig:60-208`.
- `src/terminal/pty/session.zig` owns PTY outcome classification in `howl-linux-host/src/terminal/pty/session.zig:247-254`.
- `src/terminal/pty/pump.zig` owns bounded PTY/VT progress turn derivation in `howl-linux-host/src/terminal/pty/pump.zig:43-55`.
- `src/terminal/pty/pump.zig` owns transport slicing, bounded read backlog, opportunistic/forced lock transition, and feed bounds in `howl-linux-host/src/terminal/pty/pump.zig:92-193`.
- `src/terminal/pty/pump.zig` owns PTY bytes to VT feed, feed recording, lifecycle failure marking, and pending VT output reply drain in `howl-linux-host/src/terminal/pty/pump.zig:263-312`.
- `src/terminal/pty/wait_thread.zig` owns wait-thread state and wake-pending handoff in `howl-linux-host/src/terminal/pty/wait_thread.zig:9-29`.
- `src/terminal/pty/wait_thread.zig` owns the background wait loop that only waits for wake ack, transport readability/death, and wakes the owner thread in `howl-linux-host/src/terminal/pty/wait_thread.zig:45-75`.
- `src/terminal/pty/retained.zig` owns PTY host-retained launch, lifecycle, feed record file, and feed record I/O state in `howl-linux-host/src/terminal/pty/retained.zig:3-21`.
- `src/terminal/pty/feed_record.zig` owns optional PTY feed recording start/deinit/write in `howl-linux-host/src/terminal/pty/feed_record.zig:4-33`.
- `src/terminal/vt/input.zig` owns host input to VT encoder translation for key/mod/mouse/button state in `howl-linux-host/src/terminal/vt/input.zig:27-93`.
- `src/terminal/vt/input.zig` owns paste/key/mouse/focus publication through VT encoding and PTY publication in `howl-linux-host/src/terminal/vt/input.zig:95-228`.
- `src/terminal/vt/surface.zig` owns VT visible source publication to render, visible surface slot reservation, source acquisition, hover decoration, render commit, and rejection in `howl-linux-host/src/terminal/vt/surface.zig:58-166`.
- `src/terminal/vt/surface.zig` owns VT visible meta/copy, VT cell to render source translation, colors/cursor/selection translation, and hover dirty marking in `howl-linux-host/src/terminal/vt/surface.zig:168-424`.
- `src/terminal/vt/retained.zig` owns host-retained VT scratch/title/output/input/surface/scroll/focus/cursor state in `howl-linux-host/src/terminal/vt/retained.zig:33-62`.
- `src/terminal/vt/retained.zig` owns VT title and scroll state wrappers in `howl-linux-host/src/terminal/vt/retained.zig:64-132`.
- `src/terminal/vt/retained.zig` owns VT feed/runtime/title/output/clipboard/hyperlink/selection/scroll/resize/cell-size/focus retained calls in `howl-linux-host/src/terminal/vt/retained.zig:136-354`.
- `src/terminal/render/retained.zig` owns host-side render retained state types, work state, layout sync, prepared upload, resource plan, resource-store status, and operations in `howl-linux-host/src/terminal/render/retained.zig:33-190`.
- `src/terminal/render/retained.zig` owns render resource store state transition validation and command/resource validation in `howl-linux-host/src/terminal/render/retained.zig:197-406`.
- `src/terminal/render/retained.zig` owns render-surface span/order/shape validation support in `howl-linux-host/src/terminal/render/retained.zig:408-520`.
- `src/terminal/render/surface_layout.zig` owns render/logical/grid geometry state in `howl-linux-host/src/terminal/render/surface_layout.zig:14-25`.
- `src/terminal/render/surface_layout.zig` owns resize capture and pending grid commit in `howl-linux-host/src/terminal/render/surface_layout.zig:56-104`.
- `src/terminal/render/surface_layout.zig` owns render-derived layout synchronization to PTY, VT, render retained state, and cell pixel size in `howl-linux-host/src/terminal/render/surface_layout.zig:106-202`.
- `src/terminal/render/fonts_linux.zig` owns bundled font paths, resolved font ownership, ordered fallback resolution, path realpath, and dedupe in `howl-linux-host/src/terminal/render/fonts_linux.zig:7-135`.
- `src/terminal/render/font_size.zig` owns font size adjustment/toggle/reset and the render ABI font-size call in `howl-linux-host/src/terminal/render/font_size.zig:7-55`.
- `src/config/config.zig` owns aggregate config load/deinit and process CLI overrides in `howl-linux-host/src/config/config.zig:13-74`.
- `src/config/terminal.zig` owns terminal config fields, typed policy enums, Lua config load, binding specs, font stack loading, link/mouse parsing, and helpers in `howl-linux-host/src/config/terminal.zig:8-378`.
- `src/config/window.zig` owns window config load and deinit in `howl-linux-host/src/config/window.zig:8-59`, but carries a binding loader despite empty binding specs in `howl-linux-host/src/config/window.zig:61-110`.
- `src/config/tab_bar.zig` owns tab-bar config, tab-bar binding specs, binding loader, and bitmap label font rows in `howl-linux-host/src/config/tab_bar.zig:7-153`.
- `src/config/env.zig` owns simple environment variable expansion in `howl-linux-host/src/config/env.zig:5-15` and tests/fuzz for expansion behavior in `howl-linux-host/src/config/env.zig:17-64`.
- `src/cli/args.zig` owns CLI options and parse behavior in `howl-linux-host/src/cli/args.zig:3-53`.
- `src/test/integration_entry.zig` is import-only integration coverage in `howl-linux-host/src/test/integration_entry.zig:1-8`.

## Reference Facts

- TigerBeetle requires simple explicit control flow, bounded loops/queues, and asserted non-terminating loops in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100`.
- TigerBeetle requires explicit assertions of arguments, return values, pre/postconditions, and invariants in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104-140`.
- TigerBeetle requires no dynamic allocation after initialization in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:151-156`.
- TigerBeetle pushes small scopes, small functions, centralized control flow, and centralized state mutation in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158-175`.
- TigerBeetle says external events should not directly drive work; the program should run at its own pace with bounded work in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:179-183`.
- TigerBeetle naming guidance requires precise nouns/verbs and top-down source order in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273-317`.
- TigerBeetle architecture frames static allocation as explicit upper bounds and component-owned in-flight contexts in `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222`.
- TigerBeetle architecture frames control-plane/data-plane separation as important for keeping control `if`s out of data-plane loops in `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:408-423`.
- TigerBeetle architecture frames io_uring/context ownership as component-owned contexts with bounded total concurrency in `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:467-487`.

## Owner Map

- Documentation owners: `howl-linux-host/README.md:20-28` gives the short top-level owner map; `howl-linux-host/design.md:20-38` gives the more precise host owner map.
- Build owner: `howl-linux-host/build.zig` owns host ABI harness build/dependency/test/stress wiring. The ABI harness rule is stated in `howl-linux-host/build.zig:1-4`; dependency resolution and translated C modules are in `howl-linux-host/build.zig:109-155`; host executable/link wiring is in `howl-linux-host/build.zig:167-212`; tests are wired in `howl-linux-host/build.zig:295-450`.
- Test build helper owner: `howl-linux-host/build_support/host_tests.zig` owns integration test module construction and link inputs in `howl-linux-host/build_support/host_tests.zig:3-36`.
- App owner: `howl-linux-host/src/main.zig` owns process bootstrap, app allocation, event loop, tab lifecycle, active tab routing, render snapshot, present admission, and high-level host mutation order in `howl-linux-host/src/main.zig:90-174`, `howl-linux-host/src/main.zig:221-288`, `howl-linux-host/src/main.zig:421-646`, and `howl-linux-host/src/main.zig:798-895`.
- App present owner: `howl-linux-host/src/app/present.zig` owns present reason/submission/completion semantics in `howl-linux-host/src/app/present.zig:29-85`.
- App accounting owner: `howl-linux-host/src/app/process_accounting.zig` owns debug accounting in `howl-linux-host/src/app/process_accounting.zig:108-239` and `howl-linux-host/src/app/process_accounting.zig:296-442`.
- CLI owner: `howl-linux-host/src/cli/args.zig` owns CLI options and parsing in `howl-linux-host/src/cli/args.zig:3-53`.
- Config aggregate owner: `howl-linux-host/src/config/config.zig` owns aggregate Lua load/deinit and process overrides in `howl-linux-host/src/config/config.zig:13-74`.
- Terminal config owner: `howl-linux-host/src/config/terminal.zig` owns terminal config fields, enum policies, bindings, fonts, and parsers in `howl-linux-host/src/config/terminal.zig:8-378`.
- Window config owner: `howl-linux-host/src/config/window.zig` owns window config load/deinit in `howl-linux-host/src/config/window.zig:8-59`.
- Tab-bar config owner: `howl-linux-host/src/config/tab_bar.zig` owns tab-bar config, tab bindings, and bitmap label glyph rows in `howl-linux-host/src/config/tab_bar.zig:7-153`.
- Config environment owner: `howl-linux-host/src/config/env.zig` owns environment expansion in `howl-linux-host/src/config/env.zig:5-15`.
- Input aggregate owner: `howl-linux-host/src/input/input.zig` owns bounded SDL event intake and typed host input queues in `howl-linux-host/src/input/input.zig:8-106` and `howl-linux-host/src/input/input.zig:201-324`.
- Input key owner: `howl-linux-host/src/input/keys.zig` owns host key and binding vocabulary in `howl-linux-host/src/input/keys.zig:6-293`.
- Input mouse owner: `howl-linux-host/src/input/mouse.zig` owns mouse input types in `howl-linux-host/src/input/mouse.zig:1-37`.
- Input wake owner: `howl-linux-host/src/input/window.zig` owns SDL wake/timer/semaphore/time wrappers in `howl-linux-host/src/input/window.zig:14-98`.
- Window aggregate owner: `howl-linux-host/src/window/window.zig` owns SDL window lifecycle, GL present containment, geometry, title, clipboard, cursor, URL, and texture deletion in `howl-linux-host/src/window/window.zig:84-301`.
- Window pacing owner: `howl-linux-host/src/window/pacing.zig` owns frame pacing and present permission state in `howl-linux-host/src/window/pacing.zig:18-151`.
- Window present owner: `howl-linux-host/src/window/present.zig` owns GL present state, present token completion, tab cache, proof capture, and diagnostics in `howl-linux-host/src/window/present.zig:65-180`, `howl-linux-host/src/window/present.zig:198-336`, and `howl-linux-host/src/window/present.zig:388-491`.
- Window draw owner: `howl-linux-host/src/window/draw.zig` owns immediate-mode host chrome drawing in `howl-linux-host/src/window/draw.zig:5-104`.
- Window layout owner: `howl-linux-host/src/window/layout.zig` owns host frame structs and coordinate scaling in `howl-linux-host/src/window/layout.zig:3-51`.
- Window texture owner: `howl-linux-host/src/window/texture.zig` owns generic textured quad and swap wrappers in `howl-linux-host/src/window/texture.zig:1-60`.
- Window terminal texture/render resource owner: `howl-linux-host/src/window/term_texture.zig` owns host GL realization of render surfaces and resources in `howl-linux-host/src/window/term_texture.zig:24-447` and `howl-linux-host/src/window/term_texture.zig:1922-2504`.
- Window scrollbar owner: `howl-linux-host/src/window/scrollbar.zig` owns host scrollbar state/layout/mouse math in `howl-linux-host/src/window/scrollbar.zig:13-275`.
- Window icon owner: `howl-linux-host/src/window/icon.zig` owns icon loading in `howl-linux-host/src/window/icon.zig:3-47`.
- Tab-bar label owner: `howl-linux-host/src/tab_bar/tab_bar.zig` owns bounded label snapshots in `howl-linux-host/src/tab_bar/tab_bar.zig:3-35`.
- Tab slot owner: `howl-linux-host/src/tab_bar/slots.zig` owns bounded tab storage and active/free ordering in `howl-linux-host/src/tab_bar/slots.zig:10-98`.
- Terminal aggregate owner: `howl-linux-host/src/terminal/context.zig` owns one terminal session/surface aggregate and cross-owner routing in `howl-linux-host/src/terminal/context.zig:53-1591`.
- Terminal shared aggregate owner: `howl-linux-host/src/terminal/term.zig` owns `Term` and its mutex in `howl-linux-host/src/terminal/term.zig:10-58`.
- Terminal selection owner: `howl-linux-host/src/terminal/selection.zig` owns selection gesture adaptation in `howl-linux-host/src/terminal/selection.zig:14-76`.
- Terminal links owner: `howl-linux-host/src/terminal/links.zig` owns link hover/open behavior in `howl-linux-host/src/terminal/links.zig:14-128`.
- Terminal scrollbar owner: `howl-linux-host/src/terminal/scrollbar.zig` owns terminal-specific scrollbar adaptation in `howl-linux-host/src/terminal/scrollbar.zig:18-85`.
- Terminal cursor blink owner: `howl-linux-host/src/terminal/cursor_blink.zig` owns blink cadence state in `howl-linux-host/src/terminal/cursor_blink.zig:6-54`.
- PTY session owner: `howl-linux-host/src/terminal/pty/session.zig` owns PTY ABI session translation and lifecycle in `howl-linux-host/src/terminal/pty/session.zig:60-254`.
- PTY pump owner: `howl-linux-host/src/terminal/pty/pump.zig` owns bounded PTY/VT progress in `howl-linux-host/src/terminal/pty/pump.zig:43-312`.
- PTY wait-thread owner: `howl-linux-host/src/terminal/pty/wait_thread.zig` owns wait-only thread handoff in `howl-linux-host/src/terminal/pty/wait_thread.zig:9-120`.
- PTY retained owner: `howl-linux-host/src/terminal/pty/retained.zig` owns host-retained PTY fields in `howl-linux-host/src/terminal/pty/retained.zig:3-21`.
- PTY feed record owner: `howl-linux-host/src/terminal/pty/feed_record.zig` owns feed recording in `howl-linux-host/src/terminal/pty/feed_record.zig:4-33`.
- VT input owner: `howl-linux-host/src/terminal/vt/input.zig` owns host input encoding through VT and PTY in `howl-linux-host/src/terminal/vt/input.zig:27-228`.
- VT surface owner: `howl-linux-host/src/terminal/vt/surface.zig` owns VT visible source publication and VT-to-render source translation in `howl-linux-host/src/terminal/vt/surface.zig:58-424`.
- VT retained owner: `howl-linux-host/src/terminal/vt/retained.zig` owns retained VT host scratch/state and ABI wrappers in `howl-linux-host/src/terminal/vt/retained.zig:33-354`.
- Render retained owner: `howl-linux-host/src/terminal/render/retained.zig` owns render retained state and resource validation/planning in `howl-linux-host/src/terminal/render/retained.zig:33-520`.
- Render surface layout owner: `howl-linux-host/src/terminal/render/surface_layout.zig` owns surface/grid resize state and synchronization in `howl-linux-host/src/terminal/render/surface_layout.zig:14-202`.
- Render Linux fonts owner: `howl-linux-host/src/terminal/render/fonts_linux.zig` owns font resolution in `howl-linux-host/src/terminal/render/fonts_linux.zig:7-135`.
- Render font size owner: `howl-linux-host/src/terminal/render/font_size.zig` owns font-size transitions in `howl-linux-host/src/terminal/render/font_size.zig:7-55`.

## Stale Or Misnamed Owners

- `howl-linux-host/src/terminal/context.zig` is accurately named as an aggregate but stale as an owner shape. It now includes terminal init, input routing, render upload, GL surface diagnostics, OSC52, cursor blink, link hover publication, and extensive tests. Evidence: state at `howl-linux-host/src/terminal/context.zig:53-147`, init/runtime at `howl-linux-host/src/terminal/context.zig:460-492`, render upload at `howl-linux-host/src/terminal/context.zig:611-830`, diagnostics at `howl-linux-host/src/terminal/context.zig:919-1197`, and input routing at `howl-linux-host/src/terminal/context.zig:1519-1591`.
- `howl-linux-host/src/window/term_texture.zig` is misnamed. It is not just a terminal texture owner; it owns render resource lifecycle, render-surface command validation, shape recognition, GL upload, and draw command execution. Evidence: resource slots at `howl-linux-host/src/window/term_texture.zig:24-43`, surface validation at `howl-linux-host/src/window/term_texture.zig:199-269`, GL create/upload/retire at `howl-linux-host/src/window/term_texture.zig:349-447`, and shape/upload/draw at `howl-linux-host/src/window/term_texture.zig:1922-2504`.
- `howl-linux-host/src/input/window.zig` is misnamed. It owns SDL event-loop wake state, timers, semaphores, and time, not window input semantics. Evidence: wake state at `howl-linux-host/src/input/window.zig:14-58`; timer/semaphore wrappers at `howl-linux-host/src/input/window.zig:60-98`.
- `howl-linux-host/src/window/present.zig` is broader than present. It owns present tokens, GL draw, tab-bar cache, diagnostics, and proof capture. Evidence: state at `howl-linux-host/src/window/present.zig:65-82`, cache at `howl-linux-host/src/window/present.zig:283-336`, proof capture at `howl-linux-host/src/window/present.zig:388-491`.
- `howl-linux-host/src/config/window.zig` has stale-looking binding loader scaffolding with empty `binding_specs` at `howl-linux-host/src/config/window.zig:61`, while active binding specs exist in terminal config at `howl-linux-host/src/config/terminal.zig:140-146` and tab-bar config at `howl-linux-host/src/config/tab_bar.zig:36-50`.
- `howl-linux-host/src/test/integration_entry.zig` is likely misnamed as integration coverage because it only imports host modules in `howl-linux-host/src/test/integration_entry.zig:1-8`.

## Over-Owned Files

- `howl-linux-host/src/terminal/context.zig` is the highest over-owned file. It crosses terminal aggregate state, PTY/VT/render ABI seams, host input policy, render upload, diagnostics, title, clipboard, cursor blink, link hover, and present completion. Evidence spans `howl-linux-host/src/terminal/context.zig:53-1591` and tests through `howl-linux-host/src/terminal/context.zig:1619-2386`.
- `howl-linux-host/src/window/term_texture.zig` over-owns render-surface resource contract validation and host GL realization. It duplicates or shadows resource-state reasoning that also exists in `howl-linux-host/src/terminal/render/retained.zig:197-406`.
- `howl-linux-host/src/main.zig` is a valid central event-loop owner but over-owns tab lifecycle, focus sync, paste, render snapshot creation, active-tab health, debug accounting bridges, and many tests. Evidence: `howl-linux-host/src/main.zig:74-88`, `howl-linux-host/src/main.zig:230-288`, `howl-linux-host/src/main.zig:798-895`, and `howl-linux-host/src/main.zig:905-1096`.
- `howl-linux-host/src/input/input.zig` over-owns SDL intake plus binding action generation, scroll pages, passive motion, terminal hover, link hover, and mouse motion enablement. Evidence: policy fields at `howl-linux-host/src/input/input.zig:76-105`, SDL processing at `howl-linux-host/src/input/input.zig:256-324`, key/mouse conversion at `howl-linux-host/src/input/input.zig:364-701`.
- `howl-linux-host/src/window/present.zig` over-owns present tokens, GL draw, tab-bar cache, diagnostics, and proof capture. Evidence: `howl-linux-host/src/window/present.zig:65-491`.

## Maintained Vs Stale Evidence

- Maintained: `howl-linux-host/src/main.zig` has targeted loop/present/input tests in `howl-linux-host/src/main.zig:668-1096`.
- Maintained: `howl-linux-host/src/input/input.zig` has SDL/modifier/ring/burst/redraw-owner-work tests in `howl-linux-host/src/input/input.zig:721-964`.
- Maintained: `howl-linux-host/src/window/pacing.zig` has frame permit, runtime wake, present completion, and deadline tests in `howl-linux-host/src/window/pacing.zig:153-330`.
- Maintained: `howl-linux-host/src/app/present.zig` has present reason/token/completion tests in `howl-linux-host/src/app/present.zig:96-469`.
- Maintained: `howl-linux-host/src/window/term_texture.zig` has many render-surface resource/shape/diagnostic tests from `howl-linux-host/src/window/term_texture.zig:942-1870`.
- Maintained: `howl-linux-host/src/terminal/context.zig` has targeted tests for surface layout, clipboard, cursor blink, render-surface diagnostics, input routing, render submit locking/failure, and present completion in `howl-linux-host/src/terminal/context.zig:1619-2386`.
- Maintained: `howl-linux-host/src/terminal/pty/pump.zig` has tests for progress outcome, reply drain, and transport pump bounds in `howl-linux-host/src/terminal/pty/pump.zig:314-656`.
- Maintained: `howl-linux-host/src/terminal/pty/wait_thread.zig` has wait/wake/ack/death tests in `howl-linux-host/src/terminal/pty/wait_thread.zig:122-251`.
- Maintained: `howl-linux-host/src/terminal/vt/surface.zig` has publish/hover/ack/reject tests in `howl-linux-host/src/terminal/vt/surface.zig:440-599`.
- Maintained: `howl-linux-host/src/config/env.zig` has direct and fuzz tests in `howl-linux-host/src/config/env.zig:17-64`.
- Maintained but structurally risky: `howl-linux-host/src/window/term_texture.zig` and `howl-linux-host/src/terminal/context.zig` have high test density, but their ownership is too broad.
- Small and clean: `howl-linux-host/src/input/mouse.zig`, `howl-linux-host/src/tab_bar/tab_bar.zig`, `howl-linux-host/src/tab_bar/slots.zig`, `howl-linux-host/src/terminal/cursor_blink.zig`, and `howl-linux-host/src/terminal/pty/retained.zig` are narrow owners with little or no structural ambiguity.
- Likely stale: `howl-linux-host/src/config/window.zig` binding loader scaffolding has empty specs in `howl-linux-host/src/config/window.zig:61-79`.
- Likely stale: `howl-linux-host/src/test/integration_entry.zig` is import-only at `howl-linux-host/src/test/integration_entry.zig:1-8`, despite integration test wiring in `howl-linux-host/build.zig:378-402`.
- Explicit non-goal rather than stale: `howl-linux-host/src/window/icon.zig` uses direct `@cImport` in `howl-linux-host/src/window/icon.zig:3-7`, and the design allows app icon loading as a direct `@cImport` exception in `howl-linux-host/design.md:43-44`.

## Top Structural Risks

1. `howl-linux-host/src/terminal/context.zig` is a god aggregate. It is the active ABI seam, runtime owner, input router, render uploader, diagnostics sink, clipboard adapter, and link/selection coordinator. This conflicts with TigerBeetle pressure toward precise ownership, centralized control flow, centralized state mutation, and strong naming shown in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:161-175` and `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273-317`.
2. Host render realization is split and partially duplicated between `howl-linux-host/src/window/term_texture.zig` and `howl-linux-host/src/terminal/render/retained.zig`. The ABI is the product, and duplicated render-surface validation/resource state risks divergent contract truth. Evidence: `howl-linux-host/src/window/term_texture.zig:199-269` versus `howl-linux-host/src/terminal/render/retained.zig:197-406`.
3. Main-loop admission/present/wake policy spans `howl-linux-host/src/main.zig`, `howl-linux-host/src/window/pacing.zig`, `howl-linux-host/src/app/present.zig`, `howl-linux-host/src/input/window.zig`, and `howl-linux-host/src/terminal/pty/wait_thread.zig`. The design requires centralized event-loop control and background threads that only wake owner thread in `howl-linux-host/design.md:57-65`; the current shape has the right intent but fragile distributed state transitions.
4. Runtime allocation remains normal desktop-host style, not TigerBeetle-static style. Evidence includes heap-created app objects in `howl-linux-host/src/main.zig:108-140`, font path allocations in `howl-linux-host/src/terminal/render/fonts_linux.zig:25-33`, title allocation in `howl-linux-host/src/window/window.zig:94-120`, and proof capture allocations in `howl-linux-host/src/window/present.zig:447-468`. This may be acceptable for a host, but it is a mismatch with `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:151-156` and `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222`.
5. Test gates are uneven. Unit tests are strong around many owners, but integration tests are import-only at `howl-linux-host/src/test/integration_entry.zig:1-8`, and `howl-linux-host/build.zig:378-402` wires them as the integration step. This can create false confidence for host-wide lifecycle, SDL/GL/present, and PTY/VT/render ABI interactions.

## Proof Gaps

- The inventory did not compute function lengths or assertion density. Any planning that touches `src/terminal/context.zig`, `src/window/term_texture.zig`, `src/main.zig`, or `src/input/input.zig` should first quantify function length and assertion density against TigerBeetle style.
- The inventory did not run tests or builds. Maintained-versus-stale judgment is based on source and test presence, not current test pass/fail status.
- The inventory did not inspect runtime logs such as `howl-runtime.jsonl` or stress artifacts. Runtime risks are inferred from source ownership, not observed runtime failures.
- The inventory did not inspect `assets/default_config/init.lua`. Config owner findings are based on Zig loaders, not config file schema usage.
- The inventory did not inspect external ABI headers directly. ABI-boundary findings are based on host build wiring and translated module usage, not header contract audit.
- The inventory did not compare against Ghostty or Alacritty host references. This cache is a host-internal ownership inventory constrained by TigerBeetle reference facts only.
- The inventory did not determine whether desktop-host dynamic allocation is accepted policy or debt. This remains a readiness constraint because repository law names TigerBeetle as a hard gate while host design is desktop/SDL/OpenGL.
- The inventory did not prove that duplicated render-surface validation in `src/window/term_texture.zig` and `src/terminal/render/retained.zig` is semantically divergent. It only proves duplicated ownership pressure and contract-risk shape.
- The inventory did not propose implementation slices. Any planning step should convert one proof gap or risk into one accountable source-backed slice.

## Readiness Judgment

Ready for planning with constraints.

The cache is ready to support a planning pass for host ownership cleanup because it contains a source-backed owner map, identifies stale/misnamed owners, identifies over-owned files, separates maintained from stale evidence, and records top structural risks with exact line references.

Planning should not start by changing code. The first planning constraint is to choose exactly one risk or proof gap and sharpen it into a bounded slice. The highest-confidence planning entry points are `src/terminal/context.zig` ownership split research, render-surface validation ownership between `src/window/term_texture.zig` and `src/terminal/render/retained.zig`, or the import-only integration-test gap.
