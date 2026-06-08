# V0 Prepared Alpha Glyph Run Batching

Owner: workspace root.

Status: implemented; pending commit.

## Problem

After raising the alpha atlas entry bound, local btop smoke moved sidecar loss from resource-bound
status 5 to command-bound status 1:

- `v0_emit_status=1`
- `resource_plan_status=call_failed`
- `no_sidecar_call_failed` rising
- `rgba_fallback` rising

Research confirmed status 1 is `HOWL_RENDER_V0_EMIT_COMMAND_BOUND_OVERFLOW`.

## Source Facts

- `HOWL_RENDER_V0_COMMANDS_MAX == 8192`.
- `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX == 256`.
- `appendCommand()` returns `CommandBoundOverflow` when `command_count >= commands_max`.
- Alpha prepared sprite emission calls `appendGlyphRef()`.
- `appendGlyphRef()` currently appends one glyph ref and then one `DRAW_GLYPH_RUN` command with
  `glyphs.count = 1`.
- The host glyph presentation path already iterates every glyph ref in a glyph-run command.

## Decision

Command batching is now justified. The ABI already models runs; emitting every run with one glyph is
avoidable control-plane overhead that exhausts a fixed bound.

## Required Shape

- Batch consecutive alpha glyph refs into glyph-run commands with up to 256 refs per command.
- Preserve command order by breaking the run before any non-glyph command.
- Preserve exact overflow behavior when the batched command count still exceeds the command bound.
- Do not change ABI, host code, resource lifetime, atlas entry bounds, or full-RGBA fallback.

## Verification

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Implementation

- Added explicit production glyph-ref storage bound `glyph_refs_max = 32 * 1024`.
- Split glyph-ref storage capacity from command capacity in `Limits`.
- Batched consecutive alpha glyph refs into the immediately previous `DRAW_GLYPH_RUN` command while
  the command has fewer than `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX` refs.
- Non-glyph commands naturally break batching because only the immediately previous command can be
  extended.
- `publishFrame()` rebases glyph-run spans to stable emitter-owned glyph storage after transactional
  publish.
- Preserved `CommandBoundOverflow` for true command exhaustion and glyph-ref storage exhaustion.

## Accepted Tests

- Unit test: two glyph refs share one glyph-run command.
- Unit test: one more than `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX` refs starts a second glyph-run command.
- Protocol proof: prepared alpha sprite glyph commands batch.
- Protocol proof: default `Emitter(.{})` emits more than `HOWL_RENDER_V0_COMMANDS_MAX` alpha draws
  with batched glyph runs.
- Protocol proof: artificially low command bound still returns `CommandBoundOverflow` and preserves
  accepted state.

## Verified

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Follow-Up

- Rerun btop/nvim logs after batching.
- If `v0_emit_status` changes again, research the next exact status before touching old-path deletion.
