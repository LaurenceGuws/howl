# Render Widget Surface Ownership Audit

## 1. Problem Statement

`howl-render` and `howl-linux-host` still preserve a stale generic surface model: render exposes broad `surface_*`, `cell_surface`, and `realizer` vocabulary while the host keeps tab-bar text preparation and resource presentation in `texture/frame.zig` and keeps scroll-bar control inside `src/buckets that must die/bucket2.zig`. This conflicts with the sprint contract: public render ABI must expose exactly host widget draw/render nouns and verbs, host presentation and GL resource lifetime must stay host-side, `term_surface`, `tab_bar_surface`, and `scroll_bar_surface` turns must be owned by their true widget owners, and no tab-bar or scroll-bar surface control may remain in `bucket2.zig` or `src/term.zig`.

## Orchestrator Review

The first artifact revision is rejected for implementation order. It correctly found stale nouns and ownership pressure, but it chose a host texture/frame-first slice, while the user's next step is explicitly render-repo-first: remove tab-bar/scroll-bar/term confusion from the render repo god surface worldview and make real render-side widget surfaces come to life there. Correction: the first implementation slice must sharpen public render ABI nouns with no compatibility shims before moving host owners. Public ABI must use exact widget nouns/verbs only; no `HowlRenderWidgetSurfaceFrame` shared public escape hatch is allowed. Shared primitives may remain private/internal only when named and justified as internal computation/data-plane facts. Avoid introducing broad new host owner nouns such as `presenter`; use `presentation` for the noun and keep GL work in existing `texture/*` paths. Scroll-bar render ABI remains conditional and defaults to no new render scroll-bar ABI until render computes scroll-bar output.

## 2. Current Stale Nouns And Paths

| Symbol/path | Owner today | Why wrong | Target owner/name |
|---|---|---|---|
| `howl-render/include/howl_render.h`: `HowlRenderSurfaceFrame`, `HowlRenderSurfaceFrame*`, `howl_render_surface_layout`, `howl_render_surface_point_cell` | Public render ABI | Generic `Surface` hides widget ownership; layout/point-cell are terminal-surface operations today. | `HowlRenderTermSurfaceFrame`, `HowlRenderTermSurfaceFrame*`, `howl_render_term_surface_layout`, `howl_render_term_surface_point_cell`. |
| `howl-render/include/howl_render.h`: `HowlRenderCellSurfacePrepare`, `HowlRenderCellSurfacePreparedUpload`, `howl_render_cell_surface_prepare` | Public render ABI | `cell_surface` is an implementation shape used by tab bar; it is not a host widget noun. | Delete. Replace with `HowlRenderTabBarSurfacePrepare`, `HowlRenderTabBarSurfacePreparedUpload`, `howl_render_tab_bar_surface_prepare`; add scroll-bar equivalent only if render computes a scroll-bar surface. |
| `howl-render/include/howl_render.h`: `HowlRenderTextHandle`, `HowlRenderText`, `howl_render_text_*` | Public render ABI | A single text handle makes the ABI look like a render god state shared by widgets. | Split into widget state handles: `HowlRenderTermSurfaceStateHandle`, `HowlRenderTabBarSurfaceStateHandle`, `HowlRenderScrollBarSurfaceStateHandle` as needed. |
| `howl-render/include/howl_render.h`: `HowlRenderTabBarSurface` exists, `HowlRenderScrollBarSurface` absent | Public render ABI | Tab bar has a surface ID type but no matching widget prepare/submit API; scroll bar is host-only primitive presentation in current source. | Keep exact `HowlRenderTermSurface` and `HowlRenderTabBarSurface`; do not add `HowlRenderScrollBarSurface` until render computes scroll-bar output. |
| `howl-render/src/libhowl_render.zig`: `howl_render_surface_*`, `howl_render_cell_surface_prepare`, `howl_render_text_submit_term_surface` | Render FFI | FFI exports preserve generic and mixed widget names. | Export only exact widget verbs; no compatibility exports. |
| `howl-render/src/surface/realizer.zig`, `realizer_resource_store.zig`, `realizer_test.zig` | Render test/helper surface path | Banned vocabulary and wrong owner pressure. It computes CPU pixel presentation of a frame; it is not host GL presentation. | Rename to presentation vocabulary if retained for tests, e.g. `presentation_pixels.zig` and `presentation_resource_store.zig`, or delete if superseded by widget tests. |
| `howl-render/src/surface/resource_store.zig`: `SpriteResourceStore`, `AdmissionRollback`, `resourceAdmissionForPrepared`, `atlasAdmissionForPrepared` | Render internals | `admission` is acceptable for bounded allocation checks, but path remains generic `surface`; public-facing comments/tests say render-surface. | Move under exact internal draw resource owner, e.g. `text/sprite_resources.zig` or `surface_frame/resources.zig`; keep bounded resource assertions. |
| `howl-render/src/event.zig`: `RenderRequest` | Render internal event token | If it means a render-turn action admission, it violates sprint vocabulary. | Rename to `RenderTrigger` only where semantics are wake/action admission; otherwise keep only if it is plain input data and record why. |
| `howl-render/src/surface/prepared_surface.zig`: `request: event.RenderRequest` | Render prepared surface | Couples prepared frame to stale action word. | `trigger`/`prepare_trigger` if action semantics; otherwise exact input noun. |
| `howl-linux-host/src/render/surface_retained.zig` | Host render retained state | `surface_retained` is generic and owns term-surface retained state only. | `src/render/term_surface_retained.zig` or `src/term/surface_retained.zig`; exported as `TermSurface` retained state. |
| `howl-linux-host/src/render/surface_layout.zig` | Host render layout | Generic name; functions query term layout and point-cell. | `src/render/term_surface_layout.zig` or `src/term/surface_layout.zig`. |
| `howl-linux-host/src/term.zig` | Terminal instance owner | Correct owner for `term_surface` turns, but still imports generic `surface_layout`/`surface_retained`. Must not absorb tab/scroll ownership. | Keep term-surface turns here; rename imports/types to term-surface vocabulary only. |
| `howl-linux-host/src/tab_bar/cell_surface.zig` | Tab bar helper | `cell_surface` is not a host widget noun. | `src/tab_bar/surface_layout.zig` or `src/tab_bar/text.zig`; API should prepare `tab_bar_surface`. |
| `howl-linux-host/src/tab_bar/surface.zig` | Tab bar cell writer | Owner is mostly right, but type `Surface` is too generic under the owner path. | `TabBarSurface` or `Cells` under `tab_bar` owner; public use should say `tab_bar_surface`. |
| `howl-linux-host/src/texture/frame.zig`: `tab_text_handle`, `tab_resources`, `tab_surface`, `uploadTabTextSurface` | Texture/presentation frame owner | Window texture frame owns tab-bar text state and render resources; this violates tab-bar surface control ownership. | Move control/state to `src/tab_bar/*`; texture frame may consume a prepared `tab_bar_surface` texture/presentation object only. |
| `howl-linux-host/src/texture/frame.zig`: scroll-bar draw loops | Texture/presentation frame owner | Drawing is OK as presentation backend, but control is not here. | Keep only GL drawing of already-shaped `scroll_bar_surface`/placement facts from scroll-bar owner. |
| `howl-linux-host/src/texture/term.zig`, `texture/tab_bar.zig`, `texture/scroll_bar.zig` | Host texture presentation | Correct host presentation nouns, but `texture/tab_bar.zig` also writes cells via `writeCells`. | Keep GL presentation only; move `writeCells` to `tab_bar` owner. |
| `howl-linux-host/src/buckets that must die/bucket2.zig`: `Surface` | Bucket | Bucket owns terminal wrapper, scroll-bar state, cursor, links, selection, and input callbacks. It is a false owner and explicitly must die. | Split: terminal runtime shell to true tab/pane owner; `scrollbar` field/control to `scroll_bar`; term-surface turn stays delegated to `term.zig`. |
| `howl-linux-host/src/buckets that must die/bucekt2_test.zig` | Bucket tests | Misspelled path, proves bucket behavior, and duplicates owner tests. | Move tests to true owners as slices land; delete typo path at sprint end. |

## 3. Exact Vocabulary

Accepted public/widget vocabulary:

| Kind | Accepted |
|---|---|
| Widget nouns | `term_surface`, `tab_bar_surface`, `scroll_bar_surface` |
| Host display cadence | `presentation`, `present`, `presented`, `present_in_flight`, `present_pending` |
| Wake/action edge | `trigger` when the meaning is signal/wake/action admission |
| Render compute internals | `shaping`, `layout`, `rasterization`, `atlas`, `damage`, `draw_list`, `surface_frame` only if scoped under an exact widget or internal frame owner |
| Host GL/backend | `texture`, `presentation`, `frame`, `resource`, `upload`, `retire`, `damage` |

Banned or stale vocabulary:

| Vocabulary | Rule |
|---|---|
| `realization`, `realizer`, `realize` | Replace with `presentation` vocabulary or an exact compute verb. |
| `request` | Replace with `trigger` where the meaning is signal/wake/action admission. Data input structs may keep an input noun only when they are not wake/action. |
| `HostSurface`, `host_surface` | Delete. No generic host UI surface worldview. |
| `scrollbar_surface` | Delete. Use `scroll_bar_surface`. |
| Public/generic `Surface` hiding widget ownership | Delete or move under an owner path where the full name is owner-true. |
| Compatibility aliases/shims | Delete. This is private code; no stale ABI aliases. |

## 4. Render Repo Final Public ABI Shape

Keep or add exact host widget C ABI nouns/verbs, with no compatibility shims:

| Action | ABI item |
|---|---|
| Keep, rename public frame structs by exact widget | `HowlRenderSurfaceRect` may stay as a shared primitive because it is a rectangle, not a host widget. Public frame output types must use exact widget nouns such as `HowlRenderTermSurfaceFrame` and `HowlRenderTabBarSurfaceFrame`. If an implementation struct remains shared inside Zig, it must be private/internal only and must not appear in the C ABI. |
| Keep | `HowlRenderTermSurface` with `term_surface_id`, `width`, `height`. |
| Keep | `HowlRenderTabBarSurface` with `tab_bar_surface_id`, `width`, `height`. |
| Do not add by default | `HowlRenderScrollBarSurface` only if a later source-backed slice proves render computes scroll-bar output. Current source has host-only `texture/scroll_bar.zig`, so default is no render scroll-bar ABI. |
| Replace | `HowlRenderTextHandle` with `HowlRenderTermSurfaceStateHandle` for terminal text surface state. |
| Add | `HowlRenderTabBarSurfaceStateHandle` for tab-bar text/draw state. |
| Add only if needed | `HowlRenderScrollBarSurfaceStateHandle` for scroll-bar draw state; skip if host-only primitive presentation remains sufficient. |
| Replace | `howl_render_text_init/deinit` with `howl_render_term_surface_init/deinit` and `howl_render_tab_bar_surface_init/deinit`. |
| Replace | `howl_render_surface_layout` with `howl_render_term_surface_layout`. |
| Replace | `howl_render_surface_point_cell` with `howl_render_term_surface_point_cell`. |
| Replace | `howl_render_text_prepare` with `howl_render_term_surface_prepare`. |
| Replace | `howl_render_cell_surface_prepare` with `howl_render_tab_bar_surface_prepare`; delete `cell_surface`. |
| Keep, rename | `howl_render_text_submit_term_surface` becomes `howl_render_term_surface_submit`. |
| Add | `howl_render_tab_bar_surface_submit` only if render needs submit bookkeeping for tab-bar resources; otherwise host presentation can consume the prepared frame directly and no submit verb is added. |
| Delete | Public generic `howl_render_surface_*`, `HowlRenderCellSurface*`, public `HowlRenderText*`, and all compatibility exports. |

Source-backed rationale:

| Source | Lesson |
|---|---|
| `AGENTS.md` lines 25-36, 159-176 | C ABI is the product; hosts own presentation cadence and backend resource presentation; Howl owns render contracts/computation. |
| `sprints/current.txt` lines 21-35 | Public render ABI nouns/verbs must match host widget nouns/verbs exactly; no god surface; term/tab/scroll owners are explicit. |
| Alacritty `alacritty/src/display/mod.rs` lines 341-400, 770-1047 | Display owns window, GL surface/context, glyph cache, damage tracker, draw/present sequencing. |
| Alacritty `alacritty/src/renderer/mod.rs` lines 88-93, 177-255 | Renderer owns draw operations and text/rect renderer objects, not host widget lifecycle. |
| Alacritty `alacritty/src/display/window.rs` lines 100-125, 259-265, 401-405 | Window owns redraw bit and pre-present notify, not render computation. |
| TigerBeetle `TIGER_STYLE.md` lines 271-276, 374-382 | Names must be exact; avoid duplicated/aliased state; construct/own state in the true owner. |

## 5. Host Owner Final Shape

| Owner | Final boundary |
|---|---|
| `src/term.zig` | Owns one terminal instance and `term_surface` turns: VT capture, term render prepare, prepared upload handoff, submit acknowledgement, present completion acknowledgement. It must not own tab-bar or scroll-bar surface control. |
| `src/tab_bar.zig` and `src/tab_bar/*` | Own tab metadata, label cells, tab-bar text config, tab-bar render state handle, tab-bar surface revision, and tab-bar surface prepare/upload handoff. `texture/frame.zig` may ask for a prepared `tab_bar_surface` but must not own `tab_text_handle`, `tab_resources`, or `tab_surface`. |
| `src/scroll_bar.zig` or `src/scroll_bar/*` | Own scroll model/view, mouse/drag state, placement/cache, visual invalidation, and any future `scroll_bar_surface` render state. Bucket and term do not store scroll-bar control. |
| `src/texture/term.zig` | Owns GL texture/resource presentation for one `term_surface` texture slot. It consumes render frames and returns `HowlRenderTermSurface`. |
| `src/texture/tab_bar.zig` | Owns GL drawing/presentation for tab-bar background/texture only. It must not write tab cells or own render text state. |
| `src/texture/scroll_bar.zig` | Owns GL primitive presentation for scroll bar placements only, or consumes a future prepared `scroll_bar_surface`. No scroll model/control. |
| `src/texture/frame.zig` | Owns window/main-thread GL frame presentation orchestration and present token generation. It may hold texture presentation slots, not widget control state. |
| `src/render/*` | Host-side C ABI wrappers and retained term-surface sequencing only. Generic `surface_*` files should be renamed to term-surface names or split by widget. |
| `src/buckets that must die/*` | No accepted sprint-end ownership. It may exist only while actively being emptied; no tab-bar or scroll-bar surface control may remain there. |

## 6. First Implementation Slice Only

Small reviewable render-repo-first slice: split the public `cell_surface` ABI into exact `tab_bar_surface` public ABI and update current host tab-bar call sites/tests. This is the sharper first cut because current source proves `cell_surface` is used by tab-bar only (`texture/frame.zig` prepares tab text through `HowlRenderCellSurfacePrepare`), the known panic is on the second tab/tab-bar path, and the slice makes a real render-side `tab_bar_surface` come to life without inventing scroll-bar render ABI.

Files and expected code changes:

| File | Expected change |
|---|---|
| `howl-render/include/howl_render.h` | Delete public `HowlRenderCellSurfacePrepare`, `HowlRenderCellSurfacePreparedUpload`, and `howl_render_cell_surface_prepare`. Add exact replacements `HowlRenderTabBarSurfacePrepare`, `HowlRenderTabBarSurfacePreparedUpload`, and `howl_render_tab_bar_surface_prepare`. The output frame type may remain the current public frame type in this slice only if the slice does not touch frame naming; do not add aliases. |
| `howl-render/src/libhowl_render.zig` | Replace export `howl_render_cell_surface_prepare` with `howl_render_tab_bar_surface_prepare`; call the same internal computation through a renamed method if small enough. No compatibility export remains. |
| `howl-render/src/text/surface.zig` | Rename public/internal method `prepareCellSurface` to `prepareTabBarSurface` or add exact tab-bar method and delete the cell-surface method in the same slice. The implementation may still call lower-level text/cell helpers privately. |
| `howl-render/src/test_abi.zig` | Rename ABI tests and helpers from `cellSurfacePrepare`/`HowlRenderCellSurface*`/`howl_render_cell_surface_prepare` to exact `tabBarSurfacePrepare`/`HowlRenderTabBarSurface*`/`howl_render_tab_bar_surface_prepare`. Add a negative grep expectation through naming, not a runtime shell. |
| `howl-linux-host/src/texture/frame.zig` | Update only the C ABI call and struct names in `uploadTabTextSurface`: use `HowlRenderTabBarSurfacePreparedUpload`, `HowlRenderTabBarSurfacePrepare`, and `howl_render_tab_bar_surface_prepare`. Do not move host ownership in this slice. |
| `howl-linux-host/src/tab_bar/cell_surface.zig` | If needed for compile clarity, rename type `CellSurfaceLayout` to `TabBarSurfaceLayout` while leaving the file move to a follow-up host-owner slice. Do not broaden scope. |
| `howl-linux-host/src/main.zig`, `host_test_root.zig` | Update only imports/type names required by any `TabBarSurfaceLayout` rename. |

Private/internal allowance for this slice:

| Internal item | Rule |
|---|---|
| Text cell preparation helpers | May stay private under `howl-render/src/text/*` because text cells are render computation input, not public host widget ABI. |
| Current public `HowlRenderSurfaceFrame` | May remain unchanged for this slice only to keep the cut reviewable; the next render ABI slice must rename public terminal/tab-bar frame output types to exact widget nouns. Do not introduce `HowlRenderWidgetSurfaceFrame`. |

Out of scope for first slice:

| Excluded | Reason |
|---|---|
| Host tab-bar owner move out of `texture/frame.zig` | Must follow after render ABI nouns are exact. |
| `HowlRenderSurfaceFrame`/`howl_render_surface_*` terminal-frame rename | Separate render ABI slice to avoid mixing two public ABI cuts. |
| Scroll-bar render ABI | Not source-backed yet; current scroll bar is host-only primitive presentation. |
| Bucket deletion | Must follow once render nouns and host owners are exact. |
| Panic fix by assertion weakening | Forbidden; this slice makes the tab-bar render ABI exact so the following host owner/resource-lifetime slice has unambiguous facts. |

Review proof for first slice:

| Proof | Expected result |
|---|---|
| `grep -R "HowlRenderCellSurface\|howl_render_cell_surface\|cellSurfacePrepare" howl-render/include howl-render/src howl-linux-host/src` | No matches. |
| `grep -R "HowlRenderTabBarSurfacePrepare\|howl_render_tab_bar_surface_prepare" howl-render/include howl-render/src howl-linux-host/src` | Matches in render ABI, FFI, tests, and the tab-bar host call site. |
| `grep -R "scroll_bar_surface\|HowlRenderScrollBarSurface" howl-render/include howl-render/src` | No matches unless a later accepted scroll-bar render slice adds source-backed computation. |
| `zig build test:unit` | ABI tests prove the new tab-bar-surface public path and no compatibility export. |

## 7. Follow-Up Slices In Order

1. Rename public terminal render ABI without `Frame`: `HowlRenderSurfaceFrame`/frame span types used by terminal output become exact prepared terminal surface names such as `HowlRenderTermSurfacePrepared`, `HowlRenderTermSurfacePreparedToken`, `HowlRenderTermSurfaceDamageSpan`, and `HowlRenderTermSurfaceCommandSpan`; constants use `HOWL_RENDER_TERM_SURFACE_PREPARED_*` or exact command/damage names; `surface_frame` output fields become `term_surface_prepared`; `surface_frame_status` becomes `term_surface_status`; `howl_render_surface_layout`/`howl_render_surface_point_cell` become `howl_render_term_surface_layout`/`howl_render_term_surface_point_cell`; update host call sites/tests; no compatibility shims. `HowlRenderTermSurface` remains the host presentation token and must not be reused for prepared render output.
2. Split render state handles by widget: replace public `HowlRenderTextHandle`/`HowlRenderText` and `howl_render_text_*` with exact `term_surface` and `tab_bar_surface` state handles/verbs. Keep shared text computation private.
3. Rename or delete render `realizer*` files/tests to presentation or exact compute vocabulary.
4. Audit `howl-render/src/event.zig` and `prepared_surface.zig` for `RenderRequest`; rename to `RenderTrigger` only if the semantics are action admission.
5. Move host tab-bar surface control out of `texture/frame.zig` into `src/tab_bar.zig` or `src/tab_bar/*`; `texture/frame.zig` keeps GL presentation orchestration only.
6. Move scroll-bar control out of `bucket2.zig` into `src/scroll_bar.zig` or `src/scroll_bar/*`; bucket may call the scroll-bar owner but must not own state/control long-term.
7. Rename host `render/surface_retained.zig` and `render/surface_layout.zig` to term-surface owner names; update `term.zig`, tests, and imports.
8. Delete or empty `src/buckets that must die/bucket2.zig` and move `bucekt2_test.zig` tests to true owners; remove typo path.
9. Final stale grep gate and ABI audit: no duplicate surface paths or public generic host-widget nouns remain.

## 8. Panic Hypothesis

Known panic: `trusted render create reuses live resource` in `howl-linux-host/src/texture/frame_resources.zig` lines 94-102 or the upload path lines 125-128.

Hypothesis:

| Evidence | Interpretation |
|---|---|
| `texture/frame.zig` lines 87-97 store `tab_resources` in the window texture frame state, while `uploadTabTextSurface` lines 247-269 prepares tab-bar cell text via the same render text handle/resource store across tab bar revisions. | Tab-bar resource lifecycle is coupled to window frame cache, not the tab-bar widget owner. A second tab/tab-bar show can prepare a frame that emits a create for a render resource value still live in `tab_resources`. |
| `texture/frame_resources.zig` line 100 panics if a create matches a live resource; line 101 panics if a create reuses any retired resource value. | Assertion is correct and should remain. The stale owner likely lets resource epochs/handle lifetime drift instead of explicitly reinitializing, retiring, or retaining under tab-bar owner rules. |
| `howl-render/src/surface/resource_store.zig` lines 371-383 uses `atlas_resource` with `value_next`, and tests lines 629-707 prove reuse within one store. | Reuse is valid only when the host-side resource store agrees it is the same live resource. If host tab resources are stale across a tab-bar state reset, a create for an already live value will panic correctly. |

How slices prove or fix it:

| Slice | Proof/fix |
|---|---|
| First slice | Makes the tab-bar render ABI exact (`tab_bar_surface`, not `cell_surface`) so the panic path can no longer hide behind generic cell-surface vocabulary. ABI tests prove the tab-bar surface path, but this slice is not expected to fix the panic by itself. |
| Later host tab-bar owner slice | Tab-bar owner will own `tab_resources` and tab render handle. Add owner-local test or hook that preparing the same tab-bar revision twice does not emit duplicate creates into a live resource store, and revision/tab-count changes either reuse without create or reset with GL resource deletion. Run second-tab/tab-bar repro. |
| Resource-lifetime fix slice if still needed | If the owner move only exposes the flaw, add explicit tab-bar resource epoch/lifetime transition in the tab-bar owner: on tab-bar render state reset, delete/retire host resources and create a fresh render state; on retained prepare, keep host resource store and render state paired. Do not change `frame_resources.zig` assertions. |

## 9. Tests And Gates

Required implementation gates from sprint:

| Gate | When |
|---|---|
| `zig fmt --check build.zig src` | Every host slice. |
| `zig build check` | Every host/render slice. |
| `zig build test:unit` | Every slice. |
| `zig build run -Doptimize=ReleaseFast` with second-tab/tab-bar repro | Any host presentation/tab-bar/texture/resource slice. |
| Repo-local `git diff --check` | Every slice. |
| Root `git diff --check` | Every slice. |

Stale grep gates:

| Gate | Expected sprint-end result |
|---|---|
| `grep -R "realiz\|Realiz" howl-render howl-linux-host/src` | No product-code matches except archived research/receipts if allowed. |
| `grep -R "scrollbar_surface" howl-render howl-linux-host/src` | No matches. |
| `grep -R "HostSurface\|host_surface" howl-render howl-linux-host/src` | No matches. |
| `grep -R "cell_surface\|CellSurface\|HowlRenderCellSurface\|howl_render_cell_surface" howl-render/include howl-render/src howl-linux-host/src` | No matches after first ABI slice. |
| `grep -R "howl_render_surface_\|HowlRenderSurfaceFrame\|HowlRenderTextHandle\|howl_render_text_" howl-render/include howl-linux-host/src` | No public/host matches after ABI rename slice, unless an internal primitive is explicitly receipted. |
| `grep -R "tab_text_handle\|tab_resources\|tab_surface" howl-linux-host/src/texture/frame.zig` | No matches after the later host tab-bar owner slice. |
| `grep -R "tab_bar_surface\|scroll_bar_surface" "howl-linux-host/src/buckets that must die" howl-linux-host/src/term.zig` | No control matches; term may mention only `term_surface`. |
| `grep -R "request" howl-render howl-linux-host/src` | Manually audit remaining matches; reject wake/action-admission uses, allow OS/API terms like `request_redraw` only if explicit external API vocabulary is being wrapped. |

## 10. Open Questions And Escalations

| Question | Escalation needed |
|---|---|
| Should render expose a first-class `scroll_bar_surface` ABI, or should scroll bar remain host-only GL primitive presentation? | User/orchestrator decision before ABI slice. Current source has host-only `texture/scroll_bar.zig` and no render ABI. Adding render ABI may be unnecessary unless text/shaped computation is needed. |
| May shared frame primitives keep a generic name internally? | Public ABI must be widget-prefixed. A private/internal shared frame primitive may remain only if it is not exported through C ABI and is justified as internal draw-frame data, not a host widget noun. |
| Is `request_redraw` acceptable as an external windowing/API term? | It is Alacritty and winit vocabulary (`display/window.rs` lines 259-265), but sprint bans `request` where signal/wake/action admission is meant. Keep only if treated as external API wrapper, otherwise rename Howl-local wrappers to `triggerRedraw`/`triggerFrame`. |
