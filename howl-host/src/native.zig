//! Imports the single concrete Linux Wayland, EGL, GLES, and xkb C namespace.

/// Shares one concrete C type identity across the window and render owners.
pub const c = @cImport({
    // Glibc fortify's variadic open wrappers are compiler builtins rather than
    // callable C declarations; this namespace uses fcntl but never open.
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("poll.h");
    @cInclude("pty.h");
    @cInclude("signal.h");
    @cInclude("stdint.h");
    @cInclude("sys/eventfd.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/timerfd.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-keysyms.h");
    @cInclude("xdg-shell-client-protocol.h");
});
