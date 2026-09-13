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
  ownership before reuse; closing Window cancels a blocked Session observation.

The multiplexer is intentionally small. Its job is to keep multi-session
presentation an architectural invariant while Session, VT, PTY, text, and the
native presentation path are measured and optimized. Flutter and Web retain
their own client UI policy.

The current live loop deliberately bounds presentation backlog by compositor
release while canonical Session progress remains observer-independent. It is a
correctness baseline, not the final latency scheduler.

Next: wire physical input and begin measuring input-to-present latency, frame
cadence, CPU/GPU cost, and memory slope before optimizing scheduling.
