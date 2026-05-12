# Howl-Term Contract Boundaries

Purpose: lock Milestone 1 for `howl-term` before API cleanup or runtime-path churn starts.

Last updated: 2026-05-12

## Locked Product Target

`howl-term` is the terminal embedding package for Howl.
It is the embedder-facing terminal contract.
It is not the host runtime.

`howl-term` owns:
- the public embedding contract exposed through `src/howl_term.zig` and `src/ffi.zig`
- terminal state and lifecycle rules for the `HowlTerm` owner
- the contract joining session transport, VT state, snapshot publication, and frame preparation
- host input publication and host-consumed output and callback contracts
- the Zig facade and the C ABI as two surfaces over the same terminal product

`howl-term` does not own:
- host event loops, scheduling cadence, present cadence, or platform wake policy
- platform UX, windowing, tabs, clipboard UI, or input polling
- PTY variant behavior or child transport internals
- renderer backend internals or backend runtime policy
- milestone claims above the proof layer that actually measured them

Current implementation note:
- `src/terminal.zig` and `src/runtime/*` still contain the terminal state path that joins session, VT, snapshot, and frame owners
- the default execution path is now host-driven through explicit progress calls; `start` no longer defines correctness by spawning a library-owned runtime thread
- no contract or report may describe a hidden library scheduler as what `howl-term` fundamentally is

## Canonical Owner Chain

Canonical owner chain:
- `src/howl_term.zig` -> `src/term_namespace.zig` -> `src/terminal.zig` and `src/ffi.zig` -> domain owner files -> lower modules

File roles:
- `src/howl_term.zig`: public root only. It curates Zig exports and gates exported `howl_term_*` symbols. It owns no terminal behavior.
- `src/term_namespace.zig`: namespace wrapper only. It indexes and re-exports owner surfaces. It owns no behavior.
- `src/terminal.zig`: current broad owner for `HowlTerm` state and the public method table. It may delegate behavior downward. Roots and wrappers must not take behavior back from it.
- `src/runtime/contract.zig`: shared contract types for the `HowlTerm` owner and C ABI shims.
- `src/runtime/*.zig`: current lifecycle, I/O progress path, query, title, selection, terminal-reply, and mutex owners.
- `src/render/*.zig`: frame preparation, geometry sync, render compatibility, viewport, and snapshot-facing owners.
- `src/input/*.zig`: host input publication and control-signal translation owners.
- `src/wake/wake.zig`: snapshot wake and waiter coordination owner.
- `src/config/fonts.zig`: render font path and font size mutation owner.
- `src/ffi.zig`: flat C ABI catalog and handle conversion entrypoint. It delegates to `c_api/*` and must not invent separate terminal semantics.
- `src/c_api/*.zig`: domain C ABI shims. They translate C values, return codes, and buffers into owner-file calls. They must not import the public root or become a second product definition.

Lower-module ownership:
- `howl-session` owns PTY transport contracts, PTY variants, child process I/O, and resize or control delivery
- `howl-vt-core` owns terminal protocol state, parser behavior, grid state, snapshots, and selection vocabulary
- `howl-render-core` owns render contracts, frame queue behavior, backend selection, and backend runtime details

Host ownership:
- hosts such as `howl-linux-host` own the outer runtime, event loop, scheduling, wake policy, presentation cadence, and platform UX
- hosts consume the `howl-term` contract; they do not define lower-module behavior

## Canonical Proof Ladder

Proof layers:

| Claim Layer | Allowed Proof Surface | What It Can Prove | What It Cannot Prove |
|---|---|---|---|
| contract | `design/howl-term-embedding-sprint.md`, this document, `design/module-owner-responsibilities.md`, public-root and owner-file source inspection, Zig and C surface examples | product target, owner chain, exported-surface intent, file roles, ABI-sensitive surface inventory | runtime latency, wake cadence, live host behavior |
| `howl-term` runtime | `howl-term` tests, benchmarks, and harnesses that measure work inside the package | package-layer sequencing, snapshot publication, frame-prep cost, transport/apply/render handoff cost | host event-loop behavior, presentation cadence, shipped host responsiveness |
| host-visible | real host integrations such as `howl-linux-host` and Android host runs | user-visible latency, live repro behavior, host wake policy, presentation results | package internals without package-layer measurement |

Claim rules:
- claims about exported names, ownership, file roles, or ABI surface shape require contract proof
- claims about snapshot publication, frame preparation, wake sequencing, or runtime cost inside `howl-term` require `howl-term` runtime proof
- claims about live command-output responsiveness, UI pacing, or shipped embedder behavior require host-visible proof
- lower proof layers do not close higher-layer claims
- if a proof layer is missing, the report must mark that layer open instead of implying success by intuition

Bounded proof purpose:
- Zig and C examples prove public-surface reachability and sequencing only
- package benchmarks prove package-layer work only
- host repros prove host-visible behavior only
