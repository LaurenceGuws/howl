# Host Event Loop Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-event-loop.txt`
- `reference-index.md`
- `howl-linux-host/src/event_loop.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/app/processor.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- Alacritty host/runtime references listed in researcher session `ses_15e01e14affepeC0KmW2yBd7LA`

Findings:

- The true owner noun is `EventLoop`.
- Required rename scope is limited to the owner file plus five exact typed consumers.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/event_loop.zig`
  - `howl-linux-host/src/main.zig`
  - `howl-linux-host/src/app/processor.zig`
  - `howl-linux-host/src/terminal/context.zig`
  - `howl-linux-host/src/terminal/pty/wait_thread.zig`
- Required shape:
  - rename only `pub const State = struct` to `pub const EventLoop = struct` in `howl-linux-host/src/event_loop.zig`
  - update all receivers and owner-local test locals in `event_loop.zig` from `State` to `EventLoop`
  - update direct consumers only:
    - `main.zig` from `EventLoop.State` to `EventLoop.EventLoop`
    - `processor.zig` from `*EventLoop.State` to `*EventLoop.EventLoop`
    - `context.zig` from `*EventLoop.State` to `*EventLoop.EventLoop`
    - `wait_thread.zig` from `*EventLoop.State` to `*EventLoop.EventLoop`
  - keep file path unchanged
  - keep exported free functions unchanged: `nowNs`, `startQuitTimer`, `stopQuitTimer`, semaphore wrappers
  - keep `Signal`, `QuitTimer`, `WakeSemaphore`, and all event-loop behavior unchanged
  - do not add aliases such as `pub const State = EventLoop`
- Non-goals:
  - no event-loop behavior changes
  - no rename of the import alias `const EventLoop = @import("event_loop.zig")`
  - no file moves
  - no changes to `polling/window_wake.zig`, input owners, window owners, display owners, or tab/runtime policy
  - no redesign toward Alacritty `Processor` or PTY `EventLoop` structure
  - no additional cleanup of other `State` buckets in adjacent files
- Verification:
  - `python utils/hygene/style_scan.py "howl-linux-host/src/event_loop.zig" "howl-linux-host/src/main.zig" "howl-linux-host/src/app/processor.zig" "howl-linux-host/src/terminal/context.zig" "howl-linux-host/src/terminal/pty/wait_thread.zig"`
  - `zig build test && zig build check` in `howl-linux-host`
  - grep gate: no `pub const State = struct` in `howl-linux-host/src/event_loop.zig`
  - grep gate: no `EventLoop.State` in `howl-linux-host/src/main.zig`
  - grep gate: no `EventLoop.State` in `howl-linux-host/src/app/processor.zig`
  - grep gate: no `EventLoop.State` in `howl-linux-host/src/terminal/context.zig`
  - grep gate: no `EventLoop.State` in `howl-linux-host/src/terminal/pty/wait_thread.zig`
  - grep gate: `pub const EventLoop = struct` appears in `howl-linux-host/src/event_loop.zig`
- Stop conditions:
  - stop if any file outside the five allowed files needs changes
  - stop if the worker concludes the noun must be anything other than `EventLoop`
  - stop if implementation requires behavioral edits to SDL wait/poll/wake, quit handling, timers, or PTY progress semantics
  - stop if the rename demands compatibility aliases
