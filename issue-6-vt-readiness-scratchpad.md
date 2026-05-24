# Issue 6 VT Readiness Scratchpad

Owner: workspace root.

Parent:

- `issue-6-scratchpad.md`

Purpose:

- Pressure `howl-vt` from every remaining graphics angle until VT is fully ready and no longer the hidden blocker for later Issue 6 work.

Rule:

- Challenge every next step the same way:
  - is this truly VT-owned?
  - is the current VT ABI/surface already sufficient?
  - if not, what exact VT truth is missing?
  - if yes, stop pushing VT and move up-stack

## VT Ready Means

- VT owns all retained graphics truth for the chosen protocol subset.
- VT exports that truth honestly through the product ABI.
- Host/render do not need to guess around missing VT facts.
- Remaining blockers are not secretly VT-surface or VT-lifecycle bugs.

## Already Landed In VT

- implicit destination extent truth
- resolved destination pixel edges and grid extent export
- clipping from resolved destination truth
- relative placement truth
- parent lookup / cycle rejection / depth bound / parent-tied placement lifetime

## Remaining VT Angles To Challenge

### 1. Placeholder Cell ABI Truth

- Question:
  - can placeholder/virtual placement work be done honestly with the current surface cell ABI?
- Current answer:
  - no
- Exact suspected VT blocker:
  - surface ABI drops combining-sequence truth needed for Kitty placeholder cells
- Files:
  - `howl-vt/src/screen/cell.zig`
  - `howl-vt/src/ffi.zig`
  - `howl-vt/include/howl_vt.h`

### 2. Placeholder Resolution Ownership

- Question:
  - once placeholder cell truth exists, what exact part stays VT-owned versus render-owned?
- VT should own:
  - placeholder identification truth
  - mapping from placeholder text cells to retained graphics prototypes
  - lifecycle consequences of placeholder placements
- VT must not own:
  - final draw batching or backend realization

### 3. Animation / Frame Publication Truth

- Question:
  - is current frame state and frame selection truth fully VT-owned and exportable yet?
- Challenge:
  - does current ABI expose enough frame/publication truth for honest later animation work?
  - if not, what exact frame truth is missing from VT?

### 4. Non-`t=d` Media Truth

- Question:
  - what parts of alternate media types are VT protocol truth versus host/render policy?

### 5. Compression Boundary Truth

- Question:
  - is compression a VT protocol truth extension only, or does it require a wider payload contract change?

## Sequential VT Queue

1. `Surface Cell Combining Truth`
2. `Placeholder Cell ABI Truth`
3. `Placeholder Resolution Ownership`
4. `Animation / Frame Publication Truth`
5. `Non-\`t=d\` Media Truth`
6. `Compression Boundary Truth`

## Promoted Next VT Blocker

`Surface Cell Combining Truth`

Why this tightened first:

- placeholder cell ABI truth is not code-ready yet
- the deeper VT blocker is that VT cell storage and the C surface ABI cannot retain/export the full combining sequence Kitty placeholder cells require

Exact blocker:

- `howl-vt/src/screen/cell.zig` stores only `combining_len` plus `combining: [2]u32`
- Kitty placeholder decoding uses up to 3 combining diacritics on the placeholder cell:
  - row
  - column
  - optional image-id high byte
- `howl-vt/src/ffi.zig` / `howl-vt/include/howl_vt.h` export no combining-sequence payload at all

Immediate next question:

- What is the smallest VT-owned cell storage and C ABI shape that can retain/export the full placeholder combining sequence without guessing?

Immediate next files/references:

- `utils/official_docs/kitty/graphics-protocol.md` lines `956-1207`
- `utils/dev_references/terminals/kitty/kitty/screen.c` lines `3439-3497`
- `utils/dev_references/terminals/kitty/kitty/graphics.c` lines `888-1029` and `1062-1152`
- `utils/dev_references/terminals/kitty/kitty/graphics.h`
- `utils/dev_references/terminals/ghostty/src/terminal/c/kitty_graphics.zig`
- `utils/dev_references/terminals/ghostty/include/ghostty/vt/kitty_graphics.h`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `howl-vt/src/screen/cell.zig`
- `howl-vt/src/ffi.zig`
- `howl-vt/include/howl_vt.h`

## Stop Conditions

- Stop pushing VT when the next blocker is not actually VT-owned.
- Stop if the current ABI/surface already has enough truth and the missing piece is render/host behavior.
- Stop if the next item needs a smaller research split before code.
