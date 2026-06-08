# Render FT/HB Support State Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-render-support-state.txt`
- `reference-index.md`
- render font/support references listed in researcher session `ses_15dcb050bffeMTGZ3n5ktxW8eF`

Findings:

- The exact replacement noun is `FtHbSupport`.
- Exact typed consumer scope is `support.zig`, `session/text.zig`, `glyph_raster.zig`, and `support_test.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-render/src/text/font/ft_hb/support.zig`
  - `howl-render/src/session/text.zig`
  - `howl-render/src/text/font/ft_hb/glyph_raster.zig`
  - `howl-render/src/text/font/ft_hb/support_test.zig`
- Required shape:
  - rename only `pub const State = struct` to `pub const FtHbSupport = struct` in `support.zig`
  - update all owner-local type mentions in that file, including `init`, `deinit`, helper signatures, and `testing.gatherShapeRunInput`
  - update `session/text.zig` `text_state: text_support.State` and initializer call to `text_support.FtHbSupport`
  - update `glyph_raster.zig` `DeterministicFallbackContext.text_state` and initializer from `provider_mod.State` to `provider_mod.FtHbSupport`
  - update `support_test.zig` locals from `support.State` to `support.FtHbSupport`
  - keep file path `support.zig`, field name `text_state`, free-function names, fallback-path borrowing behavior, caches, FT/HB behavior, and public ABI unchanged
- Non-goals:
  - no file rename
  - no split into Ghostty-style `Library`/deferred-face/cache owners
  - no `text_state` field rename
  - no invalidation-policy change
  - no fallback-path ownership move
  - no FT/HB loading-policy change
  - no C ABI or FFI symbol change
  - no test-root move
  - no changes to `FallbackFontCount`, `max_fallback_fonts`, or their reexports
- Verification:
  - `python utils/hygene/style_scan.py "howl-render/src/text/font/ft_hb/support.zig" "howl-render/src/session/text.zig" "howl-render/src/text/font/ft_hb/glyph_raster.zig" "howl-render/src/text/font/ft_hb/support_test.zig"`
  - `zig build test && zig build check` in `howl-render`
  - grep gate: no `pub const State = struct` in `howl-render/src/text/font/ft_hb/support.zig`
  - grep gate: no `text_support.State` in `howl-render/src/session/text.zig`
  - grep gate: no `provider_mod.State` in `howl-render/src/text/font/ft_hb/glyph_raster.zig`
  - grep gate: no `support.State` in `howl-render/src/text/font/ft_hb/support_test.zig`
- Stop conditions:
  - stop if any typed consumer outside those four files appears
  - stop if reviewer wants a broader owner split instead of a rename-only bucket fix
  - stop if making `FtHbSupport` coherent requires renaming `text_state` or moving `support.zig`
  - stop if any public ABI, FFI export, or test-root wiring change becomes necessary
  - stop if Ghostty-backed pressure is interpreted as requiring immediate decomposition into smaller owners
