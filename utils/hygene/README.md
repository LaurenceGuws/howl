# utils/hygene

Local hygiene tooling for Howl handover gates.

## `architecture_guard.sh`

Run the guard against one or more repos from the workspace root or from inside `utils/hygene`:

```bash
./utils/hygene/architecture_guard.sh howl-render-core howl-render-gl howl-sdl-host
```

The guard checks:

- `//!` file headers in `src/**/*.zig`
- source filename shape in `src/` (`uppercase` and `-` are rejected)
- new Zig test names for milestone/ticket labels
- compatibility patterns: `compat[^ib]`, `fallback`, `workaround`, `shim`

Expected output:

- one `PASS` or `FAIL` line per repo
- a final `architecture_guard: PASS` or `architecture_guard: FAIL (...)` summary line

Exit codes:

- `0` means the guard found no violations.
- `1` means one or more policy violations were found.
- `2` means usage or configuration error.

## Legacy exemptions

`architecture_guard.allowlist` is a scoped exemption file for legacy test-name labels.
Keep it empty unless a repo needs a documented temporary exemption.
Each line uses:

```text
<repo-relative-file-regex>|<test-name-regex>
```

The exemption file is local-only and is not a CI configuration file.
