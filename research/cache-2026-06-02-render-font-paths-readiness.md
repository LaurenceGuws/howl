# Render Font Paths Readiness Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Readiness

`howl-render/src/text/font/paths.zig` with a dedicated font path owner is worker-ready if the slice is constrained to moving existing path lifetime/sync behavior, not changing font discovery, FreeType/HarfBuzz loading policy, ABI semantics, or invalidation policy.

## Current Facts

- `TextSessionConfig.font_path` is a borrowed primary path input.
- `TextSessionOwner` currently owns primary/fallback path storage.
- `TextSessionOwner.destroy()` frees those paths.
- `setFontPathBytes()` duplicates a primary path and treats null/empty as unset.
- `setFallbackFontPathPtrs()` validates count/null entries, duplicates C strings, stages, then adopts.
- Primary sync is currently `font_path -> config.font_path`.
- Fallback sync writes borrowed slices into `text_state.fallback_font_paths` and clears stale slots.
- `ft_hb.support.State` borrows fallback path slices; it does not own them.
- FT/HB opens primary from `config.font_path` and fallbacks from `state.fallback_font_paths`.
- Current invalidation does a full face/cache/atlas reset for font size and path changes.

## Reference Pressure

- Alacritty keeps font config separate from renderer-owned `GlyphCache`; `Display` owns glyph cache and resets it centrally.
- Alacritty `GlyphCache` owns resolved font keys, rasterizer, metrics, and glyph cache.
- Ghostty has explicit shared font grid/cache owners keyed by font config and explicit face loading from file paths.
- This supports a Howl path owner, but not a new font cache/discovery owner in this slice.

## Exact Owner Shape

Add `howl-render/src/text/font/paths.zig`.

Owner type: `FontPaths`.

Fields:

- `allocator: std.mem.Allocator`
- `primary: ?[:0]u8 = null`
- `fallbacks: std.ArrayList([:0]u8) = .empty`

Move into `paths.zig`:

- `pub const FallbackFontCount = u8`
- `pub const max_fallback_fonts: FallbackFontCount = 24`
- `pub fn fallbackFontCount(value: u32) ?FallbackFontCount`
- `pub fn fallbackFontLen(value: FallbackFontCount) u32`

Methods:

- `init(allocator: std.mem.Allocator) FontPaths`
- `deinit(self: *FontPaths) void`
- `setPrimaryBytes(self: *FontPaths, bytes: ?[]const u8) FontConfigError!void`
- `setOwnedPrimary(self: *FontPaths, owned: ?[:0]u8) void`
- `setFallbackPathPtrs(self: *FontPaths, raw_paths: []const ?[*]const u8) FontConfigError!void`
- `adoptFallbacks(self: *FontPaths, owned_paths: *std.ArrayList([:0]u8)) void`
- `syncPrimary(self: *const FontPaths, target: *?[:0]const u8) void`
- `syncFallbacks(self: *const FontPaths, paths: *[max_fallback_fonts]?[:0]const u8, len: *FallbackFontCount) void`

Error type:

- `pub const FontConfigError = error{ InvalidArgument, OutOfMemory };`

`paths.zig` must not import `session/text.zig`.

## Allowed Files

- Add `howl-render/src/text/font/paths.zig`.
- Edit `howl-render/src/session/text.zig`.
- Edit `howl-render/src/text/font/ft_hb/support.zig`.
- Edit `howl-render/src/ffi/text_session.zig`.
- Edit `howl-render/src/text/text.zig` only if needed to curate imports/tests through existing root.

## Tests

- Move/adapt existing path tests from `session/text.zig` into `paths.zig`.
- Required tests: primary owner sync; fallback owner sync with stale slot clearing; fallback overflow and null entry validation; staging ownership after adopt.
- Keep existing session-level behavior covered enough to prove `TextSessionOwner` delegates and still invalidates.

## Verification

- `zig build test -- "font paths"`.
- `zig build test -- "setFallbackFontPathPtrs rejects overflow and null entries"` if kept or renamed compatibility is needed.
- `zig build test -- "provider loads fallback face for symbol glyph with primary present"`.
- `zig build test --summary all`.

## Grep Gates

- No `font_path: ?[:0]u8` in `howl-render/src/session/text.zig`.
- No `fallback_font_paths: std.ArrayList` in `howl-render/src/session/text.zig`.
- No `freeOwnedFallbackFontPaths` in `howl-render/src/session/text.zig`.
- No `pub const FallbackFontCount` in `ft_hb/support.zig`.
- No `pub const max_fallback_fonts` in `ft_hb/support.zig`.
- Exports in `libhowl_render.zig` unchanged.
- No new `manager`, `engine`, `controller`, `utils`, `types.zig`.

## Stop Conditions

- Stop if `paths.zig` needs to import `session/text.zig`.
- Stop if the worker needs to decide new invalidation semantics, such as resize-loaded-faces versus reset-loaded-face.
- Stop if public C ABI headers or exported symbol names need to change.
- Stop if the cut expands into font discovery, font family/style config, glyph cache ownership, atlas ownership, or FT/HB face lifecycle redesign.
- Stop if tests require a new build/test root.
- Stop if import cycles require moving `TextSessionConfig` or broader font session contracts.
