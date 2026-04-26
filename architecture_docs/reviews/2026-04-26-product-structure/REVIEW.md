# Product Structure Review - 2026-04-26

## Scope

This review covers product repos only. Utility repos under `utils/` are outside the terminal MVP hygiene gate.

Repos reviewed:

- `howl-vt-core`
- `howl-session`
- `howl-term-surface`
- `render/howl-render-core`
- `render/howl-render-gl`
- `render/howl-render-gles`
- `render/howl-render-metal`
- `render/howl-render-software`
- `render/howl-render-vulkan`
- `howl-hosts/howl-sdl-host`
- `howl-hosts/howl-android-host`

## Current Guard Result

`utils/hygene/architecture_guard.sh` passes for all product repos.

The guard now enforces:

- Zig file headers
- public declaration docs
- source file/folder naming shape
- behavior-first test names
- product dependency direction
- active-doc vocabulary discipline
- compatibility-language bans

## Findings

### High: product hygiene gate was still mixing utility repos into terminal MVP quality gates

Status: fixed in guard and documentation.

Cause:

- The workflow did not explicitly distinguish product architecture hygiene from tool-specific utility hygiene.
- This created noise from `utils/howl-microscope`, `utils/howl-docs`, and `utils/howl-pm` that is unrelated to terminal MVP module layering.

Correction:

- `utils/hygene/architecture_guard.sh` skips `utils/*` repos.
- Guard documentation now states product-only scope.
- Product repos still pass the stricter gate.

### Medium: root files are not consistently thin

Affected repos:

- `howl-vt-core`: `src/root.zig` contains extensive API conformance tests.
- `howl-session`: `src/root.zig` is acceptable but still carries many conformance checks.
- `howl-term-surface`: `src/root.zig` is a large export table, but still mostly thin.

Risk:

- Root files can become the dumping ground for tests and API assertions.
- This hides package shape and makes public API review harder.

Rule to add:

- `root.zig` should export, wire, and compile-test modules only.
- Larger conformance tests should live under a named product test module such as `src/test/api_contract.zig`, imported from root.

### Medium: SDL host still has too much runtime flow in `src/main.zig`

Affected repo:

- `howl-hosts/howl-sdl-host`

Evidence:

- `src/main.zig` is 854 lines.
- It owns SDL setup, event loop, frame pacing, render ordering, config, and presentation logic.

Risk:

- The host is the easiest place for renderer/session policy to drift back in.
- The renderer-contract correction can regress if host presentation and planning rules keep accumulating in `main.zig`.

Required direction:

- `main.zig` should become the executable entrypoint only.
- Move durable logic into named modules:
  - `platform/sdl_app.zig` or equivalent for SDL lifecycle/event pump
  - `frame_loop.zig` for tick/present order
  - `presentation.zig` for render invocation and swap semantics
  - `config/runtime_config.zig` for Lua/default config loading

### Medium: session core remains large and mixed

Affected repo:

- `howl-session`

Evidence:

- `src/session/core.zig` is 1984 lines.

Risk:

- Lifecycle, queue, transport delegation, VT integration, observability, and tests live too close together.
- Future transport portability work can become harder to review.

Required direction:

- Split by owned behavior, not by arbitrary file size:
  - `session/state.zig` for data types and invariants
  - `session/io.zig` for feed/apply/feedProcessOutput
  - `session/lifecycle.zig` for start/stop/deinit
  - `session/resize_control.zig` for resize/control observability
  - keep tests near behavior or in explicit `src/test/session_contract.zig` if cross-cutting.

### Medium: render backend scaffold repos are aligned but shallow

Affected repos:

- `render/howl-render-gles`
- `render/howl-render-metal`
- `render/howl-render-software`
- `render/howl-render-vulkan`

Risk:

- These repos pass shape checks but do not yet prove they consume the same render-core plan contract beyond minimal scaffolding.
- If left as generic copies too long, backend-specific constraints may surface late.

Required direction:

- Each backend repo needs a `contracts/` doc naming its backend-specific execution constraints.
- Each backend repo needs at least one test proving its public `Backend` type consumes the render-core-facing config/capability shape.

### Low: Android host Java shell is intentionally minimal

Affected repo:

- `howl-hosts/howl-android-host`

Status:

- Acceptable for current scaffold.
- It correctly wraps `howl_term_surface.TerminalSurface` on the Zig side.
- Java shell has no JNI runtime shape yet, which is intentional after the naming review.

Next maturity step:

- Add explicit native-call contract before adding JNI symbols.
- JNI generated names must remain outside Zig source.

## Process Cause

The drift was not only code quality. It came from workflow ambiguity:

1. The guard checked some syntax/style rules but not active architecture language.
2. Utilities were mixed with product repos, creating noisy gates.
3. Root-file and entrypoint-file responsibilities were not explicit enough.
4. Backend repos had scaffold shape, but not enough backend-specific contract pressure.

## Required Follow-up Sprint

The next sprint should not add product features. It should close structure maturity gaps:

1. Make `root.zig` thin across product repos.
2. Split SDL host `main.zig` into named runtime modules.
3. Split session core by owned behavior without changing public API.
4. Add backend-specific execution contract stubs for GLES/Metal/Software/Vulkan.
5. Add guard or review checklist entries for root thickness and entrypoint ownership.
