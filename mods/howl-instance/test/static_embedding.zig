//! One explicit shared-library export invokes the unchanged real C proof.
extern fn howl_instance_static_c() c_int;
/// Runs the exact native lifecycle consumer from an embedder-owned shared library.
pub export fn howl_instance_static_shared() c_int {
    return howl_instance_static_c();
}
