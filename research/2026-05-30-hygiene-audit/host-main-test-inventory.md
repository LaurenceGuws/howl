# Host Main Test Inventory

Date: 2026-05-30

Owner: workspace root first; `howl-linux-host` implementation only after one exact helper/test owner is
proved.

Purpose: inventory tests embedded in `howl-linux-host/src/main.zig`, classify each test, and choose at
most one safe helper/test move without public test aliases.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/build-test-architecture-plan.md`
- `research/2026-05-30-hygiene-audit/host-admission-gate.md`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/window/pacing.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/build.zig`

## Current Test Inventory

| Test | Exercised symbols | Classification |
| --- | --- | --- |
| `derivePresentReason matrix names host and terminal present cadence` | `derivePresentReason`, `PresentReason`, `TerminalContext.TurnStep` | Move candidate: present-turn policy belongs with host present planning, currently still in app owner. Needs exact owner before moving. |
| `runtime obligation due-now is treated as immediate loop work` | `tabsHavePendingRuntimeObligationWith`, `FramePacing.State.shouldWaitForWindow` | App loop admission plus frame pacing. Stay until runtime admission owner is proved. |
| `runtime obligation deadline is merged with blink wait by minimum` | `minRuntimeObligationWaitMsWith` | App loop wait policy. Stay. |
| `frame deadlines participate in wait calculation` | `loopWaitMsWith` | App loop wait policy. Stay. |
| `active window title sync uses the active context title` | `syncActiveWindowTitle` | Move candidate if title sync owner exists; today app coordinates active tab and window. Stay. |
| `child environment policy sets TERM in the app owner` | `applyChildEnvironmentPolicy` | App bootstrap/process environment. Stay. |
| `PTY publication admission keeps next turn non-blocking without present intent` | `takeTerminalInputAdmission`, `FramePacing.State.shouldWaitForWindow` | App loop admission. Stay. |
| `forward terminal input drains text before pointer UI without present intent` | `forwardTerminalInputFlow`, `deriveRedrawRenderIntent`, `takeTerminalInputAdmission`, `derivePresentReason` | Move candidate: input forwarding order may belong in terminal/input adapter, but current helper uses app layout facts. Needs separate owner proof. |
| `host visual change can trigger present without PTY publication` | `TerminalContext.DrainInputOutcome`, redraw booleans | App redraw/present policy. Stay. |
| `runtime keepalive wake stays separate from host dirty` | `FramePacing.State.shouldWaitForWindow`, `derivePresentReason` | App loop admission plus pacing. Stay. |
| `runtime keep_running does not synthesize redraw` | `deriveRedrawRenderIntent`, `derivePresentReason` | App runtime-to-render intent policy. Stay unless render-intent owner is extracted. |
| `keep_running true should_redraw false keeps host non-blocking without redraw or present` | `deriveRedrawRenderIntent`, `FramePacing.State.shouldWaitForWindow`, `derivePresentReason` | App loop admission. Stay. |
| `host_redraw_requested true can produce host-only present` | `deriveRedrawRenderIntent`, `derivePresentReason` | App/render-present policy. Stay. |
| `render_work_pending true produces render without host redraw bit` | `deriveRedrawRenderIntent`, `derivePresentReason` | App/render-turn policy. Stay. |
| `present completion only follows terminal present reasons` | `submitPresentWith`, `completeTerminalPresent` | Move candidate: present submission/completion policy can move to exact window/present owner. |
| `terminal retire submit does not require a new snapshot` | `submitPresentWith`, `recordPresentSubmissionFor` | Move candidate: present submission/completion policy. |
| `terminal retire does not clear pending retained completion` | `drainPresentComplete` | Move candidate: present completion state machine. |
| `terminal frame original token completes retained state` | `recordPresentSubmissionFor`, `drainPresentComplete` | Move candidate: present completion state machine. |
| `submit and drained completion are distinct host actions` | `drainPresentComplete` | Move candidate: present completion state machine. |
| `host damage drained completion does not call terminal completion` | `drainPresentComplete` | Move candidate: present completion state machine. |
| `terminal present completes only after drained matching token` | `drainPresentComplete` | Move candidate: present completion state machine. |
| `render facts matrix separates host redraw terminal redraw and frame work` | local matrix over `derivePresentReason` inputs | App/render-present policy. Stay unless present policy owner is extracted. |

## Owner Findings

- `main.zig` owns app loop sequencing, active tab selection, wait admission, and present submission
  orchestration today.
- `window/pacing.zig` already owns frame permit and present-in-flight pacing state, but it does not own
  terminal present token completion because that mutates app-owned `pending_terminal_present` and calls
  terminal contexts.
- `terminal/context.zig` owns per-terminal retained present completion through `notePresentSubmitted`
  and `completePresent`, but it does not own app-level matching against window completion tokens.
- A new broad `present` manager/controller would violate the host admission gate. If extracted, the
  owner must be exact: app present completion/submission policy, not generic runtime or presentation.

## Decision

Do not move tests directly out of `main.zig` yet.

The only source-backed implementation candidate is to extract app present submission/completion policy
into an exact owner file under `howl-linux-host/src/app/present.zig` or similar. However, this creates a
new app subowner path and needs its own promoted slice because it moves behavior, not just tests.

The safe next implementation slice is therefore not a test relocation. It is an owner extraction:
`Extract Host App Present Policy`.

## Proposed Next Implementation Slice

Name: `Extract Host App Present Policy`.

Exact owner:

- New file: `howl-linux-host/src/app/present.zig`.
- Owner: app-level present submission/completion policy that coordinates window present tokens,
  terminal retained present completion, and frame pacing notification.

Exact symbols to move from `main.zig`:

- `PresentReason` alias remains under review: either keep alias in `main.zig` or import from owner.
- `PresentPlan`
- `PresentSubmission`
- `derivePresentReason`
- `derivePresentPlan`
- `submitPresentWith`
- `recordPresentSubmissionFor`
- `drainPresentComplete`
- `completeTerminalPresent`

Symbols likely to stay in `main.zig` for now:

- `submitPresent`, because it constructs app-specific `RenderFrame` and calls frame pacing. It may
  become a thin caller into `app/present.zig`.
- `noteFramePacingPresentComplete`, unless the new owner can accept a tiny interface without making
  app structure generic.

Tests to move with owner:

- `present completion only follows terminal present reasons`
- `terminal retire submit does not require a new snapshot`
- `terminal retire does not clear pending retained completion`
- `terminal frame original token completes retained state`
- `submit and drained completion are distinct host actions`
- `host damage drained completion does not call terminal completion`
- `terminal present completes only after drained matching token`

Non-goals:

- Do not move runtime wait/admission tests.
- Do not move input-forwarding tests.
- Do not change present behavior.
- Do not create `manager`, `controller`, or `runtime` vocabulary.
- Do not expose private helpers publicly just for tests.

Verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test`.
- From root: `zig build check`.
- From root: `zig build test`.
- `git diff --check`.

Grep gates:

- `rg 'manager|controller|runtime|types\.zig|api\.zig|abi\.zig' howl-linux-host/src/app howl-linux-host/src/main.zig`
- `rg '^test "(present completion|terminal retire|terminal frame|submit and drained|host damage drained|terminal present completes)' howl-linux-host/src/main.zig` prints nothing after the extraction.
- `rg '^test "(present completion|terminal retire|terminal frame|submit and drained|host damage drained|terminal present completes)' howl-linux-host/src/app/present.zig` proves moved tests live with owner.

Stop conditions:

- Stop if the extraction requires changing `App` layout.
- Stop if helper signatures become vague `anytype` buckets without exact present-policy meaning.
- Stop if app loop sequencing moves out of `main.zig`.
