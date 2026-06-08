# Render Sprite Resource Results Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-render-sprite-resource-results.txt`
- `reference-index.md`
- render sprite-resource references listed in researcher session `ses_15dc0161cffedWeufiXMO65a34`

Findings:

- Exact replacement names are:
  - `Result` -> `ResourceAllocation`
  - `AtlasResult` -> `AtlasPlacement`
- Rename scope is owner-local to `howl-render/src/prepared/sprite_resource_store.zig` only.

Worker-ready contract:

- Allowed files:
  - `howl-render/src/prepared/sprite_resource_store.zig`
- Required shape:
  - rename `pub const Result = struct` to `pub const ResourceAllocation = struct`
  - keep fields `resource` and `lifetime` unchanged
  - keep nested enum `Lifetime` and its cases unchanged
  - rename `pub const AtlasResult = struct` to `pub const AtlasPlacement = struct`
  - keep fields `resource`, `rect`, `created`, and `uploaded` unchanged
  - update only owner-local references in the same file
  - keep `resourceFor` and `atlasRegionFor` names unchanged
  - keep behavior unchanged
- Non-goals:
  - no edits outside `sprite_resource_store.zig`
  - no renaming of `resourceFor` or `atlasRegionFor`
  - no field renames
  - no enum-case changes
  - no atlas/store/emitter redesign
  - no C ABI changes
  - no new tests
- Verification:
  - `python utils/hygene/style_scan.py "howl-render/src/prepared/sprite_resource_store.zig"`
  - `zig build test && zig build check` in `howl-render`
  - grep gate: no `pub const Result = struct` in `howl-render/src/prepared/sprite_resource_store.zig`
  - grep gate: no `pub const AtlasResult = struct` in `howl-render/src/prepared/sprite_resource_store.zig`
  - grep gate: no `SpriteResourceStore.Result` in `howl-render/src`
  - grep gate: no `SpriteResourceStore.AtlasResult` in `howl-render/src`
  - grep gate: `pub const ResourceAllocation = struct` exists in `howl-render/src/prepared/sprite_resource_store.zig`
  - grep gate: `pub const AtlasPlacement = struct` exists in `howl-render/src/prepared/sprite_resource_store.zig`
- Stop conditions:
  - stop if any file outside `sprite_resource_store.zig` needs editing
  - stop if review demands field renames or function renames
  - stop if any public/exported dependency on the old nested type names appears
  - stop if the slice broadens into emitter/resource protocol redesign
