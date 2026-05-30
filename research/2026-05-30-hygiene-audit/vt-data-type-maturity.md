# VT Data Type Maturity

Date: 2026-05-30

## Question

How should Howl mature VT data types so protocol semantics are encoded intuitively and efficiently, following Ghostty first and TigerBeetle always, without blindly replacing switches with tables?

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/terminals/ghostty/src/terminal/size.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/page.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/point.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/parse_table.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/ansi.zig`
- `howl-vt/src/parser/parse_table.zig`
- `howl-vt/src/parser/main.zig`
- `howl-vt/src/parser/events.zig`
- `howl-vt/src/xterm/c0.zig`
- `howl-vt/src/xterm/csi/plain.zig`
- `howl-vt/src/xterm/csi/params.zig`
- `howl-vt/src/screen/cell.zig`
- `howl-vt/src/screen/style.zig`
- `howl-vt/src/screen/color.zig`
- `howl-vt/src/screen.zig`
- `howl-vt/src/action/vocabulary.zig`

## Findings

Ghostty does not replace all switches with tables. It uses tables where the domain is dense and state-machine shaped, and switches where tagged semantic dispatch is the clearest form.

Ghostty table example:

- `terminal/parse_table.zig` generates a `[byte][state]Transition` table at comptime.
- The parser hot path indexes the table instead of re-deciding the DEC parser transition shape byte by byte.
- The table is still built from explicit `single` and `range` calls so the source remains auditable against the DEC parser model.

Howl already follows this pattern in `howl-vt/src/parser/parse_table.zig`:

- `ParseState`, `TransitionAction`, `Transition`, and `table` mirror the Ghostty/vt100.net table shape.
- The immediate parser-table maturity gap is not “use a table”; it is proving exact equivalence to Ghostty/DEC and keeping actions semantically typed after parsing.

Ghostty rich-type examples:

- `terminal/size.zig` gives size domains explicit integer types: `CellCountInt`, `StyleCountInt`, `HyperlinkCountInt`, `GraphemeBytesInt`, `StringBytesInt`.
- `terminal/size.zig` wraps offsets in `Offset(T)`, a packed typed offset with methods, rather than passing raw byte offsets everywhere.
- `terminal/point.zig` models coordinate spaces as `Point = union(Tag)` with `active`, `viewport`, `screen`, and `history` variants. The type prevents silently mixing coordinate spaces.
- `terminal/ansi.zig` gives protocol byte domains names: `C0`, `RenditionAspect`, `CursorStyle`, `StatusLineType`, `StatusDisplay`, `ModifyKeyFormat`, `ProtectedMode`.
- `terminal/Parser.zig` models parser output as tagged unions with borrowed-slice lifetime comments and bounded arrays.

Howl already has some good shapes:

- `howl-vt/src/parser/main.zig` has bounded parser arrays, `CsiSeparatorList`, `OscTerminator`, `OscAction`, `DcsHook`, `CsiAction`, and `Action`.
- `howl-vt/src/action/vocabulary.zig` has `SemanticEvent` and `ScreenAction` tagged unions, which is the correct broad direction for semantic dispatch.
- `howl-vt/src/screen/color.zig` uses `Color` with `Kind` instead of raw RGB/index/default mixing.

Howl maturity gaps found in this pass:

- `howl-vt/src/xterm/c0.zig` accepts raw `u8` control bytes and returns `C0Action`. There is no protocol byte enum equivalent to Ghostty `ansi.C0`.
- `howl-vt/src/xterm/csi/params.zig` returns erase mode as raw `u2`; `SemanticEvent` carries `erase_display: u2`, `erase_line: u2`, `selective_erase_display: u2`, and `selective_erase_line: u2`.
- `howl-vt/src/parser/main.zig` and `howl-vt/src/action/vocabulary.zig` carry many OSC command identities as raw `u16` even when they are known protocol commands.
- `howl-vt/src/selection/state.zig` and `screen_set.View` still use raw coordinate conventions, including negative `i32` rows for history. Ghostty's `point.Point` makes coordinate space explicit.
- `howl-vt/src/screen/cell.zig` stores many style booleans in an unpacked `CellAttrs` struct. Ghostty uses a more compact style model with packed flags and page-local style sets. This is a later screen/page storage redesign, not a quick flag packing slice.
- `howl-vt/src/parser/events.zig` uses several parallel `ArrayList` stores and cursor heads. This is bounded by explicit maxes in places, but it needs its own ownership/capacity review before any table/type rewrite.

## Decision

Do not make “tables instead of switches” a generic rule.

Use this rule instead:

- Dense byte/state protocols use generated tables with duplicate-transition assertions and explicit ranges.
- Tagged semantic consequences use unions and switches.
- Raw numeric protocol domains get named enum/packed/struct types when the type prevents mixing meanings or documents a bounded grammar.
- Coordinate spaces must become explicit before deeper selection/screen work; raw negative-history rows are acceptable only as a temporary ABI-adjacent representation.
- Storage-shape changes such as packed style flags or page-local style sets are deeper screen/page work and must not be smuggled into parser cleanup.

## Candidate Slices

### Slice A: VT Protocol Scalar Vocabulary

Goal: introduce exact protocol scalar types where Howl currently uses raw integers for known semantic domains.

Likely files:

- `howl-vt/src/xterm/c0.zig`
- `howl-vt/src/xterm/csi/params.zig`
- `howl-vt/src/action/vocabulary.zig`
- Callers applying erase modes and C0 actions.

Possible types:

- `C0` enum for handled C0 controls, following Ghostty `ansi.C0` posture.
- `EraseMode` enum or packed enum for ED/EL/DECSED/DECSEL values instead of raw `u2`.
- `CursorStyleParam` or equivalent only if it reduces ambiguity around `CSI Ps SP q` without adding a wrapper bucket.

Non-goals:

- Do not rewrite parser table.
- Do not change public C ABI.
- Do not change semantic behavior.
- Do not create `types.zig`.

Required tests:

- Existing action mapping tests stay green.
- Add focused tests that invalid erase values collapse to default behavior exactly as before.
- Add focused C0 tests for handled and ignored controls.

### Slice B: VT Coordinate Space Vocabulary

Goal: make active/visible/history coordinate spaces explicit before selection and surface publication work.

Likely files:

- `howl-vt/src/selection/state.zig`
- `howl-vt/src/screen_set.zig`
- `howl-vt/src/ffi.zig` only as C coordinate translation.

Reference:

- Ghostty `terminal/point.zig`.

Non-goals:

- Do not introduce Ghostty pins yet.
- Do not redesign screen storage.
- Do not change the C selection ABI.

### Slice C: VT Screen Storage Maturity Research

Goal: compare Howl flat cell/history arrays against Ghostty page, offset, style-set, grapheme, and hyperlink storage.

Likely references:

- Ghostty `terminal/page.zig`
- Ghostty `terminal/PageList.zig`
- Ghostty `terminal/style.zig`
- Howl `screen.zig`, `screen/history.zig`, `screen/cell.zig`, `screen/style.zig`

Status:

- Research-only. Not worker-ready.

## Recommended Next Slice

Do not interrupt the active VT selection research slice.

After the selection FFI extraction plan is either implemented or deliberately deferred, promote Slice A: VT Protocol Scalar Vocabulary. It is the smallest data-type maturity slice because it improves semantic encoding without touching screen storage, C ABI, or selection coordinate design.

## Review Gates For Future Slice A

- `rg 'erase_display: u2|erase_line: u2|selective_erase_display: u2|selective_erase_line: u2' howl-vt/src/action/vocabulary.zig` prints nothing after replacement.
- `rg '0x0A|0x0B|0x0C|0x0D|0x08|0x09' howl-vt/src/xterm/c0.zig` supports review that control byte constants are named or intentionally mapped.
- `zig build check`
- `zig build test`
- `git diff --check`

## Risks

- Over-typing can create wrapper churn without improving correctness. Each type must encode a real protocol boundary or prevent a real class of mixup.
- Tables can hide semantics if generated from opaque data. Keep tables explicit and source-order auditable like Ghostty's `parse_table.zig`.
- Storage compaction is tempting but dangerous. Packed style/page work belongs to a deep screen/page slice with reference-backed invariants and tests.
