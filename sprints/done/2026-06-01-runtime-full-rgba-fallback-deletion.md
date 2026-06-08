# Runtime Full RGBA Fallback Deletion

Owner: workspace root.

Status: implementation in progress. The stale prepared-buffer RGBA ABI and its FFI tests are now in
scope for deletion.

## Problem

The V0 sidecar path now holds steady for btop scroll, but the repository still contains the old
runtime full-RGBA presentation path. Keeping it around is stale product code and blocks the next RAM
and CPU work.

## Current Proof

User logs after host glyph patch, alpha atlas entry bound, and glyph-run batching show:

- `v0_emit_status=0`
- `v0_no_sidecar=0`
- `no_sidecar_call_failed=0`
- `v0_unsupported_shape=0`
- interval `rgba_fallback=0`
- interval `glyph_present=10`
- btop proc-tree scrolling no longer flickers

## Runtime RGBA Sources

- `howl-render/src/prepared/buffer.zig` composes full RGBA pixels.
- `howl-render/src/prepared/owner.zig` stores `rgba_pixels`, calls `copySurfaceBuffer()`, exposes
  `buffer()`, and retains surface pixels after submit.
- `howl-render/src/session/text.zig` owns retained surface pixels for full-RGBA partial composition.
- Deleted in this slice: `howl-render/src/ffi/prepared_surface.zig` no longer exposes
  `howl_render_prepared_surface_buffer()`.
- Deleted in this slice: `howl-render/include/howl_render.h` no longer exposes
  `HowlRenderPreparedSurfaceBuffer` or the prepared surface buffer API.
- Deleted: `howl-linux-host/src/terminal/context.zig` no longer falls back to
  `uploadPreparedBuffer()`, and `term_texture.uploadPreparedBuffer()` was removed.
- `howl-linux-host/src/window/term_texture.zig` uploads full RGBA into the terminal texture.

## Deletion Decision

Runtime presentation is V0-only. Full RGBA may remain only as explicit test/proof oracle if tests
still need it. Missing/invalid/unsupported V0 is a failure diagnostic, not fallback.

## Required Verification

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Follow-Up

- After runtime old-path deletion, measure CPU/RAM again.
- Any remaining CPU/RAM issue gets a separate source-backed slice.
