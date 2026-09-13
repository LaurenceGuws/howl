# howl-host

`howl-host` is Howl's native Linux performance canary. It is a concrete client,
not a shared UI framework and not part of the core gate.

Current foundation:

- one Wayland window owner;
- one Vulkan/DRM render owner;
- triple-buffered DMA-BUF presentation with explicit sync;
- current `howl-vk.surface` and `howl-wayland` packages;
- host-local fixed-capacity tabs and tiled splits.

The multiplexer is intentionally small. Its job is to keep multi-session
presentation an architectural invariant while Session, VT, PTY, text, and the
native presentation path are measured and optimized. Flutter and Web retain
their own client UI policy.

Next: attach canonical Howl Session endpoints and replace the bootstrap color
ring with real terminal presentation.
