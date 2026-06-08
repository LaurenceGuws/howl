# Linux Host Ghostty Lock Wake Sanity Research

## Scope

- This file records a Ghostty sanity check for Howl Linux host lock, wake, render-turn, and surface/runtime ownership.
- Ghostty is a reference for concrete lock/wake failure modes only. This research does not propose importing Ghostty's renderer thread, termio thread, xev loop, app runtime, or mailbox architecture.
- Howl files inspected: `howl-linux-host/src/main.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/pty/pump.zig`, and `howl-linux-host/src/terminal/pty/wait_thread.zig`.
- TigerBeetle pressure applied: bounded turns, explicit ownership, assertions on limits, central owner control flow, and no blocking while holding a contended state lock.

## Ghostty Facts

- `utils/dev_references/terminals/ghostty/src/renderer.zig:1-8` defines renderer ownership as turning internal screen state into output, while assuming platform renderer setup is already done. `utils/dev_references/terminals/ghostty/src/renderer.zig:23-24` exports `Thread` and `State` as distinct renderer concepts.
- `utils/dev_references/terminals/ghostty/src/renderer/State.zig:10-14` makes shared render state readable only while holding `State.mutex`; the mutex protects member values, not the `State` object itself. `utils/dev_references/terminals/ghostty/src/renderer/State.zig:16-31` shows that terminal, inspector, preedit, and mouse state are all under this shared-state discipline.
- `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:32-35` gives the renderer thread a bounded `BlockingQueue(rendererpkg.Message, 64)`. `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:45-48` gives it a cross-thread `wakeup` async handle.
- `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:198-244` starts a renderer thread, arms wake/stop/draw async handlers, and sends an initial wakeup. `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:238-262` runs the renderer thread event loop.
- `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:513-533` drains the renderer mailbox on wake and then renders immediately. `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:596-618` updates frame data and then draws.
- `utils/dev_references/terminals/ghostty/src/renderer/Thread.zig:492-510` draws directly only when allowed; if drawing must happen on the app thread, it posts `.redraw_surface` to `app_mailbox` instead of bypassing app-thread ownership.
- `utils/dev_references/terminals/ghostty/src/termio.zig:1-18` separates terminal IO into `Termio`, backend, mailbox, and optional `Thread`; multi-threading is recommended but explicitly a wrapper around termio, not the terminal state owner itself.
- `utils/dev_references/terminals/ghostty/src/termio/mailbox.zig:10-14` uses a bounded queue for write/event messages. `utils/dev_references/terminals/ghostty/src/termio/mailbox.zig:56-65` documents the critical contract: if the optional mutex is passed, it must already be locked, and a blocking send may unlock/relock it.
- `utils/dev_references/terminals/ghostty/src/termio/mailbox.zig:67-92` attempts an instant queue push first, wakes the writer thread on full queue, unlocks the renderer state mutex before a forever push, then relocks with `defer`. This is the clearest Ghostty lock/wake sanity fact: wake the consumer and release the producer's shared-state lock before a potentially blocking operation.
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig:125-135` applies the same pattern for surface mailbox sends: instant push first; if it would block, unlock `renderer_state.mutex`, do a forever push, then relock.
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig:143-172` applies the same pattern for renderer messages: instant push first; on would-block, unlock renderer state, notify renderer, then forever push and relock.
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:386-402` centralizes termio message queuing and wake notification. It passes `renderer_state.mutex` only when the caller states it is locked.
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:462-503` resizes backend first, enters a small renderer-state critical section for terminal resize, then pushes a renderer resize message and wakes renderer after leaving the critical section.
- `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:288-361` drains termio mailbox messages in a bounded owner thread turn and wakes renderer once after the drain if redraw is needed. `utils/dev_references/terminals/ghostty/src/termio/Thread.zig:440-457` arms wake callback behavior as mailbox drain only.
- `utils/dev_references/terminals/ghostty/src/apprt/surface.zig:134-154` makes surface messages route through the app mailbox with the surface pointer. Surface handling is app-thread-owned, not arbitrary-thread-owned.

## Howl Mapping

- `howl-linux-host/src/main.zig:221-288` centralizes the Linux host loop in `runLoopTurn`: quit check, frame pacing admission, SDL/window pump, host mutations, present completion, runtime progress, input policy sync, health check, redraw/render intent derivation, render, present, and final health check.
- `howl-linux-host/src/main.zig:290-319` computes whether to wait for window events from explicit owner work, runtime wake, input admission, frame permit, pending present completion, redraw, and render work facts. `howl-linux-host/src/main.zig:348-354` defines pending work as host owner work or runtime wake.
- `howl-linux-host/src/main.zig:370-385` reads per-tab wake flags from `pty_wait_thread.wakePending`. `howl-linux-host/src/main.zig:387-410` reads runtime obligations as loop-wake facts.
- `howl-linux-host/src/main.zig:504-510` marks terminal input publication as loop admission, not render intent. `howl-linux-host/src/main.zig:525-529` consumes that admission for the next wait decision.
- `howl-linux-host/src/main.zig:538-558` drives each tab once per loop turn and aggregates `should_redraw`, `keep_running`, and `drive_performed`. This is Howl's owner-thread counterpart to Ghostty's termio/render wake callbacks; it remains centralized rather than creating a Ghostty-style renderer thread.
- `howl-linux-host/src/main.zig:572-580` renders the active tab by calling `tab.renderTurn()`, `tab.noteRenderTurn(turn)`, syncing title, and taking a render snapshot. `howl-linux-host/src/main.zig:607-639` derives and submits the present plan outside `main.zig`'s runtime progress step.
- `howl-linux-host/src/terminal/context.zig:366-379` skips inactive tabs unless they have a pending wait-thread wake or due runtime obligation, drives `pty_pump.driveOnce`, applies active-tab redraw side effects, applies pending clipboard writes, and acks wake.
- `howl-linux-host/src/terminal/context.zig:381-406` holds `term.mutex` across `renderTurn`, calls `maybePublishSource`, computes work state, and if work exists, calls `driveRenderLocked` while still locked.
- `howl-linux-host/src/terminal/context.zig:515-527` chooses render action while locked. `howl-linux-host/src/terminal/context.zig:522-526` calls `self.term.render.prepare()` and then `self.submitPreparedLocked()` while still under `term.mutex` from `renderTurn`.
- `howl-linux-host/src/terminal/context.zig:567-617` performs `submitPreparedLocked` while `term.mutex` is held by callers. It realizes protocol V0 textures, samples GL state, ensures the GL surface, uploads the prepared buffer, logs diagnostics, constructs `HowlRenderSubmitExecution`, and calls `self.term.render.submit`.
- `howl-linux-host/src/terminal/context.zig:408-418` records/acks present tokens under `term.mutex`. `howl-linux-host/src/terminal/context.zig:469-474` queries work state under `term.mutex`. `howl-linux-host/src/terminal/context.zig:476-483` reads cursor blink conditions under `term.mutex`.
- `howl-linux-host/src/terminal/context.zig:449-461` starts the PTY runtime and spawns `pty_wait_thread.progressThreadMain`; the worker thread is a wake detector, not an owner of terminal mutation.
- `howl-linux-host/src/terminal/context.zig:161-183` deinitializes by setting stop, acking any pending wake, kicking wait, joining the progress thread, then stopping/deinitializing PTY, feed record, render, VT state, VT handle, and session.
- `howl-linux-host/src/terminal/pty/wait_thread.zig:45-53` waits until no unacked wake is pending, blocks in finite transport wait slices, signals one wake to the window owner, and exits if the session is no longer alive.
- `howl-linux-host/src/terminal/pty/wait_thread.zig:56-75` uses bounded 50 ms wait slices while rechecking stop and wake handoff state. `howl-linux-host/src/terminal/pty/wait_thread.zig:91-99` coalesces duplicate wake requests and signals the window only on the first pending wake.
- `howl-linux-host/src/terminal/pty/pump.zig:43-55` makes one runtime turn return only `keep`, `should_redraw`, and `alive`; keep is tied to outbound backlog, transport hit-limit, or pending runtime obligation.
- `howl-linux-host/src/terminal/pty/pump.zig:103-193` bounds transport work by compile-time backlog sizes, max reads, max bytes, and a force-lock threshold. It reads into scratch under a transport lease before acquiring the terminal mutex for feed.
- `howl-linux-host/src/terminal/pty/pump.zig:119-129` asserts positive bounds and threshold relationships. `howl-linux-host/src/terminal/pty/pump.zig:141-162` reads while unlocked and only tries/forces a terminal lock once enough data or lock availability justifies a feed. `howl-linux-host/src/terminal/pty/pump.zig:168-180` feeds at most `locked_feed_bytes` while locked.
- `howl-linux-host/src/terminal/pty/pump.zig:75-90` progresses VT runtime under `term.mutex` and drains terminal replies while locked.

## Reinforced Invariants

- The owner thread remains the only place that drives terminal mutation and presentation order. Howl's `runLoopTurn` at `howl-linux-host/src/main.zig:230-288` is the central scheduler; worker threads may wake it, but must not take over render/present policy.
- Any operation that can block on a queue, OS wait, GL driver, or host presentation must not be added under `term.mutex`. Ghostty's sanity pattern at `termio/mailbox.zig:67-92` and `stream_handler.zig:143-172` exists specifically to avoid blocking while holding shared renderer state.
- Wake flags are handoff facts, not redraw facts. Howl encodes this in `howl-linux-host/src/main.zig:504-510`, `howl-linux-host/src/main.zig:525-529`, and `howl-linux-host/src/main.zig:991-1011` tests.
- Runtime work remains bounded per owner turn. Howl's transport pump has fixed compile-time backlog and lock-feed limits at `howl-linux-host/src/terminal/pty/pump.zig:9-21`, `howl-linux-host/src/terminal/pty/pump.zig:103-193`; wait-thread blocking is sliced at `howl-linux-host/src/terminal/pty/wait_thread.zig:7` and `howl-linux-host/src/terminal/pty/wait_thread.zig:56-75`.
- Render work and present completion stay distinct. Howl records present submission through `howl-linux-host/src/main.zig:618-647` and completion through `howl-linux-host/src/main.zig:649-657`, while terminal present state is acked under `term.mutex` at `howl-linux-host/src/terminal/context.zig:408-418`.
- Surface/backend resource realization currently happens in `submitPreparedLocked` under `term.mutex` at `howl-linux-host/src/terminal/context.zig:567-617`. If this is changed, the slice must preserve render-retained state ordering while moving host/GL work out of the lock.

## Anti-Patterns To Avoid

- Do not add a Ghostty-style renderer thread, termio thread, xev loop, app runtime, or mailbox architecture to Howl Linux host as part of this sanity slice. Ghostty is only a lock/wake sanity reference here.
- Do not hide blocking work behind a helper called from `renderTurn` while `term.mutex` is held. The shape would still violate the same lock/wake invariant even if the diff looks smaller.
- Do not make the PTY wait thread parse VT, mutate render state, upload GL resources, submit presents, or decide frame cadence. `howl-linux-host/src/terminal/pty/wait_thread.zig:45-53` must remain wake-detection and handoff only.
- Do not treat input publication, runtime keepalive, or wake-pending as redraw/present intent. Howl already separates those facts in `howl-linux-host/src/main.zig:256-279` and tests that separation at `howl-linux-host/src/main.zig:914-1028`.
- Do not broaden host integration through Zig convenience imports across ABI boundaries. Resource realization/presentation changes must respect the existing host-owned platform boundary and render ABI contract.
- Do not add unbounded queues, unbounded retry loops, or wait-forever behavior in owner turns. Ghostty's bounded mailboxes and Howl's bounded transport turn both point away from unbounded hidden work.

## Proposed Slice Constraints

- The implementation slice should target only the Linux host render-turn lock boundary around `howl-linux-host/src/terminal/context.zig:381-406`, `howl-linux-host/src/terminal/context.zig:515-527`, and `howl-linux-host/src/terminal/context.zig:567-617`.
- The slice must keep `main.zig` as the centralized owner loop. Any change should preserve `runLoopTurn` ordering at `howl-linux-host/src/main.zig:230-288` unless the scratchpad explicitly promotes a source-backed owner-loop reshaping slice.
- The slice must move or split host/GL resource realization and full RGBA upload out from under `term.mutex`, or prove with source refs that the called operations cannot block and do not need moving. The suspect operations are `protocol_v0_textures.realizeFrame`, `term_texture.ensureSurface`, `term_texture.uploadPreparedBuffer`, GL state sampling, and diagnostic logging in `howl-linux-host/src/terminal/context.zig:573-600`.
- The slice must preserve `term.render.prepare`, `preparedUpload`, and `term.render.submit` ordering. If upload data is taken outside the lock, ownership and lifetime of `render_retained.PreparedUpload` must be explicit and tested.
- The slice must not change render ABI, PTY ABI, VT ABI, V0 protocol semantics, or host present semantics.
- Tests should pin at least: no GL/host upload operation under a fake locked term mutex; present-pending blocks new prepare; prepared upload ownership survives unlock/submit path; wake admission remains non-redraw; wait thread still coalesces wakes.
- Stop if moving host/GL work requires changing `howl-render` ABI or V0 resource protocol semantics; that would be a different slice.

## Proof Gaps

- Need exact source inspection of `howl-linux-host/src/window/term_texture.zig` before implementation to classify which functions call GL/driver APIs and can block or fault under lock.
- Need exact source inspection of `howl-linux-host/src/app/present.zig` and `howl-linux-host/src/window/present.zig` to confirm present completion and token ownership do not re-enter `term.mutex` in an unsafe order.
- Need exact source inspection of `howl-render` retained prepare/submit ownership to determine whether `PreparedUpload` can be safely detached from `term.mutex` without aliasing retained buffers.
- Need current tests for `Context.renderTurn` and `submitPreparedLocked` before choosing whether to split prepare/take-upload/host-upload/submit into separate owner-turn phases.
- Need to verify whether diagnostic logging in `submitPreparedLocked` is acceptable under lock. Even if it is not GL work, it may be I/O and should not remain inside a contended critical section without proof.
