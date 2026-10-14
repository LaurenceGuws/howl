//! One explicit shared-library export invokes the unchanged real C proof.
extern fn howl_render_static_c(c_int, [*c][*c]u8) c_int;
/// Runs the exact copied-font/frame consumer from an embedder-owned shared library.
pub export fn howl_render_static_shared(argc: c_int, argv: [*c][*c]u8) c_int {
    return howl_render_static_c(argc, argv);
}
