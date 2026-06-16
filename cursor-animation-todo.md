# Cursor Animation Todo

Purpose:

- Keep the cursor trail work anchored across context compaction or session handoff.
- Stay practical: this is a working checklist, not a formal sprint loop.

## Reference Anchors

- Kitty main trail implementation: `utils/dev_references/terminals/kitty/kitty/cursor_trail.c`
- Kitty trail state: `utils/dev_references/terminals/kitty/kitty/state.h`
- Kitty render scheduling: `utils/dev_references/terminals/kitty/kitty/child-monitor.c`
- Kitty draw path: `utils/dev_references/terminals/kitty/kitty/shaders.c`
- Kitty trail shaders: `utils/dev_references/terminals/kitty/kitty/trail_vertex.glsl`, `utils/dev_references/terminals/kitty/kitty/trail_fragment.glsl`
- Kitty config: `utils/dev_references/terminals/kitty/kitty/options/definition.py`
- Kitty commits: `0d0ee5474d44`, `0f476efbd10d`, `777bddaa28b0`
- Ghostty useful comparison: renderer-owned blink timer and cursor shader uniforms, not built-in Kitty-style trails.

## Current Howl Anchors

- VT cursor truth: `howl-vt/src/screen/cursor.zig`
- VT surface cursor export: `howl-vt/src/ffi/surface.zig`
- Host cursor facts/cadence: `howl-linux-host/src/terminal/surface.zig`
- Host retained render bridge: `howl-linux-host/src/terminal/render_retained.zig`
- Render retained session cadence/state: `howl-render/src/render_session.zig`
- Render C ABI cadence: `howl-render/include/howl_render.h`, `howl-render/src/c/text_session.zig`
- Render cursor publication/presentation: `howl-render/src/vt_publication/cursor.zig`
- Render cursor trail owner: `howl-render/src/text/cursor_trail.zig`
- Render text input: `howl-render/src/vt_publication/text_input.zig`
- Render scene rects: `howl-render/src/text/scene_rects.zig`

## Working Plan

1. Re-read current Howl trail path.
   - Map every cursor trail field from VT -> host -> render -> scene.
   - Identify what is actual animation state versus pass-through facts.
   - Mark host-owned trail state that should move render-side.

2. Re-read Kitty trail behavior.
   - Extract exact state fields from `CursorTrail`.
   - Extract trigger rules: delayed start, threshold skip, resize skip, opacity, completion.
   - Extract scheduling rule: render only while animation needs frames.

3. Decide owner cut.
   - VT keeps cursor truth only.
   - Host should pass cursor facts/config and wake consequences only.
   - Render should own visual interpolation/trail state if the current code disagrees.

4. Implement the smallest render-owned trail shape.
   - Add or reshape a true `CursorTrail` owner in `howl-render`.
   - Track target cursor geometry, four animated corners, opacity, last update time, and `needs_render`.
   - Use actual rendered cursor geometry, not only grid position.

5. Wire scheduling safely.
   - Ensure render work state reports pending animation while trail needs frames.
   - Do not reintroduce a busy main-thread loop.
   - Do not make `event_loop.zig` or host surface own animation policy.

6. Add proof before tuning.
   - Large cursor jump starts a trail after the configured delay.
   - Movement below threshold skips trail.
   - Trail corners move toward target and eventually settle.
   - Trail animation keeps retained render work alive while needed.
   - Animation stops scheduling when complete.

7. Runtime/manual check.
   - Use a small cursor-jump repro before noisy stress tools.
   - Then run `rain`/TUI checks only if the small repro works.
   - Confirm stderr stays clean.

## Known Weak Points

- VT publishes `position_changed_by_client_at_ms`, but the underlying VT value is a movement sequence, not time. Host must not treat that ABI field as elapsed milliseconds.
- Trail trigger delay/threshold is still host-owned. Render owns interpolation state after the trigger reaches render.
- Current backend emission is still a pixel rectangle, not Kitty's true four-corner shader quad.
- There is still no current-cursor masking equivalent to Kitty `trail_fragment.glsl`.
- Render scheduling for animation is the risky seam because recent TUI wake bugs lived nearby.
- A fresh current-code map exists for the trigger path, but not yet for the render-side four-corner implementation.
- Cursor blink phase must reset on activity/trail checks like Kitty's `cursor_blink_zero_time`; otherwise manual cursor-jump tests can hide the current cursor during the trail.

## Done Receipts

- `howl-vt` commit `8565f34 Delete VT vocabulary bucket` removed `vocabulary.zig` and moved cursor style types to the cursor owner.
- `howl-vt` tests passed after the cleanup: `timeout 300s zig build test:unit`, `timeout 300s zig build test`.
- First cursor-animation cut in progress in `howl-linux-host`:
  - `cursor_position_changed_by_client_at_ms` is now treated host-side as a movement sequence, not elapsed time.
  - Host queues a pending trail candidate from the previous cursor rect on a qualifying cursor jump.
  - Host starts that pending trail only after `cursor_trail` milliseconds of stability.
  - `cursorFacts()` exposes a finite wait while a pending trail threshold is outstanding.
  - Verification passed: `timeout 300s zig build test:unit` in `howl-linux-host`.
- First render trail accounting cut in progress in `howl-render`:
  - `countCursorTrailRects()` now matches `appendCursorTrailRects()` instead of suppressing trail capacity behind primary cursor damage/no-shape checks.
  - Existing no-shape cursor test now proves trail count remains allocated when trail rects are appended.
  - Verification passed: `timeout 300s zig build test:unit` in `howl-render`.

## Next Implementation Cuts

1. Add/keep tests for interruption:
   - Done in working tree: a second cursor move before the pending deadline replaces the pending trail candidate and pushes the deadline forward.
   - Done in working tree: a below-threshold move clears pending trail state.
2. Move from host rect-list trail visuals toward Kitty render-owned `CursorTrail` state.
   - Done in working tree: added isolated `howl-render/src/text/cursor_trail.zig` owner for Kitty-style four-corner state/math.
3. Add render-side proof for four-corner easing and completion.
    - Done in working tree: tests prove corners ease toward target, settle with one final render, and opacity follows cursor visibility.
    - Done in working tree: render trail target derivation follows actual cursor shape geometry for block, hollow, beam, underline, and no-shape.
4. Carry cadence time/config through the host/render ABI.
   - Done in working tree: `HowlRenderHostCursorCadence` carries `cursor_trail_decay_fast_s`, `cursor_trail_decay_slow_s`, and `now_ns`.
   - Done in working tree: host fills those fields from cursor blink config and current runtime time without making time-only changes dirty.
   - Verification passed: `timeout 300s zig build test:unit` in `howl-render`; `timeout 300s zig build test:unit` in `howl-linux-host`.
5. Wire render-owned trail into retained session.
   - Done in working tree: retained render session owns `CursorTrail` state, consumes host trail rects only as trigger/source geometry, and emits an internal pixel trail rect.
   - Done in working tree: scene trail rect mapping accepts internal pixel rects without changing the C ABI.
   - Verification passed: `timeout 300s zig build test:unit` in `howl-render`.
6. Remove remaining host-owned rect-list animation policy.
   - Done in working tree: host no longer stores `cursor_trail_started_ns`, ages trail rects, or computes trail opacity.
   - Done in working tree: host publishes one delayed trigger rect and clears it after successful cadence upload.
   - Verification passed: `timeout 300s zig build test:unit` in `howl-linux-host`; `timeout 300s zig build test:unit` in `howl-render`.
7. Add retained scheduling proof that animation work continues only while needed.
   - Done in working tree: render work-state ABI exposes `animation_pending` from `CursorTrail.needs_render`.
   - Done in working tree: host retained work treats `animation_pending` as render work and drives a prepare turn without owning animation policy.
   - Verification passed: `timeout 300s zig build test:unit` in `howl-render`; `timeout 300s zig build test:unit` in `howl-linux-host`.
8. Defer cursor blink after activity.
   - Done in working tree: host cursor blink now tracks a Kitty-like zero-time so activity keeps the cursor visible for the first blink interval.
   - Verification passed: `timeout 300s zig build test:unit` in `howl-linux-host`.
9. Later backend/API cut: replace temporary pixel rectangle emission with true four-corner trail quad/shader emission.
