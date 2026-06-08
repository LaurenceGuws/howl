# Host Profiler Entrypoint Cache

Date: 2026-06-07.
Role: Orchestrator research synthesis.
Purpose: keep the profiler harness loosely coupled from the load source while reusing production startup code.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/vopr.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md`
- `utils/dev_references/terminals/alacritty/CONTRIBUTING.md`
- `utils/dev_references/terminals/alacritty/README.md`
- `reference-index.md`
- `loop/flow.md`
- `sprints/current.txt`
- `howl-linux-host/build.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/cli/args.zig`
- `howl-linux-host/src/terminal/pty/feed_record.zig`
- `howl-linux-host/src/terminal/pty/pump.zig`
- `howl-linux-host/src/terminal/context.zig`

## Reference Facts

- TigerBeetle keeps deterministic simulation (`vopr`) separate from macro benchmarking (`benchmark`).
- TigerBeetle's benchmark is a dedicated entrypoint that measures throughput/latency and takes a seed from runtime args, not build metadata.
- Alacritty benchmarks throughput with a dedicated external tool (`vtebench`) and treats performance-sensitive changes as benchmarked work.

## Current-Code Facts

- `howl-linux-host/build.zig` already has a separate `run` entrypoint and a clear build-step pattern for host-only binaries.
- `howl-linux-host/src/main.zig` owns app startup and can be split into a shared startup helper without changing product behavior.
- `howl-linux-host/src/cli/args.zig` already parses runtime args for the host binary, including `--pty-vt-record-path` and `--duration-ms`.
- `howl-linux-host/src/terminal/pty/feed_record.zig` already treats the record path as a runtime value, not a build option.

## Proposed Shape

- Add a separate `profile` host binary in `howl-linux-host/build.zig`.
- Keep the load source runtime-driven through existing args or a new runtime arg, not a build option.
- Reuse production startup code from `main.zig` rather than duplicating the host launch sequence.
- Keep the profiler binary non-prod and separate from the product binary so debugging can be patched in without changing product entrypoints.

## Risks

- If the profiler binary starts accumulating scenario-specific branching, it becomes a hidden product mode.
- If load-source choice moves into build metadata, the coupling becomes too tight and the profiler stops being reusable.
- If startup code is duplicated instead of shared, the two binaries will drift.

## Readiness Judgment

- The profiler entrypoint is ready as a narrow worker slice.
- The next implementation should make the build target explicit, keep load source runtime-only, and leave the product binary unchanged.
