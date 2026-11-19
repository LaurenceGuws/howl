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

## Retire the superseded Vulkan/Wayland host (14 November 2026)

With the direct PTY/VT/Text `howl-app` path accepted for dogfood, retire
`hosts/howl-host`, `mods/howl-vk`, and `mods/howl-wayland`. Remove their
workspace dependencies, consumer imports, snapshot inventory, and active
build/audit/source-map claims. Their former presence in earlier decisions
remains historical evidence, not a current release or compatibility contract.

This is a repository-source cleanup, not a change to the installed daily app.
`howl-instance` and `howl-render` remain independent, tested public packages
with live native/consumer contracts; their possible retirement requires its
own dependency-closure review. The old Flutter tree remains an explicitly
inactive reference, not part of this deletion.

The new workspace snapshot is `0.1.11-dev`. Qualification: `zig build check
test -j4`, Zig formatting, source-reference sweep and Git diff checks passed.

## Flatten maintained package roots and retire Flutter (14 November 2026)

Captain approved dropping the old `mods/` and `hosts/` grouping. The six
maintained packages are now direct repository children: `howl-vt`,
`howl-pty`, `howl-text`, `howl-render`, `howl-instance`, and `howl-app`.
Each keeps its own manifest, independent version and owned build/audit/test
gates. The root remains the curator, not a replacement package owner.

The unsupported Flutter bring-up source and its old Linux engine patch are
retired, together with the outdated Odin/Web ABI design HTML. The Flutter
audit exception is deleted. The performance race harness and its measured
historical reports, native package-release tool/overlays, project audit, and
JSONL logger still have concrete uses and are retained. `test/consumer`
remains a nested external-distribution proof helper, not an app or library
to promote. Howl Sessions hosts are not a gate for this cleanup.

Workspace snapshot `0.1.12-dev` records the moved source tree without
changing the individual package versions. The installed daily `howl-app`
binary is not modified by this repository cleanup.

## Retire standalone Instance and Render (14 November 2026)

Captain approved retiring the independent `howl-instance` and `howl-render`
Zig/C products after source dependency review. No maintained Howl host uses
either. The local `howl-app` composes PTY, VT and Text directly; sibling
Howl Sessions hosts are deferred and are not migration gates. Previously
published archives/tags remain historical, not supported future contracts.

Keep the standalone VT native API and its externally linked consumer proof.
Move VT-owned opaque-output, shared-store and glyph-cache tests from the
legacy Render build into a separate root VT/Text composition, without making
plain VT import Text or reconstructing a renderer abstraction. Retire old
native ABIs, release overlays, build exports and stale active contracts.
Host consequences now cite the direct SDL app owner and tests in the protocol
catalogue; the canonical VT still has no host/platform dependency.

Workspace snapshot `0.1.13-dev` changes the active package inventory only;
no installed daily binary, Howl Sessions checkout, or historical performance
measurement is modified as part of this source retirement.

## Narrow direct-output repair (15 November 2026)

The VT output owner may publish a bounded horizontal pixel-damage band for
an exact, small row-command transition. The SDL app may reuse that band only
when its retained content matches the immediately preceding output revision;
missed cuts, resource or visual-context changes, and broad mutations retain
the full-row/full-frame recovery paths. This is not a second cell authority.

Private KWin A/B proved substantially fewer submitted textured quads on
sparse edits, but no repeatable process-CPU improvement. Keep source and
daily-binary promotion separate: the installed Howl is unchanged, and no
Hyprland promotion claim follows from the KWin iteration. Disposable race
receipts remain under the `howl-current` U7 workstream, not product tooling.

## Persist explicit discovery as read-only profile cache (18 November 2026)

Captain accepted replacing the startup auto-discovery route with an explicit
Profiles scan. The sidebar has one Profiles section; the saved-profile field
editor becomes its internal details view, not a second sidebar destination.
Scanned shell, REPL and SSH recipes are read-only, individually enableable, and
can be duplicated into fully independent editable saved profiles.

Two reconciliation policies are explicit: a scan retains entries that vanished
from the scanned source and marks them stale; duplicating a scanned entry does
not create a live link to that discovery. User disable choices survive future
scans. Scans read selected sources and stage changes in the same global
Save/Cancel transaction as other settings. Only saved cache is used on startup
and in the launch picker. Disabled or stale entries are not suggested. The
saved-default selector initially contained only Local and manual profiles.

Captain's follow-up clarified that cached, enabled, non-stale discoveries are
also eligible as startup defaults, without first duplicating them. The default
resolves by persistent recipe ID, never launch-picker position. Disabling a
chosen scan or rescanning it as missing stages a reset to Local; the existing
Save/Cancel transaction owns that change. Missing/disabled discoveries stay
cached but are excluded from the startup selector. The Profiles footer always
remains visible as the list scrolls; unavailable selections cannot set default.

## Profiles scroll ownership matches other Settings pages (19 November 2026)

Captain rejected relocating the Profiles scrollbar without changing its
owner: a scrollbar visually beside cards must scroll the complete page, not
an internal list. Profiles now uses the same page-owned FormViewport as
Appearance, Colors and Shortcuts. Its Discovery controls, Saved profiles and
Scanned profiles are separate cards inside that one clipped scrollable page;
the saved-profile details editor also uses a page-owned viewport. Rows retain
only hit geometry and selected profile identity, never a second scroll offset
or list viewport. The Set default footer stays outside the scrollable body,
so scrolling cannot change the selection or the Save/Cancel transaction.

## Extract Settings presentation from the SDL host (19 November 2026)

Captain rejected adding another feature to a 6,084-line main.zig as an
acceptable long-term shape. Settings policy remains in settings.zig, while
settings_pages.zig now owns the five pure viewport/card geometries,
settings_input.zig owns pointer/keyboard routing and scrolling, and
settings_paint.zig owns SDL Settings drawing. The concrete host binds the
UI methods at compile time and retains the existing draft, font, persistence
and terminal lifetime authority; the extraction creates no second runtime
controller or configuration copy. Settings-specific interaction, geometry
and software-render proofs moved to settings_ui_test.zig. General host and
terminal tests remain in main.zig.

## Settings corners follow tab chrome (19 November 2026)

Captain selected the tab chip's four-logical-pixel radius as the common
Settings shell, card, control, field, dropdown and row-highlight radius.
One-pixel-inset surfaces use a three-pixel radius, and the header/sidebar
elbow exposes the same rounded inner corner. Switch tracks retain their
functional pill shape; narrow scrollbar tracks and thumbs remain distinct.

## Retire page-specific Settings footers (19 November 2026)

The Profiles Set default footer was redundant with Startup's default-profile
selector, which already accepts enabled, non-stale scans and stages changes
under global Save/Cancel. Profiles now uses the whole scroll viewport without
an independently fixed action. Colors likewise uses that full viewport:
the terminal sample is a scrolling preview card, and selecting a color
expands its RGB sliders and Preset control directly under the edited row.
Closing the inline editor shifts later rows, so a click outside first stages
the value without retargeting the same pointer event to a moved control.
Only the global Settings header actions remain fixed.

This clears page-specific footer ownership but does not yet combine the five
page viewports. A single document will require shared section anchors,
one scroll offset and active-section tracking; Profile details must also
become an inline disclosure rather than a separate internal page.
