# Render API Language Deletion Sprint

Owner: workspace root.

Status: Slice 1 and Slice 2 accepted and committed. Slice 3 is blocked on exact
owner-path research/refinement before promotion.

Research cache:

- Accepted by Reviewer Agent: `research/cache-2026-06-01-render-api-language-deletion.md`.

## Purpose

Delete stale render internal/build/test/doc `protocol` bucket language and shape.
The render API is the product. A separate render protocol proof bucket is not a
product boundary.

This sprint does not authorize public ABI renames. Public exported C ABI names
that contain `protocol` or `V0` remain product vocabulary unless a later explicit
ABI-product slice authorizes an ABI break.

## Governing Evidence

- `AGENTS.md` defines the ABIs as the product and assigns `howl-render` ownership
  of render contracts, retained-frame state, prepare/submit scheduling,
  render-surface contracts, and text shaping.
- `loop.txt` requires research before scratchpad, scratchpad before `current.txt`,
  and `current.txt` before worker code.
- `research/cache-2026-06-01-render-api-language-deletion.md` inventories current
  `protocol`/`protocol_v0` source, build, test, docs, ABI, and host occurrences.
- Reviewer accepted that cache as sufficient evidence for this scratchpad, with
  the constraints encoded below.

## Non-Negotiable Constraints

- Do not edit product code from this scratchpad directly.
- Promote exactly one slice to `current.txt` before worker code starts.
- Preserve public ABI/export names in this sprint unless a child scratchpad and
  explicit ABI-product slice authorizes a break:
  - `HOWL_RENDER_PROTOCOL_V0_VERSION`
  - `HOWL_RENDER_V0_*`
  - `HowlRenderV0*`
  - `HowlRenderPreparedSurfaceDiagnostics.protocol_v0_emit_status`
  - `howl_render_prepared_surface_protocol_v0()`
- Delete the separate `test:protocol-proof` bucket only after every current
  `src/test_protocol_proof.zig` test is discoverable through unfiltered
  `zig build test:unit`.
- Do not require `zig build test:unit -- "protocol v0"` as a proof gate.
- Do not change host behavior while doing render naming/build cleanup.
- Do not invent vague replacement buckets such as `protocol`, `api`, `common`,
  `utils`, `manager`, `engine`, or `controller`.
- Stop if final owner names cannot be tied to source-backed responsibilities in
  the accepted research cache.

## Owner Roles From Accepted Cache

- Prepared V0 frame emission:
  - Current file: `howl-render/src/protocol_v0/emit.zig`.
  - Evidence: owns emission limits, V0 frame construction, command/upload/create
    spans, persistent sprite resource state, alpha atlas packing, glyph-run
    batching, and resource IDs.
  - True owner direction: prepared-frame V0 emission, not generic protocol.
- Software V0 realization/oracle:
  - Current file: `howl-render/src/protocol_v0/realize.zig`.
  - Evidence: owns retained resource validation, software realization into pixels,
    invalid-frame rejection, and oracle behavior.
  - True owner direction: V0 frame realization/oracle, not generic protocol.
- FFI ABI layout assertions:
  - Current file: `howl-render/src/ffi/protocol_v0.zig`.
  - Evidence: mirrors public C ABI constants and layout; translates contract facts
    only.
  - True owner direction: FFI ABI V0 layout/assertion owner. Public ABI names are
    preserved in this sprint.
- Render API unit proof:
  - Current file: `howl-render/src/test_protocol_proof.zig`.
  - Evidence: separate proof root contains oracle/equivalence tests not currently
    discovered by `test:unit`.
  - True owner direction: unit-test proof under `howl-render/src/test/`, not a
    separate build category.

## Sprint Slices

### Slice 1: Move Separate Proof Tests Under Unit Gate

Status: accepted and committed in `howl-render` `aa1749d`.

Goal:

- Make every current `src/test_protocol_proof.zig` test discoverable through
  unfiltered `zig build test:unit`.
- Keep behavior, ABI, host code, and public names unchanged.

Allowed files:

- `howl-render/src/test_protocol_proof.zig`
- `howl-render/src/test.zig`
- `howl-render/src/test_unit.zig`
- `howl-render/src/test/unit.zig`
- `howl-render/src/test/render_api_v0_oracle.zig`
- `howl-render/src/test/unit/root.zig`
- `howl-render/src/test/unit/geometry.zig`
- `howl-render/src/test/unit/render_api_v0_oracle.zig`
- `howl-render/build.zig`

Required shape:

- `src/test/unit.zig` is deleted as the mixed unit aggregate.
- `src/test/unit/root.zig` becomes the unit-test aggregate.
- Existing geometry tests from `src/test/unit.zig` move into
  `src/test/unit/geometry.zig`.
- `src/test_unit.zig` imports `test/unit/root.zig`.
- `src/test.zig` updates its unit import from `test/unit.zig` to
  `test/unit/root.zig`.
- Existing temporary `src/test/render_api_v0_oracle.zig`, if present from a held
  worker diff, moves to `src/test/unit/render_api_v0_oracle.zig` and is removed
  from the old path.
- All proof/equivalence test logic from `src/test_protocol_proof.zig` moves into
  `src/test/unit/render_api_v0_oracle.zig`.
- `src/test/unit/render_api_v0_oracle.zig` is the single owner for render API V0
  oracle/equivalence unit tests in this slice.
- `src/test/unit/root.zig` imports `render_api_v0_oracle.zig` so unfiltered
  `zig build test:unit` discovers the tests.
- `src/test_protocol_proof.zig` remains only as a temporary build-root wrapper
  for Slice 1 and imports `src/test/unit/render_api_v0_oracle.zig` to satisfy
  the old `test:protocol-proof` build step until Slice 2 deletes it.
- `src/test_protocol_proof.zig` contains no independent test logic after this
  slice.
- `howl-render/build.zig` updates only `unit_mod` wiring so the moved oracle
  tests compile under `zig build test:unit`. The wiring must match the existing
  font/options/library/include requirements already used by `protocol_proof_mod`.
- No source owner file moves in this slice.
- No host changes.

Verification:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:protocol-proof`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`

Accepted verification for `aa1749d`:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:protocol-proof`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`

Stop conditions:

- Stop if moving the test requires product-code changes.
- Stop if `zig build test:unit` does not discover the moved proof tests without a
  filter string.
- Stop if the unit test folder split requires build root behavior outside
  import rewiring in `src/test_unit.zig` and `src/test.zig`.
- Stop if `build.zig` changes anything except unit module wiring needed by the
  moved oracle tests.
- Stop if proof/equivalence test logic is duplicated or split between the new
  owner file and the temporary old build root.
- Stop if a compatibility wrapper is needed outside the old build root.

### Slice 2: Delete Separate Protocol-Proof Build Bucket

Status: accepted and committed in `howl-render` `6bf6388`.

Goal:

- Remove `protocol_proof_mod`, `test:protocol-proof`, and
  `test:protocol-proof:build` after Slice 1 proves unit discovery.

Allowed files:

- `howl-render/build.zig`
- old `howl-render/src/test_protocol_proof.zig` root, only if Slice 1 leaves it as
  a temporary wrapper for the old build step

Required shape:

- `zig build test` aggregates `test:unit` and `test:abi` only.
- `zig build test:build` aggregates category build steps without the deleted proof
  bucket.
- No filtered test command is required to prove V0/API behavior.

Verification:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From `howl-render`: `zig build test:build`
- From `howl-render`: `zig build check`
- From `howl-render`: `git diff --check`
- Grep gate: `rg 'test:protocol-proof|protocol_proof|test_protocol_proof' howl-render/build.zig howl-render/src`
  prints nothing, except historical comments are not allowed.

Accepted verification for `6bf6388`:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From `howl-render`: `zig build test:build`
- From `howl-render`: `zig build check`
- From `howl-render`: `git diff --check`
- From `howl-render`: `rg 'test:protocol-proof|protocol_proof|test_protocol_proof' build.zig src`
  printed nothing.

Stop conditions:

- Stop if any proof test becomes undiscoverable from `zig build test:unit`.
- Stop if deleting the build step requires ABI or host changes.

### Slice 3: Rename Render Internal Source Bucket To True Owners

Status: blocked. The accepted research cache identifies owner roles but does not
choose final replacement paths/names. Do not promote this slice until a focused
research cache or scratchpad refinement names exact owner paths and a reviewer
accepts them.

Goal:

- Delete `howl-render/src/protocol_v0/` as an internal source bucket.
- Preserve public ABI symbols and behavior.

Allowed files:

- `howl-render/src/protocol_v0/emit.zig`
- `howl-render/src/protocol_v0/realize.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/test/unit.zig`
- moved proof test file under `howl-render/src/test/`
- any import-only updates in `howl-render/src/ffi/protocol_v0.zig`

Required shape:

- Move `emit.zig` to a noun-owner path for prepared V0 frame emission.
- Move `realize.zig` to a noun-owner path for software V0 realization/oracle.
- Update imports only.
- Keep public ABI names unchanged.
- Keep tests under `zig build test:unit`.

Verification:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From `howl-render`: `zig build check`
- From `howl-render`: `git diff --check`
- Grep gate: `rg 'src/protocol_v0|\.\./protocol_v0|protocol_v0/' howl-render/src`
  prints nothing.

Stop conditions:

- Stop if owner names cannot be justified by the roles above.
- Stop if this requires host code changes.
- Stop if public ABI names change.

### Slice 4: Rename Internal Test Names And Docs That Teach Protocol As Product

Goal:

- Remove stale render-internal/doc language that teaches `protocol` as a separate
  product boundary.

Allowed files:

- moved render unit proof file under `howl-render/src/test/`
- moved emission/realization owner files if their test names still say
  `protocol v0`
- `docs/render-protocol-v0.md`
- documentation references discovered by the accepted cache or Slice 3 grep gates

Required shape:

- Internal test names describe render API V0 frame emission/realization/oracle
  behavior, not `protocol proof` as a category.
- Documentation describes render API V0 as the ABI/product surface, not
  `howl-render-protocol` as a separate product.
- Public ABI symbol spelling remains unchanged unless separately authorized.

Verification:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From root: `zig build check`
- From root: `zig build test`
- From workspace root: `git diff --check`
- Grep gate: `rg 'test:protocol-proof|protocol_proof|render-protocol|howl-render-protocol' .`
  prints nothing outside accepted historical research/cache files.

Stop conditions:

- Stop if doc changes imply public ABI renames.
- Stop if host internals need broad renaming; make a child scratchpad instead.

## Follow-Up Proof Gap

Host internals still contain many `protocol_v0` names while consuming public V0
frames. This sprint intentionally avoids host behavior changes. If host internal
language must be cleaned after render cleanup, create a separate host scratchpad
from targeted host research, including a full read of
`howl-linux-host/src/window/term_texture.zig`.

## Completion Criteria

- `current.txt` no longer references the completed RGBA deletion slice.
- `howl-render` has no separate protocol-proof build/test bucket.
- `howl-render/src/protocol_v0/` is gone.
- Render API proof runs through unfiltered `zig build test:unit`.
- Public ABI/export names are unchanged unless explicitly authorized by a later
  ABI slice.
- Scratchpad is closed with accepted commit hashes and verification commands.
