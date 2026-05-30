# Researcher A Hygiene Audit

Date: 2026-05-30

Scope: top-down hygiene audit from `howl-linux-host` through `howl-pty`, `howl-vt`, and `howl-render`, focused on C ABI lane shape, file/folder/symbol cohesion, and in-file organization. No implementation performed.

## Sources Read

- TigerBeetle style law: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:367`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:463`.
- TigerBeetle architecture pressure: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:408`.
- Howl law and memory: `AGENTS.md:9`, `AGENTS.md:86`, `AGENTS.md:105`, `AGENTS.md:128`, `loop.txt:26`, `loop.txt:90`, `project-memory.md:15`, `project-memory.md:127`, `libs.yaml:4`, `libs.yaml:121`, `libs.yaml:138`, `libs.yaml:215`.
- Ghostty reference pressure: `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:28`, `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:113`, `utils/dev_references/terminals/ghostty/include/ghostty/vt/terminal.h:28`, `utils/dev_references/terminals/ghostty/include/ghostty/vt/terminal.h:42`, `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:22`, `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:29`, `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:1`, `utils/dev_references/terminals/ghostty/src/terminal/stream.zig:32`.
- Alacritty reference pressure: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:18`, `utils/dev_references/terminals/alacritty/alacritty/src/main.rs:30`, `utils/dev_references/terminals/alacritty/alacritty/src/main.rs:132`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:1`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47`.

## Critical Findings

### C ABI Lane Is Not Factory-Generated Across Libraries

Symptom: each ABI library has a different public header and export-lane style, so the product boundary does not read as one small generated C lane.

Evidence: `howl-pty/include/howl_pty.h:13` starts with typed status enums and a compact function list through `howl-pty/include/howl_pty.h:118`; `howl-vt/include/howl_vt.h:14` uses broad hand-section banners and mixed anonymous enums through `howl-vt/include/howl_vt.h:81`; `howl-render/include/howl_render.h:17` uses a macro for one limit, many hand-ordered typedefs through `howl-render/include/howl_render.h:374`, and a local prose comment at `howl-render/include/howl_render.h:398`. Export roots are also hand-maintained and differently grouped: `howl-pty/src/libhowl_pty.zig:3`, `howl-vt/src/libhowl_vt.zig:3`, and `howl-render/src/libhowl_render.zig:9`.

Why this violates pressure: Howl says the ABIs are the product at `AGENTS.md:9`, public roots curate exports only at `AGENTS.md:107`, and FFI translates contracts only at `AGENTS.md:110`. TigerBeetle requires names to be exact at `TIGER_STYLE.md:273` and order to support top-down reading at `TIGER_STYLE.md:315`. Ghostty's C lane is broad, but explicitly grouped with a main header index at `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:28` and group headers at `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:113`; Howl does not want Ghostty's Zig module lane, but it should still learn from the disciplined C grouping.

Proposed owner-true shape: make each C ABI package expose one generated-looking header shape: include guard, includes, opaque handles, status/limits, owner structs, owner methods. Keep manually curated Zig export roots, but make them mechanically ordered by ABI owner and method name. Do not add compatibility typedefs or old aliases.

Candidate slice boundary: audit and normalize `howl-pty/include/howl_pty.h`, `howl-vt/include/howl_vt.h`, `howl-render/include/howl_render.h`, plus `howl-pty/src/libhowl_pty.zig`, `howl-vt/src/libhowl_vt.zig`, and `howl-render/src/libhowl_render.zig`. No semantic ABI additions in this slice unless required to preserve layout assertions.

Tests/gates/grep gates: `zig build check`, `zig build test`, `git diff --check`; grep for section banners in headers; grep for anonymous ABI enums in headers; grep that export roots contain only imports, `comptime` exports, and tests.

Risks: ABI reordering is source-visible to embedders even when layout-compatible. Since Howl has no downstream per `AGENTS.md:15`, this is acceptable, but the slice must not smuggle behavior changes.

## High Findings

### VT Public/Internal Roots Are Bucket Aggregators, Not Small Intentional Owners

Symptom: VT has multiple aggregation roots that re-export broad symbol sets, including compatibility-style constants and whole-domain aliases.

Evidence: `howl-vt/src/howl_vt.zig:1` imports action, FFI, input, parser, screen, screen_set, selection, and terminal, then re-exports `Parser`, `ParserOwnedActions`, `ScreenSet`, and `Terminal` at `howl-vt/src/howl_vt.zig:11`. `howl-vt/src/input.zig:7` through `howl-vt/src/input.zig:93` re-export keyboard, mouse, event, encoded, scratch, and encoder symbols. `howl-vt/src/action.zig:6` through `howl-vt/src/action.zig:22` re-export parser events, vocabulary, route functions, and ESC actions. `howl-vt/src/parser.zig:3` through `howl-vt/src/parser.zig:17` re-export constants and types from `parser/main.zig`. `libs.yaml:149` records these as VT owner roots, proving the pattern is not accidental.

Why this violates pressure: Howl allows namespace wrappers to aggregate owners only at `AGENTS.md:108`, but these files aggregate too many unrelated decisions and create a Zig-shaped internal consumption lane. Howl also says internal terminal modules are not host integration targets in Zig-module shape at `AGENTS.md:91`. TigerBeetle warns that abstractions are not free at `TIGER_STYLE.md:90`, and demands nouns/verbs that capture the domain at `TIGER_STYLE.md:273`. Alacritty's public terminal crate root exposes modules and only a small pair of public type re-exports at `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7` and `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:18`.

Proposed owner-true shape: keep only package roots that curate a tiny public internal test surface. Move compatibility constants to the true C FFI translator if they are ABI-only, or to owner files if they are domain truth. Make `input`, `action`, and `parser` roots either pure module indexes or delete them in favor of direct owner imports.

Candidate slice boundary: start with `howl-vt/src/input.zig`, because it is the clearest bucket and has bounded call-site fallout. Replace root constants with direct owner imports or explicit C ABI translation symbols in `howl-vt/src/ffi.zig`.

Tests/gates/grep gates: `zig build -Dskip?` is unknown from this audit, so use root `zig build check`, `zig build test`; grep `howl-vt/src` for `pub const .* = .*\.` in root files; grep for imports of `howl_vt.zig`, `input.zig`, `action.zig`, and `parser.zig` from non-test code.

Risks: broad roots may be used by tests and fuzzers. The slice must distinguish testing convenience from product shape and avoid deleting useful owner tests.

### Host Main File Still Mixes Product Code And Local Test Harnesses

Symptom: `main.zig` is an app/event-loop owner and a large test container at the same time.

Evidence: `howl-linux-host/src/main.zig:70` defines `App`, `howl-linux-host/src/main.zig:84` defines `main`, and event-loop control runs through `howl-linux-host/src/main.zig:208`. Tests begin inside the same file at `howl-linux-host/src/main.zig:572`, continue through fake-tab harnesses at `howl-linux-host/src/main.zig:597`, and normal product functions resume at `howl-linux-host/src/main.zig:690`.

Why this violates pressure: TigerBeetle says files are read top-down and important things go near the top at `TIGER_STYLE.md:315`, and comments/tests should explain methodology without forcing the reader to dive around at `TIGER_STYLE.md:363`. Alacritty keeps the app entrypoint and module declarations in `utils/dev_references/terminals/alacritty/alacritty/src/main.rs:30`, then describes the application bootstrap at `utils/dev_references/terminals/alacritty/alacritty/src/main.rs:132`; it does not interleave unit tests inside the middle of the entrypoint file in the inspected region.

Proposed owner-true shape: keep `main.zig` as the app/event-loop owner. Move helper-unit tests into `howl-linux-host/src/test/main.zig` or owner-specific test files that import the relevant helper through a deliberately exposed test-only root. If helper functions are not worth exposing, move the helper and its tests to the true owner file.

Candidate slice boundary: extract tests from `howl-linux-host/src/main.zig` without changing behavior. If Zig visibility blocks this, stop and promote a smaller owner-seam slice rather than adding broad public aliases.

Tests/gates/grep gates: `zig build check`, `zig build test`, `git diff --check`; grep `howl-linux-host/src/main.zig` for `^test "`; grep that new test file imports no C ABI internals directly.

Risks: tests may currently rely on private helpers. Making helpers public just for tests would worsen the boundary; moving helpers to true owners may be necessary.

## Medium Findings

### Render Taxonomy Still Has Stale Root Files And Banned Vocabulary

Symptom: render source contains both accepted owner subfolders and stale flat root wrappers, and it still uses `pipeline` vocabulary.

Evidence: `howl-render/src/libhowl_render.zig:1` imports flat root files including `prepare_request.zig`, `prepared_surface.zig`, `submission.zig`, `surface_geometry.zig`, `text_session.zig`, `vt_surface.zig`, and `work_state.zig`. The source tree also contains owner files under `howl-render/src/source/vt.zig`, `howl-render/src/session/text.zig`, `howl-render/src/prepared/surface.zig`, and `howl-render/src/render/geometry.zig` as recorded in `libs.yaml:231`. `howl-render/src/session/text.zig:17` imports `../text/pipeline.zig`, while `project-memory.md:29` marks `pipeline` as banned owner vocabulary and `project-memory.md:188` rejects new `pipeline` buckets. The file `howl-render/src/text/pipeline.zig:5` defines render pipeline stages and `howl-render/src/text/pipeline.zig:152` defines callback operation types, so this is not just a dead filename.

Why this violates pressure: Howl memory already accepted `source/*`, `prepared/*`, `session/*`, and `render/*` as the render direction at `project-memory.md:170` through `project-memory.md:181`. The same memory rejects vague `pipeline` vocabulary at `project-memory.md:188`. TigerBeetle naming pressure says names must capture what a thing is or does at `TIGER_STYLE.md:273`.

Proposed owner-true shape: treat flat root files as C ABI translators only if they export C functions; otherwise move them under their true owner. Rename `text/pipeline.zig` by owned content, likely `text/resolve.zig` or split into `text/resolve.zig`, `text/shape_request.zig`, and `text/raster_request.zig` after proof from callers.

Candidate slice boundary: first slice should be no behavior: rename `text/pipeline.zig` to the smallest true noun and update imports. Do not touch text shaping behavior.

Tests/gates/grep gates: `zig build check`, `zig build test`; grep `howl-render/src` for `pipeline`; grep `libs.yaml` for banned owner vocabulary after code changes.

Risks: `pipeline` may be used in scratchpads and docs; update only authoritative owner maps and code in the implementation slice, not historical scratchpads.

### VT Terminal And Screen Owners Are Still Very Broad

Symptom: `Terminal` and `Screen` own too much state directly and mix lifecycle, surface publication, runtime obligation, selection, host effects, parser stream state, Kitty state, and grid state in one place.

Evidence: `howl-vt/src/terminal.zig:17` defines `Terminal`; fields include allocator, stream, screen set, modes, Kitty, host, GL charset state, dirty generation, and surface snapshot state at `howl-vt/src/terminal.zig:24` through `howl-vt/src/terminal.zig:41`. The same file owns init variants at `howl-vt/src/terminal.zig:57`, feeding at `howl-vt/src/terminal.zig:128`, resizing at `howl-vt/src/terminal.zig:142`, surface publication at `howl-vt/src/terminal.zig:173`, runtime obligation stubs at `howl-vt/src/terminal.zig:195`, hyperlink lookup at `howl-vt/src/terminal.zig:210`, and selection mutation at `howl-vt/src/terminal.zig:223`. `howl-vt/src/screen.zig:25` defines `Screen`; its fields include grid dimensions, cursor, modes, margins, history buffers, dirty rows, tabs, and pixel size at `howl-vt/src/screen.zig:46` through `howl-vt/src/screen.zig:88`.

Why this violates pressure: Howl says owner files own state and mutation but mutation should move to the smallest true owner at `AGENTS.md:109` and `AGENTS.md:111`. Ghostty's `Terminal` is also large, but it documents the primary terminal structure and scrollback ownership up front at `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:1`; it then uses named nested state such as `Colors` at `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:132` and dirty state at `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig:149`. Alacritty makes `Term` the high-level API for `Grid` at `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:1`, but its crate root still separates `grid`, `selection`, `term`, and `tty` modules at `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7`.

Proposed owner-true shape: do not redo VT in one slice. Split first by product seams: surface publication state, selection state, runtime obligation state, and host protocol effects should become explicit owner fields or owner files. Keep `Terminal` as composer and state transition entrypoint.

Candidate slice boundary: extract `surface_snapshot_*` fields and methods from `howl-vt/src/terminal.zig` into a VT surface publication owner. This is cohesive and tied to C ABI surface copy/ack behavior.

Tests/gates/grep gates: `zig build check`, `zig build test`; existing `howl-vt/src/test/terminal_surface.zig` should remain green; grep `terminal.zig` for `surface_snapshot_` after extraction.

Risks: extracting too much at once will create fake owners. The first slice must preserve `Terminal` as the only mutation entrypoint exposed to FFI.

## Low Findings

### Header Section Banners Hurt More Than They Help

Symptom: `howl-vt/include/howl_vt.h` uses numbered banner comments that impose a hand-written table-of-contents instead of owner grouping.

Evidence: banners appear at `howl-vt/include/howl_vt.h:83`, `howl-vt/include/howl_vt.h:247`, `howl-vt/include/howl_vt.h:295`, and `howl-vt/include/howl_vt.h:302`. The banner names do not align one-to-one with owner roots in `libs.yaml:149` through `libs.yaml:214`.

Why this violates pressure: TigerBeetle says comments should be prose that explains why/how, not scribbles in the margin at `TIGER_STYLE.md:360` and `TIGER_STYLE.md:367`. Ghostty uses Doxygen groups with definitions and examples at `utils/dev_references/terminals/ghostty/include/ghostty/vt/terminal.h:28` and `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:22`; Howl does not need Ghostty's volume, but owner grouping should be structural, not ornamental.

Proposed owner-true shape: replace decorative banners with compact owner comments only where they explain ABI consequences. Prefer generated-looking contiguous declarations.

Candidate slice boundary: include in the C ABI lane normalization slice, not alone.

Tests/gates/grep gates: `git diff --check`; grep headers for long dash banners.

Risks: removing banners without improving order would reduce navigability; do both together.

## C ABI Lane Audit

- `howl-pty/include/howl_pty.h:95` through `howl-pty/include/howl_pty.h:118` is the closest to the desired small C lane: opaque handle, status, typed result structs, and direct functions.
- `howl-vt/include/howl_vt.h:14` through `howl-vt/include/howl_vt.h:81` mixes input constants, mouse enums, call status, and capacity constants before any terminal owner method. This is not factory-generated enough.
- `howl-render/include/howl_render.h:164` through `howl-render/include/howl_render.h:300` exposes source/VT surface publication types inline in a long render header. The names are better after prior cleanup, but the order still reads like accumulated strata rather than generated owner groups.
- `howl-render/src/ffi.zig:1` is clean as a C import translator, while `howl-vt/src/ffi.zig:21` through `howl-vt/src/ffi.zig:225` redefines the ABI mirror manually. That may be necessary for exported Zig functions, but it raises the burden for layout assertions and generated-looking order.
- Ghostty pressure is not to copy its many headers. Ghostty's useful lesson is explicit group ownership: main index at `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:28`, includes at `utils/dev_references/terminals/ghostty/include/ghostty/vt.h:113`, terminal group at `utils/dev_references/terminals/ghostty/include/ghostty/vt/terminal.h:28`, and render group at `utils/dev_references/terminals/ghostty/include/ghostty/vt/render.h:22`.

## File And Symbol Convention Audit

- Good: `howl-pty/src/libhowl_pty.zig:1` through `howl-pty/src/libhowl_pty.zig:19` is a public root that only curates exports.
- Bad: `howl-vt/src/input.zig:7` through `howl-vt/src/input.zig:93` is a bucket of aliases. This is the most obvious VT symbol-convention cleanup.
- Bad: `howl-vt/src/howl_vt.zig:11` through `howl-vt/src/howl_vt.zig:14` creates a broad internal public lane unrelated to the C ABI product lane.
- Bad: `howl-render/src/text/pipeline.zig:5` uses the banned `pipeline` noun and owns multiple concepts under one file.
- Needs proof: `howl-render/src/vt_surface.zig:13` through `howl-render/src/vt_surface.zig:64` may be acceptable as an FFI boundary translator, but its root-level name competes with accepted `source/*` and `session/*` owner folders from `project-memory.md:170` through `project-memory.md:181`.

## In-File Organization Convention

- Preferred convention from TigerBeetle: most important entrypoint first, fields then nested types then methods for structs, assertions near preconditions, comments as sentences explaining why, and no function beyond 70 lines. Sources: `TIGER_STYLE.md:161`, `TIGER_STYLE.md:315`, `TIGER_STYLE.md:318`, `TIGER_STYLE.md:367`.
- Howl should not standardize on decorative banners. In headers, order should do the navigation. In Zig, a short module doc comment can help if it states ownership, but banner sections should be rejected unless they are generated API documentation.
- Assertions are uneven. `howl-linux-host/src/main.zig:717` and `howl-linux-host/src/main.zig:727` show good local assertions around active tab bounds, while `howl-vt/src/terminal.zig:165` returns false for zero snapshot without a paired assertion at the call boundary. This needs deeper per-owner review before changing.
- Tests embedded mid-file hurt top-down reading. The clearest example is `howl-linux-host/src/main.zig:572` through `howl-linux-host/src/main.zig:688`, followed by product code resuming at `howl-linux-host/src/main.zig:690`.

## Top 5 First Slices

1. Normalize the C ABI lane order and comments across `howl_pty.h`, `howl_vt.h`, and `howl_render.h`, plus export-root ordering. Highest leverage because ABI is product law.
2. Delete or shrink `howl-vt/src/input.zig` as a bucket root. Safest VT hygiene slice because evidence is strong and behavior should not change.
3. Extract `howl-linux-host/src/main.zig` tests out of the app owner without making product helpers broadly public. Improves top-down readability and keeps host ownership clean.
4. Rename/split `howl-render/src/text/pipeline.zig` to owner-true text resolve/shape/raster request names. Enforces accepted banned-vocabulary memory.
5. Extract VT surface publication state from `howl-vt/src/terminal.zig`. Starts the near-redo in a constrained, ABI-visible seam.

## Non-Goals

- Do not copy Ghostty's multi-header C surface wholesale; Howl wants one small intuitive C lane.
- Do not add Zig-shaped host shortcuts or public internal terminal integration lanes.
- Do not add compatibility aliases for old names.
- Do not combine hygiene with protocol feature work such as OSC 52, hyperlinks, selection, or dynamic colors.
- Do not move behavior merely to make files smaller; owners must become more true, not more numerous.

## Open Questions

- Should Howl generate headers from a Zig-side ABI description, or merely enforce generated-looking hand-written headers? Proof missing: current build system/header-install expectations.
- Should `howl-vt/src/howl_vt.zig` exist at all after the C ABI lane is treated as product, or is it only a test convenience? Proof missing: import graph from tests, fuzzers, and package roots.
- Is `howl-render/src/vt_surface.zig` intended as a permanent FFI translator root, or stale from pre-`source/*` cleanup? Proof missing: accepted render follow-up slice after `project-memory.md:170`.
- What exact test taxonomy should own extracted app tests? `project-memory.md:296` records a build/test architecture blocker, so test relocation should not invent a new taxonomy without that plan.
