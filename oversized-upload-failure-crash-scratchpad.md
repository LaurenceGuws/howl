# Oversized Upload Failure Crash Scratchpad

Owner: workspace root.

Purpose:

- Track the remaining real-app crash after oversized Kitty graphics upload failure.
- Keep this as bug isolation work, not a new feature-design track.

## Known Facts

- Full host app repro still ends with `free(): double free detected in tcache 2`.
- Repro logs include:
  - `stage=transport-vt-feed-failed status=-5 chunk_len=4095`
  - `stage=active-tab-failed lifecycle=failed alive=true`
- VT-only oversized chunked upload failure test is deinit-safe.
- Therefore the remaining corruption is not currently reproduced by pure VT teardown alone.

## Already Fixed / Ruled Out

- `storeFrameOwned()` ownership-transfer bug was fixed.
- Upload ownership is severed immediately after `toOwnedSlice(...)`.
- Temporary broad teardown tracing was removed.
- This is not a reason to reopen the runtime-obligation design work.

## Current Suspect Area

- Host-side failure/unwind after VT feed failure.
- Later free-site detection of earlier heap corruption.
- Any host-owned resource path that only runs in the full app lifecycle after `HostTabFailed`.

## Narrow Next Question

- After `transport-vt-feed-failed` and before process exit, which host teardown path frees memory that still depends on the failed terminal/tab state?

## Next Promotion Bias

- Promote only one isolation target.
- Prefer a narrow host-side repro or teardown proof over more VT theory.
