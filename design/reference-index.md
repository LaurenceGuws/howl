# Reference Index

Owner: workspace root.

Purpose: explicit local reference index for Howl design and review work.

## Rules

- Use explicit paths from this index before searching the workspace blindly.
- Prefer the local cached corpus before asking external tools or looking elsewhere.
- If Howl is far from a target state, start from the biased reference set for that domain instead of
  reverse-engineering the answer from unrelated code.
- Prefer official docs over implementation spelunking when the official doc exists and answers the
  question.

## Search Caveat

The parent repo ignores child repos in `.gitignore`.

That means root-level `rg`, `fd`, and some glob-driven discovery can act incomplete or misleading
unless you point them at explicit child-repo or `utils/` paths.

Use explicit paths first.

## Golden Rule

If Howl's current state is far from a target state, default to this indexed reference set before
finding resources manually or looking for help elsewhere.

Examples:

- For Zig language migration questions, check the cached release notes before reading Zig stdlib
  source for clues.
- For terminal rendering correctness, check Kitty protocol and implementation references before
  guessing from local output.
- For style or hygiene rules, check TigerBeetle before improvising a local rule.

## Bias Map

- Speed and efficiency: Alacritty.
- Style and hygiene: TigerBeetle.
- Text rendering correctness: Kitty.
- Embedding standards: Ghostty.

## Primary Bible

### Speed And Efficiency

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/`

Use for:

- common-path render structure
- terminal frame preparation shape
- host-facing render cadence comparison

### Style And Hygiene

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/internals/docs.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Use for:

- code style law
- documentation hygiene
- architecture/process discipline

### Text Rendering Correctness

- `/home/home/personal/projects/howl/utils/dev_references/terminals/kitty/`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/`

Use for:

- text rendering behavior
- glyph generation expectations
- terminal protocol correctness for Kitty-owned extensions

### Embedding Standards

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/`

Use for:

- embedding surface expectations
- terminal host/runtime seam comparison
- app/runtime integration shape

## Official Docs Bias

Use official cached docs before reading upstream source when they answer the question directly.

Primary official paths:

- Zig release notes:
  - `/home/home/personal/projects/howl/utils/official_docs/ziglang.org/download/0.16.0/release-notes.html`
- Kitty protocol docs:
  - `/home/home/personal/projects/howl/utils/official_docs/kitty/`
- Xterm control sequences:
  - `/home/home/personal/projects/howl/utils/official_docs/xterm/ctlseqs.html.md`
  - `/home/home/personal/projects/howl/utils/official_docs/xterm/ctlseqs-contents.md`
- Android official docs cache:
  - `/home/home/personal/projects/howl/utils/official_docs/developer.android.com/`

## Secondary Reference Groups

Use these only when the primary bible for the domain is not enough:

- `/home/home/personal/projects/howl/utils/dev_references/text/`
- `/home/home/personal/projects/howl/utils/dev_references/fonts/`
- `/home/home/personal/projects/howl/utils/dev_references/rendering/`
- `/home/home/personal/projects/howl/utils/dev_references/platform/`
- `/home/home/personal/projects/howl/utils/dev_references/backends/`
- `/home/home/personal/projects/howl/utils/dev_references/sdlwiki_md/`
- `/home/home/personal/projects/howl/utils/dev_references/glfw_docs/`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/zig/`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/zls/`

## Current Non-Bible Groups

These exist in the corpus but are not first-choice references for Howl unless a task names them
explicitly:

- `/home/home/personal/projects/howl/utils/dev_references/editors/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/codex/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/contour/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/foot/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/hyper/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/iterm2/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/rio/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/st/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/tabby/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/termux-app/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/wezterm/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/windows_terminal/`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/xterm_snapshots/`

Do not grep these first out of habit.
