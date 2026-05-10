1. Product identity is `howl-term` / `howl_term` only.

  2. Layering is hard:
     - hosts -> `howl-term` (+ `howl-hosts/vendor/*`)
     - `howl-term` -> session/render/vt variants
     - no reverse deps

  3. Module ownership is hard:
     - session owns PTY variants
     - render-core owns render backend variants
     - hosts own platform UX/runtime only

  4. No fake progress:
     - no stub/fake placeholder semantics
     - if missing: fail hard + mark open

  5. Parity close:
     - user-visible runtime changes close only with SDL+Android proof

  6. Platform freedom:
     - parity is outcome-level, not identical internals

  7. Naming discipline:
     - short, specific symbols
     - ban ambiguous public terms: `adapter`, `bridge`, `bootstrap`, `manager`, `helper`, `util`, `pattern`
     - no sentence-style symbol names

  8. Reuse over reinvention:
     - prefer proven code paths from `~/personal/zide` when backend-agnostic
     - rebrand/restructure to fit Howl boundaries

  9. Work clarity gate:
     - if ownership/boundary/flow is unclear: stop and mark `work-not-clear`

  10. Cadence:
     - commit+push each meaningful checkpoint
     - no long local-only runs
