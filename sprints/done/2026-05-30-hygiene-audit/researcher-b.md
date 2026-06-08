# Howl Hygiene Audit Researcher B

Date: 2026-05-30

## Scope

Host down through PTY, VT, and render. Focus: C ABI lane shape, file/folder/symbol convention, cohesion, simplicity, and in-file organization. This is research only. No product code was edited.

## Sources Read

- TigerBeetle style: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:360`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:367`.
- TigerBeetle architecture: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:168`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:408`.
- Howl law and memory: `AGENTS.md:9`, `AGENTS.md:86`, `AGENTS.md:95`, `AGENTS.md:105`, `AGENTS.md:128`, `loop.txt:40`, `project-memory.md:15`, `project-memory.md:127`, `libs.yaml:4`, `libs.yaml:121`, `libs.yaml:138`, `libs.yaml:215`.
- Ghostty reference: `utils/dev_references/terminals/ghostty/src/terminal/main.zig:1`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:77`, `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:45`, `utils/dev_references/terminals/ghostty/src/terminal/c/types.zig:1`, `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:30`, `utils/dev_references/terminals/ghostty/include/ghostty/vt/terminal.h:42`, `utils/dev_references/terminals/ghostty/src/terminal/c/terminal.zig:30`.
- Alacritty reference: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:29`, `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:83`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47`, `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:23`.

## Severity Findings

### Critical

#### C ABI lane is not factory-polished across libraries

Symptom: The three ABI roots use different lane shapes. PTY and VT roots export from one `ffi` owner, while render root exports from several root-level wrapper files. Headers also use inconsistent sectioning and declaration order.

Evidence:

- `howl-pty/src/libhowl_pty.zig:1` imports only `ffi.zig`; `howl-pty/src/libhowl_pty.zig:3` opens the export block; `howl-pty/src/libhowl_pty.zig:4` to `howl-pty/src/libhowl_pty.zig:18` export all PTY symbols from `ffi`.
- `howl-vt/src/libhowl_vt.zig:1` imports only `ffi.zig`; `howl-vt/src/libhowl_vt.zig:3` opens the export block; `howl-vt/src/libhowl_vt.zig:4` to `howl-vt/src/libhowl_vt.zig:31` export all VT symbols from `ffi`.
- `howl-render/src/libhowl_render.zig:1` to `howl-render/src/libhowl_render.zig:7` import seven separate root-level boundary files; `howl-render/src/libhowl_render.zig:10` to `howl-render/src/libhowl_render.zig:36` export symbols from mixed boundary files.
- `howl-render/src/ffi.zig:1` to `howl-render/src/ffi.zig:3` only performs `@cImport`; actual render C translation lives in files such as `howl-render/src/vt_surface.zig:13`, `howl-render/src/text_session.zig:8`, `howl-render/src/submission.zig:8`, and `howl-render/src/prepared_surface.zig:8`.
- `howl-vt/include/howl_vt.h:83` to `howl-vt/include/howl_vt.h:85` use large numbered banner sections; `howl-vt/include/howl_vt.h:247` to `howl-vt/include/howl_vt.h:304` continue the numbered section scheme.
- `howl-render/include/howl_render.h:376` to `howl-render/include/howl_render.h:405` are a long ungrouped function list except for one comment at `howl-render/include/howl_render.h:398`.

Why it violates pressure: Howl law says ABIs are the product at `AGENTS.md:9`, FFI translates contracts only at `AGENTS.md:110`, and public roots curate exports only at `AGENTS.md:107`. Ghostty's C lane is explicit and mechanically traceable: C API functions are re-exported through `src/terminal/c/main.zig` (`utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:45`) and C struct layout metadata is generated in one C API metadata owner (`utils/dev_references/terminals/ghostty/src/terminal/c/types.zig:1`). Ghostty is broader than Howl wants, but it still shows one auditable C lane. Howl render currently makes the user infer why `ffi.zig` is only an import shim while the ABI translators are scattered at root.

Proposed owner-true shape: Each C ABI library should have one tiny export root and one obvious C lane. Prefer `libhowl_*.zig` as export table only, `ffi.zig` as C contract translation only, and owner files below true owner folders for domain state. Render should not keep root-level ABI files that look like owners (`vt_surface.zig`, `text_session.zig`, `prepare_request.zig`, `submission.zig`, `prepared_surface.zig`) when their job is C translation.

Candidate slice boundary: Render ABI lane normalization only. Move render C translators under a single explicit C boundary namespace or fold them into `ffi.zig` with helper files named by ABI group, then update `libhowl_render.zig` imports. Do not change C symbols or behavior in this slice.

Tests/gates/grep gates: `zig build check`, `zig build test`, `git diff --check`; grep gate that `howl-render/src/libhowl_render.zig` imports only the C boundary module(s), not state owners; grep gate that root `howl-render/src/{vt_surface,text_session,prepare_request,submission,prepared_surface}.zig` no longer exist unless accepted as explicit boundary files.

Risks: Moving only files can create fake cleanliness if ABI translation still mutates owner state directly without enough validation. Require no behavior changes and line-by-line review of every exported symbol.

#### VT root and terminal owner are bucket-shaped and too broad

Symptom: VT exposes multiple namespace wrappers and central structs that aggregate far beyond a small owner. `Terminal` owns stream state, screen set, modes, kitty state, host state, charset state, dirty generation, surface snapshot cache, selection, resize, runtime placeholders, hyperlink lookup, and tests.

Evidence:

- `howl-vt/src/howl_vt.zig:1` to `howl-vt/src/howl_vt.zig:9` import broad modules, then `howl-vt/src/howl_vt.zig:11` to `howl-vt/src/howl_vt.zig:14` re-export selected large owners.
- `howl-vt/src/action.zig:6` to `howl-vt/src/action.zig:22` is a pure re-export wrapper across parser events, vocabulary, route, and ESC action.
- `howl-vt/src/input.zig:7` to `howl-vt/src/input.zig:93` is a large re-export list for keyboard, mouse, events, encoding, constants, and functions.
- `howl-vt/src/kitty.zig:1` to `howl-vt/src/kitty.zig:11` is another wrapper mixing kitty key, pointer, color, state, protocol, and apply.
- `howl-vt/src/terminal.zig:24` to `howl-vt/src/terminal.zig:42` stores allocator, stream, screen, modes, kitty, host, GL charset state, dirty generation, and surface snapshot state in one struct.
- `howl-vt/src/terminal.zig:57` to `howl-vt/src/terminal.zig:113` has four initialization entry points and constructs stream/screen/host state.
- `howl-vt/src/terminal.zig:128` to `howl-vt/src/terminal.zig:147` owns feed, post-apply dirty/selection invalidation, and resize.
- `howl-vt/src/terminal.zig:165` to `howl-vt/src/terminal.zig:193` owns surface ack/snapshot/visible metadata.
- `howl-vt/src/terminal.zig:195` to `howl-vt/src/terminal.zig:208` contains runtime obligation/progress stubs.
- `howl-vt/src/terminal.zig:210` to `howl-vt/src/terminal.zig:248` owns hyperlink lookup and selection mutation.

Why it violates pressure: Howl law says `howl-vt` owns parser state, terminal state, selection, input encoding, host-facing protocol consequences, and VT-surface truth at `AGENTS.md:98`, but owner rules require owner files to own state and mutation, not bucket wrappers (`AGENTS.md:107` to `AGENTS.md:116`). TigerBeetle demands great names and top-down order (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`). Ghostty's terminal root is broad because it is a Zig module lane (`utils/dev_references/terminals/ghostty/src/terminal/main.zig:8` to `utils/dev_references/terminals/ghostty/src/terminal/main.zig:78`), but Howl law explicitly rejects host integration through Zig-module shape at `AGENTS.md:91`. Alacritty keeps terminal core modules explicit (`utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7` to `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:16`) and `term` owns terminal API with submodules for cell/color/search (`utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:29` to `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:31`).

Proposed owner-true shape: Treat `Terminal` as a composition root only after moving snapshot publication, runtime obligation, selection mutation, host consequence storage, and stream lifecycle into smallest owners. Public roots should export only the C ABI and tests; internal Zig re-export wrappers should be deleted unless a concrete internal caller proves they reduce coupling.

Candidate slice boundary: VT surface publication extraction. Move `surface_snapshot_*` fields and `ackSurface`, `surfaceSnapshot`, `visibleMeta`, `noteSurfacePublication` from `howl-vt/src/terminal.zig` into a true `surface/publication.zig` owner or existing `screen_set` owner if that is the real owner after proof. Keep C ABI unchanged.

Tests/gates/grep gates: `zig build test`; grep gate that `surface_snapshot_` no longer appears in `howl-vt/src/terminal.zig`; tests for ack idempotence, dirty row clearing, scrollback snapshot change, alternate-screen snapshot change, and invalid snapshot zero.

Risks: A broad VT redo can easily become architecture invention. Promote only one owner seam at a time and require a reference-backed owner decision for each extracted state group.

### High

#### Dynamic allocation is pervasive in VT consequence paths without a clear capacity plan

Symptom: VT host consequence state uses dynamically growing `ArrayList` and `dupe` during protocol application. Bounds exist in places, but allocation shape is still runtime and scattered.

Evidence:

- `howl-vt/src/host/state.zig:33` to `howl-vt/src/host/state.zig:38` define byte/count limits for pending output, retained payloads, title, and hyperlinks.
- `howl-vt/src/host/state.zig:51` to `howl-vt/src/host/state.zig:54` store `pending_output`, `hyperlink_targets`, clipboard, and title as dynamic allocations.
- `howl-vt/src/host/state.zig:89` to `howl-vt/src/host/state.zig:91` bounds pending output then appends to an `ArrayList`.
- `howl-vt/src/host/state.zig:94` to `howl-vt/src/host/state.zig:99` duplicates retained strings.
- `howl-vt/src/host/state.zig:116` to `howl-vt/src/host/state.zig:127` interns hyperlinks with a linear search, count bound, `dupe`, and append.
- `howl-vt/src/parser/events.zig:55` defines `max_queued_events`, while `howl-vt/src/parser/events.zig:57` to `howl-vt/src/parser/events.zig:68` still store several dynamic `ArrayList` buffers.

Why it violates pressure: TigerBeetle requires putting a limit on everything (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96`) and no dynamic allocation after initialization as a forcing function for explicit limits (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:151`; architecture rationale at `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189` to `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:222`). Howl is not TigerBeetle's database, but Howl law makes TigerBeetle a hard gate at `AGENTS.md:26` to `AGENTS.md:33`. The current state has some bounds but no single capacity story that a reviewer can audit top-down.

Proposed owner-true shape: Keep protocol consequence ownership in VT, but make capacities explicit at terminal initialization or a dedicated host-consequence owner. Convert append/retain paths to bounded retained buffers where feasible, or record why dynamic allocation is acceptable for each ABI-visible consequence.

Candidate slice boundary: Host consequence capacity plan only. No implementation. Produce a scratchpad that inventories every `ArrayList`/`dupe` in `howl-vt/src/host`, `howl-vt/src/parser/events.zig`, and control report paths, then promotes one bounded storage owner.

Tests/gates/grep gates: grep `std.ArrayList`, `dupe`, `alloc` in `howl-vt/src/host`, `howl-vt/src/parser/events.zig`, and `howl-vt/src/control`; tests for exact boundary at `pending_output_max_bytes`, hyperlink count 4096, retained metadata max, and rollback on short/error paths.

Risks: Overzealous static allocation can bloat memory or block needed terminal features. The immediate risk is less runtime behavior than lack of an auditable limit/ownership story.

#### Host `Context` is still a large terminal/session aggregate with many policies

Symptom: Host `Context` is the per-terminal aggregate, but it still owns too much policy directly: PTY/VT/render handles, title, geometry, font size, focus, scrollbar, links, selection, hover publish, cursor blink, render turns, present completion, runtime thread startup, and clipboard writes.

Evidence:

- `howl-linux-host/src/terminal/context.zig:1` to `howl-linux-host/src/terminal/context.zig:32` import PTY, VT, render, window, input, layout, selection, links, scrollbar, font, and config modules.
- `howl-linux-host/src/terminal/context.zig:89` to `howl-linux-host/src/terminal/context.zig:109` store terminal handles plus progress, texture, config, input, title, geometry, focus, scrollbar, links, selection, hover, and cursor blink fields.
- `howl-linux-host/src/terminal/context.zig:327` to `howl-linux-host/src/terminal/context.zig:340` own cursor blink cadence.
- `howl-linux-host/src/terminal/context.zig:343` to `howl-linux-host/src/terminal/context.zig:354` query VT runtime obligations.
- `howl-linux-host/src/terminal/context.zig:356` to `howl-linux-host/src/terminal/context.zig:368` drive PTY progress, link hover clearing, VT source publication, cursor blink reset, clipboard writes, and wake acknowledgement.
- `howl-linux-host/src/terminal/context.zig:371` to `howl-linux-host/src/terminal/context.zig:394` own render turn sequencing.
- `howl-linux-host/src/terminal/context.zig:417` to `howl-linux-host/src/terminal/context.zig:456` initialize terminal state and spawn the runtime/progress thread.

Why it violates pressure: The accepted host direction says top-level app/event processor owns event-loop dispatch and per-terminal context owns one embedded terminal widget/session (`project-memory.md:94` to `project-memory.md:105`), so the existence of a broad `Context` is not automatically wrong. The violation is that the file still centralizes too many leaf policies, while TigerBeetle says centralize control/state mutation but push helpers into true owners (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:168` to `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:175`). Alacritty separates event processor state (`utils/dev_references/terminals/alacritty/alacritty/src/event.rs:83` to `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:101`) from one-window context (`utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47` to `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:70`) and display subsystem (`utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:1` to `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:2`).

Proposed owner-true shape: Keep `Context` as composition root, but move cursor blink cadence, clipboard drain policy, runtime obligation adaptation, and render-turn sequencing into small owner files if they have stable invariants and tests. Do not create managers/controllers.

Candidate slice boundary: Cursor blink owner extraction only. Move fields and functions at `howl-linux-host/src/terminal/context.zig:108` to `howl-linux-host/src/terminal/context.zig:109` and `howl-linux-host/src/terminal/context.zig:327` to `howl-linux-host/src/terminal/context.zig:340` into `terminal/cursor_blink.zig` or an existing true owner if present.

Tests/gates/grep gates: Existing cursor blink tests plus grep that `cursor_blink_deadline_ns` appears only in the owner and `Context` field composition. Root `zig build test`.

Risks: Too much extraction can turn `Context` into an anemic pass-through. Only extract state with a crisp invariant and keep main-thread sequencing centralized.

### Medium

#### Render has duplicate and stale taxonomy signals

Symptom: Render's source tree has both accepted owner folders and root-level files with overlapping names. Memory says accepted direction includes source/session/prepared/render owners, while `libs.yaml` still lists a `surface` bucket and root wrapper files exist.

Evidence:

- `project-memory.md:168` to `project-memory.md:182` says accepted render facts include `source/*`, `prepared/*`, `session/*`, and `render/*`, and says `surface` is a product term at the ABI boundary, not an umbrella source folder.
- `libs.yaml:247` to `libs.yaml:256` still lists `howl-render/src/surface/*` owners: buffer, prepared_owner, publication_source, clip_rect, geometry, input, rgba, tokens.
- `howl-render/src/libhowl_render.zig:1` to `howl-render/src/libhowl_render.zig:7` import root `prepare_request.zig`, `prepared_surface.zig`, `submission.zig`, `surface_geometry.zig`, `text_session.zig`, `vt_surface.zig`, and `work_state.zig`.
- `howl-render/src/session/text.zig:2` to `howl-render/src/session/text.zig:20` imports `surface/*`, `source/*`, `prepared/*`, `render/*`, and `text/*` owners, then `howl-render/src/session/text.zig:340` to `howl-render/src/session/text.zig:359` composes geometry, source slot, prepare requests, submitted, handles, fonts, and retained pixels.
- `howl-render/src/text/pipeline.zig:1` starts with a blank line, then `howl-render/src/text/pipeline.zig:5` to `howl-render/src/text/pipeline.zig:18` defines pipeline vocabulary. The file name itself conflicts with Howl memory banning `pipeline` vocabulary at `project-memory.md:29` to `project-memory.md:31`.

Why it violates pressure: Owner rules ban `pipeline` and broad buckets in project memory (`project-memory.md:29` to `project-memory.md:31`) and accepted render direction says no broad `surface` bucket (`project-memory.md:184` to `project-memory.md:192`). TigerBeetle says names must capture exact nouns and verbs (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273` to `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:289`). A reader cannot tell whether `surface` is product ABI vocabulary, a source folder, a prepared output folder, or retained owner vocabulary.

Proposed owner-true shape: Update memory or source, but do not let both stand. If `surface/*` remains true, document why. Otherwise migrate `surface/tokens.zig`, `surface/geometry.zig`, `surface/input.zig`, and `surface/prepared_owner.zig` toward source/prepared/render/session owners. Rename `text/pipeline.zig` to an exact owner noun after inventorying its symbols.

Candidate slice boundary: Render taxonomy inventory and `libs.yaml` correction only, or one source-backed rename such as `text/pipeline.zig` after proving the target owner name.

Tests/gates/grep gates: grep `pipeline`, `surface/` in render source and `libs.yaml`; `zig build check`; no ABI symbol change unless explicitly promoted.

Risks: Renames without ownership movement are cosmetic. Conversely, broad folder movement risks breaking render work in flight. Start with the C lane or one stale name.

#### In-file organization often hides invariants instead of engraving them

Symptom: Several files use field buckets and long translator/helper runs where assertions are sparse or too far from mutation. Some comments are useful, but there is no visible convention for order beyond local habit.

Evidence:

- `howl-vt/src/screen.zig:24` to `howl-vt/src/screen.zig:89` defines a very large `Screen` field list with cursor, modes, margins, history, current attrs, dirty rows, tabs, and cell pixel size.
- `howl-vt/src/screen.zig:99` to `howl-vt/src/screen.zig:140` initializes most of those fields manually for cursor-only state; `howl-vt/src/screen.zig:148` to `howl-vt/src/screen.zig:208` repeats much of the shape for cell-backed state.
- `howl-render/src/vt_surface.zig:136` to `howl-render/src/vt_surface.zig:197` has a strong layout assertion block, but earlier ABI functions return aggregate failure literals repeatedly at `howl-render/src/vt_surface.zig:32`, `howl-render/src/vt_surface.zig:35`, `howl-render/src/vt_surface.zig:47`, `howl-render/src/vt_surface.zig:56`, and `howl-render/src/vt_surface.zig:57`.
- `howl-vt/src/control/report.zig:194` to `howl-vt/src/control/report.zig:316` is a long sequence of report append helpers with repeated allocator/output/encode arguments.
- `howl-render/src/text/frame_preparer.zig:41` to `howl-render/src/text/frame_preparer.zig:53` defines a broad owner with atlas, shaper, rasterizer, glyph lookup, raster op, and multiple scratches, while `howl-render/src/text/frame_preparer.zig:54` to `howl-render/src/text/frame_preparer.zig:74` offers three init paths.

Why it violates pressure: TigerBeetle says assertion density should average at least two assertions per function and arguments/pre/postconditions should be asserted (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:109` to `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:113`), variables should stay in smallest scope (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158`), and file order should be important things first (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`). Repeated literals and long field lists are review friction, not proof.

Proposed owner-true shape: Establish a Howl in-file convention: imports, constants with compile-time assertions, public owner type fields, nested simple types, public methods in lifecycle/control/data order, private helpers adjacent to their caller unless reused, tests last. No bannered sections in Zig files. Use comments only for why/protocol facts; use assertions for critical invariants.

Candidate slice boundary: Document convention in scratchpad first, then apply to one file with tests: `howl-render/src/vt_surface.zig` is a good candidate because behavior can remain identical while failure result helpers and layout assertions become a clear ABI translator convention.

Tests/gates/grep gates: `zig fmt`, `git diff --check`, grep for repeated `HowlRenderVtSurfacePublishResult` failure literals after helper extraction, existing render ABI tests.

Risks: A style-only rewrite can obscure behavior changes. Require before/after ABI tests and no public symbol movement in the same slice.

### Low

#### Header banner sections help scanning but hurt factory-generated feel

Symptom: VT header uses numbered banners that look hand-curated. PTY header is compact and direct. Render header is long and mostly unsectioned. None looks like one consistent generated ABI lane.

Evidence:

- `howl-pty/include/howl_pty.h:11` to `howl-pty/include/howl_pty.h:24` define handle/status/session status directly, and `howl-pty/include/howl_pty.h:95` to `howl-pty/include/howl_pty.h:118` declare functions directly.
- `howl-vt/include/howl_vt.h:14` labels shell input enums; `howl-vt/include/howl_vt.h:83` to `howl-vt/include/howl_vt.h:85` start numbered banners; `howl-vt/include/howl_vt.h:295` to `howl-vt/include/howl_vt.h:304` continue numbered banners.
- `howl-render/include/howl_render.h:17` defines the fallback font macro, `howl-render/include/howl_render.h:19` to `howl-render/include/howl_render.h:52` defines status enums, `howl-render/include/howl_render.h:54` to `howl-render/include/howl_render.h:374` defines many structs, and `howl-render/include/howl_render.h:376` to `howl-render/include/howl_render.h:405` declares functions.

Why it violates pressure: Ghostty's local C API guide says `include/ghostty/vt.h` contents are sorted by macros, forward declarations, types, functions, as quoted in `utils/dev_references/terminals/ghostty/src/terminal/c/AGENTS.md` read during reference traversal; the visible umbrella header also groups public API references rather than giant numbered inline regions (`utils/dev_references/terminals/ghostty/include/ghostty/vt.h:30` to `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:45`). Howl wants one small intuitive C lane, not Ghostty's many-header lane, but the ordering principle applies.

Proposed owner-true shape: One Howl header convention for all three libraries: include guards, includes, extern C, macros/constants, opaque handles, enums, structs, functions. Use short semantic comments only where they explain contract ownership or lifetime. Avoid numbered banners unless generation emits them consistently.

Candidate slice boundary: Header format convention only, no ABI changes. Apply to VT header first because it has the most visible hand-sectioning.

Tests/gates/grep gates: compile C headers through existing Zig `@cImport` tests; grep no `/* ----` banners in Howl headers; ABI diff by symbol list if a tool exists.

Risks: Reordering header declarations can break C consumers only if dependencies are not respected. Howl is private with no downstream per `AGENTS.md:15`, but compile the host and tests.

## C ABI Lane Audit

PTY is closest to the desired lane: `howl-pty/src/libhowl_pty.zig:1` imports `ffi`, and the export table at `howl-pty/src/libhowl_pty.zig:4` to `howl-pty/src/libhowl_pty.zig:18` is small and obvious. `howl-pty/src/ffi.zig:55` to `howl-pty/src/ffi.zig:76` translates handles and byte spans; `howl-pty/src/ffi.zig:151` to `howl-pty/src/ffi.zig:178` owns session init translation and allocation.

VT is consistent at the root but too large behind it: `howl-vt/src/libhowl_vt.zig:4` to `howl-vt/src/libhowl_vt.zig:31` exports only `ffi`, but `howl-vt/src/ffi.zig:1` to `howl-vt/src/ffi.zig:7` imports screen, input, selection, host state, screen set, and terminal, and `howl-vt/src/ffi.zig:21` to `howl-vt/src/ffi.zig:225` defines many C structs. That may be acceptable for one C lane, but it needs stronger ordering and layout proof.

Render is not yet factory-clean: `howl-render/src/ffi.zig:1` to `howl-render/src/ffi.zig:3` is only `@cImport`, while translators are root files. `howl-render/src/vt_surface.zig:136` to `howl-render/src/vt_surface.zig:206` is good ABI-layout proof, but it sits in a root file named like a domain owner rather than an FFI translator.

Ghostty pressure: Ghostty uses a Zig module lane at `utils/dev_references/terminals/ghostty/src/terminal/main.zig:8` to `utils/dev_references/terminals/ghostty/src/terminal/main.zig:78` and a separate C API lane at `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:45` to `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:90`. Howl should not copy the broad Zig lane, but should copy the C lane auditability.

## File And Symbol Convention Audit

Bad or suspicious vocabulary in current source:

- `howl-render/src/text/pipeline.zig:5` to `howl-render/src/text/pipeline.zig:18` uses pipeline as a type-owner namespace despite project memory banning `pipeline` as owner vocabulary at `project-memory.md:29` to `project-memory.md:31`.
- `howl-render/src/session/text.zig:17` imports `text/pipeline.zig` as `text_pipeline`, spreading that vocabulary into session owner code.
- `howl-render/src/text/frame_preparer.zig:6` imports `pipeline.zig` as `pipeline`, and `howl-render/src/text/frame_preparer.zig:41` defines `TextFramePreparer` over counters, atlas, shaper, rasterizer, lookup, raster op, and scratches. The name is serviceable but the owner breadth needs proof.
- `howl-vt/src/input.zig:7` to `howl-vt/src/input.zig:93` is an internal namespace wrapper. If hosts only consume `howl-vt/include/howl_vt.h`, this wrapper needs an internal caller justification or deletion.
- `howl-vt/src/action.zig:6` to `howl-vt/src/action.zig:22` is another namespace wrapper. It may be tolerable as an aggregate owner only if it never owns mutation, but it currently hides the true action route/vocabulary split.

Good convention worth preserving:

- PTY root export table in `howl-pty/src/libhowl_pty.zig:3` to `howl-pty/src/libhowl_pty.zig:19` is direct.
- Render source cell layout assertions in `howl-render/src/vt_surface.zig:136` to `howl-render/src/vt_surface.zig:206` are the right pressure for ABI layout.
- VT bounds in `howl-vt/src/host/state.zig:33` to `howl-vt/src/host/state.zig:38` are explicit, even though storage ownership still needs redesign.

## In-File Organization Convention

Recommended convention:

- Imports first, grouped by standard library, C/ABI, local owners. No blank first line; `howl-render/src/text/pipeline.zig:1` violates this trivially.
- Constants next, with compile-time assertions immediately after constants. Example to preserve: `howl-render/src/session/text.zig:22` to `howl-render/src/session/text.zig:43` defines capacities and asserts `max_font_faces`.
- Owner type fields before nested types and methods, matching TigerBeetle field/types/method order at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315` to `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:332`.
- Lifecycle methods before mutation methods, then query methods, then private helpers adjacent to their single caller unless reused.
- Tests last. Avoid giant test imports in production roots except package test aggregators; `howl-vt/src/howl_vt.zig:16` to `howl-vt/src/howl_vt.zig:34` is acceptable only as a test aggregator, not a product root pattern.
- No bannered sections in Zig files. For C headers, use semantic order over numbered banners.
- Use assertions for invariant proof. Comments explain why/protocol facts, per TigerBeetle comment guidance at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:360` to `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:370`.

Banner verdict: Header banners can help a human scan a hand-written file, but they hurt the factory-generated feel unless every header uses the same emitted order. Zig banner sections would be worse; they hide owner boundaries inside files instead of forcing smaller files.

## Top 5 First Slices

1. Render C ABI lane normalization. Highest leverage because ABIs are the product and render currently has the messiest root lane. Scope: `howl-render/src/libhowl_render.zig`, render C translator files, no ABI behavior changes.
2. VT surface publication owner extraction. Scope: `howl-vt/src/terminal.zig` surface snapshot fields/methods only, C ABI unchanged, tests around ack/snapshot/dirty semantics.
3. Header convention pass for `howl-vt/include/howl_vt.h`. Scope: reorder/clean comments only, no symbol/type changes, compile gates.
4. Render taxonomy inventory and stale vocabulary decision. Scope: `libs.yaml`, `project-memory.md` follow-up scratchpad, and proof for `surface/*`/`pipeline.zig`; no product code unless a single rename is promoted.
5. Host cursor blink owner extraction. Scope: `howl-linux-host/src/terminal/context.zig` cursor blink state/functions only, keep main loop sequencing unchanged.

## Non-Goals

- No implementation in this report.
- No commit.
- No C ABI symbol renames in the first hygiene slices unless a separate ABI vocabulary slice is promoted.
- No copying Ghostty's broad Zig module lane into Howl.
- No new manager/controller/engine/runtime/pipeline owners.
- No broad VT near-redo without promoted child slices.

## Open Questions

- Should Howl headers be hand-maintained with strict ordering, or generated from Zig ABI metadata? Ghostty has generated C struct layout metadata at `utils/dev_references/terminals/ghostty/src/terminal/c/types.zig:1` to `utils/dev_references/terminals/ghostty/src/terminal/c/types.zig:6`; Howl currently relies on compile-time assertions such as `howl-render/src/vt_surface.zig:136` to `howl-render/src/vt_surface.zig:206`.
- Is `howl-vt/src/howl_vt.zig` intended as an internal Zig package root or only a test aggregator? If hosts must not use Zig-module shape per `AGENTS.md:91`, internal users need to justify every re-export.
- Is `howl-render/src/surface/*` still accepted source shape despite `project-memory.md:182` saying `surface` is an ABI product term, or is `libs.yaml:247` to `libs.yaml:256` stale?
- What is the accepted memory-allocation policy for terminal host consequences? TigerBeetle says no dynamic allocation after init, but Howl currently allocates in VT consequence paths such as `howl-vt/src/host/state.zig:94` to `howl-vt/src/host/state.zig:127`.
- Should VT runtime obligation symbols remain if they are placeholders at `howl-vt/src/terminal.zig:195` to `howl-vt/src/terminal.zig:208`, or should they be removed until a real VT-owned runtime obligation exists?
