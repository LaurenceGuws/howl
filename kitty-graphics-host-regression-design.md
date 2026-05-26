# Host Kitty Graphics Regression Design

Owner: `howl-linux-host`.

Purpose:

- Define the smallest acceptable host-owned proof surface for the deterministic Kitty graphics crash repro.
- Set the acceptance gate before implementation so the regression harness does not degrade into smoke coverage.

## Governing Inputs

- `AGENTS.md`
- `loop.txt`
- `reference-index.md`
- `current.txt`
- `build-test-architecture-spec.md`
- `utils/official_docs/kitty/graphics-protocol.md`
- `utils/dev_references/terminals/ghostty/src/termio/Thread.zig`
- `utils/dev_references/terminals/ghostty/src/termio/Exec.zig`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

## Fixed Decisions

- Kitty is the protocol source of truth for the replay input.
- TigerBeetle quality gates are the final design filter.
- The Python helper is a user repro tool only. It is not proof.
- The first proof surface must stay inside the smallest true host owner.
- No ABI-boundary bypass is allowed.
- If the smallest acceptable owner cannot reproduce the crash, the next expansion is `Window.State`, not the full app loop.

## Proof Statement

- A host-owned `TerminalPanel`, driven through the real PTY transport with a fixed Kitty direct-upload replay, must reach the same host failure boundary as the live repro and then complete host teardown without allocator abort, assertion failure, or double free.

More explicitly, the regression must prove all of the following:

- the PTY transport can deliver deterministic Kitty graphics bytes into the real host VT/render integration path
- the host reaches the expected failure boundary when the repro triggers it
- host-owned teardown of the panel, progress thread, PTY session, VT handle, and render state completes exactly once and cleanly

## Canonical Step Shape

- `test:integration:kitty-graphics-replay`
- `test:integration:kitty-graphics-replay:build`

Rationale:

- This surface is host-owned.
- It proves cross-package behavior through shipped ABI seams.
- The crash history belongs to a focused leaf, not to the meaning of the aggregate name.
- `test:integration` and host `test` may depend on this leaf.

## Smallest True Owner

- First implementation owner: `TerminalPanel`

Why this is the smallest acceptable owner:

- `TerminalPanel` owns real PTY session startup and stop.
- `TerminalPanel` owns the progress thread and its wake/ack/join ordering.
- `TerminalPanel` owns the real VT handle and render surface-text handle lifetime.
- `TerminalPanel.deinit()` owns the teardown order currently suspected of corruption.

Why not start with the full app loop:

- `main.zig` and `Window.State` add unrelated SDL/OpenGL event-loop and presentation policy.
- That broader surface makes the failure harder to localize.
- The current evidence already narrows the bug frontier to host-owned failure and teardown after transport feed failure.

## Replay Input Shape

- One checked-in deterministic fixture representing Kitty direct-upload traffic for the current app-icon repro.

Fixture requirements:

- the bytes are the actual Kitty APC upload stream shape
- the stream includes the first control chunk and continuation chunks
- the stream is prompt-free and shell-noise-free
- the payload is frozen and repo-owned
- the chunking is fixed so the parser and host consequence path are deterministic

Initial fixture recommendation:

- `howl-linux-host/src/test/fixtures/kitty_graphics_parser_limit_repro.sh`

Format requirements:

- repo-owned script or data fixture only
- one deterministic transport replay stream
- no generation from mutable user tools at test runtime
- bounded fixed chunk count that is known to cross the same consequence limit

## Initial Harness Shape

- Create a focused host integration test module that:
  - constructs host terminal config with a fixed command
  - launches a `TerminalPanel`
  - uses a PTY child command that writes only the fixture replay bytes to the TTY and exits
  - drives progress in bounded turns until the failure boundary is reached or a fixed timeout expires
  - asserts the failure boundary exactly
  - calls `deinit()` and proves the process survives cleanly

The first implementation should not:

- create a real SDL window
- call the full app loop in `main.zig`
- depend on rendering to the screen as the main oracle

## Required Assertions

The harness must enforce at least these assertions:

1. Failure boundary reached

- `panel.lifecycleState() == .failed`
- `panel.isAlive() == true`

2. Bounded deterministic progress

- the failure boundary is reached within a fixed turn count or timeout
- timeout is a test failure

3. Clean one-time teardown

- after `panel.deinit()`:
  - `panel.live == false`
  - `panel.progress.thread == null`
- the test process returns normally with no allocator abort or double free

## Secondary Assertions To Add During Implementation

- the panel starts live before the repro is driven
- the progress thread exists before teardown
- teardown runs only once in the harness
- any new owner-local release helper must assert pre-release and post-release state

## Rejection Criteria

Reject any implementation that:

- uses the Python helper as proof
- feeds VT internals directly instead of using the host PTY path
- starts with a real window/present loop without proving the smaller panel seam first
- relies on log text as the primary correctness oracle
- uses mutable runtime-generated fixtures
- introduces a fake umbrella runtime layer

## Expansion Rule

- If the `TerminalPanel` harness does not reproduce the crash, stop and promote a new item.
- The next acceptable expansion is a host harness that adds `Window.State` ownership only.
- Do not jump directly to the full app loop unless the window-owned expansion is proved necessary.

## Current Narrowing Result

- `TerminalPanel` replay proof is clean.
- `Window.State` replay proof is clean.
- The real app-owner replay still aborts with `double free or corruption (!prev)`.

Current implication:

- The crash frontier requires the real app owner path in `src/main.zig`.
- The next fix loop should start from the app-owned unwind path after `error.HostTabFailed` becomes reachable.
