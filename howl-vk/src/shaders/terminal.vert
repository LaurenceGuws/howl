#version 450

layout(set = 0, binding = 0, std430) readonly buffer Instances {
    uvec4 values[];
} instances;
layout(set = 0, binding = 1, std430) readonly buffer Rows {
    uint values[];
} rows;

layout(push_constant) uniform Push {
    uvec2 surface;
    ivec2 origin;
    uvec2 grid;
    uvec2 cell;
    uvec2 atlas;
    uvec4 lines;
    uvec4 cursor;
    uvec2 cursor_colors;
} push;

layout(location = 0) out vec2 glyph_uv;
layout(location = 1) out vec2 cell_uv;
layout(location = 2) flat out uint glyph_slot;
layout(location = 3) flat out uint flags;
layout(location = 4) flat out uint foreground;
layout(location = 5) flat out uint background;
layout(location = 6) flat out uint underline_color;
layout(location = 7) flat out uvec2 logical_cell;

const vec2 corners[6] = vec2[](
    vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
    vec2(0.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0)
);

void main() {
    uint logical_row = gl_InstanceIndex / push.grid.y;
    uint logical_col = gl_InstanceIndex % push.grid.y;
    uint physical = rows.values[logical_row] * push.grid.y + logical_col;
    uvec4 value = instances.values[physical];
    vec2 corner = corners[gl_VertexIndex];
    vec2 pixel = vec2(push.origin) +
        vec2(logical_col * push.cell.x, logical_row * push.cell.y) +
        corner * vec2(push.cell);
    vec2 ndc = vec2(
        pixel.x * 2.0 / float(push.surface.x) - 1.0,
        1.0 - pixel.y * 2.0 / float(push.surface.y)
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    uint packed = value.x;
    glyph_slot = packed & 0xffffu;
    flags = packed >> 16;
    foreground = value.y;
    background = value.z;
    underline_color = value.w;
    logical_cell = uvec2(logical_col, logical_row);
    cell_uv = corner;
    if (glyph_slot == 0xffffu) {
        glyph_uv = vec2(0.0);
    } else {
        uint atlas_col = glyph_slot % 20u;
        uint atlas_row = glyph_slot / 20u;
        glyph_uv = (vec2(atlas_col, atlas_row) + corner) /
            vec2(20.0, 19.0);
    }
}
