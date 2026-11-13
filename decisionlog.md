# Captain's decisions

## Separate terminal primitives from the Sessions product family

Recorded 2 November 2026 from Captain's explanation of the earlier decision.
This is the rationale for the existing split, not a new migration instruction.

**Decision:** Server, its supporting protocol/client owners, and Flutter belong
in the sibling Howl Sessions project. Howl retains its embeddable terminal
primitives and direct-local application hosts.

**Why:** Server and Flutter began as canaries, but their bring-up increasingly
dictated Howl's scope. Moving them out protects the terminal core from
orchestration and host-specific concerns. This was an intentional ownership
boundary, not an invitation to reunify the repositories for convenience.

The separate product consumes explicit core interfaces. It must not make a
local Instance depend on Server or Session merely to host a terminal.

See [Howl Sessions decisions](https://github.com/LaurenceGuws/howl-sessions/blob/main/decisionlog.md) for the product
promotion and fresh Flutter host rationale. Neither promotion means that all
features are complete or production-qualified.

## One Instance composition path

Recorded 11 November 2026 from Captain's instruction:

> instance has only 1 accepted path that includes pty-tv-render-embedder's gpu and nothing else.

Captain clarified that this applies to the Instance module and Howl's docs,
with Session work deferred. Instance composes PTY, VT and Render; the embedder
owns the GPU backend, UI, window and platform lifecycle. VT and PTY remain
independently usable. Remove alternate Instance construction paths first, then
remove duplicate bookkeeping and compare performance for regressions.

## Direct howl-app first; simplify the terminal composition

Recorded 13 November 2026 from Captain's direct-output migration clarification.
This changes the migration sequence and intended end state described above;
it does not require an immediate rewrite or removal of the existing Instance.

**Immediate priority:** `howl-app` remains Howl's main maintained host. Finish
and qualify its direct native path first, then integrate a coherent, proven
cut into `main`. `howl-host`, `howl-vk`, `howl-wayland`, and foreign consumers
are not prerequisites for this first integration.

**Target architecture:** Let the app own its local runtime composition of
PTY, canonical VT, and Text. An optional compile-time VT output owner can
produce backend-neutral drawing commands directly from the same canonical
terminal state; the app owns GUI waking, drawing, GPU resources, and frame
handoff. The existing semantic VT observation API is not a second terminal
model. Plain VT and PTY remain independently usable, and canonical input
must never wait for a drawing consumer or font presentation.

**Simplification goal:** Remove the intermediate VT-observation-to-Render-input
translation and the duplicate Instance/Render presentation path from the app.
Retiring the `howl-render` and `howl-instance` packages entirely is a possible
end state, not an immediate deletion requirement. Retain only concepts that
buy correctness, capability, clear ownership, or measured performance.
The drawing path should skip the semantic-observation-to-Render-input stage;
the canonical VT observation API still serves selection, history, copy, and
other terminal queries without becoming a separate rendering state model.

**First-main-cut allowance:** Instance may remain temporarily if that is the
smallest correct integration. Do not let rehabilitating its accumulated
historical machinery block the working app. Bring Gandalf into a separate
architecture/source review before substantial Instance salvage or retirement;
preserve proven PTY service, backpressure, consequence, resize, and lifetime
behavior rather than rewriting it casually.
The first main merge requires `howl-app` to use the direct-output presentation
path exclusively, but does not require app-owned PTY/VT/Text composition or
removal of the legacy implementations elsewhere. Work toward those later,
from the proven app path, rather than holding the first integration for them.

**Other hosts and Server:** Plan to retire `howl-host` and its Vulkan/Wayland
code shortly after the app happy path is qualified. Their GUI libraries could
potentially be repurposed by the young experimental Howl Server, but that is
a later design choice, not a dependency or preservation obligation today.
Captain discarded the previous Server/Client module design and has begun
rebuilding that experiment; do not silently restore the rejected design.

**Acceptance:** Preserve OSC 66, history, selection, graphics, exact failure
recovery, bounded resource lifetimes, and clean independent module ownership.
Compare identifiable source-to-binary builds and real app behavior before
promotion; installed Howl stays untouched until the candidate earns it.
The first redesign is not required to match the highly optimized accepted
build's throughput. Measured regressions are an optimization backlog, not an
automatic reason to reject a correct, bounded, simpler first integration;
report their real magnitude, affected workloads, and uncertainty without
claiming performance parity. Favor independent Comrade source review on
substantial cuts before Captain's acceptance, while normally working
interactively.

## First-main integration scope: shared core plus direct app

Recorded 14 November 2026 after an independent review of the 69-commit
`experiment/vt-direct-output` dependency closure and Captain's approval.

**Approved scope:** The first main cut may carry the shared VT output/Text
extraction, canonical scalar/history and retained-input recovery improvements,
versioned VT native ABI v2 and Instance native ABI v3, and the necessary
`howl-host` poll adaptation, together with the direct-only `howl-app`.
These are explicitly shared-core changes, not a claim that only app source
changes. `howl-host` remains on its legacy Render presentation path; Vulkan,
Wayland, other foreign consumers, and Howl Server do not migrate as part of this
cut.

**Sequence:** Prefer the already-qualified dependency closure to a cosmetic
cherry-pick/reconstruction that would require fresh behavioral qualification.
The eventual review history may be curated, but any squash changes history,
not the accepted source/behavioral scope.

This is **scope approval**, not permission to skip the remaining app dogfood,
accepted-versus-candidate measurements, final integrated-source gates, or
independent review. It does not approve replacement of the installed
`howl-app` binary. Main integration and installation remain separate gates.
