# Host Wait Thread Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-wait-thread.txt`
- `reference-index.md`
- `howl-linux-host/src/terminal/pty/wait_thread.zig`
- `howl-linux-host/src/terminal/context.zig`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`
- `howl-linux-host/src/terminal/pty/session.zig`
- `howl-linux-host/src/terminal/term.zig`

Findings:

- The owner is a wait-only background thread, not generic state.
- The smallest file-backed noun is `WaitThread`.
- Only direct typed consumer is `howl-linux-host/src/terminal/context.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/terminal/pty/wait_thread.zig`
  - `howl-linux-host/src/terminal/context.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const WaitThread = struct`
  - update `init` and `deinit` receivers from `*State` to `*WaitThread`
  - update `Context.progress` from `pty_wait_thread.State` to `pty_wait_thread.WaitThread`
  - keep `progress` field name unchanged
  - keep free-function names unchanged: `progressThreadMain`, `wakePending`, `ackWake`
  - keep fields, tests, wait/wake behavior, semaphore use, and event-loop wake target unchanged
  - do not add aliases such as `pub const State = WaitThread`
- Non-goals:
  - no behavior change in PTY waiting, wake coalescing, stop handling, or event-loop wake acknowledgement
  - no rename of `Context.progress`
  - no rename of helper/free functions
  - no edits to `app/processor.zig`
  - no edits to `event_loop.zig`
  - no thread/sync redesign and no broader terminal-context cleanup
- Verification:
  - `python utils/hygene/style_scan.py "howl-linux-host/src/terminal/pty/wait_thread.zig" "howl-linux-host/src/terminal/context.zig"`
  - `zig build test && zig build check` in `howl-linux-host`
  - grep gate: no `pub const State = struct` in `howl-linux-host/src/terminal/pty/wait_thread.zig`
  - grep gate: no `pty_wait_thread.State` in `howl-linux-host/src/terminal/context.zig`
  - grep gate: `pub const WaitThread = struct` appears in `howl-linux-host/src/terminal/pty/wait_thread.zig`
- Stop conditions:
  - stop if any consumer beyond `context.zig` needs a type-site rename
  - stop if review insists on renaming `Context.progress` or the free functions in the same slice
  - stop if implementation needs to touch `event_loop.zig`, `app/processor.zig`, or any PTY/session behavior
  - stop if a direct Alacritty-backed alternative noun is required
