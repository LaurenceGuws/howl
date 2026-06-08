# Host Profiler Entrypoint Cache

Date: 2026-06-08.
Role: Researcher rejection follow-up.
Purpose: repair the active research artifact into an execution-grade slice contract for a separate linux host profiler build path.

## Problem Statement

- The active loop requires the first profiling slice to add a separate linux host profiler build path without turning the normal host binary into a profiler mode bucket, while keeping the load source runtime-driven and preserving normal `run` behavior unchanged (`loops/done/host-profiler-entrypoint.txt:8-18`).
- The previous research was rejected because it misread TigerBeetle as proof for a separate benchmark binary, overstated what `howl-linux-host/build.zig` already proves, left startup ownership ambiguous, and omitted the execution-contract fields required by `loop/flow.md`.

## Sources Read In Order

1. `loop/flow.md`
2. `loop/researcher.md`
3. `sprints/current.txt`
4. `loops/host-profiler-entrypoint.txt`
5. `research/cache-2026-06-07-host-profiler-entrypoint.md`
6. Reviewer rejection findings from session `ses_157343204ffeKrMjOcON9g138q` as supplied in the task seed and mirrored in `loops/host-profiler-entrypoint.txt:21-26`
7. `reference-index.md`
8. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
9. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
10. `utils/dev_references/terminals/alacritty/CONTRIBUTING.md`
11. `utils/dev_references/terminals/alacritty/README.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/vopr.md`
13. `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md`
14. `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/main.zig`
15. `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/benchmark_driver.zig`
16. `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/cli.zig`
17. `howl-linux-host/build.zig`
18. `howl-linux-host/src/main.zig`
19. `howl-linux-host/src/cli/args.zig`
20. `howl-linux-host/src/terminal/context.zig`
21. `howl-linux-host/src/terminal/pty/feed_record.zig`

## Reference Facts

- `loop/flow.md` requires every execution slice to define exact allowed files, exact required shape, exact tests, exact non-goals, exact stop conditions, and accountable planning session ids before coding starts (`loop/flow.md:24-31`).
- `reference-index.md` sets the posture order for this dispute: Alacritty first for host/runtime shape, TigerBeetle for Zig discipline and entrypoint discipline, and existing Howl code is not authority by default (`reference-index.md:19-36`, `reference-index.md:60-69`, `reference-index.md:221-229`).
- Alacritty treats performance measurement as an external tool concern: contributors should benchmark throughput/latency-sensitive work, and Alacritty "mainly uses the `vtebench` tool" for that purpose (`utils/dev_references/terminals/alacritty/CONTRIBUTING.md:72-83`). The README repeats that Alacritty uses `vtebench` to quantify throughput (`utils/dev_references/terminals/alacritty/README.md:84-98`).
- TigerBeetle keeps deterministic simulation in a separate build/run surface: `./zig/zig build vopr` and `./zig/zig build vopr -- 123` are the documented simulator entrypoints (`utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md:48-60`). The simulator exists to test safety/liveness under deterministic seeded faults, not to serve as a product command (`utils/dev_references/zig_maturity/tigerbeetle/docs/internals/vopr.md:26-40`).
- TigerBeetle's macro benchmark is not a separate benchmark binary. The documented command is `./zig/zig build -Drelease run -- benchmark` (`utils/dev_references/zig_maturity/tigerbeetle/docs/internals/HACKING.md:124-132`). In source, `main.zig` parses a `benchmark` command and dispatches it through `benchmark_driver.command_benchmark` inside the existing binary (`utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/main.zig:75-76`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/main.zig:102-118`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/main.zig:132-174`).
- TigerBeetle's benchmark driver reuses the current executable at runtime with `selfExePathAlloc`, optionally formats and starts a temporary single-node cluster, and then runs benchmark load in-process (`utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/benchmark_driver.zig:1-14`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/benchmark_driver.zig:25-31`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/benchmark_driver.zig:47-66`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/benchmark_driver.zig:87-91`). The CLI also models `benchmark` as a command inside the command union, not as a separate binary contract (`utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/cli.zig:331-339`, `utils/dev_references/zig_maturity/tigerbeetle/src/tigerbeetle/cli.zig:1131-1194`).
- TigerBeetle style pressure here is to prefer the smallest direct shape and avoid invented infrastructure (`utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-100`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:177-184`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94-101`).

## Current-Code Facts

- The active loop fixed the execution target: add a separate `profile` host binary/build step, keep load source runtime-driven, reuse production startup code, and leave production `run` behavior unchanged.
- `howl-linux-host/build.zig` proved only one host executable was built and installed through the main build path before this slice. `build()` called `buildHostExe()` once, installed that artifact, and wired `run` to that artifact (`howl-linux-host/build.zig:43-57`). `buildHostExe()` created a single executable rooted at `src/main.zig` (`howl-linux-host/build.zig:134-142`). `installHarnessArtifact()` and `wireRunStep()` were generic helpers, but they were only exercised for that one executable before the slice (`howl-linux-host/build.zig:200-213`).
- `howl-linux-host/build.zig` already named host artifacts through `artifactName(b, base, optimize)` and already installed host executables into `zig-out/harness/<exe.out_filename>` through `installHarnessArtifact()` (`howl-linux-host/build.zig:200-207`, `howl-linux-host/build.zig:221-231`).
- `howl-linux-host/src/main.zig` already kept load-source selection runtime-driven. `main()` parsed CLI args, resolved `HOWL_PTY_VT_RECORD_PATH` from CLI or environment, and passed the resulting optional path into `start()` (`howl-linux-host/src/main.zig:19-25`).
- `howl-linux-host/src/main.zig` owned the host startup sequence: thread naming, video init, config load, window/display setup, input/event loop setup, `Processor` construction, first tab open, optional quit timer, and `processor.run()` all lived in `start()` (`howl-linux-host/src/main.zig:28-109`).
- `Processor.openTab()` passed the runtime `feed_record_path` into terminal creation (`howl-linux-host/src/app/processor.zig:135-145`).
- `terminal/context.zig` then started the feed recorder during terminal runtime startup, before PTY session start, using the same runtime path (`howl-linux-host/src/terminal/context.zig:120-144`, `howl-linux-host/src/terminal/context.zig:449-460`).
- `terminal/pty/feed_record.zig` opened the record file only when a non-null, non-empty runtime path was provided; no build-time selection existed there (`howl-linux-host/src/terminal/pty/feed_record.zig:6-16`).
- `src/cli/args.zig` already accepted `--pty-vt-record-path` and `--duration-ms`; the existing tests covered that parse path (`howl-linux-host/src/cli/args.zig:3-10`, `howl-linux-host/src/cli/args.zig:12-44`, `howl-linux-host/src/cli/args.zig:46-59`).

## Reference Posture Resolution

- External tool: rejected for this slice. Alacritty proved that performance harnesses can live outside the product binary (`utils/dev_references/terminals/alacritty/CONTRIBUTING.md:72-83`), but adopting a separate external tool here would create a broader new owner surface than the active loop authorized.
- Dedicated command inside the existing host binary: rejected for this slice. TigerBeetle proved this is a valid pattern for its benchmark command, but it did not prove a separate benchmark binary, and the active loop explicitly forbade hiding profiler mode inside the normal product binary.
- Dedicated non-product build artifact: selected. This was the smallest Howl-local invention that satisfied the active loop's explicit direction for a separate `profile` binary/build step while preserving runtime-selected load sources and avoiding a hidden mode inside the shipped `run` binary.
- Startup owner split: resolved explicitly. The `profile` artifact reuses the existing `src/main.zig` startup owner directly; no new startup helper, no duplicate launch sequence, and no changes to `Processor`, `Context`, or PTY runtime owners were authorized in this slice.

## Slice Contract

### Exact Allowed Files

- `howl-linux-host/build.zig`

### Exact Required Shape

- Add one new build step named `profile` in `howl-linux-host/build.zig`.
- Build one additional non-product executable artifact for the linux host profiler path from the same `src/main.zig` root module used by the normal host executable.
- Name the new artifact with base name `howl_term_profile`, so the built filename is exactly `howl_term_profile_<optimize-suffix>` under the existing `artifactName()` convention.
- Install the profile artifact, do not merely stage it. Reuse `installHarnessArtifact()` so the destination is exactly `zig-out/harness/howl_term_profile_<optimize-suffix>`.
- Add a dedicated `profile` step that depends on that install artifact and nothing else beyond the artifact's own build graph.
- Keep the existing `run` step wired to the production host executable only.
- Keep `check` depending only on the production host install artifact. `check` must not depend on the new profile artifact, so default build behavior stays unchanged.
- Keep load-source selection runtime-driven exactly as it was through CLI/env resolution already owned by `src/main.zig`, `src/cli/args.zig`, `src/terminal/context.zig`, and `src/terminal/pty/feed_record.zig`; this slice must not add build options for load-source selection.
- Do not add a new CLI command, a new env var, a new startup helper, or a new profiler runtime branch in `src/main.zig` for this slice.

### Exact Tests And Verification Commands

- `zig build check`: exits 0 and continues to build only the default host harness path; the `run` step target and default `check` dependency graph remain production-only.
- `zig build profile`: exits 0 and installs `zig-out/harness/howl_term_profile_<optimize-suffix>` from `src/main.zig` without requiring any runtime-owner file changes.
- `zig build test:unit`: exits 0 with the existing unit-test surface unchanged.

### Exact Non-Goals

- No profiling logic redesign.
- No benchmark policy claims.
- No production-path behavior changes.
- No load-source build option.
- No hidden profiler mode inside the normal product binary.
- No startup refactor beyond what is strictly necessary inside `build.zig` to build a second artifact from the same root module.
- No changes to `src/main.zig`, `src/cli/args.zig`, `src/terminal/context.zig`, or `src/terminal/pty/feed_record.zig` in this slice.

### Exact Stop Conditions

- Stop if implementing `zig build profile` requires changing runtime ownership outside `howl-linux-host/build.zig`.
- Stop if the proposed shape requires a build-time load-source selector.
- Stop if the worker cannot keep the existing `run` step behavior unchanged.
- Stop if the worker cannot keep `check` production-only while adding the `profile` step separately.
- Stop if a reviewer or orchestrator wants a dedicated `profile` command inside the normal host binary without an explicit user override receipt.
- Stop if adding the profile artifact requires introducing broad performance infrastructure beyond a second build artifact.

## Accountable Planning Session Ids

- Current rejection session id: `ses_157343204ffeKrMjOcON9g138q`
- Orchestrator session id: `orch-2026-06-08-host-profiler-entrypoint-01`
- Researcher session id: `ses_1572b12e1ffegeBg595JWVQJMW`
- Reviewer session id: `ses_157343204ffeKrMjOcON9g138q`

## Risks

- A later worker may try to smuggle profiler behavior into `src/main.zig` because the second artifact shares the same root module. The slice contract must hold the line that this slice is build-only.
- The profile artifact could accidentally replace or broaden the production build graph if the worker wires it into `check` or `run` instead of keeping it under the dedicated `profile` step.
- If later profiling needs compile-time instrumentation flags, that is a separate slice and must not be inferred from this build-only entrypoint slice.

## Proof Gaps

- No reference directly prescribed a separate non-product profile artifact for an embeddable terminal host. Alacritty leaned external-tool; TigerBeetle leaned in-binary command for macro benchmark and separate simulator build target for deterministic testing. The selected shape was therefore a minimal Howl-local invention driven by the active loop's explicit requirement.
- This research did not prove whether a later profiling slice will need a separate run helper for the profile artifact. That remained intentionally out of scope; this slice only proved a separate installed build artifact and step in `build.zig`.

## Readiness Judgment

- Ready for execution review if the reviewer accepted this narrower posture: the first slice is a build-only second artifact in `howl-linux-host/build.zig`, not a runtime redesign.
- Not ready for any slice that changes runtime startup ownership, CLI surface, or terminal runtime behavior, because this research did not authorize those changes.
