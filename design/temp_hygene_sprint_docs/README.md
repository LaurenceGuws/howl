# Temporary Hygiene Sprint

Purpose: turn the vt-core architecture cleanup rules into repo-wide gates before more feature work piles onto unclear owners.

Review order:
1. `howl-render-core` - highest risk: concrete backend sprawl, GL/GLES drift, legacy batch/text-scene split.
2. `howl-hosts` - high risk: host widgets own render wake, presentation ack, threading, input, and UX policy.
3. `howl-vt-core` - high risk but recently cleaned: protect new owner boundaries from facade/action/parser creep.
4. `howl-term` - high risk: runtime owner concentration, resize ordering, borrowed snapshot lifetimes, FFI cleanup.
5. `howl-session` - medium-high risk: smaller module, but PTY parity and typed control boundaries need correction.

Global gates:
- Every source file must have a current `Responsibility`, `Ownership`, and `Reason` header or be explicitly exempted.
- No new dumping-ground files: `utils`, `common`, `helpers`, `manager`, `adapter`, `bridge`, `bootstrap`, `pattern`.
- Split by reason to change, not by line count. Large cohesive owners may stay; mixed owners must split.
- Public facades must stay lifecycle/contract surfaces. Feature behavior belongs in named internal owners.
- Queue/apply/flush/present boundaries must be explicit and must not secretly perform adjacent layer work.
- Unsupported behavior must fail hard or remain tracked open; no fake placeholder semantics.
- Tests must be owner-shaped and prove the gate, not only broad regression coverage.

Current repo gates:
- `howl-render-core/gates.md`
- `howl-hosts/gates.md`
- `howl-vt-core/gates.md`
- `howl-term/gates.md`
- `howl-session/gates.md`
