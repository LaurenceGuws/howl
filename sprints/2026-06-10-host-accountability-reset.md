Host accountability reset before more ASCII-rain performance work

Date: 2026-06-10.
Status: active.
Orchestrator session id: `orch-2026-06-09-background-default-01`.

Problem statement:

- Performance work is paused.
- The current host benchmark/proof surface is not accountable enough:
  - stale PTY/VT record-replay paths are still present in the host seam
  - the rain generator is still coupled to the Howl workspace and host stress workflow
- The host must stay narrow:
  - accept a command
  - log
- The rain workload must become an external benchmark client, not part of Howl host shape.
- Only after that correction is complete may the ASCII-rain performance sprint resume from an honest boundary.

Planning rule:

- No new performance slice is authorized while this sprint is active.
- The next work is planning and source-backed architecture correction only.
- If the correction exposes more stale benchmark-only seams inside host/runtime, they join this sprint before performance resumes.

Sequential slice queue:

1. `host-doc-and-current-surface-reset`
- completed accepted execution slice
- goal:
  - strip live host guidance of rain/replay ownership claims
  - rewrite active sprint/loop/current surface so no active artifact treats rain as host-owned runtime behavior
- allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
  - `/home/home/personal/projects/howl/sprints/current.txt`
  - `/home/home/personal/projects/howl/sprints/2026-06-10-host-accountability-reset.md`
  - `/home/home/personal/projects/howl/loops/host-doc-and-current-surface-reset.txt`
  - `/home/home/personal/projects/howl/research/host-accountability-reset-2026-06-10.md`
- required shape:
  - docs/accountability only
  - no host code changes
  - active artifacts must say performance remains paused
  - active host docs must stop presenting rain/replay as host-owned workflow
- non-goals:
  - no host code
  - no utils deletion or movement yet
  - no lower-module replay replacement
- stop conditions:
  - live artifact truth requires a benchmark-client destination receipt that does not exist yet
- acceptance receipts:
  - reviewer `019eac44-6df8-7e91-842d-c9cffd973aff` accepted the slice
  - `howl-linux-host/stress.md` no longer matches `ascii_rain_stress|benchmark_terminals\\.py|pty-vt-record-path|artifacts/replay`
  - active sprint/loop/research all carry `Performance remains paused pending host accountability reset.`

2. `host-cli-record-seam-deletion`
- completed accepted execution slice
- goal:
  - remove `--pty-vt-record-path`, `HOWL_PTY_VT_RECORD_PATH`, and runtime `feed_record` startup plumbing from the host seam
- allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/feed_record.zig`
  - host-owned arg/startup tests directly proving the seam deletion
- non-goals:
  - no lower-module replay replacement
  - no benchmark-client movement
  - no ABI changes
- stop conditions:
  - deletion requires shipped PTY/VT/render C ABI changes
- acceptance receipts:
  - host commit `4b0cdb9` `delete host record cli seam`
  - `zig test src/cli/args.zig` passed with:
    - `parse rejects pty vt record path`
    - `parse keeps command and debug switches after record seam deletion`
  - `cd howl-linux-host && zig build install -Doptimize=ReleaseFast` passed
  - grep receipt: `HOWL_PTY_VT_RECORD_PATH` no longer appears in the allowed host files
  - reviewer continuity preserved under reviewer `019eac44-6df8-7e91-842d-c9cffd973aff`

3. `host-command-and-log-proof`
- next active proof slice
- goal:
  - prove host command launch and host log/accounting behavior remain correct after seam deletion
- allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/cli/args.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/stress.md`
  - host-owned arg/startup tests directly proving command launch and debug logging/accounting
- non-goals:
  - no lower-module replay replacement
  - no benchmark-client movement
  - no ABI changes
  - no performance work
- stop conditions:
  - truthful proof requires files outside the allowed host/docs set above
  - proof reveals host command/log behavior still depends on stale benchmark/replay ownership

4. `rain-tooling-decoupling`
- remove active Howl ownership of the rain client and cross-terminal launcher

5. `lower-module-replay-replacement`
- conditional only if replay is still actually needed outside the host seam
Completion gate:

- active research names the exact files to delete, move, or reshape
- reviewer accepts the full correction plan
- the active docs/accountability reset slice lands cleanly
- the host record/replay seam is deleted from live host ownership
- performance remains paused until those corrections land

Active state receipt:

- Performance remains paused pending host accountability reset.
- No active artifact may present benchmark workloads, replay capture, or cross-terminal launch tooling as live host-owned workflow.
