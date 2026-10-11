#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(binding = 1) uniform sampler2D image_atlas;
layout(location = 0) out vec4 color;
void main() {
    color = texture(image_atlas, uv) * tint;
}
