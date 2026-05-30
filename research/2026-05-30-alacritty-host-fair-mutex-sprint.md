# Alacritty Host Fair-Mutex Sprint

Owner: workspace root (`howl-linux-host` primary; `howl-vt` touched only if evidence proves required).

Status: planned, implementation pending.

## Sprint Intent

Copy Alacritty host/event-loop synchronization posture for shared terminal state access so Howl host:

- does not deadlock in render turn,
- does not race VT feed vs VT surface copy,
- keeps critical sections bounded and explicit.

This sprint is host-loop shaping only. No Ghostty-driven host-loop invention in this sprint.

## Source Order For This Sprint

1. Alacritty host/event-loop and FairMutex sources.
2. Zig 0.16 release notes/runtime semantics.
3. TigerBeetle style and architecture constraints.
4. Current Howl source lock graph and crash/deadlock paths.

## Required Reads (Workers Must Read In This Exact Order)

Alacritty:

- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/sync.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`

Zig 0.16:

- `utils/official_docs/ziglang.org/download/0.16.0/release-notes.html`

TigerBeetle law:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Current Howl lock graph sources:

- `howl-linux-host/src/terminal/term.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/terminal/vt/retained.zig`
- `howl-linux-host/src/terminal/pty/session.zig`
- `howl-linux-host/src/main.zig`

## Locked Facts (From Research, Not Optional)

- Alacritty terminal state is shared by PTY I/O thread and render/event thread via one fair mutex owner (`FairMutex`) with `lease`, fair `lock`, and unfair fast paths.
- Alacritty bounds locked read work (`MAX_LOCKED_READ`) and uses backlog caps (`READ_BUFFER_SIZE`) to avoid lock monopolization.
- Alacritty render path drops terminal lock before heavy draw work.
- Zig 0.16 synchronization semantics are `std.Io` runtime-bound and lock primitives must respect that model.
- Current Howl deadlock edges are nested re-locks on `term.mutex` in render-turn path.
- Current Howl crash path is VT copy concurrent with VT mutation when serialization is not correctly enforced.

## Non-Goals

- No PTY taxonomy/build-step work.
- No renderer feature work.
- No host UX/layout/theme changes.
- No C ABI contract expansion unless forced by proof.
- No broad refactor outside synchronization owner boundaries.

## Files Allowed To Change In This Sprint

Primary:

- `howl-linux-host/src/terminal/term.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-linux-host/src/main.zig` (only to remove/add temporary trace logs required by verification)

Secondary (only if required by lock contract):

- `howl-linux-host/src/terminal/vt/retained.zig`
- `howl-linux-host/src/terminal/pty/session.zig`

Tests:

- `howl-linux-host/src/terminal/context.zig` tests
- `howl-linux-host/src/terminal/vt/surface.zig` tests
- `howl-linux-host/src/terminal/pty/pump.zig` tests

## Explicit Design Target

Implement a host-local fair mutex owner shape equivalent to Alacritty semantics:

- fair entry gate (`lease`),
- fair lock path (`lock`),
- unfair/internal fast path where proven necessary,
- no nested self-locking call graph,
- bounded lock hold in PTY mutation loop,
- render path lock scope limited to terminal state snapshot/copy and state transitions only.

Do not copy Rust API names blindly if Zig/runtime semantics require different names. Preserve behavior contract.

## Implementation Slices (Workers Must Execute In Order)

### Slice 1: Lock Graph Normalization (No Behavior Expansion)

Goal:

- eliminate all nested `term.mutex` re-lock cycles in render-turn path.

Required outcomes:

- every function that may be called under `term.mutex` has a clear locked/unlocked variant boundary,
- no function acquires `term.mutex` then calls another function that can acquire it again.

Hard gate:

- no deadlock at first render turn.

### Slice 2: Fair-Mutex Contract Finalization

Goal:

- finalize `term.mutex` owner API with fair gate + fair lock + bounded unfair usage points.

Required outcomes:

- PTY runtime path uses bounded lock ownership and does not starve render/event loop,
- render/event path preserves fairness and short critical sections.

Hard gate:

- no VT copy crash under startup + first render + PTY feed.

### Slice 3: Bounded-Critical-Section Proofs

Goal:

- engrave boundedness and invariants in tests/assertions.

Required outcomes:

- assertions document lock protocol invariants,
- tests cover first-frame path and contention-sensitive paths.

Hard gate:

- tests fail if lock protocol regresses into nested locking or unbounded hold patterns.

## Worker No-Guessing Rules

- If you cannot point to source evidence for a lock choice, stop.
- If a call path lock-state is ambiguous, stop and report exact path.
- If adding a lock risks nested re-entry, add locked/unlocked variant split first.
- Do not keep temporary logs in final diff.
- Do not change more than one slice intent per patch.

## Required Invariants

- `term.mutex` ownership is explicit at each boundary function.
- No self-deadlock path exists in `renderTurn` flow.
- VT feed/mutate and VT copy/snapshot do not run concurrently on shared terminal state.
- Critical sections are bounded and do not include unnecessary heavyweight work.

## Stop Conditions

- Stop if reproducer still alternates between deadlock and crash after Slice 1 normalization.
- Stop if fair-mutex API requires behavior not available under Zig `std.Io` semantics.
- Stop if a proposed change expands ABI surface or owner boundary beyond sprint scope.

## Verification Commands

From `/home/home/personal/projects/howl/howl-linux-host`:

- `zig build check`
- `zig build test`
- `zig build run` (manual observation: no startup deadlock/crash before first present path)

From `/home/home/personal/projects/howl/howl-vt`:

- `zig build check`
- `zig build test`

From `/home/home/personal/projects/howl`:

- `zig build check`
- `zig build test`
- `git diff --check`

## Diagnostic Protocol (Temporary Only)

- If runtime hangs, add minimal phase markers only around the suspected boundary.
- Remove all diagnostic logs before closing the slice.

## Deliverables

- Updated lock map notes in `project-memory.md` under current date.
- `current.txt` promoted to one active implementation slice from this sprint.
- Clean diff with no temporary traces.
