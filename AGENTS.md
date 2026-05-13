# Workspace Rules

Owner: workspace root.

Purpose: global product, ownership, runtime, proof, and documentation rules.

1. Product identity is `howl-term` / `howl_term` only.

2. Work from first principles.
   - Prefer simple control flow over clever control flow.
   - Put a bound on everything.
   - Make steady-state behavior explicit.
   - Fail hard on missing ownership, missing proof, or missing invariants.

3. Layering is hard.
   - hosts -> `howl-pty`, `howl-render`, `howl-vt`, and `howl-hosts/vendor/*`
   - no reverse deps
   - no new umbrella runtime layer

4. Ownership is hard.
   - `howl-pty` owns PTY variants, child I/O, resize delivery, control signals, and transport state.
   - `howl-vt` owns parser state, terminal state, selection, input encoding, and host-facing protocol
     consequences.
   - `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit
     scheduling, renderer variants, and text shaping.
   - hosts own platform UX, event loops, wake policy, presentation cadence, and runtime orchestration.

5. Owner rules.
   - Public roots curate exports only.
   - Namespace wrappers aggregate owners only.
   - Owner files own state and mutation.
   - FFI translates contracts only.
   - Move behavior toward the smallest true owner.

6. Runtime rules.
   - The program runs at its own pace.
   - Event loops do bounded work per turn.
   - Main-thread control flow stays centralized.
   - Leaf helpers do not own policy.
   - Background threads wake the owner thread; they do not silently take over its work.

7. Proof rules.
   - No fake progress.
   - No placeholder semantics.
   - If a required path is missing, fail hard and mark it open.
   - User-visible runtime changes close only with proof on the owning host.
   - Parity closes on outcome, not on identical internals.

8. Style rules.
   - `design/style-law.md` is the one strict style law.
   - Changes are reviewed against that law line by line.
   - Touched-file style regressions block closure unless justified at review.

9. Naming bans.
   - Do not add ambiguous public names such as `adapter`, `bridge`, `bootstrap`, `manager`,
     `helper`, `util`, or `pattern`.
   - Do not add sentence-style symbol names.

10. Dependency rules.
    - Keep dependencies explicit.
    - Prefer fewer dependencies.
    - Keep one clear build authority per repo.
    - Reuse proven code paths from `~/personal/zide` when the ownership boundary still stays true.

11. Workflow rules.
    - Read the owner boundary before editing.
    - Centralize the control spine first.
    - Prove the hot path second.
    - Update docs in the same change when boundaries, proofs, or public contracts move.
    - Finish the active checkpoint before opening the next one.

12. Git cadence.
    - Commit and push each meaningful checkpoint.
    - Do not let important work sit locally for long.
    - Keep commits narrow and truthful.

13. Work clarity gate.
    - If ownership, boundary, or flow is unclear, stop and mark `work-not-clear`.
    - Do not patch around unclear design with wrappers or temporary convenience layers.

14. Documentation rules.
    - Docs are part of the product.
    - Keep docs short, exact, and source-friendly.
    - Prefer principles, guides, proofs, and reference over long narrative drift.
    - If a doc becomes misleading, fix it immediately.

15. Current direction.
    - Keep Howl owner-true.
    - Keep runtime control flow boring.
    - Keep TigerBeetle-style discipline while preserving the Howl brand.
