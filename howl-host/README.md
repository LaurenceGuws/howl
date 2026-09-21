# howl-host

`howl-host` is Howl's native Linux performance canary. It is a concrete client,
not a shared UI framework and not part of the core gate.

The Host has two explicit initial-terminal ownership modes:

    howl-host --local FONT [--fallback FONT ...]
    howl-host ENDPOINT FONT [--fallback FONT ...]
    howl-host ENDPOINT_LEFT ENDPOINT_RIGHT FONT [--fallback FONT ...]

Every mode may append ordered `--fallback FONT` pairs. The primary font remains
the sole cell-metric authority; fallbacks are consulted only when the primary
does not cover the complete shaped cluster. The current native text atlas is an
alpha-mask renderer, so these fallbacks must be ordinary outline/mono/gray faces;
color-bitmap emoji fonts are not yet a supported fallback class.

--local owns one howl-instance directly in the Host process. Input services its
PTY/VT lifetime independently of presentation; Render borrows canonical VT
observation only for synchronous Canvas projection. There is no Howl endpoint or client connection in that route. It deliberately starts as a
one-pane generic-Canvas proof; local split/tab creation and the retained Vulkan
fast renderer are not implied.

Endpoint startup remains an attached-client route: the Host consumes explicit externally owned Instance streams. The Host does not create terminal processes for attached panes. Tabs/splits are Host presentation state; sourcing another attached pane requires another explicit Instance stream, whether supplied directly or later selected through Server -> Sessions -> Instances orchestration.

Current foundation:

- one Wayland window owner;
- one Vulkan/DRM render owner;
- triple-buffered DMA-BUF presentation with explicit sync;
- current `howl-vk.surface` and `howl-wayland` packages;
- host-local fixed-capacity tabs and tiled splits;
- canonical Instance revisions projected live through current howl-client,
  howl-text, terminal Canvas, and howl-vk.surface into the physical window;
- three explicit-sync DMA-BUF slots rotated with exact compositor-release
  ownership before reuse; closing Window cancels a blocked Instance observation;
- physical Wayland/xkb keyboard input delivered by a dedicated bounded Input
  owner so compositor dispatch never waits on Instance action acknowledgements;
  Window owns compositor-advertised key repeat timing and re-resolves repeated
  keys through current xkb modifiers without catch-up bursts;
- terminal mouse tracking from Wayland motion/button/wheel facts: Window preserves
  raw surface occurrences, Render alone resolves pane/cell/pixel geometry, and
  Input forwards the existing canonical mouse action. Motion is latest-wins while
  buttons and wheel remain ordered with one causal pointer sequence.

The multiplexer is intentionally small. Its job is to keep multi-Instance
presentation an architectural invariant while Instance, VT, PTY, text, and the
native presentation path are measured and optimized. Flutter and Web retain
their own client UI policy.

The current live loop deliberately bounds presentation backlog by compositor
release while canonical Instance progress remains observer-independent. It is a
correctness baseline, not the final latency scheduler.

Terminal wheel policy is live on the one-pane paths. Mouse-tracking
applications receive semantic wheel reports; an ordinary primary screen owns local
retained-history scrollback; alternate screen + DECSET 1007 emits plain Up/Down
key cycles. Attached history uses the existing Render control connection while
the live long-poll remains isolated; local history projects the requested
canonical VT window directly. Returning to live resets only the route-specific
observer state. Split/tab scrollback remains outside this first local slice.

Next: begin measuring input-to-present latency, frame cadence/jitter, CPU/GPU
cost, and memory slope before optimizing scheduling. The current physical typing
proof also makes per-keystroke Instance publication/presentation churn directly
measurable.
