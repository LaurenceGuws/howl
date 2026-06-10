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
- landed partial cleanup, not accepted complete
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
- current landing truth:
  - host commit `4b0cdb9` removed CLI/env/startup plumbing from the allowed file set
  - reviewer rejected this slice as complete because replay owner residue still exists outside the authorized owner set
  - no active artifact may treat the full host replay seam as deleted yet
  - next work is a reset around the remaining replay owner residue

3. `host-command-and-log-proof`
- landed proof receipts, pending truthful re-promotion after replay-owner reset
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
- current receipt state:
  - command proof receipt:
    - `artifacts/host/20260610-host-command-and-log-proof/command.result.txt`
    - `artifacts/host/20260610-host-command-and-log-proof/command.stderr.log`
  - debug accounting/log proof receipt:
    - `artifacts/host/20260610-host-command-and-log-proof/accounting.result.txt`
    - `artifacts/host/20260610-host-command-and-log-proof/accounting.stderr.log`
  - command run exited `0` with `--command 'sleep 2'`
  - debug accounting run exited `0` with `--debug-process-accounting --debug-log-every-ms 100 --command 'sleep 2'`
  - host emitted `howl-debug ...` accounting lines during the proof run
  - `zig test src/cli/args.zig` passed
  - `cd howl-linux-host && zig build install -Doptimize=ReleaseFast` passed
  - host-doc grep receipt:
    - `artifacts/host/20260610-host-command-and-log-proof/stress-grep.txt`

4. `host-replay-owner-residue-deletion`
- completed accepted execution slice
- goal:
  - truthfully delete the remaining replay owner residue from the live host seam after `4b0cdb9`
- acceptance receipts:
  - reviewer `019eac44-6df8-7e91-842d-c9cffd973aff` accepted the three-file deletion slice
  - `howl-linux-host` commit `7d511c2` `delete replay owner residue`
  - `cd howl-linux-host && zig build test` passed
  - `cd howl-linux-host && zig build install -Doptimize=ReleaseFast` passed
  - `rg -n "feed_record|feed_record_file|feed_record_io" howl-linux-host/src` returned no matches
  - the live host replay seam is now truthfully deleted from host ownership
5. `rain-tooling-decoupling`
- next active correction slice
- goal:
  - remove active Howl ownership of the rain client and cross-terminal launcher
- allowed files:
  - `/home/home/personal/projects/howl/utils/tools/build.zig`
  - `/home/home/personal/projects/howl/utils/tools/ascii_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/visual_rain_stress.zig`
  - `/home/home/personal/projects/howl/utils/tools/benchmark_terminals.py`
  - any docs/sprints/loops/research files still treating them as active Howl-owned host tooling
- non-goals:
  - no lower-module replay replacement
  - no PTY/VT/render ABI changes
  - no performance work
- stop conditions:
  - the user wants a specific external repo/project destination that is not yet explicitly seeded
  - truthful decoupling requires code movement outside the allowed tool/docs set above

6. `lower-module-replay-replacement`
- conditional only if replay is still actually needed outside the host seam
Completion gate:

- active research names the exact files to delete, move, or reshape
- reviewer accepts the full correction plan
- the active docs/accountability reset slice lands cleanly
- the host record/replay seam is truthfully deleted from live host ownership
- performance remains paused until those corrections land

Active state receipt:

- Performance remains paused pending host accountability reset.
- The live host replay seam is deleted from host ownership.
- No active artifact may present benchmark workloads or cross-terminal launch tooling as live host-owned workflow.
