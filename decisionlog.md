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

## One scrolling Settings document (19 November 2026)

Captain accepted retiring the five independently navigable Settings pages.
The sidebar is an index over one continuous Startup, Appearance, Color schemes,
Shortcuts and Profiles document, with section anchors and active-section
highlight derived from the document's scroll position. One clipped viewport
owns the scroll offset and outer scrollbar; existing forms borrow positioned
subregions and do not own scrollbars. Their category cards and rounded chrome
remain intact.

Saved-profile details expand directly beneath the chosen saved row inside its
card, with Close/Duplicate/Delete in the expanded region and all mutations
staged under the unchanged global Save/Cancel transaction. Color editors and
profile details grow the measured document, moving subsequent sections with
the same pointer/paint geometry. Global Search temporarily displays results
and reveals the matched field back in the document. Field activation and
section routing now live in settings_input.zig rather than main.zig; main.zig
retains live config, draft persistence, and terminal ownership.

## App ownership-first refit (19 November 2026)

Howl App is the target, with other independently versioned modules in scope
only when an issue belongs to their owner. Keep observable behavior and the
accepted Settings UI unchanged; prefer direct Zig modules, removing redundant
code and historical names before adding structure. The first terminal-chain
cut names the app-owned PTY/VT service `pty_vt.zig`, its borrowed output lease
owner `projection.zig`, and its terminal-originated reply policy
`consequences.zig`. The independent output test is named for its current
purpose rather than the original migration. The opaque terminal worker and
SDL boundary remain unchanged.

## Keep output and scrollback policy with the terminal worker (19 November 2026)

The app's publication gate and retained-history viewport were previously
grouped in `publication.zig`, although no other module owned or reused either.
Both are now private `OutputGate` and `HistoryViewport` state machines beside
the worker state in `terminal.zig`, with their existing tests preserved there.
Only the worker sets the publication deadline and its visual scrollback anchor;
the canonical VT still owns retained history and terminal semantics. This
retires a redundant module and import, not a production behavior or boundary.

## Settings painter is not an App method catalogue (19 November 2026)

The SDL host now invokes the Settings painter through its explicitly typed
module function, not through 18 forwarded App method aliases. Painter-internal
calls stay with that module. The remaining shared color resolution moved from
the painter into `settings.zig`, where both the editor and its visual preview
consume the same validated configured color. The Settings layout, controls,
scrolling, draft transaction and rendered pixels remain unchanged.

## Settings input is a direct module, not an App method catalogue (19 November 2026)

The remaining 55 Settings input/geometry aliases were removed from `App`.
The concrete host now calls `InputUI` and `PaintUI` module functions directly;
both modules use their own typed methods with the same borrowed `App` pointer,
not a second configuration owner. Tests exercise those module functions
directly. Together with the prior painter cut, all 74 forwarded aliases are
retired. Settings interaction, search, scrolling, layouts, Save/Cancel and
software-render tests retain their accepted behavior.

## App names follow their current owners (19 November 2026)

The terminal worker's shared completion condition is `request_completed`:
configuration and copied selection both wait on it, without introducing a
generic request owner. A terminal task retries worker-side output projection,
so its tag is `retry_projection`, not the retired `retry_render`. Internal
split actions now name the resulting pane placement (`split_right` and
`split_down`), leaving layout-axis semantics and routing unchanged. Two
visible pane size-control actions no longer refer to the removed Instance
product. All persisted shortcut IDs, including `recover_instance`, and their
existing configurations remain unchanged. Focused tests prove the action
registry identities and projection-retry state; terminal concurrency and
Settings tests remain in the full repository graph.

## One SDL clip coverage rule (19 November 2026)

The app's physical clip bounds are owned by `pixels.clipBounds`: floor the
origin and ceil the far edge of an SDL float rectangle. The shared pure
conversion now serves Settings/UI `setClip`, Canvas command/overlay clipping,
and the closed/error pane overlay in `main.zig`. This replaces three copies
of the same coverage rule, while keeping the distinct nearest-edge stroke
rounding policy unchanged. Fractional, negative, tiny and empty rectangles
are checked alongside a software-renderer clip roundtrip and Canvas's
existing 10,000-case intersection oracle and exact-pixel tests.

## Canvas uploads follow exact snapshot ownership (19 November 2026)

Only the native `Canvas.update` path admits immutable VT output, and only
`Canvas.applySnapshotResources` owns presentation-generation resets and
stale-resource retirement. The old public `applyResources` multi-upload/removal
transaction had no production caller beyond the single-resource snapshot path;
its extra array, pixel-offset and removal policy duplicated existing work.
Canvas now uploads one exact borrowed `output_commands.Residency` and its
tightly packed alpha or RGBA pixel slice through a private `uploadResource`.
It still allocates and populates the replacement before retiring any existing
texture, with `errdefer` candidate cleanup. Snapshot application also stays
private to Canvas; other app modules consume it through `update` only.
Direct Canvas raster tests retain their upload assertions, and a new injected
allocation-failure test proves the previous accepted texture survives and
replacement succeeds on retry. Other validated output-owner and host API
boundaries stay unchanged.

## Header clicks use the header's one classifier (19 November 2026)

The host's `pointerDown` now switches on `chrome.headerAt` rather than
reimplementing tab/close/button hit classification with repeated rectangle
checks. `chromeEvent` still intercepts native caption presses/releases first;
`App` still owns selected-tab handoff before close, double-click rename,
chip drag capture, and overlay/navigation effects. SDL tests exercise actual
pointer actions for fixed and fitted tab strips, at both 600 and 1,000-pixel
window widths, including non-active close, menu/settings, and native button
release cancellation. This is one less independent hit route, not a new input
controller or changed pane lifetime.

## Paint the retained header from one accepted picture (19 November 2026)

`HeaderPicture` now supplies the palette, target hover, tab selection and
geometry, drag position, maximize state and explicit text scale consumed by
header painting. `App` constructs these inputs once per header state; drawing
no longer re-reads the live window/configuration/pointer for its paint policy.
The raw action-button hover is separately retained because actions may still
highlight during a tab drag while tab-body hover is suppressed. Cache equality
includes it, eliminating an otherwise unkeyed visual dependency. Text glyph
sizing now accepts the captured scale through the existing text-draw path;
ordinary UI callers continue using the current window scale.

SDL software-render regression compares direct and retained header pixels
exactly at integer scale across tab, button, drag, fitted width and palette
transitions. The compositor's target-texture resampling at 1.25x can yield
different bytes than direct primitive rasterization, so fractional-scale
coverage instead requires exact equality for a retained cache rebuild and
reuse. A frozen HeaderPicture also paints identically after unrelated live
App state changes, while changing its captured maximize flag changes icon
pixels. Cache size limits and direct-draw fallback are unchanged.

## Pinned protocol census describes actual evidence (20 November 2026)

The schema-3 protocol census remains 662 reference-specific records across
34 groups with separate support and residual-disposition fields. Correct
catalogue wording when source/tests have moved or new behavior landed, without
increasing the support score or silently moving a reference revision. In
particular, the pinned Kitty DECSTR switch rejects CSI ! p even though Howl
and newer Kitty implement it, and current Howl already decodes bounded direct
PNG f=100 graphics. Ordinary and selective graphics erasure need distinct
residual descriptions. Comma-bearing YAML flow values must be quoted; the
catalogue validator now rejects unknown howl-record fields, with a corrupt
fixture confirming it catches the prior split-rationale failure.

## Protocol proofs use executable test names, not stale source lines (20 November 2026)

The proof census keeps each cited source path and exact named Zig test, but
drops 52 optional test declaration line numbers that had all drifted. Fifty
stale proof-name references now resolve to maintained tests; the three CSI T
scroll-down records use a new terminal-stream proof of bounded margins,
cursor and text mutation rather than an oversized Screen no-op. Existing
DECSCUSR and Kitty cursor-appearance DCS proofs now include non-factory
configured defaults across both banks, visibility and cursor colors.
All 617 proof-bearing records resolved to named declarations after the fix;
declaration-aware validation is a separate later change, not established by
path-only protocol validation. Reference source line anchors remain intact.

## Protocol source citations follow their semantic owners (20 November 2026)

The protocol census's implementation source/symbol fields identify the
function that actually performs each action, not a stale pre-extraction
wrapper or a read-only observation view. The 153 verified stale citations
now resolve to Screen, color_control, mode_report, modes, properties,
iterm_control, charset, consequences and true Terminal action methods.
Twelve additional observation-view citations now point to the actual color
or graphics action (iTerm SetColors retains its distinct command owner).
All 165 normalized citations changed without changing support/disposition,
reference pins, test proofs or VT behavior. A declaration preflight resolved
all 614 cited owners; a maintained negative-tested validator must enforce
that invariant separately, without mistaking a matching method for complete
semantic protocol equivalence.

## Protocol evidence links are mechanically checked (20 November 2026)

After restoring 153 outdated owner citations and redirecting 12 getter-only
citations to their action owners, a declaration-aware lexical inspection
caught 41 additional references that named real Zig functions without their
owning Terminal, TerminalStream or Parser type. The catalogue now cites the
actual method declarations. Two iTerm title/icon conditions were also found
to have silently split at YAML commas; they are quoted as complete strings.
All 662 records retain their support ratings, dispositions, and pinned
reference revisions.

The maintained protocol validator rejects unknown reference, group, record
and Howl fields; checks source/proof paths are canonical and repository-local;
resolves source functions and Type.methods to actual Zig declarations rather
than call sites, comments or strings; and checks exact named test declarations
against the static imports of maintained test roots and build registration.
A bounded, read-only Python standard-library scanner performs this work once
per source file, through the existing Nu command. Sixteen positive/negative
fixtures run in the root protocol build gate, alongside the ordinary catalogue
validation. A disposable malformed-title YAML fixture also produced a
record-specific diagnostic. The result is citation validity, **not** proof of
semantic parity or a comprehensive AST/compiler-level analysis. The pinned
reference census count gate remains unchanged until separately reviewed
reference expansion.

## Reviewed reference-census inventory and Windows pilot (20 November 2026)

An independently maintained `protocol_coverage_inventory.yml` now records
exact reference pins, accepted group names and branch counts. The Nu validator
compares the catalogue against that manifest instead of hard-coding 34 groups
and 662 rows or trusting totals calculated from the catalogue itself. An
in-memory fixture suite proves that additional approved groups are admitted
while missing/unapproved/miscounted groups, wrong reference pins and incomplete
subtrees are rejected. The original libvterm, iTerm2 and Kitty snapshots and
all 662 of their records remain unchanged.

The first scoped expansion pins Windows Terminal at
`9853bc96076e811cef5eab4469095fc9be58201e`. Its four explicit records
cover OSC 52 set and ignored query, the optional clipboard-write DA1 extension,
and OSC 9;4 progress. Each is `unassessed` with an active *evidence-review*
obligation, not authorization to change VT, clipboard permissions or taskbar
policy. Pinned source functions and the four record IDs were independently
checked. The acceptance inventory is 37 groups and 666 reference-specific
records; a row count is a census scope check, not a compatibility score.

## Ghostty program-status reference is a scoped, optional host contract (20 November 2026)

The pinned Ghostty revision `5813c9461d5af78b6307a1254d00b1bc190eaccd`
is indexed only for OSC 7501 query and report. The query replies with a
fixed capabilities string *only when* the program-status effect is installed;
reports are bounded and delivered to that optional effect, otherwise ignored.
Howl's support remains unassessed, with active evidence review but no automatic
status UI or protocol implementation commitment. The review inventory increases
to 38 groups and 668 reference-specific records while all preexisting records
and their pinned revisions remain unchanged. The narrower observed scope avoids
misclassifying Ghostty's parse-only OSC 66/99/3008 branches as applied effects.

## New Kitty semantics use a delta pin, not a duplicate full census (20 November 2026)

The frozen Kitty reference remains at
`d4106ef2db687579a69fefc949a6dc1b662f3ca8`. The later reviewed
`f7a16a93191a1103665905398d807ca79dab74a2` is captured separately as
`kitty_delta`, a *new-semantic-subset* reference linked mechanically to the
older base revision. It adds four scoped facts: OSC 7501 program status,
indexed `f=8` and `f=16` image formats, and the `N=1` advisory eviction hint.
Existing commands such as CSI ! p keep their historical ID and earlier
recognition record; changed behavior is noted without duplicating that
identity. OSC 7501 is one wire family independently observed in newer Kitty
and Ghostty, not two required Howl implementations.

Scoped Windows Terminal and Ghostty references now also declare their partial
census nature explicitly. Their independently reviewed inventory includes
exact new-group ID rosters, not just counts. The validator proves pin, baseline,
scope, branch membership, and approved identity integrity, including rejected
wrong-branch and changed-base fixtures. Ten new reference records remain
unassessed with active *evidence-review* obligations; no feature, permission,
status surface or GPU policy is automatically authorized. The accepted
inventory now contains 41 groups and 672 reference-specific records while
all original 662 records, their full/partial/missing ratings and their pinned
revisions remain unchanged.

## Protocol completeness is presumed; exclusions need fresh proof (20 November 2026)

Captain raised full, useful terminal-protocol coverage to the default target.
Historical `partial/excluded` classifications, many inherited from July
intake, are not permanent product decisions. Their burden of proof is now on
the *exclusion*: cite the pinned reference branch and exact differing state or
observable effect; reproduce it through current canonical VT/PTY/host or GUI
tests; identify the correct layer and an alternative implementation; then
document a concrete incompatibility, safety boundary, or disproportionate
cost with a reviewed decision. Generic "outside the complete Howl family",
reference-specific diagnostics, and old tooling constraints do not suffice.

A protocol can be complete through a deliberate no-op when the reference also
has no protocol-visible action; reference logging is not a VT protocol effect.
For the 27 Kitty OSC selectors pinned as ignored cases, direct reference
dispatcher inspection and expanded VT turn-by-turn proofs establish stable
semantic/content identities, no reply or host consequence, bounded payload
cancellation, and recovery of subsequent valid text/OSC. These are now
`full/none`, not `partial/excluded`; 350 partial records become 323 without
a runtime behavior change. This is a classification correction, not 27 new
features. The next tranches must prioritize *newly completed* cursor/edit,
reports, colour and graphics behavior, with differential reference oracles and
deterministic private-seat acceptance where presentation is implicated.

Keep VT canonical and nonblocking. OS clipboard, permissions, window control,
file and remote execution belong to the host/PTY and still require explicit
consent/security gates; those gates are implementation requirements, not an
excuse for unexamined permanent exclusion. Record exact promoted IDs, before/
after counts, test gates and genuine blockers for each subsequent tranche.

## CSI row edits own cursor admission and graphics geometry (20 November 2026)

A differential review of the pinned Kitty CSI IL/DL/SU/SD handlers and current
Howl state transitions exposed real runtime defects, separate from stale
protocol classifications:

- Screen declined CSI L/M when the cursor was outside DECSTBM or DECSLRM,
  but Terminal still scrolled Kitty image placements. Graphics now follow
  precisely the Screen admission decision, including a rejected pending-wrap
  operation that only cancels wrap.
- Accepted CSI L/M return the cursor to column zero (the active left margin
  when DECSLRM is enabled), matching Kitty's pinned carriage-return effect.
  Rejected edits leave the cursor where it was.
- Text scrolls constrained to horizontal margins no longer move image
  placements outside those columns. Entirely contained placements scroll;
  straddling placements are retired without deleting image data, since one
  image anchor cannot represent a partially clipped row move.
- Full-screen LF without actual retained history now scrolls graphics with
  text. The previous shortcut incorrectly skipped graphics whenever vertical
  margins covered the screen, even when history was disabled or the row move
  was limited by horizontal margins. Normal retained-history views continue
  to follow their absolute row origin without duplicate image translation.

Red-before/green-after VT tests cover CSI L/M rejection, both admitted line
edits and cursor homing, CSI S/T column-limited motion, boundary-crossing
image preservation/retirement, and LF with/without history. The accepted
Kitty IL/DL/SU/SD catalogue records retain **partial/deferred**: exact pinned
multicell, selection and graphics/history semantics still need independent
proof. This checkpoint improves actual terminal behavior without altering
protocol status counts, host permissions or running GUI instances.

## CSI IL multiline preservation follows the pinned Kitty boundary (20 November 2026)

A red-before/green-after screen and OSC 66 terminal-stream differential
against Kitty's frozen `screen_insert_lines` handler identified excessive
cluster erasure in Howl's partial-height, full-width downward row move.
Kitty clears a multiline character at the top edge only when that cell is a
*continuation* whose lead lies above the insertion region, not when a complete
cluster begins at the insertion row and can move intact. Howl previously
cleared any cluster touching the top row and lost valid sized text.

`Screen.scrollDownRegionRestoring` now preserves complete top-row leads in
non-restoring full-width moves and still clears cross-boundary fragments.
Partial-column moves retain their conservative cluster cleanup, and history
restoration retains its separate protection. Adversarial Screen cases cover
complete, top-crossing, bottom-crossing and deleted clusters; the terminal
stream covers OSC 66 lead movement through fragmented CSI L/M, cursor homing
and the same height/width/x/y cell provenance. VT Debug/ReleaseFast and the
root ReleaseFast check/test, audit and protocol gates passed. This is actual
terminal behavior, not an index promotion: Kitty's `partial` status remains
until selection and further multiline/graphics semantics are proven.

## Admitted CSI line edits invalidate direct-app selections (20 November 2026)

Kitty's pinned `screen_insert_lines` and `screen_delete_lines` handlers
clear selections after an admitted edit, even when the selected row itself
is not rewritten. Howl's local selection owner previously validated only
bank/columns/history retention, allowing stale ranges to survive an in-place
CSI L/M row rearrangement.

VT now exposes a read-only `Observation.structuralEditGeneration` counter,
advanced only after Screen admits CSI L or M within active vertical and
horizontal margins. No selection state enters VT, and ordinary writes,
scrolling, fragmented or rejected line edits do not increment the counter.
The local app worker binds each new manual or search-result selection to the
observed generation; a later changed generation clears the selected range
and triggers immutable selection-overlay publication without blocking PTY
progress. Attempted extension of a stale selection is rejected before
its previous endpoints can be applied. Existing bank/history/geometry
invalidation remains intact.

VT and app in-process tests prove the positive and negative turns, including
rejected line edits, live output preserving selection, admitted IL/DL
invalidating the prior range, and a fresh selection surviving idle service.
The full root Debug/ReleaseFast affected-package tests, ReleaseFast check/test,
project audit, declaration-aware protocol validator, Zig format and diff gates
were green. This is a real local-app behavior improvement, not a claim of
full pinned Kitty selection/UI/graphics parity. No installed binary or active
user window was changed.

## Screen decides CSI IL/DL admission once (20 November 2026)

The earlier margin/graphics divergence was an ownership fault: Terminal
reimplemented Screen's IL/DL margin-admission predicate before calling the
real row mutator. Two independent copies could drift and cause rejected
text edits to move graphics or invalidate selections.

Screen now owns one `editLines(kind, count)` operation returning separate
`admitted` and `changed` facts. It shares cursor/margin admission, row
motion, and cursor homing between IL and DL; Terminal consumes the admitted
result to apply graphics movement and the structural-edit generation, with
no duplicate margin predicate. The distinction matters when a rejected
command merely cancels pending wrap: `changed` can be true while
`admitted` remains false. Owner and terminal-stream tests prove that
case, along with ordinary admitted edits, including selection generation.
The six protocol source citations now identify the shared Screen owner.
No protocol support classification or runtime behavior was expanded.

This is an intentional contraction of the ownership graph, not a general
new terminal-operation abstraction. Keep subsequent debt payoffs narrow,
source-owned, and justified by a demonstrated duplication or defect.

## Screen owns horizontal-index shift geometry (20 November 2026)

DECFI/DECBI exposed the same authority split as CSI IL/DL. Screen chose
whether to move the cursor or shift the row, using the physical row edges
when the cursor was outside DECSLRM. Terminal separately compared the cursor
to the configured margins and sometimes failed to shift image placements
when Screen had shifted cells.

The distinct Screen.forwardIndex/backIndex paths are now one
Screen.indexHorizontal(direction) operation. Its result includes the exact
shifted column interval, or no shift for cursor-only movement. Terminal
consumes that interval directly for graphics without recomputing boundaries.
A red-before/green-after terminal test established the physical-edge image
mismatch in both directions; owner tests additionally prove inside-margin,
outside-margin, and cursor-only results. VT Debug/ReleaseFast, complete root
ReleaseFast check/test/audit, protocol validation, format and diff checks are
green. Two protocol source links follow the new owner. No new protocol was
admitted, and no implementation or GPU backend was installed or launched.

As with the line-edit consolidation, the typed result is a semantic fact
from the owner, not a second terminal model. Avoid general-purpose wrappers
until a proven divergence warrants one.

## LF graphics follow committed Screen history, not a second eligibility rule (20 November 2026)

Terminal's former `fullScreenHistoryScroll` predicate recognized only a
whole-screen primary scroll as history-backed. Screen can also retain a top-
anchored partial-height region in history. That mismatch shifted image
anchors within the wrong absolute interval and left fixed rows below the
region out of alignment with their text.

LF/NEL, SIXEL cursor advancement and Kitty graphics cursor advancement now
inspect the actual Screen history-origin transition after each committed row
move. If the origin advanced, placements inside the scrolling top region
retain their absolute identities and only fixed rows below it translate.
Without origin motion, visible placements scroll with their cells. The
separate full-screen-history eligibility predicate was deleted; the sized-
text path also uses the committed origin change instead of repeating Screen's
margin and history-capacity policy.

A terminal-stream test failed on the old partial-top LF mapping and passes
after the correction. It covers LF and NEL for two successive rows: first
moving a scrolling image to row zero, then into projected history, while a
fixed-row image stays on its physical row throughout. VT Debug/ReleaseFast,
the root ReleaseFast check/test and audit graph, protocol validation,
formatting and diff checks passed. No support label, binary or running app
changed. The approved Screen state transition is the single authority; the
terminal's graphics adjustment follows the resulting identity rather than
predicting policy independently.

## CSI row-wide column shifts follow Screen's admitted geometry (20 November 2026)

A focused ownership review kept the CSI SU history/retry path intact: Screen
reserves history before mutation, and Terminal's service-boundary loop must
retain exact partially completed rows and OOM continuation. Existing red/
green allocator-pressure tests prove this split is a necessary transaction
boundary, not an arbitrary duplicate policy.

The adjacent CSI SP @ (shift-left) and CSI SP A (shift-right) handlers had a
confirmed text/graphics disagreement. Screen shifted active-region cells,
while Terminal applied no corresponding image-plane motion. A newly written
terminal-stream test failed before the change and passed after it.

Screen now owns one `shiftColumns(direction,count)` operation and returns
the exact admitted row/column rectangle and clamped count, distinct from
pending-wrap-only mutation. Terminal consumes that fact, without rederiving
margins, and asks the graphics plane to shift all affected rows in one pass.
The prior left/right Screen wrappers were retired. A multi-column image
crossing the edited horizontal boundary loses its placement, not its decoded
content, because translating it whole would mutate unshifted columns.
Tests prove right/left movement, fixed rows, admitted horizontal extent,
zero-count wrap-only semantics, large-count clamping and boundary clipping.
The graphics code scans retained placements once per command rather than
once per row, preserving the low-cost presentation path.

VT Debug and ReleaseFast, the full root ReleaseFast check/test/audit graph,
protocol validation, formatting and diff checks passed. No catalogue status
promotion, installed binary, application process or GUI session change.

## ECH graphics erasure follows Screen's logical row width (20 November 2026)

Terminal previously reconstructed the graphics range for CSI ECH using the
physical grid width even though Screen erases only through the current row's
logical width. With DEC double-width line geometry, a bounded ECH could erase
image placements at columns that Screen did not touch. The terminal-stream
regression was red before the correction and passed afterward.

Screen.eraseChars now returns its exact accepted logical-row interval and the
independent changed fact; Terminal consumes the interval for graphics erasure
rather than redoing bounds arithmetic. A 999-count ECH on a double-width row
retains a placement outside the logical erasure, removes the one inside, and
preserves decoded image data. Owner tests prove normal and default-count
range coordinates. VT Debug/ReleaseFast, full root ReleaseFast check/test,
Zig/project audit, protocol validator, formatting and diff gates passed.
There is no new permission or graphics backend; no support rating was changed.

## EL graphics erasure follows Screen's logical row range (20 November 2026)

Screen.eraseLine clipped CSI 0/1/2 K text erasure to the current row's
logical DEC line width. Terminal separately constructed a graphics erase
interval using the physical grid width, causing graphics outside a
DEC double-width row's logical region to be removed even though Screen
left the corresponding cells untouched. A terminal-stream test was red
before the change and green afterward.

Screen now returns the same narrowly typed `EraseResult` used by ECH,
with a changed fact and an optional accepted inclusive logical range.
Terminal consumes that range for ordinary EL, and its old independent
`eraseLineColumns` predicate is deleted. Selective DEC EL retains its
existing text/protection and graphics policy, with no speculative change.
Tests cover 0K/1K/2K on DEC double-width rows, retained in-range/out-of-
range image placements, decoded-image lifetime and exact Screen ranges
including repeated erase on already-blank text. The full VT Debug/
ReleaseFast suite, root ReleaseFast check/test, project/zig-audit, protocol
validation, formatting and diff checks passed. No support statuses,
installed binary or running session changed. Selective erase and other
screen-region graphics coupling remain separate unproven review candidates.

## ED 0 cursor-row image erasure uses Screen's logical line edge (20 November 2026)

The preceding EL/ECH audit identified the same physical/logical width split
on the current row of CSI ED 0. Screen.eraseDisplay(.cursor_to_end) clips
its cursor-row text mutation at that row's DEC logical width, but Terminal
formerly erased image placements through the full physical width. The
second and later rows are fully erased and retain their separate full-row
graphics action.

A terminal-stream test on a DEC double-width cursor row failed before the
fix and passed afterward: the image within the logical erase disappears,
the placement outside it remains, all lower-row graphics are removed, and
decoded image data is retained. Terminal now uses Screen.lineRightBoundary
for the current row instead of calculating a physical-grid endpoint. No new
result type or abstract erasure layer was required. VT Debug and ReleaseFast,
root ReleaseFast check/test plus Zig/project audit, protocol validation,
formatting and diff checks passed. No catalogue classification, installed
binary or live app changed. Selective and rectangular image erasures remain
independent, unqualified reference-policy questions.

## Rectangle graphics follow Screen's resolved DEC origin/margins (20 November 2026)

For CSI DECERA/DECSERA, Screen.rectBounds already owns both DEC origin-mode
resolution and vertical/horizontal margin clipping. Terminal's graphics helper
reconstructed the rectangle directly from raw CSI-relative parameters using
physical rows and columns. Consequently Screen erased the correct origin-
relative text cell while the corresponding image placement remained, and
an unrelated image at the physical origin could be removed.

Terminal now consumes the exact existing Screen.rectBounds result for
rectangular graphics erasure, rather than maintaining a second rectangle
resolver. A terminal-stream test places one image at the physical origin
and another at the later margin-relative rectangle origin, then exercises
both ordinary and selective rectangular CSI erasure, an inverted rejected
rectangle, and fragmented input. Original graphics-coordinate code failed
the corrected test; the new code passed it. The out-of-range image stays
visible; erased placement data is retired while decoded images remain owned.

VT Debug and ReleaseFast, full root ReleaseFast check/test, Zig/project
audit, protocol validation, formatting and diff checks passed. No source
or image policy was expanded to claim full iTerm2 DECERA/DECSERA parity:
protected-cell/attribute differences, external image lifetimes and host
selection consequences remain separate pinned-reference questions. No
catalogue status changed, binary installed, or running session modified.

## Kitty private erasure is not identical to DEC-protected selective erasure (20 November 2026)

Reinspection of pinned Kitty d4106ef2db687579a69fefc949a6dc1b662f3ca8
shows `screen_erase_in_line` and `screen_erase_in_display` use their
private flag to clear text while preserving formatting. In
`kitty/line.c:line_clear_text` the CPU cells are replaced without
modifying the GPU formatting array; there is no DEC-protected-cell
admission check in this private path. The same commands call
`screen_dirty_line_graphics` only for lines with image placeholders.
`grman_remove_cell_images` removes nonvirtual *cell-image* references
in those rows, not every noncell/virtual graphics placement. Pinned Kitty
graphics tests explicitly prove placeholder-image disappearance after
ordinary erasure.

Howl's CSI ? K/J intentionally implements DEC selective semantics:
DEC-protected text survives, and its canonical Unicode placeholder
projection follows text mutation. Direct physical Kitty placements are
not erased by Howl's selective EL, while its selective ED applies physical
placement erasure. Treating all Kitty private erasures as generic
`graphics.erase` operations would conflate these distinct ownership
and protection models, potentially deleting unrelated image placements.

The Kitty DECSEL and DECSED catalogue residuals now document the exact
remaining comparison rather than claiming an unqualified lack of graphics
support. Both remain partial/deferred, pending a bounded independent test
of protected text, attributes, placeholder-image lifetime, stored-image
lifetime and selection policy against this pinned reference. No new
feature, security privilege, status promotion or GUI behavior was accepted.
The full root ReleaseFast check/test/audit and protocol gates passed.

## Partial DEC selective ED preserves independent physical graphics (20 November 2026)

Pinned Kitty d4106ef2... distinguishes line-placeholder cell-image references
from independent physical image placements. Its private CSI ? 0/1 J paths
clear text with retained formatting and clean up only cell-image references
on placeholder-bearing lines, whereas CSI ? 2 J invokes the graphics
manager's full visible-image clear. Howl's DEC selective owner instead
preserves DEC-protected cells, with virtual Kitty image projection derived
from the canonical placeholder cells. The independent physical placements
should not be unconditionally deleted by *partial* selective ED.

Terminal no longer erases physical image placements for selective
cursor-to-end and start-to-cursor display erasure. Screen remains sole
owner of DEC protection and text admission, and erasing unprotected
placeholders automatically removes their projected graphics. Full-display
selective erase retains its existing full physical placement removal.
No new second graphics model or broad cell-image deletion path was added.

A terminal test was red with the prior partial selective physical erase and
is green after the change. It covers ?0J, ?1J and ?2J separately with one
virtual prototype, a live placeholder projection, an unrelated physical
placement and unchanged decoded image allocations. Another test checks that
protected placeholder text/image survives while an unprotected placeholder
is erased, retaining image data. The first selective EL test independently
proves the same protection-vs-physical-lifetime distinction.
VT Debug/ReleaseFast, full root ReleaseFast check/test/audit, protocol
validation, format and diff gates passed.

The Kitty DECSED record remains partial/deferred: pinned Kitty's private
text erasure preserves formatting rather than Howl's DEC protection, and
reference cell-image/selection lifetimes require further qualification.
No installed app or running session was changed.

## Automatic selection invalidation is not a user error (20 November 2026)

A dedicated private KWin visual acceptance run exercised the prior CSI IL
selection-generation implementation with Howl 0.1.9-dev. A pointer drag
created a visible highlighted selection; a FIFO-controlled PTY producer
then emitted CSI L without additional user input. The selection correctly
cleared, but the app also surfaced the normal internal invalidation as a
bottom-of-window "SelectionContextChanged" error notice.

The direct app worker now clears its selection and requests redraw
*silently* when the canonical VT structural-edit generation changes.
Explicitly rejected stale user selection/extension requests still use
the existing error path. The previously accepted app unit test was updated
to assert the no-error result and failed before the code change; the changed
code passed in app Debug and ReleaseFast plus full root ReleaseFast tests,
audit, protocol validation and format/diff checks.

A fresh, temporary debug app build ran in a separate Fleet-owned private KWin
seat at 1280x800 scale 1. WMIO created the same drag selection and a
FIFO-triggered CSI L then cleared it, with no bottom notice. A second
turn-based case changed only a different text row; the screenshot's selected
row band was pixel-identical before and after that ordinary output. A
separate image scene tested selective ED with a colored physical placement
and a virtual Unicode-placeholder projection: after CSI ? 0 J, the
placeholder image vanished and the independent physical image remained.
These were actual private compositor/pixel observations, not just tests
rendered or inferred from canonical VT. Captures and temporary binaries
belong to the test workload and do not enter the repository.

No physical graphical environment, installed Howl executable, production
configuration or unrelated process was touched. Semantic protocol support
ratings remain separate from this UX and graphics acceptance.

## Selected text observes canonical row mutation, not an app damage journal (20 November 2026)

Pinned Kitty's screen_erase_in_line clears selections intersecting the
erased row. Howl's earlier selection reconciliation only checked bank,
geometry, retention and admitted CSI IL/DL; actual EL/ED rewrites could
leave the old highlighted range pointing to newly erased content. A
direct-app state test failed before this correction: writing/erasing an
unselected row preserved a word selection, but erasing the selected row
did not invalidate it.

VT already assigns monotonic, retained-history-preserving row generations.
Observation now exposes only the next row-generation watermark, not a
second log or UI policy. When a manual/search selection is accepted, its
app owner captures that watermark. On later VT changes, the app checks
the selected *absolute* row range against existing canonical row
generations; it invalidates silently when any selected row was rewritten,
without clearing on unrelated output or viewport/history movement.
Selected rows that are rewritten and archived in the same feed remain
detectable, and eviction remains independently invalidating. Repeated
pointer updates skip scans when VT's row-generation watermark is
unchanged. Existing CSI IL/DL admission identity remains the separate
guard for structural edits that can be admitted without a cell rewrite.

Screen row generations are authoritative. VT has no mutable selected
range, highlight or app damage journal. New direct-app and selection
tests prove unaffected writes/erases, same-row erasure, multirow middle
edits, archive admission, eviction, and rewrite-then-archive. The
pinned Kitty no-op erasure and selection policy may differ when no
cell identity changes, so this does not establish full Kitty DECSEL/
DECSED parity. Neither graphics backends nor PTY mechanics changed.

## Private CSI ? K/J is an irreconcilable pinned reference policy difference

Frozen Kitty kitty/screen.c:screen_erase_in_line and
kitty/line.c:line_clear_text implement the private flag as *clear
CPU text while preserving GPU formatting*. They do not test a DEC
protected-cell flag. Frozen libvterm
src/screen.c:erase_internal skips DEC-protected cells during
selective erasure and resets the erased cells' attributes to current
foreground/background without preserving bold/reverse. Pinned iTerm2
VT100ScreenMutableState.m:selectiveEraseRange similarly skips guarded
cells when protection is active and uses eraseAttributes:YES for
DECSEL/DECSED. One fixed interpretation of identical CSI ? K/J
input cannot simultaneously preserve the protected glyph and erase it,
or both preserve and reset its formatting.

Howl retains DEC protection as its current canonical contract. A new VT
test explicitly proves guarded text survives CSI ? 2 K, while an
unguarded bold red glyph is erased and takes reset noncolor attributes.
Matching Kitty instead would require a separately selected compatibility
mode with a deliberate contract and test matrix. No automatic TERM
guessing, hidden fallback, mode switch, or unsupported full status was
accepted. Reconsider only if product requirements justify that scope.

## DECRQM reports existing iTerm2 capability and mouse-format state (20 November 2026)

Immutable iTerm2 VT100Terminal.m at
1d6e758a390f7141f6e21b06e2663a53a02409c6 reports DEC private 1048
as 1 (supported) even though save/restore is a one-shot cursor action, not
a boolean mode state. Its DEC private DECRQM 10016 asks for
MOUSE_FORMAT_SGR_PIXEL, although its mode setter uses 1016. Howl already
owns both actual capabilities: 1048 saves/restores the cursor and 1016
selects SGR-pixel mouse reporting. Pure mode_report.decState now reports
1048 as 1 and answers 10016 from the existing 1016 state, with neither
new storage nor an invented 10016 setter. Terminal and mode-owner tests
were red before this change and green after. They cover supported and
reset states, unknown 9999, C1 framing, negative 10016 setter, and actual
1016 toggling.

The fixed-reference differences are now explicit. iTerm2 returns 4
(permanently reset) for unknown ANSI/DEC mode identities, while pinned
Kitty report_mode_status and libvterm request_dec_mode use 0 (unknown).
Pinned Kitty/libvterm also do not recognize query 1048 or the iTerm2
10016 alias, so one universal reply table cannot exactly match all three
on those bytes. These four DECRQM reference records remain partial,
without score inflation. Their catalogue semantic owner citations now
reference mode_report.decState/ansiState instead of the appendDec/appendAnsi
framing-only functions. No new host policy, mutable mode or GUI behavior
was introduced.

Accepted gates: affected VT Debug/ReleaseFast, full root ReleaseFast
check/test graph, project and Zig audits, declaration-aware protocol
validation, formatting and diff checks. No installed binary or active
session changed.

## DSR origin and status replies have incompatible pinned reference policies (20 November 2026)

Reading frozen Kitty screen.c:report_device_status, libvterm
state.c:on_csi and iTerm2 VT100Terminal.m:
handleDeviceStatusReportWithToken reveals three incompatible policies
for the same CSI 6n and private CSI ? 6n sequences under DECOM.

Libvterm always reports absolute cursor row and column. Kitty reports the
row relative to its vertical top margin, but retains absolute column.
iTerm2 queries both relative X and Y under origin mode, subject to its
terminalShouldSendReport host gate. Howl chooses origin-relative row
and column for the normal case and uses saturating coordinates if a
saved cursor predates changed margins; iTerm2 instead subtracts its
relative coordinates. Kitty reports private status 5 without a '?'
prefix while libvterm prefixes that private status. Howl follows the
unprefixed form, along with its separate DEC locator and color queries.

The existing 'device and status queries retain exact scalar transcripts
and origin coordinates' tests prove Howl's selected behavior, malformed
controls and reply framing, including the restored-cursor corner.
There is no one-profile reply that simultaneously matches all three
frozen implementations. Four DSR catalogue records now give this
specific distinction rather than invoking the inherited broad
exclusion wording. Their support/disposition/source/proof fields remain
unchanged; full parity requires a deliberately selected compatibility
contract, not automatic runtime inference or a new mirrored cursor.
Full root ReleaseFast check/test, audit, protocol validation and diff
gates passed without modifying terminal behavior.

## XTGETTCAP reports five more pinned Kitty capabilities from existing VT owners (20 November 2026)

Pinned Kitty revision d4106ef2db687579a69fefc949a6dc1b662f3ca8
delegates DCS +q through screen_request_capabilities to its Python
get_capabilities resolver in kitty/terminfo.py. The source advertises
the boolean capabilities am (automatic right margin), ccc (changeable
palette), and XF (focus events), plus the string capabilities BE
(ESC[?2004h) and BD (ESC[?2004l), with lowercase-hex string values.
A read-only Python oracle executed the exact pinned terminfo.py code
against inert stand-ins for Kitty's imported runtime modules, verifying
five successes and one unknown name. It did not start Kitty or query
the OS, TERM, GPU, input devices or current user profile.

Howl already owned every advertised behavior: Screen auto-wrap,
OSC 4 palette mutation, DEC 1004 focus reporting, and DEC 2004
bracketed paste. Its XTGETTCAP termcapValue table previously returned
0+r for those names. The table now answers the three booleans with
1+r, and BE/BD with the exact fixed control bytes encoded as lowercase
hex, without new mutable mode state, terminfo database or host-specific
identity. The terminal-stream test failed before this correction and
passed afterward. It verifies ordered mixed known/unknown responses,
fragmented DCS, 8-bit C1 serialization, exact echoed hex spelling,
queries remaining capability descriptions after changing DEC modes,
and the underlying independent 7/1004/2004 state. The existing
checkAllAllocationFailures probe now includes BE/BD/XF and proves
transactional rollback of the entire ordered result on error.

The pinned iTerm2 VT100Terminal.m instead resolves XTGETTCAP through
a chosen xterm/screen terminfo profile, asynchronous host key mapping
and application name/profile callbacks. These are not owned by VT.
The Kitty and iTerm2 reference-specific records therefore remain
partial with exact remaining obligations, not inflated as full.
Unknown TERM, arbitrary key strings, OS names, window capabilities,
and unsupported capability names still answer 0+r. This is fixed
capability reporting, not a new terminfo engine or a caller policy.

VT Debug/ReleaseFast, root ReleaseFast check/test, complete Zig and
project audit, declaration-aware protocol validation, Zig formatting
and diff gates passed. No installed binary or running process changed.

## Rejected Kitty application escape mode is a complete protocol no-op (20 November 2026)

Frozen Kitty d4106ef2db687579a69fefc949a6dc1b662f3ca8 at
kitty/screen.c:set_mode_from_const has a dedicated private DEC 7727 case.
Both setting and resetting it only emit an internal log_error saying that
application escape mode is unsupported, then break. They do not mutate
terminal modes, cursor, pending wrap, cells or child-directed output.
Logging is a product diagnostic, not a terminal-protocol consequence.

Howl already rejected the same raw CSI ? 7727 h/l through its bounded
unknown-mode path. The new terminal-level test proves 7-bit and 8-bit
CSI, split input, unchanged canonical semantic/content identities,
pending-wrap preservation, zero replies and caller consequences,
querying the unsupported mode as unknown, and successful subsequent
wrapped text. No runtime code or new mode state was necessary.

Exactly one reviewed reference record, kitty.mode.application_escape,
was promoted from partial/excluded to full with a named proof. Counts
change from 291 full / 323 partial to 292 full / 322 partial; 48
missing and 10 unassessed remain. This is classification accuracy for
existing implementation, not an added feature. VT Debug/ReleaseFast,
complete root ReleaseFast check/test and audit graph, protocol
validation, formatting and diff checks passed.

DECSACE was separately examined but not changed: frozen Kitty
screen_decsace treats all parameters other than 2 as stream extent,
while pinned iTerm2 executeDECSACE ignores parameters outside 0/1/2.
Howl currently matches the already-full iTerm2 record. Changing the
default to claim Kitty full would violate existing verified coverage.
A compatibility-profile policy is not authorized for this difference.

## iTerm2 MoreFix preserves phantom pending wrap across mode assignments (20 November 2026)

Frozen iTerm2 1d6e758a390f7141f6e21b06e2663a53a02409c6
defines moreFix in VT100Terminal.m. executeDecSetReset case 41 calls
setMoreFix, which sets a boolean and marks the UI dirty even if the
value is unchanged. It does not reposition the cursor or consume the
phantom right-edge state. In VT100ScreenMutableState.m,
appendTabAtCursor checks moreFix, cursorX > width and wraparound
to perform linefeed and carriage return before the tab. The live
query returns 1/2, saved state and resets follow the same mode.

Howl already owned the MoreFix flag, query, parameterized mode
save/restore, DECSTR, RIS, alternate-screen lifetime and HT behavior,
but Terminal.setDecMode shared cleanup canceled pending wrap on any
recognized assignment, including 41. That wrongly prevented the
following HT from entering the next line and caused disabling MoreFix
to overwrite the rightmost cell instead of wrapping the next byte.

A red-before/green-after terminal test now proves enabling MoreFix
while phantom wrap is pending, disabling it in that state, idempotent
repeat enable, the exact subsequent HT or printable effect, preserved
content identities on no-op repeats, and normal cursor/grid behavior.
The existing comprehensive MoreFix test proves query replies,
save/restore, soft/hard reset and primary/alternate lifetime. Only
DEC mode 41 returns the Boolean state mutation without the shared
pending-wrap cancellation; other modes retain existing cleanup.
No new mode or mutable owner was introduced.

The pinned iTerm2 extra dirty flag on repeated assignments is UI
presentation bookkeeping, not a terminal-protocol effect; a no-op
mode assignment properly reports no semantic VT mutation in Howl.
The scoped reference record iterm2.mode.more_fix is now full instead
of partial/excluded, supported by the new exact-state proof.

After the separately committed Kitty 7727 no-op promotion, the
reviewed census is now 293 full / 321 partial / 48 missing / 10
unassessed (672 reference-specific records unchanged). This checkpoint
is a real behavior fix and a full promotion. VT Debug/ReleaseFast,
root ReleaseFast check/test/audit, protocol validator, formatting and
diff checks all green. No installed binary, host permission or running
application was modified.

## Re-audit Kitty tab controls: exact DECST8C admission, four historical full overclaims (20 November 2026)

A bounded re-audit compared the pinned Kitty revision
d4106ef2db687579a69fefc949a6dc1b662f3ca8 at
kitty/screen.c, kitty/vt-parser.c and kitty_tests/screen.py to Howl's
Screen/tab_stops and terminal-stream evidence. Kitty explicitly retains
independent main_tabstops and alt_tabstops, including resize prefix
preservation. Howl's Screen-local stop ownership is therefore correct
for Kitty; do not relocate tab stops to a terminal-global list merely
because libvterm retains one shared table.

One actual parser defect was fixed: Kitty admits DECST8C only for
CSI ? 5 W with exactly one parameter. Howl's decodePrivateCsi
previously checked only the first parameter and admitted CSI ? 5;1 W,
wrongly clearing a custom stop. Two tests were red before the change
and green afterward, one for actual active-alt tab state and one for
parser rejection. A one-condition decoder correction now rejects
extra parameters while preserving the standard 8-column reset.

The new end-to-end tests also prove:
- independent primary and alternate custom stops under CSI 1049,
  resetting defaults on *only* the active bank, and resize growth
  preserving old custom stops and adding new 8-column defaults;
- CBT with zero, two, saturated large counts, C1 CSI, edge clamping
  and bank-specific stop traversal;
- CSI 5 g clears all in Howl (and frozen libvterm), while pinned
  Kitty supports only 0/current, 3/all, 2/no-op and diagnoses 5;
- on a blank row, Kitty screen_tab stores a special source tab marker
  that is visible in the pinned screen.py line string and copy path,
  while Howl's C0 HT and CSI CHT only move the cursor;
- Kitty HTS at a phantom cursor beyond the right edge is ignored,
  but Howl's separate wrap_pending representation allows a stop at
  the last physical column, revealed by a subsequent grid growth.

Two Kitty records were fully re-audited with exact strengthened tests:
kitty.csi.reset_tabs and kitty.csi.cbt remain full, with new direct
proof citations. Four old full records had been overclaimed and are
now partial/excluded with specific source-backed residuals:
kitty.c0.ht and kitty.csi.cht (special retained tab marker),
kitty.esc.hts (phantom-edge stop admission), and kitty.csi.tbc
(unsupported mode 5 conflicting with libvterm). This changes the
catalogue from 293 full / 321 partial to 289 full / 325 partial
without minting or dropping IDs. It is an *audit correction*, not four
new regressions. Both pinned Kitty and libvterm are intentionally
retained as reference-specific truth; changing CSI 5 g to please
Kitty would damage already-supported libvterm behavior.

No new tab or image model, generic compatibility profile, running
application, installed binary or compositor change. VT Debug/
ReleaseFast, root ReleaseFast check/test and complete Zig/project
audits, declaration-aware protocol validation and inventory fixtures,
formatting and diff checks passed. Remaining libvterm/iTerm2 tab
bank-lifetime differences deserve their own re-audit before any
broader source or catalogue change.
