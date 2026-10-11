#version 450

layout(set = 0, binding = 2) uniform sampler2D atlas;
layout(push_constant) uniform Push {
    uvec2 surface;
    ivec2 origin;
    uvec2 grid;
    uvec2 cell;
    uvec2 atlas_extent;
    uvec4 lines;
    uvec4 cursor;
    uvec2 cursor_colors;
} push;

layout(location = 0) in vec2 glyph_uv;
layout(location = 1) in vec2 cell_uv;
layout(location = 2) flat in uint glyph_slot;
layout(location = 3) flat in uint flags;
layout(location = 4) flat in uint foreground;
layout(location = 5) flat in uint background;
layout(location = 6) flat in uint underline_color;
layout(location = 7) flat in uvec2 logical_cell;
layout(location = 0) out vec4 output_color;

vec4 color(uint packed) {
    return unpackUnorm4x8(packed);
}

void main() {
    vec4 fg = color(foreground);
    vec4 bg = color(background);
    if ((flags & 2u) != 0u) fg.rgb *= 0.5;
    float alpha = 0.0;
    if (glyph_slot != 0xffffu) {
        uvec2 tile = uvec2(glyph_slot % 20u, glyph_slot / 20u);
        vec2 tile_min = (vec2(tile * push.cell) + vec2(0.5)) /
            vec2(push.atlas_extent);
        vec2 tile_max = (vec2((tile + uvec2(1u)) * push.cell) - vec2(0.5)) /
            vec2(push.atlas_extent);
        alpha = texture(atlas, clamp(glyph_uv, tile_min, tile_max)).r;
    }
    vec4 result = mix(bg, fg, alpha);
    float pixel_y = cell_uv.y * float(push.cell.y);
    if ((flags & 8u) != 0u &&
        pixel_y >= float(push.lines.x) &&
        pixel_y < float(push.lines.x + push.lines.y))
        result = color(underline_color);
    if ((flags & 16u) != 0u &&
        pixel_y >= float(push.lines.z) &&
        pixel_y < float(push.lines.z + push.lines.w))
        result = fg;
    bool cursor_cell = push.cursor.w != 0u &&
        logical_cell == push.cursor.xy;
    if (cursor_cell) {
        uint shape = push.cursor.z;
        float pixel_x = cell_uv.x * float(push.cell.x);
        bool covered = shape == 0u ||
            (shape == 1u && pixel_y >= float(push.cell.y - push.lines.y)) ||
            (shape == 2u && pixel_x < 2.0);
        if (covered) {
            vec4 cursor_color = color(push.cursor_colors.x);
            if (shape == 0u)
                result = mix(cursor_color, color(push.cursor_colors.y), alpha);
            else
                result = cursor_color;
        }
    }
    output_color = result;
}
