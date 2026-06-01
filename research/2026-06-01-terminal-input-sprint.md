# Sprint: Terminal Host Input Adaptation Owner

Accepted research caches:

- `research/cache-2026-06-01-terminal-chrome-owner.md`
- `research/cache-2026-06-01-terminal-non-pty-non-surface-inventory.md`

Reviewer decision:

- Accepted for planning.
- Rejected a broad `terminal/chrome.zig`, `terminal/ui.zig`, or `terminal/overlay.zig` owner as not source-backed.

## User Direction

- Create an interior terminal owner for behavior that is not render surfaces and not PTY.
- Alacritty is source truth for host/input/display organization.
- TigerBeetle enforces owner truth, assertions, bounds, directness, and tests.
- No Howl-only bucket owner.

## Accepted Decision

- Do not create a broad terminal chrome/UI/overlay owner.
- First source-backed cut is `terminal/input.zig`, matching Alacritty `input/mod.rs` / `ActionContext` as terminal host input adaptation.
- Existing owners remain separate: `terminal/links.zig`, `terminal/selection.zig`, `terminal/scrollbar.zig`, `terminal/cursor_blink.zig`, `terminal/vt/input.zig`, and `terminal/vt/surface.zig`.

## Non-Goals

- No public C ABI changes.
- No PTY lifecycle, PTY transport, render-surface submit/upload, display presentation, or GL resource movement.
- No title/focus/cursor-blink extraction in this cut.
- No broad owner named `chrome`, `ui`, `overlay`, `manager`, `controller`, `engine`, `utils`, or `types`.
- No duplicate test root or weakened tests.

## Cut 1: Terminal Input Adapter Extraction

Owner: worker after this scratchpad/current slice is reviewed and committed.

Purpose: move terminal host input adaptation out of `terminal/context.zig` into source-backed `terminal/input.zig`, while preserving existing public `Context` call sites as thin owner entrypoints where needed.

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/input.zig`

Required shape:

- Create `terminal/input.zig` as the terminal host input adaptation owner.
- Move `Context.DrainInputOutcome` to `terminal/input.zig` as `DrainInputOutcome`.
- Keep `pub const DrainInputOutcome = terminal_input.DrainInputOutcome;` in `Context` if current callers still use `TerminalContext.DrainInputOutcome`.
- Move `drainTextInputFastPathWith(...)`, `drainPointerAndUiInputWith(...)`, `handleTextInputFastPathEvent(...)`, and `handlePointerAndUiInputEvent(...)` logic into `terminal/input.zig`.
- Move or expose the local helper result shapes needed only for input routing: `ScrollMouseOutcome`, `ScrollVisualState`, and `MouseHandlingOutcome` only if they are input-adapter-local. Do not move owners from `links`, `selection`, or `scrollbar`.
- Keep `Context.drainTextInputFastPath(...)` and `Context.drainPointerAndUiInput(...)` as thin wrappers if main/app tests rely on the current `Context` API.
- Preserve text fast path ordering: compact pointer/UI events first, publish text bytes first, then pointer/UI drain later.
- Preserve pointer/UI routing order: scrollbar, content-relative clipping, wheel VT-or-scroll fallback, selection, links, host-only hover clear, VT mouse publication.
- Add assertions around bounded input queue compaction: read index, write index, and final length stay within `input_events.buf.len`.
- `terminal/input.zig` may use an ops struct only if it is a small intentional adapter with exact callbacks required by the moved code. It must not become a broad bucket.

Must stay out of `terminal/input.zig`:

- PTY lifecycle and `driveProgress`.
- `terminal/vt/input.zig` encoding owner.
- Render-surface submit/upload or retained render owners.
- Display presentation, frame pacing, render-surface resource realization, or GL state.
- Title/focus/cursor blink state extraction.
- Link, selection, scrollbar, and cursor blink owner files.

Required tests:

- Preserve existing tests in the single host test flow:
  - text fast path publication and no pointer/UI calls.
  - mixed input compaction and text-before-pointer order.
  - pointer/UI host visual mutation separation from PTY publication.
- If tests move to `terminal/input.zig`, the existing `test-terminal-context` path must still reach them without a new test root.
- Add no duplicate test root.

Verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan reports zero lines over 190 chars.

Grep gates:

- No `howl-linux-host/src/terminal/chrome.zig`.
- No `howl-linux-host/src/terminal/ui.zig`.
- No `howl-linux-host/src/terminal/overlay.zig`.
- No new `manager`, `engine`, `controller`, `utils`, or `types.zig` owner.
- `terminal/input.zig` must not import `howl_pty_c`, `howl_render_c`, `../display/renderer/render_surface.zig`, or `../app/present.zig`.
- `terminal/input.zig` must not contain `ensureSurface`, `uploadRenderSurface`, `submitPrepared`, `renderTurn`, `driveProgress`, `pty_session`, or `Display`.

Stop conditions:

- Stop if implementation needs a broader owner name than `terminal/input.zig`.
- Stop if the extraction requires a public C ABI change.
- Stop if tests need weakening, filtering, duplication, or a second module entrypoint.
- Stop if PTY/render/display/title/focus/cursor-blink behavior must move to make this compile.
- Stop if an ops struct becomes a bucket for unrelated terminal state.

## Follow-Up Candidates

- Link state migration into `terminal/links.zig` if source-backed by current code and tests.
- Selection field migration into `terminal/selection.zig` if source-backed by current code and tests.
- Cursor blink call-surface cleanup after input extraction.
- Title/focus adapters require separate source-backed planning; do not hide them under chrome.

## Signoff

- Research cache accepted: yes.
- Scratchpad reviewer status: pending.
- Cut 1 implementation status: pending.
- Verification status: pending.
