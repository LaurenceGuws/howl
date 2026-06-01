# Terminal Context Owner Map Cache

## Date

2026-06-01

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-06-01-host-sprint.md`
- `research/cache-2026-06-01-host-owner-boundary-map.md`
- `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig`
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig`
- `utils/dev_references/terminals/ghostty/src/Surface.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/Selection.zig`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/event_loop.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/vt/input.zig`
- `howl-linux-host/src/terminal/vt/retained.zig`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/selection.zig`
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/window/term_texture.zig`

## Question

Map `terminal/context.zig` to source-backed owners and identify the next worker-ready split after the event-loop/window-wake slice.

## TigerBeetle Gates

- TigerBeetle requires explicit bounded control flow in `TIGER_STYLE.md:90-100`.
- TigerBeetle requires assertions for arguments, preconditions, postconditions, and invariants in `TIGER_STYLE.md:104-140`.
- TigerBeetle requires small scopes and centralized state mutation in `TIGER_STYLE.md:158-175`.
- TigerBeetle says programs run at their own pace instead of arbitrary work directly in external event callbacks in `TIGER_STYLE.md:179-183`.
- TigerBeetle requires exact nouns and top-down source order in `TIGER_STYLE.md:273-317`.
- TigerBeetle architecture reinforces explicit limits and component-owned async/wake contexts in `ARCHITECTURE.md:189-222` and `ARCHITECTURE.md:467-487`.

## Reference Findings

- Ghostty splits terminal truth from host surface integration. `src/terminal/Terminal.zig:1-4` defines the emulator/grid owner, with `screens`, `title`, `modes`, `mouse_shape`, focus flag, and dirty flags at `Terminal.zig:43-130`.
- Ghostty `src/termio/Termio.zig:1-5` owns terminal I/O state: backend/PTTY, terminal, renderer wake/mailbox, surface mailbox, stream parser, resize, focus, and output processing. Exact symbols include `Termio`, `DerivedConfig`, `init`, `threadEnter`, `queueMessage`, `queueWrite`, `resize`, `focusGained`, and `processOutput`.
- Ghostty `src/termio/stream_handler.zig:18-22` owns stream side effects over VT output. Exact symbols include `StreamHandler`, `vtFallible`, `windowTitle`, `clipboardContents`, `setMouseShape`, `semanticPrompt`, and `reportPwd`.
- Ghostty `src/Surface.zig:1-11` defines a per-terminal host surface owner that is drawn and responds to events, while app runtime decides window/tab/split delivery.
- Ghostty `Surface.init` at `src/Surface.zig:466-797` wires font, renderer, renderer thread, IO thread, PTY/exec, title, and runtime surface. This is the strongest reference for Howl's per-terminal host integration owner.
- Ghostty selection has its own terminal-core owner in `src/terminal/Selection.zig:2`, with host mouse adaptation in `Surface.mouseSelection` at `Surface.zig:4777-4918`.
- Ghostty link hover is host-surface adaptation over terminal screen state through `mouseRefreshLinks` at `Surface.zig:1565-1675`, `linkAtPos` at `Surface.zig:4268-4297`, and `linkAtPin` at `Surface.zig:4305-4350`.
- Ghostty scrollbar is a narrow host/runtime notification through `updateScrollbar` at `Surface.zig:1690-1698`.
- Alacritty confirms a per-window/per-terminal owner shape. `alacritty/src/window_context.rs:47-70` defines `WindowContext` with display, terminal, notifier, mouse/search/cursor blink state, config, and PTY fd/pid.
- Alacritty `WindowContext::new` at `window_context.rs:168-258` creates `Term`, PTY, PTY event loop, notifier, cursor blink wake, and per-window context.
- Alacritty PTY lifecycle and read/write pacing live in a PTY event loop owner. Exact symbols include `EventLoop`, `Msg`, `State`, `pty_read`, `pty_write`, `spawn`, and `EventLoopSender` in `alacritty_terminal/src/event_loop.rs:29-55`, `103-171`, `173-203`, `205-324`, and `383-393`.
- Alacritty bounds PTY processing with `READ_BUFFER_SIZE` and `MAX_LOCKED_READ` at `alacritty_terminal/src/event_loop.rs:23-27`.
- Alacritty host event processing adapts terminal/window/input/render through `WindowContext::handle_event` at `window_context.rs:400-459` and `ActionContext` at `event.rs:663-688`.
- Alacritty render preparation/submission is in `Display`, not terminal context. Exact symbols include `RenderableContent` in `display/content.rs:24-40`, `RenderableContent::new` at `content.rs:40-83`, and `Display::draw` at `display/mod.rs:775-934`.
- Alacritty title/clipboard/focus are terminal events handled by host event processing. Exact symbols include `TerminalEvent::Title`, `ResetTitle`, `ClipboardStore`, and `ClipboardLoad` at `event.rs:1867-1911`, plus focus input encoding in `Processor::on_focus_change` at `input/mod.rs:830-837`.

## Current Context Facts

- `terminal/context.zig` remains a god aggregate even after the event-loop slice.
- Current product section before tests is `terminal/context.zig:1-1673`.
- Current tests are `terminal/context.zig:1674-2470`.
- Current scan found 124 product functions and 19 assertion calls, for about 0.15 assertions/function.
- Over-70-line product functions are `printRenderSurfaceSummaryDiagnostics(...)` at `terminal/context.zig:1005-1082` and `printRenderSurfaceIntervalDiagnostics(...)` at `terminal/context.zig:1084-1162`.
- Tests are after production in this file, unlike `window/term_texture.zig` where production helpers continue after tests.
- `Context` now owns `event_loop: *EventLoop.State` at `terminal/context.zig:133`, but `event_loop.zig` is the true owner of quit/wake/pump policy at `event_loop.zig:17-129`.

## Rejected Names

- Reject `context`, `manager`, `controller`, `engine`, `utils`, and `types` as owner names.
- Do not create `terminal/render/manager.zig`, `terminal/input/controller.zig`, `terminal/utils.zig`, or any `types.zig`.
- `terminal/context.zig` is not an acceptable final owner name. It may remain only as a temporary compatibility shell until a promoted rename/split owns the imports and tests.

## Field Ownership Map

- `term: HowlTerm` at `terminal/context.zig:124` may remain in the per-terminal host integration owner because it stitches PTY, VT, render, mutex, and host lifecycle. Behavior still belongs to `terminal/pty/*`, `terminal/vt/*`, `terminal/render/*`, and `terminal/term.zig`.
- `progress: pty_wait_thread.State` at `terminal/context.zig:125` belongs to `terminal/pty/wait_thread.zig`, which defines wake state at `wait_thread.zig:8-18`, wake acknowledgement at `wait_thread.zig:38-42`, and event-loop wake handoff at `wait_thread.zig:90-118`.
- `live: bool` at `terminal/context.zig:126` is a session lifecycle cache. True lifecycle owner is PTY session; the per-terminal host integration owner may retain this for init/deinit containment.
- `term_texture` at `terminal/context.zig:127` belongs to host render-surface GL realization in `window/term_texture.zig`, especially `ensureSurface(...)` at `window/term_texture.zig:2049-2079`.
- `render_surface_textures` at `terminal/context.zig:128` belongs to `window/term_texture.zig` `RenderResourceTextures`, defined at `window/term_texture.zig:24-138`.
- `render_surface_submit_diagnostics` and logged snapshot at `terminal/context.zig:129-130` belong to terminal render-surface submit diagnostics currently embedded at `terminal/context.zig:82-122` and logged at `terminal/context.zig:974-1252`.
- `conf` at `terminal/context.zig:131` is dependency injection from config. `Context` consumes terminal policy; it does not own config parsing.
- `input` at `terminal/context.zig:132` is a host input dependency. The input queue/event intake owner is `input/input.zig`; terminal-specific input adaptation remains terminal side.
- `event_loop` at `terminal/context.zig:133` belongs to `event_loop.zig`; `Context` only passes the owner-thread wake target into PTY wait-thread init at `terminal/context.zig:508`.
- `title_buf` and `title_len` at `terminal/context.zig:134-135` belong to terminal title host adaptation over VT retained state at `terminal/context.zig:336-347` and `terminal/vt/retained.zig:73-94`.
- `geometry` at `terminal/context.zig:136` belongs to `terminal/render/surface_layout.zig`; `Context` wrappers are at `terminal/context.zig:237-250`.
- `font_size_px` and `default_font_size_px` at `terminal/context.zig:137-138` belong to `terminal/render/font_size.zig`; `Context` wires layout resync at `terminal/context.zig:369-382`.
- `window_focused` and `widget_focused` at `terminal/context.zig:139-140` are per-terminal host focus adaptation. VT publication belongs to `terminal/vt/input.zig:120-126`.
- `scrollbar` at `terminal/context.zig:141` belongs to `terminal/scrollbar.zig`, especially `handlePages`, `handleMouse`, and `layout` at `scrollbar.zig:18-61`.
- `link_cursor_active` and `hovered_link_cell` at `terminal/context.zig:142-143` belong to `terminal/links.zig`, especially `handleMouse`, `clearHoveredLink`, and hover decoration at `links.zig:14-46`.
- `selection_anchor` and `selection_drag_active` at `terminal/context.zig:144-145` belong to `terminal/selection.zig`, especially mouse selection at `selection.zig:14-67`.
- `hover_publish_pending` at `terminal/context.zig:146` belongs to the VT visible-source publication boundary in `terminal/vt/surface.zig`, with link hover decoration as input.
- `cursor_blink` at `terminal/context.zig:147` belongs to `terminal/cursor_blink.zig`, defined at `cursor_blink.zig:6-43`.

## Function Group Ownership Map

- Per-terminal host integration must retain `init`, `initial`, `deinit`, `initTerm`, `startRuntime`, `launchConfig`, `renderInit`, and `initTermState` at `terminal/context.zig:159-235`, `481-513`, and `1418-1455`. These stitch PTY, VT, render, config, feed recording, event-loop wake, and thread lifecycle without changing ABI semantics.
- PTY progress/session functions `lifecycleState`, `isAlive`, `ptySnapshot`, `sessionOutcome`, and `driveProgress` at `terminal/context.zig:320-333` and `418-430` belong to `terminal/pty/session.zig`, `terminal/pty/pump.zig`, and `terminal/pty/wait_thread.zig`.
- `terminal/pty/pump.zig` owns bounded transport/runtime progress at `pump.zig:43-55` and bounded transport read loops at `pump.zig:103-193`.
- Input adapter functions `paste`, text/pointer drains, publish bytes/key/mouse, mouse ownership, and pixel conversion at `terminal/context.zig:253-294`, `1276-1324`, and `1574-1651` belong to a terminal input adapter over `terminal/vt/input.zig`, `terminal/selection.zig`, `terminal/links.zig`, and `terminal/scrollbar.zig`.
- Terminal input adapter behavior must not move into `input/input.zig`, because SDL intake and terminal VT/PTY publication are separate host boundaries.
- Scrollbar functions `handleScrollInput`, `wantsPassiveHoverWake`, `ScrollMouseOutcome`, `ScrollVisualState`, and `ContextOps.handleScrollMouse` at `terminal/context.zig:296-302` and `1326-1371` belong to `terminal/scrollbar.zig`.
- Links/focus functions `wantsLinkHover`, `setWindowFocused`, `setWidgetFocused`, `ContextOps.clearHoveredLinkOp`, and `ContextOps.handleHostLinkMouse` at `terminal/context.zig:304-307`, `349-363`, and `1385-1408` belong to `terminal/links.zig` plus per-terminal focus adaptation.
- VT focus/mouse reporting functions `wantsTerminalHoverReporting`, `syncInputFocus`, and terminal mouse conversion/publication at `terminal/context.zig:309-312`, `365-367`, and `1292-1316` belong to `terminal/vt/input.zig`.
- `overlaySnapshot` at `terminal/context.zig:314-318` may remain a thin per-terminal presentation adapter over owner-produced overlays.
- Title/clipboard functions `titleSlice`, `refreshTitle`, `renderSurfaceLabel`, `applyPendingClipboardWrites`, `WindowClipboardOps`, and `applyPendingClipboardWrite` at `terminal/context.zig:336-347`, `515-519`, `1164-1168`, and `1653-1672` belong to terminal title/clipboard host adapters over VT retained state and window clipboard calls.
- Font size functions at `terminal/context.zig:369-382` belong to `terminal/render/font_size.zig`.
- Cursor blink functions at `terminal/context.zig:388-403`, `528-545`, and `1505-1509` belong to `terminal/cursor_blink.zig` plus render ABI call boundary.
- VT runtime obligation functions `runtimeObligationDueNow` and `nextRuntimeObligationWaitMs` at `terminal/context.zig:405-416` belong to the VT retained runtime-obligation adapter in `terminal/vt/retained.zig:148-174`.
- Render prepare/submit functions `wantsRenderTurn`, `renderTurn`, `driveRender`, `driveRenderLocked`, `renderAction`, `maybePublishSource`, `prepare`, `takePreparedUpload`, `submitPrepared`, `submitPreparedLocked`, `submitPreparedLockedWith`, and present ack helpers at `terminal/context.zig:384-385`, `433-470`, `561-624`, `632-635`, `843-885`, `1254-1274`, and `1562-1572` belong to a terminal render-submit adapter over `terminal/render/retained.zig` and `terminal/vt/surface.zig`.
- Render submit split must preserve the current unlock around backend upload at `terminal/context.zig:856-858`.
- Backend upload and GL realization functions `ContextSubmitBackend.upload`, `uploadRenderSurfaceCommands`, `shouldRealizeRenderSurface`, and `execution` at `terminal/context.zig:636-840` are split-boundary functions. Submit decision/diagnostics are terminal render-submit behavior; `ensureSurface`, resource realization, shape predicates, and upload/draw execution belong to `window/term_texture.zig` at `window/term_texture.zig:2049-2705`.
- Render-surface diagnostics state and logging helpers at `terminal/context.zig:82-122`, `585-593`, `745-824`, `922-943`, and `961-1252` belong to a terminal render-surface submit diagnostics owner.
- ABI translation helpers `initTextSession`, `initSurfaceLayout`, `initVt`, `deinitVt`, font path helpers, `renderCallOk`, and pixel helpers at `terminal/context.zig:1458-1560` belong to terminal render/VT init adaptation. They must not become public Zig-shaped host integration APIs.

## Current Test Coverage

- Surface layout wrapper behavior is covered by `terminal/context.zig:1674`.
- Clipboard is covered by `terminal/context.zig:1693`; gap: no integration proof that OSC 52 clipboard write drains through live `driveProgress`.
- Cursor blink is covered by `terminal/context.zig:1742` and owner-local `terminal/cursor_blink.zig:56`.
- Render diagnostics are covered by `terminal/context.zig:1773`, `1811`, `1824`, `1835`, and `1846`; `window/term_texture.zig` also covers texture failure classification at `term_texture.zig:1918-1986`.
- Terminal input adapter is covered by `terminal/context.zig:1853`, `1981`, and `2080`.
- Render submit sequencing is covered by `terminal/context.zig:2137`, `2149`, `2308`, `2321`, `2333`, `2344`, `2358`, and `2371`.
- Present ack is covered by `terminal/context.zig:2387` and `2429`, plus retained render tests at `terminal/render/retained.zig:1906-1942` and `3122-3131`.
- PTY wait/wake is covered by `terminal/pty/wait_thread.zig:121-188`.
- PTY pump is covered by `terminal/pty/pump.zig:314-345`.
- VT surface publication is covered by `terminal/vt/surface.zig:440-538`.
- Render retained validation/resource plan is covered by `terminal/render/retained.zig:1834-3131`.
- No tests were found in `terminal/scrollbar.zig`, `terminal/links.zig`, or `terminal/selection.zig`; those behaviors are partially exercised through context input-adapter tests.

## Behavior That Must Remain Per-Terminal Host Integration

- Creation/destruction ordering across PTY, VT, render, feed record, wait thread, event loop, and GL texture state at `terminal/context.zig:159-235` and `terminal/context.zig:481-513`.
- Per-terminal storage of aggregate `HowlTerm`, lifecycle cache, focus state, title buffer, and owner references at `terminal/context.zig:124-147`.
- Mutex choreography around render backend upload: unlock before host upload and relock before submit at `terminal/context.zig:856-858`.
- Thin orchestration that asks smaller owners for facts and combines them for one terminal: `renderTurn`, `driveProgress`, input drains, focus publication, and overlay snapshot.
- ABI stitching for C handles and host-owned resources. Do not expose internal Zig convenience imports as host integration boundaries.

## Rejected Worker-Ready Split Candidate

Rejected as worker-ready: extracting terminal render-surface submit diagnostics is not yet pure diagnostics movement. Current source interleaves diagnostics, trusted render-surface failure-policy helpers, panic behavior, retained action classification, submit backend upload, and GL realization consequences.

Candidate owner file if later accepted:

- `howl-linux-host/src/terminal/render_surface_submit_diagnostics.zig`

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render_surface_submit_diagnostics.zig`

Blocked movement:

- Move `RenderSurfaceSubmitDiagnostics` from `terminal/context.zig:82-122`.
- Do not move the broad `terminal/context.zig:745-824` range until ownership is split further. Current source in this range includes trusted failure-policy behavior such as `panicUnsupportedTrustedRenderSurfaceShape`, `trustedRenderSurfaceUnavailableAction`, and `recordRenderSurfaceUnavailable`, not just diagnostics.
- Pure diagnostic counters/printers may be a future candidate, but exact helper ownership must be planned first.
- Keep `submitPreparedLockedWith(...)` in the per-terminal host integration owner because it owns mutex sequencing at `terminal/context.zig:843-885`.
- Keep GL realization in `window/term_texture.zig`.

Missing exact test gate:

- Current tests reach private submit-backend policy helpers directly, including current `terminal/context.zig:1835-1850`. A future plan must state whether those helpers stay private in the submit owner, move to a diagnostics owner, or become retained-render policy tests.
- A future plan must specify exact tests for pure diagnostics separately from trusted failure-policy/panic behavior.
- Existing submit sequencing tests at `terminal/context.zig:2308-2358` must remain in `context.zig` or the renamed per-terminal owner.

Verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan must report zero lines over 190 chars.

ABI consequences:

- None. This is host-only code movement.
- Do not touch `howl-pty`, `howl-vt`, or `howl-render` C ABIs.

Additional stop conditions required before this can become worker-ready:

- Stop if diagnostics need to inspect or mutate render internals directly.
- Stop if the split changes trusted render-surface failure semantics.
- Stop if tests must be weakened or moved to import-only coverage.
- Stop if the worker needs to invent a generic owner name.
- Stop if mutex sequencing around backend upload changes.
- Stop if extraction crosses into trusted failure-policy action helpers or panic helpers without an accepted owner map.
- Stop if a worker would need to decide whether helpers from `terminal/context.zig:745-824` belong to diagnostics, submit policy, or retained render policy.

## Next Required Planning Step

- Separate pure render-surface submit diagnostics/logging from trusted failure-policy behavior in current source.
- Decide exact ownership for trusted action helpers and panic helpers: terminal render submit policy, retained render policy, or diagnostics.
- Produce a corrected worker-ready slice only after exact helper ownership, tests, allowed files, and stop conditions are accepted.

## Corrected Worker-Ready Split: Pure Render-Surface Submit Diagnostics

Focused follow-up research separates pure diagnostics/logging from trusted failure-policy behavior.

Pure diagnostics/logging:

- `terminal/context.zig:82-122` is pure render-surface submit diagnostic state. It records counters, timings, last emit/resource-plan status, unavailable buckets, unsupported-shape buckets, and realized shape buckets.
- `terminal/context.zig:585-593`, `922-943`, `961-972`, and `974-1252` are diagnostics/logging helpers. They record prepare failures, submit failures, render-surface realization/upload timings, bounded logging, summary/interval/GL/failure printing, failure totals, and counter deltas.

Not pure diagnostics:

- `terminal/context.zig:636-743` is submit backend upload and shape realization.
- `terminal/context.zig:745-824` is mixed. `recordUnsupportedRenderSurfaceShape(...)` and the first half of `recordRenderSurfaceUnavailable(...)` mutate counters, but `panicUnsupportedTrustedRenderSurfaceShape(...)`, `trustedUnsupportedRenderSurfaceShapeAction(...)`, `trustedRenderSurfaceUnavailableAction(...)`, and the second switch in `recordRenderSurfaceUnavailable(...)` enforce trusted failure policy and panic behavior.
- `terminal/context.zig:843-885` is submit sequencing, including the unlocked backend upload window at `terminal/context.zig:856-858`, stable prepared-handle check, backend failure result, and retained submit.
- `terminal/render/retained.zig:108-130` already owns trusted render-surface action vocabulary and resource-plan status classification through `TrustedRenderSurfaceAction` and `trustedResourcePlanStatusAction(...)`.
- `window/term_texture.zig:108-138` owns host GL/resource realization failure policy for textures.

Owner names:

- Pure diagnostics owner: `terminal/render_surface_submit_diagnostics.zig`.
- Future trusted submit/failure policy owner if later separated: `terminal/trusted_render_surface_submit.zig`.
- Do not put `panicUnsupportedTrustedRenderSurfaceShape(...)`, `trustedRenderSurfaceUnavailableAction(...)`, or submit sequencing into `terminal/render_surface_submit_diagnostics.zig`.
- Reject generic names such as `terminal/render/submit_policy.zig`, `terminal/render/policy.zig`, `terminal/render/diagnostics.zig`, and `terminal/render/submit.zig` for this immediate diagnostics-only task.

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render_surface_submit_diagnostics.zig`

Move:

- `Context.RenderSurfaceSubmitDiagnostics` from `context.zig:82-122` as `render_surface_submit_diagnostics.Diagnostics`.
- Keep a compatibility alias in `Context`: `pub const RenderSurfaceSubmitDiagnostics = render_surface_submit_diagnostics.Diagnostics;`.
- Move pure helpers from `context.zig:974-1252`: logging gate, summary print, interval print, GL print, failure print, failure total, and counter delta.
- Move timing counter helpers from `context.zig:961-972` as diagnostics functions.
- Move `recordPrepareFailure(...)` from `context.zig:585-593` only as a diagnostics function taking `*Diagnostics` and `render_retained.PrepareFailure`.

Exact new leaf API:

- `pub const Diagnostics = struct { ... }` with the current fields from `Context.RenderSurfaceSubmitDiagnostics`.
- `pub const LogRequest = struct { submit: *Diagnostics, logged: *Diagnostics, texture: term_texture.RenderResourceTextures.Diagnostics, texture_failure_count: u64, label: []const u8 }`.
- `pub fn recordPrepareFailure(diagnostics: *Diagnostics, reason: render_retained.PrepareFailure) void`.
- `pub fn recordRenderSurfaceRealization(diagnostics: *Diagnostics, elapsed_us: u64) void`.
- `pub fn recordHostUpload(diagnostics: *Diagnostics, elapsed_us: u64) void`.
- `pub fn recordSubmitFailure(diagnostics: *Diagnostics, reason_name: []const u8, info: render_c.HowlRenderPreparedSurfaceInfo, execution: render_c.HowlRenderSubmitExecution) void`.
- `pub fn recordEmitStatus(diagnostics: *Diagnostics, status: c_int) void`.
- `pub fn recordResourcePlanStatus(diagnostics: *Diagnostics, status: render_retained.PreparedRenderResourcePlanStatus) void`.
- `pub fn recordUnavailable(diagnostics: *Diagnostics, status: render_retained.PreparedRenderResourcePlanStatus) void`.
- `pub fn recordUnsupportedShape(diagnostics: *Diagnostics, summary: term_texture.RenderSurfaceSummary) void`.
- `pub const ShapeKind = enum { fill_only, fill_patch, sprite, sprite_patch, glyph, glyph_patch }`.
- `pub const ShapeOutcome = enum { surface, present, failure }`.
- `pub fn recordShape(diagnostics: *Diagnostics, kind: ShapeKind, outcome: ShapeOutcome) void`.
- `pub fn logRenderSurfaceDiagnostics(request: LogRequest) void`.
- `pub fn shouldLogRenderSurfaceFailure(diagnostics: *Diagnostics, texture_failure_count: u64) bool`.
- `pub fn renderSurfaceFailureTotal(texture: term_texture.RenderResourceTextures.Diagnostics) u64`.
- `pub fn counterDelta(current: u64, previous: u64) u64`.
- Printing helpers may remain private inside `terminal/render_surface_submit_diagnostics.zig`; they must take plain `Diagnostics`, `term_texture.RenderResourceTextures.Diagnostics`, and `label: []const u8` inputs.

Exact caller shape in `Context`:

- `Context.logRenderSurfaceDiagnostics()` stays as a thin wrapper that computes `label = self.renderSurfaceLabel()` and calls `render_surface_submit_diagnostics.logRenderSurfaceDiagnostics(.{ .submit = &self.render_surface_submit_diagnostics, .logged = &self.render_surface_submit_diagnostics_logged, .texture = self.render_surface_textures.diagnostics, .texture_failure_count = self.render_surface_textures.failure_count, .label = label })`.
- `Context.shouldLogRenderSurfaceFailure()` should be deleted or reduced to a thin call only if needed by tests; diagnostics logic belongs in the new owner.
- `Context.recordPrepareFailure(...)`, `Context.recordSubmitFailure(...)`, `Context.recordRenderSurfaceRealization(...)`, and `Context.recordHostUpload(...)` may remain only as one-line wrappers if that keeps submit code minimal. Their logic must call the new diagnostics owner.
- Every pure direct mutation of `render_surface_submit_diagnostics` in `ContextSubmitBackend.upload(...)`, `uploadRenderSurfaceCommands(...)`, `recordUnsupportedRenderSurfaceShape(...)`, and the first bucket switch in `recordRenderSurfaceUnavailable(...)` must become a call to one of the diagnostics owner recording helpers above.
- `recordUnsupportedRenderSurfaceShape(...)` stays in `context.zig` only as a policy-adjacent wrapper that computes `term_texture.renderSurfaceSummary(render_surface)` and calls `render_surface_submit_diagnostics.recordUnsupportedShape(...)`.
- `recordRenderSurfaceUnavailable(...)` stays in `context.zig` only because it enforces trusted failure policy; its diagnostic bucket mutation must call `render_surface_submit_diagnostics.recordUnavailable(...)` before the policy switch.
- Status assignment in `ContextSubmitBackend.upload(...)` must call `recordEmitStatus(...)` and `recordResourcePlanStatus(...)` instead of assigning fields directly.
- Render-surface shape attempts/presents/failures in `uploadRenderSurfaceCommands(...)` must call `recordShape(...)` instead of incrementing fields directly.
- `ShapeKind.glyph_patch` maps to the existing glyph counters: `.surface` increments `render_surface_glyph_count`, `.present` increments `render_surface_glyph_present_count`, and `.failure` increments `render_surface_glyph_failure_count`.
- `renderSurfaceLabel()` stays in `Context`; title refresh and config fallback are not diagnostics ownership.

Forbidden dependencies:

- `terminal/render_surface_submit_diagnostics.zig` must not import `terminal/context.zig`.
- It must not accept `*Context`, `anytype self`, or a struct that contains terminal/context fields.
- It must not import or mutate retained render owner internals beyond public host-side types already used by current diagnostics signatures.

Stay:

- `ContextSubmitBackend.upload(...)` and `uploadRenderSurfaceCommands(...)` at `context.zig:636-743`.
- `recordUnsupportedRenderSurfaceShape(...)`, `panicUnsupportedTrustedRenderSurfaceShape(...)`, `trustedUnsupportedRenderSurfaceShapeAction(...)`, `trustedRenderSurfaceUnavailableAction(...)`, and `recordRenderSurfaceUnavailable(...)` at `context.zig:745-824`.
- `submitPreparedLockedWith(...)` at `context.zig:843-885`.
- `SubmitPreparedResult`, `SubmitFailureReason`, and `submitFailureReason(...)` at `context.zig:887-920`.
- Existing trusted failure-policy tests at `context.zig:1835-1850`.

Tests:

- Move/update diagnostics tests at `context.zig:1773-1833` to `terminal/render_surface_submit_diagnostics.zig`.
- Add/keep exact test `render surface diagnostic failure logging is first N bounded`: construct `Diagnostics`, call `shouldLogRenderSurfaceFailure(&diagnostics, failure_count)` for failures 1 through 9, assert first 8 return true, ninth returns false, and `logged_render_surface_failure_count == 8`.
- Add/keep exact test `render surface failure total sums exact buckets`: construct `term_texture.RenderResourceTextures.Diagnostics`, set each failure bucket 1 through 8, and assert `renderSurfaceFailureTotal(...) == 36`.
- Add/keep exact test `render surface unavailable diagnostics use render surface vocabulary`: assert `Diagnostics` has every `render_surface_unavailable_*` field currently asserted in `context.zig:1824-1833`.
- Add exact test `counter delta preserves reset current`: assert `counterDelta(10, 3) == 7` and `counterDelta(2, 5) == 2`.
- Add exact test `record host upload updates count last and max`: call `recordHostUpload` twice with increasing/decreasing values and assert `submit_count`, `host_upload_us_last`, and `host_upload_us_max`.
- Add exact test `record render surface realization updates last and max`: call `recordRenderSurfaceRealization` twice and assert last/max.
- Add exact test `record prepare failure increments bounded counter`: call `recordPrepareFailure` nine times and assert `prepare_failure_count == 9`.
- Add exact test `record submit failure increments bounded counter`: call `recordSubmitFailure` nine times with stable fake info/execution and assert `submit_failure_count == 9`.
- Add exact test `record unavailable classifies every resource plan status bucket`: cover each `PreparedRenderResourcePlanStatus` tag and assert aggregate bucket counters match the current switch in `context.zig:787-815`.
- Add exact test `record shape tracks surface present and failure buckets`: cover every `ShapeKind` with `.surface`, `.present`, and `.failure` where the current fields exist.
- Keep submit sequencing tests at `context.zig:2308-2385`.
- Keep trusted policy tests at `context.zig:1835-1850` in `context.zig` unless a later trusted submit owner is promoted.

Verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan must report zero lines over 190 chars.

ABI consequences:

- None. This is Linux-host-only code movement.
- Do not touch `howl-pty`, `howl-vt`, or `howl-render` C ABIs.

Stop conditions:

- Stop if the worker needs to move any symbol from `context.zig:745-824`.
- Stop if the split changes panic/fail-closed behavior for trusted render surfaces.
- Stop if submit mutex unlock/relock sequencing at `context.zig:856-858` changes.
- Stop if private trusted-policy tests are weakened or deleted.
- Stop if diagnostics starts importing or mutating retained render internals directly.

## Other Split Candidates

- Extract terminal input/selection/link/scroll/focus adaptation into non-generic owners such as `terminal/input.zig`, `terminal/selection.zig`, `terminal/links.zig`, preserving app event-loop and SDL input ownership.
- Extract PTY lifecycle/progress methods into `terminal/pty/session.zig` plus existing `terminal/pty/wait_thread.zig`, preserving wait-thread wake-only discipline.
- Extract render submit sequencing into `terminal/render/submit.zig`, but only after render-surface submit diagnostics and Lane A failure-policy interactions are not interleaved.

## Proof Gaps And Risks

- The final per-terminal owner name is not yet accepted. Ghostty supports `Surface`; Alacritty supports `WindowContext`, but `context` is banned here.
- Render submit diagnostics are less risky than render submit sequencing, but still adjacent to Lane A failure-policy behavior and must not alter semantics.
- No behavioral tests were found for `terminal/scrollbar.zig`, `terminal/links.zig`, or `terminal/selection.zig`; current context tests only cover adapter routing.
- No end-to-end test proves PTY wait-thread wake travels through `Context.event_loop` into `event_loop.State`.
- Current `terminal/context.zig` assertion density is far below TigerBeetle target.
- `printRenderSurfaceSummaryDiagnostics(...)` and `printRenderSurfaceIntervalDiagnostics(...)` exceed the 70-line target.
