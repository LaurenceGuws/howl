Host accountability reset before more ASCII-rain performance work

Status: active accepted research.

User direction receipt:

- Performance is paused until accountability is restored.
- PTY/VT record-replay is stale and must be stripped out of the host seam.
- The host benchmark role must stay narrow:
  - accept a command
  - log
- The rain workload must become a decoupled benchmark client instead of a Howl-coupled host stress dependency.

Active state receipt:

- Performance remains paused pending host accountability reset.
- No active artifact may treat rain generation, cross-terminal launch tooling, or replay capture as live host-owned workflow.

Docs execution receipt:

- `howl-linux-host/stress.md` is now host-only command/log guidance.
- Historical rain/replay claims below are pre-reset facts used to justify this sprint, not current active-doc truth.

## Research Subtask: Rain Decoupling And Host Command Boundary Reset

Role: researcher.
Session: `research-2026-06-10-host-command-boundary-reset-01`.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/host-doc-and-current-surface-reset.txt`
5. `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Required stale-loop navigation only:
   - `/home/home/personal/projects/howl/sprints/defered/2026-06-09-post-bg-performance-restart.md`
   - `/home/home/personal/projects/howl/research/defered/post-bg-performance-restart-2026-06-09.md`
10. Required current host sources/docs:
   - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
   - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/build.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/design.md`
   - `/home/home/personal/projects/howl/utils/tools/build.zig`
   - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
11. Archived cache navigation only:
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-01-terminal-context-owner-map.md`
12. Alacritty-first references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs`

### Exact File And Line References

- Current host CLI record seam:
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:3-12`
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:44-47`
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:74-86`
- Current host env/bootstrap seam:
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:15`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:20-26`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:88-111`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:121-125`
- Current host processor/context coupling:
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:21-36`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:138-147`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:149-162`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:189-208`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:293-299`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:503-513`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig:4-15`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig:25-32`
- Current host docs/build/launcher boundary after the docs reset:
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:5-13`
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:15-53`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:8-17`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:25-27`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:32-39`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:43-67`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:23-28`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:30-58`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:505-520`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:523-563`
- Current host product/design truth:
  - `/home/home/personal/projects/howl/howl-linux-host/design.md:9-18`
  - `/home/home/personal/projects/howl/howl-linux-host/design.md:22-45`
  - `/home/home/personal/projects/howl/howl-linux-host/design.md:48-64`
  - `/home/home/personal/projects/howl/howl-linux-host/build.zig:1-4`
  - `/home/home/personal/projects/howl/howl-linux-host/build.zig:33-60`
- Alacritty reference command/log boundary:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:155-205`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs:81-89`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs:132-170`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/event.rs:87-145`
- Alacritty reference replay location:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:205-225`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`

### Current-Code Facts

1. The host executable currently owns an explicit PTY/VT chunk-recording surface.
   - `Args` includes `pty_vt_record_path`, and the parser accepts `--pty-vt-record-path` with a dedicated test proving it: `src/cli/args.zig:3-12`, `14-52`, `74-86`.
   - `main.zig` also accepts the same seam through `HOWL_PTY_VT_RECORD_PATH`: `src/main.zig:15`, `20-26`.
   - `Processor` stores `feed_record_path` as process state and forwards it into every new terminal tab: `src/app/processor.zig:21-36`, `138-147`.
   - `Context.init(...)` and `startRuntime(...)` pass that path into `feed_record.start(...)`; teardown also calls `feed_record.deinit(...)`: `src/terminal/context.zig:149-162`, `189-208`, `503-513`.
   - `feed_record.zig` creates a file, writes the `howl-pty-vt-hex-v1` header, and appends raw hex chunks: `src/terminal/pty/feed_record.zig:4-15`, `25-32`.

2. The host still correctly owns command launch and log/accounting, but the stale record seam is mixed into the same startup boundary.
   - `loadConfig(...)` applies only `shell`, `start_path`, and `command` overrides to host process launch: `src/main.zig:121-125`.
   - `Context.refreshTitle()` falls back to the configured `command`/`shell`, which is consistent with “host accepts a command”: `src/terminal/context.zig:293-299`.
   - Debug logging/accounting is already a separate host concern via `debug_process_accounting` and `debug_log_every_ms`: `src/cli/args.zig:8-10`, `37-43`; `src/main.zig:102`.

3. The strongest remaining workflow coupling between the Howl host workflow and ASCII rain is not a code dependency inside `howl-linux-host/build.zig`; it is shared tooling wiring plus historical pressure from the pre-reset host doc.
   - `howl-linux-host/build.zig` defines only harness/profile/run/test steps for the host executable and does not define any rain/stress build step: `build.zig:33-60`.
   - The live `stress.md` is now narrowed to host-only command/log guidance and explicitly excludes benchmark-client generation, cross-terminal comparison, and replay-fixture capture from the live host boundary: `stress.md:5-13`, `15-53`.
   - The pre-reset host-doc coupling is now historical only; it is preserved in this research artifact as the reason the docs reset slice was necessary.
   - `utils/tools/build.zig` owns the actual rain binaries and advertises them as `stress:rain`, `stress:rain:ascii`, `stress:rain:mixed`, and `stress:rain:visual`: `utils/tools/build.zig:8-17`, `25-27`, `32-39`, `43-67`.
   - `benchmark_terminals.py` hard-codes both the host harness path and the rain binary path from the same repo, can build both with one `--build`, and injects the rain command into Howl through `--command`: `benchmark_terminals.py:23-28`, `30-58`, `505-520`, `523-563`.

4. The pre-reset docs were internally contradictory, which is itself the historical accountability failure that triggered this sprint.
   - The live `stress.md` no longer claims host-owned stress roots; it is now limited to host command/log verification: `stress.md:5-13`, `15-53`.
   - There is no `howl-linux-host/src/stress/` path in the repo; the actual binaries live under `utils/tools/`.
   - `howl-linux-host/design.md` says remaining direct `@cImport` stress-tool sites are explicit non-goals: `design.md:39-45`.
   - So the host design already says stress tooling is not core host ownership; the docs reset slice corrected the former mismatch.

5. The stale performance loop also depended on this coupling.
   - The deferred sprint and research artifacts explicitly define the broad goal around the ASCII-rain benchmark and rely on receipts produced by `artifacts/stress/...`: `sprints/defered/2026-06-09-post-bg-performance-restart.md:11-18`, `83-112`; `research/defered/post-bg-performance-restart-2026-06-09.md:100-118`.
   - That historical work is now navigation only under the active reset loop and should not remain the live host accountability surface.

### Reference Facts

1. Alacritty’s host CLI boundary is narrow: terminal command, working directory, and hold policy.
   - `TerminalOptions` owns `working_directory`, `hold`, and command parsing; `override_pty_config(...)` maps only those into PTY launch options: `alacritty/src/cli.rs:155-205`.
   - That is the closest reference shape for Howl’s host command boundary: accept a command/program and own launch policy, not benchmark workload generation.

2. Alacritty host startup initializes logging as an app concern, separate from command launch.
   - `main.rs` loads CLI options, enters the app path, initializes logging, loads config, and sets PTY environment variables before running the event processor: `alacritty/src/main.rs:81-89`, `132-170`.
   - `event.rs` keeps processor ownership around config, clipboard, scheduler, window contexts, and the event loop spine: `alacritty/src/event.rs:87-145`.
   - This matches the user rule that the host should accept a command and log. It does not own a built-in stress workload.

3. Alacritty’s recording/replay surface exists only as terminal ref-test machinery, not as a host CLI/runtime seam.
   - The terminal event loop writes `alacritty.recording` only when `ref_test` is enabled: `alacritty_terminal/src/event_loop.rs:205-225`.
   - Replay happens in `alacritty_terminal/tests/ref.rs`, where test code loads `alacritty.recording` and feeds it directly into the parser: `alacritty_terminal/tests/ref.rs:100-117`.
   - That is the key reference pressure here: record/replay belongs in an explicit lower-module proof surface, not in the host CLI and runtime startup path.

### Owner Roles And Proposed Shape

#### Current owner truth

- `howl-linux-host` should own:
  - command acceptance
  - shell/start-path/window-title overrides
  - host logging/accounting
  - process launch policy
- `howl-linux-host` should not own:
  - PTY/VT replay fixture capture as a user-facing runtime feature
  - an in-repo rain benchmark client as part of host operational guidance
  - coupled cross-terminal launcher policy
- Lower modules should own:
  - any record/replay proof surfaces needed for PTY/VT benchmarking
- External benchmark tooling should own:
  - ASCII-rain workload generation
  - cross-terminal launch orchestration
  - comparison/reporting receipts

#### Proposed shape

1. Host command boundary:
   - keep `--command`
   - keep launch-policy/logging switches that are truly host-owned
   - delete `--pty-vt-record-path`
   - delete `HOWL_PTY_VT_RECORD_PATH`
   - delete runtime `feed_record` startup from the host seam

2. Host documentation boundary:
   - replace `howl-linux-host/stress.md` with host-only accountability:
     - how to pass a command
     - how to enable host logs/accounting
     - how to run host-only verification
   - remove rain-generator instructions and PTY/VT replay capture instructions from host docs

3. Rain workload boundary:
   - remove the live Howl-host workflow coupling to `utils/tools/ascii_rain_stress.zig`, `visual_rain_stress.zig`, and `benchmark_terminals.py`
   - move or archive these as a separate benchmark client surface rather than an active Howl host surface
   - exact external destination is still a product decision, but the Howl-side correction is ready even before that destination exists

4. Replay boundary:
   - if PTY/VT capture remains needed, move it out of the host CLI and into a lower-module explicit proof surface owned by `howl-pty` or `howl-vt`
   - Alacritty pressure says this should look like ref-test/benchmark machinery, not host runtime launch behavior

### Explicit Ordered Slice Plan

1. `host-doc-and-current-surface-reset`
   - Goal:
     - strip the live host guidance of rain/replay ownership claims
     - rewrite the active sprint/loop/current pointers so no active artifact treats rain as host-owned
   - Candidate files:
     - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
     - `/home/home/personal/projects/howl/sprints/current.txt`
     - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
     - `/home/home/personal/projects/howl/loops/host-doc-and-current-surface-reset.txt`
     - `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
   - Non-goals:
     - no host code yet
     - no utils deletion yet
   - Stop:
     - if planning reveals the live artifact set is still missing a separate benchmark-client destination receipt

2. `host-cli-record-seam-deletion`
   - Goal:
     - remove `--pty-vt-record-path`, `HOWL_PTY_VT_RECORD_PATH`, and all runtime `feed_record` startup plumbing from the host
   - Candidate files:
     - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
     - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
     - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
     - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
     - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
     - any host-owned tests directly proving the old arg/env seam
   - Non-goals:
     - no lower-module replay replacement in the same slice
     - no benchmark-client movement
   - Stop:
     - if deletion requires changing shipped PTY/VT/render C ABI

3. `host-command-and-log-proof`
   - Goal:
     - prove the host still launches commands and emits host logs/accounting after the record seam deletion
   - Candidate files:
     - host tests/docs only
   - Required receipts:
     - command launch proof
     - debug accounting/log proof

4. `rain-tooling-decoupling`
   - Goal:
     - remove active Howl ownership of the rain client and cross-terminal launcher
   - Candidate files:
     - `/home/home/personal/projects/howl/utils/tools/build.zig`
     - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
     - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
     - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
     - any docs/sprints/loops/research still treating them as active Howl host tooling
   - Required shape:
     - either move them to a separately named benchmark-client surface or archive/remove them from live Howl ownership
   - Stop:
     - if the user wants a specific external repo/project destination that has not been explicitly seeded

5. `lower-module-replay-replacement` (only if still needed)
   - Goal:
     - restore any necessary replay proof surface under `howl-pty` or `howl-vt` with explicit non-host ownership
   - This is conditional. If the stale replay path is no longer needed, do not replace it.

### Required Assertions And Tests

1. Host CLI tests
   - assert `--pty-vt-record-path` is rejected or no longer parsed
   - assert `--command` still parses
   - assert debug logging/accounting switches still parse

2. Host startup/integration tests
   - prove `main.zig` no longer reads `HOWL_PTY_VT_RECORD_PATH`
   - prove tab/context startup no longer passes a record path
   - prove command launch still works through the current host startup path

3. Documentation/accountability tests
   - grep-proof that active host docs no longer mention:
     - `ascii_rain_stress`
     - `benchmark_terminals.py`
     - `pty-vt-record-path`
     - `artifacts/replay`
   - grep-proof that active host docs only describe command/log accountability for the host

4. Build/accountability tests
   - prove host build remains limited to host harness/profile/test steps
   - if rain tooling remains in-repo temporarily, prove it is not referenced by active host docs or active host loops/sprints

### Risks / Proof Gaps

1. External destination gap
   - The user said the rain app should be its own project, but this task does not specify the destination repo/path.
   - That does not block Howl-side decoupling. It does block any final “move it there” implementation choice.

2. Lower-module replay replacement gap
   - The current task proves the host seam is wrong for replay.
   - It does not yet prove whether replay should be deleted entirely or reintroduced under `howl-pty`/`howl-vt`.

3. Staged removal order
   - The safest accountable order is host docs/current-surface reset first, then host CLI/runtime deletion, then benchmark client decoupling.
   - Doing utils movement first would leave the host seam lying for longer.

### Readiness Judgment

Ready for planning and reviewer gating.

The current coupling is now source-backed and precise:
- real host-code coupling exists in the CLI/env/runtime record seam
- real workflow coupling exists in `stress.md` and `utils/tools/benchmark_terminals.py`
- the host build itself is already narrower than the stale docs imply
- Alacritty pressure supports a host boundary that accepts a command and logs, while keeping recording/replay in explicit test machinery rather than host runtime

So the next accountable work should not resume performance. It should first delete the host record/replay seam and reset the live host guidance, then decouple the rain client from active Howl host ownership.

## Researcher subtask: PTY/VT record-replay seam inside the live host path

### Sources read in order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/host-doc-and-current-surface-reset.txt`
5. `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Current Howl sources and docs:
   - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
   - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/terminal_benchmark.zig`
   - `/home/home/personal/projects/howl/howl-vt/src/test/pty_feed_record.zig`
10. Reference host/test seams:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/termio/Termio.zig`

### Exact file and line references

- Host CLI/runtime plumbing:
  - `howl-linux-host/src/cli/args.zig:3-12`
  - `howl-linux-host/src/cli/args.zig:44-47`
  - `howl-linux-host/src/cli/args.zig:74-86`
  - `howl-linux-host/src/main.zig:14-16`
  - `howl-linux-host/src/main.zig:20-26`
  - `howl-linux-host/src/main.zig:88-111`
  - `howl-linux-host/src/app/processor.zig:21-36`
  - `howl-linux-host/src/app/processor.zig:138-147`
  - `howl-linux-host/src/terminal/context.zig:138-161`
  - `howl-linux-host/src/terminal/context.zig:201-207`
  - `howl-linux-host/src/terminal/context.zig:503-513`
- Host PTY/VT record ownership:
  - `howl-linux-host/src/terminal/term.zig:30-35`
  - `howl-linux-host/src/terminal/pty/feed_record.zig:4-15`
  - `howl-linux-host/src/terminal/pty/feed_record.zig:18-32`
  - `howl-linux-host/src/terminal/pty/pump.zig:168-180`
  - `howl-linux-host/src/terminal/pty/pump.zig:250-287`
- Host docs after the docs reset:
  - `howl-linux-host/stress.md:5-13`
  - `howl-linux-host/stress.md:15-53`
- Downstream `howl-vt` replay/test coupling:
  - `howl-vt/src/test/terminal_benchmark.zig:27-31`
  - `howl-vt/src/test/terminal_benchmark.zig:414-442`
  - `howl-vt/src/test/pty_feed_record.zig:6-24`
  - `howl-vt/src/test/pty_feed_record.zig:46-56`
  - `howl-vt/src/test/pty_feed_record.zig:71-120`
- Reference facts:
  - `utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:23-31`
  - `utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:93-103`
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:208-227`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:46-55`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:148-155`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:221-225`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`
  - `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:675-693`

### Current-code facts

1. The live host executable still exposes PTY/VT record capture as a first-class runtime option.
   - `Args` owns `pty_vt_record_path` alongside the real host CLI surface, and parsing accepts `--pty-vt-record-path` directly in the main executable path (`howl-linux-host/src/cli/args.zig:3-12`, `:44-47`).
   - The CLI test keeps this option alive as accepted host behavior (`howl-linux-host/src/cli/args.zig:74-86`).

2. The live host also exposes the same seam through environment policy, not just CLI.
   - `main.zig` reads `HOWL_PTY_VT_RECORD_PATH` and feeds it into normal startup before constructing `Processor` (`howl-linux-host/src/main.zig:14-16`, `:20-26`, `:88-111`).

3. The record path is threaded through the normal host startup spine, not isolated to a test harness.
   - `Processor` stores `feed_record_path` as ordinary app state and passes it during `openTab` (`howl-linux-host/src/app/processor.zig:21-36`, `:138-147`).
   - `TerminalContext.init(...)` receives `feed_record_path`, and `startRuntime(...)` unconditionally tries to start the recorder before PTY startup (`howl-linux-host/src/terminal/context.zig:138-161`, `:503-513`).

4. The terminal owner carries record-file state in the live PTY state.
   - `PtyState` owns `feed_record_file` and `feed_record_io` fields (`howl-linux-host/src/terminal/term.zig:30-35`).
   - `Context.deinit()` explicitly tears the recorder down as part of the normal host runtime shutdown (`howl-linux-host/src/terminal/context.zig:201-207`).

5. PTY transport feeding is coupled to recording inside the hot path.
   - In `pumpTransportSliceWith(...)`, a chunk is recorded before it is fed into VT, and a record-write failure marks the PTY lifecycle failed (`howl-linux-host/src/terminal/pty/pump.zig:168-180`, `:281-287`).
   - That means record/replay is not passive documentation; it is executable host runtime behavior coupled to live PTY -> VT progress.

6. The dedicated record owner is a host runtime file, not a test-only artifact.
   - `feed_record.start(...)` creates the output file and writes the replay header (`howl-linux-host/src/terminal/pty/feed_record.zig:4-15`).
   - `writeChunkLocked(...)` emits each PTY -> VT chunk as lowercase hex (`howl-linux-host/src/terminal/pty/feed_record.zig:25-32`).

7. Before the docs reset slice, host docs presented both ASCII-rain and PTY/VT capture as normal host stress procedure.
   - That pre-reset state is the historical reason this sprint exists.
   - The live `stress.md` is now host-only command/log guidance and no longer presents those workflows.

8. `howl-vt` currently consumes the host-produced format directly in benchmark/test code.
   - `terminal_benchmark.zig` owns replay fixture paths and loads every `.hex` file into benchmark fixtures (`howl-vt/src/test/terminal_benchmark.zig:27-31`, `:414-442`).
   - `pty_feed_record.zig` hardcodes the same `"howl-pty-vt-hex-v1"` format and replays chunks slice-by-slice into the VT stream harness (`howl-vt/src/test/pty_feed_record.zig:6-24`, `:46-56`).
   - So the host runtime capture format is not just archived evidence; it is an upstream producer for current VT benchmark surfaces.

### Reference facts

1. Alacritty keeps PTY recording behind explicit debug/ref-test surface, not in the ordinary host command contract.
   - The main CLI exposes `ref_test` as a debug option, not a runtime product contract for normal host startup (`utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:23-31`, `:93-103`).
   - The PTY event loop takes a `ref_test` boolean and only writes `./alacritty.recording` when that flag is enabled (`utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:46-55`, `:148-155`, `:221-225`).
   - The reference consumer lives under `alacritty_terminal/tests/ref.rs`, where the recording is read from a test fixture directory and fed to the parser in ref tests (`utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`).
   - Alacritty window startup passes `config.debug.ref_test` into the PTY event loop as a debug/testing concern, not as the main host command/product seam (`utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:208-227`).

2. Ghostty also keeps PTY-byte recording outside the normal host command seam.
   - The cited live path records PTY bytes only when an inspector is active; otherwise the termio stream consumes the whole slice directly (`utils/dev_references/terminals/ghostty/src/termio/Termio.zig:675-693`).
   - That is selective diagnostic instrumentation, not part of the default host command surface.

3. TigerBeetle pressure cuts against the current Howl shape.
   - The current host seam mixes product runtime work with replay-fixture production and makes a file-write failure able to poison PTY lifecycle state. That violates the repo’s stated owner truth and TigerBeetle’s directness/safety pressure for explicit bounded owners and non-fake structure.

### Owner roles and proposed shape

1. Host role:
   - accept command
   - launch child through `howl-pty`
   - feed live bytes to `howl-vt`
   - log host/runtime receipts
   - stop

2. `howl-linux-host` should not own PTY/VT replay-fixture production in the live host command seam.
   - The current `feed_record_path` plumbing is stale benchmark/testing coupling, not host product shape.
   - The exact hostile seam is the thread from `Args.pty_vt_record_path` and `HOWL_PTY_VT_RECORD_PATH` through `Processor`, `TerminalContext`, `PtyState`, and `pty/pump.zig`.

3. The replay format belongs in an explicit proof surface, not in host runtime startup.
   - If record/replay remains useful, it should be produced by a dedicated benchmark/test tool or fixture-preparation path outside the live host runtime seam.
   - The host should not open replay files, carry replay file handles in terminal state, or fail PTY lifecycle because fixture capture failed.

4. The remaining ASCII-rain coupling outside the live host doc is further evidence that the host seam is carrying stale benchmark ownership.
   - This subtask is bounded to PTY/VT record-replay, but the remaining shared tooling still ties host benchmarking to a Howl-coupled rain generator.
   - The live `stress.md` no longer ties host benchmarking to a rain generator; the remaining coupling is in shared tooling and deferred historical artifacts.
   - That coupling should be handled in separate slices after the replay seam is removed from the live host path.

### Explicit ordered slice plan

1. Strip the record/replay option out of the live host executable surface.
   - Allowed owner targets:
     - `howl-linux-host/src/cli/args.zig`
     - `howl-linux-host/src/main.zig`
     - `howl-linux-host/src/app/processor.zig`
     - `howl-linux-host/src/terminal/context.zig`
     - `howl-linux-host/src/terminal/term.zig`
   - Remove:
     - `Args.pty_vt_record_path`
     - `--pty-vt-record-path`
     - `HOWL_PTY_VT_RECORD_PATH`
     - `feed_record_path` plumbing through host startup
     - record-file fields from live `PtyState`

2. Delete the host runtime recorder owner and detach the PTY hot path from replay production.
   - Allowed owner targets:
     - `howl-linux-host/src/terminal/pty/feed_record.zig`
     - `howl-linux-host/src/terminal/pty/pump.zig`
   - Remove:
     - file creation/header writing
     - per-chunk hex output
     - lifecycle failure on recorder write errors
     - record-before-feed coupling in `pumpTransportSliceWith(...)`

3. Correct host docs so the host command boundary is honest again.
   - Allowed owner targets:
     - `howl-linux-host/stress.md`
   - Remove the PTY-to-VT chunk-capture instructions from host stress guidance.
   - Rewrite host guidance around the user’s narrow host role:
     - accept command
     - log

4. Re-home replay-fixture production/consumption into explicit non-host proof surfaces.
   - This requires a second planning pass because the current active task is bounded to proving and removing the stale host seam first.
   - Candidate follow-up owners:
     - `howl-vt/src/test/terminal_benchmark.zig`
     - `howl-vt/src/test/pty_feed_record.zig`
   - Decision to make in the follow-up plan:
     - keep the replay format but source fixtures from a dedicated tool/project
     - or delete the replay format entirely and replace it with another explicit VT proof surface

5. Re-plan the rain workload separately from host ownership.
   - This is adjacent but distinct from PTY/VT replay removal.
   - The active user direction says the rain app should be its own project and not coupled to Howl host. That needs its own research slice over build/docs/tooling ownership after the record/replay seam is corrected.

### Required assertions/tests

1. Host CLI tests:
   - remove the `parse accepts pty vt record path` test because it currently proves stale host behavior (`howl-linux-host/src/cli/args.zig:74-86`)
   - replace it with negative-space coverage proving the stale option is rejected

2. Host runtime tests/builds:
   - host build/install must still pass after removing `feed_record_path` plumbing
   - startup with `--command` must still exercise the live PTY path without any replay-file state

3. PTY pump safety:
   - assert that PTY transport feed no longer depends on replay writer success to keep lifecycle valid
   - if a helper remains, it must only feed VT bytes, not combine feed and side-band fixture output

4. VT proof surface:
   - if replay stays, add or preserve tests proving the format owner outside the host
   - if replay is deleted, replace it with a direct VT proof surface before removing coverage

### Risks

1. `howl-vt` benchmark/test code currently depends on host-generated `.hex` fixtures, so host cleanup alone can strand the existing replay benchmark surface.

2. `stress.md` currently mixes two separate cleanup problems:
   - record/replay host coupling
   - ASCII-rain host coupling
   If these are edited in one unbounded coder pass, scope drift is likely.

3. The old benchmark loop already leaked bad accountability into host docs and CLI shape. Any coder slice that “just removes the flag” without rewriting the active docs and tests leaves stale truth behind.

### Proof gaps

1. This bounded research does not yet prove the best replacement owner for replay-fixture generation.
   - It proves only that the live host is the wrong owner.

2. This bounded research does not yet map the full build/tooling surface for turning ASCII-rain into an external benchmark client/project.
   - That needs separate research over build roots and tooling ownership.

3. I did not read every archived benchmark script/tool in this subtask because the assignment was bounded to the PTY/VT record-replay seam inside the host path.

### Readiness judgment

Ready for planning and review on the host record/replay removal.

The evidence is sufficient to say:
- the live host executable still owns stale PTY/VT replay-fixture production
- that seam is benchmark/testing coupling, not host product shape
- Alacritty and Ghostty keep analogous byte recording behind explicit debug/test/inspector surfaces rather than in the normal host command boundary
- the first correction pass should remove record/replay from the live host path before any further performance or benchmark work resumes
