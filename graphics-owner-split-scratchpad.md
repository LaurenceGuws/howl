# Graphics Owner Split Scratchpad

Owner: workspace root.

Source:

- `AGENTS.md`
- `loop.txt`
- `reference-index.md`
- `kitty-graphics-host-regression-design.md`
- `howl-linux-host/src/terminal/vt/surface.zig`
- `howl-render/src/frame/queue.zig`
- `howl-render/src/frame/surface_text.zig`
- `howl-render/src/frame/surface_buffer.zig`
- `howl-render/src/frame/graphics_viewport.zig`
- `howl-vt/src/kitty/graphics.zig`
- Kitty protocol docs under `utils/official_docs/kitty/`
- Ghostty image/render/runtime references
- TigerBeetle style and architecture references
- three independent research passes:
  - Ghostty-first
  - Kitty-first
  - Howl-first

Purpose:

- Record the owner-split verdict after the three-agent research round.
- Separate spec-required text coupling from suspicious graphics ownership coupling.
- Define the smallest honest next graphics question.

## Verdict

- Mixed.
- No, Howl did not literally turn image rendering into glyph rendering.
- Yes, Howl did let too much graphics preparation ownership slide into the text-frame owner.

## What Is Justified

- Kitty Unicode placeholder mode requires text-cell coupling.
- Placeholder discovery must look at cells.
- Placeholder codepoints must be suppressed from normal text shaping.
- One coherent snapshot carrying text plus graphics state is acceptable.
- Final composition can still layer graphics below background, below text, and above text.

## What Is Suspicious

- `howl-render/src/frame/surface_text.zig` owns:
  - graphics payload decode
  - graphics raster cache
  - graphics raster binding
  - placeholder run extraction
- `surface_text` is effectively both the text owner and the graphics-prepare owner.
- Placeholder knowledge is duplicated across VT and render.
- Graphics payload state is carried and compared as part of the text publication object.

## Current Owner Map

### VT Owner

- `howl-vt/src/kitty/graphics.zig`

Owns:

- Kitty image state
- placements
- virtual placements
- relative parent rules
- scroll consequences
- deletion semantics
- placeholder-parent anchoring against screen text

### Host Snapshot Bridge

- `howl-linux-host/src/terminal/vt/surface.zig`

Owns:

- one coherent publish seam from VT to render surface input

### Render Publication State

- `howl-render/src/frame/queue.zig`
- `howl-render/src/frame/surface_text_ffi.zig`

Owns:

- retained publication stream
- prepare/submit damage classification
- storage of text and graphics publication state together

### Render Preparation

- `howl-render/src/frame/graphics_viewport.zig`
  - placement viewport math and clipping
- `howl-render/src/frame/surface_text.zig`
  - text shaping
  - graphics decode/cache/bind
  - placeholder extraction and prep
- `howl-render/src/frame/input.zig`
  - placeholder suppression from text shaping

### Final Composition

- `howl-render/src/frame/surface_buffer.zig`

Owns:

- final layer composition of text and graphics pixels

## Reference Verdict

### Kitty

- Placeholder detection is text-coupled by spec.
- That does not imply image decode/cache/bind must live inside the text owner.

### Ghostty

- Keeps terminal image state under dedicated Kitty/image owners.
- Keeps renderer image state under dedicated renderer/image owners.
- Does not bury the whole graphics prep path inside text shaping ownership.

### TigerBeetle

- The current shape looks like working debt rather than final owner-honest structure.
- The suspicious part is convenience coupling, not the spec-required placeholder seam.

## Smallest Honest Next Question

- Can Howl keep placeholder detection tied to cells, while moving image decode/cache/bind out of `howl-render/src/frame/surface_text.zig` into a dedicated render-owned graphics preparer or scene, without changing the VT snapshot contract?

## Constraints For The Next Loop

- Do not break the VT snapshot contract casually.
- Do not invent a fake umbrella runtime/render layer.
- Do not pretend placeholder detection can be entirely separated from text cells; Kitty forbids that shortcut.
- Move only the suspicious ownership:
  - image decode
  - raster cache
  - raster binding
  - graphics-prepare state

## Likely Next Sprint Order

### 1. Research-only

- derive the smallest owner split that preserves:
  - VT ownership of Kitty semantics
  - render ownership of graphics raster prep
  - text ownership of text shaping only

### 2. Code

- split graphics decode/cache/bind out of `surface_text.zig`

### 3. Proof

- prove the real app-icon replay still survives publish -> prepare -> render with the new owner split

## Stop Line Before Code

- Before code starts, we must know exactly which functions and state leave `surface_text.zig`, and which placeholder responsibilities must stay coupled to cell input by spec.
