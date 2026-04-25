 1. SDL layer = window + input only

  - create window
  - create GL context + swap buffers
  - pump events
  - map input events to host actions

  2. Renderer layer = zero SDL types

  - pure renderer API (init, resize, renderFrame, deinit)
  - takes plain data (size, glyph atlas handles, draw list)
  - uses OpenGL directly, but never imports SDL headers/types

  3. Session layer (shared candidate: howl-session)

  - owns howl-vt-core engine lifecycle
  - PTY/process feed/apply loop
  - produces render-ready frame model for renderer

  4. Composition in howl-sdl-host main loop

  - SDL events -> input mapper -> session
  - session snapshot/frame -> renderer
  - renderer present -> SDL swap

  So yes: SDL only for platform shell.
  Renderer stays decoupled and reusable, just not shoved into SDL code again.
