# Researcher C Hygiene Audit

Date: 2026-05-30

## Scope

Top-down hygiene audit from host through PTY, VT, and render. Focus was C ABI lane shape, file/folder/symbol conventions, owner cohesion, VT bucket/root pressure, and in-file organization conventions. This report is research only. It does not implement, promote a slice, or commit.

## Sources Read

- TigerBeetle style: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:21`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:151`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:161`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:367`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:463`.
- TigerBeetle architecture: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:94`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:168`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:408`, `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:424`.
- Howl law and memory: `AGENTS.md:9`, `AGENTS.md:86`, `AGENTS.md:95`, `AGENTS.md:105`, `AGENTS.md:118`, `AGENTS.md:128`, `loop.txt:1`, `loop.txt:40`, `project-memory.md:15`, `project-memory.md:127`, `project-memory.md:250`, `libs.yaml:4`, `libs.yaml:121`, `libs.yaml:138`, `libs.yaml:215`.
- Ghostty reference pressure: `utils/dev_references/terminals/ghostty/src/main_c.zig:1`, `utils/dev_references/terminals/ghostty/src/main_c.zig:20`, `utils/dev_references/terminals/ghostty/src/main_c.zig:33`, `utils/dev_references/terminals/ghostty/src/main_c.zig:104`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:1`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:30`, `utils/dev_references/terminals/ghostty/src/terminal/main.zig:77`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:1`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:29`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:38`, `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:62`.
- Alacritty reference pressure: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7`, `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:18`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:188`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:196`, `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:208`, `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:83`, `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:147`, `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:197`.

## Critical Findings

None proven. I did not find a hygiene issue that necessarily means current product behavior is corrupt. The audit did find high-severity structural debt that will keep producing ABI and owner mistakes unless cut into explicit cleanup slices.

## High Findings

### H1. VT FFI Is A Bucket Translator And Policy Owner

Symptom: `howl-vt/src/ffi.zig` owns C translation, visible-selection projection, selection text copy, surface metadata packing, input encoding exports, tests, and allocation policy in one 1,152-line file.

Evidence: `howl-vt/src/ffi.zig` defines the C handle and opaque ABI types at `howl-vt/src/ffi.zig:9`, ABI layout assertions at `howl-vt/src/ffi.zig:12`, many extern structs starting at `howl-vt/src/ffi.zig:30`, pointer translation helpers at `howl-vt/src/ffi.zig:240`, surface cell conversion at `howl-vt/src/ffi.zig:280`, selection viewport helpers at `howl-vt/src/ffi.zig:442`, visible selection mutation at `howl-vt/src/ffi.zig:496`, selection text allocation/copy at `howl-vt/src/ffi.zig:509`, terminal allocation at `howl-vt/src/ffi.zig:544`, surface copy at `howl-vt/src/ffi.zig:610`, and inline FFI tests from `howl-vt/src/ffi.zig:836` through `howl-vt/src/ffi.zig:1152`.

Why it violates pressure: Howl law says FFI translates contracts only and owner files own state and mutation at `AGENTS.md:105`. TigerBeetle requires simple explicit control flow, scoped variables, and 70-line function pressure at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`, `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:158`, and `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:161`. Ghostty keeps C API entry concerns in `main_c.zig` with explicit C API assertions/imports at `utils/dev_references/terminals/ghostty/src/main_c.zig:20` and `utils/dev_references/terminals/ghostty/src/main_c.zig:33`, while terminal ownership is in the terminal module root at `utils/dev_references/terminals/ghostty/src/terminal/main.zig:55`.

Proposed owner-true shape: Keep `howl-vt/src/ffi.zig` as the one C lane entry translator, but move selection text materialization to the selection owner, visible selection projection to the surface/view owner, and ABI struct layout assertions/conversions into narrow ABI contract files named by product nouns, not `types`.

Candidate slice boundary: First slice only extracts selection copy/projection from `howl-vt/src/ffi.zig:442` through `howl-vt/src/ffi.zig:538` into the VT selection/surface owner and leaves exported function names unchanged.

Tests/gates/grep gates: Run `zig build test` at root if build taxonomy permits. Run package VT tests if available. Grep gates: `rg "fn copySelectionText|fn applyVisibleSelection|fn visibleSelectionRange|fn selectionRowSource" howl-vt/src/ffi.zig` must be empty; `rg "HowlVt" howl-vt/src/selection howl-vt/src/screen_set.zig` should stay empty unless the slice explicitly introduces a C-only adapter.

Risks: Selection semantics cross live rows and history rows. Current tests cover history-aware copy and visible selection at `howl-vt/src/ffi.zig:1083` and `howl-vt/src/ffi.zig:1117`; moving ownership without preserving those cases can regress copy/presentation consistency.

### H2. VT Root And Bucket Aggregators Hide Ownership

Symptom: VT has broad wrapper roots that aggregate nouns, constants, functions, and imported owner behavior. `howl-vt/src/input.zig` re-exports keyboard, mouse, event, encoding, constants, and functions from `howl-vt/src/input.zig:7` through `howl-vt/src/input.zig:93`. `howl-vt/src/action.zig` re-exports semantic/event vocabulary and route functions from `howl-vt/src/action.zig:6` through `howl-vt/src/action.zig:22`. `howl-vt/src/parser.zig` re-exports parser internals from `howl-vt/src/parser.zig:3` through `howl-vt/src/parser.zig:17`. `howl-vt/src/kitty.zig` re-exports kitty owners from `howl-vt/src/kitty.zig:1` through `howl-vt/src/kitty.zig:11`.

Evidence: The public root `howl-vt/src/libhowl_vt.zig` is clean export curation only at `howl-vt/src/libhowl_vt.zig:3`, but internal roots become broad convenience lanes. `libs.yaml` records these wrappers as roots for parser, action, input, and kitty at `libs.yaml:153`, `libs.yaml:161`, `libs.yaml:185`, and `libs.yaml:201`.

Why it violates pressure: Howl permits namespace wrappers to aggregate owners only, but owner files must own state/mutation and public roots curate exports only at `AGENTS.md:105`. TigerBeetle says names must capture what a thing is or does at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273` and file order/readability matter because files are read top-down at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`. Ghostty has a Zig module lane with a broad terminal root at `utils/dev_references/terminals/ghostty/src/terminal/main.zig:1`, but Howl law explicitly forbids hosts or embedding paths from targeting internal Zig-module shape at `AGENTS.md:91`.

Proposed owner-true shape: Treat `libhowl_vt.zig` as the only product root. Inside VT, remove or sharply narrow wrappers so callers import exact owners: `input/encode.zig`, `input/keyboard.zig`, `input/mouse.zig`, `action/route.zig`, `action/vocabulary.zig`, `parser/main.zig`, `parser/events.zig`, and kitty owner files.

Candidate slice boundary: Start with `howl-vt/src/input.zig` because it is demonstrably a re-export bucket and has many constants/functions. Replace internal imports of `input.zig` with exact owner imports, then shrink `input.zig` to C ABI-facing compatibility only or delete it if no internal callers remain.

Tests/gates/grep gates: `rg '@import\("input.zig"\)' howl-vt/src` should be empty after the input slice except `ffi.zig` if explicitly preserved. `rg 'pub const key_|pub const mouse_|pub const encode' howl-vt/src/input.zig` should be empty. Run VT tests and root `zig build test`.

Risks: C enum values in `howl-vt/include/howl_vt.h:14` through `howl-vt/include/howl_vt.h:65` are coupled to Zig constants consumed by FFI at `howl-vt/src/ffi.zig:307` and `howl-vt/src/ffi.zig:317`; the slice must preserve exact numeric ABI values.

### H3. C ABI Header Lane Does Not Look Factory Generated

Symptom: The three C headers differ in grouping, comments, enum style, line wrapping, handle naming, and type ordering. `howl-pty/include/howl_pty.h` is compact and unsectioned from `howl-pty/include/howl_pty.h:11` through `howl-pty/include/howl_pty.h:118`. `howl-vt/include/howl_vt.h` has hand-banner sections at `howl-vt/include/howl_vt.h:83`, `howl-vt/include/howl_vt.h:247`, `howl-vt/include/howl_vt.h:295`, and `howl-vt/include/howl_vt.h:302`. `howl-render/include/howl_render.h` has no equivalent top-level section grammar but has an isolated comment at `howl-render/include/howl_render.h:398`.

Evidence: Handle styles differ: PTY uses `typedef struct HowlPtySessionOpaque *HowlPtySessionHandle` at `howl-pty/include/howl_pty.h:11`; VT uses a named struct plus pointer typedef at `howl-vt/include/howl_vt.h:11` and `howl-vt/include/howl_vt.h:12`; render uses two named structs and pointer typedefs at `howl-render/include/howl_render.h:11` through `howl-render/include/howl_render.h:15`. Function wrapping differs: VT has a 185-column `howl_vt_terminal_copy_surface` prototype at `howl-vt/include/howl_vt.h:240`, while render has similarly long one-line prototypes at `howl-render/include/howl_render.h:376` through `howl-render/include/howl_render.h:405`.

Why it violates pressure: Howl states ABIs are the product at `AGENTS.md:9` and wants hosts to embed via the C ABI contracts at `AGENTS.md:86`. TigerBeetle caps line length at 100 columns at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:463` and emphasizes names as the mental model at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`. Ghostty's C API explicitly documents that `main_c.zig` is the C API embedding lane at `utils/dev_references/terminals/ghostty/src/main_c.zig:1`, and it places C ABI dependent assertions up front at `utils/dev_references/terminals/ghostty/src/main_c.zig:20`.

Proposed owner-true shape: Establish one generated-looking C header grammar for all Howl ABI libraries: include guard, includes, extern C, opaque handles, limits, status enums, product enums, plain structs, function groups, no ornamental banners, no one-off prose comments, no prototypes beyond 100 columns. The grammar should be documented in a scratchpad and enforced by grep/format gates before changing semantics.

Candidate slice boundary: Header-only hygiene slice for handle declarations, section comments, and line wrapping across `howl-pty/include/howl_pty.h`, `howl-vt/include/howl_vt.h`, and `howl-render/include/howl_render.h`; no ABI symbol/value changes.

Tests/gates/grep gates: `git diff --check`; `awk 'length($0)>100 {print FNR ":" $0}' howl-*/include/*.h` should print nothing; `rg '/\* -{5,}|Owned prepared-surface|Shell input enums' howl-*/include/*.h` should print nothing; ABI tests under `howl-pty/src/test/abi.zig:3` and `howl-vt/src/test/abi.zig:4` must still import headers.

Risks: Header reshaping can look semantic to downstream readers even if ABI-stable. Since the product is private and project law allows ABI breakage when correct at `project-memory.md:195`, the bigger risk is preserving ugly hand shape out of fear.

## Medium Findings

### M1. Render Still Has Compatibility/Shim Roots That Fight The Accepted Taxonomy

Symptom: Render has root-level files that appear to wrap or bridge owner files: `howl-render/src/vt_surface.zig` imports `howl-render/src/source/*` and `howl-render/src/surface/tokens.zig` at `howl-render/src/vt_surface.zig:4` through `howl-render/src/vt_surface.zig:7`; `howl-render/src/submission.zig` imports prepared owner, submit result, and tokens at `howl-render/src/submission.zig:3` through `howl-render/src/submission.zig:6`; `howl-render/src/prepare_request.zig` imports handle and tokens at `howl-render/src/prepare_request.zig:3` and `howl-render/src/prepare_request.zig:4`. The public export root then exports those wrapper functions at `howl-render/src/libhowl_render.zig:19` through `howl-render/src/libhowl_render.zig:36`.

Evidence: Project memory says the accepted direction is `source/*`, `prepared/*`, `session/*`, and `render/*`, with `surface` not acting as an umbrella source folder at `project-memory.md:168` through `project-memory.md:183`. It also records suspicious old vocabulary and owner-true replacements at `project-memory.md:195` through `project-memory.md:221`.

Why it violates pressure: Howl says public roots curate exports only and namespace wrappers aggregate owners only at `AGENTS.md:105`; render root wrappers currently translate ABI and reach across multiple owners. TigerBeetle says abstractions are not zero cost and should be minimal at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90`. Alacritty separates terminal state crate exports from display/renderer owners at `utils/dev_references/terminals/alacritty/alacritty_terminal/src/lib.rs:7` and `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:188`.

Proposed owner-true shape: Move ABI entry functions next to the owning contract noun or into a single render C ABI translator that delegates to owner files without owning policy. Root-level `vt_surface.zig`, `submission.zig`, and `prepare_request.zig` should either become pure FFI adapters with no owner decisions or disappear in favor of owner-named ABI files.

Candidate slice boundary: First render slice inventories and deletes one root shim. `howl-render/src/prepare_request.zig` is smallest at 59 lines and only adapts `takePrepareRequest` and token conversion at `howl-render/src/prepare_request.zig:6` through `howl-render/src/prepare_request.zig:59`.

Tests/gates/grep gates: `rg '@import\("prepare_request.zig"\)' howl-render/src` should only hit the intended new owner or no files. Run render package tests and root `zig build test`.

Risks: The wrapper files may be intentionally serving as a C lane. If so, the missing proof is an accepted C ABI file-layout convention for render.

### M2. Render Text Uses Banned Pipeline Vocabulary

Symptom: `howl-render/src/text/pipeline.zig` exists and is imported as `text_pipeline` by `howl-render/src/session/text.zig:17`, `howl-render/src/text/font/ft_hb/support.zig:7`, `howl-render/src/prepared/surface.zig:4`, and `howl-render/src/prepared/submit_result.zig:2`. `howl-render/src/text/frame_preparer.zig` imports it as `pipeline` at `howl-render/src/text/frame_preparer.zig:6` and uses `pipeline.TextPrepareCounters` at `howl-render/src/text/frame_preparer.zig:43`.

Evidence: Project memory bans owner vocabulary including `pipeline` at `project-memory.md:29` through `project-memory.md:31`, and render-specific memory says no new `pipeline` buckets at `project-memory.md:184` through `project-memory.md:190`. `libs.yaml` still names `text_flow: howl-render/src/text/pipeline.zig` at `libs.yaml:274`.

Why it violates pressure: The symbol `pipeline` is an ownerless process bucket unless proven otherwise. TigerBeetle demands exact nouns and verbs at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:273`; Howl bans broad owner vocabulary at `AGENTS.md:114`.

Proposed owner-true shape: Rename/split `pipeline.zig` by actual contents after reading it in a dedicated slice. Candidate owners likely include prepare counters, rasterize request/op, or text flow contract, but this report does not prove the exact split because `pipeline.zig` content was not fully read.

Candidate slice boundary: Research-only child slice to inspect `howl-render/src/text/pipeline.zig` and all imports before implementation. Do not rename blindly.

Tests/gates/grep gates: `rg 'pipeline|text_pipeline|text_flow' howl-render/src libs.yaml project-memory.md` must be intentional after cleanup. Render tests must cover scene prep and prepared submit metrics.

Risks: A mechanical rename can produce nicer words without better ownership. This needs source-backed split by symbols.

### M3. Host Main Is Still The App Owner But Large Enough To Hide Policy Drift

Symptom: `howl-linux-host/src/main.zig` defines `App` with window, tabs, input, terminal present state, and pacing at `howl-linux-host/src/main.zig:70` through `howl-linux-host/src/main.zig:82`; bootstraps config/window/tabs/input at `howl-linux-host/src/main.zig:97` through `howl-linux-host/src/main.zig:160`; and owns loop turn control at `howl-linux-host/src/main.zig:208` through `howl-linux-host/src/main.zig:250`.

Evidence: `libs.yaml` records host app ownership in `howl-linux-host/src/main.zig` at `libs.yaml:27` through `libs.yaml:35`. Project memory says host follow-up slices are inactive but current facts still put bootstrap/event-loop/tab/present ownership in `howl-linux-host/src/main.zig` at `project-memory.md:44` through `project-memory.md:48`.

Why it violates pressure only mildly: Alacritty's `Processor` owns event dispatch and windows at `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:83` through `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:101`, and `WindowContext` owns one terminal window aggregate at `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47` through `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:70`. Howl's shape is directionally consistent with that. The risk is size and hidden policy drift, not a proven owner violation.

Proposed owner-true shape: Keep main-thread control centralized, but require any new host policy to land in an existing exact owner before adding more to `main.zig`.

Candidate slice boundary: No immediate code slice. Add audit gate to future host slices: no new top-level structs/functions in `main.zig` unless the slice proves app ownership and cites Alacritty/Ghostty pressure.

Tests/gates/grep gates: Existing gates from memory: `zig build check`, `zig build test`, `git diff --check` at `project-memory.md:120` through `project-memory.md:125`.

Risks: Prematurely splitting `main.zig` can create exactly the banned runtime/controller layer. Do not split without a precise owner.

## Low Findings

### L1. Bannered Header Sections Hurt More Than They Help

Symptom: `howl-vt/include/howl_vt.h` uses ornamental section banners at `howl-vt/include/howl_vt.h:83`, `howl-vt/include/howl_vt.h:247`, `howl-vt/include/howl_vt.h:295`, and `howl-vt/include/howl_vt.h:302`; `howl-render/include/howl_render.h` uses a one-off prose marker at `howl-render/include/howl_render.h:398`.

Evidence: TigerBeetle says comments must be well-written prose explaining why/how at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:360` and `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:367`. These banners mostly repeat ordering, not rationale.

Why it violates pressure: The ABI lane should be generated-looking. Banners imply hand-maintained sections and invite inconsistent section taxonomies across headers.

Proposed owner-true shape: Use ordering and names instead of banners. If comments remain, use short product rationale comments only where a field/function has a non-obvious ABI consequence.

Candidate slice boundary: Include in H3 header grammar slice.

Tests/gates/grep gates: `rg '/\* -{5,}|/\* [0-9]\.|Owned prepared-surface|Shell input enums' howl-*/include/*.h` should be empty or explicitly justified.

Risks: Removing section banners may reduce navigability until the header order is made consistent.

## C ABI Lane Audit

The good part: Howl has one public root per ABI library and those roots export ABI symbols directly. PTY root exports only FFI functions at `howl-pty/src/libhowl_pty.zig:3` through `howl-pty/src/libhowl_pty.zig:19`; VT root exports only FFI functions at `howl-vt/src/libhowl_vt.zig:3` through `howl-vt/src/libhowl_vt.zig:32`; render root exports C ABI functions at `howl-render/src/libhowl_render.zig:9` through `howl-render/src/libhowl_render.zig:37`.

The bad part: The headers do not read as one factory lane. PTY has a compact status/session/control order at `howl-pty/include/howl_pty.h:13` through `howl-pty/include/howl_pty.h:57`; VT starts with shell input enums before surface state at `howl-vt/include/howl_vt.h:14` through `howl-vt/include/howl_vt.h:81`; render starts with render damage/prepare/submit status before geometry/source/prepared structs at `howl-render/include/howl_render.h:19` through `howl-render/include/howl_render.h:374`.

Needed convention: one C lane grammar, one handle style, one status enum style, one limits style, one function wrapping style, no banners, no ownerless comments, and ABI layout assertions paired near Zig C translators. Ghostty is not a direct model because Howl does not want a Zig module embedding lane, but Ghostty does model explicit C API entry documentation and C API dependent assertions at `utils/dev_references/terminals/ghostty/src/main_c.zig:1` and `utils/dev_references/terminals/ghostty/src/main_c.zig:20`.

## File And Symbol Convention Audit

The worst VT convention issue is wrapper roots. `howl-vt/src/input.zig` and `howl-vt/src/action.zig` are not small true owners; they are broad re-export maps at `howl-vt/src/input.zig:7` through `howl-vt/src/input.zig:93` and `howl-vt/src/action.zig:6` through `howl-vt/src/action.zig:22`. `howl-vt/src/screen.zig` is a real owner but very broad: it owns cursor, cells, margins, history, dirty rows, tab stops, cell pixel size, and many behaviors in one struct from `howl-vt/src/screen.zig:24` through `howl-vt/src/screen.zig:89`. Some of that breadth is legitimate terminal screen ownership; some should continue migrating to exact files already present under `howl-vt/src/screen/*`.

Render has cleaner owner folders in current memory, but root shims and `pipeline` vocabulary undermine that. The concrete files are `howl-render/src/vt_surface.zig:1`, `howl-render/src/submission.zig:1`, `howl-render/src/prepare_request.zig:1`, and `howl-render/src/text/pipeline.zig` as imported by `howl-render/src/text/frame_preparer.zig:6`.

PTY looks comparatively clean at top level. Its root `howl-pty/src/libhowl_pty.zig:3` exports ABI functions, and the public header is small at `howl-pty/include/howl_pty.h:1` through `howl-pty/include/howl_pty.h:124`. The unproven gap is whether PTY backend C imports in `howl-pty/src/pty/posix.zig:5` are isolated enough for platform owner clarity; this report did not audit PTY backend internals deeply.

## In-File Organization Convention

Recommended convention from TigerBeetle and references:

1. Imports and comptime layout assertions first when the file is an ABI translator. TigerBeetle supports compile-time assertions for subtle invariants at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:128`; Ghostty puts C API assertions before exports at `utils/dev_references/terminals/ghostty/src/main_c.zig:20`.
2. For owner structs, fields first, nested simple types second, methods third. TigerBeetle states struct order as fields, types, methods at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:318`.
3. Public functions before private helpers only when the public functions define the file's purpose top-down. TigerBeetle says important things go near the top at `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:315`.
4. Tests at the bottom are acceptable, but giant FFI files with many inline tests become unreadable. `howl-vt/src/ffi.zig` has production code until `howl-vt/src/ffi.zig:834` and tests from `howl-vt/src/ffi.zig:836` through `howl-vt/src/ffi.zig:1152`; this is evidence for extracting owner logic, not necessarily for moving tests first.
5. Bannered sections should not be the default. They are weaker than correct file splits and exact names. Header banners in `howl-vt/include/howl_vt.h:83` and `howl-vt/include/howl_vt.h:247` are low-value because they restate grouping rather than enforce ownership.

Assertion placement: ABI layout assertions should be paired with C translator structs. VT does this at `howl-vt/src/ffi.zig:12` through `howl-vt/src/ffi.zig:19`; render does it for source-cell ABI at `howl-render/src/vt_surface.zig:9` and `howl-render/src/vt_surface.zig:136` through `howl-render/src/vt_surface.zig:197`. The missing convention is consistent placement and naming across all ABI libraries.

## Top 5 First Slices

1. Define and apply C header grammar across PTY/VT/render headers. Highest leverage and safest because it can be comment/wrapping/ordering only with no ABI value changes. Candidate files: `howl-pty/include/howl_pty.h:11`, `howl-vt/include/howl_vt.h:11`, `howl-render/include/howl_render.h:11`.
2. Extract VT selection copy/projection out of `ffi.zig`. High leverage because it removes owner policy from C translation while preserving exported symbols. Candidate source range: `howl-vt/src/ffi.zig:442` through `howl-vt/src/ffi.zig:538`.
3. Collapse VT `input.zig` bucket by moving internal imports to exact input owners. Candidate source range: `howl-vt/src/input.zig:7` through `howl-vt/src/input.zig:93`.
4. Remove one render root shim, starting with `prepare_request.zig`. Candidate source range: `howl-render/src/prepare_request.zig:6` through `howl-render/src/prepare_request.zig:59`.
5. Research and then split/rename render `text/pipeline.zig`. Candidate references are imports at `howl-render/src/text/frame_preparer.zig:6`, `howl-render/src/session/text.zig:17`, and `libs.yaml:274`; the exact implementation slice is not worker-ready until `pipeline.zig` is read.

## Non-Goals

- Do not add a Zig embedding lane. Howl law says hosts use C ABI contracts and must not bypass with Zig-shaped convenience imports at `AGENTS.md:86` through `AGENTS.md:93`.
- Do not create umbrella runtime, manager, engine, controller, pipeline, queue, or `types.zig` owners. The ban is explicit at `AGENTS.md:114` and `project-memory.md:29` through `project-memory.md:31`.
- Do not preserve compatibility aliases when renaming wrong vocabulary. Project memory says ABI breakage is allowed and no compatibility shims or old-name aliases at `project-memory.md:195` through `project-memory.md:198`.
- Do not split host `main.zig` just because it is large. Current host app ownership is source-backed by `libs.yaml:27` through `libs.yaml:35`; a split needs an owner-true seam.
- Do not infer a VT near-redo as one broad implementation slice. Start with exact wrappers and FFI owner leaks.

## Open Questions

- Should the generated-looking C lane be enforced by a script or only by review gates? The build/test architecture is already marked fragmented at `project-memory.md:296` through `project-memory.md:308`, so adding a new gate may belong to that backlog.
- Should ABI layout assertions live in one `ffi.zig` per library or next to each owner-specific ABI adapter? Current VT centralizes them in `howl-vt/src/ffi.zig:12`; render has source-cell layout assertions in `howl-render/src/vt_surface.zig:136`.
- Is `howl-vt/src/screen.zig` intended to remain the monolithic screen owner, or should current subfiles under `howl-vt/src/screen/*` become stronger owners for mutation? This report read only the top of `screen.zig` through `howl-vt/src/screen.zig:300`.
- Is `runtime` acceptable as protocol vocabulary in VT functions such as `howl_vt_terminal_query_runtime_obligation` at `howl-vt/include/howl_vt.h:299`, or should it be renamed because project memory bans `runtime` owner vocabulary at `project-memory.md:29`? Proof missing: whether this is product ABI vocabulary already accepted by prior slices.
- Does render still need both token-based and handle-based submit APIs? Both are exported at `howl-render/src/libhowl_render.zig:24` through `howl-render/src/libhowl_render.zig:36`; proof missing: host call-site inventory and ABI product decision.
