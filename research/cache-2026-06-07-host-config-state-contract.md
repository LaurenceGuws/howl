# Host Config State Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-config-state.txt`
- `reference-index.md`
- host config and Alacritty config references listed in researcher session `ses_15dcb0d18ffeWC3tbiUQ0deQ8G`

Findings:

- The exact replacement noun is `UiConfig`.
- The exact typed consumer scope is `config.zig`, `main.zig`, and `app/processor.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/config/config.zig`
  - `howl-linux-host/src/main.zig`
  - `howl-linux-host/src/app/processor.zig`
- Required shape:
  - rename only `pub const State = struct` to `pub const UiConfig = struct` in `howl-linux-host/src/config/config.zig`
  - update `load`, `deinit`, and `applyProcessOverrides` signatures/receivers to use `UiConfig`
  - update the only live consumers from `Config.State` to `Config.UiConfig` in `main.zig` and `app/processor.zig`
  - keep file path, module import name `Config`, field layout (`term`, `window`, `tab_bar`), loader behavior, override behavior, and child owner nouns unchanged
- Non-goals:
  - no rename of the module import alias `Config`
  - no rename of child owners `terminal.zig::Config`, `tab_bar.zig::Config`, or `window.zig::Window`
  - no config schema changes
  - no loader/error-policy changes
  - no config-folder reshuffle
  - no new aliases or compatibility typedefs
  - no edits to `host_test_root.zig` or unrelated config consumers
- Verification:
  - `python utils/hygene/style_scan.py "howl-linux-host/src/config/config.zig" "howl-linux-host/src/main.zig" "howl-linux-host/src/app/processor.zig"`
  - `zig build test && zig build check` in `howl-linux-host`
  - grep gate: no `pub const State = struct` in `howl-linux-host/src/config/config.zig`
  - grep gate: `pub const UiConfig = struct` appears in `howl-linux-host/src/config/config.zig`
  - grep gate: no `Config.State` in `howl-linux-host/src/main.zig`
  - grep gate: no `Config.State` in `howl-linux-host/src/app/processor.zig`
- Stop conditions:
  - stop if any current-tree consumer of `Config.State` exists outside the three allowed files
  - stop if the worker needs to rename the module alias `Config` or any child config owner to make the cut compile
  - stop if review demands a broader host config redesign rather than this rename-sized owner correction
  - stop if Alacritty-backed `UiConfig` pressure is overridden by a user/orchestrator requirement for a different host config boundary
