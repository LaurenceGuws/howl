# Host Links Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-links.txt`
- `reference-index.md`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/input.zig`
- linked research/docs listed in researcher session `ses_15de1cd91ffeuHz8jlbzgPlicT`

Findings:

- The exact owner noun is `Links`.
- Only direct typed consumer is `howl-linux-host/src/terminal/context.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/terminal/links.zig`
  - `howl-linux-host/src/terminal/context.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const Links = struct` in `howl-linux-host/src/terminal/links.zig`
  - update all receivers and field type references in that file to `Links` only as needed by the local type name
  - update `Context.links` field type from `terminal_links.State` to `terminal_links.Links` in `howl-linux-host/src/terminal/context.zig`
  - keep the field name `links` unchanged in `Context`
  - keep hover clearing, cursor sync, hover decoration publication, open-on-ctrl-click, and context publish/deinit use unchanged
- Non-goals:
  - no rename of the `links` field in `Context`
  - no rename of functions like `handleMouse`, `clearHoveredLink`, or `hoverDecoration`
  - no movement of `hover_publish_pending` into another owner
  - no redesign of hyperlink lookup, hover policy, cursor policy, or URL opening
  - no edits to `terminal/input.zig`, `terminal/context_test.zig`, `terminal/selection.zig`, or `terminal/scrollbar.zig`
  - no new tests in this slice
- Verification:
  - `python utils/hygene/style_scan.py "howl-linux-host/src/terminal/links.zig" "howl-linux-host/src/terminal/context.zig"`
  - `zig build test && zig build check` in `howl-linux-host`
  - grep gate: no `pub const State = struct` in `howl-linux-host/src/terminal/links.zig`
  - grep gate: no `terminal_links.State` in `howl-linux-host/src/terminal/context.zig`
- Stop conditions:
  - stop if any file beyond `links.zig` and `context.zig` needs editing
  - stop if the rename exposes a requirement to split `hover_publish_pending` out of `Links`
  - stop if worker pressure shifts from noun correction to ownership movement, API change, or behavior change
  - stop if build/test failure is caused by broader pre-existing host link ownership debt rather than the direct rename
