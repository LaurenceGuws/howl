# VT Locator Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-vt-locator.txt`
- `reference-index.md`
- `howl-vt/src/control/locator.zig`
- `howl-vt/src/host/state.zig`
- `howl-vt/src/host/apply.zig`
- `howl-vt/src/control/report.zig`
- `howl-vt/src/input/encode.zig`
- xterm locator terminology and related research listed in researcher session `ses_15e01e013ffeMn994dBxUf091O`

Findings:

- The exact owner noun is `Locator`.
- Only typed consumer is `howl-vt/src/host/state.zig`; the other nearby files call free functions only.

Worker-ready contract:

- Allowed files:
  - `howl-vt/src/control/locator.zig`
  - `howl-vt/src/host/state.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const Locator = struct` in `howl-vt/src/control/locator.zig`
  - rename all receiver and helper type uses in that file from `State` to `Locator`
  - update `howl-vt/src/host/state.zig` field type from `LocatorNs.State` to `LocatorNs.Locator`
  - keep the host field name exactly `locator`
  - keep all free-function names unchanged
  - keep all fields unchanged
  - keep locator reporting configuration, retained last locator position/button state, report formatting, event handling, and behavior unchanged
  - do not add aliases
- Non-goals:
  - no edits to `howl-vt/src/host/apply.zig`, `howl-vt/src/control/report.zig`, or `howl-vt/src/input/encode.zig`
  - no rename of `vt.host.locator`
  - no split into smaller locator structs
  - no locator protocol behavior changes
  - no broader `control/report.zig` cleanup
- Verification:
  - `python utils/hygene/style_scan.py "howl-vt/src/control/locator.zig" "howl-vt/src/host/state.zig"`
  - `zig build test && zig build check` in `howl-vt`
  - grep gate: no `pub const State = struct` in `howl-vt/src/control/locator.zig`
  - grep gate: no `LocatorNs.State` in `howl-vt/src/host/state.zig`
  - grep gate: `pub const Locator = struct` appears in `howl-vt/src/control/locator.zig`
- Stop conditions:
  - stop if the worker needs to edit any file beyond the two allowed files
  - stop if concurrent tree changes introduce new type consumers beyond `howl-vt/src/host/state.zig`
  - stop if review demands a noun narrower than `Locator`
  - stop if the rename turns into a behavior slice or a struct-split slice
