Host accountability reset before more ASCII-rain performance work

Status: active research ready for review.

User direction receipt:

- Performance is paused until accountability is restored.
- PTY/VT record-replay is stale and must be stripped out of the host seam.
- The host benchmark role must stay narrow:
  - accept a command
  - log
- The rain workload must become a decoupled benchmark client instead of a Howl-coupled host stress dependency.

Active state receipt:

- Performance remains paused pending host accountability reset.
- The live host replay seam is deleted from host ownership.
- No active artifact may treat rain generation or cross-terminal launch tooling as live host-owned workflow.
- User clarification supersedes the prior delete outcome: rain tooling is its own product, not something to delete.

Landing truth receipt:

- Landed host commit `4b0cdb9` removed CLI/env/startup replay plumbing from the previously authorized file set.
- Reviewer `019eac44-6df8-7e91-842d-c9cffd973aff` rejected the slice as complete because replay owner residue still exists outside that file set, including:
  - `howl-linux-host/src/terminal/term.zig`
  - `howl-linux-host/src/terminal/pty/pump.zig`
  - remaining write-only replay owner logic in `howl-linux-host/src/terminal/pty/feed_record.zig`
- The host command/log proof receipts under `artifacts/host/20260610-host-command-and-log-proof/` are preserved, but they are not yet promoted as an accepted completed slice while the replay-owner reset is active.
- Performance remains paused. The next active slice is `host-replay-owner-residue-reset`.

Replay residue deletion receipt:

- Accepted host commit `7d511c2` deleted the remaining replay residue from:
  - `howl-linux-host/src/terminal/term.zig`
  - `howl-linux-host/src/terminal/pty/pump.zig`
  - `howl-linux-host/src/terminal/pty/feed_record.zig`
- Reviewer `019eac44-6df8-7e91-842d-c9cffd973aff` accepted the bounded three-file deletion slice.
- Verification receipts:
  - `cd howl-linux-host && zig build test` passed
  - `cd howl-linux-host && zig build install -Doptimize=ReleaseFast` passed
- `rg -n "feed_record|feed_record_file|feed_record_io" howl-linux-host/src` returned no matches
- The old `rain-tooling-decoupling` loop is not yet reviewer-clean enough for coding.
- The next active slice is `rain-product-boundary-reset`.

Historical note:

- Detailed pre-landing code facts below are navigation only wherever they describe CLI/env/startup replay plumbing that commit `4b0cdb9` already removed.
- The next active research pass must re-prove current code truth for the remaining replay owner residue before more execution work.
- The current landed-code section appended below supersedes any older fact in this file where the two conflict.

Docs execution receipt:

- `howl-linux-host/stress.md` is now host-only command/log guidance.
- Historical rain/replay claims below are pre-reset facts used to justify this sprint, not current active-doc truth.

## Historical Research Subtask: Rain Decoupling And Host Command Boundary Reset

Historical status:

- This section is pre-landing navigation only.
- It justified the docs reset and startup-plumbing removal, but it is not the current landed-code truth.
- The active current-code truth for further work is the replay-residue section below.

Role: researcher.
Session: `research-2026-06-10-host-command-boundary-reset-01`.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. Historical active loop at the time of this research:
   - `/home/home/personal/projects/howl/loops/done/host-doc-and-current-surface-reset.txt`
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

### Historical Exact File And Line References

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

### Historical Pre-Landing Code Facts

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

### Historical Ordered Slice Plan

Historical status:

- This slice plan was executed or superseded during the docs reset and startup-plumbing cleanup.
- It is retained only as navigation and receipt history.
- The active next slice is defined by the replay-residue section below.

1. `host-doc-and-current-surface-reset`
   - Goal:
     - strip the live host guidance of rain/replay ownership claims
     - rewrite the active sprint/loop/current pointers so no active artifact treats rain as host-owned
   - Candidate files:
     - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
     - `/home/home/personal/projects/howl/sprints/current.txt`
     - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
     - historical loop at that stage: `/home/home/personal/projects/howl/loops/done/host-doc-and-current-surface-reset.txt`
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

## Research Subtask: Remaining Host Replay Owner Residue After `4b0cdb9`

Role: researcher.
Session: `research-2026-06-10-host-replay-owner-residue-reset-01`.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/host-replay-owner-residue-reset.txt`
5. `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Current landed host sources and adjacent owners needed to explain the residue truthfully:
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
10. Archived cache navigation only:
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-01-host-owner-inventory.md`
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-01-terminal-context-owner-map.md`
11. Alacritty-first references used for host/runtime boundary pressure:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs`

### Exact File And Line References

- Current landed host startup and command/log boundary after `4b0cdb9`:
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:3-11`
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:13-47`
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig:69-89`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:19-25`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:27-39`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:84-109`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:118-123`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:21-35`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:137-157`
- Remaining replay owner residue in current landed host code:
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig:30-35`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:479-510`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:1-7`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:168-180`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:250-286`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig:1-11`
- Current host docs boundary:
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:13`
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:53`
- Alacritty reference boundary:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:155-193`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`

### Current Landed-Code Facts

Historical pre-landing facts above in this file described a live host CLI/env/startup replay seam. Those facts are no longer current after landed host commit `4b0cdb9`.

1. The live host startup boundary no longer owns replay configuration.
   - `Args` now owns only `command`, `shell`, `start_path`, duration, debug accounting, debug log cadence, and `window_title`: `src/cli/args.zig:3-11`.
   - The parser no longer accepts any replay option. It now explicitly rejects `--pty-vt-record-path` in a regression test: `src/cli/args.zig:69-75`.
   - `main.zig` parses CLI args, loads config overrides, applies child environment policy, initializes process accounting, and opens a tab without any replay env/config input: `src/main.zig:19-25`, `27-39`, `84-109`, `118-123`.
   - `Processor` no longer stores or forwards any replay path; its live state is host runtime, display, input, pacing, and accounting only: `src/app/processor.zig:21-35`.

2. `Context` no longer seeds replay state at terminal startup.
   - `initTerm()` builds the term from launch/session/vt/render state and sets `self.term.pty = .{ .launch = launch };` only: `src/terminal/context.zig:479-497`.
   - `startRuntime()` resets the title, starts the PTY session, syncs focus, and starts the progress thread. It does not call any replay initializer and does not touch replay file state: `src/terminal/context.zig:499-510`.

3. The remaining replay owner residue is now dead host state plus a dead PTY-pump branch.
   - `terminal/term.zig` still gives `PtyState` two replay-specific fields, `feed_record_file` and `feed_record_io`, even though current startup never initializes them: `src/terminal/term.zig:30-35`.
   - `pty/pump.zig` still imports `feed_record.zig` and still routes every locked transport chunk through `recordChunkLocked(...)` before feeding bytes into VT: `src/terminal/pty/pump.zig:1-7`, `168-177`, `250-286`.
   - `recordTermDataLocked(...)` still treats a replay-write failure as terminal lifecycle failure by setting `term.pty.lifecycle = .failed`: `src/terminal/pty/pump.zig:281-285`.
   - `feed_record.writeChunkLocked(...)` is no longer a file opener/closer. It now only attempts to write hex lines if `term.pty.feed_record_file` is non-null, and otherwise returns immediately: `src/terminal/pty/feed_record.zig:4-11`.

4. In current landed code, that replay path is not a live feature. It is stale residue.
   - Because `initTerm()` initializes `self.term.pty` with launch only and no current startup owner writes those replay fields, `term.pty.feed_record_file` and `term.pty.feed_record_io` stay null on the live host path: `src/terminal/context.zig:484-489`, `src/terminal/term.zig:30-35`.
   - That means `feed_record.writeChunkLocked(...)` is a no-op on the landed host path, but the PTY pump still pays the ownership complexity and still carries a dead failure branch for an impossible state: `src/terminal/pty/pump.zig:175-177`, `281-285`; `src/terminal/pty/feed_record.zig:4-11`.

5. The host docs are now narrower than the remaining code residue.
   - `stress.md` explicitly says benchmark workloads and replay fixtures are not live host-owned workflow: `howl-linux-host/stress.md:13`, `53`.
   - So current accountability truth is inverted from the old problem: docs are already narrowed, while stale replay owner logic still lingers in the host source.

### Reference Facts

1. Alacritty keeps the host CLI/runtime boundary narrow.
   - `TerminalOptions` owns working directory, hold policy, and command override, then maps only those into PTY launch options: `alacritty/src/cli.rs:155-193`.
   - That matches the current Howl direction that the host should accept a command and own logging, not record replay fixtures as a runtime feature.

2. Alacritty keeps recording/replay in explicit test machinery, not host runtime startup.
   - Reference replay loads `alacritty.recording` in `alacritty_terminal/tests/ref.rs` and feeds it directly into the parser inside tests: `alacritty_terminal/tests/ref.rs:100-117`.
   - That remains the relevant reference pressure for Howl: any replay that still matters belongs in lower-module proof surfaces, not in `howl-linux-host` runtime owners.

### Owner Roles And Proposed Shape

#### Current landed owner truth

- `howl-linux-host/src/main.zig`, `src/app/processor.zig`, and `src/terminal/context.zig` now correctly own host command launch, config override, startup, wake, and logging/accounting without replay startup plumbing.
- `howl-linux-host/src/terminal/pty/pump.zig` still incorrectly owns replay recording as part of the transport-to-VT hot path.
- `howl-linux-host/src/terminal/term.zig` still incorrectly stores replay file state in `PtyState`.
- `howl-linux-host/src/terminal/pty/feed_record.zig` is now only a stale helper for those two stale owners.

#### Proposed shape

1. Delete replay state from `PtyState`.
2. Delete replay recording from the PTY pump hot path.
3. Delete `terminal/pty/feed_record.zig` entirely if no other current host owner remains.
4. Keep lower-module replay questions deferred. This slice is host seam deletion only.

### Explicit Ordered Next Slice

Next slice name: `host-replay-owner-residue-deletion`

- Goal:
  - truthfully delete the remaining replay owner residue from the live host seam after `4b0cdb9`
- Allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/term.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
- Required shape:
  - remove `feed_record_file` and `feed_record_io` from `PtyState`
  - remove replay recording from `pumpTransportSliceWith(...)` / `RealTransportOps`
  - remove the dead lifecycle-failure branch that exists only for replay write failure
  - delete `feed_record.zig` if no current host owner remains after the above removals
  - preserve the bounded transport/feed behavior, lock posture, and existing non-replay semantics
- Required tests:
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - `cd /home/home/personal/projects/howl && rg -n "feed_record|feed_record_file|feed_record_io" howl-linux-host/src`
    - expected result after acceptance: no matches
- Non-goals:
  - no lower-module replay replacement
  - no `howl-vt` replay/test changes
  - no `utils/tools/*` movement
  - no renewed performance work
  - no host docs rewrite in the same slice
- Stop conditions:
  - deletion requires changing shipped PTY/VT/render C ABI
  - deletion proves some other current host owner still initializes replay state outside the three-file set
  - deletion proves a lower-module replay surface must land in the same slice for host command/log startup to remain valid

### Risks

1. Historical tests and archives still mention replay.
   - That is expected and not itself a blocker. The active question here is live host ownership, not archive wording.

2. `cli/args.zig` still contains a rejection test for the removed flag.
   - That is not live runtime replay ownership, but it is historical cleanup residue. It can be cleaned in a later host-accountability slice if the reviewer wants the host tests fully free of removed-surface references.

### Proof Gaps

1. This research pass does not decide whether the lower-module replay surface should survive under `howl-vt`.
   - Current evidence only proves it must not live in the host seam.

2. This research pass does not yet cover rain-tooling decoupling.
   - That remains a later ordered slice after the host replay residue is deleted.

### Readiness Judgment

Ready for reviewer gating and bounded execution.

The landed host code after `4b0cdb9` is now re-proved precisely:
- startup replay plumbing is gone
- the remaining residue is confined to `term.zig`, `pty/pump.zig`, and `pty/feed_record.zig`
- the next honest step is deletion of that residue, not performance work and not a broad lower-module replay redesign

## Research Subtask: Post-Replay Rain Tooling Ownership Reset

Role: researcher.
Session: `research-2026-06-10-rain-tooling-decoupling-reset-01`.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/rain-tooling-decoupling-reset.txt`
5. `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Archived cache navigation only:
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-08-ascii-rain-benchmark-surface.md`
10. Current source/docs in scope:
   - `/home/home/personal/projects/howl/utils/tools/build.zig`
   - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
   - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
   - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
   - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
   - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
   - `/home/home/personal/projects/howl/loops/rain-tooling-decoupling-reset.txt`
11. Alacritty-first references for host boundary pressure:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs`

### Exact File And Line References

- Active accountability surface still naming rain tooling as the next stale ownership problem:
  - `/home/home/personal/projects/howl/sprints/current.txt:8-18`
  - `/home/home/personal/projects/howl/loops/rain-tooling-decoupling-reset.txt:10-40`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md:9-17`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md:120-143`
- Host docs already narrowed away from rain ownership:
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:5-13`
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md:44-53`
- Current utils/tools ownership:
  - `/home/home/personal/projects/howl/utils/tools/build.zig:6-17`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:19-27`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:30-75`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:18-29`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:47-95`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:156-163`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:15-25`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:51-114`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:198-205`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:23-28`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:30-58`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:463-466`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:505-563`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:631-699`
- Alacritty reference host/test split:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:157-193`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs:136-175`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`

### Current Landed-Code Facts

1. The live host boundary is already clean; the rain coupling now lives entirely outside `howl-linux-host`.
   - `howl-linux-host/stress.md` limits the host to command launch, working-directory policy, and host logging/accounting, and explicitly says benchmark-client generation and replay capture are outside the live host boundary: `howl-linux-host/stress.md:5-13`, `44-53`.
   - `sprints/current.txt` points only at the host-accountability sprint and the `rain-tooling-decoupling-reset` loop; it does not present rain tooling as host runtime behavior, only as the next correction target: `sprints/current.txt:8-18`.

2. `utils/tools/build.zig` is a pure rain-tooling owner today.
   - The file defines no general tool surface. Its only public build work is `stress:rain*` step creation, rain executable compilation, and harness staging: `utils/tools/build.zig:6-17`, `19-27`, `30-75`.
   - `rg --files utils/tools` shows only four files in the directory, and three of them are the rain generator/launcher files; there is no broader shared tool inventory to preserve.

3. `ascii_rain_stress.zig` is a standalone benchmark client, not a host owner.
   - It owns its own `Config`, parses its own CLI, emits alternate-screen traffic to stdout, and writes `stress_metrics` to stderr: `utils/tools/ascii_rain_stress.zig:18-29`, `47-95`, `166-188`.
   - Its usage text explicitly describes terminal throughput testing rather than any Howl product seam: `utils/tools/ascii_rain_stress.zig:156-163`.

4. `visual_rain_stress.zig` is likewise a standalone benchmark client.
   - It owns terminal-size probing, drop simulation, full-screen erase/redraw, and optional metrics: `utils/tools/visual_rain_stress.zig:15-25`, `51-114`, `169-192`, `251-260`.
   - Its usage text explicitly says it is a visible correctness stress generator and distinguishes itself from `ascii_rain_stress`: `utils/tools/visual_rain_stress.zig:198-205`.

5. `benchmark_terminals.py` is the strongest remaining coupling surface.
   - It hard-codes both the Howl host harness path and the stress harness path from the same repo root: `benchmark_terminals.py:23-28`.
   - It exposes a combined benchmark CLI that assumes the in-repo rain binary exists and that the host should be launched as one peer among cross-terminal comparisons: `benchmark_terminals.py:30-58`, `505-563`, `631-699`.
   - `run_build()` builds both the host and the rain harness together in one command path: `benchmark_terminals.py:463-466`.

6. The active docs/sprint/loop/research surface still mentions rain tooling, but only because the reset sprint is not finished yet.
   - The active loop explicitly says the remaining stale ownership is benchmark-client coupling inside `utils/tools/*` and requires one exact next slice: `loops/rain-tooling-decoupling-reset.txt:14-40`.
   - The active sprint still describes the rain workload as something that must become external and keeps performance paused until that correction lands: `sprints/2026-06-10-host-accountability-reset.md:13-17`, `120-143`.

### Reference Facts

1. Alacritty keeps host CLI/runtime ownership narrow.
   - `TerminalOptions` maps only working directory, hold policy, and command override into PTY launch options: `alacritty/src/cli.rs:157-193`.
   - `main.rs` initializes logging and the app/runtime spine, but it does not bundle a benchmark client or workload generator into the host startup surface: `alacritty/src/main.rs:136-175`.

2. Alacritty keeps replay and benchmark-style proof surfaces outside host runtime ownership.
   - Reference replay loads a fixture from test data and feeds it directly into terminal/parser state inside tests: `alacritty_terminal/tests/ref.rs:100-117`.
   - That pressure is sufficient here: Howl should not keep a workspace-coupled rain client and peer-terminal launcher as part of the live host accountability surface.

### Owner Roles And Proposed Shape

#### Current owner truth

- `howl-linux-host` now correctly owns command acceptance and logging only.
- `utils/tools/build.zig` currently owns nothing except rain benchmark build/run steps.
- `ascii_rain_stress.zig`, `visual_rain_stress.zig`, and `benchmark_terminals.py` are standalone benchmark-client artifacts living inside the Howl workspace with no remaining honest host ownership.
- The active sprint/loop/research surface still has to mention them only because the deletion/decoupling slice has not landed yet.

#### Proposed shape

1. Delete the in-repo rain benchmark client from current Howl ownership:
   - delete `utils/tools/ascii_rain_stress.zig`
   - delete `utils/tools/visual_rain_stress.zig`
   - delete `utils/tools/benchmark_terminals.py`
2. Remove the corresponding `stress:rain*` build/run/stage surface from `utils/tools/build.zig`.
3. Update the active sprint/loop/research wording so rain tooling is recorded as deleted from the Howl workspace, with performance still paused until a separately seeded external benchmark client exists.
4. Do not invent a placeholder new local benchmark wrapper inside Howl. That would preserve the same stale ownership under a new name.

### One Exact Next Slice

Next slice name: `rain-tooling-delete-from-howl-workspace`

- Goal:
  - delete the in-repo rain benchmark client and launcher from current Howl ownership now that host replay/runtime coupling is already gone
- Allowed files:
  - `/home/home/personal/projects/howl/utils/tools/build.zig`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
  - `/home/home/personal/projects/howl/loops/rain-tooling-decoupling-reset.txt`
  - `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
- Required shape:
  - remove all `stress:rain*` step definitions and wiring from `utils/tools/build.zig`
  - delete the two Zig rain binaries and the Python cross-terminal launcher
  - rewrite the active sprint/loop/research text so it records deletion as the chosen outcome, not “move/archive/remove”
  - keep performance paused until an external benchmark-client project/path is explicitly seeded later
- Required tests and receipts:
  - `cd /home/home/personal/projects/howl/utils/tools && zig build`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - `cd /home/home/personal/projects/howl && rg -n "stress:rain|ascii_rain_stress|visual_rain_stress|benchmark_terminals\\.py" utils/tools`
    - expected result after acceptance: no matches
  - `cd /home/home/personal/projects/howl && rg -n "ascii_rain_stress|visual_rain_stress|benchmark_terminals\\.py|stress:rain" sprints/current.txt sprints/2026-06-10-host-accountability-reset.md loops/rain-tooling-decoupling-reset.txt research/host-accountability-reset-2026-06-10.md howl-linux-host/stress.md`
    - expected result after acceptance: no matches except historical archive files outside the active surface
- Non-goals:
  - no new benchmark wrapper inside Howl
  - no host/runtime/render/PTy/VT code changes
  - no archived artifact cleanup outside the active surface
  - no renewed performance work
  - no external repo creation or migration
- Stop conditions:
  - `utils/tools/build.zig` still needs to keep some non-rain live tool owner that cannot be separated inside the allowed file set
  - truthful deletion requires changing active files outside the allowed set above
  - reviewer concludes the external-client reseed must be specified before deletion can be accepted

### Risks

1. Performance receipts under `artifacts/stress/` will become historical evidence with no current in-repo runner.
   - That is acceptable under the current user direction. Performance is paused anyway until a new external client is explicitly seeded.

2. `utils/tools/build.zig` may become empty or trivial after deletion.
   - That is acceptable if the file can be removed cleanly inside the allowed slice. The slice should not preserve a dead build owner just to avoid deleting a file.

### Proof Gaps

1. This research does not seed the external benchmark-client repo/path.
   - That is intentionally outside the current slice and does not block deletion from Howl.

2. This research does not decide what future honest benchmark should replace rain.
   - It only proves the current workspace-coupled rain tooling is stale ownership and should be deleted first.

### Readiness Judgment

Ready for reviewer gating and bounded execution.

The current post-replay-deletion state is now specific enough to stop hedging:
- the host seam is already narrowed
- the remaining stale ownership is fully concentrated in `utils/tools/*` plus the active reset text
- the next honest outcome inside current file ownership is deletion from the Howl workspace, not another temporary coupling layer

## Research Subtask: Rain Product Boundary Reset After User Clarification

Status:

- This section supersedes the prior delete-from-workspace outcome above.
- The prior delete outcome is invalid under the explicit user direction now recorded in the active loop:
  - rain tooling is its own product
  - it is not to be deleted
  - it must not remain coupled as live Howl host ownership

Role: researcher.
Session: `research-2026-06-10-rain-product-boundary-reset-01`.

### Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/rain-product-boundary-reset.txt`
5. `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Archived cache navigation only:
   - `/home/home/personal/projects/howl/research/done/cache-2026-06-08-ascii-rain-benchmark-surface.md`
10. Current code and active artifact reads required by this task:
   - `/home/home/personal/projects/howl/build.zig`
   - `/home/home/personal/projects/howl/utils/tools/build.zig`
   - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
   - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
   - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
   - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
11. Alacritty-first references used for host/runtime boundary pressure:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs`

### Exact File And Line References

- Active loop and sprint boundary:
  - `/home/home/personal/projects/howl/loops/rain-product-boundary-reset.txt:1-33`
  - `/home/home/personal/projects/howl/sprints/current.txt:1-13`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md:9-17`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md:120-143`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md:154-158`
- Current workspace-root coupling:
  - `/home/home/personal/projects/howl/build.zig:56-76`
- Current rain-product files:
  - `/home/home/personal/projects/howl/utils/tools/build.zig:6-17`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:19-28`
  - `/home/home/personal/projects/howl/utils/tools/build.zig:30-75`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:18-29`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:47-95`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig:156-163`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:15-25`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:51-114`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig:198-205`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:23-28`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:30-58`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:463-466`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:485-520`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:523-563`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py:631-738`
- Reference boundary pressure:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/cli.rs:155-193`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/main.rs:136-175`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:205-225`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/tests/ref.rs:100-117`

### Current Landed-Code Facts

1. The live host seam is already narrow enough for the user direction.
   - The active sprint still says the host must stay narrow: accept a command and log, and that performance is paused until rain is no longer part of host shape: `sprints/2026-06-10-host-accountability-reset.md:9-17`, `154-158`.
   - The active loop explicitly says the delete-from-workspace outcome is rejected and must be replaced with a source-backed product-boundary plan: `loops/rain-product-boundary-reset.txt:10-18`, `27-33`.

2. The current stale coupling is no longer in `howl-linux-host`; it is in workspace orchestration and the rain package placement.
   - Root `build.zig` still aggregates `stress:rain*` from `utils/tools` as if those steps are part of the live workspace command surface: `build.zig:56-76`.
   - `utils/tools/build.zig` defines only rain step creation, rain executable compilation, and harness staging. It owns no general shared tooling: `utils/tools/build.zig:6-17`, `19-28`, `30-75`.

3. `ascii_rain_stress.zig` and `visual_rain_stress.zig` are already self-owned benchmark clients.
   - `ascii_rain_stress.zig` owns its own config, CLI, deterministic hostile traffic generation, and stderr metrics; its usage text says it is for terminal throughput testing: `utils/tools/ascii_rain_stress.zig:18-29`, `47-95`, `156-163`.
   - `visual_rain_stress.zig` owns its own config, terminal-size probing, drop simulation, redraw behavior, and metrics; its usage text says it is for visible correctness stress: `utils/tools/visual_rain_stress.zig:15-25`, `51-114`, `198-205`.

4. `benchmark_terminals.py` is also its own benchmark product surface today, but it is still workspace-coupled.
   - It hard-codes the Howl repo root, `howl-linux-host` harness dir, and the rain harness dir from the same tree: `benchmark_terminals.py:23-28`.
   - Its CLI assumes combined ownership of the benchmark client and the Howl host harness, and `run_build()` builds both in one path: `benchmark_terminals.py:30-58`, `463-466`.
   - It injects the stress command into Howl through `--command` and treats Howl as one peer in a cross-terminal runner: `benchmark_terminals.py:505-563`, `631-738`.

5. The current bad boundary is placement and aggregation, not rain-client logic itself.
   - The actual rain logic is already separate from host code.
   - What keeps it coupled is that it lives under vague `utils/tools`, is exported by the root workspace build, and is still named by the active reset artifacts as if it were a Howl-owned next correction target: `build.zig:56-76`; `sprints/2026-06-10-host-accountability-reset.md:120-143`.

### Reference Facts

1. Alacritty keeps host CLI/runtime narrow.
   - `TerminalOptions` maps only working directory, hold policy, and command override into PTY launch options: `alacritty/src/cli.rs:155-193`.
   - `main.rs` owns startup, logging, config, and environment setup; it does not bundle a benchmark client into the host runtime surface: `alacritty/src/main.rs:136-175`.

2. Alacritty keeps recording/replay in explicit test machinery, not in host runtime ownership.
   - Recording is guarded behind ref-test behavior in the terminal event loop: `alacritty_terminal/src/event_loop.rs:205-225`.
   - Replay is loaded from test fixtures and fed directly into terminal/parser state in tests: `alacritty_terminal/tests/ref.rs:100-117`.

3. No direct reference defines “separate benchmark product in same workspace.”
   - That means Howl must invent the smallest possible shape consistent with the existing workspace package pattern and the user’s explicit product direction.
   - The existing root build already treats sibling package directories as separate owners aggregated only by step mappings: `build.zig:1-18`, `20-76`, `92-95`.

### Owner Roles And Proposed Shape

#### Current owner truth

- `howl-linux-host` owns command acceptance and logging only.
- `utils/tools/build.zig` is not an honest owner. It is a vague bucket carrying a separate benchmark product.
- `ascii_rain_stress.zig`, `visual_rain_stress.zig`, and `benchmark_terminals.py` are a benchmark product, not Howl host code.
- Root `build.zig` currently mis-presents that product as a live Howl workspace stress surface.

#### Proposed shape

1. Split the rain benchmark into its own top-level package root inside the same workspace.
   - Create a dedicated sibling package directory with an owner-true noun, `rain-bench/`.
   - Move the rain build owner and rain binaries/launcher there.

2. Remove live Howl workspace aggregation of that product.
   - Root `build.zig` must stop exporting `stress:rain*` through the Howl workspace aggregate.
   - Active sprint/loop/research files must stop treating the rain package as a live Howl-owned correction target once the split lands.

3. Keep the rain product in the same repo for now, but as a separate package boundary.
   - This honors the user direction not to delete it.
   - It also stops lying that the product is part of host ownership.

4. Do not redesign the rain client itself in this first slice.
   - The first truthful cut is structural ownership: package root, package-local build, and removal from Howl root aggregation.
   - Deeper launcher decoupling, such as removing repo-relative default binary paths, can be planned after the product boundary is clean.

### One Exact Next Slice

Next slice name: `rain-bench-package-root-split`

- Goal:
  - separate the rain benchmark client into its own in-workspace product boundary without deleting it and without leaving it as live Howl host/workspace ownership
- Allowed files:
  - `/home/home/personal/projects/howl/build.zig`
  - `/home/home/personal/projects/howl/utils/tools/build.zig`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
  - `/home/home/personal/projects/howl/rain-bench/build.zig`
  - `/home/home/personal/projects/howl/rain-bench/ascii_rain_stress.zig`
  - `/home/home/personal/projects/howl/rain-bench/visual_rain_stress.zig`
  - `/home/home/personal/projects/howl/rain-bench/benchmark_terminals.py`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
  - `/home/home/personal/projects/howl/loops/rain-product-boundary-reset.txt`
  - `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
- Required shape:
  - create `rain-bench/` as a top-level sibling package root
  - move the current rain build owner and the three rain product files from `utils/tools/` to `rain-bench/`
  - keep the package-local rain build steps inside `rain-bench/build.zig`
  - remove root `build.zig` aggregation of `stress:rain*`
  - rewrite the active sprint/loop/research text so the accepted target is “separate in-workspace product boundary” rather than deletion or live Howl ownership
  - leave host docs and host code untouched
- Required tests and receipts:
  - `cd /home/home/personal/projects/howl/rain-bench && zig build stress:rain:build`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - `cd /home/home/personal/projects/howl && rg -n "package_dir = \\\"utils/tools\\\"|stress:rain" build.zig`
    - expected result after acceptance: no root `stress:rain*` mappings remain
  - `cd /home/home/personal/projects/howl && rg -n "ascii_rain_stress|visual_rain_stress|benchmark_terminals\\.py" utils/tools`
    - expected result after acceptance: no rain-product file definitions remain in `utils/tools`
  - `cd /home/home/personal/projects/howl && rg -n "delete-from-workspace|delete the in-repo rain|deleted from the Howl workspace" sprints/2026-06-10-host-accountability-reset.md loops/rain-product-boundary-reset.txt research/host-accountability-reset-2026-06-10.md`
    - expected result after acceptance: no stale delete-direction claims remain in the active surface
- Non-goals:
  - no host/runtime/render/PTY/VT code changes
  - no renewed performance work
  - no launcher behavior redesign beyond path movement needed for the package split
  - no external repo creation
  - no historical archive cleanup outside the active files above
- Stop conditions:
  - truthful package split requires changing active files outside the allowed set above
  - `utils/tools/build.zig` still owns non-rain live tooling that cannot move in this slice
  - the package split reveals a broader false owner than `utils/tools` that must be planned first
  - reviewer concludes the launcher defaults must be decoupled from repo-relative Howl paths in the same slice for the boundary to be honest

### Risks

1. `benchmark_terminals.py` may still be too coupled by default paths even after the package-root split.
   - That does not invalidate the structural ownership cut.
   - It does mean a second rain-product slice may be needed immediately after the split.

2. `utils/tools/build.zig` may become dead after the move.
   - That is acceptable in this slice if it collapses to no live owner work.
   - A follow-up deletion of the now-dead file can be planned only after the package split is accepted.

3. Historical performance receipts under `artifacts/stress/` will remain Howl-side evidence even though the benchmark product moved.
   - That is acceptable; receipts are history, not ownership.

### Proof Gaps

1. This research does not prove whether `rain-bench/benchmark_terminals.py` should require explicit `--howl-bin` instead of repo-relative defaults.
   - That is the main likely immediate follow-up after the structural split.

2. This research does not seed a separate external repository.
   - The user did not require that.
   - The current task is an in-workspace separate product boundary.

### Readiness Judgment

Ready for reviewer gating and bounded execution.

The next honest move is not deletion and not resumed performance work. It is a structural package-boundary cut:
- move the rain benchmark product out of vague `utils/tools`
- stop exporting it through the Howl root build
- keep it in the workspace as its own product boundary
- then review whether launcher-path defaults still require a second decoupling slice before performance resumes
