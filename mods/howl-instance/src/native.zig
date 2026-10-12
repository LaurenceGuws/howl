//! Optional Instance-owned native foreign boundary over the exact local owner.
//! No host clocks, waits, queues, wake sources or Server/codec imports.
const instance = @import("howl_instance");
/// VT-owned native vocabulary and copied semantic projection.
pub const vt = @import("howl_vt_native");
/// Artifact-owned C declarations.
pub const c = @import("instance_native_types");
/// Validation and canonical ordered-input failures used by C and Zig host adapters.
pub const InputError = instance.InputError || vt.Error;
/// Exact local composition; never interchangeable with a headless handle.
pub const Instance = instance.Instance;

/// Native named input conversion and canonical mutation share one implementation.
pub fn sendNamedKey(value: *Instance, key: u8, action: u8, mods: u8) InputError!void {
    try instance.input(value, try vt.namedInput(key, action, mods));
}
/// Native Unicode conversion rejects non-scalars before canonical mutation.
pub fn sendUnicodeKey(value: *Instance, scalar: u32, action: u8, mods: u8) InputError!void {
    try instance.input(value, try vt.unicodeInput(scalar, action, mods));
}
/// Native mouse conversion rejects unknown metadata before canonical mutation.
pub fn sendMouse(value: *Instance, kind: u8, button: u8, mods: u8, buttons: u8, row: i32, col: u16, pixels: u8, x: u32, y: u32) InputError!void {
    try instance.input(value, try vt.mouseInput(kind, button, mods, buttons, row, col, pixels, x, y));
}
/// Native focus conversion rejects unknown values before canonical mutation.
pub fn sendFocus(value: *Instance, focus: u8) InputError!void {
    try instance.input(value, try vt.focusInput(focus));
}
