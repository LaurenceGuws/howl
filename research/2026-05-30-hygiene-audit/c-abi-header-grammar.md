# C ABI Header Grammar

Date: 2026-05-30

Owner: workspace root.

Purpose: define the exact generated-looking grammar for Howl public C ABI headers so
later header workers cannot invent order, comment style, wrapping, compatibility
aliases, or Zig-shaped host shortcuts.

## Source Pressure

- Howl law says the ABIs are the product and hosts embed `howl-pty`, `howl-vt`,
  `howl-render`, and vendor contracts through the C ABI boundary only:
  `AGENTS.md:9-14`, `AGENTS.md:86-93`.
- Howl law says public roots curate exports only and FFI translates contracts only:
  `AGENTS.md:107`, `AGENTS.md:110`.
- Howl law bans convenience runtimes, managers, controllers, compatibility aliases,
  and Zig-shaped host shortcuts: `AGENTS.md:73-75`, `AGENTS.md:114-116`.
- TigerBeetle requires exact naming, top-down order, comments that explain why/how,
  compile-time assertions for layout facts, and a hard 100-column line limit:
  `TIGER_STYLE.md:273-289`, `TIGER_STYLE.md:315-332`,
  `TIGER_STYLE.md:128-134`, `TIGER_STYLE.md:360-370`,
  `TIGER_STYLE.md:463-466`.
- TigerBeetle architecture pressure favors explicit limits and auditable boundaries:
  `ARCHITECTURE.md:189-222`, `ARCHITECTURE.md:408-423`.
- Researcher A found that PTY, VT, and render headers do not read as one small
  generated C lane, and proposed include guard, includes, opaque handles,
  status/limits, owner structs, and owner methods: `researcher-a.md:17-31`,
  `researcher-a.md:119-125`.
- Researcher B found inconsistent sectioning, root export shape, and bannered VT
  headers, and recommended one header convention with semantic comments only:
  `researcher-b.md:21-40`, `researcher-b.md:168-186`.
- Researcher C found handle, wrapping, banner, and enum inconsistencies and called
  for one C lane grammar with layout assertions paired near Zig C translators:
  `researcher-c.md:55-69`, `researcher-c.md:139-146`,
  `researcher-c.md:155-166`.
- The synthesis marks `Define C ABI Header Grammar` as the first slice because it
  gives later workers exact gates before touching product headers:
  `synthesis.md:108-148`.
- Roadmap Slice 1.1 requires this document, fixes the exact order, and forbids
  generation tooling or product header edits in this slice: `roadmap.md:44-88`.

## Header Grammar

Every public Howl C ABI header follows this order exactly:

1. Include guard.
2. C includes.
3. `extern "C"` block.
4. Opaque handles.
5. Limits/macros.
6. Status/result enums.
7. Product enums.
8. Structs.
9. Functions grouped by owner handle and operation order.

No section may move to make a local header look nicer. C declaration dependencies
are satisfied inside this order by moving dependent declarations later, not by
inventing a new section.

### Include Guard

- Use one guard per header: `HOWL_<PACKAGE>_H`.
- The guard opens on line 2 after the first `#ifndef` line and closes on the last
  line with `#endif`.
- The final `#endif` has no trailing banner comment.

Example:

```c
#ifndef HOWL_RENDER_H
#define HOWL_RENDER_H

...

#endif
```

### C Includes

- C standard includes immediately follow the guard.
- Includes are sorted by dependency need, not alphabetically when C type order
  requires otherwise.
- Include only headers required by the public declarations in that file.

Example:

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
```

### Extern C Block

- Open `extern "C"` immediately after C includes.
- All public declarations live inside the block.
- Close the block immediately before the include guard closes.

Example:

```c
#ifdef __cplusplus
extern "C" {
#endif

...

#ifdef __cplusplus
}
#endif
```

### Opaque Handles

Use one handle declaration style only:

```c
typedef struct HowlPtySessionOpaque *HowlPtySessionHandle;
```

Rules:

- The opaque struct name is `Howl<Package><Owner>Opaque`.
- The handle name is `Howl<Package><Owner>Handle`.
- Declare the struct and pointer typedef in one line.
- Do not define the opaque struct body in the public header.
- Do not add const-handle aliases, old-name typedefs, compatibility aliases, or
  alternate host-facing names.

### Limits And Macros

Use one macro/limit style only:

```c
#define HOWL_RENDER_FALLBACK_FONT_COUNT_MAX 8u
```

Rules:

- Macro names are uppercase and prefixed with `HOWL_<PACKAGE>_`.
- Numeric values carry an unsigned suffix when the C type is unsigned.
- Limits describe product capacity or ABI array bounds only.
- Function-like macros are banned from public ABI headers.
- Constants that belong to an enum must be enum values, not macros.

### Status And Result Enums

Use one status/result enum style only:

```c
typedef enum HowlPtyStatus {
    HOWL_PTY_STATUS_OK = 0,
    HOWL_PTY_STATUS_INVALID_ARGUMENT = 1,
    HOWL_PTY_STATUS_SYSTEM_ERROR = 2,
} HowlPtyStatus;
```

Rules:

- Status enums come before product enums.
- The enum tag and typedef name are identical.
- Values are explicitly numbered.
- Zero is the success, none, or invalid sentinel chosen by the contract.
- Names use `HOWL_<PACKAGE>_<STATUS_OWNER>_<VALUE>`.
- Do not use anonymous public ABI enums.
- Do not add compatibility alias values or old-name typedefs.

Result structs that pair a status with payload live in the struct section, not in
the enum section.

### Product Enums

Product enums follow status/result enums.

Rules:

- Product enums use the same tagged typedef style as status enums.
- Values are explicitly numbered whenever the value crosses the C ABI.
- Values are grouped by product noun, not by caller convenience.
- Do not encode Zig enum names or internal module names into C values.

### Structs

Rules:

- Structs are plain `typedef struct Name { ... } Name;` declarations.
- Fields appear in ABI layout order only.
- Field comments are allowed only for ABI consequence, lifetime, unit, or ownership.
- Struct names use public product nouns, not internal Zig file or owner shortcuts.
- Result structs follow the payload owner they report on when dependencies allow it.

Example:

```c
typedef struct HowlPtyReadResult {
    HowlPtyStatus status;
    size_t bytes_read;
} HowlPtyReadResult;
```

### Functions

Functions are grouped by owner handle, then by operation order:

1. Create/init/open.
2. Destroy/deinit/close.
3. Configure/resize/control.
4. Feed/write/progress/prepare.
5. Query/read/copy/take.
6. Ack/release/submit.

Rules:

- Each function name is `howl_<package>_<owner>_<verb>[_<object>]`.
- The owner handle parameter is first after output/result parameters, unless the
  function constructs that handle.
- Output pointers precede input spans only when the ABI contract requires C
  caller-owned storage to be established before use.
- Callbacks, if any are ever accepted by a later ABI slice, go last.
- No group banner is allowed. Grouping is visible from sorted function names and
  owner handle order.

Use one function prototype wrapping style under 100 columns:

```c
HowlVtStatus howl_vt_terminal_copy_surface(
    HowlVtTerminalHandle terminal,
    uint64_t snapshot_id,
    HowlVtSurfaceCell *cells,
    size_t cells_len,
    HowlVtSurfaceMetadata *metadata
);
```

Wrapping rules:

- If the full prototype exceeds 100 columns, put the opening parenthesis at the
  end of the first line.
- Put one parameter per line, indented by 4 spaces.
- Put the closing `);` on its own line.
- Do not align parameters into columns.
- Keep short prototypes on one line only when they fit under 100 columns.

## Comment Rule

Comments explain ABI consequence or lifetime only; ordering does navigation.

Allowed comments:

- Lifetime transfer, such as caller-owned memory, borrowed spans, retained spans,
  and release obligations.
- ABI consequence, such as snapshot invalidation, idempotent ack behavior, enum
  value permanence, or layout coupling.
- Units for primitive numeric fields when the field name cannot carry the unit.

Banned comments:

- Header banners.
- Numbered sections.
- Table-of-contents prose.
- Comments that repeat the declaration name.
- One-off comments that compensate for bad order.

Header banners are banned unless future tooling generates them consistently for
all public C ABI headers from one source. This slice does not add that tooling.

## ABI Layout Assertions And FFI Translators

Every public C declaration that has layout, numeric, ownership, or lifetime
consequences must have a matching Zig-side proof in the C ABI translator lane.

Pairing rules:

- Header structs pair with Zig `extern struct` or imported C declarations and
  compile-time assertions for size, alignment, field offsets, and integer widths.
- Header enum values pair with compile-time assertions that the Zig translator's
  numeric values match the C ABI values.
- Header limits/macros pair with Zig constants and compile-time assertions for
  capacity relationships.
- Header handles pair with FFI pointer translation helpers that assert non-null
  handles at the boundary before delegating to owner code.
- FFI translators map C status/result contracts and pointer/span ownership only.
  They do not own PTY, VT, render, selection, text, surface, or host policy.
- Owner mutation remains behind owner APIs. The translator calls the owner; it
  does not become the owner.

Placement rules:

- Keep layout assertions adjacent to the translator declarations they prove.
- If render uses owner-specific ABI adapters later, the assertions move with the
  adapter, not into a generic `types.zig` bucket.
- Do not introduce `types.zig`, `manager`, `controller`, `engine`, `runtime`,
  `pipeline`, `queue`, or `api` owner files to hold ABI facts.

## Compatibility And Host Lane Rules

- No compatibility aliases.
- No old-name typedefs.
- No duplicate enum names for old vocabulary.
- No macro aliases for renamed symbols.
- No Zig-shaped host shortcut.
- No Ghostty-style broad Zig module lane for host integration.
- Hosts consume the C ABI contracts. If a host needs a new fact, sharpen the C
  ABI contract instead of exporting an internal Zig owner.

## Review Checklist

Use this checklist for later header implementation slices:

- The header follows the exact order: include guard, C includes, `extern "C"`,
  opaque handles, limits/macros, status/result enums, product enums, structs,
  functions grouped by owner handle and operation order.
- Every handle uses `typedef struct Howl<Package><Owner>Opaque *...Handle;`.
- Every public enum is a tagged typedef with explicit numeric values.
- Every limit macro is uppercase, package-prefixed, and product-capacity scoped.
- Every wrapped function prototype is under 100 columns and uses one parameter
  per line.
- Comments explain ABI consequence or lifetime only.
- No header banners, numbered sections, or one-off table-of-contents comments
  remain.
- No compatibility alias, old-name typedef, macro alias, or duplicate enum value
  was introduced.
- No Zig-shaped host shortcut or Ghostty-style broad Zig module lane was added.
- C declaration dependencies still compile in C and C++.
- Zig ABI layout assertions prove changed order, values, sizes, alignments, and
  field offsets.
- FFI translators translate contracts only and delegate owner mutation.
- Diffs are order, comments, and wrapping only unless a later slice explicitly
  promotes an ABI break.

## Grep Gates

Use these gates for later implementation slices:

```sh
awk 'length($0)>100 {print FILENAME ":" FNR ":" $0}' howl-*/include/*.h
rg '/\* -{5,}|/\* [0-9]+\.|Shell input enums|Owned prepared-surface' howl-*/include/*.h
rg 'typedef struct Howl[A-Za-z0-9]+Opaque \*Howl[A-Za-z0-9]+Handle' howl-*/include/*.h
rg 'typedef enum Howl|typedef struct Howl|howl_[a-z0-9_]+\(' howl-*/include/*.h
rg 'compatibility alias|old-name typedef|Zig-shaped host shortcut' howl-*/include/*.h
rg '@offsetOf|@sizeOf|@alignOf|comptime' howl-*/src
```

Expected results:

- The long-line gate prints nothing.
- The banner/prose gate prints nothing unless a future generated-doc tool emits
  identical banners across every public header.
- The handle, enum, struct, and function gates support manual order review.
- The compatibility and Zig-shaped shortcut gate prints nothing in headers.
- The Zig assertion gate supports review that header declarations are paired with
  layout assertions and translators.

## Non-Goals

- Do not edit `howl-pty/include/howl_pty.h` in this slice.
- Do not edit `howl-vt/include/howl_vt.h` in this slice.
- Do not edit `howl-render/include/howl_render.h` in this slice.
- Do not edit Zig source in this slice.
- Do not change C symbols, numeric values, struct layout, or behavior.
- Do not add generation tooling.
- Do not resolve build/test architecture.
- Do not decide render translator file movement.
- Do not decide VT bucket cleanup.
- Do not rename product vocabulary.

## Stop Conditions

- Stop if a later worker cannot satisfy C declaration dependencies within the
  grammar order without changing an exported contract.
- Stop if applying this grammar appears to require a symbol rename, enum value
  change, struct field reorder, or behavior change.
- Stop if the work needs generation tooling or build/test architecture changes.
- Stop if a header worker tries to preserve banners instead of making order do
  navigation.
- Stop if a worker adds compatibility aliases or old-name typedefs.
- Stop if a worker adds a Zig-shaped host shortcut or Ghostty-style broad Zig
  module lane instead of sharpening the C ABI contract.
