package howl_render_native

// Versioned Render payload records. Backend textures and scheduling remain host-owned.

Resource_Info :: struct {
    resource: u64,
    generation: u64,
    pixel_count: u64,
    stride: u64,
    width: u16,
    height: u16,
    format: u8,
    _reserved: [3]u8,
}

Removal_Info :: struct {
    resource: u64,
    generation: u64,
}

Command_Info :: struct {
    resource: u64,
    generation: u64,
    color_rgba: u32,
    destination_x: i32,
    destination_y: i32,
    clip_x: i32,
    clip_y: i32,
    destination_width: u16,
    destination_height: u16,
    clip_width: u16,
    clip_height: u16,
    source_x: u16,
    source_y: u16,
    source_width: u16,
    source_height: u16,
    resource_width: u16,
    resource_height: u16,
    tag: u8,
    format: u8,
    cursor_component: u8,
    _reserved: u8,
}
