# Third VT Output Path Scratchpad

Owner: workspace root.

Purpose:

- Define the missing third outward seam from `howl-vt`.
- Keep render publication and host metadata separate from runtime obligation truth.
- Invent the smallest Howl-owned shape that can support VT-owned autonomous work such as Kitty animation.

## Current VT Outward Paths

### 1. Render publication path

- Visible surface export lives in `howl_vt_terminal_copy_surface()`.
- Visible metadata lives in `howl_vt_terminal_query_visible_meta()`.
- Graphics publication is a sibling publication path:
  - `howl_vt_terminal_query_graphics_meta()`
  - `howl_vt_terminal_query_graphics_image()`
  - `howl_vt_terminal_query_graphics_placement()`
  - `howl_vt_terminal_query_graphics_virtual_placement()`
  - `howl_vt_terminal_copy_graphics_payload()`
- This path answers one question only:
  - what is true to draw now?

### 2. Host consequence / metadata path

- Retained host consequence state lives under `howl-vt/src/host/state.zig`.
- Current ABI surfaces include:
  - `howl_vt_terminal_copy_title()`
  - `howl_vt_terminal_copy_pending_output()`
  - `howl_vt_terminal_clear_pending_output()`
  - `howl_vt_terminal_drain_pending_clipboard()`
  - `howl_vt_terminal_copy_surface_hyperlink()`
  - selection query/mutation/copy APIs
- This path answers questions like:
  - what protocol consequence should the host consume?
  - what retained host-facing state does the host need to query?

## Missing Path

- We do not currently have a runtime-obligation path.
- We have no VT-owned way to say:
  - wake me again at or before a deadline
  - there is deferred owner work due even if no PTY bytes arrive
- This is the missing seam for autonomous Kitty animation.

## Why Existing Paths Are Not Enough

- Render publication path is wrong because it exports draw truth, not owner scheduling obligations.
- Host consequence path is wrong because animation wake is not user-visible metadata or a protocol payload to drain.
- Putting animation timing in render would violate the owner split.
- Putting animation state machine policy in host would violate VT ownership of protocol consequences.

## Current Kitty Animation Pressure

- VT currently supports only client-driven current-frame selection through `a=a,c=<frame>`.
- `howl-vt/src/kitty/graphics.zig` currently rejects broader animation controls when:
  - `edit_frame_number != 0`
  - `z != 0`
  - `animation_state != 0`
  - `loop_count != 0`
- Therefore the missing work is not more graphics publication shape.
- The missing work is VT-owned autonomous progression over time plus a host wake contract.

## Candidate Third Path

- Name idea:
  - runtime obligation path
  - wake/deadline path
  - deferred VT work path
- Intended meaning:
  - VT reports whether owner-thread work is due now or by a deadline
  - host owns waiting and wake delivery only
  - VT remains owner of the state transition when the owner thread re-enters VT

## Strong Constraints

- No fake event bus.
- No feature-specific animation ABI if a feature-agnostic runtime-obligation seam can work.
- No render-owned animation semantics.
- No background thread mutation of VT state.
- Owner-thread control flow stays centralized.
- Bounded work per host turn.

## Working Questions

1. Should the third path be query-based, drain-based, or ack-based?
2. Is the smallest acceptable contract just:
   - no pending work
   - pending now
   - wake by deadline
3. Does VT need an explicit owner-thread step such as:
   - advance deferred work now
   - or can ordinary feed/query/publication entrypoints absorb it safely?
4. When autonomous work advances current image truth, which identities move?
   - `dirty_generation`
   - `snapshot_seq`
   - graphics `publication_seq`
5. Can this seam be general enough to serve future VT-owned deferred work beyond animation?

## Current Bias

- VT should own:
  - animation state
  - frame graph truth
  - current-frame selection
  - loop counting
  - next-deadline computation
  - publication invalidation caused by autonomous advancement
- Host should own:
  - waiting
  - wake scheduling
  - re-entering VT on the owner thread
- Render should stay unaware of animation semantics and continue consuming ordinary graphics publication truth only.

## Next Research Step

- Define the smallest candidate ABI type for runtime obligation truth.
- Then decide whether VT also needs a dedicated owner-thread progress call for deferred work.

## Accepted Direction

- The third VT outward seam should be a runtime-obligation seam.
- It should be `query + progress-call`, not query-only.

### Recommended Shape

- `howl_vt_terminal_query_runtime_obligation(handle, now_ns)`
  - reports whether VT-owned deferred work is due now
  - reports the next monotonic deadline, or `0` if none exists
- `howl_vt_terminal_progress_runtime(handle, now_ns)`
  - performs one owner-thread deferred-work step inside VT
  - reports whether visible state changed
  - reports the next obligation state again

### Why Query-Only Is Rejected

- Query-only would either:
  - hide mutation inside a read-like call
  - or delay autonomous VT work until unrelated entrypoints happen to run
- Both are worse than an explicit owner-thread progress step.
- We want bounded control flow and honest mutation seams.

### ABI Data To Expose

- `now_ns` as host-supplied monotonic time input
- `pending_now`
- `deadline_ns`
- `state_changed` on the progress call only

### ABI Data To Avoid

- image ids
- frame ids or frame numbers
- loop counts
- animation states
- feature-specific reason tags such as Kitty animation
- any generic event bus payload

### Ownership Split

- VT owns:
  - deferred protocol state
  - animation state machine
  - current-frame truth
  - loop counting
  - next-deadline computation
  - autonomous visible-state mutation during progress
- Host owns:
  - monotonic time source
  - wake scheduling
  - merging this deadline with other host deadlines
  - calling the VT progress step on the owner thread
- Render owns nothing new here.

### Publication Rules

- `query_runtime_obligation()` must not mutate VT state.
- `progress_runtime()` is the only autonomous-mutation entrypoint.
- If progress makes no visible change:
  - `dirty_generation` does not change
  - `snapshot_seq` does not change
  - graphics `publication_seq` does not change
- If progress advances visible graphics truth:
  - increment `dirty_generation` once for that progress step
  - let existing lazy publication machinery derive the next `snapshot_seq`
  - let existing lazy publication machinery derive the next graphics `publication_seq`

### Why This Fits Howl

- It keeps protocol semantics in VT.
- It keeps scheduling policy in host.
- It avoids exporting Kitty animation semantics above VT.
- It preserves the current render contract as ordinary published image truth.

## Next Concrete Loop

- Define the exact ABI structs and status vocabulary for:
  - runtime obligation query
  - runtime progress result
- Then pressure the host loop shape against:
  - existing PTY wake thread
  - owner-thread bounded turn rules
  - active-frame / render-turn scheduling

## Accepted ABI Contract Shape

- Reuse existing `HowlVtCallStatus`.
- Do not add a feature/reason enum.
- Do not add a generic event payload.

### Proposed Types

```c
typedef struct {
  uint8_t pending_now;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t deadline_ns;
} HowlVtRuntimeObligation;

typedef struct {
  int32_t status;
  HowlVtRuntimeObligation obligation;
} HowlVtRuntimeObligationResult;

typedef struct {
  int32_t status;
  uint8_t state_changed;
  uint8_t reserved0;
  uint16_t reserved1;
  HowlVtRuntimeObligation obligation;
} HowlVtRuntimeProgressResult;

HowlVtRuntimeObligationResult howl_vt_terminal_query_runtime_obligation(
    HowlVtHandle handle,
    uint64_t now_ns);

HowlVtRuntimeProgressResult howl_vt_terminal_progress_runtime(
    HowlVtHandle handle,
    uint64_t now_ns);
```

### Field Semantics

- `pending_now = 1`
  - owner-thread deferred VT work is due now
  - host should call `progress_runtime()` on the owner thread without waiting for PTY input
- `deadline_ns`
  - absolute monotonic deadline in the host clock domain
  - `0` means no future deferred VT work is scheduled
- `state_changed = 1`
  - one bounded runtime progress step mutated VT state

### Contract Rules

- `query_runtime_obligation()` must not mutate VT state.
- `progress_runtime()` performs one bounded deferred-work step only.
- `now_ns` must be passed into both calls.
- Host should pass fresh monotonic time to each call site.

### Header Placement

- Add a new header section:
  - `/* 3. Runtime Obligation */`
- Place the new types and functions after protocol metadata host output and before shell input.
- Renumber shell input to section 4.
- Keep shell input title text unchanged.

## Accepted Host-Loop Fit

- Do not create a new background thread role.
- Keep the existing PTY wait thread PTY-only.
- Owner thread should:
  1. query VT runtime obligation per tab using current `now_ns`
  2. merge VT deadlines with existing host deadlines such as cursor blink
  3. avoid blocking if any tab reports `pending_now`
  4. after input/events and PTY progress, call `progress_runtime()` once for each due tab
  5. request another owner-thread turn if progress still reports `pending_now`

### PTY Thread Rule

- The PTY wait thread must remain PTY-readiness-only.
- It must not:
  - own VT timers
  - call VT progress
  - become a generic wake broker

## Minimal Conceptual Host Changes

- Add VT ABI wrappers for runtime obligation query/progress.
- Extend loop wait-time calculation to include VT `deadline_ns`.
- Treat VT `pending_now` like another source of immediate owner-thread work.
- Extend the bounded terminal progress turn so it can do:
  - PTY slice
  - one VT runtime progress step
  - normal consequence draining after that step

## Final Recommendation

- Ship exactly this two-call runtime seam.
- Keep it feature-agnostic.
- Keep VT as owner of deferred protocol state.
- Keep host as owner of time source and scheduling.
- Keep render unaware of animation semantics.
