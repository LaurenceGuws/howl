# Howl VT Offender Index

Re-audited from `d34ad6f` on 2026-07-18. Scores measure executable ownership,
failure, bounds, invariants, and proof. Comments and file size earn no points
by themselves.

## Current score

| Bar | Score | Blocking evidence |
| --- | ---: | --- |
| Foot directness | 10/10 | Current control flow keeps protocol classification and execution direct; no concrete indirection defect is indexed. |
| TigerBeetle defensiveness | 10/10 | Typed host operations, exact failures, allocation ownership, bounds, and post-failure reuse now have executable proof at the native boundary. |
| Character/capability density | 10/10 | The root exports one direct native `Terminal` owner without compatibility layers or additional ownership machinery. |
| Ownership/cleanup | 10/10 | Resize and runtime history replacement are transactional; every generated input, copy, and drain owner is released or transferred exactly once. |
| Exact failures | 10/10 | Parser, stream, OSC, input, retained consequences, logical snapshots, reflow, and resize storage expose their complete current failure vocabularies. |
| Documentation | 10/10 | The source audit covers every source owner and retained public declaration and guards the one-symbol embedding root. |
| Hostile-input evidence | 10/10 | Structured native histories cover hostile bytes and every current typed host operation, including rejected limits, failed allocation, drains, acknowledgement, and reuse. |
| Embedding surface | 10/10 | `src/howl_vt.zig` exports one directly owned native `Terminal`; current root-only integration proof exercises the accepted embedding shape. |
| Deliberate modification | 9/10 | Unit, simulation, fuzz, coverage data, and narrow source audits exist; whether each narrowing conversion has sufficient local proof remains a semantic review responsibility. |
| Source maturity | 10/10 | Protocol breadth, deterministic parsing, transactional history, allocation-free rectangle copy, and the complete current native host surface are proved. |

## Ordered offenders

### Kitty family remaining audit — 2026-07-19

The current safe terminal-owned family consists of the bounded progressive
keyboard stack and encoding, OSC 21 represented color control, and the
16-entry complete-color stack. Keyboard flags are separate for main and
alternate screens; requests are masked to the five implemented enhancement
bits, queries report that accepted state, and host key commands retain
press/repeat/release, shifted identity, and bounded committed text through VT
encoding. Color mutations operate only on Howl's represented palette,
foreground, background, and cursor colors.

Premature retained notification, file-transfer, text-size, pointer-shape,
clipboard-mode, and multiple-cursor state was deleted. Their parsed bounded
payloads have no semantic effect because each requires absent storage,
rendering, security, or host UX authority. Kitty graphics/images, clipboard,
selection, paste policy, notifications/attention, file transfer/storage, and
current-directory/trust metadata remain quarantined for the same reason.

The Wayland host cannot currently derive Kitty's PC-101 base-layout alternate
from the compositor-provided keymap, so it publishes only the exact unshifted
identity and current-layout shifted identity it owns. A bounded 16-key host
lifecycle retains accepted press identity and terminal target across focus and
keymap changes; repeat and release return to that owner, focus loss emits
releases, duplicate presses and unknown releases are ignored, and failed
admission retains no lifecycle. Current topology has three stable terminal
owners, so terminal removal cannot occur before window shutdown releases all
accepted keys. Neither limitation justifies guessed protocol data.

### iTerm family remaining audit — 2026-07-19

No additional safe capability is known after OSC 133 shell marks; OSC 50/1337
cursor shape; OSC 1337 cell-size report, typed shell identity, and represented
color controls. Shell identity accepts a decimal `u32` version and one optional
32-byte `shell` value; malformed, duplicate, and unknown suffix keys reject the
whole update. SetColors follows iTerm's per-pair loop: supported valid pairs
commit independently, malformed or unsupported pairs are ignored, and
`default` restores Howl's corresponding native default. ReportCellSize accepts
the bare key or an ignored value and replies height, width, and the host's
current exact scale of one. The remaining commands cross product-authority
boundaries:

- clipboard, selection, paste, file transfer, captured output, and images own
  external bytes or storage;
- CurrentDir, RemoteHost, profile, environment, and user variables establish
  trust and workspace policy;
- notifications, attention, badges, SetMark scroll positions, focus stealing, annotations, key
  labels, and tab color require host UX policy or chrome;
- ClearScrollback requires the quarantined history/viewport contract;
- UnicodeVersion changes text-width policy; SetColors keys for Display-P3,
  faces, links, selections, matches, tabs, badges, and presets have no honest
  representation in the frozen native surface.

These are authority blockers or intentionally absent domains, not parser
offenders. Kitty-family work must not infer their contracts.

### VT-022 — Stale surface acknowledgement reports success

- Status: resolved
- Path/symbol: `src/terminal.zig:Terminal.ackSurface`;
  `src/publication.zig:Publication.canAck`
- Defect: every nonzero snapshot identity returned `true`, including stale
  identities rejected by `Publication.canAck`. Dirty state remained retained,
  so the return value contradicted the operation result.
- Bars: defensiveness, embedding surface, hostile-input evidence
- Resolution: `ackSurface` now returns `false` unless publication identity and
  current dirty generation both match. Native embedding proof mutates after a
  publication, rejects its stale identity without clearing dirty state, then
  accepts the current identity and observes clean state.

### VT-016 — Locator input turns operating failures into panics

- Status: resolved
- Path/symbol: `src/locator.zig:handleMouseEvent`;
  `src/terminal.zig:Terminal.encodeInput`, `encodeMouseInput`
- Defect: locator reports append to bounded heap-backed host output, but both
  `OutOfMemory` and `ConsequenceLimit` are caught as `unreachable`.
  `Terminal.encodeInput` consequently advertises only paste failures.
- Bars: defensiveness, exact failures, hostile-input evidence, maturity
- Shape: propagate the existing exact host consequence errors through mouse
  input and combine them with paste errors at the terminal boundary.
- Proof: allocation failure and output-capacity rejection return exact errors,
  preserve pending output, leave locator state reusable, and never panic.
- Depends on: nothing
- Resolution: `handleMouseEvent` returns `host_state.ApplyError` and mutates
  one-shot/filter latches only after report publication succeeds.
  `Terminal.InputError` combines exact paste and retained-consequence errors.
  Direct tests induce locator allocation failure and a full 64 KiB output
  queue, verify unchanged output, then prove successful reuse and one-shot
  consumption.

### VT-017 — Screen runtime mutation silently loses allocation failures

- Status: resolved
- Path/symbol: `src/screen.zig:storeHistoryRow`, `copyRect`
- Defect: history retention may partially extend an open logical line before
  projection allocation fails; rectangular copy silently ignores temporary
  allocation failure. Callers cannot distinguish applied, rejected, and
  partially retained mutations.
- Bars: defensiveness, ownership, exact failures, hostile-input evidence
- Shape: make each mutation transactional or propagate its exact operating
  failure through semantic routing and `Terminal.feed`.
- Proof: exhaustive allocation failure leaves screen authority and projection
  paired, then accepts a succeeding mutation.
- Depends on: VT-016 establishes operating-error propagation at another
  terminal boundary
- Resolution: `storeHistoryRow` builds the next logical line and reserves
  projection and authority capacity before committing either representation.
  Allocation failure drops only the departing visible row; retained logical
  authority and projected rows remain paired and the next scroll can succeed.
  Full history releases one oldest logical owner and replaces its ring slot in
  constant time. `copyRect` uses overlap-aware row and column direction and
  performs no allocation. Terminal-level failure
  injection covers every allocation while starting and extending logical
  history, then proves successful reuse; Screen tests cover both rectangle
  overlap directions with the allocator set to fail.

### VT-019 — Allocation owners expose inferred failure sets

- Status: resolved
- Path/symbol: `src/parser.zig:Parser.init`;
  `src/stream_terminal.zig:DcsCapture.start`, `put`,
  `TerminalStreamState.initAlloc`; `src/osc.zig:decodeClipboardSet`;
  `src/screen/resize.zig:reflowLogicalLines`, `allocResizeBuffers`;
  `src/screen.zig:collectLogicalSnapshot`
- Defect: these allocation and decode boundaries inferred their error sets, so
  callers could not review their complete failure vocabularies and
  implementation changes could widen them silently.
- Bars: defensiveness, exact failures, deliberate modification
- Shape: give each owner the smallest exact error set supported by its current
  operations, preserving direct propagation through existing callers.
- Proof: compile-time assignments pin each public boundary to its declared
  errors and direct tests exercise each reachable failure.
- Depends on: VT-017 for the screen mutation chain
- Progress: `Parser.init` and `TerminalStreamState.initAlloc` now expose only
  `OutOfMemory`. DCS capture distinguishes initialization allocation from
  payload allocation or `StringControlLimit`. OSC 52 allocation distinguishes
  malformed payload syntax, unsupported query input, invalid padding, invalid
  alphabet bytes, and `OutOfMemory`; caller-buffer decode additionally owns
  `ShortBuffer`. Direct tests exercise each reachable error, reset/reuse after
  DCS failures, and constructor cleanup without compatibility errors.
- Resolution: logical snapshot, reflow, replacement-buffer, and directly
  coupled resize helpers now use `std.mem.Allocator.Error` as the single exact
  allocation vocabulary. Typed function assignments pin the three owner
  boundaries. Focused exhaustive failure injection releases partial owners,
  preserves source state, and completes a subsequent snapshot, reflow, or
  buffer allocation. Existing Screen and Terminal sweeps continue proving
  transactional resize and post-failure usability.

### VT-020 — Native hostile proof omits typed host operations

- Status: resolved
- Path/symbol: `test/fuzz_terminal.zig:fuzzTerminal`
- Defect: the current operation model generates feed, resize, reset, and
  inspect only. Keyboard, mouse, focus, paste, selection, drain, acknowledge
  rejection, and allocator-failure transitions are absent.
- Bars: defensiveness, hostile-input evidence, deliberate modification
- Shape: extend the bounded native operation vocabulary only as each public
  owner gains exact invariants and failure semantics.
- Proof: generated typed operations assert bounds, ownership, post-error reuse,
  and deinitialization through the curated root.
- Depends on: VT-016; screen allocation transitions depend on VT-017
- Resolution: the native Smith history now generates bounded committed bytes,
  named and Unicode keyboard input, mouse, focus, paste, selection, output
  drain, clipboard drain, and acknowledgement operations alongside terminal
  feed, resize, reset, viewport, and inspection.
  Input results are always deinitialized and checked against fixed scratch or
  paste bounds. Selection copy and both consequence drains fail a caller
  allocation first, preserve their terminal owner, then succeed and prove
  consumption. Zero acknowledgement is rejected before a valid publication is
  retired, and every operation is followed by complete surface traversal and
  publication acknowledgement. Generated mouse rows exposed an unchecked
  narrowing conversion in DEC locator retention; locator input now rejects
  rows outside its explicit `u16` coordinate domain and remains reusable at
  the inclusive upper bound.

### VT-021 — Source safety properties remain manually audited

- Status: resolved
- Path/symbol: `tools/audit_source.sh`; repository-wide
- Defect: the executable audit protects owner contracts and public
  declarations only. Inferred error unions, discarded fallible results,
  `anytype`, and assertion gaps can enter silently.
- Bars: defensiveness, exact failures, deliberate modification, maturity
- Shape: add narrow executable checks only after each forbidden pattern has a
  proven exception model; avoid brittle text policy pretending to prove
  semantics.
- Proof: each gate rejects one intentionally introduced violation and accepts
  every documented exception.
- Depends on: VT-017, VT-019, and VT-020 establish the accepted patterns
- Resolution: the source audit now rejects inferred public error returns,
  empty `deinit`/`reset`/`clear` hooks, and discarded source results outside
  compile-only root and parser test probes. It continues enforcing source-file
  and public-declaration contracts. The audit exposed exact allocator returns
  missing from dirty-column and tab-stop allocation, two discarded stream
  summaries, an unnecessary mouse parameter, and a parse result used only to
  satisfy the compiler; each was corrected at its owner. Stream adapters now
  assert the real invariant that title mutation implies terminal mutation.
  Narrowing safety and assertion sufficiency remain judgment-based because
  proximity regexes cannot prove the value range; they are intentionally not
  represented as automated coverage.

## Hardening loop

Confirm each cited defect against the live source, implement one coherent
owner slice, add evidence at its real boundary, run format/check/unit,
simulation, fuzz, audit, and diff gates, then update scores only from observed
behavior.
