#version 450

layout(set = 0, binding = 0) uniform sampler2D atlas;
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 output_color;

void main() {
    output_color = vec4(color.rgb, color.a * texture(atlas, uv).r);
}
