package howl_instance_native

// The embedder chooses/link-provides the artifact or embeds its exact export root.
// These module-owned declarations carry no host runtime/library policy.
Frame_Info :: struct {
    sequence, presentation_generation, revision, content_revision, terminal_revision: u64,
    command_count, content_command_count, upload_count, removal_count: u32,
    history_offset, history_count, history_row_base: u32,
    background_rgba: u32,
    surface_width, surface_height, cell_width, cell_height: u16,
    alternate_screen: u8,
    reserved: [7]u8,
}

@(default_calling_convention="c", link_prefix="hi_")
foreign {
    frame_close :: proc(owner: ^rawptr) ---
}
