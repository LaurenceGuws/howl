#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

reject() {
    pattern=$1
    shift
    if rg -n "$pattern" "$@"; then
        printf '%s\n' "physical terminal renderer exclusion matched: $pattern" >&2
        exit 1
    fi
}

reject 'ProducerUpdate|vkQueueSubmit|publishLatestReadyFrame|rendererFd|window|wake' \
    howl-host/src/terminal_gpu.zig
reject 'replayCursor|cursor_replay|CursorReplay|CursorOverlay' \
    howl-host/src/renderer.zig howl-vk/src/surface.zig
reject 'CursorPublication|CursorPublishError|cursorPublicationIdentity|publishCursor|takeCursor|cursor_policy|drainStaticCursorPublications|CursorPresentationPolicy|CursorSemanticPolicy|OwnerViews|ownerViews' \
    howl-host/src/terminal_handoff.zig howl-host/src/renderer.zig \
    howl-host/src/main.zig howl-host/src/config.zig
reject 'ligature|shapeText|selection|hyperlink|animation|blink|cursor_trail|terminal_image|image_placement|sixel|kitty_graphics' \
    howl-host/src/terminal_gpu.zig howl-vk/src/terminal_cells.zig \
    howl-vk/src/shaders/terminal.vert howl-vk/src/shaders/terminal.frag

submit_count=$(rg -c 'vk\.vkQueueSubmit\(' howl-host/src/renderer.zig)
producer_update_count=$(rg -c 'render_api\.canvas\.ProducerUpdate' howl-host/src/renderer.zig)
if [ "$submit_count" -ne 1 ]; then
    printf 'expected one Renderer queue-submit site, found %s\n' "$submit_count" >&2
    exit 1
fi
if [ "$producer_update_count" -ne 1 ]; then
    printf 'expected only the Chrome ProducerUpdate owner, found %s\n' "$producer_update_count" >&2
    exit 1
fi

for proof in T001 T002 T003 T004 T005 T006 T007 T008 T009 T010 T011 T012 T013 T014 T017 T018 T019 T021 T022; do
    if ! rg -q "test \"[^\"]*$proof" \
        howl-host/src/renderer.zig howl-host/src/terminal_gpu.zig \
        howl-vk/src/terminal_cells.zig; then
        printf 'missing physical terminal renderer proof %s\n' "$proof" >&2
        exit 1
    fi
done
for proof in \
    'terminal shader push constant ABI has exact tracked SPIR-V layout' \
    'terminal shader CPU oracle maps a two by two pane exactly'; do
    if ! rg -q "test \"$proof\"" howl-vk/src/terminal_cells.zig; then
        printf 'missing physical terminal renderer proof: %s\n' "$proof" >&2
        exit 1
    fi
done

# T020 is static construction/call-graph closure, deliberately not an opaque
# Vulkan-handle equality claim. Terminal descriptor construction accepts only
# terminal Resources, PaneResources, and FontGpu; generic Context is not an
# input to either terminal recorder boundary.
if ! rg -q '^fn descriptorBindingFacts\(' howl-vk/src/terminal_cells.zig ||
    ! rg -q 'resources: \*const Resources,' howl-vk/src/terminal_cells.zig ||
    ! rg -q 'pane: \*const PaneResources,' howl-vk/src/terminal_cells.zig ||
    ! rg -q 'font: \*const FontGpu,' howl-vk/src/terminal_cells.zig; then
    printf '%s\n' 'missing terminal-only descriptor construction boundary' >&2
    exit 1
fi
if ! rg -q 'try result\.retainDescriptorBindings\(facts\);' \
    howl-vk/src/terminal_cells.zig ||
    ! rg -q 'try pane\.validateDescriptorBindings\(facts\);' \
    howl-vk/src/terminal_cells.zig; then
    printf '%s\n' 'terminal descriptor identity is not retained and validated by production' >&2
    exit 1
fi
for identity in \
    descriptor_set_identity \
    descriptor_instance_buffer \
    descriptor_row_buffer \
    descriptor_instance_range \
    descriptor_row_range \
    descriptor_sampler \
    descriptor_atlas_view \
    descriptor_atlas_image; do
    if ! rg -q "$identity" howl-vk/src/terminal_cells.zig; then
        printf 'missing retained terminal descriptor identity: %s\n' "$identity" >&2
        exit 1
    fi
done
if rg -n 'surface\.Context|vk_surface\.Context|recordGenericDraws' \
    howl-vk/src/terminal_cells.zig howl-host/src/terminal_gpu.zig; then
    printf '%s\n' 'generic Canvas owner entered a terminal binding or recorder boundary' >&2
    exit 1
fi
if rg -n 'terminal_cells|terminal_gpu' howl-vk/src/surface.zig; then
    printf '%s\n' 'terminal owner entered generic Canvas Context' >&2
    exit 1
fi

render_order=$(awk '
    /fn render\(/ { inside = 1 }
    inside && /graphics\.beginPass\(/ { begin = NR }
    inside && /state\.gpu\.recordDraws\(/ { terminal = NR }
    inside && /graphics\.recordGenericDraws\(/ { generic = NR }
    inside && /graphics\.endPass\(/ { end = NR; exit }
    END {
        if (begin == 0 || terminal == 0 || generic == 0 || end == 0 ||
            !(begin < terminal && terminal < generic && generic < end)) exit 1
    }
' howl-host/src/renderer.zig) || {
    printf '%s\n' 'combined render path does not record terminal before generic in one pass' >&2
    exit 1
}
if [ -n "$render_order" ]; then
    printf '%s\n' 'unexpected renderer-order checker output' >&2
    exit 1
fi

if ! rg -q 'test "T004 physical style rasters and shader decoration values remain exact"' \
    howl-host/src/terminal_gpu.zig; then
    printf '%s\n' "missing production-shaped T004 physical raster proof" >&2
    exit 1
fi
if ! rg -q 'placeStyledRaster\(tile, metrics, raster, key\.bold, key\.italic\)' \
    howl-host/src/terminal_gpu.zig; then
    printf '%s\n' "physical font preparation does not apply bounded style raster treatment" >&2
    exit 1
fi
for proof in \
    'blank first FontGpu batch initializes atlas only after completion' \
    'FontGpu atlas transition rollback and fatal ownership remain exact' \
    'terminal sampler and fixed glyph tiles exclude adjacent texels' \
    'styled raster treatment has exact bytes clipping and no tile bleed'; do
    if ! rg -q "test \"$proof\"" \
        howl-vk/src/terminal_cells.zig howl-host/src/terminal_gpu.zig; then
        printf 'missing hostile physical terminal proof: %s\n' "$proof" >&2
        exit 1
    fi
done
if ! rg -q 'const FontCommandRecorder = union\(enum\)' \
    howl-vk/src/terminal_cells.zig; then
    printf '%s\n' "missing shared production/proof font command recorder" >&2
    exit 1
fi
if ! rg -q 'var sampler_info = terminalSamplerInfo\(\)' \
    howl-vk/src/terminal_cells.zig ||
    ! rg -q 'clamp\(glyph_uv, tile_min, tile_max\)' \
    howl-vk/src/shaders/terminal.frag; then
    printf '%s\n' "terminal glyph atlas sampling is not production-fixed to one tile" >&2
    exit 1
fi
