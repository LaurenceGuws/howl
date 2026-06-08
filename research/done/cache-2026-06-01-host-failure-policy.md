# Host Failure Policy Research Cache

## Date

2026-06-01

## Sources Read

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `/home/home/personal/projects/howl/howl-linux-host/src/**/*.zig` scan for `catch return`, `catch unreachable`, boolean failure returns, `failure_count`, `unsupported`, `std.debug.print`, and `std.debug.assert` patterns.
- Source excerpts read from:
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/window/present.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/window/window.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`

## Question

Classify Linux host failure handling into programmer/ABI invariant violations that should crash/assert, operating errors that should be handled, and unknowns requiring reference or API proof. Include exact source-backed examples and identify readiness constraints for planning.

## TigerBeetle Failure Policy Facts

- `TIGER_STYLE.md:104-107`: Assertions detect programmer errors; operating errors are expected and must be handled; corrupt code should crash.
- `TIGER_STYLE.md:109-113`: Function arguments, return values, preconditions, postconditions, and invariants must be asserted.
- `TIGER_STYLE.md:136-140`: Assert positive expected space and negative unexpected space; invalid-boundary transitions are where bugs hide.
- `TIGER_STYLE.md:213-219`: All errors must be handled; incorrect handling of non-fatal errors causes catastrophic failures.
- `TIGER_STYLE.md:96-100`: Everything needs explicit bounds; fail fast on bound violations.
- `TIGER_STYLE.md:426-429`: Simpler return types reduce call-site dimensionality; boolean failure returns need strong justification when they collapse failure classes.
- `ARCHITECTURE.md:189-222`: Static allocation and explicit limits force every resource/failure bound to be known rather than discovered by unbounded growth.
- `ARCHITECTURE.md:281-307`: Determinism simplifies error handling only when contracts are explicit and physical/logical paths are controlled.

## Programmer/ABI Invariant Findings

- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:590-600`: `syncSurfaceLayout()` asserts renderer geometry status, cell size equality, and non-zero geometry epoch after syncing a trusted text session. This is correct invariant treatment.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:603-606`: `workState()` asserts `howl_render_text_session_work_state()` returns `HOWL_RENDER_CALL_OK`. Correct if the text session handle is trusted and initialized.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:615-619`: `notePresentSubmitted()` asserts non-zero snapshot/token and no existing in-flight present. Correct owner-state invariant.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:679-733`: Submit state maps stale/needs-prepare/failed outcomes, then asserts non-zero rendered host surface fields at `723-725`. Correct postcondition handling for successful render.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:835-849`: `acceptPrepared()` handles describe failure, then asserts prepared `snapshot_seq`, `dirty_epoch`, and `geometry_epoch` match the request and publish status is OK at `843-847`. Correct if the prepared handle comes from the same renderer ABI.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig:87-94`: `commitVtSurface()` non-OK status panics with detailed state. Correct crash behavior for renderer rejection after host-built/reserved VT surface commit.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:1216-1219`: `notePreparedStep()` asserts work state must have submit or present pending after preparation. Correct internal state invariant.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:1428-1481`: `initVt()`, `deinitVt()`, and `assertRenderInit()` assert positive geometry/font inputs and non-null handles. Correct precondition treatment.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:111-129`: Compile-time and runtime transport limit assertions prove bounded work before pumping.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:141-148`: Transport read loop asserts chunk/backlog bounds after each read.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:164-183`: Transport post-loop assertions prove bounded reads, backlog, and fed bytes.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:195-208`: `transportForceThreshold()` and `transportReadRemaining()` assert threshold and remaining-byte preconditions.
- `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:275-278`: String-array config fill asserts loop index bound while writing allocated slots.
- `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:306-313`: Z-string array config fill asserts loop index bound while writing allocated slots.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/pacing.zig:63`: `divCeil(..., std.time.ns_per_ms) catch unreachable` is likely correct because the divisor is a non-zero constant. This needs only local proof if retained.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:1916`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:1922`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:1932`: `std.testing.expect... catch unreachable` occurs in test/fake callbacks, not production path.

## Operating Error Findings

- `/home/home/personal/projects/howl/howl-linux-host/src/window/window.zig:183-185`: Public `setTitle()` drops allocation failure from `setTitleWith()`. Operating error currently handled by preserving the old title, but silent degradation is not documented.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/window.zig:197-204`: `setTitleWith()` allocates a Z string and returns `!bool`. Allocation failure is a real operating error.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/window.zig:268-277`: Clipboard get/set allocation and SDL failures return `!?[]u8` / `bool`. These are operating errors at host/platform boundary.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/window.zig:297-300`: `openUrl()` allocation / SDL failure returns `false`. Operating error.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/present.zig:447-448`: Present-proof texture pixel allocation returns empty stats on OOM. Operating diagnostic failure.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/present.zig:461-462`: Framebuffer observation allocation returns empty observation on OOM. Operating diagnostic failure.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/present.zig:497-498`: `rgbaLen()` overflow returns `null`. Operating/defensive bound for external GL dimensions.
- `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig:214-218`: `/proc` sample read failure logs and skips the sample. Operating error handled.
- `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig:303-307`: Invalid task directory names are skipped with `catch continue`; `/proc` races are expected operating conditions.
- `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig:398-405`: Per-thread formatting failure is skipped in diagnostic logging. Operating diagnostic path.
- `/home/home/personal/projects/howl/howl-linux-host/src/stress/ascii_rain_stress.zig:70-71`: Stress cleanup write/flush errors are ignored. Operating cleanup path, intentionally silent unless stress tools require diagnostics.
- `/home/home/personal/projects/howl/howl-linux-host/src/stress/visual_rain_stress.zig:78-79`: Stress cleanup write/flush errors are ignored. Operating cleanup path, intentionally silent unless stress tools require diagnostics.
- `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:91`: CLI parse errors are switched explicitly. Operating/user input error.
- `/home/home/personal/projects/howl/howl-linux-host/src/main.zig:891`: Clipboard get failure is ignored. Operating failure, likely acceptable for paste polling but needs UX policy proof if planning changes.

## Unknowns Needing Proof

- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:82-121`: `RenderSurfaceSubmitDiagnostics` has many failure and unsupported counters. It records failure classes but does not prove whether they are operating conditions or ABI bugs.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:564-571`: Prepare failure logging increments a counter and continues. Needs renderer API proof that prepare failures are recoverable host-runtime conditions.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:867-887`: Submit failure logging increments a counter and continues. Needs renderer API proof distinguishing stale/needs-prepare from true ABI failure.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:919-1188`: Render-surface diagnostics print failure counters and continue. Needs proof for each printed failure class.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:616-657`: `ContextSubmitBackend.upload()` returns `false` for resource realization/upload failure and resets host texture size. GL/resource errors may be operating; invalid sidecar/resource-plan failures may be ABI bugs.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:659-719`: Render-surface command shape selection maps unsupported shapes to counters/failure. If renderer is required to emit supported shapes, this should be invariant failure; if host intentionally supports only a subset, ABI must say so.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:722-759`: `recordUnsupportedRenderSurfaceShape()` and `recordRenderSurfaceNoSidecar()` bucket unsupported/invalid/null/call-failed statuses. Each bucket needs contract proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:525-546`: Probe statuses mix call failures, span invalid, unsupported, invalid resource, and invalid upload. These are not policy-classified at type level.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1016-1152`: Resource-plan validation returns `.unsupported_*` / `.invalid_*` statuses. Unknown whether this validates trusted renderer output or defensive external C ABI memory.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1171-1336`: Software-surface validation returns `.unsupported_*` / `.invalid_*` statuses. Unknown whether invalid data is possible from Howl-owned renderer or only from hostile/external ABI data.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1089`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1241`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1294-1303`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1436-1454`, `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig:1478-1483`: Arithmetic overflow maps to invalid upload/false/null. Safe defensive validation, but may hide invariant failures if ABI bounds already prove overflow impossible.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:88-97`: `FailureBucket` mixes invalid spans, invalid order, unsupported format, tombstone reuse, capacity, and GL error into one enum. Needs policy split.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:117-124`: `realizeSurface()` increments `failure_count` on all failure classes. Needs proof that all failures are recoverable.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:193-201`: GL sample errors are handled as failures. Likely operating, but must be separated from ABI invalidity.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:204-268`: Surface transition validation returns `null` for invalid spans/order/uploads/resources. Needs proof whether this is defensive ABI validation or should assert against trusted renderer output.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:316-340`: `noteCreate()` / `noteUpload()` return buckets/booleans for unsupported format, tombstone reuse, capacity, upload bounds. Mixed policy.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:349-425`: Texture create/upload failures return `false`; includes tombstone reuse, GL generation failure, invalid GL format, missing slot/resource. Mixed ABI and operating classes.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:518-533`: `recordFailure()` records all buckets uniformly. Needs proof before planning policy changes.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:583-624`: Surface order validation uses boolean failure for impossible order states if trusted renderer output is valid.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:624-660`: Command validation uses boolean failure for unsupported command kinds and invalid command shapes. Needs ABI proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:711-724`, `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:727-750`: Upload bounds and rectangle math overflow map to `false`. Needs ABI bound proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:2145-2164`: Fill coverage area overflow maps to `false`. Needs ABI/render size bound proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:2316-2337`: Glyph command validation uses boolean failure for invalid glyph refs. Needs proof whether host receives only trusted renderer glyph refs.
- `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig:2419-2436`: Sprite upload coverage overflow maps to `false`. Needs ABI upload-size proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:79-84`: Runtime obligation/progress errors return quiet no-work. If VT runtime errors come from internal state/ABI handles, this likely should not silently stop runtime work.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:263-278`: `vt_retained.feedLocked()` non-OK marks PTY lifecycle failed. Needs proof whether arbitrary PTY bytes can produce VT failure or whether this is parser invariant failure.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig:307-311`: Pending output copy/publish errors are silently ignored and pending output clears only after successful publish. Needs proof this cannot spin or wedge replies.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig:80-90`: Grid resize commit swallows sync failure. PTY resize may be operating; VT/render layout mismatch may be invariant.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig:93-103`: Locked grid resize commit swallows sync failure. Same proof gap.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig:134-137`: Current surface-layout sync returns `false` on error. Needs policy split by failed owner.
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig:68-80`: Slot reservation/acquire failure rejects publish. Could be operating capacity/OOM, but if reservation bounds are fixed and caller controls sizes, needs proof.
- `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:231`, `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:240`, `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:325`, `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:335`, `/home/home/personal/projects/howl/howl-linux-host/src/config/terminal.zig:345`: Config read errors silently default. User config errors are operating/user input, but product policy needs to say whether malformed fields should be ignored or rejected.

## Proof Gaps

- Need `howl-render` C ABI proof for `HowlRenderSurface` trust boundary: whether Linux host receives only Howl-owned, internally valid surfaces or must defensively accept arbitrary C ABI memory.
- Need status-code proof for prepared surface sidecar calls: which of `call_failed`, `null_surface`, `unsupported_*`, `invalid_*`, overflow, and span mismatch are valid operating outcomes.
- Need resource-kind proof: whether color glyph atlases or future resource kinds are intentionally unsupported host features or impossible for this renderer version.
- Need render-surface shape proof: whether the renderer may emit command shapes the Linux host does not realize, or whether unsupported shape counters hide renderer bugs.
- Need GL/resource policy proof: separate host operating failures (`gl_error`, texture allocation/capacity) from impossible renderer lifecycle failures (`invalid_order`, tombstone reuse, invalid spans).
- Need VT runtime API proof: whether `queryRuntimeObligation`, `progressRuntime`, `copyPendingOutput`, and `feedLocked` can fail due to external data/resource pressure or only due to programmer/ABI bugs.
- Need config policy proof: malformed optional config fields currently default silently; readiness requires deciding whether silent fallback is product law.
- Need diagnostic policy proof: `std.debug.print("howl-debug ...")` paths are ad hoc diagnostics. Planning needs to decide whether these remain temporary debug gates, structured diagnostics, or invariant crashes.

## Readiness Judgment

Not ready for implementation planning as a broad cleanup. The scan is source-backed enough to plan a proof-first research/planning step, but not enough to change failure handling safely. The blocking issue is the unproven trust boundary between `howl-render` prepared render surfaces and the Linux host realization path. Planning is ready only for a narrow proof task that reads the `howl-render` ABI/contracts/tests and classifies each current render-surface bucket as invariant, operating error, or intentionally unsupported host feature.
