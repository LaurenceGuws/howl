# Host chrome shaders

These three GLSL sources define the two bounded Vulkan chrome pipelines.
`chrome.vert.spv`, `solid.frag.spv`, and `text.frag.spv` under `src/shaders`
were compiled from them with Arch `glslc 2026.2` (Vulkan headers 1.4.350.1)
using `glslc -O`.

Source → SPIR-V SHA-256:

- `chrome.vert`: `8b784df16430294a8b2a09546fde5309f639b5827e55377daba4d5bc9c7ea52f`
  → `a821106eb8361a90e1bfb68f646aa500b3e0391c51f707a3567441c6de4b85c4`
- `solid.frag`: `70c72b61d49c2dcfb4a6b6548a750d99a49546e466fe511bf868f16a09c72be0`
  → `dea84053456372cf44bf0e12241fc48844d58a17a42235ba4312fb01186003c1`
- `text.frag`: `820859d55539089dbb18b1cbb767cdf640b67790f3099f29fa4c7cd6948efeff`
  → `41b32a7802756ad1d748906fdc51c19a015299d20524bab828f41cb9888790ad`

The solid fragment shader writes the supplied RGBA color. The text fragment
shader multiplies that alpha by the shared R8 glyph-atlas coverage; the Vulkan
pipeline applies source-over blending.
