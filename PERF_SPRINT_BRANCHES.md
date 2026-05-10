# Performance Sprint Branch Map

Goal: keep every experiment as a reusable puzzle piece instead of reverting failed ideas.

## Branches

1. `perf/bench-instrumentation`
   - Repos: `howl-linux-host`, `howl-term`
   - Expected result: preserve benchmark-only logs for SDL runtime Hz, SDL FPS/render windows, and runtime feed/apply windows.
   - Success signal: logs explain whether work is paced, saturated, stale, or over-waking without changing runtime behavior materially.

2. `perf/surface-metrics`
   - Repos: `howl-term`, maybe `howl-linux-host`
   - Expected result: expose render surface queue counters in benchmark logs.
   - Success signal: we can quantify snapshot publishes, prepare requests, prepare coalesces, prepared coalesces, submit rejects, and presents per window.

3. `perf/prepare-frame-token`
   - Repos: `howl-linux-host`, `howl-term`
   - Expected result: prepare worker aligns to the 240Hz frame token/deadline and avoids preparing unlimited obsolete snapshots.
   - Success signal: SDL FPS moves toward 240 while `howl-prepare` CPU drops or stays below current levels.

4. `perf/runtime-backpressure`
   - Repos: `howl-term`, maybe `howl-linux-host`
   - Expected result: runtime applies less PTY work when render queue already has unpresented/prepared work, and applies more only when render catches up.
   - Success signal: TUI producer FPS drops intentionally while SDL FPS and total CPU improve.

5. `perf/wake-coalesce`
   - Repos: `howl-term`, `howl-linux-host`
   - Expected result: dedupe snapshot/render wakes so identical or already-covered state does not keep main/prepare hot.
   - Success signal: `howl-main` and `howl-wake` CPU drop with no visible latency regression.

6. `perf/large-pty-buffer`
   - Repos: `howl-session`, `howl-term`, maybe `howl-vt-core`
   - Expected result: revisit Alacritty-style large PTY drain/read buffering after downstream coalescing/backpressure exists.
   - Success signal: larger PTY throughput improves producer FPS or reduces runtime CPU only when combined with cleaner downstream scheduling.

7. `perf/ascii-hot-path`
   - Repos: `howl-vt-core`
   - Expected result: keep ASCII parser/grid fast-path experiments separate from scheduling work.
   - Success signal: runtime `apply_us` drops without lowering SDL FPS or raising main/prepare CPU.

## Rule

Each branch gets measured independently. Failed branches stay available with their benchmark artifact IDs and observed failure mode.
