# howl-host

`howl-host` is Howl's native Linux performance canary. It is a concrete client,
not a shared UI framework and not part of the core gate.

Current foundation:

- one Wayland window owner;
- one Vulkan/DRM render owner;
- triple-buffered DMA-BUF presentation with explicit sync;
- current `howl-vk.surface` and `howl-wayland` packages;
- host-local fixed-capacity tabs and tiled splits;
- canonical Session revisions projected live through current howl-client,
  howl-text, terminal Canvas, and howl-vk.surface into the physical window;
- three explicit-sync DMA-BUF slots rotated with exact compositor-release
  ownership before reuse; closing Window cancels a blocked Session observation;
- physical Wayland/xkb keyboard input delivered by a dedicated bounded Input
  owner so compositor dispatch never waits on Session action acknowledgements;
  Window owns compositor-advertised key repeat timing and re-resolves repeated
  keys through current xkb modifiers without catch-up bursts;
- terminal mouse tracking from Wayland motion/button/wheel facts: Window preserves
  raw surface occurrences, Render alone resolves pane/cell/pixel geometry, and
  Input forwards the existing canonical mouse action. Motion is latest-wins while
  buttons and wheel remain ordered with one causal pointer sequence.

The multiplexer is intentionally small. Its job is to keep multi-session
presentation an architectural invariant while Session, VT, PTY, text, and the
native presentation path are measured and optimized. Flutter and Web retain
their own client UI policy.

The current live loop deliberately bounds presentation backlog by compositor
release while canonical Session progress remains observer-independent. It is a
correctness baseline, not the final latency scheduler.

Terminal wheel policy is live on the canonical one-pane path. Mouse-tracking
applications receive semantic wheel reports; an ordinary primary screen owns local
retained-history scrollback; alternate screen + DECSET 1007 emits plain Up/Down
key cycles. History observations use the existing Render control connection while
the live long-poll remains isolated, and returning to live replaces that observer
with a revision-zero baseline so stale queued cuts cannot replay. Split/tab
scrollback remains outside this first happy-path slice.

Next: begin measuring input-to-present latency, frame cadence/jitter, CPU/GPU
cost, and memory slope before optimizing scheduling. The current physical typing
proof also makes per-keystroke Session publication/presentation churn directly
measurable.
