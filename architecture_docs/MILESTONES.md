# Howl Milestone Map

This document defines the full Howl development journey across modules.
It is parent-level authority: child repos own local contracts and queues, while
this document owns cross-module sequencing, product phases, and long-range
scope.

## Product Goal

Howl is an embeddable terminal stack:

- a portable VT engine
- a session/process runtime
- a terminal surface composition layer
- backend-neutral render planning
- replaceable renderer backends
- concrete hosts that own windowing, input, app lifecycle, and packaging
- supporting tools for docs, package/release work, inspection, and hygiene

The first product target is a Linux desktop terminal host using SDL for
window/input and a decoupled OpenGL renderer path.

## Phase Definitions

| Phase | Meaning |
| --- | --- |
| `POC` | Proves module shape and integration direction. API may still change, but ownership must be correct. |
| `MVP` | Required for the first usable Linux terminal release. API churn is controlled and must be justified by integration pressure. |
| `LONG` | Post-MVP direction. Work stays recorded so it is not rediscovered or accidentally pulled into MVP scope. |

## Family Milestone Ladder

| ID | Phase | Name | Outcome |
| --- | --- | --- | --- |
| `F0` | `POC` | Workspace Authority | Parent module map, dependency rules, integration flow, and repo scopes are explicit. |
| `F1` | `POC` | Package Baseline | Every planned module has a clean repo scaffold, local build/test, and matching remote. |
| `F2` | `MVP` | Session-Core Integration | Session owns process lifecycle and drives VT core through public APIs. |
| `F3` | `MVP` | Surface Contract | Surface composes session, input routing, viewport state, and frame production without host framework types. |
| `F4` | `MVP` | Render Core Contract | Backend-neutral render plan, glyph/cell layout model, damage model, and resource policy are defined. |
| `F5` | `MVP` | First Renderer Path | OpenGL renderer consumes render-core plans and draws text/cursor in a host-owned context. |
| `F6` | `MVP` | First Host Loop | SDL host owns window/input/context/present loop and runs one terminal surface. |
| `F7` | `MVP` | Interactive Terminal | Linux SDL host runs an interactive shell with resize, keyboard input, text rendering, scrollback path, and shutdown. |
| `F8` | `MVP` | MVP Quality Lock | Local evidence covers latency-sensitive loops, resize/input/render stability, leaks, and release packaging. |
| `F9` | `LONG` | Multi-Surface Runtime | Shared modules support multiple terminal surfaces without shared mutable state leaks. |
| `F10` | `LONG` | Renderer Portability | GLES, Vulkan, Metal, and software paths share render-core contracts without duplicating terminal logic. |
| `F11` | `LONG` | Host Expansion | Additional hosts integrate through surface/session/render contracts without lower-layer churn. |
| `F12` | `LONG` | Best-In-Class Terminal Stack | Competitive latency, throughput, resource discipline, protocol breadth, and UX quality are proven with evidence. |

## Module Milestones

### `howl-vt-core`

| ID | Phase | Outcome |
| --- | --- | --- |
| `VT-POC-01` | `POC` | Parser/event/screen runtime is separated from host and renderer concerns. |
| `VT-POC-02` | `POC` | Runtime facade exposes feed/apply/reset/read behavior through exported public symbols. |
| `VT-POC-03` | `POC` | Replay tests cover deterministic core behavior across split input, cursor movement, erase, reset, modes, history, selection, input encoding, snapshot, and stress evidence. |
| `VT-POC-04` | `POC` | Package identity is clean: repo is `howl-vt-core`, Zig module export is `vt_core`, and no legacy names remain in public API. |
| `VT-MVP-01` | `MVP` | Session can instantiate and drive the runtime engine entirely through public API. |
| `VT-MVP-02` | `MVP` | Surface can read all state needed for frame production without mutable escapes. |
| `VT-MVP-03` | `MVP` | First-host pressure fixes only portable VT behavior, with replay tests before behavior changes. |
| `VT-MVP-04` | `MVP` | Input encoding covers Linux SDL host keyboard requirements for shell/editor usage. |
| `VT-MVP-05` | `MVP` | Snapshot/conformance evidence can be used by session/surface tests without importing internals. |
| `VT-MVP-06` | `MVP` | MVP release documents exact supported protocol/input/history/selection/render-state scope. |
| `VT-LONG-01` | `LONG` | Broader VT protocol coverage grows from real fixture failures and documented terminal compatibility goals. |
| `VT-LONG-02` | `LONG` | Parser throughput and memory discipline are measured against reproducible fixture classes. |
| `VT-LONG-03` | `LONG` | Advanced terminal features are added only when they fit the core contract: hyperlinks, bracketed paste, synchronized update, images, and advanced modes. |
| `VT-LONG-04` | `LONG` | Multi-host conformance proves identical core behavior across Linux, mobile, and future desktop hosts. |
| `VT-LONG-05` | `LONG` | Core remains embeddable outside Howl hosts for diagnostics, replay tooling, and future editor integration. |

### `howl-session`

| ID | Phase | Outcome |
| --- | --- | --- |
| `SE-POC-01` | `POC` | Session lifecycle API exists: init/deinit/start/stop/feed/apply/reset/resize/control/snapshot/restore. |
| `SE-POC-02` | `POC` | Transport interface and in-memory/failing/Unix PTY implementations define the process boundary. |
| `SE-POC-03` | `POC` | Conformance, reliability, performance, operations, and snapshot evidence exist as local test support. |
| `SE-POC-04` | `POC` | Source topology is intentional: session core, transport implementations, and test support are separated. |
| `SE-MVP-01` | `MVP` | Unix PTY can start a shell, read output, write input, resize, signal, and stop deterministically. |
| `SE-MVP-02` | `MVP` | Current pending-byte apply path is replaced by real VT engine feed/apply integration. |
| `SE-MVP-03` | `MVP` | Session exposes a host-neutral terminal state source for surface frame production. |
| `SE-MVP-04` | `MVP` | Session input path writes encoded bytes to transport and advances VT state from process output. |
| `SE-MVP-05` | `MVP` | Resize commits session dimensions, notifies PTY, and updates VT runtime dimensions in a documented order. |
| `SE-MVP-06` | `MVP` | Failure boundaries are proven for PTY start/read/write/resize/stop without corrupting session state. |
| `SE-MVP-07` | `MVP` | One interactive terminal session can run under surface/host control with deterministic shutdown. |
| `SE-MVP-08` | `MVP` | Transport ownership separates POSIX PTY, Android container bridge, future Windows ConPTY, and future Apple container bridge behind host-neutral session contracts. |
| `SE-LONG-01` | `LONG` | Multiple sessions can run concurrently without hidden shared state or allocator leaks. |
| `SE-LONG-02` | `LONG` | Session diagnostics can capture process/runtime state for bug reports without becoming a telemetry dumping ground. |
| `SE-LONG-03` | `LONG` | Snapshot/restore and operation counters remain stable under real host loops and multi-session orchestration. |
| `SE-LONG-04` | `LONG` | Session supports richer process control where needed: environment setup, cwd, shell selection, and process groups. |
| `SE-LONG-05` | `LONG` | Session becomes reusable by terminal hosts, editor terminals, test harnesses, and headless tools. |

### `howl-term-surface`

| ID | Phase | Outcome |
| --- | --- | --- |
| `SF-POC-01` | `POC` | Surface API defines lifecycle, dimensions, input entrypoints, frame query, and error reporting. |
| `SF-POC-02` | `POC` | Surface composes one session and one renderer-facing frame path without importing SDL/OpenGL types. |
| `SF-POC-03` | `POC` | Surface owns terminal-widget state: focus, viewport, dirty state, cursor blink phase, selection view state, and frame timing policy. |
| `SF-POC-04` | `POC` | Host actions and terminal actions are separate plain-data types. |
| `SF-MVP-01` | `MVP` | Surface translates host key/text/control input into session/core calls. |
| `SF-MVP-02` | `MVP` | Surface converts session/core state into a stable frame model for render-core. |
| `SF-MVP-03` | `MVP` | Surface resize updates session dimensions and render viewport requirements coherently. |
| `SF-MVP-04` | `MVP` | Surface exposes dirty/damage information so host render loops do not redraw blindly. |
| `SF-MVP-05` | `MVP` | Surface owns one terminal widget lifecycle for the SDL host MVP. |
| `SF-MVP-06` | `MVP` | Surface test evidence covers input/feed/render-frame/reset/resize ordering. |
| `SF-LONG-01` | `LONG` | Multiple surfaces can represent tabs, panes, and embedded terminal widgets. |
| `SF-LONG-02` | `LONG` | Surface supports scrollback viewport navigation, selection extraction, clipboard boundaries, and search hooks. |
| `SF-LONG-03` | `LONG` | Surface coordinates shared renderer resources without owning backend-specific objects. |
| `SF-LONG-04` | `LONG` | Surface can be consumed by non-SDL hosts without API shape changes. |
| `SF-LONG-05` | `LONG` | Surface becomes the primary public terminal widget API for Howl applications. |

### `render/howl-render-core`

| ID | Phase | Outcome |
| --- | --- | --- |
| `RC-POC-01` | `POC` | Render-core data model defines pixels, grid, cells, glyph ids, colors, cursor, selection, and damage. |
| `RC-POC-02` | `POC` | Render plan output is plain data and can be tested without GPU or host frameworks. |
| `RC-POC-03` | `POC` | Font/shaping inputs are modeled without binding to one backend implementation. |
| `RC-POC-04` | `POC` | Draw command ordering is deterministic for clear, glyph, cursor, selection, and decoration layers. |
| `RC-MVP-01` | `MVP` | Surface frame model converts into render-core plans for visible terminal cells. |
| `RC-MVP-02` | `MVP` | Damage model supports typing, cursor movement, line clear, full clear, resize, and scroll. |
| `RC-MVP-03` | `MVP` | Glyph run planning handles ASCII, UTF-8 codepoints, wide cells, and blank/continuation cells at MVP level. |
| `RC-MVP-04` | `MVP` | Atlas/cache policy interface lets GL own GPU resources while sharing planning decisions. |
| `RC-MVP-05` | `MVP` | Render-core tests freeze output for representative terminal frames and damage scenarios. |
| `RC-MVP-06` | `MVP` | GL backend consumes render-core output without duplicating layout logic. |
| `RC-LONG-01` | `LONG` | Shaping, ligatures, emoji constraints, underline/strike/box drawing, and complex decorations are modeled. |
| `RC-LONG-02` | `LONG` | Backend-neutral render benchmarks measure plan generation cost and allocation behavior. |
| `RC-LONG-03` | `LONG` | Software renderer can serve as a reference output oracle for renderer correctness. |
| `RC-LONG-04` | `LONG` | GLES, Vulkan, Metal, and GL consume the same render-core contracts. |
| `RC-LONG-05` | `LONG` | Render-core supports high-DPI, fractional scaling policy, and color-space decisions without host coupling. |

### `render/howl-render-gl`

| ID | Phase | Outcome |
| --- | --- | --- |
| `GL-POC-01` | `POC` | GL renderer API defines context expectations, init, resize, renderFrame, resource reset, and deinit. |
| `GL-POC-02` | `POC` | Renderer builds shader/program/buffer scaffolding without SDL imports. |
| `GL-POC-03` | `POC` | Renderer accepts render-core plan data and records/draws clear and rectangle primitives. |
| `GL-POC-04` | `POC` | Tests or probes verify resource lifecycle without requiring host lifecycle ownership. |
| `GL-MVP-01` | `MVP` | Renderer draws terminal background, glyph quads, cursor, and selection for one viewport. |
| `GL-MVP-02` | `MVP` | Glyph atlas upload/update path supports MVP font and glyph set. |
| `GL-MVP-03` | `MVP` | Renderer handles resize, viewport updates, and resource rebuild deterministically. |
| `GL-MVP-04` | `MVP` | Renderer performs batched draws for changed frame plans with bounded steady-state allocation. |
| `GL-MVP-05` | `MVP` | SDL host can use GL renderer in a host-owned context and swap buffers externally. |
| `GL-MVP-06` | `MVP` | MVP evidence covers blank frame, text frame, cursor frame, resize, and repeated render loop stability. |
| `GL-LONG-01` | `LONG` | Renderer optimizes atlas packing, batching, buffer updates, and shader paths with benchmarks. |
| `GL-LONG-02` | `LONG` | Renderer supports decorations, high-DPI, fractional scaling, color management, and transparency policy. |
| `GL-LONG-03` | `LONG` | GL path remains a portable baseline renderer even if Vulkan becomes the Linux performance target. |
| `GL-LONG-04` | `LONG` | Renderer contributes comparable latency/CPU/throughput evidence against other backends. |

### `render/howl-render-gles`

| ID | Phase | Outcome |
| --- | --- | --- |
| `GLES-POC-01` | `POC` | GLES repo has clean package scaffold and backend API shape matching renderer backend rules. |
| `GLES-POC-02` | `POC` | GLES capability limits are documented: shader version, texture formats, buffer update strategy, mobile constraints. |
| `GLES-POC-03` | `POC` | Minimal context-owned resource lifecycle compiles without Android UI coupling. |
| `GLES-MVP-01` | `MVP` | Parked outside the Linux MVP critical path unless GL cannot provide the required portable baseline. |
| `GLES-MVP-02` | `MVP` | If activated, consumes render-core plans without adding mobile assumptions to render-core. |
| `GLES-LONG-01` | `LONG` | GLES renderer supports Android/mobile host constraints and mobile GPU resource discipline. |
| `GLES-LONG-02` | `LONG` | GLES output matches render-core conformance fixtures used by GL/software paths. |
| `GLES-LONG-03` | `LONG` | GLES backend participates in mobile latency, power, and memory evidence. |
| `GLES-LONG-04` | `LONG` | Android host integration uses GLES without leaking Android types into renderer core. |

### `render/howl-render-metal`

| ID | Phase | Outcome |
| --- | --- | --- |
| `MTL-POC-01` | `POC` | Metal repo has clean package scaffold and backend API shape matching renderer backend rules. |
| `MTL-POC-02` | `POC` | Metal ownership boundaries are documented: device, command queue, pipelines, textures, buffers, and drawable ownership. |
| `MTL-POC-03` | `POC` | Objective-C/Swift/C bridge requirements are isolated from render-core contracts. |
| `MTL-MVP-01` | `MVP` | Parked outside the Linux MVP critical path because Apple hosts are not part of the first release. |
| `MTL-MVP-02` | `MVP` | If activated early, proves render-core plan consumption without changing the surface API. |
| `MTL-LONG-01` | `LONG` | Metal backend supports macOS/iOS host rendering through backend-neutral plans. |
| `MTL-LONG-02` | `LONG` | Metal output matches shared renderer fixtures for text, cursor, selection, damage, and resize. |
| `MTL-LONG-03` | `LONG` | Apple platform renderer evidence covers high-DPI, color, power, and latency behavior. |
| `MTL-LONG-04` | `LONG` | Metal-specific resource strategy stays behind backend API and does not affect other renderers. |

### `render/howl-render-vulkan`

| ID | Phase | Outcome |
| --- | --- | --- |
| `VK-POC-01` | `POC` | Vulkan repo has clean package scaffold and backend API shape matching renderer backend rules. |
| `VK-POC-02` | `POC` | Vulkan ownership boundaries are documented: instance, device, swapchain-independent renderer state, command buffers, descriptors, and synchronization. |
| `VK-POC-03` | `POC` | Renderer API avoids owning host window/surface creation. |
| `VK-MVP-01` | `MVP` | Parked until GL MVP and render-core contracts are stable enough to measure against. |
| `VK-MVP-02` | `MVP` | If pulled forward, Vulkan must prove measurable MVP benefit before becoming default Linux path. |
| `VK-LONG-01` | `LONG` | Vulkan renderer consumes render-core plans and competes as the high-performance Linux backend. |
| `VK-LONG-02` | `LONG` | Vulkan path proves latency, throughput, and CPU usage against GL with reproducible measurements. |
| `VK-LONG-03` | `LONG` | Vulkan resource lifetime and synchronization are testable without host orchestration leaks. |
| `VK-LONG-04` | `LONG` | Vulkan backend supports multi-surface rendering where host composition requires it. |

### `render/howl-render-software`

| ID | Phase | Outcome |
| --- | --- | --- |
| `SW-POC-01` | `POC` | Software renderer repo has clean package scaffold and plain pixel-buffer API. |
| `SW-POC-02` | `POC` | Software renderer can consume a minimal render-core plan and write deterministic pixels. |
| `SW-POC-03` | `POC` | Output format, stride, color layout, clipping, and clear behavior are specified. |
| `SW-POC-04` | `POC` | Headless tests can compare output buffers without GPU or windowing. |
| `SW-MVP-01` | `MVP` | Optional for Linux MVP; activated if renderer correctness needs a reference output path before GL matures. |
| `SW-MVP-02` | `MVP` | Provides deterministic tests for clear, glyph cells, cursor, selection, damage, and resize output. |
| `SW-MVP-03` | `MVP` | Can generate debug snapshots for render-core/GL mismatch investigations. |
| `SW-LONG-01` | `LONG` | Software renderer becomes the correctness oracle for backend renderer conformance. |
| `SW-LONG-02` | `LONG` | Software path supports headless screenshots for docs, tests, and diagnostics. |
| `SW-LONG-03` | `LONG` | Software renderer remains simple and deterministic, not a competing optimized GUI backend. |
| `SW-LONG-04` | `LONG` | Pixel output fixtures track visual regressions across render-core changes. |
| `SW-LONG-05` | `LONG` | Software renderer can support environments without GPU access when explicitly selected. |

### `howl-hosts/howl-sdl-host`

| ID | Phase | Outcome |
| --- | --- | --- |
| `SDL-POC-01` | `POC` | Host scaffold owns executable entrypoint, window config, lifecycle state, and clean build/test. |
| `SDL-POC-02` | `POC` | SDL dependency and platform setup are documented and isolated to the host. |
| `SDL-POC-03` | `POC` | Window creation, event pump, GL context creation, and swap/present loop are proven with no terminal logic. |
| `SDL-POC-04` | `POC` | SDL keyboard/text/resize events map into host-neutral action structs. |
| `SDL-MVP-01` | `MVP` | Host creates one window and one GL context and passes context ownership expectations to GL renderer. |
| `SDL-MVP-02` | `MVP` | Host owns event loop timing, input polling, frame scheduling, and presentation. |
| `SDL-MVP-03` | `MVP` | Host composes one terminal surface, one session, and one GL renderer. |
| `SDL-MVP-04` | `MVP` | Host starts an interactive shell through session and routes keyboard/text input to it. |
| `SDL-MVP-05` | `MVP` | Host renders process output through surface, render-core, and GL renderer. |
| `SDL-MVP-06` | `MVP` | Host resize updates SDL viewport, surface dimensions, session/PTY dimensions, render-core plan, and GL viewport. |
| `SDL-MVP-07` | `MVP` | Host shutdown releases surface/session/renderer/window/process resources deterministically. |
| `SDL-MVP-08` | `MVP` | MVP build/release instructions produce a runnable Linux binary. |
| `SDL-LONG-01` | `LONG` | Host supports tabs, panes, multiple surfaces, and app-level orchestration. |
| `SDL-LONG-02` | `LONG` | Host supports renderer backend selection after GL plus at least one alternate backend are production-ready. |
| `SDL-LONG-03` | `LONG` | Host supports clipboard, IME, drag/drop, config, font selection, themes, and window state persistence. |
| `SDL-LONG-04` | `LONG` | Host quality evidence covers input latency, scroll smoothness, CPU usage, memory, and release packaging. |
| `SDL-LONG-05` | `LONG` | Linux SDL host becomes the reference host for future platform hosts. |

### `howl-hosts/howl-android-host`

| ID | Phase | Outcome |
| --- | --- | --- |
| `AND-POC-01` | `POC` | Android host scaffold owns Android lifecycle scope, platform bridge shape, and native package baseline. |
| `AND-POC-02` | `POC` | Host boundary distinguishes Android UI lifecycle, input, surface creation, and process/container bridge ownership. |
| `AND-POC-03` | `POC` | Android input events map to host-neutral action structs without leaking Android types into surface/session. |
| `AND-POC-04` | `POC` | Alpine/container-backed process plan is documented as Android host/transport integration pressure, not Unix-only session policy. |
| `AND-MVP-01` | `MVP` | Parked outside the Linux MVP critical path; scaffold exists to keep portability pressure visible. |
| `AND-MVP-02` | `MVP` | Any session changes needed by Android are expressed as transport abstraction improvements, not Android imports in session core. |
| `AND-LONG-01` | `LONG` | Android host owns activity/service lifecycle, surface lifecycle, soft keyboard/IME, clipboard, permissions, and packaging. |
| `AND-LONG-02` | `LONG` | Android terminal process runs through an embedded container/process bridge behind the session transport API. |
| `AND-LONG-03` | `LONG` | Android renderer path uses GLES or Vulkan through render-core contracts. |
| `AND-LONG-04` | `LONG` | Android host participates in multi-host conformance, performance, power, and memory evidence. |
| `AND-LONG-05` | `LONG` | Android host supports multiple terminal surfaces where platform UX requires tabs, splits, or embedded terminal widgets. |

### `utils/howl-docs`

| ID | Phase | Outcome |
| --- | --- | --- |
| `DOCS-POC-01` | `POC` | Docs site can publish stable user-facing documentation for released Howl modules. |
| `DOCS-POC-02` | `POC` | Docs content structure separates product docs from contributor workflow docs. |
| `DOCS-MVP-01` | `MVP` | MVP terminal release has user-facing install/run/config/troubleshooting pages. |
| `DOCS-MVP-02` | `MVP` | Docs site links exact module releases used by the MVP host. |
| `DOCS-LONG-01` | `LONG` | Docs site covers module APIs, host guides, renderer architecture, performance evidence, and release history. |
| `DOCS-LONG-02` | `LONG` | Docs tooling supports screenshots, examples, and generated API excerpts where useful. |

### `utils/howl-microscope`

| ID | Phase | Outcome |
| --- | --- | --- |
| `MICRO-POC-01` | `POC` | Inspection tooling can run targeted probes against terminal/session/render behavior. |
| `MICRO-POC-02` | `POC` | Probe output is useful for architect review without becoming product telemetry. |
| `MICRO-MVP-01` | `MVP` | MVP host can be inspected for frame timing, input timing, and resource behavior during manual testing. |
| `MICRO-MVP-02` | `MVP` | Tooling supports local-only evidence capture for release decisions. |
| `MICRO-LONG-01` | `LONG` | Microscope becomes the shared diagnostics bench for latency, throughput, rendering, and memory investigations. |
| `MICRO-LONG-02` | `LONG` | Probe suites can compare module releases without changing production code. |

### `utils/howl-pm`

| ID | Phase | Outcome |
| --- | --- | --- |
| `PM-POC-01` | `POC` | Package/release tooling can understand the Howl multi-repo module graph. |
| `PM-POC-02` | `POC` | Tooling can list module versions, remotes, tags, and release state. |
| `PM-MVP-01` | `MVP` | MVP release can be assembled from exact module tags with reproducible metadata. |
| `PM-MVP-02` | `MVP` | Release notes can identify participating module versions and known scope. |
| `PM-LONG-01` | `LONG` | Package tooling supports multi-module upgrades, compatibility checks, and release manifests. |
| `PM-LONG-02` | `LONG` | Tooling remains workflow-local and does not introduce CI dependency. |

### `utils/hygene`

| ID | Phase | Outcome |
| --- | --- | --- |
| `HYG-POC-01` | `POC` | Local hygiene scripts can inspect source layout, comments, line counts, and scaffold residue. |
| `HYG-POC-02` | `POC` | Script output is stable enough for architect review and does not require external services. |
| `HYG-MVP-01` | `MVP` | MVP release can run workspace hygiene checks across participating repos before tagging. |
| `HYG-MVP-02` | `MVP` | Hygiene checks report forbidden patterns, scaffold leftovers, and file-structure drift without rewriting files. |
| `HYG-LONG-01` | `LONG` | Hygiene tooling grows into a local review companion for topology, docs placement, symbol naming, and test coverage shape. |
| `HYG-LONG-02` | `LONG` | Hygiene tooling stays local and explicit; it does not become CI or hidden policy enforcement. |

## MVP Execution Order

1. `howl-session`: complete Unix PTY lifecycle and replace current queue-only behavior with real VT core driving.
2. `howl-term-surface`: define one-surface composition API around session, input routing, dimensions, dirty state, and frame model.
3. `render/howl-render-core`: define backend-neutral render frame/plan/damage/glyph data.
4. `render/howl-render-gl`: render the first terminal frames from render-core output in a host-owned GL context.
5. `howl-hosts/howl-sdl-host`: own SDL window/input/context/present and compose one terminal surface.
6. `howl-vt-core`: fix only proven portable semantic gaps discovered by real host pressure.
7. `utils/howl-docs` and `utils/howl-pm`: publish MVP docs and release metadata.
8. Family release: lock MVP behavior with local evidence, tags, and release notes.

## Linux MVP Completion Sequence

This is the ordered path to the first Linux MVP. Architect queues should advance
through this sequence unless a listed dependency is already complete.

| Step | Milestones | Required Result |
| --- | --- | --- |
| `LMVP-01` | `SE-MVP-01`, `SE-MVP-08` | Session transport boundary is portable, while Linux uses POSIX PTY as the first concrete implementation. |
| `LMVP-02` | `VT-MVP-01`, `SE-MVP-02` | Session owns a real `vt_core` engine instance and drives feed/apply through public APIs. |
| `LMVP-03` | `SE-MVP-03`, `SE-MVP-04`, `SE-MVP-05`, `SE-MVP-06` | Session can run a shell loop: process output to VT, input to process, resize in documented order, deterministic failures. |
| `LMVP-04` | `SF-POC-01` through `SF-POC-04` | Surface contract is explicit before render or host code depends on it. |
| `LMVP-05` | `SF-MVP-01`, `SF-MVP-02`, `SF-MVP-03`, `SF-MVP-04` | Surface converts session/core state into host-neutral frame data and dirty state. |
| `LMVP-06` | `RC-POC-01` through `RC-POC-04` | Render-core frame and draw plan model exists without GPU or host types. |
| `LMVP-07` | `RC-MVP-01` through `RC-MVP-06` | Render-core can plan visible terminal frames and damage for GL consumption. |
| `LMVP-08` | `GL-POC-01` through `GL-POC-04` | GL renderer resource boundary is proven without SDL ownership. |
| `LMVP-09` | `GL-MVP-01` through `GL-MVP-06` | GL renderer draws MVP terminal frames from render-core output. |
| `LMVP-10` | `SDL-POC-01` through `SDL-POC-04` | SDL host proves window, event, context, swap, and input mapping without terminal logic. |
| `LMVP-11` | `SDL-MVP-01` through `SDL-MVP-07`, `SF-MVP-05`, `SE-MVP-07` | SDL host composes one interactive terminal surface end to end. |
| `LMVP-12` | `VT-MVP-03`, `VT-MVP-04`, `VT-MVP-05`, `VT-MVP-06` | Portable VT gaps found by the host are fixed and the supported core surface is documented. |
| `LMVP-13` | `DOCS-MVP-01`, `DOCS-MVP-02`, `PM-MVP-01`, `PM-MVP-02`, `HYG-MVP-01`, `HYG-MVP-02`, `SDL-MVP-08` | MVP release is documented, locally validated, packaged, and tagged with exact module versions. |

## Transport Portability Rule

Session owns a host-neutral transport contract, not a Unix-only PTY worldview.
Linux MVP uses POSIX PTY first because it is the first host target. Android and
Apple mobile/desktop hosts are expected to apply pressure through container or
platform process bridges; Windows is expected to apply pressure through ConPTY.
Those pressures should improve the session transport abstraction rather than
introduce platform types into session core.

## Architect Steering Rules

1. Parent docs own cross-module sequencing and dependency direction.
2. Child repos own local contracts, tests, and active queues.
3. POC work proves shape; MVP work ships the first Linux terminal; LONG work is recorded but not pulled forward without a dependency reason.
4. Renderer backend work must not duplicate render-core logic.
5. Host work must not absorb session, VT, surface, or render-core responsibilities.
6. Session work must not import host, surface, or renderer types.
7. Surface work is the composition boundary, not a dumping ground for platform code or backend-specific rendering.
8. Utility tooling must support development and release work without becoming product runtime scope.
9. New module dependencies require updates to `MODULE_MAP.md`, `DEPENDENCY_RULES.md`, and this milestone map in the same commit series.

## MVP Exit Bar

The MVP is complete only when:

- one SDL host binary opens a terminal window
- a shell process runs through session-owned PTY transport
- keyboard input reaches the process
- process output reaches VT core and renders through surface, render-core, and GL
- resize updates PTY, VT dimensions, surface frame, renderer viewport, and host presentation
- shutdown releases process/session/surface/renderer/window resources deterministically
- local build/test evidence passes in all participating repos
- docs state install/run/debug steps and known missing long-term features
- release metadata identifies exact module tags used by the MVP
