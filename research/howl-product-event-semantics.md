# Howl Product Event Semantics

Status: active research report for review.

Orchestrator session id: `orch-2026-06-19-product-event-semantics-01`.
Researcher session id: `research-2026-06-19-product-event-semantics-01`.
Reviewer id: open.
Commit-hash receipt status: open. This is a documentation-only planning package until the reviewer accepts it and the orchestrator closes the receipt.

## Sources Read

Required reads, in order:

1. `loop/flow.md:1-151`
2. `loop/researcher.md:1-89`
3. `sprints/current.txt:1-64`
4. `loops/howl-product-event-semantics-loop.txt:1-27`
5. Prior active research file `research/howl-product-event-semantics.md:1-59`, replaced by this report.
6. `reference-index.md:1-273`
7. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:1-511`
8. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:1-710`

Current Howl sources read:

- Root build aggregation: `build.zig:1-88`.
- Host dependency and C-ABI harness wiring: `howl-linux-host/build.zig:1-180`, `howl-linux-host/build.zig.zon:1-29`.
- Renderer build/ABI wiring: `howl-render/build.zig:1-180`, `howl-render/include/howl_render.h:1-340`, `howl-render/src/libhowl_render.zig:1-118`.
- Renderer owner seams: `howl-render/src/event.zig:1-110`, `howl-render/src/surface/pending_prepared_surface.zig:1-206`, `howl-render/src/submitted_surface.zig:1-126`.
- Host retained-render seams: `howl-linux-host/src/terminal/render_retained.zig:1-260`, `howl-linux-host/src/terminal/surface.zig:380-639`, `howl-linux-host/src/render_session.zig:1-120`, `howl-linux-host/src/render_session.zig:780-879`.
- Host PTY/VT/runtime seams: `howl-linux-host/src/terminal/pty_pump.zig:1-140`, `howl-linux-host/src/terminal/pty_pump.zig:280-469`, `howl-linux-host/src/terminal/pty_wait_thread.zig:1-160`, `howl-linux-host/src/terminal/vt_surface.zig:1-110`, `howl-linux-host/src/terminal/fonts.zig:130-199`.
- Host event/presentation tests: `howl-linux-host/src/event.zig:730-832`, `howl-linux-host/src/display/present.zig:80-139`, `howl-linux-host/src/terminal/surface_test.zig:880-959`.
- Benchmark and simulation-only sources: `howl-render/src/benchmark_main.zig:50-129`, `howl-render/src/benchmark_main.zig:280-359`, `howl-render/src/benchmark_main.zig:670-879`, `howl-render/src/benchmark_main.zig:950-979`, `howl-vt/benchmark/terminal_benchmark.zig:430-539`, `howl-vt/simulation/main.zig:1-40`, `howl-vt/simulation/scrollback.zig:1-40`, `utils/tools/rain-bench/README.md:1-106`, root `build.zig:61-68`.
- Package ABI build wiring: `howl-vt/build.zig:1-133`, `howl-pty/build.zig:1-108`.

Reference sources read:

- Alacritty terminal events and PTY loop: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event.rs:14-110`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:23-177`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:206-280`.
- Alacritty host/window/presentation: `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:366-495`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:530-554`, `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs:104-268`, `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:475-490`.
- Alacritty display/renderer: `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:602-711`, `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:715-884`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:83-262`, `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:46-110`.
- Alacritty scheduler: `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs:1-110`.
- Ghostty VT/termio seam: `utils/dev_references/terminals/ghostty/src/termio/mailbox.zig:1-106`, `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:272-371`, `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:440-463`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:46-65`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:386-420`, `utils/dev_references/terminals/ghostty/src/terminal/c/main.zig:1-60`.

## Search Inventory

Search terms used across active product/test/build/header sources in root and nested repos: `work`, `Work`, `WORK`, `workload`, `Workload`, `WorkState`, `SessionWorkState`, `workState`, `realops`, `RealOps`, `real_ops`, `pending_work`, `work_pending`.

No active product/test/build/header hits were found for `realops`, `real_ops`, `pending_work`, or `work_pending`. No active `howl-pty` source hit was found for any requested term.

### Host Retained Render State

Files and line refs:

- `howl-linux-host/src/terminal/render_retained.zig:23-37`: `WorkState` carries `RetainedState` plus `animation_pending`; methods `inFlight()` and `needsRenderSurface()` collapse prepare, submit, present, and animation admission under "work".
- `howl-linux-host/src/terminal/render_retained.zig:167-170`: `workState(bootstrap_surface)` mutates retained state by admitting bootstrap prepare and present-in-flight before returning state.
- `howl-linux-host/src/terminal/surface.zig:404-407`: `wantsRenderTurn()` asks `workState().needsRenderSurface()`.
- `howl-linux-host/src/terminal/surface.zig:498-510`: `renderTurn()` takes `work_before = term.render.workState(bootstrap_surface)` and reports `state_before`/`state_after`.
- `howl-linux-host/src/terminal/surface.zig:585-590`: private host `Context.workState()` locks and forwards to retained render.
- `howl-linux-host/src/terminal/surface.zig:603-629`: `driveRenderLocked(self, work)` drains one render turn by switching over retained states `.idle`, `.present_in_flight`, `.submit_ready`, `.failed`, `.prepare_needed`.
- `howl-linux-host/src/terminal/surface_test.zig:907-923`: tests assert `workState(false).state` for present-in-flight and submit-ready.
- `howl-linux-host/src/terminal/surface_test.zig:1285`, `1383`, `1393`, `1404`, `1440`, `1457`, `1542`: additional tests use `workState(false)` for retained render state assertions.

Classification: retained render state, render prepare, render submit, present/presentation, runtime admission.

Finding: `WorkState` is a false bucket name. It is not arbitrary work. It is the host-side retained-render admission snapshot used to decide whether a render turn should prepare, submit, wait for present completion, or keep cursor animation alive. The method also mutates bootstrap/present truth, so `workState()` is not a pure query.

### Renderer Session Mirror

Files and line refs:

- `howl-linux-host/src/render_session.zig:31-36`: `SessionWorkState` exposes `source_pending`, `prepare_pending`, `submit_pending`, and `animation_pending`.
- `howl-linux-host/src/render_session.zig:830-840`: `TextSessionOwner.workState()` computes render source, prepare, submit, and animation pending booleans.
- `howl-linux-host/src/render_session.zig:782-791`: render-state ingestion creates `prepare_request` from VT source damage.
- `howl-linux-host/src/render_session.zig:794-805`: `takeSubmitHandle()` decides whether a prepared handle is idle, stale, needs full prepare, submit, or failed.
- `howl-linux-host/src/render_session.zig:808-819`: `submitPreparedHandle()` accepts a prepared handle and executes submit.

Classification: event creation, render prepare, render submit, retained render state.

Finding: this file is a host-local mirror or stale copied renderer session shape. The actual renderer repo exports C ABI calls `howl_render_text_prepare` and `howl_render_text_submit` but does not export `SessionWorkState` in `howl-render/include/howl_render.h:331-334`. If this host file remains live, the name must become an explicit render-session pending/admission snapshot, not `SessionWorkState`.

### Test Injection Platform Ops

Files and line refs:

- `howl-linux-host/src/terminal/pty_pump.zig:42-72`: `driveOnce()` delegates to `driveOnceWith(..., RealOps)`; `RealOps` wraps transport pump, outbound backlog, runtime progress, and alive checks.
- `howl-linux-host/src/terminal/pty_wait_thread.zig:26-28`, `84-101`: `progressThreadMain()` delegates to `RealOps`; the ops wake the event loop and wait for transport.
- `howl-linux-host/src/terminal/vt_surface.zig:27-56`: render-state capture delegates C ABI calls through `RealOps` for update/updateHover.
- `howl-linux-host/src/terminal/vt_surface.zig:58-78`: ack path uses `RealAckOps`, which is already more exact than `RealOps`.
- `howl-linux-host/src/terminal/fonts.zig:155-170`: font size setter delegates through `RealOps` to set font size under lock.

Classification: test injection/platform ops.

Finding: `RealOps` is not a product event term, but it is a vague test-injection owner. Each occurrence hides the concrete platform seam under a generic "real" namespace. `RealAckOps` in `vt_surface.zig:70-78` proves the better local pattern already exists.

### Runtime Admission And Transport Drain Tests

Files and line refs:

- `howl-linux-host/src/terminal/pty_pump.zig:22-53`: `Outcome.keep` means another PTY/runtime progress turn is needed; `should_redraw` means host wake/redraw consequence; transport and runtime are separate local structs at lines `28-40`.
- `howl-linux-host/src/terminal/pty_pump.zig:74-90`: runtime obligation is queried/progressed under terminal lock; render prepare is requested when VT runtime changes state.
- `howl-linux-host/src/terminal/pty_pump.zig:92-140`: bounded transport pump setup asserts byte/read limits.
- `howl-linux-host/src/terminal/pty_pump.zig:309-318`: test name "keeps work bounded" actually proves saturated transport slice requests another turn.
- `howl-linux-host/src/terminal/pty_pump.zig:340-349`: test name "runtime work" actually proves runtime state change requests redraw and another turn.
- `howl-linux-host/src/terminal/pty_pump.zig:443-459`: test name "caps locked feed work" actually proves locked feed byte cap.
- `howl-linux-host/src/terminal/pty_wait_thread.zig:38-48`: progress thread drains `keep` turns before waiting again.
- `howl-linux-host/src/terminal/pty_wait_thread.zig:113-128`: test name "drains kept work" actually proves kept progress turns are drained before waiting.

Classification: runtime admission, transport drain, event publication, event drain.

Finding: The code already has better names (`TransportProgress`, `RuntimeProgress`, `Outcome.keep`, `should_redraw`). The remaining `work` term is in test names and should become `turn`, `progress`, `transport slice`, or `runtime obligation` depending on the test.

### Host Presentation Tests And Facts

Files and line refs:

- `howl-linux-host/src/event.zig:730-745`: `LoopRuntimeFacts.render_work_pending` is used as an event-loop wait/present input.
- `howl-linux-host/src/event.zig:75-81`, `212-233`, `665-707`: `LoopWaitIntent.frame_work_pending` is the frame/present wait fact; it combines requested redraw and render-turn pending state, and controls whether the loop may wait for window events.
- `howl-linux-host/src/event.zig:771-798`: test "blocked frame work waits until frame deadline" proves render pending participates in frame deadline admission.
- `howl-linux-host/src/event.zig:800-828`: blocked frame still drives runtime progress when `render_work_pending` is true.
- `howl-linux-host/src/event.zig:830-832`: test "present work" maps latched host redraw to present reason.
- `howl-linux-host/src/display/present.zig:80-97`: terminal frame submission immediately notes present submitted and completes present; terminal retire path has no submitted present token.
- `howl-linux-host/src/display/present.zig:114-129`: test "visual present work" proves present submission count and token creation.

Classification: runtime admission, present/presentation, completion/acknowledgement.

Finding: `render_work_pending` is a host event-loop fact, not a retained renderer state. It should become `render_turn_pending` because current call site `surface.zig:465-472` sets it from `wantsRenderTurn()`. `frame_work_pending` is a visual/frame wait fact, not retained render state; it should become `visual_present_pending` because it combines requested redraw and render-turn pending state to decide whether presentation has a reason to run before blocking.

### Benchmark Fixture And Load Case Terms

Files and line refs:

- `howl-render/src/benchmark_main.zig:50-55`: former `WorkloadResult.dirtyCellsPerSecond()` was render benchmark output and must use benchmark-case vocabulary.
- `howl-render/src/benchmark_main.zig:58-78`: former `WorkloadDamage`, `Workload`, and `WorkloadPrepareContext` were render benchmark fixture/load-case structs and must use benchmark-case vocabulary.
- `howl-render/src/benchmark_main.zig:288-357`: former `buildWorkload` and concrete workload builders created render benchmark cases and must use benchmark-case vocabulary.
- `howl-render/src/benchmark_main.zig:681-715`: the former workload fixture conversion into prepare context/prepared surface must use benchmark-case vocabulary.
- `howl-render/src/benchmark_main.zig:738-859`: former `runWorkloadCold`, `runWorkloadWarm`, `runWorkloadResult`, `runWorkload` executed render benchmark cases and must use benchmark-case vocabulary.
- `howl-render/src/benchmark_main.zig:891`, `916`, `957-973`: printed text/NDJSON formerly used `workload` and must use `benchmark_case`.
- `howl-vt/benchmark/terminal_benchmark.zig:443-469`: replay workload name derives from fixture basename.
- `howl-vt/benchmark/terminal_benchmark.zig:501-534`: benchmark output includes `workload` field.
- `howl-vt/simulation/main.zig:5-6`: proof comment says deterministic VT simulation workloads; this is a simulation/load-case term, not product event semantics.
- `howl-vt/simulation/scrollback.zig:4-5`: scrollback simulation helper says workloads use deterministic seeded input space; this is a simulation load-case term, not product event semantics.
- Root `build.zig:67`: aggregate build step description says deterministic package simulation workloads; this is build UX for simulation load cases.
- `utils/tools/rain-bench/README.md:5-7`, `14`, `106`: standalone rain benchmark owns workload generation and receipts; explicitly not a host product surface.

Classification: benchmark fixture/load case.

Finding correction after user review: render benchmark `workload` vocabulary is not acceptable because `howl-render/src/benchmark_main.zig` is an active render measurement API/output surface. Render benchmark names must use benchmark-case vocabulary. VT benchmark and simulation `workload` terms remain unpromoted for this slice and need their own pass if the same standard is applied there.

### Legitimate External/Reference Terms

Files and line refs:

- `howl-render/src/text/testdata/LICENSE.txt` contains Apache License terms "Work" and "Derivative Works". This is a legitimate external legal term and must not be renamed.
- `howl-render/design.md:9`, `49`, `howl-linux-host/design.md:52-53`, `docs/render-surface.md:286`, `539`, `674` contain design prose using `work`. These are not product code, but docs must be updated after accepted code slices so public vocabulary matches the new interfaces.

Classification: legitimate external/reference term; delete/defer docs update until code vocabulary is accepted.

## Reference Facts

Alacritty facts:

- Terminal event vocabulary is explicit: `Event::PtyWrite`, `Event::Wakeup`, `Event::ChildExit`, `Event::CursorBlinkingChange`, etc. `Wakeup` means "New terminal content available" (`alacritty_terminal/src/event.rs:14-58`).
- PTY loop has explicit `Msg::{Input, Shutdown, Resize}` for event-loop messages (`alacritty_terminal/src/event_loop.rs:29-40`). It drains the channel by message kind (`event_loop.rs:88-101`).
- PTY read is bounded by `READ_BUFFER_SIZE` and `MAX_LOCKED_READ`, parses bytes, and publishes `Event::Wakeup` when terminal redraw is needed (`event_loop.rs:23-27`, `103-168`).
- PTY event loop handles synchronized-update timeout by sending `Event::Wakeup`, handles child exit and optional drain-on-exit, and sends `Event::ChildExit`/`Wakeup` as distinct events (`event_loop.rs:227-270`).
- Window context explicitly drains its queued events (`event_queue.drain(..)`), processes display update, and requests redraw separately (`window_context.rs:400-493`).
- Window presentation request is called `request_redraw`, with `requested_redraw` tracked on the window (`display/window.rs:104-111`, `260-264`).
- Host draw first processes renderer updates, then calls display draw (`window_context.rs:366-397`). Display draw collects `RenderableContent`, damages terminal lines, drops the terminal lock, makes GL current, then calls renderer draw methods (`display/mod.rs:770-884`).
- Display update and renderer update are deliberately separate: `handle_update` takes pending display updates and `process_renderer_update` performs OpenGL-context work right before rendering (`display/mod.rs:647-668`, `739-768`).
- Presentation uses `swap_buffers`/`swap_buffers_with_damage`, not "work" (`display/mod.rs:607-623`).
- Renderer API names are direct: `Renderer`, `draw_cells`, `draw_string`, `draw_rects`, `GlyphCache` (`renderer/mod.rs:83-91`, `177-255`, `renderer/text/glyph_cache.rs:46-110`).
- Scheduler tracks timers, schedules `Event`, processes pending timers, and returns the next deadline (`scheduler.rs:34-89`).

Ghostty facts:

- VT/termio producer/consumer seam uses `Mailbox`, a bounded `BlockingQueue(termio.Message, 64)`, plus explicit wakeup (`termio/mailbox.zig:10-14`, `29-43`).
- Message publication and notification are distinct: `Mailbox.send()` queues without notify; `notify()` wakes the writer (`termio/mailbox.zig:55-105`).
- `Termio.queueMessage()` sends a message and notifies; direct `queueWrite()` is only for the mailbox thread (`termio/Termio.zig:386-418`).
- Termio owns renderer/surface mailbox wake handles separately (`termio/Termio.zig:46-60`).
- Termio thread drains mailbox messages, handles each message by type, and notifies renderer once after drain when redraw is needed (`termio/Thread.zig:288-361`).
- Wakeup callback drains the mailbox after producers publish and wake the thread (`termio/Thread.zig:440-457`).
- Ghostty C terminal surface has curated C API modules re-exported through `terminal/c/main.zig` (`terminal/c/main.zig:1-60`), and the local `AGENTS.md` under that reference states C API additions must be carried through module, lib export, and header. That supports treating Howl headers/FFI as first-class surfaces when names are wrong.

TigerBeetle facts:

- All loops and queues must have fixed upper bounds; event loops that cannot terminate must be asserted (`TIGER_STYLE.md:90-100`).
- Assertions must check function arguments, return values, pre/postconditions, and invariants (`TIGER_STYLE.md:104-140`).
- Programs should run at their own pace rather than doing work directly in reaction to external events (`TIGER_STYLE.md:179-183`).
- Names must capture exact nouns and verbs, avoid overload, and compose outside code (`TIGER_STYLE.md:271-347`).
- Static allocation and explicit upper bounds force natural limits and backpressure (`ARCHITECTURE.md:189-222`).
- Control plane/data plane separation keeps control decisions outside hot loops (`ARCHITECTURE.md:408-423`).

## Anchor Map

- Event creation/publication: Alacritty `Event`/`Msg` and `Event::Wakeup` (`event.rs:14-58`, `event_loop.rs:29-40`, `event_loop.rs:165-168`); Ghostty `queueMessage`/`Mailbox.notify` (`Termio.zig:386-401`, `mailbox.zig:97-105`).
- Event queue/drain: Alacritty `event_queue.drain(..)` (`window_context.rs:457-459`); Ghostty bounded mailbox pop loop (`Thread.zig:288-361`).
- Runtime admission: Alacritty scheduler deadline (`scheduler.rs:54-89`, `event.rs:483-489`); Howl `LoopRuntimeFacts` and `runtimeFacts` (`event.zig:730-745`, `surface.zig:465-472`).
- Transport drain: Alacritty PTY read bounds (`event_loop.rs:23-27`, `103-168`); Howl `TransportProgress` and bounded pump (`pty_pump.zig:34-40`, `92-140`).
- Render prepare: Howl renderer ABI `howl_render_text_prepare` (`howl_render.h:305-334`) and renderer `RenderRequest` (`event.zig:26-38`).
- Render submit: Howl renderer ABI `howl_render_text_submit` (`howl_render.h:331-334`) and pending prepared take/submit owner (`pending_prepared_surface.zig:87-119`).
- Retained render state: Howl `SubmittedSurface` retained-base token (`submitted_surface.zig:16-68`) and host retained state (`render_retained.zig:10-37`).
- Presentation: Alacritty `request_redraw`, `draw`, `swap_buffers` (`display/window.rs:260-264`, `display/mod.rs:607-623`, `display/mod.rs:770-884`); Howl present lifecycle (`present.zig:80-97`).
- Completion/acknowledgement: Howl host `completePresent()` acks VT source (`surface.zig:519-525`, `vt_surface.zig:58-78`); renderer header resource ack spans (`howl_render.h:250-259`).
- Benchmark fixture/load case: VT benchmark `workload` surface (`terminal_benchmark.zig:501-534`); render benchmark cases must use `BenchmarkCase`/`benchmark_case` vocabulary.

## Vocabulary Map

Exact old to new plan:

- `render_retained.WorkState` -> `RenderTurnAdmission`.
- `State.workState(bootstrap_surface)` -> `admitRenderTurn(bootstrap_surface)` because the method mutates bootstrap/present state before returning an admission snapshot.
- `WorkState.inFlight()` -> `hasRetainedTurn()` or delete if callers only need `needsRenderSurface()` equivalent.
- `WorkState.needsRenderSurface()` -> `needsRenderTurn()`.
- `Context.workState()` -> `renderTurnAdmission()`.
- Local variable `work_before` in `renderTurn()` -> `admission_before`.
- Parameter `work` in `driveRenderLocked()` -> `admission`.
- `LoopRuntimeFacts.render_work_pending` -> `render_turn_pending`.
- `RuntimeFacts.render_work_pending` and tests using that field -> `render_turn_pending`.
- `LoopWaitIntent.frame_work_pending` -> `visual_present_pending`.
- Local variable `render_pending` in `runLoopTurn()` -> `visual_present_pending`.
- Host tests using "work" for retained render/present/frame behavior -> use `turn`, `frame`, `present`, or `admission`:
  - "blocked frame work waits until frame deadline" -> "blocked render turn waits until frame deadline".
  - "latched host redraw remains present work after event pump" -> "latched host redraw remains a present reason after event pump".
  - "submitWith submits only visual present work" -> "submitWith submits only visual present reasons".
  - "pty wake observes retained render work prepared by pty thread" -> "pty wake observes retained render turn prepared by pty thread".
- `SessionWorkState` -> `TextSessionPending` if kept in the host mirror; better final location is renderer-owned if the type is needed across ABI.
- `TextSessionOwner.workState()` -> `pending()` or `pendingRenderStages()`; choose `pending()` only inside a true `TextSessionOwner`, otherwise use `textSessionPending()` at call sites.
- `source_pending` -> `source_pending` may stay if it means unsubmitted VT source snapshot; if exported, prefer `source_snapshot_pending`.
- `prepare_pending` -> `prepare_pending` may stay.
- `submit_pending` -> `submit_pending` may stay.
- `animation_pending` -> `animation_pending` may stay.
- `RealOps` in `pty_pump.zig` -> `TerminalProgressOps`.
- `RealOps` in `pty_wait_thread.zig` -> `ProgressThreadOps`.
- `RealOps` in `vt_surface.zig` -> `RenderStateCaptureOps`.
- `RealOps` in `fonts.zig` -> `FontSizeOps`.
- `RealAckOps` in `vt_surface.zig` may stay; it is already exact enough.
- PTY/runtime test names containing "work" -> use `progress`, `turn`, `transport slice`, or `runtime obligation`:
  - "progress drive keeps work bounded after saturated transport slice" -> "progress drive requests another turn after saturated transport slice".
  - "progress drive requests redraw and next turn for runtime work" -> "progress drive requests redraw and next turn for runtime obligation".
  - "transport pump caps locked feed work" -> "transport pump caps locked feed bytes".
  - "progress thread drains kept work before waiting again" -> "progress thread drains kept turns before waiting again".
- Render benchmark `Workload`, `WorkloadDamage`, `WorkloadPrepareContext`, `WorkloadResult`, and `workload` output fields -> rename to benchmark-case vocabulary.
- VT benchmark and simulation workload comments/descriptions -> not changed in the render benchmark slice; classify separately before editing.
- Apache/license `Work` -> leave unchanged; legitimate external legal term.

ABI/interface consequence map:

- Renderer C ABI currently exposes prepare/submit and no `WorkState`/`SessionWorkState`: `howl_render.h:305-334`. No renderer header rename is required for the current source inventory.
- Host is intentionally a C ABI harness: `howl-linux-host/build.zig:1-4`, and imports translated C headers for PTY/VT/render (`build.zig:111-160`). Therefore any future movement of `TextSessionPending` into `howl-render` must update `include/howl_render.h`, `src/libhowl_render.zig`, `src/test_abi.zig`, and host translated C call sites in one slice.
- Root build aggregates package-local steps and must not add cross-package Zig imports (`build.zig:1-4`, `20-45`, `84-88`). If nested repo pointers or package contents change, the orchestrator must record root/submodule receipts.
- `howl-vt` and `howl-pty` build files ship C ABI first (`howl-vt/build.zig:1-4`, `howl-pty/build.zig:1-4`) and have no active product-code hits requiring event vocabulary changes in this sprint.

## Ordered Cross-Repo Slice Plan

### Slice 1: Host Retained Render Admission Vocabulary

Allowed files:

- `howl-linux-host/src/terminal/render_retained.zig`
- `howl-linux-host/src/terminal/surface.zig`
- `howl-linux-host/src/terminal/surface_test.zig`
- `howl-linux-host/src/event.zig`
- `howl-linux-host/src/display/present.zig`

Required shape:

- Rename `WorkState` to `RenderTurnAdmission` and `workState()` to `admitRenderTurn()` in retained render owner.
- Rename host `render_work_pending` event-loop facts to `render_turn_pending`.
- Rename host `frame_work_pending` wait facts and local `render_pending` to `visual_present_pending`.
- Rename local variables/parameters/test names from generic work to `admission`, `turn`, `frame`, or `present reason` as mapped above.
- Preserve the existing retained-state enum names (`idle`, `prepare_needed`, `submit_ready`, `present_in_flight`, `failed`) unless implementation proves a separate state rename is required.

Required assertions:

- Keep `notePresentSubmitted()` non-zero token/snapshot assertions (`render_retained.zig:189-194`).
- Keep present completion assertion before VT ack (`surface.zig:519-525`).
- If `admitRenderTurn()` still mutates bootstrap state, its name must stay a verb and tests must prove bootstrap admission.

Required tests:

- `cd howl-linux-host && zig build test:unit -- "present pending blocks submit path until host present ack"`
- `cd howl-linux-host && zig build test:unit -- "submit path runs once no host present is in flight"`
- `cd howl-linux-host && zig build test:unit -- "blocked render turn waits until frame deadline"`
- `cd howl-linux-host && zig build test:unit -- "latched host redraw remains a present reason after event pump"`
- `cd howl-linux-host && zig build test:unit -- "submitWith submits only visual present reasons"`
- `cd howl-linux-host && zig build test:unit -- "pty wake observes retained render turn prepared by pty thread"`
- `cd howl-linux-host && zig build test:unit`

Non-goals:

- Do not move renderer ABI in this slice.
- Do not rename VT benchmark/simulation `workload` terms in the render benchmark slice.
- Do not change retained render behavior.

Stop conditions:

- Stop if a host call site requires a new renderer C ABI field/function to preserve behavior.
- Stop if `admitRenderTurn()` cannot be kept as an owner-local retained-render decision without widening into event-loop policy.

Receipt expectations:

- Coder session id, reviewer id, orchestrator id, commit hash if accepted.
- If `howl-linux-host` is a nested repo pointer in the root checkout, record nested repo commit and root pointer status.

### Slice 2: Host Test-Injection Ops Vocabulary

Allowed files:

- `howl-linux-host/src/terminal/pty_pump.zig`
- `howl-linux-host/src/terminal/pty_wait_thread.zig`
- `howl-linux-host/src/terminal/vt_surface.zig`
- `howl-linux-host/src/terminal/fonts.zig`

Required shape:

- Rename each `RealOps` to the exact platform seam owner:
  - `TerminalProgressOps`
  - `ProgressThreadOps`
  - `RenderStateCaptureOps`
  - `FontSizeOps`
- Keep `RealAckOps` unless reviewer requires `RenderStateAckOps`; it is already role-specific.
- Rename test titles containing generic work according to the vocabulary map.

Required assertions:

- Preserve transport bound comptime assertions in `pty_pump.zig:12-20`, `111-129`.
- Preserve wake coalescing behavior in `pty_wait_thread.zig:78-81`, `130-144`.
- Preserve render-state scrollback bound assertion in `vt_surface.zig:41-44`, `80-92`.

Required tests:

- `cd howl-linux-host && zig build test:unit -- "progress drive requests another turn after saturated transport slice"`
- `cd howl-linux-host && zig build test:unit -- "progress drive requests redraw and next turn for runtime obligation"`
- `cd howl-linux-host && zig build test:unit -- "transport pump caps locked feed bytes"`
- `cd howl-linux-host && zig build test:unit -- "progress thread drains kept turns before waiting again"`
- `cd howl-linux-host && zig build test:unit`

Non-goals:

- No PTY/VT behavior changes.
- No queue size or timing changes.
- No renderer ABI changes.

Stop conditions:

- Stop if a rename exposes shared fake ops across unrelated seams; split the test-injection type locally rather than preserving a broad abstraction.

Receipt expectations:

- Coder session id, reviewer id, orchestrator id, commit hash if accepted, nested repo/root pointer status.

### Slice 3: Renderer Session Pending Interface Decision

Allowed files for research-correction or implementation only after reviewer acceptance:

- `howl-linux-host/src/render_session.zig`
- If and only if the interface is moved to renderer ABI: `howl-render/include/howl_render.h`, `howl-render/src/libhowl_render.zig`, renderer tests under `howl-render/src/test_abi.zig` and `howl-render/src/test_unit.zig`, host C call sites that consume the new ABI.

Required shape:

- First decide whether `howl-linux-host/src/render_session.zig` is a stale host mirror that should be deleted/deferred, or a live host-local text render owner that must be renamed.
- If kept host-local: rename `SessionWorkState` to `TextSessionPending` and `workState()` to `pendingRenderStages()` or `pending()` inside the owner.
- If ABI-facing need is proven: add explicit C ABI names for pending render stages. Do not exclude ABI changes by default.

Required tests:

- Host tests proving source/prepare/submit/animation pending flags if host-local.
- Renderer `zig build test:abi` if header/FFI changes are introduced.
- Root `zig build test:abi` after any renderer ABI change.

Non-goals:

- Do not preserve `SessionWorkState` for compatibility without a concrete ABI consumer.
- Do not introduce Zig-shaped host shortcuts across package boundaries.

Stop conditions:

- Stop if the file is stale/unwired and the correct action is deletion; get orchestrator approval for deletion slice.
- Stop if a C ABI addition requires a larger render prepare/submit contract redesign.

Receipt expectations:

- Explicit decision receipt: host-local rename, delete/defer, or renderer ABI change.
- Coder/reviewer/orchestrator ids and commit hash if accepted.
- Nested renderer and host repo commits plus root pointer status if cross-repo.

### Slice 4: Documentation And Build Surface Vocabulary Receipts

Allowed files:

- `howl-linux-host/design.md`
- `howl-render/design.md`
- `docs/render-surface.md`
- Any README/docs touched by accepted code slices.

Required shape:

- Update design prose from generic `work`/`work state` to the accepted terms: render turn admission, prepare, submit, present, ack, and benchmark case.
- Leave VT benchmark/simulation `workload` docs intact unless separately promoted.

Required tests:

- No code tests required for docs-only changes, but run `zig build test:unit:build` in touched packages if doc changes accompany code movement.

Non-goals:

- Do not rewrite archived loop/research prose.
- Do not rename Apache/license terms.

Stop conditions:

- Stop if docs would describe an unaccepted implementation decision.

Receipt expectations:

- Documentation-only commit hash or explicit orchestrator receipt if batched into code slice.

## Tests And Verification Matrix

- Host retained-render vocabulary: `howl-linux-host` unit tests for present blocking, submit path, frame deadline admission, present reason derivation, and full host unit suite.
- Host PTY/runtime vocabulary: `howl-linux-host` unit tests for saturated transport slice, runtime obligation, locked feed byte cap, progress thread kept turns, wake coalescing, and full host unit suite.
- Renderer ABI untouched path: no renderer tests required beyond root check if no renderer file changes.
- Renderer ABI touched path: `cd howl-render && zig build test:abi`, `cd howl-render && zig build test:unit`, root `zig build test:abi`.
- VT/PTTY no-hit path: no direct changes expected; root aggregation should still run `zig build test:unit` or package checks after accepted cross-repo work.
- Benchmark terms: no rename tests; keep benchmark output schemas stable unless a separate benchmark schema slice is explicitly accepted.

## Risks

- `howl-linux-host/src/render_session.zig` appears renderer-owned by imports/names but lives in host. A careless rename could normalize a stale or wrong owner instead of deleting or moving it.
- `workState()` mutates state in `render_retained.zig:167-170`; renaming it as a query would be false. Use an admission verb.
- `render_work_pending` in event-loop facts is easy to over-specialize as presentation-only. Current source proves it means any render turn need (`surface.zig:404-407`, `465-472`).
- ABI changes remain in scope. Current source does not require a renderer header change for Slice 1/2, but Slice 3 may require one if `SessionWorkState` is proven ABI-facing.
- Benchmark `workload` is not uniformly legitimate. Render benchmark output names are an active surface and were corrected to benchmark-case vocabulary; VT benchmark/simulation terms need separate classification before any rename.

## Reviewer Correction Notes

- Reviewer `review-2026-06-19-product-event-semantics-01` rejected the first report because Slice 1 missed live `frame_work_pending` fields, missed root/simulation workload classifications, allowed docs in Slice 1 while deferring docs to Slice 4, and omitted the targeted retained-render wake test.
- Reviewer `review-2026-06-19-product-event-semantics-02` rejected the corrected report because `howl-vt/simulation/scrollback.zig:4` remained unclassified.
- This revision classifies `frame_work_pending` as `visual_present_pending`, classifies root and VT simulation workload wording as simulation load-case/build UX terms, removes `howl-linux-host/design.md` from Slice 1, and adds the retained-render wake test target.

## Proof Gaps

- Need reviewer/orchestrator decision on whether `howl-linux-host/src/render_session.zig` is live, stale, or a misplaced renderer owner before Slice 3.
- Need exact nested repo status/root pointer receipts before implementation commits. This research did not use git by instruction.
- Need coder to verify all grep hits after slices because test names and local variables may have additional lower-case `work` in unchanged docs or generated output.
- Need no-implementation reviewer acceptance before promoting any slice into `sprints/current.txt`.

## Readiness Judgment

Ready for reviewer. Not ready for coder until reviewer accepts this plan and the orchestrator promotes Slice 1 into `sprints/current.txt` with exact worker/reviewer receipts.
