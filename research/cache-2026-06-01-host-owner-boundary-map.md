# Host Owner Boundary Map Cache

## Date

2026-06-01

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-06-01-host-sprint.md`
- `research/cache-2026-06-01-host-owner-inventory.md`
- `research/cache-2026-06-01-host-reference-shape.md`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/window/present.zig`
- `howl-linux-host/src/input/window.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/render/surface_layout.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- Source search for `input/window.zig`, `InputWindow`, and same-directory `@import("window.zig")` in `howl-linux-host/src/**/*.zig`

## Question

Lane B Slice 1 asks for a source-backed owner-boundary map for over-owned Linux host files, the true boundary/name for `input/window.zig`, function length and assertion-density facts before planning touches the target files, and a first implementation split only if it preserves the control spine, bounded turns, ABI boundary, and owner-thread wake discipline.

## TigerBeetle Gates

- TigerBeetle requires simple explicit control flow, bounded loops/queues, and asserted non-terminating loops in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100`.
- TigerBeetle requires assertions for arguments, return values, pre/postconditions, and invariants, with a minimum average of two assertions per function in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104-140`.
- TigerBeetle requires small scopes, centralized control flow, and centralized state mutation in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158-175`.
- TigerBeetle requires programs to run at their own pace instead of doing arbitrary work directly in reaction to external events in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:179-183`.
- TigerBeetle requires exact naming in `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273-317`.
- TigerBeetle architecture frames explicit limits as a forcing function for static allocation and component-owned in-flight contexts in `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222` and `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:467-487`.

## Accepted Inputs

- The owner-inventory cache identifies the host ABI/design boundary: the Linux host owns app lifecycle, SDL input, event loop, wake policy, tab/window orchestration, presentation cadence, backend resource realization, and process launch policy; it does not own PTY internals, VT semantics, render internals, or terminal-state truth in `research/cache-2026-06-01-host-owner-inventory.md:68-75`.
- The owner-inventory cache identifies `terminal/context.zig`, `window/term_texture.zig`, `main.zig`, `input/input.zig`, and `window/present.zig` as over-owned or broader-than-name files in `research/cache-2026-06-01-host-owner-inventory.md:212-228`.
- The reference-shape cache says Howl must preserve centralized owner-thread control while not concentrating owner-specific behavior in `main.zig`, and must preserve bounded input/transport slices and the wake-only PTY thread discipline in `research/cache-2026-06-01-host-reference-shape.md:147-164`.
- The sprint scratchpad forbids implementation planning if ownership, naming, scope, test gates, or ABI consequences are under-specified in `research/2026-06-01-host-sprint.md:28-32`.

## Function Length And Assertion Density Facts

These facts were collected before proposing any implementation split for files named in Lane B.

### `terminal/context.zig`

- Product section before tests: 1,651 lines, 127 functions, 19 assertion calls, assertion density 0.15 assertions/function.
- Over 70-line product functions: `printRenderSurfaceSummaryDiagnostics(...)` is 79 lines at `howl-linux-host/src/terminal/context.zig:984-1062`; `printRenderSurfaceIntervalDiagnostics(...)` is 80 lines at `howl-linux-host/src/terminal/context.zig:1063-1142`.
- The product assertion density is far below the TigerBeetle two-assertions-per-function target from `TIGER_STYLE.md:104-140`.
- Current test coverage exists in the same file from `howl-linux-host/src/terminal/context.zig:1653-2449`, but test presence does not repair product assertion density.

### `window/term_texture.zig`

- Product section before tests: 988 lines, 65 functions, 0 assertion calls, assertion density 0.00 assertions/function.
- Full file after tests and post-test product helpers is 2,705 lines, 100 function declarations by source scan, 21 assertion calls, and 40 test blocks.
- Over 70-line product functions before tests: none. Post-test product helper `uploadRenderSurfaceCommands(...)` is 98 lines at `howl-linux-host/src/window/term_texture.zig:2145-2241`.
- The source order places tests before production upload/shape/draw helpers: tests start at `howl-linux-host/src/window/term_texture.zig:990`, while production `ensureSurface(...)` and upload/shape/draw helpers continue at `howl-linux-host/src/window/term_texture.zig:2049-2705`. This violates the top-down source-order pressure from `TIGER_STYLE.md:315-317`.
- Product assertion density before tests is zero, despite this file owning trusted render-surface validation and GL realization.

### `main.zig`

- Production functions excluding test bodies but including production functions after tests: 74 functions, 21 assertion calls, assertion density 0.28 assertions/function.
- Over 70-line production functions: `start(...)` is 72 lines at `howl-linux-host/src/main.zig:103-174`.
- `runLoopTurn(...)` is 60 lines at `howl-linux-host/src/main.zig:230-288`, under the hard 70-line limit but carrying the full control spine.
- Test blocks are interleaved with later production functions. Tests begin at `howl-linux-host/src/main.zig:668`, while production tab/focus helpers continue at `howl-linux-host/src/main.zig:761-903`.
- Production functions after tests include `resizeTerminals(...)`, `setWindowFocused(...)`, `activeTabProblem(...)`, `activeTab(...)`, `activeContext(...)`, `handleBindingAction(...)`, `openTab(...)`, `closeActiveTab(...)`, `selectRelative(...)`, `selectTab(...)`, `syncTerminalFocus(...)`, `tabTitles(...)`, `pasteIntoActiveTab(...)`, `setCurrentThreadName(...)`, and `tabIndexInRange(...)` at `howl-linux-host/src/main.zig:761-903`.
- Tests cover runtime obligation, frame deadlines, title sync, input forwarding, redraw/present facts, tab lifecycle, and focus behavior through `howl-linux-host/src/main.zig:668-1096`.

### `input/input.zig`

- Product section before tests: 719 lines, 51 functions, 6 assertion calls, assertion density 0.12 assertions/function.
- Over 70-line product functions: `processEvent(...)` is 71 lines at `howl-linux-host/src/input/input.zig:256-324`.
- The bounded input ring asserts capacity relations at `howl-linux-host/src/input/input.zig:11-15` and runtime ring invariants at `howl-linux-host/src/input/input.zig:56-59`.
- The bounded SDL burst loop is explicit at `howl-linux-host/src/input/input.zig:242-254`, but event drop/backpressure remains silent at `howl-linux-host/src/input/input.zig:354-360`.

## Boundary Map: `terminal/context.zig`

### Fields

- `term: HowlTerm` at `howl-linux-host/src/terminal/context.zig:124` belongs to `terminal/term.zig` as the shared terminal aggregate and mutex owner; `context.zig` may contain the per-tab instance but should not absorb behavior that belongs to PTY, VT, or render retained owners.
- `progress: pty_wait_thread.State` at `howl-linux-host/src/terminal/context.zig:125` belongs to `terminal/pty/wait_thread.zig`; `context.zig` only wires the per-terminal wait state into init/deinit and owner-thread wake acknowledgement.
- `live: bool` at `howl-linux-host/src/terminal/context.zig:126` belongs to PTY session lifecycle truth in `terminal/pty/session.zig`; `context.zig` may cache it only as lifecycle containment for init/deinit.
- `term_texture: render_c.HowlRenderHostSurface` at `howl-linux-host/src/terminal/context.zig:127` belongs to the window render-surface host-surface realization owner currently implemented in `window/term_texture.zig`.
- `render_surface_textures: term_texture.RenderResourceTextures` at `howl-linux-host/src/terminal/context.zig:128` belongs to the window render-surface GL resource realization owner currently implemented in `window/term_texture.zig`.
- `render_surface_submit_diagnostics` and `render_surface_submit_diagnostics_logged` at `howl-linux-host/src/terminal/context.zig:129-130` belong to a terminal render-submit diagnostics owner. They do not belong in input, PTY, VT, or GL resource owners.
- `conf: *const TerminalConfig` at `howl-linux-host/src/terminal/context.zig:131` is config dependency injection from `config/terminal.zig`; `context.zig` should read policy but not parse or own config.
- `input: *HostInput` at `howl-linux-host/src/terminal/context.zig:132` is a wake/redraw dependency into the input owner. The actual input queues and SDL event policy belong to `input/input.zig`.
- `title_buf` and `title_len` at `howl-linux-host/src/terminal/context.zig:133-134` belong to terminal title adaptation over VT retained state, currently retained inside the per-terminal host context.
- `geometry: surface_layout.State` at `howl-linux-host/src/terminal/context.zig:135` belongs to `terminal/render/surface_layout.zig`.
- `font_size_px` and `default_font_size_px` at `howl-linux-host/src/terminal/context.zig:136-137` belong to `terminal/render/font_size.zig` as render ABI font-size transition state.
- `window_focused` and `widget_focused` at `howl-linux-host/src/terminal/context.zig:138-139` belong to per-terminal host focus adaptation, with VT focus publication delegated through `terminal/vt/input.zig`.
- `scrollbar` at `howl-linux-host/src/terminal/context.zig:140` belongs to `terminal/scrollbar.zig`, which adapts VT scroll state to the host scrollbar owner.
- `link_cursor_active` and `hovered_link_cell` at `howl-linux-host/src/terminal/context.zig:141-142` belong to `terminal/links.zig`.
- `selection_anchor` and `selection_drag_active` at `howl-linux-host/src/terminal/context.zig:143-144` belong to `terminal/selection.zig`.
- `hover_publish_pending` at `howl-linux-host/src/terminal/context.zig:145` belongs to the VT visible-source publication boundary in `terminal/vt/surface.zig`, with link-hover decoration as an input.
- `cursor_blink` at `howl-linux-host/src/terminal/context.zig:146` belongs to `terminal/cursor_blink.zig`.

### Functions

- `init(...)`, `initial(...)`, `deinit(...)`, `initTerm(...)`, `startRuntime(...)`, `launchConfig(...)`, `renderInit(...)`, and `initTermState(...)` at `howl-linux-host/src/terminal/context.zig:148-214`, `460-492`, and `1397-1435` belong to the per-terminal host integration owner because they stitch PTY, VT, render, wait-thread, and config ABIs without changing ABI semantics.
- `resize(...)`, `maybeCommitGridResize(...)`, `syncSurfaceLayout(...)`, `surfaceLayoutSnapshot(...)`, `maybeCommitGridResizeLocked(...)`, `initSurfaceLayout(...)`, `pixelToCol(...)`, `pixelToRow(...)`, and `assertRenderInit(...)` at `howl-linux-host/src/terminal/context.zig:216-231`, `589-592`, and `1450-1515` belong to `terminal/render/surface_layout.zig` except for thin call-through methods exposed by the per-terminal host context.
- `paste(...)`, `drainTextInputFastPath(...)`, `drainTextInputFastPathWith(...)`, `drainPointerAndUiInput(...)`, `drainPointerAndUiInputWith(...)`, `publishTerminalBytes(...)`, `publishTerminalKey(...)`, `publishTerminalMouse(...)`, `terminalOwnsMouse(...)`, `handleTextInputFastPathEvent(...)`, and `handlePointerAndUiInputEvent(...)` at `howl-linux-host/src/terminal/context.zig:232-274`, `1255-1295`, and `1553-1625` belong to a terminal input adapter boundary over `terminal/vt/input.zig`, `terminal/selection.zig`, `terminal/links.zig`, and `terminal/scrollbar.zig`. They must not move into `input/input.zig` because SDL intake and VT/PTY publication are separate host boundaries.
- `handleScrollInput(...)`, `wantsPassiveHoverWake(...)`, `ScrollMouseOutcome`, `ScrollVisualState`, and `ContextOps.handleScrollMouse(...)` at `howl-linux-host/src/terminal/context.zig:275-281` and `1305-1350` belong to `terminal/scrollbar.zig` as terminal-specific scrollbar adaptation.
- `wantsLinkHover(...)`, `setWindowFocused(...)`, `setWidgetFocused(...)`, `ContextOps.clearHoveredLinkOp(...)`, and `ContextOps.handleHostLinkMouse(...)` at `howl-linux-host/src/terminal/context.zig:283-286`, `328-343`, and `1364-1387` belong to `terminal/links.zig` plus per-terminal focus adaptation.
- `wantsTerminalHoverReporting(...)`, `syncInputFocus(...)`, and focus publication in `setWindowFocused(...)` and `setWidgetFocused(...)` at `howl-linux-host/src/terminal/context.zig:288-292` and `344-347` belong to `terminal/vt/input.zig` as VT focus/mouse reporting consequences.
- `overlaySnapshot(...)` at `howl-linux-host/src/terminal/context.zig:293-298` belongs to the per-terminal host presentation adapter; it should remain a thin aggregation of owner-produced overlays.
- `lifecycleState(...)`, `isAlive(...)`, `ptySnapshot(...)`, `sessionOutcome(...)`, `driveProgress(...)`, and PTY wait acknowledgement in `driveProgress(...)` at `howl-linux-host/src/terminal/context.zig:299-314` and `397-411` belong to `terminal/pty/session.zig`, `terminal/pty/pump.zig`, and `terminal/pty/wait_thread.zig` with `context.zig` only preserving owner-thread sequencing.
- `titleSlice(...)`, `refreshTitle(...)`, `renderSurfaceLabel(...)`, and `WindowClipboardOps`/`applyPendingClipboardWrite(...)` at `howl-linux-host/src/terminal/context.zig:315-327`, `1143-1147`, and `1632-1651` belong to terminal title/clipboard host adapters over VT retained state and window clipboard calls.
- `adjustFontSize(...)`, `toggleStressFontSize(...)`, `resetFontSize(...)`, `syncCursorBlinkCadence(...)`, `resetCursorBlinkActivity(...)`, `nextCursorBlinkWaitMs(...)`, `cursorBlinkShouldAnimate(...)`, `setCursorBlinkVisible(...)`, `applyRenderCursorBlinkVisible(...)`, and `setRenderCursorBlinkVisible(...)` at `howl-linux-host/src/terminal/context.zig:348-383`, `507-525`, and `1484-1488` belong to `terminal/render/font_size.zig` and `terminal/cursor_blink.zig`, with render ABI cursor visibility calls remaining behind the terminal render retained boundary.
- `runtimeObligationDueNow(...)` and `nextRuntimeObligationWaitMs(...)` at `howl-linux-host/src/terminal/context.zig:384-395` belong to the VT retained runtime-obligation adapter in `terminal/vt/retained.zig`; the main loop may query them but must not own VT timing semantics.
- `wantsRenderTurn(...)`, `renderTurn(...)`, `driveRender(...)`, `driveRenderLocked(...)`, `renderAction(...)`, `maybePublishSource(...)`, `prepare(...)`, `takePreparedUpload(...)`, `submitPrepared(...)`, `submitPreparedLocked(...)`, `submitPreparedLockedWith(...)`, `submitStep(...)`, `submitDriveResult(...)`, `notePreparedStep(...)`, `notePresentSubmitted(...)`, `completePresent(...)`, `completePresentLockedWith(...)`, and `VtPresentAckOps` at `howl-linux-host/src/terminal/context.zig:363-455`, `540-563`, `574-615`, `822-864`, and `1233-1253` belong to the terminal render-submit adapter over `terminal/render/retained.zig` and `terminal/vt/surface.zig`. They must preserve the current mutex unlock around backend upload at `howl-linux-host/src/terminal/context.zig:835-837`.
- `ContextSubmitBackend.upload(...)`, `ContextSubmitBackend.uploadRenderSurfaceCommands(...)`, `shouldRealizeRenderSurface(...)`, and `execution(...)` at `howl-linux-host/src/terminal/context.zig:616-723` and `805-821` are split-boundary functions. The decision to upload/submit belongs to the terminal render-submit adapter, but host-surface ensure/upload and GL resource realization belong to the window render-surface owner currently named `window/term_texture.zig`.
- `RenderSurfaceSubmitDiagnostics`, `recordPrepareFailure(...)`, `recordUnsupportedRenderSurfaceShape(...)`, `panicUnsupportedTrustedRenderSurfaceShape(...)`, `trustedUnsupportedRenderSurfaceShapeAction(...)`, `trustedRenderSurfaceUnavailableAction(...)`, `recordRenderSurfaceUnavailable(...)`, `SubmitFailureReason`, `submitFailureReason(...)`, `recordSubmitFailure(...)`, `recordRenderSurfaceRealization(...)`, `recordHostUpload(...)`, `logRenderSurfaceDiagnostics(...)`, `shouldLogRenderSurfaceFailure(...)`, `printRenderSurfaceSummaryDiagnostics(...)`, `printRenderSurfaceIntervalDiagnostics(...)`, `printRenderSurfaceGlDiagnostics(...)`, `printRenderSurfaceFailureDiagnostics(...)`, `renderSurfaceFailureTotal(...)`, and `counterDelta(...)` at `howl-linux-host/src/terminal/context.zig:82-122`, `564-573`, `724-804`, `872-923`, and `940-1231` belong to a terminal render-surface submit diagnostics boundary. Planning a move requires exact test gates because this is intertwined with Lane A failure-policy changes.
- `preparedHandleStable(...)`, `submit(...)`, `renderUs(...)`, `initTextSession(...)`, `initVt(...)`, `deinitVt(...)`, `applyPrimaryFontPath(...)`, `applyFallbackFontPaths(...)`, `renderFontValid(...)`, and `renderCallOk(...)` at `howl-linux-host/src/terminal/context.zig:924-939` and `1437-1539` belong to ABI translation helpers owned by the terminal render/VT init adapter. They must not become public Zig-shaped integration surfaces.

## Boundary Map: `window/term_texture.zig`

### Fields And Types

- `RenderResourceTextures.slots`, `Slot`, and `Slot.State` at `howl-linux-host/src/window/term_texture.zig:24-45` belong to host GL resource realization state for render-surface resources.
- `success_count`, `failure_count`, `failure_bucket_last`, `failure_resource_kind_last`, and `Diagnostics` at `howl-linux-host/src/window/term_texture.zig:27-88` belong to render-surface GL/resource diagnostics, not terminal context diagnostics.
- `FailureBucket`, `TrustedTextureFailureAction`, `trustedTextureFailureAction(...)`, and `trustedTextureMissingFailureAction(...)` at `howl-linux-host/src/window/term_texture.zig:90-99` and `608-629` belong to trusted render-surface failure classification at the host GL realization boundary.
- `RenderSurfaceSummary` at `howl-linux-host/src/window/term_texture.zig:599-606` belongs to render-surface shape classification, not generic terminal texture ownership.

### Functions

- `deinit(...)`, `realizeSurface(...)`, `realizeSurfaceLocked(...)`, `glSampleOk(...)`, `createTexture(...)`, `uploadTexture(...)`, `commitUploadMetadata(...)`, `invalidateUploads(...)`, `retireTexture(...)`, `deleteSlot(...)`, `retireSlot(...)`, and `sampleGlState(...)` at `howl-linux-host/src/window/term_texture.zig:108-210`, `362-462`, `441-462`, `579-597`, and `890-903` belong to the host GL render-resource realization owner.
- `validateSurface(...)`, `validateSurfaceTransition(...)`, `validateCreates(...)`, `validateUploads(...)`, `validateRetires(...)`, `noteCreate(...)`, `noteUpload(...)`, `noteRetire(...)`, `validateSurfaceOrder(...)`, `validateCommands(...)`, `validateSurfaceOrderStatic(...)`, `validateCommandsStatic(...)`, `spanCountValid(...)`, `resourceFormatValid(...)`, `uploadValidForSlot(...)`, `rectFitsResource(...)`, `findCreate(...)`, `retireForResource(...)`, `findUploadStatic(...)`, `commandUsesResource(...)`, `resourceHasFutureUpload(...)`, and `glyphCommandValid(...)` at `howl-linux-host/src/window/term_texture.zig:212-328`, `329-361`, `502-513`, `631-889`, and `2449-2480` are duplicated render-surface contract validation pressure. True contract truth belongs to the render ABI/product and host retained render validation in `terminal/render/retained.zig`; this window owner should only enforce trusted-host preconditions and GL-realization safety.
- `find(...)`, `textureIdFor(...)`, `textureSlotFor(...)`, `findEmpty(...)`, `findValue(...)`, and `rollbackCreates(...)` at `howl-linux-host/src/window/term_texture.zig:463-501` belong to the GL resource-slot owner.
- `recordSurfaceShape(...)`, `recordFailure(...)`, `recordFailureForResource(...)`, `recordFailureCounters(...)`, and `refreshSlotDiagnostics(...)` at `howl-linux-host/src/window/term_texture.zig:514-578` belong to render-surface GL/resource diagnostics.
- `ensureSurface(...)` at `howl-linux-host/src/window/term_texture.zig:2049-2079` belongs to host-surface texture realization. It is not terminal context behavior.
- `uploadRenderSurfaceFillOnly(...)`, `uploadRenderSurfaceFillPatch(...)`, `uploadRenderSurfaceSprites(...)`, `uploadRenderSurfaceSpritePatch(...)`, `uploadRenderSurfaceGlyphs(...)`, `uploadRenderSurfaceGlyphPatch(...)`, `uploadRenderSurfaceCommands(...)`, `uploadFillCommand(...)`, `drawFillCommand(...)`, `drawSpriteCommand(...)`, `drawGlyphCommand(...)`, `drawQuad(...)`, `drawTexturedQuad(...)`, `ndcX(...)`, `ndcY(...)`, and `unpackRenderSurfaceRgba(...)` at `howl-linux-host/src/window/term_texture.zig:2081-2705` belong to host GL upload/draw realization for render-surface commands.
- `renderSurfaceFillOnly(...)`, `renderSurfaceFillPatch(...)`, `renderSurfaceFillCoverage(...)`, `renderSurfaceSummary(...)`, `renderSurfaceSprite(...)`, `renderSurfaceSpritePatch(...)`, `renderSurfaceGlyphs(...)`, `renderSurfaceGlyphPatch(...)`, `renderSurfaceFillCommand(...)`, `renderSurfaceSpriteCommand(...)`, `renderSurfaceGlyphCommand(...)`, and `renderSurfaceFullClear(...)` at `howl-linux-host/src/window/term_texture.zig:2243-2488` belong to host render-surface shape classification. They are not GL resource lifecycle and should not be hidden under a name that says only `term_texture`.
- `fillCommandFitsHostRow(...)`, `trustedFillHostRowFailureAction(...)`, `spriteUploadCoversCommand(...)`, and `glyphCommandHasFutureUpload(...)` at `howl-linux-host/src/window/term_texture.zig:2531-2602` belong to trusted upload/draw invariant checks at the host GL realization boundary.

### True Name Boundary

- `window/term_texture.zig` is misnamed but not safe to rename in this slice. Its true boundary is host render-surface GL realization: host-surface texture allocation, render-resource texture slots, trusted render-surface shape classification, GL upload/draw execution, and realization diagnostics.
- Candidate names require orchestration because they affect a large file with tests, public imports from `terminal/context.zig`, and Lane A failure-policy work. Non-generic source-backed candidates are `window/render_surface.zig` or `window/render_surface_gl.zig`; choosing the exact name is a main-agent planning decision, not researcher invention.

## Boundary Map: `main.zig`

### Fields And Types

- `App.conf`, `feed_record_path`, and `io` at `howl-linux-host/src/main.zig:75-77` belong to app bootstrap/runtime dependency ownership.
- `App.window` at `howl-linux-host/src/main.zig:78` belongs to `window/window.zig`; `main.zig` should orchestrate but not own SDL/GL window internals.
- `App.tab_bar`, `App.tabs`, and `App.active_tab_idx` at `howl-linux-host/src/main.zig:79-81` belong to tab-bar and tab-slot owners, with active-tab choice as app orchestration state.
- `App.input` and `terminal_input_admitted` at `howl-linux-host/src/main.zig:82-83` belong to input intake and app-loop admission respectively; terminal input admission is a main-loop pacing fact, not a terminal owner fact.
- `App.pending_terminal_present` at `howl-linux-host/src/main.zig:84` belongs to app/window present orchestration. Current source does not use this field in product code, so planning must either prove future use or remove it in an explicit app-present cleanup slice.
- `App.frame_pacing` at `howl-linux-host/src/main.zig:85` belongs to `window/pacing.zig`.
- `App.accounting` at `howl-linux-host/src/main.zig:86` belongs to `app/process_accounting.zig`.
- `App.loop_turn_count` at `howl-linux-host/src/main.zig:87` belongs to app loop diagnostics.

### Functions

- `main(...)`, `startForTest(...)`, `start(...)`, `initVideo(...)`, `loadConfig(...)`, `createWindow(...)`, `initInput(...)`, `applyChildEnvironmentPolicy(...)`, and `setCurrentThreadName(...)` at `howl-linux-host/src/main.zig:90-219` and `897-900` belong to app bootstrap. `start(...)` is 72 lines and should be split by true owner only if a worker slice explicitly owns startup allocation/deinit order.
- `runLoop(...)`, `runLoopTurn(...)`, `computeLoopAdmission(...)`, `maybeLogLoopTurn(...)`, `collectLoopDebugFacts(...)`, `collectLoopPending(...)`, `collectLoopPendingFromDebug(...)`, `quitRequested(...)`, `pumpWindowEvents(...)`, `applyHostOwnedMutations(...)`, `deriveRedrawRenderIntent(...)`, `loopWaitMs(...)`, `loopWaitMsWith(...)`, `minRuntimeObligationWaitMs(...)`, `minRuntimeObligationWaitMsWith(...)`, `minOptionalWaitMs(...)`, and `takeTerminalInputAdmission(...)` at `howl-linux-host/src/main.zig:221-321` and `334-519` belong to the app control spine. They must remain centralized and bounded.
- `activeTabNeedsRenderTurn(...)`, `tabsHavePendingWake(...)`, `tabsPendingWakeCount(...)`, `tabsHavePendingRuntimeObligation(...)`, `tabsHavePendingRuntimeObligationWith(...)`, `tabsPendingRuntimeObligationCount(...)`, `tabsPendingRuntimeObligationCountWith(...)`, `driveRuntimeProgress(...)`, `driveTerminalProgress(...)`, `driveTabRuntimeTurn(...)`, `activeTabProblem(...)`, `activeTab(...)`, `activeContext(...)`, and `tabIndexInRange(...)` at `howl-linux-host/src/main.zig:360-405`, `430-433`, `527-556`, and `778-903` belong to app tab-runtime orchestration over bounded tab slots. They should not move into terminal owners because they iterate all tabs and make app-level active-tab decisions.
- `configureInputPolicies(...)`, `applyFocusChange(...)`, `forwardTerminalInput(...)`, `forwardTerminalInputFlow(...)`, `mergeDrainInputOutcome(...)`, and `applyWindowResize(...)` at `howl-linux-host/src/main.zig:204-216` and `480-526` belong to app-level routing between input, window, and active terminal. They preserve the SDL input/terminal publication split.
- `syncActiveBlinkCadence(...)`, `activeBlinkWaitMs(...)`, and runtime wait merging at `howl-linux-host/src/main.zig:442-479` belong to the app loop deadline owner while querying terminal/cursor owners for facts.
- `render(...)`, `syncActiveWindowTitle(...)`, `RenderSnapshot`, `renderSnapshot(...)`, `derivePresentPlan(...)`, `derivePresentReason(...)`, `submitPresent(...)`, `submitPresentWith(...)`, `recordPresentSubmission(...)`, `recordPresentSubmissionFor(...)`, `drainPresentComplete(...)`, `accountingRenderStep(...)`, and `accountingPresentReason(...)` at `howl-linux-host/src/main.zig:561-666` belong to app present orchestration over `app/present.zig`, `window/present.zig`, `window/pacing.zig`, and process accounting. Rendering the active terminal and snapshot creation are app orchestration; GL draw remains window-present ownership.
- `resizeTerminals(...)`, `setWindowFocused(...)`, `handleBindingAction(...)`, `openTab(...)`, `closeActiveTab(...)`, `selectRelative(...)`, `selectTab(...)`, `syncTerminalFocus(...)`, `tabTitles(...)`, `pasteIntoActiveTab(...)`, and `destroyTabs(...)` at `howl-linux-host/src/main.zig:557-560` and `761-896` belong to app tab lifecycle and active-tab UX orchestration. PTY/VT/render ABI creation remains inside `TerminalContext.init(...)`.

## Boundary Map: `input/input.zig`

### Fields And Types

- `FixedRing(...)`, `input_events`, and `binding_buf` at `howl-linux-host/src/input/input.zig:11-60` and `89-92` belong to bounded input queue ownership.
- `Signal = window.EventSignal` at `howl-linux-host/src/input/input.zig:64` is a wake/event-loop signal dependency from the current `input/window.zig` owner.
- `Keys`, `Mouse`, `Bindings`, `Key`, `Mod`, `Buttons`, and `Event` at `howl-linux-host/src/input/input.zig:65-75` belong to input vocabulary aggregation over `input/keys.zig` and `input/mouse.zig`.
- `HostMousePolicy` and `TerminalMousePolicy` at `howl-linux-host/src/input/input.zig:76-87` belong to input intake policy, with app/terminal owners supplying policy facts.
- `scroll_pages`, `redraw_requested`, `window_geometry_changed`, `window_focus_changed`, `last_mouse_x`, `last_mouse_y`, mouse policy fields, `current_mods`, `mouse_motion_enabled`, and `mouse_button_down` at `howl-linux-host/src/input/input.zig:90-104` belong to input intake state.
- `window_state` at `howl-linux-host/src/input/input.zig:105` belongs to the SDL wake/timer owner currently misnamed `input/window.zig`. `input/input.zig` may contain it as a field but should not own wake event registration semantics.

### Functions

- `Input.init(...)`, `setBindings(...)`, `setHostMousePolicy(...)`, `setTerminalMousePolicy(...)`, `updateMouseMotionEvents(...)`, `drainRedrawRequested(...)`, `drainInputEvent(...)`, `drainScrollPages(...)`, `drainBindingAction(...)`, `hasPendingOwnerWork(...)`, `drainWindowGeometryChanged(...)`, `drainWindowFocusChanged(...)`, `wakeWindow(...)`, `requestRedraw(...)`, and `keyFromLabel(...)` at `howl-linux-host/src/input/input.zig:107-227` belong to input intake state and app-loop owner-work interface.
- `pumpWindow(...)`, `waitAndDrainEvents(...)`, `drainPendingEvents(...)`, and `processEvent(...)` at `howl-linux-host/src/input/input.zig:201-324` belong to SDL event intake and bounded per-turn classification. `processEvent(...)` is 71 lines and has zero assertions.
- `appendBytesEvent(...)`, `appendByteEvent(...)`, `appendKeyEvent(...)`, `appendMouseEvent(...)`, `appendInputEvent(...)`, and `appendBindingAction(...)` at `howl-linux-host/src/input/input.zig:327-363` belong to bounded queue publication. Silent drop on full queue at `howl-linux-host/src/input/input.zig:354-360` is a policy proof gap from the accepted reference cache.
- `processKeyDown(...)`, `processKeyUp(...)`, `sdlKey(...)`, `sdlLetterKey(...)`, `sdlDigitKey(...)`, `sdlFunctionKey(...)`, `sdlNamedKey(...)`, `sdlKeypadKey(...)`, and `sdlMods(...)` at `howl-linux-host/src/input/input.zig:364-413` and `525-677` belong to SDL-key to host-key conversion and binding action generation. The canonical key/binding vocabulary remains in `input/keys.zig`.
- `processMouseMotion(...)`, `updateModifierState(...)`, `maybeQueueModifierMouseMove(...)`, `processMouseButtonDown(...)`, `processMouseButtonUp(...)`, `processMouseWheel(...)`, `sdlMouseButton(...)`, `modSubset(...)`, and `sdlButtons(...)` at `howl-linux-host/src/input/input.zig:415-524` and `678-702` belong to SDL mouse conversion and passive-motion policy. The mouse event types remain in `input/mouse.zig`.
- `flushAllSdlEvents(...)`, `pushShiftPageUpEvent(...)`, and `singleByteInput(...)` at `howl-linux-host/src/input/input.zig:703-719` are test helpers and should stay local unless tests move with an owner split.

## Boundary Map: `window/present.zig`

### Fields And Types

- `PresentToken` at `howl-linux-host/src/window/present.zig:7` belongs to the window present token contract consumed by app present orchestration.
- `PresentProofStats`, `PresentProofSnapshot`, `PresentProofDelta`, and `FramebufferObservation` at `howl-linux-host/src/window/present.zig:9-37` and `60-63` belong to test/proof capture, not normal present submission.
- `PresentDiagnostics` and `Readiness` at `howl-linux-host/src/window/present.zig:39-58` belong to window present diagnostics and GL readiness checking.
- `State(c)` fields `window`, `gl_context`, `next_present_token`, `submitted_present`, `completed_present`, and `diagnostics` at `howl-linux-host/src/window/present.zig:65-81` belong to present state.
- `State(c)` fields `tab_texture_id`, `tab_cache_valid`, `tab_cache_w`, `tab_cache_h`, and `tab_cache_hash` at `howl-linux-host/src/window/present.zig:69-73` belong to a tab-bar GL texture cache boundary inside window presentation. This is broader than the filename but still within window GL presentation.
- `State(c)` fields `proof_capture_requested`, `proof_probe_rect`, and `last_present_proof` at `howl-linux-host/src/window/present.zig:74-76` belong to a test-only present-proof capture boundary.

### Functions

- `flags(...)`, `init(...)`, and `deinit(...)` at `howl-linux-host/src/window/present.zig:84-124` belong to SDL/GL context present lifecycle.
- `submitPresent(...)` and `drainPresentComplete(...)` at `howl-linux-host/src/window/present.zig:126-188` belong to window present submission and synchronous token completion. The accepted reference cache says this is acceptable only as current ABI-harness simplification if treated as a host contract test seam.
- `requestPresentProof(...)`, `presentProofSnapshot(...)`, `capturePresentProof(...)`, `clipRectToBounds(...)`, `observeTexture(...)`, `observeFramebufferBytes(...)`, `compareFramebufferBytes(...)`, `rgbaLen(...)`, `observePixels(...)`, `hasNonZeroByte(...)`, `hasNonClearPixel(...)`, `pixelDiffersFromClear(...)`, and `channelDiffers(...)` at `howl-linux-host/src/window/present.zig:190-195` and `388-534` belong to test/proof capture. They should not complicate the normal present owner path.
- `recordReadiness(...)`, `readiness(...)`, `recordSwap(...)`, `elapsedUs(...)`, `logPresentDiagnostics(...)`, and `shouldLogPresentFailure(...)` at `howl-linux-host/src/window/present.zig:198-281` belong to present diagnostics.
- `updateTabCacheIfNeeded(...)`, `drawCachedTabBar(...)`, `ensureTabTexture(...)`, `releaseTabCache(...)`, `setTextureParams(...)`, and `hashTabBarState(...)` at `howl-linux-host/src/window/present.zig:283-343` and `536-547` belong to tab-bar GL texture caching under the window present owner.
- `emptyPresentProofStats(...)`, `emptyPresentProofSnapshot(...)`, `emptyPresentProofDelta(...)`, `emptyFramebufferObservation(...)`, `FakeC`, `testState(...)`, and `testFrame(...)` at `howl-linux-host/src/window/present.zig:345-603` are proof/test helpers and should move only with present-proof tests.

## Misplaced Owner Map: App Wake Bridge

- Previous current name: `input/window.zig`.
- Intermediate name after the first rename: `input/wake.zig`.
- Corrected judgment: `input/wake.zig` is a rejected intermediate placement. It fixed the false `window` noun, but kept app-loop wake, quit, time, and semaphore ownership under the input namespace.
- Current facts: `howl-linux-host/src/input/wake.zig` owns `EventSignal`, `State.quit_requested`, `State.wake_event_type`, SDL wake event registration, wake event pushing, quit requests, SDL monotonic ticks, quit timer, wake semaphore wrappers, and the quit timer callback at `howl-linux-host/src/input/wake.zig:6-98`.
- `input/` owns SDL event intake, key/mouse conversion, bounded input queues, input policy, and publication of input events. It does not own the app event loop's wake primitive, quit lifecycle, clock source, or cross-thread wake semaphore wrappers.

### Alacritty Reference Evidence

- Alacritty creates the host event loop and proxy in app bootstrap at `alacritty/alacritty/src/main.rs:137-142` with `EventLoop::<Event>::with_user_event()` and `window_event_loop.create_proxy()`.
- Alacritty `Processor` owns event-loop infrastructure, scheduler, windows, and the event-loop proxy at `alacritty/alacritty/src/event.rs:87-101`, and wires `Scheduler::new(proxy.clone())` at `alacritty/alacritty/src/event.rs:103-144`.
- Alacritty wraps `EventLoopProxy<Event>` in `EventProxy` at `alacritty/alacritty/src/event.rs:2072-2093`, where it implements terminal event delivery back to the app event loop.
- Alacritty handles terminal wake delivery through app event processing at `alacritty/alacritty/src/event.rs:409-415`, where `TerminalEvent::Wakeup` marks the window dirty and requests redraw.
- Alacritty's PTY event loop sends `Event::Wakeup` and `Event::ChildExit` from `alacritty/alacritty_terminal/src/event_loop.rs:166-168`, `244-248`, and `263-269`.
- Alacritty's PTY loop cross-thread sender owns message wake through `EventLoopSender::send(...)` at `alacritty/alacritty_terminal/src/event_loop.rs:383-393`, sending `Msg` and calling `poller.notify()`.
- Alacritty shutdown requests are app/event-loop facts: `Msg::Shutdown` is defined at `alacritty/alacritty_terminal/src/event_loop.rs:29-40`, `drain_recv_channel(...)` stops on shutdown at `alacritty/alacritty_terminal/src/event_loop.rs:91-97`, and `EventType::Shutdown` calls `event_loop.exit()` at `alacritty/alacritty/src/event.rs:392-394`.
- Alacritty signal polling converts SIGINT/SIGTERM into app shutdown at `alacritty/alacritty/src/polling/signal.rs:26-30`.
- Alacritty timers and deadlines live in app scheduling, not input: `Topic`, `Timer`, and `Scheduler` are defined at `alacritty/alacritty/src/scheduler.rs:24-47`; `Scheduler::update()` emits due events and returns the next deadline at `alacritty/alacritty/src/scheduler.rs:54-73`; `Processor::about_to_wait(...)` sets `ControlFlow::WaitUntil(instant)` or `ControlFlow::Wait` at `alacritty/alacritty/src/event.rs:466-490`.
- Alacritty uses `std::time::Instant` directly for monotonic time in scheduler and PTY timeout paths at `alacritty/alacritty/src/scheduler.rs:59`, `alacritty/alacritty/src/scheduler.rs:77`, and `alacritty/alacritty_terminal/src/event_loop.rs:231`. Input uses `Instant::now()` only locally for click timing at `alacritty/alacritty/src/input/mod.rs:633-635`; input does not own a global clock provider.

### Howl User Evidence

- `howl-linux-host/src/main.zig:6` imports the file as `InputWake`, and uses `startQuitTimer(...)`, `stopQuitTimer(...)`, and `nowNs()` for duration shutdown, app-loop accounting, frame pacing, and present timing at `howl-linux-host/src/main.zig:149-168`, `236`, `260`, and `617`.
- `howl-linux-host/src/input/input.zig:4`, `64`, `105`, and `201-218` embeds the wake state only because SDL event pumping is the mechanism used to wake the app loop. The input owner should not define the wake owner.
- `howl-linux-host/src/terminal/pty/wait_thread.zig:4`, `12`, `19`, `24`, `99`, and `109` uses wake semaphore wrappers for owner-thread wake acknowledgement. The PTY wait thread remains wait-only and does not own the app loop wake primitive.
- `howl-linux-host/src/terminal/context.zig:3`, `234`, `405`, `620`, `624`, `823`, `936`, `1559`, `1565`, `1598`, and `1620` uses `nowNs()` for terminal activity, cursor blink, render-surface, submit, and input timing.
- `howl-linux-host/src/terminal/scrollbar.zig:2` and `60` uses `nowNs()` for scrollbar hover/fade timing.
- `howl-linux-host/src/terminal/render/surface_layout.zig:2` and `76` uses `nowNs()` for resize timing.

### Correct Boundary

- True boundary: app-loop wake/time/shutdown bridge over SDL.
- Source-backed true name: `app/wake.zig`.
- Source-backed import alias: `AppWake`.
- Boundary of `app/wake.zig`: `EventSignal`, `State`, `nowNs()`, quit timer helpers, wake semaphore helpers, and the timer callback. It may import SDL. It must not own `Input` queues, key/mouse conversion, `Window.State`, GL presentation, PTY session semantics, or PTY wait-thread policy.
- ABI consequence: none. This file is host-only SDL integration and does not touch `howl-pty`, `howl-vt`, or `howl-render` C ABIs.
- Wake discipline consequence: preserve `terminal/pty/wait_thread.zig` as wait-only. The wait thread may continue to call host wake through `AppWake`, but must not process SDL events or terminal runtime work.

## Rejected Corrective Implementation Split

Rejected: moving `input/wake.zig` to `app/wake.zig` is not acceptable as a final or next owner shape. It only moves the false owner from one directory to another while leaving app-loop wait/poll/wake split across input and app-adjacent helpers.

Rejected: a cosmetic first slice that only moves the current wake bridge to `event_loop.zig` is also not acceptable. The first implementation slice must create a real event-loop boundary and a concrete tracked `polling/` owner file, and must remove SDL wait/poll/wake ownership from input in the same slice.

### Superseded App-Wake Proposal

Ready corrective split: move `howl-linux-host/src/input/wake.zig` to `howl-linux-host/src/app/wake.zig`, update host-only imports and references from `InputWake` to `AppWake`, and keep the same functions and tests.

Why this split is source-backed:

- Alacritty places wake/proxy, shutdown, timer/deadline, and cross-thread wake delivery in app/event-loop infrastructure, not input.
- Current Howl source confirms every product symbol in `input/wake.zig` is wake/time/timer/semaphore-related at `howl-linux-host/src/input/wake.zig:6-98`.
- The split does not move behavior across C ABI boundaries and does not change PTY, VT, render, or GL semantics.
- The split preserves the centralized app control spine: `main.zig` still computes admission, calls input pumping, drives runtime progress, and handles present in `howl-linux-host/src/main.zig:230-288`.
- The split preserves bounded input turns: `input/input.zig` still owns one bounded SDL burst per turn at `howl-linux-host/src/input/input.zig:242-254`.
- The split preserves owner-thread wake discipline: `terminal/pty/wait_thread.zig` remains wait-only, while wake event delivery remains an app-loop concern.

Exact files for this corrective split:

- `howl-linux-host/src/input/wake.zig` to `howl-linux-host/src/app/wake.zig`.
- Update imports in all current readers: `howl-linux-host/src/main.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/input/input.zig`, `howl-linux-host/src/terminal/scrollbar.zig`, `howl-linux-host/src/terminal/render/surface_layout.zig`, and `howl-linux-host/src/terminal/pty/wait_thread.zig`.
- Update local aliases from `InputWake` to `AppWake` in `main.zig`, `terminal/context.zig`, `terminal/scrollbar.zig`, `terminal/render/surface_layout.zig`, and `terminal/pty/wait_thread.zig`.
- Update the `input/input.zig` same-directory `wake` alias to an app wake import. The field name `window_state` is stale but renaming it requires a separate promoted slice unless the worker proves the rename is required for compilation.
- Preserve and run tests already attached to impacted files: `main.zig`, `input/input.zig`, `terminal/context.zig`, and `terminal/pty/wait_thread.zig`.
- `terminal/scrollbar.zig` and `terminal/render/surface_layout.zig` have no local test blocks in the read source; they are covered by the full host test build and by existing context/layout behavior tests that compile through their imports.
- No integration or ABI test wiring changes are needed for this move-only split.

Required verification for this corrective split:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan must print `TOTAL 0` for lines over 190 chars.

## Replacement: Event Loop And Polling Owner Shape

The accepted target is not a move-only rename. The target is a source-backed event-loop owner plus concrete polling owner shape.

### Source Evidence

- Alacritty's PTY event loop owns PTY polling and cross-thread sender wake through `Poller`, `EventLoopSender`, and `poller.notify()` at `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:46-55`, `84-86`, `205-324`, and `383-393`.
- Alacritty's app event owner owns the app event-loop proxy, scheduler, windows, and wait deadline policy at `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:87-101`, `103-144`, and `466-490`.
- Alacritty's `polling/` directory is concrete behavior, not a placeholder: `IoListener` owns signal and IPC listeners, `Events`, and `Poller` at `utils/dev_references/terminals/alacritty/alacritty/src/polling/mod.rs:19-34`, `36-92`.
- Alacritty signal polling turns SIGINT/SIGTERM into app shutdown at `utils/dev_references/terminals/alacritty/alacritty/src/polling/signal.rs:12-30`.
- Alacritty IPC polling turns accepted socket messages into app events at `utils/dev_references/terminals/alacritty/alacritty/src/polling/ipc.rs:23-91`.
- Current Howl `howl-linux-host/src/input/wake.zig:6-98` owns `EventSignal`, quit state, SDL wake event registration, SDL event push, SDL ticks, quit timer, and wake semaphore wrappers.
- Current Howl `howl-linux-host/src/input/input.zig:105`, `201-218`, and `228-254` embeds wake state and owns SDL wait/poll/wake through `window_state`, `pumpWindow`, `waitAndDrainEvents`, `drainPendingEvents`, and `wakeWindow`.
- Current Howl `howl-linux-host/src/terminal/pty/wait_thread.zig:3-19` and `116-119` targets input for cross-thread wake through `wake_input: ?*HostInput` and `input.wakeWindow()`.
- Current Howl app loop already owns loop admission and centralized control flow at `howl-linux-host/src/main.zig:230-288`.

### Correct Target Owner Shape

- `howl-linux-host/src/event_loop.zig` owns host event-loop wake, quit, SDL wake event type, pump wait/poll policy, and app-loop clock/timer facade.
- `howl-linux-host/src/polling/sdl.zig` owns direct SDL polling/time/timer/semaphore C calls used by the event-loop owner and PTY wait-thread acknowledgement.
- No `polling/signal.zig` now. Howl has no current signal behavior to preserve.
- No `polling/ipc.zig` now. Howl has no current IPC behavior to preserve.

### First Worker-Ready Slice

Allowed files:

- `howl-linux-host/src/event_loop.zig`
- `howl-linux-host/src/polling/sdl.zig`
- `howl-linux-host/src/input/wake.zig`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/render/surface_layout.zig`
- `howl-linux-host/src/test/host.zig`
- `howl-linux-host/src/test_root.zig`

Required shape:

- Create `event_loop.zig` with `Signal`, `State`, `init`, `initWakeEventType`, `quitRequested`, `requestQuit`, `wake`, `pumpInput`, `nowNs`, quit timer wrappers, and wake semaphore wrappers.
- Create `polling/sdl.zig` with concrete SDL wrappers for event registration, push, wait, wait timeout, poll, ticks, quit timer, and wake semaphore operations.
- Delete `input/wake.zig` after its behavior is moved.
- Remove `window_state`, `pumpWindow`, `waitAndDrainEvents`, `drainPendingEvents`, and `wakeWindow` from `input/input.zig`.
- Keep input classification and bounded queues in `input/input.zig`; expose only the minimal event-classification entry needed by `event_loop.State.pumpInput(...)`.
- Add `event_loop: EventLoop.State` to `main.App`.
- Initialize event-loop wake type in app startup instead of through `input.window_state`.
- Change `pumpWindowEvents(...)` to call `app.event_loop.pumpInput(app.input, admission.wait_for_window, admission.wait_ms)`.
- Change `quitRequested(...)` to query `app.event_loop.quitRequested()`.
- Change all timing imports from `InputWake.nowNs()` to `EventLoop.nowNs()`.
- Change PTY wait thread state from `wake_input: ?*HostInput` to `wake_event_loop: ?*EventLoop.State`.
- Change wait-thread real wake op to call `event_loop.wake()`, not `input.wakeWindow()`.
- Pass `*EventLoop.State` through terminal context initialization because PTY wait-thread wake must target the event-loop owner in this same slice.

Required behavior:

- Wake SDL events are consumed by the event-loop owner and are not delivered to input classification.
- Quit SDL events set event-loop quit state and return `.quit`.
- SDL polling remains bounded to `max_sdl_events_per_turn`.
- Input queue behavior, key/mouse/text conversion, focus/geometry flags, and binding behavior remain unchanged.
- PTY wait-thread remains wait-only and still coalesces wake requests until owner-thread acknowledgement clears `wake_pending`.

Required tests:

- Event-loop test: wake event is consumed and not classified as input.
- Event-loop test: quit event sets quit state and returns `.quit`.
- Event-loop test: bounded drain does not exceed `max_sdl_events_per_turn`.
- Event-loop test: `requestQuit()` sets quit and pushes wake through fake ops.
- Update existing `terminal/pty/wait_thread.zig` tests to prove wake coalescing and acknowledgement target the event-loop wake seam.

Verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan must print `TOTAL 0` for lines over 190 chars.

Stop conditions:

- Stop if `event_loop.zig` starts owning terminal runtime progress, PTY read/write, VT mutation, render submission, presentation, tabs, or window GL state.
- Stop if `polling/` gains signal or IPC files without current product behavior and tests.
- Stop if PTY wait-thread still targets input wake after the slice.
- Stop if input still owns SDL wait/poll/wake or wake event registration.
- Stop if any C ABI changes appear.

## Not Ready For Worker Split Without Orchestration

- `terminal/context.zig` render-submit diagnostics extraction is not ready. The true boundary is identifiable, but the exact owner name, allowed files, and test gates must be promoted because Lane A failure-policy changes are already interleaved in the same functions at `howl-linux-host/src/terminal/context.zig:616-804` and diagnostics at `howl-linux-host/src/terminal/context.zig:82-122`, `940-1231`.
- `window/term_texture.zig` rename/extraction is not ready. The true boundary is host render-surface GL realization, but the exact name (`window/render_surface.zig` versus `window/render_surface_gl.zig` or another accepted name), source-order repair, tests, and relationship to `terminal/render/retained.zig` validation must be orchestrated.
- `main.zig` app-control split is not ready. It has a valid centralized loop spine at `howl-linux-host/src/main.zig:230-288`; extracting lifecycle/present/tab helpers without weakening that spine needs a promoted slice with exact allowed files and tests.
- `input/input.zig` event-classification split is not ready. `processEvent(...)` is 71 lines and over the limit by one line at `howl-linux-host/src/input/input.zig:256-324`, but event drop/backpressure policy at `howl-linux-host/src/input/input.zig:354-360` remains a product decision from the reference-cache proof gaps.
- `window/present.zig` present-proof or tab-cache extraction is not ready. The current synchronous present-token model is acceptable only as current harness simplification per accepted reference cache; deciding whether proof capture or tab cache becomes a separate owner needs an explicit slice.

## Readiness Judgment

Worker-ready for one narrow implementation split only: rename `input/window.zig` to `input/wake.zig` and update the complete impacted import/alias set listed above.

Not ready for broader ownership cleanup. The broader maps are source-backed, but implementation would require main-agent orchestration for exact owner names, allowed files, test gates, and Lane A interaction.

## Blockers

- Exact owner name for the large host render-surface GL realization file is not accepted.
- Exact owner name and test gate for terminal render-submit diagnostics are not accepted.
- Input queue overflow/backpressure policy is not decided.
- Present-token/proof-capture/tab-cache future boundary is not decided.
- Function assertion density is far below TigerBeetle targets in all measured target files.
