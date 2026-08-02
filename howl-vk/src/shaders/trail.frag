#version 450

layout(push_constant) uniform TrailMask {
    vec4 cursor_rect;
};

layout(location = 1) in vec4 color;
layout(location = 0) out vec4 output_color;

void main() {
    float in_x = step(cursor_rect.x, gl_FragCoord.x) * step(gl_FragCoord.x, cursor_rect.z);
    float in_y = step(cursor_rect.y, gl_FragCoord.y) * step(gl_FragCoord.y, cursor_rect.w);
    float mask = 1.0 - in_x * in_y;
    output_color = vec4(color.rgb * mask, color.a * mask);
}
